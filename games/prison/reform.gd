class_name Reform
extends Node
## How far each prisoner has come, from 0 to 100 (see Progress). Good days,
## a nice cell, work, classes, therapy and word from home lift it; bad days
## pull it down harder. At 60 a prisoner counts as reformed: they're likelier
## to get parole, earn a bonus when they leave and less likely to come back.

## Reform at which someone counts as reformed.
const REFORMED_LINE := 60.0
## Mood at or over which a day without trouble is a good day, and under
## which any day is a bad one.
const GOOD_MOOD := 50.0
const BAD_MOOD := 30.0
## Good days in a row before the streak counts.
const STREAK_DAYS := 3
## Cell stars for the nice cell bonus.
const NICE_CELL_STARS := 3.0
## Losses on harder difficulties scale by this.
var loss_scale := 1.0

var people: People
var jobs: JobBoard
var progress: Progress
var prisoner_group: StringName = &"prisoner"
var clock: GameClock


func start() -> void:
	jobs.job_finished.connect(_on_job_finished)
	people.pace_scales.append(_skill_pace)


func value(person: Person) -> float:
	return progress.value(person)


func is_reformed(person: Person) -> bool:
	return value(person) >= REFORMED_LINE


## Good and bad days, streaks and the nice cell bonus for the day just
## gone, then a fresh day's caps. Called at midnight, before grading.
func grade_night() -> void:
	var day := (clock.day() if clock != null else 1) - 1
	var prisoners := _prisoners()
	for person in prisoners:
		var trouble := person.record.any(func(entry: Array) -> bool: return entry[0] == day)
		if person.mood < BAD_MOOD or trouble:
			_lose(person, &"bad_day")
			person.profile["good_streak"] = 0
		elif person.mood >= GOOD_MOOD:
			progress.add(person, &"good_day")
			var streak: int = person.profile.get("good_streak", 0) + 1
			person.profile["good_streak"] = streak
			if streak >= STREAK_DAYS:
				progress.add(person, &"good_streak")
		var home := people.home_room(person)
		if not home.is_empty() and people.quality(home[0], home[1]).stars() >= NICE_CELL_STARS:
			progress.add(person, &"good_cell")
	progress.new_day(prisoners)


## Takes a source's amount off, scaled by difficulty.
func _lose(person: Person, source_id: StringName) -> void:
	progress.add(person, source_id, loss_scale)


## "Reform 42 (+4 today: Good day +2, Work +2)"
func summary(person: Person) -> String:
	var today := progress.today_text(person)
	return "Reform %d%s" % [roundi(value(person)), " (%s)" % today if not today.is_empty() else ""]


func average() -> float:
	var prisoners := _prisoners()
	if prisoners.is_empty():
		return 0.0
	var sum := 0.0
	for person in prisoners:
		sum += value(person)
	return sum / prisoners.size()


## Share of prisoners over the reformed line.
func share_reformed() -> float:
	var prisoners := _prisoners()
	if prisoners.is_empty():
		return 0.0
	return float(prisoners.filter(is_reformed).size()) / prisoners.size()


## A work programme job done: a little reform and a little skill.
func _on_job_finished(job: Job, worker: Person) -> void:
	if worker == null or worker.group != prisoner_group or worker.programme == &"":
		return
	var programme: WorkProgrammeDef = jobs.programmes.get(worker.programme)
	if not job.programmes.has(worker.programme) and (programme == null or not programme.job_kinds.has(job.kind)):
		return
	progress.add(worker, &"work_shift")
	if programme != null and programme.skill != &"":
		PrisonerFile.of(worker).raise_skill(programme.skill, programme.skill_per_job)


## Skilled workers are quicker: half as fast again at 100.
func _skill_pace(person: Person) -> float:
	if person.programme == &"" or person.job == null:
		return 1.0
	var programme: WorkProgrammeDef = jobs.programmes.get(person.programme)
	if programme == null or programme.skill == &"":
		return 1.0
	return 1.0 + PrisonerFile.of(person).skill(programme.skill) / 200.0


func _prisoners() -> Array[Person]:
	var out: Array[Person] = []
	for person in people.people:
		if person.group == prisoner_group:
			out.append(person)
	return out
