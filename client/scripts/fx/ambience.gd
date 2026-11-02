extends Node
## A planet's own background sound and music, as its prototype has them (sound_bank.gd reads
## `persistent_ambient_sounds` and the ambient-sound prototypes from the player's install):
## the base ambience and the wind, crossfaded by zoom (zoomed out, the wind; close up, the
## ambience; Gleba's day and night ambiences by darkness); now and then one of the planet's distant
## sounds (Vulcanus' rumbles, Fulgora's thunder, Aquilo's cracking ice, Gleba's birds and rain);
## and the music written for the planet (space platforms: the space tracks), only when the music
## volume is above 0. Not positional: they play on the Ambient and Music buses.
##
## sfx.gd owns it; fx.gd tells it the planet (set_planet) and how dark it is; sfx.gd the zoom.

const SoundBank := preload("res://scripts/fx/sound_bank.gd")
const FxSettings := preload("res://scripts/fx/fx_settings.gd")

const FADE := 2.0  # seconds to fade the ambience in or out when the planet changes
const MUSIC_GAP := Vector2(40.0, 120.0)

## Factorio's zoom: about 1.8 at the default view, smaller further out (sfx.gd sets it).
var zoom := 1.8
var darkness := 0.0

var _planet := ""
var _space := false
var _amb: Dictionary = {}
var _base: Array = []  # [AudioStreamPlayer, SoundDef, darkness threshold]
var _wind: AudioStreamPlayer = null
var _wind_def: SoundBank.SoundDef = null
var _semi: Array = []  # [SoundDef, mean, variance, zoom fade, seconds to the next, AudioStreamPlayer or null, darkness threshold]
var _fade := 0.0
var _pending := false
var _music := AudioStreamPlayer.new()
var _music_wait := 8.0
var _last_track := ""
var _oneshot := AudioStreamPlayer.new()


func _ready() -> void:
	_music.bus = "Music"
	_music.finished.connect(func(): _music_wait = randf_range(MUSIC_GAP.x, MUSIC_GAP.y))
	add_child(_music)
	_oneshot.bus = "Ambient"
	add_child(_oneshot)


func _exit_tree() -> void:
	stop()
	_music.stream = null
	_oneshot.stream = null


## The planet the character is on ("" or `space` on a platform).
func set_planet(planet: String, space := false) -> void:
	if planet == _planet and space == _space and not _pending:
		return
	_planet = planet
	_space = space
	_pending = true  # built once the prototypes are read (and after the old one faded)


func stop() -> void:
	for b: Array in _base:
		(b[0] as AudioStreamPlayer).stop()
		(b[0] as AudioStreamPlayer).stream = null
		(b[0] as Node).queue_free()
	_base.clear()
	if _wind != null:
		_wind.stop()
		_wind.stream = null
		_wind.queue_free()
		_wind = null
	for s: Array in _semi:
		if s[5] != null:
			(s[5] as AudioStreamPlayer).stream = null
			(s[5] as Node).queue_free()
	_semi.clear()
	_oneshot.stop()
	_fade = 0.0
	# Built again for the same planet (fx.gd resets on every welcome and surface change).
	_pending = _planet != "" or _space


func _build() -> void:
	stop()
	_pending = false
	_amb = {} if _space else SoundBank.planet_ambience(_planet)
	if _amb.is_empty():
		return
	for b: Array in _amb.get("base", []):
		var def: SoundBank.SoundDef = b[0]
		var p := _loop_player(def)
		if p != null:
			_base.append([p, def, float(b[1])])
	_wind_def = _amb.get("wind")
	if _wind_def != null:
		_wind = _loop_player(_wind_def)
	for s: Array in _amb.get("semi", []):
		var def: SoundBank.SoundDef = s[0]
		var loop: AudioStreamPlayer = null
		if float(s[1]) <= 0.0:
			loop = _loop_player(def)  # no delay: it plays all the time (Gleba's rain)
		_semi.append([def, float(s[1]), float(s[2]), s[3], randf_range(2.0, maxf(3.0, float(s[1]))), loop, float(s[4])])


func _loop_player(def: SoundBank.SoundDef) -> AudioStreamPlayer:
	if def == null or def.files.is_empty():
		return null
	var stream := SoundBank.stream(def.files[0], true)
	if stream == null:
		return null
	var p := AudioStreamPlayer.new()
	p.bus = "Ambient"
	p.stream = stream
	p.volume_db = -80.0
	add_child(p)
	p.play(randf() * maxf(0.0, stream.get_length() - 0.1))
	return p


func _process(delta: float) -> void:
	if _pending and SoundBank.ready():
		_build()
	_fade = minf(1.0, _fade + delta / FADE)
	# Wind when zoomed out, the ambience close up; Factorio's cosine crossfade over its zoom.
	var cross: Array = _amb.get("crossfade", [])
	var ambience_share := 1.0
	if cross.size() == 4:
		var t := clampf((zoom - float(cross[0])) / maxf(float(cross[2]) - float(cross[0]), 0.01), 0.0, 1.0)
		t = 0.5 - 0.5 * cos(PI * t)
		ambience_share = lerpf(float(cross[1]), float(cross[3]), t) / 100.0
	for b: Array in _base:
		var def: SoundBank.SoundDef = b[1]
		var v := def.max_volumes[0] * ambience_share * _darkness_gain(float(b[2])) * _fade
		(b[0] as AudioStreamPlayer).volume_db = linear_to_db(maxf(v, 0.0001))
	if _wind != null:
		var v := _wind_def.max_volumes[0] * (1.0 - ambience_share) * _fade
		_wind.volume_db = linear_to_db(maxf(v, 0.0001))
	for s: Array in _semi:
		var def: SoundBank.SoundDef = s[0]
		var gain := _zoom_gain(s[3]) * _darkness_gain(float(s[6])) * _fade
		if s[5] != null:
			(s[5] as AudioStreamPlayer).volume_db = linear_to_db(maxf(def.max_volumes[0] * gain, 0.0001))
			continue
		s[4] = float(s[4]) - delta
		if float(s[4]) > 0.0:
			continue
		s[4] = maxf(1.0, float(s[1]) + randf_range(-1.0, 1.0) * float(s[2]))
		if gain <= 0.01 or _oneshot.playing:
			continue
		var i := def.pick()
		var stream := SoundBank.stream(def.files[i])
		if stream != null:
			_oneshot.stream = stream
			_oneshot.volume_db = linear_to_db(maxf(def.volume_of(i) * gain, 0.0001))
			_oneshot.pitch_scale = def.speed()
			_oneshot.play()
	_update_music(delta)


## advanced_volume_control.darkness_threshold: a night sound (> 0) grows with darkness up to the
## threshold, a day sound (< 0) fades out as it gets dark.
func _darkness_gain(threshold: float) -> float:
	if threshold > 0.0:
		return clampf(darkness / threshold, 0.0, 1.0)
	if threshold < 0.0:
		return clampf(1.0 - darkness / -threshold, 0.0, 1.0)
	return 1.0


## advanced_volume_control.fades.fade_in by zoom: [from zoom, from %, to zoom, to %].
func _zoom_gain(fade) -> float:
	if not (fade is Array) or fade.size() != 4:
		return 1.0
	var t := clampf((zoom - float(fade[0])) / maxf(float(fade[2]) - float(fade[0]), 0.01), 0.0, 1.0)
	t = 0.5 - 0.5 * cos(PI * t)
	return lerpf(float(fade[1]), float(fade[3]), t) / 100.0


## The planet's music, one track at a time with a pause between, when the music volume is above 0.
func _update_music(delta: float) -> void:
	if FxSettings.volumes["music"] <= 0.0 or _music.playing or _pending or (_planet == "" and not _space):
		return
	_music_wait -= delta
	if _music_wait > 0.0:
		return
	_music_wait = randf_range(MUSIC_GAP.x, MUSIC_GAP.y)
	var tracks := SoundBank.music_for("" if _space else _planet)
	var total := 0.0
	for t: Array in tracks:
		if t[0] != _last_track:
			total += float(t[3])
	var r := randf() * total
	for t: Array in tracks:
		if t[0] == _last_track:
			continue
		r -= float(t[3])
		if r <= 0.0:
			_music.stream = SoundBank.stream(t[0])
			if _music.stream != null:
				_last_track = t[0]
				_music.volume_db = linear_to_db(maxf(float(t[1]), 0.0001))
				_music.play()
				if FxSettings.log_sounds:
					print("sfx: music %s" % t[0])
			return
