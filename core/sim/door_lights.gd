class_name DoorLights
extends Node3D
## Marks on doors, on both faces of the wall: a little lamp over each door
## the timetable controls (red while locked, green while open), a padlock
## over any locked or unlocked by hand (with a red pin if it stays that way
## past the block), and a coloured plate on doors of a kind, such as a
## staff door.

@export var lamp_height := 1.3
@export var locked_colour := Color(0.95, 0.35, 0.3)
@export var open_colour := Color(0.45, 0.85, 0.5)
@export var cell_size := 1.0
@export var padlock_textures: Dictionary[String, Texture2D] = {
	"locked": preload("res://core/ui/markers/padlock.svg"),
	"locked_pinned": preload("res://core/ui/markers/padlock_pinned.svg"),
	"unlocked": preload("res://core/ui/markers/unlocked.svg"),
	"unlocked_pinned": preload("res://core/ui/markers/unlocked_pinned.svg"),
}

var runner: ScheduleRunner:
	set(value):
		runner = value
		runner.doors_changed.connect(_redraw)
var building: Building:
	set(value):
		building = value
		building.changed.connect(_redraw)
		building.active_changed.connect(func(_level: int) -> void: _redraw())
## Door kinds by id, for the colour of their plates.
var door_kinds: Dictionary[StringName, DoorKindDef] = {}

var _mesh := ImmediateMesh.new()
var _padlocks := Node3D.new()


func _ready() -> void:
	var instance := MeshInstance3D.new()
	instance.mesh = _mesh
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Unshaded, so they glow at night.
	var material := MeshShapes.vertex_colour_material()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	instance.material_override = material
	add_child(instance)
	add_child(_padlocks)
	_redraw()


func _redraw() -> void:
	if not is_inside_tree() or runner == null or building == null:
		return
	_mesh.clear_surfaces()
	for child in _padlocks.get_children():
		child.queue_free()
	var drawn := false
	for n: int in building.levels:
		if n > building.active:
			continue
		var map := building.levels[n]
		for edge: Vector3i in map.door_kinds:
			var kind: DoorKindDef = door_kinds.get(map.door_kind_at(edge))
			if kind == null:
				continue
			if not drawn:
				_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
				drawn = true
			_add_marks(map, edge, Vector3(0.36, 0.08, 0.36), kind.colour, 0.12)
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
		var locked := runner.doors[key]
		_add_marks(map, edge, Vector3(0.11, 0.07, 0.11), locked_colour if locked else open_colour, 0.0)
		if runner.overrides.has(key):
			_add_padlock(map, edge, locked, runner.pinned.has(key))
	if drawn:
		_mesh.surface_end()


## A small box on each face of a door, `rise` metres above the lamp.
func _add_marks(map: BuildingMap, edge: Vector3i, box: Vector3, colour: Color, rise: float) -> void:
	var across := _across(edge)
	for sign: float in [-1.0, 1.0]:
		var at := _above(map, edge, lamp_height + rise) + across * sign * 0.12
		MeshShapes.add_box_immediate(_mesh, at, box - across * (box.x - 0.05), colour)


func _add_padlock(map: BuildingMap, edge: Vector3i, locked: bool, pin: bool) -> void:
	var sprite := Sprite3D.new()
	sprite.texture = padlock_textures["%s%s" % ["locked" if locked else "unlocked", "_pinned" if pin else ""]]
	sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sprite.pixel_size = 0.008
	sprite.no_depth_test = true
	sprite.render_priority = 2
	sprite.position = _above(map, edge, lamp_height + 0.45)
	_padlocks.add_child(sprite)


## The middle of a door, `height` metres above the higher floor beside it.
func _above(map: BuildingMap, edge: Vector3i, height: float) -> Vector3:
	var ends := BuildingMap.edge_ends(edge)
	var middle := (ends[0] + ends[1]) * 0.5
	var cells := BuildingMap.edge_cells(edge)
	var base := maxf(map.floor_height(cells[0]) if map.has_floor(cells[0]) else -INF,
			map.floor_height(cells[1]) if map.has_floor(cells[1]) else -INF)
	return Vector3(middle.x * cell_size, base + height, middle.y * cell_size)


static func _across(edge: Vector3i) -> Vector3:
	return Vector3(0, 0, 1) if edge.z == BuildingMap.EDGE_X else Vector3(1, 0, 0)
