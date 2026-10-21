class_name Cleaning
extends Node
## Litter and rubbish. People leave litter after meals (Messy ones more
## often), which makes a room worse until it's swept up. Cleaners sweep
## each bit into the nearest bin; full bins are bagged up and the bags
## carried to the skip, which the lorry empties every morning. Without a
## bin, sweeping simply clears it away.

## How often, in game minutes, to look for litter and full bins.
const LOOK_MINUTES := 5
const SWEEP_MINUTES := 1.0
const BAG_MINUTES := 1.0
## A bin this full gets emptied.
const FULL := 0.6
const LITTER := &"litter"
const BAG := &"rubbish_bag"
const BINS: Array[StringName] = [&"bin"]
const SKIPS: Array[StringName] = [&"skip"]

## When set, its operation times are used instead of the hour above (main
## passes on Regime.operation_due).
var regime: Regime
var clock: GameClock:
	set(value):
		clock = value
		clock.minute_passed.connect(func(minute: int) -> void:
			if minute % LOOK_MINUTES == 0:
				look())
		clock.hour_changed.connect(func(hour: int) -> void:
			if hour == Kitchen.DELIVERY_HOUR and regime == null:
				collect())
var jobs: JobBoard
var items: ItemStore
var building: Building
var bag := PrisonCatalogue.item(&"rubbish_bag")
## (worker: Person) -> bool: a thorough cleaner, who sweeps the tiles
## around them too (StaffRoster.skilled). Optional.
var skilled: Callable

## Litter being swept, by floor tile, and bins being emptied, by (level,
## object id), with the job for each.
var _sweeping: Dictionary[Vector3i, Job] = {}
var _emptying: Dictionary[Vector2i, Job] = {}


## Posts jobs for litter nobody is sweeping yet, and bins filling up.
func look() -> void:
	for key: Vector3i in _sweeping.keys():
		if not jobs.jobs.has(_sweeping[key]):
			_sweeping.erase(key)
	for key: Vector2i in _emptying.keys():
		if not jobs.jobs.has(_emptying[key]):
			_emptying.erase(key)
	var bins := building.objects_tagged(BINS)
	for key: Vector3i in items.floor_spots_of(LITTER):
		if not _sweeping.has(key):
			_sweeping[key] = jobs.post(_sweep_job(key, not bins.is_empty()))
	for key in bins:
		var placed := building.object_at(key)
		if not _emptying.has(key) and items.count_in(key, LITTER) >= placed.def.capacity * FULL:
			_emptying[key] = jobs.post(_empty_job(key, not building.objects_tagged(SKIPS).is_empty()))


## The lorry takes away what's in the skips.
func collect() -> int:
	var taken := 0
	for key in building.objects_tagged(SKIPS):
		taken += items.count_in(key)
		_take_all(key, &"")
	return taken


func _sweep_job(key: Vector3i, to_bin: bool) -> Job:
	var job := Job.new()
	job.kind = &"clean"
	job.title = "Sweep up litter"
	job.priority = 2
	var sweep := Job.on_tile(Job.Do.WORK, key.x, Vector2i(key.y, key.z))
	sweep.minutes = SWEEP_MINUTES
	sweep.doing = "Sweeping up"
	sweep.finish = func(stage: Job.Stage, worker: Person) -> void:
		var swept := items.take_from_floor(Vector3i(stage.level, stage.tile.x, stage.tile.y), LITTER, 999)
		if skilled.is_valid() and skilled.call(worker):
			swept = _sweep_round(stage.level, stage.tile, swept)
		if to_bin and not swept.is_empty():
			items.pick_up(worker, swept)
	job.stages = [sweep]
	if to_bin:
		var put := Job.at_any(Job.Do.DELIVER, BINS, LITTER)
		put.doing = "Putting litter in the bin"
		job.stages.append(put)
	return job


## A thorough sweep: the litter on the eight tiles around too, added to
## what was swept (as one pile of the first kind), and their sweeping
## jobs called off if nobody has started them.
func _sweep_round(level: int, tile: Vector2i, swept: Array) -> Array:
	for x in range(-1, 2):
		for y in range(-1, 2):
			var key := Vector3i(level, tile.x + x, tile.y + y)
			if (x == 0 and y == 0) or not items.on_floor.has(key):
				continue
			var job: Job = _sweeping.get(key)
			if job != null and job.worker != null:
				continue
			var more := items.take_from_floor(key, LITTER, 999)
			if more.is_empty():
				continue
			if swept.is_empty():
				swept = more
			else:
				swept = [swept[0], swept[1] + more[1]]
			if job != null:
				jobs.cancel(job)
				_sweeping.erase(key)
	return swept


func _empty_job(key: Vector2i, to_skip: bool) -> Job:
	var job := Job.new()
	job.kind = &"rubbish"
	job.title = "Empty the bin"
	job.priority = 2
	var bag_up := Job.at(Job.Do.WORK, key.x, key.y)
	bag_up.minutes = BAG_MINUTES
	bag_up.doing = "Bagging up the rubbish"
	bag_up.finish = func(stage: Job.Stage, worker: Person) -> void:
		_take_all(Vector2i(stage.level, stage.object), LITTER)
		if to_skip:
			items.pick_up(worker, [bag, 1])
	job.stages = [bag_up]
	if to_skip:
		var put := Job.at_any(Job.Do.DELIVER, SKIPS, BAG)
		put.doing = "Taking the rubbish to the skip"
		job.stages.append(put)
	return job


## Empties an object of everything with a tag, of every kind.
func _take_all(key: Vector2i, tag: StringName) -> void:
	while not items.take_from(key, tag, 999).is_empty():
		pass
