extends "res://scripts/ui/factorio/platform_info.gd"
## Space platforms (Space Age), from the mod's `plat`: the force's platforms (the space map, the map's
## Surfaces panel and the sky read them here), and Factorio's panel of the platform the view is on,
## under the minimap (factorio_ui.gd lays it out): on board, and in the remote view of a platform
## from elsewhere. In the map view and on the space map remote_frame.gd shows the same panel in its
## right column instead. On board it has Factorio's "Drop to a planet": a cargo pod down to the
## planet the platform is stopped at (`land`, docs/PROTOCOL.md "Riding to a platform";
## scripts/world/ride.gd shows it). Going up is a ride in a rocket from a silo's screen; where a
## platform goes and its pause are set in its hub's screen, as in Factorio.

## Kept for main.gd, which connects it; nothing in this panel opens the space map now (the remote
## view's Surfaces panel does, as Factorio's).
signal space_map_requested

## Space locations that aren't planets: nothing to drop to.
const NOT_PLANETS := ["solar-system-edge", "shattered-planet"]

## The latest `plat`: index of the platform the character is on (0 on a planet), the planet it
## is on, destinations, and the platforms by index.
var on := 0
var here := ""
var destinations: Array = []
var platforms := {}  # index -> Dictionary
## The platform the view is on, set by factorio_ui.gd every frame: -1 the character's (`on`), 0 none
## (a planet, or the map or space map, whose frame has its own panel), else the platform watched
## in the remote view.
var view_index := -1


func _ready() -> void:
	theme = Kit.theme()  # the CanvasLayer between here and the window passes no theme down
	texture_filter = Kit.FILTER
	visible = false
	drop_requested.connect(func() -> void: choose_drop([] if choosing_drop() else planets()))
	drop_chosen.connect(drop_to)
	drop_cancelled.connect(func() -> void: plan_drop(""))


## Where a drop can go, as Factorio's list: the unlocked planets (`dest` less the places that aren't).
func planets() -> Array:
	return destinations.filter(func(d) -> bool: return not NOT_PLANETS.has(str(d)) and not str(d).begins_with("space-location"))


## A planet picked to drop to: at once when the platform is stopped over it, else when it gets
## there (Factorio's "Dropping to ...", until the red cross cancels it).
func drop_to(planet: String) -> void:
	choose_drop([])
	plan_drop(planet)
	_drop_if_there()


func plan_drop(planet: String) -> void:
	dropping_to = planet
	refresh()


func _drop_if_there() -> void:
	var p := current()
	if dropping_to != "" and not p.is_empty() and not p.has("to") and str(p.get("loc", "")) == dropping_to:
		dropping_to = ""
		Bridge.send({"t": "land"})
		refresh()


## A new surface (`welcome` or `surface`): the next `plat` fills in.
func surface_changed(platform_index: int, planet: String) -> void:
	on = platform_index
	here = planet
	if on == 0:
		dropping_to = ""
		choose_drop([])
	refresh()


func reset() -> void:
	on = 0
	here = ""
	dropping_to = ""
	choose_drop([])
	platforms.clear()
	destinations = []
	refresh()


func handle(msg: Dictionary) -> void:
	on = int(msg.get("on", 0))
	here = str(msg.get("here", ""))
	destinations = _array(msg.get("dest"))
	platforms.clear()
	for rec in _array(msg.get("l")):
		if rec is Dictionary:
			platforms[int(rec.get("i", 0))] = rec
	if on == 0:
		dropping_to = ""
	refresh()
	_drop_if_there()


## How big the nearest planet of a route is in the sky, 0 to 1, at `t` (0 at its start, 1 at its
## end): it shrinks over the first `fade` of the route and grows over the last (main.gd's sky).
static func planet_nearness(t: float, fade: float) -> float:
	var away := minf(t, 1.0 - t)
	return clampf(1.0 - away / fade, 0.0, 1.0)


## The platform the character is on, or {} on a planet.
func current() -> Dictionary:
	return platforms.get(on, {})


## Which platform the view is on (see `view_index`), and refreshes the panel when that changes.
func watch(index: int) -> void:
	if index != view_index:
		view_index = index
		refresh()


func shown() -> Dictionary:
	var i := on if view_index < 0 else view_index
	return platforms.get(i, {}) if i != 0 else {}


func refresh() -> void:
	var p := shown()
	visible = not p.is_empty()
	if visible:
		show_platform(p, on != 0 and int(p.get("i", 0)) == on)


static func _array(v) -> Array:
	return v if v is Array else []
