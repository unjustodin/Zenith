extends Node
## `--weapons-demo`: fires each of the character's three guns in turn at a point beside it, then
## throws a grenade and a poison capsule, sending the same commands as the player's input, and
## prints what weapon_fx.gd is drawing at each step. For headless checks and screenshots against
## the mock (`tools/mock_server.py --guns shotgun,rocket-launcher,flamethrower`) or a real server.
## Times are seconds since the world was ready, as for --screenshot (which counts from the start).

const REPEAT := 0.15
const STEP := 3.0
const AIM := Vector2(7.0, 1.5)

var fx: Node  # fx.gd

var _start_msec := -1
var _repeat := 0.0
var _step := -1
var _most := {}  # step -> [flying, beams, ground, cards] at most during it


func _ready() -> void:
	process_priority = 1  # after the player's input, which clears the aim every frame


func _process(delta: float) -> void:
	if not Bridge.world_ready or fx.avatar.unit == 0:
		return
	if _start_msec < 0:
		_start_msec = Time.get_ticks_msec()
	var t := (Time.get_ticks_msec() - _start_msec) / 1000.0 - 1.0
	if t < 0.0:
		return
	var step := int(t / STEP)
	var into := fmod(t, STEP)
	if step != _step:
		if _step >= 0:
			print("weapons-demo: step %d drew at most %s (flying, beams, fires/clouds, effect cards), played %s" % [_step, _most.get(_step, []), fx.weapons.played])
			fx.weapons.played.clear()
		_step = step
		_begin(step)
	var w: Node = fx.weapons
	var now := [w.flying_count(), w.beam_count(), w.ground_count(), fx.sprites.count()]
	var most: Array = _most.get(step, [0, 0, 0, 0])
	for i in 4:
		most[i] = maxi(most[i], now[i])
	_most[step] = most
	var me: Vector2 = fx.avatar.ground_position()
	_repeat -= delta
	if step < 3 and into < 1.6:
		var aim := me + AIM
		fx.combat.aim_mode = 1
		fx.combat.aim = aim
		if _repeat <= 0.0:
			_repeat = REPEAT
			Bridge.send({"t": "shoot", "m": 1, "x": int(aim.x * 256), "y": int(aim.y * 256)})


func _begin(step: int) -> void:
	var me: Vector2 = fx.avatar.ground_position()
	Bridge.send({"t": "shoot", "m": -1, "x": 0, "y": 0})
	if step < 3:
		Bridge.send({"t": "gun", "i": step + 1})
		print("weapons-demo: gun slot %d" % (step + 1))
	elif step == 3:
		var at := me + Vector2(6.0, -2.0)
		Bridge.send({"t": "throw", "item": "grenade", "x": int(at.x * 256), "y": int(at.y * 256)})
		print("weapons-demo: grenade")
	elif step == 4:
		var at := me + Vector2(-6.0, 2.0)
		Bridge.send({"t": "throw", "item": "poison-capsule", "x": int(at.x * 256), "y": int(at.y * 256)})
		print("weapons-demo: poison capsule")
	elif step == 5:
		print("weapons-demo: done")
