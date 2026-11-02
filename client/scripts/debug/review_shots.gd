extends Node
## Saves a set of screenshots of whatever stands where the character is, for reviewing models:
##
##   --review-shots=<dir>[@seconds]   start after that many seconds (default 12), then quit
##   --review-box=<w>,<d>,<h>         the size to frame and crop to (tiles, default 3,3,3)
##   --review-aim=<y>                 the height the side views look at (default 0.4 of the box's)
##   --review-views=<a,b,...>         which shots (default: all of VIEWS); `close+0.3` is the
##                                    close view 0.3 s after the shot before (machines moving)
##
## Meant for the mock with a model placed on the character's tile (the avatar and the HUD are
## hidden). Shots: Factorio's view (orthographic, north up, 48 degrees), the angled view from
## each side (north.png is the view from the north), a low side view and a close perspective one,
## each cropped to the box's outline on screen.

## yaw, pitch, distance for a 3-tile model (scaled to the box), orthographic; the cameras the
## review set uses. "factorio" is Factorio's own view and zoom.
const VIEWS := {
	"factorio": [0.0, 48.0, 0.0, true],
	"north": [180.0, 38.0, 7.0, false],
	"east": [270.0, 38.0, 7.0, false],
	"south": [0.0, 38.0, 7.0, false],
	"west": [90.0, 38.0, 7.0, false],
	"low": [30.0, 10.0, 7.0, false],
	"close": [20.0, 25.0, 4.0, false],
	"night": [0.0, 38.0, 7.0, false],  # the south view, named for shots taken at night
}
const MARGIN := 0.12

var rig: Node3D  # camera_rig.gd
var avatar: Node3D
var game: Node
var out_dir := ""
var delay := 12.0
var box := Vector3(3, 3, 3)
var aim := -1.0
var views: Array = VIEWS.keys()


static func requested() -> bool:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--review-shots="):
			return true
	return false


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--review-shots="):
			var spec := arg.get_slice("=", 1)
			out_dir = spec.get_slice("@", 0)
			if spec.contains("@"):
				delay = float(spec.get_slice("@", 1))
		elif arg.begins_with("--review-box="):
			var p := arg.get_slice("=", 1).split(",")
			box = Vector3(float(p[0]), float(p[1]), float(p[2]))
		elif arg.begins_with("--review-aim="):
			aim = float(arg.get_slice("=", 1))
		elif arg.begins_with("--review-views="):
			views = Array(arg.get_slice("=", 1).split(","))
	DirAccess.make_dir_recursive_absolute(out_dir)
	_run.call_deferred()


func _run() -> void:
	await get_tree().create_timer(delay).timeout
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	avatar.visible = false
	for layer in game.find_children("*", "CanvasLayer", true, false):
		(layer as CanvasLayer).visible = false
	var size := maxf(box.x, maxf(box.y, box.z))
	for view in views:
		var v: Array = VIEWS[str(view).get_slice("+", 0)]
		if v[3]:
			rig._saved_view = {}
			rig.toggle_factorio_view()
		else:
			var dist: float = v[2] * maxf(size, 1.5) / 3.0
			rig._snap(v[0], 0.0, dist, false)
			rig.pitch_degrees = v[1]  # below the rig's own limit for the low view
			rig._distance_goal = dist
			rig.distance = dist
		# Look at the middle of the box, not the ground under it (tall trees, poles).
		rig.target = null
		var look := box.z * 0.4 if aim < 0.0 else aim
		rig.global_position = avatar.global_position + Vector3(0.0, 0.0 if v[3] else look, 0.0)
		if str(view).contains("+"):
			await get_tree().create_timer(float(str(view).get_slice("+", 1))).timeout
		else:
			for i in 20:
				await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var image := get_viewport().get_texture().get_image()
		var rect := _crop(image.get_size())
		if rect.has_area():
			image = image.get_region(rect)
		if v[3] and image.get_height() < 400:
			# Factorio's zoom is small on screen: blow the crop up, pixels kept sharp.
			var k := ceili(400.0 / image.get_height())
			image.resize(image.get_width() * k, image.get_height() * k, Image.INTERPOLATE_NEAREST)
		var path := out_dir.path_join(str(view) + ".png")
		print("review shot %s: %s" % [path, error_string(image.save_png(path))])
	get_tree().quit()


## The box's outline on screen, with a margin, inside the image.
func _crop(image_size: Vector2i) -> Rect2i:
	var camera: Camera3D = rig.camera
	var c := avatar.global_position
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for sx in [-0.5, 0.5]:
		for sy in [0.0, 1.0]:
			for sz in [-0.5, 0.5]:
				var p := c + Vector3(sx * box.x, sy * box.z, sz * box.y)
				if camera.is_position_behind(p):
					return Rect2i(Vector2i.ZERO, image_size)
				var s := camera.unproject_position(p)
				lo = lo.min(s)
				hi = hi.max(s)
	var pad := (hi - lo) * MARGIN
	var r := Rect2(lo - pad, hi - lo + pad * 2.0)
	var scale := Vector2(image_size) / get_viewport().get_visible_rect().size
	r = Rect2(r.position * scale, r.size * scale)
	return Rect2i(r).intersection(Rect2i(Vector2i.ZERO, image_size))
