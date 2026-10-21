class_name Shop
extends Node
## A shop residents spend their tokens in (Purse). Each item on the list
## (ItemDef.price_tokens) can be ticked on or off, at a fixed price. Every
## morning the shelves are filled back up, which the place pays for at
## cost (ItemDef.cost); tokens spent earn nothing back. It only sells while
## someone works the till. Shared by any game with a shop: the airport and
## museum would sell for money instead.

## The hour the shelves are filled, and the fewest of each kept.
const STOCK_HOUR := 7
const LEAST_STOCK := 4
## One of each item kept for every this many residents.
const RESIDENTS_PER_STOCK := 4
const LEDGER_LINE := "Shop stock"

signal sold(person: Person, item: ItemDef)

var people: People
var ledger: Ledger
var items: Array[ItemDef] = []
## Groups who shop.
var groups: Array[StringName] = [&"prisoner"]
## Item id -> whether it is for sale. Missing means on.
var on: Dictionary[StringName, bool] = {}
## Item id -> how many are on the shelves.
var stock: Dictionary[StringName, int] = {}
## Item id -> how many sold today, and yesterday.
var sold_today: Dictionary[StringName, int] = {}
var sold_yesterday: Dictionary[StringName, int] = {}
## Share of pay put aside for when they leave: 0, 0.2 or 0.5.
var save_share := 0.2
## Whether anyone works the till: () -> bool. Optional; open otherwise.
var is_open: Callable
## Whether there is a shop at all, such as once research allows it:
## () -> bool. Optional; always otherwise.
var allowed: Callable
var clock: GameClock:
	set(value):
		clock = value
		clock.hour_changed.connect(func(hour: int) -> void:
			if hour == STOCK_HOUR:
				restock())
		clock.day_changed.connect(func(_day: int) -> void:
			sold_yesterday = sold_today.duplicate()
			sold_today.clear())


func exists() -> bool:
	return not allowed.is_valid() or allowed.call()


func open() -> bool:
	return exists() and (not is_open.is_valid() or is_open.call())


func item(id: StringName) -> ItemDef:
	for def in items:
		if def.id == id:
			return def
	return null


func is_on(def: ItemDef) -> bool:
	return on.get(def.id, true)


## How many of each item the shelves hold when full.
func target() -> int:
	var residents := 0
	if people != null:
		for person in people.people:
			if groups.has(person.group):
				residents += 1
	return maxi(LEAST_STOCK, ceili(residents / float(RESIDENTS_PER_STOCK)))


## Fills the shelves of everything on sale, paying for it. Returns what it
## cost.
func restock() -> int:
	if not exists():
		return 0
	var spent := 0
	for def in items:
		if not is_on(def):
			continue
		var short := maxi(target() - stock.get(def.id, 0), 0)
		stock[def.id] = stock.get(def.id, 0) + short
		spent += short * def.cost
	if ledger != null:
		ledger.add(-spent, LEDGER_LINE)
	return spent


## Whether someone could buy this now.
func can_buy(person: Person, def: ItemDef) -> bool:
	return open() and is_on(def) and stock.get(def.id, 0) > 0 and Purse.tokens(person) >= def.price_tokens


## Sells someone an item. False if they can't buy it.
func buy(person: Person, def: ItemDef) -> bool:
	if not can_buy(person, def) or not Purse.spend(person, def.price_tokens):
		return false
	stock[def.id] -= 1
	sold_today[def.id] = sold_today.get(def.id, 0) + 1
	sold.emit(person, def)
	return true


## The cheapest thing on sale, in tokens, or 0 with nothing.
func cheapest() -> int:
	var best := 0
	for def in items:
		if is_on(def) and stock.get(def.id, 0) > 0 and (best == 0 or def.price_tokens < best):
			best = def.price_tokens
	return best


func capture() -> Dictionary:
	return {"save_share": save_share, "on": _strings(on), "stock": _strings(stock), "sold_today": _strings(sold_today),
			"sold_yesterday": _strings(sold_yesterday)}


func restore(data: Dictionary) -> void:
	save_share = data.get("save_share", 0.2)
	on.clear()
	for id: String in data.get("on", {}):
		on[StringName(id)] = bool(data["on"][id])
	for pair: Array in [[stock, "stock"], [sold_today, "sold_today"], [sold_yesterday, "sold_yesterday"]]:
		var into: Dictionary = pair[0]
		into.clear()
		var from: Dictionary = data.get(pair[1], {})
		for id: String in from:
			into[StringName(id)] = int(from[id])


static func _strings(store: Dictionary) -> Dictionary:
	var out := {}
	for id: StringName in store:
		out[String(id)] = store[id]
	return out
