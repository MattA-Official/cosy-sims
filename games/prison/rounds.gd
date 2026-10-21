class_name Rounds
extends Node
## The warden's rounds. Once a day at HOUR the warden walks the prison,
## stopping a few minutes in up to STOPS rooms. Prisoners near a stop who
## are in a good mood get a small moodlet from meeting the warden, and the
## morning report says how the rounds went.

const HOUR := 10
const STOPS := 5
const STOP_MINUTES := 4.0
## Tiles from a stop that count as meeting the warden.
const MEET_DISTANCE := 4.0
const GOOD_MOOD := 50.0
const JOB := &"rounds"
const MOODLET := &"met_the_warden"
const WARDEN := &"warden"
## Rooms worth a visit: where prisoners spend their day.
const ROOMS: Array[StringName] = [&"canteen", &"yard", &"workshop", &"classroom", &"laundry", &"kitchen",
		&"dorm", &"shower", &"infirmary", &"counselling", &"quiet_room"]

var people: People
var jobs: JobBoard
var building: Building
var clock: GameClock:
	set(value):
		clock = value
		clock.hour_changed.connect(func(hour: int) -> void:
			if hour == HOUR:
				start_rounds())
		clock.day_changed.connect(func(_day: int) -> void:
			yesterday = today
			today = {"stops": 0, "met": 0})
## Rounds so far today and yesterday: stops made and prisoners met.
var today := {"stops": 0, "met": 0}
var yesterday := {"stops": 0, "met": 0}
var _rng := RandomNumberGenerator.new()


static func moodlet() -> MoodletDef:
	var def := MoodletDef.new()
	def.id = MOODLET
	def.display_name = "Met the warden"
	def.mood = 4.0
	def.hours = 12.0
	return def


## Sends the warden on their rounds, if they're on site. Returns the job,
## or null.
func start_rounds() -> Job:
	var warden := _warden()
	if warden == null or warden.going_home or jobs.of_kind(JOB).any(func(j: Job) -> bool: return j.only_for == warden):
		return null
	var stops := _stops()
	if stops.is_empty():
		return null
	var job := Job.new()
	job.kind = JOB
	job.only_for = warden
	job.title = "Do the rounds"
	job.priority = 5
	for stop: Vector3i in stops:
		var stage := Job.on_tile(Job.Do.WORK, stop.x, Vector2i(stop.y, stop.z))
		stage.minutes = STOP_MINUTES
		stage.doing = "Doing the rounds"
		stage.finish = func(done: Job.Stage, worker: Person) -> void: meet(done.level, worker)
		job.stages.append(stage)
	return jobs.post(job)


## The warden stops: good-humoured prisoners nearby are pleased to meet
## them. Returns how many.
func meet(level: int, warden: Person) -> int:
	var met := 0
	for person in people.people:
		if person.group == &"prisoner" and person.level == level and person.mood >= GOOD_MOOD \
				and person.flat().distance_to(warden.flat()) <= MEET_DISTANCE:
			people.add_moodlet(person, MOODLET)
			met += 1
	today["stops"] += 1
	today["met"] += met
	return met


## A line for the morning report.
func report_lines() -> Array[String]:
	if yesterday["stops"] == 0:
		return []
	return ["The warden did the rounds and met %d %s in a good mood." % [yesterday["met"],
			"prisoner" if yesterday["met"] == 1 else "prisoners"]]


## Up to STOPS rooms worth a visit, as (level, tile x, tile y).
func _stops() -> Array[Vector3i]:
	var out: Array[Vector3i] = []
	for n: int in building.levels:
		for room: Room in building.levels[n].rooms():
			if ROOMS.has(room.type) and not room.cells.is_empty():
				var cell := room.cells[room.cells.size() / 2]
				out.append(Vector3i(n, cell.x, cell.y))
	out.shuffle()
	return out.slice(0, STOPS)


func _warden() -> Person:
	for person in people.people:
		if person.role == WARDEN:
			return person
	return null
