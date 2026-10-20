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
@export var height := 1.5
@export var thickness := 0.15
## Draw as posts and rails rather than a solid wall.
@export var see_through := false
## Optional pattern laid over the colour, one repeat a metre: near-white
## greyscale, so the colour still decides how it looks.
@export var texture: Texture2D
## A band of a second colour along the bottom of the wall, like the painted
## dado in a corridor. Fully transparent for none.
@export var dado_colour := Color(0, 0, 0, 0)
@export var dado_height := 0.5
## How nice it is to have round a room, for room quality.
@export var comfort := 0.0
## What a tile's length of it costs to build, when money is on.
@export var price := 0
## Part of a perimeter: ground it encloses counts as secure (see
## SecureArea).
@export var secure := false
## Can be cut through, such as a wire fence (not a wall).
@export var cuttable := false
