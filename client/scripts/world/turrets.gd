extends Node3D
## Turrets and vehicle guns as Factorio animates them, from the mod's turret states (`ts`: where
## each weapon points, its target and the shots it fired; turrets.lua) and firing cues (`tf`):
##
## - heads turn to the game's orientation at the prototype's rotation_speed;
## - turrets raise while they have a target and fold after they lose it (Factorio's folded,
##   preparing, prepared, attacking and folding states, at each one's preparing_speed and
##   folding_speed), each in its own way: the gun turret lifts its barrels, the laser and tesla
##   heads rise out of the base, the flamethrower's nozzle slides out, the rocket pods open, the
##   railgun lowers its barrel from upright;
## - each shot (at most as often as the weapon's cooldown) kicks the barrel back and draws what
##   Factorio draws there, with the player's install's sprites and sounds: muzzle flashes
##   (explosion-gunshot, the artillery's muzzle-flash), the red laser beam, the tesla's lightning,
##   the railgun's beam, the flamethrower's burning stream arcing to its target;
## - vehicles (car, tank, artillery wagon) turn their turret part relative to the body; the
##   spidertron fires from its four launchers in turn.
##
## anim.gd hands each turret head (chunk MultiMesh instances) to head_transform() every frame;
## vehicles are found through movers.gd. Rockets, shells and artillery shells in flight and their
## explosions belong to the projectile drawing (weapons-hand's weapon_fx.gd); this draws their
## launch. Once the mod sends the game's own beams and streams (`pj`), the laser and tesla beams
## and the flame streams are left to that too (they start where the game has them); until then
## (an older mod, the mock) this draws them from the shots.

const ModelLibrary := preload("res://scripts/world/model_library.gd")
const SoundBank := preload("res://scripts/fx/sound_bank.gd")
const FxSettings := preload("res://scripts/fx/fx_settings.gd")
const BeamShader := preload("res://shaders/fx_beam.gdshader")

## A target counts as current this long after a report names it (reports come every 6 ticks).
const TARGET_HOLD := 0.4
## Seconds a turret stays raised without a target before it folds.
const FOLD_DELAY := 0.5
## Shots reported together are spread over the report's interval (6 ticks).
const REPORT_SECONDS := 0.1
const MAX_QUEUED := 16
## Heads turn a little faster than Factorio's rotation_speed so they catch up with reports.
const CATCH_UP := 1.3

## Per prototype (Factorio 2.1.23's values): rotation speed (turns a tick), preparing and folding
## speeds (of the whole animation a tick; 0 = never folds), cooldown (ticks), weapon kind, the
## folded pose (`drop`, `back` and `squeeze` as fractions of the head's size, `pitch` in radians,
## nose up), recoil (tiles, seconds), the firing, raising and folding sounds.
const TURRETS := {
	"gun-turret": {"rot": 0.015, "prep": 0.08, "fold": 0.08, "cooldown": 6, "kind": "bullet",
		"pose": {"drop": -0.06, "pitch": -0.18}, "recoil": [0.05, 0.08],
		"sound": "base/sound/fight/gun-turret-gunshot", "up": "base/sound/fight/gun-turret-activate",
		"down": "base/sound/fight/gun-turret-deactivate"},
	"laser-turret": {"rot": 0.01, "prep": 0.05, "fold": 0.05, "cooldown": 40, "kind": "laser",
		"pose": {"drop": -0.55}, "recoil": [0.0, 0.1], "sound": "base/sound/fight/laser-beam",
		"up": "base/sound/fight/laser-turret-activate", "down": "base/sound/fight/laser-turret-deactivate"},
	"flamethrower-turret": {"rot": 0.015, "prep": 0.08, "fold": 0.08, "cooldown": 4, "kind": "flame",
		"pose": {"back": 0.35, "drop": -0.12}, "recoil": [0.0, 0.1], "stream": 15.0, "gravity": 10.8,
		"sound": "base/sound/fight/flamethrower-turret-mid", "start": "base/sound/fight/flamethrower-turret-start",
		"end": "base/sound/fight/flamethrower-turret-end",
		"up": "base/sound/fight/flamethrower-turret-activate", "down": "base/sound/fight/flamethrower-turret-deactivate"},
	"rocket-turret": {"rot": 0.005, "prep": 0.08, "fold": 0.08, "cooldown": 120, "kind": "rocket",
		"pose": {"squeeze": 0.55, "drop": -0.2}, "recoil": [0.05, 0.2], "launchers": 6,
		"sound": "space-age/sound/ammo/rocket-turret-launcher",
		"up": "space-age/sound/entity/rocket-turret/rocket-turret-activate",
		"down": "space-age/sound/entity/rocket-turret/rocket-turret-deactivate"},
	"tesla-turret": {"rot": 0.005, "prep": 0.1, "fold": 0.1, "cooldown": 120, "kind": "tesla",
		"pose": {"drop": -0.5}, "recoil": [0.0, 0.1], "sound": "space-age/sound/entity/tesla-turret/tesla-turret-beam",
		"up": "space-age/sound/entity/tesla-turret/tesla-turret-activate",
		"down": "space-age/sound/entity/tesla-turret/tesla-turret-deactivate"},
	"railgun-turret": {"rot": 0.005, "prep": 0.04, "fold": 0.04, "cooldown": 170, "kind": "railgun",
		"pose": {"pitch": 1.0}, "recoil": [0.35, 0.6],
		"sound": "space-age/sound/entity/railgun-turret/railgun-turret-gunshot",
		"up": "space-age/sound/entity/railgun-turret/railgun-turret-activate",
		"down": "space-age/sound/entity/railgun-turret/railgun-turret-deactivate"},
	"artillery-turret": {"rot": 0.001, "prep": 0.0, "fold": 0.0, "cooldown": 200, "kind": "artillery",
		"pose": {}, "recoil": [0.3, 0.7], "sound": "base/sound/fight/artillery-shoots"},
	"artillery-wagon": {"rot": 0.001, "prep": 0.0, "fold": 0.0, "cooldown": 200, "kind": "artillery",
		"pose": {}, "recoil": [0.3, 0.7], "sound": "base/sound/fight/artillery-shoots", "vehicle": true},
	# Vehicles: one weapon per gun slot (selected_gun_index).
	"car": {"rot": 0.0058333, "prep": 0.0, "fold": 0.0, "vehicle": true, "guns": ["vehicle-machine-gun"]},
	"tank": {"rot": 0.0058333, "prep": 0.0, "fold": 0.0, "vehicle": true,
		"guns": ["tank-cannon", "tank-machine-gun", "tank-flamethrower"]},
	"spidertron": {"rot": 0.005, "prep": 0.0, "fold": 0.0, "vehicle": true, "torso": true, "launchers": 4,
		"guns": ["spidertron-rocket-launcher", "spidertron-rocket-launcher", "spidertron-rocket-launcher",
			"spidertron-rocket-launcher"]},
}
## Vehicle guns: cooldown, kind, recoil, sound.
const GUNS := {
	"vehicle-machine-gun": {"cooldown": 4, "kind": "bullet", "recoil": [0.02, 0.05], "sound": "base/sound/fight/heavy-gunshot"},
	"tank-machine-gun": {"cooldown": 4, "kind": "bullet", "recoil": [0.0, 0.05], "sound": "base/sound/fight/heavy-gunshot"},
	"tank-cannon": {"cooldown": 90, "kind": "cannon", "recoil": [0.18, 0.4], "sound": "base/sound/fight/tank-cannon"},
	"tank-flamethrower": {"cooldown": 1, "kind": "flame", "recoil": [0.0, 0.1], "stream": 27.0, "gravity": 5.4,
		"sound": "base/sound/fight/flamethrower-mid", "start": "base/sound/fight/flamethrower-start",
		"end": "base/sound/fight/flamethrower-end"},
	"spidertron-rocket-launcher": {"cooldown": 60, "kind": "rocket", "recoil": [0.0, 0.1],
		"sound": "base/sound/spidertron/spidertron-rocket-launcher"},
}
## Beams: sheet (under the install's data/), frame size, columns, frames, frames per second,
## tiles one frame covers along the beam, width in tiles, frames along the sheet's height
## instead of its width (the railgun's), colour of its light, how long a shot holds it (s).
const BEAMS := {
	"laser": ["base/graphics/entity/laser-turret/laser-body.png", Vector2(64, 12), 8, 8, 30.0, 1.0, 0.22, false,
		Color(1.0, 0.2, 0.12), 40.0 / 60.0],
	"tesla": ["space-age/graphics/entity/beam/tesla-body-1.png", Vector2(64, 64), 10, 20, 30.0, 1.0, 0.9, false,
		Color(0.4, 0.85, 1.0), 30.0 / 60.0],
	"railgun": ["space-age/graphics/entity/railgun-turret/railgun-beam.png", Vector2(64, 440), 16, 16, 60.0, 13.75, 1.2, true,
		Color(0.55, 0.9, 0.9), 16.0 / 60.0],
}
const RAILGUN_LENGTH := 40.0  # the beam runs out to the turret's range


class TurretState:
	var unit := 0
	var name := ""
	var cfg: Dictionary = {}
	var vehicle := false
	var yaw := 0.0  # turns, as Factorio's orientation (absolute; a vehicle's relative to its body)
	var goal := 0.0
	var seen := false
	var gun := 1
	var fold := 0.0  # 0 folded, 1 prepared
	var target := Vector3.ZERO
	var target_seen := -1000.0
	var shots: Array[float] = []  # clock times of shots still to draw
	var next_shot := 0.0  # the weapon's cooldown
	var since_shot := 100.0
	var launcher := 0
	var muzzle := Vector3.ZERO  # world position, updated with the head
	var forward := Vector3.FORWARD
	var beam_kind := ""
	var beam_left := 0.0
	var flame_left := 0.0
	var flame_emit := 0.0
	var flame_sound := 0.0
	var light: OmniLight3D
	var light_energy := 0.0
	var beam: MeshInstance3D
	var beam_age := 0.0
	var fired := 0  # shots drawn (for the UI test)


## movers.gd (vehicles), fx.gd (its sprites and sounds); set by main.gd.
var movers: Node
var fx: Node

var _states := {}  # unit -> TurretState
var _clock := 0.0
var _muzzles := {}  # model -> muzzle point in model space
var _beam_materials := {}  # kind -> ShaderMaterial (null when the sheet is missing)
## True once a `pj` message has come: the game's beam and stream entities are drawn from it.
var game_beams := false


func reset() -> void:
	for st: TurretState in _states.values():
		_free_nodes(st)
	_states.clear()


func count() -> int:
	return _states.size()


func state_of(unit: int) -> TurretState:
	return _states.get(unit)


## {t: "ts", l: [[unit, orientation (1/1000 turn), shots, gun, target x?, target y?], ...]}
func handle_states(msg: Dictionary) -> void:
	var list = msg.get("l")
	if not (list is Array):
		return
	for rec in list:
		if not (rec is Array) or rec.size() < 4:
			continue
		var st := _state(int(rec[0]))
		st.goal = int(rec[1]) / 1000.0
		if not st.seen:
			st.yaw = st.goal
			st.seen = true
		st.gun = maxi(1, int(rec[3]))
		if rec.size() >= 6:
			st.target = Vector3(int(rec[4]) / 256.0, 0.45, int(rec[5]) / 256.0)
			st.target_seen = _clock
		var n := mini(int(rec[2]), MAX_QUEUED)
		for i in n:
			if st.shots.size() < MAX_QUEUED:
				st.shots.append(_clock + REPORT_SECONDS * i / maxf(1.0, n))


## Any {t: "pj"} (projectiles, streams and beams in flight): the game's beams and streams are
## drawn from those from now on.
func handle_projectiles(_msg: Dictionary) -> void:
	game_beams = true


## {t: "tf", u, w, x, y}: a turret's hit, where it landed (the target's centre).
func handle_fire(msg: Dictionary) -> void:
	var st: TurretState = _states.get(int(msg.get("u", 0)))
	if st == null:
		return
	st.target = Vector3(int(msg.get("x", 0)) / 256.0, 0.45, int(msg.get("y", 0)) / 256.0)
	st.target_seen = _clock


## A chunk turret's head: its transform in the model (anim.gd draws it at base * this), with the
## turret's state advanced by `delta`. `unit` 0 (no unit number) is drawn folded, facing north.
func head_transform(unit: int, part: ModelLibrary.AnimPart, base: Transform3D, delta: float) -> Transform3D:
	var st: TurretState = _states.get(unit) if unit > 0 else null
	if st == null:
		var cfg0: Dictionary = TURRETS.get(part.model, {})
		return _pose(part, 0.0, 1.0 if float(cfg0.get("prep", 1.0)) == 0.0 else 0.0, cfg0, 100.0)
	if st.cfg.is_empty():
		st.name = part.model
		st.cfg = TURRETS.get(part.model, TURRETS["gun-turret"])
		st.vehicle = bool(st.cfg.get("vehicle", false))
		if float(st.cfg["prep"]) == 0.0:
			st.fold = 1.0
	_advance(st, delta)
	var base_turns := -base.basis.get_euler().y / TAU
	var local_yaw := -(st.yaw - base_turns) * TAU
	var xf := _pose(part, local_yaw, st.fold, st.cfg, st.since_shot)
	var world := base * xf
	st.muzzle = world * _muzzle_point(part, st)
	st.forward = (world.basis * Vector3.FORWARD).normalized()
	_fire_due(st)
	return xf


func _process(delta: float) -> void:
	_clock += delta
	if movers != null:
		for st: TurretState in _states.values():
			if st.cfg.is_empty() and movers.call("node_of", st.unit) != null:
				var name: String = movers.call("proto_name_of", st.unit)
				if TURRETS.has(name) and bool(TURRETS[name].get("vehicle", false)):
					st.name = name
					st.cfg = TURRETS[name]
					st.vehicle = true
					st.fold = 1.0
			if st.vehicle:
				_vehicle(st, delta)
	for st: TurretState in _states.values():
		_update_effects(st, delta)


func _state(unit: int) -> TurretState:
	var st: TurretState = _states.get(unit)
	if st == null:
		st = TurretState.new()
		st.unit = unit
		_states[unit] = st
	return st


## Turning, raising and folding, the cooldown.
func _advance(st: TurretState, delta: float) -> void:
	var cfg := st.cfg
	var rate := float(cfg["rot"]) * 60.0 * delta * CATCH_UP
	var diff := wrapf(st.goal - st.yaw, -0.5, 0.5)
	st.yaw = wrapf(st.yaw + clampf(diff, -rate, rate), 0.0, 1.0)
	st.since_shot += delta
	var prep := float(cfg["prep"])
	if prep <= 0.0:
		st.fold = 1.0
		return
	var wants := _clock - st.target_seen < TARGET_HOLD or not st.shots.is_empty()
	if wants:
		if st.fold <= 0.0:
			_sound(st, "up")
		st.fold = minf(1.0, st.fold + prep * 60.0 * delta)
	elif _clock - st.target_seen > TARGET_HOLD + FOLD_DELAY and st.fold > 0.0:
		if st.fold >= 1.0:
			_sound(st, "down")
		st.fold = maxf(0.0, st.fold - float(cfg["fold"]) * 60.0 * delta)


## The head in the model: turned by `yaw` radians about its pivot, posed between folded (0) and
## prepared (1), kicked back by the last shot.
func _pose(part: ModelLibrary.AnimPart, yaw: float, fold: float, cfg: Dictionary, since_shot: float) -> Transform3D:
	var size := part.mesh.get_aabb().size if part.mesh != null else Vector3.ONE
	var pose: Dictionary = cfg.get("pose", {})
	var f := 1.0 - fold  # how folded
	f = f * f * (3.0 - 2.0 * f)
	var offset := Vector3(0.0, float(pose.get("drop", 0.0)) * size.y * f, float(pose.get("back", 0.0)) * size.z * f)
	var recoil: Array = cfg.get("recoil", [0.0, 0.1])
	if float(recoil[0]) > 0.0 and since_shot < float(recoil[1]):
		var k := 1.0 - since_shot / float(recoil[1])
		offset.z += float(recoil[0]) * k * k
	var basis := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, float(pose.get("pitch", 0.0)) * f)
	var squeeze := float(pose.get("squeeze", 1.0))
	if squeeze != 1.0:
		basis *= Basis.from_scale(Vector3(lerpf(1.0, squeeze, f), 1.0, 1.0))
	var moved := Transform3D(basis, basis * offset)
	return part.pivot * moved * part.pivot.affine_inverse()


## A vehicle's turret: its part under the mover's node turned relative to the body; the
## spidertron's launchers follow the torso.
func _vehicle(st: TurretState, delta: float) -> void:
	var node: Node3D = movers.call("node_of", st.unit)
	if node == null:
		return
	_advance(st, delta)
	var found := false
	for child in node.get_children():
		if child.has_meta("turret_head"):
			var part: ModelLibrary.AnimPart = child.get_meta("turret_head")
			var gcfg := _gun_cfg(st)
			var xf := _pose(part, -st.yaw * TAU, 1.0, gcfg, st.since_shot)
			(child as Node3D).transform = xf
			var world := node.global_transform * xf
			st.muzzle = world * _muzzle_point(part, st)
			st.forward = (world.basis * Vector3.FORWARD).normalized()
			found = true
	if not found:
		# No turret part (the spidertron): launchers on top of the body, turned with the torso.
		var top := 1.6
		for child in node.get_children():
			# The body and its torso (the legs reach higher, and step: vehicle_anim.gd).
			var mesh_node := child as MeshInstance3D
			if mesh_node == null or mesh_node.mesh == null:
				continue
			if child.has_meta("part") and (child.get_meta("part") as ModelLibrary.AnimPart).kind != "torso":
				continue
			top = maxf(top, mesh_node.mesh.get_aabb().end.y * mesh_node.scale.y)
		var torso := Basis(Vector3.UP, -st.yaw * TAU) if bool(st.cfg.get("torso", false)) else node.global_transform.basis
		var side := -0.35 if st.launcher % 2 == 0 else 0.35
		var row := 0.15 if (st.launcher / 2) % 2 == 0 else -0.05
		st.muzzle = node.global_position + torso * Vector3(side, top * 0.85 + row, -0.45)
		st.forward = torso * Vector3.FORWARD
	_fire_due(st)


func _gun_cfg(st: TurretState) -> Dictionary:
	var guns: Array = st.cfg.get("guns", [])
	if guns.is_empty():
		return st.cfg
	return GUNS.get(str(guns[clampi(st.gun - 1, 0, guns.size() - 1)]), {})


## Shots whose time has come, once the turret is raised, no faster than its cooldown.
func _fire_due(st: TurretState) -> void:
	if st.shots.is_empty():
		return
	if st.fold < 1.0:
		return
	var gcfg := _gun_cfg(st)
	var cooldown := float(gcfg.get("cooldown", st.cfg.get("cooldown", 6))) / 60.0
	while not st.shots.is_empty() and st.shots[0] <= _clock:
		var at: float = st.shots.pop_front()
		if at < _clock - 1.0:
			continue  # stale (a stall): drop it
		if _clock < st.next_shot - 0.5 / 60.0:
			st.shots.push_front(maxf(at, st.next_shot))
			break
		st.next_shot = _clock + cooldown
		_fire(st, gcfg)


func _fire(st: TurretState, gcfg: Dictionary) -> void:
	st.since_shot = 0.0
	st.fired += 1
	var kind := str(gcfg.get("kind", "bullet"))
	var target := st.target if _clock - st.target_seen < 1.5 else st.muzzle + st.forward * 10.0
	var dir := (target - st.muzzle).normalized() if target.distance_to(st.muzzle) > 0.05 else st.forward
	var sprites: Node = fx.get("sprites") if fx != null else null
	var effects := FxSettings.effects_enabled and sprites != null
	match kind:
		"bullet":
			_flash(st, Color(1.0, 0.75, 0.35), 1.6)
			if effects:
				var flash = sprites.call("emit", "muzzle", st.muzzle + dir * 0.12, 0.45, 0.07)
				if flash != null:
					flash.spin = atan2(dir.y, Vector2(dir.x, dir.z).length())
				var hit = sprites.call("emit", "bullet-hit", target + Vector3(randf_range(-0.2, 0.2), 0.1, randf_range(-0.2, 0.2)), 0.55, 0.15)
				if hit != null:
					hit.spin = randf() * TAU
		"cannon":
			_flash(st, Color(1.0, 0.7, 0.3), 3.0)
			if effects:
				sprites.call("emit", "muzzle", st.muzzle + dir * 0.2, 1.1, 0.1)
				_smoke(sprites, st.muzzle + dir * 0.3, 3, 0.7)
		"rocket":
			st.launcher += 1
			_flash(st, Color(1.0, 0.6, 0.25), 2.0)
			if effects:
				var at := _launcher_point(st)
				sprites.call("emit", "muzzle", at, 0.7, 0.1)
				_smoke(sprites, at - dir * 0.3, 2, 0.6)
		"artillery":
			_flash(st, Color(1.0, 0.65, 0.3), 5.0)
			if effects:
				# Factorio's flash (276x382 px at scale 0.5): 4.3 tiles wide, its base at the muzzle.
				var flash = sprites.call("emit", "artillery-flash", st.muzzle + Vector3(0.0, 2.6, 0.0) + dir * 0.4, 4.3, 28.0 / 60.0)
				if flash != null:
					flash.spin = atan2(-dir.x, 1.0) * 0.3
				_smoke(sprites, st.muzzle + dir * 0.5, 4, 1.2)
		"railgun":
			_flash(st, Color(0.55, 0.9, 0.9), 6.0)
			_beam_start(st, "railgun")
			if effects:
				sprites.call("emit", "muzzle", st.muzzle + dir * 0.3, 1.2, 0.1)
		"laser", "tesla":
			if not game_beams:
				_beam_start(st, kind)
			_flash(st, BEAMS[kind][8], 1.0)
		"flame":
			if st.flame_left <= 0.0:
				_sound_path(st, str(gcfg.get("start", "")))
				st.flame_sound = 0.0
			st.flame_left = maxf(st.flame_left, float(gcfg.get("cooldown", 4)) / 60.0 + 0.12)
			return
	_sound_path(st, str(gcfg.get("sound", "")))


func _launcher_point(st: TurretState) -> Vector3:
	if bool(st.cfg.get("torso", false)):
		return st.muzzle
	var count := int(st.cfg.get("launchers", 1))
	if count <= 1:
		return st.muzzle
	# Factorio's six offsets: left, right, a row lower each time.
	var side := 1.0 if st.launcher % 2 == 0 else -1.0
	var row := (st.launcher / 2) % (count / 2)
	var across := st.forward.cross(Vector3.UP).normalized()
	return st.muzzle + across * side * (0.55 - 0.07 * row) + Vector3(0.0, -0.12 * row, 0.0)


func _smoke(sprites: Node, at: Vector3, n: int, size: float) -> void:
	for i in n:
		var puff = sprites.call("emit", "dust", at + Vector3(randf_range(-0.2, 0.2), randf_range(0.0, 0.2), randf_range(-0.2, 0.2)),
			size * randf_range(0.8, 1.2), randf_range(0.5, 0.8), Color(0.75, 0.72, 0.68, 0.7))
		if puff != null:
			puff.vel = Vector3(randf_range(-0.4, 0.4), randf_range(0.3, 0.8), randf_range(-0.4, 0.4))
			puff.size1 = size * 2.0
			puff.drag = 1.5


func _flash(st: TurretState, color: Color, energy: float) -> void:
	if st.light == null:
		st.light = OmniLight3D.new()
		st.light.omni_range = 4.0
		st.light.shadow_enabled = false
		add_child(st.light)
	st.light.light_color = color
	st.light_energy = maxf(st.light_energy, energy)


func _sound(st: TurretState, key: String) -> void:
	_sound_path(st, str(st.cfg.get(key, "")))


func _sound_path(st: TurretState, prefix: String) -> void:
	if prefix == "" or fx == null:
		return
	var sfx: Node = fx.get("sfx")
	if sfx == null:
		return
	sfx.call("play_at", SoundBank.pick(prefix), st.muzzle, 0.6, 0.05, 1.0, "Weapons")


func _beam_start(st: TurretState, kind: String) -> void:
	var spec: Array = BEAMS[kind]
	st.beam_kind = kind
	st.beam_left = float(spec[9])
	st.beam_age = 0.0
	if kind == "railgun":
		st.target = st.muzzle + (st.target - st.muzzle).normalized() * RAILGUN_LENGTH if st.target.distance_to(st.muzzle) > 0.1 \
			else st.muzzle + st.forward * RAILGUN_LENGTH
		st.target_seen = _clock


## Beams, flame streams and lights, every frame.
func _update_effects(st: TurretState, delta: float) -> void:
	if st.light != null:
		st.light_energy = maxf(0.0, st.light_energy - delta * 14.0)
		var on := st.light_energy > 0.01
		st.light.visible = on
		if on:
			st.light.global_position = st.muzzle
			st.light.light_energy = st.light_energy
	if st.beam_left > 0.0:
		st.beam_left -= delta
		st.beam_age += delta
		_draw_beam(st)
	elif st.beam != null and st.beam.visible:
		st.beam.visible = false
	if st.flame_left > 0.0:
		st.flame_left -= delta
		_flame(st, delta)
		if st.flame_left <= 0.0:
			_sound_path(st, str(_gun_cfg(st).get("end", "")))


func _draw_beam(st: TurretState) -> void:
	var cam := get_viewport().get_camera_3d()
	var mat := _beam_material(st.beam_kind)
	if cam == null or mat == null:
		return
	if st.beam == null:
		st.beam = MeshInstance3D.new()
		var quad := QuadMesh.new()
		quad.size = Vector2.ONE
		st.beam.mesh = quad
		st.beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(st.beam)
	var spec: Array = BEAMS[st.beam_kind]
	st.beam.material_override = mat
	var from := st.muzzle
	var to := st.target
	var along := to - from
	var length := along.length()
	if length < 0.05:
		st.beam.visible = false
		return
	var x := along / length
	var view := (cam.global_position - (from + to) * 0.5).normalized()
	var y := x.cross(view).normalized()
	if y.length_squared() < 0.001:
		y = Vector3.UP
	var width := float(spec[6])
	var basis := Basis(x * length, y * width, x.cross(y).normalized())
	st.beam.global_transform = Transform3D(basis, (from + to) * 0.5)
	st.beam.visible = true
	st.beam.set_instance_shader_parameter("frame", fmod(st.beam_age * float(spec[4]), float(spec[3])))
	st.beam.set_instance_shader_parameter("tiles", length / float(spec[5]))
	var fade := clampf(st.beam_left / 0.08, 0.0, 1.0)
	st.beam.set_instance_shader_parameter("strength", 1.4 * fade)
	_flash(st, spec[8], 1.2 * fade)


func _beam_material(kind: String) -> ShaderMaterial:
	if _beam_materials.has(kind):
		return _beam_materials[kind]
	var spec: Array = BEAMS[kind]
	var tex := _load_texture(str(spec[0]))
	var mat: ShaderMaterial = null
	if tex != null:
		mat = ShaderMaterial.new()
		mat.shader = BeamShader
		mat.render_priority = 2
		var frame: Vector2 = spec[1]
		var cols := float(spec[2])
		var rows := ceilf(float(spec[3]) / cols)
		mat.set_shader_parameter("atlas", tex)
		mat.set_shader_parameter("grid", Vector2(cols, rows))
		mat.set_shader_parameter("vertical", bool(spec[7]))
		mat.set_shader_parameter("cell", frame / Vector2(tex.get_width(), tex.get_height()))
	_beam_materials[kind] = mat
	return mat


## The burning stream: a fire particle every 2 ticks arcing from the nozzle to the target
## (flamethrower-fire-stream: 0.25 tiles a tick out, 0.003 down; the tank's 0.45 and 0.0015).
func _flame(st: TurretState, delta: float) -> void:
	var gcfg := _gun_cfg(st)
	st.flame_sound -= delta
	if st.flame_sound <= 0.0:
		st.flame_sound = 0.9
		_sound_path(st, str(gcfg.get("sound", "")))
	_flash(st, Color(1.0, 0.5, 0.0), 1.4)
	var sprites: Node = fx.get("sprites") if fx != null else null
	if not FxSettings.effects_enabled or sprites == null:
		return
	st.flame_emit -= delta
	if st.flame_emit > 0.0:
		return
	st.flame_emit = 2.0 / 60.0
	# The fire at the nozzle (muzzle_animation), then the stream unless the game's comes in `pj`.
	var nozzle = sprites.call("emit", "flame-muzzle", st.muzzle, 0.25, 0.1)
	if nozzle != null:
		nozzle.spin = atan2(st.forward.x, 1.0) * 0.2
	if game_beams:
		return
	var target := st.target + Vector3(randf_range(-0.3, 0.3), -0.4, randf_range(-0.3, 0.3))
	var flat := Vector3(target.x - st.muzzle.x, 0.0, target.z - st.muzzle.z)
	var speed := float(gcfg.get("stream", 15.0))
	var g := float(gcfg.get("gravity", 10.8))
	var t := clampf(flat.length() / speed, 0.08, 2.5)
	# Factorio's particle starts at 0.2 of its 124 px (at 0.666) and grows on the way.
	var card = sprites.call("emit", "flame-stream", st.muzzle, 0.55, t)
	if card != null:
		card.vel = flat / t + Vector3(0.0, (target.y - st.muzzle.y + 0.5 * g * t * t) / t, 0.0)
		card.rise = -g
		card.size1 = 2.2
		card.spin = randf() * TAU


## Where shots leave the head, in model space: the middle of its foremost faces (the barrels'
## ends); the tesla's from the top of its coil.
func _muzzle_point(part: ModelLibrary.AnimPart, st: TurretState) -> Vector3:
	var key := part.model
	if _muzzles.has(key):
		return _muzzles[key]
	var aabb := part.mesh.get_aabb() if part.mesh != null else AABB()
	var point := aabb.get_center()
	if str(st.cfg.get("kind", "")) == "tesla":
		point = Vector3(aabb.get_center().x, aabb.end.y - 0.1, aabb.get_center().z)
	elif part.mesh != null:
		var faces := _faces(part.mesh)
		if not faces.is_empty():
			var front := INF
			for v in faces:
				front = minf(front, v.z)
			var sum := Vector3.ZERO
			var n := 0
			for v in faces:
				if v.z <= front + 0.03:
					sum += v
					n += 1
			if n > 0:
				point = sum / n
	_muzzles[key] = point
	return point


## Mesh.get_faces() from the mesh's CPU arrays (ModelLods.arrays_of): get_faces reads them from the
## RenderingServer, a wait for the render thread when it runs on its own.
static func _faces(mesh: Mesh) -> PackedVector3Array:
	var out := PackedVector3Array()
	for i in mesh.get_surface_count():
		var arrays := ModelLibrary.ModelLods.arrays_of(mesh, i)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var index = arrays[Mesh.ARRAY_INDEX]
		if index is PackedInt32Array and not (index as PackedInt32Array).is_empty():
			for k in (index as PackedInt32Array):
				out.append(verts[k])
		else:
			out.append_array(verts)
	return out


static func _load_texture(file: String) -> Texture2D:
	var dir := SoundBank.data_dir()
	if dir == "":
		return null
	var path := dir.path_join(file)
	if not FileAccess.file_exists(path):
		return null
	var image := Image.load_from_file(path)
	if image == null:
		return null
	return ImageTexture.create_from_image(image)


func _free_nodes(st: TurretState) -> void:
	if st.light != null:
		st.light.queue_free()
	if st.beam != null:
		st.beam.queue_free()


## Forgets turrets that are gone (anim.gd's cleanup, by the world's entities and movers).
func forget(unit: int) -> void:
	var st: TurretState = _states.get(unit)
	if st != null:
		_free_nodes(st)
		_states.erase(unit)
