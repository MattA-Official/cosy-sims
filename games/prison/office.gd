class_name Office
extends Node
## The warden's office. A warden on the staff and an office with a desk to
## work at unlock the intake settings, grant goals and the daily report.
## While on shift the warden sits at the office desk.

const OFFICE := &"office"
const DESKS: Array[StringName] = [&"desk"]
const WARDEN := &"warden"
## Game minutes the warden works at the desk before the job comes round
## again, when they may take a break.
const DESK_MINUTES := 120.0

var people: People
var jobs: JobBoard
var building: Building
var shifts: Shifts
var clock: GameClock:
	set(value):
		clock = value
		clock.minute_passed.connect(func(_minute: int) -> void: _man_desk())


## Whether a warden is employed and has an office to work from.
func has_warden() -> bool:
	return employs_warden() and not office_desk().is_empty()


func employs_warden() -> bool:
	return shifts.shifts.any(func(shift: ShiftDef) -> bool: return shifts.wanted_for(WARDEN, shift.id) > 0)


## The desk in an office, as (level, object id), or an empty array.
func office_desk() -> Array[Vector2i]:
	for n: int in building.levels:
		var map := building.levels[n]
		for room: Room in map.rooms():
			if room.type != OFFICE:
				continue
			for placed in map.objects_in_room(room):
				if DESKS.any(func(tag: StringName) -> bool: return placed.def.tags.has(tag)):
					return [Vector2i(n, placed.id)]
	return []


## What's missing for the office to work, or "".
func missing() -> String:
	if office_desk().is_empty() and not employs_warden():
		return "Build an office with a desk and take on a warden in the Staff window (P)."
	if office_desk().is_empty():
		return "Build an office with a desk for the warden to work from."
	if not employs_warden():
		return "Take on a warden in the Staff window (P)."
	return ""


## Keeps a job on the board for the warden to work at the office desk.
func _man_desk() -> void:
	var desk := office_desk()
	for job in jobs.of_kind(&"office"):
		var stage := job.stages[0]
		if desk.is_empty() or Vector2i(stage.level, stage.object) != desk[0]:
			jobs.cancel(job)
	if desk.is_empty() or not jobs.of_kind(&"office").is_empty():
		return
	var job := Job.new()
	job.kind = &"office"
	job.title = "Run the prison"
	job.priority = 2
	var sit := Job.at(Job.Do.WORK, desk[0].x, desk[0].y)
	sit.minutes = DESK_MINUTES
	sit.doing = "Running the prison"
	job.stages = [sit]
	jobs.post(job)
