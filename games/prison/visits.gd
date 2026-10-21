class_name Visits
extends Node
## Family contact, which keeps up the family need. Each morning at
## POST_HOUR the post brings letters (LETTER_CHANCE each prisoner, more
## for the homesick). A payphone meets the need in free time. And between
## VISIT_HOURS, family come in from the road to a visiting room: each visit
## sits a prisoner and a visitor on two chairs for VISIT_MINUTES. A visit
## fills the need, lifts reform and cheers them up, but now and then a
## visitor slips them something (SMUGGLE_CHANCE).

## A visitor slipped someone contraband.
signal smuggled(person: Person, item: ItemDef)
signal visited(person: Person)

const POST_HOUR := 7
const LETTER_CHANCE := 0.2
const HOMESICK_CHANCE := 0.35
const LETTER_FAMILY := 30.0
const VISIT_HOURS := Vector2i(14, 16)
const VISIT_MINUTES := 45.0
## Most visits at once, and days before the same prisoner has another.
const MOST_VISITS := 6
const VISIT_GAP_DAYS := 3
const SMUGGLE_CHANCE := 0.1
## Game minutes a visitor may take to walk out before they simply go.
const LEAVE_MINUTES := 60.0
const OUT_DISTANCE := 1.5
const ROOM := &"visiting"
const SEATS: Array[StringName] = [&"chair"]
const NEED := &"family"
const JOB := &"visit"
const VISITOR := &"visitor"
const PRISONER := &"prisoner"

var people: People
var jobs: JobBoard
var building: Building
## Reform, for the letter and visit sources. Optional.
var progress: Progress
## What visitors may slip in. Optional.
var contraband: Array[ItemDef] = []
## () -> [level, spot]: where visitors come in from the road and leave.
var entrance: Callable
var clock: GameClock:
	set(value):
		clock = value
		clock.hour_changed.connect(func(hour: int) -> void:
			if hour == POST_HOUR:
				post()
			if hour == VISIT_HOURS.x:
				start_visits()
			if hour == VISIT_HOURS.y:
				end_visits())
		clock.minute_passed.connect(func(_minute: int) -> void: tick())
## Prisoner id -> day of their last visit.
var last_visit: Dictionary[int, int] = {}
## Visitors here now -> the prisoner they came to see.
var _visitors: Dictionary[Person, Person] = {}
## Visitors on their way out -> minutes since they set off.
var _leaving: Dictionary[Person, float] = {}
var _rng := RandomNumberGenerator.new()


func start() -> void:
	people.deciders.append(_visitor_decides)
	people.moodlet_added.connect(func(person: Person, id: StringName) -> void:
		if id == &"rang_home" and progress != null:
			progress.add(person, &"letter"))


## The morning post: letters from home. Returns how many came.
func post() -> int:
	var count := 0
	for person in people.people:
		if person.group != PRISONER or not person.needs.has(NEED):
			continue
		var homesick := person.traits.any(func(t: TraitDef) -> bool: return t.id == &"homesick")
		if _rng.randf() >= (HOMESICK_CHANCE if homesick else LETTER_CHANCE):
			continue
		person.needs[NEED] = minf(100.0, person.needs[NEED] + LETTER_FAMILY)
		people.add_moodlet(person, &"letter_from_home")
		if progress != null:
			progress.add(person, &"letter")
		count += 1
	return count


## Pairs of free chairs in visiting rooms, as [(level, id), (level, id)].
func seat_pairs() -> Array:
	var out: Array = []
	for n: int in building.levels:
		var map := building.levels[n]
		for room: Room in map.rooms():
			if room.type != ROOM:
				continue
			var seats: Array = map.objects_in_room(room).filter(func(p: BuildingMap.PlacedObject) -> bool:
				return SEATS.any(func(tag: StringName) -> bool: return p.def.tags.has(tag)))
			# Pair each chair with the nearest one left.
			while seats.size() >= 2:
				var first: BuildingMap.PlacedObject = seats.pop_front()
				var best := 0
				for i in seats.size():
					if seats[i].centre.distance_to(first.centre) < seats[best].centre.distance_to(first.centre):
						best = i
				var second: BuildingMap.PlacedObject = seats.pop_at(best)
				out.append([Vector2i(n, first.id), Vector2i(n, second.id)])
	return out


## Visiting hours begin: family come for those who miss them most. Returns
## how many visits are on.
func start_visits() -> int:
	var spot: Array = entrance.call() if entrance.is_valid() else []
	var pairs := seat_pairs()
	if spot.is_empty() or pairs.is_empty():
		return 0
	var today := _day()
	var waiting := people.people.filter(func(p: Person) -> bool:
		return p.group == PRISONER and p.needs.has(NEED) and not p.led and not p.going_home \
				and today - last_visit.get(p.id, -VISIT_GAP_DAYS) >= VISIT_GAP_DAYS)
	waiting.sort_custom(func(a: Person, b: Person) -> bool: return a.needs[NEED] < b.needs[NEED])
	var count := 0
	for prisoner: Person in waiting.slice(0, mini(pairs.size(), MOST_VISITS)):
		if visit(prisoner, pairs[count], spot) != null:
			count += 1
	return count


## A visitor comes in for someone, to a pair of chairs. Returns the
## visitor, or null.
func visit(prisoner: Person, seats: Array, spot: Array) -> Person:
	var family := prisoner.name.get_slice(" ", 1)
	var visitor := people.add_person(spot[0], spot[1], "%s %s" % [people.random_name().get_slice(" ", 0), family], VISITOR)
	if visitor == null:
		return null
	_visitors[visitor] = prisoner
	last_visit[prisoner.id] = _day()
	jobs.post(_job(prisoner, seats[0], "Having a visit", func(_stage: Job.Stage, _worker: Person) -> void:
		visit_done(prisoner)))
	jobs.post(_job(visitor, seats[1], "Visiting %s" % prisoner.name.get_slice(" ", 0), func(_stage: Job.Stage, _worker: Person) -> void:
		send_home(visitor)))
	return visitor


## A visit went well: the need is met, reform rises, and perhaps something
## was slipped across the table.
func visit_done(prisoner: Person) -> void:
	if prisoner.needs.has(NEED):
		prisoner.needs[NEED] = 100.0
	people.add_moodlet(prisoner, &"had_a_visit")
	if progress != null:
		progress.add(prisoner, &"visit")
	if not contraband.is_empty() and _rng.randf() < SMUGGLE_CHANCE:
		var item: ItemDef = contraband[_rng.randi() % contraband.size()]
		prisoner.pocket.append(item)
		smuggled.emit(prisoner, item)
	visited.emit(prisoner)


## Visiting hours are over: visits not yet sat down are called off and
## every visitor heads out.
func end_visits() -> void:
	for job in jobs.of_kind(JOB):
		if job.worker == null or job.only_for == null or job.only_for.state != Person.State.USING:
			jobs.cancel(job)
	for visitor: Person in _visitors.keys():
		if not jobs.of_kind(JOB).any(func(j: Job) -> bool: return j.only_for == visitor):
			send_home(visitor)


func send_home(visitor: Person) -> void:
	_visitors.erase(visitor)
	if _leaving.has(visitor) or not people.people.has(visitor):
		return
	_leaving[visitor] = 0.0
	visitor.going_home = true
	people.stop(visitor)
	_head_out(visitor)


## Visitors out of the gate go; any visitor nobody is expecting (after a
## load, say) heads out.
func tick() -> void:
	for person in people.people.duplicate():
		if person.group == VISITOR and not _visitors.has(person) and not _leaving.has(person):
			send_home(person)
	var spot: Array = entrance.call() if entrance.is_valid() else []
	for visitor: Person in _leaving.keys():
		_leaving[visitor] += 1.0
		var out: bool = spot.is_empty() or (visitor.level == spot[0] and visitor.flat().distance_to(spot[1]) <= OUT_DISTANCE)
		if out or _leaving[visitor] >= LEAVE_MINUTES or not people.people.has(visitor):
			_leaving.erase(visitor)
			if people.people.has(visitor):
				people.remove_person(visitor)
		elif visitor.state == Person.State.IDLE:
			_head_out(visitor)


func visitors() -> Array[Person]:
	return _visitors.keys()


func _job(person: Person, seat: Vector2i, doing: String, finish: Callable) -> Job:
	var job := Job.new()
	job.kind = JOB
	job.only_for = person
	job.title = "A visit"
	job.priority = 8
	var sit := Job.at(Job.Do.WORK, seat.x, seat.y)
	sit.minutes = VISIT_MINUTES
	sit.doing = doing
	sit.finish = finish
	job.stages = [sit]
	return job


func _head_out(visitor: Person) -> void:
	var spot: Array = entrance.call() if entrance.is_valid() else []
	if spot.is_empty() or not people.walk_to(visitor, spot[0], spot[1], "Going home"):
		visitor.activity = "Going home"


## Visitors only visit: waiting for their seat, or on their way out.
func _visitor_decides(person: Person, _may_wander: bool) -> bool:
	if person.group != VISITOR:
		return false
	if _leaving.has(person):
		if person.state == Person.State.IDLE:
			_head_out(person)
		return true
	if jobs.carry_on(person):
		return true
	person.activity = "Waiting to visit"
	return true


func capture() -> Dictionary:
	return {"last_visit": last_visit.duplicate()}


func restore(data: Dictionary) -> void:
	last_visit.clear()
	var saved: Dictionary = data.get("last_visit", {})
	for id: Variant in saved:
		last_visit[int(id)] = int(saved[id])


func _day() -> int:
	return clock.day() if clock != null else 1
