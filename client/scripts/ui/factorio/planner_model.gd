extends RefCounted
## Blueprints and planners on the wire (docs/PROTOCOL.md, "Blueprints and planners"): exchange
## strings to and from the game's stacks (`bp_get` / `bp` in parts, `bp_set` in parts / `bp_ok`),
## the game's and a taken-over player's blueprint libraries (`bp_lib` / `bpl`, `bp_rec`), book
## pages (`bp_page`), undo entries the mod keeps (`hist`, `undo`, `redo`) and the qualities
## (`quals`). ui_model.gd hands it these messages; the library, editors and player_input.gd use
## its calls.
##
## Stacks are named by main inventory slot (1-based), or -1 for the stack taken from the library
## into the cursor (the mod keeps it in a script inventory, as a library record in Factorio's
## cursor isn't in the inventory).

const BpString := preload("res://scripts/ui/factorio/bp_string.gd")

## A string goes to the mod in parts of this many characters (a datagram holds 64 KB).
const PART := 8000
## A request without its answer after this long is asked again, once.
const RETRY := 5.0

signal library_listed(src: String)
## The mod remembered an undoable action: its id and what it was.
signal history_added(h: int, what: String)
signal qualities_changed
## A string went into a stack: the slot it is in now (-1 the cursor's) and its item; `fresh` when
## the mod made it (a blueprint from Alt+B's area), so its window opens as Factorio's does.
signal stack_written(q: int, slot: int, item: String, fresh: bool)

## [[name, level, unlocked], ...] in Factorio's order.
var qualities: Array = []
## The game's library tab and the taken-over player's: [[index, item, label, icons], ...].
var game_library: Array = []
var player_library: Array = []
var player_name := ""
## Factorio's version number from the latest string seen (new records are stamped with it).
var version := 0

var _next_q := 0
var _callbacks := {}  # q -> Callable(record: Dictionary, text: String, info: Dictionary)
var _parts := {}  # q -> {part -> text}
var _asked := {}  # q -> [time, command] for the retry
var _next_upload := 0


func handle(msg: Dictionary) -> bool:
	match str(msg.get("t", "")):
		"bp":
			_on_part(msg)
		"bp_ok":
			var q := int(msg.get("q", 0))
			_asked.erase(q)
			var cb: Callable = _callbacks.get(q, Callable())
			_callbacks.erase(q)
			if cb.is_valid():
				cb.call({}, "", {"i": int(msg.get("i", 0)), "item": str(msg.get("item", ""))})
			stack_written.emit(q, int(msg.get("i", 0)), str(msg.get("item", "")), int(msg.get("new", 0)) == 1)
		"bpl":
			var list: Array = []
			for r in _array(msg.get("l")):
				if r is Array and r.size() >= 4:
					list.append([int(r[0]), str(r[1]), str(r[2]), _array(r[3])])
			if str(msg.get("src", "")) == "player":
				player_library = list
				player_name = str(msg.get("who", ""))
			else:
				game_library = list
			library_listed.emit(str(msg.get("src", "")))
		"hist":
			history_added.emit(int(msg.get("h", 0)), str(msg.get("what", "")))
		"quals":
			qualities = []
			for r in _array(msg.get("l")):
				if r is Array and r.size() >= 3:
					qualities.append([str(r[0]), int(r[1]), int(r[2]) == 1])
			qualities_changed.emit()
		_:
			return false
	return true


func _on_part(msg: Dictionary) -> void:
	var q := int(msg.get("q", 0))
	var got: Dictionary = _parts.get(q, {})
	got[int(msg.get("part", 1))] = str(msg.get("s", ""))
	_parts[q] = got
	if got.size() < int(msg.get("parts", 1)):
		return
	_parts.erase(q)
	_asked.erase(q)
	var keys := got.keys()
	keys.sort()
	var text := ""
	for k in keys:
		text += str(got[k])
	var record := BpString.decode(text) if text != "" else {}
	if not record.is_empty() and BpString.version_of(record) != 0:
		version = BpString.version_of(record)
	var cb: Callable = _callbacks.get(q, Callable())
	_callbacks.erase(q)
	if cb.is_valid():
		cb.call(record, text, {"i": int(msg.get("i", 0)), "item": str(msg.get("item", "")), "err": str(msg.get("err", ""))})


## Requests asked again when their answer didn't come (a reliable message lost in a resync).
func poll() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	for q in _asked.keys():
		var a: Array = _asked[q]
		if now - float(a[0]) > RETRY:
			_asked.erase(q)
			if int(a[2]) == 0:
				Bridge.send(a[1])
				_asked[q] = [now, a[1], 1]


func _ask(cmd: Dictionary, callback: Callable) -> int:
	_next_q += 1
	cmd["q"] = _next_q
	if callback.is_valid():
		_callbacks[_next_q] = callback
	_asked[_next_q] = [Time.get_ticks_msec() / 1000.0, cmd, 0]
	Bridge.send(cmd)
	return _next_q


## The stack at `slot` as a decoded record: callback(record, text, info). An empty record when
## there is nothing to export there (info["err"] says why).
func export_stack(slot: int, callback: Callable) -> int:
	return _ask({"t": "bp_get", "i": slot}, callback)


## A record of the game's ("game") or the taken-over player's ("player") library, decoded.
func export_record(src: String, index: int, callback: Callable) -> int:
	return _ask({"t": "bp_rec", "src": src, "ix": index}, callback)


## Takes a record of the game's library straight into the cursor's stack (no round trip of the
## string); callback(record {}, "", {"i": -1, "item"}) when it is there.
func take_record(src: String, index: int, callback: Callable) -> int:
	return _ask({"t": "bp_rec", "src": src, "ix": index, "to": -1}, callback)


## Writes a record (or an exchange string) into slot `slot`: 0 a new stack in the inventory, -1
## the cursor's stack. callback({}, "", {"i": slot it went to, "item"}) when done.
func write(slot: int, record: Variant, callback := Callable()) -> int:
	var text: String = record if record is String else BpString.encode(record)
	_next_q += 1
	var q := _next_q
	if callback.is_valid():
		_callbacks[q] = callback
	if text.length() <= PART:
		Bridge.send({"t": "bp_set", "q": q, "i": slot, "s": text})
		return q
	_next_upload += 1
	var n := ceili(text.length() / float(PART))
	for k in n:
		Bridge.send({"t": "bp_set", "q": q, "i": slot, "id": _next_upload, "part": k + 1, "parts": n,
			"d": text.substr(k * PART, PART)})
	return q


## A book's active page (1-based, as LuaItemStack.active_index).
## Destroys the blueprint, book or planner at a main slot (or -1, the library one): `bp_del`.
func delete(slot: int) -> void:
	Bridge.send({"t": "bp_del", "i": slot})


func set_page(slot: int, page: int) -> void:
	Bridge.send({"t": "bp_page", "i": slot, "a": page})


func request_libraries() -> void:
	Bridge.send({"t": "bp_lib"})


func undo(h: int) -> void:
	Bridge.send({"t": "undo", "h": h})


func redo(h: int) -> void:
	Bridge.send({"t": "redo", "h": h})


## The qualities the force has, in order: [name, ...] (at least "normal").
func unlocked_qualities() -> Array:
	var out: Array = []
	for q in qualities:
		if q[2]:
			out.append(q[0])
	if out.is_empty():
		out.append("normal")
	return out


## A new empty record of a kind, stamped with the game's version when one is known.
func empty(kind: String) -> Dictionary:
	return BpString.empty(kind, version)


static func _array(v) -> Array:
	return v if v is Array else []
