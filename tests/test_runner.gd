extends SceneTree
## Headless checks. Run from the project folder with:
##   godot --headless -s res://tests/test_runner.gd

var _failures := 0


func _process(_delta: float) -> bool:
	# Runs on the first frame, once the root viewport is in the tree.
	_test_grid_conversions()
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


func _test_main_scene_loads() -> void:
	var scene: PackedScene = load("res://games/prison/main.tscn")
	_check(scene != null, "main scene loads")
	if scene == null:
		return
	var main := scene.instantiate()
	root.add_child(main)
	_check(main.get_node("BuildGrid/Ground") != null, "grid builds its ground")
	main.free()
