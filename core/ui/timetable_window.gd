class_name TimetableWindow
extends PanelContainer
## The timetable: a strip of 24 hours, each painted with a block. Pick a
## block from the row of swatches, then click or drag across hours to paint
## it, like Prison Architect's regime. With a runner and categories, a
## category can be given its own timetable (and merged back), picked from
## a menu. Toggle with T.

const HOUR_WIDTH := 40.0
const STRIP_HEIGHT := 46.0

var schedule: Schedule
## The blocks the player can paint with, in swatch order.
var activities: Array[ActivityDef] = []
var clock: GameClock
## Shown in the heading, such as "Prisoners".
var group_name := "Prisoners"
## Optional: for category timetables.
var runner: ScheduleRunner
var categories: Array[CategoryDef] = []
## The timetable being painted, as a runner key.
var key: StringName = &""

var _picked: ActivityDef
var _strip := HourStrip.new()
var _note := Label.new()
var _who := Label.new()
var _pick_timetable := OptionButton.new()
var _split := MenuButton.new()
var _merge := Button.new()


## The 24 hours, drawn and painted on.
class HourStrip:
	extends Control

	var window: TimetableWindow
	var _painting := false

	func _gui_input(event: InputEvent) -> void:
		var button := event as InputEventMouseButton
		if button != null and button.button_index == MOUSE_BUTTON_LEFT:
			_painting = button.pressed
			if button.pressed:
				_paint(button.position)
			accept_event()
		var motion := event as InputEventMouseMotion
		if motion != null and _painting:
			_paint(motion.position)
			accept_event()

	func _paint(at: Vector2) -> void:
		var hour := clampi(floori(at.x / TimetableWindow.HOUR_WIDTH), 0, Schedule.HOURS - 1)
		window.paint(hour)

	func _draw() -> void:
		var font := get_theme_font(&"font", &"Label")
		var ink := get_theme_color(&"font_color", &"Label")
		var top := 18.0
		var now := window.clock.hour() if window.clock != null else -1
		for hour in Schedule.HOURS:
			var x := hour * TimetableWindow.HOUR_WIDTH
			var def := window.schedule.at(hour)
			var text := "%02d" % hour
			var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
			draw_string(font, Vector2(x + (TimetableWindow.HOUR_WIDTH - width) * 0.5, 12), text,
					HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(ink, 0.6 if hour != now else 1.0))
			var rect := Rect2(x + 1, top, TimetableWindow.HOUR_WIDTH - 2, TimetableWindow.STRIP_HEIGHT)
			var colour := def.colour if def != null else Color(0.8, 0.8, 0.8)
			draw_style_box(_cell_box(colour), rect)
			if def != null and window.schedule.at(hour - 1) != def:
				var label := def.short_name if not def.short_name.is_empty() else def.display_name
				draw_string(font, rect.position + Vector2(4, rect.size.y * 0.5 + 5), label,
						HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.18, 0.2, 0.22))
			if hour == now:
				var marker := StyleBoxFlat.new()
				marker.draw_center = false
				marker.set_border_width_all(3)
				marker.border_color = ink
				marker.set_corner_radius_all(7)
				draw_style_box(marker, rect.grow(2))

	func _cell_box(colour: Color) -> StyleBoxFlat:
		var box := StyleBoxFlat.new()
		box.bg_color = colour
		box.set_corner_radius_all(6)
		return box


func _ready() -> void:
	set_anchors_and_offsets_preset(PRESET_CENTER_TOP, PRESET_MODE_MINSIZE)
	grow_horizontal = GROW_DIRECTION_BOTH
	offset_top = 76.0
	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", 10)
	add_child(box)

	var heading := HBoxContainer.new()
	var title := Label.new()
	title.text = "Timetable"
	title.theme_type_variation = &"HeaderLabel"
	heading.add_child(title)
	_who.text = group_name
	_who.theme_type_variation = &"SubtleLabel"
	_who.size_flags_vertical = SIZE_SHRINK_CENTER
	heading.add_child(_who)
	var spacer := Control.new()
	spacer.size_flags_horizontal = SIZE_EXPAND_FILL
	heading.add_child(spacer)
	var close := Button.new()
	close.text = "Close"
	close.theme_type_variation = &"FlatButton"
	close.focus_mode = FOCUS_NONE
	close.pressed.connect(hide)
	heading.add_child(close)
	box.add_child(heading)
	if runner != null and not categories.is_empty():
		box.add_child(_category_row())

	var swatches := HBoxContainer.new()
	var group := ButtonGroup.new()
	for def in activities:
		var swatch := Button.new()
		swatch.text = def.display_name
		swatch.toggle_mode = true
		swatch.button_group = group
		swatch.focus_mode = FOCUS_NONE
		swatch.tooltip_text = def.description
		for state: StringName in [&"normal", &"hover", &"pressed", &"hover_pressed"]:
			swatch.add_theme_stylebox_override(state, _swatch_box(def.colour,
					state == &"pressed" or state == &"hover_pressed", state.begins_with("hover")))
		for state: StringName in [&"font_color", &"font_hover_color", &"font_pressed_color",
				&"font_hover_pressed_color"]:
			swatch.add_theme_color_override(state, Color(0.18, 0.2, 0.22))
		swatch.toggled.connect(func(on: bool) -> void:
			if on:
				_pick(def))
		swatches.add_child(swatch)
		if _picked == null:
			swatch.button_pressed = true
	box.add_child(swatches)

	_strip.window = self
	_strip.custom_minimum_size = Vector2(HOUR_WIDTH * Schedule.HOURS, STRIP_HEIGHT + 20)
	_strip.mouse_default_cursor_shape = CURSOR_POINTING_HAND
	box.add_child(_strip)
	_note.theme_type_variation = &"SubtleLabel"
	box.add_child(_note)
	if not activities.is_empty():
		_pick(activities[0])
	if clock != null:
		clock.hour_changed.connect(func(_hour: int) -> void: _strip.queue_redraw())
	visible = false


func toggle() -> void:
	visible = not visible
	_refresh_timetables()
	_strip.queue_redraw()


## Which timetable to paint, and splitting a category off or merging it back.
func _category_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 8)
	_pick_timetable.focus_mode = FOCUS_NONE
	_pick_timetable.tooltip_text = "Which timetable you're painting."
	_pick_timetable.item_selected.connect(func(index: int) -> void:
		show_timetable(StringName(_pick_timetable.get_item_metadata(index))))
	row.add_child(_pick_timetable)
	_split.text = "Separate timetable for…"
	_split.flat = false
	_split.focus_mode = FOCUS_NONE
	_split.tooltip_text = "Gives a security category its own timetable, starting as a copy of everyone's."
	_split.get_popup().id_pressed.connect(func(id: int) -> void:
		var def := categories[id]
		runner.split(schedule.group, def.id)
		show_timetable(ScheduleRunner.category_key(schedule.group, def.id)))
	row.add_child(_split)
	_merge.text = "Merge back"
	_merge.focus_mode = FOCUS_NONE
	_merge.tooltip_text = "This category goes back to everyone's timetable."
	_merge.pressed.connect(func() -> void:
		var group := schedule.group
		runner.merge(key)
		show_timetable(group))
	row.add_child(_merge)
	return row


## Switches to painting another timetable, by runner key.
func show_timetable(to: StringName) -> void:
	if runner == null or not runner.schedules.has(to):
		return
	key = to
	schedule = runner.schedules[to]
	_refresh_timetables()
	_strip.queue_redraw()


## The name of a timetable, such as "Everyone" or "High security".
func timetable_name(of: StringName) -> String:
	var parts := String(of).split("/")
	if parts.size() < 2:
		return "Everyone"
	for def in categories:
		if def.id == StringName(parts[1]):
			return def.display_name
	return parts[1].capitalize()


func _refresh_timetables() -> void:
	if runner == null or categories.is_empty() or schedule == null:
		return
	var group := schedule.group
	if key == &"":
		key = group
	_pick_timetable.clear()
	var keys: Array[StringName] = [group]
	for def in categories:
		var category_key := ScheduleRunner.category_key(group, def.id)
		if runner.schedules.has(category_key):
			keys.append(category_key)
	for i in keys.size():
		_pick_timetable.add_item(timetable_name(keys[i]))
		_pick_timetable.set_item_metadata(i, keys[i])
		if keys[i] == key:
			_pick_timetable.select(i)
	var popup := _split.get_popup()
	popup.clear()
	for i in categories.size():
		if not runner.schedules.has(ScheduleRunner.category_key(group, categories[i].id)):
			popup.add_item(categories[i].display_name, i)
	_split.disabled = popup.item_count == 0
	_merge.visible = key != group
	_who.text = group_name if key == group else "%s: %s only" % [group_name, timetable_name(key)]


## Paints an hour with the picked block.
func paint(hour: int) -> void:
	if _picked == null:
		return
	schedule.set_hour(hour, _picked)
	_strip.queue_redraw()


func _pick(def: ActivityDef) -> void:
	_picked = def
	_note.text = "Painting %s: %s Click or drag across the hours." % [def.display_name, def.description]


func _swatch_box(colour: Color, picked: bool, hover: bool) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = colour.lightened(0.12) if hover else colour
	box.set_corner_radius_all(9)
	box.content_margin_left = 12
	box.content_margin_right = 12
	box.content_margin_top = 5
	box.content_margin_bottom = 5
	if picked:
		box.set_border_width_all(3)
		box.border_color = Color(0.18, 0.2, 0.22)
	return box
