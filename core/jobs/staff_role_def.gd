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
## Hired only through a card (such as a department head's), so no
## applicants turn up for it by themselves.
@export var by_card := false
## Pay for a day shift; other shifts scale it (see ShiftDef.pay_scale).
@export var wage := 0
@export var outfit_colour := Color(0.27, 0.36, 0.52)
@export var icon: Texture2D
## What each of them claims as their own, by object tag, such as
## "office_desk". Empty claims nothing.
@export var claims: StringName
## What they set out on the free spots of what they claim, in order.
@export var dressing: Array[ObjectDef] = []
## Their role's course, such as "De-escalation"; empty for none.
@export var course_name: String
## What they get better at from level StaffRoster.PERK_LEVEL, or after their
## course: a name, words for it, and Modifiers each of them adds while on
## the payroll (systems may also ask StaffRoster.has_perk for one person).
@export var perk_name: String
@export_multiline var perk_words: String
@export var perk_bonus: Dictionary[StringName, float] = {}


## Whether they work a shift at all.
func works(shift: StringName) -> bool:
	return only_shifts.is_empty() or only_shifts.has(shift)
