extends Node
## `--fx-demo`: plays the character through a short script so sounds and effects can be checked
## without anyone at the keyboard (headless runs, screenshots). It sends the same commands as the
## player's input: walk east, mine the nearest tree or rock, build a furnace and an inserter,
## turn the inserter, shoot (`--fx-demo=space`: at enemies, as with Space; otherwise at a point
## beside the character, as with C), then mine the furnace back. At 11 s it also fakes a
## `died` for the nearest building, shown by fx.gd only (the building stays), to see an
## explosion. Times are seconds since the scene started, as for --screenshot.
##
## `--fx-demo=stress` goes on to a battle a big base might hear (fx.gd only, nothing changes in the
## game): from 15 s, every second for 10 s, 30 biters die at once round the character, 8 buildings
## explode and 12 shots ring out, to measure with `--sfx-log` that it neither clips nor stacks.

const WorldMirror := preload("res://scripts/world/world.gd")
const SoundBank := preload("res://scripts/fx/sound_bank.gd")

const REPEAT := 0.15

var fx: Node  # fx.gd
var space := false
var stress := false
var _volleys := 0

var _repeat := 0.0
var _mine_target: WorldMirror.Rec = null
var _looked := false
var _built := Vector2.ZERO
var _faked := false
var _rotated := false
var _built_furnace := false
var _built_inserter := false
var _stopped := false
var _start_msec := 0


func _ready() -> void:
	process_priority = 1  # after the player's input, which clears the aim every frame
	_start_msec = Time.get_ticks_msec()


func _process(delta: float) -> void:
	if not Bridge.world_ready or fx.avatar.unit == 0:
		return
	var t := (Time.get_ticks_msec() - _start_msec) / 1000.0
	var me: Vector2 = fx.avatar.ground_position()
	_repeat -= delta
	var tick := _repeat <= 0.0
	if tick:
		_repeat = REPEAT
	if t < 2.0:
		return
	if t < 4.0:
		if tick:
			Bridge.send({"t": "walk", "d": 4})
	elif t < 7.0:
		if not _looked:
			_looked = true
			Bridge.send({"t": "walk", "d": -1})
			_mine_target = _nearest(me, ["tree", "simple-entity", "resource"], 9.0)
			print("fx-demo: mining %s" % (fx.world.protos.entity(_mine_target.proto_id).name if _mine_target != null else "nothing in reach"))
		if tick and _mine_target != null:
			_send_target("mine", _mine_target)
	elif t < 8.5:
		if not _built_furnace:
			Bridge.send({"t": "mine_stop"})
			_built_furnace = true
			_built = (me + Vector2(2.0, 3.0)).floor() + Vector2(1.0, 1.0)
			Bridge.send({"t": "build", "item": "stone-furnace", "x": int(_built.x * 256), "y": int(_built.y * 256), "d": 0})
		elif t > 7.6 and not _built_inserter:
			_built_inserter = true
			var at := (me + Vector2(-2.0, 3.0)).floor() + Vector2(0.5, 0.5)
			Bridge.send({"t": "build", "item": "inserter", "x": int(at.x * 256), "y": int(at.y * 256), "d": 0})
		elif t > 8.2 and not _rotated:
			_rotated = true
			var ins := _nearest(me + Vector2(-2.0, 3.0), ["inserter"], 1.5)
			if ins != null:
				Bridge.send({"t": "rotate", "u": ins.unit, "p": ins.proto_id, "x": ins.fixed.x, "y": ins.fixed.y, "rev": 0})
	elif t < 11.0:
		var aim := me + Vector2(5.0, 2.0)
		fx.combat.aim_mode = 0 if space else 1
		fx.combat.aim = aim
		if tick:
			Bridge.send({"t": "shoot", "m": 0 if space else 1, "x": int(aim.x * 256), "y": int(aim.y * 256)})
	elif t < 14.0:
		if not _faked:
			_faked = true
			Bridge.send({"t": "shoot", "m": -1, "x": 0, "y": 0})
			var victim := _nearest(me, ["container", "furnace", "assembling-machine", "wall", "electric-pole", "inserter"], 14.0)
			if victim != null:
				print("fx-demo: %.2f s, faking a death for %s" % [t, fx.world.protos.entity(victim.proto_id).name])
				fx.handle({"t": "died", "u": victim.unit, "p": victim.proto_id, "x": victim.fixed.x, "y": victim.fixed.y})
		var furnace := _nearest(_built, ["furnace"], 1.0)
		if tick and furnace != null and t > 12.0:
			_send_target("mine", furnace)
	elif not _stopped:
		_stopped = true
		Bridge.send({"t": "mine_stop"})
		print("fx-demo: done")
	elif stress and t >= 15.0 + _volleys and _volleys < 10:
		_volleys += 1
		_battle(me)


## One volley of the stress test: deaths and shots in a single frame.
func _battle(me: Vector2) -> void:
	var biter: Variant = fx.world.protos.entities_by_name.get("small-biter")
	if biter != null:
		for i in 30:
			var at := me + Vector2.from_angle(randf() * TAU) * randf_range(3.0, 12.0)
			fx.handle({"t": "died", "u": 0, "p": biter.id, "x": int(at.x * 256), "y": int(at.y * 256)})
	var n := 0
	for r: WorldMirror.Rec in fx.world.entities.values():
		var proto = fx.world.protos.entity(r.proto_id)
		if proto != null and proto.type in ["container", "furnace", "assembling-machine", "inserter", "electric-pole"] and r.pos.distance_to(me) < 16.0:
			fx.handle({"t": "died", "u": r.unit, "p": r.proto_id, "x": r.fixed.x, "y": r.fixed.y})
			n += 1
			if n >= 8:
				break
	for i in 12:
		var at := me + Vector2.from_angle(randf() * TAU) * randf_range(1.0, 8.0)
		fx.sfx.play_at(SoundBank.pick("base/sound/fight/submachine-gunshot"), Vector3(at.x, 1.0, at.y), 0.55, 0.05, 1.0, "Weapons")
	print("fx-demo: volley %d: 30 biters, %d buildings, 12 shots" % [_volleys, n])


func _send_target(kind: String, r: WorldMirror.Rec) -> void:
	Bridge.send({"t": kind, "u": r.unit, "p": r.proto_id, "x": r.fixed.x, "y": r.fixed.y})


func _nearest(from: Vector2, types: Array, max_distance: float) -> WorldMirror.Rec:
	var best: WorldMirror.Rec = null
	var best_d := max_distance
	for r: WorldMirror.Rec in fx.world.entities.values():
		var d := r.pos.distance_to(from)
		if d >= best_d:
			continue
		var proto = fx.world.protos.entity(r.proto_id)
		if proto != null and proto.type in types:
			best = r
			best_d = d
	return best
