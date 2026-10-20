class_name Laundry
extends Node
## Uniforms. After a shower, prisoners drop their uniform in a laundry
## basket and take a clean one from a clothes shelf; with none left on the
## shelves they put the old one back on and feel grubby. Cleaners carry
## baskets to a washing machine, wash and iron the uniforms and stack them
## back on the shelves. With no laundry basket anywhere, nobody changes.

const WASH_MINUTES := 30.0
const IRON_MINUTES := 10.0
## Changing happens after using an object with this tag.
const CHANGE_AT := &"shower"
## A basket this full goes to the wash, or any at all once the shelves run
## this low.
const LOAD := 4
const BASKETS: Array[StringName] = [&"laundry_basket"]
const SHELVES: Array[StringName] = [&"clothes_shelf"]
const MACHINES: Array[StringName] = [&"washing_machine"]
const BOARDS: Array[StringName] = [&"ironing_board"]
const LOOK_MINUTES := 10
## Clean uniforms on the shelves for each prisoner at the start.
const SPARES := 1.5

var people: People:
	set(value):
		people = value
		people.used.connect(_on_used)
var clock: GameClock:
	set(value):
		clock = value
		clock.minute_passed.connect(func(minute: int) -> void:
			if minute % LOOK_MINUTES == 0:
				look())
var jobs: JobBoard
var items: ItemStore
var building: Building
var dirty := PrisonCatalogue.item(&"dirty_laundry")
var clean := PrisonCatalogue.item(&"clean_laundry")

## Baskets being taken to the wash, with the job for each.
var _washing: Dictionary[Vector2i, Job] = {}


## Stocks the shelves with clean uniforms: one for every prisoner and
## half as many again, so there are spares while a load is in the wash.
func start() -> void:
	var wanted := ceili(_prisoners() * SPARES) - items.total(&"clean_laundry") - items.total(&"dirty_laundry")
	for key in building.objects_tagged(SHELVES):
		if wanted <= 0:
			break
		wanted -= items.put_in(key, building.object_at(key), clean, wanted)


## Posts jobs to take baskets to the wash.
func look() -> void:
	for key: Vector2i in _washing.keys():
		if not jobs.jobs.has(_washing[key]):
			_washing.erase(key)
	var running_low := _clean_on_shelves() < LOAD
	for key in building.objects_tagged(BASKETS):
		var count := items.count_in(key, &"dirty_laundry")
		if not _washing.has(key) and (count >= LOAD or (count > 0 and running_low)):
			_washing[key] = jobs.post(_wash_job(key))


func _on_used(person: Person, placed: BuildingMap.PlacedObject) -> void:
	if person.group != &"prisoner" or not placed.def.tags.has(CHANGE_AT):
		return
	var basket := _nearest(person, BASKETS, func(key: Vector2i) -> bool:
		return items.room_in(key, building.object_at(key)) > 0)
	if basket.y == -1:
		return
	var shelf := _nearest(person, SHELVES, func(key: Vector2i) -> bool:
		return items.count_in(key, &"clean_laundry") > 0)
	if shelf.y == -1:
		people.add_moodlet(person, &"grubby_uniform")
		return
	items.take_from(shelf, &"clean_laundry", 1)
	items.put_in(basket, building.object_at(basket), dirty, 1)


func _wash_job(basket: Vector2i) -> Job:
	var job := Job.new()
	job.kind = &"laundry"
	job.title = "Do the laundry"
	job.priority = 2
	var fetch := Job.at(Job.Do.FETCH, basket.x, basket.y)
	fetch.tag = &"dirty_laundry"
	fetch.count = dirty.carry_count
	fetch.doing = "Picking up the laundry"
	var wash := Job.at_any(Job.Do.WORK, MACHINES)
	wash.minutes = WASH_MINUTES
	wash.doing = "Washing"
	wash.finish = func(_stage: Job.Stage, worker: Person) -> void:
		var load := items.put_down(worker)
		if not load.is_empty():
			items.pick_up(worker, [clean, load[1]])
	var iron := Job.at_any(Job.Do.WORK, BOARDS)
	iron.minutes = IRON_MINUTES
	iron.doing = "Ironing"
	var stack := Job.at_any(Job.Do.DELIVER, SHELVES, &"clean_laundry")
	stack.doing = "Stacking clean uniforms"
	job.stages = [fetch, wash, iron, stack]
	return job


func _clean_on_shelves() -> int:
	var count := 0
	for key in building.objects_tagged(SHELVES):
		count += items.count_in(key, &"clean_laundry")
	return count


## The nearest object with one of the tags that passes `test`, as (level,
## object id), or (0, -1).
func _nearest(person: Person, tags: Array[StringName], test: Callable) -> Vector2i:
	var best := Vector2i(0, -1)
	var best_distance := INF
	for key in building.objects_tagged(tags):
		if not test.call(key):
			continue
		var distance := building.object_at(key).centre.distance_to(person.flat()) + absi(key.x - person.level) * 12.0
		if distance < best_distance:
			best = key
			best_distance = distance
	return best


func _prisoners() -> int:
	return people.people.filter(func(p: Person) -> bool: return p.group == &"prisoner").size()
