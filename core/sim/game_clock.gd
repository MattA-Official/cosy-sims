class_name GameClock
extends Node
## The one clock everything else listens to. At normal speed a game minute
## lasts one real second, so an hour is a real minute and a day is 24
## minutes. Days are numbered from Day 1 with a weekday name; there are no
## months or seasons.
##
##   clock.hour_changed.connect(func(hour: int) -> void: ...)
##   clock.advanced.connect(people.step) # minutes since the last frame

## Every whole minute, as minutes since midnight (0 to 1439).
signal minute_passed(minute: int)
signal hour_changed(hour: int)
## Every half hour (on the hour too), as the half hour of the week from
## Monday midnight: see Schedule.slot_of.
signal half_hour_changed(slot: int)
signal day_changed(day: int)
## Game minutes moved on this frame. Nothing is sent while paused.
signal advanced(minutes: float)
signal speed_changed(index: int)

const MINUTES_PER_HOUR := 60
const MINUTES_PER_DAY := 24 * 60
## Paused, 1×, 2× and 4×.
const SPEEDS: Array[float] = [0.0, 1.0, 2.0, 4.0]
const WEEKDAYS: Array[String] = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday",
		"Saturday", "Sunday"]

## Real seconds a game minute lasts at 1×.
@export var seconds_per_minute := 1.0
## Where the clock starts on Day 1, in hours.
@export var start_hour := 7.0

## Game minutes since midnight at the start of Day 1.
var total_minutes := 0.0
## An index into SPEEDS. 0 is paused.
var speed_index := 1:
	set(value):
		value = clampi(value, 0, SPEEDS.size() - 1)
		if value == speed_index:
			return
		if value > 0:
			_last_running = value
		speed_index = value
		speed_changed.emit(value)

var _last_running := 1


func _ready() -> void:
	total_minutes = start_hour * MINUTES_PER_HOUR


func _process(delta: float) -> void:
	advance(delta * SPEEDS[speed_index] / maxf(seconds_per_minute, 0.001))


## Moves the clock on by some game minutes, sending a signal for every
## minute, hour and day crossed on the way.
func advance(minutes: float) -> void:
	if minutes <= 0.0:
		return
	var before := floori(total_minutes)
	total_minutes += minutes
	_cross(before, floori(total_minutes))
	advanced.emit(minutes)


## Jumps straight to a time of day, today or tomorrow if it has passed,
## without anything happening in between. Signals the new hour.
func jump_to_hour(hour: int) -> void:
	var target := (day() - 1) * MINUTES_PER_DAY + hour * MINUTES_PER_HOUR
	if target <= total_minutes:
		target += MINUTES_PER_DAY
	var old_day := day()
	total_minutes = target
	if day() != old_day:
		day_changed.emit(day())
	hour_changed.emit(hour)
	half_hour_changed.emit(Schedule.slot_of(total_minutes))
	minute_passed.emit(minute_of_day())


func paused() -> bool:
	return speed_index == 0


## Pauses, or carries on at the last speed.
func toggle_pause() -> void:
	speed_index = _last_running if paused() else 0


func speed() -> float:
	return SPEEDS[speed_index]


## The day number, from 1.
func day() -> int:
	return floori(total_minutes / MINUTES_PER_DAY) + 1


func weekday() -> String:
	return WEEKDAYS[(day() - 1) % WEEKDAYS.size()]


## Whole minutes since midnight.
func minute_of_day() -> int:
	return posmod(floori(total_minutes), MINUTES_PER_DAY)


func hour() -> int:
	return minute_of_day() / MINUTES_PER_HOUR


## The time of day in hours, with the fraction, such as 13.5 for 13:30.
func hour_float() -> float:
	return fposmod(total_minutes, MINUTES_PER_DAY) / MINUTES_PER_HOUR


## Minutes since the current hour began.
func minute_of_hour() -> int:
	return minute_of_day() % MINUTES_PER_HOUR


## "07:45"
func time_text() -> String:
	return "%02d:%02d" % [hour(), minute_of_hour()]


static func hour_text(hour: int) -> String:
	return "%02d:00" % hour


func _cross(from: int, to: int) -> void:
	for whole in range(from + 1, to + 1):
		var minute := posmod(whole, MINUTES_PER_DAY)
		if minute == 0:
			day_changed.emit(whole / MINUTES_PER_DAY + 1)
		if minute % MINUTES_PER_HOUR == 0:
			hour_changed.emit(minute / MINUTES_PER_HOUR)
		if minute % 30 == 0:
			half_hour_changed.emit(Schedule.slot_of(whole))
		minute_passed.emit(minute)
