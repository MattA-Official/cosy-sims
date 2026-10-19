extends Node3D
## The prison sandbox: a grid you can build on, with a sample prison to
## start from (see SamplePrisons) and prisoners walking about it.

## Off starts on empty land.
@export var build_sample_layout := true
## Which sample prison to start with. The F3 inspector can switch to another.
@export_enum("Starter block", "Two storeys", "Hillside", "Island", "Long way round", "Basement",
		"Crowded canteen", "Locked out") var sample := 0
## Split levels: floors nudged within their storey, and ramps between
## them. Off keeps every floor a whole storey above the one below.
@export var split_levels := false
## Door steps: a door between floors up to a metre apart gets a few steps
## on the low side. Off refuses doors between floors more than a step apart.
@export var door_steps := false

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
var people := People.new()
## The F3 inspector for people, objects and rooms.
var inspector := Inspector.new()
## Grid lines at the height of the level being built on, off the ground.
var level_grid := LevelGrid.new()
## One BuildingView per level, by level number.
var views: Dictionary[int, BuildingView] = {}


func _ready() -> void:
	Building.split_levels = split_levels
	Building.door_steps = door_steps
	# The grid is the whole world; you start owning the middle of it.
	var land := Rect2i(grid.size / 4, grid.size / 2)
	building = Building.new(land, PrisonCatalogue.FLOORS, PrisonCatalogue.WALLS)
	map = building.ground()
	view.room_types = PrisonCatalogue.ROOM_TYPES
	view.map = map
	views[0] = view
	building.level_added.connect(_add_level_view)
	building.active_changed.connect(_on_level_changed)
	controller.wall_view_changed.connect(func(_mode: BuildController.WallView) -> void: _apply_wall_view())
	controller.building = building
	paths.terrain = terrain
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

	# People walk the build.
	people.name = "People"
	people.terrain = terrain
	people.needs = PrisonCatalogue.NEEDS
	people.building = building
	people.paths = paths
	grid.add_child(people)
	level_grid.name = "LevelGrid"
	level_grid.grid = grid
	level_grid.height_at = _floor_level_at
	level_grid.building = building
	grid.add_child(level_grid)
	inspector.name = "Inspector"
	inspector.people = people
	inspector.building = building
	inspector.cursor = cursor
	inspector.controller = controller
	inspector.debug_overlay = debug_overlay
	inspector.room_types = PrisonCatalogue.ROOM_TYPES
	grid.add_child(inspector)
	if SamplePrisons.next >= 0:
		sample = SamplePrisons.next
		SamplePrisons.next = -1
	var site := SamplePrisons.Site.new()
	site.building = building
	site.terrain = terrain
	site.water = water
	site.foliage = foliage
	site.paths = paths
	site.people = people
	SamplePrisons.build(sample if build_sample_layout else -1, site)
	var load_sample := func(index: int) -> void:
		SamplePrisons.next = index
		get_tree().reload_current_scene()
	inspector.offer_samples(SamplePrisons.NAMES, SamplePrisons.CHALLENGES, sample, load_sample)

	camera_rig.bounds = grid.world_rect()
	camera_rig.position = grid.centre()
	camera_rig.focus_on(grid.centre())

	controller.tool_changed.connect(func(tool: BuildController.Tool) -> void:
		cursor.visible = tool == BuildController.Tool.NONE)
	cursor.cell_hovered.connect(_on_cell_hovered)
	cursor.height_at = _floor_level_at
	building.changed.connect(func() -> void: _on_cell_hovered(cursor.hovered_cell))
	_on_cell_hovered(cursor.hovered_cell)
	_apply_wall_view()


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
	level_view.visible = building == null or level <= building.active
	grid.add_child(level_view)
	level_view.map = level_map
	views[level] = level_view
	# Roofs leave out tiles the level above has floor on.
	if building.levels.has(level + 1):
		level_view.above = building.levels[level + 1]
	if views.has(level - 1):
		views[level - 1].above = level_map
	_apply_wall_view()


## Shows the levels up to the one being built on, and hides the land when
## looking at a basement.
func _on_level_changed(level: int) -> void:
	var above_ground := level >= 0
	for node: Node3D in [terrain, water, foliage, path_view]:
		node.visible = above_ground
	controller.view = views[level]
	_apply_wall_view()
	debug_overlay.map = building.current()
	camera_rig.pick_height = NAN if level == 0 else _level_height(level)
	_on_cell_hovered(cursor.hovered_cell)


## Sets every level's walls and roofs for the Tab view. Levels below the
## one being built on have their walls up and their roofs on, so you see
## the floor above them; the level being built on takes the Tab view.
## Roofs on shows every level, roofs and all, as from outside.
func _apply_wall_view() -> void:
	if building == null:
		return
	var mode := controller.wall_view
	var level := building.active
	for n: int in views:
		var v := views[n]
		var current := n == level
		v.visible = n <= level or (mode == BuildController.WallView.ROOFS and n >= 0)
		v.show_labels = current and mode != BuildController.WallView.ROOFS
		v.walls_low = current and mode == BuildController.WallView.DOWN
		v.cutaway = current and mode == BuildController.WallView.CUTAWAY
		v.show_roof = n < level or mode == BuildController.WallView.ROOFS


func _process(_delta: float) -> void:
	# Cutaway follows the camera round.
	var camera := get_viewport().get_camera_3d()
	if camera != null and controller.wall_view == BuildController.WallView.CUTAWAY:
		var look := -camera.global_transform.basis.z
		controller.view.cut_direction = Vector2(look.x, look.z)


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
