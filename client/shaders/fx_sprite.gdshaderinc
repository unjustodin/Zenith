// Sprite-sheet cards for effects (smoke, steam, flashes, explosions, scorch marks), drawn from
// one MultiMesh per sheet. Per instance: COLOR is the tint and opacity; INSTANCE_CUSTOM.x the
// frame in the sheet, .z the card's spin. The instance basis carries the card's size.

uniform sampler2D atlas : source_color, filter_linear_mipmap, repeat_disable;
uniform vec2 grid = vec2(1.0, 1.0);  // frames across and down
uniform bool billboard = true;  // false: lies as the instance transform says (decals)
uniform float brightness = 1.0;  // dims smoke at night; flashes keep 1

varying vec2 frame_uv;

void vertex() {
	float frame = floor(INSTANCE_CUSTOM.x + 0.001);
	vec2 cell = vec2(mod(frame, grid.x), floor(frame / grid.x));
	frame_uv = (cell + UV) / grid;
	if (billboard) {
		vec2 size = vec2(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz));
		float c = cos(INSTANCE_CUSTOM.z);
		float s = sin(INSTANCE_CUSTOM.z);
		vec2 v = VERTEX.xy * size;
		VERTEX = vec3(v.x * c - v.y * s, v.x * s + v.y * c, 0.0);
		MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	}
}

void fragment() {
	vec4 t = texture(atlas, frame_uv) * COLOR;
	ALBEDO = t.rgb * brightness;
	ALPHA = t.a;
}
