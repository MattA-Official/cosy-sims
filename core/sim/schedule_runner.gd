class_name ScheduleRunner
extends Node
## Runs the timetables. On every hour it works out each group's block and
## puts everyone in theirs (see People.set_block); every minute it locks
## and unlocks the doors of rooms people sleep in, and marks who is out of
## place. It is the only thing besides the clock that knows the time.

signal block_changed(group: StringName, def: ActivityDef)
## Doors the timetable controls were added, removed, locked or unlocked.
signal doors_changed

## Game minutes into a block before people not where it wants them count
## as out of place.
const LATE_MINUTES := 15.0

var clock: GameClock:
	set(value):
		clock = value
		clock.hour_changed.connect(func(_hour: int) -> void: refresh())
		clock.minute_passed.connect(func(_minute: int) -> void: _every_minute())
var people: People:
	set(value):
		people = value
		people.person_added.connect(func(person: Person) -> void:
			people.set_block(person, current(person.group)))
var building: Building
## One timetable per group of people, such as &"prisoner".
var schedules: Dictionary[StringName, Schedule] = {}:
	set(value):
		schedules = value
		for schedule: Schedule in schedules.values():
			schedule.edited.connect(refresh)
## The doors the timetable controls, as (level, edge x, edge y, edge axis),
## and whether each is locked: the doors of rooms people sleep in, and any
## locked or unlocked by hand.
var doors: Dictionary[Vector4i, bool] = {}
## Doors locked (true) or unlocked (false) by hand, whatever the timetable
## says. They go back to the timetable when the block changes, unless
## pinned.
var overrides: Dictionary[Vector4i, bool] = {}
var pinned: Dictionary[Vector4i, bool] = {}
## Other doors something else controls, such as security gates: returns
## each one's key and whether it should be locked. Hand locks still win.
## Optional.
var other_locks: Callable

## What the timetable alone wants each door it controls to be.
var _planned: Dictionary[Vector4i, bool] = {}

var _current: Dictionary[StringName, ActivityDef] = {}
## Game minutes on the clock when each group's block began.
var _started: Dictionary[StringName, float] = {}


## The block a group is in now.
func current(group: StringName = &"prisoner") -> ActivityDef:
	if not _current.has(group) and schedules.has(group) and clock != null:
		_current[group] = schedules[group].at(clock.hour())
		_started[group] = clock.total_minutes
	return _current.get(group)


## Game minutes since a group's block began.
func minutes_into_block(group: StringName = &"prisoner") -> float:
	current(group)
	return clock.total_minutes - _started.get(group, clock.total_minutes)


## Works out every group's block for the hour and puts everyone in theirs.
## Called on the hour, and when a timetable is edited.
func refresh() -> void:
	for group: StringName in schedules:
		var def := schedules[group].at(clock.hour())
		if _current.get(group) != def:
			_current[group] = def
			_started[group] = clock.total_minutes
			block_changed.emit(group, def)
			for key: Vector4i in overrides.keys():
				if not pinned.has(key):
					overrides.erase(key)
	for person in people.people:
		people.set_block(person, current(person.group))
	_every_minute()


func _every_minute() -> void:
	_update_doors()
	_update_lateness()


## A room people sleep in locks once its block says so, everyone who
## sleeps there is inside and nobody else is; one nobody sleeps in locks
## whenever any block locks. Everything else is unlocked.
func _update_doors() -> void:
	var any_locks := false
	for def: ActivityDef in _current.values():
		any_locks = any_locks or (def != null and def.door_rule == ActivityDef.DoorRule.LOCK_OWN_ROOM)
	var owners: Dictionary[Room, Array] = {}
	var visitors: Dictionary[Room, bool] = {}
	for person in people.people:
		var home := people.home_room(person)
		if not home.is_empty():
			if not owners.has(home[1]):
				owners[home[1]] = []
			owners[home[1]].append(person)
		var here := people.room_of(person)
		if not here.is_empty() and (home.is_empty() or home[1] != here[1]):
			visitors[here[1]] = true
	var wanted: Dictionary[Vector4i, bool] = {}
	for n: int in building.levels:
		var map := building.levels[n]
		for room: Room in map.rooms():
			if not people.home_room_types.has(room.type):
				continue
			var lock := any_locks and not visitors.has(room)
			if owners.has(room) and lock:
				for person: Person in owners[room]:
					var here := people.room_of(person)
					if person.block == null or person.block.door_rule != ActivityDef.DoorRule.LOCK_OWN_ROOM \
							or here.is_empty() or here[1] != room:
						lock = false
						break
			for edge in room_doors(map, room):
				var key := Vector4i(n, edge.x, edge.y, edge.z)
				wanted[key] = wanted.get(key, false) or lock
	if other_locks.is_valid():
		wanted.merge(other_locks.call(), true)
	_planned = wanted.duplicate()
	for key: Vector4i in overrides.keys():
		var map := building.levels.get(key.x) as BuildingMap
		if map == null or map.wall_at(Vector3i(key.y, key.z, key.w)) != BuildingMap.Wall.DOOR:
			overrides.erase(key)
			pinned.erase(key)
		else:
			wanted[key] = overrides[key]
	var changed := wanted.size() != doors.size()
	for key: Vector4i in doors:
		if not wanted.has(key):
			people.set_door_locked(key.x, Vector3i(key.y, key.z, key.w), false)
	for key: Vector4i in wanted:
		changed = changed or doors.get(key) != wanted[key]
		people.set_door_locked(key.x, Vector3i(key.y, key.z, key.w), wanted[key])
	doors = wanted
	if changed:
		doors_changed.emit()


## Locks a door by hand if it is open, or unlocks it if locked, until the
## block changes. With `pin`, it stays that way until clicked again.
func toggle_lock(level: int, edge: Vector3i, pin := false) -> void:
	var key := Vector4i(level, edge.x, edge.y, edge.z)
	if pin and overrides.has(key):
		# Pinning (or unpinning) keeps the door as it is.
		if pinned.has(key):
			pinned.erase(key)
			overrides.erase(key)
		else:
			pinned[key] = true
	else:
		overrides[key] = not people.is_door_locked(level, edge)
		if pin:
			pinned[key] = true
		elif not pinned.has(key) and overrides[key] == _planned.get(key, false):
			# Back to what the timetable wants, so no longer overridden.
			overrides.erase(key)
	_update_doors()
	doors_changed.emit()


func _update_lateness() -> void:
	for person in people.people:
		var late := minutes_into_block(person.group) >= LATE_MINUTES
		person.out_of_place = (late and not people.is_in_place(person)) or person.truant_minutes > 0.0


## The doors on the straight walls round a room.
static func room_doors(map: BuildingMap, room: Room) -> Array[Vector3i]:
	var out: Array[Vector3i] = []
	for cell in room.cells:
		for d in BuildingMap.DIRECTIONS:
			var edge := BuildingMap.edge_between(cell, cell + d)
			if map.wall_at(edge) == BuildingMap.Wall.DOOR and not out.has(edge):
				out.append(edge)
	return out
