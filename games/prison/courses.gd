class_name Courses
extends Node
## Classes and therapy. Each course (see CourseDef) runs in a room of its
## type, one course to a room, with a teacher (or counsellor) on shift. The
## player sets how many places each course has; free places fill from the
## prisoners who haven't passed it, lowest reform first. In blocks that
## hold classes, the teacher works at the board and each student sits at a
## desk; a session counts if they sat through it with the teacher there.
## After the course's sessions comes the exam: a pass lifts reform and the
## course's skill, a fail goes back two sessions to resit.

signal passed(person: Person, def: CourseDef)
signal failed(person: Person, def: CourseDef)

## Pass chance: a base, plus a little per reform point, less for a low
## mood, kept between the bounds.
const PASS_BASE := 0.45
const PASS_PER_REFORM := 0.004
const LOW_MOOD := 40.0
const LOW_MOOD_PENALTY := 0.15
const PASS_MIN := 0.1
const PASS_MAX := 0.95
## Sessions a fail sends them back.
const RESIT_BACK := 2
## Share of a session they must sit through, leaving time to walk there.
const ATTEND_SHARE := 0.65
## Calm Minds: tempers cool this much after a pass for good, and for a few
## days after each session.
const CALMER := &"calmer"
const CALMER_SCALE := 0.7
const SESSION_CALM_SCALE := 0.8
const SESSION_CALM_DAYS := 3
## How often enrolment and classes are looked at, in game minutes.
const LOOK_EVERY := 5

var people: People
var jobs: JobBoard
var building: Building
var runner: ScheduleRunner
## Places sessions in the week. Optional: without it, classes run in every
## block that holds them.
var regime: Regime
var reform: Progress
var prisoner_group: StringName = &"prisoner"
var defs: Array[CourseDef] = []
## Places each course has, by id, as the player sets them.
var places: Dictionary[StringName, int] = {}
var clock: GameClock:
	set(value):
		clock = value
		clock.minute_passed.connect(func(minute: int) -> void:
			if minute % LOOK_EVERY == 0:
				look())

## The teacher's job each running course has, and each student's.
var _teaching: Dictionary[StringName, Job] = {}
var _attending: Dictionary[Person, Job] = {}
var _rng := RandomNumberGenerator.new()


func def(id: StringName) -> CourseDef:
	for course in defs:
		if course.id == id:
			return course
	return null


## The course someone is on, or null.
func course_of(person: Person) -> CourseDef:
	return def(person.profile.get("course", &""))


## Sessions they've sat of their course so far.
func attended(person: Person) -> int:
	return person.profile.get("course_attended", 0)


func enrolled(id: StringName) -> Array[Person]:
	var out: Array[Person] = []
	for person in people.people:
		if person.profile.get("course", &"") == id:
			out.append(person)
	return out


## Who'd take a free place, first in line first: anyone put forward in
## the inspector, then the least reformed.
func waiting(id: StringName) -> Array[Person]:
	var out: Array[Person] = []
	for person in people.people:
		if person.group != prisoner_group or person.profile.get("course", &"") != &"" \
				or PrisonerFile.of(person).passed.has(id) or PrisonerFile.of(person).due_out:
			continue
		out.append(person)
	out.sort_custom(func(a: Person, b: Person) -> bool:
		var a_first: bool = a.profile.get("put_forward", &"") == id
		var b_first: bool = b.profile.get("put_forward", &"") == id
		if a_first != b_first:
			return a_first
		return reform.value(a) < reform.value(b))
	return out


func set_places(id: StringName, count: int) -> void:
	places[id] = maxi(count, 0)
	fill()


## Puts someone on a course, or takes them off theirs.
func enrol(person: Person, id: StringName) -> void:
	leave(person)
	person.profile["course"] = id
	person.profile["course_attended"] = 0
	person.profile.erase("put_forward")


func leave(person: Person) -> void:
	person.profile.erase("course")
	person.profile.erase("course_attended")
	if _attending.has(person):
		jobs.cancel(_attending[person])
		_attending.erase(person)


## Fills free places, and frees any over the number set (newest first).
func fill() -> void:
	for course in defs:
		var on := enrolled(course.id)
		var want: int = places.get(course.id, 0)
		on.sort_custom(func(a: Person, b: Person) -> bool: return attended(a) < attended(b))
		while on.size() > want:
			leave(on.pop_front())
		if on.size() < want:
			for person in waiting(course.id).slice(0, want - on.size()):
				enrol(person, course.id)


## The room each course with students runs in, as [level, Room], one
## course to a room, in the order the courses are listed.
func rooms() -> Dictionary[StringName, Array]:
	var out: Dictionary[StringName, Array] = {}
	var taken: Array[Room] = []
	for course in defs:
		if enrolled(course.id).is_empty():
			continue
		for n: int in building.levels:
			for room: Room in building.levels[n].rooms():
				if room.type == course.room_type and not taken.has(room) and not out.has(course.id):
					out[course.id] = [n, room]
					taken.append(room)
	return out


## Why a course isn't running, or "" if it is.
func problem(course: CourseDef) -> String:
	if places.get(course.id, 0) <= 0:
		return "No places set"
	if enrolled(course.id).is_empty():
		return "Nobody waiting"
	if not rooms().has(course.id):
		return "Needs a free %s" % ("counselling room" if course.room_type == &"counselling" else String(course.room_type))
	if not _teacher_on(course):
		return "No %s on shift" % course.teacher_role
	return ""


func _teacher_on(course: CourseDef) -> bool:
	return people.people.any(func(p: Person) -> bool: return p.role == course.teacher_role and not p.going_home)


## Posts and cancels class jobs for whoever is in a class block now.
func look() -> void:
	fill()
	var running := rooms()
	for course in defs:
		var students := enrolled(course.id).filter(_in_class)
		if not running.has(course.id) or students.is_empty():
			_stop_teaching(course.id)
			continue
		var level: int = running[course.id][0]
		var room: Room = running[course.id][1]
		if not _teaching.has(course.id) and _teacher_on(course):
			_teach(course, level, room)
		for student: Person in students:
			if not _attending.has(student) and student.profile.get("class_block", -1.0) != _block_start(student):
				_attend(course, student, level, room)
	for student: Person in _attending.keys():
		if not _in_class(student) or course_of(student) == null:
			jobs.cancel(_attending[student])
			_attending.erase(student)


func _in_class(person: Person) -> bool:
	if regime != null:
		var course := course_of(person)
		var placed := regime.running(course.id, clock.total_minutes) if course != null else null
		return placed != null and person.block != null and regime._allowed(placed.session, person.block)
	return person.block != null and person.block.classes


## When the class someone is in began, in game minutes: its session, or
## without a regime, its block.
func _block_start(person: Person) -> float:
	if regime != null and course_of(person) != null:
		var placed := regime.running(course_of(person).id, clock.total_minutes)
		if placed != null:
			var into := posmod(Schedule.slot_of(clock.total_minutes) - placed.slot, Schedule.SLOTS)
			return snappedf(floorf(clock.total_minutes / Schedule.SLOT_MINUTES) * Schedule.SLOT_MINUTES
					- into * Schedule.SLOT_MINUTES, 1.0)
	var key := runner.key_for(person)
	return snappedf(clock.total_minutes - runner.minutes_into_block(key), 1.0)


func _teach(course: CourseDef, level: int, room: Room) -> void:
	var spot := _free_object(level, room, course.teacher_tag, [])
	if spot == -1:
		return
	var job := Job.new()
	job.kind = &"teach"
	job.title = "Teach %s" % course.display_name
	job.roles = [course.teacher_role]
	job.priority = 4
	var stage := Job.at(Job.Do.WORK, level, spot)
	stage.minutes = course.session_minutes
	stage.doing = "Running Calm Minds" if course.teacher_role == &"counsellor" else "Teaching %s" % course.display_name.to_lower()
	job.stages = [stage]
	job.on_done = func(_job: Job) -> void: _teaching.erase(course.id)
	_teaching[course.id] = jobs.post(job)


func _stop_teaching(id: StringName) -> void:
	if _teaching.has(id):
		jobs.cancel(_teaching[id])
		_teaching.erase(id)


func _attend(course: CourseDef, student: Person, level: int, room: Room) -> void:
	var used: Array[int] = []
	for other: Person in _attending:
		var stage := _attending[other].current()
		if stage != null and stage.level == level:
			used.append(stage.object)
	if _teaching.has(course.id) and course.teacher_tag == course.student_tag:
		used.append(_teaching[course.id].stages[0].object)
	var seat := _free_object(level, room, course.student_tag, used)
	if seat == -1:
		return
	var job := Job.new()
	job.kind = &"attend"
	job.title = "Go to %s" % course.display_name
	job.only_for = student
	job.priority = 4
	var stage := Job.at(Job.Do.WORK, level, seat)
	stage.minutes = course.session_minutes * ATTEND_SHARE
	stage.doing = "In %s" % ("therapy" if course.teacher_role == &"counsellor" else "class")
	var block := _block_start(student)
	stage.finish = func(_stage: Job.Stage, _worker: Person) -> void: _sat(student, course, block)
	job.stages = [stage]
	job.on_done = func(_job: Job) -> void: _attending.erase(student)
	_attending[student] = jobs.post(job)


## A free object with a tag in a room, other than those in `used`.
func _free_object(level: int, room: Room, tag: StringName, used: Array[int]) -> int:
	var map := building.levels[level]
	for placed in map.objects_in_room(room):
		if placed.def.tags.has(tag) and not used.has(placed.id):
			return placed.id
	return -1


## Sat through a session: it counts if the teacher was there.
func _sat(student: Person, course: CourseDef, block: float) -> void:
	student.profile["class_block"] = block
	var teacher: Job = _teaching.get(course.id)
	if teacher == null or teacher.worker == null or teacher.worker.state != Person.State.USING:
		student.bubble = "No teacher today!"
		student.bubble_minutes = 30.0
		return
	session_done(student, course)


## A session counted: reform, a calmer few days for therapy, and the exam
## once they've had them all.
func session_done(student: Person, course: CourseDef) -> void:
	student.profile["course_attended"] = attended(student) + 1
	reform.add(student, course.session_source)
	if course.after_pass == CALMER:
		student.profile["calm_until"] = _today() + SESSION_CALM_DAYS
	if attended(student) >= course.sessions:
		exam(student, course)


## Their chance of passing a course's exam now, from 0.1 to 0.95.
func pass_chance(person: Person, course: CourseDef) -> float:
	var chance := PASS_BASE + reform.value(person) * PASS_PER_REFORM
	for t in person.traits:
		chance += course.trait_bonus.get(t.id, 0.0)
	if person.mood < LOW_MOOD:
		chance -= LOW_MOOD_PENALTY
	return clampf(chance, PASS_MIN, PASS_MAX)


## Sits the exam. Returns whether they passed.
func exam(person: Person, course: CourseDef, roll := -1.0) -> bool:
	var file := PrisonerFile.of(person)
	if (roll if roll >= 0.0 else _rng.randf()) < pass_chance(person, course):
		file.passed.append(course.id)
		reform.add(person, &"course_passed")
		if course.skill != &"":
			file.raise_skill(course.skill, course.skill_on_pass)
		if course.after_pass == CALMER:
			person.profile[CALMER] = true
		if course.pass_moodlet != &"":
			people.add_moodlet(person, course.pass_moodlet)
		file.add_log(_today(), "Passed %s" % course.display_name)
		leave(person)
		passed.emit(person, course)
		return true
	person.profile["course_attended"] = maxi(course.sessions - RESIT_BACK, 0)
	file.add_log(_today(), "Failed the %s exam, resitting" % course.display_name)
	failed.emit(person, course)
	return false


## How much Calm Minds cools someone's temper (see Misconduct).
func calm_scale(person: Person) -> float:
	var scale := CALMER_SCALE if person.profile.get(CALMER, false) else 1.0
	if person.profile.get("calm_until", 0) >= _today():
		scale *= SESSION_CALM_SCALE
	return scale


## "Woodwork: session 5 of 8, pass chance 71%", for the inspector.
func summary(person: Person) -> String:
	var course := course_of(person)
	if course == null:
		var passed_names := PackedStringArray()
		for id: StringName in PrisonerFile.of(person).passed:
			var done := def(id)
			passed_names.append(done.display_name if done != null else String(id))
		return "Passed %s" % ", ".join(passed_names) if not passed_names.is_empty() else ""
	return "%s: session %d of %d, pass chance %d%%" % [course.display_name, mini(attended(person) + 1, course.sessions),
			course.sessions, roundi(pass_chance(person, course) * 100.0)]


func _today() -> int:
	return clock.day() if clock != null else 1
