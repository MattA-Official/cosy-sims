class_name ActivityDef
extends Resource
## One kind of block in a timetable, such as Sleep, Eat or Yard: where
## people must be, what they may use there, and what doors do. Needs still
## pick between the choices a block leaves open. Each game keeps its own
## as .tres files; the code that runs them (ScheduleRunner, People) is
## shared.

enum Place {
	ANYWHERE, ## Wherever they may go.
	OWN_ROOM, ## The room their own bed is in, such as their cell.
	ROOM_TYPES, ## Any room of the types in `room_types`.
}

enum DoorRule {
	OPEN, ## Doors stay as they are.
	LOCK_OWN_ROOM, ## Each own room locks once everyone who sleeps there is inside.
}

@export var id: StringName
@export var display_name: String
## Short enough for one hour of the timetable window, such as "Eat".
@export var short_name: String
@export var colour := Color.WHITE
@export var place := Place.ANYWHERE
## For ROOM_TYPES: the RoomTypeDef ids people go to.
@export var room_types: Array[StringName] = []
## Object tags people may use during the block. Needs whose objects are
## not listed wait for another block.
@export var allowed_tags: Array[StringName] = []
## The object the block is for, used whether or not a need asks for it:
## a bed in Sleep, a table in Eat, a shower in Shower. Empty for none.
@export var main_tag: StringName
## Stay on the main object until the block ends, even once the need is
## met, as in bed overnight.
@export var stay_on_main := false
## Free to go anywhere once the main object has been used, as after a
## shower.
@export var free_after := false
@export var door_rule := DoorRule.OPEN
## What the block is for, in a line, for the timetable window.
@export_multiline var description := ""


func allows(tag: StringName) -> bool:
	return allowed_tags.has(tag)


## Whether the block says where people must be.
func has_place() -> bool:
	return place != Place.ANYWHERE
