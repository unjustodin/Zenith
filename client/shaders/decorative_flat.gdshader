shader_type spatial;
// Factorio's flat decoratives (decoratives.gd): grass, flowers, bushes, small rocks and decals lying on
// the ground, blended as Factorio draws them. As hard cut-outs their thin leaves crawled and sparkled
// whenever the view moved less than a pixel. They write no depth and are drawn in a fixed order (each
// decorative a render priority by Factorio's layer), so overlapping ones never swap. The atlas's
// colours are spread into its see-through pixels before its mipmaps are made (fix_alpha_edges), so far
// away they fade evenly instead of darkening at their edges. INSTANCE_CUSTOM is (u start, u width,
// v height, unused). They take the sun's shadows (trees' and buildings' fall over them, as in Factorio)
// but cast none (decoratives.gd turns casting off).
render_mode blend_mix, depth_draw_never, cull_disabled;

#include "res://shaders/ground_height.gdshaderinc"

uniform sampler2D atlas : source_color, filter_linear_mipmap_anisotropic, repeat_disable;

void vertex() {
	UV = vec2(INSTANCE_CUSTOM.x + UV.x * INSTANCE_CUSTOM.y, UV.y * INSTANCE_CUSTOM.z);
	VERTEX = ground_lift(VERTEX, MODEL_MATRIX);
}

void fragment() {
	vec4 c = texture(atlas, UV);
	ALBEDO = c.rgb;
	ALPHA = c.a;
}
