extends Node
## The sun's shadow map fitted to the ground the camera sees (Settings > Graphics > Shadows).
##
## Godot draws every shadow caster in the light's box once per split, and the splits cover the
## camera's view out to directional_shadow_max_distance whether or not there is anything to see
## there. From the angled view the ground runs out at the top of the screen about 40 tiles from
## the camera, so a fixed 150 with four splits drew one split of air by the camera and two of
## casters under the ground beyond the view (and world.gd let every chunk out there cast). Here
## the distance follows the camera: just past the furthest ground in view (the shadows fade out
## beyond the top of the screen), on a ladder of steps so zooming changes it now and then, not
## every frame. The nearest ground in view is then at least half as far as the furthest, so one
## map covers it all as sharply as the splits did (a 4096 map over the default view: 55 texels a
## tile, against 41 to 102 before), drawing the casters once instead of in three splits. Only
## when the view reaches far beyond the nearest ground (first person, a low tilt) do Godot's own
## cascades take over, out to the quality's cap.
##
## Measured on a copy of the owner's save at the busy belts (High, the default view, noon), against
## the fixed 150 tiles and four splits on an 8192 atlas: the sun's shadows cost 3.7 ms of GPU and
## 1.0 ms of render CPU a frame; one fitted 4096 map costs 2.2 and 0.7 ms less (shadow draws 1,270
## -> 390, triangles 1.5 -> 0.5 million). A second split cost more than it saved (each is drawn in
## full), and so did 8192 (+1.4 ms for sharper shadows than before).

## Per quality: splits (1 = one map; 2 or 4), the splits when the view reaches far (first
## person), the shadow atlas, the furthest the shadows reach (tiles from the camera), where they
## start to fade (a fraction of the distance), whether neighbouring splits blend, the soft filter
## (RenderingServer.ShadowQuality: its own cost measured under 0.1 ms) and how wide it blurs
## (Light3D.shadow_blur, in texels). High's map has about half the texels a tile the old nearest
## split had, which blurred thin shadows such as a pole's lattice: blurring 0.6 texels keeps their
## edges as before.
const QUALITY := {
	"low": {"splits": 1, "horizon_splits": 2, "atlas": 2048, "cap": 80.0, "fade": 0.8, "blend": false, "filter": RenderingServer.SHADOW_QUALITY_SOFT_VERY_LOW, "blur": 1.0},
	"medium": {"splits": 1, "horizon_splits": 2, "atlas": 4096, "cap": 110.0, "fade": 0.8, "blend": false, "filter": RenderingServer.SHADOW_QUALITY_SOFT_LOW, "blur": 1.0},
	"high": {"splits": 1, "horizon_splits": 4, "atlas": 4096, "cap": 150.0, "fade": 0.8, "blend": false, "filter": RenderingServer.SHADOW_QUALITY_SOFT_LOW, "blur": 0.6},
	"ultra": {"splits": 1, "horizon_splits": 4, "atlas": 8192, "cap": 200.0, "fade": 0.8, "blend": true, "filter": RenderingServer.SHADOW_QUALITY_SOFT_LOW, "blur": 1.0},
}
## The view reaches "far" (cascades, horizon_splits) once the shadows' distance is this many times
## the nearest ground in view; back to one map below the second figure.
const FAR_RATIO := 4.0
const NEAR_RATIO := 3.5
## The shortest distance (zoomed right in) and the ladder's step: each is this much longer.
const MIN_DISTANCE := 32.0
const STEP := 1.15
## A shorter step is only taken once the view needs this much less than it (so zooming back and
## forth across a step doesn't flip it).
const HYSTERESIS := 0.9
const MODES := {1: DirectionalLight3D.SHADOW_ORTHOGONAL, 2: DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS, 4: DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS}
## --legacy-render: the shadows as they were before (a fixed 150 tiles, four splits, two on Low;
## and model_lods.gd's levels of detail), for comparisons.
const LEGACY_ATLAS := {"low": 2048, "medium": 4096, "high": 8192, "ultra": 8192}
static var legacy := "--legacy-render" in OS.get_cmdline_user_args()

var sun: DirectionalLight3D
var quality := "high"
var spec: Dictionary = QUALITY["high"]
## Settings > Graphics > Shadow distance: the furthest the shadows reach, tiles from the camera, in
## place of the quality's cap; 0 (Automatic) keeps the quality's. The shadows still stop just past
## the ground in view: this only lets them go further when zoomed out (and spreads the same map
## over more ground, so they are softer), or stops them sooner.
var distance_cap := 0.0
## The ground in view now: [nearest, furthest] depth from the camera (furthest INF: the horizon).
var view_depths := Vector2.ZERO
## Whether the view reaches far now (Godot's cascades rather than one map).
var far_view := false


func _ready() -> void:
	process_priority = 10  # after the camera rig has moved the camera this frame


## Settings > Graphics > Shadows: off, low, medium, high, ultra.
func apply_quality(q: String) -> void:
	quality = q if QUALITY.has(q) else "high"
	if legacy:
		apply_legacy()
		return
	set_process(true)
	apply_spec(QUALITY[quality])


## The shadows as they were before this fitting (--legacy-render, --probe-variants' "legacy render").
func apply_legacy() -> void:
	set_process(false)
	if sun == null:
		return
	RenderingServer.directional_shadow_atlas_set_size(int(LEGACY_ATLAS[quality]), true)
	RenderingServer.directional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_SOFT_LOW)
	sun.directional_shadow_max_distance = 150.0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS if quality == "low" else DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_split_1 = 0.1
	sun.directional_shadow_split_2 = 0.2
	sun.directional_shadow_split_3 = 0.5
	sun.directional_shadow_fade_start = 0.8
	sun.directional_shadow_blend_splits = false
	sun.shadow_blur = 1.0


## Sets the shadows from a QUALITY entry (or one like it: --probe-variants' "fit ...").
func apply_spec(s: Dictionary) -> void:
	spec = s
	if sun == null:
		return
	RenderingServer.directional_shadow_atlas_set_size(int(spec["atlas"]), true)
	sun.directional_shadow_blend_splits = bool(spec["blend"])
	sun.directional_shadow_fade_start = float(spec["fade"])
	sun.shadow_blur = float(spec.get("blur", 1.0))
	RenderingServer.directional_soft_shadow_filter_set_quality(int(spec["filter"]))
	_fit(true)


func _process(_delta: float) -> void:
	_fit(false)


func _fit(force: bool) -> void:
	if sun == null or not sun.shadow_enabled:
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	view_depths = ground_depths(cam)
	var cap := cap_for(spec, distance_cap)
	var want := distance_for(view_depths.y, cap, -1.0 if force else sun.directional_shadow_max_distance, float(spec["fade"]))
	if want != sun.directional_shadow_max_distance or force:
		sun.directional_shadow_max_distance = want
	# Looking far (the horizon, a low tilt) the nearest ground is many times nearer than the
	# furthest, which one map can't cover sharply: Godot's own cascades then.
	far_view = reaches_far(view_depths, want, far_view)
	var count := int(spec["horizon_splits"]) if far_view else int(spec["splits"])
	var mode: DirectionalLight3D.ShadowMode = MODES[count]
	if sun.directional_shadow_mode != mode:
		sun.directional_shadow_mode = mode
	var splits := split_fractions(Vector2(0.0, INF) if far_view else view_depths, want, count, float(spec.get("split_at", 0.5)))
	# Only when they move by more than a little: each change shifts the splits' texel grid.
	if force or absf(splits.x - sun.directional_shadow_split_1) > 0.02 or absf(splits.y - sun.directional_shadow_split_2) > 0.02 \
			or absf(splits.z - sun.directional_shadow_split_3) > 0.02:
		sun.directional_shadow_split_1 = splits.x
		sun.directional_shadow_split_2 = splits.y
		sun.directional_shadow_split_3 = splits.z


## The nearest and furthest ground (y = 0) the camera sees, as depths along its view: from the
## rays through the screen's corners and edges' middles. The furthest is INF when a ray along the
## top edge doesn't come down to the ground (the horizon is in view).
static func ground_depths(cam: Camera3D) -> Vector2:
	var size := cam.get_viewport().get_visible_rect().size
	var forward := -cam.global_basis.z
	var nearest := INF
	var furthest := 0.0
	for p: Vector2 in [Vector2.ZERO, Vector2(size.x * 0.5, 0.0), Vector2(size.x, 0.0), Vector2(0.0, size.y), Vector2(size.x * 0.5, size.y), size]:
		var origin := cam.project_ray_origin(p)
		var ray := cam.project_ray_normal(p)
		if origin.y <= 0.0 or ray.y > -0.02:
			furthest = INF
			nearest = minf(nearest, maxf(cam.near, 0.0))
			continue
		var hit := origin + ray * (-origin.y / ray.y)
		var depth := (hit - cam.global_position).dot(forward)
		nearest = minf(nearest, depth)
		furthest = maxf(furthest, depth)
	return Vector2(nearest, furthest)


## The shadow distance for ground in view out to `furthest`: past it by the fade (Godot's shadows
## fade out from `fade` of the distance on, so the fade starts past the top of the screen), on the
## The shadows' cap: the setting's distance when one is chosen, else the quality's.
static func cap_for(s: Dictionary, chosen: float) -> float:
	return chosen if chosen > 0.0 else float(s["cap"])


## ladder (MIN_DISTANCE x STEP^n), at most `cap`. `current` (-1: none) is kept while the view needs
## a little less than it.
static func distance_for(furthest: float, cap: float, current: float, fade := 0.8) -> float:
	var need := minf(furthest / fade, cap)
	var step := MIN_DISTANCE
	while step < need and step < cap:
		step *= STEP
	step = minf(snappedf(step, 0.1), cap)
	if current > 0.0 and step < current and need > current / STEP * HYSTERESIS and current <= cap:
		return current
	return step


## Whether shadows out to `distance` reach far beyond the nearest ground in view (`depths`, from
## ground_depths), so cascades beat one map; `now` is the answer so far (hysteresis).
static func reaches_far(depths: Vector2, distance: float, now: bool) -> bool:
	if depths.y == INF:
		return true
	return distance > depths.x * (NEAR_RATIO if now else FAR_RATIO)


## Where the splits end, as fractions of the distance (DirectionalLight3D.directional_shadow_split_*):
## the ground in view shared out between them (two splits meet `at` of the way from its nearest to
## its furthest). With the horizon in view, Godot's defaults.
static func split_fractions(depths: Vector2, distance: float, splits: int, at := 0.5) -> Vector3:
	if depths.y == INF or distance <= 0.0:
		return Vector3(0.1, 0.2, 0.5)
	var start := clampf(depths.x / distance, 0.0, 0.9)
	var end := clampf(depths.y / distance, start + 0.05, 1.0)
	if splits == 2:
		return Vector3(lerpf(start, end, at), 0.2, 0.5)
	return Vector3(lerpf(start, end, 0.25), lerpf(start, end, 0.5), lerpf(start, end, 0.75))
