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
