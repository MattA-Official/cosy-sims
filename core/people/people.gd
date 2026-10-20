class_name People
extends Node3D
## Everyone walking about, and what they decide to do. Each person's needs
## run down over game time, and each follows the timetable block they are
## in (see ActivityDef): first they get to where the block wants them,
## then they use the block's own object (a table in Eat), then they see to
## any pressing need the block allows, and otherwise they wander about
## where they are allowed. With no block they are free. The walking graph
## is rebuilt whenever the build or the paths change, and once the ground
## has stopped changing for a moment (rebuilding on every frame of
## sculpting made the brush lag).
##
## Time is in game minutes. With a GameClock set, people move as the clock
## does; without one, a real second counts as a game minute.

signal person_added(person: Person)
signal person_removed(person: Person)
## A door was locked or unlocked.
signal doors_changed

## Needs below this send people off to see to them.
const NEED_LINE := 40.0
## Game minutes before trying again for something that couldn't be found
## or reached.
const RETRY_MINUTES := 8.0
## How long people use an object that sees to no need, such as a bench.
const USE_MINUTES := 20.0
## Seconds the ground must stay still before the walking graph catches up.
const GROUND_SETTLE_SECONDS := 0.5
const FIRST_NAMES: Array[String] = ["Alfie", "Bea", "Cass", "Dot", "Eli", "Fen", "Gus", "Hattie",
		"Ivo", "Jude", "Kit", "Lou", "Mo", "Nell", "Ozzy", "Pip", "Quin", "Rory", "Sid", "Tess",
		"Uma", "Vic", "Wren", "Zak"]
const SURNAMES: Array[String] = ["Abbott", "Blythe", "Crumb", "Dimble", "Ellery", "Fitch", "Goodbody",
		"Hobbs", "Inchley", "Jolly", "Kettle", "Lark", "Muddle", "Nutt", "Oddie", "Puddick",
		"Quill", "Rumbold", "Scrope", "Tuttle"]

@export var terrain: Terrain
## Walking speed in tiles a game minute (at 1×, a real second).
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
@export var flag_colour := Color(1.0, 0.72, 0.2)

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
## Moves everyone on as it ticks. Without one, people move in real time.
var clock: GameClock:
	set(value):
		clock = value
		if clock != null:
			clock.advanced.connect(func(minutes: float) -> void:
				if not paused:
					step(minutes))
var needs: Array[NeedDef] = []
## Room types, for naming where people are heading.
var room_types: Array[RoomTypeDef] = []
## Room types a bed makes someone's own, such as a cell. Beds elsewhere
## (an infirmary, say) belong to nobody.
var home_room_types: Array[StringName] = []
## Object tags that belong to one person each: they use their own, and
## nobody else's.
var owned_tags: Array[StringName] = [&"bed"]
var people: Array[Person] = []
var graph: NavGraph
## Stops everyone, for looking at things in the inspector.
var paused := false
## Locked doors, as (level, edge x, edge y, edge axis).
var locked_doors: Dictionary[Vector4i, bool] = {}

var _dirty := true
## Whether the ground under the building has changed too (terrain, water or
## paths), rather than only the building.
var _ground_dirty := true
## Seconds until the ground has settled after sculpting, or below 0 when
## it has nothing waiting.
var _ground_wait := -1.0
var _beds_dirty := true
var _next_id := 1
var _rng := RandomNumberGenerator.new()
## (level, object id): the person using or heading for it.
var _claimed: Dictionary[Vector2i, Person] = {}
## (level, object id): whose bed it is.
var _bed_owners: Dictionary[Vector2i, Person] = {}
var _bodies: Dictionary[Person, Node3D] = {}
var _materials: Dictionary[Color, StandardMaterial3D] = {}
## Rooms of the types each block sends people to, worked out once a step.
var _rooms_for: Dictionary[ActivityDef, Array] = {}


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
	if clock == null and not paused:
		step(delta)
	_update_bodies()


func mark_dirty() -> void:
	_dirty = true
	_beds_dirty = true
	_rooms_for.clear()


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
		for key: Vector4i in locked_doors:
			graph.set_door_locked(key.x, Vector3i(key.y, key.z, key.w), true)
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
	_beds_dirty = true
	person_added.emit(person)
	return person


func remove_person(person: Person) -> void:
	_release(person)
	_bed_owners.erase(person.bed)
	people.erase(person)
	if _bodies.has(person):
		_bodies[person].queue_free()
		_bodies.erase(person)
	_beds_dirty = true
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


## Moves everyone on by some game minutes.
func step(minutes: float) -> void:
	nav()
	_rooms_for.clear()
	if _beds_dirty:
		assign_beds()
	for person in people.duplicate():
		_think(person, minutes)


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


## Whose bed an object is, or null.
func owner_of(level: int, object_id: int) -> Person:
	return _bed_owners.get(Vector2i(level, object_id))


#region Timetable

## Puts someone in a timetable block. Whatever they were doing stops,
## unless the new block still allows it where they are (asleep in their
## cell from Lockup into Sleep, say).
func set_block(person: Person, def: ActivityDef) -> void:
	if person.block == def:
		return
	person.block = def
	person.done_main = false
	person.gave_up.clear()
	person.place_wait = 0.0
	person.out_of_place = false
	if person.state == Person.State.USING and _still_allowed(person):
		return
	_stop(person)
	person.timer = 0.0


## Whether someone is where their block wants them. Without a bed of
## their own, a block that wants them in it can't be met.
func is_in_place(person: Person) -> bool:
	var block := person.block
	if block == null or not block.has_place() or (block.free_after and person.done_main):
		return true
	var here := room_of(person)
	if here.is_empty():
		return false
	for pair: Array in place_rooms(person):
		if pair[0] == here[0] and pair[1] == here[1]:
			return true
	return false


## The rooms someone's block wants them in, as [level, Room] pairs. Empty
## when the block lets them go anywhere, or there are none. Don't change
## the array: it may be shared.
func place_rooms(person: Person) -> Array:
	var out: Array = []
	var block := person.block
	if block == null or not block.has_place():
		return out
	if block.place == ActivityDef.Place.OWN_ROOM:
		var home := home_room(person)
		if not home.is_empty():
			out.append(home)
		return out
	if not _rooms_for.has(block):
		for n: int in building.levels:
			for room: Room in building.levels[n].rooms():
				if block.room_types.has(room.type):
					out.append([n, room])
		_rooms_for[block] = out
	return _rooms_for[block]


## The room someone is in, as [level, Room], or [] if they are not in one.
func room_of(person: Person) -> Array:
	var map := building.levels.get(person.level) as BuildingMap
	var room := map.room_at_point(person.flat()) if map != null else null
	return [person.level, room] if room != null else []


## The room someone's bed is in, as [level, Room], or [] if they have none.
func home_room(person: Person) -> Array:
	if not person.has_bed():
		return []
	var map := building.levels.get(person.bed.x) as BuildingMap
	var placed: BuildingMap.PlacedObject = map.objects.get(person.bed.y) if map != null else null
	var room := map.room_at_point(placed.centre) if placed != null else null
	return [person.bed.x, room] if room != null else []


## Who sleeps in a room, by their beds in it.
func owners_in(level: int, room: Room) -> Array[Person]:
	var out: Array[Person] = []
	var map := building.levels.get(level) as BuildingMap
	for placed in map.objects_in_room(room):
		var owner := owner_of(level, placed.id)
		if owner != null:
			out.append(owner)
	return out


## Gives everyone without a bed the nearest free one in a home room (a
## cell), and takes back beds that have gone or are no longer in one.
func assign_beds() -> void:
	_beds_dirty = false
	var free: Array = [] # [level, PlacedObject]
	var valid: Dictionary[Vector2i, bool] = {}
	for n: int in building.levels:
		var map := building.levels[n]
		for placed: BuildingMap.PlacedObject in map.objects.values():
			if not _is_owned_tag_object(placed):
				continue
			var room := map.room_at_point(placed.centre)
			if room != null and home_room_types.has(room.type):
				valid[Vector2i(n, placed.id)] = true
	for key: Vector2i in _bed_owners.keys():
		var owner := _bed_owners[key]
		if not valid.has(key) or owner.bed != key or not people.has(owner):
			_bed_owners.erase(key)
			if owner.bed == key:
				owner.bed = Person.NO_BED
	for key: Vector2i in valid:
		if not _bed_owners.has(key):
			free.append(key)
	for person in people:
		if person.has_bed() or free.is_empty():
			continue
		var best := 0
		var best_score := INF
		for i in free.size():
			var key: Vector2i = free[i]
			var placed: BuildingMap.PlacedObject = building.levels[key.x].objects[key.y]
			var score := placed.centre.distance_to(person.flat()) + absi(key.x - person.level) * 12.0
			if score < best_score:
				best = i
				best_score = score
		person.bed = free[best]
		_bed_owners[person.bed] = person
		free.remove_at(best)


## Locks or unlocks a door on a straight wall, for everyone.
func set_door_locked(level: int, edge: Vector3i, locked: bool) -> void:
	var key := Vector4i(level, edge.x, edge.y, edge.z)
	if locked_doors.has(key) == locked:
		return
	if locked:
		locked_doors[key] = true
	else:
		locked_doors.erase(key)
	if graph != null and not _dirty:
		graph.set_door_locked(level, edge, locked)
	doors_changed.emit()


func is_door_locked(level: int, edge: Vector3i) -> bool:
	return locked_doors.has(Vector4i(level, edge.x, edge.y, edge.z))

#endregion


func _think(person: Person, minutes: float) -> void:
	_run_down_needs(person, minutes)
	for tag: StringName in person.gave_up.keys():
		person.gave_up[tag] -= minutes
		if person.gave_up[tag] <= 0.0:
			person.gave_up.erase(tag)
	person.place_wait -= minutes
	if person.has_target() and target_object(person) == null:
		_stop(person) # The object went while they were on their way.
	match person.state:
		Person.State.WALKING:
			if person.wandering and _has_errand(person):
				_stop(person)
				_decide(person, false)
			else:
				_walk(person, minutes)
		Person.State.USING:
			person.timer -= minutes
			if _done_using(person):
				_finish_using(person)
		Person.State.IDLE:
			person.timer -= minutes
			if _has_errand(person) or person.timer <= 0.0:
				_decide(person, person.timer <= 0.0)


## Needs run down, at the asleep rate while sleeping, except the one being
## seen to, which fills.
func _run_down_needs(person: Person, minutes: float) -> void:
	var using := person.state == Person.State.USING
	var seeing_to := need_def(person.target_need) if using else null
	var asleep := seeing_to != null and seeing_to.sleeping
	for need: StringName in person.needs:
		var def := need_def(need)
		if def == null:
			continue
		if def == seeing_to:
			person.needs[need] = minf(100.0, person.needs[need] + 100.0 / maxf(def.use_minutes, 0.1) * minutes)
		else:
			var rate := def.asleep_decay_per_hour if asleep else def.decay_per_hour
			person.needs[need] = maxf(0.0, person.needs[need] - rate / 60.0 * minutes)


## Something to do other than wander: getting to where the block wants
## them, its own object, or a pressing need it allows.
func _has_errand(person: Person) -> bool:
	if person.place_wait <= 0.0 and not is_in_place(person) and not place_rooms(person).is_empty():
		return true
	return _main_tag(person) != &"" or _pressing_need(person) != &""


## Works out what someone does next, in the order the class comment gives.
func _decide(person: Person, may_wander: bool) -> void:
	var block := person.block
	if not is_in_place(person):
		if person.place_wait <= 0.0 and _go_to_place(person):
			return
		person.place_wait = maxf(person.place_wait, RETRY_MINUTES)
	var main := _main_tag(person)
	if main != &"" and _seek(person, main):
		return
	var need := _pressing_need(person)
	if need != &"" and _seek(person, need_def(need).object_tag, need):
		return
	if may_wander:
		_wander(person)
	elif block != null and not is_in_place(person) and person.state == Person.State.IDLE:
		person.activity = _why_not_in_place(person)


## The block's own object, if it is still to be used.
func _main_tag(person: Person) -> StringName:
	var block := person.block
	if block == null or block.main_tag == &"" or person.done_main or person.gave_up.has(block.main_tag):
		return &""
	return block.main_tag


## The lowest need below the line whose objects the block allows, or &"".
func _pressing_need(person: Person) -> StringName:
	var best: StringName = &""
	for need: StringName in person.needs:
		var def := need_def(need)
		if def == null or person.needs[need] >= NEED_LINE or person.gave_up.has(def.object_tag):
			continue
		if person.block != null and not person.block.allows(def.object_tag):
			continue
		if best == &"" or person.needs[need] < person.needs[best]:
			best = need
	return best


## Heads for the nearest of the rooms the block wants them in.
func _go_to_place(person: Person) -> bool:
	var rooms := place_rooms(person).duplicate()
	if rooms.is_empty():
		return false
	rooms.sort_custom(func(a: Array, b: Array) -> bool:
		return _room_score(person, a) < _room_score(person, b))
	for pair: Array in rooms.slice(0, 3):
		for attempt in 6:
			var spot: Variant = _spot_in_room(pair[0], pair[1])
			if spot != null and _walk_to(person, pair[0], spot):
				person.activity = "Heading to %s" % _place_name(person, pair[1])
				return true
	person.place_wait = RETRY_MINUTES
	return false


func _room_score(person: Person, pair: Array) -> float:
	var room: Room = pair[1]
	return room.centre().distance_to(person.flat()) + absi(int(pair[0]) - person.level) * 12.0


## "their cell", "the canteen"
func _place_name(person: Person, room: Room) -> String:
	var type_name := "room"
	for def in room_types:
		if def.id == room.type:
			type_name = def.display_name.to_lower()
	if person.block != null and person.block.place == ActivityDef.Place.OWN_ROOM:
		return "their %s" % type_name
	return "the %s" % type_name


## Why someone isn't where their block wants them, in words.
func _why_not_in_place(person: Person) -> String:
	var block := person.block
	if block.place == ActivityDef.Place.OWN_ROOM and home_room(person).is_empty():
		return "Has no bed of their own"
	if place_rooms(person).is_empty():
		return "There's nowhere to go for %s" % block.display_name
	return "Can't get to where %s should be" % block.display_name


## Whether a room is somebody else's own, such as another prisoner's
## cell, which people keep out of.
func _someone_elses(person: Person, level: int, room: Room) -> bool:
	if not home_room_types.has(room.type):
		return false
	var home := home_room(person)
	return home.is_empty() or home[0] != level or home[1] != room


## A random spot people can stand on in a room, or null if none turned up.
func _spot_in_room(level: int, room: Room) -> Variant:
	for attempt in 8:
		var cell: Vector2i = room.cells[_rng.randi() % room.cells.size()]
		var spot := Vector2(cell) + Vector2(_rng.randf_range(0.3, 0.7), _rng.randf_range(0.3, 0.7))
		var map := building.levels[level]
		if nav().point_at(level, spot) != -1 and map.room_at_point(spot) == room:
			return spot
	return null


## Whether someone may go on using the object they are on.
func _still_allowed(person: Person) -> bool:
	var block := person.block
	if block == null:
		return true
	if not block.allows(person.target_tag) or not is_in_place(person):
		return false
	return person.target_tag != &"" and (person.target_need != &"" or person.target_tag == block.main_tag)


## Heads for the nearest free object with a tag, where the block allows.
## Returns false, and gives up on the tag for a while, if none can be
## reached.
func _seek(person: Person, tag: StringName, need: StringName = &"") -> bool:
	if need == &"":
		need = _need_for_tag(tag)
	var restricted := _restricted(person)
	var allowed_rooms := place_rooms(person) if restricted else []
	var candidates: Array = [] # [score, level, object]
	for n: int in building.levels:
		var map := building.levels[n]
		for placed: BuildingMap.PlacedObject in map.objects.values():
			if not tag in placed.def.tags or _claimed.has(Vector2i(n, placed.id)):
				continue
			if not _may_use(person, n, placed):
				continue
			if restricted and not _room_listed(allowed_rooms, n, map.room_at_point(placed.centre)):
				continue
			var score := placed.centre.distance_to(person.flat()) + absi(n - person.level) * 12.0
			candidates.append([score, n, placed])
	candidates.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	for entry: Array in candidates.slice(0, 5):
		var n: int = entry[1]
		var placed: BuildingMap.PlacedObject = entry[2]
		for spot in _spots_beside(n, placed, person.flat()):
			if _walk_to(person, n, spot):
				person.target = Vector2i(n, placed.id)
				person.target_tag = tag
				person.target_need = need
				_claimed[person.target] = person
				var def := need_def(need)
				person.activity = "Going to a %s" % placed.def.display_name.to_lower() \
						+ (" for %s" % def.display_name.to_lower() if def != null else "")
				return true
	person.gave_up[tag] = RETRY_MINUTES
	person.activity = ("Can't find a free %s" if candidates.is_empty() else "Can't reach a %s") % tag
	person.timer = 2.0
	return false


## Whether someone's block keeps them to certain rooms just now. Not once
## they're free after the block's own object, nor when it wants them in a
## room of their own and they have none.
func _restricted(person: Person) -> bool:
	var block := person.block
	if block == null or not block.has_place() or (block.free_after and person.done_main):
		return false
	return block.place != ActivityDef.Place.OWN_ROOM or person.has_bed()


func _room_listed(rooms: Array, level: int, room: Room) -> bool:
	for pair: Array in rooms:
		if pair[0] == level and pair[1] == room:
			return true
	return false


## Owned objects (beds) are for their owner only; people without one may
## use any nobody owns.
func _may_use(person: Person, level: int, placed: BuildingMap.PlacedObject) -> bool:
	if not _is_owned_tag_object(placed):
		return true
	var key := Vector2i(level, placed.id)
	return person.bed == key if person.has_bed() else not _bed_owners.has(key)


func _is_owned_tag_object(placed: BuildingMap.PlacedObject) -> bool:
	for tag in placed.def.tags:
		if owned_tags.has(tag):
			return true
	return false


func _need_for_tag(tag: StringName) -> StringName:
	for def in needs:
		if def.object_tag == tag:
			return def.id
	return &""


func _wander(person: Person) -> void:
	var spot: Variant = null
	var here := room_of(person)
	if _restricted(person) and is_in_place(person) and not here.is_empty():
		spot = _spot_in_room(here[0], here[1])
	elif not here.is_empty():
		# Indoors or in the yard, they keep to rooms rather than drifting off
		# across the land; access zones will say where they may go.
		for attempt in 4:
			var near: Variant = nav().random_spot(person.level, person.flat(), 6.0, _rng)
			var room := building.levels[person.level].room_at_point(near) if near != null else null
			if room != null and not _someone_elses(person, person.level, room):
				spot = near
				break
	else:
		spot = nav().random_spot(person.level, person.flat(), 6.0, _rng)
	if spot != null and _walk_to(person, person.level, spot):
		person.activity = "Pottering about" if _restricted(person) else "Wandering"
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


func _walk(person: Person, minutes: float) -> void:
	var budget := speed * minutes
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
	person.timer = USE_MINUTES
	var map := building.levels[person.target.x]
	person.position = Vector3(placed.centre.x, map.floor_height(Vector2i(placed.centre.floor()))
			+ placed.def.height * 0.6, placed.centre.y)
	var def := need_def(person.target_need)
	person.activity = def.doing if def != null else "Using the %s" % placed.def.display_name.to_lower()


## Done once the need is met, or the time is up for objects that meet
## none. The block's own object keeps them until the block ends if it says
## so (in bed until morning).
func _done_using(person: Person) -> bool:
	var block := person.block
	if block != null and block.stay_on_main and person.target_tag == block.main_tag:
		return false
	if person.target_need != &"":
		return person.needs.get(person.target_need, 100.0) >= 99.9
	return person.timer <= 0.0


func _finish_using(person: Person) -> void:
	if person.block != null and person.target_tag == person.block.main_tag:
		person.done_main = true
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
	person.wandering = false
	person.activity = "Standing about"


func _release(person: Person) -> void:
	if person.has_target() and _claimed.get(person.target) == person:
		_claimed.erase(person.target)
	person.target_tag = &""
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
		var walking := person.state == Person.State.WALKING and not paused \
				and (clock == null or not clock.paused())
		var step := Time.get_ticks_msec() * 0.001 * speed * 7.0 + person.id
		body.position.y += absf(sin(step)) * 0.035 if walking else 0.0
		body.rotation.z = sin(step) * 0.07 if walking else 0.0
		if not person.route.is_empty():
			var ahead := Vector2(person.route[0].x, person.route[0].z) - person.flat()
			if ahead.length() > 0.01:
				body.rotation.y = atan2(-ahead.x, -ahead.y)
		body.get_node("Flag").visible = person.out_of_place
	_update_visibility()


## People above the level being looked at are hidden, like the floors.
func _update_visibility() -> void:
	var active := building.active if building != null else 0
	for person: Person in _bodies:
		_bodies[person].visible = person.level <= active


## A little person about 0.9 m tall: the body model with this person's
## colours, or a placeholder rounded body and head, with a flag over them
## for being out of place.
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
		_add_flag(model)
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
	_add_flag(root)
	return root


## A "?" over someone's head, shown while they are out of place.
func _add_flag(root: Node3D) -> void:
	var flag := Label3D.new()
	flag.name = "Flag"
	flag.text = "?"
	flag.font_size = 72
	flag.outline_size = 18
	flag.pixel_size = 0.006
	flag.modulate = flag_colour
	flag.outline_modulate = Color(0.25, 0.18, 0.1)
	flag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	flag.no_depth_test = true
	flag.position.y = 1.15
	flag.visible = false
	root.add_child(flag)


## Shared between everyone of the same colour.
func _flat_material(colour: Color) -> StandardMaterial3D:
	if not _materials.has(colour):
		var material := StandardMaterial3D.new()
		material.albedo_color = colour
		material.roughness = 0.8
		_materials[colour] = material
	return _materials[colour]
