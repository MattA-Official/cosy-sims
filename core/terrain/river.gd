class_name River
extends RefCounted
## A river: a spline through control points, its bed carved into the ground
## and its water running downhill from source to mouth, never less than
## MIN_FALL a tile. From NAVIGABLE_WIDTH boats may use it. Kept by
## WaterLayer; the shape is worked out once, when it's drawn, and saved.

## Metres the bed falls at least each tile.
const MIN_FALL := 0.02
## Tiles between samples along it.
const STEP := 0.5
const NAVIGABLE_WIDTH := 4.0
const LEAST_WIDTH := 2.0
const MOST_WIDTH := 6.0
## How far the water sits below the banks it was carved from.
const FREEBOARD := 0.15

var points := PackedVector2Array()
## In tiles, 2 to 6.
var width := 3.0
## How deep the bed is carved below the ground.
var depth := 0.6
## Tiles a game minute the water seems to run, for the shader.
var flow := 1.5
## Sampled along the spline: the middle, and the bed's height there.
var line := PackedVector2Array()
var beds := PackedFloat32Array()


func navigable() -> bool:
	return width >= NAVIGABLE_WIDTH


## The water's height at sample i.
func surface(i: int) -> float:
	return beds[i] + depth - FREEBOARD


## Samples a smooth curve through the control points.
static func sample(through: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	if through.size() < 2:
		return out
	for i in through.size() - 1:
		var p0 := through[maxi(i - 1, 0)]
		var p1 := through[i]
		var p2 := through[i + 1]
		var p3 := through[mini(i + 2, through.size() - 1)]
		var steps := maxi(ceili(p1.distance_to(p2) / STEP), 1)
		for k in steps:
			var t := float(k) / steps
			var t2 := t * t
			var t3 := t2 * t
			out.append(0.5 * ((2.0 * p1) + (p2 - p0) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2
					+ (3.0 * p1 - p0 - 3.0 * p2 + p3) * t3))
	out.append(through[through.size() - 1])
	return out


## Works out the curve and a bed that always runs downhill, from the
## ground as it is now.
func shape(terrain: Terrain) -> void:
	line = sample(points)
	beds.resize(line.size())
	for i in line.size():
		var below := terrain.height_at(line[i]) - depth
		if i == 0:
			beds[i] = below
		else:
			beds[i] = minf(below, beds[i - 1] - MIN_FALL * line[i].distance_to(line[i - 1]))


## The corner heights that carve the bed: every corner within half the
## width of the middle drops to the bed there, unless already lower.
func carving(terrain: Terrain) -> Dictionary:
	var nearest := {}
	var reach := width * 0.5
	for i in line.size():
		var middle := line[i]
		var from := Vector2i((middle - Vector2.ONE * reach).floor())
		var to := Vector2i((middle + Vector2.ONE * reach).ceil())
		for z in range(from.y, to.y + 1):
			for x in range(from.x, to.x + 1):
				var corner := Vector2i(x, z)
				var distance := Vector2(corner).distance_to(middle)
				if distance <= reach and terrain.in_bounds(corner) and (not nearest.has(corner) or distance < nearest[corner][0]):
					nearest[corner] = [distance, i]
	var out := {}
	for corner: Vector2i in nearest:
		var bed := beds[nearest[corner][1]]
		if terrain.corner_height(corner) > bed:
			out[corner] = bed
	return out


## The tiles it covers, each with its water height.
func cells() -> Dictionary[Vector2i, float]:
	var out: Dictionary[Vector2i, float] = {}
	var best: Dictionary[Vector2i, float] = {}
	var reach := width * 0.5
	for i in line.size():
		var middle := line[i]
		var from := Vector2i((middle - Vector2.ONE * reach).floor())
		var to := Vector2i((middle + Vector2.ONE * reach).ceil())
		for z in range(from.y, to.y + 1):
			for x in range(from.x, to.x + 1):
				var cell := Vector2i(x, z)
				var distance := (Vector2(cell) + Vector2(0.5, 0.5)).distance_to(middle)
				if distance <= reach and (not best.has(cell) or distance < best[cell]):
					best[cell] = distance
					out[cell] = surface(i)
	return out


## The sample nearest a point, and how far it is: [index, distance].
func nearest(point: Vector2) -> Array:
	var best := [0, INF]
	for i in line.size():
		var distance := line[i].distance_to(point)
		if distance < best[1]:
			best = [i, distance]
	return best


func to_data() -> Array:
	return [points, width, depth, flow, line, beds]


static func from_data(data: Array) -> River:
	var river := River.new()
	river.points = data[0]
	river.width = data[1]
	river.depth = data[2]
	river.flow = data[3]
	river.line = data[4]
	river.beds = data[5]
	return river
