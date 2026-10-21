class_name Action
extends RefCounted
## One thing a brain can tell someone to do. Starting it sets them walking
## or working; People carries it through from there.


## Starts it; false when it can't be done just now.
func start(_people: People, _person: Person) -> bool:
	return false
