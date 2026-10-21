class_name Wander
extends Action
## Potter about nearby, keeping to where they are allowed.


func start(people: People, person: Person) -> bool:
	people.wander(person)
	return true
