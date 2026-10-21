class_name PlayerBrain
extends Brain
## Someone the player steers, for Escape Mode: they do the orders given
## them, one at a time, and otherwise stand still unless `needs_when_idle`
## lets their needs and the timetable decide meanwhile.

## Orders still to do, first first.
var orders: Array[Action] = []
## With no orders left, decide by needs as anyone else would.
var needs_when_idle := false
## The order being carried out, or null.
var doing: Action = null


## Adds an order; `now` drops the rest and starts it at once.
func order(people: People, person: Person, action: Action, now := true) -> bool:
	if now:
		orders.clear()
		orders.append(action)
		return decide(people, person, false)
	orders.append(action)
	return true


func decide(people: People, person: Person, _may_wander: bool) -> bool:
	while not orders.is_empty():
		var action: Action = orders.pop_front()
		if action.start(people, person):
			doing = action
			return true
	doing = null
	if needs_when_idle:
		return false
	person.activity = "Waiting for orders"
	person.timer = 1.0
	return true
