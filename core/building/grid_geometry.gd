class_name GridGeometry
extends RefCounted
## Pure geometry for the tile grid, shared by BuildingMap and anything else
## that works in cells, corners and edges. See BuildingMap for how cells,
## corners, edges and angled wall pieces ("slants") are numbered.

const EDGE_X := 0
const EDGE_Z := 1
const NO_EDGE := Vector3i(-1, -1, -1)
const DIRECTIONS: Array[Vector2i] = [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP]
## Objects may touch each other and walls; this stops rounding from
## counting a touch as an overlap.
const EPSILON := 0.001


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
static func rect_between(a: Vector2i, b: Vector2i) -> Rect2i:
	return Rect2i(a.min(b), (a - b).abs() + Vector2i.ONE)


## An object's footprint with its top-left corner at position.
static func object_rect(def: ObjectDef, position: Vector2, rotation: int) -> Rect2:
	var extent := def.size if rotation % 2 == 0 else Vector2(def.size.y, def.size.x)
	return Rect2(position, extent)


## An object's footprint, turned by `angle` radians about its centre.
static func object_polygon(def: ObjectDef, centre: Vector2, angle: float) -> PackedVector2Array:
	var half := def.size * 0.5
	var out := PackedVector2Array()
	for corner: Vector2 in [Vector2(-half.x, -half.y), Vector2(half.x, -half.y), half,
			Vector2(-half.x, half.y)]:
		out.append(centre + corner.rotated(angle))
	return out


static func polygon_bounds(points: PackedVector2Array) -> Rect2:
	var bounds := Rect2(points[0], Vector2.ZERO)
	for point in points:
		bounds = bounds.expand(point)
	return bounds


## Does the line from a to b pass through the inside of a polygon?
static func segment_crosses(points: PackedVector2Array, a: Vector2, b: Vector2) -> bool:
	var inner := Geometry2D.offset_polygon(points, -EPSILON * 2.0)
	if inner.is_empty():
		return false
	return not Geometry2D.intersect_polyline_with_polygon(PackedVector2Array([a, b]), inner[0]).is_empty()


## The two corners at the ends of an edge.
static func edge_ends(edge: Vector3i) -> Array[Vector2]:
	var start := Vector2(edge.x, edge.y)
	return [start, start + (Vector2.RIGHT if edge.z == EDGE_X else Vector2.DOWN)]


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


static func _gcd(a: int, b: int) -> int:
	while b != 0:
		var t := b
		b = a % b
		a = t
	return a
