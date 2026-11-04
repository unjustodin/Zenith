shader_type spatial;
// Factorio's decoratives (decoratives.gd): one of a decorative's pictures per instance, from an
// atlas of its variants side by side. INSTANCE_CUSTOM is (u start, u width, v height, unused).
// Plants on the "object" layer (Gleba's) are cards standing up and turned to the camera around the
// vertical, cut out here; the ones lying flat are blended (decorative_flat.gdshader).
render_mode cull_disabled, shadows_disabled;

#include "res://shaders/ground_height.gdshaderinc"

uniform sampler2D atlas : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform bool upright = false;

void vertex() {
	UV = vec2(INSTANCE_CUSTOM.x + UV.x * INSTANCE_CUSTOM.y, UV.y * INSTANCE_CUSTOM.z);
	if (!upright) {
		VERTEX = ground_lift(VERTEX, MODEL_MATRIX);
	} else {
		mat4 m = MODEL_MATRIX;
		m[3].y += ground_h(m[3].xz);
		MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
			vec4(normalize(cross(vec3(0.0, 1.0, 0.0), INV_VIEW_MATRIX[2].xyz)), 0.0),
			vec4(0.0, 1.0, 0.0, 0.0),
			vec4(normalize(cross(INV_VIEW_MATRIX[0].xyz, vec3(0.0, 1.0, 0.0))), 0.0),
			m[3]);
		MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(vec4(length(m[0].xyz), 0.0, 0.0, 0.0), vec4(0.0, length(m[1].xyz), 0.0, 0.0),
			vec4(0.0, 0.0, length(m[2].xyz), 0.0), vec4(0.0, 0.0, 0.0, 1.0));
		MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
	}
}

void fragment() {
	vec4 c = texture(atlas, UV);
	ALBEDO = c.rgb;
	ALPHA = c.a;
	ALPHA_SCISSOR_THRESHOLD = 0.4;
	// Alpha to coverage with MSAA: the cut-out's edge is spread over the pixel's samples instead of
	// switching on or off, so it shimmers less as the camera moves.
	ALPHA_ANTIALIASING_EDGE = 0.4;
	ALPHA_TEXTURE_COORDINATE = UV * vec2(textureSize(atlas, 0));
}
