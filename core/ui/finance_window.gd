class_name FinanceWindow
extends PanelContainer
## The prison's money: the balance, a chart of the last week's closing
## balances, and what came in and went out today and yesterday, line by
## line. A sandbox switch gives unlimited money. Toggle with M.

## Seconds between showing the lines again while open.
const REFRESH_SECONDS := 0.5
const CHART_HEIGHT := 90.0

var ledger: Ledger

var _balance := Label.new()
var _state := Label.new()
var _sandbox := CheckButton.new()
var _chart := BalanceChart.new()
var _today := GridContainer.new()
var _yesterday := GridContainer.new()
var _wait := 0.0


## Bars for the closing balances, today's last; below zero in red.
class BalanceChart:
	extends Control

	var values: Array[int] = []
	var labels: Array[String] = []

	func _draw() -> void:
		if values.is_empty():
			return
		var top := maxi(values.max(), 0)
		var bottom := mini(values.min(), 0)
		var span := maxf(top - bottom, 1.0)
		var zero := size.y * top / span
		var gap := 6.0
		var width := (size.x - gap * (values.size() - 1)) / values.size()
		var font := get_theme_default_font()
		for i in values.size():
			var height := size.y * values[i] / span
			var x := i * (width + gap)
			var colour := Color(0.45, 0.68, 0.55) if values[i] >= 0 else Color(0.85, 0.45, 0.42)
			if i == values.size() - 1:
				colour = colour.lightened(0.25)
			draw_rect(Rect2(x, minf(zero, zero - height), width, maxf(absf(height), 1.0)), colour)
			if i < labels.size():
				draw_string(font, Vector2(x, size.y + 14), labels[i], HORIZONTAL_ALIGNMENT_CENTER, width, 11,
						Color(0.45, 0.45, 0.45))
		draw_line(Vector2(0, zero), Vector2(size.x, zero), Color(0.5, 0.5, 0.5, 0.6), 1.0)


func _ready() -> void:
	set_anchors_and_offsets_preset(PRESET_CENTER_TOP, PRESET_MODE_MINSIZE)
	grow_horizontal = GROW_DIRECTION_BOTH
	offset_top = 76.0
	custom_minimum_size = Vector2(440, 0)
	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", 8)
	add_child(box)

	var heading := HBoxContainer.new()
	var title := Label.new()
	title.text = "Money"
	title.theme_type_variation = &"HeaderLabel"
	heading.add_child(title)
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

	var row := HBoxContainer.new()
	_balance.theme_type_variation = &"HeaderLabel"
	_balance.add_theme_font_size_override(&"font_size", 26)
	row.add_child(_balance)
	_state.theme_type_variation = &"SubtleLabel"
	_state.size_flags_vertical = SIZE_SHRINK_CENTER
	_state.size_flags_horizontal = SIZE_EXPAND_FILL
	_state.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(_state)
	box.add_child(row)

	_chart.custom_minimum_size = Vector2(0, CHART_HEIGHT)
	box.add_child(_chart)
	box.add_child(Control.new())

	var columns := HBoxContainer.new()
	columns.add_theme_constant_override(&"separation", 24)
	columns.add_child(_column("Today", _today))
	columns.add_child(_column("Yesterday", _yesterday))
	box.add_child(columns)

	_sandbox.text = "Sandbox: unlimited money"
	_sandbox.tooltip_text = "Build and hire whatever the balance. Money is still counted."
	_sandbox.focus_mode = FOCUS_NONE
	_sandbox.toggled.connect(func(on: bool) -> void:
		ledger.sandbox = on
		refresh())
	box.add_child(_sandbox)
	visible = false
	refresh()


func _process(delta: float) -> void:
	if not visible:
		return
	_wait -= delta
	if _wait <= 0.0:
		_wait = REFRESH_SECONDS
		refresh()


func toggle() -> void:
	visible = not visible
	refresh()


func refresh() -> void:
	if ledger == null:
		return
	_balance.text = Ledger.text(ledger.balance)
	_sandbox.set_pressed_no_signal(ledger.sandbox)
	if ledger.sandbox:
		_state.text = "Sandbox: spend freely."
	elif ledger.balance < 0:
		_state.text = "In debt: no building or hiring until the balance is back above zero."
	else:
		_state.text = ""
	var values: Array[int] = ledger.closing.duplicate()
	values.append(ledger.balance)
	var labels: Array[String] = []
	for i in values.size():
		var ago := values.size() - 1 - i
		labels.append("Now" if ago == 0 else "-%dd" % ago)
	_chart.values = values
	_chart.labels = labels
	_chart.queue_redraw()
	_fill(_today, ledger.today)
	_fill(_yesterday, ledger.yesterday)


func _column(text: String, grid: GridContainer) -> VBoxContainer:
	var column := VBoxContainer.new()
	column.size_flags_horizontal = SIZE_EXPAND_FILL
	var label := Label.new()
	label.text = text
	label.theme_type_variation = &"HeaderLabel"
	column.add_child(label)
	grid.columns = 2
	grid.add_theme_constant_override(&"h_separation", 16)
	column.add_child(grid)
	return column


## Lists lines with money in first, then a total.
func _fill(grid: GridContainer, lines: Dictionary[String, int]) -> void:
	for child in grid.get_children():
		grid.remove_child(child)
		child.queue_free()
	var names: Array = lines.keys()
	names.sort_custom(func(a: String, b: String) -> bool: return lines[a] > lines[b])
	for line: String in names:
		_add_line(grid, line, lines[line], false)
	if names.is_empty():
		_add_line(grid, "Nothing yet", 0, false)
	else:
		_add_line(grid, "Total", Ledger.total(lines), true)


func _add_line(grid: GridContainer, text: String, amount: int, bold: bool) -> void:
	var name_label := Label.new()
	name_label.text = text
	name_label.size_flags_horizontal = SIZE_EXPAND_FILL
	var amount_label := Label.new()
	amount_label.text = ("+" if amount > 0 else "") + Ledger.text(amount) if text != "Nothing yet" else ""
	amount_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	if amount < 0:
		amount_label.add_theme_color_override(&"font_color", Color(0.75, 0.35, 0.32))
	if bold:
		name_label.theme_type_variation = &"HeaderLabel"
		amount_label.theme_type_variation = &"HeaderLabel"
	grid.add_child(name_label)
	grid.add_child(amount_label)
