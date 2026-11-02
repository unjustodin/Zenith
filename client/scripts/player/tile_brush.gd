extends Node3D
## Placing tiles from the cursor, as Factorio does with stone brick, concrete, landfill, foundation
## and the rest: a square brush (Numpad + / -: Factorio's larger / smaller tile area) drawn at the
## cursor, green where the tile can go, red where it can't (the wrong ground, out of reach) and
## blue as ghosts (Shift, none left, remote view); holding the left button paints, the right button
## mines placed tiles back. R turns hazard concrete's stripes. The mod lays the tiles
## (`tile`, `tile_mine`); the world redraws them from `tiles`.

const WorldMirror := preload("res://scripts/world/world.gd")
const Visuals := preload("res://scripts/world/visuals.gd")

const MAX_SIZE := 32
const REPEAT := 0.1
## The character's build_distance (player_input.gd's too).
const BUILD_REACH := 10.0
const COLORS := {"ok": Color(0.35, 1.0, 0.45, 0.35), "bad": Color(1.0, 0.3, 0.25, 0.35), "ghost": Color(0.45, 0.65, 1.0, 0.35),
	"mine": Color(1.0, 0.75, 0.3, 0.3)}

## The player_input node (world, hud, avatar, ground); untyped to keep the two scripts apart.
var pi: Node
## Brush size in tiles (Factorio's tile area), kept while the client runs.
var size := 1
## Hazard concrete's other stripe direction (R).
var alt := false

var _mm := MultiMesh.new()
var _mmi := MultiMeshInstance3D.new()
var _timer := 0.0
var _last_paint := Vector2(INF, INF)


func _ready() -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2(0.96, 0.96)
	quad.orientation = PlaneMesh.FACE_Y
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.use_colors = true
	_mm.mesh = quad
	_mmi.multimesh = _mm
	var m := Visuals.ghost_material(Color.WHITE)
	m.vertex_color_use_as_albedo = true
	_mmi.material_override = m
	_mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mmi)
	visible = false


## The held item's tile use (`iuse` "t"): [tile name, other direction's tile, {tile id: true}] or [].
func use_of(item: String) -> Array:
	var u: Dictionary = pi.hud.ui.model.item_uses.get(item, {})
	return u.get("t", [])


func resize(steps: int) -> void:
	size = clampi(size + steps, 1, MAX_SIZE)
	pi.hud.show_message("Tile area: %d × %d" % [size, size])


## The tile positions under a brush of `n` at `at`: odd sizes centre on the tile, even ones on the
## nearest tile corner (the mod's tiles.lua brush()).
static func brush(at: Vector2, n: int) -> Array[Vector2i]:
	var x0: int
	var y0: int
	if n % 2 == 1:
		x0 = floori(at.x) - (n - 1) / 2
		y0 = floori(at.y) - (n - 1) / 2
	else:
		x0 = floori(at.x + 0.5) - n / 2
		y0 = floori(at.y + 0.5) - n / 2
	var out: Array[Vector2i] = []
	for dy in n:
		for dx in n:
			out.append(Vector2i(x0 + dx, y0 + dy))
	return out


## Each brush tile's state for the preview: "ok", "bad", "ghost", or "" (already that tile).
func tile_states(item: String, at: Vector2, ghost_mode: bool) -> Array:
	var use := use_of(item)
	var out: Array = []
	if use.is_empty():
		return out
	var protos = pi.world.protos
	var want := str(use[1]) if alt and str(use[1]) != "" else str(use[0])
	var on: Dictionary = use[2]
	var reach_from: Vector2 = pi.avatar.ground_position() if pi.avatar != null else at
	for t in brush(at, size):
		var id: int = pi.world.tile_at(t.x, t.y)
		var state := "ok"
		if id >= 0 and id < protos.tile_names.size() and protos.tile_names[id] == want:
			state = ""
		elif id >= 0 and not on.has(id):
			state = "bad"
		elif ghost_mode:
			state = "ghost"
		elif (Vector2(t) + Vector2(0.5, 0.5)).distance_to(reach_from) > BUILD_REACH + 1.5:
			state = "bad"
		out.append([t, state])
	return out


## Draws the brush at the cursor for a held tile item (or hides it). Called every frame.
func update_preview(item: String, has_ground: bool, ground: Vector2, ghost_mode: bool, mining: bool) -> void:
	visible = has_ground and not use_of(item).is_empty()
	if not visible:
		return
	var states := tile_states(item, ground, ghost_mode)
	_mm.instance_count = states.size()
	for i in states.size():
		var t: Vector2i = states[i][0]
		var state: String = states[i][1]
		_mm.set_instance_transform(i, Transform3D(Basis.IDENTITY, Vector3(t.x + 0.5, 0.05, t.y + 0.5)))
		var c: Color = COLORS["mine"] if mining else COLORS.get(state, Color(1, 1, 1, 0.12))
		_mm.set_instance_color(i, c)


## Holding the left button paints where the brush moved to (and every REPEAT while it stays).
func paint(item: String, ground: Vector2, ghost_mode: bool, delta: float) -> void:
	_timer -= delta
	var tile := Vector2(floorf(ground.x), floorf(ground.y))
	if tile == _last_paint and _timer > 0.0:
		return
	_last_paint = tile
	_timer = REPEAT * 3.0
	var cmd := {"t": "tile", "item": item, "x": int(ground.x * 256.0), "y": int(ground.y * 256.0), "n": size}
	if ghost_mode:
		cmd["ghost"] = 1
	if alt:
		cmd["r"] = 1
	Bridge.send(cmd)


## Holding the right button with a tile in hand mines the placed tiles under the brush.
func mine(ground: Vector2, delta: float) -> void:
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = REPEAT
	Bridge.send({"t": "tile_mine", "x": int(ground.x * 256.0), "y": int(ground.y * 256.0), "n": size})


func reset_drag() -> void:
	_last_paint = Vector2(INF, INF)
	_timer = 0.0


## For tests: how many brush tiles are drawn, and how many in each state.
func preview_counts() -> Dictionary:
	var out := {"shown": _mm.instance_count if visible else 0}
	return out
