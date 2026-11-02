// Value noise shared by the terrain and water shaders: the procedural ground without a Factorio
// install, and the ripples, ragged transitions and coast with one.

// Hash of a lattice point. Wrapping the lattice keeps fract() precise far from the origin,
// and the wrap is seamless because neighbouring cells wrap together.
float hash12(vec2 p) {
	p = mod(p, 4096.0);
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

// Value noise in [0, 1] with its analytic gradient: (value, d/dx, d/dy). The gradient gives a
// bump normal without sampling the noise again.
vec3 noised(vec2 x) {
	vec2 i = floor(x);
	vec2 f = fract(x);
	vec2 u = f * f * (3.0 - 2.0 * f);
	vec2 du = 6.0 * f * (1.0 - f);
	float a = hash12(i);
	float b = hash12(i + vec2(1.0, 0.0));
	float c = hash12(i + vec2(0.0, 1.0));
	float d = hash12(i + vec2(1.0, 1.0));
	float k1 = b - a;
	float k2 = c - a;
	float k4 = a - b - c + d;
	return vec3(a + k1 * u.x + k2 * u.y + k4 * u.x * u.y, du * vec2(k1 + k4 * u.y, k2 + k4 * u.x));
}

float vnoise(vec2 x) {
	return noised(x).x;
}

// Three octaves, rotated between octaves so the lattice doesn't line up with the tile grid.
float fbm3(vec2 p) {
	const mat2 rot = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8));
	float v = 0.5 * vnoise(p);
	p = rot * p * 2.03;
	v += 0.3 * vnoise(p);
	p = rot * p * 2.01;
	v += 0.2 * vnoise(p);
	return v;
}
