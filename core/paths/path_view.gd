class_name PathView
extends Node3D
## Draws a PathNetwork: each segment as a strip of blocks that follows the
## ground, or for built paths, stairs, ramps and bridges. Where paths meet,
## the corners between them are filled with smooth curves.

@export var terrain: Terrain
@export var styles: Array[PathStyleDef] = []
## How far the path's surface sits above the ground.
@export var lift := 0.05
@export var bridge_colour := Color(0.6, 0.45, 0.32)
## How far the curve at a junction reaches along each path's edge.
@export var corner_radius := 0.6

var network: PathNetwork:
	set(value):
		if network != null:
			network.changed.disconnect(queue_rebuild)
		network = value
		if network != null:
			network.changed.connect(queue_rebuild)
		queue_rebuild()

var _mesh := MeshInstance3D.new()
var _material := MeshShapes.vertex_colour_material()
var _rebuild_queued := false


func _init() -> void:
	add_child(_mesh)


func _ready() -> void:
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mesh.material_override = _material
	if terrain != null:
		terrain.changed.connect(queue_rebuild)
		if terrain.water != null:
			terrain.water.changed.connect(queue_rebuild)


func style(id: StringName) -> PathStyleDef:
	for def in styles:
		if def.id == id:
			return def
	return styles[0] if not styles.is_empty() else null


func queue_rebuild() -> void:
	if _rebuild_queued:
		return
	_rebuild_queued = true
	rebuild.call_deferred()


func rebuild() -> void:
	_rebuild_queued = false
	if network == null or not is_inside_tree():
		return
	if network.segments.is_empty():
		_mesh.mesh = null
		return
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for segment: PathNetwork.Segment in network.segments.values():
		var def := style(segment.style)
		add_curve(st, network.sample(segment), def, Color(1, 1, 1, 1), segment.built,
				network.heights.get(segment.a, NAN), network.heights.get(segment.b, NAN))
	for node: int in network.nodes:
		_add_corners(st, node)
	_mesh.mesh = st.commit()


## Adds one curve's geometry. Also used by the drawing tool's preview.
func add_curve(st: SurfaceTool, points: PackedVector2Array, def: PathStyleDef,
		tint := Color(1, 1, 1, 1), built := false, from_height := NAN, to_height := NAN) -> void:
	var profile := PathProfile.build(points, terrain, built, from_height, to_height)
	var half := (def.width if def != null else 1.5) * 0.5
	var colour := (def.colour if def != null else Color.TAN) * tint
	var edge := (def.edge_colour if def != null else Color.SADDLE_BROWN) * tint
	var wood := bridge_colour * tint
	# Wider paths sit a hair higher, so where two styles overlap at a
	# junction the wider one shows rather than flickering.
	var raised := lift + half * 0.004
	if profile.steps > 0:
		_add_steps(st, profile, half, colour, edge)
		return
	# Cross-sections square to the curve at each point, shared by the
	# stretches either side so bends have no gaps or notches.
	var sides := _sides(points, half)
	for i in profile.kinds.size():
		var p0 := points[i]
		var p1 := points[i + 1]
		var h0 := profile.heights[i]
		var h1 := profile.heights[i + 1]
		match profile.kinds[i]:
			PathProfile.Kind.GROUND when not built:
				var top0 := _hugged(p0, sides[i]) + raised
				var top1 := _hugged(p1, sides[i + 1]) + raised
				_add_section(st, p0 - sides[i], p0 + sides[i], p1 + sides[i + 1], p1 - sides[i + 1],
						top0, top1, minf(h0, h1) - 0.3, colour, edge)
			PathProfile.Kind.GROUND:
				var low := minf(_ground(p0), _ground(p1)) - 0.3
				_add_section(st, p0 - sides[i], p0 + sides[i], p1 + sides[i + 1], p1 - sides[i + 1],
						h0 + raised, h1 + raised, low, colour, edge)
			_:
				_add_bridge(st, p0, p1, half, h0 + raised, h1 + raised, wood)


## A block whose ends are the cross-sections at p0 and p1 (tile units).
## The top slopes from top0 to top1; the bottom is flat at `bottom`.
func add_block(st: SurfaceTool, p0: Vector2, p1: Vector2, half: float, top0: float,
		top1: float, bottom: float, top_colour: Color, side_colour: Color) -> void:
	var dir := (p1 - p0).normalized()
	if dir == Vector2.ZERO:
		return
	var side := Vector2(-dir.y, dir.x) * half
	_add_section(st, p0 - side, p0 + side, p1 + side, p1 - side, top0, top1, bottom,
			top_colour, side_colour)


## A block between two cross-sections: left and right at the start (l0, r0)
## and at the end (r1, l1), in tile units.
func _add_section(st: SurfaceTool, l0: Vector2, r0: Vector2, r1: Vector2, l1: Vector2,
		top0: float, top1: float, bottom: float, top_colour: Color, side_colour: Color) -> void:
	var cs := terrain.cell_size if terrain != null else 1.0
	var corners := [l0, r0, r1, l1]
	var tops := [top0, top0, top1, top1]
	var up: Array[Vector3] = []
	var down: Array[Vector3] = []
	for k in 4:
		var c: Vector2 = corners[k] * cs
		up.append(Vector3(c.x, tops[k], c.y))
		down.append(Vector3(c.x, bottom, c.y))
	_quad(st, up[0], up[1], up[2], up[3], top_colour, Vector3.UP)
	var middle := (up[0] + up[2]) * 0.5
	for k in 4:
		var n := (k + 1) % 4
		var outward := (up[k] + up[n]) * 0.5 - middle
		outward.y = 0.0
		_quad(st, up[k], up[n], down[n], down[k], side_colour, outward)


## The height a strip needs here to sit on the ground without sinking into
## it across a slope. `side` reaches from the middle to one edge.
func _hugged(point: Vector2, side: Vector2) -> float:
	if terrain == null:
		return 0.0
	return maxf(terrain.height_at(point), maxf(terrain.height_at(point + side),
			terrain.height_at(point - side)))


## Stairs along a path: every step rises the same, the same height as
## stairs indoors, with the treads spread evenly along the curve.
func _add_steps(st: SurfaceTool, profile: PathProfile, half: float, colour: Color,
		edge: Color) -> void:
	var points := profile.points
	var h0 := profile.heights[0]
	var h1 := profile.heights[-1]
	var count := profile.steps
	var rise := (h1 - h0) / count
	var lengths := PackedFloat32Array([0.0])
	for i in range(1, points.size()):
		lengths.append(lengths[-1] + points[i - 1].distance_to(points[i]))
	var total := lengths[-1]
	var sides := _sides(points, half)
	var low := INF
	for p in points:
		low = minf(low, _ground(p))
	low -= 0.3
	for k in count:
		# Going up, each tread is at the top of its riser; going down, the
		# riser comes at the far end of the tread.
		var tread := h0 + rise * (k + 1) if rise > 0.0 else h0 + rise * k
		var from := total * k / count
		var to := total * (k + 1) / count
		for i in points.size() - 1:
			var start := maxf(from, lengths[i])
			var end := minf(to, lengths[i + 1])
			if end - start < 0.001:
				continue
			var span := maxf(lengths[i + 1] - lengths[i], 0.0001)
			var u0 := (start - lengths[i]) / span
			var u1 := (end - lengths[i]) / span
			var a := points[i].lerp(points[i + 1], u0)
			var b := points[i].lerp(points[i + 1], u1)
			var side_a := sides[i].lerp(sides[i + 1], u0)
			var side_b := sides[i].lerp(sides[i + 1], u1)
			_add_section(st, a - side_a, a + side_a, b + side_b, b - side_b, tread + lift,
					tread + lift, low, colour.lightened(0.05 * (k % 2)), edge)


func _add_bridge(st: SurfaceTool, p0: Vector2, p1: Vector2, half: float, top0: float,
		top1: float, wood: Color) -> void:
	add_block(st, p0, p1, half, top0, top1, minf(top0, top1) - 0.2, wood, wood.darkened(0.2))
	var dir := (p1 - p0).normalized()
	var side := Vector2(-dir.y, dir.x)
	# Rails along both edges.
	for s in [-1.0, 1.0]:
		var offset: Vector2 = side * (half - 0.05) * s
		add_block(st, p0 + offset, p1 + offset, 0.05, top0 + 0.35, top1 + 0.35, minf(top0, top1),
				wood.darkened(0.15), wood.darkened(0.15))
	# A pier under the start of every other stretch keeps it from floating.
	if terrain != null and int(p0.x * 7.0 + p0.y * 13.0) % 2 == 0:
		var ground := terrain.height_at(p0) - 0.5
		add_block(st, p0 - dir * 0.1, p0 + dir * 0.1, half * 0.6, top0 - 0.2, top0 - 0.2, ground,
				wood.darkened(0.3), wood.darkened(0.3))


## Fills the corners where paths meet at a node: a curve between each
## pair of neighbouring paths on the inside of the turn, and a rounded edge
## round the outside of a bend.
func _add_corners(st: SurfaceTool, node: int) -> void:
	var attached := network.segments_at(node)
	if attached.size() < 2:
		return
	var centre := network.node_position(node)
	var arms: Array = [] # [direction, half width, def]
	for segment in attached:
		var def := style(segment.style)
		arms.append([network.direction_from(segment, node), (def.width if def != null else 1.5) * 0.5, def])
	arms.sort_custom(func(x: Array, y: Array) -> bool: return x[0].angle() < y[0].angle())
	var widest: PathStyleDef = null
	var top := -INF
	for arm: Array in arms:
		if widest == null or (arm[2] != null and arm[2].width > widest.width):
			widest = arm[2]
		top = maxf(top, _hugged(centre, Vector2(arm[0]).orthogonal() * arm[1]))
	var colour := widest.colour if widest != null else Color.TAN
	var edge := widest.edge_colour if widest != null else Color.SADDLE_BROWN
	var bottom := _ground(centre) - 0.3
	if network.heights.has(node):
		top = network.heights[node]
		# Off the ground, the corner is part of a bridge deck.
		if top - _ground(centre) > PathProfile.BRIDGE_HEIGHT:
			colour = bridge_colour
			edge = bridge_colour.darkened(0.2)
			bottom = top - 0.2
	top += lift + (widest.width * 0.5 if widest != null else 0.75) * 0.004 + 0.002
	for i in arms.size():
		var u1: Vector2 = arms[i][0]
		var u2: Vector2 = arms[(i + 1) % arms.size()][0]
		var h1: float = arms[i][1]
		var h2: float = arms[(i + 1) % arms.size()][1]
		var turn := fposmod(u2.angle() - u1.angle(), TAU)
		# Each arm's edge on the side facing the next arm round.
		var n1 := Vector2(-u1.y, u1.x)
		var n2 := Vector2(-u2.y, u2.x)
		var e1 := centre + n1 * h1
		var e2 := centre - n2 * h2
		var outline := PackedVector2Array()
		if turn < PI - 0.05:
			# The edges meet at a sharp inside corner; round it off.
			var meet: Variant = Geometry2D.line_intersects_line(e1, u1, e2, u2)
			if meet == null:
				continue
			var corner: Vector2 = meet
			# Paths of different widths can meet so the corner falls behind
			# the node; there is no gap to fill then.
			var reach := maxf(h1, h2) * 2.0
			if (corner - e1).dot(u1) < 0.0 or (corner - e2).dot(u2) < 0.0:
				continue
			# Paths meeting at a shallow angle already overlap well past the
			# node; a long thin wedge would only stick out where they curve.
			if (corner - e1).dot(u1) > reach or (corner - e2).dot(u2) > reach:
				continue
			var q1 := corner + u1 * corner_radius
			var q2 := corner + u2 * corner_radius
			outline.append(corner)
			for k in 9:
				outline.append(PathNetwork.bezier(q1, corner, q2, k / 8.0))
		elif turn > PI + 0.05:
			# A gap round the outside of a bend; fill it with an arc.
			outline.append(centre)
			var from := n1.angle()
			var sweep := turn - PI
			var radius := maxf(h1, h2)
			for k in 9:
				outline.append(centre + Vector2.from_angle(from + sweep * k / 8.0) * radius)
		else:
			continue
		_add_fan(st, outline, top, bottom, colour, edge)


## A flat piece of path: a fan of triangles from the first point, with
## kerbs down to `bottom` round the rest of the outline.
func _add_fan(st: SurfaceTool, outline: PackedVector2Array, top: float, bottom: float,
		colour: Color, edge: Color) -> void:
	var cs := terrain.cell_size if terrain != null else 1.0
	var points: Array[Vector3] = []
	for p in outline:
		points.append(Vector3(p.x * cs, top, p.y * cs))
	MeshShapes.add_polygon(st, points, Vector3.UP, colour)
	var middle := points[0]
	for k in range(1, points.size() - 1):
		var a := points[k]
		var b := points[k + 1]
		_quad(st, a, b, Vector3(b.x, bottom, b.z), Vector3(a.x, bottom, a.z), edge,
				(a + b) * 0.5 - middle)


func _sides(points: PackedVector2Array, half: float) -> Array[Vector2]:
	var sides: Array[Vector2] = []
	for i in points.size():
		var along := points[mini(i + 1, points.size() - 1)] - points[maxi(i - 1, 0)]
		sides.append(Vector2(-along.y, along.x).normalized() * half)
	return sides


func _ground(point: Vector2) -> float:
	return terrain.height_at(point) if terrain != null else 0.0


## A flat four-sided face, wound so its front faces `outward` (Godot
## treats clockwise as the front, where the cross product points away from
## the viewer).
func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, colour: Color,
		outward: Vector3) -> void:
	var cross := (b - a).cross(c - a)
	st.set_color(colour)
	st.set_normal(outward.normalized() if outward != Vector3.ZERO else -cross.normalized())
	var order := [a, b, c, a, c, d] if cross.dot(outward) < 0.0 else [a, c, b, a, d, c]
	for v in order:
		st.add_vertex(v)
