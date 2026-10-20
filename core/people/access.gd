class_name Access
extends RefCounted
## Who may go where. Each room's zone says which groups of people may be in
## it, a staff door lets only staff through, and a locked door stops anyone
## without keys. Ground outside any room is open to everyone.
##
## Everyone shares one walking graph, so before finding someone a way, the
## graph is set up for their group: the floor of rooms they may not enter
## is shut, and so are doors they can't pass. Only what differs from the
## group set up last changes, so going from one group to the next is cheap.

## Every zone, by id.
var zones: Dictionary[StringName, ZoneDef] = {}
## The zone of rooms that are unpainted and whose type names none.
var default_zone: StringName = &""
## Every group of people, by id.
var groups: Dictionary[StringName, GroupDef] = {}
## Every kind of door, by id.
var door_kinds: Dictionary[StringName, DoorKindDef] = {}
## Room types by id, for the zone each starts with.
var room_types: Dictionary[StringName, RoomTypeDef] = {}
## Locked doors, as (level, edge x, edge y, edge axis).
var locked: Dictionary[Vector4i, bool] = {}

var _graph: NavGraph
## What is shut on the graph now: points, and doors as above.
var _shut_points: Dictionary[int, bool] = {}
var _shut_doors: Dictionary[Vector4i, bool] = {}
## What each group needs shut, as [points, doors] like the two above,
## worked out when first wanted.
var _wanted: Dictionary[StringName, Array] = {}
## The group the graph is set up for just now, or empty if unsure.
var _set_for: StringName = &""


## Forgets what each group needs shut, after a build or a lock changes.
func changed() -> void:
	_wanted.clear()
	_set_for = &""


## The zone a room is in: the one painted on it, else its type's, else
## the default. Null for no room.
func zone_of(room: Room) -> ZoneDef:
	if room == null:
		return null
	var id := room.zone
	if id.is_empty():
		var type: RoomTypeDef = room_types.get(room.type)
		if type != null:
			id = type.zone
	if id.is_empty():
		id = default_zone
	return zones.get(id)


## May people of a group be in a room? Anyone may be outside any room, or
## where no zones are set up.
func may_enter(group: StringName, room: Room) -> bool:
	var zone := zone_of(room)
	return zone == null or zone.allows(group)


## May people of a group walk through a door? Not a staff door unless they
## are staff, nor a locked one without keys.
func may_pass(group: StringName, map: BuildingMap, key: Vector4i) -> bool:
	var edge := Vector3i(key.y, key.z, key.w)
	var kind: DoorKindDef = door_kinds.get(map.door_kind_at(edge)) if map != null else null
	if kind != null and not kind.lets_through(group):
		return false
	return not locked.has(key) or has_keys(group)


func has_keys(group: StringName) -> bool:
	var def: GroupDef = groups.get(group)
	return def != null and def.has_keys


## Does someone of this group get a bed of their own? Everyone does when no
## groups are set up.
func gets_bed(group: StringName) -> bool:
	var def: GroupDef = groups.get(group)
	return def == null or def.gets_bed


## Does someone of this group have a need? Everyone has every need when
## no groups are set up.
func has_need(group: StringName, need: StringName) -> bool:
	var def: GroupDef = groups.get(group)
	return def == null or def.needs.is_empty() or def.needs.has(need)


## Locks or unlocks a door. Returns whether anything changed.
func set_locked(key: Vector4i, lock: bool) -> bool:
	if locked.has(key) == lock:
		return false
	if lock:
		locked[key] = true
	else:
		locked.erase(key)
	_wanted.clear()
	_set_for = &""
	return true


## Sets the graph up for someone of `group`. A room passed as `let_out_of`
## stays open even if they may not be there, so someone caught in the wrong
## room can still walk out of it.
func set_up(graph: NavGraph, building: Building, group: StringName,
		let_out_of: Room = null, let_out_level := 0) -> void:
	if graph != _graph:
		# A fresh graph starts with everything open.
		_graph = graph
		_shut_points.clear()
		_shut_doors.clear()
		_wanted.clear()
		_set_for = &""
	var letting_out := let_out_of != null and not may_enter(group, let_out_of)
	if group == _set_for and not letting_out:
		return
	_set_for = &"" if letting_out else group
	if not _wanted.has(group):
		_wanted[group] = _work_out(graph, building, group)
	var points: Dictionary[int, bool] = _wanted[group][0]
	var doors: Dictionary[Vector4i, bool] = _wanted[group][1]
	if letting_out:
		points = points.duplicate()
		for id in graph.points_in(let_out_level, let_out_of):
			points.erase(id)
	for id: int in _shut_points.keys():
		if not points.has(id):
			graph.set_point_shut(id, false)
			_shut_points.erase(id)
	for id: int in points:
		if not _shut_points.has(id):
			graph.set_point_shut(id, true)
			_shut_points[id] = true
	for key: Vector4i in _shut_doors.keys():
		if not doors.has(key):
			graph.set_door_locked(key.x, Vector3i(key.y, key.z, key.w), false)
			_shut_doors.erase(key)
	for key: Vector4i in doors:
		if not _shut_doors.has(key):
			graph.set_door_locked(key.x, Vector3i(key.y, key.z, key.w), true)
			_shut_doors[key] = true


func _work_out(graph: NavGraph, building: Building, group: StringName) -> Array:
	var points: Dictionary[int, bool] = {}
	var doors: Dictionary[Vector4i, bool] = {}
	for n: int in building.levels:
		for room: Room in building.levels[n].rooms():
			if not may_enter(group, room):
				for id in graph.points_in(n, room):
					points[id] = true
	for key in graph.doors():
		if not may_pass(group, building.levels.get(key.x), key):
			doors[key] = true
	return [points, doors]
