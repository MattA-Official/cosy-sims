class_name EscapePlans
extends Node3D
## Planned escapes, for the truly miserable. A prisoner who has been under
## PLOT_MOOD for PLOT_NIGHTS midnights in a row, with more than
## PLOT_DAYS_LEFT days still to serve and the right tool in their pocket,
## starts a plan once there's a perimeter to get past:
##
## - A tunnel, from a ground-floor cell with a spoon: one tile a night
##   towards the nearest ground outside the perimeter. A pile of dirt by the
##   bed gives it away, and a search of the cell always finds it.
## - A fence cut, with a screwdriver: CUT_NIGHTS nights at a stretch of
##   perimeter with no guard or camera on it. The damaged fence shows, and a
##   guard who comes within FIND_DISTANCE finds it.
##
## Once through, they break out at night and make a run for it (see
## Escapes). Found first, the plan ends with an escape attempt on their
## record and an alert.

signal found(person: Person, words: String)
signal broke_out(person: Person, kind: StringName)

const PLOT_MOOD := 20.0
const PLOT_NIGHTS := 3
const PLOT_DAYS_LEFT := 5
## The hour of the night they dig or cut.
const WORK_HOUR := 3
const CUT_NIGHTS := 3
## Tiles from a fence cut that must have no guard or watched camera.
const QUIET_DISTANCE := 8.0
const FIND_DISTANCE := 3.0
const DIG_ITEMS: Array[StringName] = [&"spoon"]
const CUT_ITEMS: Array[StringName] = [&"screwdriver"]
const TUNNEL := &"tunnel"
const FENCE_CUT := &"fence_cut"
const DIRT_COLOUR := Color(0.47, 0.36, 0.26)
const CUT_COLOUR := Color(0.85, 0.45, 0.25)

## One prisoner's plan.
class Plan:
	var person: Person
	var kind: StringName
	## Nights of work done, and needed.
	var done := 0
	var needed := 1
	## Where the clue is (the bed's tile, or the fence tile inside), and
	## the tile outside they come out on.
	var spot := Vector2i.ZERO
	var out := Vector2i.ZERO
	var mark: Node3D

var people: People
var secure_area: SecureArea
var escapes: Escapes
var security: Security
var guard_role: StringName = &"guard"
var prisoner_group: StringName = &"prisoner"
var cell_size := 1.0
## (level, point) -> float: the ground's height, for the clues.
var height_at: Callable
var clock: GameClock:
	set(value):
		clock = value
		clock.hour_changed.connect(func(hour: int) -> void:
			if hour == WORK_HOUR:
				work_night())
		clock.minute_passed.connect(func(minute: int) -> void:
			if minute % 5 == 0:
				_patrol_finds())

var plans: Dictionary[Person, Plan] = {}


func start() -> void:
	people.person_removed.connect(func(person: Person) -> void:
		if plans.has(person):
			_drop(person))


## Midnight: counts miserable nights, and starts plans.
func nightly() -> void:
	for person in people.people:
		if person.group != prisoner_group:
			continue
		var low: int = person.profile.get("low_nights", 0)
		person.profile["low_nights"] = low + 1 if person.mood < PLOT_MOOD else 0
		if not plans.has(person) and should_plot(person):
			plot(person)


func should_plot(person: Person) -> bool:
	if not escapes.possible() or not secure_area.has_perimeter or person.going_home:
		return false
	var file := PrisonerFile.of(person)
	return person.profile.get("low_nights", 0) >= PLOT_NIGHTS \
			and (not file.has_sentence() or file.days_left(clock.day()) > PLOT_DAYS_LEFT) \
			and (_has(person, DIG_ITEMS) or _has(person, CUT_ITEMS))


## Starts a plan: a tunnel from a ground-floor cell with a digging tool,
## else a fence cut with a cutting tool. Returns it, or null.
func plot(person: Person) -> Plan:
	var plan: Plan = null
	if person.has_bed() and person.bed.x == 0 and _has(person, DIG_ITEMS):
		plan = _tunnel(person)
	if plan == null and _has(person, CUT_ITEMS):
		plan = _fence_cut(person)
	if plan != null:
		plans[person] = plan
		_draw(plan)
	return plan


## The night's digging and cutting; anyone through breaks out.
func work_night() -> void:
	for person: Person in plans.keys():
		var plan := plans[person]
		if person.led or person.going_home or person.quiet_room_hours > 0.0 or escapes.runners.has(person):
			continue
		if plan.kind == FENCE_CUT and not quiet_at(plan.spot):
			continue
		plan.done += 1
		_draw(plan)
		if plan.done >= plan.needed:
			_break_out(plan)


## Whether nobody is watching near a stretch of fence.
func quiet_at(cell: Vector2i) -> bool:
	var point := Vector2(cell) + Vector2(0.5, 0.5)
	if security != null and security.watched(0, point):
		return false
	return not people.people.any(func(p: Person) -> bool:
		return p.role == guard_role and p.level == 0 and p.flat().distance_to(point) <= QUIET_DISTANCE)


## A cell search finds any tunnel started in it.
func search_room(level: int, room: Room) -> void:
	for person: Person in plans.keys():
		var plan := plans[person]
		if plan.kind == TUNNEL and level == 0 and room.cells.has(plan.spot) and plan.done > 0:
			_found(plan, "A tunnel under %s's bed" % person.name.get_slice(" ", 0))


## How far along someone's plan is, for the inspector, or "".
func summary(person: Person) -> String:
	var plan: Plan = plans.get(person)
	if plan == null:
		return ""
	return "Planning %s (%d of %d nights)" % ["a tunnel" if plan.kind == TUNNEL else "to cut the fence",
			plan.done, plan.needed]


## Plans in progress, as plain data for a save.
func capture() -> Array:
	var out: Array = []
	for person: Person in plans:
		var plan := plans[person]
		out.append([person.id, plan.kind, plan.done, plan.needed, plan.spot, plan.out])
	return out


func restore(saved: Array) -> void:
	for entry: Array in saved:
		for person in people.people:
			if person.id == entry[0]:
				var plan := Plan.new()
				plan.person = person
				plan.kind = entry[1]
				plan.done = entry[2]
				plan.needed = entry[3]
				plan.spot = entry[4]
				plan.out = entry[5]
				plans[person] = plan
				_draw(plan)


func _tunnel(person: Person) -> Plan:
	var map := people.building.ground()
	var bed: BuildingMap.PlacedObject = map.objects.get(person.bed.y)
	if bed == null:
		return null
	var from := Vector2i(bed.centre.floor())
	var out := _nearest_outside(from)
	if out == Vector2i(-1, -1):
		return null
	var plan := Plan.new()
	plan.person = person
	plan.kind = TUNNEL
	plan.spot = from
	plan.out = out
	plan.needed = maxi(absi(out.x - from.x) + absi(out.y - from.y), 1)
	return plan


func _fence_cut(person: Person) -> Plan:
	var from := Vector2i(person.flat().floor())
	if person.has_bed():
		var bed: BuildingMap.PlacedObject = people.building.levels[person.bed.x].objects.get(person.bed.y)
		if bed != null:
			from = Vector2i(bed.centre.floor())
	# Fence tiles inside, with ground outside next to them, quietest and
	# nearest first.
	var best := Vector2i(-1, -1)
	var best_out := Vector2i(-1, -1)
	var best_distance := INF
	for cell: Vector2i in secure_area.secure:
		for step in BuildingMap.DIRECTIONS:
			var outside: Vector2i = cell + step
			if secure_area.is_secure(outside) or not people.building.ground().owns(outside):
				continue
			var distance := Vector2(from).distance_to(Vector2(cell))
			if distance < best_distance and quiet_at(cell):
				best = cell
				best_out = outside
				best_distance = distance
	if best == Vector2i(-1, -1):
		return null
	var plan := Plan.new()
	plan.person = person
	plan.kind = FENCE_CUT
	plan.spot = best
	plan.out = best_out
	plan.needed = CUT_NIGHTS
	return plan


## The nearest owned ground tile outside the perimeter, or (-1, -1).
func _nearest_outside(from: Vector2i) -> Vector2i:
	var map := people.building.ground()
	var best := Vector2i(-1, -1)
	var best_distance := 1 << 30
	for cell in BuildingMap.cells_in(map.land_bounds()):
		if not map.owns(cell) or secure_area.is_secure(cell):
			continue
		var distance := absi(cell.x - from.x) + absi(cell.y - from.y)
		if distance < best_distance:
			best = cell
			best_distance = distance
	return best


func _has(person: Person, ids: Array[StringName]) -> bool:
	return person.pocket.any(func(def: ItemDef) -> bool: return ids.has(def.id))


## Through: out at the far end, and running.
func _break_out(plan: Plan) -> void:
	var person := plan.person
	_drop(person)
	people.stop(person)
	var at := Vector2(plan.out) + Vector2(0.5, 0.5)
	var height: float = height_at.call(0, at) if height_at.is_valid() else 0.0
	person.level = 0
	person.position = Vector3(at.x, height, at.y)
	broke_out.emit(person, plan.kind)
	if not escapes.run(person):
		# Nowhere to run to from there: they're simply out of bounds.
		person.out_of_place = true


func _found(plan: Plan, words: String) -> void:
	var person := plan.person
	_drop(person)
	person.record.append([clock.day(), &"escape", "planned an escape"])
	if security != null:
		security.count(&"escape_plan", person, words)
	found.emit(person, words)


## Each few minutes: a guard near a cut fence spots it.
func _patrol_finds() -> void:
	for person: Person in plans.keys():
		var plan := plans[person]
		if plan.kind != FENCE_CUT or plan.done == 0:
			continue
		var point := Vector2(plan.spot) + Vector2(0.5, 0.5)
		if people.people.any(func(p: Person) -> bool:
				return p.role == guard_role and p.level == 0 and p.flat().distance_to(point) <= FIND_DISTANCE):
			_found(plan, "A cut in the fence")


func _drop(person: Person) -> void:
	var plan: Plan = plans.get(person)
	plans.erase(person)
	if plan != null and plan.mark != null:
		plan.mark.queue_free()


## The clue: a pile of dirt by the bed, or a bent bit of fence.
func _draw(plan: Plan) -> void:
	if plan.done == 0 or not is_inside_tree():
		return
	if plan.mark == null:
		var mesh := MeshInstance3D.new()
		var material := StandardMaterial3D.new()
		if plan.kind == TUNNEL:
			var mound := SphereMesh.new()
			mound.radius = 0.22
			mound.height = 0.2
			mesh.mesh = mound
			material.albedo_color = DIRT_COLOUR
		else:
			var bent := BoxMesh.new()
			bent.size = Vector3(0.5, 0.35, 0.08)
			mesh.mesh = bent
			material.albedo_color = CUT_COLOUR
		mesh.material_override = material
		plan.mark = mesh
		add_child(mesh)
	var at := Vector2(plan.spot) + Vector2(0.5, 0.5)
	if plan.kind == FENCE_CUT:
		at = at.lerp(Vector2(plan.out) + Vector2(0.5, 0.5), 0.45)
	var height: float = height_at.call(0, at) if height_at.is_valid() else 0.0
	plan.mark.position = Vector3(at.x * cell_size, height + (0.2 if plan.kind == FENCE_CUT else 0.0),
			at.y * cell_size)
	# A tunnel's pile grows with the digging.
	if plan.kind == TUNNEL:
		plan.mark.scale = Vector3.ONE * (0.8 + 0.4 * float(plan.done) / plan.needed)
