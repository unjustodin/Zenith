// The backdrop on a space platform: black space with two layers of stars, a faint band of
// nebula, and, while the platform is at a planet (or near one on a route), that planet below the
// platform, big enough that its curve shows past the deck's edges from the default view (50
// degrees down, a narrow field of view).
// Stars are fixed to directions, so they stay put as the camera moves, like distant stars.
shader_type sky;

#include "res://shaders/sky_view.gdshaderinc"

uniform vec3 planet_color = vec3(0.25, 0.42, 0.55);
uniform float planet_on = 0.0;
// Where the planet is and how big it looks (radians). Straight below the platform, as Factorio draws
// the planet under it: fixed in the sky, so it looks the same whichever way the camera turns (F4).
uniform vec3 planet_dir = vec3(0.0, -1.0, 0.0);
uniform float planet_radius = 0.2;
// Factorio's own picture of the planet (its star map sprite, from the player's install), drawn
// over the disc; without one, the procedural sphere below.
uniform sampler2D planet_tex : source_color, filter_linear_mipmap;
uniform float planet_tex_on = 0.0;
// Factorio's own maps of the planet's whole surface (space-age/graphics/space/<planet>*.png, 2048 x
// 1024, longitude across, latitude down), wrapped round a lit sphere: the surface, its clouds
// (luminance and alpha) turning a little faster than the ground, and what glows on the night side
// (Vulcanus' lava). Used once loaded (main.gd); the star map picture above until then.
uniform sampler2D planet_map : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D planet_clouds : filter_linear_mipmap, repeat_enable;
uniform sampler2D planet_emission : source_color, filter_linear_mipmap, repeat_enable;
uniform float planet_map_on = 0.0;
uniform float planet_clouds_on = 0.0;
uniform float planet_emission_on = 0.0;

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

float value_noise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = mix(mix(hash13(i), hash13(i + vec3(1, 0, 0)), f.x), mix(hash13(i + vec3(0, 1, 0)), hash13(i + vec3(1, 1, 0)), f.x), f.y);
	float b = mix(mix(hash13(i + vec3(0, 0, 1)), hash13(i + vec3(1, 0, 1)), f.x), mix(hash13(i + vec3(0, 1, 1)), hash13(i + vec3(1, 1, 1)), f.x), f.y);
	return mix(a, b, f.z);
}

float fbm(vec3 p) {
	return value_noise(p) * 0.55 + value_noise(p * 2.1) * 0.28 + value_noise(p * 4.3) * 0.17;
}

vec3 stars(vec3 d, float scale, float threshold, float size, float salt) {
	vec3 p = d * scale;
	vec3 cell = floor(p);
	vec3 f = fract(p) - 0.5;
	float h = hash13(cell + salt);
	if (h < threshold) {
		return vec3(0.0);
	}
	vec3 offset = vec3(hash13(cell + salt + 1.7), hash13(cell + salt + 3.1), hash13(cell + salt + 5.3)) - 0.5;
	float dist = length(f - offset * 0.6);
	float b = smoothstep(size, 0.0, dist) * (0.4 + 0.6 * (h - threshold) / (1.0 - threshold));
	float warm = hash13(cell + salt + 7.9);
	return mix(vec3(0.75, 0.82, 1.0), vec3(1.0, 0.88, 0.72), warm) * b;
}

void sky() {
	vec3 d = sky_view_dir(EYEDIR, SCREEN_UV, AT_CUBEMAP_PASS);
	vec3 col = vec3(0.006, 0.007, 0.016);
	float band = exp(-pow(dot(d, normalize(vec3(0.4, 0.7, -0.6))), 2.0) * 6.0);
	col += vec3(0.012, 0.008, 0.02) * band * (0.4 + 0.6 * fbm(d * 6.0));
	col += stars(d, 150.0, 0.975, 0.16, 0.0) * 2.2;
	col += stars(d, 380.0, 0.97, 0.22, 11.0) * 0.9;
	if (planet_on > 0.5) {
		vec3 pd = normalize(planet_dir);
		float ang = acos(clamp(dot(d, pd), -1.0, 1.0));
		if (planet_map_on > 0.5 && ang < planet_radius * 1.25) {
			float r = ang / planet_radius;
			vec3 ref = abs(pd.y) > 0.99 ? vec3(0.0, 0.0, -1.0) : vec3(0.0, 1.0, 0.0);
			vec3 right = normalize(cross(pd, ref));
			vec3 up = cross(right, pd);
			vec3 sun = normalize(vec3(0.5, 0.8, 0.3));
			if (r < 1.0) {
				vec3 side = normalize(d - pd * dot(d, pd));
				vec3 n = normalize(pd * -sqrt(1.0 - r * r) + side * r);
				// The sphere's own frame: its pole towards the picture's top (north), facing us.
				vec3 local = vec3(dot(n, right), dot(n, up), dot(n, -pd));
				float lat = asin(clamp(local.y, -1.0, 1.0));
				float lon = atan(local.x, local.z);
				float spin = TIME * 0.004;
				vec2 uv = vec2(lon / TAU + 0.5 + spin, 0.5 - lat / PI);
				// Mip level from a longitude without the wrap's jump, so the seam shows no line.
				vec2 uv_alt = vec2(fract(lon / TAU + 1.0 + spin), uv.y);
				vec2 gx = dFdx(uv);
				vec2 gy = dFdy(uv);
				vec2 gx2 = dFdx(uv_alt);
				vec2 gy2 = dFdy(uv_alt);
				if (abs(gx2.x) + abs(gy2.x) < abs(gx.x) + abs(gy.x)) {
					gx = gx2;
					gy = gy2;
				}
				vec3 surface = textureGrad(planet_map, uv, gx, gy).rgb;
				float day = dot(n, sun);
				float light = smoothstep(-0.15, 0.35, day);
				vec3 lit = surface * (0.03 + 1.05 * light);
				if (planet_clouds_on > 0.5) {
					vec2 cuv = uv + vec2(TIME * 0.0025, 0.0);
					vec4 c = textureGrad(planet_clouds, cuv, gx, gy);
					lit = mix(lit, vec3(c.r) * (0.04 + 1.1 * light), c.g * 0.85);
				}
				if (planet_emission_on > 0.5) {
					vec3 glow = textureGrad(planet_emission, uv, gx, gy).rgb;
					lit += glow * (1.0 - light) * 1.4;
				}
				// The limb darkens a little, as a ball does.
				col = lit * mix(0.75, 1.0, sqrt(1.0 - r * r));
			}
			// Atmosphere: a thin glow of the planet's colour round the lit edge.
			float rim = smoothstep(1.12, 1.0, r) * smoothstep(0.86, 1.0, r);
			col += planet_color * rim * 0.45;
		} else if (planet_tex_on > 0.5 && ang < planet_radius * 1.05) {
			// The picture's top towards north (-Z) when the planet is straight below.
			vec3 ref = abs(pd.y) > 0.99 ? vec3(0.0, 0.0, -1.0) : vec3(0.0, 1.0, 0.0);
			vec3 right = normalize(cross(pd, ref));
			vec3 up = cross(right, pd);
			vec2 off = vec2(dot(d, right), dot(d, up)) / sin(planet_radius);
			vec2 uv = vec2(0.5, 0.5) + vec2(off.x, -off.y) * 0.5;
			if (uv.x >= 0.0 && uv.x <= 1.0 && uv.y >= 0.0 && uv.y <= 1.0) {
				vec4 t = texture(planet_tex, uv);
				col = mix(col, t.rgb, t.a);
			}
		} else if (planet_tex_on < 0.5 && ang < planet_radius * 1.25) {
			// A lit sphere: the sun comes from above, so its top is day and its underside night.
			float r = ang / planet_radius;
			if (r < 1.0) {
				vec3 side = normalize(d - pd * dot(d, pd));
				vec3 n = normalize(pd * -sqrt(1.0 - r * r) + side * r);
				float light = clamp(dot(n, normalize(vec3(0.5, 0.8, 0.3))) * 0.6 + 0.4, 0.0, 1.0);
				// Land and sea from noise on the sphere, and a few lighter clouds over them.
				float land = smoothstep(0.45, 0.55, fbm(n * 3.0));
				float clouds = smoothstep(0.55, 0.75, fbm(n * 5.0 + 9.0));
				vec3 surface = mix(planet_color * 0.55, planet_color * 1.15, land);
				surface = mix(surface, vec3(0.85), clouds * 0.6);
				col = surface * (0.04 + 0.6 * light * light);
			}
			// Atmosphere glow at the rim.
			float rim = smoothstep(1.25, 1.0, r) * smoothstep(0.8, 1.0, r);
			col += planet_color * rim * 0.25;
		}
	}
	COLOR = col;
}
