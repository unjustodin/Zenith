extends RefCounted
## api.updates: asks the bridge for lighter updates while something long runs (a timelapse left
## for hours), so the game keeps its speed. The request lowers the player's settings for as long
## as it stands; Zenith's own "Hold the game at 60 UPS" (ups_governor.gd) still lowers them further
## when the game runs slow, and wins where both ask. Knobs (leave out what you don't need):
##   rate    0-3: the bridge's costliest updates (moving things, belt items, machine states...)
##           sent less often, each level twice as far apart; the client glides over the gaps
##   entity  tiles round the focus with moving things and machine states
##   near    tiles round the focus where every item on belts is drawn (at least 8)
##   far     tiles out to which belts show an icon of what they carry (0: none)
##   view    chunks drawn round the focus
##   map     how many times longer the minimap waits between refreshes

const AddonRequests := preload("res://scripts/addons/addon_requests.gd")

var _host
var _api


func _init(host, api) -> void:
	_host = host
	_api = api


## Asks for these knobs (replacing this add-on's earlier request).
func request(knobs: Dictionary) -> void:
	if AddonRequests.set_request(_api.id, knobs):
		_host.requests_changed()


## Back to the player's settings (and the governor's).
func clear() -> void:
	if AddonRequests.set_request(_api.id, {}):
		_host.requests_changed()


## This add-on's request now ({} for none).
func current() -> Dictionary:
	return (AddonRequests.requests.get(_api.id, {}) as Dictionary).duplicate()


## What the UPS governor holds back now, as the F4 line says it ("" for nothing).
func governor_status() -> String:
	var g = _host.game_node("ups_governor")
	return str(g.status()) if g != null else ""
