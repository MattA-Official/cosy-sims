class_name PrisonerFileCard
extends PanelContainer
## A prisoner's paper file, opened from the inspector: their face, what
## they're in for, how far through their time they are, the traits found so
## far (the rest show as "?"), a reform bar and their history.

var people: People
var sentences: Sentences
var reform: Reform
var clock: GameClock
## Who the file is open on, or null.
var person: Person

var _column: VBoxContainer


func _ready() -> void:
	set_anchors_and_offsets_preset(PRESET_CENTER)
	grow_horizontal = GROW_DIRECTION_BOTH
	grow_vertical = GROW_DIRECTION_BOTH
	custom_minimum_size = Vector2(420, 0)
	var paper := StyleBoxFlat.new()
	paper.bg_color = Color(0.93, 0.86, 0.68)
	paper.border_color = Color(0.78, 0.68, 0.48)
	paper.set_border_width_all(2)
	paper.set_corner_radius_all(6)
	paper.set_content_margin_all(18)
	add_theme_stylebox_override(&"panel", paper)
	visible = false
	_column = VBoxContainer.new()
	_column.add_theme_constant_override(&"separation", 8)
	add_child(_column)


func show_for(who: Person) -> void:
	person = who
	refresh()
	show()
	move_to_front()


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("build_cancel"):
		hide()
		get_viewport().set_input_as_handled()


func refresh() -> void:
	for child in _column.get_children():
		child.queue_free()
	if person == null:
		return
	var file := PrisonerFile.of(person)
	var top := HBoxContainer.new()
	top.add_theme_constant_override(&"separation", 10)
	var face := TextureRect.new()
	face.custom_minimum_size = Vector2(48, 48)
	face.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	face.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	face.texture = people.face_textures[people.face(person)] if people != null else null
	top.add_child(face)
	var heading := VBoxContainer.new()
	heading.size_flags_horizontal = SIZE_EXPAND_FILL
	heading.add_child(_label(person.name, &"HeaderLabel"))
	heading.add_child(_label("%s category" % String(person.category).capitalize() if person.category != &"" else "Prisoner", &"SubtleLabel"))
	top.add_child(heading)
	var close := Button.new()
	close.text = "Close"
	close.theme_type_variation = &"FlatButton"
	close.focus_mode = FOCUS_NONE
	close.pressed.connect(hide)
	close.size_flags_vertical = SIZE_SHRINK_BEGIN
	top.add_child(close)
	_column.add_child(top)
	if person.profile.get("file_missing", false):
		_column.add_child(_label("Awaiting paperwork", &"HeaderLabel"))
		return
	_row("Offence", file.offence_words())
	if sentences != null and file.has_sentence():
		_row("Sentence", sentences.summary(person))
	var traits := PackedStringArray()
	for def in person.traits:
		traits.append(def.display_name if file.knows_trait(def.id) else "?")
	_row("Traits", ", ".join(traits) if not traits.is_empty() else "None")
	if reform != null:
		var bar := ProgressBar.new()
		bar.max_value = 100.0
		bar.value = reform.value(person)
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(0, 12)
		bar.size_flags_horizontal = SIZE_EXPAND_FILL
		bar.tooltip_text = reform.summary(person)
		var line := HBoxContainer.new()
		line.add_child(_label("Reform", &"TitleLabel"))
		line.add_child(bar)
		_column.add_child(line)
	if not file.passed.is_empty():
		_row("Passed", ", ".join(file.passed.map(func(id: StringName) -> String: return String(id).capitalize())))
	_column.add_child(_label("HISTORY", &"TitleLabel"))
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 160)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var lines := VBoxContainer.new()
	lines.size_flags_horizontal = SIZE_EXPAND_FILL
	var history := file.log.duplicate()
	history.reverse()
	for entry: Array in history:
		var text := _label("Day %d  %s" % [entry[0], entry[1]])
		text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lines.add_child(text)
	scroll.add_child(lines)
	_column.add_child(scroll)


func _row(title: String, words: String) -> void:
	var line := HBoxContainer.new()
	line.add_theme_constant_override(&"separation", 10)
	var name_label := _label(title, &"TitleLabel")
	name_label.custom_minimum_size = Vector2(80, 0)
	line.add_child(name_label)
	var value := _label(words)
	value.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	value.size_flags_horizontal = SIZE_EXPAND_FILL
	line.add_child(value)
	_column.add_child(line)


func _label(text: String, variation: StringName = &"") -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override(&"font_color", Color(0.25, 0.2, 0.15))
	if variation != &"":
		label.theme_type_variation = variation
	else:
		label.add_theme_font_size_override(&"font_size", 14)
	return label
