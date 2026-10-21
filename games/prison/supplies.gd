class_name Supplies
extends Node
## Soap, toilet roll and cleaning stuff, kept as a number rather than
## items. Prisoners get through PER_PRISONER a day. The morning lorry
## tops the stock up: with storerooms, to what their shelves hold
## (SHELF_HOLDS each), at PRICE a unit; without one, only a day's worth,
## bought in small amounts at SMALL_ORDER times the price. Run out and
## showers come without soap.

const PER_PRISONER := 1.0
const PRICE := 2.0
const SMALL_ORDER := 1.5
const SHELF_HOLDS := 40.0
const ROOM := &"storeroom"
const SHELVES: Array[StringName] = [&"food_shelf", &"goods_shelf", &"clothes_shelf", &"wall_shelf"]
const SHOWER := &"shower"
const HYGIENE := &"hygiene"
## Without soap, a shower leaves hygiene no higher than this.
const SOAPLESS_HYGIENE := 60.0
const LINE := "Supplies"
const DELIVERY_HOUR := 6

var building: Building
var ledger: Ledger
var prisoner_group: StringName = &"prisoner"
## When set, the kitchen lorry operation restocks instead (main calls
## restock()).
var regime: Regime
## Units in stock.
var stock := 0.0
var people: People:
	set(value):
		people = value
		people.used.connect(_on_used)
var clock: GameClock:
	set(value):
		clock = value
		clock.hour_changed.connect(func(hour: int) -> void:
			stock = maxf(stock - _prisoners() * PER_PRISONER / 24.0, 0.0)
			if hour == DELIVERY_HOUR and regime == null:
				restock())


## What the storerooms' shelves hold.
func capacity() -> float:
	var shelves := 0
	for n: int in building.levels:
		var map: BuildingMap = building.levels[n]
		for key in building.objects_tagged(SHELVES):
			if key.x != n:
				continue
			var room := map.room_at_point(building.object_at(key).centre)
			if room != null and room.type == ROOM:
				shelves += 1
	return shelves * SHELF_HOLDS


## A day's worth.
func daily() -> float:
	return _prisoners() * PER_PRISONER


## The lorry tops up the stock. Returns what it cost.
func restock() -> int:
	var room := capacity()
	var target := room if room > 0.0 else daily()
	var order := maxf(target - stock, 0.0)
	if order <= 0.0:
		return 0
	var cost := roundi(order * PRICE * (1.0 if room > 0.0 else SMALL_ORDER))
	stock += order
	if ledger != null:
		ledger.add(-cost, LINE)
	return cost


## For the office: how the stock stands.
func words() -> String:
	var room := capacity()
	if room <= 0.0:
		return "Supplies: no storeroom, so soap and toilet roll come a day at a time, at %d%% more." % roundi((SMALL_ORDER - 1.0) * 100.0)
	return "Supplies: %d of %d in the storeroom, about %d days' worth." % [roundi(stock), roundi(room),
			floori(stock / maxf(daily(), 1.0))]


func capture() -> Dictionary:
	return {"stock": stock}


func restore(data: Dictionary) -> void:
	stock = data.get("stock", stock)


func _on_used(person: Person, placed: BuildingMap.PlacedObject) -> void:
	if placed == null or not placed.def.tags.has(SHOWER) or person.group != prisoner_group or stock > 0.0:
		return
	person.needs[HYGIENE] = minf(person.needs.get(HYGIENE, 100.0), SOAPLESS_HYGIENE)
	people.add_moodlet(person, &"no_soap")


func _prisoners() -> int:
	return people.people.filter(func(p: Person) -> bool: return p.group == prisoner_group and not p.going_home).size()
