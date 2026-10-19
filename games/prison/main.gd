extends Node3D
## Step 1 sandbox for the prison game: a grid, the camera, and a cursor.
## Left-click a cell to drop or remove a placeholder crate, just to get a feel
## for picking cells. Real building tools arrive in step 2.

@onready var grid: BuildGrid = $BuildGrid
@onready var camera_rig: CameraRig = $CameraRig
@onready var cursor: GridCursor = $GridCursor
@onready var cell_label: Label = $HUD/CellLabel

var _crates := {} # Vector2i -> Node3D
var _crate_mesh := BoxMesh.new()
var _crate_material := StandardMaterial3D.new()


func _ready() -> void:
	camera_rig.bounds = grid.world_rect()
	camera_rig.position = grid.centre()
	camera_rig.focus_on(grid.centre())

	_crate_mesh.size = Vector3.ONE * grid.cell_size * 0.8
	_crate_material.albedo_color = Color(0.95, 0.72, 0.45)

	cursor.cell_hovered.connect(_on_cell_hovered)
	cursor.cell_clicked.connect(_on_cell_clicked)
	_on_cell_hovered(cursor.hovered_cell)


func _on_cell_hovered(cell: Vector2i) -> void:
	if cell == GridCursor.NO_CELL:
		cell_label.text = "Cell: none"
	else:
		cell_label.text = "Cell: %d, %d" % [cell.x, cell.y]


func _on_cell_clicked(cell: Vector2i, _button: MouseButton) -> void:
	if _crates.has(cell):
		_crates[cell].queue_free()
		_crates.erase(cell)
		return
	var crate := MeshInstance3D.new()
	crate.mesh = _crate_mesh
	crate.material_override = _crate_material
	add_child(crate)
	crate.global_position = grid.cell_to_world(cell) + Vector3.UP * _crate_mesh.size.y * 0.5
	_crates[cell] = crate
