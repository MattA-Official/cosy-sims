class_name GoalDef
extends Resource
## Something to work towards, paying a grant when done: house 20
## prisoners, open a workshop, grant parole five times. The game says what
## each `kind` measures (see Standing.goal_value); the goal is done when
## that reaches `amount`, or with `hold_days`, when it has at that many
## midnights in a row.

@export var id: StringName
@export var title: String
@export var grant := 1000
## Such as &"prisoners", &"has_room", &"grade", &"measure",
## &"goods_sold", &"courses_passed", &"parole_granted",
## &"released_reformed", &"average_mood".
@export var kind: StringName
@export var amount := 1.0
## A room type or measure the kind is about, such as &"workshop".
@export var target: StringName
## Midnights in a row it must hold; 0 for as soon as it's true.
@export var hold_days := 0
## Counted from when the goal comes up rather than from the start, such
## as courses passed.
@export var counted := false
