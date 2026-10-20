class_name RoomQuality
extends RefCounted
## How nice a room is, from -10 to +10: room to move, a window, decoration,
## and what the floor and walls are made of. It feeds the mood of people
## who sleep in the room or spend time in it, and shows as stars in the
## inspector. Nothing here is prison-specific: a ward or a lounge has its
## own ideal size on its RoomTypeDef.
##
##   var quality := RoomQuality.assess(map, room, PrisonCatalogue.room_type(room.type))
##   quality.score # 3.0
##   quality.parts # [["Has a window", 2.0], ["Bare floor", 0.0], ...]

const MIN := -10.0
const MAX := 10.0
## Most cramped (half the ideal space or less) and roomiest (half as much
## again or more).
const CRAMPED := -4.0
const ROOMY := 2.0
const WINDOW := 2.0
const DECOR_EACH := 1.0
const DECOR_MOST := 3.0

var score := 0.0
## What made the score, as [words, points] pairs, biggest effect first.
var parts: Array = []
## Every object tag in the room, with how many objects carry it.
var tags: Dictionary[StringName, int] = {}


## Works out a room's quality. `type` may be null for an unmarked room.
## Beds are counted as the people who sleep there; objects tagged `decor`
## count as decoration.
static func assess(map: BuildingMap, room: Room, type: RoomTypeDef, bed_tag: StringName = &"bed",
		decor_tag: StringName = &"decor") -> RoomQuality:
	var out := RoomQuality.new()
	var beds := 0
	var decor := 0
	for placed in map.objects_in_room(room):
		for tag in placed.def.tags:
			out.tags[tag] = out.tags.get(tag, 0) + 1
		if placed.def.tags.has(bed_tag):
			beds += 1
		if placed.def.tags.has(decor_tag):
			decor += 1
	if type != null and type.ideal_tiles > 0.0 and beds > 0:
		var ratio := room.area / beds / type.ideal_tiles
		if ratio < 1.0:
			out._add("Cramped", CRAMPED * clampf((1.0 - ratio) / 0.5, 0.0, 1.0))
		else:
			out._add("Roomy" if ratio > 1.1 else "Room to move", ROOMY * clampf((ratio - 1.0) / 0.5, 0.0, 1.0))
	var walls := _walls(map, room)
	out._add("Has a window" if walls[1] > 0 else "No window", WINDOW if walls[1] > 0 else 0.0)
	if decor > 0:
		out._add("Decorated", minf(decor * DECOR_EACH, DECOR_MOST))
	var floor_comfort := _floor_comfort(map, room)
	if not is_zero_approx(floor_comfort):
		out._add("Nice floor" if floor_comfort > 0.0 else "Grim floor", floor_comfort)
	if not is_zero_approx(walls[0]):
		out._add("Nice walls" if walls[0] > 0.0 else "Grim walls", walls[0])
	if type != null and not is_zero_approx(type.quality_bonus):
		out._add(type.quality_bonus_text, type.quality_bonus)
	out.score = clampf(out.score, MIN, MAX)
	out.parts.sort_custom(func(a: Array, b: Array) -> bool: return absf(a[1]) > absf(b[1]))
	return out


## Out of five, in halves, for showing as stars.
func stars() -> float:
	return roundf((score - MIN) / (MAX - MIN) * 10.0) / 2.0


## "★★★½☆"
func star_text() -> String:
	var full := floori(stars())
	var half := stars() - full >= 0.5
	return "★".repeat(full) + ("½" if half else "") + "☆".repeat(5 - full - (1 if half else 0))


func _add(text: String, points: float) -> void:
	parts.append([text, points])
	score += points


## The average comfort of the room's floor, by area.
static func _floor_comfort(map: BuildingMap, room: Room) -> float:
	var total := 0.0
	for cell in room.cells:
		var def := map.floor_def(map.floors.get(cell, &""))
		total += def.comfort if def != null else 0.0
	return total / maxf(room.cells.size(), 1)


## [the average comfort of the walls round the room, how many windows].
static func _walls(map: BuildingMap, room: Room) -> Array:
	var comfort := 0.0
	var count := 0
	var windows := 0
	var seen := {}
	for cell in room.cells:
		for d in BuildingMap.DIRECTIONS:
			var edge := BuildingMap.edge_between(cell, cell + d)
			var kind := map.wall_at(edge)
			if kind == BuildingMap.Wall.NONE or seen.has(edge):
				continue
			seen[edge] = true
			var def := map.wall_def(map.wall_style(edge))
			comfort += def.comfort if def != null else 0.0
			count += 1
			if kind == BuildingMap.Wall.WINDOW:
				windows += 1
		for key: Vector4i in map.slants_through(cell):
			if seen.has(key):
				continue
			seen[key] = true
			var def := map.wall_def(map.slant_style(key))
			comfort += def.comfort if def != null else 0.0
			count += 1
			if map.slant_at(key) == BuildingMap.Wall.WINDOW:
				windows += 1
	return [comfort / maxf(count, 1), windows]
