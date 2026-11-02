// The direction a sky pixel looks in. Godot builds a sky's view rays from the camera's projection as
// if it were a perspective one, so under an orthographic camera (Factorio's view, F6) the field of
// view grows to nearly 180 degrees and the sky smears towards the edges. There
// main.gd sets these, and the sky is drawn as a perspective camera turned the same way would see it.
// The cubemap pass that lights reflections has its own rays, which are right either way.
uniform float view_ortho = 0.0;
uniform mat3 view_basis = mat3(1.0);
// tan of half the field of view, across and up.
uniform vec2 view_tan = vec2(0.56, 0.32);

vec3 sky_view_dir(vec3 eyedir, vec2 screen_uv, bool cubemap) {
	if (view_ortho < 0.5 || cubemap) {
		return normalize(eyedir);
	}
	vec2 ndc = screen_uv * 2.0 - 1.0;
	return normalize(view_basis * vec3(ndc.x * view_tan.x, -ndc.y * view_tan.y, -1.0));
}
