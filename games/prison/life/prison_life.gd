class_name PrisonLife
## Wires M11's prisoner life into the prison: friends and rivals, staff
## rapport, hobbies, clubs, events, cliques, tokens and the shop, and
## colds, fitness and age, pets, named families, and old faces.
## Each system keeps to its own node; this only connects them.

## Bond changes from things that happen.
const FIGHT_BOND := -30.0
const QUIET_ROOM_BOND := 10.0
const TRADE_BOND := 3.0
## What the prison gets for something a prisoner made (a painting, a scarf).
const MADE_PRICE := 10
## A clique sits in with this many, not SitIns.MIN_CROWD.
const CLIQUE_SIT_IN := 4
## Pay for traits that work harder or less.
const WAGE_TRAITS: Dictionary[StringName, float] = {&"grafter": 1.25, &"lazy": 0.75}
## Savings policies: the share of pay put aside.
const SAVE_SHARES: Array[float] = [0.0, 0.2, 0.5]
## A shift at the till, and how close the worker must be to it.
const TILL_MINUTES := 60.0
const TILL_REACH := 2.0
## Odds a prisoner free to shop goes when they next decide.
const SHOP_ODDS := 0.2
## What shop things do.
const RADIO_MOOD := 2.0
const GIFT_BOND := 10.0
const STAMP_FAMILY := 40.0
const CHOCOLATE_MOOD_UNDER := 60.0
const GIFT_ODDS := 0.3
## Every SAVINGS_STEP tokens saved takes SAVINGS_CUT off the chance of
## coming back, up to SAVINGS_MOST.
const SAVINGS_STEP := 50
const SAVINGS_CUT := 0.02
const SAVINGS_MOST := 0.1
## Colds a nurse sees to an hour, in the infirmary.
const TREAT_PER_HOUR := 6
## Blocks the ill may leave to see the nurse in.
const NURSE_BLOCKS: Array[StringName] = [&"free", &"yard", &"work", &"club", &"learn"]
## The ill take to their bed with energy under this, whatever the block.
const BED_UNDER := 50.0
## Under-25s take this much more from courses.
const YOUNG_COURSES := 1.2
## Research: clean and showered (hygiene over HYGIENE_ABOVE) catch this
## much less with the hygiene drive, everyone with vaccinations; the
## isolation ward stops the seen-to spreading.
const HYGIENE_ABOVE := 50.0
const HYGIENE_SCALE := 0.7
const VACCINE_SCALE := 0.5
## A flu week: a chance a day, how long, and how much faster colds spread.
const FLU_WEEK_ODDS := 0.01
const FLU_WEEK_DAYS := 7
const FLU_WEEK_SCALE := 2.0
const FLU_WEEK_LEAST := 10
## How often the ill sneeze, a chance an hour.
const SNEEZE_ODDS := 0.3
## Cats: one for every CAT_PRISONERS prisoners, once there are CAT_FROM; a
## stray's chance a day of turning up before then.
const CAT_PRISONERS := 40
const CAT_FROM := 10
const STRAY_ODDS := 0.05
## Cage pets: the hour they're given out, a clean week to earn one, care
## a day, and days of neglect before they're rehomed.
const PET_HOUR := 8
const PET_CLEAN_DAYS := 7
const PET_CARE_MINUTES := 20.0
const PET_NEGLECT_DAYS := 2
## A rabbit's chance a day of getting out, and how long catching it takes.
const RABBIT_LOOSE_ODDS := 0.01
const CATCH_MINUTES := 10.0
## The therapy dog's visit, on days someone is on Calm Minds.
const DOG_HOURS := Vector2i(14, 17)
const DOG_REACH := 1.5
const FAMILY_DAY := &"family_day"
## What a prisoner who comes back still has, and bonds strong enough to
## remember.
const OLD_FACE_KEYS: Array[String] = ["hobbies", "hobby_skill", "family", "age", "fitness"]
const OLD_FACE_BOND := 20.0


static func setup(main: Node) -> void:
	_relationships(main)
	_rapport(main)
	_hobbies(main)
	_events(main)
	_cliques(main)
	_shop(main)
	_health(main)
	_pets(main)
	_families(main)
	_old_faces(main)
	_news(main)


## Each prisoner's small named family: who writes, who visits, fondness
## kept up by letters, calls and visits, and family days when children
## bring drawings for the cell wall.
static func _families(main: Node) -> void:
	var people: People = main.people
	var visits: Visits = main.visits
	var events: Events = main.events
	var research: Research = main.research
	var clock: GameClock = main.clock
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var is_prisoner := func(p: Person) -> bool: return p.group == &"prisoner"
	for person: Person in people.people:
		if is_prisoner.call(person):
			Families.make(person, rng)
	people.person_added.connect(func(person: Person) -> void:
		if is_prisoner.call(person):
			Families.make(person, rng))
	var family_day := func() -> bool:
		var today := events.today()
		return today != null and today.id == FAMILY_DAY
	events.allowed = func(def: EventDef) -> bool:
		return def.id != FAMILY_DAY or research.mode == Research.Mode.OFF or research.has_flag(&"family_day")
	visits.family_day = family_day
	visits.visitor_for = func(prisoner: Person) -> Dictionary:
		Families.make(prisoner, rng)
		var least := Families.LETTER_FONDNESS if family_day.call() else Families.VISIT_FONDNESS
		var relative := Families.any(prisoner, least, rng)
		return {} if relative.is_empty() else {"name": relative.name, "title": Families.title(relative)}
	visits.letter_from = func(prisoner: Person) -> String:
		Families.make(prisoner, rng)
		var relative := Families.any(prisoner, Families.LETTER_FONDNESS, rng)
		return "" if relative.is_empty() else "%s %s" % [Families.title(relative), relative.name]
	visits.letter.connect(func(prisoner: Person, from: String) -> void:
		var file := PrisonerFile.of(prisoner)
		if file != null:
			file.add_log(clock.day(), "A letter from %s" % from))
	visits.visited_by.connect(func(prisoner: Person, visitor: Person) -> void:
		var relative: Dictionary = {}
		for r: Dictionary in Families.of(prisoner):
			if r.name == visitor.profile.get("relative", ""):
				relative = r
		Families.warm(relative, Families.VISIT)
		if not family_day.call():
			return
		events.attended[prisoner.id] = true
		var child := Families.child(prisoner)
		if not child.is_empty():
			prisoner.profile["drawing"] = {"from": child.name, "day": clock.day()}
			people.quality_changed()
			var file := PrisonerFile.of(prisoner)
			if file != null:
				file.add_log(clock.day(), "%s drew them a picture" % child.name))
	people.moodlet_added.connect(func(person: Person, id: StringName) -> void:
		if id == &"rang_home":
			Families.warm(Families.fondest(person), Families.CALL))
	clock.day_changed.connect(func(day: int) -> void:
		var had := people.people.any(func(p: Person) -> bool: return p.profile.has("drawing"))
		for person: Person in people.people:
			if is_prisoner.call(person):
				Families.new_day(person, day)
		if had:
			people.quality_changed())
	# A drawing on the wall makes the cell a little nicer.
	people.quality_extras.append(func(level: int, room: Room) -> Array:
		for owner: Person in people.owners_in(level, room):
			if owner.profile.has("drawing"):
				return [["A drawing on the wall", Families.DRAWING_QUALITY]]
		return [])
	(main.inspector as Inspector).person_lines.append(Families.words)


## Prisoners who come back are the same people: their hobbies, family,
## age and fitness, and a friend or rival or two, who remember them.
static func _old_faces(main: Node) -> void:
	var release: Release = main.release
	var relationships: Relationships = main.relationships
	var people: People = main.people
	release.recording.append(func(person: Person, entry: Dictionary) -> void:
		var kept := {}
		for key: String in OLD_FACE_KEYS:
			if person.profile.has(key):
				kept[key] = person.profile[key].duplicate(true) if person.profile[key] is Dictionary \
						or person.profile[key] is Array else person.profile[key]
		entry["kept"] = kept
		var bonds := {}
		for other: Person in people.people:
			if other != person and other.group == person.group:
				var value := relationships.bond(person, other)
				if absf(value) >= OLD_FACE_BOND:
					bonds[other.id] = value
		entry["bonds"] = bonds)
	release.returned.connect(func(person: Person, entry: Dictionary) -> void:
		var kept: Dictionary = entry.get("kept", {})
		for key: String in kept:
			person.profile[key] = kept[key].duplicate(true) if kept[key] is Dictionary or kept[key] is Array else kept[key]
		var bonds: Dictionary = entry.get("bonds", {})
		for other: Person in people.people:
			if bonds.has(other.id):
				relationships.change(person, other, float(bonds[other.id]) - relationships.bond(person, other))
			elif bonds.has(str(other.id)):
				relationships.change(person, other, float(bonds[str(other.id)]) - relationships.bond(person, other)))


## A cat or two that wander the wings, rabbits and budgies kept in cells by
## prisoners on the pet care programme, and a visiting therapy dog.
static func _pets(main: Node) -> void:
	var people: People = main.people
	var animals: Animals = main.animals
	var research: Research = main.research
	var clock: GameClock = main.clock
	var jobs: JobBoard = main.jobs
	var building: Building = main.building
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	animals.name = "Animals"
	animals.people = people
	animals.defs.assign(PrisonCatalogue.ANIMALS)
	animals.room_words = func(room: Room) -> String:
		var type: RoomTypeDef = people.access.room_types.get(room.type)
		return "the %s" % type.display_name.to_lower() if type != null else ("outside" if not room.indoor else "a room")
	animals.clock = clock
	main.add_child(animals)
	animals.attach()
	(main.misconduct as Misconduct).temper_scales.append(animals.temper_scale)
	var flag := func(id: StringName) -> bool: return research.mode == Research.Mode.OFF or research.has_flag(id)
	var prisoners := func() -> Array: return people.people.filter(func(p: Person) -> bool: return p.group == &"prisoner")
	clock.day_changed.connect(func(_day: int) -> void:
		var count: int = prisoners.call().size()
		if count < CAT_FROM:
			return
		if flag.call(&"prison_cat"):
			var want := maxi(1, count / CAT_PRISONERS)
			for i in want - animals.of_kind(&"cat").size():
				add_cat(main)
		elif not main.has_meta(&"stray_seen") and rng.randf() < STRAY_ODDS:
			main.set_meta(&"stray_seen", true)
			(main.counters as Counters).add(&"stray")
			var toasts := main.get_node_or_null("/root/Toasts")
			if not main.attract and toasts != null:
				toasts.post("A stray cat", "A stray cat was seen by the gate. The Prison cat card would let it stay."))
	# Cage pets.
	clock.hour_changed.connect(func(hour: int) -> void:
		if hour == PET_HOUR:
			give_pets(main, rng)
			care_jobs(main))
	clock.day_changed.connect(func(day: int) -> void:
		for keeper: Person in prisoners.call():
			var pet: Dictionary = keeper.profile.get("pet", {})
			if pet.is_empty():
				continue
			if day - int(pet.get("cared", day)) > PET_NEGLECT_DAYS:
				keeper.profile.erase("pet")
				people.add_moodlet(keeper, &"lost_my_pet")
				var file := PrisonerFile.of(keeper)
				if file != null:
					file.add_log(day, "%s was taken away" % pet.get("name", "Their pet"))
			elif String(pet.get("kind", "")) == "rabbit" and rng.randf() < RABBIT_LOOSE_ODDS:
				rabbit_loose(main, keeper))
	# The therapy dog.
	clock.hour_changed.connect(func(hour: int) -> void:
		if hour == DOG_HOURS.x and flag.call(&"therapy_dogs") and animals.of_kind(&"therapy_dog").is_empty() \
				and prisoners.call().any(func(p: Person) -> bool: return p.profile.get("course", "") == "calm_minds"):
			dog_visit(main)
		elif hour == DOG_HOURS.y:
			for dog in animals.of_kind(&"therapy_dog"):
				dog_leaves(main, dog)
			# Any handler left without their dog, such as after a load.
			for person: Person in people.people.duplicate():
				if person.profile.has("handler_room"):
					people.remove_person(person))
	# The handler walks the dog round the room it came to.
	people.deciders.append(func(person: Person, _may_wander: bool) -> bool:
		if not person.profile.has("handler_room"):
			return false
		if person.state != Person.State.IDLE:
			return true
		var place: Array = person.profile["handler_room"]
		var room := (building.levels.get(place[0]) as BuildingMap).room_at(place[1]) if building.levels.has(place[0]) else null
		person.timer = 5.0
		person.activity = "Walking the therapy dog"
		if room != null and not room.cells.is_empty():
			var cell: Vector2i = room.cells[rng.randi() % room.cells.size()]
			people.walk_to(person, place[0], Vector2(cell) + Vector2(0.5, 0.5), person.activity)
		return true)
	clock.minute_passed.connect(func(_minute: int) -> void:
		for dog in animals.of_kind(&"therapy_dog"):
			for other in people.nearby(dog, DOG_REACH):
				if other.group == &"prisoner" and not other.moodlets.has(&"good_dog") \
						and other.flat().distance_to(dog.flat()) <= DOG_REACH:
					people.add_moodlet(other, &"good_dog"))
	(main.inspector as Inspector).person_lines.append(animals.words)
	(main.inspector as Inspector).person_lines.append(func(person: Person) -> String:
		var pet: Dictionary = person.profile.get("pet", {})
		if pet.is_empty():
			return ""
		var today := int(pet.get("cared", -1)) == clock.day()
		return "Keeps %s the %s%s" % [pet.get("name", "?"), pet.get("kind", "pet"), " (looked after today)" if today else ""])
	(main.standing as Standing).report_lines.append(func() -> Array[String]:
		var out: Array[String] = []
		for cat in animals.of_kind(&"cat"):
			var spot := animals.favourite_spot(cat)
			if not spot.is_empty():
				out.append("%s the cat was mostly found in %s." % [cat.name, spot])
		return out)


## A cat, somewhere outdoors if it can be.
static func add_cat(main: Node) -> Person:
	var animals: Animals = main.animals
	var people: People = main.people
	var rooms := people._all_rooms()
	rooms.sort_custom(func(a: Array, b: Array) -> bool: return not (a[1] as Room).indoor and (b[1] as Room).indoor)
	for pair: Array in rooms:
		var cat := animals.add_in(animals.def_by_id(&"cat"), pair[0], pair[1])
		if cat != null:
			return cat
	return null


## Pets for keepers on the pet care programme with a clean week and an
## empty cage in their cell.
static func give_pets(main: Node, rng: RandomNumberGenerator) -> void:
	var people: People = main.people
	var animals: Animals = main.animals
	var day := (main.clock as GameClock).day()
	for key in (main.building as Building).objects_tagged([&"pet"]):
		var placed := (main.building as Building).object_at(key)
		var room := ((main.building as Building).levels[key.x] as BuildingMap).room_at_point(placed.centre)
		for keeper: Person in people.people:
			if keeper.programme != &"pet_care" or keeper.profile.has("pet"):
				continue
			var home := people.home_room(keeper)
			if home.is_empty() or home[0] != key.x or home[1] != room:
				continue
			if keeper.record.any(func(entry: Array) -> bool: return int(entry[0]) > day - PET_CLEAN_DAYS):
				continue
			var kind: StringName = [&"rabbit", &"budgie"][rng.randi() % 2]
			var def := animals.def_by_id(kind)
			keeper.profile["pet"] = {"kind": String(kind), "name": animals.random_name(def), "cared": day,
					"cage": [key.x, key.y]}
			var file := PrisonerFile.of(keeper)
			if file != null:
				file.add_log(day, "Was given %s the %s" % [keeper.profile["pet"]["name"], kind])
			break


## A job for each keeper to look after their pet today.
static func care_jobs(main: Node) -> void:
	var people: People = main.people
	var jobs: JobBoard = main.jobs
	var clock: GameClock = main.clock
	for keeper: Person in people.people:
		var pet: Dictionary = keeper.profile.get("pet", {})
		if pet.is_empty() or jobs.of_kind(&"pet_care").any(func(j: Job) -> bool: return j.only_for == keeper):
			continue
		var cage: Array = pet.get("cage", [])
		if cage.size() < 2 or (main.building as Building).object_at(Vector2i(cage[0], cage[1])) == null:
			continue
		var job := Job.new()
		job.kind = &"pet_care"
		job.title = "Look after %s" % pet.get("name", "the pet")
		job.only_for = keeper
		var stage := Job.at(Job.Do.WORK, int(cage[0]), int(cage[1]))
		stage.minutes = PET_CARE_MINUTES
		stage.doing = "Looking after %s" % pet.get("name", "the pet")
		stage.finish = func(_stage: Job.Stage, worker: Person) -> void:
			var mine: Dictionary = worker.profile.get("pet", {})
			if mine.is_empty():
				return
			mine["cared"] = clock.day()
			(main.reform as Reform).progress.add(worker, &"pet_care")
			people.add_moodlet(worker, &"my_pet")
		job.stages = [stage]
		jobs.post(job)


## A rabbit gets out and runs to the canteen, to everyone's delight, until a
## guard catches it.
static func rabbit_loose(main: Node, keeper: Person) -> Person:
	var people: People = main.people
	var animals: Animals = main.animals
	var pet: Dictionary = keeper.profile.get("pet", {})
	for pair: Array in people._all_rooms():
		var room: Room = pair[1]
		if room.type != &"canteen":
			continue
		var rabbit := animals.add_in(animals.def_by_id(&"rabbit"), pair[0], room, pet.get("name", ""))
		if rabbit == null:
			continue
		rabbit.set_meta(&"stay", true)
		rabbit.profile["loose"] = true
		for person: Person in people.people:
			if person.group == &"prisoner" and People._same_place([pair[0], room], people.room_of(person)):
				people.add_moodlet(person, &"rabbit_chaos")
		var job := Job.new()
		job.kind = &"catch_rabbit"
		job.title = "Catch %s the rabbit" % rabbit.name
		job.roles = [&"guard"]
		job.priority = 4
		var stage := Job.on_tile(Job.Do.WORK, pair[0], Vector2i(rabbit.flat().floor()))
		stage.minutes = CATCH_MINUTES
		stage.doing = "Catching %s" % rabbit.name
		stage.finish = func(_stage: Job.Stage, _guard: Person) -> void:
			if people.people.has(rabbit):
				people.remove_person(rabbit)
		job.stages = [stage]
		(main.jobs as JobBoard).post(job)
		var toasts := main.get_node_or_null("/root/Toasts")
		if not main.attract and toasts != null:
			toasts.post("Rabbit on the loose!", "%s got out and is running round the canteen." % rabbit.name)
		return rabbit
	return null


## The therapy dog comes for the afternoon, to wherever most prisoners are.
static func dog_visit(main: Node) -> Person:
	var people: People = main.people
	var animals: Animals = main.animals
	var counts: Dictionary = {}
	var best: Array = []
	for person: Person in people.people:
		var here := people.room_of(person)
		if person.group == &"prisoner" and not here.is_empty():
			counts[here[1]] = counts.get(here[1], 0) + 1
			if best.is_empty() or counts[here[1]] > counts[best[1]]:
				best = here
	if best.is_empty():
		return null
	var dog := animals.add_in(animals.def_by_id(&"therapy_dog"), best[0], best[1])
	if dog == null:
		return null
	var handler := people.add_person(dog.level, dog.flat(), "", &"visitor")
	if handler != null:
		handler.traits.clear()
		handler.profile["guest"] = true
		handler.profile["handler_room"] = [best[0], (best[1] as Room).cells[0]]
		handler.activity = "Walking the therapy dog"
		animals.leaders[dog] = handler
	return dog


## The therapy dog goes home with its handler.
static func dog_leaves(main: Node, dog: Person) -> void:
	var people: People = main.people
	var animals: Animals = main.animals
	var handler: Person = animals.leaders.get(dog)
	animals.leaders.erase(dog)
	if handler != null and people.people.has(handler):
		people.remove_person(handler)
	people.remove_person(dog)


## Colds going round, seen to by a nurse in the infirmary; fitness from
## exercise; and age.
static func _health(main: Node) -> void:
	var people: People = main.people
	var illnesses: Illnesses = main.illnesses
	var research: Research = main.research
	var infirmary: Infirmary = main.infirmary
	var clock: GameClock = main.clock
	var counters: Counters = main.counters
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	illnesses.name = "Illnesses"
	illnesses.people = people
	illnesses.defs.assign(PrisonCatalogue.ILLNESSES)
	illnesses.clock = clock
	main.add_child(illnesses)
	illnesses.attach()
	var flag := func(id: StringName) -> bool: return research.mode == Research.Mode.OFF or research.has_flag(id)
	illnesses.catch_scales.append(func(person: Person) -> float:
		var scale := 1.0
		if flag.call(&"hygiene_drive") and person.needs.get(&"hygiene", 0.0) > HYGIENE_ABOVE:
			scale *= HYGIENE_SCALE
		if flag.call(&"vaccinations"):
			scale *= VACCINE_SCALE
		if int(main.get_meta(&"flu_week_until", -1)) >= clock.day():
			scale *= FLU_WEEK_SCALE
		return scale)
	illnesses.spreads = func(person: Person) -> bool:
		return not (illnesses.is_treated(person) and flag.call(&"isolation_ward"))
	illnesses.outbreak.connect(func(_ill: int) -> void: counters.add(&"cold_outbreak"))
	(main.reform as Reform).progress.source_scales.append(func(person: Person, source: StringName) -> float:
		return YOUNG_COURSES if String(source).begins_with("course") and illnesses.is_young(person) else 1.0)
	# Seeing the nurse, and a day in bed.
	var seen := [0]
	clock.hour_changed.connect(func(_hour: int) -> void:
		seen[0] = 0
		for person in illnesses.ill():
			if rng.randf() < SNEEZE_ODDS and person.bubble.is_empty():
				person.bubble = "Atchoo!"
				person.bubble_minutes = 2.0)
	people.deciders.append(func(person: Person, _may_wander: bool) -> bool:
		if illnesses.illness_of(person) == null or person.group != &"prisoner" or person.job != null:
			return false
		if person.needs.get(people.tired_need, 100.0) < BED_UNDER and person.block != null \
				and person.block.id != &"eat" and not person.lying:
			if people._seek(person, [&"bed"], &"", true):
				person.reason = "A day in bed with a cold"
				return true
		if illnesses.is_treated(person) or person.block == null or not NURSE_BLOCKS.has(person.block.id) \
				or not infirmary.nurse_on_duty() or people._urgent_need(person) != &"":
			return false
		var here := people.room_of(person)
		if not here.is_empty() and (here[1] as Room).type == &"infirmary":
			if seen[0] < TREAT_PER_HOUR:
				seen[0] += 1
				illnesses.treat(person)
				person.activity = "Seen by the nurse"
				person.timer = 5.0
				return true
			return false
		for pair: Array in people._all_rooms():
			if (pair[1] as Room).type == &"infirmary":
				if people.walk_to(person, pair[0], (pair[1] as Room).centre(), "Off to see the nurse"):
					person.reason = "Has a cold"
					return true
		return false)
	# A flu week now and then.
	clock.day_changed.connect(func(_day: int) -> void:
		if not illnesses.enabled or int(main.get_meta(&"flu_week_until", -1)) >= clock.day():
			return
		var prisoners := people.people.filter(func(p: Person) -> bool: return p.group == &"prisoner").size()
		if prisoners >= FLU_WEEK_LEAST and rng.randf() < FLU_WEEK_ODDS:
			start_flu_week(main))
	# A red nose on the ill.
	var noses := func() -> void:
		for person: Person in people.people:
			var body := people.body_of(person)
			if body == null:
				continue
			var nose := body.get_node_or_null(^"ColdNose") as MeshInstance3D
			var ill := illnesses.illness_of(person) != null
			if nose == null and ill:
				nose = MeshInstance3D.new()
				nose.name = "ColdNose"
				var sphere := SphereMesh.new()
				sphere.radius = 0.03
				sphere.height = 0.06
				nose.mesh = sphere
				nose.position = Vector3(0.0, 0.74, 0.15)
				var material := StandardMaterial3D.new()
				material.albedo_color = Color(0.85, 0.3, 0.3)
				nose.material_override = material
				body.add_child(nose)
			if nose != null:
				nose.visible = ill
	illnesses.caught.connect(func(_person: Person, _def: IllnessDef) -> void: noses.call())
	illnesses.recovered.connect(func(_person: Person) -> void: noses.call())
	clock.hour_changed.connect(func(_hour: int) -> void: noses.call())
	var tint: HealthTint = main.health_tint
	tint.name = "HealthTint"
	tint.cell_size = (main.grid as BuildGrid).cell_size
	tint.building = main.building
	tint.people = people
	tint.illnesses = illnesses
	(main.grid as BuildGrid).add_child(tint)
	(main.inspector as Inspector).person_lines.append(illnesses.words)
	(main.standing as Standing).report_lines.append(func() -> Array[String]:
		var ill := illnesses.ill().size()
		var out: Array[String] = []
		if ill >= 2:
			out.append("Cold going round: %d ill." % ill)
		if int(main.get_meta(&"flu_week_until", -1)) >= clock.day():
			out.append("Flu week until day %d." % int(main.get_meta(&"flu_week_until", -1)))
		return out)


## A week when colds spread twice as fast, starting with one.
static func start_flu_week(main: Node) -> void:
	var illnesses: Illnesses = main.illnesses
	var clock: GameClock = main.clock
	main.set_meta(&"flu_week_until", clock.day() + FLU_WEEK_DAYS - 1)
	(main.counters as Counters).add(&"flu_week")
	var prisoners: Array = (main.people as People).people.filter(func(p: Person) -> bool:
		return p.group == &"prisoner" and illnesses.illness_of(p) == null)
	if not prisoners.is_empty() and not illnesses.defs.is_empty():
		illnesses.catch(prisoners.pick_random(), illnesses.defs[0])
	var toasts := main.get_node_or_null("/root/Toasts")
	if not main.attract and toasts != null:
		toasts.post("Flu week", "Colds are spreading twice as fast this week. A nurse in the infirmary helps.")


## Work pays tokens, the shop sells for them while someone works the till,
## and savings go home with them. All once the Prison shop card is done.
static func _shop(main: Node) -> void:
	var people: People = main.people
	var shop: Shop = main.shop
	var jobs: JobBoard = main.jobs
	var building: Building = main.building
	var research: Research = main.research
	var hobbies: Hobbies = main.hobbies
	var relationships: Relationships = main.relationships
	var clock: GameClock = main.clock
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	shop.name = "Shop"
	shop.people = people
	shop.ledger = main.ledger
	shop.items.assign(PrisonCatalogue.SHOP_ITEMS)
	shop.allowed = func() -> bool: return research.mode == Research.Mode.OFF or research.has_flag(&"prison_shop")
	shop.is_open = func() -> bool: return not open_tills(people, jobs, building).is_empty()
	shop.clock = clock
	main.add_child(shop)
	var programmes := PrisonCatalogue.programmes()
	clock.hour_changed.connect(func(_hour: int) -> void:
		if not shop.exists():
			return
		# Wages for an hour's work.
		for person: Person in people.people:
			if person.group != &"prisoner" or person.programme == &"" or person.job == null:
				continue
			var def: WorkProgrammeDef = programmes.get(person.programme)
			if def == null:
				continue
			var wage := float(def.wage)
			for t in person.traits:
				wage *= WAGE_TRAITS.get(t.id, 1.0)
			Purse.pay(person, wage, shop.save_share)
		man_tills(jobs, building))
	# Going shopping in free time.
	people.deciders.append(func(person: Person, _may_wander: bool) -> bool:
		if person.group != &"prisoner" or person.block == null or not person.block.allows(&"till") \
				or person.job != null or not shop.open():
			return false
		if int(person.profile.get("shopped_day", -1)) == clock.day() or people._urgent_need(person) != &"":
			return false
		var cheapest := shop.cheapest()
		if cheapest == 0 or Purse.tokens(person) < cheapest or rng.randf() >= SHOP_ODDS:
			return false
		if want(shop, hobbies, relationships, person, rng) == null:
			return false
		person.profile["shopped_day"] = clock.day()
		if people.seek(person, [&"till"], &""):
			person.reason = "Going shopping"
			return true
		return false)
	people.used.connect(func(person: Person, placed: BuildingMap.PlacedObject) -> void:
		if placed == null or not placed.def.tags.has(&"till") or person.group != &"prisoner":
			return
		if not shop.open():
			person.activity = "Nobody at the till"
			return
		var def := want(shop, hobbies, relationships, person, rng)
		if def != null and shop.buy(person, def):
			person.activity = "Bought %s" % def.display_name.to_lower())
	shop.sold.connect(func(person: Person, def: ItemDef) -> void: _use_bought(people, relationships, person, def))
	people.mood_extras.append(func(person: Person, _here: Array) -> Array:
		return [["Has a radio", RADIO_MOOD]] if person.profile.get("has_radio", false) else [])
	# A hobby kit lets them keep it up in their cell.
	clock.day_changed.connect(func(_day: int) -> void:
		for person: Person in people.people:
			if person.profile.get("hobby_kit", false):
				hobbies.did_at_home(person))
	(main.release as Release).return_cuts.append(func(person: Person) -> float:
		return minf(floorf(Purse.savings(person) / float(SAVINGS_STEP)) * SAVINGS_CUT, SAVINGS_MOST))
	(main.inspector as Inspector).person_lines.append(Purse.words)


## What something bought from the shop does.
static func _use_bought(people: People, relationships: Relationships, person: Person, def: ItemDef) -> void:
	match def.use:
		&"treat":
			if def.pack > 1:
				for i in def.pack:
					person.pocket.append(def)
			elif def.use_moodlet != &"":
				people.add_moodlet(person, def.use_moodlet)
		&"stamp":
			if person.needs.has(&"family"):
				person.needs[&"family"] = minf(person.needs[&"family"] + STAMP_FAMILY, 100.0)
			people.add_moodlet(person, &"wrote_home")
			Families.warm(Families.fondest(person), Families.WRITE_BACK)
		&"radio":
			person.profile["has_radio"] = true
		&"hobby_kit":
			person.profile["hobby_kit"] = true
		&"gift":
			var friends := relationships.friends_of(person)
			if not friends.is_empty():
				var friend: Person = friends[0][0]
				relationships.change(person, friend, GIFT_BOND)
				people.add_moodlet(friend, def.use_moodlet)


## What someone would buy, or null: a radio if they've none, a kit for
## their hobby, a stamp when missing home, a present for a friend now and
## then, chocolate when low, else biscuits.
static func want(shop: Shop, hobbies: Hobbies, relationships: Relationships, person: Person,
		rng: RandomNumberGenerator) -> ItemDef:
	var wishes: Array[StringName] = []
	if not person.profile.get("has_radio", false):
		wishes.append(&"radio")
	if not person.profile.get("hobby_kit", false) and not hobbies.hobbies_of(person).is_empty():
		wishes.append(&"hobby_kit")
	if person.needs.get(&"family", 100.0) < 50.0:
		wishes.append(&"stamp")
	if not relationships.friends_of(person).is_empty() and rng.randf() < GIFT_ODDS:
		wishes.append(&"gift")
	if person.mood < CHOCOLATE_MOOD_UNDER:
		wishes.append(&"chocolate")
	wishes.append(&"biscuit")
	for id in wishes:
		var def := shop.item(id)
		if def != null and shop.can_buy(person, def):
			return def
	return null


## Tills with someone working them, as (level, object id).
static func open_tills(people: People, jobs: JobBoard, building: Building) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for job in jobs.of_kind(&"till"):
		if job.worker == null or job.worker.state == Person.State.WALKING or not job.has_meta(&"till"):
			continue
		var key: Vector2i = job.get_meta(&"till")
		var placed := building.object_at(key)
		if placed != null and job.worker.level == key.x and job.worker.flat().distance_to(placed.centre) <= TILL_REACH:
			out.append(key)
	return out


## Keeps a job on the board to work every till, standing beside it.
static func man_tills(jobs: JobBoard, building: Building) -> void:
	var tills := building.objects_tagged([&"till"])
	var covered: Array[Vector2i] = []
	for job in jobs.of_kind(&"till"):
		var key: Vector2i = job.get_meta(&"till", Vector2i(-1, -1))
		if not tills.has(key):
			jobs.cancel(job)
		else:
			covered.append(key)
	for key in tills:
		if covered.has(key):
			continue
		var placed := building.object_at(key)
		var job := Job.new()
		job.kind = &"till"
		job.title = "Work the shop till"
		job.priority = 3
		job.set_meta(&"till", key)
		var stand := Job.on_tile(Job.Do.WORK, key.x, _beside(building, key.x, placed))
		stand.minutes = TILL_MINUTES
		stand.doing = "Working the till"
		job.stages = [stand]
		jobs.post(job)


## A tile just behind a till, for whoever works it.
static func _beside(building: Building, level: int, placed: BuildingMap.PlacedObject) -> Vector2i:
	var rect := Rect2i(placed.rect.position.floor(), placed.rect.size.ceil())
	var map := building.levels[level] as BuildingMap
	var room := map.room_at_point(placed.centre)
	for tile: Vector2i in [rect.position + Vector2i(0, -1), rect.position + Vector2i(0, rect.size.y),
			rect.position + Vector2i(-1, 0), rect.position + Vector2i(rect.size.x, 0)]:
		var middle := Vector2(tile) + Vector2(0.5, 0.5)
		if map.room_at_point(middle) == room and map.object_at(middle) == null:
			return tile
	return rect.position + Vector2i(0, -1)


## Lines for the morning report and the paper: "The Gardeners formed", by
## the day they happened.
static func _news(main: Node) -> void:
	var standing: Standing = main.standing
	var clock: GameClock = main.clock
	var cliques: Cliques = main.cliques
	var news: Array = []
	var add := func(day: int, line: String) -> void: news.append([day, line])
	cliques.formed.connect(func(clique: Cliques.Clique) -> void:
		add.call(clock.day() - 1, "%s formed around %s." % [clique.name,
				(main.hobbies as Hobbies).def_of(clique.hobby).display_name.to_lower()]))
	cliques.ended.connect(func(clique: Cliques.Clique) -> void:
		add.call(clock.day() - 1, "%s broke up." % clique.name))
	(main.events as Events).finished.connect(func(def: EventDef, came: Array[Person]) -> void:
		var line := "%s: %d took part." % [def.display_name, came.size()]
		for clique in cliques.cliques:
			if clique.hobby == def.hobby and came.any(func(p: Person) -> bool: return clique.members.has(p.id)):
				line = "%s won the %s." % [clique.name, def.display_name.to_lower()]
				break
		add.call(clock.day() - 1, line))
	standing.report_lines.append(func() -> Array[String]:
		var out: Array[String] = []
		for entry: Array in news.duplicate():
			if entry[0] < clock.day() - 1:
				news.erase(entry)
			elif entry[0] == clock.day() - 1:
				out.append(entry[1])
		return out)


## Friendly groups around a hobby: they sit together, do their hobby
## together for club spirit and reform, wear a pin, and act up together
## when fed up.
static func _cliques(main: Node) -> void:
	var people: People = main.people
	var cliques: Cliques = main.cliques
	var misconduct: Misconduct = main.misconduct
	var reform: Progress = (main.reform as Reform).progress
	cliques.name = "Cliques"
	cliques.people = people
	cliques.relationships = main.relationships
	cliques.hobbies = main.hobbies
	cliques.clock = main.clock
	main.add_child(cliques)
	cliques.attach()
	(main.clock as GameClock).hour_changed.connect(func(_hour: int) -> void:
		for entry: Array in cliques.together():
			for member: Person in entry[1]:
				reform.add(member, &"club")
				people.add_moodlet(member, &"club_spirit"))
	# Acting up together: one member's misconduct pulls in the rest close
	# by, at Mischief at most unless they're very fed up.
	var joining := [false]
	var mischief := misconduct.rung(&"mischief")
	misconduct.acted.connect(func(person: Person, rung: MisconductDef, _words: String) -> void:
		if joining[0]:
			return
		var clique := cliques.clique_of(person)
		if clique == null:
			return
		var grievance := cliques.grievance(clique)
		if grievance <= Cliques.GRIEVANCE_JOIN:
			return
		var worst := rung
		if grievance <= Cliques.GRIEVANCE_ANY and misconduct.rungs.find(rung) > misconduct.rungs.find(mischief):
			worst = mischief
		joining[0] = true
		for member in cliques.joiners(person):
			if member.warning == &"":
				misconduct.act(member, worst)
		joining[0] = false)
	(main.sit_ins as SitIns).crowd_least = func(crowd: Array) -> int:
		for clique in cliques.cliques:
			if crowd.filter(func(p: Person) -> bool: return clique.members.has(p.id)).size() >= CLIQUE_SIT_IN:
				return CLIQUE_SIT_IN
		return SitIns.MIN_CROWD
	var log := func(clique: Cliques.Clique, words: String) -> void:
		for member in cliques.members_of(clique):
			var file := PrisonerFile.of(member)
			if file != null:
				file.add_log((main.clock as GameClock).day(), words % clique.name)
	cliques.formed.connect(func(clique: Cliques.Clique) -> void: log.call(clique, "Joined %s"))
	# Pins on the uniform.
	var pins := func() -> void:
		for person: Person in people.people:
			var body := people.body_of(person)
			if body == null:
				continue
			var clique := cliques.clique_of(person)
			var pin := body.get_node_or_null(^"CliquePin") as MeshInstance3D
			if clique == null:
				if pin != null:
					pin.visible = false
				continue
			if pin == null:
				pin = MeshInstance3D.new()
				pin.name = "CliquePin"
				var sphere := SphereMesh.new()
				sphere.radius = 0.035
				sphere.height = 0.07
				pin.mesh = sphere
				pin.position = Vector3(0.07, 0.48, 0.16)
				pin.material_override = StandardMaterial3D.new()
				body.add_child(pin)
			pin.visible = true
			(pin.material_override as StandardMaterial3D).albedo_color = clique.colour
	(main.clock as GameClock).hour_changed.connect(func(_hour: int) -> void: pins.call())
	cliques.formed.connect(func(_clique: Cliques.Clique) -> void: pins.call())
	(main.inspector as Inspector).person_lines.append(cliques.words)
	((main.inspector as Inspector).get_node("BondLines") as BondLines).cliques = cliques


## Hobbies for every prisoner, clubs in the Clubs block, and the things
## they make, sold at the gate.
static func _hobbies(main: Node) -> void:
	var people: People = main.people
	var hobbies: Hobbies = main.hobbies
	var relationships: Relationships = main.relationships
	var reform: Progress = (main.reform as Reform).progress
	hobbies.name = "Hobbies"
	hobbies.people = people
	hobbies.defs.assign(PrisonCatalogue.HOBBIES)
	hobbies.clock = main.clock
	var research: Research = main.research
	hobbies.clubs_allowed = func() -> bool:
		return research.mode == Research.Mode.OFF or research.has_flag(&"hobby_clubs")
	main.add_child(hobbies)
	hobbies.attach()
	relationships.share_scale = func(a: Person, b: Person) -> float:
		for def in hobbies.hobbies_of(a):
			if hobbies.hobbies_of(b).has(def):
				return Relationships.SHARED_SCALE
		return 1.0
	var day := func() -> int: return (main.clock as GameClock).day()
	hobbies.club_met.connect(func(def: HobbyDef, members: Array[Person], leader: Person) -> void:
		for member in members:
			reform.add(member, &"club")
			people.add_moodlet(member, &"club_spirit")
		people.add_moodlet(leader, &"useful_day")
		var file := PrisonerFile.of(leader)
		if file != null and leader.profile.get("led_club_day", -1) != day.call():
			leader.profile["led_club_day"] = day.call()
			file.add_log(day.call(), "Led %s" % def.club_name))
	hobbies.made.connect(func(person: Person, def: HobbyDef) -> void:
		(main.ledger as Ledger).add(MADE_PRICE, "Hobby sales")
		var file := PrisonerFile.of(person)
		if file != null and not def.made_words.is_empty():
			file.add_log(day.call(), def.made_words))
	(main.inspector as Inspector).person_lines.append(hobbies.words)


## One-day events put on from the office.
static func _events(main: Node) -> void:
	var events: Events = main.events
	var hobbies: Hobbies = main.hobbies
	events.name = "Events"
	events.people = main.people
	events.ledger = main.ledger
	events.defs.assign(PrisonCatalogue.EVENTS)
	events.may_take_part = func(person: Person, def: EventDef) -> bool:
		return def.hobby == &"" or hobbies.hobbies_of(person).any(func(h: HobbyDef) -> bool: return h.id == def.hobby)
	events.clock = main.clock
	main.add_child(events)
	events.attach()
	events.finished.connect(func(def: EventDef, came: Array[Person]) -> void:
		var toasts := main.get_node_or_null("/root/Toasts")
		if not main.attract and toasts != null and not came.is_empty():
			toasts.post(def.display_name, "%d prisoner%s took part and had a great day." % [came.size(), "" if came.size() == 1 else "s"]))


## Guards get to know the prisoners where they work: each shift adds
## rapport with everyone they were in a room with. Well-known guards calm
## tempers near them and talk sit-ins round faster.
static func _rapport(main: Node) -> void:
	var people: People = main.people
	var roster: StaffRoster = main.roster
	var relationships: Relationships = main.relationships
	# Guard record id -> prisoners seen this shift.
	var seen: Dictionary[int, Dictionary] = {}
	(main.clock as GameClock).hour_changed.connect(func(_hour: int) -> void:
		for guard: Person in people.people:
			if guard.role != &"guard":
				continue
			var record := roster.record_of(guard)
			if record == null:
				continue
			var here := people.room_of(guard)
			if here.is_empty():
				continue
			var met: Dictionary = seen.get_or_add(record.id, {})
			for other: Person in people.people:
				if other.group == &"prisoner" and People._same_place(here, people.room_of(other)):
					met[other] = true)
	(main.shifts as Shifts).left.connect(func(guard: Person) -> void:
		var record := roster.record_of(guard)
		if record == null or not seen.has(record.id):
			return
		for prisoner: Person in seen[record.id]:
			if people.people.has(prisoner):
				relationships.add_rapport(record.id, prisoner)
		seen.erase(record.id))
	var best_near := func(prisoner: Person) -> float:
		var best := 0.0
		for other: Person in people.nearby(prisoner):
			if other.role == &"guard":
				var record := roster.record_of(other)
				if record != null:
					best = maxf(best, relationships.rapport_of(record.id, prisoner))
		return best
	(main.misconduct as Misconduct).temper_scales.append(func(prisoner: Person) -> float:
		return Relationships.rapport_scale(best_near.call(prisoner)))
	(main.sit_ins as SitIns).talk_speed = func(talker: Person, sit_in: SitIns.SitIn) -> float:
		var record := roster.record_of(talker)
		if record == null:
			return 1.0
		var best := 0.0
		for member: Person in sit_in.members:
			best = maxf(best, relationships.rapport_of(record.id, member))
		return 1.0 / Relationships.rapport_scale(best)
	(main.inspector as Inspector).person_lines.append(func(person: Person) -> String:
		if person.role != &"guard":
			return ""
		var record := roster.record_of(person)
		if record == null:
			return ""
		var known := 0
		for k: Vector2i in relationships.rapport:
			if k.x == record.id and relationships.rapport[k] > Relationships.RAPPORT_FROM:
				known += 1
		return "Knows %d prisoner%s well" % [known, "" if known == 1 else "s"] if known > 0 else "")


static func _relationships(main: Node) -> void:
	var people: People = main.people
	var relationships: Relationships = main.relationships
	relationships.name = "Relationships"
	relationships.people = people
	relationships.clock = main.clock
	main.add_child(relationships)
	# Bonds replace the old rule that cellmates sharing a trait get on;
	# they start from the same rule.
	people.cellmate_moods = false
	people.mood_extras.append(relationships.mood_parts)
	(main.fights as Fights).rivalry = relationships.is_rival
	(main.misconduct as Misconduct).odds = func(person: Person) -> float:
		return Relationships.RIVAL_ODDS if relationships.rival_near(person) else 1.0
	(main.fights as Fights).started.connect(func(fight: Fights.Fight) -> void:
		for a: Person in fight.fighters:
			for b: Person in fight.fighters:
				if a.id < b.id:
					relationships.change(a, b, FIGHT_BOND))
	(main.contraband as Contraband).traded.connect(func(buyer: Person, seller: Person, _item: ItemDef) -> void:
		relationships.change(buyer, seller, TRADE_BOND))
	# A night in the quiet room at the same time: comic solidarity.
	(main.clock as GameClock).day_changed.connect(func(_day: int) -> void:
		var inside: Array = people.people.filter(func(p: Person) -> bool: return p.quiet_room_hours > 0.0)
		for a: Person in inside:
			for b: Person in inside:
				if a.id < b.id:
					relationships.change(a, b, QUIET_ROOM_BOND))
	var log := func(a: Person, b: Person, words: String) -> void:
		var day := (main.clock as GameClock).day()
		for pair: Array in [[a, b], [b, a]]:
			var file := PrisonerFile.of(pair[0])
			if file != null:
				file.add_log(day, words % (pair[1] as Person).name)
	relationships.became_friends.connect(func(a: Person, b: Person) -> void: log.call(a, b, "Became friends with %s"))
	relationships.became_rivals.connect(func(a: Person, b: Person) -> void: log.call(a, b, "Fell out with %s"))
	people.person_removed.connect(func(gone: Person) -> void:
		for pair: Array in relationships.friends_of(gone):
			people.add_moodlet(pair[0], &"missing_friend"))
	var inspector: Inspector = main.inspector
	inspector.person_lines.append(relationships.words)
	var lines := BondLines.new()
	lines.name = "BondLines"
	lines.inspector = inspector
	lines.relationships = relationships
	lines.building = main.building
	inspector.add_child(lines)
