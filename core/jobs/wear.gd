class_name Wear
extends Node3D
## Objects wear out with use. Each use (someone using it for a need, or a
## job's work done at it) counts towards ObjectDef.uses_before_breaking;
## then it breaks, nobody can use it, a spanner floats over it, and a job
## goes on the board to mend it.

signal broke(key: Vector2i)
signal mended(key: Vector2i)

## Game minutes mending takes.
const REPAIR_MINUTES := 20.0
## Metres above the object the broken marker floats.
const MARKER_HEIGHT := 0.5
## How much longer a skilled mender's repairs last, as a share of the
## object's uses.
const SKILLED_MEND := 0.5

## Research bonuses: wear_rate and repair_speed. Optional.
var modifiers: Modifiers
var people: People:
	set(value):
		people = value
		people.used.connect(func(_person: Person, placed: BuildingMap.PlacedObject) -> void:
			var key := _key_of(placed)
			if key.y != -1:
				use(key))
var jobs: JobBoard:
	set(value):
		jobs = value
		jobs.job_finished.connect(_on_job_finished)
var building: Building:
	set(value):
		building = value
		building.changed.connect(_tidy)
var cell_size := 1.0
## (worker: Person) -> bool: a skilled mender, whose repairs last
## SKILLED_MEND longer (StaffRoster.skilled). Optional.
var skilled: Callable
var marker: Texture2D = preload("res://core/ui/markers/broken.svg")
## Uses since each object was last mended, by (level, object id).
var uses: Dictionary[Vector2i, int] = {}

var _markers: Dictionary[Vector2i, Sprite3D] = {}
var _repairs: Dictionary[Vector2i, Job] = {}


## Counts a use of an object, breaking it once it has had its fill.
func use(key: Vector2i) -> void:
	var placed := building.object_at(key)
	if placed == null or placed.def.uses_before_breaking <= 0 or is_broken(key):
		return
	uses[key] = uses.get(key, 0) + 1
	if uses[key] >= placed.def.uses_before_breaking / maxf(0.1, Modifiers.scale(modifiers, &"wear_rate")):
		break_object(key)


func is_broken(key: Vector2i) -> bool:
	return people.broken.has(key)


## Breaks an object and posts a job to mend it.
func break_object(key: Vector2i) -> void:
	var placed := building.object_at(key)
	if placed == null or is_broken(key):
		return
	people.broken[key] = true
	var sprite := Sprite3D.new()
	sprite.texture = marker
	sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sprite.pixel_size = 0.008
	sprite.no_depth_test = true
	sprite.render_priority = 2
	var map: BuildingMap = building.levels[key.x]
	var floor_y := map.floor_height(Vector2i(placed.centre.floor()))
	sprite.position = Vector3(placed.centre.x * cell_size, floor_y + placed.def.height + MARKER_HEIGHT,
			placed.centre.y * cell_size)
	add_child(sprite)
	_markers[key] = sprite
	var job := Job.new()
	job.kind = &"repair"
	job.title = "Mend the %s" % placed.def.display_name.to_lower()
	job.priority = 3
	var mend := Job.at(Job.Do.WORK, key.x, key.y)
	mend.minutes = REPAIR_MINUTES / Modifiers.scale(modifiers, &"repair_speed")
	mend.doing = "Mending the %s" % placed.def.display_name.to_lower()
	mend.finish = func(_stage: Job.Stage, worker: Person) -> void:
		fix(key)
		if skilled.is_valid() and skilled.call(worker):
			uses[key] = -roundi(placed.def.uses_before_breaking * SKILLED_MEND)
	job.stages = [mend]
	_repairs[key] = jobs.post(job)
	broke.emit(key)


## Mends an object: as good as new.
func fix(key: Vector2i) -> void:
	uses.erase(key)
	_repairs.erase(key)
	if not people.broken.erase(key):
		return
	if _markers.has(key):
		_markers[key].queue_free()
		_markers.erase(key)
	mended.emit(key)


## What's broken, in words, for the jobs panel.
func warnings() -> Array[String]:
	var out: Array[String] = []
	if people.broken.is_empty():
		return out
	var names := PackedStringArray()
	for key: Vector2i in people.broken:
		var placed := building.object_at(key)
		if placed != null:
			names.append(placed.def.display_name.to_lower())
	out.append("Broken: %s" % ", ".join(names))
	return out


func _on_job_finished(job: Job, _worker: Person) -> void:
	if job.kind == &"repair":
		return
	for stage in job.stages:
		if stage.do == Job.Do.WORK and stage.object != -1:
			use(Vector2i(stage.level, stage.object))


## Forgets objects that have gone.
func _tidy() -> void:
	for key: Vector2i in uses.keys():
		if building.object_at(key) == null:
			uses.erase(key)
	for key: Vector2i in people.broken.keys():
		if building.object_at(key) == null:
			people.broken.erase(key)
			if _markers.has(key):
				_markers[key].queue_free()
				_markers.erase(key)
			if _repairs.has(key):
				jobs.cancel(_repairs[key])
				_repairs.erase(key)


## An object's (level, object id), or (0, -1) if it isn't in the building.
func _key_of(placed: BuildingMap.PlacedObject) -> Vector2i:
	for n: int in building.levels:
		if building.levels[n].objects.get(placed.id) == placed:
			return Vector2i(n, placed.id)
	return Vector2i(0, -1)
