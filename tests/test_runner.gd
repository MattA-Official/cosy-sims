extends SceneTree
## Headless checks. Run from the project folder with:
##   godot --headless -s res://tests/test_runner.gd

var _failures := 0


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
	_test_terrain()
	_test_water()
	_test_path_network()
	_test_building_levels()
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
			if index == 2 or index == 3:
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
					_check(people.people.all(func(p: Person) -> bool: return p.activity == "Sleeping"),
							"in the night everyone is asleep")
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
func _reachable_needs(people: People) -> Array[StringName]:
	var out: Array[StringName] = []
	for def in people.needs:
		if not def.id in [&"sleep", &"hunger", &"hygiene", &"bladder"]:
			continue
		var everyone := true
		for person in people.people:
			var found := false
			for n: int in people.building.levels:
				for placed: BuildingMap.PlacedObject in people.building.levels[n].objects.values():
					if found or not placed.def.tags.any(def.met_by):
						continue
					for spot in people._spots_beside(n, placed, person.flat()):
						if not people.nav().find_path(person.level, person.flat(), n, spot).is_empty():
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
