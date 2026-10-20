class_name ObjectDef
extends Resource
## Something that can be placed on a floor, such as a bed or a table.
## Each game keeps its own catalogue of these as .tres files.

@export var id: StringName
@export var display_name: String
enum Snap {
	TILE, ## Lines up with whole tiles, like beds and tables.
	QUARTER, ## Quarter-tile steps, for smaller things.
	FREE, ## Anywhere, for decorations.
}

## Footprint in tiles before rotation: x across, y deep. Can be fractional.
@export var size := Vector2.ONE
## How placement snaps. Holding Alt places freely whatever this says.
@export var snap := Snap.TILE
## Lifts link a level with the one above. Stairs are drawn with their own
## tool rather than placed as objects.
enum Connects {
	NONE,
	LIFT, ## Links with a lift in the same spot on the next level up.
}

## Its model, origin at the middle of its footprint on the floor. Without
## one it shows as a box of `height` and `colour`.
@export var model: PackedScene
## Height in metres, for the placeholder box and anything that needs to
## know how tall it is.
@export var height := 0.6
@export var colour := Color.WHITE
## What the object is good for, such as "bed" or "toilet". Room types and,
## later, people's needs look objects up by tag rather than by id.
@export var tags: Array[StringName] = []
## Whether this links to the level above, and how.
@export var connects := Connects.NONE
## Item tags it can hold, such as "ingredient" for a fridge or "meal" for
## a serving counter. Empty for objects that hold nothing.
@export var holds: Array[StringName] = []
## How many items it holds at most.
@export var capacity := 0
