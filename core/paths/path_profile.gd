class_name PathProfile
## How a run of path points sits on the land: a height for each point, and
## what each stretch between two points is.
##
## A ground path follows the land and is never anything else: too steep or
## through water and it cannot be built. Stairs, ramps and bridges are a
## choice you make while placing (a built path), and run straight from the
## height of one end to the other. A built path steeper than a ground path
## may be is stairs, with steps the same height as stairs indoors; a gentle
## one is a ramp, and becomes a bridge where it is well clear of the ground.

enum Kind { GROUND, STEPS, BRIDGE }

## Rise per tile beyond which a ground path is too steep, and a built path
## becomes stairs.
const MAX_SLOPE := 0.35
## The shallowest a stair tread may be, in tiles.
const MIN_GOING := 0.3
## Lowest a bridge deck may be above the water.
const BRIDGE_CLEARANCE := 0.15
## How high a ramp may be off the ground before it is a bridge on piers.
const BRIDGE_HEIGHT := 0.4

var points := PackedVector2Array()
var heights := PackedFloat32Array() ## One per point.
var kinds: Array[Kind] = [] ## One per stretch, so one fewer than points.
var built := false
## How many steps a stair path has. 0 when it is not stairs.
var steps := 0
## Why it cannot be built, or "" if it can.
var problem := ""


static func build(path_points: PackedVector2Array, terrain: Terrain, is_built := false,
		from_height := NAN, to_height := NAN) -> PathProfile:
	var profile := PathProfile.new()
	profile.points = path_points
	profile.built = is_built
	var count := path_points.size()
	var ground := PackedFloat32Array()
	var water := PackedFloat32Array()
	var length := 0.0
	var along := PackedFloat32Array([0.0])
	for i in count:
		var point := path_points[i]
		ground.append(terrain.height_at(point) if terrain != null else 0.0)
		water.append(terrain.water_surface(point) if terrain != null else -INF)
		if i > 0:
			length += path_points[i - 1].distance_to(point)
			along.append(length)

	if not is_built:
		profile.heights = ground
		for j in count - 1:
			profile.kinds.append(Kind.GROUND)
			var run := path_points[j].distance_to(path_points[j + 1])
			if absf(ground[j + 1] - ground[j]) > run * MAX_SLOPE + 0.001:
				profile.problem = "Too steep. Page Up or Down to build stairs."
		for j in count:
			if water[j] > ground[j]:
				profile.problem = "In the water. Page Up to build a bridge."
		return profile

	var h0 := from_height if not is_nan(from_height) else ground[0]
	var h1 := to_height if not is_nan(to_height) else ground[count - 1]
	for i in count:
		profile.heights.append(lerpf(h0, h1, along[i] / maxf(length, 0.001)))
	var stairs := absf(h1 - h0) > length * MAX_SLOPE
	if stairs:
		profile.steps = maxi(1, roundi(absf(h1 - h0) / Staircase.RISE))
		if length / profile.steps < MIN_GOING:
			profile.problem = "Too steep even for stairs."
	for j in count - 1:
		if stairs:
			profile.kinds.append(Kind.STEPS)
		elif maxf(profile.heights[j] - ground[j], profile.heights[j + 1] - ground[j + 1]) > BRIDGE_HEIGHT \
				or water[j] > ground[j] or water[j + 1] > ground[j + 1]:
			profile.kinds.append(Kind.BRIDGE)
		else:
			profile.kinds.append(Kind.GROUND)
	for j in count:
		if water[j] > ground[j] and profile.heights[j] < water[j] + BRIDGE_CLEARANCE:
			profile.problem = "Too low over the water. Page Up to raise it."
	return profile


func has_kind(kind: Kind) -> bool:
	return kinds.has(kind)
