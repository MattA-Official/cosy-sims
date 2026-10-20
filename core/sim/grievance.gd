class_name Grievance
extends RefCounted
## What a crowd is upset about together: the bad mood part (such as
## "Hungry" or "Missed a meal") that most of them have among their worst
## few. A prison sit-in, a school walk-out.


## The shared complaint, or "" if most of them don't share one. `top` is
## how many of each person's worst parts count.
static func shared(people: Array, top := 3, share := 0.5) -> String:
	if people.is_empty():
		return ""
	var counts: Dictionary[String, int] = {}
	for person: Person in people:
		for part: Array in worst(person, top):
			counts[part[0]] = counts.get(part[0], 0) + 1
	var best := ""
	for text: String in counts:
		if counts[text] > people.size() * share and (best.is_empty() or counts[text] > counts[best]):
			best = text
	return best


## Someone's worst few mood parts, worst first.
static func worst(person: Person, top := 3) -> Array:
	var bad: Array = person.mood_parts.filter(func(part: Array) -> bool: return part[1] < 0.0)
	bad.sort_custom(func(a: Array, b: Array) -> bool: return a[1] < b[1])
	return bad.slice(0, top)


## Whether someone still has a complaint among their worst few.
static func has(person: Person, text: String, top := 3) -> bool:
	return worst(person, top).any(func(part: Array) -> bool: return part[0] == text)
