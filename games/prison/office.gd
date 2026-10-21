class_name Office
extends Node
## The warden's office. A warden on the staff and an office with a desk to
## work at unlock the intake settings, grant goals and the daily report.
## Everyone who works at a desk (the warden and the department heads) has
## a job to sit at it, working through their pile of desk work (DeskWork)
## while on shift.

const OFFICE := &"office"
const DESKS: Array[StringName] = [&"office_desk"]
const WARDEN := &"warden"
## The job kind of desk work.
const DESK_JOB := &"office"
## Game minutes at the desk before the job comes round again, when they
## may take a break.
const DESK_MINUTES := 120.0
## Shortest sit for a small pile.
const LEAST_MINUTES := 15.0
## Roles who work everyone's paperwork rather than a pile of their own.
const CLERKS: Array[StringName] = [&"clerk"]
## How much faster a clerk with their perk works.
const SKILLED_CLERK := 1.25
## Desk work speed for each point of office quality.
const OFFICE_QUALITY := 0.03

var people: People
var claims: Claims
var jobs: JobBoard
var building: Building
var shifts: Shifts
## Optional: whose pile is whose, and the piles.
var roster: StaffRoster
var desk_work: DeskWork
## Paper stacks for the size of someone's pile (see pile_dressing).
var stacks: Array[ObjectDef] = [preload("res://games/prison/catalogue/paper_stack_small.tres"),
		preload("res://games/prison/catalogue/paper_stack_tall.tres"),
		preload("res://games/prison/catalogue/paper_stack_teetering.tres")]
var clock: GameClock:
	set(value):
		clock = value
		clock.minute_passed.connect(func(_minute: int) -> void: _man_desks())


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


## The desk the warden works at: the one they've claimed, or else any
## office desk.
func warden_desk() -> Array[Vector2i]:
	for person in people.people:
		if person.role == WARDEN:
			return desk_for(person)
	return office_desk()


## Someone's desk: the one they've claimed, or for the warden any office
## desk. Empty for none.
func desk_for(person: Person) -> Array[Vector2i]:
	if claims != null and claims.claim_of(person) != Person.NO_OBJECT:
		return [claims.claim_of(person)]
	return office_desk() if person.role == WARDEN else []


## How much desk work someone gets through a minute at their desk: morale,
## a clerk's perk, and how nice their office is (OFFICE_QUALITY a point of
## room quality). Their level and work traits already make the minutes go
## quicker (StaffRoster.pace).
func desk_speed(record: StaffRoster.Record, desk: Array[Vector2i] = []) -> float:
	if record == null:
		return 1.0
	var speed := 0.8 if record.morale < 30.0 else 1.1 if record.morale > 70.0 else 1.0
	if not desk.is_empty():
		speed *= office_factor(desk[0])
	if CLERKS.has(record.role) and roster != null and roster.has_perk(record):
		speed *= SKILLED_CLERK
	return speed


## How much an office's quality speeds desk work at a desk in it.
func office_factor(desk: Vector2i) -> float:
	var placed := building.object_at(desk)
	if placed == null or not building.levels.has(desk.x):
		return 1.0
	var room := building.levels[desk.x].room_at(Vector2i(placed.centre.floor()))
	if room == null:
		return 1.0
	return clampf(1.0 + OFFICE_QUALITY * people.quality(desk.x, room).score, 0.7, 1.3)


## Minutes of desk work waiting for someone (the shared pile for clerks),
## or -1 for someone with no desk work.
func desk_minutes(person: Person) -> float:
	var record := roster.record_of(person) if roster != null else null
	if desk_work == null or (record == null and not CLERKS.has(person.role)):
		return -1.0
	if CLERKS.has(person.role):
		return desk_work.all_paperwork()
	return desk_work.pile_minutes(record.id)


func desk_overloaded(person: Person) -> bool:
	var record := roster.record_of(person) if roster != null else null
	if desk_work == null:
		return false
	if CLERKS.has(person.role):
		return desk_work.all_paperwork() > DeskWork.OVERLOAD
	return record != null and desk_work.is_overloaded(record.id)


## The paper stack on someone's desk: none for an empty pile, small under
## DeskWork.CLEAR minutes, tall up to DeskWork.OVERLOAD, teetering when
## overloaded. Clerks show the shared pile.
func pile_dressing(person: Person) -> Array:
	var record := roster.record_of(person) if roster != null else null
	if desk_work == null or (record == null and not CLERKS.has(person.role)):
		return []
	var owner := DeskWork.SHARED if CLERKS.has(person.role) else record.id
	var minutes := desk_work.all_paperwork() if CLERKS.has(person.role) else desk_work.pile_minutes(owner)
	if minutes <= 0.0:
		return []
	if desk_work.is_overloaded(owner):
		return [stacks[2]]
	return [stacks[0] if minutes < DeskWork.CLEAR else stacks[1]]


## Words about someone's desk work, for the inspector, or "".
func pile_words(person: Person) -> String:
	var record := roster.record_of(person) if roster != null else null
	if desk_work == null or record == null or not desk_workers().has(person) or CLERKS.has(person.role):
		return ""
	var parts := PackedStringArray()
	for kind in DeskWork.ORDER:
		var minutes := desk_work.pile_minutes(record.id, kind)
		if minutes > 0.0:
			parts.append("%s %d" % [String(kind), ceili(minutes)])
	var total := desk_work.pile_minutes(record.id)
	if total <= 0.0:
		return "Desk work: all done"
	return "Desk work: %d minutes (%s), %s%s" % [ceili(total), ", ".join(parts), DeskWork.time_text(total),
			"; overloaded, so their bonus is halved" if desk_work.is_overloaded(record.id) else ""]


## Staff on site whose role works at a desk.
func desk_workers() -> Array[Person]:
	var out: Array[Person] = []
	for person in people.people:
		if person.role.is_empty() or person.going_home:
			continue
		var role: StaffRoleDef = claims.roles.get(person.role) if claims != null else null
		if (role != null and role.job_kinds.has(DESK_JOB)) or person.role == WARDEN:
			out.append(person)
	return out


## Keeps a job on the board for each desk worker to sit at their desk.
func _man_desks() -> void:
	var workers := desk_workers()
	var covered: Array[Person] = []
	for job in jobs.of_kind(DESK_JOB):
		var who := job.only_for
		var stage := job.stages[0]
		var desk := desk_for(who) if who != null else ([] as Array[Vector2i])
		if who == null or not workers.has(who) or desk.is_empty() or Vector2i(stage.level, stage.object) != desk[0]:
			jobs.cancel(job)
		else:
			covered.append(who)
	for person in workers:
		if not covered.has(person):
			_post_desk_job(person)


func _post_desk_job(person: Person) -> void:
	var desk := desk_for(person)
	if desk.is_empty():
		return
	var record := roster.record_of(person) if roster != null else null
	var speed := desk_speed(record, desk)
	var clerk := CLERKS.has(person.role)
	var pile := 0.0
	if desk_work != null:
		pile = desk_work.all_paperwork() if clerk else desk_work.pile_minutes(record.id) if record != null else 0.0
	var job := Job.new()
	job.kind = DESK_JOB
	job.only_for = person
	job.title = "Desk work" if person.role != WARDEN else "Run the prison"
	job.priority = 2
	var sit := Job.at(Job.Do.WORK, desk[0].x, desk[0].y)
	sit.minutes = clampf(pile / speed, LEAST_MINUTES, DESK_MINUTES) if pile > 0.0 else DESK_MINUTES
	sit.doing = _doing(record, person)
	if clerk and desk_work != null:
		sit.finish = func(stage: Job.Stage, _worker: Person) -> void:
			desk_work.work_paperwork(stage.minutes * speed)
	elif record != null and desk_work != null:
		var owner := record.id
		sit.finish = func(stage: Job.Stage, _worker: Person) -> void:
			desk_work.work(owner, stage.minutes * speed)
	job.stages = [sit]
	jobs.post(job)


func _doing(record: StaffRoster.Record, person: Person) -> String:
	if CLERKS.has(person.role):
		return "Doing the paperwork" if desk_work != null and desk_work.all_paperwork() > 0.0 else "Filing"
	if record != null and desk_work != null:
		var pile: Array = desk_work.piles.get(record.id, [])
		if not pile.is_empty():
			var top: DeskWork.Item = pile[0]
			return top.title if top.kind != &"paperwork" else "Doing the paperwork"
	return "Running the prison" if person.role == WARDEN else "Planning"
