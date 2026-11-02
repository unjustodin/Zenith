extends RefCounted
## Where things are: factorio.exe (found like server/run-server.ps1 does: every Steam library,
## then the standalone installer's folder; Settings → Factorio overrides it), the repo's mod and
## server folders, the server's write-data folder and saves, and Factorio's own saves.
##
## Command-line options (after `--`): --factorio=<factorio.exe or install folder>
## --server-data=<dir> --saves-dir=<dir>, for tests that must not touch the normal folders.

const Settings := preload("res://scripts/menu/settings.gd")
const ItemIcons := preload("res://scripts/world/item_icons.gd")

const EXE := "bin/x64/factorio.exe"


## Where the mod and server folders are: the repo checkout the client runs from (client/..), or in
## an exported build (tools/release/package.py) the folder Zenith.exe sits in, which holds `mod/`
## and `server/` beside it.
static func repo_dir() -> String:
	if OS.has_feature("template"):
		return OS.get_executable_path().get_base_dir()
	return ProjectSettings.globalize_path("res://").path_join("..").simplify_path()


static func mod_dir() -> String:
	return repo_dir().path_join("mod/factorio-3d-bridge")


static func server_settings_file() -> String:
	return repo_dir().path_join("server/server-settings.json")


## The server's config, logs, mods link and RCON password, apart from the normal game's.
static func server_data_dir() -> String:
	var dir := Settings.arg_value("--server-data=")
	if dir == "":
		dir = str(Settings.get_value("factorio", "server_data"))
	return _absolute(dir) if dir != "" else repo_dir().path_join("server/data")


static func saves_dir() -> String:
	var dir := Settings.arg_value("--saves-dir=")
	if dir == "":
		dir = str(Settings.get_value("factorio", "saves"))
	return _absolute(dir) if dir != "" else repo_dir().path_join("server/saves")


## Factorio's own saves (%APPDATA%\Factorio\saves, ~/.factorio/saves), or "".
static func factorio_saves_dir() -> String:
	var candidates: Array[String] = []
	var appdata := OS.get_environment("APPDATA")
	if appdata != "":
		candidates.append(appdata.replace("\\", "/").path_join("Factorio/saves"))
	var home := OS.get_environment("HOME")
	if home != "":
		candidates.append(home.path_join(".factorio/saves"))
		candidates.append(home.path_join("Library/Application Support/factorio/saves"))
	for dir in candidates:
		if DirAccess.dir_exists_absolute(dir):
			return dir
	return ""


## factorio.exe: the setting or --factorio, else the install the icons come from, else Steam's
## libraries and the standalone folder. "" when there is none.
static func factorio_exe() -> String:
	var configured := Settings.arg_value("--factorio=")
	if configured == "":
		configured = str(Settings.get_value("factorio", "executable"))
	if configured != "":
		return _exe_in(configured)
	return find_factorio_exe()


## Searching only, without the setting (shown in Settings as what "automatic" finds).
static func find_factorio_exe() -> String:
	var candidates: Array[String] = []
	var data := ItemIcons.factorio_data_dir()
	if data != "":
		candidates.append(data.path_join("..").simplify_path().path_join(EXE))
	for lib in _steam_libraries():
		candidates.append(lib.path_join("steamapps/common/Factorio").path_join(EXE))
	candidates.append("C:/Program Files/Factorio".path_join(EXE))
	candidates.append(OS.get_environment("HOME").path_join("factorio/bin/x64/factorio"))
	for c in candidates:
		if FileAccess.file_exists(c):
			return c
	return ""


## The install's data folder (read-data in config.ini) for a factorio.exe.
static func read_data_dir(exe: String) -> String:
	return exe.get_base_dir().path_join("../../data").simplify_path()


## Factorio's version from the install's base mod, e.g. "2.1.23", or "".
static func factorio_version(exe: String) -> String:
	var info := read_data_dir(exe).path_join("base/info.json")
	if not FileAccess.file_exists(info):
		return ""
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(info))
	return str(parsed.get("version", "")) if parsed is Dictionary else ""


## A path given as the install folder, its bin folder or the exe itself.
static func _exe_in(path: String) -> String:
	path = _absolute(path)
	if FileAccess.file_exists(path):
		return path
	for sub in [EXE, "x64/factorio.exe", "factorio.exe", "bin/x64/factorio"]:
		if FileAccess.file_exists(path.path_join(sub)):
			return path.path_join(sub)
	return path  # missing: the launcher reports it with this path


static func _absolute(path: String) -> String:
	path = path.strip_edges().replace("\\", "/")
	if path.is_relative_path():
		path = repo_dir().path_join(path)
	return path.simplify_path()


## Steam's folder from the registry (HKCU\Software\Valve\Steam SteamPath) or its default, then
## the other libraries listed in libraryfolders.vdf.
static func _steam_libraries() -> Array[String]:
	var out: Array[String] = []
	if OS.get_name() != "Windows":
		var home := OS.get_environment("HOME")
		for steam in [home.path_join(".steam/steam"), home.path_join(".local/share/Steam")]:
			out.append(steam)
			out.append_array(ItemIcons._steam_libraries(steam.path_join("steamapps/libraryfolders.vdf")))
		return out
	var steam := "C:/Program Files (x86)/Steam"
	var output: Array = []
	if OS.execute("reg", ["query", "HKCU\\Software\\Valve\\Steam", "/v", "SteamPath"], output) == 0 and not output.is_empty():
		var m := RegEx.create_from_string("SteamPath\\s+REG_SZ\\s+(.+)").search(str(output[0]))
		if m != null:
			steam = m.get_string(1).strip_edges().replace("\\", "/")
	out.append(steam)
	out.append_array(ItemIcons._steam_libraries(steam.path_join("steamapps/libraryfolders.vdf")))
	return out
