extends Node3D
## The main menu's background, like Factorio's live menu simulations: a small factory drawn by the
## client's own world renderer, with the camera drifting slowly over it. The world is a recording
## of the mock server's starter factory (res://data/menu_world.json, made by
## tools/record_menu_world.py): prototypes, chunks and entities are applied once, and the live
## updates (moving things, items on belts, inserter hands) are replayed in a loop. No server.

const WorldMirror := preload("res://scripts/world/world.gd")
const MoverLayer := preload("res://scripts/world/movers.gd")
const BeltItemLayer := preload("res://scripts/world/belt_items.gd")
const GroundItemLayer := preload("res://scripts/world/ground_items.gd")
const InserterArmLayer := preload("res://scripts/world/inserter_arms.gd")
const Settings := preload("res://scripts/menu/settings.gd")

const DATA := "res://data/menu_world.json"
const LIVE := ["mv", "bi", "ih", "gi"]
const DRIFT_SPEED := 0.035
const FACTORY_TYPES := ["assembling-machine", "furnace", "transport-belt", "inserter", "mining-drill",
	"boiler", "generator", "lab", "container", "electric-pole", "splitter", "underground-belt"]

var world: WorldMirror
var camera := Camera3D.new()

var _movers: MoverLayer
var _belt_items: BeltItemLayer
var _arms: InserterArmLayer
var _ground_items: GroundItemLayer
var _live: Array = []  # [seconds, message], in order
var _length := 1.0
var _clock := 0.0
var _next := 0
var _loop := 0
var _tick_span := 0
var _center := Vector2.ZERO
var _time := 0.0
var _env: Environment


func _ready() -> void:
	_build_environment()
	world = WorldMirror.new()
	world.name = "MenuWorld"
	world.view_radius = 2
	add_child(world)
	_movers = MoverLayer.new()
	_movers.protos = world.protos
	add_child(_movers)
	_belt_items = BeltItemLayer.new()
	_belt_items.protos = world.protos
	add_child(_belt_items)
	_arms = InserterArmLayer.new()
	_arms.protos = world.protos
	_arms.world = world
	add_child(_arms)
	_ground_items = GroundItemLayer.new()
	_ground_items.protos = world.protos
	add_child(_ground_items)

	camera.fov = 35.0
	camera.near = 0.5
	camera.far = 1000.0
	add_child(camera)
	camera.make_current()
	_load()


func _load() -> void:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(DATA)) if FileAccess.file_exists(DATA) else null
	if not (parsed is Dictionary):
		return
	var center: Array = parsed.get("center", [0, 0])
	_center = Vector2(float(center[0]), float(center[1]))
	world.set_focus(_center)
	world._update_subscription(0.0)  # makes the chunk views; nothing is sent without a server
	var first_tick := -1
	var last_tick := 0
	for msg in parsed.get("messages", []):
		if not (msg is Dictionary):
			continue
		var t := str(msg.get("t", ""))
		if LIVE.has(t):
			_live.append([float(msg.get("dt", 0.0)), msg])
			_length = maxf(_length, float(msg.get("dt", 0.0)))
			var k := int(msg.get("k", 0))
			if first_tick < 0:
				first_tick = k
			last_tick = maxi(last_tick, k)
		else:
			world.handle(msg)
	_tick_span = maxi(1, last_tick - maxi(first_tick, 0) + 6)
	_length += 0.1
	_center = _factory_center(_center)


## Where the buildings are: the camera circles them rather than the trees.
func _factory_center(fallback: Vector2) -> Vector2:
	var sum := Vector2.ZERO
	var n := 0
	for r: WorldMirror.Rec in world.entities.values():
		var proto = world.protos.entity(r.proto_id)
		if proto != null and FACTORY_TYPES.has(proto.type):
			sum += r.pos
			n += 1
	return sum / n if n > 0 else fallback


func _process(delta: float) -> void:
	world._rebuild_dirty()
	_time += delta
	_clock += delta
	while _next < _live.size() and float(_live[_next][0]) <= _clock:
		_replay(_live[_next][1])
		_next += 1
	if _clock >= _length:
		_clock -= _length
		_next = 0
		_loop += 1
	# A slow drift across the factory, turning a little, like a camera on a long crane.
	var a := _time * DRIFT_SPEED
	var focus := _center + Vector2(sin(a) * 9.0, sin(a * 0.7 + 1.0) * 5.0 - 3.0)
	var yaw := deg_to_rad(35.0 + 20.0 * sin(a * 0.5))
	var turn := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, -deg_to_rad(42.0))
	camera.transform = Transform3D(turn, Vector3(focus.x, 0.0, focus.y) + turn * Vector3(0.0, 0.0, 38.0))
	world.set_focus(focus)


## A live update from the recording, its tick moved on by whole loops so the layers see time pass.
func _replay(msg: Dictionary) -> void:
	var copy := msg.duplicate()
	copy["k"] = int(msg.get("k", 0)) + _loop * _tick_span
	match str(msg.get("t", "")):
		"mv":
			_movers.handle(copy)
		"bi":
			_belt_items.handle(copy)
		"ih":
			_arms.handle(copy)
		"gi":
			_ground_items.handle(copy)


func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.55, 0.62, 0.68)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.78, 0.78, 0.8)
	env.ambient_light_energy = 0.6
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.ssao_enabled = bool(Settings.get_value("graphics", "ssao"))
	_env = env
	Settings.apply_environment(env)
	Settings.listen(_on_setting)
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)
	var sun := DirectionalLight3D.new()
	# Late afternoon: long shadows across the factory.
	sun.rotation_degrees = Vector3(-35.0, -55.0, 0.0)
	sun.light_energy = 1.15
	sun.light_color = Color(1.0, 0.95, 0.86)
	sun.shadow_enabled = Settings.shadow_size() > 0
	sun.directional_shadow_max_distance = 120.0
	add_child(sun)


## Brightness, contrast and saturation change as they are dragged in Settings.
func _on_setting(section: String, _key: String) -> void:
	if section == "graphics" and _env != null and is_inside_tree():
		Settings.apply_environment(_env)
		_env.ssao_enabled = bool(Settings.get_value("graphics", "ssao"))


func _exit_tree() -> void:
	Settings.unlisten(_on_setting)
