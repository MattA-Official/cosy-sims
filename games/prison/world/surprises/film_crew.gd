extends Surprise
## A film crew makes a documentary for the day: they tour like an open day,
## and how nice the rooms they saw were decides how it looks on screen. When
## hard, the messiest room they saw decides it.

const CREW := 2
## Loaded when needed: the catalogue that lists this script is used by it.
const WORLD := "res://games/prison/world/prison_world.gd"

var _crew: Array[Person] = []


func choose(index: int) -> void:
	if index != 0:
		minutes_left = 0.0
		return
	_crew = load(WORLD).open_doors(main, CREW, false)
	for person in _crew:
		person.profile["film_crew"] = true
		person.activity = "Filming a documentary"
	if _crew.is_empty():
		minutes_left = 0.0


func finish() -> void:
	if _crew.is_empty():
		return
	var world: GDScript = load(WORLD)
	var score: float = world.tour_score(main, _crew, hard)
	if score > world.OPEN_GOOD:
		(main.reputation as Reputation).report(&"film_good")
	elif score < world.OPEN_BAD:
		(main.reputation as Reputation).report(&"film_bad")
	main.set_meta(&"film_score", score)
	world.see_off(main, _crew)
	_crew.clear()


func words() -> String:
	return "Filming" if not _crew.is_empty() else "Waiting for an answer"


func from_data(_data: Dictionary) -> void:
	var people: People = main.people
	for person in people.people:
		if person.profile.has("film_crew"):
			_crew.append(person)
