class_name Backdrop
extends Node3D
## Past the edge of the map the world carries on: rolling ground, woods, a
## farm with its fields and the town the road leads to, fading into soft fog
## over distant hills, with no hard wall. Scenery only: nothing walks or
## drives out here. It is rebuilt from a seed rather than saved, and on a
## coast the ground runs down into the sea.

enum Detail { LOW, HIGH }

## Width of the ring past the map edge, in tiles.
const RING_TILES := 64
## Vertex spacing across the ring, in tiles. Along the map edge it matches
## the terrain's own tiles, so the two meet without a seam.
const RING_STEP := 4
## Fog from the land for sale, in metres: clear up to FOG_START, then
## thickening over FOG_WIDTH. Low detail keeps the old close fog.
const FOG_START := 20.0
const FOG_WIDTH := 64.0
const LOW_FOG_WIDTH := 18.0
## The tallest the far hills get.
const MAX_HILL := 12.0
## Tiles over which the ground leaves the map's own heights for its own.
const SETTLE := 10.0
## How far below the lowest tide the sea floor falls off a coast.
const SEA_DROP := 2.5
## How far past the edge the town and the farm sit, in tiles.
const TOWN_OUT := 34.0
const FARM_OUT := 24.0
## About one tree per this many tiles of ring, gathered into woods.
const TILES_PER_TREE := 18.0
## Prisoners out on community service shown working in the town, at most.
const MOST_OUT := 6
const SETTINGS := "user://graphics.cfg"

const OBJECT_SHADER := preload("res://core/world/backdrop_object.gdshader")
## The ground parameters the ring and the scenery copy from the map's ground.
const SHARED := [&"base_colour", &"snow", &"fog_colour", &"fog_rect", &"fog_start", &"fog_width"]

const WALLS: Array[Color] = [Color(0.88, 0.84, 0.74), Color(0.72, 0.42, 0.34), Color(0.78, 0.76, 0.72),
		Color(0.9, 0.88, 0.82), Color(0.66, 0.5, 0.4)]
const ROOFS: Array[Color] = [Color(0.36, 0.38, 0.44), Color(0.55, 0.3, 0.24), Color(0.42, 0.34, 0.3)]
const FIELDS: Array[Color] = [Color(0.52, 0.4, 0.28), Color(0.84, 0.75, 0.44), Color(0.47, 0.62, 0.32),
		Color(0.58, 0.68, 0.36)]

var terrain: Terrain:
	set(value):
		terrain = value
		terrain.changed.connect(_on_ground_changed)
var water: WaterLayer
var roads: Roads:
	set(value):
		roads = value
		roads.paths.changed.connect(func() -> void:
			if _exit() != _built_exit:
				queue_rebuild())
var cell_size := 1.0
## The map's ground: the ring follows its grass colour, snow and fog.
var ground: ShaderMaterial
## () -> float: daylight from 0 at night to 1 by day, for lit windows.
var daylight: Callable
## () -> int: prisoners out on community service.
var outings: Callable
var noise_seed := 0:
	set(value):
		noise_seed = value
		hill_noise.seed = value
		queue_rebuild()
## The edge the town sits on when no road leaves the land (a Coast bit).
var town_side: int = WaterLayer.Coast.SOUTH
var detail := Detail.HIGH:
	set(value):
		detail = value
		visible = detail == Detail.HIGH
		_apply_fog()
var hill_noise := FastNoiseLite.new()

var _ground_material: ShaderMaterial
var _materials := {}
var _sea: Array[MeshInstance3D] = []
var _workers: Array[MeshInstance3D] = []
var _base := 0.0
var _built_exit := []
var _built_coast := -1
var _town := Vector2.ZERO
var _farm := Vector2.ZERO
var _road: Array[Vector2] = []
var _fields: Array[Rect2] = []
var _queued := false


func _init() -> void:
	hill_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	hill_noise.frequency = 0.02


## The detail last picked on this computer.
static func saved_detail() -> Detail:
	var file := ConfigFile.new()
	if file.load(SETTINGS) != OK:
		return Detail.HIGH
	return file.get_value("graphics", "backdrop", Detail.HIGH) as Detail


static func remember_detail(value: Detail) -> void:
	var file := ConfigFile.new()
	file.load(SETTINGS)
	file.set_value("graphics", "backdrop", int(value))
	file.save(SETTINGS)


func queue_rebuild() -> void:
	if _queued:
		return
	_queued = true
	rebuild.call_deferred()


func rebuild() -> void:
	_queued = false
	for child in get_children():
		child.queue_free()
	_sea.clear()
	_workers.clear()
	if terrain == null:
		return
	_built_coast = water.coast if water != null else 0
	_built_exit = _exit()
	_lay_out()
	_ground_material = (ground.duplicate() if ground != null else ShaderMaterial.new()) as ShaderMaterial
	_ground_material.set_shader_parameter(&"grid_lines", false)
	_add(_ring_mesh(), _ground_material)
	_add(_fields_mesh(), _material(&"fields", Color.WHITE))
	_add(_road_mesh(), _material(&"road", Color(0.42, 0.42, 0.44), 0.6))
	var roofs := SurfaceTool.new()
	var windows := SurfaceTool.new()
	for st in [roofs, windows]:
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_build_town(roofs, windows)
	_build_farm(roofs, windows)
	_add(roofs.commit(), _material(&"buildings", Color.WHITE))
	_add(windows.commit(), _material(&"windows", Color.WHITE, 0.0))
	_plant_trees()
	_build_sea()
	_build_workers()
	_apply_fog()
	_sync()


## Height of the ground at a point past the map, in tiles. On the map's
## edge it is the terrain's own height; further out it settles to a gentle
## roll and climbs into hills, flattened round the town, the farm and the
## road, and falls away into the sea off a coast.
func height_at(point: Vector2) -> float:
	var size := Vector2(terrain.size)
	var inside := point.clamp(Vector2.ZERO, size)
	var past := point.distance_to(inside)
	var edge := terrain.height_at(inside)
	var settle := smoothstep(0.0, SETTLE, past)
	var flat := _flatness(point)
	var roll := hill_noise.get_noise_2d(point.x * 2.5, point.y * 2.5) * 0.6 * (1.0 - flat)
	var hills := (hill_noise.get_noise_2d(point.x, point.y) * 0.5 + 0.5) * minf(past / RING_TILES, 1.0) \
			* MAX_HILL * (1.0 - flat * 0.85)
	var land := lerpf(edge, _base + roll, settle) + hills
	var sea := sea_amount(point)
	return lerpf(land, lerpf(edge, _sea_floor(), settle), sea) if sea > 0.0 else land


## How far a point lies out to sea, from 0 on land to 1 well past a coast.
func sea_amount(point: Vector2) -> float:
	if water == null or water.coast == 0:
		return 0.0
	var size := Vector2(terrain.size)
	var most := 0.0
	for side: int in [WaterLayer.Coast.NORTH, WaterLayer.Coast.EAST, WaterLayer.Coast.SOUTH, WaterLayer.Coast.WEST]:
		if water.coast & side:
			var past: float = [-point.y, point.x - size.x, point.y - size.y, -point.x][_side_index(side)]
			most = maxf(most, smoothstep(0.0, SETTLE, past))
	return most


## Where the town sits, in tiles.
func town() -> Vector2:
	return _town


## Where the farm sits, in tiles.
func farm() -> Vector2:
	return _farm


## The road from the map's edge to the town, in tiles.
func road() -> Array[Vector2]:
	return _road


## The fields round the farm, in tiles.
func fields() -> Array[Rect2]:
	return _fields


## The trees as tile positions, for checking where they stand.
func trees() -> Array[Vector2]:
	var out: Array[Vector2] = []
	for child in get_children():
		if child is MultiMeshInstance3D and child.name == &"Trunks":
			var mm := (child as MultiMeshInstance3D).multimesh
			for i in mm.instance_count:
				var at := mm.get_instance_transform(i).origin / cell_size
				out.append(Vector2(at.x, at.z))
	return out


func capture() -> Dictionary:
	return {"seed": noise_seed, "town_side": town_side}


func restore(data: Dictionary) -> void:
	town_side = int(data.get("town_side", town_side))
	noise_seed = int(data.get("seed", noise_seed))


func _process(_delta: float) -> void:
	if visible:
		_sync()


## Follows the map's ground (season, snow, fog), the tide and the time of day.
func _sync() -> void:
	if ground == null or _ground_material == null:
		return
	if water != null and water.coast != _built_coast:
		queue_rebuild()
	for name: StringName in SHARED:
		var value: Variant = ground.get_shader_parameter(name)
		if value == null:
			continue
		_ground_material.set_shader_parameter(name, value)
		if name != &"base_colour":
			for material: ShaderMaterial in _materials.values():
				material.set_shader_parameter(name, value)
	var grass: Variant = ground.get_shader_parameter(&"base_colour")
	if grass is Color:
		(_materials[&"leaves"] as ShaderMaterial).set_shader_parameter(&"colour", (grass as Color).darkened(0.3))
	if water != null:
		_ground_material.set_shader_parameter(&"water_level", water.sea_level() if water.coast != 0
				else ground.get_shader_parameter(&"water_level"))
		for sea in _sea:
			sea.position.y = water.sea_level()
	var night := 1.0 - (daylight.call() as float if daylight.is_valid() else 1.0)
	var windows := _materials[&"windows"] as ShaderMaterial
	windows.set_shader_parameter(&"colour", Color(0.36, 0.42, 0.5).lerp(Color(1.0, 0.82, 0.5), night))
	windows.set_shader_parameter(&"glow", night * 0.9)
	var out := mini(outings.call() as int if outings.is_valid() else 0, MOST_OUT)
	for i in _workers.size():
		_workers[i].visible = i < out


func _apply_fog() -> void:
	if ground == null:
		return
	var high := detail == Detail.HIGH
	ground.set_shader_parameter(&"fog_start", FOG_START if high else 0.0)
	ground.set_shader_parameter(&"fog_width", FOG_WIDTH if high else LOW_FOG_WIDTH)


func _on_ground_changed() -> void:
	var area := terrain.last_changed
	if not area.has_area() or area.position.x <= 0 or area.position.y <= 0 \
			or area.end.x >= terrain.size.x or area.end.y >= terrain.size.y:
		queue_rebuild()


## The edge the road leaves the land by, and where along it: [side, along],
## or the town side and the middle of the edge when no road leaves.
func _exit() -> Array:
	if roads != null and terrain != null:
		for node in roads.edge_nodes():
			var side := _side_of(roads.outward(node))
			if water == null or not (water.coast & side):
				var at: Vector2 = roads.paths.nodes[node]
				return [side, at.x if side in [WaterLayer.Coast.NORTH, WaterLayer.Coast.SOUTH] else at.y]
	var side := town_side
	if water != null and water.coast & side:
		for other: int in [WaterLayer.Coast.SOUTH, WaterLayer.Coast.EAST, WaterLayer.Coast.WEST, WaterLayer.Coast.NORTH]:
			if not (water.coast & other):
				side = other
				break
	var size := Vector2(terrain.size) if terrain != null else Vector2.ZERO
	return [side, (size.x if side in [WaterLayer.Coast.NORTH, WaterLayer.Coast.SOUTH] else size.y) * 0.5]


static func _side_of(direction: Vector2) -> int:
	if absf(direction.x) >= absf(direction.y):
		return WaterLayer.Coast.EAST if direction.x > 0.0 else WaterLayer.Coast.WEST
	return WaterLayer.Coast.SOUTH if direction.y > 0.0 else WaterLayer.Coast.NORTH


static func _side_index(side: int) -> int:
	return [WaterLayer.Coast.NORTH, WaterLayer.Coast.EAST, WaterLayer.Coast.SOUTH, WaterLayer.Coast.WEST].find(side)


## Out from the map on a side, as a direction.
static func _outward(side: int) -> Vector2:
	return [Vector2.UP, Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT][_side_index(side)]


## The point on a side's edge at `along`.
func _edge_point(side: int, along: float) -> Vector2:
	var size := Vector2(terrain.size)
	return [Vector2(along, 0.0), Vector2(size.x, along), Vector2(along, size.y), Vector2(0.0, along)][_side_index(side)]


func _sea_floor() -> float:
	return water.sea_base - water.tide_range - SEA_DROP if water != null else -SEA_DROP


## Places the town at the end of the road and the farm on another side.
func _lay_out() -> void:
	var size := Vector2(terrain.size)
	var border := 0.0
	var count := 0
	for x in terrain.size.x + 1:
		border += terrain.corner_height(Vector2i(x, 0)) + terrain.corner_height(Vector2i(x, terrain.size.y))
		count += 2
	for z in terrain.size.y + 1:
		border += terrain.corner_height(Vector2i(0, z)) + terrain.corner_height(Vector2i(terrain.size.x, z))
		count += 2
	_base = border / count
	var side: int = _built_exit[0]
	var along: float = _built_exit[1]
	var start := _edge_point(side, along)
	_town = start + _outward(side) * TOWN_OUT
	_road = [start, _town + _outward(side) * 10.0]
	# The farm goes on the next side round that isn't the town's or the sea.
	var order := [WaterLayer.Coast.NORTH, WaterLayer.Coast.EAST, WaterLayer.Coast.SOUTH, WaterLayer.Coast.WEST]
	var farm_side := -1
	for step in range(1, 4):
		var other: int = order[(_side_index(side) + step) % 4]
		if water == null or not (water.coast & other):
			farm_side = other
			break
	_fields.clear()
	if farm_side < 0:
		_farm = Vector2(INF, INF)
		return
	var across := size.x if farm_side in [WaterLayer.Coast.NORTH, WaterLayer.Coast.SOUTH] else size.y
	var rng := RandomNumberGenerator.new()
	rng.seed = noise_seed
	_farm = _edge_point(farm_side, across * rng.randf_range(0.3, 0.7)) + _outward(farm_side) * FARM_OUT
	# A patchwork of fields either side of the farmyard.
	var out := _outward(farm_side)
	var along_axis := Vector2(absf(out.y), absf(out.x))
	for i: int in [-2, -1, 1, 2]:
		for j: int in [-1, 1]:
			var centre := _farm + along_axis * (i * 13.0) + out * (j * 8.0)
			var half := along_axis * rng.randf_range(4.5, 6.0) + Vector2(absf(out.x), absf(out.y)) * rng.randf_range(2.5, 3.5)
			_fields.append(Rect2(centre - half, half * 2.0))


## 1 on the flat ground of the town, farm and road, 0 elsewhere.
func _flatness(point: Vector2) -> float:
	var flat := 0.0
	if not _road.is_empty():
		var near := Geometry2D.get_closest_point_to_segment(point, _road[0], _road[1])
		flat = 1.0 - smoothstep(2.0, 7.0, point.distance_to(near))
	flat = maxf(flat, 1.0 - smoothstep(12.0, 20.0, point.distance_to(_town)))
	if _farm.is_finite():
		flat = maxf(flat, 1.0 - smoothstep(30.0, 40.0, point.distance_to(_farm)))
	return flat


## The coordinates along one axis: ring spacing outside, tile spacing
## along the map.
static func _axis(tiles: int) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for i in range(-RING_TILES, 0, RING_STEP):
		out.append(i)
	for i in tiles + 1:
		out.append(i)
	for i in range(tiles + RING_STEP, tiles + RING_TILES + 1, RING_STEP):
		out.append(i)
	return out


func _inside(x0: float, x1: float, z0: float, z1: float) -> bool:
	return x0 >= 0.0 and z0 >= 0.0 and x1 <= terrain.size.x and z1 <= terrain.size.y


func _ring_mesh() -> ArrayMesh:
	var xs := _axis(terrain.size.x)
	var zs := _axis(terrain.size.y)
	var index := {}
	var vertices := PackedVector3Array()
	var indices := PackedInt32Array()
	for j in zs.size() - 1:
		for i in xs.size() - 1:
			if _inside(xs[i], xs[i + 1], zs[j], zs[j + 1]):
				continue
			var corners: Array[int] = []
			for c: Vector2i in [Vector2i(i, j), Vector2i(i + 1, j), Vector2i(i, j + 1), Vector2i(i + 1, j + 1)]:
				var key := c.y * xs.size() + c.x
				if not index.has(key):
					index[key] = vertices.size()
					var at := Vector2(xs[c.x], zs[c.y])
					vertices.append(Vector3(at.x, height_at(at), at.y) * cell_size)
				corners.append(index[key])
			# Clockwise from above, like the terrain.
			indices.append_array([corners[0], corners[1], corners[2], corners[1], corners[3], corners[2]])
	return _with_normals(vertices, indices)


## Flat-coloured patches over the ring's own cells round the farm.
func _fields_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var xs := _axis(terrain.size.x)
	var zs := _axis(terrain.size.y)
	for j in zs.size() - 1:
		for i in xs.size() - 1:
			if _inside(xs[i], xs[i + 1], zs[j], zs[j + 1]):
				continue
			var centre := Vector2(xs[i] + xs[i + 1], zs[j] + zs[j + 1]) * 0.5
			for f in _fields.size():
				if _fields[f].has_point(centre) and sea_amount(centre) < 0.1:
					var points: Array[Vector3] = []
					for at: Vector2 in [Vector2(xs[i], zs[j]), Vector2(xs[i + 1], zs[j]),
							Vector2(xs[i + 1], zs[j + 1]), Vector2(xs[i], zs[j + 1])]:
						points.append(Vector3(at.x, height_at(at) + 0.06, at.y) * cell_size)
					MeshShapes.add_quad(st, points[0], points[1], points[2], points[3], Vector3.UP,
							FIELDS[(f + noise_seed) % FIELDS.size()])
					break
	return st.commit()


## A ribbon of road from the map's edge through the town.
func _road_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var along := (_road[1] - _road[0]).normalized()
	var side := Vector2(-along.y, along.x) * 1.2
	var length := _road[0].distance_to(_road[1])
	var t := 0.0
	while t < length:
		var a := _road[0] + along * t
		var b := _road[0] + along * minf(t + 2.0, length)
		var points: Array[Vector3] = []
		for at: Vector2 in [a - side, a + side, b + side, b - side]:
			points.append(Vector3(at.x, height_at(at) + 0.08, at.y) * cell_size)
		MeshShapes.add_quad(st, points[0], points[1], points[2], points[3], Vector3.UP, Color.WHITE)
		t += 2.0
	return st.commit()


## Two rows of houses along the road, with a church at the far end.
func _build_town(st: SurfaceTool, windows: SurfaceTool) -> void:
	var along := (_road[1] - _road[0]).normalized()
	var across := Vector2(-along.y, along.x)
	var rng := RandomNumberGenerator.new()
	rng.seed = noise_seed + 1
	for row: float in [-5.0, 5.0, -11.0, 11.0]:
		for step in range(-3, 3):
			if absf(row) > 6.0 and rng.randf() < 0.35:
				continue
			var at := _town + along * (step * 4.5 + rng.randf_range(-0.6, 0.6)) + across * row
			var size := Vector3(rng.randf_range(1.4, 1.9), rng.randf_range(1.6, 2.2), rng.randf_range(1.6, 2.2))
			_house(st, windows, at, across * signf(row), size, WALLS[rng.randi() % WALLS.size()],
					ROOFS[rng.randi() % ROOFS.size()])
	_church(st, windows, _town + along * 16.0 + across * 6.0, along)


## A barn, a silo and a farmhouse.
func _build_farm(st: SurfaceTool, windows: SurfaceTool) -> void:
	if not _farm.is_finite():
		return
	_house(st, windows, _farm, Vector2.DOWN, Vector3(1.6, 1.8, 2.0), WALLS[0], ROOFS[1])
	var barn := _farm + Vector2(6.0, 1.0)
	_house(st, null, barn, Vector2.LEFT, Vector3(2.6, 2.4, 4.0), Color(0.55, 0.27, 0.22), ROOFS[0])
	var silo := barn + Vector2(0.0, -6.0)
	var ring := PackedVector2Array()
	for i in 8:
		ring.append((silo + Vector2.from_angle(TAU * i / 8.0) * 1.1) * cell_size)
	var base := height_at(silo) * cell_size
	MeshShapes.add_prism(st, ring, base - 0.5, base + 5.5 * cell_size, Color(0.72, 0.72, 0.7))


## A house facing `front`, `size` its half width, wall height and half depth.
func _house(st: SurfaceTool, windows: SurfaceTool, at: Vector2, front: Vector2, size: Vector3,
		wall: Color, roof: Color) -> void:
	var xf := _frame(at, front)
	_box(st, xf, Vector3(0.0, size.y * 0.5 - 0.5, 0.0), Vector3(size.x, size.y * 0.5 + 0.5, size.z), wall)
	_gable(st, xf, size.y, Vector2(size.x + 0.2, size.z + 0.2), size.x * 0.8, roof, wall)
	if windows != null:
		for x: float in [-size.x * 0.5, size.x * 0.5]:
			_box(windows, xf, Vector3(x, size.y * 0.6, size.z + 0.02), Vector3(0.3, 0.3, 0.04), Color.WHITE)
		_box(windows, xf, Vector3(0.0, size.y * 0.6, -size.z - 0.02), Vector3(0.3, 0.3, 0.04), Color.WHITE)


func _church(st: SurfaceTool, windows: SurfaceTool, at: Vector2, along: Vector2) -> void:
	var stone := Color(0.7, 0.68, 0.62)
	var xf := _frame(at, along)
	_box(st, xf, Vector3(0.0, 1.25, 0.0), Vector3(2.2, 1.75, 4.0), stone)
	_gable(st, xf, 3.0, Vector2(2.4, 4.2), 2.2, ROOFS[0], stone)
	_box(st, xf, Vector3(0.0, 3.0, 4.6), Vector3(1.3, 3.5, 1.3), stone)
	var top := 6.5
	var peak := xf * (Vector3(0.0, top + 4.5, 4.6) * cell_size)
	var corners: Array[Vector3] = []
	for c: Vector2 in [Vector2(-1.4, -1.4), Vector2(1.4, -1.4), Vector2(1.4, 1.4), Vector2(-1.4, 1.4)]:
		corners.append(xf * (Vector3(c.x, top, 4.6 + c.y) * cell_size))
	for i in 4:
		var middle := (corners[i] + corners[(i + 1) % 4]) * 0.5
		MeshShapes.add_polygon(st, [corners[i], corners[(i + 1) % 4], peak], middle - xf.origin + Vector3.UP, ROOFS[0])
	for z: float in [-2.0, 0.0, 2.0]:
		for x: float in [-2.22, 2.22]:
			_box(windows, xf, Vector3(x, 1.6, z), Vector3(0.04, 0.6, 0.3), Color.WHITE)


## A frame standing on the ground at `at`, its +Z facing `front`.
func _frame(at: Vector2, front: Vector2) -> Transform3D:
	var origin := Vector3(at.x, height_at(at), at.y) * cell_size
	return Transform3D(Basis(Vector3.UP, atan2(front.x, front.y)), origin)


func _box(st: SurfaceTool, xf: Transform3D, centre: Vector3, half: Vector3, colour: Color) -> void:
	var c := cell_size
	MeshShapes.add_oriented_box(st, xf * (centre * c), xf.basis * Vector3(half.x * c, 0, 0),
			xf.basis * Vector3(0, 0, half.z * c), half.y * c, colour)


## A pitched roof from height `base`, `half` its overhang half size, its
## ridge running front to back.
func _gable(st: SurfaceTool, xf: Transform3D, base: float, half: Vector2, rise: float,
		roof: Color, wall: Color) -> void:
	var c := cell_size
	var p := func(x: float, y: float, z: float) -> Vector3: return xf * (Vector3(x, y, z) * c)
	var top := base + rise
	MeshShapes.add_quad(st, p.call(-half.x, base, -half.y), p.call(0.0, top, -half.y), p.call(0.0, top, half.y),
			p.call(-half.x, base, half.y), xf.basis * Vector3(-1, 1, 0), roof)
	MeshShapes.add_quad(st, p.call(half.x, base, -half.y), p.call(0.0, top, -half.y), p.call(0.0, top, half.y),
			p.call(half.x, base, half.y), xf.basis * Vector3(1, 1, 0), roof)
	var inset := half.y - 0.2
	for z: float in [-inset, inset]:
		MeshShapes.add_polygon(st, [p.call(-half.x + 0.2, base, z), p.call(half.x - 0.2, base, z),
				p.call(0.0, top - 0.15, z)], xf.basis * Vector3(0, 0, signf(z)), wall)


## Round trees gathered into woods, kept off the road, the town, the
## farm and the sea.
func _plant_trees() -> void:
	var size := Vector2(terrain.size)
	var outer := Rect2(-Vector2.ONE * RING_TILES, size + Vector2.ONE * RING_TILES * 2)
	var area := outer.get_area() - size.x * size.y
	var rng := RandomNumberGenerator.new()
	rng.seed = noise_seed + 2
	var transforms: Array[Transform3D] = []
	for i in int(area / TILES_PER_TREE * 2.0):
		var at := Vector2(rng.randf_range(outer.position.x, outer.end.x), rng.randf_range(outer.position.y, outer.end.y))
		var past := at.distance_to(at.clamp(Vector2.ZERO, size))
		if past < 2.0 or hill_noise.get_noise_2d(at.x * 0.8 + 500.0, at.y * 0.8) < 0.0:
			continue
		if _flatness(at) > 0.3 or sea_amount(at) > 0.05 or _fields.any(func(f: Rect2) -> bool: return f.grow(1.0).has_point(at)):
			continue
		var scale := rng.randf_range(0.8, 1.4)
		transforms.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * scale),
				Vector3(at.x, height_at(at), at.y) * cell_size))
	var trunk := SurfaceTool.new()
	trunk.begin(Mesh.PRIMITIVE_TRIANGLES)
	MeshShapes.add_box(trunk, Vector3(0, 0.5, 0) * cell_size, Vector3(0.15, 0.7, 0.15) * cell_size, Color(0.42, 0.3, 0.22))
	var crown := SphereMesh.new()
	crown.radius = 1.0 * cell_size
	crown.height = 2.2 * cell_size
	crown.radial_segments = 8
	crown.rings = 4
	for part: Array in [[&"Trunks", trunk.commit(), _material(&"trunks", Color.WHITE, 0.0)],
			[&"Crowns", crown, _material(&"leaves", Color(0.3, 0.45, 0.25))]]:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = part[1]
		mm.instance_count = transforms.size()
		for i in transforms.size():
			var xf := transforms[i]
			if part[0] == &"Crowns":
				xf.origin += xf.basis * (Vector3.UP * 1.9 * cell_size)
			mm.set_instance_transform(i, xf)
		var instance := MultiMeshInstance3D.new()
		instance.name = part[0]
		instance.multimesh = mm
		instance.material_override = part[2]
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(instance)


## A sheet of sea over each coast side of the ring, raised and lowered
## with the tide.
func _build_sea() -> void:
	if water == null:
		return
	var size := Vector2(terrain.size)
	var r := float(RING_TILES)
	for side: int in [WaterLayer.Coast.NORTH, WaterLayer.Coast.EAST, WaterLayer.Coast.SOUTH, WaterLayer.Coast.WEST]:
		if not (water.coast & side):
			continue
		var rect: Rect2 = [Rect2(-r, -r, size.x + r * 2.0, r), Rect2(size.x, -r, r, size.y + r * 2.0),
				Rect2(-r, size.y, size.x + r * 2.0, r), Rect2(-r, -r, r, size.y + r * 2.0)][_side_index(side)]
		var plane := PlaneMesh.new()
		plane.size = rect.size * cell_size
		var sea := MeshInstance3D.new()
		sea.mesh = plane
		sea.position = Vector3(rect.get_center().x, 0.0, rect.get_center().y) * cell_size
		sea.material_override = _material(&"sea", Color(0.32, 0.58, 0.78), 0.0)
		add_child(sea)
		_sea.append(sea)


## Little figures in high-visibility vests, out on community service.
func _build_workers() -> void:
	var along := (_road[1] - _road[0]).normalized()
	var across := Vector2(-along.y, along.x)
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.22 * cell_size
	capsule.height = 1.0 * cell_size
	capsule.radial_segments = 8
	capsule.rings = 2
	for i in MOST_OUT:
		var at := _town - along * 6.0 + across * (2.2 + (i % 3) * 0.8) + along * floorf(i / 3.0) * 0.9
		var worker := MeshInstance3D.new()
		worker.mesh = capsule
		worker.position = Vector3(at.x, height_at(at) + 0.5, at.y) * cell_size
		worker.material_override = _material(&"workers", Color(0.98, 0.55, 0.15), 0.0)
		worker.visible = false
		add_child(worker)
		_workers.append(worker)


func _material(key: StringName, colour: Color, takes_snow := 1.0) -> ShaderMaterial:
	if not _materials.has(key):
		var material := ShaderMaterial.new()
		material.shader = OBJECT_SHADER
		material.set_shader_parameter(&"colour", colour)
		material.set_shader_parameter(&"takes_snow", takes_snow)
		_materials[key] = material
	return _materials[key]


func _add(mesh: Mesh, material: Material) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(instance)
	return instance


static func _with_normals(vertices: PackedVector3Array, indices: PackedInt32Array) -> ArrayMesh:
	var normals := PackedVector3Array()
	normals.resize(vertices.size())
	for k in range(0, indices.size(), 3):
		var a := vertices[indices[k]]
		var face := (vertices[indices[k + 2]] - a).cross(vertices[indices[k + 1]] - a)
		for n in 3:
			normals[indices[k + n]] += face
	for i in normals.size():
		normals[i] = normals[i].normalized() if normals[i].length_squared() > 0.0 else Vector3.UP
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	if not vertices.is_empty():
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
