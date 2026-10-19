extends CanvasLayer
## Short notes that pop up in the bottom-right corner and fade away, such as
## "Breakfast is served". Loaded as the Toasts autoload, so anything can say:
##   Toasts.post("Breakfast is served", "38 prisoners are heading to the canteen.")

const MAX_SHOWN := 4

var _stack := VBoxContainer.new()


func _ready() -> void:
	layer = 20
	add_child(_stack)
	_stack.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE, 14)
	_stack.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_stack.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_stack.alignment = BoxContainer.ALIGNMENT_END
	_stack.mouse_filter = Control.MOUSE_FILTER_IGNORE


## Shows a note for `seconds`, then fades it out. Returns the note, so a
## caller can free it early.
func post(title: String, body := "", seconds := 6.0) -> Control:
	var note := PanelContainer.new()
	note.theme_type_variation = &"ToastPanel"
	note.mouse_filter = Control.MOUSE_FILTER_IGNORE
	note.custom_minimum_size.x = 280
	var column := VBoxContainer.new()
	column.add_theme_constant_override(&"separation", 2)
	note.add_child(column)
	var heading := Label.new()
	heading.text = title
	heading.theme_type_variation = &"HeaderLabel"
	heading.add_theme_font_size_override(&"font_size", 17)
	column.add_child(heading)
	if not body.is_empty():
		var text := Label.new()
		text.text = body
		text.theme_type_variation = &"SubtleLabel"
		text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		text.custom_minimum_size.x = 250
		column.add_child(text)
	_stack.add_child(note)
	while _stack.get_child_count() > MAX_SHOWN:
		_stack.get_child(0).free()
	var tween := note.create_tween()
	tween.tween_interval(seconds)
	tween.tween_property(note, "modulate:a", 0.0, 0.6)
	tween.tween_callback(note.queue_free)
	return note
