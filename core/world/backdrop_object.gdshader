shader_type spatial;
// The scenery past the map (see Backdrop): flat colours from the vertex
// colours times `colour`, snow on what faces up, and the same fog as the
// ground (grid_ground.gdshader), measured from the land for sale.

uniform vec3 colour : source_color = vec3(1.0);
uniform float snow = 0.0;
uniform float takes_snow = 1.0;
uniform vec3 snow_colour : source_color = vec3(0.93, 0.95, 0.98);
// Lit windows by night: 0 by day, 1 at night.
uniform float glow = 0.0;
uniform vec4 fog_rect = vec4(0.0);
uniform float fog_start = 0.0;
uniform float fog_width = 18.0;
uniform vec3 fog_colour : source_color = vec3(0.74, 0.81, 0.76);

varying vec3 world_pos;
varying vec3 world_normal;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 albedo = colour * COLOR.rgb;
	albedo = mix(albedo, snow_colour, snow * takes_snow * smoothstep(0.45, 0.75, world_normal.y));
	float fog = 0.0;
	if (fog_rect.z > 0.0) {
		vec2 outside = max(max(fog_rect.xy - world_pos.xz, world_pos.xz - (fog_rect.xy + fog_rect.zw)), vec2(0.0));
		fog = smoothstep(fog_start, fog_start + fog_width, length(outside));
	}
	ALBEDO = albedo * (1.0 - fog);
	EMISSION = fog_colour * fog + albedo * glow * (1.0 - fog);
	ROUGHNESS = 0.95;
}
