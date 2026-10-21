class_name Brain
extends RefCounted
## What decides someone's next move once they are free to choose. People
## asks a person's own brain first, then their group's (see People.brains),
## after anything in People.deciders has had its say. Walking, doors, needs
## and mood carry on the same whichever brain is deciding, so a brain only
## has to start Actions.


## Starts whatever they do next. False leaves it to their group's brain.
func decide(_people: People, _person: Person, _may_wander: bool) -> bool:
	return false
