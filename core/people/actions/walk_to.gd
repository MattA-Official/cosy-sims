class_name WalkTo
extends Action
## Walk to one spot, in tile units across the ground.

var level := 0
var spot := Vector2.ZERO


func _init(on_level := 0, to := Vector2.ZERO) -> void:
	level = on_level
	spot = to


func start(people: People, person: Person) -> bool:
	people.stop(person)
	return people.walk_to(person, level, spot, "Walking")
