class_name FloorDef
extends Resource
## A floor style, such as tiles indoors or a gravel path outdoors.

@export var id: StringName
@export var display_name: String
@export var colour := Color.WHITE
## Outdoor floors (paths, paving, grass) are for yards and grounds.
@export var outdoor := false
