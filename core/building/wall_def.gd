class_name WallDef
extends Resource
## A wall style. Indoor walls make rooms indoors; outdoor ones, such as
## fences and hedges, still divide areas but leave them outdoors.

@export var id: StringName
@export var display_name: String
@export var colour := Color.WHITE
@export var top_colour := Color(0.36, 0.32, 0.3)
@export var outdoor := false
## Height in metres when walls are up. Fences are usually lower.
@export var height := 2.5
@export var thickness := 0.15
## Draw as posts and rails rather than a solid wall.
@export var see_through := false
