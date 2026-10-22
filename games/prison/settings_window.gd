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
var protest: Protest
var calendar: Calendar
var weather: Weather
var surprises: Surprises
var utilities: Utilities
## For the first-time tips setting.
var guide: Guide

var _difficulty := OptionButton.new()
var _about := Label.new()
var _length := OptionButton.new()
var _worries := Label.new()
var _instant := CheckButton.new()
var _red_tape := OptionButton.new()
var _research := OptionButton.new()
var _illness := CheckButton.new()
var _protestors := CheckButton.new()
var _seasons := CheckButton.new()
var _season_length := OptionButton.new()
var _weather := CheckButton.new()
var _surprises := OptionButton.new()
var _utilities := OptionButton.new()
var _location := OptionButton.new()
var _coast := OptionButton.new()
var _backdrop := OptionButton.new()
var _tips := CheckButton.new()
## For the backdrop detail setting: the scenery past the map.
var backdrop: Backdrop
## For the coast setting.
var water: WaterLayer
const SEASON_LENGTHS: Array[int] = [3, 5, 7, 10, 14, 30]


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
	_protestors.focus_mode = FOCUS_NONE
	_protestors.tooltip_text = "On, bad headlines bring campaigners with placards to the gate, and good ones may bring well-wishers with cake. They heckle staff and hold up traffic, never worse."
	_protestors.toggled.connect(func(on: bool) -> void:
		if protest != null:
			protest.enabled = on)
	box.add_child(_row("Protestors", _protestors))
	_seasons.focus_mode = FOCUS_NONE
	_seasons.tooltip_text = "On, the year turns through spring, summer, autumn and winter, with their own light, weather and festive days."
	_seasons.toggled.connect(func(on: bool) -> void:
		if calendar != null:
			calendar.enabled = on)
	box.add_child(_row("Seasons", _seasons))
	for days in SEASON_LENGTHS:
		_season_length.add_item("%d days" % days)
	_season_length.focus_mode = FOCUS_NONE
	_season_length.tooltip_text = "How many game days each season lasts."
	_season_length.item_selected.connect(func(index: int) -> void:
		if calendar != null:
			calendar.length = SEASON_LENGTHS[index])
	box.add_child(_row("Season length", _season_length))
	_weather.focus_mode = FOCUS_NONE
	_weather.tooltip_text = "On, rain, snow, heat and storms come and go. Wet days move the yard indoors; snow needs gritting."
	_weather.toggled.connect(func(on: bool) -> void:
		if weather != null:
			weather.enabled = on)
	box.add_child(_row("Weather", _weather))
	for words in ["Off", "Rare", "Normal", "Lively"]:
		_surprises.add_item(words)
	_surprises.focus_mode = FOCUS_NONE
	_surprises.tooltip_text = "How often small surprises come: an escaped hen, flu week, a film crew, a celebrity chef, a heatwave or a snow day. One roll each morning; never a game over."
	_surprises.item_selected.connect(func(index: int) -> void:
		if surprises != null:
			surprises.frequency = index as Surprises.Frequency)
	box.add_child(_row("Surprises", _surprises))
	for words: String in ["Off", "Bought in", "Self-sufficient"]:
		_utilities.add_item(words)
	_utilities.focus_mode = FOCUS_NONE
	_utilities.tooltip_text = "Off, power, water and sewage just work. Bought in, the prison pays for what it uses by the hour, and for heating by the day (more in winter), and power cuts can happen. Self-sufficient, you build generators, wells and treatment plants and lay cables and pipes to what needs them (the utilities tool, U); short of supply, the things furthest along a run go off."
	_utilities.item_selected.connect(func(index: int) -> void:
		if utilities != null:
			utilities.mode = index as Utilities.Mode)
	box.add_child(_row("Utilities", _utilities))
	for def in PrisonCatalogue.LOCATIONS:
		_location.add_item(def.display_name + (" (location pack)" if def.pack else ""))
		_location.set_item_disabled(_location.item_count - 1, def.pack)
		_location.set_item_tooltip(_location.item_count - 1, def.description)
	_location.focus_mode = FOCUS_NONE
	_location.tooltip_text = "Where the prison stands, which decides the ways in. The countryside has a road and buses, and a jetty for the ferry where there's water. Other places come as location packs."
	box.add_child(_row("Location", _location))
	for words in ["None", "North", "East", "South", "West"]:
		_coast.add_item(words)
	_coast.focus_mode = FOCUS_NONE
	_coast.tooltip_text = "Which edge of the map meets the sea. Ground dug below the sea's level near that edge floods, and the tide comes and goes twice a day."
	_coast.item_selected.connect(func(index: int) -> void:
		if water != null:
			water.coast = 0 if index == 0 else 1 << (index - 1)
			water.update_sea())
	box.add_child(_row("Coast", _coast))
	box.add_child(HSeparator.new())
	for words in ["Low", "High"]:
		_backdrop.add_item(words)
	_backdrop.focus_mode = FOCUS_NONE
	_backdrop.tooltip_text = "High draws the world past your land: hills, woods, a farm and the town, fading into fog. Low swaps it for plain fog, for slower computers. Kept on this computer for every prison."
	_backdrop.select(Backdrop.saved_detail())
	_backdrop.item_selected.connect(func(index: int) -> void:
		Backdrop.remember_detail(index as Backdrop.Detail)
		if backdrop != null:
			backdrop.detail = index as Backdrop.Detail)
	box.add_child(_row("Scenery detail", _backdrop))
	_tips.focus_mode = FOCUS_NONE
	_tips.tooltip_text = "On, a short card explains each tool, page and new happening the first time it comes up. Kept on this computer for every prison."
	_tips.toggled.connect(func(on: bool) -> void:
		if guide != null:
			guide.tips_on = on)
	var tips_row := HBoxContainer.new()
	var again := Button.new()
	again.text = "Show again"
	again.focus_mode = FOCUS_NONE
	again.tooltip_text = "Forgets which tips you've seen, so each shows once more."
	again.pressed.connect(func() -> void:
		if guide != null:
			guide.reset_tips()
			guide.tips_on = true
			_tips.set_pressed_no_signal(true))
	tips_row.add_child(again)
	tips_row.add_child(_tips)
	box.add_child(_row("First-time tips", tips_row))
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
	if guide != null:
		_tips.set_pressed_no_signal(guide.tips_on)
	if desk_work != null:
		_red_tape.select(desk_work.red_tape)
	if research != null:
		_research.select(research.mode)
	if illnesses != null:
		_illness.set_pressed_no_signal(illnesses.enabled)
	if protest != null:
		_protestors.set_pressed_no_signal(protest.enabled)
	if calendar != null:
		_seasons.set_pressed_no_signal(calendar.enabled)
		_season_length.select(maxi(SEASON_LENGTHS.find(calendar.length), 0))
	if weather != null:
		_weather.set_pressed_no_signal(weather.enabled)
	if surprises != null:
		_surprises.select(surprises.frequency)
	if water != null:
		_coast.select(0 if water.coast == 0 else [1, 2, 4, 8].find(water.coast) + 1)
	if utilities != null:
		_utilities.select(mini(utilities.mode, _utilities.item_count - 1))
