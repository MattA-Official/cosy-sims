class_name StaffWindow
extends PanelContainer
## Who works here. A row for each staff role with how many there are and
## buttons to take one on or let one go, and a row for each work programme
## with how many prisoners are on it and buttons to put one more on or
## take one off. Staff are free for now and always on site; shifts and
## wages come later. Toggle with P.

## Take on someone for a role, or let one go.
signal hire_pressed(role: StringName)
signal fire_pressed(role: StringName)

## Seconds between counting everyone again while open.
const REFRESH_SECONDS := 0.5

var roles: Array[StaffRoleDef] = []
var programmes: Array[WorkProgrammeDef] = []
var people: People
## Who goes on work programmes.
var programme_group: StringName = &"prisoner"

var _counts: Dictionary[StringName, Label] = {}
var _programme_counts: Dictionary[StringName, Label] = {}
var _free_text := Label.new()
var _wait := 0.0


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
	title.text = "Staff"
	title.theme_type_variation = &"HeaderLabel"
	heading.add_child(title)
	var note := Label.new()
	note.text = "Free for now, and always on site"
	note.theme_type_variation = &"SubtleLabel"
	note.size_flags_vertical = SIZE_SHRINK_CENTER
	heading.add_child(note)
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

	for def in roles:
		box.add_child(_row(def.icon, def.display_name, def.description, _counts, def.id,
				func() -> void: hire_pressed.emit(def.id),
				func() -> void: fire_pressed.emit(def.id)))

	if not programmes.is_empty():
		box.add_child(HSeparator.new())
		var work := Label.new()
		work.text = "Work programmes"
		work.theme_type_variation = &"HeaderLabel"
		box.add_child(work)
		_free_text.theme_type_variation = &"SubtleLabel"
		_free_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(_free_text)
		for def in programmes:
			box.add_child(_row(def.icon, def.display_name, def.description, _programme_counts, def.id,
					func() -> void: _put_on(def.id), func() -> void: _take_off(def.id)))
	visible = false
	refresh()


func _process(delta: float) -> void:
	if not visible:
		return
	_wait -= delta
	if _wait <= 0.0:
		_wait = REFRESH_SECONDS
		refresh()


func toggle() -> void:
	visible = not visible
	refresh()


## Counts everyone again.
func refresh() -> void:
	if people == null:
		return
	for role: StringName in _counts:
		_counts[role].text = str(_with(func(p: Person) -> bool: return p.role == role).size())
	for programme: StringName in _programme_counts:
		_programme_counts[programme].text = str(_with(func(p: Person) -> bool:
				return p.programme == programme).size())
	if not _programme_counts.is_empty():
		var free := _free().size()
		_free_text.text = "Prisoners on a programme work in work blocks. %d %s on none." % [
				free, "prisoner is" if free == 1 else "prisoners are"]


func _row(icon: Texture2D, text: String, tip: String, counts: Dictionary[StringName, Label],
		id: StringName, more: Callable, fewer: Callable) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 8)
	row.tooltip_text = tip
	var picture := TextureRect.new()
	picture.texture = icon
	picture.custom_minimum_size = Vector2(28, 28)
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	row.add_child(picture)
	# White line icons take the theme's ink, known once in the tree.
	picture.ready.connect(func() -> void: picture.modulate = picture.get_theme_color(&"font_color", &"Label"))
	var name_label := Label.new()
	name_label.text = text
	name_label.size_flags_horizontal = SIZE_EXPAND_FILL
	name_label.tooltip_text = tip
	name_label.mouse_filter = MOUSE_FILTER_PASS
	row.add_child(name_label)
	var minus := Button.new()
	minus.text = "−"
	minus.focus_mode = FOCUS_NONE
	minus.custom_minimum_size = Vector2(32, 0)
	minus.pressed.connect(func() -> void:
		fewer.call()
		refresh())
	row.add_child(minus)
	var count := Label.new()
	count.custom_minimum_size = Vector2(28, 0)
	count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	counts[id] = count
	row.add_child(count)
	var plus := Button.new()
	plus.text = "+"
	plus.focus_mode = FOCUS_NONE
	plus.custom_minimum_size = Vector2(32, 0)
	plus.pressed.connect(func() -> void:
		more.call()
		refresh())
	row.add_child(plus)
	return row


## Puts the first prisoner on no programme onto one.
func _put_on(programme: StringName) -> void:
	var free := _free()
	if not free.is_empty():
		free[0].programme = programme


## Takes the last one on a programme off it.
func _take_off(programme: StringName) -> void:
	var on := _with(func(p: Person) -> bool: return p.programme == programme)
	if not on.is_empty():
		var person: Person = on.back()
		if person.job != null:
			people.stop(person)
		person.programme = &""


func _free() -> Array:
	return _with(func(p: Person) -> bool: return p.group == programme_group and p.programme == &"")


func _with(test: Callable) -> Array:
	return people.people.filter(test)
