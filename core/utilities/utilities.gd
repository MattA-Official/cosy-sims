class_name Utilities
extends Node
## Power, water and sewage, as a setting (Mode). Off: everything just works
## and costs nothing. Bought in: the place pays the mains for what it uses,
## billed by the hour, and for heating by the day, more in winter.
## Self-sufficient (generators, wells and conduits) comes later under the
## same setting. Every SAMPLE_MINUTES, objects being used, objects that
## always draw something and indoor rooms lit after dark add to the hour's
## use. In a power cut nothing draws power. Shared by any game.

enum Mode { OFF, BOUGHT_IN, SELF_SUFFICIENT }

const KINDS: Array[StringName] = [&"power", &"water", &"sewage"]
const LINES := {&"power": "Power", &"water": "Water", &"sewage": "Sewage"}
const SAMPLE_MINUTES := 10.0
## Power an hour for each indoor floor tile once it's dark.
const LIGHT_POWER := 0.05
## Daylight below which rooms are lit.
const DARK_BELOW := 0.4
## Pounds a day for each indoor floor tile, times the season's heating
## scale.
const HEAT_PER_TILE := 0.25
const HEATING_LINE := "Heating"
## Self-sufficient: the share of an object's in-use rate counted when
## sharing out supply, as not everything is used at once.
const IN_USE_SHARE := 0.25
## Mains units bought to make up a shortfall cost this times the price;
## spare power sold back fetches SELL_SCALE of it.
const BUY_SCALE := 1.5
const SELL_SCALE := 0.5
const FUEL_LINE := "Fuel"
const SOLD_LINE := "Power sold"
## Minutes of too little sewage capacity before the drains back up.
const BACKED_UP_MINUTES := 30.0
const SMELL := &"smelly_drains"
## Room quality lost to backed-up drains.
const SMELL_QUALITY := -2.0
const DARK := &"lights_out"
const NAMES := {&"power": "power", &"water": "water", &"sewage": "drains"}
const RUNS := {&"power": "cable", &"water": "water pipe", &"sewage": "sewage pipe"}

## A state for the utilities view and the inspector.
enum Supply { NONE, ON, STORES, OFF }

signal power_changed(on: bool)
signal mode_changed


## One joined-up run of cables or pipes of one kind, with what's on it.
class Network:
	var kind: StringName
	## Vector3i(x, z, level) of each tile of the run.
	var cells: Dictionary[Vector3i, bool] = {}
	## [level, PlacedObject] of plant, stores and mains connections on it.
	var plant: Array = []
	var stores: Array = []
	var mains: Array = []
	## [level, PlacedObject or Room, steps from the nearest plant].
	var users: Array = []
	## Units an hour the plant makes now, and what's asked of it.
	var supply := 0.0
	var demand := 0.0
	var stored := 0.0
	var capacity := 0.0
	## Minutes it has been short.
	var short_minutes := 0.0

	func has_mains() -> bool:
		return not mains.is_empty()


var mode := Mode.OFF:
	set(value):
		var was := mode
		mode = value
		_dirty = true
		if mode != Mode.SELF_SUFFICIENT:
			_release()
		if was != mode:
			mode_changed.emit()
## Optional: plant wears with the hours it runs.
var wear: Wear
## Units held in each store, by (level, object id).
var store_levels: Dictionary[Vector2i, float] = {}
## Self-sufficient networks, rebuilt when the building changes.
var networks: Array[Network] = []
## Objects switched off, by (level, object id): [kind, words].
var off: Dictionary[Vector2i, Array] = {}
## Objects running on stores, by (level, object id).
var on_stores: Dictionary[Vector2i, bool] = {}
## Indoor rooms with no light after dark.
var dark_rooms: Dictionary[Room, bool] = {}
## Rooms with backed-up drains, which count against their quality.
var smelly_rooms: Dictionary[Room, bool] = {}
## Pence a unit when bought in; location packs may change them.
var prices: Dictionary[StringName, int] = {&"power": 15, &"water": 10, &"sewage": 8}
var building: Building:
	set(value):
		building = value
		building.changed.connect(func() -> void: _dirty = true)
var people: People:
	set(value):
		people = value
		people.use_filters.append(func(_person: Person, placed: BuildingMap.PlacedObject) -> bool:
			return not _off_objects.has(placed))
		people.quality_extras.append(func(_level: int, room: Room) -> Array:
			return [["Backed-up drains", SMELL_QUALITY]] if smelly_rooms.has(room) else [])
var ledger: Ledger
var day_night: DayNight
var calendar: Calendar
## A power cut: nothing electric works.
var cut := false:
	set(value):
		if cut != value:
			cut = value
			power_changed.emit(not cut)
## Units used so far this hour, and over the last whole day.
var hour_use: Dictionary[StringName, float] = {}
var day_use: Dictionary[StringName, float] = {}
var yesterday: Dictionary[StringName, float] = {}
var heating_yesterday := 0
var clock: GameClock:
	set(value):
		clock = value
		clock.minute_passed.connect(func(_minute: int) -> void:
			_wait -= 1.0
			if _wait <= 0.0:
				_wait = SAMPLE_MINUTES
				sample(SAMPLE_MINUTES))
		clock.hour_changed.connect(func(_hour: int) -> void:
			bill_hour()
			hourly())
		clock.day_changed.connect(func(_day: int) -> void: bill_day())

var _wait := 0.0
## Pence owed but not yet a whole pound, by kind.
var _pence: Dictionary[StringName, float] = {}
## Self-sufficient money this hour, by ledger line: pence, costs below 0.
var _hour_money: Dictionary[String, float] = {}
var _dirty := true
var _off_objects: Dictionary[BuildingMap.PlacedObject, bool] = {}
## Plant that ran this hour, by (level, object id).
var _ran: Dictionary[Vector2i, bool] = {}
## Electric doors this locked, as Vector4i(edge x, z, axis, level).
var _locked: Dictionary[Vector4i, bool] = {}


func on() -> bool:
	return mode != Mode.OFF


func bought_in() -> bool:
	return mode == Mode.BOUGHT_IN


func is_dark() -> bool:
	return day_night != null and clock != null and day_night.daylight(clock.hour_float()) < DARK_BELOW


## Adds what's been used over some minutes to the hour's use.
func sample(minutes: float) -> void:
	if not on() or building == null:
		return
	if mode == Mode.SELF_SUFFICIENT:
		balance(minutes)
		return
	var hours := minutes / 60.0
	for n: int in building.levels:
		var map: BuildingMap = building.levels[n]
		for placed: BuildingMap.PlacedObject in map.objects.values():
			if not placed.def.idle_uses.is_empty():
				_add(placed.def.idle_uses, hours)
			if not placed.def.uses.is_empty() and people != null and people.user_of(n, placed.id) != null:
				_add(placed.def.uses, hours)
		if is_dark():
			_add({&"power": LIGHT_POWER * indoor_tiles_on(map)}, hours)


func _add(amounts: Dictionary, hours: float) -> void:
	for kind: StringName in amounts:
		if kind == &"power" and cut:
			continue
		hour_use[kind] = hour_use.get(kind, 0.0) + float(amounts[kind]) * hours


## The hour's bill, a line for each kind, bought in.
func bill_hour() -> void:
	for line: String in _hour_money:
		var pence: float = _pence.get(StringName(line), 0.0) + _hour_money[line]
		var pounds := floori(pence / 100.0) if pence >= 0.0 else -floori(-pence / 100.0)
		_pence[StringName(line)] = pence - pounds * 100.0
		if ledger != null and pounds != 0:
			ledger.add(pounds, line)
	_hour_money.clear()
	for kind: StringName in hour_use:
		day_use[kind] = day_use.get(kind, 0.0) + hour_use[kind]
		if bought_in() and ledger != null:
			var pence: float = _pence.get(kind, 0.0) + hour_use[kind] * prices.get(kind, 0)
			var pounds := floori(pence / 100.0)
			_pence[kind] = pence - pounds * 100.0
			ledger.add(-pounds, LINES.get(kind, String(kind).capitalize()))
	hour_use.clear()


## The day's heating, bought in.
func bill_day() -> void:
	yesterday = day_use.duplicate()
	day_use.clear()
	heating_yesterday = heating_bill() if on() else 0
	if heating_yesterday > 0 and ledger != null:
		ledger.add(-heating_yesterday, HEATING_LINE)


## What a day's heating costs now.
func heating_bill() -> int:
	var scale := 1.0
	if calendar != null and calendar.enabled and calendar.season() != null:
		scale = calendar.season().heating_scale
	var tiles := 0
	if building != null:
		for map: BuildingMap in building.levels.values():
			tiles += indoor_tiles_on(map)
	return roundi(tiles * HEAT_PER_TILE * scale)


func indoor_tiles_on(map: BuildingMap) -> int:
	var tiles := 0
	for room in map.rooms():
		if room.indoor:
			tiles += room.cells.size()
	return tiles


## "Power 140, water 80, sewage 40 units yesterday; heating £50" for the
## money window, or "".
func words() -> String:
	if not on():
		return ""
	var parts: Array[String] = []
	for kind in KINDS:
		parts.append("%s %d" % [LINES[kind].to_lower(), roundi(yesterday.get(kind, 0.0))])
	var out := "Used yesterday: %s units" % ", ".join(parts)
	if heating_yesterday > 0:
		out += "; heating £%d" % heating_yesterday
	return out


func capture() -> Dictionary:
	return {"mode": mode, "pence": _pence.duplicate(), "yesterday": yesterday.duplicate(), "heating": heating_yesterday,
			"stores": store_levels.duplicate()}


func restore(data: Dictionary) -> void:
	mode = int(data.get("mode", Mode.OFF)) as Mode
	_pence.assign(data.get("pence", {}))
	store_levels.assign(data.get("stores", {}))
	yesterday.assign(data.get("yesterday", {}))
	heating_yesterday = int(data.get("heating", 0))


#region Self-sufficient

## Shares out every network's supply over some minutes: who's on, who's
## off, what's stored, bought, sold and burnt.
func balance(minutes: float) -> void:
	if _dirty:
		_build_networks()
	var hours := minutes / 60.0
	off.clear()
	on_stores.clear()
	_off_objects.clear()
	dark_rooms.clear()
	var lit: Dictionary[Room, bool] = {}
	var smelt := smelly_rooms.duplicate()
	smelly_rooms.clear()
	for net in networks:
		_balance(net, hours, lit)
	if smelt != smelly_rooms and people != null:
		people.quality_changed()
	# What no run reaches is off; indoor rooms no cable reaches are dark.
	for n: int in building.levels:
		var map: BuildingMap = building.levels[n]
		for placed: BuildingMap.PlacedObject in map.objects.values():
			var key := Vector2i(n, placed.id)
			for kind in KINDS:
				if off.has(key) or not _needs(placed.def, kind) or _attached.get(kind, {}).has(key):
					continue
				off[key] = [kind, "No %s: no %s reaches it" % [NAMES[kind], RUNS[kind]]]
		if is_dark():
			for room in map.rooms():
				if room.indoor and not lit.has(room):
					dark_rooms[room] = true
	for key: Vector2i in off:
		var placed := building.object_at(key)
		if placed != null:
			_off_objects[placed] = true
	_doors()


func _balance(net: Network, hours: float, lit: Dictionary[Room, bool]) -> void:
	var kind := net.kind
	var cut_off := cut and kind == &"power"
	net.supply = 0.0
	for entry: Array in net.plant:
		var placed: BuildingMap.PlacedObject = entry[1]
		if cut_off or (people != null and people.broken.has(Vector2i(entry[0], placed.id))):
			continue
		net.supply += _makes(placed.def, kind)
	net.capacity = 0.0
	net.stored = 0.0
	for entry: Array in net.stores:
		var placed: BuildingMap.PlacedObject = entry[1]
		var key := Vector2i(entry[0], placed.id)
		net.capacity += placed.def.stores[kind]
		store_levels[key] = minf(store_levels.get(key, 0.0), placed.def.stores[kind])
		net.stored += store_levels[key]
	var mains := net.has_mains() and not cut_off
	# Share out by distance from the plant, nearest first.
	var available := net.supply + (net.stored / hours if hours > 0.0 else 0.0)
	var given := 0.0
	var used := 0.0
	var short := false
	net.demand = 0.0
	for entry: Array in net.users:
		var rated := _rated(entry[1], kind)
		net.demand += rated
	for entry: Array in net.users:
		var level: int = entry[0]
		var rated := _rated(entry[1], kind)
		var on_it := mains or given + rated <= available + 0.001
		if entry[1] is Room:
			if on_it:
				lit[entry[1]] = true
				given += rated
				used += rated
			else:
				short = true
			continue
		var placed: BuildingMap.PlacedObject = entry[1]
		var key := Vector2i(level, placed.id)
		if not on_it:
			short = true
			off[key] = [kind, _short_words(net)]
			continue
		given += rated
		if given > net.supply + 0.001 and not mains:
			on_stores[key] = true
		used += _uses_now(level, placed, kind)
	# Units this while: from the plant, then stores, then the mains.
	var made := net.supply * hours
	var need := used * hours
	var produced := minf(made, need)
	var spare := made - produced
	var want := need - produced
	if want > 0.0:
		var drawn := minf(want, net.stored)
		_draw_stores(net, -drawn)
		want -= drawn
		if want > 0.0 and mains:
			_money(LINES[kind], -want * prices.get(kind, 0) * BUY_SCALE)
	elif spare > 0.0:
		# Spare fills the stores, then power goes to the mains; plant with
		# nowhere for it to go idles.
		var charged := minf(spare, net.capacity - net.stored)
		_draw_stores(net, charged)
		produced += charged
		spare -= charged
		if spare > 0.0 and mains and kind == &"power":
			_money(SOLD_LINE, spare * prices.get(kind, 0) * SELL_SCALE)
			produced += spare
	_burn(net, produced)
	hour_use[kind] = hour_use.get(kind, 0.0) + need
	net.short_minutes = net.short_minutes + hours * 60.0 if short else 0.0
	if kind == &"sewage" and net.short_minutes >= BACKED_UP_MINUTES:
		_smell(net)


## Units an hour some plant makes now.
func _makes(def: ObjectDef, kind: StringName) -> float:
	var amount: float = def.supplies.get(kind, 0.0)
	if def.solar:
		amount *= clampf(day_night.daylight(clock.hour_float()), 0.0, 1.0) if day_night != null and clock != null else 1.0
	return amount


## What a user is counted as asking for when sharing out.
func _rated(user: Variant, kind: StringName) -> float:
	if user is Room:
		return LIGHT_POWER * (user as Room).cells.size() if is_dark() else 0.0
	var def: ObjectDef = (user as BuildingMap.PlacedObject).def
	return float(def.uses.get(kind, 0.0)) * IN_USE_SHARE + float(def.idle_uses.get(kind, 0.0))


## Units an hour an object is drawing right now.
func _uses_now(level: int, placed: BuildingMap.PlacedObject, kind: StringName) -> float:
	var amount: float = placed.def.idle_uses.get(kind, 0.0)
	if people != null and people.user_of(level, placed.id) != null:
		amount += float(placed.def.uses.get(kind, 0.0))
	return amount


## Shares what was made among the plant that made it: fuel and wear.
func _burn(net: Network, units: float) -> void:
	if units <= 0.0 or net.supply <= 0.0:
		return
	for entry: Array in net.plant:
		var placed: BuildingMap.PlacedObject = entry[1]
		var made := _makes(placed.def, net.kind)
		if made <= 0.0 or (people != null and people.broken.has(Vector2i(entry[0], placed.id))):
			continue
		_ran[Vector2i(entry[0], placed.id)] = true
		if placed.def.unit_cost > 0.0:
			_money(FUEL_LINE, -units * made / net.supply * placed.def.unit_cost)


## Fills (amount over 0) or empties a network's stores, shared by size.
func _draw_stores(net: Network, amount: float) -> void:
	if net.capacity <= 0.0 or amount == 0.0:
		return
	for entry: Array in net.stores:
		var placed: BuildingMap.PlacedObject = entry[1]
		var key := Vector2i(entry[0], placed.id)
		var size: float = placed.def.stores[net.kind]
		store_levels[key] = clampf(store_levels.get(key, 0.0) + amount * size / net.capacity, 0.0, size)
	net.stored = clampf(net.stored + amount, 0.0, net.capacity)


func _money(line: String, pence: float) -> void:
	_hour_money[line] = _hour_money.get(line, 0.0) + pence


func _short_words(net: Network) -> String:
	var source := "nothing"
	if net.plant.size() == 1:
		source = "the %s" % (net.plant[0][1] as BuildingMap.PlacedObject).def.display_name.to_lower()
	elif net.plant.size() > 1:
		source = "%d plant" % net.plant.size()
	return "No %s: %s supplies %d, demand is %d" % [NAMES[net.kind], source, roundi(net.supply), roundi(net.demand)]


## Backed-up drains: everyone in a room with something on this run that's
## off smells it.
func _smell(net: Network) -> void:
	if people == null:
		return
	var rooms: Dictionary[Room, bool] = {}
	for entry: Array in net.users:
		if entry[1] is BuildingMap.PlacedObject and off.has(Vector2i(entry[0], (entry[1] as BuildingMap.PlacedObject).id)):
			var map: BuildingMap = building.levels[entry[0]]
			var room := map.room_at_point((entry[1] as BuildingMap.PlacedObject).centre)
			if room != null:
				rooms[room] = true
	smelly_rooms.merge(rooms)
	for person in people.people:
		var here := people.room_of(person)
		if not here.is_empty() and rooms.has(here[1]):
			people.add_moodlet(person, SMELL)


## Each hour: plant that ran wears, and anyone awake in a dark room feels
## it.
func hourly() -> void:
	if mode != Mode.SELF_SUFFICIENT:
		return
	if wear != null:
		for key: Vector2i in _ran:
			wear.use(key)
	_ran.clear()
	if people == null or dark_rooms.is_empty():
		return
	for person in people.people:
		if person.group != &"prisoner" or person.outdoors or people.is_asleep(person):
			continue
		var here := people.room_of(person)
		if not here.is_empty() and dark_rooms.has(here[1]):
			people.add_moodlet(person, DARK)


## Electric doors with no power beside them fail locked; power back, they
## open again.
func _doors() -> void:
	if people == null:
		return
	var wanted: Dictionary[Vector4i, bool] = {}
	for n: int in building.levels:
		var map: BuildingMap = building.levels[n]
		for edge: Vector3i in map.door_kinds:
			var kind: DoorKindDef = people.access.door_kinds.get(map.door_kinds[edge])
			if kind == null or not kind.electric:
				continue
			var cells := [Vector2i(edge.x, edge.y), Vector2i(edge.x, edge.y - 1) if edge.z == BuildingMap.EDGE_X
					else Vector2i(edge.x - 1, edge.y)]
			var powered := false
			for cell: Vector2i in cells:
				var net: Network = _cell_nets.get(&"power", {}).get(Vector3i(cell.x, cell.y, n))
				if net != null and (net.supply > 0.0 or net.stored > 0.0 or (net.has_mains() and not cut)):
					powered = true
			if not powered:
				wanted[Vector4i(edge.x, edge.y, edge.z, n)] = true
	for key: Vector4i in _locked.keys():
		if not wanted.has(key):
			people.set_door_locked(key.w, Vector3i(key.x, key.y, key.z), false)
			_locked.erase(key)
	for key: Vector4i in wanted:
		var edge := Vector3i(key.x, key.y, key.z)
		if not _locked.has(key) and not people.is_door_locked(key.w, edge):
			people.set_door_locked(key.w, edge, true)
			_locked[key] = true


## Leaving Self-sufficient: everything back on.
func _release() -> void:
	if not smelly_rooms.is_empty() and people != null:
		smelly_rooms.clear()
		people.quality_changed()
	off.clear()
	on_stores.clear()
	_off_objects.clear()
	dark_rooms.clear()
	if people != null:
		for key: Vector4i in _locked:
			people.set_door_locked(key.w, Vector3i(key.x, key.y, key.z), false)
	_locked.clear()


func _needs(def: ObjectDef, kind: StringName) -> bool:
	return def.uses.has(kind) or def.idle_uses.has(kind)


## Network by tile, by kind.
var _cell_nets: Dictionary[StringName, Dictionary] = {}
## (level, object id) of everything joined to a run, by kind.
var _attached: Dictionary[StringName, Dictionary] = {}


## Finds every joined-up run of each kind, and what's on each.
func _build_networks() -> void:
	_dirty = false
	networks.clear()
	_cell_nets.clear()
	_attached.clear()
	if building == null:
		return
	for kind in KINDS:
		var by_cell: Dictionary[Vector3i, Network] = {}
		_cell_nets[kind] = by_cell
		_attached[kind] = {}
		for n: int in building.levels:
			var map: BuildingMap = building.levels[n]
			for cell: Vector2i in map.conduits:
				var start := Vector3i(cell.x, cell.y, n)
				if map.has_conduit(cell, kind) and not by_cell.has(start):
					var net := Network.new()
					net.kind = kind
					_flood(net, start, by_cell)
					networks.append(net)
		_join_objects(kind, by_cell)
	for net in networks:
		_order_users(net)


func _flood(net: Network, start: Vector3i, by_cell: Dictionary[Vector3i, Network]) -> void:
	var bit: int = BuildingMap.CONDUIT_BITS[net.kind]
	var queue: Array[Vector3i] = [start]
	by_cell[start] = net
	while not queue.is_empty():
		var at: Vector3i = queue.pop_back()
		net.cells[at] = true
		for step: Vector3i in [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 1, 0), Vector3i(0, -1, 0),
				Vector3i(0, 0, 1), Vector3i(0, 0, -1)]:
			var next := at + step
			var map := building.levels.get(next.z) as BuildingMap
			if map == null or by_cell.has(next) or (map.conduits.get(Vector2i(next.x, next.y), 0) & bit) == 0:
				continue
			by_cell[next] = net
			queue.append(next)


## Joins each object to the run under or beside it, and each indoor room
## to a cable inside it.
func _join_objects(kind: StringName, by_cell: Dictionary[Vector3i, Network]) -> void:
	if by_cell.is_empty():
		return
	for n: int in building.levels:
		var map: BuildingMap = building.levels[n]
		for placed: BuildingMap.PlacedObject in map.objects.values():
			var def := placed.def
			var is_plant := def.supplies.has(kind)
			var is_store := def.stores.has(kind)
			var is_mains := def.mains
			if not (is_plant or is_store or is_mains or _needs(def, kind)):
				continue
			var net := _net_beside(GridGeometry.cells_under(placed.rect), n, by_cell)
			if net == null:
				continue
			_attached[kind][Vector2i(n, placed.id)] = true
			if is_plant:
				net.plant.append([n, placed])
			if is_store:
				net.stores.append([n, placed])
			if is_mains:
				net.mains.append([n, placed])
			if _needs(def, kind):
				net.users.append([n, placed, 0])
		if kind == &"power":
			for room in map.rooms():
				if not room.indoor:
					continue
				for cell in room.cells:
					var net: Network = by_cell.get(Vector3i(cell.x, cell.y, n))
					if net != null:
						net.users.append([n, room, 0])
						break


func _net_beside(cells: Array[Vector2i], level: int, by_cell: Dictionary[Vector3i, Network]) -> Network:
	for cell in cells:
		var net: Network = by_cell.get(Vector3i(cell.x, cell.y, level))
		if net != null:
			return net
	for cell in cells:
		for step: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var net: Network = by_cell.get(Vector3i(cell.x + step.x, cell.y + step.y, level))
			if net != null:
				return net
	return null


## Steps along the run from the nearest plant, store or mains to each user,
## nearest first.
func _order_users(net: Network) -> void:
	var steps: Dictionary[Vector3i, int] = {}
	var queue: Array[Vector3i] = []
	for entry: Array in net.plant + net.stores + net.mains:
		for cell in _touching(net, entry[0], entry[1]):
			if not steps.has(cell):
				steps[cell] = 0
				queue.append(cell)
	var head := 0
	while head < queue.size():
		var at := queue[head]
		head += 1
		for step: Vector3i in [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 1, 0), Vector3i(0, -1, 0),
				Vector3i(0, 0, 1), Vector3i(0, 0, -1)]:
			var next := at + step
			if net.cells.has(next) and not steps.has(next):
				steps[next] = steps[at] + 1
				queue.append(next)
	for entry: Array in net.users:
		var best := 1 << 30
		for cell in _touching(net, entry[0], entry[1]):
			best = mini(best, steps.get(cell, 1 << 30))
		entry[2] = best
	net.users.sort_custom(func(a: Array, b: Array) -> bool: return a[2] < b[2])


## The run's tiles under or beside an object, or in a room.
func _touching(net: Network, level: int, thing: Variant) -> Array[Vector3i]:
	var out: Array[Vector3i] = []
	var cells: Array[Vector2i] = []
	if thing is Room:
		cells.assign((thing as Room).cells)
	else:
		cells = GridGeometry.cells_under((thing as BuildingMap.PlacedObject).rect)
		for cell: Vector2i in cells.duplicate():
			for step: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
				cells.append(cell + step)
	for cell in cells:
		var key := Vector3i(cell.x, cell.y, level)
		if net.cells.has(key):
			out.append(key)
	return out


## How an object stands, for the utilities view: Supply.NONE if it
## neither uses nor makes anything.
func supply_of(level: int, placed: BuildingMap.PlacedObject) -> Supply:
	var key := Vector2i(level, placed.id)
	if off.has(key):
		return Supply.OFF
	if on_stores.has(key):
		return Supply.STORES
	var def := placed.def
	if def.supplies.is_empty() and def.stores.is_empty() and not def.mains and def.uses.is_empty() and def.idle_uses.is_empty():
		return Supply.NONE
	if (people != null and people.broken.has(key)) or (not def.supplies.is_empty() and not _attached_any(key)):
		return Supply.OFF
	return Supply.ON


func _attached_any(key: Vector2i) -> bool:
	for kind: StringName in _attached:
		if _attached[kind].has(key):
			return true
	return false


## For the inspector: why something's off or what it runs on, or "".
func object_words(level: int, placed: BuildingMap.PlacedObject) -> String:
	if mode != Mode.SELF_SUFFICIENT:
		return ""
	var key := Vector2i(level, placed.id)
	if off.has(key):
		return off[key][1]
	var parts: Array[String] = []
	for net in networks:
		var on_net := net.plant.any(func(e: Array) -> bool: return e[1] == placed) \
				or net.stores.any(func(e: Array) -> bool: return e[1] == placed)
		if not on_net:
			continue
		if placed.def.supplies.has(net.kind):
			parts.append("Makes %d %s an hour; the run needs %d" % [roundi(_makes(placed.def, net.kind)),
					"units of " + NAMES[net.kind] if net.kind != &"sewage" else "units of sewage treated", roundi(net.demand)])
		if placed.def.stores.has(net.kind):
			parts.append("Holds %d of %d" % [roundi(store_levels.get(key, 0.0)), roundi(placed.def.stores[net.kind])])
	if on_stores.has(key):
		parts.append("Running on stores")
	if not placed.def.supplies.is_empty() and not _attached_any(key):
		var runs := PackedStringArray()
		for kind: StringName in placed.def.supplies:
			runs.append(RUNS[kind])
		parts.append("Not joined to any %s" % " or ".join(runs))
	return ". ".join(parts)


## "Power: 40 made, 32 needed" for each kind, for the utilities tool.
func summary() -> String:
	if mode != Mode.SELF_SUFFICIENT:
		return ""
	if _dirty:
		_build_networks()
	var parts: Array[String] = []
	for kind in KINDS:
		var made := 0.0
		var asked := 0.0
		var stored := 0.0
		for net in networks:
			if net.kind == kind:
				made += net.supply
				asked += net.demand
				stored += net.stored
		var words := "%s %d made, %d needed" % [LINES[kind], roundi(made), roundi(asked)]
		if stored > 0.0:
			words += ", %d stored" % roundi(stored)
		var dead := off.values().filter(func(why: Array) -> bool: return why[0] == kind).size()
		if dead > 0:
			words += ", %d thing%s off" % [dead, "" if dead == 1 else "s"]
		parts.append(words)
	return "; ".join(parts)

#endregion
