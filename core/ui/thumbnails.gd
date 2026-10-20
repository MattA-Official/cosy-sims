class_name Thumbnails
extends Node
## Small pictures of catalogue entries for the build menu, rendered in a
## little world of their own: objects and plants as they look in the game,
## floors and walls as swatches, and a floor and wall pair as a cut-away
## corner of a room. Each is drawn once, the first time it is asked for, so
## anything new added to a catalogue gets its picture for free.

const SIZE := 128
## Seen from the same angle as the game's camera.
const PITCH := -35.0
const YAW := 45.0

var _cache := {} # key -> ImageTexture
var _queue: Array[Array] = [] # [texture, Callable that fills the stage]
var _viewport := SubViewport.new()
var _stage := Node3D.new()
var _camera := Camera3D.new()
var _busy := false


func _ready() -> void:
	_viewport.size = Vector2i(SIZE, SIZE)
	_viewport.own_world_3d = true
	_viewport.transparent_bg = true
	_viewport.msaa_3d = Viewport.MSAA_4X
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_viewport)
	var environment := Environment.new()
	environment.background_mode = Environment.BG_CLEAR_COLOR
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.85, 0.9, 0.95)
	environment.ambient_light_energy = 0.55
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var world := WorldEnvironment.new()
	world.environment = environment
	_viewport.add_child(world)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-55.0), deg_to_rad(20.0), 0.0)
	sun.light_color = Color(1, 0.96, 0.9)
	_viewport.add_child(sun)
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.rotation_degrees = Vector3(PITCH, YAW, 0.0)
	_viewport.add_child(_camera)
	_viewport.add_child(_stage)


func object(def: ObjectDef) -> Texture2D:
	return _request(def, func() -> void:
		if def.model != null:
			_stage.add_child(def.model.instantiate())
			return
		var margin := minf(0.1, minf(def.size.x, def.size.y) * 0.1)
		_box(Vector3.UP * def.height * 0.5,
				Vector3(def.size.x - margin * 2.0, def.height, def.size.y - margin * 2.0), def.colour))


func floor_swatch(def: FloorDef) -> Texture2D:
	return _request(def, func() -> void:
		_box(Vector3.ZERO, Vector3(1.2, 0.08, 1.2), def.colour, def.texture))


func wall_swatch(def: WallDef) -> Texture2D:
	return _request(def, func() -> void:
		_wall(def, Vector3.ZERO, Vector3.RIGHT, 1.3, def.height))


## A one-tile room with its front walls cut away, showing a floor and wall
## style together.
func room(floor_def: FloorDef, wall_def: WallDef) -> Texture2D:
	return _request([floor_def, wall_def], func() -> void:
		_box(Vector3(0, -0.04, 0), Vector3(1.0, 0.08, 1.0), floor_def.colour, floor_def.texture)
		var height := minf(wall_def.height, 1.0)
		var t := wall_def.thickness
		_wall(wall_def, Vector3(0, 0, -0.5 - t * 0.5), Vector3.RIGHT, 1.0 + t * 2.0, height)
		_wall(wall_def, Vector3(-0.5 - t * 0.5, 0, 0), Vector3.BACK, 1.0, height))


func plant(def: FoliageDef) -> Texture2D:
	return _request(def, _plant_shapes.bind(def))


func path(def: PathStyleDef) -> Texture2D:
	return _request(def, func() -> void:
		var width := def.width
		_box(Vector3.ZERO, Vector3(2.0, 0.06, width), def.colour)
		for side in [-1.0, 1.0]:
			_box(Vector3(0, 0.01, side * (width * 0.5 + 0.05)), Vector3(2.0, 0.08, 0.1), def.edge_colour))


func _request(key: Variant, fill: Callable) -> Texture2D:
	if _cache.has(key):
		return _cache[key]
	var texture := ImageTexture.create_from_image(Image.create(1, 1, false, Image.FORMAT_RGBA8))
	_cache[key] = texture
	_queue.append([texture, fill])
	if not _busy:
		_bake_queue()
	return texture


func _bake_queue() -> void:
	_busy = true
	# Wait until we're in the tree and the first frame is up.
	if not is_inside_tree():
		await ready
	while not _queue.is_empty():
		var job: Array = _queue.pop_front()
		for child in _stage.get_children():
			_stage.remove_child(child)
			child.free()
		job[1].call()
		_frame()
		_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
		await RenderingServer.frame_post_draw
		var image := _viewport.get_texture().get_image()
		if image != null and not image.is_empty():
			image.generate_mipmaps()
			(job[0] as ImageTexture).set_image(image)
	_busy = false


## Points the camera at whatever is on the stage and zooms to fit it.
func _frame() -> void:
	var bounds := AABB()
	var first := true
	for mesh: MeshInstance3D in _stage.find_children("*", "MeshInstance3D", true, false):
		var box := _stage.global_transform.affine_inverse() * mesh.global_transform * mesh.get_aabb()
		bounds = box if first else bounds.merge(box)
		first = false
	var centre := bounds.get_center()
	var back := _camera.basis.z
	_camera.position = centre + back * 20.0
	# The widest the bounds look from the camera, with a little room round it.
	var right := _camera.basis.x
	var up := _camera.basis.y
	var across := 0.0
	var tall := 0.0
	for i in 8:
		var corner := bounds.get_endpoint(i) - centre
		across = maxf(across, absf(corner.dot(right)))
		tall = maxf(tall, absf(corner.dot(up)))
	_camera.size = maxf(across, tall) * 2.0 * 1.12


func _plant_shapes(def: FoliageDef) -> void:
	if def.model != null:
		var model := def.model.instantiate() as Node3D
		for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
			var tint: Variant = FoliageLayer._tint(def, StringName(mesh.name))
			if tint != null:
				var material := StandardMaterial3D.new()
				material.albedo_color = tint
				material.roughness = 0.9
				mesh.material_override = material
		_stage.add_child(model)
		return
	match def.shape:
		FoliageDef.Shape.TREE:
			_cylinder(Vector3.UP * 0.3, Vector3(0.18, 0.6, 0.18), def.trunk_colour)
			_ball(Vector3.UP * 0.95, Vector3(0.8, 0.85, 0.8), def.colour)
		FoliageDef.Shape.BUSH:
			_ball(Vector3.UP * 0.3, Vector3(1.0, 0.7, 1.0), def.colour)
		_:
			_cylinder(Vector3.UP * 0.35, Vector3(0.12, 0.7, 0.12), Color(0.35, 0.6, 0.3))
			_ball(Vector3.UP * 0.75, Vector3.ONE * 0.45, def.colour)


func _box(centre: Vector3, size: Vector3, colour: Color, texture: Texture2D = null) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	var instance := _add(mesh, centre, Vector3.ONE, colour)
	_textured(instance, texture, Vector3(size.x, size.z, 1.0))


func _cylinder(centre: Vector3, scale: Vector3, colour: Color) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.5
	mesh.bottom_radius = 0.5
	mesh.height = 1.0
	mesh.radial_segments = 12
	_add(mesh, centre, scale, colour)


func _ball(centre: Vector3, scale: Vector3, colour: Color) -> void:
	var mesh := SphereMesh.new()
	mesh.radius = 0.5
	mesh.height = 1.0
	_add(mesh, centre, scale, colour)


## A straight run of wall, or posts and rails for see-through walls, with
## its foot on the ground at `middle`.
func _wall(def: WallDef, middle: Vector3, along: Vector3, length: float, height: float) -> void:
	var t := def.thickness
	if def.see_through:
		for end in [-0.5, 0.5]:
			_oriented_box(middle + along * length * end * 0.94 + Vector3.UP * height * 0.5,
					along, Vector3(0.12, height, 0.12), def.colour)
		for rail_y in [height * 0.45, height * 0.85]:
			_oriented_box(middle + Vector3.UP * rail_y, along, Vector3(length, 0.1, t * 0.6), def.colour)
		return
	var dado := minf(def.dado_height, height - 0.04) if def.dado_colour.a > 0.0 else 0.0
	if dado > 0.0:
		_oriented_box(middle + Vector3.UP * dado * 0.5, along, Vector3(length, dado, t), def.dado_colour,
				def.texture)
	var wall := height - 0.04 - dado
	_oriented_box(middle + Vector3.UP * (dado + wall * 0.5), along, Vector3(length, wall, t), def.colour,
			def.texture)
	_oriented_box(middle + Vector3.UP * (height - 0.02), along, Vector3(length, 0.04, t), def.top_colour)


func _oriented_box(centre: Vector3, along: Vector3, size: Vector3, colour: Color,
		texture: Texture2D = null) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	var instance := _add(mesh, centre, Vector3.ONE, colour)
	instance.basis = Basis(Vector3.UP, atan2(-along.z, along.x))
	_textured(instance, texture, Vector3(size.x, size.y, 1.0))


## Lays a one-metre texture over a box's front face. BoxMesh stretches its
## UVs over each face, so the scale is the face's size in metres.
func _textured(instance: MeshInstance3D, texture: Texture2D, metres: Vector3) -> void:
	if texture == null:
		return
	var material := instance.material_override as StandardMaterial3D
	material.albedo_texture = texture
	material.uv1_scale = metres * Vector3(3.0, 2.0, 1.0)


func _add(mesh: Mesh, centre: Vector3, scale: Vector3, colour: Color) -> MeshInstance3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = colour
	material.roughness = 0.8
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.position = centre
	instance.scale = scale
	_stage.add_child(instance)
	return instance
