extends Node3D
## Fire and glow on working machines near the camera, as Factorio's working_visualisations:
## the furnaces' and boilers' fire animations (their own sprite sheets from the player's install,
## played at the prototype's speed) in the fire mouth, with a flickering light, and labs pulsing
## blue while they research. Shown while the mod reports the machine working (`st`, world.working),
## fading in and out.
##
## The cards are additive and face the camera (fx_sprite_add); the model in front hides them
## where it should, so a fire shows through the mouth's opening only. One MultiMesh per sheet.

const ProtoDB := preload("res://scripts/world/protos.gd")
const SoundBank := preload("res://scripts/fx/sound_bank.gd")
const ADD_SHADER := preload("res://shaders/fx_sprite_add.gdshader")

const RADIUS := 40.0
const REFRESH := 0.25
const MAX_LIGHTS := 16
const FADE_IN := 0.4
const FADE_OUT := 1.2

## Prototype -> [sheet, where in the model (north-facing, tiles), card width, light colour,
## light energy, flicker]. Directional ones (boilers) turn with the entity.
const MACHINES := {
	"stone-furnace": ["stone-fire", Vector3(0.0, 0.3, 0.74), 0.36, Color(1.0, 0.55, 0.2), 1.2, 0.35],
	"steel-furnace": ["steel-fire", Vector3(0.0, 0.42, 0.72), 0.5, Color(1.0, 0.55, 0.2), 1.3, 0.35],
	"boiler": ["boiler-fire", Vector3(0.12, 0.3, 1.0), 0.3, Color(1.0, 0.5, 0.18), 1.0, 0.35],
	"lab": ["", Vector3(0.0, 1.6, 0.0), 0.0, Color(0.35, 0.65, 1.0), 2.5, 0.0],
	"biolab": ["", Vector3(0.0, 1.8, 0.0), 0.0, Color(0.7, 0.4, 1.0), 2.5, 0.0],
}
## Where the fire sits in models drawn one per direction (model_library.gd FACING_MODELS), by
## direction (north, east, south, west), each in its own model's frame: the boiler's grate, as
## tools/models/power.py BOILER_FITS places it in each direction's model.
const FACING_SPOTS := {"boiler": [Vector3(-0.13, 1.11, 0.62), Vector3(-0.04, 1.49, 0.64),
	Vector3(0.23, 0.98, 0.5), Vector3(0.25, 1.4, 0.66)]}
## Sheet -> [file under base/graphics/entity, frame width, height, frames, line length, frames
## a second] (entities.lua: stone and steel furnace fire 48 frames at 1 a tick, the boiler's 64
## at 0.5).
const SHEETS := {
	"stone-fire": ["stone-furnace/stone-furnace-fire.png", 41, 100, 48, 8, 60.0],
	"steel-fire": ["steel-furnace/steel-furnace-fire.png", 57, 81, 48, 8, 60.0],
	"boiler-fire": ["boiler/boiler-N-fire.png", 26, 26, 64, 8, 30.0],
}
## Labs: Factorio's lab animation loops 33 frames at 1/3 a tick (1.65 s); the light pulses with it.
const LAB_LOOP := 33.0 / 20.0

## The world mirror: entities, working states and the focus.
var world: Node3D
var protos: ProtoDB

var _sheets := {}  # sheet -> [MultiMeshInstance3D, aspect, frames, fps]
var _lights: Array[OmniLight3D] = []
var _shown := {}  # entity key -> [rec, MACHINES entry, level 0-1, seed, prototype name]
var _timer := 0.0
var _clock := 0.0


func _ready() -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	for name in SHEETS:
		var spec: Array = SHEETS[name]
		var texture := _load(str(spec[0]))
		if texture == null:
			continue
		var material := ShaderMaterial.new()
		material.shader = ADD_SHADER
		material.set_shader_parameter("atlas", texture)
		material.set_shader_parameter("grid", Vector2(float(spec[4]), ceilf(float(spec[3]) / float(spec[4]))))
		material.set_shader_parameter("billboard", true)
		material.render_priority = 1
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.use_custom_data = true
		mm.mesh = quad
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = material
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mmi.custom_aabb = AABB(Vector3(-1e5, -10, -1e5), Vector3(2e5, 20, 2e5))
		add_child(mmi)
		_sheets[name] = [mmi, float(spec[2]) / float(spec[1]), int(spec[3]), float(spec[5])]
	for i in MAX_LIGHTS:
		var light := OmniLight3D.new()
		light.omni_range = 4.0
		light.visible = false
		light.shadow_enabled = false
		add_child(light)
		_lights.append(light)


func reset() -> void:
	_shown.clear()


func count() -> int:
	return _shown.size()


func _process(delta: float) -> void:
	if world == null:
		return
	if protos == null:
		protos = world.protos
	_clock += delta
	_timer += delta
	if _timer >= REFRESH:
		_timer = 0.0
		_refresh()
	var focus: Vector2 = world.focus()
	var buffers := {}
	var lit: Array = []
	for key in _shown.keys():
		var s: Array = _shown[key]
		var on: bool = int(world.working.get(s[0].unit, 0)) == 1 and world.entities.has(key)
		var level: float = move_toward(float(s[2]), 1.0 if on else 0.0, delta / (FADE_IN if on else FADE_OUT))
		s[2] = level
		if level <= 0.0 and not on:
			_shown.erase(key)
			continue
		var entry: Array = s[1]
		var rec = s[0]
		var turn := Basis(Vector3.UP, -float(rec.dir) / 16.0 * TAU)
		var offset: Vector3 = entry[1]
		if FACING_SPOTS.has(s[4]):
			offset = FACING_SPOTS[s[4]][(int(rec.dir) >> 2) % 4]
		var at := Vector3(rec.pos.x, 0.0, rec.pos.y) + turn * offset
		var seed: float = s[3]
		var flicker := 1.0 - float(entry[5]) * (0.5 + 0.5 * sin(_clock * 13.0 + seed * 40.0) * sin(_clock * 7.3 + seed * 17.0))
		var sheet := str(entry[0])
		if sheet != "" and _sheets.has(sheet):
			var info: Array = _sheets[sheet]
			if not buffers.has(sheet):
				buffers[sheet] = PackedFloat32Array()
			var w: float = entry[2]
			var h: float = w * float(info[1])
			var frame := fmod(_clock * float(info[3]) + seed * 97.0, float(info[2]))
			# The fire's foot sits in the mouth: the card's centre half its height up.
			var c := at + Vector3(0.0, h * 0.3, 0.0)
			var a := level * flicker
			# Packed arrays are values: append to it, then put it back.
			var buf: PackedFloat32Array = buffers[sheet]
			buf.append_array([w, 0.0, 0.0, c.x, 0.0, h, 0.0, c.y, 0.0, 0.0, 1.0, c.z,
				1.0, 1.0, 1.0, a, frame, 0.0, 0.0, 0.0])
			buffers[sheet] = buf
		var energy: float = float(entry[4]) * level
		if sheet == "":
			energy *= 0.6 + 0.4 * sin((_clock / LAB_LOOP + seed) * TAU)
		else:
			energy *= flicker
		lit.append([Vector2(at.x, at.z).distance_squared_to(focus), at, entry[3], energy])
	for sheet in _sheets:
		var mm: MultiMesh = (_sheets[sheet][0] as MultiMeshInstance3D).multimesh
		var buf: PackedFloat32Array = buffers.get(sheet, PackedFloat32Array())
		var n := buf.size() / 20
		if mm.instance_count < n:
			mm.instance_count = maxi(n * 2, 16)
		if n > 0:
			buf.resize(mm.instance_count * 20)
			mm.buffer = buf
		mm.visible_instance_count = n
	lit.sort_custom(func(x: Array, y: Array) -> bool: return float(x[0]) < float(y[0]))
	for i in _lights.size():
		var light := _lights[i]
		light.visible = i < lit.size()
		if light.visible:
			light.position = (lit[i][1] as Vector3) + Vector3(0.0, 0.3, 0.25)
			light.light_color = lit[i][2]
			light.light_energy = lit[i][3]


## Which working machines of these kinds are near the focus.
func _refresh() -> void:
	var focus: Vector2 = world.focus()
	for unit in world.working:
		if int(world.working[unit]) != 1 or _shown.has(unit):
			continue
		var rec = world.entities.get(unit)
		if rec == null or rec.pos.distance_to(focus) > RADIUS:
			continue
		var proto: ProtoDB.EntityProto = protos.entity(rec.proto_id)
		if proto == null or not MACHINES.has(proto.name):
			continue
		_shown[unit] = [rec, MACHINES[proto.name], 0.0, fposmod(rec.pos.x * 0.37 + rec.pos.y * 0.71, 1.0), proto.name]
	for key in _shown.keys():
		if (_shown[key][0].pos as Vector2).distance_to(focus) > RADIUS + 8.0:
			_shown.erase(key)


static func _load(file: String) -> Texture2D:
	var dir := SoundBank.data_dir()
	if dir == "":
		return null
	var path := dir.path_join("base/graphics/entity").path_join(file)
	if not FileAccess.file_exists(path):
		return null
	var image := Image.load_from_file(path)
	if image == null:
		return null
	image.generate_mipmaps()
	return ImageTexture.create_from_image(image)
