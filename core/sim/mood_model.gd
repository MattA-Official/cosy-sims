class_name MoodModel
extends Resource
## How mood is worked out, Sims-style: a middling 50, plus a little for each
## need that is well met, minus more for each that is low, plus the rooms
## someone sleeps and spends time in, plus moodlets (a good meal, being
## locked up hungry). Each part keeps its words, so the inspector can
## always say why someone is unhappy. Mood follows the total gently rather
## than jumping.
##
##   mood = 50 + need parts + room parts + moodlets, kept between 0 and 100

enum Face { BEAMING, CONTENT, FED_UP, ANGRY }

const FACE_NAMES: Array[String] = ["Beaming", "Content", "Fed up", "Angry"]

@export var base := 50.0
## A need above this adds up to `high_most`, at 100.
@export var high_line := 70.0
@export var high_most := 5.0
## Below this takes off up to `low_most` at `urgent_line`...
@export var low_line := 40.0
@export var low_most := -10.0
## ...and below that, up to `urgent_most` at 0.
@export var urgent_line := 15.0
@export var urgent_most := -20.0
## Points a game hour mood moves towards what the parts add up to.
@export var follow_per_hour := 40.0
## Where the faces change.
@export var beaming_from := 75.0
@export var content_from := 50.0
@export var fed_up_from := 30.0


## What one need adds to mood: up to +5 when well met, nothing in the
## middle, down to -20 when it has run out.
func need_points(value: float) -> float:
	if value > high_line:
		return high_most * (value - high_line) / (100.0 - high_line)
	if value >= low_line:
		return 0.0
	if value >= urgent_line:
		return low_most * (low_line - value) / (low_line - urgent_line)
	return low_most + (urgent_most - low_most) * (urgent_line - value) / urgent_line


## Everything that makes up someone's mood, as [words, points] pairs with
## the biggest effect first. `extras` are the parts the caller worked out
## (rooms, cellmates, crowds), already as pairs; moodlets come from
## `moodlet_defs` by id, scaled by any trait that takes bad ones harder.
func parts(person: Person, needs: Array[NeedDef], moodlet_defs: Dictionary, extras: Array) -> Array:
	var out: Array = []
	for def in needs:
		if not person.needs.has(def.id):
			continue
		var points := need_points(person.needs[def.id])
		if not is_zero_approx(points):
			out.append([def.high_text if points > 0.0 else def.low_text, points])
	out.append_array(extras)
	var bad_scale := 1.0
	for t in person.traits:
		bad_scale *= t.bad_mood_scale
	for id: StringName in person.moodlets:
		var def: MoodletDef = moodlet_defs.get(id)
		if def != null:
			out.append([def.display_name, def.mood * (bad_scale if def.mood < 0.0 else 1.0)])
	out.sort_custom(func(a: Array, b: Array) -> bool: return absf(a[1]) > absf(b[1]))
	return out


## The mood the parts add up to, between 0 and 100.
func target(mood_parts: Array) -> float:
	var total := base
	for part: Array in mood_parts:
		total += part[1]
	return clampf(total, 0.0, 100.0)


## Moves mood towards the parts' total over some game minutes.
func follow(mood: float, mood_parts: Array, minutes: float) -> float:
	return move_toward(mood, target(mood_parts), follow_per_hour / 60.0 * minutes)


func face(mood: float) -> Face:
	if mood >= beaming_from:
		return Face.BEAMING
	if mood >= content_from:
		return Face.CONTENT
	if mood >= fed_up_from:
		return Face.FED_UP
	return Face.ANGRY
