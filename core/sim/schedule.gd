class_name Schedule
extends Resource
## A timetable: one ActivityDef for each hour of the day, for one group of
## people. M1 has one for every prisoner; later each security category can
## have its own.

signal edited

const HOURS := 24

## Who follows it, such as &"prisoner".
@export var group: StringName = &"prisoner"
## The block for each hour from midnight, 24 of them.
@export var hours: Array[ActivityDef] = []


## A copy to edit, with its own hours but the same blocks, so painting it
## leaves the original alone.
func copy() -> Schedule:
	var out: Schedule = duplicate()
	out.hours = hours.duplicate()
	return out


## The block at an hour of the day.
func at(hour: int) -> ActivityDef:
	if hours.is_empty():
		return null
	return hours[posmod(hour, HOURS) % hours.size()]


## Paints one hour with a block.
func set_hour(hour: int, def: ActivityDef) -> void:
	hour = posmod(hour, HOURS)
	while hours.size() < HOURS:
		hours.append(hours.back() if not hours.is_empty() else def)
	if hours[hour] == def:
		return
	hours[hour] = def
	edited.emit()


## The hour the block running at `hour` started, counting back.
func block_start(hour: int) -> int:
	var def := at(hour)
	for back in range(1, HOURS):
		if at(hour - back) != def:
			return posmod(hour - back + 1, HOURS)
	return 0
