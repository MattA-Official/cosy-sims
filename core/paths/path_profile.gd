class_name PathProfile
## How a run of path points sits on the land: a height for each point, and
## what each stretch between two points is. Gentle slopes follow the
## ground, steep ones become steps, and stretches over water become
## bridges that run straight from bank to bank.

enum Kind { GROUND, STEPS, BRIDGE }

## Rise per tile beyond which a stretch becomes steps.
const MAX_SLOPE := 0.35
## Lowest a bridge deck may be above the water.
const BRIDGE_CLEARANCE := 0.4

var points := PackedVector2Array()
var heights := PackedFloat32Array() ## One per point.
var kinds: Array[Kind] = [] ## One per stretch, so one fewer than points.


static func build(path_points: PackedVector2Array, terrain: Terrain) -> PathProfile:
	var profile := PathProfile.new()
	profile.points = path_points
	var count := path_points.size()
	var wet: Array[bool] = []
	var water := PackedFloat32Array()
	for point in path_points:
		var ground := terrain.height_at(point) if terrain != null else 0.0
		var surface := terrain.water_surface(point) if terrain != null else -INF
		profile.heights.append(ground)
		water.append(surface)
		wet.append(surface > ground)

	# Bridges: each run of wet points spans between the dry points either side.
	var i := 0
	while i < count:
		if not wet[i]:
			i += 1
			continue
		var start := i
		while i < count and wet[i]:
			i += 1
		var before := start - 1
		var after := i
		var highest_water := -INF
		for j in range(start, after):
			highest_water = maxf(highest_water, water[j])
		var deck_low := highest_water + BRIDGE_CLEARANCE
		var left := profile.heights[before] if before >= 0 else deck_low
		var right := profile.heights[after] if after < count else deck_low
		for j in range(start, after):
			var t := float(j - before) / float(after - before)
			profile.heights[j] = maxf(lerpf(left, right, t), deck_low)

	for j in count - 1:
		if wet[j] or wet[j + 1]:
			profile.kinds.append(Kind.BRIDGE)
			continue
		var run := path_points[j].distance_to(path_points[j + 1])
		var rise := absf(profile.heights[j + 1] - profile.heights[j])
		profile.kinds.append(Kind.STEPS if rise > run * MAX_SLOPE else Kind.GROUND)
	return profile


func has_kind(kind: Kind) -> bool:
	return kinds.has(kind)
