class_name Guarding
extends Node
## Guards keep order. One mans each guard post's desk, and while a guard
## is there the security gates near it open for prisoners; with nobody at
## a post, its gates stay locked to anyone without keys. Guards with
## nothing else to do patrol where the prisoners are. A guard who spots a
## prisoner out of place has a word and walks them back where the
## timetable wants them. Guards put on a patrol route walk round it
## instead.

## Guard post desks: a guard at one opens the gates near it.
const DESKS: Array[StringName] = [&"guard_desk"]
## Door kinds a manned guard post opens for prisoners.
const GATE_KINDS: Array[StringName] = [&"security_gate", &"people_gate"]
## Tiles from a desk to the gates it opens.
const GATE_RANGE := 10.0
## Game minutes a guard sits at a post before the job comes round again,
## when they may take a break. They get up sooner only for a need that has
## nearly run out.
const POST_MINUTES := 90.0
## Game minutes a post's gates stay open after its guard gets up, so a
## change of guard or a quick break doesn't shut them.
const GATE_GRACE := 5.0
## Game minutes a guard keeps an eye on one spot while patrolling.
const PATROL_MINUTES := 5.0
## Game minutes a guard pauses at each point of a patrol route.
const ROUTE_PAUSE := 0.5
## Tiles a guard can see a prisoner out of place from.
const WATCH_DISTANCE := 3.0
## The furthest any category is spotted from (see CategoryDef).
const FAR_WATCH_DISTANCE := 5.0
## Game minutes before the same prisoner is walked back again.
const ESCORT_COOLDOWN := 30.0
## Tiles tried in a room for somewhere to walk a prisoner back to.
const PLACE_TRIES := 8
## Tiles a prisoner being walked somewhere keeps to behind their guard.
const FOLLOW_DISTANCE := 1.2

var people: People
var jobs: JobBoard
var building: Building
var clock: GameClock:
	set(value):
		clock = value
		clock.minute_passed.connect(func(_minute: int) -> void: look())
## Routes guards walk, with how many on each. Optional.
var routes: PatrolRoutes
## Who is a prisoner, and the moodlet for being walked back.
var prisoner_group: StringName = &"prisoner"
## (level, point) -> float: how much more a place needs watching, such as
## an area on alert. Optional.
var area_weight: Callable
var walked_back_moodlet: StringName = &"walked_back"

## Desks, as (level, object id), with the game minute a guard last sat
## at each.
var _last_manned: Dictionary[Vector2i, float] = {}
## Prisoners being walked somewhere, with the guard walking them.
var _led: Dictionary[Person, Person] = {}
## What each of them is shown doing.
var _led_doing: Dictionary[Person, String] = {}
## Prisoners walked back lately, with the game minute it happened.
var _walked_back: Dictionary[Person, float] = {}
var _rng := RandomNumberGenerator.new()


## Every game minute: posts to man, patrols for idle guards, prisoners to
## walk back, and anyone being walked keeping up.
func look() -> void:
	for key in manned_desks():
		_last_manned[key] = clock.total_minutes
	_man_posts()
	_walk_routes()
	_patrol()
	_spot_out_of_place()
	_lead()


## Whether each security gate should be locked, by (level, edge x, edge y,
## edge axis): locked unless a guard sits at a desk near it, or did a
## moment ago.
func gate_locks() -> Dictionary[Vector4i, bool]:
	var out: Dictionary[Vector4i, bool] = {}
	var manned := manned_desks()
	for key: Vector2i in _last_manned:
		if clock.total_minutes - _last_manned[key] <= GATE_GRACE and not manned.has(key) \
				and building.object_at(key) != null:
			manned.append(key)
	for n: int in building.levels:
		var map: BuildingMap = building.levels[n]
		for edge: Vector3i in map.door_kinds:
			if not GATE_KINDS.has(map.door_kind_at(edge)):
				continue
			var cells := BuildingMap.edge_cells(edge)
			var middle := (Vector2(cells[0]) + Vector2(cells[1])) * 0.5 + Vector2(0.5, 0.5)
			var open := manned.any(func(key: Vector2i) -> bool:
				return key.x == n and building.object_at(key).centre.distance_to(middle) <= GATE_RANGE)
			out[Vector4i(n, edge.x, edge.y, edge.z)] = not open
	return out


## Desks with a guard sitting at them, as (level, object id).
func manned_desks() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for job in jobs.of_kind(&"post"):
		var stage := job.current()
		if job.worker != null and job.worker.state == Person.State.USING and stage != null and stage.object != -1:
			out.append(Vector2i(stage.level, stage.object))
	return out


## Whether someone is being walked somewhere by a guard.
func is_led(person: Person) -> bool:
	return _led.has(person)


## Keeps a job on the board to man every guard post desk.
func _man_posts() -> void:
	var desks := building.objects_tagged(DESKS)
	var waiting := jobs.of_kind(&"post")
	var covered: Array[Vector2i] = []
	for job in waiting:
		var stage := job.stages[0]
		var key := Vector2i(stage.level, stage.object)
		if not desks.has(key):
			jobs.cancel(job)
		else:
			covered.append(key)
	for key in desks:
		if covered.has(key):
			continue
		var job := Job.new()
		job.kind = &"post"
		job.title = "Man the guard post"
		job.priority = 3
		var sit := Job.at(Job.Do.WORK, key.x, key.y)
		sit.minutes = POST_MINUTES
		sit.doing = "Watching the gates"
		job.stages = [sit]
		jobs.post(job)


## Keeps a job on the board for each guard a patrol route wants: once
## round the loop, then it comes round again.
func _walk_routes() -> void:
	var on: Dictionary[PatrolRoutes.Route, int] = {}
	for job in jobs.of_kind(&"patrol"):
		if not job.has_meta(&"route"):
			continue
		var route: PatrolRoutes.Route = job.get_meta(&"route")
		if routes == null or not routes.routes.has(route) or on.get(route, 0) >= route.guards:
			jobs.cancel(job)
		else:
			on[route] = on.get(route, 0) + 1
	if routes == null:
		return
	for route in routes.routes:
		for i in route.guards - on.get(route, 0):
			var job := Job.new()
			job.kind = &"patrol"
			job.title = "Walk %s" % route.name.to_lower()
			job.priority = 2
			job.set_meta(&"route", route)
			for point in route.points:
				var stop := Job.on_tile(Job.Do.WORK, route.level, Vector2i(point.floor()))
				stop.minutes = ROUTE_PAUSE
				stop.doing = "Walking %s" % route.name.to_lower()
				job.stages.append(stop)
			jobs.post(job)


## A patrol job for every guard with nothing to do, keeping an eye on
## wherever the most prisoners are.
func _patrol() -> void:
	var idle := 0
	for person in people.people:
		if _is_guard(person) and person.job == null and not person.going_home:
			idle += 1
	var waiting := jobs.of_kind(&"patrol").filter(func(job: Job) -> bool:
		return job.worker == null and not job.has_meta(&"route")).size()
	# Routes still wanting a guard take some of them.
	waiting += jobs.of_kind(&"patrol").filter(func(job: Job) -> bool:
		return job.worker == null and job.has_meta(&"route")).size()
	for i in idle - waiting:
		var spot: Variant = _busy_spot()
		if spot == null:
			return
		var job := Job.new()
		job.kind = &"patrol"
		job.title = "Patrol"
		job.priority = 1
		var watch := Job.on_tile(Job.Do.WORK, spot[0], spot[1])
		watch.minutes = PATROL_MINUTES
		watch.doing = "Keeping an eye out"
		job.stages = [watch]
		jobs.post(job)


## A tile, as [level, tile], somewhere in the room with the most
## prisoners in it (an area on alert counting extra), or near a prisoner
## out on the ground. Null with no
## prisoners about.
func _busy_spot() -> Variant:
	var counts: Dictionary[Room, float] = {}
	var levels: Dictionary[Room, int] = {}
	var outside: Array[Person] = []
	for person in people.people:
		if person.group != prisoner_group:
			continue
		var here := people.room_of(person)
		if here.is_empty():
			outside.append(person)
			continue
		counts[here[1]] = counts.get(here[1], 0.0) + 1.0
		levels[here[1]] = here[0]
	if area_weight.is_valid():
		for room: Room in counts:
			counts[room] *= area_weight.call(levels[room], room.centre())
	var best: Room = null
	for room: Room in counts:
		if best == null or counts[room] > counts[best] or (counts[room] == counts[best] and _rng.randf() < 0.5):
			best = room
	if best != null and (outside.is_empty() or counts[best] >= outside.size()):
		var cell: Vector2i = best.cells[_rng.randi() % best.cells.size()]
		return [levels[best], cell]
	if not outside.is_empty():
		var someone := outside[_rng.randi() % outside.size()]
		return [someone.level, Vector2i(someone.flat().floor())]
	return null


## Guards who see a prisoner out of place post a job to walk them back.
func _spot_out_of_place() -> void:
	var guards := people.people.filter(func(p: Person) -> bool: return _is_guard(p) and not p.going_home)
	if guards.is_empty():
		return
	var asked: Dictionary[Person, bool] = {}
	for job in jobs.of_kind(&"escort"):
		asked[job.get_meta(&"prisoner")] = true
	for guard: Person in guards:
		for person in people.nearby(guard, FAR_WATCH_DISTANCE):
			if person.group != prisoner_group or not person.out_of_place or asked.has(person) or person.sitting \
					or person.flat().distance_to(guard.flat()) > watch_distance(person) \
					or _led.has(person) or clock.total_minutes - _walked_back.get(person, -INF) < ESCORT_COOLDOWN:
				continue
			var to := _place_tile(person)
			if to.is_empty():
				continue
			asked[person] = true
			escort(person, to)


## How far from a guard someone is spotted out of place, by category.
func watch_distance(person: Person) -> float:
	var category: CategoryDef = people.categories.get(person.category)
	return minf(category.watch_distance, FAR_WATCH_DISTANCE) if category != null else WATCH_DISTANCE


## A tile in the first room someone's block wants them in that they can
## get to, as [level, tile], or [].
func _place_tile(person: Person) -> Array:
	for entry: Array in people.place_rooms(person):
		var room: Room = entry[1]
		for attempt in PLACE_TRIES:
			var tile: Vector2i = room.cells[_rng.randi() % room.cells.size()]
			if people.can_reach(person, entry[0], Vector2(tile) + Vector2(0.5, 0.5)):
				return [entry[0], tile]
	return []


## Posts a job for a guard to walk someone to a tile, as [level, tile]:
## back where they should be unless `where` says otherwise, such as "to
## their cell". The moodlet, if any, is theirs when they get there.
func escort(person: Person, to: Array, where := "back", moodlet := walked_back_moodlet) -> void:
	jobs.post(_escort_job(person, to, where, moodlet))


## An escort again for a guard loaded part way through one.
func rebuild(work: Dictionary) -> Job:
	var id: int = work["with"].get(&"prisoner", -1)
	var prisoners := people.people.filter(func(p: Person) -> bool: return p.id == id)
	if prisoners.is_empty():
		return null
	var person: Person = prisoners[0]
	var title: String = work["title"]
	var where := title.substr(title.find(" ", 5) + 1)
	return _escort_job(person, [work["last"][0], work["last"][2]], where,
			walked_back_moodlet if where == "back" else &"")


## Takes down any job to walk someone somewhere, and lets them go if a
## guard has them.
func cancel_escort(person: Person) -> void:
	for job in jobs.of_kind(&"escort"):
		if job.get_meta(&"prisoner") == person:
			jobs.cancel(job)
	if _led.has(person):
		_let_go(person)


func _escort_job(person: Person, to: Array, where: String, moodlet: StringName) -> Job:
	var first := person.name.get_slice(" ", 0)
	var job := Job.new()
	job.kind = &"escort"
	job.title = "Walk %s %s" % [first, where]
	job.priority = 4
	job.set_meta(&"prisoner", person)
	var word := Job.on_tile(Job.Do.WORK, person.level, Vector2i(person.flat().floor()))
	word.minutes = 1.0
	word.doing = "Having a word" if where == "back" else "Collecting %s" % first
	word.finish = func(_stage: Job.Stage, guard: Person) -> void:
		if people.people.has(person):
			people.stop(person)
			person.led = true
			_led[person] = guard
			_led_doing[person] = "Being walked %s" % where
	var walk := Job.on_tile(Job.Do.WORK, to[0], to[1])
	walk.minutes = 1.0
	walk.doing = "Walking %s %s" % [first, where]
	walk.finish = func(_stage: Job.Stage, _guard: Person) -> void:
		_let_go(person)
		_walked_back[person] = clock.total_minutes
		if people.people.has(person) and moodlet != &"":
			people.add_moodlet(person, moodlet)
	job.stages = [word, walk]
	return job


## Prisoners being walked keep up with their guard, and are let go if the
## guard stops walking them.
func _lead() -> void:
	for person: Person in _led.keys():
		var guard := _led[person]
		var still: bool = people.people.has(person) and people.people.has(guard) and guard.job != null \
				and guard.job.kind == &"escort" and guard.job.get_meta(&"prisoner") == person
		if not still:
			_let_go(person)
			continue
		if person.level != guard.level or person.flat().distance_to(guard.flat()) > FOLLOW_DISTANCE:
			people.walk_to(person, guard.level, guard.flat(), _led_doing.get(person, "Being walked back"))
			person.led = true


func _let_go(person: Person) -> void:
	_led.erase(person)
	_led_doing.erase(person)
	person.led = false
	if people.people.has(person):
		people.stop(person)


func _is_guard(person: Person) -> bool:
	return person.role != &"" and jobs.roles.has(person.role) \
			and (jobs.roles[person.role] as StaffRoleDef).job_kinds.has(&"patrol")
