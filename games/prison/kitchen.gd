class_name Kitchen
extends Node
## The food chain. Every morning the lorry leaves crates of food on the
## delivery pallet, enough for two days' meals counting what is in stock;
## handymen carry them to fridges and food shelves. An hour before each
## mealtime the cooks fetch a crate each, cook a batch of trays and fill
## the serving counter, and prisoners pick up a tray on their way to a
## table; leftovers are scraped away once the meal is over. With no
## serving counter anywhere, tables feed people as they always have, and
## nothing is cooked.

const DELIVERY_HOUR := 6
const MEALS_PER_BATCH := 8
const COOK_MINUTES := 20.0
## A good_meal moodlet this fresh was from the mealtime just ending.
const FRESH_MEAL_MINUTES := 120.0
## Days of meals to keep in stock after a delivery.
const STOCK_DAYS := 2
## The block whose own object is a table is a mealtime.
const MEAL_TAG := &"table"
const STORES: Array[StringName] = [&"fridge", &"food_shelf"]
## Where cooks take crates from: the stores, or straight off the pallet.
const COOK_FROM: Array[StringName] = [&"fridge", &"food_shelf", &"delivery_pallet"]
const COUNTERS: Array[StringName] = [&"serving_counter"]
const COOKERS: Array[StringName] = [&"cooker"]
const PALLETS: Array[StringName] = [&"delivery_pallet"]

## The lorry has been, leaving this many crates.
signal delivered(count: int)

## When set, its operation times are used instead of the hour above (main
## passes on Regime.operation_due).
var regime: Regime
var clock: GameClock:
	set(value):
		clock = value
		clock.hour_changed.connect(_on_hour)
		clock.half_hour_changed.connect(_on_half_hour)
var people: People
var jobs: JobBoard
var items: ItemStore
var building: Building
## The prisoners' timetable, for when meals are.
var schedule: Schedule
var crate := PrisonCatalogue.item(&"food_crate")
var tray := PrisonCatalogue.item(&"meal_tray")
## For skilled cooks' "tasty_meals". Optional.
var modifiers: Modifiers
var _rng := RandomNumberGenerator.new()


## Gets the day going from wherever the clock is: a delivery, and cooking
## if a meal is due within the hour.
func start() -> void:
	deliver()
	var now := Schedule.slot_of(clock.total_minutes)
	if _meal_starts(now + 1) or _meal_starts(now + 2):
		cook()
	elif schedule.at_slot(now) != null and schedule.at_slot(now).main_tag == MEAL_TAG:
		# Starting at a mealtime, the meal is already out.
		var wanted := _prisoners()
		for key in building.objects_tagged(COUNTERS):
			if not building.objects_tagged(COOKERS).is_empty():
				wanted -= items.put_in(key, building.object_at(key), tray, wanted)


func _on_hour(hour: int) -> void:
	if hour == DELIVERY_HOUR and regime == null:
		deliver()
	_unload()


## Cooking starts an hour before each meal; leftovers go once it ends.
func _on_half_hour(slot: int) -> void:
	if _meal_starts(slot + 2):
		cook()
	if _meal_ends(slot):
		clear_leftovers()
		tasty_meals()


## Scrapes away whatever trays are left on the counters and cookers.
## Returns how many.
func clear_leftovers() -> int:
	var cleared := 0
	for key in building.objects_tagged(COUNTERS) + building.objects_tagged(COOKERS):
		while true:
			var taken := items.take_from(key, &"meal", 999)
			if taken.is_empty():
				break
			cleared += taken[1]
	return cleared


## With skilled cooks (the "tasty_meals" modifier), each prisoner who had a
## good meal this mealtime has that chance of it having been lovely.
## Returns how many.
func tasty_meals() -> int:
	var chance := modifiers.value(&"tasty_meals") if modifiers != null else 0.0
	if chance <= 0.0:
		return 0
	var good: MoodletDef = PrisonCatalogue.moodlets()[&"good_meal"]
	var count := 0
	for person in people.people:
		var left: float = person.moodlets.get(&"good_meal", 0.0)
		# Only meals from this sitting: still nearly all their time to run.
		if left <= 0.0 or left < good.hours * 60.0 - FRESH_MEAL_MINUTES or _rng.randf() >= chance:
			continue
		person.moodlets.erase(&"good_meal")
		people.add_moodlet(person, &"lovely_meal")
		count += 1
	return count


## The lorry leaves enough crates on the delivery pallets to keep two
## days' meals in stock, as far as they fit. Returns how many came.
func deliver() -> int:
	var per_day := ceili(float(_prisoners() * meals_per_day()) / MEALS_PER_BATCH)
	var wanted := per_day * STOCK_DAYS - items.total(&"ingredient")
	var came := 0
	for key in building.objects_tagged(PALLETS):
		if wanted - came <= 0:
			break
		came += items.put_in(key, building.object_at(key), crate, wanted - came)
	if came > 0:
		delivered.emit(came)
		_unload()
	return came


## Posts jobs to carry crates on the pallets to the stores, for any not
## already being carried.
func _unload() -> void:
	if building.objects_tagged(STORES).is_empty():
		return
	for key in building.objects_tagged(PALLETS):
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
	if building.objects_tagged(COUNTERS).is_empty() or building.objects_tagged(COOKERS).is_empty():
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
			items.put_in(key, building.object_at(key), tray, MEALS_PER_BATCH)
		var collect := Job.at_any(Job.Do.FETCH, COOKERS, &"meal")
		collect.count = MEALS_PER_BATCH
		collect.doing = "Picking up the trays"
		var serve := Job.at_any(Job.Do.DELIVER, COUNTERS, &"meal")
		serve.doing = "Filling the serving counter"
		job.stages = [fetch, work, collect, serve]
		jobs.post(job)
	return maxi(batches, 0)


## What's wrong with the food chain, in words, for the jobs panel.
func warnings() -> Array[String]:
	var out: Array[String] = []
	if building.objects_tagged(COUNTERS).is_empty():
		return out
	if building.objects_tagged(COOKERS).is_empty():
		out.append("A serving counter but no cooker: meals will be missed")
	if building.objects_tagged(PALLETS).is_empty():
		out.append("No delivery pallet, so no food arrives")
	elif items.total(&"ingredient") * MEALS_PER_BATCH < _prisoners() * meals_per_day():
		out.append("Not enough food in for tomorrow's meals")
	if not people.people.any(func(p: Person) -> bool: return p.role == &"cook" or p.programme == &"kitchen"):
		out.append("Nobody to cook")
	return out


## How many meals the prisoners' timetable has in a day.
func meals_per_day() -> int:
	var count := 0
	var day := Schedule.weekday_of(clock.total_minutes) if clock != null else 0
	for i in Schedule.SLOTS_PER_DAY:
		if _meal_starts(day * Schedule.SLOTS_PER_DAY + i):
			count += 1
	return count


## Whether a meal starts in a half hour of the week.
func _meal_starts(slot: int) -> bool:
	var now := schedule.at_slot(slot)
	return now != null and now.main_tag == MEAL_TAG and schedule.at_slot(slot - 1) != now


func _meal_ends(slot: int) -> bool:
	var before := schedule.at_slot(slot - 1)
	return before != null and before.main_tag == MEAL_TAG and schedule.at_slot(slot) != before


func _prisoners() -> int:
	return people.people.filter(func(p: Person) -> bool: return p.group == &"prisoner").size()
