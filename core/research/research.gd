class_name Research
extends Node
## The research board in play. Each wedge has one slot: the warden's
## office, and each department whose head is hired. A slot's card is a
## DeskItem of kind research on its owner's pile, worked after paperwork
## and in-tray cards; its know-how is paid in full when it starts. Most
## cards start face down and turn up from how the prison is run (see
## RevealDef), or by word of mouth WORD_OF_MOUTH_DAYS after everything
## they need is done.
##
## Until a department has a head, the warden may work its cards, at half
## speed outside the office and Administration. Hire cards go through
## Heads: starting one puts the hire on the warden's desk, and it's done
## when the applicants arrive.

signal changed
signal revealed(card: ResearchCardDef, why: String)
signal started(card: ResearchCardDef, owner: int)
signal finished(card: ResearchCardDef, owner: int)

enum State { HIDDEN, FACE_UP, RESEARCHING, PAUSED, TRIAL, DONE, LOCKED_OUT }
enum Mode { FULL, WARDEN_ONLY, OFF }

const OFFICE := &"office"
const ADMIN := &"admin"
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
## Know-how back when a card is shelved after a trial.
const SHELVE_REFUND := 0.5

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

var board: ResearchBoardDef
var mode := Mode.FULL
## Card id -> CardState.
var states: Dictionary[StringName, CardState] = {}
## Department (or OFFICE) -> card ids queued after the one being worked.
var queues: Dictionary[StringName, Array] = {}
## Add-ons owned.
var addons: Array[StringName] = []
## Character: -100 caring to +100 strict, rebuilt at midnight.
var lean := 0.0
## In-tray shifts to the lean, each [amount, day], fading over LEAN_FADE_DAYS.
var lean_shifts: Array = []
const LEAN_FADE_DAYS := 10

var knowhow: Knowhow
var counters: Counters
var heads: Heads
var roster: StaffRoster
var desk_work: DeskWork
var modifiers: Modifiers
var building: Building
## () -> int: last midnight's star grade.
var grade: Callable
## (setting id) -> Variant: a setting's value, for SETTING reveals.
var setting: Callable
var clock: GameClock:
	set(value):
		clock = value
		clock.day_changed.connect(func(_day: int) -> void: nightly())

var _department_of_hire: Dictionary[StringName, StringName] = {}


func start() -> void:
	for department: StringName in board.hire_cards:
		_department_of_hire[board.hire_cards[department]] = department
	for card in board.cards:
		if not states.has(card.id):
			states[card.id] = CardState.new()
	var root := states.get(&"warden-s-office") as CardState
	if root != null:
		root.state = State.DONE
	if counters != null:
		counters.counted.connect(func(_id: StringName, _total: int, _n: int) -> void: check_reveals())
	if desk_work != null:
		desk_work.finished.connect(_on_desk_finished)
	if heads != null:
		heads.applicants_ready.connect(_on_applicants)
		heads.hired.connect(func(_d: DepartmentDef, _r: StaffRoster.Record) -> void: resume())
	if roster != null:
		roster.changed.connect(_on_roster_changed)
		roster.levelled_up.connect(func(_r: StaffRoster.Record) -> void: check_reveals())
	if building != null:
		building.changed.connect(check_reveals)
	set_mode(mode)
	check_reveals()


## A fresh game's know-how.
func give_start_knowhow() -> void:
	for id: StringName in START_KNOWHOW:
		knowhow.add(id, START_KNOWHOW[id])


func set_mode(value: Mode) -> void:
	mode = value
	if knowhow != null:
		knowhow.earning = mode != Mode.OFF
	if mode == Mode.OFF:
		for card in board.cards:
			if card.pair == &"" and _addon_owned(card):
				_finish(card, 0, false)
	changed.emit()


func card(id: StringName) -> ResearchCardDef:
	return board.card(id)


func state_of(id: StringName) -> State:
	var s: CardState = states.get(id)
	return s.state if s != null else State.HIDDEN


func is_done(id: StringName) -> bool:
	return state_of(id) == State.DONE


func is_shown(def: ResearchCardDef) -> bool:
	return _addon_owned(def)


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
			return "Not turned up yet" + (": %s." % def.reveal.hint if def.reveal != null else ".")
		State.RESEARCHING, State.TRIAL:
			return "Already under way."
		State.DONE:
			return "Done."
	if mode == Mode.OFF:
		return "Research is off."
	var met := def.requires.filter(func(id: StringName) -> bool: return is_done(id)).size()
	if met < def.needed():
		return "Needs %s first." % _needs_words(def)
	var stars: int = GATES.get(def.tier, 0)
	if stars > 0 and _grade() < stars:
		return "Needs a %d-star grade (now %d)." % [stars, _grade()]
	if def.pair != &"" and state_of(def.pair) in [State.RESEARCHING, State.TRIAL, State.PAUSED] :
		return "Locked out: %s is under way." % card(def.pair).display_name
	if not knowhow.can_pay(cost(def)):
		return "Not enough know-how."
	if _department_of_hire.has(def.id):
		var department := heads.find(_department_of_hire[def.id]) if heads != null else null
		if department == null:
			return "No such department."
		if mode == Mode.WARDEN_ONLY:
			return "Research is warden only."
		return heads.why_not(department)
	if owner_for(def) == 0:
		return "Needs a warden at a desk."
	if _slot_busy(slot_of(def)):
		return "%s is busy; queue it instead." % _slot_name(slot_of(def))
	return ""


## Know-how a card costs now: double when switching to a pick-one partner.
func cost(def: ResearchCardDef) -> Dictionary:
	var out := {}
	var times := 2 if states[def.id].double else 1
	for id: StringName in def.knowhow:
		out[id] = def.knowhow[id] * times
	return out


## The wedge slot that works a card: its department once a head is hired,
## otherwise the warden's office.
func slot_of(def: ResearchCardDef) -> StringName:
	if mode == Mode.WARDEN_ONLY or def.department == OFFICE or _department_of_hire.has(def.id):
		return OFFICE
	return def.department if _head_record(def.department) != null else OFFICE


## The roster id of whoever works a slot, or 0.
func slot_owner(slot: StringName) -> int:
	if slot == OFFICE:
		var warden := heads.warden() if heads != null else null
		return warden.id if warden != null else 0
	var record := _head_record(slot)
	return record.id if record != null else 0


func owner_for(def: ResearchCardDef) -> int:
	return slot_owner(slot_of(def))


## The slots there are: the office and each department with a head.
func slots() -> Array[StringName]:
	var out: Array[StringName] = [OFFICE]
	if mode != Mode.WARDEN_ONLY and heads != null:
		for department in heads.departments:
			if heads.head(department) != null:
				out.append(department.id)
	return out


## The card a slot is working, or null.
func slot_card(slot: StringName) -> ResearchCardDef:
	for id: StringName in states:
		var def := card(id)
		if states[id].state == State.RESEARCHING and slot_of(def) == slot and not _department_of_hire.has(id):
			return def
	if slot == OFFICE and heads != null and heads.hiring() != null:
		return card(board.hire_cards.get(heads.hiring().id, &""))
	return null


## Starts a card now, paying its know-how. Returns whether it started.
func begin(def: ResearchCardDef) -> bool:
	if not available(def):
		return false
	knowhow.pay(cost(def))
	var s: CardState = states[def.id]
	if _department_of_hire.has(def.id):
		heads.start_hire(heads.find(_department_of_hire[def.id]))
		s.state = State.RESEARCHING
		started.emit(def, owner_for(def))
		changed.emit()
		return true
	s.state = State.RESEARCHING
	if def.pair != &"" and state_of(def.pair) == State.FACE_UP:
		states[def.pair].state = State.LOCKED_OUT
	_put_on_desk(def)
	started.emit(def, owner_for(def))
	changed.emit()
	return true


## Queues a card after what its slot is working, up to QUEUE. Starts it
## at once if the slot is free.
func queue(def: ResearchCardDef) -> bool:
	if available(def):
		return begin(def)
	var slot := slot_of(def)
	var line: Array = queues.get_or_add(slot, [])
	if line.size() >= QUEUE or line.has(def.id) or states[def.id].state != State.FACE_UP:
		return false
	line.append(def.id)
	changed.emit()
	return true


func unqueue(def: ResearchCardDef) -> void:
	for slot: StringName in queues:
		(queues[slot] as Array).erase(def.id)
	changed.emit()


## Stops a card before it's done: all the know-how back, progress kept.
func cancel(def: ResearchCardDef) -> void:
	var s: CardState = states[def.id]
	if s.state != State.RESEARCHING:
		return
	if _department_of_hire.has(def.id):
		heads.cancel_hire()
	else:
		s.progress = progress(def)
		desk_work.remove(&"research", def.id)
	knowhow.refund(cost(def))
	s.state = State.FACE_UP
	if def.pair != &"" and state_of(def.pair) == State.LOCKED_OUT and not is_done(def.pair):
		states[def.pair].state = State.FACE_UP
	changed.emit()
	_next_in(slot_of(def))


## How far along a card is, 0 to 1.
func progress(def: ResearchCardDef) -> float:
	var s: CardState = states[def.id]
	if s.state == State.DONE:
		return 1.0
	if _department_of_hire.has(def.id):
		var hire := heads.hire_card() if heads != null else null
		return hire.done_share() if hire != null and StringName(hire.ref) == _department_of_hire[def.id] else 0.0
	for item in _desk_items(def):
		return s.progress + item.done_share() * (1.0 - s.progress)
	return s.progress


## The research speed for a card beyond what the desk already gives (level,
## traits and office): morale, the warden away from home, and modifiers.
func speed(def: ResearchCardDef, owner: int) -> float:
	var out := 1.0 + (modifiers.value(&"research_speed") if modifiers != null else 0.0)
	var record := _record(owner)
	if record != null:
		out *= 0.8 if record.morale < 30.0 else 1.1 if record.morale > 70.0 else 1.0
		var warden := heads.warden() if heads != null else null
		if warden != null and record.id == warden.id and mode != Mode.WARDEN_ONLY \
				and def.department != OFFICE and def.department != ADMIN:
			out *= WARDEN_AWAY_SPEED
	return out


## "Researching Cell searches: 62%, about 1 day" for an owner, or "".
func owner_line(owner: int) -> String:
	for slot in slots():
		if slot_owner(slot) == owner:
			var def := slot_card(slot)
			if def != null:
				return "Researching %s: %d%%" % [def.display_name, roundi(progress(def) * 100.0)]
	return ""


## Puts cards whose slot came back (a head hired again) back on a desk.
func resume() -> void:
	for id: StringName in states:
		var s: CardState = states[id]
		if s.state == State.PAUSED:
			var def := card(id)
			# A wedge's card waits for its own head, not the warden.
			var home := mode == Mode.WARDEN_ONLY or def.department == OFFICE or _head_record(def.department) != null
			if home and owner_for(def) != 0 and not _slot_busy(slot_of(def)):
				s.state = State.RESEARCHING
				_put_on_desk(def)
	for slot in slots():
		_next_in(slot)
	changed.emit()


## Turns face up every card whose reveal has happened.
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
## ready first, such as after a conference. Returns how many turned up.
func reveal_in(department: StringName, count: int, why: String) -> int:
	var hidden := board.cards.filter(func(def: ResearchCardDef) -> bool:
		return def.department == department and states[def.id].state == State.HIDDEN and _addon_owned(def))
	hidden.sort_custom(func(a: ResearchCardDef, b: ResearchCardDef) -> bool:
		var ma := a.needed() - a.requires.filter(is_done).size()
		var mb := b.needed() - b.requires.filter(is_done).size()
		return a.tier < b.tier or a.tier == b.tier and ma < mb)
	for def: ResearchCardDef in hidden.slice(0, count):
		reveal(def, why)
	return mini(count, hidden.size())


## Midnight: the character scale, word of mouth and grade reveals.
func nightly() -> void:
	refresh_lean()
	var today := clock.day() if clock != null else 1
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
	var today := clock.day() if clock != null else 1
	for shift: Array in lean_shifts.duplicate():
		var age: int = today - int(shift[1])
		if age >= LEAN_FADE_DAYS:
			lean_shifts.erase(shift)
		else:
			total += float(shift[0]) * (1.0 - float(age) / LEAN_FADE_DAYS)
	lean = clampf(total, -100.0, 100.0)


## A choice tagged strict or caring nudges the character scale.
func nudge_lean(amount: float) -> void:
	lean_shifts.append([amount, clock.day() if clock != null else 1])


## "Fairly caring", for the report.
func lean_words() -> String:
	var size := absf(lean)
	if size < 10.0:
		return "Even-handed"
	var side := "strict" if lean > 0.0 else "caring"
	return ("Slightly " if size < 30.0 else "Fairly " if size < 60.0 else "Very ") + side


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
			return reveal_def.hint if seen >= reveal_def.count else ""
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


func _addon_owned(def: ResearchCardDef) -> bool:
	return def.addon == &"" or addons.has(def.addon)


func _needs_words(def: ResearchCardDef) -> String:
	var names := def.requires.filter(func(id: StringName) -> bool: return not is_done(id)) \
			.map(func(id: StringName) -> String: return card(id).display_name)
	if def.rule == 0:
		return " and ".join(names)
	return ("one of " if def.needed() == 1 else "%d of " % def.needed()) + ", ".join(names)


func _slot_busy(slot: StringName) -> bool:
	return slot_card(slot) != null


func _slot_name(slot: StringName) -> String:
	if slot == OFFICE:
		return "The warden"
	var record := _head_record(slot)
	return record.name if record != null else String(slot)


func _head_record(department: StringName) -> StaffRoster.Record:
	if heads == null:
		return null
	var def := heads.find(department)
	return heads.head(def) if def != null else null


func _record(id: int) -> StaffRoster.Record:
	if roster == null:
		return null
	for record in roster.records:
		if record.id == id:
			return record
	return null


func _desk_items(def: ResearchCardDef) -> Array[DeskWork.Item]:
	var out: Array[DeskWork.Item] = []
	if desk_work == null:
		return out
	for owner: int in desk_work.piles:
		for item: DeskWork.Item in desk_work.piles[owner]:
			if item.kind == &"research" and item.ref is StringName and item.ref == def.id:
				out.append(item)
	return out


func _put_on_desk(def: ResearchCardDef) -> void:
	var owner := owner_for(def)
	var s: CardState = states[def.id]
	if owner == 0:
		s.state = State.PAUSED
		return
	var minutes := def.desk_minutes * (2.0 if s.double else 1.0) * (1.0 - s.progress) / speed(def, owner)
	desk_work.add(owner, &"research", def.display_name, maxf(minutes, 1.0), def.id)


func _next_in(slot: StringName) -> void:
	var line: Array = queues.get(slot, [])
	while not line.is_empty() and not _slot_busy(slot):
		var def := card(line.pop_front())
		if def != null and available(def):
			begin(def)


func _on_desk_finished(owner: int, item: DeskWork.Item) -> void:
	if item.kind != &"research" or not item.ref is StringName:
		return
	var def := card(item.ref)
	if def == null:
		return
	_finish(def, owner, true)
	_next_in(slot_of(def))


func _on_applicants(department: DepartmentDef) -> void:
	var id: StringName = board.hire_cards.get(department.id, &"")
	if id != &"":
		_finish(card(id), heads.warden().id if heads.warden() != null else 0, true)


## A head gone or away: their card waits, its progress kept.
func _on_roster_changed() -> void:
	for id: StringName in states:
		var s: CardState = states[id]
		var def := card(id)
		if s.state != State.RESEARCHING or _department_of_hire.has(id):
			continue
		var items := _desk_items(def)
		if items.is_empty():
			s.state = State.PAUSED
		elif _record(_owner_of_item(items[0])) == null:
			s.progress = progress(def)
			desk_work.remove(&"research", def.id)
			s.state = State.PAUSED
	resume()


func _owner_of_item(item: DeskWork.Item) -> int:
	for owner: int in desk_work.piles:
		if (desk_work.piles[owner] as Array).has(item):
			return owner
	return 0


func _finish(def: ResearchCardDef, owner: int, announce: bool) -> void:
	var s: CardState = states[def.id]
	if s.state == State.DONE:
		return
	s.state = State.DONE
	s.progress = 1.0
	if def.pair != &"" and state_of(def.pair) == State.DONE:
		_undo(card(def.pair))
	if def.pair != &"" and state_of(def.pair) != State.DONE:
		states[def.pair].state = State.LOCKED_OUT
		states[def.pair].double = true
	if announce:
		for effect: Dictionary in def.effects:
			if effect.has("reveal"):
				reveal_in(def.department, int(effect.reveal), def.display_name)
		finished.emit(def, owner)
	changed.emit()


## Takes a card's effects away, such as when its partner is adopted.
func _undo(def: ResearchCardDef) -> void:
	var s: CardState = states[def.id]
	s.state = State.LOCKED_OUT
	s.progress = 0.0
	s.double = true


## The modifiers every card done adds up to, such as {&"job_output": 0.2}.
## Effects aren't saved: they follow from which cards are done.
func modifier_sums() -> Dictionary:
	var out := {}
	for def in board.cards:
		if is_done(def.id):
			for effect: Dictionary in def.effects:
				if effect.has("modifier"):
					var key := StringName(effect.modifier)
					out[key] = out.get(key, 0.0) + float(effect.amount)
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


func capture() -> Dictionary:
	var cards := {}
	for id: StringName in states:
		var s: CardState = states[id]
		var def := card(id)
		cards[String(id)] = [s.state, progress(def) if def != null else s.progress, s.revealed_by, s.ready_day, s.double]
	var saved_queues := {}
	for slot: StringName in queues:
		saved_queues[String(slot)] = (queues[slot] as Array).map(func(id: StringName) -> String: return String(id))
	return {"cards": cards, "queues": saved_queues, "mode": mode, "lean_shifts": lean_shifts.duplicate(true),
			"addons": addons.map(func(id: StringName) -> String: return String(id))}


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
		if s.state == State.RESEARCHING and _department_of_hire.has(id) and heads.hiring() == null:
			s.state = State.FACE_UP
	queues.clear()
	var saved_queues: Dictionary = data.get("queues", {})
	for slot: String in saved_queues:
		queues[StringName(slot)] = (saved_queues[slot] as Array).map(func(id: String) -> StringName: return StringName(id))
	lean_shifts = (data.get("lean_shifts", []) as Array).duplicate(true)
	addons.assign((data.get("addons", []) as Array).map(func(id: String) -> StringName: return StringName(id)))
	mode = int(data.get("mode", Mode.FULL)) as Mode
	if knowhow != null:
		knowhow.earning = mode != Mode.OFF
	refresh_lean()
	changed.emit()
