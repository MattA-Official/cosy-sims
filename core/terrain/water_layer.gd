class_name WaterLayer
extends Node3D
## Water of three kinds. Ponds and lakes: each body fills a hollow in the
## terrain up to the height where it would spill over its rim, and refills
## itself when the ground near it changes, so digging a pond deeper or
## cutting through its rim just works. A lake a river runs into never dries.
## Rivers (River): carved beds with water running downhill, drawn as a
## sloped ribbon that flows. The sea: every tile joined to a coast edge
## and below the sea's level, which rises and falls with the tide.
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
			terrain.changed.disconnect(_on_ground_changed)
		terrain = value
		if terrain != null:
			terrain.changed.connect(_on_ground_changed)
@export var colour := Color(0.35, 0.65, 0.9, 0.7)

## Tiles water cannot enter, such as floors. Takes a Vector2i tile.
var is_blocked: Callable = func(_cell: Vector2i) -> bool: return false


class Body:
	var seed: Vector2i ## The tile it was filled from; refilling starts here.
	var level: float
	var cells: Dictionary[Vector2i, bool] = {}
	## Rivers running into it, by index; a fed lake never dries.
	var inflow: Array[int] = []

	func bounds() -> Rect2i:
		var out := Rect2i(seed, Vector2i.ONE)
		for cell in cells:
			out = out.expand(cell).expand(cell + Vector2i.ONE)
		return out


## Coast edges, as bits: north (y = 0), east, south, west.
enum Coast { NORTH = 1, EAST = 2, SOUTH = 4, WEST = 8 }
## Game minutes between tide updates.
const TIDE_MINUTES := 10.0

var bodies: Array[Body] = []
var rivers: Array[River] = []
## The sea: which edges are coast (Coast bits, 0 for none), its middle
## level, metres from low to high water, and hours from one high to the
## next.
var coast := 0
var sea_base := -0.35
var tide_range := 0.6
var tide_period := 12.4
## Game hours since the start, for the tide.
var tide_hours := 0.0

var _lookup: Dictionary[Vector2i, Body] = {}
var _river_cells: Dictionary[Vector2i, float] = {}
var _sea_cells: Dictionary[Vector2i, bool] = {}
var _mesh := MeshInstance3D.new()
var _river_mesh := MeshInstance3D.new()
var _sea_mesh := MeshInstance3D.new()
var _rebuild_queued := false


func _init() -> void:
	add_child(_mesh)
	add_child(_river_mesh)
	add_child(_sea_mesh)


func _ready() -> void:
	_mesh.material_override = water_material(colour)
	_sea_mesh.material_override = water_material(colour)
	_river_mesh.material_override = flowing_material(colour)
	for mesh in [_mesh, _river_mesh, _sea_mesh]:
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
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
	var cell := Vector2i(point.floor())
	var body := body_at(cell)
	var level := body.level if body != null else -INF
	if _river_cells.has(cell):
		level = maxf(level, _river_cells[cell])
	if _sea_cells.has(cell):
		level = maxf(level, sea_level())
	return level


## Whether any water lies on a tile.
func is_wet(cell: Vector2i) -> bool:
	return _lookup.has(cell) or _river_cells.has(cell) or _sea_cells.has(cell)


func _on_ground_changed() -> void:
	refill(terrain.last_changed)


## Works the bodies near an area out again from their seeds (all of them
## with no area given), after the ground has changed. Bodies that no longer
## hold water go, unless a river feeds them, and two that have joined
## become one.
func refill(area := Rect2i()) -> void:
	var old := bodies
	bodies = []
	_lookup.clear()
	var any_change := false
	var kept: Array[Body] = []
	var redo: Array[Body] = []
	for body in old:
		if area.size != Vector2i.ZERO and not body.bounds().grow(1).intersects(area):
			kept.append(body)
		else:
			redo.append(body)
	for body in kept:
		_add(body)
	for body in redo:
		if _lookup.has(body.seed):
			any_change = true # Merged into a body already refilled.
			continue
		var fresh := find_basin(body.seed)
		if fresh == null:
			if not body.inflow.is_empty():
				_add(body)
			else:
				any_change = true
			continue
		fresh.inflow = body.inflow
		if not is_equal_approx(fresh.level, body.level) or fresh.cells.size() != body.cells.size():
			any_change = true
		# A kept body this one has grown into joins it.
		for other in kept:
			if bodies.has(other) and other.cells.keys().any(func(c: Vector2i) -> bool: return fresh.cells.has(c)):
				bodies.erase(other)
				fresh.inflow.append_array(other.inflow)
				any_change = true
		_add(fresh)
	if any_change:
		_rebuild_lookup()
	update_sea()
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


#region Rivers

## Draws a river through control points: carves its bed and fills it. Where
## it ends in a hollow rather than at the map edge, it feeds a lake there.
## Returns it, or null for fewer than two points.
func add_river(points: PackedVector2Array, width := 3.0) -> River:
	if terrain == null or points.size() < 2:
		return null
	var river := River.new()
	river.points = points
	river.width = clampf(width, River.LEAST_WIDTH, River.MOST_WIDTH)
	river.shape(terrain)
	rivers.append(river)
	_river_cells_from_rivers()
	terrain.set_corners(river.carving(terrain))
	var mouth := Vector2i(river.line[river.line.size() - 1].floor())
	if _on_map(mouth + Vector2i.ONE) and _on_map(mouth - Vector2i.ONE):
		var lake := body_at(mouth)
		if lake == null:
			lake = find_basin(mouth)
			if lake != null:
				_add(lake)
		if lake != null:
			lake.inflow.append(rivers.size() - 1)
	_changed()
	return river


## The river covering a tile, or null.
func river_at(cell: Vector2i) -> River:
	for river in rivers:
		if river.cells().has(cell):
			return river
	return null


## Stops a river running; its bed stays dug.
func remove_river(river: River) -> void:
	var index := rivers.find(river)
	if index < 0:
		return
	rivers.remove_at(index)
	for body in bodies:
		body.inflow.erase(index)
		for i in body.inflow.size():
			if body.inflow[i] > index:
				body.inflow[i] -= 1
	_river_cells_from_rivers()
	_changed()


func _river_cells_from_rivers() -> void:
	_river_cells.clear()
	for river in rivers:
		var cells := river.cells()
		for cell in cells:
			if _on_map(cell) and not is_blocked.call(cell):
				_river_cells[cell] = maxf(_river_cells.get(cell, -INF), cells[cell])

#endregion


#region The sea

## The sea's level now, with the tide.
func sea_level() -> float:
	return sea_base + tide_range * 0.5 * sin(TAU * tide_hours / tide_period)


## Moves the tide on to a time, in game hours. Returns whether any tiles
## flooded or dried.
func set_tide(hours: float) -> bool:
	tide_hours = hours
	return update_sea()


## Hours from now to the next high tide.
func hours_to_high_tide() -> float:
	var quarter := tide_period * 0.25
	return fposmod(quarter - tide_hours, tide_period)


func is_sea(cell: Vector2i) -> bool:
	return _sea_cells.has(cell)


## "High tide at 14:20", from the time the tide was last set.
func tide_words() -> String:
	var at := fposmod(tide_hours + hours_to_high_tide(), 24.0)
	var minutes := roundi(at * 60.0) % (24 * 60)
	return "High tide at %02d:%02d" % [minutes / 60, minutes % 60]


## Whether the tide covers a tile now that is dry at mean sea level.
func tidal(cell: Vector2i) -> bool:
	return _sea_cells.has(cell) and _low(cell) >= sea_base


## Floods every tile joined to a coast edge that lies below the sea, and
## dries the rest. Returns whether anything changed.
func update_sea() -> bool:
	var fresh: Dictionary[Vector2i, bool] = {}
	if terrain != null and coast != 0:
		var level := sea_level()
		var stack: Array[Vector2i] = []
		for x in terrain.size.x:
			if coast & Coast.NORTH:
				stack.append(Vector2i(x, 0))
			if coast & Coast.SOUTH:
				stack.append(Vector2i(x, terrain.size.y - 1))
		for y in terrain.size.y:
			if coast & Coast.WEST:
				stack.append(Vector2i(0, y))
			if coast & Coast.EAST:
				stack.append(Vector2i(terrain.size.x - 1, y))
		while not stack.is_empty():
			var cell: Vector2i = stack.pop_back()
			if fresh.has(cell) or not _on_map(cell) or is_blocked.call(cell) or _low(cell) >= level:
				continue
			fresh[cell] = true
			for step in BuildingMap.DIRECTIONS:
				stack.append(cell + step)
	if fresh.size() == _sea_cells.size() and fresh.keys().all(func(c: Vector2i) -> bool: return _sea_cells.has(c)):
		return false
	_sea_cells = fresh
	_changed()
	return true

#endregion


## Every body of water, for saving and undo.
func to_data() -> Dictionary:
	var out: Array = []
	for body in bodies:
		out.append([body.seed, body.level, body.cells.duplicate(), body.inflow.duplicate()])
	return {"bodies": out, "rivers": rivers.map(func(r: River) -> Array: return r.to_data()),
			"sea": [coast, sea_base, tide_range, tide_period]}


func load_data(data: Dictionary) -> void:
	bodies.clear()
	for entry: Array in data.get("bodies", []):
		var body := Body.new()
		body.seed = entry[0]
		body.level = entry[1]
		body.cells.assign(entry[2])
		if entry.size() > 3:
			body.inflow.assign(entry[3])
		bodies.append(body)
	rivers.clear()
	for entry: Array in data.get("rivers", []):
		rivers.append(River.from_data(entry))
	var sea: Array = data.get("sea", [0, sea_base, tide_range, tide_period])
	coast = sea[0]
	sea_base = sea[1]
	tide_range = sea[2]
	tide_period = sea[3]
	_rebuild_lookup()
	_river_cells_from_rivers()
	update_sea()
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
	_build_rivers()
	_build_sea()
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


## A ribbon for each river at its water height, sloping down its length;
## v runs along it in tiles, for the flow.
func _build_rivers() -> void:
	if rivers.is_empty():
		_river_mesh.mesh = null
		return
	var cs := terrain.cell_size if terrain != null else 1.0
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_normal(Vector3.UP)
	for river in rivers:
		var along := 0.0
		var edges: Array = []
		for i in river.line.size():
			var here := river.line[i]
			var ahead := river.line[mini(i + 1, river.line.size() - 1)] - river.line[maxi(i - 1, 0)]
			var side := Vector2(-ahead.y, ahead.x).normalized() * river.width * 0.5
			if i > 0:
				along += here.distance_to(river.line[i - 1])
			var y := river.surface(i)
			edges.append([Vector3((here.x + side.x) * cs, y, (here.y + side.y) * cs),
					Vector3((here.x - side.x) * cs, y, (here.y - side.y) * cs), along])
		for i in edges.size() - 1:
			var a: Array = edges[i]
			var b: Array = edges[i + 1]
			# Both ways round, so the ribbon shows whichever way it was drawn.
			var corners := [[a[0], 0.0, a[2]], [a[1], 1.0, a[2]], [b[0], 0.0, b[2]], [b[1], 1.0, b[2]]]
			for k in [0, 2, 1, 2, 3, 1, 0, 1, 2, 2, 1, 3]:
				st.set_uv(Vector2(corners[k][1], float(corners[k][2]) / river.width))
				st.set_color(Color(river.flow, 0.0, 0.0))
				st.add_vertex(corners[k][0])
	_river_mesh.mesh = st.commit()


## A tile of sea at its level for each tile it covers.
func _build_sea() -> void:
	if _sea_cells.is_empty():
		_sea_mesh.mesh = null
		return
	var cs := terrain.cell_size if terrain != null else 1.0
	var level := sea_level()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_normal(Vector3.UP)
	for cell in _sea_cells:
		var a := Vector3(cell.x * cs, level, cell.y * cs)
		for p in [a, a + Vector3(cs, 0, 0), a + Vector3(0, 0, cs), a + Vector3(cs, 0, 0), a + Vector3(cs, 0, cs), a + Vector3(0, 0, cs)]:
			st.add_vertex(p)
	_sea_mesh.mesh = st.commit()


## Water that runs: ripples sliding along v, as fast as the vertex
## colour's red says.
static func flowing_material(tint: Color) -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = """shader_type spatial;
render_mode cull_disabled;
uniform vec4 tint : source_color;
varying float flow;
void vertex() {
	flow = COLOR.r;
}
void fragment() {
	float ripple = sin((UV.y * 6.0 - TIME * flow * 0.4) * 6.2832 + sin(UV.x * 9.0) * 0.6) * 0.5 + 0.5;
	ALBEDO = mix(tint.rgb, vec3(1.0), ripple * 0.12);
	ALPHA = tint.a;
	ROUGHNESS = 0.1;
	SPECULAR = 0.8;
}
"""
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter(&"tint", tint)
	return material


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
