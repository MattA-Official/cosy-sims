class_name Standing
extends Node
## How the prison is doing. Each midnight it is graded from one to five
## stars on safety, wellbeing, reform and money together, and can't run
## more than two stars ahead of the weakest of them; a better grade
## means a bigger daily grant and a bigger intake. With a warden in the
## office there are grant goals to work towards, a few at a time, and a
## daily report each morning.

signal report_ready(text: String)
signal goal_done(goal: GoalDef)
## A fail rule ran out on a difficulty that can be lost.
signal failed(rule: FailRule)
signal difficulty_changed(def: DifficultyDef)

const REPORT_HOUR := 6
## Grant goals shown at once.
const GOALS_SHOWN := 3
const MEASURES: Array[String] = ["Safety", "Wellbeing", "Reform", "Money"]
## The grade is at most the lowest measure plus this.
const SPREAD := 2
const HISTORY_NIGHTS := 7
## The difficulty a new game starts on, once one has been picked.
static var next_difficulty: StringName = &""
const DIFFICULTIES: Array[DifficultyDef] = [
	preload("res://games/prison/catalogue/difficulty_sandbox.tres"),
	preload("res://games/prison/catalogue/difficulty_cosy.tres"),
	preload("res://games/prison/catalogue/difficulty_standard.tres"),
	preload("res://games/prison/catalogue/difficulty_tough.tres"),
]
## Days of costs the Money measure averages over.
const MONEY_DAYS := 3
## Nights each measure's stars are averaged over.
const AVERAGE_NIGHTS := 3
## The Money value for being in debt: below every line.
const IN_DEBT := -1e12

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
var goals: Array[GoalDef] = []
## Goal ids done.
var goals_done: Dictionary[StringName, bool] = {}
## Events counted for goals, such as &"parole_granted", since the start.
var counts: Dictionary[StringName, int] = {}
## (goal) -> float for goal kinds the prison adds.
var goal_kinds: Dictionary[StringName, Callable] = {}
var difficulty: DifficultyDef = preload("res://games/prison/catalogue/difficulty_standard.tres")
## Nights in a row each fail rule has held, by kind.
var fail_counts: Dictionary[StringName, int] = {}
## The Ministry's worries right now, for the report and clock bar.
var warnings: Array[String] = []
## Optional: () -> float, the longest sit-in going on now in game hours.
var longest_sit_in: Callable
## The game was lost (on a difficulty that can be).
var lost := false
## Each measure's value and why line as of last midnight, by name.
var values: Dictionary[String, float] = {}
var why: Dictionary[String, String] = {}
## The measure holding the grade down, or "".
var held_by := ""
## The last few nights, oldest first: {day, grade, stars, values}.
var history: Array[Dictionary] = []
## The last daily report, or "".
var report := ""

## Counts at the moment each counted goal came up, by goal id.
var _baselines: Dictionary[StringName, int] = {}
## Midnights in a row each held goal has been met, by goal id.
var _held: Dictionary[StringName, int] = {}
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
	for def in DIFFICULTIES:
		if def.id == next_difficulty:
			difficulty = def
	var defaults: Dictionary[String, Callable] = {"Safety": _safety, "Wellbeing": _wellbeing,
			"Reform": _reform, "Money": _money}
	for measure: String in defaults:
		if not measure_value.has(measure):
			measure_value[measure] = defaults[measure]
	_apply()
	goals.assign((preload("res://games/prison/catalogue/goals_sandbox.tres") as GoalListDef).goals)


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
	# Older saves list goals done by title.
	var done: Array = saved.get("goals_done", [])
	goals_done.clear()
	for goal in goals:
		if done.has(goal.id) or done.has(goal.title):
			goals_done[goal.id] = true
	counts.assign(saved.get("counts", {}))
	_baselines.assign(saved.get("baselines", {}))
	_held.assign(saved.get("held", {}))
	fail_counts.assign(saved.get("fail_counts", {}))
	warnings.assign(saved.get("warnings", []))
	var difficulty_id: StringName = saved.get("difficulty", difficulty.id)
	for def in DIFFICULTIES:
		if def.id == difficulty_id:
			difficulty = def
	_apply()


## Goals being worked towards now: the first few not done.
func current_goals() -> Array[GoalDef]:
	var out: Array[GoalDef] = []
	for goal in goals:
		if not goals_done.has(goal.id):
			out.append(goal)
			if goal.counted and not _baselines.has(goal.id):
				_baselines[goal.id] = counts.get(goal.kind, 0)
		if out.size() == GOALS_SHOWN:
			break
	return out


func is_done(goal: GoalDef) -> bool:
	return goals_done.has(goal.id)


## Counts something goals may ask for, such as a course passed.
func count(kind: StringName, times := 1) -> void:
	counts[kind] = counts.get(kind, 0) + times


## Where a goal stands now, in the units of its amount.
func goal_value(goal: GoalDef) -> float:
	if goal.counted:
		return counts.get(goal.kind, 0) - _baselines.get(goal.id, counts.get(goal.kind, 0))
	match goal.kind:
		&"prisoners": return _prisoners()
		&"has_room": return 1.0 if _has_room(goal.target) else 0.0
		&"goods_sold": return workshop.sold if workshop != null else 0.0
		&"grade": return grade if measures_known() else 0.0
		&"measure": return measures.get(String(goal.target), 0) if measures_known() else 0.0
		&"average_mood": return _average_mood()
	if goal_kinds.has(goal.kind):
		return goal_kinds[goal.kind].call(goal)
	return 0.0


## "7 of 12", "now 54" or "2 of 5 nights", or "" when there's nothing to
## count.
func goal_progress(goal: GoalDef) -> String:
	if goal.hold_days > 1:
		return "%d of %d nights" % [_held.get(goal.id, 0), goal.hold_days]
	if goal.kind == &"average_mood":
		return "now %d" % roundi(_average_mood())
	if goal.kind in [&"has_room", &"grade", &"measure"]:
		return ""
	return "%d of %d" % [roundi(goal_value(goal)), roundi(goal.amount)]


## Whether the game was graded on a real day yet.
func measures_known() -> bool:
	return _graded


## Pays out any goal done, if a warden is here to claim it. Goals that
## must hold for some nights are only counted at midnight.
func check_goals(midnight := false) -> Array[GoalDef]:
	var finished: Array[GoalDef] = []
	for goal in current_goals():
		if goal.hold_days > 0 and midnight:
			_held[goal.id] = _held.get(goal.id, 0) + 1 if goal_value(goal) >= goal.amount else 0
	if not office.has_warden():
		return finished
	for goal in current_goals():
		var met: bool = _held.get(goal.id, 0) >= goal.hold_days if goal.hold_days > 0 \
				else goal_value(goal) >= goal.amount
		if met:
			goals_done[goal.id] = true
			ledger.add(goal.grant, "Grants")
			finished.append(goal)
			goal_done.emit(goal)
	return finished


## Changes how kind the game is; the Ministry's counts start again.
func set_difficulty(def: DifficultyDef) -> void:
	difficulty = def
	fail_counts.clear()
	warnings.clear()
	_apply()
	difficulty_changed.emit(def)


## At midnight: counts the nights each fail rule has held, and warns or
## loses the game.
func check_fail_rules() -> void:
	warnings.clear()
	for rule in difficulty.fail_rules:
		if rule.kind == &"sit_in":
			continue
		var met := false
		match rule.kind:
			&"debt": met = ledger.balance < -rule.amount and not ledger.sandbox
			&"grade": met = float(grade) <= rule.amount
		if not met:
			fail_counts.erase(rule.kind)
			continue
		fail_counts[rule.kind] = fail_counts.get(rule.kind, 0) + 1
		_warn_or_fail(rule, rule.days - fail_counts[rule.kind])


## Hourly: a sit-in going on too long.
func _check_sit_in() -> void:
	if not longest_sit_in.is_valid():
		return
	var hours: float = longest_sit_in.call()
	for rule in difficulty.fail_rules:
		if rule.kind != &"sit_in":
			continue
		var line_index := warnings.find_custom(func(line: String) -> bool:
			return line.begins_with(rule.warning.get_slice(".", 0)))
		if line_index != -1:
			warnings.remove_at(line_index)
		if hours >= rule.amount * 0.5:
			_warn_or_fail(rule, ceili(rule.amount - hours))


func _warn_or_fail(rule: FailRule, left: int) -> void:
	if not difficulty.can_fail:
		# Only a warning: no count of nights left.
		warnings.append(rule.warning.get_slice(".", 0) + ".")
	elif left <= 0:
		if not lost:
			lost = true
			failed.emit(rule)
	else:
		warnings.append(rule.warning % left)


## Grades the day just gone. Called at midnight.
func grade_day() -> void:
	for step in nightly:
		step.call()
	_graded = true
	var tonight: Dictionary[String, int] = {}
	for def in measure_defs:
		var got: Array = measure_value[def.display_name].call()
		values[def.display_name] = got[0]
		why[def.display_name] = got[1]
		tonight[def.display_name] = def.stars(got[0])
	if security != null:
		security.end_day()
	# Each measure is its stars averaged over the last few nights, so one
	# bad night dents the grade rather than sinking it.
	var recent := history.slice(maxi(history.size() - (AVERAGE_NIGHTS - 1), 0))
	var weighted := 0.0
	var weights := 0.0
	var lowest := 6
	var lowest_name := ""
	for def in measure_defs:
		var sum := float(tonight[def.display_name])
		for night in recent:
			sum += night.stars.get(def.display_name, tonight[def.display_name])
		var average := sum / (recent.size() + 1)
		var stars := clampi(roundi(average), 1, 5)
		measures[def.display_name] = stars
		weighted += average * def.weight
		weights += def.weight
		if stars < lowest:
			lowest = stars
			lowest_name = def.display_name
	var mean := clampi(roundi(weighted / maxf(weights, 0.001)), 1, 5)
	grade = mini(mean, lowest + SPREAD)
	held_by = lowest_name if grade < mean else ""
	history.append({"day": clock.day() - 1 if clock != null else 0, "grade": grade,
			"stars": tonight, "values": values.duplicate()})
	if history.size() > HISTORY_NIGHTS:
		history = history.slice(history.size() - HISTORY_NIGHTS)
	_apply()
	_yesterday_moodlets = _moodlets
	_yesterday_arrivals = _arrivals
	_moodlets = {}
	_arrivals = 0
	check_goals(true)
	check_fail_rules()


## The morning paper: yesterday in a few lines.
func write_report() -> String:
	var lines := PackedStringArray()
	lines.append("%s  %d-star prison" % ["★".repeat(grade) + "☆".repeat(5 - grade), grade])
	if not held_by.is_empty():
		lines.append("Held to %d★ by %s." % [grade, held_by])
	for line in warnings:
		lines.append(line)
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
	_check_sit_in()
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


## In debt is one star; otherwise how many days of costs are in the bank.
func _money() -> Array:
	if ledger.balance < 0 and not ledger.sandbox:
		return [IN_DEBT, "in debt"]
	var costs := ledger.daily_costs(MONEY_DAYS)
	if costs <= 0.0:
		return [99.0, "no costs yet"]
	var days := ledger.balance / costs
	return [days, "%s in the bank, %d days of costs" % [Ledger.text(ledger.balance), floori(days)]]


func _apply() -> void:
	finances.grant_scale = (0.8 + 0.1 * (grade - 1)) * difficulty.grant_scale


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

