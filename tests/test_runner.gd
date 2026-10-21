extends SceneTree
## Headless checks. Run from the project folder with:
##   godot --headless -s res://tests/test_runner.gd

var _failures := 0
## Prisoners can walk off a prison with no perimeter. Every test but the
## escape one turns that off, so long runs keep everyone they start with.
var _escapes_on := false


func _initialize() -> void:
	node_added.connect(func(node: Node) -> void:
		if node is Escapes and not _escapes_on:
			(node as Escapes).enabled = false)


func _process(_delta: float) -> bool:
	# Runs on the first frame, once the root viewport is in the tree.
	_test_grid_conversions()
	_test_edges()
	_test_rooms()
	_test_room_types()
	_test_objects()
	_test_snapping()
	_test_styles_and_indoors()
	_test_land()
	_test_demolish()
	_test_windows()
	_test_wall_paint()
	_test_wall_joins()
	_test_terrain()
	_test_water()
	_test_path_network()
	_test_building_levels()
	_test_walls_beside_stairs()
	_test_object_categories()
	_test_ramps()
	_test_stair_builder()
	_test_nav_graph()
	_test_door_steps()
	_test_people()
	_test_angled_walls()
	_test_path_profile()
	_test_foliage()
	_test_main_scene_loads()
	_test_sample_prisons()
	_test_clock()
	_test_daily_routine()
	_test_mood_model()
	_test_room_quality()
	_test_traits_and_choices()
	_test_needs_in_a_day()
	_test_zones_and_doors()
	_test_stopped_on_stairs()
	_test_jobs_and_carrying()
	_test_kitchen()
	_test_cleaning()
	_test_laundry()
	_test_work_programmes()
	_test_staff_window()
	_test_guards()
	_test_wear_and_repair()
	_test_money()
	_test_intake()
	_test_standing()
	_test_undo()
	_test_saving()
	_test_flexible_objects()
	_test_roads()
	_test_buying_land()
	_test_misconduct()
	_test_contraband()
	_test_fights()
	_test_consequences()
	_test_perimeter()
	_escapes_on = true
	_test_escapes()
	_escapes_on = false
	_test_security()
	_test_sit_ins()
	_test_category_timetables()
	_test_category_zones()
	_test_trading_and_tools()
	_test_shakedown_and_deaths()
	_test_progress()
	_test_sentences_and_reform()
	_test_courses()
	_test_parole()
	_test_release()
	_test_balanced_grade()
	_test_goals_and_difficulty()
	_test_escape_plans()
	_test_budget()
	_test_staff_roster()
	_test_readout_and_eyedropper()
	_test_move_and_copy()
	_test_templates()
	_test_build_feel()
	_test_blueprints()
	_test_regime()
	_test_heads()
	_test_in_tray()
	_test_perks()
	if _failures == 0:
		print("All tests passed.")
	quit(1 if _failures > 0 else 0)
	return false


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		printerr("FAIL: ", message)


func _test_grid_conversions() -> void:
	var grid := BuildGrid.new()
	grid.size = Vector2i(10, 8)
	grid.cell_size = 2.0
	root.add_child(grid)
	_check(grid.world_to_cell(Vector3(0.1, 0, 0.1)) == Vector2i(0, 0), "point near origin is cell 0,0")
	_check(grid.world_to_cell(Vector3(-0.1, 0, 3.9)) == Vector2i(-1, 1), "negative x rounds down")
	_check(grid.cell_to_world(Vector2i(2, 3)) == Vector3(5, 0, 7), "cell centre")
	_check(grid.world_to_cell(grid.cell_to_world(Vector2i(7, 4))) == Vector2i(7, 4), "round trip")
	_check(grid.contains(Vector2i(9, 7)) and not grid.contains(Vector2i(10, 0)), "contains edges")
	_check(grid.world_rect() == Rect2(0, 0, 20, 16), "world rect")
	grid.free()


func _test_edges() -> void:
	var a := Vector2i(2, 3)
	_check(BuildingMap.edge_between(a, a + Vector2i.RIGHT) == BuildingMap.edge_between(a + Vector2i.RIGHT, a),
			"edge_between is symmetric")
	_check(BuildingMap.edge_between(a, a + Vector2i(1, 1)) == BuildingMap.NO_EDGE, "diagonals share no edge")
	for step in BuildingMap.DIRECTIONS:
		var cells := BuildingMap.edge_cells(BuildingMap.edge_between(a, a + step))
		_check(cells.has(a) and cells.has(a + step), "edge_cells inverts edge_between")
	_check(BuildingMap.edges_on_line(Vector2i(1, 1), Vector2i(4, 1)).size() == 3, "line along X")
	_check(BuildingMap.edges_on_line(Vector2i(1, 1), Vector2i(3, 3)).is_empty(), "no diagonal walls")
	_check(BuildingMap.rect_perimeter(Rect2i(0, 0, 3, 2)).size() == 10, "perimeter of 3x2")
	_check(BuildingMap.rect_between(Vector2i(5, 1), Vector2i(2, 3)) == Rect2i(2, 1, 4, 3), "rect_between")


func _test_rooms() -> void:
	var map := BuildingMap.new(Rect2i(0, 0, 20, 20))
	map.fill_floor(Rect2i(0, 0, 4, 4))
	_check(map.rooms().size() == 1 and not map.rooms()[0].enclosed, "bare floor is one open room")

	map = BuildingMap.new(Rect2i(0, 0, 20, 20))
	map.build_room(Rect2i(2, 2, 4, 3))
	_check(map.rooms().size() == 1 and map.rooms()[0].enclosed, "built room is enclosed")
	_check(map.rooms()[0].cells.size() == 12, "room has every cell")

	# Split it with a wall down the middle, then put a door in it.
	map.build_walls(BuildingMap.edges_on_line(Vector2i(4, 2), Vector2i(4, 5)))
	_check(map.rooms().size() == 2, "a wall splits a room")
	map.set_door(Vector3i(4, 3, BuildingMap.EDGE_Z), true)
	_check(map.rooms().size() == 2, "a door still separates rooms")
	_check(map.can_walk_between(Vector2i(3, 3), Vector2i(4, 3)), "people can walk through doors")
	_check(not map.can_walk_between(Vector2i(3, 2), Vector2i(4, 2)), "people cannot walk through walls")

	# Knock out part of the outside wall.
	map.remove_walls([Vector3i(2, 2, BuildingMap.EDGE_X)])
	_check(not map.room_at(Vector2i(2, 2)).enclosed, "a gap opens a room")
	_check(map.room_at(Vector2i(5, 2)).enclosed, "the other room stays enclosed")
	_check(map.room_at(Vector2i(10, 10)) == null, "no room without floor")


func _test_room_types() -> void:
	var cell_type := PrisonCatalogue.room_type(&"cell")
	var map := BuildingMap.new(Rect2i(0, 0, 20, 20))
	map.build_room(Rect2i(0, 0, 6, 3))
	map.set_room_type(map.room_at(Vector2i.ZERO), &"cell")
	_check(map.room_at(Vector2i(5, 2)).type == &"cell", "room type covers the room")
	_check(Array(cell_type.problems(map.room_at(Vector2i.ZERO), map)) == ["Needs a bed", "Needs a toilet"],
			"empty cell lists what it needs")
	map.place_object(PrisonCatalogue.object(&"bed"), Vector2(0, 0), 0)
	map.place_object(PrisonCatalogue.object(&"toilet"), Vector2(1, 0), 0)
	_check(cell_type.problems(map.room_at(Vector2i.ZERO), map).is_empty(), "furnished cell is fine")

	# Splitting keeps the type on both halves; extending spreads it.
	map.build_walls(BuildingMap.edges_on_line(Vector2i(3, 0), Vector2i(3, 3)))
	_check(map.room_at(Vector2i(4, 1)).type == &"cell", "split rooms keep their type")
	map.remove_walls(BuildingMap.edges_on_line(Vector2i(6, 0), Vector2i(6, 3)))
	map.build_room(Rect2i(6, 0, 1, 3))
	map.remove_walls(BuildingMap.edges_on_line(Vector2i(6, 0), Vector2i(6, 3)))
	_check(map.room_at(Vector2i(6, 1)).type == &"cell", "extending a room spreads its type")
	map.set_room_type(map.room_at(Vector2i(4, 1)), &"")
	_check(map.room_at(Vector2i(4, 1)).type.is_empty(), "room type can be cleared")


func _test_objects() -> void:
	var bed := PrisonCatalogue.object(&"bed")
	var toilet := PrisonCatalogue.object(&"toilet")
	var map := BuildingMap.new(Rect2i(0, 0, 20, 20))
	_check(map.place_object(bed, Vector2(1, 1), 0) == 0, "objects need floor")
	map.build_room(Rect2i(0, 0, 4, 4))
	var id := map.place_object(bed, Vector2(1, 1), 0)
	_check(id != 0 and map.object_at(Vector2(1.5, 2.5)).id == id, "bed covers two tiles")
	_check(map.place_object(bed, Vector2(1, 2), 1) == 0, "objects cannot overlap")
	_check(map.place_object(bed, Vector2(0, 2), 1) == 0, "a rotated bed runs into the first one")
	_check(map.place_object(bed, Vector2(3, 3), 0) == 0, "objects stay on the floor")
	_check(map.place_object(toilet, Vector2(2, 1), 0) != 0, "objects can touch")
	_check(not map.can_build_wall(Vector3i(1, 2, BuildingMap.EDGE_X)), "no wall through an object")
	_check(map.can_build_wall(Vector3i(1, 1, BuildingMap.EDGE_X)), "walls can run along an object")
	map.build_walls([Vector3i(3, 1, BuildingMap.EDGE_Z)])
	_check(not map.can_place(bed, Vector2(2.5, 1), 1), "objects cannot straddle a wall")
	_check(map.remove_object(id) and map.object_at(Vector2(1.5, 1.5)) == null, "objects can be removed")


func _test_snapping() -> void:
	var bed := PrisonCatalogue.object(&"bed")
	var toilet := PrisonCatalogue.object(&"toilet")
	_check(BuildingMap.snapped_position(bed, Vector2(3.4, 4.9), 0, ObjectDef.Snap.TILE) == Vector2(3, 4),
			"tile snapping centres a bed on whole tiles")
	_check(BuildingMap.snapped_position(toilet, Vector2(3.4, 4.9), 0, ObjectDef.Snap.QUARTER)
			== Vector2(3.25, 4.5), "quarter snapping")
	_check(BuildingMap.snapped_position(toilet, Vector2(3.4, 4.9), 0, ObjectDef.Snap.FREE)
			.is_equal_approx(Vector2(3.15, 4.525)), "free placement does not snap")
	var map := BuildingMap.new(Rect2i(0, 0, 20, 20))
	map.build_room(Rect2i(0, 0, 2, 1))
	_check(map.place_object(toilet, Vector2(0.25, 0.25), 0) != 0
			and map.place_object(toilet, Vector2(0.75, 0.25), 0) != 0
			and map.place_object(toilet, Vector2(1.25, 0.25), 0) != 0, "three toilets fit side by side")
	_check(map.place_object(toilet, Vector2(1.5, 0.25), 0) == 0, "but not on top of each other")


func _test_styles_and_indoors() -> void:
	var map := BuildingMap.new(Rect2i(0, 0, 20, 20))
	map.register_styles(PrisonCatalogue.FLOORS, PrisonCatalogue.WALLS)
	map.build_room(Rect2i(0, 0, 3, 3), &"tiles", &"brick")
	_check(map.room_at(Vector2i.ZERO).indoor, "walled room is indoors")
	_check(map.floors[Vector2i(1, 1)] == &"tiles" and map.wall_style(Vector3i(0, 0, 0)) == &"brick",
			"styles are stored")
	map.build_room(Rect2i(5, 0, 3, 3), &"lawn", &"fence")
	var yard := map.room_at(Vector2i(5, 0))
	_check(yard.enclosed and not yard.indoor, "fenced area is enclosed but outdoors")
	map.build_walls(BuildingMap.rect_perimeter(Rect2i(5, 0, 3, 3)), &"plaster")
	_check(map.room_at(Vector2i(5, 0)).indoor, "restyling the fence to walls brings it indoors")
	var yard_type := PrisonCatalogue.room_type(&"yard")
	map.set_room_type(map.room_at(Vector2i(5, 0)), &"yard")
	_check(Array(yard_type.problems(map.room_at(Vector2i(5, 0)), map)) == ["Needs to be outdoors"],
			"a yard has to be outdoors")
	map.fill_floor(Rect2i(10, 0, 1, 1), &"paving")
	_check(not map.room_at(Vector2i(10, 0)).indoor, "a lone patch of paving is outdoors")


func _test_land() -> void:
	var map := BuildingMap.new(Rect2i(10, 10, 5, 5))
	_check(map.fill_floor(Rect2i(8, 8, 4, 4)) == 4, "floor only goes on owned land")
	_check(map.can_build_wall(Vector3i(10, 10, BuildingMap.EDGE_Z))
			and not map.can_build_wall(Vector3i(9, 10, BuildingMap.EDGE_Z)), "walls can run along the land edge")
	map.add_land(Rect2i(15, 10, 5, 5))
	_check(map.owns(Vector2i(16, 11)) and map.land_bounds() == Rect2i(10, 10, 10, 5), "land can grow")


func _test_demolish() -> void:
	var map := BuildingMap.new(Rect2i(0, 0, 20, 20))
	map.build_room(Rect2i(0, 0, 3, 3))
	map.build_room(Rect2i(3, 0, 3, 3))
	map.place_object(PrisonCatalogue.object(&"toilet"), Vector2(4, 1), 0)
	map.demolish(Rect2i(3, 0, 3, 3))
	_check(map.objects.is_empty(), "demolish removes objects")
	_check(map.rooms().size() == 1 and map.rooms()[0].enclosed, "demolish keeps the shared wall")
	_check(map.walls.size() == 12, "and removes the rest of the demolished room's walls")
	map.build_walls(BuildingMap.edges_on_line(Vector2i(8, 0), Vector2i(8, 4)))
	map.demolish(Rect2i(8, 1, 1, 1))
	_check(map.walls.size() == 15, "demolishing next to a lone wall removes the touching piece")


## Loads every sample prison and checks who can reach a bed, a table and a
## shower. Everyone should reach everything, except in Locked out, where
## the showers have no door and the canteen needs door steps.
func _test_sample_prisons() -> void:
	var scene: PackedScene = load("res://games/prison/main.tscn")
	for index in SamplePrisons.NAMES.size():
		for steps: bool in ([false, true] if index == 7 else [false]):
			var main := scene.instantiate()
			main.sample = index
			main.door_steps = steps
			root.add_child(main)
			var name := SamplePrisons.NAMES[index] + (" with door steps" if steps else "")
			var people: People = main.people
			_check(people.people.size() >= 4, "%s: prisoners start in it" % name)
			var reach := _reachable_needs(people)
			var expected: Array[StringName] = [&"sleep", &"hunger", &"hygiene", &"bladder"]
			if index == 7:
				expected.assign([&"sleep", &"hunger", &"bladder"] if steps else [&"sleep", &"bladder"])
			_check(reach == expected, "%s: everyone can reach %s (got %s)" % [name, expected, reach])
			# On the hillside the road's eased slope joins the terraces too.
			if index == 3:
				# Without its stairs, ramp or bridge, the cells are cut off.
				people.graph = NavGraph.build(main.building, PathNetwork.new(), main.terrain)
				people._dirty = false
				_check(_reachable_needs(people) == ([&"sleep", &"bladder"] as Array[StringName]),
						"%s: only the built paths lead to the canteen" % name)
			main.free()
	Building.door_steps = false


func _test_clock() -> void:
	var clock := GameClock.new()
	clock.start_hour = 23.0
	root.add_child(clock)
	var hours: Array[int] = []
	var days: Array[int] = []
	var minutes := [0]
	clock.hour_changed.connect(func(hour: int) -> void: hours.append(hour))
	clock.day_changed.connect(func(day: int) -> void: days.append(day))
	clock.minute_passed.connect(func(_minute: int) -> void: minutes[0] += 1)
	_check(clock.time_text() == "23:00" and clock.day() == 1 and clock.weekday() == "Monday", "the clock starts when told")
	clock.advance(90.0)
	_check(minutes[0] == 90 and hours == [0] and days == [2], "the clock signals every minute, hour and day it crosses")
	_check(clock.time_text() == "00:30" and clock.weekday() == "Tuesday", "and moves on to the next day")
	clock.speed_index = 3
	clock._process(1.0)
	_check(is_equal_approx(clock.hour_float(), 0.5 + 4.0 / 60.0), "at 4×, a real second is four game minutes")
	clock.toggle_pause()
	clock._process(10.0)
	_check(clock.paused() and is_equal_approx(clock.hour_float(), 0.5 + 4.0 / 60.0), "paused, the clock stands still")
	clock.toggle_pause()
	_check(clock.speed_index == 3, "and carries on at the same speed")
	clock.jump_to_hour(12)
	_check(clock.time_text() == "12:00" and clock.day() == 2 and hours.back() == 12, "the clock jumps to an hour")
	clock.jump_to_hour(6)
	_check(clock.time_text() == "06:00" and clock.day() == 3, "an hour already gone today means tomorrow")
	var schedule: Schedule = PrisonCatalogue.SCHEDULE.copy()
	_check(schedule.at(23).id == &"sleep" and schedule.at(12).id == &"eat", "the default timetable")
	_check(schedule.block_start(3) == 22, "a block runs on across midnight")
	clock.free()


## Runs the starter prison through a whole day at speed: everyone eats in
## the canteen at lunch and is locked in their own cell at night.
func _test_daily_routine() -> void:
	var main: Node = load("res://games/prison/main.tscn").instantiate()
	main.sample = 0
	root.add_child(main)
	var clock: GameClock = main.clock
	var people: People = main.people
	var runner: ScheduleRunner = main.runner
	clock.speed_index = 0
	_check(clock.time_text() == "07:00" and runner.current().id == &"eat", "the day starts with breakfast")
	_check(people.people.all(func(p: Person) -> bool: return p.has_bed()), "everyone in the starter prison has a bed")
	var beds := {}
	for person in people.people:
		beds[person.bed] = true
	_check(beds.size() == people.people.size(), "nobody shares a bed")
	var checked := {}
	var in_room := func(person: Person, type: StringName) -> bool:
		var here := people.room_of(person)
		return not here.is_empty() and here[1].type == type
	var in_own_cell := func(person: Person) -> bool:
		var here := people.room_of(person)
		var home := people.home_room(person)
		return not here.is_empty() and not home.is_empty() and here[1] == home[1]
	for i in 25 * 60 * 2:
		clock.advance(0.5)
		match clock.time_text():
			"07:10":
				if not checked.has("doors open"):
					checked["doors open"] = true
					_check(not runner.doors.is_empty() and not runner.doors.values().has(true),
							"cell doors are open in the day")
			"12:15":
				if not checked.has("lunch"):
					checked["lunch"] = true
					# Bar anyone nipping out because they're bursting: the last
					# cell has no toilet of its own.
					var away := people.people.filter(func(p: Person) -> bool:
						return not in_room.call(p, &"canteen") and p.target_tag != &"toilet")
					_check(away.is_empty(), "at 12:15 everyone is in the canteen (not %s)" % [away.map(
							func(p: Person) -> String: return "%s: %s, %s" % [p.name, p.activity, p.reason])])
					_check(not people.people.any(func(p: Person) -> bool:
							return p.out_of_place and p.target_tag != &"toilet"), "and nobody is out of place")
			"22:00":
				if not checked.has("night"):
					checked["night"] = true
					_check(people.people.all(in_own_cell), "at 22:00 everyone is in their own cell")
					_check(runner.doors.size() == 6 and not runner.doors.values().has(false),
							"with every cell door locked")
					var person: Person = people.people[0]
					var outside := Vector2(main.map.land_bounds().position) + Vector2(1.5, 1.5)
					_check(not people.send(person, 0, outside), "nobody gets out of a locked cell")
			"03:00":
				if not checked.has("asleep"):
					checked["asleep"] = true
					# Bar anyone up for the toilet.
					var awake := people.people.filter(func(p: Person) -> bool:
							return p.activity != "Sleeping" and p.target_tag != &"toilet")
					_check(awake.is_empty(), "in the night everyone is asleep (not %s)" % [awake.map(
							func(p: Person) -> String: return "%s: %s, %s" % [p.name, p.activity, p.reason])])
	_check(checked.size() == 4, "the day ran through (checked %s)" % [checked.keys()])
	_check(not runner.doors.values().has(true), "in the morning the cell doors open again (%s at %s: %s)" % [
			runner.current().id, clock.time_text(), runner.doors])
	_check(people.people.all(func(p: Person) -> bool: return p.needs[&"hunger"] > 0.0 and p.needs[&"sleep"] > 0.0),
			"the default day keeps up with hunger and sleep")
	# Painting the timetable changes the block straight away.
	var hour := clock.hour()
	main.timetable.paint(hour) # The first swatch: Sleep.
	_check(runner.current().id == &"sleep" and people.people.all(func(p: Person) -> bool: return p.block.id == &"sleep"),
			"painting the current hour puts everyone in the new block")
	_check(PrisonCatalogue.SCHEDULE.at(hour).id != &"sleep" or hour < 7 or hour >= 22,
			"painting the game's timetable leaves the catalogue's alone")
	# Someone who can't get where they should be is flagged once they're late.
	main.free()
	main = load("res://games/prison/main.tscn").instantiate()
	main.sample = 7 # Locked out: the canteen can't be reached.
	root.add_child(main)
	main.clock.speed_index = 0
	for i in 20:
		main.clock.advance(0.5)
	_check(main.people.people.all(func(p: Person) -> bool: return not p.out_of_place),
			"before 15 minutes, nobody is late yet")
	for i in 20:
		main.clock.advance(0.5)
	_check(main.people.people.all(func(p: Person) -> bool: return p.out_of_place),
			"after 15 minutes, people who can't reach the canteen are out of place")
	main.free()


func _test_mood_model() -> void:
	var model := MoodModel.new()
	_check(is_equal_approx(model.need_points(100.0), 5.0) and is_zero_approx(model.need_points(55.0)),
			"a well met need adds a little to mood, a middling one nothing")
	_check(is_equal_approx(model.need_points(27.5), -5.0) and is_equal_approx(model.need_points(15.0), -10.0)
			and is_equal_approx(model.need_points(0.0), -20.0), "low needs take off more, run-out ones most")
	var person := Person.new()
	person.needs = {&"hunger": 100.0, &"sleep": 10.0}
	var meal := MoodletDef.new()
	meal.id = &"meal"
	meal.display_name = "Had a meal"
	meal.mood = -6.0
	person.moodlets[&"meal"] = 60.0
	var hothead := TraitDef.new()
	hothead.bad_mood_scale = 1.5
	person.traits = [hothead]
	var parts := model.parts(person, PrisonCatalogue.NEEDS, {&"meal": meal}, [["Nice cell", 2.0]])
	_check(parts[0][0] == "Tired" and parts[1][0] == "Had a meal" and is_equal_approx(parts[1][1], -9.0),
			"mood parts come biggest first, with bad moodlets worse for a hothead (got %s)" % [parts])
	var total := model.target(parts)
	_check(is_equal_approx(total, 50.0 + 5.0 - 13.333333 - 9.0 + 2.0), "mood adds its parts to 50 (got %f)" % total)
	_check(is_equal_approx(model.follow(50.0, [["Great", 40.0]], 30.0), 70.0), "mood follows its parts gently")
	_check(model.face(80.0) == MoodModel.Face.BEAMING and model.face(20.0) == MoodModel.Face.ANGRY,
			"mood shows as a face")


func _test_room_quality() -> void:
	var map := BuildingMap.new(Rect2i(0, 0, 20, 20))
	map.register_styles(PrisonCatalogue.FLOORS, PrisonCatalogue.WALLS)
	map.build_room(Rect2i(2, 2, 2, 3), &"concrete", &"brick")
	var cell := PrisonCatalogue.room_type(&"cell")
	map.set_room_type(map.room_at(Vector2i(2, 2)), &"cell")
	map.place_object(PrisonCatalogue.object(&"bed"), Vector2(2, 2), 0)
	var quality := RoomQuality.assess(map, map.room_at(Vector2i(2, 2)), cell)
	_check(is_zero_approx(quality.score) and quality.parts.any(func(p: Array) -> bool: return p[0] == "No window"),
			"a bare cell of the ideal size is plain (got %s)" % [quality.parts])
	map.set_opening(Vector3i(3, 2, BuildingMap.EDGE_X), BuildingMap.Wall.WINDOW, BuildingMap.WINDOW_BARS)
	map.place_object(PrisonCatalogue.object(&"poster"), Vector2(3, 2), 0)
	quality = RoomQuality.assess(map, map.room_at(Vector2i(2, 2)), cell)
	_check(is_equal_approx(quality.score, 3.0), "a window and a poster make it nicer (got %f)" % quality.score)
	map.place_object(PrisonCatalogue.object(&"bed"), Vector2(3, 3), 0)
	quality = RoomQuality.assess(map, map.room_at(Vector2i(2, 2)), cell)
	_check(is_equal_approx(quality.score, -1.0) and quality.parts[0][0] == "Cramped",
			"two beds in it make it cramped (got %s)" % [quality.parts])
	_check(quality.star_text() == "★★☆☆☆" or quality.stars() == 2.5, "quality shows as stars (got %s)" % quality.star_text())
	map.build_room(Rect2i(8, 2, 6, 4), &"wood", &"plaster")
	var dorm := PrisonCatalogue.room_type(&"dorm")
	map.place_object(PrisonCatalogue.object(&"bed"), Vector2(8, 2), 0)
	map.place_object(PrisonCatalogue.object(&"bed"), Vector2(9, 2), 0)
	map.place_object(PrisonCatalogue.object(&"toilet"), Vector2(13.5, 2), 0)
	map.place_object(PrisonCatalogue.object(&"shower"), Vector2(13.25, 5.25), 0)
	var room := map.room_at(Vector2i(8, 2))
	_check(dorm.problems(room, map) == PackedStringArray(["Needs 4 beds"]), "a dorm needs four beds (got %s)" % dorm.problems(room, map))
	map.place_object(PrisonCatalogue.object(&"bed"), Vector2(10, 2), 0)
	map.place_object(PrisonCatalogue.object(&"bed"), Vector2(11, 2), 0)
	room = map.room_at(Vector2i(8, 2))
	_check(dorm.problems(room, map).is_empty(), "and then it works")
	quality = RoomQuality.assess(map, room, dorm)
	_check(quality.parts.any(func(p: Array) -> bool: return p[0] == "Not much privacy")
			and quality.parts.any(func(p: Array) -> bool: return p[0] == "Nice floor"),
			"a dorm lacks privacy, and a wooden floor is nice (got %s)" % [quality.parts])


func _test_traits_and_choices() -> void:
	var building := Building.new(Rect2i(0, 0, 20, 20), PrisonCatalogue.FLOORS, PrisonCatalogue.WALLS)
	var map := building.ground()
	map.build_room(Rect2i(2, 2, 8, 6), &"wood", &"plaster")
	map.place_object(PrisonCatalogue.object(&"radio"), Vector2(2, 2), 0)
	map.place_object(PrisonCatalogue.object(&"bookshelf"), Vector2(8, 2), 0)
	var people := People.new()
	people.needs = PrisonCatalogue.NEEDS
	people.traits = PrisonCatalogue.TRAITS
	people.moodlet_defs = PrisonCatalogue.moodlets()
	people.building = building
	var everyone_fine := true
	for i in 40:
		var person := people.add_person(0, Vector2(14.5, 14.5))
		var first: TraitDef = person.traits[0]
		var second: TraitDef = person.traits[1]
		everyone_fine = everyone_fine and person.traits.size() == 2 and first != second \
				and first.opposite != second.id and second.opposite != first.id
	_check(everyone_fine, "everyone gets two traits, never opposites")
	for person in people.people.duplicate():
		people.remove_person(person)
	# A Bookworm picks the bookshelf over a radio just as near.
	var reader := people.add_person(0, Vector2(5.5, 3.5), "Reader")
	reader.traits = [PrisonCatalogue.TRAITS.filter(func(t: TraitDef) -> bool: return t.id == &"bookworm")[0]]
	for need: StringName in reader.needs:
		reader.needs[need] = 100.0
	reader.needs[&"recreation"] = 30.0
	people.step(0.5)
	_check(reader.target_tag == &"book", "a bookworm reaches for a book (got %s)" % reader.target_tag)
	# A Gentle soul calms the people near them.
	var gentle := people.add_person(0, Vector2(4.5, 6.5), "Calm")
	gentle.traits = [PrisonCatalogue.TRAITS.filter(func(t: TraitDef) -> bool: return t.id == &"gentle")[0]]
	var other := people.add_person(0, Vector2(5.5, 6.5), "Other")
	other.traits = []
	for person: Person in [gentle, other]:
		for need: StringName in person.needs:
			person.needs[need] = 100.0
		person.timer = 100.0 # Standing still rather than wandering off.
	for i in 2:
		people.step(0.5)
	_check(other.moodlets.has(&"calmed") and not gentle.moodlets.has(&"calmed"), "a gentle soul calms those near them")
	_check(other.in_company, "and is company")
	# Running out of bladder with no toilet is an accident.
	other.needs[&"bladder"] = 0.1
	other.needs[&"hygiene"] = 80.0
	people.step(1.0)
	_check(other.moodlets.has(&"had_an_accident") and other.needs[&"bladder"] == 100.0
			and other.needs[&"hygiene"] < 40.0, "with no toilet, bladder running out is an accident")
	people.free()


## Two days in the starter prison: urgent needs, moodlets, the yard and
## the mood they all add up to.
func _test_needs_in_a_day() -> void:
	var main: Node = load("res://games/prison/main.tscn").instantiate()
	main.sample = 0
	root.add_child(main)
	var clock: GameClock = main.clock
	var people: People = main.people
	clock.speed_index = 0
	var checked := {}
	var bursting: Person = people.people[0]
	var hungry: Person = people.people[1]
	var lowest_mood := 100.0
	var in_canteen := func(person: Person) -> bool:
		var here := people.room_of(person)
		return not here.is_empty() and here[1].type == &"canteen"
	for i in 38 * 60 * 2:
		clock.advance(0.5)
		if clock.day() == 1:
			continue
		for person in people.people:
			lowest_mood = minf(lowest_mood, person.mood)
		match clock.time_text():
			"12:20":
				if not checked.has("bursting"):
					checked["bursting"] = true
					_check(in_canteen.call(bursting), "lunch starts in the canteen")
					bursting.needs[&"bladder"] = 10.0
			"12:30":
				if not checked.has("toilet"):
					checked["toilet"] = true
					_check(not in_canteen.call(bursting) or bursting.target_tag == &"toilet"
							or bursting.needs[&"bladder"] > 90.0,
							"a prisoner who is bursting leaves lunch for a toilet (%s)" % bursting.activity)
			"12:55":
				if not checked.has("meal"):
					checked["meal"] = true
					_check(people.people.filter(func(p: Person) -> bool:
							return p.moodlets.has(&"good_meal") or p.moodlets.has(&"lovely_meal")).size() >= 4,
							"most people enjoyed their lunch")
			"14:00":
				if not checked.has("yard"):
					checked["yard"] = true
					_check(people.people.filter(func(p: Person) -> bool: return p.outdoors).size() >= 5,
							"in the yard, people are outdoors")
					_check(people.people.all(func(p: Person) -> bool: return p.needs[&"social"] > 60.0),
							"and in good company")
					_check(people.people.all(func(p: Person) -> bool: return p.needs[&"outdoors"] > 80.0),
							"and get their fresh air")
			"19:55":
				if not checked.has("hungry"):
					checked["hungry"] = true
					hungry.needs[&"hunger"] = 20.0
			"20:05":
				if not checked.has("locked up hungry"):
					checked["locked up hungry"] = true
					_check(hungry.moodlets.has(&"locked_up_hungry"), "locked up hungry is a moodlet")
					var cell_part := func(p: Person) -> bool:
						return p.mood_parts.any(func(part: Array) -> bool: return part[0] == "Nice cell to sleep in")
					_check(people.people.any(cell_part), "a cell with a window is nice to sleep in")
	_check(checked.size() == 6, "the day ran through (checked %s)" % [checked.keys()])
	var average := 0.0
	for person in people.people:
		average += person.mood / people.people.size()
	_check(average > 45.0 and average < 95.0, "the starter prison keeps people fairly happy (%d)" % average)
	_check(lowest_mood > 15.0, "nobody gets furious in it (lowest %d)" % lowest_mood)
	# The inspector explains a person and a room.
	var inspector: Inspector = main.inspector
	inspector.select(bursting)
	inspector._refresh_person(bursting)
	_check(inspector._mood_text.text.contains("Why?"), "the inspector says why someone feels as they do")
	var home: Array = people.home_room(bursting)
	inspector.select(home[1], home[0])
	main.free()


## The basic needs (sleep, hunger, hygiene and bladder) every person in
## the build can reach an object for.
## The Staff wing sample: zones keep prisoners out of the staff room and
## office, a staff door lets only staff through, locked doors stop all but
## staff, and the zones tool locks doors by hand until the block changes.
func _test_zones_and_doors() -> void:
	var main: Node = load("res://games/prison/main.tscn").instantiate()
	main.sample = 8
	root.add_child(main)
	var people: People = main.people
	var runner: ScheduleRunner = main.runner
	var map: BuildingMap = main.map
	var clock: GameClock = main.clock
	clock.speed_index = 0
	var o: Vector2i = main.building.land[0].get_center() - Vector2i(10, 8)
	var at := func(x: int, z: int) -> Vector2: return Vector2(o + Vector2i(x, z)) + Vector2(0.5, 0.5)
	var prisoner: Person = people.people[0]
	var staff: Person = people.people[6]
	_check(staff.group == &"staff" and not staff.needs.has(&"sleep") and not staff.has_bed(),
			"staff have their own needs and no bed")
	var staff_room := map.room_at(o + Vector2i(13, 8))
	var office := map.room_at(o + Vector2i(17, 3))
	_check(people.access.zone_of(staff_room).id == &"staff" and people.access.zone_of(office).id == &"staff",
			"the staff room and office are staff only")
	_check(people.access.zone_of(map.room_at(o + Vector2i(1, 1))).id == &"shared",
			"cells go by the usual zone")
	_check(not people.can_reach(prisoner, 0, at.call(17, 3)), "prisoners can't get into the office")
	_check(people.can_reach(staff, 0, at.call(17, 3)), "staff can")
	_check(people.can_reach(prisoner, 0, at.call(6, 7)), "prisoners can get to the canteen")

	# The staff door keeps prisoners out even of a room they may be in.
	map.set_room_zone(staff_room, &"everyone")
	staff_room = map.room_at(o + Vector2i(13, 8))
	_check(not people.can_reach(prisoner, 0, at.call(13, 8)), "a staff door stops prisoners")
	_check(people.can_reach(staff, 0, at.call(13, 8)), "but not staff")
	var staff_door := BuildingMap.edge_between(o + Vector2i(13, 5), o + Vector2i(13, 4))
	map.set_door(staff_door, true)
	_check(map.door_kind_at(staff_door) == &"", "a door put back in plain forgets it was a staff door")
	_check(people.can_reach(prisoner, 0, at.call(13, 8)), "a plain door lets prisoners into a room open to them")
	map.set_door(staff_door, true, &"staff")
	map.set_room_zone(map.room_at(o + Vector2i(13, 8)), &"staff")

	# Locked by hand from the zones tool, until the block changes.
	var canteen_door := BuildingMap.edge_between(o + Vector2i(3, 5), o + Vector2i(3, 4))
	var controller: BuildController = main.controller
	controller.tool = BuildController.Tool.ZONE
	controller._has_hover = true
	controller._hover_point = Vector2(o + Vector2i(3, 5)) + Vector2(0.5, 0.1)
	controller._on_press()
	_check(people.is_door_locked(0, canteen_door), "clicking a door with the zones tool locks it")
	_check(runner.overrides.has(Vector4i(0, canteen_door.x, canteen_door.y, canteen_door.z)),
			"as an override, with a padlock")
	_check(not people.can_reach(prisoner, 0, at.call(6, 7)), "prisoners can't get through a locked door")
	_check(people.can_reach(staff, 0, at.call(6, 7)), "staff have keys")
	var block := runner.current()
	while runner.current() == block:
		clock.advance(1.0)
	_check(not people.is_door_locked(0, canteen_door), "a door locked by hand opens when the block changes")
	runner.toggle_lock(0, canteen_door, true)
	block = runner.current()
	while runner.current() == block:
		clock.advance(1.0)
	_check(people.is_door_locked(0, canteen_door), "unless it was pinned")
	runner.toggle_lock(0, canteen_door, true)
	_check(not people.is_door_locked(0, canteen_door) and runner.overrides.is_empty(),
			"Shift-clicking a pinned door lets it go back to the timetable")

	# Someone caught in a room painted staff only walks out of it.
	var caught: Person = people.people[1]
	people.send(caught, 0, at.call(16, 3))
	for i in 60:
		clock.advance(0.5)
	people._stop(caught)
	caught.position = Vector3(at.call(17, 4).x, 0.0, at.call(17, 4).y)
	var left := false
	for i in 120:
		clock.advance(0.5)
		var here := people.room_of(caught)
		if here.is_empty() or here[1] != map.room_at(o + Vector2i(17, 3)):
			left = true
			break
	_check(left, "a prisoner in a staff-only room leaves it (%s, %s)" % [caught.activity, caught.reason])

	# A whole day: prisoners never set foot in the staff rooms.
	var trespass := []
	for i in 24 * 60:
		clock.advance(1.0)
		for person in people.people:
			var here := people.room_of(person)
			if person.group == &"prisoner" and not here.is_empty() \
					and not people.may_enter(person, here[1]) and not trespass.has(person.name):
				trespass.append(person.name)
	_check(trespass.is_empty(), "over a day, no prisoner goes where they may not (%s)" % [trespass])
	root.remove_child(main)
	main.free()


## Someone who stops part way up the stairs (a block changing mid-climb)
## can still find a way off them.
func _test_jobs_and_carrying() -> void:
	var main: Node = load("res://games/prison/main.tscn").instantiate()
	main.sample = 8
	root.add_child(main)
	var people: People = main.people
	var jobs: JobBoard = main.jobs
	var items: ItemStore = main.items
	var map: BuildingMap = main.map
	var clock: GameClock = main.clock
	clock.speed_index = 0
	var o: Vector2i = main.building.land[0].get_center() - Vector2i(10, 8)
	var shelf := ObjectDef.new()
	shelf.id = &"test_shelf"
	shelf.display_name = "Shelf"
	shelf.holds = [&"food"]
	shelf.capacity = 4
	var crate := ItemDef.new()
	crate.id = &"crate"
	crate.tags = [&"food"]
	var from := map.place_object(shelf, Vector2(o + Vector2i(1, 6)), 0)
	var to := map.place_object(shelf, Vector2(o + Vector2i(6, 8)), 0)
	_check(from != -1 and to != -1, "shelves for the jobs test go in the canteen")
	var handy: Person = people.people[6]
	for need: StringName in handy.needs:
		handy.needs[need] = 100.0
	people.set_role(handy, &"handyman")
	_check(jobs.wants_work(handy) and not jobs.wants_work(people.people[0]),
			"staff with a role work from the board, prisoners off a programme don't")
	items.put_in(Vector2i(0, from), map.objects[from], crate, 3)
	var finished: Array[Job] = []
	jobs.job_finished.connect(func(job: Job, _worker: Person) -> void: finished.append(job))
	var carry := jobs.post(Job.carry(&"food", 2, Job.at(Job.Do.FETCH, 0, from), Job.at(Job.Do.DELIVER, 0, to)))
	carry.title = "Carry food"
	var minutes := 0
	while not carry.done and minutes < 120:
		clock.advance(1.0)
		minutes += 1
	_check(carry.done and finished.has(carry), "a handyman carries food from one shelf to another")
	_check(items.count_in(Vector2i(0, from), &"food") == 1 and items.count_in(Vector2i(0, to), &"food") == 2,
			"two crates moved, one left")
	_check(handy.job == null and jobs.of_kind(&"carry").is_empty(), "the job is off the board once done")

	# Called away mid-carry, what they hold goes down where they are and
	# the job starts again from there.
	var second := jobs.post(Job.carry(&"food", 1, Job.at(Job.Do.FETCH, 0, from), Job.at(Job.Do.DELIVER, 0, to)))
	minutes = 0
	while items.carrying(handy) == null and minutes < 120:
		clock.advance(0.5)
		minutes += 1
	_check(items.carrying(handy) == crate, "they pick the crate up")
	people.set_role(handy, &"")
	_check(items.carrying(handy) == null and not items.floor_spots_of(&"food").is_empty(),
			"dropped where they were when their role went")
	_check(second.worker == null and second.current().do == Job.Do.FETCH and not second.current().at_object(),
			"the job goes back on the board to pick it up off the floor")
	people.set_role(handy, &"handyman")
	minutes = 0
	while not second.done and minutes < 120:
		clock.advance(1.0)
		minutes += 1
	_check(second.done and items.count_in(Vector2i(0, to), &"food") == 3 and items.floor_spots_of(&"food").is_empty(),
			"and someone finishes it from the floor")

	# No room where it goes: what doesn't fit is left on the floor and the
	# job waits with the reason.
	items.put_in(Vector2i(0, from), map.objects[from], crate, 3)
	var third := jobs.post(Job.carry(&"food", 3, Job.at(Job.Do.FETCH, 0, from), Job.at(Job.Do.DELIVER, 0, to)))
	minutes = 0
	while third.reason.is_empty() and minutes < 120:
		clock.advance(0.5)
		minutes += 1
	_check(third.reason == "No room to put it down" and third.wait > 0.0 and not third.done,
			"a full shelf stops the job, with a reason")
	_check(items.count_in(Vector2i(0, to)) == 4 and items.total(&"food") == 6,
			"one fits, the rest are put down, none lost")
	jobs.cancel(third)
	_check(jobs.of_kind(&"carry").is_empty() and handy.job == null, "a cancelled job leaves the board")
	main.queue_free()


func _test_kitchen() -> void:
	var main: Node = load("res://games/prison/main.tscn").instantiate()
	main.sample = 9
	root.add_child(main)
	var people: People = main.people
	var items: ItemStore = main.items
	var jobs: JobBoard = main.jobs
	var kitchen: Kitchen = main.kitchen
	var clock: GameClock = main.clock
	var map: BuildingMap = main.map
	clock.speed_index = 0
	_check(kitchen.meals_per_day() == 3, "three meals a day on the prisoners' timetable")
	_check(items.total(&"ingredient") == 6 and jobs.of_kind(&"carry").size() == 3,
			"the lorry leaves two days of crates and the handyman is given them to put away")
	_check(items.total(&"meal") == 6, "starting at breakfast, the meal is already out")
	var fetched := false
	var minutes := 0
	while minutes < 60:
		clock.advance(0.5)
		minutes += 1
		for person in people.people:
			var held := items.carrying(person)
			fetched = fetched or (held != null and held.has_tag(&"meal") and person.target_tag == &"table")
	_check(fetched, "prisoners carry a tray from the counter to a table")
	var pallet := map.objects.values().filter(func(p: BuildingMap.PlacedObject) -> bool:
			return p.def.id == &"delivery_pallet")[0] as BuildingMap.PlacedObject
	while clock.hour() != 11:
		clock.advance(1.0)
	_check(items.count_in(Vector2i(0, pallet.id)) == 0, "the delivery is all put away")
	_check(jobs.of_kind(&"cook").size() >= 1, "cooking starts an hour before lunch")
	var missed := false
	while clock.day() < 2 or clock.hour() < 8:
		clock.advance(1.0)
		for person in people.people:
			missed = missed or person.moodlets.has(&"missed_meal")
	_check(not missed, "nobody misses a meal for a day and a half")
	_check(items.total(&"ingredient") >= 4, "the morning lorry tops up the stock")

	# Without a cooker, nothing is cooked and meals are missed, softly.
	for placed: BuildingMap.PlacedObject in map.objects.values().duplicate():
		if placed.def.id == &"cooker":
			map.remove_object(placed.id)
	for key: Vector2i in items.held.keys():
		items.take_from(key, &"meal", 99)
	while clock.hour() != 12:
		clock.advance(1.0)
	_check(jobs.of_kind(&"cook").is_empty(), "nothing to cook on, so no cooking")
	clock.advance(45.0)
	missed = false
	for person in people.people:
		missed = missed or person.moodlets.has(&"missed_meal")
	_check(missed, "with an empty counter, prisoners miss the meal")
	main.queue_free()


func _test_cleaning() -> void:
	var main: Node = load("res://games/prison/main.tscn").instantiate()
	main.sample = 9
	root.add_child(main)
	var people: People = main.people
	var items: ItemStore = main.items
	var cleaning: Cleaning = main.cleaning
	var clock: GameClock = main.clock
	var map: BuildingMap = main.map
	clock.speed_index = 0
	var o: Vector2i = main.building.land[0].get_center() - Vector2i(10, 8)
	var canteen := map.room_at(o + Vector2i(4, 7))
	var before := people.quality(0, canteen).score
	var paper := PrisonCatalogue.LITTER[0]
	var spot := Vector3i(0, o.x + 4, o.y + 9)
	items.drop_on_floor(spot, paper, 3)
	var after := people.quality(0, canteen)
	_check(after.score < before and after.parts.any(func(p: Array) -> bool: return p[0] == "Litter about"),
			"litter makes a room worse")
	var bins := map.objects.values().filter(func(p: BuildingMap.PlacedObject) -> bool: return p.def.id == &"bin")
	var skip := map.objects.values().filter(func(p: BuildingMap.PlacedObject) -> bool:
			return p.def.id == &"skip")[0] as BuildingMap.PlacedObject
	var in_bins := func() -> int:
		return bins.reduce(func(sum: int, p: BuildingMap.PlacedObject) -> int:
				return sum + items.count_in(Vector2i(0, p.id), &"litter"), 0)
	var minutes := 0
	while items.count_on_floor(spot) > 0 and minutes < 240:
		clock.advance(1.0)
		minutes += 1
	_check(items.count_on_floor(spot) == 0, "the cleaner sweeps it up")
	minutes = 0
	while in_bins.call() < 3 and minutes < 60:
		clock.advance(1.0)
		minutes += 1
	_check(in_bins.call() >= 3, "and puts it in a bin")
	var bin := bins[0] as BuildingMap.PlacedObject
	items.put_in(Vector2i(0, bin.id), bin, paper, bin.def.capacity)
	minutes = 0
	while items.count_in(Vector2i(0, skip.id)) == 0 and minutes < 240:
		clock.advance(1.0)
		minutes += 1
	_check(items.count_in(Vector2i(0, skip.id), &"rubbish_bag") >= 1, "a full bin is bagged up and taken to the skip")
	_check(cleaning.collect() >= 1 and items.count_in(Vector2i(0, skip.id)) == 0, "the lorry empties the skip")
	main.queue_free()


func _test_laundry() -> void:
	var main: Node = load("res://games/prison/main.tscn").instantiate()
	main.sample = 9
	root.add_child(main)
	var items: ItemStore = main.items
	var clock: GameClock = main.clock
	clock.speed_index = 0
	_check(items.total(&"clean_laundry") == 9, "the shelves start with a clean uniform each and spares")
	var changed: Array[int] = [0] # Lambdas capture a copy of an int.
	main.people.used.connect(func(person: Person, placed: BuildingMap.PlacedObject) -> void:
		if placed.def.id == &"shower" and person.group == &"prisoner":
			changed[0] += 1)
	var most_dirty := 0
	while clock.hour() != 9:
		clock.advance(1.0)
		most_dirty = maxi(most_dirty, items.total(&"dirty_laundry"))
		_check(items.total(&"dirty_laundry") + items.total(&"clean_laundry") == 9, "no uniform goes missing")
	_check(changed[0] > 0 and most_dirty >= mini(changed[0], Laundry.LOAD),
			"after a shower, prisoners leave their uniform in the basket and take a clean one")
	# A part load waits in the basket while the shelves have plenty, and
	# someone may shower again in the meantime.
	var minutes := 0
	while items.total(&"dirty_laundry") >= Laundry.LOAD and minutes < 600:
		clock.advance(1.0)
		minutes += 1
	_check(items.total(&"dirty_laundry") < Laundry.LOAD, "the cleaner washes it")
	var shelf := main.map.objects.values().filter(func(p: BuildingMap.PlacedObject) -> bool:
			return p.def.id == &"clothes_shelf")[0] as BuildingMap.PlacedObject
	var put_away := func() -> bool:
		return items.count_in(Vector2i(0, shelf.id), &"clean_laundry") + items.total(&"dirty_laundry") == 9
	minutes = 0
	while not put_away.call() and minutes < 120:
		clock.advance(1.0)
		minutes += 1
	_check(put_away.call(), "irons it and stacks it back on the shelf")
	main.queue_free()


func _test_work_programmes() -> void:
	var main: Node = load("res://games/prison/main.tscn").instantiate()
	main.sample = 9
	root.add_child(main)
	var people: People = main.people
	var jobs: JobBoard = main.jobs
	var clock: GameClock = main.clock
	clock.speed_index = 0
	var maker: Person = people.people.filter(func(p: Person) -> bool: return p.programme == &"workshop")[0]
	var idle: Person = people.people.filter(func(p: Person) -> bool:
			return p.group == &"prisoner" and p.programme == &"")[0]
	_check(jobs.of_kind(&"make").size() == 2, "a making job waits at each workbench")
	_check(not jobs.wants_work(maker), "prisoners on a programme don't work outside work blocks")
	while not main.runner.current().jobs:
		clock.advance(1.0)
	_check(jobs.wants_work(maker) and not jobs.wants_work(idle), "in a work block they do; others have free time")
	_check(people.is_in_place(maker), "and they count as in place wherever the work is")
	var useful := false
	var minutes := 0
	while main.items.total(&"goods") == 0 and minutes < 180:
		clock.advance(1.0)
		minutes += 1
		useful = useful or maker.moodlets.has(&"useful_day") or maker.moodlets.has(&"made_to_work")
	_check(main.items.total(&"goods") > 0, "the workshop makes goods")
	minutes = 0
	while not useful and minutes < 30:
		clock.advance(1.0)
		minutes += 1
		useful = maker.moodlets.has(&"useful_day") or maker.moodlets.has(&"made_to_work")
	_check(useful, "a job done makes for a useful day")
	var made := 0
	for key: Vector2i in main.building.objects_tagged(Workshop.SHELVES):
		made += main.items.count_in(key, &"goods")
	_check(main.workshop.collect() == made and main.workshop.sold == made, "the lorry takes the goods to sell")
	main.queue_free()


## The Guarded prison: a guard at the post opens the security gate to the
## yard, the other patrols, and prisoners out of place are walked back.
func _test_guards() -> void:
	var main: Node = load("res://games/prison/main.tscn").instantiate()
	main.sample = 10
	root.add_child(main)
	var people: People = main.people
	var guarding: Guarding = main.guarding
	var shifts: Shifts = main.shifts
	var clock: GameClock = main.clock
	var jobs: JobBoard = main.jobs
	clock.speed_index = 0
	# Nobody acting up while the guards are tested.
	(main.misconduct as Misconduct).enabled = false
	_check(shifts.wanted_for(&"guard", &"day") == 2 and shifts.wanted_for(&"guard", &"night") == 1,
			"two guards by day and one by night")
	var gates := guarding.gate_locks()
	_check(gates.size() == 1 and gates.values()[0], "the security gate is locked with nobody at the post")
	# Bodies show their outfit and skin, and hats only for their role.
	var shown := func(person: Person) -> Array[String]:
		var body := people._make_body(person)
		var out: Array[String] = []
		for mesh: MeshInstance3D in body.find_children("*", "MeshInstance3D", true, false):
			if mesh.visible:
				out.append(String(mesh.name))
		body.free()
		return out
	var a_guard: Person = people.people.filter(func(p: Person) -> bool: return p.role == &"guard")[0]
	var a_prisoner: Person = people.people.filter(func(p: Person) -> bool: return p.group == &"prisoner")[0]
	var guard_parts: Array[String] = shown.call(a_guard)
	var prisoner_parts: Array[String] = shown.call(a_prisoner)
	_check(prisoner_parts.has("outfit") and prisoner_parts.has("skin") and not prisoner_parts.has("navy_guard"),
			"a prisoner's body shows, without a guard's cap: %s" % [prisoner_parts])
	_check(guard_parts.has("outfit") and guard_parts.has("navy_guard"), "a guard's body shows with their cap: %s" % [guard_parts])
	var key: Vector4i = gates.keys()[0]
	var edge := Vector3i(key.y, key.z, key.w)
	var cells := BuildingMap.edge_cells(edge)
	var prisoner: Person = people.people.filter(func(p: Person) -> bool: return p.group == &"prisoner")[0]
	var yard_side := Vector2(cells[1]) + Vector2(0.5, 0.5)
	_check(not people.can_reach(prisoner, 0, yard_side), "so prisoners can't get out to the yard")
	var minutes := 0
	while guarding.manned_desks().is_empty() and minutes < 30:
		clock.advance(1.0)
		minutes += 1
	clock.advance(1.0)
	_check(not guarding.manned_desks().is_empty(), "a guard sits at the post")
	var standing: Array = people.people.filter(func(p: Person) -> bool:
		return p.group == &"prisoner" and p.state != Person.State.USING)
	_check(not people.is_door_locked(0, edge) and standing.any(func(p: Person) -> bool:
			return people.can_reach(p, 0, yard_side)), "which opens the gate for prisoners")
	var patrolling := false
	for i in 20:
		clock.advance(1.0)
		patrolling = patrolling or jobs.of_kind(&"patrol").any(func(j: Job) -> bool: return j.worker != null)
	_check(patrolling, "the other guard patrols")

	# A prisoner out of place near a guard gets walked back.
	var on_patrol := func() -> Array: return people.people.filter(func(p: Person) -> bool:
		return p.role == &"guard" and p.job != null and p.job.kind == &"patrol" and p.state == Person.State.USING)
	minutes = 0
	while on_patrol.call().is_empty() and minutes < 120:
		clock.advance(1.0)
		minutes += 1
	var guard: Person = on_patrol.call()[0]
	prisoner.out_of_place = true
	# Stopped first, as stopping someone mid-use puts them back where they stood.
	people.stop(prisoner)
	prisoner.position = guard.position
	prisoner.level = guard.level
	people._buckets_fresh = false
	guarding._walked_back.erase(prisoner)
	prisoner.moodlets.erase(&"walked_back")
	guarding._spot_out_of_place()
	_check(jobs.of_kind(&"escort").any(func(j: Job) -> bool: return j.get_meta(&"prisoner") == prisoner),
			"a guard who sees a prisoner out of place goes to walk them back")
	var led := false
	minutes = 0
	while not prisoner.moodlets.has(&"walked_back") and minutes < 60:
		clock.advance(1.0)
		minutes += 1
		led = led or guarding.is_led(prisoner)
	_check(led and prisoner.moodlets.has(&"walked_back") and not prisoner.led,
			"and walks them back, which they don't enjoy")

	# Patrol routes: drawn as a loop, and walked by the guards put on them.
	var routes: PatrolRoutes = main.routes
	var yard := Vector2(cells[1])
	main.controller.tool = BuildController.Tool.ROUTE
	routes.click(0, yard + Vector2(0.2, 1.3))
	routes.click(0, yard + Vector2(4.5, 1.5))
	routes.click(0, yard + Vector2(4.5, 3.5))
	routes.click(0, yard + Vector2(0.6, 1.4))
	_check(routes.routes.size() == 1 and routes.drawing == null and routes.routes[0].points.size() == 3
			and routes.routes[0].points[0] == yard + Vector2(0.5, 1.5),
			"the route tool draws a loop, closed by clicking the first point")
	var route: PatrolRoutes.Route = routes.routes[0]
	routes.set_guards(route, 1)
	var walking := false
	minutes = 0
	while not walking and minutes < 120:
		clock.advance(1.0)
		minutes += 1
		walking = jobs.of_kind(&"patrol").any(func(j: Job) -> bool:
			return j.has_meta(&"route") and j.worker != null and j.stage > 0)
	_check(walking, "a guard put on it walks round it")
	main.staff_window.refresh()
	_check(main.staff_window._route_counts[route].text == "1", "the Staff window lists it with its guard")
	routes.click(0, yard + Vector2(2.5, 1.5), true)
	clock.advance(1.0)
	_check(routes.routes.is_empty() and not jobs.of_kind(&"patrol").any(func(j: Job) -> bool:
			return j.has_meta(&"route")), "Ctrl-click removes it, and the guard stops")
	main.queue_free()


## Objects wear out with use and break; the handyman mends them.
func _test_wear_and_repair() -> void:
	var main: Node = load("res://games/prison/main.tscn").instantiate()
	main.sample = 9
	root.add_child(main)
	var people: People = main.people
	var wear: Wear = main.wear
	var jobs: JobBoard = main.jobs
	var clock: GameClock = main.clock
	clock.speed_index = 0
	var toilets: Array[Vector2i] = main.building.objects_tagged([&"toilet"] as Array[StringName])
	var key := toilets[0]
	var placed: BuildingMap.PlacedObject = main.building.object_at(key)
	for i in placed.def.uses_before_breaking - 1:
		wear.use(key)
	_check(not wear.is_broken(key), "a toilet takes plenty of use")
	wear.use(key)
	_check(wear.is_broken(key) and jobs.of_kind(&"repair").size() == 1, "then breaks, and a job goes up to mend it")
	_check(main.jobs_panel.describe().contains("Broken: toilet"), "the jobs panel says what's broken")
	var prisoner: Person = people.people.filter(func(p: Person) -> bool: return p.group == &"prisoner")[0]
	_check(not people._may_use(prisoner, key.x, placed), "nobody uses it while it's broken")
	var minutes := 0
	var mending := false
	while wear.is_broken(key) and minutes < 180:
		clock.advance(1.0)
		minutes += 1
		mending = mending or people.people.any(func(p: Person) -> bool:
			return p.role == &"handyman" and p.activity == "Mending the toilet")
	_check(mending and not wear.is_broken(key) and jobs.of_kind(&"repair").is_empty(),
			"the handyman mends it")
	var cooker: Vector2i = main.building.objects_tagged([&"cooker"] as Array[StringName])[0]
	var before: int = wear.uses.get(cooker, 0)
	while main.building.objects_tagged([&"cooker"] as Array[StringName]).all(func(k: Vector2i) -> bool: return wear.uses.get(k, 0) == 0) \
			and minutes < 600:
		clock.advance(1.0)
		minutes += 1
	_check(main.building.objects_tagged([&"cooker"] as Array[StringName]).any(func(k: Vector2i) -> bool: return wear.uses.get(k, 0) > 0),
			"work done at an object wears it too (cooker was %d)" % before)
	main.queue_free()


func _test_money() -> void:
	var main: Node = load("res://games/prison/main.tscn").instantiate()
	main.sample = 9
	root.add_child(main)
	var ledger: Ledger = main.ledger
	var clock: GameClock = main.clock
	var map: BuildingMap = main.building.ground()
	clock.speed_index = 0
	_check(ledger.balance == Finances.STARTING_MONEY, "a prison starts with some money, the sample free")
	var land := map.land_bounds()
	var rect := Rect2i(land.position + Vector2i(1, 1), Vector2i(3, 3))
	_check(not map.has_build_near(rect.grow(1)), "an empty corner to build in")
	var before := ledger.balance
	map.build_room(rect)
	var cost := before - ledger.balance
	# Nine tiles of concrete at 10 and twelve lengths of plaster wall at 30.
	_check(cost == 9 * 10 + 12 * 30, "building a room costs its floor and walls (%d)" % cost)
	_check(ledger.today.get("Building", 0) == -cost, "under the Building line")
	var bed: ObjectDef = PrisonCatalogue.object(&"bed")
	var id := map.place_object(bed, Vector2(rect.position) + Vector2(1, 1), 0)
	_check(id > 0 and before - ledger.balance == cost + bed.price, "a bed costs its price")
	map.remove_object(id)
	_check(before - ledger.balance == cost + bed.price - roundi(bed.price * BuildCosts.REFUND),
			"demolishing gives three quarters back")
	ledger.balance = -10
	_check(not main.controller.spending_allowed.call(), "nothing more can be built in debt")
	ledger.sandbox = true
	_check(main.controller.spending_allowed.call(), "except in sandbox")
	ledger.sandbox = false
	ledger.balance = 5000
	var day: ShiftDef = PrisonCatalogue.SHIFTS[0]
	var wages: int = main.finances.shift_wages(day)
	_check(wages > 0, "the day shift costs wages (%d)" % wages)
	var night: ShiftDef = PrisonCatalogue.SHIFTS[1]
	var paid: Array[int] = []
	var grant := 0
	for i in GameClock.MINUTES_PER_DAY * 2:
		var was: int = ledger.today.get("Wages", 0)
		clock.advance(1.0)
		if ledger.today.get("Wages", 0) != was:
			paid.append(was - ledger.today.get("Wages", 0))
		if ledger.closing.size() == 1 and grant == 0:
			grant = ledger.yesterday.get("Daily grant", 0)
		if paid.has(wages) and grant > 0:
			break
	_check(paid.has(wages) or paid.has(main.finances.shift_wages(night)), "wages are paid as a shift starts (%s)" % [paid])
	_check(grant > 0, "at midnight the grant comes in and the day closes")
	_check(main.finance_window != null and main.clock_bar._money.text != "", "the balance shows by the clock")
	main.queue_free()


func _test_intake() -> void:
	var main: Node = load("res://games/prison/main.tscn").instantiate()
	main.sample = 11
	root.add_child(main)
	var intake: Intake = main.intake
	var ledger: Ledger = main.ledger
	var people: People = main.people
	var clock: GameClock = main.clock
	clock.speed_index = 0
	_check(main.office.has_warden() and intake.warden_here(), "the paying prison has a warden in an office")
	_check(intake.warnings().is_empty() and intake.free_beds() == 4, "a reception and four free beds")
	intake.caps[&"high"] = 3
	intake.accepted = {&"low": false, &"medium": false, &"high": true}
	var fees: int = ledger.today.get("Intake fees", 0)
	# The bus drives in along the road; they step off when it stops.
	var ride := func() -> Array[Person]:
		var got: Array[Person] = intake.bus()
		var waited := 0
		while got.is_empty() and intake.bus_here() and waited < 60:
			var before := people.people.size()
			clock.advance(1.0)
			waited += 1
			if people.people.size() > before:
				got.assign(people.people.slice(before))
		return got
	var parked: int = main.vehicles.get_child_count()
	var bus_called := intake.bus()
	_check(bus_called.is_empty() and intake.bus_here() and main.vehicles.get_child_count() == parked + 1,
			"the bus drives in by road")
	var came: Array[Person] = []
	for i in 60:
		var before := people.people.size()
		clock.advance(1.0)
		if people.people.size() > before:
			came.assign(people.people.slice(before))
			break
	_check(came.size() == 3, "Monday's bus brings the warden's cap")
	_check(came.all(func(p: Person) -> bool: return p.category == &"high" and p.moodlets.has(Intake.FIRST_NIGHT)),
			"of the categories accepted, each feeling their first night")
	_check(ledger.today.get("Intake fees", 0) - fees == 3 * Intake.FEE, "and the prison is paid for each")
	_check(people.body_of(came[0]) == null or people._outfit(came[0]) == PrisonCatalogue.categories()[&"high"].outfit_colour,
			"high security prisoners wear their own colour")
	var searched := false
	for i in 240:
		clock.advance(1.0)
		searched = searched or came.any(func(p: Person) -> bool: return p.activity == "Being searched and signed in")
		if came.all(func(p: Person) -> bool: return not intake.is_arriving(p) and not p.led):
			break
	_check(searched, "arrivals are searched at reception")
	_check(came.all(func(p: Person) -> bool: return not intake.is_arriving(p) and p.has_bed()),
			"then signed in with a bed of their own")
	_check(not intake.bus_here(), "the bus drives off again")
	_check(intake.free_beds() == 1 and ride.call().size() == 1, "the next bus brings only as many as there are beds")
	_check(ride.call().is_empty() and intake.warnings()[0].begins_with("No free beds"), "and none when the cells are full")
	main.shifts.set_wanted(&"warden", &"day", 0)
	_check(not intake.warden_here() and intake.todays_count() == Intake.WITHOUT_WARDEN, "without a warden a couple come")
	intake.limit = 0
	_check(intake.todays_count() == 0 and intake.forecast().all(func(e: Array) -> bool: return e[2] == 0),
			"or none, closed")
	main.shifts.set_wanted(&"warden", &"day", 1)
	intake.caps = {&"low": 4, &"medium": 0, &"high": 0}
	intake.accepted = {&"low": true, &"medium": true, &"high": false}
	var week: Array = intake.forecast()
	_check(week.size() == 7 and week.all(func(e: Array) -> bool: return e[2] >= 1 and e[2] <= 4)
			and week.any(func(e: Array) -> bool: return e[1] == "Monday" and e[2] == 4), "a week ahead, Mondays full")
	var offer: Dictionary = intake._maybe_offer(true)
	_check(not offer.is_empty(), "the Ministry offers a transfer")
	var tomorrow: int = main.clock.day() + 1
	var before_plan: int = intake.plan_for(tomorrow).get(offer.category, 0)
	intake.accept_offer()
	_check(intake.offer.is_empty() and intake.plan_for(tomorrow).get(offer.category, 0) == before_plan + offer.count,
			"accepted, they come on tomorrow's bus")
	main.queue_free()


func _test_standing() -> void:
	var main: Node = load("res://games/prison/main.tscn").instantiate()
	main.sample = 11
	root.add_child(main)
	var standing: Standing = main.standing
	var ledger: Ledger = main.ledger
	_check(standing.grade == 3 and is_equal_approx(main.finances.grant_scale, 1.0), "a new prison starts at three stars")
	_check(standing.current_goals().size() == Standing.GOALS_SHOWN, "with a few grant goals to work on")
	main.shifts.set_wanted(&"warden", &"day", 0)
	_check(standing.check_goals().is_empty(), "which need a warden to claim")
	main.shifts.set_wanted(&"warden", &"day", 1)
	var finished := standing.check_goals()
	_check(finished.size() == 1 and finished[0].title == "Open a workshop" and ledger.today.get("Grants", 0) == 1500,
			"the paying prison's workshop wins its grant")
	_check(standing.current_goals().size() == Standing.GOALS_SHOWN, "and the next goal comes up")
	standing.grade_day()
	_check(standing.measures.size() == 4 and standing.grade >= 1 and standing.grade <= 5, "each midnight it is graded")
	var report := standing.write_report()
	_check(report.contains("★") and report.contains("Money:"), "and the morning report sums up yesterday")
	main.queue_free()


func _test_undo() -> void:
	var main: Node = load("res://games/prison/main.tscn").instantiate()
	main.sample = 9
	root.add_child(main)
	var undo: UndoHistory = main.undo
	var ledger: Ledger = main.ledger
	var map: BuildingMap = main.building.ground()
	_check(not undo.can_undo(), "nothing to undo in a new prison")
	var before := ledger.balance
	var walls := map.walls.size()
	var rect := Rect2i(map.land_bounds().position + Vector2i(1, 1), Vector2i(3, 3))
	map.build_room(rect)
	map.place_object(PrisonCatalogue.object(&"bed"), Vector2(rect.position) + Vector2(1, 1), 0)
	undo._flush()
	_check(undo.can_undo() and ledger.balance < before, "building can be undone")
	undo.undo()
	_check(map.walls.size() == walls and map.object_at(Vector2(rect.position) + Vector2(1.5, 1.5)) == null,
			"undo takes the room and the bed away in one step")
	_check(ledger.balance == before, "and gives all the money back")
	undo.redo()
	_check(map.walls.size() == walls + 12 and map.object_at(Vector2(rect.position) + Vector2(1.5, 1.5)) != null,
			"redo puts them back")
	main.terrain.set_corners({Vector2i(2, 2): 3.0})
	undo._flush()
	undo.undo()
	_check(not is_equal_approx(main.terrain.corner_height(Vector2i(2, 2)), 3.0), "the land can be undone too")
	main.queue_free()


func _test_saving() -> void:
	var main: Node = load("res://games/prison/main.tscn").instantiate()
	main.sample = 11
	root.add_child(main)
	var clock: GameClock = main.clock
	clock.speed_index = 0
	for i in 150:
		clock.advance(1.0)
	main.intake.bus()
	var map: BuildingMap = main.building.ground()
	map.build_room(Rect2i(map.land_bounds().position + Vector2i(1, 6), Vector2i(3, 3)))
	main.ledger.sandbox = true
	main.schedule.set_hour(3, PrisonCatalogue.ACTIVITIES[0])
	var data := PrisonSave.capture(main)
	_check(PrisonSave.write("test", data) == OK and not PrisonSave.read("test").is_empty(), "a prison saves to a file")
	var names: Array = main.people.people.filter(func(p: Person) -> bool: return not p.going_home) \
			.map(func(p: Person) -> String: return p.name)
	var walls: int = map.walls.size()
	var minutes: float = clock.total_minutes
	var balance: int = main.ledger.balance
	var shelf: int = main.items.total(&"ingredient")
	var was: Dictionary[String, Array] = {}
	for p: Person in main.people.people:
		was[p.name] = [p.state, p.target_tag, p.route.size(), p.job != null, p.position]
	main.queue_free()

	PrisonSave.pending = PrisonSave.read("test")
	var loaded: Node = load("res://games/prison/main.tscn").instantiate()
	root.add_child(loaded)
	var again: Array = loaded.people.people.map(func(p: Person) -> String: return p.name)
	_check(again.size() >= names.size() - 1 and names.all(func(n: String) -> bool: return again.has(n) or n.is_empty()),
			"everyone comes back by name (%d of %d)" % [again.size(), names.size()])
	_check(loaded.building.ground().walls.size() == walls, "the build comes back, new room and all")
	_check(is_equal_approx(loaded.clock.total_minutes, minutes), "and the time")
	_check(loaded.ledger.balance == balance and loaded.ledger.sandbox, "and the money")
	_check(loaded.schedule.at(3) == PrisonCatalogue.ACTIVITIES[0], "and the timetable")
	_check(loaded.items.total(&"ingredient") == shelf, "and the food on the shelves")
	_check(loaded.people.people.filter(func(p: Person) -> bool: return p.group == &"prisoner").all(
			func(p: Person) -> bool: return p.category != &""), "and each prisoner's category")
	_check(loaded.title == "Paying prison", "under its name")
	_check(PrisonSave.describe(PrisonSave.read("test")).begins_with("Paying prison · Day 1"), "and saves say what's in them")
	var same_doing := 0
	var workers := 0
	for p: Person in loaded.people.people:
		var then: Array = was.get(p.name, [])
		if then.is_empty():
			continue
		if p.state == then[0] and p.target_tag == then[1] and p.route.size() == then[2] \
				and p.position.is_equal_approx(then[4]):
			same_doing += 1
		if then[3]:
			workers += 1
	_check(same_doing >= was.size() - 2, "everyone carries on mid-walk or mid-meal (%d of %d)" % [same_doing, was.size()])
	# Jobs can finish in the meantime, so count anyone back at one at all.
	var resumed: Dictionary[Person, bool] = {}
	for i in 4:
		for p: Person in loaded.people.people:
			if p.job != null and not was.get(p.name, []).is_empty() and was[p.name][3]:
				resumed[p] = true
		loaded.clock.advance(1.0)
	var back_at_work := resumed.size()
	_check(workers == 0 or back_at_work >= workers - 1, "and workers take up their jobs again (%d of %d)" % [back_at_work, workers])
	DirAccess.remove_absolute(PrisonSave._path("test"))
	loaded.queue_free()


func _test_flexible_objects() -> void:
	var map := BuildingMap.new(Rect2i(0, 0, 8, 8))
	map.fill_floor(Rect2i(0, 0, 8, 8))
	var table := map.place_object(PrisonCatalogue.object(&"games_table"), Vector2(2, 2), 0)
	var board_def := PrisonCatalogue.object(&"chess_board")
	_check(map.place_object_at(board_def, Vector2(5.5, 5.5), 0.0) == 0, "a chess board won't go on the floor")
	var board := map.place_on_surface(board_def, table, 0)
	_check(board != 0 and map.objects[board].centre.is_equal_approx(Vector2(2.5, 2.5)), "it goes on the table's spot")
	_check(map.place_on_surface(PrisonCatalogue.object(&"mug"), table, 0) == 0, "one thing to a spot")
	_check(map.object_at(Vector2(2.5, 2.5)).id == board, "clicking the table finds the board first")
	var chair_def := PrisonCatalogue.object(&"chair")
	var chair := map.place_beside(chair_def, table, Vector2(0, 0.65))
	_check(chair != 0 and is_equal_approx(map.objects[chair].angle, PI), "a chair goes beside it, facing it")
	_check(not map.blocks_at(map.objects[chair].centre), "and people can step between chairs")
	var radio_def := PrisonCatalogue.object(&"radio")
	_check(map.place_object(radio_def, Vector2(6, 0), 0) != 0, "a radio still stands on the floor")
	var desk := map.place_object(PrisonCatalogue.object(&"desk"), Vector2(0, 6), 0)
	_check(map.place_on_surface(radio_def, desk, 1) != 0, "or on a desk")
	_check(map.place_beside(chair_def, desk, Vector2(0, 0.5)) != 0, "a chair tucks under the desk")
	var look := map.place_object(PrisonCatalogue.object(&"desk"), Vector2(4, 0), 0)
	_check(map.set_look(look, 2) and map.objects[look].def.model_for(2) != map.objects[look].def.model,
			"a desk can wear another look")
	var copy := BuildingMap.new(Rect2i(0, 0, 8, 8))
	copy.load_data(map.to_data(), PrisonCatalogue.object)
	_check(copy.objects[board].on == table and copy.objects[look].look == 2, "looks and surfaces are saved")
	map.remove_object(table)
	_check(not map.objects.has(board) and map.objects.has(chair), "taking the table takes the board, not the chair")

	# The warden claims an office desk, which sets itself out; they sit to work.
	var main: Node = load("res://games/prison/main.tscn").instantiate()
	main.sample = 11
	root.add_child(main)
	var claims: Claims = main.claims
	var people: People = main.people
	claims.refresh()
	var warden: Person = people.people.filter(func(p: Person) -> bool: return p.role == &"warden")[0]
	var key := claims.claim_of(warden)
	var office_map: BuildingMap = main.building.levels[key.x]
	_check(key != Person.NO_OBJECT and office_map.objects[key.y].def.id == &"office_desk", "the warden claims the office desk")
	_check(office_map.dressing.get(key.y, []).size() == 4, "and it sets itself out for them")
	var clock: GameClock = main.clock
	var minutes := 0
	while warden.seat == Person.NO_OBJECT and minutes < 120:
		clock.advance(1.0)
		minutes += 1
	_check(warden.seat != Person.NO_OBJECT, "the warden sits on the chair to work")
	people.remove_person(warden)
	claims.refresh()
	_check(not office_map.dressing.has(key.y), "an unclaimed desk is bare")
	main.queue_free()


func _test_buying_land() -> void:
	var main: Node = load("res://games/prison/main.tscn").instantiate()
	main.sample = 9
	root.add_child(main)
	var plots: LandPlots = main.land_plots
	var building: Building = main.building
	var terrain: Terrain = main.terrain
	var ledger: Ledger = main.ledger
	var land := building.land[0]
	var for_sale := plots.plots()
	_check(for_sale.size() == 8 and for_sale.all(func(p: Rect2i) -> bool:
			return not p.intersects(land) and p.grow(1).intersects(land) and p.size == Vector2i(24, 24)),
			"the plots beside your land are for sale, 24 tiles square")
	# A bumpy plot to the right of the land.
	var plot := plots.plot_at(Vector2i(land.end.x + 1, land.position.y + 1))
	_check(plot.has_area() and plot in for_sale, "a plot to the side can be bought")
	var flat_price := plots.price(plot)
	for corner in plots._corners(plot):
		terrain.set_corner_height(corner, 1.0 if (corner.x + corner.y) % 2 == 0 else 0.0)
	_check(plots.price(plot) < flat_price, "hilly land is cheaper")
	var edge_height := plots.flatten_height(plot)
	var fee := plots.flatten_price(plot)
	_check(fee > 0, "flattening a hilly plot costs something")
	ledger.sandbox = false
	ledger.balance = 10
	_check(not plots.buy(plot, true) and not building.ground().owns(plot.position), "you can't buy land you can't afford")
	ledger.balance = 100000
	var cost := plots.price(plot) + fee
	_check(plots.buy(plot, true), "buying a plot")
	_check(ledger.balance == 100000 - cost, "buying charges the price and the flattening fee")
	_check(building.ground().owns(plot.position) and building.ground().owns(plot.end - Vector2i.ONE),
			"bought land is yours to build on")
	_check(is_equal_approx(terrain.corner_height(plot.get_center()), edge_height),
			"flattening levels the plot with your land")
	_check(not plot in plots.plots(), "a bought plot isn't for sale any more")
	var corner_plot := Rect2i(plot.position - Vector2i(0, plot.size.y), plot.size)
	_check(corner_plot in plots.plots(), "the plot round the corner is for sale now")
	var far := plots.plot_at(Vector2i(land.position.x - 1, land.end.y + 1))
	_check(not far in plots.plots() and plots.buyable(plots.plots_between(far.position,
			Vector2i(land.position.x + 1, land.end.y + 1))).size() == 2,
			"a plot away from your land can be bought with one between in the same drag")
	_check(plots.buy_all(plots.buyable(plots.plots_between(far.position, Vector2i(land.position.x + 1, land.end.y + 1))))
			and building.ground().owns(far.get_center()), "a dragged block buys together")
	# Giving land back.
	_check(not plots.can_sell(Rect2i(land.position, plot.size)), "land with the prison on it doesn't sell")
	var before := ledger.balance
	_check(plots.undo_last() and not building.ground().owns(far.get_center())
			and ledger.balance == before + plots.PLOT_PRICE * 2, "undone within the hour, a purchase is refunded in full")
	_check(not plots.can_sell(plot), "land a road runs through doesn't sell")
	plots.buy(corner_plot, false)
	var price_paid: int = plots.paid[corner_plot.position]
	before = ledger.balance
	_check(plots.sell_all([corner_plot]) and not building.ground().owns(corner_plot.get_center())
			and ledger.balance == before + snappedi(price_paid / 2, 10), "empty land sells back at half price")
	plots.buy(corner_plot, false)
	(main.clock as GameClock).jump_to_hour(((main.clock as GameClock).hour() + 2) % 24)
	_check(not plots.undo_last() and building.ground().owns(corner_plot.get_center()), "after the hour, it stays bought")
	var left := plots.plot_at(Vector2i(land.position.x - 1, land.position.y + 1))
	var above_left := Rect2i(left.position - Vector2i(0, left.size.y), left.size)
	_check(plots.buy_all([left, above_left]) and not plots.can_sell(left) and plots.can_sell(above_left),
			"land that would leave a piece cut off doesn't sell")
	var saved := PrisonSave.capture(main)
	main.queue_free()
	main = load("res://games/prison/main.tscn").instantiate()
	PrisonSave.pending = saved
	root.add_child(main)
	_check((main.building as Building).ground().owns(plot.position), "bought land is kept in saves")
	main.queue_free()


func _test_roads() -> void:
	var main: Node = load("res://games/prison/main.tscn").instantiate()
	main.sample = 9
	root.add_child(main)
	var roads: Roads = main.roads
	_check(roads.has_roads() and roads.edge_nodes().size() == 2, "every prison gets a road through, between two tunnels")
	var land_rect := Rect2((main.map as BuildingMap).land_bounds())
	var inside := true
	for p: Vector2 in roads.paths.nodes.values():
		inside = inside and land_rect.grow(0.01).has_point(p)
	_check(inside, "the road is inside the land")
	var vehicles: Vehicles = main.vehicles
	var through := roads.route_through(RandomNumberGenerator.new())
	_check(through.size() > 2 and not land_rect.has_point(through[0]) and not land_rect.has_point(through[-1]),
			"cars can drive right through, out of sight in the tunnels at each end")
	var passing := vehicles.drive_through(main.CARS[0], through)
	_check(passing != null and not passing.visible, "a car starts hidden in the tunnel")
	for i in 120:
		(main.clock as GameClock).advance(1.0)
	_check(not is_instance_valid(passing) or passing.is_queued_for_deletion(), "and is gone at the other end")
	# The ground under the road is smooth.
	var terrain: Terrain = main.terrain
	var segment: PathNetwork.Segment = roads.paths.segments.values()[0]
	var points := roads.paths.sample(segment, 1.0)
	var worst := 0.0
	for i in range(1, points.size()):
		worst = maxf(worst, absf(terrain.height_at(points[i]) - terrain.height_at(points[i - 1])))
	_check(worst < 0.2, "the road doesn't bump (worst step %.2f m)" % worst)
	main.queue_free()

	# Staff come on the bus.
	main = load("res://games/prison/main.tscn").instantiate()
	main.sample = 11
	root.add_child(main)
	var bus_shifts: Shifts = main.shifts
	var bus_people: People = main.people
	var bus_clock: GameClock = main.clock
	var count := bus_people.people.size()
	var wanted := bus_shifts.wanted_for(&"cleaner", &"day")
	bus_shifts.set_wanted(&"cleaner", &"day", wanted + 1)
	_check(bus_people.people.size() == count and (main.vehicles as Vehicles).get_child_count() > 0,
			"a new cleaner comes on the bus")
	var arrived := false
	for i in 90:
		bus_clock.advance(1.0)
		if bus_people.people.size() > count:
			arrived = bus_people.people[-1].role == &"cleaner"
			break
	_check(arrived, "and gets off at the bus stop")
	main.queue_free()

	main = load("res://games/prison/main.tscn").instantiate()
	main.sample = 11
	main.staff_cars = true
	root.add_child(main)
	var car_park: CarPark = main.car_park
	var shifts: Shifts = main.shifts
	var clock: GameClock = main.clock
	var people: People = main.people
	_check(car_park.bays().size() == 6 and car_park.free_bays().is_empty(), "staff already here have parked")
	var land: Rect2i = main.building.land[0]
	main.building.ground().fill_floor(Rect2i(land.position + Vector2i(2, 2), Vector2i(6, 2)), &"car_park")
	var free := car_park.free_bays().size()
	_check(free == 6, "a bigger car park has room")
	var before := people.people.size()
	var cleaners := shifts.wanted_for(&"cleaner", &"day")
	shifts.set_wanted(&"cleaner", &"day", cleaners + 1)
	_check(people.people.size() == before and car_park.free_bays().size() == free - 1,
			"a new cleaner drives in rather than appearing")
	var cleaner: Person = null
	for i in 60:
		clock.advance(1.0)
		if people.people.size() > before:
			cleaner = people.people[-1]
			break
	_check(cleaner != null and cleaner.role == &"cleaner", "and gets out once parked")
	var car: Node3D = car_park._drivers[cleaner][0]
	shifts.set_wanted(&"cleaner", &"day", cleaners)
	_check(cleaner.going_home, "sent home again")
	for i in 120:
		clock.advance(1.0)
		if not people.people.has(cleaner):
			break
	_check(not people.people.has(cleaner) and car_park.free_bays().size() == free, "going home, they walk back to the car")
	for i in 60:
		clock.advance(1.0)
	_check(not is_instance_valid(car) or car.is_queued_for_deletion(), "and drive off")
	main.queue_free()
	CarPark.enabled = false


func _test_staff_window() -> void:
	var main: Node = load("res://games/prison/main.tscn").instantiate()
	main.sample = 8
	root.add_child(main)
	var people: People = main.people
	var window: StaffWindow = main.staff_window
	var shifts: Shifts = main.shifts
	var clock: GameClock = main.clock
	clock.speed_index = 0
	var cooks := func() -> Array: return people.people.filter(func(p: Person) -> bool:
			return p.role == &"cook" and not p.going_home)
	_check(shifts.on_now().id == &"day", "the game starts on the day shift")
	_check(not shifts.entrance.is_empty(), "staff have an entrance at the edge of the land")
	# Walking in from the entrance, as when there's no bus.
	shifts.ride_in = Callable()
	shifts.set_wanted(&"cook", &"day", 2)
	var cook: Person = cooks.call().back()
	_check(cooks.call().size() == 2 and cook.group == &"staff" and cook.shift == &"day",
			"the staff window takes on cooks for the day shift")
	_check(cook.flat().distance_to(shifts.entrance[1]) < 1.0, "who arrive at the entrance")
	window.refresh()
	_check(window._counts[&"cook"][&"day"].text == "2" and window._counts[&"cook"][&"night"].text == "0",
			"and counts them for each shift")
	var wardens := shifts.wanted_for(&"warden", &"day")
	shifts.set_wanted(&"warden", &"day", 3, false)
	shifts.set_wanted(&"warden", &"night", 1, false)
	_check(shifts.wanted_for(&"warden", &"day") == 1 and shifts.wanted_for(&"warden", &"night") == 0
			and not window._counts[&"warden"].has(&"night"), "there's one warden at most, on days only")
	shifts.set_wanted(&"warden", &"day", wardens, false)
	shifts.set_wanted(&"cook", &"day", 1)
	_check(cooks.call().size() == 1 and cook.going_home, "and sends one home")
	for i in 60:
		clock.advance(1.0)
	_check(not people.people.has(cook), "who walks out and is gone")
	shifts.set_wanted(&"cook", &"night", 1)
	_check(cooks.call().size() == 1, "nobody comes in for nights during the day")
	clock.jump_to_hour(17)
	while clock.minute_of_day() < 17 * 60 + 50:
		clock.advance(1.0)
	_check(cooks.call().size() == 2, "the night cook arrives before the day one leaves")
	while clock.minute_of_day() < 18 * 60 + 5:
		clock.advance(1.0)
	var on: Array = cooks.call()
	_check(on.size() == 1 and on[0].shift == &"night", "and the day cook goes home at the end of the shift")

	# Staff needs: energy for the shift, coffee in the staff room, slow
	# when worn out, and a setting to switch them off.
	var night_cook: Person = on[0]
	var prisoner: Person = people.people.filter(func(p: Person) -> bool: return p.group == &"prisoner")[0]
	_check(night_cook.needs.has(&"energy") and not prisoner.needs.has(&"energy"), "staff have energy, prisoners don't")
	night_cook.needs[&"energy"] = 20.0
	_check(people.work_pace(night_cook) < 1.0, "worn-out staff work slower")
	var cuppa := false
	for i in 90:
		clock.advance(1.0)
		cuppa = cuppa or night_cook.activity == "Having a cuppa"
	_check(cuppa and night_cook.needs[&"energy"] > 50.0, "and go for a coffee in the staff room")
	people.needs_off.append(&"staff")
	night_cook.needs[&"hunger"] = 10.0
	clock.advance(1.0)
	_check(night_cook.needs.values().all(func(v: float) -> bool: return v == 100.0),
			"with staff needs off, their needs stay met")
	window._put_on(&"workshop")
	_check(people.people.filter(func(p: Person) -> bool: return p.programme == &"workshop").size() == 1,
			"puts a prisoner on a work programme")
	window._take_off(&"workshop")
	_check(people.people.all(func(p: Person) -> bool: return p.programme == &""), "and takes them off")
	_check(InputMap.has_action("staff_toggle"), "P opens it")
	main.queue_free()

	# The jobs panel lists jobs, stock and warnings.
	var working: Node = load("res://games/prison/main.tscn").instantiate()
	working.sample = 9
	root.add_child(working)
	var text: String = working.jobs_panel.describe()
	_check(text.contains("Put away the food delivery") and text.contains("Crate of food: 6"),
			"the jobs panel lists open jobs and stock")
	for placed: BuildingMap.PlacedObject in working.map.objects.values().duplicate():
		if placed.def.id == &"cooker":
			working.map.remove_object(placed.id)
	_check(working.jobs_panel.describe().contains("no cooker"), "and warns when the kitchen can't work")
	working.queue_free()


func _test_stopped_on_stairs() -> void:
	var main: Node = load("res://games/prison/main.tscn").instantiate()
	main.sample = 1
	root.add_child(main)
	var people: People = main.people
	var o: Vector2i = main.building.land[0].get_center() - Vector2i(7, 5)
	var person: Person = people.people[0]
	people._stop(person)
	person.level = 0
	person.position = Vector3(o.x + 5.5, 0.875, o.y + 5.5)
	_check(people.nav().point_at(0, person.flat()) == -1, "the middle of the stairs is no floor")
	_check(people.can_reach(person, 0, Vector2(o + Vector2i(3, 8)) + Vector2(0.5, 0.5)),
			"someone stopped on the stairs can still get down to the canteen")
	root.remove_child(main)
	main.free()


func _reachable_needs(people: People) -> Array[StringName]:
	var out: Array[StringName] = []
	for def in people.needs:
		if not def.id in [&"sleep", &"hunger", &"hygiene", &"bladder"]:
			continue
		var everyone := true
		for person in people.people:
			if not person.needs.has(def.id):
				continue
			var found := false
			for n: int in people.building.levels:
				for placed: BuildingMap.PlacedObject in people.building.levels[n].objects.values():
					if found or not placed.def.tags.any(def.met_by):
						continue
					for spot in people._spots_beside(n, placed, person.flat()):
						if people.can_reach(person, n, spot):
							found = true
							break
			everyone = everyone and found
		if everyone:
			out.append(def.id)
	return out


func _test_main_scene_loads() -> void:
	var scene: PackedScene = load("res://games/prison/main.tscn")
	_check(scene != null, "main scene loads")
	if scene == null:
		return
	var main := scene.instantiate()
	root.add_child(main)
	var map: BuildingMap = main.map
	var terrain: Terrain = main.terrain
	_check(terrain.get_child_count() > 0, "terrain builds its mesh")
	_check(is_zero_approx(terrain.cell_height(map.land_bounds().get_center())), "owned land starts flat")
	_check(main.foliage.plants.size() > 50, "the world starts with some plants")
	_check(main.water.bodies.size() == 1, "the world starts with a pond")
	_check(map.rooms().size() == 10, "sample layout has ten rooms")
	var view: BuildingView = main.get_node("BuildGrid/BuildingView")
	view.rebuild()
	_check(view.get_child_count() > 0, "view builds its parts")
	var windows := map.walls.values().count(BuildingMap.Wall.WINDOW)
	_check(windows == 9, "sample layout has nine windows")
	var overlay: DebugOverlay = main.debug_overlay
	overlay.visible = true
	overlay._draw_rooms()
	# The first cell's middle tile, just inside its barred window.
	var text := overlay.describe(map.land_bounds().get_center() - Vector2i(7, 7))
	_check(text.contains("Enclosed: yes") and text.contains("Indoors") and text.contains("bars window"),
			"debug view describes a cell, its room and its window")
	main.building.active = 1
	main.level_grid.rebuild()
	_check(main.level_grid._mesh.get_surface_count() == 1, "upstairs, a grid shows at floor level")
	var below := map.floor_height(map.land_bounds().get_center() - Vector2i(7, 7))
	_check(is_equal_approx(main.level_grid.sheet_height(), below + Building.STOREY),
			"upstairs, open tiles show one storey above the floors below")
	main.building.active = 0
	main.level_grid.rebuild()
	_check(main.level_grid._mesh.get_surface_count() == 0, "on the ground, the ground's own grid shows")
	_test_roofs_and_wall_views(main, map)
	var people: People = main.people
	_check(people.people.size() == 6, "six prisoners start in the sample prison")
	people.step(0.5)
	var inspector: Inspector = main.inspector
	inspector.select(people.people[0])
	inspector._process(0.0)
	_check(inspector._live_text != null and inspector._live_text.text.contains("Doing:"),
			"the inspector describes a person")
	inspector.select(Vector2i(map.land_bounds().position + Vector2i(2, 2)))
	inspector._add_prisoner(map.land_bounds().position + Vector2i(2, 2))
	_check(people.people.size() == 7 and inspector.selected() is Person, "the inspector adds a prisoner")
	# Nobody near the mouse, so a click picks what is on the tile.
	for person in people.people.duplicate():
		people.remove_person(person)
	_check(inspector.selected() == null, "removing the selected person clears the inspector")
	inspector._on_cell_clicked(map.land_bounds().get_center() - Vector2i(8, 7), MOUSE_BUTTON_LEFT)
	_check(inspector.selected() is Array, "clicking a bed in the debug view inspects it")
	overlay.visible = false
	_check(overlay.describe(GridCursor.NO_CELL).contains("Rooms: "), "debug view shows totals")
	_test_tools(main.controller, map)
	main.building.active = 1
	_check(main.views[1].visible and main.views[0].visible and not main.views[0].show_labels,
			"upstairs shows the floor below without its labels")
	main.building.active = -1
	_check(not main.terrain.visible and not main.views[0].visible, "basements hide the land and the floors above")
	_check(not is_nan(main.camera_rig.pick_height), "off the ground, picking uses a flat plane")
	main.building.active = 0
	_check(main.terrain.visible and is_nan(main.camera_rig.pick_height), "back on the ground, the land shows again")
	main.free()


## Drives the build tools the way the mouse would, by moving the hover point.
## Positions are relative to the corner of the owned land.
func _test_roofs_and_wall_views(main: Node, map: BuildingMap) -> void:
	var o := map.land_bounds().get_center() - Vector2i(8, 7)
	var ground_view: BuildingView = main.views[0]
	var controller: BuildController = main.controller
	_check(ground_view.has_roof(o + Vector2i(1, 6)), "indoor rooms get a flat roof")
	_check(not ground_view.has_roof(o + Vector2i(14, 2)), "the fenced yard doesn't")
	_check(not ground_view.show_roof, "roofs are hidden on the floor you're building on")
	main.building.active = 1
	_check(ground_view.show_roof, "and show from the floor above")
	main.building.level(1).fill_floor(Rect2i(o + Vector2i(1, 6), Vector2i(1, 1)), &"wood", Building.STOREY)
	_check(not ground_view.has_roof(o + Vector2i(1, 6)), "floor above stands in for the roof")
	main.building.level(1).clear_floor(Rect2i(o + Vector2i(1, 6), Vector2i(1, 1)))
	# Stairs up from the corridor: open over the flight below, roofed at the top.
	var up: BuildingMap = main.building.level(1)
	up.build_room(Rect2i(o + Vector2i(0, 3), Vector2i(12, 2)), &"concrete", &"brick", Building.STOREY)
	var route: Array[Vector2i] = [o + Vector2i(4, 3), o + Vector2i(5, 3), o + Vector2i(6, 3)]
	map.add_stairs(Staircase.create(route, [false, false, false] as Array[bool]))
	_check(not ground_view.has_roof(o + Vector2i(5, 3)), "no roof cuts across stairs going up")
	_check(main.views[1].has_roof(o + Vector2i(5, 3)), "the stairwell is roofed over upstairs")
	map.remove_stairs(map.stairs.keys()[0])
	up.demolish(Rect2i(o + Vector2i(0, 3), Vector2i(12, 2)))
	main.building.active = 0
	_check(controller.wall_view == BuildController.WallView.UP, "walls start up")
	controller.next_wall_view()
	_check(ground_view.cutaway and not ground_view.walls_low, "Tab goes to cutaway")
	var north := [Vector2(o), Vector2(o) + Vector2(1, 0)]
	ground_view.cut_direction = Vector2(0, 1)
	_check(ground_view.is_cut(north[0], north[1]), "cutaway drops a wall with a room behind it")
	ground_view.cut_direction = Vector2(0, -1)
	_check(not ground_view.is_cut(north[0], north[1]), "and keeps the far wall up")
	controller.next_wall_view()
	_check(ground_view.walls_low and not ground_view.cutaway, "then to walls down")
	controller.next_wall_view()
	_check(ground_view.show_roof and not ground_view.walls_low and main.views[1].visible,
			"then roofs on, showing every level")
	controller.next_wall_view()
	_check(controller.wall_view == BuildController.WallView.UP and not ground_view.show_roof
			and not main.views[1].visible, "and back to walls up")


func _test_tools(controller: BuildController, map: BuildingMap) -> void:
	var base := Vector2(map.land_bounds().position)
	var cell := func(x: int, z: int) -> Vector2i: return Vector2i(base) + Vector2i(x, z)
	var hover := func(x: float, z: float) -> void:
		controller._has_hover = true
		controller._hover_point = base + Vector2(x, z)
	var rooms_before := map.rooms().size()

	controller.tool = BuildController.Tool.ROOM
	hover.call(2.5, 2.5)
	controller._on_press()
	hover.call(5.5, 4.5)
	controller._draw_preview()
	controller._on_release()
	_check(map.rooms().size() == rooms_before + 1 and map.room_at(cell.call(2, 2)).cells.size() == 12,
			"room tool builds an enclosed room")

	controller.tool = BuildController.Tool.WALL
	hover.call(4.1, 1.9)
	controller._on_press()
	hover.call(3.8, 5.2)
	controller._on_release()
	_check(map.rooms().size() == rooms_before + 2, "wall tool splits the room")

	controller.force_erase = true
	hover.call(4.1, 1.9)
	controller._on_press()
	hover.call(3.8, 5.2)
	controller._draw_preview()
	controller._on_release()
	controller.force_erase = false
	_check(map.rooms().size() == rooms_before + 1, "wall tool with Ctrl removes walls")
	controller.tool = BuildController.Tool.WALL
	hover.call(4.1, 1.9)
	controller._on_press()
	hover.call(3.8, 5.2)
	controller._on_release()

	# Painting: Shift paints every side facing into the room under the mouse.
	controller.wall_mode = BuildController.WallMode.PAINT
	controller.wall_style = &"wall_tiles"
	hover.call(2.5, 2.5)
	Input.action_press("build_whole_room")
	controller._draw_preview()
	controller._on_press()
	Input.action_release("build_whole_room")
	var west := Vector3i(cell.call(2, 2).x, cell.call(2, 2).y, BuildingMap.EDGE_Z)
	_check(map.side_style(west, BuildingMap.wall_side(west, Vector2(cell.call(2, 2)) + Vector2(0.5, 0.5)))
			== &"wall_tiles" and map.wall_style(west) != &"wall_tiles", "paint mode paints a room's inner sides")
	controller._painting = false
	controller.force_erase = true
	Input.action_press("build_whole_room")
	controller._on_press()
	Input.action_release("build_whole_room")
	controller.force_erase = false
	controller._painting = false
	_check(not map.wall_paints.has(west), "Ctrl takes the paint off again")
	controller.wall_mode = BuildController.WallMode.BUILD
	controller.wall_style = BuildingMap.DEFAULT_WALL

	controller.tool = BuildController.Tool.OPENING
	hover.call(3.9, 3.5)
	controller._on_press()
	_check(map.wall_at(Vector3i(cell.call(4, 3).x, cell.call(4, 3).y, BuildingMap.EDGE_Z))
			== BuildingMap.Wall.DOOR, "door tool makes a door")

	controller.opening = BuildingMap.Wall.WINDOW
	controller.window_kind = BuildingMap.WINDOW_GLASS
	hover.call(3.9, 2.5)
	controller._draw_preview()
	controller._on_press()
	var window_edge := Vector3i(cell.call(4, 2).x, cell.call(4, 2).y, BuildingMap.EDGE_Z)
	_check(map.wall_at(window_edge) == BuildingMap.Wall.WINDOW, "opening tool puts in a window")
	controller._on_press()
	_check(map.wall_at(window_edge) == BuildingMap.Wall.WALL, "clicking a window again fills it in")
	controller.opening = BuildingMap.Wall.DOOR

	controller.tool = BuildController.Tool.OBJECT
	controller.object_def = PrisonCatalogue.object(&"toilet")
	hover.call(2.5, 2.5)
	controller._draw_preview()
	controller._on_press()
	_check(map.object_at(base + Vector2(2.5, 2.5)) != null, "object tool places an object")

	controller.tool = BuildController.Tool.ROOM_TYPE
	controller.room_type = PrisonCatalogue.room_type(&"cell")
	controller._on_press()
	_check(map.room_at(cell.call(2, 2)).type == &"cell", "room type tool marks the room")

	controller.tool = BuildController.Tool.ZONE
	controller.zone = PrisonCatalogue.ZONES[1]
	controller._draw_preview()
	controller._on_press()
	_check(map.room_at(cell.call(2, 2)).zone == &"staff", "zones tool paints a room")
	controller.zone = null
	controller._on_press()
	_check(map.room_at(cell.call(2, 2)).zone == &"", "and clears it back to the room type's")

	controller.tool = BuildController.Tool.DEMOLISH
	controller._draw_preview()
	controller._on_press()
	controller._on_release()
	_check(map.object_at(base + Vector2(2.5, 2.5)) == null and map.has_floor(cell.call(2, 2)),
			"demolish click removes just the object")
	hover.call(4.05, 2.5)
	controller._draw_preview()
	controller._on_press()
	controller._on_release()
	_check(map.rooms().size() == rooms_before + 1, "demolish click on a wall removes just that wall")
	hover.call(2.5, 2.5)
	controller._on_press()
	hover.call(5.5, 4.5)
	controller._on_release()
	_check(map.rooms().size() == rooms_before, "demolish drag clears the area")

	# Terrain: raising a patch of open land, then building on it flattens it.
	var terrain := controller.terrain
	controller.tool = BuildController.Tool.TERRAIN
	controller.terrain_brush = Terrain.Brush.RAISE
	controller.brush_radius = 3.0
	var outside_before := terrain.corner_height(cell.call(-1, -1))
	hover.call(10.0, 10.0)
	controller._on_press()
	controller._draw_preview()
	controller._apply_brush(0.5)
	controller._brushing = false
	var peak := terrain.corner_height(cell.call(10, 10))
	_check(peak > 0.5, "terrain tool raises the ground")
	hover.call(0.0, 0.0)
	controller._apply_brush(0.5)
	_check(terrain.corner_height(cell.call(-1, -1)) == outside_before
			and terrain.corner_height(cell.call(1, 1)) > 0.0, "sculpting stays on owned land")
	controller.tool = BuildController.Tool.ROOM
	var skirt_corner: Vector2i = cell.call(9, 13)
	var skirt_before := terrain.corner_height(skirt_corner)
	hover.call(10.5, 10.5)
	controller._on_press()
	hover.call(12.5, 12.5)
	controller._on_release()
	var floor_height := terrain.cell_height(cell.call(10, 10))
	_check(absf(terrain.corner_height(skirt_corner) - floor_height) < absf(skirt_before - floor_height) - 0.01,
			"the ground round a new room slopes to meet it")
	_check(is_equal_approx(terrain.cell_height(cell.call(12, 12)), floor_height)
			and map.has_floor(cell.call(12, 12)), "a new room flattens the ground under it")
	_check(is_equal_approx(map.floor_height(cell.call(12, 12)), floor_height),
			"the room remembers its floor height")
	controller.tool = BuildController.Tool.FLOOR
	controller.floor_style = &"wood"
	hover.call(9.5, 9.5)
	controller._on_press()
	hover.call(13.5, 13.5)
	controller._on_release()
	_check(map.floors[cell.call(9, 9)] == &"wood" and is_equal_approx(map.floor_height(cell.call(9, 9)),
			floor_height), "floor next to a room is laid at the room's height")
	_check(map.floors[cell.call(11, 11)] != &"wood", "dragged floor stays on the side of the wall it began")
	Input.action_press("build_whole_room")
	hover.call(11.5, 11.5)
	controller._on_press()
	controller._on_release()
	Input.action_release("build_whole_room")
	_check(map.floors[cell.call(11, 11)] == &"wood" and map.floors[cell.call(12, 12)] == &"wood",
			"Shift-click floors the whole room")
	var poking := false
	for z in range(9, 15):
		for x in range(9, 15):
			var corner: Vector2i = cell.call(x, z)
			for touch: Vector2i in [Vector2i.ZERO, Vector2i(-1, 0), Vector2i(0, -1), Vector2i(-1, -1)]:
				if map.has_floor(corner + touch) \
						and terrain.corner_height(corner) > map.floor_height(corner + touch) + 0.001:
					poking = true
	_check(not poking, "the ground never pokes through a floor")
	controller.floor_style = BuildingMap.DEFAULT_FLOOR
	controller.tool = BuildController.Tool.TERRAIN
	controller.terrain_brush = Terrain.Brush.LOWER
	hover.call(11.0, 11.0)
	controller._on_press()
	controller._apply_brush(0.5)
	controller._brushing = false
	_check(is_equal_approx(terrain.cell_height(cell.call(11, 11)), floor_height),
			"sculpting leaves ground under buildings alone")

	# Plants grow on open land but not on floors, and Ctrl clears them. The
	# spot is well away from the sample layout's floors.
	var foliage := controller.foliage
	controller.tool = BuildController.Tool.PLANTS
	controller.plant_def = PrisonCatalogue.PLANTS[3]
	var before := foliage.plants.size()
	hover.call(8.0, 40.0)
	controller._on_press()
	for i in 5:
		controller._apply_brush(0.1)
	_check(foliage.plants.size() > before, "plant tool plants")
	hover.call(11.5, 11.5)
	controller.brush_radius = 1.0
	before = foliage.plants.size()
	controller._apply_brush(0.1)
	_check(foliage.plants.size() == before, "plants do not grow on floors")
	hover.call(8.0, 40.0)
	controller.brush_radius = 4.0
	controller.force_erase = true
	controller._apply_brush(0.1)
	controller.force_erase = false
	controller._brushing = false
	var left := foliage.plants.filter(func(p: FoliageLayer.Plant) -> bool:
		return p.position.distance_to(base + Vector2(8, 40)) < 4.0)
	_check(left.is_empty(), "Ctrl clears plants")

	# Water: dig a hollow, fill it, check you can't build in it, then drain it.
	var water := controller.water
	controller.tool = BuildController.Tool.TERRAIN
	controller.terrain_brush = Terrain.Brush.LOWER
	controller.brush_radius = 3.0
	hover.call(8.0, 30.0)
	controller._on_press()
	controller._apply_brush(1.0)
	controller._brushing = false
	controller.water_mode = BuildController.WaterMode.ADD
	controller._draw_preview()
	controller._on_press()
	var pond := water.body_at(cell.call(8, 30))
	_check(pond != null and pond.level < 0.0 and pond.cells.size() < 60,
			"terrain tool fills a hole dug in flat land to the brim")
	_check(not controller._is_dry(Rect2i(cell.call(7, 29), Vector2i(2, 2))), "you can't build in a pond")
	controller.water_mode = BuildController.WaterMode.REMOVE
	controller._draw_preview()
	controller._on_press()
	_check(water.body_at(cell.call(8, 30)) == null, "terrain tool drains a pond")
	controller.water_mode = BuildController.WaterMode.NONE

	# Paths: a straight path, chained on, a curve, freehand, and removal.
	var paths := controller.paths
	_check(paths.segments.values().any(func(seg: PathNetwork.Segment) -> bool: return seg.style == &"road"),
			"a new prison comes with a road")
	paths.load_data({}) # Without the road, to count paths drawn.
	controller.tool = BuildController.Tool.PATH
	controller.path_tool.style = &"gravel"
	controller.path_tool.mode = PathTool.Mode.STRAIGHT
	hover.call(2.0, 44.0)
	controller._on_press()
	hover.call(10.0, 44.0)
	controller._draw_preview()
	controller._on_press()
	_check(paths.segments.size() == 1, "path tool draws a straight path")
	hover.call(10.0, 46.0)
	controller._on_press()
	_check(paths.segments.size() == 2, "the next click carries the path on")
	controller.path_tool.cancel()
	hover.call(-3.0, 44.0)
	controller._on_press()
	hover.call(2.0, 44.0)
	controller._on_press()
	_check(paths.segments.size() == 2, "paths stay on your own land")
	controller.path_tool.cancel()
	controller.path_tool.mode = PathTool.Mode.CURVED
	hover.call(12.0, 40.0)
	controller._on_press()
	hover.call(16.0, 36.0)
	controller._on_press()
	hover.call(20.0, 40.0)
	controller._draw_preview()
	controller._on_press()
	_check(paths.segments.size() == 3, "curved mode takes a start, a bend and an end")
	controller.path_tool.cancel()
	controller.path_tool.mode = PathTool.Mode.FREEHAND
	hover.call(24.0, 42.0)
	controller._on_press()
	for i in 20:
		controller.path_tool.extend_trail(base + Vector2(24.0 + i * 0.6, 42.0 + sin(i * 0.4) * 2.0))
	controller.path_tool.end_trail(base + Vector2(36.0, 44.0))
	_check(paths.segments.size() >= 6, "freehand turns a drag into a chain of curves")
	map.build_room(Rect2i(cell.call(30, 2), Vector2i(3, 3)))
	map.set_door(Vector3i(cell.call(31, 5).x, cell.call(31, 5).y, BuildingMap.EDGE_X), true)
	var door: Vector2 = controller.path_tool.door_points()[0]
	_check(controller.path_tool.snap(door + Vector2(0.3, 0.3)) == door, "path ends snap to doors")
	var free_spot := base + Vector2(20.3, 20.8)
	_check(controller.path_tool.snap(free_spot) == base + Vector2(20.5, 20.5), "path ends snap to the middle of tiles")
	_check(controller.path_tool.snap(free_spot, false) == free_spot, "bends do not snap")
	controller.path_tool.free_held = true
	_check(controller.path_tool.snap(free_spot) == free_spot and controller.path_tool.snap(free_spot, false)
			== base + Vector2(20.5, 20.5), "Alt swaps snapping for the point being placed")
	controller.path_tool.free_held = false
	controller.path_tool.raise()
	controller.path_tool.raise()
	_check(controller.path_tool.built and controller.path_tool.raise_steps == 1,
			"Page Up builds the stretch, then raises its end")
	controller.path_tool.lower()
	controller.path_tool.lower()
	_check(not controller.path_tool.built, "Page Down goes back to the ground")
	# A path running along another is refused; one crossing it is fine.
	controller.path_tool.cancel()
	controller.path_tool.mode = PathTool.Mode.STRAIGHT
	hover.call(26.0, 38.0)
	controller._on_press()
	hover.call(34.0, 38.0)
	controller._on_press()
	controller.path_tool.cancel()
	var segments_now := paths.segments.size()
	hover.call(27.0, 38.4)
	controller._on_press()
	hover.call(33.0, 38.4)
	_check(controller.path_tool.status(controller._hover_point).contains("another path"),
			"the hint says why a path cannot go there")
	controller._on_press()
	_check(paths.segments.size() == segments_now, "a path cannot run along another")
	controller.path_tool.cancel()
	hover.call(30.0, 35.0)
	controller._on_press()
	hover.call(30.0, 41.0)
	controller._on_press()
	_check(paths.segments.size() == segments_now + 3, "a path can cross another, making a junction")
	controller.path_tool.cancel()
	controller.force_erase = true
	controller.path_tool.mode = PathTool.Mode.STRAIGHT
	hover.call(6.0, 44.1)
	controller._on_press()
	controller.force_erase = false
	_check(paths.segments.size() >= 5 and paths.closest(base + Vector2(6, 44))[2] > 1.0,
			"Ctrl-click removes a path")
	controller.path_view.rebuild()

	# Storeys: build upstairs over the ground floor, not over thin air.
	var building := controller.building
	var ground_room := Rect2i(cell.call(36, 30), Vector2i(4, 4))
	map.build_room(ground_room)
	building.active = 1
	controller.tool = BuildController.Tool.ROOM
	hover.call(36.5, 30.5)
	controller._on_press()
	hover.call(39.5, 33.5)
	controller._draw_preview()
	controller._on_release()
	var upstairs := building.level(1)
	_check(upstairs.rooms().size() == 1 and is_equal_approx(upstairs.floor_height(cell.call(37, 31)),
			map.floor_height(cell.call(37, 31)) + Building.STOREY), "room tool builds a storey up")
	hover.call(41.5, 30.5)
	controller._on_press()
	hover.call(43.5, 32.5)
	controller._on_release()
	_check(upstairs.rooms().size() == 1, "upstairs rooms need floor below")
	controller.tool = BuildController.Tool.TERRAIN
	controller.terrain_brush = Terrain.Brush.RAISE
	var before_sculpt := terrain.corner_height(cell.call(44, 44))
	hover.call(44.0, 44.0)
	controller._on_press()
	controller._apply_brush(0.5)
	controller._brushing = false
	_check(terrain.corner_height(cell.call(44, 44)) == before_sculpt, "terrain tools only work on the ground floor")
	if upstairs.wall_def(&"perimeter_fence") != null:
		controller.tool = BuildController.Tool.WALL
		controller.wall_style = &"perimeter_fence"
		var walls_before := upstairs.walls.size() + map.walls.size()
		hover.call(44.0, 44.0)
		controller._on_press()
		hover.call(46.0, 44.0)
		controller._on_release()
		_check(upstairs.walls.size() + map.walls.size() == walls_before, "perimeter fences only go on the ground floor")
		controller.wall_style = BuildingMap.DEFAULT_WALL
	else:
		_check(false, "the perimeter fence style is known to the build tools")
	building.active = -1
	controller.tool = BuildController.Tool.ROOM
	hover.call(41.5, 40.5)
	controller._on_press()
	hover.call(44.5, 43.5)
	controller._on_release()
	_check(building.level(-1).rooms().size() == 1 and building.level(-1).floor_height(cell.call(42, 41))
			< terrain.cell_height(cell.call(42, 41)) - Building.STOREY + 0.5, "basements go below ground")
	# Split levels (behind a flag): raise half the ground room, then go too far.
	building.active = 0
	controller.floor_mode = BuildController.FloorMode.RAISE
	_check(controller.floor_mode == BuildController.FloorMode.LAY
			and controller.nudge_floors(Rect2i(cell.call(36, 30), Vector2i(4, 4)), 0.25) == 0,
			"with split levels off, floors can't be nudged")
	Building.split_levels = true
	controller.tool = BuildController.Tool.FLOOR
	controller.floor_mode = BuildController.FloorMode.RAISE
	var low_cell: Vector2i = cell.call(36, 31)
	var high_cell: Vector2i = cell.call(38, 31)
	var start_height := map.floor_height(high_cell)
	hover.call(38.5, 30.5)
	controller._on_press()
	hover.call(39.5, 33.5)
	controller._draw_preview()
	controller._on_release()
	_check(is_equal_approx(map.floor_height(high_cell), start_height + BuildController.NUDGE_STEP)
			and is_equal_approx(map.floor_height(low_cell), start_height), "raise nudges the dragged floor up")
	_check(map.can_walk_between(cell.call(37, 31), high_cell), "a small split is a step people can take")
	for i in 3:
		controller.nudge_floors(Rect2i(cell.call(38, 30), Vector2i(2, 4)), BuildController.NUDGE_STEP)
	_check(not map.can_walk_between(cell.call(37, 31), high_cell), "a big split needs a ramp or stairs")
	controller.floor_mode = BuildController.FloorMode.RAMP
	hover.call(36.5, 31.5)
	controller._on_press()
	hover.call(37.5, 31.5)
	controller._draw_preview()
	var planned := controller.planned_ramp()
	controller._on_release()
	_check(planned != null and planned.rise == Vector2i.RIGHT and map.ramp_at(cell.call(37, 31)) != null
			and map.can_walk_between(cell.call(37, 31), high_cell), "a dragged ramp climbs to the higher floor")
	controller.floor_mode = BuildController.FloorMode.RAISE
	building.active = 1
	for i in 10:
		controller.nudge_floors(Rect2i(cell.call(36, 30), Vector2i(4, 4)), BuildController.NUDGE_STEP)
	_check(upstairs.floor_height(cell.call(37, 31)) <= map.floor_height(cell.call(37, 31))
			+ Building.STOREY + BuildController.NUDGE_UP + 0.001, "upstairs nudges stay within the storey")
	controller.floor_mode = BuildController.FloorMode.LAY
	Building.split_levels = false
	building.active = 0

	# Angled walls: 45° snaps by default, Alt allows any angle.
	controller.tool = BuildController.Tool.ROOM
	hover.call(10.5, 38.5)
	controller._on_press()
	hover.call(15.5, 43.5)
	controller._on_release()
	var square := map.room_at(cell.call(12, 40))
	_check(square != null and square.cells.size() == 36, "a room for angled walls")
	controller.tool = BuildController.Tool.WALL
	hover.call(10.0, 38.0)
	controller._on_press()
	hover.call(16.2, 43.4)
	controller._draw_preview()
	controller._on_release()
	var start := Vector2i(cell.call(10, 38))
	_check(map.slants.has(BuildingMap.slant_key(start, start + Vector2i(1, 1)))
			and map.slants.size() == 6 and map.room_at_point(base + Vector2(12.8, 40.2))
			!= map.room_at_point(base + Vector2(12.2, 40.8)), "a near-diagonal drag snaps to 45°")
	controller.force_erase = true
	hover.call(10.0, 38.0)
	controller._on_press()
	hover.call(16.0, 44.0)
	controller._on_release()
	controller.force_erase = false
	_check(map.slants.is_empty(), "Ctrl removes angled walls")
	Input.action_press("build_free_place")
	hover.call(10.0, 38.0)
	controller._on_press()
	hover.call(16.0, 41.0)
	controller._draw_preview()
	controller._on_release()
	Input.action_release("build_free_place")
	_check(map.slants.size() == 3 and map.slants.has(BuildingMap.slant_key(start, start + Vector2i(2, 1))),
			"Alt draws a wall at any angle")
	controller.tool = BuildController.Tool.OPENING
	controller.opening = BuildingMap.Wall.DOOR
	hover.call(13.05, 39.4)
	controller._on_press()
	var middle_key := BuildingMap.slant_key(start + Vector2i(2, 1), start + Vector2i(4, 2))
	_check(map.slant_at(middle_key) == BuildingMap.Wall.DOOR, "a door goes in an angled wall")
	controller.tool = BuildController.Tool.FLOOR
	controller.force_erase = true
	hover.call(11.8, 38.2)
	controller._on_press()
	controller._on_release()
	controller.force_erase = false
	_check(map.floors.has(cell.call(11, 38)) and not map.piece_has_floor(map.piece_at(base + Vector2(11.8, 38.2)))
			and map.piece_has_floor(map.piece_at(base + Vector2(11.2, 38.8))), "Ctrl-click lifts half a cut tile")
	hover.call(11.8, 38.2)
	controller._on_press()
	controller._on_release()
	_check(map.piece_has_floor(map.piece_at(base + Vector2(11.8, 38.2))), "a click puts it back")
	controller.tool = BuildController.Tool.DEMOLISH
	hover.call(13.05, 39.4)
	controller._on_press()
	controller._on_release()
	_check(not map.slants.has(middle_key) and map.slants.size() == 2, "demolish removes one angled wall")
	# Objects at any angle.
	controller.tool = BuildController.Tool.OBJECT
	controller.object_def = load("res://games/prison/catalogue/table.tres")
	controller.object_angle = 0.0
	controller.rotation_step = 45.0
	var press_key := func(action: String) -> void:
		var event := InputEventAction.new()
		event.action = action
		event.pressed = true
		controller._unhandled_input(event)
	press_key.call("build_rotate")
	_check(is_equal_approx(controller.object_angle, PI * 0.25), "R turns an object by 45°")
	press_key.call("build_brush_smaller")
	_check(controller.rotation_step == 22.5 and controller.hint().contains("22.5"), "[ makes the turn finer")
	controller.rotation_step = 45.0
	var objects_before := map.objects.size()
	hover.call(12.6, 42.1)
	controller._on_press()
	var table_id: int = map.objects.keys().max() if map.objects.size() > objects_before else 0
	var table: BuildingMap.PlacedObject = map.objects.get(table_id)
	_check(table != null and is_equal_approx(table.angle, PI * 0.25)
			and table.centre == base + Vector2(12.5, 42.0), "a turned table snaps its middle to half tiles")
	_check(map.object_at(base + Vector2(12.5, 42.0)) == table and map.object_at(base + Vector2(11.6, 41.1)) == null,
			"picking a turned object follows its shape")
	controller._on_press()
	_check(map.objects.size() == objects_before + 1, "turned objects cannot overlap")
	Input.action_press("build_free_rotate")
	hover.call(14.8, 39.2)
	controller._update_free_rotate()
	hover.call(15.0, 42.5)
	controller._update_free_rotate()
	_check(controller._object_centre() == base + Vector2(15.0, 39.0)
			and is_equal_approx(controller.object_angle, 0.0), "holding F pins the object and turns it to the mouse")
	Input.action_release("build_free_rotate")
	controller._update_free_rotate()
	controller.tool = BuildController.Tool.NONE


func _test_windows() -> void:
	var map := BuildingMap.new(Rect2i(0, 0, 20, 20))
	map.register_styles(PrisonCatalogue.FLOORS, PrisonCatalogue.WALLS)
	map.build_room(Rect2i(0, 0, 3, 3), &"concrete", &"brick")
	map.fill_floor(Rect2i(3, 0, 2, 3))
	var edge := Vector3i(3, 1, BuildingMap.EDGE_Z)
	_check(map.set_opening(edge, BuildingMap.Wall.WINDOW, BuildingMap.WINDOW_BARS), "a wall takes a window")
	_check(map.window_kind(edge) == BuildingMap.WINDOW_BARS, "window kind is stored")
	_check(not map.can_walk_between(Vector2i(2, 1), Vector2i(3, 1)), "windows block walking")
	_check(map.room_at(Vector2i(1, 1)).indoor, "a room with a window stays indoors")
	_check(map.room_at(Vector2i(1, 1)) != map.room_at(Vector2i(3, 1)), "windows split rooms")
	_check(map.set_opening(edge, BuildingMap.Wall.WINDOW, BuildingMap.WINDOW_GLASS), "windows can change kind")
	_check(map.set_door(edge, true) and map.window_kind(edge) == &"", "a window can become a door")
	_check(map.can_walk_between(Vector2i(2, 1), Vector2i(3, 1)), "doors let people through")
	map.set_opening(edge, BuildingMap.Wall.WINDOW)
	map.remove_walls([edge])
	_check(not map.window_kinds.has(edge), "removing a wall forgets its window")
	map.build_walls([Vector3i(10, 10, BuildingMap.EDGE_X)], &"fence")
	_check(not map.set_opening(Vector3i(10, 10, BuildingMap.EDGE_X), BuildingMap.Wall.WINDOW),
			"fences cannot take windows")


func _test_wall_paint() -> void:
	var map := BuildingMap.new(Rect2i(0, 0, 20, 20))
	map.register_styles(PrisonCatalogue.FLOORS, PrisonCatalogue.WALLS)
	map.build_room(Rect2i(0, 0, 3, 3), &"concrete", &"plaster")
	var edge := Vector3i(1, 3, BuildingMap.EDGE_X)
	_check(BuildingMap.wall_side(edge, Vector2(1.5, 3.5)) == 0
			and BuildingMap.wall_side(edge, Vector2(1.5, 2.5)) == 1, "side 0 of a wall along X is towards +Z")
	_check(map.paint_side(edge, 1, &"brick"), "one side of a wall takes paint")
	_check(map.side_style(edge, 1) == &"brick" and map.side_style(edge, 0) == &"plaster"
			and map.wall_style(edge) == &"plaster", "only that side changes")
	_check(not map.paint_side(edge, 1, &"brick"), "painting it again changes nothing")
	_check(map.paint_side(edge, 1, &"plaster") and not map.wall_paints.has(edge),
			"painting with the wall's own style takes the paint off")
	_check(not map.paint_side(edge, 0, &"fence") and not map.paint_side(edge, 0, &"hedge"),
			"fences and hedges are not paints")
	map.build_walls([Vector3i(10, 10, BuildingMap.EDGE_X)], &"fence")
	_check(not map.paint_side(Vector3i(10, 10, BuildingMap.EDGE_X), 0, &"brick"), "fences cannot be painted")
	var inside := map.sides_facing(Vector2(1.5, 1.5))
	_check(inside.size() == 12 and inside.all(func(entry: Array) -> bool:
			var ends := BuildingMap.wall_ends(entry[0])
			var middle: Vector2 = (ends[0] + ends[1]) * 0.5
			return BuildingMap.wall_side(entry[0], Vector2(1.5, 1.5)) == entry[1] \
					and Rect2(0, 0, 3, 3).grow(0.01).has_point(middle)), "Shift finds every inner side of a room")
	_check(map.paint_sides(inside, &"wall_tiles") == 12 and map.side_style(edge, 1) == &"wall_tiles"
			and map.side_style(edge, 0) == &"plaster", "the whole room's inner sides paint at once")
	map.build_walls([edge], &"brick")
	_check(not map.wall_paints.has(edge), "restyling a wall takes its paint off")
	map.paint_side(edge, 0, &"wall_tiles")
	map.remove_walls([edge])
	_check(not map.wall_paints.has(edge), "removing a wall forgets its paint")
	# Angled walls: both sides, and Shift reaches them from the room.
	map.build_room(Rect2i(5, 0, 4, 4), &"concrete", &"plaster")
	var keys := BuildingMap.slants_on_line(Vector2i(5, 0), Vector2i(9, 4))
	map.build_slants(keys, &"plaster")
	var key := keys[0]
	_check(map.paint_side(key, BuildingMap.wall_side(key, Vector2(8, 1)), &"brick")
			and map.side_style(key, BuildingMap.wall_side(key, Vector2(6, 3))) == &"plaster",
			"angled walls take paint on one side")
	var corner := map.sides_facing(Vector2(8.5, 0.5))
	_check(corner.size() == 4 + 4 + 4 and corner.any(func(entry: Array) -> bool:
			return entry[0] is Vector4i and entry[0] == key),
			"the corner room's sides include the angled wall")
	map.remove_slants([key])
	_check(not map.slant_paints.has(key), "removing an angled wall forgets its paint")


## Walls meeting at a corner join at a mitre rather than overlapping, which
## flickers where their faces lie in the same plane.
func _test_wall_joins() -> void:
	var map := BuildingMap.new(Rect2i(0, 0, 20, 20))
	map.register_styles(PrisonCatalogue.FLOORS, PrisonCatalogue.WALLS)
	var grid := BuildGrid.new()
	var view := BuildingView.new()
	view.grid = grid
	root.add_child(view)
	var run := func(wall: Variant) -> BuildingView.WallRun:
		return view._make_run(wall, 0.0, 0.5, BuildingMap.Wall.WALL, &"")
	view.map = map
	# An L: along X from (2, 2) and along Z from (2, 2), brick and plaster.
	map.build_walls([Vector3i(2, 2, BuildingMap.EDGE_X)], &"brick")
	map.build_walls([Vector3i(2, 2, BuildingMap.EDGE_Z)], &"plaster")
	var a: BuildingView.WallRun = run.call(Vector3i(2, 2, BuildingMap.EDGE_X))
	var b: BuildingView.WallRun = run.call(Vector3i(2, 2, BuildingMap.EDGE_Z))
	var hubs := view._join_walls([a, b])
	_check(hubs.is_empty(), "an L needs no post")
	_check(is_equal_approx(a.side_from[0], b.half) and is_equal_approx(a.side_from[1], -b.half)
			and is_equal_approx(b.side_from[1], a.half) and is_equal_approx(b.side_from[0], -a.half),
			"an L's sides meet at a mitre, inner side short and outer side long")
	_check(is_equal_approx(a.side_to[0], a.length + a.half), "a lone end reaches past its corner")
	# Straight on: two walls end to end must not overlap.
	var c: BuildingView.WallRun = run.call(Vector3i(3, 2, BuildingMap.EDGE_X))
	a = run.call(Vector3i(2, 2, BuildingMap.EDGE_X))
	view._join_walls([a, c])
	_check(is_equal_approx(a.side_to[0], a.length) and is_equal_approx(a.side_to[1], a.length)
			and is_zero_approx(c.side_from[0]) and is_zero_approx(c.side_from[1]),
			"walls in a line meet end to end without overlapping")
	# A T gets a post in the middle; an angled wall mitres onto a straight one.
	a = run.call(Vector3i(2, 2, BuildingMap.EDGE_X))
	b = run.call(Vector3i(2, 2, BuildingMap.EDGE_Z))
	var d: BuildingView.WallRun = run.call(Vector3i(1, 2, BuildingMap.EDGE_X))
	_check(view._join_walls([a, b, d]).size() == 1, "a T-junction gets a post")
	var slant: BuildingView.WallRun = run.call(BuildingMap.slant_key(Vector2i(2, 2), Vector2i(3, 3)))
	a = run.call(Vector3i(2, 2, BuildingMap.EDGE_X))
	_check(view._join_walls([a, slant]).is_empty() and a.side_from[0] > 0.0 and slant.side_from[0] < 0.0,
			"an angled wall joins a straight one at a mitre")
	view.free()
	grid.free()


func _test_terrain() -> void:
	var terrain := Terrain.new()
	terrain.size = Vector2i(16, 16)
	_check(terrain.height_at(Vector2(3.5, 3.5)) == 0.0, "terrain starts flat")
	terrain.sculpt(Terrain.Brush.RAISE, Vector2(8, 8), 3.0, 1.0)
	_check(is_equal_approx(terrain.corner_height(Vector2i(8, 8)), 1.0), "raise lifts the middle fully")
	_check(terrain.corner_height(Vector2i(10, 8)) > 0.0 and terrain.corner_height(Vector2i(10, 8)) < 1.0,
			"raise falls off towards the rim")
	_check(terrain.corner_height(Vector2i(12, 8)) == 0.0, "raise leaves outside the brush alone")
	_check(terrain.last_changed == Rect2i(5, 5, 7, 7), "the terrain says which corners a brush touched")
	var far_map := BuildingMap.new(Rect2i(0, 0, 16, 16))
	far_map.build_room(Rect2i(0, 0, 3, 3), &"concrete", &"brick", 0.0)
	_check(not far_map.has_build_near(terrain.last_changed) and far_map.has_build_near(Rect2i(3, 3, 2, 2)),
			"buildings only redraw when the ground changes next to them")
	_check(is_equal_approx(terrain.height_at(Vector2(8.5, 8)),
			(terrain.corner_height(Vector2i(8, 8)) + terrain.corner_height(Vector2i(9, 8))) * 0.5),
			"heights blend between corners")

	terrain.is_locked = func(corner: Vector2i) -> bool: return corner == Vector2i(8, 8)
	terrain.sculpt(Terrain.Brush.LOWER, Vector2(8, 8), 3.0, 1.0)
	_check(is_equal_approx(terrain.corner_height(Vector2i(8, 8)), 1.0), "locked corners do not move")
	terrain.is_locked = func(_corner: Vector2i) -> bool: return false

	terrain.sculpt(Terrain.Brush.FLATTEN, Vector2(8, 8), 4.0, 1.0, 0.5)
	_check(is_equal_approx(terrain.corner_height(Vector2i(8, 8)), 0.5), "flatten pulls towards the target")
	terrain.sculpt(Terrain.Brush.RAISE, Vector2(8, 8), 2.0, 100.0)
	_check(terrain.corner_height(Vector2i(8, 8)) == Terrain.MAX_HEIGHT, "heights are clamped")
	terrain.flatten_cells(BuildingMap.cells_in(Rect2i(5, 5, 6, 6)), 0.0)
	terrain.set_corner_height(Vector2i(8, 8), 3.0)
	var spike := terrain.corner_height(Vector2i(8, 8))
	terrain.sculpt(Terrain.Brush.SMOOTH, Vector2(8, 8), 2.0, 1.0)
	_check(terrain.corner_height(Vector2i(8, 8)) < spike, "smooth lowers a spike")

	terrain.flatten_cells([Vector2i(2, 2), Vector2i(3, 2)], 2.0)
	_check(terrain.cell_height(Vector2i(2, 2)) == 2.0 and terrain.cell_height(Vector2i(3, 2)) == 2.0,
			"flatten_cells levels whole tiles")
	_check(not terrain.is_underwater(Vector2(14, 14)), "no water without a sea or ponds")
	terrain.has_sea = true
	terrain.flatten_cells([Vector2i(14, 14)], -2.0)
	_check(terrain.is_underwater(Vector2(14.5, 14.5)), "ground below the sea is under water")

	# A ray straight down lands on the ground, or on the water where it is lower.
	var hit: Variant = terrain.intersect_ray(Vector3(2.5, 20, 2.5), Vector3.DOWN)
	_check(hit != null and absf(hit.y - 2.0) < 0.01, "ray hits raised ground")
	hit = terrain.intersect_ray(Vector3(14.5, 20, 14.5), Vector3.DOWN)
	_check(hit != null and absf(hit.y - terrain.sea_level) < 0.01, "ray stops at the water")
	hit = terrain.intersect_ray(Vector3(5.5, 20, 5.5), Vector3(1, -1, 0))
	_check(hit != null and absf(hit.y - terrain.height_at(Vector2(hit.x, hit.z))) < 0.01,
			"slanted ray lands on the surface")
	terrain.free()


func _test_water() -> void:
	var terrain := Terrain.new()
	terrain.size = Vector2i(30, 30)
	var water := WaterLayer.new()
	water.terrain = terrain
	terrain.water = water
	# A bowl: ground 1 m up everywhere, dipping to -1 m in the middle, with
	# a low notch in the rim at 0.5 m on one side.
	terrain.generate(func(corner: Vector2i) -> float:
		var d := Vector2(corner).distance_to(Vector2(15, 15))
		return lerpf(-1.0, 1.0, clampf(d / 5.0, 0.0, 1.0)))
	_check(water.fill_at(Vector2i(2, 2)) == null, "flat ground holds no water")
	var body := water.fill_at(Vector2i(15, 15))
	_check(body != null, "a hollow fills with water")
	_check(body != null and absf(body.level - (1.0 - WaterLayer.RIM_GAP)) < 0.01, "water rises to the rim")
	_check(terrain.is_underwater(Vector2(15, 15)) and not terrain.is_underwater(Vector2(2, 2)),
			"the bowl is under water and the plain is not")
	_check(water.fill_at(Vector2i(15, 15)) == null, "a wet tile cannot be filled again")
	var size_before := body.cells.size()

	# Cutting a notch in the rim lowers the water to the notch.
	var notch := {}
	for x in range(15, 31):
		for z in range(14, 17):
			notch[Vector2i(x, z)] = minf(terrain.corner_height(Vector2i(x, z)), 0.5) if x > 15 \
					else terrain.corner_height(Vector2i(x, z))
	terrain.set_corners(notch)
	_check(water.bodies.size() == 1 and absf(water.bodies[0].level - (0.5 - WaterLayer.RIM_GAP)) < 0.06,
			"cutting the rim lets the water down to the notch")
	_check(water.bodies[0].cells.size() < size_before, "and the pond shrinks")

	# Blocked tiles (floors) stay dry.
	water.is_blocked = func(cell: Vector2i) -> bool: return cell == Vector2i(13, 15)
	water.refill()
	_check(water.body_at(Vector2i(13, 15)) == null, "water stays off blocked tiles")

	# Filling the whole bowl flat drains it.
	terrain.generate(func(_corner: Vector2i) -> float: return 1.0)
	_check(water.bodies.is_empty(), "flattening the ground drains the pond")
	water.free()
	terrain.free()


## Every object sits under one of the objects menu's tabs, and none is so
## crowded it runs off the screen.
func _test_object_categories() -> void:
	var counts := {}
	var lost := PackedStringArray()
	for def in PrisonCatalogue.OBJECTS:
		if not PrisonCatalogue.OBJECT_CATEGORIES.has(def.category):
			lost.append(def.display_name)
		counts[def.category] = counts.get(def.category, 0) + 1
	_check(lost.is_empty(), "every object is under a tab of the objects menu (%s)" % ", ".join(lost))
	_check(counts.values().all(func(n: int) -> bool: return n <= 12), "no tab has more than 12 objects")


## Upstairs walls beside a stairwell stand on the upstairs floor, not down
## on the ground hidden in the wall below.
func _test_walls_beside_stairs() -> void:
	var building := Building.new(Rect2i(0, 0, 20, 20), PrisonCatalogue.FLOORS, PrisonCatalogue.WALLS)
	var ground := building.ground()
	ground.build_room(Rect2i(2, 2, 4, 5), &"concrete", &"brick", 0.0)
	var up := building.level(1)
	up.build_room(Rect2i(2, 2, 4, 5), &"wood", &"brick", Building.STOREY)
	var route: Array[Vector2i] = [Vector2i(2, 3), Vector2i(2, 4), Vector2i(2, 5)]
	ground.add_stairs(Staircase.create(route, [false, false, false] as Array[bool]))
	var view := BuildingView.new()
	view.grid = BuildGrid.new()
	root.add_child(view)
	view.map = up
	_check(is_equal_approx(view._wall_base(Vector3i(2, 4, BuildingMap.EDGE_Z)), Building.STOREY),
			"an upstairs wall beside the stairs stands on the upstairs floor")
	view.queue_free()


func _test_building_levels() -> void:
	var building := Building.new(Rect2i(0, 0, 20, 20), PrisonCatalogue.FLOORS, PrisonCatalogue.WALLS)
	var ground := building.ground()
	ground.build_room(Rect2i(2, 2, 4, 4), &"concrete", &"brick", 0.5)
	_check(building.storey_height(1, Vector2i(3, 3), 0.0) == 0.5 + Building.STOREY,
			"upstairs floor goes a storey above the floor below")
	_check(building.storey_height(-1, Vector2i(3, 3), 0.0) == 0.5 - Building.STOREY,
			"a basement goes a storey below the floor above")
	_check(building.storey_height(-2, Vector2i(10, 10), 1.0) == 1.0 - 2.0 * Building.STOREY,
			"a deep basement under open ground is two storeys down")
	_check(building.is_supported(1, Vector2i(3, 3)) and not building.is_supported(1, Vector2i(10, 10)),
			"upper floors need floor below")
	building.active = 1
	_check(building.current() != ground and building.levels.size() == 2, "going up a level makes it")
	building.level(-1).fill_floor(Rect2i(12, 12, 2, 2), &"concrete", -3.0)
	_check(building.corner_in_use(Vector2i(13, 13)), "basements lock the ground above them")
	building.active = 99
	_check(building.active == Building.MAX_LEVEL, "levels are limited")
	building.add_land(Rect2i(20, 0, 5, 5))
	_check(building.level(1).owns(Vector2i(21, 1)), "new land reaches every level")

	# Stairs cut the floor above; lifts link with a lift above them.
	var lift: ObjectDef = load("res://games/prison/catalogue/lift.tres")
	var upstairs := building.level(1)
	upstairs.fill_floor(Rect2i(2, 2, 4, 4), &"wood", 0.5 + Building.STOREY)
	var route: Array[Vector2i] = [Vector2i(3, 2), Vector2i(3, 3), Vector2i(3, 4)]
	var flags: Array[bool] = [false, false, false]
	var flight := ground.add_stairs(Staircase.create(route, flags))
	_check(flight != 0 and not upstairs.has_floor(Vector2i(3, 3)) and upstairs.holes.has(Vector2i(3, 4))
			and upstairs.has_floor(Vector2i(4, 3)), "stairs cut a hole in the floor above")
	_check(upstairs.fill_floor(Rect2i(3, 2, 1, 3), &"wood", 0.5 + Building.STOREY) == 0,
			"no floor goes over a stairwell")
	var links := building.links()
	_check(links.size() == 2 and links[0].from_cell == Vector2i(3, 1) and links[0].to_level == 1
			and links[0].to_cell == Vector2i(3, 5), "stairs link the foot to the landing above")
	ground.remove_stairs(flight)
	_check(upstairs.holes.is_empty() and upstairs.fill_floor(Rect2i(3, 2, 1, 3), &"wood", 2.25) == 3,
			"removing stairs lets floor back in")
	_check(not building.can_add_stairs(Building.MAX_LEVEL, route), "no stairs on the top level")
	ground.place_object(lift, Vector2(4, 4), 0)
	_check(building.links().is_empty(), "a lift alone goes nowhere")
	upstairs.place_object(lift, Vector2(4, 4), 0)
	links = building.links()
	_check(links.size() == 2 and links[0].kind == Building.Link.Kind.LIFT,
			"lifts stacked up link")


func _test_people() -> void:
	var building := Building.new(Rect2i(0, 0, 20, 20), PrisonCatalogue.FLOORS, PrisonCatalogue.WALLS)
	var map := building.ground()
	map.build_room(Rect2i(2, 2, 8, 5), &"concrete", &"brick", 0.0)
	map.place_object(PrisonCatalogue.object(&"bed"), Vector2(8, 2), 0)
	var people := People.new()
	people.needs = PrisonCatalogue.NEEDS
	people.building = building
	var sleepy := people.add_person(0, Vector2(3.5, 5.5), "Test Person")
	_check(sleepy != null and sleepy.needs.size() == PrisonCatalogue.NEEDS.size(), "people start with every need")
	_check(people.add_person(0, Vector2(15.5, 15.5)) != null, "people can stand on open ground")
	for need: StringName in sleepy.needs:
		sleepy.needs[need] = 100.0
	sleepy.needs[&"sleep"] = 10.0
	people.step(0.5)
	_check(sleepy.state == Person.State.WALKING and sleepy.activity.contains("bed"), "a sleepy person heads for a bed")
	for i in 100:
		people.step(0.1)
	_check(sleepy.state == Person.State.USING and sleepy.activity == "Sleeping", "and sleeps in it")
	# Game minutes: a night's sleep takes hours.
	for i in 480:
		people.step(1.0)
	_check(sleepy.state != Person.State.USING and sleepy.needs[&"sleep"] > 90.0, "and gets up rested")
	for need: StringName in sleepy.needs:
		sleepy.needs[need] = 100.0
	sleepy.needs[&"hunger"] = 30.0
	sleepy.gave_up.clear()
	people.step(0.5)
	_check(sleepy.reason == "Can't find a free table", "with no table, they say so")
	_check(people.send(sleepy, 0, Vector2(15.5, 15.5)) == false and sleepy.activity == "Can't get there",
			"people can't be sent through walls")
	map.set_door(BuildingMap.edge_between(Vector2i(5, 6), Vector2i(5, 7)), true)
	_check(people.send(sleepy, 0, Vector2(15.5, 15.5)), "but can go out of a door")
	# Once there they may wander off again, so watch for them getting close.
	var nearest := INF
	for i in 200:
		people.step(0.1)
		nearest = minf(nearest, sleepy.flat().distance_to(Vector2(15.5, 15.5)))
	_check(nearest < 1.0, "and walk out over the ground")
	people.remove_person(sleepy)
	_check(people.people.size() == 1, "people can be removed")
	var ground := Terrain.new()
	people.terrain = ground
	people._ready()
	people.nav()
	ground.sculpt(Terrain.Brush.RAISE, Vector2(15, 15), 2.0, 0.1)
	_check(not people._dirty, "sculpting doesn't rebuild the walking graph straight away")
	people._process(0.2)
	_check(not people._dirty, "nor while the ground is still changing")
	people.paused = true
	people._process(0.4)
	_check(people._dirty, "but does once the ground settles")
	ground.free()
	people.free()


func _test_door_steps() -> void:
	var building := Building.new(Rect2i(0, 0, 20, 12), PrisonCatalogue.FLOORS, PrisonCatalogue.WALLS)
	var map := building.ground()
	map.build_room(Rect2i(2, 2, 4, 4), &"concrete", &"brick", 0.0)
	map.build_room(Rect2i(6, 2, 4, 4), &"concrete", &"brick", 0.75)
	var edge := BuildingMap.edge_between(Vector2i(5, 3), Vector2i(6, 3))
	_check(is_equal_approx(map.door_rise(edge), 0.75), "the floors either side of a wall can differ")
	_check(not map.set_door(edge, true), "with door steps off, a door between them is refused")
	Building.door_steps = true
	_check(map.set_door(edge, true), "with door steps on, the door goes in")
	_check(map.door_steps() == {edge: Vector2i(5, 3)}, "and gets steps on the low side")
	_check(not map.can_place_at(PrisonCatalogue.object(&"toilet"), Vector2(5.5, 3.5), 0.0),
			"nothing can stand on door steps")
	var graph := NavGraph.build(building)
	var walk := graph.find_path(0, Vector2(2.5, 4.5), 0, Vector2(8.5, 3.5))
	_check(not walk.is_empty(), "people can climb door steps")
	var climbs_at_door := false
	for point in walk:
		if Vector2(point.x, point.z).distance_to(Vector2(5.5, 3.5)) < 0.1:
			climbs_at_door = true
	_check(climbs_at_door, "and their route goes by the steps")
	var far := BuildingMap.edge_between(Vector2i(5, 5), Vector2i(6, 5))
	map.set_floor_heights({Vector2i(6, 5): 1.5})
	_check(not map.set_door(far, true), "steps only make up a metre")
	Building.door_steps = false
	_check(map.door_steps().is_empty(), "turning door steps off removes them")
	_check(map.unusable_doors() == ([edge] as Array[Vector3i]), "and the door is flagged as one nobody can use")


func _test_nav_graph() -> void:
	var building := Building.new(Rect2i(0, 0, 30, 20), PrisonCatalogue.FLOORS, PrisonCatalogue.WALLS)
	var ground := building.ground()
	# Two rooms side by side, sharing a wall with a door in it.
	ground.build_room(Rect2i(2, 2, 4, 4), &"concrete", &"brick", 0.0)
	ground.build_room(Rect2i(6, 2, 4, 4), &"concrete", &"brick", 0.0)
	var graph := NavGraph.build(building)
	_check(graph.find_path(0, Vector2(3.5, 3.5), 0, Vector2(8.5, 3.5)).is_empty(),
			"no way between rooms with no door")
	ground.set_door(BuildingMap.edge_between(Vector2i(5, 4), Vector2i(6, 4)), true)
	graph = NavGraph.build(building)
	var walk := graph.find_path(0, Vector2(3.5, 3.5), 0, Vector2(8.5, 3.5))
	var through_door := false
	for p in walk:
		through_door = through_door or (absf(p.z - 4.5) < 0.01 and absf(p.x - 6.0) < 0.6)
	_check(through_door, "people go through the door")
	_check(walk.size() <= 5, "straight stretches are walked in one go")
	# Out of a room through an outside door onto open ground.
	ground.set_door(BuildingMap.edge_between(Vector2i(3, 5), Vector2i(3, 6)), true)
	graph = NavGraph.build(building)
	_check(not graph.find_path(0, Vector2(3.5, 3.5), 0, Vector2(15.5, 12.5)).is_empty(),
			"people walk out of doors and over open ground")
	_check(graph.point_at(0, Vector2(40, 40)) == -1, "nobody walks off your land")
	# Upstairs by the stairs, and by the lift.
	var up := building.level(1)
	up.build_room(Rect2i(2, 2, 8, 4), &"wood", &"brick", Building.STOREY)
	var route: Array[Vector2i] = [Vector2i(3, 3), Vector2i(4, 3), Vector2i(5, 3)]
	ground.add_stairs(Staircase.create(route, [false, false, false] as Array[bool]))
	graph = NavGraph.build(building)
	var climb := graph.find_path(0, Vector2(2.5, 4.5), 1, Vector2(8.5, 4.5))
	var on_stairs := false
	for p in climb:
		on_stairs = on_stairs or (p.y > 0.5 and p.y < 1.5)
	_check(on_stairs, "people climb the stairs to the floor above")
	building.ground().remove_stairs(building.ground().stairs.keys()[0])
	graph = NavGraph.build(building)
	_check(graph.find_path(0, Vector2(2.5, 4.5), 1, Vector2(8.5, 4.5)).is_empty(), "no stairs, no way up")
	var lift: ObjectDef = load("res://games/prison/catalogue/lift.tres")
	ground.place_object(lift, Vector2(8, 4), 0)
	up.place_object(lift, Vector2(8, 4), 0)
	graph = NavGraph.build(building)
	_check(not graph.find_path(0, Vector2(2.5, 4.5), 1, Vector2(3.5, 4.5)).is_empty(), "people take the lift")
	# Ground paths are cheaper to walk than open ground.
	var paths := PathNetwork.new()
	paths.add_segment(Vector2(12.5, 8.5), Vector2(12.5, 16.5))
	graph = NavGraph.build(building, paths)
	var along := graph.find_path(0, Vector2(12.5, 8.5), 0, Vector2(12.5, 16.5))
	_check(along.size() == 2, "a path is walked straight along")
	# Reusing the ground layer after a building change gives the same graph
	# as working everything out again.
	ground.build_room(Rect2i(14, 10, 4, 3), &"concrete", &"fence", 0.0)
	var reused := NavGraph.build(building, paths, null, graph.ground_layer)
	var fresh := NavGraph.build(building, paths)
	var joins := func(g: NavGraph) -> int:
		var count := 0
		for id in g.astar.get_point_ids():
			count += g.astar.get_point_connections(id).size()
		return count
	_check(reused.ground_layer == graph.ground_layer
			and reused.astar.get_point_count() == fresh.astar.get_point_count()
			and joins.call(reused) == joins.call(fresh), "the ground layer is reused when only the building changes")
	# A built bridge crosses what the ground cannot.
	var land := Building.new(Rect2i(0, 0, 10, 10))
	var walls_off := PathNetwork.new()
	land.ground().build_walls(BuildingMap.edges_on_line(Vector2i(5, 0), Vector2i(5, 10)), &"fence")
	graph = NavGraph.build(land, walls_off)
	_check(graph.find_path(0, Vector2(2.5, 5.5), 0, Vector2(8.5, 5.5)).is_empty(), "a fence blocks the way")
	walls_off.add_segment(Vector2(1.5, 5.5), Vector2(3.5, 5.5), null, &"", true, NAN, 1.25)
	walls_off.add_segment(Vector2(3.5, 5.5), Vector2(7.5, 5.5), null, &"", true, NAN, 1.25)
	walls_off.add_segment(Vector2(7.5, 5.5), Vector2(9.5, 5.5), null, &"", true)
	graph = NavGraph.build(land, walls_off)
	_check(not graph.find_path(0, Vector2(0.5, 5.5), 0, Vector2(8.5, 6.5)).is_empty(),
			"people walk over built paths")


func _test_stair_builder() -> void:
	var tool := StairTool.new()
	# Before the first click it shows a straight flight; a click there sets the foot.
	var straight := tool.plan(Vector2i(2, 2))
	_check(straight[2] and straight[0] == [Vector2i(2, 2), Vector2i(2, 3), Vector2i(2, 4)],
			"stairs start as a straight flight of three tiles")
	_check(tool.press(Vector2i(2, 2)) == null and tool.is_drawing(), "the first click sets the foot")
	var east := tool.plan(Vector2i(9, 2))
	_check(east[2] and east[0][2] == Vector2i(4, 2), "moving off to one side climbs that way")
	# Up two tiles, a landing, across, another landing, and back down.
	_check(tool.press(Vector2i(2, 4)) == null and tool.steps_left() == 1, "a click short of the top adds a landing")
	_check(tool.press(Vector2i(3, 4)) == null and tool.steps_left() == 1, "landings can sit side by side")
	var back := tool.plan(Vector2i(3, 0))
	_check(back[2] and back[0] == [Vector2i(2, 2), Vector2i(2, 3), Vector2i(2, 4), Vector2i(3, 4), Vector2i(3, 3)]
			and back[1] == [false, false, true, true, false], "stairs can turn back on themselves")
	tool.rounded = true
	var flight := tool.press(Vector2i(3, 0))
	_check(flight != null and not tool.is_drawing() and flight.entry() == Vector2i(2, 1)
			and flight.exit() == Vector2i(3, 2), "the last click builds the stairs")
	var treads := flight.treads()
	_check(treads.size() == 8 and is_equal_approx(treads[3][1], 1.0) and is_equal_approx(treads[4][1], 1.0)
			and is_equal_approx(treads[-1][1], 1.5), "every step rises the same, and landings stay level")
	_check(is_equal_approx(flight.top_height() + Staircase.RISE, Building.STOREY), "seven steps make a storey")
	var outline: PackedVector2Array = treads[4][0]
	_check(outline.size() > 4 and outline[0] == Vector2(3, 4), "rounded landings swing round the inside corner")

	var map := BuildingMap.new(Rect2i(0, 0, 10, 10))
	map.fill_floor(Rect2i(0, 0, 8, 8))
	_check(map.add_stairs(flight) != 0 and map.stairs_at(Vector2i(3, 4)) == flight, "stairs go on floor")
	var bed: ObjectDef = load("res://games/prison/catalogue/bed.tres")
	_check(not map.can_place_at(bed, Vector2(2.5, 3.0), 0.0), "nothing can be placed on stairs")
	_check(not map.can_build_wall(BuildingMap.edge_between(Vector2i(2, 3), Vector2i(2, 4))),
			"no wall across a flight")
	_check(map.can_build_wall(BuildingMap.edge_between(Vector2i(2, 3), Vector2i(3, 3))),
			"walls can run between the two halves")
	var walled: Array[Vector2i] = [Vector2i(5, 1), Vector2i(5, 2), Vector2i(5, 3)]
	map.build_walls([BuildingMap.edge_between(Vector2i(5, 1), Vector2i(5, 2))])
	_check(not map.can_add_stairs(walled), "stairs cannot climb through a wall")
	map.demolish(Rect2i(3, 3, 1, 1))
	_check(map.stairs.is_empty(), "demolishing any of the stairs removes them")


func _test_ramps() -> void:
	var map := BuildingMap.new(Rect2i(0, 0, 10, 10))
	map.fill_floor(Rect2i(0, 0, 5, 2), &"concrete", 0.0)
	map.set_floor_heights({Vector2i(4, 0): 1.0, Vector2i(4, 1): 1.0})
	_check(not map.can_walk_between(Vector2i(3, 0), Vector2i(4, 0)), "a tall split blocks the way")
	_check(map.add_ramp(Rect2i(1, 0, 3, 2), Vector2i.RIGHT, 0.0, 1.0), "a ramp goes over floor")
	_check(map.can_walk_between(Vector2i(0, 0), Vector2i(1, 0))
			and map.can_walk_between(Vector2i(1, 0), Vector2i(2, 0))
			and map.can_walk_between(Vector2i(3, 0), Vector2i(4, 0)), "a ramp joins the two heights")
	_check(is_equal_approx(map.floor_height(Vector2i(2, 1)), 0.5), "a ramp tile sits at its middle height")
	_check(not map.add_ramp(Rect2i(2, 0, 2, 1), Vector2i.RIGHT, 0.0, 1.0), "ramps do not overlap")
	_check(map.place_object(load("res://games/prison/catalogue/bed.tres"), Vector2(2, 0), 0) == 0,
			"nothing is placed on a ramp")
	map.set_floor_heights({Vector2i(2, 0): 0.25})
	_check(map.ramps.is_empty(), "nudging a ramp flattens it back to tiles")
	map.add_ramp(Rect2i(1, 0, 3, 2), Vector2i.RIGHT, 0.0, 1.0)
	map.clear_floor(Rect2i(1, 0, 1, 1))
	_check(map.ramps.is_empty(), "clearing floor under a ramp removes it")


func _test_angled_walls() -> void:
	var map := BuildingMap.new(Rect2i(0, 0, 20, 20))
	map.register_styles(PrisonCatalogue.FLOORS, PrisonCatalogue.WALLS)
	map.build_room(Rect2i(0, 0, 4, 4), &"wood", &"plaster")
	_check(BuildingMap.slants_on_line(Vector2i(0, 0), Vector2i(4, 2))
			== [Vector4i(0, 0, 2, 1), Vector4i(2, 1, 4, 2)], "a 1:2 line is two wall pieces")
	_check(BuildingMap.slants_on_line(Vector2i(0, 0), Vector2i(0, 4)).is_empty(),
			"straight lines are left to ordinary walls")
	map.build_slants(BuildingMap.slants_on_line(Vector2i(0, 0), Vector2i(4, 4)), &"plaster")
	_check(map.slants.size() == 4 and map.pieces(Vector2i(2, 2)).size() == 2
			and map.pieces(Vector2i(2, 1)).size() == 1, "a diagonal wall cuts the tiles it crosses")
	var rooms := map.rooms()
	_check(rooms.size() == 2 and is_equal_approx(rooms[0].area, 8.0) and is_equal_approx(rooms[1].area, 8.0)
			and rooms[0].indoor and rooms[1].indoor, "a diagonal wall splits a room in two")
	_check(map.room_at_point(Vector2(2.8, 2.2)) != map.room_at_point(Vector2(2.2, 2.8)),
			"each half of a cut tile belongs to its own side")
	_check(map.place_object(load("res://games/prison/catalogue/bed.tres"), Vector2(1, 1), 0) == 0,
			"objects cannot straddle an angled wall")
	_check(map.set_piece_floors([map.piece_at(Vector2(3.8, 3.2))], &"") == 1
			and not map.room_at_point(Vector2(3.5, 2.5)).enclosed
			and is_equal_approx(map.room_at_point(Vector2(3.5, 2.5)).area, 7.5),
			"taking up half a tile leaves a gap in the room")
	map.set_piece_floors([map.piece_at(Vector2(3.8, 3.2))], &"wood")
	map.set_piece_floors(map.pieces_within_walls(Vector2(2.8, 2.2)), &"tiles")
	_check(map.piece_floor(map.piece_at(Vector2(2.8, 2.2))) == &"tiles"
			and map.piece_floor(map.piece_at(Vector2(2.2, 2.8))) == &"wood"
			and map.pieces_within_walls(Vector2(2.8, 2.2)).size() == 4 + 6,
			"each side of an angled wall keeps its own floor style")
	map.set_slant_opening(Vector4i(1, 1, 2, 2), BuildingMap.Wall.DOOR)
	_check(map.slant_at(Vector4i(1, 1, 2, 2)) == BuildingMap.Wall.DOOR and map.rooms().size() == 2,
			"a door in an angled wall still splits rooms")
	map.remove_slants(map.slants.keys())
	_check(map.rooms().size() == 1 and is_equal_approx(map.rooms()[0].area, 16.0),
			"removing the angled wall joins the room again")
	map.build_slants(BuildingMap.slants_on_line(Vector2i(0, 0), Vector2i(4, 2)), &"plaster")
	var total := 0.0
	for room in map.rooms():
		total += room.area
	_check(map.rooms().size() == 2 and is_equal_approx(total, 16.0), "a shallow angle splits the room too")
	map.demolish(Rect2i(0, 0, 4, 4))
	_check(map.slants.is_empty(), "demolishing takes angled walls with it")


func _test_path_network() -> void:
	# A ground path ending under a raised bridge stays on the ground; one
	# raised to the bridge's height joins it.
	var raised := PathNetwork.new()
	var bridge := raised.add_segment(Vector2(0, 0), Vector2(10, 0), null, &"", true, 2.0, 2.0)
	var under := raised.add_segment(Vector2(5, 6), Vector2(5, 0.2))
	_check(under.b != bridge.b and raised.segments.size() == 2, "a ground path doesn't join a bridge in mid-air")
	var up := raised.add_segment(Vector2(3, 6), Vector2(3, 0.2), null, &"", true, NAN, 2.0)
	_check(raised.segments.size() == 4 and raised.segments_at(up.b).size() == 3, "one built up to it does")
	_check(is_equal_approx(raised.snap_height(Vector2(7, 0.2)), 2.0) and is_nan(raised.snap_height(Vector2(5, 6))),
			"an end snapped onto a bridge takes its height, so the path tool joins it")
	# A curve crossing a path twice makes two junctions.
	var twice := PathNetwork.new()
	twice.add_segment(Vector2(0.5, 5.5), Vector2(10.5, 5.5))
	twice.add_segment(Vector2(2.5, 2.5), Vector2(8.5, 2.5), Vector2(5.5, 12.5))
	var junctions := 0
	for node: int in twice.nodes:
		if twice.segments_at(node).size() == 4:
			junctions += 1
	_check(junctions == 2 and twice.segments.size() == 6, "a curve crossing a path twice joins it twice")

	var paths := PathNetwork.new()
	var first := paths.add_segment(Vector2(0, 0), Vector2(10, 0))
	_check(paths.nodes.size() == 2 and paths.segments.size() == 1, "a segment adds two nodes")
	var second := paths.add_segment(Vector2(10.3, 0.2), Vector2(10, 8))
	_check(second.a == first.b and paths.nodes.size() == 3, "an end near a node joins it")
	paths.add_segment(Vector2(5, 0.3), Vector2(5, -6))
	_check(paths.segments.size() == 4 and paths.nodes.size() == 5, "an end on a segment splits it into a junction")
	var junction := paths.node_near(Vector2(5, 0))
	_check(junction != -1 and paths.segments_at(junction).size() == 3, "the junction joins three segments")
	_check(paths.add_segment(Vector2(1, 1), Vector2(1.2, 1.1)) == null, "a segment needs two different ends")
	var curved := paths.add_segment(Vector2(20, 0), Vector2(30, 0), Vector2(25, 5))
	var top := paths.point_on(curved, 0.5)
	_check(absf(top.y - 2.5) < 0.01 and paths.length(curved) > 10.5, "the control point bends the curve")
	var mid := paths.split(curved, 0.5)
	_check(paths.node_position(mid).distance_to(top) < 0.01, "splitting keeps the shape")
	_check(paths.remove_segment(curved.id) and not paths.nodes.has(curved.a), "removing a segment drops lonely nodes")
	_check(paths.remove_in_rect(Rect2(4, -7, 2, 5)) == 1, "remove_in_rect removes paths running through it")

	# Crossing paths meet at a new junction; a path well above passes over.
	var grid := PathNetwork.new()
	grid.add_segment(Vector2(0, 5), Vector2(10, 5))
	var across := grid.add_segment(Vector2(5, 0), Vector2(5, 10))
	var middle := grid.node_near(Vector2(5, 5), 0.1)
	_check(middle != -1 and grid.segments_at(middle).size() == 4 and across.b == middle,
			"a path crossing another makes a junction")
	var before := grid.segments.size()
	grid.add_segment(Vector2(2, 0), Vector2(2, 10), null, &"", true, 2.0, 2.0)
	_check(grid.segments.size() == before + 1, "a bridge passes over a path without joining it")
	_check(is_equal_approx(grid.node_height(grid.node_near(Vector2(2, 0), 0.1)), 2.0),
			"built ends keep their height")


func _test_path_profile() -> void:
	var terrain := Terrain.new()
	terrain.size = Vector2i(30, 10)
	var water := WaterLayer.new()
	water.terrain = terrain
	terrain.water = water
	# Flat at 1 m, a steep step up to 3 m at x = 20, and a pond around x = 8.
	terrain.generate(func(corner: Vector2i) -> float:
		if corner.x >= 20:
			return 3.0
		if corner.x >= 6 and corner.x <= 10 and corner.y >= 3 and corner.y <= 7:
			return -0.5
		return 1.0)
	water.fill_at(Vector2i(8, 5))
	var flat := PathProfile.build(PathNetwork.sample_curve(Vector2(1, 5), Vector2(2, 5), Vector2(4, 5)), terrain)
	_check(not flat.has_kind(PathProfile.Kind.STEPS) and not flat.has_kind(PathProfile.Kind.BRIDGE),
			"a flat path stays on the ground")
	var pond_curve := PathNetwork.sample_curve(Vector2(3, 5), Vector2(8, 5), Vector2(13, 5))
	_check(not PathProfile.build(pond_curve, terrain).problem.is_empty(), "a ground path cannot go through a pond")
	_check(not PathProfile.build(pond_curve, terrain, true).problem.is_empty(),
			"a bridge level with the banks is too low over the water")
	var over := PathProfile.build(pond_curve, terrain, true, 1.5, 1.5)
	_check(over.has_kind(PathProfile.Kind.BRIDGE) and over.problem.is_empty(),
			"a built path over the pond is a bridge")
	var lowest := INF
	for i in over.points.size():
		if over.points[i].x > 6.5 and over.points[i].x < 9.5:
			lowest = minf(lowest, over.heights[i])
	_check(lowest >= water.bodies[0].level + PathProfile.BRIDGE_CLEARANCE - 0.01, "the bridge stays above the water")
	var steep := PathNetwork.sample_curve(Vector2(17, 2), Vector2(19.5, 2), Vector2(22, 2))
	_check(not PathProfile.build(steep, terrain).problem.is_empty(), "a steep ground path is too steep")
	var up := PathProfile.build(steep, terrain, true)
	_check(up.has_kind(PathProfile.Kind.STEPS) and up.steps == 8, "built, it is stairs with steps like indoors")
	var cliff := PathNetwork.sample_curve(Vector2(19.8, 2), Vector2(20, 2), Vector2(20.2, 2))
	_check(not PathProfile.build(cliff, terrain, true, NAN, 3.0 + 2.0).problem.is_empty(),
			"stairs cannot be steeper than their treads allow")
	water.free()
	terrain.free()


func _test_foliage() -> void:
	var foliage := FoliageLayer.new()
	var tree: FoliageDef = PrisonCatalogue.PLANTS[0]
	var flower: FoliageDef = PrisonCatalogue.PLANTS[3]
	_check(foliage.add(tree, Vector2(5, 5)), "first tree goes in")
	_check(not foliage.add(tree, Vector2(5.5, 5)), "trees keep their spacing")
	_check(foliage.add(tree, Vector2(5 + tree.spacing + 0.1, 5)), "a tree further away goes in")
	_check(not foliage.add(flower, Vector2(5.1, 5)), "nothing grows right on top of a tree")
	_check(foliage.add(flower, Vector2(5.5, 5.2)), "flowers can grow near a tree")
	var sparse := FoliageLayer.new()
	sparse.add(tree, Vector2(5, 5))
	_check(not sparse.add(tree, Vector2(5 + tree.spacing + 0.1, 5), 1.0, 0.0, 2.0),
			"a lower density keeps trees further apart")
	_check(sparse.add(tree, Vector2(5 + tree.spacing * 2.0 + 0.1, 5), 1.0, 0.0, 2.0),
			"but no further than it says")
	sparse.free()
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	var added := foliage.paint(flower, Vector2(20, 20), 3.0, 50, rng,
			func(p: Vector2) -> bool: return p.x < 20.0)
	_check(added > 0 and foliage.plants.all(func(p: FoliageLayer.Plant) -> bool:
		return p.position.x < 20.0 or p.def == tree), "painting respects can_grow")
	_check(foliage.remove_in_rect(Rect2(4, 4, 2, 2)) == 2, "remove_in_rect clears an area")
	var count := foliage.plants.size()
	_check(foliage.remove_in_circle(Vector2(20, 20), 3.5) == count - 1, "remove_in_circle clears the rest")
	foliage.free()


func _test_misconduct() -> void:
	var model := MisconductModel.new()
	_check(model.temper_after(0.0, 10.0, 1.0) > 0.0, "temper builds while unhappy")
	_check(model.temper_after(50.0, 80.0, 1.0) < 50.0, "and cools while content")
	_check(is_equal_approx(model.chance(80.0, true), model.chance(80.0, false) * model.watched_factor),
			"a guard close by makes acting up less likely")
	var hothead: TraitDef = preload("res://games/prison/catalogue/trait_hothead.tres")
	_check(model.temper_after(0.0, 10.0, 1.0, hothead.temper_scale) > model.temper_after(0.0, 10.0, 1.0),
			"hotheads boil over sooner")
	var main: Node = load("res://games/prison/main.tscn").instantiate()
	main.sample = 9
	root.add_child(main)
	var people: People = main.people
	var misconduct: Misconduct = main.misconduct
	var prisoners: Array = people.people.filter(func(p: Person) -> bool: return p.group == &"prisoner")
	var prisoner: Person = prisoners[0]
	prisoner.mood = 40.0
	_check(model.pick(misconduct.rungs, 40.0, {}, [] as Array[StringName], RandomNumberGenerator.new()).id == &"grumble",
			"only grumbling while merely fed up")
	misconduct.act(prisoner, misconduct.rung(&"grumble"))
	_check(not prisoner.bubble.is_empty() and prisoner.record.is_empty(), "grumbling shows a bubble and leaves no record")
	# Warnings: a lifted mood calls it off.
	prisoner.warning = &"vandalism"
	prisoner.warning_minutes = 10.0
	prisoner.mood = 90.0
	misconduct.tick(1.0)
	_check(prisoner.warning == &"", "cheering someone up calls off what they were about to do")
	# Vandalism breaks the nearest breakable thing and goes on the record.
	var tvs: Array[Vector2i] = main.building.objects_tagged([&"toilet"] as Array[StringName])
	var key := tvs[0]
	var placed: BuildingMap.PlacedObject = main.building.object_at(key)
	var vandal: Person = prisoners[1]
	vandal.level = key.x
	vandal.position = Vector3(placed.centre.x, vandal.position.y, placed.centre.y)
	vandal.mood = 10.0
	misconduct.act(vandal, misconduct.rung(&"vandalism"))
	_check((main.wear as Wear).is_broken(key), "vandals break things")
	_check(vandal.record.size() == 1 and String(vandal.record[0][2]).begins_with("broke the toilet"),
			"and it goes on their record with the reason (%s)" % [vandal.record])
	# Mischief: off the timetable for a while.
	var imp: Person = prisoners[2]
	misconduct.act(imp, misconduct.rung(&"mischief"))
	_check(imp.truant_minutes > 0.0, "mischief takes them off the timetable")
	people._decide(imp, true)
	_check(imp.reason.begins_with("Up to no good"), "and they wander about up to no good")
	for i in 70:
		(main.clock as GameClock).advance(1.0)
	_check(imp.truant_minutes == 0.0, "for an hour")
	# Left alone and miserable, someone acts up sooner or later.
	var acted := []
	for person: Person in prisoners:
		person.temper = 100.0
		person.mood = 15.0
		for hour in 10:
			if person.warning == &"" and misconduct.roll(person) != null:
				acted.append(person)
	_check(not acted.is_empty(), "unhappy prisoners act up")
	main.queue_free()


func _test_contraband() -> void:
	var main: Node = load("res://games/prison/main.tscn").instantiate()
	main.sample = 10
	root.add_child(main)
	var people: People = main.people
	var items: ItemStore = main.items
	var contraband: Contraband = main.contraband
	var searching: Searching = main.searching
	var clock: GameClock = main.clock
	searching.random_per_day = 0
	var prisoners: Array = people.people.filter(func(p: Person) -> bool:
		return p.group == &"prisoner" and not people.home_room(p).is_empty())
	var prisoner: Person = prisoners[0]
	prisoner.traits.clear()
	prisoner.mood = 80.0
	_check(not contraband.tempted(prisoner), "content prisoners leave things be")
	prisoner.mood = 20.0
	_check(contraband.tempted(prisoner), "unhappy ones are tempted")
	var tables: Array[Vector2i] = main.building.objects_tagged([&"table"] as Array[StringName])
	var spoon := contraband.pocket_from(prisoner, main.building.object_at(tables[0]))
	_check(spoon != null and spoon.id == &"spoon" and prisoner.pocket.has(spoon), "a spoon from the canteen goes in their pocket")
	# Hidden in their cell, in whatever hides best.
	var home := people.home_room(prisoner)
	var room: Room = home[1]
	people.stop(prisoner)
	prisoner.level = home[0]
	prisoner.position = Vector3(room.cells[0].x + 0.5, prisoner.position.y, room.cells[0].y + 0.5)
	var spot := contraband.hiding_place(prisoner)
	_check(spot != Vector2i(-1, -1), "their cell has somewhere to hide it")
	contraband.tick()
	_check(prisoner.pocket.is_empty() and items.hidden.has(spot) and items.stash_owner[spot] == prisoner.id,
			"and they hide it there")
	_check(Searching.find_chance(0.6, 0) < Searching.find_chance(0.3, 0)
			and Searching.find_chance(0.6, 3) > Searching.find_chance(0.6, 0),
			"good hiding places are found less often, messy cells more")
	# A guard searches the cell, again until it turns up.
	var found := []
	searching.found.connect(func(owner: Person, def: ItemDef, _where: String) -> void: found.append([owner, def]))
	for attempt in 15:
		if not found.is_empty():
			break
		_check(searching.search_cell(home[0], room) != null, "a cell search goes up as a job")
		var minutes := 0
		while not searching.jobs.of_kind(&"search").is_empty() and minutes < 240:
			clock.advance(1.0)
			minutes += 1
		_check(searching.jobs.of_kind(&"search").is_empty(), "and a guard does it")
	_check(not found.is_empty() and found[0][0] == prisoner and found[0][1] == spoon and not items.hidden.has(spot),
			"the spoon is found and taken away")
	_check(prisoner.record.any(func(e: Array) -> bool: return e[1] == &"contraband"), "and goes on their record")
	_check(prisoner.moodlets.has(&"searched"), "having their cell turned over puts them out")
	# A person search finds what's in their pocket (before they can hide it).
	contraband.enabled = false
	var other: Person = prisoners[1]
	other.pocket.append(contraband.item(&"screwdriver"))
	found.clear()
	searching.search_person(other)
	var held := false
	var minutes := 0
	while not searching.jobs.of_kind(&"search").is_empty() and minutes < 240:
		clock.advance(1.0)
		minutes += 1
		held = held or other.led
	_check(held and not other.led, "a guard stops them while they're searched, then lets them go")
	_check(other.pocket.is_empty() and not found.is_empty(), "and finds the screwdriver")
	# Treats are eaten when low.
	contraband.enabled = true
	other.pocket.append(contraband.item(&"biscuit"))
	other.mood = 20.0
	contraband.tick()
	_check(other.pocket.is_empty() and other.moodlets.has(&"had_a_biscuit"), "a biscuit cheers someone up")
	# Saved and loaded.
	items.hide_in(spot, contraband.item(&"mallet"), prisoner.id)
	other.pocket.append(contraband.item(&"spoon"))
	_check(PrisonSave.write("test", PrisonSave.capture(main)) == OK, "a prison with contraband saves")
	main.queue_free()
	PrisonSave.pending = PrisonSave.read("test")
	main = load("res://games/prison/main.tscn").instantiate()
	root.add_child(main)
	_check((main.items as ItemStore).hidden.has(spot), "stashes are saved")
	var again: Array = (main.people as People).people.filter(func(p: Person) -> bool: return p.id == other.id)
	_check(not again.is_empty() and again[0].pocket.size() == 1, "and so are pockets")
	main.queue_free()


func _test_fights() -> void:
	_check(Health.injury(100.0) == Health.Injury.NONE and Health.injury(80.0) == Health.Injury.BRUISED
			and Health.injury(50.0) == Health.Injury.HURT and Health.injury(20.0) == Health.Injury.KNOCKED_OUT,
			"health bands: bruised, hurt, knocked out")
	_check(Health.pace(50.0) < 1.0, "the hurt limp")
	var main: Node = load("res://games/prison/main.tscn").instantiate()
	main.sample = 10
	root.add_child(main)
	var people: People = main.people
	var fights: Fights = main.fights
	var infirmary: Infirmary = main.infirmary
	var clock: GameClock = main.clock
	var misconduct: Misconduct = main.misconduct
	misconduct.enabled = false
	(main.searching as Searching).random_per_day = 0
	var minutes := 0
	while not people.people.any(func(p: Person) -> bool: return p.role == &"guard") and minutes < 240:
		clock.advance(1.0)
		minutes += 1
	var prisoners: Array = people.people.filter(func(p: Person) -> bool: return p.group == &"prisoner")
	var a: Person = prisoners[0]
	var b: Person = prisoners[1]
	for p: Person in [a, b]:
		people.stop(p)
		p.level = 0
		p.traits.clear()
	b.position = a.position + Vector3(0.6, 0.0, 0.0)
	people._buckets_fresh = false
	var fight := fights.begin(a, b)
	_check(fight != null and fight.cloud != null and fights.fighting(a) and fights.fighting(b), "two prisoners start a fight")
	_check(main.jobs.of_kind(&"break_up").size() == 1, "and a guard is sent to break it up")
	people._decide(a, true)
	_check(a.activity == "Fighting", "fighters stay put")
	var ended := []
	fights.ended.connect(func(_f: Fights.Fight) -> void: ended.append(true))
	for i in 10:
		clock.advance(1.0)
	_check(not ended.is_empty() and fights.fights.is_empty(), "it doesn't last long")
	_check(a.health < 100.0 and b.health < 100.0, "and both come off worse")
	# With a weapon it's quicker and nastier.
	var c: Person = prisoners[2]
	people.stop(c)
	c.level = a.level
	c.position = a.position + Vector3(0.0, 0.0, 0.6)
	people._buckets_fresh = false
	a.pocket.append((main.contraband as Contraband).item(&"mallet"))
	fight = fights.begin(a, c)
	_check(fight != null and fight.armed and fight.minutes_left <= Fights.ARMED_MINUTES, "a mallet makes it armed")
	fights.end(fight)
	_check(people.people.any(func(p: Person) -> bool: return p.moodlets.has(&"saw_a_nasty_fight")),
			"and those nearby saw a nasty fight")
	a.pocket.clear()
	# The fight rung picks someone close by.
	var d: Person = prisoners[3]
	people.stop(d)
	d.level = a.level
	d.position = a.position + Vector3(0.5, 0.0, 0.5)
	people._buckets_fresh = false
	misconduct.act(d, misconduct.rung(&"fight"))
	_check(fights.fighting(d) and String(d.record[-1][2]).begins_with("started a fight with"), "a fight goes on the record")
	for f in fights.fights.duplicate():
		fights.end(f)
	# The infirmary: two beds in the canteen.
	var map: BuildingMap = main.building.ground()
	var canteen: Room = null
	for room in map.rooms():
		if room.type == &"canteen":
			canteen = room
	var placed_beds := 0
	for cell in canteen.cells:
		if placed_beds < 2 and map.place_object(PrisonCatalogue.object(&"infirmary_bed"), Vector2(cell), 0) != 0:
			placed_beds += 1
	_check(placed_beds == 2, "infirmary beds go in")
	(main.shifts as Shifts).set_wanted(&"nurse", &"day", 1)
	var hurt: Person = prisoners[4]
	hurt.health = 50.0
	var out: Person = prisoners[5]
	out.health = 20.0
	people.stop(out)
	var lay := false
	var helped := []
	main.jobs.job_finished.connect(func(j: Job, w: Person) -> void:
		if j.kind == &"carry_patient" and (w.role == &"guard" or w.role == &"nurse"):
			helped.append(true))
	infirmary.tick(1.0)
	var stars := out.bubble == "Seeing stars"
	minutes = 0
	while not (hurt.lying and out.lying) and minutes < 240:
		clock.advance(1.0)
		minutes += 1
	_check(stars, "the knocked out see stars")
	_check(hurt.lying, "the hurt limp to an infirmary bed and lie down")
	_check(not helped.is_empty() and out.lying, "a guard carries the knocked out there")
	var before := out.health
	var treated := []
	main.jobs.job_finished.connect(func(j: Job, _w: Person) -> void:
		if j.kind == &"treat":
			treated.append(true))
	minutes = 0
	while treated.is_empty() and minutes < 300:
		clock.advance(1.0)
		minutes += 1
	_check(not treated.is_empty() and out.health > before, "a nurse patches them up")
	minutes = 0
	while hurt.lying and minutes < 600:
		clock.advance(1.0)
		minutes += 1
	_check(not hurt.lying and not infirmary.beds.has(hurt), "and they're back on their feet")
	main.queue_free()


func _test_consequences() -> void:
	var main: Node = load("res://games/prison/main.tscn").instantiate()
	main.sample = 10
	root.add_child(main)
	var people: People = main.people
	var consequences: Consequences = main.consequences
	var clock: GameClock = main.clock
	(main.misconduct as Misconduct).enabled = false
	(main.searching as Searching).random_per_day = 0
	var prisoners: Array = people.people.filter(func(p: Person) -> bool: return p.group == &"prisoner")
	var a: Person = prisoners[0]
	a.record.append([1, &"mischief", "skived off"])
	clock.advance(1.0)
	_check(a.points == 1.0 and a.bubble == "Warned" and a.restrictions.is_empty(), "a first minor offence is a warning")
	a.record.append([1, &"mischief", "skived off again"])
	clock.advance(1.0)
	_check(a.restrictions.has(&"yard"), "a second loses them the yard")
	people.set_block(a, people.activities[&"yard"])
	_check(a.block.id == &"lockup", "so yard time is lockup for them")
	var tv := BuildingMap.PlacedObject.new()
	tv.def = PrisonCatalogue.object(&"tv")
	a.restrictions[&"tv"] = 1.0
	_check(people.restricted_from(a, tv), "and a lost telly keeps them off the TV")
	consequences.new_day()
	_check(not a.restrictions.has(&"tv") and a.points == 1.0, "restrictions run out and points fade day by day")
	# A fight with no quiet room costs two privileges.
	var b: Person = prisoners[1]
	b.record.append([1, &"fight", "started a fight"])
	clock.advance(1.0)
	_check(b.restrictions.size() == 2 and b.quiet_room_hours == 0.0, "without a quiet room a fight costs two privileges")
	# Mark someone else's cell a quiet room.
	var map: BuildingMap = main.building.ground()
	var cell: Room = null
	for room in map.rooms():
		if room.type == &"cell":
			cell = room
	map.set_room_type(cell, &"quiet_room")
	var c: Person = prisoners[2]
	c.record.append([1, &"fight", "joined a fight"])
	var minutes := 0
	while not consequences.in_quiet_room(c) and minutes < 240:
		clock.advance(1.0)
		minutes += 1
	_check(consequences.in_quiet_room(c) and c.quiet_room_hours > 20.0, "a fighter is walked to the quiet room")
	# They may use the toilet or bed in there, but never leave.
	var stayed := true
	for i in 30:
		clock.advance(1.0)
		stayed = stayed and consequences.in_quiet_room(c)
	_check(stayed, "and stays there")
	_check(c.moodlets.has(&"in_the_quiet_room"), "which they don't enjoy")
	consequences.let_off(c)
	_check(c.quiet_room_hours == 0.0 and c.temper == 0.0, "letting them off lets them out")
	# Too many points by midnight moves them up a category.
	var d: Person = prisoners[3]
	d.category = &"medium"
	d.points = 9.0
	consequences.new_day()
	_check(d.category == &"high", "lots of trouble moves them up to high security")
	main.queue_free()


func _test_perimeter() -> void:
	var main: Node = load("res://games/prison/main.tscn").instantiate()
	main.sample = 9
	root.add_child(main)
	var secure: SecureArea = main.secure_area
	var map: BuildingMap = main.building.ground()
	_check(not secure.has_perimeter and secure.secure.is_empty(), "no perimeter, no secure ground")
	var land := map.land_bounds()
	var inner := land.grow(-3)
	var edges := BuildingMap.rect_perimeter(inner)
	map.build_walls(edges, &"perimeter_fence")
	_check(secure.has_perimeter and secure.is_secure(inner.get_center()) and not secure.is_secure(land.position),
			"a perimeter fence makes the ground inside secure")
	var gap: Vector3i = edges[edges.size() / 2]
	map.remove_walls([gap] as Array[Vector3i])
	_check(not secure.is_secure(inner.get_center()), "a gap lets the outside in")
	map.build_walls([gap] as Array[Vector3i], &"perimeter_fence")
	map.set_door(gap, true, &"people_gate")
	_check(secure.is_secure(inner.get_center()), "a gate in it counts as shut")
	var people: People = main.people
	_check(not people.access.door_kinds[&"vehicle_gate"].lets_through(&"prisoner"), "prisoners can't use the vehicle gate")
	main.queue_free()


func _test_escapes() -> void:
	var main: Node = load("res://games/prison/main.tscn").instantiate()
	main.sample = 10
	root.add_child(main)
	var people: People = main.people
	var escapes: Escapes = main.escapes
	var clock: GameClock = main.clock
	(main.misconduct as Misconduct).enabled = false
	(main.searching as Searching).random_per_day = 0
	var minutes := 0
	while not people.people.any(func(p: Person) -> bool: return p.role == &"guard") and minutes < 240:
		clock.advance(1.0)
		minutes += 1
	var prisoners: Array = people.people.filter(func(p: Person) -> bool: return p.group == &"prisoner")
	_check(escapes.possible() and escapes.exit_for(prisoners[0]) != Vector2.INF,
			"without a perimeter, anyone out of place could walk off")
	var map: BuildingMap = main.building.ground()
	var land := map.land_bounds()
	var fence := BuildingMap.rect_perimeter(land.grow(-6))
	map.build_walls(fence, &"perimeter_fence")
	_check(escapes.possible(), "with a perimeter, a gap would let them")
	# Outside the fence is out of bounds.
	var a: Person = prisoners[0]
	people.stop(a)
	a.level = 0
	a.position = Vector3(land.position.x + 2.5, a.position.y, land.get_center().y + 0.5)
	clock.advance(1.0)
	_check(a.out_of_place, "outside the perimeter is out of bounds")
	# Near the edge they get away.
	var fined := (main.ledger as Ledger).balance
	_check(escapes.run(a), "someone outside can make a run for it")
	minutes = 0
	while people.people.has(a) and minutes < 30:
		clock.advance(1.0)
		minutes += 1
	_check(not people.people.has(a) and escapes.at_large.size() == 1, "and gets away")
	_check((main.ledger as Ledger).balance < fined, "which costs a fine")
	# With a guard on their heels they're caught.
	var b: Person = prisoners[1]
	var guard: Person = people.people.filter(func(p: Person) -> bool: return p.role == &"guard")[0]
	people.stop(b)
	b.level = 0
	b.position = Vector3(land.position.x + 3.5, b.position.y, land.position.y + 3.5)
	people.stop(guard)
	guard.level = 0
	guard.position = b.position + Vector3(0.5, 0.0, 0.0)
	people._buckets_fresh = false
	var caught := []
	escapes.caught.connect(func(p: Person, _by: Person) -> void: caught.append(p))
	escapes.run(b)
	minutes = 0
	while caught.is_empty() and people.people.has(b) and minutes < 30:
		clock.advance(1.0)
		minutes += 1
	_check(caught.has(b) and b.record.any(func(e: Array) -> bool: return e[1] == &"escape"),
			"a guard close behind catches them, and it goes on their record")
	clock.advance(1.0)
	_check(b.quiet_room_hours > 0.0 or b.restrictions.size() >= 2, "with a consequence")
	main.queue_free()


func _test_security() -> void:
	# Coverage: a watcher sees their own room, not through walls.
	var building := Building.new(Rect2i(0, 0, 20, 20), PrisonCatalogue.FLOORS, PrisonCatalogue.WALLS)
	var map := building.ground()
	map.build_room(Rect2i(0, 0, 6, 6), &"wood", &"plaster")
	map.build_room(Rect2i(6, 0, 6, 6), &"wood", &"plaster")
	var coverage := Coverage.new()
	coverage.building = building
	coverage.update([[0, Vector2(3, 3), 5.0]])
	_check(coverage.seen_at(0, Vector2(1.5, 1.5)) == 1.0, "a watcher sees across their room")
	_check(coverage.seen_at(0, Vector2(7.5, 3.5)) == 0.0, "but not through the wall")
	coverage.update([], 15.0)
	_check(is_equal_approx(coverage.seen_at(0, Vector2(1.5, 1.5)), 0.5), "what was seen fades")
	coverage.update([], 15.0)
	_check(coverage.seen_at(0, Vector2(1.5, 1.5)) == 0.0, "and is gone after half an hour")
	# A camera sees a cone in front of it.
	coverage.update([[0, Vector2(0.5, 0.5), 8.0, Vector2(1, 1).normalized(), PI * 0.5]])
	_check(coverage.seen_at(0, Vector2(4.5, 4.5)) > 0.0, "a camera sees ahead")
	coverage.seen.clear()
	coverage.update([[0, Vector2(5.5, 5.5), 8.0, Vector2(1, 1).normalized(), PI * 0.5]])
	_check(coverage.seen_at(0, Vector2(1.5, 1.5)) == 0.0, "but not behind")
	# Safety stars from incidents per ten prisoners.
	_check(Security.safety_stars({}, 20) == 5, "no incidents, five stars")
	_check(Security.safety_stars({&"fight": 1}, 20) == 4, "one fight among twenty, four stars")
	_check(Security.safety_stars({&"escape": 1}, 20) == 1, "an escape, one star")
	# In a prison: the camera is watched from the guard post, and incidents count.
	var main: Node = load("res://games/prison/main.tscn").instantiate()
	main.sample = 10
	root.add_child(main)
	var people: People = main.people
	var security: Security = main.security
	var clock: GameClock = main.clock
	(main.misconduct as Misconduct).enabled = false
	(main.searching as Searching).random_per_day = 0
	var minutes := 0
	while not security.cameras_live() and minutes < 600:
		clock.advance(1.0)
		minutes += 1
	_check(security.cameras_live(), "a guard at the post watches the canteen camera")
	clock.advance(1.0)
	var camera: BuildingMap.PlacedObject = main.building.object_at(main.building.objects_tagged(Array([&"camera"], TYPE_STRING_NAME, &"", null))[0])
	var ahead := camera.centre + Security.facing(camera) * 3.0
	_check(security.watched(0, ahead), "so the canteen in front of it counts as watched")
	var prisoner: Person = people.people.filter(func(p: Person) -> bool: return p.group == &"prisoner")[0]
	people.stop(prisoner)
	prisoner.level = 0
	prisoner.position = Vector3(ahead.x, prisoner.position.y, ahead.y)
	_check((main.misconduct as Misconduct).watched(prisoner), "and nobody acts up there")
	var fights := (main.fights as Fights)
	fights.knocked_out.emit(prisoner)
	_check(security.today.get(&"knocked_out", 0) == 1 and not security.alerts.is_empty(), "a knock-out is an incident and an alert")
	var standing: Standing = main.standing
	standing.grade_day()
	_check(standing.measures["Safety"] < 5 and security.today.is_empty() and security.yesterday.get(&"knocked_out", 0) == 1,
			"which costs Safety at midnight")
	(main.security_window as SecurityWindow).toggle()
	_check(Array((main.security_window as SecurityWindow).status_lines())[0].contains("watched from the monitor"),
			"the Security window says the cameras are watched")
	main.queue_free()


func _test_sit_ins() -> void:
	var main: Node = load("res://games/prison/main.tscn").instantiate()
	main.sample = 10
	root.add_child(main)
	var people: People = main.people
	var sit_ins: SitIns = main.sit_ins
	var clock: GameClock = main.clock
	(main.misconduct as Misconduct).enabled = false
	(main.searching as Searching).random_per_day = 0
	sit_ins.enabled = false
	var minutes := 0
	while not people.people.any(func(p: Person) -> bool: return p.role == &"guard") and minutes < 240:
		clock.advance(1.0)
		minutes += 1
	var map: BuildingMap = main.building.ground()
	var canteen: Room = map.rooms().filter(func(r: Room) -> bool: return r.type == &"canteen")[0]
	var prisoners: Array = people.people.filter(func(p: Person) -> bool: return p.group == &"prisoner")
	_check(prisoners.size() >= 6, "enough prisoners for a sit-in")
	var crowd: Array = prisoners.slice(0, 6)
	var put_in_canteen := func() -> void:
		for i in crowd.size():
			var person: Person = crowd[i]
			people.stop(person)
			person.traits.clear()
			person.level = 0
			var cell: Vector2i = canteen.cells[(i * 3 + 7) % canteen.cells.size()]
			person.position = Vector3(cell.x + 0.5, map.floor_height(cell), cell.y + 0.5)
			person.moodlets[&"missed_meal"] = 6.0
			person.mood = 10.0
			person.mood_parts = [["Missed a meal", -8.0]]
	put_in_canteen.call()
	_check(sit_ins.try_start(0, canteen, crowd.slice(0, 5)) == null, "five is too few for a sit-in")
	var sit_in := sit_ins.try_start(0, canteen, crowd)
	_check(sit_in != null and sit_in.members.size() == 6 and sit_in.demand == "Proper dinners!",
			"six unhappy about missing meals sit in for proper dinners")
	_check(crowd.all(func(p: Person) -> bool: return p.sitting), "and sit down")
	var spot: Vector3 = (crowd[0] as Person).position
	clock.advance(5.0)
	_check((crowd[0] as Person).position.distance_to(spot) < 0.1 and (crowd[0] as Person).bubble == "Proper dinners!",
			"they stay put with a placard")
	# Talked round by a guard.
	var how := []
	sit_ins.ended.connect(func(_s: SitIns.SitIn, h: String) -> void: how.append(h))
	sit_ins.negotiate(sit_in)
	minutes = 0
	while how.is_empty() and minutes < 120:
		for person: Person in crowd:
			person.mood_parts = [["Missed a meal", -8.0]]
		clock.advance(1.0)
		minutes += 1
	_check(how == ["talked"], "a guard talks them round")
	_check(crowd.all(func(p: Person) -> bool: return not p.sitting and p.moodlets.has(&"listened_to")),
			"and they stand up feeling listened to")
	_check((crowd[0] as Person).record.any(func(e: Array) -> bool: return e[1] == &"sit_in"), "it goes on their record")
	# Fixed: the complaint goes away.
	put_in_canteen.call()
	sit_in = sit_ins.try_start(0, canteen, crowd)
	how.clear()
	minutes = 0
	while how.is_empty() and minutes < 30:
		for person: Person in crowd:
			person.moodlets.erase(&"missed_meal")
			person.mood_parts = [["Bored", -2.0]]
		clock.advance(1.0)
		minutes += 1
	_check(how == ["fixed"], "fixing what upset them stands them up")
	# Left too long, it ends in a scrap.
	put_in_canteen.call()
	sit_in = sit_ins.try_start(0, canteen, crowd)
	sit_in.minutes = SitIns.BOIL_MINUTES
	how.clear()
	sit_ins.tick()
	_check(how == ["boiled"] and (main.fights as Fights).fights.size() == 1, "left for hours it boils over into a fight")
	main.queue_free()


func _test_category_timetables() -> void:
	var main: Node = load("res://games/prison/main.tscn").instantiate()
	main.sample = 10
	root.add_child(main)
	var people: People = main.people
	var runner: ScheduleRunner = main.runner
	var clock: GameClock = main.clock
	var prisoners: Array = people.people.filter(func(p: Person) -> bool: return p.group == &"prisoner")
	var high: Person = prisoners[0]
	var other: Person = prisoners[1]
	high.category = &"high"
	other.category = &"medium"
	_check(runner.key_for(high) == &"prisoner", "without its own timetable a category follows everyone's")
	var split := runner.split(&"prisoner", &"high")
	_check(runner.key_for(high) == &"prisoner/high" and runner.key_for(other) == &"prisoner",
			"a split timetable is followed by that category only")
	var lockup: ActivityDef = PrisonCatalogue.ACTIVITIES.filter(func(d: ActivityDef) -> bool: return d.id == &"lockup")[0]
	var hour := clock.hour()
	var was := runner.current(&"prisoner")
	split.set_hour(hour, lockup if was != lockup else PrisonCatalogue.ACTIVITIES[0])
	_check(runner.current_for(high) != runner.current_for(other) and runner.current_for(other) == was,
			"painting it changes only their block")
	_check((main.schedule as Schedule).at(hour) == was, "and leaves everyone's timetable alone")
	high.category = &"medium"
	clock.advance(1.0)
	_check(runner.key_for(high) == &"prisoner", "moving category moves timetable")
	high.category = &"high"
	clock.advance(1.0)
	var window: TimetableWindow = main.timetable
	window.toggle()
	window.show_timetable(&"prisoner/high")
	_check(window.schedule == split and window.timetable_name(&"prisoner/high") == "High security",
			"the timetable window can paint the high security timetable")
	window.every_day = false
	window.show_day(2)
	var before: ActivityDef = split.at_slot(20)
	window.paint_slot(20)
	_check(split.at_slot(2 * Schedule.SLOTS_PER_DAY + 20).id == &"sleep" and split.at_slot(20) == before and before.id != &"sleep"
			and not split.same_every_day(), "painting one day leaves the others alone")
	window.every_day = true
	var data := PrisonSave.capture(main)
	runner.merge(&"prisoner/high")
	_check(not runner.schedules.has(&"prisoner/high") and runner.current_for(high) == was, "merging puts them back")
	_check(data["category_timetables"].has(&"prisoner/high"), "category timetables are saved")
	main.queue_free()


func _test_category_zones() -> void:
	var main: Node = load("res://games/prison/main.tscn").instantiate()
	main.sample = 10
	root.add_child(main)
	var people: People = main.people
	var map: BuildingMap = main.building.ground()
	var cells: Array = map.rooms().filter(func(r: Room) -> bool: return r.type == &"cell")
	var wing: Room = cells[0]
	map.set_room_zone(wing, &"high_security")
	wing = map.room_at(wing.cells[0])
	var prisoners: Array = people.people.filter(func(p: Person) -> bool: return p.group == &"prisoner")
	var high: Person = prisoners[0]
	high.category = &"high"
	for i in range(1, prisoners.size()):
		(prisoners[i] as Person).category = &"medium"
	var staff: Person = people.people.filter(func(p: Person) -> bool: return p.group == &"staff")[0]
	_check(people.may_enter(high, wing) and not people.may_enter(prisoners[1], wing) and people.may_enter(staff, wing),
			"a high security wing lets in high security prisoners and staff only")
	people.beds_changed()
	people.assign_beds()
	var in_wing := func(p: Person) -> bool:
		var home := people.home_room(p)
		return not home.is_empty() and home[1].cells.has(wing.cells[0])
	_check(in_wing.call(high), "high security prisoners get their beds in it")
	_check(not prisoners.slice(1).any(in_wing), "and nobody else does")
	main.queue_free()


func _test_trading_and_tools() -> void:
	var main: Node = load("res://games/prison/main.tscn").instantiate()
	main.sample = 10
	root.add_child(main)
	var people: People = main.people
	var contraband: Contraband = main.contraband
	var security: Security = main.security
	var clock: GameClock = main.clock
	(main.misconduct as Misconduct).enabled = false
	(main.searching as Searching).random_per_day = 0
	var map: BuildingMap = main.building.ground()
	var prisoners: Array = people.people.filter(func(p: Person) -> bool: return p.group == &"prisoner")
	# A rolling pin taken from the kitchen is missed at the shift change.
	var cooker: BuildingMap.PlacedObject = main.building.object_at(main.building.objects_tagged(
			Array([&"cooker"], TYPE_STRING_NAME, &"", null))[0])
	var a: Person = prisoners[0]
	a.pocket.clear()
	var pin := contraband.pocket_from(a, cooker)
	_check(pin != null and contraband.missing.size() == 1, "a tool taken from the kitchen goes missing")
	var missed := []
	contraband.tool_missing.connect(func(_l: int, _r: Room, def: ItemDef) -> void: missed.append(def))
	contraband.count_tools()
	_check(missed == [pin] and security.alerts[0][2].contains("missing from the kitchen"),
			"and the shift change count raises an alert")
	# Biscuits buy a weapon.
	var buyer: Person = prisoners[1]
	var seller: Person = prisoners[2]
	for p: Person in [buyer, seller]:
		people.stop(p)
		p.pocket.clear()
		p.traits.clear()
	seller.pocket.append(contraband.item(&"rolling_pin"))
	for i in 6:
		buyer.pocket.append(contraband.item(&"biscuit"))
	buyer.temper = 80.0
	var bought := contraband.try_trade(buyer, seller)
	_check(bought != null and bought.id == &"rolling_pin" and buyer.pocket.has(bought), "a fuming prisoner buys a rolling pin")
	_check(not buyer.pocket.any(func(d: ItemDef) -> bool: return d.id == &"biscuit")
			and seller.pocket.size() == 6, "for six biscuits")
	_check(contraband.try_trade(buyer, seller) == null, "and can't buy without biscuits")
	# A metal detector beeps at a spoon.
	var edge := Vector3i.ZERO
	for room in map.rooms():
		if room.type == &"canteen":
			edge = ScheduleRunner.room_doors(map, room)[0]
	map.set_door(edge, true, &"metal_detector")
	var c: Person = prisoners[3]
	people.stop(c)
	c.pocket = [contraband.item(&"spoon")]
	var cells := BuildingMap.edge_cells(edge)
	var middle := (Vector2(cells[0]) + Vector2(cells[1])) * 0.5 + Vector2(0.5, 0.5)
	c.level = 0
	c.position = Vector3(middle.x, c.position.y, middle.y)
	var beeped := []
	contraband.detected.connect(func(p: Person, _d: ItemDef) -> void: beeped.append(p))
	contraband.check_detectors()
	_check(beeped == [c], "a metal detector beeps at someone with a spoon")
	_check((main.jobs as JobBoard).of_kind(&"search").any(func(j: Job) -> bool:
			return j.has_meta(&"prisoner") and j.get_meta(&"prisoner") == c), "and a guard is sent to search them")
	contraband.check_detectors()
	_check(beeped.size() == 1, "once, not every minute")
	main.queue_free()


func _test_shakedown_and_deaths() -> void:
	var main: Node = load("res://games/prison/main.tscn").instantiate()
	main.sample = 10
	root.add_child(main)
	var people: People = main.people
	var searching: Searching = main.searching
	var infirmary: Infirmary = main.infirmary
	(main.misconduct as Misconduct).enabled = false
	searching.random_per_day = 0
	var prisoners: Array = people.people.filter(func(p: Person) -> bool: return p.group == &"prisoner")
	var cells := {}
	for p: Person in prisoners:
		var home := people.home_room(p)
		if not home.is_empty():
			cells[home[1]] = true
	var a: Person = prisoners[0]
	a.temper = 0.0
	searching.shakedown_tonight = true
	var lockup: ActivityDef = people.activities[&"lockup"]
	for p: Person in prisoners:
		p.block = lockup
	searching._tick()
	_check(not searching.shakedown_tonight and (main.jobs as JobBoard).of_kind(&"search").size() == cells.size(),
			"a shakedown at lockup searches every cell")
	_check(a.temper >= Searching.SHAKEDOWN_TEMPER, "and puts everyone in a temper")
	# Deaths: off, the knocked out never drop below the floor.
	var b: Person = prisoners[1]
	b.health = 1.0
	infirmary.tick(600.0)
	_check(people.people.has(b) and b.health > 0.0, "with deaths off nobody dies")
	infirmary.deaths = true
	var c: Person = prisoners[2]
	c.health = 0.0
	var died := []
	infirmary.died.connect(func(p: Person, _l: int, _pt: Vector2) -> void: died.append(p))
	infirmary.tick(1.0)
	_check(died == [c] and not people.people.has(c), "with deaths on, someone beaten to nothing dies")
	_check((main.security as Security).today.get(&"death", 0) == 1, "which counts heavily against Safety")
	main.queue_free()


## The shared progress engine: source caps, the day's cap, milestones,
## losses and clamping.
func _test_progress() -> void:
	var def := ProgressDef.new()
	def.id = &"reform"
	def.start = 20.0
	def.daily_cap = 8.0
	var make := func(id: StringName, text: String, amount: float, cap: float, milestone := false) -> ProgressSourceDef:
		var source := ProgressSourceDef.new()
		source.id = id
		source.text = text
		source.amount = amount
		source.per_day_cap = cap
		source.milestone = milestone
		return source
	var progress := Progress.new(def, [make.call(&"good", "Good day", 2.0, 2.0), make.call(&"work", "Work", 3.0, 0.0),
			make.call(&"bad", "Bad day", -3.0, 0.0), make.call(&"pass", "Passed", 15.0, 0.0, true)])
	var person := Person.new()
	_check(progress.value(person) == 20.0, "progress starts at the def's start")
	progress.add(person, &"good")
	progress.add(person, &"good")
	_check(progress.value(person) == 22.0, "a source gives no more than its cap a day")
	progress.add(person, &"work", 3.0)
	_check(progress.value(person) == 28.0, "all gains together stop at the day's cap")
	progress.add(person, &"pass")
	_check(progress.value(person) == 43.0, "a milestone isn't held back by the day's cap")
	progress.add(person, &"bad")
	_check(progress.value(person) == 40.0, "losses always count")
	_check(progress.today_text(person) == "+20 today: Good day +2, Work +6, Passed +15, Bad day -3",
			"today's parts explain the change (%s)" % progress.today_text(person))
	progress.new_day([person] as Array[Person])
	progress.add(person, &"good")
	_check(progress.value(person) == 42.0 and progress.today_text(person) == "+2 today: Good day +2",
			"a new day resets the caps")
	progress.set_value(person, 99.0)
	progress.add(person, &"pass")
	_check(progress.value(person) == 100.0, "progress tops out at 100")


## Sentences roll on arrival and count down at midnight; reform moves with
## good and bad days.
func _test_sentences_and_reform() -> void:
	var main: Node = load("res://games/prison/main.tscn").instantiate()
	main.sample = 8
	root.add_child(main)
	var people: People = main.people
	var sentences: Sentences = main.sentences
	var reform: Reform = main.reform
	var clock: GameClock = main.clock
	(main.misconduct as Misconduct).enabled = false
	var prisoners: Array = people.people.filter(func(p: Person) -> bool: return p.group == &"prisoner")
	_check(not prisoners.is_empty() and prisoners.all(func(p: Person) -> bool:
			var file := PrisonerFile.of(p)
			return file.has_sentence() and file.served_days < file.sentence_days and file.release_day > clock.day()),
			"everyone already here has a sentence part-served")
	var low: Person = prisoners[0]
	low.category = &"low"
	low.profile.clear()
	sentences.open_file(low)
	var file := PrisonerFile.of(low)
	_check(file.sentence_days >= 2 and file.sentence_days <= 6 and file.served_days == 0
			and file.release_day == clock.day() + file.sentence_days, "a low-security sentence is 2 to 6 days")
	_check(file.parole_from_day == clock.day() + ceili(file.sentence_days * 0.5), "parole comes halfway through")
	_check(reform.value(low) == Sentences.STARTING_REFORM, "and reform starts at 20")
	file.release_day = clock.day() + 1
	var happy: Person = prisoners[1]
	var cross: Person = prisoners[2]
	var happy_before := reform.value(happy)
	var cross_before := reform.value(cross)
	# Hold moods steady through to midnight.
	var hold := func(_minute: int) -> void:
		happy.mood = 80.0
		cross.mood = 20.0
	clock.minute_passed.connect(hold)
	var served := PrisonerFile.of(happy).served_days
	while clock.day() == 1:
		clock.advance(30.0)
	clock.minute_passed.disconnect(hold)
	_check(PrisonerFile.of(happy).served_days == served + 1, "a day is served each midnight")
	_check(file.due_out, "someone whose time is up is due out")
	_check(reform.value(happy) >= happy_before + 2.0, "a good day lifts reform")
	_check(is_equal_approx(reform.value(cross), cross_before - 3.0), "a bad day takes it down")
	_check(sentences.summary(happy).begins_with("Day ") and reform.summary(happy).begins_with("Reform "),
			"the inspector shows the sentence and reform")
	main.free()


## Classes: places fill lowest reform first, a teacher teaches in the
## Learn block, students sit at desks, sessions count, and the exam passes
## or sends them back.
func _test_courses() -> void:
	var main: Node = load("res://games/prison/main.tscn").instantiate()
	main.sample = 12
	root.add_child(main)
	var people: People = main.people
	var courses: Courses = main.courses
	var reform: Reform = main.reform
	var clock: GameClock = main.clock
	var building: Building = main.building
	(main.misconduct as Misconduct).enabled = false
	_check(building.objects_tagged([&"whiteboard"]).size() == 1 and building.objects_tagged([&"class_desk"]).size() == 6
			and building.objects_tagged([&"armchair"]).size() == 2, "the reforming prison has a classroom and a counselling room")
	var prisoners: Array = people.people.filter(func(p: Person) -> bool: return p.group == &"prisoner")
	courses.set_places(&"calm_minds", 0)
	var lowest: Person = prisoners[0]
	for p: Person in prisoners:
		reform.progress.set_value(p, 50.0)
	reform.progress.set_value(lowest, 5.0)
	courses.set_places(&"reading", 0)
	courses.set_places(&"reading", 1)
	_check(courses.enrolled(&"reading").size() == 1 and courses.enrolled(&"reading")[0] == lowest, "the least reformed get the first place")
	courses.set_places(&"reading", 4)
	_check(courses.enrolled(&"reading").size() == 4 and courses.problem(courses.def(&"reading")).is_empty(),
			"places fill and the course can run")
	var student: Person = courses.enrolled(&"reading")[0]
	var before := courses.attended(student)
	clock.jump_to_hour(15)
	var sat := false
	var taught := false
	while clock.hour() < 17:
		clock.advance(1.0)
		sat = sat or (student.job != null and student.job.kind == &"attend" and student.seat != Person.NO_OBJECT)
		taught = taught or people.people.any(func(p: Person) -> bool:
				return p.role == &"teacher" and p.job != null and p.job.kind == &"teach" and p.state == Person.State.USING)
	_check(taught, "the teacher teaches at the whiteboard in the Learn block")
	_check(sat, "students sit at a desk")
	_check(courses.attended(student) == before + 1, "a session sat through counts (%d)" % courses.attended(student))
	var course := courses.def(&"reading")
	student.profile["course_attended"] = course.sessions - 1
	var passing := reform.value(student)
	_check(not courses.exam(student, course, 0.99) and courses.attended(student) == course.sessions - Courses.RESIT_BACK,
			"a failed exam goes back two sessions")
	_check(courses.exam(student, course, 0.0) and PrisonerFile.of(student).passed.has(&"reading")
			and PrisonerFile.of(student).skill(&"reading") >= 30 and reform.value(student) >= passing + 15.0
			and courses.course_of(student) == null, "a pass lifts reform and the skill and frees the place")
	_check(not courses.waiting(&"reading").has(student), "nobody takes a course they've passed")
	var calm := courses.def(&"calm_minds")
	courses.enrol(student, &"calm_minds")
	courses.exam(student, calm, 0.0)
	_check(courses.calm_scale(student) < 1.0, "Calm Minds cools tempers after a pass")
	main.free()


## Parole: who's eligible, the chance, the warden hearing cases at the
## desk, and what granted and refused mean.
func _test_parole() -> void:
	var main: Node = load("res://games/prison/main.tscn").instantiate()
	main.sample = 12
	root.add_child(main)
	var people: People = main.people
	var parole: Parole = main.parole
	var reform: Reform = main.reform
	var clock: GameClock = main.clock
	(main.misconduct as Misconduct).enabled = false
	var prisoners: Array = people.people.filter(func(p: Person) -> bool: return p.group == &"prisoner")
	var good: Person = prisoners[0]
	var file := PrisonerFile.of(good)
	file.sentence_days = 10
	file.release_day = clock.day() + 6
	file.parole_from_day = clock.day() + 1
	_check(not parole.eligible(good) and parole.why_not(good).begins_with("Not until"), "no hearing before parole day")
	file.parole_from_day = clock.day()
	_check(parole.eligible(good), "eligible from parole day")
	reform.progress.set_value(good, 30.0)
	_check(is_equal_approx(parole.chance(good)[0], 0.26), "reform 30 alone gives a 26% chance")
	reform.progress.set_value(good, 60.0)
	file.passed.append(&"reading")
	file.raise_skill(&"reading", 60)
	_check(is_equal_approx(parole.chance(good)[0], 0.6), "reform 60, a course and a skill give 60%")
	good.record.append([clock.day(), &"grumble", "grumbled"])
	_check(not parole.eligible(good), "trouble in the last few days rules them out")
	good.record.clear()
	good.profile["parole_held_back"] = true
	_check(not parole.eligible(good), "held back, they aren't put forward")
	good.profile.erase("parole_held_back")
	for p: Person in prisoners:
		if p != good:
			PrisonerFile.of(p).parole_from_day = clock.day() + 50
	clock.jump_to_hour(13)
	_check(parole.queue.size() == 1 and parole.queue[0] == good, "13:00 draws up the list")
	var granted := false
	while clock.hour() < 17 and parole.today.is_empty():
		clock.advance(1.0)
	_check(parole.today.size() == 1, "the warden hears the case at the desk")
	granted = parole.today[0][1]
	if granted:
		_check(file.release_day == clock.day() + 1 and good.moodlets.has(Parole.GRANTED), "granted, they go home tomorrow")
	else:
		_check(good.profile.get("parole_next", 0) == clock.day() + Parole.RETRY_DAYS, "refused, they wait to try again")
	var other: Person = prisoners[1]
	var other_file := PrisonerFile.of(other)
	other_file.parole_from_day = clock.day()
	other_file.release_day = clock.day() + 6
	_check(not parole.hear(other, 0.99) and not parole.eligible(other)
			and other.moodlets.has(Parole.REFUSED), "a refusal waits a few days")
	_check(parole.hear(good, 0.0) and file.release_day == clock.day() + 1, "a grant brings release to tomorrow")
	main.free()


func _test_release() -> void:
	var main: Node = load("res://games/prison/main.tscn").instantiate()
	main.sample = 12
	root.add_child(main)
	var people: People = main.people
	var release: Release = main.release
	var reform: Reform = main.reform
	var ledger: Ledger = main.ledger
	var clock: GameClock = main.clock
	(main.misconduct as Misconduct).enabled = false
	(main.intake as Intake).limit = 0
	(main.intake as Intake).accepted.clear()
	var prisoners: Array = people.people.filter(func(p: Person) -> bool: return p.group == &"prisoner")
	for p: Person in prisoners:
		PrisonerFile.of(p).release_day = clock.day() + 50
		PrisonerFile.of(p).parole_from_day = clock.day() + 50
	var good: Person = prisoners[0]
	var bad: Person = prisoners[1]
	reform.progress.set_value(good, 70.0)
	PrisonerFile.of(good).passed.append(&"cooking")
	PrisonerFile.of(good).raise_skill(&"cooking", 50)
	reform.progress.set_value(bad, 20.0)
	_check(is_equal_approx(release.return_chance(good), 0.08), "reform 70 and a course: 8% come back")
	_check(is_equal_approx(release.return_chance(bad), 0.43), "reform 20: 43% come back")
	var good_name := good.name
	var bad_name := bad.name
	var bad_look := bad.id
	var bad_traits: Array = bad.traits.map(func(t: TraitDef) -> StringName: return t.id)
	clock.jump_to_hour(7)
	for p: Person in [good, bad]:
		PrisonerFile.of(p).release_day = clock.day()
		PrisonerFile.of(p).due_out = true
	var before := prisoners.size()
	var bonus_before: int = ledger.today.get("Reform bonus", 0)
	var signed := false
	while clock.hour() < 14 and (people.people.has(good) or people.people.has(bad)):
		clock.advance(1.0)
		if people.people.has(good) and release.is_leaving(good) and good.activity.begins_with("Signing out"):
			signed = true
	_check(signed, "leavers sign out at reception")
	while (main.intake as Intake).bus_here() and clock.hour() < 14:
		clock.advance(1.0)
	_check(not people.people.has(good) and not people.people.has(bad), "both have gone by the afternoon")
	_check(people.people.filter(func(p: Person) -> bool: return p.group == &"prisoner").size() == before - 2,
			"two fewer prisoners")
	_check(ledger.today.get("Reform bonus", 0) - bonus_before == Release.REFORM_BONUS, "the reformed one brings a bonus")
	_check(release.alumni.size() == 2 and release.alumni.any(func(e: Dictionary) -> bool: return e.name == good_name),
			"both are remembered")
	var good_entry: Dictionary = release.alumni.filter(func(e: Dictionary) -> bool: return e.name == good_name)[0]
	var bad_entry: Dictionary = release.alumni.filter(func(e: Dictionary) -> bool: return e.name == bad_name)[0]
	_check(good_entry.best_skill == &"cooking" and not good_entry.plan.is_empty(), "the record has what they'll do")
	_check(release.today_lines.any(func(line: String) -> bool: return line.begins_with(good_name)),
			"a line for the report")
	good_entry.postcard_day = clock.day() + 1
	good_entry.will_return_day = -1
	bad_entry.will_return_day = clock.day() + 1
	clock.jump_to_hour(0)
	_check(release.postcards.size() == 1 and release.postcards[0].from == good_name
			and (release.postcards[0].text as String).ends_with(good_name.get_slice(" ", 0)), "a postcard comes")
	_check(release.report_lines().any(func(line: String) -> bool: return line.contains("postcard from " + good_name)),
			"the postcard is in the report")
	_check(release.returning_today().size() == 1, "one is due back")
	clock.jump_to_hour(Intake.BUS_HOUR)
	var back: Array = []
	while clock.hour() < 13 and back.is_empty():
		clock.advance(1.0)
		back = people.people.filter(func(p: Person) -> bool: return p.name == bad_name)
	_check(back.size() == 1, "the reoffender comes back on the bus")
	if back.size() == 1:
		var again: Person = back[0]
		_check(again.look_seed == bad_look and again.traits.map(func(t: TraitDef) -> StringName: return t.id) == bad_traits,
				"looking the same, with the same traits")
		_check(PrisonerFile.of(again).came_back == 1 and is_equal_approx(reform.value(again), Sentences.REOFFENDER_REFORM),
				"marked as back, starting low")
		_check(release.week().back == 1, "counted as came back")
	main.free()


func _test_balanced_grade() -> void:
	var safety: MeasureDef = load("res://games/prison/catalogue/measure_safety.tres")
	_check(safety.stars(0.0) == 5 and safety.stars(3.0) == 1, "fewer incidents, more stars")
	var main: Node = load("res://games/prison/main.tscn").instantiate()
	main.sample = 12
	root.add_child(main)
	var standing: Standing = main.standing
	var release: Release = main.release
	var reform: Reform = main.reform
	standing.measure_value["Safety"] = func() -> Array: return [0.0, "calm"]
	standing.measure_value["Wellbeing"] = func() -> Array: return [90.0, "happy"]
	standing.measure_value["Money"] = func() -> Array: return [5000.0, "rich"]
	var weak := func() -> Array: return [0.0, "nobody reformed"]
	standing.measure_value["Reform"] = weak
	standing.grade_day()
	_check(standing.measures["Reform"] == 1 and standing.grade == 3 and standing.held_by == "Reform",
			"5, 5, 5 and 1 star grade 3, held by Reform")
	_check(standing.write_report().contains("Held to 3★ by Reform"), "the report says what held it")
	standing.measure_value["Reform"] = func() -> Array: return [0.5, "fine"]
	standing.grade_day()
	_check(standing.measures["Reform"] == 3 and standing.grade == 4 and standing.held_by.is_empty()
			and standing.history.size() == 2, "Reform averages 1 and 4 over two nights, and nothing holds it back")
	standing.measure_value["Reform"] = weak
	standing.grade_day()
	_check(standing.measures["Reform"] == 2 and standing.grade == 4, "one bad night dents the grade rather than sinking it")
	var ledger: Ledger = main.ledger
	ledger.balance = 7000
	ledger.spent.assign([1000, 1000, 1000])
	_check(is_equal_approx(standing._money()[0], 7.0), "money counts days of costs in the bank")
	ledger.balance = 7000
	# The real Reform measure: half average reform, half this week's leavers.
	standing.measure_value.erase("Reform")
	standing.start()
	for p: Person in main.people.people:
		if p.group == &"prisoner":
			reform.progress.set_value(p, 40.0)
	var got: Array = standing.measure_value["Reform"].call()
	_check(is_equal_approx(got[0], 0.4), "with nobody gone home, reform is the average")
	release.alumni.append({"left_day": main.clock.day(), "reform": 70.0, "will_return_day": -1})
	release.alumni.append({"left_day": main.clock.day(), "reform": 20.0, "will_return_day": main.clock.day(), "returned": true})
	got = standing.measure_value["Reform"].call()
	_check(is_equal_approx(got[0], 0.2 + 0.5 / 3.0), "a comeback counts twice against the leavers' share")
	main.free()


func _test_goals_and_difficulty() -> void:
	var main: Node = load("res://games/prison/main.tscn").instantiate()
	main.sample = 12
	root.add_child(main)
	var standing: Standing = main.standing
	var ledger: Ledger = main.ledger
	var clock: GameClock = main.clock
	_check(standing.goals.size() == 12, "a dozen sandbox goals")
	for goal in standing.goals.slice(0, 4):
		standing.goals_done[goal.id] = true
	var current := standing.current_goals()
	_check(current[0].id == &"pass_3_courses" and standing.goal_progress(current[0]) == "0 of 3",
			"counted goals count from when they come up")
	standing.count(&"courses_passed", 3)
	var finished := standing.check_goals()
	_check(finished.any(func(g: GoalDef) -> bool: return g.id == &"pass_3_courses"), "three passes win the grant")
	for goal in standing.goals:
		if goal.id != &"five_nights_4":
			standing.goals_done[goal.id] = true
	for measure: String in Standing.MEASURES:
		standing.measure_value[measure] = func() -> Array: return [0.0 if measure == "Safety" else 1e6, ""]
	for night in 4:
		standing.grade_day()
	_check(not standing.goals_done.has(&"five_nights_4") and standing.goal_progress(standing.goals[-1]) == "4 of 5 nights",
			"held goals count nights in a row")
	standing.grade_day()
	_check(standing.goals_done.has(&"five_nights_4"), "and pay on the fifth")
	# Difficulty.
	var tough: DifficultyDef = Standing.DIFFICULTIES[3]
	standing.set_difficulty(tough)
	_check(is_equal_approx(main.finances.wage_scale, 1.15) and is_equal_approx(main.release.return_scale, 1.5)
			and is_equal_approx(main.finances.grant_scale, (0.8 + 0.1 * (standing.grade - 1)) * 0.85),
			"Tough scales wages, comebacks and grants")
	var lost: Array = []
	standing.failed.connect(func(rule: FailRule) -> void: lost.append(rule))
	ledger.balance = -6000
	standing.grade_day()
	_check(standing.warnings.any(func(line: String) -> bool: return line.contains("2 nights")),
			"deep in debt, the Ministry warns")
	standing.grade_day()
	_check(lost.is_empty(), "not lost yet")
	standing.grade_day()
	_check(lost.size() == 1 and lost[0].kind == &"debt" and clock.paused() and (main.fail_card as FailCard).visible,
			"three nights in deep debt loses the prison")
	(main.fail_card as FailCard).keep_playing.call()
	_check(standing.difficulty.id == &"sandbox" and not clock.paused() and not standing.lost, "keep playing as Sandbox")
	standing.set_difficulty(Standing.DIFFICULTIES[2])
	standing.grade_day()
	standing.grade_day()
	standing.grade_day()
	_check(lost.size() == 1 and standing.warnings.size() == 1 and not standing.warnings[0].contains("nights"),
			"Standard only warns")
	_check(PrisonSave.capture(main)["standing"]["difficulty"] == &"standard", "the difficulty saves")
	main.free()


func _test_escape_plans() -> void:
	var main: Node = load("res://games/prison/main.tscn").instantiate()
	main.sample = 10
	root.add_child(main)
	var people: People = main.people
	var plans: EscapePlans = main.escape_plans
	var escapes: Escapes = main.escapes
	var clock: GameClock = main.clock
	escapes.enabled = true
	(main.misconduct as Misconduct).enabled = false
	(main.searching as Searching).random_per_day = 0
	people.assign_beds()
	var map: BuildingMap = main.building.ground()
	var land := map.land_bounds()
	map.build_walls(BuildingMap.rect_perimeter(land.grow(-6)), &"perimeter_fence")
	_check((main.secure_area as SecureArea).has_perimeter, "a perimeter to get past")
	var digger: Person = null
	for p: Person in people.people:
		if p.group == &"prisoner" and p.has_bed() and p.bed.x == 0:
			digger = p
			break
	var spoon := PrisonCatalogue.item(&"spoon")
	var screwdriver := PrisonCatalogue.item(&"screwdriver")
	digger.pocket.append(spoon)
	PrisonerFile.of(digger).release_day = clock.day() + 30
	_check(not plans.should_plot(digger), "a content prisoner doesn't plot")
	digger.profile["low_nights"] = EscapePlans.PLOT_NIGHTS
	_check(plans.should_plot(digger), "three miserable nights, time left and a spoon: they plot")
	var plan := plans.plot(digger)
	_check(plan != null and plan.kind == EscapePlans.TUNNEL and plan.needed >= 1, "a ground-floor cell means a tunnel")
	plan.needed = 3
	plans.work_night()
	_check(plan.done == 1 and plan.mark != null, "a night's digging leaves a pile of dirt")
	var room := map.room_at_point(Vector2(plan.spot) + Vector2(0.5, 0.5))
	plans.search_room(0, room)
	_check(not plans.plans.has(digger) and digger.record.any(func(r: Array) -> bool: return r[1] == &"escape"),
			"a cell search finds the tunnel")
	# Dug through, they break out and run.
	plan = plans.plot(digger)
	plan.done = plan.needed - 1
	var ran: Array = []
	escapes.running.connect(func(p: Person) -> void: ran.append(p))
	plans.work_night()
	_check(not plans.plans.has(digger) and not (main.secure_area as SecureArea).is_secure(Vector2i(digger.flat().floor()))
			and ran.has(digger), "through the tunnel, out and running")
	# A fence cut, found by a guard passing.
	var cutter: Person = null
	for p: Person in people.people:
		if p.group == &"prisoner" and p != digger:
			cutter = p
			break
	digger.pocket.clear()
	cutter.pocket.append(screwdriver)
	PrisonerFile.of(cutter).release_day = clock.day() + 30
	for p: Person in people.people.duplicate():
		if p.role == &"guard":
			people.remove_person(p)
	var cut := plans.plot(cutter)
	_check(cut != null and cut.kind == EscapePlans.FENCE_CUT and cut.needed == EscapePlans.CUT_NIGHTS,
			"with a screwdriver, a fence cut")
	plans.work_night()
	_check(cut.done == 1, "cutting where nobody watches")
	var guard := people.add_person(0, Vector2(cut.spot) + Vector2(0.5, 0.5), "", &"staff")
	people.set_role(guard, &"guard")
	_check(not plans.quiet_at(cut.spot), "a guard nearby stops the cutting")
	clock.advance(5.0)
	_check(not plans.plans.has(cutter), "and finds the cut")
	main.free()


func _test_readout_and_eyedropper() -> void:
	var main: Node = load("res://games/prison/main.tscn").instantiate()
	main.sample = 0
	root.add_child(main)
	var controller: BuildController = main.controller
	var map: BuildingMap = main.map
	var land: Rect2i = map.land_bounds()
	var spot := land.end - Vector2i(10, 10)
	controller.tool = BuildController.Tool.ROOM
	controller._has_hover = true
	controller._dragging = true
	controller._drag_start_cell = spot
	controller._hover_point = Vector2(spot + Vector2i(3, 2)) + Vector2(0.5, 0.5)
	var said: Array = controller.readout()
	var floor_price := map.floor_def(controller.floor_style).price
	var wall_price := map.wall_def(controller.wall_style).price
	_check(said.size() == 2 and (said[0] as String).begins_with("4 × 3")
			and (said[0] as String).ends_with(Ledger.text(12 * floor_price + 14 * wall_price)) and said[1],
			"dragging a room shows its size and cost")
	(main.ledger as Ledger).sandbox = false
	(main.ledger as Ledger).balance = 10
	_check(not controller.readout()[1], "and says when you can't afford it")
	controller._dragging = false
	# The eyedropper picks up what's under the mouse.
	var placed: BuildingMap.PlacedObject = map.objects.values()[0]
	controller._hover_point = placed.centre
	_check(controller.eyedrop() and controller.tool == BuildController.Tool.OBJECT
			and controller.object_def == placed.def, "the eyedropper picks up an object")
	var floored: Vector2i = map.floors.keys()[0]
	controller._hover_point = Vector2(floored) + Vector2(0.5, 0.5)
	if map.object_at(controller._hover_point) == null:
		_check(controller.eyedrop() and controller.tool == BuildController.Tool.FLOOR
				and controller.floor_style == map.floors[floored], "and a floor")
	main.free()


func _test_move_and_copy() -> void:
	var main: Node = load("res://games/prison/main.tscn").instantiate()
	main.sample = 0
	root.add_child(main)
	var controller: BuildController = main.controller
	var map: BuildingMap = main.map
	var ledger: Ledger = main.ledger
	ledger.sandbox = false
	ledger.balance = 100000
	var land: Rect2i = map.land_bounds()
	var spot := land.end - Vector2i(12, 12)
	var rect := Rect2i(spot, Vector2i(3, 2))
	map.build_room(rect)
	var door := BuildingMap.edge_between(spot + Vector2i(1, 1), spot + Vector2i(1, 2))
	map.set_door(door, true)
	map.paint_side(BuildingMap.edge_between(spot, spot + Vector2i(-1, 0)),
			BuildingMap.wall_side(BuildingMap.edge_between(spot, spot + Vector2i(-1, 0)), Vector2(spot) + Vector2(0.5, 0.5)), &"plaster")
	var bed := PrisonCatalogue.object(&"bed")
	var bed_id := map.place_object(bed, Vector2(spot), 0)
	map.set_room_type(map.room_at(spot), &"cell")
	controller.tool = BuildController.Tool.MOVE
	controller._has_hover = true
	controller._hover_point = Vector2(spot) + Vector2(2.5, 0.5)
	_check(controller.pick_up(Rect2i(spot + Vector2i(2, 0), Vector2i.ONE)) and controller.carrying().floors.size() == 6
			and controller.carrying().ids == [bed_id], "the move tool picks up a whole room with its furniture")
	controller._turn_carried(1)
	_check(controller.carrying().size == Vector2i(2, 3), "and turns it")
	var target := spot + Vector2i(-6, -6)
	controller._hover_point = Vector2(target) + controller._grab
	var floor_price := map.floor_def(BuildingMap.DEFAULT_FLOOR).price
	var before := ledger.balance
	_check(controller.drop(), "putting it down somewhere empty works")
	_check(not map.has_floor(spot) and map.has_floor(target) and map.has_floor(target + Vector2i(1, 2))
			and not map.has_floor(target + Vector2i(2, 0)), "the room moves, turned")
	_check(map.objects.has(bed_id) and Rect2i(target, Vector2i(2, 3)).has_point(Vector2i(map.objects[bed_id].centre))
			and is_equal_approx(map.objects[bed_id].angle, PI * 0.5), "the bed keeps its id and turns with the room")
	var moved := map.room_at(target)
	_check(moved != null and moved.type == &"cell", "the room stays a cell")
	var doors := 0
	for e: Vector3i in map.walls:
		if map.walls[e] == BuildingMap.Wall.DOOR and Rect2i(target - Vector2i.ONE, Vector2i(4, 5)).has_point(Vector2i(e.x, e.y)):
			doors += 1
	_check(doors == 1, "and keeps its door")
	var paid := before - ledger.balance
	_check(paid >= 6 * floor_price and paid < 6 * floor_price + 20 * 200, "moving the structure costs its full price again (%d)" % paid)
	_check(controller.carrying() == null, "and nothing is carried afterwards")
	# A room won't go down over another.
	controller._hover_point = Vector2(target) + Vector2(0.5, 0.5)
	controller.pick_up(Rect2i(target, Vector2i.ONE))
	var grab := controller._grab
	controller._hover_point = Vector2(target + Vector2i(1, 0)) + grab
	before = ledger.balance
	_check(not controller.drop() and map.has_floor(target) and ledger.balance == before
			and map.objects.has(bed_id), "a move that overlaps itself fine, but over other floor is refused")
	controller._carried = null
	# Copy and paste make a new room, charged in full.
	controller._hover_point = Vector2(target) + Vector2(0.5, 2.5)
	_check(controller.copy_hovered() and BuildController.clipboard != null and controller.carrying() == null,
			"Ctrl+C copies the room under the mouse")
	_check(controller.paste() and controller.carrying() != null, "Ctrl+V takes up a copy")
	var copy_at := target + Vector2i(5, 0)
	controller._hover_point = Vector2(copy_at) + controller._grab
	before = ledger.balance
	var count := map.objects.size()
	_check(controller.drop() and map.has_floor(copy_at) and map.objects.size() == count + 1
			and controller.carrying() != null, "a paste puts down a new room and keeps another copy in hand")
	_check(before - ledger.balance >= 6 * floor_price + bed.price, "and costs everything in it")
	_check(map.room_at(copy_at).type == &"cell", "with its room type")
	controller._hover_point = Vector2(land.end + Vector2i(5, 5))
	_check(not controller.drop(), "but not off your land")
	# One object on its own moves for free.
	controller._carried = null
	controller._hover_point = map.objects[bed_id].centre
	controller.pick_up(Rect2i(Vector2i(map.objects[bed_id].centre), Vector2i.ONE))
	_check(controller.carrying() != null and not controller.carrying().is_structure(), "clicking an object picks up just it")
	before = ledger.balance
	var was: Vector2 = map.objects[bed_id].centre
	controller._hover_point = was + Vector2(0, 2)
	_check(controller.drop() and map.objects.has(bed_id) and map.objects[bed_id].centre.is_equal_approx(was + Vector2(0, 2))
			and ledger.balance == before, "and moving it is free")
	main.free()


func _test_templates() -> void:
	var main: Node = load("res://games/prison/main.tscn").instantiate()
	main.sample = 0
	root.add_child(main)
	var controller: BuildController = main.controller
	var map: BuildingMap = main.map
	var store: TemplateStore = controller.templates
	store.path = "user://test_templates.cfg"
	if FileAccess.file_exists(store.path):
		DirAccess.remove_absolute(store.path)
	_check(store.names() == ["Single cell", "Double cell", "Shower block", "Small canteen"],
			"four starter templates come with the game")
	var single := store.clip("Single cell")
	_check(single.size == Vector2i(2, 3) and single.objects.size() == 3 and single.types.values().has(&"cell"),
			"the single cell has its bed, toilet and radio, and is a cell")
	var land: Rect2i = map.land_bounds()
	var at := land.end - Vector2i(12, 12)
	controller._has_hover = true
	controller.carry_copy(single)
	controller._hover_point = Vector2(at) + controller._grab
	_check(controller.drop() and map.room_at(at) != null and map.room_at(at).type == &"cell"
			and map.room_at(at).type == &"cell", "a starter goes down as a ready cell")
	var problems := PrisonCatalogue.room_type(&"cell").problems(map.room_at(at), map)
	_check(problems.is_empty(), "with nothing missing (%s)" % ", ".join(problems))
	controller._carried = null
	controller._hover_point = Vector2(at) + Vector2(0.5, 2.5)
	controller.pick_up(Rect2i(at + Vector2i(0, 2), Vector2i.ONE))
	_check(store.keep("My cell", controller.carrying()) and not store.keep("Single cell", controller.carrying()),
			"your own templates can be kept, but not over a starter")
	var again := TemplateStore.new()
	again.path = store.path
	again.find_object = PrisonCatalogue.object
	var kept := again.clip("My cell")
	_check(kept != null and kept.floors.size() == 6 and kept.objects.size() == 3 and kept.walls.size() >= 10,
			"and they last, read back from the user folder")
	_check(store.free_name("My cell") == "My cell 2", "a fresh name is offered for another")
	_check(store.forget("My cell") and not store.names().has("My cell"), "and they can be forgotten")
	_check(ClipPlan.texture(kept, map.floor_def).get_width() > 0, "each has a little plan to show")
	DirAccess.remove_absolute(store.path)
	main.free()


func _test_build_feel() -> void:
	var board: Node = root.get_node_or_null(^"Sounds")
	_check(board != null and board.defs.size() == 8 and board.defs[&"build_place"].streams.size() == 3,
			"the build sounds are loaded, three takes each")
	_check(AudioServer.get_bus_index(&"Effects") >= 0 and AudioServer.get_bus_index(&"Music") >= 0,
			"with buses for effects, interface, ambience and music")
	var main: Node = load("res://games/prison/main.tscn").instantiate()
	main.sample = 0
	root.add_child(main)
	var controller: BuildController = main.controller
	var map: BuildingMap = main.map
	var feel: BuildFeel = main.build_feel
	var land: Rect2i = map.land_bounds()
	var spot := land.end - Vector2i(12, 12)
	var effects := feel.get_child_count()
	map.build_room(Rect2i(spot, Vector2i(3, 3)))
	_check(feel.get_child_count() == effects, "nothing shows while not building")
	controller.tool = BuildController.Tool.ROOM
	map.build_room(Rect2i(spot + Vector2i(4, 0), Vector2i(3, 3)))
	_check(feel.get_child_count() >= effects + 13, "building a room raises its walls and sweeps its floor")
	var view: BuildingView = main.views[0]
	map.place_object(PrisonCatalogue.object(&"bed"), Vector2(spot + Vector2i(4, 0)), 0)
	_check(not view._popping.is_empty(), "a placed object pops in")
	effects = feel.get_child_count()
	map.demolish(Rect2i(spot, Vector2i(3, 3)))
	_check(feel.get_child_count() > effects, "and demolishing puffs up dust")
	main.free()


func _test_blueprints() -> void:
	var main: Node = load("res://games/prison/main.tscn").instantiate()
	main.sample = 9
	root.add_child(main)
	var map: BuildingMap = main.map
	var blueprints: Blueprints = main.blueprints
	var controller: BuildController = main.controller
	var ledger: Ledger = main.ledger
	var jobs: JobBoard = main.jobs
	var clock: GameClock = main.clock
	clock.speed_index = 0
	ledger.sandbox = false
	ledger.balance = 50000
	_check(blueprints.instant, "a sample opened to try things out builds at once")
	blueprints.instant = false
	var land: Rect2i = map.land_bounds()
	var rect := Rect2i()
	for z in range(land.end.y - 8, land.position.y, -1):
		for x in range(land.end.x - 8, land.position.x, -1):
			if not map.in_use(Rect2i(x - 2, z - 2, 8, 8)) and map.owns(Vector2i(x - 2, z - 2)):
				rect = Rect2i(x, z, 3, 3)
				break
		if rect.has_area():
			break
	controller.tool = BuildController.Tool.ROOM
	var before := ledger.balance
	map.build_room(rect)
	_check(not map.has_floor(rect.position) and map.planned_floors.size() == 9 and map.planned_walls.size() == 12,
			"with instant building off, a room goes down as a blueprint")
	_check(ledger.balance == before, "and costs nothing yet")
	_check(not map.can_walk_between(rect.position, rect.position + Vector2i(-1, 0)),
			"its planned walls already stop people")
	var door := BuildingMap.edge_between(rect.position + Vector2i(1, 2), rect.position + Vector2i(1, 3))
	map.set_door(door, true)
	_check(map.planned_walls[door][0] == BuildingMap.Wall.DOOR, "a door in a planned wall is planned too")
	var job: Job = jobs.of_kind(&"build")[0] if not jobs.of_kind(&"build").is_empty() else null
	_check(job != null and jobs.of_kind(&"build").size() == 1, "and a job goes up for a handyman (%s)" % jobs.of_kind(&"build").size())
	controller.tool = BuildController.Tool.NONE
	var bed := PrisonCatalogue.object(&"bed")
	_check(map.place_object(bed, Vector2(rect.position), 0) != 0, "objects can go on planned floor straight away")
	var minutes := 0
	var built_some := false
	while not map.planned_floors.is_empty() or not map.planned_walls.is_empty():
		clock.advance(1.0)
		blueprints._process(0.0)
		minutes += 1
		built_some = built_some or (map.has_floor(rect.position) and not map.planned_walls.is_empty())
		if minutes > 600:
			break
	_check(map.has_floor(rect.position) and map.has_floor(rect.end - Vector2i.ONE)
			and map.wall_at(door) == BuildingMap.Wall.DOOR, "a handyman builds it, door and all (%d min)" % minutes)
	_check(built_some, "floor first, then the walls")
	var floor_price := map.floor_def(BuildingMap.DEFAULT_FLOOR).price
	_check(before - ledger.balance >= 9 * floor_price and before - ledger.balance < 9 * floor_price + 13 * 300,
			"paid for once, when work started (%d)" % (before - ledger.balance))
	_check(jobs.of_kind(&"build").is_empty(), "and the job is done")
	# Cancelling a plan before work starts is free.
	controller.tool = BuildController.Tool.ROOM
	var other := Rect2i(rect.position + Vector2i(0, -5), Vector2i(2, 2))
	map.build_room(other)
	before = ledger.balance
	_check(not map.planned_floors.is_empty(), "another plan")
	controller.tool = BuildController.Tool.DEMOLISH
	map.demolish(other)
	_check(map.planned_floors.is_empty() and map.planned_walls.is_empty() and ledger.balance == before
			and jobs.of_kind(&"build").is_empty(), "is cancelled with the demolish tool, for nothing")
	main.free()


func _test_regime() -> void:
	var clock := GameClock.new()
	clock.start_hour = 0.0
	root.add_child(clock)
	var regime := Regime.new()
	regime.operations = PrisonRegime.operations()
	regime.sessions = PrisonRegime.sessions(PrisonCatalogue.COURSES)
	regime.on_duty = func(_role: StringName, _slot: int) -> bool: return true
	regime.rooms = func(_type: StringName) -> int: return 2
	regime.clock = clock
	regime.schedule = PrisonCatalogue.SCHEDULE.copy()
	root.add_child(regime)
	regime.start()
	var reading := regime.sessions[0]
	var placed := regime.placements.filter(func(p: Regime.Placement) -> bool: return p.session == reading)
	_check(placed.size() == 7, "a course offered daily is placed seven times a week (%d)" % placed.size())
	_check(placed.all(func(p: Regime.Placement) -> bool: return regime.fits(reading, p.slot, p)), "each in a block that allows it")
	var days := {}
	for p: Regime.Placement in placed:
		days[p.slot / Schedule.SLOTS_PER_DAY] = true
	_check(days.size() == 7, "spread one a day")
	var wednesday: Regime.Placement = placed[2]
	_check(not regime.move(wednesday, 2 * Schedule.SLOTS_PER_DAY + 4), "a session can't move into the night")
	var at := wednesday.slot
	regime.set_offered(reading.id, 3)
	_check(regime.placements.filter(func(p: Regime.Placement) -> bool: return p.session == reading).size() == 3, "offering fewer places fewer")
	regime.set_offered(reading.id, 7)
	wednesday = regime.placements.filter(func(p: Regime.Placement) -> bool: return p.session == reading)[2]
	wednesday.pinned = true
	var data := regime.to_data()
	_check((data.pinned as Array).size() == 1, "pinned sessions are saved")
	_check(not regime.set_time(&"daily_report", 0, 20), "fixed operations don't move")
	_check(regime.set_time(&"intake_bus", 0, 99) and regime.slot_of(&"intake_bus") == regime.operation(&"intake_bus").latest,
			"an operation is kept inside its window")
	var due: Array = []
	regime.operation_due.connect(func(id: StringName, _index: int) -> void: due.append(id))
	clock.advance(14 * 60.0 + 1.0)
	_check(due.has(&"intake_bus") and due.has(&"kitchen_lorry") and due.count(&"tool_counts") == 1, "operations fall due at their times (%s)" % [due])
	var again := Regime.new()
	again.operations = regime.operations
	again.sessions = regime.sessions
	again.schedule = regime.schedule
	again.start()
	again.load_data(data)
	_check(again.slot_of(&"intake_bus") == 18 and again.placements.any(func(p: Regime.Placement) -> bool:
			return p.pinned and p.slot == at), "times and pinned sessions load back")
	regime.set_time(&"tool_counts", 0, 26)
	_check(regime.clashes().any(func(c: Array) -> bool: return String(c[1]).begins_with("Tool counts during")),
			"a tool count in the yard is a clash (%s)" % [regime.clashes()])
	regime.rooms = func(_type: StringName) -> int: return 0
	_check(regime.clashes().any(func(c: Array) -> bool: return String(c[1]).begins_with("No ")), "no classroom is a clash")
	again.free()
	regime.free()
	clock.free()


func _test_heads() -> void:
	var main: Node = load("res://games/prison/main.tscn").instantiate()
	main.sample = 12
	root.add_child(main)
	var heads: Heads = main.heads
	var desk_work: DeskWork = main.desk_work
	var modifiers: Modifiers = main.modifiers
	var warden := heads.warden()
	_check(warden != null, "the classroom prison has a warden on the roster")
	var security := heads.find(&"security")
	var medical := heads.find(&"medical")
	_check(heads.available(heads.find(&"education")), "a classroom brings the Head of Learning's hire card")
	heads.morning()
	var prisoners: int = heads.prisoners.call()
	_check(is_equal_approx(desk_work.pile_minutes(warden.id, &"paperwork"), prisoners * 2.0),
			"light red tape: two minutes of paperwork a prisoner for the warden")
	_check(heads.start_hire(security) and heads.hiring() == security, "the warden takes on the security hire card")
	_check(not heads.start_hire(medical), "one hire card at a time")
	_check(desk_work.items(warden.id, &"research")[0] == desk_work.piles[warden.id].back(), "paperwork comes before the card")
	desk_work.work(warden.id, desk_work.pile_minutes(warden.id))
	var applicants := heads.applicants(security)
	_check(applicants.size() == Heads.APPLICANTS and heads.hiring() == null, "a finished hire card brings two applicants")
	var head := heads.hire(applicants[0])
	_check(head != null and heads.head(security) == head and heads.applicants(security).is_empty(),
			"taking one on sends the other home")
	_check(is_equal_approx(modifiers.value(&"search_speed"), 0.1), "the Chief of Security's bonus counts")
	desk_work.add_paperwork(head.id, DeskWork.OVERLOAD + 60.0)
	desk_work.morning(0, 0, [])
	_check(desk_work.is_overloaded(head.id) and is_equal_approx(modifiers.value(&"search_speed"), 0.05),
			"an overloaded head gives half their bonus")
	desk_work.work(head.id, 400.0)
	_check(not desk_work.is_overloaded(head.id) and is_equal_approx(modifiers.value(&"search_speed"), 0.1),
			"and all of it once the pile is down")
	var saved := desk_work.capture()
	desk_work.add(head.id, &"research", "Something", 30.0, "x")
	desk_work.restore(saved)
	_check(desk_work.items(head.id, &"research").is_empty(), "desk piles save and load")
	var clock: GameClock = main.clock
	clock.advance(5.0)
	var jobs: JobBoard = main.jobs
	var on_site: Array = (main.people as People).people.filter(func(p: Person) -> bool: return p.role == &"warden")
	if not on_site.is_empty():
		_check(jobs.of_kind(Office.DESK_JOB).any(func(j: Job) -> bool: return j.only_for == on_site[0]),
				"the warden has a desk job of their own")
	heads.let_go(head)
	_check(heads.head(security) == null and modifiers.value(&"search_speed") == 0.0, "letting a head go ends the bonus")
	warden.work_traits = [heads.roster.find_work_trait(&"stickler")]
	heads.refresh_bonuses()
	_check(is_equal_approx(modifiers.value(&"search_speed"), 0.1), "a stickler warden has guards search faster")
	warden.work_traits = [heads.roster.find_work_trait(&"old_hand")]
	heads.refresh_bonuses()
	_check(modifiers.value(&"search_speed") == 0.0 and heads.start_hire(medical) == heads.available(medical)
			and (heads.hire_card() == null or heads.hire_card().total < medical.hire_minutes), "an old hand works hire cards quicker")
	warden.work_traits.clear()
	heads.cancel_hire()
	heads.refresh_bonuses()
	# Clerks take the biggest paperwork pile first.
	desk_work.add_paperwork(warden.id, 100.0)
	desk_work.add_paperwork(77, 30.0)
	desk_work.work_paperwork(110.0)
	_check(is_equal_approx(desk_work.pile_minutes(warden.id, &"paperwork") + desk_work.pile_minutes(77, &"paperwork"), 20.0)
			and desk_work.pile_minutes(77, &"paperwork") <= 30.0, "a clerk works down the paperwork, biggest pile first")
	var roster: StaffRoster = main.roster
	var cook: StaffRoster.Record = roster.take_on(&"cook", &"day")
	var pay := roster.day_pay(cook)
	var job := Job.new()
	var stage := Job.at(Job.Do.WORK, 0, 0)
	stage.minutes = StaffRoster.XP_MINUTES * 2.0
	job.stages = [stage]
	var levelled := [0]
	roster.levelled_up.connect(func(_r: StaffRoster.Record) -> void: levelled[0] += 1)
	var person := Person.new()
	person.profile["staff_id"] = cook.id
	roster.job_done(job, person)
	_check(cook.level == 2 and levelled[0] == 1, "two days' worth of work makes a level")
	_check(roster.day_pay(cook) > pay and is_equal_approx(roster.pace(person), StaffRoster.LEVEL_PACE[1]),
			"a level works faster and is paid more")
	cook.morale = 0.0
	var sick := false
	for i in 200:
		cook.low_days = 0
		cook.morale = 0.0
		roster.nightly()
		if roster.is_off(cook):
			sick = true
			break
	_check(sick and roster.next_in(&"cook", &"day") != cook, "low morale brings a sick day, and they stay home")
	main.queue_free()


func _test_in_tray() -> void:
	var main: Node = load("res://games/prison/main.tscn").instantiate()
	main.sample = 12
	root.add_child(main)
	var tray: InTray = main.in_tray
	var ledger: Ledger = main.ledger
	var people: People = main.people
	var desk_work: DeskWork = main.desk_work
	var roster: StaffRoster = main.roster
	tray.cards.clear()
	var card := tray.post(tray.find(&"guitar"))
	_check(card != null and not card.words.is_empty() and card.text().begins_with(card.words), "a request names the prisoner asking")
	var asker: Person = people.people.filter(func(p: Person) -> bool: return p.id == card.subject)[0]
	var balance := ledger.balance
	tray.answer(card, 0)
	_check(ledger.balance == balance - 40 and asker.moodlets.has(&"tray_yes") and tray.cards.is_empty(),
			"saying yes pays for it and cheers them up")
	var kettle := tray.post(tray.find(&"kettle"))
	var record: StaffRoster.Record = roster.records.filter(func(r: StaffRoster.Record) -> bool: return r.id == kettle.subject)[0]
	var morale := record.morale
	tray.answer(kettle, 1)
	_check(is_equal_approx(record.morale, maxf(morale - 5.0, 0.0)), "turning down staff lowers their morale")
	var plant := tray.post(tray.find(&"pot_plant"))
	plant.due_day = (main.clock as GameClock).day()
	tray.morning()
	_check(not tray.cards.has(plant) and tray.history.back().ends_with("(lapsed)"), "an unanswered card lapses to its default")
	desk_work.red_tape = DeskWork.RedTape.OFF
	tray.cards.clear()
	tray.morning()
	_check(tray.cards.is_empty(), "no red tape, no cards")
	desk_work.red_tape = DeskWork.RedTape.LIGHT
	roster.take_on(&"clerk", &"day")
	tray.set_rule(&"prisoner_request", &"approve")
	var book := tray.post(tray.find(&"book_club"))
	_check(book.queued == 0 and desk_work.pile_minutes(DeskWork.SHARED) > 0.0, "with a rule, the clerk takes the card")
	desk_work.work_paperwork(desk_work.all_paperwork())
	_check(not tray.cards.has(book) and tray.history.back().ends_with("(clerk)"), "and answers it after some desk work")
	var unhappy: StaffRoster.Record = roster.take_on(&"cook", &"day")
	unhappy.morale = 0.0
	unhappy.low_days = StaffRoster.QUIT_DAYS
	roster.nightly()
	var letters := tray.cards.filter(func(c: InTray.Card) -> bool: return c.def.id == &"resignation")
	_check(letters.size() == 1 and roster.records.has(unhappy), "someone unhappy writes a letter rather than just going")
	var wage := unhappy.wage
	tray.answer(letters[0], 1)
	_check(roster.records.has(unhappy) and unhappy.wage > wage and not unhappy.resigning, "a raise keeps them on")
	balance = ledger.balance
	var xp := unhappy.xp
	_check(roster.send_on_course(unhappy) and ledger.balance == balance - StaffRoster.COURSE_FEE
			and unhappy.xp > xp and roster.next_in(&"cook", &"day") != unhappy, "a course costs a fee, adds experience and takes them away")
	var files: MissingFiles = main.missing_files
	var newcomer: Person = people.people.filter(func(p: Person) -> bool: return p.group == &"prisoner")[0]
	_check(files.lose(newcomer) and MissingFiles.is_missing(newcomer)
			and (main.parole as Parole).why_not(newcomer) in ["Awaiting paperwork", "Going home anyway"],
			"an arrival without a file can't go up for parole")
	desk_work.work_paperwork(desk_work.all_paperwork())
	_check(not MissingFiles.is_missing(newcomer), "until a clerk fills it in")
	var spicy := tray.post(tray.find(&"spicy"))
	var saved := tray.capture()
	tray.cards.clear()
	tray.restore(saved)
	_check(tray.cards.size() == 1 and tray.cards[0].def.id == &"spicy" and tray.cards[0].words == spicy.words,
			"the in-tray saves and loads")
	main.queue_free()


func _test_perks() -> void:
	var main: Node = load("res://games/prison/main.tscn").instantiate()
	main.sample = 12
	root.add_child(main)
	var roster: StaffRoster = main.roster
	var ledger: Ledger = main.ledger
	var modifiers: Modifiers = main.modifiers
	var people: People = main.people
	var cook: StaffRoster.Record = roster.take_on(&"cook", &"day")
	_check(not roster.has_perk(cook), "a new cook has no perk yet")
	var balance := ledger.balance
	_check(roster.send_on_course(cook, true) and ledger.balance == balance - StaffRoster.TRAINING_FEE
			and cook.training_day == (main.clock as GameClock).day() + 1 and roster.next_in(&"cook", &"day") != null,
			"training on site is cheaper and they still come in")
	_check(roster.has_perk(cook) and modifiers.value(&"tasty_meals") >= 0.2, "after their course a cook has their perk")
	var guard: StaffRoster.Record = roster.take_on(&"guard", &"day")
	roster.add_xp(guard, StaffRoster.LEVEL_XP[StaffRoster.PERK_LEVEL - 2])
	_check(guard.level >= StaffRoster.PERK_LEVEL and roster.has_perk(guard), "a level 3 guard has their perk")
	var clerk: StaffRoster.Record = roster.take_on(&"clerk", &"day")
	var office: Office = main.office
	var slow := office.desk_speed(clerk)
	clerk.trained = true
	_check(office.desk_speed(clerk) > slow, "a skilled clerk works faster")
	modifiers.set_source(&"test_cooks", {&"tasty_meals": 1.0})
	var prisoners := people.people.filter(func(p: Person) -> bool: return p.group == &"prisoner")
	for person: Person in prisoners:
		person.moodlets.erase(&"lovely_meal")
		people.add_moodlet(person, &"good_meal")
	var had_good := prisoners.filter(func(p: Person) -> bool: return p.moodlets.has(&"good_meal")).size()
	_check(had_good > 0 and (main.kitchen as Kitchen).tasty_meals() == had_good
			and prisoners.all(func(p: Person) -> bool: return p.moodlets.has(&"lovely_meal") and not p.moodlets.has(&"good_meal")),
			"a skilled kitchen turns good meals lovely")
	var saved := roster.capture()
	roster.restore(saved)
	var again: StaffRoster.Record = roster.records.filter(func(r: StaffRoster.Record) -> bool: return r.id == cook.id)[0]
	_check(again.trained and again.training_day == cook.training_day, "training saves and loads")
	_check(not (main.training as Training).has_room(), "no training room in the sample")
	var warden: StaffRoster.Record = roster.records.filter(func(r: StaffRoster.Record) -> bool: return r.role == &"warden")[0]
	warden.work_traits.clear()
	roster.preset(&"warden", [&"stickler", &"penny_pincher"])
	_check(warden.work_traits.size() == 2 and NewGame.warden_candidates().size() == 3, "the warden picked at a new game gets their traits")
	var target := roster.morale_target(cook)
	warden.work_traits.clear()
	_check(roster.morale_target(cook) > target, "a penny pinching warden makes staff less happy")
	var level := Heads.level_scale(warden)
	roster.add_xp(warden, 20.0)
	_check(Heads.level_scale(warden) > level, "a higher level head gives a bigger bonus")
	var box: Suggestions = main.suggestions
	var tray: InTray = main.in_tray
	tray.cards.clear()
	box.last_day = -100
	_check(not box.suggest().is_empty() and tray.cards.size() == 1 and tray.cards[0].def.kind == &"suggestion",
			"a member of staff makes a suggestion, which comes in the in-tray")
	var wanted := [true]
	var files: MissingFiles = main.missing_files
	_check(files.file_minutes() == MissingFiles.FILE_MINUTES * 2.0, "without a filing cabinet, a missing file takes twice as long")
	box.ideas = [box._idea(&"test", &"guard", "A test", "Test this.", func() -> bool: return wanted[0])]
	box.open.clear()
	box.recent.clear()
	box.last_day = -100
	box.suggest()
	var suggester := box._record(box.open[0]["record"])
	suggester.morale = 50.0
	wanted[0] = false
	box.morning()
	_check(box.open.is_empty() and suggester.morale > 50.0, "taking up a suggestion cheers up whoever made it")
	main.queue_free()


func _test_staff_roster() -> void:
	var main: Node = load("res://games/prison/main.tscn").instantiate()
	main.sample = 11
	root.add_child(main)
	var roster: StaffRoster = main.roster
	var shifts: Shifts = main.shifts
	var ledger: Ledger = main.ledger
	var people: People = main.people
	var staff: Array = people.people.filter(func(p: Person) -> bool: return p.role != &"" and not p.going_home)
	_check(not staff.is_empty() and staff.all(func(p: Person) -> bool:
			var r := roster.record_of(p)
			return r != null and r.name == p.name and r.person == p), "everyone at work is on the roster by name")
	_check(roster.records.size() == staff.size() + roster.count(&"guard", &"night") + roster.count(&"cook", &"night")
			+ roster.count(&"cleaner", &"night") + roster.count(&"nurse", &"night") + roster.count(&"handyman", &"night"),
			"and so is the night shift, at home")
	var now := shifts.on_now().id
	var guard: StaffRoster.Record = roster.cheapest(&"guard", now)
	_check(guard != null and roster.applicants_for(&"warden", &"night").is_empty(), "applicants for each shift a role works")
	var before := shifts.wanted_for(&"guard", now)
	_check(roster.hire(guard) == guard and shifts.wanted_for(&"guard", now) == before + 1
			and not roster.applicants.has(guard), "hiring an applicant puts them on the shift")
	shifts.balance(true)
	_check(guard.person != null and guard.person.name == guard.name and guard.person.look_seed == guard.look_seed
			and guard.person.traits == guard.traits, "they come in as themselves")
	var wages: int = ledger.today.get("Wages", 0)
	var person := guard.person
	roster.dismiss(guard)
	shifts.balance()
	_check(ledger.today.get("Wages", 0) == wages - roster.day_pay(guard) and person.going_home
			and shifts.wanted_for(&"guard", now) == before, "letting someone go pays a day's notice and sends them home")
	var cook: StaffRoster.Record = roster.on(&"cook", now)[0]
	var wage := cook.wage
	roster.raise(cook)
	_check(cook.wage > wage and roster.pay_feeling(cook) > (float(wage) / 60.0 - 1.0) * 100.0, "a raise, and they feel it")
	cook.wage = 15
	var quit: Array = []
	roster.quit.connect(func(r: StaffRoster.Record) -> void: quit.append(r))
	for i in 25:
		roster.nightly()
	var tray: InTray = main.in_tray
	var letter: Array = tray.cards.filter(func(c: InTray.Card) -> bool: return c.def.id == &"resignation" and c.subject == cook.id)
	_check(letter.size() == 1, "badly paid and miserable, they write a resignation letter")
	if not letter.is_empty():
		tray.answer(letter[0], 0)
	shifts.balance()
	_check(quit.has(cook) and not roster.records.has(cook) and cook.person.going_home, "accepting it, they go")
	_check(roster.applicants.all(func(a: StaffRoster.Record) -> bool: return a.until >= (main.clock as GameClock).day()),
			"applicants wait a few days")
	var names: Array = roster.records.map(func(r: StaffRoster.Record) -> String: return r.name)
	var saved := PrisonSave.capture(main)
	main.queue_free()
	main = load("res://games/prison/main.tscn").instantiate()
	PrisonSave.pending = saved
	root.add_child(main)
	roster = main.roster
	_check(roster.records.map(func(r: StaffRoster.Record) -> String: return r.name) == names
			and (main.people as People).people.all(func(p: Person) -> bool:
				return p.role == &"" or p.going_home or roster.record_of(p) != null and roster.record_of(p).person == p),
			"the roster saves, and staff at work rejoin it")
	main.queue_free()


func _test_budget() -> void:
	var main: Node = load("res://games/prison/main.tscn").instantiate()
	main.sample = 11
	root.add_child(main)
	var budget: Budget = main.budget
	var ledger: Ledger = main.ledger
	var clock: GameClock = main.clock
	var week: Array = budget.forecast()
	_check(week.size() == 7 and week.all(func(row: Array) -> bool: return row[1] > 0 and row[2] > 0),
			"a week ahead of money in and out")
	_check(budget.has_workshop() and budget.make_offers().size() == Budget.OFFERS, "contracts on offer for the workshop")
	var offer: Dictionary = budget.offers[0]
	_check(budget.accept(0) and budget.contract.goods == offer.goods and not budget.accept(0), "one contract at a time")
	var before: int = ledger.today.get("Contracts", 0)
	(main.workshop as Workshop).collected.emit(offer.goods)
	_check(budget.contract.is_empty() and ledger.today.get("Contracts", 0) - before == offer.pay,
			"made in time, it pays on top")
	var balance := ledger.balance
	_check(budget.borrow(5000) and ledger.balance == balance + 5000 and not budget.borrow(2000), "one loan at a time")
	clock.jump_to_hour(0)
	_check(budget.loan.left == 5500 - 550, "paid back a share each midnight, with interest")
	budget.make_offers()
	budget.accept(1)
	var due: int = budget.contract.due
	while clock.day() <= due:
		clock.jump_to_hour(0)
	_check(budget.contract.is_empty(), "late, a contract lapses")
	main.free()
