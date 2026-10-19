class_name TilePiece
extends RefCounted
## Part of a tile left over when angled walls cross it. A tile with no angled
## walls is one piece, the whole square. Pieces are convex polygons in tile
## units, and each side remembers what it lies along: one of the tile's own
## sides, or the angled wall that cut it.

## Side tags for the tile's own sides, matching BuildingMap.DIRECTIONS.
const SIDE_RIGHT := 0
const SIDE_LEFT := 1
const SIDE_DOWN := 2
const SIDE_UP := 3

const EPSILON := 0.0001

var cell: Vector2i
var index := 0
var polygon: PackedVector2Array
## One tag per side: side i runs from polygon[i] to polygon[i + 1]. An int is
## one of the tile's sides (SIDE_*); a Vector4i is the angled wall's key.
var sides: Array = []


## The whole tile as one piece.
static func square(at: Vector2i) -> TilePiece:
	var piece := TilePiece.new()
	piece.cell = at
	var p := Vector2(at)
	piece.polygon = PackedVector2Array([p, p + Vector2(1, 0), p + Vector2(1, 1), p + Vector2(0, 1)])
	piece.sides = [SIDE_UP, SIDE_RIGHT, SIDE_DOWN, SIDE_LEFT]
	return piece


## Cuts a tile into pieces along each wall line. `lines` maps a wall key to
## its two end points. Lines that only touch the tile change nothing.
static func split(at: Vector2i, lines: Dictionary) -> Array[TilePiece]:
	var pieces: Array[TilePiece] = [square(at)]
	for key: Vector4i in lines:
		var ends: Array = lines[key]
		var next: Array[TilePiece] = []
		for piece in pieces:
			for keep in [1.0, -1.0]:
				var part := piece._clip(ends[0], ends[1], key, keep)
				if part != null:
					next.append(part)
		pieces = next
	for i in pieces.size():
		pieces[i].index = i
	return pieces


func area() -> float:
	var total := 0.0
	for i in polygon.size():
		total += polygon[i].cross(polygon[(i + 1) % polygon.size()])
	return absf(total) * 0.5


func centre() -> Vector2:
	var total := Vector2.ZERO
	for point in polygon:
		total += point
	return total / maxf(polygon.size(), 1)


func has_point(point: Vector2) -> bool:
	return Geometry2D.is_point_in_polygon(point, polygon)


## Is this the whole tile?
func is_whole() -> bool:
	return polygon.size() == 4 and absf(area() - 1.0) < EPSILON


## The stretch of this piece's outline that lies along a side tag, as pairs
## of points. Most pieces have at most one.
func sides_tagged(tag: Variant) -> Array[PackedVector2Array]:
	var out: Array[PackedVector2Array] = []
	for i in sides.size():
		if typeof(sides[i]) == typeof(tag) and sides[i] == tag:
			out.append(PackedVector2Array([polygon[i], polygon[(i + 1) % polygon.size()]]))
	return out


## Do two stretches along the same line share more than a point?
static func overlaps(a: PackedVector2Array, b: PackedVector2Array) -> bool:
	var dir := (a[1] - a[0]).normalized()
	var a0 := a[0].dot(dir)
	var a1 := a[1].dot(dir)
	var b0 := b[0].dot(dir)
	var b1 := b[1].dot(dir)
	return minf(maxf(a0, a1), maxf(b0, b1)) - maxf(minf(a0, a1), minf(b0, b1)) > EPSILON


## The part of this piece on one side of the line from a to b, or null if
## nothing worth keeping is there.
func _clip(a: Vector2, b: Vector2, key: Vector4i, keep: float) -> TilePiece:
	var points := PackedVector2Array()
	var tags: Array = []
	var count := polygon.size()
	for i in count:
		var p := polygon[i]
		var q := polygon[(i + 1) % count]
		var sp := (b - a).cross(p - a) * keep
		var sq := (b - a).cross(q - a) * keep
		if sp >= -EPSILON:
			points.append(p)
			tags.append(sides[i])
			if sq < -EPSILON and sp > EPSILON:
				points.append(p.lerp(q, sp / (sp - sq)))
				tags.append(key)
			elif sq < -EPSILON:
				tags[-1] = key
		elif sq > EPSILON:
			points.append(p.lerp(q, sp / (sp - sq)))
			tags.append(sides[i])
	# Drop points that landed on top of each other.
	var i := 0
	while i < points.size() and points.size() > 2:
		if points[i].distance_to(points[(i + 1) % points.size()]) < EPSILON:
			points.remove_at(i)
			tags.remove_at(i)
		else:
			i += 1
	if points.size() < 3:
		return null
	var piece := TilePiece.new()
	piece.cell = cell
	piece.polygon = points
	piece.sides = tags
	if piece.area() < EPSILON:
		return null
	return piece
