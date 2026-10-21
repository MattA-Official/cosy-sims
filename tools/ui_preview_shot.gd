extends SceneTree
## Puts the theme mock-up over the running game, with the game's own HUD
## hidden, and saves a screenshot. Needs a real renderer (not --headless):
##   godot --path . --rendering-driver vulkan -s res://tools/ui_preview_shot.gd -- out.png [dark] [accent=#6f93b8]
## An accent rebuilds the theme with that accent, to try another game's colour.

const FRAMES_TO_WAIT := 90

var _frames := 0


func _initialize() -> void:
	var scene: PackedScene = load("res://games/prison/main.tscn")
	root.add_child(scene.instantiate())


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 5:
		for layer in root.find_children("*", "CanvasLayer", true, false):
			layer.visible = false
		var args := OS.get_cmdline_user_args()
		var dark := "dark" in args
		var layer := CanvasLayer.new()
		layer.layer = 50
		root.add_child(layer)
		var preview: Control = load("res://core/ui/theme_preview.gd").new()
		preview.theme = load("res://core/ui/cosy_theme_dark.tres" if dark else "res://core/ui/cosy_theme.tres")
		for arg in args:
			if arg.begins_with("accent="):
				preview.theme = CosyTheme.build(CosyTheme.DARK if dark else CosyTheme.LIGHT, Color(arg.trim_prefix("accent=")))
		layer.add_child(preview)
	if _frames < FRAMES_TO_WAIT:
		return false
	var path := "user://ui_preview.png"
	for arg in OS.get_cmdline_user_args():
		if arg.ends_with(".png"):
			path = arg
	root.get_texture().get_image().save_png(path)
	print("Saved ", path)
	return true
