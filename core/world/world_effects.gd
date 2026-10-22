class_name WorldEffects
extends Node3D
## Small touches that make the place feel lived in: steam off showers and
## cookers in use, smoke from running generators, a sparkle when something
## is mended, and warm lights in the rooms after dark (none in a room the
## power doesn't reach).

## Object tags that steam while someone uses them.
const STEAMY: Array[StringName] = [&"shower", &"cooker"]
## Seconds between looking for things in use, and between puffs from each.
const LOOK := 0.4
const PUFF_EVERY := 1.4
## The most rooms lit at once, biggest first, to spare the renderer.
const MAX_LIGHTS := 48
const LIGHT_COLOUR := Color(1.0, 0.8, 0.55)
const LIGHT_ENERGY := 1.4
const PUFF := preload("res://core/building/effects/dust_puff.png")

@export var cell_size := 1.0

var people: People
var building: Building:
	set(value):
		building = value
		building.changed.connect(_lights_stale)
		building.active_changed.connect(func(_level: int) -> void: _lights_stale())
var day_night: DayNight
var clock: GameClock
var utilities: Utilities
var wear: Wear:
	set(value):
		wear = value
		wear.mended.connect(_on_mended)

var _look := 0.0
var _last_puff: Dictionary[Vector2i, float] = {}
var _time := 0.0
var _lights: Array[OmniLight3D] = []
var _lights_dirty := true
var _dark: Dictionary = {}


func _process(delta: float) -> void:
	_time += delta
	var night := 0.0
	if day_night != null and clock != null and not day_night.always_day:
		night = 1.0 - day_night.daylight(clock.hour_float())
	if utilities != null and utilities.dark_rooms != _dark:
		_dark = utilities.dark_rooms.duplicate()
		_lights_dirty = true
	if _lights_dirty and night > 0.0:
		_build_lights()
	for light in _lights:
		light.light_energy = LIGHT_ENERGY * night
		light.visible = night > 0.02
	_look -= delta
	if _look > 0.0:
		return
	_look = LOOK
	if people != null and clock != null and not clock.paused():
		_steam()
		_smoke()


## Puffs of steam over showers and cookers someone is using.
func _steam() -> void:
	for person: Person in people.people:
		if person.state != Person.State.USING:
			continue
		var placed := people.target_object(person)
		if placed == null or not placed.def.tags.any(func(tag: StringName) -> bool: return STEAMY.has(tag)):
			continue
		var key := Vector2i(person.level, placed.id)
		if _time - _last_puff.get(key, -INF) < PUFF_EVERY:
			continue
		_last_puff[key] = _time
		var at: Variant = _top_of(person.level, placed)
		if at != null:
			add_child(puffs(&"steam", at))


## Smoke from generators while they make power.
func _smoke() -> void:
	if utilities == null or utilities.mode != Utilities.Mode.SELF_SUFFICIENT:
		return
	for network: Utilities.Network in utilities.networks:
		for entry: Array in network.plant:
			var placed: BuildingMap.PlacedObject = entry[1]
			if placed.def.unit_cost <= 0.0 or placed.def.solar:
				continue
			var key := Vector2i(entry[0], placed.id)
			if utilities.off.has(key) or _time - _last_puff.get(key, -INF) < PUFF_EVERY * 0.7:
				continue
			_last_puff[key] = _time
			var at: Variant = _top_of(entry[0], placed)
			if at != null:
				add_child(puffs(&"smoke", at))


func _on_mended(key: Vector2i) -> void:
	var map := building.levels.get(key.x) as BuildingMap if building != null else null
	if map == null or not map.objects.has(key.y):
		return
	var at: Variant = _top_of(key.x, map.objects[key.y])
	if at != null:
		add_child(puffs(&"sparkle", at))


func _top_of(level: int, placed: BuildingMap.PlacedObject) -> Variant:
	var map := building.levels.get(level) as BuildingMap if building != null else null
	if map == null:
		return null
	var floor_y := map.floor_height(Vector2i(placed.centre.floor()))
	return Vector3(placed.centre.x * cell_size, floor_y + placed.def.height, placed.centre.y * cell_size)


## A one-shot burst of `kind` (steam, smoke or sparkle) at a point; it
## frees itself when done.
static func puffs(kind: StringName, at: Vector3) -> CPUParticles3D:
	var bits := CPUParticles3D.new()
	bits.name = String(kind).capitalize()
	bits.position = at
	bits.one_shot = true
	bits.local_coords = false
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	material.albedo_texture = PUFF
	material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	material.billboard_keep_scale = true
	var quad := QuadMesh.new()
	quad.material = material
	bits.mesh = quad
	var fade := Gradient.new()
	fade.offsets = PackedFloat32Array([0.0, 0.2, 1.0])
	bits.direction = Vector3.UP
	bits.gravity = Vector3.ZERO
	match kind:
		&"sparkle":
			quad.size = Vector2(0.12, 0.12)
			bits.amount = 10
			bits.lifetime = 0.8
			bits.explosiveness = 0.9
			bits.spread = 70.0
			bits.initial_velocity_min = 0.6
			bits.initial_velocity_max = 1.2
			bits.gravity = Vector3(0, -1.2, 0)
			fade.colors = PackedColorArray([Color(1, 0.95, 0.6, 0), Color(1, 0.92, 0.5, 1), Color(1, 1, 0.8, 0)])
		&"smoke":
			quad.size = Vector2(0.35, 0.35)
			bits.amount = 3
			bits.lifetime = 2.6
			bits.explosiveness = 0.3
			bits.spread = 12.0
			bits.initial_velocity_min = 0.35
			bits.initial_velocity_max = 0.5
			bits.gravity = Vector3(0.12, 0.05, 0.0)
			bits.scale_amount_max = 2.0
			fade.colors = PackedColorArray([Color(0.5, 0.5, 0.52, 0), Color(0.45, 0.45, 0.47, 0.55), Color(0.6, 0.6, 0.62, 0)])
		_:
			quad.size = Vector2(0.3, 0.3)
			bits.amount = 3
			bits.lifetime = 1.6
			bits.explosiveness = 0.4
			bits.spread = 20.0
			bits.initial_velocity_min = 0.25
			bits.initial_velocity_max = 0.4
			bits.scale_amount_max = 1.8
			fade.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 0.45), Color(1, 1, 1, 0)])
	var grow := Curve.new()
	grow.add_point(Vector2(0, 0.6))
	grow.add_point(Vector2(1, 1.4))
	bits.scale_amount_curve = grow
	bits.color_ramp = fade
	bits.emitting = true
	bits.finished.connect(bits.queue_free)
	return bits


func _lights_stale() -> void:
	_lights_dirty = true


## A warm light in each lit indoor room on the levels in view, biggest
## rooms first.
func _build_lights() -> void:
	_lights_dirty = false
	for light in _lights:
		light.queue_free()
	_lights.clear()
	if building == null:
		return
	var rooms: Array = []
	for level: int in building.levels:
		if level > building.active:
			continue
		var map: BuildingMap = building.levels[level]
		for room: Room in map.rooms():
			if room.indoor and room.area >= 2.0 and not _dark.has(room):
				rooms.append([room, map])
	rooms.sort_custom(func(a: Array, b: Array) -> bool: return a[0].area > b[0].area)
	for entry: Array in rooms.slice(0, MAX_LIGHTS):
		var room: Room = entry[0]
		var map: BuildingMap = entry[1]
		var middle := room.centre()
		var light := OmniLight3D.new()
		light.light_color = LIGHT_COLOUR
		light.omni_range = clampf(sqrt(room.area) * 0.9 + 1.5, 2.5, 9.0) * cell_size
		light.omni_attenuation = 1.2
		light.shadow_enabled = false
		light.light_energy = 0.0
		var floor_y := map.floor_height(Vector2i(middle.floor()))
		light.position = Vector3(middle.x * cell_size, floor_y + 1.2, middle.y * cell_size)
		add_child(light)
		_lights.append(light)
