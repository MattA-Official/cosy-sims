class_name Job
extends RefCounted
## One piece of work on the jobs board: carry a crate to the kitchen, cook
## a batch of meals, sweep up rubbish. A job is a list of stages done in
## order, each at one place: fetch items from somewhere, deliver them
## somewhere else, or work at a spot for a while.

enum Do {
	FETCH, ## Take items with `tag` from an object or the floor.
	DELIVER, ## Put down what they carry in an object (or on the floor).
	WORK, ## Stay a while, then call `finish`.
}


class Stage:
	var do: Do
	var level := 0
	## The object to go to, or -1 for a floor tile.
	var object := -1
	## Object tags to choose from instead of a set object: the nearest
	## suitable one is picked each time the stage starts (one holding the
	## items to fetch, with room for those to deliver, or free to work at).
	var places: Array[StringName] = []
	var tile := Vector2i.ZERO
	## FETCH: the tag of the items to take, and how many at most. DELIVER
	## and WORK with `places`: the tag of items the place must have room
	## for.
	var tag: StringName
	var count := 1
	## WORK: game minutes, and what happens after, called with the stage
	## and the worker.
	var minutes := 0.0
	var finish: Callable
	## What they are doing here, in words, such as "Cooking".
	var doing := ""

	func at_object() -> bool:
		return object != -1 or not places.is_empty()


## Such as &"carry", &"cook" or &"clean".
var kind: StringName
## In words, for the inspector and the jobs list.
var title := ""
## 1 (whenever) to 5 (drop everything).
var priority := 3
## Staff roles that may take it, and work programmes whose people may.
## Empty lets any role or programme that takes jobs of its kind.
var roles: Array[StringName] = []
var programmes: Array[StringName] = []
var stages: Array[Stage] = []
## The stage being worked on.
var stage := 0
var worker: Person
## Game minutes before it may be taken again, after it couldn't be done.
var wait := 0.0
## Why it last couldn't be done, for the inspector.
var reason := ""
var done := false
## Called with the job once its last stage is done.
var on_done: Callable


func current() -> Stage:
	return stages[stage] if stage < stages.size() else null


## A stage at an object.
static func at(do: Do, level: int, object: int) -> Stage:
	var out := Stage.new()
	out.do = do
	out.level = level
	out.object = object
	return out


## A stage on a floor tile.
static func on_tile(do: Do, level: int, tile: Vector2i) -> Stage:
	var out := Stage.new()
	out.do = do
	out.level = level
	out.tile = tile
	return out


## A stage at the nearest object with one of the tags that suits.
static func at_any(do: Do, places: Array[StringName], tag: StringName = &"") -> Stage:
	var out := Stage.new()
	out.do = do
	out.places = places
	out.tag = tag
	return out


## Fetches items with a tag from one object and delivers them to another.
static func carry(tag: StringName, count: int, from: Stage, to: Stage) -> Job:
	var job := Job.new()
	job.kind = &"carry"
	from.do = Do.FETCH
	from.tag = tag
	from.count = count
	from.doing = "Picking up"
	to.do = Do.DELIVER
	to.doing = "Putting down"
	job.stages = [from, to]
	return job
