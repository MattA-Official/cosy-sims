class_name BuildClip
extends RefCounted
## A piece of building picked up to move, copy or keep as a template:
## floor, straight walls with their doors, windows and paint, floor objects
## with whatever stands on them, and the rooms' types and zones. Everything
## is kept relative to the top-left of its box, so it can be turned in
## quarter turns and put down anywhere.
##
## Angled walls, stairs and ramps stay where they are.

## The box everything sits in, in tiles.
var size := Vector2i.ONE
## Floor by cell: [style, height above the lowest floor in the clip].
var floors: Dictionary[Vector2i, Array] = {}
## Straight walls as [cell, cell across it, kind, style, window kind, door
## kind, paint facing the first cell, paint facing the second].
var walls: Array = []
## Floor objects as [def, middle, turn, look, things], where things are
## [def, spot, turn from the surface, look] for what stands on it.
var objects: Array = []
## Room types and zones by cell.
var types: Dictionary[Vector2i, StringName] = {}
var zones: Dictionary[Vector2i, StringName] = {}
## Ids of the objects picked up, in the order of `objects`, while the clip
## came off the map; empty for copies and templates.
var ids: Array[int] = []
## Where the clip's top-left came off the map, and the floor it took up
## there, while it's being moved.
var from := Vector2i.ZERO
var taken: Array[Vector2i] = []


## Picks up some cells (their floor and every wall round or between them)
## and some objects. Walls only come with floor. Objects on surfaces come
## with their surface.
static func capture(map: BuildingMap, cells: Array[Vector2i], picked: Array) -> BuildClip:
	var clip := BuildClip.new()
	var floored: Array[Vector2i] = []
	for cell in cells:
		if map.has_floor(cell):
			floored.append(cell)
	var surfaces: Array[BuildingMap.PlacedObject] = []
	for placed: BuildingMap.PlacedObject in picked:
		var base: BuildingMap.PlacedObject = map.objects.get(placed.on) if placed.on_surface() else placed
		if base != null and not surfaces.has(base):
			surfaces.append(base)
	if floored.is_empty() and surfaces.is_empty():
		return null
	var low := Vector2i(1 << 30, 1 << 30)
	var high := -low
	for cell in floored:
		low = low.min(cell)
		high = high.max(cell + Vector2i.ONE)
	for placed in surfaces:
		low = low.min(Vector2i(placed.rect.position.floor()))
		high = high.max(Vector2i(placed.rect.end.ceil()))
	clip.size = high - low
	var bottom := INF
	for cell in floored:
		bottom = minf(bottom, map.floor_height(cell))
	for cell in floored:
		clip.floors[cell - low] = [map.floors[cell], map.floor_height(cell) - bottom]
	var seen: Dictionary[Vector3i, bool] = {}
	for cell in floored:
		for side in BuildingMap.DIRECTIONS:
			var edge := BuildingMap.edge_between(cell, cell + side)
			if seen.has(edge) or map.wall_at(edge) == BuildingMap.Wall.NONE:
				continue
			seen[edge] = true
			var across := cell + side
			var paints: Array = map.wall_paints.get(edge, [&"", &""])
			var mine := BuildingMap.wall_side(edge, Vector2(cell) + Vector2(0.5, 0.5))
			clip.walls.append([cell - low, across - low, map.walls[edge], map.wall_style(edge),
					map.window_kind(edge), map.door_kind_at(edge), paints[mine], paints[1 - mine]])
	for placed in surfaces:
		var things: Array = []
		for thing in map.things_on(placed.id):
			things.append([thing.def, thing.spot, thing.angle - placed.angle, thing.look])
		clip.objects.append([placed.def, placed.centre - Vector2(low), placed.angle, placed.look, things])
		clip.ids.append(placed.id)
	var marks := map.cell_marks(floored)
	for cell: Vector2i in marks[0]:
		clip.types[cell - low] = marks[0][cell]
	for cell: Vector2i in marks[1]:
		clip.zones[cell - low] = marks[1][cell]
	clip.from = low
	clip.taken = floored
	return clip


## Picks up one object, with what stands on it.
static func capture_object(map: BuildingMap, placed: BuildingMap.PlacedObject) -> BuildClip:
	return capture(map, [], [placed])


## Picks up a room: its floor, walls, objects and marks.
static func capture_room(map: BuildingMap, room: Room) -> BuildClip:
	return capture(map, room.cells, map.objects_in_room(room))


## Picks up everything in a rectangle: floor, walls round it and objects
## standing in it.
static func capture_rect(map: BuildingMap, rect: Rect2i) -> BuildClip:
	var picked: Array = []
	for placed: BuildingMap.PlacedObject in map.objects.values():
		if not placed.on_surface() and Rect2(rect).has_point(placed.centre):
			picked.append(placed)
	return capture(map, BuildingMap.cells_in(rect), picked)


func is_structure() -> bool:
	return not floors.is_empty()


## A copy that isn't tied to the map: a paste puts down new things.
func copy() -> BuildClip:
	var out := BuildClip.new()
	out.size = size
	out.floors = floors.duplicate(true)
	out.walls = walls.duplicate(true)
	out.objects = objects.duplicate(true)
	out.types = types.duplicate()
	out.zones = zones.duplicate()
	return out


## Turns the clip by quarter turns, clockwise as seen from above.
func rotate(quarters: int) -> void:
	for i in posmod(quarters, 4):
		_quarter_turn()


func _quarter_turn() -> void:
	var h := size.y
	var turn_cell := func(cell: Vector2i) -> Vector2i: return Vector2i(h - 1 - cell.y, cell.x)
	var new_floors: Dictionary[Vector2i, Array] = {}
	for cell in floors:
		new_floors[turn_cell.call(cell)] = floors[cell]
	floors = new_floors
	for wall: Array in walls:
		wall[0] = turn_cell.call(wall[0])
		wall[1] = turn_cell.call(wall[1])
	for entry: Array in objects:
		var centre: Vector2 = entry[1]
		entry[1] = Vector2(h - centre.y, centre.x)
		entry[2] = wrapf(entry[2] + PI * 0.5, 0.0, TAU)
	for marks: Dictionary in [types, zones]:
		var turned := {}
		for cell: Vector2i in marks:
			turned[turn_cell.call(cell)] = marks[cell]
		marks.clear()
		marks.merge(turned)
	size = Vector2i(size.y, size.x)


## The cells the clip's floor would cover with its top-left at a tile.
func cells_at(at: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for cell in floors:
		out.append(cell + at)
	return out


## Why the floor can't go down with its top-left at a tile, or empty if it
## can: every tile on your land, open, and free of floor other than tiles
## in `leaving` (where a move is taking floor away).
func floor_problem(map: BuildingMap, at: Vector2i, leaving: Array[Vector2i] = []) -> String:
	for cell in cells_at(at):
		if not map.owns(cell):
			return "That's off your land."
		if map.holes.has(cell) or map.stairs_at(cell) != null:
			return "Stairs are in the way."
		if map.has_floor(cell) and not leaving.has(cell):
			return "Something's already built there."
	return ""


## Puts the clip down with its top-left at a tile, its floor at `base`
## metres. Objects in `lifted` (as lift_objects() gave them) go down in
## place of new ones. Returns the objects that didn't fit; the rest is
## built whatever happens.
func put(map: BuildingMap, at: Vector2i, base: float, lifted: Array[BuildingMap.PlacedObject] = []) -> int:
	for cell in floors:
		var entry: Array = floors[cell]
		map.fill_floor(Rect2i(cell + at, Vector2i.ONE), entry[0], base + entry[1])
	for wall: Array in walls:
		var a: Vector2i = wall[0] + at
		var b: Vector2i = wall[1] + at
		var edge := BuildingMap.edge_between(a, b)
		if map.wall_at(edge) == BuildingMap.Wall.NONE:
			map.build_walls([edge], wall[3])
		if map.wall_at(edge) == BuildingMap.Wall.NONE:
			continue
		if wall[2] != BuildingMap.Wall.WALL:
			map.set_opening(edge, wall[2], wall[4] if not (wall[4] as StringName).is_empty()
					else BuildingMap.WINDOW_GLASS, wall[5])
		var side_a := BuildingMap.wall_side(edge, Vector2(a) + Vector2(0.5, 0.5))
		if not (wall[6] as StringName).is_empty():
			map.paint_side(edge, side_a, wall[6])
		if not (wall[7] as StringName).is_empty() and floors.has(wall[1]):
			map.paint_side(edge, 1 - side_a, wall[7])
	var marks_types: Dictionary[Vector2i, StringName] = {}
	var marks_zones: Dictionary[Vector2i, StringName] = {}
	for cell in types:
		marks_types[cell + at] = types[cell]
	for cell in zones:
		marks_zones[cell + at] = zones[cell]
	if not marks_types.is_empty() or not marks_zones.is_empty():
		map.mark_cells(marks_types, marks_zones)
	var misfits := 0
	for i in objects.size():
		var entry: Array = objects[i]
		var centre: Vector2 = entry[1] + Vector2(at)
		if i < lifted.size():
			if not map.put_object(lifted[i], centre, entry[2]):
				misfits += 1
			continue
		var id := map.place_object_at(entry[0], centre, entry[2], entry[3])
		if id == 0:
			misfits += 1
			continue
		for thing: Array in entry[4]:
			map.place_on_surface(thing[0], id, thing[1], thing[2], thing[3])
	return misfits


## Plain data for keeping as a template. Objects are kept by def id.
func to_data() -> Dictionary:
	var object_list: Array = []
	for entry: Array in objects:
		var things: Array = []
		for thing: Array in entry[4]:
			things.append([String((thing[0] as ObjectDef).id), thing[1], thing[2], thing[3]])
		object_list.append([String((entry[0] as ObjectDef).id), entry[1], entry[2], entry[3], things])
	return {"size": size, "floors": floors.duplicate(true), "walls": walls.duplicate(true),
			"objects": object_list, "types": types.duplicate(), "zones": zones.duplicate()}


## A clip from to_data(). `find_object` turns a def id into its ObjectDef;
## objects whose def is gone are left out.
static func from_data(data: Dictionary, find_object: Callable) -> BuildClip:
	var clip := BuildClip.new()
	clip.size = data.get("size", Vector2i.ONE)
	clip.floors.assign(data.get("floors", {}))
	clip.walls = data.get("walls", []).duplicate(true)
	clip.types.assign(data.get("types", {}))
	clip.zones.assign(data.get("zones", {}))
	for entry: Array in data.get("objects", []):
		var def: ObjectDef = find_object.call(StringName(entry[0]))
		if def == null:
			continue
		var things: Array = []
		for thing: Array in entry[4]:
			var thing_def: ObjectDef = find_object.call(StringName(thing[0]))
			if thing_def != null:
				things.append([thing_def, thing[1], thing[2], thing[3]])
		clip.objects.append([def, entry[1], entry[2], entry[3], things])
	return clip
