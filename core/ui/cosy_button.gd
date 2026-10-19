class_name CosyButton
extends Button
## A button with a hover card: a bold title and a line or two of detail,
## drawn in the theme's tooltip style. Build menu tiles and tool buttons
## use it so they can be pictures with their words on hover.

## Shown in bold at the top of the hover card.
var title := ""
## Shown under the title, smaller.
var details := ""
## A white line drawing to tint with the theme's ink, rather than a picture.
var symbol := false


## A square picture tile, such as an object in the build menu. `symbol`
## icons (white line drawings) take the theme's ink colour; thumbnails
## keep their own colours.
static func tile(title_text: String, details_text: String, picture: Texture2D,
		is_symbol := false, group: ButtonGroup = null) -> CosyButton:
	var button := CosyButton.new()
	button.theme_type_variation = &"TileButton"
	button.title = title_text
	button.details = details_text
	button.icon = picture
	button.symbol = is_symbol
	button.expand_icon = not is_symbol
	button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	button.vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER
	button.toggle_mode = true
	button.button_group = group
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(64, 64)
	return button


func _ready() -> void:
	# Tooltips only appear for buttons with some tooltip text.
	if tooltip_text.is_empty():
		tooltip_text = title
	if symbol:
		# The theme's colours are only known once in the tree.
		var ink := get_theme_color(&"font_color", &"Label")
		for state in [&"icon_normal_color", &"icon_hover_color", &"icon_pressed_color",
				&"icon_hover_pressed_color", &"icon_focus_color"]:
			add_theme_color_override(state, ink)
		add_theme_constant_override(&"icon_max_width", 32)
	# A thumbnail can arrive after the button is made.
	if icon != null:
		icon.changed.connect(queue_redraw)


func _make_custom_tooltip(_for_text: String) -> Object:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	var heading := Label.new()
	heading.text = title
	heading.theme_type_variation = &"HeaderLabel"
	heading.add_theme_font_size_override("font_size", 17)
	box.add_child(heading)
	if not details.is_empty():
		var body := Label.new()
		body.text = details
		body.theme_type_variation = &"SubtleLabel"
		box.add_child(body)
	return box
