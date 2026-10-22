class_name Ministry
extends Node
## The Ministry gives the sandbox direction beyond grant goals: one short
## contract at a time, offered as an in-tray memo; a review at the end of
## each season; and inspectors who come to check the prison against the
## grade it claims. Never anything worse than a capped grade, and a missed
## contract costs money only under Full red tape. Shared by any game: the
## game says how to measure things through the callables.

signal changed
signal contract_ended(def: ContractDef, success: bool)
signal reviewed(average: float)
signal inspection_booked(visit: Inspection)
signal inspection_done(visit: Inspection)

## Days between offers while no contract runs.
const OFFER_EVERY := 7
## Days an offer waits in the in-tray.
const OFFER_DAYS := 3
## A season averaging this many stars or more earns a bigger grant next
## season (and an inspector, to earn a fifth star); below REVIEW_BAD, an
## inspector comes to see what's wrong.
const REVIEW_GOOD := 4.0
const REVIEW_BAD := 2.5
const GOOD_BONUS := 0.05
## Days' notice of an inspection, and the extra with the Inspection prep
## card (which also gives notice of surprise visits).
const NOTICE_DAYS := 3
const PREP_DAYS := 2
## Days a passed inspection lets a fifth star show.
const CEILING_DAYS := 30
const INSPECT_HOUR := 10
const INSPECT_MINUTES := 120.0
## Lobbying makes targets this much easier.
const LOBBY_EASE := 0.8
## Failed checks listed as fixes, at most.
const FIXES := 3
const OFF := 0
const FULL := 2
const MEASURES: Array[String] = ["Safety", "Wellbeing", "Reform", "Money"]

## A booked or finished visit.
class Inspection:
	var day := 0
	var announced := true
	## &"review" (a poor season), &"claim" (a good one, to earn a fifth
	## star).
	var reason: StringName
	var started := false
	var done := false
	var passed := false
	## Check id -> [passed, words].
	var results: Dictionary = {}
	var fixes: Array[StringName] = []

	func to_data() -> Dictionary:
		return {"day": day, "announced": announced, "reason": String(reason), "started": started, "done": done,
				"passed": passed, "results": results.duplicate(true), "fixes": fixes.map(func(f: StringName) -> String: return String(f))}

	static func from_data(data: Dictionary) -> Inspection:
		var out := Inspection.new()
		out.day = data.get("day", 0)
		out.announced = data.get("announced", true)
		out.reason = StringName(data.get("reason", ""))
		out.started = data.get("started", false)
		out.done = data.get("done", false)
		out.passed = data.get("passed", false)
		out.results = data.get("results", {})
		for fix: String in data.get("fixes", []):
			out.fixes.append(StringName(fix))
		return out

var enabled := true
var contracts: Array[ContractDef] = []
var inspection: InspectionDef
var in_tray: InTray:
	set(value):
		in_tray = value
		in_tray.lookups.append(_memo)
		in_tray.answered.connect(_on_answered)
var calendar: Calendar:
	set(value):
		calendar = value
		calendar.season_changed.connect(func(_def: SeasonDef) -> void: review())
var clock: GameClock:
	set(value):
		clock = value
		clock.day_changed.connect(func(_day: int) -> void: midnight())
		clock.hour_changed.connect(func(hour: int) -> void:
			if hour == INSPECT_HOUR:
				start_inspection())
		clock.minute_passed.connect(func(_minute: int) -> void: _walk())

## () -> int: the grade now, 1 to 5.
var grade: Callable
## (goal: GoalDef) -> float: where a contract's measure stands; for a
## counted goal, the running total.
var value_of: Callable
## (check: InspectionCheckDef, inspector: Object) -> [value: float,
## words: String], such as [0.7, "meals 70% good"].
var measure: Callable
## () -> int: the Red tape setting, 0 Off, 1 Light, 2 Full.
var red_tape: Callable
## (flag: StringName) -> bool: a research flag.
var has_flag: Callable
## (id: StringName) -> bool: a research card done.
var has_card: Callable
## (amount: int, line: String) -> void
var pay: Callable
## (counter: StringName) -> void, for research reveals.
var count: Callable
## (event: StringName) -> void, for the paper.
var report: Callable
## () -> Object: the inspector arriving, or null to look round unseen.
var arrive: Callable
## (inspector: Object, words: String) -> void: what they're doing.
var describe: Callable
## (inspector: Object) -> void: sends them home.
var leave: Callable

var running: ContractDef
var started_day := 0
var base := 0.0
var held := 0
var last_offer := -OFFER_EVERY
var season_sum := 0.0
var season_nights := 0
var last_average := 0.0
## Added to the grant scale this season after a good review.
var bonus := 0.0
## The measure counting double this year (Long-term plan), or "".
var focus := ""
var booked: Inspection
var last: Inspection
## The day a passed inspection stops letting a fifth star show.
var ceiling_until := 0
## The grade held while fixes are open; 0 for none.
var cap := 0
var history: Array[String] = []

var _inspector: Object
var _rng := RandomNumberGenerator.new()


func inspections_on() -> bool:
	return enabled and (not red_tape.is_valid() or red_tape.call() != OFF)


## The highest grade the Ministry lets show: four stars until an inspector
## has passed the prison lately, and the grade held at a failed visit until
## the fixes are done.
func grade_limit() -> int:
	if not inspections_on():
		return 5
	var limit := 5 if _day() <= ceiling_until else 4
	return mini(limit, cap) if cap > 0 else limit


func grant_scale() -> float:
	return 1.0 + bonus if enabled else 1.0


## Where a contract's goal is set, eased by Lobbying.
func amount(def: ContractDef) -> float:
	var target := def.goal.amount
	if _flag(&"lobbying"):
		target = target / LOBBY_EASE if def.at_most else target * LOBBY_EASE
	return floorf(target) if def.at_most else ceilf(target)


## Where the running contract stands.
func progress() -> float:
	if running == null or not value_of.is_valid():
		return 0.0
	var now: float = value_of.call(running.goal)
	return now - base if running.goal.counted else now


func met() -> bool:
	if running == null:
		return false
	return progress() <= amount(running) if running.at_most else progress() >= amount(running)


func days_left() -> int:
	return started_day + running.days - _day() if running != null else 0


## "6 of 10, 18 days left" or "3 of 5 nights, 4 days left".
func contract_words() -> String:
	if running == null:
		return ""
	var left := "%d day%s left" % [days_left(), "" if days_left() == 1 else "s"]
	if running.goal.hold_days > 0:
		return "%d of %d nights, %s" % [held, running.goal.hold_days, left]
	if running.at_most:
		return "now %d (at most %d), %s" % [roundi(progress()), roundi(amount(running)), left]
	return "%d of %d, %s" % [roundi(progress()), roundi(amount(running)), left]


## Contracts the Ministry might offer now.
func offers() -> Array[ContractDef]:
	var now: int = grade.call() if grade.is_valid() else 3
	return contracts.filter(func(def: ContractDef) -> bool: return def.min_grade <= now and def != running)


## Puts an offer in the in-tray: two to choose from with Ministry liaison.
func offer() -> InTray.Card:
	var pool := offers()
	if pool.is_empty() or in_tray == null:
		return null
	pool.shuffle()
	var ids := pool.slice(0, 2 if _card(&"ministry-liaison") else 1).map(func(def: ContractDef) -> String: return String(def.id))
	last_offer = _day()
	var def := _memo(StringName("ministry_offer:" + ",".join(ids)))
	return in_tray.post_about(def, 0, "")


func take(def: ContractDef) -> void:
	running = def
	started_day = _day()
	held = 0
	base = value_of.call(def.goal) if def.goal.counted and value_of.is_valid() else 0.0
	_note("Took on a Ministry contract: %s." % def.title)


## Each midnight: the contract, the fixes, the season's grades and offers.
func midnight() -> void:
	if not enabled:
		return
	if grade.is_valid():
		season_sum += grade.call()
		season_nights += 1
	if running != null:
		var done := met()
		if running.goal.hold_days > 0:
			held = held + 1 if done else 0
			done = held >= running.goal.hold_days
		if done:
			_end(true)
		elif days_left() <= 0:
			_end(false)
	if cap > 0 and last != null:
		var open := last.fixes.filter(func(id: StringName) -> bool: return not _passes(_check(id), null)[0])
		if open.is_empty():
			cap = 0
			_note("The Ministry is satisfied: the inspector's fixes are done.")
	if running == null and _day() - last_offer >= OFFER_EVERY and not _offer_waiting():
		offer()
	changed.emit()


## The end of a season: the Ministry averages its nightly grades.
func review() -> void:
	if not enabled or season_nights == 0:
		return
	last_average = season_sum / season_nights
	season_sum = 0.0
	season_nights = 0
	bonus = GOOD_BONUS if last_average >= REVIEW_GOOD else 0.0
	var words := "Seasonal review: %.1f stars on average." % last_average
	if last_average >= REVIEW_GOOD:
		words += " A bigger grant this season."
	if inspections_on() and booked == null and (last_average < REVIEW_BAD or last_average >= REVIEW_GOOD):
		book(&"review" if last_average < REVIEW_BAD else &"claim")
		words += " An inspector will call."
	_note(words)
	if calendar != null and not calendar.seasons.is_empty() and calendar.season() == calendar.seasons[0] \
			and _flag(&"long_term_plan"):
		focus = ""
		in_tray.post_about(_memo(&"ministry_focus"), 0, "")
	reviewed.emit(last_average)
	changed.emit()


## Books an inspection: announced by letter some days ahead, or under
## Full red tape a surprise (with a little notice from Inspection prep).
func book(reason: StringName, day := -1) -> Inspection:
	var visit := Inspection.new()
	visit.reason = reason
	var surprise: bool = red_tape.is_valid() and red_tape.call() == FULL
	var notice := (PREP_DAYS if surprise else NOTICE_DAYS + PREP_DAYS) if _flag(&"inspection_prep") \
			else (0 if surprise else NOTICE_DAYS)
	visit.announced = notice > 0
	visit.day = day if day > 0 else _day() + (notice if notice > 0 else _rng.randi_range(1, NOTICE_DAYS))
	booked = visit
	if visit.announced and in_tray != null:
		in_tray.post_about(_memo(&"ministry_inspection"), 0, "day %d" % visit.day)
	inspection_booked.emit(visit)
	changed.emit()
	return visit


## The inspector arrives at 10:00 on the day and walks the prison.
func start_inspection() -> void:
	if booked == null or booked.started or booked.day != _day() or not inspections_on():
		return
	booked.started = true
	_inspector = arrive.call() if arrive.is_valid() else null
	if _inspector == null:
		while booked != null and booked.results.size() < inspection.checks.size():
			_check_next()
		_finish()
	changed.emit()


## The checks are spread over the visit, in order.
func _walk() -> void:
	if booked == null or not booked.started or booked.done:
		return
	var minutes := fmod(clock.total_minutes, 24.0 * 60.0) - INSPECT_HOUR * 60.0
	var due := ceili(minutes / INSPECT_MINUTES * inspection.checks.size())
	while booked.results.size() < mini(due, inspection.checks.size()):
		_check_next()
	if minutes >= INSPECT_MINUTES:
		_finish()


func _check_next() -> void:
	var check := inspection.checks[booked.results.size()]
	var result := _passes(check, _inspector)
	booked.results[String(check.id)] = result
	if _inspector != null and describe.is_valid():
		describe.call(_inspector, "Checking %s: %s" % [check.words, _result_words(result)])


## Pass all but one (all but two with Open books) to pass.
func _finish() -> void:
	var visit := booked
	if visit == null or visit.done:
		return
	visit.done = true
	var failed: Array[StringName] = []
	for check in inspection.checks:
		if not (visit.results.get(String(check.id), [true])[0] as bool):
			failed.append(check.id)
	var allowed := inspection.allowed_fails + (1 if _flag(&"open_books") else 0)
	visit.passed = failed.size() <= allowed
	if visit.passed:
		ceiling_until = _day() + CEILING_DAYS
		cap = 0
		visit.fixes.clear()
		if report.is_valid():
			report.call(&"inspection_good")
	else:
		cap = grade.call() if grade.is_valid() else 3
		visit.fixes.assign(failed.slice(0, FIXES))
		if report.is_valid():
			report.call(&"inspection_bad")
	if count.is_valid():
		count.call(&"inspection")
	if _inspector != null and leave.is_valid():
		leave.call(_inspector)
	_inspector = null
	last = visit
	booked = null
	_note(report_words(visit))
	inspection_done.emit(visit)
	changed.emit()


## "The inspector passed the prison: …" with each check.
func report_words(visit: Inspection) -> String:
	var lines := PackedStringArray()
	lines.append("The inspector passed the prison; a fifth star can show for %d days." % CEILING_DAYS if visit.passed
			else "The inspector failed the prison; the grade is held at %d★ until the fixes are done." % cap)
	for check in inspection.checks:
		var result: Array = visit.results.get(String(check.id), [])
		if not result.is_empty():
			lines.append("%s: %s" % [check.words.capitalize(), _result_words(result)])
	return "\n".join(lines)


## Lines for the office: the contract, the review, the inspector.
func words() -> PackedStringArray:
	var lines := PackedStringArray()
	if not enabled:
		return lines
	if running != null:
		lines.append("Contract: %s (%s). %s on completion." % [running.title, contract_words(),
				Ledger.text(running.reward)])
	else:
		lines.append("No contract running. The Ministry writes again in %d days." % maxi(OFFER_EVERY - (_day() - last_offer), 1)
				if not _offer_waiting() else "A contract offer is waiting in the in-tray.")
	if calendar != null and calendar.enabled:
		var left := calendar.length - calendar.day_of_season() + 1
		lines.append("Seasonal review in %d day%s, %.1f stars on average so far." % [left, "" if left == 1 else "s",
				season_sum / season_nights if season_nights > 0 else 0.0])
	if not focus.is_empty():
		lines.append("This year's focus: %s counts double." % focus)
	if not inspections_on():
		return lines
	if booked != null:
		lines.append("An inspector calls on day %d at %02d:00." % [booked.day, INSPECT_HOUR] if booked.announced
				else "An inspector may call any day.")
	if _day() <= ceiling_until:
		lines.append("Passed inspection: a fifth star can show until day %d." % ceiling_until)
	elif cap == 0:
		lines.append("A fifth star needs a passed inspection.")
	if cap > 0 and last != null:
		lines.append("Held at %d★ until these are fixed:" % cap)
		for id in last.fixes:
			var check := _check(id)
			var now := _passes(check, null)
			lines.append("%s %s: %s" % ["☑" if now[0] else "☐", check.words.capitalize(), now[1]])
	return lines


func capture() -> Dictionary:
	return {"running": String(running.id) if running != null else "", "started_day": started_day, "base": base,
			"held": held, "last_offer": last_offer, "season_sum": season_sum, "season_nights": season_nights,
			"last_average": last_average, "bonus": bonus, "focus": focus, "ceiling_until": ceiling_until, "cap": cap,
			"booked": booked.to_data() if booked != null else {}, "last": last.to_data() if last != null else {},
			"history": history.duplicate()}


func restore(data: Dictionary) -> void:
	running = _contract(StringName(data.get("running", "")))
	started_day = data.get("started_day", 0)
	base = data.get("base", 0.0)
	held = data.get("held", 0)
	last_offer = data.get("last_offer", -OFFER_EVERY)
	season_sum = data.get("season_sum", 0.0)
	season_nights = data.get("season_nights", 0)
	last_average = data.get("last_average", 0.0)
	bonus = data.get("bonus", 0.0)
	focus = data.get("focus", "")
	ceiling_until = data.get("ceiling_until", 0)
	cap = data.get("cap", 0)
	var saved: Dictionary = data.get("booked", {})
	booked = Inspection.from_data(saved) if not saved.is_empty() else null
	if booked != null and booked.started and not booked.done:
		# A visit cut short by the save: it starts again tomorrow.
		booked.started = false
		booked.results.clear()
		booked.day = _day() + 1
	saved = data.get("last", {})
	last = Inspection.from_data(saved) if not saved.is_empty() else null
	history.assign(data.get("history", []))
	changed.emit()


func _end(success: bool) -> void:
	var def := running
	running = null
	last_offer = _day()
	if success:
		if pay.is_valid():
			pay.call(def.reward, "Ministry")
		if count.is_valid():
			count.call(&"contract_done")
		_note("Ministry contract done: %s. %s paid." % [def.title, Ledger.text(def.reward)])
	else:
		var fined: bool = def.penalty > 0 and red_tape.is_valid() and red_tape.call() == FULL
		if fined and pay.is_valid():
			pay.call(-def.penalty, "Ministry")
		_note("Ministry contract missed: %s.%s" % [def.title, " %s fine." % Ledger.text(def.penalty) if fined else ""])
	contract_ended.emit(def, success)


func _on_answered(card: InTray.Card, choice: TrayChoiceDef, _by: StringName) -> void:
	for tag in choice.tags:
		var text := String(tag)
		if text.begins_with("contract:") and running == null:
			var def := _contract(StringName(text.trim_prefix("contract:")))
			if def != null:
				take(def)
		elif text.begins_with("focus:"):
			focus = text.trim_prefix("focus:")
			if not focus.is_empty():
				_note("This year the Ministry will weigh %s double." % focus.to_lower())
	if String(card.def.id).begins_with("ministry_"):
		changed.emit()


## The Ministry's in-tray memos, made from their ids so saves find them.
func _memo(id: StringName) -> TrayCardDef:
	var text := String(id)
	var def: TrayCardDef
	if text.begins_with("ministry_offer:"):
		var choices: Array = []
		var titles := PackedStringArray()
		for contract_id in text.trim_prefix("ministry_offer:").split(","):
			var contract := _contract(StringName(contract_id))
			if contract == null:
				continue
			titles.append("%s (%d days, %s)" % [contract.title, contract.days, Ledger.text(contract.reward)])
			choices.append(TrayCardDef.choice("Take on: " + contract.title, [], [&"approve", StringName("contract:" + contract_id)],
					"Took on the Ministry's contract"))
		choices.append(TrayCardDef.choice("Not now", [], [&"decline"], "Turned the Ministry's contract down"))
		def = TrayCardDef.make(id, &"memo", &"", "A contract from the Ministry",
				"The Ministry offers: %s." % " or ".join(titles), choices, choices.size() - 1)
		def.deadline_days = OFFER_DAYS
	elif text == "ministry_focus":
		var choices: Array = [TrayCardDef.choice("Keep a balance", [], [&"focus:"], "No focus this year")]
		for name in MEASURES:
			choices.append(TrayCardDef.choice(name, [], [StringName("focus:" + name)], "%s counts double this year" % name))
		def = TrayCardDef.make(id, &"memo", &"", "Long-term plan",
				"A new year: pick a focus, and the Ministry weighs that score double for grants.", choices, 0)
		def.deadline_days = OFFER_DAYS
	elif text == "ministry_inspection":
		def = TrayCardDef.make(id, &"memo", &"", "An inspector is coming",
				"The Ministry's inspector visits on {who} at %02d:00 to check the rooms, cleaning, meals, staffing, health care and safety." % INSPECT_HOUR,
				[TrayCardDef.choice("Noted", [], [&"approve"], "Got ready for the inspector")])
		def.deadline_days = NOTICE_DAYS
	else:
		return null
	def.weight = 0.0
	return def


func _offer_waiting() -> bool:
	return in_tray != null and in_tray.cards.any(func(c: InTray.Card) -> bool: return String(c.def.id).begins_with("ministry_offer:"))


func _passes(check: InspectionCheckDef, inspector: Object) -> Array:
	if check == null:
		return [true, ""]
	var got: Array = measure.call(check, inspector) if measure.is_valid() else [check.pass_line, ""]
	if not check.passed_by_flag.is_empty() and _flag(check.passed_by_flag):
		return [true, got[1]]
	var value: float = got[0]
	return [value <= check.pass_line if check.at_most else value >= check.pass_line, got[1]]


static func _result_words(result: Array) -> String:
	return "%s (%s)" % [result[1], "pass" if result[0] else "fail"]


func _check(id: StringName) -> InspectionCheckDef:
	for check in inspection.checks:
		if check.id == id:
			return check
	return null


func _contract(id: StringName) -> ContractDef:
	for def in contracts:
		if def.id == id:
			return def
	return null


func _flag(flag: StringName) -> bool:
	return has_flag.is_valid() and has_flag.call(flag)


func _card(id: StringName) -> bool:
	return has_card.is_valid() and has_card.call(id)


func _note(words: String) -> void:
	history.append(words)
	if history.size() > 6:
		history.pop_front()
	if in_tray != null:
		in_tray.note(words.get_slice("\n", 0))


func _day() -> int:
	return clock.day() if clock != null else 1
