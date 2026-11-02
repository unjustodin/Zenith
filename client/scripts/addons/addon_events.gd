extends Node
## api.events: things worth watching, worked out by the client from what the bridge already sends
## (nothing extra is asked of the game), as signals, and the last few as a list (recent()).
## Like everything the client knows they are seen only near the focus (trains, fights) or
## anywhere on the surface shown (rocket launches) or in the game (platforms, players).
##
## Positions are Godot's (x east, z south, tiles; y 0 on the ground).

## A train with a carriage near the focus left the stop it was at, or arrived at one.
signal train_departed(train_id: int, stop_unit: int, position: Vector3)
signal train_arrived(train_id: int, stop_unit: int, position: Vector3)
## A rocket launch was ordered at a silo on the surface shown (it lifts off a few seconds later).
signal rocket_launched(silo_unit: int, position: Vector3)
## Enemies started attacking, or turrets started firing, where nothing had for FIGHT_QUIET seconds;
## and a fight that stayed quiet that long ended. `size`: attackers and turrets seen in it so far.
signal fight_started(position: Vector3, size: int)
signal fight_ended(position: Vector3)
## A space platform left a planet, or arrived at one (`location`: the planet).
signal platform_departed(platform: int, location: String)
signal platform_arrived(platform: int, location: String)
## A player connected or left.
signal player_joined(player_name: String)
signal player_left(player_name: String)

## Seconds without shots or attacks that end a fight; tiles within which attacks are one fight.
const FIGHT_QUIET := 10.0
const FIGHT_REACH := 48.0
const KEEP := 40

var _main = null
## Ongoing fights: [{position (Vector2), since, last (seconds), units {unit: true}}].
var _fights: Array = []
## Train id -> the stop it was at (0 none), from the last `tr`.
var _train_stops := {}
var _connected := {}  # player name -> true
var _recent: Array = []  # newest first: {kind, time, position, ...}


## Starts watching a game (main.gd's nodes; addon_host.gd calls it).
func attach(main_node) -> void:
	detach()
	_main = main_node
	if not Bridge.message_received.is_connected(_on_message):
		Bridge.message_received.connect(_on_message)
	var model = _model()
	if model != null:
		model.trains_changed.connect(_on_trains)
		model.rocket_launched.connect(_on_rocket)
		model.platform_state_changed.connect(_on_platform)
		model.players_changed.connect(_on_players)


func detach() -> void:
	if Bridge.message_received.is_connected(_on_message):
		Bridge.message_received.disconnect(_on_message)
	var model = _model()
	if model != null:
		for pair in [[model.trains_changed, _on_trains], [model.rocket_launched, _on_rocket],
				[model.platform_state_changed, _on_platform], [model.players_changed, _on_players]]:
			if (pair[0] as Signal).is_connected(pair[1]):
				(pair[0] as Signal).disconnect(pair[1])
	_main = null
	_fights.clear()
	_train_stops.clear()
	_connected.clear()
	_recent.clear()


## The last events, newest first, at most `seconds` old: [{kind ("train_departed",
## "train_arrived", "rocket_launched", "fight_started", "fight_ended", "platform_departed",
## "platform_arrived", "player_joined", "player_left"), time (seconds since Zenith started),
## age (seconds), position (Vector3, or null), and the signal's other values by name}].
func recent(seconds := 60.0) -> Array:
	var now := _now()
	var out: Array = []
	for e: Dictionary in _recent:
		if now - float(e["time"]) > seconds:
			break
		var copy := e.duplicate()
		copy["age"] = now - float(e["time"])
		out.append(copy)
	return out


## Fights going on now: [{position (Vector3), since (seconds ago it started), size}].
func fights() -> Array:
	var now := _now()
	var out: Array = []
	for f: Dictionary in _fights:
		var p: Vector2 = f["position"]
		out.append({"position": Vector3(p.x, 0.0, p.y), "since": now - float(f["since"]), "size": (f["units"] as Dictionary).size()})
	return out


func _process(_delta: float) -> void:
	var now := _now()
	for i in range(_fights.size() - 1, -1, -1):
		var f: Dictionary = _fights[i]
		if now - float(f["last"]) > FIGHT_QUIET:
			_fights.remove_at(i)
			var p: Vector2 = f["position"]
			_emit("fight_ended", Vector3(p.x, 0.0, p.y), {})


func _on_message(msg: Dictionary) -> void:
	match str(msg.get("t", "")):
		"en":
			var l = msg.get("l")
			if l is Array:
				var i := 0
				while i + 2 < l.size():
					_fight_at(Vector2(int(l[i + 1]), int(l[i + 2])) / 256.0, int(l[i]))
					i += 3
		"tf":
			_fight_at(Vector2(int(msg.get("x", 0)), int(msg.get("y", 0))) / 256.0, int(msg.get("u", 0)))


## An attack on (or a shot at) a point: part of a fight there, or a new one.
func _fight_at(at: Vector2, unit: int) -> void:
	var now := _now()
	for f: Dictionary in _fights:
		var p: Vector2 = f["position"]
		if p.distance_to(at) <= FIGHT_REACH:
			f["position"] = p.lerp(at, 0.1)
			f["last"] = now
			(f["units"] as Dictionary)[unit] = true
			return
	_fights.append({"position": at, "since": now, "last": now, "units": {unit: true}})
	_emit("fight_started", Vector3(at.x, 0.0, at.y), {"size": 1})


func _on_trains() -> void:
	var model = _model()
	if model == null:
		return
	var seen := {}
	for id in model.trains:
		var t: Dictionary = model.trains[id]
		var stop := int(t["station"])
		seen[id] = stop
		if not _train_stops.has(id):
			continue
		var was := int(_train_stops[id])
		var units: Array = t["carriages"]
		var at := _position_of(int(units[0]) if not units.is_empty() else 0)
		if was != 0 and stop == 0:
			_emit("train_departed", at, {"train_id": int(id), "stop_unit": was})
		elif was == 0 and stop != 0:
			_emit("train_arrived", at, {"train_id": int(id), "stop_unit": stop})
	_train_stops = seen


func _on_rocket(silo: int, at: Vector2, surface: String) -> void:
	var rockets = _main.get("rockets") if _main != null else null
	var shown := str(rockets.surface) if rockets != null else ""
	if shown != "" and surface != "" and surface != shown:
		return
	_emit("rocket_launched", Vector3(at.x, 0.0, at.y), {"silo_unit": silo})


func _on_platform(platform: int, state: String, old_state: String, location: String) -> void:
	if state == "on_the_path" and old_state == "waiting_at_station":
		_emit("platform_departed", null, {"platform": platform, "location": location})
	elif state == "waiting_at_station" and old_state == "on_the_path":
		_emit("platform_arrived", null, {"platform": platform, "location": location})


func _on_players() -> void:
	var model = _model()
	if model == null:
		return
	var now := {}
	for p: Dictionary in model.players:
		if bool(p["connected"]):
			now[str(p["name"])] = true
	var first := _connected.is_empty() and not now.is_empty() and _recent.is_empty()
	if not first:
		for n in now:
			if not _connected.has(n):
				_emit("player_joined", null, {"player_name": n})
		for n in _connected:
			if not now.has(n):
				_emit("player_left", null, {"player_name": n})
	_connected = now


func _emit(kind: String, at, extra: Dictionary) -> void:
	var e := {"kind": kind, "time": _now(), "position": at}
	e.merge(extra)
	_recent.push_front(e)
	if _recent.size() > KEEP:
		_recent.resize(KEEP)
	match kind:
		"train_departed": train_departed.emit(int(extra["train_id"]), int(extra["stop_unit"]), at)
		"train_arrived": train_arrived.emit(int(extra["train_id"]), int(extra["stop_unit"]), at)
		"rocket_launched": rocket_launched.emit(int(extra["silo_unit"]), at)
		"fight_started": fight_started.emit(at, int(extra["size"]))
		"fight_ended": fight_ended.emit(at)
		"platform_departed": platform_departed.emit(int(extra["platform"]), str(extra["location"]))
		"platform_arrived": platform_arrived.emit(int(extra["platform"]), str(extra["location"]))
		"player_joined": player_joined.emit(str(extra["player_name"]))
		"player_left": player_left.emit(str(extra["player_name"]))


func _position_of(unit: int) -> Vector3:
	var layer = _main.get("movers") if _main != null else null
	if layer == null or unit == 0:
		return Vector3.ZERO
	var p = layer.position_of(unit)
	return p if p is Vector3 else Vector3.ZERO


func _model():
	if _main == null:
		return null
	var hud = _main.get("hud")
	return hud.ui.model if hud != null and hud.get("ui") != null else null


static func _now() -> float:
	return Time.get_ticks_msec() / 1000.0
