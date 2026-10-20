class_name Contraband
extends Node
## Things prisoners shouldn't have: a spoon from the canteen, a rolling pin
## from the kitchen, a screwdriver from the workshop. Ordinary items with
## `pocketed_from` set. A prisoner up to no good (mood low enough for
## mischief) or light-fingered may pocket one on finishing with an object
## when no staff are close, and hides it in their own cell at the next
## chance, in whatever hides things best. Treats get eaten when they're
## feeling low. Searches (see Searching) find them.
##
## Kitchens and workshops count their tools at each shift change, so a
## missing rolling pin or screwdriver raises an alert. Biscuits are money:
## in free time and the yard a prisoner who wants a weapon may buy one
## from someone in the same room. A metal detector doorway beeps at anyone
## carrying something metal.

## Chance to pocket something on finishing with an object, and for the
## light-fingered.
const POCKET_CHANCE := 0.05
const LIGHT_FINGERED_CHANCE := 0.15
## Staff this close see it, in tiles.
const SEEN_WITHIN := 3.0
## Treats are eaten once mood falls below this.
const TREAT_MOOD := 40.0

signal pocketed(person: Person, item: ItemDef)
## A kitchen or workshop counted its tools and one was gone.
signal tool_missing(level: int, room: Room, item: ItemDef)
signal traded(buyer: Person, seller: Person, item: ItemDef)
## Someone walked through a metal detector with metal on them.
signal detected(person: Person, item: ItemDef)

## Rooms that count their tools, and the hours they do (shift changes).
const TOOL_ROOMS: Array[StringName] = [&"kitchen", &"workshop"]
const COUNT_HOURS: Array[int] = [6, 18]
## Blocks in which prisoners trade, and the chance an hour that someone
## who wants something tries.
const TRADE_BLOCKS: Array[StringName] = [&"free", &"yard"]
const TRADE_CHANCE := 0.5
const CURRENCY := &"biscuit"
## How near a metal detector's middle counts as walking through it, and
## how long before it beeps at the same person again.
const DETECT_DISTANCE := 0.45
const DETECT_COOLDOWN := 30.0

var people: People
var items: ItemStore
var misconduct: Misconduct
## Every item that can be contraband.
var catalogue: Array[ItemDef] = []
var prisoner_group: StringName = &"prisoner"
var light_fingered: StringName = &"light_fingered"
## Off for none of it.
var enabled := true
## Tools taken since the last count: [level, Room, ItemDef].
var missing: Array = []
var clock: GameClock:
	set(value):
		clock = value
		clock.minute_passed.connect(func(minute: int) -> void:
			tick()
			if minute % 60 == 30:
				trade_round()
			if minute % 60 == 0 and COUNT_HOURS.has(minute / 60):
				count_tools())

var _rng := RandomNumberGenerator.new()
## When each person last set off a metal detector, in game minutes.
var _beeped: Dictionary[Person, float] = {}


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
	var map: BuildingMap = people.building.levels.get(person.level)
	var room := map.room_at_point(placed.centre) if map != null else null
	if room != null and TOOL_ROOMS.has(room.type) and def.use != &"treat":
		missing.append([person.level, room, def])
	pocketed.emit(person, def)
	return def


## The shift change count: each tool gone since the last one is noticed.
func count_tools() -> void:
	for entry: Array in missing:
		tool_missing.emit(entry[0], entry[1], entry[2])
	missing.clear()


## Everything someone has: in their pocket and in their stashes.
func holdings(person: Person) -> Array[ItemDef]:
	var out: Array[ItemDef] = person.pocket.duplicate()
	for key: Vector2i in items.stash_owner:
		if items.stash_owner[key] != person.id:
			continue
		var stash: Dictionary = items.hidden.get(key, {})
		for def: ItemDef in stash:
			for i in stash[def]:
				out.append(def)
	return out


## Takes one of something someone has, from their pocket first. Returns
## whether they had it.
func take(person: Person, def: ItemDef) -> bool:
	var at := person.pocket.find(def)
	if at != -1:
		person.pocket.remove_at(at)
		return true
	for key: Vector2i in items.stash_owner.keys():
		if items.stash_owner[key] == person.id and (items.hidden.get(key, {}) as Dictionary).has(def):
			items.unhide(key, def)
			return true
	return false


## What someone would buy: a weapon if they're spoiling for trouble.
func wants(person: Person) -> StringName:
	var fight := misconduct.rung(&"fight") if misconduct != null else null
	var hothead := person.traits.any(func(t: TraitDef) -> bool: return t.temper_scale > 1.0)
	if person.temper > 50.0 or hothead or (fight != null and person.mood < fight.mood_below + 10.0):
		return &"weapon"
	return &""


## Tries a trade between two prisoners: the buyer pays biscuits for
## something the seller has that they want. Returns the item, or null.
func try_trade(buyer: Person, seller: Person) -> ItemDef:
	var want := wants(buyer)
	if want.is_empty() or seen(buyer):
		return null
	var money := holdings(buyer).filter(func(def: ItemDef) -> bool: return def.id == CURRENCY).size()
	for def in holdings(seller):
		if def.use != want or def.trade_value > money:
			continue
		take(seller, def)
		buyer.pocket.append(def)
		var currency := item(CURRENCY)
		for i in def.trade_value:
			take(buyer, currency)
			seller.pocket.append(currency)
		traded.emit(buyer, seller, def)
		return def
	return null


## The hour's trading, in free time and the yard.
func trade_round() -> void:
	if not enabled:
		return
	var rooms: Dictionary[Room, Array] = {}
	for person in people.people:
		if person.group != prisoner_group or person.block == null or not TRADE_BLOCKS.has(person.block.id) \
				or person.led or person.sitting:
			continue
		var here := people.room_of(person)
		if not here.is_empty():
			rooms.get_or_add(here[1], []).append(person)
	for room: Room in rooms:
		var crowd: Array = rooms[room]
		for buyer: Person in crowd:
			if _rng.randf() >= TRADE_CHANCE or wants(buyer).is_empty():
				continue
			for seller: Person in crowd:
				if seller != buyer and try_trade(buyer, seller) != null:
					break


## Metal detector doorways beep at prisoners carrying something metal.
func check_detectors() -> void:
	var now := clock.total_minutes if clock != null else 0.0
	var detectors: Array = []
	for n: int in people.building.levels:
		var map: BuildingMap = people.building.levels[n]
		for edge: Vector3i in map.door_kinds:
			var kind: DoorKindDef = people.access.door_kinds.get(map.door_kind_at(edge))
			if kind != null and kind.detects_metal:
				var cells := BuildingMap.edge_cells(edge)
				detectors.append([n, (Vector2(cells[0]) + Vector2(cells[1])) * 0.5 + Vector2(0.5, 0.5)])
	if detectors.is_empty():
		return
	for person in people.people:
		if person.group != prisoner_group or now - _beeped.get(person, -INF) < DETECT_COOLDOWN:
			continue
		var metal := person.pocket.filter(func(def: ItemDef) -> bool: return def.metal)
		if metal.is_empty():
			continue
		for detector: Array in detectors:
			if detector[0] == person.level and (detector[1] as Vector2).distance_to(person.flat()) <= DETECT_DISTANCE:
				_beeped[person] = now
				detected.emit(person, metal[0])
				break


## Hides what's in their pocket if they're in their own room, and eats a
## treat when low.
func tick() -> void:
	if not enabled:
		return
	check_detectors()
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
