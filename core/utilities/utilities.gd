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

signal power_changed(on: bool)

var mode := Mode.OFF
## Pence a unit when bought in; location packs may change them.
var prices: Dictionary[StringName, int] = {&"power": 15, &"water": 10, &"sewage": 8}
var building: Building
var people: People
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
		clock.hour_changed.connect(func(_hour: int) -> void: bill_hour())
		clock.day_changed.connect(func(_day: int) -> void: bill_day())

var _wait := 0.0
## Pence owed but not yet a whole pound, by kind.
var _pence: Dictionary[StringName, float] = {}


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
	heating_yesterday = heating_bill() if bought_in() else 0
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
	return {"mode": mode, "pence": _pence.duplicate(), "yesterday": yesterday.duplicate(), "heating": heating_yesterday}


func restore(data: Dictionary) -> void:
	mode = int(data.get("mode", Mode.OFF)) as Mode
	_pence.assign(data.get("pence", {}))
	yesterday.assign(data.get("yesterday", {}))
	heating_yesterday = int(data.get("heating", 0))
