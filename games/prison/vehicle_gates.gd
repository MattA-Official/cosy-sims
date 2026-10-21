class_name VehicleGates
extends Node
## Where the road comes through the perimeter. A guard sitting at a post
## within Guarding.GATE_RANGE of a vehicle gate checks every vehicle: now
## and then the lorry carries something it shouldn't (DELIVERY_CHANCE),
## and a check finds it. Unchecked, it gets through to a prisoner. And an
## unmanned gate opening for the bus or lorry lets anyone close by slip
## out behind it (SLIP_CHANCE).

## Something came in on the lorry unchecked, to this prisoner.
signal smuggled(person: Person, item: ItemDef)
## A check at the gate found something on the lorry.
signal found(item: ItemDef)

const KIND := &"vehicle_gate"
const DELIVERY_CHANCE := 0.1
const SLIP_CHANCE := 0.1
## Tiles from an unmanned gate a prisoner must be to slip out.
const SLIP_DISTANCE := 5.0

## Research bonuses: vehicle_search. Optional.
var modifiers: Modifiers
var building: Building
var people: People
var guarding: Guarding
var escapes: Escapes
## What a delivery might carry.
var contraband: Array[ItemDef] = []
var prisoner_group: StringName = &"prisoner"
## Prisoners on this programme unload near the lorry, so are the likeliest
## to end up with what it carried.
var near_programme: StringName = &"kitchen"
## Whom the vehicle gate lets through, for someone slipping out behind it.
var slip_group: StringName = &"staff"
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	escapes.caught.connect(func(person: Person, _by: Person) -> void: person.passes_as = &"")


## Every vehicle gate, as [level, its middle].
func gates() -> Array:
	var out: Array = []
	for n: int in building.levels:
		var map: BuildingMap = building.levels[n]
		for edge: Vector3i in map.door_kinds:
			if map.door_kind_at(edge) == KIND:
				var cells := BuildingMap.edge_cells(edge)
				out.append([n, (Vector2(cells[0]) + Vector2(cells[1])) * 0.5 + Vector2(0.5, 0.5)])
	return out


## Whether a guard at a post is near enough to check vehicles at a gate.
func manned(gate: Array) -> bool:
	return guarding.manned_desks().any(func(key: Vector2i) -> bool:
		var desk := building.object_at(key)
		return key.x == gate[0] and desk != null and desk.centre.distance_to(gate[1]) <= Guarding.GATE_RANGE)


## Whether every vehicle gate is watched (and there is at least one).
func checked() -> bool:
	var all := gates()
	return not all.is_empty() and all.all(manned)


## The lorry has come: perhaps with something extra, found or not.
## Returns what came, or null.
func delivery(force := false) -> ItemDef:
	if contraband.is_empty() or (not force and _rng.randf() >= DELIVERY_CHANCE):
		return null
	var item: ItemDef = contraband[_rng.randi() % contraband.size()]
	if checked() or _rng.randf() < Modifiers.amount(modifiers, &"vehicle_search"):
		found.emit(item)
		return item
	var prisoners := people.people.filter(func(p: Person) -> bool: return p.group == prisoner_group and not p.going_home)
	if prisoners.is_empty():
		return null
	var helpers := prisoners.filter(func(p: Person) -> bool: return p.programme == near_programme)
	var person: Person = (helpers if not helpers.is_empty() else prisoners).pick_random()
	person.pocket.append(item)
	smuggled.emit(person, item)
	return item


## A vehicle came through: at an unmanned gate, a prisoner close by may
## slip out behind it. Returns who did, or null.
func vehicle_came(chance := SLIP_CHANCE) -> Person:
	for gate: Array in gates():
		if manned(gate):
			continue
		for person in people.people:
			if person.group != prisoner_group or person.level != gate[0] or person.led or escapes.runners.has(person) \
					or person.flat().distance_to(gate[1]) > SLIP_DISTANCE:
				continue
			if _rng.randf() >= chance:
				continue
			# Through the gate before it shuts, as if they were the driver.
			person.passes_as = slip_group
			if escapes.run(person):
				return person
			person.passes_as = &""
	return null


## What's wrong at the gates, for the Security window.
func warnings() -> Array[String]:
	var out: Array[String] = []
	for gate: Array in gates():
		if not manned(gate):
			out.append("A vehicle gate is unmanned: deliveries go unchecked, and anyone near it can slip out. Man a guard post within %d tiles." % roundi(Guarding.GATE_RANGE))
			break
	return out
