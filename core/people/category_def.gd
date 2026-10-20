class_name CategoryDef
extends Resource
## A security category for someone in a group, such as a low-security
## prisoner: the colour of their uniform, and the grant the prison gets
## for them each day.

@export var id: StringName
@export var display_name: String
@export_multiline var description: String
@export var outfit_colour := Color(0.95, 0.55, 0.2)
## Paid each day for each person of this category.
@export var daily_grant := 50
