// An item icon cut out at alpha 0.5, sampled no smaller than its 8-pixel copy. Smaller copies
// average an icon into its see-through corners, and a thin one sank under the cut-off: far from the
// camera iron and copper plates (0.40 solid) vanished from belts while circuits (0.63) stayed.
vec4 icon_texel(sampler2D tex, vec2 uv) {
	float max_lod = max(0.0, log2(float(textureSize(tex, 0).x) / 8.0));
	return textureLod(tex, uv, min(textureQueryLod(tex, uv).x, max_lod));
}
