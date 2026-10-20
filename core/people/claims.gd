class_name Claims
extends Node
## People claim things as their own: prisoners their bed (see People), and
## staff whatever their role says, such as the warden an office desk.
## Claiming the desk rather than the room lets an open-plan office work.
## A claimed surface sets itself out for its owner (a nameplate and an
## in-tray for the warden); an unclaimed one is bare. The dressing is
## only for show, so it never gets in the way of building.

## Seconds between checks while running.
const CHECK_SECONDS := 1.0

var people: People
var building: Building
## For each role id, its def.
var roles: Dictionary[StringName, StaffRoleDef] = {}

## Who has claimed what, as (level, object id).
var _claims: Dictionary[Person, Vector2i] = {}
## Surfaces set out last time, as (level, object id).
var _dressed: Dictionary[Vector2i, bool] = {}
var _wait := 0.0


func _process(delta: float) -> void:
	_wait -= delta
	if _wait <= 0.0:
		_wait = CHECK_SECONDS
		refresh()


## What someone has claimed, or Person.NO_OBJECT.
func claim_of(person: Person) -> Vector2i:
	return _claims.get(person, Person.NO_OBJECT)


## Who has claimed something, or null.
func owner_of(key: Vector2i) -> Person:
	for person: Person in _claims:
		if _claims[person] == key:
			return person
	return null


## Keeps each claim that still stands, gives anyone without one the nearest
## free thing their role claims, and sets out the claimed surfaces.
func refresh() -> void:
	for person: Person in _claims.keys():
		var role: StaffRoleDef = roles.get(person.role)
		if not people.people.has(person) or person.going_home or role == null \
				or not _tagged(_claims[person], role.claims):
			_claims.erase(person)
	var taken: Dictionary[Vector2i, bool] = {}
	for key: Vector2i in _claims.values():
		taken[key] = true
	for person in people.people:
		var role: StaffRoleDef = roles.get(person.role)
		if role == null or role.claims == &"" or person.going_home or _claims.has(person):
			continue
		var best := Person.NO_OBJECT
		var best_distance := INF
		for key in building.objects_tagged([role.claims]):
			if taken.has(key):
				continue
			var placed := building.object_at(key)
			var distance := placed.centre.distance_to(person.flat()) + absi(key.x - person.level) * 12.0
			if distance < best_distance:
				best = key
				best_distance = distance
		if best != Person.NO_OBJECT:
			_claims[person] = best
			taken[best] = true
	_dress()


func _dress() -> void:
	var now: Dictionary[Vector2i, bool] = {}
	for person: Person in _claims:
		var key := _claims[person]
		var things: Array = []
		for def in (roles[person.role] as StaffRoleDef).dressing:
			things.append([def, PI if def.faces_out else 0.0])
		building.levels[key.x].set_dressing(key.y, things)
		now[key] = true
	for key: Vector2i in _dressed:
		if not now.has(key) and building.levels.has(key.x):
			building.levels[key.x].set_dressing(key.y, [])
	_dressed = now


func _tagged(key: Vector2i, tag: StringName) -> bool:
	var placed := building.object_at(key)
	return placed != null and placed.def.tags.has(tag)
