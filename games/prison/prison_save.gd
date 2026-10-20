class_name PrisonSave
## Saving and loading a prison. A save keeps the build and the land, the
## clock, money, timetable, staff and settings, and everyone in it with
## their needs, mood, bed and history, in the middle of whatever they were
## doing: walking somewhere, eating, at work. Jobs are posted afresh by
## whatever needs them, and workers take theirs up again where they were.
##
## Saves are files in user://saves: three slots and an autosave written
## each morning.

const FOLDER := "user://saves"
const SLOTS: Array[String] = ["slot_1", "slot_2", "slot_3"]
const AUTOSAVE := "autosave"
const VERSION := 1

## A save to load once the scene starts again, or empty.
static var pending: Dictionary = {}


## Everything worth keeping, as plain data.
static func capture(main: Node) -> Dictionary:
	var people: People = main.people
	var everyone: Array = []
	for person in people.people:
		if person.going_home:
			continue
		var traits: Array = []
		for t in person.traits:
			traits.append(t.id)
		everyone.append({
			"id": person.id, "name": person.name, "group": person.group, "role": person.role,
			"shift": person.shift, "programme": person.programme, "category": person.category,
			# Off whatever they were using, where they stood to use it.
			"level": person.level,
			"position": person.stand_spot if person.state == Person.State.USING else person.position, "needs": person.needs.duplicate(),
			"mood": person.mood, "moodlets": person.moodlets.duplicate(), "traits": traits,
			"profile": person.profile.duplicate(true), "bed": person.bed,
			"doing": people.doing_of(person), "work": (main.jobs as JobBoard).work_of(person),
		})
	var hours: Array = []
	for def in (main.schedule as Schedule).hours:
		hours.append(def.id if def != null else &"")
	var routes: Array = []
	for route in (main.routes as PatrolRoutes).routes:
		routes.append([route.level, route.points.duplicate(), route.guards, route.name])
	var ledger: Ledger = main.ledger
	var standing: Standing = main.standing
	var goals_done: Array = []
	for goal in standing.goals:
		if goal.done:
			goals_done.append(goal.title)
	return {
		"version": VERSION,
		"title": main.title,
		"world": main.capture_world(),
		"minutes": (main.clock as GameClock).total_minutes,
		"people": everyone,
		"next_person_id": people.next_id(),
		"needs_off": people.needs_off.duplicate(),
		"broken": people.broken.duplicate(),
		"wear_uses": (main.wear as Wear).uses.duplicate(),
		"items_held": _items_out((main.items as ItemStore).held),
		"items_floor": _items_out((main.items as ItemStore).on_floor),
		"timetable": hours,
		"locks": people.access.locked.duplicate(),
		"overrides": (main.runner as ScheduleRunner).overrides.duplicate(),
		"pinned": (main.runner as ScheduleRunner).pinned.duplicate(),
		"wanted": (main.shifts as Shifts).wanted.duplicate(true),
		"entrance": (main.shifts as Shifts).entrance.duplicate(),
		"routes": routes,
		"money": {"balance": ledger.balance, "sandbox": ledger.sandbox, "today": ledger.today.duplicate(),
				"yesterday": ledger.yesterday.duplicate(), "closing": ledger.closing.duplicate()},
		"sold": (main.workshop as Workshop).sold,
		"intake": {"limit": (main.intake as Intake).limit, "accepted": (main.intake as Intake).accepted.duplicate(),
				"arriving": (main.intake as Intake).arriving_ids()},
		"standing": {"grade": standing.grade, "measures": standing.measures.duplicate(), "goals_done": goals_done,
				"report": standing.report, "graded": standing.measures_known()},
	}


## Puts the build and the people back, before the prison's systems start.
static func apply_world(main: Node, data: Dictionary) -> void:
	main.restore_world(data.get("world", {}))
	var people: People = main.people
	for entry: Dictionary in data.get("people", []):
		var at: Vector3 = entry["position"]
		var spot := Vector2(at.x, at.z)
		var person: Person = null
		# Where they were, or else the nearest tile they can stand on.
		for nudge: Vector2 in [Vector2.ZERO, Vector2(0.5, 0.5), Vector2(1.5, 0.5), Vector2(-0.5, 0.5),
				Vector2(0.5, 1.5), Vector2(0.5, -0.5)]:
			var try_at := spot if nudge == Vector2.ZERO else spot.floor() + nudge
			person = people.add_person(entry["level"], try_at, entry["name"], entry["group"])
			if person != null:
				break
		if person == null:
			continue
		person.id = entry["id"]
		person.needs.assign(entry["needs"])
		person.mood = entry["mood"]
		person.moodlets.assign(entry["moodlets"])
		person.programme = entry["programme"]
		person.category = entry["category"]
		person.shift = entry["shift"]
		person.profile = entry["profile"]
		var traits: Array[TraitDef] = []
		for id: StringName in entry["traits"]:
			for def in PrisonCatalogue.TRAITS:
				if def.id == id:
					traits.append(def)
		person.traits = traits
		if entry["role"] != &"":
			people.set_role(person, entry["role"])
		var block: StringName = entry.get("doing", {}).get("block", &"")
		for def in PrisonCatalogue.ACTIVITIES:
			if def.id == block:
				person.block = def
	people.set_next_id(data.get("next_person_id", 1))
	people.needs_off.assign(data.get("needs_off", []))
	main.clock.total_minutes = data.get("minutes", main.clock.total_minutes)


## Puts back the rest once the prison's systems are running.
static func apply_rest(main: Node, data: Dictionary) -> void:
	var people: People = main.people
	var schedule: Schedule = main.schedule
	var hours: Array = data.get("timetable", [])
	for i in mini(hours.size(), schedule.hours.size()):
		for def in PrisonCatalogue.ACTIVITIES:
			if def.id == hours[i]:
				schedule.hours[i] = def
	people.access.locked.assign(data.get("locks", {}))
	(main.runner as ScheduleRunner).overrides.assign(data.get("overrides", {}))
	(main.runner as ScheduleRunner).pinned.assign(data.get("pinned", {}))
	var shifts: Shifts = main.shifts
	var wanted: Dictionary = data.get("wanted", {})
	for role: StringName in wanted:
		for shift: StringName in wanted[role]:
			shifts.set_wanted(role, shift, wanted[role][shift], false)
	var routes: PatrolRoutes = main.routes
	for entry: Array in data.get("routes", []):
		var route := PatrolRoutes.Route.new()
		route.level = entry[0]
		route.points.assign(entry[1])
		route.guards = entry[2]
		route.name = entry[3]
		routes.routes.append(route)
	routes.changed.emit()
	var wear: Wear = main.wear
	wear.uses.assign(data.get("wear_uses", {}))
	for key: Vector2i in data.get("broken", {}):
		wear.break_object(key)
	var items: ItemStore = main.items
	items.held.assign(_items_in(data.get("items_held", {})))
	items.on_floor.assign(_items_in(data.get("items_floor", {})))
	items.changed.emit()
	items.floor_changed.emit()
	var money: Dictionary = data.get("money", {})
	var ledger: Ledger = main.ledger
	ledger.balance = money.get("balance", ledger.balance)
	ledger.sandbox = money.get("sandbox", false)
	ledger.today.assign(money.get("today", {}))
	ledger.yesterday.assign(money.get("yesterday", {}))
	ledger.closing.assign(money.get("closing", []))
	ledger.changed.emit()
	(main.workshop as Workshop).sold = data.get("sold", 0)
	var intake: Dictionary = data.get("intake", {})
	(main.intake as Intake).limit = intake.get("limit", 4)
	(main.intake as Intake).accepted.assign(intake.get("accepted", {}))
	var saved: Dictionary = data.get("standing", {})
	(main.standing as Standing).restore(saved)
	(main.intake as Intake).restore_arriving(intake.get("arriving", {}))
	people.assign_beds()
	(main.runner as ScheduleRunner).refresh()
	# Everyone back in the middle of what they were doing.
	var by_id: Dictionary[int, Person] = {}
	for person in people.people:
		by_id[person.id] = person
	for entry: Dictionary in data.get("people", []):
		var person: Person = by_id.get(entry["id"])
		if person != null:
			people.resume_doing(person, entry.get("doing", {}))
			(main.jobs as JobBoard).resume_work(person, entry.get("work", {}))


static func write(slot: String, data: Dictionary) -> Error:
	DirAccess.make_dir_recursive_absolute(FOLDER)
	var file := FileAccess.open(_path(slot), FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	data["saved_at"] = Time.get_datetime_string_from_system(false, true)
	file.store_var(data)
	return OK


## A save's data, or empty if there isn't one.
static func read(slot: String) -> Dictionary:
	if not FileAccess.file_exists(_path(slot)):
		return {}
	var file := FileAccess.open(_path(slot), FileAccess.READ)
	if file == null:
		return {}
	var data: Variant = file.get_var()
	return data if data is Dictionary and data.get("version", 0) <= VERSION else {}


## A line about a save, such as "Paying prison · Day 3 09:00 · 12
## prisoners · £21,400", or "Empty".
static func describe(data: Dictionary) -> String:
	if data.is_empty():
		return "Empty"
	var minutes: float = data.get("minutes", 0.0)
	var day := int(minutes / GameClock.MINUTES_PER_DAY) + 1
	var minute_of_day := int(minutes) % GameClock.MINUTES_PER_DAY
	var prisoners: int = data.get("people", []).filter(func(p: Dictionary) -> bool:
		return p["group"] == &"prisoner").size()
	return "%s · Day %d %02d:%02d · %d prisoners · %s" % [data.get("title", "Prison"), day,
			minute_of_day / 60, minute_of_day % 60, prisoners, Ledger.text(data.get("money", {}).get("balance", 0))]


static func _path(slot: String) -> String:
	return "%s/%s.save" % [FOLDER, slot]


static func _items_out(store: Dictionary) -> Dictionary:
	var out := {}
	for key: Variant in store:
		var counts := {}
		for item: ItemDef in store[key]:
			counts[item.id] = store[key][item]
		out[key] = counts
	return out


static func _items_in(saved: Dictionary) -> Dictionary:
	var out := {}
	for key: Variant in saved:
		var counts := {}
		for id: StringName in saved[key]:
			var def := PrisonCatalogue.item(id)
			if def != null:
				counts[def] = saved[key][id]
		if not counts.is_empty():
			out[key] = counts
	return out
