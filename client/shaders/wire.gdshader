shader_type spatial;
// Copper and circuit wires (wires.gd): the vertex colour, lit as a slightly metallic tube, riding
// on the hills (ground_height.gdshaderinc) as the poles do.
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

#include "res://shaders/ground_height.gdshaderinc"

void vertex() {
	VERTEX = ground_lift(VERTEX, MODEL_MATRIX);
}

void fragment() {
	ALBEDO = COLOR.rgb;
	ROUGHNESS = 0.55;
	METALLIC = 0.3;
}
