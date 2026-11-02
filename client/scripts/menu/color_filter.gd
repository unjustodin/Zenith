extends CanvasLayer
## Factorio's colour filter (Settings → Graphics → Accessibility): the whole window, game and
## windows, seen as with protanopia, deuteranopia or tritanopia, or corrected for them. A layer
## over everything that reads the screen; hidden (and free) when the filter is "none".
##
## Simulation matrices: Machado, Oliveira and Fernandes (2009), full severity. Correction moves
## the colour difference a viewer can't see into channels they can (daltonisation).

const Settings := preload("res://scripts/menu/settings.gd")

## Setting value -> name shown in Settings (Factorio's [gui-graphics-settings] color-filter-*).
const FILTERS := [
	["none", "None"], ["protanopia", "Protanopia"], ["deuteranopia", "Deuteranopia"],
	["tritanopia", "Tritanopia"], ["protanopia-correction", "Protanopia correction"],
	["deuteranopia-correction", "Deuteranopia correction"], ["tritanopia-correction", "Tritanopia correction"],
]
const MATRICES := {
	"protanopia": [Vector3(0.152286, 1.052583, -0.204868), Vector3(0.114503, 0.786281, 0.099216), Vector3(-0.003882, -0.048116, 1.051998)],
	"deuteranopia": [Vector3(0.367322, 0.860646, -0.227968), Vector3(0.280085, 0.672501, 0.047413), Vector3(-0.011820, 0.042940, 0.968881)],
	"tritanopia": [Vector3(1.255528, -0.076749, -0.178779), Vector3(-0.078411, 0.930809, 0.147602), Vector3(0.004733, 0.691367, 0.303900)],
}
const SHADER := """
shader_type canvas_item;
uniform sampler2D screen : hint_screen_texture, filter_nearest;
uniform vec3 r0 = vec3(1.0, 0.0, 0.0);
uniform vec3 r1 = vec3(0.0, 1.0, 0.0);
uniform vec3 r2 = vec3(0.0, 0.0, 1.0);
uniform bool correct = false;
void fragment() {
	vec3 c = texture(screen, SCREEN_UV).rgb;
	vec3 sim = vec3(dot(r0, c), dot(r1, c), dot(r2, c));
	if (correct) {
		vec3 err = c - sim;
		c = clamp(c + vec3(0.0, 0.7 * err.r + err.g, 0.7 * err.r + err.b), 0.0, 1.0);
	} else {
		c = clamp(sim, 0.0, 1.0);
	}
	COLOR = vec4(c, 1.0);
}
"""

var _rect := ColorRect.new()
var _material := ShaderMaterial.new()


func _ready() -> void:
	layer = 128
	name = "ColorFilter"
	var shader := Shader.new()
	shader.code = SHADER
	_material.shader = shader
	_rect.material = _material
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_rect)
	Settings.listen(_on_setting)
	apply()


func _exit_tree() -> void:
	Settings.unlisten(_on_setting)


func _on_setting(section: String, key: String) -> void:
	if section == "graphics" and key == "color_filter":
		apply()


func apply() -> void:
	var filter := str(Settings.get_value("graphics", "color_filter"))
	var base := filter.trim_suffix("-correction")
	visible = MATRICES.has(base)
	if not visible:
		return
	var m: Array = MATRICES[base]
	_material.set_shader_parameter("r0", m[0])
	_material.set_shader_parameter("r1", m[1])
	_material.set_shader_parameter("r2", m[2])
	_material.set_shader_parameter("correct", filter.ends_with("-correction"))
