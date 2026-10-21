class_name MealDef
extends Resource
## How well the kitchen feeds people (the office's Meals setting): what a
## crate of food costs, how long a batch takes to cook, and the moodlet a
## cooked meal leaves.

@export var id: StringName
@export var display_name: String
@export_multiline var description: String
## Multiplies the price of each crate of food.
@export var cost_scale := 1.0
## Game minutes to cook a batch.
@export var cook_minutes := 20.0
## The moodlet for eating one.
@export var moodlet: StringName
