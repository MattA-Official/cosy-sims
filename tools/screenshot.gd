extends SceneTree
## Renders the main scene for a moment and saves a screenshot. Needs a real
## renderer (not --headless). Usage:
##   godot --path . -s res://tools/screenshot.gd -- out.png [hour] [timetable] [staff] [money] [office] [bus] [debug] [route] [land] [loop=X,Z,...] [break=TAG] [trouble] [fight] [perimeter] [security] [sample=N] [inspect=N] [zones] [at=X,Z] [zoom=F]
## With an hour, the day plays out at speed until then first (12.25 is
## 12:15); "timetable" opens the timetable window; sample=N starts in
## another sample prison; inspect=N opens the F3 inspector on the Nth
## person; "zones" opens the zones tool; "land" buys a plot and shows the
## plots for sale; "staff" opens the staff window;
## "money" and "office" open those windows; "bus" brings the morning bus;
## "debug" turns on the debug view (F3); "route" opens the patrol route
## tool; loop=X,Z,X,Z,... draws a patrol route with a guard on it;
## break=TAG breaks the first object with that tag; "security" opens the
## Security window and shows what's being watched;
## at=X,Z points the camera at a tile, and zoom=F scales its distance.

const FRAMES_TO_WAIT := 90

var _frames := 0
var _main: Node


func _initialize() -> void:
	var scene: PackedScene = load(ProjectSettings.get_setting("application/run/main_scene"))
	_main = scene.instantiate()
	var sample := _option("sample")
	if sample >= 0:
		_main.sample = sample
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
		if args.has("zones"):
			_main.controller.tool = BuildController.Tool.ZONE
		if args.has("staff"):
			_main.staff_window.toggle()
		if args.has("money"):
			_main.finance_window.toggle()
		if args.has("office"):
			_main.office_window.toggle()
		if args.has("bus"):
			_main.intake.bus()
		if args.has("debug"):
			_main.debug_overlay.visible = true
		if args.has("land"):
			var land: Rect2i = _main.building.land[0]
			var plots: LandPlots = _main.land_plots
			plots.buy(plots.plot_at(Vector2i(land.end.x + 1, land.position.y + 9)), true)
			_main.controller.buying_land = true
			_main.controller.flatten_land = true
			_main.controller.tool = BuildController.Tool.TERRAIN
		if args.has("route"):
			_main.controller.tool = BuildController.Tool.ROUTE
		if args.has("perimeter"):
			# A perimeter fence a little inside the land, with a people gate.
			var map: BuildingMap = _main.building.ground()
			var edges := BuildingMap.rect_perimeter(map.land_bounds().grow(-2))
			map.build_walls(edges, &"perimeter_fence")
			map.set_door(edges[edges.size() / 2], true, &"people_gate")
		if args.has("fight"):
			# Two prisoners scrapping, and one already knocked out beside them.
			var prisoners: Array = _main.people.people.filter(func(p: Person) -> bool: return p.group == &"prisoner")
			var a: Person = prisoners[0]
			for i in [1, 2]:
				var other: Person = prisoners[i]
				_main.people.stop(other)
				other.level = a.level
				other.position = a.position + Vector3(0.7 * i, 0.0, 0.3 * i)
			(prisoners[2] as Person).health = 20.0
			_main.people.stop(a)
			_main.fights.begin(a, prisoners[1])
			_main.camera_rig.focus_on(a.position * _main.grid.cell_size)
		if args.has("trouble"):
			# Every prisoner fed up: some grumble, some about to act up.
			var misconduct: Misconduct = _main.misconduct
			var prisoners: Array = _main.people.people.filter(func(p: Person) -> bool: return p.group == &"prisoner")
			for i in prisoners.size():
				var person: Person = prisoners[i]
				person.mood = 15.0
				person.temper = 80.0
				var rung := misconduct.rungs[i % misconduct.rungs.size()]
				if rung.warning_minutes > 0.0:
					person.warning = rung.id
					person.warning_minutes = 60.0
					person.bubble = Misconduct.words_over_head(rung, person)
					person.bubble_minutes = 60.0
				else:
					misconduct.act(person, rung)
			misconduct.act(prisoners[0], misconduct.rung(&"vandalism"))
		if args.has("security"):
			_main.coverage_tint.shown = true
			_main.security_window.toggle()
		for arg in args:
			if arg.begins_with("at="):
				var at := arg.get_slice("=", 1).split_floats(",")
				_main.camera_rig.focus_on(Vector3(at[0], 0.0, at[1]) * _main.grid.cell_size)
			elif arg.begins_with("loop="):
				var at := arg.get_slice("=", 1).split_floats(",")
				for i in range(0, at.size() - 1, 2):
					_main.routes.click(0, Vector2(at[i], at[i + 1]))
				_main.routes.finish()
				_main.routes.set_guards(_main.routes.routes.back(), 1)
			elif arg.begins_with("break="):
				var tagged: Array[StringName] = [StringName(arg.get_slice("=", 1))]
				for key in _main.building.objects_tagged(tagged).slice(0, 1):
					_main.wear.break_object(key)
			elif arg.begins_with("zoom="):
				_main.camera_rig.zoom_by(float(arg.get_slice("=", 1)))
		var inspect := _option("inspect")
		if inspect >= 0 and inspect < _main.people.people.size():
			_main.debug_overlay.visible = true
			_main.inspector.select(_main.people.people[inspect])
	if _frames < FRAMES_TO_WAIT:
		return false
	var path: String = args[0] if args.size() > 0 else "user://screenshot.png"
	root.get_texture().get_image().save_png(path)
	print("Saved ", path)
	return true


## The number after "name=" in the arguments, or -1.
func _option(name: String) -> int:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with(name + "="):
			return int(arg.get_slice("=", 1))
	return -1
