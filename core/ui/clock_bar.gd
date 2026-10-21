class_name ClockBar
extends PanelContainer
## The clock in the top-left corner: the day, the time, the timetable
## block everyone is in, and buttons for the speed (Space pauses, , and .
## go slower and faster), the timetable window (T), the staff window (P),
## the office (O), security (K), programmes (L), always-day light, and the balance, which opens the money window (M).

signal timetable_pressed
signal staff_pressed
signal money_pressed
signal office_pressed
signal security_pressed
signal programmes_pressed

const ICONS := "res://core/ui/icons/%s.svg"
const SPEED_ICONS: Array[String] = ["speed_pause", "speed_1", "speed_2", "speed_3"]
const SPEED_NAMES: Array[String] = ["Pause", "Normal speed", "Fast", "Fastest"]
const SPEED_DETAILS: Array[String] = [
	"Stops the clock. You can still build. Space",
	"A game minute a second, a day in 24 minutes.",
	"Twice as fast.",
	"Four times as fast: a day in 6 minutes.",
]

var clock: GameClock
var runner: ScheduleRunner
var day_night: DayNight
## The prison's money, shown as a balance. Optional.
var ledger: Ledger

var _day := Label.new()
var _time := Label.new()
var _block := Label.new()
var _chip := PanelContainer.new()
var _chip_box := StyleBoxFlat.new()
var _speeds: Array[CosyButton] = []
var _timetable: CosyButton
var _money: Button


func _ready() -> void:
	theme_type_variation = &"HudBar"
	set_anchors_and_offsets_preset(PRESET_TOP_LEFT, PRESET_MODE_MINSIZE, 12)
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 6)
	add_child(row)

	var when := VBoxContainer.new()
	when.add_theme_constant_override(&"separation", -4)
	_time.theme_type_variation = &"HeaderLabel"
	_time.add_theme_font_size_override(&"font_size", 22)
	_time.custom_minimum_size.x = 64
	when.add_child(_time)
	_day.theme_type_variation = &"SubtleLabel"
	when.add_child(_day)
	row.add_child(when)

	_chip_box.set_corner_radius_all(9)
	_chip_box.content_margin_left = 10
	_chip_box.content_margin_right = 10
	_chip_box.content_margin_top = 3
	_chip_box.content_margin_bottom = 3
	_chip.add_theme_stylebox_override(&"panel", _chip_box)
	_chip.size_flags_vertical = SIZE_SHRINK_CENTER
	_chip.mouse_filter = MOUSE_FILTER_PASS
	_block.add_theme_font_size_override(&"font_size", 15)
	_block.add_theme_color_override(&"font_color", Color(0.18, 0.2, 0.22))
	_chip.add_child(_block)
	row.add_child(_chip)
	row.add_child(VSeparator.new())

	var group := ButtonGroup.new()
	for i in GameClock.SPEEDS.size():
		var button := _button(SPEED_NAMES[i], SPEED_DETAILS[i], SPEED_ICONS[i])
		button.button_group = group
		button.toggled.connect(func(on: bool) -> void:
			if on:
				clock.speed_index = i)
		row.add_child(button)
		_speeds.append(button)
	row.add_child(VSeparator.new())

	_timetable = _button("Timetable", "Who should be where, hour by hour. T", "timetable")
	_timetable.toggle_mode = false
	_timetable.pressed.connect(timetable_pressed.emit)
	row.add_child(_timetable)
	var staff := _button("Staff", "Who works here, and work programmes. P", "staff")
	staff.toggle_mode = false
	staff.pressed.connect(staff_pressed.emit)
	row.add_child(staff)
	var office := _button("Office", "The warden's office: intake, goals and the grade. O", "office")
	office.toggle_mode = false
	office.pressed.connect(office_pressed.emit)
	row.add_child(office)
	var security := _button("Security", "Cameras, incidents, alerts and the Safety grade. K", "security")
	security.toggle_mode = false
	security.pressed.connect(security_pressed.emit)
	row.add_child(security)
	var programmes := _button("Programmes", "Courses, therapy, parole and how reformed everyone is. L", "programmes")
	programmes.toggle_mode = false
	programmes.pressed.connect(programmes_pressed.emit)
	row.add_child(programmes)
	var sun := _button("Always day", "Keeps the light bright while you build, whatever the time.",
			"always_day")
	sun.toggled.connect(func(on: bool) -> void:
		if day_night != null:
			day_night.always_day = on)
	row.add_child(sun)
	if ledger != null:
		row.add_child(VSeparator.new())
		_money = Button.new()
		_money.icon = load(ICONS % "money")
		_money.expand_icon = false
		_money.add_theme_constant_override(&"icon_max_width", 22)
		_money.theme_type_variation = &"FlatButton"
		_money.focus_mode = FOCUS_NONE
		_money.tooltip_text = "Money: what comes in and goes out. M"
		_money.pressed.connect(money_pressed.emit)
		row.add_child(_money)
		var ink := get_theme_color(&"font_color", &"Label")
		for state in [&"icon_normal_color", &"icon_hover_color", &"icon_pressed_color",
				&"icon_hover_pressed_color", &"icon_focus_color"]:
			_money.add_theme_color_override(state, ink)

	clock.speed_changed.connect(func(_index: int) -> void: _show_speed())
	_show_speed()
	_refresh()


func _process(_delta: float) -> void:
	_refresh()


func _refresh() -> void:
	if _money != null:
		var balance := "Sandbox" if ledger.sandbox else Ledger.text(ledger.balance)
		if _money.text != balance:
			_money.text = balance
			if ledger.balance < 0 and not ledger.sandbox:
				_money.add_theme_color_override(&"font_color", Color(0.75, 0.3, 0.28))
			else:
				_money.remove_theme_color_override(&"font_color")
	var time := clock.time_text()
	if _time.text != time:
		_time.text = time
		_day.text = "Day %d · %s" % [clock.day(), clock.weekday()]
	var def := runner.current() if runner != null else null
	_chip.visible = def != null
	if def != null and _block.text != def.display_name:
		_block.text = def.display_name
		_chip_box.bg_color = def.colour
		_chip.tooltip_text = def.description


func _show_speed() -> void:
	for i in _speeds.size():
		_speeds[i].set_pressed_no_signal(i == clock.speed_index)


func _button(title: String, details: String, icon_name: String) -> CosyButton:
	var button := CosyButton.new()
	button.title = title
	button.details = details
	button.icon = load(ICONS % icon_name)
	button.theme_type_variation = &"ModeButton"
	button.toggle_mode = true
	button.focus_mode = FOCUS_NONE
	button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	button.custom_minimum_size = Vector2(34, 34)
	return button
