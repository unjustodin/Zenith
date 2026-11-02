shader_type spatial;
// belt_lanes.gd: one item icon per belt lane, lying on the belt, cut out by the icon's alpha. Left
// out near the focus (where belt_items.gd draws every item) and past the chosen distance.
render_mode world_vertex_coords, cull_disabled, shadows_disabled;

uniform sampler2D icon : source_color, filter_linear_mipmap_anisotropic;
uniform vec2 focus = vec2(0.0);
uniform float near = 22.0;
uniform float far = 160.0;

varying vec2 world_xz;

void vertex() {
	world_xz = VERTEX.xz;
}

void fragment() {
	vec2 d = abs(world_xz - focus);
	// The near area is a square, like the mod's detail area.
	if (max(d.x, d.y) < near || length(world_xz - focus) > far) {
		discard;
	}
	vec4 c = texture(icon, UV);
	ALBEDO = c.rgb;
	ALPHA = c.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	ROUGHNESS = 0.9;
}
