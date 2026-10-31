extends SceneTree
## Renders the airport scene with the shed and saves a screenshot. Needs a
## real renderer (not --headless). Usage:
##   godot --path . -s res://tools/airport_shot.gd -- out.png [zones] [level=N] [view=N] [zoom=F] [at=X,Z] [gap] [title]
## "zones" opens the zones tool; level=N builds on that level; view=N sets
## the Tab view (0 up, 1 cutaway, 2 down, 3 roofs); at=X,Z points the
## camera at a tile from the shed's corner; "gap" swaps the screening point
## for a plain door, to show it in red; "title" shows the title screen.

const FRAMES_TO_WAIT := 90

var _frames := 0
var _main: Node


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.has("title"):
		_main = (load("res://games/airport/title.tscn") as PackedScene).instantiate()
	else:
		_main = (load("res://games/airport/main.tscn") as PackedScene).instantiate()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	var args := OS.get_cmdline_user_args()
	_frames += 1
	if _frames == 1 and not args.has("title"):
		var building: Building = _main.building
		var o: Vector2i = building.ground().land_bounds().get_center() - SampleAirports.SHED_SIZE / 2
		var rig: CameraRig = _main.camera_rig
		rig.focus_on(Vector3(o.x + 12.5, 0.0, o.y + 7.0) * _main.grid.cell_size)
		if args.has("gap"):
			building.ground().set_door(BuildingMap.edge_between(o + Vector2i(11, 5), o + Vector2i(12, 5)), true, &"")
		if args.has("zones"):
			_main.controller.tool = BuildController.Tool.ZONE
		for arg in args:
			if arg.begins_with("level="):
				building.active = int(arg.get_slice("=", 1))
			elif arg.begins_with("view="):
				_main.controller.wall_view = int(arg.get_slice("=", 1)) as BuildController.WallView
			elif arg.begins_with("at="):
				var at := arg.get_slice("=", 1).split(",")
				rig.focus_on(Vector3(o.x + float(at[0]), 0.0, o.y + float(at[1])) * _main.grid.cell_size)
			elif arg.begins_with("zoom="):
				rig.zoom_by(float(arg.get_slice("=", 1)))
	if _frames < FRAMES_TO_WAIT:
		return false
	var path: String = args[0] if args.size() > 0 else "user://airport.png"
	root.get_texture().get_image().save_png(path)
	print("Saved ", path)
	return true
