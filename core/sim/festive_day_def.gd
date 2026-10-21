class_name FestiveDayDef
extends Resource
## A festive day (see Calendar): on its day of the season the working
## blocks become festivities, the kitchen serves something special and
## everyone gets a treat.

@export var id: StringName
@export var display_name: String
@export var season: StringName
@export var day_of_season := 1
## The block that takes the place of work, learning, clubs and the yard.
@export var block: ActivityDef
## The meal served all day, by MealDef id; none keeps the usual.
@export var menu: StringName
@export var moodlet: StringName
@export_multiline var description := ""
