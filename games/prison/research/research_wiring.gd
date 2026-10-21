class_name ResearchWiring
## Sets up counters, know-how and research for the prison, and tells the
## counters about what happens in it: each system's own signals become
## Counters events, so none of them needs to know about research.

## Job kinds -> the Counters event each one finished counts as.
const JOB_EVENTS := {&"treat": &"treatment", &"search": &"search_done", &"repair": &"repair_done",
		&"laundry": &"laundry_load", &"cook": &"meal_batch", &"make": &"workshop_good",
		&"teach": &"course_session", &"patrol": &"patrol_hour"}
## Fighters it takes to count as a big fight.
const BIG_FIGHT := 5
## A calm day: no fights, and prisoners' average mood at least this.
const CALM_MOOD := 60.0
## Days in a game year, until M12 brings seasons: four weeks.
const DAYS_PER_YEAR := 28


static func setup(main: Node) -> void:
	var counters: Counters = main.counters
	var knowhow: Knowhow = main.knowhow
	var research: Research = main.research
	var clock: GameClock = main.clock
	var board := PrisonResearch.board()
	counters.name = "Counters"
	counters.clock = clock
	main.add_child(counters)
	knowhow.name = "Knowhow"
	knowhow.kinds = board.knowhow
	knowhow.sources = board.sources
	knowhow.counters = counters
	knowhow.clock = clock
	main.add_child(knowhow)
	research.name = "Research"
	research.board = board
	research.knowhow = knowhow
	research.counters = counters
	research.heads = main.heads
	research.roster = main.roster
	research.desk_work = main.desk_work
	research.modifiers = main.modifiers
	research.building = main.building
	research.grade = func() -> int: return (main.standing as Standing).grade
	research.setting = func(id: StringName) -> Variant: return _setting(main, id)
	research.clock = clock
	main.add_child(research)
	research.start()
	_count(main)
	clock.hour_changed.connect(func(_hour: int) -> void: research.check_reveals())


## Whether the prison is new (nothing saved): gives the starting know-how.
static func new_game(main: Node) -> void:
	(main.research as Research).give_start_knowhow()


static func _setting(main: Node, id: StringName) -> Variant:
	match id:
		&"staff_needs":
			return not (main.people as People).needs_off.has(&"staff")
		&"red_tape":
			return (main.desk_work as DeskWork).red_tape != DeskWork.RedTape.OFF
	return null


static func _count(main: Node) -> void:
	var counters: Counters = main.counters
	var people: People = main.people
	(main.jobs as JobBoard).job_finished.connect(func(job: Job, _worker: Person) -> void:
		if JOB_EVENTS.has(job.kind):
			counters.add(JOB_EVENTS[job.kind]))
	people.moodlet_added.connect(func(_person: Person, id: StringName) -> void:
		if id == &"good_meal":
			counters.add(&"meal_good")
		elif id == &"lovely_meal" or id == &"hearty_meal":
			counters.add(&"meal_lovely"))
	var fights: Fights = main.fights
	fights.started.connect(func(fight: Fights.Fight) -> void:
		counters.add(&"fight")
		if fight.fighters.size() >= BIG_FIGHT:
			counters.add(&"big_fight"))
	(main.sit_ins as SitIns).started.connect(func(_sit_in: SitIns.SitIn) -> void: counters.add(&"riot"))
	(main.escapes as Escapes).got_away.connect(func(_person: Person) -> void: counters.add(&"escape"))
	(main.escape_plans as EscapePlans).broke_out.connect(func(_person: Person, _kind: StringName) -> void:
		counters.add(&"escape"))
	var found := func(def: ItemDef) -> void:
		counters.add(&"contraband_found")
		if def.smell > 0.0:
			counters.add(&"drug_found")
		if def.tags.has(&"weapon"):
			counters.add(&"weapon_found")
	(main.searching as Searching).found.connect(func(_owner: Person, def: ItemDef, _where: String) -> void:
		found.call(def))
	(main.contraband as Contraband).detected.connect(func(_person: Person, def: ItemDef) -> void: found.call(def))
	(main.vehicle_gates as VehicleGates).found.connect(func(def: ItemDef) -> void:
		found.call(def)
		counters.add(&"delivery_smuggling_found"))
	var visits: Visits = main.visits
	visits.visited.connect(func(_person: Person) -> void: counters.add(&"visit"))
	visits.smuggled.connect(func(_person: Person, _def: ItemDef) -> void: counters.add(&"visit_smuggled"))
	(main.courses as Courses).passed.connect(func(_person: Person, _def: CourseDef) -> void:
		counters.add(&"course_passed"))
	(main.parole as Parole).heard.connect(func(_person: Person, granted: bool) -> void:
		if granted:
			counters.add(&"parole_passed"))
	(main.release as Release).left.connect(func(entry: Dictionary) -> void:
		if entry.reform >= Reform.REFORMED_LINE:
			counters.add(&"reformed_release"))
	(main.land_plots as LandPlots).bought.connect(func(_plot: Rect2i) -> void: counters.add(&"land_bought"))
	(main.standing as Standing).goal_done.connect(func(_goal: GoalDef) -> void: counters.add(&"grant_goal"))
	(main.desk_work as DeskWork).finished.connect(func(_owner: int, item: DeskWork.Item) -> void:
		if item.kind == &"paperwork":
			counters.add(&"desk_hour", roundi(item.total / 60.0)))
	(main.in_tray as InTray).answered.connect(func(_card: InTray.Card, choice: TrayChoiceDef, by: StringName) -> void:
		if by == &"player":
			counters.add(&"tray_card_warden")
		if by != &"lapsed":
			counters.add(&"tray_card")
		if choice.tags.has(&"strict"):
			(main.research as Research).nudge_lean(1.0)
		elif choice.tags.has(&"caring"):
			(main.research as Research).nudge_lean(-1.0))
	(main.shifts as Shifts).left.connect(func(person: Person) -> void:
		if person.shift == &"night" and person.role == &"guard":
			counters.add(&"night_shift"))
	var secure_area: SecureArea = main.secure_area
	(main.building as Building).changed.connect(func() -> void:
		if secure_area.has_perimeter and counters.total(&"perimeter_closed") == 0:
			counters.add(&"perimeter_closed"))
	var standing: Standing = main.standing
	standing.nightly.append(func() -> void:
		var day := (main.clock as GameClock).day()
		if day > 1 and (day - 1) % DAYS_PER_YEAR == 0:
			counters.add(&"year_end")
		if counters.today.get(&"fight", 0) == 0 and standing._average_mood() >= CALM_MOOD \
				and people.people.any(func(p: Person) -> bool: return p.group == &"prisoner"):
			counters.add(&"calm_day"))
