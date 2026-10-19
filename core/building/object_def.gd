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
## Stairs and lifts link a level with the one above.
enum Connects {
	NONE,
	STAIRS, ## Rises one storey along its length and cuts a hole in the floor above.
	LIFT, ## Links with a lift in the same spot on the next level up.
}

## Placeholder box height in metres.
@export var height := 0.6
@export var colour := Color.WHITE
## What the object is good for, such as "bed" or "toilet". Room types and,
## later, people's needs look objects up by tag rather than by id.
@export var tags: Array[StringName] = []
## Whether this links to the level above, and how.
@export var connects := Connects.NONE
