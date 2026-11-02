shader_type spatial;
// Leaf cards (model_library.gd: materials named "leafcard-..."): factorio_material.gdshader with
// the leaves cut out of each card (leaf_cut in the include) and both sides drawn.

render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley, specular_schlick_ggx;

#define LEAF_CUT
#include "res://shaders/factorio_material.gdshaderinc"
