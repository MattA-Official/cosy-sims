class_name CoverageTint
extends Node3D
## Tints the tiles watchers have seen lately in blue, stronger the fresher,
## on the level in view: while the patrol route tool is open, or while
## `shown` is on (the Security window's toggle).

const REFRESH_SECONDS := 0.5

@export var cell_size := 1.0
@export var lift := 0.06
@export var colour := Color(0.35, 0.6, 1.0, 0.5)

var coverage: Coverage
var building: Building
var controller: BuildController
## (level, cell: Vector2i) -> float: the floor or ground height there.
var height_at: Callable
var shown := false:
	set(value):
		shown = value
		_redraw()

var _mesh := ImmediateMesh.new()
var _wait := 0.0


func _ready() -> void:
	var instance := MeshInstance3D.new()
	instance.mesh = _mesh
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.material_override = MeshShapes.vertex_colour_material(true)
	add_child(instance)


func showing() -> bool:
	return shown or (controller != null and controller.tool == BuildController.Tool.ROUTE)


func _process(delta: float) -> void:
	_wait -= delta
	if _wait <= 0.0:
		_wait = REFRESH_SECONDS
		_redraw()


func _redraw() -> void:
	if not is_inside_tree():
		return
	_mesh.clear_surfaces()
	if coverage == null or building == null or not showing():
		return
	var level := building.active
	var any := false
	for key: Vector3i in coverage.seen:
		if key.x != level:
			continue
		if not any:
			_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
			any = true
		var cell := Vector2i(key.y, key.z)
		var tint := colour
		tint.a *= clampf(coverage.seen[key], 0.15, 1.0)
		var height: float = height_at.call(level, cell) if height_at.is_valid() else 0.0
		MeshShapes.add_box_immediate(_mesh, Vector3((cell.x + 0.5) * cell_size, height + lift,
				(cell.y + 0.5) * cell_size), Vector3(0.48, 0.01, 0.48) * cell_size, tint)
	if any:
		_mesh.surface_end()
