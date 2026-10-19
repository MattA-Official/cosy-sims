class_name BuildingView
extends Node3D
## Draws a BuildingMap with placeholder geometry: floors, walls, doors,
## objects, and a floating label over each room that has a type.
## Rebuilds everything whenever the map changes, which is plenty fast at
## prototype sizes.

@export var grid: BuildGrid
@export var room_types: Array[RoomTypeDef] = []

@export_group("Walls")
@export var wall_height := 2.5
@export var low_wall_height := 0.35 ## Height when walls are cut away.
@export var wall_thickness := 0.15
@export var door_height := 2.0
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
@export var problem_colour := Color(1.0, 0.55, 0.45)
@export var land_edge_colour := Color(0.36, 0.5, 0.3)

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
var _objects := Node3D.new()
var _labels := Node3D.new()
var _material := MeshShapes.vertex_colour_material()
var _object_materials := {} # Color -> StandardMaterial3D
var _rebuild_queued := false


func _ready() -> void:
	for child: Node in [_floor_mesh, _wall_mesh, _objects, _labels]:
		add_child(child)
	_floor_mesh.material_override = _material
	_wall_mesh.material_override = _material
	_floor_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


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
			var centre := Vector3(cell.x + 0.5, 0.0, cell.y + 0.5) * cs
			MeshShapes.add_box(st, centre + Vector3.UP * 0.015, Vector3(0.5 * cs, 0.015, 0.5 * cs),
					colour * shade)
	_add_land_edge(st)
	_floor_mesh.mesh = st.commit()


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
		MeshShapes.add_box(st, middle + Vector3.UP * 0.03,
				along * cs * 0.5 + across * 0.06 + Vector3.UP * 0.03, land_edge_colour)


func _build_walls() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
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
		# Stretch each piece by half a thickness so corners join up.
		var half_len := along * (cs + thickness) * 0.5
		var half_across := across * thickness * 0.5
		if map.wall_at(edge) == BuildingMap.Wall.DOOR:
			_add_door(st, middle, half_len, half_across, height, full_height, colour, top)
		elif def != null and def.see_through and not walls_low:
			_add_fence(st, middle, along, half_across, height, cs, colour, top)
		else:
			_add_slab(st, middle, half_len + half_across, 0.0, height, colour, top)
	_wall_mesh.mesh = st.commit() if not map.walls.is_empty() else null


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


## Posts at each end and two rails between them.
func _add_fence(st: SurfaceTool, middle: Vector3, along: Vector3, half_across: Vector3,
		height: float, cs: float, colour: Color, top: Color) -> void:
	var post := along * 0.06 + half_across.normalized() * 0.06
	for end in [-0.5, 0.5]:
		_add_slab(st, middle + along * cs * end, post, 0.0, height, colour, top)
	for rail_y in [height * 0.45, height * 0.85]:
		_add_slab(st, middle, along * cs * 0.5 + half_across * 0.6, rail_y - 0.05, rail_y + 0.05,
				colour, top)


func _build_objects() -> void:
	for child in _objects.get_children():
		child.queue_free()
	var cs := grid.cell_size
	for placed: BuildingMap.PlacedObject in map.objects.values():
		# Shrink a touch so neighbours and walls do not look fused together.
		var margin := minf(0.1, minf(placed.rect.size.x, placed.rect.size.y) * 0.1)
		var box := BoxMesh.new()
		box.size = Vector3((placed.rect.size.x - margin * 2.0) * cs, placed.def.height,
				(placed.rect.size.y - margin * 2.0) * cs)
		var instance := MeshInstance3D.new()
		instance.mesh = box
		instance.material_override = _object_material(placed.def.colour)
		var centre := placed.rect.get_center() * cs
		instance.position = Vector3(centre.x, placed.def.height * 0.5, centre.y)
		_objects.add_child(instance)


func _build_labels() -> void:
	for child in _labels.get_children():
		child.queue_free()
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
		label.position = Vector3(centre.x, lift, centre.y)
		_labels.add_child(label)


func _object_material(colour: Color) -> StandardMaterial3D:
	if not _object_materials.has(colour):
		var material := StandardMaterial3D.new()
		material.albedo_color = colour
		material.roughness = 0.8
		_object_materials[colour] = material
	return _object_materials[colour]
