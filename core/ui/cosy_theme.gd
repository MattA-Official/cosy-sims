class_name CosyTheme
extends RefCounted
## Builds the shared UI theme for every cosy sim from one small palette: soft
## rounded cards, chunky buttons, a rounded font and muted institutional
## colours. Each game can swap the accent colour and keep everything else.
##
## Run tools/build_theme.gd to save the result as core/ui/cosy_theme.tres,
## which is what scenes use. Tweak the palette here, not in the .tres, or the
## next build will overwrite your change.
##
## Type variations, set on a control's Theme Type Variation:
##   Labels: HeaderLabel, TitleLabel, SubtleLabel, KeyLabel, HudLabel
##   Buttons: ToolButton, AccentButton, DangerButton, FlatButton, TileButton
##   Panels: HudBar, InsetPanel, ToastPanel, TooltipPanel
##   Bars: BarWarning, BarDanger

const FONT_PATH := "res://core/ui/fonts/Nunito-Variable.ttf"

## Cream cards with slate-green ink: the default look.
const LIGHT := {
	"panel": Color("f6f0e2"),
	"panel_alpha": 0.97,
	"panel_border": Color("dccfb4"),
	"inset": Color("ebe2cd"),
	"ink": Color("33463f"),
	"muted": Color("7a8780"),
	"button": Color("ebe3cf"),
	"button_hover": Color("f2ecdc"),
	"button_edge": Color("cdbf9f"),
	"accent": Color("5f8a7e"),
	"accent_edge": Color("456a60"),
	"on_accent": Color("fbf7ee"),
	"good": Color("8fb38a"),
	"warning": Color("dcb36a"),
	"danger": Color("c9786a"),
	"danger_edge": Color("a65a4e"),
	"track": Color("e0d6bf"),
	"shadow": Color(0.16, 0.2, 0.18, 0.22),
	"hud_text": Color("fbf7ee"),
	"hud_outline": WORLD_OUTLINE,
}

## Slate-green cards with cream ink, for comparison.
const DARK := {
	"panel": Color("34473f"),
	"panel_alpha": 0.95,
	"panel_border": Color("4a6058"),
	"inset": Color("2b3c35"),
	"ink": Color("f3ecdb"),
	"muted": Color("a9b5ab"),
	"button": Color("44594f"),
	"button_hover": Color("4e655a"),
	"button_edge": Color("2a3a33"),
	"accent": Color("e8dcc0"),
	"accent_edge": Color("bfae88"),
	"on_accent": Color("2f4139"),
	"good": Color("9cc196"),
	"warning": Color("e2bc72"),
	"danger": Color("d08474"),
	"danger_edge": Color("9e5649"),
	"track": Color("26352f"),
	"shadow": Color(0.05, 0.08, 0.07, 0.35),
	"hud_text": Color("fbf7ee"),
	"hud_outline": WORLD_OUTLINE,
}

## Outline for text drawn over the world (HUD labels and room labels).
const WORLD_OUTLINE := Color(0.13, 0.18, 0.16, 0.7)
const RADIUS := 12
const BUTTON_RADIUS := 10
const FONT_SIZE := 16

var p: Dictionary
var theme := Theme.new()
var _regular: FontVariation
var _bold: FontVariation


## `accent` replaces the palette's accent (and darkens it for the edge), so a
## hospital could be mint and an airport sky blue on the same shapes.
static func build(palette := LIGHT, accent := Color(0, 0, 0, 0)) -> Theme:
	var builder := CosyTheme.new()
	builder.p = palette.duplicate()
	if accent.a > 0.0:
		builder.p.accent = accent
		builder.p.accent_edge = accent.darkened(0.25)
	return builder._build()


## The theme's bold font, for Label3Ds in the world, which themes don't reach.
static func bold_font() -> FontVariation:
	var font := FontVariation.new()
	font.base_font = load(FONT_PATH)
	font.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): 800}
	return font


func _build() -> Theme:
	_fonts()
	_labels()
	_panels()
	_buttons()
	_toggles()
	_ranges()
	_inputs()
	_tabs()
	_popups()
	_scrollbars()
	return theme


func _fonts() -> void:
	var base: FontFile = load(FONT_PATH)
	_regular = _weight(base, 560)
	_bold = bold_font()
	theme.default_font = _regular
	theme.default_font_size = FONT_SIZE


func _weight(base: FontFile, weight: int) -> FontVariation:
	var font := FontVariation.new()
	font.base_font = base
	var ts := TextServerManager.get_primary_interface()
	font.variation_opentype = {ts.name_to_tag("wght"): weight}
	return font


func _labels() -> void:
	theme.set_color("font_color", "Label", p.ink)
	theme.set_constant("line_spacing", "Label", 2)
	_variation("HeaderLabel", "Label")
	theme.set_font("font", "HeaderLabel", _bold)
	theme.set_font_size("font_size", "HeaderLabel", 21)
	_variation("TitleLabel", "Label")
	theme.set_font("font", "TitleLabel", _bold)
	theme.set_font_size("font_size", "TitleLabel", 15)
	theme.set_color("font_color", "TitleLabel", p.muted)
	_variation("SubtleLabel", "Label")
	theme.set_font_size("font_size", "SubtleLabel", 14)
	theme.set_color("font_color", "SubtleLabel", p.muted)
	# A little keycap, for shortcuts next to tools and in hints.
	_variation("KeyLabel", "Label")
	theme.set_font("font", "KeyLabel", _bold)
	theme.set_font_size("font_size", "KeyLabel", 12)
	theme.set_color("font_color", "KeyLabel", p.muted)
	var key := _box(p.inset, 6)
	key.set_content_margin_all(2)
	key.content_margin_left = 6
	key.content_margin_right = 6
	theme.set_stylebox("normal", "KeyLabel", key)
	# Text straight over the world, like the build hint.
	_variation("HudLabel", "Label")
	theme.set_font("font", "HudLabel", _weight(load(FONT_PATH), 700))
	theme.set_color("font_color", "HudLabel", p.hud_text)
	theme.set_color("font_outline_color", "HudLabel", p.hud_outline)
	theme.set_constant("outline_size", "HudLabel", 5)


func _panels() -> void:
	var card := _card()
	theme.set_stylebox("panel", "Panel", card)
	theme.set_stylebox("panel", "PanelContainer", card)
	_variation("HudBar", "PanelContainer")
	var bar := _card()
	bar.set_corner_radius_all(18)
	bar.content_margin_top = 6
	bar.content_margin_bottom = 6
	bar.content_margin_left = 10
	bar.content_margin_right = 10
	theme.set_stylebox("panel", "HudBar", bar)
	_variation("InsetPanel", "PanelContainer")
	var inset := _box(p.inset, BUTTON_RADIUS)
	inset.set_content_margin_all(8)
	inset.content_margin_left = 10
	inset.content_margin_right = 10
	theme.set_stylebox("panel", "InsetPanel", inset)
	_variation("ToastPanel", "PanelContainer")
	var toast := _card()
	toast.border_width_left = 6
	toast.border_color = p.accent
	theme.set_stylebox("panel", "ToastPanel", toast)
	var tip := _card()
	tip.set_content_margin_all(8)
	tip.content_margin_left = 10
	tip.content_margin_right = 10
	tip.set_corner_radius_all(BUTTON_RADIUS)
	theme.set_stylebox("panel", "TooltipPanel", tip)
	theme.set_color("font_color", "TooltipLabel", p.ink)
	theme.set_font_size("font_size", "TooltipLabel", 14)
	var line := StyleBoxLine.new()
	line.color = p.panel_border
	line.thickness = 2
	theme.set_stylebox("separator", "HSeparator", line)
	theme.set_constant("separation", "HSeparator", 10)
	var vline := line.duplicate() as StyleBoxLine
	vline.vertical = true
	theme.set_stylebox("separator", "VSeparator", vline)
	theme.set_constant("separation", "VSeparator", 10)
	theme.set_constant("separation", "VBoxContainer", 6)
	theme.set_constant("separation", "HBoxContainer", 6)


func _buttons() -> void:
	_button_type("Button", p.button, p.button_hover, p.button_edge, p.ink, p.accent, p.on_accent)
	_variation("ToolButton", "Button")
	_button_type("ToolButton", p.button, p.button_hover, p.button_edge, p.ink, p.accent, p.on_accent, 10)
	theme.set_font("font", "ToolButton", _bold)
	_variation("AccentButton", "Button")
	_button_type("AccentButton", p.accent, p.accent.lightened(0.1), p.accent_edge, p.on_accent, p.accent_edge, p.on_accent)
	theme.set_font("font", "AccentButton", _bold)
	_variation("DangerButton", "Button")
	_button_type("DangerButton", p.danger, p.danger.lightened(0.1), p.danger_edge, p.on_accent, p.danger_edge, p.on_accent)
	theme.set_font("font", "DangerButton", _bold)
	_variation("FlatButton", "Button")
	var clear := Color(p.button, 0.0)
	_button_type("FlatButton", clear, Color(p.button, 0.6), clear, p.ink, p.inset, p.ink)
	_tiles()
	var arrow := CosyIcons.chevron(14, p.muted)
	theme.set_icon("arrow", "OptionButton", arrow)
	theme.set_constant("arrow_margin", "OptionButton", 10)


## Square picture tiles for the build menu. The picture keeps its own
## colours; picking one rings it in the accent.
func _tiles() -> void:
	_variation("TileButton", "Button")
	var normal := _box(p.inset, RADIUS)
	normal.set_border_width_all(2)
	normal.border_color = p.inset
	normal.set_content_margin_all(4)
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = p.button_hover
	hover.border_color = p.button_edge
	var picked := normal.duplicate() as StyleBoxFlat
	picked.bg_color = p.button_hover
	picked.set_border_width_all(3)
	picked.border_color = p.accent
	for state in ["normal", "disabled"]:
		theme.set_stylebox(state, "TileButton", normal)
	theme.set_stylebox("hover", "TileButton", hover)
	theme.set_stylebox("pressed", "TileButton", picked)
	theme.set_stylebox("hover_pressed", "TileButton", picked)
	theme.set_stylebox("focus", "TileButton", StyleBoxEmpty.new())
	for state in ["icon_normal_color", "icon_hover_color", "icon_pressed_color",
			"icon_hover_pressed_color", "icon_focus_color"]:
		theme.set_color(state, "TileButton", Color.WHITE)
	theme.set_color("icon_disabled_color", "TileButton", Color(1, 1, 1, 0.4))
	theme.set_color("font_color", "TileButton", p.ink)
	theme.set_color("font_pressed_color", "TileButton", p.ink)
	theme.set_color("font_hover_pressed_color", "TileButton", p.ink)
	theme.set_font_size("font_size", "TileButton", 13)


## Normal, hover, pressed (selected toggles), disabled and focus looks for one
## button type. The thick bottom edge makes buttons look pressable; pressing
## squashes it.
func _button_type(type: StringName, fill: Color, hover: Color, edge: Color, text: Color,
		on_fill: Color, on_text: Color, pad := 8) -> void:
	var normal := _button_box(fill, edge, 4, pad)
	var hovered := _button_box(hover, edge, 4, pad)
	var pressed := _button_box(on_fill, on_fill.darkened(0.22), 2, pad)
	pressed.content_margin_top += 2
	var disabled := _button_box(Color(fill, fill.a * 0.5), Color(edge, edge.a * 0.4), 4, pad)
	var focus := StyleBoxFlat.new()
	focus.draw_center = false
	focus.set_corner_radius_all(BUTTON_RADIUS + 2)
	focus.set_border_width_all(2)
	focus.border_color = Color(p.accent, 0.8)
	focus.set_expand_margin_all(2)
	theme.set_stylebox("normal", type, normal)
	theme.set_stylebox("hover", type, hovered)
	theme.set_stylebox("pressed", type, pressed)
	theme.set_stylebox("hover_pressed", type, pressed)
	theme.set_stylebox("disabled", type, disabled)
	theme.set_stylebox("focus", type, focus)
	theme.set_color("font_color", type, text)
	theme.set_color("font_hover_color", type, text)
	theme.set_color("font_focus_color", type, text)
	theme.set_color("font_pressed_color", type, on_text)
	theme.set_color("font_hover_pressed_color", type, on_text)
	theme.set_color("font_disabled_color", type, Color(text, 0.45))
	theme.set_color("icon_normal_color", type, text)
	theme.set_color("icon_hover_color", type, text)
	theme.set_color("icon_focus_color", type, text)
	theme.set_color("icon_pressed_color", type, on_text)
	theme.set_color("icon_hover_pressed_color", type, on_text)
	theme.set_constant("h_separation", type, 8)


func _toggles() -> void:
	for type in ["CheckBox", "CheckButton"]:
		var empty := StyleBoxEmpty.new()
		empty.set_content_margin_all(4)
		for state in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
			theme.set_stylebox(state, type, empty)
		var focus := StyleBoxEmpty.new()
		theme.set_stylebox("focus", type, focus)
		for state in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
			theme.set_color(state, type, p.ink)
		theme.set_color("font_disabled_color", type, Color(p.ink, 0.45))
		theme.set_constant("h_separation", type, 10)
	var box_on := CosyIcons.check_box(20, p.accent, p.on_accent, true)
	var box_off := CosyIcons.check_box(20, p.track, p.panel_border.darkened(0.1), false)
	theme.set_icon("checked", "CheckBox", box_on)
	theme.set_icon("unchecked", "CheckBox", box_off)
	theme.set_icon("checked_disabled", "CheckBox", box_on)
	theme.set_icon("unchecked_disabled", "CheckBox", box_off)
	theme.set_icon("radio_checked", "CheckBox", CosyIcons.radio(20, p.accent, p.on_accent, true))
	theme.set_icon("radio_unchecked", "CheckBox", CosyIcons.radio(20, p.track, p.panel_border.darkened(0.1), false))
	var switch_on := CosyIcons.switch(40, 22, p.accent, p.on_accent, true)
	var switch_off := CosyIcons.switch(40, 22, p.track, p.panel, false)
	theme.set_icon("checked", "CheckButton", switch_on)
	theme.set_icon("unchecked", "CheckButton", switch_off)
	theme.set_icon("checked_disabled", "CheckButton", switch_on)
	theme.set_icon("unchecked_disabled", "CheckButton", switch_off)


func _ranges() -> void:
	var track := _box(p.track, 8)
	track.content_margin_top = 4
	track.content_margin_bottom = 4
	var filled := _box(p.accent, 8)
	theme.set_stylebox("slider", "HSlider", track)
	theme.set_stylebox("grabber_area", "HSlider", filled)
	theme.set_stylebox("grabber_area_highlight", "HSlider", filled)
	theme.set_icon("grabber", "HSlider", CosyIcons.knob(22, p.panel, p.accent))
	theme.set_icon("grabber_highlight", "HSlider", CosyIcons.knob(22, p.panel, p.accent.lightened(0.15)))
	theme.set_icon("tick", "HSlider", CosyIcons.dot(6, p.panel_border))
	theme.set_constant("center_grabber", "HSlider", 0)

	var bar_bg := _box(p.track, 8)
	bar_bg.content_margin_top = 2
	bar_bg.content_margin_bottom = 2
	theme.set_stylebox("background", "ProgressBar", bar_bg)
	theme.set_stylebox("fill", "ProgressBar", _box(p.good, 8))
	theme.set_color("font_color", "ProgressBar", p.ink)
	theme.set_font_size("font_size", "ProgressBar", 12)
	_variation("BarWarning", "ProgressBar")
	theme.set_stylebox("fill", "BarWarning", _box(p.warning, 8))
	_variation("BarDanger", "ProgressBar")
	theme.set_stylebox("fill", "BarDanger", _box(p.danger, 8))


func _inputs() -> void:
	var normal := _box(p.inset, BUTTON_RADIUS)
	normal.set_content_margin_all(7)
	normal.content_margin_left = 10
	normal.content_margin_right = 10
	var focus := normal.duplicate() as StyleBoxFlat
	focus.set_border_width_all(2)
	focus.border_color = p.accent
	theme.set_stylebox("normal", "LineEdit", normal)
	theme.set_stylebox("focus", "LineEdit", focus)
	theme.set_stylebox("read_only", "LineEdit", normal)
	theme.set_color("font_color", "LineEdit", p.ink)
	theme.set_color("font_placeholder_color", "LineEdit", Color(p.muted, 0.8))
	theme.set_color("caret_color", "LineEdit", p.accent)
	theme.set_color("selection_color", "LineEdit", Color(p.accent, 0.35))


func _tabs() -> void:
	var selected := _box(p.panel, BUTTON_RADIUS)
	selected.corner_radius_bottom_left = 0
	selected.corner_radius_bottom_right = 0
	selected.content_margin_left = 14
	selected.content_margin_right = 14
	selected.content_margin_top = 7
	selected.content_margin_bottom = 7
	selected.border_width_top = 3
	selected.border_color = p.accent
	var unselected := selected.duplicate() as StyleBoxFlat
	unselected.bg_color = p.inset
	unselected.border_color = p.inset
	var hovered := unselected.duplicate() as StyleBoxFlat
	hovered.bg_color = p.button_hover
	hovered.border_color = p.button_hover
	var body := _card()
	body.corner_radius_top_left = 0
	for type in ["TabContainer", "TabBar"]:
		theme.set_stylebox("tab_selected", type, selected)
		theme.set_stylebox("tab_unselected", type, unselected)
		theme.set_stylebox("tab_hovered", type, hovered)
		theme.set_stylebox("tab_focus", type, StyleBoxEmpty.new())
		theme.set_color("font_selected_color", type, p.ink)
		theme.set_color("font_unselected_color", type, p.muted)
		theme.set_color("font_hovered_color", type, p.ink)
		theme.set_font("font", type, _bold)
		theme.set_constant("tab_separation", type, 4)
	theme.set_stylebox("panel", "TabContainer", body)
	theme.set_stylebox("tabbar_background", "TabContainer", StyleBoxEmpty.new())


func _popups() -> void:
	var menu := _card()
	menu.set_content_margin_all(6)
	theme.set_stylebox("panel", "PopupMenu", menu)
	theme.set_stylebox("panel", "PopupPanel", menu)
	theme.set_stylebox("hover", "PopupMenu", _box(p.inset, 8))
	theme.set_color("font_color", "PopupMenu", p.ink)
	theme.set_color("font_hover_color", "PopupMenu", p.ink)
	theme.set_color("font_disabled_color", "PopupMenu", Color(p.ink, 0.45))
	theme.set_color("font_separator_color", "PopupMenu", p.muted)
	theme.set_constant("v_separation", "PopupMenu", 8)
	theme.set_constant("item_start_padding", "PopupMenu", 8)
	var line := StyleBoxLine.new()
	line.color = p.panel_border
	line.thickness = 2
	theme.set_stylebox("separator", "PopupMenu", line)
	theme.set_icon("radio_checked", "PopupMenu", CosyIcons.radio(16, p.accent, p.on_accent, true))
	theme.set_icon("radio_unchecked", "PopupMenu", CosyIcons.radio(16, p.track, p.panel_border, false))
	theme.set_icon("checked", "PopupMenu", CosyIcons.check_box(16, p.accent, p.on_accent, true))
	theme.set_icon("unchecked", "PopupMenu", CosyIcons.check_box(16, p.track, p.panel_border, false))
	# Embedded windows (dialogs inside the game window).
	var frame := _card()
	frame.set_expand_margin_all(8)
	frame.expand_margin_top = 38
	frame.set_border_width_all(0)
	theme.set_stylebox("embedded_border", "Window", frame)
	theme.set_stylebox("embedded_unfocused_border", "Window", frame)
	theme.set_color("title_color", "Window", p.ink)
	theme.set_font("title_font", "Window", _bold)
	theme.set_constant("title_height", "Window", 34)
	theme.set_stylebox("panel", "AcceptDialog", StyleBoxEmpty.new())


func _scrollbars() -> void:
	for type in ["VScrollBar", "HScrollBar"]:
		var track := _box(Color(p.track, 0.6), 6)
		track.set_content_margin_all(3)
		theme.set_stylebox("scroll", type, track)
		theme.set_stylebox("scroll_focus", type, track)
		theme.set_stylebox("grabber", type, _box(p.button_edge, 6))
		theme.set_stylebox("grabber_highlight", type, _box(p.muted, 6))
		theme.set_stylebox("grabber_pressed", type, _box(p.accent, 6))
		var none := ImageTexture.create_from_image(Image.create(1, 1, false, Image.FORMAT_RGBA8))
		theme.set_icon("increment", type, none)
		theme.set_icon("decrement", type, none)


## A floating card: the panel colour with a soft border and drop shadow.
func _card() -> StyleBoxFlat:
	var card := _box(Color(p.panel, p.panel_alpha), RADIUS)
	card.set_border_width_all(2)
	card.border_color = p.panel_border
	card.shadow_color = p.shadow
	card.shadow_size = 10
	card.shadow_offset = Vector2(0, 4)
	card.set_content_margin_all(14)
	return card


func _button_box(fill: Color, edge: Color, depth: int, pad: int) -> StyleBoxFlat:
	var box := _box(fill, BUTTON_RADIUS)
	box.border_width_bottom = depth
	box.border_color = edge
	box.content_margin_left = 12 + pad - 8
	box.content_margin_right = 12 + pad - 8
	box.content_margin_top = 5 + pad / 2
	# A shallower edge gives its height back, so pressing never resizes.
	box.content_margin_bottom = 5 + pad / 2 - (4 - depth)
	return box


func _box(fill: Color, radius: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.set_corner_radius_all(radius)
	box.corner_detail = 6
	box.anti_aliasing = true
	return box


func _variation(variation: StringName, base: StringName) -> void:
	theme.set_type_variation(variation, base)
