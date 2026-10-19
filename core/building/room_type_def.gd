class_name RoomTypeDef
extends Resource
## A kind of room the player can mark an area as, such as a cell or a canteen.

@export var id: StringName
@export var display_name: String
@export var colour := Color.WHITE
## Most rooms need walls all round; a yard does not.
@export var needs_enclosure := true
## Each tag needs at least one object carrying it inside the room.
@export var required_tags: Array[StringName] = []


## What is stopping this room from working, in words. Empty means it is fine.
func problems(room: Room, map: BuildingMap) -> PackedStringArray:
	var out := PackedStringArray()
	if needs_enclosure and not room.enclosed:
		out.append("Needs walls all round")
	var present := {}
	for placed in map.objects_in_room(room):
		for tag in placed.def.tags:
			present[tag] = true
	for tag in required_tags:
		if not present.has(tag):
			out.append("Needs a %s" % tag)
	return out
