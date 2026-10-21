class_name StaffBus
extends Node
## Staff come to work on the bus (unless staff cars are on; see CarPark).
## Before each shift a bus brings everyone starting it to the bus stop, and
## they walk in from there; going home, staff walk back to the stop and
## catch a bus there. Without a road the bus can't come, so staff walk in
## from the entrance as before.

## Game minutes a bus waits at the stop before driving off.
const STAY := 20.0
## Game minutes after a bus has been that another comes for staff going
## home.
const PICK_UP_GAP := 30.0

var vehicles: Vehicles
var intake: Intake
var shifts: Shifts
var bus_model: PackedScene
## Ways in (see Arrivals). Optional.
var arrivals: Arrivals
var clock: GameClock:
	set(value):
		clock = value
		clock.advanced.connect(func(minutes: float) -> void: _since_bus += minutes)

## Staff on the bus that's on its way, as [role, shift] pairs.
var _riders: Array = []
var _bus: Node3D
var _since_bus := INF


func start() -> void:
	shifts.ride_in = ride_in
	shifts.way_out = way_out
	shifts.left.connect(_on_left)


## Puts someone on the next bus in. Returns whether a bus can come.
func ride_in(role: StringName, shift: StringName) -> bool:
	if _bus == null or not vehicles.is_driving(_bus):
		if arrivals != null and not arrivals.closed_reason(Arrivals.STAFF).is_empty():
			return false
		_bus = arrivals.send(Arrivals.STAFF, bus_model, intake.stop_point(), _step_off, STAY) if arrivals != null \
				else vehicles.drive_in(bus_model, intake.stop_point(), _step_off, STAY)
		if _bus == null:
			return false
		_riders.clear()
	_riders.append([role, shift])
	_since_bus = 0.0
	return true


## Back to the bus stop, when there is a road for the bus.
func way_out(_person: Person) -> Array:
	if arrivals != null:
		var off := arrivals.step_off(Arrivals.STAFF)
		if not off.is_empty():
			return off
	return intake.arrival_spot() if not vehicles.roads.edge_nodes().is_empty() else []


func _step_off(_vehicle: Node3D) -> void:
	var spot := arrivals.step_off(Arrivals.STAFF) if arrivals != null else []
	if spot.is_empty():
		spot = intake.arrival_spot()
	for rider: Array in _riders:
		shifts.come_in(rider[0], rider[1], spot)
	_riders.clear()
	_bus = null


## Someone going home has reached the stop: a bus comes for them unless
## one has just been.
func _on_left(_person: Person) -> void:
	if _since_bus < PICK_UP_GAP or vehicles.roads.edge_nodes().is_empty():
		return
	_since_bus = 0.0
	if arrivals != null:
		arrivals.send(Arrivals.STAFF, bus_model, intake.stop_point(), Callable(), STAY)
	else:
		vehicles.drive_in(bus_model, intake.stop_point(), Callable(), STAY)
