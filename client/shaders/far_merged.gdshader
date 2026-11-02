shader_type spatial;
// Far chunks' buildings merged into one mesh each (far_chunks.gd): every model's colour is baked
// into its vertices from the same rules factorio_material.gdshaderinc applies (part colours,
// palette greying, baked occlusion), so one material draws them all. What is left here is what
// depends on the light and the view: flat faces, the part colours' top and side balance, a little
// grime from the ground.
//
// COLOR.rgb: the colour's square root (8 bits a channel keep dark paint smooth that way).
// COLOR.a: 16 * metallic step + part-colour step, each 0-15 (far_chunks.gd Bake).

render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform vec2 part_light = vec2(0.95, 0.6);
uniform vec3 grime_color : source_color = vec3(0.13, 0.11, 0.09);
uniform float ground_grime = 0.3;
uniform float ground_grime_height = 0.45;

varying float world_y;

void vertex() {
	world_y = (MODEL_MATRIX * vec4(VERTEX, 1.0)).y;
}

void fragment() {
	vec3 col = COLOR.rgb * COLOR.rgb;
	float packed = floor(COLOR.a * 255.0 + 0.5);
	float pc = mod(packed, 16.0) / 15.0;
	float metal = floor(packed / 16.0) / 15.0;
	float ground = 1.0 - smoothstep(0.0, ground_grime_height, world_y);
	col = mix(col, grime_color, ground_grime * ground);
	// Flat shading from the faces themselves: the merged meshes carry no normals (clustered
	// vertices are shared by faces turned every way), and Factorio's buildings are boxy.
	vec3 n = normalize(cross(dFdx(VERTEX), dFdy(VERTEX)));
	NORMAL = dot(n, VERTEX) > 0.0 ? -n : n;
	float up = clamp((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).y, 0.0, 1.0);
	ALBEDO = col * mix(1.0, mix(part_light.x, part_light.y, up), pc);
	ROUGHNESS = mix(0.65, 0.85, pc);
	METALLIC = metal;
	SPECULAR = mix(0.5, 0.2, pc);
}
