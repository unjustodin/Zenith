shader_type spatial;
// The see-through variant of factorio_material_mover.gdshader.

render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

#define BLEND_ALPHA
#define MOVER
#include "res://shaders/factorio_material.gdshaderinc"
