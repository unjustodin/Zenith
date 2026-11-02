shader_type spatial;
// Turret beams (turrets.gd): a frame of one of Factorio's beam sheets, repeated along a quad that
// runs from the muzzle to the target. UV.x runs along the beam, UV.y across it.
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, fog_disabled;

uniform sampler2D atlas : source_color, filter_linear, repeat_disable;
uniform vec2 grid = vec2(1.0);  // columns, rows of frames in the sheet
uniform vec2 cell = vec2(1.0);  // one frame's size as a fraction of the sheet
uniform bool vertical = false;  // the beam runs down each frame (the railgun's) instead of across
instance uniform float frame = 0.0;
instance uniform float tiles = 1.0;  // frames along the beam's length
instance uniform float strength = 1.0;

void fragment() {
	float u = fract(UV.x * tiles);
	float f = floor(frame);
	vec2 at = vec2(mod(f, grid.x), floor(f / grid.x));
	vec2 local = vertical ? vec2(UV.y, u) : vec2(u, UV.y);
	// Keep half a texel off the frame's edges so the neighbours don't bleed in.
	local = clamp(local, vec2(0.002), vec2(0.998));
	vec4 c = texture(atlas, (at + local) * cell);
	ALBEDO = c.rgb * strength;
	ALPHA = c.a;
}
