class_name Visits
extends Node
## Family contact, which keeps up the family need. Each morning at
## POST_HOUR the post brings letters (LETTER_CHANCE each prisoner, more
## for the homesick). A payphone meets the need in free time. And between
## VISIT_HOURS, family come in from the road to a visiting room: each visit
## sits a prisoner and a visitor on two chairs for VISIT_MINUTES. A visit
## fills the need, lifts reform and cheers them up, but now and then a
## visitor slips them something (SMUGGLE_CHANCE).

## With a road, visitors come together on a bus at visiting hours.

## A visitor slipped someone contraband.
signal smuggled(person: Person, item: ItemDef)
signal visited(person: Person)
## A visit ended, with who came.
signal visited_by(person: Person, visitor: Person)
## A letter came, and who it was from.
signal letter(person: Person, from: String)

const POST_HOUR := 7
const LETTER_CHANCE := 0.2
const HOMESICK_CHANCE := 0.35
const LETTER_FAMILY := 30.0
const VISIT_HOURS := Vector2i(18, 20)
const VISIT_MINUTES := 30.0
## Visitors sit and wait this long at most; the visit ends when the
## prisoner's time at the table is up.
const VISITOR_MINUTES := 120.0
## Most visits at once, and days before the same prisoner has another.
const MOST_VISITS := 6
const VISIT_GAP_DAYS := 3
const SMUGGLE_CHANCE := 0.1
## Game minutes the visitors' bus waits before driving off.
const BUS_STAY := 30.0
## Game minutes a visitor may take to walk out before they simply go.
const LEAVE_MINUTES := 60.0
const OUT_DISTANCE := 1.5
const ROOM := &"visiting"
const SEATS: Array[StringName] = [&"chair"]
const NEED := &"family"
const JOB := &"visit"
const VISITOR := &"visitor"
const PRISONER := &"prisoner"

## Research bonuses: visit_length and visit_smuggle. Optional.
var modifiers: Modifiers
var people: People
var jobs: JobBoard
var building: Building
## Reform, for the letter and visit sources. Optional.
var progress: Progress
## What visitors may slip in. Optional.
var contraband: Array[ItemDef] = []
## () -> [level, spot]: where visitors come in from the road and leave.
var entrance: Callable
## (prisoner) -> {name, title}: who comes to see them, or {} for nobody.
## Optional; someone always comes otherwise.
var visitor_for: Callable
## (prisoner) -> String: who writes to them, or "" for nobody. Optional.
var letter_from: Callable
## () -> bool: a family day, when visits don't wait their turn and twice as
## many come. Optional.
var family_day: Callable
## () -> float: more or fewer visits, such as by the prison's name. Optional.
var visit_scale: Callable
## The visitors' bus: it drives in to bus_stop () -> Vector2 when there's a
## road. Optional.
var vehicles: Vehicles
var bus_model: PackedScene
var bus_stop: Callable
var clock: GameClock:
	set(value):
		clock = value
		clock.hour_changed.connect(func(hour: int) -> void:
			if hour == POST_HOUR:
				post()
			if hour == VISIT_HOURS.x:
				visiting_hours()
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
		var from: String = letter_from.call(person) if letter_from.is_valid() else "home"
		if from.is_empty():
			continue
		person.needs[NEED] = minf(100.0, person.needs[NEED] + LETTER_FAMILY)
		people.add_moodlet(person, &"letter_from_home")
		if progress != null:
			progress.add(person, &"letter")
		letter.emit(person, from)
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


## Visiting hours begin: the visitors' bus drives in and they get off,
## or without a road they walk in at once.
func visiting_hours() -> void:
	if vehicles != null and bus_model != null and bus_stop.is_valid() and not seat_pairs().is_empty() \
			and not waiting().is_empty():
		if vehicles.drive_in(bus_model, bus_stop.call(), func(_bus: Node3D) -> void: start_visits(), BUS_STAY) != null:
			return
	start_visits()


## Prisoners due a visit who someone would come to see, loneliest first.
func waiting() -> Array:
	var today := _day()
	var gap := 0 if _family_day() else VISIT_GAP_DAYS
	var out := people.people.filter(func(p: Person) -> bool:
		return p.group == PRISONER and p.needs.has(NEED) and not p.led and not p.going_home \
				and today - last_visit.get(p.id, -VISIT_GAP_DAYS) >= gap)
	out.sort_custom(func(a: Person, b: Person) -> bool: return a.needs[NEED] < b.needs[NEED])
	return out


## Family come for those who miss them most. Returns how many visits are
## on.
func start_visits() -> int:
	var spot: Array = entrance.call() if entrance.is_valid() else []
	var pairs := seat_pairs()
	if spot.is_empty() or pairs.is_empty():
		return 0
	var most := MOST_VISITS * (2 if _family_day() else 1)
	if visit_scale.is_valid():
		most = maxi(1, roundi(most * visit_scale.call()))
	var count := 0
	for prisoner: Person in waiting():
		if count >= mini(pairs.size(), most):
			break
		if visit(prisoner, pairs[count], spot) != null:
			count += 1
	return count


## A visitor comes in for someone, to a pair of chairs. Returns the
## visitor, or null.
func visit(prisoner: Person, seats: Array, spot: Array) -> Person:
	var who: Dictionary = visitor_for.call(prisoner) if visitor_for.is_valid() else {}
	if visitor_for.is_valid() and who.is_empty():
		return null
	var family := prisoner.name.get_slice(" ", 1)
	var first: String = who.get("name", people.random_name().get_slice(" ", 0))
	var visitor := people.add_person(spot[0], spot[1], "%s %s" % [first, family], VISITOR)
	if visitor == null:
		return null
	visitor.profile["relative"] = first
	visitor.profile["relation"] = who.get("title", "")
	var doing := "Visiting %s" % prisoner.name.get_slice(" ", 0)
	if not String(who.get("title", "")).is_empty():
		doing = "%s, visiting %s" % [who.title, prisoner.name.get_slice(" ", 0)]
	_visitors[visitor] = prisoner
	last_visit[prisoner.id] = _day()
	jobs.post(_job(prisoner, seats[0], "Having a visit", VISIT_MINUTES * Modifiers.scale(modifiers, &"visit_length"), func(_stage: Job.Stage, _worker: Person) -> void:
		visit_done(prisoner)))
	jobs.post(_job(visitor, seats[1], doing, VISITOR_MINUTES,
			func(_stage: Job.Stage, _worker: Person) -> void: send_home(visitor)))
	return visitor


## A visit went well: the need is met, reform rises, and perhaps something
## was slipped across the table. Their visitor heads home.
func visit_done(prisoner: Person) -> void:
	for visitor: Person in _visitors.keys():
		if _visitors[visitor] == prisoner:
			visited_by.emit(prisoner, visitor)
			_call_off(visitor)
			send_home(visitor)
	if prisoner.needs.has(NEED):
		prisoner.needs[NEED] = 100.0
	people.add_moodlet(prisoner, &"had_a_visit")
	if progress != null:
		progress.add(prisoner, &"visit")
	if not contraband.is_empty() and _rng.randf() < SMUGGLE_CHANCE * maxf(0.0, Modifiers.scale(modifiers, &"visit_smuggle")):
		var item: ItemDef = contraband[_rng.randi() % contraband.size()]
		prisoner.pocket.append(item)
		smuggled.emit(prisoner, item)
	visited.emit(prisoner)


## Visiting hours are over: visits not yet sat down are called off and
## every visitor heads out.
func end_visits() -> void:
	for job in jobs.of_kind(JOB):
		if job.only_for == null or job.only_for.group == VISITOR:
			continue
		if job.worker == null or job.only_for.state != Person.State.USING:
			jobs.cancel(job)
	# Visitors whose prisoner isn't mid-visit go now; the rest once it ends.
	for visitor: Person in _visitors.keys():
		var prisoner: Person = _visitors[visitor]
		if not jobs.of_kind(JOB).any(func(j: Job) -> bool: return j.only_for == prisoner):
			_call_off(visitor)
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
		if person.group == VISITOR and not _visitors.has(person) and not _leaving.has(person) \
				and not person.profile.has("guest"):
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


## Takes a visitor's sitting off the board.
func _call_off(visitor: Person) -> void:
	for job in jobs.of_kind(JOB):
		if job.only_for == visitor:
			jobs.cancel(job)


func _job(person: Person, seat: Vector2i, doing: String, minutes: float, finish: Callable) -> Job:
	var job := Job.new()
	job.kind = JOB
	job.only_for = person
	job.any_time = true
	job.title = "A visit"
	job.priority = 8
	var sit := Job.at(Job.Do.WORK, seat.x, seat.y)
	sit.minutes = minutes
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
	if person.group != VISITOR or person.profile.has("guest"):
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


func _family_day() -> bool:
	return family_day.is_valid() and family_day.call()


func _day() -> int:
	return clock.day() if clock != null else 1
