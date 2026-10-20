extends Node3D
## The prison sandbox: a grid you can build on, with a sample prison to
## start from (see SamplePrisons) and prisoners living out the day on its
## timetable.

## Off starts on empty land.
@export var build_sample_layout := true
## Which sample prison to start with. The F3 inspector can switch to another.
@export_enum("Starter block", "Two storeys", "Hillside", "Island", "Long way round", "Basement",
		"Crowded canteen", "Locked out", "Staff wing", "Kitchen") var sample := 0
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
@onready var hud: CanvasLayer = $HUD
@onready var sun: DirectionalLight3D = $Sun
@onready var world_environment: WorldEnvironment = $WorldEnvironment

var building: Building
## The ground level's map. Other levels are in `building`.
var map: BuildingMap
var paths := PathNetwork.new()
var people := People.new()
## Every item about the place, and the work to be done with them.
var items := ItemStore.new()
var jobs := JobBoard.new()
var item_view := ItemView.new()
var kitchen := Kitchen.new()
var cleaning := Cleaning.new()
## Game time. Everything that happens over time listens to it.
var clock := GameClock.new()
## The prisoners' timetable, a copy of the catalogue's so edits stay in
## this game.
var schedule: Schedule = PrisonCatalogue.SCHEDULE.copy()
## Puts everyone in their timetable block and locks cell doors.
var runner := ScheduleRunner.new()
var day_night := DayNight.new()
var door_lights := DoorLights.new()
## Tints rooms by who may be in them while the zones tool is open.
var zone_tints := ZoneTints.new()
## The day, time, block and speed, top left.
var clock_bar := ClockBar.new()
## Painting the timetable, on T.
var timetable := TimetableWindow.new()
## The F3 inspector for people, objects and rooms.
var inspector := Inspector.new()
## Grid lines at the height of the level being built on, off the ground.
var level_grid := LevelGrid.new()
## The bar across the top: level, room under the mouse, people.
var status := StatusBar.new()
## Level, wall view, help and debug buttons, top right.
var view_bar := ViewBar.new()
## Every control, on F1.
var help_card := HelpCard.new()
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
	view.door_model = PrisonCatalogue.DOOR_MODEL
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

	# People walk the build, following the clock and the timetable.
	clock.name = "Clock"
	add_child(clock)
	people.name = "People"
	people.terrain = terrain
	people.body_model = PrisonCatalogue.PERSON_MODEL
	people.needs = PrisonCatalogue.NEEDS
	people.traits = PrisonCatalogue.TRAITS
	people.moodlet_defs = PrisonCatalogue.moodlets()
	people.room_types = PrisonCatalogue.ROOM_TYPES
	people.home_room_types = PrisonCatalogue.HOME_ROOM_TYPES
	people.access = PrisonCatalogue.access()
	jobs.people = people
	jobs.items = items
	jobs.roles = PrisonCatalogue.roles()
	people.jobs = jobs
	people.items = items
	people.litter = PrisonCatalogue.LITTER
	people.building = building
	people.paths = paths
	people.clock = clock
	grid.add_child(people)
	runner.name = "ScheduleRunner"
	runner.clock = clock
	runner.building = building
	runner.people = people
	runner.schedules = {&"prisoner": schedule}
	add_child(runner)
	door_lights.name = "DoorLights"
	door_lights.cell_size = grid.cell_size
	door_lights.building = building
	door_lights.runner = runner
	door_lights.door_kinds = people.access.door_kinds
	grid.add_child(door_lights)
	controller.door_lock_clicked.connect(runner.toggle_lock)
	zone_tints.name = "ZoneTints"
	zone_tints.cell_size = grid.cell_size
	zone_tints.access = people.access
	zone_tints.controller = controller
	zone_tints.building = building
	grid.add_child(zone_tints)
	item_view.name = "Items"
	item_view.cell_size = grid.cell_size
	item_view.items = items
	item_view.people = people
	item_view.building = building
	grid.add_child(item_view)
	day_night.name = "DayNight"
	day_night.sun = sun
	day_night.environment = world_environment.environment
	day_night.clock = clock
	add_child(day_night)
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
	inspector.clock = clock
	inspector.runner = runner
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
	people.assign_beds()
	runner.refresh()
	kitchen.name = "Kitchen"
	kitchen.people = people
	kitchen.jobs = jobs
	kitchen.items = items
	kitchen.building = building
	kitchen.schedule = schedule
	kitchen.clock = clock
	add_child(kitchen)
	kitchen.start()
	cleaning.name = "Cleaning"
	cleaning.jobs = jobs
	cleaning.items = items
	cleaning.building = building
	cleaning.clock = clock
	add_child(cleaning)
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
	_add_hud()
	_on_cell_hovered(cursor.hovered_cell)
	_apply_wall_view()
	if build_sample_layout:
		Toasts.post(SamplePrisons.NAMES[sample], SamplePrisons.CHALLENGES[sample]
				+ "\nPress F1 for the controls.", 8.0)


func _add_hud() -> void:
	hud.add_child(status)
	view_bar.building = building
	view_bar.controller = controller
	view_bar.help_pressed.connect(func() -> void: help_card.visible = not help_card.visible)
	view_bar.debug_pressed.connect(func() -> void: debug_overlay.visible = not debug_overlay.visible)
	debug_overlay.visibility_changed.connect(func() -> void: view_bar.show_debug(debug_overlay.visible))
	hud.add_child(view_bar)
	help_card.sections = PrisonHelp.SECTIONS
	hud.add_child(help_card)
	clock_bar.clock = clock
	clock_bar.runner = runner
	clock_bar.day_night = day_night
	clock_bar.timetable_pressed.connect(timetable.toggle)
	hud.add_child(clock_bar)
	timetable.schedule = schedule
	timetable.activities = PrisonCatalogue.ACTIVITIES
	timetable.clock = clock
	hud.add_child(timetable)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("level_up"):
		building.active += 1
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("level_down"):
		building.active -= 1
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("time_pause"):
		clock.toggle_pause()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("time_faster"):
		clock.speed_index += 1
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("time_slower"):
		if not clock.paused():
			clock.speed_index = maxi(clock.speed_index - 1, 1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("timetable_toggle"):
		timetable.toggle()
		get_viewport().set_input_as_handled()


func _add_level_view(level: int, level_map: BuildingMap) -> void:
	var level_view := BuildingView.new()
	level_view.name = "BuildingView%d" % level
	level_view.grid = grid
	level_view.terrain = terrain
	level_view.level = level
	level_view.room_types = PrisonCatalogue.ROOM_TYPES
	level_view.door_model = PrisonCatalogue.DOOR_MODEL
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


func _exit_tree() -> void:
	jobs.clear()


func _process(_delta: float) -> void:
	# Cutaway follows the camera round.
	var camera := get_viewport().get_camera_3d()
	if camera != null and controller.wall_view == BuildController.WallView.CUTAWAY:
		var look := -camera.global_transform.basis.z
		controller.view.cut_direction = Vector2(look.x, look.z)
	var count := "%d people" % people.people.size()
	if status.item_text(&"people") != count:
		status.set_item(&"people", count, &"SubtleLabel")


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
	status.set_item(&"level", Building.level_name(building.active), &"HeaderLabel")
	var room := building.current().room_at(cell) if cell != GridCursor.NO_CELL else null
	if room == null:
		status.set_item(&"room", "No room here" if cell != GridCursor.NO_CELL else "Off the map", &"SubtleLabel")
		return
	var def := PrisonCatalogue.room_type(room.type)
	status.set_item(&"room", "%s  ·  %d tiles  ·  %s" % [
		def.display_name if def != null else "Unmarked room",
		room.cells.size(),
		"indoors" if room.indoor else "outdoors"])
