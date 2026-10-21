class_name Animals
extends Node
## Animals about the place (AnimalDef): people of their own group with no
## needs, so they walk the same paths. Those that roam wander from room to
## room every WANDER_MINUTES, liking outdoor rooms and laps: one may pad
## over to someone sitting down and curl up there. Everyone in a room with
## one cheers up a little, and tempers rise slower near them. Each keeps
## count of where it spends its time, for its favourite spot. Shared by any
## game: the museum's gallery cat and the hospital's therapy dog.

const WANDER_MINUTES := 10.0
const LAP_MINUTES := 15.0
## How much likelier an outdoor room is when wandering, and a lap.
const OUTDOOR_WEIGHT := 2.0
const LAP_ODDS := 0.4
## How close counts as on someone's lap, in tiles.
const LAP_REACH := 1.2
const LAP_MOODLET := &"cat_on_lap"

## An animal curled up with someone.
signal sat_with(animal: Person, person: Person)

var people: People
var defs: Array[AnimalDef] = []
var group: StringName = &"animal"
## Who they visit and calm.
var resident_group: StringName = &"prisoner"
## Words for a room, such as "the yard": (Room) -> String. Optional.
var room_words: Callable
## Animals kept on a lead -> who walks them, such as a dog's handler.
var leaders: Dictionary[Person, Person] = {}
var clock: GameClock:
	set(value):
		clock = value
		clock.hour_changed.connect(func(_hour: int) -> void: hourly())

var _rng := RandomNumberGenerator.new()


class AnimalBrain:
	extends Brain
	var animals: Animals

	func decide(_people: People, person: Person, _may_wander: bool) -> bool:
		animals.next(person)
		return true


func _ready() -> void:
	_rng.randomize()


func attach() -> void:
	var brain := AnimalBrain.new()
	brain.animals = self
	people.brains[group] = brain
	if not people.needs_off.has(group):
		people.needs_off.append(group)
	people.custom_bodies.append(func(person: Person) -> PackedScene:
		var def := def_of(person)
		return def.model if def != null else null)


func def_of(person: Person) -> AnimalDef:
	if person.group != group:
		return null
	return def_by_id(StringName(person.profile.get("animal", "")))


func def_by_id(id: StringName) -> AnimalDef:
	for def in defs:
		if def.id == id:
			return def
	return null


func all() -> Array[Person]:
	var out: Array[Person] = []
	for person in people.people:
		if person.group == group:
			out.append(person)
	return out


func of_kind(id: StringName) -> Array[Person]:
	return all().filter(func(p: Person) -> bool: return StringName(p.profile.get("animal", "")) == id)


## A new animal at a spot. Null if nobody could stand there.
func add(def: AnimalDef, level: int, spot: Vector2, animal_name := "") -> Person:
	if animal_name.is_empty():
		animal_name = random_name(def)
	var person := people.add_person(level, spot, animal_name, group)
	if person == null:
		return null
	person.traits.clear()
	person.profile["animal"] = String(def.id)
	person.activity = "Having a look round"
	return person


## A new animal in a room, on the free tile nearest its middle. Null if
## there's no room to stand.
func add_in(def: AnimalDef, level: int, room: Room, animal_name := "") -> Person:
	var cells := room.cells.duplicate()
	var middle := room.centre()
	cells.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return (Vector2(a) + Vector2(0.5, 0.5)).distance_squared_to(middle) < (Vector2(b) + Vector2(0.5, 0.5)).distance_squared_to(middle))
	for cell: Vector2i in cells:
		var spot := Vector2(cell) + Vector2(0.5, 0.5)
		if not is_nan(people.nav().height_at(level, spot)):
			return add(def, level, spot, animal_name)
	return null


func random_name(def: AnimalDef) -> String:
	var taken := all().map(func(p: Person) -> String: return p.name)
	var left := def.names.filter(func(n: String) -> bool: return not taken.has(n))
	if left.is_empty():
		return def.display_name
	return left[_rng.randi() % left.size()]


## What an animal does next: rest a while where it is, or wander on, to a
## lap now and then.
func next(animal: Person) -> void:
	var def := def_of(animal)
	var leader: Person = leaders.get(animal)
	if leader != null and people.people.has(leader):
		animal.timer = 1.0
		animal.activity = "With %s" % leader.name.get_slice(" ", 0)
		var beside := leader.flat() + Vector2(0.6, 0.0)
		if leader.level == animal.level and animal.flat().distance_to(beside) > 0.8:
			people.walk_to(animal, leader.level, beside, animal.activity)
		return
	if def == null or not def.roams or animal.has_meta(&"stay"):
		animal.timer = WANDER_MINUTES
		animal.activity = "In its cage" if def != null and not def.roams else "Sitting tight"
		return
	var lap: Person = animal.get_meta(&"lap", null)
	animal.remove_meta(&"lap")
	if lap != null and people.people.has(lap) and lap.sitting and lap.level == animal.level \
			and lap.flat().distance_to(animal.flat()) <= LAP_REACH + 0.5:
		animal.timer = LAP_MINUTES
		animal.activity = "Curled up with %s" % lap.name.get_slice(" ", 0)
		if def.id == &"cat":
			people.add_moodlet(lap, LAP_MOODLET)
		sat_with.emit(animal, lap)
		return
	if not animal.has_meta(&"rested"):
		animal.set_meta(&"rested", true)
		animal.timer = WANDER_MINUTES
		animal.activity = ["Washing its paws", "Having a stretch", "Watching the world go by"][_rng.randi() % 3]
		return
	animal.remove_meta(&"rested")
	if _rng.randf() < LAP_ODDS:
		var sitters := people.people.filter(func(p: Person) -> bool:
			return p.group == resident_group and p.sitting and not p.lying)
		sitters.shuffle()
		for sitter: Person in sitters.slice(0, 3):
			var spot: Vector2 = sitter.flat() + Vector2(0.4, 0.0)
			if people.walk_to(animal, sitter.level, spot, "Padding over to %s" % sitter.name.get_slice(" ", 0)):
				animal.set_meta(&"lap", sitter)
				return
	var rooms := people._all_rooms().filter(func(pair: Array) -> bool:
		return people.access.may_enter(group, pair[1]))
	if rooms.is_empty():
		animal.timer = WANDER_MINUTES
		return
	var weights := PackedFloat32Array()
	for pair: Array in rooms:
		weights.append(OUTDOOR_WEIGHT if not (pair[1] as Room).indoor else 1.0)
	for i in 3:
		var pair: Array = rooms[_rng.rand_weighted(weights)]
		var room: Room = pair[1]
		var cell: Vector2i = room.cells[_rng.randi() % room.cells.size()]
		if people.walk_to(animal, pair[0], Vector2(cell) + Vector2(0.5, 0.5), "Wandering"):
			return
	animal.timer = WANDER_MINUTES


## Each hour: those in a room with an animal cheer up, and each animal
## notes where it is.
func hourly() -> void:
	for animal in all():
		var def := def_of(animal)
		var here := people.room_of(animal)
		if here.is_empty() or def == null:
			continue
		var spots: Dictionary = animal.profile.get_or_add("spots", {})
		var words := _words_for(here[1])
		spots[words] = int(spots.get(words, 0)) + 1
		if def.calm_moodlet == &"":
			continue
		for person in people.people:
			if person.group == resident_group and People._same_place(here, people.room_of(person)):
				people.add_moodlet(person, def.calm_moodlet)


## How much an animal in their room slows someone's temper: the calmest
## one there, or 1.
func temper_scale(person: Person) -> float:
	var here := people.room_of(person)
	if here.is_empty():
		return 1.0
	var scale := 1.0
	for animal in all():
		var def := def_of(animal)
		if def != null and People._same_place(here, people.room_of(animal)):
			scale = minf(scale, def.temper_scale)
	return scale


## Where an animal has spent most hours, such as "the yard", or "".
func favourite_spot(animal: Person) -> String:
	var spots: Dictionary = animal.profile.get("spots", {})
	var best := ""
	for words: String in spots:
		if best.is_empty() or spots[words] > spots[best]:
			best = words
	return best


## "Biscuit the cat. Favourite spot: the yard." for the inspector, or "".
func words(person: Person) -> String:
	var def := def_of(person)
	if def == null:
		return ""
	var spot := favourite_spot(person)
	return "%s the %s.%s" % [person.name, def.display_name.to_lower(),
			" Favourite spot: %s." % spot if not spot.is_empty() else ""]


func _words_for(room: Room) -> String:
	if room_words.is_valid():
		return room_words.call(room)
	return "the %s" % String(room.type).replace("_", " ") if room.type != &"" else "a room"
