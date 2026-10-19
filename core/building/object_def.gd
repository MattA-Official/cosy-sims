class_name ObjectDef
extends Resource
## Something that can be placed on a floor, such as a bed or a table.
## Each game keeps its own catalogue of these as .tres files.

@export var id: StringName
@export var display_name: String
## Footprint in cells before rotation: x across, y deep.
@export var size := Vector2i.ONE
## Placeholder box height in metres.
@export var height := 0.6
@export var colour := Color.WHITE
## What the object is good for, such as "bed" or "toilet". Room types and,
## later, people's needs look objects up by tag rather than by id.
@export var tags: Array[StringName] = []
