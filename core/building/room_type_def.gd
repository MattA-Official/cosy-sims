class_name RoomTypeDef
extends Resource
## A kind of room the player can mark an area as, such as a cell or a canteen.

@export var id: StringName
@export var display_name: String
@export var colour := Color.WHITE
## A white line drawing for the build menu.
@export var icon: Texture2D
enum Location { INDOORS, OUTDOORS, EITHER }

## Most rooms need to be indoors; a yard needs to be outdoors.
@export var location := Location.INDOORS
## Each tag needs at least one object carrying it inside the room.
@export var required_tags: Array[StringName] = []
## Tags that need more than one, such as 4 beds in a dorm.
@export var required_counts: Dictionary[StringName, int] = {}
## Floor tiles each person sleeping in it should have, for room quality.
## 0 for rooms nobody sleeps in.
@export var ideal_tiles := 0.0
## Many people sleep here together rather than in a room of their own,
## which some mind.
@export var dorm := false
## Added to room quality as it is, such as -2 for a dorm's lack of
## privacy.
@export var quality_bonus := 0.0
@export var quality_bonus_text := ""
## The ZoneDef id of who may be in it until the player paints another, such
## as staff only for a staff room. Empty takes the game's usual zone.
@export var zone: StringName


## What is stopping this room from working, in words. Empty means it is fine.
func problems(room: Room, map: BuildingMap) -> PackedStringArray:
	var out := PackedStringArray()
	if location == Location.INDOORS and not room.indoor:
		out.append("Needs walls all round")
	elif location == Location.OUTDOORS and room.indoor:
		out.append("Needs to be outdoors")
	var present := {}
	for placed in map.objects_in_room(room):
		for tag in placed.def.tags:
			present[tag] = present.get(tag, 0) + 1
	for tag in required_tags:
		if not present.has(tag):
			out.append("Needs a %s" % tag)
	for tag: StringName in required_counts:
		var count: int = present.get(tag, 0)
		if count < required_counts[tag] and not (count == 0 and required_tags.has(tag)):
			out.append("Needs %d %ss" % [required_counts[tag], tag])
	return out
