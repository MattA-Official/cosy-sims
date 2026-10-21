class_name NeedsBrain
extends Brain
## The usual brain: needs, the timetable and work, as People describes.


func decide(people: People, person: Person, may_wander: bool) -> bool:
	people.decide_by_needs(person, may_wander)
	return true
