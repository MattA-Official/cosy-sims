class_name Training
extends Node
## The training room. Staff sent on their course on site (StaffRoster
## send_on_course with on_site) spend that day's shift on a chair in a
## training room, off the floor, in sittings of SITTING_MINUTES so they can
## still take breaks.

const ROOM := &"training"
const SEATS: Array[StringName] = [&"chair"]
const JOB := &"training"
const SITTING_MINUTES := 120.0

var people: People
var jobs: JobBoard
var building: Building
var roster: StaffRoster
var clock: GameClock:
	set(value):
		clock = value
		clock.minute_passed.connect(func(_minute: int) -> void: update())


## Whether there's a training room with a seat in it.
func has_room() -> bool:
	return not seats().is_empty()


## Every seat in a training room, as (level, object id).
func seats() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for n: int in building.levels:
		var map := building.levels[n]
		for room: Room in map.rooms():
			if room.type != ROOM:
				continue
			for placed in map.objects_in_room(room):
				if SEATS.any(func(tag: StringName) -> bool: return placed.def.tags.has(tag)):
					out.append(Vector2i(n, placed.id))
	return out


## Keeps a sitting on the board for everyone in training today.
func update() -> void:
	var covered: Array[Person] = []
	for job in jobs.of_kind(JOB):
		if job.only_for == null or not roster.in_training(roster.record_of(job.only_for)) or job.only_for.going_home:
			jobs.cancel(job)
		else:
			covered.append(job.only_for)
	var free := seats()
	for job in jobs.of_kind(JOB):
		free.erase(Vector2i(job.stages[0].level, job.stages[0].object))
	for record in roster.records:
		var person := record.person
		if person == null or person.going_home or covered.has(person) or not roster.in_training(record) or free.is_empty():
			continue
		var seat: Vector2i = free.pop_front()
		var role := roster._role(record.role)
		var job := Job.new()
		job.kind = JOB
		job.only_for = person
		job.title = "Training"
		job.priority = 9
		var sit := Job.at(Job.Do.WORK, seat.x, seat.y)
		sit.minutes = SITTING_MINUTES
		sit.doing = "On a %s course" % role.course_name.to_lower() if role != null and not role.course_name.is_empty() else "Training"
		job.stages = [sit]
		jobs.post(job)
