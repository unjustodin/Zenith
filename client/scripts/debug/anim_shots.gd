extends Node
## Saves a short clip as numbered screenshots, for looking at animations frame by frame:
##
##   --anim-shots=<dir>@<start>,<count>,<step>   from `start` seconds, `count` frames `step`
##                                               seconds apart, then quit
##   --anim-hud                                  keep the HUD (hidden by default)
##   --clean-shot                                hide the character too
##
## Pair it with --anim-pose=<run|mine|aim|...> (avatar.gd) to hold the character in one
## animation, and --camera=<yaw>,<pitch>,<distance> to frame it.

var game: Node
var out_dir := ""
var start := 6.0
var count := 12
var step := 0.05


static func requested() -> bool:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--anim-shots="):
			return true
	return false


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--anim-shots="):
			var spec := arg.get_slice("=", 1)
			out_dir = spec.get_slice("@", 0)
			if spec.contains("@"):
				var p := spec.get_slice("@", 1).split(",")
				start = float(p[0])
				if p.size() > 1:
					count = int(p[1])
				if p.size() > 2:
					step = float(p[2])
	DirAccess.make_dir_recursive_absolute(out_dir)
	_run.call_deferred()


func _run() -> void:
	await get_tree().create_timer(start).timeout
	if not OS.get_cmdline_user_args().has("--anim-hud"):
		Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
		for layer in game.find_children("*", "CanvasLayer", true, false):
			(layer as CanvasLayer).visible = false
	if OS.get_cmdline_user_args().has("--clean-shot"):
		var avatar := game.get_node_or_null("Avatar") as Node3D
		if avatar != null:
			avatar.visible = false
	for i in count:
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		img.save_png(out_dir.path_join("%03d.png" % i))
		if step > 0.0:
			await get_tree().create_timer(step).timeout
	print("anim shots: %d frames in %s" % [count, out_dir])
	get_tree().quit()
