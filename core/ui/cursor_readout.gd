class_name CursorReadout
extends PanelContainer
## A small label by the mouse saying what a drag would build and cost, red
## when you can't afford it, or a room type's checklist while marking
## rooms. Reads BuildController.readout() each frame.

const OFFSET := Vector2(20, 18)
const SHORT_COLOUR := Color(0.75, 0.35, 0.32)

var controller: BuildController

var _label := Label.new()


func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	theme_type_variation = &"TooltipPanel"
	_label.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(_label)
	visible = false


func _process(_delta: float) -> void:
	var said: Array = controller.readout() if controller != null else []
	visible = not said.is_empty()
	if not visible:
		return
	_label.text = said[0]
	if said[1]:
		_label.remove_theme_color_override(&"font_color")
	else:
		_label.add_theme_color_override(&"font_color", SHORT_COLOUR)
	reset_size()
	var at := get_viewport().get_mouse_position() + OFFSET
	var room := get_viewport_rect().size - size
	position = at.clamp(Vector2.ZERO, room)
