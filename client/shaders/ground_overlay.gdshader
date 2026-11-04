shader_type spatial;
// Factorio's flat marks over the world (the hover brackets, arrows, roboport and drill areas, rail
// planner arrows, Alt-mode arrows, health bars), drawn over everything as before but riding on the
// hills (ground_height.gdshaderinc): the vertex colour, times a picture when one is set.
render_mode unshaded, blend_mix, depth_test_disabled, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

#include "res://shaders/ground_height.gdshaderinc"

uniform sampler2D picture : source_color, filter_linear_mipmap, repeat_disable;
uniform bool use_picture = false;
uniform vec4 tint : source_color = vec4(1.0);

void vertex() {
	VERTEX = ground_lift(VERTEX, MODEL_MATRIX);
}

void fragment() {
	vec4 c = COLOR * tint;
	if (use_picture) {
		c *= texture(picture, UV);
	}
	ALBEDO = c.rgb;
	ALPHA = c.a;
}
