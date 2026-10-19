extends SceneTree
## Renders the main scene for a moment and saves a screenshot. Needs a real
## renderer (not --headless). Usage:
##   godot --path . -s res://tools/screenshot.gd -- out.png

const FRAMES_TO_WAIT := 90

var _frames := 0


func _initialize() -> void:
	var scene: PackedScene = load(ProjectSettings.get_setting("application/run/main_scene"))
	root.add_child(scene.instantiate())


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < FRAMES_TO_WAIT:
		return false
	var args := OS.get_cmdline_user_args()
	var path: String = args[0] if args.size() > 0 else "user://screenshot.png"
	root.get_texture().get_image().save_png(path)
	print("Saved ", path)
	return true
