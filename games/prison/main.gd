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
@onready var path_view: PathView = $BuildGrid/PathView
@onready var debug_overlay: DebugOverlay = $BuildGrid/DebugOverlay
@onready var camera_rig: CameraRig = $CameraRig
@onready var cursor: GridCursor = $GridCursor
@onready var cell_label: Label = $HUD/CellLabel

var building: Building
## The ground level's map. Other levels are in `building`.
var map: BuildingMap
var paths := PathNetwork.new()
## One BuildingView per level, by level number.
var views: Dictionary[int, BuildingView] = {}


func _ready() -> void:
	# The grid is the whole world; you start owning the middle of it.
	var land := Rect2i(grid.size / 4, grid.size / 2)
	building = Building.new(land, PrisonCatalogue.FLOORS, PrisonCatalogue.WALLS)
	map = building.ground()
	view.room_types = PrisonCatalogue.ROOM_TYPES
	view.map = map
	views[0] = view
	building.level_added.connect(_add_level_view)
	building.active_changed.connect(_on_level_changed)
	controller.building = building
	controller.paths = paths
	path_view.styles = PrisonCatalogue.PATHS
	path_view.network = paths
	debug_overlay.room_types = PrisonCatalogue.ROOM_TYPES
	debug_overlay.map = map

	# Hills and a pond around the land. Ground under buildings stays put,
	# water stays off floors, and plants drown when water reaches them.
	terrain.is_locked = building.corner_in_use
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
	cursor.height_at = _floor_level_at
	building.changed.connect(func() -> void: _on_cell_hovered(cursor.hovered_cell))
	_on_cell_hovered(cursor.hovered_cell)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("level_up"):
		building.active += 1
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("level_down"):
		building.active -= 1
		get_viewport().set_input_as_handled()


func _add_level_view(level: int, level_map: BuildingMap) -> void:
	var level_view := BuildingView.new()
	level_view.name = "BuildingView%d" % level
	level_view.grid = grid
	level_view.terrain = terrain
	level_view.level = level
	level_view.room_types = PrisonCatalogue.ROOM_TYPES
	grid.add_child(level_view)
	level_view.map = level_map
	views[level] = level_view


## Shows the levels up to the one being built on, and hides the land when
## looking at a basement.
func _on_level_changed(level: int) -> void:
	var walls_low := controller.view.walls_low
	for n: int in views:
		views[n].visible = n <= level
		views[n].show_labels = n == level
	var above_ground := level >= 0
	for node: Node3D in [terrain, water, foliage, path_view]:
		node.visible = above_ground
	controller.view = views[level]
	controller.view.walls_low = walls_low
	debug_overlay.map = building.current()
	camera_rig.pick_height = NAN if level == 0 else _level_height(level)
	_on_cell_hovered(cursor.hovered_cell)


## A typical floor height for a level, for picking: the middle of the land
## at that storey.
func _level_height(level: int) -> float:
	var centre := building.ground().land_bounds().get_center()
	var floors := building.level(level).floor_heights.values()
	if not floors.is_empty():
		return floors.reduce(func(a: float, b: float) -> float: return a + b) / floors.size()
	return building.storey_height(level, centre, terrain.cell_height(centre))


## Where the hover highlight sits: on the floor of the level being built
## on, or on the ground.
func _floor_level_at(cell: Vector2i) -> float:
	var level_map := building.current()
	if level_map.has_floor(cell):
		return level_map.floor_height(cell)
	if building.active == 0:
		return terrain.cell_height(cell)
	return building.storey_height(building.active, cell, terrain.cell_height(cell))


func _on_cell_hovered(cell: Vector2i) -> void:
	var prefix := Building.level_name(building.active) + "    "
	if cell == GridCursor.NO_CELL:
		cell_label.text = prefix + "Cell: none"
		return
	var text := prefix + "Cell: %d, %d" % [cell.x, cell.y]
	var room := building.current().room_at(cell)
	if room != null:
		var def := PrisonCatalogue.room_type(room.type)
		text += "    Room: %s, %d tiles, %s" % [
			def.display_name if def != null else "unassigned",
			room.cells.size(),
			"indoors" if room.indoor else "outdoors"]
	cell_label.text = text
