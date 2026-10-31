class_name Signage
extends RefCounted
## Finding the way. People new to a place only set off for somewhere they
## can see, or that a sign in sight points to: a sign is an object whose
## def lists what it shows the way to (ObjectDef.signs_to, by room type or
## object tag, such as &"gate" or &"toilet"). Without one they are lost:
## they mill about where they are and get fed up (see People.find_way_to).
##
## In sight means in the same indoor room, or outdoors (open ground or
## unwalled paving) within SIGHT tiles of another outdoor sign. Groups in `knowing_groups` (staff, say) always know the way, as
## does anyone who has been there before (see learn()).

## How far people see signs across open ground, in tiles.
const SIGHT := 8.0
## Where in someone's profile the places they know are kept.
const KNOWN_KEY := "known_places"

var building: Building
## Groups who know their way about without signs.
var knowing_groups: Array[StringName] = [&"staff"]
## Room types by id, for signs that point to a kind of room.
var room_types: Dictionary[StringName, RoomTypeDef] = {}


## Signs someone at a spot can see.
func signs_seen(level: int, spot: Vector2) -> Array[BuildingMap.PlacedObject]:
	var out: Array[BuildingMap.PlacedObject] = []
	var map: BuildingMap = building.levels.get(level)
	if map == null:
		return out
	var room := _indoor_room(map, spot)
	for placed: BuildingMap.PlacedObject in map.objects.values():
		if placed.def.signs_to.is_empty():
			continue
		if room != null:
			if map.room_at_point(placed.centre) == room:
				out.append(placed)
		elif placed.centre.distance_to(spot) <= SIGHT and _indoor_room(map, placed.centre) == null:
			out.append(placed)
	return out


## The indoor room at a spot, or null outdoors (open ground, or paving
## with no walls round it).
static func _indoor_room(map: BuildingMap, spot: Vector2) -> Room:
	if not map.has_floor(Vector2i(spot.floor())):
		return null
	var room := map.room_at_point(spot)
	return room if room != null and room.indoor else null


## Can someone at a spot see the way to `target` (a room type or object
## tag)? They can if it is right there in the room with them, or a sign
## they can see points to it.
func shows_way(level: int, spot: Vector2, target: StringName) -> bool:
	for placed in signs_seen(level, spot):
		if placed.def.signs_to.has(target):
			return true
	return in_sight(level, spot, target)


## Is `target` itself in sight: the room they are in is of that type, or
## holds an object with that tag?
func in_sight(level: int, spot: Vector2, target: StringName) -> bool:
	var map: BuildingMap = building.levels.get(level)
	if map == null or not map.has_floor(Vector2i(spot.floor())):
		return false
	var room := map.room_at_point(spot)
	if room == null:
		return false
	if room.type == target:
		return true
	for placed: BuildingMap.PlacedObject in map.objects.values():
		if placed.def.tags.has(target) and map.room_at_point(placed.centre) == room:
			return true
	return false


## Does someone know their way to `target` from where they stand?
func knows_way(person: Person, target: StringName) -> bool:
	if knowing_groups.has(person.group) or knows(person, target):
		return true
	return shows_way(person.level, person.flat(), target)


## Has someone been to a `target` before, so needs no signs for it?
static func knows(person: Person, target: StringName) -> bool:
	return (person.profile.get(KNOWN_KEY, []) as Array).has(target)


## Remembers that someone has found a `target`.
static func learn(person: Person, target: StringName) -> void:
	var known: Array = person.profile.get_or_add(KNOWN_KEY, [])
	if not known.has(target):
		known.append(target)
