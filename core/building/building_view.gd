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
@export var floor_colour := Color(0.74, 0.72, 0.68)
@export var wall_colour := Color(0.93, 0.88, 0.8)
@export var wall_top_colour := Color(0.36, 0.32, 0.3)
@export var door_colour := Color(0.45, 0.65, 0.88)
@export var problem_colour := Color(1.0, 0.55, 0.45)

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
		var colour := floor_colour
		var def := room_type(room.type)
		if def != null:
			colour = floor_colour.lerp(def.colour, 0.6)
		for cell in room.cells:
			# A faint checkerboard makes floors read as tiles.
			var shade := 1.0 if (cell.x + cell.y) % 2 == 0 else 0.95
			var centre := Vector3(cell.x + 0.5, 0.0, cell.y + 0.5) * cs
			MeshShapes.add_box(st, centre + Vector3.UP * 0.015, Vector3(0.5 * cs, 0.015, 0.5 * cs),
					colour * shade)
	_floor_mesh.mesh = st.commit() if not map.floors.is_empty() else null


func _build_walls() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var cs := grid.cell_size
	var height := low_wall_height if walls_low else wall_height
	var half_t := wall_thickness * 0.5
	for edge: Vector3i in map.walls:
		var start := Vector3(edge.x, 0.0, edge.y) * cs
		var along := Vector3.RIGHT if edge.z == BuildingMap.EDGE_X else Vector3.BACK
		var across := Vector3.BACK if edge.z == BuildingMap.EDGE_X else Vector3.RIGHT
		var middle := start + along * cs * 0.5
		# Stretch each piece by half a thickness so corners join up.
		var half_len := along * (cs * 0.5 + half_t)
		var half_across := across * half_t
		if map.wall_at(edge) == BuildingMap.Wall.DOOR:
			_add_door(st, middle, along, across, height, cs)
		else:
			MeshShapes.add_box(st, middle + Vector3.UP * height * 0.5,
					half_len + half_across + Vector3.UP * height * 0.5, wall_colour, wall_top_colour)
	_wall_mesh.mesh = st.commit() if not map.walls.is_empty() else null


func _add_door(st: SurfaceTool, middle: Vector3, along: Vector3, across: Vector3,
		height: float, cs: float) -> void:
	var half_t := wall_thickness * 0.5
	var half_len := along * (cs * 0.5 + half_t)
	if walls_low:
		MeshShapes.add_box(st, middle + Vector3.UP * height * 0.25,
				half_len + across * half_t + Vector3.UP * height * 0.25, door_colour)
		return
	var lintel := wall_height - door_height
	MeshShapes.add_box(st, middle + Vector3.UP * (door_height + lintel * 0.5),
			half_len + across * half_t + Vector3.UP * lintel * 0.5, wall_colour, wall_top_colour)
	MeshShapes.add_box(st, middle + Vector3.UP * door_height * 0.5,
			along * cs * 0.4 + across * half_t * 0.4 + Vector3.UP * door_height * 0.5, door_colour)


func _build_objects() -> void:
	for child in _objects.get_children():
		child.queue_free()
	var cs := grid.cell_size
	for placed: BuildingMap.PlacedObject in map.objects.values():
		var lo := Vector2(placed.cells[0])
		var hi := Vector2(placed.cells[-1]) + Vector2.ONE
		var box := BoxMesh.new()
		box.size = Vector3((hi.x - lo.x) * cs - 0.2, placed.def.height, (hi.y - lo.y) * cs - 0.2)
		var instance := MeshInstance3D.new()
		instance.mesh = box
		instance.material_override = _object_material(placed.def.colour)
		instance.position = Vector3((lo.x + hi.x) * 0.5 * cs, placed.def.height * 0.5,
				(lo.y + hi.y) * 0.5 * cs)
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
