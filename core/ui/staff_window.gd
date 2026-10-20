class_name StaffWindow
extends PanelContainer
## Who works here. A row for each staff role with how many work each
## shift and buttons to take one on or let one go, and a row for each work
## programme with how many prisoners are on it and buttons to put one more
## on or take one off. With a ledger, staff cost their wages and nobody
## can be taken on while the prison is in debt. Toggle with P.

## Someone tried to take on staff while the prison is in debt.
signal hire_refused

## Seconds between counting everyone again while open.
const REFRESH_SECONDS := 0.5
## Width of each − count + group, and the shift names over them.
const CONTROLS_WIDTH := 104.0

var roles: Array[StaffRoleDef] = []
var programmes: Array[WorkProgrammeDef] = []
var people: People
## Who works which shift.
var shifts: Shifts
## Patrol routes, to put guards on. Optional.
var routes: PatrolRoutes
var route_icon: Texture2D
## Whose needs the Staff needs box switches on and off.
var staff_group: StringName = &"staff"
## Who goes on work programmes.
var programme_group: StringName = &"prisoner"
## The prison's money, for wages. Optional: without it staff are free.
var ledger: Ledger

## Count labels by role, then by shift.
var _counts: Dictionary[StringName, Dictionary] = {}
var _programme_counts: Dictionary[StringName, Label] = {}
var _free_text := Label.new()
var _wages_text := Label.new()
var _route_box := VBoxContainer.new()
var _route_counts: Dictionary[PatrolRoutes.Route, Label] = {}
var _wait := 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(PRESET_CENTER_TOP, PRESET_MODE_MINSIZE)
	grow_horizontal = GROW_DIRECTION_BOTH
	offset_top = 76.0
	custom_minimum_size = Vector2(520, 0)
	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", 8)
	add_child(box)

	var heading := HBoxContainer.new()
	var title := Label.new()
	title.text = "Staff"
	title.theme_type_variation = &"HeaderLabel"
	heading.add_child(title)
	_wages_text.text = "Free until wages come in"
	_wages_text.theme_type_variation = &"SubtleLabel"
	_wages_text.size_flags_vertical = SIZE_SHRINK_CENTER
	heading.add_child(_wages_text)
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

	if shifts != null:
		var columns := HBoxContainer.new()
		columns.add_theme_constant_override(&"separation", 8)
		var gap := Control.new()
		gap.size_flags_horizontal = SIZE_EXPAND_FILL
		columns.add_child(gap)
		for shift in shifts.shifts:
			var label := Label.new()
			label.text = shift.display_name
			label.tooltip_text = shift.hours_text()
			label.mouse_filter = MOUSE_FILTER_PASS
			label.theme_type_variation = &"SubtleLabel"
			label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			label.custom_minimum_size = Vector2(CONTROLS_WIDTH, 0)
			columns.add_child(label)
		box.add_child(columns)
	for def in roles:
		var tip := def.description
		if ledger != null:
			tip += "\nWage: %s a day shift, more at night." % Ledger.text(def.wage)
		var row := _row(def.icon, def.display_name, tip)
		_counts[def.id] = {}
		for shift in shifts.shifts if shifts != null else []:
			var shift_id: StringName = shift.id
			var role_id := def.id
			_counts[def.id][shift_id] = _stepper(row,
					func() -> void:
						if _may_hire():
							shifts.set_wanted(role_id, shift_id, shifts.wanted_for(role_id, shift_id) + 1),
					func() -> void: shifts.set_wanted(role_id, shift_id, shifts.wanted_for(role_id, shift_id) - 1))
		box.add_child(row)

	var staff_needs := CheckButton.new()
	staff_needs.text = "Staff needs"
	staff_needs.tooltip_text = "On: staff get hungry and tired, take breaks in the staff room and work slower when worn out.\nOff: they simply work their shift."
	staff_needs.focus_mode = FOCUS_NONE
	staff_needs.button_pressed = people != null and not people.needs_off.has(staff_group)
	staff_needs.toggled.connect(func(on: bool) -> void:
		if on:
			people.needs_off.erase(staff_group)
		elif not people.needs_off.has(staff_group):
			people.needs_off.append(staff_group))
	box.add_child(staff_needs)

	if routes != null:
		box.add_child(HSeparator.new())
		var heading_routes := Label.new()
		heading_routes.text = "Patrol routes"
		heading_routes.theme_type_variation = &"HeaderLabel"
		box.add_child(heading_routes)
		_route_box.add_theme_constant_override(&"separation", 8)
		box.add_child(_route_box)
		routes.changed.connect(_list_routes)
		_list_routes()

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
			var row := _row(def.icon, def.display_name, def.description)
			_programme_counts[def.id] = _stepper(row,
					func() -> void: _put_on(def.id), func() -> void: _take_off(def.id))
			box.add_child(row)
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
		for shift: StringName in _counts[role]:
			var label: Label = _counts[role][shift]
			var want := shifts.wanted_for(role, shift)
			var here := shifts.on_site(role, shift).size()
			label.text = str(want)
			label.tooltip_text = "%d wanted, %d on site now" % [want, here]
	if ledger != null:
		_wages_text.text = "Wages %s a day" % Ledger.text(daily_wages())
	for route: PatrolRoutes.Route in _route_counts:
		_route_counts[route].text = str(route.guards)
	for programme: StringName in _programme_counts:
		_programme_counts[programme].text = str(_with(func(p: Person) -> bool:
				return p.programme == programme).size())
	if not _programme_counts.is_empty():
		var free := _free().size()
		_free_text.text = "Prisoners on a programme work in work blocks. %d %s on none." % [
				free, "prisoner is" if free == 1 else "prisoners are"]


## A row for each patrol route with how many guards walk it.
func _list_routes() -> void:
	for child in _route_box.get_children():
		child.queue_free()
	_route_counts.clear()
	if routes.routes.is_empty():
		var none := Label.new()
		none.text = "None yet. Draw one with the route tool (X); guards with no route patrol where the prisoners are."
		none.theme_type_variation = &"SubtleLabel"
		none.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_route_box.add_child(none)
		return
	for route in routes.routes:
		var row := _row(route_icon, route.name, "%d points. Guards on it walk round the loop." % route.points.size())
		_route_counts[route] = _stepper(row,
				func() -> void: routes.set_guards(route, route.guards + 1),
				func() -> void: routes.set_guards(route, route.guards - 1))
		_route_box.add_child(row)
	refresh()


## A row with an icon and a name, for steppers to go on the end of.
func _row(icon: Texture2D, text: String, tip: String) -> HBoxContainer:
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
	return row


## − count + on the end of a row. Returns the count's label.
func _stepper(row: HBoxContainer, more: Callable, fewer: Callable) -> Label:
	var group := HBoxContainer.new()
	group.add_theme_constant_override(&"separation", 4)
	group.custom_minimum_size = Vector2(CONTROLS_WIDTH, 0)
	var minus := Button.new()
	minus.text = "−"
	minus.focus_mode = FOCUS_NONE
	minus.custom_minimum_size = Vector2(32, 0)
	minus.pressed.connect(func() -> void:
		fewer.call()
		refresh())
	group.add_child(minus)
	var count := Label.new()
	count.custom_minimum_size = Vector2(28, 0)
	count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	count.mouse_filter = MOUSE_FILTER_PASS
	group.add_child(count)
	var plus := Button.new()
	plus.text = "+"
	plus.focus_mode = FOCUS_NONE
	plus.custom_minimum_size = Vector2(32, 0)
	plus.pressed.connect(func() -> void:
		more.call()
		refresh())
	group.add_child(plus)
	row.add_child(group)
	return count


## What a day of every shift's staff costs.
func daily_wages() -> int:
	var sum := 0.0
	for def in roles:
		for shift in shifts.shifts if shifts != null else []:
			sum += def.wage * shift.pay_scale * shifts.wanted_for(def.id, shift.id)
	return roundi(sum)


## Whether more staff can be taken on: not while in debt.
func _may_hire() -> bool:
	if ledger == null or ledger.can_spend():
		return true
	hire_refused.emit()
	return false


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
