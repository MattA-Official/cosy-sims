class_name SavesWindow
extends PanelContainer
## Saving and loading: the autosave from this morning and three slots,
## each with what's in it. Toggle with F2.

## (slot) -> void: saves into a slot.
var save: Callable
## (slot) -> void: loads a slot.
var load_slot: Callable

var _rows := VBoxContainer.new()


func _ready() -> void:
	set_anchors_and_offsets_preset(PRESET_CENTER_TOP, PRESET_MODE_MINSIZE)
	grow_horizontal = GROW_DIRECTION_BOTH
	offset_top = 76.0
	custom_minimum_size = Vector2(560, 0)
	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", 8)
	add_child(box)
	var heading := HBoxContainer.new()
	var title := Label.new()
	title.text = "Save and load"
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
	var note := Label.new()
	note.text = "The prison saves itself each morning at %02d:00. Loading picks up where everyone stands." \
			% 6
	note.theme_type_variation = &"SubtleLabel"
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(note)
	_rows.add_theme_constant_override(&"separation", 6)
	box.add_child(_rows)
	visible = false


func toggle() -> void:
	visible = not visible
	if visible:
		refresh()


func refresh() -> void:
	for child in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()
	_add_row("Autosave", PrisonSave.AUTOSAVE, false)
	for i in PrisonSave.SLOTS.size():
		_add_row("Slot %d" % (i + 1), PrisonSave.SLOTS[i], true)


func _add_row(name_text: String, slot: String, can_save: bool) -> void:
	var data := PrisonSave.read(slot)
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 8)
	var name_label := Label.new()
	name_label.text = name_text
	name_label.theme_type_variation = &"HeaderLabel"
	name_label.custom_minimum_size = Vector2(90, 0)
	row.add_child(name_label)
	var about := Label.new()
	about.text = PrisonSave.describe(data)
	about.theme_type_variation = &"SubtleLabel"
	about.size_flags_horizontal = SIZE_EXPAND_FILL
	about.clip_text = true
	about.tooltip_text = "Saved %s" % data.get("saved_at", "") if not data.is_empty() else ""
	about.mouse_filter = MOUSE_FILTER_PASS
	row.add_child(about)
	if can_save:
		var save_button := Button.new()
		save_button.text = "Save"
		save_button.focus_mode = FOCUS_NONE
		save_button.pressed.connect(func() -> void:
			save.call(slot)
			refresh())
		row.add_child(save_button)
	var load_button := Button.new()
	load_button.text = "Load"
	load_button.focus_mode = FOCUS_NONE
	load_button.disabled = data.is_empty()
	load_button.pressed.connect(func() -> void: load_slot.call(slot))
	row.add_child(load_button)
	_rows.add_child(row)
