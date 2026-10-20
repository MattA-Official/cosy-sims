class_name NeedDef
extends Resource
## Something people need, such as sleep, and what meets it. Needs run from
## 100 (met) down to 0. People go to see to one once it drops below the
## line, and choose between several by how low each is (see People).
## Rates are per game hour, so the length of a day never retunes them.

enum Source {
	OBJECT, ## Using an object with one of `object_tags`, such as a bed.
	OUTDOORS, ## Being outdoors: in a yard, or out on the ground.
	COMPANY, ## Being near other people who are up and about.
}

@export var id: StringName
@export var display_name: String
@export var source := Source.OBJECT
## For OBJECT: objects with any of these tags see to the need, such as
## "bed" for sleep.
@export var object_tags: Array[StringName] = []
## What people are doing while they see to it, such as "Sleeping".
@export var doing: String
## How the inspector says the need is low or well met, such as "Hungry"
## and "Well fed".
@export var low_text: String
@export var high_text: String
## People only go out of their way to see to it below this, with nothing
## else to do. Sleep waits for bedtime unless it is low; bladder doesn't
## send people to the toilet every half hour.
@export var seek_below := 70.0
## Points lost per game hour while awake. For OUTDOORS and COMPANY, only
## while indoors or alone.
@export var decay_per_hour := 4.0
## Points lost per game hour while asleep.
@export var asleep_decay_per_hour := 1.0
## Game minutes it takes to see to it from empty. For OUTDOORS and
## COMPANY, how long being outdoors or in company takes to fill it.
@export var use_minutes := 20.0
## Seeing to this need is sleeping, so the others run down at their asleep
## rate meanwhile.
@export var sleeping := false
## A moodlet for when the need runs right out, such as an accident when
## bladder does. The need is then met again, at a cost to other needs.
@export var empty_moodlet: StringName
## Need id: points lost when this one runs out (an accident costs hygiene).
@export var empty_costs: Dictionary[StringName, float] = {}
## A moodlet for being locked in (a block that locks their own room
## starting) with this need below the line, such as going to bed hungry.
@export var shut_in_moodlet: StringName
## A moodlet for seeing to the need right up, such as a good chat.
@export var met_moodlet: StringName


## Whether an object with this tag sees to the need.
func met_by(tag: StringName) -> bool:
	return source == Source.OBJECT and object_tags.has(tag)


## The tag a timetable block must allow for people to see to this need:
## the object's tag, or the need's own id for OUTDOORS and COMPANY.
func allowed_by(block: ActivityDef, tag: StringName = &"") -> bool:
	if block == null:
		return true
	if source != Source.OBJECT:
		return block.allows(id)
	if tag != &"":
		return block.allows(tag)
	return object_tags.any(func(t: StringName) -> bool: return block.allows(t))


## Whether the need fills from somewhere to be rather than an object.
func by_place() -> bool:
	return source != Source.OBJECT
