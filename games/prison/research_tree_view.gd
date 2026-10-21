class_name ResearchTreeView
extends Control
## One research tree drawn left to right, as on the mock-up board: a band
## for each tier, cards placed and lines routed ahead of time
## (research/board_layout.json, baked from the board's own layout), and
## each card showing how it stands in this game. Clicking a card selects
## it; its ancestors light up and the rest fade. Drag empty space to pan.

signal card_pressed(id: StringName)

const LAYOUT_PATH := "res://games/prison/research/board_layout.json"
## The board's colours: one per tree, and an accent for selection.
const TREE_COLOURS := {&"office": Color("3a4547"), &"security": Color("3d6b9e"), &"wellbeing": Color("b0506a"),
		&"medical": Color("24857a"), &"education": Color("9c7a16"), &"industry": Color("87593a"), &"admin": Color("6b57a3")}
const ACCENT := Color("d85f22")
const ACCENT_SOFT := Color("f5d9c8")
const DONE_FILL := Color("dde8d5")
const TRIAL_FILL := Color("f3e6c4")
const CORNER := 8.0
const NAME_SIZE := 14
const SMALL_SIZE := 11

static var _layout: Dictionary = {}

## Cards that don't match fade: "" for none, "start", "face_up", "busy",
## "done" or "kind:<know-how id>".
var filter := ""
var research: Research:
	set(value):
		research = value
		if is_inside_tree():
			_relayout()
var heads: Heads
## The tree on show: &"office" or a department id.
var tree: StringName = &"office":
	set(value):
		tree = value
		_relayout()
var selected: StringName = &""

var _cards: Dictionary = {} # id -> Vector2 (top left)
var _lines: Array = [] # [from, to, PackedVector2Array]
var _cols := 1
var _card_size := Vector2(214, 80)
var _gap := 300.0
var _pad := 50.0
var _head := 58.0
var _ink: Color = CosyTheme.LIGHT.ink
var _muted: Color = CosyTheme.LIGHT.muted
var _line: Color = CosyTheme.LIGHT.panel_border
var _surface := Color("fbf8f0")
var _bold: Font = CosyTheme.bold_font()
var _drag_from := Vector2.INF


static func layout() -> Dictionary:
	if _layout.is_empty():
		_layout = JSON.parse_string(FileAccess.get_file_as_string(LAYOUT_PATH))
	return _layout


## The trees, in the board's order.
static func trees() -> Array[StringName]:
	return [&"office", &"security", &"wellbeing", &"medical", &"education", &"industry", &"admin"]


## The ids of the cards drawn in a tree, hire cards included.
static func cards_in(id: StringName) -> Array[StringName]:
	var out: Array[StringName] = []
	for key: String in layout().trees[String(id)].cards:
		out.append(StringName(key))
	return out


## The tree a card belongs to when linked from elsewhere: a hire card
## stands for its department.
static func home_of(def: ResearchCardDef, board: ResearchBoardDef) -> StringName:
	for department: StringName in board.hire_cards:
		if board.hire_cards[department] == def.id:
			return department
	return def.department


func _ready() -> void:
	mouse_filter = MOUSE_FILTER_STOP
	_relayout()


func _relayout() -> void:
	var data := layout()
	var t: Dictionary = data.trees[String(tree)]
	_card_size = Vector2(data.card[0], data.card[1])
	_gap = data.gap
	_pad = data.pad
	_head = data.head
	_cols = int(t.ncols)
	_cards.clear()
	# An add-on's cards leave a blank space until it's owned.
	for key: String in t.cards:
		var def := research.card(StringName(key)) if research != null else null
		if def == null or research._addon_owned(def):
			_cards[StringName(key)] = Vector2(t.cards[key][0], t.cards[key][1])
	_lines.clear()
	for line: Dictionary in t.lines:
		if not _cards.has(StringName(line.from)) or not _cards.has(StringName(line.to)):
			continue
		var pts := PackedVector2Array()
		for p: Array in line.pts:
			pts.append(Vector2(p[0], p[1]))
		_lines.append([StringName(line.from), StringName(line.to), pts])
	custom_minimum_size = Vector2(t.size[0], t.size[1])
	if not _cards.has(selected):
		selected = &""
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	var button := event as InputEventMouseButton
	if button != null and button.button_index == MOUSE_BUTTON_LEFT:
		if button.pressed:
			var id := card_at(button.position)
			if id != &"":
				card_pressed.emit(id)
				_drag_from = Vector2.INF
			else:
				_drag_from = button.global_position
			accept_event()
		else:
			_drag_from = Vector2.INF
	var motion := event as InputEventMouseMotion
	if motion != null and _drag_from != Vector2.INF and motion.button_mask & MOUSE_BUTTON_MASK_LEFT:
		var scroll := get_parent() as ScrollContainer
		if scroll != null:
			scroll.scroll_horizontal -= int(motion.relative.x)
			scroll.scroll_vertical -= int(motion.relative.y)
		accept_event()


## Whether a card matches the filter.
func passes(id: StringName) -> bool:
	var def := research.card(id)
	var state := research.state_of(id)
	match filter:
		"":
			return true
		"start":
			return state == Research.State.FACE_UP and research.available(def)
		"face_up":
			return state == Research.State.FACE_UP
		"busy":
			return state == Research.State.RESEARCHING or state == Research.State.PAUSED or state == Research.State.TRIAL
		"done":
			return state == Research.State.DONE
	if filter.begins_with("kind:"):
		return def.kinds().has(StringName(filter.trim_prefix("kind:")))
	return true


func card_at(point: Vector2) -> StringName:
	for id: StringName in _cards:
		if Rect2(_cards[id], _card_size).has_point(point):
			return id
	return &""


## Where a card sits, for scrolling to it.
func card_rect(id: StringName) -> Rect2:
	return Rect2(_cards.get(id, Vector2.ZERO), _card_size)


func _get_tooltip(at_position: Vector2) -> String:
	var id := card_at(at_position)
	if id == &"" or research == null:
		return ""
	var def := research.card(id)
	if research.state_of(id) == Research.State.HIDDEN:
		return "Face down. Turns up: %s" % research.hint_words(def)
	return "%s\n%s" % [def.display_name, def.gives_text]


func _draw() -> void:
	if research == null:
		return
	var font := get_theme_default_font()
	# Tier bands.
	for d in _cols:
		var x := _pad + d * _gap - (_gap - _card_size.x) / 2.0 + 8.0
		var band := Rect2(x, 6, _gap - 16.0, size.y - 12.0)
		draw_style_box(_box(CosyTheme.LIGHT.inset if d % 2 else Color("f1ead9"), Color(0, 0, 0, 0), 0.0, 8.0), band)
		var title := ("START" if tree == &"office" else "HEAD") if d == 0 else "TIER %d" % d
		draw_string(_bold, Vector2(x + 14, 30), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, _ink)
		var sub := ("the warden's desk" if tree == &"office" else "hired from the Warden tab") if d == 0 else gate(d)
		draw_string(font, Vector2(x + 14, 47), sub, HORIZONTAL_ALIGNMENT_LEFT, -1, SMALL_SIZE, _muted)
	var lit := _ancestors(selected)
	var kids := _children(selected)
	# Lines, then cards over them.
	for line: Array in _lines:
		var on: bool = selected != &"" and (line[1] == selected or lit.has(line[1])) and lit.has(line[0])
		var out: bool = selected != &"" and line[0] == selected
		var colour := ACCENT if on else _ink if out else Color(_muted, 0.7)
		if selected != &"" and not on and not out:
			colour.a = 0.12
		_draw_route(line[2], colour, 2.4 if on else 1.8 if out else 1.4)
	for id: StringName in _cards:
		_draw_card(id, font, lit, kids)


func _draw_route(pts: PackedVector2Array, colour: Color, width: float) -> void:
	var path := PackedVector2Array([pts[0]])
	for i in range(1, pts.size() - 1):
		var a := pts[i - 1]
		var b := pts[i]
		var c := pts[i + 1]
		var r := minf(CORNER, minf(a.distance_to(b), b.distance_to(c)) / 2.0)
		if r < 0.5:
			path.append(b)
			continue
		var p0 := b + (a - b).normalized() * r
		var p1 := b + (c - b).normalized() * r
		for s in 5:
			var t := s / 4.0
			path.append(p0.lerp(b, t).lerp(b.lerp(p1, t), t))
	path.append(pts[-1])
	draw_polyline(path, colour, width, true)
	var tip := pts[-1] + Vector2(6, 0)
	draw_colored_polygon(PackedVector2Array([tip, tip + Vector2(-8, -4.5), tip + Vector2(-8, 4.5)]), colour)


func _draw_card(id: StringName, font: Font, lit: Dictionary, kids: Dictionary) -> void:
	var def := research.card(id)
	var state := research.state_of(id)
	var at: Vector2 = _cards[id]
	var rect := Rect2(at, _card_size)
	var hidden := state == Research.State.HIDDEN
	var head := tree != &"office" and research.is_hire(def)
	var fill := _surface
	var edge := _line
	var width := 1.2
	match state:
		Research.State.DONE:
			fill = DONE_FILL
		Research.State.RESEARCHING, Research.State.PAUSED:
			fill = ACCENT_SOFT
		Research.State.TRIAL:
			fill = TRIAL_FILL
		Research.State.HIDDEN:
			fill = CosyTheme.LIGHT.inset
	if state == Research.State.FACE_UP and research.available(def):
		edge = _ink
		width = 2.0
	if id == &"warden-s-office" or research.is_hire(def):
		width = maxf(width, 2.4)
	var alpha := 1.0
	if state == Research.State.LOCKED_OUT:
		alpha = 0.45
	if not passes(id):
		alpha *= 0.25
	if selected != &"":
		if id == selected:
			edge = ACCENT
			width = 3.0
		elif lit.has(id):
			edge = ACCENT
			width = 2.0
		elif kids.has(id):
			edge = _ink
			width = 2.0
		else:
			alpha *= 0.3
	var ink := Color(_ink, alpha)
	var muted := Color(_muted, alpha)
	draw_style_box(_box(Color(fill, alpha), Color(edge, alpha), width, 6.0), rect)
	# Know-how stripe, or the tree's colour for its head.
	var kinds := def.kinds() if not def.kinds().is_empty() else ([&"admin"] as Array[StringName])
	if head:
		draw_rect(Rect2(at + Vector2(8, 5), Vector2(_card_size.x - 16, 4)), Color(TREE_COLOURS[tree], alpha))
	elif id != &"warden-s-office":
		var w := (_card_size.x - 16) / kinds.size()
		for i in kinds.size():
			var tree_of: StringName = research.board.kind_departments.get(kinds[i], &"admin")
			draw_rect(Rect2(at + Vector2(8 + i * w, 5), Vector2(w, 4)), Color(TREE_COLOURS.get(tree_of, _muted), alpha))
	var name := def.display_name
	if head:
		var department := heads.find(tree) if heads != null else null
		var record := heads.head(department) if department != null else null
		name = department.head_role.display_name if department != null else name
		if record != null:
			name = "%s: %s" % [name, record.name]
	if hidden:
		name = "Face down"
	var lines := _wrap(name, 25)
	for i in lines.size():
		draw_string(_bold, at + Vector2(10, 26 + i * 16), lines[i], HORIZONTAL_ALIGNMENT_LEFT, _card_size.x - 20, NAME_SIZE,
				muted if hidden else ink)
	var meta_y := 46.0 if lines.size() == 1 else 60.0
	if hidden:
		var hint := research.hint_words(def) if def.reveal != null else ""
		draw_string(font, at + Vector2(10, meta_y), "◆ " + hint, HORIZONTAL_ALIGNMENT_LEFT, _card_size.x - 20, SMALL_SIZE,
				Color(ACCENT, alpha))
	else:
		var state_words := _state_words(def, state)
		var x := 10.0
		if not state_words.is_empty():
			draw_string(_bold, at + Vector2(x, meta_y), state_words, HORIZONTAL_ALIGNMENT_LEFT, -1, SMALL_SIZE,
					Color(ACCENT if state != Research.State.DONE else Color("4f7a4a"), alpha))
			x += _bold.get_string_size(state_words + "  ", HORIZONTAL_ALIGNMENT_LEFT, -1, SMALL_SIZE).x
		var meta := PackedStringArray()
		if def.lean != 0:
			meta.append("▲ strict" if def.lean > 0 else "♥ caring")
		if def.pair != &"":
			meta.append("pick one")
		if def.addon != &"":
			meta.append("add-on")
		if not head and def.rule != 0 and def.requires.size() > 1:
			meta.append("needs %s of %d" % ["any 1" if def.needed() == 1 else str(def.needed()), def.requires.size()])
		draw_string(font, at + Vector2(x, meta_y), " · ".join(meta), HORIZONTAL_ALIGNMENT_LEFT,
				maxf(10.0, _card_size.x - x - 10), SMALL_SIZE, muted)
	# Progress along the bottom.
	if state == Research.State.RESEARCHING or state == Research.State.PAUSED:
		var share := research.progress(def)
		draw_rect(Rect2(at + Vector2(1.5, _card_size.y - 5), Vector2((_card_size.x - 3) * share, 3.5)), Color(ACCENT, alpha))
	# What it needs from other trees, and what it opens there.
	if head:
		return
	var x := 10.0
	var needs: Array[StringName] = []
	for pre in def.requires:
		if not _cards.has(pre):
			var other := home_of(research.card(pre), research.board)
			if other != tree and not needs.has(other):
				needs.append(other)
	for other in needs:
		var label := "Needs %s" % tree_name(other)
		draw_circle(at + Vector2(x + 4, _card_size.y - 13), 4.0, Color(TREE_COLOURS.get(other, _muted), alpha))
		draw_string(font, at + Vector2(x + 12, _card_size.y - 9), label, HORIZONTAL_ALIGNMENT_LEFT, -1, SMALL_SIZE, muted)
		x += font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, SMALL_SIZE).x + 22
	var opens := 0
	for child in research.board.children(id):
		if not _cards.has(child.id) and child.department != tree and research.is_shown(child):
			opens += 1
	if opens > 0:
		draw_string(font, at + Vector2(10, _card_size.y - 9), "opens %d ↗" % opens, HORIZONTAL_ALIGNMENT_RIGHT,
				_card_size.x - 20, SMALL_SIZE, muted)


func _state_words(def: ResearchCardDef, state: Research.State) -> String:
	match state:
		Research.State.RESEARCHING:
			return "%d%%" % roundi(research.progress(def) * 100.0)
		Research.State.PAUSED:
			return "Paused"
		Research.State.TRIAL:
			return "On trial"
		Research.State.DONE:
			return "✓ Done"
		Research.State.LOCKED_OUT:
			return "Locked out"
	for slot: StringName in research.queues:
		if (research.queues[slot] as Array).has(def.id):
			return "Queued"
	return ""


func tree_name(id: StringName) -> String:
	if id == &"office":
		return "Warden"
	var department := heads.find(id) if heads != null else null
	return department.display_name if department != null else String(id).capitalize()


func gate(tier: int) -> String:
	return "needs a %d-star grade" % Research.GATES[tier] if Research.GATES.has(tier) else "open from the start"


## A card's ancestors within this tree.
func _ancestors(id: StringName) -> Dictionary:
	var out := {}
	if id == &"":
		return out
	var todo: Array[StringName] = [id]
	while not todo.is_empty():
		var def := research.card(todo.pop_back())
		for pre in def.requires:
			if _cards.has(pre) and not out.has(pre):
				out[pre] = true
				todo.append(pre)
	return out


func _children(id: StringName) -> Dictionary:
	var out := {}
	if id != &"":
		for child in research.board.children(id):
			out[child.id] = true
	return out


func _box(fill: Color, edge: Color, width: float, radius: float) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = edge
	box.set_border_width_all(roundi(width))
	box.set_corner_radius_all(roundi(radius))
	box.anti_aliasing = true
	return box


static func _wrap(text: String, most: int) -> Array[String]:
	var out: Array[String] = []
	var line := ""
	for word in text.split(" "):
		if not line.is_empty() and (line + " " + word).length() > most:
			out.append(line)
			line = word
		else:
			line = (line + " " + word).strip_edges()
	if not line.is_empty():
		out.append(line)
	return out.slice(0, 2)
