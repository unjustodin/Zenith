extends Node
## --flicker-probe=<folder>[@degrees per frame]: the tree flicker measurement (PROGRESS.md, the
## tree flicker fix): once the world has settled, turns the camera slowly (0.1 degrees a frame by
## default) for FRAMES frames, saving each frame as <folder>/f<NN>.png, then quits.
## tools/flicker_count.py counts the pixels that change and change back. Run it windowed.

const FRAMES := 40
const SETTLE := 25.0  # seconds after the world is ready, so models and LODs are in

var world  # world.gd
var out_dir := ""
var step := 0.1

var _wait := 0.0
var _frame := -1
var _busy := false  # a frame being captured: the camera turns again only after it is saved


func _ready() -> void:
	var spec := out_dir.split("@")
	out_dir = spec[0]
	if spec.size() > 1:
		step = float(spec[1])
	DirAccess.make_dir_recursive_absolute(out_dir)


func _process(delta: float) -> void:
	if world == null or not Bridge.world_ready or _frame >= FRAMES or _busy:
		return
	var rig = world.get_parent().get_parent().get("rig")
	if rig == null:
		return
	if _frame < 0:
		_wait += delta
		if _wait < SETTLE:
			return
		_frame = 0
	_busy = true
	rig.yaw_degrees += step
	rig._yaw_goal = rig.yaw_degrees
	# Two frames drawn with the new view (the separate render thread draws a frame behind).
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	image.save_png(out_dir.path_join("f%02d.png" % _frame))
	_frame += 1
	_busy = false
	if _frame >= FRAMES:
		print("FLICKER saved %d frames to %s" % [FRAMES, out_dir])
		preload("res://scripts/menu/exit_guard.gd").arm()
		get_tree().quit()
