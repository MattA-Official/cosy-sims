class_name HelpCard
extends PanelContainer
## A card in the middle of the screen listing every control, toggled with F1
## or the view bar's help button. The game fills it with `sections`: each is
## [heading, [[keys, what they do], ...]]. Keys are split on " / " and each
## drawn as a keycap.

var sections: Array = []


func _ready() -> void:
	set_anchors_and_offsets_preset(PRESET_CENTER)
	grow_horizontal = GROW_DIRECTION_BOTH
	grow_vertical = GROW_DIRECTION_BOTH
	visible = false
	var column := VBoxContainer.new()
	column.add_theme_constant_override(&"separation", 10)
	add_child(column)
	var top := HBoxContainer.new()
	var title := Label.new()
	title.text = "Controls"
	title.theme_type_variation = &"HeaderLabel"
	title.size_flags_horizontal = SIZE_EXPAND_FILL
	top.add_child(title)
	var close := Button.new()
	close.text = "Close"
	close.theme_type_variation = &"FlatButton"
	close.focus_mode = FOCUS_NONE
	close.pressed.connect(hide)
	top.add_child(close)
	column.add_child(top)
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override(&"separation", 28)
	column.add_child(columns)
	for section: Array in sections:
		var block := VBoxContainer.new()
		var heading := Label.new()
		heading.text = String(section[0]).to_upper()
		heading.theme_type_variation = &"TitleLabel"
		block.add_child(heading)
		var grid := GridContainer.new()
		grid.columns = 2
		grid.add_theme_constant_override(&"h_separation", 12)
		grid.add_theme_constant_override(&"v_separation", 6)
		for entry: Array in section[1]:
			grid.add_child(_keys(entry[0]))
			var what := Label.new()
			what.text = entry[1]
			what.add_theme_font_size_override(&"font_size", 14)
			grid.add_child(what)
		block.add_child(grid)
		columns.add_child(block)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("help_toggle"):
		visible = not visible
		get_viewport().set_input_as_handled()
	elif visible and event.is_action_pressed("build_cancel"):
		hide()
		get_viewport().set_input_as_handled()


func _keys(text: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 3)
	for key in text.split(" / "):
		var cap := Label.new()
		cap.text = key
		cap.theme_type_variation = &"KeyLabel"
		cap.size_flags_vertical = SIZE_SHRINK_CENTER
		row.add_child(cap)
	return row
