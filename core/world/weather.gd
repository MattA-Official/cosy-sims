class_name Weather
extends Node
## Each day's weather (WeatherDef), rolled at FORECAST_HOUR for tomorrow
## from the season's table so it can be forecast, never two storms in a
## row. Rain, snow and storms close the outdoors: timetabled blocks with a
## wet_block move indoors, and anyone caught out gets the weather's
## moodlet. Snow slows walkers outdoors until the paths are gritted; heat
## makes those out of the shade swelter. Shared by any game.

const FORECAST_HOUR := 18
## Walking on snow that hasn't been gritted.
const SNOW_PACE := 0.7
## Game minutes gritting lasts before the snow covers it again.
const GRIT_MINUTES := 120.0
const HOT_MOODLET := &"sweltering"
const SHADE_TAG := &"shade"
const SHADE_REACH := 2.0

signal changed(def: WeatherDef)

var people: People
var calendar: Calendar
var defs: Array[WeatherDef] = []
var enabled := true:
	set(value):
		enabled = value
		_apply()
## Groups who feel the weather.
var groups: Array[StringName] = [&"prisoner", &"staff", &"visitor"]
var today: WeatherDef
var tomorrow: WeatherDef
## Game minutes (total) until the snow covers the gritted paths.
var gritted_until := -1.0
## Optional: the ground material to cover in snow, and the light to grey.
var ground: ShaderMaterial
var day_night: DayNight
var clock: GameClock:
	set(value):
		clock = value
		clock.hour_changed.connect(func(hour: int) -> void:
			if hour == FORECAST_HOUR:
				forecast()
			hourly())
		clock.day_changed.connect(func(_day: int) -> void: new_day())

var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()


func attach() -> void:
	people.walk_scales.append(func(person: Person) -> float:
		return SNOW_PACE if is_snowy() and person.outdoors and not gritted() else 1.0)
	if today == null:
		today = def_of(&"clear")
	_apply()


func def_of(id: StringName) -> WeatherDef:
	for def in defs:
		if def.id == id:
			return def
	return null


func current() -> WeatherDef:
	return today if enabled else null


func outdoors_ok() -> bool:
	return current() == null or current().outdoors_ok


func is_snowy() -> bool:
	return current() != null and current().snowy


func is_hot() -> bool:
	return current() != null and current().hot


func is_stormy() -> bool:
	return current() != null and current().stormy


func gritted() -> bool:
	return clock != null and clock.total_minutes < gritted_until


## Rolls tomorrow's weather from the season ahead's table.
func forecast() -> WeatherDef:
	var season := calendar.season_of(clock.day() + 1) if calendar != null and clock != null else null
	var table: Dictionary = season.weather if season != null else {&"clear": 1.0}
	var ids: Array = []
	var weights := PackedFloat32Array()
	for id: StringName in table:
		var def := def_of(id)
		if def == null or (def.stormy and today != null and today.stormy):
			continue
		ids.append(id)
		weights.append(table[id])
	tomorrow = def_of(ids[_rng.rand_weighted(weights)]) if not ids.is_empty() else def_of(&"clear")
	return tomorrow


func new_day() -> void:
	if tomorrow == null:
		forecast()
	set_today(tomorrow)
	tomorrow = null


func set_today(def: WeatherDef) -> void:
	today = def
	gritted_until = -1.0
	_apply()
	changed.emit(def)


## Each hour, those caught out in it feel it.
func hourly() -> void:
	var def := current()
	if def == null or people == null:
		return
	for person in people.people:
		if not groups.has(person.group) or not person.outdoors or person.away:
			continue
		if def.moodlet != &"":
			people.add_moodlet(person, def.moodlet)
		if def.hot and not _in_shade(person):
			people.add_moodlet(person, HOT_MOODLET)


## The paths are gritted for a while.
func grit() -> void:
	if clock != null:
		gritted_until = clock.total_minutes + GRIT_MINUTES


## "Rain today, snow tomorrow", for the clock bar.
func words() -> String:
	if not enabled or today == null:
		return ""
	return today.display_name


func forecast_words() -> String:
	if not enabled:
		return "Weather is off."
	var ahead := tomorrow.display_name.to_lower() if tomorrow != null else "not known until 18:00"
	return "Today: %s. Tomorrow: %s." % [today.display_name.to_lower() if today != null else "clear", ahead]


func _in_shade(person: Person) -> bool:
	for entry: Array in people._objects_tagged(SHADE_TAG):
		if entry[0] == person.level and (entry[1] as BuildingMap.PlacedObject).centre.distance_to(person.flat()) <= SHADE_REACH:
			return true
	return false


func _apply() -> void:
	if people != null:
		people.outdoors_closed = not outdoors_ok()
	var def := current()
	if ground != null:
		ground.set_shader_parameter("snow", 1.0 if def != null and def.snowy else 0.0)
	if day_night != null:
		day_night.overcast = def.overcast if def != null else 0.0


func capture() -> Dictionary:
	return {"today": String(today.id) if today != null else "", "tomorrow": String(tomorrow.id) if tomorrow != null else "",
			"gritted_until": gritted_until}


func restore(data: Dictionary) -> void:
	today = def_of(StringName(data.get("today", "clear")))
	if today == null:
		today = def_of(&"clear")
	tomorrow = def_of(StringName(data.get("tomorrow", "")))
	gritted_until = float(data.get("gritted_until", -1.0))
	_apply()
