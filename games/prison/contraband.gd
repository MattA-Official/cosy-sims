class_name Contraband
extends Node
## Things prisoners shouldn't have: a spoon from the canteen, a rolling pin
## from the kitchen, a screwdriver from the workshop. Ordinary items with
## `pocketed_from` set. A prisoner up to no good (mood low enough for
## mischief) or light-fingered may pocket one on finishing with an object
## when no staff are close, and hides it in their own cell at the next
## chance, in whatever hides things best. Treats get eaten when they're
## feeling low. Searches (see Searching) find them.

## Chance to pocket something on finishing with an object, and for the
## light-fingered.
const POCKET_CHANCE := 0.05
const LIGHT_FINGERED_CHANCE := 0.15
## Staff this close see it, in tiles.
const SEEN_WITHIN := 3.0
## Treats are eaten once mood falls below this.
const TREAT_MOOD := 40.0

signal pocketed(person: Person, item: ItemDef)

var people: People
var items: ItemStore
var misconduct: Misconduct
## Every item that can be contraband.
var catalogue: Array[ItemDef] = []
var prisoner_group: StringName = &"prisoner"
var light_fingered: StringName = &"light_fingered"
## Off for none of it.
var enabled := true
var clock: GameClock:
	set(value):
		clock = value
		clock.minute_passed.connect(func(_minute: int) -> void: tick())

var _rng := RandomNumberGenerator.new()


func start() -> void:
	people.used.connect(_on_used)


func item(id: StringName) -> ItemDef:
	for def in catalogue:
		if def.id == id:
			return def
	return null


## Whether someone is in the mood to take things.
func tempted(person: Person) -> bool:
	if person.traits.any(func(t: TraitDef) -> bool: return t.id == light_fingered):
		return true
	var mischief := misconduct.rung(&"mischief") if misconduct != null else null
	return mischief != null and person.mood < mischief.mood_below


## Whether any member of staff is close enough to see.
func seen(person: Person) -> bool:
	for other in people.nearby(person, SEEN_WITHIN):
		if other.group != prisoner_group and other.flat().distance_to(person.flat()) <= SEEN_WITHIN:
			return true
	return false


## Pockets one thing that comes from the object, if there is one.
func pocket_from(person: Person, placed: BuildingMap.PlacedObject) -> ItemDef:
	var choices := catalogue.filter(func(def: ItemDef) -> bool:
		return def.pocketed_from.any(func(tag: StringName) -> bool: return placed.def.tags.has(tag)))
	if choices.is_empty():
		return null
	var def: ItemDef = choices[_rng.randi() % choices.size()]
	person.pocket.append(def)
	pocketed.emit(person, def)
	return def


## Hides what's in their pocket if they're in their own room, and eats a
## treat when low.
func tick() -> void:
	if not enabled:
		return
	for person in people.people:
		if person.group != prisoner_group or person.pocket.is_empty():
			continue
		if person.mood < TREAT_MOOD:
			_eat_treat(person)
		var spot := hiding_place(person)
		if spot != Vector2i(-1, -1):
			for def in person.pocket:
				items.hide_in(spot, def, person.id)
			person.pocket.clear()


## The best place to hide things in the room they sleep in, while they're
## in it, as (level, object id), or (-1, -1).
func hiding_place(person: Person) -> Vector2i:
	var home := people.home_room(person)
	if home.is_empty() or home[0] != person.level:
		return Vector2i(-1, -1)
	var room: Room = home[1]
	var map: BuildingMap = people.building.levels.get(person.level)
	if map == null or map.room_at_point(person.flat()) != room:
		return Vector2i(-1, -1)
	var best: BuildingMap.PlacedObject = null
	for placed in map.objects_in_room(room):
		if placed.def.hide_spot > 0.0 and (best == null or placed.def.hide_spot > best.def.hide_spot):
			best = placed
	return Vector2i(person.level, best.id) if best != null else Vector2i(-1, -1)


func _on_used(person: Person, placed: BuildingMap.PlacedObject) -> void:
	if not enabled or placed == null or person.group != prisoner_group or not tempted(person) or seen(person):
		return
	var chance := LIGHT_FINGERED_CHANCE if person.traits.any(func(t: TraitDef) -> bool:
		return t.id == light_fingered) else POCKET_CHANCE
	if _rng.randf() < chance:
		pocket_from(person, placed)


func _eat_treat(person: Person) -> void:
	for i in person.pocket.size():
		var def := person.pocket[i]
		if def.use == &"treat":
			person.pocket.remove_at(i)
			if def.use_moodlet != &"":
				people.add_moodlet(person, def.use_moodlet)
			return
