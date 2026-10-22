class_name ContractDef
extends Resource
## A short job from the Ministry, such as "House 10 low-category prisoners
## for 5 nights": a goal (measured as a GoalDef is) to meet within `days`.
## Pays `reward` when met; costs `penalty` when missed, under Full red
## tape only.

@export var id: StringName
@export var title: String
@export var goal: GoalDef
## Done when the measure is at most the goal's amount, rather than at least.
@export var at_most := false
## Days to do it in.
@export var days := 20
@export var reward := 2000
@export var penalty := 0
## Offered only at or above this grade.
@export var min_grade := 1
