class_name Terrain
extends Node3D
## Sculptable ground: a heightmap with one height per tile corner, drawn as
## a single mesh. Water comes from an optional sea level (anything below it
## is underwater, for coastal maps) and from the ponds and lakes in a
## WaterLayer.
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
@export var ground_material: Material
## Optional: ponds and lakes.
@export var water: WaterLayer
@export_group("Sea")
@export var has_sea := false
@export var sea_level := -0.35
@export var sea_colour := Color(0.35, 0.65, 0.9, 0.7)

## Corners that sculpting must leave alone, such as those under buildings.
## Set by the game; takes a Vector2i corner and returns true when locked.
var is_locked: Callable = func(_corner: Vector2i) -> bool: return false

## The corners the latest change touched, so listeners can skip work
## when sculpting happens far from them. The whole map after generation,
## flattening or setting many corners at once.
var last_changed := Rect2i()

var _heights := PackedFloat32Array()
## Triangle indices for the ground mesh, which never change.
var _indices := PackedInt32Array()
var _mesh_instance := MeshInstance3D.new()
var _sea := MeshInstance3D.new()
var _rebuild_queued := false


func _init() -> void:
	_heights.resize((size.x + 1) * (size.y + 1))
	add_child(_mesh_instance)
	add_child(_sea)


func _ready() -> void:
	_build_sea()
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


## The height of the water surface at a point (in tile units), or -INF if
## there is no water there.
func water_surface(point: Vector2) -> float:
	var surface := sea_level if has_sea else -INF
	if water != null:
		surface = maxf(surface, water.level_at(point))
	return surface


func is_underwater(point: Vector2) -> bool:
	return height_at(point) < water_surface(point)


## Sets every corner of the given tiles to one height, ignoring locks.
## Used when a building goes down.
func flatten_cells(cells: Array[Vector2i], height: float) -> void:
	# Only says it changed if it did, so building on ground that is already
	# flat doesn't make people work the ground out again.
	var moved := false
	for cell in cells:
		for offset: Vector2i in [Vector2i.ZERO, Vector2i(1, 0), Vector2i(0, 1), Vector2i.ONE]:
			var corner := cell + offset
			if in_bounds(corner) and not is_equal_approx(corner_height(corner), clampf(height, MIN_HEIGHT, MAX_HEIGHT)):
				set_corner_height(corner, height)
				moved = true
	if moved:
		_changed(_whole())


## Sets many corners at once, ignoring locks. Takes Vector2i corners to heights.
func set_corners(heights: Dictionary) -> void:
	for corner: Vector2i in heights:
		set_corner_height(corner, heights[corner])
	if not heights.is_empty():
		_changed(_whole())


## Fills the heights from a function of the corner, for world generation.
func generate(height_for_corner: Callable) -> void:
	for z in size.y + 1:
		for x in size.x + 1:
			set_corner_height(Vector2i(x, z), height_for_corner.call(Vector2i(x, z)))
	_changed(_whole())

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
		_changed(Rect2i(from, to - from + Vector2i.ONE))


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
	var point := Vector2(local.x, local.z) / cell_size
	return maxf(height_at(point), water_surface(point))

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
	# Packed arrays rather than SurfaceTool: this runs every frame while
	# sculpting, and is several times faster this way.
	var stride := size.x + 1
	var count := stride * (size.y + 1)
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	vertices.resize(count)
	normals.resize(count)
	var two := 2.0 * cell_size
	for z in size.y + 1:
		for x in stride:
			var i := z * stride + x
			var h := _heights[i]
			vertices[i] = Vector3(x * cell_size, h, z * cell_size)
			var left := _heights[i - 1] if x > 0 else 0.0
			var right := _heights[i + 1] if x < size.x else 0.0
			var up := _heights[i - stride] if z > 0 else 0.0
			var down := _heights[i + stride] if z < size.y else 0.0
			normals[i] = Vector3(left - right, two, up - down).normalized()
	if _indices.size() != size.x * size.y * 6:
		_indices.resize(size.x * size.y * 6)
		var k := 0
		for z in size.y:
			for x in size.x:
				var i := z * stride + x
				# Clockwise from above, which Godot treats as the front.
				for index in [i, i + 1, i + stride, i + 1, i + stride + 1, i + stride]:
					_indices[k] = index
					k += 1
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = _indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_mesh_instance.mesh = mesh
	_mesh_instance.material_override = ground_material


func _build_sea() -> void:
	_sea.visible = has_sea
	if not has_sea:
		return
	var plane := PlaneMesh.new()
	plane.size = Vector2(size) * cell_size
	_sea.mesh = plane
	_sea.position = Vector3(size.x * 0.5 * cell_size, sea_level, size.y * 0.5 * cell_size)
	_sea.material_override = WaterLayer.water_material(sea_colour)
	_sea.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _changed(area: Rect2i) -> void:
	last_changed = area
	queue_rebuild()
	changed.emit()


func _whole() -> Rect2i:
	return Rect2i(Vector2i.ZERO, size + Vector2i.ONE)

#endregion
