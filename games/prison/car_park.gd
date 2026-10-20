class_name CarPark
extends Node
## Staff who can drive in do: with a car park by the road, each arriving
## member of staff comes by car, parks in a free bay and walks in from
## there, and walks back to the car to go home. Without a free bay they
## walk in from the entrance as before.
##
## Bays are car park floor tiles in pairs along Z, one car to a pair, so
## the lines on the floor sit between the cars.

const BAY_FLOOR := &"car_park"
## Staff cars and car parks, behind a setting (Main's Staff Cars) for now.
static var enabled := false
## How far from a road, in tiles, a bay can be and still be driven to.
const ROAD_REACH := 10.0

var building: Building
var vehicles: Vehicles
var roads: Roads
var shifts: Shifts
var cars: Array[PackedScene] = []

## Drivers on site: Person to [car, bay].
var _drivers: Dictionary[Person, Array] = {}
var _taken: Dictionary[Vector2i, bool] = {}
var _rng := RandomNumberGenerator.new()


func start() -> void:
	shifts.ride_in = ride_in
	shifts.way_out = way_out
	shifts.left.connect(_on_left)


## Every bay on the ground floor, by its first tile.
func bays() -> Array[Vector2i]:
	var map := building.ground()
	var out: Array[Vector2i] = []
	for cell: Vector2i in map.floors:
		if map.floors[cell] != BAY_FLOOR or map.floors.get(cell - Vector2i(0, 1)) == BAY_FLOOR:
			continue
		# The top of a run: pair the tiles from here down.
		var z := cell
		while map.floors.get(z) == BAY_FLOOR and map.floors.get(z + Vector2i(0, 1)) == BAY_FLOOR:
			out.append(z)
			z += Vector2i(0, 2)
	return out


func free_bays() -> Array[Vector2i]:
	return bays().filter(func(bay: Vector2i) -> bool:
		if _taken.has(bay):
			return false
		var hit := roads.nearest(middle(bay))
		return not hit.is_empty() and hit[2] <= ROAD_REACH)


static func middle(bay: Vector2i) -> Vector2:
	return Vector2(bay) + Vector2(0.5, 1.0)


## Brings someone in by car if a bay's free. Returns whether they're coming.
func ride_in(role: StringName, shift: StringName) -> bool:
	var free := free_bays()
	if free.is_empty() or cars.is_empty():
		return false
	var bay := free[_rng.randi() % free.size()]
	var model := cars[_rng.randi() % cars.size()]
	var car := vehicles.drive_in(model, middle(bay), func(parked: Node3D) -> void:
		parked.rotation.y = snappedf(parked.rotation.y, PI)
		var person := shifts.come_in(role, shift, [0, middle(bay)])
		if person == null:
			_taken.erase(bay)
			vehicles.drive_out(parked)
			return
		_drivers[person] = [parked, bay], -1.0, true)
	if car == null:
		return false
	_taken[bay] = true
	return true


## Parks a car for each member of staff already here, such as at the
## start or after loading, while there are bays.
func park_staff_here() -> void:
	for person in shifts.people.people:
		if person.role == &"" or person.going_home or _drivers.has(person) or cars.is_empty():
			continue
		var free := free_bays()
		if free.is_empty():
			return
		var bay := free[0]
		var car := vehicles.park(cars[_rng.randi() % cars.size()], middle(bay))
		if car == null:
			return
		car.rotation.y = snappedf(car.rotation.y, PI)
		_drivers[person] = [car, bay]
		_taken[bay] = true


## Back to their car, for those who came in one.
func way_out(person: Person) -> Array:
	return [0, middle(_drivers[person][1])] if _drivers.has(person) else []


func _on_left(person: Person) -> void:
	if not _drivers.has(person):
		return
	var entry: Array = _drivers[person]
	_drivers.erase(person)
	_taken.erase(entry[1])
	vehicles.drive_out(entry[0])
