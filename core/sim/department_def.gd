class_name DepartmentDef
extends Resource
## A department the warden can hire a head for, such as Security: the
## head's role, the standing bonus they bring, and when the hire card
## turns up.

@export var id: StringName
@export var display_name: String
@export var head_role: StaffRoleDef
## Modifier amounts while the head is on the payroll, such as
## {&"search_speed": 0.1}.
@export var bonus: Dictionary[StringName, float] = {}
## The bonus in words, such as "Guards search 10% faster".
@export var bonus_text: String
## Room types, any one of which must be built before the hire card turns
## up; empty for from the start.
@export var needs_rooms: Array[StringName] = []
## Desk minutes the warden spends on the hire card.
@export var hire_minutes := 480.0
@export var colour := Color(0.6, 0.6, 0.6)
