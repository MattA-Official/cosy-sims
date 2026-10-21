class_name KnowhowDef
extends Resource
## A kind of know-how research cards cost, such as Care, earned by doing
## that kind of work.

@export var id: StringName
@export var display_name: String
## The letter cards.json uses for it, such as "C".
@export var letter: String
@export var colour := Color(0.6, 0.6, 0.6)
