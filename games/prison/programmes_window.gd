class_name ProgrammesWindow
extends PanelContainer
## Courses and therapy: one row per course with how many places it has,
## who's on it and who's waiting, and what's stopping it if it can't run.
## Above them, how reformed the prison is. Work programmes stay in the
## Staff window. Toggle with L.

const REFRESH_SECONDS := 0.5

var courses: Courses
var reform: Reform

var _summary := Label.new()
var _rows: Dictionary[StringName, Array] = {}
var _wait := 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(PRESET_CENTER_TOP, PRESET_MODE_MINSIZE)
	grow_horizontal = GROW_DIRECTION_BOTH
	offset_top = 76.0
	custom_minimum_size = Vector2(520, 0)
	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", 8)
	add_child(box)

	var heading := HBoxContainer.new()
	var title := Label.new()
	title.text = "Programmes"
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
	_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_summary.theme_type_variation = &"SubtleLabel"
	box.add_child(_summary)
	box.add_child(HSeparator.new())

	var places_heading := HBoxContainer.new()
	var courses_label := Label.new()
	courses_label.text = "Courses"
	courses_label.theme_type_variation = &"HeaderLabel"
	courses_label.size_flags_horizontal = SIZE_EXPAND_FILL
	places_heading.add_child(courses_label)
	var places_label := Label.new()
	places_label.text = "Places"
	places_label.theme_type_variation = &"SubtleLabel"
	places_label.custom_minimum_size = Vector2(104, 0)
	places_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	places_heading.add_child(places_label)
	box.add_child(places_heading)
	for def in courses.defs:
		box.add_child(_course_row(def))
	var hint := Label.new()
	hint.text = "Classes run in Learn blocks on the timetable. Places fill with the least reformed first."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.theme_type_variation = &"SubtleLabel"
	box.add_child(hint)
	visible = false


func _course_row(def: CourseDef) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 8)
	row.tooltip_text = "%s\n%d sessions, then an exam." % [def.description, def.sessions]
	var words := VBoxContainer.new()
	words.size_flags_horizontal = SIZE_EXPAND_FILL
	words.add_theme_constant_override(&"separation", 0)
	var name_label := Label.new()
	name_label.text = def.display_name
	name_label.mouse_filter = MOUSE_FILTER_PASS
	words.add_child(name_label)
	var state := Label.new()
	state.theme_type_variation = &"SubtleLabel"
	state.mouse_filter = MOUSE_FILTER_PASS
	words.add_child(state)
	row.add_child(words)
	var minus := Button.new()
	minus.text = "−"
	minus.focus_mode = FOCUS_NONE
	minus.custom_minimum_size = Vector2(32, 0)
	minus.pressed.connect(func() -> void:
		courses.set_places(def.id, courses.places.get(def.id, 0) - 1)
		refresh())
	row.add_child(minus)
	var count := Label.new()
	count.custom_minimum_size = Vector2(28, 0)
	count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(count)
	var plus := Button.new()
	plus.text = "+"
	plus.focus_mode = FOCUS_NONE
	plus.custom_minimum_size = Vector2(32, 0)
	plus.pressed.connect(func() -> void:
		courses.set_places(def.id, courses.places.get(def.id, 0) + 1)
		refresh())
	row.add_child(plus)
	_rows[def.id] = [state, count]
	return row


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
	if courses == null:
		return
	_summary.text = summary()
	for def in courses.defs:
		var row: Array = _rows[def.id]
		(row[0] as Label).text = state_text(def)
		(row[1] as Label).text = str(courses.places.get(def.id, 0))


## Average reform and how many are over the line.
func summary() -> String:
	if reform == null:
		return ""
	return "Average reform %d · %d%% reformed (%d or more)" % [roundi(reform.average()),
			roundi(reform.share_reformed() * 100.0), roundi(Reform.REFORMED_LINE)]


## "4 on it, 6 waiting · No teacher on shift"
func state_text(def: CourseDef) -> String:
	var on := courses.enrolled(def.id).size()
	var waiting := courses.waiting(def.id).size()
	var words := "%d on it, %d waiting" % [on, waiting]
	var problem := courses.problem(def)
	if not problem.is_empty() and problem != "No places set":
		words += " · " + problem
	return words
