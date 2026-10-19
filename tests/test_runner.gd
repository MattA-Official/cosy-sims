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
	_test_demolish()
	_test_main_scene_loads()
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
	var map := BuildingMap.new(Vector2i(20, 20))
	map.fill_floor(Rect2i(0, 0, 4, 4))
	_check(map.rooms().size() == 1 and not map.rooms()[0].enclosed, "bare floor is one open room")

	map = BuildingMap.new(Vector2i(20, 20))
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
	var map := BuildingMap.new(Vector2i(20, 20))
	map.build_room(Rect2i(0, 0, 6, 3))
	map.set_room_type(map.room_at(Vector2i.ZERO), &"cell")
	_check(map.room_at(Vector2i(5, 2)).type == &"cell", "room type covers the room")
	_check(Array(cell_type.problems(map.room_at(Vector2i.ZERO), map)) == ["Needs a bed", "Needs a toilet"],
			"empty cell lists what it needs")
	map.place_object(PrisonCatalogue.object(&"bed"), Vector2i(0, 0), 0)
	map.place_object(PrisonCatalogue.object(&"toilet"), Vector2i(1, 0), 0)
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
	var map := BuildingMap.new(Vector2i(20, 20))
	_check(map.place_object(bed, Vector2i(1, 1), 0) == 0, "objects need floor")
	map.build_room(Rect2i(0, 0, 4, 4))
	var id := map.place_object(bed, Vector2i(1, 1), 0)
	_check(id != 0 and map.object_at(Vector2i(1, 2)).id == id, "bed covers two cells")
	_check(map.place_object(bed, Vector2i(1, 2), 1) == 0, "objects cannot overlap")
	_check(map.place_object(bed, Vector2i(0, 2), 1) == 0, "a rotated bed runs into the first one")
	_check(map.place_object(bed, Vector2i(3, 3), 0) == 0, "objects stay on the floor")
	_check(not map.can_build_wall(Vector3i(1, 2, BuildingMap.EDGE_X)), "no wall through an object")
	map.build_walls([Vector3i(3, 1, BuildingMap.EDGE_Z)])
	_check(not map.can_place(bed, Vector2i(2, 1), 1), "objects cannot straddle a wall")
	_check(map.remove_object(id) and map.object_at(Vector2i(1, 1)) == null, "objects can be removed")


func _test_demolish() -> void:
	var map := BuildingMap.new(Vector2i(20, 20))
	map.build_room(Rect2i(0, 0, 3, 3))
	map.build_room(Rect2i(3, 0, 3, 3))
	map.place_object(PrisonCatalogue.object(&"toilet"), Vector2i(4, 1), 0)
	map.demolish(Rect2i(3, 0, 3, 3))
	_check(map.objects.is_empty(), "demolish removes objects")
	_check(map.rooms().size() == 1 and not map.rooms()[0].enclosed,
			"demolish takes the shared wall with it")


func _test_main_scene_loads() -> void:
	var scene: PackedScene = load("res://games/prison/main.tscn")
	_check(scene != null, "main scene loads")
	if scene == null:
		return
	var main := scene.instantiate()
	root.add_child(main)
	_check(main.get_node("BuildGrid/Ground") != null, "grid builds its ground")
	var map: BuildingMap = main.map
	_check(map.rooms().size() == 5, "sample layout has five rooms")
	var view: BuildingView = main.get_node("BuildGrid/BuildingView")
	view.rebuild()
	_check(view.get_child_count() > 0, "view builds its parts")
	_test_tools(main.controller, map)
	main.free()


## Drives the build tools the way the mouse would, by moving the hover point.
func _test_tools(controller: BuildController, map: BuildingMap) -> void:
	var hover := func(point: Vector2) -> void:
		controller._has_hover = true
		controller._hover_point = point
	var rooms_before := map.rooms().size()

	controller.tool = BuildController.Tool.ROOM
	hover.call(Vector2(2.5, 2.5))
	controller._on_press()
	hover.call(Vector2(5.5, 4.5))
	controller._draw_preview()
	controller._on_release()
	_check(map.rooms().size() == rooms_before + 1 and map.room_at(Vector2i(2, 2)).cells.size() == 12,
			"room tool builds an enclosed room")

	controller.tool = BuildController.Tool.WALL
	hover.call(Vector2(4.1, 1.9))
	controller._on_press()
	hover.call(Vector2(3.8, 5.2))
	controller._on_release()
	_check(map.rooms().size() == rooms_before + 2, "wall tool splits the room")

	controller.tool = BuildController.Tool.DOOR
	hover.call(Vector2(3.9, 3.5))
	controller._on_press()
	_check(map.wall_at(Vector3i(4, 3, BuildingMap.EDGE_Z)) == BuildingMap.Wall.DOOR, "door tool makes a door")

	controller.tool = BuildController.Tool.OBJECT
	controller.object_def = PrisonCatalogue.object(&"toilet")
	hover.call(Vector2(2.5, 2.5))
	controller._draw_preview()
	controller._on_press()
	_check(map.object_at(Vector2i(2, 2)) != null, "object tool places an object")

	controller.tool = BuildController.Tool.ROOM_TYPE
	controller.room_type = PrisonCatalogue.room_type(&"cell")
	controller._on_press()
	_check(map.room_at(Vector2i(2, 2)).type == &"cell", "room type tool marks the room")

	controller.tool = BuildController.Tool.DEMOLISH
	controller._on_press()
	controller._on_release()
	_check(map.object_at(Vector2i(2, 2)) == null and map.has_floor(Vector2i(2, 2)),
			"demolish click removes just the object")
	hover.call(Vector2(2.5, 2.5))
	controller._on_press()
	hover.call(Vector2(5.5, 4.5))
	controller._on_release()
	_check(map.rooms().size() == rooms_before, "demolish drag clears the area")
