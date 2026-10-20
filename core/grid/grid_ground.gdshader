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
// Soft near-white mottling over the colours, repeating every detail_scale metres.
uniform sampler2D detail : source_color, hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float detail_scale = 6.0;

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

	vec2 coord = world_pos.xz / cell_size;
	vec2 width = fwidth(coord) * line_width;
	vec2 dist = abs(fract(coord - 0.5) - 0.5);
	vec2 lines = 1.0 - smoothstep(vec2(0.0), width, dist);
	float line = max(lines.x, lines.y);
	float view_distance = length(VERTEX);
	line *= 1.0 - smoothstep(line_fade_distance * 0.6, line_fade_distance, view_distance);

	ALBEDO = mix(ground, ground * 0.82, line);
	ROUGHNESS = 0.95;
}
