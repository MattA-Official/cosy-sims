class_name Inspector
extends Node3D
## A developer inspector, shown with the debug view (F3). With no build
## tool in hand, click a person, object, room or tile to see everything
## about it in a panel on the left, and change it: set a person's needs,
## rename them, send them somewhere or remove them; remove an object; add
## a prisoner on a tile. The selected person's route is drawn on the ground.
## The game can also offer ready-made layouts to switch to.

@export var cursor: GridCursor
@export var controller: BuildController
@export var debug_overlay: DebugOverlay
@export var room_types: Array[RoomTypeDef] = []
@export var route_colour := Color(1.0, 0.85, 0.2, 0.9)

var people: People
var building: Building

var _layer := CanvasLayer.new()
var _panel := PanelContainer.new()
var _box := VBoxContainer.new()
var _mesh := ImmediateMesh.new()
var _material := MeshShapes.vertex_colour_material(true)

## What is selected: a Person, a [level, object id] pair, a Room, a cell,
## or null.
var _selected: Variant = null
var _selected_level := 0
var _sending := false
## Labels and sliders refreshed every frame for the selected person.
var _live_text: Label
var _need_sliders: Dictionary[StringName, HSlider] = {}
## Ready-made layouts the game offers, what each is for, and how to load one.
var _samples: Array[String] = []
var _sample_notes: Array[String] = []
var _current_sample := -1
var _load_sample: Callable


func _ready() -> void:
	var instance := MeshInstance3D.new()
	instance.mesh = _mesh
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(instance)
	_layer.layer = 10
	add_child(_layer)
	_panel.offset_left = 12.0
	_panel.offset_top = 120.0
	_panel.custom_minimum_size = Vector2(330, 0)
	_panel.add_child(_box)
	_layer.add_child(_panel)
	if cursor != null:
		cursor.cell_clicked.connect(_on_cell_clicked)
	if people != null:
		people.person_removed.connect(func(person: Person) -> void:
			if _selected == person:
				select(null))
	_rebuild()


func _process(_delta: float) -> void:
	var on := debug_overlay == null or debug_overlay.visible
	_panel.visible = on
	_mesh.clear_surfaces()
	if not on:
		return
	if _selected is Person:
		_refresh_person(_selected)
		_draw_person(_selected)


## Selects something to inspect, or nothing with null.
func select(thing: Variant, level := 0) -> void:
	_selected = thing
	_selected_level = level
	_sending = false
	_rebuild()


func selected() -> Variant:
	return _selected


## Lists layouts to switch to at the foot of the panel. `load` takes the
## chosen index.
func offer_samples(names: Array[String], notes: Array[String], current: int, load: Callable) -> void:
	_samples = names
	_sample_notes = notes
	_current_sample = current
	_load_sample = load
	_rebuild()


func _on_cell_clicked(cell: Vector2i, button: MouseButton) -> void:
	if button != MOUSE_BUTTON_LEFT or (debug_overlay != null and not debug_overlay.visible):
		return
	if controller != null and controller.tool != BuildController.Tool.NONE:
		return
	var level := building.active if building != null else 0
	var spot := Vector2(cell) + Vector2(0.5, 0.5)
	if _sending and _selected is Person:
		people.send(_selected, level, spot)
		_sending = false
		_rebuild()
		return
	var person := _person_under_mouse()
	if person != null:
		select(person)
		return
	var map := building.levels.get(level) as BuildingMap
	if map == null:
		select(cell, level)
		return
	var placed := map.object_at(spot)
	if placed != null:
		select([level, placed.id], level)
	elif map.room_at(cell) != null:
		select(map.room_at(cell), level)
	else:
		select(cell, level)


## The person drawn nearest the mouse, if any is close enough.
func _person_under_mouse() -> Person:
	var camera := get_viewport().get_camera_3d()
	if camera == null or people == null:
		return null
	var mouse := get_viewport().get_mouse_position()
	var best: Person = null
	var best_distance := 36.0
	var active := building.active if building != null else 0
	for person in people.people:
		if person.level > active:
			continue
		var at := Vector3(person.position.x, person.position.y + 0.45, person.position.z)
		if camera.is_position_behind(at):
			continue
		var distance := camera.unproject_position(at).distance_to(mouse)
		if distance < best_distance:
			best = person
			best_distance = distance
	return best


func _rebuild() -> void:
	for child in _box.get_children():
		child.queue_free()
	_need_sliders.clear()
	_live_text = null
	_heading("Inspector")
	if _selected is Person:
		_show_person(_selected)
	elif _selected is Array:
		_show_object(_selected[0], _selected[1])
	elif _selected is Room:
		_show_room(_selected)
	elif _selected is Vector2i:
		_show_tile(_selected)
	else:
		_text("Click a person, object, room or tile. Pick no build tool first (Esc).")
	_box.add_child(HSeparator.new())
	if people != null:
		_text("%d people" % people.people.size())
		var pause := _button("Pause people" if not people.paused else "Carry on", func() -> void:
			people.paused = not people.paused
			_rebuild())
		pause.tooltip_text = "Stops everyone where they are."
	if not _samples.is_empty():
		_show_samples()


func _show_samples() -> void:
	_box.add_child(HSeparator.new())
	_text("Sample prisons")
	var picker := OptionButton.new()
	for name in _samples:
		picker.add_item(name)
	picker.selected = clampi(_current_sample, 0, _samples.size() - 1)
	_box.add_child(picker)
	var note := _text(_sample_notes[picker.selected] if picker.selected < _sample_notes.size() else "")
	picker.item_selected.connect(func(index: int) -> void:
		note.text = _sample_notes[index] if index < _sample_notes.size() else "")
	_button("Load this sample (starts again)", func() -> void: _load_sample.call(picker.selected))


func _show_person(person: Person) -> void:
	var name_edit := LineEdit.new()
	name_edit.text = person.name
	name_edit.text_submitted.connect(func(text: String) -> void: person.name = text)
	name_edit.text_changed.connect(func(text: String) -> void: person.name = text)
	_box.add_child(name_edit)
	_live_text = _text("")
	for def in people.needs:
		var row := HBoxContainer.new()
		var label := Label.new()
		label.text = def.display_name
		label.custom_minimum_size = Vector2(80, 0)
		row.add_child(label)
		var slider := HSlider.new()
		slider.min_value = 0.0
		slider.max_value = 100.0
		slider.step = 1.0
		slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slider.value = person.needs.get(def.id, 0.0)
		var id := def.id
		slider.value_changed.connect(func(value: float) -> void: person.needs[id] = value)
		row.add_child(slider)
		_box.add_child(row)
		_need_sliders[def.id] = slider
	_button("Send somewhere (then click a tile)", func() -> void:
		_sending = true
		_rebuild.call_deferred())
	if _sending:
		_text("Click where to send them.")
	_button("Remove person", func() -> void:
		people.remove_person(person))


func _refresh_person(person: Person) -> void:
	if _live_text == null:
		return
	var target := people.target_object(person)
	var lines := PackedStringArray([
		"Doing: %s" % person.activity,
		"State: %s" % ["idle", "walking", "using an object"][person.state],
		"Where: %s, tile %d, %d, %.2f m up" % [Building.level_name(person.level),
				floori(person.position.x), floori(person.position.z), person.position.y],
		"Heading for: %s" % (target.def.display_name if target != null else "nothing in particular"),
		"Steps left on the way: %d" % person.route.size(),
	])
	for need: StringName in person.needs:
		lines.append("%s: %d%s" % [String(need).capitalize(), roundi(person.needs[need]),
				"  (below the line)" if person.needs[need] < People.NEED_LINE else ""])
	_live_text.text = "\n".join(lines)
	for need: StringName in _need_sliders:
		var slider := _need_sliders[need]
		if not slider.has_focus():
			slider.set_value_no_signal(person.needs.get(need, 0.0))


func _show_object(level: int, id: int) -> void:
	var map := building.levels.get(level) as BuildingMap
	var placed: BuildingMap.PlacedObject = map.objects.get(id) if map != null else null
	if placed == null:
		_text("That object has gone.")
		return
	var user := people.user_of(level, id) if people != null else null
	_text("%s\n%s\nTags: %s\nCentre: %.2f, %.2f\nTurned: %d°\nSize: %s tiles\nIn use: %s" % [
		placed.def.display_name, Building.level_name(level), ", ".join(placed.def.tags),
		placed.centre.x, placed.centre.y, roundi(rad_to_deg(placed.angle)),
		"%s by %s" % [String.num(placed.def.size.x), String.num(placed.def.size.y)],
		user.name if user != null else "no"])
	if user != null:
		_button("Inspect %s" % user.name, func() -> void: select(user))
	_button("Remove object", func() -> void:
		map.remove_object(id)
		select(null))


func _show_room(room: Room) -> void:
	var map := building.levels.get(_selected_level) as BuildingMap
	var names := PackedStringArray()
	for placed in map.objects_in_room(room):
		names.append(placed.def.display_name)
	var type_name := "unassigned"
	for def in room_types:
		if def.id == room.type:
			type_name = def.display_name
	_text("Room: %s\n%s\n%d tiles, %s\nObjects: %s" % [type_name, Building.level_name(_selected_level),
			room.cells.size(), "indoors" if room.indoor else ("outdoors" if room.enclosed else "not closed in"),
			", ".join(names) if not names.is_empty() else "none"])
	var inside := room.cells[0]
	_button("Add a prisoner here", func() -> void: _add_prisoner(inside))


func _show_tile(cell: Vector2i) -> void:
	_text("Tile %d, %d on the %s" % [cell.x, cell.y, Building.level_name(_selected_level).to_lower()])
	_button("Add a prisoner here", func() -> void: _add_prisoner(cell))


func _add_prisoner(cell: Vector2i) -> void:
	var person := people.add_person(_selected_level, Vector2(cell) + Vector2(0.5, 0.5))
	if person != null:
		select(person)
	else:
		_text("Nobody can stand there.")


## A ring round the selected person and a line of dots along their route.
func _draw_person(person: Person) -> void:
	_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _material)
	var centre := person.position
	for k in 16:
		var at := centre + Vector3(cos(TAU * k / 16.0), 0.0, sin(TAU * k / 16.0)) * 0.4
		MeshShapes.add_box_immediate(_mesh, at + Vector3.UP * 0.05, Vector3(0.05, 0.03, 0.05), route_colour)
	var from := centre
	for point in person.route:
		var gap := from.distance_to(point)
		var dots := maxi(1, ceili(gap / 0.4))
		for k in dots:
			var at := from.lerp(point, float(k + 1) / dots)
			MeshShapes.add_box_immediate(_mesh, at + Vector3.UP * 0.08, Vector3(0.06, 0.04, 0.06), route_colour)
		from = point
	_mesh.surface_end()


func _heading(text: String) -> void:
	var label := _text(text)
	label.theme_type_variation = &"HeaderLabel"
	label.remove_theme_font_size_override("font_size")


func _text(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 15)
	_box.add_child(label)
	return label


func _button(text: String, pressed: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.pressed.connect(pressed)
	_box.add_child(button)
	return button
