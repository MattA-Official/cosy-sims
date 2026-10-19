class_name CameraRig
extends Node3D
## A Parkitect-style management camera: it orbits a focus point on the ground.
##
## Keyboard: WASD or arrows to pan, Q/E to rotate, +/- to zoom, Shift to go faster.
## Mouse: wheel to zoom, right-drag to pan, middle-drag to rotate and tilt.
##
## Every movement sets a target and the rig eases towards it each frame, which
## is what gives the camera its soft, floaty feel.

@export_group("Pan")
@export var pan_speed := 1.2 ## Ground distance per second, as a multiple of zoom distance.
@export var fast_multiplier := 2.5
@export var drag_pan_speed := 0.0025 ## Per pixel, as a multiple of zoom distance.
@export var edge_scroll := false
@export var edge_margin_px := 12
@export var bounds := Rect2(-50, -50, 100, 100) ## Limits for the focus point, on the XZ plane.

@export_group("Rotate")
@export var rotate_speed_deg := 90.0 ## Q/E, per second.
@export var drag_rotate_speed := 0.3 ## Degrees per pixel.
@export var min_pitch_deg := 25.0
@export var max_pitch_deg := 80.0

@export_group("Zoom")
@export var min_distance := 6.0
@export var max_distance := 60.0
@export var zoom_step := 1.15 ## Each wheel notch multiplies or divides the distance by this.

@export_group("Start")
@export var start_yaw_deg := 45.0
@export var start_pitch_deg := 40.0
@export var start_distance := 24.0

## When set, the camera picks points on the terrain and keeps its focus at
## ground level. Otherwise it uses the flat plane y = 0.
@export var terrain: Terrain

@export_group("Feel")
@export var smoothing := 10.0 ## Higher is snappier.

var _target_position: Vector3
var _target_yaw: float
var _target_pitch: float
var _target_distance: float
var _yaw: float
var _pitch: float
var _distance: float
var _rotating := false
var _panning := false

@onready var _pitch_pivot: Node3D = $Pitch
@onready var camera: Camera3D = $Pitch/Camera3D


func _ready() -> void:
	_target_position = position
	_target_yaw = start_yaw_deg
	_target_pitch = clampf(start_pitch_deg, min_pitch_deg, max_pitch_deg)
	_target_distance = clampf(start_distance, min_distance, max_distance)
	_yaw = _target_yaw
	_pitch = _target_pitch
	_distance = _target_distance
	_apply()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		match event.button_index:
			MOUSE_BUTTON_WHEEL_UP when event.pressed:
				zoom_by(1.0 / zoom_step)
			MOUSE_BUTTON_WHEEL_DOWN when event.pressed:
				zoom_by(zoom_step)
			MOUSE_BUTTON_MIDDLE:
				_rotating = event.pressed
			MOUSE_BUTTON_RIGHT:
				_panning = event.pressed
	elif event is InputEventMouseMotion:
		if _rotating:
			_target_yaw -= event.relative.x * drag_rotate_speed
			_target_pitch = clampf(_target_pitch + event.relative.y * drag_rotate_speed,
					min_pitch_deg, max_pitch_deg)
		if _panning:
			var amount: Vector2 = -event.relative * drag_pan_speed * _target_distance
			pan_by(amount)


func _process(delta: float) -> void:
	var fast := fast_multiplier if Input.is_action_pressed("camera_fast") else 1.0

	var move := Input.get_vector("camera_pan_left", "camera_pan_right",
			"camera_pan_forward", "camera_pan_back")
	if edge_scroll:
		move += _edge_scroll_vector()
	if move != Vector2.ZERO:
		pan_by(move.limit_length(1.0) * pan_speed * _target_distance * fast * delta)

	var spin := Input.get_axis("camera_rotate_right", "camera_rotate_left")
	_target_yaw += spin * rotate_speed_deg * fast * delta

	if Input.is_action_pressed("camera_zoom_in"):
		zoom_by(1.0 - delta * 2.0)
	if Input.is_action_pressed("camera_zoom_out"):
		zoom_by(1.0 + delta * 2.0)

	if terrain != null:
		var local := terrain.to_local(_target_position) / terrain.cell_size
		var point := Vector2(local.x, local.z)
		_target_position.y = maxf(terrain.height_at(point), terrain.water_surface(point))
	var t := 1.0 - exp(-smoothing * delta)
	position = position.lerp(_target_position, t)
	_yaw = lerpf(_yaw, _target_yaw, t)
	_pitch = lerpf(_pitch, _target_pitch, t)
	_distance = lerpf(_distance, _target_distance, t)
	_apply()


## Moves the focus point. x is screen-right and y is screen-down, relative to
## the way the camera currently faces.
func pan_by(screen_offset: Vector2) -> void:
	var basis_yaw := Basis(Vector3.UP, deg_to_rad(_target_yaw))
	var world := basis_yaw * Vector3(screen_offset.x, 0.0, screen_offset.y)
	_target_position += world
	_target_position.x = clampf(_target_position.x, bounds.position.x, bounds.end.x)
	_target_position.z = clampf(_target_position.z, bounds.position.y, bounds.end.y)


func zoom_by(factor: float) -> void:
	_target_distance = clampf(_target_distance * factor, min_distance, max_distance)


## Jumps the focus to a point on the ground, easing there.
func focus_on(world_position: Vector3) -> void:
	_target_position = Vector3(world_position.x, 0.0, world_position.z)
	pan_by(Vector2.ZERO) # Re-applies the bounds.


## Returns where a screen position hits the ground (the terrain if there is
## one, else the plane y = 0), or null if the ray points at the sky.
func ground_point_at(screen_position: Vector2) -> Variant:
	var origin := camera.project_ray_origin(screen_position)
	var direction := camera.project_ray_normal(screen_position)
	if terrain != null:
		var to_local := terrain.global_transform.affine_inverse()
		var hit: Variant = terrain.intersect_ray(to_local * origin, to_local.basis * direction)
		return terrain.to_global(hit) if hit != null else null
	return Plane(Vector3.UP, 0.0).intersects_ray(origin, direction)


func _apply() -> void:
	rotation_degrees.y = _yaw
	_pitch_pivot.rotation_degrees.x = -_pitch
	camera.position = Vector3(0.0, 0.0, _distance)


func _edge_scroll_vector() -> Vector2:
	var viewport := get_viewport()
	if not viewport.get_window().has_focus():
		return Vector2.ZERO
	var mouse := viewport.get_mouse_position()
	var size := viewport.get_visible_rect().size
	var v := Vector2.ZERO
	if mouse.x < edge_margin_px: v.x -= 1.0
	if mouse.x > size.x - edge_margin_px: v.x += 1.0
	if mouse.y < edge_margin_px: v.y -= 1.0
	if mouse.y > size.y - edge_margin_px: v.y += 1.0
	return v
