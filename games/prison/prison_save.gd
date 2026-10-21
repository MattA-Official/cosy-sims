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
		# Staff on their way home are gone; prisoners going home set off again.
		if person.going_home and person.group != &"prisoner":
			continue
		var traits: Array = []
		for t in person.traits:
			traits.append(t.id)
		everyone.append({
			"id": person.id, "name": person.name, "look_seed": person.look_seed, "group": person.group, "role": person.role,
			"shift": person.shift, "programme": person.programme, "category": person.category,
			# Off whatever they were using, where they stood to use it.
			"level": person.level,
			"position": person.stand_spot if person.state == Person.State.USING else person.position, "needs": person.needs.duplicate(),
			"mood": person.mood, "moodlets": person.moodlets.duplicate(), "traits": traits,
			"temper": person.temper, "minutes_below": person.minutes_below.duplicate(),
			"record": person.record.duplicate(true), "warning": person.warning,
			"warning_minutes": person.warning_minutes, "bubble": person.bubble,
			"bubble_minutes": person.bubble_minutes, "truant_minutes": person.truant_minutes,
			"pace": person.pace, "health": person.health, "restrictions": person.restrictions.duplicate(),
			"points": person.points, "quiet_room_hours": person.quiet_room_hours, "lying": person.lying,
			"bed_in_infirmary": (main.infirmary as Infirmary).beds.get(person, Vector2i(-1, -1)), "pocket": person.pocket.map(func(def: ItemDef) -> StringName: return def.id),
			"profile": person.profile.duplicate(true), "bed": person.bed,
			"doing": people.doing_of(person), "work": (main.jobs as JobBoard).work_of(person),
		})
	var hours: Array = []
	for def in (main.schedule as Schedule).hours:
		hours.append(def.id if def != null else &"")
	var category_hours: Dictionary = {}
	for key: StringName in (main.runner as ScheduleRunner).schedules:
		if String(key).contains("/"):
			category_hours[key] = (main.runner as ScheduleRunner).schedules[key].hours.map(
					func(def: ActivityDef) -> StringName: return def.id if def != null else &"")
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
		"items_hidden": _items_out((main.items as ItemStore).hidden),
		"stash_owner": (main.items as ItemStore).stash_owner.duplicate(),
		"at_large": (main.escapes as Escapes).at_large.duplicate(true),
		"sit_ins": (main.sit_ins as SitIns).sit_ins.map(func(sit_in: SitIns.SitIn) -> Dictionary:
			return {"level": sit_in.level, "cell": sit_in.room.cells[0], "cause": sit_in.cause,
					"demand": sit_in.demand, "hint": sit_in.hint, "minutes": sit_in.minutes, "talked": sit_in.talked,
					"members": sit_in.members.map(func(p: Person) -> int: return p.id)}),
		"missing_tools": (main.contraband as Contraband).missing.map(func(entry: Array) -> Array:
			return [entry[0], (entry[1] as Room).cells[0], (entry[2] as ItemDef).id]),
		"security": {"today": (main.security as Security).today.duplicate(),
				"yesterday": (main.security as Security).yesterday.duplicate(),
				"alerts": (main.security as Security).alerts.duplicate(true)},
		"policies": {"privilege_days": (main.consequences as Consequences).privilege_days,
				"quiet_room": (main.consequences as Consequences).quiet_room_on},
		"deaths": (main.infirmary as Infirmary).deaths,
		"course_places": (main.courses as Courses).places.duplicate(),
		"parole": {"queue": (main.parole as Parole).queue.map(func(p: Person) -> int: return p.id),
				"today": (main.parole as Parole).today.duplicate(true),
				"yesterday": (main.parole as Parole).yesterday.duplicate(true),
				"granted": (main.parole as Parole).granted_total},
		"sentence_length": (main.sentences as Sentences).length,
		"release": {"alumni": (main.release as Release).alumni.duplicate(true),
				"postcards": (main.release as Release).postcards.duplicate(true),
				"today": (main.release as Release).today_lines.duplicate(),
				"yesterday": (main.release as Release).yesterday_lines.duplicate()},
		"searching": {"policy": (main.searching as Searching).random_per_day,
				"shakedown": (main.searching as Searching).shakedown_tonight,
				"today": (main.searching as Searching).searches_today,
				"found": (main.searching as Searching).found_today.duplicate()},
		"timetable": hours,
		"category_timetables": category_hours,
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
		person.look_seed = entry.get("look_seed", -1)
		person.needs.assign(entry["needs"])
		person.mood = entry["mood"]
		person.moodlets.assign(entry["moodlets"])
		# Saves from before misconduct have none of this.
		person.temper = entry.get("temper", 0.0)
		person.minutes_below.assign(entry.get("minutes_below", {}))
		person.record.assign(entry.get("record", []))
		person.warning = StringName(entry.get("warning", ""))
		person.warning_minutes = entry.get("warning_minutes", 0.0)
		person.bubble = entry.get("bubble", "")
		person.bubble_minutes = entry.get("bubble_minutes", 0.0)
		person.truant_minutes = entry.get("truant_minutes", 0.0)
		# Staff run only while chasing, which isn't saved.
		person.pace = entry.get("pace", 1.0) if person.role == &"" else 1.0
		person.health = entry.get("health", 100.0)
		person.restrictions.assign(entry.get("restrictions", {}))
		person.points = entry.get("points", 0.0)
		person.quiet_room_hours = entry.get("quiet_room_hours", 0.0)
		person.lying = entry.get("lying", false)
		var bed: Vector2i = entry.get("bed_in_infirmary", Vector2i(-1, -1))
		if bed.x != -1:
			(main.infirmary as Infirmary).beds[person] = bed
		person.pocket.clear()
		for id: StringName in entry.get("pocket", []):
			var def := PrisonCatalogue.item(id)
			if def != null:
				person.pocket.append(def)
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
	var category_hours: Dictionary = data.get("category_timetables", {})
	for key: StringName in category_hours:
		var parts := String(key).split("/")
		var split := (main.runner as ScheduleRunner).split(StringName(parts[0]), StringName(parts[1]))
		var saved_hours: Array = category_hours[key]
		for i in mini(saved_hours.size(), split.hours.size()):
			for def in PrisonCatalogue.ACTIVITIES:
				if def.id == saved_hours[i]:
					split.hours[i] = def
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
	items.hidden.assign(_items_in(data.get("items_hidden", {})))
	items.stash_owner.assign(data.get("stash_owner", {}))
	(main.escapes as Escapes).at_large.assign(data.get("at_large", []))
	for entry: Array in data.get("missing_tools", []):
		var tool_map: BuildingMap = (main.building as Building).levels.get(entry[0])
		var tool_room := tool_map.room_at(entry[1]) if tool_map != null else null
		var tool := (main.contraband as Contraband).item(entry[2])
		if tool_room != null and tool != null:
			(main.contraband as Contraband).missing.append([entry[0], tool_room, tool])
	var security_data: Dictionary = data.get("security", {})
	(main.security as Security).today.assign(security_data.get("today", {}))
	(main.security as Security).yesterday.assign(security_data.get("yesterday", {}))
	(main.security as Security).alerts.assign(security_data.get("alerts", []))
	var policies: Dictionary = data.get("policies", {})
	(main.consequences as Consequences).privilege_days = policies.get("privilege_days", 2.0)
	(main.consequences as Consequences).quiet_room_on = policies.get("quiet_room", true)
	var searching: Dictionary = data.get("searching", {})
	(main.searching as Searching).random_per_day = searching.get("policy", 2)
	(main.searching as Searching).shakedown_tonight = searching.get("shakedown", false)
	(main.infirmary as Infirmary).deaths = data.get("deaths", false)
	(main.searching as Searching).searches_today = searching.get("today", 0)
	(main.searching as Searching).found_today.assign(searching.get("found", []))
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
	(main.courses as Courses).places.assign(data.get("course_places", {}))
	var parole_data: Dictionary = data.get("parole", {})
	var parole: Parole = main.parole
	parole.today = parole_data.get("today", [])
	parole.yesterday = parole_data.get("yesterday", [])
	parole.granted_total = parole_data.get("granted", 0)
	for id: int in parole_data.get("queue", []):
		if by_id.has(id):
			parole.queue.append(by_id[id])
	(main.sentences as Sentences).length = data.get("sentence_length", Sentences.Length.NORMAL)
	var release_data: Dictionary = data.get("release", {})
	var release: Release = main.release
	release.alumni.assign(release_data.get("alumni", []))
	release.postcards.assign(release_data.get("postcards", []))
	release.today_lines.assign(release_data.get("today", []))
	release.yesterday_lines.assign(release_data.get("yesterday", []))
	for entry: Dictionary in data.get("sit_ins", []):
		var map: BuildingMap = (main.building as Building).levels.get(entry["level"])
		var room := map.room_at(entry["cell"]) if map != null else null
		if room == null:
			continue
		var sit_in := SitIns.SitIn.new()
		sit_in.level = entry["level"]
		sit_in.room = room
		sit_in.cause = entry["cause"]
		sit_in.demand = entry["demand"]
		sit_in.hint = entry["hint"]
		sit_in.minutes = entry["minutes"]
		sit_in.talked = entry["talked"]
		for id: int in entry["members"]:
			var member: Person = by_id.get(id)
			if member != null:
				member.sitting = true
				sit_in.members.append(member)
		(main.sit_ins as SitIns).sit_ins.append(sit_in)


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
