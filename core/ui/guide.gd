class_name Guide
extends PanelContainer
## Teaching the player, in a card down the right-hand side under the status
## bar. Two ways:
## - Steps: a guided run of things to do in order (the tutorial's first
##   day). Each step says what to do, rings the button to press, and ticks
##   itself off when its check passes.
## - Tips: a short card the first time something comes up (a tool, a
##   page), once on this computer, unless tips are switched off.
## Tips wait while steps are running.

signal steps_finished
## The player chose to stop the steps early.
signal steps_skipped

const SEEN := "user://guide.cfg"
## Seconds between checking whether the current step is done.
const CHECK := 0.3
const WIDTH := 300.0


## One thing to do in the steps.
class Step:
	var title: String
	var words: String
	## () -> bool: whether it's done.
	var done: Callable
	## () -> Control: the button to ring, or null.
	var target: Callable

	static func make(step_title: String, step_words: String, check: Callable, ring := Callable()) -> Step:
		var step := Step.new()
		step.title = step_title
		step.words = step_words
		step.done = check
		step.target = ring
		return step


var steps: Array[Step] = []
var current := -1
## Whether first-time tips show. Kept on this computer.
var tips_on := true:
	set(value):
		tips_on = value
		_save()
		if not tips_on and _tip_id != &"":
			_hide_tip()
## Where tips are remembered; tests point it elsewhere.
var seen_path := SEEN
## What the last card said, for tests.
var shown_title := ""
## Words for the last button of the steps, and what it does. Optional.
var finish_label := ""
var finish_pressed: Callable

var _seen: Dictionary[StringName, bool] = {}
var _tip_id: StringName = &""
var _queue: Array = []
var _box := VBoxContainer.new()
var _heading := Label.new()
var _title := Label.new()
var _words := Label.new()
var _buttons := HBoxContainer.new()
var _ring := _Ring.new()
var _wait := 0.0


## Rings a control: a soft pulsing outline drawn over everything.
class _Ring extends Control:
	var target: Control
	var _time := 0.0

	func _ready() -> void:
		mouse_filter = MOUSE_FILTER_IGNORE
		set_anchors_preset(PRESET_FULL_RECT)

	func _process(delta: float) -> void:
		_time += delta
		queue_redraw()

	func _draw() -> void:
		if target == null or not is_instance_valid(target) or not target.is_visible_in_tree():
			return
		var rect := target.get_global_rect()
		rect.position -= get_global_rect().position
		var pulse := 0.5 + 0.5 * sin(_time * 5.0)
		var grow := 4.0 + pulse * 4.0
		var colour := Color(1.0, 0.72, 0.25, 0.55 + 0.45 * pulse)
		draw_style_box(_outline(colour), rect.grow(grow))

	func _outline(colour: Color) -> StyleBoxFlat:
		var box := StyleBoxFlat.new()
		box.draw_center = false
		box.border_color = colour
		box.set_border_width_all(3)
		box.set_corner_radius_all(10)
		return box


func _ready() -> void:
	_load()
	set_anchors_and_offsets_preset(PRESET_TOP_RIGHT, PRESET_MODE_MINSIZE, 12)
	offset_top = 110.0
	offset_left = -12.0 - WIDTH
	offset_right = -12.0
	custom_minimum_size.x = WIDTH
	grow_horizontal = GROW_DIRECTION_BEGIN
	theme_type_variation = &"ToastPanel"
	_box.add_theme_constant_override(&"separation", 6)
	_heading.theme_type_variation = &"SubtleLabel"
	_title.theme_type_variation = &"HeaderLabel"
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_words.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_buttons.alignment = BoxContainer.ALIGNMENT_END
	for child: Control in [_heading, _title, _words, _buttons]:
		_box.add_child(child)
	add_child(_box)
	visible = false
	# The ring sits on its own layer over the whole HUD.
	var layer := CanvasLayer.new()
	layer.layer = 50
	layer.add_child(_ring)
	add_child(layer)


func _process(delta: float) -> void:
	if current < 0 or current >= steps.size():
		return
	_wait -= delta
	if _wait > 0.0:
		return
	_wait = CHECK
	var step := steps[current]
	if step.target.is_valid():
		_ring.target = step.target.call()
	if step.done.is_valid() and step.done.call():
		advance()


## Starts a run of steps from the first, or from `from`.
func start_steps(list: Array[Step], from := 0) -> void:
	steps = list
	current = from - 1
	_hide_tip()
	advance()


func running() -> bool:
	return current >= 0 and current < steps.size()


## On to the next step, or the end.
func advance() -> void:
	current += 1
	_ring.target = null
	_clear_buttons()
	if current >= steps.size():
		_show_end()
		return
	var step := steps[current]
	_show("Step %d of %d" % [current + 1, steps.size()], step.title, step.words)
	_button("Skip tutorial", func() -> void:
		current = steps.size()
		_ring.target = null
		visible = false
		steps_skipped.emit())
	_ring.target = step.target.call() if step.target.is_valid() else null
	_wait = CHECK


func _show_end() -> void:
	current = steps.size()
	_show("All done", "That's the basics", "You've built a working prison. The F1 help card has every control, and tips will pop up as new things come along.")
	if not finish_label.is_empty() and finish_pressed.is_valid():
		_button(finish_label, func() -> void:
			visible = false
			finish_pressed.call())
	_button("Keep building", func() -> void: visible = false)
	steps_finished.emit()


## Shows a tip the first time `id` comes up, unless tips are off or the
## steps are running. Returns whether it showed.
func tip(id: StringName, title: String, words: String) -> bool:
	if not tips_on or _seen.has(id) or running():
		return false
	if _tip_id != &"":
		if not _queue.any(func(entry: Array) -> bool: return entry[0] == id):
			_queue.append([id, title, words])
		return false
	_seen[id] = true
	_save()
	_tip_id = id
	_clear_buttons()
	_show("Tip", title, words)
	_button("No more tips", func() -> void: tips_on = false)
	_button("Got it", _hide_tip)
	return true


func has_seen(id: StringName) -> bool:
	return _seen.has(id)


## Forgets which tips have been seen, so they show again.
func reset_tips() -> void:
	_seen.clear()
	_save()


func _hide_tip() -> void:
	_tip_id = &""
	if not running():
		visible = false
	while not _queue.is_empty():
		var next: Array = _queue.pop_front()
		if tip(next[0], next[1], next[2]):
			break


func _show(heading: String, title: String, words: String) -> void:
	_heading.text = heading
	_title.text = title
	_words.text = words
	shown_title = title
	visible = true


func _clear_buttons() -> void:
	for child in _buttons.get_children():
		_buttons.remove_child(child)
		child.queue_free()


func _button(text: String, pressed: Callable) -> void:
	var button := Button.new()
	button.text = text
	button.focus_mode = FOCUS_NONE
	button.theme_type_variation = &"FlatButton" if _buttons.get_child_count() == 0 else &"AccentButton"
	button.pressed.connect(pressed)
	_buttons.add_child(button)


func _load() -> void:
	var file := ConfigFile.new()
	if file.load(seen_path) != OK:
		return
	for id: String in file.get_value("guide", "seen", []):
		_seen[StringName(id)] = true
	tips_on = file.get_value("guide", "tips", true)


func _save() -> void:
	if not is_inside_tree():
		return
	var file := ConfigFile.new()
	file.set_value("guide", "tips", tips_on)
	file.set_value("guide", "seen", _seen.keys().map(func(id: StringName) -> String: return String(id)))
	file.save(seen_path)
