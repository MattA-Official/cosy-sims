class_name Escapes
extends Node
## Prisoners making a run for it. Ground outside the perimeter (see
## SecureArea) is out of bounds: a prisoner on it is out of place, and
## guards walk them back. A prisoner out of place who can walk to the edge
## of your land without crossing the perimeter may make a run for it,
## likelier the unhappier they are. The alarm goes up and the nearest
## guards give chase, a little faster than a prisoner runs. Caught, it's an
## escape attempt on their record (and the quiet room); reach the edge and
## they're gone, with a fine.

## Chance an hour that someone out of place who could get away tries,
## happy and unhappy.
const CHANCE := 0.15
const UNHAPPY_CHANCE := 0.4
const UNHAPPY_BELOW := 40.0
## Guards who give chase, how close they must be to catch, and how much
## faster they run.
const CHASERS := 2
const CATCH_DISTANCE := 1.2
const CHASE_PACE := 1.3
const FINE := 2000
## Tiles from the land edge that count as away.
const AWAY := 0.8

signal got_away(person: Person)
signal caught(person: Person, by: Person)
signal running(person: Person)
## The alarm went off with someone running, or stopped with nobody left
## running.
signal alarm_changed(on: bool)

var people: People
var jobs: JobBoard
var secure_area: SecureArea
var ledger: Ledger
var prisoner_group: StringName = &"prisoner"
var guard_role: StringName = &"guard"
var enabled := true
## Whether prisoners can walk off before any perimeter is built (Matt's
## call, 21 October): without one, anyone out of place may make for the
## edge of your land.
var without_perimeter := true
## Everyone who got away, as [name, day].
var at_large: Array = []
var clock: GameClock:
	set(value):
		clock = value
		clock.minute_passed.connect(func(_minute: int) -> void: tick())

## Prisoners running, and where to.
var runners: Dictionary[Person, Vector2] = {}
## Guards chasing, and who.
var chasers: Dictionary[Person, Person] = {}
## Sounding while anyone is running: every free guard gives chase.
var alarm := false
var _rng := RandomNumberGenerator.new()


func start() -> void:
	people.deciders.push_front(_run_or_chase)
	people.person_removed.connect(func(person: Person) -> void:
		runners.erase(person)
		chasers.erase(person)
		for guard: Person in chasers.keys():
			if chasers[guard] == person:
				_stop_chasing(guard))


## Whether walking off is possible at all just now.
func possible() -> bool:
	return enabled and (secure_area.has_perimeter or without_perimeter)


func tick() -> void:
	_catch_up()
	if not possible():
		return
	var minute := clock.minute_of_day() if clock != null else 0
	for person in people.people:
		if person.group != prisoner_group or runners.has(person) or person.led or person.going_home \
				or person.quiet_room_hours > 0.0 or Health.injury(person.health) >= Health.Injury.HURT:
			continue
		if secure_area.has_perimeter and person.level == 0 and not secure_area.is_secure(Vector2i(person.flat().floor())):
			person.out_of_place = true
		if person.out_of_place and (minute + person.id) % 60 == 30:
			var chance := UNHAPPY_CHANCE if person.mood < UNHAPPY_BELOW else CHANCE
			if _rng.randf() < chance:
				run(person)


## Makes a run for it, if there's a way out. Returns whether they're off.
func run(person: Person) -> bool:
	var way_out := exit_for(person)
	if way_out == Vector2.INF:
		return false
	people.stop(person)
	if not people.walk_to(person, 0, way_out, "Making a run for it!"):
		return false
	runners[person] = way_out
	person.bubble = "Legging it!"
	person.bubble_minutes = 0.0
	person.pace = 1.0
	var sounding := alarm
	alarm = true
	_send_chasers(person)
	running.emit(person)
	if not sounding:
		alarm_changed.emit(true)
	return true


## The nearest point on the edge of your land they can walk to without
## crossing the perimeter, or Vector2.INF.
func exit_for(person: Person) -> Vector2:
	var map := people.building.ground()
	var edges: Array[Vector2i] = []
	for cell in BuildingMap.cells_in(map.land_bounds()):
		if map.owns(cell) and not secure_area.is_secure(cell) and _at_edge(map, cell):
			edges.append(cell)
	var from := person.flat()
	edges.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return from.distance_squared_to(Vector2(a)) < from.distance_squared_to(Vector2(b)))
	for cell in edges.slice(0, 12):
		var point := Vector2(cell) + Vector2(0.5, 0.5)
		if people.can_reach(person, 0, point):
			return point
	return Vector2.INF


func _at_edge(map: BuildingMap, cell: Vector2i) -> bool:
	for step in BuildingMap.DIRECTIONS:
		if not map.owns(cell + step):
			return true
	return false


func _send_chasers(person: Person) -> void:
	var guards := people.people.filter(func(p: Person) -> bool:
		return p.role == guard_role and not p.going_home and not chasers.has(p) \
				and Health.injury(p.health) < Health.Injury.HURT)
	guards.sort_custom(func(a: Person, b: Person) -> bool:
		return a.flat().distance_squared_to(person.flat()) < b.flat().distance_squared_to(person.flat()))
	# With the alarm going, every free guard gives chase.
	for guard: Person in guards.slice(0, guards.size() if alarm else CHASERS):
		if guard.job != null:
			jobs.abandon(guard)
		people.stop(guard)
		chasers[guard] = person
		guard.pace = CHASE_PACE


## Runners who got away or were caught, and chasers keeping on their heels.
func _catch_up() -> void:
	for person: Person in runners.keys():
		var by := _caught_by(person)
		if by != null:
			_caught(person, by)
		elif person.flat().distance_to(runners[person]) <= AWAY:
			_gone(person)
		elif person.state != Person.State.WALKING:
			# Knocked off course: off again.
			people.walk_to(person, 0, runners[person], "Making a run for it!")
	for guard: Person in chasers.keys():
		var target := chasers[guard]
		if not runners.has(target):
			_stop_chasing(guard)
		else:
			people.walk_to(guard, target.level, target.flat(), "Chasing %s" % target.name.get_slice(" ", 0))
	if alarm and runners.is_empty():
		alarm = false
		alarm_changed.emit(false)


func _caught_by(person: Person) -> Person:
	for guard: Person in chasers:
		if chasers[guard] == person and guard.level == person.level \
				and guard.flat().distance_to(person.flat()) <= CATCH_DISTANCE:
			return guard
	return null


func _caught(person: Person, by: Person) -> void:
	runners.erase(person)
	person.bubble = ""
	people.stop(person)
	person.record.append([clock.day() if clock != null else 1, &"escape", "tried to escape"])
	caught.emit(person, by)


func _gone(person: Person) -> void:
	runners.erase(person)
	at_large.append([person.name, clock.day() if clock != null else 1])
	if ledger != null:
		ledger.add(-FINE, "Escape fines")
	got_away.emit(person)
	people.remove_person(person)


func _stop_chasing(guard: Person) -> void:
	chasers.erase(guard)
	guard.pace = 1.0
	if people.people.has(guard):
		people.stop(guard)


## Runners keep running and chasers keep chasing.
func _run_or_chase(person: Person, _may_wander: bool) -> bool:
	if runners.has(person):
		person.activity = "Making a run for it!"
		return true
	if chasers.has(person):
		return true
	return false
