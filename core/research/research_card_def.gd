class_name ResearchCardDef
extends Resource
## One card on the research board.

enum Rule { ALL = 0, ANY = 1 }

@export var id: StringName
@export var display_name: String
## What it gives, in words.
@export var gives_text: String
## The department whose head works it, or &"office" for the warden's wedge.
@export var department: StringName
@export var tier := 1
## Know-how kind id -> amount; the first key is the main kind.
@export var knowhow: Dictionary[StringName, int] = {}
## Desk minutes after paying the know-how.
@export var desk_minutes := 480.0
@export var requires: Array[StringName] = []
## 0 = all of `requires`, 1 = any one, N = any N of them.
@export var rule := 0
## Null for face up from the start.
@export var reveal: RevealDef
## Effects as dictionaries, run by Research when it's done, such as
## {"modifier": "guard_walk_speed", "amount": 0.1}.
@export var effects: Array[Dictionary] = []
## A policy, tried in one wing before it's rolled out.
@export var trial := false
## -1 caring, 0, +1 strict.
@export var lean := 0
## The pick-one partner's id, or empty.
@export var pair: StringName
## The add-on that owns it; hidden without it. Hooks are base cards.
@export var addon: StringName
@export var repeatable := false


func main_kind() -> StringName:
	return knowhow.keys()[0] if not knowhow.is_empty() else &""


func kinds() -> Array[StringName]:
	var out: Array[StringName] = []
	out.assign(knowhow.keys())
	return out


## How many of `requires` must be done.
func needed() -> int:
	if requires.is_empty():
		return 0
	return requires.size() if rule == Rule.ALL else mini(rule, requires.size())
