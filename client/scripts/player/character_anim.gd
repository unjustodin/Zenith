extends RefCounted
## The character's animations, Factorio's set and timing (base/prototypes/entity/
## character-animations.lua and the character prototype in entities.lua), posed on its skeleton
## (character_pose.gd):
##
## - idle: breathing, 22 frames at 0.15 a tick (2.4 s a breath);
## - running: legs and arms in step with the ground, one loop (two steps) per 22 frames x
##   distance_per_frame 0.13 / animation_speed 0.6 = 4.77 tiles (at running_speed 0.15 a tick
##   that's about 1.9 loops a second);
## - mining_with_tool: a pickaxe swung over the head, 26 frames at 0.9 (half a second a swing),
##   striking at frame 19;
## - running_with_gun and idle_with_gun: the gun held out towards the target while firing, at
##   the ready for a while after (ticks_to_stay_in_combat 600, ten seconds), the upper body
##   twisting towards the aim while the legs run, kicked back by each shot (kick());
## - crafting: hands busy in front while the crafting queue isn't empty (Factorio has no such
##   picture; a gentle stand-in so a long queue shows);
## - dead: falls on its back.
##
## Layers blend in and out over a fraction of a second, so changing state never snaps.

const CharacterPose := preload("res://scripts/player/character_pose.gd")

const IDLE_LOOP := 22.0 / (0.15 * 60.0)
## Tiles walked per run loop: Factorio advances a running animation animation_speed frames per
## distance_per_frame walked (UnitPrototype's frames = distance / distance_per_frame x
## animation_speed), so 22 frames x 0.13 / 0.6 for the character and / 0.37 for the mech's run
## (leaving animation_speed out ran the cycle 1.7 times too fast, flailing).
const RUN_LOOP := 22.0 * 0.13 / 0.6
const MECH_RUN_LOOP := 22.0 * 0.13 / 0.37
const MINE_LOOP := 26.0 / (0.9 * 60.0)
const MINE_STRIKE := 19.0 / 26.0
const COMBAT_SECONDS := 10.0
const FALL_SECONDS := 0.7
## How fast layers fade in and out (1 / seconds).
const BLEND_RATE := 9.0
## The furthest the upper body twists towards the aim before the legs turn too (radians).
const MAX_TWIST := 1.25

## Inputs, set by the avatar every frame.
var running := false
var mining := false
var aiming := false  # shooting at something
var firing := false  # shots going off
var aim_twist := 0.0  # radians from where the legs face to the aim, + to the left
var crafting := false
var dead := false
## In mech armour (Space Age's mech-armor animations): the right forearm is a gun and the left a
## claw, so no pickaxe or hand gun; a long, crouching stride; mining swings the claw.
var mech := false

## Outputs.
var pickaxe_shown := false
var gun_shown := false

var _t := 0.0
var _run_phase := 0.0
var _mine_clock := 0.0
var _combat := 0.0
var _fall := 0.0
var _w := {"run": 0.0, "mine": 0.0, "aim": 0.0, "ready": 0.0, "craft": 0.0}
var _twist := 0.0
var _recoil := 0.0
var _kick := 1.0
var _kicked := false  # shots come from the bridge (`shot`); before one has, kick on a beat


## `distance`: tiles walked this frame (+ forwards, - backwards).
func step(pose: CharacterPose, delta: float, distance: float) -> void:
	_t += delta
	_run_phase = fposmod(_run_phase + distance / (MECH_RUN_LOOP if mech else RUN_LOOP) * TAU, TAU)
	if aiming or firing:
		_combat = COMBAT_SECONDS
	else:
		_combat = maxf(0.0, _combat - delta)
	var k := 1.0 - exp(-delta * BLEND_RATE)
	_blend("run", 1.0 if running and not dead else 0.0, k)
	_blend("mine", 1.0 if mining and not running and not dead and not aiming else 0.0, k)
	_blend("aim", 1.0 if aiming and not dead else 0.0, k)
	_blend("ready", 1.0 if _combat > 0.0 and not aiming and not mining and not dead else 0.0, k)
	_blend("craft", 1.0 if crafting and not running and not mining and _combat <= 0.0 and not dead else 0.0, k)
	_twist = lerp_angle(_twist, clampf(aim_twist, -MAX_TWIST, MAX_TWIST) if aiming else 0.0, k)
	if _w["mine"] > 0.01:
		_mine_clock += delta
	else:
		_mine_clock = MINE_LOOP * 0.35  # start the next swing from the backswing
	_fall = move_toward(_fall, 1.0 if dead else 0.0, delta / FALL_SECONDS if dead else delta * 2.0)
	_recoil = maxf(0.0, _recoil - delta * 12.0)
	if firing and not _kicked and fmod(_t, 0.25) < delta:
		_recoil = 1.0
	pickaxe_shown = _w["mine"] > 0.3 and not mech
	gun_shown = (_w["aim"] + _w["ready"]) > 0.3 and _w["mine"] <= 0.3 and not mech

	pose.clear()
	var run: float = _w["run"]
	var action := clampf(_w["mine"] + _w["aim"] + _w["ready"] + _w["craft"], 0.0, 1.0)
	if mech:
		_mech_idle(pose, 1.0 - run, 1.0 - action)
		_mech_run(pose, run, 1.0 - action)
		if _w["mine"] > 0.0:
			_mech_mine(pose, _w["mine"], 1.0 - run)
		if _w["aim"] + _w["ready"] > 0.0:
			_mech_gun(pose, _w["aim"], _w["ready"])
	else:
		_idle(pose, 1.0 - run, 1.0 - action)
		_run(pose, run, 1.0 - action)
		if _w["mine"] > 0.0:
			_mine(pose, _w["mine"], 1.0 - run)
		if _w["aim"] > 0.0:
			_gun(pose, _w["aim"], true)
		if _w["ready"] > 0.0:
			_gun(pose, _w["ready"], false)
		if _w["craft"] > 0.0:
			_craft(pose, _w["craft"])
	if _fall > 0.0:
		_die(pose, _fall)
	pose.compute()


func _blend(layer: String, goal: float, k: float) -> void:
	var v: float = _w[layer]
	v += (goal - v) * k
	_w[layer] = 0.0 if v < 0.002 else v


## `body`: weight of the whole pose; `upper`: of the arms, spine and head (less while another
## layer uses them).
func _idle(pose: CharacterPose, body: float, upper: float) -> void:
	var b := sin(_t / IDLE_LOOP * TAU)
	var u := body * upper
	pose.root_offset.y += 0.006 * b * body
	pose.add("spine", Vector3(0.015 * b - 0.02, 0.0, 0.0), u)
	pose.add("head", Vector3(-0.02 * b, 0.03 * sin(_t / IDLE_LOOP * PI), 0.0), u)
	pose.add("upper_arm_r", Vector3(0.04, 0.0, 0.05 + 0.025 * b), u)
	pose.add("upper_arm_l", Vector3(0.04, 0.0, -0.05 - 0.025 * b), u)
	pose.add("forearm_r", Vector3(0.15 + 0.03 * b, 0.0, 0.0), u)
	pose.add("forearm_l", Vector3(0.15 + 0.03 * b, 0.0, 0.0), u)
	pose.add("shin_r", Vector3(-0.05, 0.0, 0.0), body)
	pose.add("thigh_r", Vector3(0.05, 0.0, 0.0), body)
	pose.add("shin_l", Vector3(-0.05, 0.0, 0.0), body)
	pose.add("thigh_l", Vector3(0.05, 0.0, 0.0), body)


func _run(pose: CharacterPose, w: float, upper: float) -> void:
	if w <= 0.0:
		return
	# Tuned against Factorio's running sprites (all 8 directions, 22 frames) by silhouette
	# overlap, tools/models/turntable_anim.py: the torso stays upright, the arms pump hard with
	# the elbows bent, the knees stay bent all the way round.
	var p := _run_phase
	var s := sin(p)
	# A leg swings forward (and its knee folds) while its thigh's angle grows: cos > 0 for the
	# right leg; the foot lands with the knee still a little bent.
	pose.add("thigh_r", Vector3(-0.03 + 0.9 * s, 0.0, 0.0), w)
	pose.add("thigh_l", Vector3(-0.03 - 0.9 * s, 0.0, 0.0), w)
	pose.add("shin_r", Vector3(-0.81 - 1.15 * pow(maxf(0.0, cos(p - 0.3)), 1.5), 0.0, 0.0), w)
	pose.add("shin_l", Vector3(-0.81 - 1.15 * pow(maxf(0.0, -cos(p - 0.3)), 1.5), 0.0, 0.0), w)
	# Lowest as a foot lands, highest pushing off: twice a loop.
	pose.root_offset.y += (-0.013 - 0.04 * cos(2.0 * p + 0.4)) * w
	pose.add("root", Vector3(0.0, -0.06 * s, 0.0), w)
	var u := w * upper
	# Each arm swings against its leg, a little after it.
	var a := sin(p + 0.6)
	pose.add("spine", Vector3(-0.02, 0.16 * s * upper, 0.0), w)
	pose.add("head", Vector3(-0.05, -0.1 * s, 0.0), w)
	pose.add("upper_arm_r", Vector3(-0.4 - 1.2 * a, 0.0, 0.12), u)
	pose.add("upper_arm_l", Vector3(-0.4 + 1.2 * a, 0.0, -0.12), u)
	pose.add("forearm_r", Vector3(1.35 - 0.6 * a, 0.0, 0.0), u)
	pose.add("forearm_l", Vector3(1.35 + 0.6 * a, 0.0, 0.0), u)


## Keyframes of a swing: [time 0-1, upper arm, forearm, spine lean, spine twist].
const SWING := [
	[0.0, 0.85, 0.15, -0.38, 0.12],
	[0.18, 1.05, 0.45, -0.3, 0.08],
	[0.52, 2.75, 1.55, 0.04, -0.22],
	[0.64, 2.9, 1.7, 0.06, -0.25],
	[MINE_STRIKE, 0.8, 0.1, -0.4, 0.14],
	[1.0, 0.85, 0.15, -0.38, 0.12],
]


func _mine(pose: CharacterPose, w: float, legs: float) -> void:
	var u := fposmod(_mine_clock / MINE_LOOP, 1.0)
	var k := 0
	while k < SWING.size() - 2 and u > float(SWING[k + 1][0]):
		k += 1
	var a: Array = SWING[k]
	var b: Array = SWING[k + 1]
	var f := clampf((u - float(a[0])) / maxf(float(b[0]) - float(a[0]), 0.001), 0.0, 1.0)
	f = f * f * (3.0 - 2.0 * f) if k != 3 else f * f  # the strike accelerates
	var arm := lerpf(float(a[1]), float(b[1]), f)
	var fore := lerpf(float(a[2]), float(b[2]), f)
	var lean := lerpf(float(a[3]), float(b[3]), f)
	var twist := lerpf(float(a[4]), float(b[4]), f)
	pose.add("upper_arm_r", Vector3(arm, 0.0, 0.18), w)
	pose.add("forearm_r", Vector3(fore, 0.0, 0.0), w)
	pose.add("upper_arm_l", Vector3(0.75 + 0.15 * lean, 0.0, -0.05), w)
	pose.add("forearm_l", Vector3(1.0, 0.0, 0.0), w)
	pose.add("spine", Vector3(lean, twist, 0.0), w)
	pose.add("head", Vector3(-0.1 - 0.3 * lean, -0.5 * twist, 0.0), w)
	# A wide stance, right foot forward.
	var l := w * legs
	pose.add("thigh_r", Vector3(0.38, 0.0, 0.06), l)
	pose.add("shin_r", Vector3(-0.42, 0.0, 0.0), l)
	pose.add("thigh_l", Vector3(-0.2, 0.0, -0.08), l)
	pose.add("shin_l", Vector3(-0.3, 0.0, 0.0), l)
	pose.root_offset.y += (-0.06 + 0.02 * lean) * l


## One shot going off: the gun kicks back, harder for heavy guns (`strength` about 0.5 to 1.6).
func kick(strength := 1.0) -> void:
	_kicked = true
	_recoil = 1.0
	_kick = strength


## The gun towards the target (`aimed`), or held across the chest at the ready.
func _gun(pose: CharacterPose, w: float, aimed: bool) -> void:
	var lift := 1.0 if aimed else 0.55
	var kick := 0.07 * _recoil * _kick if aimed else 0.0
	pose.add("upper_arm_r", Vector3(1.38 * lift - kick, 0.0, -0.12), w)
	pose.add("forearm_r", Vector3(0.2 + (1.0 - lift) * 1.2, 0.0, 0.0), w)
	pose.add("upper_arm_l", Vector3(1.2 * lift - kick, 0.25, 0.4), w)
	pose.add("forearm_l", Vector3(0.55 + (1.0 - lift) * 0.9, 0.0, 0.0), w)
	pose.add("spine", Vector3(-0.08 + 0.4 * kick, _twist * 0.75, 0.0), w)
	pose.add("head", Vector3(0.04, _twist * 0.25, 0.0), w)


func _craft(pose: CharacterPose, w: float) -> void:
	var c := sin(_t * TAU * 1.4)
	pose.add("upper_arm_r", Vector3(0.5, 0.0, -0.12), w)
	pose.add("upper_arm_l", Vector3(0.5, 0.0, 0.12), w)
	pose.add("forearm_r", Vector3(1.3 + 0.14 * c, 0.0, 0.0), w)
	pose.add("forearm_l", Vector3(1.3 - 0.14 * c, 0.0, 0.0), w)
	pose.add("spine", Vector3(-0.1, 0.0, 0.0), w)
	pose.add("head", Vector3(-0.3, 0.06 * sin(_t * 1.3), 0.0), w)


## Falls backwards about the heels, arms flung out, and lies on its back.
func _die(pose: CharacterPose, k: float) -> void:
	var f := k * k  # gravity
	var back := 1.42 * f
	pose.body_pivot = Vector3(0.0, 0.0, 0.18)
	pose.body_turn = Basis(Vector3.RIGHT, back)
	pose.root_offset.y += 0.32 * f
	var w := clampf(k * 1.5, 0.0, 1.0)
	pose.add("upper_arm_r", Vector3(0.9, 0.0, 1.0), w)
	pose.add("upper_arm_l", Vector3(0.5, 0.0, -1.2), w)
	pose.add("forearm_r", Vector3(0.6, 0.0, 0.0), w)
	pose.add("forearm_l", Vector3(0.3, 0.0, 0.0), w)
	pose.add("thigh_r", Vector3(0.45, 0.0, 0.1), w)
	pose.add("shin_r", Vector3(-0.6, 0.0, 0.0), w)
	pose.add("thigh_l", Vector3(0.15, 0.0, -0.15), w)
	pose.add("head", Vector3(0.25, 0.4, 0.0), w)


# --- Mech armour ------------------------------------------------------------------------------
# Space Age's mech-armor animations (mech-armor-animations.lua): the same character, its run
# loop by distance as before, but a crouching stride with the legs reaching far, the gun arm
# held up in front, and mining done with the claw (27 frames at 0.45, striking at frames 10 and
# 25). Poses fitted to mech-run's frames by silhouette (8 directions): the legs straight at the
# ends of a stride and both knees bent between, the body 0.2 tiles lower and leaning forward there.

const MECH_MINE_LOOP := 27.0 / (0.45 * 60.0)
const MECH_STRIKES := [10.0 / 27.0, 25.0 / 27.0]


func _mech_idle(pose: CharacterPose, body: float, upper: float) -> void:
	var b := sin(_t / IDLE_LOOP * TAU)
	pose.root_offset.y += 0.01 * b * body
	pose.add("spine", Vector3(0.012 * b, 0.0, 0.0), body * upper)
	pose.add("upper_arm_l", Vector3(0.03 * b, 0.0, 0.0), body * upper)


## Legs as mech_run_pose(); the whole layer weighted by `w`, the arms by `upper` too.
func _mech_run(pose: CharacterPose, w: float, upper: float) -> void:
	if w <= 0.0:
		return
	var turns := mech_run_pose(_run_phase)
	for bone in turns:
		var arm := str(bone).contains("arm")
		pose.add(str(bone), turns[bone], w * (upper if arm else 1.0))
	pose.root_offset.y += float(mech_run_drop(_run_phase)) * w


## The stride at run phase `p` (radians; the right leg furthest forward at PI / 2), as turns per
## bone. Static, so tools can pose the model the same way.
static func mech_run_pose(p: float) -> Dictionary:
	var s := sin(p)
	var c := cos(p)
	return {
		"root": Vector3(-0.05, 0.1 * s, 0.0),
		"spine": Vector3(-0.05 - 0.3 * c * c, -0.1 * s, 0.0),
		"thigh_r": Vector3(0.9 * s, 0.0, 0.0),
		"thigh_l": Vector3(-0.9 * s, 0.0, 0.0),
		"shin_r": Vector3(-0.45 * c * c, 0.0, 0.0),
		"shin_l": Vector3(-0.45 * c * c, 0.0, 0.0),
		"upper_arm_r": Vector3(0.5, 0.0, 0.0),
		"forearm_r": Vector3(-0.3, 0.0, 0.0),
		"upper_arm_l": Vector3(-0.2 + 0.42 * s, 0.0, 0.0),
		"forearm_l": Vector3(0.5, 0.0, 0.0),
	}


## How far the body sinks at run phase `p` (tiles, negative is down): most between strides.
static func mech_run_drop(p: float) -> float:
	return -0.17 - 0.05 * cos(2.0 * p)


func _mech_mine(pose: CharacterPose, w: float, legs: float) -> void:
	var u := fposmod(_mine_clock / MECH_MINE_LOOP, 1.0)
	# The claw rises after each strike and comes down on the next.
	var reach := 1.0
	for strike in MECH_STRIKES:
		reach = minf(reach, absf(u - float(strike)))
	reach = minf(reach, absf(u + 1.0 - float(MECH_STRIKES[0])))
	var up := smoothstep(0.0, 0.25, reach)
	pose.add("upper_arm_l", Vector3(-0.1 + 1.8 * up, 0.0, -0.3 * up), w)
	pose.add("forearm_l", Vector3(0.6 - 0.4 * up, 0.0, 0.0), w)
	pose.add("spine", Vector3(-0.25 + 0.15 * up, 0.15 * up, 0.0), w)
	var l := w * legs
	pose.add("thigh_r", Vector3(0.3, 0.0, 0.0), l)
	pose.add("shin_r", Vector3(-0.4, 0.0, 0.0), l)
	pose.add("thigh_l", Vector3(0.2, 0.0, 0.0), l)
	pose.add("shin_l", Vector3(-0.35, 0.0, 0.0), l)
	pose.root_offset.y += -0.1 * l


## The gun arm raised towards the target (`aim`), a little lower at the ready.
func _mech_gun(pose: CharacterPose, aim: float, ready: float) -> void:
	var kick := 0.06 * _recoil * aim
	pose.add("upper_arm_r", Vector3(0.3 - kick, 0.0, 0.0), aim)
	pose.add("upper_arm_r", Vector3(0.15, 0.0, 0.0), ready)
	pose.add("spine", Vector3(-0.05, _twist * 0.85, 0.0), aim)