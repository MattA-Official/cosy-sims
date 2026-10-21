class_name SettingsWindow
extends PanelContainer
## How the game plays and sounds: difficulty, sentence length, instant
## building, red tape, research and volumes. Changing difficulty starts the
## Ministry's counts again. Toggle with F4.

## A volume slider per sound bus: [bus, words].
const VOLUMES := [[&"Master", "All sound"], [&"Effects", "Building and the prison"],
		[&"Interface", "Menus and clicks"], [&"Ambience", "Surroundings"], [&"Music", "Music"]]

var standing: Standing
var blueprints: Blueprints
var desk_work: DeskWork
var sentences: Sentences
var research: Research
var illnesses: Illnesses

var _difficulty := OptionButton.new()
var _about := Label.new()
var _length := OptionButton.new()
var _worries := Label.new()
var _instant := CheckButton.new()
var _red_tape := OptionButton.new()
var _research := OptionButton.new()
var _illness := CheckButton.new()


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
	title.text = "Game settings"
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

	for def in Standing.DIFFICULTIES:
		_difficulty.add_item(def.display_name)
	_difficulty.focus_mode = FOCUS_NONE
	_difficulty.item_selected.connect(func(index: int) -> void:
		standing.set_difficulty(Standing.DIFFICULTIES[index])
		Standing.next_difficulty = Standing.DIFFICULTIES[index].id
		refresh())
	box.add_child(_row("Difficulty", _difficulty))
	_about.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_about.theme_type_variation = &"SubtleLabel"
	box.add_child(_about)
	_worries.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_worries)
	box.add_child(HSeparator.new())

	for words in Sentences.LENGTH_NAMES:
		_length.add_item(words)
	_length.focus_mode = FOCUS_NONE
	_length.tooltip_text = "How long new arrivals are sent here for. Prisoners already here keep theirs."
	_length.item_selected.connect(func(index: int) -> void: sentences.length = index as Sentences.Length)
	box.add_child(_row("Sentence length", _length))
	_instant.focus_mode = FOCUS_NONE
	_instant.tooltip_text = "On, everything goes up the moment you place it. Off, walls, floors, doors and windows go down as blueprints for handymen to build, paid for when they start. Objects are always instant."
	_instant.toggled.connect(func(on: bool) -> void:
		if blueprints != null:
			blueprints.instant = on)
	box.add_child(_row("Instant building", _instant))
	for words in ["Off", "Light", "Full"]:
		_red_tape.add_item(words)
	_red_tape.focus_mode = FOCUS_NONE
	_red_tape.tooltip_text = "How much paperwork lands on the warden's and heads' desks each morning, per prisoner. Off: none. Light: 2 minutes for the warden, 1 for each head. Full: twice that."
	_red_tape.item_selected.connect(func(index: int) -> void:
		if desk_work != null:
			desk_work.red_tape = index as DeskWork.RedTape)
	box.add_child(_row("Red tape", _red_tape))
	for words in ["Full", "Warden only", "Off"]:
		_research.add_item(words)
	_research.focus_mode = FOCUS_NONE
	_research.tooltip_text = "Full: the warden and each head research their own trees, with joint cards and wing trials. Warden only: one desk, the warden's, works every card at full speed. Off: every card is done at once, and pick-one pairs become policies to choose on the research board. Cards done stay done if you switch back."
	_research.item_selected.connect(func(index: int) -> void:
		if research != null:
			research.set_mode(index as Research.Mode))
	box.add_child(_row("Research", _research))
	_illness.focus_mode = FOCUS_NONE
	_illness.tooltip_text = "On, prisoners catch colds from each other, more in crowded rooms. A cold passes in a few days, or one once a nurse sees to it. Nobody's health suffers."
	_illness.toggled.connect(func(on: bool) -> void:
		if illnesses != null:
			illnesses.enabled = on)
	box.add_child(_row("Illness", _illness))
	box.add_child(HSeparator.new())
	for entry: Array in VOLUMES:
		var slider := HSlider.new()
		slider.min_value = 0.0
		slider.max_value = 1.0
		slider.step = 0.05
		slider.focus_mode = FOCUS_NONE
		slider.value = Sound.volume(entry[0])
		slider.value_changed.connect(func(amount: float) -> void:
			Sound.set_volume(entry[0], amount)
			Sound.play(&"build_place" if entry[0] != &"Interface" else &"build_rotate"))
		box.add_child(_row(entry[1], slider))
	visible = false


func _row(text: String, control: Control) -> Control:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = text
	label.size_flags_horizontal = SIZE_EXPAND_FILL
	row.add_child(label)
	control.custom_minimum_size = Vector2(150, 0)
	row.add_child(control)
	return row


func toggle() -> void:
	visible = not visible
	if visible:
		refresh()


func refresh() -> void:
	if standing == null:
		return
	_difficulty.select(Standing.DIFFICULTIES.find(standing.difficulty))
	_about.text = standing.difficulty.description
	_worries.text = "\n".join(standing.warnings) if not standing.warnings.is_empty() else ""
	_worries.visible = not standing.warnings.is_empty()
	if sentences != null:
		_length.select(sentences.length)
	if blueprints != null:
		_instant.set_pressed_no_signal(blueprints.instant)
	if desk_work != null:
		_red_tape.select(desk_work.red_tape)
	if research != null:
		_research.select(research.mode)
	if illnesses != null:
		_illness.set_pressed_no_signal(illnesses.enabled)
