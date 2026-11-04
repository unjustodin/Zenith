extends Node
## Moves the factory between chunk rebuilds, like Factorio's animations. chunk_view.gd draws
## each model's moving parts (model_library.gd, `anim_*` nodes) as their own MultiMesh and hands
## them over as Groups, with the glowing models' instances.
##
## Most of it is done by the model shader (factorio_material.gdshaderinc, anim_mode) from each
## instance's state in its custom data, which this writes only when that state changes, never
## per frame:
##
## - spinning parts (drill heads, assembler arms, steam engine flywheels) turn while the mod
##   reports the machine working (`st`, world.working), spinning up and coasting to a stop;
## - glowing surfaces (furnace fire, `anim_glow_*` parts) fade in and out with the working
##   state (activity_glow);
## - cycling parts (ModelLibrary.CYCLES: pistons, crusher jaws) slide or swing once per loop of
##   Factorio's animation while the machine works;
## - rocking parts (the pumpjack's beam) see-saw with their model's crank;
## - pistons (`bob_*`) go up and down in their windows while a pump works, and the power switch's
##   core (`switch`) slides in while it's on;
## - lights (`lit_*` parts) show, lit, while the entity's reported state is one of LIT_STATES:
##   rail and chain signals' lamps by colour, accumulators' glow while charging or discharging,
##   lightning rods and collectors when a strike lands on them (`lt`, strike());
## - hatches (ModelLibrary.HATCHES: the rocket silo's doors, cargo hatches) slide open while a
##   rocket or cargo pod is at the entity (movers.gd), a client-side guess; roboport hatch doors
##   (`door_n`, `door_s`) open and its charging points (`charge`) light up while a robot flies
##   within a few tiles, and a logistic chest's hatch (`hatch_e`, `hatch_w`) while a robot hovers
##   over it (also guesses: the mod doesn't send door states); gate doors sink into the ground
##   while the character or a friendly vehicle is close (Factorio opens them for its own force).
##   Those near the camera are looked for here a few times a second; the shader moves them.
##
## What needs the game's state every frame stays here, in the chunks near the camera:
##
## - turret heads turn, raise, fold and fire as the mod's turret states say (turrets.gd);
## - the asteroid collector's arm (`reach_collector_*`) reaches for asteroid chunks, catches them
##   and pulls them in (collectors.gd);
## - worms attack what the mod says they shoot at (`en`, through creatures.gd), turned its way,
##   and stay up a while after; they rise while the character is within their prepare range
##   (Factorio raises them for any enemy in range, which the mod doesn't send). With a mod
##   without `en`, they attack the character within their range.
##
## `still` parts are only separate so they can stay upright (model_library.gd, UPRIGHT_PREFIX) and
## don't move. Belts move in the shader alone (belt_speed), and inserter arms in inserter_arms.gd.
##
## The shader's clock (f3d_anim_time) is this node's time since the start of its latest even and
## odd EPOCH, so it stays small and precise in a long game; each new epoch every state is moved
## onto it, a few groups a frame, before the older clock starts again.

const ModelLibrary := preload("res://scripts/world/model_library.gd")

## Entity types the mod reports working states for (ANIMATED_TYPES in the mod's registry.lua).
## Others (turrets, chests) count as always working for their glow.
const STATE_TYPES := {
	"assembling-machine": true, "furnace": true, "mining-drill": true, "lab": true, "boiler": true,
	"generator": true, "reactor": true, "radar": true, "rocket-silo": true, "pump": true,
	"offshore-pump": true, "beacon": true, "burner-generator": true, "fusion-reactor": true,
	"fusion-generator": true, "agricultural-tower": true, "asteroid-collector": true, "lamp": true,
	"thruster": true, "rail-signal": true, "rail-chain-signal": true, "accumulator": true,
	"power-switch": true,
}
## Chunks whose nearest edge is within this many tiles of the camera's focus have their turrets,
## collectors, worms, hatches, doors and gates looked after.
const RADIUS := 40.0
## Parts of an asteroid collector's arm (collectors.gd moves them).
const COLLECTOR_PREFIX := "reach_collector_"
## Full speed by part kind, turns per second, close to Factorio's animation loops (an electric
## mining drill's 30 frames at 0.4 take 1.25 s; an assembler's 64 frames about a second; a steam
## engine's 32 frames about half a second).
const SPIN_SPEEDS := {"spin_drill": 0.45, "spin_arms": 0.3, "spin_flywheel": 1.6, "spin_flywheel_ns": 1.6, "spin_crank": 0.75, "spin_radar": 0.6}
## Rocking parts (`rock_*`, the pumpjack's walking beam) follow the model's crank: this many
## radians either way, in step with ROCK_DRIVER's turn.
const ROCK_AMPLITUDE := 0.2
const ROCK_DRIVER := "spin_crank"
## The agricultural tower's crane swings slowly round while the tower works (m-space2); a
## splitter's gear wheels turn about once per two loops of its 32-frame structure (a guess at the
## gears' turn from the sprite, at yellow speed).
const SPIN_SPEEDS_EXTRA := {"spin_crane": 0.04, "spin_turbine_pad": 0.09, "spin_turbine_fan": 0.23, "spin_gear": 60.0 / 64.0}
## Models whose parts move whether or not the mod reports them working (Factorio runs their
## animation all the time): the landing pad's turbine.
const ALWAYS_MOVING := {"cargo-landing-pad": true}
## Overrides by model name.
const MODEL_SPEEDS := {"burner-mining-drill": 0.9, "burner-mining-drill-east": 0.9, "burner-mining-drill-south": 0.9,
	"burner-mining-drill-west": 0.9}
## Parts that move whenever the entity is drawn: a splitter's gear wheels, cranks and rack, as
## its structure animates with the belt, which always runs; a fish's tail.
const ALWAYS_ON := {"spin_gear": true, "crank_split_wa": true, "crank_split_wb": true, "crank_split_ea": true,
	"crank_split_eb": true, "slide_split_rack": true, "tail_fish": true}
const DEFAULT_SPIN := 0.5
## Seconds to get about two thirds of the way to full speed, or to a stop (the shader's ANIM_*).
const SPIN_UP := 0.35
const SPIN_DOWN := 0.9
const GLOW_UP := 0.25
const GLOW_DOWN := 0.9
const TURRET_LOOK := 0.15  # seconds between looking for a robot near a roboport
const CLEANUP_INTERVAL := 5.0
## Roboports: doors open (slide this many tiles) while a robot is this close; how fast they move.
const DOOR_TRAVEL := 0.5
const DOOR_SPEED := 1.2
const ROBOT_NEAR := 3.0
const ROBOPORT_KINDS := {"door_n": true, "door_s": true, "charge": true, "hatch_e": true, "hatch_w": true}
## How far each door kind opens ("angle" units of its slide, model_library.gd SLIDE_KINDS).
const DOOR_OPEN := {"door_n": DOOR_TRAVEL, "door_s": DOOR_TRAVEL, "hatch_e": 1.0, "hatch_w": 1.0}
## A logistic chest's hatch opens for a robot this close; Factorio's robot_door is 7 frames, so
## it snaps open.
const HATCH_NEAR := 1.2
const HATCH_SPEED := 6.0
## Roboport charging points light up and go out at this much a second.
const CHARGE_SPEED := 4.0
## Lit parts: the reported states (`st`) that show them. Signals: 1 green, 2 yellow, 3 red, 4 blue;
## accumulators: 1 charging, 2 discharging. `lit_strike` lights from strikes instead.
const LIT_STATES := {"lit_green": [1], "lit_yellow": [2], "lit_red": [3], "lit_blue": [4],
	"lit_charge": [1], "lit_discharge": [2], "lit_strike": []}
## Lit parts that flicker, like Factorio's arcs on accumulators and lightning attractors.
const FLICKER := {"lit_charge": true, "lit_discharge": true, "lit_strike": true}
## A lightning attractor's glow after a strike: up over its charge animation (24 frames), then
## fading as it discharges, seconds (the shader's ANIM_STRIKE_*).
const STRIKE_RISE := 0.4
const STRIKE_FADE := 2.5
const STRIKE_REACH := 1.5  # tiles between a strike's point and the attractor it lights
const STRIKE_GONE := 4.0  # seconds after which a strike's glow is under the shader's 0.02
## Pistons (`bob_*`) while working, cycles a second: a pump's 32 frames at 0.5, an offshore
## pump's at 0.25. `bob_b` runs half a cycle behind `bob_a`.
const BOB_SPEEDS := {"pump": 60.0 / 64.0, "offshore-pump": 60.0 / 128.0, "offshore-pump-east": 60.0 / 128.0,
	"offshore-pump-south": 60.0 / 128.0, "offshore-pump-west": 60.0 / 128.0}
const BOB_PHASE := {"bob_a": 0.0, "bob_b": PI}
## The power switch's core slides in over its power_on_animation: 6 frames at 0.2, half a second.
const SWITCH_SPEED := 2.0
## Worms (Factorio's enemy-constants.lua), by size: [range, range + prepare_range] in tiles.
## The family's model is scaled per tier, so its height tells the tier.
const WORM_RANGES := [[0.75, 25.0, 33.0], [0.9, 30.0, 46.0], [1.1, 38.0, 62.0], [9.0, 48.0, 84.0]]
## Seconds each change of state takes: 1 / speed ticks (the speeds are progress per tick):
## preparing 0.024, folding 0.015, starting attack 0.034, ending attack 0.016.
const WORM_RISE := 1.0 / 0.024 / 60.0
const WORM_FOLD := 1.0 / 0.015 / 60.0
const WORM_START_ATTACK := 1.0 / 0.034 / 60.0
const WORM_END_ATTACK := 1.0 / 0.016 / 60.0
## Seconds a worm stays prepared after its last attack before folding (its target is still in
## its prepare range as far as anyone can tell).
const WORM_HOLD := 6.0
const WORM_TURN := 8.0  # radians a second (Factorio's worms turn almost at once)
## Gates: Factorio's opening_speed (0.0667 a tick, a quarter second), and how close something
## must be to open one (tiles from the gate's centre).
const GATE_SPEED := 0.0666666 * 60.0
const GATE_REACH := 2.5
const GATE_VEHICLE_REACH := 4.0

## How the shader moves a part (factorio_material.gdshaderinc anim_mode). NONE: turned here
## (turret heads, collectors' arms) or not at all.
const MOTION_NONE := 0
const MOTION_SPIN := 1
const MOTION_CYCLE := 2
const MOTION_ROCK := 3
const MOTION_BOB := 4
const MOTION_LIT := 5
const MOTION_LINEAR := 6
const MOTION_FADE := 7
const WAVES := {"out": 0, "swing": 1, "spin": 2}
## What this node does with a Group (Group.kind).
const KIND_GLOW := 0  # a glowing model's instances: written when the working state changes
const KIND_WORM := 1  # turned and raised here every frame
const KIND_TURRET := 2  # turrets.gd, every frame
const KIND_COLLECTOR := 3  # collectors.gd, every frame
const KIND_STILL := 4  # never moves
const KIND_TIMED := 5  # spinning, cycling, rocking, pistons: written when the working state changes
const KIND_LIT := 6  # written when the state changes or lightning strikes
const KIND_SWITCH := 7  # written when the state changes
const KIND_HATCH := 8  # looked for pods and rockets near, written when that changes
const KIND_ROBOPORT := 9  # looked for robots near
const KIND_GATE := 10  # looked for the character and vehicles near
## world.prof keys for the script time each kind of group takes a frame (--stutter-probe shows them as w_<key>).
const PROF_KEYS := {KIND_WORM: "anim_worms", KIND_TURRET: "anim_turrets", KIND_COLLECTOR: "anim_collectors",
	KIND_HATCH: "anim_near", KIND_ROBOPORT: "anim_near", KIND_GATE: "anim_near"}
## Seconds of each of the shader's two clocks before it starts again (f3d_anim_time). Float
## precision over twice this is about 0.25 ms.
const EPOCH := 1800.0
## Microseconds a frame spent moving states onto a new epoch's clock.
const MIGRATE_USEC := 300


## One MultiMesh this animates: a moving part's instances (`part`), or a glowing model's
## static instances (part null). Index i is the i-th entity in every array.
class Group:
	var mm: MultiMesh
	var part: ModelLibrary.AnimPart
	var keys: Array = []
	var units := PackedInt64Array()
	var bases: Array[Transform3D] = []
	var stateful := PackedByteArray()  # 1 where the entity reports a working state
	## Each instance's custom data as last set, so nothing reads it back from the RenderingServer
	## (a wait for the render thread when it runs on its own).
	var customs := PackedColorArray()
	var kind := -1  # KIND_*
	var epoch := -1  # the clock epoch all its instances were last written on
	var look := 0.0  # near-checked groups: seconds to the next look (each group on its own beat)
	var drawn: Array[Transform3D] = []  # turret heads, collectors' arms: each instance's transform as last set
	var _index := {}  # entity key -> instance index, or an Array of them (indices_of)

	## The instances of an entity in this group (cargo bays' pieces put one entity in several).
	func indices_of(key) -> Array:
		if _index.is_empty() and not keys.is_empty():
			for i in keys.size():
				var k = keys[i]
				var prev = _index.get(k)
				if prev == null:
					_index[k] = i
				elif prev is Array:
					prev.append(i)
				else:
					_index[k] = [prev, i]
		var found = _index.get(key)
		if found == null:
			return []
		return found if found is Array else [found]


## An entity's state. Its parts' motion and its glow: what they ease towards (`on`, `glowing`),
## and where they were when that last changed (`at`), which the shader works on from.
class State:
	var started := false  # the motion and glow below are set
	var always := false  # parts that move whether or not it works (ALWAYS_ON, ALWAYS_MOVING)
	var stateful := true
	var on := false
	var glowing := false
	var at := 0.0  # the animator's time of the last change
	var speed := 0.0  # 0 (still) to 1 (full speed), then
	var dist := 0.0  # seconds at full speed it had moved by then (each part's loops: rate * dist)
	var glow := 0.0  # 0 to 1, then
	var lin := {}  # linear part kind -> [at, amount then, open]
	var strike_at := -1e9  # lit_strike parts: when the last strike landed
	var target = null  # whether a robot (a gate: a friendly vehicle or robot) was near at the last look
	var looked := -1e9  # when that was: a roboport's three parts and a chest's two hatch halves share it
	var activity := -1.0  # a worm: folded 0, prepared 1, attacking 2; -1 until drawn
	var idle_timer := 0.0  # a worm: seconds it stays prepared after its last attack (WORM_HOLD)
	var yaw := 0.0  # a worm's turn towards its target

	func speed_at(t: float) -> float:
		var goal := 1.0 if on else 0.0
		return goal + (speed - goal) * exp(-(t - at) / (SPIN_UP if on else SPIN_DOWN))

	func dist_at(t: float) -> float:
		var goal := 1.0 if on else 0.0
		var tau := SPIN_UP if on else SPIN_DOWN
		return dist + goal * (t - at) + (speed - goal) * tau * (1.0 - exp(-(t - at) / tau))

	func glow_at(t: float) -> float:
		var goal := 1.0 if glowing else 0.0
		return goal + (glow - goal) * exp(-(t - at) / (GLOW_UP if glowing else GLOW_DOWN))

	## The same motion and glow from `t` on, aiming at `on_now` and `glowing_now` from then.
	func change(t: float, on_now: bool, glowing_now: bool) -> void:
		dist = dist_at(t)
		speed = speed_at(t)
		glow = glow_at(t)
		at = t
		on = on_now
		glowing = glowing_now

	## Whether it has never moved: its parts are at rest as modelled (no loop phase yet).
	func at_rest() -> bool:
		return dist == 0.0 and speed == 0.0 and not on


## The world mirror (world.gd): chunks, entities, working states and the focus.
var world: Node
## movers.gd, for roboports and gates; found as the world's sibling "Movers" when not set.
var movers: Node
## turrets.gd: turret heads turn, raise and fire from the mod's turret states (main.gd sets it).
var turrets: Node
## collectors.gd: asteroid collectors' arms (main.gd sets it).
var collectors: Node
## Instances' states written (place, state changes, migration) and the microseconds that took,
## for probes and tests.
var writes := 0
var write_usec := 0

var _states := {}  # entity key -> State
var _time := 0.0
var _epoch := 0
var _migrate: Array = []  # chunk coords whose groups still need moving onto the current clock
var _cleanup_timer := 0.0
## --worm-state=<0|1|2>: every worm folded, prepared or attacking (for looking at them).
var _worm_override := -1.0


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--worm-state="):
			_worm_override = float(arg.get_slice("=", 1))
	_update_clock()


static func has_state(proto_type: String) -> bool:
	return STATE_TYPES.has(proto_type)


## A moving part's or glowing model's custom data as the parts this node turns read it: the
## entity's position (x, z), its direction (0-3: north, east, south, west) and how much it glows.
static func custom_for(rec, level: float) -> Color:
	return Color(rec.pos.x, rec.pos.y, float(posmod(int(round(rec.dir / 4.0)), 4)), level)


func reset() -> void:
	_states.clear()
	_migrate.clear()


## The clock time now (seconds since this node started).
func now() -> float:
	return _time


## What this node does with a group (KIND_*).
static func kind_of(group: Group) -> int:
	var part := group.part
	if part == null:
		return KIND_WORM if _is_worm(group) else KIND_GLOW
	var kind := part.kind
	if kind == "turret_head":
		return KIND_TURRET
	if kind == "still":
		return KIND_STILL
	if kind.begins_with(COLLECTOR_PREFIX):
		return KIND_COLLECTOR
	if ModelLibrary.CYCLES.has(kind):
		return KIND_TIMED
	if ModelLibrary.HATCHES.has(kind):
		return KIND_HATCH
	if kind.begins_with("rock_"):
		return KIND_TIMED
	if ROBOPORT_KINDS.has(kind):
		return KIND_ROBOPORT
	if kind == "gate_door":
		return KIND_GATE
	if part.lit:
		return KIND_LIT
	if BOB_PHASE.has(kind):
		return KIND_TIMED
	if kind == "switch":
		return KIND_SWITCH
	return KIND_TIMED  # spinning


## A part's motion for the shader, once per part (parts are shared by every chunk drawing the
## model): AnimPart.motion, rate and phase (for linear parts: amount a second and when open), its
## materials' anim_* uniforms, and its mesh's bounds over the whole motion so it isn't culled.
static func setup_part(part: ModelLibrary.AnimPart) -> void:
	if part == null or part.motion >= 0:
		return
	var kind := part.kind
	var motion := MOTION_NONE
	var wave := 0
	var amount := 1.0
	var speed := 0.0
	var open := 1.0
	var range_lo := 0.0
	var range_hi := 0.0
	var fake := Group.new()
	fake.part = part
	match kind_of(fake):
		KIND_TIMED:
			if ModelLibrary.CYCLES.has(kind):
				var c: Dictionary = ModelLibrary.CYCLES[kind]
				motion = MOTION_CYCLE
				part.rate = 1.0 / float(c.get("period", 1.0))
				part.phase = float(c.get("phase", 0.0))
				wave = int(WAVES.get(c.get("wave", "out"), 0))
				amount = float(c.get("angle", 1.0))
				range_lo = -amount if wave == 1 else 0.0
				range_hi = amount
			elif kind.begins_with("rock_"):
				motion = MOTION_ROCK
				part.rate = -_turns(part.model, ROCK_DRIVER)
				amount = ROCK_AMPLITUDE
				range_lo = -amount
				range_hi = amount
			elif BOB_PHASE.has(kind):
				motion = MOTION_BOB
				part.rate = float(BOB_SPEEDS.get(part.model, 1.0))
				part.phase = float(BOB_PHASE[kind]) / TAU
				range_hi = 1.0
			else:
				# Clockwise seen from above (or from the east, for flywheels), as Factorio's turn.
				motion = MOTION_SPIN
				part.rate = -_turns(part.model, kind)
				range_hi = TAU
		KIND_LIT:
			motion = MOTION_LIT
		KIND_SWITCH:
			motion = MOTION_LINEAR
			speed = SWITCH_SPEED
		KIND_HATCH:
			var h: Dictionary = ModelLibrary.HATCHES[kind]
			motion = MOTION_LINEAR
			speed = 1.0 / float(h.get("time", 1.0))
			amount = float(h.get("angle", 1.0))
		KIND_ROBOPORT:
			motion = MOTION_FADE if kind == "charge" else MOTION_LINEAR
			speed = CHARGE_SPEED if kind == "charge" else (HATCH_SPEED if kind.begins_with("hatch_") else DOOR_SPEED)
			open = float(DOOR_OPEN.get(kind, 1.0))
		KIND_GATE:
			motion = MOTION_LINEAR
			speed = GATE_SPEED
	if motion == MOTION_LINEAR or motion == MOTION_FADE:
		part.rate = speed
		part.phase = open
		range_hi = open * amount if motion == MOTION_LINEAR else 0.0
	part.motion = motion
	if motion == MOTION_NONE or part.mesh == null:
		return
	var axis := part.axis.normalized() if part.axis != Vector3.ZERO else Vector3.UP
	for i in part.mesh.get_surface_count():
		var m := part.mesh.surface_get_material(i) as ShaderMaterial
		if m == null:
			continue
		m.set_shader_parameter("anim_mode", motion)
		m.set_shader_parameter("anim_wave", wave)
		m.set_shader_parameter("anim_rate", part.rate if motion < MOTION_LIT else 0.0)
		m.set_shader_parameter("anim_amount", amount)
		m.set_shader_parameter("anim_slide", part.slide)
		m.set_shader_parameter("anim_axis", axis)
		m.set_shader_parameter("anim_pivot", Projection(part.pivot))
		m.set_shader_parameter("anim_unpivot", Projection(part.pivot.affine_inverse()))
		m.set_shader_parameter("anim_speed", speed)
		m.set_shader_parameter("anim_open", open)
		m.set_shader_parameter("anim_flicker", FLICKER.has(kind))
		m.set_shader_parameter("anim_strike", kind == "lit_strike")
	if range_hi > range_lo and part.mesh is ArrayMesh:
		var rest := part.mesh.get_aabb()
		var box := rest
		var steps := 16 if motion == MOTION_SPIN or wave == 2 else 8
		for s in steps + 1:
			box = box.merge(part.turned(lerpf(range_lo, range_hi, float(s) / steps)) * rest)
		(part.mesh as ArrayMesh).custom_aabb = box.grow(0.05)


## Turns a second at full speed of a spinning part kind on a model.
static func _turns(model: String, kind: String) -> float:
	return float(MODEL_SPEEDS.get(model, SPIN_SPEEDS.get(kind, SPIN_SPEEDS_EXTRA.get(kind, DEFAULT_SPIN))))


## Draws a new group's instances where their entities' states have them now (chunk_view.gd, after
## filling its MultiMesh with the entities' transforms and `customs` with custom_for's). Without an
## animator they stay at rest.
static func place(group: Group, anim: Node, working: Dictionary) -> void:
	setup_part(group.part)
	group.kind = kind_of(group)
	group.look = randf() * TURRET_LOOK  # a new chunk's groups look on different frames
	if group.part != null and group.part.upright:
		for i in group.bases.size():
			group.mm.set_instance_transform(i, group.bases[i])
	if anim != null:
		anim._place(group, working)
		return
	# Nothing moves them: at rest, lit parts hidden (custom_for's data, as parts turned on the CPU read it).
	for i in group.keys.size():
		if group.part != null and group.part.lit:
			group.mm.set_instance_transform(i, group.bases[i] * ModelLibrary.HIDDEN)
		group.mm.set_instance_custom_data(i, group.customs[i])


func _place(group: Group, working: Dictionary) -> void:
	var t0 := Time.get_ticks_usec()
	group.epoch = _epoch
	match group.kind:
		KIND_WORM, KIND_TURRET, KIND_COLLECTOR, KIND_STILL:
			for i in group.keys.size():
				var custom := group.customs[i]
				var st: State = _states.get(group.keys[i])
				if group.kind == KIND_WORM:
					custom.a = st.activity if st != null and st.activity >= 0.0 else 1.0
				elif group.stateful[i] == 1 and st != null and st.started:
					custom.a = st.glow_at(_time)
				elif group.stateful[i] == 1:
					custom.a = 1.0 if int(working.get(group.units[i], 0)) == 1 else 0.0
				group.customs[i] = custom
				group.mm.set_instance_custom_data(i, custom)
		_:
			for i in group.keys.size():
				_write(group, i, working)
	write_usec += Time.get_ticks_usec() - t0


## Writes instance i's custom data from its entity's state now (a timed group's).
func _write(group: Group, i: int, working: Dictionary) -> void:
	var part := group.part
	var key = group.keys[i]
	var unit := int(group.units[i])
	var start := _epoch * EPOCH
	var parity := 2 if _epoch % 2 == 1 else 0
	var custom: Color
	match group.kind:
		KIND_GLOW, KIND_TIMED:
			var always := part != null and (ALWAYS_ON.has(part.kind) or ALWAYS_MOVING.has(part.model))
			var st := _motion(key, unit, always, group.stateful[i] == 1, working)
			if st.at < start:
				st.change(start, st.on, st.glowing)  # the same motion, on the current clock
			var loops := 0.0
			if part != null and not st.at_rest():
				var scatter := 0.0
				if ModelLibrary.CYCLES.has(part.kind) and ModelLibrary.CYCLES[part.kind].get("scatter", false):
					scatter = float(hash(key) & 0xff) / 256.0  # starts out of step
				loops = fposmod(part.rate * st.dist + part.phase + scatter, 1.0)
			var flags := (1 if st.on else 0) + parity + (4 if st.glowing else 0)
			custom = Color(st.at - start, loops, -(1.0 + flags + minf(st.speed, 0.999)), st.glow)
		KIND_LIT:
			var st := _state(key)
			var shown: bool
			var t := 0.0
			if part.kind == "lit_strike":
				shown = _time - st.strike_at < STRIKE_GONE
				t = st.strike_at - start if shown else 0.0
			else:
				shown = (LIT_STATES.get(part.kind, []) as Array).has(int(working.get(unit, 0)))
			custom = Color(t, 0.0, -(1.0 + (1 if shown else 0) + parity), 1.0)
		_:  # linear: switches (open while on), hatches, doors, gates, charging lights
			var st := _state(key)
			var l: Array = _linear(st, part, group.kind == KIND_SWITCH, int(working.get(unit, 0)) == 1)
			if float(l[0]) < start:
				l = [start, _amount(l, part, start), l[2]]
				st.lin[part.kind] = l
			var glowing := group.stateful[i] == 0 or int(working.get(unit, 0)) == 1
			custom = Color(float(l[0]) - start, float(l[1]), -(1.0 + (1 if l[2] else 0) + parity + (4 if glowing else 0)),
				1.0 if glowing else 0.0)
	group.customs[i] = custom
	group.mm.set_instance_custom_data(i, custom)
	writes += 1


func _state(key) -> State:
	var st: State = _states.get(key)
	if st == null:
		st = State.new()
		_states[key] = st
	return st


## An entity's motion and glow, aimed at its working state now (eased on from where they were
## when that changed). Seen for the first time, its parts start from rest and its glow at its goal.
func _motion(key, unit: int, always: bool, stateful: bool, working: Dictionary) -> State:
	var st := _state(key)
	var state := int(working.get(unit, 0))
	if not st.started:
		st.started = true
		st.always = always
		st.stateful = stateful
		st.at = _time
		st.on = always or state == 1
		st.glowing = not stateful or state == 1
		st.glow = 1.0 if st.glowing else 0.0
		return st
	st.always = st.always or always
	var on := st.always or state == 1
	var glowing := not st.stateful or state == 1
	if on != st.on or glowing != st.glowing:
		st.change(_time, on, glowing)
	return st


## A linear part's [at, amount then, open], opening or closing from where it is now when `open`
## differs (with `apply`); new ones start shut.
func _linear(st: State, part: ModelLibrary.AnimPart, apply: bool, open: bool) -> Array:
	var l: Array = st.lin.get(part.kind, [])
	if l.is_empty():
		l = [_time, 0.0, false]
		st.lin[part.kind] = l
	if apply and bool(l[2]) != open:
		l = [_time, _amount(l, part, _time), open]
		st.lin[part.kind] = l
	return l


## How far open a linear part is at time t (AnimPart.rate: amount a second; phase: when open).
static func _amount(l: Array, part: ModelLibrary.AnimPart, t: float) -> float:
	return move_toward(float(l[1]), part.phase if l[2] else 0.0, part.rate * (t - float(l[0])))


## The mod reported a new working state for an entity (world.gd `st`): its parts and glow ease
## towards it in the shader from now.
func state_changed(rec) -> void:
	if world == null or rec == null:
		return
	var cv = world.chunks.get(rec.chunk)
	if cv == null or cv.anim_groups.is_empty():
		return
	var t0 := Time.get_ticks_usec()
	var working: Dictionary = world.working
	for group: Group in cv.anim_groups:
		if group.kind == KIND_GLOW or group.kind == KIND_TIMED or group.kind == KIND_LIT or group.kind == KIND_SWITCH:
			for i in group.indices_of(rec.key):
				_write(group, i, working)
	var spent := Time.get_ticks_usec() - t0
	write_usec += spent
	if "prof" in world:
		world.prof["anim_states"] = int(world.prof.get("anim_states", 0)) + spent


## A lightning strike landed (ui_model.gd lightning_struck): attractors there light up.
func strike(at: Vector2, caught := true) -> void:
	if not caught or world == null:
		return
	var c := Vector2i(floori(at.x / 32.0), floori(at.y / 32.0))
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var cv = world.chunks.get(c + Vector2i(dx, dy))
			if cv == null:
				continue
			for group: Group in cv.anim_groups:
				if group.kind != KIND_LIT or group.part.kind != "lit_strike":
					continue
				for i in group.keys.size():
					var o := group.bases[i].origin
					if Vector2(o.x, o.z).distance_to(at) > STRIKE_REACH:
						continue
					var st := _state(group.keys[i])
					# Rising again from wherever an earlier strike's glow is.
					var age := _time - st.strike_at
					var level := 0.0
					if age < STRIKE_GONE:
						level = age / STRIKE_RISE if age < STRIKE_RISE else exp(-(age - STRIKE_RISE) / STRIKE_FADE * 3.0)
					st.strike_at = _time - minf(level, 1.0) * STRIKE_RISE
					_write(group, i, world.working)


## The shader's two clocks now (f3d_anim_time): seconds since the latest even and odd epoch began.
func clock() -> Vector2:
	var cur := _time - _epoch * EPOCH
	return Vector2(cur, cur + EPOCH) if _epoch % 2 == 0 else Vector2(cur + EPOCH, cur)


func _update_clock() -> void:
	var k := int(floor(_time / EPOCH))
	if k != _epoch:
		_epoch = k
		_migrate = world.chunks.keys() if world != null else []
	RenderingServer.global_shader_parameter_set(&"f3d_anim_time", clock())


## Moves groups not yet on the current epoch's clock onto it, within MIGRATE_USEC.
func _migrate_some() -> void:
	var t0 := Time.get_ticks_usec()
	while not _migrate.is_empty() and Time.get_ticks_usec() - t0 < MIGRATE_USEC:
		var cv = world.chunks.get(_migrate[-1])
		var done := true
		if cv != null:
			for group: Group in cv.anim_groups:
				if group.epoch == _epoch or group.kind <= KIND_STILL and group.kind != KIND_GLOW:
					continue
				for i in group.keys.size():
					_write(group, i, world.working)
				group.epoch = _epoch
				if Time.get_ticks_usec() - t0 >= MIGRATE_USEC:
					done = false
					break
		if done:
			_migrate.pop_back()
	write_usec += Time.get_ticks_usec() - t0
	if not _migrate.is_empty() or Time.get_ticks_usec() - t0 > 50:
		preload("res://scripts/world/frame_budget.gd").spent(&"anim_migrate", Time.get_ticks_usec() - t0, _migrate.size())


func _process(delta: float) -> void:
	_time += delta
	_update_clock()
	if world == null:
		return
	if movers == null and world.get_parent() != null:
		movers = world.get_parent().get_node_or_null("Movers")
	if not _migrate.is_empty():
		_migrate_some()
	var focus: Vector2 = world.focus()
	var spent := {}  # KIND_* -> microseconds this frame (world.prof, for --stutter-probe)
	var lo := Vector2i(floori((focus.x - RADIUS) / 32.0), floori((focus.y - RADIUS) / 32.0))
	var hi := Vector2i(floori((focus.x + RADIUS) / 32.0), floori((focus.y + RADIUS) / 32.0))
	for cy in range(lo.y, hi.y + 1):
		for cx in range(lo.x, hi.x + 1):
			var cv = world.chunks.get(Vector2i(cx, cy))
			if cv == null or cv.anim_groups.is_empty():
				continue
			var rect := Rect2(Vector2(cx, cy) * 32.0, Vector2(32.0, 32.0))
			if focus.clamp(rect.position, rect.end).distance_to(focus) > RADIUS:
				continue
			for group: Group in cv.anim_groups:
				if group.kind < KIND_WORM or group.kind == KIND_STILL or group.kind == KIND_TIMED or group.kind == KIND_LIT or group.kind == KIND_SWITCH:
					continue
				var t0 := Time.get_ticks_usec()
				match group.kind:
					KIND_TURRET:
						_turrets(group, delta)
					KIND_COLLECTOR:
						_collector(group, delta)
					KIND_WORM:
						_worms(group, focus, delta)
					KIND_HATCH:
						_hatch(group, delta)
					KIND_ROBOPORT:
						_roboport(group, delta)
					KIND_GATE:
						_gates(group, focus, delta)
				spent[group.kind] = int(spent.get(group.kind, 0)) + Time.get_ticks_usec() - t0
	if "prof" in world:
		for kind in spent:
			var key: String = PROF_KEYS[kind]
			world.prof[key] = int(world.prof.get(key, 0)) + int(spent[kind])
	_cleanup_timer += delta
	if _cleanup_timer >= CLEANUP_INTERVAL:
		_cleanup_timer = 0.0
		for key in _states.keys():
			if not world.entities.has(key):
				_states.erase(key)
				if turrets != null and key is int:
					turrets.call("forget", key)


## Opens or shuts instance i of a linear group, writing it only when that changes.
func _set_open(group: Group, i: int, st: State, open: bool) -> void:
	var l := _linear(st, group.part, false, false)
	if bool(l[2]) == open:
		return
	_linear(st, group.part, true, open)
	_write(group, i, world.working if world != null else {})


## Whether a near-checked group looks this frame: every TURRET_LOOK or so, each group on its own beat.
static func _looks(group: Group, delta: float) -> bool:
	group.look -= delta
	if group.look > 0.0:
		return false
	group.look = TURRET_LOOK * randf_range(0.8, 1.2)
	return true


## Hatches: open while a mover of the hatch's types is within its reach (movers.gd), closed
## after, at the hatch's speed.
func _hatch(group: Group, delta: float) -> void:
	if not _looks(group, delta):
		return
	var h: Dictionary = ModelLibrary.HATCHES[group.part.kind]
	for i in group.keys.size():
		var base := group.bases[i]
		var near: bool = movers != null and not movers.pick(Vector2(base.origin.x, base.origin.z), h.get("reach", 2.0), h["types"]).is_empty()
		_set_open(group, i, _state(group.keys[i]), near)


## Sets instance i's transform, only when it changed (an idle turret's head or folded arm stays put).
static func _draw_at(group: Group, i: int, xf: Transform3D) -> void:
	if group.drawn.size() != group.keys.size():
		group.drawn.resize(group.keys.size())
		group.drawn.fill(Transform3D(Basis.from_scale(Vector3.ZERO), Vector3.ZERO))
	if group.drawn[i] != xf:
		group.drawn[i] = xf
		group.mm.set_instance_transform(i, xf)


## Turret heads: turned, raised and fired by turrets.gd from the mod's turret states.
func _turrets(group: Group, delta: float) -> void:
	if turrets == null:
		return
	var part := group.part
	for i in group.keys.size():
		var base := group.bases[i]
		var xf: Transform3D = turrets.call("head_transform", int(group.units[i]), part, base, delta)
		_draw_at(group, i, base * xf)


## An asteroid collector's arm: its head, fingers and links where collectors.gd has them.
func _collector(group: Group, delta: float) -> void:
	if collectors == null:
		return
	var part := group.part
	for i in group.keys.size():
		var base := group.bases[i]
		var xf: Transform3D = collectors.call("part_transform", int(group.units[i]), part, base, delta,
			group.customs[i])
		_draw_at(group, i, base * xf)


## Roboport doors and charging lights, logistic chests' hatches: open and lit while a robot is
## near (movers.gd).
func _roboport(group: Group, delta: float) -> void:
	if not _looks(group, delta):
		return
	var reach := HATCH_NEAR if group.part.kind.begins_with("hatch_") else ROBOT_NEAR
	var asks := movers != null and movers.has_method("robot_near")
	for i in group.keys.size():
		var st := _state(group.keys[i])
		if _time - st.looked >= TURRET_LOOK * 0.7:
			st.looked = _time
			st.target = asks and movers.robot_near(group.bases[i].origin, reach)
		_set_open(group, i, st, st.target == true)


## Gate doors: open (sunk) while the character (every frame) or a friendly vehicle (looked for
## every TURRET_LOOK or so) is near, at the gate's speed; closed again once it has gone.
func _gates(group: Group, focus: Vector2, delta: float) -> void:
	var look := _looks(group, delta) and movers != null and movers.has_method("friendly_near")
	for i in group.keys.size():
		var base := group.bases[i]
		var at := Vector2(base.origin.x, base.origin.z)
		var st := _state(group.keys[i])
		if look:
			st.target = movers.friendly_near(Vector3(at.x, 0.0, at.y), GATE_VEHICLE_REACH)
		_set_open(group, i, st, at.distance_to(focus) <= GATE_REACH or st.target == true)


static func _is_worm(group: Group) -> bool:
	# A mesh without a rig (or no mesh yet) has no rig_mode, which comes back null.
	var mesh := group.mm.mesh if group.mm != null else null
	var m := mesh.surface_get_material(0) as ShaderMaterial if mesh != null and mesh.get_surface_count() > 0 else null
	var mode: Variant = m.get_shader_parameter("rig_mode") if m != null else null
	return mode != null and int(mode) == 4


## Worms: folded (0), prepared (1) or attacking (2), in the instance's custom data, moving
## between them at Factorio's speeds; attacking ones turn to face their target.
func _worms(group: Group, focus: Vector2, delta: float) -> void:
	var height := group.mm.mesh.get_aabb().end.y
	var ranges: Array = WORM_RANGES[0]
	for r in WORM_RANGES:
		ranges = r
		if height < float(r[0]) * 4.0:
			break
	var creatures: Node = movers.get_node_or_null("Creatures") if movers != null else null
	var reported: bool = creatures != null and creatures.attacks_reported()
	for i in group.keys.size():
		var st := _state(group.keys[i])
		var base := group.bases[i]
		var at := Vector2(base.origin.x, base.origin.z)
		var d := at.distance_to(focus)
		var aim: Variant = null
		if reported:
			var t = creatures.attack_target(group.units[i])
			if t != null:
				aim = Vector2(t.x, t.z)
				st.idle_timer = WORM_HOLD
		elif d <= float(ranges[1]):
			aim = focus
		st.idle_timer = maxf(st.idle_timer - delta, 0.0)
		var goal := 0.0
		if aim != null:
			goal = 2.0
		elif d <= float(ranges[2]) or st.idle_timer > 0.0:
			goal = 1.0
		if _worm_override >= 0.0:
			goal = _worm_override
		if st.activity < 0.0:
			st.activity = minf(goal, 1.0)
		var seconds := WORM_RISE
		if st.activity > 1.0 or goal > 1.0:
			seconds = WORM_START_ATTACK if goal > st.activity else WORM_END_ATTACK
		elif goal < st.activity:
			seconds = WORM_FOLD
		st.activity = move_toward(st.activity, goal, delta / seconds)
		if aim != null:
			var want := atan2(-(aim.x - at.x), -(aim.y - at.y)) - base.basis.get_euler().y
			st.yaw += clampf(wrapf(want - st.yaw, -PI, PI), -WORM_TURN * delta, WORM_TURN * delta)
		_draw_at(group, i, base * Transform3D(Basis(Vector3.UP, st.yaw), Vector3.ZERO))
		var custom := group.customs[i]
		if custom.a != st.activity:
			custom.a = st.activity
			group.customs[i] = custom
			group.mm.set_instance_custom_data(i, custom)
