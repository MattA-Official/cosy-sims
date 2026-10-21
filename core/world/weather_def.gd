class_name WeatherDef
extends Resource
## One kind of day's weather (see Weather).

@export var id: StringName
@export var display_name: String
## False closes the outdoors to the timetable (rain, snow, storms).
@export var outdoors_ok := true
## Given to anyone out in it, such as soaked.
@export var moodlet: StringName
## Ground covered in snow, slowing walkers until gritted.
@export var snowy := false
## Hot: those out of the shade swelter and tempers fray.
@export var hot := false
## Bad enough to send crowds home.
@export var stormy := false
## How grey the sky goes, 0 to 1.
@export var overcast := 0.0
## Falling rain or snow to draw: "", "rain" or "snow".
@export var falling: StringName
