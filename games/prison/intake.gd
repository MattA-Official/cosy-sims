class_name Intake
extends Node
## New prisoners. Each morning a bus drives in by road and stops at the
## bus stop, or by the entrance, and the day's arrivals walk to reception, where they are searched and signed
## in. Then a guard walks each one to their cell, or with no guard free
## they find their own way. Nobody comes without a reception, or without a
## free bed. The prison is paid a fee for each.
##
## A warden sets how many come a day and which security categories are
## accepted. Without one a couple of low or medium security prisoners come
## each day.

signal arrived(people: Array[Person])

const BUS_HOUR := 9
const RECEPTION := &"reception"
## Arrivals a day without a warden to set the limit.
const WITHOUT_WARDEN := 2
const FEE := 200
const SEARCH_MINUTES := 10.0
## Game minutes an arrival waits for a guard before finding their own way.
const ESCORT_WAIT := 45.0
## Game minutes an arrival may take getting to reception before they are
## signed in wherever they are.
const WALK_LIMIT := 90.0
const FIRST_NIGHT := &"first_night"
const WITHOUT_WARDEN_CATEGORIES: Array[StringName] = [&"low", &"medium"]
## Game minutes the bus waits before driving off.
const BUS_STAY := 30.0
## Where the bus stops, if there is one.
const BUS_STOP := &"bus_stop"

enum Stage { WALKING, SEARCHING, WAITING }

var people: People
var building: Building
var ledger: Ledger
var guarding: Guarding
var categories: Array[CategoryDef] = []
var prisoner_group: StringName = &"prisoner"
## Where the bus stops, as [level, spot]: the staff entrance.
var entrance: Array = []
## Whether a warden is running the prison, for the intake settings.
var has_warden: Callable
## How many arrive a day, with a warden, and the most that may (the
## grade raises it).
var limit := 4
var max_limit := 8
## Category ids a warden accepts.
var accepted: Dictionary[StringName, bool] = {&"low": true, &"medium": true, &"high": false}
## For drawing the bus, optional: where to put it, the model, and the
## ground's height (Vector2 in tiles -> metres).
## Drives the bus in, when there's a road.
var vehicles: Vehicles
var bus_model: PackedScene
var clock: GameClock:
	set(value):
		clock = value
		clock.minute_passed.connect(func(_minute: int) -> void:
			_look()
			_bus_waits())
		clock.hour_changed.connect(func(hour: int) -> void:
			if hour == BUS_HOUR:
				bus())

## Arrivals still being signed in: [stage, minutes in it].
var _arriving: Dictionary[Person, Array] = {}
var _rng := RandomNumberGenerator.new()
var _bus: Node3D
var _bus_minutes := 0.0


## Arrivals still being signed in, by person id, for a save.
func arriving_ids() -> Dictionary:
	var out := {}
	for person: Person in _arriving:
		out[person.id] = _arriving[person].duplicate()
	return out


## Puts back arrivals from a save, by person id.
func restore_arriving(saved: Dictionary) -> void:
	for person in people.people:
		if saved.has(person.id):
			_arriving[person] = (saved[person.id] as Array).duplicate()


## Gives everyone already here a category: medium, unless they have one.
func start() -> void:
	for person in people.people:
		if person.group == prisoner_group and person.category == &"":
			person.category = &"medium"


## The bus comes: the day's arrivals get off and head to reception.
## Returns them.
## Sends the bus with today's arrivals. With a road in it drives up and
## they step off once it stops; without one they walk in from the
## entrance straight away, and come back at once. Returns those already
## here.
func bus() -> Array[Person]:
	var count := mini(todays_count(), free_beds())
	if count <= 0 or _reception().is_empty() or entrance.is_empty() or _bus != null:
		return []
	if vehicles != null:
		_bus = vehicles.drive_in(bus_model, stop_point(), func(_vehicle: Node3D) -> void:
			_bus_minutes = 0.0
			_step_off(count))
		if _bus != null:
			return []
	return _step_off(count)


## Is the bus on its way or waiting?
func bus_here() -> bool:
	return _bus != null


func _step_off(count: int) -> Array[Person]:
	var came: Array[Person] = []
	var room := _reception()
	var at := arrival_spot()
	if room.is_empty() or at.is_empty():
		return came
	var choices := _categories()
	count = mini(count, free_beds())
	for i in count:
		var spot: Vector2 = at[1] + Vector2(_rng.randf_range(-0.6, 0.6), _rng.randf_range(-0.6, 0.6))
		var person := people.add_person(at[0], spot, "", prisoner_group)
		if person == null:
			person = people.add_person(at[0], at[1], "", prisoner_group)
		if person == null:
			continue
		person.category = choices[_rng.randi() % choices.size()]
		person.led = true
		ledger.add(FEE, "Intake fees")
		people.add_moodlet(person, FIRST_NIGHT)
		_arriving[person] = [Stage.WALKING, 0.0]
		_head_in(person, room)
		came.append(person)
	if not came.is_empty():
		arrived.emit(came)
	return came


## How many come today, before free beds are counted.
func todays_count() -> int:
	return limit if warden_here() else WITHOUT_WARDEN


func warden_here() -> bool:
	return has_warden.is_valid() and has_warden.call()


## Beds in cells and dorms nobody has yet, counting arrivals.
func free_beds() -> int:
	var beds := 0
	for n: int in building.levels:
		var map := building.levels[n]
		for placed: BuildingMap.PlacedObject in map.objects.values():
			if not placed.def.tags.any(func(tag: StringName) -> bool: return people.owned_tags.has(tag)):
				continue
			var room := map.room_at_point(placed.centre)
			if room != null and people.home_room_types.has(room.type):
				beds += 1
	var prisoners := people.people.filter(func(p: Person) -> bool: return p.group == prisoner_group).size()
	return maxi(beds - prisoners, 0)


func is_arriving(person: Person) -> bool:
	return _arriving.has(person)


## Problems to show, such as having no reception.
func warnings() -> Array[String]:
	var out: Array[String] = []
	if _reception().is_empty():
		out.append("No reception: no new prisoners arrive")
	elif free_beds() == 0:
		out.append("No free beds: no new prisoners arrive")
	return out


## Category ids arrivals are picked from.
func _categories() -> Array[StringName]:
	var out: Array[StringName] = []
	if warden_here():
		for def in categories:
			if accepted.get(def.id, false):
				out.append(def.id)
	if out.is_empty():
		out = WITHOUT_WARDEN_CATEGORIES.duplicate()
	return out


## A reception room, as [level, room], or [].
func _reception() -> Array:
	for n: int in building.levels:
		for room: Room in building.levels[n].rooms():
			if room.type == RECEPTION:
				return [n, room]
	return []


## Moves each arrival on: searched once at reception, then walked to their
## cell.
func _look() -> void:
	for person: Person in _arriving.keys():
		if not people.people.has(person):
			_arriving.erase(person)
			continue
		var entry: Array = _arriving[person]
		entry[1] += 1.0
		match entry[0]:
			Stage.WALKING:
				var here := people.room_of(person)
				var arrived: bool = not here.is_empty() and (here[1] as Room).type == RECEPTION
				if (arrived and person.state == Person.State.IDLE) or entry[1] >= WALK_LIMIT:
					people.stop(person)
					_arriving[person] = [Stage.SEARCHING, 0.0]
				elif person.state == Person.State.IDLE:
					_head_in(person, _reception())
			Stage.SEARCHING:
				person.activity = "Being searched and signed in"
				if entry[1] >= SEARCH_MINUTES:
					_to_cell(person)
			Stage.WAITING:
				person.activity = "Waiting to be shown to their cell"
				if guarding.is_led(person):
					# The guard has them; they're no longer ours.
					_arriving.erase(person)
				elif entry[1] >= ESCORT_WAIT:
					guarding.cancel_escort(person)
					_let_go(person)


## Where the bus stops: by a bus stop if there is one, otherwise by the
## entrance.
func stop_point() -> Vector2:
	var stops := building.objects_tagged([BUS_STOP])
	if not stops.is_empty():
		return building.object_at(stops[0]).centre
	return entrance[1] if not entrance.is_empty() else Vector2.ZERO


## Where arrivals step off: beside the bus stop, or at the entrance.
func arrival_spot() -> Array:
	var stops := building.objects_tagged([BUS_STOP])
	if not stops.is_empty():
		var placed := building.object_at(stops[0])
		var spots := people.spots_beside(stops[0].x, placed, placed.centre)
		if not spots.is_empty():
			return [stops[0].x, spots[0]]
	return entrance


## The bus waits a while, then drives off.
func _bus_waits() -> void:
	if _bus == null or vehicles.is_driving(_bus):
		return
	_bus_minutes += 1.0
	if _bus_minutes < BUS_STAY:
		return
	vehicles.drive_out(_bus)
	_bus = null

## Sends an arrival to a tile in reception they can get to.
func _head_in(person: Person, room: Array) -> void:
	if room.is_empty():
		return
	for attempt in 6:
		var tile: Vector2i = room[1].cells[_rng.randi() % room[1].cells.size()]
		if people.walk_to(person, room[0], Vector2(tile) + Vector2(0.5, 0.5), "Arriving on the bus"):
			return


func _to_cell(person: Person) -> void:
	people.assign_beds()
	if guarding == null or not person.has_bed():
		_let_go(person)
		return
	var map := building.levels[person.bed.x]
	var bed: BuildingMap.PlacedObject = map.objects.get(person.bed.y)
	if bed == null:
		_let_go(person)
		return
	var room := map.room_at_point(bed.centre)
	var tile := Vector2i(bed.centre.floor())
	for cell: Vector2i in room.cells if room != null else []:
		if map.object_at(Vector2(cell) + Vector2(0.5, 0.5)) == null:
			tile = cell
			break
	_arriving[person] = [Stage.WAITING, 0.0]
	guarding.escort(person, [person.bed.x, tile], "to their cell", &"")


func _let_go(person: Person) -> void:
	_arriving.erase(person)
	person.led = false
	people.stop(person)
