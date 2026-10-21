class_name ManagementBook
extends Control
## The management book, after Prison Architect's reports: a rail of
## bookmarks down the left edge, and a book that opens beside it on one
## page at a time. Every management window (the timetable, staff, money and
## so on) is a page, so they open in the same place and never pile up.
##
## A page is any Control with a `refresh()` method, usually one of the
## PanelContainer windows. The book takes it over: it drops the page's card
## (the book is the card), lays it out, and shows it when its bookmark or
## key is pressed. A page closing itself (its own Close button hides it)
## closes the book, and a page shown by code (`window.toggle()`) opens the
## book on it, so a window works the same inside the book as out of it.
##
##   book.add_page(&"staff", "Staff", "Who works here. P", "staff", staff_window)
##   book.toggle(&"staff")

signal page_changed(id: StringName)

const ICONS := "res://core/ui/icons/%s.svg"
## Below the clock bar in the top-left corner.
const TOP := 76.0
const MARGIN := 12.0
const GAP := 8.0
## The book never gets narrower than this, so short pages don't look lost.
const MIN_WIDTH := 480.0
## Room left under the book for the build menu's row of tools.
const BOTTOM := 96.0

## The open page's id, or &"" when the book is shut.
var current: StringName = &""

var _rail := PanelContainer.new()
var _marks := VBoxContainer.new()
var _card := PanelContainer.new()
var _scroll := ScrollContainer.new()
var _holder := VBoxContainer.new()
var _group := ButtonGroup.new()
## id -> {page, button}
var _pages: Dictionary[StringName, Dictionary] = {}
## True while the book itself is showing and hiding pages, so those
## changes aren't taken for the page closing itself.
var _switching := false


func _ready() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_IGNORE

	_rail.theme_type_variation = &"HudBar"
	_rail.position = Vector2(MARGIN, TOP)
	_marks.add_theme_constant_override(&"separation", 4)
	_rail.add_child(_marks)
	add_child(_rail)

	_card.visible = false
	# Solid, unlike the see-through HUD cards, so the world doesn't show
	# through a page of figures.
	var paper := _card.get_theme_stylebox(&"panel").duplicate() as StyleBoxFlat
	if paper != null:
		paper.bg_color.a = 1.0
		_card.add_theme_stylebox_override(&"panel", paper)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_holder.size_flags_horizontal = SIZE_EXPAND_FILL
	# Room on the right for the scroll bar, so it never sits on a button.
	var gutter := MarginContainer.new()
	gutter.add_theme_constant_override(&"margin_right", 14)
	gutter.size_flags_horizontal = SIZE_EXPAND_FILL
	gutter.add_child(_holder)
	_scroll.add_child(gutter)
	_card.add_child(_scroll)
	add_child(_card)
	_group.allow_unpress = true
	get_viewport().size_changed.connect(_fit)


## Adds a page with a bookmark on the rail: `title` and `details` for its
## hover card, and an icon from core/ui/icons.
func add_page(id: StringName, title: String, details: String, icon_name: String, page: Control) -> void:
	var button := CosyButton.new()
	button.title = title
	button.details = details
	button.icon = load(ICONS % icon_name)
	button.theme_type_variation = &"ModeButton"
	button.toggle_mode = true
	button.button_group = _group
	button.focus_mode = FOCUS_NONE
	button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	button.custom_minimum_size = Vector2(38, 38)
	button.pressed.connect(func() -> void: toggle(id))
	_marks.add_child(button)
	_pages[id] = {"page": page, "button": button}
	page.visible = false
	if page.get_parent() != null:
		page.get_parent().remove_child(page)
	_holder.add_child(page)
	# The book is the card; the page keeps only its contents.
	if page is PanelContainer:
		page.add_theme_stylebox_override(&"panel", StyleBoxEmpty.new())
	page.size_flags_horizontal = SIZE_EXPAND_FILL
	page.visibility_changed.connect(_on_page_visibility.bind(id))
	page.minimum_size_changed.connect(func() -> void:
		if current == id:
			_fit())


## Opens the book on a page.
func open(id: StringName) -> void:
	if not _pages.has(id):
		return
	_switching = true
	for other: StringName in _pages:
		_pages[other].page.visible = other == id
		(_pages[other].button as Button).set_pressed_no_signal(other == id)
	_switching = false
	var changed := current != id
	current = id
	var page: Control = _pages[id].page
	if page.has_method(&"refresh"):
		page.refresh()
	_card.visible = true
	_scroll.scroll_vertical = 0
	_fit()
	if changed:
		page_changed.emit(id)


## Shuts the book.
func close() -> void:
	if current == &"":
		return
	_switching = true
	for id: StringName in _pages:
		_pages[id].page.visible = false
		(_pages[id].button as Button).set_pressed_no_signal(false)
	_switching = false
	current = &""
	_card.visible = false
	page_changed.emit(current)


## Opens the book on a page, or shuts it if that page is already open.
func toggle(id: StringName) -> void:
	if current == id:
		close()
	else:
		open(id)


func is_open() -> bool:
	return current != &""


## The page added as `id`, or null.
func page(id: StringName) -> Control:
	return _pages[id].page if _pages.has(id) else null


func _unhandled_input(event: InputEvent) -> void:
	if is_open() and event.is_action_pressed("build_cancel"):
		close()
		get_viewport().set_input_as_handled()


func _on_page_visibility(id: StringName) -> void:
	if _switching:
		return
	var page: Control = _pages[id].page
	if page.visible and current != id:
		open(id)
	elif not page.visible and current == id:
		close()


## Sizes the book to the open page: as wide as it needs, and as tall, up
## to just above the build tools; past that the page scrolls. The left edge
## stays put, so changing page doesn't jump.
func _fit() -> void:
	if not is_open():
		return
	var screen := get_viewport_rect().size
	var left := MARGIN + _rail.get_combined_minimum_size().x + GAP
	var page: Control = _pages[current].page
	var card_style := _card.get_theme_stylebox(&"panel")
	var padding := card_style.get_minimum_size() if card_style != null else Vector2.ZERO
	var width := minf(maxf(MIN_WIDTH, page.get_combined_minimum_size().x), screen.x - left - MARGIN - padding.x)
	var tall := minf(page.get_combined_minimum_size().y, screen.y - TOP - BOTTOM - padding.y)
	_scroll.custom_minimum_size = Vector2(width + 14.0, tall)
	_card.position = Vector2(left, TOP)
	_card.reset_size()
