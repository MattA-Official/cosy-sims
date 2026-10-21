extends Surprise
## A television chef cooks in the kitchen for a season: every good meal is
## a lovely one while they're here, and the papers love it. When hard, their
## fans throw things over the fence each day.

const SOURCE := &"celebrity_chef"
const NAMES: Array[String] = ["Delia Crumble", "Gordon Rumsey", "Nigella Lawless", "Jamie Olive", "Rick Steamer"]

var chef := ""
var welcomed := false
var _hours := 0.0


func start() -> void:
	chef = NAMES[randi() % NAMES.size()]


func choose(index: int) -> void:
	if index != 0:
		minutes_left = 0.0
		return
	_welcome()
	(main.reputation as Reputation).report(&"celebrity", chef)


func _welcome() -> void:
	welcomed = true
	(main.modifiers as Modifiers).set_source(SOURCE, {&"tasty_meals": 1.0})


func tick(minutes: float) -> void:
	if not hard or not welcomed:
		return
	_hours += minutes / 60.0
	if _hours >= 24.0:
		_hours = 0.0
		(main.contraband as Contraband).throw_over(true)


func finish() -> void:
	(main.modifiers as Modifiers).clear_source(SOURCE)


func words() -> String:
	var days := ceili(minutes_left / 60.0 / 24.0)
	return "%s, %d day%s left" % [chef, days, "" if days == 1 else "s"]


func to_data() -> Dictionary:
	return {"chef": chef, "hours": _hours, "welcomed": welcomed}


func from_data(data: Dictionary) -> void:
	chef = data.get("chef", NAMES[0])
	_hours = float(data.get("hours", 0.0))
	if data.get("welcomed", false):
		_welcome()
