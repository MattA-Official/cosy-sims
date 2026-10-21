class_name CategoryDef
extends Resource
## A security category for someone in a group, such as a low-security
## prisoner: the colour of their uniform, and the grant the prison gets
## for them each day, and how closely they're watched.

@export var id: StringName
@export var display_name: String
@export_multiline var description: String
@export var outfit_colour := Color(0.95, 0.55, 0.2)
## Paid each day for each person of this category.
@export var daily_grant := 50
## Temper builds this much faster (see Misconduct).
@export var temper_scale := 1.0
## How likely their cell is to be picked for a random search, against 1.
@export var search_weight := 1.0
## Tiles from a guard at which they're spotted out of place.
@export var watch_distance := 3.0
## How long they stay, in game days: a sentence, or a hospital stay.
@export var stay_days_min := 5
@export var stay_days_max := 12
