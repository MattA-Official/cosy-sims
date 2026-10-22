class_name ObjectDef
extends Resource
## Something that can be placed on a floor, such as a bed or a table.
## Each game keeps its own catalogue of these as .tres files.

@export var id: StringName
@export var display_name: String
## Which tab of the objects menu it sits under, such as "Cells".
@export var category := "Other"
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
## Scales the model to suit the people, such as a shorter shelf. Keep
## `height` to match.
@export var model_scale := Vector3.ONE
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
## How well things hidden in it stay hidden from a search, 0 to 1; 0 for
## nowhere to hide anything.
@export var hide_spot := 0.0
## What it costs to place, when money is on. Demolishing gives most of it
## back.
@export var price := 0
## Game minutes people use it for when it meets no need, such as a quick
## stop at a shop till. 0 for the usual while.
@export var use_minutes := 0.0
## Utilities (see Utilities): units an hour of &"power", &"water" or
## &"sewage" while someone uses it, and always.
@export var uses: Dictionary[StringName, float] = {}
@export var idle_uses: Dictionary[StringName, float] = {}
## Plant, with utilities Self-sufficient: units an hour it makes (a
## generator's power, a well's water, a treatment plant's sewage taken
## away), and units it holds in store (a battery, a water tower).
@export var supplies: Dictionary[StringName, float] = {}
@export var stores: Dictionary[StringName, float] = {}
## It supplies only by day, more in full sun, as solar panels do.
@export var solar := false
## The mains: buys whatever its network is short of, and sells spare power
## back.
@export var mains := false
## Pence for each unit it makes, such as a generator's fuel.
@export var unit_cost := 0.0

## Where it can stand: on the floor, only on a surface's spot (a chess
## board on a table), or either (a radio).
enum Sits {
	FLOOR,
	SURFACE,
	EITHER,
}
@export var sits := Sits.FLOOR
## Spots on its top where small things stand, in tiles from the middle of
## its footprint before it is turned (front is +y). Empty for anything that
## isn't a surface. Things stand at `height`, the top.
@export var spots: Array[Vector2] = []
## Using it means sitting on a free chair beside it, or beside the surface
## it stands on. Leisure needs one free; work at it is done standing
## without.
@export var seated := false
## Placed beside a surface, it turns to face it, as chairs do.
@export var faces_surfaces := false
## Whether people walk round it. Chairs they can step between.
@export var blocks := true
## Set out on a desk, it faces whoever comes to the desk rather than
## whoever sits at it, as a nameplate does.
@export var faces_out := false
## Other looks for the same thing, such as pine or metal desks. The first
## look is `model` itself; these come after it.
@export var looks: Array[ObjectLook] = []


## How many looks it comes in, counting its own.
func look_count() -> int:
	return 1 + looks.size()


## The model for a look; 0 is its own.
func model_for(look: int) -> PackedScene:
	if look > 0 and look <= looks.size() and looks[look - 1].model != null:
		return looks[look - 1].model
	return model


## A fresh copy of the model for a look, scaled, or null without one.
func make_model(look := 0) -> Node3D:
	var scene := model_for(look)
	if scene == null:
		return null
	var node := scene.instantiate() as Node3D
	node.scale = model_scale
	return node


func look_name(look: int) -> String:
	if look > 0 and look <= looks.size():
		return looks[look - 1].display_name
	return "Standard"


## Whether it can stand on a surface's spot.
func goes_on_surfaces() -> bool:
	return sits != Sits.FLOOR


func is_surface() -> bool:
	return not spots.is_empty()
