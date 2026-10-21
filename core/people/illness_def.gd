class_name IllnessDef
extends Resource
## Something people catch from each other, such as a cold. Shared by any
## game with residents: the hospital's whole caseload uses the same
## resource. Each game keeps its own as .tres files.

@export var id: StringName
@export var display_name: String
## The chance an hour of catching it from each ill person close by, and
## how close counts, in tiles.
@export var spread_chance := 0.02
@export var spread_radius := 3.0
## Days it lasts untreated, and once treated.
@export var days_least := 2.0
@export var days_most := 4.0
@export var treated_days := 1.0
## Need id -> how much faster it runs down while ill.
@export var need_rates: Dictionary[StringName, float] = {}
## Walking pace while ill.
@export var pace := 0.8
## Mood while ill, and its words.
@export var mood := -5.0
@export var mood_words := "Under the weather"
## The chance an arrival brings it with them.
@export var arrival_chance := 0.03
