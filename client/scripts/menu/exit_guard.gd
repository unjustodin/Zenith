extends RefCounted
## Ends the program if it hasn't ended GRACE_MSEC after quitting. With the renderer on its own
## thread (project setting thread_model Separate, still experimental in Godot 4.7) Godot's shutdown
## sometimes never finishes (about 1 quit in 15 on a busy base): the window stops responding and
## the server launched from the menu (server_launcher.gd's watchdog) waits for the client to end.
## A normal shutdown takes well under a second, so the guard only acts when it has stuck; its
## thread just sleeps until then, and ends with the process.

const GRACE_MSEC := 8000

static var _thread: Thread


## Called right before get_tree().quit(), once everything of ours is saved and stopped.
static func arm() -> void:
	if _thread != null or OS.has_feature("web"):
		return
	_thread = Thread.new()
	_thread.start(_watch.bind(GRACE_MSEC))


static func _watch(msec: int) -> void:
	OS.delay_msec(msec)
	OS.kill(OS.get_process_id())
