extends Node3D
## The sky over a planet and the weather on its ground: a sky dome (shaders/planet_sky.gdshader)
## with a gradient, the sun, stars at night and clouds; the clouds' soft shadows drifting over the
## ground and, where the planet has it, a coloured haze (shaders/cloud_shadows.gdshader, one
## full-screen pass); and the sun and ambient light's colours. All of it follows the game's time of
## day, which main.gd eases and hands to apply().
##
## Each planet looks as Factorio draws it (`surface_render_parameters` in its planet prototype):
## Nauvis, Gleba and Fulgora have clouds (shadow opacity 0.25, Fulgora's stormier and darker at
## night, with lightning), Vulcanus and Gleba have fog (yellow; yellow and green), Aquilo neither,
## under a cold dim sky. Space platforms keep shaders/space_sky.gdshader (main.gd).
##
## Clouds can be turned off (Settings, graphics "clouds"); `--clean-shot` and `--review-shots` turn
## them off too, so model screenshots stay clean. `--sky=<planet>[@<daytime 0..1>]` shows another
## planet's sky (and holds the time of day), for screenshots against the mock.

const SKY_SHADER := preload("res://shaders/planet_sky.gdshader")
const SHADOW_SHADER := preload("res://shaders/cloud_shadows.gdshader")
const ItemIcons := preload("res://scripts/world/item_icons.gd")

## Per planet: sky by day and night, sun and ambient light by day and night, clouds (shadow
## opacity, cover: lower is more cloud, 1 none), haze (strength and its two colours), lightning.
const PLANETS := {
	"nauvis": {
		"zenith": [Color(0.27, 0.47, 0.76), Color(0.012, 0.02, 0.05)],
		"horizon": [Color(0.7, 0.8, 0.88), Color(0.05, 0.07, 0.12)],
		"sun": [Color(1.0, 0.97, 0.92), Color(0.6, 0.68, 0.95)], "sun_energy": [1.1, 0.12],
		"ambient": [Color(0.75, 0.78, 0.82), Color(0.35, 0.42, 0.6)], "ambient_energy": [0.6, 0.12],
		"shadow": 0.25, "cover": 0.46, "clouds": [Color(1.0, 1.0, 1.0), Color(0.6, 0.65, 0.72)],
		"haze": 0.0, "stars": 1.0,
	},
	"vulcanus": {
		"zenith": [Color(0.36, 0.2, 0.12), Color(0.05, 0.025, 0.02)],
		"horizon": [Color(0.86, 0.56, 0.3), Color(0.2, 0.08, 0.04)],
		"sun": [Color(1.0, 0.8, 0.58), Color(0.75, 0.42, 0.3)], "sun_energy": [1.15, 0.14],
		"ambient": [Color(0.85, 0.68, 0.52), Color(0.45, 0.28, 0.22)], "ambient_energy": [0.62, 0.15],
		"shadow": 0.0, "cover": 1.0, "clouds": [Color(0.9, 0.7, 0.5), Color(0.4, 0.25, 0.18)],
		"haze": 0.045, "haze_colors": [Color(1.0, 0.87, 0.3), Color(1.0, 0.87, 0.29)], "stars": 0.25,
	},
	"gleba": {
		"zenith": [Color(0.42, 0.55, 0.42), Color(0.02, 0.04, 0.03)],
		"horizon": [Color(0.78, 0.82, 0.62), Color(0.07, 0.1, 0.07)],
		"sun": [Color(0.97, 1.0, 0.84), Color(0.55, 0.7, 0.6)], "sun_energy": [1.0, 0.12],
		"ambient": [Color(0.72, 0.8, 0.66), Color(0.32, 0.42, 0.36)], "ambient_energy": [0.62, 0.13],
		"shadow": 0.25, "cover": 0.46, "clouds": [Color(0.92, 0.95, 0.85), Color(0.55, 0.62, 0.52)],
		"haze": 0.025, "haze_colors": [Color(1.0, 0.85, 0.55), Color(0.72, 1.0, 0.66)], "stars": 0.6,
	},
	"fulgora": {
		"zenith": [Color(0.3, 0.26, 0.4), Color(0.015, 0.01, 0.035)],
		"horizon": [Color(0.68, 0.58, 0.7), Color(0.07, 0.04, 0.1)],
		"sun": [Color(0.95, 0.86, 1.0), Color(0.5, 0.45, 0.85)], "sun_energy": [0.95, 0.08],
		"ambient": [Color(0.7, 0.66, 0.8), Color(0.3, 0.25, 0.48)], "ambient_energy": [0.56, 0.1],
		"shadow": 0.25, "cover": 0.4, "clouds": [Color(0.75, 0.7, 0.82), Color(0.3, 0.27, 0.38)],
		"haze": 0.0, "stars": 0.5, "lightning": true,
	},
	"aquilo": {
		"zenith": [Color(0.42, 0.52, 0.66), Color(0.01, 0.015, 0.035)],
		"horizon": [Color(0.75, 0.82, 0.9), Color(0.05, 0.07, 0.11)],
		"sun": [Color(0.85, 0.92, 1.0), Color(0.5, 0.6, 0.9)], "sun_energy": [0.75, 0.08],
		"ambient": [Color(0.72, 0.8, 0.92), Color(0.3, 0.36, 0.55)], "ambient_energy": [0.52, 0.1],
		"shadow": 0.0, "cover": 1.0, "clouds": [Color(0.9, 0.94, 1.0), Color(0.5, 0.56, 0.66)],
		"haze": 0.02, "haze_colors": [Color(0.85, 0.92, 1.0), Color(0.75, 0.85, 1.0)], "stars": 1.0,
	},
}
const CLOUD_HEIGHT := 70.0
## Lightning on Fulgora: seconds between strikes at night.
const LIGHTNING_GAP := Vector2(3.0, 12.0)

static var _shape_tex: Texture2D
static var _detail_tex: Texture2D
static var _loading := false
## Images read by the background task, made into textures on the main thread.
static var _loaded: Array = []
static var _loaded_lock := Mutex.new()

var planet := "nauvis"
var clouds_on := true
var sky_material := ShaderMaterial.new()
var _shadow_material := ShaderMaterial.new()
var _shadow_quad := MeshInstance3D.new()
var _p: Dictionary = PLANETS["nauvis"]
var _flash := 0.0
var _lightning_wait := 5.0
## From --sky=<planet>@<daytime>: the planet always shown, and the time of day held (-1: the game's).
var _forced_planet := ""
var forced_daytime := -1.0
var _clouds_forced_off := false


func _ready() -> void:
	sky_material.shader = SKY_SHADER
	sky_material.set_shader_parameter("cloud_height", CLOUD_HEIGHT)
	_shadow_material.shader = SHADOW_SHADER
	_shadow_material.set_shader_parameter("cloud_height", CLOUD_HEIGHT)
	_shadow_material.render_priority = -100  # before the other see-through things: ghosts, smoke
	var quad := QuadMesh.new()
	quad.size = Vector2(2.0, 2.0)
	_shadow_quad.mesh = quad
	_shadow_quad.material_override = _shadow_material
	_shadow_quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_shadow_quad.extra_cull_margin = 16384.0  # it covers the screen wherever it is
	_shadow_quad.name = "CloudShadows"
	add_child(_shadow_quad)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--sky="):
			var spec := arg.get_slice("=", 1)
			_forced_planet = spec.get_slice("@", 0)
			if spec.contains("@"):
				forced_daytime = float(spec.get_slice("@", 1))
		elif arg == "--clean-shot" or arg.begins_with("--review-shots="):
			_clouds_forced_off = true
			clouds_on = false
	set_planet(_forced_planet if _forced_planet != "" else "nauvis")
	_load_noise()


func _exit_tree() -> void:
	# Textures still held at quit would be reported as leaked; the next game loads them again.
	_shape_tex = null
	_detail_tex = null
	_loading = false
	sky_material.set_shader_parameter("cloud_shape", null)
	sky_material.set_shader_parameter("cloud_detail", null)
	_shadow_material.set_shader_parameter("cloud_shape", null)
	_shadow_material.set_shader_parameter("cloud_detail", null)


## The planet whose sky this is (unknown names, like a modded surface, look like Nauvis).
func set_planet(name: String) -> void:
	if _forced_planet != "":
		name = _forced_planet
	planet = name if PLANETS.has(name) else "nauvis"
	_p = PLANETS[planet]
	sky_material.set_shader_parameter("cloud_cover", float(_p["cover"]))
	_shadow_material.set_shader_parameter("cloud_cover", float(_p["cover"]))
	var hz: Array = _p.get("haze_colors", [Color.WHITE, Color.WHITE])
	_shadow_material.set_shader_parameter("haze_color", hz[0])
	_shadow_material.set_shader_parameter("haze_color2", hz[1])
	sky_material.set_shader_parameter("haze_color", hz[0].lerp(_pair("horizon", 0.0), 0.5))


func set_clouds(on: bool) -> void:
	clouds_on = on and not _clouds_forced_off


## Lights the scene for the time of day: `daytime` 0 is noon, 0.5 midnight; `night` 0 to 1 is how
## dark it is. Sets the sun's angle and colour, the ambient light, the sky and the clouds.
func apply(env: Environment, sun: DirectionalLight3D, daytime: float, night: float, delta: float, space: bool) -> void:
	var high := clampf(cos(TAU * daytime) * 0.5 + 0.5, 0.0, 1.0)  # 1 at noon, 0 at midnight
	sun.rotation_degrees = Vector3(-lerpf(20.0, 60.0, high), -30.0 + 60.0 * sin(TAU * daytime), 0.0)
	sun.light_energy = lerpf(_p["sun_energy"][0], _p["sun_energy"][1], night)
	sun.light_color = _pair("sun", night)
	env.ambient_light_energy = lerpf(_p["ambient_energy"][0], _p["ambient_energy"][1], night)
	env.ambient_light_color = _pair("ambient", night)
	env.background_color = _pair("horizon", night)
	_update_lightning(env, delta, night)
	if not _loaded.is_empty():
		_take_loaded()
	var to_sun := sun.global_transform.basis.z.normalized()
	_shadow_quad.visible = not space and clouds_on and (float(_p["shadow"]) > 0.0 or float(_p["haze"]) > 0.0)
	if space:
		return
	sky_material.set_shader_parameter("zenith_color", _pair("zenith", night))
	sky_material.set_shader_parameter("horizon_color", _pair("horizon", night))
	sky_material.set_shader_parameter("ground_color", _pair("horizon", night) * 0.45)
	sky_material.set_shader_parameter("sun_dir", to_sun)
	sky_material.set_shader_parameter("sun_color", sun.light_color)
	sky_material.set_shader_parameter("sun_strength", clampf(to_sun.y * 4.0, 0.0, 1.0) * (1.0 - night))
	sky_material.set_shader_parameter("stars", float(_p["stars"]) * smoothstep(0.4, 0.9, night))
	sky_material.set_shader_parameter("haze", float(_p["haze"]) * 6.0)
	sky_material.set_shader_parameter("flash", _flash)
	var cloudy := clouds_on and float(_p["cover"]) < 1.0
	sky_material.set_shader_parameter("cloud_alpha", (0.85 - 0.25 * night) if cloudy else 0.0)
	# Lit by the sun by day, grey-blue shapes against the night sky.
	var cc: Array = _p["clouds"]
	var lit := lerpf(1.0, 0.12, night)
	sky_material.set_shader_parameter("cloud_color", (cc[0] as Color) * lit)
	sky_material.set_shader_parameter("cloud_shade", (cc[1] as Color) * lit)
	if _shadow_quad.visible:
		_shadow_material.set_shader_parameter("sun_dir", to_sun)
		# Shadows fade as the light does; Factorio's clouds shade daylight, not the lamps' light.
		_shadow_material.set_shader_parameter("shadow_strength", float(_p["shadow"]) * (1.0 - night) if cloudy else 0.0)
		_shadow_material.set_shader_parameter("haze_strength", float(_p["haze"]) * (1.0 - 0.6 * night))


func _pair(key: String, night: float) -> Color:
	var pair: Array = _p[key]
	return (pair[0] as Color).lerp(pair[1], night)


## Fulgora's storms at night: a flash lights the sky and the ground for a moment.
func _update_lightning(env: Environment, delta: float, night: float) -> void:
	_flash = maxf(0.0, _flash - delta * 5.0)
	if _p.get("lightning", false) and night > 0.4 and clouds_on:
		_lightning_wait -= delta
		if _lightning_wait <= 0.0:
			_lightning_wait = randf_range(LIGHTNING_GAP.x, LIGHTNING_GAP.y)
			_flash = randf_range(0.5, 1.0)
	if _flash > 0.0:
		env.ambient_light_energy += _flash * 0.35
		env.ambient_light_color = env.ambient_light_color.lerp(Color(0.75, 0.8, 1.0), _flash * 0.5)


## Factorio's cloud noise from the player's install, loaded in the background and shared by every
## game; a generated noise stands in until then, or for good without an install.
func _load_noise() -> void:
	if _shape_tex == null:
		_shape_tex = _generated_noise(1)
		_detail_tex = _generated_noise(7)
		var data := ItemIcons.factorio_data_dir()
		if data != "" and not _loading:
			_loading = true
			var shape_path := data.path_join("core/graphics/clouds-noise.png")
			var detail_path := data.path_join("core/graphics/clouds-detail-noise.png")
			if FileAccess.file_exists(shape_path) and FileAccess.file_exists(detail_path):
				WorkerThreadPool.add_task(_load_images.bind(shape_path, detail_path), false, "cloud noise")
	_set_noise()


func _set_noise() -> void:
	for m: ShaderMaterial in [sky_material, _shadow_material]:
		m.set_shader_parameter("cloud_shape", _shape_tex)
		m.set_shader_parameter("cloud_detail", _detail_tex)


static func _load_images(shape_path: String, detail_path: String) -> void:
	var shape := Image.load_from_file(shape_path)
	var detail := Image.load_from_file(detail_path)
	if shape == null or detail == null or shape.is_empty() or detail.is_empty():
		return
	# A quarter of the size is plenty for soft shadows, and quick to sample.
	for img: Image in [shape, detail]:
		img.resize(512, 512, Image.INTERPOLATE_BILINEAR)
		img.generate_mipmaps()
	_loaded_lock.lock()
	_loaded = [shape, detail]
	_loaded_lock.unlock()


func _take_loaded() -> void:
	_loaded_lock.lock()
	var images := _loaded
	_loaded = []
	_loaded_lock.unlock()
	if images.size() == 2:
		_shape_tex = ImageTexture.create_from_image(images[0])
		_detail_tex = ImageTexture.create_from_image(images[1])
		_set_noise()


static func _generated_noise(seed_value: int) -> Texture2D:
	var noise := FastNoiseLite.new()
	noise.seed = seed_value
	noise.frequency = 0.012
	noise.fractal_octaves = 3
	var tex := NoiseTexture2D.new()
	tex.width = 256
	tex.height = 256
	tex.seamless = true
	tex.generate_mipmaps = true
	tex.noise = noise
	return tex

