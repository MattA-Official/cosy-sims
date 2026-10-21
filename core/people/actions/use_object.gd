class_name UseObject
extends Action
## Go and use one object, queuing or fetching what it needs as usual.

var level := 0
var placed: BuildingMap.PlacedObject


func _init(on_level := 0, object: BuildingMap.PlacedObject = null) -> void:
	level = on_level
	placed = object


func start(people: People, person: Person) -> bool:
	return people.use_object(person, level, placed)
