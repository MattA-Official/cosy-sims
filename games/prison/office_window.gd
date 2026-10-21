class_name OfficeWindow
extends PanelContainer
## The warden's office: who comes on the bus each morning, and (with a
## warden) the grant goals and the prison's grade. Toggle with O.

const REFRESH_SECONDS := 0.5

var office: Office
var intake: Intake
var standing: Standing
var consequences: Consequences
var searching: Searching
## For the Kitchen and stores section. Optional.
var kitchen: Kitchen
var finances: Finances
var supplies: Supplies
## Opens the research board. Optional.
var open_research: Callable
## For the Events section. Optional.
var events: Events
## For the Shop section. Optional.
var shop: Shop
## What the town thinks, shown beside the grade. Optional.
var reputation: Reputation
## Protestors at the gate, and () -> bool to have a word with them (and
## whether the warden may). Optional.
var protest: Protest
var have_a_word: Callable
var may_have_a_word: Callable
var _word := Button.new()

var _missing := Label.new()
var _limit := Label.new()
var _limit_row := HBoxContainer.new()
var _beds := Label.new()
var _checks: Dictionary[StringName, CheckBox] = {}
var _caps: Dictionary[StringName, Label] = {}
var _cap_rows: Array[Control] = []
var _forecast := Label.new()
var _offer_row := HBoxContainer.new()
var _offer := Label.new()
var _buttons: Array[Button] = []
var _wait := 0.0
var _grade := Label.new()
var _measures := Label.new()
var _goals := VBoxContainer.new()
## The scenario's win goals, pinned at the top.
var _scenario := VBoxContainer.new()
var _report := Label.new()
var _policies: Array[Control] = []
var _searches := OptionButton.new()
var _days := OptionButton.new()
var _quiet := CheckBox.new()
var _meals := OptionButton.new()
var _stock := Label.new()
var _event_pick := OptionButton.new()
var _event_day := OptionButton.new()
var _event_list := VBoxContainer.new()
## What the event list last showed, so it is only rebuilt when it changes.
var _event_key := ""
var _shop_words := Label.new()
var _shop_box := VBoxContainer.new()
var _savings := OptionButton.new()
## Item id -> [CheckBox, Label] for each thing the shop sells.
var _shop_rows: Dictionary[StringName, Array] = {}


func _ready() -> void:
	set_anchors_and_offsets_preset(PRESET_CENTER_TOP, PRESET_MODE_MINSIZE)
	grow_horizontal = GROW_DIRECTION_BOTH
	offset_top = 76.0
	custom_minimum_size = Vector2(460, 0)
	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", 8)
	add_child(box)

	var heading := HBoxContainer.new()
	var title := Label.new()
	title.text = "Warden's office"
	title.theme_type_variation = &"HeaderLabel"
	heading.add_child(title)
	var spacer := Control.new()
	spacer.size_flags_horizontal = SIZE_EXPAND_FILL
	heading.add_child(spacer)
	var board := Button.new()
	board.text = "Research board (N)"
	board.tooltip_text = "Know-how, cards and trials."
	board.theme_type_variation = &"FlatButton"
	board.focus_mode = FOCUS_NONE
	board.pressed.connect(func() -> void:
		if open_research.is_valid():
			open_research.call())
	heading.add_child(board)
	var close := Button.new()
	close.text = "Close"
	close.theme_type_variation = &"FlatButton"
	close.focus_mode = FOCUS_NONE
	close.pressed.connect(hide)
	heading.add_child(close)
	box.add_child(heading)
	_missing.theme_type_variation = &"SubtleLabel"
	_missing.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_missing)
	_scenario.add_theme_constant_override(&"separation", 2)
	box.add_child(_scenario)

	var intake_heading := Label.new()
	intake_heading.text = "Intake"
	intake_heading.theme_type_variation = &"HeaderLabel"
	box.add_child(intake_heading)
	var words := Label.new()
	words.text = "The bus comes at %02d:00. Each arrival is searched at reception, then walked to a free bed." \
			% Intake.BUS_HOUR
	words.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	words.theme_type_variation = &"SubtleLabel"
	box.add_child(words)

	var name_label := Label.new()
	name_label.text = "Arrivals a day"
	name_label.size_flags_horizontal = SIZE_EXPAND_FILL
	_limit_row.add_child(name_label)
	_limit_row.add_child(_stepper(func() -> void: intake.limit = maxi(intake.limit - 1, 0)))
	_limit.custom_minimum_size = Vector2(56, 0)
	_limit.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_limit_row.add_child(_limit)
	_limit_row.add_child(_stepper(func() -> void:
		intake.limit = mini(intake.limit + 1, Intake.MOST_WITHOUT_WARDEN)))
	box.add_child(_limit_row)
	for def in intake.categories:
		var row := HBoxContainer.new()
		var check := CheckBox.new()
		check.text = def.display_name
		check.tooltip_text = "%s\nGrant: %s a day each." % [def.description, Ledger.text(def.daily_grant)]
		check.focus_mode = FOCUS_NONE
		check.size_flags_horizontal = SIZE_EXPAND_FILL
		var id := def.id
		check.toggled.connect(func(on: bool) -> void: intake.accepted[id] = on)
		row.add_child(check)
		_checks[def.id] = check
		row.add_child(_button("−", func() -> void: intake.caps[id] = maxi(intake.caps.get(id, 0) - 1, 0)))
		var cap := Label.new()
		cap.custom_minimum_size = Vector2(56, 0)
		cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cap.tooltip_text = "The most a day. Mondays bring this many; other days a few fewer."
		cap.mouse_filter = MOUSE_FILTER_PASS
		row.add_child(cap)
		_caps[def.id] = cap
		row.add_child(_button("+", func() -> void:
			intake.caps[id] = mini(intake.caps.get(id, 0) + 1, Intake.MOST_CAP)))
		_cap_rows.append(row)
		box.add_child(row)
	_forecast.theme_type_variation = &"SubtleLabel"
	_forecast.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_forecast)
	_offer_row.add_theme_constant_override(&"separation", 8)
	_offer.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_offer.size_flags_horizontal = SIZE_EXPAND_FILL
	_offer_row.add_child(_offer)
	_offer_row.add_child(_button("Accept", func() -> void: intake.accept_offer()))
	_offer_row.add_child(_button("Decline", func() -> void: intake.decline_offer()))
	box.add_child(_offer_row)
	_beds.theme_type_variation = &"SubtleLabel"
	box.add_child(_beds)
	if consequences != null and searching != null:
		_add_policies(box)
	if kitchen != null:
		_add_stores(box)
	if events != null:
		_add_events(box)
	if shop != null:
		_add_shop(box)
	if standing != null:
		box.add_child(HSeparator.new())
		_grade.theme_type_variation = &"HeaderLabel"
		_grade.tooltip_text = "Graded each midnight on safety, wellbeing, reform and money. A better grade brings a bigger grant."
		_grade.mouse_filter = MOUSE_FILTER_PASS
		box.add_child(_grade)
		_measures.theme_type_variation = &"SubtleLabel"
		box.add_child(_measures)
		_word.text = "Have a word with the protestors"
		_word.tooltip_text = "The warden goes out to the gate to talk things over, which calms the crowd. Once a week, with the Public relations card."
		_word.focus_mode = FOCUS_NONE
		_word.pressed.connect(func() -> void:
			if have_a_word.is_valid():
				have_a_word.call()
			refresh())
		box.add_child(_word)
		box.add_child(HSeparator.new())
		var goals_heading := Label.new()
		goals_heading.text = "Grant goals"
		goals_heading.theme_type_variation = &"HeaderLabel"
		box.add_child(goals_heading)
		_goals.add_theme_constant_override(&"separation", 2)
		box.add_child(_goals)
		_report.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_report.theme_type_variation = &"SubtleLabel"
		box.add_child(_report)
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


func refresh() -> void:
	if intake == null:
		return
	var warden := office.has_warden()
	var missing := office.missing()
	_missing.text = "The warden is in charge." if missing.is_empty() else missing
	if not warden:
		_missing.text += " Until then you set a simple number a day of low or medium security prisoners."
	_limit_row.visible = not warden
	_limit.text = str(intake.limit) if intake.limit > 0 else "Closed"
	for row in _cap_rows:
		row.visible = warden
	for id: StringName in _checks:
		_checks[id].set_pressed_no_signal(intake.accepted.get(id, false))
		_caps[id].text = str(intake.caps.get(id, 0))
	var days := PackedStringArray()
	for entry: Array in intake.forecast():
		days.append("%s %d" % [(entry[1] as String).left(3), entry[2]])
	_forecast.text = "Next 7 days: " + " · ".join(days)
	_offer_row.visible = warden and not intake.offer.is_empty()
	if not intake.offer.is_empty():
		var category := PrisonCatalogue.categories().get(intake.offer.category) as CategoryDef
		_offer.text = "Transfer offer: %d %s prisoners on tomorrow's bus, %s each." % [intake.offer.count,
				category.display_name.to_lower() if category != null else String(intake.offer.category),
				Ledger.text(intake.offer.fee)]
	for control in _policies:
		if control is BaseButton:
			(control as BaseButton).disabled = not warden
	if kitchen != null:
		_meals.disabled = not warden
		_meals.selected = maxi(PrisonCatalogue.MEALS.find(kitchen.meal), 0)
		_stock.text = stock_text()
	if events != null:
		_show_events()
	if shop != null:
		_show_shop()
	if searching != null:
		_searches.selected = maxi(Searching.POLICIES.find(searching.random_per_day), 0)
		_days.selected = maxi(DAYS.find(roundi(consequences.privilege_days)), 0)
		_quiet.set_pressed_no_signal(consequences.quiet_room_on)
	var problems := intake.warnings()
	_beds.text = problems[0] if not problems.is_empty() else "%d free beds." % intake.free_beds()
	if standing != null:
		_show_standing(warden)


## How long privileges are lost for, in game days.
const DAYS: Array[int] = [1, 2, 4]


func _add_policies(box: VBoxContainer) -> void:
	box.add_child(HSeparator.new())
	var heading := Label.new()
	heading.text = "Policies"
	heading.theme_type_variation = &"HeaderLabel"
	box.add_child(heading)
	for count in Searching.POLICIES:
		_searches.add_item("None" if count == 0 else "%d a day" % count)
	_searches.item_selected.connect(func(index: int) -> void: searching.random_per_day = Searching.POLICIES[index])
	_searches.tooltip_text = "Guards turn over random cells. Finds contraband, but being searched puts prisoners out."
	box.add_child(_row("Random cell searches", _searches))
	for days in DAYS:
		_days.add_item("%d day%s" % [days, "" if days == 1 else "s"])
	_days.item_selected.connect(func(index: int) -> void: consequences.privilege_days = DAYS[index])
	_days.tooltip_text = "How long a prisoner loses the yard, the telly or games after an offence."
	box.add_child(_row("Privileges lost for", _days))
	_quiet.text = "Quiet room for fights"
	_quiet.tooltip_text = "Fighters spend a day in a quiet room, if you have one. Off, they lose two privileges instead."
	_quiet.focus_mode = FOCUS_NONE
	_quiet.toggled.connect(func(on: bool) -> void: consequences.quiet_room_on = on)
	box.add_child(_quiet)
	_policies.assign([_searches, _days, _quiet])


func _add_stores(box: VBoxContainer) -> void:
	box.add_child(HSeparator.new())
	var heading := Label.new()
	heading.text = "Kitchen and stores"
	heading.theme_type_variation = &"HeaderLabel"
	box.add_child(heading)
	var tips := PackedStringArray()
	for def in PrisonCatalogue.MEALS:
		_meals.add_item(def.display_name)
		tips.append("%s: %s" % [def.display_name, def.description])
	_meals.tooltip_text = "\n".join(tips) + "\nThe warden sets it."
	_meals.item_selected.connect(func(index: int) -> void: kitchen.meal = PrisonCatalogue.MEALS[index])
	box.add_child(_row("Meals", _meals))
	_stock.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_stock.theme_type_variation = &"SubtleLabel"
	box.add_child(_stock)


func _add_shop(box: VBoxContainer) -> void:
	box.add_child(HSeparator.new())
	var heading := Label.new()
	heading.text = "Shop"
	heading.theme_type_variation = &"HeaderLabel"
	box.add_child(heading)
	_shop_words.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_shop_words.theme_type_variation = &"SubtleLabel"
	box.add_child(_shop_words)
	for share in PrisonLife.SAVE_SHARES:
		_savings.add_item("None" if share == 0.0 else "%d%%" % roundi(share * 100.0))
	_savings.tooltip_text = "Pay put aside for release. Every 50 tokens saved makes coming back a little less likely."
	_savings.item_selected.connect(func(index: int) -> void: shop.save_share = PrisonLife.SAVE_SHARES[index])
	_shop_box.add_child(_row("Savings from pay", _savings))
	for def in shop.items:
		var row := HBoxContainer.new()
		var check := CheckBox.new()
		check.text = "%s, %d token%s" % [def.display_name if def.pack == 1 else "%s (%d)" % [def.display_name, def.pack],
				def.price_tokens, "" if def.price_tokens == 1 else "s"]
		check.tooltip_text = "Untick to stop selling it. Stocking one costs %s." % Ledger.text(def.cost)
		check.focus_mode = FOCUS_NONE
		check.size_flags_horizontal = SIZE_EXPAND_FILL
		var id := def.id
		check.toggled.connect(func(on: bool) -> void: shop.on[id] = on)
		row.add_child(check)
		var numbers := Label.new()
		numbers.theme_type_variation = &"SubtleLabel"
		row.add_child(numbers)
		_shop_rows[def.id] = [check, numbers]
		_shop_box.add_child(row)
	box.add_child(_shop_box)


func _show_shop() -> void:
	_shop_box.visible = shop.exists()
	if not shop.exists():
		_shop_words.text = "Research the Prison shop card to pay prisoners tokens for work and open a shop."
		return
	var sold := 0
	for id: StringName in shop.sold_today:
		sold += shop.sold_today[id]
	_shop_words.text = "Prisoners earn tokens on work programmes and spend them at the till in a shop room, while someone on the Shop programme works it. Shelves are filled at %02d:00. %s today: %d sold." \
			% [Shop.STOCK_HOUR, "Open" if shop.open() else "Closed (nobody at the till)", sold]
	_savings.selected = maxi(PrisonLife.SAVE_SHARES.find(shop.save_share), 0)
	for id: StringName in _shop_rows:
		(_shop_rows[id][0] as CheckBox).set_pressed_no_signal(shop.on.get(id, true))
		(_shop_rows[id][1] as Label).text = "%d in stock, %d sold" % [shop.stock.get(id, 0), shop.sold_today.get(id, 0)]


## How many days ahead an event can be booked.
const EVENT_DAYS_AHEAD := 7


func _add_events(box: VBoxContainer) -> void:
	box.add_child(HSeparator.new())
	var heading := Label.new()
	heading.text = "Events"
	heading.theme_type_variation = &"HeaderLabel"
	box.add_child(heading)
	var words := Label.new()
	words.text = "Put on a one-day event. Prisoners free to go take part, and everyone who does has a great day."
	words.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	words.theme_type_variation = &"SubtleLabel"
	box.add_child(words)
	var tips := PackedStringArray()
	for def in events.defs:
		_event_pick.add_item("%s (%s)" % [def.display_name, Ledger.text(def.cost)])
		tips.append("%s: %s" % [def.display_name, def.description])
	_event_pick.tooltip_text = "\n".join(tips)
	_event_pick.focus_mode = FOCUS_NONE
	for ahead in range(1, EVENT_DAYS_AHEAD + 1):
		_event_day.add_item("Tomorrow" if ahead == 1 else "In %d days" % ahead)
	var row := _row("Event", _event_pick)
	_event_day.focus_mode = FOCUS_NONE
	row.add_child(_event_day)
	row.add_child(_button("Book", func() -> void:
		var day := events.clock.day() + _event_day.selected + 1
		events.schedule(events.defs[_event_pick.selected], day)))
	box.add_child(row)
	_event_list.add_theme_constant_override(&"separation", 2)
	box.add_child(_event_list)


func _show_events() -> void:
	var today := events.clock.day()
	var upcoming := events.upcoming()
	var open := events.defs.map(func(def: EventDef) -> bool: return events.may_put_on(def))
	var key := "%d %d %s %s" % [today, events.attended.size(), upcoming, open]
	if key == _event_key:
		return
	for i in events.defs.size():
		_event_pick.set_item_disabled(i, not open[i])
	_event_key = key
	for child in _event_list.get_children():
		child.queue_free()
	if upcoming.is_empty():
		var none := Label.new()
		none.text = "Nothing booked."
		none.theme_type_variation = &"SubtleLabel"
		_event_list.add_child(none)
	for entry: Array in upcoming:
		var day: int = entry[0]
		var def: EventDef = entry[1]
		var when := "Today" if day == today else "Tomorrow" if day == today + 1 else "Day %d" % day
		var row := HBoxContainer.new()
		var label := Label.new()
		label.text = "%s: %s" % [when, def.display_name]
		if day == today:
			label.text += " (%d taking part so far)" % events.attended.size()
		label.size_flags_horizontal = SIZE_EXPAND_FILL
		row.add_child(label)
		if day > today:
			var cancel := Button.new()
			cancel.text = "Cancel"
			cancel.theme_type_variation = &"FlatButton"
			cancel.focus_mode = FOCUS_NONE
			cancel.pressed.connect(func() -> void:
				events.cancel(day)
				refresh())
			row.add_child(cancel)
		_event_list.add_child(row)


## What's in the stores, and whether there's enough food for tomorrow.
func stock_text() -> String:
	var items := kitchen.items
	var lines := PackedStringArray()
	var crates := items.total(&"ingredient")
	lines.append("Food: %d crate%s, %d meals (tomorrow needs %d)%s." % [crates, "" if crates == 1 else "s",
			kitchen.meals_in_stock(), kitchen.meals_needed(),
			", %s a crate" % Ledger.text(roundi(finances.crate_price())) if finances != null else ""])
	lines.append("Uniforms: %d clean, %d waiting to be washed." % [items.total(&"clean_laundry"), items.total(&"dirty_laundry")])
	if supplies != null:
		lines.append(supplies.words())
	var goods := items.total(&"goods")
	if goods > 0:
		lines.append("Goods waiting for the lorry: %d." % goods)
	for warning in kitchen.warnings():
		lines.append(warning + ".")
	return "\n".join(lines)


func _row(text: String, control: Control) -> HBoxContainer:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = text
	label.size_flags_horizontal = SIZE_EXPAND_FILL
	row.add_child(label)
	control.focus_mode = FOCUS_NONE
	row.add_child(control)
	return row


## A line per measure with why, any measure holding the grade down, and
## the last few nights.
func measures_text() -> String:
	if not standing.measures_known():
		return "First graded at midnight."
	var lines := PackedStringArray()
	for measure: String in standing.measures:
		var stars: int = standing.measures[measure]
		var words := "%s %s" % [measure, "★".repeat(stars) + "☆".repeat(5 - stars)]
		if standing.why.has(measure):
			words += "  " + standing.why[measure]
		lines.append(words)
	if not standing.held_by.is_empty():
		lines.append("Held to %d★ by %s." % [standing.grade, standing.held_by])
	for line in standing.warnings:
		lines.append(line)
	if standing.history.size() > 1:
		lines.append("Last %d nights: %s" % [standing.history.size(), " ".join(standing.history.map(
				func(night: Dictionary) -> String: return "%d★" % night.grade))])
	return "\n".join(lines)


## The scenario's goals and days, warden or not, and any warnings.
func _show_scenario() -> void:
	for child in _scenario.get_children():
		_scenario.remove_child(child)
		child.queue_free()
	_scenario.visible = standing.scenario != null or not standing.warnings.is_empty()
	if standing.scenario != null:
		var heading := Label.new()
		var when := standing.days_left_text()
		heading.text = "%s%s" % [standing.scenario.title, "  ·  " + when if not when.is_empty() else ""]
		heading.theme_type_variation = &"HeaderLabel"
		_scenario.add_child(heading)
		for goal in standing.scenario.win_goals:
			var done := standing.scenario_done.has(goal.id)
			var progress := standing.goal_progress(goal)
			var line := Label.new()
			line.text = "%s %s%s" % ["✓" if done else "○", goal.title,
					" (%s)" % progress if not progress.is_empty() and not done else ""]
			_scenario.add_child(line)
	for warning in standing.warnings:
		var line := Label.new()
		line.text = warning
		line.add_theme_color_override(&"font_color", Color(0.75, 0.3, 0.28))
		line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_scenario.add_child(line)


func _show_standing(warden: bool) -> void:
	_grade.text = "Grade  %s%s" % ["★".repeat(standing.grade), "☆".repeat(5 - standing.grade)]
	if reputation != null:
		_grade.text += "    Town: %s (%d)" % [reputation.words(), roundi(reputation.score)]
		var recent := reputation.recent_words()
		_grade.tooltip_text = "Graded each midnight on safety, wellbeing, reform and money. A better grade brings a bigger grant.\n\n" \
				+ ("What the town has heard lately:\n" + "\n".join(recent) if not recent.is_empty() \
				else "The town hasn't heard much about the prison yet.")
		_grade.mouse_filter = MOUSE_FILTER_STOP
	_measures.text = measures_text()
	_word.visible = protest != null and protest.state == Protest.State.PROTESTING
	_word.disabled = not warden or not may_have_a_word.is_valid() or not may_have_a_word.call()
	for child in _goals.get_children():
		_goals.remove_child(child)
		child.queue_free()
	_show_scenario()
	if not warden:
		var none := Label.new()
		none.text = "A warden in the office takes on grant goals."
		none.theme_type_variation = &"SubtleLabel"
		_goals.add_child(none)
	else:
		for goal in standing.current_goals():
			var row := HBoxContainer.new()
			var title := Label.new()
			var progress := standing.goal_progress(goal)
			title.text = goal.title + (" (%s)" % progress if not progress.is_empty() else "")
			title.size_flags_horizontal = SIZE_EXPAND_FILL
			row.add_child(title)
			var grant := Label.new()
			grant.text = Ledger.text(goal.grant)
			row.add_child(grant)
			_goals.add_child(row)
	_report.text = ("Today's report:\n" + standing.report) if warden and not standing.report.is_empty() else ""


## A − or + for the arrivals without a warden.
func _stepper(pressed: Callable) -> Button:
	var button := Button.new()
	button.text = "−" if _limit_row.get_child_count() == 1 else "+"
	button.focus_mode = FOCUS_NONE
	button.custom_minimum_size = Vector2(32, 0)
	button.pressed.connect(func() -> void:
		pressed.call()
		refresh())
	return button


func _button(text: String, pressed: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = FOCUS_NONE
	button.custom_minimum_size = Vector2(32, 0)
	button.pressed.connect(func() -> void:
		pressed.call()
		refresh())
	_buttons.append(button)
	return button
