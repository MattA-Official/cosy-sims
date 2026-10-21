class_name FailCard
extends PanelContainer
## Shown when the game is lost on a hard setting: why, the best night, and
## three ways on.

## Each () -> void.
var keep_playing: Callable
var load_autosave: Callable
var start_again: Callable

var _reason := Label.new()
var _best := Label.new()


func _ready() -> void:
	set_anchors_and_offsets_preset(PRESET_CENTER, PRESET_MODE_MINSIZE)
	grow_horizontal = GROW_DIRECTION_BOTH
	grow_vertical = GROW_DIRECTION_BOTH
	custom_minimum_size = Vector2(440, 0)
	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", 10)
	add_child(box)
	var title := Label.new()
	title.text = "The Ministry has taken the prison over"
	title.theme_type_variation = &"HeaderLabel"
	box.add_child(title)
	_reason.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_reason)
	_best.theme_type_variation = &"SubtleLabel"
	box.add_child(_best)
	var buttons := VBoxContainer.new()
	buttons.add_theme_constant_override(&"separation", 4)
	for entry: Array in [["Keep playing as Sandbox", func() -> void: keep_playing.call()],
			["Load this morning's save", func() -> void: load_autosave.call()],
			["Start again", func() -> void: start_again.call()]]:
		var button := Button.new()
		button.text = entry[0]
		button.focus_mode = FOCUS_NONE
		button.pressed.connect(entry[1])
		buttons.add_child(button)
	box.add_child(buttons)
	visible = false


## Shows why, and the best night in the last week.
func show_for(reason: String, history: Array[Dictionary]) -> void:
	_reason.text = reason
	var best: Dictionary = {}
	for night in history:
		if best.is_empty() or night.grade >= best.grade:
			best = night
	_best.text = "Best night this week: %d★ on day %d." % [best.grade, best.day] if not best.is_empty() else ""
	visible = true
