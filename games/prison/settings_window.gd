class_name SettingsWindow
extends PanelContainer
## How the game plays and sounds: difficulty, sentence length and volumes. Changing difficulty
## starts the Ministry's counts again. Toggle with F4.

## A volume slider per sound bus: [bus, words].
const VOLUMES := [[&"Master", "All sound"], [&"Effects", "Building and the prison"],
		[&"Interface", "Menus and clicks"], [&"Ambience", "Surroundings"], [&"Music", "Music"]]

var standing: Standing
var sentences: Sentences

var _difficulty := OptionButton.new()
var _about := Label.new()
var _length := OptionButton.new()
var _worries := Label.new()


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
