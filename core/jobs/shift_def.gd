class_name ShiftDef
extends Resource
## A shift staff work, such as days or nights: when it starts, how long it
## runs, and how much more it pays.

@export var id: StringName
@export var display_name: String
## The hour of the day it starts.
@export_range(0, 23) var start_hour := 6
@export_range(1, 24) var hours := 12
## Pay for the shift against a day's wage, for when wages arrive (nights
## pay half as much again).
@export var pay_scale := 1.0
@export var icon: Texture2D


## Whether the shift is on at a minute of the day, counting from `early`
## minutes before it starts.
func is_on(minute_of_day: int, early := 0) -> bool:
	var since := posmod(minute_of_day - start_hour * GameClock.MINUTES_PER_HOUR + early, GameClock.MINUTES_PER_DAY)
	return since < hours * GameClock.MINUTES_PER_HOUR + early


## The hours it runs, such as "06:00 to 18:00".
func hours_text() -> String:
	return "%02d:00 to %02d:00" % [start_hour, (start_hour + hours) % 24]
