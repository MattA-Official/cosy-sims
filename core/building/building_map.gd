class_name BuildingMap
extends GridGeometry
## Everything built on the grid: floors in tiles, walls and doors on the edges
## between tiles (like The Sims), and objects placed on floors.
## Pure data with no nodes, so it can be tested on its own and saved later.
##
## Tiles ("cells") are Vector2i(x, z). Corners are Vector2i too: corner (x, z)
## is the top-left corner of cell (x, z). Edges are Vector3i(x, z, axis):
## - EDGE_X runs along X from corner (x, z) to (x + 1, z),
##   between cells (x, z - 1) and (x, z).
## - EDGE_Z runs along Z from corner (x, z) to (x, z + 1),
##   between cells (x - 1, z) and (x, z).
##
## Walls can also run at an angle between any two corners. These "slants"
## are stored as short straight pieces between the nearest corners on their
## line, keyed Vector4i(ax, az, bx, bz) with the first corner the smaller.
## A slant cuts the tiles it crosses into pieces (see TilePiece), and rooms
## are worked out from pieces rather than whole tiles.
##
## Floors use whole tiles, less any pieces cut away. Objects use positions in tile units
## (Vector2, so 2.25 is a quarter of the way into tile 2) and can snap to
## tiles, quarter tiles, or nothing.
##
## Floors and walls carry a style id (see FloorDef and WallDef). Each side
## of a wall can also be painted in another style's finish. Whether a
## room is indoors is decided by its walls: enclosed by indoor walls and
## doors means indoors; fences and hedges leave it outdoors.
##
## You can only build on land you own, which starts as one rectangle and can
## grow with add_land().

signal changed
## The dressing on claimed surfaces changed.
signal dressing_changed

const DEFAULT_FLOOR := &"concrete"
const DEFAULT_WALL := &"plaster"
## Neighbouring floors further apart in height than this need a ramp or
## stairs between them; closer ones are a step people can take.
const MAX_STEP := 0.25
## The tallest difference door steps can make up, with door steps on.
const DOOR_STEPS_MAX := 1.0

enum Wall { NONE, WALL, DOOR, WINDOW }

## Kinds of window. Both let light and sight through but nobody past.
const WINDOW_GLASS := &"glass"
const WINDOW_BARS := &"bars"


class PlacedObject:
	var id: int
	var def: ObjectDef
	var rotation: int ## The nearest quarter turn, 0 to 3.
	var angle := 0.0 ## The turn in radians; quarter turns are multiples of PI / 2.
	var centre: Vector2 ## The middle of the footprint, in tile units.
	var rect: Rect2 ## A box around the footprint, in tile units.
	var look := 0 ## Which of its def's looks it wears.
	var on := 0 ## The surface it stands on, or 0 on the floor.
	var spot := -1 ## Which of that surface's spots.

	func on_surface() -> bool:
		return on != 0

	## The footprint's four corners, in tile units.
	func polygon() -> PackedVector2Array:
		return BuildingMap.object_polygon(def, centre, angle)


## A drawn slope between two floor heights, climbing one way.
class Ramp:
	var rect: Rect2i
	var rise: Vector2i ## The way the ramp climbs.
	var low: float ## Surface height at the bottom edge.
	var high: float ## Surface height at the top edge.

	func length() -> float:
		return absf(Vector2(rect.size).dot(Vector2(rise)))

	## Surface height at a point in tile units, held level past either end.
	func height_at(point: Vector2) -> float:
		var foot := Rect2(rect).get_center() - Vector2(rise) * length() * 0.5
		return lerpf(low, high, clampf((point - foot).dot(Vector2(rise)) / length(), 0.0, 1.0))


var land: Array[Rect2i] = []
var floors: Dictionary[Vector2i, StringName] = {}
## The height of each floor tile's surface, in metres. Set when the floor is
## laid; restyling a floor keeps its height.
var floor_heights: Dictionary[Vector2i, float] = {}
var walls: Dictionary[Vector3i, int] = {} ## Values are Wall.WALL, DOOR or WINDOW.
var wall_styles: Dictionary[Vector3i, StringName] = {}
var window_kinds: Dictionary[Vector3i, StringName] = {} ## For Wall.WINDOW edges only.
## Angled walls, with their styles and window kinds, like the three above.
var slants: Dictionary[Vector4i, int] = {}
var slant_styles: Dictionary[Vector4i, StringName] = {}
var slant_window_kinds: Dictionary[Vector4i, StringName] = {}
## Paint on either side of a wall: [side 0 style, side 1 style], empty for
## the wall's own finish. See paint_side().
var wall_paints: Dictionary[Vector3i, Array] = {}
var slant_paints: Dictionary[Vector4i, Array] = {}
## Floor styles for single pieces of tiles cut by angled walls, where they
## differ from the tile's own: [a point inside the piece, style] pairs. An
## empty style means that piece has no floor.
var piece_styles: Dictionary[Vector2i, Array] = {}
var objects: Dictionary[int, PlacedObject] = {}
## Things set out for show on surfaces people have claimed, by surface
## id: [ObjectDef, turn in radians] pairs filling its free spots in order.
## Not part of the build, so not saved and no change to it.
var dressing: Dictionary[int, Array] = {}
var ramps: Array[Ramp] = []
var stairs: Dictionary[int, Staircase] = {}
## Tiles open to stairs coming up from the level below. No floor goes here.
var holes: Dictionary[Vector2i, bool] = {}

## Room types are stored per cell, so they survive rooms being split, merged
## or extended: each room takes the type most of its cells carry.
var _room_types: Dictionary[Vector2i, StringName] = {}
## Zones painted onto rooms (ZoneDef ids), stored per cell like room types.
var _room_zones: Dictionary[Vector2i, StringName] = {}
## The DoorKindDef id of each door that has one, such as a staff door.
## Plain doors have none.
var door_kinds: Dictionary[Vector3i, StringName] = {}
var _next_object_id := 1
var _next_stairs_id := 1
var _rooms: Array[Room] = []
var _room_lookup: Dictionary[Vector2i, Room] = {}
var _rooms_dirty := true
## Rooms by piece: Vector3i(cell x, cell z, piece index).
var _piece_rooms: Dictionary[Vector3i, Room] = {}
var _slant_cells: Dictionary[Vector2i, Array] = {}
var _pieces: Dictionary[Vector2i, Array] = {}
var _squares: Dictionary[Vector2i, Array] = {}
var _slants_dirty := true
var _floor_defs: Dictionary[StringName, FloorDef] = {}
var _wall_defs: Dictionary[StringName, WallDef] = {}


func _init(starting_land: Rect2i) -> void:
	land.append(starting_land)


## Tells the map about the game's floor and wall styles, so it knows which
## are outdoor. Unknown styles count as indoor.
func register_styles(floor_list: Array[FloorDef], wall_list: Array[WallDef]) -> void:
	for def in floor_list:
		_floor_defs[def.id] = def
	for def in wall_list:
		_wall_defs[def.id] = def
	_changed()


func floor_def(id: StringName) -> FloorDef:
	return _floor_defs.get(id)


func wall_def(id: StringName) -> WallDef:
	return _wall_defs.get(id)


#region Land

func owns(cell: Vector2i) -> bool:
	for rect in land:
		if rect.has_point(cell):
			return true
	return false


func add_land(rect: Rect2i) -> void:
	land.append(rect)
	_changed()


## Gives up a rectangle of land: owned rectangles it overlaps are cut
## around it.
func remove_land(rect: Rect2i) -> void:
	land.assign(subtract_rect(land, rect))
	_changed()


## Rectangles less one, cutting any that overlap it into the pieces left.
static func subtract_rect(rects: Array[Rect2i], cut: Rect2i) -> Array[Rect2i]:
	var out: Array[Rect2i] = []
	for rect in rects:
		var overlap := rect.intersection(cut)
		if not overlap.has_area():
			out.append(rect)
			continue
		# Strips above and below the cut, then left and right of it.
		var pieces: Array[Rect2i] = [
			Rect2i(rect.position.x, rect.position.y, rect.size.x, overlap.position.y - rect.position.y),
			Rect2i(rect.position.x, overlap.end.y, rect.size.x, rect.end.y - overlap.end.y),
			Rect2i(rect.position.x, overlap.position.y, overlap.position.x - rect.position.x, overlap.size.y),
			Rect2i(overlap.end.x, overlap.position.y, rect.end.x - overlap.end.x, overlap.size.y)]
		for piece in pieces:
			if piece.has_area():
				out.append(piece)
	return out


## Whether anything is built in a rectangle: floors, walls, objects or
## stairs.
func in_use(rect: Rect2i) -> bool:
	for cell in floors:
		if rect.has_point(cell):
			return true
	for edge: Vector3i in walls:
		if rect.has_point(Vector2i(edge.x, edge.y)):
			return true
	for key: Vector4i in slants:
		for end: Vector2i in slant_ends(key):
			if Rect2(rect).has_point(Vector2(end)):
				return true
	for placed: PlacedObject in objects.values():
		if Rect2(rect).intersects(placed.rect):
			return true
	return false


## The smallest rectangle covering all owned land.
func land_bounds() -> Rect2i:
	var bounds := land[0]
	for rect in land:
		bounds = bounds.merge(rect)
	return bounds

#endregion

#region Floors

func has_floor(cell: Vector2i) -> bool:
	return floors.has(cell)


func floor_height(cell: Vector2i) -> float:
	return floor_heights.get(cell, 0.0)


## Changes the height of existing floor tiles, for split levels. Takes
## Vector2i tiles to heights; tiles without floor are skipped.
func set_floor_heights(heights: Dictionary) -> int:
	var count := 0
	for cell: Vector2i in heights:
		if floors.has(cell) and not is_equal_approx(floor_heights.get(cell, 0.0), heights[cell]):
			# Moving part of a ramp flattens the whole ramp back to tiles.
			var ramp := ramp_at(cell)
			if ramp != null:
				ramps.erase(ramp)
			floor_heights[cell] = heights[cell]
			count += 1
	if count > 0:
		_changed()
	return count


## The height of floor already in or right next to a rectangle, so new
## floor can line up with it. NAN when there is none.
func floor_height_near(rect: Rect2i) -> float:
	for cell in cells_in(rect.grow(1)):
		if floors.has(cell):
			return floor_heights.get(cell, 0.0)
	return NAN


## Lays or restyles floor. New tiles go in at `height`; existing ones keep theirs.
func fill_floor(rect: Rect2i, type: StringName = DEFAULT_FLOOR, height := 0.0) -> int:
	var count := _fill_floor(rect, type, height)
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

## Walls can go on edges next to owned land.
func edge_in_bounds(edge: Vector3i) -> bool:
	var sides := edge_cells(edge)
	return owns(sides[0]) or owns(sides[1])


func wall_at(edge: Vector3i) -> int:
	return walls.get(edge, Wall.NONE)


## Is anything built in or right beside a block of tiles? Used to skip
## redrawing buildings when the ground changes somewhere else.
func has_build_near(rect: Rect2i) -> bool:
	if floors.is_empty() and walls.is_empty() and slants.is_empty():
		return false
	var area := rect.grow(1)
	for cell in cells_in(area):
		if corner_in_use(cell):
			return true
	for key: Vector4i in slants:
		if area.has_point(Vector2i(key.x, key.y)) or area.has_point(Vector2i(key.z, key.w)):
			return true
	return false


## Is anything built at this corner? Used to stop sculpting under buildings.
func corner_in_use(corner: Vector2i) -> bool:
	for offset: Vector2i in [Vector2i.ZERO, Vector2i(-1, 0), Vector2i(0, -1), Vector2i(-1, -1)]:
		if floors.has(corner + offset):
			return true
	for edge: Vector3i in [Vector3i(corner.x, corner.y, EDGE_X), Vector3i(corner.x - 1, corner.y, EDGE_X),
			Vector3i(corner.x, corner.y, EDGE_Z), Vector3i(corner.x, corner.y - 1, EDGE_Z)]:
		if walls.has(edge):
			return true
	for key: Vector4i in slants:
		if corner in slant_ends(key):
			return true
	return false


func wall_style(edge: Vector3i) -> StringName:
	return wall_styles.get(edge, &"")


func window_kind(edge: Vector3i) -> StringName:
	return window_kinds.get(edge, &"")


func is_outdoor_wall(edge: Vector3i) -> bool:
	var def := wall_def(wall_style(edge))
	return def != null and def.outdoor


## Can people walk from one cell to its neighbour? Walls and windows
## block; doors do not. Between two floors, a drop bigger than MAX_STEP
## blocks too.
func can_walk_between(a: Vector2i, b: Vector2i) -> bool:
	var edge := edge_between(a, b)
	if edge == NO_EDGE or not owns(a) or not owns(b):
		return false
	var kind := wall_at(edge)
	if kind != Wall.NONE and kind != Wall.DOOR:
		return false
	if floors.has(a) and floors.has(b):
		return absf(edge_height(a, b - a) - edge_height(b, a - b)) <= MAX_STEP + EPSILON \
				or door_has_steps(edge)
	return true


## Can a wall go on this edge? Not off our land, and not through an object.
func can_build_wall(edge: Vector3i) -> bool:
	if not edge_in_bounds(edge):
		return false
	var ends := edge_ends(edge)
	for placed: PlacedObject in objects.values():
		if segment_crosses(placed.polygon(), ends[0], ends[1]):
			return false
	var sides := edge_cells(edge)
	var flight := stairs_at(sides[0])
	if flight != null and flight == stairs_at(sides[1]):
		var i := flight.cells.find(sides[0])
		var j := flight.cells.find(sides[1])
		if absi(i - j) == 1:
			return false
	return true


## Builds walls on empty edges, and restyles walls already there.
## Doors and windows stay as they are.
func build_walls(edges: Array[Vector3i], style: StringName = DEFAULT_WALL) -> int:
	var count := _build_walls(edges, style)
	if count > 0:
		_changed()
	return count


func remove_walls(edges: Array[Vector3i]) -> int:
	var count := 0
	for edge in edges:
		if walls.erase(edge):
			wall_styles.erase(edge)
			window_kinds.erase(edge)
			wall_paints.erase(edge)
			door_kinds.erase(edge)
			count += 1
	if count > 0:
		_changed()
	return count


## How far apart the floors either side of an edge are, or 0 unless both
## sides have floor.
func door_rise(edge: Vector3i) -> float:
	var sides := edge_cells(edge)
	if not floors.has(sides[0]) or not floors.has(sides[1]):
		return 0.0
	return absf(edge_height(sides[0], sides[1] - sides[0]) - edge_height(sides[1], sides[0] - sides[1]))


## Can a door go in this wall? Not between floors more than a step apart,
## unless door steps are on and the gap is small enough for them.
func can_put_door(edge: Vector3i) -> bool:
	var rise := door_rise(edge)
	return rise <= MAX_STEP + EPSILON or (Building.door_steps and rise <= DOOR_STEPS_MAX + EPSILON)


## Does this door have steps up to it? Only with door steps on.
func door_has_steps(edge: Vector3i) -> bool:
	if not Building.door_steps or wall_at(edge) != Wall.DOOR:
		return false
	var rise := door_rise(edge)
	return rise > MAX_STEP + EPSILON and rise <= DOOR_STEPS_MAX + EPSILON


## Doors nobody can walk through because the floors either side drifted
## more than a step apart after the door went in (and no steps make it up).
func unusable_doors() -> Array[Vector3i]:
	var out: Array[Vector3i] = []
	for edge: Vector3i in walls:
		if walls[edge] == Wall.DOOR and not can_put_door(edge):
			out.append(edge)
	return out


## Every door with steps, as edge to the low-side tile the steps stand on.
func door_steps() -> Dictionary[Vector3i, Vector2i]:
	var found: Dictionary[Vector3i, Vector2i] = {}
	if not Building.door_steps:
		return found
	for edge: Vector3i in walls:
		if door_has_steps(edge):
			var sides := edge_cells(edge)
			var low := sides[0] if floor_height(sides[0]) < floor_height(sides[1]) else sides[1]
			found[edge] = low
	return found


## Turns a wall into a door, or a door back into a wall. `door_kind` makes
## it a staff door and so on.
func set_door(edge: Vector3i, is_door: bool, door_kind: StringName = &"") -> bool:
	return set_opening(edge, Wall.DOOR if is_door else Wall.WALL, WINDOW_GLASS, door_kind)


## Makes a wall piece plain, a door or a window. Windows need a kind, and
## can't go in outdoor walls such as fences; doors can have a kind, such
## as a staff door. Returns whether anything changed.
func set_opening(edge: Vector3i, kind: Wall, window: StringName = WINDOW_GLASS,
		door_kind: StringName = &"") -> bool:
	if wall_at(edge) == Wall.NONE or kind == Wall.NONE:
		return false
	if kind == Wall.WINDOW and is_outdoor_wall(edge):
		return false
	if kind == Wall.DOOR and not can_put_door(edge):
		return false
	if walls[edge] == kind and (kind != Wall.WINDOW or window_kind(edge) == window) \
			and (kind != Wall.DOOR or door_kind_at(edge) == door_kind):
		return false
	walls[edge] = kind
	if kind == Wall.WINDOW:
		window_kinds[edge] = window
	else:
		window_kinds.erase(edge)
	if kind == Wall.DOOR and not door_kind.is_empty():
		door_kinds[edge] = door_kind
	else:
		door_kinds.erase(edge)
	_changed()
	return true


## The kind of door in a wall, such as &"staff", or empty for a plain door
## or no door at all.
func door_kind_at(edge: Vector3i) -> StringName:
	return door_kinds.get(edge, &"") if wall_at(edge) == Wall.DOOR else &""

#endregion

#region Angled walls

func slant_at(key: Vector4i) -> int:
	return slants.get(key, Wall.NONE)


func slant_style(key: Vector4i) -> StringName:
	return slant_styles.get(key, &"")


func slant_window_kind(key: Vector4i) -> StringName:
	return slant_window_kinds.get(key, &"")


func is_outdoor_slant(key: Vector4i) -> bool:
	var def := wall_def(slant_style(key))
	return def != null and def.outdoor


## Angled walls go over owned land, and not through objects.
func can_build_slant(key: Vector4i) -> bool:
	for cell in slant_crossings(key):
		if not owns(cell):
			return false
	for placed: PlacedObject in objects.values():
		var ends := slant_ends(key)
		if segment_crosses(placed.polygon(), Vector2(ends[0]), Vector2(ends[1])):
			return false
	return true


## Builds angled walls on empty lines and restyles ones already there.
func build_slants(keys: Array[Vector4i], style: StringName = DEFAULT_WALL) -> int:
	var count := 0
	for key in keys:
		if slant_at(key) == Wall.NONE:
			if not can_build_slant(key):
				continue
			slants[key] = Wall.WALL
		elif slant_style(key) == style:
			continue
		slant_styles[key] = style
		slant_paints.erase(key)
		count += 1
	if count > 0:
		_changed()
	return count


func remove_slants(keys: Array[Vector4i]) -> int:
	var count := 0
	for key in keys:
		if slants.erase(key):
			slant_styles.erase(key)
			slant_window_kinds.erase(key)
			slant_paints.erase(key)
			count += 1
	if count > 0:
		_changed()
	return count


## Like set_opening, for an angled wall piece.
func set_slant_opening(key: Vector4i, kind: Wall, window: StringName = WINDOW_GLASS) -> bool:
	if slant_at(key) == Wall.NONE or kind == Wall.NONE:
		return false
	if kind == Wall.WINDOW and is_outdoor_slant(key):
		return false
	if slants[key] == kind and (kind != Wall.WINDOW or slant_window_kind(key) == window):
		return false
	slants[key] = kind
	if kind == Wall.WINDOW:
		slant_window_kinds[key] = window
	else:
		slant_window_kinds.erase(key)
	_changed()
	return true


## The angled wall pieces crossing a cell.
func slants_through(cell: Vector2i) -> Array:
	_update_slants()
	return _slant_cells.get(cell, [])


## The pieces a tile is cut into: just the whole tile unless angled walls
## cross it.
func pieces(cell: Vector2i) -> Array:
	_update_slants()
	if _pieces.has(cell):
		return _pieces[cell]
	# Uncut tiles are asked for a lot (the walking graph asks for every
	# floor tile and its neighbours), so keep them rather than make new ones.
	if not _squares.has(cell):
		_squares[cell] = [TilePiece.square(cell)]
	return _squares[cell]


## The piece of a tile holding a point, in tile units.
func piece_at(point: Vector2) -> TilePiece:
	var cell := Vector2i(point.floor())
	for piece: TilePiece in pieces(cell):
		if piece.has_point(point):
			return piece
	return pieces(cell)[0]


## A piece's floor style, or empty if it has no floor.
func piece_floor(piece: TilePiece) -> StringName:
	if not floors.has(piece.cell):
		return &""
	for entry: Array in piece_styles.get(piece.cell, []):
		if piece.has_point(entry[0]):
			return entry[1]
	return floors[piece.cell]


func piece_has_floor(piece: TilePiece) -> bool:
	return not piece_floor(piece).is_empty()


## Lays, restyles or takes up floor on just these pieces, leaving the rest
## of their tiles alone. An empty style takes the floor up. New floor goes in
## at `height`. Returns how many pieces changed.
func set_piece_floors(chosen: Array[TilePiece], type: StringName, height := 0.0) -> int:
	var by_cell: Dictionary[Vector2i, Array] = {}
	for piece in chosen:
		if owns(piece.cell) and not holes.has(piece.cell):
			by_cell.get_or_add(piece.cell, []).append(piece.index)
	var count := 0
	for cell: Vector2i in by_cell:
		var list := pieces(cell)
		var types: Array[StringName] = []
		for piece: TilePiece in list:
			types.append(piece_floor(piece))
		for index: int in by_cell[cell]:
			if types[index] != type:
				types[index] = type
				count += 1
		_store_piece_floors(cell, types, height)
	if count > 0:
		_changed()
	return count


## The pieces you can reach from the one under a point without crossing a
## wall, door or window, nor leaving `limit` (cells) when one is given.
## With `max_pieces`, an area that runs off your land or past that size
## gives nothing back, so one click cannot flood the whole map.
func pieces_within_walls(point: Vector2, limit := Rect2i(), max_pieces := 0) -> Array[TilePiece]:
	var start := piece_at(point)
	var out: Array[TilePiece] = []
	if not owns(start.cell) or (limit.has_area() and not limit.has_point(start.cell)):
		return out
	var seen := {_piece_id(start): true}
	var stack: Array[TilePiece] = [start]
	while not stack.is_empty():
		var piece: TilePiece = stack.pop_back()
		out.append(piece)
		if max_pieces > 0 and out.size() > max_pieces:
			return []
		for i in piece.sides.size():
			var tag: Variant = piece.sides[i]
			if tag is Vector4i:
				continue
			var next_cell: Vector2i = piece.cell + DIRECTIONS[tag]
			if wall_at(edge_between(piece.cell, next_cell)) != Wall.NONE:
				continue
			if limit.has_area() and not limit.has_point(next_cell):
				continue
			if not owns(next_cell):
				if max_pieces > 0:
					return []
				continue
			var stretch := PackedVector2Array([piece.polygon[i],
					piece.polygon[(i + 1) % piece.polygon.size()]])
			for next: TilePiece in pieces(next_cell):
				if seen.has(_piece_id(next)) or not next.sides_tagged(tag ^ 1).any(
						func(other: PackedVector2Array) -> bool:
							return TilePiece.overlaps(stretch, other)):
					continue
				seen[_piece_id(next)] = true
				stack.append(next)
	return out


## Stores the floor of every piece of a tile: the most common style becomes
## the tile's, and the others are kept per piece.
func _store_piece_floors(cell: Vector2i, types: Array[StringName], height: float) -> void:
	var votes := {}
	for type in types:
		if not type.is_empty():
			votes[type] = votes.get(type, 0) + 1
	if votes.is_empty():
		_clear_floor(Rect2i(cell, Vector2i.ONE))
		return
	var base: StringName = votes.keys()[0]
	for type: StringName in votes:
		if votes[type] > votes[base]:
			base = type
	if not floors.has(cell):
		floor_heights[cell] = height
	floors[cell] = base
	var list := pieces(cell)
	var entries: Array = []
	for i in types.size():
		if types[i] != base:
			entries.append([list[i].centre(), types[i]])
	if entries.is_empty():
		piece_styles.erase(cell)
	else:
		piece_styles[cell] = entries


func _update_slants() -> void:
	if not _slants_dirty:
		return
	_slants_dirty = false
	_slant_cells.clear()
	_pieces.clear()
	for key: Vector4i in slants:
		for cell in slant_crossings(key):
			var list: Array = _slant_cells.get_or_add(cell, [])
			list.append(key)
	for cell: Vector2i in _slant_cells:
		var lines := {}
		for key: Vector4i in _slant_cells[cell]:
			var ends := slant_ends(key)
			lines[key] = [Vector2(ends[0]), Vector2(ends[1])]
		_pieces[cell] = TilePiece.split(cell, lines)


#endregion

#region Wall paint

## A straight wall (its edge, Vector3i) or an angled one (its key, Vector4i).
## Both work with the functions below.

## The two corners a wall runs between, in tile units.
static func wall_ends(wall: Variant) -> Array[Vector2]:
	if wall is Vector3i:
		return edge_ends(wall)
	var ends := slant_ends(wall)
	return [Vector2(ends[0]), Vector2(ends[1])]


## Which side of a wall a point is on. Side 0 is the side to the left of
## the line from the wall's first corner to its second, turning from +X
## towards +Z (so the side `across` points to in BuildingView); side 1 is
## the other.
static func wall_side(wall: Variant, point: Vector2) -> int:
	var ends := wall_ends(wall)
	return 0 if (ends[1] - ends[0]).cross(point - ends[0]) > 0.0 else 1


func has_wall(wall: Variant) -> bool:
	return (wall_at(wall) if wall is Vector3i else slant_at(wall)) != Wall.NONE


func style_of(wall: Variant) -> StringName:
	return wall_style(wall) if wall is Vector3i else slant_style(wall)


## The style whose finish (colour, texture and dado) a side of a wall shows:
## its paint, or the wall's own style.
func side_style(wall: Variant, side: int) -> StringName:
	var paints: Array = wall_paints.get(wall, []) if wall is Vector3i else slant_paints.get(wall, [])
	if not paints.is_empty() and not (paints[side] as StringName).is_empty():
		return paints[side]
	return style_of(wall)


## Can a wall's sides be painted in a style? Paints are indoor finishes, and
## only indoor walls take them: fences and hedges stay as they are.
func can_paint(wall: Variant, style: StringName) -> bool:
	if not has_wall(wall):
		return false
	var own := wall_def(style_of(wall))
	var paint := wall_def(style)
	return (own == null or not own.outdoor) and (paint == null or not paint.outdoor)


## Paints one side of a wall in a style's finish. The wall keeps its own
## height, thickness and top. Painting with the wall's own style, or an
## empty one, takes the paint off. Returns whether anything changed.
func paint_side(wall: Variant, side: int, style: StringName) -> bool:
	if not _paint_side(wall, side, style):
		return false
	_changed()
	return true


## Paints many sides at once: [wall, side] pairs. Returns how many changed.
func paint_sides(sides: Array, style: StringName) -> int:
	var count := 0
	for entry: Array in sides:
		if _paint_side(entry[0], entry[1], style):
			count += 1
	if count > 0:
		_changed()
	return count


## The wall sides facing into the area around a point, as [wall, side]
## pairs: every wall bounding the pieces reachable from it without crossing
## a wall (see pieces_within_walls).
func sides_facing(point: Vector2, max_pieces := 0) -> Array:
	var out: Array = []
	var seen := {}
	for piece in pieces_within_walls(point, Rect2i(), max_pieces):
		for i in piece.sides.size():
			var tag: Variant = piece.sides[i]
			var wall: Variant = tag
			if tag is int:
				wall = edge_between(piece.cell, piece.cell + DIRECTIONS[tag])
			if not has_wall(wall):
				continue
			var entry := [wall, wall_side(wall, piece.centre())]
			if not seen.has(entry):
				seen[entry] = true
				out.append(entry)
	return out


func _paint_side(wall: Variant, side: int, style: StringName) -> bool:
	if not style.is_empty() and not can_paint(wall, style):
		return false
	if style == style_of(wall):
		style = &""
	var store: Dictionary = wall_paints if wall is Vector3i else slant_paints
	var paints: Array = store.get(wall, [&"", &""]).duplicate()
	if paints[side] == style:
		return false
	paints[side] = style
	if (paints[0] as StringName).is_empty() and (paints[1] as StringName).is_empty():
		store.erase(wall)
	else:
		store[wall] = paints
	return true

#endregion

#region Objects

func can_place(def: ObjectDef, position: Vector2, rotation: int) -> bool:
	return can_place_at(def, object_rect(def, position, rotation).get_center(), rotation * PI * 0.5)


## Can an object go with its centre here, turned by `angle` radians? It needs
## floor under all of it, and no other object, wall or ramp in the way.
func can_place_at(def: ObjectDef, centre: Vector2, angle: float) -> bool:
	var points := object_polygon(def, centre, angle)
	var rect := polygon_bounds(points)
	var shrunk := Geometry2D.offset_polygon(points, -EPSILON * 2.0)
	if shrunk.is_empty():
		return false
	var inner: PackedVector2Array = shrunk[0]
	var stepped := door_steps().values()
	for cell in cells_under(rect):
		var square := PackedVector2Array([Vector2(cell), Vector2(cell) + Vector2(1, 0),
				Vector2(cell) + Vector2.ONE, Vector2(cell) + Vector2(0, 1)])
		if Geometry2D.intersect_polygons(inner, square).is_empty():
			continue
		if not has_floor(cell) or ramp_at(cell) != null or stairs_at(cell) != null or stepped.has(cell):
			return false
	for placed: PlacedObject in objects.values():
		# Chairs tuck under tables and desks.
		if (not def.blocks and placed.def.is_surface()) or (def.is_surface() and not placed.def.blocks):
			continue
		if not placed.on_surface() and placed.rect.grow(-EPSILON).intersects(rect) \
				and not Geometry2D.intersect_polygons(inner, placed.polygon()).is_empty():
			return false
	# An object cannot straddle a wall or door.
	for edge in rect_edges(_cell_bounds(rect)):
		if wall_at(edge) != Wall.NONE:
			var ends := edge_ends(edge)
			if segment_crosses(points, ends[0], ends[1]):
				return false
	for key: Vector4i in slants:
		var ends := slant_ends(key)
		if segment_crosses(points, Vector2(ends[0]), Vector2(ends[1])):
			return false
	return true


## Places an object and returns its id, or 0 if it does not fit.
func place_object(def: ObjectDef, position: Vector2, rotation: int) -> int:
	return place_object_at(def, object_rect(def, position, rotation).get_center(), rotation * PI * 0.5)


## Places an object centred on a point and turned by `angle` radians. Lifts
## only take quarter turns. Returns its id, or 0 if it does not fit.
func place_object_at(def: ObjectDef, centre: Vector2, angle: float, look := 0) -> int:
	if def.connects != ObjectDef.Connects.NONE:
		angle = snappedf(angle, PI * 0.5)
	angle = wrapf(angle, 0.0, TAU)
	if def.sits == ObjectDef.Sits.SURFACE or not can_place_at(def, centre, angle):
		return 0
	return _add_object(def, centre, angle, look, 0, -1)


## Stands a small thing on a surface's spot, turned by `angle` radians
## from the surface. Returns its id, or 0 if it can't go there.
func place_on_surface(def: ObjectDef, surface_id: int, spot: int, angle := 0.0, look := 0) -> int:
	var surface: PlacedObject = objects.get(surface_id)
	if not def.goes_on_surfaces() or surface == null or spot < 0 or spot >= surface.def.spots.size() \
			or spot_taken(surface_id, spot):
		return 0
	return _add_object(def, spot_point(surface, spot), wrapf(surface.angle + angle, 0.0, TAU), look,
			surface_id, spot)


## Places a chair (or anything people sit on) beside a surface, `offset`
## tiles from its middle in the surface's own frame, turned to face it.
## Returns its id, or 0 if it doesn't fit.
func place_beside(def: ObjectDef, surface_id: int, offset: Vector2, look := 0) -> int:
	var surface: PlacedObject = objects.get(surface_id)
	if surface == null:
		return 0
	var at := surface.centre + offset.rotated(surface.angle)
	return place_object_at(def, at, facing(at, surface.centre), look)


## The turn that faces an object's front (its +y) from one point towards
## another.
static func facing(from: Vector2, to: Vector2) -> float:
	return wrapf((to - from).angle() - PI * 0.5, 0.0, TAU)


## Where a surface's spot is, in tile units.
func spot_point(surface: PlacedObject, spot: int) -> Vector2:
	return surface.centre + surface.def.spots[spot].rotated(surface.angle)


## What stands on a surface.
func things_on(surface_id: int) -> Array[PlacedObject]:
	var out: Array[PlacedObject] = []
	for placed: PlacedObject in objects.values():
		if placed.on == surface_id:
			out.append(placed)
	return out


func spot_taken(surface_id: int, spot: int) -> bool:
	return things_on(surface_id).any(func(p: PlacedObject) -> bool: return p.spot == spot)


## The surface under a point, if any.
func surface_at(point: Vector2) -> PlacedObject:
	for placed: PlacedObject in objects.values():
		if placed.def.is_surface() and not placed.on_surface() and placed.rect.has_point(point) \
				and Geometry2D.is_point_in_polygon(point, placed.polygon()):
			return placed
	return null


## A surface's free spot nearest a point, or -1 if all are taken.
func free_spot_near(surface: PlacedObject, point: Vector2) -> int:
	var best := -1
	for i in surface.def.spots.size():
		if spot_taken(surface.id, i):
			continue
		if best == -1 or spot_point(surface, i).distance_to(point) < spot_point(surface, best).distance_to(point):
			best = i
	return best


## Whether people have to walk round whatever is at a point.
func blocks_at(point: Vector2) -> bool:
	for placed: PlacedObject in objects.values():
		if placed.def.blocks and not placed.on_surface() and placed.rect.has_point(point) \
				and Geometry2D.is_point_in_polygon(point, placed.polygon()):
			return true
	return false


## Sets out things for show on a surface, or clears them with an empty
## list.
func set_dressing(surface_id: int, things: Array) -> void:
	if dressing.get(surface_id, []) == things:
		return
	if things.is_empty():
		dressing.erase(surface_id)
	else:
		dressing[surface_id] = things
	dressing_changed.emit()


## Changes the look of something placed. Returns whether it changed.
func set_look(id: int, look: int) -> bool:
	var placed: PlacedObject = objects.get(id)
	if placed == null or look < 0 or look >= placed.def.look_count() or placed.look == look:
		return false
	placed.look = look
	_changed()
	return true


func _add_object(def: ObjectDef, centre: Vector2, angle: float, look: int, on: int, spot: int) -> int:
	var placed := PlacedObject.new()
	placed.id = _next_object_id
	_next_object_id += 1
	placed.def = def
	placed.angle = angle
	placed.rotation = posmod(roundi(angle / (PI * 0.5)), 4)
	placed.centre = centre
	placed.rect = polygon_bounds(object_polygon(def, centre, angle))
	placed.look = clampi(look, 0, def.look_count() - 1)
	placed.on = on
	placed.spot = spot
	objects[placed.id] = placed
	_changed()
	return placed.id


## Takes away things left standing on surfaces that are gone.
func _drop_orphans() -> int:
	var count := 0
	for placed: PlacedObject in objects.values():
		if placed.on_surface() and not objects.has(placed.on):
			objects.erase(placed.id)
			count += 1
	return count


#region Ramps

func ramp_at(cell: Vector2i) -> Ramp:
	for ramp in ramps:
		if ramp.rect.has_point(cell):
			return ramp
	return null


## The surface height where a tile meets its neighbour in direction `side`:
## the floor height, or partway up a ramp.
func edge_height(cell: Vector2i, side: Vector2i) -> float:
	var ramp := ramp_at(cell)
	if ramp == null:
		return floor_height(cell)
	return ramp.height_at(Vector2(cell) + Vector2(0.5, 0.5) + Vector2(side) * 0.5)


## A ramp needs floor under all of it, with no walls, objects or other ramps
## in the way.
func can_add_ramp(rect: Rect2i) -> bool:
	if rect.size.x < 1 or rect.size.y < 1:
		return false
	for cell in cells_in(rect):
		if not has_floor(cell) or ramp_at(cell) != null or stairs_at(cell) != null:
			return false
	for edge in rect_edges(rect):
		if wall_at(edge) != Wall.NONE and edge_crosses(edge, Rect2(rect)):
			return false
	for placed: PlacedObject in objects.values():
		if placed.rect.grow(-EPSILON).intersects(Rect2(rect)):
			return false
	return true


## Lays a ramp over floor, climbing along `rise` from `low` to `high`.
func add_ramp(rect: Rect2i, rise: Vector2i, low: float, high: float) -> bool:
	if not can_add_ramp(rect) or rise not in DIRECTIONS:
		return false
	var ramp := Ramp.new()
	ramp.rect = rect
	ramp.rise = rise
	ramp.low = low
	ramp.high = high
	ramps.append(ramp)
	# Each tile keeps its middle height, for anything that wants one number.
	for cell in cells_in(rect):
		floor_heights[cell] = ramp.height_at(Vector2(cell) + Vector2(0.5, 0.5))
	_changed()
	return true

#endregion


#region Stairs

## The staircase covering a tile, if any.
func stairs_at(cell: Vector2i) -> Staircase:
	for flight: Staircase in stairs.values():
		if flight.covers(cell):
			return flight
	return null


## Can a staircase run along this route? Each tile needs floor, with no
## object, ramp, stairwell, angled wall or other stairs on it, and each must
## step straight on to the next without a wall between them.
func can_add_stairs(route: Array[Vector2i]) -> bool:
	if route.is_empty():
		return false
	var seen: Dictionary[Vector2i, bool] = {}
	for i in route.size():
		var cell := route[i]
		if seen.has(cell) or not owns(cell) or not has_floor(cell) or ramp_at(cell) != null \
				or holes.has(cell) or stairs_at(cell) != null or not slants_through(cell).is_empty():
			return false
		seen[cell] = true
		if i > 0:
			var step := cell - route[i - 1]
			if absi(step.x) + absi(step.y) != 1 or wall_at(edge_between(route[i - 1], cell)) != Wall.NONE:
				return false
		var square := PackedVector2Array([Vector2(cell), Vector2(cell) + Vector2(1, 0),
				Vector2(cell) + Vector2.ONE, Vector2(cell) + Vector2(0, 1)])
		var inner: PackedVector2Array = Geometry2D.offset_polygon(square, -EPSILON * 2.0)[0]
		for placed: PlacedObject in objects.values():
			if not Geometry2D.intersect_polygons(inner, placed.polygon()).is_empty():
				return false
	return true


## Adds a staircase and returns its id, or 0 if its route is not clear.
func add_stairs(flight: Staircase) -> int:
	if not can_add_stairs(flight.cells):
		return 0
	flight.id = _next_stairs_id
	_next_stairs_id += 1
	stairs[flight.id] = flight
	_changed()
	return flight.id


func remove_stairs(id: int) -> bool:
	if not stairs.erase(id):
		return false
	_changed()
	return true

#endregion


## Opens the floor for stairs below, clearing whatever was on those tiles.
## Tiles no longer above stairs can take floor again.
func set_holes(cells: Dictionary[Vector2i, bool]) -> void:
	if cells == holes:
		return
	holes = cells
	for cell: Vector2i in cells:
		_clear_floor(Rect2i(cell, Vector2i.ONE))
	_changed()


func remove_object(id: int) -> bool:
	if not objects.erase(id):
		return false
	_drop_orphans()
	_changed()
	return true


## The object covering a point in tile units, if any: something small on
## a surface before the surface itself.
func object_at(point: Vector2) -> PlacedObject:
	for placed: PlacedObject in objects.values():
		if placed.on_surface() and placed.rect.grow(0.05).has_point(point):
			return placed
	for placed: PlacedObject in objects.values():
		if placed.rect.has_point(point) and Geometry2D.is_point_in_polygon(point, placed.polygon()):
			return placed
	return null


## A tile in a room with no furniture over its middle, so someone sent
## there stands inside the room; the middle tile if every one is covered.
func clear_cell(room: Room) -> Vector2i:
	var in_room := objects_in_room(room).filter(func(placed: PlacedObject) -> bool: return placed.def.blocks)
	for cell in room.cells:
		var middle := Vector2(cell) + Vector2(0.5, 0.5)
		if not in_room.any(func(placed: PlacedObject) -> bool: return placed.rect.has_point(middle)):
			return cell
	return room.cells[room.cells.size() / 2]


func objects_in_room(room: Room) -> Array[PlacedObject]:
	var out: Array[PlacedObject] = []
	for placed: PlacedObject in objects.values():
		if room_at_point(placed.centre) == room:
			out.append(placed)
	return out

#endregion

#region Rooms

func rooms() -> Array[Room]:
	_update_rooms()
	return _rooms


## The room a cell belongs to, or null if the cell has no floor. A cell
## split by an angled wall belongs to the room with the bigger share of it.
func room_at(cell: Vector2i) -> Room:
	_update_rooms()
	return _room_lookup.get(cell)


## The room at a point in tile units, minding angled walls.
func room_at_point(point: Vector2) -> Room:
	_update_rooms()
	return _piece_rooms.get(_piece_id(piece_at(point)))


## Marks a room as a type. An empty type clears it.
func set_room_type(room: Room, type: StringName) -> void:
	_mark_cells(_room_types, room, type)


## Paints a zone (who may be in it) onto a room. An empty zone goes back to
## the room type's.
func set_room_zone(room: Room, zone: StringName) -> void:
	_mark_cells(_room_zones, room, zone)


func _mark_cells(marks: Dictionary[Vector2i, StringName], room: Room, value: StringName) -> void:
	for cell in room.cells:
		if value.is_empty():
			marks.erase(cell)
		else:
			marks[cell] = value
	_changed()

#endregion

#region Saving

## Everything on this level as plain data (no objects or resources), for
## saving and undo. Objects are stored by their def's id.
func to_data() -> Dictionary:
	var placed: Array = []
	for item: PlacedObject in objects.values():
		placed.append([item.id, item.def.id, item.angle, item.centre, item.look, item.on, item.spot])
	var ramp_list: Array = []
	for ramp in ramps:
		ramp_list.append([ramp.rect, ramp.rise, ramp.low, ramp.high])
	var flights: Array = []
	for flight: Staircase in stairs.values():
		flights.append([flight.id, flight.cells.duplicate(), flight.landings.duplicate(), flight.rounded,
				flight.style])
	return {
		"land": land.duplicate(),
		"floors": floors.duplicate(),
		"floor_heights": floor_heights.duplicate(),
		"walls": walls.duplicate(),
		"wall_styles": wall_styles.duplicate(),
		"window_kinds": window_kinds.duplicate(),
		"slants": slants.duplicate(),
		"slant_styles": slant_styles.duplicate(),
		"slant_window_kinds": slant_window_kinds.duplicate(),
		"wall_paints": wall_paints.duplicate(true),
		"slant_paints": slant_paints.duplicate(true),
		"piece_styles": piece_styles.duplicate(true),
		"objects": placed,
		"ramps": ramp_list,
		"stairs": flights,
		"holes": holes.duplicate(),
		"room_types": _room_types.duplicate(),
		"room_zones": _room_zones.duplicate(),
		"door_kinds": door_kinds.duplicate(),
		"next_object_id": _next_object_id,
		"next_stairs_id": _next_stairs_id,
	}


## Puts this level back as to_data() left it. `find_object` turns a def id
## into its ObjectDef; objects whose def is gone are left out.
func load_data(data: Dictionary, find_object: Callable) -> void:
	land.assign(data.get("land", land))
	floors.assign(data.get("floors", {}))
	floor_heights.assign(data.get("floor_heights", {}))
	walls.assign(data.get("walls", {}))
	wall_styles.assign(data.get("wall_styles", {}))
	window_kinds.assign(data.get("window_kinds", {}))
	slants.assign(data.get("slants", {}))
	slant_styles.assign(data.get("slant_styles", {}))
	slant_window_kinds.assign(data.get("slant_window_kinds", {}))
	wall_paints.assign(data.get("wall_paints", {}).duplicate(true))
	slant_paints.assign(data.get("slant_paints", {}).duplicate(true))
	piece_styles.assign(data.get("piece_styles", {}).duplicate(true))
	objects.clear()
	for entry: Array in data.get("objects", []):
		var def: ObjectDef = find_object.call(entry[1])
		if def == null:
			continue
		var item := PlacedObject.new()
		item.id = entry[0]
		item.def = def
		item.angle = entry[2]
		item.rotation = posmod(roundi(item.angle / (PI * 0.5)), 4)
		item.centre = entry[3]
		item.rect = polygon_bounds(object_polygon(def, item.centre, item.angle))
		if entry.size() > 4:
			item.look = clampi(entry[4], 0, def.look_count() - 1)
			item.on = entry[5]
			item.spot = entry[6]
		objects[item.id] = item
	ramps.clear()
	for entry: Array in data.get("ramps", []):
		var ramp := Ramp.new()
		ramp.rect = entry[0]
		ramp.rise = entry[1]
		ramp.low = entry[2]
		ramp.high = entry[3]
		ramps.append(ramp)
	stairs.clear()
	for entry: Array in data.get("stairs", []):
		var flight := Staircase.new()
		flight.id = entry[0]
		flight.cells.assign(entry[1])
		flight.landings.assign(entry[2])
		flight.rounded = entry[3]
		flight.style = entry[4]
		stairs[flight.id] = flight
	holes.assign(data.get("holes", {}))
	_room_types.assign(data.get("room_types", {}))
	_room_zones.assign(data.get("room_zones", {}))
	door_kinds.assign(data.get("door_kinds", {}))
	_next_object_id = data.get("next_object_id", 1)
	_next_stairs_id = data.get("next_stairs_id", 1)
	_changed()

#endregion

#region Compound actions

## Floor plus walls all round, like the room tool in Software Inc.
func build_room(rect: Rect2i, floor_type: StringName = DEFAULT_FLOOR,
		wall_type: StringName = DEFAULT_WALL, height := 0.0) -> void:
	var count := _fill_floor(rect, floor_type, height) + _build_walls(rect_perimeter(rect), wall_type)
	if count > 0:
		_changed()


## Clears a rectangle: objects, floor, and walls inside it. Walls around the
## edge go too, unless they still have floor on their far side, so knocking
## down one room leaves its neighbours closed in.
func demolish(rect: Rect2i) -> void:
	var count := _clear_floor(rect)
	for edge in rect_edges(rect):
		if wall_at(edge) == Wall.NONE:
			continue
		var sides := edge_cells(edge)
		var keep := has_floor(sides[0]) or has_floor(sides[1])
		if not keep and walls.erase(edge):
			wall_styles.erase(edge)
			window_kinds.erase(edge)
			wall_paints.erase(edge)
			count += 1
	# Angled walls go once no floor is left on either side of them.
	for key: Vector4i in slants.keys():
		var crossed := slant_crossings(key)
		if not crossed.any(func(cell: Vector2i) -> bool: return rect.has_point(cell)):
			continue
		if not crossed.any(has_floor):
			slants.erase(key)
			slant_styles.erase(key)
			slant_window_kinds.erase(key)
			slant_paints.erase(key)
			count += 1
	if count > 0:
		_changed()


#endregion


func _fill_floor(rect: Rect2i, type: StringName, height: float) -> int:
	var count := 0
	for cell in cells_in(rect):
		if owns(cell) and not holes.has(cell) and floors.get(cell) != type:
			if not floors.has(cell):
				floor_heights[cell] = height
				piece_styles.erase(cell)
			floors[cell] = type
			count += 1
	return count


## Removes floor in a rectangle, and every object touching it.
func _clear_floor(rect: Rect2i) -> int:
	var count := 0
	var area := Rect2(rect)
	for ramp in ramps.duplicate():
		if ramp.rect.intersects(rect):
			ramps.erase(ramp)
	for flight: Staircase in stairs.values():
		if flight.cells.any(rect.has_point):
			stairs.erase(flight.id)
			count += 1
	for placed: PlacedObject in objects.values():
		if placed.rect.grow(-EPSILON).intersects(area):
			objects.erase(placed.id)
			count += 1
	count += _drop_orphans()
	for cell in cells_in(rect):
		floor_heights.erase(cell)
		piece_styles.erase(cell)
		if floors.erase(cell):
			count += 1
		_room_types.erase(cell)
		_room_zones.erase(cell)
	return count


func _build_walls(edges: Array[Vector3i], style: StringName) -> int:
	var count := 0
	for edge in edges:
		if wall_at(edge) == Wall.NONE:
			if not can_build_wall(edge):
				continue
			walls[edge] = Wall.WALL
		elif wall_style(edge) == style:
			continue
		wall_styles[edge] = style
		wall_paints.erase(edge)
		count += 1
	return count


## The whole cells around a rectangle in tile units.
func _cell_bounds(rect: Rect2) -> Rect2i:
	var from := Vector2i(rect.position.floor())
	return Rect2i(from, Vector2i(rect.end.ceil()) - from)


func _changed() -> void:
	_rooms_dirty = true
	_slants_dirty = true
	changed.emit()


## Flood-fills the floor into rooms, piece by piece. Walls, doors and
## windows split rooms, angled ones included; reaching a piece with no floor
## without passing a wall means the room is not enclosed. An enclosed room
## is indoors unless an outdoor wall (a fence) bounds it.
func _update_rooms() -> void:
	if not _rooms_dirty:
		return
	_rooms_dirty = false
	_rooms.clear()
	_room_lookup.clear()
	_piece_rooms.clear()
	var best_area: Dictionary[Vector2i, float] = {}
	for start_cell: Vector2i in floors:
		for start: TilePiece in pieces(start_cell):
			if _piece_rooms.has(_piece_id(start)) or not piece_has_floor(start):
				continue
			var room := Room.new()
			room.id = _rooms.size()
			_piece_rooms[_piece_id(start)] = room
			var stack: Array[TilePiece] = [start]
			var fenced := false
			while not stack.is_empty():
				var piece: TilePiece = stack.pop_back()
				# A stairwell belongs to the room around it without being floor.
				if piece_has_floor(piece):
					room.pieces.append(_piece_id(piece))
					room.area += piece.area()
					if piece.cell not in room.cells:
						room.cells.append(piece.cell)
					if piece.area() > best_area.get(piece.cell, 0.0):
						best_area[piece.cell] = piece.area()
						_room_lookup[piece.cell] = room
				for i in piece.sides.size():
					var tag: Variant = piece.sides[i]
					if tag is Vector4i:
						fenced = fenced or is_outdoor_slant(tag)
						continue
					var next_cell: Vector2i = piece.cell + DIRECTIONS[tag]
					var edge := edge_between(piece.cell, next_cell)
					if wall_at(edge) != Wall.NONE:
						fenced = fenced or is_outdoor_wall(edge)
						continue
					var stretch := PackedVector2Array([piece.polygon[i],
							piece.polygon[(i + 1) % piece.polygon.size()]])
					for next: TilePiece in pieces(next_cell):
						if not next.sides_tagged(tag ^ 1).any(
								func(other: PackedVector2Array) -> bool:
									return TilePiece.overlaps(stretch, other)):
							continue
						if not piece_has_floor(next) and not holes.has(next_cell):
							room.enclosed = false
						elif not _piece_rooms.has(_piece_id(next)):
							_piece_rooms[_piece_id(next)] = room
							stack.append(next)
			room.indoor = room.enclosed and not fenced
			room.type = _settle(_room_types, room)
			room.zone = _settle(_room_zones, room)
			_rooms.append(room)


static func _piece_id(piece: TilePiece) -> Vector3i:
	return Vector3i(piece.cell.x, piece.cell.y, piece.index)


## The mark (type or zone) most of a room's cells carry, spread to the
## rest of its cells.
func _settle(marks: Dictionary[Vector2i, StringName], room: Room) -> StringName:
	var votes := {}
	for cell in room.cells:
		var mark: StringName = marks.get(cell, &"")
		if not mark.is_empty():
			votes[mark] = votes.get(mark, 0) + 1
	var best: StringName = &""
	for mark: StringName in votes:
		if best.is_empty() or votes[mark] > votes[best]:
			best = mark
	if not best.is_empty():
		for cell in room.cells:
			marks[cell] = best
	return best
