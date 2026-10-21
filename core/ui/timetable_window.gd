class_name TimetableWindow
extends PanelContainer
## The regime: one day of the week in half hours, in lanes. The timetable
## lane is painted with blocks, like Prison Architect's regime: pick a
## block from the swatches, then click or drag across it. With a Regime,
## lanes below show the sessions placed into the blocks (drag to move,
## which pins them; click or right-click to pin or unpin), the staff rota,
## and the prison's operations (drag each within its shaded window), with
## the week's clashes listed underneath. With a runner and categories, a
## category can be given its own timetable (and merged back). Toggle with T.

## Width of one half hour.
const SLOT_WIDTH := 20.0
## The lane names' column.
const LABEL_WIDTH := 150.0
const RULER := 18.0
const TIMETABLE_HEIGHT := 40.0
const SESSION_HEIGHT := 26.0
const ROTA_HEIGHT := 18.0
const OPERATION_HEIGHT := 20.0
const LANE_GAP := 10.0
## Clashes listed before "and N more".
const CLASHES_SHOWN := 6
const INK := Color(0.18, 0.2, 0.22)

var schedule: Schedule
## The blocks the player can paint with, in swatch order.
var activities: Array[ActivityDef] = []
var clock: GameClock
## Shown in the heading, such as "Prisoners".
var group_name := "Prisoners"
## Optional: for category timetables.
var runner: ScheduleRunner
var categories: Array[CategoryDef] = []
## Optional: sessions, rota, operations and clashes.
var regime: Regime:
	set(value):
		regime = value
		regime.changed.connect(_redraw)
## The timetable being painted, as a runner key.
var key: StringName = &""
## The day shown, 0 for Monday.
var day := 0
## Painting changes the same half hour of every day, not just this one.
var every_day := true

var _picked: ActivityDef
var _lanes := Lanes.new()
var _note := Label.new()
var _who := Label.new()
var _pick_timetable := OptionButton.new()
var _split := MenuButton.new()
var _merge := Button.new()
var _days: Array[Button] = []
var _every_day := CheckButton.new()
var _offers := HFlowContainer.new()
var _clash_box := VBoxContainer.new()


## The lanes for one day, drawn and dragged on.
class Lanes:
	extends Control

	var window: TimetableWindow
	var _painting := false
	## What's being dragged: a Regime.Placement, or [operation id, index].
	var _dragging: Variant = null
	var _drag_from := Vector2.ZERO
	var _drag_slot := 0
	## Placements drawn this frame, with their rects, for hit tests.
	var _session_rects: Array = []
	var _operation_rects: Array = []

	func _ready() -> void:
		tooltip_text = " "

	func lane_tops() -> Dictionary:
		var top := TimetableWindow.RULER
		var out := {&"timetable": top}
		top += TimetableWindow.TIMETABLE_HEIGHT + TimetableWindow.LANE_GAP
		if window.regime == null:
			out[&"end"] = top
			return out
		out[&"sessions"] = top
		top += maxi(_session_rows(), 1) * TimetableWindow.SESSION_HEIGHT + TimetableWindow.LANE_GAP
		out[&"rota"] = top
		top += maxi(_rota().size(), 1) * TimetableWindow.ROTA_HEIGHT + TimetableWindow.LANE_GAP
		out[&"operations"] = top
		top += window.regime.operations.size() * TimetableWindow.OPERATION_HEIGHT
		out[&"end"] = top
		return out

	func wanted_height() -> float:
		return lane_tops()[&"end"] + 4.0

	func slot_at(x: float) -> int:
		return clampi(floori((x - TimetableWindow.LABEL_WIDTH) / TimetableWindow.SLOT_WIDTH), 0, Schedule.SLOTS_PER_DAY - 1)

	func _gui_input(event: InputEvent) -> void:
		var button := event as InputEventMouseButton
		if button != null and button.button_index == MOUSE_BUTTON_RIGHT and button.pressed:
			var placed: Variant = _thing_at(button.position)
			if placed is Regime.Placement:
				window.regime.pin(placed, not placed.pinned)
			accept_event()
			return
		if button != null and button.button_index == MOUSE_BUTTON_LEFT:
			if button.pressed:
				var tops := lane_tops()
				if button.position.y < tops[&"timetable"] + TimetableWindow.TIMETABLE_HEIGHT:
					_painting = true
					_paint(button.position)
				else:
					_dragging = _thing_at(button.position)
					_drag_from = button.position
					_drag_slot = slot_at(button.position.x)
			else:
				_painting = false
				if _dragging != null:
					_drop(button.position)
				_dragging = null
				queue_redraw()
			accept_event()
		var motion := event as InputEventMouseMotion
		if motion != null:
			if _painting:
				_paint(motion.position)
			elif _dragging != null:
				_drag_slot = slot_at(motion.position.x)
				queue_redraw()
			accept_event()

	func _drop(at: Vector2) -> void:
		var moved := slot_at(at.x) - slot_at(_drag_from.x)
		if _dragging is Regime.Placement:
			var placed: Regime.Placement = _dragging
			if moved == 0 and at.distance_to(_drag_from) < 4.0:
				window.regime.pin(placed, not placed.pinned)
			elif not window.regime.move(placed, placed.slot + moved):
				Sound.play(&"build_error")
		elif _dragging is Array:
			var id: StringName = _dragging[0]
			var index: int = _dragging[1]
			if moved != 0 and not window.regime.set_time(id, index, window.regime.slot_of(id, index) + moved):
				Sound.play(&"build_error")

	func _paint(at: Vector2) -> void:
		window.paint_slot(slot_at(at.x))

	## The session or operation time under a point.
	func _thing_at(at: Vector2) -> Variant:
		for entry: Array in _session_rects:
			if (entry[1] as Rect2).has_point(at):
				return entry[0]
		for entry: Array in _operation_rects:
			if (entry[2] as Rect2).grow(3).has_point(at):
				var op: OperationDef = window.regime.operation(entry[0])
				return null if op.fixed else [entry[0], entry[1]]
		return null

	func _get_tooltip(at: Vector2) -> String:
		var slot := slot_at(at.x)
		var tops := lane_tops()
		if at.y < tops[&"timetable"] + TimetableWindow.TIMETABLE_HEIGHT:
			var def := window.schedule.at_slot(window.day * Schedule.SLOTS_PER_DAY + slot)
			return "%s %s: %s" % [Schedule.slot_text(slot), def.display_name, def.description] if def != null else ""
		for entry: Array in _session_rects:
			if (entry[1] as Rect2).has_point(at):
				var placed: Regime.Placement = entry[0]
				return "%s, %s to %s. %s\nDrag to move it; click to %s it." % [placed.session.display_name,
						Schedule.slot_text(placed.slot), Schedule.slot_text(placed.slot + placed.session.length),
						"Pinned here." if placed.pinned else "Placed by the regime.", "unpin" if placed.pinned else "pin"]
		for entry: Array in _operation_rects:
			if (entry[2] as Rect2).grow(3).has_point(at):
				var op: OperationDef = window.regime.operation(entry[0])
				var when := Schedule.slot_text(window.regime.slot_of(op.id, entry[1]))
				if op.fixed:
					return "%s at %s. %s\n%s" % [op.display_name, when, op.description, op.fixed_reason]
				return "%s at %s. %s\nDrag between %s and %s." % [op.display_name, when, op.description,
						Schedule.slot_text(op.earliest), Schedule.slot_text(op.latest)]
		return ""

	func _session_rows() -> int:
		var rows := 0
		for row: Array in _placed_rows():
			rows = maxi(rows, row[1] + 1)
		return rows

	## Today's placements with the row each sits in: [Placement, row].
	func _placed_rows() -> Array:
		var out: Array = []
		var ends: Array[int] = []
		for placed in window.regime.placements:
			var start := placed.slot - window.day * Schedule.SLOTS_PER_DAY
			if start < 0 or start >= Schedule.SLOTS_PER_DAY:
				continue
			var row := 0
			while row < ends.size() and ends[row] > start:
				row += 1
			if row == ends.size():
				ends.append(0)
			ends[row] = start + placed.session.length
			out.append([placed, row])
		return out

	func _rota() -> Array:
		return window.regime.rota.call() if window.regime.rota.is_valid() else []

	func _draw() -> void:
		var font := get_theme_font(&"font", &"Label")
		var ink := get_theme_color(&"font_color", &"Label")
		var faint := Color(ink, 0.55)
		var left := TimetableWindow.LABEL_WIDTH
		var w := TimetableWindow.SLOT_WIDTH
		var tops := lane_tops()
		var now := -1
		if window.clock != null and Schedule.weekday_of(window.clock.total_minutes) == window.day:
			now = Schedule.slot_of(window.clock.total_minutes) % Schedule.SLOTS_PER_DAY
		# The hours along the top, and faint lines down every lane.
		for hour in Schedule.HOURS:
			var x := left + hour * 2 * w
			draw_string(font, Vector2(x + 2, 12), "%02d" % hour, HORIZONTAL_ALIGNMENT_LEFT, -1, 11,
					Color(ink, 1.0 if now / 2 == hour else 0.6))
			draw_line(Vector2(x, RULER_LINE), Vector2(x, tops[&"end"]), Color(ink, 0.08), 1.0)

		_lane_label(font, faint, tops[&"timetable"], TimetableWindow.TIMETABLE_HEIGHT, "Timetable")
		var base := window.day * Schedule.SLOTS_PER_DAY
		for i in Schedule.SLOTS_PER_DAY:
			var def := window.schedule.at_slot(base + i)
			var rect := Rect2(left + i * w, tops[&"timetable"], w, TimetableWindow.TIMETABLE_HEIGHT)
			var colour := def.colour if def != null else Color(0.8, 0.8, 0.8)
			var starts := i == 0 or window.schedule.at_slot(base + i - 1) != def
			var ends := i == Schedule.SLOTS_PER_DAY - 1 or window.schedule.at_slot(base + i + 1) != def
			draw_style_box(_box(colour, starts, ends), Rect2(rect.position + Vector2(1 if starts else 0, 0),
					rect.size - Vector2((1 if starts else 0) + (1 if ends else 0), 0)))
		# Names on top, once the boxes they run across are drawn.
		for i in Schedule.SLOTS_PER_DAY:
			var def := window.schedule.at_slot(base + i)
			var rect := Rect2(left + i * w, tops[&"timetable"], w, TimetableWindow.TIMETABLE_HEIGHT)
			if def != null and (i == 0 or window.schedule.at_slot(base + i - 1) != def):
				var label := def.short_name if not def.short_name.is_empty() else def.display_name
				var run := 1
				while i + run < Schedule.SLOTS_PER_DAY and window.schedule.at_slot(base + i + run) == def:
					run += 1
				draw_string(font, rect.position + Vector2(5, rect.size.y * 0.5 + 5), label,
						HORIZONTAL_ALIGNMENT_LEFT, run * w - 8, 12, TimetableWindow.INK)
		if now >= 0:
			var x := left + (now + fmod(window.clock.total_minutes, Schedule.SLOT_MINUTES) / Schedule.SLOT_MINUTES) * w
			draw_line(Vector2(x, RULER_LINE), Vector2(x, tops[&"end"]), ink, 2.0)

		if window.regime == null:
			return
		var clashing := {}
		for clash: Array in window.regime.clashes():
			clashing[clash[0]] = true

		_lane_label(font, faint, tops[&"sessions"], TimetableWindow.SESSION_HEIGHT, "Sessions")
		if window.regime.placements.is_empty():
			draw_string(font, Vector2(left + 5, tops[&"sessions"] + 16), "No sessions placed: see the clashes below.",
					HORIZONTAL_ALIGNMENT_LEFT, -1, 11, faint)
		_session_rects.clear()
		for entry: Array in _placed_rows():
			var placed: Regime.Placement = entry[0]
			var start: int = placed.slot - base
			if _dragging == placed:
				start += _drag_slot - slot_at(_drag_from.x)
			var rect := Rect2(left + start * w + 1, tops[&"sessions"] + entry[1] * TimetableWindow.SESSION_HEIGHT + 1,
					placed.session.length * w - 2, TimetableWindow.SESSION_HEIGHT - 4)
			var box := _box(Color(0.93, 0.89, 0.8), true, true)
			if placed.pinned:
				box.set_border_width_all(2)
				box.border_color = TimetableWindow.INK
			if clashing.has(placed.slot):
				box.bg_color = Color(0.96, 0.75, 0.7)
			draw_style_box(box, rect)
			draw_string(font, rect.position + Vector2(5, 15), placed.session.display_name,
					HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 8, 11, TimetableWindow.INK)
			_session_rects.append([placed, rect])

		_lane_label(font, faint, tops[&"rota"], TimetableWindow.ROTA_HEIGHT, "Rota")
		var rota := _rota()
		if rota.is_empty():
			draw_string(font, Vector2(left + 5, tops[&"rota"] + 13), "Nobody on the staff rota yet: hire staff on the Staff page.",
					HORIZONTAL_ALIGNMENT_LEFT, -1, 11, faint)
		for i in rota.size():
			var row: Array = rota[i]
			var y: float = tops[&"rota"] + i * TimetableWindow.ROTA_HEIGHT
			var first: int = row[1]
			var length: int = row[2]
			for part in [[first, mini(length, Schedule.SLOTS_PER_DAY - first)], [0, first + length - Schedule.SLOTS_PER_DAY]]:
				if part[1] <= 0:
					continue
				var rect := Rect2(left + part[0] * w + 1, y + 2, part[1] * w - 2, TimetableWindow.ROTA_HEIGHT - 4)
				draw_style_box(_box(Color(0.72, 0.8, 0.86), true, true), rect)
			draw_string(font, Vector2(left + first * w + 5, y + 13), row[0], HORIZONTAL_ALIGNMENT_LEFT,
					mini(length, Schedule.SLOTS_PER_DAY - first) * w - 8, 11, TimetableWindow.INK)

		_operation_rects.clear()
		for i in window.regime.operations.size():
			var op := window.regime.operations[i]
			var y: float = tops[&"operations"] + i * TimetableWindow.OPERATION_HEIGHT
			draw_string(font, Vector2(4, y + 14), op.display_name, HORIZONTAL_ALIGNMENT_LEFT,
					TimetableWindow.LABEL_WIDTH - 8, 11, faint)
			if not op.fixed:
				var lo := op.earliest
				var hi := mini(op.latest, Schedule.SLOTS_PER_DAY - 1)
				draw_rect(Rect2(left + lo * w, y + 3, (hi - lo + 1) * w, TimetableWindow.OPERATION_HEIGHT - 6),
						Color(ink, 0.07))
			var list: Array = window.regime.times.get(op.id, op.times)
			for index in list.size():
				var slot: int = list[index]
				if _dragging is Array and _dragging[0] == op.id and _dragging[1] == index:
					slot = clampi(slot + _drag_slot - slot_at(_drag_from.x), op.earliest, op.latest)
				var rect := Rect2(left + slot * w + 2, y + 2, w - 4, TimetableWindow.OPERATION_HEIGHT - 4)
				var colour := Color(0.62, 0.62, 0.6) if op.fixed else Color(0.95, 0.72, 0.4)
				if clashing.has(base + slot) or clashing.has(slot):
					colour = Color(0.88, 0.45, 0.4)
				draw_style_box(_box(colour, true, true), rect)
				_operation_rects.append([op.id, index, rect])

	const RULER_LINE := 16.0

	func _lane_label(font: Font, colour: Color, top: float, height: float, text: String) -> void:
		draw_string(font, Vector2(4, top + minf(height, 26.0) * 0.5 + 5), text, HORIZONTAL_ALIGNMENT_LEFT,
				TimetableWindow.LABEL_WIDTH - 8, 13, colour)

	func _box(colour: Color, round_left: bool, round_right: bool) -> StyleBoxFlat:
		var box := StyleBoxFlat.new()
		box.bg_color = colour
		box.corner_radius_top_left = 6 if round_left else 0
		box.corner_radius_bottom_left = 6 if round_left else 0
		box.corner_radius_top_right = 6 if round_right else 0
		box.corner_radius_bottom_right = 6 if round_right else 0
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
	title.text = "Regime" if regime != null else "Timetable"
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
	box.add_child(_day_row())

	var swatches := HFlowContainer.new()
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
			swatch.add_theme_color_override(state, INK)
		swatch.toggled.connect(func(on: bool) -> void:
			if on:
				_pick(def))
		swatches.add_child(swatch)
		if _picked == null:
			swatch.button_pressed = true
	box.add_child(swatches)

	_lanes.window = self
	_lanes.mouse_default_cursor_shape = CURSOR_POINTING_HAND
	box.add_child(_lanes)
	_note.theme_type_variation = &"SubtleLabel"
	_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_note)
	if regime != null:
		var offers_title := Label.new()
		offers_title.text = "Sessions a week"
		box.add_child(offers_title)
		_offers.add_theme_constant_override(&"h_separation", 14)
		box.add_child(_offers)
		_build_offers()
		box.add_child(_clash_box)
	if not activities.is_empty():
		_pick(activities[0])
	if clock != null:
		clock.half_hour_changed.connect(func(_slot: int) -> void: _redraw())
		clock.minute_passed.connect(func(_minute: int) -> void:
			if visible:
				_lanes.queue_redraw())
	_lanes.custom_minimum_size = Vector2(LABEL_WIDTH + SLOT_WIDTH * Schedule.SLOTS_PER_DAY, _lanes.wanted_height())
	visible = false


func toggle() -> void:
	visible = not visible
	refresh()


func refresh() -> void:
	_refresh_timetables()
	_redraw()


## Shows another day of the week, 0 for Monday.
func show_day(to: int) -> void:
	day = posmod(to, Schedule.DAYS)
	for i in _days.size():
		_days[i].set_pressed_no_signal(i == day)
	_redraw()


func _day_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 4)
	var group := ButtonGroup.new()
	for i in Schedule.DAYS:
		var button := Button.new()
		button.text = Schedule.DAY_NAMES[i].left(3)
		button.toggle_mode = true
		button.button_group = group
		button.focus_mode = FOCUS_NONE
		button.button_pressed = i == day
		button.pressed.connect(show_day.bind(i))
		row.add_child(button)
		_days.append(button)
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(12, 0)
	row.add_child(spacer)
	_every_day.text = "Paint every day"
	_every_day.focus_mode = FOCUS_NONE
	_every_day.button_pressed = every_day
	_every_day.tooltip_text = "On, painting changes the same time on all seven days. Off, only the day shown."
	_every_day.toggled.connect(func(on: bool) -> void:
		every_day = on
		_pick(_picked))
	row.add_child(_every_day)
	return row


## A number box per session: how many times a week it runs.
func _build_offers() -> void:
	for child in _offers.get_children():
		child.queue_free()
	for def in regime.sessions:
		var cell := HBoxContainer.new()
		var name_label := Label.new()
		name_label.text = def.display_name
		cell.add_child(name_label)
		var count := SpinBox.new()
		count.min_value = 0
		count.max_value = 14
		count.value = regime.offered.get(def.id, def.per_week)
		count.focus_mode = FOCUS_NONE
		count.get_line_edit().focus_mode = FOCUS_CLICK
		count.value_changed.connect(func(value: float) -> void: regime.set_offered(def.id, int(value)))
		cell.add_child(count)
		_offers.add_child(cell)


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
	_redraw()


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


## Paints a whole hour of the day shown (or every day) with the picked block.
func paint(hour: int) -> void:
	paint_slot(hour * 2)
	paint_slot(hour * 2 + 1)


## Paints a half hour of the day shown (or every day) with the picked block.
func paint_slot(slot: int) -> void:
	if _picked == null:
		return
	schedule.set_slot(day * Schedule.SLOTS_PER_DAY + slot, _picked, every_day)
	_redraw()


## Lanes and the clash list again, after anything changed.
func _redraw() -> void:
	if not is_node_ready():
		return
	_lanes.custom_minimum_size.y = _lanes.wanted_height()
	_lanes.queue_redraw()
	if regime == null or not visible:
		return
	for child in _clash_box.get_children():
		child.queue_free()
	var clashes := regime.clashes()
	if clashes.is_empty():
		return
	var title := Label.new()
	title.text = "Clashes (%d)" % clashes.size()
	_clash_box.add_child(title)
	for i in mini(clashes.size(), CLASHES_SHOWN):
		var clash: Array = clashes[i]
		var line := Button.new()
		line.flat = true
		line.focus_mode = FOCUS_NONE
		line.alignment = HORIZONTAL_ALIGNMENT_LEFT
		var slot: int = clash[0]
		var at := "%s %s · " % [Schedule.DAY_NAMES[slot / Schedule.SLOTS_PER_DAY].left(3), Schedule.slot_text(slot)] if slot >= 0 else ""
		line.text = at + String(clash[1])
		line.pressed.connect(show_day.bind(maxi(slot, 0) / Schedule.SLOTS_PER_DAY))
		_clash_box.add_child(line)
	if clashes.size() > CLASHES_SHOWN:
		var more := Label.new()
		more.theme_type_variation = &"SubtleLabel"
		more.text = "and %d more" % (clashes.size() - CLASHES_SHOWN)
		_clash_box.add_child(more)


func _pick(def: ActivityDef) -> void:
	_picked = def
	if def == null:
		return
	_note.text = "Painting %s on %s: %s" % [def.display_name,
			"every day" if every_day else Schedule.DAY_NAMES[day], def.description]


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
		box.border_color = INK
	return box
