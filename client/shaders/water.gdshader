shader_type spatial;
// Water tiles: drifting ripples in the normal, a fresnel sky tint and foam along the shore.
// Vertex alpha is 1 at tile corners that touch land. The colour is Factorio's own water picture
// when there is an install (`textured`; CUSTOM0 = (own layer, the other water type nearby, that
// type's share at this corner), so water and deep water blend instead of meeting in squares),
// else the tile's map colour (vertex colour).
// Opaque on purpose: transparent water would need sorting and a sea bed.

render_mode cull_back, specular_schlick_ggx;

#include "res://shaders/noise.gdshaderinc"

uniform vec3 sky_tint : source_color = vec3(0.50, 0.62, 0.72);
uniform vec3 foam_color : source_color = vec3(0.86, 0.90, 0.90);
uniform float ripple = 1.0;
uniform float speed = 1.0;

uniform bool textured = false;
uniform sampler2DArray tiles : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform vec4 tile_info[96];  // terrain_textures.gd MAX_LAYERS
uniform float texture_brightness = 0.95;
// How much sky each layer reflects: 1 for water, less for Gleba's swamps and Aquilo's brash ice,
// which Factorio draws murky with no sky in them.
uniform float tile_reflect[96];

const vec2 SLOT = vec2(1.0 / 32.0, 1.0 / 16.0);

varying vec3 world_pos;
varying flat vec2 water_layers;
varying float other_share;
varying flat vec2 tile_origin;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	water_layers = CUSTOM0.xy;
	other_share = CUSTOM0.z;
	tile_origin = UV2;
}

// Same as the terrain shader's: a layer's picture at a world position, variant per block.
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
	vec2 p = world_pos.xz;
	float t = TIME * speed;

	// Three layers drifting in different directions; summing their gradients (scaled by the
	// sampling frequency) gives the ripple normal.
	vec3 a = noised(p * 0.45 + vec2(t * 0.11, t * 0.07));
	vec3 b = noised(p * 1.3 + vec2(-t * 0.17, t * 0.12) + 13.1);
	vec3 c = noised(p * 3.4 + vec2(t * 0.31, -t * 0.23) + 47.9);
	vec2 grad = ripple * (a.yz * 0.45 * 0.30 + b.yz * 1.3 * 0.11 + c.yz * 3.4 * 0.035);
	vec3 n = normalize(vec3(-grad.x, 1.0, -grad.y));
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);

	float shore = COLOR.a;
	vec3 water = COLOR.rgb;
	float wobble = 0.62 + 0.2 * (a.x * 0.6 + b.x * 0.4);
	int own = int(round(water_layers.x));
	float sky_share = 1.0;
	if (textured && own >= 0) {
		vec2 dx = dFdx(p);
		vec2 dy = dFdy(p);
		// Which tile this pixel is in from the tile's corner, not from p, so no line of pixels
		// along a tile edge picks the neighbouring block's variant.
		vec2 pt = tile_origin + clamp(p - tile_origin, 0.001, 0.999);
		water = layer_color(own, pt, dx, dy);
		int other = int(round(water_layers.y));
		if (other >= 0) {
			// Deep and shallow water meet along a slow, soft, wandering line.
			float edge = other_share + 0.35 * (fbm3(p * 0.35 + 5.1) - 0.5);
			water = mix(water, layer_color(other, pt, dx, dy), smoothstep(0.35, 0.65, edge));
		}
		water *= texture_brightness;
		sky_share = tile_reflect[own];
		wobble = 0.85 + 0.15 * (a.x * 0.6 + b.x * 0.4);
	}
	vec3 base = water * wobble;
	// Faint bright lines along the ridges of the middle layer, like wave crests, fading in and
	// out with the broad layer so they don't form an even net.
	base += sky_share * vec3(0.06, 0.08, 0.09) * pow(1.0 - abs(2.0 * b.x - 1.0), 8.0) * smoothstep(0.25, 0.75, a.x);
	// Shallow water by the bank is lighter and a little greener.
	base = mix(base, water * 1.1 + vec3(0.0, 0.04, 0.02), shore * shore * (textured ? 0.0 : 0.6));

	// Schlick with a raised floor: the camera looks down steeply, so plain Schlick would give
	// almost no sky reflection anywhere on screen.
	float facing = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float fresnel = 0.08 + 0.92 * pow(1.0 - facing, 4.0);
	vec3 col = mix(base, sky_tint, clamp(fresnel * 0.6, 0.0, 0.4) * sky_share);

	float foam_noise = vnoise(p * 2.2 + vec2(t * 0.21, -t * 0.16));
	float lap = 0.07 * sin(t * 1.4 + (p.x + p.y) * 0.8);
	float foam = smoothstep(0.7, 0.95, shore - 0.45 * foam_noise + lap + 0.15);
	// Factorio's shores have no surf; with textures the wet shelf of the bank makes the edge,
	// and anything following the tile corners would show the grid.
	if (textured) foam = 0.0;

	ALBEDO = mix(col, foam_color, foam * 0.65);
	ROUGHNESS = mix(0.07, 0.6, foam);
	SPECULAR = 0.6;
	METALLIC = 0.0;
}
