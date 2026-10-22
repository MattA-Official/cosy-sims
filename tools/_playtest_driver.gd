extends SceneTree
## Interactive driver for playtesting: polls a command file and feeds input.
## Scratch tool for playtesting; see the playtesting notes.

const DIR := "/tmp/claude-0/pt/"
var _queue: Array = []
var _wait := 0
var _seq := 0
var _hold: Dictionary = {}


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(DIR + "shots")
	var start := "res://games/prison/title.tscn"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("scene="):
			start = a.get_slice("=", 1)
	change_scene_to_file(start)


func _process(_delta: float) -> bool:
	if _wait > 0:
		_wait -= 1
		return false
	if _queue.is_empty():
		if FileAccess.file_exists(DIR + "cmd.txt"):
			var text := FileAccess.get_file_as_string(DIR + "cmd.txt")
			DirAccess.remove_absolute(DIR + "cmd.txt")
			for line in text.split("\n"):
				if line.strip_edges() != "":
					_queue.append(line.strip_edges())
			_queue.append("__done")
		return false
	var item = _queue.pop_front()
	if item is Array:
		match item[0]:
			"__up":
				_mouse(item[1], item[2], false)
				_wait = 3
			"__mv":
				_motion(item[1], item[2])
				_wait = 1
			"__kup":
				_key(item[1], false)
				_wait = 2
		return false
	_run(item)
	return false


func _log(s: String) -> void:
	var f := FileAccess.open(DIR + "out.txt", FileAccess.READ_WRITE if FileAccess.file_exists(DIR + "out.txt") else FileAccess.WRITE)
	f.seek_end()
	f.store_line(s)
	f.close()


func _mouse(pos: Vector2, button: int, pressed: bool) -> void:
	var e := InputEventMouseButton.new()
	e.position = pos
	e.global_position = pos
	e.button_index = button
	e.pressed = pressed
	e.button_mask = (1 << (button - 1)) if pressed else 0
	for k in _hold:
		_apply_mod(e, k)
	Input.parse_input_event(e)


func _motion(pos: Vector2, mask: int) -> void:
	Input.warp_mouse(pos)
	var e := InputEventMouseMotion.new()
	e.position = pos
	e.global_position = pos
	e.button_mask = mask
	for k in _hold:
		_apply_mod(e, k)
	Input.parse_input_event(e)


func _apply_mod(e: InputEventWithModifiers, k: String) -> void:
	match k:
		"shift": e.shift_pressed = true
		"ctrl": e.ctrl_pressed = true
		"alt": e.alt_pressed = true


func _key(name: String, pressed: bool) -> void:
	var e := InputEventKey.new()
	var code := OS.find_keycode_from_string(name)
	e.keycode = code
	e.physical_keycode = code
	e.pressed = pressed
	if name.length() == 1:
		e.unicode = name.to_lower().unicode_at(0)
	for k in _hold:
		_apply_mod(e, k)
	Input.parse_input_event(e)


func _run(line: String) -> void:
	var p := line.split(" ", false)
	var c := p[0]
	match c:
		"__done":
			_log("== done")
			var f := FileAccess.open(DIR + "done.txt", FileAccess.WRITE)
			f.store_string(str(_seq))
			_seq += 1
		"move":
			_motion(Vector2(float(p[1]), float(p[2])), 0)
			_wait = 2
		"click", "rclick":
			var b := MOUSE_BUTTON_LEFT if c == "click" else MOUSE_BUTTON_RIGHT
			var pos := Vector2(float(p[1]), float(p[2]))
			_queue.push_front(["__up", pos, b])
			_motion(pos, 0)
			_mouse(pos, b, true)
			_wait = 2
		"wheel":
			var pos := Vector2(float(p[1]), float(p[2]))
			var b := MOUSE_BUTTON_WHEEL_UP if int(p[3]) > 0 else MOUSE_BUTTON_WHEEL_DOWN
			for i in absi(int(p[3])):
				_mouse(pos, b, true)
				_mouse(pos, b, false)
			_wait = 2
		"drag":
			var a := Vector2(float(p[1]), float(p[2]))
			var z := Vector2(float(p[3]), float(p[4]))
			_motion(a, 0)
			_mouse(a, MOUSE_BUTTON_LEFT, true)
			var steps := 8
			var cmds: Array = []
			for i in range(1, steps + 1):
				cmds.append(["__mv", a.lerp(z, float(i) / steps), 1])
			cmds.append(["__up", z, MOUSE_BUTTON_LEFT])
			for i in range(cmds.size() - 1, -1, -1):
				_queue.push_front(cmds[i])
			_wait = 2
		"down":
			var pos := Vector2(float(p[1]), float(p[2]))
			_motion(pos, 0)
			_mouse(pos, MOUSE_BUTTON_LEFT, true)
			_wait = 2
		"up":
			var pos := Vector2(float(p[1]), float(p[2]))
			_mouse(pos, MOUSE_BUTTON_LEFT, false)
			_wait = 2
		"drawto":
			var pos := Vector2(float(p[1]), float(p[2]))
			_motion(pos, 1)
			_wait = 2
		"hold":
			_hold[p[1]] = true
			_key(p[1].capitalize() if p[1] != "ctrl" else "Ctrl", true)
		"release":
			_hold.erase(p[1])
			_key(p[1].capitalize() if p[1] != "ctrl" else "Ctrl", false)
		"key":
			_key(p[1], true)
			_queue.push_front(["__kup", p[1]])
			_wait = 1
		"keydown":
			_key(p[1], true)
		"keyup":
			_key(p[1], false)
		"wait":
			_wait = int(p[1])
		"shot":
			var img := root.get_texture().get_image()
			img.save_png(DIR + "shots/" + p[1] + ".png")
			_log("shot " + p[1])
		"eval":
			var src := line.substr(5)
			var ex := Expression.new()
			var err := ex.parse(src, ["tree", "main"])
			if err != OK:
				_log("parse error: " + ex.get_error_text())
				return
			var r = ex.execute([self, current_scene], self)
			if ex.has_execute_failed():
				_log("exec error: " + ex.get_error_text())
			else:
				_log("=> " + str(r))
		"gd":
			var body := line.substr(3).replace("\\n", "\n\t")
			var scr := GDScript.new()
			scr.source_code = "extends RefCounted\nfunc run(main):\n\t" + body + "\n"
			if scr.reload() != OK:
				_log("gd compile error")
				return
			var obj = scr.new()
			_log("=> " + str(obj.run(current_scene)))
		"fps":
			_log("fps " + str(Engine.get_frames_per_second()))
		"advance":
			# Fast-forward N game minutes (like leaving it on fastest).
			var clock = current_scene.clock
			var target: float = clock.total_minutes + float(p[1])
			var budget := 30
			while clock.total_minutes < target and budget > 0:
				clock.advance(minf(0.5, target - clock.total_minutes))
				budget -= 1
			if clock.total_minutes < target - 0.01:
				_queue.push_front("advance " + str(target - clock.total_minutes))
			_wait = 1
		_:
			_log("unknown " + line)


func _run_arr(a: Array) -> void:
	pass


func _notification(what: int) -> void:
	pass
