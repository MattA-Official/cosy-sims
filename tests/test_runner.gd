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
	_test_angled_walls()
	_test_path_profile()
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
	# Split levels: raise half the ground room, then go too far.
	building.active = 0
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
	var stairs: ObjectDef = load("res://games/prison/catalogue/stairs.tres")
	var lift: ObjectDef = load("res://games/prison/catalogue/lift.tres")
	var staff_lift: ObjectDef = load("res://games/prison/catalogue/lift_staff.tres")
	var upstairs := building.level(1)
	upstairs.fill_floor(Rect2i(2, 2, 4, 4), &"wood", 0.5 + Building.STOREY)
	var flight := ground.place_object(stairs, Vector2(3, 2), 0)
	_check(flight != 0 and not upstairs.has_floor(Vector2i(3, 3)) and upstairs.holes.has(Vector2i(3, 4))
			and upstairs.has_floor(Vector2i(4, 3)), "stairs cut a hole in the floor above")
	_check(upstairs.fill_floor(Rect2i(3, 2, 1, 3), &"wood", 0.5 + Building.STOREY) == 0,
			"no floor goes over a stairwell")
	var links := building.links()
	_check(links.size() == 2 and links[0].from_cell == Vector2i(3, 1) and links[0].to_level == 1
			and links[0].to_cell == Vector2i(3, 5), "stairs link the foot to the landing above")
	ground.remove_object(flight)
	_check(upstairs.holes.is_empty() and upstairs.fill_floor(Rect2i(3, 2, 1, 3), &"wood", 2.25) == 3,
			"removing stairs lets floor back in")
	_check(not building.can_place(Building.MAX_LEVEL, stairs, Vector2(3, 2), 0),
			"no stairs on the top level")
	ground.place_object(lift, Vector2(4, 4), 0)
	_check(building.links().is_empty(), "a lift alone goes nowhere")
	upstairs.place_object(staff_lift, Vector2(4, 4), 0)
	links = building.links()
	_check(links.size() == 2 and links[0].kind == ObjectDef.Connects.LIFT and links[0].staff_only
			and links[1].staff_only, "lifts stacked up link, and staff lifts are staff only")


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
	_check(map.set_piece_floor(Vector2(3.8, 3.2), false) and not map.room_at_point(Vector2(3.5, 2.5)).enclosed
			and is_equal_approx(map.room_at_point(Vector2(3.5, 2.5)).area, 7.5),
			"taking up half a tile leaves a gap in the room")
	map.set_piece_floor(Vector2(3.8, 3.2), true)
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
	var over := PathProfile.build(PathNetwork.sample_curve(Vector2(3, 5), Vector2(8, 5), Vector2(13, 5)), terrain)
	_check(over.has_kind(PathProfile.Kind.BRIDGE), "a path over the pond becomes a bridge")
	var lowest := INF
	for i in over.points.size():
		if over.points[i].x > 6.5 and over.points[i].x < 9.5:
			lowest = minf(lowest, over.heights[i])
	_check(lowest >= water.bodies[0].level + PathProfile.BRIDGE_CLEARANCE - 0.01, "the bridge stays above the water")
	var up := PathProfile.build(PathNetwork.sample_curve(Vector2(17, 2), Vector2(19.5, 2), Vector2(22, 2)), terrain)
	_check(up.has_kind(PathProfile.Kind.STEPS), "a steep path becomes steps")
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
