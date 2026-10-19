extends Node3D
## The prison sandbox: a grid you can build on, with a small sample block to
## start from. People arrive in step 3.

@export var build_sample_layout := true

@onready var grid: BuildGrid = $BuildGrid
@onready var view: BuildingView = $BuildGrid/BuildingView
@onready var controller: BuildController = $BuildGrid/BuildController
@onready var camera_rig: CameraRig = $CameraRig
@onready var cursor: GridCursor = $GridCursor
@onready var cell_label: Label = $HUD/CellLabel

var map: BuildingMap


func _ready() -> void:
	map = BuildingMap.new(grid.size)
	view.room_types = PrisonCatalogue.ROOM_TYPES
	view.map = map
	controller.map = map
	if build_sample_layout:
		SampleLayout.build(map, grid.size / 2 - Vector2i(6, 5))

	camera_rig.bounds = grid.world_rect()
	camera_rig.position = grid.centre()
	camera_rig.focus_on(grid.centre())

	controller.tool_changed.connect(func(tool: BuildController.Tool) -> void:
		cursor.visible = tool == BuildController.Tool.NONE)
	cursor.cell_hovered.connect(_on_cell_hovered)
	map.changed.connect(func() -> void: _on_cell_hovered(cursor.hovered_cell))
	_on_cell_hovered(cursor.hovered_cell)


func _on_cell_hovered(cell: Vector2i) -> void:
	if cell == GridCursor.NO_CELL:
		cell_label.text = "Cell: none"
		return
	var text := "Cell: %d, %d" % [cell.x, cell.y]
	var room := map.room_at(cell)
	if room != null:
		var def := PrisonCatalogue.room_type(room.type)
		text += "    Room: %s, %d tiles%s" % [
			def.display_name if def != null else "unassigned",
			room.cells.size(),
			"" if room.enclosed else ", open"]
	cell_label.text = text
