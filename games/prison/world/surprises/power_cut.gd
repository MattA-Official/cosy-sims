extends Surprise
## The power goes off for the night, from CUT_HOUR: electric doors fail
## locked, the lights go out, and a handyman goes to mend the fuse box,
## which brings it back sooner. The cameras go off too when hard.

const CUT_HOUR := 22
const FIX := &"fix_power"
const FIX_MINUTES := 30.0
const DARK := &"lights_out"

var off := false
## [level, edge] of the doors this locked.
var _locked: Array = []
var _hour := 0.0


func tick(minutes: float) -> void:
	var clock: GameClock = main.clock
	if not off and clock.hour() >= CUT_HOUR:
		cut()
	if not off:
		return
	_hour += minutes
	if _hour >= 60.0:
		_hour = 0.0
		var people: People = main.people
		for person in people.people:
			if person.group == &"prisoner" and not person.outdoors and not people.is_asleep(person):
				people.add_moodlet(person, DARK)


## The power goes.
func cut() -> void:
	off = true
	_apply()
	var spot: Array = (main.shifts as Shifts).entrance
	if spot.is_empty():
		return
	var job := Job.new()
	job.kind = FIX
	job.title = "Mend the fuse box"
	job.roles = [&"handyman"]
	job.priority = 5
	job.any_time = true
	var stage := Job.on_tile(Job.Do.WORK, spot[0], Vector2i((spot[1] as Vector2).floor()))
	stage.minutes = FIX_MINUTES
	stage.doing = "Mending the fuse box"
	stage.finish = func(_stage: Job.Stage, _worker: Person) -> void: minutes_left = 0.0
	job.stages = [stage]
	(main.jobs as JobBoard).post(job)


func _apply() -> void:
	(main.utilities as Utilities).cut = true
	if hard:
		(main.security as Security).cameras_off = true
	var people: People = main.people
	var building: Building = main.building
	for n: int in building.levels:
		var map: BuildingMap = building.levels[n]
		for edge: Vector3i in map.door_kinds:
			var kind: DoorKindDef = people.access.door_kinds.get(map.door_kinds[edge])
			if kind != null and kind.electric and not people.is_door_locked(n, edge):
				people.set_door_locked(n, edge, true)
				_locked.append([n, edge])


func finish() -> void:
	var people: People = main.people
	for entry: Array in _locked:
		people.set_door_locked(entry[0], entry[1], false)
	_locked.clear()
	(main.utilities as Utilities).cut = false
	(main.security as Security).cameras_off = false
	var jobs: JobBoard = main.jobs
	for job in jobs.of_kind(FIX):
		jobs.cancel(job)


func words() -> String:
	return "Power off" if off else "Expected at %d:00" % CUT_HOUR


func to_data() -> Dictionary:
	return {"off": off, "locked": _locked.duplicate(true)}


func from_data(data: Dictionary) -> void:
	off = data.get("off", false)
	if off:
		_apply()
		for entry: Array in data.get("locked", []):
			if not _locked.has(entry):
				_locked.append(entry)
