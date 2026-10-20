class_name ZoneDef
extends Resource
## Who may be in a room, such as prisoners and staff, or staff only. The
## Zones tool paints these onto rooms; a room nobody has painted takes its
## type's zone. Ground outside any room is open to everyone.

@export var id: StringName
@export var display_name: String
@export_multiline var description: String
## The groups of people (Person.group) allowed in.
@export var groups: Array[StringName] = []
## How rooms in this zone are tinted while the Zones tool is open.
@export var colour := Color.WHITE
## A white line drawing for the build menu.
@export var icon: Texture2D


func allows(group: StringName) -> bool:
	return groups.has(group)
