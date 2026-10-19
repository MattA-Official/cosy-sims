class_name NeedDef
extends Resource
## Something people need, such as sleep, and the kind of object that meets
## it. Needs run from 100 (met) down to 0, and people go to see to the
## lowest once it drops below the line.

@export var id: StringName
@export var display_name: String
## Objects with this tag see to the need, such as "bed" for sleep.
@export var object_tag: StringName
## What people are doing while they use the object, such as "Sleeping".
@export var doing: String
## Points lost per second.
@export var decay := 0.4
## Seconds it takes to see to it from empty.
@export var use_seconds := 20.0
