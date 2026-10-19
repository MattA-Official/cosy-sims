class_name PathNetwork
extends RefCounted
## Paths and roads drawn as curves, off the tile grid, like Cities:
## Skylines 2. Nodes are points in tile units; each segment joins two nodes
## along a quadratic Bézier curve bent by one control point. Segments that
## share a node form a junction there.
##
## Ends dropped near an existing node join it, and ends dropped on the
## middle of a segment split it to make a junction.

signal changed

## How close, in tiles, an end must be to a node or segment to join it.
const SNAP_DISTANCE := 0.6


class Segment:
	var id: int
	var a: int ## Node ids.
	var b: int
	var control: Vector2
	var style: StringName


var nodes: Dictionary[int, Vector2] = {}
var segments: Dictionary[int, Segment] = {}

var _next_node := 1
var _next_segment := 1


func node_position(node: int) -> Vector2:
	return nodes[node]


## The nearest node within `radius`, or -1.
func node_near(position: Vector2, radius := SNAP_DISTANCE) -> int:
	var best := -1
	var best_distance := radius
	for node: int in nodes:
		var distance := nodes[node].distance_to(position)
		if distance <= best_distance:
			best = node
			best_distance = distance
	return best


func segments_at(node: int) -> Array[Segment]:
	var out: Array[Segment] = []
	for segment: Segment in segments.values():
		if segment.a == node or segment.b == node:
			out.append(segment)
	return out


## Where an end dropped at `position` would go: onto a nearby node, onto a
## nearby segment, or where it is.
func snap(position: Vector2) -> Vector2:
	var node := node_near(position)
	if node != -1:
		return nodes[node]
	var hit := closest(position)
	if not hit.is_empty() and hit[2] <= SNAP_DISTANCE:
		return point_on(hit[0], hit[1])
	return position


## Adds a segment between two points, joining or splitting whatever the
## ends land on. A null control makes it straight. Returns the new segment.
func add_segment(from: Vector2, to: Vector2, control: Variant = null,
		style: StringName = &"") -> Segment:
	var a := _node_at(from)
	var b := _node_at(to)
	if a == b:
		return null
	var segment := Segment.new()
	segment.id = _next_segment
	_next_segment += 1
	segment.a = a
	segment.b = b
	segment.control = control if control != null else (nodes[a] + nodes[b]) * 0.5
	segment.style = style
	segments[segment.id] = segment
	changed.emit()
	return segment


## Removes a segment, and any node it leaves with nothing attached.
func remove_segment(id: int) -> bool:
	var segment: Segment = segments.get(id)
	if segment == null:
		return false
	segments.erase(id)
	for node in [segment.a, segment.b]:
		if segments_at(node).is_empty():
			nodes.erase(node)
	changed.emit()
	return true


## Removes every segment that runs through a rectangle (in tile units),
## for example when a building goes up over it. Ends that only touch the
## edge, such as at a door, are kept.
func remove_in_rect(rect: Rect2) -> int:
	var inner := rect.grow(-0.3)
	var doomed: Array[int] = []
	for segment: Segment in segments.values():
		for p in sample(segment, 0.25):
			if inner.has_point(p):
				doomed.append(segment.id)
				break
	for id in doomed:
		remove_segment(id)
	return doomed.size()


## Splits a segment in two at `t` (0 to 1), keeping its shape. Returns the
## node in the middle.
func split(segment: Segment, t: float) -> int:
	var a := nodes[segment.a]
	var b := nodes[segment.b]
	var c := segment.control
	var left := a.lerp(c, t)
	var right := c.lerp(b, t)
	var middle := add_node(left.lerp(right, t))
	var second := Segment.new()
	second.id = _next_segment
	_next_segment += 1
	second.a = middle
	second.b = segment.b
	second.control = right
	second.style = segment.style
	segments[second.id] = second
	segment.b = middle
	segment.control = left
	changed.emit()
	return middle


func add_node(position: Vector2) -> int:
	var id := _next_node
	_next_node += 1
	nodes[id] = position
	return id


func point_on(segment: Segment, t: float) -> Vector2:
	return bezier(nodes[segment.a], segment.control, nodes[segment.b], t)


static func bezier(a: Vector2, control: Vector2, b: Vector2, t: float) -> Vector2:
	return a.lerp(control, t).lerp(control.lerp(b, t), t)


## Points along a segment about `spacing` tiles apart, both ends included.
func sample(segment: Segment, spacing := 0.5) -> PackedVector2Array:
	return sample_curve(nodes[segment.a], segment.control, nodes[segment.b], spacing)


static func sample_curve(a: Vector2, control: Vector2, b: Vector2, spacing := 0.5) -> PackedVector2Array:
	# The control polygon is at least as long as the curve, so it gives a
	# safe number of steps.
	var rough := a.distance_to(control) + control.distance_to(b)
	var steps := maxi(1, ceili(rough / spacing))
	var out := PackedVector2Array()
	for i in steps + 1:
		out.append(bezier(a, control, b, float(i) / steps))
	return out


func length(segment: Segment) -> float:
	var points := sample(segment, 0.25)
	var total := 0.0
	for i in range(1, points.size()):
		total += points[i - 1].distance_to(points[i])
	return total


## The segment nearest a point, as [segment, t, distance], or [] if there
## are none.
func closest(position: Vector2) -> Array:
	var best: Array = []
	for segment: Segment in segments.values():
		var points := sample(segment, 0.25)
		for i in points.size():
			var distance := points[i].distance_to(position)
			if best.is_empty() or distance < best[2]:
				best = [segment, float(i) / (points.size() - 1), distance]
	return best


## The node for an end at `position`: an existing node, a new junction on a
## segment, or a new node.
func _node_at(position: Vector2) -> int:
	var node := node_near(position)
	if node != -1:
		return node
	var hit := closest(position)
	if not hit.is_empty() and hit[2] <= SNAP_DISTANCE and hit[1] > 0.0 and hit[1] < 1.0:
		return split(hit[0], hit[1])
	return add_node(position)
