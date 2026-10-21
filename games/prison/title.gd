extends Control
## The title screen: a prison going about its day behind, slowly turning,
## and a card with Continue, New prison, Load and Quit. New prison and
## Load open a second card beside it.

const GAME_SCENE := "res://games/prison/main.tscn"
## The sample prison running behind the menu.
const BACKDROP_SAMPLE := 12
## Degrees a second the camera turns round the backdrop.
const TURN_SPEED := 2.5

var _world := SubViewport.new()
var _backdrop: Node
var _side := PanelContainer.new()
var _new_game := NewGamePanel.new()
var _loads := VBoxContainer.new()
var _load_card := PanelContainer.new()


func _ready() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_add_backdrop()

	# A soft wash down the left so the card reads against the world.
	var wash := TextureRect.new()
	var gradient := Gradient.new()
	gradient.set_color(0, Color(0.98, 0.96, 0.9, 0.85))
	gradient.set_color(1, Color(0.98, 0.96, 0.9, 0.0))
	var fade := GradientTexture2D.new()
	fade.gradient = gradient
	fade.width = 64
	fade.height = 4
	wash.texture = fade
	wash.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	wash.stretch_mode = TextureRect.STRETCH_SCALE
	wash.anchor_bottom = 1.0
	wash.offset_right = 760
	wash.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(wash)

	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 24)
	row.set_anchors_and_offsets_preset(PRESET_LEFT_WIDE)
	row.offset_left = 64
	row.offset_right = 64 + 960
	row.alignment = BoxContainer.ALIGNMENT_BEGIN
	add_child(row)
	var menu_card := PanelContainer.new()
	menu_card.size_flags_vertical = SIZE_SHRINK_CENTER
	row.add_child(menu_card)
	var menu := VBoxContainer.new()
	menu.custom_minimum_size.x = 300
	menu_card.add_child(menu)
	var logo := Label.new()
	logo.text = "Cosy Prison"
	logo.theme_type_variation = &"HeaderLabel"
	logo.add_theme_font_size_override(&"font_size", 50)
	menu.add_child(logo)
	var tagline := Label.new()
	tagline.text = "Build a kind little prison, and help everyone in it do better."
	tagline.theme_type_variation = &"SubtleLabel"
	tagline.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tagline.add_theme_font_size_override(&"font_size", 17)
	menu.add_child(tagline)
	var gap := Control.new()
	gap.custom_minimum_size.y = 24
	menu.add_child(gap)

	var latest := _latest_save()
	var buttons := VBoxContainer.new()
	buttons.add_theme_constant_override(&"separation", 8)
	menu.add_child(buttons)
	if latest != "":
		var resume := _button("Continue", func() -> void: _load(latest), &"AccentButton")
		resume.tooltip_text = PrisonSave.describe(PrisonSave.read(latest))
		buttons.add_child(resume)
		var about := Label.new()
		about.text = PrisonSave.describe(PrisonSave.read(latest))
		about.theme_type_variation = &"SubtleLabel"
		about.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		about.custom_minimum_size.x = 280
		buttons.add_child(about)
	buttons.add_child(_button("New prison", _show.bind(_new_game),
			&"" if latest != "" else &"AccentButton"))
	var load_button := _button("Load", _show.bind(_load_card))
	load_button.disabled = latest == ""
	buttons.add_child(load_button)
	buttons.add_child(_button("Quit", func() -> void: get_tree().quit()))

	_side.add_theme_stylebox_override(&"panel", StyleBoxEmpty.new())
	_side.size_flags_vertical = SIZE_SHRINK_CENTER
	row.add_child(_side)
	_new_game.started.connect(func() -> void: get_tree().change_scene_to_file(GAME_SCENE))
	_new_game.back_pressed.connect(_show.bind(null))
	_new_game.visible = false
	_side.add_child(_new_game)
	_build_load_card()
	_load_card.visible = false
	_side.add_child(_load_card)
	Toasts.clear()


func _exit_tree() -> void:
	Toasts.muted = false


func _process(delta: float) -> void:
	if _backdrop != null:
		(_backdrop.camera_rig as Node3D).rotation_degrees.y += TURN_SPEED * delta


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("build_cancel"):
		_show(null)
		get_viewport().set_input_as_handled()


## A prison from the samples, living out its day in a world of its own.
## It gets no input: the menu is all you touch.
func _add_backdrop() -> void:
	var view := TextureRect.new()
	view.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	view.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(view)
	_world.own_world_3d = true
	_world.size = get_viewport_rect().size
	_world.msaa_3d = Viewport.MSAA_2X
	add_child(_world)
	view.texture = _world.get_texture()
	get_viewport().size_changed.connect(func() -> void: _world.size = get_viewport_rect().size)
	Toasts.muted = true
	SamplePrisons.next = BACKDROP_SAMPLE
	_backdrop = (load(GAME_SCENE) as PackedScene).instantiate()
	_backdrop.attract = true
	_world.add_child(_backdrop)
	# The camera stays put but for a slow turn.
	(_backdrop.camera_rig as Node).set_process(false)
	(_backdrop.camera_rig as Node).set_process_unhandled_input(false)
	(_backdrop.cursor as Node3D).visible = false
	(_backdrop.cursor as Node).set_process(false)
	(_backdrop.day_night as DayNight).always_day = true
	for level_view: BuildingView in _backdrop.views.values():
		level_view.show_labels = false
	# Further out than in play, with the prison to the right of the menu.
	var rig: CameraRig = _backdrop.camera_rig
	rig.camera.position.z = 34.0
	rig.camera.h_offset = -9.0


func _show(card: Control) -> void:
	_new_game.visible = card == _new_game
	_load_card.visible = card == _load_card


func _build_load_card() -> void:
	_load_card.custom_minimum_size = Vector2(520, 0)
	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", 10)
	_load_card.add_child(box)
	var heading := HBoxContainer.new()
	var title := Label.new()
	title.text = "Load a prison"
	title.theme_type_variation = &"HeaderLabel"
	title.add_theme_font_size_override(&"font_size", 24)
	title.size_flags_horizontal = SIZE_EXPAND_FILL
	heading.add_child(title)
	var back := Button.new()
	back.text = "Back"
	back.theme_type_variation = &"FlatButton"
	back.focus_mode = FOCUS_NONE
	back.pressed.connect(_show.bind(null))
	heading.add_child(back)
	box.add_child(heading)
	var slots: Array = [["This morning's autosave", PrisonSave.AUTOSAVE]]
	for i in PrisonSave.SLOTS.size():
		slots.append(["Slot %d" % (i + 1), PrisonSave.SLOTS[i]])
	for entry: Array in slots:
		var data := PrisonSave.read(entry[1])
		var slot_row := HBoxContainer.new()
		slot_row.add_theme_constant_override(&"separation", 10)
		var words := VBoxContainer.new()
		words.add_theme_constant_override(&"separation", -2)
		words.size_flags_horizontal = SIZE_EXPAND_FILL
		var name_label := Label.new()
		name_label.text = entry[0]
		words.add_child(name_label)
		var about := Label.new()
		about.text = PrisonSave.describe(data)
		about.theme_type_variation = &"SubtleLabel"
		about.clip_text = true
		words.add_child(about)
		slot_row.add_child(words)
		var load_button := _button("Load", _load.bind(entry[1]))
		load_button.disabled = data.is_empty()
		load_button.custom_minimum_size = Vector2(90, 0)
		slot_row.add_child(load_button)
		box.add_child(slot_row)


## The most recently saved slot, or "" if nothing's saved.
func _latest_save() -> String:
	var best := ""
	var best_at := ""
	for slot: String in [PrisonSave.AUTOSAVE] + Array(PrisonSave.SLOTS):
		var at: String = PrisonSave.read(slot).get("saved_at", "")
		if at != "" and at > best_at:
			best = slot
			best_at = at
	return best


func _load(slot: String) -> void:
	PrisonSave.pending = PrisonSave.read(slot)
	get_tree().change_scene_to_file(GAME_SCENE)


func _button(text: String, pressed: Callable, variation := &"") -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = FOCUS_NONE
	button.custom_minimum_size = Vector2(280, 46)
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.add_theme_font_size_override(&"font_size", 18)
	if variation != &"":
		button.theme_type_variation = variation
	button.pressed.connect(pressed)
	return button
