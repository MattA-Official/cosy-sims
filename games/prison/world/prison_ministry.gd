class_name PrisonMinistry
## Wires the Ministry (core/sim/ministry.gd) into the prison: what its
## contracts and its inspector measure, the inspector's walk round as a
## visitor, and where its money, grade cap and focus land.

const INSPECTOR_NAMES: Array[String] = ["Mrs Pennywhistle", "Mr Hargreaves", "Ms Okonkwo", "Mr Fairweather",
		"Dr Ashby", "Mrs Lindqvist"]
## Meal moodlets that count as a good meal for the inspector.
const GOOD_MEALS: Array[StringName] = [&"good_meal", &"hearty_meal", &"lovely_meal"]
const ALL_MEALS: Array[StringName] = [&"good_meal", &"hearty_meal", &"lovely_meal", &"plain_meal", &"missed_meal"]


static func setup(main: Node) -> void:
	var ministry: Ministry = main.ministry
	var standing: Standing = main.standing
	var research: Research = main.research
	var counters: Counters = main.counters
	var people: People = main.people
	ministry.name = "Ministry"
	ministry.contracts.assign(PrisonCatalogue.CONTRACTS)
	ministry.inspection = PrisonCatalogue.INSPECTION
	standing.goal_kinds[&"prisoners_of"] = func(goal: GoalDef) -> float:
		return people.people.filter(func(p: Person) -> bool:
			return p.group == &"prisoner" and p.category == goal.target).size()
	standing.goal_kinds[&"litter"] = func(_goal: GoalDef) -> float: return litter(main)
	ministry.grade = func() -> int: return standing.grade
	ministry.value_of = func(goal: GoalDef) -> float:
		if goal.counted:
			return standing.counts.get(goal.kind, counters.total(goal.kind))
		return standing.goal_value(goal)
	ministry.measure = func(check: InspectionCheckDef, inspector: Object) -> Array:
		return measure(main, check.measure, inspector as Person)
	ministry.red_tape = func() -> int: return (main.desk_work as DeskWork).red_tape
	ministry.has_flag = func(flag: StringName) -> bool:
		return research.mode != Research.Mode.OFF and research.has_flag(flag)
	ministry.has_card = func(id: StringName) -> bool:
		return research.mode != Research.Mode.OFF and research.is_done(id)
	ministry.pay = func(amount: int, line: String) -> void: (main.ledger as Ledger).add(amount, line)
	ministry.count = func(id: StringName) -> void: counters.add(id)
	ministry.report = func(id: StringName) -> void: (main.reputation as Reputation).report(id)
	ministry.arrive = func() -> Object: return arrive(main)
	ministry.describe = func(inspector: Object, words: String) -> void:
		(inspector as Person).profile["doing"] = words
		(inspector as Person).activity = words
	ministry.leave = func(inspector: Object) -> void:
		(inspector as Person).profile.erase("doing")
		PrisonWorld.see_off(main, [inspector])
	ministry.in_tray = main.in_tray
	ministry.calendar = main.calendar
	ministry.clock = main.clock
	standing.grade_limits.append(ministry.grade_limit)
	standing.grant_scales.append(ministry.grant_scale)
	standing.nightly.append(func() -> void:
		standing.weight_scales.clear()
		if not ministry.focus.is_empty():
			standing.weight_scales[ministry.focus] = 2.0)
	ministry.inspection_done.connect(func(visit: Ministry.Inspection) -> void:
		_toast(main, "The inspector passed the prison" if visit.passed else "The inspector failed the prison",
				ministry.report_words(visit).get_slice("\n", 0)))
	ministry.contract_ended.connect(func(def: ContractDef, success: bool) -> void:
		_toast(main, "Contract done" if success else "Contract missed", def.title))
	main.add_child(ministry)


## The inspector comes in at the visitors' entrance and tours the prison.
static func arrive(main: Node) -> Person:
	var came := PrisonWorld.open_doors(main, 1, false)
	if came.is_empty():
		return null
	var inspector: Person = came[0]
	inspector.name = INSPECTOR_NAMES[(main.clock as GameClock).day() % INSPECTOR_NAMES.size()]
	inspector.profile["inspector"] = true
	inspector.activity = "Inspecting for the Ministry"
	return inspector


## What the inspector measures, and how it reads: [value, words].
static func measure(main: Node, what: StringName, inspector: Person) -> Array:
	var people: People = main.people
	var prisoners := people.people.filter(func(p: Person) -> bool: return p.group == &"prisoner")
	match what:
		&"rooms":
			var score := PrisonWorld.tour_score(main, [inspector] if inspector != null else [])
			return [score, "rooms %d out of 100" % roundi(score)]
		&"litter_share":
			var count := litter(main)
			return [count / maxf(prisoners.size(), 1.0), "%d piece%s of litter" % [count, "" if count == 1 else "s"]]
		&"good_meals":
			var ate := 0
			var good := 0
			for person: Person in prisoners:
				if ALL_MEALS.any(func(id: StringName) -> bool: return person.moodlets.has(id)):
					ate += 1
					if GOOD_MEALS.any(func(id: StringName) -> bool: return person.moodlets.has(id)):
						good += 1
			if ate == 0:
				var meal: MealDef = (main.kitchen as Kitchen).meal
				var served := meal != null and GOOD_MEALS.has(meal.moodlet)
				return [1.0 if served else 0.0, "good meals on the menu" if served else "plain meals on the menu"]
			return [float(good) / ate, "meals %d%% good" % roundi(100.0 * good / ate)]
		&"staff_ratio":
			var staff := people.people.filter(func(p: Person) -> bool: return p.group == &"staff").size()
			if prisoners.is_empty():
				return [1.0, "%d staff, no prisoners yet" % staff]
			return [float(staff) / prisoners.size(), "%d staff to %d prisoners" % [staff, prisoners.size()]]
		&"medical":
			var room := people._all_rooms().any(func(pair: Array) -> bool: return (pair[1] as Room).type == &"infirmary")
			var nurse := people.people.any(func(p: Person) -> bool: return p.role == &"nurse")
			return [1.0 if room and nurse else 0.0, "an infirmary and a nurse" if room and nurse
					else ("no nurse" if room else "no infirmary")]
		&"safety_stars":
			var standing: Standing = main.standing
			var stars: int = standing.measures.get("Safety", 3)
			return [float(stars), "safety %d★" % stars]
	return [0.0, ""]


## Litter lying about on every floor.
static func litter(main: Node) -> int:
	var people: People = main.people
	var items: ItemStore = people.items
	if items == null:
		return 0
	var count := 0
	for key: Vector3i in items.on_floor:
		count += items.count_on_floor(key, people.litter_tag)
	return count


static func _toast(main: Node, title: String, words: String) -> void:
	var toasts := main.get_node_or_null("/root/Toasts")
	if toasts != null and not main.attract:
		toasts.post(title, words)
