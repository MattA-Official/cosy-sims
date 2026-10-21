extends SceneTree
## Saves a close-up of a few wall joins (corners, T-junctions, a crossing,
## angled walls and walls of different styles meeting) for checking how
## walls are drawn. Needs a real renderer (not --headless):
##   godot --path . --rendering-driver vulkan -s res://tools/wall_shot.gd -- out.png [yaw] [distance] [pitch] [low] [paint] [hud]
## "hud" keeps the HUD and opens the wall tool's paint mode.
## "paint" paints some sides: the first brick room tiled inside, and one
## side of the wall between the plaster rooms grey.

const FRAMES_TO_WAIT := 120

var _frames := 0
var _main: Node


func _initialize() -> void:
	var scene: PackedScene = load("res://games/prison/main.tscn")
	_main = scene.instantiate()
	_main.set("build_sample_layout", false)
	root.add_child(_main)


func _process(_delta: float) -> bool:
	_frames += 1
	var args := OS.get_cmdline_user_args()
	var numbers: Array[float] = []
	for arg in args:
		if arg.is_valid_float():
			numbers.append(float(arg))
	if _frames == 2:
		if "hud" in args:
			var controller: BuildController = _main.get("controller")
			controller.wall_mode = BuildController.WallMode.PAINT
			controller.wall_style = &"wall_tiles"
			controller.tool = BuildController.Tool.WALL
		else:
			for layer in root.find_children("*", "CanvasLayer", true, false):
				layer.visible = false
		var map: BuildingMap = _main.get("map")
		var o := map.land_bounds().get_center() - Vector2i(4, 4)
		_build(map, o)
		if "paint" in args:
			map.paint_sides(map.sides_facing(Vector2(o) + Vector2(1.5, 1.5)), &"wall_tiles")
			for edge in BuildingMap.edges_on_line(o + Vector2i(3, 3), o + Vector2i(3, 6)):
				map.paint_side(edge, BuildingMap.wall_side(edge, Vector2(o) + Vector2(4.5, 4.5)), &"grey_blocks")
		if "low" in args:
			(_main.get("view") as BuildingView).walls_low = true
		var rig: Node3D = _main.get_node("CameraRig")
		var cs: float = (_main.get("grid") as BuildGrid).cell_size
		var target := Vector3(o.x + 4, 0.0, o.y + 4) * cs
		var distance := numbers[1] if numbers.size() > 1 else 9.0
		rig.set("_target_position", target)
		rig.position = target
		rig.set("_target_distance", distance)
		rig.set("_distance", distance)
		if numbers.size() > 0:
			rig.set("_target_yaw", numbers[0])
			rig.set("_yaw", numbers[0])
		if numbers.size() > 2:
			rig.set("_target_pitch", numbers[2])
			rig.set("_pitch", numbers[2])
	if _frames < FRAMES_TO_WAIT:
		return false
	var path := "user://wall_shot.png"
	for arg in args:
		if arg.ends_with(".png"):
			path = arg
	root.get_texture().get_image().save_png(path)
	print("Saved ", path)
	return true


## Two brick rooms with a plaster room beside them (thick and thin walls
## meeting), a crossing, and an angled wall cutting a corner off.
func _build(map: BuildingMap, o: Vector2i) -> void:
	map.build_room(Rect2i(o, Vector2i(3, 3)), &"concrete", &"brick")
	map.build_room(Rect2i(o + Vector2i(3, 0), Vector2i(3, 3)), &"concrete", &"brick")
	map.build_room(Rect2i(o + Vector2i(0, 3), Vector2i(6, 3)), &"wood", &"plaster")
	map.build_walls(BuildingMap.edges_on_line(o + Vector2i(3, 3), o + Vector2i(3, 6)), &"plaster")
	map.build_walls(BuildingMap.edges_on_line(o + Vector2i(6, 1), o + Vector2i(8, 1)), &"plaster")
	map.set_door(Vector3i(o.x + 1, o.y + 3, BuildingMap.EDGE_X), true)
	map.set_opening(Vector3i(o.x + 4, o.y + 6, BuildingMap.EDGE_X), BuildingMap.Wall.WINDOW,
			BuildingMap.WINDOW_GLASS)
	map.build_slants(BuildingMap.slants_on_line(o + Vector2i(0, 8), o + Vector2i(3, 6)), &"plaster")
	map.build_walls(BuildingMap.edges_on_line(o + Vector2i(0, 6), o + Vector2i(0, 8)), &"plaster")
	map.build_slants(BuildingMap.slants_on_line(o + Vector2i(6, 3), o + Vector2i(8, 5)), &"brick")
	map.build_walls(BuildingMap.edges_on_line(o + Vector2i(6, 6), o + Vector2i(8, 6)), &"fence")
	map.build_walls(BuildingMap.edges_on_line(o + Vector2i(8, 5), o + Vector2i(8, 6)), &"fence")
	map.fill_floor(Rect2i(o + Vector2i(0, 6), Vector2i(3, 2)), &"wood")
