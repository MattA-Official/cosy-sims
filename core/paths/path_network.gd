class_name PathNetwork
extends RefCounted
## Paths and roads drawn as curves, off the tile grid, like Cities:
## Skylines 2. Nodes are points in tile units; each segment joins two nodes
## along a quadratic Bézier curve bent by one control point. Segments that
## share a node form a junction there.
##
## Ends dropped near an existing node join it, and ends dropped on the
## middle of a segment split it to make a junction.
##
## Most segments lie on the ground and follow it. Built segments (stairs,
## ramps and bridges) run straight from the height of one end to the
## other; nodes off the ground keep their height in `heights`.

signal changed

## How close, in tiles, an end must be to a node or segment to join it.
const SNAP_DISTANCE := 0.6
## How far apart in height two crossing paths must be for one to pass over
## the other rather than meet at a junction. People are about 0.9 m tall.
const PASS_UNDER := 1.0


class Segment:
	var id: int
	var a: int ## Node ids.
	var b: int
	var control: Vector2
	var style: StringName
	## Runs straight between its ends' heights instead of following the ground.
	var built := false


## The ground the paths lie on. Without it the ground is flat at 0.
var terrain: Terrain
var nodes: Dictionary[int, Vector2] = {}
## Heights of nodes that sit off the ground, such as the ends of a bridge.
## Other nodes are on the ground.
var heights: Dictionary[int, float] = {}
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


## The height of whatever an end at `position` snaps onto, or NAN if that
## is the ground. An end snapped onto the middle of a bridge takes the
## bridge's height there, so it joins the bridge rather than passing under.
func snap_height(position: Vector2) -> float:
	var node := node_near(position)
	if node != -1:
		return heights.get(node, NAN)
	var hit := _partway(position)
	if hit.is_empty():
		return NAN
	var height := height_on(hit[0], hit[1])
	return height if absf(height - _ground(position)) >= PASS_UNDER else NAN


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
## ends land on. A null control makes it straight. Built segments give
## their new ends a height (NAN for on the ground); existing nodes keep
## theirs. Paths it crosses at about the same height join it at a new
## junction. Returns the new segment, the part nearest `from` if it was
## split.
func add_segment(from: Vector2, to: Vector2, control: Variant = null,
		style: StringName = &"", built := false, from_height := NAN, to_height := NAN) -> Segment:
	var bend: Vector2 = control if control != null else (from + to) * 0.5
	var crossed := crossings(from, bend, to, built, from_height, to_height)
	var a := _node_at(from, from_height)
	var b := _node_at(to, to_height)
	if a == b:
		return null
	for pair: Array in [[a, from_height], [b, to_height]]:
		if not is_nan(pair[1]) and not heights.has(pair[0]) and _is_new(pair[0]):
			heights[pair[0]] = pair[1]
	var segment := Segment.new()
	segment.id = _next_segment
	_next_segment += 1
	segment.a = a
	segment.b = b
	segment.control = bend
	segment.style = style
	segment.built = built
	segments[segment.id] = segment
	# Join each path it crosses, furthest first so the earlier splits keep
	# their place along what is left.
	crossed.sort_custom(func(x: Array, y: Array) -> bool: return x[2] > y[2])
	var scale := 1.0
	var pieces: Dictionary[int, Array] = {} # A crossed segment's id: the pieces it is now in.
	for hit: Array in crossed:
		var other: Segment = hit[0]
		var parts: Array = pieces.get_or_add(other.id, [other])
		# The segment may already have been split at another crossing.
		var best: Array = []
		for part: Segment in parts:
			var points := sample(part, 0.1)
			for i in points.size():
				var distance := points[i].distance_to(hit[3])
				if best.is_empty() or distance < best[2]:
					best = [part, float(i) / (points.size() - 1), distance]
		if best[1] <= 0.0 or best[1] >= 1.0:
			continue
		var count := segments.size()
		var junction := split(best[0], best[1])
		parts.append(segments.values()[count])
		split(segment, hit[2] / scale, junction)
		scale = hit[2]
	changed.emit()
	return segment


## Where a new curve would cross existing paths at about the same height,
## as [segment, t along it, t along the new curve]. Crossings near the
## new curve's ends are left out, as those ends join the path anyway.
func crossings(a: Vector2, control: Vector2, b: Vector2, built := false, from_height := NAN,
		to_height := NAN) -> Array:
	var out: Array = []
	var mine := sample_curve(a, control, b, 0.25)
	for segment: Segment in segments.values():
		var theirs := sample(segment, 0.25)
		for i in mine.size() - 1:
			for j in theirs.size() - 1:
				var hit: Variant = Geometry2D.segment_intersects_segment(mine[i], mine[i + 1],
						theirs[j], theirs[j + 1])
				if hit == null:
					continue
				var point: Vector2 = hit
				if point.distance_to(a) < SNAP_DISTANCE or point.distance_to(b) < SNAP_DISTANCE:
					continue
				var t_new := (i + mine[i].distance_to(point) / maxf(mine[i].distance_to(mine[i + 1]), 0.0001)) \
						/ (mine.size() - 1)
				var t_old := (j + theirs[j].distance_to(point) / maxf(theirs[j].distance_to(theirs[j + 1]), 0.0001)) \
						/ (theirs.size() - 1)
				if t_old <= 0.0 or t_old >= 1.0:
					continue
				var mine_height := curve_height(a, b, t_new, terrain, built, from_height, to_height, control)
				var their_height := height_on(segment, t_old)
				var seen := out.any(func(other: Array) -> bool: return other[3].distance_to(point) < 0.5)
				if absf(mine_height - their_height) < PASS_UNDER and not seen:
					out.append([segment, t_old, t_new, point])
	return out


## The height of a point partway along a segment: the ground, or for
## built segments, straight between its ends.
func height_on(segment: Segment, t: float) -> float:
	return curve_height(nodes[segment.a], nodes[segment.b], t, terrain, segment.built,
			heights.get(segment.a, NAN), heights.get(segment.b, NAN), segment.control)


## The height of a node: its own if it has one, otherwise the ground.
func node_height(node: int) -> float:
	if heights.has(node):
		return heights[node]
	return _ground(nodes[node])


## The height partway along a curve. Ends without a height are on the
## ground.
static func curve_height(a: Vector2, b: Vector2, t: float, ground: Terrain, built: bool,
		from_height := NAN, to_height := NAN, control: Variant = null) -> float:
	var ground_a := ground.height_at(a) if ground != null else 0.0
	var ground_b := ground.height_at(b) if ground != null else 0.0
	if not built:
		var bend: Vector2 = control if control != null else (a + b) * 0.5
		var point := bezier(a, bend, b, t)
		return ground.height_at(point) if ground != null else 0.0
	var h0 := from_height if not is_nan(from_height) else ground_a
	var h1 := to_height if not is_nan(to_height) else ground_b
	return lerpf(h0, h1, t)


## Removes a segment, and any node it leaves with nothing attached.
func remove_segment(id: int) -> bool:
	var segment: Segment = segments.get(id)
	if segment == null:
		return false
	segments.erase(id)
	for node in [segment.a, segment.b]:
		if segments_at(node).is_empty():
			nodes.erase(node)
			heights.erase(node)
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
## node in the middle: a new one, or `at` if given, such as where two paths
## cross.
func split(segment: Segment, t: float, at := -1) -> int:
	var a := nodes[segment.a]
	var b := nodes[segment.b]
	var c := segment.control
	var left := a.lerp(c, t)
	var right := c.lerp(b, t)
	var middle := at if at != -1 else add_node(left.lerp(right, t))
	if segment.built and at == -1:
		heights[middle] = height_on(segment, t)
	var second := Segment.new()
	second.id = _next_segment
	_next_segment += 1
	second.a = middle
	second.b = segment.b
	second.control = right
	second.style = segment.style
	second.built = segment.built
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


## The way a segment leaves one of its nodes, aimed at the point `reach`
## tiles along it so a curve's bend is taken into account.
func direction_from(segment: Segment, node: int, reach := 1.0) -> Vector2:
	var points := sample(segment, 0.1)
	if node == segment.b:
		points.reverse()
	var here := points[0]
	for p in points:
		if p.distance_to(here) >= reach:
			return (p - here).normalized()
	return (points[-1] - here).normalized()


## Has nothing been attached to this node yet?
func _is_new(node: int) -> bool:
	return segments_at(node).is_empty()


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
## segment, or a new node. An end only splits a path partway at about its
## own height (`height`, or the ground when NAN): a path on the ground
## ending under a bridge stays on the ground rather than joining it in
## mid-air. Ends on an existing node join it unless given a height well
## away from the node's.
func _node_at(position: Vector2, height := NAN) -> int:
	var node := node_near(position)
	if node != -1 and (is_nan(height) or absf(node_height(node) - height) < PASS_UNDER):
		return node
	if is_nan(height):
		height = _ground(position)
	var hit := _partway(position)
	if not hit.is_empty() and absf(height_on(hit[0], hit[1]) - height) < PASS_UNDER:
		return split(hit[0], hit[1])
	return add_node(position)


## The segment an end at `position` would land partway along, as [segment,
## t, distance], or [] if it is near none or only near an end.
func _partway(position: Vector2) -> Array:
	var hit := closest(position)
	if hit.is_empty() or hit[2] > SNAP_DISTANCE or hit[1] <= 0.0 or hit[1] >= 1.0:
		return []
	return hit


func _ground(position: Vector2) -> float:
	return terrain.height_at(position) if terrain != null else 0.0
