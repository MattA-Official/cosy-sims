class_name Person
extends RefCounted
## One person: where they are, what they need, and what they are doing.
## People moves and decides for them; this is just their state.

enum State { IDLE, WALKING, USING }

## No bed of their own.
const NO_BED := Vector2i(0, -1)

var id := 0
var name := ""
## Who they are in the game, such as &"prisoner". Each group follows its own
## timetable.
var group: StringName = &"prisoner"
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

## The timetable block they are in, set by ScheduleRunner. Null leaves
## them free.
var block: ActivityDef
## They have used the block's own object (a shower in Shower) this block.
var done_main := false
## Not where the block wants them, though they've had time to get there.
var out_of_place := false
## The bed they sleep in, as (level, object id), or NO_BED. The room it is
## in is their own, such as their cell.
var bed := NO_BED

## The positions still to walk to, with each one's level and whether it
## is on floor or ground.
var route: Array[Vector3] = []
var route_levels: Array[int] = []
var route_on_surface: Array[bool] = []
## The object they are heading for or using, as (level, object id), the
## tag they wanted it for, and the need it sees to (empty if none does).
var target := Vector2i(0, 0)
var target_tag: StringName = &""
var target_need: StringName = &""
## Where they stood before stepping onto the object.
var stand_spot := Vector3.ZERO
## Game minutes left: using an object, or waiting before wandering again.
var timer := 0.0
## Object tags nothing could be found for, with game minutes before trying
## again.
var gave_up: Dictionary[StringName, float] = {}
## Game minutes before trying again to reach where the block wants them.
var place_wait := 0.0


func flat() -> Vector2:
	return Vector2(position.x, position.z)


func has_target() -> bool:
	return target_tag != &""


func has_bed() -> bool:
	return bed != NO_BED
