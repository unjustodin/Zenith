shader_type spatial;
// Flying robots drawn by robot_swarm.gd: factorio_material.gdshader with the robots' bob, thruster
// swing, lamps and glow done per instance (robot_vertex in the include), each robot drawn where its
// record (mover_records.gdshaderinc) says it is now.

render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

#define ROBOT
#define MOVER
#include "res://shaders/factorio_material.gdshaderinc"
