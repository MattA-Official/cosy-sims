class_name Roads
extends RefCounted
## The roads among the paths, for vehicles: buses, lorries and cars drive
## only on paths of a road style. A road that ends at the edge of your
## land goes on into a tunnel, and that is where vehicles come and go.

var paths: PathNetwork
## Path styles vehicles may drive on.
var styles: Array[StringName] = [&"road"]
## Your land, in tiles: road ends on its edge lead into tunnels.
var bounds: Rect2i
## How close to the edge, in tiles, a road's end must be to lead into a
## tunnel.
const EDGE := 1.5
## How far into the tunnel vehicles start and finish, out of sight.
const TUNNEL := 4.0


func is_road(segment: PathNetwork.Segment) -> bool:
	return styles.has(segment.style)


func has_roads() -> bool:
	return paths.segments.values().any(is_road)


## Road ends at the edge of your land, each the mouth of a tunnel.
func edge_nodes() -> Array[int]:
	var out: Array[int] = []
	var inner := Rect2(bounds).grow(-EDGE)
	for node: int in paths.nodes:
		var at := paths.segments_at(node)
		if not inner.has_point(paths.nodes[node]) and at.size() == 1 and is_road(at[0]):
			out.append(node)
	return out


## The way out of the land from a road end: straight on from the road.
func outward(node: int) -> Vector2:
	var segment: PathNetwork.Segment = paths.segments_at(node)[0]
	var points := paths.sample(segment, 0.5)
	if segment.a != node:
		points.reverse()
	return (points[0] - points[mini(1, points.size() - 1)]).normalized()


## Where vehicles start and finish inside a tunnel.
func tunnel_end(node: int) -> Vector2:
	return paths.nodes[node] + outward(node) * TUNNEL


## A way right through, in one tunnel and out of another, or empty if
## there aren't two tunnels joined by road.
func route_through(rng: RandomNumberGenerator) -> PackedVector2Array:
	var ends := edge_nodes()
	if ends.size() < 2:
		return PackedVector2Array()
	var from := ends[rng.randi() % ends.size()]
	var distances := _distances_from([from])
	var others := ends.filter(func(node: int) -> bool: return node != from and distances.has(node))
	if others.is_empty():
		return PackedVector2Array()
	var to: int = others[rng.randi() % others.size()]
	var out := _walk_back(distances, to)
	out.append(tunnel_end(to))
	return out


## The point on a road nearest `point`, as [segment, t, distance], or [].
func nearest(point: Vector2) -> Array:
	var best: Array = []
	for segment: PathNetwork.Segment in paths.segments.values():
		if not is_road(segment):
			continue
		var points := paths.sample(segment, 0.25)
		for i in points.size():
			var distance := points[i].distance_to(point)
			if best.is_empty() or distance < best[2]:
				best = [segment, float(i) / (points.size() - 1), distance]
	return best


## The way in by road from a tunnel to the road point nearest
## `to`, as points in tile units, or empty if no road from the edge gets
## there.
func route_in(to: Vector2) -> PackedVector2Array:
	var hit := nearest(to)
	if hit.is_empty():
		return PackedVector2Array()
	var segment: PathNetwork.Segment = hit[0]
	var t: float = hit[1]
	var distances := _distances_from(edge_nodes())
	var best := PackedVector2Array()
	var best_length := INF
	# In from whichever end of the nearest road is closer to the edge.
	for end: int in [segment.a, segment.b]:
		if not distances.has(end):
			continue
		var part := _partial(segment, end, t)
		var length: float = distances[end][0] + _length(part)
		if length < best_length:
			best_length = length
			best = _walk_back(distances, end)
			best.append_array(part.slice(1))
	return best


## Each node reachable by road from the given ones: [distance, previous
## node or -1, segment there or null].
func _distances_from(starts: Array[int]) -> Dictionary:
	var out := {}
	var open: Array[int] = []
	for node in starts:
		out[node] = [0.0, -1, null]
		open.append(node)
	while not open.is_empty():
		open.sort_custom(func(a: int, b: int) -> bool: return out[a][0] < out[b][0])
		var node: int = open.pop_front()
		for segment in paths.segments_at(node):
			if not is_road(segment):
				continue
			var other := segment.b if segment.a == node else segment.a
			var distance: float = out[node][0] + paths.length(segment)
			if not out.has(other) or distance < out[other][0]:
				out[other] = [distance, node, segment]
				if not open.has(other):
					open.append(other)
	return out


## The points from inside a tunnel to a node, following the shortest roads.
func _walk_back(distances: Dictionary, node: int) -> PackedVector2Array:
	var chain: Array[PackedVector2Array] = []
	while distances[node][1] != -1:
		var segment: PathNetwork.Segment = distances[node][2]
		var points := paths.sample(segment, 0.5)
		if segment.a == node:
			points.reverse()
		chain.push_front(points)
		node = distances[node][1]
	var out := PackedVector2Array([tunnel_end(node), paths.nodes[node]])
	for points in chain:
		out.append_array(points.slice(1))
	return out


## Points along a segment from one of its ends to `t`.
func _partial(segment: PathNetwork.Segment, from: int, t: float) -> PackedVector2Array:
	var points := paths.sample(segment, 0.5)
	var count := roundi(t * (points.size() - 1))
	if from == segment.a:
		return points.slice(0, count + 1)
	points.reverse()
	return points.slice(0, points.size() - count)


static func _length(points: PackedVector2Array) -> float:
	var total := 0.0
	for i in range(1, points.size()):
		total += points[i - 1].distance_to(points[i])
	return total


## Smooths the ground along a straight road from a to b (tiles) so it
## doesn't bump over every lump: the corners under it follow a gently
## eased line of the ground's height, blending back into the ground over
## `blend` tiles either side. Corners `keep` says yes to are left alone.
static func grade(terrain: Terrain, a: Vector2, b: Vector2, half: float, keep: Callable, blend := 2.0) -> void:
	var length := a.distance_to(b)
	if length < 0.01:
		return
	var along := (b - a) / length
	var side := Vector2(-along.y, along.x)
	var stations := ceili(length) + 1
	var profile: Array[float] = []
	for i in stations:
		var at := a + along * minf(i, length)
		var sum := 0.0
		for k in 5:
			sum += terrain.height_at(at + side * lerpf(-half, half, k / 4.0))
		profile.append(sum / 5.0)
	# Ease it: a wide running average, a few times over.
	for pass_count in 3:
		var eased: Array[float] = []
		for i in stations:
			var sum := 0.0
			var count := 0
			for k in range(maxi(i - 6, 0), mini(i + 7, stations)):
				sum += profile[k]
				count += 1
			eased.append(sum / count)
		profile = eased
	var reach := half + 0.5 + blend
	var lo := Vector2i((Vector2(minf(a.x, b.x), minf(a.y, b.y)) - Vector2.ONE * reach).floor())
	var hi := Vector2i((Vector2(maxf(a.x, b.x), maxf(a.y, b.y)) + Vector2.ONE * reach).ceil())
	var heights := {}
	for z in range(lo.y, hi.y + 1):
		for x in range(lo.x, hi.x + 1):
			var corner := Vector2i(x, z)
			if not terrain.in_bounds(corner) or (keep.is_valid() and keep.call(corner)):
				continue
			var t := clampf((Vector2(corner) - a).dot(along), 0.0, length)
			var away := absf((Vector2(corner) - a).dot(side))
			if away > reach or (Vector2(corner) - a).dot(along) < -0.5 or (Vector2(corner) - a).dot(along) > length + 0.5:
				continue
			var i := mini(floori(t), stations - 2) if stations > 1 else 0
			var target := lerpf(profile[i], profile[mini(i + 1, stations - 1)], t - i)
			var share := clampf((away - half - 0.5) / blend, 0.0, 1.0)
			heights[corner] = lerpf(target, terrain.corner_height(corner), share * share)
	terrain.set_corners(heights)
