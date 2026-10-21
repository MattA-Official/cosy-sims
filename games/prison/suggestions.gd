class_name Suggestions
extends Node
## The staff suggestions box. Once every WEEK_DAYS days, at POST_HOUR, a
## member of staff suggests something specific the prison lacks ("The yard
## needs a bench"), picked from the ideas whose check finds a need and
## whose role is on the payroll. It comes as an in-tray card (or a toast
## with no red tape). If the need is met within FOLLOW_DAYS, whoever
## suggested it is chuffed: TAKEN_MORALE. It doubles as a hint system.

signal suggested(idea: Dictionary, record: StaffRoster.Record)
signal taken_up(idea: Dictionary, record: StaffRoster.Record)

const WEEK_DAYS := 7
const POST_HOUR := 9
const FOLLOW_DAYS := 14
## Days before the same idea can come again.
const REPEAT_DAYS := 21
const TAKEN_MORALE := 10.0

var building: Building
var people: People
var roster: StaffRoster
## () -> int: prisoners in the prison.
var prisoners: Callable
var clock: GameClock:
	set(value):
		clock = value
		clock.hour_changed.connect(func(hour: int) -> void:
			if hour == POST_HOUR:
				morning())
## Ideas: {id, role, title, words, need: () -> bool}, from ideas().
var ideas: Array[Dictionary] = []
## The day the last one came.
var last_day := 0
## Open suggestions: {idea id, record id, day}.
var open: Array[Dictionary] = []
## Idea id -> day it was last suggested.
var recent: Dictionary[StringName, int] = {}
var _rng := RandomNumberGenerator.new()


func start() -> void:
	ideas = make_ideas()


## Follows up open ones; once a week, a new one.
func morning() -> void:
	var today := _day()
	for entry: Dictionary in open.duplicate():
		var idea := find(entry["idea"])
		var record := _record(entry["record"])
		if idea.is_empty() or record == null or today - int(entry["day"]) > FOLLOW_DAYS:
			open.erase(entry)
		elif not idea["need"].call():
			open.erase(entry)
			record.morale = minf(record.morale + TAKEN_MORALE, 100.0)
			taken_up.emit(idea, record)
	if today - last_day >= WEEK_DAYS:
		suggest()


## Picks an idea someone on staff would make and posts it. Returns it, or {}.
func suggest() -> Dictionary:
	var today := _day()
	var pool: Array[Array] = []
	for idea in ideas:
		if recent.has(idea["id"]) and today - recent[idea["id"]] < REPEAT_DAYS:
			continue
		if open.any(func(e: Dictionary) -> bool: return e["idea"] == idea["id"]):
			continue
		var staff := roster.records.filter(func(r: StaffRoster.Record) -> bool:
				return idea["role"] == &"" or r.role == idea["role"])
		if staff.is_empty() or not idea["need"].call():
			continue
		pool.append([idea, staff[_rng.randi() % staff.size()]])
	if pool.is_empty():
		return {}
	var pick: Array = pool[_rng.randi() % pool.size()]
	last_day = today
	recent[pick[0]["id"]] = today
	open.append({"idea": pick[0]["id"], "record": pick[1].id, "day": today})
	suggested.emit(pick[0], pick[1])
	return pick[0]


func find(id: StringName) -> Dictionary:
	for idea in ideas:
		if idea["id"] == id:
			return idea
	return {}


## The prison's ideas, with checks on what's built.
func make_ideas() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var count := func(tag: StringName) -> int: return building.objects_tagged([tag] as Array[StringName]).size()
	var head_count := func() -> int: return prisoners.call() if prisoners.is_valid() else 0
	out.append(_idea(&"yard_bench", &"guard", "A bench in the yard",
			"The yard could do with a bench. Folk just stand about out there.",
			func() -> bool: return _has_room(&"yard") and not _room_has(&"yard", &"bench")))
	out.append(_idea(&"more_tables", &"cook", "More canteen tables",
			"There aren't enough seats at mealtimes; people are eating standing up.",
			func() -> bool: return count.call(&"table") * 4 < head_count.call() and count.call(&"serving_counter") > 0))
	out.append(_idea(&"second_counter", &"cook", "A second serving counter",
			"The dinner queue goes on for ages. A second serving counter would help.",
			func() -> bool: return count.call(&"serving_counter") == 1 and head_count.call() > 30))
	out.append(_idea(&"fridge", &"cook", "A fridge in the kitchen",
			"We've nowhere to keep the food but the delivery pallet. A fridge, please!",
			func() -> bool: return count.call(&"cooker") > 0 and count.call(&"fridge") + count.call(&"food_shelf") == 0))
	out.append(_idea(&"bins", &"cleaner", "More bins",
			"There's litter everywhere and nowhere to put it. More bins would help.",
			func() -> bool: return count.call(&"bin") * 15 < head_count.call()))
	out.append(_idea(&"coffee", &"", "A coffee machine",
			"Could the staff have a coffee machine? The night shift especially.",
			func() -> bool: return count.call(&"coffee") == 0 and roster.records.size() >= 4))
	out.append(_idea(&"cameras", &"guard", "Cameras",
			"A few cameras and a monitor would let us see trouble before it starts.",
			func() -> bool: return count.call(&"camera") == 0 and head_count.call() >= 12))
	out.append(_idea(&"guard_post", &"guard", "A guard post",
			"We need a guard post near the cells, somewhere to keep watch from.",
			func() -> bool: return not _has_room(&"guard_post") and head_count.call() >= 8))
	out.append(_idea(&"quiet_room", &"guard", "A quiet room",
			"When someone loses their temper we've nowhere to take them to calm down.",
			func() -> bool: return not _has_room(&"quiet_room") and head_count.call() >= 10))
	out.append(_idea(&"infirmary", &"", "An infirmary",
			"If anyone gets hurt we've nowhere to patch them up. An infirmary, maybe?",
			func() -> bool: return not _has_room(&"infirmary") and head_count.call() >= 10))
	out.append(_idea(&"bookshelf", &"teacher", "Books for the classroom",
			"A bookshelf in the classroom would give the keen ones something to read.",
			func() -> bool: return _has_room(&"classroom") and not _room_has(&"classroom", &"book")))
	out.append(_idea(&"counselling", &"counsellor", "A counselling room",
			"I could do much more with a quiet room of my own for sessions.",
			func() -> bool: return not _has_room(&"counselling")))
	out.append(_idea(&"training", &"", "A training room",
			"If we had a training room we could do courses here instead of going away.",
			func() -> bool: return not _has_room(&"training") and roster.records.size() >= 6))
	out.append(_idea(&"showers", &"cleaner", "More showers",
			"The queue for the showers is terrible in the mornings.",
			func() -> bool: return count.call(&"shower") * 8 < head_count.call() and count.call(&"shower") > 0))
	out.append(_idea(&"tv", &"guard", "Something to do in the evenings",
			"They get bored in the evenings, and bored means trouble. A TV or a games table?",
			func() -> bool: return count.call(&"tv") + count.call(&"game") == 0 and head_count.call() >= 6))
	return out


func _idea(id: StringName, role: StringName, title: String, words: String, need: Callable) -> Dictionary:
	return {"id": id, "role": role, "title": title, "words": words, "need": need}


func _has_room(type: StringName) -> bool:
	for n: int in building.levels:
		for room: Room in building.levels[n].rooms():
			if room.type == type:
				return true
	return false


func _room_has(type: StringName, tag: StringName) -> bool:
	for n: int in building.levels:
		var map := building.levels[n]
		for room: Room in map.rooms():
			if room.type == type and map.objects_in_room(room).any(func(p: BuildingMap.PlacedObject) -> bool:
					return p.def.tags.has(tag)):
				return true
	return false


func _record(id: int) -> StaffRoster.Record:
	for record in roster.records:
		if record.id == id:
			return record
	return null


func capture() -> Dictionary:
	return {"last_day": last_day, "open": open.duplicate(true), "recent": recent.duplicate()}


func restore(data: Dictionary) -> void:
	last_day = data.get("last_day", last_day)
	open.assign(data.get("open", []))
	recent.assign(data.get("recent", {}))


func _day() -> int:
	return clock.day() if clock != null else 1
