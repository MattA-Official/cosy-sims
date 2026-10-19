class_name GridCursor
extends Node3D
## Highlights the grid cell under the mouse and reports clicks on cells.
## Building tools in step 2 will listen to these signals.

signal cell_hovered(cell: Vector2i)
signal cell_clicked(cell: Vector2i, button: MouseButton)

@export var grid: BuildGrid
@export var camera_rig: CameraRig
## Optional: lifts the highlight onto the terrain.
@export var terrain: Terrain
@export var colour := Color(1.0, 1.0, 1.0, 0.35)

const NO_CELL := Vector2i(-1_000_000, -1_000_000)

## The hovered cell, or NO_CELL when the mouse is off the grid.
var hovered_cell := NO_CELL
## Optional: the height to draw the highlight at for a cell, such as the
## floor of an upper storey. Overrides the terrain when set.
var height_at: Callable

var _highlight: MeshInstance3D


func _ready() -> void:
	_highlight = MeshInstance3D.new()
	var quad := PlaneMesh.new()
	quad.size = Vector2.ONE * grid.cell_size * 0.94
	_highlight.mesh = quad
	var material := StandardMaterial3D.new()
	material.albedo_color = colour
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_highlight.material_override = material
	_highlight.visible = false
	add_child(_highlight)


func _process(_delta: float) -> void:
	var cell := NO_CELL
	var hit: Variant = camera_rig.ground_point_at(get_viewport().get_mouse_position())
	if hit != null:
		var candidate := grid.world_to_cell(hit)
		if grid.contains(candidate):
			cell = candidate
	if cell == hovered_cell:
		return
	hovered_cell = cell
	_highlight.visible = cell != NO_CELL
	if _highlight.visible:
		var lift := 0.0
		if height_at.is_valid():
			lift = height_at.call(cell)
		elif terrain != null:
			lift = terrain.cell_height(cell)
		_highlight.global_position = grid.cell_to_world(cell) + Vector3.UP * (lift + 0.04)
	cell_hovered.emit(cell)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and hovered_cell != NO_CELL:
		if event.button_index == MOUSE_BUTTON_LEFT:
			cell_clicked.emit(hovered_cell, event.button_index)
