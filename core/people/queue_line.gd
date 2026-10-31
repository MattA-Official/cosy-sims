class_name QueueLine
extends RefCounted
## A line of people waiting their turn, in the order they joined, standing
## along a route from the front (beside the counter or desk) back through
## any queue posts the player has put down. Past the last post the line
## carries straight on the way the last stretch was heading.
##
## Pure data: People, check-in desks and the like keep one per thing that
## serves, and walk each person to spot(index_of(person)).

## Room each person takes up along the line, in tiles.
const GAP := 0.75

## The route, front first, in tile units.
var route := PackedVector2Array()
## Who is waiting, front first.
var members: Array[Person] = []
var gap := GAP


static func along(points: PackedVector2Array, spacing := GAP) -> QueueLine:
	var line := QueueLine.new()
	line.route = points
	line.gap = spacing
	return line


## Joins someone at the back, or leaves them where they are if already in
## the line. Returns their place: 0 at the front.
func join(person: Person) -> int:
	if not members.has(person):
		members.append(person)
	return members.find(person)


## Takes someone out of the line; everyone behind moves up a place.
func leave(person: Person) -> bool:
	if not members.has(person):
		return false
	members.erase(person)
	return true


## Someone's place, 0 at the front, or -1 if they aren't in it.
func index_of(person: Person) -> int:
	return members.find(person)


## Who is at the front, or null if nobody is waiting.
func front() -> Person:
	return members[0] if not members.is_empty() else null


## Serves whoever is at the front: they leave and the rest move up.
func serve() -> Person:
	var first := front()
	if first != null:
		members.remove_at(0)
	return first


func size() -> int:
	return members.size()


## How long the posted route is, in tiles.
func length() -> float:
	var total := 0.0
	for i in range(1, route.size()):
		total += route[i - 1].distance_to(route[i])
	return total


## How many fit along the posts before the line runs past the last one.
func room() -> int:
	return floori(length() / gap) + 1


## Is the line longer than its posts?
func overflowing() -> bool:
	return members.size() > room()


## Where the person in a place stands: `index` places of `gap` back along
## the route from the front.
func spot(index: int) -> Vector2:
	if route.is_empty():
		return Vector2.ZERO
	var left := index * gap
	for i in range(1, route.size()):
		var stretch := route[i - 1].distance_to(route[i])
		if left <= stretch:
			return route[i - 1].move_toward(route[i], left)
		left -= stretch
	var last := route[route.size() - 1]
	var heading := Vector2.DOWN
	if route.size() >= 2:
		heading = (last - route[route.size() - 2]).normalized()
	return last + heading * left


## The route a line takes from `front` through the queue posts on a level:
## each next post is the nearest unused one within `reach` of the last
## point, so a row of posts laid out in a snake makes a snaking line. Just
## [front] when there are no posts nearby.
static func posted_route(map: BuildingMap, front: Vector2, tag: StringName = &"queue_post",
		reach := 2.5) -> PackedVector2Array:
	var posts: Array[Vector2] = []
	for placed: BuildingMap.PlacedObject in map.objects.values():
		if placed.def.tags.has(tag):
			posts.append(placed.centre)
	var out := PackedVector2Array([front])
	var here := front
	while not posts.is_empty():
		var best := -1
		for i in posts.size():
			if posts[i].distance_to(here) <= reach and (best == -1
					or posts[i].distance_to(here) < posts[best].distance_to(here)):
				best = i
		if best == -1:
			break
		here = posts[best]
		out.append(here)
		posts.remove_at(best)
	return out
