class_name OfficeWindow
extends PanelContainer
## The warden's office: who comes on the bus each morning, and (with a
## warden) the grant goals and the prison's grade. Toggle with O.

const REFRESH_SECONDS := 0.5

var office: Office
var intake: Intake
## Extra sections below the intake, such as goals: a Control each.
var sections: Array[Control] = []

var _missing := Label.new()
var _limit := Label.new()
var _limit_row := HBoxContainer.new()
var _beds := Label.new()
var _checks: Dictionary[StringName, CheckBox] = {}
var _buttons: Array[Button] = []
var _wait := 0.0


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
	_limit_row.add_child(_button("+", func() -> void: intake.limit = mini(intake.limit + 1, Intake.MAX_LIMIT)))
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
	for section in sections:
		box.add_child(HSeparator.new())
		box.add_child(section)
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
	var problems := intake.warnings()
	_beds.text = problems[0] if not problems.is_empty() else "%d free beds." % intake.free_beds()


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
