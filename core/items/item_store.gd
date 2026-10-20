class_name ItemStore
extends RefCounted
## Where every item is: kept in an object that holds items (a fridge, a
## serving counter), lying on the floor, or carried by someone. Counts
## only: two meal trays are two of the same ItemDef, not two things.

## The items kept somewhere changed, or someone picked up or put down.
signal changed
## Items were dropped on or taken off the floor.
signal floor_changed

## Items kept in objects, by (level, object id): ItemDef to count.
var held: Dictionary[Vector2i, Dictionary] = {}
## Items on the floor, by (level, tile x, tile y): ItemDef to count.
var on_floor: Dictionary[Vector3i, Dictionary] = {}
## What each person is carrying, as [ItemDef, count].
var carried: Dictionary[Person, Array] = {}
## Things hidden in objects, out of sight until a search finds them, by
## (level, object id): ItemDef to count.
var hidden: Dictionary[Vector2i, Dictionary] = {}
## Who hid what's in each stash, by (level, object id): their person id.
var stash_owner: Dictionary[Vector2i, int] = {}


## How many items with a tag an object holds.
func count_in(key: Vector2i, tag: StringName = &"") -> int:
	return _count(held.get(key, {}), tag)


func count_on_floor(key: Vector3i, tag: StringName = &"") -> int:
	return _count(on_floor.get(key, {}), tag)


## Room left in an object for more items.
func room_in(key: Vector2i, placed: BuildingMap.PlacedObject) -> int:
	return maxi(0, placed.def.capacity - count_in(key))


## Puts items in an object, as many as fit. Returns how many went in.
func put_in(key: Vector2i, placed: BuildingMap.PlacedObject, item: ItemDef, count: int) -> int:
	var fits := mini(count, room_in(key, placed))
	if fits > 0:
		_add(held.get_or_add(key, {}), item, fits)
		changed.emit()
	return fits


## Takes up to `count` items with a tag out of an object. Returns
## [ItemDef, count taken], or [] if there were none.
func take_from(key: Vector2i, tag: StringName, count: int) -> Array:
	var out := _take(held.get(key, {}), tag, count)
	if not out.is_empty():
		if held[key].is_empty():
			held.erase(key)
		changed.emit()
	return out


func drop_on_floor(key: Vector3i, item: ItemDef, count: int) -> void:
	_add(on_floor.get_or_add(key, {}), item, count)
	changed.emit()
	floor_changed.emit()


func take_from_floor(key: Vector3i, tag: StringName, count: int) -> Array:
	var out := _take(on_floor.get(key, {}), tag, count)
	if not out.is_empty():
		if on_floor[key].is_empty():
			on_floor.erase(key)
		changed.emit()
		floor_changed.emit()
	return out


## Every object holding items with a tag, as (level, object id) keys.
func holders_of(tag: StringName) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for key: Vector2i in held:
		if count_in(key, tag) > 0:
			out.append(key)
	return out


## Every floor tile with items with a tag on it.
func floor_spots_of(tag: StringName) -> Array[Vector3i]:
	var out: Array[Vector3i] = []
	for key: Vector3i in on_floor:
		if count_on_floor(key, tag) > 0:
			out.append(key)
	return out


## Everything of a tag anywhere, carried included.
func total(tag: StringName = &"") -> int:
	var sum := 0
	for items: Dictionary in held.values():
		sum += _count(items, tag)
	for items: Dictionary in on_floor.values():
		sum += _count(items, tag)
	for pair: Array in carried.values():
		if tag.is_empty() or (pair[0] as ItemDef).has_tag(tag):
			sum += pair[1]
	return sum


func carrying(person: Person) -> ItemDef:
	var pair: Array = carried.get(person, [])
	return pair[0] if not pair.is_empty() else null


func pick_up(person: Person, pair: Array) -> void:
	if pair.is_empty():
		return
	carried[person] = pair
	changed.emit()


## Hands back what someone carries, as [ItemDef, count], and empties their
## hands.
func put_down(person: Person) -> Array:
	var pair: Array = carried.get(person, [])
	carried.erase(person)
	if not pair.is_empty():
		changed.emit()
	return pair


## Hides something in an object.
func hide_in(key: Vector2i, item: ItemDef, owner_id: int) -> void:
	var stash: Dictionary = hidden.get_or_add(key, {})
	stash[item] = stash.get(item, 0) + 1
	stash_owner[key] = owner_id


## Takes one hidden item out of a stash, emptying it when it's the last.
func unhide(key: Vector2i, item: ItemDef) -> void:
	var stash: Dictionary = hidden.get(key, {})
	if not stash.has(item):
		return
	stash[item] -= 1
	if stash[item] <= 0:
		stash.erase(item)
	if stash.is_empty():
		hidden.erase(key)
		stash_owner.erase(key)


## Forgets items kept in objects that are gone. Returns how many objects
## were forgotten.
func forget_missing(objects_exist: Callable) -> int:
	var gone := held.keys().filter(func(key: Vector2i) -> bool: return not objects_exist.call(key))
	for key: Vector2i in gone:
		held.erase(key)
	for key: Vector2i in hidden.keys():
		if not objects_exist.call(key):
			hidden.erase(key)
			stash_owner.erase(key)
	if not gone.is_empty():
		changed.emit()
	return gone.size()


static func _count(items: Dictionary, tag: StringName) -> int:
	var sum := 0
	for item: ItemDef in items:
		if tag.is_empty() or item.has_tag(tag):
			sum += items[item]
	return sum


static func _add(items: Dictionary, item: ItemDef, count: int) -> void:
	items[item] = items.get(item, 0) + count


static func _take(items: Dictionary, tag: StringName, count: int) -> Array:
	for item: ItemDef in items.keys():
		if tag.is_empty() or item.has_tag(tag):
			var taken := mini(count, items[item])
			items[item] -= taken
			if items[item] <= 0:
				items.erase(item)
			return [item, taken]
	return []
