class_name SessionDef
extends Resource
## Something that runs inside a timetable block for some people: a class,
## counselling, a club. The Regime places its sessions into the week.

@export var id: StringName
@export var display_name: String
## How long each session runs, in half hours.
@export var length := 4
@export var room_type: StringName
## The staff role that runs it, who must be on duty.
@export var staff_role: StringName
## Blocks it may sit in, by activity id; empty for any block that holds
## classes.
@export var blocks: Array[StringName] = []
## Sessions a week, unless the player offers a different number.
@export var per_week := 7
## The course it runs, if it's a class or therapy.
@export var course: StringName
