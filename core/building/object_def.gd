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
## People may help themselves to what it holds, as at a serving counter.
## Otherwise only workers take from it.
@export var hands_out := false
## Item tags it can hold, such as "ingredient" for a fridge or "meal" for
## a serving counter. Empty for objects that hold nothing.
@export var holds: Array[StringName] = []
## How many items it holds at most.
@export var capacity := 0
## Whether what it holds is drawn on top of it (trays on a counter) or is
## shut away (crates in a fridge).
@export var shows_held := true
## Using it at mealtimes and such needs an item with this tag in hand
## first, such as a meal tray for a table: people fetch one from whatever
## holds them on their way. Only during a block whose own object this is,
## and only once something about the place holds such items; until then
## it works without.
@export var needs_item: StringName
## The moodlet someone gets when there's none of `needs_item` to be had,
## such as "Missed a meal".
@export var without_item_moodlet: StringName
## The chance someone leaves litter where they stood after using it, as
## after a meal.
@export_range(0.0, 1.0) var litter_chance := 0.0
## Uses before it wears out and breaks, until someone mends it (see Wear).
## 0 never breaks.
@export var uses_before_breaking := 0
