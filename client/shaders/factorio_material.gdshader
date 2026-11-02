shader_type spatial;
// Every model surface (model_library.gd): the imported colour, roughness and metallic, weathered
// to match Factorio's sprites. The work is in factorio_material.gdshaderinc.

render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

#include "res://shaders/factorio_material.gdshaderinc"
