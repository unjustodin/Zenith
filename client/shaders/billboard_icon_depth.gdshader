shader_type spatial;
// billboard_icon.gdshader with the depth test on: Alt-mode icons in first person, hidden behind
// the buildings in front of them (alt_overlay.gd). A quad that faces the camera.
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

#include "res://shaders/ground_height.gdshaderinc"

uniform sampler2D icon : source_color, filter_linear_mipmap;
uniform vec4 tint : source_color = vec4(1.0);
// Seconds per blink; 0 keeps the icon steady.
uniform float blink_period = 0.0;

void vertex() {
	// Billboard, keeping the instance's scale.
	mat4 m = MODEL_MATRIX;
	m[3].y += ground_h(m[3].xz);
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], m[3]);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(vec4(length(m[0].xyz), 0.0, 0.0, 0.0), vec4(0.0, length(m[1].xyz), 0.0, 0.0), vec4(0.0, 0.0, length(m[2].xyz), 0.0), vec4(0.0, 0.0, 0.0, 1.0));
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
}

void fragment() {
	vec4 c = texture(icon, UV) * tint;
	float on = 1.0;
	if (blink_period > 0.0) {
		on = step(0.45, fract(TIME / blink_period));
	}
	ALBEDO = c.rgb;
	ALPHA = c.a * on;
}
