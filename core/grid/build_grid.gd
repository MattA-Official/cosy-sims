class_name BuildGrid
extends Node3D
## The square tile grid everything is built on. Cell (0, 0) has its corner at
## this node's origin and cells run along +X and +Z.
##
## Floors and objects will sit in cells; walls will sit on the edges between
## cells (like The Sims), so rooms can be any shape.

signal size_changed

@export var size := Vector2i(48, 48):
	set(value):
		size = value
		if is_node_ready():
			_build_ground()
		size_changed.emit()
@export var cell_size := 1.0
@export var ground_material: Material
## Turn off when a Terrain draws the ground instead of this flat plane.
@export var draw_ground := true

var _ground: MeshInstance3D


func _ready() -> void:
	_build_ground()


func contains(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < size.x and cell.y < size.y


## The cell under a world position. It may be outside the grid; check with contains().
func world_to_cell(world_position: Vector3) -> Vector2i:
	var local := to_local(world_position)
	return Vector2i(floori(local.x / cell_size), floori(local.z / cell_size))


## The centre of a cell, on the ground.
func cell_to_world(cell: Vector2i) -> Vector3:
	return to_global(Vector3((cell.x + 0.5) * cell_size, 0.0, (cell.y + 0.5) * cell_size))


## The middle of the whole grid, on the ground.
func centre() -> Vector3:
	return to_global(Vector3(size.x, 0.0, size.y) * cell_size * 0.5)


## The grid's extent on the XZ plane, in world units (ignores rotation).
func world_rect() -> Rect2:
	var origin := global_position
	return Rect2(origin.x, origin.z, size.x * cell_size, size.y * cell_size)


func _build_ground() -> void:
	if not draw_ground:
		return
	if _ground == null:
		_ground = MeshInstance3D.new()
		_ground.name = "Ground"
		add_child(_ground)
	var plane := PlaneMesh.new()
	plane.size = Vector2(size) * cell_size
	_ground.mesh = plane
	_ground.position = Vector3(size.x, 0.0, size.y) * cell_size * 0.5
	_ground.material_override = ground_material
