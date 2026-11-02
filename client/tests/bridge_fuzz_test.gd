extends Node
## Throws malformed packets at the client's side of the protocol (scripts/net/bridge.gd's
## receive and _handle): random bytes, truncated JSON, deep nesting, fields of the wrong type,
## sequence numbers that are strings, negative, huge or out of order, duplicates. Afterwards a new
## welcome must still connect and messages must still arrive. Exits 1 if a check fails; CI also
## fails on any SCRIPT ERROR in the output (a GDScript runtime error only stops that one call).
##
##   godot --headless --path client res://tests/bridge_fuzz_test.tscn

const BridgeScript := preload("res://scripts/net/bridge.gd")
const TYPES := ["welcome", "ready", "chunk", "ents", "add", "upd", "del", "sky", "me", "mv", "msg", "gui", "bi", "planet", "seg"]
const ROUNDS := 5000

var fails := 0
var rng := RandomNumberGenerator.new()


func check(cond: bool, what: String) -> void:
	if not cond:
		fails += 1
		print("FAIL: ", what)


func _ready() -> void:
	rng.seed = 1
	var b: Node = BridgeScript.new()
	add_child(b)
	var seen := [0]
	var count := func(_m: Dictionary) -> void:
		seen[0] += 1
	b.message_received.connect(count)

	b.receive(_bytes({"t": "welcome", "r": 1, "v": 1, "k": 5}))
	check(b.connected, "a welcome connects")
	for i in ROUNDS:
		match rng.randi() % 5:
			0:
				b.receive(_random_bytes())
			1:
				var good := JSON.stringify(_junk_msg()).to_utf8_buffer()
				b.receive(good.slice(0, rng.randi_range(0, good.size())))
			2:
				b.receive(("[" if rng.randi() % 2 else "{\"a\":").repeat(rng.randi_range(1, 2000)).to_utf8_buffer())
			_:
				var m := _junk_msg()
				for k in rng.randi_range(1, 3):  # duplicated
					b.receive(_bytes(m))
	check(b.server_tick is int, "server_tick stays an int")

	b.receive(_bytes({"t": "welcome", "r": 1, "v": 1}))
	b.receive(_bytes({"t": "ready", "r": 2}))
	check(b.connected and b.world_ready, "a new welcome and ready still work after the fuzzing")
	var before: int = seen[0]
	b.receive(_bytes({"t": "sky", "d": 1, "n": 0, "k": 9}))
	b.receive(_bytes({"t": "add", "r": 3, "e": [1, 2, 0, 0, 0]}))
	check(seen[0] == before + 2 and b.server_tick == 9, "messages still arrive in order")
	print("bridge fuzz: %d rounds, FAILS: %d" % [ROUNDS, fails])
	get_tree().quit(1 if fails else 0)


func _bytes(m: Dictionary) -> PackedByteArray:
	return JSON.stringify(m).to_utf8_buffer()


func _random_bytes() -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(rng.randi_range(0, 300))
	for i in out.size():
		out[i] = rng.randi() % 256
	return out


func _junk(depth := 0) -> Variant:
	match rng.randi() % (12 if depth < 3 else 9):
		0: return null
		1: return true
		2: return rng.randi_range(-1000, 1000)
		3: return 1.0e300
		4: return -1.0e300
		5: return 0.5
		6: return "x".repeat(rng.randi_range(0, 3000))
		7: return TYPES[rng.randi() % TYPES.size()]
		8: return 2147483647 * 4
		9: return [_junk(depth + 1), _junk(depth + 1)]
		10: return {"t": _junk(depth + 1), "r": _junk(depth + 1)}
		_: return [[_junk(depth + 1)]]


func _junk_msg() -> Dictionary:
	var m := {}
	m["t"] = TYPES[rng.randi() % TYPES.size()] if rng.randi() % 4 else _junk()
	for key in ["r", "k", "v", "part", "parts", "l", "e", "x", "y"]:
		if rng.randi() % 2:
			m[key] = _junk()
	if rng.randi() % 3 == 0:
		m["r"] = rng.randi_range(-5, 50)
	return m
