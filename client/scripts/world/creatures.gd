extends Node3D
## Walking creatures (biters, spitters): drawn as one MultiMesh per model and pose, so a screen
## full of them stays cheap, and animated in the material's vertex shader (creature_models.gd).
##
## A walking creature is drawn from its record (mover_records.gd), which movers.gd writes when a
## new position of it arrives: its instance (in a layer of its model for its LIVE_CELL square) only
## says which record, and the shader (factorio_material_mover.gdshader) works out where it is, its
## facing, its gait's phase from the distance walked (one loop of legs per Factorio animation loop:
## distance_per_frame x 16 frames, so feet keep pace with the ground), the gait's strength from its
## speed and its bob. Nothing is done here for it per frame: ~450 biters walking at the owner's wall
## had cost 2-2.5 ms of script a frame. An instance is written only when it comes, goes or crosses
## into another square.
##
## Attacking and dying creatures are posed here every frame instead (their bites, spits and falls),
## each frame's poses appended after a layer's walkers; so are other players' characters (posed on
## the CPU, character_pose.gd) and creatures whose model can't walk on the GPU, from their nodes,
## which movers.gd moves.
##
## Attacks come from the mod's `en` (units in range of their attack target, worms with a shooting
## target); with a mod too old to send it, one that stands still near the player's character
## counts as attacking. Biters bite with their family's `-attack` pose once per cooldown, spitters
## brace in theirs and spit (the acid stream itself is a stream entity, drawn with the projectiles).
## Where an enemy dies it falls the way its corpse lies over its corpse's dying time, then that
## `-corpse` pose (one of four, by the direction it faced) lies for Factorio's 15 minutes and sinks
## into the ground. Worms fall out of their holes the same way, Gleba's spawners slump, Nauvis's
## leave their corpse at once (`died_at`, from main.gd's `died`).
##
## Fights stay cheap to draw. A creature model is 7,000-9,000 triangles, and with every MultiMesh
## bounded by the whole map each creature and corpse anywhere was drawn in the view and in all four
## shadow splits (a 150-enemy wave in real 2.1.23: 1.7 million triangles a frame -> 7.2 million,
## staying so for the corpses' 15 minutes). The live ones are now bounded by where they are this
## frame; corpses, which don't move, lie in one MultiMesh per model per CORPSE_CELL square (16 tiles), rebuilt
## only when one comes, goes or sinks, so cells out of view (or out of a shadow split) cost nothing.
## Creature models get view LODs (model_lods.gd): the same vertices, so the shader's limbs still bend.

const ModelLibrary := preload("res://scripts/world/model_library.gd")
const CreatureModels := preload("res://scripts/world/creature_models.gd")
const ItemIcons := preload("res://scripts/world/item_icons.gd")
const ModelLods := preload("res://scripts/world/model_lods.gd")
const MoverRecords := preload("res://scripts/world/mover_records.gd")
const MoverShader := preload("res://shaders/factorio_material_mover.gdshader")
const MoverAlphaShader := preload("res://shaders/factorio_material_mover_alpha.gdshader")

## Tiles walked per loop of the run animation (Factorio's distance_per_frame x 16 frames).
const LOOP_DISTANCE := {
	"small-biter": 2.0, "medium-biter": 3.0, "big-biter": 4.8, "behemoth-biter": 5.1,
	"small-spitter": 0.64, "medium-spitter": 0.88, "big-spitter": 1.12, "behemoth-spitter": 1.34,
	"small-wriggler-pentapod": 2.625, "medium-wriggler-pentapod": 2.625, "big-wriggler-pentapod": 2.625,
}
const DEFAULT_LOOP := 2.0
## Loops per second while standing still but awake, so the legs never freeze mid-step.
const IDLE_LOOPS := 0.15
## Tiles from the character within which a still unit counts as attacking, without `en` (biters
## bite from next to it, spitters from range).
const ATTACK_RANGE := {"biter": 3.0, "spitter": 16.0}
## Attack cooldowns from Factorio's unit prototypes, in seconds (ticks / 60); each one varies by
## up to 15 % (cooldown_deviation).
const BITER_ATTACK_SECONDS := {
	"small-biter": 35.0 / 60.0, "medium-biter": 35.0 / 60.0,
	"big-biter": 35.0 / 60.0, "behemoth-biter": 50.0 / 60.0,
}
const SPITTER_ATTACK_SECONDS := 100.0 / 60.0
const COOLDOWN_DEVIATION := 0.15
## How long the attack animations run: the biter's 11 frames at 0.4 a tick; the spitter's 14
## frames forward-then-backward (27 steps) at 0.4.
const BITE_SECONDS := 11.0 / 0.4 / 60.0
const SPIT_SECONDS := 27.0 / 0.4 / 60.0
## How far into its attack a spitter swaps to its `-attack` stance (and back at the end).
const SPIT_SWAP := 0.1
## An attack lapses when its unit hasn't been in `en` for this long (it comes every 10 ticks).
const ATTACK_HOLD := 0.5
## Without an `en` for this long, attacks are guessed again (a mod that doesn't send it).
const EN_TIMEOUT := 30.0
const TURN_RATE := 10.0  # how fast an attacker turns to its target (1 / seconds)
const STILL_SPEED := 0.4  # tiles per second
const STILL_SECONDS := 0.25
## The corpses' dying animations (1 / dying_speed ticks, in seconds): the live model collapses.
const DYING_SECONDS := {
	"small-biter": 0.93, "medium-biter": 1.06, "big-biter": 1.19, "behemoth-biter": 1.25,
	"small-spitter": 0.89, "medium-spitter": 1.01, "big-spitter": 1.13, "behemoth-spitter": 1.18,
	# Gleba's: their corpses' dying_speed 0.015.
	"gleba-spawner": 1.11, "gleba-spawner-small": 1.11,
	# Worms' corpses: dying_speed 0.01; the worm falls out of its hole.
	"small-worm-turret": 1.67, "medium-worm-turret": 1.67, "big-worm-turret": 1.67, "behemoth-worm-turret": 1.67,
}
const DEFAULT_DYING := 1.0
## How each corpse model lies compared with its live model (tools/models/creature_pose.py): the
## body's middle at rest ("at") and fallen ("to"), the turn and the scale. The dying animation
## turns the live model that way, so the corpse that replaces it lies where it fell.
const POSES_PATH := "res://data/creature_poses.json"
## Factorio's corpses stay 54,000 ticks (time_before_removed), then this sinks them.
const CORPSE_SECONDS := 900.0
const CORPSE_SINK := 5.0
const MAX_CORPSES := 300
## Corpses are drawn per square cell this many tiles wide (see the top).
const CORPSE_CELL := 16.0
## Biter and spitter corpses lie in a puddle (the corpse's ground_patch): Factorio's sheet of 4
## variations, tinted as the prototype does, drawn at the big tier's 0.5 scale times the tier's.
const PUDDLE_FILE := "base/graphics/entity/biter/blood-puddle-var-main.png"
const PUDDLE_VARIATIONS := 4
const PUDDLE_TINT := Color(0.54, 0.09, 0.54, 1.0)
const PUDDLE_SCALE := 0.5
const PUDDLE_HEIGHT := 0.015


class Creature:
	var name := ""
	var unit := 0
	var node: Node3D
	var last := Vector3.ZERO
	var speed := 0.0
	var phase := 0.0
	var still := 0.0
	var lunge := 0.0  # seconds into the current attack cycle
	var cycle := 1.0  # this cycle's cooldown, in seconds
	var yaw := 0.0
	var attacking := false
	## What it was last drawn as (its model and instance data), reused on frames it is skipped
	## (far from the focus: see FAR_EVERY), and the seconds skipped since.
	var drawn_model := ""
	var drawn := PackedFloat32Array()
	var drawn_at := Vector3.ZERO
	var skipped := 0.0
	## Its record (mover_records.gd) when it walks on the GPU, else -1 (drawn from its node here).
	var slot := -1
	## The layer its walking instance is in and its index there, or null while it is posed here.
	var walker: Layer
	var index := -1
	var at := Vector3.ZERO  # its newest position (placed)


## Live creatures of one model in one LIVE_CELL square: the walkers' instances (kept, written when
## one comes, goes or moves in from another square), then this frame's posed ones.
class Layer:
	var mmi: MultiMeshInstance3D
	var model := ""
	var cell := Vector2i.ZERO
	var mover := false  # its mesh is the model's copy with the mover shader
	var walkers: Array[Creature] = []
	var buffer := PackedFloat32Array()  # the walkers' instances, as many as the MultiMesh holds
	var posed := PackedFloat32Array()  # this frame's
	var low := Vector3.INF  # the posed ones' origins' bounds this frame
	var high := -Vector3.INF
	var dirty := false
	var shown := 0
	var idle_since := 0.0  # when it was left empty
	var box := AABB()
	var cast := -1
	var lods := false  # its mesh is the copy with view LODs (nothing more to swap)
	var still := false  # walkers only, nothing changed: _flush looks at it again when the focus moves


class Corpse:
	var model := ""
	var xform := Transform3D.IDENTITY
	var born := 0.0  # _clock when it lay down
	var puddle := -1  # its blood puddle's variation, or -1 for none
	var size := 1.0
	var cell := Vector2i.ZERO


## The corpses in one CORPSE_CELL square and what draws them.
class CorpseCell:
	var corpses: Array[Corpse] = []
	var dirty := true
	var sinking := false  # some are sinking: rebuilt every frame until they are gone
	var layers := {}  # model name -> MultiMeshInstance3D
	var puddles: Array[MultiMeshInstance3D] = []  # one per puddle variation, made with the first puddle
	## What was last written to its MultiMeshes (model name -> instances; per puddle variation), and
	## corpses come since: a corpse is added to them instead of the cell being built again (a wall
	## under attack piles a hundred corpses in a cell, a new one every few frames).
	var buffers := {}
	var puddle_buffers: Array[PackedFloat32Array] = []
	var built := false
	var pending: Array[Corpse] = []


## A creature collapsing before its corpse lies down, drawn with its own model.
class Dying:
	var name := ""
	var xform := Transform3D.IDENTITY
	var phase := 0.0
	var age := 0.0
	var seconds := 1.0
	var heap := false  # a spawner: it slumps and spreads instead of rolling over
	var corpse := ""  # the corpse model it falls into (its tier's name + "-corpse" or a variant)


## The player's character, for the attack guess; found as the "Avatar" sibling when not set.
var target: Node3D
## mover_records.gd's state(slot) and the records themselves (movers.gd sets them): where a creature
## walking on the GPU is drawn now, for posing it here (it starts to attack, it dies).
var pose_source: Callable
var records: MoverRecords
## Where the focus was when _flush last looked at every layer (their shadows go by it).
var _flushed_at := Vector3.INF

var _creatures := {}  # unit -> Creature
var _corpses: Array[Corpse] = []  # oldest first (MAX_CORPSES drops from the front)
var _cells := {}  # Vector2i -> CorpseCell
var _expiry_wait := 0.0
var _dying: Array[Dying] = []
var _attacks := {}  # unit -> [target Vector3, when it was last listed]
var _looks := {}  # another player's character unit -> its armour's look (set_looks)
var _clock := 0.0
var _en_time := -1e9  # when the last `en` came
var _layers := {}  # model name -> {LIVE_CELL square: Layer}
var _posed := {}  # unit -> Creature: posed here every frame (attacking, characters, no GPU model)
var _mover_meshes := {}  # model name -> its copy with the mover shader, or null where it can't walk on the GPU
var _guess_wait := 0.0
var _missing := {}  # model names without a mesh
var _falls := {}  # corpse model -> {at, to, turn, scale} (POSES_PATH), loaded on first use
var _falls_loaded := false
var _puddle_meshes: Array[PlaneMesh] = []  # one per variation, empty without an install
## prewarm(): 1 asked, 2 done. The first corpse cell made the renderer compile the puddles'
## pipelines and stall 300-600 ms mid-fight; a hidden corpse drawn under the ground before the
## fight makes them while nothing is going on.
var _warm := 0
const WARM_MODEL := "small-biter-corpse"
var _puddle_task := -1  # loading the puddles' sheet on a worker thread; -2 once done
var _puddle_images: Array = []  # what that task made, one per variation


func clear() -> void:
	for c: Creature in _creatures.values():
		c.walker = null
	for cells: Dictionary in _layers.values():
		for layer: Layer in cells.values():
			layer.walkers.clear()
			layer.dirty = true
	_creatures.clear()
	_posed.clear()
	_corpses.clear()
	for cell: CorpseCell in _cells.values():
		_free_cell(cell)
	_cells.clear()
	_dying.clear()
	_attacks.clear()


func count() -> int:
	return _creatures.size()


func corpse_count() -> int:
	return _corpses.size() + _dying.size()


## MultiMeshes drawing corpses and their puddles (for tests).
func corpse_layers() -> int:
	var n := 0
	for cell: CorpseCell in _cells.values():
		n += cell.layers.size() + cell.puddles.size()
	return n


## Draws prototype `name` until removed: walking from record `slot` on the GPU (movers.gd writes it;
## gait() said it can), or with slot -1 at `node` (kept up to date by movers.gd), posed here.
func add(unit: int, name: String, node: Node3D, slot := -1) -> void:
	var c := Creature.new()
	c.name = name
	c.unit = unit
	c.node = node
	c.last = node.position
	c.phase = randf() * TAU
	c.slot = slot
	c.at = node.position
	_creatures[unit] = c
	if slot >= 0:
		_walk(c)
	else:
		_posed[unit] = c


## For a prototype that can walk on the GPU: Vector2(radians of its gait a tile walked, its bob's
## scale), for its record; Vector2.ZERO when it can't (it is posed here from its node instead).
func gait(name: String) -> Vector2:
	if _mover_mesh(name) == null:
		return Vector2.ZERO
	return Vector2(TAU / float(LOOP_DISTANCE.get(name, DEFAULT_LOOP)), _scale_of(name))


## A walking creature's newest position (movers.gd, as its record is written): its instance moves to
## the layer of its new square when it crosses into one.
func placed(unit: int, at: Vector3) -> void:
	var c: Creature = _creatures.get(unit)
	if c == null:
		return
	c.at = at
	if c.walker != null and _cell_of(at) != c.walker.cell:
		_unwalk(c)
		_walk(c)


static func _cell_of(at: Vector3) -> Vector2i:
	return Vector2i(floori(at.x / LIVE_CELL), floori(at.z / LIVE_CELL))


## Puts a GPU creature's walking instance in its layer (it is drawn from its record from now on).
func _walk(c: Creature) -> void:
	_posed.erase(c.unit)
	c.attacking = false
	var layer := _layer(c.name, _cell_of(c.at))
	if layer == null:
		_posed[c.unit] = c  # its model isn't made yet: tried again from _process
		return
	if not layer.mover:
		_use_mover_mesh(layer)
	c.walker = layer
	c.index = layer.walkers.size()
	layer.walkers.append(c)
	_ensure(layer, layer.walkers.size())
	var b := layer.buffer
	var o := c.index * 16
	var centre := (Vector2(layer.cell) + Vector2(0.5, 0.5)) * LIVE_CELL
	# A plain transform at the square's middle; the record (slot + 1 in b) says the rest.
	b[o] = 1.0
	b[o + 1] = 0.0
	b[o + 2] = 0.0
	b[o + 3] = centre.x
	b[o + 4] = 0.0
	b[o + 5] = 1.0
	b[o + 6] = 0.0
	b[o + 7] = 0.0
	b[o + 8] = 0.0
	b[o + 9] = 0.0
	b[o + 10] = 1.0
	b[o + 11] = centre.y
	b[o + 12] = 0.0
	b[o + 13] = 0.0
	b[o + 14] = float(c.slot + 1)
	b[o + 15] = 1.0
	layer.dirty = true


## Takes a creature's walking instance out of its layer (the last one moves into its place).
func _unwalk(c: Creature) -> void:
	var layer := c.walker
	if layer == null:
		return
	var last := layer.walkers.size() - 1
	if c.index != last:
		var other: Creature = layer.walkers[last]
		layer.walkers[c.index] = other
		other.index = c.index
		var b := layer.buffer
		for k in 16:
			b[c.index * 16 + k] = b[last * 16 + k]
	layer.walkers.resize(last)
	layer.dirty = true
	c.walker = null
	c.index = -1


## A GPU creature starts to be posed here (it attacks): from where its record draws it now.
func _pose(c: Creature) -> void:
	_unwalk(c)
	var xf := _pose_now(c)
	c.last = xf.origin
	c.yaw = xf.basis.get_euler().y
	c.speed = 0.0
	_posed[c.unit] = c


## Where a creature is drawn now: from its record for one walking on the GPU, else its node.
func _pose_now(c: Creature) -> Transform3D:
	if c.slot >= 0 and records != null:
		return Transform3D(Basis(Vector3.UP, records.yaw_at(c.slot, records.tick)), records.position(c.slot))
	if c.slot >= 0 and pose_source.is_valid():
		var st: Dictionary = pose_source.call(c.slot)
		return Transform3D(Basis(Vector3.UP, st["yaw"]), st["pos"])
	return c.node.transform


## The model's copy whose materials use the mover shader (its walkers drawn from their records), made
## once; null where it can't walk on the GPU (no mesh, not a walking rig, a material of another kind).
## Built from the CPU arrays and copied materials (nothing read back from the RenderingServer).
func _mover_mesh(model: String) -> ArrayMesh:
	if _mover_meshes.has(model):
		return _mover_meshes[model]
	if not pose_source.is_valid() or not ModelLibrary.ready(model):
		return null
	var mesh := ModelLibrary.mesh_for(model) as ArrayMesh
	var base := CreatureModels.base_model(model)
	var out: ArrayMesh = null
	if mesh != null and CreatureModels.rig(model if base == "" else base).get("mode", "") == "walk":
		out = ArrayMesh.new()
		var kept: Array = []
		for i in mesh.get_surface_count():
			var material := mesh.surface_get_material(i) as ShaderMaterial
			var alpha := material != null and material.shader == ModelLibrary.FactorioAlphaShader
			if material == null or not (alpha or material.shader == ModelLibrary.FactorioShader) \
					or mesh.surface_get_primitive_type(i) != Mesh.PRIMITIVE_TRIANGLES:
				out = null
				break
			# The source's own CPU copy where it has one (nothing here changes it), else a copy.
			var arrays: Array = (mesh.get_meta(ModelLods.ARRAYS_META) as Array)[i] if mesh.has_meta(ModelLods.ARRAYS_META) \
				else ModelLods.arrays_of(mesh, i)
			kept.append(arrays)
			out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, mesh.surface_get_format(i) & ModelLods.CUSTOM_FORMATS)
			var copy := ModelLods.copy_material(material)
			copy.shader = MoverAlphaShader if alpha else MoverShader
			out.surface_set_material(i, copy)
			out.surface_set_name(i, mesh.surface_get_name(i))
		if out != null:
			out.set_meta(ModelLods.ARRAYS_META, kept)
			out.resource_name = mesh.resource_name
	_mover_meshes[model] = out
	return out


func _use_mover_mesh(layer: Layer) -> void:
	var mesh := _mover_mesh(layer.model)
	if mesh == null:
		return
	layer.mover = true
	ModelLods.request_view_lods(mesh)
	var lods := ModelLods.lod_copy(mesh)
	layer.mmi.multimesh.mesh = lods if lods != null else mesh
	layer.lods = lods != null
	layer.still = false


## Other players' characters by unit -> the model of their armour's look (avatar.gd look_for),
## from `pl`; kept apart from the creatures, which may come before or after it.
func set_looks(looks: Dictionary) -> void:
	_looks = looks


## The model unit is drawn with.
func look_of(unit: int) -> String:
	var c: Creature = _creatures.get(unit)
	var name := c.name if c != null else ""
	var model := str(_looks.get(unit, ""))
	return model if model != "" and _has_model(model) else name


## `en`: who is attacking, and where its target is.
func handle_attacks(msg: Dictionary) -> void:
	var l = msg.get("l")
	if not l is Array:
		return
	_en_time = _clock
	for i in range(0, l.size() - 2, 3):
		var unit := int(l[i])
		_attacks[unit] = [Vector3(float(l[i + 1]) / 256.0, 0.0, float(l[i + 2]) / 256.0), _clock]
		var c: Creature = _creatures.get(unit)
		if c != null and c.walker != null:
			_pose(c)  # posed here while it attacks


## The position a unit (or worm) is attacking, or null; anim.gd asks for worms.
func attack_target(unit: int) -> Variant:
	var a = _attacks.get(unit)
	if a == null or _clock - float(a[1]) > ATTACK_HOLD:
		return null
	return a[0]


## True while the mod is sending `en` (attacks aren't guessed then).
func attacks_reported() -> bool:
	return _clock - _en_time < EN_TIMEOUT


## `died`: it collapses where it was, then leaves its corpse.
func remove(unit: int, died := false) -> void:
	var c: Creature = _creatures.get(unit)
	if c == null:
		return
	_creatures.erase(unit)
	_posed.erase(unit)
	_attacks.erase(unit)
	var xform := _pose_now(c)
	_unwalk(c)
	if died and _has_model(c.name + "-corpse"):
		var d := Dying.new()
		d.name = c.name
		d.xform = xform
		if c.attacking:
			d.xform.basis = Basis(Vector3.UP, c.yaw)
		d.phase = c.phase
		_pick_corpse(d)
		d.seconds = float(DYING_SECONDS.get(c.name, DEFAULT_DYING))
		_dying.append(d)


## An enemy that isn't drawn here died (a worm, a spawner): its corpse, if it has a model. Gleba's
## spawners first slump into it with their own model over their corpse's dying time.
func died_at(name: String, at: Vector3) -> void:
	if CreatureModels.walks(name) or not _has_model(name + "-corpse"):
		return
	if DYING_SECONDS.has(name) and _has_model(name):
		var d := Dying.new()
		d.name = name
		d.xform = Transform3D(Basis.IDENTITY, at)
		d.seconds = float(DYING_SECONDS[name])
		d.heap = fall_of(name).is_empty()  # a worm falls over as its corpse lies
		_dying.append(d)
		return
	_add_corpse(name + "-corpse", Transform3D(Basis.IDENTITY, at))


func _add_corpse(model: String, xform: Transform3D, puddle := -1, size := 1.0) -> void:
	var corpse := Corpse.new()
	corpse.model = model
	corpse.xform = xform
	corpse.puddle = puddle
	corpse.size = size
	corpse.born = _clock
	corpse.cell = Vector2i(floori(xform.origin.x / CORPSE_CELL), floori(xform.origin.z / CORPSE_CELL))
	_corpses.append(corpse)
	var cell: CorpseCell = _cells.get(corpse.cell)
	if cell == null:
		cell = CorpseCell.new()
		_cells[corpse.cell] = cell
	cell.corpses.append(corpse)
	if cell.built and not cell.dirty:
		cell.pending.append(corpse)
	else:
		cell.dirty = true
	if _corpses.size() > MAX_CORPSES:
		_drop_corpse(_corpses.pop_front())


func _drop_corpse(corpse: Corpse) -> void:
	var cell: CorpseCell = _cells.get(corpse.cell)
	if cell != null:
		cell.corpses.erase(corpse)
		cell.dirty = true


## The last frame's _process time, microseconds, its parts (posed: attacking and other creatures
## posed here; dying; corpses; layers: the live layers' uploads), and how many were attacking
## (--stutter-probe).
var process_usec := 0
var parts_usec := {}
var attacking := 0

## Live creatures are drawn per model per LIVE_CELL-tile square: each square's layer takes its own
## level of detail from its distance and is culled on its own, and squares further than
## LIVE_SHADOW_RANGE from the focus cast no shadow. One layer per model for a whole wave took one
## LOD for all and cast every creature into all four shadow splits (owner's save, ~450 biters at a
## wall: 15-17 ms of GPU a frame). A square's layer left empty LIVE_IDLE seconds is freed.
const LIVE_CELL := 32.0
const LIVE_SHADOW_RANGE := 48.0
const LIVE_IDLE := 10.0
## Tiles the focus moves before every live layer's shadow casting is looked at again.
const LIVE_MOVED := 8.0
## Live layers _flush looked at in the last frame (--stutter-probe).
var layers_seen := 0
var _idle_sweep_at := 0.0
## Creatures posed here further than these from the focus are worked out every second and every
## third frame and drawn as they were in between (movers.gd moves those it moves as often).
const NEAR_EVERY := 40.0
const FAR_EVERY := 80.0
var _stepping: Creature  # the creature _step is pushing, so _push can keep what it drew


## Turrets or enemies are about: get the corpses' and puddles' drawing ready (see _warm).
func prewarm() -> void:
	if _warm == 0:
		_warm = 1


func _process(delta: float) -> void:
	var t0 := Time.get_ticks_usec()
	_clock += delta
	if _warm == 1 and target != null and not _poll_puddles() and ModelLibrary.ready(WARM_MODEL):
		_warm = 2
		# Under the ground below the focus (in view, hidden by the terrain), sinking out of the
		# list within a few seconds.
		_add_corpse(WARM_MODEL, Transform3D(Basis.IDENTITY, Vector3(target.position.x, -8.0, target.position.z)), 0)
		_corpses[-1].born = _clock - CORPSE_SECONDS - CORPSE_SINK + 4.0
		_corpses.push_front(_corpses.pop_back())  # the oldest: the first to go
	if target == null and get_parent() != null and get_parent().get_parent() != null:
		target = get_parent().get_parent().get_node_or_null("Avatar")
	var focus: Vector3 = target.position if target != null else Vector3.ZERO
	var reported := attacks_reported()
	var frame := Engine.get_process_frames()
	attacking = 0
	var walking: Array[Creature] = []
	var t1 := Time.get_ticks_usec()
	for c: Creature in _posed.values():
		if c.attacking:
			attacking += 1
		if not c.drawn.is_empty() and c.drawn_model != "":
			var away := Vector2(c.drawn_at.x - focus.x, c.drawn_at.z - focus.z).length_squared()
			var every := 3 if away > FAR_EVERY * FAR_EVERY else (2 if away > NEAR_EVERY * NEAR_EVERY else 1)
			if every > 1 and (frame + c.unit) % every != 0:
				c.skipped += delta
				_push_drawn(c)
				continue
		_stepping = c
		if _step(c, delta + c.skipped, focus, reported):
			walking.append(c)
		_stepping = null
		c.skipped = 0.0
	for c in walking:
		c.drawn = PackedFloat32Array()
		_walk(c)
	if not reported:
		_guess_attacks(delta, focus)
	var t2 := Time.get_ticks_usec()
	for i in range(_dying.size() - 1, -1, -1):
		var d := _dying[i]
		d.age += delta
		if d.age >= d.seconds:
			_dying.remove_at(i)
			_add_corpse(d.corpse if d.corpse != "" else d.name + "-corpse", d.xform, randi() % PUDDLE_VARIATIONS if CreatureModels.walks(d.name) else -1, _scale_of(d.name))
			continue
		_push(d.name, _collapse(d), d.phase, 0.0)
	var t3 := Time.get_ticks_usec()
	_age_corpses(delta)
	if not _attacks.is_empty() and Engine.get_process_frames() % 60 == 0:
		for unit in _attacks.keys():
			if _clock - float(_attacks[unit][1]) > ATTACK_HOLD:
				_attacks.erase(unit)
	var t4 := Time.get_ticks_usec()
	_flush(focus, delta)
	process_usec = Time.get_ticks_usec() - t0
	parts_usec = {"posed": t2 - t1, "dying": t3 - t2, "corpses": t4 - t3, "layers": process_usec - (t4 - t0)}


## Once a second corpses past their time go; cells with corpses sinking redraw every frame.
func _age_corpses(delta: float) -> void:
	_expiry_wait -= delta
	if _expiry_wait <= 0.0:
		_expiry_wait = 1.0
		while not _corpses.is_empty() and _clock - _corpses[0].born > CORPSE_SECONDS + CORPSE_SINK:
			_drop_corpse(_corpses.pop_front())
		for cell: CorpseCell in _cells.values():
			cell.sinking = cell.corpses.any(func(c: Corpse) -> bool: return _clock - c.born > CORPSE_SECONDS)
			for mmi: MultiMeshInstance3D in cell.layers.values():
				_use_lods(mmi)
	for key in _cells.keys():
		var cell: CorpseCell = _cells[key]
		if not (cell.dirty or cell.sinking):
			if not cell.pending.is_empty():
				_append_cell(cell)
			continue
		if cell.corpses.is_empty():
			_free_cell(cell)
			_cells.erase(key)
			continue
		_build_cell(cell, key)


## Adds a cell's new corpses to what its MultiMeshes hold (as _build_cell would lay them), or
## leaves it to be built again when one needs a layer it doesn't have yet or isn't ready.
func _append_cell(cell: CorpseCell) -> void:
	var touched := {}
	var puddled := false
	for corpse in cell.pending:
		var puddle := corpse.puddle >= 0 and corpse.puddle < _puddle_meshes.size()
		if not _has_model(corpse.model) or not cell.layers.has(corpse.model) or not cell.buffers.has(corpse.model) \
				or (puddle and cell.puddles.size() != _puddle_meshes.size()) or (corpse.puddle >= 0 and _poll_puddles()):
			cell.dirty = true
			cell.pending.clear()
			return
	for corpse in cell.pending:
		_append_instance(cell.buffers[corpse.model], corpse.xform, 0.0, 0.0)
		touched[corpse.model] = true
		if corpse.puddle >= 0 and corpse.puddle < _puddle_meshes.size():
			var at := corpse.xform.origin
			var k := corpse.size
			var lift := at.y + PUDDLE_HEIGHT + 0.0012 * posmod(hash(Vector2i(roundi(at.x * 4.0), roundi(at.z * 4.0))), 4)
			cell.puddle_buffers[corpse.puddle].append_array([k, 0.0, 0.0, at.x, 0.0, 1.0, 0.0, lift, 0.0, 0.0, k, at.z])
			puddled = true
	cell.pending.clear()
	for model in touched:
		_fill((cell.layers[model] as MultiMeshInstance3D).multimesh, cell.buffers[model], 16)
	if puddled:
		for v in cell.puddles.size():
			_fill(cell.puddles[v].multimesh, cell.puddle_buffers[v], 12)


## Writes one cell's corpses and puddles into its MultiMeshes.
func _build_cell(cell: CorpseCell, key: Vector2i) -> void:
	var puddles_coming := _poll_puddles()
	var by_model := {}
	var puddles: Array[PackedFloat32Array] = []
	puddles.resize(PUDDLE_VARIATIONS)
	var waiting := false
	for corpse: Corpse in cell.corpses:
		if not _has_model(corpse.model):
			waiting = waiting or not _missing.has(corpse.model)
			continue
		waiting = waiting or (puddles_coming and corpse.puddle >= 0)
		var xf := corpse.xform
		var sink := clampf((_clock - corpse.born - CORPSE_SECONDS) / CORPSE_SINK, 0.0, 1.0)
		xf.origin.y -= sink * 0.6
		if not by_model.has(corpse.model):
			by_model[corpse.model] = PackedFloat32Array()
		_append_instance(by_model[corpse.model], xf, 0.0, 0.0)
		if corpse.puddle >= 0 and corpse.puddle < _puddle_meshes.size() and sink < 1.0:
			var at := corpse.xform.origin
			var k := corpse.size * (1.0 - sink)
			# A step apart by place, so overlapping puddles don't flicker against each other.
			var lift := at.y + PUDDLE_HEIGHT + 0.0012 * posmod(hash(Vector2i(roundi(at.x * 4.0), roundi(at.z * 4.0))), 4)
			puddles[corpse.puddle].append_array([k, 0.0, 0.0, at.x, 0.0, 1.0, 0.0, lift, 0.0, 0.0, k, at.z])
	cell.dirty = waiting  # a model still being made on a worker thread: built again next frame
	var bounds := AABB(Vector3(key.x * CORPSE_CELL - 4.0, -1.0, key.y * CORPSE_CELL - 4.0), Vector3(CORPSE_CELL + 8.0, 6.0, CORPSE_CELL + 8.0))
	for model in cell.layers:
		if not by_model.has(model):
			_fill((cell.layers[model] as MultiMeshInstance3D).multimesh, PackedFloat32Array(), 16)
	for model in by_model:
		var mmi: MultiMeshInstance3D = cell.layers.get(model)
		if mmi == null:
			mmi = _new_layer(model)
			mmi.custom_aabb = bounds
			cell.layers[model] = mmi
		_fill(mmi.multimesh, by_model[model], 16)
	if cell.puddles.is_empty() and not _puddle_meshes.is_empty() and puddles.any(func(b: PackedFloat32Array) -> bool: return not b.is_empty()):
		for mesh in _puddle_meshes:
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.mesh = mesh
			var mmi := MultiMeshInstance3D.new()
			mmi.multimesh = mm
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mmi.custom_aabb = bounds
			add_child(mmi)
			cell.puddles.append(mmi)
	for v in cell.puddles.size():
		_fill(cell.puddles[v].multimesh, puddles[v], 12)
	cell.buffers = by_model
	cell.puddle_buffers = puddles
	cell.built = not cell.dirty
	cell.pending.clear()


func _free_cell(cell: CorpseCell) -> void:
	for mmi in cell.layers.values():
		(mmi as Node).queue_free()
	for mmi in cell.puddles:
		mmi.queue_free()
	cell.layers.clear()
	cell.puddles.clear()


## Sets a MultiMesh to the instances in `b` (`stride` floats each), growing it when needed.
static func _fill(mm: MultiMesh, b: PackedFloat32Array, stride: int) -> void:
	var n := b.size() / stride
	if mm.instance_count < n:
		mm.instance_count = maxi(n * 2, 8)
	if n == 0:
		mm.visible_instance_count = 0
		return
	var full := b
	if mm.instance_count > n:
		full = b.duplicate()
		full.resize(mm.instance_count * stride)
	mm.buffer = full
	mm.visible_instance_count = n


## Without the mod's `en`: a GPU creature standing still near the character is posed here, where
## _step counts it as attacking (checked four times a second, by its newest position first).
func _guess_attacks(delta: float, focus: Vector3) -> void:
	_guess_wait -= delta
	if _guess_wait > 0.0 or target == null or not pose_source.is_valid():
		return
	_guess_wait = 0.25
	for c: Creature in _creatures.values():
		if c.walker == null:
			continue
		var family := "spitter" if c.name.contains("spitter") else "biter"
		if Vector2(c.at.x - focus.x, c.at.z - focus.z).length() > float(ATTACK_RANGE[family]) + 1.0:
			continue
		var st: Dictionary = pose_source.call(c.slot)
		if float(st["still"]) > STILL_SECONDS:
			_pose(c)
			c.still = STILL_SECONDS + 0.01


## Poses a creature for this frame; true when a GPU creature has stopped attacking and walks on its
## record again.
func _step(c: Creature, delta: float, focus: Vector3, reported: bool) -> bool:
	var xf := _pose_now(c)
	var pos := xf.origin
	var moved := Vector2(pos.x - c.last.x, pos.z - c.last.z).length()
	c.last = pos
	var speed := moved / maxf(delta, 0.0001)
	c.speed = lerpf(c.speed, speed, 1.0 - exp(-delta * 10.0))
	var loop: float = LOOP_DISTANCE.get(c.name, DEFAULT_LOOP)
	c.phase = fposmod(c.phase + (moved / loop + IDLE_LOOPS * delta) * TAU, TAU)
	c.still = c.still + delta if c.speed < STILL_SPEED else 0.0
	var family := "spitter" if c.name.contains("spitter") else "biter"
	var at: Variant = null  # the target's position while attacking
	if reported:
		at = attack_target(c.unit)
	elif c.still > STILL_SECONDS and target != null and target.is_visible_in_tree() \
			and Vector2(pos.x - focus.x, pos.z - focus.z).length() < float(ATTACK_RANGE[family]):
		# A hidden character (in a vehicle, or --clean-shot) isn't being bitten.
		at = focus
	if at == null:
		c.attacking = false
		if c.slot >= 0:
			return true
		var gait := clampf(c.speed / 1.5, 0.0, 1.0)
		# The body bobs twice a loop, once per step of each tripod.
		xf.origin.y += absf(sin(c.phase)) * 0.025 * gait * _scale_of(c.name)
		_push(look_of(c.unit), xf, c.phase, maxf(gait, 0.15))
		return false
	if not c.attacking:
		c.attacking = true
		c.lunge = 0.0
		c.cycle = _cooldown(c.name, family)
		c.yaw = xf.basis.get_euler().y
	c.lunge += delta
	if c.lunge >= c.cycle:
		c.lunge -= c.cycle
		c.cycle = _cooldown(c.name, family)
	# Face the target, as Factorio's units do while attacking.
	var to: Vector3 = at - pos
	if Vector2(to.x, to.z).length() > 0.05:
		c.yaw = lerp_angle(c.yaw, atan2(-to.x, -to.z), 1.0 - exp(-delta * TURN_RATE))
	xf.basis = Basis(Vector3.UP, c.yaw)
	var size := _scale_of(c.name)
	var forward := -xf.basis.z
	if family == "biter":
		var bite := _bite_pulse(c.lunge / BITE_SECONDS) if c.lunge < BITE_SECONDS else 0.0
		xf.origin += forward * bite * 0.14 * size
		xf.origin.y += maxf(bite, 0.0) * 0.035 * size
		xf.basis = xf.basis * Basis(Vector3.RIGHT, -bite * 0.08)
		_push(c.name + "-attack" if _has_model(c.name + "-attack") else c.name, xf, c.phase, 0.0)
		return false
	# Spitters brace on their legs, throw the head forward and spit, then settle (Factorio's
	# attack runs forward then backward). The `-attack` model is that stance, legs planted wide
	# (fitted to the sprite's frame 13, where the body barely tilts): it stands in for the walking
	# model over the attack, nodding up a little at the top. Without one the walking model rears.
	var rise := _spit_pulse(c.lunge / SPIT_SECONDS) if c.lunge < SPIT_SECONDS else 0.0
	var spit := maxf(0.0, 1.0 - absf(c.lunge / SPIT_SECONDS - 0.5) * 8.0)
	var pivot := -forward * 0.45 * size  # the back legs
	var reared := rise > SPIT_SWAP and _has_model(c.name + "-attack")
	var tilt := Basis(xf.basis.x.normalized(), rise * (0.08 if reared else 0.32))
	xf.origin += pivot - tilt * pivot + forward * spit * 0.06 * size
	xf.basis = tilt * xf.basis
	_push(c.name + "-attack" if reared else c.name, xf, c.phase, 0.0)
	return false


## The puddles' meshes, made on first use from Factorio's sheet (none without an install). The
## sheet is read and cut on a worker thread (30-49 ms on the main thread at a fight's first corpse).
## True while it is still coming.
func _poll_puddles() -> bool:
	if _puddle_task == -2:
		return false
	if _puddle_task == -1:
		_puddle_task = WorkerThreadPool.add_task(_load_puddles.bind(ItemIcons.factorio_data_dir(), _puddle_images), false, "blood puddles")
		return true
	if not WorkerThreadPool.is_task_completed(_puddle_task):
		return true
	WorkerThreadPool.wait_for_task_completion(_puddle_task)
	_puddle_task = -2
	for image: Image in _puddle_images:
		# The textures themselves are made here: made on the worker, with the renderer on its
		# own thread, the next frame stalled for 600 ms.
		var texture := ImageTexture.create_from_image(image)
		var material := StandardMaterial3D.new()
		material.albedo_texture = texture
		material.albedo_color = PUDDLE_TINT
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.roughness = 0.35  # still wet
		var plane := PlaneMesh.new()
		plane.size = Vector2(texture.get_width(), texture.get_height()) * PUDDLE_SCALE / 32.0
		plane.material = material
		_puddle_meshes.append(plane)
	return false


static func _load_puddles(data_dir: String, out: Array) -> void:
	var path := data_dir.path_join(PUDDLE_FILE) if data_dir != "" else ""
	if path == "" or not FileAccess.file_exists(path):
		return
	var sheet := Image.load_from_file(path)
	if sheet == null:
		return
	sheet.convert(Image.FORMAT_RGBA8)
	var w := sheet.get_width() / PUDDLE_VARIATIONS
	for v in PUDDLE_VARIATIONS:
		var image := sheet.get_region(Rect2i(v * w, 0, w, sheet.get_height()))
		image.generate_mipmaps()
		out.append(image)


func _exit_tree() -> void:
	if _puddle_task >= 0:
		WorkerThreadPool.wait_for_task_completion(_puddle_task)
		_puddle_task = -2


func _cooldown(name: String, family: String) -> float:
	var base: float = SPITTER_ATTACK_SECONDS if family == "spitter" else float(BITER_ATTACK_SECONDS.get(name, 35.0 / 60.0))
	return base * (1.0 + randf_range(-COOLDOWN_DEVIATION, COOLDOWN_DEVIATION))


## The live model in its dying animation: legs still, it falls the way its corpse lies (or, with
## no pose for it, rolls onto its side and sinks).
func _collapse(d: Dying) -> Transform3D:
	var t := _smooth01(d.age / d.seconds)
	var xf := d.xform
	if d.heap:
		# Slumps flat and spreads a little, as the spawner's corpse picture lies.
		xf.basis = xf.basis * Basis.from_scale(Vector3(1.0 + 0.15 * t, 1.0 - 0.85 * t, 1.0 + 0.15 * t))
		return xf
	var fall := _fall(d.corpse if d.corpse != "" else d.name + "-corpse")
	if not fall.is_empty():
		# Falling: slow to start, quick at the end (Factorio's dying frames are much the same).
		var f := _smooth01(d.age / d.seconds) * clampf(d.age / d.seconds, 0.0, 1.0)
		var k := _scale_of(d.name)
		var at: Vector3 = fall["at"] * k
		var to: Vector3 = fall["to"] * k
		var turn := Basis(Quaternion.IDENTITY.slerp(fall["turn"], f)).scaled(Vector3.ONE * lerpf(1.0, fall["scale"], f))
		return xf * Transform3D(turn, at.lerp(to, f) - turn * at)
	var side := 1.0 if int(d.phase * 7.0) % 2 == 0 else -1.0
	xf.basis = Basis(-xf.basis.z.normalized(), t * 0.6 * side) * xf.basis
	xf.origin.y -= t * 0.12 * _scale_of(d.name)
	return xf


## Factorio's dying sheets take turns with four falls round the 16 directions (direction d falls the
## (d mod 4)th way), each with its corpse model ("-corpse", "-corpse-1" to "-corpse-3",
## tools/models/creature_pose.py): the corpse goes by the direction it died facing, turned to it.
func _pick_corpse(d: Dying) -> void:
	var yaw := d.xform.basis.get_euler().y
	var dir := posmod(roundi(-yaw / TAU * 16.0), 16)
	var variant := dir % 4
	var model := d.name + "-corpse" + ("" if variant == 0 else "-%d" % variant)
	if not _has_model(model):
		model = d.name + "-corpse"
	d.corpse = model
	var origin := d.xform.origin
	d.xform = Transform3D(Basis(Vector3.UP, -float(dir) / 16.0 * TAU), origin)


## How a creature (any tier) falls into its corpse: {at, to: Vector3, turn: Quaternion, scale}
## at the family's size, or {} without a fitted pose.
func fall_of(name: String) -> Dictionary:
	return _fall(name + "-corpse")


## The same for a corpse model (a tier's, or a variant: "small-biter-corpse-2").
func _fall(corpse: String) -> Dictionary:
	if not _falls_loaded:
		_falls_loaded = true
		var text := FileAccess.get_file_as_string(POSES_PATH)
		var parsed = JSON.parse_string(text) if text != "" else null
		if parsed is Dictionary:
			for key in parsed:
				var e: Dictionary = parsed[key]
				var a: Array = e.get("at", [0, 0, 0])
				var b: Array = e.get("to", [0, 0, 0])
				var q: Array = e.get("turn", [0, 0, 0, 1])
				_falls[key] = {"at": Vector3(float(a[0]), float(a[1]), float(a[2])),
					"to": Vector3(float(b[0]), float(b[1]), float(b[2])),
					"turn": Quaternion(float(q[0]), float(q[1]), float(q[2]), float(q[3])).normalized(),
					"scale": float(e.get("scale", 1.0))}
	var model := CreatureModels.base_model(corpse)
	var found = _falls.get(model if model != "" else corpse)
	return found if found is Dictionary else {}


## A quick jaw/body strike over the bite animation: ease back, snap forward, recoil and rest.
func _bite_pulse(phase: float) -> float:
	if phase < 0.2:
		return -0.25 * _smooth01(phase / 0.2)
	if phase < 0.35:
		return lerpf(-0.25, 1.0, _smooth01((phase - 0.2) / 0.15))
	if phase < 0.45:
		return 1.0
	if phase < 0.75:
		return 1.0 - _smooth01((phase - 0.45) / 0.3)
	return 0.0


## Rearing to spit: up over the first part, held at the top, down at the end.
func _spit_pulse(phase: float) -> float:
	return _smooth01(phase / 0.4) if phase < 0.5 else _smooth01((1.0 - phase) / 0.4)


func _smooth01(value: float) -> float:
	var t := clampf(value, 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


func _scale_of(name: String) -> float:
	var alias = CreatureModels.ALIASES.get(name)
	return float(alias[1]) if alias != null else 1.0


func _has_model(model: String) -> bool:
	if _missing.has(model):
		return false
	if _layers.has(model):
		return true
	if not ModelLibrary.ready(model):
		return false  # being made on a worker thread: drawn once it is
	if ModelLibrary.mesh_for(model) == null:
		_missing[model] = true
		return false
	return true


## The layer of a model's live creatures in one LIVE_CELL square, made when first asked; null while
## the model is still being made.
func _layer(model: String, cell: Vector2i) -> Layer:
	if not _has_model(model):
		return null
	var cells: Dictionary = _layers.get(model, {})
	if cells.is_empty():
		_layers[model] = cells
	var layer: Layer = cells.get(cell)
	if layer == null:
		layer = Layer.new()
		layer.model = model
		layer.cell = cell
		layer.mmi = _new_layer(model)
		layer.mover = _mover_meshes.get(model) != null
		cells[cell] = layer
	return layer


## Room for `n` instances in a layer's MultiMesh and buffer (grown to twice that: it is written whole).
static func _ensure(layer: Layer, n: int) -> void:
	var mm := layer.mmi.multimesh
	if mm.instance_count >= n and layer.buffer.size() == mm.instance_count * 16:
		return
	var count := maxi(mm.instance_count, 8)
	while count < n:
		count *= 2
	if count != mm.instance_count:
		mm.instance_count = count  # empties the MultiMesh: written again whole (_flush)
		layer.shown = -1
	layer.buffer.resize(count * 16)
	layer.dirty = true


func _push(model: String, xf: Transform3D, phase: float, gait: float) -> void:
	var layer := _layer(model, _cell_of(xf.origin))
	if layer == null:
		return
	# Appended in place: taking the packed array out into a variable and putting it back copied the
	# whole buffer for every creature.
	_append_instance(layer.posed, xf, phase, gait)
	layer.low = layer.low.min(xf.origin)
	layer.high = layer.high.max(xf.origin)
	if _stepping != null:
		_stepping.drawn = layer.posed.slice(layer.posed.size() - 16)
		_stepping.drawn_model = model
		_stepping.drawn_at = xf.origin


## A skipped creature, drawn as it was last.
func _push_drawn(c: Creature) -> void:
	var layer := _layer(c.drawn_model, _cell_of(c.drawn_at))
	if layer == null:
		return
	_append_drawn(layer.posed, c.drawn)
	layer.low = layer.low.min(c.drawn_at)
	layer.high = layer.high.max(c.drawn_at)


## Appends `drawn` to the bucket's buffer in place (as _append_instance does).
static func _append_drawn(b: PackedFloat32Array, drawn: PackedFloat32Array) -> void:
	b.append_array(drawn)


## MultiMesh buffer: a 3x4 transform (rows) then the custom data.
static func _append_instance(b: PackedFloat32Array, xf: Transform3D, phase: float, gait: float) -> void:
	var x := xf.basis.x
	var y := xf.basis.y
	var z := xf.basis.z
	var o := xf.origin
	b.append_array([x.x, y.x, z.x, o.x, x.y, y.y, z.y, o.y, x.z, y.z, z.z, o.z, phase, gait, 0.0, 1.0])


func _new_layer(model: String) -> MultiMeshInstance3D:
	var mmi := MultiMeshInstance3D.new()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	var mesh: Mesh = _mover_meshes.get(model)
	if mesh == null:
		mesh = ModelLibrary.mesh_for(model)
	ModelLods.request_view_lods(mesh as ArrayMesh)
	mm.mesh = ModelLods.lod_copy(mesh) if ModelLods.lod_copy(mesh) != null else mesh
	mmi.multimesh = mm
	add_child(mmi)
	return mmi


## Swaps a layer to its mesh's copy with view LODs once that is made (ModelLods.request_view_lods);
## true once it has it.
static func _use_lods(mmi: MultiMeshInstance3D) -> bool:
	var copy := ModelLods.lod_copy(mmi.multimesh.mesh)
	if copy != null:
		mmi.multimesh.mesh = copy
		return true
	return false


## Each layer's walkers (when they changed) and this frame's posed creatures to its MultiMesh, its
## bounds, level of detail and shadows; layers left empty LIVE_IDLE seconds are freed.
func _flush(focus: Vector3, delta := 0.0) -> void:
	# A layer of walkers only that nothing changed in is left alone until the focus moves LIVE_MOVED
	# tiles (its shadows go by the distance from the focus), a layer still waiting for its view LODs
	# looked at again twice a second: a wave spread over the map keeps a hundred layers, and running
	# with exoskeletons the focus moves a tile every couple of frames.
	var moved := focus.distance_squared_to(_flushed_at) > LIVE_MOVED * LIVE_MOVED
	if moved:
		_flushed_at = focus
	var lod_beat := Engine.get_process_frames() % 30 == 0
	# Layers left empty (a wave walking on leaves dozens behind) are freed after LIVE_IDLE, looked
	# for once a second.
	var sweep := _clock >= _idle_sweep_at
	if sweep:
		_idle_sweep_at = _clock + 1.0
	var gone: Array = []
	layers_seen = 0
	for model in _layers:
		var layers: Dictionary = _layers[model]
		for cell in layers:
			var layer: Layer = layers[cell]
			var posed := layer.posed.size() / 16
			if layer.still and posed == 0 and not layer.dirty and not moved and not sweep and (layer.lods or not lod_beat):
				continue
			layers_seen += 1
			var mm := layer.mmi.multimesh
			var walkers := layer.walkers.size()
			var total := walkers + posed
			if total == 0:
				layer.dirty = false
				if layer.shown != 0:
					mm.visible_instance_count = 0
					layer.shown = 0
					layer.idle_since = _clock
				layer.still = true
				if _clock - layer.idle_since > LIVE_IDLE:
					gone.append([layers, cell])
				continue
			_ensure(layer, total)
			if posed > 0:
				var b := layer.buffer.slice(0, walkers * 16)
				b.append_array(layer.posed)
				b.resize(mm.instance_count * 16)
				RenderingServer.multimesh_set_buffer(mm.get_rid(), b)
				layer.dirty = false
			elif layer.dirty:
				RenderingServer.multimesh_set_buffer(mm.get_rid(), layer.buffer)
				layer.dirty = false
			if layer.shown != total:
				mm.visible_instance_count = total
				layer.shown = total
			# Walkers are drawn within a few tiles of their square (a step behind their newest
			# position, which put them in it); posed ones are bounded by where they are this frame (a
			# behemoth reaches a few tiles from its origin). Out of view or out of a shadow split, a
			# layer isn't drawn there.
			var box := AABB()
			if walkers > 0:
				box = AABB(Vector3(cell.x * LIVE_CELL - 6.0, -2.0, cell.y * LIVE_CELL - 6.0), Vector3(LIVE_CELL + 12.0, 12.0, LIVE_CELL + 12.0))
			if posed > 0:
				var low: Vector3 = layer.low - Vector3(5.0, 2.0, 5.0)
				var high: Vector3 = layer.high + Vector3(5.0, 8.0, 5.0)
				var pb := AABB(low, high - low)
				box = box.merge(pb) if walkers > 0 else pb
				layer.posed.clear()
				layer.low = Vector3.INF
				layer.high = -Vector3.INF
			if box != layer.box:
				layer.box = box
				layer.mmi.custom_aabb = box
			if not layer.lods:
				layer.lods = _use_lods(layer.mmi)
			layer.still = posed == 0
			var centre := (Vector2(cell) + Vector2(0.5, 0.5)) * LIVE_CELL
			var near := centre.distance_to(Vector2(focus.x, focus.z)) <= LIVE_SHADOW_RANGE + LIVE_CELL * 0.71
			var cast := GeometryInstance3D.SHADOW_CASTING_SETTING_ON if near else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			if layer.cast != cast:
				layer.cast = cast
				layer.mmi.cast_shadow = cast
	for g in gone:
		var layers: Dictionary = g[0]
		(layers[g[1]] as Layer).mmi.queue_free()
		layers.erase(g[1])
