class_name Reputation
extends Node
## What the town thinks of the place, 0 to 100, starting at 50. It moves
## only through named, dated entries (ReputationEventDef), so it can always
## say why. Old news fades: each midnight the score drifts DRIFT of the way
## back to 50, and a quiet, happy day earns a little. The local paper leads
## with the day's weightiest news. Shared by any game.

const START := 50.0
const DRIFT := 0.02
## Days entries and headlines are kept.
const KEEP_DAYS := 14
const HEADLINE_DAYS := 7
## A day with no bad news and mood above this earns QUIET_GAIN.
const QUIET_MOOD := 60.0
const QUIET_GAIN := 0.5
const QUIET_ID := &"quiet_day"
const PAPER_NAMES: Array[String] = ["Little Hollow Gazette", "Bramley Bugle", "Thistledown Times",
		"Puddleby Post", "Netherwold Echo", "Ashcombe Advertiser", "Market Wending Mercury", "Kettlewell Courier"]

signal changed(score: float)
signal reported(entry: Dictionary)

var defs: Array[ReputationEventDef] = []
var score := START
## Recent news, newest last: {day, id, subject, change, words}.
var entries: Array[Dictionary] = []
## The papers' headlines, newest last: {day, words}.
var headlines: Array[Dictionary] = []
var paper_name := ""
## () -> float: average mood, for quiet days. Optional.
var mood: Callable
## (def, change) -> float: more scales on a change, such as a public
## relations card for good news.
var change_scales: Array[Callable] = []
var clock: GameClock:
	set(value):
		clock = value
		clock.day_changed.connect(func(day: int) -> void: midnight(day - 1))

var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	if paper_name.is_empty():
		paper_name = PAPER_NAMES[_rng.randi() % PAPER_NAMES.size()]


func def_of(id: StringName) -> ReputationEventDef:
	for def in defs:
		if def.id == id:
			return def
	return null


## Something newsworthy happened. Returns the entry, or {} if it isn't
## news (unknown, or already in today's paper).
func report(id: StringName, subject := "") -> Dictionary:
	var def := def_of(id)
	if def == null:
		return {}
	var today := _day()
	if def.once_a_day and entries.any(func(e: Dictionary) -> bool: return e.id == id and e.day == today):
		return {}
	var amount := def.change
	for scale in change_scales:
		amount *= scale.call(def, amount)
	var words := def.headlines[_rng.randi() % def.headlines.size()] if not def.headlines.is_empty() else String(id)
	words = words.format({"name": subject if not subject.is_empty() else "A prisoner"})
	var entry := {"day": today, "id": id, "subject": subject, "change": amount, "words": words}
	entries.append(entry)
	_set_score(score + amount)
	reported.emit(entry)
	return entry


## Midnight: a quiet day earns a little, then everything fades back
## towards 50.
func midnight(day: int) -> void:
	var bad := entries.any(func(e: Dictionary) -> bool:
		var def := def_of(e.id)
		return e.day == day and def != null and def.tone == ReputationEventDef.Tone.BAD)
	if not bad and mood.is_valid() and mood.call() > QUIET_MOOD:
		var def := def_of(QUIET_ID)
		if def != null:
			var was_day := entries.size()
			report(QUIET_ID)
			if entries.size() > was_day:
				entries[-1].day = day
		else:
			_set_score(score + QUIET_GAIN)
	_set_score(score + (START - score) * DRIFT)
	entries = entries.filter(func(e: Dictionary) -> bool: return e.day > day - KEEP_DAYS)


## The day's news, weightiest first.
func news(day: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for entry in entries:
		if entry.day == day:
			out.append(entry)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return _weight(a) > _weight(b))
	return out


## Notes a paper's headline.
func print_headline(day: int, words: String) -> void:
	headlines.append({"day": day, "words": words})
	headlines = headlines.filter(func(h: Dictionary) -> bool: return h.day > day - HEADLINE_DAYS)


## The last few entries, newest first, as "−8 Prisoner on the run!".
func recent_words(count := 5) -> Array[String]:
	var out: Array[String] = []
	for i in range(entries.size() - 1, maxi(entries.size() - 1 - count, -1), -1):
		var entry: Dictionary = entries[i]
		out.append("%+.1f %s" % [entry.change, entry.words])
	return out


## "Good", "Fair" and so on, for the score.
func words() -> String:
	if score >= 80.0:
		return "Loved"
	if score >= 65.0:
		return "Well thought of"
	if score >= 35.0:
		return "Fair"
	if score >= 20.0:
		return "Frowned on"
	return "Notorious"


func capture() -> Dictionary:
	return {"score": score, "entries": entries.duplicate(true), "headlines": headlines.duplicate(true),
			"paper_name": paper_name}


func restore(data: Dictionary) -> void:
	score = float(data.get("score", START))
	entries.assign(data.get("entries", []))
	headlines.assign(data.get("headlines", []))
	paper_name = data.get("paper_name", paper_name)
	changed.emit(score)


func _weight(entry: Dictionary) -> int:
	var def := def_of(entry.id)
	return def.weight if def != null else 0


func _set_score(value: float) -> void:
	score = clampf(value, 0.0, 100.0)
	changed.emit(score)


func _day() -> int:
	return clock.day() if clock != null else 0
