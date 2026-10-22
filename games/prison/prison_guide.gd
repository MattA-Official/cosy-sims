class_name PrisonGuide
## Wires the guide card (core/ui/guide.gd) into the prison: a first-time
## tip for each tool, page and a few happenings, and the tutorial's guided
## first day on empty land, which starts chapter 1 when it's done.

## A tip the first time each tool is picked: [title, words].
const TOOL_TIPS := {
	BuildController.Tool.ROOM: ["Rooms", "Drag out a box for walls all round with a floor inside. Without instant building, it goes down as a plan and a handyman builds it."],
	BuildController.Tool.WALL: ["Walls", "Drag between corners for a run of wall. Alt for any angle; Paint mode colours one side at a time."],
	BuildController.Tool.FLOOR: ["Floors", "Drag to lay floor on this side of any walls. Shift-click floors a whole room."],
	BuildController.Tool.OPENING: ["Doors and windows", "Click a wall to put one in. Rooms need a door before anyone can use them."],
	BuildController.Tool.OBJECT: ["Objects", "Pick something and click to place it. R turns it; hover a tile for what it does."],
	BuildController.Tool.ROOM_TYPE: ["Room types", "Click a room to say what it's for. The card says what it still needs, such as a bed and a toilet for a cell."],
	BuildController.Tool.DEMOLISH: ["Demolish", "Click or drag to take things away. Plans not yet started come back free; built things give most of their price back."],
	BuildController.Tool.PATH: ["Paths", "Click to start and click to end. Floored ground counts as path too."],
	BuildController.Tool.PLANTS: ["Plants", "Hold the mouse to plant. Prisoners like a bit of green in the yard."],
	BuildController.Tool.TERRAIN: ["Land", "Hold the mouse to raise or lower the ground. Water bodies are in here too."],
	BuildController.Tool.ZONE: ["Zones", "Click a room to say who may be in it. Click a door to lock it."],
	BuildController.Tool.ROUTE: ["Patrol routes", "Click points for a loop; guards on patrol walk it."],
	BuildController.Tool.MOVE: ["Moving things", "Click a room or object to pick it up, and click again to put it down."],
	BuildController.Tool.CONDUIT: ["Cables and pipes", "With Self-sufficient utilities, lay runs from your plant to what needs it. Green is on, amber on stores, red off."],
}
## A tip the first time each page of the management book opens.
const PAGE_TIPS := {
	&"timetable": ["The regime", "The week, half an hour at a time. Paint blocks such as Sleep, Eat and Yard onto the days; the rota says who works when."],
	&"staff": ["Staff", "Say how many of each job you want on each shift; they apply and turn up. Wages are paid daily."],
	&"money": ["Money", "What comes in each day and what goes out. Keep the balance above zero or nobody new can be hired."],
	&"office": ["The office", "Intake, goals and the grade. The Ministry pays for each prisoner and judges you on safety, wellbeing, reform and money."],
	&"in_tray": ["The in-tray", "Requests and letters wait here. Answer them before they go stale."],
	&"heads": ["Department heads", "The warden hires heads with a hire card at their desk. Each head brings a bonus to their department."],
	&"research": ["Research", "Heads earn know-how; spend it on the board for new rooms, objects and ways of working."],
	&"security": ["Security", "Cameras, incidents and alerts. The Safety grade is built from here."],
	&"programmes": ["Programmes", "Courses and therapy make prisoners less likely to come back, and earn parole."],
}

## Saved with the prison: the tutorial step reached, or -1 for none.
const META := &"tutorial_step"


static func setup(main: Node) -> Guide:
	var guide := Guide.new()
	guide.name = "Guide"
	if main.attract:
		guide.tips_on = false
		return guide
	(main.hud as CanvasLayer).add_child(guide)
	var controller: BuildController = main.controller
	controller.tool_changed.connect(func(tool: BuildController.Tool) -> void:
		if TOOL_TIPS.has(tool):
			guide.tip(StringName("tool:%d" % tool), TOOL_TIPS[tool][0], TOOL_TIPS[tool][1]))
	var book: ManagementBook = main.book
	book.page_changed.connect(func(id: StringName) -> void:
		if PAGE_TIPS.has(id):
			guide.tip(StringName("page:" + String(id)), PAGE_TIPS[id][0], PAGE_TIPS[id][1]))
	(main.wear as Wear).broke.connect(func(_key: Vector2i) -> void:
		guide.tip(&"broke", "Something broke", "Things wear out with use. A handyman mends them; a spanner shows over anything waiting."))
	(main.fights as Fights).started.connect(func(_fight: Variant) -> void:
		guide.tip(&"fight", "A fight", "Guards nearby break it up. Unhappy, crowded or bored prisoners fight more; the Security page shows where."))
	(main.intake as Intake).arrived.connect(func(_people: Array) -> void:
		guide.tip(&"arrivals", "New arrivals", "Prisoners are searched in reception, then find a free bed. Click one to see their needs and mood."))
	(main.escapes as Escapes).running.connect(func(_person: Person) -> void:
		guide.tip(&"escape", "Someone's running", "Guards give chase. Fences and walls all round, with gates, keep prisoners in."))
	(main.utilities as Utilities).mode_changed.connect(func() -> void:
		if (main.utilities as Utilities).mode == Utilities.Mode.SELF_SUFFICIENT:
			guide.tip(&"self_sufficient", "Self-sufficient", "Build a generator, a well and a treatment plant, then lay cables and pipes with the utilities tool (U)."))
	if NewGame.tutorial:
		NewGame.tutorial = false
		main.set_meta(META, 0)
	_resume(main, guide)
	return guide


## Starts the steps where the prison left off, if a tutorial is running.
static func _resume(main: Node, guide: Guide) -> void:
	var from: int = main.get_meta(META, -1)
	if from < 0:
		return
	var list := steps(main)
	if from >= list.size():
		return
	guide.finish_label = "Start chapter 1"
	guide.finish_pressed = func() -> void: PrisonCampaign.start_chapter(main, PrisonCatalogue.CHAPTERS[0])
	guide.steps_finished.connect(func() -> void: main.set_meta(META, list.size()))
	guide.steps_skipped.connect(func() -> void: main.set_meta(META, -1))
	var track := func() -> void: main.set_meta(META, guide.current)
	(main.clock as GameClock).minute_passed.connect(func(_minute: int) -> void:
		if guide.running():
			track.call())
	guide.start_steps(list, from)


## The guided first day, from empty land to the first prisoners.
static func steps(main: Node) -> Array[Guide.Step]:
	var building: Building = main.building
	var book: ManagementBook = main.book
	var toolbar := main.get_node_or_null("HUD/BuildToolbar")
	var tool_button := func(tool: BuildController.Tool) -> Callable:
		return func() -> Control: return toolbar._tool_buttons.get(tool) if toolbar != null else null
	var bookmark := func(id: StringName) -> Callable:
		return func() -> Control: return book._pages[id].button if book._pages.has(id) else null
	var rig: Node3D = main.camera_rig
	var start_view := [rig.get("_target_position"), rig.get("_target_distance"), rig.get("_target_yaw")]
	var looked := func() -> bool:
		return [rig.get("_target_position"), rig.get("_target_distance"), rig.get("_target_yaw")] != start_view
	var shifts: Shifts = main.shifts
	var wants := func(roles: Array) -> bool:
		return roles.all(func(role: StringName) -> bool:
			return shifts.shifts.any(func(shift: ShiftDef) -> bool: return shifts.wanted_for(role, shift.id) > 0))
	var working := func(type: StringName) -> bool: return _working_room(building, type)
	var opened := {}
	book.page_changed.connect(func(id: StringName) -> void: opened[id] = true)
	var people: People = main.people
	var inspector: Inspector = main.inspector
	var clock: GameClock = main.clock
	var speed_button := func() -> Control:
		var bar: Node = main.clock_bar
		return bar._speeds[2] if bar._speeds.size() > 2 else null
	var list: Array[Guide.Step] = [
		Guide.Step.make("Have a look round",
				"Pan with W A S D or right-drag, turn with Q and E, and zoom with the wheel. This is your land.", looked),
		Guide.Step.make("Take on a handyman",
				"Open the Staff page and add a handyman to the day shift. Building here goes down as plans, and the handyman builds them.",
				wants.bind([&"handyman"]), bookmark.call(&"staff")),
		Guide.Step.make("Build a room",
				"Pick the Room tool and drag out a box about four tiles by three. It's a plan until the handyman has built it.",
				func() -> bool: return _any_walls(building), tool_button.call(BuildController.Tool.ROOM)),
		Guide.Step.make("Put in a door",
				"With the Doors tool, click one of the room's walls.",
				func() -> bool: return _any_door(building), tool_button.call(BuildController.Tool.OPENING)),
		Guide.Step.make("Make it a cell",
				"Once the walls are up, pick Room type, choose Cell and click inside the room.",
				func() -> bool: return _has_room(building, &"cell"), tool_button.call(BuildController.Tool.ROOM_TYPE)),
		Guide.Step.make("A bed and a toilet",
				"Every cell needs a bed and a toilet. Find them under Objects and click to place them in the cell.",
				working.bind(&"cell"), tool_button.call(BuildController.Tool.OBJECT)),
		Guide.Step.make("Build a reception",
				"New prisoners are searched there first. Build another room with a door, mark it Reception and give it a reception desk.",
				working.bind(&"reception"), tool_button.call(BuildController.Tool.ROOM_TYPE)),
		Guide.Step.make("An office for the warden",
				"Nobody is sent without a warden. Build an Office with a desk, then add a warden on the Staff page.",
				func() -> bool: return working.call(&"office") and wants.call([&"warden"]), bookmark.call(&"staff")),
		Guide.Step.make("A kitchen and a canteen",
				"A Kitchen needs a cooker (and a fridge and serving counter help); a Canteen needs tables and seats.",
				func() -> bool: return working.call(&"kitchen") and working.call(&"canteen"),
				tool_button.call(BuildController.Tool.ROOM_TYPE)),
		Guide.Step.make("A shower room",
				"Build a room, mark it Shower and put in a shower or two.",
				working.bind(&"shower"), tool_button.call(BuildController.Tool.ROOM_TYPE)),
		Guide.Step.make("Cook and guard",
				"On the Staff page, add a cook and a guard to the day shift.",
				wants.bind([&"cook", &"guard"]), bookmark.call(&"staff")),
		Guide.Step.make("Look at the regime",
				"The Regime page is the prison's week: when everyone sleeps, eats, washes and goes out. The default one is fine to start.",
				func() -> bool: return opened.has(&"timetable"), bookmark.call(&"timetable")),
		Guide.Step.make("Wait for the bus",
				"Speed time up. The bus comes at 9 in the morning with prisoners for each free bed.",
				func() -> bool: return people.people.any(func(p: Person) -> bool: return p.group == &"prisoner"),
				speed_button),
		Guide.Step.make("Meet a prisoner",
				"Click a prisoner to see their needs, mood and what they're doing.",
				func() -> bool:
					var picked: Variant = inspector.selected()
					return picked is Person and (picked as Person).group == &"prisoner"),
	]
	return list


## Whether any walls are built or planned on any level.
static func _any_walls(building: Building) -> bool:
	for map: BuildingMap in building.levels.values():
		if not map.walls.is_empty() or not map.planned_walls.is_empty():
			return true
	return false


static func _any_door(building: Building) -> bool:
	for map: BuildingMap in building.levels.values():
		if map.walls.values().has(BuildingMap.Wall.DOOR):
			return true
		if map.planned_walls.values().any(func(plan: Array) -> bool: return plan[0] == BuildingMap.Wall.DOOR):
			return true
	return false


static func _has_room(building: Building, type: StringName) -> bool:
	for map: BuildingMap in building.levels.values():
		if map.rooms().any(func(room: Room) -> bool: return room.type == type):
			return true
	return false


## Whether a room of the type is marked and has all it needs.
static func _working_room(building: Building, type: StringName) -> bool:
	var defs := PrisonCatalogue.ROOM_TYPES.filter(func(d: RoomTypeDef) -> bool: return d.id == type)
	if defs.is_empty():
		return false
	var def: RoomTypeDef = defs[0]
	for map: BuildingMap in building.levels.values():
		for room: Room in map.rooms():
			if room.type == type and def.problems(room, map).is_empty():
				return true
	return false
