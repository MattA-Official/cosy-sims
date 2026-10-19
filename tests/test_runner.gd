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
	_test_foliage()
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
	_check(map.rooms().size() == 6, "sample layout has six rooms")
	var view: BuildingView = main.get_node("BuildGrid/BuildingView")
	view.rebuild()
	_check(view.get_child_count() > 0, "view builds its parts")
	var windows := map.walls.values().count(BuildingMap.Wall.WINDOW)
	_check(windows == 5, "sample layout has five windows")
	var overlay: DebugOverlay = main.debug_overlay
	overlay.visible = true
	overlay._draw_rooms()
	# The first cell's middle tile, just inside its barred window.
	var text := overlay.describe(map.land_bounds().get_center() - Vector2i(7, 7))
	_check(text.contains("Enclosed: yes") and text.contains("Indoors") and text.contains("bars window"),
			"debug view describes a cell, its room and its window")
	_check(overlay.describe(GridCursor.NO_CELL).contains("Rooms: "), "debug view shows totals")
	_test_tools(main.controller, map)
	main.free()


## Drives the build tools the way the mouse would, by moving the hover point.
## Positions are relative to the corner of the owned land.
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
	hover.call(10.5, 10.5)
	controller._on_press()
	hover.call(12.5, 12.5)
	controller._on_release()
	var floor_height := terrain.cell_height(cell.call(10, 10))
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
	_check(map.floors[cell.call(11, 11)] == &"wood" and is_equal_approx(map.floor_height(cell.call(9, 9)),
			floor_height), "floor next to a room is laid at the room's height")
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


func _test_foliage() -> void:
	var foliage := FoliageLayer.new()
	var tree: FoliageDef = PrisonCatalogue.PLANTS[0]
	var flower: FoliageDef = PrisonCatalogue.PLANTS[3]
	_check(foliage.add(tree, Vector2(5, 5)), "first tree goes in")
	_check(not foliage.add(tree, Vector2(5.5, 5)), "trees keep their spacing")
	_check(foliage.add(tree, Vector2(5 + tree.spacing + 0.1, 5)), "a tree further away goes in")
	_check(not foliage.add(flower, Vector2(5.1, 5)), "nothing grows right on top of a tree")
	_check(foliage.add(flower, Vector2(5.5, 5.2)), "flowers can grow near a tree")
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
