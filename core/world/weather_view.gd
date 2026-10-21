class_name WeatherView
extends Node3D
## Rain or snow falling around wherever the camera looks (see Weather).

const AREA := 60.0
const HEIGHT := 22.0

var weather: Weather
## () -> Vector3: where to centre the fall, such as the camera's focus.
var centre: Callable

var _rain := CPUParticles3D.new()
var _snow := CPUParticles3D.new()


func _ready() -> void:
	_set_up(_rain, Vector3(0.03, 0.5, 0.03), Color(0.75, 0.8, 0.9, 0.55), 1600, 1.0, 26.0)
	_set_up(_snow, Vector3(0.12, 0.12, 0.12), Color(1.0, 1.0, 1.0, 0.9), 1200, 7.0, 3.5)
	_snow.direction = Vector3(0.2, -1.0, 0.1)
	_snow.spread = 25.0


func _set_up(particles: CPUParticles3D, size: Vector3, colour: Color, amount: int, life: float, speed: float) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = colour
	mesh.material = material
	particles.mesh = mesh
	particles.amount = amount
	particles.lifetime = life
	particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	particles.emission_box_extents = Vector3(AREA * 0.5, 0.5, AREA * 0.5)
	particles.direction = Vector3(0.0, -1.0, 0.0)
	particles.spread = 3.0
	particles.gravity = Vector3.ZERO
	particles.initial_velocity_min = speed * 0.9
	particles.initial_velocity_max = speed * 1.1
	particles.position.y = HEIGHT
	particles.emitting = false
	particles.visibility_aabb = AABB(Vector3(-AREA, -HEIGHT - 5.0, -AREA), Vector3(AREA * 2.0, HEIGHT + 10.0, AREA * 2.0))
	add_child(particles)


func _process(_delta: float) -> void:
	var def := weather.current() if weather != null else null
	var falling: StringName = def.falling if def != null else &""
	_rain.emitting = falling == &"rain"
	_snow.emitting = falling == &"snow"
	if centre.is_valid():
		var at: Vector3 = centre.call()
		position = Vector3(at.x, 0.0, at.z)
