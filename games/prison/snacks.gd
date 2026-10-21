class_name Snacks
extends Node
## Snack machines: anyone peckish in their free time can get a snack, once
## a day. It takes the edge off their hunger (up to SNACK_HUNGER, not a
## full meal), cheers them a little, and the prison takes the money.

const TAG := &"snack_machine"
const HUNGER := &"hunger"
## A snack leaves hunger no higher than this.
const SNACK_HUNGER := 80.0
## What the prison makes on each snack.
const PRICE := 2
const LINE := "Snacks"

var ledger: Ledger
var clock: GameClock
var people: People:
	set(value):
		people = value
		people.use_filters.append(func(person: Person, placed: BuildingMap.PlacedObject) -> bool:
			return not placed.def.tags.has(TAG) or not had_one_today(person))
		people.used.connect(_on_used)


func had_one_today(person: Person) -> bool:
	return clock != null and person.profile.get("snack_day", -1) == clock.day()


func _on_used(person: Person, placed: BuildingMap.PlacedObject) -> void:
	if placed == null or not placed.def.tags.has(TAG):
		return
	if clock != null:
		person.profile["snack_day"] = clock.day()
	person.needs[HUNGER] = minf(person.needs.get(HUNGER, 100.0), SNACK_HUNGER)
	# Topping hunger right up counted as a good meal: it wasn't one.
	var good: MoodletDef = PrisonCatalogue.moodlets()[&"good_meal"]
	if person.moodlets.get(&"good_meal", 0.0) >= good.hours * 60.0 - 1.0:
		person.moodlets.erase(&"good_meal")
	people.add_moodlet(person, &"had_a_snack")
	if ledger != null:
		ledger.add(PRICE, LINE)
