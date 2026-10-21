class_name Release
extends Node
## Going home. From 08:00 each prisoner whose time is up (or who was
## granted parole) collects their things at reception, then waits at the
## bus stop for the morning bus, or walks out of the entrance without a
## road. Leaving frees their bed and keeps a record of them: reformed
## leavers bring a bonus and may send a postcard home a few days later;
## poorly reformed ones may be back on the bus within days.
##
## Without a reception leavers wait a day; on the second they walk out
## anyway.

signal going(count: int)
signal left(entry: Dictionary)
signal returned(person: Person, entry: Dictionary)
signal postcard_came(card: Dictionary)

const LEAVE_HOUR := 8
## Leavers don't set off after this hour; they try again tomorrow.
const LAST_HOUR := 18
const SIGN_OUT_MINUTES := 10.0
## Game minutes to reach reception before signing out wherever they are,
## and to reach the way out before leaving wherever they are.
const WALK_LIMIT := 90.0
## Game minutes waiting at the stop for a bus before walking off.
const BUS_WAIT := 120.0
const REFORM_BONUS := 500
const ALUMNI_KEPT := 200
const POSTCARDS_KEPT := 30
const POSTCARD_CHANCE := 0.5
const POSTCARD_DAYS := Vector2i(3, 7)
const RETURN_DAYS := Vector2i(3, 10)
## Reoffending chance: BASE less per reform point and per course passed.
const RETURN_BASE := 0.55
const RETURN_PER_REFORM := 0.006
const RETURN_PER_COURSE := 0.05
const RETURN_COURSES_MAX := 3
const RETURN_MIN := 0.02
const RETURN_MAX := 0.9
## Postcards shown on a board.
const BOARD_CARDS := 6
const WEEK := 7

enum Stage { TO_RECEPTION, SIGNING, TO_EXIT, AT_STOP }

var people: People
var building: Building
var ledger: Ledger
var intake: Intake
var reform: Reform
var postcard_defs: Array[PostcardDef] = []
var prisoner_group: StringName = &"prisoner"
## Scales the reoffending chance (difficulty).
var return_scale := 1.0
## When set, its operation times are used instead of the hour above (main
## passes on Regime.operation_due).
var regime: Regime
var clock: GameClock:
	set(value):
		clock = value
		clock.minute_passed.connect(func(_minute: int) -> void: _look())
		clock.hour_changed.connect(_on_hour)

## Who has left, newest first: plain dictionaries (see _record).
var alumni: Array[Dictionary] = []
## Postcards received, newest first: {day, from, id, text}.
var postcards: Array[Dictionary] = []
## Report lines for today so far, and yesterday's.
var today_lines: Array[String] = []
var yesterday_lines: Array[String] = []

## Leavers on their way: [stage, minutes in it].
var _leaving: Dictionary[Person, Array] = {}
var _rng := RandomNumberGenerator.new()


## Prisoners whose time is up and who haven't set off yet.
func due() -> Array[Person]:
	return people.people.filter(func(p: Person) -> bool:
		return p.group == prisoner_group and PrisonerFile.of(p).due_out and not _leaving.has(p))


func is_leaving(person: Person) -> bool:
	return _leaving.has(person)


## Leavers who will want the bus: on their way or due.
func waiting_for_bus() -> int:
	return _leaving.size() + (due().size() if clock.hour() < LAST_HOUR else 0)


## The reoffending chance for someone leaving now.
func return_chance(person: Person) -> float:
	var courses := mini(PrisonerFile.of(person).passed.size(), RETURN_COURSES_MAX)
	var chance := RETURN_BASE - RETURN_PER_REFORM * reform.value(person) - RETURN_PER_COURSE * courses
	return clampf(chance * return_scale, RETURN_MIN, RETURN_MAX)


## Alumni coming back today, oldest first, for the bus.
func returning_today() -> Array:
	var out: Array = []
	for entry in alumni:
		if entry.will_return_day != -1 and entry.will_return_day <= clock.day() and not entry.get("returned", false):
			out.push_front(entry)
	return out


## Makes a new arrival into someone who has been here before.
func bring_back(person: Person, entry: Dictionary) -> void:
	entry["returned"] = true
	person.name = entry.name
	person.look_seed = entry.look
	person.category = &"medium" if entry.category == &"low" else entry.category
	var traits: Array[TraitDef] = []
	for id: StringName in entry.traits:
		for def in people.traits:
			if def.id == id:
				traits.append(def)
	if not traits.is_empty():
		person.traits = traits
	var file := PrisonerFile.of(person)
	file.came_back = entry.came_back + 1
	for id: StringName in entry.skills:
		file.skills[id] = entry.skills[id]
	file.add_log(clock.day(), "Back, %d days after leaving" % (clock.day() - entry.left_day))
	today_lines.append("%s is back, %d %s after leaving." % [person.name, clock.day() - entry.left_day,
			"day" if clock.day() - entry.left_day == 1 else "days"])
	returned.emit(person, entry)


## Left, reformed and came back in the last week.
func week() -> Dictionary:
	var since := clock.day() - WEEK
	var out := {"left": 0, "reformed": 0, "back": 0}
	for entry in alumni:
		if entry.left_day > since:
			out.left += 1
			if entry.reform >= Reform.REFORMED_LINE:
				out.reformed += 1
		if entry.get("returned", false) and entry.will_return_day > since:
			out.back += 1
	return out


## Runs at midnight: today's lines become yesterday's, and the morning
## post brings any postcards due.
func nightly() -> void:
	yesterday_lines = today_lines
	today_lines = []
	for entry in alumni:
		if entry.postcard_day != -1 and entry.postcard_day <= clock.day():
			entry.postcard_day = -1
			_send_postcard(entry)


## Lines for the morning report.
func report_lines() -> Array[String]:
	var out: Array[String] = yesterday_lines.duplicate()
	for card in postcards:
		if card.day == clock.day():
			out.append("A postcard from %s: \"%s\"" % [card.from, card.text])
	return out


## When leavers set off, in hours.
func leave_hour() -> float:
	return regime.hour_of(&"release") if regime != null else float(LEAVE_HOUR)


## The morning's leavers are told about (main calls this for the regime's
## release time).
func announce() -> void:
	var count := due().size()
	if count > 0:
		going.emit(count)


func _on_hour(hour: int) -> void:
	if hour == LEAVE_HOUR and regime == null:
		announce()


## Moves leavers along, and sets off anyone due.
func _look() -> void:
	var minute := clock.minute_of_day()
	if minute >= leave_hour() * 60 and minute < LAST_HOUR * 60:
		for person in due():
			_set_off(person)
	for person: Person in _leaving.keys():
		if not people.people.has(person):
			_leaving.erase(person)
			continue
		var entry: Array = _leaving[person]
		entry[1] += 1.0
		match entry[0]:
			Stage.TO_RECEPTION:
				var here := people.room_of(person)
				var there: bool = not here.is_empty() and (here[1] as Room).type == Intake.RECEPTION
				if (there and person.state == Person.State.IDLE) or entry[1] >= WALK_LIMIT:
					people.stop(person)
					_leaving[person] = [Stage.SIGNING, 0.0]
				elif person.state == Person.State.IDLE:
					_walk_to_reception(person)
			Stage.SIGNING:
				person.activity = "Signing out and getting their own clothes back"
				if entry[1] >= SIGN_OUT_MINUTES:
					_head_out(person)
			Stage.TO_EXIT:
				var exit := _exit()
				if exit.is_empty() or person.flat().distance_to(exit[1]) <= 1.5 or entry[1] >= WALK_LIMIT:
					if _uses_bus():
						people.stop(person)
						_leaving[person] = [Stage.AT_STOP, 0.0]
					else:
						_leave(person)
				elif person.state == Person.State.IDLE:
					_head_out(person, false)
			Stage.AT_STOP:
				person.activity = "Waiting for the bus home"
				if intake.bus_parked() or entry[1] >= BUS_WAIT:
					_leave(person)


func _set_off(person: Person) -> void:
	if person.led or person.lying or person.going_home:
		return
	var file := PrisonerFile.of(person)
	var reception := _reception()
	if reception.is_empty() and clock.day() <= file.release_day:
		return # No reception: they wait a day, then walk out anyway.
	person.going_home = true
	people.stop(person)
	if reception.is_empty():
		_head_out(person)
		return
	_leaving[person] = [Stage.TO_RECEPTION, 0.0]
	_walk_to_reception(person)


func _walk_to_reception(person: Person) -> void:
	var room := _reception()
	if room.is_empty():
		return
	for attempt in 6:
		var tile: Vector2i = room[1].cells[_rng.randi() % room[1].cells.size()]
		if people.walk_to(person, room[0], Vector2(tile) + Vector2(0.5, 0.5), "Going home today"):
			return


func _head_out(person: Person, fresh := true) -> void:
	if fresh:
		_leaving[person] = [Stage.TO_EXIT, 0.0]
	var exit := _exit()
	if exit.is_empty() or not people.walk_to(person, exit[0], exit[1], "Going home today"):
		person.activity = "Going home today"


## Where leavers head: the bus stop, or the entrance.
func _exit() -> Array:
	return intake.arrival_spot()


## Whether leavers wait for the bus: there's a road for it to come on.
func _uses_bus() -> bool:
	return intake.vehicles != null and intake.vehicles.has_route_to(intake.stop_point())


func _reception() -> Array:
	for n: int in building.levels:
		for room: Room in building.levels[n].rooms():
			if room.type == Intake.RECEPTION:
				return [n, room]
	return []


## They go: the bed frees, and they're remembered.
func _leave(person: Person) -> void:
	_leaving.erase(person)
	var entry := _record(person)
	people.remove_person(person)
	people.assign_beds()
	left.emit(entry)


func _record(person: Person) -> Dictionary:
	var file := PrisonerFile.of(person)
	var value := reform.value(person)
	var reformed := value >= Reform.REFORMED_LINE
	var today := clock.day()
	var traits: Array[StringName] = []
	for t in person.traits:
		traits.append(t.id)
	var def := _postcard_def(file)
	var plan: String = def.plans[_rng.randi() % def.plans.size()] if def != null and not def.plans.is_empty() else "start again"
	var entry := {
		"id": person.id, "name": person.name,
		"look": person.look_seed if person.look_seed >= 0 else person.id,
		"category": person.category, "traits": traits, "reform": value,
		"best_skill": file.best_skill(), "skills": file.skills.duplicate(),
		"passed": file.passed.duplicate(), "left_day": today, "came_back": file.came_back,
		"parole": person.profile.get("paroled", false), "plan": plan, "will_return_day": -1, "postcard_day": -1,
	}
	if reformed:
		ledger.add(REFORM_BONUS, "Reform bonus")
		if _rng.randf() < POSTCARD_CHANCE:
			entry.postcard_day = today + _rng.randi_range(POSTCARD_DAYS.x, POSTCARD_DAYS.y)
	if _rng.randf() < return_chance(person):
		entry.will_return_day = today + _rng.randi_range(RETURN_DAYS.x, RETURN_DAYS.y)
	alumni.push_front(entry)
	if alumni.size() > ALUMNI_KEPT:
		alumni.resize(ALUMNI_KEPT)
	var how := "on parole" if entry.parole else "at the end of their sentence"
	today_lines.append("%s went home %s%s to %s." % [person.name, how,
			", reformed," if reformed else "", plan])
	if reformed:
		today_lines.append("Reform bonus: %s." % Ledger.text(REFORM_BONUS))
	return entry


## The card for someone's best skill or a course they passed, or a general one.
func _postcard_def(file: PrisonerFile) -> PostcardDef:
	var keys: Array = []
	if file.best_skill() != &"":
		keys.append(file.best_skill())
	keys.append_array(file.passed)
	var general: PostcardDef = null
	for key: StringName in keys:
		for def in postcard_defs:
			if def.key == key:
				return def
	for def in postcard_defs:
		if def.key == &"":
			general = def
	return general


func _send_postcard(entry: Dictionary) -> void:
	var file := PrisonerFile.new()
	file.profile = {"skills": entry.skills, "passed": entry.passed}
	var def := _postcard_def(file)
	if def == null or def.lines.is_empty():
		return
	var line: String = def.lines[_rng.randi() % def.lines.size()]
	var card := {"day": clock.day(), "from": entry.name, "id": entry.id,
			"text": line.format({"name": (entry.name as String).get_slice(" ", 0)})}
	postcards.push_front(card)
	if postcards.size() > POSTCARDS_KEPT:
		postcards.resize(POSTCARDS_KEPT)
	postcard_came.emit(card)
