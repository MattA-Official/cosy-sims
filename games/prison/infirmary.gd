class_name Infirmary
extends Node
## Getting better after a fight. Anyone hurt limps to a free infirmary bed
## and lies down; anyone knocked out lies where they fell seeing stars
## until a guard helps them there. In bed they mend slowly on their own,
## and a nurse looking after them mends them quickly. Without an
## infirmary, the hurt mend slowly wherever they are and the knocked out
## come round after a while. Nobody dies: health never falls below FLOOR.
## New arrivals have a check-up: when a nurse is on duty and a bed is
## free, they lie down for a nurse to look them over.

## Health a nurse's visit gives back, and how long it takes.
const TREAT_HEALTH := 15.0
const TREAT_MINUTES := 30.0
## Mending an hour: in bed, and up and about.
const BED_HEAL := 5.0
const SELF_HEAL := 2.0
## Lost an hour lying knocked out, down to FLOOR.
const UNTREATED_LOSS := 5.0
const FLOOR := 5.0
## Game minutes knocked out before coming round with nowhere to go.
const COME_ROUND := 60.0
## Close enough to the bed to get in, in tiles.
const BESIDE := 2.5
## Back on their feet at this.
const DISCHARGE := 90.0

## A knocked-out patient left untreated, or hit hard enough, can die.
## Off (the default), health never drops below FLOOR from neglect and
## nobody dies.
var deaths := false

signal died(person: Person, level: int, point: Vector2)
signal checked(person: Person)
## Someone was knocked out: a serious injury.
signal knocked_out(person: Person)

## Bonuses such as a department head's. Optional.
var modifiers: Modifiers
var people: People
var jobs: JobBoard
var bed_tag: StringName = &"infirmary_bed"
var clock: GameClock:
	set(value):
		clock = value
		clock.minute_passed.connect(func(_minute: int) -> void: tick(1.0))

## Patients and their beds, as (level, object id).
var beds: Dictionary[Person, Vector2i] = {}
## The knocked out being carried, and who by.
var carried: Dictionary[Person, Person] = {}
## New arrivals waiting for a check-up, and those in a bed having one.
var checkups: Array[Person] = []
var checking: Dictionary[Person, bool] = {}
var _out_for: Dictionary[Person, float] = {}


func start() -> void:
	people.deciders.push_front(_patient)
	jobs.rebuilders[&"treat"] = func(work: Dictionary) -> Job:
		var person := _patient_in(work)
		return _treat_job(person) if person != null else null
	jobs.rebuilders[&"checkup"] = jobs.rebuilders[&"treat"]
	jobs.rebuilders[&"carry_patient"] = func(work: Dictionary) -> Job:
		var person := _patient_in(work)
		return _carry_job(person) if person != null else null
	people.person_removed.connect(func(person: Person) -> void:
		beds.erase(person)
		carried.erase(person)
		checkups.erase(person)
		checking.erase(person)
		_out_for.erase(person))


## Puts arrivals on the list for a check-up.
func want_checkups(arrivals: Array[Person]) -> void:
	for person in arrivals:
		if not checkups.has(person):
			checkups.append(person)


func _start_checkups() -> void:
	if checkups.is_empty() or not nurse_on_duty():
		return
	for person: Person in checkups.duplicate():
		# Once they're through reception and have a cell.
		if beds.has(person) or people.home_room(person).is_empty():
			continue
		var bed := free_bed()
		if bed == Vector2i(-1, -1):
			return
		checkups.erase(person)
		beds[person] = bed
		checking[person] = true


func tick(minutes: float) -> void:
	_start_checkups()
	for person in people.people.duplicate():
		if person.health >= Health.WELL and not beds.has(person):
			continue
		if deaths and person.health <= 0.0:
			die(person)
			continue
		var injury := Health.injury(person.health)
		if beds.has(person) and not person.lying and injury < Health.Injury.HURT and not checking.has(person):
			beds.erase(person)
		if not beds.has(person) and injury >= Health.Injury.HURT:
			var bed := free_bed()
			if bed != Vector2i(-1, -1):
				beds[person] = bed
		if person.lying and beds.has(person):
			person.health = minf(100.0, person.health + BED_HEAL * minutes / 60.0)
			if person.health >= DISCHARGE and not checking.has(person):
				get_up(person)
			elif not _has_treat_job(person):
				_post_treat(person)
		elif injury == Health.Injury.KNOCKED_OUT:
			if not _out_for.has(person):
				knocked_out.emit(person)
			_out_for[person] = _out_for.get(person, 0.0) + minutes
			person.health = maxf(0.0 if deaths else FLOOR, person.health - UNTREATED_LOSS * minutes / 60.0)
			person.bubble = "Seeing stars"
			if beds.has(person):
				if not _being_helped(person):
					_post_carry(person)
			elif _out_for[person] >= COME_ROUND:
				person.health = Health.HURT_ABOVE + 1.0
		else:
			person.health = minf(100.0, person.health + SELF_HEAL * minutes / 60.0)
		if injury != Health.Injury.KNOCKED_OUT and _out_for.has(person):
			_out_for.erase(person)
			if person.bubble == "Seeing stars":
				person.bubble = ""


## Gone: they leave the prison for good.
func die(person: Person) -> void:
	var level := person.level
	var point := person.flat()
	beds.erase(person)
	carried.erase(person)
	_out_for.erase(person)
	people.remove_person(person)
	died.emit(person, level, point)


## An infirmary bed nobody has, as (level, object id), or (-1, -1).
func free_bed() -> Vector2i:
	for key in people.building.objects_tagged([bed_tag] as Array[StringName]):
		if not beds.values().has(key):
			return key
	return Vector2i(-1, -1)


## Out of bed and back to their day.
func get_up(person: Person) -> void:
	var spot := _bed_spot(person)
	beds.erase(person)
	person.lying = false
	if not spot.is_empty():
		person.position = Vector3(spot[1].x, person.position.y, spot[1].y)
	people.stop(person)


## Whether a nurse is at work.
func nurse_on_duty() -> bool:
	return people.people.any(func(p: Person) -> bool: return p.role == &"nurse" and not p.going_home)


## Patients go to bed and stay there; the knocked out stay put.
func _patient(person: Person, _may_wander: bool) -> bool:
	if person.lying and beds.has(person):
		person.activity = "Having a check-up" if checking.has(person) else "Getting better in the infirmary"
		return true
	var injury := Health.injury(person.health)
	# The knocked out wait to be carried.
	if beds.has(person) and injury != Health.Injury.KNOCKED_OUT:
		var key := beds[person]
		var placed: BuildingMap.PlacedObject = people.building.object_at(key)
		if placed == null:
			beds.erase(person)
		elif person.level == key.x and person.flat().distance_to(placed.centre) <= BESIDE:
			_lie_in(person, placed)
			return true
	if injury == Health.Injury.KNOCKED_OUT:
		person.activity = "Knocked out"
		return true
	if not beds.has(person) or (injury < Health.Injury.HURT and not checking.has(person)):
		return false
	var spot := _bed_spot(person)
	return not spot.is_empty() and people.walk_to(person, spot[0], spot[1],
			"Going for a check-up" if checking.has(person) else "Limping to the infirmary")


func _lie_in(person: Person, placed: BuildingMap.PlacedObject) -> void:
	people.stop(person)
	person.lying = true
	person.bubble = ""
	var map: BuildingMap = people.building.levels[beds[person].x]
	person.position = Vector3(placed.centre.x, map.floor_height(Vector2i(placed.centre.floor())) + placed.def.height,
			placed.centre.y)
	person.activity = "Getting better in the infirmary"


## Where to stand beside their bed, as [level, point], or [].
func _bed_spot(person: Person) -> Array:
	var key: Vector2i = beds.get(person, Vector2i(-1, -1))
	var placed: BuildingMap.PlacedObject = people.building.object_at(key) if key.x != -1 else null
	if placed == null:
		return []
	var spots := people.spots_beside(key.x, placed, person.flat())
	return [key.x, spots[0]] if not spots.is_empty() else []


func _being_helped(person: Person) -> bool:
	return jobs.of_kind(&"carry_patient").any(func(j: Job) -> bool: return j.get_meta(&"patient") == person)


func _patient_in(work: Dictionary) -> Person:
	var id: int = work["with"].get(&"patient", -1)
	for person in people.people:
		if person.id == id:
			return person
	return null


func _post_carry(person: Person) -> void:
	var job := _carry_job(person)
	if job != null:
		jobs.post(job)


## A guard or the nurse picks them up and carries them to their bed.
func _carry_job(person: Person) -> Job:
	var spot := _bed_spot(person)
	if spot.is_empty():
		return null
	var first := person.name.get_slice(" ", 0)
	var job := Job.new()
	job.kind = &"carry_patient"
	job.title = "Carry %s to the infirmary" % first
	job.priority = 5
	job.set_meta(&"patient", person)
	var pick_up := Job.on_tile(Job.Do.WORK, person.level, Vector2i(person.flat().floor()))
	pick_up.minutes = 1.0
	pick_up.doing = "Picking %s up" % first
	pick_up.finish = func(_stage: Job.Stage, carrier: Person) -> void:
		if people.people.has(person):
			carried[person] = carrier
	var take := Job.on_tile(Job.Do.WORK, spot[0], Vector2i(spot[1].floor()))
	take.minutes = 0.5
	take.doing = "Carrying %s to the infirmary" % first
	take.finish = func(_stage: Job.Stage, _carrier: Person) -> void:
		carried.erase(person)
		var placed: BuildingMap.PlacedObject = people.building.object_at(beds.get(person, Vector2i(-1, -1))) \
				if beds.has(person) else null
		if people.people.has(person) and placed != null:
			_lie_in(person, placed)
	job.on_done = func(_job: Job) -> void: carried.erase(person)
	job.stages = [pick_up, take]
	return job


## The carried go where their carrier goes.
func _process(_delta: float) -> void:
	for person: Person in carried.keys():
		var carrier := carried[person]
		if not people.people.has(carrier) or carrier.job == null or carrier.job.kind != &"carry_patient":
			carried.erase(person)
			continue
		person.level = carrier.level
		person.position = carrier.position + Vector3(0.0, 0.35, 0.0)


func _has_treat_job(person: Person) -> bool:
	return (jobs.of_kind(&"treat") + jobs.of_kind(&"checkup")).any(func(j: Job) -> bool:
		return j.get_meta(&"patient") == person)


func _post_treat(person: Person) -> void:
	var job := _treat_job(person)
	if job != null:
		jobs.post(job)


## A nurse comes to look after a patient in bed.
func _treat_job(person: Person) -> Job:
	var spot := _bed_spot(person)
	if spot.is_empty():
		return null
	var job := Job.new()
	var checkup := checking.has(person)
	job.kind = &"checkup" if checkup else &"treat"
	job.title = ("Check-up for %s" if checkup else "Look after %s") % person.name.get_slice(" ", 0)
	job.priority = 5
	job.set_meta(&"patient", person)
	var stage := Job.on_tile(Job.Do.WORK, spot[0], Vector2i(spot[1].floor()))
	stage.minutes = TREAT_MINUTES / Modifiers.scale(modifiers, &"treat_speed")
	stage.doing = ("Looking %s over" if checkup else "Patching up %s") % person.name.get_slice(" ", 0)
	stage.finish = func(_stage: Job.Stage, _nurse: Person) -> void:
		if not people.people.has(person):
			return
		person.health = minf(100.0, person.health + TREAT_HEALTH)
		if checking.has(person):
			checking.erase(person)
			checked.emit(person)
			get_up(person)
	job.stages = [stage]
	return job
