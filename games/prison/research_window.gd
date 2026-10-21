class_name ResearchWindow
extends PanelContainer
## The research board, laid out as on the mock-up: know-how along the top,
## a tab per tree (the warden's and one per department), the chosen tree
## drawn left to right in tier bands, and a panel on the right. With
## nothing picked the panel shows the desks, trials and the tree's tools
## (budget, conference, deputy, refinement); a picked card shows what it
## gives, needs and leads to, with Start, Queue or Stop. Toggle with N.

const REFRESH_SECONDS := 0.5
const SIDE_WIDTH := 330.0
## Room the book keeps around a page: its rail, margins and the build bar.
const BOOK_ROOM := Vector2(150, 76 + 96 + 44)

var research: Research
var knowhow: Knowhow
var heads: Heads

var _chips := HFlowContainer.new()
var _lean := Label.new()
var _tabs := HBoxContainer.new()
var _tab_buttons: Dictionary[StringName, Button] = {}
var _scroll := ScrollContainer.new()
var _view := ResearchTreeView.new()
var _side := VBoxContainer.new()
var _wait := 0.0
## What the side panel was built from, so it's only rebuilt when it changes.
var _built := ""
## Labels that change between rebuilds: [Label, Callable returning text].
var _live: Array = []


func _ready() -> void:
	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", 8)
	add_child(box)
	var heading := HBoxContainer.new()
	heading.add_theme_constant_override(&"separation", 12)
	var title := Label.new()
	title.text = "Research"
	title.theme_type_variation = &"HeaderLabel"
	heading.add_child(title)
	_chips.add_theme_constant_override(&"h_separation", 14)
	_chips.size_flags_horizontal = SIZE_EXPAND_FILL
	_chips.alignment = FlowContainer.ALIGNMENT_BEGIN
	heading.add_child(_chips)
	_lean.theme_type_variation = &"SubtleLabel"
	heading.add_child(_lean)
	var close := Button.new()
	close.text = "Close"
	close.theme_type_variation = &"FlatButton"
	close.focus_mode = FOCUS_NONE
	close.pressed.connect(hide)
	heading.add_child(close)
	box.add_child(heading)

	var body := HBoxContainer.new()
	body.add_theme_constant_override(&"separation", 12)
	body.size_flags_vertical = SIZE_EXPAND_FILL
	box.add_child(body)
	var left := VBoxContainer.new()
	left.size_flags_horizontal = SIZE_EXPAND_FILL
	left.add_theme_constant_override(&"separation", 0)
	body.add_child(left)
	_tabs.add_theme_constant_override(&"separation", 4)
	left.add_child(_tabs)
	_scroll.size_flags_vertical = SIZE_EXPAND_FILL
	_scroll.size_flags_horizontal = SIZE_EXPAND_FILL
	left.add_child(_scroll)
	_view.card_pressed.connect(_select)
	_scroll.add_child(_view)
	var side_scroll := ScrollContainer.new()
	side_scroll.custom_minimum_size.x = SIDE_WIDTH
	side_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_side.size_flags_horizontal = SIZE_EXPAND_FILL
	_side.add_theme_constant_override(&"separation", 10)
	side_scroll.add_child(_side)
	body.add_child(side_scroll)
	visible = false
	get_viewport().size_changed.connect(_fit)
	_fit()


## As big as the book allows, so the tree has room.
func _fit() -> void:
	custom_minimum_size = (get_viewport_rect().size - BOOK_ROOM).max(Vector2(720, 420))


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
	if research == null:
		return
	if _tab_buttons.is_empty():
		_view.research = research
		_view.heads = heads
		for id in ResearchTreeView.trees():
			var button := Button.new()
			button.toggle_mode = true
			button.focus_mode = FOCUS_NONE
			_set_dot(button, ResearchTreeView.TREE_COLOURS[id])
			button.pressed.connect(_show_tree.bind(id))
			_tabs.add_child(button)
			_tab_buttons[id] = button
		_show_tree(&"office")
	_lean.text = "Character: %s" % research.lean_words() if research.mode != Research.Mode.OFF else "Research is off"
	for id: StringName in _tab_buttons:
		var ready := ResearchTreeView.cards_in(id).filter(func(card: StringName) -> bool:
			return research.state_of(card) == Research.State.FACE_UP and research.available(research.card(card))).size()
		_tab_buttons[id].text = "%s%s" % [_view.tree_name(id), "  %d" % ready if ready > 0 else ""]
		_tab_buttons[id].tooltip_text = "%d cards ready to start" % ready if ready > 0 else ""
		_tab_buttons[id].set_pressed_no_signal(id == _view.tree)
	var key := _state_key()
	if key != _built:
		_built = key
		_rebuild()
	for entry: Array in _live:
		(entry[0] as Label).text = (entry[1] as Callable).call()
	_view.queue_redraw()


## Shows a tree, or a card in its tree.
func show_card(id: StringName) -> void:
	var def := research.card(id)
	if def == null:
		return
	if not ResearchTreeView.cards_in(_view.tree).has(id):
		var home := ResearchTreeView.home_of(def, research.board)
		var trees := ResearchTreeView.trees().filter(func(t: StringName) -> bool: return ResearchTreeView.cards_in(t).has(id))
		if not trees.is_empty():
			_show_tree(home if trees.has(home) else trees[0])
	_view.selected = &""
	_select(id)
	# Once the tree has its new size, so the scroll isn't clamped.
	await get_tree().process_frame
	var rect := _view.card_rect(id)
	_scroll.scroll_horizontal = int(maxf(0.0, rect.get_center().x - _scroll.size.x / 2.0))
	_scroll.scroll_vertical = int(maxf(0.0, rect.get_center().y - _scroll.size.y / 2.0))


func _show_tree(id: StringName) -> void:
	_view.tree = id
	_view.selected = &""
	_scroll.scroll_horizontal = 0
	_scroll.scroll_vertical = 0
	_built = ""
	refresh()


func _select(id: StringName) -> void:
	_view.selected = id if _view.selected != id else &""
	_built = ""
	refresh()


## Everything the side panel shows apart from progress and know-how.
func _state_key() -> String:
	var parts := PackedStringArray([_view.tree, _view.selected, research.mode, research.slots(), research.queues,
			research.trials.keys(), research.budget, research.conferences.keys(), research.refinements])
	if _view.selected != &"":
		var def := research.card(_view.selected)
		parts.append("%d%s" % [research.state_of(def.id), research.why_not(def)])
	else:
		for id in research.slots():
			parts.append(str(research.slot_card(id)))
	return "|".join(parts)


func _rebuild() -> void:
	for holder: Control in [_chips, _side]:
		for child in holder.get_children():
			child.queue_free()
	_live.clear()
	_chips.visible = research.mode != Research.Mode.OFF
	for def in knowhow.kinds:
		var chip := Label.new()
		chip.tooltip_text = "Earned today: %s" % knowhow.breakdown(def.id)
		chip.mouse_filter = MOUSE_FILTER_PASS
		var tree_of: StringName = research.board.kind_departments.get(def.id, &"admin")
		chip.add_theme_color_override(&"font_color", ResearchTreeView.TREE_COLOURS.get(tree_of, def.colour))
		var id := def.id
		_live.append([chip, func() -> String: return knowhow.chip_text(id)])
		_chips.add_child(chip)
	if _view.selected != &"":
		_card_panel(research.card(_view.selected))
	else:
		_desks_panel()


# --- With nothing picked: the desks ----------------------------------------

func _desks_panel() -> void:
	_side.add_child(_heading("Desks"))
	if research.mode == Research.Mode.OFF:
		_side.add_child(_words("Research is off: every card is done, and the pick-one cards are policies to choose between.", true))
	else:
		for slot in research.slots():
			_side.add_child(_slot_row(slot))
	for id: StringName in research.trials:
		_side.add_child(_trial_row(research.card(id)))
	_tree_tools()
	_side.add_child(HSeparator.new())
	_side.add_child(_heading("How to read a tree"))
	_side.add_child(_words("Each tab is one tree in tier columns; lines always run to a higher tier. Click a card to see what it gives and needs, and to start it. A coloured tag such as Needs Medical means it also needs a card from another tree, and \"opens 2 ↗\" means it leads to cards elsewhere.", true))
	_side.add_child(_words("Face-down cards turn up from how the prison is run; hover one for its hint. Tiers 4 and 5 need a 3-star grade and tier 6 a 4-star grade. ▲ leans strict and ♥ leans caring; a pick-one card shuts off its partner.", true))


func _slot_row(slot: StringName) -> Control:
	var line := HBoxContainer.new()
	var words := Label.new()
	words.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	words.size_flags_horizontal = SIZE_EXPAND_FILL
	_live.append([words, func() -> String:
		var def := research.slot_card(slot)
		var queued: Array = research.queues.get(slot, [])
		var next := "" if queued.is_empty() else " Next: %s." % ", ".join(queued.map(func(id: StringName) -> String:
			return research.card(id).display_name))
		if def == null:
			return "%s: free.%s" % [research.slot_name(slot), next]
		var away := research.away_line(research.states[def.id])
		return "%s: %s, %d%%.%s%s" % [research.slot_name(slot), def.display_name, roundi(research.progress(def) * 100.0),
				next, "" if away == "" else " " + away]])
	line.add_child(words)
	var def := research.slot_card(slot)
	if def != null:
		line.add_child(_button("Show", "Shows the card on its tree.", show_card.bind(def.id)))
	return line


## Budgets, conferences, deputies and the refinement for the tree on show.
func _tree_tools() -> void:
	var wedge := _view.tree
	var tools := VBoxContainer.new()
	if wedge != Research.OFFICE and research.has_flag(&"department_budgets"):
		var line := HBoxContainer.new()
		var label := Label.new()
		label.text = "%s budget a day" % _view.tree_name(wedge)
		label.size_flags_horizontal = SIZE_EXPAND_FILL
		line.add_child(label)
		var spin := SpinBox.new()
		spin.max_value = 500
		spin.step = 50
		spin.value = research.budget.get(wedge, 0)
		spin.prefix = "£"
		spin.tooltip_text = "Each £100 a day makes this tree's research 10%% faster, up to %d%%." \
				% roundi((Research.BUDGET_MOST - 1.0) * 100.0)
		spin.value_changed.connect(func(value: float) -> void: research.set_budget(wedge, int(value)))
		line.add_child(spin)
		tools.add_child(line)
	var department := heads.find(wedge) if wedge != Research.OFFICE else null
	var head := heads.head(department) if department != null else null
	if head != null and research.has_flag(&"conferences"):
		var go := _button("Send %s to a conference (%s)" % [head.first_name(), Ledger.text(Research.CONFERENCE_COST)],
				"Away %d days; back with %d new cards in this tree." % [Research.CONFERENCE_DAYS, Research.CONFERENCE_CARDS],
				func() -> void: research.send_to_conference(head))
		var why := research.why_no_conference(head)
		go.disabled = not why.is_empty()
		if go.disabled:
			go.tooltip_text = why
		tools.add_child(go)
	if research.has_flag(&"deputy_warden" if wedge == Research.OFFICE else &"deputy_heads"):
		var why := research.why_no_deputy(wedge)
		var take := _button("Take on a deputy", why if not why.is_empty() else "A second research slot in this tree.",
				func() -> void: research.take_on_deputy(wedge))
		take.disabled = not why.is_empty()
		tools.add_child(take)
	var refine := research.board.refinement(wedge)
	if refine != null and research.state_of(refine.id) != Research.State.HIDDEN:
		tools.add_child(_button("%s (done %d times)" % [refine.display_name, research.refinements.get(wedge, 0)],
				refine.gives_text, _select.bind(refine.id)))
	if tools.get_child_count() > 0:
		_side.add_child(HSeparator.new())
		_side.add_child(_heading(_view.tree_name(wedge)))
		_side.add_child(tools)


func _trial_row(def: ResearchCardDef) -> Control:
	var row := VBoxContainer.new()
	var words := Label.new()
	words.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_live.append([words, func() -> String:
		var trial: Dictionary = research.trials.get(def.id, {})
		if trial.is_empty():
			return ""
		return "Trial: %s, in %d rooms. %s" % [def.display_name, (trial.rooms as Array).size(), research.trial_words(def)]])
	row.add_child(words)
	row.add_child(_trial_buttons(def))
	return row


func _trial_buttons(def: ResearchCardDef) -> Control:
	var line := HFlowContainer.new()
	line.add_child(_button("Roll it out", "Everywhere, from now on.", func() -> void: research.roll_out(def)))
	line.add_child(_button("Try another wing", "Starts the trial again in the other rooms.", func() -> void: research.adjust(def)))
	line.add_child(_button("Shelve it", "Half its know-how back.", func() -> void: research.shelve(def)))
	return line


# --- A picked card ---------------------------------------------------------------

func _card_panel(def: ResearchCardDef) -> void:
	var state := research.state_of(def.id)
	var top := HBoxContainer.new()
	var tree_label := Label.new()
	var home := ResearchTreeView.home_of(def, research.board)
	tree_label.text = _view.tree_name(def.department if def.department != &"" else home)
	tree_label.add_theme_color_override(&"font_color", ResearchTreeView.TREE_COLOURS.get(def.department, Color.GRAY))
	tree_label.size_flags_horizontal = SIZE_EXPAND_FILL
	top.add_child(tree_label)
	top.add_child(_button("Back", "Back to the desks.", _select.bind(def.id)))
	_side.add_child(top)
	var name := Label.new()
	name.text = def.display_name if state != Research.State.HIDDEN else "A face-down card"
	name.theme_type_variation = &"HeaderLabel"
	name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_side.add_child(name)
	var tags := PackedStringArray()
	if def.tier > 0:
		tags.append("Tier %d, %s" % [def.tier, _view.gate(def.tier)])
	if def.lean != 0:
		tags.append("leans strict" if def.lean > 0 else "leans caring")
	if def.trial:
		tags.append("a policy: tried in one wing first")
	if research.is_joint(def):
		tags.append("joint: worked at %d:00 meetings" % Research.MEETING_HOUR)
	if not tags.is_empty():
		var text := ", ".join(tags)
		_side.add_child(_words(text.left(1).to_upper() + text.substr(1) + ".", true))
	if state == Research.State.HIDDEN:
		_side.add_child(_section("Turns up", research.hint_words(def)))
		_needs(def)
		return
	_side.add_child(_section("Gives", def.gives_text))
	if not def.knowhow.is_empty():
		var cost := research.cost(def)
		var parts := PackedStringArray()
		for id: StringName in cost:
			var kind := knowhow.kind(id)
			parts.append("%s %d" % [kind.display_name if kind != null else String(id), cost[id]])
		_side.add_child(_section("Costs", "%s know-how, then %s at a desk." % [", ".join(parts),
				DeskWork.time_text(research.minutes(def))]))
	if not research.states[def.id].revealed_by.is_empty():
		_side.add_child(_section("Turned up", research.states[def.id].revealed_by))
	_needs(def)
	if def.pair != &"":
		var pair := VBoxContainer.new()
		pair.add_child(_lab("Pick one"))
		pair.add_child(_words("Researching this shuts off its partner, unless you pay double later to switch.", true))
		pair.add_child(_card_link(def.pair))
		_side.add_child(pair)
	var leads := research.board.children(def.id).filter(research.is_shown)
	var leads_box := VBoxContainer.new()
	leads_box.add_child(_lab("Leads to"))
	if leads.is_empty():
		leads_box.add_child(_words("Nothing further. Once its tree is finished, a repeatable refinement takes over.", true))
	for child: ResearchCardDef in leads:
		leads_box.add_child(_card_link(child.id))
	_side.add_child(leads_box)
	_side.add_child(HSeparator.new())
	_actions(def, state)


func _needs(def: ResearchCardDef) -> void:
	if def.requires.is_empty():
		return
	var box := VBoxContainer.new()
	var rule := "Needs" if def.requires.size() == 1 else "Needs all of" if def.rule == 0 \
			else "Needs any one of" if def.needed() == 1 else "Needs %d of" % def.needed()
	box.add_child(_lab(rule))
	for id in def.requires:
		box.add_child(_card_link(id))
	_side.add_child(box)


func _actions(def: ResearchCardDef, state: Research.State) -> void:
	var status := Label.new()
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_live.append([status, func() -> String: return _status_words(def)])
	_side.add_child(status)
	var line := HFlowContainer.new()
	if research.mode == Research.Mode.OFF:
		if def.pair != &"" and state != Research.State.DONE:
			line.add_child(_button("Choose this policy", "Picks it over %s." % research.card(def.pair).display_name,
					func() -> void: research.choose_policy(def), &"AccentButton"))
	elif state == Research.State.FACE_UP:
		var why := research.why_not(def)
		var start := _button("Start", "Pays its know-how and puts it on a desk.", func() -> void: research.begin(def), &"AccentButton")
		start.disabled = not why.is_empty()
		line.add_child(start)
		if why.is_empty() or why.ends_with("queue it instead."):
			line.add_child(_button("Queue", "Starts when its tree's desk is free.", func() -> void: research.queue(def)))
		if not why.is_empty():
			_side.add_child(_words(why, true))
	elif state == Research.State.RESEARCHING or state == Research.State.PAUSED:
		line.add_child(_button("Stop", "All its know-how back; its progress is kept.", func() -> void: research.cancel(def)))
	elif state == Research.State.TRIAL:
		_side.add_child(_words(research.trial_words(def), false))
		line = _trial_buttons(def)
	if line.get_child_count() > 0:
		_side.add_child(line)


func _status_words(def: ResearchCardDef) -> String:
	match research.state_of(def.id):
		Research.State.RESEARCHING:
			var s: Research.CardState = research.states[def.id]
			var who := research.slot_name(s.slot) if s.slot != &"" else "The warden"
			if s.partner != &"":
				who += " and %s" % research.slot_name(s.partner)
			var away := research.away_line(s)
			return "%s: %d%% done.%s" % [who, roundi(research.progress(def) * 100.0), "" if away == "" else "\n" + away]
		Research.State.PAUSED:
			return "Paused at %d%%: nobody is at its desk. It goes on when its head is hired again." % roundi(research.progress(def) * 100.0)
		Research.State.TRIAL:
			return "On trial in one wing."
		Research.State.DONE:
			return "Done."
		Research.State.LOCKED_OUT:
			return "Locked out by %s." % research.card(def.pair).display_name if def.pair != &"" else "Locked out."
	if def.repeatable:
		return "Done %d times so far." % research.refinements.get(def.department, 0)
	return ""


# --- Bits --------------------------------------------------------------------------

func _card_link(id: StringName) -> Button:
	var def := research.card(id)
	var hidden := research.state_of(id) == Research.State.HIDDEN
	var mark := "✓ " if research.is_done(id) else ""
	var home := ResearchTreeView.home_of(def, research.board)
	var button := _button("%s%s" % [mark, "A face-down card" if hidden else def.display_name],
			"In the %s tree." % _view.tree_name(home), show_card.bind(id))
	button.theme_type_variation = &"FlatButton"
	_set_dot(button, ResearchTreeView.TREE_COLOURS.get(home, Color.GRAY))
	return button


func _heading(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.theme_type_variation = &"TitleLabel"
	return label


func _lab(text: String) -> Label:
	var label := Label.new()
	label.text = text.to_upper()
	label.theme_type_variation = &"KeyLabel"
	return label


func _section(title: String, text: String) -> Control:
	var box := VBoxContainer.new()
	box.add_child(_lab(title))
	box.add_child(_words(text, false))
	return box


func _words(text: String, subtle: bool) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = SIDE_WIDTH - 20
	if subtle:
		label.theme_type_variation = &"SubtleLabel"
	return label


func _button(text: String, tip: String, pressed: Callable, variation: StringName = &"") -> Button:
	var button := Button.new()
	button.text = text
	button.tooltip_text = tip
	button.focus_mode = FOCUS_NONE
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	if variation != &"":
		button.theme_type_variation = variation
	button.pressed.connect(func() -> void:
		pressed.call()
		_built = ""
		refresh())
	return button


## A tree's colour dot as a button's icon, unaffected by the theme's
## icon tint.
static func _set_dot(button: Button, colour: Color) -> void:
	button.icon = _dot(colour)
	for state in [&"icon_normal_color", &"icon_hover_color", &"icon_pressed_color", &"icon_hover_pressed_color",
			&"icon_focus_color", &"icon_disabled_color"]:
		button.add_theme_color_override(state, Color.WHITE)


static var _dots: Dictionary = {}


static func _dot(colour: Color) -> Texture2D:
	if not _dots.has(colour):
		var image := Image.create(10, 10, false, Image.FORMAT_RGBA8)
		for y in 10:
			for x in 10:
				var d := Vector2(x + 0.5, y + 0.5).distance_to(Vector2(5, 5))
				image.set_pixel(x, y, Color(colour, clampf(5.0 - d, 0.0, 1.0)))
		_dots[colour] = ImageTexture.create_from_image(image)
	return _dots[colour]
