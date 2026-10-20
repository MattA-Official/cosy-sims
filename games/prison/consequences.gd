class_name Consequences
extends Node
## What happens after an offence goes on someone's record. Each offence
## scores points (grumbling none, a fight 3) that fade by one a day. The
## first minor one is a warning; after that they lose a privilege (the yard,
## the telly, games and the gym) for a few days, two once it adds up. A
## fight or an escape attempt means a day in the quiet room, if there is
## one: a guard walks them there and they stay put, meals passed in. Too
## many points at midnight moves them up a security category; a clean
## week moves them down.

## Points each kind of offence scores, by record id.
const POINTS: Dictionary[StringName, float] = {
	&"grumble": 0.0, &"mischief": 1.0, &"contraband": 2.0, &"vandalism": 2.0, &"fight": 3.0, &"escape": 5.0,
}
## Offences that mean the quiet room.
const SERIOUS: Array[StringName] = [&"fight", &"escape"]
const QUIET_ROOM_HOURS := 24.0
## Without a quiet room, serious offences cost this many privileges for
## this many days instead.
const SERIOUS_PRIVILEGES := 2
const SERIOUS_DAYS := 3.0
## Points fading a day, and the thresholds for moving category.
const FADE := 1.0
const UP_ABOVE := 8.0
const DOWN_BELOW := 1.0
const CLEAN_DAYS := 7
## Needs kept up in the quiet room: meals come through the hatch and
## there's a toilet and a bed.
const QUIET_ROOM_NEEDS := 40.0
## Categories from lowest to highest security.
const CATEGORY_ORDER: Array[StringName] = [&"low", &"medium", &"high"]

signal punished(person: Person, words: String)

var people: People
var guarding: Guarding
var prisoner_group: StringName = &"prisoner"
var quiet_room_type: StringName = &"quiet_room"
var quiet_room_moodlet: StringName = &"in_the_quiet_room"
## Policies, set in the warden's office.
var privilege_days := 2.0
var quiet_room_on := true
## Privileges in the order they're taken away.
var privilege_order: Array[StringName] = [&"yard", &"tv", &"games"]
var clock: GameClock:
	set(value):
		clock = value
		clock.minute_passed.connect(func(_minute: int) -> void: tick(1.0))
		clock.day_changed.connect(func(_day: int) -> void: new_day())

## How many record entries each person had last time we looked.
var _seen: Dictionary[Person, int] = {}
## Days in a row someone has been under DOWN_BELOW points.
var _clean_days: Dictionary[Person, int] = {}


func start() -> void:
	people.deciders.push_front(_quiet)
	people.person_removed.connect(func(person: Person) -> void:
		_seen.erase(person)
		_clean_days.erase(person))
	# Whatever is already on the record (such as from a save) has been
	# dealt with.
	people.person_added.connect(func(person: Person) -> void: _seen[person] = person.record.size())
	for person in people.people:
		_seen[person] = person.record.size()


## New offences, and time in the quiet room.
func tick(minutes: float) -> void:
	for person in people.people:
		if person.group != prisoner_group:
			continue
		var seen: int = _seen.get(person, 0)
		if person.record.size() > seen:
			_seen[person] = person.record.size()
			for entry: Array in person.record.slice(seen):
				offence(person, entry[1])
		if person.quiet_room_hours > 0.0:
			_in_quiet_room(person, minutes)


## Deals with one offence.
func offence(person: Person, kind: StringName) -> void:
	var points: float = POINTS.get(kind, 1.0)
	if points <= 0.0:
		return
	var before := person.points
	person.points += points
	if SERIOUS.has(kind):
		if quiet_room_on and send_to_quiet_room(person):
			return
		_take_privileges(person, SERIOUS_PRIVILEGES, SERIOUS_DAYS)
	elif before <= 0.0 and person.points <= 1.0:
		person.bubble = "Warned"
		person.bubble_minutes = 20.0
		punished.emit(person, "a warning")
	elif person.points <= 3.0:
		_take_privileges(person, 1, privilege_days)
	else:
		_take_privileges(person, 2, privilege_days)


## Has a guard walk them to the quiet room. Returns false if there isn't
## one free.
func send_to_quiet_room(person: Person) -> bool:
	var spot := _quiet_room_spot(person)
	if spot.is_empty():
		return false
	person.quiet_room_hours = QUIET_ROOM_HOURS
	if not in_quiet_room(person):
		guarding.escort(person, spot, "to the quiet room", quiet_room_moodlet)
	else:
		people.add_moodlet(person, quiet_room_moodlet)
	punished.emit(person, "a day in the quiet room")
	return true


## Lets them out of the quiet room early, and gives back what they lost.
func let_off(person: Person) -> void:
	person.restrictions.clear()
	if person.quiet_room_hours > 0.0:
		_release(person)
	people.set_block(person, person.block)


func in_quiet_room(person: Person) -> bool:
	var here := people.room_of(person)
	return not here.is_empty() and (here[1] as Room).type == quiet_room_type


## Midnight: restrictions run down, points fade, categories move.
func new_day() -> void:
	for person in people.people:
		if person.group != prisoner_group:
			continue
		for id: StringName in person.restrictions.keys():
			person.restrictions[id] -= 1.0
			if person.restrictions[id] <= 0.0:
				person.restrictions.erase(id)
		if person.points > UP_ABOVE:
			_move_category(person, 1)
		person.points = maxf(0.0, person.points - FADE)
		_clean_days[person] = _clean_days.get(person, 0) + 1 if person.points < DOWN_BELOW else 0
		if _clean_days[person] >= CLEAN_DAYS:
			_clean_days[person] = 0
			_move_category(person, -1)


func _take_privileges(person: Person, count: int, days: float) -> void:
	var taken: Array[String] = []
	for id in privilege_order:
		if taken.size() >= count:
			break
		if person.restrictions.has(id):
			continue
		person.restrictions[id] = days
		var def: PrivilegeDef = people.privileges.get(id)
		taken.append(def.display_name.to_lower() if def != null else String(id))
	if taken.is_empty():
		return
	# Swapped blocks take effect straight away.
	people.set_block(person, person.block)
	punished.emit(person, "lost %s for %d days" % [" and ".join(taken), roundi(days)])


func _move_category(person: Person, step: int) -> void:
	var at := CATEGORY_ORDER.find(person.category)
	if at == -1:
		return
	var to := clampi(at + step, 0, CATEGORY_ORDER.size() - 1)
	if to == at:
		return
	person.category = CATEGORY_ORDER[to]
	people.redraw(person)
	punished.emit(person, "moved %s to %s security" % ["up" if step > 0 else "down", CATEGORY_ORDER[to]])


func _in_quiet_room(person: Person, minutes: float) -> void:
	if not in_quiet_room(person):
		# On the way, or slipped out: back they go.
		if not person.led and not guarding.jobs.of_kind(&"escort").any(func(j: Job) -> bool:
				return j.get_meta(&"prisoner") == person):
			var spot := _quiet_room_spot(person)
			if spot.is_empty():
				person.quiet_room_hours = 0.0
			else:
				guarding.escort(person, spot, "to the quiet room", &"")
		return
	person.quiet_room_hours -= minutes / 60.0
	for need: StringName in person.needs:
		person.needs[need] = maxf(person.needs[need], QUIET_ROOM_NEEDS)
	if person.quiet_room_hours <= 0.0:
		_release(person)


func _release(person: Person) -> void:
	person.quiet_room_hours = 0.0
	person.temper = 0.0
	person.moodlets.erase(quiet_room_moodlet)
	people.stop(person)


## In the quiet room they stay put.
func _quiet(person: Person, _may_wander: bool) -> bool:
	if person.quiet_room_hours <= 0.0 or not in_quiet_room(person):
		return false
	person.activity = "In the quiet room"
	person.reason = "Sent here for %d more hours" % ceili(person.quiet_room_hours)
	return true


## A tile in a quiet room nobody else is in, as [level, tile], or [].
func _quiet_room_spot(person: Person) -> Array:
	for level: int in people.building.levels:
		var map: BuildingMap = people.building.levels[level]
		for room in map.rooms():
			if room.type != quiet_room_type:
				continue
			var taken := people.people.any(func(other: Person) -> bool:
				return other != person and other.quiet_room_hours > 0.0 and other.level == level \
						and map.room_at_point(other.flat()) == room)
			if not taken:
				return [level, room.cells[room.cells.size() / 2]]
	return []
