class_name PauseMenu
extends Control
## The pause menu, on Esc when nothing else is open: the world dims and
## stops, and a card offers a column of buttons. Some buttons run a
## function (Resume, Quit to title); others open a page beside the column,
## such as the save slots or the game settings.
##
## The game fills it before adding it to the tree:
##
##   pause_menu.clock = clock
##   pause_menu.add_page(&"saves", "Save and load", saves_window, "saves_toggle")
##   pause_menu.add_button("Quit to title", func() -> void: ...)
##
## Pages are taken over like the management book's: their card is
## dropped, and their own Close button goes back to the column.

const WIDTH := 240.0

## Paused while the menu is open, and started again after if it was
## running before.
var clock: GameClock
## A line under the heading, such as the prison's name.
var subtitle := ""

var _column := VBoxContainer.new()
var _holder := PanelContainer.new()
var _subtitle := Label.new()
## id -> {page, action}
var _pages: Dictionary[StringName, Dictionary] = {}
var _current: StringName = &""
var _paused_it := false
var _switching := false
var _resume: Button


func _ready() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	visible = false
	var dim := ColorRect.new()
	dim.color = Color(0.12, 0.13, 0.16, 0.45)
	dim.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	dim.mouse_filter = MOUSE_FILTER_STOP
	add_child(dim)
	var centre := CenterContainer.new()
	centre.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	centre.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(centre)
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 12)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	centre.add_child(row)

	var card := PanelContainer.new()
	card.size_flags_vertical = SIZE_SHRINK_BEGIN
	row.add_child(card)
	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", 6)
	box.custom_minimum_size.x = WIDTH
	card.add_child(box)
	var title := Label.new()
	title.text = "Paused"
	title.theme_type_variation = &"HeaderLabel"
	title.add_theme_font_size_override(&"font_size", 26)
	box.add_child(title)
	_subtitle.theme_type_variation = &"SubtleLabel"
	_subtitle.text = subtitle
	_subtitle.visible = subtitle != ""
	box.add_child(_subtitle)
	box.add_child(HSeparator.new())
	_column.add_theme_constant_override(&"separation", 6)
	box.add_child(_column)
	_resume = _make_button("Resume", close, &"AccentButton")
	_column.add_child(_resume)
	_column.move_child(_resume, 0)

	_holder.size_flags_vertical = SIZE_SHRINK_BEGIN
	_holder.visible = false
	row.add_child(_holder)
	for id: StringName in _pages:
		_adopt(id)


## Adds a button that opens `page` beside the column. `action`, if given,
## is an input action that opens the menu straight on this page.
func add_page(id: StringName, title: String, page: Control, action := &"") -> void:
	_pages[id] = {"page": page, "action": action}
	_column.add_child(_make_button(title, open.bind(id)))
	if is_node_ready():
		_adopt(id)


## Adds a button that calls `pressed`. `variation` is a Button theme type,
## such as DangerButton.
func add_button(title: String, pressed: Callable, variation := &"") -> void:
	_column.add_child(_make_button(title, pressed, variation))


## Adds a gap between groups of buttons.
func add_gap() -> void:
	var gap := Control.new()
	gap.custom_minimum_size.y = 8
	_column.add_child(gap)


func set_subtitle(text: String) -> void:
	subtitle = text
	_subtitle.text = text
	_subtitle.visible = text != ""


## Shows the menu, on a page if `id` is given.
func open(id := &"") -> void:
	if not visible:
		visible = true
		_paused_it = clock != null and not clock.paused()
		if _paused_it:
			clock.toggle_pause()
	_show_page(id)


func close() -> void:
	if not visible:
		return
	_show_page(&"")
	visible = false
	if _paused_it and clock != null and clock.paused():
		clock.toggle_pause()
	_paused_it = false


func toggle() -> void:
	if visible:
		close()
	else:
		open()


func _unhandled_input(event: InputEvent) -> void:
	for id: StringName in _pages:
		var action: StringName = _pages[id].action
		if action != &"" and event.is_action_pressed(action):
			if visible and _current == id:
				close()
			else:
				open(id)
			get_viewport().set_input_as_handled()
			return
	if not visible:
		return
	if event.is_action_pressed("build_cancel"):
		if _current != &"":
			_show_page(&"")
		else:
			close()
	# Nothing else reaches the world while it's paused.
	if event is InputEventKey or event is InputEventMouseButton:
		get_viewport().set_input_as_handled()


func _show_page(id: StringName) -> void:
	_switching = true
	for other: StringName in _pages:
		_pages[other].page.visible = other == id
	_switching = false
	_current = id
	_holder.visible = id != &""
	if id != &"":
		var page: Control = _pages[id].page
		if page.has_method(&"refresh"):
			page.refresh()


func _adopt(id: StringName) -> void:
	var page: Control = _pages[id].page
	if page.get_parent() != null:
		page.get_parent().remove_child(page)
	_holder.add_child(page)
	page.visible = false
	if page is PanelContainer:
		page.add_theme_stylebox_override(&"panel", StyleBoxEmpty.new())
	page.visibility_changed.connect(func() -> void:
		if _switching:
			return
		if page.visible and _current != id:
			open(id)
		elif not page.visible and _current == id:
			_show_page(&""))


func _make_button(title: String, pressed: Callable, variation := &"") -> Button:
	var button := Button.new()
	button.text = title
	button.focus_mode = FOCUS_NONE
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.custom_minimum_size.y = 40
	if variation != &"":
		button.theme_type_variation = variation
	button.pressed.connect(pressed)
	return button
