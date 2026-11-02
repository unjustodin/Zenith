// Cloud shadows and haze over everything on the ground, in one full-screen pass after the opaque
// geometry (scripts/world/sky.gd): each pixel's ground position comes from the depth buffer, is
// carried up along the sunlight to the cloud layer, and darkens by the cloud density there, like
// Factorio's cloud shadows drifting over the base. A planet with haze (Vulcanus' yellow fog,
// Gleba's humid air) gets slow coloured patches of it on top. The sky (nothing in the depth
// buffer) is left alone. Premultiplied alpha: result = haze + under * (1 - alpha).
shader_type spatial;
render_mode unshaded, blend_premul_alpha, depth_draw_never, depth_test_disabled, cull_disabled, fog_disabled, shadows_disabled;

#include "res://shaders/clouds.gdshaderinc"

uniform sampler2D depth_texture : hint_depth_texture, filter_nearest;
// Towards the sun (its height decides how far the shadow falls from the cloud).
uniform vec3 sun_dir = vec3(0.0, 0.7, -0.7);
uniform float cloud_height = 70.0;
// How dark a full cloud's shadow is (Factorio's clouds opacity, 0.25), already faded for night.
uniform float shadow_strength = 0.25;
uniform vec3 haze_color : source_color = vec3(1.0, 0.87, 0.3);
uniform vec3 haze_color2 : source_color = vec3(1.0, 0.87, 0.29);
uniform float haze_strength = 0.0;

void vertex() {
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

void fragment() {
	float depth = texture(depth_texture, SCREEN_UV).r;
	if (depth <= 0.0) {
		discard;  // the sky (reverse depth: 0 is infinitely far)
	}
	vec4 world = INV_VIEW_MATRIX * INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth, 1.0);
	vec3 pos = world.xyz / world.w;
	vec3 sd = normalize(sun_dir);
	vec2 p = pos.xz + sd.xz / max(sd.y, 0.25) * (cloud_height - pos.y);
	float shadow = shadow_strength > 0.0 ? cloud_density(p) * shadow_strength : 0.0;
	float h = 0.0;
	vec3 hc = haze_color;
	if (haze_strength > 0.0) {
		// Low, slow patches: the cloud noise at a bigger scale, moving at a third of the speed.
		vec2 q = pos.xz * 1.7 + vec2(97.0, 41.0) + cloud_wind * TIME * -1.3;
		float n = cloud_density(q);
		hc = mix(haze_color, haze_color2, texture(cloud_detail, pos.xz / 210.0).r);
		h = haze_strength * (0.25 + n);
	}
	float a = 1.0 - (1.0 - shadow) * (1.0 - h);
	if (a < 0.002) {
		discard;
	}
	ALBEDO = hc * h;
	ALPHA = a;
}
