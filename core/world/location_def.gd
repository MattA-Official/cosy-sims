class_name LocationDef
extends Resource
## Where the place stands: the countryside in the base game; islands,
## deserts and the moon come as location packs. A location picks the ways
## in it allows.

@export var id: StringName
@export var display_name: String
@export_multiline var description: String
@export var arrivals: Array[ArrivalPointDef] = []
## Shown on the new-game picker but not yet playable (a location pack).
@export var pack := false
