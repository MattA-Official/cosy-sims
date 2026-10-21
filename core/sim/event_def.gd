class_name EventDef
extends Resource
## A one-day event the player puts on, such as a talent show or a veg
## show. Everyone who takes part that day has a great day. Shared by any
## game with residents; each game keeps its own as .tres files.

@export var id: StringName
@export var display_name: String
@export_multiline var description: String
## The hobby it is for, or none for everyone.
@export var hobby: StringName
## Objects people take part at, by tag.
@export var object_tags: Array[StringName] = []
## What it costs to put on.
@export var cost := 100
## Given to everyone who took part, when the day ends.
@export var moodlet: StringName = &"great_day"
