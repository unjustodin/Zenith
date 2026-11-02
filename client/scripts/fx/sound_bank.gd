extends RefCounted
## Factorio's own sounds and the rules it plays them by, read at runtime from the player's install
## (never copied into this repo). Paths are relative to Factorio's `data` folder:
## "base/sound/boiler.ogg".
##
## Factorio's sound engine is part of the game, but how each sound is to be played is data in its
## prototypes (`<data>/<mod>/prototypes/**/*.lua`), found here with a light text scan (no Lua is
## run): every sound definition's variations and their volumes, pitch range, how far it carries
## (`audible_distance_modifier`), its distance curve (`advanced_volume_control.attenuation`),
## `priority` and `aggregation` (how many may start at once); each machine's `working_sound` (the
## sound, its `idle_sound`, `activate_sound` and `deactivate_sound`, `max_sounds_per_prototype`,
## `fade_in_ticks` and `fade_out_ticks`); each planet's `persistent_ambient_sounds` (base ambience,
## wind and the occasional distant sound); and the music tracks and the planets they play on.
## A few common machines have a built-in fallback in case the scan misses them. Without an install
## every lookup comes back empty and the client is silent.
##
## The scan runs once, in the background (prepare(), started by sfx.gd); until it is done lookups
## answer with what they can (files are still found, rules are defaults).

const ItemIcons := preload("res://scripts/world/item_icons.gd")

const PROTOTYPE_MODS := ["core", "base", "space-age", "quality", "elevated-rails"]

## File names and volumes as in Factorio's prototypes, used when the scan finds nothing.
const FALLBACK_WORKING := {
	"assembling-machine-1": ["base/sound/assembling-machine-t1-1.ogg", 0.7, 1.0],
	"assembling-machine-2": ["base/sound/assembling-machine-t2-1.ogg", 0.45, 1.0],
	"assembling-machine-3": ["base/sound/assembling-machine-t3-1.ogg", 0.45, 1.0],
	"stone-furnace": ["base/sound/furnace.ogg", 0.6, 0.4],
	"steel-furnace": ["base/sound/steel-furnace.ogg", 0.6, 0.4],
	"electric-furnace": ["base/sound/electric-furnace.ogg", 0.6, 0.5],
	"boiler": ["base/sound/boiler.ogg", 0.7, 0.3],
	"steam-engine": ["base/sound/steam-engine-90bpm.ogg", 0.55, 0.8],
	"lab": ["base/sound/lab.ogg", 0.7, 0.7],
	"electric-mining-drill": ["base/sound/electric-mining-drill.ogg", 1.0, 1.0],
	"burner-mining-drill": ["base/sound/burner-mining-drill-1.ogg", 0.6, 1.0],
	"pumpjack": ["base/sound/pumpjack.ogg", 0.7, 0.6],
	"offshore-pump": ["base/sound/offshore-pump.ogg", 0.5, 0.7],
	"pump": ["base/sound/pump.ogg", 0.3, 0.5],
	"radar": ["base/sound/radar.ogg", 0.8, 1.0],
}


## A sound as Factorio defines it (prototype type `Sound`): its variations and how to play them.
class SoundDef:
	var files := PackedStringArray()
	var min_volumes := PackedFloat32Array()
	var max_volumes := PackedFloat32Array()
	var min_speed := 1.0
	var max_speed := 1.0
	## audible_distance_modifier: how far it carries, as a multiple of the audible distance.
	var reach := 1.0
	## advanced_volume_control.attenuation.curve_type ("" when not given).
	var attenuation := ""
	## 0 is the highest priority, 255 the lowest.
	var priority := 127
	## aggregation: 0 when the definition has none.
	var max_count := 0
	var remove := false
	var count_already_playing := false
	var progress_threshold := 1.0
	var volume_reduction_rate := 2.0
	var allow_random_repeat := false
	## Identifies the definition, for aggregation (its first file).
	var key := ""
	var _last := -1

	## A variation to play: its index; avoids repeating the last one unless allowed.
	func pick() -> int:
		if files.size() <= 1:
			return 0
		var i := randi() % files.size()
		if i == _last and not allow_random_repeat:
			i = (i + 1 + randi() % (files.size() - 1)) % files.size()
		_last = i
		return i

	func volume_of(i: int) -> float:
		return randf_range(min_volumes[i], max_volumes[i])

	func speed() -> float:
		return randf_range(min_speed, max_speed)

	static func single(path: String, volume: float) -> SoundDef:
		var d := SoundDef.new()
		d.files = PackedStringArray([path])
		d.min_volumes = PackedFloat32Array([volume])
		d.max_volumes = PackedFloat32Array([volume])
		d.key = path
		return d


## A machine's working_sound.
class Loop:
	var sound: SoundDef
	var idle: SoundDef = null
	var activate: SoundDef = null
	var deactivate: SoundDef = null
	## max_sounds_per_prototype; 0 when not given.
	var max_per_prototype := 0
	## Seconds (Factorio's fade_in_ticks 8 and fade_out_ticks 20 by default).
	var fade_in := 8.0 / 60.0
	var fade_out := 20.0 / 60.0
	var persistent := false
	## Kept for older callers: the main sound's files, its volume and reach.
	var files: PackedStringArray:
		get:
			return sound.files
	var volume: float:
		get:
			return sound.max_volumes[0] if sound.max_volumes.size() > 0 else 0.5
	var reach: float:
		get:
			return sound.reach


## A Lua file's text with its braces matched, to find the table round any point.
class LuaText:
	var path := ""  # relative to the data folder: "base/prototypes/entity/sounds.lua"
	var text := ""
	var pos := PackedInt32Array()  # every brace, in order
	var match_of := PackedInt32Array()  # brace index -> its partner's index
	var parent_of := PackedInt32Array()  # brace index of an opening brace -> the enclosing opening brace (-1)

	func _init(t: String, file: String) -> void:
		text = t
		path = file
		var found := RegEx.create_from_string("[{}]").search_all(t)
		pos.resize(found.size())
		match_of.resize(found.size())
		parent_of.resize(found.size())
		var stack := PackedInt32Array()
		for i in found.size():
			var p := found[i].get_start()
			pos[i] = p
			match_of[i] = -1
			parent_of[i] = -1
			if t.unicode_at(p) == 123:  # {
				parent_of[i] = stack[stack.size() - 1] if stack.size() > 0 else -1
				stack.append(i)
			elif stack.size() > 0:
				var o := stack[stack.size() - 1]
				stack.resize(stack.size() - 1)
				match_of[o] = i
				match_of[i] = o

	## The opening brace (index) of the innermost table round text position `p`, or -1.
	func enclosing(p: int) -> int:
		var i := pos.bsearch(p) - 1
		if i < 0:
			return -1
		if text.unicode_at(pos[i]) == 123:
			return i
		var o := match_of[i]
		return parent_of[o] if o >= 0 else -1

	func open_at(p: int) -> int:
		var i := pos.bsearch(p)
		return i if i < pos.size() and pos[i] == p else -1

	func body(open: int) -> String:
		var close := match_of[open]
		if close < 0:
			return ""
		return text.substr(pos[open] + 1, pos[close] - pos[open] - 1)

	## The key a table or value at text position `p` is assigned to ("sound" in `sound = {`), or "".
	func key_before(p: int) -> String:
		var from := maxi(0, p - 60)
		var m := _KEY.search(text.substr(from, p - from))
		return m.get_string(1) if m != null else ""

	## The table's own text with its nested tables blanked out, for its own keys only.
	func top_level(open: int) -> String:
		var close := match_of[open]
		if close < 0:
			return ""
		var out := ""
		var at := pos[open] + 1
		var depth := 0
		for i in range(open + 1, close):
			var is_open := text.unicode_at(pos[i]) == 123
			if depth == 0 and is_open:
				out += text.substr(at, pos[i] - at) + "{}"
			if is_open:
				depth += 1
			else:
				depth -= 1
				if depth == 0:
					at = pos[i] + 1
		if depth == 0:
			out += text.substr(at, pos[close] - at)
		return out

	## The opening braces of the table's direct children, with the keys they are assigned to.
	func children(open: int) -> Array:
		var out: Array = []
		var close := match_of[open]
		var i := open + 1
		while i < close and i >= 0:
			if text.unicode_at(pos[i]) == 123:
				out.append([i, key_before(pos[i])])
				i = match_of[i] + 1 if match_of[i] > i else close
			else:
				i += 1
		return out

	static var _KEY := RegEx.create_from_string("([A-Za-z_][A-Za-z_0-9]*)\\s*=\\s*$")


static var _streams := {}  # "path|loop" -> AudioStream, or null when the file isn't there
static var _decoding := {}  # "path|loop" -> true while a worker decodes it
static var _stream_lock := Mutex.new()
static var _variants := {}  # prefix -> PackedStringArray
static var _working := {}  # entity name -> Loop or null
static var _by_file := {}  # path -> SoundDef: the definition each file was found in
static var _entity_ws := {}  # entity name -> [LuaText, text position of "working_sound"]
static var _sound_refs := {}  # name of sounds.name -> [[LuaText, text position after its "="], ...]
static var _ambience := {}  # planet -> Dictionary (planet_ambience)
static var _tracks: Array = []  # [path, volume, planets (Array, empty: space), track type, weight]
static var _ready := false
static var _lock := Mutex.new()
static var _started := false
static var scan_msec := 0


static func data_dir() -> String:
	return ItemIcons.factorio_data_dir()


static func available() -> bool:
	return data_dir() != "" and DirAccess.dir_exists_absolute(data_dir().path_join("base/sound"))


static func exists(path: String) -> bool:
	var dir := data_dir()
	return dir != "" and FileAccess.file_exists(dir.path_join(path))


## Starts reading the prototypes in the background (once).
static func prepare() -> void:
	if _started:
		return
	_started = true
	if data_dir() == "":
		_ready = true
		return
	WorkerThreadPool.add_task(_scan, false, "Factorio sound rules")


static func ready() -> bool:
	return _ready


## The stream for a file, cached; null without the file. Loops are separate streams so a file
## can be both (car engine). Decodes on the spot when it isn't cached yet: for the windows' sounds,
## which are small; the world's use stream_soon().
static func stream(path: String, loop := false) -> AudioStream:
	var key := "%s|%d" % [path, int(loop)]
	_stream_lock.lock()
	var cached := _streams.has(key)
	var s: AudioStream = _streams.get(key)
	_stream_lock.unlock()
	if cached:
		return s
	s = _decode(path, loop)
	_stream_lock.lock()
	_streams[key] = s
	_stream_lock.unlock()
	return s


## The stream for a file if it is decoded already; otherwise null now, and it is decoded on a
## worker thread for next time. A sound's first decode took 110-340 ms on the main thread, a
## hitch while walking into new machines' sounds; skipping its very first play costs nothing.
static func stream_soon(path: String, loop := false) -> AudioStream:
	var key := "%s|%d" % [path, int(loop)]
	_stream_lock.lock()
	var s: AudioStream = _streams.get(key)
	if s == null and not _streams.has(key) and not _decoding.has(key):
		_make_crc_table()
		_decoding[key] = true
		WorkerThreadPool.add_task(_decode_later.bind(key, path, loop), false, "Factorio sound")
	_stream_lock.unlock()
	return s


static func _decode_later(key: String, path: String, loop: bool) -> void:
	var s := _decode(path, loop)
	_stream_lock.lock()
	_streams[key] = s
	_decoding.erase(key)
	_stream_lock.unlock()


static func _decode(path: String, loop: bool) -> AudioStreamOggVorbis:
	var dir := data_dir()
	if dir == "" or not path.ends_with(".ogg"):
		return null
	var full := dir.path_join(path)
	if not FileAccess.file_exists(full):
		return null
	var s := AudioStreamOggVorbis.load_from_buffer(_fix_comment(FileAccess.get_file_as_bytes(full)))
	if s != null:
		s.loop = loop
	return s


static var _crc_table := PackedInt64Array()

## Some of Factorio's files carry a Vorbis comment "Ogg Vorbis 1.0 Final" without the "key="
## that Godot expects, which makes it print a warning per file. The copy in memory gets
## "Ogg=Vorbis..." instead (same length), and its Ogg page a fresh checksum.
static func _fix_comment(data: PackedByteArray) -> PackedByteArray:
	var head := data.slice(0, mini(data.size(), 8192))
	var at := _find(head, "Ogg Vorbis 1.0 Final".to_ascii_buffer())
	if at < 0:
		return data
	var page := at
	var magic := "OggS".to_ascii_buffer()
	while page >= 0 and data.slice(page, page + 4) != magic:
		page -= 1
	if page < 0:
		return data
	data[at + 3] = 0x3D  # "="
	var length := 27 + data[page + 26]
	for i in data[page + 26]:
		length += data[page + 27 + i]
	for i in 4:
		data[page + 22 + i] = 0
	var crc := _crc(data, page, length)
	for i in 4:
		data[page + 22 + i] = (crc >> (8 * i)) & 0xFF
	return data


static func _find(data: PackedByteArray, needle: PackedByteArray) -> int:
	var first := needle[0]
	for i in data.size() - needle.size():
		if data[i] == first and data.slice(i, i + needle.size()) == needle:
			return i
	return -1


## Built on the main thread before any worker decodes (stream_soon), so they only read it.
static func _make_crc_table() -> void:
	if not _crc_table.is_empty():
		return
	var table := PackedInt64Array()
	table.resize(256)
	for i in 256:
		var r := i << 24
		for _j in 8:
			r = ((r << 1) ^ 0x04C11DB7) if (r & 0x80000000) != 0 else (r << 1)
			r &= 0xFFFFFFFF
		table[i] = r
	_crc_table = table


## Ogg's CRC-32 (polynomial 0x04c11db7, no reflection, initial value 0).
static func _crc(data: PackedByteArray, from: int, length: int) -> int:
	_make_crc_table()
	var crc := 0
	for i in range(from, from + length):
		crc = ((crc << 8) & 0xFFFFFFFF) ^ _crc_table[((crc >> 24) & 0xFF) ^ data[i]]
	return crc


## The numbered variations of a sound: "core/sound/walking/grass" ->
## ["base/.../grass-1.ogg", ...]. A prefix that is itself a file comes back alone.
static func variants(prefix: String) -> PackedStringArray:
	if _variants.has(prefix):
		return _variants[prefix]
	var out := PackedStringArray()
	if exists(prefix + ".ogg"):
		out.append(prefix + ".ogg")
	else:
		for i in range(1, 25):
			var p := "%s-%d.ogg" % [prefix, i]
			if exists(p):
				out.append(p)
			elif i > 1:
				break
	_variants[prefix] = out
	return out


## A random variation of `prefix`, or "" when there is none.
static func pick(prefix: String) -> String:
	var list := variants(prefix)
	return list[randi() % list.size()] if list.size() > 0 else ""


## The definition a sound file belongs to in Factorio's prototypes (its volume, variations,
## aggregation...), or null when it wasn't found (or the scan isn't done yet).
static func sound_for_file(path: String) -> SoundDef:
	if not _ready:
		return null
	return _by_file.get(path)


## What an entity sounds like while working, or null.
static func working_sound(entity: String) -> Loop:
	if not _ready:
		return null
	if _working.has(entity):
		return _working[entity]
	var loop: Loop = null
	if _entity_ws.has(entity):
		var at: Array = _entity_ws[entity]
		loop = _parse_working(at[0], at[1])
	if loop == null and FALLBACK_WORKING.has(entity):
		var f: Array = FALLBACK_WORKING[entity]
		loop = Loop.new()
		loop.sound = SoundDef.single(f[0], f[1])
		loop.sound.reach = f[2]
	if loop != null:
		for d: SoundDef in [loop.sound, loop.idle, loop.activate, loop.deactivate]:
			if d != null:
				_keep_present(d)
		if loop.sound.files.is_empty():
			loop = null
	_working[entity] = loop
	return loop


## A planet's persistent_ambient_sounds: {"base": [[SoundDef, darkness threshold], ...],
## "wind": SoundDef or null, "crossfade": [from control, from %, to control, to %] or [],
## "semi": [[SoundDef, mean seconds (0: plays all the time), variance seconds, zoom fade [from
## control, from %, to control, to %] or [], darkness threshold], ...]}. Empty without one.
static func planet_ambience(planet: String) -> Dictionary:
	if not _ready:
		return {}
	return _ambience.get(planet, {})


## Music for a planet ("" for space platforms): [[path, volume, track type, weight], ...].
static func music_for(planet: String) -> Array:
	var out: Array = []
	if not _ready:
		return out
	for t: Array in _tracks:
		var planets: Array = t[2]
		if (planet == "" and planets.is_empty()) or planets.has(planet) or planets.has("*"):
			out.append([t[0], t[1], t[3], t[4]])
	return out


static func _keep_present(d: SoundDef) -> void:
	var files := PackedStringArray()
	var lo := PackedFloat32Array()
	var hi := PackedFloat32Array()
	for i in d.files.size():
		if exists(d.files[i]):
			files.append(d.files[i])
			lo.append(d.min_volumes[i])
			hi.append(d.max_volumes[i])
	d.files = files
	d.min_volumes = lo
	d.max_volumes = hi


# --- The scan ------------------------------------------------------------------------------------

static var _FILE := RegEx.create_from_string("filename\\s*=\\s*\"__([a-z0-9-]+)__/([^\"]+\\.(?:ogg|wav))\"")
static var _VARS := RegEx.create_from_string("sound_variations(_with_volume_variations)?\\(\\s*\"__([a-z0-9-]+)__/([^\"]+)\"\\s*,\\s*(\\d+)(?:\\s*,\\s*([0-9.]+))?(?:\\s*,\\s*([0-9.]+))?")
static var _HEADER := RegEx.create_from_string("(?m)^\\s*type\\s*=\\s*\"([a-z0-9-]+)\",\\s*\\n\\s*name\\s*=\\s*\"([a-z0-9-]+)\"")
static var _REF := RegEx.create_from_string("^\\s*([a-z_]+)\\.([a-z_0-9]+)")
static var _AGG := RegEx.create_from_string("aggregation\\s*=\\s*\\{([^}]*)\\}")
static var _ATT := RegEx.create_from_string("attenuation\\s*=\\s*(?:\\{[^}]*curve_type\\s*=\\s*)?\"([A-Za-z-]+)\"")
static var _NAMED := RegEx.create_from_string("(?m)^\\s*sounds\\.([a-z_0-9]+)\\s*=\\s*")
static var _QUOTED := RegEx.create_from_string("\"([a-z0-9-]+)\"")
static var _NUM := {}
static var _KEYED := {}


static func _scan() -> void:
	var started := Time.get_ticks_msec()
	var dir := data_dir()
	var texts: Array = []  # LuaText
	for mod in PROTOTYPE_MODS:
		var root: String = mod.path_join("prototypes")
		if DirAccess.dir_exists_absolute(dir.path_join(root)):
			_collect(dir, root, texts)
	# Named sounds first (sounds.lua: `sounds.name = ...`), so entity files can refer to them.
	for lt: LuaText in texts:
		for m in _NAMED.search_all(lt.text):
			if not _sound_refs.has(m.get_string(1)):
				_sound_refs[m.get_string(1)] = []
			_sound_refs[m.get_string(1)].append([lt, m.get_end()])
	for lt: LuaText in texts:
		_index_files(lt)
		_index_entities(lt)
		_index_planets(lt)
		_index_music(lt)
	scan_msec = Time.get_ticks_msec() - started
	_lock.lock()
	_ready = true
	_lock.unlock()


static func _collect(dir: String, folder: String, texts: Array) -> void:
	var full := dir.path_join(folder)
	for file in DirAccess.get_files_at(full):
		if file.ends_with(".lua"):
			var t := FileAccess.get_file_as_string(full.path_join(file))
			if t.contains("sound") or t.contains("ambient"):
				texts.append(LuaText.new(t, folder.path_join(file)))
	for sub in DirAccess.get_directories_at(full):
		_collect(dir, folder.path_join(sub), texts)


## Every sound definition in the file, by the files it plays.
static func _index_files(lt: LuaText) -> void:
	var defs := {}  # opening brace -> SoundDef, parsed once
	for m in _FILE.search_all(lt.text) + _VARS.search_all(lt.text):
		var table := _sound_table(lt, m.get_start(), m.get_string(0).begins_with("sound_variations"))
		var d: SoundDef = null
		if table >= 0:
			if not defs.has(table):
				defs[table] = _parse_sound(lt, table)
			d = defs[table]
		else:
			d = _parse_variations_call(m)
		if d == null:
			continue
		for f in d.files:
			var old: SoundDef = _by_file.get(f)
			# The first definition wins, unless a later one says how to aggregate and it doesn't.
			if old == null or (old.max_count == 0 and d.max_count > 0):
				_by_file[f] = d


## The Sound table a file reference at `p` belongs to, or -1 for a bare sound_variations() list.
static func _sound_table(lt: LuaText, p: int, is_call: bool) -> int:
	var t := lt.enclosing(p)
	if is_call:
		return t if lt.key_before(p) == "variations" else -1
	if t < 0:
		return -1
	var parent := lt.parent_of[t]
	if parent >= 0 and lt.key_before(lt.pos[parent]) == "variations":
		return lt.parent_of[parent]
	return t


static func _parse_variations_call(m: RegExMatch) -> SoundDef:
	var d := SoundDef.new()
	var path := "%s/%s" % [m.get_string(2), m.get_string(3)]
	var with_range := m.get_string(1) != ""
	var lo := float(m.get_string(5)) if m.get_string(5) != "" else 0.5
	var hi := float(m.get_string(6)) if with_range and m.get_string(6) != "" else lo
	for i in range(1, int(m.get_string(4)) + 1):
		d.files.append("%s-%d.ogg" % [path, i])
		d.min_volumes.append(lo)
		d.max_volumes.append(hi)
	d.key = d.files[0] if d.files.size() > 0 else ""
	return d


## A Sound table: its variations (filename or sound_variations()) and its own keys.
static func _parse_sound(lt: LuaText, open: int) -> SoundDef:
	var d := SoundDef.new()
	var own := lt.top_level(open)
	var whole := lt.body(open)
	var vol := _num(own, "volume", -1.0)
	var lo := _num(own, "min_volume", vol if vol >= 0.0 else 1.0)
	var hi := _num(own, "max_volume", vol if vol >= 0.0 else 1.0)
	if vol >= 0.0:
		lo = vol
		hi = vol
	var f := _FILE.search(own)
	if f != null:
		d.files.append("%s/%s" % [f.get_string(1), f.get_string(2)])
		d.min_volumes.append(lo)
		d.max_volumes.append(hi)
	else:
		var v := _VARS.search(own)
		if v != null:
			var call := _parse_variations_call(v)
			d.files = call.files
			d.min_volumes = call.min_volumes
			d.max_volumes = call.max_volumes
		else:
			for child: Array in lt.children(open):
				if child[1] != "variations":
					continue
				var entries := lt.children(child[0])
				for entry: Array in entries:
					var e := lt.top_level(entry[0])
					var ef := _FILE.search(e)
					if ef == null:
						continue
					var ev := _num(e, "volume", -1.0)
					d.files.append("%s/%s" % [ef.get_string(1), ef.get_string(2)])
					d.min_volumes.append(ev if ev >= 0.0 else _num(e, "min_volume", 1.0))
					d.max_volumes.append(ev if ev >= 0.0 else _num(e, "max_volume", 1.0))
					if entry == entries[0]:
						var sp := _num(e, "speed", -1.0)
						d.min_speed = sp if sp > 0.0 else _num(e, "min_speed", 1.0)
						d.max_speed = sp if sp > 0.0 else _num(e, "max_speed", d.min_speed)
	var speed := _num(own, "speed", -1.0)
	if speed > 0.0:
		d.min_speed = speed
		d.max_speed = speed
	elif own.contains("min_speed"):
		d.min_speed = _num(own, "min_speed", 1.0)
		d.max_speed = _num(own, "max_speed", d.min_speed)
	d.reach = _num(own, "audible_distance_modifier", 1.0)
	d.priority = int(_num(own, "priority", 127.0))
	d.allow_random_repeat = own.contains("allow_random_repeat = true")
	var agg := _AGG.search(whole)
	if agg != null and own.contains("aggregation"):
		var a := agg.get_string(1)
		d.max_count = int(_num(a, "max_count", 0.0))
		d.remove = a.contains("remove = true")
		d.count_already_playing = a.contains("count_already_playing = true")
		d.progress_threshold = _num(a, "progress_threshold", 1.0)
		d.volume_reduction_rate = _num(a, "volume_reduction_rate", 2.0)
	var att := _ATT.search(whole)
	if att != null:
		d.attenuation = att.get_string(1)
	d.key = d.files[0] if d.files.size() > 0 else ""
	return d


static func _num(text: String, key: String, default: float) -> float:
	if not _NUM.has(key):
		_NUM[key] = RegEx.create_from_string("(?:^|[^a-z_])" + key + "\\s*=\\s*(-?[0-9.]+)\\s*(?:/\\s*([0-9.]+))?")
	var m: RegExMatch = _NUM[key].search(text)
	if m == null:
		return default
	var v := float(m.get_string(1))
	if m.get_string(2) != "":
		v /= maxf(float(m.get_string(2)), 0.0001)
	return v


## Where each entity's working_sound is, by entity name.
static func _index_entities(lt: LuaText) -> void:
	if not lt.text.contains("working_sound"):
		return
	var found := _HEADER.search_all(lt.text)
	for i in found.size():
		var name := found[i].get_string(2)
		if _entity_ws.has(name):
			continue
		var from := found[i].get_start()
		var to := found[i + 1].get_start() if i + 1 < found.size() else lt.text.length()
		var at := lt.text.find("working_sound", from)
		if at >= 0 and at < to:
			_entity_ws[name] = [lt, at]


## A working_sound at text position `at` (the word itself).
static func _parse_working(lt: LuaText, at: int) -> Loop:
	var value := _value_at(lt, at + "working_sound".length())
	if value.is_empty():
		return null
	var wl: LuaText = value[0]
	var open: int = value[1]
	var loop := Loop.new()
	var own := wl.top_level(open)
	for child: Array in wl.children(open):
		var key: String = child[1]
		match key:
			"sound":
				loop.sound = _sound_value(wl, child[0])
			"idle_sound":
				loop.idle = _sound_value(wl, child[0])
			"activate_sound":
				loop.activate = _sound_value(wl, child[0])
			"deactivate_sound":
				loop.deactivate = _sound_value(wl, child[0])
			"main_sounds":
				var first: Array = wl.children(child[0])
				if first.size() > 0:
					var entry: int = first[0][0]
					for c: Array in wl.children(entry):
						if c[1] == "sound":
							loop.sound = _sound_value(wl, c[0])
					var e := wl.top_level(entry)
					loop.fade_in = _num(e, "fade_in_ticks", 8.0) / 60.0
					loop.fade_out = _num(e, "fade_out_ticks", 20.0) / 60.0
	# `sound = sound_variations(...)` or `idle_sound = sounds.name`: not tables of their own.
	for key in ["sound", "idle_sound", "activate_sound", "deactivate_sound"]:
		if not _KEYED.has(key):
			_KEYED[key] = RegEx.create_from_string("(?:^|[^a-z_])" + key + "\\s*=\\s*(?:([a-z_]+)\\.([a-z_0-9]+)|sound_variations)")
		var m: RegExMatch = _KEYED[key].search(own)
		if m == null:
			continue
		var d: SoundDef = null
		if m.get_string(1) == "":
			var v := _VARS.search(own, m.get_start())
			d = _parse_variations_call(v) if v != null else null
		else:
			var ref := _resolve(m.get_string(1), m.get_string(2), wl)
			if not ref.is_empty():
				d = _parse_sound(ref[0], ref[1])
		match key:
			"sound":
				loop.sound = d if loop.sound == null else loop.sound
			"idle_sound":
				loop.idle = d
			"activate_sound":
				loop.activate = d
			"deactivate_sound":
				loop.deactivate = d
	if loop.sound == null:
		# A plain Sound in place of a WorkingSound.
		if own.contains("filename") or own.contains("variations"):
			loop.sound = _parse_sound(wl, open)
		else:
			return null
	loop.max_per_prototype = int(_num(own, "max_sounds_per_prototype", 0.0))
	if own.contains("fade_in_ticks"):
		loop.fade_in = _num(own, "fade_in_ticks", 8.0) / 60.0
	if own.contains("fade_out_ticks"):
		loop.fade_out = _num(own, "fade_out_ticks", 20.0) / 60.0
	loop.persistent = own.contains("persistent = true")
	if loop.sound.files.is_empty():
		return null
	return loop


## The table assigned after text position `from` (`= {...}`, `= sounds.name`, `= sounds.name(...)`),
## following references to sounds.lua: [LuaText, opening brace], or [] when it isn't one.
static func _value_at(lt: LuaText, from: int) -> Array:
	var rest := lt.text.substr(from, 200)
	var eq := rest.find("=")
	if eq < 0:
		return []
	var after := rest.substr(eq + 1)
	var stripped := after.strip_edges(true, false)
	var at := from + eq + 1 + (after.length() - stripped.length())
	if stripped.begins_with("{"):
		var o := lt.open_at(at)
		return [lt, o] if o >= 0 else []
	var m := _REF.search(stripped)
	if m == null:
		return []
	return _resolve(m.get_string(1), m.get_string(2), lt)


## `sounds.name` / `space_age_sounds.name`: the table it is defined as (or a function of it
## returns), preferring the sounds.lua of the mod the name points at: [LuaText, opening brace].
static func _resolve(prefix: String, name: String, from: LuaText) -> Array:
	if not _sound_refs.has(name):
		return []
	var mod := "space-age" if prefix.begins_with("space_age") else ("base" if prefix == "sounds" else from.path.get_slice("/", 0))
	var best: Array = _sound_refs[name][0]
	for target: Array in _sound_refs[name]:
		if (target[0] as LuaText).path.begins_with(mod + "/"):
			best = target
			break
	var tl: LuaText = best[0]
	var brace := tl.text.find("{", int(best[1]))
	var o := tl.open_at(brace) if brace >= 0 else -1
	return [tl, o] if o >= 0 else []


## A sound value at a table's opening brace: a Sound table, or a bare list of variations.
static func _sound_value(lt: LuaText, open: int) -> SoundDef:
	return _parse_sound(lt, open)


## Each planet's persistent_ambient_sounds.
static func _index_planets(lt: LuaText) -> void:
	if not lt.text.contains("persistent_ambient_sounds"):
		return
	var found := _HEADER.search_all(lt.text)
	for i in found.size():
		if found[i].get_string(1) != "planet":
			continue
		var name := found[i].get_string(2)
		var from := found[i].get_start()
		var to := found[i + 1].get_start() if i + 1 < found.size() else lt.text.length()
		var at := lt.text.find("persistent_ambient_sounds", from)
		if at < 0 or at >= to:
			continue
		var value := _value_at(lt, at + "persistent_ambient_sounds".length())
		if value.is_empty():
			continue
		var open: int = value[1]
		var amb := {"base": [], "wind": null, "crossfade": [], "semi": []}
		for child: Array in lt.children(open):
			match child[1]:
				"base_ambience":
					var parts: Array = lt.children(child[0])
					if parts.size() > 0 and parts[0][1] == "" and lt.top_level(child[0]).strip_edges().begins_with("{"):
						# A list of {sound = ...} entries (Gleba: day and night).
						for part: Array in parts:
							for c: Array in lt.children(part[0]):
								if c[1] == "sound":
									var d := _parse_sound(lt, c[0])
									amb["base"].append([d, _num(lt.body(c[0]), "darkness_threshold", 0.0)])
					else:
						amb["base"].append([_parse_sound(lt, child[0]), 0.0])
				"wind":
					amb["wind"] = _parse_sound(lt, child[0])
				"crossfade":
					amb["crossfade"] = _control_range(lt.body(child[0]))
				"semi_persistent":
					for entry: Array in lt.children(child[0]):
						var e := lt.top_level(entry[0])
						for c: Array in lt.children(entry[0]):
							if c[1] == "sound":
								var body := lt.body(c[0])
								amb["semi"].append([_parse_sound(lt, c[0]), _num(e, "delay_mean_seconds", 0.0),
									_num(e, "delay_variance_seconds", 0.0), _control_range(body) if body.contains("fade_in") else [],
									_num(body, "darkness_threshold", 0.0)])
		_ambience[name] = amb


## [from control, from volume %, to control, to volume %] of a crossfade or zoom fade, or [].
static func _control_range(text: String) -> Array:
	var m := RegEx.create_from_string("from\\s*=\\s*\\{\\s*(?:control\\s*=\\s*)?([0-9.]+)\\s*,\\s*(?:volume_percentage\\s*=\\s*)?([0-9.]+)\\s*\\}\\s*,\\s*to\\s*=\\s*\\{\\s*(?:control\\s*=\\s*)?([0-9.]+)\\s*,\\s*(?:volume_percentage\\s*=\\s*)?([0-9.]+)").search(text)
	if m == null:
		return []
	return [float(m.get_string(1)), float(m.get_string(2)), float(m.get_string(3)), float(m.get_string(4))]


## The music: ambient-sound prototypes with a static sound.
static func _index_music(lt: LuaText) -> void:
	if not lt.text.contains("\"ambient-sound\""):
		return
	var found := _HEADER.search_all(lt.text)
	for i in found.size():
		if found[i].get_string(1) != "ambient-sound":
			continue
		var t := lt.enclosing(found[i].get_start())
		if t < 0:
			continue
		var own := lt.top_level(t)
		var path := ""
		var volume := 1.0
		var s := RegEx.create_from_string("(?:^|[^a-z_])sound\\s*=\\s*\"__([a-z0-9-]+)__/([^\"]+)\"").search(own)
		if s != null:
			path = "%s/%s" % [s.get_string(1), s.get_string(2)]
		else:
			for c: Array in lt.children(t):
				if c[1] == "sound":
					var d := _parse_sound(lt, c[0])
					if d.files.size() > 0:
						path = d.files[0]
						volume = d.max_volumes[0]
		if path == "":
			continue  # variable_sound: layered tracks, not played here
		var planets: Array = []
		for c: Array in lt.children(t):
			if c[1] == "planets":
				for p in _QUOTED.search_all(lt.body(c[0])):
					planets.append(p.get_string(1))
		var single := RegEx.create_from_string("planet\\s*=\\s*\"([a-z0-9-]+)\"").search(own)
		if single != null:
			planets.append(single.get_string(1))
		if own.contains("play_on_all_surfaces = true"):
			planets.append("*")
		var kind := RegEx.create_from_string("track_type\\s*=\\s*\"([a-z-]+)\"").search(own)
		_tracks.append([path, volume, planets, kind.get_string(1) if kind != null else "main-track", _num(own, "weight", 1.0)])


## Drops the cached streams (at exit, so Godot doesn't report them as leaked).
static func clear_cache() -> void:
	_streams.clear()
	_variants.clear()
