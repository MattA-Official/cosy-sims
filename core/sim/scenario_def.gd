class_name ScenarioDef
extends Resource
## A prison to take over with a job to do: a layout to start from, the
## money and grade it starts with, the goals that win it and the days
## there are to do it in. Missing the day limit loses on a difficulty that
## can fail; otherwise it just finishes late.

@export var id: StringName
@export var title: String
@export_multiline var description: String
## The sample layout to start from (a SamplePrisons index).
@export var layout := 0
## Money to start with, or -1 for the difficulty's.
@export var starting_money := -1
## Stars the prison starts on, as if it had had a few nights at that
## grade; 0 to start as usual.
@export var starting_grade := 0
## Prisoners to start with in all; more than the layout has arrive on day
## one, beds or no beds.
@export var starting_prisoners := 0
## All of these done wins.
@export var win_goals: Array[GoalDef] = []
## Days to win in; 0 for no limit.
@export var day_limit := 0
