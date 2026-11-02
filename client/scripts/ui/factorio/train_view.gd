extends Control
## A train card's picture, as Factorio's train overview and train stop windows show one: a small
## live view of the train's surroundings from straight above, north up. It is the client's own 3D
## world seen through an orthographic camera in a SubViewport that shares the main world; where
## the client hasn't loaded the world (a train far from the character), the map's chart shows
## through underneath (map_cache.gd).
##
## Many cards can be open at once, so each view renders only while it is on screen, at REFRESH
## seconds apart (UPDATE_ONCE), and at most BUDGET views render in the same frame. A card makes its
## 3D view only once the train is in the client's world (making one per card made the
## overview slow to open); for a train far away it asks the map cache for the chart around it.

const Kit := preload("res://scripts/ui/factorio/kit.gd")

## Seconds between a view's frames.
const REFRESH := 0.5
## Views rendered in one frame, over all cards.
const BUDGET := 3
## Tiles the view shows from top to bottom.
const SPAN := 32.0

## The train's locomotive (a mover the client may be drawing), and where the mod last said the
## train was (tiles). The view follows the mover while there is one, else glides between the
## mod's positions.
var unit := 0
var target := Vector2.ZERO
## map_cache.gd, for the chart under the view, or null.
var cache = null
## movers.gd, for the locomotive's live position, or null.
var movers = null

var _at := Vector2.ZERO
var _placed := false
var _vp: SubViewport
var _cam: Camera3D
var _timer := 0.0
var _marker := Control.new()
var _live_now := false
var _has_view := false
var _asked_at := -1e9

static var _frame := -1
static var _used := 0


func _init() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ready() -> void:
	# The client draws movers only near the character: elsewhere a marker shows where the train is.
	_marker.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_marker.draw.connect(func() -> void:
		if not _live_now:
			var c := _marker.size * 0.5
			var r := float(Kit.px(5))
			_marker.draw_circle(c, r + Kit.px(2), Color(0, 0, 0, 0.7))
			_marker.draw_circle(c, r, Color8(255, 166, 0)))
	add_child(_marker)
	_timer = randf() * REFRESH  # cards opened together don't all render in the same frame


## The 3D view, made the first time the train is in the client's world.
func _make_view() -> void:
	_vp = SubViewport.new()
	_cam = Camera3D.new()
	var holder := SubViewportContainer.new()
	holder.stretch = true
	holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(holder)
	_vp.transparent_bg = true
	_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_vp.world_3d = get_viewport().world_3d
	_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	_cam.size = SPAN
	_cam.near = 1.0
	_cam.far = 400.0
	_cam.current = true
	_vp.add_child(_cam)
	holder.add_child(_vp)
	move_child(holder, 0)  # under the marker
	_has_view = true


## Sets the train to show (the card's data from `trl`).
func show_train(new_unit: int, at: Vector2) -> void:
	unit = new_unit
	target = at
	if not _placed:
		_at = at
		_placed = true


func _live() -> Variant:
	if movers != null and is_instance_valid(movers) and unit != 0:
		var p = movers.position_of(unit)
		if p is Vector3:
			return Vector2((p as Vector3).x, (p as Vector3).z)
	return null


func _on_screen() -> bool:
	if not is_visible_in_tree() or size.x <= 0.0:
		return false
	return get_viewport_rect().intersects(get_global_rect())


func _process(delta: float) -> void:
	var live = _live()
	if (live != null) != _live_now:
		_live_now = live != null
		_marker.queue_redraw()
	if live != null:
		_at = live
	else:
		_at = _at.lerp(target, clampf(delta * 2.0, 0.0, 1.0))
	_timer -= delta
	if _timer > 0.0 or not _on_screen():
		return
	if live == null:
		# Far away: the chart under the marker, asked for now and then.
		_timer = REFRESH
		_ask_chart()
		queue_redraw()
		return
	if not _has_view:
		_make_view()
	var f := Engine.get_process_frames()
	if f != _frame:
		_frame = f
		_used = 0
	if _used >= BUDGET:
		return
	_used += 1
	_timer = REFRESH
	# Straight down, north (-Z) at the top of the picture.
	_cam.transform = Transform3D(Basis.from_euler(Vector3(-PI / 2.0, 0.0, 0.0)), Vector3(_at.x, 120.0, _at.y))
	_cam.size = SPAN
	_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	queue_redraw()


## Asks the map cache for the chart around the train (at most every 10 s).
func _ask_chart() -> void:
	if cache != null and cache.has_method("ask_spot") and Time.get_ticks_msec() - _asked_at > 10000.0:
		_asked_at = Time.get_ticks_msec()
		var chunk := Vector2i(floori(_at.x / 32.0), floori(_at.y / 32.0))
		cache.ask_spot(Rect2i(chunk - Vector2i.ONE, Vector2i(3, 3)))


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	draw_rect(r, Color8(18, 20, 16))
	if cache != null and is_instance_valid(cache) and cache.has_method("draw"):
		cache.draw(self, r, _at, size.y / SPAN)
