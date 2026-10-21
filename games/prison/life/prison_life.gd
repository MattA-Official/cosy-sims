class_name PrisonLife
## Wires M11's prisoner life into the prison: friends and rivals so far.
## Each system keeps to its own node; this only connects them.

## Bond changes from things that happen.
const FIGHT_BOND := -30.0
const QUIET_ROOM_BOND := 10.0
const TRADE_BOND := 3.0


static func setup(main: Node) -> void:
	_relationships(main)
	_rapport(main)


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
