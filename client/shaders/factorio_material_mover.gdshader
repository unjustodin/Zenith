shader_type spatial;
// Walking creatures drawn by creatures.gd: factorio_material.gdshader, with each walker drawn where
// its record (mover_records.gdshaderinc) says it is now, its gait and bob worked out here too.

render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

#define MOVER
#include "res://shaders/factorio_material.gdshaderinc"
