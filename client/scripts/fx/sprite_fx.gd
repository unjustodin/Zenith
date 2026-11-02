extends Node3D
## Pooled sprite-sheet cards for effects: one MultiMesh per sheet, rewritten each frame from a
## flat buffer, so hundreds of puffs cost a few draw calls. The sheets are Factorio's own
## (smoke, explosions, muzzle flash, sparks, scorch marks), read from the player's install;
## without one each sheet is a soft procedural blob.

const SoundBank := preload("res://scripts/fx/sound_bank.gd")
const MIX_SHADER := preload("res://shaders/fx_sprite.gdshader")
const ADD_SHADER := preload("res://shaders/fx_sprite_add.gdshader")

## name: [file under data/base/graphics/entity, frame width, height, frames, additive, cyclic,
## card capacity, flat on the ground, fade-in and fade-out (fractions of the card's life)].
## Frame sizes and counts are as in Factorio's prototypes (explosion-animations.lua, smoke.lua).
const SHEETS := {
	"smoke": ["smoke/smoke.png", 152, 120, 60, false, true, 400, false, 0.15, 0.6],
	"dust": ["smoke-fast/smoke-fast.png", 50, 50, 16, false, false, 160, false, 0.0, 0.5],
	"explosion": ["medium-explosion/medium-explosion-1.png", 124, 224, 30, false, false, 24, false, 0.0, 0.15],
	"small-explosion": ["small-explosion/small-explosion-1.png", 88, 178, 24, false, false, 32, false, 0.0, 0.15],
	"hit": ["explosion/explosion-1.png", 48, 42, 17, true, false, 48, false, 0.0, 0.2],
	"muzzle": ["explosion-gunshot/explosion-gunshot.png", 34, 38, 2, true, false, 16, false, 0.0, 0.3],
	"sparks": ["sparks/sparks-01.png", 39, 34, 19, true, false, 64, false, 0.0, 0.2],
	"scorch": ["scorchmark/small-scorchmark.png", 256, 182, 4, false, false, 240, true, 0.02, 0.25],
	# Turrets and vehicle guns (turrets.gd): a bullet's hit, the artillery's muzzle flash, the
	# flamethrower's stream particles and the fire at its nozzle.
	"bullet-hit": ["explosion-hit/explosion-hit.png", 34, 38, 13, false, false, 96, false, 0.0, 0.2],
	"artillery-flash": ["artillery-cannon-muzzle-flash/muzzle-flash.png", 276, 382, 21, false, false, 8, false, 0.0, 0.2],
	"flame-stream": ["flamethrower-fire-stream/flamethrower-explosion.png", 124, 108, 36, false, false, 400, false, 0.05, 0.25],
	"flame-muzzle": ["flamethrower-turret/flamethrower-turret-muzzle-fire.png", 16, 30, 32, true, true, 24, false, 0.0, 0.3],
}


class Card:
	var pos := Vector3.ZERO
	var vel := Vector3.ZERO
	var age := 0.0
	var life := 1.0
	var size0 := 1.0
	var size1 := 1.0
	var spin := 0.0
	var spin_rate := 0.0
	var color := Color.WHITE
	var frame := 0.0  # first frame; cyclic sheets play on from it at `fps`
	var fps := 15.0
	var rise := 0.0  # upward acceleration (smoke) or gravity when negative
	var drag := 0.0
	var angle := 0.0  # on the ground (decals)


class Pool:
	var mmi := MultiMeshInstance3D.new()
	var mm := MultiMesh.new()
	var material := ShaderMaterial.new()
	var cards: Array = []
	var frames := 1
	var aspect := 1.0
	var cyclic := false
	var additive := false
	var flat := false
	var capacity := 64
	var fade_in := 0.0
	var fade_out := 0.3
	var glow := false  # draws itself lit: not dimmed at night (Factorio's draw_as_glow)
	var buffer := PackedFloat32Array()


var _pools := {}  # name -> Pool
## 0 by day, 1 at night: smoke dims with the light, flashes don't.
var night := 0.0


func _ready() -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	for name in SHEETS:
		var spec: Array = SHEETS[name]
		var pool := Pool.new()
		pool.additive = spec[4]
		pool.cyclic = spec[5]
		pool.capacity = spec[6]
		pool.flat = spec[7]
		pool.fade_in = spec[8]
		pool.fade_out = spec[9]
		pool.aspect = float(spec[2]) / float(spec[1])
		var grid := Vector2.ONE
		var texture := _load_sheet(spec[0])
		if texture != null:
			pool.frames = int(spec[3])
			grid = Vector2(floorf(texture.get_width() / float(spec[1])), ceilf(texture.get_height() / float(spec[2])))
		else:
			texture = _blob(name)
			pool.aspect = 1.0
		pool.material.shader = ADD_SHADER if pool.additive else MIX_SHADER
		pool.material.set_shader_parameter("atlas", texture)
		pool.material.set_shader_parameter("grid", grid)
		pool.material.set_shader_parameter("billboard", not pool.flat)
		# Decals draw before the smoke and flashes above them.
		pool.material.render_priority = -1 if pool.flat else (1 if pool.additive else 0)
		pool.mm.transform_format = MultiMesh.TRANSFORM_3D
		pool.mm.use_colors = true
		pool.mm.use_custom_data = true
		pool.mm.mesh = quad
		pool.mm.instance_count = pool.capacity
		pool.mm.visible_instance_count = 0
		pool.mmi.multimesh = pool.mm
		pool.mmi.material_override = pool.material
		pool.mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		pool.mmi.name = name
		pool.buffer.resize(pool.capacity * 20)
		add_child(pool.mmi)
		_pools[name] = pool


## A new card on sheet `sheet` at `pos` (its centre), `width` tiles wide (the sheet's frame
## shape sets its height). Returns it to tweak, or null for an unknown sheet. When the pool is
## full the oldest card makes way.
func emit(sheet: String, pos: Vector3, width: float, life: float, color := Color.WHITE) -> Card:
	var pool: Pool = _pools.get(sheet)
	if pool == null:
		return null
	var c := Card.new()
	c.pos = pos
	c.size0 = width
	c.size1 = width
	c.life = maxf(life, 0.01)
	c.color = color
	if pool.cyclic:
		c.frame = randi() % pool.frames
	if pool.cards.size() >= pool.capacity:
		pool.cards.pop_front()
	pool.cards.append(c)
	return c


## A pool for a sheet made at runtime (weapon_fx.gd cuts Factorio's explosion, projectile and
## fire animations into atlases): `grid` frames across and down, `aspect` a frame's height over
## its width. Does nothing if the name is taken.
func add_pool(sheet: String, texture: Texture2D, grid: Vector2, frames: int, aspect: float, additive: bool,
		cyclic: bool, flat: bool, capacity: int, glow := false, fade_in := 0.0, fade_out := 0.15) -> void:
	if _pools.has(sheet):
		return
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	var pool := Pool.new()
	pool.additive = additive
	pool.cyclic = cyclic
	pool.flat = flat
	pool.glow = glow
	pool.capacity = capacity
	pool.fade_in = fade_in
	pool.fade_out = fade_out
	pool.aspect = aspect
	pool.frames = maxi(frames, 1)
	pool.material.shader = ADD_SHADER if additive else MIX_SHADER
	pool.material.set_shader_parameter("atlas", texture)
	pool.material.set_shader_parameter("grid", grid)
	pool.material.set_shader_parameter("billboard", not flat)
	pool.material.render_priority = -1 if flat else (1 if additive else 0)
	pool.mm.transform_format = MultiMesh.TRANSFORM_3D
	pool.mm.use_colors = true
	pool.mm.use_custom_data = true
	pool.mm.mesh = quad
	pool.mm.instance_count = capacity
	pool.mm.visible_instance_count = 0
	pool.mmi.multimesh = pool.mm
	pool.mmi.material_override = pool.material
	pool.mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pool.mmi.name = sheet.validate_node_name()
	pool.buffer.resize(capacity * 20)
	add_child(pool.mmi)
	_pools[sheet] = pool


func has_pool(sheet: String) -> bool:
	return _pools.has(sheet)


## Takes a card out at once (a projectile that hit, a fire that went out).
func kill(card: Card) -> void:
	card.age = card.life


func frame_count(sheet: String) -> int:
	var pool: Pool = _pools.get(sheet)
	return pool.frames if pool != null else 1


func count() -> int:
	var n := 0
	for pool: Pool in _pools.values():
		n += pool.cards.size()
	return n


func clear() -> void:
	for pool: Pool in _pools.values():
		pool.cards.clear()
		pool.mm.visible_instance_count = 0


## The last frame's _process time, microseconds (--stutter-probe).
var process_usec := 0


func _process(delta: float) -> void:
	var t0 := Time.get_ticks_usec()
	var brightness := lerpf(1.0, 0.3, night)
	for pool: Pool in _pools.values():
		if not pool.additive and not pool.glow:
			pool.material.set_shader_parameter("brightness", brightness)
		_step(pool, delta)
	process_usec = Time.get_ticks_usec() - t0


func _step(pool: Pool, delta: float) -> void:
	var cards := pool.cards
	var i := 0
	while i < cards.size():
		var c: Card = cards[i]
		c.age += delta
		if c.age >= c.life:
			cards.remove_at(i)
			continue
		c.vel.y += c.rise * delta
		if c.drag > 0.0:
			c.vel *= maxf(0.0, 1.0 - c.drag * delta)
		c.pos += c.vel * delta
		c.spin += c.spin_rate * delta
		i += 1
	var buf := pool.buffer
	var n := cards.size()
	for k in n:
		var c: Card = cards[k]
		var t := c.age / c.life
		var w := lerpf(c.size0, c.size1, t)
		var h := w * pool.aspect
		var a := c.color.a
		if pool.fade_in > 0.0 and t < pool.fade_in:
			a *= t / pool.fade_in
		if t > 1.0 - pool.fade_out:
			a *= (1.0 - t) / pool.fade_out
		var frame: float
		if pool.cyclic:
			frame = fmod(c.frame + c.age * c.fps, pool.frames)
		elif pool.flat:
			frame = c.frame
		else:
			frame = minf(pool.frames - 1, t * pool.frames)
		var o := k * 20
		if pool.flat:
			var cs := cos(c.angle)
			var sn := sin(c.angle)
			buf[o] = cs * w; buf[o + 1] = -sn * h; buf[o + 2] = 0.0; buf[o + 3] = c.pos.x
			buf[o + 4] = 0.0; buf[o + 5] = 0.0; buf[o + 6] = 1.0; buf[o + 7] = c.pos.y
			buf[o + 8] = -sn * w; buf[o + 9] = -cs * h; buf[o + 10] = 0.0; buf[o + 11] = c.pos.z
		else:
			buf[o] = w; buf[o + 1] = 0.0; buf[o + 2] = 0.0; buf[o + 3] = c.pos.x
			buf[o + 4] = 0.0; buf[o + 5] = h; buf[o + 6] = 0.0; buf[o + 7] = c.pos.y
			buf[o + 8] = 0.0; buf[o + 9] = 0.0; buf[o + 10] = 1.0; buf[o + 11] = c.pos.z
		buf[o + 12] = c.color.r; buf[o + 13] = c.color.g; buf[o + 14] = c.color.b; buf[o + 15] = a
		buf[o + 16] = frame; buf[o + 17] = 0.0; buf[o + 18] = c.spin; buf[o + 19] = 0.0
	if n > 0:
		pool.mm.buffer = buf
	pool.mm.visible_instance_count = n


static func _load_sheet(file: String) -> Texture2D:
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


## A soft round blob in place of a missing sheet: white (tinted per card) for smoke and dust, a
## hot core for flashes, dark for scorch marks.
static func _blob(name: String) -> Texture2D:
	var size := 64
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var hot := name in ["hit", "muzzle", "sparks", "explosion", "small-explosion"]
	for y in size:
		for x in size:
			var d := Vector2(x + 0.5 - size * 0.5, y + 0.5 - size * 0.5).length() / (size * 0.5)
			var a := clampf(1.0 - d, 0.0, 1.0)
			a = a * a * (3.0 - 2.0 * a)
			var c := Color(1, 1, 1, a)
			if hot:
				c = Color(1.0, lerpf(0.95, 0.45, d), lerpf(0.7, 0.1, d), a)
			elif name == "scorch":
				c = Color(0.08, 0.07, 0.06, a * 0.8)
			image.set_pixel(x, y, c)
	image.generate_mipmaps()
	return ImageTexture.create_from_image(image)
