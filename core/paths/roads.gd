class_name Roads
extends RefCounted
## The roads among the paths, for vehicles: buses, lorries and cars drive
## only on paths of a road style, coming in from the edge of the map.

var paths: PathNetwork
## Path styles vehicles may drive on.
var styles: Array[StringName] = [&"road"]
## The whole map, in tiles: roads reaching its edge are where vehicles
## come from.
var bounds: Rect2i
## How close to the map's edge, in tiles, a road's end must be to lead off
## it.
const EDGE := 1.5


func is_road(segment: PathNetwork.Segment) -> bool:
	return styles.has(segment.style)


func has_roads() -> bool:
	return paths.segments.values().any(is_road)


## Road ends at the edge of the map, where vehicles come and go.
func edge_nodes() -> Array[int]:
	var out: Array[int] = []
	var inner := Rect2(bounds).grow(-EDGE)
	for node: int in paths.nodes:
		if not inner.has_point(paths.nodes[node]) and paths.segments_at(node).any(is_road):
			out.append(node)
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


## The way in by road from the edge of the map to the road point nearest
## `to`, as points in tile units, or empty if no road from the edge gets
## there.
func route_in(to: Vector2) -> PackedVector2Array:
	var hit := nearest(to)
	if hit.is_empty():
		return PackedVector2Array()
	var segment: PathNetwork.Segment = hit[0]
	var t: float = hit[1]
	var distances := _distances_from_edge()
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


## Each node reachable by road from the map's edge: [distance, previous
## node or -1, segment there or null].
func _distances_from_edge() -> Dictionary:
	var out := {}
	var open: Array[int] = []
	for node in edge_nodes():
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


## The points from the edge to a node, following the shortest roads.
func _walk_back(distances: Dictionary, node: int) -> PackedVector2Array:
	var chain: Array[PackedVector2Array] = []
	while distances[node][1] != -1:
		var segment: PathNetwork.Segment = distances[node][2]
		var points := paths.sample(segment, 0.5)
		if segment.a == node:
			points.reverse()
		chain.push_front(points)
		node = distances[node][1]
	var out := PackedVector2Array([paths.nodes[node]])
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
