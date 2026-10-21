class_name Person
extends RefCounted
## One person: where they are, what they need, and what they are doing.
## People moves and decides for them; this is just their state.

enum State { IDLE, WALKING, USING }

## No bed of their own.
const NO_BED := Vector2i(0, -1)
## `target` when what they are seeing to is a place or company rather
## than an object.
const NO_OBJECT := Vector2i(0, -1)

var id := 0
var name := ""
## Seeds how they look; -1 to go by id. Someone coming back keeps theirs.
var look_seed := -1
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
## Why they are doing it, such as "Eat block" or "Bladder is low".
var reason := ""

## Who they are: two traits, picked when they arrive.
var traits: Array[TraitDef] = []
## Anything else the game wants to know about them, such as a prisoner's
## security category or sentence.
var profile: Dictionary = {}
## From 0 (furious) to 100 (beaming), worked out from `mood_parts`.
var mood := 50.0
## What makes up their mood, as [words, points] pairs, biggest effect
## first.
var mood_parts: Array = []
## Moodlet ids, with game minutes each has left to run.
var moodlets: Dictionary[StringName, float] = {}
## Out in the open air just now, and near people who are up and about.
var outdoors := false
var in_company := false
## Game minutes until they next look around and decide, and until their
## mood is next worked out.
var think_wait := 0.0
var mood_wait := 0.0

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
## For a need met by a place or company, `target` is NO_OBJECT and the tag
## is the need's id.
var target := Vector2i(0, 0)
var target_tag: StringName = &""
var target_need: StringName = &""
## Where they are fetching the item their object needs first (a meal
## tray for a table), as (level, object id), or NO_OBJECT.
var fetch_from := NO_OBJECT
## Where they stood before stepping onto the object.
var stand_spot := Vector3.ZERO
## The chair they sit on to use a seated object, as (level, object id), or
## NO_OBJECT.
var seat := NO_OBJECT
## Game minutes left: using an object, or waiting before wandering again.
var timer := 0.0
## Object tags nothing could be found for, with game minutes before trying
## again.
var gave_up: Dictionary[StringName, float] = {}
## Game minutes before trying again to reach where the block wants them.
var place_wait := 0.0
## The job they are doing from the jobs board, or null.
var job: Job
## Their staff role, such as &"cook", or empty for none.
var role: StringName = &""
## The work programme a prisoner is on, such as &"kitchen", or empty.
var programme: StringName = &""
## A prisoner's security category (CategoryDef id), or empty.
var category: StringName = &""
## The shift a member of staff works, such as &"day", or empty for always.
var shift: StringName = &""
## On their way home at the end of a shift: they do nothing else.
var going_home := false
## Being walked somewhere by someone else, such as a guard: they decide
## nothing for themselves meanwhile.
var led := false
## When set, doors treat them as this group instead of their own (someone
## slipping out behind a vehicle through a staff-only gate).
var passes_as: StringName = &""
## How close they are to acting up, 0 to 100 (see MisconductModel).
var temper := 0.0
## Game minutes spent under each misconduct rung's mood, by rung id.
var minutes_below: Dictionary[StringName, float] = {}
## What they have done wrong, oldest first: [day, rung id, words].
var record: Array = []
## A rung they are about to act on, and game minutes until they do.
var warning: StringName = &""
var warning_minutes := 0.0
## Words over their head, and game minutes left to show them.
var bubble := ""
var bubble_minutes := 0.0
## Game minutes left ignoring the timetable, up to no good.
var truant_minutes := 0.0
## How fast they walk, against everyone's usual speed.
var pace := 1.0
## How well they are, 0 to 100 (see Health).
var health := 100.0
## Lying down where they are, such as in an infirmary bed.
var lying := false
## Sat on the floor where they are, such as in a sit-in.
var sitting := false
## Privileges lost for now (see PrivilegeDef): id to game days left.
var restrictions: Dictionary[StringName, float] = {}
## Points from offences on their record, fading a little each day.
var points := 0.0
## Game hours left in the quiet room, 0 if not.
var quiet_room_hours := 0.0
## Contraband tucked away about them, out of sight.
var pocket: Array[ItemDef] = []


func flat() -> Vector2:
	return Vector2(position.x, position.z)


func has_target() -> bool:
	return target_tag != &""


## Whether they are heading for or using an object, rather than a place.
func has_object() -> bool:
	return has_target() and target != NO_OBJECT


func has_trait(id: StringName) -> bool:
	return traits.any(func(t: TraitDef) -> bool: return t.id == id)


func has_bed() -> bool:
	return bed != NO_BED
