class_name CastDef
extends Resource
## Someone in the campaign's recurring cast, such as Old Stan the
## long-serving guard: who writes the letters in the in-tray.

@export var id: StringName
@export var display_name: String
## Who they are, such as "at the Ministry".
@export var role: String
## A staff role this person fills in the prison, so they can be clicked,
## or &"" for someone who only writes.
@export var staff_role: StringName
