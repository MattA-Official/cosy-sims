class_name Misconduct
extends Node
## Unhappy prisoners acting up, a rung at a time: grumbling, mischief,
## vandalism (and from later steps fights and escape plans). Temper builds
## while mood is low; once a game hour each prisoner may act on it, less
## likely with a guard close by. Worse rungs warn first with a bubble over
## their head, and a guard turning up or their mood lifting calls it off.
## Every offence goes on their record with the reason, such as "broke the
## TV (Missed a meal)".

## How close a guard must be to count as watching, in tiles.
const WATCH_DISTANCE := 3.0
## Who sees it happen, in tiles.
const WITNESS_DISTANCE := 5.0
## How long grumbling and mischief last, in game minutes.
const GRUMBLE_MINUTES := 30.0
const GRUMBLE_PACE := 0.8
const TRUANT_MINUTES := 60.0
## How far someone goes to find something to break, in tiles.
const VANDAL_REACH := 8.0

signal acted(person: Person, rung: MisconductDef, words: String)

var people: People
var model: MisconductModel
## Rungs in order, mildest first.
var rungs: Array[MisconductDef] = []
var wear: Wear
var fights: Fights
var items: ItemStore
## Optional: somewhere seen lately counts as watched too.
var security: Security
var prisoner_group: StringName = &"prisoner"
var guard_role: StringName = &"guard"
## Off for none of it, such as in a sandbox.
var enabled := true
## (person) -> float: anything else that cools or heats tempers, such as
## Calm Minds therapy. Multiplied together.
var temper_scales: Array[Callable] = []
var clock: GameClock:
	set(value):
		clock = value
		clock.minute_passed.connect(func(_minute: int) -> void: tick(1.0))

var _rng := RandomNumberGenerator.new()


func start() -> void:
	people.deciders.append(_up_to_no_good)


func rung(id: StringName) -> MisconductDef:
	for def in rungs:
		if def.id == id:
			return def
	return null


## A game minute for everyone: temper, warnings and rolls.
func tick(minutes: float) -> void:
	var minute := clock.minute_of_day() if clock != null else 0
	for person in people.people.duplicate():
		if person.group != prisoner_group:
			continue
		_count_down(person, minutes)
		if not enabled or person.led or person.going_home or person.sitting:
			continue
		person.temper = model.temper_after(person.temper, person.mood, minutes / 60.0, _temper_scale(person))
		for def in rungs:
			if def.days_below > 0.0:
				person.minutes_below[def.id] = person.minutes_below.get(def.id, 0.0) + minutes \
						if person.mood < def.mood_below else 0.0
		if person.warning != &"":
			_warn(person, minutes)
		elif person.truant_minutes <= 0.0 and (minute + person.id) % 60 == 0:
			roll(person)


## The hour's roll: maybe they act up, warning first for worse rungs.
## Returns the rung picked, or null.
func roll(person: Person, force := false) -> MisconductDef:
	if not force and _rng.randf() >= model.chance(person.temper, watched(person)):
		return null
	var trait_ids: Array[StringName] = []
	for t in person.traits:
		trait_ids.append(t.id)
	var def := model.pick(rungs, person.mood, person.minutes_below, trait_ids, _rng)
	if def == null:
		return null
	if def.warning_minutes > 0.0:
		person.warning = def.id
		person.warning_minutes = def.warning_minutes
		_say(person, words_over_head(def, person), def.warning_minutes)
	else:
		act(person, def)
	return def


## Whether a guard is close enough to see them.
func watched(person: Person) -> bool:
	if security != null and security.watched(person.level, person.flat()):
		return true
	for other in people.nearby(person, WATCH_DISTANCE):
		if other.role == guard_role and not other.going_home and other.flat().distance_to(person.flat()) <= WATCH_DISTANCE:
			return true
	return false


## The worst thing on someone's mind, such as "Missed a meal".
static func worry(person: Person) -> String:
	var worst: Array = []
	for part: Array in person.mood_parts:
		if part[1] < 0.0 and (worst.is_empty() or part[1] < worst[1]):
			worst = part
	return worst[0] if not worst.is_empty() else "Fed up"


static func words_over_head(def: MisconductDef, person: Person) -> String:
	return def.bubble % worry(person) if def.bubble.contains("%s") else def.bubble


## Does the rung's deed now.
func act(person: Person, def: MisconductDef) -> void:
	person.warning = &""
	person.warning_minutes = 0.0
	var why := worry(person)
	var what := ""
	match def.id:
		&"grumble":
			_say(person, words_over_head(def, person), GRUMBLE_MINUTES)
			person.pace = GRUMBLE_PACE
		&"vandalism":
			what = _break_something(person)
			if what.is_empty():
				what = _mischief(person)
		&"fight":
			var other := fights.target_for(person) if fights != null else null
			if other != null and fights.begin(person, other) != null:
				what = "started a fight with %s" % other.name.get_slice(" ", 0)
			else:
				what = _break_something(person)
				if what.is_empty():
					what = _mischief(person)
		_:
			what = _mischief(person)
	person.temper = maxf(0.0, person.temper - model.after_acting)
	var words := "%s (%s)" % [what, why.to_lower()] if not what.is_empty() else why
	if def.points > 0:
		person.record.append([clock.day() if clock != null else 1, def.id, words])
	if def.witness_moodlet != &"":
		for other in people.nearby(person, WITNESS_DISTANCE):
			if other.group == prisoner_group:
				people.add_moodlet(other, def.witness_moodlet)
	acted.emit(person, def, words)


func _warn(person: Person, minutes: float) -> void:
	var def := rung(person.warning)
	if def == null or watched(person) or person.mood >= def.mood_below:
		person.warning = &""
		person.bubble = ""
		person.bubble_minutes = 0.0
		return
	person.warning_minutes -= minutes
	if person.warning_minutes <= 0.0:
		act(person, def)


func _count_down(person: Person, minutes: float) -> void:
	if person.bubble_minutes > 0.0:
		person.bubble_minutes -= minutes
		if person.bubble_minutes <= 0.0 and person.warning == &"":
			person.bubble = ""
			person.pace = 1.0
	if person.truant_minutes > 0.0:
		person.truant_minutes = maxf(0.0, person.truant_minutes - minutes)


func _say(person: Person, words: String, minutes: float) -> void:
	person.bubble = words
	person.bubble_minutes = minutes


func _temper_scale(person: Person) -> float:
	var scale := 1.0
	for t in person.traits:
		scale *= t.temper_scale
	var category: CategoryDef = people.categories.get(person.category)
	if category != null:
		scale *= category.temper_scale
	for extra in temper_scales:
		scale *= extra.call(person)
	return scale


## Off the timetable for a while, dropping litter as they go.
func _mischief(person: Person) -> String:
	person.truant_minutes = TRUANT_MINUTES
	person.out_of_place = true
	people.stop(person)
	if items != null and not people.litter.is_empty():
		var tile := Vector2i(person.flat().floor())
		items.drop_on_floor(Vector3i(person.level, tile.x, tile.y), people.litter[_rng.randi() % people.litter.size()], 1)
	return "skived off and dropped litter"


## Breaks the nearest thing that can break, and says what it was.
func _break_something(person: Person) -> String:
	if wear == null:
		return ""
	var map: BuildingMap = people.building.levels.get(person.level)
	if map == null:
		return ""
	var best: BuildingMap.PlacedObject = null
	for placed: BuildingMap.PlacedObject in map.objects.values():
		if placed.def.uses_before_breaking <= 0 or wear.is_broken(Vector2i(person.level, placed.id)):
			continue
		var distance := placed.centre.distance_to(person.flat())
		if distance <= VANDAL_REACH and (best == null or distance < best.centre.distance_to(person.flat())):
			best = placed
	if best == null:
		return ""
	wear.break_object(Vector2i(person.level, best.id))
	var room := map.room_at_point(best.centre)
	var room_type := people.room_type(room.type) if room != null else null
	return "broke the %s%s" % [best.def.display_name.to_lower(),
			" in the %s" % room_type.display_name.to_lower() if room_type != null else ""]


## While up to no good they ignore the timetable and wander.
func _up_to_no_good(person: Person, _may_wander: bool) -> bool:
	if person.truant_minutes <= 0.0 or person.group != prisoner_group:
		return false
	people.wander(person)
	person.reason = "Up to no good: %s" % worry(person).to_lower()
	return true
