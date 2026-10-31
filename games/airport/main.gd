extends Node3D
## The airport sandbox: land to build a terminal on, with the shed to start
## from (see SampleAirports). For now (milestone A0) it is the build tools
## and a few people wandering: queues, signs, one-way doors, escalators,
## double-height halls, belts and the landside / airside line are all
## here to build with; flights, passengers with somewhere to be and bags
## come in later milestones.

const TITLE_SCENE := "res://games/airport/title.tscn"

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
var signage := Signage.new()
## The line between landside and airside, and the doors that break it.
var sides := SecuritySides.new()
var belt_view := BeltView.new()
var clock := GameClock.new()
var day_night := DayNight.new()
var zone_tints := ZoneTints.new()
var ledger := Ledger.new()
var build_costs := BuildCosts.new()
var land_plots := LandPlots.new()
var undo := UndoHistory.new()
var inspector := Inspector.new()
var level_grid := LevelGrid.new()
var status := StatusBar.new()
var view_bar := ViewBar.new()
var clock_bar := ClockBar.new()
var help_card := HelpCard.new()
var pause_menu := PauseMenu.new()
## Made in code, as it needs the catalogue before it joins the tree.
var toolbar := BuildToolbar.new()
## One BuildingView per level, by level number.
var views: Dictionary[int, BuildingView] = {}
## Running behind the title screen: no HUD, no notes.
var attract := false
var title := "My airport"
var start := AirportNewGame.Start.SHED
var map_size: MapSizeDef


func _ready() -> void:
	var new_game := AirportNewGame.pending
	AirportNewGame.pending = false
	if new_game:
		start = AirportNewGame.start
		if AirportNewGame.airport_name != "":
			title = AirportNewGame.airport_name
	map_size = AirportCatalogue.map_size(AirportNewGame.map_size)
	grid.size = Vector2i.ONE * map_size.tiles(LandPlots.SIZE)
	terrain.size = grid.size
	building = Building.new(map_size.start(LandPlots.SIZE), AirportCatalogue.FLOORS, AirportCatalogue.WALLS)
	map = building.ground()
	_setup_view(view, 0)
	view.map = map
	views[0] = view
	building.level_added.connect(_add_level_view)
	building.active_changed.connect(_on_level_changed)
	controller.wall_view_changed.connect(func(_mode: BuildController.WallView) -> void: _apply_wall_view())
	controller.building = building
	paths.terrain = terrain
	controller.paths = paths
	path_view.styles = AirportCatalogue.PATHS
	path_view.network = paths
	debug_overlay.room_types = AirportCatalogue.ROOM_TYPES
	debug_overlay.map = map
	terrain.is_locked = building.corner_in_use
	water.is_blocked = map.has_floor
	water.changed.connect(foliage.remove_underwater)
	(terrain.ground_material as ShaderMaterial).set_shader_parameter("water_level", Terrain.MIN_HEIGHT - 10.0)

	clock.name = "Clock"
	add_child(clock)
	people.name = "People"
	people.terrain = terrain
	people.body_model = AirportCatalogue.PERSON_MODEL
	people.needs = AirportCatalogue.NEEDS
	people.room_types = AirportCatalogue.ROOM_TYPES
	people.access = AirportCatalogue.access()
	people.building = building
	people.paths = paths
	people.clock = clock
	signage.building = building
	for def in AirportCatalogue.ROOM_TYPES:
		signage.room_types[def.id] = def
	people.signage = signage
	grid.add_child(people)
	sides.access = people.access
	sides.building = building
	sides.exit_sides = [&"airside"]

	belt_view.name = "Belts"
	belt_view.cell_size = grid.cell_size
	belt_view.terrain = terrain
	belt_view.building = building
	grid.add_child(belt_view)
	zone_tints.name = "ZoneTints"
	zone_tints.ground_height = terrain.cell_height
	zone_tints.cell_size = grid.cell_size
	zone_tints.access = people.access
	zone_tints.flagged_doors = sides.gaps
	zone_tints.controller = controller
	zone_tints.building = building
	grid.add_child(zone_tints)
	day_night.name = "DayNight"
	day_night.sun = sun
	day_night.environment = world_environment.environment
	day_night.clock = clock
	day_night.fog_material = terrain.ground_material as ShaderMaterial
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
	inspector.room_types = AirportCatalogue.ROOM_TYPES
	inspector.clock = clock
	inspector.add_groups = [[&"passenger", "Add a passenger here"], [&"staff", "Add a member of staff here"]]
	grid.add_child(inspector)

	var site := SampleAirports.Site.new()
	site.area = map_size.area(LandPlots.SIZE)
	site.building = building
	site.terrain = terrain
	site.water = water
	site.foliage = foliage
	site.paths = paths
	site.people = people
	SampleAirports.build(start, site)

	# Money is a sandbox until the airport earns its own (A5).
	ledger.name = "Ledger"
	ledger.sandbox = true
	add_child(ledger)
	build_costs.name = "BuildCosts"
	build_costs.building = building
	build_costs.ledger = ledger
	build_costs.door_kinds = people.access.door_kinds
	add_child(build_costs)
	build_costs.start()
	controller.spending_allowed = ledger.can_spend
	controller.build_costs = build_costs
	controller.find_object = AirportCatalogue.object
	controller.templates = TemplateStore.new()
	controller.templates.find_object = AirportCatalogue.object
	controller.balance = func() -> int: return 1 << 30
	controller.drop_refused.connect(func(reason: String) -> void: Toasts.post("Can't put it there", reason))
	controller.copied.connect(func(what: String) -> void:
		Toasts.post("Copied", "Ctrl+V to put down a copy of the %s." % what))
	land_plots.building = building
	land_plots.terrain = terrain
	land_plots.water = water
	land_plots.ledger = ledger
	land_plots.paths = paths
	land_plots.clock = clock
	land_plots.area = map_size.area(LandPlots.SIZE)
	var area := Rect2(land_plots.area)
	(terrain.ground_material as ShaderMaterial).set_shader_parameter("fog_rect",
			Vector4(area.position.x, area.position.y, area.size.x, area.size.y) * grid.cell_size)
	controller.land_plots = land_plots

	undo.name = "Undo"
	undo.capture = capture_world
	undo.restore = func(state: Dictionary) -> void:
		build_costs.refund_all = true
		restore_world(state)
		build_costs.refund_all = false
	add_child(undo)
	undo.start([building.changed, terrain.changed, water.changed, foliage.changed, paths.changed] as Array[Signal])
	land_plots.bought.connect(func(_plot: Rect2i) -> void: undo.reset())
	land_plots.sold.connect(func(_plot: Rect2i) -> void: undo.reset())
	undo.nothing_to_undo = land_plots.undo_last

	toolbar.name = "BuildToolbar"
	toolbar.controller = controller
	toolbar.catalogue = AirportCatalogue
	toolbar.tools = AirportCatalogue.TOOLS
	toolbar.group_starts = AirportCatalogue.GROUP_STARTS
	toolbar.extra_keys = AirportCatalogue.EXTRA_KEYS
	toolbar.floor_modes = AirportCatalogue.FLOOR_MODES
	toolbar.openings = AirportCatalogue.OPENINGS
	toolbar.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	toolbar.offset_top = -140.0
	toolbar.offset_bottom = -12.0
	toolbar.grow_vertical = Control.GROW_DIRECTION_BEGIN
	hud.add_child(toolbar)

	camera_rig.bounds = Rect2(grid.to_global(Vector3(area.position.x, 0, area.position.y)).x,
			grid.to_global(Vector3(area.position.x, 0, area.position.y)).z, area.size.x, area.size.y)
	camera_rig.max_distance = maxf(camera_rig.max_distance, area.size.x * 0.55)
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
	if attract:
		hud.visible = false
	else:
		Toasts.post("Welcome to " + title, ("A field by the road to build on." if start == AirportNewGame.Start.EMPTY
				else "The shed: a little terminal to try the build tools in. Z shows landside and airside; red doors are gaps in the line.")
				+ "\nPress F1 for the controls.", 8.0)


func _add_hud() -> void:
	hud.add_child(status)
	view_bar.building = building
	view_bar.controller = controller
	view_bar.day_night = day_night
	view_bar.help_pressed.connect(func() -> void: help_card.visible = not help_card.visible)
	view_bar.debug_pressed.connect(func() -> void: debug_overlay.visible = not debug_overlay.visible)
	view_bar.menu_pressed.connect(func() -> void: pause_menu.open())
	debug_overlay.visibility_changed.connect(func() -> void: view_bar.show_debug(debug_overlay.visible))
	hud.add_child(view_bar)
	clock_bar.clock = clock
	clock_bar.ledger = ledger
	clock_bar.warnings = func() -> Array:
		var gaps := sides.all_gaps().size()
		if gaps == 0:
			return []
		return ["%d %s between landside and airside with no checkpoint. Press Z to see %s in red." % [gaps,
				"door crosses the line" if gaps == 1 else "doors cross the line", "it" if gaps == 1 else "them"]]
	hud.add_child(clock_bar)
	help_card.sections = AirportHelp.SECTIONS
	hud.add_child(help_card)
	var readout := CursorReadout.new()
	readout.controller = controller
	hud.add_child(readout)
	pause_menu.clock = clock
	pause_menu.subtitle = title
	pause_menu.add_button("Controls", func() -> void:
		pause_menu.close()
		help_card.show())
	pause_menu.add_gap()
	pause_menu.add_button("Quit to title", func() -> void: get_tree().change_scene_to_file(TITLE_SCENE))
	pause_menu.add_button("Quit to desktop", func() -> void: get_tree().quit(), &"DangerButton")
	hud.add_child(pause_menu)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("level_up"):
		building.active += 1
	elif event.is_action_pressed("level_down"):
		building.active -= 1
	elif event.is_action_pressed("time_pause"):
		clock.toggle_pause()
	elif event.is_action_pressed("time_faster"):
		clock.speed_index += 1
	elif event.is_action_pressed("time_slower"):
		if not clock.paused():
			clock.speed_index = maxi(clock.speed_index - 1, 1)
	elif event.is_action_pressed("build_cancel"):
		pause_menu.open()
	else:
		return
	get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	var camera := get_viewport().get_camera_3d()
	if camera != null and controller.wall_view == BuildController.WallView.CUTAWAY:
		var look := -camera.global_transform.basis.z
		controller.view.cut_direction = Vector2(look.x, look.z)
	var count := "%d people" % people.people.size()
	if status.item_text(&"people") != count:
		status.set_item(&"people", count, &"SubtleLabel")


func _setup_view(level_view: BuildingView, level: int) -> void:
	level_view.room_types = AirportCatalogue.ROOM_TYPES
	level_view.door_model = AirportCatalogue.DOOR_MODEL
	level_view.level = level


func _add_level_view(level: int, level_map: BuildingMap) -> void:
	var level_view := BuildingView.new()
	level_view.name = "BuildingView%d" % level
	level_view.grid = grid
	level_view.terrain = terrain
	_setup_view(level_view, level)
	level_view.visible = building == null or level <= building.active
	grid.add_child(level_view)
	level_view.map = level_map
	views[level] = level_view
	if building.levels.has(level + 1):
		level_view.above = building.levels[level + 1]
	if views.has(level - 1):
		views[level - 1].above = level_map
	_apply_wall_view()


func _on_level_changed(level: int) -> void:
	var above_ground := level >= 0
	for node: Node3D in [terrain, water, foliage, path_view]:
		node.visible = above_ground
	controller.view = views[level]
	belt_view.highest_level = level
	_apply_wall_view()
	debug_overlay.map = building.current()
	camera_rig.pick_height = NAN if level == 0 else _level_height(level)
	_on_cell_hovered(cursor.hovered_cell)


## As the prison's: levels below the one being built on have their walls up
## and roofs on; the level being built on takes the Tab view.
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
		v.show_void_roof = n + 1 < level or mode == BuildController.WallView.ROOFS


func capture_world() -> Dictionary:
	return {
		"building": building.to_data(),
		"terrain": terrain.to_data(),
		"water": water.to_data(),
		"foliage": foliage.to_data(),
		"paths": paths.to_data(),
	}


func restore_world(state: Dictionary) -> void:
	terrain.load_data(state.get("terrain", {}))
	water.load_data(state.get("water", {}))
	foliage.load_data(state.get("foliage", {}), func(id: StringName) -> FoliageDef:
		for def in AirportCatalogue.PLANTS:
			if def.id == id:
				return def
		return null)
	paths.load_data(state.get("paths", {}))
	building.load_data(state.get("building", {}), AirportCatalogue.object)


func _level_height(level: int) -> float:
	var centre := building.ground().land_bounds().get_center()
	var floors := building.level(level).floor_heights.values()
	if not floors.is_empty():
		return floors.reduce(func(a: float, b: float) -> float: return a + b) / floors.size()
	return building.storey_height(level, centre, terrain.cell_height(centre))


func _floor_level_at(cell: Vector2i) -> float:
	var level_map := building.current()
	if level_map.has_floor(cell):
		return level_map.floor_height(cell)
	if building.active == 0:
		return terrain.cell_height(cell)
	return building.storey_height(building.active, cell, terrain.cell_height(cell))


func _on_cell_hovered(cell: Vector2i) -> void:
	var room := building.current().room_at(cell) if cell != GridCursor.NO_CELL else null
	if room == null:
		status.set_item(&"room", "No room here" if cell != GridCursor.NO_CELL else "Off the map", &"SubtleLabel")
		return
	var def := AirportCatalogue.room_type(room.type)
	var side := sides.side_of(room)
	status.set_item(&"room", "%s  ·  %d tiles  ·  %s%s%s" % [
		def.display_name if def != null else "Unmarked room",
		room.cells.size(),
		"indoors" if room.indoor else "outdoors",
		("  ·  " + side.capitalize()) if not side.is_empty() else "",
		"  ·  double height" if building.is_double_height(building.active, cell) else ""])
