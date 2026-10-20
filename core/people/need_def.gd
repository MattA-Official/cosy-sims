class_name NeedDef
extends Resource
## Something people need, such as sleep, and the kind of object that meets
## it. Needs run from 100 (met) down to 0, and people go to see to the
## lowest once it drops below the line. Rates are per game hour, so the
## length of a day never retunes them.

@export var id: StringName
@export var display_name: String
## Objects with this tag see to the need, such as "bed" for sleep.
@export var object_tag: StringName
## What people are doing while they use the object, such as "Sleeping".
@export var doing: String
## Points lost per game hour while awake.
@export var decay_per_hour := 4.0
## Points lost per game hour while asleep.
@export var asleep_decay_per_hour := 1.0
## Game minutes it takes to see to it from empty.
@export var use_minutes := 20.0
## Seeing to this need is sleeping, so the others run down at their asleep
## rate meanwhile.
@export var sleeping := false
