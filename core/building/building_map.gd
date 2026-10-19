class_name BuildingMap
extends RefCounted
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
## Floors and walls carry a style id (see FloorDef and WallDef). Whether a
## room is indoors is decided by its walls: enclosed by indoor walls and
## doors means indoors; fences and hedges leave it outdoors.
##
## You can only build on land you own, which starts as one rectangle and can
## grow with add_land().

signal changed

const EDGE_X := 0
const EDGE_Z := 1
const NO_EDGE := Vector3i(-1, -1, -1)
const DIRECTIONS: Array[Vector2i] = [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP]
## Objects may touch each other and walls; this stops rounding from
## counting a touch as an overlap.
const EPSILON := 0.001
const DEFAULT_FLOOR := &"concrete"
const DEFAULT_WALL := &"plaster"
## Neighbouring floors further apart in height than this need a ramp or
## stairs between them; closer ones are a step people can take.
const MAX_STEP := 0.25

enum Wall { NONE, WALL, DOOR, WINDOW }

## Kinds of window. Both let light and sight through but nobody past.
const WINDOW_GLASS := &"glass"
const WINDOW_BARS := &"bars"


class PlacedObject:
	var id: int
	var def: ObjectDef
	var rotation: int ## Quarter turns, 0 to 3.
	var rect: Rect2 ## The footprint in tile units, after rotation.


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
## Points in tiles where a piece of floor was taken up. Any piece holding one
## of these points has no floor, though the rest of its tile does.
var floor_cuts: Dictionary[Vector2i, PackedVector2Array] = {}
var objects: Dictionary[int, PlacedObject] = {}
var ramps: Array[Ramp] = []
## Tiles open to stairs coming up from the level below. No floor goes here.
var holes: Dictionary[Vector2i, bool] = {}

## Room types are stored per cell, so they survive rooms being split, merged
## or extended: each room takes the type most of its cells carry.
var _room_types: Dictionary[Vector2i, StringName] = {}
var _next_object_id := 1
var _rooms: Array[Room] = []
var _room_lookup: Dictionary[Vector2i, Room] = {}
var _rooms_dirty := true
## Rooms by piece: Vector3i(cell x, cell z, piece index).
var _piece_rooms: Dictionary[Vector3i, Room] = {}
var _slant_cells: Dictionary[Vector2i, Array] = {}
var _pieces: Dictionary[Vector2i, Array] = {}
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


## The smallest rectangle covering all owned land.
func land_bounds() -> Rect2i:
	var bounds := land[0]
	for rect in land:
		bounds = bounds.merge(rect)
	return bounds

#endregion

#region Geometry helpers

## The edge shared by two neighbouring cells, or NO_EDGE if they do not touch.
static func edge_between(a: Vector2i, b: Vector2i) -> Vector3i:
	match b - a:
		Vector2i.RIGHT: return Vector3i(b.x, b.y, EDGE_Z)
		Vector2i.LEFT: return Vector3i(a.x, a.y, EDGE_Z)
		Vector2i.DOWN: return Vector3i(b.x, b.y, EDGE_X)
		Vector2i.UP: return Vector3i(a.x, a.y, EDGE_X)
	return NO_EDGE


## The two cells either side of an edge.
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


## The cells a rectangle in tile units touches.
static func cells_under(rect: Rect2) -> Array[Vector2i]:
	var from := Vector2i((rect.position + Vector2.ONE * EPSILON).floor())
	var to := Vector2i((rect.end - Vector2.ONE * EPSILON).ceil())
	return cells_in(Rect2i(from, to - from))


## The smallest rectangle covering both cells.
## The way stairs climb for a rotation: along their length, away from the
## foot.
static func rise_direction(rotation: int) -> Vector2i:
	return [Vector2i(0, 1), Vector2i(-1, 0), Vector2i(0, -1), Vector2i(1, 0)][posmod(rotation, 4)]


## The tiles at the bottom and top of a flight of stairs, inside its footprint.
static func stair_ends(placed: PlacedObject) -> Array[Vector2i]:
	var dir := rise_direction(placed.rotation)
	var cells := cells_under(placed.rect)
	var low := cells[0]
	var high := cells[0]
	for cell in cells:
		if Vector2(cell).dot(dir) < Vector2(low).dot(dir):
			low = cell
		if Vector2(cell).dot(dir) > Vector2(high).dot(dir):
			high = cell
	return [low, high]


static func rect_between(a: Vector2i, b: Vector2i) -> Rect2i:
	return Rect2i(a.min(b), (a - b).abs() + Vector2i.ONE)


## An object's footprint with its top-left corner at position.
static func object_rect(def: ObjectDef, position: Vector2, rotation: int) -> Rect2:
	var extent := def.size if rotation % 2 == 0 else Vector2(def.size.y, def.size.x)
	return Rect2(position, extent)


## Where an object centred on a point should go, snapped as the object likes.
## Returns the top-left corner of its footprint.
static func snapped_position(def: ObjectDef, centre: Vector2, rotation: int,
		snap: ObjectDef.Snap) -> Vector2:
	var corner := centre - object_rect(def, Vector2.ZERO, rotation).size * 0.5
	match snap:
		ObjectDef.Snap.TILE:
			return corner.round()
		ObjectDef.Snap.QUARTER:
			return (corner * 4.0).round() / 4.0
	return corner


## Does a wall on this edge pass through the inside of a rectangle?
static func edge_crosses(edge: Vector3i, rect: Rect2) -> bool:
	var inner := rect.grow(-EPSILON)
	if edge.z == EDGE_X:
		return edge.y > inner.position.y and edge.y < inner.end.y \
				and edge.x + 1 > inner.position.x and edge.x < inner.end.x
	return edge.x > inner.position.x and edge.x < inner.end.x \
			and edge.y + 1 > inner.position.y and edge.y < inner.end.y

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
		return absf(edge_height(a, b - a) - edge_height(b, a - b)) <= MAX_STEP + EPSILON
	return true


## Can a wall go on this edge? Not off our land, and not through an object.
func can_build_wall(edge: Vector3i) -> bool:
	if not edge_in_bounds(edge):
		return false
	for placed: PlacedObject in objects.values():
		if edge_crosses(edge, placed.rect):
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
			count += 1
	if count > 0:
		_changed()
	return count


## Turns a wall into a door, or a door back into a wall.
func set_door(edge: Vector3i, is_door: bool) -> bool:
	return set_opening(edge, Wall.DOOR if is_door else Wall.WALL)


## Makes a wall piece plain, a door or a window. Windows need a kind, and
## can't go in outdoor walls such as fences. Returns whether anything changed.
func set_opening(edge: Vector3i, kind: Wall, window: StringName = WINDOW_GLASS) -> bool:
	if wall_at(edge) == Wall.NONE or kind == Wall.NONE:
		return false
	if kind == Wall.WINDOW and is_outdoor_wall(edge):
		return false
	if walls[edge] == kind and (kind != Wall.WINDOW or window_kind(edge) == window):
		return false
	walls[edge] = kind
	if kind == Wall.WINDOW:
		window_kinds[edge] = window
	else:
		window_kinds.erase(edge)
	_changed()
	return true

#endregion

#region Angled walls

## The key for an angled wall piece between two corners, smaller corner first.
static func slant_key(a: Vector2i, b: Vector2i) -> Vector4i:
	if b.x < a.x or (b.x == a.x and b.y < a.y):
		var swap := a
		a = b
		b = swap
	return Vector4i(a.x, a.y, b.x, b.y)


static func slant_ends(key: Vector4i) -> Array[Vector2i]:
	return [Vector2i(key.x, key.y), Vector2i(key.z, key.w)]


## The angled wall pieces along a line between two corners: one piece per
## stretch between corners the line passes through exactly. Nothing if the
## line runs along X or Z, which is for ordinary walls.
static func slants_on_line(from: Vector2i, to: Vector2i) -> Array[Vector4i]:
	var out: Array[Vector4i] = []
	var d := to - from
	if d.x == 0 or d.y == 0:
		return out
	var steps := _gcd(absi(d.x), absi(d.y))
	var step := d / steps
	for i in steps:
		out.append(slant_key(from + step * i, from + step * (i + 1)))
	return out


## The cells an angled wall piece cuts through.
static func slant_crossings(key: Vector4i) -> Array[Vector2i]:
	var ends := slant_ends(key)
	var a := Vector2(ends[0])
	var b := Vector2(ends[1])
	var out: Array[Vector2i] = []
	for cell in cells_in(Rect2i(ends[0].min(ends[1]), (ends[1] - ends[0]).abs())):
		var above := false
		var below := false
		for offset: Vector2 in [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]:
			var side := (b - a).cross(Vector2(cell) + offset - a)
			above = above or side > EPSILON
			below = below or side < -EPSILON
		if above and below:
			out.append(cell)
	return out


## Does an angled wall piece pass through the inside of a rectangle?
static func slant_crosses(key: Vector4i, rect: Rect2) -> bool:
	var ends := slant_ends(key)
	var inner := rect.grow(-EPSILON)
	var a := Vector2(ends[0])
	var b := Vector2(ends[1])
	if not inner.intersects(Rect2(a.min(b), (b - a).abs())):
		return false
	if inner.has_point(a) or inner.has_point(b):
		return true
	var corners := [inner.position, Vector2(inner.end.x, inner.position.y), inner.end,
			Vector2(inner.position.x, inner.end.y)]
	for i in 4:
		if Geometry2D.segment_intersects_segment(a, b, corners[i], corners[(i + 1) % 4]) != null:
			return true
	return false


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
		if slant_crosses(key, placed.rect):
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
	return [TilePiece.square(cell)]


## The piece of a tile holding a point, in tile units.
func piece_at(point: Vector2) -> TilePiece:
	var cell := Vector2i(point.floor())
	for piece: TilePiece in pieces(cell):
		if piece.has_point(point):
			return piece
	return pieces(cell)[0]


## Whether a piece of a tile has floor: the tile has, and the piece was not
## taken up on its own.
func piece_has_floor(piece: TilePiece) -> bool:
	if not floors.has(piece.cell):
		return false
	for point in floor_cuts.get(piece.cell, PackedVector2Array()):
		if piece.has_point(point):
			return false
	return true


## Takes up, or puts back, the floor of just the piece of a tile under a
## point. Returns whether anything changed.
func set_piece_floor(point: Vector2, has: bool) -> bool:
	var piece := piece_at(point)
	if not floors.has(piece.cell) or piece_has_floor(piece) == has:
		return false
	var cuts: PackedVector2Array = floor_cuts.get(piece.cell, PackedVector2Array())
	if has:
		var kept := PackedVector2Array()
		for cut in cuts:
			if not piece.has_point(cut):
				kept.append(cut)
		cuts = kept
	else:
		if pieces(piece.cell).size() < 2:
			return false
		cuts.append(piece.centre())
	if cuts.is_empty():
		floor_cuts.erase(piece.cell)
	else:
		floor_cuts[piece.cell] = cuts
	_changed()
	return true


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


static func _gcd(a: int, b: int) -> int:
	while b != 0:
		var t := b
		b = a % b
		a = t
	return a

#endregion

#region Objects

func can_place(def: ObjectDef, position: Vector2, rotation: int) -> bool:
	var rect := object_rect(def, position, rotation)
	for cell in cells_under(rect):
		if not has_floor(cell) or ramp_at(cell) != null:
			return false
	for placed: PlacedObject in objects.values():
		if placed.rect.grow(-EPSILON).intersects(rect):
			return false
	# An object cannot straddle a wall or door.
	for edge in rect_edges(_cell_bounds(rect)):
		if wall_at(edge) != Wall.NONE and edge_crosses(edge, rect):
			return false
	for key: Vector4i in slants:
		if slant_crosses(key, rect):
			return false
	return true


## Places an object and returns its id, or 0 if it does not fit.
func place_object(def: ObjectDef, position: Vector2, rotation: int) -> int:
	if not can_place(def, position, rotation):
		return 0
	var placed := PlacedObject.new()
	placed.id = _next_object_id
	_next_object_id += 1
	placed.def = def
	placed.rotation = posmod(rotation, 4)
	placed.rect = object_rect(def, position, rotation)
	objects[placed.id] = placed
	_changed()
	return placed.id


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
		if not has_floor(cell) or ramp_at(cell) != null:
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
	_changed()
	return true


## The object covering a point in tile units, if any.
func object_at(point: Vector2) -> PlacedObject:
	for placed: PlacedObject in objects.values():
		if placed.rect.has_point(point):
			return placed
	return null


func objects_in_room(room: Room) -> Array[PlacedObject]:
	var out: Array[PlacedObject] = []
	for placed: PlacedObject in objects.values():
		if room_at_point(placed.rect.get_center()) == room:
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
	for cell in room.cells:
		if type.is_empty():
			_room_types.erase(cell)
		else:
			_room_types[cell] = type
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
	for placed: PlacedObject in objects.values():
		if placed.rect.grow(-EPSILON).intersects(area):
			objects.erase(placed.id)
			count += 1
	for cell in cells_in(rect):
		floor_heights.erase(cell)
		floor_cuts.erase(cell)
		if floors.erase(cell):
			count += 1
		_room_types.erase(cell)
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
			_settle_room_type(room)
			_rooms.append(room)


static func _piece_id(piece: TilePiece) -> Vector3i:
	return Vector3i(piece.cell.x, piece.cell.y, piece.index)


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
