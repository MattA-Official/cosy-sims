class_name MeshShapes
## Small helpers for building placeholder geometry in code.

const _NORMALS: Array[Vector3] = [
	Vector3.UP, Vector3.DOWN, Vector3.LEFT, Vector3.RIGHT, Vector3.FORWARD, Vector3.BACK,
]


## Adds an axis-aligned box to a SurfaceTool. The top face can have its own
## colour, which gives walls the dark cap you see in The Sims.
static func add_box(st: SurfaceTool, centre: Vector3, half: Vector3, colour: Color,
		top_colour: Color = colour) -> void:
	for normal in _NORMALS:
		st.set_normal(normal)
		st.set_color(top_colour if normal == Vector3.UP else colour)
		for vertex in _face(centre, half, normal):
			st.add_vertex(vertex)


## Adds a box with its sides along any two flat directions, given as half
## extents: `half_a` and `half_b` across the ground, `half_up` upwards.
static func add_oriented_box(st: SurfaceTool, centre: Vector3, half_a: Vector3, half_b: Vector3,
		half_up: float, colour: Color, top_colour: Color = colour) -> void:
	for face in _oriented_faces(centre, half_a, half_b, half_up):
		add_quad(st, face[0], face[1], face[2], face[3], face[4], top_colour if face[4].y > 0.0 else colour)


## The same as add_oriented_box, for an ImmediateMesh surface already begun.
static func add_oriented_box_immediate(mesh: ImmediateMesh, centre: Vector3, half_a: Vector3,
		half_b: Vector3, half_up: float, colour: Color) -> void:
	for face in _oriented_faces(centre, half_a, half_b, half_up):
		var cross: Vector3 = (face[1] - face[0]).cross(face[2] - face[0])
		var order: Array = [face[0], face[1], face[2], face[0], face[2], face[3]]
		if cross.dot(face[4]) >= 0.0:
			order = [face[0], face[2], face[1], face[0], face[3], face[2]]
		mesh.surface_set_normal(face[4])
		mesh.surface_set_color(colour)
		for vertex: Vector3 in order:
			mesh.surface_add_vertex(vertex)


## Each face of an oriented box as four corners and its outward direction.
static func _oriented_faces(centre: Vector3, half_a: Vector3, half_b: Vector3,
		half_up: float) -> Array:
	var up := Vector3.UP * half_up
	var out := []
	# Each face: its outward half extent, then the two half extents it spans.
	for face: Array in [[half_a, half_b, up], [-half_a, half_b, up], [half_b, half_a, up],
			[-half_b, half_a, up], [up, half_a, half_b], [-up, half_a, half_b]]:
		var base: Vector3 = centre + face[0]
		var u: Vector3 = face[1]
		var v: Vector3 = face[2]
		out.append([base - u - v, base + u - v, base + u + v, base - u + v, face[0].normalized()])
	return out


## A four-sided face, wound so its front faces `outward`.
static func add_quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3,
		outward: Vector3, colour: Color) -> void:
	var cross := (b - a).cross(c - a)
	st.set_normal(cross.normalized() * (1.0 if cross.dot(outward) >= 0.0 else -1.0))
	st.set_color(colour)
	var order: Array[Vector3] = [a, b, c, a, c, d]
	if cross.dot(outward) >= 0.0:
		order = [a, c, b, a, d, c]
	for vertex in order:
		st.add_vertex(vertex)


## Adds a flat convex polygon, facing `outward`.
static func add_polygon(st: SurfaceTool, points: Array[Vector3], outward: Vector3,
		colour: Color) -> void:
	for i in range(1, points.size() - 1):
		var a := points[0]
		var b := points[i]
		var c := points[i + 1]
		var cross := (b - a).cross(c - a)
		st.set_normal(cross.normalized() * (1.0 if cross.dot(outward) >= 0.0 else -1.0))
		st.set_color(colour)
		for vertex: Vector3 in ([a, c, b] if cross.dot(outward) >= 0.0 else [a, b, c]):
			st.add_vertex(vertex)


## Adds an upright solid with a flat convex outline (x and z in `points`),
## from `bottom` to `top`.
static func add_prism(st: SurfaceTool, points: PackedVector2Array, bottom: float, top: float,
		colour: Color, top_colour: Color = colour) -> void:
	var middle := Vector2.ZERO
	for p in points:
		middle += p
	middle /= maxf(points.size(), 1)
	var cap: Array[Vector3] = []
	for p in points:
		cap.append(Vector3(p.x, top, p.y))
	add_polygon(st, cap, Vector3.UP, top_colour)
	for i in points.size():
		var a := points[i]
		var b := points[(i + 1) % points.size()]
		var outward := (a + b) * 0.5 - middle
		add_quad(st, Vector3(a.x, top, a.y), Vector3(b.x, top, b.y), Vector3(b.x, bottom, b.y),
				Vector3(a.x, bottom, a.y), Vector3(outward.x, 0.0, outward.y), colour)


## Adds an axis-aligned box to an ImmediateMesh surface that is already begun.
static func add_box_immediate(mesh: ImmediateMesh, centre: Vector3, half: Vector3,
		colour: Color) -> void:
	for normal in _NORMALS:
		mesh.surface_set_normal(normal)
		mesh.surface_set_color(colour)
		for vertex in _face(centre, half, normal):
			mesh.surface_add_vertex(vertex)


## A material that colours geometry by its vertex colours.
static func vertex_colour_material(unshaded := false) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.vertex_color_is_srgb = true
	material.roughness = 0.9
	if unshaded:
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.no_depth_test = true
	return material


## Two triangles for one face of a box, wound clockwise as seen from outside,
## which is what Godot treats as the front.
static func _face(centre: Vector3, half: Vector3, normal: Vector3) -> Array[Vector3]:
	var u := Vector3.RIGHT if absf(normal.x) < 0.5 else Vector3.BACK
	var v := normal.cross(u)
	var base := centre + normal * half
	var hu := u * half
	var hv := v * half
	var p0 := base - hu - hv
	var p1 := base + hu - hv
	var p2 := base + hu + hv
	var p3 := base - hu + hv
	return [p0, p2, p1, p0, p3, p2]
