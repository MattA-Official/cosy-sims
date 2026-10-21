class_name Schedule
extends Resource
## A timetable for one group of people: an ActivityDef for every half hour
## of the week, Monday to Sunday. Day 1 of a game is a Monday.
##
## A timetable resource can give just `hours` (one block per hour, every
## day the same); the week is filled from them the first time it's needed.

signal edited

const HOURS := 24
const SLOT_MINUTES := 30
const SLOTS_PER_DAY := 48
const DAYS := 7
const SLOTS := SLOTS_PER_DAY * DAYS
const DAY_NAMES: Array[String] = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]

## Who follows it, such as &"prisoner".
@export var group: StringName = &"prisoner"
## One block per hour from midnight, the same every day: how a timetable
## resource is written. The week below starts from it.
@export var hours: Array[ActivityDef] = []
## The block for each half hour of the week from Monday midnight.
var slots: Array[ActivityDef] = []


## A copy to edit, with its own week but the same blocks, so painting it
## leaves the original alone.
func copy() -> Schedule:
	_fill_week()
	var out: Schedule = duplicate()
	out.hours = hours.duplicate()
	out.slots = slots.duplicate()
	return out


## The half hour of the week a moment falls in, from game minutes.
static func slot_of(total_minutes: float) -> int:
	return posmod(floori(total_minutes / SLOT_MINUTES), SLOTS)


## The day of the week (0 for Monday) a moment falls in.
static func weekday_of(total_minutes: float) -> int:
	return slot_of(total_minutes) / SLOTS_PER_DAY


## "09:30" for a half hour of the day.
static func slot_text(slot: int) -> String:
	slot = posmod(slot, SLOTS_PER_DAY)
	return "%02d:%02d" % [slot / 2, (slot % 2) * 30]


## The block at a moment, from game minutes.
func at_time(total_minutes: float) -> ActivityDef:
	return at_slot(slot_of(total_minutes))


## The block in a half hour of the week; slots wrap round the week.
func at_slot(slot: int) -> ActivityDef:
	_fill_week()
	return slots[posmod(slot, SLOTS)] if not slots.is_empty() else null


## The block at the start of an hour on a day (0 for Monday).
func at(hour: int, day := 0) -> ActivityDef:
	return at_slot(day * SLOTS_PER_DAY + hour * 2)


## Paints a half hour with a block: on its own day, or the same half hour
## of every day.
func set_slot(slot: int, def: ActivityDef, every_day := false) -> void:
	_fill_week()
	slot = posmod(slot, SLOTS)
	var changed := false
	for day in (DAYS if every_day else 1):
		var each := posmod(slot + day * SLOTS_PER_DAY, SLOTS) if every_day else slot
		if slots[each] != def:
			slots[each] = def
			changed = true
	if changed:
		edited.emit()


## Paints a whole hour of every day.
func set_hour(hour: int, def: ActivityDef) -> void:
	_fill_week()
	hour = posmod(hour, HOURS)
	var changed := false
	for day in DAYS:
		for half in 2:
			var slot := day * SLOTS_PER_DAY + hour * 2 + half
			if slots[slot] != def:
				slots[slot] = def
				changed = true
	if changed:
		edited.emit()


## Copies one day's timetable onto another.
func copy_day(from: int, to: int) -> void:
	_fill_week()
	for i in SLOTS_PER_DAY:
		slots[to * SLOTS_PER_DAY + i] = slots[from * SLOTS_PER_DAY + i]
	edited.emit()


## Whether every day of the week is the same.
func same_every_day() -> bool:
	_fill_week()
	for slot in range(SLOTS_PER_DAY, SLOTS):
		if slots[slot] != slots[slot % SLOTS_PER_DAY]:
			return false
	return true


## The hour the block running at `hour` on Monday started, counting back.
func block_start(hour: int) -> int:
	return posmod(block_start_slot(hour * 2), SLOTS_PER_DAY) / 2


## The half hour of the week the block running in `slot` started.
func block_start_slot(slot: int) -> int:
	var def := at_slot(slot)
	for back in range(1, SLOTS):
		if at_slot(slot - back) != def:
			return posmod(slot - back + 1, SLOTS)
	return 0


## The blocks' ids, half hour by half hour, for saving.
func ids() -> Array:
	_fill_week()
	return slots.map(func(def: ActivityDef) -> StringName: return def.id if def != null else &"")


## Puts back blocks from ids: a week of half hours, or (from older saves)
## one day of hours.
func load_ids(saved: Array, defs: Array) -> void:
	_fill_week()
	var by_id := {}
	for def: ActivityDef in defs:
		by_id[def.id] = def
	if saved.size() == HOURS:
		for slot in SLOTS:
			var id: StringName = saved[(slot % SLOTS_PER_DAY) / 2]
			if by_id.has(id):
				slots[slot] = by_id[id]
	else:
		for slot in mini(saved.size(), SLOTS):
			if by_id.has(saved[slot]):
				slots[slot] = by_id[saved[slot]]
	edited.emit()


func _fill_week() -> void:
	if slots.size() == SLOTS or hours.is_empty():
		return
	slots.clear()
	for slot in SLOTS:
		slots.append(hours[((slot % SLOTS_PER_DAY) / 2) % hours.size()])
