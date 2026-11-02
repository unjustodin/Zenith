// The remote view's fog where no radar sees (scripts/world/remote_fog.gd), in one full-screen pass
// after everything else in the world: each pixel's ground position comes from the depth buffer (or,
// where nothing was drawn, from where its view ray meets the ground) and picks its chunk in a small
// texture (one texel a chunk, 1 where radars or the character see). Seen chunks are left alone, in
// full colour; elsewhere a dark, slowly drifting fog covers everything, as Factorio's remote view
// shows what it doesn't see, with a soft, ragged edge that starts at the coverage's border and lies
// wholly outside it.
shader_type spatial;
render_mode unshaded, depth_draw_never, depth_test_disabled, cull_disabled, fog_disabled, shadows_disabled;

uniform sampler2D depth_texture : hint_depth_texture, filter_nearest;
uniform sampler2D seen_texture : filter_nearest, repeat_disable;
// The chunk at the texture's first texel, and the texture's size in chunks.
uniform vec2 origin_chunk = vec2(0.0);
uniform float size = 256.0;
// Tiles from the border to full fog (under a chunk, so the 3 x 3 chunks round a pixel are enough).
uniform float edge = 10.0;
uniform vec3 fog_dark : source_color = vec3(0.010, 0.011, 0.014);
uniform vec3 fog_light : source_color = vec3(0.060, 0.062, 0.070);

void vertex() {
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

float seen_chunk(vec2 chunk) {
	vec2 p = chunk - origin_chunk;
	if (p.x < 0.0 || p.y < 0.0 || p.x >= size || p.y >= size) {
		return 0.0;
	}
	return texelFetch(seen_texture, ivec2(p), 0).r;
}

// Without sin(): the GPU's sin of big arguments repeats in streaks, which showed as blocks in the fog.
float hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * noise(p);
		p = mat2(vec2(1.6, 1.2), vec2(-1.2, 1.6)) * p + vec2(17.0, 9.0);  // turned, so no grid shows
		a *= 0.5;
	}
	return v;
}

vec3 view_point(vec2 uv, float depth, mat4 inv_projection) {
	vec4 p = inv_projection * vec4(uv * 2.0 - 1.0, depth, 1.0);
	return p.xyz / p.w;
}

void fragment() {
	// The view ray, worked out in view space and then turned into the world: two points near the
	// camera subtracted in world space lose too much precision far from the map's origin. Reverse
	// depth: 1 is the near plane; 0.5 stays finite for a perspective camera too.
	vec3 near_v = view_point(SCREEN_UV, 1.0, INV_PROJECTION_MATRIX);
	vec3 dir = mat3(INV_VIEW_MATRIX) * (view_point(SCREEN_UV, 0.5, INV_PROJECTION_MATRIX) - near_v);
	vec3 origin = (INV_VIEW_MATRIX * vec4(near_v, 1.0)).xyz;
	// Where the ray meets the ground (y = 0). The fog's pattern lies there, so it doesn't trace the
	// outlines of what stands under it. Above the horizon: far beyond anything a radar sees.
	bool ground = dir.y < -1e-6;
	vec2 floor_tile = ground ? (origin + dir * (-origin.y / dir.y)).xz : origin.xz + normalize(dir.xz + vec2(1e-6)) * 1e5;
	// Whatever is drawn here decides whether it is seen (a tall machine in a seen chunk stays in view
	// in front of the fog); where nothing is (the sky, or a chunk hidden under the fog), the ground.
	float depth = texture(depth_texture, SCREEN_UV).r;
	vec2 tile = floor_tile;
	if (depth > 0.0) {
		tile = (INV_VIEW_MATRIX * vec4(view_point(SCREEN_UV, depth, INV_PROJECTION_MATRIX), 1.0)).xz;
		ground = true;
	}
	float dist = 1e9;
	if (ground) {
		vec2 chunk = floor(tile / 32.0);
		if (seen_chunk(chunk) > 0.5) {
			discard;
		}
		for (int i = -1; i <= 1; i++) {
			for (int j = -1; j <= 1; j++) {
				vec2 c = chunk + vec2(float(i), float(j));
				if ((i != 0 || j != 0) && seen_chunk(c) > 0.5) {
					vec2 q = max(max(c * 32.0 - tile, tile - (c * 32.0 + 32.0)), vec2(0.0));
					dist = min(dist, length(q));
				}
			}
		}
	}
	vec2 drift = vec2(TIME * 0.35, TIME * 0.12);
	float n = fbm(floor_tile / 22.0 + drift / 22.0);
	// Ragged border: the noise pushes the fog's edge in and out by a few tiles, never into coverage.
	float a = smoothstep(0.0, edge, dist - (n - 0.5) * edge * 0.8);
	float m = fbm(floor_tile / 9.0 - drift / 15.0 + vec2(40.0, 13.0));
	ALBEDO = mix(fog_dark, fog_light, smoothstep(0.25, 0.85, n * 0.6 + m * 0.4));
	ALPHA = a;
}
