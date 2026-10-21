extends Surprise
## A heatwave or a snow day: tomorrow's weather is settled, whatever the
## forecast said. Three days of it when hard.

const SPELLS := {&"heatwave": &"heat", &"snow_day": &"snow"}


func start() -> void:
	if hard:
		minutes_left *= 3.0
	_force()


func tick(_minutes: float) -> void:
	_force()


func _force() -> void:
	var weather: Weather = main.weather
	var def := weather.def_of(SPELLS.get(self.def.id, &""))
	if def != null and weather.tomorrow != def:
		weather.tomorrow = def
