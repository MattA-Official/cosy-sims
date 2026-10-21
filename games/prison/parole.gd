class_name Parole
extends Node
## Parole hearings. From part-way through their sentence (see Sentences) a
## prisoner with a clean few days may go before the warden. At 13:00 the
## day's list is drawn up, most reformed first; from 14:00 the warden hears
## each case at the office desk. The chance of release rises with reform,
## courses passed and a good skill, and falls with recent trouble. Granted,
## they go home tomorrow; refused, they wait a few days to try again. The
## player can hold someone back, but not push them forward.

signal heard(person: Person, granted: bool)

const PLAN_HOUR := 13
const HEARING_HOUR := 14
const HEARINGS_PER_DAY := 4
const HEARING_MINUTES := 20.0
## Days between hearings for the same prisoner.
const RETRY_DAYS := 3
## Days without misconduct before they're put forward.
const CLEAN_DAYS := 3
## Not worth a hearing this close to going home anyway.
const SOON_DAYS := 2
## The chance: a base, then per reform point, per course passed (up to
## three), for a skill of 50 or more, less per misconduct in the last week
## (up to three) and for high security.
const BASE := 0.08
const PER_REFORM := 0.006
const PER_COURSE := 0.08
const MAX_COURSES := 3
const SKILLED := 0.08
const SKILLED_AT := 50
const PER_MISCONDUCT := 0.1
const MAX_MISCONDUCT := 3
const HIGH_SECURITY := 0.1
const LEAST := 0.02
const MOST := 0.9
const GRANTED := &"parole_granted"
const REFUSED := &"parole_refused"

var people: People
var office: Office
var jobs: JobBoard
var reform: Reform
var prisoner_group: StringName = &"prisoner"
## Flat change to every chance, from difficulty.
var chance_shift := 0.0
## When set, its operation times are used instead of the hour above (main
## passes on Regime.operation_due).
var regime: Regime
var clock: GameClock:
	set(value):
		clock = value
		clock.hour_changed.connect(_on_hour)

## Today's hearings still to hold, in order.
var queue: Array[Person] = []
## Today's and yesterday's results, as [name, granted].
var today: Array = []
var yesterday: Array = []
## Hearings granted since the start, for goals.
var granted_total := 0
var _rng := RandomNumberGenerator.new()


## Whether someone may go before a hearing today, and if not, why.
func why_not(person: Person) -> String:
	var file := PrisonerFile.of(person)
	var day := _day()
	if not file.has_sentence() or file.due_out:
		return "Going home anyway"
	if MissingFiles.is_missing(person):
		return "Awaiting paperwork"
	if day < file.parole_from_day:
		return "Not until day %d" % file.parole_from_day
	if day < person.profile.get("parole_next", 0):
		return "Next hearing day %d" % person.profile["parole_next"]
	if file.release_day - day <= SOON_DAYS:
		return "Out in a day or two anyway"
	if person.profile.get("parole_held_back", false):
		return "Held back"
	if _misconduct(person, CLEAN_DAYS) > 0:
		return "Needs %d clean days" % CLEAN_DAYS
	return ""


func eligible(person: Person) -> bool:
	return person.group == prisoner_group and why_not(person).is_empty()


## Draws up today's list: the most reformed first.
func plan_day() -> void:
	var list: Array[Person] = []
	for person in people.people:
		if eligible(person):
			list.append(person)
	list.sort_custom(func(a: Person, b: Person) -> bool:
		var a_first: bool = a.profile.get("parole_missed", false)
		var b_first: bool = b.profile.get("parole_missed", false)
		if a_first != b_first:
			return a_first
		return reform.value(a) > reform.value(b))
	queue = list.slice(0, HEARINGS_PER_DAY)
	for person in queue:
		person.profile.erase("parole_missed")
		person.bubble = "Parole hearing this afternoon!"
		person.bubble_minutes = 60.0


## The chance a hearing grants parole now, and what makes it up, as
## [chance, [[words, amount], ...]].
func chance(person: Person) -> Array:
	var file := PrisonerFile.of(person)
	var parts: Array = []
	var value := reform.value(person)
	parts.append(["Reform %d" % roundi(value), value * PER_REFORM])
	var courses := mini(file.passed.size(), MAX_COURSES)
	if courses > 0:
		parts.append(["%d %s passed" % [courses, "course" if courses == 1 else "courses"], courses * PER_COURSE])
	var best := file.best_skill()
	if best != &"" and file.skill(best) >= SKILLED_AT:
		parts.append(["Good at %s" % best, SKILLED])
	var trouble := mini(_misconduct(person, 7), MAX_MISCONDUCT)
	if trouble > 0:
		parts.append(["Trouble this week", -trouble * PER_MISCONDUCT])
	if person.category == &"high":
		parts.append(["High security", -HIGH_SECURITY])
	if not is_zero_approx(chance_shift):
		parts.append(["Difficulty", chance_shift])
	var sum := BASE
	for part: Array in parts:
		sum += part[1]
	return [clampf(sum, LEAST, MOST), parts]


## Hears a case and decides it. `roll` is for tests. Returns whether
## parole was granted.
func hear(person: Person, roll := -1.0) -> bool:
	queue.erase(person)
	var file := PrisonerFile.of(person)
	var p: float = chance(person)[0]
	var granted := (roll if roll >= 0.0 else _rng.randf()) < p
	person.profile["parole_hearings"] = person.profile.get("parole_hearings", 0) + 1
	if granted:
		file.release_day = _day() + 1
		person.profile["paroled"] = true
		people.add_moodlet(person, GRANTED)
		file.add_log(_day(), "Granted parole")
		person.bubble = "Parole! Home tomorrow!"
		granted_total += 1
	else:
		person.profile["parole_next"] = _day() + RETRY_DAYS
		people.add_moodlet(person, REFUSED)
		file.add_log(_day(), "Refused parole")
		person.bubble = "Parole refused..."
	person.bubble_minutes = 60.0
	today.append([person.name, granted])
	heard.emit(person, granted)
	return granted


## "Parole from day 5 · chance 48% (Reform 42 +25%, 1 course passed +8%)"
func summary(person: Person) -> String:
	var file := PrisonerFile.of(person)
	if not file.has_sentence() or file.due_out:
		return ""
	var reason := why_not(person)
	var result := chance(person)
	var parts := PackedStringArray()
	for part: Array in result[1]:
		parts.append("%s %+d%%" % [part[0], roundi(part[1] * 100.0)])
	return "Parole: %s%d%% chance (%s)" % ["%s · " % reason if not reason.is_empty() else "",
			roundi(result[0] * 100.0), ", ".join(parts)]


func _on_hour(hour: int) -> void:
	if hour == 0:
		yesterday = today
		today = []
		for person in queue:
			person.profile["parole_missed"] = true
		queue.clear()
	elif hour == PLAN_HOUR and regime == null:
		plan_day()
	elif hour == HEARING_HOUR and regime == null:
		_post_hearing()


## Puts the next hearing on the board for the warden, at their desk.
func _post_hearing() -> void:
	queue = queue.filter(func(p: Person) -> bool: return people.people.has(p) and eligible(p))
	if queue.is_empty() or not office.has_warden() or not jobs.of_kind(&"parole").is_empty():
		return
	var desk := office.warden_desk()
	if desk.is_empty():
		return
	var person: Person = queue[0]
	var job := Job.new()
	job.kind = &"parole"
	job.title = "Hear %s's parole case" % person.name.get_slice(" ", 0)
	job.roles = [Office.WARDEN]
	job.priority = 4
	var stage := Job.at(Job.Do.WORK, desk[0].x, desk[0].y)
	stage.minutes = HEARING_MINUTES
	stage.doing = "Hearing a parole case"
	stage.finish = func(_stage: Job.Stage, _worker: Person) -> void:
		if people.people.has(person) and queue.has(person):
			hear(person)
	job.stages = [stage]
	job.on_done = func(_job: Job) -> void: _post_hearing.call_deferred()
	jobs.post(job)


## Misconduct on their record in the last `days` days.
func _misconduct(person: Person, days: int) -> int:
	var since := _day() - days
	return person.record.filter(func(entry: Array) -> bool: return entry[0] > since).size()


func _day() -> int:
	return clock.day() if clock != null else 1
