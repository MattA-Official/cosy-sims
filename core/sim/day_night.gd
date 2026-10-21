class_name DayNight
extends Node
## Moves the sun with the clock and dims the world at night: dawn about
## 06:00, dusk about 20:00, a cool moonlight in between. `always_day` keeps
## it bright for building.

@export var sun: DirectionalLight3D
@export var environment: Environment
@export var dawn := 6.0
@export var dusk := 20.0
## Hours either side of dawn and dusk the light takes to change.
@export var twilight := 1.0
@export var day_colour := Color(1.0, 0.96, 0.9)
@export var low_sun_colour := Color(1.0, 0.72, 0.5)
@export var night_colour := Color(0.72, 0.77, 0.95)
@export var day_energy := 1.0
@export var night_energy := 0.45
@export var day_ambient := 0.35
@export var night_ambient := 0.22
@export var night_sky_top := Color(0.12, 0.16, 0.32)
@export var night_sky_horizon := Color(0.25, 0.28, 0.45)
## The fog past the edge of the map, by day and by night. The sky below
## the horizon takes it too, so the ground melts into it.
@export var day_fog := Color(0.74, 0.81, 0.76)
@export var night_fog := Color(0.2, 0.23, 0.33)
## The ground's material, whose fog_colour follows the light. Optional.
var fog_material: ShaderMaterial

## How much an overcast sky dims the sun.
const OVERCAST_DIM := 0.45

var clock: GameClock
## How grey the weather makes the day, 0 to 1.
var overcast := 0.0
## Keeps it midday whatever the time.
var always_day := false:
	set(value):
		always_day = value
		apply()

var _day_sky_top: Color
var _day_sky_horizon: Color
var _day_rotation_y := 0.0


func _ready() -> void:
	if sun != null:
		_day_rotation_y = sun.rotation.y
	var sky := _sky_material()
	if sky != null:
		_day_sky_top = sky.sky_top_color
		_day_sky_horizon = sky.sky_horizon_color
	apply()


func _process(_delta: float) -> void:
	apply()


## How much daylight there is at an hour, from 0 at night to 1 by day.
func daylight(hour: float) -> float:
	var morning := clampf((hour - (dawn - twilight)) / (twilight * 2.0), 0.0, 1.0)
	var evening := clampf(((dusk + twilight) - hour) / (twilight * 2.0), 0.0, 1.0)
	return smoothstep(0.0, 1.0, minf(morning, evening))


## Sets the light for the clock's time.
func apply() -> void:
	if sun == null:
		return
	var hour := 12.0 if always_day or clock == null else clock.hour_float()
	var light := daylight(hour)
	# By day the sun climbs from the east and sets in the west; at night the
	# moon stands still, high up.
	var through_day := clampf((hour - dawn) / (dusk - dawn), 0.0, 1.0)
	var height := lerpf(deg_to_rad(-20.0), deg_to_rad(-62.0), sin(through_day * PI))
	var day_angle := Vector3(height, _day_rotation_y + lerpf(-0.9, 0.9, through_day), 0.0)
	var night_angle := Vector3(deg_to_rad(-55.0), _day_rotation_y + 0.6, 0.0)
	sun.rotation = night_angle.lerp(day_angle, light)
	var low := 1.0 - sin(through_day * PI)
	var colour := day_colour.lerp(low_sun_colour, clampf(low * 1.3 - 0.3, 0.0, 1.0) * light)
	sun.light_color = night_colour.lerp(colour, light)
	sun.light_energy = lerpf(night_energy, day_energy * (1.0 - OVERCAST_DIM * overcast), light)
	if environment != null:
		environment.ambient_light_energy = lerpf(night_ambient, day_ambient, light)
	var sky := _sky_material()
	if sky != null:
		var grey := Color(0.62, 0.65, 0.7)
		sky.sky_top_color = night_sky_top.lerp(_day_sky_top.lerp(grey, overcast), light)
		sky.sky_horizon_color = night_sky_horizon.lerp(_day_sky_horizon.lerp(grey, overcast * 0.6), light)
		var fog := night_fog.lerp(day_fog, light)
		sky.ground_horizon_color = fog
		sky.ground_bottom_color = fog
		if fog_material != null:
			fog_material.set_shader_parameter("fog_colour", fog)


func _sky_material() -> ProceduralSkyMaterial:
	if environment == null or environment.sky == null:
		return null
	return environment.sky.sky_material as ProceduralSkyMaterial
