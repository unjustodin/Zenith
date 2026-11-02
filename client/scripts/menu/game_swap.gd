extends RefCounted
## Swapping between the 3D client and the normal game, on the same running world: one key
## here ("Show in Factorio", Ctrl+F9) brings Factorio's window to the front, or starts Factorio
## joined to the server this client started; the mod's own key in Factorio (the same Ctrl+F9,
## "Show in Zenith") sends `raise` back, and the client comes to the front. Nothing reloads: the
## server keeps running, and while the player is in the real game the bridge drives their character
## (puppet.lua), so both windows show the same character.
##
## Windows refuses SetForegroundWindow to a process that isn't in front, so a hidden PowerShell
## does it with the usual Alt-key tap first.

const Paths := preload("res://scripts/menu/paths.gd")

const FOCUS_PS := """param([int]$Id, [string]$Name)
Add-Type @'
using System; using System.Runtime.InteropServices;
public class ZenithWin {
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int c);
  [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr h);
  [DllImport("user32.dll")] public static extern void keybd_event(byte b, byte s, uint f, UIntPtr e);
}
'@
if ($Id -gt 0) { $p = Get-Process -Id $Id -ErrorAction SilentlyContinue }
else { $p = Get-Process -Name $Name -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1 }
if (-not $p -or $p.MainWindowHandle -eq 0) { exit 2 }
$h = $p.MainWindowHandle
if ([ZenithWin]::IsIconic($h)) { [ZenithWin]::ShowWindow($h, 9) | Out-Null }
[ZenithWin]::keybd_event(0x12, 0, 0, [UIntPtr]::Zero)
[ZenithWin]::SetForegroundWindow($h) | Out-Null
[ZenithWin]::keybd_event(0x12, 0, 2, [UIntPtr]::Zero)
exit 0
"""

## The Factorio this client started to join its server, if it's still running.
static var _game_pid := -1


## Brings Factorio's window forward, or starts Factorio joined to `game_port` (the server this
## client started; 0 when the client connected to a game it didn't start). Returns a line for the
## HUD's message.
static func show_factorio(game_port: int) -> String:
	if _focus(_game_pid if _game_pid > 0 and OS.is_process_running(_game_pid) else 0, "factorio") == 0:
		return ""
	if game_port <= 0:
		return "No Factorio window to show: start Factorio and join this game (or play it in single-player with --enable-lua-udp)"
	var exe := Paths.factorio_exe()
	if exe == "" or not FileAccess.file_exists(exe):
		return "Factorio wasn't found: set its folder in Settings → Other"
	_game_pid = OS.create_process(exe, ["--mp-connect", "127.0.0.1:%d" % game_port])
	if _game_pid <= 0:
		_game_pid = -1
		return "Couldn't start Factorio"
	return "Starting Factorio, joining this game: Ctrl+F9 there comes back to 3D"


## The mod's `raise`: the player pressed "Show in Zenith" in the real game.
static func show_client() -> void:
	if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_MINIMIZED:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_move_to_foreground()
	_focus(OS.get_process_id(), "")


## 0 when the window came forward.
static func _focus(pid: int, process_name: String) -> int:
	if OS.get_name() != "Windows":
		if pid > 0:
			return 1
		var out: Array = []
		return OS.execute("sh", ["-c", "command -v wmctrl >/dev/null && wmctrl -x -a %s" % process_name], out)
	var script := OS.get_user_data_dir().path_join("focus_window.ps1")
	if not FileAccess.file_exists(script) or FileAccess.get_file_as_string(script) != FOCUS_PS:
		var f := FileAccess.open(script, FileAccess.WRITE)
		if f == null:
			return 1
		f.store_string(FOCUS_PS)
		f.close()
	var args := ["-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-WindowStyle", "Hidden",
		"-File", script.replace("/", "\\"), "-Id", str(pid), "-Name", process_name if process_name != "" else "none"]
	var out: Array = []
	return OS.execute("powershell.exe", args, out)
