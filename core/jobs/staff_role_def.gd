class_name StaffRoleDef
extends Resource
## A kind of staff, such as a cook or a cleaner: which jobs they take from
## the board and how they look.

@export var id: StringName
@export var display_name: String
@export_multiline var description: String
## The Job kinds they take, such as &"cook" and &"carry".
@export var job_kinds: Array[StringName] = []
## At most this many of them across every shift, such as one warden; 0 for
## no limit.
@export var most := 0
## The shifts they work, by id, such as only days for office roles; empty
## for any shift.
@export var only_shifts: Array[StringName] = []
## Pay for a day shift; other shifts scale it (see ShiftDef.pay_scale).
@export var wage := 0
@export var outfit_colour := Color(0.27, 0.36, 0.52)
@export var icon: Texture2D
## What each of them claims as their own, by object tag, such as
## "office_desk". Empty claims nothing.
@export var claims: StringName
## What they set out on the free spots of what they claim, in order.
@export var dressing: Array[ObjectDef] = []


## Whether they work a shift at all.
func works(shift: StringName) -> bool:
	return only_shifts.is_empty() or only_shifts.has(shift)
