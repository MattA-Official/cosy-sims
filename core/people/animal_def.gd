class_name AnimalDef
extends Resource
## An animal about the place: a cat that wanders, a rabbit in a cage, a
## visiting dog. Animals are people of their own group with no needs, so
## they walk the same paths. Shared by any game: the museum's gallery cat
## and the hospital's therapy dog are the same.

@export var id: StringName
@export var display_name: String
@export var model: PackedScene
## Given to everyone in its room now and then, and how much it calms
## tempers there.
@export var calm_moodlet: StringName
@export var temper_scale := 1.0
## Whether it wanders (a cat, a dog) or stays in a cage (a rabbit, a
## budgie).
@export var roams := true
## Names to pick from.
@export var names: Array[String] = []
