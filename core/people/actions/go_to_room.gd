class_name GoToRoom
extends Action
## Walk to somewhere free in a room.

var level := 0
var room: Room


func _init(on_level := 0, to: Room = null) -> void:
	level = on_level
	room = to


func start(people: People, person: Person) -> bool:
	return people.go_to_room(person, level, room)
