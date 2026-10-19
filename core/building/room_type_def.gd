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
			present[tag] = true
	for tag in required_tags:
		if not present.has(tag):
			out.append("Needs a %s" % tag)
	return out
