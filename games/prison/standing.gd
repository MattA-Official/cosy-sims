class_name Standing
extends Node
## How the prison is doing. Each midnight it is graded from one to five
## stars on safety, wellbeing, reform and money together, and can't run
## more than two stars ahead of the weakest of them; a better grade
## means a bigger daily grant and a bigger intake. With a warden in the
## office there are grant goals to work towards, a few at a time, and a
## daily report each morning.

signal report_ready(text: String)
signal goal_done(goal: Goal)

const REPORT_HOUR := 6
## Grant goals shown at once.
const GOALS_SHOWN := 3
const MEASURES: Array[String] = ["Safety", "Wellbeing", "Reform", "Money"]
## The grade is at most the lowest measure plus this.
const SPREAD := 2
const HISTORY_NIGHTS := 7
## Days of money the Money measure looks back over.
const MONEY_DAYS := 3
## The Money value for being in debt: below every line.
const IN_DEBT := -1e12

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
## Optional: for the Reform measure. Without them, the share of prisoners
## on work programmes stands in.
var reform: Reform
var release: Release
## The measures, in order.
var measure_defs: Array[MeasureDef] = [
	preload("res://games/prison/catalogue/measure_safety.tres"),
	preload("res://games/prison/catalogue/measure_wellbeing.tres"),
	preload("res://games/prison/catalogue/measure_reform.tres"),
	preload("res://games/prison/catalogue/measure_money.tres"),
]
## Each measure's value tonight, by name: () -> [value, why], such as
## [52.0, "average mood 52"]. Filled in with the prison's own at start.
var measure_value: Dictionary[String, Callable] = {}
var prisoner_group: StringName = &"prisoner"
## Run at midnight before grading, such as a day served and the night's
## reform.
var nightly: Array[Callable] = []
## () -> Array[String]: more lines for the morning report, such as who
## went home.
var report_lines: Array[Callable] = []
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
## Each measure's value and why line as of last midnight, by name.
var values: Dictionary[String, float] = {}
var why: Dictionary[String, String] = {}
## The measure holding the grade down, or "".
var held_by := ""
## The last few nights, oldest first: {day, grade, stars, values}.
var history: Array[Dictionary] = []
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
	var defaults: Dictionary[String, Callable] = {"Safety": _safety, "Wellbeing": _wellbeing,
			"Reform": _reform, "Money": _money}
	for measure: String in defaults:
		if not measure_value.has(measure):
			measure_value[measure] = defaults[measure]
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
	values.assign(saved.get("values", {}))
	why.assign(saved.get("why", {}))
	held_by = saved.get("held_by", "")
	history.assign(saved.get("history", []))
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
	var weighted := 0.0
	var weights := 0.0
	var lowest := 6
	var lowest_name := ""
	for def in measure_defs:
		var got: Array = measure_value[def.display_name].call()
		values[def.display_name] = got[0]
		why[def.display_name] = got[1]
		var stars := def.stars(got[0])
		measures[def.display_name] = stars
		weighted += stars * def.weight
		weights += def.weight
		if stars < lowest:
			lowest = stars
			lowest_name = def.display_name
	if security != null:
		security.end_day()
	var mean := clampi(roundi(weighted / maxf(weights, 0.001)), 1, 5)
	grade = mini(mean, lowest + SPREAD)
	held_by = lowest_name if grade < mean else ""
	history.append({"day": clock.day() - 1 if clock != null else 0, "grade": grade,
			"stars": measures.duplicate(), "values": values.duplicate()})
	if history.size() > HISTORY_NIGHTS:
		history = history.slice(history.size() - HISTORY_NIGHTS)
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
	if not held_by.is_empty():
		lines.append("Held to %d★ by %s." % [grade, held_by])
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
	for more in report_lines:
		for line: String in more.call():
			lines.append(line)
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


## Incident points per ten prisoners today, from Security; without it,
## prisoners walked back.
func _safety() -> Array:
	var prisoners := maxi(_prisoners(), 1)
	if security != null:
		var per_ten := Security.points(security.today) * 10.0 / prisoners
		return [per_ten, "%.1f incident points per 10 prisoners" % per_ten]
	var walked: int = _moodlets.get(&"walked_back", 0)
	return [walked * 10.0 / prisoners, "%d walked back" % walked]


func _wellbeing() -> Array:
	var mood := _average_mood()
	return [mood, "average mood %d" % roundi(mood)]


## Half average reform, half the share of this week's leavers who went
## home reformed (those who came back count again, as not reformed).
func _reform() -> Array:
	if reform == null:
		var working := people.people.filter(func(p: Person) -> bool:
			return p.group == prisoner_group and p.programme != &"").size()
		var share := float(working) / maxi(_prisoners(), 1)
		return [share, "%d%% on work programmes" % roundi(share * 100.0)]
	var average := reform.average()
	var week: Dictionary = release.week() if release != null else {"left": 0, "reformed": 0, "back": 0}
	var leavers: int = week.left + week.back
	if leavers == 0:
		return [average / 100.0, "average %d, nobody went home this week" % roundi(average)]
	var share := float(week.reformed) / leavers
	return [0.5 * average / 100.0 + 0.5 * share, "average %d, %d of %d leavers reformed" % [roundi(average),
			week.reformed, leavers]]


## In debt is one star; otherwise the last few days' takings.
func _money() -> Array:
	if ledger.balance < 0 and not ledger.sandbox:
		return [IN_DEBT, "in debt"]
	var net := Ledger.total(ledger.yesterday)
	var days := 1
	if ledger.closing.size() >= 2:
		var back := mini(MONEY_DAYS, ledger.closing.size() - 1)
		net = ledger.closing[-1] - ledger.closing[-1 - back]
		days = back
	return [float(net), "%s%s over the last %s" % ["+" if net > 0 else "", Ledger.text(net),
			"day" if days == 1 else "%d days" % days]]


func _apply() -> void:
	finances.grant_scale = 0.8 + 0.1 * (grade - 1)
	intake.max_limit = 2 + grade * 2
	intake.limit = mini(intake.limit, intake.max_limit)


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

