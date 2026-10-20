class_name WaterLayer
extends Node3D
## Ponds and lakes. Each body fills a hollow in the terrain up to the height
## where it would spill over its rim, and refills itself whenever the ground
## changes, so digging a pond deeper or cutting through its rim just works.
##
## A tile counts as wet when its lowest corner is below the water level;
## the water surface is drawn over the whole tile and the ground hides the
## parts above it.

signal changed

## Hollows bigger than this many tiles are not filled. Stops one click on
## a plain ringed by hills from flooding everything, and keeps it quick.
const MAX_CELLS := 1500
## How far below the rim the water sits, so it never quite touches it.
const RIM_GAP := 0.05
## Hollows shallower than this are not worth filling.
const MIN_DEPTH := 0.1

@export var terrain: Terrain:
	set(value):
		if terrain != null:
			terrain.changed.disconnect(refill)
		terrain = value
		if terrain != null:
			terrain.changed.connect(refill)
@export var colour := Color(0.35, 0.65, 0.9, 0.7)

## Tiles water cannot enter, such as floors. Takes a Vector2i tile.
var is_blocked: Callable = func(_cell: Vector2i) -> bool: return false


class Body:
	var seed: Vector2i ## The tile it was filled from; refilling starts here.
	var level: float
	var cells: Dictionary[Vector2i, bool] = {}


var bodies: Array[Body] = []

var _lookup: Dictionary[Vector2i, Body] = {}
var _mesh := MeshInstance3D.new()
var _rebuild_queued := false


func _init() -> void:
	add_child(_mesh)


func _ready() -> void:
	_mesh.material_override = water_material(colour)
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	queue_rebuild()


## Fills the hollow around a tile. Returns the new body, or null if the
## tile is already wet or there is no hollow to fill.
func fill_at(cell: Vector2i) -> Body:
	if _lookup.has(cell):
		return null
	var body := find_basin(cell)
	if body == null:
		return null
	_add(body)
	_changed()
	return body


func remove_at(cell: Vector2i) -> bool:
	var body := body_at(cell)
	if body == null:
		return false
	bodies.erase(body)
	_rebuild_lookup()
	_changed()
	return true


func body_at(cell: Vector2i) -> Body:
	return _lookup.get(cell)


## The water level at a point in tile units, or -INF where it is dry.
func level_at(point: Vector2) -> float:
	var body := body_at(Vector2i(point.floor()))
	return body.level if body != null else -INF


## Works every body out again from its seed, after the ground has changed.
## Bodies that no longer hold water go, and two that have joined become one.
func refill() -> void:
	var old := bodies
	bodies = []
	_lookup.clear()
	var any_change := false
	for body in old:
		if _lookup.has(body.seed):
			any_change = true # Merged into a body already refilled.
			continue
		var fresh := find_basin(body.seed)
		if fresh == null:
			any_change = true
			continue
		if not is_equal_approx(fresh.level, body.level) or fresh.cells.size() != body.cells.size():
			any_change = true
		_add(fresh)
	if any_change:
		_changed()


## Works out how a hollow would fill from one tile, without adding it.
## Water rises from the lowest tile, spreading to the lowest neighbour first;
## the moment the next tile is lower than the water, it would spill there,
## so that height is the rim. Reaching flat ground at the water's height
## counts as the rim too, so a hole dug in a plain fills to the brim
## instead of flooding the plain.
func find_basin(seed: Vector2i) -> Body:
	if terrain == null or not _on_map(seed) or is_blocked.call(seed):
		return null
	var start := _low(seed)
	var level := start
	var heap := _MinHeap.new()
	var queued := {seed: true}
	heap.push(start, seed)
	var visited := 0
	while not heap.is_empty():
		var height := heap.peek_priority()
		var cell: Vector2i = heap.pop()
		if height < level:
			break # Downhill from here: the water spills at `level`.
		if level > start and is_equal_approx(height, level) and _is_flat(cell):
			break # A flat ledge or plain at the rim: fill to the brim and stop.
		level = height
		visited += 1
		if visited > MAX_CELLS:
			return null
		for step in BuildingMap.DIRECTIONS:
			var next := cell + step
			if queued.has(next):
				continue
			queued[next] = true
			if not _on_map(next):
				heap.push(-INF, next) # Water runs off the edge of the map.
			elif is_blocked.call(next):
				continue
			else:
				heap.push(_low(next), next)
	if level - start < MIN_DEPTH:
		return null
	var body := Body.new()
	body.seed = seed
	body.level = level - RIM_GAP
	# The wet tiles are those below the water, joined to the seed.
	var stack: Array[Vector2i] = [seed]
	body.cells[seed] = true
	while not stack.is_empty():
		var cell: Vector2i = stack.pop_back()
		for step in BuildingMap.DIRECTIONS:
			var next: Vector2i = cell + step
			if body.cells.has(next) or not _on_map(next) or is_blocked.call(next):
				continue
			if _low(next) < body.level:
				body.cells[next] = true
				stack.append(next)
	return body


func _add(body: Body) -> void:
	bodies.append(body)
	for cell in body.cells:
		_lookup[cell] = body


func _rebuild_lookup() -> void:
	_lookup.clear()
	for body in bodies:
		for cell in body.cells:
			_lookup[cell] = body


func _on_map(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < terrain.size.x and cell.y < terrain.size.y


## A tile's lowest corner: water gets in as soon as it is above this.
func _low(cell: Vector2i) -> float:
	return minf(minf(terrain.corner_height(cell), terrain.corner_height(cell + Vector2i(1, 0))),
			minf(terrain.corner_height(cell + Vector2i(0, 1)), terrain.corner_height(cell + Vector2i.ONE)))


func _is_flat(cell: Vector2i) -> bool:
	var h := terrain.corner_height(cell)
	return is_equal_approx(h, terrain.corner_height(cell + Vector2i(1, 0))) \
			and is_equal_approx(h, terrain.corner_height(cell + Vector2i(0, 1))) \
			and is_equal_approx(h, terrain.corner_height(cell + Vector2i.ONE))


## Every body of water, for saving and undo.
func to_data() -> Dictionary:
	var out: Array = []
	for body in bodies:
		out.append([body.seed, body.level, body.cells.duplicate()])
	return {"bodies": out}


func load_data(data: Dictionary) -> void:
	bodies.clear()
	for entry: Array in data.get("bodies", []):
		var body := Body.new()
		body.seed = entry[0]
		body.level = entry[1]
		body.cells.assign(entry[2])
		bodies.append(body)
	_rebuild_lookup()
	_changed()


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
	if bodies.is_empty():
		_mesh.mesh = null
		return
	var cs := terrain.cell_size if terrain != null else 1.0
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_normal(Vector3.UP)
	for body in bodies:
		for cell in body.cells:
			var a := Vector3(cell.x * cs, body.level, cell.y * cs)
			var b := a + Vector3(cs, 0, 0)
			var c := a + Vector3(cs, 0, cs)
			var d := a + Vector3(0, 0, cs)
			# Clockwise from above, which Godot treats as the front.
			for p in [a, b, d, b, c, d]:
				st.add_vertex(p)
	_mesh.mesh = st.commit()


static func water_material(tint: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = tint
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.roughness = 0.1
	material.metallic_specular = 0.8
	return material

#endregion


## A small binary min-heap of tiles, keyed by height.
class _MinHeap:
	var _priorities: Array[float] = []
	var _items: Array = []

	func is_empty() -> bool:
		return _items.is_empty()

	func peek_priority() -> float:
		return _priorities[0]

	func push(priority: float, item: Variant) -> void:
		_priorities.append(priority)
		_items.append(item)
		var i := _items.size() - 1
		while i > 0:
			var parent := (i - 1) / 2
			if _priorities[parent] <= _priorities[i]:
				break
			_swap(i, parent)
			i = parent

	func pop() -> Variant:
		var top: Variant = _items[0]
		var last := _items.size() - 1
		_swap(0, last)
		_items.pop_back()
		_priorities.pop_back()
		var i := 0
		while true:
			var left := i * 2 + 1
			var right := left + 1
			var smallest := i
			if left < _items.size() and _priorities[left] < _priorities[smallest]:
				smallest = left
			if right < _items.size() and _priorities[right] < _priorities[smallest]:
				smallest = right
			if smallest == i:
				break
			_swap(i, smallest)
			i = smallest
		return top

	func _swap(a: int, b: int) -> void:
		var p := _priorities[a]
		_priorities[a] = _priorities[b]
		_priorities[b] = p
		var item: Variant = _items[a]
		_items[a] = _items[b]
		_items[b] = item
