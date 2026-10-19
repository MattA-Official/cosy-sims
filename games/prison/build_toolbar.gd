extends VBoxContainer
## The build toolbar along the bottom of the screen: a row of tools, a row of
## choices for the current tool (which object, which room type), and a hint.
## Number keys 1 to 9 pick tools.

@export var controller: BuildController

const TOOLS := [
	[BuildController.Tool.ROOM, "Room"],
	[BuildController.Tool.FLOOR, "Floor"],
	[BuildController.Tool.WALL, "Wall"],
	[BuildController.Tool.DOOR, "Door"],
	[BuildController.Tool.OBJECT, "Objects"],
	[BuildController.Tool.ROOM_TYPE, "Room type"],
	[BuildController.Tool.DEMOLISH, "Demolish"],
	[BuildController.Tool.TERRAIN, "Terrain"],
	[BuildController.Tool.PLANTS, "Plants"],
]

const BRUSHES := [
	[Terrain.Brush.RAISE, "Raise"],
	[Terrain.Brush.LOWER, "Lower"],
	[Terrain.Brush.FLATTEN, "Flatten"],
	[Terrain.Brush.SMOOTH, "Smooth"],
]

var _hint := Label.new()
var _options := HBoxContainer.new()
var _tool_buttons := {} # Tool -> Button
var _tool_group := ButtonGroup.new()
var _walls_button: Button


func _ready() -> void:
	alignment = BoxContainer.ALIGNMENT_END
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Only the buttons should catch the mouse, so clicks elsewhere on this
	# full-width strip still reach the build tools.
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_options.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.add_theme_constant_override("outline_size", 4)
	_hint.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	add_child(_hint)
	_options.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(_options)

	var tools := HBoxContainer.new()
	tools.alignment = BoxContainer.ALIGNMENT_CENTER
	tools.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(tools)
	for i in TOOLS.size():
		var tool: BuildController.Tool = TOOLS[i][0]
		var button := _make_button("%d  %s" % [i + 1, TOOLS[i][1]], _tool_group)
		button.toggled.connect(func(on: bool) -> void:
			if on:
				controller.tool = tool
			elif controller.tool == tool:
				controller.tool = BuildController.Tool.NONE)
		tools.add_child(button)
		_tool_buttons[tool] = button
	_walls_button = _make_button("Tab  Walls down")
	_walls_button.toggled.connect(func(on: bool) -> void: controller.view.walls_low = on)
	tools.add_child(_walls_button)

	_tool_group.allow_unpress = true
	controller.tool_changed.connect(_on_tool_changed)
	_on_tool_changed(controller.tool)


func _process(_delta: float) -> void:
	# Tab toggles walls without going through the button, so keep it in step.
	_walls_button.set_pressed_no_signal(controller.view.walls_low)


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	var index := key.physical_keycode - KEY_1
	if index >= 0 and index < TOOLS.size():
		var tool: BuildController.Tool = TOOLS[index][0]
		controller.tool = BuildController.Tool.NONE if controller.tool == tool else tool
		get_viewport().set_input_as_handled()


func _on_tool_changed(tool: BuildController.Tool) -> void:
	for t: BuildController.Tool in _tool_buttons:
		_tool_buttons[t].set_pressed_no_signal(t == tool)
	_hint.text = BuildController.HINTS[tool]
	for child in _options.get_children():
		child.queue_free()
	match tool:
		BuildController.Tool.ROOM:
			_add_style_choices(PrisonCatalogue.FLOORS, true)
			_options.add_child(VSeparator.new())
			_add_style_choices(PrisonCatalogue.WALLS, false)
		BuildController.Tool.FLOOR:
			_add_style_choices(PrisonCatalogue.FLOORS, true)
		BuildController.Tool.WALL:
			_add_style_choices(PrisonCatalogue.WALLS, false)
		BuildController.Tool.OBJECT:
			_add_choices(PrisonCatalogue.OBJECTS, controller.object_def,
					func(def: Resource) -> void: controller.object_def = def)
		BuildController.Tool.ROOM_TYPE:
			_add_choices(PrisonCatalogue.ROOM_TYPES, controller.room_type,
					func(def: Resource) -> void: controller.room_type = def, "Clear")
		BuildController.Tool.TERRAIN:
			_add_brush_choices()
		BuildController.Tool.PLANTS:
			_add_choices(PrisonCatalogue.PLANTS, controller.plant_def,
					func(def: Resource) -> void: controller.plant_def = def)


## Floor or wall style buttons, with outdoor styles marked.
func _add_style_choices(defs: Array, floors: bool) -> void:
	var current: StringName = controller.floor_style if floors else controller.wall_style
	var group := ButtonGroup.new()
	for def: Resource in defs:
		var label: String = def.display_name + (" (outdoor)" if def.outdoor else "")
		var button := _make_button(label, group)
		button.button_pressed = def.id == current
		var id: StringName = def.id
		button.toggled.connect(func(on: bool) -> void:
			if not on:
				return
			if floors:
				controller.floor_style = id
			else:
				controller.wall_style = id)
		_options.add_child(button)


func _add_brush_choices() -> void:
	var group := ButtonGroup.new()
	for entry: Array in BRUSHES:
		var brush: Terrain.Brush = entry[0]
		var button := _make_button(entry[1], group)
		button.button_pressed = controller.terrain_brush == brush
		button.toggled.connect(func(on: bool) -> void:
			if on:
				controller.terrain_brush = brush)
		_options.add_child(button)


## One toggle button per definition. The first is picked if nothing is yet.
func _add_choices(defs: Array, current: Resource, pick: Callable, none_label := "") -> void:
	var group := ButtonGroup.new()
	var entries: Array = defs.duplicate()
	if not none_label.is_empty():
		entries.append(null)
	if current == null and none_label.is_empty():
		current = defs[0]
		pick.call(current)
	for def: Resource in entries:
		var label: String = def.display_name if def != null else none_label
		var button := _make_button(label, group)
		button.button_pressed = def == current
		button.toggled.connect(func(on: bool) -> void:
			if on:
				pick.call(def))
		_options.add_child(button)


func _make_button(text: String, group: ButtonGroup = null) -> Button:
	var button := Button.new()
	button.text = text
	button.toggle_mode = true
	button.button_group = group
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(0, 36)
	return button
