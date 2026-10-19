extends SceneTree
## Saves the shared UI themes from CosyTheme's palettes. Usage:
##   godot --headless --path . -s res://tools/build_theme.gd

const THEMES := {
	"res://core/ui/cosy_theme.tres": "LIGHT",
	"res://core/ui/cosy_theme_dark.tres": "DARK",
}


func _initialize() -> void:
	for path: String in THEMES:
		var palette: Dictionary = CosyTheme.LIGHT if THEMES[path] == "LIGHT" else CosyTheme.DARK
		var error := ResourceSaver.save(CosyTheme.build(palette), path)
		print("Saved ", path if error == OK else "nothing: error %d" % error)
	quit()
