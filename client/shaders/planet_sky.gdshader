// A planet's sky (scripts/world/sky.gd sets the colours for the planet and the time of day): a
// gradient from the horizon up, the sun with a glow, stars at night, the clouds whose shadows cross
// the ground (shaders/clouds.gdshaderinc), haze at the horizon and, on Fulgora, lightning flashes.
// Stars and clouds are skipped in the radiance pass that lights reflections, which stays cheap.
shader_type sky;

#include "res://shaders/clouds.gdshaderinc"
#include "res://shaders/sky_view.gdshaderinc"

uniform vec3 zenith_color : source_color = vec3(0.3, 0.5, 0.78);
uniform vec3 horizon_color : source_color = vec3(0.7, 0.8, 0.88);
uniform vec3 ground_color : source_color = vec3(0.32, 0.3, 0.26);
// Towards the sun, and how bright its disc and glow are (0 below the horizon).
uniform vec3 sun_dir = vec3(0.0, 0.7, -0.7);
uniform vec3 sun_color : source_color = vec3(1.0, 0.95, 0.85);
uniform float sun_strength = 1.0;
uniform float stars = 0.0;
uniform vec3 cloud_color : source_color = vec3(1.0);
uniform vec3 cloud_shade : source_color = vec3(0.62, 0.66, 0.72);
uniform float cloud_alpha = 0.85;
uniform float cloud_height = 70.0;
uniform vec3 haze_color : source_color = vec3(0.8, 0.85, 0.9);
uniform float haze = 0.0;
uniform float flash = 0.0;

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

vec3 star_layer(vec3 d, float scale, float threshold, float size, float salt) {
	vec3 p = d * scale;
	vec3 cell = floor(p);
	vec3 f = fract(p) - 0.5;
	float h = hash13(cell + salt);
	if (h < threshold) {
		return vec3(0.0);
	}
	vec3 offset = vec3(hash13(cell + salt + 1.7), hash13(cell + salt + 3.1), hash13(cell + salt + 5.3)) - 0.5;
	float b = smoothstep(size, 0.0, length(f - offset * 0.6)) * (0.4 + 0.6 * (h - threshold) / (1.0 - threshold));
	return mix(vec3(0.75, 0.82, 1.0), vec3(1.0, 0.88, 0.72), hash13(cell + salt + 7.9)) * b;
}

void sky() {
	vec3 d = sky_view_dir(EYEDIR, SCREEN_UV, AT_CUBEMAP_PASS);
	float up = d.y;
	vec3 col = mix(horizon_color, zenith_color, pow(clamp(up, 0.0, 1.0), 0.45));
	col = mix(col, ground_color, smoothstep(0.0, -0.12, up));
	vec3 sd = normalize(sun_dir);
	float s = max(dot(d, sd), 0.0);
	// The glow around the sun warms the horizon on its side.
	col += sun_color * sun_strength * (pow(s, 6.0) * 0.18 + pow(s, 48.0) * 0.35);
	col += sun_color * sun_strength * smoothstep(0.9993, 0.9997, s) * 6.0;
	if (!AT_CUBEMAP_PASS) {
		if (stars > 0.0 && up > -0.05) {
			col += (star_layer(d, 90.0, 0.97, 0.22, 0.0) * 1.8 + star_layer(d, 200.0, 0.965, 0.25, 11.0) * 0.8)
				* stars * smoothstep(-0.05, 0.25, up);
		}
		if (cloud_alpha > 0.0 && up > 0.015) {
			vec2 p = POSITION.xz + d.xz / up * max(cloud_height - POSITION.y, 10.0);
			float c = cloud_density(p);
			// Lit on the sun's side; thin out towards the horizon, where they would shimmer.
			vec3 cc = mix(cloud_shade, cloud_color, 0.55 + 0.45 * s);
			col = mix(col, cc, c * cloud_alpha * smoothstep(0.015, 0.2, up));
			// Clouds hide the stars behind them (added above), mostly.
		}
	}
	col = mix(col, haze_color, haze * exp(-max(up, 0.0) * 7.0));
	col += vec3(0.75, 0.8, 1.0) * flash * (0.4 + 0.6 * smoothstep(-0.1, 0.5, up));
	COLOR = col;
}
