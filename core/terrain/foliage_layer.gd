class_name FoliageLayer
extends Node3D
## Trees, bushes and flowers sitting on the terrain. Plants are free-placed
## (not on the tile grid) and drawn with one MultiMesh per kind and part,
## so thousands of them stay cheap.

signal changed

@export var terrain: Terrain


class Plant:
	var def: FoliageDef
	var position: Vector2 ## In tile units.
	var scale: float
	var rotation: float ## Radians around the vertical.


var plants: Array[Plant] = []

var _buckets: Dictionary[Vector2i, Array] = {} ## Tile to the plants in it.
var _instances := {} # [def id, part] -> MultiMeshInstance3D
var _rebuild_queued := false


func _ready() -> void:
	if terrain != null:
		terrain.changed.connect(queue_rebuild)
	queue_rebuild()


## Adds a plant if nothing is too close. Returns whether it was added.
func add(def: FoliageDef, position: Vector2, scale := 1.0, rotation := 0.0) -> bool:
	if not has_room(def, position):
		return false
	var plant := Plant.new()
	plant.def = def
	plant.position = position
	plant.scale = scale
	plant.rotation = rotation
	plants.append(plant)
	_bucket(position).append(plant)
	_changed()
	return true


## Is there space for this kind of plant here?
func has_room(def: FoliageDef, position: Vector2) -> bool:
	var reach := ceili(def.spacing)
	var home := Vector2i(position.floor())
	for z in range(home.y - reach, home.y + reach + 1):
		for x in range(home.x - reach, home.x + reach + 1):
			for other: Plant in _buckets.get(Vector2i(x, z), []):
				var gap := def.spacing if other.def == def else 0.3
				if other.position.distance_to(position) < gap:
					return false
	return true


## Scatters up to `attempts` plants at random inside a circle. `can_grow`
## takes a position and says whether a plant may go there.
func paint(def: FoliageDef, centre: Vector2, radius: float, attempts: int,
		rng: RandomNumberGenerator, can_grow: Callable) -> int:
	var added := 0
	for i in attempts:
		var offset := Vector2.from_angle(rng.randf() * TAU) * sqrt(rng.randf()) * radius
		var position := centre + offset
		if not can_grow.call(position):
			continue
		var scale := rng.randf_range(def.scale_range.x, def.scale_range.y)
		if add(def, position, scale, rng.randf() * TAU):
			added += 1
	return added


func remove_in_circle(centre: Vector2, radius: float) -> int:
	return _remove_where(func(plant: Plant) -> bool:
		return plant.position.distance_to(centre) <= radius)


## Clears plants that are now under water.
func remove_underwater() -> int:
	if terrain == null:
		return 0
	return _remove_where(func(plant: Plant) -> bool: return terrain.is_underwater(plant.position))


## Clears plants from an area, for example when a building goes down.
func remove_in_rect(rect: Rect2) -> int:
	return _remove_where(func(plant: Plant) -> bool: return rect.has_point(plant.position))


func _remove_where(test: Callable) -> int:
	var kept: Array[Plant] = []
	for plant in plants:
		if not test.call(plant):
			kept.append(plant)
	var removed := plants.size() - kept.size()
	if removed > 0:
		plants = kept
		_buckets.clear()
		for plant in plants:
			_bucket(plant.position).append(plant)
		_changed()
	return removed


func _bucket(position: Vector2) -> Array:
	var key := Vector2i(position.floor())
	if not _buckets.has(key):
		_buckets[key] = []
	return _buckets[key]


func _changed() -> void:
	queue_rebuild()
	changed.emit()


#region Drawing

func queue_rebuild() -> void:
	if _rebuild_queued:
		return
	_rebuild_queued = true
	rebuild.call_deferred()


func rebuild() -> void:
	_rebuild_queued = false
	if not is_inside_tree():
		return
	var cs := terrain.cell_size if terrain != null else 1.0
	var transforms := {} # [def id, part] -> Array[Transform3D]
	var key_defs := {} # [def id, part] -> FoliageDef
	for plant in plants:
		var ground := terrain.height_at(plant.position) if terrain != null else 0.0
		var base := Transform3D(Basis(Vector3.UP, plant.rotation).scaled(Vector3.ONE * plant.scale),
				Vector3(plant.position.x * cs, ground, plant.position.y * cs))
		for part in _parts(plant.def):
			var key := [plant.def.id, part]
			if not transforms.has(key):
				transforms[key] = []
				key_defs[key] = plant.def
			transforms[key].append(base * _part_offset(plant.def, part))
	for key in _instances.keys():
		if not transforms.has(key):
			_instances[key].multimesh.instance_count = 0
	for key in transforms:
		var instance := _instance_for(key, key_defs[key])
		var list: Array = transforms[key]
		instance.multimesh.instance_count = list.size()
		for i in list.size():
			instance.multimesh.set_instance_transform(i, list[i])


func _parts(def: FoliageDef) -> Array[StringName]:
	if def.shape == FoliageDef.Shape.TREE:
		return [&"trunk", &"canopy"]
	return [&"body"]


## Where each part sits relative to the plant's foot.
func _part_offset(def: FoliageDef, part: StringName) -> Transform3D:
	var s := def.size
	match def.shape:
		FoliageDef.Shape.TREE:
			if part == &"trunk":
				return Transform3D(Basis.from_scale(Vector3(0.18, 0.6, 0.18) * s), Vector3.UP * 0.3 * s)
			return Transform3D(Basis.from_scale(Vector3(0.8, 0.85, 0.8) * s), Vector3.UP * 0.95 * s)
		FoliageDef.Shape.BUSH:
			return Transform3D(Basis.from_scale(Vector3(1.0, 0.7, 1.0) * s), Vector3.UP * 0.3 * s)
	return Transform3D(Basis.from_scale(Vector3.ONE * s), Vector3.UP * 0.5 * s)


func _instance_for(key: Array, def: FoliageDef) -> MultiMeshInstance3D:
	if _instances.has(key):
		return _instances[key]
	var part: StringName = key[1]
	var mesh: Mesh
	var material := StandardMaterial3D.new()
	material.roughness = 0.9
	if part == &"trunk":
		var cylinder := CylinderMesh.new()
		cylinder.top_radius = 0.5
		cylinder.bottom_radius = 0.5
		cylinder.height = 1.0
		cylinder.radial_segments = 8
		mesh = cylinder
		material.albedo_color = def.trunk_colour
	else:
		var sphere := SphereMesh.new()
		sphere.radius = 0.5
		sphere.height = 1.0
		sphere.radial_segments = 12
		sphere.rings = 6
		mesh = sphere
		material.albedo_color = def.colour
	mesh.surface_set_material(0, material)
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = mesh
	var instance := MultiMeshInstance3D.new()
	instance.multimesh = multimesh
	add_child(instance)
	_instances[key] = instance
	return instance


#endregion
