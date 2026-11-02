extends RefCounted
## api.view: what the window shows, for clean shots and timelapses. None of it changes the game.

var _host
var _api
const AddonRequests := preload("res://scripts/addons/addon_requests.gd")

var _hiding := false
var _holding_daytime := false


func _init(host, api) -> void:
	_host = host
	_api = api


## Hides Zenith's interface (the HUD, windows, the cursor, hover outlines) for a clean shot, or
## shows it again. Add-ons' windows hide too; their overlay layer (api.ui.layer()) stays. Zenith's
## menus still open over it (Esc) and show the cursor while they do.
func hide_interface(on: bool) -> void:
	_hiding = on
	_host.request_hidden(_api, on)


func interface_hidden() -> bool:
	return _host.interface_hidden()


## Saves what a viewport shows (the window when null) as a PNG at `path` (user://... or a full
## path; folders are made). The picture is taken now (the last frame drawn) and written on a worker
## thread, so a frame every few seconds costs the game little. False when there's nothing to save.
func save_frame(path: String, viewport: Viewport = null) -> bool:
	return _host.save_frame(path, viewport)


## Frames still being written.
func frames_pending() -> int:
	return _host.frames_pending()


## The 3D world the game is drawn in, for an add-on's own SubViewport and Camera3D (a second shot
## drawn off screen, saved with save_frame); null outside a game.
func world_3d() -> World3D:
	return _host.world_3d()


## Holds the time of day as drawn (0 noon, 0.25 dusk, 0.5 midnight), for a timelapse that should
## stay in daylight; the game's own time runs on. A negative value lets it run again.
func hold_daytime(daytime: float) -> void:
	_holding_daytime = daytime >= 0.0
	_host.hold_daytime(_api, daytime)


func daytime_held() -> bool:
	return _holding_daytime


## (API 1.1) Keeps Zenith drawing for an add-on that films in the background: Zenith's window
## isn't minimised when it loses focus (Settings > Graphics' "Minimize on focus loss"; a minimised
## window draws nothing, not even an add-on's own viewport), and "Hold the game at 60 UPS" never
## caps the frame rate under `min_fps`. Zenith keeps drawing behind other windows anyway; the player
## minimising it by hand still stops it. 0 (or a negative) gives it back.
func keep_drawing(min_fps: int) -> void:
	var before := AddonRequests.drawing.duplicate()
	if min_fps > 0:
		AddonRequests.drawing[_api.id] = min_fps
	else:
		AddonRequests.drawing.erase(_api.id)
	if before != AddonRequests.drawing:
		_host.requests_changed()


func keeping_drawing() -> bool:
	return AddonRequests.drawing.has(_api.id)


func screen_size() -> Vector2:
	return _host.get_viewport().get_visible_rect().size


func _release() -> void:
	if _hiding:
		hide_interface(false)
	if _holding_daytime:
		hold_daytime(-1.0)
	keep_drawing(0)
