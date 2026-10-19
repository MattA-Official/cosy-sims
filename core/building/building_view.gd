class_name BuildingView
extends Node3D
## Draws a BuildingMap with placeholder geometry: floors, walls, doors,
## objects, and a floating label over each room that has a type.
## Rebuilds everything whenever the map changes, which is plenty fast at
## prototype sizes.

@export var grid: BuildGrid
## Optional: buildings sit on the terrain's height instead of y = 0.
@export var terrain: Terrain
@export var room_types: Array[RoomTypeDef] = []
## Which storey this view draws. Off the ground, floors are slabs of
## `slab_depth` rather than foundations reaching into the terrain.
@export var level := 0
@export var slab_depth := 0.28
## Room labels show only on the level being built on.
@export var show_labels := true:
	set(value):
		show_labels = value
		queue_rebuild()

@export_group("Walls")
@export var wall_height := 1.5
@export var low_wall_height := 0.25 ## Height when walls are cut away.
@export var wall_thickness := 0.15
@export var door_height := 1.15
@export var window_sill := 0.5
@export var window_head := 1.15
@export var walls_low := false:
	set(value):
		walls_low = value
		queue_rebuild()

@export_group("Colours")
## Used for floors and walls whose style the map does not know.
@export var floor_colour := Color(0.74, 0.72, 0.68)
@export var wall_colour := Color(0.93, 0.88, 0.8)
@export var wall_top_colour := Color(0.36, 0.32, 0.3)
@export var door_colour := Color(0.45, 0.65, 0.88)
@export var glass_colour := Color(0.7, 0.88, 1.0, 0.35)
@export var bars_colour := Color(0.3, 0.32, 0.36)
@export var problem_colour := Color(1.0, 0.55, 0.45)
@export var land_edge_colour := Color(0.36, 0.5, 0.3)
@export var foundation_colour := Color(0.62, 0.6, 0.57)

## How far floors and walls reach down into the ground, so they never
## float above a slope.
const FOUNDATION_DEPTH := 0.6

var map: BuildingMap:
	set(value):
		if map != null:
			map.changed.disconnect(queue_rebuild)
		map = value
		if map != null:
			map.changed.connect(queue_rebuild)
		queue_rebuild()

var _floor_mesh := MeshInstance3D.new()
var _wall_mesh := MeshInstance3D.new()
var _glass_mesh := MeshInstance3D.new()
var _objects := Node3D.new()
var _stairs_material := MeshShapes.vertex_colour_material()
var _labels := Node3D.new()
var _material := MeshShapes.vertex_colour_material()
var _glass_material := _make_glass_material()
var _object_materials := {} # Color -> StandardMaterial3D
var _rebuild_queued := false


func _ready() -> void:
	for child: Node in [_floor_mesh, _wall_mesh, _glass_mesh, _objects, _labels]:
		add_child(child)
	_floor_mesh.material_override = _material
	_wall_mesh.material_override = _material
	_glass_mesh.material_override = _glass_material
	_glass_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_floor_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if terrain != null:
		terrain.changed.connect(queue_rebuild)


func queue_rebuild() -> void:
	if _rebuild_queued:
		return
	_rebuild_queued = true
	rebuild.call_deferred()


func room_type(id: StringName) -> RoomTypeDef:
	for def in room_types:
		if def.id == id:
			return def
	return null


func rebuild() -> void:
	_rebuild_queued = false
	if map == null or not is_inside_tree():
		return
	_build_floors()
	_build_walls()
	_build_objects()
	_build_labels()


func _build_floors() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var cs := grid.cell_size
	for room in map.rooms():
		var type := room_type(room.type)
		for cell in room.cells:
			var def := map.floor_def(map.floors[cell])
			var colour := def.colour if def != null else floor_colour
			if type != null:
				colour = colour.lerp(type.colour, 0.35)
			# A faint checkerboard makes floors read as tiles.
			var shade := 1.0 if (cell.x + cell.y) % 2 == 0 else 0.95
			var top_y := map.floor_height(cell) + 0.03
			var bottom := _lowest_ground(cell) - FOUNDATION_DEPTH if level == 0 \
					else top_y - slab_depth
			var centre := Vector3(cell.x + 0.5, 0.0, cell.y + 0.5) * cs
			# The top face takes the floor colour; the sides show as foundations
			# reaching down into the ground.
			var ramp := map.ramp_at(cell)
			if ramp != null:
				_add_ramp_tile(st, cell, ramp, bottom, colour * shade)
				continue
			var depth := top_y - bottom
			MeshShapes.add_box(st, centre + Vector3.UP * (top_y - depth * 0.5),
					Vector3(0.5 * cs, depth * 0.5, 0.5 * cs), foundation_colour, colour * shade)
			_add_split_steps(st, cell, top_y, colour * shade)
	if level == 0:
		_add_land_edge(st)
	elif map.floors.is_empty():
		_floor_mesh.mesh = null
		return
	_floor_mesh.mesh = st.commit()


## Where a neighbouring floor is up to MAX_STEP higher, with nothing in
## between, a half-height step on this tile makes the climb read as two
## easy steps rather than one tall one.
func _add_split_steps(st: SurfaceTool, cell: Vector2i, top_y: float, colour: Color) -> void:
	var cs := grid.cell_size
	for step in BuildingMap.DIRECTIONS:
		var next := cell + step
		if not map.has_floor(next) or not map.can_walk_between(cell, next) \
				or map.ramp_at(next) != null:
			continue
		var rise := map.floor_height(next) - map.floor_height(cell)
		if rise <= BuildingMap.MAX_STEP * 0.5:
			continue
		var tread := 0.3 * cs
		var dir := Vector3(step.x, 0.0, step.y)
		var across := Vector3(absf(step.y), 0.0, absf(step.x))
		var centre := Vector3(cell.x + 0.5, 0.0, cell.y + 0.5) * cs + dir * (0.5 * cs - tread * 0.5)
		var half_rise := rise * 0.25
		MeshShapes.add_box(st, centre + Vector3.UP * (top_y + half_rise),
				across * 0.5 * cs + dir * tread * 0.5 + Vector3.UP * half_rise, colour.darkened(0.1),
				colour)


## One tile of a ramp: a sloped top over sides reaching down to `bottom`.
func _add_ramp_tile(st: SurfaceTool, cell: Vector2i, ramp: BuildingMap.Ramp, bottom: float,
		colour: Color) -> void:
	var cs := grid.cell_size
	var corners: Array[Vector3] = []
	for offset: Vector2 in [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]:
		var point := Vector2(cell) + offset
		corners.append(Vector3(point.x * cs, ramp.height_at(point) + 0.03, point.y * cs))
	var centre := (Vector3(cell.x + 0.5, 0.0, cell.y + 0.5) * cs)
	_add_quad(st, corners[0], corners[1], corners[2], corners[3], Vector3.UP, colour)
	for i in 4:
		var a := corners[i]
		var b := corners[(i + 1) % 4]
		var outward := ((a + b) * 0.5 - centre)
		outward.y = 0.0
		_add_quad(st, a, b, Vector3(b.x, bottom, b.z), Vector3(a.x, bottom, a.z), outward.normalized(),
				foundation_colour)


## A four-sided face, wound to face `outward`.
func _add_quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, outward: Vector3,
		colour: Color) -> void:
	var normal := (b - a).cross(c - a).normalized()
	if normal.dot(outward) < 0.0:
		normal = -normal
	st.set_normal(normal)
	st.set_color(colour)
	var order: Array[Vector3] = [a, b, c, a, c, d]
	if (b - a).cross(c - a).dot(outward) >= 0.0:
		order = [a, c, b, a, d, c]
	for vertex in order:
		st.add_vertex(vertex)


## A low kerb around the land you own, so you can see where you may build.
func _add_land_edge(st: SurfaceTool) -> void:
	var cs := grid.cell_size
	var bounds := map.land_bounds().grow(1)
	for edge in BuildingMap.rect_edges(bounds):
		var sides := BuildingMap.edge_cells(edge)
		if map.owns(sides[0]) == map.owns(sides[1]):
			continue
		var along := Vector3.RIGHT if edge.z == BuildingMap.EDGE_X else Vector3.BACK
		var across := Vector3.BACK if edge.z == BuildingMap.EDGE_X else Vector3.RIGHT
		var middle := Vector3(edge.x, 0.0, edge.y) * cs + along * cs * 0.5
		middle.y = _height_at(Vector2(middle.x, middle.z) / cs)
		MeshShapes.add_box(st, middle + Vector3.UP * 0.03,
				along * cs * 0.5 + across * 0.06 + Vector3.UP * 0.03, land_edge_colour)


func _build_walls() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var glass := SurfaceTool.new()
	glass.begin(Mesh.PRIMITIVE_TRIANGLES)
	var has_glass := false
	var cs := grid.cell_size
	for edge: Vector3i in map.walls:
		var def := map.wall_def(map.wall_style(edge))
		var full_height := def.height if def != null else wall_height
		var height := minf(low_wall_height, full_height) if walls_low else full_height
		var thickness := def.thickness if def != null else wall_thickness
		var colour := def.colour if def != null else wall_colour
		var top := def.top_colour if def != null else wall_top_colour
		var along := Vector3.RIGHT if edge.z == BuildingMap.EDGE_X else Vector3.BACK
		var across := Vector3.BACK if edge.z == BuildingMap.EDGE_X else Vector3.RIGHT
		var middle := Vector3(edge.x, 0.0, edge.y) * cs + along * cs * 0.5
		middle.y = _wall_base(edge)
		# Foundations reach below the lowest ground at either end.
		var start := Vector2(edge.x, edge.y)
		var end := start + Vector2(along.x, along.z)
		var drop := middle.y - minf(_height_at(start), _height_at(end)) + FOUNDATION_DEPTH \
				if level == 0 else middle.y - _lowest_floor_beside(edge) + 0.05
		# Stretch each piece by half a thickness so corners join up.
		var half_len := along * (cs + thickness) * 0.5
		var half_across := across * thickness * 0.5
		if map.wall_at(edge) == BuildingMap.Wall.DOOR:
			_add_door(st, middle, half_len, half_across, height, full_height, colour, top)
		elif map.wall_at(edge) == BuildingMap.Wall.WINDOW:
			var kind := map.window_kind(edge)
			_add_window(st, middle, along, half_len, half_across, height, full_height, cs, kind,
					drop, colour, top)
			if kind == BuildingMap.WINDOW_GLASS and not walls_low:
				_add_slab(glass, middle, along * cs * 0.5 + half_across * 0.25, window_sill,
						window_head, glass_colour, glass_colour)
				has_glass = true
		elif def != null and def.see_through and not walls_low:
			_add_fence(st, middle, along, half_across, height, cs, drop, colour, top)
		else:
			_add_slab(st, middle, half_len + half_across, -drop, height, colour, top)
	_wall_mesh.mesh = st.commit() if not map.walls.is_empty() else null
	_glass_mesh.mesh = glass.commit() if has_glass else null


## A box standing on the ground (or starting at bottom) up to top_y.
func _add_slab(st: SurfaceTool, middle: Vector3, half_flat: Vector3, bottom: float,
		top_y: float, colour: Color, top_colour: Color) -> void:
	var half_height := (top_y - bottom) * 0.5
	MeshShapes.add_box(st, middle + Vector3.UP * (bottom + half_height),
			half_flat + Vector3.UP * half_height, colour, top_colour)


func _add_door(st: SurfaceTool, middle: Vector3, half_len: Vector3, half_across: Vector3,
		height: float, full_height: float, colour: Color, top: Color) -> void:
	if walls_low or full_height <= door_height:
		_add_slab(st, middle, half_len + half_across, 0.0, minf(height, low_wall_height) * 0.5,
				door_colour, door_colour)
		return
	_add_slab(st, middle, half_len + half_across, door_height, full_height, colour, top)
	_add_slab(st, middle, half_len * 0.8 + half_across * 0.4, 0.0, door_height, door_colour,
			door_colour)


## Wall below the sill and above the head, with glass or bars between.
## Cut-away walls show the window as a coloured top so it is still easy
## to spot.
func _add_window(st: SurfaceTool, middle: Vector3, along: Vector3, half_len: Vector3,
		half_across: Vector3, height: float, full_height: float, cs: float, kind: StringName,
		drop: float, colour: Color, top: Color) -> void:
	var accent := bars_colour if kind == BuildingMap.WINDOW_BARS else glass_colour
	accent.a = 1.0
	if walls_low or full_height <= window_head:
		_add_slab(st, middle, half_len + half_across, -drop, height, colour, accent)
		return
	_add_slab(st, middle, half_len + half_across, -drop, window_sill, colour, top)
	_add_slab(st, middle, half_len + half_across, window_head, full_height, colour, top)
	# Narrow pillars at each end make a frame and keep corners solid.
	var pillar := along * 0.1 + half_across
	for end in [-0.5, 0.5]:
		_add_slab(st, middle + along * (cs * end + (0.05 if end < 0 else -0.05)), pillar,
				window_sill, window_head, colour, top)
	if kind == BuildingMap.WINDOW_BARS:
		var bar := along * 0.025 + half_across.normalized() * 0.025
		var count := 6
		for i in count:
			var offset := (float(i) + 0.5) / count - 0.5
			_add_slab(st, middle + along * cs * offset * 0.8, bar, window_sill, window_head,
					bars_colour, bars_colour)


static func _make_glass_material() -> StandardMaterial3D:
	var material := MeshShapes.vertex_colour_material()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material


## Posts at each end and two rails between them.
func _add_fence(st: SurfaceTool, middle: Vector3, along: Vector3, half_across: Vector3,
		height: float, cs: float, drop: float, colour: Color, top: Color) -> void:
	var post := along * 0.06 + half_across.normalized() * 0.06
	for end in [-0.5, 0.5]:
		_add_slab(st, middle + along * cs * end, post, -drop, height, colour, top)
	for rail_y in [height * 0.45, height * 0.85]:
		_add_slab(st, middle, along * cs * 0.5 + half_across * 0.6, rail_y - 0.05, rail_y + 0.05,
				colour, top)


func _build_objects() -> void:
	for child in _objects.get_children():
		child.queue_free()
	var cs := grid.cell_size
	for placed: BuildingMap.PlacedObject in map.objects.values():
		if placed.def.connects == ObjectDef.Connects.STAIRS:
			_add_stairs(placed)
			continue
		# Shrink a touch so neighbours and walls do not look fused together.
		var margin := minf(0.1, minf(placed.rect.size.x, placed.rect.size.y) * 0.1)
		var box := BoxMesh.new()
		box.size = Vector3((placed.rect.size.x - margin * 2.0) * cs, placed.def.height,
				(placed.rect.size.y - margin * 2.0) * cs)
		var instance := MeshInstance3D.new()
		instance.mesh = box
		instance.material_override = _object_material(placed.def.colour)
		var centre := placed.rect.get_center() * cs
		var ground := map.floor_height(Vector2i(placed.rect.get_center().floor()))
		instance.position = Vector3(centre.x, ground + 0.03 + placed.def.height * 0.5, centre.y)
		_objects.add_child(instance)


## A flight of stairs climbing one storey along its length.
func _add_stairs(placed: BuildingMap.PlacedObject) -> void:
	var cs := grid.cell_size
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var ends := BuildingMap.stair_ends(placed)
	var dir := BuildingMap.rise_direction(placed.rotation)
	var along := Vector3(dir.x, 0.0, dir.y)
	var across := Vector3(absf(dir.y), 0.0, absf(dir.x))
	var base := map.floor_height(ends[0]) + 0.03
	var length := absf(placed.rect.size.dot(Vector2(dir)))
	var width := absf(placed.rect.size.dot(Vector2(absf(dir.y), absf(dir.x))))
	var steps := maxi(roundi(length * 2.5), 2)
	var tread := length / steps
	var rise := Building.STOREY / steps
	var start := Vector3(placed.rect.get_center().x, 0.0, placed.rect.get_center().y) * cs \
			- along * length * 0.5 * cs
	var colour := placed.def.colour
	for i in steps:
		var top := base + rise * (i + 1)
		var centre := start + along * (tread * (i + 0.5)) * cs
		MeshShapes.add_box(st, centre + Vector3.UP * (base + top) * 0.5,
				across * (width * 0.5 - 0.06) * cs + along * tread * 0.5 * cs
				+ Vector3.UP * (top - base) * 0.5,
				colour.darkened(0.2), colour.lightened(0.05 * (i % 2)))
	var instance := MeshInstance3D.new()
	instance.mesh = st.commit()
	instance.material_override = _stairs_material
	_objects.add_child(instance)


func _build_labels() -> void:
	for child in _labels.get_children():
		child.queue_free()
	if not show_labels:
		return
	var cs := grid.cell_size
	for room in map.rooms():
		var def := room_type(room.type)
		if def == null:
			continue
		var label := Label3D.new()
		var problems := def.problems(room, map)
		label.text = def.display_name
		if not problems.is_empty():
			label.text += "\n" + "\n".join(problems)
			label.modulate = problem_colour
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.no_depth_test = true
		label.fixed_size = true
		label.pixel_size = 0.0012
		label.font_size = 22
		label.outline_size = 10
		var centre := room.centre() * cs
		var lift := low_wall_height + 0.6 if walls_low else wall_height + 0.6
		lift += map.floor_height(room.cells[0])
		label.position = Vector3(centre.x, lift, centre.y)
		_labels.add_child(label)


## Ground height at a point in tile units.
func _height_at(point: Vector2) -> float:
	return terrain.height_at(point) if terrain != null else 0.0


func _lowest_floor_beside(edge: Vector3i) -> float:
	var lowest := INF
	for cell in BuildingMap.edge_cells(edge):
		if map.has_floor(cell):
			lowest = minf(lowest, map.floor_height(cell))
	return lowest if lowest < INF else _wall_base(edge)


func _lowest_ground(cell: Vector2i) -> float:
	var lowest := INF
	for offset: Vector2i in [Vector2i.ZERO, Vector2i(1, 0), Vector2i(0, 1), Vector2i.ONE]:
		lowest = minf(lowest, _height_at(Vector2(cell + offset)))
	return lowest


## Walls stand on the higher floor beside them, or on the lower end of the ground.
func _wall_base(edge: Vector3i) -> float:
	var best := -INF
	for cell in BuildingMap.edge_cells(edge):
		if map.has_floor(cell):
			best = maxf(best, map.floor_height(cell))
	if best > -INF:
		return best
	var start := Vector2(edge.x, edge.y)
	var end := start + (Vector2.RIGHT if edge.z == BuildingMap.EDGE_X else Vector2.DOWN)
	return minf(_height_at(start), _height_at(end))


func _object_material(colour: Color) -> StandardMaterial3D:
	if not _object_materials.has(colour):
		var material := StandardMaterial3D.new()
		material.albedo_color = colour
		material.roughness = 0.8
		_object_materials[colour] = material
	return _object_materials[colour]
