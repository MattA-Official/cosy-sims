class_name DifficultyDef
extends Resource
## How kind the game is: scales on money, tempers, reform and reoffending,
## and whether it can be lost.

@export var id: StringName
@export var display_name: String
@export_multiline var description: String
## Money a new game starts with.
@export var starting_money := 20000
@export var grant_scale := 1.0
@export var wage_scale := 1.0
## Scales how quickly tempers rise.
@export var misconduct_scale := 1.0
## Scales reform lost on bad days.
@export var reform_loss_scale := 1.0
## Scales the chance a leaver comes back.
@export var reoffend_scale := 1.0
## Whether breaking a fail rule loses the game; otherwise it only warns.
@export var can_fail := false
@export var fail_rules: Array[FailRule] = []
