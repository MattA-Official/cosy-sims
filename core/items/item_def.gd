class_name ItemDef
extends Resource
## Something people carry about, such as a crate of food, a meal tray or a
## bundle of laundry. Each game keeps its own catalogue of these.

@export var id: StringName
@export var display_name: String
## What it is good for, such as "ingredient" or "meal". Objects say which
## tags they hold, and jobs fetch items by tag.
@export var tags: Array[StringName] = []
## How many one person carries at once.
@export var carry_count := 1
## Its model, held in front of whoever carries it and stacked where it is
## kept. Without one it shows as a box of `colour`.
@export var model: PackedScene
@export var colour := Color(0.8, 0.65, 0.45)


func has_tag(tag: StringName) -> bool:
	return tags.has(tag)
