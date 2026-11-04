shader_type spatial;
// Icons over entities that buildings in front hide (quality marks, alert and power icons): a quad
// that faces the camera, depth tested. Its solid middle goes into the depth pre-pass, so where two
// icons overlap the nearer one wins whatever order they are drawn in (blended without it, overlapping
// icons swapped order and flickered as the camera moved). Its rim is blended rather than cut
// at a threshold, which left Factorio's 64-pixel pictures stair-stepped and ragged.
render_mode unshaded, blend_mix, depth_prepass_alpha, cull_disabled, shadows_disabled;

#include "res://shaders/ground_height.gdshaderinc"

uniform sampler2D icon : source_color, filter_linear_mipmap;
uniform vec4 tint : source_color = vec4(1.0);
// Seconds per blink; 0 keeps the icon steady.
uniform float blink_period = 0.0;
// The share of each blink the icon shows (Factorio's alerts are on a little over half the time).
uniform float blink_on = 0.55;
// Towards the next larger mipmap: the icons are a few dozen pixels on screen and trilinear
// filtering between the 32 and 16 pixel ones blurred them.
uniform float sharpen = -0.6;

void vertex() {
	// Billboard, keeping the instance's scale.
	mat4 m = MODEL_MATRIX;
	m[3].y += ground_h(m[3].xz);
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], m[3]);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(vec4(length(m[0].xyz), 0.0, 0.0, 0.0), vec4(0.0, length(m[1].xyz), 0.0, 0.0), vec4(0.0, 0.0, length(m[2].xyz), 0.0), vec4(0.0, 0.0, 0.0, 1.0));
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
}

void fragment() {
	vec4 c = texture(icon, UV, sharpen) * tint;
	float on = 1.0;
	if (blink_period > 0.0) {
		on = step(1.0 - blink_on, fract(TIME / blink_period));
	}
	ALBEDO = c.rgb;
	ALPHA = c.a * on;
}
