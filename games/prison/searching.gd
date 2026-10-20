class_name Searching
extends Node
## Guards searching cells and prisoners for contraband (see Contraband).
## A cell search takes a guard 8 minutes and finds each stash with a chance
## that falls the better it's hidden and rises the messier the cell. A
## person search has a guard stop them and pat them down for 2 minutes,
## finding everything they carry. Being searched puts people out, so
## searching everyone every day makes for an unhappy prison. Random cell
## searches happen a few times a day by policy.

const CELL_MINUTES := 8.0
const PERSON_MINUTES := 2.0
## How carefully guards search, 0 to 1. One value for everyone until
## training arrives.
const THOROUGHNESS := 0.5
## Random searches a day the warden can choose between.
const POLICIES: Array[int] = [0, 2, 5]
## Random searches are spread over these hours.
const FIRST_HOUR := 9
const LAST_HOUR := 19

## Something was found: who it belonged to (or null) and where, in words.
signal found(owner: Person, item: ItemDef, where: String)

var people: People
var jobs: JobBoard
var items: ItemStore
var prisoner_group: StringName = &"prisoner"
var searched_moodlet: StringName = &"searched"
## Random cell searches a day.
var random_per_day := 2
## Today's tally, for the daily report and the Security window.
var searches_today := 0
var found_today: Array[String] = []
var clock: GameClock:
	set(value):
		clock = value
		clock.minute_passed.connect(func(_minute: int) -> void: _tick())
		clock.day_changed.connect(func(_day: int) -> void:
			searches_today = 0
			found_today.clear())

## People stood still waiting for, or having, a pat-down: their job.
var _held: Dictionary[Person, Job] = {}
var _rng := RandomNumberGenerator.new()


func start() -> void:
	jobs.rebuilders[&"search"] = rebuild


## Has a guard search the room someone sleeps in. Returns the job, or null
## if there's already one.
func search_cell(level: int, room: Room) -> Job:
	for job in jobs.of_kind(&"search"):
		if job.has_meta(&"room") and job.get_meta(&"room") == room:
			return null
	var job := Job.new()
	job.kind = &"search"
	job.title = "Search %s" % _room_words(level, room)
	job.priority = 3
	job.set_meta(&"room", room)
	var tile := room.cells[room.cells.size() / 2]
	var look := Job.on_tile(Job.Do.WORK, level, tile)
	look.minutes = CELL_MINUTES
	look.doing = "Searching"
	look.finish = func(_stage: Job.Stage, _guard: Person) -> void: _search_room(level, room)
	job.stages = [look]
	return jobs.post(job)


## Has a guard stop someone and search them. Returns the job, or null if
## there's already one.
func search_person(person: Person) -> Job:
	for job in jobs.of_kind(&"search"):
		if job.has_meta(&"prisoner") and job.get_meta(&"prisoner") == person:
			return null
	var first := person.name.get_slice(" ", 0)
	var job := Job.new()
	job.kind = &"search"
	job.title = "Search %s" % first
	job.priority = 4
	job.set_meta(&"prisoner", person)
	var pat := Job.on_tile(Job.Do.WORK, person.level, Vector2i(person.flat().floor()))
	pat.minutes = PERSON_MINUTES
	pat.doing = "Searching %s" % first
	var reach := Job.on_tile(Job.Do.WORK, person.level, Vector2i(person.flat().floor()))
	reach.minutes = 0.1
	reach.doing = "Stopping %s" % first
	reach.finish = func(_stage: Job.Stage, _guard: Person) -> void:
		# They wait where they are now while they're patted down.
		_hold(person, job)
		pat.level = person.level
		pat.tile = Vector2i(person.flat().floor())
	pat.finish = func(_stage: Job.Stage, _guard: Person) -> void:
		_pat_down(person)
		_release(person)
	job.stages = [reach, pat]
	return jobs.post(job)


## A search again for a guard loaded part way through one.
func rebuild(work: Dictionary) -> Job:
	var id: int = work["with"].get(&"prisoner", -1)
	if id != -1:
		for person in people.people:
			if person.id == id:
				return search_person(person)
		return null
	var level: int = work["last"][0]
	var map: BuildingMap = people.building.levels.get(level)
	var room := map.room_at_point(Vector2(work["last"][2]) + Vector2(0.5, 0.5)) if map != null else null
	return search_cell(level, room) if room != null else null


## The chance a search finds a stash in this object.
static func find_chance(hide_spot: float, litter: int) -> float:
	return clampf(0.5 + 0.3 * THOROUGHNESS - 0.4 * hide_spot + 0.2 * minf(1.0, litter / 3.0), 0.05, 0.95)


## A random cell search, if the policy wants one now.
func _tick() -> void:
	for person: Person in _held.keys():
		if not people.people.has(person) or not jobs.jobs.has(_held[person]):
			_release(person)
	if random_per_day <= 0 or clock == null:
		return
	var minute := clock.minute_of_day()
	var span := (LAST_HOUR - FIRST_HOUR) * 60
	var gap := span / random_per_day
	if minute < FIRST_HOUR * 60 or minute >= LAST_HOUR * 60 or (minute - FIRST_HOUR * 60) % gap != gap / 2:
		return
	var homes: Array = []
	for person in people.people:
		var home := people.home_room(person) if person.group == prisoner_group else []
		if not home.is_empty() and not homes.any(func(h: Array) -> bool: return h[1] == home[1]):
			homes.append(home)
	if not homes.is_empty():
		var home: Array = homes[_rng.randi() % homes.size()]
		search_cell(home[0], home[1])


func _search_room(level: int, room: Room) -> void:
	searches_today += 1
	var map: BuildingMap = people.building.levels.get(level)
	if map == null:
		return
	var litter := 0
	for cell in room.cells:
		litter += items.count_on_floor(Vector3i(level, cell.x, cell.y), &"litter")
	var owners := people.owners_in(level, room)
	for placed in map.objects_in_room(room):
		var key := Vector2i(level, placed.id)
		if not items.hidden.has(key) or _rng.randf() >= find_chance(placed.def.hide_spot, litter):
			continue
		var owner := _person(items.stash_owner.get(key, -1))
		var where := "%s's %s" % [owner.name.get_slice(" ", 0), placed.def.display_name.to_lower()] if owner != null \
				else "a %s" % placed.def.display_name.to_lower()
		var stash: Dictionary = items.hidden[key].duplicate()
		for def: ItemDef in stash:
			for i in stash[def]:
				items.unhide(key, def)
				_confiscate(owner, def, "in %s" % where)
	for owner in owners:
		people.add_moodlet(owner, searched_moodlet)


func _pat_down(person: Person) -> void:
	searches_today += 1
	for def in person.pocket.duplicate():
		person.pocket.erase(def)
		_confiscate(person, def, "on %s" % person.name.get_slice(" ", 0))
	people.add_moodlet(person, searched_moodlet)


func _confiscate(owner: Person, def: ItemDef, where: String) -> void:
	found_today.append(def.display_name.to_lower())
	if owner != null:
		owner.record.append([clock.day() if clock != null else 1, &"contraband",
				"caught with a %s" % def.display_name.to_lower()])
	found.emit(owner, def, where)


func _hold(person: Person, job: Job) -> void:
	if not people.people.has(person):
		return
	people.stop(person)
	person.led = true
	person.activity = "Being searched"
	_held[person] = job


func _release(person: Person) -> void:
	if _held.erase(person) and people.people.has(person):
		person.led = false
		people.stop(person)


func _person(id: int) -> Person:
	for person in people.people:
		if person.id == id:
			return person
	return null


func _room_words(level: int, room: Room) -> String:
	var owners := people.owners_in(level, room)
	if owners.size() == 1:
		return "%s's cell" % owners[0].name.get_slice(" ", 0)
	var type := people.room_type(room.type)
	return "the %s" % type.display_name.to_lower() if type != null else "a room"
