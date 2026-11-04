shader_type spatial;
// belt_lanes.gd: one item icon per belt lane, lying on the belt, cut out by the icon's alpha. Left
// out on the belts whose items belt_items.gd draws (the belt's centre, in the instance's custom data,
// inside the square the items were read round) and past the chosen distance.
render_mode world_vertex_coords, cull_disabled, shadows_disabled;

#include "res://shaders/icon_lod.gdshaderinc"
#include "res://shaders/ground_height.gdshaderinc"

uniform sampler2D icon : source_color, filter_linear_mipmap_anisotropic;
uniform vec2 focus = vec2(0.0);
uniform float near = 22.0;
uniform float far = 160.0;

varying vec2 world_xz;
varying flat vec2 belt;

void vertex() {
	world_xz = VERTEX.xz;
	belt = INSTANCE_CUSTOM.xy;
	VERTEX.y += ground_h(VERTEX.xz);  // world coordinates here
}

void fragment() {
	vec2 d = abs(belt - focus);
	// The near area is a square of belts, as the mod reads them: a belt is in it or not, whole.
	if (max(d.x, d.y) < near || length(world_xz - focus) > far) {
		discard;
	}
	vec4 c = icon_texel(icon, UV);
	ALBEDO = c.rgb;
	ALPHA = c.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	ROUGHNESS = 0.9;
}
