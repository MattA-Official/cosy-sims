class_name Arrivals
extends Node
## Every way in. Arrival points (ArrivalPointDef) are placed objects the
## location allows; each kind of thing carried (prisoners, staff, visitors,
## deliveries) has a Trip that says which point it uses. The game's systems
## ask send() for their vehicle instead of driving it in themselves: it
## brings the vehicle to the trip's point by the point's route, and a trip
## a point's weather closes is cancelled for the day. ROAD drives in as
## before; WATER sails in from the map edge; AIR and CABLE fly or ride in
## over travel_minutes. With no point placed, a trip falls back to the road
## and the game's own spot, as before. Shared by any game.

const PRISONERS := &"prisoners"
const STAFF := &"staff"
const VISITORS := &"visitors"
const DELIVERIES := &"deliveries"
const CARRIES: Array[StringName] = [PRISONERS, STAFF, VISITORS, DELIVERIES]
const WORDS := {PRISONERS: "New prisoners", STAFF: "Staff", VISITORS: "Visitors", DELIVERIES: "Deliveries"}
## How high a flying vehicle cruises, and over how many tiles it climbs or
## lands.
const FLY_HEIGHT := 4.0

## A trip was called off, with why, such as "The storm closed the dock".
signal cancelled(carries: StringName, reason: String)

## The kind of thing a trip carries -> the point id it uses; missing for
## whichever point is placed.
class Trip:
	var carries: StringName
	var point: StringName

var location: LocationDef
var points: Array[ArrivalPointDef] = []
var trips: Dictionary[StringName, Trip] = {}
var building: Building
var people: People
var vehicles: Vehicles
## The whole map in tiles, for where boats and aircraft come from.
var map_size := Vector2i(96, 96)
## () -> StringName: today's weather id. Optional.
var weather_id: Callable
## (carries) -> int: the hour a trip comes, for the timetable. Optional.
var hour_of: Callable
## (carries) -> bool: whether the player may pick a trip's point, such as
## deliveries with the Logistics card. Optional: always.
var may_choose: Callable
## Lines for the timetable window when something changes.
signal changed


func _init() -> void:
	for carries in CARRIES:
		var trip := Trip.new()
		trip.carries = carries
		trips[carries] = trip


func set_location(def: LocationDef) -> void:
	location = def
	points.assign(def.arrivals)
	changed.emit()


func point_def(id: StringName) -> ArrivalPointDef:
	for def in points:
		if def.id == id:
			return def
	return null


## The first placed object marking a point, as Vector2i(level, id), or
## (-1, -1).
func placed(def: ArrivalPointDef) -> Vector2i:
	if building == null or def == null:
		return Vector2i(-1, -1)
	var found := building.objects_tagged([def.object_tag])
	return found[0] if not found.is_empty() else Vector2i(-1, -1)


func is_placed(def: ArrivalPointDef) -> bool:
	return placed(def).x >= 0 or (def != null and def.route == ArrivalPointDef.Route.ROAD and building != null \
			and not building.objects_tagged([def.object_tag]).is_empty())


## The point a trip uses: its own if placed, else the first placed one the
## location allows; null for none.
func point_for(carries: StringName) -> ArrivalPointDef:
	var trip: Trip = trips.get(carries)
	if trip != null and not trip.point.is_empty():
		var own := point_def(trip.point)
		if own != null and is_placed(own):
			return own
	for def in points:
		if is_placed(def):
			return def
	return null


## Picks the point a trip uses.
func choose(carries: StringName, point: StringName) -> void:
	if trips.has(carries):
		trips[carries].point = point
		changed.emit()


## Where a trip's vehicle stops: the point's middle; or `fallback`.
func stop_at(carries: StringName, fallback := Vector2.ZERO) -> Vector2:
	var key := placed(point_for(carries))
	return building.object_at(key).centre if key.x >= 0 else fallback


## Where people step off: a free spot beside the point, as [level, spot];
## or [] with no point.
func step_off(carries: StringName) -> Array:
	var key := placed(point_for(carries))
	if key.x < 0:
		return []
	var object := building.object_at(key)
	var spots := people.spots_beside(key.x, object, object.centre) if people != null else ([] as Array[Vector2])
	return [key.x, spots[0] if not spots.is_empty() else object.centre]


## Why a trip can't run today, or "": the weather has closed its point.
func closed_reason(carries: StringName) -> String:
	var def := point_for(carries)
	if def == null or not weather_id.is_valid():
		return ""
	var today: StringName = weather_id.call()
	if def.closed_by.has(today):
		return "The %s closed the %s, so the %s couldn't come." % [String(today).replace("_", " "),
				def.display_name.to_lower(), def.vehicle_name]
	return ""


## Whether today's trip is off. Says why, once, when it is.
func cancel_if_closed(carries: StringName) -> bool:
	var reason := closed_reason(carries)
	if reason.is_empty():
		return false
	cancelled.emit(carries, reason)
	return true


## Brings a trip's vehicle to its point, calling `arrived` with it there.
## `model` is the game's own (the bus), used for road points without
## their own vehicle; `to` is where it drives to by road, such as the bus
## stop or the lorry's pallets. Returns
## the vehicle, or null if none can come (no road and no other way).
func send(carries: StringName, model: PackedScene, to: Vector2, arrived := Callable(), stay := -1.0) -> Node3D:
	if vehicles == null:
		return null
	var def := point_for(carries)
	if def == null or def.route == ArrivalPointDef.Route.ROAD:
		var vehicle := def.vehicle if def != null and def.vehicle != null else model
		return vehicles.drive_in(vehicle, to, arrived, stay)
	var at := stop_at(carries, to)
	var route := PackedVector2Array([edge_point(at), at])
	var lift := FLY_HEIGHT if def.route == ArrivalPointDef.Route.AIR or def.route == ArrivalPointDef.Route.CABLE else 0.0
	return vehicles.arrive_along(def.vehicle if def.vehicle != null else model, route, arrived, stay, lift,
			def.route == ArrivalPointDef.Route.WATER)


## The nearest point on the map edge to a spot, where boats and aircraft
## come from.
func edge_point(at: Vector2) -> Vector2:
	var size := Vector2(map_size)
	var options := [Vector2(0.0, at.y), Vector2(size.x, at.y), Vector2(at.x, 0.0), Vector2(at.x, size.y)]
	options.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.distance_to(at) < b.distance_to(at))
	return options[0]


## A row for each trip, for the timetable: {carries, words, hour, point,
## choices, closed}.
func rows() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for carries in CARRIES:
		var def := point_for(carries)
		var hour: int = hour_of.call(carries) if hour_of.is_valid() else -1
		var choices: Array[StringName] = []
		if not may_choose.is_valid() or may_choose.call(carries):
			for point in points:
				if is_placed(point):
					choices.append(point.id)
		out.append({"carries": carries, "words": WORDS.get(carries, String(carries)), "hour": hour,
				"point": def.id if def != null else &"",
				"how": "by %s at the %s" % [def.vehicle_name, def.display_name.to_lower()] if def != null else "on foot from the road",
				"choices": choices, "closed": closed_reason(carries)})
	return out


func capture() -> Dictionary:
	var out := {"location": String(location.id) if location != null else "", "trips": {}}
	for carries in trips:
		out["trips"][String(carries)] = String(trips[carries].point)
	return out


func restore(data: Dictionary) -> void:
	var saved: Dictionary = data.get("trips", {})
	for carries: String in saved:
		if trips.has(StringName(carries)):
			trips[StringName(carries)].point = StringName(saved[carries])
	changed.emit()
