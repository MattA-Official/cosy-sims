class_name Terrain
extends Node3D
## Sculptable ground: a heightmap with one height per tile corner, drawn as
## a single mesh, plus a flat water level. Anything below the water level is
## underwater.
##
## Corner (x, z) is the top-left corner of tile (x, z), as in BuildingMap.
## Positions passed in and out are in this node's local space, which lines
## up with the BuildGrid it sits under (one tile is cell_size wide).

signal changed

const MIN_HEIGHT := -4.0
const MAX_HEIGHT := 8.0

@export var size := Vector2i(96, 96): ## In tiles.
	set(value):
		size = value
		_heights.resize((size.x + 1) * (size.y + 1))
@export var cell_size := 1.0
@export var water_level := -0.35
@export var ground_material: Material
@export var water_colour := Color(0.35, 0.65, 0.9, 0.7)

## Corners that sculpting must leave alone, such as those under buildings.
## Set by the game; takes a Vector2i corner and returns true when locked.
var is_locked: Callable = func(_corner: Vector2i) -> bool: return false

var _heights := PackedFloat32Array()
var _mesh_instance := MeshInstance3D.new()
var _water := MeshInstance3D.new()
var _rebuild_queued := false


func _init() -> void:
	_heights.resize((size.x + 1) * (size.y + 1))
	add_child(_mesh_instance)
	add_child(_water)


func _ready() -> void:
	_build_water()
	rebuild()


#region Heights

func in_bounds(corner: Vector2i) -> bool:
	return corner.x >= 0 and corner.y >= 0 and corner.x <= size.x and corner.y <= size.y


func corner_height(corner: Vector2i) -> float:
	if not in_bounds(corner):
		return 0.0
	return _heights[corner.y * (size.x + 1) + corner.x]


func set_corner_height(corner: Vector2i, height: float) -> void:
	if in_bounds(corner):
		_heights[corner.y * (size.x + 1) + corner.x] = clampf(height, MIN_HEIGHT, MAX_HEIGHT)


## Ground height at any point (in tile units), blending the four corners.
func height_at(point: Vector2) -> float:
	var base := Vector2i(point.floor())
	var f := point - Vector2(base)
	var top := lerpf(corner_height(base), corner_height(base + Vector2i(1, 0)), f.x)
	var bottom := lerpf(corner_height(base + Vector2i(0, 1)), corner_height(base + Vector2i.ONE), f.x)
	return lerpf(top, bottom, f.y)


## The average height of a tile's corners.
func cell_height(cell: Vector2i) -> float:
	return (corner_height(cell) + corner_height(cell + Vector2i(1, 0))
			+ corner_height(cell + Vector2i(0, 1)) + corner_height(cell + Vector2i.ONE)) * 0.25


func is_underwater(point: Vector2) -> bool:
	return height_at(point) < water_level


## Sets every corner of the given tiles to one height, ignoring locks.
## Used when a building goes down.
func flatten_cells(cells: Array[Vector2i], height: float) -> void:
	for cell in cells:
		for offset: Vector2i in [Vector2i.ZERO, Vector2i(1, 0), Vector2i(0, 1), Vector2i.ONE]:
			set_corner_height(cell + offset, height)
	_changed()


## Sets many corners at once, ignoring locks. Takes Vector2i corners to heights.
func set_corners(heights: Dictionary) -> void:
	for corner: Vector2i in heights:
		set_corner_height(corner, heights[corner])
	if not heights.is_empty():
		_changed()


## Fills the heights from a function of the corner, for world generation.
func generate(height_for_corner: Callable) -> void:
	for z in size.y + 1:
		for x in size.x + 1:
			set_corner_height(Vector2i(x, z), height_for_corner.call(Vector2i(x, z)))
	_changed()

#endregion

#region Sculpting

enum Brush { RAISE, LOWER, FLATTEN, SMOOTH }

## Applies a brush around a point (in tile units). Strength is metres per
## call at the centre for raise and lower, and a 0 to 1 blend for flatten
## and smooth. Locked corners are skipped. `allowed` limits which corners
## can change (for example, only owned land).
func sculpt(brush: Brush, centre: Vector2, radius: float, strength: float,
		target := 0.0, allowed: Callable = Callable()) -> void:
	var from := Vector2i((centre - Vector2.ONE * radius).floor())
	var to := Vector2i((centre + Vector2.ONE * radius).ceil())
	var updates := {}
	for z in range(from.y, to.y + 1):
		for x in range(from.x, to.x + 1):
			var corner := Vector2i(x, z)
			var distance := Vector2(corner).distance_to(centre)
			if distance > radius or not in_bounds(corner) or is_locked.call(corner):
				continue
			if allowed.is_valid() and not allowed.call(corner):
				continue
			# Smooth falloff: full strength in the middle, none at the rim.
			var weight := 1.0 - smoothstep(0.0, radius, distance)
			var height := corner_height(corner)
			match brush:
				Brush.RAISE:
					height += strength * weight
				Brush.LOWER:
					height -= strength * weight
				Brush.FLATTEN:
					height = lerpf(height, target, clampf(strength * weight, 0.0, 1.0))
				Brush.SMOOTH:
					height = lerpf(height, _neighbour_average(corner), clampf(strength * weight, 0.0, 1.0))
			updates[corner] = height
	# Apply afterwards so smoothing reads the old heights.
	for corner: Vector2i in updates:
		set_corner_height(corner, updates[corner])
	if not updates.is_empty():
		_changed()


func _neighbour_average(corner: Vector2i) -> float:
	var total := 0.0
	var count := 0
	for step in BuildingMap.DIRECTIONS:
		if in_bounds(corner + step):
			total += corner_height(corner + step)
			count += 1
	return total / maxf(count, 1)

#endregion

#region Picking

## Where a ray (in this node's local space) first meets the ground or the
## water, or null if it misses.
func intersect_ray(origin: Vector3, direction: Vector3) -> Variant:
	var dir := direction.normalized()
	var step := cell_size * 0.25
	var previous := 0.0
	var t := 0.0
	# Skip ahead to just above the highest possible ground.
	if origin.y > MAX_HEIGHT and dir.y < 0.0:
		t = (origin.y - MAX_HEIGHT) / -dir.y
		previous = t
	for i in 4000:
		var p := origin + dir * t
		if p.y < MIN_HEIGHT - 1.0:
			return null
		if p.y <= _surface_at(p):
			# Narrow it down between the last point above and this one.
			var lo := previous
			var hi := t
			for j in 12:
				var mid := (lo + hi) * 0.5
				var q := origin + dir * mid
				if q.y <= _surface_at(q):
					hi = mid
				else:
					lo = mid
			return origin + dir * hi
		previous = t
		t += step
	return null


## Height of the ground or the water, whichever is higher.
func _surface_at(local: Vector3) -> float:
	return maxf(height_at(Vector2(local.x, local.z) / cell_size), water_level)

#endregion

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
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for z in size.y + 1:
		for x in size.x + 1:
			var corner := Vector2i(x, z)
			st.set_normal(_corner_normal(corner))
			st.add_vertex(Vector3(x * cell_size, corner_height(corner), z * cell_size))
	var stride := size.x + 1
	for z in size.y:
		for x in size.x:
			var i := z * stride + x
			# Clockwise from above, which Godot treats as the front.
			st.add_index(i)
			st.add_index(i + 1)
			st.add_index(i + stride)
			st.add_index(i + 1)
			st.add_index(i + stride + 1)
			st.add_index(i + stride)
	_mesh_instance.mesh = st.commit()
	_mesh_instance.material_override = ground_material


func _corner_normal(corner: Vector2i) -> Vector3:
	var dx := corner_height(corner + Vector2i(1, 0)) - corner_height(corner - Vector2i(1, 0))
	var dz := corner_height(corner + Vector2i(0, 1)) - corner_height(corner - Vector2i(0, 1))
	return Vector3(-dx, 2.0 * cell_size, -dz).normalized()


func _build_water() -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(size) * cell_size
	_water.mesh = plane
	_water.position = Vector3(size.x * 0.5 * cell_size, water_level, size.y * 0.5 * cell_size)
	var material := StandardMaterial3D.new()
	material.albedo_color = water_colour
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.roughness = 0.1
	material.metallic_specular = 0.8
	_water.material_override = material
	_water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _changed() -> void:
	queue_rebuild()
	changed.emit()

#endregion
