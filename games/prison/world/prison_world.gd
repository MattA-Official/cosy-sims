class_name PrisonWorld
## Wires M12's outside world into the prison: the town's opinion and the
## local paper, open days, community service, protestors, and seasons,
## weather and festive days. Each system keeps to its own node; this only
## connects them.

## Below LOW_REPUTATION Safety loses a star; above HIGH_REPUTATION the
## grant gains HIGH_GRANT.
const LOW_REPUTATION := 30.0
const HIGH_REPUTATION := 70.0
const HIGH_GRANT := 1.1
## Goods sell for up to this much more or less with the town's opinion.
const GOODS_SWING := 0.1
## Good news counts this much more with the Public relations card.
const PUBLIC_RELATIONS := 1.25
## Security incidents that make the news.
const NEWS_KINDS: Array[StringName] = [&"escape", &"death", &"sit_in", &"fight", &"escape_plan"]
## Open days: when the town tours, how many come, how often one may be
## held, and the room quality (0–100) that wins them over or puts them off.
const OPEN_DAY := &"open_day"
const OPEN_HOURS := Vector2i(10, 16)
const TOURISTS := 4
const OPEN_GAP_DAYS := 7
const OPEN_GOOD := 70.0
const OPEN_BAD := 40.0
## Protest pressure an open day, and a word from the warden, take off; days
## between words.
const OPEN_DAY_EASE := 30.0
const WORD_EASE := 25.0
const WORD_DAYS := 7
## Blocks a festive day turns into festivities.
const FESTIVE_SWAPS: Array[StringName] = [&"work", &"learn", &"club", &"yard"]
## Hotheads lose their temper this much sooner in a heatwave.
const HEAT_TEMPER := 1.3
const GRIT_KIND := &"grit"
const GRIT_SPOTS := 4
const GRIT_STAGE_MINUTES := 10.0
## Community service: the hours out, a chance each day of slipping away
## (halved for the happy), and what they do.
const COMMUNITY := &"community"
const SERVICE_HOURS := Vector2i(10, 15)
const ABSCOND := 0.01
const ABSCOND_HAPPY := 60.0
const SERVICE_CATEGORY := &"low"
const TASKS: Array[String] = ["Painting the bandstand", "Litter picking in the park", "Tidying the churchyard",
		"Helping at the food bank", "Mending the village hall fence"]


static func setup(main: Node) -> void:
	_reputation(main)
	_open_day(main)
	_community_service(main)
	_protest(main)
	_seasons(main)


static func _reputation(main: Node) -> void:
	var reputation: Reputation = main.reputation
	var standing: Standing = main.standing
	var research: Research = main.research
	reputation.name = "Reputation"
	reputation.defs.assign(PrisonCatalogue.REPUTATION)
	reputation.mood = standing._average_mood
	reputation.clock = main.clock
	main.add_child(reputation)
	reputation.change_scales.append(func(def: ReputationEventDef, _change: float) -> float:
		return PUBLIC_RELATIONS if def.tone == ReputationEventDef.Tone.GOOD \
				and research.mode != Research.Mode.OFF and research.has_flag(&"public_relations") else 1.0)
	var security: Security = main.security
	if security != null:
		security.counted.connect(func(kind: StringName) -> void:
			if NEWS_KINDS.has(kind):
				reputation.report(kind))
	(main.release as Release).left.connect(func(entry: Dictionary) -> void:
		if float(entry.reform) >= Reform.REFORMED_LINE:
			reputation.report(&"release_did_well", entry.name))
	standing.star_adjusts.append(func(tonight: Dictionary) -> void:
		if reputation.score < LOW_REPUTATION and tonight.has("Safety"):
			tonight["Safety"] = maxi(1, tonight["Safety"] - 1))
	standing.grant_scales.append(func() -> float:
		return HIGH_GRANT if reputation.score > HIGH_REPUTATION else 1.0)
	standing.news = func() -> Array:
		var day: int = (main.clock as GameClock).day() - 1
		var out := reputation.news(day)
		var lead: ReputationEventDef = null
		if not out.is_empty():
			reputation.print_headline(day + 1, out[0].words)
			lead = reputation.def_of(out[0].id)
		# The worst topic in the day's news is what any crowd protests about.
		var about := &""
		for entry: Dictionary in out:
			var def := reputation.def_of(entry.id)
			if def != null and def.tone == ReputationEventDef.Tone.BAD and def.topic != &"":
				about = def.topic
				break
		(main.protest as Protest).read_paper(lead.tone if lead != null else ReputationEventDef.Tone.NEUTRAL, about)
		return out
	standing.paper_name = func() -> String: return reputation.paper_name
	# A good name brings more visitors and more custom for the workshop.
	(main.visits as Visits).visit_scale = func() -> float: return 0.5 + reputation.score / 100.0
	reputation.changed.connect(func(score: float) -> void:
		(main.finances as Finances).goods_scale = 1.0 + GOODS_SWING * (score - Reputation.START) / Reputation.START)
	standing.report_lines.append(func() -> Array[String]:
		return ["The town's view of the prison: %s (%d)." % [reputation.words(), roundi(reputation.score)]])


## Once a season the town may tour the prison; how nice the rooms are
## decides what they tell the paper.
static func _open_day(main: Node) -> void:
	var events: Events = main.events
	var people: People = main.people
	var research: Research = main.research
	var clock: GameClock = main.clock
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var before := events.allowed
	events.allowed = func(def: EventDef) -> bool:
		if before.is_valid() and not before.call(def):
			return false
		if def.id != OPEN_DAY:
			return true
		return (research.mode == Research.Mode.OFF or research.has_flag(&"open_day")) \
				and clock.day() - int(main.get_meta(&"last_open_day", -OPEN_GAP_DAYS)) >= OPEN_GAP_DAYS
	clock.hour_changed.connect(func(hour: int) -> void:
		var today := events.today()
		if today == null or today.id != OPEN_DAY:
			return
		if hour == OPEN_HOURS.x:
			open_doors(main)
		elif hour == OPEN_HOURS.y:
			close_doors(main))
	people.deciders.append(func(person: Person, _may_wander: bool) -> bool:
		if not person.profile.has("tour"):
			return false
		if person.state != Person.State.IDLE:
			return true
		var here := people.room_of(person)
		if not here.is_empty() and (here[1] as Room).type != &"":
			var seen: Array = person.profile["tour"]
			var key := [here[0], (here[1] as Room).cells[0]]
			if not seen.has(key):
				seen.append(key)
		person.activity = "Touring the prison"
		person.timer = 3.0
		var rooms := people._all_rooms().filter(func(pair: Array) -> bool: return (pair[1] as Room).type != &"")
		for i in 3:
			if rooms.is_empty():
				break
			var pair: Array = rooms[rng.randi() % rooms.size()]
			var room: Room = pair[1]
			var cell: Vector2i = room.cells[rng.randi() % room.cells.size()]
			if people.walk_to(person, pair[0], Vector2(cell) + Vector2(0.5, 0.5), "Touring the prison"):
				break
		return true)


## The town arrives for the open day. Returns the tourists.
static func open_doors(main: Node) -> Array[Person]:
	var people: People = main.people
	var visits: Visits = main.visits
	main.set_meta(&"last_open_day", (main.clock as GameClock).day())
	var out: Array[Person] = []
	var spot: Array = visits.entrance.call() if visits.entrance.is_valid() else []
	if spot.is_empty():
		return out
	for i in TOURISTS:
		var tourist := people.add_person(spot[0], spot[1] + Vector2(i * 0.3, 0.0), "", Visits.VISITOR)
		if tourist == null:
			tourist = people.add_person(spot[0], spot[1], "", Visits.VISITOR)
		if tourist == null:
			continue
		tourist.traits.clear()
		tourist.profile["guest"] = true
		tourist.profile["tour"] = []
		tourist.passes_as = &"staff"
		tourist.activity = "Touring the prison"
		out.append(tourist)
	return out


## The open day ends: the town says what it thought, and goes home.
## Returns the score, 0–100.
static func close_doors(main: Node) -> float:
	var people: People = main.people
	var visits: Visits = main.visits
	var reputation: Reputation = main.reputation
	var building: Building = main.building
	var seen: Array = []
	var tourists: Array = people.people.filter(func(p: Person) -> bool: return p.profile.has("tour"))
	for tourist: Person in tourists:
		for key: Array in tourist.profile["tour"]:
			if not seen.has(key):
				seen.append(key)
	var rooms: Array = []
	for key: Array in seen:
		var map: BuildingMap = building.levels.get(key[0])
		var room := map.room_at(key[1]) if map != null else null
		if room != null:
			rooms.append([key[0], room])
	if rooms.is_empty():
		rooms = people._all_rooms().filter(func(pair: Array) -> bool: return (pair[1] as Room).type != &"")
	var sum := 0.0
	for pair: Array in rooms:
		var quality := people.quality(pair[0], pair[1])
		sum += (quality.score - RoomQuality.MIN) / (RoomQuality.MAX - RoomQuality.MIN) * 100.0
	var score := sum / rooms.size() if not rooms.is_empty() else 50.0
	(main.protest as Protest).ease(OPEN_DAY_EASE)
	if score > OPEN_GOOD:
		reputation.report(&"open_day_good")
	elif score < OPEN_BAD:
		reputation.report(&"open_day_bad")
	for tourist: Person in tourists:
		tourist.profile.erase("tour")
		tourist.profile.erase("guest")
		tourist.passes_as = &""
		visits.send_home(tourist)
	return score


## Low-category prisoners on the community service programme go out into
## the town with a guard from 10:00 to 15:00.
static func _community_service(main: Node) -> void:
	var people: People = main.people
	var clock: GameClock = main.clock
	clock.hour_changed.connect(func(hour: int) -> void:
		if hour == SERVICE_HOURS.x:
			send_out(main)
		elif hour == SERVICE_HOURS.y:
			bring_back(main))
	clock.minute_passed.connect(func(_minute: int) -> void:
		for person: Person in people.people:
			if person.profile.has("outing") or person.away:
				person.away = person.profile.has("outing") and person.state == Person.State.USING)
	(main.inspector as Inspector).person_lines.append(func(person: Person) -> String:
		if person.profile.has("outing"):
			return "%s (community service)" % person.profile["outing"]
		if person.programme == COMMUNITY and person.category != SERVICE_CATEGORY:
			return "Community service is for low-category prisoners only."
		return "")


## Sends today's community service out, with a guard. Returns how many go.
static func send_out(main: Node) -> int:
	var people: People = main.people
	var jobs: JobBoard = main.jobs
	var spot: Array = (main.shifts as Shifts).entrance
	if spot.is_empty() or not jobs.of_kind(COMMUNITY).is_empty():
		return 0
	var going: Array = people.people.filter(func(p: Person) -> bool:
		return p.group == &"prisoner" and p.programme == COMMUNITY and p.category == SERVICE_CATEGORY \
				and not p.going_home and not p.led and p.quiet_room_hours <= 0.0 and not p.profile.has("outing"))
	if going.is_empty():
		return 0
	var task: String = TASKS[(main.clock as GameClock).day() % TASKS.size()]
	var minutes := float(SERVICE_HOURS.y - SERVICE_HOURS.x) * 60.0
	var tile := Vector2i((spot[1] as Vector2).floor())
	var guard := _outing_job(spot[0], tile, task, minutes, "Supervising community service")
	guard.roles = [&"guard"]
	jobs.post(guard)
	for prisoner: Person in going:
		var job := _outing_job(spot[0], tile, task, minutes, "%s (community service)" % task)
		job.only_for = prisoner
		prisoner.passes_as = &"staff"
		jobs.post(job)
	return going.size()


static func _outing_job(level: int, tile: Vector2i, task: String, minutes: float, doing: String) -> Job:
	var job := Job.new()
	job.kind = COMMUNITY
	job.title = "Community service"
	job.any_time = true
	job.priority = 5
	var out := Job.on_tile(Job.Do.WORK, level, tile)
	out.minutes = 1.0
	out.doing = "Signing out"
	out.finish = func(_stage: Job.Stage, worker: Person) -> void:
		worker.profile["outing"] = task
	var away := Job.on_tile(Job.Do.WORK, level, tile)
	away.minutes = minutes
	away.doing = doing
	job.stages = [out, away]
	return job


## Community service comes back: good for the prison's name and for reform,
## unless someone slipped away. Returns those who came back.
static func bring_back(main: Node) -> Array[Person]:
	var people: People = main.people
	var jobs: JobBoard = main.jobs
	var reputation: Reputation = main.reputation
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	for job in jobs.of_kind(COMMUNITY):
		jobs.cancel(job)
	var back: Array[Person] = []
	for person: Person in people.people.duplicate():
		if person.programme == COMMUNITY and person.group == &"prisoner":
			person.passes_as = &""
		if not person.profile.has("outing"):
			continue
		var task: String = person.profile["outing"]
		person.profile.erase("outing")
		person.away = false
		people.stop(person)
		if person.group != &"prisoner":
			continue
		var chance := ABSCOND * (0.5 if person.mood > ABSCOND_HAPPY else 1.0)
		if rng.randf() < chance:
			reputation.report(&"abscond", person.name)
			(main.escapes as Escapes)._gone(person)
			continue
		reputation.report(&"community", person.name)
		(main.reform as Reform).progress.add(person, &"community")
		var file := PrisonerFile.of(person)
		if file != null:
			file.add_log((main.clock as GameClock).day(), "%s (community service)" % task)
		back.append(person)
	return back


## Campaigners at the gate after bad headlines; well-wishers after a run
## of good ones.
static func _protest(main: Node) -> void:
	var protest: Protest = main.protest
	var people: People = main.people
	var standing: Standing = main.standing
	var intake: Intake = main.intake
	var reputation: Reputation = main.reputation
	var visits: Visits = main.visits
	protest.name = "Protest"
	protest.people = people
	protest.reputation = reputation
	protest.topics.assign(PrisonCatalogue.PROTEST_TOPICS)
	protest.stop = func() -> Array:
		var at: Array = visits.entrance.call() if visits.entrance.is_valid() else []
		return [at[0], (at[1] as Vector2) + Vector2(2.0, 2.0)] if not at.is_empty() else []
	protest.send_bus = func(arrived: Callable) -> bool:
		if visits.vehicles == null or visits.bus_model == null or not visits.bus_stop.is_valid():
			return false
		return visits.vehicles.drive_in(visits.bus_model, visits.bus_stop.call(), func(_bus: Node3D) -> void:
			arrived.call(), Visits.BUS_STAY) != null
	protest.fixes = {
		&"overcrowding": func() -> bool: return intake.free_beds() > 0,
		&"food": func() -> bool:
			var good: int = standing._yesterday_moodlets.get(&"good_meal", 0) + standing._yesterday_moodlets.get(&"lovely_meal", 0)
			return good > 0 and standing._yesterday_moodlets.get(&"missed_meal", 0) == 0,
		&"soft": func() -> bool: return standing.measures.get("Safety", 0) >= 4,
		&"safety": func() -> bool:
			var since: int = (main.clock as GameClock).day() - 7
			return not reputation.entries.any(func(e: Dictionary) -> bool: return e.id == &"escape" and e.day > since),
	}
	protest.clock = main.clock
	main.add_child(protest)
	protest.attach()
	(main.vehicles as Vehicles).holds.append(protest.hold_at)
	(main.inspector as Inspector).person_lines.append(protest.words)
	var office_window: Node = main.get(&"office_window")
	if office_window != null:
		office_window.protest = protest
		office_window.have_a_word = func() -> bool: return have_a_word(main)
		office_window.may_have_a_word = func() -> bool: return may_have_a_word(main)
	protest.arrived.connect(func(count: int, friendly: bool) -> void:
		var toasts := main.get_node_or_null("/root/Toasts")
		if main.attract or toasts == null:
			return
		if friendly:
			toasts.post("Well-wishers at the gate", "%d people came with cake to cheer the staff on." % count)
		else:
			var def := protest.topic_def(protest.topic)
			toasts.post("Protestors at the gate", "%d campaigners are protesting about %s." % [count,
					def.display_name.to_lower() if def != null else "the prison"]))
	protest.left.connect(func() -> void:
		var toasts := main.get_node_or_null("/root/Toasts")
		if not main.attract and toasts != null:
			toasts.post("The crowd has gone", "The people at the gate packed up and went home."))
	standing.report_lines.append(func() -> Array[String]:
		if protest.state == Protest.State.PROTESTING:
			var def := protest.topic_def(protest.topic)
			if def != null:
				return ["Campaigners at the gate about %s. %s would help." % [def.display_name.to_lower(), def.fix_words]]
			return ["Campaigners at the gate."]
		return [])


## The warden has a word with the campaigners (Public relations card), once
## a week. Returns whether it was allowed.
static func have_a_word(main: Node) -> bool:
	if not may_have_a_word(main):
		return false
	main.set_meta(&"last_word", (main.clock as GameClock).day())
	(main.protest as Protest).ease(WORD_EASE)
	return true


static func may_have_a_word(main: Node) -> bool:
	var research: Research = main.research
	if research.mode != Research.Mode.OFF and not research.has_flag(&"public_relations"):
		return false
	return (main.clock as GameClock).day() - int(main.get_meta(&"last_word", -WORD_DAYS)) >= WORD_DAYS \
			and (main.protest as Protest).state == Protest.State.PROTESTING


## The year turning: seasons with their light, the day's weather, and
## festive days off.
static func _seasons(main: Node) -> void:
	var calendar: Calendar = main.calendar
	var weather: Weather = main.weather
	var people: People = main.people
	var runner: ScheduleRunner = main.runner
	var clock: GameClock = main.clock
	var ground := (main.terrain as Terrain).ground_material as ShaderMaterial
	calendar.name = "Calendar"
	calendar.seasons.assign(PrisonCatalogue.SEASONS)
	calendar.festive.assign(PrisonCatalogue.FESTIVE_DAYS)
	calendar.day_night = main.day_night
	calendar.ground = ground
	calendar.clock = clock
	main.add_child(calendar)
	calendar.apply()
	weather.name = "Weather"
	weather.people = people
	weather.calendar = calendar
	weather.defs.assign(PrisonCatalogue.WEATHER)
	weather.ground = ground
	weather.day_night = main.day_night
	weather.clock = clock
	main.add_child(weather)
	weather.attach()
	var view := WeatherView.new()
	view.name = "WeatherView"
	view.weather = weather
	view.centre = func() -> Vector3: return (main.camera_rig as Node3D).position if main.camera_rig != null else Vector3.ZERO
	main.add_child(view)
	(main.protest as Protest).stormy = weather.is_stormy
	runner.substitutes.append(func(group: StringName, def: ActivityDef) -> ActivityDef:
		if def == null or not String(group).begins_with("prisoner"):
			return def
		var festive := calendar.festive_today()
		if festive != null and festive.block != null and FESTIVE_SWAPS.has(def.id):
			return festive.block
		if not weather.outdoors_ok() and def.wet_block != null:
			return def.wet_block
		return def)
	weather.changed.connect(func(_def: WeatherDef) -> void: runner.refresh())
	clock.day_changed.connect(func(_day: int) -> void:
		var kitchen: Kitchen = main.kitchen
		if main.has_meta(&"usual_meal"):
			var usual := PrisonCatalogue.meal(main.get_meta(&"usual_meal"))
			if usual != null:
				kitchen.meal = usual
			main.remove_meta(&"usual_meal")
		var festive := calendar.festive_today()
		if festive != null:
			celebrate(main, festive)
		runner.refresh())
	(main.misconduct as Misconduct).temper_scales.append(func(person: Person) -> float:
		return HEAT_TEMPER if weather.is_hot() and person.traits.any(func(t: TraitDef) -> bool: return t.id == &"hothead") else 1.0)
	clock.hour_changed.connect(func(hour: int) -> void:
		if hour % 2 == 0 and weather.is_snowy() and not weather.gritted() and (main.jobs as JobBoard).of_kind(GRIT_KIND).is_empty():
			grit_job(main))
	var clock_bar: Node = main.get(&"clock_bar")
	if clock_bar != null:
		clock_bar.calendar = calendar
		clock_bar.weather = weather
	(main.inspector as Inspector).person_lines.append(func(person: Person) -> String:
		if person.block != null and person.block.id == &"indoor_rec" and weather.current() != null:
			return "Indoors because of the %s (Yard block)" % weather.current().display_name.to_lower()
		return "")
	(main.standing as Standing).report_lines.append(func() -> Array[String]:
		var out: Array[String] = []
		if calendar.enabled:
			out.append("%s." % calendar.words())
		if weather.enabled:
			out.append(weather.forecast_words())
		var next := calendar.next_festive()
		if not next.is_empty() and int(next[0]) > 0 and int(next[0]) <= 3:
			out.append("%s in %d day%s." % [(next[1] as FestiveDayDef).display_name, next[0], "" if next[0] == 1 else "s"])
		return out)


## A festive day: festivities instead of work, a special dinner and a treat
## for everyone.
static func celebrate(main: Node, festive: FestiveDayDef) -> void:
	var people: People = main.people
	var kitchen: Kitchen = main.kitchen
	if festive.menu != &"" and PrisonCatalogue.meal(festive.menu) != null:
		main.set_meta(&"usual_meal", kitchen.meal.id)
		kitchen.meal = PrisonCatalogue.meal(festive.menu)
	for person: Person in people.people:
		if person.group == &"prisoner" or person.group == &"staff":
			people.add_moodlet(person, festive.moodlet)
	var toasts := main.get_node_or_null("/root/Toasts")
	if not main.attract and toasts != null:
		toasts.post(festive.display_name, festive.description)


## A cleaner's job to grit the paths, at a few points along them.
static func grit_job(main: Node) -> Job:
	var paths: PathNetwork = main.paths
	var weather: Weather = main.weather
	var spots: Array = []
	for segment: PathNetwork.Segment in paths.segments.values():
		if spots.size() >= GRIT_SPOTS:
			break
		spots.append(paths.point_on(segment, 0.5))
	var entrance: Array = (main.shifts as Shifts).entrance
	if spots.is_empty() and not entrance.is_empty():
		spots.append(entrance[1])
	if spots.is_empty():
		weather.grit()
		return null
	var job := Job.new()
	job.kind = GRIT_KIND
	job.title = "Grit the paths"
	job.roles = [&"cleaner"]
	job.priority = 4
	job.any_time = true
	for spot: Vector2 in spots:
		var stage := Job.on_tile(Job.Do.WORK, 0, Vector2i(spot.floor()))
		stage.minutes = GRIT_STAGE_MINUTES
		stage.doing = "Gritting the paths"
		job.stages.append(stage)
	(job.stages[-1] as Job.Stage).finish = func(_stage: Job.Stage, _worker: Person) -> void: weather.grit()
	(main.jobs as JobBoard).post(job)
	return job
