class_name Calendar
extends Node
## The year: four short seasons of `length` days each, worked out from the
## day, so nothing needs remembering but the setting. Each season sets
## when the sun rises and sets and how the grass looks. Festive days
## (FestiveDayDef) fall on set days of a season. With seasons off it stays
## the first season. Shared by any game.

const LENGTH_LEAST := 3
const LENGTH_MOST := 30

signal season_changed(def: SeasonDef)
signal festive_day(def: FestiveDayDef)

var seasons: Array[SeasonDef] = []
var festive: Array[FestiveDayDef] = []
var enabled := true:
	set(value):
		enabled = value
		apply()
## Days in a season.
var length := 7:
	set(value):
		length = clampi(value, LENGTH_LEAST, LENGTH_MOST)
		apply()
## Optional: the light to set dawn and dusk on, and the ground material
## whose grass colour follows the season.
var day_night: DayNight
var ground: ShaderMaterial
var clock: GameClock:
	set(value):
		clock = value
		clock.day_changed.connect(func(_day: int) -> void:
			apply()
			if day_of_season() == 1:
				season_changed.emit(season())
			var today := festive_today()
			if today != null:
				festive_day.emit(today))


func season() -> SeasonDef:
	if seasons.is_empty():
		return null
	if not enabled:
		return seasons[0]
	return seasons[(_day() - 1) / length % seasons.size()]


func season_of(day: int) -> SeasonDef:
	if seasons.is_empty():
		return null
	return seasons[0] if not enabled else seasons[(day - 1) / length % seasons.size()]


## 1 on a season's first day.
func day_of_season() -> int:
	return (_day() - 1) % length + 1 if enabled else _day()


func festive_today() -> FestiveDayDef:
	if not enabled:
		return null
	var now := season()
	for def in festive:
		if now != null and def.season == now.id and def.day_of_season == day_of_season():
			return def
	return null


## The next festive day, as [days from now, def], or [].
func next_festive() -> Array:
	if not enabled:
		return []
	for ahead in range(0, length * seasons.size() + 1):
		var day := _day() + ahead
		var now := season_of(day)
		for def in festive:
			if now != null and def.season == now.id and def.day_of_season == (day - 1) % length + 1:
				return [ahead, def]
	return []


## "Autumn, day 3".
func words() -> String:
	var now := season()
	if now == null:
		return ""
	return "%s, day %d" % [now.display_name, day_of_season()] if enabled else now.display_name


## Sets the light and grass for the season.
func apply() -> void:
	var now := season()
	if now == null:
		return
	if day_night != null:
		day_night.dawn = now.dawn
		day_night.dusk = now.dusk
	if ground != null:
		ground.set_shader_parameter("base_colour", now.ground_tint)


func _day() -> int:
	return clock.day() if clock != null else 1
