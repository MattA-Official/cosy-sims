class_name Workshop
extends Node
## Prisoners on the workshop programme make wooden toys and birdhouses at
## the workbenches and stack them on a goods shelf, and the lorry takes
## them away to sell every morning. Every workbench always has a job
## waiting, taken only in work blocks.

## The lorry has taken this many goods away to sell.
signal collected(count: int)

const MAKE_MINUTES := 45.0
const BENCHES: Array[StringName] = [&"workbench"]
const SHELVES: Array[StringName] = [&"goods_shelf"]

var jobs: JobBoard:
	set(value):
		jobs = value
		jobs.job_finished.connect(_on_job_finished)
## When set, its operation times are used instead of the hour above (main
## passes on Regime.operation_due).
var regime: Regime
var clock: GameClock:
	set(value):
		clock = value
		clock.hour_changed.connect(func(hour: int) -> void:
			look()
			if hour == Kitchen.DELIVERY_HOUR and regime == null:
				collect())
var items: ItemStore
var building: Building
## What the workshop makes, one picked at random each time.
var goods: Array[ItemDef] = [PrisonCatalogue.item(&"wooden_toy"), PrisonCatalogue.item(&"birdhouse")]
## Everything the lorry has taken away to sell.
var sold := 0

var _rng := RandomNumberGenerator.new()


## Keeps a making job on the board for every workbench.
func look() -> void:
	var waiting := jobs.of_kind(&"make").size()
	for i in building.objects_tagged(BENCHES).size() - waiting:
		jobs.post(_make_job())


## The lorry takes the goods away. Returns how many.
func collect() -> int:
	var taken := 0
	for key in building.objects_tagged(SHELVES):
		while true:
			var pair := items.take_from(key, &"goods", 999)
			if pair.is_empty():
				break
			taken += pair[1]
	sold += taken
	if taken > 0:
		collected.emit(taken)
	return taken


## A making job again from a save, for whoever was making it.
func rebuild(work: Dictionary) -> Job:
	for item in goods:
		if work["title"] == "Make a %s" % item.display_name.to_lower():
			return _make_job(item)
	return null


func _make_job(item: ItemDef = null) -> Job:
	var job := Job.new()
	job.kind = &"make"
	if item == null:
		item = goods[_rng.randi() % goods.size()]
	job.title = "Make a %s" % item.display_name.to_lower()
	job.priority = 1
	var make := Job.at_any(Job.Do.WORK, BENCHES)
	make.minutes = MAKE_MINUTES
	make.doing = "Making a %s" % item.display_name.to_lower()
	make.finish = func(_stage: Job.Stage, worker: Person) -> void:
		items.pick_up(worker, [item, 1])
	var stack := Job.at_any(Job.Do.DELIVER, SHELVES, &"goods")
	stack.doing = "Putting it on the shelf"
	job.stages = [make, stack]
	return job


func _on_job_finished(job: Job, _worker: Person) -> void:
	if job.kind == &"make":
		look()
