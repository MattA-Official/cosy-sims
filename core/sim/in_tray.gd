class_name InTray
extends Node
## The warden's in-tray: a gentle morning post of request cards, each with
## two or three answers. At POST_HOUR each free place in the tray has a
## POST_CHANCE of a new card, picked by weight from those that fit; a card
## not answered by its due day takes its default answer. Nothing ever
## waits on paper.
##
## Red tape sets how many cards fit (none when Off) and Full shortens the
## days. With a clerk on the staff, a delegation rule for a kind of card
## (approve or decline) has the clerk answer it after CLERK_MINUTES at a
## desk.

## A card arrived, or one was answered (by the player, a clerk or running
## out of days).
signal posted(card: Card)
signal answered(card: Card, choice: TrayChoiceDef, by: StringName)
signal changed

const POST_HOUR := 7
const POST_CHANCE := 0.6
## Cards the tray holds, by Red tape (Off, Light, Full).
const CAPS: Array[int] = [0, 5, 7]
## Days before a card can come again.
const REPEAT_DAYS := 10
## Lines of history kept.
const HISTORY := 8
const CLERK_MINUTES := 20.0
## The DeskWork pile for cards waiting on a clerk.
const CLERK_PILE := DeskWork.SHARED

## One card in the tray.
class Card:
	var id := 0
	var def: TrayCardDef
	## Who {who} is: a person id or a staff record id; 0 for nobody.
	var subject := 0
	var words := ""
	var posted_day := 0
	var due_day := 0
	## With a clerk: the answer they'll give, or -1.
	var queued := -1

	func text() -> String:
		return def.body.replace("{who}", words)

var defs: Array[TrayCardDef] = []
## (id: StringName) -> TrayCardDef or null: cards made on the spot
## rather than listed in defs, such as the Ministry's offers, so saves
## find them.
var lookups: Array[Callable] = []
## Research bonuses: tray_days. Optional.
var modifiers: Modifiers
var desk_work: DeskWork
## (card: Card) -> bool: picks the card's subject (setting subject and
## words); false when there's nobody suitable.
var pick_subject: Callable
## (card: Card, choice: TrayChoiceDef) -> void: does a choice's effects.
var apply: Callable
## () -> int: prisoners in the prison.
var prisoners: Callable
## () -> bool: a clerk is on the staff.
var has_clerk: Callable
## (choice: TrayChoiceDef) -> int: what a choice costs, for rules with a
## limit. Optional.
var cost_of: Callable
## Kind -> &"approve", &"decline" or missing to ask the player; or
## &"approve_<n>" to approve only when it costs n or less, else ask.
var rules: Dictionary[StringName, StringName] = {}
var cards: Array[Card] = []
## Card def id -> day it was last posted.
var recent: Dictionary[StringName, int] = {}
var next_id := 1
## What happened to recent cards, newest last, in words.
var history: Array[String] = []
var clock: GameClock:
	set(value):
		clock = value
		clock.hour_changed.connect(func(hour: int) -> void:
			if hour == POST_HOUR:
				morning())

var _rng := RandomNumberGenerator.new()


func start() -> void:
	if desk_work != null:
		desk_work.finished.connect(func(owner: int, item: DeskWork.Item) -> void:
			if owner == CLERK_PILE and item.kind == &"card":
				_clerk_done(int(item.ref)))


func red_tape() -> int:
	return desk_work.red_tape if desk_work != null else DeskWork.RedTape.LIGHT


func cap() -> int:
	return CAPS[red_tape()]


## Lapsed cards take their default; then new ones may arrive.
func morning() -> void:
	var today := _day()
	for card: Card in cards.duplicate():
		if card.due_day <= today and card.queued < 0:
			answer(card, card.def.default_choice, &"lapsed")
	for i in cap() - cards.size():
		if _rng.randf() < POST_CHANCE:
			post()


## Posts a card: a given one, or one picked by weight. Returns it, or null.
func post(def: TrayCardDef = null) -> Card:
	if cards.size() >= cap() and def == null:
		return null
	if def == null:
		def = _pick()
	if def == null:
		return null
	var card := Card.new()
	card.id = next_id
	next_id += 1
	card.def = def
	if not def.subject.is_empty() and (not pick_subject.is_valid() or not pick_subject.call(card)):
		return null
	card.posted_day = _day()
	var days := maxi(def.deadline_days - (1 if red_tape() == DeskWork.RedTape.FULL else 0), 1)
	card.due_day = card.posted_day + roundi(days * Modifiers.scale(modifiers, &"tray_days"))
	cards.append(card)
	recent[def.id] = card.posted_day
	posted.emit(card)
	_delegate(card)
	changed.emit()
	return card


## Posts an event card about someone in particular, such as a
## resignation, whatever the tray holds; the roll never picks these.
func post_about(def: TrayCardDef, subject: int, words: String) -> Card:
	var card := Card.new()
	card.id = next_id
	next_id += 1
	card.def = def
	card.subject = subject
	card.words = words
	card.posted_day = _day()
	card.due_day = card.posted_day + def.deadline_days
	cards.append(card)
	posted.emit(card)
	changed.emit()
	return card


## Answers a card. `by` is &"player", &"clerk" or &"lapsed".
func answer(card: Card, index: int, by: StringName = &"player") -> void:
	if not cards.has(card) or index < 0 or index >= card.def.choices.size():
		return
	cards.erase(card)
	if card.queued >= 0 and desk_work != null:
		for item in desk_work.items(CLERK_PILE, &"card"):
			if int(item.ref) == card.id:
				(desk_work.piles[CLERK_PILE] as Array).erase(item)
	var choice := card.def.choices[index]
	if apply.is_valid():
		apply.call(card, choice)
	answered.emit(card, choice, by)
	changed.emit()


## Notes what happened to a card, keeping the last HISTORY.
func note(words: String) -> void:
	history.append(words)
	if history.size() > HISTORY:
		history.pop_front()
	changed.emit()


## A rule for a kind of card: &"approve", &"decline", or &"" to ask.
func set_rule(kind: StringName, tag: StringName) -> void:
	if tag.is_empty():
		rules.erase(kind)
	else:
		rules[kind] = tag
	for card in cards:
		if card.queued < 0:
			_delegate(card)
	changed.emit()


## The answer a rule gives a card, or -1.
func rule_choice(card: Card) -> int:
	var tag: StringName = rules.get(card.def.kind, &"")
	if tag.is_empty():
		return -1
	var limit := -1
	if String(tag).begins_with("approve_"):
		limit = String(tag).get_slice("_", 1).to_int()
		tag = &"approve"
	for i in card.def.choices.size():
		if limit >= 0 and card.def.choices[i].tags.has(tag) and cost_of.is_valid() and cost_of.call(card.def.choices[i]) > limit:
			return -1
		if card.def.choices[i].tags.has(tag):
			return i
	return -1


func _delegate(card: Card) -> void:
	if desk_work == null or not has_clerk.is_valid() or not has_clerk.call():
		return
	var index := rule_choice(card)
	if index < 0:
		return
	card.queued = index
	desk_work.add(CLERK_PILE, &"card", card.def.title, CLERK_MINUTES, card.id)


func _clerk_done(id: int) -> void:
	for card in cards:
		if card.id == id:
			answer(card, card.queued, &"clerk")
			return


func _pick() -> TrayCardDef:
	var today := _day()
	var count: int = prisoners.call() if prisoners.is_valid() else 0
	var pool: Array[TrayCardDef] = []
	var total := 0.0
	for def in defs:
		if def.weight <= 0.0 or def.red_tape > red_tape() or count < def.min_prisoners:
			continue
		if recent.has(def.id) and today - recent[def.id] < REPEAT_DAYS:
			continue
		if cards.any(func(c: Card) -> bool: return c.def == def):
			continue
		pool.append(def)
		total += def.weight
	var roll := _rng.randf() * total
	for def in pool:
		roll -= def.weight
		if roll <= 0.0:
			return def
	return pool.back() if not pool.is_empty() else null


func find(id: StringName) -> TrayCardDef:
	for def in defs:
		if def.id == id:
			return def
	for lookup in lookups:
		var def: TrayCardDef = lookup.call(id)
		if def != null:
			return def
	return null


func capture() -> Dictionary:
	return {"next_id": next_id, "rules": rules.duplicate(), "recent": recent.duplicate(), "history": history.duplicate(),
			"cards": cards.map(func(c: Card) -> Array:
				return [c.id, String(c.def.id), c.subject, c.words, c.posted_day, c.due_day, c.queued])}


func restore(data: Dictionary) -> void:
	next_id = data.get("next_id", next_id)
	rules.assign(data.get("rules", {}))
	recent.assign(data.get("recent", {}))
	history.assign(data.get("history", []))
	cards.clear()
	for entry: Array in data.get("cards", []):
		var def := find(StringName(entry[1]))
		if def == null:
			continue
		var card := Card.new()
		card.id = entry[0]
		card.def = def
		card.subject = entry[2]
		card.words = entry[3]
		card.posted_day = entry[4]
		card.due_day = entry[5]
		card.queued = entry[6]
		cards.append(card)
	changed.emit()


func _day() -> int:
	return clock.day() if clock != null else 1
