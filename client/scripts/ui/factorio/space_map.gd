extends Control
## Factorio 2.1's space map: the remote view of the whole solar system, over the full screen inside
## the "Remote view" frame (remote_frame.gd keeps its title bar, the Surfaces panel with "Space map"
## chosen, and the right column). The star in the middle, each planet's orbit round it (grey;
## orange under the mouse), the planets and other space locations with Factorio's star map pictures
## at their prototype positions and sizes (`magnitude`), their names where `label_orientation`
## puts them, the routes between them, and the force's platforms with Factorio's star map platform
## sprites: parked by the planet they are stopped at (stacked when several), or along their route
## as far as they have come (`plat`). Locked places are dark.
##
## Mouse, as in Factorio's remote view: drag to move the view, the wheel zooms round the mouse. A
## click on a planet shows it in remote view (show_place); a click on a platform selects it (its
## panel shows under the tag icons, platform_selected), a second click looks at it. From the mod's
## `smap` (asked for on opening) and `plat` (platform_panel.gd).

const Kit := preload("res://scripts/ui/factorio/kit.gd")
const LocaleNames := preload("res://scripts/world/locale_names.gd")
const SpacePanels := preload("res://scripts/ui/factorio/space_panels.gd")
const GuiAssets := preload("res://scripts/ui/factorio/gui_assets.gd")

signal close_requested
## A place to look at: a planet's name, or a platform's index (planet "").
signal show_place(planet: String, platform: int)
## The platform clicked (its index), or 0 when the selection goes.
signal platform_selected(index: int)

## Star map units a planet of magnitude 1 is across.
const PLANET_SIZE := 3.2
## The star's size in star map units.
const STAR_SIZE := 9.0
const REFRESH := 0.5
## utility-constants.lua's starmap_orbit_*_color (gui_color.grey, orange, light orange; disabled).
const ORBIT := Color(0.5, 0.5, 0.5, 0.55)
const ORBIT_HOVERED := Color(0.98, 0.66, 0.22)
const ORBIT_DISABLED := Color(0.25, 0.25, 0.25, 0.6)
const ROUTE := Color(0.62, 0.66, 0.72, 0.32)
const ROUTE_HOVERED := Color(0.98, 0.66, 0.22, 0.9)
const ZOOM_STEP := 1.2

var model
## platform_panel.gd, for the platforms (`plat`).
var platforms: Control = null
## The selected platform's index, or 0.
var selected := 0

## View: the star map point in the middle of the screen, and screen pixels per star map unit.
var view_center := Vector2.ZERO
var view_scale := 0.0
var _hover := {}  # {"planet": name}, {"platform": index} or {"route": index in space_connections}
var _stars := PackedVector3Array()
var _dragging := false
var _dragged := false
var _press_at := Vector2.ZERO
var _timer := 0.0
var _textures := {}


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in 700:
		_stars.append(Vector3(rng.randf(), rng.randf(), rng.randf_range(0.15, 1.0)))
	model.space_map_changed.connect(_on_map_changed)


func is_open() -> bool:
	return visible


func open(on: bool) -> void:
	if on == visible:
		return
	visible = on
	_dragging = false
	if on:
		model.request_space_map()
		view_scale = 0.0  # fit on the first draw
		queue_redraw()
	elif selected != 0:
		select(0)


func select(index: int) -> void:
	selected = index
	platform_selected.emit(index)
	queue_redraw()


func _on_map_changed() -> void:
	if visible:
		if view_scale <= 0.0:
			_fit()
		queue_redraw()


func _process(delta: float) -> void:
	if not visible:
		return
	_timer -= delta
	if _timer <= 0.0:
		_timer = REFRESH
		queue_redraw()  # platforms move


# --- projection --------------------------------------------------------------------------------

## The whole system in view, clear of the frame's panels.
func _fit() -> void:
	if model.space_locations.is_empty() or size.x <= 0.0:
		return
	var rect := Rect2(Vector2.ZERO, Vector2.ZERO)
	for loc in model.space_locations:
		rect = rect.expand(loc["position"])
	rect = rect.grow(PLANET_SIZE * 1.5)
	var area := Rect2(Vector2(Kit.px(290), Kit.px(60)), size - Vector2(Kit.px(290 + 290), Kit.px(60 + 140)))
	if area.size.x < size.x * 0.3 or area.size.y < size.y * 0.3:
		area = Rect2(Vector2.ZERO, size)  # a small window: all of it
	view_scale = minf(area.size.x / maxf(rect.size.x, 1.0), area.size.y / maxf(rect.size.y, 1.0))
	view_center = rect.get_center() - (area.get_center() - size * 0.5) / view_scale


func to_screen(p: Vector2) -> Vector2:
	if view_scale <= 0.0:
		_fit()
	return size * 0.5 + (p - view_center) * view_scale


func to_map(screen: Vector2) -> Vector2:
	return view_center + (screen - size * 0.5) / view_scale


func _location(name: String) -> Dictionary:
	for loc in model.space_locations:
		if loc["name"] == name:
			return loc
	return {}


func _radius(loc: Dictionary) -> float:
	var m := float(loc.get("magnitude", 1.0))
	var units := PLANET_SIZE * m * (1.0 if loc["type"] == "planet" else 0.7)
	return maxf(units * view_scale * 0.5, float(Kit.px(10)))


func _texture(path: String) -> Texture2D:
	if not _textures.has(path):
		_textures[path] = GuiAssets.data_sprite(path)
	return _textures[path]


func _planet_texture(name: String) -> Texture2D:
	for path in ["space-age/graphics/icons/starmap-%s.png", "space-age/graphics/icons/starmap-planet-%s.png",
			"base/graphics/icons/starmap-planet-%s.png"]:
		var t := _texture(path % name)
		if t != null:
			return t
	return SpacePanels.planet_icon(name)


## One of Factorio's star map platform sprites (utility-sprites.lua): kind "moving", "stopped" or
## "stacked", state 0 normal, 1 hovered, 2 clicked.
func _platform_sprite(kind: String, state: int) -> Texture2D:
	var key := "pf/%s/%d" % [kind, state]
	if _textures.has(key):
		return _textures[key]
	var sheet := _texture("core/graphics/icons/starmap-platform-%s-states.png" % kind)
	var out: Texture2D = null
	if sheet != null:
		var h: int = {"moving": 37, "stopped": 33, "stacked": 54}[kind]
		var a := AtlasTexture.new()
		a.atlas = sheet
		a.region = Rect2(0, h * state, 54, h)
		out = a
	_textures[key] = out
	return out


# --- drawing ------------------------------------------------------------------------------------

func _draw() -> void:
	if view_scale <= 0.0:
		_fit()
	draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0))
	for s in _stars:
		var c := Color(1, 1, 1, s.z * 0.75)
		var at := Vector2(s.x * size.x, s.y * size.y)
		if s.z > 0.9:
			draw_rect(Rect2(at, Vector2(2, 2)), c)
		else:
			draw_rect(Rect2(at, Vector2(1, 1)), c)
	if model.space_locations.is_empty() or view_scale <= 0.0:
		var f := Kit.font("regular")
		var text := "Asking the game for the solar system..."
		var w := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, Kit.px(16)).x
		draw_string(f, Vector2((size.x - w) * 0.5, size.y * 0.5), text, HORIZONTAL_ALIGNMENT_LEFT, -1, Kit.px(16), Kit.DISABLED_TEXT)
		return
	var sun := to_screen(Vector2.ZERO)
	var star := _texture("core/graphics/icons/starmap-star.png")
	var star_r := STAR_SIZE * view_scale * 0.5
	if star != null:
		draw_texture_rect(star, Rect2(sun - Vector2(star_r, star_r), Vector2(star_r, star_r) * 2.0), false)
	else:
		draw_circle(sun, star_r * 0.4, Color(1.0, 0.85, 0.4))
	# Orbits round the star.
	for loc in model.space_locations:
		if not loc.get("orbit", true):
			continue
		var r := (loc["position"] as Vector2).length() * view_scale
		var col := ORBIT if loc["unlocked"] else ORBIT_DISABLED
		if _hover.get("planet", "") == loc["name"]:
			col = ORBIT_HOVERED
		draw_arc(sun, r, 0.0, TAU, maxi(64, int(r / 3.0)), col, maxf(1.0, Kit.px(1.5)), true)
	# Routes between places, each with its distance at its middle.
	var small := Kit.font("default")
	var small_fs := Kit.px(13)
	for i in model.space_connections.size():
		var ends := _route_ends(i)
		if ends.is_empty():
			continue
		var c: Dictionary = model.space_connections[i]
		var open := bool(_location(c["from"])["unlocked"]) and bool(_location(c["to"])["unlocked"])
		var col := ROUTE if open else Color(ROUTE, ROUTE.a * 0.35)
		if int(_hover.get("route", -1)) == i:
			col = ROUTE_HOVERED
		_dashed(ends[0], ends[1], col)
		var text := "%s km" % km(int(c["length"]))
		var w := small.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, small_fs).x
		if ends[0].distance_to(ends[1]) > w + Kit.px(24):
			var mid: Vector2 = (ends[0] + ends[1]) * 0.5 + Vector2(-w * 0.5, small_fs * 0.35)
			draw_string_outline(small, mid, text, HORIZONTAL_ALIGNMENT_LEFT, -1, small_fs, Kit.px(3), Color(0, 0, 0, 0.85))
			draw_string(small, mid, text, HORIZONTAL_ALIGNMENT_LEFT, -1, small_fs, Kit.WHITE if open else Kit.DISABLED_TEXT)
	# The places, their names.
	var font := Kit.font("bold")
	var fs := Kit.px(16)
	for loc in model.space_locations:
		var at := to_screen(loc["position"])
		var r := _radius(loc)
		var tint := Color.WHITE if loc["unlocked"] else Color(0.3, 0.3, 0.3)
		var tex := _planet_texture(str(loc["name"]))
		if tex != null:
			draw_texture_rect(tex, Rect2(at - Vector2(r, r), Vector2(r, r) * 2.0), false, tint)
		else:
			draw_circle(at, r, Color(0.45, 0.5, 0.6) * tint)
		var label := LocaleNames.space_location(str(loc["name"]))
		var o := float(loc.get("label", 0.25)) * TAU
		var dir := Vector2(sin(o), -cos(o))
		var w := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var anchor := at + dir * (r + Kit.px(10))
		# Text sits beside the planet on the label's side.
		var pos := anchor + Vector2((dir.x - 1.0) * w * 0.5, fs * 0.35 + dir.y * fs * 0.5)
		var text_col := Kit.WHITE if loc["unlocked"] else Kit.DISABLED_TEXT
		if _hover.get("planet", "") == loc["name"]:
			text_col = ORBIT_HOVERED
		draw_string_outline(font, pos, label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Kit.px(3), Color(0, 0, 0, 0.85))
		draw_string(font, pos, label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, text_col)
	_draw_platforms(font)


## A route's drawn ends on screen (between the two places' edges), or [] when a place is unknown.
func _route_ends(i: int) -> Array:
	if view_scale <= 0.0:
		_fit()
	var c: Dictionary = model.space_connections[i]
	var a := _location(c["from"])
	var b := _location(c["to"])
	if a.is_empty() or b.is_empty():
		return []
	var pa := to_screen(a["position"])
	var pb := to_screen(b["position"])
	var dir := (pb - pa).normalized()
	return [pa + dir * (_radius(a) + Kit.px(6)), pb - dir * (_radius(b) + Kit.px(6))]


## A distance as Factorio writes it on the space map: every digit, thousands spaced (15 000).
static func km(n: int) -> String:
	var digits := str(absi(n))
	var out := ""
	while digits.length() > 3:
		out = " " + digits.right(3) + out
		digits = digits.left(digits.length() - 3)
	return ("-" if n < 0 else "") + digits + out


## Factorio's words for a route's asteroid danger (its `asteroid_spawn_definitions`, 0..1 here).
static func danger_text(d: float) -> String:
	if d < 0.15:
		return "Low"
	if d < 0.5:
		return "Medium"
	return "High"


func _dashed(a: Vector2, b: Vector2, col: Color) -> void:
	var length := a.distance_to(b)
	if length <= 1.0:
		return
	var dir := (b - a) / length
	var dash := float(Kit.px(8))
	var gap := float(Kit.px(6))
	var t := 0.0
	while t < length:
		draw_line(a + dir * t, a + dir * minf(t + dash, length), col, maxf(1.0, Kit.px(2)), true)
		t += dash + gap


## [[screen position, [platform indices], moving], ...]: parked platforms share a spot by their
## planet, travelling ones are where they are along their route.
func _platform_spots() -> Array:
	var out: Array = []
	if view_scale <= 0.0:
		_fit()
	if platforms == null or not is_instance_valid(platforms) or view_scale <= 0.0:
		return out
	var parked := {}
	var keys: Array = platforms.platforms.keys()
	keys.sort()
	for i in keys:
		var p: Dictionary = platforms.platforms[i]
		if p.has("to"):
			var a := _location(str(p.get("from", "")))
			var b := _location(str(p.get("to", "")))
			if a.is_empty() or b.is_empty():
				continue
			var at := to_screen((a["position"] as Vector2).lerp(b["position"], int(p.get("d", 0)) / 1000.0))
			out.append([at, [int(i)], true])
		else:
			var name := str(p.get("loc", ""))
			if not parked.has(name):
				parked[name] = []
			parked[name].append(int(i))
	for name in parked:
		var loc := _location(name)
		if loc.is_empty():
			continue
		# Parked platforms wait at the planet's lower left, outside its picture.
		var o := 0.625 * TAU
		var at := to_screen(loc["position"]) + Vector2(sin(o), -cos(o)) * (_radius(loc) + Kit.px(12))
		out.append([at, parked[name], false])
	return out


func _draw_platforms(font: Font) -> void:
	for spot in _platform_spots():
		var at: Vector2 = spot[0]
		var list: Array = spot[1]
		var kind := "stacked" if list.size() > 1 else ("moving" if spot[2] else "stopped")
		var state := 0
		if list.has(selected) and selected != 0:
			state = 2
		elif list.has(int(_hover.get("platform", -1))):
			state = 1
		var tex := _platform_sprite(kind, state)
		var h := {"moving": 37.0, "stopped": 33.0, "stacked": 54.0}[kind] as float
		var sz := Vector2(Kit.px(27), Kit.px(h * 0.5))
		if tex != null:
			draw_texture_rect(tex, Rect2(at - sz * 0.5, sz), false)
		else:
			draw_rect(Rect2(at - sz * 0.5, sz), [Color(0.8, 0.8, 0.85), ORBIT_HOVERED, Color(1.0, 0.8, 0.5)][state])
		var shown := selected if list.has(selected) else (int(_hover.get("platform", 0)) if list.has(int(_hover.get("platform", -1))) else 0)
		if shown != 0:
			var p: Dictionary = platforms.platforms.get(shown, {})
			var name := SpacePanels.plain(str(p.get("n", "")))
			var pos := at + Vector2(sz.x * 0.5 + Kit.px(4), Kit.px(5))
			draw_string_outline(font, pos, name, HORIZONTAL_ALIGNMENT_LEFT, -1, Kit.px(14), Kit.px(3), Color(0, 0, 0, 0.85))
			draw_string(font, pos, name, HORIZONTAL_ALIGNMENT_LEFT, -1, Kit.px(14), ORBIT_HOVERED if state > 0 else Kit.WHITE)


# --- the mouse ----------------------------------------------------------------------------------

## What is under a screen point: {"platform": index} (the first of a stack, or the selected one in
## it), {"planet": name} or {}.
func pick(pos: Vector2) -> Dictionary:
	if view_scale <= 0.0:
		_fit()
	for spot in _platform_spots():
		if (spot[0] as Vector2).distance_to(pos) <= Kit.px(16):
			var list: Array = spot[1]
			if list.size() > 1 and list.has(selected):
				var next: int = int(list[(list.find(selected) + 1) % list.size()])
				return {"platform": next}
			return {"platform": int(list[0])}
	for loc in model.space_locations:
		if to_screen(loc["position"]).distance_to(pos) <= _radius(loc) + Kit.px(4):
			return {"planet": str(loc["name"])}
	for i in model.space_connections.size():
		var ends := _route_ends(i)
		if not ends.is_empty() and Geometry2D.get_closest_point_to_segment(pos, ends[0], ends[1]).distance_to(pos) <= Kit.px(6):
			return {"route": i}
	return {}


func _gui_input(event: InputEvent) -> void:
	var motion := event as InputEventMouseMotion
	if motion != null:
		if _dragging:
			if motion.position.distance_to(_press_at) > Kit.px(4):
				_dragged = true
			view_center -= motion.relative / maxf(view_scale, 0.0001)
			queue_redraw()
		var h := pick(motion.position)
		if h != _hover:
			_hover = h
			queue_redraw()
		accept_event()
		return
	var mb := event as InputEventMouseButton
	if mb == null:
		return
	if mb.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN] and mb.pressed:
		var f := ZOOM_STEP if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / ZOOM_STEP
		zoom_at(mb.position, f)
		accept_event()
		return
	if mb.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_MIDDLE, MOUSE_BUTTON_RIGHT]:
		if mb.pressed:
			_dragging = true
			_dragged = false
			_press_at = mb.position
		else:
			_dragging = false
			if not _dragged and mb.button_index == MOUSE_BUTTON_LEFT:
				click(mb.position)
		accept_event()


## Zooms by `f` keeping the star map point under `at` still.
func zoom_at(at: Vector2, f: float) -> void:
	var before := to_map(at)
	view_scale = clampf(view_scale * f, 0.5, 400.0)
	view_center += before - to_map(at)
	queue_redraw()


## A click: a planet shows it in remote view; a platform is selected, and looked at when clicked again.
func click(at: Vector2) -> void:
	var h := pick(at)
	if h.has("planet"):
		show_place.emit(str(h["planet"]), 0)
	elif h.has("platform"):
		var i := int(h["platform"])
		if i == selected:
			show_place.emit("", i)
		else:
			select(i)
	elif selected != 0:
		select(0)


func _get_tooltip(at: Vector2) -> String:
	var h := pick(at)
	if h.has("planet"):
		var loc := _location(str(h["planet"]))
		var lines: Array = [LocaleNames.space_location(str(h["planet"]))]
		if not loc.get("unlocked", true):
			lines.append("Not discovered yet")
		for c in model.space_connections:
			if c["from"] == h["planet"] or c["to"] == h["planet"]:
				var other := str(c["to"] if c["from"] == h["planet"] else c["from"])
				lines.append("%s: %s km" % [LocaleNames.space_location(other), Kit.count_text(int(c["length"]))])
		return "\n".join(lines)
	if h.has("route"):
		var c: Dictionary = model.space_connections[int(h["route"])]
		return "%s — %s\nDistance: %s km\nAsteroids: %s" % [LocaleNames.space_location(str(c["from"])),
			LocaleNames.space_location(str(c["to"])), km(int(c["length"])), danger_text(float(c.get("danger", 0.0)))]
	if h.has("platform") and platforms != null:
		var p: Dictionary = platforms.platforms.get(int(h["platform"]), {})
		return SpacePanels.plain(str(p.get("n", "")))
	return ""
