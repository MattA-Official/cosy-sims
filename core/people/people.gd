class_name People
extends Node3D
## Everyone walking about, and what they decide to do. Each person's needs
## run down over game time, and each follows the timetable block they are
## in (see ActivityDef). Deciding goes: a need that has nearly run out
## comes first, wherever the block wants them (if they can get out to see
## to it); then getting to where the block wants them; then the block's own
## object (a table in Eat); then the best of what the block allows, scored
## by how low each need is, what they like, and how far it is; and
## otherwise they wander about where they are allowed. With no block they
## are free. Workers (staff with a role, and prisoners on a work programme
## in a work block) take jobs from the jobs board once nothing has nearly
## run out, and leave one part way only for that.
##
## Every half game minute each person also looks around: whether they are
## outdoors and in company (which fill those needs), their moodlets, and
## their mood (see MoodModel). The walking graph is rebuilt whenever the
## build or the paths change, and once the ground has stopped changing for
## a moment (rebuilding on every frame of sculpting made the brush lag).
##
## Time is in game minutes. With a GameClock set, people move as the clock
## does; without one, a real second counts as a game minute.

signal person_added(person: Person)
signal person_removed(person: Person)
## Someone has finished using an object.
signal used(person: Person, placed: BuildingMap.PlacedObject)
## A door was locked or unlocked.
signal doors_changed
## Someone has a moodlet, by its id after their traits swap it.
signal moodlet_added(person: Person, id: StringName)

## Needs below this send people off to see to them, cutting short a
## wander.
const NEED_LINE := 40.0
## Needs below this are worth seeing to when there is nothing else to do.
const WANT_LINE := 70.0
## Needs below this come before everything, even where the block wants
## them.
const URGENT_LINE := 15.0
## Tiles within which people count as company, or a crowd.
const NEARBY := 3.0
## Game minutes between each person looking around and deciding.
const THINK_MINUTES := 0.5
## How far down someone sat on the floor sits.
const SIT_DROP := 0.2
## Game minutes between working out each person's mood.
const MOOD_MINUTES := 2.0
## Added to the distance to a choice when scoring it, in tiles, so nearby
## choices don't win by too much.
const DISTANCE_EASE := 10.0
## Scores are nudged by up to this much either way, so a crowd doesn't all
## pick the same table.
const WOBBLE := 0.1
const NO_TAGS: Array[StringName] = []
## No item to be had for an object that needs one (see _item_source).
const NONE_LEFT := Vector2i(0, -2)
## Room quality lost for each piece of litter, and at most.
const LITTER_EACH := 0.5
const LITTER_MOST := 3.0
## Game minutes before trying again for something that couldn't be found
## or reached.
const RETRY_MINUTES := 8.0
## How long people use an object that sees to no need, such as a bench.
const USE_MINUTES := 20.0
## How far beyond a surface's edge, in tiles, a chair still counts as
## beside it.
const SEAT_REACH := 0.75
## Workers with `tired_need` below this work at this pace.
const TIRED_LINE := 30.0
const TIRED_PACE := 0.6
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
## A face for each MoodModel.Face, shown over people who are fed up or
## angry.
@export var face_textures: Array[Texture2D] = [
	preload("res://core/ui/faces/beaming.svg"), preload("res://core/ui/faces/content.svg"),
	preload("res://core/ui/faces/fed_up.svg"), preload("res://core/ui/faces/angry.svg"),
]

## Bonuses, such as good moodlets lasting longer. Optional.
var modifiers: Modifiers
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
## The traits people can have; everyone gets two that aren't opposites.
var traits: Array[TraitDef] = []
## Every moodlet, by id.
var moodlet_defs: Dictionary[StringName, MoodletDef] = {}
var mood_model := MoodModel.new()
## Room types, for naming where people are heading and room quality.
var room_types: Array[RoomTypeDef] = []
## Room types a bed makes someone's own, such as a cell. Beds elsewhere
## (an infirmary, say) belong to nobody.
var home_room_types: Array[StringName] = []
## Privileges people can lose, by id (see Person.restrictions).
var privileges: Dictionary[StringName, PrivilegeDef] = {}
## Every timetable block by id, for swapping one for another.
var activities: Dictionary[StringName, ActivityDef] = {}
## Object tags that belong to one person each: they use their own, and
## nobody else's.
var owned_tags: Array[StringName] = [&"bed"]
## What people sit on to use seated objects (see ObjectDef.seated).
var seat_tag: StringName = &"chair"
var people: Array[Person] = []
var graph: NavGraph
## Stops everyone, for looking at things in the inspector.
var paused := false
## Who may go where: zones, staff doors and locked doors.
var access := Access.new()
## The group whose doors someone being led (person.led) may go through,
## such as staff walking a prisoner. Empty to keep their own.
var led_group: StringName = &""
## Security categories by id, for uniform colours.
var categories: Dictionary[StringName, CategoryDef] = {}
## Objects broken and waiting to be mended, by (level, object id): nobody
## uses them.
var broken: Dictionary[Vector2i, bool] = {}
## Groups whose needs are switched off in the settings (staff, say): their
## needs stay met.
var needs_off: Array[StringName] = []
## The need that makes workers slow when it is low.
var tired_need: StringName = &"energy"
## The work to be done, for workers. Optional.
var jobs: JobBoard
## Where items are, for objects that need one in hand first, and litter.
## Optional.
var items: ItemStore:
	set(value):
		items = value
		if items != null:
			items.floor_changed.connect(func() -> void: _qualities.clear())
## What people drop as litter, one picked at random each time.
var litter: Array[ItemDef] = []
## Items with this tag lying in a room make it worse.
var litter_tag: StringName = &"litter"
## (person, may_wander) -> bool: called before someone decides what to do;
## true means it has decided for them. This is where something other than
## their needs and the timetable can take over, such as misconduct or a
## player in control.
var deciders: Array[Callable] = []

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
## How bodies look while using things (lying in bed, sitting to eat).
var poses := PersonPoses.new()
## Rooms of the types each block sends people to, by group (as zones
## keep some groups out), worked out when first wanted.
var _rooms_for: Dictionary[ActivityDef, Dictionary] = {}
## Each room's quality, worked out when first wanted after a build change.
## (person) -> float: anything else that speeds up or slows down someone's
## work, such as a prisoner's skill at it. Multiplied together.
var pace_scales: Array[Callable] = []
var _qualities: Dictionary[Room, RoomQuality] = {}
## People by (level, x, z) in squares NEARBY tiles across, for finding
## who is close, refilled when first wanted each step.
var _buckets: Dictionary[Vector3i, Array] = {}
var _buckets_fresh := false
## Who each person is chatting with, by name.
var _chatting_with: Dictionary[Person, String] = {}
## Each person's own room, as from home_room, and who sleeps in each such
## room, worked out with the beds.
var _homes: Dictionary[Person, Array] = {}
var _sleepers: Dictionary[Room, Array] = {}
var _need_defs: Dictionary[StringName, NeedDef] = {}
## Every object by tag, as [level, PlacedObject, Room or null] entries,
## worked out when first wanted after a build change.
var _by_tag: Dictionary[StringName, Array] = {}
## Objects people help themselves to items from, by item tag, as [level,
## PlacedObject, Room or null].
var _givers: Dictionary[StringName, Array] = {}
## The room each person was last found in, and where they stood then.
var _where: Dictionary[Person, Array] = {}


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


## Beds are handed out again before they're next needed, such as after
## someone moves category and may no longer sleep where they did.
func beds_changed() -> void:
	_beds_dirty = true
	_rooms_for.clear()


func mark_dirty() -> void:
	_dirty = true
	_beds_dirty = true
	_rooms_for.clear()
	_qualities.clear()
	_where.clear()
	_by_tag.clear()
	_givers.clear()
	access.changed()


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


## Can someone get to a spot from where they are, minding where they may
## go?
func can_reach(person: Person, level: int, spot: Vector2) -> bool:
	_set_up_access(person)
	return not nav().find_path(person.level, person.flat(), level, spot, [], [], person.position.y).is_empty()


## May someone be in a room? Anyone may be outside one.
func may_enter(person: Person, room: Room) -> bool:
	return access.may_enter(person.group, room, person.category)


## Walks someone to a spot for a job, saying what they're off to do.
## Returns false if they can't get there.
func walk_to(person: Person, level: int, spot: Vector2, doing: String) -> bool:
	if not _walk_to(person, level, spot):
		return false
	person.activity = doing
	return true


## How fast someone works: slower when worn out.
func work_pace(person: Person) -> float:
	var pace := TIRED_PACE if person.needs.get(tired_need, 100.0) < TIRED_LINE else 1.0
	for scale in pace_scales:
		pace *= scale.call(person)
	return pace


## Keeps someone at a job where they stand for some game minutes.
func start_working(person: Person, minutes: float, doing: String) -> void:
	person.stand_spot = person.position
	person.state = Person.State.USING
	person.timer = minutes
	person.activity = doing
	# At a desk, they pull up a chair if there's one free.
	var stage := person.job.current() if person.job != null else null
	if stage != null and stage.object != -1 and building.levels.has(stage.level):
		var placed: BuildingMap.PlacedObject = building.levels[stage.level].objects.get(stage.object)
		if placed != null and placed.def.seated:
			var chair := free_seat(stage.level, placed, person.flat())
			if chair != null:
				_take_seat(person, Vector2i(stage.level, chair.id))


## Done working where they stand, ready to move on.
func finish_working(person: Person) -> void:
	_leave_seat(person)
	person.state = Person.State.IDLE
	person.activity = "Standing about"


## Drops whatever someone was doing.
func stop(person: Person) -> void:
	_stop(person)


## Tiles beside an object to stand on to use it, nearest first.
func spots_beside(level: int, placed: BuildingMap.PlacedObject, from: Vector2) -> Array[Vector2]:
	return _spots_beside(level, placed, from)


## What someone is in the middle of, as plain data for a save: where
## they're walking, what they're using and for how long. Their job is
## saved by the JobBoard.
func doing_of(person: Person) -> Dictionary:
	return {
		"position": person.position, "state": person.state, "activity": person.activity,
		"wandering": person.wandering, "reason": person.reason,
		"route": person.route.duplicate(), "route_levels": person.route_levels.duplicate(),
		"route_on_surface": person.route_on_surface.duplicate(),
		"target": person.target, "target_tag": person.target_tag, "target_need": person.target_need,
		"fetch_from": person.fetch_from, "stand_spot": person.stand_spot, "seat": person.seat,
		"timer": person.timer, "gave_up": person.gave_up.duplicate(), "place_wait": person.place_wait,
		"think_wait": person.think_wait, "mood_wait": person.mood_wait, "done_main": person.done_main,
		"block": person.block.id if person.block != null else &"",
	}


## Puts someone back in the middle of what doing_of() saved. Anything that
## no longer makes sense (the object they were using is gone) leaves them
## standing about to choose again.
func resume_doing(person: Person, doing: Dictionary) -> void:
	if doing.is_empty():
		return
	_stop(person)
	person.position = doing["position"]
	person.activity = doing["activity"]
	person.reason = doing["reason"]
	person.gave_up.assign(doing["gave_up"])
	person.place_wait = doing["place_wait"]
	person.think_wait = doing["think_wait"]
	person.mood_wait = doing["mood_wait"]
	person.done_main = doing["done_main"]
	person.timer = doing["timer"]
	person.stand_spot = doing["stand_spot"]
	person.target = doing["target"]
	person.target_tag = doing["target_tag"]
	person.target_need = doing["target_need"]
	person.fetch_from = doing["fetch_from"]
	if person.has_object():
		if building.object_at(person.target) == null or _claimed.has(person.target):
			_release(person)
			person.state = Person.State.IDLE
			person.activity = "Standing about"
			if doing["state"] == Person.State.USING:
				person.position = person.stand_spot
			return
		_claimed[person.target] = person
	var seat: Vector2i = doing["seat"]
	if seat != Person.NO_OBJECT and building.object_at(seat) != null and not _claimed.has(seat):
		_take_seat(person, seat)
	person.route.assign(doing["route"])
	person.route_levels.assign(doing["route_levels"])
	person.route_on_surface.assign(doing["route_on_surface"])
	person.wandering = doing["wandering"]
	person.state = doing["state"]
	if person.state == Person.State.WALKING and person.route.is_empty():
		person.state = Person.State.IDLE


## Adds someone of a group (a prisoner unless told otherwise) standing at
## a spot on a level. Returns null if nobody can stand there.
func add_person(level: int, spot: Vector2, person_name := "", group: StringName = &"prisoner") -> Person:
	var height := nav().height_at(level, spot)
	if is_nan(height):
		return null
	var person := Person.new()
	person.id = _next_id
	_next_id += 1
	person.name = person_name if not person_name.is_empty() else random_name()
	person.group = group
	person.level = level
	person.position = Vector3(spot.x, height, spot.y)
	for def in needs:
		if access.has_need(group, def.id):
			person.needs[def.id] = _rng.randf_range(55.0, 100.0)
	person.traits = _pick_traits()
	person.think_wait = _rng.randf_range(0.0, THINK_MINUTES)
	person.mood_wait = _rng.randf_range(0.0, MOOD_MINUTES)
	people.append(person)
	_beds_dirty = true
	person_added.emit(person)
	return person


## A first name and a surname.
func random_name() -> String:
	return "%s %s" % [FIRST_NAMES[_rng.randi() % FIRST_NAMES.size()], SURNAMES[_rng.randi() % SURNAMES.size()]]


## The id the next person added will get.
func next_id() -> int:
	return _next_id


## Carries on numbering people from an id, such as after loading a save.
func set_next_id(id: int) -> void:
	_next_id = maxi(id, _next_id)


## Gives someone a staff role (or none), dressing them for it.
func set_role(person: Person, role: StringName) -> void:
	if person.role == role:
		return
	_stop(person)
	person.role = role
	if _bodies.has(person):
		_bodies[person].queue_free()
		_bodies.erase(person)


## Draws someone afresh, such as after their category changes colour.
func redraw(person: Person) -> void:
	if _bodies.has(person):
		_bodies[person].queue_free()
		_bodies.erase(person)


func remove_person(person: Person) -> void:
	_stop(person)
	_chatting_with.erase(person)
	_where.erase(person)
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
	_buckets_fresh = false
	if jobs != null:
		jobs.step(minutes)
	for person in people.duplicate():
		_think(person, minutes)


func need_def(id: StringName) -> NeedDef:
	if _need_defs.size() != needs.size():
		_need_defs.clear()
		for def in needs:
			_need_defs[def.id] = def
	return _need_defs.get(id)


## The object someone is heading for or using, or null.
func target_object(person: Person) -> BuildingMap.PlacedObject:
	if not person.has_object():
		return null
	var map := building.levels.get(person.target.x) as BuildingMap
	return map.objects.get(person.target.y) if map != null else null


## Who is using or heading for an object, or null.
func user_of(level: int, object_id: int) -> Person:
	return _claimed.get(Vector2i(level, object_id))


## Whose bed an object is, or null.
func owner_of(level: int, object_id: int) -> Person:
	return _bed_owners.get(Vector2i(level, object_id))


func room_type(id: StringName) -> RoomTypeDef:
	for def in room_types:
		if def.id == id:
			return def
	return null


## How nice a room is (see RoomQuality).
func quality(level: int, room: Room) -> RoomQuality:
	if not _qualities.has(room):
		var out := RoomQuality.assess(building.levels[level], room, room_type(room.type))
		var litter_count := _litter_in(level, room)
		if litter_count > 0:
			out.add_part("Litter about", -minf(litter_count * LITTER_EACH, LITTER_MOST))
		_qualities[room] = out
	return _qualities[room]


## How many pieces of litter lie in a room.
func _litter_in(level: int, room: Room) -> int:
	if items == null:
		return 0
	var count := 0
	var map := building.levels[level]
	for key: Vector3i in items.on_floor:
		if key.x == level and map.room_at(Vector2i(key.y, key.z)) == room:
			count += items.count_on_floor(key, litter_tag)
	return count


## Whether someone is asleep: using a bed for sleep.
func is_asleep(person: Person) -> bool:
	if person.state != Person.State.USING or not person.has_object():
		return false
	var def := need_def(person.target_need)
	return def != null and def.sleeping


## Gives someone a moodlet, or starts its timer again if they have it. A
## trait may swap it for another (a Foodie's lovely meal).
func add_moodlet(person: Person, id: StringName) -> void:
	for t in person.traits:
		id = t.moodlet_swaps.get(id, id)
	var def: MoodletDef = moodlet_defs.get(id)
	if def != null:
		var hours := def.hours
		if def.mood > 0.0:
			hours *= Modifiers.scale(modifiers, &"good_moodlet_time")
		person.moodlets[id] = hours * 60.0
		moodlet_added.emit(person, id)


## People within `distance` (up to NEARBY) of someone on the same level,
## not counting them.
func nearby(person: Person, distance := NEARBY) -> Array[Person]:
	if not _buckets_fresh:
		_buckets_fresh = true
		_buckets.clear()
		for other in people:
			_buckets.get_or_add(_bucket(other.level, other.flat()), []).append(other)
	var out: Array[Person] = []
	var centre := _bucket(person.level, person.flat())
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			for other: Person in _buckets.get(centre + Vector3i(0, dx, dz), []):
				if other != person and other.flat().distance_to(person.flat()) <= distance:
					out.append(other)
	return out


## The square of people a spot falls in, for `nearby`.
static func _bucket(level: int, spot: Vector2) -> Vector3i:
	return Vector3i(level, floori(spot.x / NEARBY), floori(spot.y / NEARBY))


## The face for someone's mood (see MoodModel.Face).
func face(person: Person) -> MoodModel.Face:
	return mood_model.face(person.mood)


#region Timetable

## Puts someone in a timetable block. Whatever they were doing stops,
## unless the new block still allows it where they are (asleep in their
## cell from Lockup into Sleep, say).
func set_block(person: Person, def: ActivityDef) -> void:
	def = swapped_block(person, def)
	if person.block == def:
		return
	_block_moodlets(person, person.block, def)
	person.block = def
	person.done_main = false
	person.gave_up.clear()
	person.place_wait = 0.0
	person.out_of_place = false
	if person.state == Person.State.USING and _still_allowed(person):
		return
	_stop(person)
	person.timer = 0.0


## The block someone gets instead of `def` while a privilege is lost,
## such as lockup instead of the yard.
func swapped_block(person: Person, def: ActivityDef) -> ActivityDef:
	if def == null:
		return def
	for id: StringName in person.restrictions:
		var privilege: PrivilegeDef = privileges.get(id)
		if privilege != null and privilege.swap_block.has(def.id):
			return activities.get(privilege.swap_block[def.id], def)
	return def


## Whether a lost privilege keeps someone off an object.
func restricted_from(person: Person, placed: BuildingMap.PlacedObject) -> bool:
	for id: StringName in person.restrictions:
		var privilege: PrivilegeDef = privileges.get(id)
		if privilege != null and privilege.blocks_tags.any(func(tag: StringName) -> bool: return placed.def.tags.has(tag)):
			return true
	return false


## Whether someone is where their block wants them. Without a bed of
## their own, a block that wants them in it can't be met.
func is_in_place(person: Person) -> bool:
	var block := person.block
	if block == null or not block.has_place() or (block.free_after and person.done_main):
		return true
	# On a work programme, they go where the work is.
	if block.jobs and person.programme != &"":
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
	var by_group: Dictionary = _rooms_for.get_or_add(block, {})
	var key := access.key_of(person.group, person.category)
	if not by_group.has(key):
		for n: int in building.levels:
			for room: Room in building.levels[n].rooms():
				if block.room_types.has(room.type) and may_enter(person, room):
					out.append([n, room])
		by_group[key] = out
	return by_group[key]


## Somewhere in the nearest room someone's block wants them in, as
## [level, spot], or [] if there's nowhere.
func place_spot(person: Person) -> Array:
	var rooms := place_rooms(person).duplicate()
	rooms.sort_custom(func(a: Array, b: Array) -> bool:
		return _room_score(person, a) < _room_score(person, b))
	for pair: Array in rooms:
		var spot: Variant = _spot_in_room(pair[0], pair[1])
		if spot != null:
			return [pair[0], spot]
	return []


## The room someone is in, as [level, Room], or [] if they are not in one.
## Don't change the array: it may be shared.
func room_of(person: Person) -> Array:
	var last: Array = _where.get(person, [])
	if not last.is_empty() and last[0] == person.position and last[1] == person.level:
		return last[2]
	var map := building.levels.get(person.level) as BuildingMap
	var room := map.room_at_point(person.flat()) if map != null else null
	var here := [person.level, room] if room != null else []
	_where[person] = [person.position, person.level, here]
	return here


## The room someone's bed is in, as [level, Room], or [] if they have none.
## Don't change the array: it may be shared.
func home_room(person: Person) -> Array:
	if _beds_dirty:
		assign_beds()
	return _homes.get(person, [])


## Who sleeps in a room, by their beds in it.
func owners_in(_level: int, room: Room) -> Array[Person]:
	if _beds_dirty:
		assign_beds()
	var out: Array[Person] = []
	out.assign(_sleepers.get(room, []))
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
		if not valid.has(key) or owner.bed != key or not people.has(owner) \
				or not may_enter(owner, building.levels[key.x].room_at_point(building.levels[key.x].objects[key.y].centre)):
			_bed_owners.erase(key)
			if owner.bed == key:
				owner.bed = Person.NO_BED
	for key: Vector2i in valid:
		if not _bed_owners.has(key):
			free.append(key)
	for person in people:
		if person.has_bed() or free.is_empty() or not access.gets_bed(person.group):
			continue
		var best := 0
		var best_score := INF
		best = -1
		for i in free.size():
			var key: Vector2i = free[i]
			var placed: BuildingMap.PlacedObject = building.levels[key.x].objects[key.y]
			# Only beds in rooms they may be in, such as their category's wing.
			if not may_enter(person, building.levels[key.x].room_at_point(placed.centre)):
				continue
			var score := placed.centre.distance_to(person.flat()) + absi(key.x - person.level) * 12.0
			if score < best_score:
				best = i
				best_score = score
		if best == -1:
			continue
		person.bed = free[best]
		_bed_owners[person.bed] = person
		free.remove_at(best)
	_homes.clear()
	_sleepers.clear()
	for person in people:
		if not person.has_bed():
			continue
		var map := building.levels[person.bed.x]
		var room := map.room_at_point(map.objects[person.bed.y].centre)
		_homes[person] = [person.bed.x, room]
		_sleepers.get_or_add(room, []).append(person)


## Locks or unlocks a door on a straight wall, for everyone without keys.
func set_door_locked(level: int, edge: Vector3i, locked: bool) -> void:
	if access.set_locked(Vector4i(level, edge.x, edge.y, edge.z), locked):
		doors_changed.emit()


func is_door_locked(level: int, edge: Vector3i) -> bool:
	return access.locked.has(Vector4i(level, edge.x, edge.y, edge.z))

#endregion


## Walking and timers move on every step; everything else (needs, mood,
## deciding) every half game minute for each person, staggered, so a big
## prison stays cheap.
func _think(person: Person, minutes: float) -> void:
	if person.state == Person.State.WALKING:
		_walk(person, minutes)
	else:
		person.timer -= minutes
	person.think_wait -= minutes
	if person.think_wait > 0.0:
		return
	var since := THINK_MINUTES - person.think_wait
	person.think_wait = THINK_MINUTES
	_run_down_needs(person, since)
	_look_around(person, since)
	for key: StringName in person.gave_up.keys():
		person.gave_up[key] -= since
		if person.gave_up[key] <= 0.0:
			person.gave_up.erase(key)
	person.place_wait -= since
	if person.going_home or person.led:
		return
	if person.has_object() and target_object(person) == null:
		_stop(person) # The object went while they were on their way.
	match person.state:
		Person.State.WALKING:
			if person.wandering and _has_errand(person):
				_stop(person)
				_decide(person, false)
		Person.State.USING when person.job != null:
			if person.timer <= 0.0:
				jobs.stage_done(person)
				if person.state == Person.State.IDLE:
					_decide(person, false)
			elif _urgent_need(person) != &"":
				_stop(person)
				_decide(person, false)
		Person.State.USING:
			if _done_using(person):
				_finish_using(person)
				_decide(person, false)
			elif _should_break_off(person) or _work_waiting(person):
				_stop(person)
				_decide(person, false)
		Person.State.IDLE:
			if _has_errand(person) or person.timer <= 0.0:
				_decide(person, person.timer <= 0.0)


## Needs run down, at the asleep rate while sleeping and faster or slower
## for some traits. The one being seen to with an object fills, and so do
## outdoors and company while someone is out or among people.
func _run_down_needs(person: Person, minutes: float) -> void:
	if needs_off.has(person.group):
		for need: StringName in person.needs:
			person.needs[need] = 100.0
		return
	var seeing_to := need_def(person.target_need) if person.state == Person.State.USING \
			and person.has_object() else null
	var asleep := is_asleep(person)
	for need: StringName in person.needs:
		var def := need_def(need)
		if def == null:
			continue
		var before: float = person.needs[need]
		var fills := def == seeing_to
		if not asleep:
			fills = fills or (def.source == NeedDef.Source.OUTDOORS and person.outdoors) \
					or (def.source == NeedDef.Source.COMPANY and person.in_company)
		if fills:
			person.needs[need] = minf(100.0, before + 100.0 / maxf(def.use_minutes, 0.1) * minutes)
			if before < 99.9 and person.needs[need] >= 99.9 and def.met_moodlet != &"":
				add_moodlet(person, def.met_moodlet)
			continue
		var rate := def.asleep_decay_per_hour if asleep else def.decay_per_hour
		person.needs[need] = maxf(0.0, before - rate * _need_rate(person, need) / 60.0 * minutes)
		if person.needs[need] <= 0.0 and def.empty_moodlet != &"":
			_run_out(person, def)


## How much faster someone's traits make a need run down.
func _need_rate(person: Person, need: StringName) -> float:
	var rate := 1.0
	for t in person.traits:
		rate *= t.need_rates.get(need, 1.0)
	return rate


## A need has run right out (an accident): a moodlet, the need met again,
## and other needs knocked down.
func _run_out(person: Person, def: NeedDef) -> void:
	add_moodlet(person, def.empty_moodlet)
	person.needs[def.id] = 100.0
	for other: StringName in def.empty_costs:
		if person.needs.has(other):
			person.needs[other] = maxf(0.0, person.needs[other] - def.empty_costs[other])
	if person.target_need == def.id:
		_stop(person)


## Every half game minute: whether someone is outdoors and in company,
## moodlets from the people about them, their moodlets running down, and
## their mood.
func _look_around(person: Person, minutes: float) -> void:
	for id: StringName in person.moodlets.keys():
		person.moodlets[id] -= minutes
		if person.moodlets[id] <= 0.0:
			person.moodlets.erase(id)
	var here := room_of(person)
	person.outdoors = not here[1].indoor if not here.is_empty() else person.level >= 0
	var asleep := is_asleep(person)
	var company := 0
	for other in nearby(person):
		if is_asleep(other) or other.state == Person.State.WALKING or not _same_place(here, room_of(other)):
			continue
		company += 1
		if not asleep:
			for t in other.traits:
				if t.nearby_moodlet != &"":
					add_moodlet(person, t.nearby_moodlet)
	person.in_company = company > 0 and not asleep and person.state != Person.State.WALKING
	for t in person.traits:
		if t.crowd_limit > 0 and company > t.crowd_limit and t.crowd_moodlet != &"":
			add_moodlet(person, t.crowd_moodlet)
	# Mood moves slowly, so it is worked out less often.
	person.mood_wait -= minutes
	if person.mood_wait > 0.0:
		return
	var first := person.mood_parts.is_empty()
	person.mood_parts = mood_model.parts(person, needs, moodlet_defs, _mood_extras(person, here))
	person.mood = mood_model.target(person.mood_parts) if first \
			else mood_model.follow(person.mood, person.mood_parts, MOOD_MINUTES - person.mood_wait)
	person.mood_wait = MOOD_MINUTES


## Whether two places from room_of are the same room, or both out of any
## room.
static func _same_place(a: Array, b: Array) -> bool:
	if a.is_empty() or b.is_empty():
		return a.is_empty() and b.is_empty()
	return a[0] == b[0] and a[1] == b[1]


## The parts of someone's mood that come from where they are and who they
## are: the room they sleep in and the one they're in, their cellmates,
## and their traits.
func _mood_extras(person: Person, here: Array) -> Array:
	var out: Array = []
	var home := home_room(person)
	if home.is_empty():
		if access.gets_bed(person.group):
			out.append(["Has no bed of their own", -5.0])
	else:
		var home_type := room_type(home[1].type)
		_room_part(out, quality(home[0], home[1]), home_type)
		var clashes: Array[String] = []
		var friends: Array[String] = []
		for mate in owners_in(home[0], home[1]):
			if mate == person:
				continue
			if _clash(person, mate):
				clashes.append(mate.name.get_slice(" ", 0))
			elif person.traits.any(func(t: TraitDef) -> bool: return mate.traits.has(t)):
				friends.append(mate.name.get_slice(" ", 0))
		# In a dorm it's the number that counts, up to a point.
		if not clashes.is_empty():
			out.append(["Doesn't get on with %s" % _who(clashes), -4.0 * mini(clashes.size(), 2)])
		if not friends.is_empty():
			out.append(["Gets on with %s" % _who(friends), 3.0 * mini(friends.size(), 2)])
		if home_type != null and home_type.dorm:
			for t in person.traits:
				if not is_zero_approx(t.dorm_mood):
					out.append(["Sleeps in a dorm", t.dorm_mood])
	if not here.is_empty() and (home.is_empty() or here[1] != home[1]):
		var here_quality := quality(here[0], here[1])
		_room_part(out, here_quality, room_type(here[1].type), true)
		for t in person.traits:
			for tag: StringName in t.room_likes:
				if here_quality.tags.has(tag):
					out.append([t.room_like_text, t.room_likes[tag]])
	for t in person.traits:
		if not is_zero_approx(t.steady_mood):
			out.append([t.steady_text, t.steady_mood])
	return out


## A room's quality as part of mood, such as "Nice cell" or "Grim canteen".
func _room_part(out: Array, room_quality: RoomQuality, type: RoomTypeDef, visiting := false) -> void:
	if absf(room_quality.score) < 0.5:
		return
	var type_name := type.display_name.to_lower() if type != null else "room"
	var text := ("Nice %s" if room_quality.score > 0.0 else "Grim %s") % type_name
	out.append([text if visiting else "%s to sleep in" % text, room_quality.score])


## "Bea", "Bea and Gus", or "4 others".
static func _who(names: Array[String]) -> String:
	if names.size() == 1:
		return names[0]
	if names.size() == 2:
		return "%s and %s" % names
	return "%d others" % names.size()


## Whether two people have traits that don't get on.
func _clash(a: Person, b: Person) -> bool:
	for t in a.traits:
		for other in b.traits:
			if t.clashes_with.has(other.id) or other.clashes_with.has(t.id):
				return true
	return false


## Moodlets for a change of block: going to bed hungry, or getting up
## earlier or later than a Night owl or Early bird would like.
func _block_moodlets(person: Person, old: ActivityDef, new: ActivityDef) -> void:
	if new == null:
		return
	var locks := func(def: ActivityDef) -> bool:
		return def != null and def.door_rule == ActivityDef.DoorRule.LOCK_OWN_ROOM
	if locks.call(new) and not locks.call(old):
		for def in needs:
			if def.shut_in_moodlet != &"" and person.needs.get(def.id, 100.0) < NEED_LINE:
				add_moodlet(person, def.shut_in_moodlet)
	var sleeps := func(def: ActivityDef) -> bool:
		if def == null or def.main_tag == &"":
			return false
		var need := _need_for_tag(def.main_tag)
		return need != &"" and need_def(need).sleeping
	if sleeps.call(old) and not sleeps.call(new) and clock != null:
		for t in person.traits:
			if t.wake_before_hour >= 0 and clock.hour() < t.wake_before_hour and t.wake_moodlet != &"":
				add_moodlet(person, t.wake_moodlet)


## Two traits that aren't the same or opposites, or none if the game has
## none.
func _pick_traits() -> Array[TraitDef]:
	return pick_traits(traits)


## Two traits from a pool that aren't the same or opposites.
func pick_traits(from: Array[TraitDef]) -> Array[TraitDef]:
	var out: Array[TraitDef] = []
	var pool := from.duplicate()
	while out.size() < 2 and not pool.is_empty():
		var pick: TraitDef = pool.pop_at(_rng.randi() % pool.size())
		if out.any(func(t: TraitDef) -> bool: return t.opposite == pick.id or pick.opposite == t.id):
			continue
		out.append(pick)
	return out


## Something to do other than wander: a need running out, getting to where
## the block wants them, its own object, or a need below the line.
func _has_errand(person: Person) -> bool:
	if _urgent_need(person) != &"":
		return true
	if jobs != null and jobs.has_work_for(person):
		return true
	if person.place_wait <= 0.0 and not is_in_place(person) and not place_rooms(person).is_empty():
		return true
	return _main_tag(person) != &"" or _pressing_need(person) != &""


## Works out what someone does next, in the order the class comment gives.
func _decide(person: Person, may_wander: bool) -> void:
	var block := person.block
	# Anything else deciding for them first, such as someone up to no good.
	for decider in deciders:
		if decider.call(person, may_wander):
			return
	if _leave_if_kept_out(person):
		return
	var urgent := _urgent_need(person)
	if person.job != null and (urgent != &"" or not jobs.wants_work(person)):
		jobs.abandon(person)
	if urgent != &"" and _see_to(person, urgent, true):
		person.reason = "%s has nearly run out" % need_def(urgent).display_name
		return
	# Between jobs, workers see to a need that has run low first.
	var running_low: StringName = _pressing_need(person) if person.job == null else &""
	if running_low != &"" and jobs != null and jobs.wants_work(person) and _see_to(person, running_low):
		person.reason = "%s is low" % need_def(running_low).display_name
		return
	if jobs != null and jobs.wants_work(person) and is_in_place(person) and jobs.carry_on(person):
		person.reason = "Working"
		return
	if not is_in_place(person):
		if person.place_wait <= 0.0 and _go_to_place(person):
			person.reason = "%s block" % block.display_name
			return
		person.place_wait = maxf(person.place_wait, RETRY_MINUTES)
	var main := _main_tag(person)
	var main_tags: Array[StringName] = [main]
	if main != &"" and _seek(person, main_tags):
		person.reason = "%s block" % block.display_name
		return
	person.reason = ""
	for choice: StringName in _choices(person):
		if _see_to(person, choice):
			var low: float = person.needs[choice]
			person.reason = "%s is %s" % [need_def(choice).display_name, "low" if low < NEED_LINE else "a bit low"]
			return
	if may_wander:
		_wander(person)
		if person.reason.is_empty():
			person.reason = "Nothing they need just now"
	elif block != null and not is_in_place(person) and person.state == Person.State.IDLE:
		person.activity = _why_not_in_place(person)


## The block's own object, if it is still to be used.
func _main_tag(person: Person) -> StringName:
	var block := person.block
	if block == null or block.main_tag == &"" or person.done_main or person.gave_up.has(block.main_tag):
		return &""
	return block.main_tag


## The lowest need below the line that the block allows, or &"".
func _pressing_need(person: Person) -> StringName:
	return _lowest_need(person, NEED_LINE)


## The lowest need that has nearly run out and the block allows, other
## than one being seen to, or &"".
func _urgent_need(person: Person) -> StringName:
	return _lowest_need(person, URGENT_LINE)


func _lowest_need(person: Person, line: float) -> StringName:
	var best: StringName = &""
	for need: StringName in person.needs:
		var def := need_def(need)
		if def == null or person.needs[need] >= line or person.gave_up.has(need):
			continue
		if not def.allowed_by(person.block) or (person.target_need == need and person.has_target()):
			continue
		if best == &"" or person.needs[need] < person.needs[best]:
			best = need
	return best


## Workers leave off something they're only doing for pleasure (not a
## need below the line) when there is a job for them.
func _work_waiting(person: Person) -> bool:
	if jobs == null or person.needs.get(person.target_need, 100.0) < NEED_LINE:
		return false
	var block := person.block
	if block != null and block.stay_on_main and person.target_tag == block.main_tag:
		return false
	return jobs.has_work_for(person)


## Whether someone should leave off what they're doing: a need running
## out, or, while only enjoying a place or company, any need below the
## line.
func _should_break_off(person: Person) -> bool:
	if _urgent_need(person) != &"":
		return true
	return not person.has_object() and _pressing_need(person) != &""


## The needs worth seeing to now that the block allows, best first: each
## scored by how low it is (squared, so low needs shout), how much they
## like what meets it, and how far away that is, with a little wobble.
func _choices(person: Person) -> Array[StringName]:
	var scored: Array = [] # [score, need]
	for need: StringName in person.needs:
		var def := need_def(need)
		var value: float = person.needs[need]
		if def == null or value >= minf(def.seek_below, WANT_LINE) or person.gave_up.has(need) \
				or not def.allowed_by(person.block):
			continue
		var best := _best_option(person, def, false)
		if best.is_empty():
			if value < NEED_LINE:
				_give_up(person, def.object_tags, need)
				person.reason = _nothing_for(def)
			continue
		var urgency := pow((100.0 - value) / 100.0, 2.0)
		var score: float = urgency * _liking(person, need) / (best[0] + DISTANCE_EASE) \
				* _rng.randf_range(1.0 - WOBBLE, 1.0 + WOBBLE)
		scored.append([score, need])
	scored.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
	var out: Array[StringName] = []
	for entry: Array in scored:
		out.append(entry[1])
	return out


## How much someone's traits make them like something: an object tag or a
## need id.
func _liking(person: Person, key: StringName) -> float:
	var like := 1.0
	for t in person.traits:
		like *= t.likes.get(key, 1.0)
	return like


## The nearest way to see to a need, as [distance in tiles, ...], or []
## for none. Distances count liked things as nearer.
func _best_option(person: Person, def: NeedDef, unrestricted: bool) -> Array:
	match def.source:
		NeedDef.Source.OUTDOORS:
			var rooms := _outdoor_rooms(person, unrestricted)
			return [0.0] if person.outdoors else ([_room_score(person, rooms[0])] if not rooms.is_empty() else [])
		NeedDef.Source.COMPANY:
			if person.in_company:
				return [0.0]
			var others := _company(person, unrestricted)
			return [others[0].flat().distance_to(person.flat())] if not others.is_empty() else []
	var candidates := _candidates(person, def.object_tags, unrestricted)
	return candidates[0] if not candidates.is_empty() else []


## Heads off to see to a need: an object that meets it, the outdoors, or
## someone to chat with. Returns false, and gives up on it for a while, if
## there is none to be had.
func _see_to(person: Person, need: StringName, urgent := false) -> bool:
	var def := need_def(need)
	match def.source:
		NeedDef.Source.OUTDOORS:
			return _go_outdoors(person, def, urgent)
		NeedDef.Source.COMPANY:
			return _find_company(person, def, urgent)
	return _seek(person, def.object_tags, need, urgent)


## Heads for the nearest free object with one of the tags, where the block
## allows (anywhere it allows the tag, if `unrestricted`). Returns false,
## and gives up on the tags for a while, if none can be reached.
func _seek(person: Person, tags: Array[StringName], need: StringName = &"", unrestricted := false) -> bool:
	if need == &"":
		need = _need_for_tag(tags[0])
	var candidates := _candidates(person, tags, unrestricted)
	var none_left: BuildingMap.PlacedObject = null
	for entry: Array in candidates.slice(0, 5):
		var n: int = entry[1]
		var placed: BuildingMap.PlacedObject = entry[2]
		var source := _item_source(person, placed, entry[3])
		if source == NONE_LEFT:
			none_left = placed
			continue
		var going_to := placed if source == Person.NO_OBJECT \
				else building.levels[source.x].objects[source.y] as BuildingMap.PlacedObject
		var seat: BuildingMap.PlacedObject = null
		if placed.def.seated:
			seat = free_seat(n, placed, person.flat())
			if seat == null:
				continue
		var spots := _spots_beside(source.x if going_to != placed else n, going_to, person.flat())
		if seat != null and going_to == placed:
			spots = _seat_spots(n, seat, person.flat())
		for spot in spots:
			if _walk_to(person, source.x if going_to != placed else n, spot):
				if seat != null:
					_take_seat(person, Vector2i(n, seat.id))
				person.target = Vector2i(n, placed.id)
				person.target_tag = entry[3]
				person.target_need = need
				person.fetch_from = source
				_claimed[person.target] = person
				var def := need_def(need)
				if going_to != placed:
					person.activity = "Fetching a %s" % String(placed.def.needs_item).replace("_", " ")
				else:
					person.activity = "Going to a %s" % placed.def.display_name.to_lower() \
							+ (" for %s" % def.display_name.to_lower() if def != null else "")
				return true
	if none_left != null:
		_give_up(person, tags, need)
		add_moodlet(person, none_left.def.without_item_moodlet)
		person.activity = "No %ss left" % String(none_left.def.needs_item).replace("_", " ")
		person.timer = 2.0
		return false
	_give_up(person, tags, need)
	person.activity = ("Can't find a free %s" if candidates.is_empty() else "Can't reach a %s") \
			% String(tags[0]).replace("_", " ")
	person.timer = 2.0
	return false


## Where to fetch the item an object needs in hand first, as (level,
## object id): Person.NO_OBJECT when it needs none just now, or NONE_LEFT
## when it does and nothing they can get to has any.
func _item_source(person: Person, placed: BuildingMap.PlacedObject, tag: StringName) -> Vector2i:
	var item := placed.def.needs_item
	if item == &"" or items == null or person.block == null or person.block.main_tag != tag:
		return Person.NO_OBJECT
	var holding := items.carrying(person)
	if holding != null and holding.has_tag(item):
		return Person.NO_OBJECT
	var givers := _givers_of(item)
	if givers.is_empty():
		return Person.NO_OBJECT
	var best := NONE_LEFT
	var best_distance := INF
	for entry: Array in givers:
		var key := Vector2i(entry[0], (entry[1] as BuildingMap.PlacedObject).id)
		if items.count_in(key, item) <= 0 or not may_enter(person, entry[2]):
			continue
		var distance := (entry[1] as BuildingMap.PlacedObject).centre.distance_to(person.flat()) \
				+ absi(key.x - person.level) * 12.0
		if distance < best_distance:
			best = key
			best_distance = distance
	return best


## Objects people help themselves to items with a tag from.
func _givers_of(item: StringName) -> Array:
	if not _givers.has(item):
		var out: Array = []
		for n: int in building.levels:
			var map := building.levels[n]
			for placed: BuildingMap.PlacedObject in map.objects.values():
				if placed.def.hands_out and placed.def.holds.has(item):
					out.append([n, placed, map.room_at_point(placed.centre)])
		_givers[item] = out
	return _givers[item]


## Why a need can't be seen to now, such as "Can't find a free table".
func _nothing_for(def: NeedDef) -> String:
	match def.source:
		NeedDef.Source.OUTDOORS:
			return "Nowhere outdoors to go"
		NeedDef.Source.COMPANY:
			return "Nobody about to talk to"
	return "Can't find a free %s" % String(def.object_tags[0]).replace("_", " ")


func _give_up(person: Person, tags: Array[StringName], need: StringName) -> void:
	for tag in tags:
		person.gave_up[tag] = RETRY_MINUTES
	if need != &"":
		person.gave_up[need] = RETRY_MINUTES


## Free objects with any of the tags that someone may use now, as
## [distance, level, object, tag], nearest first. Liked tags count as
## nearer.
func _candidates(person: Person, tags: Array[StringName], unrestricted := false) -> Array:
	var restricted := not unrestricted and _restricted(person)
	var allowed_rooms := place_rooms(person) if restricted else []
	var out: Array = []
	var seen: Dictionary[BuildingMap.PlacedObject, bool] = {}
	for tag in tags:
		if person.block != null and not person.block.allows(tag):
			continue
		for entry: Array in _objects_tagged(tag):
			var n: int = entry[0]
			var placed: BuildingMap.PlacedObject = entry[1]
			var room: Room = entry[2]
			if seen.has(placed) or _claimed.has(Vector2i(n, placed.id)) or not _may_use(person, n, placed) \
					or not may_enter(person, room):
				continue
			seen[placed] = true
			if restricted and not _room_listed(allowed_rooms, n, room):
				continue
			# Nearly bursting, they'll nip into someone else's cell if it's open.
			if room != null and not unrestricted and _someone_elses(person, n, room):
				continue
			var distance := placed.centre.distance_to(person.flat()) + absi(n - person.level) * 12.0
			out.append([distance / _liking(person, tag), n, placed, tag])
	out.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	return out


## Every object with a tag, as [level, PlacedObject, Room or null].
func _objects_tagged(tag: StringName) -> Array:
	if _by_tag.is_empty():
		_by_tag[&""] = []
		for n: int in building.levels:
			var map := building.levels[n]
			for placed: BuildingMap.PlacedObject in map.objects.values():
				var room := map.room_at_point(placed.centre)
				for t in placed.def.tags:
					_by_tag.get_or_add(t, []).append([n, placed, room])
	return _by_tag.get(tag, [])


## Outdoor rooms (a yard) someone may go to now, nearest first, as
## [level, Room] pairs.
func _outdoor_rooms(person: Person, unrestricted := false) -> Array:
	var restricted := not unrestricted and _restricted(person)
	var out: Array = []
	for pair: Array in (place_rooms(person) if restricted else _all_rooms()):
		var room: Room = pair[1]
		if room.enclosed and not room.indoor and not _someone_elses(person, pair[0], room) \
				and may_enter(person, room):
			out.append(pair)
	out.sort_custom(func(a: Array, b: Array) -> bool: return _room_score(person, a) < _room_score(person, b))
	return out


func _all_rooms() -> Array:
	var out: Array = []
	for n: int in building.levels:
		for room: Room in building.levels[n].rooms():
			out.append([n, room])
	return out


## Heads out to an outdoor room to enjoy the fresh air, or stays put if
## already out.
func _go_outdoors(person: Person, def: NeedDef, unrestricted: bool) -> bool:
	if person.outdoors:
		_enjoy_here(person, def)
		return true
	for pair: Array in _outdoor_rooms(person, unrestricted).slice(0, 3):
		for attempt in 4:
			var spot: Variant = _spot_in_room(pair[0], pair[1])
			if spot != null and _walk_to(person, pair[0], spot):
				_aim_at_place(person, def)
				person.activity = "Going out for some fresh air"
				return true
	_give_up(person, NO_TAGS, def.id)
	return false


## People someone could go and chat with: up and about, not off somewhere,
## and where they may go too. Nearest first.
func _company(person: Person, unrestricted := false) -> Array[Person]:
	var restricted := not unrestricted and _restricted(person)
	var allowed_rooms := place_rooms(person) if restricted else []
	var out: Array[Person] = []
	for other in people:
		if other == person or other.state == Person.State.WALKING or is_asleep(other):
			continue
		var there := room_of(other)
		if restricted and (there.is_empty() or not _room_listed(allowed_rooms, there[0], there[1])):
			continue
		if not there.is_empty() and _someone_elses(person, there[0], there[1]):
			continue
		out.append(other)
	out.sort_custom(func(a: Person, b: Person) -> bool:
		return a.flat().distance_to(person.flat()) + absi(a.level - person.level) * 12.0 \
				< b.flat().distance_to(person.flat()) + absi(b.level - person.level) * 12.0)
	return out


## Goes over to someone for a chat, or stays put if already among people.
func _find_company(person: Person, def: NeedDef, unrestricted: bool) -> bool:
	if person.in_company:
		_enjoy_here(person, def)
		return true
	for other: Person in _company(person, unrestricted).slice(0, 3):
		for attempt in 4:
			var angle := _rng.randf() * TAU
			var spot := other.flat() + Vector2(cos(angle), sin(angle)) * 0.8
			if nav().point_at(other.level, spot) != -1 and _walk_to(person, other.level, spot):
				_aim_at_place(person, def)
				_chatting_with[person] = other.name.get_slice(" ", 0)
				person.activity = "Going over to %s" % _chatting_with[person]
				return true
	_give_up(person, NO_TAGS, def.id)
	return false


## Marks someone as on their way to see to a need by a place or company.
func _aim_at_place(person: Person, def: NeedDef) -> void:
	person.target = Person.NO_OBJECT
	person.target_tag = def.id
	person.target_need = def.id


## Starts seeing to a need by a place or company right where they are.
func _enjoy_here(person: Person, def: NeedDef) -> void:
	_stop(person)
	_aim_at_place(person, def)
	_arrive(person)


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
		for pair: Array in _all_rooms():
			if block.room_types.has(pair[1].type):
				return "Not allowed anywhere for %s" % block.display_name
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
	var key := Vector2i(level, placed.id)
	if broken.has(key):
		return false
	if not person.restrictions.is_empty() and restricted_from(person, placed):
		return false
	if not _is_owned_tag_object(placed):
		return true
	return person.bed == key if person.has_bed() else not _bed_owners.has(key)


func _is_owned_tag_object(placed: BuildingMap.PlacedObject) -> bool:
	for tag in placed.def.tags:
		if owned_tags.has(tag):
			return true
	return false


func _need_for_tag(tag: StringName) -> StringName:
	for def in needs:
		if def.met_by(tag):
			return def.id
	return &""


## Sends someone for a stroll somewhere nearby they may go.
func wander(person: Person) -> void:
	_wander(person)


func _wander(person: Person) -> void:
	var spot: Variant = null
	var here := room_of(person)
	if _restricted(person) and is_in_place(person) and not here.is_empty():
		spot = _spot_in_room(here[0], here[1])
	elif not here.is_empty():
		# Indoors or in the yard, they keep to rooms they may be in rather
		# than drifting off across the land.
		for attempt in 4:
			var near: Variant = nav().random_spot(person.level, person.flat(), 6.0, _rng)
			var room := building.levels[person.level].room_at_point(near) if near != null else null
			if room != null and not _someone_elses(person, person.level, room) and may_enter(person, room):
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


## A free chair beside an object, or beside the surface it stands on,
## nearest `near` first; null if there's none.
func free_seat(level: int, placed: BuildingMap.PlacedObject, near: Vector2) -> BuildingMap.PlacedObject:
	var map := building.levels.get(level) as BuildingMap
	if map == null:
		return null
	var surface: BuildingMap.PlacedObject = map.objects.get(placed.on, placed)
	var best: BuildingMap.PlacedObject = null
	for entry: Array in _objects_tagged(seat_tag):
		var chair: BuildingMap.PlacedObject = entry[1]
		if entry[0] != level or _claimed.has(Vector2i(level, chair.id)) or broken.has(Vector2i(level, chair.id)) \
				or not surface.rect.grow(SEAT_REACH).has_point(chair.centre):
			continue
		if best == null or chair.centre.distance_to(near) < best.centre.distance_to(near):
			best = chair
	return best


## Where to stand to sit on a chair: on it, as people step between chairs,
## or else beside it.
func _seat_spots(level: int, chair: BuildingMap.PlacedObject, from: Vector2) -> Array[Vector2]:
	if nav().point_at(level, chair.centre) != -1:
		return [chair.centre]
	return _spots_beside(level, chair, from)


func _take_seat(person: Person, key: Vector2i) -> void:
	_leave_seat(person)
	person.seat = key
	_claimed[key] = person


func _leave_seat(person: Person) -> void:
	if person.seat != Person.NO_OBJECT and _claimed.get(person.seat) == person:
		_claimed.erase(person.seat)
	person.seat = Person.NO_OBJECT


## Someone in a room they may not be in (painted staff only while they
## were there, say) heads out through the nearest door they can. Returns
## whether they are on their way.
func _leave_if_kept_out(person: Person) -> bool:
	var here := room_of(person)
	if here.is_empty() or may_enter(person, here[1]):
		return false
	person.reason = "Not allowed in here"
	if person.state == Person.State.WALKING and person.activity == "Leaving":
		return true
	var map := building.levels[here[0]]
	var doors := ScheduleRunner.room_doors(map, here[1])
	doors.sort_custom(func(a: Vector3i, b: Vector3i) -> bool:
		return _door_middle(a).distance_to(person.flat()) < _door_middle(b).distance_to(person.flat()))
	for edge in doors:
		for cell in BuildingMap.edge_cells(edge):
			var room := map.room_at(cell)
			if room != here[1] and may_enter(person, room) \
					and _walk_to(person, here[0], Vector2(cell) + Vector2(0.5, 0.5)):
				person.activity = "Leaving"
				return true
	person.activity = "Can't get out"
	return false


static func _door_middle(edge: Vector3i) -> Vector2:
	var ends := BuildingMap.edge_ends(edge)
	return (ends[0] + ends[1]) * 0.5


func _set_up_access(person: Person) -> void:
	var here := room_of(person)
	if person.led and led_group != &"":
		# Kept with whoever leads them, through doors they couldn't pass.
		access.set_up(nav(), building, led_group, here[1] if not here.is_empty() else null, person.level)
		return
	access.set_up(nav(), building, person.passes_as if person.passes_as != &"" else person.group,
			here[1] if not here.is_empty() else null, person.level, person.category)


func _walk_to(person: Person, level: int, spot: Vector2) -> bool:
	var levels: Array[int] = []
	var surface: Array[bool] = []
	_set_up_access(person)
	var route := nav().find_path(person.level, person.flat(), level, spot, levels, surface, person.position.y)
	if route.is_empty():
		return false
	person.wandering = false
	person.route = route
	person.route_levels = levels
	person.route_on_surface = surface
	person.state = Person.State.WALKING
	return true


func _walk(person: Person, minutes: float) -> void:
	var budget := speed * person.pace * Health.pace(person.health) * minutes
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
	if person.job != null:
		jobs.arrived(person)
		return
	if person.fetch_from != Person.NO_OBJECT:
		_fetch_item(person)
		return
	if person.has_target() and not person.has_object():
		# Somewhere to be or someone to be with, rather than an object.
		person.stand_spot = person.position
		person.state = Person.State.USING
		person.timer = USE_MINUTES
		var place_def := need_def(person.target_need)
		person.activity = place_def.doing
		if _chatting_with.has(person):
			person.activity += " with %s" % _chatting_with[person]
		return
	var placed := target_object(person)
	if placed == null:
		person.state = Person.State.IDLE
		person.activity = "Standing about"
		return
	if items != null and placed.def.needs_item != &"":
		items.put_down(person) # Their tray, eaten.
	person.stand_spot = person.position
	person.state = Person.State.USING
	person.timer = USE_MINUTES
	var map := building.levels[person.target.x]
	person.position = Vector3(placed.centre.x, map.floor_height(Vector2i(placed.centre.floor()))
			+ placed.def.height * 0.6, placed.centre.y)
	var def := need_def(person.target_need)
	person.activity = def.doing if def != null else "Using the %s" % placed.def.display_name.to_lower()


## At the counter: take the item and carry it on to the object.
func _fetch_item(person: Person) -> void:
	var source := person.fetch_from
	person.fetch_from = Person.NO_OBJECT
	var placed := target_object(person)
	var got := items.take_from(source, placed.def.needs_item, 1) if placed != null else []
	if got.is_empty():
		_stop(person)
		person.activity = "Someone took the last one"
		person.timer = 0.5
		return
	items.pick_up(person, got)
	var seat: BuildingMap.PlacedObject = building.levels[person.seat.x].objects.get(person.seat.y) \
			if person.seat != Person.NO_OBJECT else null
	var spots := _seat_spots(person.target.x, seat, person.flat()) if seat != null \
			else _spots_beside(person.target.x, placed, person.flat())
	for spot in spots:
		if _walk_to(person, person.target.x, spot):
			person.activity = "Taking a %s to a %s" % [(got[0] as ItemDef).display_name.to_lower(),
					placed.def.display_name.to_lower()]
			return
	_stop(person)


## Done once the need is met, or the time is up for objects that meet
## none. The block's own object keeps them until the block ends if it says
## so (in bed until morning).
func _done_using(person: Person) -> bool:
	var block := person.block
	if block != null and block.stay_on_main and person.target_tag == block.main_tag:
		return false
	if person.target_need != &"" and person.needs.get(person.target_need, 100.0) >= 99.9:
		return true
	# Objects that meet a need keep people until it is met; places and
	# company, and objects that meet none, only for a while.
	return person.timer <= 0.0 and not (person.has_object() and person.target_need != &"")


func _finish_using(person: Person) -> void:
	if person.block != null and person.target_tag == person.block.main_tag:
		person.done_main = true
	_maybe_litter(person, target_object(person))
	if target_object(person) != null:
		used.emit(person, target_object(person))
	person.position = person.stand_spot
	_release(person)
	person.state = Person.State.IDLE
	person.activity = "Standing about"
	person.timer = 1.0


## Someone leaving an object may leave litter where they stood.
func _maybe_litter(person: Person, placed: BuildingMap.PlacedObject) -> void:
	if placed == null or items == null or litter.is_empty() or placed.def.litter_chance <= 0.0:
		return
	var chance := placed.def.litter_chance
	for t in person.traits:
		chance *= t.litter_scale
	if _rng.randf() < chance:
		var tile := Vector2i(Vector2(person.stand_spot.x, person.stand_spot.z).floor())
		items.drop_on_floor(Vector3i(person.target.x, tile.x, tile.y), litter[_rng.randi() % litter.size()], 1)


## Drops whatever someone was doing, stepping off any object they were on.
## A job part done goes back on the board.
func _stop(person: Person) -> void:
	if person.job != null:
		jobs.abandon(person)
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
	if person.has_object() and _claimed.get(person.target) == person:
		_claimed.erase(person.target)
	_leave_seat(person)
	person.fetch_from = Person.NO_OBJECT
	if items != null and person.job == null:
		items.put_down(person) # A tray they were taking somewhere.
	_chatting_with.erase(person)
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
		_pose(person, body, cs)
		_lie_down(person, body)
		_sit_down(person, body)
		body.get_node("Flag").visible = person.out_of_place and person.bubble.is_empty()
		var bubble := body.get_node("Bubble") as Label3D
		bubble.visible = not person.bubble.is_empty()
		bubble.text = person.bubble
		var face := body.get_node("Face") as Sprite3D
		var mood_face := mood_model.face(person.mood)
		face.visible = not person.out_of_place and person.bubble.is_empty() and mood_face >= MoodModel.Face.FED_UP \
				and not person.mood_parts.is_empty()
		if face.visible:
			face.texture = face_textures[mood_face]
	_update_visibility()


## The node drawing someone, or null before it is first drawn.
func body_of(person: Person) -> Node3D:
	return _bodies.get(person)


## Lies, sits or showers someone's body while they use an object, or
## work at one for a job (a guard at a desk).
func _pose(person: Person, body: Node3D, cs: float) -> void:
	var placed := target_object(person) if person.state == Person.State.USING else null
	var level := person.target.x
	if placed == null and person.state == Person.State.USING and person.job != null:
		var stage := person.job.current()
		if stage != null and stage.object != -1 and building.levels.has(stage.level):
			placed = building.levels[stage.level].objects.get(stage.object)
			level = stage.level
	if placed != null and placed.def.seated:
		# On the chair they took, or standing if there was none.
		var seat: BuildingMap.PlacedObject = building.levels[level].objects.get(person.seat.y) \
				if person.seat != Person.NO_OBJECT and person.seat.x == level else null
		placed = seat
	if placed != null:
		var map := building.levels[level]
		var floor_y := map.floor_height(Vector2i(placed.centre.floor()))
		if poses.apply(body, placed, floor_y, Vector2(person.stand_spot.x, person.stand_spot.z), cs,
				person.target_need):
			body.set_meta(&"posed", true)
			return
	if body.has_meta(&"posed"):
		body.remove_meta(&"posed")
		poses.clear(body)


## Flat out when knocked out or lying in bed for treatment. Only the body
## tips over; the labels over their head stay put.
func _lie_down(person: Person, body: Node3D) -> void:
	var lying := person.lying or Health.injury(person.health) == Health.Injury.KNOCKED_OUT
	if lying == body.has_meta(&"lying"):
		return
	if lying:
		body.set_meta(&"lying", true)
	else:
		body.remove_meta(&"lying")
	var tip := Transform3D(Basis(Vector3.RIGHT, -PI / 2.0), Vector3(0.0, 0.15, 0.0))
	for child in body.get_children():
		if child is Node3D and not (child is Label3D or child is Sprite3D):
			var part := child as Node3D
			if lying:
				part.set_meta(&"standing", part.transform)
				part.transform = tip * part.transform
			elif part.has_meta(&"standing"):
				part.transform = part.get_meta(&"standing")
				part.remove_meta(&"standing")


## Sat on the floor, legs out in front.
func _sit_down(person: Person, body: Node3D) -> void:
	if person.sitting and not person.lying and not body.has_meta(&"posed"):
		body.position.y -= SIT_DROP
		PersonPoses._swing(body, &"legs", PI * 0.5)
		body.set_meta(&"sat", true)
	elif body.has_meta(&"sat"):
		body.remove_meta(&"sat")
		PersonPoses._swing(body, &"legs", 0.0)


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
		rng.seed = person.look_seed if person.look_seed >= 0 else person.id
		var skin := skin_tones[rng.randi() % skin_tones.size()] if not skin_tones.is_empty() else head_colour
		var hair := hair_colours[rng.randi() % hair_colours.size()] if not hair_colours.is_empty() \
				else head_colour
		for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
			var part := mesh.name.get_slice("_", 0).to_lower()
			match part:
				"outfit": mesh.material_override = _flat_material(_outfit(person))
				"skin": mesh.material_override = _flat_material(skin)
				"hair": mesh.material_override = _flat_material(hair)
			# Parts for one group or role only, like the staff badge (named
			# *_staff) or a guard's cap (*_guard). Legs and arms are for
			# posing and always show.
			# get_slice gives the whole name when there is no "_", so plain
			# parts (outfit, skin) need checking for one first.
			var only := StringName(mesh.name.get_slice("_", 1)) if mesh.name.contains("_") else &""
			if access.groups.has(only):
				mesh.visible = only == person.group
			elif only not in [&"", &"legs", &"arms"]:
				mesh.visible = only == person.role
		_add_flag(model)
		return model
	var root := Node3D.new()
	var body := MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.17
	capsule.height = 0.62
	body.mesh = capsule
	body.position.y = 0.31
	body.material_override = _flat_material(_outfit(person))
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


## A "?" over someone's head, shown while they are out of place, and a
## face for when they are unhappy.
func _add_flag(root: Node3D) -> void:
	var face := Sprite3D.new()
	face.name = "Face"
	face.pixel_size = 0.005
	face.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	face.no_depth_test = true
	face.position.y = 1.15
	face.visible = false
	root.add_child(face)
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
	# What they're grumbling about, or a warning before they act up.
	var bubble := Label3D.new()
	bubble.name = "Bubble"
	bubble.font_size = 44
	bubble.outline_size = 14
	bubble.pixel_size = 0.006
	bubble.modulate = Color(1.0, 0.96, 0.9)
	bubble.outline_modulate = Color(0.45, 0.2, 0.15)
	bubble.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	bubble.no_depth_test = true
	bubble.position.y = 1.2
	bubble.visible = false
	root.add_child(bubble)


## Shared between everyone of the same colour.
## The colour of someone's clothes: their group's, else everyone's.
func _outfit(person: Person) -> Color:
	var role: StaffRoleDef = jobs.roles.get(person.role) if jobs != null else null
	if role != null:
		return role.outfit_colour
	var category: CategoryDef = categories.get(person.category)
	if category != null:
		return category.outfit_colour
	var group: GroupDef = access.groups.get(person.group)
	return group.outfit_colour if group != null else body_colour


func _flat_material(colour: Color) -> StandardMaterial3D:
	if not _materials.has(colour):
		var material := StandardMaterial3D.new()
		material.albedo_color = colour
		material.roughness = 0.8
		_materials[colour] = material
	return _materials[colour]
