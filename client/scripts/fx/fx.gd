extends Node3D
## Sound and effects for what the bridge reports: working machines (loops, chimney smoke,
## steam), the character (footsteps by ground, dust, mining hits and sparks, gunshots and
## muzzle flashes), building, rotating and mining things out, deaths (explosions, scorch marks,
## corpses and remnants), biters calling, cars and trains driving. Sounds and sprite sheets are
## Factorio's own, from the player's install (sound_bank.gd, sprite_fx.gd); without one it is
## silent and the effects are plain blobs.
##
## main.gd hands every message to handle() before routing it, so a deleted entity or a dead
## mover can still be looked up here.

const WorldMirror := preload("res://scripts/world/world.gd")
const MoverLayer := preload("res://scripts/world/movers.gd")
const CombatLayer := preload("res://scripts/world/combat.gd")
const ProtoDB := preload("res://scripts/world/protos.gd")
const Visuals := preload("res://scripts/world/visuals.gd")
const ModelLibrary := preload("res://scripts/world/model_library.gd")
const Avatar := preload("res://scripts/player/avatar.gd")
const CameraRig := preload("res://scripts/player/camera_rig.gd")
const Sfx := preload("res://scripts/fx/sfx.gd")
const SpriteFx := preload("res://scripts/fx/sprite_fx.gd")
const SoundBank := preload("res://scripts/fx/sound_bank.gd")
const FxSettings := preload("res://scripts/fx/fx_settings.gd")
const FxDemo := preload("res://scripts/fx/fx_demo.gd")
const WeaponFx := preload("res://scripts/fx/weapon_fx.gd")
const WeaponsDemo := preload("res://scripts/fx/weapons_demo.gd")

const SCAN_INTERVAL := 0.25
## Machines and vehicles further than this from the listener (tiles) are not considered.
const HEARING := 40.0
const SMOKE_RANGE := 45.0
const MAX_EMITTERS := 24
## Seconds between footsteps (Factorio's running animation takes two steps in about 0.6 s).
const STEP_INTERVAL := 0.3
const MINE_INTERVAL := 0.5
const BUILD_RANGE := 16.0
const CORPSE_LIMIT := 40
const CORPSE_SECONDS := 30.0
const REMNANT_SECONDS := 60.0
const SINK_SECONDS := 4.0
const WIND := Vector3(0.35, 0.0, 0.12)  # tiles per second; Factorio's smoke drifts too
const ENEMY_TYPES := ["unit", "spider-unit", "segmented-unit"]

## Smoke from working burner machines: sheet kind, chimney offset (tiles, north-facing, x east,
## y south), puffs per second, height as a fraction of the model's top, spread along y.
const EMITTERS := {
	"stone-furnace": ["smoke", Vector2(0.0, -0.25), 2.5, 0.95, 0.0],
	"steel-furnace": ["smoke", Vector2(0.4, -0.6), 2.0, 0.95, 0.0],
	"boiler": ["smoke", Vector2(-1.0, 0.25), 4.0, 1.0, 0.0],
	"burner-mining-drill": ["smoke", Vector2(0.35, -0.35), 2.0, 0.95, 0.0],
	"steam-engine": ["steam", Vector2(0.0, 0.0), 3.0, 0.9, 1.6],
	"steam-turbine": ["steam", Vector2(0.0, -1.6), 4.5, 0.95, 0.0],
	"thruster": ["thrust", Vector2(0.0, 1.1), 5.0, 0.15, 0.0],
}

const GUN_SOUNDS := {
	"pistol": "base/sound/fight/light-gunshot",
	"submachine-gun": "base/sound/fight/submachine-gunshot",
	"shotgun": "base/sound/fight/pump-shotgun",
	"combat-shotgun": "base/sound/fight/pump-shotgun",
	"rocket-launcher": "base/sound/fight/rocket-launcher",
	"flamethrower": "base/sound/fight/flamethrower-mid",
	"railgun": "space-age/sound/entity/railgun/railgun-gunshot",
}

## Loops for moving vehicles: [driving, idle with the character inside, volume].
const VEHICLE_SOUNDS := {
	"car": ["base/sound/car-engine-driving.ogg", "base/sound/car-engine.ogg", 0.6],
	"tank": ["base/sound/fight/tank-engine-driving.ogg", "base/sound/fight/tank-engine.ogg", 0.6],
	"locomotive": ["base/sound/train-engine-driving.ogg", "base/sound/train-engine.ogg", 0.6],
	"cargo-wagon": ["base/sound/train-wagon-wheels.ogg", "", 0.5],
	"fluid-wagon": ["base/sound/train-wagon-wheels.ogg", "", 0.5],
	"artillery-wagon": ["base/sound/train-wagon-wheels.ogg", "", 0.5],
}


class Tracked:
	var proto_id := 0
	var pos := Vector2.ZERO
	var scan_pos := Vector2.ZERO
	var speed := 0.0  # tiles per second
	var seen := 0


class Emitter:
	var pos := Vector3.ZERO
	var kind := "smoke"
	var rate := 1.0
	var spread := Vector3.ZERO  # puffs come from anywhere along this, both ways
	var due := 0.0


var world: WorldMirror
var movers: MoverLayer
var combat: CombatLayer
var avatar: Avatar
var rig: CameraRig

var sfx := Sfx.new()
var sprites := SpriteFx.new()
## What weapons fire: shots, projectiles, beams, explosions, fires and clouds (weapon_fx.gd).
var weapons := WeaponFx.new()

var _tracked := {}  # unit -> Tracked, from mv
var _gun := "pistol"
var _night := 0.0
var _scan_timer := 0.0
var _emitters := {}  # unit -> Emitter
var _step_timer := 0.0
var _mine_timer := 0.0
var _mine_kind := ""
var _mine_target := Vector2(INF, INF)
var _last_mining_msec := -100000
var _last_mining_at := Vector2.ZERO
var _last_mining_progress := -1
var _shot_clock := 0.0
var _biter_wait := 0.0
var _corpses: Array = []  # [MeshInstance3D, age, life, start y]
var _burning := {}  # unit -> [remaining seconds, last position]
var _corpse_material: StandardMaterial3D
var _tops := {}  # proto name -> height of the model's top
var _states := {}  # unit -> working state last scan, for activate/deactivate sounds


func _ready() -> void:
	FxSettings.load_settings()
	sfx.name = "Sfx"
	add_child(sfx)
	sprites.name = "Sprites"
	sprites.visible = FxSettings.effects_enabled
	add_child(sprites)
	weapons.name = "Weapons"
	weapons.sprites = sprites
	weapons.sfx = sfx
	add_child(weapons)
	_corpse_material = Visuals.solid_material(Color(0.2, 0.14, 0.1))
	# After the player's input (which sets combat's aim each frame) and fx_demo.gd.
	process_priority = 2
	for arg in OS.get_cmdline_user_args():
		if arg == "--weapons-demo":
			var weapons_demo := WeaponsDemo.new()
			weapons_demo.fx = self
			add_child(weapons_demo)
		if arg.begins_with("--fx-demo"):
			var demo := FxDemo.new()
			demo.fx = self
			demo.space = arg == "--fx-demo=space"
			demo.stress = arg == "--fx-demo=stress"
			add_child(demo)


func _exit_tree() -> void:
	SoundBank.clear_cache()


## The planet the character is on, for its ambience and music; `space` on a platform.
func set_planet(planet: String, space: bool) -> void:
	sfx.ambience.set_planet(planet, space)
	weapons.in_space = space


func reset() -> void:
	_tracked.clear()
	_states.clear()
	_emitters.clear()
	sprites.clear()
	sfx.stop_all()
	for c in _corpses:
		(c[0] as Node3D).queue_free()
	_corpses.clear()
	weapons.reset()
	_burning.clear()
	_tops.clear()


## Every message from the bridge, before main.gd routes it.
func handle(msg: Dictionary) -> void:
	match str(msg.get("t", "")):
		"mv":
			_track(msg)
		"add":
			if Bridge.world_ready:
				_on_add(msg.get("e"))
		"upd":
			if Bridge.world_ready:
				_on_upd(msg.get("e"))
		"del":
			_on_del(msg)
		"died":
			_on_died(msg)
		"afx":
			_on_combat_fx(msg)
		"shot":
			_on_shot(msg)
			weapons.handle(msg)
		"pj", "gf":
			weapons.handle(msg)
		"guns":
			var list = msg.get("l")
			var sel := int(msg.get("sel", 1)) - 1
			if list is Array and sel >= 0 and sel < list.size() and list[sel] is Array and list[sel].size() > 0:
				_gun = str(list[sel][0])
		"sky":
			_night = clampf(int(msg.get("n", 0)) / 850.0, 0.0, 1.0)
			sfx.ambience.darkness = int(msg.get("n", 0)) / 1000.0


func _process(delta: float) -> void:
	if rig == null or avatar == null:
		return
	sfx.set_listener(rig.focus_point(), get_viewport().get_camera_3d(), rig.distance)
	sprites.night = _night
	weapons.avatar = avatar
	weapons.movers = movers
	weapons.world = world
	weapons.hand_stream = avatar.firing and _gun == "flamethrower"
	weapons.aim = combat.aim if combat != null and combat.aim_mode == 1 else null
	if not Bridge.world_ready:
		return
	_scan_timer += delta
	if _scan_timer >= SCAN_INTERVAL:
		_scan(_scan_timer)
		_scan_timer = 0.0
	_update_steps(delta)
	_update_mining(delta)
	_update_shots(delta)
	sprites.visible = FxSettings.effects_enabled  # the Settings window can change it in the game
	if FxSettings.effects_enabled:
		_update_emitters(delta)
	_update_corpses(delta)
	_update_combat_fx(delta)


# --- What is near: machine and vehicle loops, smoke emitters, biters ----------------------------

func _scan(elapsed: float) -> void:
	var here := sfx.listener_position()
	var focus := Vector2(here.x, here.z)
	var sources: Array = []
	var emitters := {}
	var protos := world.protos
	var states := {}
	for unit in world.working:
		var working := int(world.working[unit]) == 1
		var r: WorldMirror.Rec = world.entities.get(unit)
		if r == null:
			continue
		var off := r.pos - focus
		if absf(off.x) > SMOKE_RANGE or absf(off.y) > SMOKE_RANGE:
			continue
		var proto: ProtoDB.EntityProto = protos.entity(r.proto_id)
		if proto == null or proto.type == "lamp":
			continue
		if off.length() < HEARING:
			_machine_sound(unit, r, proto, working, sources)
			states[unit] = working
		if not working:
			continue
		if EMITTERS.has(proto.name) and emitters.size() < MAX_EMITTERS:
			var e: Emitter = _emitters.get(unit)
			if e == null:
				e = _make_emitter(r, proto)
			emitters[unit] = e
	_emitters = emitters
	_states = states
	# Vehicles, from their movement since the last scan.
	var stale := Time.get_ticks_msec() - 1000
	var biters: Array = []
	for unit in _tracked.keys():
		var t: Tracked = _tracked[unit]
		if t.seen < stale:
			_tracked.erase(unit)
			continue
		t.speed = lerpf(t.speed, t.pos.distance_to(t.scan_pos) / elapsed, 0.6)
		t.scan_pos = t.pos
		if t.pos.distance_to(focus) > HEARING:
			continue
		var proto: ProtoDB.EntityProto = protos.entity(t.proto_id)
		if proto == null:
			continue
		if VEHICLE_SOUNDS.has(proto.type):
			var spec: Array = VEHICLE_SOUNDS[proto.type]
			var inside: bool = avatar.vehicle == int(unit)
			var at := Vector3(t.pos.x, 1.0, t.pos.y)
			var rules := SoundBank.working_sound(proto.name)
			var vehicle := {"key": "v%d" % unit, "pos": at, "group": proto.type, "reach": 1.0,
				"per_group": rules.max_per_prototype if rules != null else 0,
				"fade_in": rules.fade_in if rules != null else 0.13, "fade_out": rules.fade_out if rules != null else 0.33}
			if t.speed > 0.4:
				vehicle["path"] = spec[0]
				vehicle["volume"] = float(spec[2]) * clampf(0.4 + t.speed / 12.0, 0.4, 1.0)
				sources.append(vehicle)
			elif inside and spec[1] != "":
				vehicle["path"] = spec[1]
				vehicle["volume"] = float(spec[2]) * 0.7
				sources.append(vehicle)
		elif ENEMY_TYPES.has(proto.type) and t.pos.distance_to(focus) < 24.0:
			biters.append([proto.name, t.pos])
	sfx.set_loops(sources)
	_biter_chatter(biters, elapsed)


## A machine near the listener: its working loop (or its idle sound while it isn't working), with
## its prototype's rules, and its activate/deactivate sound when it just started or stopped.
func _machine_sound(unit, r: WorldMirror.Rec, proto: ProtoDB.EntityProto, working: bool, sources: Array) -> void:
	var loop := SoundBank.working_sound(proto.name)
	if loop == null:
		return
	var at := Vector3(r.pos.x, 1.0, r.pos.y)
	if _states.has(unit) and bool(_states[unit]) != working:
		sfx.play_def(loop.activate if working else loop.deactivate, at, "Environment")
	var def: SoundBank.SoundDef = loop.sound if working else loop.idle
	if def == null or def.files.is_empty():
		return
	# Each machine keeps one variation (Factorio picks one per entity).
	var i := int(unit) % def.files.size()
	sources.append({"key": unit, "pos": at, "path": def.files[i], "volume": def.max_volumes[i], "reach": def.reach,
		"curve": def.attenuation, "group": proto.name, "per_group": loop.max_per_prototype,
		"fade_in": loop.fade_in, "fade_out": loop.fade_out})


func _make_emitter(r: WorldMirror.Rec, proto: ProtoDB.EntityProto) -> Emitter:
	var spec: Array = EMITTERS[proto.name]
	var e := Emitter.new()
	e.kind = spec[0]
	e.rate = spec[2]
	var yaw := Visuals.direction_yaw(r.dir)
	var off: Vector2 = spec[1]
	var local := Vector3(off.x, 0.0, off.y).rotated(Vector3.UP, yaw)
	e.pos = Vector3(r.pos.x, _top(proto) * float(spec[3]), r.pos.y) + local
	e.spread = Vector3(0.0, 0.0, float(spec[4])).rotated(Vector3.UP, yaw)
	e.due = randf()
	return e


## Biters call now and then, a few at a time, like a nest heard from nearby.
func _biter_chatter(biters: Array, elapsed: float) -> void:
	_biter_wait -= elapsed
	if biters.is_empty() or _biter_wait > 0.0:
		return
	if randf() > minf(0.6, biters.size() * 0.08):
		return
	_biter_wait = randf_range(0.6, 2.0)
	var b: Array = biters[randi() % biters.size()]
	var name: String = b[0]
	var path := ""
	if "spitter" in name:
		path = "base/sound/creatures/Spiters_%d_%d.ogg" % [randi_range(1, 5), randi_range(1, 2)]
	elif "behemoth" in name:
		path = SoundBank.pick("base/sound/creatures/biter-roar-behemoth")
	elif "big" in name:
		path = SoundBank.pick("base/sound/creatures/biter-roar-big")
	elif "medium" in name:
		path = SoundBank.pick("base/sound/creatures/biter-roar-mid")
	else:
		path = SoundBank.pick("base/sound/creatures/biter-roar")
	var pos: Vector2 = b[1]
	sfx.play_at(path, Vector3(pos.x, 0.5, pos.y), 0.45, 0.08, 1.0, "Enemies")


func _track(msg: Dictionary) -> void:
	var list = msg.get("l")
	if not (list is Array):
		return
	var now := Time.get_ticks_msec()
	for rec in list:
		if not (rec is Array) or rec.size() < 4:
			continue
		var unit := int(rec[0])
		var t: Tracked = _tracked.get(unit)
		var pos := Vector2(int(rec[2]), int(rec[3])) / 256.0
		if t == null:
			t = Tracked.new()
			t.scan_pos = pos
			_tracked[unit] = t
		t.proto_id = int(rec[1])
		t.pos = pos
		t.seen = now


# --- Smoke and steam ------------------------------------------------------------------------------

func _update_emitters(delta: float) -> void:
	for e: Emitter in _emitters.values():
		e.due -= delta * e.rate
		while e.due <= 0.0:
			e.due += 1.0
			_puff(e)


func _puff(e: Emitter) -> void:
	var at := e.pos + e.spread * randf_range(-1.0, 1.0)
	if e.kind == "thrust":
		var flame := sprites.emit("hit", at, randf_range(0.25, 0.45), 0.22, Color(1.0, randf_range(0.28, 0.65), 0.08, 0.85))
		if flame != null:
			flame.vel = Vector3(randf_range(-0.2, 0.2), -randf_range(0.3, 0.8), randf_range(-0.2, 0.2))
		return
	if e.kind == "steam":
		# The smoke sheet is mid-grey; tinting above white makes it steam.
		var c := sprites.emit("smoke", at, 0.8, randf_range(2.0, 3.0), Color(1.8, 1.8, 1.85, 0.6))
		if c != null:
			c.size1 = randf_range(2.0, 2.8)
			c.vel = Vector3(randf_range(-0.2, 0.2), randf_range(0.9, 1.3), randf_range(-0.2, 0.2)) + WIND
			c.drag = 0.4
			c.spin_rate = randf_range(-0.4, 0.4)
	else:
		var c := sprites.emit("smoke", at, 0.45, randf_range(3.5, 5.0), Color(0.3, 0.29, 0.28, 0.6))
		if c != null:
			c.size1 = randf_range(2.2, 3.0)
			c.vel = Vector3(randf_range(-0.1, 0.1), randf_range(0.6, 0.9), randf_range(-0.1, 0.1))
			c.rise = 0.05
			c.drag = 0.15
			c.spin_rate = randf_range(-0.3, 0.3)
			c.vel += WIND


func _top(proto: ProtoDB.EntityProto) -> float:
	if _tops.has(proto.name):
		return _tops[proto.name]
	if not ModelLibrary.ready(proto.name):
		return Visuals.height_for(proto)  # its model is being made: asked again next time
	var mesh := ModelLibrary.mesh_for(proto.name)
	var top := mesh.get_aabb().end.y if mesh != null else Visuals.height_for(proto)
	_tops[proto.name] = top
	return top


func _on_combat_fx(msg: Dictionary) -> void:
	if not FxSettings.effects_enabled:
		return
	var pos := Vector3(int(msg.get("x", 0)) / 256.0, 0.04, int(msg.get("y", 0)) / 256.0)
	var unit := int(msg.get("u", 0))
	if str(msg.get("fx", "")) == "burn":
		_burning[unit] = [2.4, pos]
		for i in 5:
			var flame := sprites.emit("hit", pos + Vector3(randf_range(-0.28, 0.28), randf_range(0.25, 0.8), randf_range(-0.28, 0.28)), 0.38, 0.3, Color(1.0, randf_range(0.2, 0.55), 0.04, 0.9))
			if flame != null:
				flame.vel = Vector3(randf_range(-0.25, 0.25), randf_range(0.25, 0.7), randf_range(-0.25, 0.25))
		return
	var decal := sprites.emit("scorch", pos, randf_range(0.25, 0.55), 18.0, Color(0.65, 0.045, 0.035, 0.9))
	if decal != null:
		decal.frame = randi() % sprites.frame_count("scorch")
		decal.angle = randf() * TAU
	for i in 3:
		var drop := sprites.emit("hit", pos + Vector3(randf_range(-0.25, 0.25), randf_range(0.2, 0.65), randf_range(-0.25, 0.25)), 0.2, 0.28, Color(0.8, 0.05, 0.025, 0.85))
		if drop != null:
			drop.vel = Vector3(randf_range(-0.7, 0.7), randf_range(0.1, 0.6), randf_range(-0.7, 0.7))


func _update_combat_fx(delta: float) -> void:
	for unit in _burning.keys():
		var entry: Array = _burning[unit]
		entry[0] = float(entry[0]) - delta
		var pos: Vector3 = entry[1]
		if avatar != null and (int(unit) == 0 or int(unit) == avatar.unit):
			pos = Vector3(avatar.position.x, 0.4, avatar.position.z)
		elif int(unit) > 0 and movers != null:
			var moving = movers.position_of(int(unit))
			if moving is Vector3:
				pos = moving + Vector3(0, 0.35, 0)
		if randf() < delta * 8.0:
			var flame := sprites.emit("hit", pos + Vector3(randf_range(-0.25, 0.25), randf_range(0.25, 0.8), randf_range(-0.25, 0.25)), 0.34, 0.28, Color(1.0, randf_range(0.2, 0.55), 0.03, 0.88))
			if flame != null:
				flame.vel = Vector3(randf_range(-0.2, 0.2), 0.35, randf_range(-0.2, 0.2))
		if float(entry[0]) <= 0.0:
			_burning.erase(unit)


# --- The character ----------------------------------------------------------------------------------

func _update_steps(delta: float) -> void:
	if not avatar.walking or avatar.vehicle != 0:
		_step_timer = STEP_INTERVAL * 0.5
		return
	_step_timer += delta
	if _step_timer < STEP_INTERVAL:
		return
	_step_timer = 0.0
	var ground := avatar.ground_position()
	var surface := _ground_under(ground)
	sfx.play_at(SoundBank.pick(surface[0]), avatar.position + Vector3(0, 0.1, 0), 0.5, 0.06, 1.0, "Walking")
	if FxSettings.effects_enabled and surface[1] is Color:
		var tint: Color = surface[1]
		var c := sprites.emit("dust", avatar.position + Vector3(randf_range(-0.15, 0.15), 0.15, randf_range(-0.15, 0.15)), 0.35, 0.7, Color(tint.r, tint.g, tint.b, 0.22))
		if c != null:
			c.size1 = 0.9
			c.vel = Vector3(0, 0.25, 0)


## [sound prefix, dust colour or null] for the ground at `p`: what the character stands on
## (belts, rails, ore), else the tile.
func _ground_under(p: Vector2) -> Array:
	var r := world.pick(p)
	if r != null:
		var proto: ProtoDB.EntityProto = world.protos.entity(r.proto_id)
		if proto != null:
			if proto.type in ["transport-belt", "underground-belt", "splitter"]:
				return ["core/sound/walking/transport-belt", null]
			if "rail" in proto.type:
				return ["base/sound/walking/rails/rails", null]
			if proto.type == "resource":
				var oil := "oil" in proto.name
				return ["base/sound/walking/resources/oil" if oil else "base/sound/walking/resources/ore", proto.color]
	var id := world.tile_at(floori(p.x), floori(p.y))
	if id < 0 or id >= world.protos.tile_names.size():
		return ["base/sound/walking/dirt-1", null]
	var tile := world.protos.tile_names[id]
	var color := world.protos.tile_color(id)
	if world.protos.is_water(id):
		return ["base/sound/walking/shallow-water", null]
	if "refined-concrete" in tile:
		return ["base/sound/walking/refined-concrete", null]
	if "concrete" in tile or "stone-path" in tile:
		return ["base/sound/walking/concrete", null]
	if "sand" in tile or "desert" in tile:
		return ["base/sound/walking/sand", color]
	if "grass" in tile:
		return ["base/sound/walking/grass", color]
	return ["base/sound/walking/dirt-1", color]


func _update_mining(delta: float) -> void:
	if avatar.mining < 0:
		_mine_timer = 0.15  # the first swing lands shortly after the button goes down
		_mine_target = Vector2(INF, INF)
		_last_mining_progress = -1
		return
	_last_mining_msec = Time.get_ticks_msec()
	_last_mining_at = avatar.mining_at
	if avatar.mining_at != _mine_target:
		_mine_target = avatar.mining_at
		_mine_kind = _mining_kind(avatar.mining_at)
	# A resource is mined over and over: each time the bar comes round, an item came out.
	if _mine_kind == "ore" and _last_mining_progress > avatar.mining + 30:
		sfx.play_at(SoundBank.pick("core/sound/picked-up-item"), avatar.position, 0.35, 0.05)
	_last_mining_progress = avatar.mining
	_mine_timer -= delta
	if _mine_timer > 0.0:
		return
	_mine_timer = MINE_INTERVAL
	var target := Vector3(avatar.mining_at.x, 0.0, avatar.mining_at.y)
	var toward := (avatar.position - target)
	toward.y = 0.0
	var hit := target + toward.normalized() * minf(0.5, toward.length()) + Vector3(0, 0.45, 0)
	match _mine_kind:
		"wood":
			sfx.play_at(SoundBank.pick("core/sound/mining-wood"), hit, 0.6, 0.06)
		"stone":
			sfx.play_at(SoundBank.pick("core/sound/axe-mining-stone"), hit, 0.6, 0.06)
		_:
			sfx.play_at(SoundBank.pick("core/sound/axe-mining-ore"), hit, 0.6, 0.06)
	if not FxSettings.effects_enabled:
		return
	if _mine_kind == "wood":
		for i in 2:
			var c := sprites.emit("dust", hit + Vector3(randf_range(-0.2, 0.2), randf_range(0.0, 0.4), randf_range(-0.2, 0.2)), 0.3, 0.6, Color(0.45, 0.33, 0.18, 0.5))
			if c != null:
				c.size1 = 0.6
				c.vel = Vector3(randf_range(-0.5, 0.5), 0.6, randf_range(-0.5, 0.5))
	else:
		var s := sprites.emit("sparks", hit, 0.5, 0.35)
		if s != null:
			s.spin = randf() * TAU
		var c := sprites.emit("dust", hit, 0.35, 0.6, Color(0.5, 0.45, 0.4, 0.35))
		if c != null:
			c.size1 = 0.8
			c.vel = Vector3(0, 0.4, 0)


## "wood" (trees), "stone" (rocks), "ore" (resources) or "other" (buildings).
func _mining_kind(at: Vector2) -> String:
	var r := world.pick(at)
	var proto: ProtoDB.EntityProto = world.protos.entity(r.proto_id) if r != null else null
	if proto == null:
		return "other"
	match proto.type:
		"tree":
			return "wood"
		"simple-entity":
			return "stone"
		"resource":
			return "ore"
	return "other"


## A gun's sound for each round the bridge reports (`shot`; weapon_fx.gd draws the flash).
func _on_shot(msg: Dictionary) -> void:
	var gun := str(msg.get("g", ""))
	var at := Vector3(avatar.position.x, CombatLayer.MUZZLE_HEIGHT, avatar.position.z)
	if int(msg.get("u", 0)) != avatar.unit:
		var p = movers.position_of(int(msg.get("u", 0)))
		if p == null:
			return
		at = p
	if GUN_SOUNDS.has(gun):
		sfx.play_at(SoundBank.pick(GUN_SOUNDS[gun]), at, 0.55, 0.05, 1.0, "Weapons")


## The flamethrower fires every tick, so no `shot` comes: its sound repeats while the character
## fires it (its streams are drawn from `pj`).
func _update_shots(delta: float) -> void:
	if not avatar.firing or combat == null or combat.aim_mode < 0 or _gun != "flamethrower":
		_shot_clock = 0.0
		return
	var before := _shot_clock
	_shot_clock += delta
	var interval := 0.5
	if before > 0.0 and floori(before / interval) == floori(_shot_clock / interval):
		return
	sfx.play_at(SoundBank.pick(GUN_SOUNDS["flamethrower"]), avatar.position + Vector3(0, CombatLayer.MUZZLE_HEIGHT, 0), 0.55, 0.05, 1.0, "Weapons")


# --- Building, rotating, mining out ---------------------------------------------------------------

func _on_add(e) -> void:
	if not (e is Array) or e.size() < 5:
		return
	var proto: ProtoDB.EntityProto = world.protos.entity(int(e[1]))
	if proto == null or proto.type in ["resource", "tree", "simple-entity", "fish", "item-entity"]:
		return
	var pos := Vector2(int(e[2]), int(e[3])) / 256.0
	if pos.distance_to(avatar.ground_position()) > BUILD_RANGE:
		return
	var ghost: bool = e.size() > 5 and e[5] is Dictionary and e[5].has("gh")
	var size := _size_class(proto)
	var at := Vector3(pos.x, 0.3, pos.y)
	if ghost:
		sfx.play_at("core/sound/build-ghost-%s.ogg" % size, at, 0.5)
		return
	sfx.play_at("core/sound/build-%s.ogg" % size, at, 0.7, 0.04)
	if FxSettings.effects_enabled:
		var s := proto.size()
		for i in clampi(int(s.x * s.y), 2, 8):
			var c := sprites.emit("dust", at + Vector3(randf_range(-0.5, 0.5) * s.x, 0.0, randf_range(-0.5, 0.5) * s.y), 0.6, 0.8, Color(0.55, 0.5, 0.42, 0.35))
			if c != null:
				c.size1 = 1.2
				c.vel = Vector3(randf_range(-0.4, 0.4), 0.3, randf_range(-0.4, 0.4))


func _on_upd(e) -> void:
	if not (e is Array) or e.size() < 5:
		return
	var unit := int(e[0])
	var key = unit if unit > 0 else WorldMirror.static_key(int(e[1]), int(e[2]), int(e[3]))
	var old: WorldMirror.Rec = world.entities.get(key)
	if old == null or old.proto_id != int(e[1]) or old.dir == int(e[4]):
		return
	if old.pos.distance_to(avatar.ground_position()) > BUILD_RANGE:
		return
	var proto: ProtoDB.EntityProto = world.protos.entity(old.proto_id)
	var size := _size_class(proto) if proto != null else "small"
	sfx.play_at("core/sound/rotate-%s.ogg" % ("big" if size == "large" else size), Vector3(old.pos.x, 0.3, old.pos.y), 0.6)


## The thing the character was mining is gone: Factorio's sound for having mined it.
func _on_del(msg: Dictionary) -> void:
	if Time.get_ticks_msec() - _last_mining_msec > 1500:
		return
	var unit := int(msg.get("u", 0))
	var key = unit if unit > 0 else WorldMirror.static_key(int(msg.get("p", 0)), int(msg.get("x", 0)), int(msg.get("y", 0)))
	var r: WorldMirror.Rec = world.entities.get(key)
	if r == null:
		return
	var proto: ProtoDB.EntityProto = world.protos.entity(r.proto_id)
	if proto == null:
		return
	if not WorldMirror.selection_rect(proto, r.pos, r.dir).grow(0.6).has_point(_last_mining_at):
		return
	var at := Vector3(r.pos.x, 0.4, r.pos.y)
	match proto.type:
		"tree":
			sfx.play_at(SoundBank.pick("core/sound/mining-wood"), at, 0.8)
		"simple-entity":
			sfx.play_at("core/sound/deconstruct-bricks.ogg", at, 0.7)
		_:
			sfx.play_at("core/sound/deconstruct-%s.ogg" % _size_class(proto), at, 0.7)
	if FxSettings.effects_enabled:
		for i in 4:
			var c := sprites.emit("dust", at + Vector3(randf_range(-0.4, 0.4), randf_range(0.0, 0.6), randf_range(-0.4, 0.4)), 0.6, 0.8, Color(0.5, 0.46, 0.4, 0.4))
			if c != null:
				c.size1 = 1.2
				c.vel = Vector3(randf_range(-0.5, 0.5), 0.5, randf_range(-0.5, 0.5))


static func _size_class(proto: ProtoDB.EntityProto) -> String:
	var s := maxi(proto.tile_size.x, proto.tile_size.y)
	return "small" if s <= 1 else ("medium" if s <= 3 else "large")


# --- Deaths -------------------------------------------------------------------------------------

func _on_died(msg: Dictionary) -> void:
	var proto: ProtoDB.EntityProto = world.protos.entity(int(msg.get("p", 0)))
	var pos := Vector2(int(msg.get("x", 0)), int(msg.get("y", 0))) / 256.0
	var at := Vector3(pos.x, 0.0, pos.y)
	if proto == null:
		return
	if ENEMY_TYPES.has(proto.type):
		var big := "big" in proto.name or "behemoth" in proto.name
		sfx.play_at(SoundBank.pick("base/sound/creatures/biter-death-big" if big else "base/sound/creatures/biter-death"), at, 0.6, 0.06, 1.0, "Enemies")
		if FxSettings.effects_enabled:
			for i in 3:
				var c := sprites.emit("dust", at + Vector3(randf_range(-0.3, 0.3), 0.3, randf_range(-0.3, 0.3)), 0.5, 0.7, Color(0.42, 0.3, 0.12, 0.6))
				if c != null:
					c.size1 = 1.0
					c.vel = Vector3(randf_range(-0.6, 0.6), 0.5, randf_range(-0.6, 0.6))
			# The corpse itself is creatures.gd's (the enemy's corpse model).
		return
	if proto.type in ["tree", "character", "resource", "fish"]:
		return
	var s := proto.size()
	var extent := maxf(s.x, s.y)
	if proto.type == "car":
		sfx.play_at(SoundBank.pick("base/sound/fight/car-explosion"), at, 0.8, 0.0, 1.0, "Explosions")
	elif extent >= 4.0:
		sfx.play_at(SoundBank.pick("base/sound/fight/large-explosion"), at, 0.8, 0.0, 1.0, "Explosions")
	elif extent >= 1.5:
		sfx.play_at(SoundBank.pick("base/sound/fight/medium-explosion"), at, 0.8, 0.0, 1.0, "Explosions")
	else:
		sfx.play_at(SoundBank.pick("base/sound/small-explosion"), at, 0.8, 0.0, 1.0, "Explosions")
	if not FxSettings.effects_enabled:
		return
	# The entity's own dying explosion, as Factorio plays it.
	var dying := weapons.dying_explosion(proto.name)
	if dying != "":
		weapons.explode(dying, at)
		return
	var sheet := "explosion" if extent >= 1.5 else "small-explosion"
	var width := clampf(extent * 0.9, 1.4, 5.0)
	var aspect := 224.0 / 124.0 if sheet == "explosion" else 178.0 / 88.0
	sprites.emit(sheet, at + Vector3(0, width * aspect * 0.45, 0), width, 1.0 if sheet == "explosion" else 0.8)
	# No marks on a space platform: there is no ground to burn.
	var scorch: SpriteFx.Card = null if weapons.in_space else sprites.emit("scorch", at + Vector3(0, 0.03, 0), extent + 1.2, REMNANT_SECONDS)
	if scorch != null:
		scorch.frame = randi() % sprites.frame_count("scorch")
		scorch.angle = randf() * TAU
	# What is left of it is a remnants entity in the game, streamed and drawn with the world
	# (ModelLibrary.remnant_mesh).


func _add_corpse(proto: ProtoDB.EntityProto, at: Vector3, yaw: float, life: float, material: Material, squash: float) -> void:
	var mi := MeshInstance3D.new()
	var mesh := ModelLibrary.mesh_for(proto.name)
	var shape := Transform3D.IDENTITY
	if mesh != null:
		mi.mesh = mesh
	else:
		mi.mesh = Visuals.box_mesh()
		shape = Visuals.placeholder_transform(proto, Vector2.ZERO, 0, Visuals.height_for(proto))
	mi.material_override = material
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var holder := Node3D.new()
	holder.position = at
	holder.basis = Basis(Vector3.UP, yaw) * Basis.from_scale(Vector3(1.0, squash, 1.0))
	mi.transform = shape
	holder.add_child(mi)
	add_child(holder)
	_corpses.append([holder, 0.0, life, at.y])
	while _corpses.size() > CORPSE_LIMIT:
		(_corpses.pop_front()[0] as Node3D).queue_free()


func _update_corpses(delta: float) -> void:
	for i in range(_corpses.size() - 1, -1, -1):
		var c: Array = _corpses[i]
		var age: float = c[1] + delta
		c[1] = age
		var node: Node3D = c[0]
		var life: float = c[2]
		if age >= life:
			node.queue_free()
			_corpses.remove_at(i)
		elif age > life - SINK_SECONDS:
			node.position.y = float(c[3]) - (age - (life - SINK_SECONDS)) / SINK_SECONDS * 0.6


func corpse_count() -> int:
	return _corpses.size()


func status() -> String:
	return "sound %d loops %d one-shots · %d effect cards · %d smoke sources · %s" % [sfx.busy_loops(), sfx.busy_shots(), sprites.count(), _emitters.size(), weapons.status()]
