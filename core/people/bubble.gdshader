shader_type spatial;
// A speech or thought bubble behind words or an icon over someone's head:
// a rounded box facing the camera, with a little tail (speech) or two
// small puffs (thought) underneath. The node's scale is the box's size in
// metres; the tail hangs below it.
render_mode unshaded, depth_test_disabled, cull_disabled, blend_mix, shadows_disabled;

uniform vec4 fill : source_color = vec4(1.0, 0.98, 0.94, 0.96);
uniform vec4 edge : source_color = vec4(0.36, 0.3, 0.26, 1.0);
uniform bool thought = false;
// Metres of the quad below the box kept for the tail.
uniform float tail = 0.08;

varying vec2 box;

void vertex() {
	box = vec2(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz));
	// The quad is 1 by 1; grow it to the box plus room for the tail.
	VERTEX.xy *= vec2(box.x, box.y + tail);
	VERTEX.y -= tail * 0.5;
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
}

float rounded_box(vec2 p, vec2 half_size, float r) {
	vec2 q = abs(p) - half_size + r;
	return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

void fragment() {
	// Where this pixel is, in metres from the middle of the box.
	vec2 size = vec2(box.x, box.y + tail);
	vec2 p = (vec2(UV.x, 1.0 - UV.y) - 0.5) * size;
	p.y -= tail * 0.5;
	float radius = min(box.y * 0.5, 0.09);
	float d = rounded_box(p, box * 0.5, radius);
	if (thought) {
		d = min(d, length(p - vec2(-box.x * 0.18, -box.y * 0.5 - tail * 0.35)) - tail * 0.32);
		d = min(d, length(p - vec2(-box.x * 0.24, -box.y * 0.5 - tail * 0.85)) - tail * 0.16);
	} else {
		// A triangle under the middle, pointing down.
		vec2 t = p - vec2(-box.x * 0.12, -box.y * 0.5);
		float tri = max(-t.y - tail * 0.95, max(t.y - 0.02, abs(t.x + t.y * 0.45) - (tail + t.y) * 0.45));
		d = min(d, tri);
	}
	float px = fwidth(d);
	float inside = 1.0 - smoothstep(-px, px, d);
	float line = 1.0 - smoothstep(-px, px, d + 0.012);
	ALBEDO = mix(edge.rgb, fill.rgb, line);
	ALPHA = inside * mix(edge.a, fill.a, line);
}
