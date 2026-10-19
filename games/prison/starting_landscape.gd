class_name StartingLandscape
## The world around a new prison: flat land to build on, gentle hills beyond
## it, a pond, and some trees. Seeded, so it comes out the same every time.


## Shapes the ground. Owned land stays flat at height 0 so the sample
## layout sits on level ground; hills fade in a few tiles past its edge.
static func shape(terrain: Terrain, land: Rect2i, pond_centre: Vector2, pond_radius := 6.0,
		seed := 7) -> void:
	var noise := FastNoiseLite.new()
	noise.seed = seed
	noise.frequency = 0.035
	noise.fractal_octaves = 3
	terrain.generate(func(corner: Vector2i) -> float:
		var outside := _distance_outside(Vector2(corner), land)
		var hills := (noise.get_noise_2d(corner.x, corner.y) * 0.5 + 0.5) * 6.5
		var height := hills * smoothstep(0.0, 8.0, outside)
		var to_pond := Vector2(corner).distance_to(pond_centre)
		var dip := 1.0 - smoothstep(pond_radius * 0.4, pond_radius, to_pond)
		return lerpf(height, -1.4, dip))


## Scatters trees and bushes outside the land, and a few around the prison.
static func plant(foliage: FoliageLayer, terrain: Terrain, map: BuildingMap,
		layout_origin: Vector2i, seed := 7) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var oak := PrisonCatalogue.PLANTS[0]
	var blossom := PrisonCatalogue.PLANTS[1]
	var bush := PrisonCatalogue.PLANTS[2]
	var wild := func(position: Vector2) -> bool:
		return not map.owns(Vector2i(position.floor())) and not terrain.is_underwater(position) \
				and terrain.height_at(position) > terrain.water_level + 0.3
	var size := Vector2(terrain.size)
	for i in 700:
		var position := Vector2(rng.randf() * size.x, rng.randf() * size.y)
		if not wild.call(position):
			continue
		var roll := rng.randf()
		var def: FoliageDef = oak if roll < 0.6 else (bush if roll < 0.85 else blossom)
		foliage.add(def, position, rng.randf_range(def.scale_range.x, def.scale_range.y),
				rng.randf() * TAU)

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
