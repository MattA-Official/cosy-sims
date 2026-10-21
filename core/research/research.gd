class_name Research
extends Node
## The research board in play. Each wedge has a slot: the warden's office,
## and each department whose head is hired, plus one more for a deputy. A
## slot's card is a DeskItem of kind research on its owner's pile, worked
## after paperwork and in-tray cards; its know-how is paid in full when it
## starts. Most cards start face down and turn up from how the prison is
## run (see RevealDef), by word of mouth WORD_OF_MOUTH_DAYS after
## everything they need is done, as a new head's pet project, or after a
## conference.
##
## Until a department has a head, the warden may work its cards, at half
## speed outside the office and Administration. Hire cards go through
## Heads: starting one puts the hire on the warden's desk, and it's done
## when the applicants arrive.
##
## Joint cards (two kinds of know-how) need the heads of both, the
## Management meeting card and a meeting room: they sit in both heads'
## slots and move on only at the morning meeting, while both attend.
## Policy cards are tried in one wing for TRIAL_DAYS before they're rolled
## out, adjusted or shelved. A wedge with nothing left offers a repeatable
## refinement.

signal changed
signal revealed(card: ResearchCardDef, why: String)
signal started(card: ResearchCardDef, owner: int)
signal finished(card: ResearchCardDef, owner: int)
## A wing trial has run its days: what it found, in words.
signal trial_report(card: ResearchCardDef, words: String)

enum State { HIDDEN, FACE_UP, RESEARCHING, PAUSED, TRIAL, DONE, LOCKED_OUT }
enum Mode { FULL, WARDEN_ONLY, OFF }

const OFFICE := &"office"
const ADMIN := &"admin"
## A slot's deputy slot is its id with this on the end.
const DEPUTY := "+"
const QUEUE := 3
const WORD_OF_MOUTH_DAYS := 7
const WARDEN_AWAY_SPEED := 0.5
## Star grade needed by tier, from tier 4 up.
const GATES := {4: 3, 5: 3, 6: 4}
## Know-how in hand when a game starts, so the first hire needn't wait.
const START_KNOWHOW := {&"admin": 30.0}
## Lean from an adopted lean card, and from a head's trait while employed.
const CARD_LEAN := 15.0
const HEAD_LEAN := 5.0
const LEAN_REVEAL := 30.0
const LEAN_FADE_DAYS := 10
## Wing trials: how long, how long the report waits before it rolls out
## (the in-tray card lapses a day sooner), and the know-how back when one
## is shelved.
const TRIAL_DAYS := 3
const TRIAL_GRACE := 3
const SHELVE_REFUND := 0.5
## The morning meeting for joint cards.
const MEETING_HOUR := 10
const MEETING_MINUTES := 120.0
const MEETING_ROOM := &"meeting"
const MEETING_SEAT := &"chair"
const MEETING_JOB := &"meeting"
## Budgets: so much faster per £100 a day, up to BUDGET_MOST.
const BUDGET_STEP := 0.1
const BUDGET_MOST := 1.5
const CONFERENCE_DAYS := 2
const CONFERENCE_COST := 200
const CONFERENCE_CARDS := 2
## A refinement costs this much more each time.
const REFINE_GROWTH := 1.5
## Deputies' roles, by the slot they work: "deputy_warden", "deputy_security".
const DEPUTY_ROLE := "deputy_%s"
const DEPUTY_LEVEL := 3

## One card's progress.
class CardState:
	var state := State.HIDDEN
	## 0 to 1 of the card's desk time, kept while paused.
	var progress := 0.0
	## Why it turned up, such as "First escape".
	var revealed_by := ""
	## The day everything it needs was done, for word of mouth; 0 for not yet.
	var ready_day := 0
	## Switching to a pick-one partner costs double.
	var double := false
	## The slot working it, and a joint card's second slot.
	var slot: StringName = &""
	var partner: StringName = &""

var board: ResearchBoardDef
var mode := Mode.FULL
## Card id -> CardState.
var states: Dictionary[StringName, CardState] = {}
## A wedge's first slot -> card ids queued after the one being worked.
var queues: Dictionary[StringName, Array] = {}
## Add-ons owned.
var addons: Array[StringName] = []
## Character: -100 caring to +100 strict, rebuilt at midnight.
var lean := 0.0
## In-tray shifts to the lean, each [amount, day], fading over LEAN_FADE_DAYS.
var lean_shifts: Array = []
## Department -> £ a day spent on its research (Department budgets).
var budget: Dictionary[StringName, int] = {}
## Department -> refinements done.
var refinements: Dictionary[StringName, int] = {}
## Card id -> {rooms: [[level, x, z]...], start_day, report_day, wing: [mood
## sum, samples, fights, finds], rest: [...]}.
var trials: Dictionary[StringName, Dictionary] = {}
## Roster id -> [department, day back].
var conferences: Dictionary[int, Array] = {}
## Roster id -> the card turned up as their pet project.
var pet_projects: Dictionary[int, StringName] = {}
## What happened on the board today, and yesterday's for the morning
## report: "Ada Moss finished Cell searches."
var news: Array[String] = []
var yesterday_news: Array[String] = []

var knowhow: Knowhow
var counters: Counters
var heads: Heads
var roster: StaffRoster
var desk_work: DeskWork
var modifiers: Modifiers
var building: Building
var jobs: JobBoard
## For wings: whose bed is where. Optional.
var people: People
## () -> int: last midnight's star grade.
var grade: Callable
## (setting id) -> Variant: a setting's value, for SETTING reveals.
var setting: Callable
## (amount, line) -> void: spends money, for budgets and conferences.
var pay: Callable
var clock: GameClock:
	set(value):
		clock = value
		clock.day_changed.connect(func(_day: int) -> void: nightly())
		clock.hour_changed.connect(func(hour: int) -> void:
			if hour == MEETING_HOUR:
				hold_meetings())

var _department_of_hire: Dictionary[StringName, StringName] = {}
## Joint card id -> roster ids at today's meeting so far.
var _attended: Dictionary[StringName, Array] = {}
## Card id -> [progress last night, share done a day], for "about N days".
var _pace: Dictionary[StringName, Array] = {}


func start() -> void:
	for department: StringName in board.hire_cards:
		_department_of_hire[board.hire_cards[department]] = department
	for def in board.cards + board.refinements:
		if not states.has(def.id):
			states[def.id] = CardState.new()
	var root := states.get(&"warden-s-office") as CardState
	if root != null:
		root.state = State.DONE
	if counters != null:
		counters.counted.connect(func(_id: StringName, _total: int, _n: int) -> void: check_reveals())
	if desk_work != null:
		desk_work.finished.connect(_on_desk_finished)
	if heads != null:
		heads.applicants_ready.connect(_on_applicants)
		heads.hired.connect(_on_hired)
	if roster != null:
		roster.changed.connect(_on_roster_changed)
		roster.levelled_up.connect(func(_r: StaffRoster.Record) -> void: check_reveals())
	if building != null:
		building.changed.connect(check_reveals)
	set_mode(mode)
	check_reveals()
	# After the cards face up from the start, so only new ones are news.
	revealed.connect(func(def: ResearchCardDef, why: String) -> void:
		news.append("A new idea: %s (%s)." % [def.display_name, why.to_lower() if why != "Word of mouth" else "word of mouth"]))
	finished.connect(func(def: ResearchCardDef, owner: int) -> void: news.append(finished_words(def, owner)))


## "Ada Moss finished Cell searches."
func finished_words(def: ResearchCardDef, owner: int) -> String:
	var record := _record(owner)
	return "%s finished %s." % [record.name if record != null else "The warden", def.display_name]


## Lines for the morning report: yesterday's news and the character.
func report_lines() -> Array[String]:
	var out: Array[String] = yesterday_news.duplicate()
	if mode != Mode.OFF:
		out.append("Character: %s." % lean_words().to_lower())
	return out


## A fresh game's know-how.
func give_start_knowhow() -> void:
	for id: StringName in START_KNOWHOW:
		knowhow.add(id, START_KNOWHOW[id])


## Full, Warden only, or Off: every card done but the pick-one pairs,
## which become policies to choose between.
func set_mode(value: Mode) -> void:
	mode = value
	if knowhow != null:
		knowhow.earning = mode != Mode.OFF
	if mode == Mode.OFF:
		for def in board.cards:
			if def.pair == &"" and _addon_owned(def):
				_finish(def, 0, false)
	changed.emit()


## With research Off, picks one side of a pick-one pair.
func choose_policy(def: ResearchCardDef) -> void:
	if mode == Mode.OFF and def.pair != &"":
		_finish(def, 0, false)


func card(id: StringName) -> ResearchCardDef:
	return board.card(id)


func state_of(id: StringName) -> State:
	var s: CardState = states.get(id)
	return s.state if s != null else State.HIDDEN


func is_done(id: StringName) -> bool:
	return state_of(id) == State.DONE


func is_shown(def: ResearchCardDef) -> bool:
	return _addon_owned(def)


func is_hire(def: ResearchCardDef) -> bool:
	return _department_of_hire.has(def.id)


## Whether a card can be started now.
func available(def: ResearchCardDef) -> bool:
	return why_not(def).is_empty()


## Why a card can't start now, or "".
func why_not(def: ResearchCardDef) -> String:
	var s: CardState = states[def.id]
	if not _addon_owned(def):
		return "Comes with an add-on."
	match s.state:
		State.HIDDEN:
			return "Not turned up yet" + (": %s." % hint_words(def) if def.reveal != null else ".")
		State.RESEARCHING, State.PAUSED:
			return "Already under way."
		State.TRIAL:
			return "Being tried in a wing."
		State.DONE:
			return "Done."
	if mode == Mode.OFF:
		return "Research is off."
	var met := def.requires.filter(_counts_as_done).size()
	if met < def.needed():
		return "Needs %s first." % _needs_words(def)
	var stars: int = GATES.get(def.tier, 0)
	if stars > 0 and _grade() < stars:
		return "Needs a %d-star grade (now %d)." % [stars, _grade()]
	if def.pair != &"" and state_of(def.pair) in [State.RESEARCHING, State.TRIAL, State.PAUSED]:
		return "Locked out: %s is under way." % card(def.pair).display_name
	if not knowhow.can_pay(cost(def)):
		return "Not enough know-how."
	if is_hire(def):
		var department := heads.find(_department_of_hire[def.id]) if heads != null else null
		if department == null:
			return "No such department."
		if mode == Mode.WARDEN_ONLY:
			return "With research Warden only, hire heads from the Heads page (H)."
		return heads.why_not(department)
	var slot := free_slot(def)
	if slot == &"":
		var first := home_slots(def)[0]
		return "Needs a warden." if slot_owner(first) == 0 else "%s is busy; queue it instead." % slot_name(first)
	if is_joint(def):
		if not has_flag(&"joint_cards"):
			return "A joint card: needs the Management meeting card."
		if not _built([String(MEETING_ROOM)]):
			return "A joint card: needs a meeting room."
		var partner := partner_slot(def, slot)
		if partner != &"" and is_busy(partner):
			return "%s is busy." % slot_name(partner)
	return ""


## Know-how a card costs now: double when switching to a pick-one partner,
## and more for each refinement already done.
func cost(def: ResearchCardDef) -> Dictionary:
	var out := {}
	var times := (2.0 if states[def.id].double else 1.0) * _refine_scale(def)
	for id: StringName in def.knowhow:
		out[id] = roundi(def.knowhow[id] * times)
	return out


## Desk minutes a card takes in all.
func minutes(def: ResearchCardDef) -> float:
	return def.desk_minutes * (2.0 if states[def.id].double else 1.0) * _refine_scale(def)


## Joint: two kinds of know-how worked by two people, under Full
## research. The warden stands in for any wedge without a head, so a card
## both of whose wedges are the warden's is theirs alone.
func is_joint(def: ResearchCardDef) -> bool:
	if mode != Mode.FULL or def.knowhow.size() < 2 or is_hire(def) or def.repeatable:
		return false
	var kinds := def.kinds()
	return _kind_base(kinds[0]) != _kind_base(kinds[1])


## The first slot that may work a card.
func slot_of(def: ResearchCardDef) -> StringName:
	return home_slots(def)[0]


## The slots that may work a card: its wedge's head and deputy, or the
## warden and deputy warden until the wedge has a head.
func home_slots(def: ResearchCardDef) -> Array[StringName]:
	var base := OFFICE
	if mode != Mode.WARDEN_ONLY and def.department != OFFICE and not is_hire(def) \
			and _head_record(def.department) != null:
		base = def.department
	if is_hire(def):
		return [OFFICE]
	return [base, StringName(String(base) + DEPUTY)]


## The first of a card's home slots with someone in it and nothing on, or &"".
func free_slot(def: ResearchCardDef) -> StringName:
	for slot in home_slots(def):
		if slot_owner(slot) != 0 and not is_busy(slot):
			return slot
	return &""


## The second slot a joint card needs, worked from `slot`, or &"".
func partner_slot(def: ResearchCardDef, slot: StringName) -> StringName:
	for kind: StringName in def.kinds().slice(0, 2):
		var base := _kind_base(kind)
		if base != _base(slot):
			return base
	return &""


## The roster id of whoever works a slot, or 0.
func slot_owner(slot: StringName) -> int:
	if slot == &"":
		return 0
	var record: StaffRoster.Record = null
	if String(slot).ends_with(DEPUTY):
		record = _role_record(deputy_role(_base(slot)))
	elif slot == OFFICE:
		record = heads.warden() if heads != null else null
	else:
		record = _head_record(slot)
	return record.id if record != null else 0


func deputy_role(base: StringName) -> StringName:
	return StringName(DEPUTY_ROLE % ("warden" if base == OFFICE else String(base)))


## The slots there are now.
func slots() -> Array[StringName]:
	var bases: Array[StringName] = [OFFICE]
	if mode != Mode.WARDEN_ONLY and heads != null:
		for department in heads.departments:
			if heads.head(department) != null:
				bases.append(department.id)
	var out: Array[StringName] = []
	for base in bases:
		out.append(base)
		var deputy := StringName(String(base) + DEPUTY)
		if slot_owner(deputy) != 0:
			out.append(deputy)
	return out


## The card a slot is working, or null.
func slot_card(slot: StringName) -> ResearchCardDef:
	for id: StringName in states:
		var s: CardState = states[id]
		if s.state == State.RESEARCHING and (s.slot == slot or s.partner == slot) and not is_hire(card(id)):
			return card(id)
	if slot == OFFICE and heads != null and heads.hiring() != null:
		return card(board.hire_cards.get(heads.hiring().id, &""))
	return null


func is_busy(slot: StringName) -> bool:
	return slot_card(slot) != null


func slot_name(slot: StringName) -> String:
	var record := _record(slot_owner(slot))
	if record != null:
		return record.name
	return "The warden" if slot == OFFICE else String(slot).capitalize()


## Starts a card now, paying its know-how. Returns whether it started.
func begin(def: ResearchCardDef) -> bool:
	if not available(def):
		return false
	knowhow.pay(cost(def))
	var s: CardState = states[def.id]
	s.state = State.RESEARCHING
	if def.pair != &"" and state_of(def.pair) == State.FACE_UP:
		states[def.pair].state = State.LOCKED_OUT
	if is_hire(def):
		s.slot = OFFICE
		heads.start_hire(heads.find(_department_of_hire[def.id]))
	else:
		s.slot = free_slot(def)
		s.partner = partner_slot(def, s.slot) if is_joint(def) else &""
		if s.partner == &"":
			_put_on_desk(def)
	unqueue(def, false)
	started.emit(def, slot_owner(s.slot))
	changed.emit()
	return true


## Queues a card after what its wedge is working, up to QUEUE. Starts it
## at once if a slot is free.
func queue(def: ResearchCardDef) -> bool:
	if available(def):
		return begin(def)
	var line: Array = queues.get_or_add(home_slots(def)[0], [])
	if line.size() >= QUEUE or line.has(def.id) or states[def.id].state != State.FACE_UP:
		return false
	line.append(def.id)
	changed.emit()
	return true


func unqueue(def: ResearchCardDef, tell := true) -> void:
	for slot: StringName in queues:
		(queues[slot] as Array).erase(def.id)
	if tell:
		changed.emit()


## Stops a card before it's done: all the know-how back, progress kept.
func cancel(def: ResearchCardDef) -> void:
	var s: CardState = states[def.id]
	if s.state != State.RESEARCHING and s.state != State.PAUSED:
		return
	if is_hire(def):
		heads.cancel_hire()
	else:
		s.progress = progress(def)
		desk_work.remove(&"research", _ref(def))
	knowhow.refund(cost(def))
	s.state = State.FACE_UP
	var slot := s.slot
	s.slot = &""
	s.partner = &""
	if def.pair != &"" and state_of(def.pair) == State.LOCKED_OUT and not is_done(def.pair) and not states[def.pair].double:
		states[def.pair].state = State.FACE_UP
	changed.emit()
	_next_in(slot)


## How far along a card is, 0 to 1.
func progress(def: ResearchCardDef) -> float:
	var s: CardState = states[def.id]
	if s.state == State.DONE:
		return 1.0
	if is_hire(def):
		var hire := heads.hire_card() if heads != null else null
		return hire.done_share() if hire != null and StringName(hire.ref) == _department_of_hire[def.id] else 0.0
	for item in _desk_items(def):
		return s.progress + item.done_share() * (1.0 - s.progress)
	return s.progress


## Research speed beyond what the desk already gives (level, traits and
## office): morale, the warden away from home, budgets and modifiers.
func speed(def: ResearchCardDef, owner: int) -> float:
	var out := 1.0 + (modifiers.value(&"research_speed") if modifiers != null else 0.0)
	var record := _record(owner)
	if record != null:
		out *= 0.8 if record.morale < 30.0 else 1.1 if record.morale > 70.0 else 1.0
		var warden := heads.warden() if heads != null else null
		if warden != null and record.id == warden.id and mode != Mode.WARDEN_ONLY \
				and def.department != OFFICE and def.department != ADMIN:
			out *= WARDEN_AWAY_SPEED
	if has_flag(&"department_budgets"):
		out *= minf(BUDGET_MOST, 1.0 + BUDGET_STEP * budget.get(def.department, 0) / 100.0)
	return out


## "Researching Cell searches: 62%" for an owner, with any pet project,
## or "".
func owner_line(owner: int) -> String:
	var lines: Array[String] = []
	for slot in slots():
		if slot_owner(slot) == owner:
			var def := slot_card(slot)
			if def != null:
				var s: CardState = states[def.id]
				var with := ""
				if s.partner != &"":
					var other := s.partner if s.slot == slot else s.slot
					with = " with %s (meetings at %d:00)" % [slot_name(other), MEETING_HOUR]
				var days := days_left(def)
				lines.append("Researching %s%s: %d%%%s" % [def.display_name, with, roundi(progress(def) * 100.0),
						"" if days <= 0 else ", about %d day%s left" % [days, "" if days == 1 else "s"]])
				var away := away_line(s)
				if away != "":
					lines.append(away)
	if pet_projects.has(owner):
		lines.append("Pet project: %s" % card(pet_projects[owner]).display_name)
	return "\n".join(lines)


## Days a card has left at the pace of the last few days, or 0 when
## there's no pace yet.
func days_left(def: ResearchCardDef) -> int:
	var pace: Array = _pace.get(def.id, [])
	if pace.size() < 2 or pace[1] <= 0.0:
		return 0
	return maxi(1, ceili((1.0 - progress(def)) / pace[1]))


func _note_pace() -> void:
	for id: StringName in states:
		if states[id].state != State.RESEARCHING:
			_pace.erase(id)
			continue
		var now := progress(card(id))
		var pace: Array = _pace.get(id, [])
		if pace.is_empty():
			_pace[id] = [now]
		else:
			var day := now - float(pace[0])
			var was: float = pace[1] if pace.size() > 1 else day
			# Lean on the last day, but keep a little of the days before.
			_pace[id] = [now, lerpf(was, day, 0.6)]


## "Paused: Ann Lee is off sick until day 5." when someone a card needs
## is away, or "".
func away_line(s: CardState) -> String:
	for slot in [s.slot, s.partner]:
		var record := _record(slot_owner(slot)) if slot != &"" else null
		if record != null and record.off_until >= _day():
			return "Paused: %s is %s until day %d." % [record.name, record.away if record.away != "" else "away", record.off_until + 1]
	return ""


## Fits desk time left to today's speed (morale, budgets, modifiers), so a
## change shows on cards already started.
func respeed() -> void:
	for id: StringName in states:
		var s: CardState = states[id]
		if s.state != State.RESEARCHING:
			continue
		var def := card(id)
		for item in _desk_items(def):
			var share := item.done_share()
			var total := maxf(minutes(def) * (1.0 - s.progress) / speed(def, slot_owner(s.slot)), 1.0)
			item.total = total
			item.minutes = total * (1.0 - share)


## Puts cards whose slot came back (a head hired again) back on a desk.
func resume() -> void:
	for id: StringName in states:
		var s: CardState = states[id]
		if s.state != State.PAUSED:
			continue
		var def := card(id)
		# A wedge's card waits for its own head, not the warden.
		var home := mode == Mode.WARDEN_ONLY or def.department == OFFICE or _head_record(def.department) != null
		var slot := free_slot(def)
		if home and slot != &"":
			s.state = State.RESEARCHING
			s.slot = slot
			s.partner = partner_slot(def, slot) if is_joint(def) else &""
			if s.partner == &"":
				_put_on_desk(def)
	for slot in slots():
		_next_in(slot)
	changed.emit()


## Turns face up every card whose reveal has happened, and refinements for
## wedges with nothing left.
func check_reveals() -> void:
	for def in board.cards:
		var s: CardState = states[def.id]
		if s.state != State.HIDDEN or not _addon_owned(def):
			continue
		if def.reveal == null:
			reveal(def, "From the start")
			continue
		var why := _revealed_now(def.reveal)
		if not why.is_empty():
			reveal(def, why)
	for def in board.refinements:
		if states[def.id].state == State.HIDDEN and _wedge_finished(def.department):
			reveal(def, "Every card in the wedge is done")


func reveal(def: ResearchCardDef, why: String) -> void:
	var s: CardState = states[def.id]
	if s.state != State.HIDDEN:
		return
	s.state = State.LOCKED_OUT if def.pair != &"" and is_done(def.pair) else State.FACE_UP
	s.revealed_by = why
	if mode == Mode.OFF and def.pair == &"":
		_finish(def, 0, false)
	revealed.emit(def, why)
	changed.emit()


## Turns up the lowest-tier hidden cards in a wedge, those nearest to
## ready first, such as after a conference. Returns the cards.
func reveal_in(department: StringName, count: int, why: String) -> Array[ResearchCardDef]:
	var hidden := board.cards.filter(func(def: ResearchCardDef) -> bool:
		return def.department == department and states[def.id].state == State.HIDDEN and _addon_owned(def))
	hidden.sort_custom(func(a: ResearchCardDef, b: ResearchCardDef) -> bool:
		var ma := a.needed() - a.requires.filter(is_done).size()
		var mb := b.needed() - b.requires.filter(is_done).size()
		return a.tier < b.tier or a.tier == b.tier and ma < mb)
	var out: Array[ResearchCardDef] = []
	for def: ResearchCardDef in hidden.slice(0, count):
		reveal(def, why)
		out.append(def)
	return out


## Midnight: budgets, conferences, trials, the character scale, word of
## mouth and grade reveals.
func nightly() -> void:
	var today := _day()
	yesterday_news = news
	news = []
	_note_pace()
	respeed()
	if has_flag(&"department_budgets") and pay.is_valid():
		var spend := 0
		for department: StringName in budget:
			spend += budget[department]
		if spend > 0:
			pay.call(spend, "Research budgets")
	for id: int in conferences.keys():
		var entry: Array = conferences[id]
		if today >= int(entry[1]):
			conferences.erase(id)
			var record := _record(id)
			reveal_in(entry[0], CONFERENCE_CARDS, "Conference: %s" % (record.name if record != null else "a head"))
	_trials_nightly()
	refresh_lean()
	for def in board.cards:
		var s: CardState = states[def.id]
		if s.state != State.HIDDEN:
			continue
		var all_done := not def.requires.is_empty() and def.requires.all(is_done)
		if not all_done:
			s.ready_day = 0
			continue
		if s.ready_day == 0:
			s.ready_day = today
		elif def.reveal != null and def.reveal.fallback and today - s.ready_day >= WORD_OF_MOUTH_DAYS:
			reveal(def, "Word of mouth")
	check_reveals()


# --- Joint cards and the morning meeting ------------------------------------

## Sends both heads of each joint card to the meeting room, if both are in
## and there are seats.
func hold_meetings() -> void:
	_attended.clear()
	if jobs == null or building == null:
		return
	var seats := _meeting_seats()
	for id: StringName in states:
		var s: CardState = states[id]
		if s.state != State.RESEARCHING or s.partner == &"":
			continue
		var a := _record(slot_owner(s.slot))
		var b := _record(slot_owner(s.partner))
		if a == null or b == null or a.person == null or b.person == null or seats.size() < 2:
			continue
		_attended[id] = []
		for record: StaffRoster.Record in [a, b]:
			var seat: Vector2i = seats.pop_front()
			var job := Job.new()
			job.kind = MEETING_JOB
			job.only_for = record.person
			job.any_time = true
			job.title = "Meeting: %s" % card(id).display_name
			job.priority = 4
			var sit := Job.at(Job.Do.WORK, seat.x, seat.y)
			sit.minutes = MEETING_MINUTES
			sit.doing = "In a meeting about %s" % card(id).display_name.to_lower()
			var who := record.id
			sit.finish = func(_stage: Job.Stage, _worker: Person) -> void: attend(id, who)
			job.stages = [sit]
			jobs.post(job)


## Someone sat through a meeting about a joint card; once both have, it
## moves on by a meeting's worth at their average speed.
func attend(id: StringName, owner: int) -> void:
	var s: CardState = states.get(id)
	if s == null or s.state != State.RESEARCHING:
		return
	var seen: Array = _attended.get_or_add(id, [])
	if not seen.has(owner):
		seen.append(owner)
	var a := slot_owner(s.slot)
	var b := slot_owner(s.partner)
	if not (seen.has(a) and seen.has(b)):
		return
	_attended.erase(id)
	var def := card(id)
	var pace := (speed(def, a) + speed(def, b)) / 2.0
	s.progress = minf(1.0, s.progress + MEETING_MINUTES * pace / minutes(def))
	if s.progress >= 0.999:
		# Both heads learn from a joint card, as from one on their desk.
		for record in [_record(a), _record(b)]:
			if record != null and roster != null:
				roster.add_xp(record, Heads.CARD_XP)
		_reached_end(def, a)
	changed.emit()


func _meeting_seats() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var tags: Array[StringName] = [MEETING_SEAT]
	for key in building.objects_tagged(tags):
		var placed := building.object_at(key)
		var room := building.levels[key.x].room_at_point(placed.centre) if placed != null else null
		if room != null and room.type == MEETING_ROOM:
			out.append(key)
	return out


# --- Budgets, deputies and conferences -------------------------------------

func set_budget(department: StringName, amount: int) -> void:
	budget[department] = maxi(0, amount)
	respeed()
	changed.emit()


## Why a deputy can't be taken on for a slot's wedge now, or "".
func why_no_deputy(base: StringName) -> String:
	if slot_owner(StringName(String(base) + DEPUTY)) != 0:
		return "Already has a deputy."
	if base == OFFICE:
		return "" if has_flag(&"deputy_warden") else "Needs the Deputy warden card."
	if not has_flag(&"deputy_heads"):
		return "Needs the Deputy heads card."
	var record := _head_record(base)
	if record == null:
		return "Needs a head first."
	if record.level < DEPUTY_LEVEL:
		return "The head needs to reach level %d." % DEPUTY_LEVEL
	return ""


## Takes on a deputy for the warden or a head, with a second slot.
func take_on_deputy(base: StringName) -> StaffRoster.Record:
	if not why_no_deputy(base).is_empty() or roster == null:
		return null
	var record := roster.take_on(deputy_role(base), &"day")
	resume()
	return record


## Why a head can't go to a conference now, or "".
func why_no_conference(record: StaffRoster.Record) -> String:
	if not has_flag(&"conferences"):
		return "Needs the Conferences card."
	if record == null or heads == null or heads.department_of(record) == null:
		return "Only heads go to conferences."
	if conferences.has(record.id) or record.off_until >= _day():
		return "Away already."
	return ""


## Sends a head away for CONFERENCE_DAYS; they come back with
## CONFERENCE_CARDS cards in their wedge turned face up.
func send_to_conference(record: StaffRoster.Record) -> bool:
	if not why_no_conference(record).is_empty():
		return false
	var today := _day()
	record.off_until = today + CONFERENCE_DAYS - 1
	record.away = "at a conference"
	conferences[record.id] = [heads.department_of(record).id, today + CONFERENCE_DAYS]
	if pay.is_valid():
		pay.call(CONFERENCE_COST, "Conferences")
	changed.emit()
	return true


# --- Wing trials ------------------------------------------------------------

## Sleeping rooms as [level, room] pairs, for picking a wing.
func sleeping_rooms() -> Array:
	return people.home_rooms().map(func(entry: Array) -> Array: return [entry[0], entry[1]]) if people != null else []


## About half the beds, rooms taken in order across the map.
func default_wing() -> Array:
	var rooms := people.home_rooms() if people != null else []
	rooms.sort_custom(func(a: Array, b: Array) -> bool:
		var ca: Vector2i = (a[1] as Room).cells[0]
		var cb: Vector2i = (b[1] as Room).cells[0]
		return a[0] < b[0] or a[0] == b[0] and (ca.x < cb.x or ca.x == cb.x and ca.y < cb.y))
	var beds := 0
	for entry: Array in rooms:
		beds += int(entry[2])
	var out: Array = []
	var taken := 0
	for entry: Array in rooms:
		if taken * 2 >= beds and not out.is_empty():
			break
		out.append([entry[0], (entry[1] as Room).cells[0].x, (entry[1] as Room).cells[0].y])
		taken += int(entry[2])
	return out


## Whether someone sleeps in a trial's wing.
func in_wing(id: StringName, person: Object) -> bool:
	var trial: Dictionary = trials.get(id, {})
	if trial.is_empty() or people == null or not person is Person:
		return false
	var home := people.home_room(person)
	if home.is_empty():
		return false
	var key := [home[0], (home[1] as Room).cells[0].x, (home[1] as Room).cells[0].y]
	return (trial.rooms as Array).has(key)


## Starts trying a policy card in a wing: its effects count only there.
func start_trial(def: ResearchCardDef, rooms: Array = []) -> void:
	var s: CardState = states[def.id]
	s.state = State.TRIAL
	trials[def.id] = {"rooms": rooms if not rooms.is_empty() else default_wing(), "start_day": _day(),
			"report_day": 0, "wing": [0.0, 0, 0, 0], "rest": [0.0, 0, 0, 0]}
	_scope_trial(def)
	changed.emit()


## Something worth comparing happened to someone during trials: &"fight"
## or &"find".
func note_trial(person: Person, what: StringName) -> void:
	for id: StringName in trials:
		var side: Array = trials[id].wing if in_wing(id, person) else trials[id].rest
		side[2 if what == &"fight" else 3] += 1


## Rolls a trial out everywhere: the card is done.
func roll_out(def: ResearchCardDef) -> void:
	if state_of(def.id) != State.TRIAL:
		return
	_end_trial(def)
	_finish(def, 0, true)


## Tries it again in another wing.
func adjust(def: ResearchCardDef) -> void:
	if state_of(def.id) != State.TRIAL:
		return
	var old: Array = trials.get(def.id, {}).get("rooms", [])
	var others := sleeping_rooms().map(func(pair: Array) -> Array:
		return [pair[0], (pair[1] as Room).cells[0].x, (pair[1] as Room).cells[0].y]).filter(func(key: Array) -> bool:
		return not old.has(key))
	start_trial(def, others)


## Drops it: half the know-how back, and it can be researched again.
func shelve(def: ResearchCardDef) -> void:
	if state_of(def.id) != State.TRIAL:
		return
	_end_trial(def)
	var s: CardState = states[def.id]
	s.state = State.FACE_UP
	s.progress = 0.0
	knowhow.refund(cost(def), SHELVE_REFUND)
	if def.pair != &"" and state_of(def.pair) == State.LOCKED_OUT and not states[def.pair].double:
		states[def.pair].state = State.FACE_UP
	changed.emit()


## "Wing: mood 64, 1 fight; rest: mood 58, 3 fights" for a trial.
func trial_words(def: ResearchCardDef) -> String:
	var trial: Dictionary = trials.get(def.id, {})
	if trial.is_empty():
		return ""
	if int(trial.wing[1]) == 0 and int(trial.rest[1]) == 0:
		return "No numbers yet: the first come in at midnight."
	var side := func(name: String, row: Array) -> String:
		var mood := roundi(row[0] / row[1]) if int(row[1]) > 0 else 0
		return "%s: mood %d, %d %s, %d %s found" % [name, mood, row[2], "fight" if int(row[2]) == 1 else "fights",
				row[3], "item" if int(row[3]) == 1 else "items"]
	return "%s. %s." % [side.call("The wing", trial.wing), side.call("The rest", trial.rest)]


func _scope_trial(def: ResearchCardDef) -> void:
	if modifiers == null:
		return
	var sums := {}
	for effect: Dictionary in def.effects:
		if effect.has("modifier"):
			sums[StringName(effect.modifier)] = sums.get(StringName(effect.modifier), 0.0) + float(effect.amount)
	var id := def.id
	modifiers.set_scoped(StringName("trial_%s" % id), sums, func(person: Object) -> bool: return in_wing(id, person))


func _end_trial(def: ResearchCardDef) -> void:
	trials.erase(def.id)
	if modifiers != null:
		modifiers.clear_scoped(StringName("trial_%s" % def.id))


func _trials_nightly() -> void:
	var today := _day()
	for id: StringName in trials.keys():
		var trial: Dictionary = trials[id]
		if people != null:
			for person in people.people:
				if person.group == &"prisoner":
					var side: Array = trial.wing if in_wing(id, person) else trial.rest
					side[0] += person.mood
					side[1] += 1
		if int(trial.report_day) == 0 and today - int(trial.start_day) >= TRIAL_DAYS:
			trial.report_day = today
			trial_report.emit(card(id), trial_words(card(id)))
		elif int(trial.report_day) > 0 and today - int(trial.report_day) >= TRIAL_GRACE:
			roll_out(card(id))


# --- Effects ----------------------------------------------------------------

## The modifiers every card done adds up to, such as {&"job_output": 0.2}.
## Effects aren't saved: they follow from which cards are done.
func modifier_sums() -> Dictionary:
	var out := {}
	for def in board.cards + board.refinements:
		var times := float(refinements.get(def.department, 0)) if def.repeatable else (1.0 if is_done(def.id) else 0.0)
		if times <= 0.0:
			continue
		for effect: Dictionary in def.effects:
			if effect.has("modifier"):
				var key := StringName(effect.modifier)
				out[key] = out.get(key, 0.0) + float(effect.amount) * times
	return out


## Whether a card done has switched on a flag, such as &"joint_cards".
func has_flag(flag: StringName) -> bool:
	for def in board.cards:
		if is_done(def.id):
			for effect: Dictionary in def.effects:
				if effect.has("flag") and StringName(effect.flag) == flag:
					return true
	return false


## Whether something a card unlocks (kind "room", "object" or "role") may
## be used: anything no card unlocks always may.
func unlocked(kind: String, id: StringName) -> bool:
	if mode == Mode.OFF:
		return true
	var unlocker := unlocked_by(kind, id)
	return unlocker == null or is_done(unlocker.id)


## The card that unlocks something, or null.
func unlocked_by(kind: String, id: StringName) -> ResearchCardDef:
	for def in board.cards:
		for effect: Dictionary in def.effects:
			if effect.get("unlock", "") == kind and StringName(effect.id) == id:
				return def
	return null


## Money cards done bring in each day, as [[amount, line], ...].
func daily_money() -> Array:
	var out: Array = []
	for def in board.cards:
		if is_done(def.id):
			for effect: Dictionary in def.effects:
				if effect.has("money_per_day"):
					out.append([int(effect.money_per_day), String(effect.line)])
	return out


# --- The character scale ----------------------------------------------------

## Rebuilds the character scale from its sources.
func refresh_lean() -> void:
	var total := 0.0
	for def in board.cards:
		if def.lean != 0 and is_done(def.id):
			total += def.lean * CARD_LEAN
	if roster != null:
		for record in roster.records:
			for def in record.work_traits:
				total += def.lean * HEAD_LEAN
	var today := _day()
	for shift: Array in lean_shifts.duplicate():
		var age: int = today - int(shift[1])
		if age >= LEAN_FADE_DAYS:
			lean_shifts.erase(shift)
		else:
			total += float(shift[0]) * (1.0 - float(age) / LEAN_FADE_DAYS)
	lean = clampf(total, -100.0, 100.0)


## A choice tagged strict or caring nudges the character scale.
func nudge_lean(amount: float) -> void:
	lean_shifts.append([amount, _day()])


## "Fairly caring", for the report.
func lean_words() -> String:
	var size := absf(lean)
	if size < 10.0:
		return "Even-handed"
	var side := "strict" if lean > 0.0 else "caring"
	return ("Slightly " if size < 30.0 else "Fairly " if size < 60.0 else "Very ") + side


# --- Inside -------------------------------------------------------------------

## A face-down card's hint, with how far along it is when it counts
## things: "10 drug finds (6 so far)".
func hint_words(def: ResearchCardDef) -> String:
	if def.reveal == null:
		return "From the start"
	var reveal_def := def.reveal
	match reveal_def.kind:
		RevealDef.Kind.COUNT, RevealDef.Kind.EVENT, RevealDef.Kind.PRISONER:
			if counters != null and reveal_def.count > 1:
				var seen := 0
				for id in String(reveal_def.id).split("|"):
					seen += counters.total(StringName(id))
				return "%s (%d so far)" % [reveal_def.hint, mini(seen, reveal_def.count)]
		RevealDef.Kind.GRADE:
			return "%s (now grade %d)" % [reveal_def.hint, _grade()]
	return reveal_def.hint


func _revealed_now(reveal_def: RevealDef) -> String:
	match reveal_def.kind:
		RevealDef.Kind.START:
			return "From the start"
		RevealDef.Kind.COUNT, RevealDef.Kind.FIRST, RevealDef.Kind.EVENT, RevealDef.Kind.PRISONER:
			if counters == null:
				return ""
			var seen := 0
			for id in String(reveal_def.id).split("|"):
				seen += counters.total(StringName(id))
			# A Party planner makes things count more towards turning cards up.
			var scale := Modifiers.scale(modifiers, &"reveal_counts") if reveal_def.kind != RevealDef.Kind.FIRST else 1.0
			return reveal_def.hint if seen * scale >= reveal_def.count else ""
		RevealDef.Kind.BUILT:
			return reveal_def.hint if _built(String(reveal_def.id).split("|")) else ""
		RevealDef.Kind.SETTING:
			if not setting.is_valid():
				return ""
			return reveal_def.hint if setting.call(reveal_def.id) == reveal_def.value else ""
		RevealDef.Kind.GRADE:
			return reveal_def.hint if _grade() >= reveal_def.count else ""
		RevealDef.Kind.LEAN:
			return reveal_def.hint if lean * reveal_def.count >= LEAN_REVEAL else ""
		RevealDef.Kind.ADDON:
			return reveal_def.hint if addons.has(reveal_def.id) else ""
		RevealDef.Kind.HEAD_LEVEL:
			if heads == null:
				return ""
			for department in heads.departments:
				var record := heads.head(department)
				if record != null and record.level >= reveal_def.count:
					return reveal_def.hint
	return ""


## Whether a wedge has nothing left but done or locked-out cards.
func _wedge_finished(department: StringName) -> bool:
	for def in board.cards:
		if def.department == department and _addon_owned(def) and not is_hire(def) \
				and not state_of(def.id) in [State.DONE, State.LOCKED_OUT]:
			return false
	return true


func _refine_scale(def: ResearchCardDef) -> float:
	return pow(REFINE_GROWTH, refinements.get(def.department, 0)) if def.repeatable else 1.0


func _built(types: Array) -> bool:
	if building == null:
		return false
	for n: int in building.levels:
		for room: Room in building.levels[n].rooms():
			if types.has(String(room.type)):
				return true
	return false


func _grade() -> int:
	return grade.call() if grade.is_valid() else 0


func _day() -> int:
	return clock.day() if clock != null else 1


func _addon_owned(def: ResearchCardDef) -> bool:
	return def.addon == &"" or addons.has(def.addon)


## Done, or a hire card under Warden only, where no card waits on a head.
func _counts_as_done(id: StringName) -> bool:
	return is_done(id) or mode == Mode.WARDEN_ONLY and _department_of_hire.has(id)


func _needs_words(def: ResearchCardDef) -> String:
	var names := def.requires.filter(func(id: StringName) -> bool: return not _counts_as_done(id)) \
			.map(func(id: StringName) -> String: return card(id).display_name)
	if def.rule == 0:
		return " and ".join(names)
	return ("one of " if def.needed() == 1 else "%d of " % def.needed()) + ", ".join(names)


## The slot that works a kind of know-how: its wedge's head, or the warden.
func _kind_base(kind: StringName) -> StringName:
	var department: StringName = board.kind_departments.get(kind, OFFICE)
	return department if mode != Mode.WARDEN_ONLY and _head_record(department) != null else OFFICE


func _base(slot: StringName) -> StringName:
	return StringName(String(slot).trim_suffix(DEPUTY))


func _head_record(department: StringName) -> StaffRoster.Record:
	if heads == null:
		return null
	var def := heads.find(department)
	return heads.head(def) if def != null else null


func _role_record(role: StringName) -> StaffRoster.Record:
	if roster == null:
		return null
	for record in roster.records:
		if record.role == role:
			return record
	return null


func _record(id: int) -> StaffRoster.Record:
	if roster == null or id == 0:
		return null
	for record in roster.records:
		if record.id == id:
			return record
	return null


## Research items carry "card:<id>", so a saved game reads them back the
## same way.
func _ref(def: ResearchCardDef) -> String:
	return "card:%s" % def.id


func _desk_items(def: ResearchCardDef) -> Array[DeskWork.Item]:
	var out: Array[DeskWork.Item] = []
	if desk_work == null:
		return out
	var ref := _ref(def)
	for owner: int in desk_work.piles:
		for item: DeskWork.Item in desk_work.piles[owner]:
			if item.kind == &"research" and item.ref is String and item.ref == ref:
				out.append(item)
	return out


func _put_on_desk(def: ResearchCardDef) -> void:
	var s: CardState = states[def.id]
	var owner := slot_owner(s.slot)
	if owner == 0:
		s.state = State.PAUSED
		return
	var left := minutes(def) * (1.0 - s.progress) / speed(def, owner)
	desk_work.add(owner, &"research", def.display_name, maxf(left, 1.0), _ref(def))


func _next_in(slot: StringName) -> void:
	var line: Array = queues.get(_base(slot), [])
	while not line.is_empty() and (free_slot(card(line[0])) != &""):
		var def := card(line.pop_front())
		if def != null and available(def):
			begin(def)


func _on_desk_finished(owner: int, item: DeskWork.Item) -> void:
	if item.kind != &"research" or not item.ref is String or not String(item.ref).begins_with("card:"):
		return
	var def := card(StringName(String(item.ref).trim_prefix("card:")))
	if def == null:
		return
	var slot := states[def.id].slot
	_reached_end(def, owner)
	_next_in(slot)


## A card's desk time is all done: policies go to a wing trial, others
## are done.
func _reached_end(def: ResearchCardDef, owner: int) -> void:
	var s: CardState = states[def.id]
	s.slot = &""
	s.partner = &""
	if def.trial and mode == Mode.FULL:
		s.progress = 1.0
		start_trial(def)
		return
	_finish(def, owner, true)


func _on_applicants(department: DepartmentDef) -> void:
	var id: StringName = board.hire_cards.get(department.id, &"")
	if id != &"":
		_finish(card(id), heads.warden().id if heads.warden() != null else 0, true)


## A new head's pet project: a card in their wedge turns up.
func _on_hired(department: DepartmentDef, record: StaffRoster.Record) -> void:
	if mode != Mode.OFF:
		var found := reveal_in(department.id, 1, "Pet project of %s" % record.name)
		if not found.is_empty():
			pet_projects[record.id] = found[0].id
	resume()


## A head gone: their card waits, its progress kept.
func _on_roster_changed() -> void:
	for id: StringName in states:
		var s: CardState = states[id]
		var def := card(id)
		if s.state != State.RESEARCHING or is_hire(def):
			continue
		if slot_owner(s.slot) != 0 and (s.partner == &"" or slot_owner(s.partner) != 0):
			continue
		s.progress = progress(def)
		desk_work.remove(&"research", _ref(def))
		s.state = State.PAUSED
		s.slot = &""
		s.partner = &""
	for owner: int in pet_projects.keys():
		if _record(owner) == null:
			pet_projects.erase(owner)
	resume()


func _finish(def: ResearchCardDef, owner: int, announce: bool) -> void:
	var s: CardState = states[def.id]
	if s.state == State.DONE:
		return
	if def.repeatable:
		refinements[def.department] = refinements.get(def.department, 0) + 1
		s.state = State.FACE_UP
		s.progress = 0.0
		if announce:
			finished.emit(def, owner)
		changed.emit()
		return
	s.state = State.DONE
	s.progress = 1.0
	if def.pair != &"":
		if state_of(def.pair) == State.DONE:
			_undo(card(def.pair))
		else:
			if state_of(def.pair) == State.TRIAL:
				_end_trial(card(def.pair))
			states[def.pair].state = State.LOCKED_OUT
			states[def.pair].double = true
	if announce:
		for effect: Dictionary in def.effects:
			if effect.has("reveal"):
				reveal_in(def.department, int(effect.reveal), def.display_name)
		if has_flag(&"deputy_warden") and def.effects.any(func(e: Dictionary) -> bool: return e.get("flag", "") == "deputy_warden"):
			take_on_deputy(OFFICE)
		finished.emit(def, owner)
	changed.emit()


## A pick-one card switched away from: its effects go with its state.
func _undo(def: ResearchCardDef) -> void:
	var s: CardState = states[def.id]
	s.state = State.LOCKED_OUT
	s.progress = 0.0
	s.double = true


func capture() -> Dictionary:
	var cards := {}
	for id: StringName in states:
		var s: CardState = states[id]
		var def := card(id)
		cards[String(id)] = [s.state, progress(def) if def != null else s.progress, s.revealed_by, s.ready_day, s.double,
				String(s.slot), String(s.partner)]
	var saved_queues := {}
	for slot: StringName in queues:
		saved_queues[String(slot)] = (queues[slot] as Array).map(func(id: StringName) -> String: return String(id))
	var saved_trials := {}
	for id: StringName in trials:
		saved_trials[String(id)] = trials[id].duplicate(true)
	return {"cards": cards, "queues": saved_queues, "mode": mode, "lean_shifts": lean_shifts.duplicate(true),
			"addons": addons.map(func(id: StringName) -> String: return String(id)),
			"budget": _strings(budget), "refinements": _strings(refinements), "trials": saved_trials,
			"conferences": conferences.duplicate(true), "pet_projects": _strings(pet_projects),
			"news": news.duplicate(), "yesterday_news": yesterday_news.duplicate()}


## Loads card states; cards the board no longer has are dropped, and new
## ones start hidden.
func restore(data: Dictionary) -> void:
	var cards: Dictionary = data.get("cards", {})
	for key: String in cards:
		var id := StringName(key)
		if not states.has(id):
			push_warning("Research card %s is no longer on the board" % key)
			continue
		var row: Array = cards[key]
		var s: CardState = states[id]
		s.state = int(row[0]) as State
		s.progress = float(row[1])
		s.revealed_by = row[2]
		s.ready_day = int(row[3])
		s.double = bool(row[4])
		s.slot = StringName(row[5]) if row.size() > 5 else &""
		s.partner = StringName(row[6]) if row.size() > 6 else &""
		if s.state == State.RESEARCHING and is_hire(card(id)) and heads.hiring() == null:
			s.state = State.FACE_UP
	queues.clear()
	var saved_queues: Dictionary = data.get("queues", {})
	for slot: String in saved_queues:
		queues[StringName(slot)] = (saved_queues[slot] as Array).map(func(id: String) -> StringName: return StringName(id))
	lean_shifts = (data.get("lean_shifts", []) as Array).duplicate(true)
	addons.assign((data.get("addons", []) as Array).map(func(id: String) -> StringName: return StringName(id)))
	budget.clear()
	for key: String in data.get("budget", {}):
		budget[StringName(key)] = int(data.budget[key])
	refinements.clear()
	for key: String in data.get("refinements", {}):
		refinements[StringName(key)] = int(data.refinements[key])
	trials.clear()
	for key: String in data.get("trials", {}):
		trials[StringName(key)] = (data.trials[key] as Dictionary).duplicate(true)
		_scope_trial(card(StringName(key)))
	conferences.clear()
	for key: Variant in data.get("conferences", {}):
		conferences[int(key)] = data.conferences[key]
	pet_projects.clear()
	news.assign(data.get("news", []))
	yesterday_news.assign(data.get("yesterday_news", []))
	for key: Variant in data.get("pet_projects", {}):
		pet_projects[int(key)] = StringName(data.pet_projects[key])
	mode = int(data.get("mode", Mode.FULL)) as Mode
	if knowhow != null:
		knowhow.earning = mode != Mode.OFF
	refresh_lean()
	changed.emit()


func _strings(from: Dictionary) -> Dictionary:
	var out := {}
	for key: Variant in from:
		out[String(key) if key is StringName else key] = String(from[key]) if from[key] is StringName else from[key]
	return out
