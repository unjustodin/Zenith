extends Node3D
## Plays Factorio's sounds by Factorio's rules (read from its prototypes by sound_bank.gd):
## positional one-shots (steps, shots, explosions, building) and the working loops of machines and
## vehicles near the listener, the windows' clicks, and, through ambience.gd, each planet's
## ambience and music.
##
## What it does as Factorio does:
## - each sound's own volume, a random variation (not the same one twice running) and pitch range;
## - distance: a sound fades out over the audible distance (AUDIBLE_DISTANCE tiles times its
##   `audible_distance_modifier`) along its attenuation curve, heard from the middle of the view,
##   and quieter the further the camera is zoomed out;
## - `aggregation`: at most `max_count` of one sound start at once (counting those still playing when
##   `count_already_playing`), the rest dropped (`remove`) or made quieter;
## - working loops: at most `max_sounds_per_prototype` machines of a kind heard at once (nearest and
##   loudest), faded in and out over the prototype's `fade_in_ticks`/`fade_out_ticks`, the idle
##   sound for idle machines;
## - a limit on sounds at once per category (CATEGORY_LIMITS), where a sound of higher `priority`
##   or a louder one takes the place of the weakest;
## - and, so a big base never clips, a limiter on the master output.
## The audible distance, the default curve and the category limits are the engine's, not in the
## data: the values here are chosen to sound like it.
##
## The UI calls the static helper: `Sfx.play_ui("gui-click")` (core/sound/<name>.ogg), with
## `const Sfx := preload("res://scripts/fx/sfx.gd")`. Without an instance or an install it does
## nothing.
##
## `--sfx-log` prints every sound started and, every 5 s, how many voices are busy, the loudest
## peaks, and sounds started over the same file.

const SoundBank := preload("res://scripts/fx/sound_bank.gd")
const FxSettings := preload("res://scripts/fx/fx_settings.gd")
const Ambience := preload("res://scripts/fx/ambience.gd")

const ONE_SHOT_VOICES := 24
const UI_VOICES := 4
## One-shots playing at once per category (bus). Machine and vehicle loops have their own voices
## (Settings: max_voices).
const CATEGORY_LIMITS := {"Effects": 10, "Walking": 2, "Weapons": 6, "Explosions": 6, "Enemies": 6, "Environment": 6}
## Working loops of one prototype heard at once when its prototype doesn't say.
const DEFAULT_PER_PROTOTYPE := 4
## Tiles over which a sound with audible_distance_modifier 1 fades to nothing.
const AUDIBLE_DISTANCE := 40.0
## The camera distance (camera_rig.gd) of the default view: zooming out from it moves the
## listener up, away from everything, as zooming out quietens Factorio.
const DEFAULT_CAMERA_DISTANCE := 30.0
const LISTENER_HEIGHT := 3.0
## Same file again within this time is skipped when its definition has no aggregation (twenty
## biters dying in one tick).
const REPEAT_MSEC := 40
## A playing source keeps its voice unless another is this much louder, so voices don't hop
## between machines of about the same loudness.
const KEEP_BONUS := 1.4

static var instance = null  # the Sfx node, untyped so its own methods can be called


class LoopVoice:
	var player: AudioStreamPlayer3D
	var key = null  # whatever the caller identifies the source by; null when free
	var path := ""
	var group := ""
	var gain := 0.0  # the fade, 0 to 1
	var volume := 1.0
	var reach := 1.0
	var curve := ""
	var fade_in := 0.13
	var fade_out := 0.33
	var wanted := false


class Shot:
	var player: AudioStreamPlayer3D
	var path := ""
	var key := ""  # the sound definition, for aggregation
	var bus := "Effects"
	var priority := 127
	var volume := 1.0  # before distance
	var reach := 1.0
	var curve := ""
	var started := 0
	var length := 1.0


var listener := AudioListener3D.new()
var ambience := Ambience.new()
var _loops: Array = []  # LoopVoice
var _shots: Array = []  # Shot
var _ui: Array = []  # AudioStreamPlayer
var _ui_next := 0
var _zoom_height := 0.0
var _last_played := {}  # path -> msec
var _log_timer := 0.0
var _counts := {}  # what played since the last log line, by path
## --sfx-log measurements over each 5 s: the most voices at once, the loudest peaks (dB) on the
## Effects bus and the master output, sounds started while the same file was already playing, and
## the most voices playing one file at once.
var _stat_voices := 0
var _stat_peak_fx := -200.0
var _stat_peak_master := -200.0
var _stat_peak_env := -200.0
var _stat_peak_amb := -200.0
var _stat_dups := 0
var _stat_same := 0
var _stat_dropped := 0


## A click or other window sound: "gui-click", "gui-tab", "inventory-move"... (Factorio's
## core/sound names), or a full path relative to Factorio's data folder.
static func play_ui(sound: String, volume := 1.0) -> void:
	if instance != null and is_instance_valid(instance):
		instance.play_flat(sound if sound.ends_with(".ogg") else "core/sound/%s.ogg" % sound, volume)


func _ready() -> void:
	instance = self
	FxSettings.load_settings()
	SoundBank.prepare()
	add_child(listener)
	listener.make_current()
	for i in FxSettings.max_voices:
		var v := LoopVoice.new()
		v.player = _player_3d()
		v.player.bus = "Environment"  # Factorio: machines and vehicles
		_loops.append(v)
	for i in ONE_SHOT_VOICES:
		var s := Shot.new()
		s.player = _player_3d()
		_shots.append(s)
	for i in UI_VOICES:
		var p := AudioStreamPlayer.new()
		p.bus = "UI"
		add_child(p)
		_ui.append(p)
	ambience.name = "Ambience"
	add_child(ambience)
	if FxSettings.log_sounds:
		print("sfx: Factorio sounds %s, %d loop voices, volumes %s" % [
			"from " + SoundBank.data_dir() if SoundBank.available() else "not found (silent)", _loops.size(), FxSettings.volumes])


func _exit_tree() -> void:
	if instance == self:
		instance = null
	# Playbacks still running at quit would be reported as leaked.
	stop_all()
	for v: LoopVoice in _loops:
		v.player.stream = null
	for s: Shot in _shots:
		s.player.stream = null
	for p: AudioStreamPlayer in _ui:
		p.stream = null


func _player_3d() -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	p.bus = "Effects"
	# The distance fade is Factorio's (distance_gain), not Godot's.
	p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_DISABLED
	p.max_distance = 0.0
	p.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_DISABLED
	add_child(p)
	return p


## Hears from above the point the camera looks at, turned like the camera, so sounds pan with
## the view. Factorio hears from the middle of the screen. `camera_distance` (camera_rig.gd's) zooms.
func set_listener(focus: Vector2, camera: Camera3D, camera_distance := DEFAULT_CAMERA_DISTANCE) -> void:
	var basis := Basis.IDENTITY
	if camera != null:
		var forward := -camera.global_transform.basis.z
		forward.y = 0.0
		if forward.length() > 0.01:
			basis = Basis.looking_at(forward.normalized(), Vector3.UP)
	listener.global_transform = Transform3D(basis, Vector3(focus.x, LISTENER_HEIGHT, focus.y))
	_zoom_height = maxf(0.0, camera_distance - DEFAULT_CAMERA_DISTANCE) * 0.5
	ambience.zoom = 54.0 / maxf(camera_distance, 1.0)


func listener_position() -> Vector3:
	return listener.global_position


## How loud a sound at `pos` is heard, 0 to 1: Factorio's fade over the audible distance.
func distance_gain(pos: Vector3, reach := 1.0, curve := "") -> float:
	var here := listener.global_position
	var flat := Vector2(pos.x - here.x, pos.z - here.z).length()
	var d := sqrt(flat * flat + _zoom_height * _zoom_height)
	var x := d / (AUDIBLE_DISTANCE * maxf(reach, 0.05))
	if x >= 1.0:
		return 0.0
	match curve:
		"none":
			return 1.0
		"exponential":
			return pow(1.0 - x, 3.0)
		"logarithmic":
			return 1.0 - log(1.0 + 9.0 * x) / log(10.0)
		"cosine":
			return 0.5 + 0.5 * cos(PI * x)
		"S-curve":
			return 1.0 - smoothstep(0.0, 1.0, x)
	return pow(1.0 - x, 1.5)


## A positional one-shot of a file. The file's definition in Factorio's prototypes, when found,
## decides its volume, variations' pitch, reach, aggregation and priority; `volume`,
## `pitch_spread` and `reach` are used for files it doesn't define. `bus` is the sound settings
## category (fx_settings.gd BUSES). Quietly does nothing for "" or a missing file.
func play_at(path: String, pos: Vector3, volume := 1.0, pitch_spread := 0.0, reach := 1.0, bus := "Effects") -> void:
	if path == "" or volume <= 0.0:
		return
	var def := SoundBank.sound_for_file(path)
	if def != null:
		var i := def.files.find(path)
		_play(path, def, pos, def.volume_of(i) if i >= 0 else volume, def.speed(), bus)
	else:
		var plain := SoundBank.SoundDef.single(path, volume)
		plain.reach = reach
		plain.min_speed = 1.0 - pitch_spread
		plain.max_speed = 1.0 + pitch_spread
		_play(path, plain, pos, volume, plain.speed(), bus)


## A positional one-shot of a whole definition: a random variation of it.
func play_def(def: SoundBank.SoundDef, pos: Vector3, bus := "Effects", scale := 1.0) -> void:
	if def == null or def.files.is_empty():
		return
	var i := def.pick()
	_play(def.files[i], def, pos, def.volume_of(i) * scale, def.speed(), bus)


func _play(path: String, def: SoundBank.SoundDef, pos: Vector3, volume: float, speed: float, bus: String) -> void:
	var gain := distance_gain(pos, def.reach, def.attenuation)
	if gain <= 0.0 or volume <= 0.0:
		return
	var now := Time.get_ticks_msec()
	if def.max_count <= 0 and now - int(_last_played.get(path, -100000)) < REPEAT_MSEC:
		_stat_dropped += 1
		return
	var factor := _aggregate(def, now)
	if factor <= 0.0:
		_stat_dropped += 1
		return
	volume *= factor
	var stream := SoundBank.stream_soon(path)
	if stream == null:
		return
	var s := _shot_voice(bus, def.priority, volume * gain)
	if s == null:
		_stat_dropped += 1
		return
	_last_played[path] = now
	if FxSettings.log_sounds and _playing_paths().has(path):
		_stat_dups += 1
	s.player.stop()
	s.player.stream = stream
	s.path = path
	s.key = def.key
	s.bus = bus
	s.priority = def.priority
	s.volume = volume
	s.reach = def.reach
	s.curve = def.attenuation
	s.started = now
	s.length = maxf(stream.get_length(), 0.05) / maxf(speed, 0.05)
	s.player.global_position = pos
	s.player.volume_db = linear_to_db(maxf(volume * gain, 0.0001))
	s.player.pitch_scale = speed
	s.player.bus = bus
	s.player.play()
	_note(path, pos)


## Factorio's aggregation: the volume factor for one more of `def` now (0: don't play it).
func _aggregate(def: SoundBank.SoundDef, now: int) -> float:
	if def.max_count <= 0:
		return 1.0
	var n := 0
	for s: Shot in _shots:
		if s.key != def.key or not s.player.playing:
			continue
		if now - s.started <= 17:  # started this tick
			n += 1
		elif def.count_already_playing and (now - s.started) / 1000.0 / s.length < def.progress_threshold:
			n += 1
	if n < def.max_count:
		return 1.0
	if def.remove:
		return 0.0
	return pow(n - def.max_count + 2.0, -def.volume_reduction_rate)


## A voice for a one-shot in `bus`: a free one while the category has room, else the weakest
## of the category (or of all) if the new sound outranks it, else null.
func _shot_voice(bus: String, priority: int, loudness: float) -> Shot:
	var limit: int = CATEGORY_LIMITS.get(bus, ONE_SHOT_VOICES)
	var in_bus := 0
	var weakest_bus: Shot = null
	var weakest: Shot = null
	var free: Shot = null
	for s: Shot in _shots:
		if not s.player.playing:
			if free == null:
				free = s
			continue
		if s.bus == bus:
			in_bus += 1
			if weakest_bus == null or _outranks(weakest_bus, s):
				weakest_bus = s
		if weakest == null or _outranks(weakest, s):
			weakest = s
	var victim: Shot = null
	if in_bus >= limit:
		victim = weakest_bus
	elif free != null:
		return free
	else:
		victim = weakest
	if victim == null:
		return null
	if priority < victim.priority or (priority == victim.priority and loudness > _heard(victim)):
		return victim
	return null


## True when `b` should give way before `a`: lower priority (higher number), else quieter.
func _outranks(a: Shot, b: Shot) -> bool:
	if a.priority != b.priority:
		return a.priority < b.priority
	return _heard(a) > _heard(b)


func _heard(s: Shot) -> float:
	return s.volume * distance_gain(s.player.global_position, s.reach, s.curve)


## Not positional: the windows' sounds.
func play_flat(path: String, volume := 1.0) -> void:
	var stream := SoundBank.stream(path)
	if stream == null:
		return
	var p: AudioStreamPlayer = _ui[_ui_next]
	_ui_next = (_ui_next + 1) % _ui.size()
	p.stream = stream
	p.volume_db = linear_to_db(volume)
	p.play()
	_note(path, null)


## The working loops that should be playing now: one Dictionary per source in hearing range:
## {key, pos (Vector3), path, volume, reach, curve, group (the prototype), per_group (its
## max_sounds_per_prototype, 0: default), fade_in, fade_out (seconds)}. The loudest get the voices,
## at most per_group of each group; voices that lose their source fade out.
func set_loops(sources: Array) -> void:
	var playing := {}
	for v: LoopVoice in _loops:
		if v.key != null and v.wanted:
			playing[v.key] = true
	var scored: Array = []
	for s: Dictionary in sources:
		var g := distance_gain(s["pos"], float(s.get("reach", 1.0)), str(s.get("curve", "")))
		if g <= 0.0:
			continue
		var loudness := float(s["volume"]) * g * (KEEP_BONUS if playing.has(s["key"]) else 1.0)
		scored.append([loudness, s])
	scored.sort_custom(func(a, b): return a[0] > b[0])
	var chosen := {}
	var per_group := {}
	for entry in scored:
		if chosen.size() >= _loops.size():
			break
		var s: Dictionary = entry[1]
		var group := str(s.get("group", s["path"]))
		var limit := int(s.get("per_group", 0))
		if limit <= 0:
			limit = DEFAULT_PER_PROTOTYPE
		var n: int = per_group.get(group, 0)
		if n >= limit:
			continue
		per_group[group] = n + 1
		chosen[s["key"]] = s
	for v: LoopVoice in _loops:
		v.wanted = v.key != null and chosen.has(v.key) and chosen[v.key]["path"] == v.path
		if v.wanted:
			var s: Dictionary = chosen[v.key]
			v.player.global_position = s["pos"]
			v.volume = float(s["volume"])
			chosen.erase(v.key)
	for key in chosen:
		var s: Dictionary = chosen[key]
		var voice := _free_voice()
		if voice == null:
			break
		var stream := SoundBank.stream_soon(s["path"], true)
		if stream == null:
			continue
		if FxSettings.log_sounds and _playing_paths().has(s["path"]):
			_stat_dups += 1
		voice.key = key
		voice.path = s["path"]
		voice.group = str(s.get("group", s["path"]))
		voice.volume = float(s["volume"])
		voice.reach = float(s.get("reach", 1.0))
		voice.curve = str(s.get("curve", ""))
		voice.fade_in = maxf(float(s.get("fade_in", 0.13)), 0.02)
		voice.fade_out = maxf(float(s.get("fade_out", 0.33)), 0.02)
		voice.wanted = true
		voice.gain = 0.0
		voice.player.stream = stream
		voice.player.global_position = s["pos"]
		voice.player.volume_db = -80.0
		# Start somewhere in the loop, so a row of machines doesn't play in unison.
		voice.player.play(randf() * maxf(0.0, stream.get_length() - 0.1))
		_note(voice.path + " (loop)", s["pos"])


func _free_voice() -> LoopVoice:
	var quietest: LoopVoice = null
	for v: LoopVoice in _loops:
		if v.key == null:
			return v
		if not v.wanted and (quietest == null or v.gain < quietest.gain):
			quietest = v
	if quietest != null:
		quietest.player.stop()
		quietest.key = null
	return quietest


func busy_loops() -> int:
	var n := 0
	for v: LoopVoice in _loops:
		if v.key != null:
			n += 1
	return n


func busy_shots() -> int:
	var n := 0
	for s: Shot in _shots:
		if s.player.playing:
			n += 1
	return n


func stop_all() -> void:
	for v: LoopVoice in _loops:
		v.player.stop()
		v.key = null
		v.gain = 0.0
	for s: Shot in _shots:
		s.player.stop()
	ambience.stop()


func _process(delta: float) -> void:
	for v: LoopVoice in _loops:
		if v.key == null:
			continue
		if v.wanted:
			v.gain = minf(1.0, v.gain + delta / v.fade_in)
		else:
			v.gain -= delta / v.fade_out
			if v.gain <= 0.0:
				v.player.stop()
				v.key = null
				continue
		var heard := v.gain * v.volume * distance_gain(v.player.global_position, v.reach, v.curve)
		v.player.volume_db = linear_to_db(maxf(heard, 0.0001))
	# One-shots follow the listener too (the view moves while an explosion rings out).
	for s: Shot in _shots:
		if s.player.playing:
			s.player.volume_db = linear_to_db(maxf(_heard(s), 0.0001))
	if FxSettings.log_sounds:
		_measure()
		_log_timer += delta
		if _log_timer >= 5.0:
			_log_timer = 0.0
			print("sfx: voices %d/%d loops, %d/%d one-shots; played %s" % [busy_loops(), _loops.size(), busy_shots(), _shots.size(), _counts])
			print("sfx: 5 s: at most %d voices, peak %.1f dB effects / %.1f dB master (machines %.1f, ambience %.1f), %d started over the same file, at most %d of one file, %d held back" % [
				_stat_voices, _stat_peak_fx, _stat_peak_master, _stat_peak_env, _stat_peak_amb, _stat_dups, _stat_same, _stat_dropped])
			_counts.clear()
			_stat_voices = 0
			_stat_peak_fx = -200.0
			_stat_peak_master = -200.0
			_stat_peak_env = -200.0
			_stat_peak_amb = -200.0
			_stat_dups = 0
			_stat_same = 0
			_stat_dropped = 0


## Paths of the voices playing now, with how many play each.
func _playing_paths() -> Dictionary:
	var out := {}
	for v: LoopVoice in _loops:
		if v.key != null and v.player.playing:
			out[v.path] = int(out.get(v.path, 0)) + 1
	for s: Shot in _shots:
		if s.player.playing:
			out[s.path] = int(out.get(s.path, 0)) + 1
	return out


func _measure() -> void:
	var playing := _playing_paths()
	var total := 0
	for path in playing:
		total += int(playing[path])
		_stat_same = maxi(_stat_same, int(playing[path]))
	_stat_voices = maxi(_stat_voices, total)
	_stat_peak_fx = maxf(_stat_peak_fx, _bus_peak("Effects"))
	_stat_peak_master = maxf(_stat_peak_master, _bus_peak("Master"))
	_stat_peak_env = maxf(_stat_peak_env, _bus_peak("Environment"))
	_stat_peak_amb = maxf(_stat_peak_amb, _bus_peak("Ambient"))


static func _bus_peak(bus: String) -> float:
	var i := AudioServer.get_bus_index(bus)
	if i < 0:
		return -200.0
	return maxf(AudioServer.get_bus_peak_volume_left_db(i, 0), AudioServer.get_bus_peak_volume_right_db(i, 0))


func _note(what: String, pos) -> void:
	if not FxSettings.log_sounds:
		return
	var short := what.get_file()
	_counts[short] = int(_counts.get(short, 0)) + 1
	if pos is Vector3:
		var p: Vector3 = pos
		print("sfx: play %s at (%.1f, %.1f), %.1f tiles away" % [what, p.x, p.z, p.distance_to(listener.global_position)])
	else:
		print("sfx: play %s" % what)
