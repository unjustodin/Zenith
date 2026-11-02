shader_type spatial;
// The see-through variant of factorio_material.gdshader (glass), alpha from the base colour.

render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

#define BLEND_ALPHA
#include "res://shaders/factorio_material.gdshaderinc"
