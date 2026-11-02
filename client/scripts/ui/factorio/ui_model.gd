extends RefCounted
## What the Factorio-style UI shows, and the one place that turns bridge messages into it (and UI
## actions into commands). The windows only read from here and redraw on the signals.
##
## A mod with the UI data (docs/PROTOCOL.md, "Factorio's windows") sends `slots`, `qb`, `rdet`,
## `craftable`, `cq`, `techs` and `rs`; older mods only `inv` (item totals, no slots) and
## `recipes` (names only), and then the inventory is shown as those stacks in order followed by
## empty slots, recipes have no groups, ingredients or times, and the quickbar is kept by the
## client (user://quickbar.cfg).

signal inventory_changed
signal recipes_changed
signal quickbar_changed
signal queue_changed
signal research_changed
signal guns_changed
## A chunk's map chart arrived (chunk coordinates).
signal map_changed(chunk: Vector2i)
signal tags_changed
## The surfaces the map can show (`surfs`) or the one it shows changed.
signal map_surfaces_changed
signal trains_changed
## Factorio's trains overview: the list arrived (`trl`), or a window asked to see it.
signal trains_overview_changed
signal trains_overview_requested
## Alt-mode icons (`ai`), the clipboard (`clip`), chat lines and statistics arrived.
signal alt_icons_changed
## Vulcanus' demolisher territories arrived or went (`terr`): territory_edges changed.
signal territories_changed
## The trains on the map's surface arrived (`mtr`): map_trains changed.
signal map_trains_changed
## The mod's answer to unghost(): `n` ghosts were removed (0: nothing there).
signal unghost_answered(q: int, n: int)
## A surface's roboports arrived and differ from before (`mrp`): roboports_of() and roboport_covers().
signal roboports_changed
## The mod's answer to ask_landing_pad(): the force's cargo landing pad on surface `si` (`found` false: none).
signal landing_pad_found(si: int, q: int, at: Vector2, found: bool)
## The mod answered about the hovered machine or beacon (`hinfo`): hover_info changed.
signal hover_info_changed
## The mod's answer to command(): its lines; `known` false when the bridge doesn't run that command.
signal command_answered(id: int, lines: Array, known: bool)
signal clipboard_changed
signal chat_received(from: String, text: String)
signal stats_received(kind: String, prec: int, rows: Array)
## The Bonuses window's `bonus` and the Permissions window's `perms` arrived.
signal bonuses_changed
signal perms_changed
signal logistics_changed
## The surface's planet changed (`planet`), or the streams below updated.
signal planet_changed
signal planet_data_changed
signal lightning_struck(position: Vector2, caught: bool)
signal rocket_launched(silo: int, position: Vector2, surface: String)
signal platform_state_changed(platform: int, state: String, old_state: String, location: String)
## The armour's or the open vehicle's equipment grid (`eq`), the character tab (`cinfo`) or the
## players (`pl`) changed.
signal equipment_changed(kind: String)
signal character_info_changed
signal players_changed
## The client's character is dead (`dead`): ticks until the respawn, where it died (Vector2 tiles or null).
signal died(ticks: int, at)
## Space Age (space.lua): the solar system arrived (`smap`), asteroid chunks moved (`ach`).
signal space_map_changed
signal asteroid_chunks_changed
## The force's alerts (`al`), Factoriopedia's index (`pidx`) and pages (`pedia`), and the
## logistic networks window's list (`lnets`) and one network (`lnet`).
signal alerts_changed
signal pedia_index_changed
signal pedia_page_received(kind: String, name: String)
signal lnets_changed
signal lnet_received(id: int)
## A map ping (a gps link clicked or posted in the chat): the map and minimap draw it a while.
signal pinged

const QUICKBAR_SLOTS := 10
## The character's main inventory in 2.x, used until the mod sends the real size.
const DEFAULT_MAIN_SIZE := 80
## Where the client-side quickbar is kept (tests point it elsewhere).
static var save_path := "user://quickbar.cfg"
const NO_LIMIT := 1 << 30

## Main inventory, slot by slot: {"item": String, "count": int}, or {} for an empty slot.
var main_slots: Array = []
## True once the mod sends real slots; until then main_slots are `inv`'s totals in order.
var has_slots := false
## Slot filters of the main inventory (Factorio's middle click): slot (1-based) -> item.
var main_filters := {}
## item -> total count in the main inventory.
var counts := {}

## Hand-craftable recipes in Factorio's order, each a dictionary:
##   name, group, subgroup, order (strings, "" unknown), energy (seconds, -1 unknown),
##   ingredients and products ([[item, amount], ...], empty when unknown),
##   craftable (how many can be made now, -1 unknown).
var recipes: Array = []
## Item groups for the crafting tabs, in order (names). Empty without group data: no tabs.
var groups: Array = []
var _group_order: Array = []
## name -> recipe with details, kept across `recipes` updates and reconnects.
var _details := {}

## Quickbar: QUICKBAR_SLOTS item names, "" for an empty slot.
var quickbar: Array = []
## True once the mod keeps the quickbar (then pins are sent, not saved here).
var server_quickbar := false

## Crafting queue: [{"recipe", "count", "progress" (0..1)}]; today only its length (`me.q`).
var craft_queue: Array = []
var craft_queue_size := 0

## The character's other inventories by slot ("guns", "ammo", "armor", "trash"), each a list like
## main_slots. Empty until the mod sends `slots`.
var other_slots := {}
## The mod's whole quickbar (100 names, 10 pages) and the page shown.
var quickbar_page := 1
## The upper quickbar row's page when the page chooser set it (0: the page after quickbar_page).
var quickbar_upper := 0
var _server_quickbar: Array = []

## Technology name -> {order, prerequisites, ingredients [[pack, amount]], count, seconds,
## state (0 locked, 1 available, 2 researched), trigger}; and the research in progress.
var techs := {}
var research := ""
var research_progress := 0.0
var research_queue: Array = []
## [[lab unit, status name], ...] for labs near the camera ("working", "missing_science_packs"...).
var labs: Array = []

## The map, chunk by chunk as requested with request_map(): Vector2i -> Image (n x n pixels, one per
## tiles-per-pixel square, north-west first), or null for a chunk the force hasn't charted yet.
var map_charts := {}
## What the map view's switches draw over each chunk (the chart's `ov`): Vector2i -> [[kind, x, y,
## ...], ...] with positions in tiles (docs/PROTOCOL.md "Map"); a chunk without any isn't kept.
var map_overlays := {}
## The trains on the map's surface (`mtr`), six numbers per carriage: x, y (1/256 tile),
## orientation (1/1000 turn), length, width (1/256 tile), colour 0xRRGGBB.
var map_trains := PackedInt32Array()
## What radars cover on the map's surface (`mtr` `cov`): a square of chunks per working radar.
## With the ground round the character (COVERED_RADIUS) the rest of the map is dimmed, as Factorio's.
var map_coverage: Array[Rect2i] = []
var map_coverage_known := false
const COVERED_RADIUS := 96.0
var _map_train_parts := PackedInt32Array()
var _map_trains_asked := -1000000
## Every roboport of the force on a surface (`mrp`, H13), for the map's logistic layer and what
## counts as seen (a chunk whose centre lies in a construction area, as the mod counts it):
## si -> {"l": PackedInt32Array [x, y, logistic radius, construction radius, ...] (1/256 tile),
## "at": {Vector2i (x, y): true}, "chunks": {Vector2i chunk: true}}. Asked for every
## ROBOPORTS_EVERY_MSEC while a map or the remote view needs them.
var _roboports := {}
var _roboport_parts := {}  # si -> [next part number, PackedInt32Array so far]
var _roboports_asked := {}  # si -> msec
var _roboport_q := 0
## Bumped whenever a surface's roboports change (the remote view's fog redraws).
var roboports_version := 0
const ROBOPORTS_EVERY_MSEC := 10000
var _lpad_q := 0
## Map tags: [{"id", "position" (Vector2, tiles), "text", "icon_type", "icon_name" ("" none)}].
var map_tags: Array = []
## The surfaces the map can show (`surfs`): [{"si", "name", "planet" ("" on a platform),
## "platform" (its name, "" on a planet), "pf" (platform index)}].
var map_surfaces: Array = []
## Factorio's trains overview (`trl`): [{"id", "state", "manual", "stop", "group", "carriages",
## "unit" (front carriage), "position" (tiles), "si", "speed" (tiles a tick), "cargo" [[item, count]],
## "fluid" [[fluid, amount]]}].
var trains_overview: Array = []
## The surface the character is on (from `welcome` / `surface`), and the one the map shows (the
## map view's surface switcher; 0 or the same: the character's).
var character_si := 0
var map_si := 0

## Trains near the camera, by train id: {"state" (Factorio's train_state name), "manual" (bool),
## "speed" (tiles per tick, negative backwards), "station" (unit of the stop it is at, 0 none),
## "dest" (name of the stop it is heading for), "carriages" (units, front first)}; and each
## carriage's train id.
var trains := {}
var train_of_unit := {}

## The `guns` message: [[gun, ammo, magazines], ...] per gun slot ("" when empty), and the selected
## slot (1-based).
var guns: Array = []
var selected_gun := 1

## Alt-mode icons near the camera (`ai`): unit -> [icon type ("item", "fluid", "recipe"), name].
var alt_icons := {}
var _unghost_q := 0
## Demolisher territories (`terr`): their borders as tile segments, [a0, b0, a1, b1, ...] where a
## chunk of a territory meets ground that isn't that territory's.
var territory_edges := PackedVector2Array()
## The same territories' chunks (Vector2i -> true), which the map view stripes, and the surface
## they are on (`si`; 0 when the mod didn't say: then the character's).
var territory_chunks := {}
var territory_si := 0
## Pollution by chunk on the map's surface (charts' `pol`).
var map_pollution := {}
var _territory_parts: Array = []
## What the mod says about the machine or beacon under the mouse (`hinfo`): {"u" (its unit),
## "eff" ({sp, pr, co, po, q} in thousandths), "m" ([[module, count, quality], ...]), "b" (beacons
## reaching it), "n" (machines a beacon reaches), "de" (a beacon's distribution effectivity), "el"
## (its electricity, H20: {"e" joules in its buffer, "b" the buffer's size, "mx" / "mn" its max. and
## min. consumption in watts}), "rn" (a roboport's linked roboports, H14: [Vector2 tiles, ...])}.
var hover_info := {}
var _hinfo_q := 0
var _hinfo_unit := 0
var _hinfo_msec := -100000
## The clipboard while pasting (`clip`): [{"p" (proto id), "at" (Vector2 tiles from its centre), "d"}].
var clipboard: Array = []
## Blueprints and planners: exchange strings, the libraries, undo entries, qualities (planner_model.gd).
var planners = preload("res://scripts/ui/factorio/planner_model.gd").new()
## Build cursor previews (`eprops`): proto id -> {"under" (underground reach, tiles), "wire" (pole
## wire reach), "supply" (half side of a pole's supply area), "x" (the overlay drawn on hover and
## while placing: inserter vectors, roboport and drill areas, fluid connections; PROTOCOL.md)}.
var eprops := {}
## What items do besides building their entity (`iuse`): item -> {"t": [tile, other direction's
## tile or "", {tile id it may go on: true}], "c": [capsule action type, range, radius], "r":
## [support entity, elevated allowed 0/1] (rail planners), "b" / "p": the belt's underground or the
## pipe's pipe-to-ground item}.
var item_uses := {}
## Chat lines, oldest first: [from, text, time (msec)].
var chat_log: Array = []
var _command_id := 0
## The character's logistic requests (`clog`): [{"item", "min", "max" (-1 none), "quality"}],
## whether they are on, and whether unrequested items go to the trash.
var char_requests: Array = []
var char_requests_on := true
var char_trash_unrequested := false
## Its logistic sections one by one (`clog.sec`, the hub's form: {"i", "g", "on", "m", "man", "f"}),
## and the force's logistic group names (`clog.lgs`); null when the mod doesn't send them.
var char_sections = null
var logistic_groups: Array = []
## The character's colour (`ccol`); Factorio's default player orange until the mod says.
var char_color := Color8(255, 161, 66)
var char_color_known := false
## The logistic network the character stands in (`ln`): {"id", "logistic" [available, all],
## "construction" [available, all]}, or {} outside any network.
var network := {}
## What robots near the camera carry (`rc`): unit -> {"item_id" (world.protos.item_name), "count"}.
var robot_cargo := {}

## The planet the character is on (`planet`): {"name" ("space" on a platform), "props" (surface
## properties: gravity, pressure, magnetic-field, solar-power, ...), "day" (ticks per day),
## "always_day", "min_brightness", "solar" (multipliers, 1 = Nauvis), "dusk", "evening",
## "morning", "dawn" (day fractions)}; and each heat source's heating radius by entity prototype id.
var planet := {}
var heating_radius := {}
## Demolishers (`seg`): unit -> {"proto": id, "segments": [{"proto", "position" (Vector2, tiles),
## "orientation"}], head first}.
var demolishers := {}
var demolishers_serial := 0  # counts `seg`s, so demolishers.gd sees each one
## Gleba: plant growth (`pg`) by position (Vector2, tiles) -> 0..1, spawners' units out (`sp`),
## spider units' feet (`legs`, unit -> PackedVector2Array), freshness on belts (`bf`, unique id -> 0..1).
var plant_growth := {}
var spawner_units := {}
var legs := {}
var belt_freshness := {}
## Aquilo: units of frozen machines (`fz`).
var frozen := {}
## Cargo pods near the camera (`cp`): unit -> {"state", "destination", "surface"}.
var cargo_pods := {}
## The solar system (`smap`): locations [{"name", "type", "position" (Vector2, star map units),
## "unlocked", "surface"}] and connections [{"from", "to", "length" (km), "danger" (0..1)}].
var space_locations: Array = []
var space_connections: Array = []
## Asteroid chunks near the camera on a platform (`ach`): [{"name", "position", "velocity"
## (Vector2, tiles and tiles per second)}], and when they arrived (msec).
var asteroid_chunks: Array = []
var asteroid_chunks_msec := 0
## Belt items better than normal (`bq`): unique id -> quality.
var belt_quality := {}
## What can't be built on this surface (`planet.nb`): entity prototype id -> [property, min, max].
var not_buildable := {}

## Equipment grids (`eq`) by kind: "char" (the armour's) and "veh" (the open or driven vehicle's):
## {"unit", "w", "h" (0: none), "equipment": [{"name", "x", "y", "w", "h", "quality", "energy",
## "max_energy", "shield", "max_shield", "ghost"}], "shield", "max_shield", "battery", "max_battery",
## "power" (W made), "movement" (bonus, 1 = +100 %), "inventory", "movement_on", "night_vision",
## "roboport_on" (-1: no switch)}.
var grids := {"char": {"unit": 0, "w": 0, "h": 0, "equipment": []}, "veh": {"unit": 0, "w": 0, "h": 0, "equipment": []}}
## The character tab (`cinfo`): the message's fields as they came (see docs/PROTOCOL.md).
var character_info := {}
## The game's players (`pl`): [{"index", "name", "connected", "color", "unit" (their character, 0
## none), "surface", "admin", "afk" (ticks), "tag"}]; which one the client plays (0: the bridge's own
## character) and the client's character unit.
var players: Array = []
var me_player := 0
var me_unit := 0

## The force's alerts, in the mod's order: [{"kind", "count", "entities": [{"position" (tiles), "si",
## "name", "unit", "subject"}]}]. alerts_known is false until the mod sends any (an old mod).
var alerts: Array = []
var alerts_known := false
## Factoriopedia: [{"kind", "name", "group", "sub", "order"}] in the mod's order, the groups (tabs)
## [[group, order], ...], and pages by "kind/name" ({"found": bool, "d": {...}}).
var pedia_index: Array = []
var pedia_groups: Array = []
var pedia_pages := {}
var _pedia_asked := {}  # "kind/name" -> msec of the request
var _pedia_index_asked := -100000
## The logistic networks window: [{"id", "si", "surface", "logistic": [available, all], "construction",
## "cells", "storages", "providers", "requesters", "position" (tiles), "name"}], and networks' contents
## by id ({"id", "logistic", "construction", "items": [[item, count, quality?], ...]}).
var lnets: Array = []
var lnet := {}
## The last statistics reply's surface (0: all) and graph lines ([[name, [in...], [out...]], ...]).
var stats_si := 0
var stats_graph: Array = []
## An electric network's accumulators (`stats` kind electric, `st`): [[name, stored J averaged over the
## time scale, stored J now], ...].
var stats_storage: Array = []
## An electric network's last update (`ef`, joules per tick): [met, demand, used, available,
## stored, capacity], or [] when the mod couldn't read it.
var stats_flow: Array = []
## `bonus`: [[kind, value, [item names]], ...]; `perms`: [[group, [player names]], ...] and the
## client's player's group.
var bonuses: Array = []
var perm_groups: Array = []
var perm_me := ""
## Map pings: [[position (tiles), msec], ...], the newest last.
var pings: Array = []
const PING_SECONDS := 6.0

var _craftable := {}  # recipe -> count, from `craftable`
var _rdet: Array = []  # the latest complete `rdet` records
var _parts := {}  # message type -> the multi-part list being received


func _init() -> void:
	quickbar.resize(QUICKBAR_SLOTS)
	quickbar.fill("")
	_load_quickbar()
	set_inventory_totals([])


## Takes a bridge message if it is UI data; returns false for anything else.
func handle(msg: Dictionary) -> bool:
	match str(msg.get("t", "")):
		"inv":
			set_inventory_totals(_array(msg.get("l")))
		"recipes":
			set_recipe_list(_array(msg.get("l")))
		"slots":
			var lists = msg.get("l")
			main_filters.clear()
			for f in _array(msg.get("fl")):
				if f is Array and f.size() >= 2:
					main_filters[int(f[0])] = str(f[1])
			if lists is Dictionary:
				other_slots.clear()
				for role in lists:
					var list := _array(lists[role])
					if role == "main":
						set_inventory_slots(list, list.size())
					else:
						other_slots[role] = _slot_dicts(list)
				# The icons of blueprints, books and planners, drawn over the item (slot.gd).
				for e in _array(msg.get("ic")):
					var at := int(e[0]) - 1 if e is Array and e.size() >= 2 else -1
					if at >= 0 and at < main_slots.size() and not (main_slots[at] as Dictionary).is_empty():
						main_slots[at]["icons"] = _array(e[1])
				inventory_changed.emit()
		"qb":
			quickbar_page = maxi(1, int(msg.get("p", 1)))
			_server_quickbar = _array(msg.get("l"))
			var first := (quickbar_page - 1) * QUICKBAR_SLOTS
			set_quickbar(_server_quickbar.slice(first, first + QUICKBAR_SLOTS))
		"rdet":
			var list = _gather(msg)
			if list != null:
				_rdet = list
				_apply_recipe_details()
		"craftable":
			_craftable.clear()
			for entry in _array(msg.get("l")):
				if entry is Array and entry.size() >= 2:
					_craftable[str(entry[0])] = int(entry[1])
			if not _rdet.is_empty():
				_apply_recipe_details()
		"cq":
			var progress := int(msg.get("pr", 0)) / 1000.0
			var entries: Array = []
			for entry in _array(msg.get("l")):
				if entry is Array and entry.size() >= 4:
					entries.append({"index": int(entry[0]), "recipe": str(entry[1]), "count": int(entry[2]),
						"progress": progress if entries.is_empty() else 0.0})
			set_craft_queue(entries)
		"techs":
			var list = _gather(msg)
			if list != null:
				techs.clear()
				for r in list:
					if r is Array and r.size() >= 8:
						techs[str(r[0])] = {
							"order": str(r[1]), "prerequisites": _array(r[2]), "ingredients": _array(r[3]),
							"count": int(r[4]), "seconds": float(r[5]), "state": int(r[6]), "trigger": str(r[7]),
							"effects": [], "level": 1, "max_level": 1, "trigger_detail": [], "saved": 0.0, "formula": "",
						}
						if r.size() >= 14:
							var t: Dictionary = techs[str(r[0])]
							t["effects"] = _array(r[8])
							t["level"] = int(r[9])
							t["max_level"] = int(r[10])
							t["trigger_detail"] = _array(r[11])
							t["saved"] = int(r[12]) / 1000.0
							t["formula"] = str(r[13])
						techs[str(r[0])]["essential"] = int(r[14]) == 1 if r.size() >= 15 else true
				research_changed.emit()
		"chart":
			if not _shown_surface(msg):
				return true
			var chunk := Vector2i(int(msg.get("cx", 0)), int(msg.get("cy", 0)))
			var n := int(msg.get("n", 0))
			var pal := _array(msg.get("pal"))
			var px := _array(msg.get("px"))
			var image: Image = null
			if n > 0 and px.size() == n * n:
				image = chart_image(n, pal, px)
			map_charts[chunk] = image
			if msg.has("pol"):
				map_pollution[chunk] = int(msg["pol"])
			else:
				map_pollution.erase(chunk)
			var ov: Array = []
			for r in _array(msg.get("ov")):
				if r is Array and r.size() >= 3:
					var entry: Array = r.duplicate()
					entry[1] = int(r[1]) / 256.0
					entry[2] = int(r[2]) / 256.0
					if str(r[0]) == "w" and r.size() >= 5:  # a wire's other end, in tiles too
						entry[3] = int(r[3]) / 256.0
						entry[4] = int(r[4]) / 256.0
					ov.append(entry)
			if ov.is_empty():
				map_overlays.erase(chunk)
			elif n > 0:
				map_overlays[chunk] = ov
			map_changed.emit(chunk)
		"clog":
			char_requests = _requests(msg.get("l"))
			char_requests_on = int(msg.get("on", 1)) == 1
			char_trash_unrequested = int(msg.get("trash", 0)) == 1
			char_sections = _array(msg.get("sec")).duplicate(true) if msg.has("sec") else null
			logistic_groups = _array(msg.get("lgs"))
			logistics_changed.emit()
		"ccol":
			var c := _array(msg.get("c"))
			if c.size() >= 3:
				char_color = Color8(int(c[0]), int(c[1]), int(c[2]))
				char_color_known = true
				logistics_changed.emit()
		"ln":
			network = {}
			if int(msg.get("id", 0)) != 0:
				network = {"id": int(msg.get("id")), "logistic": _array(msg.get("log")), "construction": _array(msg.get("con"))}
			logistics_changed.emit()
		"planet":
			planet = {"name": str(msg.get("name", "")), "props": msg.get("props") if msg.get("props") is Dictionary else {},
				"day": int(msg.get("day", 0)), "always_day": int(msg.get("always", 0)) == 1,
				"min_brightness": int(msg.get("mb", 0)) / 1000.0, "solar": int(msg.get("sol", 1000)) / 1000.0,
				"dusk": int(msg.get("dusk", 0)) / 1000.0, "evening": int(msg.get("evening", 0)) / 1000.0,
				"morning": int(msg.get("morning", 0)) / 1000.0, "dawn": int(msg.get("dawn", 0)) / 1000.0}
			heating_radius.clear()
			for h in _array(msg.get("heat")):
				if h is Array and h.size() >= 2:
					heating_radius[int(h[0])] = float(h[1])
			not_buildable.clear()
			for r in _array(msg.get("nb")):
				if r is Array and r.size() >= 4:
					not_buildable[int(r[0])] = [str(r[1]), float(r[2]), float(r[3])]
			planet_changed.emit()
		"seg":
			demolishers.clear()
			for r in _array(msg.get("l")):
				if r is Array and r.size() >= 3:
					var segs: Array = []
					var f := _array(r[2])
					var i := 0
					while i + 3 < f.size():
						segs.append({"proto": int(f[i]), "position": Vector2(int(f[i + 1]), int(f[i + 2])) / 256.0,
							"orientation": int(f[i + 3]) / 1000.0})
						i += 4
					demolishers[int(r[0])] = {"proto": int(r[1]), "segments": segs}
			demolishers_serial += 1
			planet_data_changed.emit()
		"lt":
			for r in _array(msg.get("l")):
				if r is Array and r.size() >= 3:
					lightning_struck.emit(Vector2(int(r[0]), int(r[1])) / 256.0, int(r[2]) == 1)
		"pg":
			plant_growth.clear()
			var l := _array(msg.get("l"))
			var i := 0
			while i + 3 < l.size():
				plant_growth[Vector2(int(l[i + 1]), int(l[i + 2])) / 256.0] = int(l[i + 3]) / 1000.0
				i += 4
			planet_data_changed.emit()
		"sp":
			spawner_units.clear()
			var l := _array(msg.get("l"))
			var i := 0
			while i + 1 < l.size():
				spawner_units[int(l[i])] = int(l[i + 1])
				i += 2
			planet_data_changed.emit()
		"legs":
			legs.clear()
			for r in _array(msg.get("l")):
				if r is Array and r.size() >= 2:
					var feet := PackedVector2Array()
					var f := _array(r[1])
					var i := 0
					while i + 1 < f.size():
						feet.append(Vector2(int(f[i]), int(f[i + 1])) / 256.0)
						i += 2
					legs[int(r[0])] = feet
			planet_data_changed.emit()
		"bf":
			if int(msg.get("part", 1)) == 1:
				belt_freshness.clear()
			var l := _array(msg.get("l"))
			var i := 0
			while i + 1 < l.size():
				belt_freshness[int(l[i])] = int(l[i + 1]) / 1000.0
				i += 2
		"fz":
			frozen.clear()
			for u in _array(msg.get("l")):
				frozen[int(u)] = true
			planet_data_changed.emit()
		"cp":
			cargo_pods.clear()
			for r in _array(msg.get("l")):
				if r is Array and r.size() >= 4:
					cargo_pods[int(r[0])] = {"state": str(r[1]), "destination": str(r[2]), "surface": str(r[3])}
			planet_data_changed.emit()
		"smap":
			space_locations.clear()
			for r in _array(msg.get("loc")):
				if r is Array and r.size() >= 6:
					space_locations.append({"name": str(r[0]), "type": str(r[1]), "position": Vector2(int(r[2]), int(r[3])) / 1000.0,
						"unlocked": int(r[4]) == 1, "surface": int(r[5]) == 1,
						"magnitude": int(r[6]) / 1000.0 if r.size() >= 9 else 1.0, "orbit": int(r[7]) == 1 if r.size() >= 9 else true,
						"label": int(r[8]) / 1000.0 if r.size() >= 9 else 0.25})
			space_connections.clear()
			for r in _array(msg.get("con")):
				if r is Array and r.size() >= 4:
					space_connections.append({"from": str(r[0]), "to": str(r[1]), "length": int(r[2]), "danger": int(r[3]) / 1000.0})
			space_map_changed.emit()
		"ach":
			asteroid_chunks.clear()
			for r in _array(msg.get("l")):
				if r is Array and r.size() >= 5:
					asteroid_chunks.append({"name": str(r[0]), "position": Vector2(int(r[1]), int(r[2])) / 256.0,
						"velocity": Vector2(int(r[3]), int(r[4])) / 256.0})
			asteroid_chunks_msec = Time.get_ticks_msec()
			asteroid_chunks_changed.emit()
		"bq":
			belt_quality.clear()
			for r in _array(msg.get("l")):
				if r is Array and r.size() >= 2:
					belt_quality[int(r[0])] = str(r[1])
		"rk":
			rocket_launched.emit(int(msg.get("u", 0)), Vector2(int(msg.get("x", 0)), int(msg.get("y", 0))) / 256.0, str(msg.get("s", "")))
		"pst":
			platform_state_changed.emit(int(msg.get("i", 0)), str(msg.get("st", "")), str(msg.get("old", "")), str(msg.get("loc", "")))
		"rc":
			robot_cargo.clear()
			var l := _array(msg.get("l"))
			var i := 0
			while i + 2 < l.size():
				robot_cargo[int(l[i])] = {"item_id": int(l[i + 1]), "count": int(l[i + 2])}
				i += 3
		"tr":
			trains.clear()
			train_of_unit.clear()
			for r in _array(msg.get("l")):
				if r is Array and r.size() >= 7:
					var id := int(r[0])
					var units: Array = []
					for u in _array(r[6]):
						units.append(int(u))
						train_of_unit[int(u)] = id
					trains[id] = {"state": str(r[1]), "manual": int(r[2]) == 1, "speed": int(r[3]) / 1000.0,
						"station": int(r[4]), "dest": str(r[5]), "carriages": units}
			trains_changed.emit()
		"trl":
			var list = _gather(msg)
			if list != null:
				trains_overview.clear()
				for r in list:
					if r is Array and r.size() >= 13:
						trains_overview.append({"id": int(r[0]), "state": str(r[1]), "manual": int(r[2]) == 1, "stop": str(r[3]),
							"group": str(r[4]), "carriages": int(r[5]), "unit": int(r[6]),
							"position": Vector2(int(r[7]), int(r[8])) / 256.0, "si": int(r[9]), "speed": int(r[10]) / 1000.0,
							"cargo": _array(r[11]), "fluid": _array(r[12])})
				trains_overview_changed.emit()
		"surfs":
			map_surfaces.clear()
			for r in _array(msg.get("l")):
				if r is Array and r.size() >= 5:
					map_surfaces.append({"si": int(r[0]), "name": str(r[1]), "planet": str(r[2]),
						"platform": str(r[3]), "pf": int(r[4])})
			map_surfaces_changed.emit()
		"tags":
			if not _shown_surface(msg):
				return true
			map_tags.clear()
			for r in _array(msg.get("l")):
				if r is Array and r.size() >= 6:
					map_tags.append({"id": int(r[0]), "position": Vector2(int(r[1]), int(r[2])) / 256.0,
						"text": str(r[3]), "icon_type": str(r[4]), "icon_name": str(r[5])})
			tags_changed.emit()
		"unghost":
			unghost_answered.emit(int(msg.get("q", 0)), int(msg.get("n", 0)))
		"mrp":
			_roboport_part(msg)
		"lpad":
			landing_pad_found.emit(int(msg.get("si", 0)), int(msg.get("q", 0)),
				Vector2(int(msg.get("x", 0)), int(msg.get("y", 0))) / 256.0, msg.has("x") and msg.has("y"))
		"hinfo":
			if int(msg.get("q", 0)) == _hinfo_q:
				var info := {"u": int(msg.get("u", 0)), "m": []}
				if msg.get("eff") is Dictionary:
					var eff := {}
					for k in msg["eff"]:
						eff[str(k)] = int(msg["eff"][k])
					info["eff"] = eff
				for r in _array(msg.get("m")):
					if r is Array and r.size() >= 2:
						info["m"].append([str(r[0]), int(r[1]), str(r[2]) if r.size() >= 3 else "normal"])
				for k in ["b", "n", "de"]:
					if msg.has(k):
						info[k] = int(msg[k])
				if msg.has("rn"):
					var links: Array = []
					var flat := _array(msg["rn"])
					for i in range(0, flat.size() - 1, 2):
						links.append(Vector2(int(flat[i]), int(flat[i + 1])) / 256.0)
					info["rn"] = links
				if msg.get("el") is Dictionary:
					var el := {}
					for k in ["e", "b", "mx", "mn"]:
						el[k] = float(msg["el"].get(k, 0.0))
					info["el"] = el
				hover_info = info
				hover_info_changed.emit()
		"cmdr":
			var lines: Array = []
			for l in _array(msg.get("l")):
				lines.append(str(l))
			command_answered.emit(int(msg.get("id", 0)), lines, int(msg.get("ok", 1)) != 0)
		"terr":
			if int(msg.get("part", 1)) == 1:
				_territory_parts.clear()
			_territory_parts.append_array(_array(msg.get("l")))
			if int(msg.get("part", 1)) >= int(msg.get("parts", 1)):
				territory_edges = territory_borders(_territory_parts)
				territory_chunks.clear()
				for t in _territory_parts:
					var flat := _array(t)
					for i in range(0, flat.size() - 1, 2):
						territory_chunks[Vector2i(int(flat[i]), int(flat[i + 1]))] = true
				territory_si = int(msg.get("si", 0))
				territories_changed.emit()
		"mtr":
			if int(msg.get("si", 0)) == shown_surface():
				if int(msg.get("part", 1)) == 1:
					_map_train_parts.clear()
					if msg.has("cov"):
						var cov := _array(msg.get("cov"))
						map_coverage.clear()
						for i in range(0, cov.size() - 2, 3):
							var d := int(cov[i + 2])
							map_coverage.append(Rect2i(int(cov[i]) - d, int(cov[i + 1]) - d, 2 * d + 1, 2 * d + 1))
						map_coverage_known = true
				for v in _array(msg.get("l")):
					_map_train_parts.append(int(v))
				if int(msg.get("part", 1)) >= int(msg.get("parts", 1)):
					map_trains = _map_train_parts.duplicate()
					map_trains_changed.emit()
		"ai":
			alt_icons.clear()
			for r in _array(msg.get("l")):
				# A machine without a recipe or filter shows nothing (not an empty frame).
				if r is Array and r.size() >= 3 and str(r[2]) != "":
					var icon := [str(r[1]), str(r[2])]
					if r.size() >= 4 and r[3] is Array:  # a filter inserter's other filters
						for f in r[3]:
							icon.append(str(f))
					alt_icons[int(r[0])] = icon
			alt_icons_changed.emit()
		"bp", "bp_ok", "bpl", "hist", "quals":
			planners.handle(msg)
		"clip":
			clipboard.clear()
			for r in _array(msg.get("l")):
				if r is Array and r.size() >= 4:
					clipboard.append({"p": int(r[0]), "at": Vector2(int(r[1]), int(r[2])) / 256.0, "d": int(r[3])})
			clipboard_changed.emit()
		"iuse":
			if int(msg.get("part", 1)) == 1:
				item_uses.clear()
			for r in _array(msg.get("l")):
				if not (r is Array and r.size() >= 3):
					continue
				var item := str(r[0])
				var kind := str(r[1])
				var u: Dictionary = item_uses.get(item, {})
				match kind:
					"t":
						var on := {}
						for id in (r[4] if r.size() > 4 and r[4] is Array else []):
							on[int(id)] = true
						u["t"] = [str(r[2]), str(r[3]) if r.size() > 3 else "", on]
					"c":
						u["c"] = [str(r[2]), float(r[3]) if r.size() > 3 else 0.0, float(r[4]) if r.size() > 4 else 0.0]
					"r":
						u["r"] = [str(r[2]), int(r[3]) if r.size() > 3 else 0]
					"b", "p", "m":
						u[kind] = str(r[2])
				item_uses[item] = u
		"eprops":
			for r in _array(msg.get("l")):
				if r is Array and r.size() >= 4:
					eprops[int(r[0])] = {"under": float(r[1]), "wire": float(r[2]), "supply": float(r[3]),
						"x": r[4] if r.size() > 4 and r[4] is Dictionary else {}}
		"chat":
			var c := _array(msg.get("c"))
			var line := [str(msg.get("from", "")), str(msg.get("text", "")), Time.get_ticks_msec(),
				Color(float(c[0]), float(c[1]), float(c[2])) if c.size() >= 3 else Color(0, 0, 0, 0)]
			chat_log.append(line)
			while chat_log.size() > 200:
				chat_log.pop_front()
			chat_received.emit(line[0], line[1])
		"bonus":
			bonuses = []
			for r in _array(msg.get("l")):
				if r is Array and r.size() >= 3:
					bonuses.append([str(r[0]), float(r[1]), _array(r[2])])
			bonuses_changed.emit()
		"perms":
			perm_groups = []
			for r in _array(msg.get("l")):
				if r is Array and r.size() >= 2:
					perm_groups.append([str(r[0]), _array(r[1])])
			perm_me = str(msg.get("me", ""))
			perms_changed.emit()
		"stats":
			stats_si = int(msg.get("si", 0))
			stats_graph = _array(msg.get("gr"))
			stats_storage = _array(msg.get("st"))
			stats_flow = _array(msg.get("ef"))
			stats_received.emit(str(msg.get("kind", "item")), int(msg.get("prec", 2)), _array(msg.get("l")))
		"eq":
			var kind := str(msg.get("kind", "char"))
			var g := {"unit": int(msg.get("u", 0)), "w": int(msg.get("w", 0)), "h": int(msg.get("h", 0)), "equipment": [],
				"shield": int(msg.get("sh", 0)), "max_shield": int(msg.get("msh", 0)), "battery": float(msg.get("bat", 0)),
				"max_battery": float(msg.get("mbat", 0)), "power": float(msg.get("gen", 0)), "movement": int(msg.get("mv", 0)) / 1000.0,
				"inventory": int(msg.get("inv", 0)), "movement_on": int(msg.get("mvon", 1)) == 1, "night_vision": int(msg.get("nv", 0)) == 1,
				"roboport_on": int(msg.get("rb", -1))}
			for r in _array(msg.get("l")):
				if r is Array and r.size() >= 11:
					g["equipment"].append({"name": str(r[0]), "x": int(r[1]), "y": int(r[2]), "w": int(r[3]), "h": int(r[4]),
						"quality": str(r[5]), "energy": float(r[6]), "max_energy": float(r[7]), "shield": float(r[8]),
						"max_shield": float(r[9]), "ghost": int(r[10]) == 1})
			grids[kind] = g
			equipment_changed.emit(kind)
		"dead":
			var at = Vector2(int(msg["x"]), int(msg["y"])) / 256.0 if msg.has("x") else null
			died.emit(int(msg.get("left", 0)), at)
		"cinfo":
			character_info = msg.duplicate()
			character_info.erase("t")
			character_info.erase("k")
			character_info_changed.emit()
		"pl":
			players.clear()
			me_player = int(msg.get("me", 0))
			me_unit = int(msg.get("u", 0))
			for r in _array(msg.get("l")):
				if r is Array and r.size() >= 11:
					players.append({"index": int(r[0]), "name": str(r[1]), "connected": int(r[2]) == 1,
						"color": Color8(int(r[3]), int(r[4]), int(r[5])), "unit": int(r[6]), "surface": str(r[7]),
						"admin": int(r[8]) == 1, "afk": int(r[9]), "tag": str(r[10]),
						"armor": str(r[11]) if r.size() >= 12 else ""})
			players_changed.emit()
		"al":
			alerts.clear()
			alerts_known = true
			for a in _array(msg.get("l")):
				if a is Array and a.size() >= 3:
					var ents: Array = []
					for e in _array(a[2]):
						if e is Array and e.size() >= 5:
							ents.append({"position": Vector2(int(e[0]), int(e[1])) / 256.0, "si": int(e[2]), "name": str(e[3]),
								"unit": int(e[4]), "subject": str(e[5]) if e.size() > 5 else ""})
					alerts.append({"kind": str(a[0]), "count": int(a[1]), "entities": ents})
			alerts_changed.emit()
		"pidx":
			var groups := _array(msg.get("g"))
			if int(msg.get("part", 1)) == 1:
				pedia_groups = groups
			var list = _gather(msg)
			if list != null:
				pedia_index.clear()
				for r in list:
					if r is Array and r.size() >= 5:
						pedia_index.append({"kind": str(r[0]), "name": str(r[1]), "group": str(r[2]), "sub": str(r[3]), "order": str(r[4])})
				pedia_index_changed.emit()
		"pedia":
			var key := "%s/%s" % [str(msg.get("kind", "")), str(msg.get("name", ""))]
			pedia_pages[key] = {"found": int(msg.get("found", 0)) == 1, "d": msg.get("d") if msg.get("d") is Dictionary else {}}
			_pedia_asked.erase(key)
			pedia_page_received.emit(str(msg.get("kind", "")), str(msg.get("name", "")))
		"lnets":
			lnets.clear()
			for r in _array(msg.get("l")):
				if r is Array and r.size() >= 12:
					lnets.append({"id": int(r[0]), "si": int(r[1]), "surface": str(r[2]), "logistic": _array(r[3]),
						"construction": _array(r[4]), "cells": int(r[5]), "storages": int(r[6]), "providers": int(r[7]),
						"requesters": int(r[8]), "position": Vector2(int(r[9]), int(r[10])) / 256.0, "name": str(r[11])})
			lnets_changed.emit()
		"lnet":
			var id := int(msg.get("id", 0))
			if int(msg.get("found", 0)) == 1:
				lnet[id] = {"id": id, "logistic": _array(msg.get("log")), "construction": _array(msg.get("con")),
					"items": _array(msg.get("items"))}
			else:
				lnet.erase(id)
			lnet_received.emit(id)
		"rs":
			research = str(msg.get("cur", ""))
			research_progress = int(msg.get("pr", 0)) / 1000.0
			research_queue = _array(msg.get("q"))
			labs = _array(msg.get("labs"))
			research_changed.emit()
		_:
			return false
	return true


# --- inventory -------------------------------------------------------------------------------

## `inv`: [[item, count], ...] totals. Shown as one stack each, then empty slots.
func set_inventory_totals(list: Array) -> void:
	if has_slots:
		return  # the slot data is better; `inv` is only kept for old clients
	var slots: Array = []
	for entry in list:
		if entry is Array and entry.size() >= 2 and int(entry[1]) > 0:
			slots.append({"item": str(entry[0]), "count": int(entry[1])})
	while slots.size() < DEFAULT_MAIN_SIZE or slots.size() % 10 != 0:
		slots.append({})
	_set_slots(slots)


## The main inventory by slot. `slots` is [[item, count(, quality)] or empty ([] / {} / 0), ...]
## in slot order; `size` the inventory size (slots beyond the list are empty).
func set_inventory_slots(slots: Array, size: int) -> void:
	has_slots = true
	var out := _slot_dicts(slots)
	while out.size() < size:
		out.append({})
	_set_slots(out)


## [{"item", "count", "quality"?} or {}, ...] from the protocol's slot list.
static func _slot_dicts(slots: Array) -> Array:
	var out: Array = []
	for entry in slots:
		if entry is Array and entry.size() >= 2 and str(entry[0]) != "" and int(entry[1]) > 0:
			var d := {"item": str(entry[0]), "count": int(entry[1])}
			if entry.size() >= 3:
				d["quality"] = str(entry[2])
			if entry.size() >= 4:
				d["freshness"] = int(entry[3]) / 1000.0  # spoiling items (Gleba): 1 fresh, 0 about to spoil
			out.append(d)
		else:
			out.append({})
	return out


## Moves the stack in slot `from_slot` (1-based) of `from_role` to `to_slot` of `to_role`, like a
## click in Factorio (merge, swap; `n` > 0 splits). Roles: main, guns, ammo, armor, trash, or the
## open machine's chest, input, output, fuel, burnt, modules (give its unit).
func move(from_role: String, from_slot: int, to_role: String, to_slot: int, n := 0, unit := 0) -> void:
	var cmd := {"t": "move", "from": from_role, "fi": from_slot, "to": to_role, "ti": to_slot, "n": n}
	if unit != 0:
		cmd["u"] = unit
	Bridge.send(cmd)


## Factorio's Shift / Ctrl clicks on slot `index` of `role`: `kind` "stack", "half", "all" or
## "allhalf", to the other inventory (the open machine's with its unit, else the character's own).
func xfer(role: String, index: int, kind: String, unit := 0) -> void:
	var cmd := {"t": "xfer", "from": role, "fi": index, "k": kind}
	if unit != 0:
		cmd["u"] = unit
	Bridge.send(cmd)


## Filters slot `index` (1-based) of the main inventory to an item ("" clears it).
func set_slot_filter(index: int, item: String) -> void:
	Bridge.send({"t": "inv_filter", "i": index, "item": item})


func sort_inventory(role := "main", unit := 0) -> void:
	var cmd := {"t": "sort", "inv": role}
	if unit != 0:
		cmd["u"] = unit
	Bridge.send(cmd)


func _set_slots(slots: Array) -> void:
	main_slots = slots
	counts.clear()
	for s in slots:
		if not s.is_empty():
			counts[s["item"]] = int(counts.get(s["item"], 0)) + int(s["count"])
	_update_craftable()
	inventory_changed.emit()


## The icons of the first stack of a blueprint, book or planner in the main inventory ([] for
## none): what the quickbar shows over it.
func icons_of(item: String) -> Array:
	for s in main_slots:
		if s is Dictionary and str(s.get("item", "")) == item and s.has("icons"):
			return s["icons"]
	return []


func count_of(item: String) -> int:
	return int(counts.get(item, 0))


## A module (`iuse` "m"): clicked on a building or ghost, it goes in or is asked for (F6).
func is_module(item: String) -> bool:
	return item != "" and (item_uses.get(item, {}) as Dictionary).has("m")


## Asks for a module in an entity's module slots (`modreq`): within reach the mod puts it in,
## otherwise (remote view, a ghost, out of reach) it is requested for the robots or a platform's
## hub to bring. `slot` (1-based) from the machine screen; `clear` takes requests back.
func request_module(target: Dictionary, item: String, quality := "normal", slot := 0, clear := false) -> void:
	var cmd := target.duplicate()
	cmd["t"] = "modreq"
	if clear:
		cmd["clr"] = 1
	else:
		cmd["item"] = item
		if quality != "normal" and quality != "":
			cmd["q"] = quality
	if slot > 0:
		cmd["s"] = slot
	Bridge.send(cmd)


## An inventory of the character's by role ("main", "guns", "ammo", "armor", "trash"): its slots
## like main_slots. Without `slots` from the mod, guns and ammo come from the `guns` message.
func slots_of(role: String) -> Array:
	if role == "main":
		return main_slots
	if other_slots.has(role):
		return other_slots[role]
	if role == "guns" or role == "ammo":
		var out: Array = []
		for g in guns:
			var item := str(g[0] if role == "guns" else g[1]) if g is Array and g.size() >= 3 else ""
			var n := 1 if role == "guns" else int(g[2]) if g is Array and g.size() >= 3 else 0
			out.append({"item": item, "count": n} if item != "" and n > 0 else {})
		return out
	return []


## The stack in a slot (1-based) of one of the character's inventories, or {}.
func stack_at(role: String, index: int) -> Dictionary:
	var list := slots_of(role)
	return list[index - 1] if index >= 1 and index <= list.size() and list[index - 1] is Dictionary else {}


## Slots of the character's inventories are known one by one (else only the item totals).
func knows_slots(role: String) -> bool:
	return has_slots if role == "main" else other_slots.has(role)


# --- guns ------------------------------------------------------------------------------------

## The `guns` message.
func set_guns(sel: int, list: Array) -> void:
	selected_gun = maxi(1, sel)
	guns = list
	guns_changed.emit()


## Uses gun slot `index` (1-based), like Factorio's Tab or clicking the gun.
func select_gun(index: int) -> void:
	if index != selected_gun:
		Bridge.send({"t": "gun", "i": index})


# --- recipes ---------------------------------------------------------------------------------

## `recipes`: names only. Details already known (set_recipe_details) are kept.
func set_recipe_list(names: Array) -> void:
	var out: Array = []
	for n in names:
		var name := str(n)
		out.append(_details[name] if _details.has(name) else _recipe({"name": name}))
	recipes = out
	_update_groups(_group_order)
	if not groups.is_empty():  # without details, keep the mod's order
		recipes.sort_custom(_recipe_before)
	_update_craftable()
	recipes_changed.emit()


## Recipes with details. Each entry is a dictionary with "name" and any of
## "group", "subgroup", "order", "energy", "ingredients", "products", "craftable" (see `recipes`);
## `group_order` lists the groups in Factorio's tab order (else they follow the recipes).
## Recipes are shown sorted by group, subgroup and order, like Factorio's crafting grid.
func set_recipe_details(list: Array, group_order: Array = []) -> void:
	var out: Array = []
	for entry in list:
		var r := _recipe(entry if entry is Dictionary else {"name": str(entry)})
		_details[r["name"]] = r
		out.append(r)
	recipes = out
	_group_order = group_order.duplicate()
	_update_groups(_group_order)
	if not groups.is_empty():  # without details, keep the mod's order
		recipes.sort_custom(_recipe_before)
	_update_craftable()
	recipes_changed.emit()


static func _recipe_before(a: Dictionary, b: Dictionary) -> bool:
	for key in ["group_index", "subgroup", "order", "name"]:
		if a[key] != b[key]:
			return a[key] < b[key]
	return false


func recipe(name: String) -> Dictionary:
	for r in recipes:
		if r["name"] == name:
			return r
	return {}


func _recipe(d: Dictionary) -> Dictionary:
	return {
		"name": str(d.get("name", "")),
		"group": str(d.get("group", "")),
		"subgroup": str(d.get("subgroup", "")),
		"order": str(d.get("order", "")),
		"group_index": 0,
		"energy": float(d.get("energy", -1)),
		"ingredients": _array(d.get("ingredients")),
		"products": _array(d.get("products")),
		"server_craftable": int(d.get("craftable", -1)),
		"craftable": int(d.get("craftable", -1)),
	}


## The groups that have recipes, in `order` first.
func _update_groups(order: Array) -> void:
	var used := {}
	for r in recipes:
		used[r["group"]] = true
	groups = []
	for g in order:
		if used.has(str(g)):
			groups.append(str(g))
	for r in recipes:
		if r["group"] != "" and not groups.has(r["group"]):
			groups.append(r["group"])
	for r in recipes:
		r["group_index"] = maxi(0, groups.find(r["group"]))


## How many of each recipe the inventory has ingredients for (when the mod didn't say), counting
## direct ingredients only.
func _update_craftable() -> void:
	for r in recipes:
		if r["server_craftable"] >= 0 or r["ingredients"].is_empty():
			r["craftable"] = r["server_craftable"]
			continue
		var n := NO_LIMIT
		for ing in r["ingredients"]:
			if ing is Array and ing.size() >= 2 and int(ing[1]) > 0:
				n = mini(n, count_of(str(ing[0])) / int(ing[1]))
		r["craftable"] = n if n != NO_LIMIT else -1


## `rdet` records -> set_recipe_details, with the `craftable` counts. Subgroups sort by their
## own order string first, as in Factorio's crafting grid; groups by theirs.
func _apply_recipe_details() -> void:
	var list: Array = []
	var group_orders := {}
	for r in _rdet:
		if not (r is Array and r.size() >= 10):
			continue
		group_orders[str(r[3])] = str(r[4])
		list.append({
			"name": str(r[0]), "energy": float(r[1]), "group": str(r[3]),
			"subgroup": "%s %s" % [str(r[6]), str(r[5])], "order": str(r[7]),
			"ingredients": _pairs(_array(r[8])), "products": _pairs(_array(r[9])),
			"craftable": int(_craftable.get(str(r[0]), 0)),
		})
	var order: Array = group_orders.keys()
	order.sort_custom(func(a, b) -> bool: return group_orders[a] < group_orders[b])
	set_recipe_details(list, order)


## [[type, name, amount], ...] -> [[name, amount], ...] (whole amounts shown rounded).
static func _pairs(list: Array) -> Array:
	var out: Array = []
	for x in list:
		if x is Array and x.size() >= 3:
			out.append([str(x[1]), float(x[2])])
	return out


func cancel_craft(index: int, n := 1) -> void:
	Bridge.send({"t": "cancel_craft", "i": index, "n": n})


## Hand-craft n of a recipe.
func craft(name: String, n: int) -> void:
	Bridge.send({"t": "craft", "recipe": name, "n": n})


# --- quickbar --------------------------------------------------------------------------------

func pin(index: int, item: String) -> void:
	if index < 0 or index >= QUICKBAR_SLOTS:
		return
	if server_quickbar:  # the mod keeps it: ask, and redraw when its `qb` comes back
		for i in _server_quickbar.size():
			if str(_server_quickbar[i]) == item:
				Bridge.send({"t": "qb_set", "i": i + 1, "item": ""})
		Bridge.send({"t": "qb_set", "i": (quickbar_page - 1) * QUICKBAR_SLOTS + index + 1, "item": item})
		return
	for i in QUICKBAR_SLOTS:  # an item lives in one slot, as in Factorio
		if quickbar[i] == item:
			quickbar[i] = ""
	quickbar[index] = item
	_save_quickbar()
	quickbar_changed.emit()


## Factorio shows two quickbar rows: the page in use and, above it, another page: the next one
## (1-10 wrap) until X swaps the rows or the page chooser sets it (quickbar_upper, kept by the client).
func quickbar_upper_page() -> int:
	return quickbar_upper if quickbar_upper > 0 else quickbar_page % 10 + 1


## The item names on quickbar page p (1-10), "" for empty slots. Only the mod keeps pages: while the
## client keeps the quickbar every other page is empty.
func quickbar_page_items(p: int) -> Array:
	var out: Array = []
	var first := (p - 1) * QUICKBAR_SLOTS
	for i in QUICKBAR_SLOTS:
		var v = _server_quickbar[first + i] if first + i < _server_quickbar.size() else ""
		out.append(v if v is String else "")
	return out


## Pins an item to slot index (0-9) of quickbar page p, or clears it with "" (the mod's pages only).
func pin_on_page(p: int, index: int, item: String) -> void:
	if not server_quickbar or index < 0 or index >= QUICKBAR_SLOTS:
		return
	if item != "":
		for i in _server_quickbar.size():
			if str(_server_quickbar[i]) == item:
				Bridge.send({"t": "qb_set", "i": i + 1, "item": ""})
	Bridge.send({"t": "qb_set", "i": (p - 1) * QUICKBAR_SLOTS + index + 1, "item": item})


func unpin(index: int) -> void:
	if index < 0 or index >= QUICKBAR_SLOTS:
		return
	if server_quickbar:
		Bridge.send({"t": "qb_set", "i": (quickbar_page - 1) * QUICKBAR_SLOTS + index + 1, "item": ""})
		return
	quickbar[index] = ""
	_save_quickbar()
	quickbar_changed.emit()


## Shows quickbar page p (1-10; Shift+1-0, page chooser) in the lower row. Only the mod keeps
## pages; the client's own quickbar has one.
func select_quickbar_page(p: int) -> void:
	p = clampi(p, 1, 10)
	if not server_quickbar or p == quickbar_page:
		return
	quickbar_page = p
	var first := (quickbar_page - 1) * QUICKBAR_SLOTS
	set_quickbar(_server_quickbar.slice(first, first + QUICKBAR_SLOTS))
	Bridge.send({"t": "qb_page", "p": quickbar_page})


## Swaps the two shown quickbar rows' pages (Factorio's X, Rotate active quickbars).
func swap_quickbars() -> void:
	if not server_quickbar:
		return
	var upper := quickbar_upper_page()
	var lower := quickbar_page
	quickbar_upper = lower
	if upper != lower:
		select_quickbar_page(upper)
	else:
		quickbar_changed.emit()


func set_quickbar(slots: Array) -> void:
	server_quickbar = true
	for i in QUICKBAR_SLOTS:
		quickbar[i] = str(slots[i]) if i < slots.size() and slots[i] is String else ""
	quickbar_changed.emit()


func _load_quickbar() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(save_path) != OK:
		return
	var saved = cfg.get_value("quickbar", "slots", [])
	if saved is Array:
		for i in mini(saved.size(), QUICKBAR_SLOTS):
			quickbar[i] = str(saved[i])


func _save_quickbar() -> void:
	if server_quickbar:
		return
	var cfg := ConfigFile.new()
	cfg.set_value("quickbar", "slots", quickbar)
	cfg.save(save_path)


# --- equipment grids -------------------------------------------------------------------------

## The grid of `kind` ("char" or "veh"), as `grids` has it.
func grid(kind: String) -> Dictionary:
	return grids.get(kind, {})


## The equipment covering a cell of a grid, or {}.
func equipment_at(kind: String, cell: Vector2i) -> Dictionary:
	for e in grid(kind).get("equipment", []):
		if cell.x >= e["x"] and cell.x < e["x"] + e["w"] and cell.y >= e["y"] and cell.y < e["y"] + e["h"]:
			return e
	return {}


func _grid_command(t: String, kind: String, fields: Dictionary) -> void:
	var cmd := {"t": t, "kind": kind}
	if kind == "veh":
		cmd["u"] = int(grid("veh").get("unit", 0))
	cmd.merge(fields)
	Bridge.send(cmd)


## One of the equipment in main inventory slot `slot` (1-based) into a grid with its top left at
## `cell`, or (cell (-1, -1)) wherever it first fits, like Shift+click.
func put_equipment(kind: String, slot: int, cell := Vector2i(-1, -1)) -> void:
	var f := {"fi": slot}
	if cell.x >= 0 and cell.y >= 0:
		f["x"] = cell.x
		f["y"] = cell.y
	_grid_command("eq_put", kind, f)


## The equipment covering `cell` back into the inventory (main slot `slot` when it is empty).
func take_equipment(kind: String, cell: Vector2i, slot := 0) -> void:
	var f := {"x": cell.x, "y": cell.y}
	if slot > 0:
		f["ti"] = slot
	_grid_command("eq_take", kind, f)


## The equipment covering `cell` moves so its top left is at `to`.
func move_equipment(kind: String, cell: Vector2i, to: Vector2i) -> void:
	_grid_command("eq_move", kind, {"x": cell.x, "y": cell.y, "tx": to.x, "ty": to.y})


## Factorio's Alt+F ("roboport") and Alt+E ("movement") switches, on the character.
func toggle_equipment(what: String, on: bool) -> void:
	Bridge.send({"t": "eq_toggle", "what": what, "on": 1 if on else 0})


## The death screen's Respawn button.
func respawn() -> void:
	Bridge.send({"t": "respawn"})


## A player by their character's unit, or {}.
func player_of_unit(unit: int) -> Dictionary:
	if unit == 0:
		return {}
	for p in players:
		if int(p["unit"]) == unit:
			return p
	return {}


# --- crafting queue --------------------------------------------------------------------------

## The queue's length from `me.q`.
func set_queue_size(n: int) -> void:
	if n != craft_queue_size:
		craft_queue_size = n
		queue_changed.emit()


## The queue's entries, [{"recipe", "count", "progress", "index"?}] (index: for cancel_craft).
func set_craft_queue(entries: Array) -> void:
	craft_queue = entries
	craft_queue_size = 0
	for e in entries:
		if e is Dictionary:
			craft_queue_size += int(e.get("count", 1))
	queue_changed.emit()


# --- Factorio's world controls (ui_actions.lua) -------------------------------------------------

## Alt-mode on or off: while on the mod sends the icons near the camera once a second.
func set_alt_mode(on: bool) -> void:
	Bridge.send({"t": "alt", "on": 1 if on else 0})
	if not on:
		alt_icons.clear()
		alt_icons_changed.emit()


## A line in the game's chat.
func say(text: String) -> void:
	if text.strip_edges() != "":
		Bridge.send({"t": "chat", "text": text})


## Statistics: kind "item", "fluid", "kill", "build", "pollution", or "electric" with a pole's
## identity in `target` ({u, p, x, y}); prec 1-8 is Factorio's time scale (5 s, 1 min, 10 min, 1 h,
## 10 h, 50 h, 250 h, 1000 h); `si` a surface index (0: all, -1: the character's); `graph` the names
## to draw lines for ([] the busiest, null none). The answer arrives as stats_received, with
## stats_si and stats_graph set.
func request_bonuses() -> void:
	Bridge.send({"t": "bonuses"})


func request_perms() -> void:
	Bridge.send({"t": "perms"})


func request_stats(kind: String, prec: int, target := {}, si := -1, graph = null) -> void:
	var cmd := {"t": "stats", "kind": kind, "prec": prec}
	cmd.merge(target)
	if si >= 0:
		cmd["si"] = si
	if graph is Array:
		cmd["g"] = graph
	Bridge.send(cmd)


# --- Factoriopedia and the logistic networks window ------------------------------------------------

## Asks for Factoriopedia's index (once, unless `again`); pedia_index_changed says it arrived.
func request_pedia_index(again := false) -> void:
	var now := Time.get_ticks_msec()
	if (not pedia_index.is_empty() and not again) or now - _pedia_index_asked < 3000:
		return
	_pedia_index_asked = now
	Bridge.send({"t": "pedia_index"})


## A Factoriopedia page ({"found", "d"}), or {} until it arrives (it is asked for then, once every
## few seconds at most); pedia_page_received says when.
func pedia_page(kind: String, name: String) -> Dictionary:
	var key := "%s/%s" % [kind, name]
	if pedia_pages.has(key):
		return pedia_pages[key]
	var now := Time.get_ticks_msec()
	if now - int(_pedia_asked.get(key, -100000)) > 3000:
		_pedia_asked[key] = now
		Bridge.send({"t": "pedia", "kind": kind, "name": name})
	return {}


## An item's or entity's page data ("d"), the entity's own part for an item that builds one; {}
## while it isn't known.
func pedia_data(kind: String, name: String) -> Dictionary:
	var page := pedia_page(kind, name)
	return page.get("d", {}) if page.get("found", false) else {}


## Pings the map at a position (tiles), as a gps link does in Factorio.
func ping(at: Vector2) -> void:
	pings.append([at, Time.get_ticks_msec()])
	while pings.size() > 8:
		pings.pop_front()
	pinged.emit()


## The pings still showing: [[position, 0..1 of their time gone], ...].
func live_pings() -> Array:
	var now := Time.get_ticks_msec()
	var out: Array = []
	for p in pings:
		var t := (now - int(p[1])) / 1000.0 / PING_SECONDS
		if t < 1.0:
			out.append([p[0], t])
	return out


func request_lnets() -> void:
	Bridge.send({"t": "lnets"})


func request_lnet(id: int) -> void:
	Bridge.send({"t": "lnet", "id": id})


# --- entity settings on the open screen (entity_ui.lua) ------------------------------------------

## An inserter's filters ([item or ""] by slot), mode ("whitelist" / "blacklist"), whether it uses
## them, and its stack size (0: the most it can). Leave out (null / -1) what doesn't change.
func set_inserter(unit: int, filters = null, mode := "", use := -1, stack := -1, spoil := "") -> void:
	var cmd := {"t": "set_inserter", "u": unit}
	if spoil != "":
		cmd["sp"] = spoil
	if filters is Array:
		cmd["f"] = filters
	if mode != "":
		cmd["m"] = mode
	if use >= 0:
		cmd["use"] = use
	if stack >= 0:
		cmd["st"] = stack
	Bridge.send(cmd)


## A splitter's input and output priority ("left", "none", "right"; "" unchanged) and filter (null
## unchanged, "" none).
func set_splitter(unit: int, input := "", output := "", filter = null) -> void:
	var cmd := {"t": "set_splitter", "u": unit}
	if input != "":
		cmd["i"] = input
	if output != "":
		cmd["o"] = output
	if filter is String:
		cmd["f"] = filter
	Bridge.send(cmd)


## A chest's limit bar: how many slots machines may use.
func set_bar(unit: int, n: int) -> void:
	Bridge.send({"t": "set_bar", "u": unit, "n": n})


func set_switch(unit: int, on: bool) -> void:
	Bridge.send({"t": "set_switch", "u": unit, "on": 1 if on else 0})


func set_panel_text(unit: int, text: String) -> void:
	Bridge.send({"t": "set_panel", "u": unit, "text": text})


## A display panel's settings: any of text, icon ({type, name} or {}), show, chart (0/1) and msgs
## ([{text, icon, cond}]).
func set_panel(unit: int, settings: Dictionary) -> void:
	var cmd := {"t": "set_panel", "u": unit}
	cmd.merge(settings)
	Bridge.send(cmd)


## A lamp's or train stop's colour, [r, g, b] in 0-255.
func set_color(unit: int, rgb: Array) -> void:
	Bridge.send({"t": "set_color", "u": unit, "c": rgb})


## A programmable speaker's settings: any of vol (0-1), mode, poly, vctl, vsig, inst, note, pitch,
## stop, al ({show, map, icon, msg}).
func set_speaker(unit: int, settings: Dictionary) -> void:
	var cmd := {"t": "set_speaker", "u": unit}
	cmd.merge(settings)
	Bridge.send(cmd)


## A pump's fluid filter ("" none).
func set_pump(unit: int, fluid: String) -> void:
	Bridge.send({"t": "set_pump", "u": unit, "f": fluid})


## A turret's priority targets (entity names; null unchanged) and whether it ignores the rest
## (0/1; -1 unchanged).
func set_targets(unit: int, targets = null, ignore := -1) -> void:
	var cmd := {"t": "set_targets", "u": unit}
	if targets is Array:
		cmd["l"] = targets
	if ignore >= 0:
		cmd["ign"] = ignore
	Bridge.send(cmd)


## The open entity's circuit or logistic connection settings ({field: value}, gui.cc's fields).
func set_circuit(unit: int, fields: Dictionary) -> void:
	Bridge.send({"t": "set_cc", "u": unit, "f": fields})


## A red ("r"), green ("g") or copper ("w") wire between two entities, or off again if it is there.
## Each end is {u, p, x, y, mx, my}: the entity and where it was clicked (a combinator's side).
func wire(kind: String, from: Dictionary, to: Dictionary) -> void:
	Bridge.send({"t": "wire", "k": kind, "a": from, "b": to})


## Removes every copper cable of a pole ({u, p, x, y}).
func wire_clear(pole: Dictionary) -> void:
	var cmd := {"t": "wire_clear"}
	cmd.merge(pole)
	Bridge.send(cmd)


# --- circuit network -------------------------------------------------------------------------

## A combinator's new settings, in the shape its screen's `cb` has (arithmetic, decider and
## selector: the game's parameters; constant: {enabled, signals: [[type, name, count], ...]}).
func set_combinator(unit: int, settings: Dictionary) -> void:
	Bridge.send({"t": "set_cb", "u": unit, "cb": settings})


# --- planets ---------------------------------------------------------------------------------

## From a platform stopped at a planet, down to its surface in a cargo pod (`land`).
## Asks for the solar system (`smap`), for the space map.
func request_space_map() -> void:
	Bridge.send({"t": "smap"})


## Factorio's "new platform" over a planet: waits there for one of the character's starter packs.
func new_platform(planet := "") -> void:
	var cmd := {"t": "plat_new"}
	if planet != "":
		cmd["planet"] = planet
	Bridge.send(cmd)


## "Can't build here: ..." for an entity prototype on this surface (Space Age's surface
## conditions), or "".
func cant_build_reason(proto_id: int) -> String:
	var r = not_buildable.get(proto_id)
	if not (r is Array):
		return ""
	var prop := str(r[0])
	var props = planet.get("props")
	var value := float(props.get(prop, 0.0)) if props is Dictionary else 0.0
	var units := {"pressure": " hPa", "gravity": " m/s²", "magnetic-field": " μT", "solar-power": "%"}
	var unit := str(units.get(prop, ""))
	var low := value < float(r[1])
	var bound := float(r[1]) if low else float(r[2])
	return "Can't build here: %s is %s%s, it needs %s %s%s" % [prop.replace("-", " "), str(snappedf(value, 0.1)), unit,
		"at least" if low else "at most", str(snappedf(bound, 0.1)), unit]


func land() -> void:
	Bridge.send({"t": "land"})


# --- logistics -------------------------------------------------------------------------------

## The character's logistic requests, in the shape `char_requests` has; also turns them on or off
## and sets auto-trash.
## The character's colour (and its player's), through the bridge.
func set_character_color(c: Color) -> void:
	Bridge.send({"t": "set_char_color", "c": [c.r8, c.g8, c.b8]})


func set_character_requests(requests: Array, on := true, trash_unrequested := false) -> void:
	Bridge.send({"t": "set_char_requests", "l": _request_list(requests), "on": 1 if on else 0,
		"trash": 1 if trash_unrequested else 0})


## A requester or buffer chest's requests (the open screen's `u`), as `gui.lg.requests` shows them.
func set_chest_requests(unit: int, requests: Array) -> void:
	Bridge.send({"t": "set_requests", "u": unit, "l": _request_list(requests)})


## What a storage chest takes ("" for anything).
func set_storage_filter(unit: int, item: String) -> void:
	Bridge.send({"t": "set_storage_filter", "u": unit, "item": item})


## [[item, min, max, quality?], ...] from the wire into dictionaries.
static func _requests(v) -> Array:
	var out: Array = []
	for r in _array(v):
		if r is Array and r.size() >= 3:
			out.append({"item": str(r[0]), "min": int(r[1]), "max": int(r[2]), "quality": str(r[3]) if r.size() >= 4 else "normal"})
	return out


static func _request_list(requests: Array) -> Array:
	var out: Array = []
	for r in requests:
		if r is Dictionary:
			var rec: Array = [str(r.get("item", "")), int(r.get("min", 0)), int(r.get("max", -1))]
			if str(r.get("quality", "normal")) != "normal":
				rec.append(str(r["quality"]))
			out.append(rec)
	return out


# --- trains ----------------------------------------------------------------------------------
# On the open screen's entity (a locomotive or wagon: its train; or a train stop), as `gui.tr`
# and `gui.stop` show them.

## The train's schedule records, in the shape `gui.tr.sched.records` has ({station or rail [x, y],
## wait_conditions [{type, compare_type, ticks...}], temporary...}).
func set_schedule(unit: int, records: Array) -> void:
	Bridge.send({"t": "set_schedule", "u": unit, "records": records})


## Sends the train to its schedule's record i (1-based).
func train_go(unit: int, i: int) -> void:
	Bridge.send({"t": "train_go", "u": unit, "i": i})


func set_train_automatic(unit: int, automatic: bool) -> void:
	Bridge.send({"t": "train_mode", "u": unit, "auto": 1 if automatic else 0})


## The open train stop's priority and circuit settings ({"pri"?, "cb"?: {key: value}}, see
## docs/PROTOCOL.md "Trains").
func set_stop_settings(unit: int, settings: Dictionary) -> void:
	var cmd := {"t": "set_stop", "u": unit}
	cmd.merge(settings)
	Bridge.send(cmd)


## The open train's schedule interrupts ([{name, conditions, targets, inside_interrupt}]).
func set_interrupts(unit: int, interrupts: Array) -> void:
	Bridge.send({"t": "set_interrupts", "u": unit, "interrupts": interrupts})


## Factorio's "go to": the open train goes to that stop now, as a temporary record.
func train_go_to_station(unit: int, station: String) -> void:
	Bridge.send({"t": "train_temp", "u": unit, "station": station})


## Asks for the trains overview (`trl`); with `show`, the overview window opens too.
func request_trains_overview(show := false) -> void:
	Bridge.send({"t": "trains_list"})
	if show:
		trains_overview_requested.emit()


## Automatic or manual for any train of the force, from the overview.
func set_train_automatic_by_id(id: int, automatic: bool) -> void:
	Bridge.send({"t": "train_mode_id", "id": id, "auto": 1 if automatic else 0})


## Renames a train stop ("" keeps the name) and sets its trains limit (-1 none, -2 unchanged).
func set_stop(unit: int, stop_name := "", limit := -2) -> void:
	var cmd := {"t": "set_stop", "u": unit}
	if stop_name != "":
		cmd["name"] = stop_name
	if limit >= -1:
		cmd["limit"] = limit
	Bridge.send(cmd)


# --- map -------------------------------------------------------------------------------------

## Asks for the map of chunks from..to (inclusive), at 2, 4, 8, 16 or 32 tiles per pixel. Charts
## arrive a few chunks per tick, nearest the centre first (map_changed); a new request replaces
## one still being sent. They are snapshots: ask again to refresh.
func request_map(from_chunk: Vector2i, to_chunk: Vector2i, tiles_per_pixel := 4) -> void:
	var cmd := {"t": "map", "cx1": from_chunk.x, "cy1": from_chunk.y, "cx2": to_chunk.x, "cy2": to_chunk.y,
		"res": tiles_per_pixel}
	if map_si > 0:
		cmd["si"] = map_si
	Bridge.send(cmd)


## The surface the map shows: `si` from map_surfaces, or 0 for the character's.
func set_map_surface(si: int) -> void:
	if si == character_si:
		si = 0
	if si == map_si:
		return
	map_si = si
	map_charts.clear()
	map_pollution.clear()
	map_overlays.clear()
	map_tags.clear()
	map_trains.clear()
	map_coverage.clear()
	map_coverage_known = false
	tags_changed.emit()
	map_surfaces_changed.emit()
	map_trains_changed.emit()


## The character is on surface `si` now (welcome, surface): the map shows it again.
func set_character_surface(si: int) -> void:
	character_si = si
	map_si = 0
	# Joined (perhaps another game) or moved: the roboports are listed again when next needed.
	_roboports.clear()
	_roboport_parts.clear()
	_roboports_asked.clear()
	roboports_version += 1
	map_surfaces_changed.emit()
	roboports_changed.emit()


## A map or the remote view shows surface `si`: asks for its roboports (`mrp`) at once the first
## time, then every ROBOPORTS_EVERY_MSEC (an answer lost on the way is asked for again then).
func ask_roboports(si: int) -> void:
	if si <= 0 or not Bridge.world_ready:
		return
	var now := Time.get_ticks_msec()
	if _roboports_asked.has(si) and now - int(_roboports_asked[si]) < ROBOPORTS_EVERY_MSEC:
		return
	_roboports_asked[si] = now
	_roboport_q += 1
	Bridge.send({"t": "mrp", "si": si, "q": _roboport_q})


## A part of `mrp`. Parts come in order; one missing drops the list until the next asking.
func _roboport_part(msg: Dictionary) -> void:
	var si := int(msg.get("si", 0))
	var part := int(msg.get("part", 1))
	var got: Array = _roboport_parts.get(si, [1, PackedInt32Array()])
	if part == 1:
		got = [1, PackedInt32Array()]
	if part != int(got[0]):
		_roboport_parts.erase(si)
		return
	var l: PackedInt32Array = got[1]
	for v in _array(msg.get("l")):
		l.append(int(v))
	if int(msg.get("last", 0)) != 1:
		_roboport_parts[si] = [part + 1, l]
		return
	_roboport_parts.erase(si)
	set_roboports(si, l)


## Surface `si`'s roboports, four integers each (`mrp`'s `l`). Works out the chunks they reveal.
func set_roboports(si: int, l: PackedInt32Array) -> void:
	var old: Dictionary = _roboports.get(si, {})
	if not old.is_empty() and old["l"] == l:
		return
	var at := {}
	var chunks := {}
	for i in range(0, l.size() - 3, 4):
		at[Vector2i(l[i], l[i + 1])] = true
		var x := l[i] / 256.0
		var y := l[i + 1] / 256.0
		var r := l[i + 3] / 256.0
		# Chunks whose centre (32 c + 16) lies within r of the roboport on both axes.
		for cx in range(ceili((x - r - 16.0) / 32.0), floori((x + r - 16.0) / 32.0) + 1):
			for cy in range(ceili((y - r - 16.0) / 32.0), floori((y + r - 16.0) / 32.0) + 1):
				chunks[Vector2i(cx, cy)] = true
	_roboports[si] = {"l": l, "at": at, "chunks": chunks}
	roboports_version += 1
	roboports_changed.emit()


## Surface `si`'s roboports as `mrp` lists them (empty until they arrive).
func roboports_of(si: int) -> PackedInt32Array:
	var r: Dictionary = _roboports.get(si, {})
	return r["l"] if not r.is_empty() else PackedInt32Array()


## Whether surface `si`'s list has a roboport at this position (1/256 tile).
func has_roboport_at(si: int, fixed_at: Vector2i) -> bool:
	return _roboports.has(si) and _roboports[si]["at"].has(fixed_at)


## Whether a roboport's construction area on surface `si` holds this chunk's centre (H13).
func roboport_covers(si: int, chunk: Vector2i) -> bool:
	# Asked for every chunk round the view several times a second: no dictionary made on the way.
	return _roboports.has(si) and _roboports[si]["chunks"].has(chunk)


## The map view switched to a planet: asks where its cargo landing pad is (landing_pad_found).
## Returns the ask's id.
func ask_landing_pad(si: int) -> int:
	_lpad_q += 1
	Bridge.send({"t": "lpad", "si": si, "q": _lpad_q})
	return _lpad_q


## A map is open: asks for the trains on its surface, at most once a second (Factorio draws them
## live on the map).
func ask_map_trains() -> void:
	var now := Time.get_ticks_msec()
	if now - _map_trains_asked < 1000 or not Bridge.world_ready:
		return
	_map_trains_asked = now
	var cmd := {"t": "mtr"}
	if map_si > 0:
		cmd["si"] = map_si
	Bridge.send(cmd)


## Whether radars, roboports' construction areas (H13) or the character (at `character_at` on the
## character's surface) see this chunk. Until the mod has said where its radars are, everything
## counts as seen.
func chunk_covered(chunk: Vector2i, character_at: Vector2) -> bool:
	if not map_coverage_known:
		return true
	if map_si == 0 and (Vector2(chunk) * 32.0 + Vector2(16, 16)).distance_to(character_at) <= COVERED_RADIUS + 16.0:
		return true
	if roboport_covers(shown_surface(), chunk):
		return true
	for r in map_coverage:
		if r.has_point(chunk):
			return true
	return false


## Whether the territories (`terr`) are on the surface the map shows: they are the world's surface's,
## which is the character's unless the remote view streams another.
func territories_shown() -> bool:
	if territory_si == 0:
		return map_si == 0
	return territory_si == shown_surface()


## The surface the map shows (its index; character_si when it is the character's).
func shown_surface() -> int:
	return map_si if map_si > 0 else character_si


## The map's entry for a surface, or {}.
func map_surface(si: int) -> Dictionary:
	for s in map_surfaces:
		if int(s["si"]) == si:
			return s
	return {}


## Charts and tags of a surface the map no longer shows are dropped.
func _shown_surface(msg: Dictionary) -> bool:
	return not msg.has("si") or shown_surface() == 0 or int(msg.get("si")) == shown_surface()


## A tag at a map position (tiles), with an optional icon (a signal: type "item", "fluid",
## "virtual"... and its name).
## The borders of territories given as flat chunk lists ([x1, y1, x2, y2, ...] each): every side of
## a territory's chunk whose neighbour isn't in the same territory, as a segment in tiles.
static func territory_borders(territories: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	var sides := [[Vector2i(0, -1), Vector2(0, 0), Vector2(1, 0)], [Vector2i(1, 0), Vector2(1, 0), Vector2(1, 1)],
		[Vector2i(0, 1), Vector2(0, 1), Vector2(1, 1)], [Vector2i(-1, 0), Vector2(0, 0), Vector2(0, 1)]]
	for t in territories:
		var flat := _array(t)
		var mine := {}
		for i in range(0, flat.size() - 1, 2):
			mine[Vector2i(int(flat[i]), int(flat[i + 1]))] = true
		for c: Vector2i in mine:
			for side in sides:
				if not mine.has(c + (side[0] as Vector2i)):
					out.append((Vector2(c) + (side[1] as Vector2)) * 32.0)
					out.append((Vector2(c) + (side[2] as Vector2)) * 32.0)
	return out


## Asks the mod about the machine or beacon under the mouse: at once when it is a new one,
## then about once a second while it stays, as beacons and modules come and go.
func ask_hover_info(unit: int, proto_id: int, fixed: Vector2i) -> void:
	var now := Time.get_ticks_msec()
	if unit == _hinfo_unit and now - _hinfo_msec < 1000:
		return
	if unit != _hinfo_unit:
		hover_info = {}
	_hinfo_unit = unit
	_hinfo_msec = now
	_hinfo_q += 1
	Bridge.send({"t": "hinfo", "q": _hinfo_q, "u": unit, "p": proto_id, "x": fixed.x, "y": fixed.y})


## A console command for the bridge to run for its character ("/cheat all"); command_answered
## carries the answer. Returns the request's id.
func command(text: String) -> int:
	_command_id += 1
	Bridge.send({"t": "cmd", "id": _command_id, "text": text})
	return _command_id


## Right-click on the map: asks the mod to remove the ghost under `position` (tiles) on the map's
## surface; unghost_answered says whether there was one. Returns the request's id.
func unghost(position: Vector2) -> int:
	_unghost_q += 1
	var cmd := {"t": "unghost", "q": _unghost_q, "x": roundi(position.x * 256), "y": roundi(position.y * 256)}
	if map_si > 0:
		cmd["si"] = map_si
	Bridge.send(cmd)
	return _unghost_q


func add_map_tag(position: Vector2, text: String, icon_type := "", icon_name := "") -> void:
	var cmd := {"t": "tag_add", "x": roundi(position.x * 256), "y": roundi(position.y * 256), "text": text}
	if map_si > 0:
		cmd["si"] = map_si
	if icon_name != "":
		cmd["icon"] = [icon_type if icon_type != "" else "item", icon_name]
	Bridge.send(cmd)


func remove_map_tag(id: int) -> void:
	var cmd := {"t": "tag_del", "id": id}
	if map_si > 0:
		cmd["si"] = map_si
	Bridge.send(cmd)


# --- research --------------------------------------------------------------------------------

func start_research(technology: String) -> void:
	Bridge.send({"t": "research", "name": technology})


func cancel_research(technology: String) -> void:
	Bridge.send({"t": "research_cancel", "name": technology})


## A multi-part list (rdet, techs) once its last part is in, else null.
func _gather(msg: Dictionary) -> Variant:
	var t := str(msg.get("t", ""))
	var part := int(msg.get("part", 1))
	if part == 1:
		_parts[t] = []
	if not _parts.has(t):
		return null
	(_parts[t] as Array).append_array(_array(msg.get("l")))
	if part < int(msg.get("parts", 1)):
		return null
	var list: Array = _parts[t]
	_parts.erase(t)
	return list


## A chart's n x n picture from its palette and pixels (palette indices), black where an index
## has no colour. Filled as bytes: a pixel at a time with set_pixel, the map's pages cost 1-2 ms a
## chunk to read while walking on a big base.
static func chart_image(n: int, pal: Array, px: Array) -> Image:
	var colours := PackedByteArray()
	colours.resize(pal.size() * 3)
	var known := PackedByteArray()
	known.resize(pal.size())
	for k in pal.size():
		var c: Array = _array(pal[k])
		if c.size() >= 3:
			colours[k * 3] = int(c[0])
			colours[k * 3 + 1] = int(c[1])
			colours[k * 3 + 2] = int(c[2])
			known[k] = 1
	var data := PackedByteArray()
	data.resize(n * n * 3)
	for i in px.size():
		var k := int(px[i])
		if k >= 0 and k < known.size() and known[k] == 1:
			data[i * 3] = colours[k * 3]
			data[i * 3 + 1] = colours[k * 3 + 1]
			data[i * 3 + 2] = colours[k * 3 + 2]
	return Image.create_from_data(n, n, false, Image.FORMAT_RGB8, data)


static func _array(v) -> Array:
	return v if v is Array else []
