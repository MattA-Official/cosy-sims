class_name Knowhow
extends Node
## The prison's know-how, one pool per kind, earned by doing (see
## KnowhowSourceDef) and spent when a research card starts. Pools have no
## cap. While `earning` is off, nothing is earned.

signal changed

var kinds: Array[KnowhowDef] = []
var sources: Array[KnowhowSourceDef] = []
## Kind id -> know-how in hand.
var pools: Dictionary[StringName, float] = {}
## Kind id -> {source text: amount} earned today.
var gained_today: Dictionary[StringName, Dictionary] = {}
var earning := true
## (kind) -> float: a multiplier on earning, such as Research assistants
## adding 10% Learning. Optional.
var scale: Callable
var counters: Counters:
	set(value):
		counters = value
		counters.counted.connect(func(id: StringName, _total: int, n: int) -> void: earn(id, n))
var clock: GameClock:
	set(value):
		clock = value
		clock.day_changed.connect(func(_day: int) -> void:
			gained_today.clear()
			changed.emit())


func kind(id: StringName) -> KnowhowDef:
	for def in kinds:
		if def.id == id:
			return def
	return null


func by_letter(letter: String) -> KnowhowDef:
	for def in kinds:
		if def.letter == letter:
			return def
	return null


func amount(id: StringName) -> float:
	return pools.get(id, 0.0)


## Earns from every source for an event, `times` over.
func earn(event: StringName, times := 1.0) -> void:
	if not earning:
		return
	var any := false
	for source in sources:
		if source.event != event:
			continue
		var gain: float = source.amount * times * (scale.call(source.kind) if scale.is_valid() else 1.0)
		add(source.kind, gain, source.text)
		any = true
	if any:
		changed.emit()


func add(id: StringName, gain: float, why := "") -> void:
	pools[id] = pools.get(id, 0.0) + gain
	if not why.is_empty():
		var parts: Dictionary = gained_today.get_or_add(id, {})
		parts[why] = parts.get(why, 0.0) + gain


func today(id: StringName) -> float:
	var sum := 0.0
	for why: String in gained_today.get(id, {}):
		sum += gained_today[id][why]
	return sum


## Whether every amount is in hand.
func can_pay(cost: Dictionary) -> bool:
	for id: StringName in cost:
		if amount(id) + 0.001 < float(cost[id]):
			return false
	return true


func pay(cost: Dictionary) -> bool:
	if not can_pay(cost):
		return false
	for id: StringName in cost:
		pools[id] = amount(id) - float(cost[id])
	changed.emit()
	return true


func refund(cost: Dictionary, share := 1.0) -> void:
	for id: StringName in cost:
		pools[id] = amount(id) + float(cost[id]) * share
	changed.emit()


## "Care 142 (+38 today)".
func chip_text(id: StringName) -> String:
	var def := kind(id)
	return "%s %d (+%d today)" % [def.display_name if def != null else String(id), floori(amount(id)), roundi(today(id))]


## "Visits 16, Calm day 10", today's sources for a kind.
func breakdown(id: StringName) -> String:
	var parts: Dictionary = gained_today.get(id, {})
	var words: Array[String] = []
	for why: String in parts:
		words.append("%s %s" % [why, String.num(parts[why], 1).trim_suffix(".0")])
	return ", ".join(words) if not words.is_empty() else "Nothing yet today"


func capture() -> Dictionary:
	return {"pools": pools.duplicate()}


func restore(data: Dictionary) -> void:
	pools.clear()
	var saved: Dictionary = data.get("pools", {})
	for id in saved:
		pools[StringName(id)] = float(saved[id])
	changed.emit()
