class_name ProgrammesWindow
extends PanelContainer
## Reform and release. How reformed the prison is; courses and therapy,
## one row per course with how many places it has, who's on it and who's
## waiting, and what's stopping it if it can't run; then today's parole
## list, with a chance for each and a box to hold someone back. Work
## programmes stay in the Staff window. Last, who went home this week and
## the latest postcards. Toggle with L.

const REFRESH_SECONDS := 0.5

var courses: Courses
var reform: Reform
var parole: Parole
var release: Release

var _summary := Label.new()
var _rows: Dictionary[StringName, Array] = {}
var _wait := 0.0
var _parole_words := Label.new()
var _parole_rows := VBoxContainer.new()
var _shown_parole: Array = []
var _release_words := Label.new()


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
	if parole != null:
		box.add_child(HSeparator.new())
		var parole_heading := Label.new()
		parole_heading.text = "Parole"
		parole_heading.theme_type_variation = &"HeaderLabel"
		box.add_child(parole_heading)
		_parole_words.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_parole_words.theme_type_variation = &"SubtleLabel"
		box.add_child(_parole_words)
		_parole_rows.add_theme_constant_override(&"separation", 2)
		box.add_child(_parole_rows)
	if release != null:
		box.add_child(HSeparator.new())
		var release_heading := Label.new()
		release_heading.text = "Gone home"
		release_heading.theme_type_variation = &"HeaderLabel"
		box.add_child(release_heading)
		_release_words.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(_release_words)
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
	if parole != null:
		_parole_words.text = parole_text()
		_show_parole()
	if release != null:
		_release_words.text = release_text()


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


## "This week: 9 went home, 5 reformed, 2 came back", and the last
## postcards.
func release_text() -> String:
	var week := release.week()
	var lines := PackedStringArray(["This week: %d went home, %d reformed, %d came back." % [week.left,
			week.reformed, week.back]])
	if release.due().size() > 0:
		lines.append("%d due to go home." % release.due().size())
	for card in release.postcards.slice(0, 3):
		lines.append("Day %d, from %s: \"%s\"" % [card.day, card.from, card.text])
	if release.postcards.is_empty():
		lines.append("No postcards yet. Reformed leavers sometimes write.")
	return "\n".join(lines)


## When hearings are, and how yesterday's went.
func parole_text() -> String:
	var words := "The warden hears up to %d cases from %02d:00, most reformed first." % [Parole.HEARINGS_PER_DAY,
			Parole.HEARING_HOUR]
	var results: Array = parole.today if not parole.today.is_empty() else parole.yesterday
	if not results.is_empty():
		var granted := results.filter(func(entry: Array) -> bool: return entry[1]).size()
		words += " %s: %d heard, %d granted." % ["Today" if results == parole.today else "Yesterday",
				results.size(), granted]
	return words


## Who could go before a hearing next, with their chance and a hold back
## box: today's list once it's drawn up, else everyone eligible.
func _show_parole() -> void:
	var list: Array[Person] = []
	if not parole.queue.is_empty():
		list = parole.queue.duplicate()
	else:
		for person in courses.people.people:
			if person.group == parole.prisoner_group and PrisonerFile.of(person).has_sentence() \
					and (parole.eligible(person) or person.profile.get("parole_held_back", false)):
				list.append(person)
		list.sort_custom(func(a: Person, b: Person) -> bool: return reform.value(a) > reform.value(b))
		list = list.slice(0, 6)
	var key: Array = list.map(func(p: Person) -> Array:
		return [p.id, roundi(parole.chance(p)[0] * 100.0), p.profile.get("parole_held_back", false)])
	if key == _shown_parole:
		return
	_shown_parole = key
	for child in _parole_rows.get_children():
		_parole_rows.remove_child(child)
		child.queue_free()
	if list.is_empty():
		var none := Label.new()
		none.text = "Nobody is due a hearing yet."
		none.theme_type_variation = &"SubtleLabel"
		_parole_rows.add_child(none)
		return
	for person in list:
		var row := HBoxContainer.new()
		var name_label := Label.new()
		name_label.text = person.name
		name_label.size_flags_horizontal = SIZE_EXPAND_FILL
		name_label.tooltip_text = parole.summary(person)
		name_label.mouse_filter = MOUSE_FILTER_PASS
		row.add_child(name_label)
		var odds := Label.new()
		odds.text = "%d%%" % roundi(parole.chance(person)[0] * 100.0)
		odds.custom_minimum_size = Vector2(48, 0)
		odds.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(odds)
		var hold := CheckBox.new()
		hold.text = "Hold back"
		hold.focus_mode = FOCUS_NONE
		hold.tooltip_text = "Keep them from parole hearings until you untick this."
		hold.button_pressed = person.profile.get("parole_held_back", false)
		hold.toggled.connect(func(on: bool) -> void:
			if on:
				person.profile["parole_held_back"] = true
				parole.queue.erase(person)
			else:
				person.profile.erase("parole_held_back"))
		row.add_child(hold)
		_parole_rows.add_child(row)
