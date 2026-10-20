class_name JobBoard
extends RefCounted
## Every piece of work in the place, on one board. Systems post jobs (a
## lorry arrives, a meal is due, rubbish appears); idle workers take the
## best one they may do, highest priority first, then nearest, and work
## through its stages. A job is held by one worker at a time. One that
## can't be done goes back on the board for a while, with the reason.
##
## Workers are staff with a role, and prisoners on a work programme while
## their block says to work (ActivityDef.jobs).

## Game minutes a job waits after it couldn't be done.
const RETRY_MINUTES := 5.0
## How long picking up or putting down takes.
const HANDLING_MINUTES := 0.5

signal job_finished(job: Job)

var jobs: Array[Job] = []
var people: People
var items: ItemStore
## Staff roles by id, for the job kinds each may take.
var roles: Dictionary[StringName, StaffRoleDef] = {}


func post(job: Job) -> Job:
	jobs.append(job)
	return job


## Takes a job off the board, letting go of anyone working on it.
func cancel(job: Job) -> void:
	jobs.erase(job)
	var worker := job.worker
	if worker != null:
		var pair := items.put_down(worker)
		if not pair.is_empty():
			var tile := Vector2i(worker.flat().floor())
			items.drop_on_floor(Vector3i(worker.level, tile.x, tile.y), pair[0], pair[1])
		_let_go(job)
		people.stop(worker)


## Takes every job off the board, so jobs and their workers (who point at
## each other) can be freed.
func clear() -> void:
	for job in jobs:
		if job.worker != null:
			job.worker.job = null
		job.worker = null
	jobs.clear()


func step(minutes: float) -> void:
	for job in jobs:
		job.wait -= minutes


## Open jobs of a kind, taken or not.
func of_kind(kind: StringName) -> Array[Job]:
	var out: Array[Job] = []
	for job in jobs:
		if job.kind == kind:
			out.append(job)
	return out


## Does someone work from the board just now?
func wants_work(person: Person) -> bool:
	if person.role != &"":
		return true
	return person.programme != &"" and person.block != null and person.block.jobs


## May someone take a job?
func may_take(person: Person, job: Job) -> bool:
	if person.role != &"":
		var role: StaffRoleDef = roles.get(person.role)
		return job.roles.has(person.role) or (role != null and role.job_kinds.has(job.kind) and job.roles.is_empty())
	return person.programme != &"" and job.programmes.has(person.programme)


## Is there a job someone could take now?
func has_work_for(person: Person) -> bool:
	if person.job != null:
		return true
	if not wants_work(person):
		return false
	for job in jobs:
		if job.worker == null and job.wait <= 0.0 and may_take(person, job):
			return true
	return false


## Gets someone on with their job, taking the best one first if they have
## none. Returns false if there is nothing for them.
func carry_on(person: Person) -> bool:
	if person.job == null:
		var best := _best_for(person)
		if best == null:
			return false
		best.worker = person
		person.job = best
	return _start_stage(person)


## They have reached the place for their job's stage.
func arrived(person: Person) -> void:
	var job := person.job
	var stage := job.current()
	match stage.do:
		Job.Do.FETCH:
			var got := _fetch(stage)
			if got.is_empty():
				_fail(job, "Nothing to pick up")
				return
			items.pick_up(person, got)
			_work_for(person, HANDLING_MINUTES, stage.doing)
		Job.Do.DELIVER:
			if not _deliver(person, stage):
				_fail(job, "No room to put it down")
				return
			_work_for(person, HANDLING_MINUTES, stage.doing)
		Job.Do.WORK:
			_work_for(person, stage.minutes, stage.doing)


## Their time at the stage is up: on to the next, or done.
func stage_done(person: Person) -> void:
	var job := person.job
	var stage := job.current()
	if stage.do == Job.Do.WORK and stage.finish.is_valid():
		stage.finish.call(stage, person)
	people.finish_working(person)
	job.stage += 1
	if job.stage < job.stages.size():
		_start_stage(person)
		return
	job.done = true
	person.job = null
	job.worker = null
	jobs.erase(job)
	if job.on_done.is_valid():
		job.on_done.call(job)
	job_finished.emit(job)


## Someone has stopped part way (called away, or removed): whatever they
## carry goes down on the floor where they are, and the job goes back on
## the board to fetch it from there.
func abandon(person: Person) -> void:
	var job := person.job
	if job == null:
		return
	_drop_carried(person, job)
	_let_go(job)


func _start_stage(person: Person) -> bool:
	var job := person.job
	var stage := job.current()
	if not stage.places.is_empty():
		var key := _choose(person, stage)
		if key.y == -1:
			_fail(job, ["Nothing to pick up", "Nowhere to put it", "Nowhere free to do it"][stage.do])
			return false
		stage.level = key.x
		stage.object = key.y
	var map := people.building.levels.get(stage.level) as BuildingMap
	if map == null:
		_fail(job, "Its place has gone")
		return false
	var spots: Array[Vector2] = []
	if stage.at_object():
		var placed: BuildingMap.PlacedObject = map.objects.get(stage.object)
		if placed == null:
			_fail(job, "Its %s has gone" % ("object" if stage.do != Job.Do.WORK else "place"))
			return false
		spots = people.spots_beside(stage.level, placed, person.flat())
	else:
		spots = [Vector2(stage.tile) + Vector2(0.5, 0.5)]
	for spot in spots:
		if spot.distance_to(person.flat()) < 0.3 and stage.level == person.level:
			arrived(person)
			return person.job == job
		if people.walk_to(person, stage.level, spot, stage.doing if not stage.doing.is_empty() else job.title):
			return true
	_fail(job, "Can't get there")
	return false


func _work_for(person: Person, minutes: float, doing: String) -> void:
	people.start_working(person, minutes, doing)


func _fetch(stage: Job.Stage) -> Array:
	if stage.at_object():
		return items.take_from(Vector2i(stage.level, stage.object), stage.tag, stage.count)
	return items.take_from_floor(Vector3i(stage.level, stage.tile.x, stage.tile.y), stage.tag, stage.count)


func _deliver(person: Person, stage: Job.Stage) -> bool:
	var pair := items.put_down(person)
	if pair.is_empty():
		return true
	if not stage.at_object():
		items.drop_on_floor(Vector3i(stage.level, stage.tile.x, stage.tile.y), pair[0], pair[1])
		return true
	var placed: BuildingMap.PlacedObject = people.building.levels[stage.level].objects.get(stage.object)
	var key := Vector2i(stage.level, stage.object)
	var went := items.put_in(key, placed, pair[0], pair[1]) if placed != null else 0
	if went < pair[1]:
		# What doesn't fit stays in their hands.
		items.pick_up(person, [pair[0], pair[1] - went])
		return false
	return true


func _best_for(person: Person) -> Job:
	var best: Job = null
	var best_score := INF
	for job in jobs:
		if job.worker != null or job.wait > 0.0 or not may_take(person, job):
			continue
		var stage := job.current()
		var distance := 0.0
		if stage.places.is_empty():
			distance = _place(stage).distance_to(person.flat()) + absi(stage.level - person.level) * 12.0
		var score := -job.priority * 1000.0 + distance
		if score < best_score:
			best = job
			best_score = score
	return best


## The nearest object for a stage that picks its place, as (level, object
## id), or (0, -1) if none suits.
func _choose(person: Person, stage: Job.Stage) -> Vector2i:
	var best := Vector2i(0, -1)
	var best_distance := INF
	for n: int in people.building.levels:
		var map := people.building.levels[n]
		for placed: BuildingMap.PlacedObject in map.objects.values():
			if not placed.def.tags.any(func(t: StringName) -> bool: return stage.places.has(t)):
				continue
			var key := Vector2i(n, placed.id)
			match stage.do:
				Job.Do.FETCH:
					if items.count_in(key, stage.tag) <= 0:
						continue
				Job.Do.DELIVER:
					if not placed.def.holds.has(stage.tag) or items.room_in(key, placed) <= 0:
						continue
				Job.Do.WORK:
					if _busy(key, person) or (stage.tag != &"" and items.room_in(key, placed) <= 0):
						continue
			if not people.may_enter(person, map.room_at_point(placed.centre)):
				continue
			var distance := placed.centre.distance_to(person.flat()) + absi(n - person.level) * 12.0
			if distance < best_distance:
				best = key
				best_distance = distance
	return best


## Is someone else working at an object for a job?
func _busy(key: Vector2i, person: Person) -> bool:
	for job in jobs:
		var stage := job.current()
		if job.worker != null and job.worker != person and stage != null and stage.do == Job.Do.WORK \
				and stage.level == key.x and stage.object == key.y:
			return true
	return false


func _place(stage: Job.Stage) -> Vector2:
	if stage.at_object():
		var map := people.building.levels.get(stage.level) as BuildingMap
		var placed: BuildingMap.PlacedObject = map.objects.get(stage.object) if map != null else null
		if placed != null:
			return placed.centre
	return Vector2(stage.tile) + Vector2(0.5, 0.5)


func _fail(job: Job, reason: String) -> void:
	job.reason = reason
	job.wait = RETRY_MINUTES
	var worker := job.worker
	if worker != null:
		_drop_carried(worker, job)
		_let_go(job)
		people.stop(worker)
		worker.reason = "%s: %s" % [job.title, reason]


func _drop_carried(person: Person, job: Job) -> void:
	var pair := items.put_down(person)
	if pair.is_empty():
		return
	var tile := Vector2i(person.flat().floor())
	items.drop_on_floor(Vector3i(person.level, tile.x, tile.y), pair[0], pair[1])
	# Back on the board, starting by picking them up again. Holding them
	# during a fetch means that fetch is done.
	var fetch := Job.on_tile(Job.Do.FETCH, person.level, tile)
	fetch.tag = pair[0].tags[0] if not pair[0].tags.is_empty() else &""
	fetch.count = pair[1]
	fetch.doing = "Picking up"
	var current := job.current()
	job.stages = job.stages.slice(job.stage + (1 if current != null and current.do == Job.Do.FETCH else 0))
	job.stages.insert(0, fetch)
	job.stage = 0


func _let_go(job: Job) -> void:
	if job.worker != null:
		job.worker.job = null
	job.worker = null
