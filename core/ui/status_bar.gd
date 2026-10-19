class_name StatusBar
extends PanelContainer
## The rounded bar across the top of the screen: a row of short readouts
## (the level, the room under the mouse, how many people) with dividers
## between them. Readouts appear in the order they are first set.
##
##   status.set_item(&"level", "Ground floor", &"HeaderLabel")
##   status.set_item(&"room", "Cell, 16 tiles")
##   status.remove_item(&"room")

var _row := HBoxContainer.new()
var _items := {} # key -> Label


func _ready() -> void:
	theme_type_variation = &"HudBar"
	set_anchors_and_offsets_preset(PRESET_CENTER_TOP)
	grow_horizontal = GROW_DIRECTION_BOTH
	offset_top = 12.0
	mouse_filter = MOUSE_FILTER_IGNORE
	_row.add_theme_constant_override(&"separation", 12)
	_row.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(_row)
	visible = false


## Shows `text` for `key`, adding it at the end if it is new. `variation` is
## a Label theme type such as HeaderLabel or SubtleLabel.
func set_item(key: StringName, text: String, variation := &"") -> void:
	var label: Label = _items.get(key)
	if label == null:
		if not _items.is_empty():
			var divider := VSeparator.new()
			divider.name = "Divider_" + key
			_row.add_child(divider)
		label = Label.new()
		label.name = key
		label.size_flags_vertical = SIZE_SHRINK_CENTER
		_row.add_child(label)
		_items[key] = label
	label.theme_type_variation = variation
	label.text = text
	visible = true
	_recentre.call_deferred()


func remove_item(key: StringName) -> void:
	var label: Label = _items.get(key)
	if label == null:
		return
	_items.erase(key)
	var index := label.get_index()
	label.queue_free()
	# Take the divider before it, or after it if it was first.
	var divider := _row.get_child(index - 1) if index > 0 else _row.get_child(index + 1) if index + 1 < _row.get_child_count() else null
	if divider is VSeparator:
		divider.queue_free()
	visible = not _items.is_empty()
	_recentre.call_deferred()


func item_text(key: StringName) -> String:
	var label: Label = _items.get(key)
	return label.text if label != null else ""


## Keeps the bar centred as its readouts change width.
func _recentre() -> void:
	reset_size()
	var width := get_combined_minimum_size().x
	offset_left = -width * 0.5
	offset_right = width * 0.5
