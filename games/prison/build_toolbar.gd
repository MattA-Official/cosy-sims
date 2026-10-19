extends VBoxContainer
## The build toolbar along the bottom of the screen: a row of tool icons, a
## bar of choices for the current tool above it, and a hint. Choices from the
## catalogue (objects, floors, walls, rooms, plants, paths) are picture tiles
## with their name on hover, so new entries slot in without new code.
## Number keys 1 to 9, then 0, pick tools.

@export var controller: BuildController

const TOOLS := [
	[BuildController.Tool.ROOM, "Room", "Drag out a floor with walls all round.", "tool_room"],
	[BuildController.Tool.FLOOR, "Floor", "Lay or restyle floors, and build stairs.", "tool_floor"],
	[BuildController.Tool.WALL, "Wall", "Build or restyle walls, fences and hedges.", "tool_wall"],
	[BuildController.Tool.OPENING, "Doors and windows", "Put a door or window in a wall.", "tool_opening"],
	[BuildController.Tool.OBJECT, "Objects", "Place beds, tables, showers and more.", "tool_object"],
	[BuildController.Tool.ROOM_TYPE, "Room type", "Mark a room as a cell, canteen and so on.", "tool_room_type"],
	[BuildController.Tool.DEMOLISH, "Demolish", "Remove objects and walls, or clear an area.", "tool_demolish"],
	[BuildController.Tool.TERRAIN, "Terrain", "Shape the ground, or add and drain water.", "tool_terrain"],
	[BuildController.Tool.PLANTS, "Plants", "Plant trees, bushes and flowers.", "tool_plants"],
	[BuildController.Tool.PATH, "Paths", "Lay paths and roads, with stairs and bridges.", "tool_path"],
]

const ICONS := "res://core/ui/icons/%s.svg"

const FLOOR_MODES := [
	[BuildController.FloorMode.LAY, "Lay"],
	[BuildController.FloorMode.RAISE, "Raise"],
	[BuildController.FloorMode.LOWER, "Lower"],
	[BuildController.FloorMode.RAMP, "Ramp"],
	[BuildController.FloorMode.STAIRS, "Stairs"],
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
var _options_bar := PanelContainer.new()
var _tool_buttons := {} # Tool -> Button
var _tool_group := ButtonGroup.new()
var _walls_button: Button
var _thumbnails := Thumbnails.new()


func _ready() -> void:
	alignment = BoxContainer.ALIGNMENT_END
	add_child(_thumbnails)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Only the buttons should catch the mouse, so clicks elsewhere on this
	# full-width strip still reach the build tools.
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_options.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.theme_type_variation = &"HudLabel"
	add_child(_hint)
	_options_bar.theme_type_variation = &"HudBar"
	_options_bar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_options_bar.add_child(_options)
	add_child(_options_bar)

	var tools_bar := PanelContainer.new()
	tools_bar.theme_type_variation = &"HudBar"
	tools_bar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	add_child(tools_bar)
	var tools := HBoxContainer.new()
	tools_bar.add_child(tools)
	for i in TOOLS.size():
		var tool: BuildController.Tool = TOOLS[i][0]
		var button := _make_tool_button(str((i + 1) % 10), TOOLS[i][1], TOOLS[i][2], TOOLS[i][3], _tool_group)
		button.toggled.connect(func(on: bool) -> void:
			if on:
				controller.tool = tool
			elif controller.tool == tool:
				controller.tool = BuildController.Tool.NONE)
		tools.add_child(button)
		_tool_buttons[tool] = button
	tools.add_child(VSeparator.new())
	_walls_button = _make_tool_button("Tab", "Wall view",
			"Loops through walls up, cutaway, walls down and roofs on.", "tool_walls_view")
	_walls_button.toggle_mode = false
	_walls_button.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_walls_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_walls_button.add_theme_constant_override(&"h_separation", 8)
	_walls_button.pressed.connect(controller.next_wall_view)
	tools.add_child(_walls_button)
	controller.wall_view_changed.connect(_show_wall_view)
	_show_wall_view(controller.wall_view)

	_tool_group.allow_unpress = true
	controller.tool_changed.connect(_on_tool_changed)
	controller.hint_changed.connect(func() -> void: _hint.text = controller.hint())
	_on_tool_changed(controller.tool)


func _show_wall_view(mode: BuildController.WallView) -> void:
	_walls_button.text = BuildController.WALL_VIEW_NAMES[mode]
	# Leave room for the keycap after the words.
	_walls_button.custom_minimum_size.x = _walls_button.get_minimum_size().x + 30.0


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
			_add_room_choices()
		BuildController.Tool.FLOOR:
			_add_floor_mode_choices()
			if controller.floor_mode == BuildController.FloorMode.STAIRS:
				_add_landing_choices()
			_add_style_choices(PrisonCatalogue.FLOORS, true)
		BuildController.Tool.WALL:
			_add_wall_angle_choices()
			_add_style_choices(PrisonCatalogue.WALLS, false)
		BuildController.Tool.OBJECT:
			_add_choices("Objects", PrisonCatalogue.OBJECTS, controller.object_def,
					func(def: Resource) -> void: controller.object_def = def)
		BuildController.Tool.ROOM_TYPE:
			_add_choices("Room types", PrisonCatalogue.ROOM_TYPES, controller.room_type,
					func(def: Resource) -> void: controller.room_type = def, "Clear")
		BuildController.Tool.OPENING:
			_add_opening_choices()
		BuildController.Tool.TERRAIN:
			_add_brush_choices()
		BuildController.Tool.PATH:
			_add_path_choices()
		BuildController.Tool.PLANTS:
			_add_choices("Plants", PrisonCatalogue.PLANTS, controller.plant_def,
					func(def: Resource) -> void: controller.plant_def = def)

	_options_bar.visible = _options.get_children().any(func(c: Node) -> bool:
		return not c.is_queued_for_deletion())


## Floor or wall style buttons, with outdoor styles marked.
func _add_style_choices(defs: Array, floors: bool) -> void:
	var current: StringName = controller.floor_style if floors else controller.wall_style
	var group := ButtonGroup.new()
	var row := _section("Floors" if floors else "Walls")
	for def: Resource in defs:
		var picture: Texture2D = _thumbnails.floor_swatch(def) if floors else _thumbnails.wall_swatch(def)
		var button := CosyButton.tile(def.display_name, _describe(def), picture, false, group)
		button.button_pressed = def.id == current
		var id: StringName = def.id
		button.toggled.connect(func(on: bool) -> void:
			if not on:
				return
			if floors:
				controller.floor_style = id
			else:
				controller.wall_style = id)
		row.add_child(button)


## Every floor with every wall of the same kind (indoor or outdoor), each
## shown as a cut-away corner of a room. Picking one sets both styles.
func _add_room_choices() -> void:
	var group := ButtonGroup.new()
	var row := _section("Rooms")
	for wall: WallDef in PrisonCatalogue.WALLS:
		for floor: FloorDef in PrisonCatalogue.FLOORS:
			if floor.outdoor != wall.outdoor:
				continue
			var details := "%s floor, %s walls" % [floor.display_name, wall.display_name.to_lower()]
			if wall.outdoor:
				details += "\nStays outdoors"
			var button := CosyButton.tile("%s and %s" % [wall.display_name, floor.display_name.to_lower()],
					details, _thumbnails.room(floor, wall), false, group)
			button.button_pressed = controller.floor_style == floor.id and controller.wall_style == wall.id
			var floor_id := floor.id
			var wall_id := wall.id
			button.toggled.connect(func(on: bool) -> void:
				if on:
					controller.floor_style = floor_id
					controller.wall_style = wall_id)
			row.add_child(button)


func _add_floor_mode_choices() -> void:
	var group := ButtonGroup.new()
	var row := _section("Mode")
	for entry: Array in FLOOR_MODES:
		var split_only: bool = entry[0] in [BuildController.FloorMode.RAISE,
				BuildController.FloorMode.LOWER, BuildController.FloorMode.RAMP]
		if split_only and not Building.split_levels:
			continue
		var mode: BuildController.FloorMode = entry[0]
		var button := _make_button(entry[1], group)
		button.button_pressed = controller.floor_mode == mode
		button.toggled.connect(func(on: bool) -> void:
			if on and controller.floor_mode != mode:
				controller.floor_mode = mode
				# Stairs bring their own choices, so lay the row out again.
				_on_tool_changed.call_deferred(controller.tool))
		row.add_child(button)


func _add_landing_choices() -> void:
	var group := ButtonGroup.new()
	var row := _section("Landings")
	for entry: Array in [[false, "Square landings"], [true, "Rounded landings"]]:
		var rounded: bool = entry[0]
		var button := _make_button(entry[1], group)
		button.button_pressed = controller.stair_tool.rounded == rounded
		button.toggled.connect(func(on: bool) -> void:
			if on:
				controller.stair_tool.rounded = rounded)
		row.add_child(button)


func _add_wall_angle_choices() -> void:
	var group := ButtonGroup.new()
	var row := _section("Angles")
	for entry: Array in [[false, "Straight and 45°"], [true, "Any angle"]]:
		var any: bool = entry[0]
		var button := _make_button(entry[1], group)
		button.button_pressed = controller.any_angle == any
		button.toggled.connect(func(on: bool) -> void:
			if on:
				controller.any_angle = any)
		row.add_child(button)


func _add_path_choices() -> void:
	var modes := ButtonGroup.new()
	var row := _section("Mode")
	for entry: Array in PATH_MODES:
		var mode: PathTool.Mode = entry[0]
		var button := _make_button(entry[1], modes)
		button.button_pressed = controller.path_tool.mode == mode
		button.toggled.connect(func(on: bool) -> void:
			if on:
				controller.path_tool.cancel()
				controller.path_tool.mode = mode
				_hint.text = controller.hint())
		row.add_child(button)
	var grid := _make_button("Snap to grid")
	grid.button_pressed = controller.path_tool.snap_to_grid
	grid.toggled.connect(func(on: bool) -> void: controller.path_tool.snap_to_grid = on)
	row.add_child(grid)
	if controller.path_tool.style.is_empty():
		controller.path_tool.style = PrisonCatalogue.PATHS[0].id
	var styles := ButtonGroup.new()
	var tiles := _section("Paths")
	for def in PrisonCatalogue.PATHS:
		var button := CosyButton.tile(def.display_name, _describe(def), _thumbnails.path(def), false, styles)
		button.button_pressed = controller.path_tool.style == def.id
		var id := def.id
		button.toggled.connect(func(on: bool) -> void:
			if on:
				controller.path_tool.style = id)
		tiles.add_child(button)


func _add_opening_choices() -> void:
	var group := ButtonGroup.new()
	var row := _section("Openings")
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
		row.add_child(button)


## Sculpting brushes, then the water modes, as one set of choices.
func _add_brush_choices() -> void:
	var group := ButtonGroup.new()
	var row := _section("Brushes")
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
		row.add_child(button)
	row = _section("Water")
	for entry: Array in WATER_MODES:
		var mode: BuildController.WaterMode = entry[0]
		var button := _make_button(entry[1], group)
		button.button_pressed = controller.water_mode == mode
		button.toggled.connect(func(on: bool) -> void:
			if on:
				controller.water_mode = mode
				_hint.text = controller.hint())
		row.add_child(button)


## One picture tile per definition. The first is picked if nothing is yet.
func _add_choices(title: String, defs: Array, current: Resource, pick: Callable, none_label := "") -> void:
	var group := ButtonGroup.new()
	var row := _section(title)
	var entries: Array = defs.duplicate()
	if not none_label.is_empty():
		entries.append(null)
	if current == null and none_label.is_empty():
		current = defs[0]
		pick.call(current)
	for def: Resource in entries:
		var button: CosyButton
		if def == null:
			button = CosyButton.tile(none_label, "Unmark a room.", load(ICONS % "clear"), true, group)
		elif def is RoomTypeDef:
			button = CosyButton.tile(def.display_name, _describe(def), def.icon, true, group)
		elif def is ObjectDef:
			button = CosyButton.tile(def.display_name, _describe(def), _thumbnails.object(def), false, group)
		else:
			button = CosyButton.tile(def.display_name, _describe(def), _thumbnails.plant(def), false, group)
		button.button_pressed = def == current
		button.toggled.connect(func(on: bool) -> void:
			if on:
				pick.call(def))
		row.add_child(button)


## A titled group of choices in the options bar, after a divider if it isn't
## the first. Returns the row to put the choices in.
func _section(title: String) -> HBoxContainer:
	var live := _options.get_children().filter(func(c: Node) -> bool: return not c.is_queued_for_deletion())
	if not live.is_empty():
		_options.add_child(VSeparator.new())
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 4)
	var label := Label.new()
	label.text = title.to_upper()
	label.theme_type_variation = &"TitleLabel"
	label.add_theme_font_size_override("font_size", 12)
	column.add_child(label)
	var row := HBoxContainer.new()
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(row)
	_options.add_child(column)
	return row


## The line or two under a choice's name on its hover card.
func _describe(def: Resource) -> String:
	if def is ObjectDef:
		var size: Vector2 = def.size
		return "%s × %s tiles" % [_number(size.x), _number(size.y)]
	if def is FloorDef:
		return "Outdoor floor" if def.outdoor else "Indoor floor"
	if def is WallDef:
		var kind := "Outdoor" if def.outdoor else "Indoor"
		return "%s, %s m high\n%s" % [kind, _number(def.height),
				"Leaves rooms outdoors" if def.outdoor else "Makes rooms indoors"]
	if def is RoomTypeDef:
		var where: String = ["Indoors", "Outdoors", "Indoors or outdoors"][def.location]
		if def.required_tags.is_empty():
			return where
		var needs := PackedStringArray()
		for tag: StringName in def.required_tags:
			needs.append(String(tag))
		return "%s\nNeeds a %s" % [where, " and a ".join(needs)]
	if def is FoliageDef:
		return ["Tree", "Bush", "Flower"][def.shape]
	if def is PathStyleDef:
		return "%s tiles wide" % _number(def.width)
	return ""


func _number(value: float) -> String:
	return String.num(value, 2)


func _make_button(text: String, group: ButtonGroup = null) -> Button:
	var button := Button.new()
	button.text = text
	button.toggle_mode = true
	button.button_group = group
	button.focus_mode = Control.FOCUS_NONE
	return button


## A tool button: an icon with its shortcut on a keycap in the corner, and
## its name and what it does on hover.
func _make_tool_button(key: String, title: String, details: String, icon_name: String,
		group: ButtonGroup = null) -> CosyButton:
	var button := CosyButton.new()
	button.title = title
	button.details = details + "\nShortcut: " + key
	button.icon = load(ICONS % icon_name)
	button.theme_type_variation = &"ToolButton"
	button.toggle_mode = true
	button.button_group = group
	button.focus_mode = Control.FOCUS_NONE
	button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	button.add_theme_constant_override(&"icon_max_width", 26)
	button.custom_minimum_size = Vector2(58, 50)
	var keycap := Label.new()
	keycap.text = key
	keycap.theme_type_variation = &"KeyLabel"
	keycap.add_theme_font_size_override(&"font_size", 10)
	keycap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(keycap)
	# Tucked into the bottom-right corner, above the button's thick edge.
	keycap.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	keycap.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	keycap.grow_vertical = Control.GROW_DIRECTION_BEGIN
	keycap.offset_left = -4.0
	keycap.offset_right = -4.0
	keycap.offset_top = -7.0
	keycap.offset_bottom = -7.0
	return button
