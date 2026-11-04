// Items drawn as Factorio's icon (item_cards.gd): a card lying face up, cut out by the icon's
// alpha. Glides like item.gdshader.
shader_type spatial;
render_mode world_vertex_coords;

#include "res://shaders/belt_path.gdshaderinc"
#include "res://shaders/ground_height.gdshaderinc"
#include "res://shaders/icon_lod.gdshaderinc"

uniform sampler2D icon : source_color, filter_linear_mipmap_anisotropic;

void vertex() {
	VERTEX = belt_vertex(VERTEX, INSTANCE_CUSTOM);
	VERTEX.y += ground_h(VERTEX.xz);  // world coordinates here
}

void fragment() {
	vec4 c = icon_texel(icon, UV);
	ALBEDO = c.rgb;
	ALPHA = c.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	ROUGHNESS = 0.9;
}
