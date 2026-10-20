class_name ZoneTints
extends Node3D
## While the zones tool is open, tints every room on the level in view by
## its zone's colour and names the zone, so the whole plan of who may go
## where shows at a glance. With a perimeter, open ground on the ground
## floor is tinted too: green inside it, orange outside.

@export var cell_size := 1.0
## How far above the floor the tint sits.
@export var lift := 0.05
@export var alpha := 0.45

var access: Access
## Optional: secure ground inside a perimeter.
var secure_area: SecureArea
var secure_colour := Color(0.55, 0.85, 0.5, 0.4)
var outside_colour := Color(0.95, 0.6, 0.3, 0.45)
## (cell: Vector2i) -> float: the ground's height, for the open ground tint.
var ground_height: Callable
var controller: BuildController:
	set(value):
		controller = value
		controller.tool_changed.connect(func(_tool: BuildController.Tool) -> void: _redraw())
var building: Building:
	set(value):
		building = value
		building.changed.connect(_redraw)
		building.active_changed.connect(func(_level: int) -> void: _redraw())

var _mesh := ImmediateMesh.new()
var _labels := Node3D.new()
var _label_font := CosyTheme.bold_font()


func _ready() -> void:
	var instance := MeshInstance3D.new()
	instance.mesh = _mesh
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.material_override = MeshShapes.vertex_colour_material(true)
	add_child(instance)
	add_child(_labels)
	_redraw()


func _redraw() -> void:
	if not is_inside_tree() or building == null or controller == null or access == null:
		return
	_mesh.clear_surfaces()
	for child in _labels.get_children():
		child.queue_free()
	if controller.tool != BuildController.Tool.ZONE:
		return
	var map := building.levels.get(building.active) as BuildingMap
	if map == null:
		return
	var ground := building.active == 0 and secure_area != null and secure_area.has_perimeter
	if map.rooms().is_empty() and not ground:
		return
	_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	if ground:
		_tint_ground(map)
	for room in map.rooms():
		var zone := access.zone_of(room)
		if zone == null:
			continue
		var colour := zone.colour
		colour.a = alpha
		var top := -INF
		for cell in room.cells:
			var height := map.floor_height(cell) + lift
			top = maxf(top, height)
			MeshShapes.add_box_immediate(_mesh, Vector3((cell.x + 0.5) * cell_size, height,
					(cell.y + 0.5) * cell_size), Vector3(0.48, 0.01, 0.48) * cell_size, colour)
		var label := Label3D.new()
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.no_depth_test = true
		label.font_size = 44
		label.pixel_size = 0.008
		label.outline_size = 8
		label.font = _label_font
		label.modulate = Color.WHITE
		label.outline_modulate = zone.colour.darkened(0.45)
		label.text = zone.display_name + ("" if room.zone.is_empty() else " (painted)")
		var centre := room.centre()
		label.position = Vector3(centre.x * cell_size, top + 0.1, centre.y * cell_size)
		_labels.add_child(label)
	_mesh.surface_end()


## Open ground, inside the perimeter or not.
func _tint_ground(map: BuildingMap) -> void:
	for cell in BuildingMap.cells_in(map.land_bounds()):
		if not map.owns(cell) or map.room_at(cell) != null:
			continue
		var colour := secure_colour if secure_area.is_secure(cell) else outside_colour
		var height: float = ground_height.call(cell) if ground_height.is_valid() else 0.0
		MeshShapes.add_box_immediate(_mesh, Vector3((cell.x + 0.5) * cell_size, height + lift,
				(cell.y + 0.5) * cell_size), Vector3(0.48, 0.01, 0.48) * cell_size, colour)
