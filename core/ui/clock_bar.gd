class_name ClockBar
extends PanelContainer
## The clock in the top-left corner: the day, the time, the timetable
## block everyone is in, buttons for the speed (Space pauses, , and . go
## slower and faster), the balance, which opens the money page (M), and
## counts of the regime's clashes and the in-tray's letters when there are
## any, and any warnings counting towards losing, which open their pages.
## The other management windows live in the ManagementBook below it.

signal money_pressed
signal clashes_pressed
signal tray_pressed
signal warnings_pressed

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
## The prison's money, shown as a balance. Optional.
var ledger: Ledger
## For the clash count. Optional.
var regime: Regime
## For the count of cards waiting. Optional.
var in_tray: InTray
## () -> Array of warning lines, such as the Ministry counting nights in
## debt. Optional.
var warnings: Callable

var _day := Label.new()
var _time := Label.new()
var _block := Label.new()
var _chip := PanelContainer.new()
var _chip_box := StyleBoxFlat.new()
var _speeds: Array[CosyButton] = []
var _money: Button
var _clashes := Button.new()
var _tray := Button.new()
var _warnings := Button.new()


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

	if regime != null:
		_clashes.theme_type_variation = &"DangerButton"
		_clashes.focus_mode = FOCUS_NONE
		_clashes.size_flags_vertical = SIZE_SHRINK_CENTER
		_clashes.tooltip_text = "Things in the regime that don't add up. Opens the regime. T"
		_clashes.pressed.connect(clashes_pressed.emit)
		row.add_child(_clashes)
		regime.changed.connect(count_clashes)
		clock.hour_changed.connect(func(_hour: int) -> void: count_clashes())
		count_clashes()
	if in_tray != null:
		_tray.theme_type_variation = &"FlatButton"
		_tray.focus_mode = FOCUS_NONE
		_tray.size_flags_vertical = SIZE_SHRINK_CENTER
		_tray.tooltip_text = "Cards waiting in the in-tray. J"
		_tray.pressed.connect(tray_pressed.emit)
		row.add_child(_tray)
		in_tray.changed.connect(count_cards)
		count_cards()
	if warnings.is_valid():
		_warnings.theme_type_variation = &"DangerButton"
		_warnings.focus_mode = FOCUS_NONE
		_warnings.size_flags_vertical = SIZE_SHRINK_CENTER
		_warnings.pressed.connect(warnings_pressed.emit)
		row.add_child(_warnings)
		clock.hour_changed.connect(func(_hour: int) -> void: count_warnings())
		count_warnings()
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


## Counts the cards in the in-tray again.
func count_cards() -> void:
	var count := in_tray.cards.filter(func(c: InTray.Card) -> bool: return c.queued < 0).size()
	_tray.visible = count > 0
	_tray.text = "%d letter%s" % [count, "" if count == 1 else "s"]


## Counts the warnings again.
func count_warnings() -> void:
	var lines: Array = warnings.call()
	_warnings.visible = not lines.is_empty()
	_warnings.text = "%d warning%s" % [lines.size(), "" if lines.size() == 1 else "s"]
	_warnings.tooltip_text = "\n".join(lines)


## Counts the regime's clashes again.
func count_clashes() -> void:
	var count := regime.clashes().size() if regime != null else 0
	_clashes.visible = count > 0
	_clashes.text = "%d clash%s" % [count, "" if count == 1 else "es"]


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
