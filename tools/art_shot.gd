extends SceneTree
## Saves a close-up screenshot of the running game for judging art, with the
## HUD hidden. Needs a real renderer (not --headless):
##   godot --path . --rendering-driver vulkan -s res://tools/art_shot.gd -- out.png [x z distance yaw pitch] [sample=N] [hud]
## x and z are the tile to look at. sample picks a sample prison, as in Main.

const FRAMES_TO_WAIT := 120

var _frames := 0
var _main: Node


func _initialize() -> void:
	var scene: PackedScene = load(ProjectSettings.get_setting("application/run/main_scene"))
	_main = scene.instantiate()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("sample="):
			_main.set("sample", int(arg.trim_prefix("sample=")))
	root.add_child(_main)


func _process(_delta: float) -> bool:
	_frames += 1
	var args := OS.get_cmdline_user_args()
	var numbers: Array[float] = []
	for arg in args:
		if arg.is_valid_float():
			numbers.append(float(arg))
	if _frames == 2:
		if not "hud" in args:
			for layer in root.find_children("*", "CanvasLayer", true, false):
				layer.visible = false
		if numbers.size() >= 3:
			var rig: Node3D = _main.get_node("CameraRig")
			rig.set("_target_position", Vector3(numbers[0], 0.0, numbers[1]))
			rig.set("_target_distance", numbers[2])
			rig.set("_distance", numbers[2])
			if numbers.size() >= 4:
				rig.set("_target_yaw", numbers[3])
				rig.set("_yaw", numbers[3])
			if numbers.size() >= 5:
				rig.set("_target_pitch", numbers[4])
				rig.set("_pitch", numbers[4])
			rig.position = Vector3(numbers[0], 0.0, numbers[1])
	if _frames < FRAMES_TO_WAIT:
		return false
	var path := "user://art_shot.png"
	for arg in args:
		if arg.ends_with(".png"):
			path = arg
	root.get_texture().get_image().save_png(path)
	print("Saved ", path)
	return true
