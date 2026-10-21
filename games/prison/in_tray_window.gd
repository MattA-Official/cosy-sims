class_name InTrayWindow
extends PanelContainer
## The in-tray: request cards waiting for an answer, each with its choices
## and the day it lapses to its default; rules a clerk follows for each
## kind of card; and what happened to recent cards. Toggle with J.

const KINDS := [[&"prisoner_request", "Prisoner requests"], [&"staff_request", "Staff requests"],
		[&"memo", "Memos"], [&"complaint", "Complaints"], [&"suggestion", "Staff suggestions"]]
const RULES := [[&"", "Ask me"], [&"approve", "Approve"], [&"approve_50", "Approve up to £50"],
		[&"approve_100", "Approve up to £100"], [&"decline", "Decline"]]

var in_tray: InTray
var clock: GameClock

var _note := Label.new()
var _cards := VBoxContainer.new()
var _rules := VBoxContainer.new()
var _history := Label.new()
var _rule_pickers: Dictionary[StringName, OptionButton] = {}
var _built := ""


func _ready() -> void:
	set_anchors_and_offsets_preset(PRESET_CENTER_TOP, PRESET_MODE_MINSIZE)
	grow_horizontal = GROW_DIRECTION_BOTH
	offset_top = 76.0
	custom_minimum_size = Vector2(500, 0)
	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", 8)
	add_child(box)
	var heading := HBoxContainer.new()
	var title := Label.new()
	title.text = "In-tray"
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
	_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_note.theme_type_variation = &"SubtleLabel"
	box.add_child(_note)
	_cards.add_theme_constant_override(&"separation", 10)
	box.add_child(_cards)
	box.add_child(HSeparator.new())
	var rules_title := Label.new()
	rules_title.text = "Clerk's rules"
	box.add_child(rules_title)
	var rules_note := Label.new()
	rules_note.text = "With a clerk on the staff, they answer these kinds of card for you, after a little desk work."
	rules_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rules_note.theme_type_variation = &"SubtleLabel"
	box.add_child(rules_note)
	for entry: Array in KINDS:
		var row := HBoxContainer.new()
		var label := Label.new()
		label.text = entry[1]
		label.size_flags_horizontal = SIZE_EXPAND_FILL
		row.add_child(label)
		var picker := OptionButton.new()
		picker.focus_mode = FOCUS_NONE
		for rule: Array in RULES:
			picker.add_item(rule[1])
		var kind: StringName = entry[0]
		picker.item_selected.connect(func(index: int) -> void: in_tray.set_rule(kind, RULES[index][0]))
		row.add_child(picker)
		_rule_pickers[kind] = picker
		_rules.add_child(row)
	box.add_child(_rules)
	box.add_child(HSeparator.new())
	_history.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_history.theme_type_variation = &"SubtleLabel"
	box.add_child(_history)
	if in_tray != null:
		in_tray.changed.connect(func() -> void:
			if visible:
				refresh())
	visible = false


func toggle() -> void:
	visible = not visible
	refresh()


func refresh() -> void:
	if in_tray == null:
		return
	var tape: String = ["Off", "Light", "Full"][in_tray.red_tape()]
	_note.text = "Red tape: %s. %s" % [tape, "No cards come; turn it up in Game settings." if in_tray.cap() == 0
			else "Up to %d cards; each takes its default answer when its day comes." % in_tray.cap()]
	for kind: StringName in _rule_pickers:
		var tag: StringName = in_tray.rules.get(kind, &"")
		_rule_pickers[kind].select(RULES.map(func(r: Array) -> StringName: return r[0]).find(tag))
	_history.text = "Lately:\n" + "\n".join(in_tray.history.slice(-5)) if not in_tray.history.is_empty() else ""
	var key := ",".join(in_tray.cards.map(func(c: InTray.Card) -> String: return "%d:%d" % [c.id, c.queued]))
	if key == _built:
		return
	_built = key
	for child in _cards.get_children():
		child.queue_free()
	if in_tray.cards.is_empty():
		var empty := Label.new()
		empty.text = "Nothing in the tray."
		empty.theme_type_variation = &"SubtleLabel"
		_cards.add_child(empty)
	for card in in_tray.cards:
		_cards.add_child(_card(card))


func _card(card: InTray.Card) -> Control:
	var paper := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.99, 0.97, 0.9)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(10)
	style.shadow_color = Color(0, 0, 0, 0.12)
	style.shadow_size = 3
	paper.add_theme_stylebox_override(&"panel", style)
	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", 4)
	paper.add_child(box)
	var ink := Color(0.2, 0.22, 0.25)
	var title := Label.new()
	title.text = card.def.title
	title.add_theme_color_override(&"font_color", ink)
	box.add_child(title)
	var body := Label.new()
	body.text = card.text()
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_theme_color_override(&"font_color", ink)
	box.add_child(body)
	var due := Label.new()
	var days := card.due_day - (clock.day() if clock != null else card.posted_day)
	if card.queued >= 0:
		due.text = "With the clerk: %s." % card.def.choices[card.queued].label
	else:
		due.text = "%s, then: %s." % ["Today" if days <= 0 else "Tomorrow" if days == 1 else "%d days" % days,
				card.def.choices[card.def.default_choice].label]
	due.add_theme_color_override(&"font_color", Color(ink, 0.6))
	box.add_child(due)
	var row := HFlowContainer.new()
	row.add_theme_constant_override(&"h_separation", 6)
	for i in card.def.choices.size():
		var button := Button.new()
		button.text = card.def.choices[i].label
		var tags := card.def.choices[i].tags
		if tags.has(&"caring") or tags.has(&"strict"):
			button.tooltip_text = "Nudges your character towards %s." % ("caring" if tags.has(&"caring") else "strict")
		button.focus_mode = FOCUS_NONE
		var index := i
		button.pressed.connect(func() -> void: in_tray.answer(card, index))
		row.add_child(button)
	box.add_child(row)
	return paper
