class_name Movers
extends RefCounted
## Escalators and travelators: objects that carry people along their
## length. An escalator climbs a storey from its foot to its head on the
## level above, cutting the floor over itself like stairs; a travelator
## stays on one level. Each runs one way (ObjectDef.mover_way) at a pace
## faster than walking (ObjectDef.mover_speed). People step on at one end
## and off at the other, never across the side. The one lift is still the
## only lift: these sit beside it and the stairs.
##
## The length runs along the object's depth (ObjectDef.size.y): at no
## turn, from low z to high z.


class Mover:
	var level := 0
	var placed: BuildingMap.PlacedObject
	## The level the far end lets people off on.
	var head_level := 0
	## Where people step on and off at either end, in tile units, just
	## beyond the object.
	var foot := Vector2.ZERO
	var head := Vector2.ZERO
	## 1 carries people from foot to head, -1 head to foot, 0 either way.
	var way := 1
	var speed := 1.0

	func is_escalator() -> bool:
		return placed.def.connects == ObjectDef.Connects.ESCALATOR

	## Which way along its length it heads, in tile units.
	func ahead() -> Vector2:
		return Vector2(0.0, 1.0).rotated(placed.angle)


static func is_mover(def: ObjectDef) -> bool:
	return def.connects == ObjectDef.Connects.ESCALATOR or def.connects == ObjectDef.Connects.TRAVELATOR


## The mover a placed object makes on a level, or null if it isn't one.
static func of(level: int, placed: BuildingMap.PlacedObject) -> Mover:
	if not is_mover(placed.def):
		return null
	var mover := Mover.new()
	mover.level = level
	mover.placed = placed
	mover.way = placed.def.mover_way
	mover.speed = maxf(placed.def.mover_speed, 0.1)
	var ahead := mover.ahead()
	var half := placed.def.size.y * 0.5
	mover.foot = placed.centre - ahead * (half + 0.5)
	mover.head = placed.centre + ahead * (half + 0.5)
	mover.head_level = level + 1 if mover.is_escalator() else level
	return mover


## Every escalator and travelator on every level.
static func all(building: Building) -> Array[Mover]:
	var out: Array[Mover] = []
	for n: int in building.levels:
		for placed: BuildingMap.PlacedObject in building.levels[n].objects.values():
			var mover := of(n, placed)
			if mover != null:
				out.append(mover)
	return out


## The tiles an escalator on level `n` opens in the floor above it.
static func openings(map: BuildingMap) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for placed: BuildingMap.PlacedObject in map.objects.values():
		if placed.def.connects != ObjectDef.Connects.ESCALATOR:
			continue
		for cell in BuildingMap.cells_under(placed.rect.grow(-0.05)):
			if not out.has(cell):
				out.append(cell)
	return out
