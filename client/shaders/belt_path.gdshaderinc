// Items on belts glide on the GPU between updates (belt_items.gd, belt_paths.gd). An instance's
// custom data says how: w = 0, in a straight line by xyz × `glide`; w > 0, along its lane's path,
// points read from `belt_paths` (an offset from the instance's place and 1 where it shows, 0 under
// the ground): w - 1 = first point × 64 + points - 2. `glide` is how far along, 0 to 1.
uniform float glide = 0.0;
uniform sampler2D belt_paths : filter_nearest, repeat_disable;

vec4 belt_glide(vec4 custom) {
	if (custom.w < 0.5) {
		return vec4(custom.xyz * glide, 1.0);
	}
	int code = int(custom.w + 0.5) - 1;
	int first = code / 64;
	int pieces = code - first * 64 + 1;
	float f = clamp(glide, 0.0, 1.0) * float(pieces);
	int i = min(int(f), pieces - 1);
	int width = textureSize(belt_paths, 0).x;
	int a = first + i;
	vec4 p0 = texelFetch(belt_paths, ivec2(a % width, a / width), 0);
	vec4 p1 = texelFetch(belt_paths, ivec2((a + 1) % width, (a + 1) / width), 0);
	return mix(p0, p1, f - float(i));
}

// Moves a vertex (world coordinates) where its item is drawn now; under the ground, nowhere.
vec3 belt_vertex(vec3 vertex, vec4 custom) {
	vec4 o = belt_glide(custom);
	return o.w >= 0.5 ? vertex + o.xyz : vec3(0.0);
}
