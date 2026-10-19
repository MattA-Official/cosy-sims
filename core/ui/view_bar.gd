class_name ViewBar
extends PanelContainer
## The view controls in the top-right corner, kept apart from the build
## menu: which level you're on (Page Up / Down), how walls are shown (Tab),
## and buttons for the help card (F1) and the debug view (F3).

signal help_pressed
signal debug_pressed

const ICONS := "res://core/ui/icons/%s.svg"
const VIEW_ICONS: Array[String] = ["view_walls_up", "view_cutaway", "view_walls_down", "view_roofs"]
const VIEW_DETAILS: Array[String] = [
	"Every wall at full height.",
	"Walls in front of rooms drop, following the camera round.",
	"Every wall cut low.",
	"Every level with its roofs, as from outside.",
]

var building: Building
var controller: BuildController

var _level := Label.new()
var _views: Array[CosyButton] = []
var _debug: CosyButton


func _ready() -> void:
	theme_type_variation = &"HudBar"
	set_anchors_and_offsets_preset(PRESET_TOP_RIGHT, PRESET_MODE_MINSIZE, 12)
	grow_horizontal = GROW_DIRECTION_BEGIN
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 4)
	add_child(row)

	var down := _button("Down a level", "Page Down", "level_down")
	down.toggle_mode = false
	down.pressed.connect(func() -> void: building.active -= 1)
	row.add_child(down)
	_level.theme_type_variation = &"HeaderLabel"
	_level.add_theme_font_size_override(&"font_size", 15)
	_level.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_level.custom_minimum_size.x = 104
	row.add_child(_level)
	var up := _button("Up a level", "Page Up", "level_up")
	up.toggle_mode = false
	up.pressed.connect(func() -> void: building.active += 1)
	row.add_child(up)
	row.add_child(VSeparator.new())

	var group := ButtonGroup.new()
	for i in BuildController.WALL_VIEW_NAMES.size():
		var button := _button(BuildController.WALL_VIEW_NAMES[i], VIEW_DETAILS[i] + "\nTab loops through them.",
				VIEW_ICONS[i])
		button.button_group = group
		button.toggled.connect(func(on: bool) -> void:
			if on:
				controller.wall_view = i as BuildController.WallView)
		row.add_child(button)
		_views.append(button)
	row.add_child(VSeparator.new())

	var help := _button("Controls", "Every key and mouse control. F1", "help")
	help.toggle_mode = false
	help.pressed.connect(help_pressed.emit)
	row.add_child(help)
	_debug = _button("Debug view", "Rooms tinted and labelled, and an inspector. F3", "debug")
	_debug.pressed.connect(debug_pressed.emit)
	row.add_child(_debug)

	building.active_changed.connect(func(_level_number: int) -> void: _show_level())
	controller.wall_view_changed.connect(func(_mode: BuildController.WallView) -> void: _show_wall_view())
	_show_level()
	_show_wall_view()


## Lights the debug button to match whether the debug view is showing.
func show_debug(on: bool) -> void:
	_debug.set_pressed_no_signal(on)


func _show_level() -> void:
	_level.text = Building.level_name(building.active)


func _show_wall_view() -> void:
	for i in _views.size():
		_views[i].set_pressed_no_signal(i == controller.wall_view)


func _button(title: String, details: String, icon_name: String) -> CosyButton:
	var button := CosyButton.new()
	button.title = title
	button.details = details
	button.icon = load(ICONS % icon_name)
	button.theme_type_variation = &"ModeButton"
	button.toggle_mode = true
	button.focus_mode = FOCUS_NONE
	button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	button.custom_minimum_size = Vector2(34, 34)
	return button
