class_name Person
extends RefCounted
## One person: where they are, what they need, and what they are doing.
## People moves and decides for them; this is just their state.

enum State { IDLE, WALKING, USING }

var id := 0
var name := ""
var level := 0
## Tile units across the ground, metres up.
var position := Vector3.ZERO
## Each need's id: how met it is, from 0 to 100.
var needs: Dictionary[StringName, float] = {}
var state := State.IDLE
## What they are doing, in words, for the inspector.
var activity := "Standing about"
## Walking about with nowhere in particular to be, so a pressing need can
## cut it short.
var wandering := false

## The positions still to walk to, with each one's level and whether it
## is on floor or ground.
var route: Array[Vector3] = []
var route_levels: Array[int] = []
var route_on_surface: Array[bool] = []
## The object they are heading for or using, as (level, object id), and
## the need it is for.
var target := Vector2i(0, 0)
var target_need: StringName = &""
## Where they stood before stepping onto the object.
var stand_spot := Vector3.ZERO
## Seconds left: using an object, or waiting before wandering again.
var timer := 0.0
## Needs nothing could be found for, with seconds before trying again.
var gave_up: Dictionary[StringName, float] = {}


func flat() -> Vector2:
	return Vector2(position.x, position.z)


func has_target() -> bool:
	return target_need != &""


## The lowest need below `line`, or &"" if all are fine.
func most_pressing(line: float) -> StringName:
	var best: StringName = &""
	for need: StringName in needs:
		if needs[need] < line and not gave_up.has(need) and (best == &"" or needs[need] < needs[best]):
			best = need
	return best
