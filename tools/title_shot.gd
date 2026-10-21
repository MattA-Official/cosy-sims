extends SceneTree
## Renders the title screen and saves a screenshot. Needs a real renderer.
## Usage: godot --path . -s res://tools/title_shot.gd -- out.png [new|load]
var _frames := 0
var _title: Node

func _initialize() -> void:
	_title = load("res://games/prison/title.tscn").instantiate()
	root.add_child(_title)

func _process(_delta: float) -> bool:
	var args := OS.get_cmdline_user_args()
	_frames += 1
	if _frames == 5:
		if args.has("new"):
			_title._show(_title._new_game)
		elif args.has("load"):
			_title._show(_title._load_card)
	if _frames < 90:
		return false
	root.get_texture().get_image().save_png(args[0])
	print("Saved ", args[0])
	return true
