// Cloud density over the ground, shared by the sky (shaders/planet_sky.gdshader) and the cloud
// shadows (shaders/cloud_shadows.gdshader), so the clouds seen in the sky are the ones whose
// shadows cross the ground. The noise is Factorio's own (core/graphics/clouds-noise.png: red and
// green warp the shape in blue; clouds-detail-noise.png roughens the edges), loaded from the
// player's install by scripts/world/sky.gd, with a generated noise in its place without one.
// They drift with the wind: TIME, so both shaders agree without a uniform per frame.

uniform sampler2D cloud_shape : repeat_enable, filter_linear_mipmap;
uniform sampler2D cloud_detail : repeat_enable, filter_linear_mipmap;
// Tiles per second, Godot x/z (Factorio x east, y south).
uniform vec2 cloud_wind = vec2(0.9, 0.3);
// One repeat of the noise, in tiles.
uniform float cloud_tile = 280.0;
// Density at which a cloud begins and where it is solid: lower means more sky covered.
uniform float cloud_cover = 0.5;
uniform float cloud_softness = 0.4;

float cloud_density(vec2 p) {
	vec2 uv = (p - cloud_wind * TIME) / cloud_tile;
	// The warp drifts at a slightly different speed, so the shapes change as they travel.
	vec2 warp = texture(cloud_shape, uv * 0.47 + vec2(0.31, 0.17) + cloud_wind * TIME / cloud_tile * 0.35).rg - 0.5;
	// A blurrier mip of the shape: Factorio's cloud shadows have soft edges.
	float shape = 1.0 - texture(cloud_shape, uv + warp * 0.09, 2.0).b;
	float detail = texture(cloud_detail, uv * 3.3 - cloud_wind * TIME / cloud_tile * 0.6).r;
	float d = shape * 0.85 + (detail - 0.5) * 0.3;
	return smoothstep(cloud_cover - cloud_softness * 0.5, cloud_cover + cloud_softness * 0.5, d);
}
