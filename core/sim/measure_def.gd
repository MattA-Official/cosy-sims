class_name MeasureDef
extends Resource
## One of the measures a place is graded on each night, such as Safety:
## the game works out a value, and `lines` turn it into one to five stars.

@export var id: StringName
@export var display_name: String
## The values for 2, 3, 4 and 5 stars, worst to best.
@export var lines: Array[float] = []
## Lower values are better, such as incidents.
@export var lower_is_better := false
## How much it counts towards the grade.
@export var weight := 1.0


## Stars, 1 to 5, for a value.
func stars(value: float) -> int:
	var out := 1
	for line in lines:
		if (value <= line) if lower_is_better else (value >= line):
			out += 1
	return out
