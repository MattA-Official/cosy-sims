class_name PathView
extends Node3D
## Draws a PathNetwork: each segment as a strip of blocks that follows the
## ground, with steps where it is steep and bridges over water, and a round
## pad at every node so junctions and bends join up.

@export var terrain: Terrain
@export var styles: Array[PathStyleDef] = []
## How far the path's surface sits above the ground.
@export var lift := 0.05
@export var bridge_colour := Color(0.6, 0.45, 0.32)
@export var step_height := 0.18

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
		add_curve(st, network.sample(segment), def)
	for node: int in network.nodes:
		_add_pad(st, node)
	_mesh.mesh = st.commit()


## Adds one curve's geometry. Also used by the drawing tool's preview.
func add_curve(st: SurfaceTool, points: PackedVector2Array, def: PathStyleDef,
		tint := Color(1, 1, 1, 1)) -> void:
	var profile := PathProfile.build(points, terrain)
	var half := (def.width if def != null else 1.5) * 0.5
	var colour := (def.colour if def != null else Color.TAN) * tint
	var edge := (def.edge_colour if def != null else Color.SADDLE_BROWN) * tint
	var wood := bridge_colour * tint
	# Cross-sections square to the curve at each point, shared by the
	# stretches either side so bends have no gaps or notches.
	var sides: Array[Vector2] = []
	for i in points.size():
		var along := points[mini(i + 1, points.size() - 1)] - points[maxi(i - 1, 0)]
		sides.append(Vector2(-along.y, along.x).normalized() * half)
	for i in profile.kinds.size():
		var p0 := points[i]
		var p1 := points[i + 1]
		var h0 := profile.heights[i]
		var h1 := profile.heights[i + 1]
		match profile.kinds[i]:
			PathProfile.Kind.GROUND:
				var top0 := _hugged(p0, sides[i]) + lift
				var top1 := _hugged(p1, sides[i + 1]) + lift
				_add_section(st, p0 - sides[i], p0 + sides[i], p1 + sides[i + 1], p1 - sides[i + 1],
						top0, top1, minf(h0, h1) - 0.3, colour, edge)
			PathProfile.Kind.STEPS:
				_add_steps(st, p0, p1, half, h0, h1, colour, edge)
			PathProfile.Kind.BRIDGE:
				_add_bridge(st, p0, p1, half, h0 + lift, h1 + lift, wood)


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


func _add_steps(st: SurfaceTool, p0: Vector2, p1: Vector2, half: float, h0: float, h1: float,
		colour: Color, edge: Color) -> void:
	var count := maxi(1, ceili(absf(h1 - h0) / step_height))
	var low := minf(h0, h1) - 0.3
	for k in count:
		var a := p0.lerp(p1, float(k) / count)
		var b := p0.lerp(p1, float(k + 1) / count)
		# Each tread is flat, at the height of the step's upper end.
		var tread := lerpf(h0, h1, float(k + 1) / count) if h1 > h0 \
				else lerpf(h0, h1, float(k) / count)
		add_block(st, a, b, half, tread + lift, tread + lift, low, colour, edge)


func _add_bridge(st: SurfaceTool, p0: Vector2, p1: Vector2, half: float, top0: float,
		top1: float, wood: Color) -> void:
	add_block(st, p0, p1, half, top0, top1, minf(top0, top1) - 0.2, wood, wood.darkened(0.2))
	var dir := (p1 - p0).normalized()
	var side := Vector2(-dir.y, dir.x)
	# Rails along both edges.
	for s in [-1.0, 1.0]:
		var offset: Vector2 = side * (half - 0.05) * s
		add_block(st, p0 + offset, p1 + offset, 0.05, top0 + 0.45, top1 + 0.45, minf(top0, top1),
				wood.darkened(0.15), wood.darkened(0.15))
	# A pier under the start of every other stretch keeps it from floating.
	if terrain != null and int(p0.x * 7.0 + p0.y * 13.0) % 2 == 0:
		var ground := terrain.height_at(p0) - 0.5
		add_block(st, p0 - dir * 0.1, p0 + dir * 0.1, half * 0.6, top0 - 0.2, top0 - 0.2, ground,
				wood.darkened(0.3), wood.darkened(0.3))


## A round pad at a node so segments meeting at an angle join up.
func _add_pad(st: SurfaceTool, node: int) -> void:
	var attached := network.segments_at(node)
	if attached.is_empty():
		return
	var centre := network.node_position(node)
	var half := 0.0
	var def: PathStyleDef = null
	for segment in attached:
		var d := style(segment.style)
		if d != null and d.width * 0.5 > half:
			half = d.width * 0.5
			def = d
	if terrain != null and terrain.is_underwater(centre):
		return
	var top := _hugged(centre, Vector2(half, 0))
	top = maxf(top, _hugged(centre, Vector2(0, half))) + lift + 0.002
	var cs := terrain.cell_size if terrain != null else 1.0
	var sides := 12
	var colour := def.colour if def != null else Color.TAN
	var edge := def.edge_colour if def != null else Color.SADDLE_BROWN
	var bottom := (terrain.height_at(centre) if terrain != null else 0.0) - 0.3
	var middle := Vector3(centre.x * cs, top, centre.y * cs)
	for k in sides:
		var a := centre + Vector2.from_angle(TAU * k / sides) * half
		var b := centre + Vector2.from_angle(TAU * (k + 1) / sides) * half
		var va := Vector3(a.x * cs, top, a.y * cs)
		var vb := Vector3(b.x * cs, top, b.y * cs)
		st.set_color(colour)
		st.set_normal(Vector3.UP)
		var fan := [middle, va, vb]
		if (va - middle).cross(vb - middle).y > 0.0:
			fan = [middle, vb, va]
		for v in fan:
			st.add_vertex(v)
		_quad(st, va, vb, Vector3(vb.x, bottom, vb.z), Vector3(va.x, bottom, va.z), edge,
				(va + vb) * 0.5 - middle)


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
