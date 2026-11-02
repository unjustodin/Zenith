extends Node
## --quit-probe=<seconds>: quits that long after the start (get_tree().quit(), as the probes do)
## without the exit guard, so a shutdown that never ends stays visible to whoever started the
## client (tools/quit_soak.py times it). Prints what of ours still runs on worker threads then.

const ModelLibrary := preload("res://scripts/world/model_library.gd")
const ModelLods := preload("res://scripts/world/model_lods.gd")

var main: Node
var seconds := 30.0
var _left := 0.0
var _done := false


func _ready() -> void:
	_left = seconds


func _process(delta: float) -> void:
	if _done:
		return
	_left -= delta
	if _left > 0.0:
		return
	_done = true
	var models := 0
	for name in ModelLibrary._job_order:
		var entry: Array = ModelLibrary._jobs[name]
		if int(entry[0]) >= 0 and not WorkerThreadPool.is_task_completed(entry[0]):
			models += 1
	var decor := 0
	var decoratives = main.get("decoratives")
	if decoratives != null:
		decor = (decoratives.get("_jobs") as Array).size()
	var terrain := 0
	var world = main.get("world")
	if world != null:
		terrain = (world.get("_terrain_jobs") as Dictionary).size()
	print("QUITPROBE quitting at %d ms: models %d, lods %d, decoratives %d, terrain %d, %.0f fps" % [Time.get_ticks_msec(), models,
		ModelLods._running.size(), decor, terrain, Engine.get_frames_per_second()])
	get_tree().quit()
