class_name NavGraph
extends RefCounted
## Where people can walk, as a graph for A*. Every piece of floor on every
## level is a point, and so is every tile of open ground on your land.
## Points join where people can step from one to the next: no wall or
## window between them (doors are fine) and no drop bigger than a step.
## Stairs, lifts and built paths (stairs, ramps and bridges outdoors) add
## points of their own that join the levels and cross what the ground
## cannot. Ground paths make the ground under them cheaper to walk on, so
## people keep to them.
##
## Positions are in tile units across the ground and metres up: x and z
## match the grid, y is height.

## Steepest rise between two neighbouring ground tiles people will walk.
const MAX_GROUND_RISE := 0.6
## Walking cost on bare ground compared with floor or path.
const GROUND_COST := 1.6
## Extra cost of taking a lift, for the wait.
const LIFT_COST := 4.0
## Spacing of points along built paths, in tiles.
const PATH_STEP := 1.0


## Open ground worked out from the terrain, water, paths and land alone,
## kept between rebuilds while those stay the same: building only changes
## which tiles are open and which walls are in the way, which is cheap to
## apply on top. Working this out is most of the cost of a rebuild.
class GroundLayer:
	var land: Array[Rect2i] = []
	var terrain: Terrain
	var paths: PathNetwork
	## Each dry tile's walking point and weight (cheaper on ground paths).
	var points: Dictionary[Vector2i, Vector3] = {}
	var weights: Dictionary[Vector2i, float] = {}
	## Neighbouring tiles (diagonals included) gentle enough to walk
	## between, as (x, y, next x, next y), each pair once.
	var links: Array[Vector4i] = []


var astar := AStar3D.new()
## The ground layer this graph was built on, to pass to the next build.
var ground_layer: GroundLayer

var _building: Building
var _paths: PathNetwork
var _terrain: Terrain
var _next_id := 1
## (level, cell x, cell y, piece index) for floor, piece -1 for open ground.
var _ids: Dictionary[Vector4i, int] = {}
var _levels: Dictionary[int, int] = {} ## Point id: its level.
## Each door on a straight wall, as (level, edge x, edge y, edge axis): the
## pairs of points it joins, so it can be locked without a rebuild.
var _door_links: Dictionary[Vector4i, Array] = {}


## Builds the graph. Pass the last graph's `ground_layer` to reuse it when
## only the building has changed: the caller must know the terrain, water
## and paths haven't. It is worked out afresh if the land has grown or the
## terrain or paths are different ones.
static func build(building: Building, paths: PathNetwork = null, terrain: Terrain = null,
		ground: GroundLayer = null) -> NavGraph:
	var graph := NavGraph.new()
	graph._building = building
	graph._paths = paths
	graph._terrain = terrain
	if ground == null or ground.land != building.ground().land or ground.terrain != terrain \
			or ground.paths != paths:
		ground = graph._work_out_ground()
	graph.ground_layer = ground
	for n: int in building.levels:
		graph._add_floors(n)
	graph._add_ground()
	for n: int in building.levels:
		graph._join_floors(n)
	graph._join_ground()
	graph._add_stairs()
	graph._add_lifts()
	graph._add_built_paths()
	return graph


## The point people stand on at a spot on a level, or -1 if they cannot
## stand there.
func point_at(level: int, spot: Vector2) -> int:
	var cell := Vector2i(spot.floor())
	var map := _building.levels.get(level) as BuildingMap
	if map != null and map.has_floor(cell):
		var piece := map.piece_at(spot)
		if piece != null:
			return _ids.get(Vector4i(level, cell.x, cell.y, piece.index), -1)
	return _ids.get(Vector4i(level, cell.x, cell.y, -1), -1)


## A random spot people can stand on, on a level, within `radius` tiles of
## `near`, or null if none turned up.
func random_spot(level: int, near: Vector2, radius: float, rng: RandomNumberGenerator) -> Variant:
	for attempt in 12:
		var spot := near + Vector2(rng.randf_range(-radius, radius), rng.randf_range(-radius, radius))
		var id := point_at(level, spot)
		if id != -1:
			var p := position_of(id)
			return Vector2(p.x, p.z)
	return null


## The level a point is on.
func level_of(id: int) -> int:
	return _levels.get(id, 0)


func position_of(id: int) -> Vector3:
	return astar.get_point_position(id)


## A walk from one spot to another, as positions to head for in turn, or
## [] if there is no way there. Straight stretches with nothing in the way
## are taken in one go rather than tile by tile. `levels` and
## `on_surface`, if given, are filled with each position's level and
## whether it is on floor or ground (rather than stairs, a lift or a built
## path). Someone stopped part way up the stairs, where `from` is no floor
## or ground, starts from the nearest point if `from_height` is given.
func find_path(from_level: int, from: Vector2, to_level: int, to: Vector2,
		levels: Array[int] = [], on_surface: Array[bool] = [], from_height := NAN) -> Array[Vector3]:
	var start := point_at(from_level, from)
	if start == -1 and not is_nan(from_height):
		var at := Vector3(from.x, from_height, from.y)
		var nearest := astar.get_closest_point(at)
		if nearest != -1 and position_of(nearest).distance_to(at) < 1.0:
			start = nearest
	var goal := point_at(to_level, to)
	var out: Array[Vector3] = []
	if start == -1 or goal == -1:
		return out
	var ids := astar.get_id_path(start, goal)
	if ids.is_empty():
		return out
	# Drop points that can be walked past in a straight line.
	var kept: Array[int] = [ids[0]]
	var i := 0
	while i < ids.size() - 1:
		var j := ids.size() - 1
		while j > i + 1 and not _clear_between(ids[i], ids[j]):
			j -= 1
		kept.append(ids[j])
		i = j
	for id in kept:
		out.append(position_of(id))
		levels.append(level_of(id))
		on_surface.append(_is_surface(id))
	return out


## The height of the floor or ground people stand on at a spot, or NAN if
## they cannot stand there.
func height_at(level: int, spot: Vector2) -> float:
	var id := point_at(level, spot)
	if id == -1:
		return NAN
	var map := _building.levels.get(level) as BuildingMap
	if map != null and map.has_floor(Vector2i(spot.floor())):
		return _floor_height(map, spot)
	return _ground(spot)


## Can people walk straight from one point to another? Both must be floor
## or ground on the same level, and every point the line passes over must
## join the next.
func _clear_between(a: int, b: int) -> bool:
	if level_of(a) != level_of(b) or not _is_surface(a) or not _is_surface(b):
		return false
	var from := position_of(a)
	var to := position_of(b)
	var flat_from := Vector2(from.x, from.z)
	var flat_to := Vector2(to.x, to.z)
	var steps := ceili(flat_from.distance_to(flat_to) / 0.25)
	var previous := a
	for k in range(1, steps + 1):
		var spot := flat_from.lerp(flat_to, float(k) / steps)
		var here := point_at(level_of(a), spot)
		if here == -1:
			return false
		if here != previous:
			if _stepped.has(here) or astar.is_point_disabled(here) \
					or not astar.are_points_connected(previous, here):
				return false
			previous = here
	return previous == b


var _surface: Dictionary[int, bool] = {} ## Floor and ground points.
## Points on tiles with door steps, which routes must not cut past.
var _stepped: Dictionary[int, bool] = {}


func _is_surface(id: int) -> bool:
	return _surface.has(id)


func _add_point(key: Vector4i, level: int, position: Vector3, weight := 1.0) -> int:
	var id := _next_id
	_next_id += 1
	astar.add_point(id, position, weight)
	_levels[id] = level
	if key.w != -2:
		_ids[key] = id
	return id


func _add_floors(n: int) -> void:
	var map := _building.levels[n]
	for cell: Vector2i in map.floors:
		if map.holes.has(cell) or map.stairs_at(cell) != null:
			continue
		for piece: TilePiece in map.pieces(cell):
			if not map.piece_has_floor(piece):
				continue
			var middle := piece.centre()
			if _blocked(map, middle):
				continue
			var id := _add_point(Vector4i(n, cell.x, cell.y, piece.index), n,
					Vector3(middle.x, _floor_height(map, middle), middle.y))
			_surface[id] = true


## The ground layer for the current terrain, water, paths and land.
func _work_out_ground() -> GroundLayer:
	var layer := GroundLayer.new()
	var map := _building.ground()
	layer.land = map.land.duplicate()
	layer.terrain = _terrain
	layer.paths = _paths
	var pathed := _path_cells()
	for rect in map.land:
		for cell in BuildingMap.cells_in(rect):
			if layer.points.has(cell):
				continue
			var middle := Vector2(cell) + Vector2(0.5, 0.5)
			if _terrain != null and _terrain.is_underwater(middle):
				continue
			layer.points[cell] = Vector3(middle.x, _ground(middle), middle.y)
			layer.weights[cell] = 1.0 if pathed.has(cell) else GROUND_COST
	for cell: Vector2i in layer.points:
		var height := layer.points[cell].y
		# Half the neighbours, so each pair is seen once.
		for offset: Vector2i in [Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(1, -1)]:
			var next := cell + offset
			if layer.points.has(next) \
					and absf(layer.points[next].y - height) <= MAX_GROUND_RISE * Vector2(offset).length():
				layer.links.append(Vector4i(cell.x, cell.y, next.x, next.y))
	return layer


## Open ground on your land: every dry tile on the ground level with no
## floor.
func _add_ground() -> void:
	var map := _building.ground()
	for cell: Vector2i in ground_layer.points:
		if map.has_floor(cell):
			continue
		var id := _add_point(Vector4i(0, cell.x, cell.y, -1), 0, ground_layer.points[cell],
				ground_layer.weights[cell])
		_surface[id] = true


## Joins floor pieces to their neighbours, across tile sides and through
## doors in angled walls.
func _join_floors(n: int) -> void:
	var map := _building.levels[n]
	for key: Vector4i in _ids.keys():
		if key.x != n or key.w < 0:
			continue
		var cell := Vector2i(key.y, key.z)
		var piece: TilePiece = map.pieces(cell)[key.w]
		var id := _ids[key]
		for i in piece.sides.size():
			var tag: Variant = piece.sides[i]
			var stretch := PackedVector2Array([piece.polygon[i], piece.polygon[(i + 1) % piece.polygon.size()]])
			if tag is Vector4i:
				if map.slant_at(tag) != BuildingMap.Wall.DOOR:
					continue
				for other: TilePiece in map.pieces(cell):
					if other.index != piece.index and other.sides_tagged(tag).any(
							func(s: PackedVector2Array) -> bool: return TilePiece.overlaps(stretch, s)):
						_join(id, _ids.get(Vector4i(n, cell.x, cell.y, other.index), -1))
				continue
			var next_cell: Vector2i = cell + BuildingMap.DIRECTIONS[tag]
			var edge := BuildingMap.edge_between(cell, next_cell)
			if not map.passable(edge):
				continue
			var kind := map.wall_at(edge)
			var door_key := Vector4i(n, edge.x, edge.y, edge.z)
			if map.door_has_steps(edge):
				# Door steps make up the difference; the low side's tile is
				# kept as a corner of every route so people climb them there.
				var across: int = _ids.get(Vector4i(n, next_cell.x, next_cell.y, 0), -1)
				if across != -1 and piece.is_whole():
					_join(id, across)
					_note_door(door_key, id, across)
					var low := cell if map.floor_height(cell) < map.floor_height(next_cell) else next_cell
					_stepped[_ids.get(Vector4i(n, low.x, low.y, 0), -1)] = true
				continue
			var nexts := map.pieces(next_cell)
			# Two uncut tiles always share their whole side.
			var whole := nexts.size() == 1 and piece.is_whole()
			for next: TilePiece in nexts:
				if not whole and not next.sides_tagged(tag ^ 1).any(
						func(s: PackedVector2Array) -> bool: return TilePiece.overlaps(stretch, s)):
					continue
				var other: int = _ids.get(Vector4i(n, next_cell.x, next_cell.y, next.index), -1)
				if other == -1 and n == 0 and not map.has_floor(next_cell):
					other = _ids.get(Vector4i(0, next_cell.x, next_cell.y, -1), -1)
				if other != -1 and absf(map.edge_height(cell, BuildingMap.DIRECTIONS[tag])
						- _edge_height_of(other, n, next_cell, -BuildingMap.DIRECTIONS[tag])) <= BuildingMap.MAX_STEP + 0.01:
					_join(id, other)
					if kind == BuildingMap.Wall.DOOR:
						_note_door(door_key, id, other)
		# Diagonals across whole tiles, when both ways round are open.
		if piece.is_whole():
			for d in [Vector2i(1, 1), Vector2i(1, -1)]:
				_join_diagonal(n, cell, d)


## Joins open ground to the ground around it, diagonals included, where
## the slope is gentle enough and no wall or fence is in the way.
func _join_ground() -> void:
	# Walls are few next to tiles of ground, so list the pairs they block
	# and the tiles they touch; links away from those need no checks.
	var blocked: Dictionary[Vector4i, bool] = {}
	var walled: Dictionary[Vector2i, bool] = {}
	var map := _building.ground()
	for edge: Vector3i in map.walls:
		if map.walls[edge] == BuildingMap.Wall.DOOR:
			continue
		var cells := BuildingMap.edge_cells(edge)
		blocked[Vector4i(cells[0].x, cells[0].y, cells[1].x, cells[1].y)] = true
		blocked[Vector4i(cells[1].x, cells[1].y, cells[0].x, cells[0].y)] = true
		walled[cells[0]] = true
		walled[cells[1]] = true
	for link: Vector4i in ground_layer.links:
		var id: int = _ids.get(Vector4i(0, link.x, link.y, -1), -1)
		var other: int = _ids.get(Vector4i(0, link.z, link.w, -1), -1)
		if id == -1 or other == -1:
			continue
		if walled.has(Vector2i(link.x, link.y)) or walled.has(Vector2i(link.z, link.w)):
			if blocked.has(link):
				continue
			# A diagonal also needs both ways round open.
			if link.x != link.z and link.y != link.w and (
					blocked.has(Vector4i(link.x, link.y, link.z, link.y))
					or blocked.has(Vector4i(link.x, link.y, link.x, link.w))
					or blocked.has(Vector4i(link.z, link.y, link.z, link.w))
					or blocked.has(Vector4i(link.x, link.w, link.z, link.w))):
				continue
		# Each pair of new ground points comes up once, so no need to check
		# whether they are joined already.
		astar.connect_points(id, other)


## Each staircase: a point on every tread's tile, from the foot to the
## floor above.
func _add_stairs() -> void:
	for n: int in _building.levels:
		var map := _building.levels[n]
		var above := _building.levels.get(n + 1) as BuildingMap
		for flight: Staircase in map.stairs.values():
			var base := map.floor_height(flight.cells[0])
			var previous := point_at(n, Vector2(flight.entry()) + Vector2(0.5, 0.5))
			var risers := 0
			for i in flight.cells.size():
				if not flight.landings[i]:
					risers += 2
				var middle := Vector2(flight.cells[i]) + Vector2(0.5, 0.5)
				var id := _add_point(Vector4i(0, 0, 0, -2), n,
						Vector3(middle.x, base + (risers - 1) * Staircase.RISE, middle.y))
				_join(previous, id)
				previous = id
			if above != null:
				_join(previous, point_at(n + 1, Vector2(flight.exit()) + Vector2(0.5, 0.5)))


## Each pair of stacked lifts: a point in the lift on each level, joined
## to each other and to the floor around them.
func _add_lifts() -> void:
	for link: Building.Link in _building.links():
		if link.kind != Building.Link.Kind.LIFT or link.from_level > link.to_level:
			continue
		var cars: Array[int] = []
		for pair: Array in [[link.from_level, link.from_cell], [link.to_level, link.to_cell]]:
			var n: int = pair[0]
			var cell: Vector2i = pair[1]
			var map := _building.levels[n]
			var middle := Vector2(cell) + Vector2(0.5, 0.5)
			var car := _add_point(Vector4i(0, 0, 0, -2), n,
					Vector3(middle.x, map.floor_height(cell), middle.y), LIFT_COST)
			cars.append(car)
			for d in BuildingMap.DIRECTIONS:
				if map.passable(BuildingMap.edge_between(cell, cell + d)):
					_join(car, point_at(n, middle + Vector2(d)))
		_join(cars[0], cars[1])


## Built paths: points along each stairway, ramp or bridge, joined at their
## ends to the ground or to each other.
func _add_built_paths() -> void:
	if _paths == null:
		return
	var ends: Dictionary[int, int] = {} # Path node: graph point, for raised nodes.
	for segment: PathNetwork.Segment in _paths.segments.values():
		if not segment.built:
			continue
		var length := _paths.length(segment)
		var count := maxi(1, ceili(length / PATH_STEP))
		var previous := -1
		for k in count + 1:
			var t := float(k) / count
			var spot := _paths.point_on(segment, t)
			var node := segment.a if k == 0 else (segment.b if k == count else -1)
			var id := -1
			if node != -1 and not _paths.heights.has(node):
				id = point_at(0, spot) # An end on the ground joins the ground.
			elif node != -1 and ends.has(node):
				id = ends[node]
			if id == -1:
				id = _add_point(Vector4i(0, 0, 0, -2), 0,
						Vector3(spot.x, _paths.height_on(segment, t), spot.y))
				if node != -1:
					ends[node] = id
			_join(previous, id)
			previous = id


func _join_diagonal(n: int, cell: Vector2i, d: Vector2i) -> void:
	var map := _building.levels[n]
	var corner := cell + d
	var a: int = _ids.get(Vector4i(n, cell.x, cell.y, 0), -1)
	var b: int = _ids.get(Vector4i(n, corner.x, corner.y, 0), -1)
	var side_x: int = _ids.get(Vector4i(n, cell.x + d.x, cell.y, 0), -1)
	var side_y: int = _ids.get(Vector4i(n, cell.x, cell.y + d.y, 0), -1)
	if a == -1 or b == -1 or side_x == -1 or side_y == -1:
		return
	if map.pieces(corner).size() != 1 or map.pieces(cell + Vector2i(d.x, 0)).size() != 1 \
			or map.pieces(cell + Vector2i(0, d.y)).size() != 1:
		return
	if astar.are_points_connected(a, side_x) and astar.are_points_connected(a, side_y) \
			and astar.are_points_connected(side_x, b) and astar.are_points_connected(side_y, b):
		_join(a, b)


## Locks or unlocks a door on a straight wall: locked, nobody walks
## through it. Doors in angled walls can't be locked yet.
func set_door_locked(level: int, edge: Vector3i, locked: bool) -> void:
	for pair: Vector2i in _door_links.get(Vector4i(level, edge.x, edge.y, edge.z), []):
		if locked:
			if astar.are_points_connected(pair.x, pair.y):
				astar.disconnect_points(pair.x, pair.y)
		else:
			_join(pair.x, pair.y)


## Every door on a straight wall that joins anything, as (level, edge x,
## edge y, edge axis).
func doors() -> Array[Vector4i]:
	return _door_links.keys()


## The points on a room's floor, for shutting it to people not allowed in.
func points_in(level: int, room: Room) -> Array[int]:
	var out: Array[int] = []
	for piece in room.pieces:
		var id: int = _ids.get(Vector4i(level, piece.x, piece.y, piece.z), -1)
		if id != -1:
			out.append(id)
	return out


## Shuts a point so routes go round it, or opens it again.
func set_point_shut(id: int, shut: bool) -> void:
	astar.set_point_disabled(id, shut)


func is_door_locked(level: int, edge: Vector3i) -> bool:
	var pairs: Array = _door_links.get(Vector4i(level, edge.x, edge.y, edge.z), [])
	return not pairs.is_empty() and not astar.are_points_connected(pairs[0].x, pairs[0].y)


func _note_door(key: Vector4i, a: int, b: int) -> void:
	if a == -1 or b == -1:
		return
	if not _door_links.has(key):
		_door_links[key] = []
	_door_links[key].append(Vector2i(a, b))


func _join(a: int, b: int) -> void:
	if a != -1 and b != -1 and a != b and not astar.are_points_connected(a, b):
		astar.connect_points(a, b)


## Is a spot taken up by an object people walk round?
func _blocked(map: BuildingMap, spot: Vector2) -> bool:
	return map.blocks_at(spot)


func _floor_height(map: BuildingMap, spot: Vector2) -> float:
	var cell := Vector2i(spot.floor())
	var ramp := map.ramp_at(cell)
	return ramp.height_at(spot) if ramp != null else map.floor_height(cell)


## The height where a point's tile meets its neighbour in direction `side`.
func _edge_height_of(id: int, n: int, cell: Vector2i, side: Vector2i) -> float:
	var map := _building.levels[n]
	if map.has_floor(cell):
		return map.edge_height(cell, side)
	return position_of(id).y


func _ground(spot: Vector2) -> float:
	return _terrain.height_at(spot) if _terrain != null else 0.0


## Tiles of ground a ground path covers.
func _path_cells() -> Dictionary[Vector2i, bool]:
	var out: Dictionary[Vector2i, bool] = {}
	if _paths == null:
		return out
	for segment: PathNetwork.Segment in _paths.segments.values():
		if segment.built:
			continue
		for spot in _paths.sample(segment, 0.25):
			out[Vector2i(spot.floor())] = true
	return out
