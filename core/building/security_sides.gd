class_name SecuritySides
extends RefCounted
## Security lines between zones: each zone may be on a side (ZoneDef.side),
## such as landside or airside in an airport. A door between rooms on two
## different sides has to be a checkpoint (DoorKindDef.checkpoint), such
## as a screening point or a badge door; any other is flagged red in the
## zone view, as a gap in the line. Ground outside rooms is on no side.
## A one-way door that only lets people out of a side in `exit_sides` is
## fine too: an arrivals exit from airside to landside, say.

var access: Access
var building: Building
## Sides people may leave freely through a one-way door.
var exit_sides: Array[StringName] = []


## The side a room is on, or empty for none.
func side_of(room: Room) -> StringName:
	var zone := access.zone_of(room) if access != null else null
	return zone.side if zone != null else &""


## Every door on a level that crosses a security line without being a
## checkpoint, as edges.
func gaps(level: int) -> Array[Vector3i]:
	var out: Array[Vector3i] = []
	var map: BuildingMap = building.levels.get(level) if building != null else null
	if map == null:
		return out
	for edge: Vector3i in map.walls:
		if map.walls[edge] != BuildingMap.Wall.DOOR:
			continue
		var cells := BuildingMap.edge_cells(edge)
		var sides: Array[StringName] = []
		for cell in cells:
			sides.append(side_of(map.room_at(cell)) if map.has_floor(cell) else &"")
		if sides[0].is_empty() or sides[1].is_empty() or sides[0] == sides[1]:
			continue
		var way := map.door_way(edge)
		if way != 0 and exit_sides.has(sides[0] if way == 1 else sides[1]):
			continue
		var kind: DoorKindDef = access.door_kinds.get(map.door_kind_at(edge))
		if kind == null or not kind.checkpoint:
			out.append(edge)
	return out


## Every gap on every level, as (level, edge x, edge y, edge axis).
func all_gaps() -> Array[Vector4i]:
	var out: Array[Vector4i] = []
	if building == null:
		return out
	for n: int in building.levels:
		for edge in gaps(n):
			out.append(Vector4i(n, edge.x, edge.y, edge.z))
	return out
