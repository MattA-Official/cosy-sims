class_name People
extends Node3D
## Everyone walking about, and what they decide to do. Each person's needs
## run down over time; once one drops below the line they walk to the
## nearest free object that sees to it, use it, and carry on. With nothing
## pressing they wander. The walking graph is rebuilt whenever the build or
## the paths change, and once the ground has stopped changing for a moment
## (rebuilding on every frame of sculpting made the brush lag).

signal person_added(person: Person)
signal person_removed(person: Person)

## Needs below this send people off to see to them.
const NEED_LINE := 40.0
## Seconds before trying again for a need nothing could be found for.
const RETRY_SECONDS := 8.0
## Seconds the ground must stay still before the walking graph catches up.
const GROUND_SETTLE_SECONDS := 0.5
const FIRST_NAMES: Array[String] = ["Alfie", "Bea", "Cass", "Dot", "Eli", "Fen", "Gus", "Hattie",
		"Ivo", "Jude", "Kit", "Lou", "Mo", "Nell", "Ozzy", "Pip", "Quin", "Rory", "Sid", "Tess",
		"Uma", "Vic", "Wren", "Zak"]
const SURNAMES: Array[String] = ["Abbott", "Blythe", "Crumb", "Dimble", "Ellery", "Fitch", "Goodbody",
		"Hobbs", "Inchley", "Jolly", "Kettle", "Lark", "Muddle", "Nutt", "Oddie", "Puddick",
		"Quill", "Rumbold", "Scrope", "Tuttle"]

@export var terrain: Terrain
## Walking speed in tiles a second.
@export var speed := 1.4
@export var body_colour := Color(0.95, 0.55, 0.2)
@export var head_colour := Color(0.96, 0.82, 0.68)
## Optional model for everyone, feet at the origin, facing -z. Meshes named
## outfit, skin and hair are tinted: the outfit `body_colour`, skin and
## hair picked for each person from the lists below.
@export var body_model: PackedScene
@export var skin_tones: Array[Color] = [Color(0.98, 0.84, 0.72), Color(0.93, 0.76, 0.6),
		Color(0.82, 0.62, 0.45), Color(0.66, 0.46, 0.32), Color(0.48, 0.33, 0.24)]
@export var hair_colours: Array[Color] = [Color(0.25, 0.18, 0.14), Color(0.45, 0.3, 0.2),
		Color(0.72, 0.52, 0.3), Color(0.9, 0.78, 0.5), Color(0.6, 0.3, 0.18), Color(0.7, 0.7, 0.68),
		Color(0.16, 0.15, 0.15)]

var building: Building:
	set(value):
		building = value
		if building != null:
			building.changed.connect(mark_dirty)
			building.active_changed.connect(func(_level: int) -> void: _update_visibility())
		mark_dirty()
var paths: PathNetwork:
	set(value):
		paths = value
		if paths != null:
			paths.changed.connect(mark_ground_dirty)
		mark_ground_dirty()
var needs: Array[NeedDef] = []
var people: Array[Person] = []
var graph: NavGraph
## Stops everyone, for looking at things in the inspector.
var paused := false

var _dirty := true
## Whether the ground under the building has changed too (terrain, water or
## paths), rather than only the building.
var _ground_dirty := true
## Seconds until the ground has settled after sculpting, or below 0 when
## it has nothing waiting.
var _ground_wait := -1.0
var _next_id := 1
var _rng := RandomNumberGenerator.new()
## (level, object id): the person using or heading for it.
var _claimed: Dictionary[Vector2i, Person] = {}
var _bodies: Dictionary[Person, Node3D] = {}
var _materials: Dictionary[Color, StandardMaterial3D] = {}


func _ready() -> void:
	if terrain != null:
		terrain.changed.connect(_on_ground_changed)
		if terrain.water != null:
			terrain.water.changed.connect(mark_ground_dirty)


func _process(delta: float) -> void:
	if _ground_wait >= 0.0:
		_ground_wait -= delta
		if _ground_wait < 0.0:
			mark_ground_dirty()
	if not paused:
		step(delta)
	_update_bodies()


func mark_dirty() -> void:
	_dirty = true


## Like mark_dirty, for changes to the ground itself, which cost more to
## take in.
func mark_ground_dirty() -> void:
	_dirty = true
	_ground_dirty = true


## People keep the old graph while the ground is being sculpted, and get a
## new one once it settles.
func _on_ground_changed() -> void:
	_ground_wait = GROUND_SETTLE_SECONDS
	# Building flattens the ground under it, so the next rebuild, even one
	# for the building, must not reuse the old ground.
	_ground_dirty = true


## The walking graph, rebuilt first if anything has changed.
func nav() -> NavGraph:
	if _dirty or graph == null:
		_dirty = false
		var ground := graph.ground_layer if graph != null and not _ground_dirty else null
		_ground_dirty = false
		graph = NavGraph.build(building, paths, terrain, ground)
	return graph


## Adds someone standing at a spot on a level. Returns null if nobody can
## stand there.
func add_person(level: int, spot: Vector2, person_name := "") -> Person:
	var height := nav().height_at(level, spot)
	if is_nan(height):
		return null
	var person := Person.new()
	person.id = _next_id
	_next_id += 1
	person.name = person_name if not person_name.is_empty() else "%s %s" % [
			FIRST_NAMES[_rng.randi() % FIRST_NAMES.size()], SURNAMES[_rng.randi() % SURNAMES.size()]]
	person.level = level
	person.position = Vector3(spot.x, height, spot.y)
	for def in needs:
		person.needs[def.id] = _rng.randf_range(55.0, 100.0)
	people.append(person)
	person_added.emit(person)
	return person


func remove_person(person: Person) -> void:
	_release(person)
	people.erase(person)
	if _bodies.has(person):
		_bodies[person].queue_free()
		_bodies.erase(person)
	person_removed.emit(person)


## Sends someone to a spot, dropping whatever they were doing. Returns
## false if they cannot get there.
func send(person: Person, level: int, spot: Vector2) -> bool:
	_stop(person)
	if not _walk_to(person, level, spot):
		person.activity = "Can't get there"
		return false
	person.activity = "Walking where you sent them"
	person.timer = 4.0
	return true


## Moves everyone on by `delta` seconds.
func step(delta: float) -> void:
	nav()
	for person in people.duplicate():
		_think(person, delta)


func need_def(id: StringName) -> NeedDef:
	for def in needs:
		if def.id == id:
			return def
	return null


## The object someone is heading for or using, or null.
func target_object(person: Person) -> BuildingMap.PlacedObject:
	if not person.has_target():
		return null
	var map := building.levels.get(person.target.x) as BuildingMap
	return map.objects.get(person.target.y) if map != null else null


## Who is using or heading for an object, or null.
func user_of(level: int, object_id: int) -> Person:
	return _claimed.get(Vector2i(level, object_id))


func _think(person: Person, delta: float) -> void:
	# Needs run down, except the one being seen to.
	for need: StringName in person.needs:
		var def := need_def(need)
		if def == null:
			continue
		if person.state == Person.State.USING and person.target_need == need:
			person.needs[need] = minf(100.0, person.needs[need] + 100.0 / maxf(def.use_seconds, 0.1) * delta)
		else:
			person.needs[need] = maxf(0.0, person.needs[need] - def.decay * delta)
	for need: StringName in person.gave_up.keys():
		person.gave_up[need] -= delta
		if person.gave_up[need] <= 0.0:
			person.gave_up.erase(need)
	if person.has_target() and target_object(person) == null:
		_stop(person) # The object went while they were on their way.
	match person.state:
		Person.State.WALKING:
			var need := person.most_pressing(NEED_LINE) if person.wandering else &""
			if need != &"":
				_stop(person)
				_seek(person, need)
			else:
				_walk(person, delta)
		Person.State.USING:
			if person.needs[person.target_need] >= 99.9:
				_finish_using(person)
		Person.State.IDLE:
			person.timer -= delta
			var need := person.most_pressing(NEED_LINE)
			if need != &"":
				_seek(person, need)
			elif person.timer <= 0.0:
				_wander(person)


## Heads for the nearest free object that sees to a need.
func _seek(person: Person, need: StringName) -> void:
	var def := need_def(need)
	var candidates: Array = [] # [score, level, object]
	for n: int in building.levels:
		for placed: BuildingMap.PlacedObject in building.levels[n].objects.values():
			if def.object_tag in placed.def.tags and not _claimed.has(Vector2i(n, placed.id)):
				var score := placed.centre.distance_to(person.flat()) + absi(n - person.level) * 12.0
				candidates.append([score, n, placed])
	candidates.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	for entry: Array in candidates.slice(0, 5):
		var n: int = entry[1]
		var placed: BuildingMap.PlacedObject = entry[2]
		for spot in _spots_beside(n, placed, person.flat()):
			if _walk_to(person, n, spot):
				person.target = Vector2i(n, placed.id)
				person.target_need = need
				_claimed[person.target] = person
				person.activity = "Going to a %s for %s" % [placed.def.display_name.to_lower(),
						def.display_name.to_lower()]
				return
	person.gave_up[need] = RETRY_SECONDS
	person.activity = ("Can't find a free %s" if candidates.is_empty() else "Can't reach a %s") \
			% def.object_tag
	person.timer = 2.0


func _wander(person: Person) -> void:
	var spot: Variant = nav().random_spot(person.level, person.flat(), 6.0, _rng)
	if spot != null and _walk_to(person, person.level, spot):
		person.activity = "Wandering"
		person.wandering = true
	person.timer = _rng.randf_range(2.0, 6.0)


## Tiles beside an object people could stand on to use it, nearest to
## `from` first. In a walled room they must be inside it, not on the far
## side of a wall.
func _spots_beside(level: int, placed: BuildingMap.PlacedObject, from: Vector2) -> Array[Vector2]:
	var out: Array[Vector2] = []
	var map := building.levels.get(level) as BuildingMap
	var room := map.room_at_point(placed.centre) if map != null else null
	for cell in BuildingMap.cells_under(placed.rect.grow(0.8)):
		var spot := Vector2(cell) + Vector2(0.5, 0.5)
		if placed.rect.grow(-0.05).has_point(spot) or nav().point_at(level, spot) == -1:
			continue
		if room != null and room.enclosed and map.room_at_point(spot) != room:
			continue
		out.append(spot)
	out.sort_custom(func(a: Vector2, b: Vector2) -> bool:
		return a.distance_to(placed.centre) + a.distance_to(from) * 0.1 \
				< b.distance_to(placed.centre) + b.distance_to(from) * 0.1)
	return out.slice(0, 4)


func _walk_to(person: Person, level: int, spot: Vector2) -> bool:
	var levels: Array[int] = []
	var surface: Array[bool] = []
	var route := nav().find_path(person.level, person.flat(), level, spot, levels, surface)
	if route.is_empty():
		return false
	person.wandering = false
	person.route = route
	person.route_levels = levels
	person.route_on_surface = surface
	person.state = Person.State.WALKING
	return true


func _walk(person: Person, delta: float) -> void:
	var budget := speed * delta
	while budget > 0.0 and not person.route.is_empty():
		var next := person.route[0]
		var here := person.flat()
		var there := Vector2(next.x, next.z)
		var gap := here.distance_to(there)
		if gap <= budget:
			budget -= gap
			person.position = next
			person.level = person.route_levels[0]
			person.route.pop_front()
			person.route_levels.pop_front()
			person.route_on_surface.pop_front()
			continue
		var moved := here.move_toward(there, budget)
		budget = 0.0
		# On floor or ground, stand on it; on stairs and bridges, climb
		# steadily from one point to the next.
		var height := NAN
		if not person.route_on_surface.is_empty() and person.route_on_surface[0] \
				and person.route_levels[0] == person.level:
			height = nav().height_at(person.level, moved)
		if is_nan(height):
			height = lerpf(person.position.y, next.y, 1.0 - moved.distance_to(there) / maxf(gap, 0.001))
		person.position = Vector3(moved.x, height, moved.y)
	if person.route.is_empty():
		_arrive(person)


func _arrive(person: Person) -> void:
	var placed := target_object(person)
	if placed == null:
		person.state = Person.State.IDLE
		person.activity = "Standing about"
		return
	person.stand_spot = person.position
	person.state = Person.State.USING
	var map := building.levels[person.target.x]
	person.position = Vector3(placed.centre.x, map.floor_height(Vector2i(placed.centre.floor()))
			+ placed.def.height * 0.6, placed.centre.y)
	var def := need_def(person.target_need)
	person.activity = def.doing if def != null else "Busy"


func _finish_using(person: Person) -> void:
	person.position = person.stand_spot
	_release(person)
	person.state = Person.State.IDLE
	person.activity = "Standing about"
	person.timer = 1.0


## Drops whatever someone was doing, stepping off any object they were on.
func _stop(person: Person) -> void:
	if person.state == Person.State.USING:
		person.position = person.stand_spot
	_release(person)
	person.route.clear()
	person.route_levels.clear()
	person.route_on_surface.clear()
	person.state = Person.State.IDLE
	person.activity = "Standing about"


func _release(person: Person) -> void:
	if person.has_target() and _claimed.get(person.target) == person:
		_claimed.erase(person.target)
	person.target_need = &""


func _update_bodies() -> void:
	var cs := terrain.cell_size if terrain != null else 1.0
	for person in people:
		var body: Node3D = _bodies.get(person)
		if body == null:
			body = _make_body(person)
			_bodies[person] = body
			add_child(body)
		body.position = Vector3(person.position.x * cs, person.position.y, person.position.z * cs)
		# A little waddle while walking.
		var walking := person.state == Person.State.WALKING and not paused
		var step := Time.get_ticks_msec() * 0.001 * speed * 7.0 + person.id
		body.position.y += absf(sin(step)) * 0.035 if walking else 0.0
		body.rotation.z = sin(step) * 0.07 if walking else 0.0
		if not person.route.is_empty():
			var ahead := Vector2(person.route[0].x, person.route[0].z) - person.flat()
			if ahead.length() > 0.01:
				body.rotation.y = atan2(-ahead.x, -ahead.y)
	_update_visibility()


## People above the level being looked at are hidden, like the floors.
func _update_visibility() -> void:
	var active := building.active if building != null else 0
	for person: Person in _bodies:
		_bodies[person].visible = person.level <= active


## A little person about 0.9 m tall: the body model with this person's
## colours, or a placeholder rounded body and head.
func _make_body(person: Person) -> Node3D:
	if body_model != null:
		var model := body_model.instantiate() as Node3D
		var rng := RandomNumberGenerator.new()
		rng.seed = person.id
		var skin := skin_tones[rng.randi() % skin_tones.size()] if not skin_tones.is_empty() else head_colour
		var hair := hair_colours[rng.randi() % hair_colours.size()] if not hair_colours.is_empty() \
				else head_colour
		for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
			var part := mesh.name.get_slice("_", 0).to_lower()
			match part:
				"outfit": mesh.material_override = _flat_material(body_colour)
				"skin": mesh.material_override = _flat_material(skin)
				"hair": mesh.material_override = _flat_material(hair)
		return model
	var root := Node3D.new()
	var body := MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.17
	capsule.height = 0.62
	body.mesh = capsule
	body.position.y = 0.31
	body.material_override = _flat_material(body_colour)
	root.add_child(body)
	var head := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.15
	sphere.height = 0.3
	head.mesh = sphere
	head.position.y = 0.74
	head.material_override = _flat_material(head_colour)
	root.add_child(head)
	return root


## Shared between everyone of the same colour.
func _flat_material(colour: Color) -> StandardMaterial3D:
	if not _materials.has(colour):
		var material := StandardMaterial3D.new()
		material.albedo_color = colour
		material.roughness = 0.8
		_materials[colour] = material
	return _materials[colour]
