extends Node
## Creates maps and runs headless Factorio for the menu, with the same arguments as
## server/run-server.ps1: the server's own write-data folder (server/data: config.ini, logs, mods,
## RCON password), the repo's mod linked into its mods (a junction, so edits apply on restart),
## `--enable-lua-udp`, the game port and RCON bound to 127.0.0.1. Ports are picked free, from
## PORT_BASE up (--port-base=<n> to move them), so servers started by hand or by tests keep theirs.
##
## Progress comes from the server's log (factorio-current.log): "Loading map", then the state
## change to InGame. Stopping goes through RCON: /quit (Factorio saves the map as it quits) or,
## to leave without saving, ending the process.

signal progress(text: String, fraction: float)

const Paths := preload("res://scripts/menu/paths.gd")
const Rcon := preload("res://scripts/menu/rcon.gd")
const Settings := preload("res://scripts/menu/settings.gd")
const MapGen := preload("res://scripts/menu/map_gen.gd")

## Above the ports the docs use (34197/34198/34200 for run-server.ps1, 34400s for a second game);
## Settings → Factorio → First port for servers changes it.
const PORT_BASE := 34500
const PREVIEW_TIMEOUT_MSEC := 120000
const START_TIMEOUT_MSEC := 180000
const CREATE_TIMEOUT_MSEC := 300000
const QUIT_TIMEOUT_MSEC := 30000

var pid := -1
var udp_port := 0
var game_port := 0
var rcon_port := 0
## A free port for the client's own UDP socket.
var client_port := 0
var save_path := ""
## The host settings the running server was started with ({} when only this computer can join).
var hosting := {}
var error := ""
var rcon := Rcon.new()
var _exe := ""
var _data := ""
var _password := ""
var _stopping := false
## A map creation or preview still running (ended with the program).
var _helper_pid := -1
## The small process that ends the server if this program dies without stopping it.
var _watch_pid := -1


func is_running() -> bool:
	return pid > 0 and OS.is_process_running(pid)


func log_path() -> String:
	return Paths.server_data_dir().path_join("factorio-current.log")


## Creates a new map at `path` from map generator settings (map_gen.gd: {"gen", "map"}; a
## preset name works too). `exchange` is a map exchange string, loaded instead of the settings.
## False with `error` on failure.
func create_map(path: String, settings: Variant, seed_text: String, exchange := "") -> bool:
	if not _prepare():
		return false
	progress.emit("Creating map…", 0.05)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var args := _common() + ["--create", _native(path)] + _map_args(settings, seed_text, exchange, "create")
	var started := Time.get_unix_time_from_system()
	var started_msec := Time.get_ticks_msec()
	var creator := OS.create_process(_exe, args)
	_helper_pid = creator
	if creator <= 0:
		error = "Couldn't start %s" % _exe
		return false
	print("menu: creating %s with %s" % [path, _exe])
	while OS.is_process_running(creator):
		var t := (Time.get_ticks_msec() - started_msec) / 1000.0
		progress.emit("Creating map…", 0.05 + 0.25 * (1.0 - exp(-t / 8.0)))
		if Time.get_ticks_msec() - started_msec > CREATE_TIMEOUT_MSEC:
			OS.kill(creator)
			break
		await get_tree().create_timer(0.2).timeout
	if not FileAccess.file_exists(path) or FileAccess.get_modified_time(path) < int(started) - 1:
		error = "Map creation failed.\n" + _log_errors(int(started))
		return false
	return true


## Factorio's map preview (--generate-map-preview) for these settings: a PNG of `size` pixels
## around the map's centre on `planet`. The image, or null with `error`.
func generate_preview(settings: Variant, seed_text: String, exchange := "", planet := "nauvis", size := 512) -> Image:
	if not _prepare():
		return null
	var out := _data.path_join("map-presets/preview.png")
	DirAccess.make_dir_recursive_absolute(out.get_base_dir())
	if FileAccess.file_exists(out):
		DirAccess.remove_absolute(out)
	var args := _common() + ["--generate-map-preview", _native(out), "--map-preview-size", str(size),
		"--map-preview-planet", planet, "--threads", str(maxi(1, OS.get_processor_count() - 1))] + _map_args(settings, seed_text, exchange, "preview")
	var started := Time.get_unix_time_from_system()
	var started_msec := Time.get_ticks_msec()
	var maker := OS.create_process(_exe, args)
	_helper_pid = maker
	if maker <= 0:
		error = "Couldn't start %s" % _exe
		return null
	while OS.is_process_running(maker):
		if Time.get_ticks_msec() - started_msec > PREVIEW_TIMEOUT_MSEC:
			OS.kill(maker)
			break
		await get_tree().create_timer(0.1).timeout
	var image := Image.new()
	if not FileAccess.file_exists(out) or image.load(out) != OK:
		error = "Factorio made no preview.\n" + _log_errors(int(started))
		return null
	return image


## --map-gen-settings, --map-settings and the seed, or the exchange string.
func _map_args(settings: Variant, seed_text: String, exchange: String, tag: String) -> Array:
	var args: Array = []
	if exchange.strip_edges() != "":
		args += ["--exchange-string", exchange.strip_edges()]
	else:
		var s: Dictionary = settings if settings is Dictionary else MapGen.preset_settings(str(settings), _exe)
		var dir := _data.path_join("map-presets")
		DirAccess.make_dir_recursive_absolute(dir)
		var gen_file := dir.path_join("%s-gen.json" % tag)
		var map_file := dir.path_join("%s-map.json" % tag)
		var gen: Dictionary = (s.get("gen", {}) as Dictionary).duplicate(true)
		gen.erase("seed")
		_write(gen_file, JSON.stringify(gen, "  "))
		_write(map_file, JSON.stringify(s.get("map", {}), "  "))
		args += ["--map-gen-settings", _native(gen_file)]
		if tag == "create":
			args += ["--map-settings", _native(map_file)]
	if seed_text.strip_edges().is_valid_int():
		args += ["--map-gen-seed", str(int(seed_text.strip_edges()) & 0xFFFFFFFF)]
	return args


## Starts the server on a save. Returns once it is hosting (or false with `error`); the bridge
## then connects to `udp_port`. `host` ({name, description, port, password, max_players, lan})
## opens the game to normal Factorio players on the network (Multiplayer → Host); without it the
## server only listens on this computer.
func start(path: String, host := {}) -> bool:
	if is_running():
		await stop(true)
	if not _prepare():
		return false
	if not FileAccess.file_exists(path):
		error = "The save %s doesn't exist." % path
		return false
	save_path = path
	var base := int(Settings.get_value("factorio", "port_base"))
	if base < 1024:
		base = PORT_BASE
	if Settings.arg_value("--port-base=").is_valid_int():
		base = int(Settings.arg_value("--port-base="))
	udp_port = free_udp_port(base)
	game_port = free_udp_port(udp_port + 1)
	if not host.is_empty():
		game_port = int(host.get("port", 34197))
		if not _udp_free(game_port):
			error = "Port %d is in use: another Factorio server? Pick another port to host on." % game_port
			return false
	rcon_port = free_tcp_port(game_port + 1)
	client_port = free_udp_port(rcon_port + 1)
	if udp_port == 0 or game_port == 0 or rcon_port == 0 or client_port == 0:
		error = "No free ports found from %d up. Close other servers, or start this one with --port-base=<port>." % base
		return false
	var args := _common() + [
		"--start-server", _native(path),
		"--server-settings", _native(_server_settings(host)),
		"--enable-lua-udp", str(udp_port),
		"--port", str(game_port),
		"--bind", "0.0.0.0" if not host.is_empty() else "127.0.0.1",
		"--rcon-bind", "127.0.0.1:%d" % rcon_port,
		"--rcon-password", _password,
	]
	if bool(Settings.get_value("factorio", "verbose_logging")):
		args.append("--verbose")
	hosting = host.duplicate()
	var started := int(Time.get_unix_time_from_system())
	var started_msec := Time.get_ticks_msec()
	progress.emit("Starting server…", 0.3)
	pid = OS.create_process(_exe, args)
	if pid <= 0:
		pid = -1
		error = "Couldn't start %s" % _exe
		return false
	print("menu: server pid %d on %s: UDP %d, game %d, RCON %d" % [pid, path.get_file(), udp_port, game_port, rcon_port])
	_watch(pid)
	var loading := false
	while true:
		await get_tree().create_timer(0.25).timeout
		if not is_running():
			pid = -1
			error = "The server stopped while starting.\n" + _log_errors(started)
			return false
		if Time.get_ticks_msec() - started_msec > START_TIMEOUT_MSEC:
			error = "The server didn't start within %d s.\n%s" % [START_TIMEOUT_MSEC / 1000, _log_errors(started)]
			await stop(false)
			return false
		var text := _fresh_log(started)
		if text.contains("changing state from(CreatingGame) to(InGame)"):
			break
		if text.contains("Loading map"):
			loading = true
		var t := (Time.get_ticks_msec() - started_msec) / 1000.0
		if loading:
			progress.emit("Loading map…", 0.4 + 0.3 * (1.0 - exp(-t / 6.0)))
		else:
			progress.emit("Starting server…", 0.3 + 0.1 * (1.0 - exp(-t / 3.0)))
	progress.emit("Connecting…", 0.75)
	if not await rcon.open(get_tree(), rcon_port, _password):
		push_warning("menu: %s (saving from the menu won't work)" % rcon.error)
	return true


## Saves now (RCON /server-save). True when the server said it saved.
func save() -> bool:
	if not is_running() or not rcon.is_open():
		error = "No server to save to"
		return false
	var before := FileAccess.get_modified_time(save_path)
	var reply: String = await rcon.run(get_tree(), "/server-save")
	# The reply comes before the file is written; wait for it (a big map takes a few seconds).
	var started := Time.get_ticks_msec()
	while FileAccess.get_modified_time(save_path) == before and Time.get_ticks_msec() - started < 20000:
		await get_tree().create_timer(0.2).timeout
	var saved := FileAccess.get_modified_time(save_path) != before
	if not saved:
		error = "The server didn't save (%s)" % reply.strip_edges()
	return saved


## Saves a copy under another name: /server-save <name> writes <data>/saves/<name>.zip, which is
## then copied into the saves folder. The game goes on in its own save. True once copied.
func save_as(save_name: String) -> bool:
	if not is_running() or not rcon.is_open():
		error = "No server to save to"
		return false
	var written := _data.path_join("saves").path_join(save_name + ".zip")
	var before := FileAccess.get_modified_time(written) if FileAccess.file_exists(written) else 0
	var reply: String = await rcon.run(get_tree(), "/server-save " + save_name)
	var started := Time.get_ticks_msec()
	while Time.get_ticks_msec() - started < 30000:
		if FileAccess.file_exists(written) and FileAccess.get_modified_time(written) != before:
			# The file can appear before Factorio has finished writing it: wait for its size to settle.
			var size := _file_size(written)
			await get_tree().create_timer(0.5).timeout
			if size > 0 and size == _file_size(written):
				break
		await get_tree().create_timer(0.2).timeout
	if not FileAccess.file_exists(written) or FileAccess.get_modified_time(written) == before:
		error = "The server didn't save (%s)" % reply.strip_edges()
		return false
	var target := Paths.saves_dir().path_join(save_name + ".zip")
	if DirAccess.copy_absolute(written, target) != OK:
		error = "Saved as %s, but couldn't copy it into %s." % [written, Paths.saves_dir()]
		return false
	return true


## Stops the server: /quit saves the map first (as Factorio does); without saving, the process is
## ended. Waits until it has gone.
func stop(save_first: bool) -> void:
	if _stopping:
		while _stopping:
			await get_tree().process_frame
		return
	_stopping = true
	if is_running():
		if save_first and rcon.is_open():
			progress.emit("Saving and stopping the server…", 0.5)
			await rcon.run(get_tree(), "/quit")
			var started := Time.get_ticks_msec()
			while is_running() and Time.get_ticks_msec() - started < QUIT_TIMEOUT_MSEC:
				await get_tree().create_timer(0.1).timeout
		if is_running():
			OS.kill(pid)
			var started := Time.get_ticks_msec()
			while is_running() and Time.get_ticks_msec() - started < 5000:
				await get_tree().create_timer(0.1).timeout
		print("menu: server pid %d %s" % [pid, "still running!" if is_running() else "stopped"])
	rcon.close()
	pid = -1
	_end_watch()
	_stopping = false


## The program is ending without going through the menu (--quit-after, a crash in a script):
## don't leave a server behind.
func _exit_tree() -> void:
	if is_running():
		print("menu: ending server pid %d as the client exits" % pid)
	kill_now()
	if _helper_pid > 0 and OS.is_process_running(_helper_pid):
		OS.kill(_helper_pid)
	_end_watch()


## Ends the server at once, without waiting (the window is closing).
func kill_now() -> void:
	if is_running():
		OS.kill(pid)
	pid = -1


## A crash, a hang ended from the Task Manager or a closed console window skip _exit_tree, which
## left the server running with nobody to stop it. So a separate process waits for this one to end
## and then ends the server, unless the server has already gone (its start time guards against the
## number being reused by another program).
func _watch(server: int) -> void:
	_end_watch()
	var me := OS.get_process_id()
	if OS.get_name() == "Windows":
		var script := ("$c = Get-Process -Id %d -ErrorAction SilentlyContinue; $s = Get-Process -Id %d -ErrorAction SilentlyContinue; "
			+ "if ($c -and $s) { $t = $s.StartTime; $c.WaitForExit(); $s = Get-Process -Id %d -ErrorAction SilentlyContinue; "
			+ "if ($s -and $s.StartTime -eq $t) { Stop-Process -Id %d -Force } }") % [me, server, server, server]
		_watch_pid = OS.create_process("powershell.exe", ["-NoProfile", "-NonInteractive", "-WindowStyle", "Hidden", "-Command", script])
	else:
		var script := ("while kill -0 %d 2>/dev/null; do sleep 1; done; "
			+ "ps -p %d -o comm= 2>/dev/null | grep -qi factorio && kill %d") % [me, server, server]
		_watch_pid = OS.create_process("/bin/sh", ["-c", script])
	if _watch_pid <= 0:
		push_warning("menu: couldn't start the watchdog; if the client crashes, end the server (pid %d) yourself" % server)
		_watch_pid = -1


func _end_watch() -> void:
	if _watch_pid > 0 and OS.is_process_running(_watch_pid):
		OS.kill(_watch_pid)
	_watch_pid = -1


static func free_udp_port(from: int) -> int:
	for port in range(maxi(from, 1024), mini(from + 400, 65535)):
		if _udp_free(port):
			return port
	return 0


static func free_tcp_port(from: int) -> int:
	for port in range(maxi(from, 1024), mini(from + 400, 65535)):
		var server := TCPServer.new()
		if server.listen(port, "127.0.0.1") == OK:
			server.stop()
			if _udp_free(port):  # keep the four ports apart, whatever protocol
				return port
	return 0


static func _udp_free(port: int) -> bool:
	for address in ["127.0.0.1", "*"]:
		var udp := PacketPeerUDP.new()
		if udp.bind(port, address) != OK:
			return false
		udp.close()
	var tcp := TCPServer.new()
	if tcp.listen(port, "127.0.0.1") != OK:
		return false
	tcp.stop()
	return true


## config.ini, the mod link and the RCON password in the server's data folder.
func _prepare() -> bool:
	error = ""
	_exe = Paths.factorio_exe()
	if _exe == "" or not FileAccess.file_exists(_exe):
		error = "Factorio wasn't found%s.\nSet the path to factorio.exe in Settings → Factorio." % (" at " + _exe if _exe != "" else "")
		return false
	_data = Paths.server_data_dir()
	var mods := _data.path_join("mods")
	DirAccess.make_dir_recursive_absolute(mods)
	# /server-save <name> writes to <data>/saves, and Factorio stops the game if it's missing.
	DirAccess.make_dir_recursive_absolute(_data.path_join("saves"))
	DirAccess.make_dir_recursive_absolute(Paths.saves_dir())
	if _locked():
		error = "Another Factorio is using the server folder %s.\nStop that server first, or pick another server data folder in Settings → Factorio." % _data
		return false
	var config := "[path]\nread-data=%s\nwrite-data=%s\n" % [_native(Paths.read_data_dir(_exe)), _native(_data)]
	_write(_data.path_join("config.ini"), config)
	var link := mods.path_join("factorio-3d-bridge")
	if not DirAccess.dir_exists_absolute(link):
		var out: Array = []
		if OS.get_name() == "Windows":
			OS.execute("cmd.exe", ["/c", "mklink", "/J", _native(link), _native(Paths.mod_dir())], out)
		else:
			OS.execute("ln", ["-s", Paths.mod_dir(), link], out)
		if not DirAccess.dir_exists_absolute(link):
			error = "Couldn't link the mod into %s:\n%s" % [mods, "\n".join(out)]
			return false
	var password_file := _data.path_join("rcon-password.txt")
	if FileAccess.file_exists(password_file):
		_password = FileAccess.get_file_as_string(password_file).strip_edges()
	if _password == "":
		var chars := "0123456789abcdefghijklmnopqrstuvwxyz"
		var crypto := Crypto.new()
		var bytes := crypto.generate_random_bytes(24)
		for b in bytes:
			_password += chars[b % chars.length()]
		_write(password_file, _password + "\n")
	return true


## Factorio holds `.lock` in its write-data folder while it runs; it can't be opened then.
func _locked() -> bool:
	var lock := _data.path_join(".lock")
	if not FileAccess.file_exists(lock):
		return false
	var f := FileAccess.open(lock, FileAccess.READ_WRITE)
	if f == null:
		return true
	f.close()
	return false


func _common() -> Array:
	return ["--config", _native(_data.path_join("config.ini")), "--mod-directory", _native(_data.path_join("mods"))]


## The log as this run wrote it ("" while it is still the previous run's).
func _fresh_log(started: int) -> String:
	var path := log_path()
	if not FileAccess.file_exists(path) or FileAccess.get_modified_time(path) < started - 1:
		return ""
	var f := FileAccess.open(path, FileAccess.READ)
	return f.get_as_text() if f != null else ""


## The error lines of this run's log, for the message box.
func _log_errors(started: int) -> String:
	var text := _fresh_log(started)
	if text == "":
		return "See %s." % log_path()
	var lines: Array = []
	for line in text.split("\n"):
		if line.contains("Error") or line.contains("error") or line.contains("Failed") or line.contains("Couldn't"):
			lines.append(line.strip_edges())
	if lines.is_empty():
		var all := text.strip_edges().split("\n")
		lines = Array(all.slice(maxi(0, all.size() - 4)))
	return "\n".join(lines.slice(maxi(0, lines.size() - 6))) + "\n(%s)" % log_path()


## The repo's server-settings.json with Settings → Other (autosave) and the host's name,
## password, player limit and LAN visibility, written to the server's data folder.
func _server_settings(host: Dictionary) -> String:
	var file := Paths.server_settings_file()
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(file)) if FileAccess.file_exists(file) else null
	var s: Dictionary = parsed if parsed is Dictionary else {}
	s["autosave_interval"] = int(Settings.get_value("factorio", "autosave_interval"))
	s["autosave_slots"] = int(Settings.get_value("factorio", "autosave_slots"))
	if not host.is_empty():
		s["name"] = str(host.get("name", "Zenith"))
		s["description"] = str(host.get("description", ""))
		s["game_password"] = str(host.get("password", ""))
		s["max_players"] = int(host.get("max_players", 0))
		s["visibility"] = {"public": false, "lan": bool(host.get("lan", true))}
		s["require_user_verification"] = false
	var out := _data.path_join("server-settings.json")
	_write(out, JSON.stringify(s, "  "))
	return out


static func _write(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_string(text)
		f.close()


static func _native(path: String) -> String:
	return path.replace("/", "\\") if OS.get_name() == "Windows" else path


static func _file_size(path: String) -> int:
	var f := FileAccess.open(path, FileAccess.READ)
	return f.get_length() if f != null else 0
