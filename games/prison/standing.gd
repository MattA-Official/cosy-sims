class_name Standing
extends Node
## How the prison is doing. Each midnight it is graded from one to five
## stars on safety, wellbeing, reform and money together; a better grade
## means a bigger daily grant and a bigger intake. With a warden in the
## office there are grant goals to work towards, a few at a time, and a
## daily report each morning.

signal report_ready(text: String)
signal goal_done(goal: Goal)

const REPORT_HOUR := 6
## Grant goals shown at once.
const GOALS_SHOWN := 3
const MEASURES: Array[String] = ["Safety", "Wellbeing", "Reform", "Money"]

## A grant goal: done when `check` says so, paying `grant`.
class Goal:
	var title: String
	var grant: int
	## () -> bool
	var check: Callable
	## () -> String, such as "7 of 12". Optional.
	var progress: Callable
	var done := false

	func _init(goal_title: String, goal_grant: int, goal_check: Callable, goal_progress := Callable()) -> void:
		title = goal_title
		grant = goal_grant
		check = goal_check
		progress = goal_progress


var people: People
var ledger: Ledger
var office: Office
var intake: Intake
var finances: Finances
var building: Building
var workshop: Workshop
## Optional: incidents, for the Safety grade. Without it, Safety goes by
## how many prisoners were walked back.
var security: Security
var prisoner_group: StringName = &"prisoner"
## Run at midnight before grading, such as a day served and the night's
## reform.
var nightly: Array[Callable] = []
var clock: GameClock:
	set(value):
		clock = value
		clock.hour_changed.connect(_on_hour)
		clock.day_changed.connect(func(_day: int) -> void: grade_day())

## Stars, 1 to 5, as of last midnight; 3 before the first.
var grade := 3
## Each measure's stars, by name, as of last midnight.
var measures: Dictionary[String, int] = {}
var goals: Array[Goal] = []
## The last daily report, or "".
var report := ""

## Today so far: moodlets given out, by id, and arrivals.
var _moodlets: Dictionary[StringName, int] = {}
var _arrivals := 0
## Yesterday's, for the report.
var _yesterday_moodlets: Dictionary[StringName, int] = {}
var _yesterday_arrivals := 0
var _rng := RandomNumberGenerator.new()
var _graded := false


func start() -> void:
	people.moodlet_added.connect(func(_person: Person, id: StringName) -> void:
		_moodlets[id] = _moodlets.get(id, 0) + 1)
	intake.arrived.connect(func(came: Array[Person]) -> void: _arrivals += came.size())
	for measure in MEASURES:
		measures[measure] = 3
	_apply()
	goals = [
		Goal.new("House 12 prisoners", 1000, func() -> bool: return _prisoners() >= 12,
				func() -> String: return "%d of 12" % _prisoners()),
		Goal.new("Open a workshop", 1500, func() -> bool: return _has_room(&"workshop"),
				Callable()),
		Goal.new("Sell 20 goods from the workshop", 1000, func() -> bool: return workshop.sold >= 20,
				func() -> String: return "%d of 20" % workshop.sold),
		Goal.new("Reach a three-star grade", 2000, func() -> bool: return grade >= 3 and measures_known(),
				Callable()),
		Goal.new("House 20 prisoners", 2500, func() -> bool: return _prisoners() >= 20,
				func() -> String: return "%d of 20" % _prisoners()),
		Goal.new("Keep average mood over 60 at midnight", 2000,
				func() -> bool: return measures_known() and _average_mood() > 60.0,
				func() -> String: return "now %d" % roundi(_average_mood())),
		Goal.new("Reach a four-star grade", 4000, func() -> bool: return grade >= 4 and measures_known(),
				Callable()),
	]


## Puts back the grade and goals from a save.
func restore(saved: Dictionary) -> void:
	grade = saved.get("grade", grade)
	measures.assign(saved.get("measures", measures))
	report = saved.get("report", "")
	_graded = saved.get("graded", false)
	var done: Array = saved.get("goals_done", [])
	for goal in goals:
		goal.done = done.has(goal.title)
	_apply()


## Goals being worked towards now: the first few not done.
func current_goals() -> Array[Goal]:
	var out: Array[Goal] = []
	for goal in goals:
		if not goal.done:
			out.append(goal)
		if out.size() == GOALS_SHOWN:
			break
	return out


## Whether the prison has been graded on a real day yet.
func measures_known() -> bool:
	return _graded


## Pays out any goal done, if a warden is here to claim it.
func check_goals() -> Array[Goal]:
	var finished: Array[Goal] = []
	if not office.has_warden():
		return finished
	for goal in current_goals():
		if goal.check.call():
			goal.done = true
			ledger.add(goal.grant, "Grants")
			finished.append(goal)
			goal_done.emit(goal)
	return finished


## Grades the day just gone. Called at midnight.
func grade_day() -> void:
	for step in nightly:
		step.call()
	_graded = true
	var prisoners := maxi(_prisoners(), 1)
	var walked_back: int = _moodlets.get(&"walked_back", 0)
	if security != null:
		measures["Safety"] = Security.safety_stars(security.today, prisoners)
		security.end_day()
	else:
		measures["Safety"] = _stars(1.0 - float(walked_back) / prisoners, [0.5, 0.75, 0.9, 1.0])
	measures["Wellbeing"] = _stars(_average_mood(), [30.0, 45.0, 60.0, 75.0])
	# Until classes and parole come, work programmes stand in for reform.
	var working := people.people.filter(func(p: Person) -> bool:
		return p.group == prisoner_group and p.programme != &"").size()
	measures["Reform"] = _stars(float(working) / prisoners, [0.01, 0.2, 0.4, 0.6])
	var day_total := Ledger.total(ledger.yesterday)
	measures["Money"] = 1 if ledger.balance < 0 and not ledger.sandbox else (5 if day_total > 0 else (4 if day_total >= -100 else 3))
	var sum := 0
	for measure: String in measures:
		sum += measures[measure]
	grade = clampi(roundi(float(sum) / measures.size()), 1, 5)
	_apply()
	_yesterday_moodlets = _moodlets
	_yesterday_arrivals = _arrivals
	_moodlets = {}
	_arrivals = 0
	check_goals()


## The morning paper: yesterday in a few lines.
func write_report() -> String:
	var lines := PackedStringArray()
	lines.append("%s  %d-star prison" % ["★".repeat(grade) + "☆".repeat(5 - grade), grade])
	var good: int = _yesterday_moodlets.get(&"good_meal", 0) + _yesterday_moodlets.get(&"lovely_meal", 0)
	var missed: int = _yesterday_moodlets.get(&"missed_meal", 0)
	lines.append("%d good meals, %d missed." % [good, missed])
	if _yesterday_arrivals > 0:
		lines.append("%d new %s arrived." % [_yesterday_arrivals, "prisoner" if _yesterday_arrivals == 1 else "prisoners"])
	var walked: int = _yesterday_moodlets.get(&"walked_back", 0)
	if walked > 0:
		lines.append("Guards walked back %d %s." % [walked, "prisoner" if walked == 1 else "prisoners"])
	if security != null:
		var incidents := PackedStringArray()
		for kind: StringName in Security.NAMES:
			if kind != &"walk_back" and security.yesterday.get(kind, 0) > 0:
				incidents.append("%s %d" % [Security.NAMES[kind].to_lower(), security.yesterday[kind]])
		if not incidents.is_empty():
			lines.append("Incidents: %s." % ", ".join(incidents))
	var money := Ledger.total(ledger.yesterday)
	lines.append("Money: %s%s, balance %s." % ["+" if money > 0 else "", Ledger.text(money), Ledger.text(ledger.balance)])
	var story := _story()
	if not story.is_empty():
		lines.append(story)
	return "\n".join(lines)


func _on_hour(hour: int) -> void:
	check_goals()
	if hour == REPORT_HOUR and _graded and office.has_warden():
		report = write_report()
		report_ready.emit(report)


## A line about one prisoner's day, from a moodlet they have.
func _story() -> String:
	var stories: Dictionary[StringName, String] = {
		&"lovely_meal": "%s says yesterday's dinner was the best yet.",
		&"had_fun": "%s had a lovely time in the yard.",
		&"useful_day": "%s felt useful after a day's work.",
		&"good_chat": "%s had a good natter with a friend.",
		&"first_night": "%s is settling in after a first night inside.",
		&"slept_well": "%s slept like a log.",
	}
	var tellers: Array = []
	for person in people.people:
		if person.group != prisoner_group:
			continue
		for id: StringName in stories:
			if person.moodlets.has(id):
				tellers.append([person, id])
	if tellers.is_empty():
		return ""
	var pick: Array = tellers[_rng.randi() % tellers.size()]
	return stories[pick[1]] % (pick[0] as Person).name


func _apply() -> void:
	finances.grant_scale = 0.8 + 0.1 * (grade - 1)
	intake.max_limit = 2 + grade * 2
	intake.limit = mini(intake.limit, intake.max_limit)


## Stars for a value against the lines for 2, 3, 4 and 5 stars.
static func _stars(value: float, lines: Array) -> int:
	var stars := 1
	for line: float in lines:
		if value >= line:
			stars += 1
	return stars


func _prisoners() -> int:
	return people.people.filter(func(p: Person) -> bool: return p.group == prisoner_group).size()


func _average_mood() -> float:
	var sum := 0.0
	var count := 0
	for person in people.people:
		if person.group == prisoner_group:
			sum += person.mood
			count += 1
	return sum / count if count > 0 else 50.0


func _has_room(type: StringName) -> bool:
	for n: int in building.levels:
		for room: Room in building.levels[n].rooms():
			if room.type == type:
				return true
	return false

