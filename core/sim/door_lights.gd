class_name DoorLights
extends Node3D
## A little lamp over each door the timetable controls, on both faces of
## the wall: red while it is locked, green while it is open.

@export var lamp_height := 1.3
@export var locked_colour := Color(0.95, 0.35, 0.3)
@export var open_colour := Color(0.45, 0.85, 0.5)
@export var cell_size := 1.0

var runner: ScheduleRunner:
	set(value):
		runner = value
		runner.doors_changed.connect(_redraw)
var building: Building:
	set(value):
		building = value
		building.changed.connect(_redraw)
		building.active_changed.connect(func(_level: int) -> void: _redraw())

var _mesh := ImmediateMesh.new()


func _ready() -> void:
	var instance := MeshInstance3D.new()
	instance.mesh = _mesh
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Unshaded, so they glow at night.
	var material := MeshShapes.vertex_colour_material()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	instance.material_override = material
	add_child(instance)
	_redraw()


func _redraw() -> void:
	if not is_inside_tree() or runner == null or building == null:
		return
	_mesh.clear_surfaces()
	var drawn := false
	for key: Vector4i in runner.doors:
		if key.x > building.active:
			continue
		var map := building.levels.get(key.x) as BuildingMap
		if map == null:
			continue
		var edge := Vector3i(key.y, key.z, key.w)
		if map.wall_at(edge) != BuildingMap.Wall.DOOR:
			continue
		if not drawn:
			_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
			drawn = true
		var ends := BuildingMap.edge_ends(edge)
		var middle := (ends[0] + ends[1]) * 0.5
		var cells := BuildingMap.edge_cells(edge)
		var base := maxf(map.floor_height(cells[0]) if map.has_floor(cells[0]) else -INF,
				map.floor_height(cells[1]) if map.has_floor(cells[1]) else -INF)
		var across := Vector3(0, 0, 1) if edge.z == BuildingMap.EDGE_X else Vector3(1, 0, 0)
		var colour := locked_colour if runner.doors[key] else open_colour
		for sign: float in [-1.0, 1.0]:
			var at := Vector3(middle.x * cell_size, base + lamp_height, middle.y * cell_size) + across * sign * 0.12
			MeshShapes.add_box_immediate(_mesh, at, Vector3(0.11, 0.07, 0.11) - across * 0.06, colour)
	if drawn:
		_mesh.surface_end()
