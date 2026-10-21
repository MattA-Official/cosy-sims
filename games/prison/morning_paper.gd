class_name MorningPaper
extends PanelContainer
## The local paper, out at 06:00: a masthead, yesterday's biggest news as
## the headline, the day under a few headings in two columns, and one
## prisoner's story at the foot. Opened from the morning's toast.

const MASTHEAD := "The Morning Report"

var _column: VBoxContainer


func _ready() -> void:
	set_anchors_and_offsets_preset(PRESET_CENTER)
	grow_horizontal = GROW_DIRECTION_BOTH
	grow_vertical = GROW_DIRECTION_BOTH
	custom_minimum_size = Vector2(560, 0)
	var newsprint := StyleBoxFlat.new()
	newsprint.bg_color = Color(0.95, 0.93, 0.87)
	newsprint.border_color = Color(0.7, 0.67, 0.6)
	newsprint.set_border_width_all(1)
	newsprint.set_corner_radius_all(3)
	newsprint.set_content_margin_all(20)
	newsprint.shadow_color = Color(0, 0, 0, 0.25)
	newsprint.shadow_size = 6
	add_theme_stylebox_override(&"panel", newsprint)
	visible = false
	_column = VBoxContainer.new()
	_column.add_theme_constant_override(&"separation", 8)
	add_child(_column)


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("build_cancel"):
		hide()
		get_viewport().set_input_as_handled()


func show_paper(paper: Dictionary) -> void:
	if paper.is_empty():
		return
	for child in _column.get_children():
		child.queue_free()
	var ink := Color(0.15, 0.14, 0.12)
	var faded := Color(0.4, 0.38, 0.34)
	var masthead := _label(paper.get("name", "") if not String(paper.get("name", "")).is_empty() else MASTHEAD, 30, ink)
	masthead.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_column.add_child(masthead)
	var dateline := _label("Day %d   ·   %s" % [paper.day, "★".repeat(paper.stars) + "☆".repeat(5 - paper.stars)], 13, faded)
	dateline.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_column.add_child(dateline)
	_column.add_child(_rule(ink))
	_column.add_child(_label(paper.headline, 22, ink))
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override(&"separation", 18)
	_column.add_child(columns)
	var sides: Array[VBoxContainer] = [VBoxContainer.new(), VBoxContainer.new()]
	for side in sides:
		side.size_flags_horizontal = SIZE_EXPAND_FILL
		side.add_theme_constant_override(&"separation", 4)
		columns.add_child(side)
	var sections: Array = paper.sections
	for i in sections.size():
		var side := sides[0 if i < ceili(sections.size() / 2.0) else 1]
		side.add_child(_label(String(sections[i][0]).to_upper(), 12, faded))
		for line: String in sections[i][1]:
			var body := _label(line, 14, ink)
			body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			side.add_child(body)
		side.add_child(Control.new())
	if not String(paper.story).is_empty():
		_column.add_child(_rule(faded))
		var story := _label(paper.story, 15, ink)
		story.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_column.add_child(story)
	var close := Button.new()
	close.text = "Fold it up"
	close.size_flags_horizontal = SIZE_SHRINK_END
	close.focus_mode = FOCUS_NONE
	close.pressed.connect(hide)
	_column.add_child(close)
	show()
	move_to_front()


func _label(text: String, size: int, colour: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override(&"font_size", size)
	label.add_theme_color_override(&"font_color", colour)
	return label


func _rule(colour: Color) -> ColorRect:
	var rule := ColorRect.new()
	rule.color = colour
	rule.custom_minimum_size = Vector2(0, 2)
	return rule
