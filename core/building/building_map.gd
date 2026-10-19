class_name BuildingMap
extends RefCounted
## Everything built on a grid: floors in cells, walls and doors on the edges
## between cells (like The Sims), and objects covering one or more cells.
## Pure data with no nodes, so it can be tested on its own and saved later.
##
## Cells are Vector2i(x, z). Corners are Vector2i too: corner (x, z) is the
## top-left corner of cell (x, z). Edges are Vector3i(x, z, axis):
## - EDGE_X runs along X from corner (x, z) to (x + 1, z),
##   between cells (x, z - 1) and (x, z).
## - EDGE_Z runs along Z from corner (x, z) to (x, z + 1),
##   between cells (x - 1, z) and (x, z).

signal changed

const EDGE_X := 0
const EDGE_Z := 1
const NO_EDGE := Vector3i(-1, -1, -1)
const DIRECTIONS: Array[Vector2i] = [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP]

enum Wall { NONE, WALL, DOOR }


class PlacedObject:
	var id: int
	var def: ObjectDef
	var origin: Vector2i
	var rotation: int ## Quarter turns, 0 to 3.
	var cells: Array[Vector2i]


var size: Vector2i
var floors: Dictionary[Vector2i, StringName] = {}
var walls: Dictionary[Vector3i, int] = {} ## Values are Wall.WALL or Wall.DOOR.
var objects: Dictionary[int, PlacedObject] = {}

var _occupancy: Dictionary[Vector2i, int] = {} ## Cell to object id.
## Room types are stored per cell, so they survive rooms being split, merged
## or extended: each room takes the type most of its cells carry.
var _room_types: Dictionary[Vector2i, StringName] = {}
var _next_object_id := 1
var _rooms: Array[Room] = []
var _room_lookup: Dictionary[Vector2i, Room] = {}
var _rooms_dirty := true


func _init(map_size: Vector2i) -> void:
	size = map_size


func in_bounds(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < size.x and cell.y < size.y


#region Geometry helpers

## The edge shared by two neighbouring cells, or NO_EDGE if they do not touch.
static func edge_between(a: Vector2i, b: Vector2i) -> Vector3i:
	match b - a:
		Vector2i.RIGHT: return Vector3i(b.x, b.y, EDGE_Z)
		Vector2i.LEFT: return Vector3i(a.x, a.y, EDGE_Z)
		Vector2i.DOWN: return Vector3i(b.x, b.y, EDGE_X)
		Vector2i.UP: return Vector3i(a.x, a.y, EDGE_X)
	return NO_EDGE


## The two cells either side of an edge. Either may be outside the map.
static func edge_cells(edge: Vector3i) -> Array[Vector2i]:
	if edge.z == EDGE_X:
		return [Vector2i(edge.x, edge.y - 1), Vector2i(edge.x, edge.y)]
	return [Vector2i(edge.x - 1, edge.y), Vector2i(edge.x, edge.y)]


## The edges along a straight line between two corners. Returns nothing if
## the corners are not in a line along X or Z.
static func edges_on_line(from: Vector2i, to: Vector2i) -> Array[Vector3i]:
	var out: Array[Vector3i] = []
	if from.y == to.y:
		for x in range(mini(from.x, to.x), maxi(from.x, to.x)):
			out.append(Vector3i(x, from.y, EDGE_X))
	elif from.x == to.x:
		for z in range(mini(from.y, to.y), maxi(from.y, to.y)):
			out.append(Vector3i(from.x, z, EDGE_Z))
	return out


## The edges around the outside of a rectangle of cells.
static func rect_perimeter(rect: Rect2i) -> Array[Vector3i]:
	var out: Array[Vector3i] = []
	out.append_array(edges_on_line(rect.position, Vector2i(rect.end.x, rect.position.y)))
	out.append_array(edges_on_line(Vector2i(rect.position.x, rect.end.y), rect.end))
	out.append_array(edges_on_line(rect.position, Vector2i(rect.position.x, rect.end.y)))
	out.append_array(edges_on_line(Vector2i(rect.end.x, rect.position.y), rect.end))
	return out


## Every edge inside or around a rectangle of cells.
static func rect_edges(rect: Rect2i) -> Array[Vector3i]:
	var out: Array[Vector3i] = []
	for z in range(rect.position.y, rect.end.y + 1):
		for x in range(rect.position.x, rect.end.x):
			out.append(Vector3i(x, z, EDGE_X))
	for z in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x + 1):
			out.append(Vector3i(x, z, EDGE_Z))
	return out


static func cells_in(rect: Rect2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for z in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			out.append(Vector2i(x, z))
	return out


## The smallest rectangle covering both cells.
static func rect_between(a: Vector2i, b: Vector2i) -> Rect2i:
	return Rect2i(a.min(b), (a - b).abs() + Vector2i.ONE)


## The cells an object covers when placed at origin with the given rotation.
static func footprint(def: ObjectDef, origin: Vector2i, rotation: int) -> Array[Vector2i]:
	var extent := def.size if rotation % 2 == 0 else Vector2i(def.size.y, def.size.x)
	return cells_in(Rect2i(origin, extent))

#endregion

#region Floors

func has_floor(cell: Vector2i) -> bool:
	return floors.has(cell)


func fill_floor(rect: Rect2i, type: StringName = &"concrete") -> int:
	var count := _fill_floor(rect, type)
	if count > 0:
		_changed()
	return count


## Removes floor, and anything standing on it, from a rectangle.
func clear_floor(rect: Rect2i) -> int:
	var count := _clear_floor(rect)
	if count > 0:
		_changed()
	return count

#endregion

#region Walls and doors

func edge_in_bounds(edge: Vector3i) -> bool:
	if edge.z == EDGE_X:
		return edge.x >= 0 and edge.x < size.x and edge.y >= 0 and edge.y <= size.y
	return edge.x >= 0 and edge.x <= size.x and edge.y >= 0 and edge.y < size.y


func wall_at(edge: Vector3i) -> int:
	return walls.get(edge, Wall.NONE)


## Can people walk from one cell to its neighbour? Walls block; doors do not.
func can_walk_between(a: Vector2i, b: Vector2i) -> bool:
	var edge := edge_between(a, b)
	return edge != NO_EDGE and in_bounds(a) and in_bounds(b) and wall_at(edge) != Wall.WALL


## Can a wall go on this edge? Not off the map, and not through an object.
func can_build_wall(edge: Vector3i) -> bool:
	if not edge_in_bounds(edge):
		return false
	var sides := edge_cells(edge)
	var a: int = _occupancy.get(sides[0], 0)
	return a == 0 or a != _occupancy.get(sides[1], 0)


## Builds walls on empty edges. Existing walls and doors are left alone.
func build_walls(edges: Array[Vector3i]) -> int:
	var count := _build_walls(edges)
	if count > 0:
		_changed()
	return count


func remove_walls(edges: Array[Vector3i]) -> int:
	var count := 0
	for edge in edges:
		if walls.erase(edge):
			count += 1
	if count > 0:
		_changed()
	return count


## Turns a wall into a door, or a door back into a wall.
func set_door(edge: Vector3i, is_door: bool) -> bool:
	if wall_at(edge) == Wall.NONE:
		return false
	var kind := Wall.DOOR if is_door else Wall.WALL
	if walls[edge] == kind:
		return false
	walls[edge] = kind
	_changed()
	return true

#endregion

#region Objects

func can_place(def: ObjectDef, origin: Vector2i, rotation: int) -> bool:
	var cells := footprint(def, origin, rotation)
	for cell in cells:
		if not has_floor(cell) or _occupancy.has(cell):
			return false
	# An object cannot straddle a wall or door.
	for cell in cells:
		for step: Vector2i in [Vector2i.RIGHT, Vector2i.DOWN]:
			if cells.has(cell + step) and wall_at(edge_between(cell, cell + step)) != Wall.NONE:
				return false
	return true


## Places an object and returns its id, or 0 if it does not fit.
func place_object(def: ObjectDef, origin: Vector2i, rotation: int) -> int:
	if not can_place(def, origin, rotation):
		return 0
	var placed := PlacedObject.new()
	placed.id = _next_object_id
	_next_object_id += 1
	placed.def = def
	placed.origin = origin
	placed.rotation = posmod(rotation, 4)
	placed.cells = footprint(def, origin, rotation)
	objects[placed.id] = placed
	for cell in placed.cells:
		_occupancy[cell] = placed.id
	_changed()
	return placed.id


func remove_object(id: int) -> bool:
	if not _remove_object(id):
		return false
	_changed()
	return true


func object_at(cell: Vector2i) -> PlacedObject:
	return objects.get(_occupancy.get(cell, 0))


func objects_in_room(room: Room) -> Array[PlacedObject]:
	var out: Array[PlacedObject] = []
	for placed: PlacedObject in objects.values():
		if room_at(placed.origin) == room:
			out.append(placed)
	return out

#endregion

#region Rooms

func rooms() -> Array[Room]:
	_update_rooms()
	return _rooms


## The room a cell belongs to, or null if the cell has no floor.
func room_at(cell: Vector2i) -> Room:
	_update_rooms()
	return _room_lookup.get(cell)


## Marks a room as a type. An empty type clears it.
func set_room_type(room: Room, type: StringName) -> void:
	for cell in room.cells:
		if type.is_empty():
			_room_types.erase(cell)
		else:
			_room_types[cell] = type
	_changed()

#endregion

#region Compound actions

## Floor plus walls all round, like the room tool in Software Inc.
func build_room(rect: Rect2i, floor_type: StringName = &"concrete") -> void:
	var count := _fill_floor(rect, floor_type) + _build_walls(rect_perimeter(rect))
	if count > 0:
		_changed()


## Clears a rectangle: objects, floor, and every wall and door in or around it.
func demolish(rect: Rect2i) -> void:
	var count := _clear_floor(rect)
	for edge in rect_edges(rect):
		if walls.erase(edge):
			count += 1
	if count > 0:
		_changed()

#endregion


func _fill_floor(rect: Rect2i, type: StringName) -> int:
	var count := 0
	for cell in cells_in(rect):
		if in_bounds(cell) and floors.get(cell) != type:
			floors[cell] = type
			count += 1
	return count


func _clear_floor(rect: Rect2i) -> int:
	var count := 0
	for cell in cells_in(rect):
		if _remove_object(_occupancy.get(cell, 0)):
			count += 1
		if floors.erase(cell):
			count += 1
		_room_types.erase(cell)
	return count


func _build_walls(edges: Array[Vector3i]) -> int:
	var count := 0
	for edge in edges:
		if wall_at(edge) == Wall.NONE and can_build_wall(edge):
			walls[edge] = Wall.WALL
			count += 1
	return count


func _remove_object(id: int) -> bool:
	var placed: PlacedObject = objects.get(id)
	if placed == null:
		return false
	for cell in placed.cells:
		_occupancy.erase(cell)
	objects.erase(id)
	return true


func _changed() -> void:
	_rooms_dirty = true
	changed.emit()


## Flood-fills the floor into rooms. Walls and doors split rooms; reaching a
## cell with no floor without passing a wall means the room is not enclosed.
func _update_rooms() -> void:
	if not _rooms_dirty:
		return
	_rooms_dirty = false
	_rooms.clear()
	_room_lookup.clear()
	for start: Vector2i in floors:
		if _room_lookup.has(start):
			continue
		var room := Room.new()
		room.id = _rooms.size()
		_room_lookup[start] = room
		var stack: Array[Vector2i] = [start]
		while not stack.is_empty():
			var cell: Vector2i = stack.pop_back()
			room.cells.append(cell)
			for step in DIRECTIONS:
				var next := cell + step
				if wall_at(edge_between(cell, next)) != Wall.NONE:
					continue
				if not floors.has(next):
					room.enclosed = false
				elif not _room_lookup.has(next):
					_room_lookup[next] = room
					stack.append(next)
		_settle_room_type(room)
		_rooms.append(room)


## Gives a room the type most of its cells carry, and spreads it to the rest.
func _settle_room_type(room: Room) -> void:
	var votes := {}
	for cell in room.cells:
		var type: StringName = _room_types.get(cell, &"")
		if not type.is_empty():
			votes[type] = votes.get(type, 0) + 1
	var best: StringName = &""
	for type: StringName in votes:
		if best.is_empty() or votes[type] > votes[best]:
			best = type
	room.type = best
	if best.is_empty():
		return
	for cell in room.cells:
		_room_types[cell] = best
