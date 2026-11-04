shader_type spatial;
// Land tiles and the banks down to the water.
//
// With a Factorio install (`textured`): each tile shows its variant of Factorio's own tile picture
// (a layer of `tiles`, slot in UV; see terrain_textures.gd), and up to two higher neighbouring
// tile types spread over its edges with a ragged, noisy mask, like Factorio's transitions. CUSTOM0
// = (own layer or -1, lower spreading layer, upper spreading layer, mask A + 256 * mask B), the
// masks being which of the 8 neighbours carry that type (bits: E W S N SE SW NE NW). CUSTOM1.x is
// the same kind of mask for water neighbours (a wet rim along the bank). COLOR tints the texture.
//
// Without (or for a tile with no picture): the tile's map colour (COLOR) broken up by
// world-space noise, so any tile type gets detail without a texture.

render_mode cull_back;

#include "res://shaders/noise.gdshaderinc"
#include "res://shaders/ground_height.gdshaderinc"

uniform float detail = 1.0;
uniform float bump = 1.0;
// How dark the joins between tiles are. Kept faint: Factorio's ground has no visible grid, but a
// hint of one helps read distances in 3D. Not drawn on textured ground, whose variants show it.
uniform float tile_edge = 0.04;

uniform bool textured = false;
uniform sampler2DArray tiles : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
// Per layer: first slot row, variant width and height in tiles, variant count.
uniform vec4 tile_info[96];  // terrain_textures.gd MAX_LAYERS
// Factorio shows its tile pictures unlit; under this scene's sun and sky they come out brighter,
// so they are toned down to match (the models' sprites use the same 0.8).
uniform float texture_gain = 0.8;
// How far (in tiles) a higher tile's edge reaches into its neighbour, and how soft it is.
uniform float reach = 0.4;
uniform float softness = 0.07;
uniform float raggedness = 1.0;
// The shore (textured only): how far the coast strays from the tile edge, and the width of the
// wet rim between the ground and the water.
uniform float coast_wander = 0.55;
uniform float rim = 0.14;

const vec2 SLOT = vec2(1.0 / 32.0, 1.0 / 16.0);

varying vec3 world_pos;
varying vec3 world_normal;
varying flat vec4 layers;
varying flat vec4 masks;
varying flat vec2 tile_origin;
// The hills' slope here (ground_height.gdshaderinc), world space; straight up on flat ground.
varying vec3 hill_normal;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	layers = CUSTOM0;
	masks = CUSTOM1;
	tile_origin = UV2;
	// Hills: the vertex lifted by the ground under it. world_pos stays flat, so the tile pictures,
	// noise and banks are worked out as before.
	hill_normal = ground_n(world_pos.xz);
	VERTEX = ground_lift(VERTEX, MODEL_MATRIX);
}

// Distance from `f` (position in the tile) to the nearest neighbour named in `mask`.
float mask_distance(int mask, vec2 f) {
	float d = 9.0;
	if ((mask & 1) != 0) d = min(d, 1.0 - f.x);
	if ((mask & 2) != 0) d = min(d, f.x);
	if ((mask & 4) != 0) d = min(d, 1.0 - f.y);
	if ((mask & 8) != 0) d = min(d, f.y);
	if ((mask & 16) != 0) d = min(d, length(1.0 - f));
	if ((mask & 32) != 0) d = min(d, length(vec2(f.x, 1.0 - f.y)));
	if ((mask & 64) != 0) d = min(d, length(vec2(1.0 - f.x, f.y)));
	if ((mask & 128) != 0) d = min(d, length(f));
	return d;
}

// How much of a higher neighbour shows d tiles from it, with the ragged offset n. Always all
// of it at the shared edge and none a tile away, so it joins up with the tiles on either side.
float spread_weight(float d, float n) {
	float wgt = 1.0 - smoothstep(reach - softness, reach + softness, d + n);
	wgt = max(wgt, 1.0 - smoothstep(0.0, 0.08, d));
	return wgt * (1.0 - smoothstep(0.85, 0.98, d));
}

// Where the coast runs, as an offset from the tiles' land/water edge (see the fragment).
float coast(vec2 w) {
	return coast_wander * (2.0 * fbm3(w * 0.45 + 11.3) - 1.0) + 0.1 * (vnoise(w * 3.1 + 2.9) - 0.5);
}

// Polynomial smooth minimum: rounds the corners where two edges' distances meet.
float smin(float a, float b, float k) {
	float h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
	return mix(b, a, h) - k * h * (1.0 - h);
}

// Like mask_distance, but with rounded corners: for the outline of a shore.
float smooth_distance(int mask, vec2 f) {
	float d = 9.0;
	float k = 0.45;
	if ((mask & 1) != 0) d = smin(d, 1.0 - f.x, k);
	if ((mask & 2) != 0) d = smin(d, f.x, k);
	if ((mask & 4) != 0) d = smin(d, 1.0 - f.y, k);
	if ((mask & 8) != 0) d = smin(d, f.y, k);
	// A corner next to a side that is already in counts for nothing more, and would only dent the
	// outline at every tile corner through smin.
	if ((mask & 16) != 0 && (mask & 5) == 0) d = smin(d, length(1.0 - f), k);
	if ((mask & 32) != 0 && (mask & 6) == 0) d = smin(d, length(vec2(f.x, 1.0 - f.y)), k);
	if ((mask & 64) != 0 && (mask & 9) == 0) d = smin(d, length(vec2(1.0 - f.x, f.y)), k);
	if ((mask & 128) != 0 && (mask & 10) == 0) d = smin(d, length(f), k);
	return d;
}

// A layer's texture at a world position, for where it spreads beyond its own tiles: the variant
// for each block of the world from a hash, so it doesn't repeat every few tiles.
vec3 layer_color(int layer, vec2 w, vec2 dx, vec2 dy) {
	vec4 info = tile_info[layer];
	vec2 size = max(info.yz, vec2(1.0));
	vec2 block = floor(w / size);
	float v = floor(hash12(block + float(layer) * 37.0) * max(info.w, 1.0));
	float per_row = floor(32.0 / size.x);
	vec2 slot = vec2(mod(v, per_row) * size.x, info.x + floor(v / per_row) * size.y);
	vec2 uv = (slot + (w - block * size)) * SLOT;
	return textureGrad(tiles, vec3(uv, float(layer)), dx * SLOT, dy * SLOT).rgb;
}

void fragment() {
	// Banks are vertical, so height goes into the noise coordinates or the noise would streak.
	vec2 p = world_pos.xz + world_pos.y * vec2(1.7, -1.3);
	float top = step(0.5, world_normal.y);
	vec2 w = world_pos.xz;
	vec2 dx = dFdx(w);
	vec2 dy = dFdy(w);
	// Position within the tile, from the tile's own corner: fract(w) would put a column of pixels
	// on each tile edge into the neighbouring tile and draw a line there.
	vec2 f = clamp(w - tile_origin, 0.0, 1.0);
	vec2 wt = tile_origin + clamp(f, 0.001, 0.999);

	float broad = fbm3(p * 0.06);  // patches a few tiles across
	vec3 mid = noised(p * 0.9);
	vec3 fine = noised(p * 4.3 + 31.7);
	int own = int(round(layers.x));
	int kind = int(round(masks.y));  // 0 ground or bank, 1 shelf under ground, 2 shelf over water
	vec3 albedo;
	float bump_scale = bump;
	if (textured && own >= 0) {
		if (kind == 2) {
			albedo = layer_color(own, wt, dx, dy) * texture_gain;
		} else {
			// Kept half a texel inside the tile's slot, so filtering doesn't reach the next one.
			vec2 uv = top > 0.5 ? UV + (clamp(f, 0.5 / 64.0, 1.0 - 0.5 / 64.0) - f) * SLOT : UV;
			albedo = texture(tiles, vec3(uv, float(own))).rgb * texture_gain;
		}
		// A whisper of broad variation keeps large fields from looking printed.
		albedo *= 1.0 + detail * 0.12 * (broad - 0.5);
		bump_scale *= 0.35;
	} else {
		// Grit: small dark and light specks where the finest noise is at its extremes.
		float grit = vnoise(p * 11.0 + 5.1);
		float shade = 1.0 + detail * (0.36 * (broad - 0.5) + 0.16 * (mid.x - 0.5) + 0.12 * (fine.x - 0.5)
			+ 0.10 * (smoothstep(0.7, 0.95, grit) - 1.0 + smoothstep(0.05, 0.3, grit)));
		// A slight warm/cool drift over large areas, like dry and damp ground.
		vec3 tint = mix(vec3(0.95, 1.0, 1.06), vec3(1.06, 1.0, 0.92), vnoise(p * 0.018 + 7.3));
		tint = mix(vec3(1.0), tint, detail);
		if (!textured) {
			vec2 e = abs(fract(world_pos.xz) - 0.5);
			shade *= 1.0 - tile_edge * top * smoothstep(0.43, 0.5, max(e.x, e.y));
		}
		albedo = vec3(shade) * tint;
	}
	albedo *= COLOR.rgb;

	float roughness = 0.95;
	// The coast (textured only): a line wandering up to `coast_wander` tiles either side of the
	// tiles' land/water edge, so it doesn't follow the grid. `t` is the signed distance across
	// that edge, negative on the land side; the coast is where t = c. The ground stops `rim`
	// short of it, a wet shelf just above the water fills the rim, and water (also drawn under
	// the land tiles along the shore) the rest.
	if (textured && top > 0.5 && kind > 0) {
		float c = coast(w);
		float d = smooth_distance(int(round(masks.x)), f);
		float t = kind == 2 ? d : -d;
		if (t > c) discard;
		float wet = smoothstep(c - rim, c, t);
		albedo *= mix(vec3(0.68, 0.66, 0.62), vec3(0.45, 0.47, 0.47), wet);
		roughness = mix(0.75, 0.4, wet);
	} else if (textured && top > 0.5) {
		// The ragged line Factorio's transition masks draw: blotches about a tile across with
		// a finer fringe.
		int wet_mask = int(round(masks.x));
		if (wet_mask != 0) {
			float c = coast(w);
			float t = -smooth_distance(wet_mask, f);
			if (t > c - rim) discard;
			// Damp ground along the edge.
			albedo *= 1.0 - 0.25 * (1.0 - smoothstep(0.0, 0.3, c - rim - t));
		}
		int packed = int(round(layers.w));
		int mask_a = packed & 255;
		int mask_b = (packed >> 8) & 255;
		int la = int(round(layers.y));
		int lb = int(round(layers.z));
		float n = 0.0;
		if (packed != 0) {
			n = raggedness * (0.55 * (2.0 * fbm3(w * 1.4 + 3.7) - 1.0) + 0.2 * (vnoise(w * 5.3 + 9.2) - 0.5));
		}
		if (la >= 0 && mask_a != 0) {
			float wa = spread_weight(mask_distance(mask_a, f), n);
			if (wa > 0.0) albedo = mix(albedo, layer_color(la, wt, dx, dy) * texture_gain, wa);
		}
		if (lb >= 0 && mask_b != 0) {
			float wb = spread_weight(mask_distance(mask_b, f), n);
			if (wb > 0.0) albedo = mix(albedo, layer_color(lb, wt, dx, dy) * texture_gain, wb);
		}
	}

	ALBEDO = albedo;
	ROUGHNESS = roughness;
	SPECULAR = 0.3;

	if (top > 0.5) {
		// Height = 0.06 * mid + 0.015 * fine; the gradient tilts the normal. Chain rule: the
		// noise is sampled at p * scale, so its gradient scales too.
		vec2 grad = bump_scale * (mid.yz * 0.9 * 0.06 + fine.yz * 4.3 * 0.015);
		vec3 nrm = normalize(hill_normal + vec3(-grad.x, 0.0, -grad.y));
		NORMAL = normalize((VIEW_MATRIX * vec4(nrm, 0.0)).xyz);
	}
}
