class_name WorkProgrammeDef
extends Resource
## Work prisoners (or whoever a game puts on one) do in work blocks
## (ActivityDef.jobs), taking jobs from the board like staff: helping in
## the kitchen, say, or making things in the workshop.

@export var id: StringName
@export var display_name: String
@export_multiline var description: String
## The Job kinds people on it take.
@export var job_kinds: Array[StringName] = []
@export var icon: Texture2D
## The skill it trains, such as &"cooking", and how much each job done
## adds (0 to 100). Skill speeds the work up, half as fast again at 100.
@export var skill: StringName
@export var skill_per_job := 1
