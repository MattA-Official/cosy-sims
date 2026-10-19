shader_type spatial;
// Soft grass with faint grid lines, drawn in world space so the lines always
// match the BuildGrid cells (keep cell_size in step with the grid).

uniform vec3 base_colour : source_color = vec3(0.40, 0.64, 0.30);
uniform vec3 line_colour : source_color = vec3(0.32, 0.53, 0.25);
uniform float cell_size = 1.0;
uniform float line_width = 1.2; // In pixels.
uniform float line_fade_distance = 70.0; // Lines fade out beyond this camera distance.

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 coord = world_pos.xz / cell_size;
	vec2 width = fwidth(coord) * line_width;
	vec2 dist = abs(fract(coord - 0.5) - 0.5);
	vec2 lines = 1.0 - smoothstep(vec2(0.0), width, dist);
	float line = max(lines.x, lines.y);
	float view_distance = length(VERTEX);
	line *= 1.0 - smoothstep(line_fade_distance * 0.6, line_fade_distance, view_distance);

	ALBEDO = mix(base_colour, line_colour, line);
	ROUGHNESS = 0.95;
}
