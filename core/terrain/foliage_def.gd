class_name FoliageDef
extends Resource
## A kind of plant. Placeholder shapes for now: trees are a trunk with a
## round canopy, bushes are a squashed ball, flowers are a tiny ball.

enum Shape { TREE, BUSH, FLOWER }

@export var id: StringName
@export var display_name: String
@export var shape := Shape.TREE
@export var colour := Color(0.3, 0.6, 0.3)
@export var trunk_colour := Color(0.5, 0.36, 0.25)
## Base size in metres; each plant is scaled randomly within scale_range.
@export var size := 1.0
@export var scale_range := Vector2(0.8, 1.2)
## Closest two plants of this kind may be when painted, in tiles.
@export var spacing := 1.0
