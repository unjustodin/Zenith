extends Node3D
## Throwing what's in the cursor, as Factorio does with grenades, cliff explosives, poison, slowdown
## and robot capsules: the throw range is drawn as a circle round the character and the blast
## area at the cursor (red when out of range); a left click throws (`throw`), holding it keeps
## throwing at the capsule's pace. Fish and other use-on-self capsules are eaten on a click.

const Visuals := preload("res://scripts/world/visuals.gd")

## Seconds between throws while the button is held (a grenade's cooldown is 30 ticks).
const REPEAT := 0.5
const SEGMENTS := 64

## Where the last capsule went and when (msec), so weapon_fx.gd lands it there on its arc.
static var last_target := Vector2(INF, INF)
static var last_msec := -100000

## player_input (hud, avatar); untyped to keep the scripts apart.
var pi: Node

var _mesh := ImmediateMesh.new()
var _mi := MeshInstance3D.new()
var _ok_mat := Visuals.ghost_material(Color(1.0, 1.0, 1.0, 0.55))
var _bad_mat := Visuals.ghost_material(Color(1.0, 0.3, 0.25, 0.6))
var _timer := 0.0


func _ready() -> void:
	_mi.mesh = _mesh
	_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mi)
	visible = false


## [action type, range, radius] for a capsule item (`iuse` "c"), or [].
func use_of(item: String) -> Array:
	var u: Dictionary = pi.hud.ui.model.item_uses.get(item, {})
	return u.get("c", [])


func in_range(item: String, at: Vector2) -> bool:
	var use := use_of(item)
	if use.is_empty() or pi.avatar == null or str(use[0]) == "use-on-self":
		return true
	var r := float(use[1])
	return r <= 0.0 or (pi.avatar.ground_position() as Vector2).distance_to(at) <= r + 0.5


func update_preview(item: String, has_ground: bool, ground: Vector2) -> void:
	var use := use_of(item)
	visible = has_ground and not use.is_empty() and str(use[0]) != "use-on-self" and pi.avatar != null
	if not visible:
		return
	var centre: Vector2 = pi.avatar.ground_position()
	_mesh.clear_surfaces()
	_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	_ring(centre, float(use[1]))
	var blast := maxf(float(use[2]), 0.5)
	_ring(ground, blast)
	_mesh.surface_end()
	_mi.material_override = _ok_mat if in_range(item, ground) else _bad_mat


func _ring(c: Vector2, r: float) -> void:
	for i in SEGMENTS:
		var a := TAU * i / SEGMENTS
		var b := TAU * (i + 1) / SEGMENTS
		_mesh.surface_add_vertex(Vector3(c.x + cos(a) * r, 0.08, c.y + sin(a) * r))
		_mesh.surface_add_vertex(Vector3(c.x + cos(b) * r, 0.08, c.y + sin(b) * r))


## While the left button is held: throws now and then every REPEAT.
func hold(item: String, ground: Vector2, delta: float) -> void:
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = REPEAT
	if not in_range(item, ground):
		pi.hud.show_message("Out of range")
		return
	Bridge.send({"t": "throw", "item": item, "x": int(ground.x * 256.0), "y": int(ground.y * 256.0)})
	last_target = ground
	last_msec = Time.get_ticks_msec()


func release() -> void:
	_timer = 0.0
