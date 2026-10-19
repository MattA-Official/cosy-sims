extends VBoxContainer
## The build toolbar along the bottom of the screen: a row of tools, a row of
## choices for the current tool (which object, which room type), and a hint.
## Number keys 1 to 9, then 0, pick tools.

@export var controller: BuildController

const TOOLS := [
	[BuildController.Tool.ROOM, "Room"],
	[BuildController.Tool.FLOOR, "Floor"],
	[BuildController.Tool.WALL, "Wall"],
	[BuildController.Tool.OPENING, "Doors and windows"],
	[BuildController.Tool.OBJECT, "Objects"],
	[BuildController.Tool.ROOM_TYPE, "Room type"],
	[BuildController.Tool.DEMOLISH, "Demolish"],
	[BuildController.Tool.TERRAIN, "Terrain"],
	[BuildController.Tool.PLANTS, "Plants"],
	[BuildController.Tool.PATH, "Paths"],
]

const FLOOR_MODES := [
	[BuildController.FloorMode.LAY, "Lay"],
	[BuildController.FloorMode.RAISE, "Raise"],
	[BuildController.FloorMode.LOWER, "Lower"],
]

const PATH_MODES := [
	[PathTool.Mode.STRAIGHT, "Straight"],
	[PathTool.Mode.CURVED, "Curved"],
	[PathTool.Mode.FREEHAND, "Freehand"],
]

const OPENINGS := [
	[BuildingMap.Wall.DOOR, &"", "Door"],
	[BuildingMap.Wall.WINDOW, BuildingMap.WINDOW_GLASS, "Glass window"],
	[BuildingMap.Wall.WINDOW, BuildingMap.WINDOW_BARS, "Barred window"],
]

const WATER_MODES := [
	[BuildController.WaterMode.ADD, "Add water"],
	[BuildController.WaterMode.REMOVE, "Drain water"],
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
		var button := _make_button("%d  %s" % [(i + 1) % 10, TOOLS[i][1]], _tool_group)
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
	var index := 9 if key.physical_keycode == KEY_0 else key.physical_keycode - KEY_1
	if index >= 0 and index < TOOLS.size():
		var tool: BuildController.Tool = TOOLS[index][0]
		controller.tool = BuildController.Tool.NONE if controller.tool == tool else tool
		get_viewport().set_input_as_handled()


func _on_tool_changed(tool: BuildController.Tool) -> void:
	for t: BuildController.Tool in _tool_buttons:
		_tool_buttons[t].set_pressed_no_signal(t == tool)
	_hint.text = controller.hint()
	for child in _options.get_children():
		child.queue_free()
	match tool:
		BuildController.Tool.ROOM:
			_add_style_choices(PrisonCatalogue.FLOORS, true)
			_options.add_child(VSeparator.new())
			_add_style_choices(PrisonCatalogue.WALLS, false)
		BuildController.Tool.FLOOR:
			_add_floor_mode_choices()
			_options.add_child(VSeparator.new())
			_add_style_choices(PrisonCatalogue.FLOORS, true)
		BuildController.Tool.WALL:
			_add_style_choices(PrisonCatalogue.WALLS, false)
		BuildController.Tool.OBJECT:
			_add_choices(PrisonCatalogue.OBJECTS, controller.object_def,
					func(def: Resource) -> void: controller.object_def = def)
		BuildController.Tool.ROOM_TYPE:
			_add_choices(PrisonCatalogue.ROOM_TYPES, controller.room_type,
					func(def: Resource) -> void: controller.room_type = def, "Clear")
		BuildController.Tool.OPENING:
			_add_opening_choices()
		BuildController.Tool.TERRAIN:
			_add_brush_choices()
		BuildController.Tool.PATH:
			_add_path_choices()
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


func _add_floor_mode_choices() -> void:
	var group := ButtonGroup.new()
	for entry: Array in FLOOR_MODES:
		var mode: BuildController.FloorMode = entry[0]
		var button := _make_button(entry[1], group)
		button.button_pressed = controller.floor_mode == mode
		button.toggled.connect(func(on: bool) -> void:
			if on:
				controller.floor_mode = mode
				_hint.text = controller.hint())
		_options.add_child(button)


func _add_path_choices() -> void:
	var modes := ButtonGroup.new()
	for entry: Array in PATH_MODES:
		var mode: PathTool.Mode = entry[0]
		var button := _make_button(entry[1], modes)
		button.button_pressed = controller.path_tool.mode == mode
		button.toggled.connect(func(on: bool) -> void:
			if on:
				controller.path_tool.cancel()
				controller.path_tool.mode = mode
				_hint.text = controller.hint())
		_options.add_child(button)
	_options.add_child(VSeparator.new())
	if controller.path_tool.style.is_empty():
		controller.path_tool.style = PrisonCatalogue.PATHS[0].id
	var styles := ButtonGroup.new()
	for def in PrisonCatalogue.PATHS:
		var button := _make_button(def.display_name, styles)
		button.button_pressed = controller.path_tool.style == def.id
		var id := def.id
		button.toggled.connect(func(on: bool) -> void:
			if on:
				controller.path_tool.style = id)
		_options.add_child(button)


func _add_opening_choices() -> void:
	var group := ButtonGroup.new()
	for entry: Array in OPENINGS:
		var kind: BuildingMap.Wall = entry[0]
		var window: StringName = entry[1]
		var button := _make_button(entry[2], group)
		button.button_pressed = controller.opening == kind \
				and (kind != BuildingMap.Wall.WINDOW or controller.window_kind == window)
		button.toggled.connect(func(on: bool) -> void:
			if not on:
				return
			controller.opening = kind
			if kind == BuildingMap.Wall.WINDOW:
				controller.window_kind = window)
		_options.add_child(button)


## Sculpting brushes, then the water modes, as one set of choices.
func _add_brush_choices() -> void:
	var group := ButtonGroup.new()
	for entry: Array in BRUSHES:
		var brush: Terrain.Brush = entry[0]
		var button := _make_button(entry[1], group)
		button.button_pressed = controller.water_mode == BuildController.WaterMode.NONE \
				and controller.terrain_brush == brush
		button.toggled.connect(func(on: bool) -> void:
			if on:
				controller.terrain_brush = brush
				controller.water_mode = BuildController.WaterMode.NONE
				_hint.text = controller.hint())
		_options.add_child(button)
	_options.add_child(VSeparator.new())
	for entry: Array in WATER_MODES:
		var mode: BuildController.WaterMode = entry[0]
		var button := _make_button(entry[1], group)
		button.button_pressed = controller.water_mode == mode
		button.toggled.connect(func(on: bool) -> void:
			if on:
				controller.water_mode = mode
				_hint.text = controller.hint())
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
