class_name StaffTraitDef
extends Resource
## A way a member of staff works, such as "Eagle-eyed" or the warden's
## "Penny pincher". Like TraitDef it only changes existing numbers: how fast
## they work, named Modifiers while they're on the payroll, and their
## morale. Applicants roll them for their role (StaffRoster.work_traits).

@export var id: StringName
@export var display_name: String
## What it does, in words, such as "Guards search 3% faster".
@export var description: String
## Roles that may have it.
@export var roles: Array[StringName] = []
## How fast they get through work, 1 for normal.
@export var work_speed := 1.0
## Named Modifiers it adds while they're on the payroll.
@export var modifiers: Dictionary[StringName, float] = {}
## Points on their own morale target.
@export var morale := 0.0
## Points on every member of staff's morale target, such as a penny
## pinching warden's -5.
@export var staff_morale := 0.0
## How fast their morale moves, 1 for normal.
@export var morale_rate := 1.0
## -1 caring, 0, +1 strict: the research character scale (M10).
@export var lean := 0


static func make(id: StringName, display_name: String, description: String, roles: Array, bonus := {},
		work_speed := 1.0) -> StaffTraitDef:
	var def := StaffTraitDef.new()
	def.id = id
	def.display_name = display_name
	def.description = description
	def.roles.assign(roles)
	def.modifiers.assign(bonus)
	def.work_speed = work_speed
	return def
