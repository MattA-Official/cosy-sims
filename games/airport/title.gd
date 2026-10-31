extends Control
## The airport's title screen: the shed terminal behind, slowly turning,
## and a card with New airport and Quit. New airport opens a second card
## beside it.

const GAME_SCENE := "res://games/airport/main.tscn"
## Degrees a second the camera turns round the backdrop.
const TURN_SPEED := 2.5

var _world := SubViewport.new()
var _backdrop: Node
var _side := PanelContainer.new()
var _new_game := NewAirportPanel.new()


func _ready() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_add_backdrop()

	# A soft wash down the left so the card reads against the world.
	var wash := TextureRect.new()
	var gradient := Gradient.new()
	gradient.set_color(0, Color(0.96, 0.97, 0.99, 0.85))
	gradient.set_color(1, Color(0.96, 0.97, 0.99, 0.0))
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
	add_child(row)
	var menu_card := PanelContainer.new()
	menu_card.size_flags_vertical = SIZE_SHRINK_CENTER
	row.add_child(menu_card)
	var menu := VBoxContainer.new()
	menu.custom_minimum_size.x = 300
	menu_card.add_child(menu)
	var logo := Label.new()
	logo.text = "Cosy Airport"
	logo.theme_type_variation = &"HeaderLabel"
	logo.add_theme_font_size_override(&"font_size", 50)
	menu.add_child(logo)
	var tagline := Label.new()
	tagline.text = "Grow a grass strip into a busy little airport, and get everyone away on time."
	tagline.theme_type_variation = &"SubtleLabel"
	tagline.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tagline.add_theme_font_size_override(&"font_size", 17)
	menu.add_child(tagline)
	var gap := Control.new()
	gap.custom_minimum_size.y = 24
	menu.add_child(gap)
	var buttons := VBoxContainer.new()
	buttons.add_theme_constant_override(&"separation", 8)
	menu.add_child(buttons)
	buttons.add_child(_button("New airport", _show.bind(_new_game), &"AccentButton"))
	buttons.add_child(_button("Quit", func() -> void: get_tree().quit()))

	_side.add_theme_stylebox_override(&"panel", StyleBoxEmpty.new())
	_side.size_flags_vertical = SIZE_SHRINK_CENTER
	row.add_child(_side)
	_new_game.started.connect(func() -> void: get_tree().change_scene_to_file(GAME_SCENE))
	_new_game.back_pressed.connect(_show.bind(null))
	_new_game.visible = false
	_side.add_child(_new_game)
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


## The shed, in a world of its own behind the menu. It gets no input.
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
	_backdrop = (load(GAME_SCENE) as PackedScene).instantiate()
	_backdrop.attract = true
	_world.add_child(_backdrop)
	(_backdrop.camera_rig as Node).set_process(false)
	(_backdrop.camera_rig as Node).set_process_unhandled_input(false)
	(_backdrop.cursor as Node3D).visible = false
	(_backdrop.cursor as Node).set_process(false)
	(_backdrop.day_night as DayNight).always_day = true
	for level_view: BuildingView in _backdrop.views.values():
		level_view.show_labels = false
	var rig: CameraRig = _backdrop.camera_rig
	rig.camera.position.z = 30.0
	rig.camera.h_offset = -8.0


func _show(card: Control) -> void:
	_new_game.visible = card == _new_game


func _button(text: String, action: Callable, variation: StringName = &"") -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = FOCUS_NONE
	button.theme_type_variation = variation
	button.custom_minimum_size.y = 44
	button.pressed.connect(action)
	return button
