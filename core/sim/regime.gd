class_name Regime
extends Node
## Everything timed in the prison, over a week in half hours: the
## timetables (see Schedule and ScheduleRunner), sessions placed into their
## blocks, the staff rota and the prison's own operations. It places
## sessions, says when operations are due and lists clashes.
##
## Sessions are offered so many times a week; fill() places them into the
## earliest blocks that allow them, with a free room and the staff on duty,
## spreading them over the week. Placed sessions can be moved (which pins
## them); pinned ones stay put when the fill runs again, each midnight and
## after any edit.

## An operation's time came round: id, and which of its times.
signal operation_due(id: StringName, index: int)
## Times, offers or placements changed.
signal changed

class Placement:
	var session: SessionDef
	## Half hour of the week it starts.
	var slot := 0
	var pinned := false

	func covers(at: int) -> bool:
		return posmod(at - slot, Schedule.SLOTS) < session.length


var clock: GameClock:
	set(value):
		clock = value
		clock.half_hour_changed.connect(_on_half_hour)
		clock.day_changed.connect(func(_day: int) -> void: fill())
## The timetable sessions are placed against: everyone's.
var schedule: Schedule:
	set(value):
		schedule = value
		schedule.edited.connect(fill)
## Every timetable, by runner key, for clash checks. Optional.
var schedules: Callable
var operations: Array[OperationDef] = []
var sessions: Array[SessionDef] = []
## (role: StringName, half hour of the day: int) -> bool: someone in the
## role is on duty then.
var on_duty: Callable
## (room type: StringName) -> int: how many rooms of a type there are.
var rooms: Callable
## Rows for the rota lane: [words, first half hour of the day, half hours,
## how many]. Optional.
var rota: Callable
## Each operation's times, as half hours of the day, by id.
var times: Dictionary[StringName, Array] = {}
## Sessions a week the player offers, by session id.
var offered: Dictionary[StringName, int] = {}
var placements: Array[Placement] = []


func start() -> void:
	for op in operations:
		if not times.has(op.id):
			times[op.id] = op.times.duplicate()
	for def in sessions:
		if not offered.has(def.id):
			offered[def.id] = def.per_week
	fill()


func operation(id: StringName) -> OperationDef:
	for op in operations:
		if op.id == id:
			return op
	return null


func session(id: StringName) -> SessionDef:
	for def in sessions:
		if def.id == id:
			return def
	return null


## An operation's time as a half hour of the day; its default without a
## regime entry.
func slot_of(id: StringName, index := 0) -> int:
	var list: Array = times.get(id, [])
	if index < list.size():
		return list[index]
	var op := operation(id)
	return op.times[index] if op != null and index < op.times.size() else 0


## An operation's time in hours, such as 9.5 for 09:30.
func hour_of(id: StringName, index := 0) -> float:
	return slot_of(id, index) * 0.5


## Moves one of an operation's times, kept in its window and clear of its
## other times. Returns whether it moved.
func set_time(id: StringName, index: int, slot: int) -> bool:
	var op := operation(id)
	if op == null or op.fixed or index >= times.get(id, []).size():
		return false
	slot = clampi(slot, op.earliest, op.latest)
	var list: Array = times[id]
	for i in list.size():
		if i != index and absi(list[i] - slot) < maxi(op.min_gap, 1):
			return false
	if list[index] == slot:
		return false
	list[index] = slot
	changed.emit()
	fill()
	return true


func set_offered(id: StringName, count: int) -> void:
	offered[id] = clampi(count, 0, 14)
	fill()


func _on_half_hour(slot: int) -> void:
	var of_day := slot % Schedule.SLOTS_PER_DAY
	for op in operations:
		var list: Array = times.get(op.id, op.times)
		for i in list.size():
			if list[i] == of_day:
				operation_due.emit(op.id, i)

#region Sessions

## The placement of a session running at a moment, or null.
func running(id: StringName, total_minutes: float) -> Placement:
	var at := Schedule.slot_of(total_minutes)
	for placed in placements:
		if placed.session.id == id and placed.covers(at):
			return placed
	return null


## Places every offered session that isn't pinned again.
func fill() -> void:
	if schedule == null:
		return
	placements = placements.filter(func(p: Placement) -> bool: return p.pinned and offered.get(p.session.id, 0) > 0)
	for def in sessions:
		var want: int = offered.get(def.id, def.per_week)
		var have := placements.filter(func(p: Placement) -> bool: return p.session == def).size()
		# Spread over the week: one a day first, then doubling up.
		for per_day in [1, 2]:
			for day in Schedule.DAYS:
				if have >= want:
					break
				var today := placements.filter(func(p: Placement) -> bool:
					return p.session == def and p.slot / Schedule.SLOTS_PER_DAY == day).size()
				if today >= per_day:
					continue
				for i in Schedule.SLOTS_PER_DAY - def.length + 1:
					var slot := day * Schedule.SLOTS_PER_DAY + i
					if fits(def, slot):
						var placed := Placement.new()
						placed.session = def
						placed.slot = slot
						placements.append(placed)
						have += 1
						break
	placements.sort_custom(func(a: Placement, b: Placement) -> bool: return a.slot < b.slot)
	changed.emit()


## Whether a session could start in a half hour of the week: all of it in
## one block that allows it, staff on duty, a room free and no overlap
## with itself. `moving` is left out of the checks.
func fits(def: SessionDef, slot: int, moving: Placement = null) -> bool:
	return _problems(def, slot, moving, true).is_empty()


## Moves a placed session to start somewhere else, pinning it there.
## Returns whether it fits there.
func move(placed: Placement, slot: int) -> bool:
	slot = posmod(slot, Schedule.SLOTS)
	if not fits(placed.session, slot, placed):
		return false
	placed.slot = slot
	placed.pinned = true
	fill()
	return true


func pin(placed: Placement, on: bool) -> void:
	placed.pinned = on
	fill()


func _problems(def: SessionDef, slot: int, moving: Placement, first_only := false) -> Array[String]:
	var out: Array[String] = []
	var block := schedule.at_slot(slot)
	for i in def.length:
		var here := schedule.at_slot(slot + i)
		if here != block or schedule.block_start_slot(slot + i) != schedule.block_start_slot(slot):
			out.append("%s runs past the end of its %s block" % [def.display_name,
					block.display_name.to_lower() if block != null else "timetable"])
			break
	if not _allowed(def, block):
		out.append("%s can't run in %s" % [def.display_name, block.display_name.to_lower() if block != null else "no block"])
	if first_only and not out.is_empty():
		return out
	if not def.staff_role.is_empty() and on_duty.is_valid():
		for i in def.length:
			if not on_duty.call(def.staff_role, posmod(slot + i, Schedule.SLOTS_PER_DAY)):
				out.append("No %s on duty for %s" % [def.staff_role, def.display_name])
				break
	if first_only and not out.is_empty():
		return out
	var probe := Placement.new()
	probe.session = def
	probe.slot = slot
	var same_room := 0
	for placed in placements:
		if placed == moving or not _overlap(placed, probe):
			continue
		if placed.session == def:
			out.append("%s twice at once" % def.display_name)
		if placed.session.room_type == def.room_type:
			same_room += 1
	# With no such room at all, it's placed anyway and shows as a clash.
	var room_count: int = rooms.call(def.room_type) if rooms.is_valid() and not def.room_type.is_empty() else 1 << 20
	if room_count == 0 and not first_only:
		out.append("No %s for %s" % [String(def.room_type).replace("_", " "), def.display_name])
	elif same_room >= maxi(room_count, 1):
		out.append("No free %s for %s" % [String(def.room_type).replace("_", " "), def.display_name])
	return out


func _allowed(def: SessionDef, block: ActivityDef) -> bool:
	if block == null:
		return false
	return def.blocks.has(block.id) if not def.blocks.is_empty() else block.classes


static func _overlap(a: Placement, b: Placement) -> bool:
	for i in b.session.length:
		if a.covers(b.slot + i):
			return true
	return false

#endregion

#region Clashes

## Everything that doesn't add up, as [half hour of the week, words]; the
## half hour is -1 for a whole-week problem.
func clashes() -> Array:
	var out: Array = []
	for placed in placements:
		var problems := _problems(placed.session, placed.slot, placed)
		for words in problems:
			out.append([placed.slot, words])
	for op in operations:
		var list: Array = times.get(op.id, op.times)
		for i in list.size():
			for day in Schedule.DAYS:
				var slot: int = day * Schedule.SLOTS_PER_DAY + list[i]
				var block := schedule.at_slot(slot) if schedule != null else null
				if block != null and (op.avoid_tags.has(block.main_tag) or op.avoid_blocks.has(block.id)):
					out.append([slot, "%s during %s" % [op.display_name, block.display_name.to_lower()]])
					break
			if not op.needs_role.is_empty() and on_duty.is_valid() and not on_duty.call(op.needs_role, list[i]):
				out.append([list[i], "No %s on duty for %s" % [op.needs_role, op.display_name.to_lower()]])
	var all: Dictionary = schedules.call() if schedules.is_valid() else {&"": schedule}
	for key: StringName in all:
		var each: Schedule = all[key]
		for day in Schedule.DAYS:
			for need: Array in [[&"eat", "meal"], [&"sleep", "sleep"], [&"shower", "shower"]]:
				var found := false
				for i in Schedule.SLOTS_PER_DAY:
					var block := each.at_slot(day * Schedule.SLOTS_PER_DAY + i)
					if block != null and block.id == need[0]:
						found = true
						break
				if not found:
					var who := "Everyone" if not String(key).contains("/") else String(key).get_slice("/", 1).capitalize()
					out.append([day * Schedule.SLOTS_PER_DAY, "%s: no %s on %s" % [who, need[1], Schedule.DAY_NAMES[day]]])
	return out

#endregion

#region Saving

func to_data() -> Dictionary:
	var placed: Array = []
	for each in placements:
		if each.pinned:
			placed.append([String(each.session.id), each.slot])
	return {"times": times.duplicate(true), "offered": offered.duplicate(), "pinned": placed}


func load_data(data: Dictionary) -> void:
	for id: StringName in data.get("times", {}):
		if operation(id) != null:
			times[id] = (data.times[id] as Array).duplicate()
	offered.merge(data.get("offered", {}), true)
	placements.clear()
	for entry: Array in data.get("pinned", []):
		var def := session(StringName(entry[0]))
		if def != null:
			var placed := Placement.new()
			placed.session = def
			placed.slot = entry[1]
			placed.pinned = true
			placements.append(placed)
	fill()

#endregion
