class_name StartingLandscape
## The world around a new prison: flat land to build on and to buy, with a
## few small features dotted about it (a pond, a stream, a copse, an old
## barn or a cottage), and gentle hills beyond the land for sale that fade
## into the fog. Seeded, so it comes out the same every time.

## Tiles a feature keeps back from the edge of its plot.
const FEATURE_INSET := 4
## Of the plots for sale, the share with a feature.
const FEATURE_SHARE := 0.4
## Tiles past the land for sale that trees still grow, before the fog.
const TREE_MARGIN := 4.0


## Shapes the ground. Land for sale is flat at height 0; owned land is too,
## unless `base` gives a height for each corner of it (terraces, a moat),
## which fades back to flat a few tiles past its edge. Past `area` (the
## land for sale) gentle hills rise into the fog.
static func shape(terrain: Terrain, land: Rect2i, pond_centre: Vector2, pond_radius := 6.0,
		seed := 7, base: Callable = Callable(), area := Rect2i()) -> void:
	var noise := FastNoiseLite.new()
	noise.seed = seed
	noise.frequency = 0.035
	noise.fractal_octaves = 3
	if not area.has_area():
		area = land
	terrain.generate(func(corner: Vector2i) -> float:
		var inside := 0.0
		if base.is_valid():
			var nearest := corner.clamp(land.position, land.end)
			inside = lerpf(base.call(nearest), 0.0, smoothstep(0.0, 8.0, _distance_outside(Vector2(corner), land)))
		var hills := (noise.get_noise_2d(corner.x, corner.y) * 0.5 + 0.5) * 4.0
		var height := lerpf(inside, hills, smoothstep(0.0, 16.0, _distance_outside(Vector2(corner), area)))
		var to_pond := Vector2(corner).distance_to(pond_centre)
		var dip := 1.0 - smoothstep(pond_radius * 0.4, pond_radius, to_pond)
		return lerpf(height, -1.4, dip))


## Dots small features over the land for sale, a plot at a time: a pond, a
## stream, a copse, an old barn or a cottage. Plots touching `land`, and
## any holding a spot in `keep_clear`, are left alone.
static func features(building: Building, terrain: Terrain, water: WaterLayer, foliage: FoliageLayer,
		area: Rect2i, land: Rect2i, keep_clear: Array[Vector2] = [], seed := 7) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	for z in range(area.position.y, area.end.y, LandPlots.SIZE):
		for x in range(area.position.x, area.end.x, LandPlots.SIZE):
			var plot := Rect2i(x, z, LandPlots.SIZE, LandPlots.SIZE)
			var roll := rng.randf()
			var kind := rng.randi() % 5
			if roll > FEATURE_SHARE or plot.grow(1).intersects(land) \
					or keep_clear.any(func(spot: Vector2) -> bool: return Rect2(plot).grow(6).has_point(spot)):
				continue
			var inner := plot.grow(-FEATURE_INSET)
			var at := Vector2(inner.position) + Vector2(rng.randf(), rng.randf()) * Vector2(inner.size - Vector2i(8, 8)) \
					+ Vector2(4, 4)
			match kind:
				0: _pond(terrain, water, at, rng.randf_range(3.0, 4.5))
				1: _stream(terrain, water, inner, rng)
				2: _copse(foliage, at, rng)
				3: _cottage(building, Vector2i(at.floor()) - Vector2i(3, 2), rng)
				4: _barn(building, Vector2i(at.floor()) - Vector2i(4, 3))


static func _pond(terrain: Terrain, water: WaterLayer, centre: Vector2, radius: float) -> void:
	var heights := {}
	for corner in BuildingMap.cells_in(Rect2i(Vector2i(centre.floor()) - Vector2i.ONE * ceili(radius + 1),
			Vector2i.ONE * (ceili(radius + 1) * 2 + 1))):
		var dip := 1.0 - smoothstep(radius * 0.4, radius, Vector2(corner).distance_to(centre))
		if dip > 0.0:
			heights[corner] = minf(terrain.corner_height(corner), lerpf(0.0, -1.0, dip))
	terrain.set_corners(heights)
	water.fill_at(Vector2i(centre.floor()))


## A brook winding across a plot, closed at both ends.
static func _stream(terrain: Terrain, water: WaterLayer, inner: Rect2i, rng: RandomNumberGenerator) -> void:
	var across := rng.randf() < 0.5
	var phase := rng.randf() * TAU
	var middle := Vector2(inner.get_center())
	var length := float(inner.size.x if across else inner.size.y)
	var heights := {}
	for corner in BuildingMap.cells_in(inner.grow(1)):
		var along := float(corner.x - inner.position.x) if across else float(corner.y - inner.position.y)
		var t := along / length
		var bend := sin(t * TAU * 1.2 + phase) * 3.0
		var off := absf((corner.y - middle.y if across else corner.x - middle.x) - bend)
		var ends := smoothstep(0.0, 0.12, t) * smoothstep(1.0, 0.88, t)
		var dip := (1.0 - smoothstep(0.6, 1.6, off)) * ends
		if dip > 0.0:
			heights[corner] = minf(terrain.corner_height(corner), -0.7 * dip)
	terrain.set_corners(heights)
	var start := Vector2(inner.position.x + length * 0.5, middle.y + sin(0.5 * TAU * 1.2 + phase) * 3.0) if across \
			else Vector2(middle.x + sin(0.5 * TAU * 1.2 + phase) * 3.0, inner.position.y + length * 0.5)
	water.fill_at(Vector2i(start.floor()))


static func _copse(foliage: FoliageLayer, centre: Vector2, rng: RandomNumberGenerator) -> void:
	var oak := PrisonCatalogue.PLANTS[0]
	var bush := PrisonCatalogue.PLANTS[2]
	for i in rng.randi_range(9, 15):
		var at := centre + Vector2.from_angle(rng.randf() * TAU) * sqrt(rng.randf()) * 4.5
		var def: FoliageDef = oak if rng.randf() < 0.75 else bush
		foliage.add(def, at, rng.randf_range(def.scale_range.x, def.scale_range.y), rng.randf() * TAU)


## A little brick cottage with a door and windows, yours if you buy the plot.
static func _cottage(building: Building, at: Vector2i, rng: RandomNumberGenerator) -> void:
	var rect := Rect2i(at, Vector2i(6, 5))
	_built_on(building, rect, func(map: BuildingMap) -> void:
		map.build_room(rect, &"wood", &"brick")
		var door := Vector3i(rect.position.x + 2 + rng.randi() % 2, rect.end.y, BuildingMap.EDGE_X)
		map.set_door(door, true)
		for x in [rect.position.x + 1, rect.end.x - 2]:
			map.set_opening(Vector3i(x, rect.position.y, BuildingMap.EDGE_X), BuildingMap.Wall.WINDOW))


## An old barn: a big plain shed with wide doors.
static func _barn(building: Building, at: Vector2i) -> void:
	var rect := Rect2i(at, Vector2i(8, 6))
	_built_on(building, rect, func(map: BuildingMap) -> void:
		map.build_room(rect, &"concrete", &"plaster")
		for x in [rect.position.x + 3, rect.position.x + 4]:
			map.set_door(Vector3i(x, rect.end.y, BuildingMap.EDGE_X), true))


## Builds on land you don't own yet, by owning it for a moment.
static func _built_on(building: Building, rect: Rect2i, build: Callable) -> void:
	var lot := rect.grow(1)
	building.add_land(lot)
	build.call(building.ground())
	building.remove_land(lot)


## Scatters a few trees and bushes over the land for sale (`area`, or the
## whole map), and (with `garden`) a few flowers and bushes around the
## starter prison.
static func plant(foliage: FoliageLayer, terrain: Terrain, map: BuildingMap,
		layout_origin: Vector2i, seed := 7, garden := true, area := Rect2i()) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var oak := PrisonCatalogue.PLANTS[0]
	var blossom := PrisonCatalogue.PLANTS[1]
	var bush := PrisonCatalogue.PLANTS[2]
	# Keep trees out of the water and a little back from the shore.
	var wild := func(position: Vector2) -> bool:
		if map.owns(Vector2i(position.floor())) or map.has_floor(Vector2i(position.floor())):
			return false
		for offset: Vector2 in [Vector2.ZERO, Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
			if terrain.water_surface(position + offset) > terrain.height_at(position) - 0.3:
				return false
		return true
	var wood := Rect2(area).grow(TREE_MARGIN) if area.has_area() else Rect2(Vector2.ZERO, Vector2(terrain.size))
	for i in roundi(wood.get_area() / 60.0):
		var position := wood.position + Vector2(rng.randf(), rng.randf()) * wood.size
		if not wild.call(position):
			continue
		var roll := rng.randf()
		var def: FoliageDef = oak if roll < 0.6 else (bush if roll < 0.85 else blossom)
		foliage.add(def, position, rng.randf_range(def.scale_range.x, def.scale_range.y),
				rng.randf() * TAU)

	if not garden:
		return
	# A little greenery around the prison itself.
	var tame := func(position: Vector2) -> bool:
		var cell := Vector2i(position.floor())
		return map.owns(cell) and not map.has_floor(cell)
	var o := Vector2(layout_origin)
	foliage.paint(blossom, o + Vector2(21.5, 2.0), 1.5, 4, rng, tame)
	foliage.paint(bush, o + Vector2(20.5, 7.0), 2.0, 12, rng, tame)
	foliage.paint(PrisonCatalogue.PLANTS[3], o + Vector2(4.0, 11.5), 2.5, 40, rng, tame)
	foliage.paint(PrisonCatalogue.PLANTS[4], o + Vector2(14.0, 11.5), 2.5, 40, rng, tame)


## How far a point is outside a rectangle, or 0 inside it.
static func _distance_outside(point: Vector2, rect: Rect2i) -> float:
	var r := Rect2(rect)
	var dx := maxf(maxf(r.position.x - point.x, point.x - r.end.x), 0.0)
	var dz := maxf(maxf(r.position.y - point.y, point.y - r.end.y), 0.0)
	return Vector2(dx, dz).length()
