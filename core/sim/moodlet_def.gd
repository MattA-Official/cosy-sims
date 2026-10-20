class_name MoodletDef
extends Resource
## Something that happened to someone and lifts or lowers their mood for a
## while, such as a good meal (+5 for 6 hours) or being locked up hungry.
## Getting one they already have starts its timer again rather than adding
## a second.

@export var id: StringName
## How it reads in the inspector, such as "Had a good meal".
@export var display_name: String
## Added to mood while it lasts. Negative for bad things.
@export var mood := 5.0
@export var hours := 6.0
