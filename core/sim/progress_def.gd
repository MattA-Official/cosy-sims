class_name ProgressDef
extends Resource
## A named, explained 0 to 100 value each person carries, such as a
## prisoner's reform, a patient's recovery or a pupil's learning. Kept in
## person.profile under `id`, so it saves with them.

@export var id: StringName
@export var display_name: String
## Where it starts for someone new.
@export var start := 20.0
## Most it can rise in a day, from every source together. Losses ignore it.
@export var daily_cap := 8.0
