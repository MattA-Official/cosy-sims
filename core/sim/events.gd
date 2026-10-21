class_name Events
extends Node
## One-day events the player puts on (EventDef). On the day, residents
## whose timetable lets them go and take part at the event's objects once
## their pressing needs are seen to; everyone who took part has a great day
## when it ends at midnight. Shared by any game with residents.

## Game minutes between looks at who is taking part.
const TICK_MINUTES := 2.0

signal scheduled_changed
## An event ended, with everyone who took part.
signal finished(def: EventDef, attended: Array[Person])

var people: People
var ledger: Ledger
var defs: Array[EventDef] = []
## Groups who take part.
var groups: Array[StringName] = [&"prisoner"]
## Lets a resident take part, if set: (person, def) -> bool, such as
## having the hobby.
var may_take_part: Callable
## The need taking part fills (Fun).
var fun_need: StringName = &"recreation"
## Day -> event id. One event a day.
var scheduled: Dictionary[int, StringName] = {}
## Who has taken part today, by person id.
var attended: Dictionary[int, bool] = {}
var clock: GameClock:
	set(value):
		clock = value
		clock.minute_passed.connect(func(_minute: int) -> void:
			_wait -= 1.0
			if _wait <= 0.0:
				_wait = TICK_MINUTES
				tick())
		clock.day_changed.connect(func(day: int) -> void: end_day(day - 1))

var _wait := 0.0


func attach() -> void:
	people.deciders.append(decide)


func def_of(id: StringName) -> EventDef:
	for def in defs:
		if def.id == id:
			return def
	return null


## Today's event, or null.
func today() -> EventDef:
	return def_of(scheduled.get(_today(), &""))


## Puts an event on a day, paying for it. False if that day is taken, it
## is in the past, or there isn't the money.
func schedule(def: EventDef, day: int) -> bool:
	if scheduled.has(day) or day < _today():
		return false
	if ledger != null:
		if not ledger.can_spend():
			return false
		ledger.add(-def.cost, "Events")
	scheduled[day] = def.id
	scheduled_changed.emit()
	return true


## Calls an event off, giving the money back if it hasn't started.
func cancel(day: int) -> void:
	var def := def_of(scheduled.get(day, &""))
	if def == null or day < _today() or (day == _today() and not attended.is_empty()):
		return
	scheduled.erase(day)
	if ledger != null:
		ledger.add(def.cost, "Events")
	scheduled_changed.emit()


## The days ahead with something on, soonest first, as [day, def].
func upcoming() -> Array:
	var out: Array = []
	var days := scheduled.keys()
	days.sort()
	for day: int in days:
		if day >= _today():
			out.append([day, def_of(scheduled[day])])
	return out


## Notes who is taking part at the event's objects.
func tick() -> void:
	var def := today()
	if def == null or people == null:
		return
	for person in people.people:
		if not groups.has(person.group) or person.state != Person.State.USING or not person.has_object():
			continue
		var placed := people.target_object(person)
		if placed != null and placed.def.tags.any(func(tag: StringName) -> bool: return def.object_tags.has(tag)):
			attended[person.id] = true


## On the day, anyone free to go who may take part heads to the event.
func decide(person: Person, _may_wander: bool) -> bool:
	var def := today()
	if def == null or not groups.has(person.group) or attended.has(person.id) or person.job != null:
		return false
	if may_take_part.is_valid() and not may_take_part.call(person, def):
		return false
	if people._urgent_need(person) != &"" or person.block == null \
			or not def.object_tags.any(func(tag: StringName) -> bool: return person.block.allowed_tags.has(tag)):
		return false
	if people.seek(person, def.object_tags, fun_need):
		person.reason = "Off to the %s" % def.display_name.to_lower()
		return true
	return false


## Ends a day's event: everyone who took part gets its moodlet.
func end_day(day: int) -> void:
	var def := def_of(scheduled.get(day, &""))
	if def == null:
		attended.clear()
		return
	var came: Array[Person] = []
	if people != null:
		for person in people.people:
			if attended.has(person.id):
				came.append(person)
				people.add_moodlet(person, def.moodlet)
	scheduled.erase(day)
	attended.clear()
	finished.emit(def, came)
	scheduled_changed.emit()


func capture() -> Dictionary:
	var days := {}
	for day: int in scheduled:
		days[str(day)] = String(scheduled[day])
	return {"scheduled": days, "attended": attended.keys()}


func restore(data: Dictionary) -> void:
	scheduled.clear()
	var days: Dictionary = data.get("scheduled", {})
	for day: String in days:
		scheduled[int(day)] = StringName(days[day])
	attended.clear()
	for id in data.get("attended", []):
		attended[int(id)] = true
	scheduled_changed.emit()


func _today() -> int:
	return clock.day() if clock != null else 0
