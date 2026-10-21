class_name Hobbies
extends Node
## What people love doing. Each resident is given one or two hobbies at
## arrival (likelier when a trait suits one). They like their hobby's
## objects more, doing it fills Fun twice as fast, cheers them up and
## builds a skill, and going three days without it makes them miss it. In
## a Clubs block they go and do it, and three or more in one room with a
## skilled leader make a club. Now and then they finish something (a
## painting, a scarf). Everything is kept in Person.profile, so it saves
## with the person. Shared by any game with residents.

## How much more they like their hobby's objects.
const LIKE := 1.5
## Skill gained a game hour doing it, and the most.
const SKILL_PER_HOUR := 0.2
const MOST_SKILL := 10.0
## Skill they may already have on arrival.
const START_SKILL_MOST := 6.0
## Days without it before they miss it, and the mood part then.
const MISS_DAYS := 3
const MISS_MOOD := -3.0
## A club needs this many doing the hobby in one room, one with LEADER_SKILL.
const CLUB_LEAST := 3
const LEADER_SKILL := 5.0
## Odds of a second hobby, and how much a suiting trait weighs.
const SECOND_ODDS := 0.4
const TRAIT_WEIGHT := 4.0
## Hours of a hobby to finish something, for hobbies that make things.
const MAKE_HOURS := 6.0
## Hours an evening with a hobby kit in their cell counts for.
const HOME_HOURS := 2.0
## Game minutes between looks at who is doing what.
const TICK_MINUTES := 2.0

## A club met this hour: the hobby, everyone there and the leader.
signal club_met(hobby: HobbyDef, members: Array[Person], leader: Person)
## Someone finished something, such as a painting.
signal made(person: Person, hobby: HobbyDef)

var people: People
var defs: Array[HobbyDef] = []
## Groups who have hobbies.
var groups: Array[StringName] = [&"prisoner"]
## The need hobbies fill (Fun), and the timetable block for clubs.
var fun_need: StringName = &"recreation"
var club_block: StringName = &"club"
## Whether clubs may meet, such as once a research card allows them.
## Optional; always otherwise.
var clubs_allowed: Callable
var clock: GameClock:
	set(value):
		clock = value
		clock.minute_passed.connect(func(_minute: int) -> void:
			_wait -= 1.0
			if _wait <= 0.0:
				_wait = TICK_MINUTES
				tick(TICK_MINUTES))
		clock.hour_changed.connect(func(_hour: int) -> void: run_clubs())

var _wait := 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()


## Hooks into People: liking, filling, mood, clubs, and hobbies for new
## arrivals.
func attach() -> void:
	people.likings.append(liking)
	people.fill_scales.append(fill_scale)
	people.mood_extras.append(mood_parts)
	people.deciders.append(decide)
	people.person_added.connect(func(person: Person) -> void:
		if groups.has(person.group) and not person.profile.has("hobbies"):
			pick(person))
	fill_in()


## Gives hobbies to anyone without, such as people from an older save.
func fill_in() -> void:
	for person in people.people:
		if groups.has(person.group) and not person.profile.has("hobbies"):
			pick(person)


func def_of(id: StringName) -> HobbyDef:
	for def in defs:
		if def.id == id:
			return def
	return null


## Gives someone one hobby, sometimes two, weighted towards ones their
## traits suit, with a little skill to start.
func pick(person: Person) -> void:
	var trait_ids: Array[StringName] = []
	for t in person.traits:
		trait_ids.append(t.id)
	var left := defs.duplicate()
	var chosen: Array[String] = []
	var count := 2 if _rng.randf() < SECOND_ODDS else 1
	while chosen.size() < count and not left.is_empty():
		var weights := PackedFloat32Array()
		for def: HobbyDef in left:
			var suits := def.likes_traits.any(func(id: StringName) -> bool: return trait_ids.has(id))
			weights.append(1.0 + TRAIT_WEIGHT if suits else 1.0)
		var def: HobbyDef = left[_rng.rand_weighted(weights)]
		left.erase(def)
		chosen.append(String(def.id))
	set_hobbies(person, chosen)
	for id in chosen:
		_skills(person)[id] = snappedf(_rng.randf_range(0.0, START_SKILL_MOST), 0.1)


func set_hobbies(person: Person, ids: Array) -> void:
	var list: Array[String] = []
	for id in ids:
		list.append(String(id))
	person.profile["hobbies"] = list
	var last := _last_days(person)
	for id in list:
		if not last.has(id):
			last[id] = _today()


func hobbies_of(person: Person) -> Array[HobbyDef]:
	var out: Array[HobbyDef] = []
	for id: String in person.profile.get("hobbies", []):
		var def := def_of(StringName(id))
		if def != null:
			out.append(def)
	return out


func skill(person: Person, id: StringName) -> float:
	return _skills(person).get(String(id), 0.0)


func set_skill(person: Person, id: StringName, amount: float) -> void:
	_skills(person)[String(id)] = clampf(amount, 0.0, MOST_SKILL)


## Their hobby that an object tag is for, or null.
func hobby_for_tag(person: Person, tag: StringName) -> HobbyDef:
	for def in hobbies_of(person):
		if def.object_tags.has(tag):
			return def
	return null


## The hobby they are doing right now, using one of its objects, or null.
func doing(person: Person) -> HobbyDef:
	if person.state != Person.State.USING or not person.has_object():
		return null
	var placed := people.target_object(person)
	if placed == null:
		return null
	for tag in placed.def.tags:
		var def := hobby_for_tag(person, tag)
		if def != null:
			return def
	return null


## For People.likings: their hobby's objects score twice.
func liking(person: Person, key: StringName) -> float:
	return LIKE if hobby_for_tag(person, key) != null else 1.0


## For People.fill_scales: Fun fills faster doing a hobby.
func fill_scale(person: Person, need: StringName, placed: BuildingMap.PlacedObject) -> float:
	if need != fun_need or placed == null:
		return 1.0
	for tag in placed.def.tags:
		var def := hobby_for_tag(person, tag)
		if def != null:
			return def.fill_scale
	return 1.0


## Those doing a hobby gain skill, cheer up, remember the day and work
## towards finishing something.
func tick(minutes: float) -> void:
	if people == null:
		return
	var hours := minutes / 60.0
	for person in people.people:
		if not groups.has(person.group):
			continue
		var def := doing(person)
		if def == null:
			continue
		var id := String(def.id)
		set_skill(person, def.id, skill(person, def.id) + SKILL_PER_HOUR * hours)
		_last_days(person)[id] = _today()
		if person.moodlets.get(&"did_my_hobby", 0.0) < 60.0:
			people.add_moodlet(person, &"did_my_hobby")
		if def.makes_item != &"":
			var making: Dictionary = person.profile.get_or_add("hobby_making", {})
			making[id] = making.get(id, 0.0) + hours
			if making[id] >= MAKE_HOURS:
				making[id] = 0.0
				made.emit(person, def)


## An evening of their hobbies in their cell, with a kit from the shop:
## they don't miss them and get a little better.
func did_at_home(person: Person) -> void:
	for def in hobbies_of(person):
		_last_days(person)[String(def.id)] = _today()
		set_skill(person, def.id, skill(person, def.id) + SKILL_PER_HOUR * HOME_HOURS)


## "Misses chess" for each hobby not done for MISS_DAYS, for
## People.mood_extras.
func mood_parts(person: Person, _here: Array) -> Array:
	var out: Array = []
	if not groups.has(person.group):
		return out
	var last := _last_days(person)
	for def in hobbies_of(person):
		if _today() - int(last.get(String(def.id), _today())) >= MISS_DAYS:
			out.append(["Misses %s" % def.display_name.to_lower(), MISS_MOOD])
	return out


## In a Clubs block, people go and do one of their hobbies once their
## pressing needs are seen to. For People.deciders.
func decide(person: Person, _may_wander: bool) -> bool:
	if not groups.has(person.group) or person.block == null or person.block.id != club_block:
		return false
	if person.job != null or people._urgent_need(person) != &"":
		return false
	for def in hobbies_of(person):
		if people.seek(person, def.object_tags, fun_need):
			person.reason = "Going to do some %s" % def.display_name.to_lower()
			return true
	return false


## Each hour of a Clubs block: three or more doing the same hobby in one
## room, one of them skilled enough to lead, is a club. Returns the clubs
## that met, as [hobby, members, leader].
func run_clubs() -> Array:
	var met: Array = []
	if people == null or (clubs_allowed.is_valid() and not clubs_allowed.call()):
		return met
	# Room and hobby -> [hobby, room, members].
	var groups_found: Dictionary[String, Array] = {}
	for person in people.people:
		if not groups.has(person.group) or person.block == null or person.block.id != club_block:
			continue
		var def := doing(person)
		var here := people.room_of(person)
		if def == null or here.is_empty():
			continue
		var key := "%d:%d:%s" % [here[0], (here[1] as Object).get_instance_id(), def.id]
		var found: Array = groups_found.get_or_add(key, [def, []])
		(found[1] as Array).append(person)
	for found: Array in groups_found.values():
		var members: Array[Person] = []
		members.assign(found[1])
		if members.size() < CLUB_LEAST:
			continue
		var def: HobbyDef = found[0]
		var leader: Person = null
		for member in members:
			if skill(member, def.id) >= LEADER_SKILL and (leader == null or skill(member, def.id) > skill(leader, def.id)):
				leader = member
		if leader == null:
			continue
		met.append([def, members, leader])
		club_met.emit(def, members, leader)
	return met


## "Hobbies: Chess 4.2, Painting 1.0" for the inspector, or "".
func words(person: Person) -> String:
	var parts: Array[String] = []
	for def in hobbies_of(person):
		parts.append("%s %s" % [def.display_name, _bar(skill(person, def.id))])
	return "Hobbies: %s" % ", ".join(parts) if not parts.is_empty() else ""


static func _bar(amount: float) -> String:
	var filled := clampi(roundi(amount / 2.0), 0, 5)
	return "●".repeat(filled) + "○".repeat(5 - filled)


func _skills(person: Person) -> Dictionary:
	return person.profile.get_or_add("hobby_skill", {})


func _last_days(person: Person) -> Dictionary:
	return person.profile.get_or_add("hobby_day", {})


func _today() -> int:
	return clock.day() if clock != null else 0
