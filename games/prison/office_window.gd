class_name OfficeWindow
extends PanelContainer
## The warden's office: who comes on the bus each morning, and (with a
## warden) the grant goals and the prison's grade. Toggle with O.

const REFRESH_SECONDS := 0.5

var office: Office
var intake: Intake
var standing: Standing
var consequences: Consequences
var searching: Searching

var _missing := Label.new()
var _limit := Label.new()
var _limit_row := HBoxContainer.new()
var _beds := Label.new()
var _checks: Dictionary[StringName, CheckBox] = {}
var _buttons: Array[Button] = []
var _wait := 0.0
var _grade := Label.new()
var _measures := Label.new()
var _goals := VBoxContainer.new()
var _report := Label.new()
var _policies: Array[Control] = []
var _searches := OptionButton.new()
var _days := OptionButton.new()
var _quiet := CheckBox.new()


func _ready() -> void:
	set_anchors_and_offsets_preset(PRESET_CENTER_TOP, PRESET_MODE_MINSIZE)
	grow_horizontal = GROW_DIRECTION_BOTH
	offset_top = 76.0
	custom_minimum_size = Vector2(460, 0)
	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", 8)
	add_child(box)

	var heading := HBoxContainer.new()
	var title := Label.new()
	title.text = "Warden's office"
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
	_missing.theme_type_variation = &"SubtleLabel"
	_missing.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_missing)

	var intake_heading := Label.new()
	intake_heading.text = "Intake"
	intake_heading.theme_type_variation = &"HeaderLabel"
	box.add_child(intake_heading)
	var words := Label.new()
	words.text = "The bus comes at %02d:00. Each arrival is searched at reception, then walked to a free bed." \
			% Intake.BUS_HOUR
	words.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	words.theme_type_variation = &"SubtleLabel"
	box.add_child(words)

	var name_label := Label.new()
	name_label.text = "Arrivals a day"
	name_label.size_flags_horizontal = SIZE_EXPAND_FILL
	_limit_row.add_child(name_label)
	_limit_row.add_child(_button("−", func() -> void: intake.limit = maxi(intake.limit - 1, 0)))
	_limit.custom_minimum_size = Vector2(32, 0)
	_limit.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_limit_row.add_child(_limit)
	_limit_row.add_child(_button("+", func() -> void: intake.limit = mini(intake.limit + 1, intake.max_limit)))
	box.add_child(_limit_row)
	var categories := HBoxContainer.new()
	categories.add_theme_constant_override(&"separation", 12)
	for def in intake.categories:
		var check := CheckBox.new()
		check.text = def.display_name
		check.tooltip_text = "%s\nGrant: %s a day each." % [def.description, Ledger.text(def.daily_grant)]
		check.focus_mode = FOCUS_NONE
		var id := def.id
		check.toggled.connect(func(on: bool) -> void: intake.accepted[id] = on)
		categories.add_child(check)
		_checks[def.id] = check
	box.add_child(categories)
	_beds.theme_type_variation = &"SubtleLabel"
	box.add_child(_beds)
	if consequences != null and searching != null:
		_add_policies(box)
	if standing != null:
		box.add_child(HSeparator.new())
		_grade.theme_type_variation = &"HeaderLabel"
		_grade.tooltip_text = "Graded each midnight on safety, wellbeing, reform and money. A better grade brings a bigger grant and a bigger intake."
		_grade.mouse_filter = MOUSE_FILTER_PASS
		box.add_child(_grade)
		_measures.theme_type_variation = &"SubtleLabel"
		box.add_child(_measures)
		box.add_child(HSeparator.new())
		var goals_heading := Label.new()
		goals_heading.text = "Grant goals"
		goals_heading.theme_type_variation = &"HeaderLabel"
		box.add_child(goals_heading)
		_goals.add_theme_constant_override(&"separation", 2)
		box.add_child(_goals)
		_report.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_report.theme_type_variation = &"SubtleLabel"
		box.add_child(_report)
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
	if intake == null:
		return
	var warden := office.has_warden()
	var missing := office.missing()
	_missing.text = "The warden is in charge." if missing.is_empty() else missing
	if not warden:
		_missing.text += " Until then %d low or medium security prisoners come each day." % Intake.WITHOUT_WARDEN
	_limit.text = str(intake.todays_count())
	for button in _buttons:
		button.disabled = not warden
	for id: StringName in _checks:
		_checks[id].disabled = not warden
		_checks[id].set_pressed_no_signal(intake.accepted.get(id, false) if warden
				else Intake.WITHOUT_WARDEN_CATEGORIES.has(id))
	for control in _policies:
		if control is BaseButton:
			(control as BaseButton).disabled = not warden
	if searching != null:
		_searches.selected = maxi(Searching.POLICIES.find(searching.random_per_day), 0)
		_days.selected = maxi(DAYS.find(roundi(consequences.privilege_days)), 0)
		_quiet.set_pressed_no_signal(consequences.quiet_room_on)
	var problems := intake.warnings()
	_beds.text = problems[0] if not problems.is_empty() else "%d free beds." % intake.free_beds()
	if standing != null:
		_show_standing(warden)


## How long privileges are lost for, in game days.
const DAYS: Array[int] = [1, 2, 4]


func _add_policies(box: VBoxContainer) -> void:
	box.add_child(HSeparator.new())
	var heading := Label.new()
	heading.text = "Policies"
	heading.theme_type_variation = &"HeaderLabel"
	box.add_child(heading)
	for count in Searching.POLICIES:
		_searches.add_item("None" if count == 0 else "%d a day" % count)
	_searches.item_selected.connect(func(index: int) -> void: searching.random_per_day = Searching.POLICIES[index])
	_searches.tooltip_text = "Guards turn over random cells. Finds contraband, but being searched puts prisoners out."
	box.add_child(_row("Random cell searches", _searches))
	for days in DAYS:
		_days.add_item("%d day%s" % [days, "" if days == 1 else "s"])
	_days.item_selected.connect(func(index: int) -> void: consequences.privilege_days = DAYS[index])
	_days.tooltip_text = "How long a prisoner loses the yard, the telly or games after an offence."
	box.add_child(_row("Privileges lost for", _days))
	_quiet.text = "Quiet room for fights"
	_quiet.tooltip_text = "Fighters spend a day in a quiet room, if you have one. Off, they lose two privileges instead."
	_quiet.focus_mode = FOCUS_NONE
	_quiet.toggled.connect(func(on: bool) -> void: consequences.quiet_room_on = on)
	box.add_child(_quiet)
	_policies.assign([_searches, _days, _quiet])


func _row(text: String, control: Control) -> HBoxContainer:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = text
	label.size_flags_horizontal = SIZE_EXPAND_FILL
	row.add_child(label)
	control.focus_mode = FOCUS_NONE
	row.add_child(control)
	return row


## A line per measure with why, any measure holding the grade down, and
## the last few nights.
func measures_text() -> String:
	if not standing.measures_known():
		return "First graded at midnight."
	var lines := PackedStringArray()
	for measure: String in standing.measures:
		var stars: int = standing.measures[measure]
		var words := "%s %s" % [measure, "★".repeat(stars) + "☆".repeat(5 - stars)]
		if standing.why.has(measure):
			words += "  " + standing.why[measure]
		lines.append(words)
	if not standing.held_by.is_empty():
		lines.append("Held to %d★ by %s." % [standing.grade, standing.held_by])
	if standing.history.size() > 1:
		lines.append("Last %d nights: %s" % [standing.history.size(), " ".join(standing.history.map(
				func(night: Dictionary) -> String: return "%d★" % night.grade))])
	return "\n".join(lines)


func _show_standing(warden: bool) -> void:
	_grade.text = "Grade  %s%s" % ["★".repeat(standing.grade), "☆".repeat(5 - standing.grade)]
	_measures.text = measures_text() + "\nUp to %d arrivals a day at this grade." % intake.max_limit
	for child in _goals.get_children():
		_goals.remove_child(child)
		child.queue_free()
	if not warden:
		var none := Label.new()
		none.text = "A warden in the office takes on grant goals."
		none.theme_type_variation = &"SubtleLabel"
		_goals.add_child(none)
	else:
		for goal in standing.current_goals():
			var row := HBoxContainer.new()
			var title := Label.new()
			title.text = goal.title + (" (%s)" % goal.progress.call() if goal.progress.is_valid() else "")
			title.size_flags_horizontal = SIZE_EXPAND_FILL
			row.add_child(title)
			var grant := Label.new()
			grant.text = Ledger.text(goal.grant)
			row.add_child(grant)
			_goals.add_child(row)
	_report.text = ("Today's report:\n" + standing.report) if warden and not standing.report.is_empty() else ""


func _button(text: String, pressed: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = FOCUS_NONE
	button.custom_minimum_size = Vector2(32, 0)
	button.pressed.connect(func() -> void:
		pressed.call()
		refresh())
	_buttons.append(button)
	return button
