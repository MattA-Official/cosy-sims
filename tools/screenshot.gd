extends SceneTree
## Renders the main scene for a moment and saves a screenshot. Needs a real
## renderer (not --headless). Usage:
##   godot --path . -s res://tools/screenshot.gd -- out.png [hour] [timetable]
## With an hour, the day plays out at speed until then first (12.25 is
## 12:15); "timetable" opens the timetable window.

const FRAMES_TO_WAIT := 90

var _frames := 0
var _main: Node


func _initialize() -> void:
	var scene: PackedScene = load(ProjectSettings.get_setting("application/run/main_scene"))
	_main = scene.instantiate()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	var args := OS.get_cmdline_user_args()
	_frames += 1
	if _frames == 1 and args.size() > 1:
		var clock: GameClock = _main.clock
		clock.speed_index = 0
		var target := (clock.day() - 1) * GameClock.MINUTES_PER_DAY + float(args[1]) * 60.0
		if target < clock.total_minutes:
			target += GameClock.MINUTES_PER_DAY
		while clock.total_minutes < target:
			clock.advance(minf(0.5, target - clock.total_minutes))
		if args.has("timetable"):
			_main.timetable.toggle()
	if _frames < FRAMES_TO_WAIT:
		return false
	var path: String = args[0] if args.size() > 0 else "user://screenshot.png"
	root.get_texture().get_image().save_png(path)
	print("Saved ", path)
	return true
