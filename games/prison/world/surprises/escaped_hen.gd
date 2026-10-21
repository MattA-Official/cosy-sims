extends Surprise
## A hen from the farm next door gets in and runs about. Guards chase it as
## a job; prisoners who see it have a good laugh. Two hens when hard.

const HEN := &"hen"
const CHASE := &"hen_chase"
const CHASE_MINUTES := 4.0
## How close a guard must get to catch it, and the tries before it's
## cornered anyway.
const CATCH_REACH := 2.0
const TRIES := 3
const LAUGH_REACH := 4.0
const LAUGH := &"laughed"

var _hour := 0.0


func start() -> void:
	var animals: Animals = main.animals
	var def := animals.def_by_id(HEN)
	var spot: Array = (main.shifts as Shifts).entrance
	if def == null or spot.is_empty():
		minutes_left = 0.0
		return
	for i in 2 if hard else 1:
		var hen := animals.add(def, spot[0], spot[1] + Vector2(0.4 * i, 0.3))
		if hen != null:
			hen.activity = "Running about"
	(main.reputation as Reputation).report(&"hen")


func hens() -> Array[Person]:
	return (main.animals as Animals).of_kind(HEN)


func tick(minutes: float) -> void:
	var loose := hens()
	if loose.is_empty():
		minutes_left = 0.0
		return
	var jobs: JobBoard = main.jobs
	for hen in loose:
		if not jobs.of_kind(CHASE).any(func(j: Job) -> bool: return j.get_meta(&"hen", null) == hen):
			jobs.post(chase_job(hen))
	_hour += minutes
	if _hour >= 60.0:
		_hour = 0.0
		laugh()


## Prisoners near a hen laugh at it.
func laugh() -> void:
	var people: People = main.people
	for hen in hens():
		for person in people.nearby(hen, LAUGH_REACH):
			if person.group == &"prisoner":
				people.add_moodlet(person, LAUGH)


## A guard goes to where the hen is; if it's still there, it's caught.
func chase_job(hen: Person) -> Job:
	var job := Job.new()
	job.kind = CHASE
	job.title = "Catch the hen"
	job.roles = [&"guard"]
	job.priority = 4
	job.any_time = true
	job.set_meta(&"hen", hen)
	var stage := Job.on_tile(Job.Do.WORK, hen.level, Vector2i(hen.flat().floor()))
	stage.minutes = CHASE_MINUTES
	stage.doing = "Chasing the hen"
	stage.finish = func(_stage: Job.Stage, worker: Person) -> void:
		var tries := int(hen.profile.get("tries", 0)) + 1
		hen.profile["tries"] = tries
		if worker == null or tries >= TRIES or (worker.level == hen.level and worker.flat().distance_to(hen.flat()) <= CATCH_REACH):
			catch(hen)
	job.stages = [stage]
	return job


## The hen goes back over the fence to the farm.
func catch(hen: Person) -> void:
	var people: People = main.people
	if people.people.has(hen):
		people.remove_person(hen)
	var jobs: JobBoard = main.jobs
	for job in jobs.of_kind(CHASE):
		if job.get_meta(&"hen", null) == hen:
			jobs.cancel(job)
	if hens().is_empty():
		minutes_left = 0.0


func finish() -> void:
	for hen in hens():
		catch(hen)
	var jobs: JobBoard = main.jobs
	for job in jobs.of_kind(CHASE):
		jobs.cancel(job)


func words() -> String:
	var count := hens().size()
	return "%d hen%s loose" % [count, "" if count == 1 else "s"] if count > 0 else "Caught"
