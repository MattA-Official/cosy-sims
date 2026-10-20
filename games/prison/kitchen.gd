class_name Kitchen
extends Node
## The food chain. Every morning the lorry leaves crates of food on the
## delivery pallet, enough for two days' meals counting what is in stock;
## handymen carry them to fridges and food shelves. An hour before each
## mealtime the cooks fetch a crate each, cook a batch of trays and fill
## the serving counter, and prisoners pick up a tray on their way to a
## table. With no serving counter anywhere, tables feed people as they
## always have, and nothing is cooked.

const DELIVERY_HOUR := 6
const MEALS_PER_BATCH := 8
const COOK_MINUTES := 20.0
## Days of meals to keep in stock after a delivery.
const STOCK_DAYS := 2
## The block whose own object is a table is a mealtime.
const MEAL_TAG := &"table"
const STORES: Array[StringName] = [&"fridge", &"food_shelf"]
## Where cooks take crates from: the stores, or straight off the pallet.
const COOK_FROM: Array[StringName] = [&"fridge", &"food_shelf", &"delivery_pallet"]
const COUNTERS: Array[StringName] = [&"serving_counter"]
const COOKERS: Array[StringName] = [&"cooker"]

## The lorry has been, leaving this many crates.
signal delivered(count: int)

var clock: GameClock:
	set(value):
		clock = value
		clock.hour_changed.connect(_on_hour)
var people: People
var jobs: JobBoard
var items: ItemStore
var building: Building
## The prisoners' timetable, for when meals are.
var schedule: Schedule
var crate := PrisonCatalogue.item(&"food_crate")
var tray := PrisonCatalogue.item(&"meal_tray")


## Gets the day going from wherever the clock is: a delivery, and cooking
## if a meal is due within the hour.
func start() -> void:
	deliver()
	if _meal_starts(clock.hour() + 1):
		cook()
	elif schedule.at(clock.hour()) != null and schedule.at(clock.hour()).main_tag == MEAL_TAG:
		# Starting at a mealtime, the meal is already out.
		var wanted := _prisoners()
		for key in _objects_tagged(&"serving_counter"):
			if _has_any(COOKERS):
				wanted -= items.put_in(key, _placed(key), tray, wanted)


func _on_hour(hour: int) -> void:
	if hour == DELIVERY_HOUR:
		deliver()
	_unload()
	if _meal_starts(hour + 1):
		cook()


## The lorry leaves enough crates on the delivery pallets to keep two
## days' meals in stock, as far as they fit. Returns how many came.
func deliver() -> int:
	var per_day := ceili(float(_prisoners() * meals_per_day()) / MEALS_PER_BATCH)
	var wanted := per_day * STOCK_DAYS - items.total(&"ingredient")
	var came := 0
	for key in _objects_tagged(&"delivery_pallet"):
		if wanted - came <= 0:
			break
		came += items.put_in(key, _placed(key), crate, wanted - came)
	if came > 0:
		delivered.emit(came)
		_unload()
	return came


## Posts jobs to carry crates on the pallets to the stores, for any not
## already being carried.
func _unload() -> void:
	if not _has_any(STORES):
		return
	for key in _objects_tagged(&"delivery_pallet"):
		var waiting := items.count_in(key, &"ingredient")
		for job in jobs.of_kind(&"carry"):
			if job.stage == 0 and job.current().level == key.x and job.current().object == key.y:
				waiting -= job.current().count
		while waiting > 0:
			var count := mini(waiting, crate.carry_count)
			var job := Job.carry(&"ingredient", count, Job.at(Job.Do.FETCH, key.x, key.y),
					Job.at_any(Job.Do.DELIVER, STORES, &"ingredient"))
			job.title = "Put away the food delivery"
			job.priority = 2
			jobs.post(job)
			waiting -= count


## Posts a cooking job for each batch of trays the next meal needs, less
## any already cooked or cooking. Nothing is cooked without a serving
## counter to put it on.
func cook() -> int:
	if not _has_any(COUNTERS) or not _has_any(COOKERS):
		return 0
	var ready := items.total(&"meal") + jobs.of_kind(&"cook").size() * MEALS_PER_BATCH
	var batches := ceili(float(_prisoners() - ready) / MEALS_PER_BATCH)
	for i in batches:
		var job := Job.new()
		job.kind = &"cook"
		job.title = "Cook a batch of meals"
		job.priority = 3
		var fetch := Job.at_any(Job.Do.FETCH, COOK_FROM, &"ingredient")
		fetch.doing = "Fetching food"
		var work := Job.at_any(Job.Do.WORK, COOKERS, &"meal")
		work.minutes = COOK_MINUTES
		work.doing = "Cooking"
		work.finish = func(stage: Job.Stage, worker: Person) -> void:
			items.put_down(worker) # The crate, cooked.
			var key := Vector2i(stage.level, stage.object)
			items.put_in(key, _placed(key), tray, MEALS_PER_BATCH)
		var collect := Job.at_any(Job.Do.FETCH, COOKERS, &"meal")
		collect.count = MEALS_PER_BATCH
		collect.doing = "Picking up the trays"
		var serve := Job.at_any(Job.Do.DELIVER, COUNTERS, &"meal")
		serve.doing = "Filling the serving counter"
		job.stages = [fetch, work, collect, serve]
		jobs.post(job)
	return maxi(batches, 0)


## How many meals the prisoners' timetable has in a day.
func meals_per_day() -> int:
	var count := 0
	for hour in Schedule.HOURS:
		if _meal_starts(hour):
			count += 1
	return count


func _meal_starts(hour: int) -> bool:
	var now := schedule.at(hour)
	return now != null and now.main_tag == MEAL_TAG and schedule.at(hour - 1) != now


func _prisoners() -> int:
	return people.people.filter(func(p: Person) -> bool: return p.group == &"prisoner").size()


func _objects_tagged(tag: StringName) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for n: int in building.levels:
		for placed: BuildingMap.PlacedObject in building.levels[n].objects.values():
			if placed.def.tags.has(tag):
				out.append(Vector2i(n, placed.id))
	return out


func _has_any(tags: Array[StringName]) -> bool:
	return tags.any(func(tag: StringName) -> bool: return not _objects_tagged(tag).is_empty())


func _placed(key: Vector2i) -> BuildingMap.PlacedObject:
	return building.levels[key.x].objects.get(key.y)
