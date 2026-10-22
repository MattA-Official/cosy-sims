class_name InspectionCheckDef
extends Resource
## One thing an inspector checks, such as the meals: a measure the game
## works out, and the line it must reach to pass.

@export var id: StringName
## Where the inspector goes for it, such as "the kitchen".
@export var words: String
## What the game measures, such as &"meals"; the game says how.
@export var measure: StringName
@export var pass_line := 0.5
## Passes at or below the line, rather than at or above.
@export var at_most := false
## A research flag that makes this check pass whatever, such as
## &"health_inspection_ready".
@export var passed_by_flag: StringName
