class_name Illnesses
extends Node
## Colds and the like going round, and two things that change how easily
## people catch them: fitness and age. Each hour, everyone close to someone
## ill may catch it, more in crowded rooms, less when fit or well fed. Being
## ill makes some needs run down faster, slows people and dampens their
## mood; it passes in a few days, or one once seen to. Illness never harms
## anyone's health. Fitness rises using exercise objects and slowly falls;
## age is picked on arrival. All kept in Person.profile. Shared by any game
## with residents.

## A room is crowded with fewer floor tiles each than this, and catching is
## then this much likelier.
const CROWD_TILES := 4.0
const CROWD_SCALE := 1.5
## Catching is this much likelier with each unit of (1.5 - fitness/100).
## Fit people catch at half the rate of the unfit.
const FIT_BASE := 1.5
## Well fed (a good meal in the last day): this much less likely.
const DIET_SCALE := 0.8
const DIET_MOODLETS: Array[StringName] = [&"good_meal", &"lovely_meal"]
## Fitness gained an hour exercising, lost a day, and where it cheers them.
const FIT_GAIN := 5.0
const FIT_FADE := 2.0
const FIT_MOOD_ABOVE := 60.0
const FIT_MOOD := 2.0
## Ages: the range on arrival, and the old and the young.
const AGE_LEAST := 18
const AGE_MOST := 75
const OLD_FROM := 60
const YOUNG_UNDER := 25
const OLD_PACE := 0.85
const OLD_CATCH := 1.3
const OLD_BOOK := 1.3
## So many ill at once is an outbreak.
const OUTBREAK := 3
## Game minutes between looks at who is exercising.
const TICK_MINUTES := 2.0

signal caught(person: Person, def: IllnessDef)
signal recovered(person: Person)
## Enough are ill at once to call it going round.
signal outbreak(ill: int)

var people: People
var defs: Array[IllnessDef] = []
## Groups who catch things, keep fit and have ages.
var groups: Array[StringName] = [&"prisoner"]
## Whether anyone catches anything (the Illness setting).
var enabled := true
var exercise_tags: Array[StringName] = [&"exercise"]
var book_tag: StringName = &"book"
## (person) -> float: more scales on catching, such as research cards.
var catch_scales: Array[Callable] = []
## (person) -> bool: whether someone ill passes it on, such as not once
## kept apart. Optional; always otherwise.
var spreads: Callable
## Words for where someone is, such as "in the canteen": (Person) ->
## String. Optional.
var place_words: Callable
var clock: GameClock:
	set(value):
		clock = value
		clock.minute_passed.connect(func(_minute: int) -> void:
			_wait -= 1.0
			if _wait <= 0.0:
				_wait = TICK_MINUTES
				tick(TICK_MINUTES))
		clock.hour_changed.connect(func(_hour: int) -> void: spread())
		clock.day_changed.connect(func(_day: int) -> void: new_day())

var _wait := 0.0
var _was_outbreak := false
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()


func attach() -> void:
	people.rate_scales.append(func(person: Person, need: StringName) -> float:
		var def := illness_of(person)
		return def.need_rates.get(need, 1.0) if def != null else 1.0)
	people.walk_scales.append(func(person: Person) -> float:
		var pace := 1.0
		var def := illness_of(person)
		if def != null:
			pace *= def.pace
		if is_old(person):
			pace *= OLD_PACE
		return pace)
	people.likings.append(func(person: Person, key: StringName) -> float:
		return OLD_BOOK if key == book_tag and is_old(person) else 1.0)
	people.mood_extras.append(mood_parts)
	people.person_added.connect(func(person: Person) -> void:
		if groups.has(person.group) and not person.profile.has("age"):
			arrive(person))
	fill_in()


## Gives anyone without one an age and fitness, such as from an older save.
func fill_in() -> void:
	for person in people.people:
		if groups.has(person.group) and not person.profile.has("age"):
			set_up(person)


## A new arrival: an age, some fitness, and maybe a cold they bring in.
func arrive(person: Person) -> void:
	set_up(person)
	if not enabled:
		return
	for def in defs:
		if _rng.randf() < def.arrival_chance:
			catch(person, def)
			break


func set_up(person: Person) -> void:
	person.profile["age"] = _rng.randi_range(AGE_LEAST, AGE_MOST)
	person.profile["fitness"] = snappedf(_rng.randf_range(20.0, 70.0), 1.0)


func age(person: Person) -> int:
	return int(person.profile.get("age", 35))


func is_old(person: Person) -> bool:
	return person.profile.has("age") and age(person) >= OLD_FROM


func is_young(person: Person) -> bool:
	return person.profile.has("age") and age(person) < YOUNG_UNDER


func fitness(person: Person) -> float:
	return person.profile.get("fitness", 50.0)


func illness_of(person: Person) -> IllnessDef:
	var id: String = person.profile.get("illness", "")
	if id.is_empty():
		return null
	for def in defs:
		if String(def.id) == id:
			return def
	return null


func days_left(person: Person) -> float:
	return person.profile.get("ill_days", 0.0)


func is_treated(person: Person) -> bool:
	return person.profile.get("treated", false)


func ill() -> Array[Person]:
	var out: Array[Person] = []
	for person in people.people:
		if illness_of(person) != null:
			out.append(person)
	return out


func catch(person: Person, def: IllnessDef) -> void:
	if illness_of(person) != null:
		return
	person.profile["illness"] = String(def.id)
	person.profile["ill_days"] = snappedf(_rng.randf_range(def.days_least, def.days_most), 0.5)
	person.profile["treated"] = false
	caught.emit(person, def)
	var count := ill().size()
	if count >= OUTBREAK and not _was_outbreak:
		_was_outbreak = true
		outbreak.emit(count)


## Seen to: it passes sooner.
func treat(person: Person) -> void:
	var def := illness_of(person)
	if def == null or is_treated(person):
		return
	person.profile["treated"] = true
	person.profile["ill_days"] = minf(days_left(person), def.treated_days)


func recover(person: Person) -> void:
	for key in ["illness", "ill_days", "treated", "caught_from"]:
		person.profile.erase(key)
	recovered.emit(person)


## How likely someone is to catch something, against the plain chance.
func catch_scale(person: Person, crowded: bool) -> float:
	var scale := clampf(FIT_BASE - fitness(person) / 100.0, 0.5, 1.5)
	if crowded:
		scale *= CROWD_SCALE
	if DIET_MOODLETS.any(func(id: StringName) -> bool: return person.moodlets.has(id)):
		scale *= DIET_SCALE
	if is_old(person):
		scale *= OLD_CATCH
	for extra in catch_scales:
		scale *= extra.call(person)
	return scale


## The hour's catching: everyone near someone ill rolls for it.
func spread() -> void:
	if not enabled or people == null:
		return
	var crowds := _crowded_rooms()
	for sick in ill():
		if spreads.is_valid() and not spreads.call(sick):
			continue
		var def := illness_of(sick)
		for other in people.nearby(sick, def.spread_radius):
			if not groups.has(other.group) or illness_of(other) != null:
				continue
			if other.flat().distance_to(sick.flat()) > def.spread_radius:
				continue
			var here := people.room_of(other)
			var crowded := not here.is_empty() and crowds.has(here[1])
			if _rng.randf() < def.spread_chance * catch_scale(other, crowded):
				var where: String = place_words.call(other) if place_words.is_valid() else ""
				other.profile["caught_from"] = sick.name + (" " + where if not where.is_empty() else "")
				catch(other, def)


## Rooms with too many people for their floor.
func _crowded_rooms() -> Dictionary[Object, bool]:
	var counts: Dictionary[Object, int] = {}
	for person in people.people:
		var here := people.room_of(person)
		if not here.is_empty():
			counts[here[1]] = counts.get(here[1], 0) + 1
	var out: Dictionary[Object, bool] = {}
	for room: Object in counts:
		if counts[room] > 1 and (room as Room).area / counts[room] < CROWD_TILES:
			out[room] = true
	return out


## A day passes: illness wears off, fitness fades a little.
func new_day() -> void:
	for person in people.people:
		if not groups.has(person.group):
			continue
		if illness_of(person) != null:
			person.profile["ill_days"] = days_left(person) - 1.0
			if days_left(person) <= 0.0:
				recover(person)
		if person.profile.has("fitness"):
			person.profile["fitness"] = maxf(0.0, fitness(person) - FIT_FADE)
	if ill().size() < OUTBREAK:
		_was_outbreak = false


## Those exercising get fitter.
func tick(minutes: float) -> void:
	if people == null:
		return
	for person in people.people:
		if not groups.has(person.group) or person.state != Person.State.USING or not person.has_object():
			continue
		var placed := people.target_object(person)
		if placed != null and placed.def.tags.any(func(tag: StringName) -> bool: return exercise_tags.has(tag)):
			person.profile["fitness"] = minf(100.0, fitness(person) + FIT_GAIN * minutes / 60.0)


## "Under the weather" while ill, "Feeling fit" when fit.
func mood_parts(person: Person, _here: Array) -> Array:
	var out: Array = []
	var def := illness_of(person)
	if def != null:
		out.append([def.mood_words, def.mood])
	if person.profile.has("fitness") and fitness(person) > FIT_MOOD_ABOVE:
		out.append(["Feeling fit", FIT_MOOD])
	return out


## "Cold, 2 days left (seen to)" and "Age 47 · fitness 64" for the
## inspector.
func words(person: Person) -> String:
	if not person.profile.has("age"):
		return ""
	var lines: Array[String] = []
	var def := illness_of(person)
	if def != null:
		var days := ceili(days_left(person))
		lines.append("%s, %d day%s left%s" % [def.display_name, days, "" if days == 1 else "s",
				" (seen to)" if is_treated(person) else ""])
		if person.profile.has("caught_from"):
			lines.append("Caught from %s" % person.profile["caught_from"])
	lines.append("Age %d · fitness %d" % [age(person), roundi(fitness(person))])
	return "\n".join(lines)
