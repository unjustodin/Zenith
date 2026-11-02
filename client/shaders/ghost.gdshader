shader_type spatial;
// Factorio's entity ghosts: the entity drawn in a translucent blue-white, unlit so it reads the
// same by day and night. A little shading from the normal and a brighter rim keep the shape.
render_mode unshaded, blend_mix, depth_draw_always, cull_back, shadows_disabled;

uniform vec4 tint : source_color = vec4(0.58, 0.68, 1.0, 0.42);

void fragment() {
	float facing = clamp(dot(NORMAL, normalize(vec3(0.3, 0.8, 0.5))) * 0.5 + 0.5, 0.0, 1.0);
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.0);
	ALBEDO = tint.rgb * (0.65 + 0.35 * facing) + vec3(rim * 0.25);
	ALPHA = clamp(tint.a + rim * 0.2, 0.0, 1.0);
}
