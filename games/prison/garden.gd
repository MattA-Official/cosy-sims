class_name Garden
extends Node
## Prisoners on the garden programme tend the vegetable beds, once a day
## each. After GROW_DAYS of tending a bed is ready, and that day's gardener
## brings a crate of veg in to the kitchen's stores, so the lorry brings
## one crate fewer.

## A bed has given a crate of veg.
signal harvested(key: Vector2i)

const TEND_MINUTES := 30.0
const GROW_DAYS := 4
const BEDS: Array[StringName] = [&"veg_bed"]
const KIND := &"garden"

var jobs: JobBoard
var items: ItemStore
var building: Building
var clock: GameClock:
	set(value):
		clock = value
		clock.hour_changed.connect(func(_hour: int) -> void: look())
var crate := PrisonCatalogue.item(&"food_crate")
## Bed (level, id) -> days tended since the last crop.
var growth: Dictionary[Vector2i, int] = {}
## Bed -> the day it was last tended.
var tended: Dictionary[Vector2i, int] = {}


## Keeps a tending job on the board for each bed not yet tended today.
func look() -> void:
	var today := _day()
	var waiting: Array[Vector2i] = []
	for job in jobs.of_kind(KIND):
		waiting.append(Vector2i(job.stages[0].level, job.stages[0].object))
	for key in building.objects_tagged(BEDS):
		if tended.get(key, -1) != today and not waiting.has(key):
			jobs.post(_tend_job(key))
	for key: Vector2i in growth.keys():
		if building.object_at(key) == null:
			growth.erase(key)
			tended.erase(key)


## A day's tending done: the bed grows, and is picked when ready.
func tend(key: Vector2i, worker: Person) -> void:
	tended[key] = _day()
	growth[key] = growth.get(key, 0) + 1
	if growth[key] >= GROW_DAYS and worker != null and _has_store():
		growth[key] = 0
		items.pick_up(worker, [crate, 1])
		harvested.emit(key)


## How a bed is coming along, for the inspector.
func words(key: Vector2i) -> String:
	var days: int = growth.get(key, 0)
	if days >= GROW_DAYS:
		return "Ready to pick, once there's a fridge or food shelf"
	return "Growing: %d of %d days" % [days, GROW_DAYS]


func capture() -> Dictionary:
	var out := {}
	for key in growth:
		out["%d,%d" % [key.x, key.y]] = [growth[key], tended.get(key, -1)]
	return {"beds": out}


func restore(data: Dictionary) -> void:
	growth.clear()
	tended.clear()
	var beds: Dictionary = data.get("beds", {})
	for text: String in beds:
		var key := Vector2i(int(text.get_slice(",", 0)), int(text.get_slice(",", 1)))
		growth[key] = int(beds[text][0])
		tended[key] = int(beds[text][1])


func _tend_job(key: Vector2i) -> Job:
	var job := Job.new()
	job.kind = KIND
	job.title = "Tend the vegetables"
	job.priority = 1
	var work := Job.at(Job.Do.WORK, key.x, key.y)
	work.minutes = TEND_MINUTES
	work.doing = "Watering and weeding"
	work.finish = func(_stage: Job.Stage, worker: Person) -> void: tend(key, worker)
	job.stages = [work]
	# The day it is picked, the crate goes in to the stores.
	if growth.get(key, 0) + 1 >= GROW_DAYS and _has_store():
		var store := Job.at_any(Job.Do.DELIVER, Kitchen.COOK_FROM, &"ingredient")
		store.doing = "Bringing the veg in"
		job.stages.append(store)
	return job


func _has_store() -> bool:
	return not building.objects_tagged(Kitchen.COOK_FROM).is_empty()


func _day() -> int:
	return clock.day() if clock != null else 1
