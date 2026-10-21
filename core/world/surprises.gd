class_name Surprises
extends Node
## Small surprises that test one system at a time, never a game over. At
## ROLL_HOUR each day one roll, at the Frequency setting's chance, may draw
## a surprise by weight from those whose season, conditions, first day and
## cooldown allow. One runs at a time; its Surprise script ticks with the
## clock until its hours are up. A surprise with choices waits
## CHOICE_MINUTES for an answer, then takes its default. Shared by any game.

enum Frequency { OFF, RARE, NORMAL, LIVELY }

const CHANCES: Array[float] = [0.0, 0.1, 0.2, 0.35]
const ROLL_HOUR := 7
const CHOICE_MINUTES := 120.0

signal started(surprise: Surprise)
signal finished(surprise: Surprise)
## The answer is due; whoever posted a card for it answers it now.
signal choice_due(surprise: Surprise)
signal changed

var defs: Array[SurpriseDef] = []
var frequency := Frequency.NORMAL
## Harder versions (the hardest difficulty).
var hard := false
## Condition id -> () -> bool. A condition nobody named never holds.
var conditions: Dictionary[StringName, Callable] = {}
var calendar: Calendar
## Passed to each Surprise as its main.
var host: Node
var running: Surprise
## Surprise id -> the day it last came.
var last_day: Dictionary[StringName, int] = {}
## The answer picked for the running surprise, or -1.
var chosen := -1
var choice_wait := 0.0
var clock: GameClock:
	set(value):
		clock = value
		clock.hour_changed.connect(func(hour: int) -> void:
			if hour == ROLL_HOUR:
				roll())
		clock.minute_passed.connect(func(_minute: int) -> void: tick(1.0))

var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()


func find(id: StringName) -> SurpriseDef:
	for def in defs:
		if def.id == id:
			return def
	return null


## The morning roll. Returns what started, or null.
func roll() -> Surprise:
	if running != null or _rng.randf() >= CHANCES[frequency]:
		return null
	var def := draw()
	return start(def) if def != null else null


## Whether a surprise may come today.
func may_come(def: SurpriseDef) -> bool:
	var today := _day()
	if def.weight <= 0.0 or def.behaviour == null or today < def.min_day:
		return false
	if last_day.has(def.id) and today - last_day[def.id] < def.cooldown_days:
		return false
	if not def.seasons.is_empty():
		var season := calendar.season() if calendar != null and calendar.enabled else null
		if season == null or not def.seasons.has(season.id):
			return false
	for need in def.requires:
		var holds: Callable = conditions.get(need, Callable())
		if not holds.is_valid() or not holds.call():
			return false
	return true


## Picks one that may come, by weight; null for none.
func draw() -> SurpriseDef:
	var pool: Array[SurpriseDef] = []
	var weights := PackedFloat32Array()
	for def in defs:
		if may_come(def):
			pool.append(def)
			weights.append(def.weight)
	return pool[_rng.rand_weighted(weights)] if not pool.is_empty() else null


## Starts a surprise now, whatever the roll says. Null if one is running.
func start(def: SurpriseDef) -> Surprise:
	if running != null or def == null or def.behaviour == null:
		return null
	running = _make(def)
	running.minutes_left = def.hours * 60.0
	last_day[def.id] = _day()
	chosen = -1
	choice_wait = CHOICE_MINUTES
	running.start()
	started.emit(running)
	changed.emit()
	return running


func tick(minutes: float) -> void:
	if running == null:
		return
	if not running.def.choices.is_empty() and chosen < 0:
		choice_wait -= minutes
		if choice_wait <= 0.0:
			choice_due.emit(running)
			if chosen < 0:
				choose(running.def.default_choice)
	if running == null:
		return
	running.tick(minutes)
	running.minutes_left -= minutes
	if running.minutes_left <= 0.0:
		finish()


## The player (or the default) answers the running surprise.
func choose(index: int) -> void:
	if running == null or chosen >= 0 or index < 0 or index >= running.def.choices.size():
		return
	chosen = index
	running.choose(index)
	changed.emit()


func finish() -> void:
	if running == null:
		return
	var done := running
	running = null
	done.finish()
	finished.emit(done)
	changed.emit()


## "Escaped hen · 2h left" for the banner, or "".
func words() -> String:
	if running == null:
		return ""
	var hours := ceili(running.minutes_left / 60.0)
	var extra := running.words()
	return "%s · %s" % [running.def.display_name, extra if not extra.is_empty() else
			"%d hour%s left" % [hours, "" if hours == 1 else "s"]]


func capture() -> Dictionary:
	var out := {"frequency": frequency, "last_day": last_day.duplicate()}
	if running != null:
		out["running"] = {"id": String(running.def.id), "minutes": running.minutes_left, "chosen": chosen,
				"wait": choice_wait, "data": running.to_data()}
	return out


func restore(data: Dictionary) -> void:
	frequency = int(data.get("frequency", frequency)) as Frequency
	last_day.assign(data.get("last_day", {}))
	running = null
	var saved: Dictionary = data.get("running", {})
	var def := find(StringName(saved.get("id", "")))
	if def != null and def.behaviour != null:
		running = _make(def)
		running.minutes_left = float(saved.get("minutes", 0.0))
		chosen = int(saved.get("chosen", -1))
		choice_wait = float(saved.get("wait", CHOICE_MINUTES))
		running.from_data(saved.get("data", {}))
	changed.emit()


func _make(def: SurpriseDef) -> Surprise:
	var surprise: Surprise = def.behaviour.new()
	surprise.def = def
	surprise.main = host
	surprise.hard = hard
	return surprise


func _day() -> int:
	return clock.day() if clock != null else 1
