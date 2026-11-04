// Loose items (item_cards.gd): 3D item models, whose colours are in the vertices (linear, from
// glTF), and plain coloured blocks (no vertex colours: COLOR is white). Items on belts glide on
// the GPU along their lanes (belt_path.gdshaderinc), so a frame doesn't touch their transforms.
shader_type spatial;
render_mode world_vertex_coords;

#include "res://shaders/belt_path.gdshaderinc"
#include "res://shaders/ground_height.gdshaderinc"

uniform vec4 color : source_color = vec4(1.0);
uniform float roughness = 0.8;
// The colours were picked from icons drawn already lit; this keeps the sun from lighting them twice.
uniform float exposure = 1.0;

void vertex() {
	VERTEX = belt_vertex(VERTEX, INSTANCE_CUSTOM);
	VERTEX.y += ground_h(VERTEX.xz);  // world coordinates here
}

void fragment() {
	ALBEDO = color.rgb * COLOR.rgb * exposure;
	ROUGHNESS = roughness;
}
