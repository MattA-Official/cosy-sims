extends Node3D
## The prison sandbox: a grid you can build on, with a small sample block to
## start from. People arrive in step 3.

@export var build_sample_layout := true

@onready var grid: BuildGrid = $BuildGrid
@onready var view: BuildingView = $BuildGrid/BuildingView
@onready var controller: BuildController = $BuildGrid/BuildController
@onready var terrain: Terrain = $BuildGrid/Terrain
@onready var foliage: FoliageLayer = $BuildGrid/Foliage
@onready var water: WaterLayer = $BuildGrid/Water
@onready var debug_overlay: DebugOverlay = $BuildGrid/DebugOverlay
@onready var camera_rig: CameraRig = $CameraRig
@onready var cursor: GridCursor = $GridCursor
@onready var cell_label: Label = $HUD/CellLabel

var map: BuildingMap


func _ready() -> void:
	# The grid is the whole world; you start owning the middle of it.
	var land := Rect2i(grid.size / 4, grid.size / 2)
	map = BuildingMap.new(land)
	map.register_styles(PrisonCatalogue.FLOORS, PrisonCatalogue.WALLS)
	view.room_types = PrisonCatalogue.ROOM_TYPES
	view.map = map
	controller.map = map
	debug_overlay.room_types = PrisonCatalogue.ROOM_TYPES
	debug_overlay.map = map

	# Hills and a pond around the land. Ground under buildings stays put,
	# water stays off floors, and plants drown when water reaches them.
	terrain.is_locked = map.corner_in_use
	water.is_blocked = map.has_floor
	water.changed.connect(foliage.remove_underwater)
	var ground: ShaderMaterial = terrain.ground_material
	ground.set_shader_parameter("water_level",
			terrain.sea_level if terrain.has_sea else Terrain.MIN_HEIGHT - 10.0)
	var pond := Vector2(land.end.x + 9, land.get_center().y + 6)
	StartingLandscape.shape(terrain, land, pond)
	water.fill_at(Vector2i(pond))

	var layout_origin := land.get_center() - Vector2i(8, 7)
	if build_sample_layout:
		SampleLayout.build(map, layout_origin)
	StartingLandscape.plant(foliage, terrain, map, layout_origin)

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
		text += "    Room: %s, %d tiles, %s" % [
			def.display_name if def != null else "unassigned",
			room.cells.size(),
			"indoors" if room.indoor else "outdoors"]
	cell_label.text = text
