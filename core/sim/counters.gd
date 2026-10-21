class_name Counters
extends Node
## One place every system reports what happened, such as a fight or a
## course passed. Know-how, research reveals and the daily report read the
## counts, so no system has to know about them.
##
##   counters.add(&"contraband_found")

## n is how many happened just now.
signal counted(id: StringName, total: int, n: int)

## Running count per event since the game began.
var totals: Dictionary[StringName, int] = {}
## Counts since midnight.
var today: Dictionary[StringName, int] = {}
## The day each event first happened.
var firsts: Dictionary[StringName, int] = {}
var clock: GameClock:
	set(value):
		clock = value
		clock.day_changed.connect(func(_day: int) -> void: today.clear())


func add(id: StringName, n := 1) -> void:
	if n <= 0:
		return
	totals[id] = totals.get(id, 0) + n
	today[id] = today.get(id, 0) + n
	if not firsts.has(id):
		firsts[id] = clock.day() if clock != null else 1
	counted.emit(id, totals[id], n)


func total(id: StringName) -> int:
	return totals.get(id, 0)


func capture() -> Dictionary:
	return {"totals": totals.duplicate(), "today": today.duplicate(), "firsts": firsts.duplicate()}


func restore(data: Dictionary) -> void:
	for key in ["totals", "today", "firsts"]:
		var into: Dictionary = get(key)
		into.clear()
		var saved: Dictionary = data.get(key, {})
		for id in saved:
			into[StringName(id)] = int(saved[id])
