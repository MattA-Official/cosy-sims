class_name ResearchWiring
## Sets up counters, know-how and research for the prison, and tells the
## counters about what happens in it: each system's own signals become
## Counters events, so none of them needs to know about research.

## Job kinds -> the Counters event each one finished counts as.
const JOB_EVENTS := {&"treat": &"treatment", &"search": &"search_done", &"repair": &"repair_done",
		&"laundry": &"laundry_load", &"cook": &"meal_batch", &"make": &"workshop_good",
		&"teach": &"course_session", &"checkup": &"checkup"}
## Fighters it takes to count as a big fight.
const BIG_FIGHT := 5
## A calm day: no fights, and prisoners' average mood at least this.
const CALM_MOOD := 60.0
## A skill this high counts as a high skill.
const HIGH_SKILL := 60
## Things broken at once that count as a big repair bill.
const BIG_REPAIR := 5
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
	# Cards such as Research assistants make a kind come faster.
	knowhow.scale = func(kind: StringName) -> float: return Modifiers.scale(main.modifiers, StringName("knowhow_%s" % kind))
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
	research.jobs = main.jobs
	research.people = main.people
	research.pay = func(amount: int, line: String) -> void: (main.ledger as Ledger).add(-amount, line)
	research.grade = func() -> int: return (main.standing as Standing).grade
	research.setting = func(id: StringName) -> Variant: return _setting(main, id)
	research.clock = clock
	main.add_child(research)
	research.start()
	var marks := TrialMarks.new()
	marks.name = "TrialMarks"
	marks.cell_size = (main.grid as BuildGrid).cell_size
	marks.building = main.building
	marks.research = research
	marks.clock = clock
	(main.grid as BuildGrid).add_child(marks)
	_count(main)
	_effects(main)
	_trials(main)
	_feedback(main)
	_thoughts(main)
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
		&"no_road":
			return not (main.roads as Roads).has_roads()
		&"utilities":
			return [&"off", &"bought_in", &"self_sufficient"][(main.utilities as Utilities).mode]
	return null


static func _count(main: Node) -> void:
	var counters: Counters = main.counters
	var people: People = main.people
	(main.jobs as JobBoard).job_finished.connect(func(job: Job, worker: Person) -> void:
		if worker != null and worker.group == &"prisoner":
			(main.research as Research).note_trial(worker, &"work")
		if JOB_EVENTS.has(job.kind):
			counters.add(JOB_EVENTS[job.kind]))
	(main.in_tray as InTray).posted.connect(func(card: InTray.Card) -> void:
		if card.def.kind == &"memo":
			counters.add(&"ministry_memo"))
	(main.infirmary as Infirmary).knocked_out.connect(func(_person: Person) -> void: counters.add(&"serious_injury"))
	(main.wear as Wear).broke.connect(func(_key: Vector2i) -> void:
		if people.broken.size() >= BIG_REPAIR:
			counters.add(&"big_repair_bill"))
	# Each prisoner with a high skill counts once, checked each night.
	var skilled: Dictionary[int, bool] = {}
	(main.clock as GameClock).day_changed.connect(func(_day: int) -> void:
		for person: Person in people.people:
			var file := PrisonerFile.of(person) if person.group == &"prisoner" else null
			if file != null and not skilled.has(person.id) and file.skill(file.best_skill()) >= HIGH_SKILL:
				skilled[person.id] = true
				counters.add(&"high_skill"))
	# Patrols count by the hour a guard spends on them, not by the job.
	var patrolled := {"minutes": 0.0}
	(main.clock as GameClock).minute_passed.connect(func(_minute: int) -> void:
		for person: Person in people.people:
			if person.job != null and person.job.kind == &"patrol":
				patrolled.minutes += 1.0
		if patrolled.minutes >= 60.0:
			counters.add(&"patrol_hour", floori(patrolled.minutes / 60.0))
			patrolled.minutes = fmod(patrolled.minutes, 60.0))
	people.moodlet_added.connect(func(_person: Person, id: StringName) -> void:
		if id == &"good_meal":
			counters.add(&"meal_good")
		elif id == &"lovely_meal" or id == &"hearty_meal":
			counters.add(&"meal_lovely"))
	var fights: Fights = main.fights
	var research: Research = main.research
	fights.started.connect(func(fight: Fights.Fight) -> void:
		counters.add(&"fight")
		for person: Person in fight.fighters:
			research.note_trial(person, &"fight")
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
	(main.searching as Searching).found.connect(func(owner: Person, def: ItemDef, _where: String) -> void:
		found.call(def)
		if owner != null:
			research.note_trial(owner, &"find"))
	(main.contraband as Contraband).detected.connect(func(person: Person, def: ItemDef) -> void:
		found.call(def)
		research.note_trial(person, &"find"))
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


## Toasts as cards finish and turn up, and the morning report's lines.
static func _feedback(main: Node) -> void:
	var research: Research = main.research
	(main.standing as Standing).report_lines.append(research.report_lines)
	(main.inspector as Inspector).person_lines.append(func(person: Person) -> String:
		var record := (main.roster as StaffRoster).record_of(person)
		return research.owner_line(record.id) if record != null else "")
	(main.inspector as Inspector).person_lines.append(func(person: Person) -> String:
		return "\n".join(PrisonResearch.person_lines(research, person)))
	var toast := func(title: String, body: String) -> void:
		var toasts := main.get_node_or_null("/root/Toasts")
		if not main.attract and toasts != null:
			toasts.post(title, body)
	research.finished.connect(func(def: ResearchCardDef, owner: int) -> void:
		toast.call("Research done: %s" % def.display_name, "%s %s" % [research.finished_words(def, owner), def.gives_text]))
	research.revealed.connect(func(def: ResearchCardDef, why: String) -> void:
		if why != "From the start":
			toast.call("A new idea: %s" % def.display_name, "Turned up: %s. See the research board (N)." % why.to_lower()))


## A head at their desk on a card shows it in a thought bubble; clicking
## them opens the board on that card.
static func _thoughts(main: Node) -> void:
	var research: Research = main.research
	var roster: StaffRoster = main.roster
	var desk_work: DeskWork = main.desk_work
	var card_of := func(person: Person) -> ResearchCardDef:
		var record := roster.record_of(person)
		if record == null or person.job == null or person.job.kind != Office.DESK_JOB or not person.sitting:
			return null
		for item: DeskWork.Item in desk_work.piles.get(record.id, []):
			if item.kind == &"research" and item.ref is String:
				return research.card(StringName(String(item.ref).trim_prefix("card:")))
			if item.kind != &"research":
				return null
		return null
	(main.clock as GameClock).minute_passed.connect(func(_minute: int) -> void:
		for slot in research.slots():
			var record := research._record(research.slot_owner(slot))
			var person: Person = record.person if record != null else null
			if person == null or (not person.bubble.is_empty() and not person.has_meta(&"research_bubble")):
				continue
			var def: ResearchCardDef = card_of.call(person)
			if def != null:
				person.bubble = "… %s" % def.display_name
				person.bubble_minutes = 2.0
				person.set_meta(&"research_bubble", def.id)
			elif person.has_meta(&"research_bubble"):
				person.remove_meta(&"research_bubble")
				person.bubble = "")
	(main.cursor as GridCursor).cell_clicked.connect(func(_cell: Vector2i, button: MouseButton) -> void:
		var inspector: Inspector = main.inspector
		if button != MOUSE_BUTTON_LEFT or (main.controller as BuildController).tool != BuildController.Tool.NONE:
			return
		var person := inspector.person_under_mouse()
		if person != null and person.has_meta(&"research_bubble"):
			var book: ManagementBook = main.book
			book.open(&"research")
			(main.research_window as ResearchWindow).show_card(person.get_meta(&"research_bubble")))


## Wing trials report through the in-tray.
static func _trials(main: Node) -> void:
	var research: Research = main.research
	var in_tray: InTray = main.in_tray
	(main.prison_tray as PrisonTray).research = research
	for def in research.board.cards:
		if def.trial:
			in_tray.defs.append(PrisonTray.trial(def))
	research.trial_report.connect(func(def: ResearchCardDef, words: String) -> void:
		in_tray.post_about(in_tray.find(StringName("trial_%s" % def.id)), 0, words)
		var toasts := main.get_node_or_null("/root/Toasts")
		if not main.attract and toasts != null:
			toasts.post("Trial report: %s" % def.display_name, "See the in-tray (J) to roll it out, try another wing or shelve it."))


## Hours when night_trouble counts.
const NIGHT_FROM := 22
const NIGHT_TO := 6


## What cards done do: their modifiers summed into one Modifiers source,
## a little money each day, and tempers.
static func _effects(main: Node) -> void:
	var research: Research = main.research
	var modifiers: Modifiers = main.modifiers
	for system: Object in [main.desk_work, main.in_tray, main.wear, main.contraband, main.visits, main.supplies,
			main.parole, main.fights, main.vehicle_gates, main.land_plots, main.standing]:
		system.set(&"modifiers", modifiers)
	research.changed.connect(func() -> void: modifiers.set_source(&"research", research.modifier_sums()))
	var toolbar := main.get_node_or_null("HUD/BuildToolbar")
	if toolbar != null:
		toolbar.allowed = research.unlocked
		toolbar.upgrades = research.upgrades_of
	modifiers.set_source(&"research", research.modifier_sums())
	var misconduct: Misconduct = main.misconduct
	var clock: GameClock = main.clock
	misconduct.temper_scales.append(func(person: Person) -> float:
		var scale := maxf(0.1, 1.0 + modifiers.value_for(&"temper_rate", person))
		var hour := clock.hour()
		if hour >= NIGHT_FROM or hour < NIGHT_TO:
			scale *= maxf(0.1, 1.0 + modifiers.value_for(&"night_trouble", person))
		return scale)
	(main.reform as Reform).progress.gain_scales.append(func(person: Person) -> float:
		return 1.0 + modifiers.value_for(&"reform_gain", person))
	(main.standing as Standing).nightly.append(func() -> void:
		for entry: Array in research.daily_money():
			(main.ledger as Ledger).add(entry[0], entry[1]))
