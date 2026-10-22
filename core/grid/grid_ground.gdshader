shader_type spatial;
// Soft grass with faint grid lines, drawn in world space so the lines always
// match the BuildGrid cells (keep cell_size in step with the grid). Steep
// slopes turn to earth and the ground near the water turns to sand.

uniform vec3 base_colour : source_color = vec3(0.40, 0.64, 0.30);
uniform vec3 earth_colour : source_color = vec3(0.55, 0.42, 0.3);
uniform vec3 sand_colour : source_color = vec3(0.86, 0.78, 0.56);
uniform float cell_size = 1.0;
uniform float water_level = -0.35;
uniform float line_width = 1.2; // In pixels.
uniform float line_fade_distance = 70.0; // Lines fade out beyond this camera distance.
// Past the land for sale (x, z, width, depth in metres) the ground fades
// into fog over fog_width metres, starting fog_start metres out. A zero
// size means no fog.
uniform vec4 fog_rect = vec4(0.0);
uniform float fog_start = 0.0;
uniform float fog_width = 18.0;
// Off for the scenery past the map (see Backdrop).
uniform bool grid_lines = true;
uniform vec3 fog_colour : source_color = vec3(0.74, 0.81, 0.76);
// Soft near-white mottling over the colours, repeating every detail_scale metres.
uniform sampler2D detail : source_color, hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float detail_scale = 6.0;
// Snow lying on flat ground, 0 to 1.
uniform float snow = 0.0;
uniform vec3 snow_colour : source_color = vec3(0.93, 0.95, 0.98);

varying vec3 world_pos;
varying vec3 world_normal;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 ground = base_colour;
	float steep = smoothstep(0.82, 0.7, world_normal.y);
	ground = mix(ground, earth_colour, steep);
	float shore = 1.0 - smoothstep(water_level + 0.05, water_level + 0.3, world_pos.y);
	ground = mix(ground, sand_colour, shore);
	ground *= texture(detail, world_pos.xz / detail_scale).rgb;
	ground = mix(ground, snow_colour, snow * smoothstep(0.7, 0.9, world_normal.y) * (1.0 - shore));

	vec2 coord = world_pos.xz / cell_size;
	vec2 width = fwidth(coord) * line_width;
	vec2 dist = abs(fract(coord - 0.5) - 0.5);
	vec2 lines = 1.0 - smoothstep(vec2(0.0), width, dist);
	float line = max(lines.x, lines.y);
	float view_distance = length(VERTEX);
	line *= 1.0 - smoothstep(line_fade_distance * 0.6, line_fade_distance, view_distance);
	if (!grid_lines) {
		line = 0.0;
	}

	vec3 albedo = mix(ground, ground * 0.82, line);
	float fog = 0.0;
	if (fog_rect.z > 0.0) {
		vec2 outside = max(max(fog_rect.xy - world_pos.xz, world_pos.xz - (fog_rect.xy + fog_rect.zw)), vec2(0.0));
		fog = smoothstep(fog_start, fog_start + fog_width, length(outside));
	}
	// The fog is unlit, like the sky behind it.
	ALBEDO = albedo * (1.0 - fog);
	EMISSION = fog_colour * fog;
	ROUGHNESS = 0.95;
}
