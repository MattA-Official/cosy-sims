extends Node3D
## The prison sandbox: a grid you can build on, with a sample prison to
## start from (see SamplePrisons) and prisoners living out the day on its
## timetable.

## Off starts on empty land.
@export var build_sample_layout := true
## Which sample prison to start with. The F3 inspector can switch to another.
@export_enum("Starter block", "Two storeys", "Hillside", "Island", "Long way round", "Basement",
		"Crowded canteen", "Locked out", "Staff wing", "Working prison", "Guarded prison",
		"Paying prison") var sample := 0
## Split levels: floors nudged within their storey, and ramps between
## them. Off keeps every floor a whole storey above the one below.
@export var split_levels := false
## Door steps: a door between floors up to a metre apart gets a few steps
## on the low side. Off refuses doors between floors more than a step apart.
@export var door_steps := false
## Staff cars: staff with a car park by the road drive in and park. Off,
## staff come on the staff bus, and car park floor isn't in the build menu.
@export var staff_cars := false

const LORRY := preload("res://games/prison/art/models/lorry.glb")
## The bus's front is towards +X.
const BUS := preload("res://games/prison/art/models/bus.glb")
## The mouth faces +Z, with its bank behind.
const TUNNEL := preload("res://games/prison/art/models/tunnel_portal.glb")
const CARS: Array[PackedScene] = [preload("res://games/prison/art/models/car_red.glb"),
		preload("res://games/prison/art/models/car_blue.glb"), preload("res://games/prison/art/models/car_cream.glb")]
## Game minutes the lorry waits before driving off.
const LORRY_STAY := 30.0
## Tiles between the edge of the land and the side of the generated road.
const ROAD_VERGE := 0.5
## Game minutes between cars passing through, at random in this range.
const PASSING_CARS := Vector2(20.0, 90.0)
## Spots on the edge of the land tried for the staff entrance, nearest
## first.
const ENTRANCE_TRIES := 60
## The hour the game saves itself each day.
const AUTOSAVE_HOUR := 6
const TITLE_SCENE := "res://games/prison/title.tscn"
## The key for each page of the management book.
const BOOK_KEYS: Dictionary[StringName, StringName] = {&"timetable": &"timetable_toggle",
		&"staff": &"staff_toggle", &"money": &"money_toggle", &"office": &"office_toggle", &"heads": &"heads_toggle", &"in_tray": &"in_tray_toggle",
		&"security": &"security_toggle", &"programmes": &"programmes_toggle"}

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
## The roads among the paths, and the vehicles on them.
var roads := Roads.new()
var vehicles := Vehicles.new()
var car_park := CarPark.new()
var staff_bus := StaffBus.new()
var tunnels := Tunnels.new()
var _passing_wait := 0.0
var _rng := RandomNumberGenerator.new()
var people := People.new()
## Every item about the place, and the work to be done with them.
var items := ItemStore.new()
var jobs := JobBoard.new()
var item_view := ItemView.new()
var kitchen := Kitchen.new()
var cleaning := Cleaning.new()
var laundry := Laundry.new()
var workshop := Workshop.new()
## Guard posts and gates, patrols, and walking prisoners back.
var guarding := Guarding.new()
## Loops drawn for guards to walk.
var routes := PatrolRoutes.new()
## Objects wearing out, and jobs to mend them.
var wear := Wear.new()
## Unhappy prisoners acting up.
var misconduct := Misconduct.new()
## Ground inside the perimeter fence.
var secure_area := SecureArea.new()
## Prisoners making a run for it.
var escapes := Escapes.new()
## What happens after an offence.
var consequences := Consequences.new()
## Fights, and mending afterwards.
var fights := Fights.new()
var infirmary := Infirmary.new()
## Things prisoners shouldn't have, and guards searching for them.
var contraband := Contraband.new()
var searching := Searching.new()
var security := Security.new()
var sit_ins := SitIns.new()
var coverage_tint := CoverageTint.new()
## Staff coming and going on day and night shifts.
var shifts := Shifts.new()
## Staff by name: who's hired, from which applicants.
var roster := StaffRoster.new()
## The prison's money, and what comes in and goes out.
var ledger := Ledger.new()
var build_costs := BuildCosts.new()
var build_feel := BuildFeel.new()
var blueprints := Blueprints.new()
var finances := Finances.new()
## New prisoners arriving on the morning bus.
var intake := Intake.new()
## The warden's office.
var office := Office.new()
## Each desk worker's pile of paper.
var desk_work := DeskWork.new()
## Bonuses, such as department heads'.
var modifiers := Modifiers.new()
var training := Training.new()
var suggestions := Suggestions.new()
var rounds := Rounds.new()
## Department heads, hired from the warden's desk.
var heads := Heads.new()
## Request cards for the warden, and what their answers do.
var in_tray := InTray.new()
var prison_tray := PrisonTray.new()
## Arrivals who come without their paperwork.
var missing_files := MissingFiles.new()
## Desks people have claimed.
var claims := Claims.new()
## The grade, grant goals and the daily report.
var standing := Standing.new()
## Sentences and prisoner files, and how far each prisoner has come.
var sentences := Sentences.new()
var reform := Reform.new()
var courses := Courses.new()
var parole := Parole.new()
## Going home, postcards and those who come back.
var release := Release.new()
## Tunnels and fence cuts.
var escape_plans := EscapePlans.new()
## The week's forecast, contracts and loans.
var budget := Budget.new()
var programmes_window := ProgrammesWindow.new()
## Difficulty and sentence length, on F4.
var settings_window := SettingsWindow.new()
var fail_card := FailCard.new()
## Ctrl+Z and Ctrl+Y for building and landscaping.
var undo := UndoHistory.new()
var land_plots := LandPlots.new()
## Open jobs and stock, with the debug view.
var jobs_panel := JobsPanel.new()
## Game time. Everything that happens over time listens to it.
var clock := GameClock.new()
## The prisoners' timetable, a copy of the catalogue's so edits stay in
## this game.
var schedule: Schedule = PrisonCatalogue.SCHEDULE.copy()
## Puts everyone in their timetable block and locks cell doors.
var runner := ScheduleRunner.new()
var regime := Regime.new()
var day_night := DayNight.new()
var door_lights := DoorLights.new()
## Tints rooms by who may be in them while the zones tool is open.
var zone_tints := ZoneTints.new()
## The day, time, block and speed, top left.
var clock_bar := ClockBar.new()
## Painting the timetable, on T.
var timetable := TimetableWindow.new()
## Taking on staff and putting prisoners on work programmes, on P.
var staff_window := StaffWindow.new()
## The balance and the last week's money, on M.
var finance_window := FinanceWindow.new()
## Intake, goals and the grade, on O.
var office_window := OfficeWindow.new()
var security_window := SecurityWindow.new()
## Department heads, on H.
var heads_window := HeadsWindow.new()
## The in-tray, on J.
var in_tray_window := InTrayWindow.new()
## Save slots and the autosave, on F2.
var saves_window := SavesWindow.new()
## The bookmarks down the left and the book they open: every management
## window is a page in it.
var book := ManagementBook.new()
## Esc with nothing to put away: resume, save and load, settings, quit.
var pause_menu := PauseMenu.new()
## Running behind the title screen: no HUD, no notes, no autosave.
var attract := false
## The prison's name in saves: the sample's, or the save's it was loaded from.
var title := "My prison"
## How big the map is: the plots for sale and the ground round them.
var map_size: MapSizeDef
## The F3 inspector for people, objects and rooms.
var inspector := Inspector.new()
## Grid lines at the height of the level being built on, off the ground.
var level_grid := LevelGrid.new()
## Room under the mouse and people, under the view bar.
var status := StatusBar.new()
## Level, wall view, always day, help, debug and menu buttons, top right.
var view_bar := ViewBar.new()
## Every control, on F1.
var help_card := HelpCard.new()
## One BuildingView per level, by level number.
var views: Dictionary[int, BuildingView] = {}


func _ready() -> void:
	if NewGame.pending:
		build_sample_layout = NewGame.start >= 0
		if build_sample_layout:
			SamplePrisons.next = NewGame.start
		staff_cars = NewGame.staff_cars
		split_levels = NewGame.split_levels
		door_steps = NewGame.door_steps
	Building.split_levels = split_levels
	Building.door_steps = door_steps
	CarPark.enabled = staff_cars
	if SamplePrisons.next == SamplePrisons.EMPTY:
		sample = -1
		SamplePrisons.next = -1
	elif SamplePrisons.next >= 0:
		sample = SamplePrisons.next
		SamplePrisons.next = -1
	# The grid is the whole world: the land for sale in plots, with a margin
	# round it fading into fog. You start owning plots in the middle.
	map_size = _choose_map_size()
	grid.size = Vector2i.ONE * map_size.tiles(LandPlots.SIZE)
	terrain.size = grid.size
	var land := map_size.start(LandPlots.SIZE)
	building = Building.new(land, PrisonCatalogue.FLOORS, PrisonCatalogue.WALLS)
	map = building.ground()
	view.room_types = PrisonCatalogue.ROOM_TYPES
	view.door_model = PrisonCatalogue.DOOR_MODEL
	view.door_models = PrisonCatalogue.door_models()
	view.dress_model = _dress_model
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
	roads.paths = paths
	roads.bounds = map.land_bounds()
	building.changed.connect(func() -> void: roads.bounds = map.land_bounds())
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
	for def in PrisonCatalogue.PRIVILEGES:
		people.privileges[def.id] = def
	for def in PrisonCatalogue.ACTIVITIES:
		people.activities[def.id] = def
	people.access = PrisonCatalogue.access()
	people.categories = PrisonCatalogue.categories()
	jobs.people = people
	jobs.items = items
	jobs.roles = PrisonCatalogue.roles()
	jobs.programmes = PrisonCatalogue.programmes()
	# A job done on a work programme makes for a useful day.
	jobs.job_finished.connect(func(_job: Job, worker: Person) -> void:
		if worker.programme != &"":
			people.add_moodlet(worker, &"useful_day"))
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
	# Secure ground first, so everything redrawn after a change sees it.
	secure_area.building = building
	building.changed.connect(secure_area.refresh)
	secure_area.refresh()
	zone_tints.secure_area = secure_area
	zone_tints.ground_height = terrain.cell_height
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
	inspector.room_types = PrisonCatalogue.ROOM_TYPES
	inspector.clock = clock
	inspector.runner = runner
	grid.add_child(inspector)
	var site := SamplePrisons.Site.new()
	site.area = map_size.area(LandPlots.SIZE)
	site.building = building
	site.terrain = terrain
	site.water = water
	site.foliage = foliage
	site.paths = paths
	site.people = people
	var saved := PrisonSave.pending
	PrisonSave.pending = {}
	if saved.is_empty():
		SamplePrisons.build(sample if build_sample_layout else -1, site)
		if build_sample_layout and sample >= 0:
			title = SamplePrisons.NAMES[sample]
	else:
		PrisonSave.apply_world(self, saved)
		title = saved.get("title", title)
	if NewGame.pending and NewGame.prison_name != "":
		title = NewGame.prison_name
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
	laundry.name = "Laundry"
	laundry.jobs = jobs
	jobs.rebuilders[&"laundry"] = laundry.rebuild
	jobs.rebuilders[&"make"] = workshop.rebuild
	laundry.items = items
	laundry.building = building
	laundry.people = people
	laundry.clock = clock
	add_child(laundry)
	laundry.start()
	workshop.name = "Workshop"
	workshop.items = items
	workshop.building = building
	workshop.jobs = jobs
	workshop.clock = clock
	add_child(workshop)
	workshop.look()
	shifts.name = "Shifts"
	shifts.people = people
	shifts.roles = PrisonCatalogue.all_roles()
	shifts.shifts = PrisonCatalogue.SHIFTS
	shifts.start_spot = _staff_spot
	shifts.clock = clock
	add_child(shifts)
	roster.name = "StaffRoster"
	roster.people = people
	roster.roles = PrisonCatalogue.all_roles()
	roster.work_trait_pool = PrisonStaffTraits.all()
	roster.work_trait_counts[&"warden"] = 2
	roster.modifiers = modifiers
	roster.shifts = PrisonCatalogue.SHIFTS
	roster.trait_pool.assign(PrisonCatalogue.TRAITS.filter(func(t: TraitDef) -> bool: return t.id != &"light_fingered"))
	roster.clock = clock
	add_child(roster)
	if saved.has("staff"):
		roster.restore(saved["staff"])
	shifts.roster = roster
	roster.start()
	_set_entrance()
	if saved.is_empty():
		_lay_road()
	vehicles.name = "Vehicles"
	vehicles.roads = roads
	vehicles.cell_size = grid.cell_size
	vehicles.ground_at = func(tile: Vector2) -> float: return terrain.height_at(tile)
	vehicles.clock = clock
	vehicles.front_turns[BUS] = -PI * 0.5
	# Out of sight once inside a tunnel.
	vehicles.shown_at = func(tile: Vector2) -> bool: return Rect2(map.land_bounds()).grow(0.25).has_point(tile)
	grid.add_child(vehicles)
	tunnels.name = "Tunnels"
	tunnels.cell_size = grid.cell_size
	tunnels.ground_at = func(tile: Vector2) -> float: return terrain.height_at(tile)
	tunnels.model = TUNNEL
	tunnels.roads = roads
	grid.add_child(tunnels)
	_passing_wait = _rng.randf_range(PASSING_CARS.x, PASSING_CARS.y)
	clock.advanced.connect(_pass_through)
	car_park.name = "CarPark"
	car_park.building = building
	car_park.vehicles = vehicles
	car_park.roads = roads
	car_park.shifts = shifts
	car_park.cars = CARS
	add_child(car_park)
	if CarPark.enabled:
		car_park.start()
	# A loaded prison wants the staff it had, so nobody is sent home.
	var saved_wanted: Dictionary = saved.get("wanted", {})
	for role: StringName in saved_wanted:
		for shift: StringName in saved_wanted[role]:
			shifts.set_wanted(role, shift, saved_wanted[role][shift], false)
	shifts.start()
	if CarPark.enabled:
		car_park.park_staff_here()
	for role: StringName in site.night_staff:
		shifts.set_wanted(role, &"night", site.night_staff[role], false)
	guarding.name = "Guarding"
	guarding.people = people
	guarding.jobs = jobs
	jobs.rebuilders[&"escort"] = guarding.rebuild
	guarding.building = building
	guarding.clock = clock
	routes.name = "PatrolRoutes"
	routes.controller = controller
	routes.debug_overlay = debug_overlay
	routes.cell_size = grid.cell_size
	routes.height_at = func(level: int, point: Vector2) -> float: return people.nav().height_at(level, point)
	grid.add_child(routes)
	guarding.routes = routes
	add_child(guarding)
	runner.other_locks = guarding.gate_locks
	runner.refresh()
	wear.name = "Wear"
	wear.cell_size = grid.cell_size
	wear.people = people
	wear.jobs = jobs
	wear.building = building
	grid.add_child(wear)
	misconduct.name = "Misconduct"
	misconduct.people = people
	misconduct.model = MisconductModel.new()
	misconduct.rungs.assign(PrisonCatalogue.MISCONDUCT)
	misconduct.wear = wear
	misconduct.fights = fights
	misconduct.items = items
	misconduct.clock = clock
	add_child(misconduct)
	misconduct.start()
	fights.name = "Fights"
	fights.people = people
	fights.jobs = jobs
	fights.cell_size = grid.cell_size
	fights.height_at = func(level: int, point: Vector2) -> float: return people.nav().height_at(level, point)
	fights.clock = clock
	grid.add_child(fights)
	fights.start()
	fights.started.connect(func(fight: Fights.Fight) -> void:
		var map: BuildingMap = building.levels.get(fight.level)
		var room := map.room_at_point(fight.centre) if map != null else null
		var type := people.room_type(room.type) if room != null else null
		Toasts.post("Fight!", "A fight broke out%s. A guard is on the way." % (
				" in the %s" % type.display_name.to_lower() if type != null else "")))
	infirmary.name = "Infirmary"
	infirmary.people = people
	infirmary.jobs = jobs
	infirmary.clock = clock
	add_child(infirmary)
	infirmary.start()
	consequences.name = "Consequences"
	consequences.people = people
	consequences.guarding = guarding
	consequences.clock = clock
	add_child(consequences)
	consequences.start()
	consequences.punished.connect(func(person: Person, words: String) -> void:
		Toasts.post(person.name, words[0].to_upper() + words.substr(1) + "."))
	inspector.person_actions.append(["Send to the quiet room", "A guard walks them to a free quiet room for a day.",
			func(person: Person) -> void:
				if not consequences.send_to_quiet_room(person):
					Toasts.post("No quiet room free", "Build a small room with a bed and a toilet and mark it a quiet room."),
			func(person: Person) -> bool: return person.group == &"prisoner" and person.quiet_room_hours <= 0.0])
	inspector.person_actions.append(["Let them off", "Gives back lost privileges and lets them out of the quiet room.",
			consequences.let_off,
			func(person: Person) -> bool: return not person.restrictions.is_empty() or person.quiet_room_hours > 0.0])
	escapes.name = "Escapes"
	escapes.people = people
	escapes.jobs = jobs
	escapes.secure_area = secure_area
	escapes.ledger = ledger
	escapes.clock = clock
	add_child(escapes)
	escapes.start()
	escapes.running.connect(func(person: Person) -> void:
		Toasts.post("Escape!", "%s is making a run for it. The nearest guards are giving chase." % person.name))
	escapes.caught.connect(func(person: Person, by: Person) -> void:
		Toasts.post("Caught", "%s caught %s." % [by.name, person.name]))
	escapes.got_away.connect(func(person: Person) -> void:
		Toasts.post("Got away", "%s escaped. The prison is fined %s." % [person.name, Ledger.text(Escapes.FINE)]))
	contraband.name = "Contraband"
	contraband.people = people
	contraband.items = items
	contraband.misconduct = misconduct
	contraband.catalogue.assign(PrisonCatalogue.CONTRABAND)
	contraband.clock = clock
	add_child(contraband)
	contraband.start()
	searching.name = "Searching"
	searching.people = people
	searching.jobs = jobs
	searching.items = items
	searching.clock = clock
	add_child(searching)
	searching.start()
	var is_prisoner := func(person: Person) -> bool: return person.group == &"prisoner"
	inspector.person_actions.append(["Search them", "A guard stops them and pats them down. "
			+ "Being searched puts people out.", searching.search_person, is_prisoner])
	inspector.person_actions.append(["Search their cell", "A guard turns over the room they sleep in.",
			func(person: Person) -> void:
				var home := people.home_room(person)
				if not home.is_empty():
					searching.search_cell(home[0], home[1]),
			func(person: Person) -> bool: return is_prisoner.call(person) and not people.home_room(person).is_empty()])
	searching.found.connect(func(_owner: Person, def: ItemDef, where: String) -> void:
		Toasts.post("Contraband found", "A %s %s." % [def.display_name.to_lower(), where]))
	security.name = "Security"
	security.people = people
	security.jobs = jobs
	security.building = building
	security.clock = clock
	add_child(security)
	security.start()
	misconduct.security = security
	misconduct.acted.connect(func(person: Person, rung: MisconductDef, words: String) -> void:
		if rung.id == &"vandalism" or rung.id == &"fight":
			security.count(rung.id, person, words))
	searching.found.connect(func(owner: Person, def: ItemDef, where: String) -> void:
		security.count(&"contraband", owner, "A %s %s" % [def.display_name.to_lower(), where]))
	fights.knocked_out.connect(func(person: Person) -> void:
		security.count(&"knocked_out", person, "Knocked out in a fight"))
	escapes.running.connect(func(person: Person) -> void:
		security.count(&"escape", person, "Making a run for it"))
	sit_ins.name = "SitIns"
	sit_ins.people = people
	sit_ins.jobs = jobs
	sit_ins.fights = fights
	sit_ins.clock = clock
	add_child(sit_ins)
	sit_ins.start()
	var room_name := func(sit_in: SitIns.SitIn) -> String:
		var type := people.room_type(sit_in.room.type)
		return type.display_name.to_lower() if type != null else "room"
	sit_ins.started.connect(func(sit_in: SitIns.SitIn) -> void:
		var words := SitIns.words(sit_in, room_name.call(sit_in))
		Toasts.post("Sit-in!", "%s. To end it, %s, or send someone to talk them round (Security window, K)." % [words, sit_in.hint])
		security.count(&"sit_in", null, "", true)
		security.alert_at(words, sit_in.level, sit_in.room.centre()))
	sit_ins.ended.connect(func(sit_in: SitIns.SitIn, how: String) -> void:
		var endings := {"fixed": "They've stood up: whatever it was is sorted.",
				"talked": "They've been talked round and gone back to the timetable.",
				"boiled": "Nobody came, and it's ended in a scrap.",
				"fizzled": "It's fizzled out."}
		Toasts.post("Sit-in over", endings.get(how, "")))
	clock.hour_changed.connect(func(_hour: int) -> void:
		for sit_in in sit_ins.sit_ins:
			if sit_in.minutes >= 1.0:
				security.count(&"sit_in", null, "", true))
	inspector.person_actions.append(["Talk them round", "Sends a guard, or the warden, to hear them out and end the sit-in.",
			func(person: Person) -> void:
				var sit_in := sit_ins.sit_in_of(person)
				if sit_in != null:
					sit_ins.negotiate(sit_in),
			func(person: Person) -> bool: return person.sitting])
	contraband.tool_missing.connect(func(level: int, room: Room, def: ItemDef) -> void:
		var type := people.room_type(room.type)
		var words := "A %s is missing from the %s" % [def.display_name.to_lower(),
				type.display_name.to_lower() if type != null else "room"]
		security.count(&"missing_tool", null, "", true)
		security.alert_at(words, level, room.centre())
		Toasts.post("Tool missing", words + ". A search might turn it up."))
	contraband.detected.connect(func(person: Person, def: ItemDef) -> void:
		security.count(&"metal_detector", person, "Set off the metal detector")
		searching.search_person(person))
	searching.shakedown_started.connect(func(cells: int) -> void:
		Toasts.post("Shakedown", "Guards are turning over %d cells. Nobody's happy about it." % cells))
	infirmary.died.connect(func(person: Person, level: int, point: Vector2) -> void:
		security.count(&"death", null, "", true)
		security.alert_at("%s died" % person.name, level, point)
		Toasts.post("A death", "%s didn't make it. A plaque marks the spot." % person.name)
		_ghost(level, point)
		var map: BuildingMap = building.levels.get(level)
		if map != null:
			map.place_object_at(PrisonCatalogue.object(&"memorial_plaque"), point, 0.0))
	coverage_tint.name = "CoverageTint"
	coverage_tint.cell_size = grid.cell_size
	coverage_tint.coverage = security.coverage
	coverage_tint.building = building
	coverage_tint.controller = controller
	coverage_tint.height_at = func(level: int, cell: Vector2i) -> float:
		return people.nav().height_at(level, Vector2(cell) + Vector2(0.5, 0.5))
	grid.add_child(coverage_tint)
	ledger.name = "Ledger"
	ledger.balance = Finances.STARTING_MONEY
	add_child(ledger)
	build_costs.name = "BuildCosts"
	build_costs.building = building
	build_costs.ledger = ledger
	build_costs.door_kinds = people.access.door_kinds
	add_child(build_costs)
	# Blueprints watch the building before costs do, so what becomes a plan
	# isn't charged until a handyman starts on it.
	blueprints.name = "Blueprints"
	blueprints.building = building
	blueprints.terrain = terrain
	blueprints.jobs = jobs
	blueprints.ledger = ledger
	blueprints.build_costs = build_costs
	blueprints.cell_size = grid.cell_size
	# A new game builds over time unless it's a sandbox; prisons opened
	# straight from a sample (for trying things out) build at once.
	blueprints.instant = not NewGame.pending or Standing.next_difficulty == &"sandbox"
	blueprints.active = func() -> bool:
		return controller.tool != BuildController.Tool.NONE and not undo.restoring()
	add_child(blueprints)
	blueprints.start()
	build_costs.start()
	controller.blueprints = blueprints
	controller.spending_allowed = ledger.can_spend
	controller.build_costs = build_costs
	controller.find_object = PrisonCatalogue.object
	controller.templates = TemplateStore.new()
	controller.templates.find_object = PrisonCatalogue.object
	controller.templates.starters = StarterTemplates.build()
	controller.drop_refused.connect(func(reason: String) -> void:
		Toasts.post("Can't put it there", reason))
	controller.copied.connect(func(what: String) -> void:
		Toasts.post("Copied", "Ctrl+V to put down a copy of the %s. Each copy costs the full price." % what))
	controller.balance = func() -> int: return 1 << 30 if ledger.sandbox else ledger.balance
	land_plots.building = building
	land_plots.terrain = terrain
	land_plots.water = water
	land_plots.ledger = ledger
	land_plots.paths = paths
	land_plots.clock = clock
	land_plots.area = map_size.area(LandPlots.SIZE)
	if map_size.margin > 0:
		var area_rect := Rect2(land_plots.area)
		(terrain.ground_material as ShaderMaterial).set_shader_parameter("fog_rect",
				Vector4(area_rect.position.x, area_rect.position.y, area_rect.size.x, area_rect.size.y) * grid.cell_size)
	for key: Vector2i in saved.get("land_paid", {}):
		land_plots.paid[key] = saved["land_paid"][key]
	controller.land_plots = land_plots
	for refused: Signal in [controller.land_refused, controller.spending_refused, controller.drop_refused]:
		refused.connect(func(_why := "") -> void: Sound.play(&"build_error"))
	controller.land_refused.connect(func() -> void:
		Toasts.post("Not enough money", "That plot costs more than you have."))
	controller.spending_refused.connect(func() -> void:
		Toasts.post("Out of money", "Building is paused until the balance is back above zero. "
				+ "Demolishing still gives some money back."))
	finances.name = "Finances"
	finances.ledger = ledger
	finances.people = people
	finances.shifts = shifts
	for role in PrisonCatalogue.all_roles():
		finances.roles[role.id] = role
	finances.categories = PrisonCatalogue.categories()
	finances.kitchen = kitchen
	finances.workshop = workshop
	finances.clock = clock
	add_child(finances)
	claims.name = "Claims"
	claims.people = people
	claims.building = building
	claims.roles = PrisonCatalogue.roles()
	add_child(claims)
	office.name = "Office"
	office.claims = claims
	office.people = people
	office.jobs = jobs
	office.building = building
	office.shifts = shifts
	office.clock = clock
	office.roster = roster
	office.desk_work = desk_work
	add_child(office)
	claims.extra_dressing = office.pile_dressing
	training.name = "Training"
	training.people = people
	training.jobs = jobs
	training.building = building
	training.roster = roster
	training.clock = clock
	add_child(training)
	desk_work.name = "DeskWork"
	add_child(desk_work)
	modifiers.name = "Modifiers"
	add_child(modifiers)
	heads.name = "Heads"
	heads.departments = PrisonDepartments.all()
	heads.roster = roster
	heads.desk_work = desk_work
	heads.modifiers = modifiers
	heads.building = building
	heads.prisoners = func() -> int:
		return people.people.filter(func(p: Person) -> bool: return p.group == &"prisoner").size()
	heads.pay = func(amount: int) -> void: ledger.add(-amount, "Wages")
	heads.clock = clock
	add_child(heads)
	heads.start()
	heads.applicants_ready.connect(func(department: DepartmentDef) -> void:
		var card := in_tray.find(StringName("applicants_%s" % department.id))
		if card != null:
			var words := " or ".join(heads.applicants(department).map(func(a: StaffRoster.Record) -> String:
				return "%s (%s)" % [a.name, roster.work_trait_words(a)] if not a.work_traits.is_empty() else a.name))
			in_tray.post_about(card, 0, words)
		if not attract:
			Toasts.post("Applicants for %s" % department.head_role.display_name,
					"The hire card is done: pick one in the in-tray (J) or on the Heads page (H)."))
	for system: Object in [people, searching, infirmary, courses, workshop, finances]:
		system.set(&"modifiers", modifiers)
	jobs.job_finished.connect(roster.job_done)
	for def in PrisonTray.moodlets():
		people.moodlet_defs[def.id] = def
	prison_tray.name = "PrisonTray"
	prison_tray.people = people
	prison_tray.ledger = ledger
	prison_tray.roster = roster
	prison_tray.desk_work = desk_work
	prison_tray.heads = heads
	prison_tray.clock = clock
	add_child(prison_tray)
	in_tray.name = "InTray"
	in_tray.defs = PrisonTray.cards()
	in_tray.defs.append(PrisonTray.resignation())
	in_tray.defs.append(PrisonTray.review())
	for department in heads.departments:
		in_tray.defs.append(PrisonTray.applicants(department))
	in_tray.desk_work = desk_work
	in_tray.prisoners = heads.prisoners
	in_tray.has_clerk = func() -> bool: return roster.records.any(func(r: StaffRoster.Record) -> bool:
			return Office.CLERKS.has(r.role))
	in_tray.pick_subject = prison_tray.pick_subject
	in_tray.apply = prison_tray.apply
	in_tray.cost_of = PrisonTray.cost
	in_tray.clock = clock
	add_child(in_tray)
	in_tray.start()
	suggestions.name = "Suggestions"
	suggestions.building = building
	suggestions.people = people
	suggestions.roster = roster
	suggestions.prisoners = heads.prisoners
	suggestions.clock = clock
	add_child(suggestions)
	suggestions.start()
	people.moodlet_defs[Rounds.MOODLET] = Rounds.moodlet()
	rounds.name = "Rounds"
	rounds.people = people
	rounds.jobs = jobs
	rounds.building = building
	rounds.clock = clock
	add_child(rounds)
	for idea in suggestions.ideas:
		in_tray.defs.append(PrisonTray.suggestion(idea))
	suggestions.suggested.connect(func(idea: Dictionary, record: StaffRoster.Record) -> void:
		var card := in_tray.find(StringName("suggest_%s" % idea["id"]))
		if in_tray.cap() > 0 and card != null:
			in_tray.post_about(card, record.id, prison_tray.staff_words(record))
		if not attract:
			Toasts.post("Suggestions box: %s" % idea["title"], "%s: \"%s\"" % [prison_tray.staff_words(record), idea["words"]]))
	suggestions.taken_up.connect(func(idea: Dictionary, record: StaffRoster.Record) -> void:
		in_tray.note("%s is chuffed you took up their idea: %s." % [record.first_name(), String(idea["title"]).to_lower()])
		if not attract:
			Toasts.post("A good idea", "%s is chuffed you took up their idea: %s." % [prison_tray.staff_words(record), String(idea["title"]).to_lower()]))
	roster.resign = func(record: StaffRoster.Record) -> void:
		in_tray.post_about(in_tray.find(&"resignation"), record.id, prison_tray.staff_words(record))
		if not attract:
			Toasts.post("A resignation letter", "%s wants to leave. Answer in the in-tray (J)." % record.name)
	roster.charge = func(amount: int, line: String) -> void: ledger.add(-amount, line)
	roster.unhappy.connect(func(record: StaffRoster.Record) -> void:
		var role := shifts.role_def(record.role)
		if record.role != &"warden" and (role == null or not role.by_card):
			return
		in_tray.post_about(in_tray.find(&"annual_review"), record.id, prison_tray.staff_words(record))
		if not attract:
			Toasts.post("An annual review", "%s is unhappy and may leave. See the in-tray (J)." % record.name))
	missing_files.name = "MissingFiles"
	missing_files.building = building
	missing_files.desk_work = desk_work
	missing_files.heads = heads
	missing_files.people = people
	missing_files.has_clerk = in_tray.has_clerk
	missing_files.intake = intake
	add_child(missing_files)
	missing_files.start()
	in_tray.answered.connect(func(card: InTray.Card, choice: TrayChoiceDef, by: StringName) -> void:
		var words := PrisonTray.why(card, choice)
		in_tray.note(words + (" (lapsed)" if by == &"lapsed" else " (clerk)" if by == &"clerk" else ""))
		if by == &"lapsed" and not attract:
			Toasts.post("In-tray: %s" % card.def.title, "Nobody answered, so: %s" % choice.label.get_slice(" (", 0).to_lower()))
	people.pace_scales.append(roster.pace)
	fights.skilled = roster.skilled
	cleaning.skilled = roster.skilled
	wear.skilled = roster.skilled
	kitchen.modifiers = modifiers
	intake.name = "Intake"
	intake.people = people
	intake.building = building
	intake.ledger = ledger
	intake.guarding = guarding
	intake.categories = PrisonCatalogue.CATEGORIES
	intake.entrance = shifts.entrance
	intake.has_warden = office.has_warden
	intake.vehicles = vehicles
	intake.bus_model = BUS
	intake.clock = clock
	add_child(intake)
	intake.start()
	if not CarPark.enabled:
		staff_bus.name = "StaffBus"
		staff_bus.vehicles = vehicles
		staff_bus.intake = intake
		staff_bus.shifts = shifts
		staff_bus.bus_model = BUS
		staff_bus.clock = clock
		add_child(staff_bus)
		staff_bus.start()
	standing.name = "Standing"
	standing.people = people
	standing.security = security
	standing.ledger = ledger
	standing.office = office
	standing.intake = intake
	standing.finances = finances
	standing.building = building
	standing.workshop = workshop
	standing.clock = clock
	add_child(standing)
	standing.start()
	reform.name = "Reform"
	reform.people = people
	reform.jobs = jobs
	reform.progress = PrisonCatalogue.reform_progress()
	reform.clock = clock
	add_child(reform)
	reform.start()
	sentences.name = "Sentences"
	sentences.people = people
	sentences.intake = intake
	sentences.categories = PrisonCatalogue.categories()
	sentences.reform = reform.progress
	sentences.clock = clock
	add_child(sentences)
	sentences.start()
	if NewGame.pending:
		sentences.length = NewGame.sentence_length
	courses.name = "Courses"
	courses.people = people
	courses.jobs = jobs
	courses.building = building
	courses.runner = runner
	courses.reform = reform.progress
	courses.defs = PrisonCatalogue.COURSES
	courses.clock = clock
	add_child(courses)
	courses.places.assign(site.course_places)
	regime.name = "Regime"
	regime.operations = PrisonRegime.operations()
	regime.sessions = PrisonRegime.sessions(PrisonCatalogue.COURSES)
	regime.on_duty = func(role: StringName, slot: int) -> bool:
		for shift in shifts.shifts:
			if shift.is_on(slot * Schedule.SLOT_MINUTES) and shifts.wanted_for(role, shift.id) > 0:
				return true
		return false
	regime.rooms = func(type: StringName) -> int:
		var count := 0
		for n: int in building.levels:
			for room: Room in building.levels[n].rooms():
				if room.type == type:
					count += 1
		return count
	regime.schedules = func() -> Dictionary: return runner.schedules
	regime.rota = _rota_rows
	regime.clock = clock
	regime.schedule = schedule
	add_child(regime)
	regime.start()
	courses.regime = regime
	regime.operation_due.connect(_on_operation)
	for system: Object in [kitchen, cleaning, workshop, budget, release, intake, parole, contraband, searching]:
		system.set(&"regime", regime)
	misconduct.temper_scales.append(courses.calm_scale)
	inspector.person_pickers.append(["Course", "Put them on a course now, or take them off one.",
		func(_person: Person) -> Array:
			var out: Array = [[&"", "None"]]
			for def in courses.defs:
				out.append([def.id, def.display_name])
			return out,
		func(person: Person) -> StringName: return person.profile.get("course", &""),
		func(person: Person, id: StringName) -> void:
			if id == &"":
				courses.leave(person)
			else:
				courses.enrol(person, id)
				courses.places[id] = maxi(courses.places.get(id, 0), courses.enrolled(id).size()),
		func(person: Person) -> bool: return person.group == &"prisoner"])
	courses.passed.connect(func(person: Person, def: CourseDef) -> void:
		Toasts.post("Course passed", "%s passed %s." % [person.name, def.display_name]))
	parole.name = "Parole"
	parole.people = people
	parole.office = office
	parole.jobs = jobs
	parole.reform = reform
	parole.clock = clock
	add_child(parole)
	parole.heard.connect(func(person: Person, granted: bool) -> void:
		Toasts.post("Parole granted" if granted else "Parole refused", "%s %s." % [person.name,
				"goes home tomorrow" if granted else "can try again in %d days" % Parole.RETRY_DAYS]))
	release.name = "Release"
	release.people = people
	release.building = building
	release.ledger = ledger
	release.intake = intake
	release.reform = reform
	release.postcard_defs = PrisonCatalogue.POSTCARDS
	release.clock = clock
	add_child(release)
	intake.leavers = release.waiting_for_bus
	intake.returning = release.returning_today
	intake.on_return = release.bring_back
	release.going.connect(func(count: int) -> void:
		Toasts.post("Going home", "%d %s home today." % [count,
				"prisoner goes" if count == 1 else "prisoners go"]))
	release.returned.connect(func(person: Person, entry: Dictionary) -> void:
		Toasts.post("Back again", "%s is back, %d days after leaving." % [person.name,
				clock.day() - entry.left_day]))
	release.postcard_came.connect(func(card: Dictionary) -> void:
		Toasts.post("A postcard from %s" % card.from, card.text, 10.0)
		for n: int in views:
			views[n].redraw_objects())
	standing.nightly.append(sentences.tick)
	standing.nightly.append(reform.grade_night)
	standing.nightly.append(release.nightly)
	escape_plans.name = "EscapePlans"
	escape_plans.people = people
	escape_plans.secure_area = secure_area
	escape_plans.escapes = escapes
	escape_plans.security = security
	escape_plans.cell_size = grid.cell_size
	escape_plans.height_at = func(level: int, point: Vector2) -> float: return people.nav().height_at(level, point)
	escape_plans.clock = clock
	grid.add_child(escape_plans)
	escape_plans.start()
	standing.nightly.append(escape_plans.nightly)
	searching.room_checks.append(escape_plans.search_room)
	escape_plans.found.connect(func(person: Person, words: String) -> void:
		Toasts.post("Escape plan found", "%s. %s has it on their record now." % [words, person.name]))
	escape_plans.broke_out.connect(func(person: Person, kind: StringName) -> void:
		Toasts.post("Break-out!", "%s came out through %s." % [person.name,
				"a tunnel" if kind == EscapePlans.TUNNEL else "a cut in the fence"]))
	standing.report_lines.append(release.report_lines)
	standing.report_lines.append(rounds.report_lines)
	standing.reform = reform
	standing.release = release
	courses.passed.connect(func(_person: Person, _def: CourseDef) -> void: standing.count(&"courses_passed"))
	parole.heard.connect(func(_person: Person, granted: bool) -> void:
		if granted:
			standing.count(&"parole_granted"))
	release.left.connect(func(entry: Dictionary) -> void:
		if entry.reform >= Reform.REFORMED_LINE:
			standing.count(&"released_reformed"))
	misconduct.temper_scales.append(func(_person: Person) -> float: return standing.difficulty.misconduct_scale)
	standing.longest_sit_in = func() -> float:
		var longest := 0.0
		for sit_in in sit_ins.sit_ins:
			longest = maxf(longest, sit_in.minutes / 60.0)
		return longest
	standing.difficulty_changed.connect(func(_def: DifficultyDef) -> void: _apply_difficulty())
	if saved.is_empty() and not ledger.sandbox:
		ledger.balance = standing.difficulty.starting_money
	budget.name = "Budget"
	budget.ledger = ledger
	budget.finances = finances
	budget.intake = intake
	budget.workshop = workshop
	budget.building = building
	budget.clock = clock
	add_child(budget)
	budget.start()
	budget.contract_done.connect(func(c: Dictionary) -> void:
		Toasts.post("Contract done", "The %d goods for %s are delivered: %s on top." % [c.goods, c.client,
				Ledger.text(c.pay)]))
	budget.contract_missed.connect(func(c: Dictionary) -> void:
		Toasts.post("Contract missed", "%s gave up waiting for their goods." % (c.client as String).capitalize()))
	standing.failed.connect(func(rule: FailRule) -> void:
		if not clock.paused():
			clock.toggle_pause()
		fail_card.show_for(rule.reason, standing.history))
	_apply_difficulty()
	roster.pay = func(amount: int) -> void: ledger.add(-amount, "Wages")
	roster.quit.connect(func(record: StaffRoster.Record) -> void:
		Toasts.post("%s quit" % record.name, "%s, a %s on the %s shift, has handed in their notice." % [
				record.first_name(), shifts.role_def(record.role).display_name.to_lower(), record.shift]))
	inspector.person_lines.append(roster.summary)
	inspector.person_lines.append(office.pile_words)
	# Morale: a staff room helps, an overloaded desk doesn't, and trouble on
	# their shift stays with them a few days.
	roster.morale_parts.append(func(record: StaffRoster.Record) -> Array:
		var out: Array = []
		if desk_work.is_overloaded(record.id):
			out.append([-10.0, "overloaded"])
		var best := -INF
		for n: int in building.levels:
			for room: Room in building.levels[n].rooms():
				if room.type == &"staff_room":
					best = maxf(best, people.quality(n, room).score)
		if best > -INF:
			out.append([5.0 + clampf(best / 2.0, -5.0, 5.0), "a staff room"])
		return out)
	security.counted.connect(func(kind: StringName) -> void:
		if not kind in [&"fight", &"knocked_out", &"escape", &"sit_in", &"death"]:
			return
		for record in roster.records:
			if record.person != null and not record.person.going_home:
				roster.add_event(record, -5.0, 3, "trouble on their shift"))
	inspector.person_lines.append(func(person: Person) -> String:
		return "File: awaiting paperwork, so no parole yet" if MissingFiles.is_missing(person) else "")
	inspector.person_lines.append(func(person: Person) -> String:
		if person.group != &"prisoner":
			return ""
		var file := sentences.summary(person)
		var lines := PackedStringArray([file, reform.summary(person), courses.summary(person), parole.summary(person),
				escape_plans.summary(person)])
		return "\n".join(Array(lines).filter(func(line: String) -> bool: return not line.is_empty())))
	standing.report_ready.connect(func(text: String) -> void: Toasts.post("Daily report", text, 12.0))
	standing.goal_done.connect(func(goal: GoalDef) -> void:
		Toasts.post("Goal done: " + goal.title, "A grant of %s came in." % Ledger.text(goal.grant)))
	# The lorry brings the morning delivery and takes the rubbish and goods.
	kitchen.delivered.connect(func(_crates: int) -> void:
		var pallets := building.objects_tagged([&"delivery_pallet"])
		var to := building.object_at(pallets[0]).centre if not pallets.is_empty() else intake.stop_point()
		vehicles.drive_in(LORRY, to, Callable(), LORRY_STAY))
	intake.offer_made.connect(func(offer: Dictionary) -> void:
		Toasts.post("Transfer offer", "The Ministry asks you to take %d more prisoners tomorrow, at %s each. Accept or decline in the office (O)."
				% [offer.count, Ledger.text(offer.fee)]))
	intake.arrived.connect(func(came: Array[Person]) -> void:
		var words := "%d new %s on the way to reception." % [came.size(),
				"prisoner is" if came.size() == 1 else "prisoners are"]
		if escapes.without_perimeter and not secure_area.has_perimeter:
			words += " There's no perimeter yet, so anyone who wanders off can walk away."
		Toasts.post("The bus is here", words))
	if not saved.is_empty():
		PrisonSave.apply_rest(self, saved)
		build_costs.start_from_now()
		_apply_difficulty()
	clock.hour_changed.connect(func(hour: int) -> void:
		if hour == AUTOSAVE_HOUR and not attract:
			PrisonSave.write(PrisonSave.AUTOSAVE, PrisonSave.capture(self)))
	undo.name = "Undo"
	undo.capture = capture_world
	undo.restore = func(state: Dictionary) -> void:
		build_costs.refund_all = true
		restore_world(state)
		build_costs.refund_all = false
	add_child(undo)
	undo.start([building.changed, terrain.changed, water.changed, foliage.changed, paths.changed] as Array[Signal])
	build_feel.name = "BuildFeel"
	build_feel.building = building
	build_feel.terrain = terrain
	build_feel.cell_size = grid.cell_size
	build_feel.view_for = func(level: int) -> BuildingView: return views.get(level)
	build_feel.active = func() -> bool:
		return (controller.tool != BuildController.Tool.NONE and not undo.restoring()) or blueprints.finishing
	add_child(build_feel)
	build_feel.start()
	# Land bought stays bought: undo starts again from the new boundary.
	var tunnel_ends: Array = []
	land_plots.buying.connect(func(_plot: Rect2i) -> void:
		tunnel_ends.clear()
		for node in roads.edge_nodes():
			tunnel_ends.append([paths.nodes[node], roads.outward(node)]))
	land_plots.bought.connect(func(_plot: Rect2i) -> void:
		_extend_roads(tunnel_ends)
		undo.reset())
	# With nothing left to undo, the latest land bought goes back for a full
	# refund, within the hour.
	undo.nothing_to_undo = land_plots.undo_last
	# Land given back stays given back.
	land_plots.sold.connect(func(_plot: Rect2i) -> void: undo.reset())
	jobs_panel.name = "JobsPanel"
	jobs_panel.debug_overlay = debug_overlay
	jobs_panel.jobs = jobs
	jobs_panel.items = items
	jobs_panel.building = building
	jobs_panel.warnings = func() -> Array[String]:
		return kitchen.warnings() + laundry.warnings() + wear.warnings() + intake.warnings()
	grid.add_child(jobs_panel)
	var load_sample := func(index: int) -> void:
		SamplePrisons.next = index
		get_tree().reload_current_scene()
	inspector.offer_samples(SamplePrisons.NAMES, SamplePrisons.CHALLENGES, sample, load_sample)

	var area := Rect2(land_plots.area)
	camera_rig.bounds = Rect2(grid.to_global(Vector3(area.position.x, 0, area.position.y)).x,
			grid.to_global(Vector3(area.position.x, 0, area.position.y)).z, area.size.x, area.size.y) \
			if area.has_area() else grid.world_rect()
	# Far enough out to see the land for sale.
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
	var new_game := NewGame.pending
	NewGame.pending = false
	if new_game and not NewGame.warden_traits.is_empty():
		roster.preset(&"warden", NewGame.warden_traits)
	if attract:
		hud.visible = false
	elif not saved.is_empty():
		Toasts.post("Loaded", PrisonSave.describe(saved), 6.0)
	elif new_game:
		Toasts.post("Welcome to " + title, ("Empty land to build on." if not build_sample_layout
				else SamplePrisons.CHALLENGES[sample]) + "\nPress F1 for the controls.", 8.0)
	elif build_sample_layout:
		Toasts.post(SamplePrisons.NAMES[sample], SamplePrisons.CHALLENGES[sample]
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
	clock_bar.runner = runner
	clock_bar.ledger = ledger
	clock_bar.regime = regime
	clock_bar.in_tray = in_tray
	clock_bar.tray_pressed.connect(book.toggle.bind(&"in_tray"))
	clock_bar.money_pressed.connect(book.toggle.bind(&"money"))
	clock_bar.clashes_pressed.connect(book.toggle.bind(&"timetable"))
	hud.add_child(clock_bar)

	# The management book: each window is a page behind a bookmark.
	hud.add_child(book)
	timetable.schedule = schedule
	timetable.runner = runner
	timetable.categories.assign(PrisonCatalogue.CATEGORIES)
	timetable.activities = PrisonCatalogue.ACTIVITIES
	timetable.clock = clock
	timetable.regime = regime
	book.add_page(&"timetable", "Regime", "The week: timetable, sessions, rota and the prison's own jobs. T", "timetable", timetable)
	staff_window.roles = PrisonCatalogue.ROLES
	staff_window.programmes = PrisonCatalogue.PROGRAMMES
	staff_window.people = people
	staff_window.shifts = shifts
	staff_window.routes = routes
	staff_window.route_icon = load("res://core/ui/icons/tool_route.svg")
	staff_window.ledger = ledger
	staff_window.roster = roster
	staff_window.has_training_room = training.has_room
	staff_window.hire_refused.connect(func() -> void:
		Toasts.post("Out of money", "Nobody new can be taken on until the balance is back above zero."))
	book.add_page(&"staff", "Staff", "Who works here, and work programmes. P", "staff", staff_window)
	finance_window.ledger = ledger
	var budget_panel := BudgetPanel.new()
	budget_panel.budget = budget
	finance_window.add_section(budget_panel)
	book.add_page(&"money", "Money", "What comes in and goes out. M", "money", finance_window)
	office_window.office = office
	office_window.intake = intake
	office_window.standing = standing
	office_window.consequences = consequences
	office_window.searching = searching
	book.add_page(&"office", "Office", "The warden's office: intake, goals and the grade. O", "office",
			office_window)
	heads_window.heads = heads
	heads_window.desk_work = desk_work
	heads_window.clock = clock
	in_tray_window.in_tray = in_tray
	in_tray_window.clock = clock
	book.add_page(&"in_tray", "In-tray", "Requests and letters waiting for an answer. J", "in_tray", in_tray_window)
	book.add_page(&"heads", "Heads", "Department heads: hire cards, applicants and bonuses. H", "heads",
			heads_window)
	security_window.security = security
	security_window.secure_area = secure_area
	security_window.searching = searching
	security_window.escapes = escapes
	security_window.coverage_tint = coverage_tint
	security_window.sit_ins = sit_ins
	security_window.infirmary = infirmary
	security_window.prisoners = func() -> int:
		return people.people.filter(func(p: Person) -> bool: return p.group == &"prisoner").size()
	security_window.look_pressed.connect(func(level: int, point: Vector2) -> void:
		building.active = level
		camera_rig.focus_on(Vector3(point.x * grid.cell_size, people.nav().height_at(level, point), point.y * grid.cell_size)))
	book.add_page(&"security", "Security", "Cameras, incidents, alerts and the Safety grade. K", "security",
			security_window)
	programmes_window.courses = courses
	programmes_window.reform = reform
	programmes_window.parole = parole
	programmes_window.release = release
	book.add_page(&"programmes", "Programmes", "Courses, therapy, parole and how reformed everyone is. L",
			"programmes", programmes_window)

	help_card.sections = PrisonHelp.SECTIONS
	hud.add_child(help_card)
	var readout := CursorReadout.new()
	readout.controller = controller
	hud.add_child(readout)
	fail_card.keep_playing = func() -> void:
		standing.lost = false
		standing.set_difficulty(Standing.DIFFICULTIES[0])
		fail_card.hide()
		if clock.paused():
			clock.toggle_pause()
	fail_card.load_autosave = func() -> void: saves_window.load_slot.call(PrisonSave.AUTOSAVE)
	fail_card.start_again = func() -> void:
		SamplePrisons.next = sample
		get_tree().reload_current_scene()
	hud.add_child(fail_card)

	# The pause menu goes last, so it sits over everything and hears keys
	# first.
	saves_window.save = func(slot: String) -> void:
		if PrisonSave.write(slot, PrisonSave.capture(self)) == OK:
			Toasts.post("Saved", PrisonSave.describe(PrisonSave.read(slot)))
	saves_window.load_slot = func(slot: String) -> void:
		PrisonSave.pending = PrisonSave.read(slot)
		get_tree().reload_current_scene()
	settings_window.standing = standing
	settings_window.sentences = sentences
	settings_window.blueprints = blueprints
	settings_window.desk_work = desk_work
	pause_menu.clock = clock
	pause_menu.subtitle = title
	pause_menu.add_page(&"saves", "Save and load", saves_window, &"saves_toggle")
	pause_menu.add_page(&"settings", "Game settings", settings_window, &"settings_toggle")
	pause_menu.add_button("Controls", func() -> void:
		pause_menu.close()
		help_card.show())
	pause_menu.add_gap()
	pause_menu.add_button("Quit to title", func() -> void:
		get_tree().change_scene_to_file(TITLE_SCENE))
	pause_menu.add_button("Quit to desktop", func() -> void: get_tree().quit(), &"DangerButton")
	hud.add_child(pause_menu)


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
	elif event.is_action_pressed("build_cancel"):
		# Only reaches here when no window or tool wanted Esc.
		pause_menu.open()
		get_viewport().set_input_as_handled()
	else:
		for id: StringName in BOOK_KEYS:
			if event.is_action_pressed(BOOK_KEYS[id]):
				book.toggle(id)
				get_viewport().set_input_as_handled()
				return


## A little ghost that floats up and fades where someone died.
func _ghost(level: int, point: Vector2) -> void:
	var ghost := Label3D.new()
	ghost.text = "~ o o ~"
	ghost.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	ghost.font_size = 64
	ghost.outline_size = 12
	ghost.pixel_size = 0.006
	ghost.modulate = Color(1, 1, 1, 0.9)
	ghost.outline_modulate = Color(0.55, 0.6, 0.75)
	var at := Vector3(point.x * grid.cell_size, people.nav().height_at(level, point) + 0.6, point.y * grid.cell_size)
	ghost.position = at
	grid.add_child(ghost)
	var tween := ghost.create_tween()
	tween.set_parallel()
	tween.tween_property(ghost, "position", at + Vector3.UP * 2.5, 6.0)
	tween.tween_property(ghost, "modulate:a", 0.0, 6.0)
	tween.chain().tween_callback(ghost.queue_free)


## Difficulty's scales on wages, reform, reoffending and grants.
func _apply_difficulty() -> void:
	var def := standing.difficulty
	finances.wage_scale = def.wage_scale
	reform.loss_scale = def.reform_loss_scale
	release.return_scale = def.reoffend_scale


## An operation's time came round in the regime.
func _on_operation(id: StringName, index: int) -> void:
	match id:
		&"kitchen_lorry":
			kitchen.deliver()
			cleaning.collect()
			workshop.collect()
		&"workshop_contracts":
			budget.make_offers()
		&"release":
			release.announce()
		&"intake_bus":
			intake.bus()
		&"parole_planning":
			parole.plan_day()
		&"parole_hearings":
			parole._post_hearing()
		&"tool_counts":
			contraband.count_tools()


## The rota lane: a row per shift with its staff, such as "Days: Guard 2,
## Cook 1".
func _rota_rows() -> Array:
	var out: Array = []
	for shift in shifts.shifts:
		var parts := PackedStringArray()
		var total := 0
		for role in PrisonCatalogue.all_roles():
			var count := shifts.wanted_for(role.id, shift.id)
			if count > 0:
				parts.append("%s %d" % [role.display_name, count])
				total += count
		if total > 0:
			out.append(["%s: %s" % [shift.display_name, ", ".join(parts)], shift.start_hour * 2, shift.hours * 2, total])
	return out


## Postcard boards show the latest cards that came.
func _dress_model(placed: BuildingMap.PlacedObject, model: Node3D) -> void:
	if placed.def.id != &"postcard_board":
		return
	var shown := mini(release.postcards.size(), Release.BOARD_CARDS)
	for i in Release.BOARD_CARDS:
		var card := model.find_child("card_%d" % (i + 1), true, false)
		if card != null:
			card.visible = i < shown


func _add_level_view(level: int, level_map: BuildingMap) -> void:
	var level_view := BuildingView.new()
	level_view.name = "BuildingView%d" % level
	level_view.grid = grid
	level_view.terrain = terrain
	level_view.level = level
	level_view.room_types = PrisonCatalogue.ROOM_TYPES
	level_view.door_model = PrisonCatalogue.DOOR_MODEL
	level_view.door_models = PrisonCatalogue.door_models()
	level_view.visible = building == null or level <= building.active
	level_view.dress_model = _dress_model
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


## A road along the inside of the land on the side nearest the entrance,
## from one edge to the other, into a tunnel at each end, with the ground
## under it smoothed. Not across water: a prison by the water goes without.
func _lay_road() -> void:
	if shifts.entrance.is_empty() or roads.has_roads():
		return
	var land := map.land_bounds()
	var spot: Vector2 = shifts.entrance[1]
	var gaps: Array[float] = [spot.x - land.position.x, land.end.x - spot.x, spot.y - land.position.y,
			land.end.y - spot.y]
	var side := gaps.find(gaps.min())
	var inset := ROAD_VERGE + PrisonCatalogue.path(&"road").width * 0.5
	var line: float = [land.position.x + inset, land.end.x - inset, land.position.y + inset,
			land.end.y - inset][side]
	var a := Vector2(line, land.position.y) if side < 2 else Vector2(land.position.x, line)
	var b := Vector2(line, land.end.y) if side < 2 else Vector2(land.end.x, line)
	for i in 101:
		var cell := Vector2i(a.lerp(b, i / 100.0).floor())
		if water.body_at(cell) != null:
			return
	_road_between(a, b)


## A straight road from a to b (tiles), with the plants cleared and the
## ground smoothed under it.
func _road_between(a: Vector2, b: Vector2) -> void:
	var half := PrisonCatalogue.path(&"road").width * 0.5
	foliage.remove_in_rect(Rect2(a, b - a).abs().grow(half + 0.5))
	Roads.grade(terrain, a, b, half, building.corner_in_use)
	paths.add_segment(a, b, null, &"road")


## Roads that ran into a tunnel where land was just bought carry on to the
## new edge. `ends` are the tunnel mouths before buying, as [point,
## outward].
func _extend_roads(ends: Array) -> void:
	var land := Rect2(map.land_bounds())
	for end: Array in ends:
		var from: Vector2 = end[0]
		var out: Vector2 = end[1]
		if not land.grow(-Roads.EDGE).has_point(from):
			continue
		var to := from
		while map.owns(Vector2i((to + out * 0.5).floor())):
			to += out * 0.5
		to = to.clamp(land.position, land.end)
		var strip := Rect2(from, to - from).abs().grow(PrisonCatalogue.path(&"road").width * 0.5)
		# Not through a pond, or a barn that came with the land.
		if water.body_at(Vector2i(((from + to) * 0.5).floor())) == null \
				and not building.in_use(Rect2i(Vector2i(strip.position.floor()), Vector2i(strip.size.ceil()))):
			_road_between(from, to)


## Every so often a car drives through, in one tunnel and out of another.
func _pass_through(minutes: float) -> void:
	_passing_wait -= minutes
	if _passing_wait > 0.0:
		return
	_passing_wait = _rng.randf_range(PASSING_CARS.x, PASSING_CARS.y)
	vehicles.drive_through(CARS[_rng.randi() % CARS.size()], roads.route_through(_rng))


## Where staff come and go: the spot on the edge of the land with the
## shortest walk to where they work, of the nearest few. They set off
## early enough to be in by the time their shift starts.
func _set_entrance() -> void:
	var work := _staff_spot()
	if work.is_empty():
		return
	var land := building.land[0]
	var edge: Array[Vector2] = []
	for x in range(land.position.x, land.end.x):
		edge.append(Vector2(x + 0.5, land.position.y + 0.5))
		edge.append(Vector2(x + 0.5, land.end.y - 0.5))
	for z in range(land.position.y + 1, land.end.y - 1):
		edge.append(Vector2(land.position.x + 0.5, z + 0.5))
		edge.append(Vector2(land.end.x - 0.5, z + 0.5))
	edge.sort_custom(func(a: Vector2, b: Vector2) -> bool:
		return a.distance_squared_to(work[1]) < b.distance_squared_to(work[1]))
	var best: Array = []
	var shortest := INF
	for spot in edge.slice(0, ENTRANCE_TRIES):
		if is_nan(people.nav().height_at(0, spot)):
			continue
		var route := people.nav().find_path(0, spot, work[0], work[1])
		var length := 0.0
		for i in range(1, route.size()):
			length += route[i].distance_to(route[i - 1])
		if not route.is_empty() and length < shortest:
			best = [0, spot]
			shortest = length
	shifts.entrance = best
	if not best.is_empty():
		shifts.walk_in_minutes = shortest / people.speed


## Somewhere for new staff to stand, as [level, spot], or [] for nowhere.
func _staff_spot() -> Array:
	var tries: Array = []
	for n: int in building.levels:
		for room: Room in building.levels[n].rooms():
			var zone := people.access.zone_of(room)
			if zone != null and zone.id == &"staff":
				tries.append([n, room.centre()])
	var centre := Vector2(building.land[0].get_center())
	for ring in 12:
		for step in 8:
			tries.append([0, centre + Vector2.from_angle(step * TAU / 8) * ring * 2.0])
	for entry: Array in tries:
		if not is_nan(people.nav().height_at(entry[0], entry[1])):
			return entry
	return []


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


## The build and the land as plain data, for undo and saving.
## A save's map size (older saves had no plots), a sample's, or the one
## chosen for a new prison.
func _choose_map_size() -> MapSizeDef:
	var def: MapSizeDef = null
	if not PrisonSave.pending.is_empty():
		def = PrisonCatalogue.map_size(PrisonSave.pending.get("map_size", &"legacy"))
	elif build_sample_layout and sample >= 0:
		def = PrisonCatalogue.map_size(&"sample")
	else:
		def = PrisonCatalogue.map_size(SamplePrisons.next_map_size)
	return def if def != null else PrisonCatalogue.MAP_SIZES[0]


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
		for def in PrisonCatalogue.PLANTS:
			if def.id == id:
				return def
		return null)
	paths.load_data(state.get("paths", {}))
	building.load_data(state.get("building", {}), PrisonCatalogue.object)


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
	var room := building.current().room_at(cell) if cell != GridCursor.NO_CELL else null
	if room == null:
		status.set_item(&"room", "No room here" if cell != GridCursor.NO_CELL else "Off the map", &"SubtleLabel")
		return
	var def := PrisonCatalogue.room_type(room.type)
	status.set_item(&"room", "%s  ·  %d tiles  ·  %s" % [
		def.display_name if def != null else "Unmarked room",
		room.cells.size(),
		"indoors" if room.indoor else "outdoors"])
