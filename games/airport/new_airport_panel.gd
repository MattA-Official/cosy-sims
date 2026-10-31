class_name NewAirportPanel
extends PanelContainer
## The new airport card on the title screen: a name, what to start with
## and the map size. Start fills in AirportNewGame and emits `started`.

signal started
signal back_pressed

const START_ABOUT: Dictionary[AirportNewGame.Start, String] = {
	AirportNewGame.Start.EMPTY: "A grass field by the road, and nothing on it yet. Build the lot yourself.",
	AirportNewGame.Start.SHED: "A little shed terminal: check-in, a screening point, a lounge and a gate, with a double-height hall, escalators to a viewing deck and a bag hall with belts.",
}
const START_NAMES: Dictionary[AirportNewGame.Start, String] = {
	AirportNewGame.Start.EMPTY: "Empty field",
	AirportNewGame.Start.SHED: "The shed",
}

var _name := LineEdit.new()
var _start := AirportNewGame.Start.SHED
var _start_about := Label.new()
var _map := 0
var _map_about := Label.new()


func _ready() -> void:
	custom_minimum_size = Vector2(560, 0)
	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", 10)
	add_child(box)
	var heading := HBoxContainer.new()
	var title := Label.new()
	title.text = "A new airport"
	title.theme_type_variation = &"HeaderLabel"
	title.add_theme_font_size_override(&"font_size", 24)
	title.size_flags_horizontal = SIZE_EXPAND_FILL
	heading.add_child(title)
	var back := Button.new()
	back.text = "Back"
	back.theme_type_variation = &"FlatButton"
	back.focus_mode = FOCUS_NONE
	back.pressed.connect(back_pressed.emit)
	heading.add_child(back)
	box.add_child(heading)

	box.add_child(_heading("Name"))
	var name_row := HBoxContainer.new()
	_name.text = AirportNewGame.random_name()
	_name.size_flags_horizontal = SIZE_EXPAND_FILL
	_name.max_length = 40
	name_row.add_child(_name)
	var dice := CosyButton.new()
	dice.title = "Another name"
	dice.details = "Picks a name at random."
	dice.icon = load("res://core/ui/icons/dice.svg")
	dice.theme_type_variation = &"ModeButton"
	dice.focus_mode = FOCUS_NONE
	dice.pressed.connect(func() -> void: _name.text = AirportNewGame.random_name())
	name_row.add_child(dice)
	box.add_child(name_row)

	box.add_child(_heading("Start with"))
	var starts := HBoxContainer.new()
	var start_group := ButtonGroup.new()
	for start: AirportNewGame.Start in START_NAMES:
		var button := Button.new()
		button.text = START_NAMES[start]
		button.toggle_mode = true
		button.button_group = start_group
		button.focus_mode = FOCUS_NONE
		button.button_pressed = start == _start
		button.toggled.connect(func(on: bool) -> void:
			if on:
				_start = start
				_start_about.text = START_ABOUT[start])
		starts.add_child(button)
	box.add_child(starts)
	_start_about.text = START_ABOUT[_start]
	_about(_start_about)
	box.add_child(_start_about)

	box.add_child(_heading("Map size"))
	var sizes := HBoxContainer.new()
	var size_group := ButtonGroup.new()
	for i in AirportCatalogue.MAP_SIZES.size():
		var def := AirportCatalogue.MAP_SIZES[i]
		var button := Button.new()
		button.text = def.display_name
		button.toggle_mode = true
		button.button_group = size_group
		button.focus_mode = FOCUS_NONE
		button.button_pressed = i == _map
		button.toggled.connect(func(on: bool) -> void:
			if on:
				_map = i
				_map_about.text = def.description)
		sizes.add_child(button)
	box.add_child(sizes)
	_map_about.text = AirportCatalogue.MAP_SIZES[_map].description
	_about(_map_about)
	box.add_child(_map_about)

	var go := Button.new()
	go.text = "Open the airport"
	go.theme_type_variation = &"AccentButton"
	go.focus_mode = FOCUS_NONE
	go.pressed.connect(start)
	box.add_child(go)


## Fills in AirportNewGame from the card and says so.
func start() -> void:
	AirportNewGame.pending = true
	AirportNewGame.airport_name = _name.text.strip_edges()
	AirportNewGame.start = _start
	AirportNewGame.map_size = AirportCatalogue.MAP_SIZES[_map].id
	started.emit()


func _heading(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.theme_type_variation = &"KeyLabel"
	return label


func _about(label: Label) -> void:
	label.theme_type_variation = &"SubtleLabel"
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = 500
