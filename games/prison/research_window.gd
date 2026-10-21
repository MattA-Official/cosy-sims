class_name ResearchWindow
extends PanelContainer
## The research board, as lists for now: know-how in hand, who is working
## what (with budgets, deputies and conferences once their cards are
## done), wing trials waiting on a decision, and each wedge's cards by
## tier with Start and Queue. Face-down cards show their hint. Toggle
## with N.

const REFRESH_SECONDS := 0.5
const OFFICE_NAME := "Office"

var research: Research
var knowhow: Knowhow
var heads: Heads

var _chips := HFlowContainer.new()
var _lean := Label.new()
var _slots := VBoxContainer.new()
var _trials := VBoxContainer.new()
var _tabs := TabBar.new()
var _cards := VBoxContainer.new()
var _wedges: Array[StringName] = []
var _wait := 0.0
## What the rows were built from, so they're only rebuilt when it changes.
var _built := ""
## Labels that change between rebuilds: [Label, Callable returning text].
var _live: Array = []


func _ready() -> void:
	set_anchors_and_offsets_preset(PRESET_CENTER_TOP, PRESET_MODE_MINSIZE)
	grow_horizontal = GROW_DIRECTION_BOTH
	offset_top = 76.0
	custom_minimum_size = Vector2(620, 0)
	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", 8)
	add_child(box)
	var heading := HBoxContainer.new()
	var title := Label.new()
	title.text = "Research"
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
	about.text = "Running the prison earns know-how. A card costs know-how to start, then desk time from the warden or the wedge's head. Most cards start face down and turn up from what happens here. Policies are tried in one wing first."
	about.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	about.theme_type_variation = &"SubtleLabel"
	box.add_child(about)
	_chips.add_theme_constant_override(&"h_separation", 14)
	box.add_child(_chips)
	_lean.theme_type_variation = &"SubtleLabel"
	box.add_child(_lean)
	box.add_child(HSeparator.new())
	_slots.add_theme_constant_override(&"separation", 6)
	box.add_child(_slots)
	_trials.add_theme_constant_override(&"separation", 6)
	box.add_child(_trials)
	box.add_child(HSeparator.new())
	_tabs.focus_mode = FOCUS_NONE
	_tabs.tab_changed.connect(func(_tab: int) -> void:
		_built = ""
		refresh())
	box.add_child(_tabs)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 300)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_cards.size_flags_horizontal = SIZE_EXPAND_FILL
	_cards.add_theme_constant_override(&"separation", 6)
	scroll.add_child(_cards)
	box.add_child(scroll)
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
	if research == null:
		return
	if _wedges.is_empty():
		_wedges.append(Research.OFFICE)
		_tabs.add_tab(OFFICE_NAME)
		for department in heads.departments:
			_wedges.append(department.id)
			_tabs.add_tab(department.display_name)
	_lean.text = "Character: %s." % research.lean_words() if research.mode != Research.Mode.OFF else "Research is off."
	var key := _state_key()
	if key != _built:
		_built = key
		_rebuild()
	for entry: Array in _live:
		(entry[0] as Label).text = (entry[1] as Callable).call()


## Everything the rows show apart from progress and know-how, in a string.
func _state_key() -> String:
	var parts := PackedStringArray([_tabs.current_tab, research.mode, research.slots(), research.queues,
			research.trials.keys(), research.budget, research.conferences.keys()])
	for def in _wedge_cards():
		parts.append("%s%d%s" % [def.id, research.state_of(def.id), research.why_not(def)])
	return "|".join(parts)


func _rebuild() -> void:
	for holder: Control in [_chips, _slots, _trials, _cards]:
		for child in holder.get_children():
			child.queue_free()
	_live.clear()
	for def in knowhow.kinds:
		var chip := Label.new()
		chip.tooltip_text = "Earned today: %s" % knowhow.breakdown(def.id)
		chip.mouse_filter = MOUSE_FILTER_PASS
		chip.add_theme_color_override(&"font_color", def.colour.lightened(0.3))
		var id := def.id
		_live.append([chip, func() -> String: return knowhow.chip_text(id)])
		_chips.add_child(chip)
	if research.mode != Research.Mode.OFF:
		for slot in research.slots():
			_slots.add_child(_slot_row(slot))
		_wedge_tools()
	for id: StringName in research.trials:
		_trials.add_child(_trial_row(research.card(id)))
	var by_tier := _wedge_cards()
	by_tier.sort_custom(func(a: ResearchCardDef, b: ResearchCardDef) -> bool: return a.tier < b.tier)
	var tier := 0
	for def in by_tier:
		if def.tier != tier:
			tier = def.tier
			var header := Label.new()
			header.text = "Tier %d%s" % [tier, " · needs a %d-star grade" % Research.GATES[tier] if Research.GATES.has(tier) else ""]
			header.theme_type_variation = &"SubtleLabel"
			_cards.add_child(header)
		_cards.add_child(_card_row(def))


func _wedge() -> StringName:
	return _wedges[_tabs.current_tab] if _tabs.current_tab < _wedges.size() else Research.OFFICE


func _wedge_cards() -> Array[ResearchCardDef]:
	var wedge := _wedge()
	var out: Array[ResearchCardDef] = []
	for def in research.board.cards + research.board.refinements:
		if def.department == wedge and research.is_shown(def) \
				and (not def.repeatable or research.state_of(def.id) != Research.State.HIDDEN):
			out.append(def)
	return out


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
		return "%s: %s, %d%%.%s" % [research.slot_name(slot), def.display_name, roundi(research.progress(def) * 100.0), next]])
	line.add_child(words)
	var def := research.slot_card(slot)
	if def != null and not research.is_hire(def):
		line.add_child(_button("Stop", "All its know-how back; its progress is kept for later.", func() -> void: research.cancel(def)))
	return line


## Budgets, conferences and deputies for the wedge on show.
func _wedge_tools() -> void:
	var wedge := _wedge()
	var line := HBoxContainer.new()
	line.add_theme_constant_override(&"separation", 8)
	if wedge != Research.OFFICE and research.has_flag(&"department_budgets"):
		var label := Label.new()
		label.text = "Budget a day:"
		line.add_child(label)
		var spin := SpinBox.new()
		spin.max_value = 500
		spin.step = 50
		spin.value = research.budget.get(wedge, 0)
		spin.prefix = "£"
		spin.tooltip_text = "Each £100 a day makes this wedge's research 10%% faster, up to %d%%." \
				% roundi((Research.BUDGET_MOST - 1.0) * 100.0)
		spin.value_changed.connect(func(value: float) -> void: research.set_budget(wedge, int(value)))
		line.add_child(spin)
	var head := heads.head(heads.find(wedge)) if wedge != Research.OFFICE else null
	if head != null and research.has_flag(&"conferences"):
		var go := _button("Send %s to a conference (%s)" % [head.first_name(), Ledger.text(Research.CONFERENCE_COST)],
				"Away %d days; back with %d new cards in their wedge." % [Research.CONFERENCE_DAYS, Research.CONFERENCE_CARDS],
				func() -> void: research.send_to_conference(head))
		go.disabled = not research.why_no_conference(head).is_empty()
		if go.disabled:
			go.tooltip_text = research.why_no_conference(head)
		line.add_child(go)
	var flag := &"deputy_warden" if wedge == Research.OFFICE else &"deputy_heads"
	if research.has_flag(flag):
		var why := research.why_no_deputy(wedge)
		var take := _button("Take on a deputy", why if not why.is_empty() else "A second research slot in this wedge.",
				func() -> void: research.take_on_deputy(wedge))
		take.disabled = not why.is_empty()
		line.add_child(take)
	if line.get_child_count() > 0:
		_slots.add_child(line)


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
	var line := HBoxContainer.new()
	line.add_child(_button("Roll it out", "Everywhere, from now on.", func() -> void: research.roll_out(def)))
	line.add_child(_button("Try another wing", "Starts the trial again in the other rooms.", func() -> void: research.adjust(def)))
	line.add_child(_button("Shelve it", "Half its know-how back.", func() -> void: research.shelve(def)))
	row.add_child(line)
	return row


func _card_row(def: ResearchCardDef) -> Control:
	var state := research.state_of(def.id)
	var line := HBoxContainer.new()
	line.add_theme_constant_override(&"separation", 8)
	var words := Label.new()
	words.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	words.size_flags_horizontal = SIZE_EXPAND_FILL
	words.mouse_filter = MOUSE_FILTER_PASS
	if state == Research.State.HIDDEN:
		words.text = "Face down. %s" % (def.reveal.hint if def.reveal != null else "")
		words.theme_type_variation = &"SubtleLabel"
		line.add_child(words)
		return line
	words.text = "%s: %s%s" % [def.display_name, def.gives_text, _state_words(def, state)]
	words.tooltip_text = _cost_words(def)
	if state == Research.State.DONE or state == Research.State.LOCKED_OUT:
		words.theme_type_variation = &"SubtleLabel"
	line.add_child(words)
	if research.mode == Research.Mode.OFF:
		if def.pair != &"" and state != Research.State.DONE:
			line.add_child(_button("Choose", "Picks this policy over %s." % research.card(def.pair).display_name,
					func() -> void: research.choose_policy(def)))
		return line
	if state == Research.State.FACE_UP:
		var why := research.why_not(def)
		var start := _button("Start", why if not why.is_empty() else _cost_words(def), func() -> void: research.begin(def))
		start.disabled = not why.is_empty()
		line.add_child(start)
		if not start.disabled or why.ends_with("queue it instead."):
			line.add_child(_button("Queue", "Starts when the wedge's slot is free.", func() -> void: research.queue(def)))
	elif state == Research.State.RESEARCHING or state == Research.State.PAUSED:
		line.add_child(_button("Stop", "All its know-how back; its progress is kept.", func() -> void: research.cancel(def)))
	return line


func _state_words(def: ResearchCardDef, state: Research.State) -> String:
	match state:
		Research.State.RESEARCHING:
			return " (under way, %d%%)" % roundi(research.progress(def) * 100.0)
		Research.State.PAUSED:
			return " (paused, %d%%)" % roundi(research.progress(def) * 100.0)
		Research.State.TRIAL:
			return " (on trial in a wing)"
		Research.State.DONE:
			return " (done)"
		Research.State.LOCKED_OUT:
			return " (locked out by %s)" % research.card(def.pair).display_name if def.pair != &"" else " (locked out)"
	if def.repeatable:
		return " (done %d times)" % research.refinements.get(def.department, 0)
	return ""


## "Costs Security 15, Admin 9; about a day at a desk. Joint: ..."
func _cost_words(def: ResearchCardDef) -> String:
	var cost := research.cost(def)
	var parts := PackedStringArray()
	for id: StringName in cost:
		var kind := knowhow.kind(id)
		parts.append("%s %d" % [kind.display_name if kind != null else String(id), cost[id]])
	var words := "Costs %s; %s at a desk." % [", ".join(parts), DeskWork.time_text(research.minutes(def))]
	if research.is_joint(def):
		words += " A joint card: worked at meetings at %d:00." % Research.MEETING_HOUR
	if def.trial:
		words += " A policy: tried in one wing for %d days first." % Research.TRIAL_DAYS
	return words


func _button(text: String, tip: String, pressed: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.tooltip_text = tip
	button.focus_mode = FOCUS_NONE
	button.pressed.connect(func() -> void:
		pressed.call()
		_built = ""
		refresh())
	return button
