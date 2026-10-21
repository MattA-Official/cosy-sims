class_name Inspector
extends Node3D
## A developer inspector, shown with the debug view (F3). With no build
## tool in hand, click a person, object, room or tile to see everything
## about it in a panel on the left, and change it: set a person's needs,
## rename them, send them somewhere or remove them; remove an object; add
## a prisoner on a tile. The selected person's route is drawn on the ground.
## With a clock, it can jump to any hour to test the timetable. The game
## can also offer ready-made layouts to switch to.

@export var cursor: GridCursor
@export var controller: BuildController
@export var debug_overlay: DebugOverlay
@export var room_types: Array[RoomTypeDef] = []
@export var route_colour := Color(1.0, 0.85, 0.2, 0.9)

var people: People
var building: Building
var clock: GameClock
var runner: ScheduleRunner
## Buttons offered under a person, each [text, tooltip, pressed (person),
## shown (person) -> bool], such as the prison's "Search them".
var person_actions: Array = []
## Drop-downs offered under a person, each [title, tooltip, choices
## (person) -> Array of [value, words], current (person) -> value, pick
## (person, value), shown (person) -> bool], such as a prisoner's course.
var person_pickers: Array = []
## (person) -> String: lines the game adds at the top of a person's
## details, such as a prisoner's sentence. Empty strings are skipped.
var person_lines: Array[Callable] = []

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
var _mood_face: TextureRect
var _mood_text: Label
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
	_mood_face = null
	_mood_text = null
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
	if clock != null:
		_show_clock()
	if not _samples.is_empty():
		_show_samples()


## Jumping the clock to an hour, to test the timetable.
func _show_clock() -> void:
	var row := HBoxContainer.new()
	var picker := OptionButton.new()
	for hour in Schedule.HOURS:
		var def := runner.schedules.values()[0].at(hour) as ActivityDef if runner != null \
				and not runner.schedules.is_empty() else null
		picker.add_item("%s  %s" % [GameClock.hour_text(hour), def.display_name if def != null else ""])
	picker.selected = (clock.hour() + 1) % Schedule.HOURS
	picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(picker)
	var jump := Button.new()
	jump.text = "Jump"
	jump.tooltip_text = "Moves the clock straight to that hour, today or tomorrow."
	jump.pressed.connect(func() -> void: clock.jump_to_hour(picker.selected))
	row.add_child(jump)
	_box.add_child(row)


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
	var traits := PackedStringArray()
	for t in person.traits:
		traits.append("%s: %s" % [t.display_name, t.description])
	if not traits.is_empty():
		_text("\n".join(traits)).theme_type_variation = &"SubtleLabel"
	if people.jobs != null and person.role == &"" and not people.jobs.programmes.is_empty():
		_show_programme(person)
	for picker: Array in person_pickers:
		if (picker[5] as Callable).call(person):
			_picker(person, picker)
	for action: Array in person_actions:
		if (action[3] as Callable).call(person):
			_button(action[0], func() -> void: (action[2] as Callable).call(person)).tooltip_text = action[1]
	var mood_row := HBoxContainer.new()
	_mood_face = TextureRect.new()
	_mood_face.custom_minimum_size = Vector2(32, 32)
	_mood_face.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_mood_face.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	mood_row.add_child(_mood_face)
	_mood_text = Label.new()
	_mood_text.add_theme_font_size_override("font_size", 15)
	_mood_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_mood_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mood_row.add_child(_mood_text)
	_box.add_child(mood_row)
	_live_text = _text("")
	for def in people.needs:
		if not person.needs.has(def.id):
			continue
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


## A game's drop-down for a person (see person_pickers).
func _picker(person: Person, picker: Array) -> void:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = picker[0]
	label.tooltip_text = picker[1]
	label.mouse_filter = Control.MOUSE_FILTER_PASS
	row.add_child(label)
	var choices: Array = (picker[2] as Callable).call(person)
	var current: Variant = (picker[3] as Callable).call(person)
	var drop := OptionButton.new()
	drop.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	drop.tooltip_text = picker[1]
	for choice: Array in choices:
		drop.add_item(choice[1])
		if choice[0] == current:
			drop.selected = drop.item_count - 1
	drop.item_selected.connect(func(index: int) -> void:
		(picker[4] as Callable).call(person, choices[index][0])
		_rebuild.call_deferred())
	row.add_child(drop)
	_box.add_child(row)


## Which work programme someone is on, to change.
func _show_programme(person: Person) -> void:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = "Work programme"
	row.add_child(label)
	var picker := OptionButton.new()
	picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	picker.add_item("None")
	var ids: Array[StringName] = [&""]
	for id: StringName in people.jobs.programmes:
		var def := people.jobs.programmes[id]
		picker.add_item(def.display_name)
		picker.set_item_tooltip(ids.size(), def.description)
		ids.append(id)
	picker.selected = maxi(ids.find(person.programme), 0)
	picker.item_selected.connect(func(index: int) -> void:
		if person.job != null:
			people.stop(person)
		person.programme = ids[index])
	row.add_child(picker)
	_box.add_child(row)


func _refresh_person(person: Person) -> void:
	if _live_text == null:
		return
	var face := people.face(person)
	_mood_face.texture = people.face_textures[face]
	var why := PackedStringArray()
	for part: Array in person.mood_parts.slice(0, 3):
		why.append("%s %+d" % [part[0], roundi(part[1])])
	_mood_text.text = "%s, mood %d\nWhy? %s" % [MoodModel.FACE_NAMES[face], roundi(person.mood),
			", ".join(why) if not why.is_empty() else "nothing much"]
	var target := people.target_object(person)
	var group: GroupDef = people.access.groups.get(person.group)
	var lines := PackedStringArray()
	for extra in person_lines:
		var line: String = extra.call(person)
		if not line.is_empty():
			lines.append(line)
	lines.append_array(PackedStringArray([
		"Group: %s" % (group.display_name if group != null else String(person.group))
				+ (", %s" % _role_name(person) if person.role != &"" else "")
				+ (", %s shift" % person.shift if person.shift != &"" else "")
				+ (", going home" if person.going_home else ""),
		"Doing: %s" % person.activity,
		"Because: %s" % (person.reason if not person.reason.is_empty() else "-"),
		"State: %s" % ["idle", "walking", "using an object"][person.state],
		"Where: %s, tile %d, %d, %.2f m up" % [Building.level_name(person.level),
				floori(person.position.x), floori(person.position.z), person.position.y],
		"Heading for: %s" % (target.def.display_name if target != null else "nothing in particular"),
		"Steps left on the way: %d" % person.route.size(),
	]))
	if person.job != null:
		var stage := person.job.current()
		lines.append("Job: %s%s" % [person.job.title, ", %s" % stage.doing.to_lower()
				if stage != null and not stage.doing.is_empty() else ""])
	var carrying := people.items.carrying(person) if people.items != null else null
	if carrying != null:
		lines.append("Carrying: %d × %s" % [people.items.carried[person][1], carrying.display_name.to_lower()])
	if person.block != null:
		lines.append("Block: %s, %s" % [person.block.display_name,
				"in place" if people.is_in_place(person) else ("out of place" if person.out_of_place
				else "on the way")])
	if person.health < Health.WELL:
		lines.append("Health: %d, %s" % [roundi(person.health), Health.words(person.health).to_lower()])
	if person.temper > 0.5 or not person.record.is_empty():
		lines.append("Temper: %d%s" % [roundi(person.temper), ", about to act up" if person.warning != &""
				else (", up to no good" if person.truant_minutes > 0.0 else "")]
				+ (", mostly %s" % _worst_worry(person) if person.temper > 0.5 else ""))
	if person.points > 0.0:
		lines.append("Points on record: %.1f" % person.points)
	for id: StringName in person.restrictions:
		var privilege: PrivilegeDef = people.privileges.get(id)
		lines.append("Lost %s: %d days left" % [privilege.display_name.to_lower() if privilege != null else String(id),
				ceili(person.restrictions[id])])
	if person.quiet_room_hours > 0.0:
		lines.append("Quiet room: %d hours left" % ceili(person.quiet_room_hours))
	for entry: Array in person.record.slice(-5):
		lines.append("Record: day %d, %s" % [entry[0], entry[2]])
	var home := people.home_room(person)
	lines.append("Bed: %s" % ("none of their own" if home.is_empty()
			else "in a room on the %s" % Building.level_name(home[0]).to_lower()))
	lines.append("Here: %s%s" % ["outdoors" if person.outdoors else "indoors",
			", with company" if person.in_company else ""])
	for id: StringName in person.moodlets:
		var def: MoodletDef = people.moodlet_defs.get(id)
		if def != null:
			lines.append("%s %+d, %s left" % [def.display_name, roundi(def.mood),
					_duration(person.moodlets[id])])
	for part: Array in person.mood_parts.slice(3):
		lines.append("Mood: %s %+.1f" % part)
	_live_text.text = "\n".join(lines)
	for need: StringName in _need_sliders:
		var slider := _need_sliders[need]
		if not slider.has_focus():
			slider.set_value_no_signal(person.needs.get(need, 0.0))


## The worst thing on someone's mind, in lower case.
func _worst_worry(person: Person) -> String:
	var worst: Array = []
	for part: Array in person.mood_parts:
		if part[1] < 0.0 and (worst.is_empty() or part[1] < worst[1]):
			worst = part
	return String(worst[0]).to_lower() if not worst.is_empty() else "fed up"


func _role_name(person: Person) -> String:
	var role: StaffRoleDef = people.jobs.roles.get(person.role) if people.jobs != null else null
	return role.display_name.to_lower() if role != null else String(person.role)


## "2 h 30 min", "45 min"
static func _duration(minutes: float) -> String:
	var whole := roundi(minutes)
	if whole < 60:
		return "%d min" % whole
	return "%d h %d min" % [whole / 60, whole % 60] if whole % 60 != 0 else "%d h" % (whole / 60)


func _show_object(level: int, id: int) -> void:
	var map := building.levels.get(level) as BuildingMap
	var placed: BuildingMap.PlacedObject = map.objects.get(id) if map != null else null
	if placed == null:
		_text("That object has gone.")
		return
	var user := people.user_of(level, id) if people != null else null
	var owner := people.owner_of(level, id) if people != null else null
	_text("%s\n%s\nTags: %s\nCentre: %.2f, %.2f\nTurned: %d°\nSize: %s tiles\nIn use: %s%s" % [
		placed.def.display_name, Building.level_name(level), ", ".join(placed.def.tags),
		placed.centre.x, placed.centre.y, roundi(rad_to_deg(placed.angle)),
		"%s by %s" % [String.num(placed.def.size.x), String.num(placed.def.size.y)],
		user.name if user != null else "no", "\nBelongs to: %s" % owner.name if owner != null else ""])
	if user != null:
		_button("Inspect %s" % user.name, func() -> void: select(user))
	if owner != null and owner != user:
		_button("Inspect %s" % owner.name, func() -> void: select(owner))
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
	if people != null:
		var zone := people.access.zone_of(room)
		if zone != null:
			_text("Who may be here: %s%s" % [zone.display_name,
					"" if room.zone.is_empty() else " (painted)"])
	if people != null:
		var quality := people.quality(_selected_level, room)
		var parts := PackedStringArray()
		for part: Array in quality.parts:
			parts.append("%s %+.1f" % part)
		_text("Quality: %s (%+.1f)\n%s" % [quality.star_text(), quality.score, "\n".join(parts)])
		var sleepers := people.owners_in(_selected_level, room)
		if not sleepers.is_empty():
			_text("Sleeps here: %s" % ", ".join(sleepers.map(func(p: Person) -> String: return p.name)))
	var inside := room.cells[0]
	_button("Add a prisoner here", func() -> void: _add_prisoner(inside))
	_button("Add a member of staff here", func() -> void: _add_prisoner(inside, &"staff"))


func _show_tile(cell: Vector2i) -> void:
	_text("Tile %d, %d on the %s" % [cell.x, cell.y, Building.level_name(_selected_level).to_lower()])
	_button("Add a prisoner here", func() -> void: _add_prisoner(cell))
	_button("Add a member of staff here", func() -> void: _add_prisoner(cell, &"staff"))


func _add_prisoner(cell: Vector2i, group: StringName = &"prisoner") -> void:
	var person := people.add_person(_selected_level, Vector2(cell) + Vector2(0.5, 0.5), "", group)
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
