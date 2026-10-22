class_name NewGamePanel
extends PanelContainer
## The new game screen's card: the prison's name, what to start with, the
## difficulty, sentence length and a few extras. Start fills in NewGame
## and emits `started`; the title screen then loads the prison.

signal started
signal back_pressed

const EMPTY_ABOUT := "Flat land by the road, and nothing on it yet. Build the lot yourself."
## Scenarios come after the samples in the start choices, from this value.
const FIRST_SCENARIO := 100
## Campaign chapters come after the scenarios, from this value.
const FIRST_CHAPTER := 200
## Short lines for the sample prisons offered, by SamplePrisons index.
const START_ABOUT: Dictionary[int, String] = {
	0: "A small cell block with a corridor and a fenced yard. Plenty of room to grow.",
	9: "Kitchen, laundry and workshop running, with prisoners on work programmes. No guards yet.",
	10: "A working prison with a guard post and guards on patrol, day and night.",
	11: "A warden, a reception and the morning bus: money and grades are on from day one.",
	12: "Everything in the paying prison, plus a classroom and counselling for reform and parole.",
}
const EXTRAS := [
	["staff_cars", "Staff drive in", "Staff with a car park by the road drive to work and park. Off, they come on the staff bus."],
	["split_levels", "Split levels", "Floors can sit part way up a storey, with ramps between them."],
	["door_steps", "Door steps", "Doors between floors up to a metre apart get a few steps on the low side."],
]

var _name := LineEdit.new()
var _start_about := Label.new()
var _difficulty_about := Label.new()
var _start := -1
var _map_size := 0
var _map_box: Control
var _map_about := Label.new()
var _difficulty := 2
var _length := Sentences.Length.NORMAL
var _extras: Dictionary[String, bool] = {}
## Warden candidates (pairs of work trait ids), and which is picked: 0 for
## the default warden.
var _candidates := NewGame.warden_candidates()
var _warden := 0
var _warden_about := Label.new()


func _ready() -> void:
	custom_minimum_size = Vector2(600, 0)
	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", 10)
	add_child(box)
	var heading := HBoxContainer.new()
	var title := Label.new()
	title.text = "A new prison"
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
	_name.text = NewGame.random_name()
	_name.size_flags_horizontal = SIZE_EXPAND_FILL
	_name.max_length = 40
	name_row.add_child(_name)
	var dice := CosyButton.new()
	dice.title = "Another name"
	dice.details = "Picks a name at random."
	dice.icon = load("res://core/ui/icons/dice.svg")
	dice.theme_type_variation = &"ModeButton"
	dice.focus_mode = FOCUS_NONE
	dice.custom_minimum_size = Vector2(38, 38)
	dice.pressed.connect(func() -> void: _name.text = NewGame.random_name())
	name_row.add_child(dice)
	box.add_child(name_row)

	box.add_child(_heading("Start with"))
	var starts: Array = [["Empty land", -1]]
	for index in NewGame.STARTS:
		starts.append([SamplePrisons.NAMES[index], index])
	for i in PrisonCatalogue.SCENARIOS.size():
		starts.append(["Scenario: %s" % PrisonCatalogue.SCENARIOS[i].title, FIRST_SCENARIO + i])
	var campaign := Campaign.new()
	campaign.chapters.assign(PrisonCatalogue.CHAPTERS)
	for def in campaign.unlocked():
		starts.append(["Chapter %d: %s" % [def.chapter, def.title], FIRST_CHAPTER + def.chapter - 1])
	campaign.free()
	box.add_child(_choices(starts, _start, func(value: int) -> void:
		_start = value
		_show_about()))
	_start_about.theme_type_variation = &"SubtleLabel"
	_start_about.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_start_about)

	# Only empty land comes in sizes; the samples are laid out already.
	_map_box = VBoxContainer.new()
	_map_box.add_child(_heading("Map size"))
	var sizes: Array = []
	var offered := _offered_sizes()
	for i in offered.size():
		sizes.append([offered[i].display_name, i])
	_map_box.add_child(_choices(sizes, _map_size, func(value: int) -> void:
		_map_size = value
		_show_about()))
	_map_about.theme_type_variation = &"SubtleLabel"
	_map_about.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_map_box.add_child(_map_about)
	box.add_child(_map_box)

	box.add_child(_heading("Difficulty"))
	var levels: Array = []
	for i in Standing.DIFFICULTIES.size():
		levels.append([Standing.DIFFICULTIES[i].display_name, i])
	box.add_child(_choices(levels, _difficulty, func(value: int) -> void:
		_difficulty = value
		_show_about()))
	_difficulty_about.theme_type_variation = &"SubtleLabel"
	_difficulty_about.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_difficulty_about)

	box.add_child(_heading("Warden"))
	var traits := PrisonStaffTraits.all()
	var words := func(ids: Array) -> String:
		return " and ".join(ids.map(func(id: StringName) -> String:
				return traits.filter(func(t: StaffTraitDef) -> bool: return t.id == id)[0].display_name))
	var wardens: Array = [["Default", 0]]
	for i in _candidates.size():
		wardens.append([words.call(_candidates[i]), i + 1])
	box.add_child(_choices(wardens, _warden, func(value: int) -> void:
		_warden = value
		_show_about()))
	_warden_about.theme_type_variation = &"SubtleLabel"
	_warden_about.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_warden_about)

	box.add_child(_heading("Sentences"))
	var lengths: Array = []
	for i in Sentences.LENGTH_NAMES.size():
		lengths.append([Sentences.LENGTH_NAMES[i], i])
	box.add_child(_choices(lengths, _length, func(value: int) -> void:
		_length = value as Sentences.Length))

	box.add_child(_heading("Extras"))
	var extras := HFlowContainer.new()
	extras.add_theme_constant_override(&"h_separation", 18)
	for entry: Array in EXTRAS:
		var check := CheckBox.new()
		check.text = entry[1]
		check.tooltip_text = entry[2]
		check.focus_mode = FOCUS_NONE
		_extras[entry[0]] = false
		check.toggled.connect(func(on: bool) -> void: _extras[entry[0]] = on)
		extras.add_child(check)
	box.add_child(extras)

	box.add_child(HSeparator.new())
	var go := Button.new()
	go.text = "Open the gates"
	go.theme_type_variation = &"AccentButton"
	go.focus_mode = FOCUS_NONE
	go.size_flags_horizontal = SIZE_SHRINK_END
	go.custom_minimum_size = Vector2(200, 44)
	go.pressed.connect(_go)
	box.add_child(go)
	_show_about()


func _go() -> void:
	NewGame.pending = true
	NewGame.prison_name = _name.text.strip_edges() if _name.text.strip_edges() != "" else NewGame.random_name()
	var scenario := _scenario()
	NewGame.start = scenario.layout if scenario != null else _start
	Standing.next_scenario = scenario.id if scenario != null else &""
	SamplePrisons.next_map_size = _offered_sizes()[_map_size].id
	NewGame.sentence_length = _length
	NewGame.staff_cars = _extras.staff_cars
	NewGame.split_levels = _extras.split_levels
	NewGame.door_steps = _extras.door_steps
	Standing.next_difficulty = Standing.DIFFICULTIES[_difficulty].id
	NewGame.warden_traits.assign(_candidates[_warden - 1] if _warden > 0 else [])
	started.emit()


func _show_about() -> void:
	var scenario := _scenario()
	if scenario != null:
		_start_about.text = scenario.description + (" You have %d days." % scenario.day_limit if scenario.day_limit > 0 else "")
		if scenario.chapter > 0:
			_start_about.text += " Teaches: " + scenario.teaches
	else:
		_start_about.text = EMPTY_ABOUT if _start < 0 else START_ABOUT.get(_start, SamplePrisons.CHALLENGES[_start])
	_difficulty_about.text = Standing.DIFFICULTIES[_difficulty].description
	_map_box.visible = _start < 0
	if _warden == 0:
		_warden_about.text = "A steady pair of hands, with no particular way of working."
	else:
		var traits := PrisonStaffTraits.all()
		_warden_about.text = ". ".join(_candidates[_warden - 1].map(func(id: StringName) -> String:
				var def: StaffTraitDef = traits.filter(func(t: StaffTraitDef) -> bool: return t.id == id)[0]
				return "%s: %s" % [def.display_name, def.description.to_lower()])) + "."
	_map_about.text = _offered_sizes()[_map_size].description


func _scenario() -> ScenarioDef:
	if _start >= FIRST_CHAPTER:
		return PrisonCatalogue.CHAPTERS[_start - FIRST_CHAPTER]
	return PrisonCatalogue.SCENARIOS[_start - FIRST_SCENARIO] if _start >= FIRST_SCENARIO else null


func _offered_sizes() -> Array:
	return PrisonCatalogue.MAP_SIZES.filter(func(d: MapSizeDef) -> bool: return d.offered)


func _heading(text: String) -> Label:
	var label := Label.new()
	label.text = text.to_upper()
	label.theme_type_variation = &"TitleLabel"
	return label


## A row of buttons, one lit at a time. Each entry is [text, value].
func _choices(entries: Array, current: int, pick: Callable) -> Control:
	var row := HFlowContainer.new()
	row.add_theme_constant_override(&"h_separation", 6)
	row.add_theme_constant_override(&"v_separation", 6)
	var group := ButtonGroup.new()
	for entry: Array in entries:
		var button := Button.new()
		button.text = entry[0]
		button.toggle_mode = true
		button.button_group = group
		button.focus_mode = FOCUS_NONE
		button.set_pressed_no_signal(entry[1] == current)
		button.pressed.connect(pick.bind(entry[1]))
		row.add_child(button)
	return row
