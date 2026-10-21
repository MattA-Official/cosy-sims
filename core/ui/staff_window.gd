class_name StaffWindow
extends PanelContainer
## Who works here. A row for each staff role with how many work each
## shift and buttons to take one on or let one go, and a row for each work
## programme with how many prisoners are on it and buttons to put one more
## on or take one off. With a ledger, staff cost their wages and nobody
## can be taken on while the prison is in debt. With a roster, a column
## beside lists the day's applicants to hire and everyone on the payroll,
## and + takes on the cheapest applicant for that shift. Toggle with P.

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
## Staff by name. Optional.
var roster: StaffRoster

## Count labels by role, then by shift.
var _counts: Dictionary[StringName, Dictionary] = {}
var _programme_counts: Dictionary[StringName, Label] = {}
var _free_text := Label.new()
var _wages_text := Label.new()
var _route_box := VBoxContainer.new()
var _route_counts: Dictionary[PatrolRoutes.Route, Label] = {}
var _wait := 0.0
var _applicant_box := VBoxContainer.new()
var _payroll_box := VBoxContainer.new()
var _listed := false


func _ready() -> void:
	set_anchors_and_offsets_preset(PRESET_CENTER_TOP, PRESET_MODE_MINSIZE)
	grow_horizontal = GROW_DIRECTION_BOTH
	offset_top = 76.0
	custom_minimum_size = Vector2(520, 0)
	var outer := HBoxContainer.new()
	outer.add_theme_constant_override(&"separation", 12)
	add_child(outer)
	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", 8)
	box.custom_minimum_size = Vector2(520, 0)
	outer.add_child(box)
	if roster != null:
		outer.add_child(VSeparator.new())
		outer.add_child(_side())
		roster.changed.connect(func() -> void: _listed = false)

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
		if def.most > 0:
			tip += "\nAt most %d." % def.most
		var row := _row(def.icon, def.display_name, tip)
		_counts[def.id] = {}
		for shift in shifts.shifts if shifts != null else []:
			var shift_id: StringName = shift.id
			var role_id := def.id
			if not def.works(shift_id):
				var none := Label.new()
				none.text = "–"
				none.tooltip_text = "%s only work %s." % [def.display_name.to_lower() + "s",
						" and ".join(def.only_shifts.map(func(id: StringName) -> String: return String(id) + "s"))]
				none.mouse_filter = MOUSE_FILTER_PASS
				none.theme_type_variation = &"SubtleLabel"
				none.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
				none.custom_minimum_size = Vector2(CONTROLS_WIDTH, 0)
				row.add_child(none)
				continue
			_counts[def.id][shift_id] = _stepper(row,
					func() -> void:
						if not _may_hire():
							return
						if roster == null:
							shifts.set_wanted(role_id, shift_id, shifts.wanted_for(role_id, shift_id) + 1)
						elif shifts.may_add(role_id, shift_id):
							var pick := roster.cheapest(role_id, shift_id)
							if pick != null:
								roster.hire(pick),
					func() -> void:
						if roster == null:
							shifts.set_wanted(role_id, shift_id, shifts.wanted_for(role_id, shift_id) - 1)
						else:
							var on := roster.on(role_id, shift_id)
							if not on.is_empty():
								roster.dismiss(on.back()))
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
			if roster != null:
				var waiting := roster.applicants_for(role, shift).size()
				label.tooltip_text = "%d on the roster, %d on site now. %s" % [want, here,
						"No applicants today." if waiting == 0
						else "+ takes on the cheapest of %d applicants; − lets the newest go with a day's pay." % waiting]
	if ledger != null:
		_wages_text.text = "Wages %s a day" % Ledger.text(daily_wages())
	if roster != null and not _listed:
		_listed = true
		_list_staff()
	for route: PatrolRoutes.Route in _route_counts:
		_route_counts[route].text = str(route.guards)
	for programme: StringName in _programme_counts:
		_programme_counts[programme].text = str(_with(func(p: Person) -> bool:
				return p.programme == programme).size())
	if not _programme_counts.is_empty():
		var free := _free().size()
		_free_text.text = "Prisoners on a programme work in work blocks. %d %s on none." % [
				free, "prisoner is" if free == 1 else "prisoners are"]


## The column of applicants and the payroll.
func _side() -> Control:
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(400, 520)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var column := VBoxContainer.new()
	column.add_theme_constant_override(&"separation", 8)
	column.size_flags_horizontal = SIZE_EXPAND_FILL
	scroll.add_child(column)
	column.add_child(_heading("On the payroll"))
	column.add_child(_note("Morale follows how they feel at work and their pay. Under %d for %d days, they quit." % [
			roundi(StaffRoster.QUIT_MORALE), StaffRoster.QUIT_DAYS]))
	_payroll_box.add_theme_constant_override(&"separation", 6)
	column.add_child(_payroll_box)
	column.add_child(HSeparator.new())
	column.add_child(_heading("Applicants"))
	column.add_child(_note("Each waits %d days for an answer; more apply each night. Wages are a day shift's; nights pay more." % StaffRoster.APPLICANT_DAYS))
	_applicant_box.add_theme_constant_override(&"separation", 6)
	column.add_child(_applicant_box)
	return scroll


func _list_staff() -> void:
	for box: VBoxContainer in [_applicant_box, _payroll_box]:
		for child in box.get_children():
			box.remove_child(child)
			child.queue_free()
	for applicant in roster.applicants:
		var role := shifts.role_def(applicant.role)
		var words := "%s, %s shift. Asks %s a day." % [role.display_name if role != null else String(applicant.role),
				applicant.shift, Ledger.text(applicant.wage)]
		var hire := Button.new()
		hire.text = "Hire"
		hire.focus_mode = FOCUS_NONE
		if not shifts.may_add(applicant.role, applicant.shift):
			hire.disabled = true
			hire.tooltip_text = "No room for another %s." % (role.display_name.to_lower() if role != null else "")
		hire.pressed.connect(func() -> void:
			if _may_hire() and shifts.may_add(applicant.role, applicant.shift):
				roster.hire(applicant)
				refresh())
		_applicant_box.add_child(_person_row(applicant, words, [hire]))
	if roster.records.is_empty():
		_payroll_box.add_child(_note("Nobody yet."))
	for record in roster.records:
		var role := shifts.role_def(record.role)
		var words := "%s, %s shift, level %d. %s a day. Morale %d.%s" % [role.display_name if role != null else String(record.role),
				record.shift, record.level, Ledger.text(roster.day_pay(record)), roundi(record.morale),
				" Off sick today." if roster.is_off(record) else ""]
		var raise := Button.new()
		raise.text = "Raise"
		raise.focus_mode = FOCUS_NONE
		raise.tooltip_text = "Pay them %d%% more, which lifts their morale." % roundi(StaffRoster.RAISE * 100.0)
		raise.pressed.connect(func() -> void:
			roster.raise(record)
			refresh())
		var dismiss := Button.new()
		dismiss.text = "Let go"
		dismiss.focus_mode = FOCUS_NONE
		dismiss.tooltip_text = "They go home and don't come back, with %s as notice." % Ledger.text(roster.day_pay(record))
		dismiss.pressed.connect(func() -> void:
			roster.dismiss(record)
			refresh())
		var row := _person_row(record, words, [raise, dismiss])
		if record.morale < StaffRoster.QUIT_MORALE + 10.0:
			row.get_child(0).get_child(1).add_theme_color_override(&"font_color", Color(0.75, 0.35, 0.32))
		_payroll_box.add_child(row)


func _person_row(record: StaffRoster.Record, words: String, buttons: Array) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 6)
	var text := VBoxContainer.new()
	text.add_theme_constant_override(&"separation", 0)
	text.size_flags_horizontal = SIZE_EXPAND_FILL
	var name_label := Label.new()
	name_label.text = record.name
	text.add_child(name_label)
	var about := _note(words)
	text.add_child(about)
	if not record.traits.is_empty():
		text.add_child(_note(", ".join(record.traits.map(func(t: TraitDef) -> String: return t.display_name))))
	row.add_child(text)
	for button: Button in buttons:
		button.size_flags_vertical = SIZE_SHRINK_CENTER
		row.add_child(button)
	return row


func _heading(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.theme_type_variation = &"HeaderLabel"
	return label


func _note(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.theme_type_variation = &"SubtleLabel"
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label


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
	for shift in shifts.shifts if shifts != null else []:
		sum += shifts.wage_bill(shift.id) * shift.pay_scale
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
