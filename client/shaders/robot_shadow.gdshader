shader_type spatial;
// Flying robots' drop shadows (robot_swarm.gd), as Factorio draws them: the robot's parts squashed
// flat on the ground in see-through black, offset as its shadow sprites are (0.99 tiles east, 0.83
// south), turned and placed from the robot's record (mover_records.gdshaderinc). INSTANCE_CUSTOM.r
// is the record's slot; the instance transform is a plain translation.

render_mode blend_mix, depth_draw_opaque, cull_disabled, unshaded, shadows_disabled;

#include "res://shaders/mover_records.gdshaderinc"

const vec3 SHADOW_OFFSET = vec3(0.99, 0.0, 0.83);
const float SHADOW_SQUASH = 0.01;
const float SHADOW_HEIGHT = 0.03;

void vertex() {
	MoverState s = mover_state(int(INSTANCE_CUSTOM.r + 0.5));
	s.pos = vec3(s.pos.x + SHADOW_OFFSET.x, SHADOW_HEIGHT, s.pos.z + SHADOW_OFFSET.z);
	vec3 v = vec3(VERTEX.x, VERTEX.y * SHADOW_SQUASH, VERTEX.z);
	vec3 n = NORMAL;
	mover_place(v, n, s, MODEL_MATRIX[3].xyz);
	VERTEX = v;
}

void fragment() {
	ALBEDO = vec3(0.0);
	ALPHA = 0.45;
}
