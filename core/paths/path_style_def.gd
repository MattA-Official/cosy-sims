class_name PathStyleDef
extends Resource
## A kind of path or road: how wide it is and what it looks like.

@export var id: StringName
@export var display_name: String
@export var colour := Color(0.78, 0.72, 0.6)
## The kerb or verge along both sides.
@export var edge_colour := Color(0.58, 0.53, 0.45)
## Full width in tiles.
@export var width := 1.5
