extends RefCounted
## The ground's height under the flat Factorio world, drawn only (Factorio itself stays flat).
##
## Off by default: everything sits at y = 0 as before. Something (the Terrain Elevation add-on,
## through api.terrain) gives a height field, a grid of heights in tiles over a square of the
## map; then every shader that draws the world lifts its vertices by the height under them
## (shaders/ground_height.gdshaderinc), and the few things placed on the CPU (the mouse's ground
## point, the camera's focus) ask `at()`. Both read the same grid the same way (bilinear between
## texel centres, 0 outside the square), so a building, the belt beside it and the ground under
## both agree.
##
## Static: one field for the whole client, set on the main thread.

const GLOBAL_TEX := &"f3d_ground"
const GLOBAL_RECT := &"f3d_ground_rect"
const GLOBAL_ON := &"f3d_ground_on"

static var _image: Image
static var _texture: ImageTexture
static var _origin := Vector2.ZERO  # world x, z of the grid's first texel's corner
static var _step := 1.0  # tiles per texel
static var _size := Vector2i.ZERO
static var _on := false


## Sets the field: `heights` an Image of FORMAT_RF (heights in tiles) or FORMAT_RGF (red the
## ground, green the ground without its cliffs' terraces: what cliff models sit on), its first
## texel's corner at `origin` (world x, z), `tiles_per_texel` tiles a texel. Replaces any field
## before it.
static func set_field(heights: Image, origin: Vector2, tiles_per_texel: float) -> void:
	if heights == null or heights.is_empty():
		clear()
		return
	var format := heights.get_format()
	if format != Image.FORMAT_RF and format != Image.FORMAT_RGF:
		heights = heights.duplicate()
		heights.convert(Image.FORMAT_RF)
	var low_ground := heights.get_format() == Image.FORMAT_RGF
	var size := Vector2i(heights.get_width(), heights.get_height())
	if _texture != null and size == _size:
		_texture.update(heights)
	else:
		_texture = ImageTexture.create_from_image(heights)
	_image = heights
	_size = size
	_origin = origin
	_step = maxf(tiles_per_texel, 0.001)
	_on = true
	RenderingServer.global_shader_parameter_set(GLOBAL_TEX, _texture)
	RenderingServer.global_shader_parameter_set(GLOBAL_RECT, Vector4(_origin.x, _origin.y, _step, 1.0 if low_ground else 0.0))
	RenderingServer.global_shader_parameter_set(GLOBAL_ON, 1.0)


## Back to flat ground.
static func clear() -> void:
	_on = false
	_image = null
	RenderingServer.global_shader_parameter_set(GLOBAL_ON, 0.0)


static func is_on() -> bool:
	return _on


## The square the field covers: Rect2(origin, size in tiles), or an empty Rect2 when off.
static func area() -> Rect2:
	if not _on:
		return Rect2()
	return Rect2(_origin, Vector2(_size) * _step)


## The height under a world point (x east, z south), in tiles. The same sum as the shaders'.
static func at(x: float, z: float) -> float:
	if not _on or _image == null:
		return 0.0
	# Texel centres sit at origin + (i + 0.5) * step.
	var gx := (x - _origin.x) / _step - 0.5
	var gz := (z - _origin.y) / _step - 0.5
	if gx < -0.5 or gz < -0.5 or gx > _size.x - 0.5 or gz > _size.y - 0.5:
		return 0.0
	var ix := floori(gx)
	var iz := floori(gz)
	var fx := gx - ix
	var fz := gz - iz
	var x0 := clampi(ix, 0, _size.x - 1)
	var x1 := clampi(ix + 1, 0, _size.x - 1)
	var z0 := clampi(iz, 0, _size.y - 1)
	var z1 := clampi(iz + 1, 0, _size.y - 1)
	var a := lerpf(_image.get_pixel(x0, z0).r, _image.get_pixel(x1, z0).r, fx)
	var b := lerpf(_image.get_pixel(x0, z1).r, _image.get_pixel(x1, z1).r, fx)
	return lerpf(a, b, fz)


## A point lifted onto the ground: its y plus the height under it.
static func lift(p: Vector3) -> Vector3:
	return Vector3(p.x, p.y + at(p.x, p.z), p.z)


## Where a ray meets the ground: the flat ground's crossing, then walked onto the hills (a few
## steps along the ray, then halving back over the crossing). Null when it points away.
static func ray_hit(from: Vector3, dir: Vector3):
	var flat = Plane(Vector3.UP, 0.0).intersects_ray(from, dir)
	if not _on or flat == null or absf(dir.y) < 0.0001:
		return flat
	# Above ground at t = 0 (the camera); march until under it, then bisect.
	var d := dir.normalized()
	var t_flat: float = (flat - from).length()
	var lo := 0.0
	var hi := -1.0
	var t := maxf(t_flat - 64.0, 0.0)
	var step := 2.0
	var limit := t_flat + 64.0
	while t <= limit:
		var p := from + d * t
		if p.y <= at(p.x, p.z):
			hi = t
			break
		lo = t
		t += step
	if hi < 0.0:
		return flat
	for i in 12:
		var mid := (lo + hi) * 0.5
		var q := from + d * mid
		if q.y <= at(q.x, q.z):
			hi = mid
		else:
			lo = mid
	var hit := from + d * hi
	return Vector3(hit.x, 0.0, hit.z)


## A material for flat marks drawn over everything (no depth test), riding on the hills: the
## vertex colour, times `picture` when given. In place of an unshaded, see-through
## StandardMaterial3D with `no_depth_test`.
static func overlay_material(priority: int, picture: Texture2D = null) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = preload("res://shaders/ground_overlay.gdshader")
	m.render_priority = priority
	if picture != null:
		m.set_shader_parameter(&"picture", picture)
		m.set_shader_parameter(&"use_picture", true)
	return m
