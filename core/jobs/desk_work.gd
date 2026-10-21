class_name DeskWork
extends Node
## What's on each desk: a pile of paper per member of staff (by roster
## record id), worked through at their claimed desk. Paperwork comes first,
## then cards, then research, such as a hire card. Each morning at
## PAPER_HOUR paperwork lands on desks: so many minutes per prisoner, by
## the Red tape setting. A pile over OVERLOAD minutes then is overloaded
## until it drops under CLEAR.

## Something on a pile finished: whose pile, and the item.
signal finished(owner: int, item: Item)
signal changed

enum RedTape { OFF, LIGHT, FULL }

const PAPER_HOUR := 6
const OVERLOAD := 480.0
const CLEAR := 240.0
## Desk minutes of paperwork per prisoner each morning, for the warden and
## for each head, by Red tape.
const WARDEN_PAPER: Array[float] = [0.0, 2.0, 4.0]
const HEAD_PAPER: Array[float] = [0.0, 1.0, 2.0]
const ORDER: Array[StringName] = [&"paperwork", &"file", &"planning", &"card", &"research"]
## The pile clerks share for things handed to them, such as in-tray cards.
const SHARED := -1

## One thing on a pile.
class Item:
	var kind: StringName = &"paperwork"
	var title := ""
	var minutes := 0.0
	var total := 0.0
	## What it's about, such as a department id for a hire card.
	var ref: Variant = null

	func done_share() -> float:
		return 1.0 - minutes / total if total > 0.0 else 1.0

var red_tape := RedTape.LIGHT
## Research bonuses: paperwork. Optional.
var modifiers: Modifiers
## Record id -> Array[Item], oldest first within each kind.
var piles: Dictionary[int, Array] = {}
## Record ids overloaded since this morning.
var overloaded: Dictionary[int, bool] = {}


## Puts something on someone's pile, after anything of an earlier kind.
func add(owner: int, kind: StringName, title: String, minutes: float, ref: Variant = null) -> Item:
	var item := Item.new()
	item.kind = kind
	item.title = title
	item.minutes = minutes
	item.total = minutes
	item.ref = ref
	var pile: Array = piles.get_or_add(owner, [])
	var at := pile.size()
	while at > 0 and ORDER.find((pile[at - 1] as Item).kind) > ORDER.find(kind):
		at -= 1
	pile.insert(at, item)
	changed.emit()
	return item


## Takes something off whichever pile it's on, unfinished. Returns
## whether it was there.
func remove(kind: StringName, ref: Variant) -> bool:
	for owner: int in piles:
		for item: Item in piles[owner]:
			if item.kind == kind and item.ref == ref:
				(piles[owner] as Array).erase(item)
				changed.emit()
				return true
	return false


## Paperwork lands on a pile, joining any already there.
func add_paperwork(owner: int, minutes: float) -> void:
	if minutes <= 0.0:
		return
	var pile: Array = piles.get_or_add(owner, [])
	for item: Item in pile:
		if item.kind == &"paperwork":
			item.minutes += minutes
			item.total += minutes
			changed.emit()
			return
	add(owner, &"paperwork", "Paperwork", minutes)


## Desk minutes of work done on someone's pile, from the top down.
func work(owner: int, minutes: float) -> void:
	var pile: Array = piles.get(owner, [])
	while minutes > 0.0 and not pile.is_empty():
		var item: Item = pile[0]
		var used := minf(minutes, item.minutes)
		item.minutes -= used
		minutes -= used
		if item.minutes <= 0.001:
			pile.pop_front()
			finished.emit(owner, item)
	if overloaded.has(owner) and pile_minutes(owner) < CLEAR:
		overloaded.erase(owner)
	changed.emit()


## Clerks' work: desk minutes off the biggest paperwork pile, then the
## next, then the shared pile. Returns the minutes used.
func work_paperwork(minutes: float) -> float:
	var used := 0.0
	while minutes - used > 0.001:
		var biggest := 0
		var most := 0.0
		for owner: int in piles:
			var paper := pile_minutes(owner, &"paperwork") if owner != SHARED else 0.0
			if paper > most:
				most = paper
				biggest = owner
		if most <= 0.0:
			var shared := minf(minutes - used, pile_minutes(SHARED))
			if shared > 0.0:
				work(SHARED, shared)
				used += shared
			break
		for item: Item in piles[biggest]:
			if item.kind == &"paperwork":
				var take := minf(minutes - used, item.minutes)
				item.minutes -= take
				used += take
				if item.minutes <= 0.001:
					(piles[biggest] as Array).erase(item)
					finished.emit(biggest, item)
				break
		if overloaded.has(biggest) and pile_minutes(biggest) < CLEAR:
			overloaded.erase(biggest)
	changed.emit()
	return used


## Paperwork waiting on every desk, and the clerks' shared pile.
func all_paperwork() -> float:
	var sum := pile_minutes(SHARED)
	for owner: int in piles:
		sum += pile_minutes(owner, &"paperwork")
	return sum


## Minutes left on a pile, of one kind or of everything.
func pile_minutes(owner: int, kind: StringName = &"") -> float:
	var sum := 0.0
	for item: Item in piles.get(owner, []):
		if kind.is_empty() or item.kind == kind:
			sum += item.minutes
	return sum


## The items of a kind on a pile.
func items(owner: int, kind: StringName) -> Array[Item]:
	var out: Array[Item] = []
	for item: Item in piles.get(owner, []):
		if item.kind == kind:
			out.append(item)
	return out


func is_overloaded(owner: int) -> bool:
	return overloaded.has(owner)


## The morning's paperwork: per prisoner, for the warden and each head.
## Then whoever is over OVERLOAD is overloaded.
func morning(prisoners: int, warden: int, heads: Array[int]) -> void:
	var scale := maxf(0.0, Modifiers.scale(modifiers, &"paperwork"))
	if warden != 0:
		add_paperwork(warden, prisoners * WARDEN_PAPER[red_tape] * scale)
	for head in heads:
		add_paperwork(head, prisoners * HEAD_PAPER[red_tape] * scale)
	for owner: int in piles:
		if pile_minutes(owner) > OVERLOAD:
			overloaded[owner] = true
	changed.emit()


## Drops the pile of someone who has left.
func forget(owner: int) -> void:
	piles.erase(owner)
	overloaded.erase(owner)
	changed.emit()


## "About 3 hours", for a pile.
static func time_text(minutes: float) -> String:
	if minutes < 60.0:
		return "%d minutes" % ceili(minutes)
	return "about %d hour%s" % [roundi(minutes / 60.0), "" if roundi(minutes / 60.0) == 1 else "s"]


func capture() -> Dictionary:
	var out := {}
	for owner: int in piles:
		out[owner] = (piles[owner] as Array).map(func(item: Item) -> Array:
			return [String(item.kind), item.title, item.minutes, item.total, item.ref])
	return {"red_tape": red_tape, "piles": out, "overloaded": overloaded.keys()}


func restore(data: Dictionary) -> void:
	red_tape = data.get("red_tape", red_tape)
	piles.clear()
	overloaded.clear()
	var saved: Dictionary = data.get("piles", {})
	for key: Variant in saved:
		var pile: Array = []
		for entry: Array in saved[key]:
			var item := Item.new()
			item.kind = StringName(entry[0])
			item.title = entry[1]
			item.minutes = entry[2]
			item.total = entry[3]
			item.ref = entry[4]
			pile.append(item)
		piles[int(key)] = pile
	for owner: Variant in data.get("overloaded", []):
		overloaded[int(owner)] = true
	changed.emit()
