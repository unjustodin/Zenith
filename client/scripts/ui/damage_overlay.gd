extends ColorRect
## Factorio's damage feedback over the whole screen: when the character loses health or shield
## the screen's edges flash red and fade, and while its health is low the screen stays tinted red,
## pulsing slowly, stronger the closer it is to dying. hud.gd feeds it from `me`.

## Below this share of health the screen turns red.
const LOW_HEALTH := 0.3
const FLASH_SECONDS := 0.45

const SHADER := """
shader_type canvas_item;
uniform float flash = 0.0;
uniform float low = 0.0;
void fragment() {
	vec2 p = (UV - 0.5) * 2.0;
	float edge = smoothstep(0.35, 1.25, length(p));
	float a = flash * edge * 0.75 + low * (0.10 + 0.45 * edge);
	COLOR = vec4(0.75, 0.02, 0.0, clamp(a, 0.0, 0.85));
}
"""

## 0..1: the flash now, and how low the health is (0 fine, 1 nearly dead).
var flash := 0.0
var low := 0.0

var _hp := -1
var _shield := -1
var _time := 0.0
var _material := ShaderMaterial.new()


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var shader := Shader.new()
	shader.code = SHADER
	_material.shader = shader
	material = _material
	color = Color.WHITE
	visible = false


## From `me`: health and its maximum. Losing some flashes; a respawn (full again) starts over.
func set_health(hp: int, max_hp: int) -> void:
	if _hp >= 0 and hp < _hp:
		hit()
	_hp = hp
	var f := clampf(float(hp) / maxi(1, max_hp), 0.0, 1.0)
	low = clampf((LOW_HEALTH - f) / LOW_HEALTH, 0.0, 1.0) if hp > 0 else 0.0
	_update()


func set_shield(shield: int, max_shield: int) -> void:
	if max_shield <= 0:
		_shield = -1
		return
	if _shield >= 0 and shield < _shield:
		hit()
	_shield = shield


func hit() -> void:
	flash = 1.0
	_update()


## The character died or the game ended: nothing to show until the next `me`.
func reset() -> void:
	_hp = -1
	_shield = -1
	flash = 0.0
	low = 0.0
	_update()


func _process(delta: float) -> void:
	_time += delta
	if flash > 0.0:
		flash = maxf(0.0, flash - delta / FLASH_SECONDS)
	_update()


func _update() -> void:
	var pulse := 0.8 + 0.2 * sin(_time * 4.0)
	_material.set_shader_parameter("flash", flash)
	_material.set_shader_parameter("low", low * pulse)
	visible = flash > 0.0 or low > 0.0
