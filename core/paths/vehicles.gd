class_name Vehicles
extends Node3D
## Vehicles on the roads: the intake bus, the delivery lorry, staff cars,
## and cars just passing through. Each comes out of a tunnel to a stop, waits until told to
## go, then turns round and drives back out the way it came. They move
## with game time, so they stop when the game is paused.

## Tiles a vehicle drives in a game minute.
const SPEED := 3.0
## Tiles a flying vehicle takes to climb or land.
const CLIMB := 4.0

var roads: Roads
var cell_size := 1.0
## (point: Vector2) -> float: the ground's height at a point in tiles.
var ground_at: Callable
## (tile spot) -> float: the water's surface there, or -INF; for boats.
## Optional.
var water_at: Callable
## (point: Vector2) -> bool: whether a vehicle there can be seen, not in
## a tunnel. Optional.
var shown_at: Callable
## Models whose front isn't +Z, with the turn from +Z to their front,
## such as -PI / 2 for a front towards +X.
var front_turns: Dictionary[PackedScene, float] = {}
var clock: GameClock:
	set(value):
		clock = value
		clock.advanced.connect(_drive)

## Vehicles on the move: Node3D to [points, distance along, on arrival].
var _trips: Dictionary[Node3D, Array] = {}
## Parked vehicles and the way they came in, for leaving.
var _parked: Dictionary[Node3D, PackedVector2Array] = {}
## Game minutes left before parked vehicles leave on their own.
var _stays: Dictionary[Node3D, float] = {}
## (point: Vector2) -> float: game minutes a vehicle passing a point is
## held up, such as by a crowd at the gate; 0 for none. Each vehicle is
## held once at most.
var holds: Array[Callable] = []
## Vehicles held up -> game minutes left.
var _held: Dictionary[Node3D, float] = {}


## Sends a vehicle in by road to the road point nearest `to`, or with
## `off_road` on to `to` itself. Calls
## `arrived` (with the vehicle) once there. Given a stay, it drives off
## again after that many game minutes; otherwise it waits for drive_out().
## Returns the vehicle, or null if no road leads there.
func drive_in(model: PackedScene, to: Vector2, arrived := Callable(), stay := -1.0,
		off_road := false) -> Node3D:
	var points := roads.route_in(to) if roads != null else PackedVector2Array()
	if points.size() < 2 or model == null:
		return null
	if off_road:
		# On from the road to the spot itself, such as a parking bay.
		points.append(to)
	var vehicle := model.instantiate() as Node3D
	vehicle.set_meta(&"turn", front_turns.get(model, 0.0))
	add_child(vehicle)
	_trips[vehicle] = [points, 0.0, arrived]
	if stay >= 0.0:
		_stays[vehicle] = stay
	_place(vehicle, points, 0.0)
	return vehicle


## Brings a vehicle in along `points` (tiles) rather than the road, such
## as a ferry over water or a helicopter through the air, `lift` tiles up
## while under way. Otherwise like drive_in. Returns it, or null.
func arrive_along(model: PackedScene, points: PackedVector2Array, arrived := Callable(), stay := -1.0,
		lift := 0.0, afloat := false) -> Node3D:
	if points.size() < 2 or model == null:
		return null
	var vehicle := model.instantiate() as Node3D
	vehicle.set_meta(&"turn", front_turns.get(model, 0.0))
	if lift > 0.0:
		vehicle.set_meta(&"lift", lift)
	if afloat:
		vehicle.set_meta(&"afloat", true)
	add_child(vehicle)
	_trips[vehicle] = [points, 0.0, arrived]
	if stay >= 0.0:
		_stays[vehicle] = stay
	_place(vehicle, points, 0.0)
	return vehicle


## Whether a vehicle could drive in to the road point nearest `to`.
func has_route_to(to: Vector2) -> bool:
	return roads != null and roads.route_in(to).size() >= 2


## Puts a vehicle already parked at `to`, off the road, as if it had
## driven in. Returns it, or null if no road leads there.
func park(model: PackedScene, to: Vector2) -> Node3D:
	var points := roads.route_in(to) if roads != null else PackedVector2Array()
	if points.size() < 2 or model == null:
		return null
	points.append(to)
	var vehicle := model.instantiate() as Node3D
	vehicle.set_meta(&"turn", front_turns.get(model, 0.0))
	add_child(vehicle)
	_place(vehicle, points, Roads._length(points))
	_parked[vehicle] = points
	return vehicle


## Drives a vehicle along `points` (tiles) and away at the end, such as a
## car passing through. Returns it, or null.
func drive_through(model: PackedScene, points: PackedVector2Array) -> Node3D:
	if points.size() < 2 or model == null:
		return null
	var vehicle := model.instantiate() as Node3D
	vehicle.set_meta(&"turn", front_turns.get(model, 0.0))
	add_child(vehicle)
	_trips[vehicle] = [points, 0.0, func(gone: Node3D) -> void:
		_parked.erase(gone)
		_held.erase(gone)
		gone.queue_free()]
	_place(vehicle, points, 0.0)
	return vehicle


## Turns a parked vehicle round and drives it back out, then it's gone.
func drive_out(vehicle: Node3D) -> void:
	if vehicle == null or not is_instance_valid(vehicle):
		return
	var points: PackedVector2Array = _parked.get(vehicle, PackedVector2Array())
	_parked.erase(vehicle)
	_stays.erase(vehicle)
	if _trips.has(vehicle):
		var trip: Array = _trips[vehicle]
		points = (trip[0] as PackedVector2Array).slice(0, _index_at(trip[0], trip[1]) + 1)
		_trips.erase(vehicle)
	if points.size() < 2:
		vehicle.queue_free()
		return
	points.reverse()
	_trips[vehicle] = [points, 0.0, func(gone: Node3D) -> void:
		_parked.erase(gone)
		_held.erase(gone)
		gone.queue_free()]


## Whether a vehicle is still on its way to its stop.
func is_driving(vehicle: Node3D) -> bool:
	return _trips.has(vehicle)


## Vehicles parked at their stops.
func parked() -> Array[Node3D]:
	var out: Array[Node3D] = []
	for vehicle: Node3D in _parked:
		out.append(vehicle)
	return out


func _drive(minutes: float) -> void:
	for vehicle: Node3D in _stays.keys():
		if _parked.has(vehicle):
			_stays[vehicle] -= minutes
			if _stays[vehicle] <= 0.0:
				drive_out(vehicle)
	for vehicle: Node3D in _trips.keys():
		if not is_instance_valid(vehicle):
			_trips.erase(vehicle)
			continue
		if _held.get(vehicle, 0.0) > 0.0:
			_held[vehicle] -= minutes
			continue
		if not _held.has(vehicle) and vehicle.has_meta(&"at"):
			for hold in holds:
				var wait: float = hold.call(vehicle.get_meta(&"at"))
				if wait > 0.0:
					_held[vehicle] = wait
					break
		var trip: Array = _trips[vehicle]
		var points: PackedVector2Array = trip[0]
		trip[1] = minf(trip[1] + SPEED * minutes, Roads._length(points))
		_place(vehicle, points, trip[1])
		if trip[1] >= Roads._length(points):
			_trips.erase(vehicle)
			_parked[vehicle] = points
			var arrived: Callable = trip[2]
			if arrived.is_valid():
				arrived.call(vehicle)


## Puts a vehicle `along` tiles down its route, facing the way it goes.
func _place(vehicle: Node3D, points: PackedVector2Array, along: float) -> void:
	var i := _index_at(points, along)
	var before := 0.0
	for k in i:
		before += points[k].distance_to(points[k + 1])
	var a := points[i]
	var b := points[mini(i + 1, points.size() - 1)]
	var gap := maxf(a.distance_to(b), 0.0001)
	var at := a.lerp(b, clampf((along - before) / gap, 0.0, 1.0))
	var height: float = ground_at.call(at) if ground_at.is_valid() else 0.0
	if vehicle.has_meta(&"afloat") and water_at.is_valid():
		height = maxf(height, water_at.call(at))
	if vehicle.has_meta(&"lift"):
		# Climbs from the start and lands at the end, CLIMB tiles each.
		var left := Roads._length(points) - along
		height += float(vehicle.get_meta(&"lift")) * clampf(minf(along, left) / CLIMB, 0.0, 1.0)
	vehicle.position = Vector3(at.x * cell_size, height, at.y * cell_size)
	vehicle.set_meta(&"at", at)
	vehicle.visible = not shown_at.is_valid() or shown_at.call(at)
	if b != a:
		vehicle.rotation.y = atan2(b.x - a.x, b.y - a.y) + float(vehicle.get_meta(&"turn", 0.0))


## The index of the point starting the piece of the route `along` tiles in.
static func _index_at(points: PackedVector2Array, along: float) -> int:
	var total := 0.0
	for i in points.size() - 1:
		total += points[i].distance_to(points[i + 1])
		if total >= along:
			return i
	return maxi(points.size() - 2, 0)
