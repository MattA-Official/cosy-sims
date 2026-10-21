class_name SeasonDef
extends Resource
## One of the year's seasons (see Calendar): its light, its weather and
## how it colours the ground.

@export var id: StringName
@export var display_name: String
## Hours the sun rises and sets.
@export var dawn := 6.0
@export var dusk := 20.0
## Weather id -> weight for each day's roll.
@export var weather: Dictionary[StringName, float] = {}
## The grass colour.
@export var ground_tint := Color(0.40, 0.64, 0.30)
## Multiplier on the heating bill.
@export var heating_scale := 1.0
