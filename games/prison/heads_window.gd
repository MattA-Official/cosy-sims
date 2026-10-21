class_name HeadsWindow
extends PanelContainer
## Department heads: for each department, its head (with how their desk is
## doing), the applicants waiting, the hire card in progress, or a button
## to put the hire card on the warden's desk. Toggle with H.

const REFRESH_SECONDS := 0.5

var heads: Heads
var desk_work: DeskWork
var clock: GameClock

var _desk := Label.new()
var _rows := VBoxContainer.new()
var _wait := 0.0
## What the rows were built from, so they're only rebuilt when it changes.
var _built := ""
## Labels that change between rebuilds: [Label, Callable returning text].
var _live: Array = []


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
	title.text = "Department heads"
	title.theme_type_variation = &"HeaderLabel"
	heading.add_child(title)
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
	var about := Label.new()
	about.text = "The warden works a hire card at their desk, then two people apply. Each head brings their department's bonus while on the payroll, works days at an office desk, and gets a share of the morning's paperwork. A head whose desk piles up gives half their bonus until it's clear."
	about.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	about.theme_type_variation = &"SubtleLabel"
	box.add_child(about)
	_desk.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_desk)
	box.add_child(HSeparator.new())
	_rows.add_theme_constant_override(&"separation", 10)
	box.add_child(_rows)
	visible = false


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


func refresh() -> void:
	if heads == null:
		return
	_desk.text = _desk_text(heads.warden(), "The warden")
	var key := _state_key()
	if key != _built:
		_built = key
		_rebuild()
	for entry: Array in _live:
		(entry[0] as Label).text = (entry[1] as Callable).call()


func _desk_text(record: StaffRoster.Record, who: String) -> String:
	if record == null:
		return "Take on a warden in the Staff window (P) to start hiring heads."
	var minutes := desk_work.pile_minutes(record.id)
	if minutes <= 0.0:
		return "%s's desk is clear." % who
	var parts := PackedStringArray()
	var paper := desk_work.pile_minutes(record.id, &"paperwork")
	if paper > 0.0:
		parts.append("paperwork, %s" % DeskWork.time_text(paper))
	for item in desk_work.items(record.id, &"research"):
		parts.append("%s, %d%% done" % [item.title, roundi(item.done_share() * 100.0)])
	var words := "%s's desk: %s." % [who, "; ".join(parts)]
	if desk_work.is_overloaded(record.id):
		words += " Overloaded: snowed under until it's below %s." % DeskWork.time_text(DeskWork.CLEAR)
	return words


## Who's hired, who's applying and which card is on, in a string.
func _state_key() -> String:
	var parts := PackedStringArray()
	parts.append(str(heads.warden() != null))
	for department in heads.departments:
		var head := heads.head(department)
		parts.append("%s:%s:%s:%s:%s" % [department.id, head.id if head != null else 0,
				heads.applicants(department).map(func(a: StaffRoster.Record) -> int: return a.id),
				heads.hiring() == department, heads.why_not(department)])
	return "|".join(parts)


func _rebuild() -> void:
	for child in _rows.get_children():
		child.queue_free()
	_live.clear()
	for department in heads.departments:
		_rows.add_child(_row(department))


func _row(department: DepartmentDef) -> Control:
	var row := VBoxContainer.new()
	row.add_theme_constant_override(&"separation", 4)
	var top := HBoxContainer.new()
	top.add_theme_constant_override(&"separation", 8)
	var swatch := ColorRect.new()
	swatch.color = department.colour
	swatch.custom_minimum_size = Vector2(6, 0)
	top.add_child(swatch)
	var name_label := Label.new()
	name_label.text = "%s · %s" % [department.display_name, department.head_role.display_name]
	name_label.size_flags_horizontal = SIZE_EXPAND_FILL
	name_label.tooltip_text = department.head_role.description
	name_label.mouse_filter = MOUSE_FILTER_PASS
	top.add_child(name_label)
	var bonus := Label.new()
	bonus.text = department.bonus_text
	bonus.theme_type_variation = &"SubtleLabel"
	top.add_child(bonus)
	row.add_child(top)

	var head := heads.head(department)
	var applicants := heads.applicants(department)
	if head != null:
		var line := HBoxContainer.new()
		var words := Label.new()
		words.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		words.size_flags_horizontal = SIZE_EXPAND_FILL
		_live.append([words, func() -> String:
			return "%s, level %d, morale %d, %s a day.%s %s" % [head.name, head.level, roundi(head.morale),
					Ledger.text(heads.roster.day_pay(head)),
					" %s." % heads.roster.work_trait_words(head) if not head.work_traits.is_empty() else "",
					_desk_text(head, head.first_name())]])
		line.add_child(words)
		line.add_child(_button("Let go", "Pays %d days' wages as notice. Their department's bonus stops." % Heads.NOTICE_DAYS,
				func() -> void: heads.let_go(head)))
		row.add_child(line)
	elif not applicants.is_empty():
		var waiting := Label.new()
		waiting.text = "Applicants, waiting until day %d:" % applicants[0].until
		waiting.theme_type_variation = &"SubtleLabel"
		row.add_child(waiting)
		for applicant in applicants:
			var traits := ", ".join(applicant.work_traits.map(func(t: StaffTraitDef) -> String: return t.display_name))
			row.add_child(_button("Take on %s · %s a day%s" % [applicant.name, Ledger.text(applicant.wage),
					" · %s" % traits if not traits.is_empty() else ""],
					"%s. They start on the next day shift." % heads.roster.work_trait_words(applicant) if not traits.is_empty()
					else "They start on the next day shift.",
					func() -> void: heads.hire(applicant)))
	elif heads.hiring() == department:
		var line := HBoxContainer.new()
		var words := Label.new()
		words.size_flags_horizontal = SIZE_EXPAND_FILL
		_live.append([words, func() -> String:
			var card := heads.hire_card()
			return "Hire card on the warden's desk: %d%% done." % roundi(card.done_share() * 100.0) if card != null else ""])
		line.add_child(words)
		line.add_child(_button("Stop", "Takes the card off the warden's desk; its progress is lost.",
				func() -> void: heads.cancel_hire()))
		row.add_child(line)
	else:
		var line := HBoxContainer.new()
		var why := heads.why_not(department)
		var words := Label.new()
		words.text = why if not why.is_empty() else "No head yet. The hire card takes the warden about %s at their desk." \
				% DeskWork.time_text(department.hire_minutes)
		words.theme_type_variation = &"SubtleLabel"
		words.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		words.size_flags_horizontal = SIZE_EXPAND_FILL
		line.add_child(words)
		var start := _button("Start hire card", "Puts the card on the warden's desk, after the paperwork.",
				func() -> void: heads.start_hire(department))
		start.disabled = not why.is_empty()
		line.add_child(start)
		row.add_child(line)
	return row


func _button(text: String, tip: String, pressed: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.tooltip_text = tip
	button.focus_mode = FOCUS_NONE
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.pressed.connect(func() -> void:
		pressed.call()
		_built = ""
		refresh())
	return button
