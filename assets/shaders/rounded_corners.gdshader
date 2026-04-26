// Rounded-corner mask for any CanvasItem (typically a TextureRect).
//
// `size` must be set from script to the rendered rect's size in
// pixels. We can't lean on `UV` because TextureRect's stretch modes
// (KEEP_ASPECT, KEEP_ASPECT_COVERED, …) remap UV to a subregion of
// the source texture, so UV-based corner tests evaluate in the
// wrong space. Pass canvas-local position through a varying instead.
shader_type canvas_item;

uniform vec2 size = vec2(64.0, 64.0);
uniform float radius : hint_range(0.0, 64.0) = 4.0;

varying vec2 v_local;

void vertex() {
	v_local = VERTEX;
}

void fragment() {
	vec2 from_corner = abs(v_local - size * 0.5) - (size * 0.5 - vec2(radius));
	float dist = length(max(from_corner, vec2(0.0))) - radius;
	if (dist > 0.0) {
		discard;
	}
}
