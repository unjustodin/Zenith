extends Node
## Holds the game at 60 UPS (Settings > Graphics > Hold the game at 60 UPS). The client's drawing
## doesn't slow Factorio's simulation, but what it asks the bridge for does: every item on belts
## near the focus, far belt lanes, moving things and machine states within the entity distance,
## chunks within the view distance and the minimap's charts are all worked out in the game's tick,
## and on the same PC the client's own frames take CPU from the server. Measured on the owner's
## save (REPORT-ACCT2.md): the bridge cost ~14 ms a tick standing at its belts and ~23 walking,
## so the game ran at 50 and 35 UPS.
##
## This watches the game's UPS (server ticks per real second, over the last WINDOW seconds) and,
## while it stays under LOW, lowers one step of STEPS at a time, PAUSE_DOWN apart; once it has held
## HIGH for a while it takes the last step back, towards the player's own settings. It never writes
## the settings: `limit()` gives each knob's value under the player's, which main.gd applies.
## Ticks that stop altogether (a save, the game paused) are not slowness and are skipped.
##
## It also keeps the bridge's work budget per tick (budget.lua) to the room the game has, before
## anything is asked: a big request (a map zoom, a jump, another planet's remote view) is worked
## through within that budget, so it can't make a slow tick when it comes, it only fills in more
## slowly. Reacting once the UPS has dropped would be too late for those (the owner's point).

const BeltCaps := preload("res://scripts/world/belt_lanes.gd")
const Settings := preload("res://scripts/menu/settings.gd")
const AddonRequests := preload("res://scripts/addons/addon_requests.gd")

signal changed

## Steps from the first taken to the last, cheapest in looks for the UPS they buy first (measured on
## the owner's save; REPORT-ACCT2.md). [knob, value]: the knob's value is at most the smallest of
## the steps taken. map: how much longer the minimap waits between refreshes; entity: tiles round
## the focus with moving things and machine states; far: the belt item distance (tiles); updates:
## the most belt items sent moving (Belt updates); view: chunks drawn round the focus; fps: the frame rate cap (frees CPU for the
## server on the same PC); rate: the bridge sends its costliest updates less often (`rate`, 1-3),
## which the client glides over, so it goes first. The last value of each knob is its floor.
const STEPS := [
	["rate", 1],
	["rate", 2],
	["map", 2.0],
	["rate", 3],
	["entity", 128],
	["updates", 3000],
	["far", 96],
	["map", 4.0],
	["entity", 96],
	["updates", 1500],
	["far", 64],
	["entity", 64],
	["view", 7],
	["far", 32],
	["view", 5],
	["fps", 45],
]
const LABELS := {"map": "minimap refreshes %s× apart", "entity": "entity distance %s", "far": "belt item distance %s",
	"updates": "belt updates %s", "view": "view distance %s", "fps": "FPS limit %s",
	"rate": "updates slowed to level %s"}

const LOW := 57.0  # UPS under this, for HOLD_DOWN seconds, takes a step down
const HIGH := 59.5  # UPS at or over this, for hold_up seconds, takes one back
const WINDOW := 3.0  # seconds the UPS is measured over for stepping down
const LONG_WINDOW := 10.0  # and for stepping back up: a 3 s reading at 60 dips under 59.5 now and then
const HOLD_DOWN := 2.0
## Seconds under LOW it takes after a step back up, for AFTER_UP seconds: a longer view distance
## or entity distance makes the bridge send a burst of new chunks and movers first (seen on the
## copied save: 49 UPS for a few seconds, then 60), which isn't load to step down for.
const HOLD_DOWN_AFTER_UP := 8.0
const AFTER_UP := 20.0
const PAUSE_DOWN := 5.0  # seconds between steps down: the mod's cost changes within a few ticks
const PAUSE_DOWN_FAR := 3.0  # and when the game runs at under FAR_BELOW
const FAR_BELOW := 45.0
const HOLD_UP := 30.0
const HOLD_UP_MAX := 240.0  # a step back up that was soon undone waits twice as long next time, to this
const UNDONE := 60.0  # a step down this soon after a step up undoes it
const START_DELAY := 10.0  # seconds after joining before anything is judged (the load's own burst)
const NO_GAIN_WAIT := 15.0  # at the last step: seconds before asking whether the steps helped at all
const NO_GAIN := 2.0  # UPS they must have bought, else the slowness isn't the client's: all back up
const NO_GAIN_RETRY := 300.0  # and nothing is held back for this long

## The work budget (units a tick; one is about an entity painted into a chart, 15-30 µs on the
## owner's save). Shrunk by BUDGET_CUT every BUDGET_EVERY seconds while the 3 s reading is under
## BUDGET_TIGHT, grown back by BUDGET_GROW while the 10 s reading holds HIGH: past the default only
## while work waits in the bridge's queues, up to BUDGET_MAX (about 10-15 ms of work in a tick).
const BUDGET_DEFAULT := 300
const BUDGET_FLOOR := 60
const BUDGET_MAX := 600
const BUDGET_EVERY := 0.5
const BUDGET_TIGHT := 58.5
const BUDGET_CUT := 0.7
const BUDGET_GROW := 1.2

signal budget_changed(units: int)

var enabled := true
## Steps taken (0: the player's settings).
var level := 0
## The UPS measured now over WINDOW and LONG_WINDOW (0 until a window is full or while the ticks
## stall).
var ups := 0.0
var ups_long := 0.0

var _samples: Array = []  # [seconds, tick]
var _clock := 0.0
var _ready_for := 0.0
var _low_for := 0.0
var _high_for := 0.0
var _since_step := 1e9
var _hold_up := HOLD_UP
var _last_up := -1e9
var _ups_before := 0.0  # UPS when the first step was taken
var _no_gain_until := -1e9
var _caps := {}  # knob -> value of the steps taken
## The work budget to keep the bridge at, and what was last sent (-1: send it again).
var budget := BUDGET_DEFAULT
## Work waiting in the bridge's queues (its `wb`), set before each feed.
var queued := 0
var _budget_sent := -1
var _budget_for := 0.0


func _ready() -> void:
	enabled = bool(Settings.get_value("graphics", "hold_ups"))
	Settings.listen(_on_setting)


func _exit_tree() -> void:
	Settings.unlisten(_on_setting)


func _on_setting(section: String, key: String) -> void:
	if section == "graphics" and key == "hold_ups":
		enabled = bool(Settings.get_value("graphics", "hold_ups"))
		if not enabled:
			reset()


## Everything back to the player's settings (a new game, switched off).
func reset() -> void:
	_samples.clear()
	_ready_for = 0.0
	_low_for = 0.0
	_high_for = 0.0
	_hold_up = HOLD_UP
	ups = 0.0
	budget = BUDGET_DEFAULT
	_budget_sent = -1
	if level != 0:
		level = 0
		_caps = {}
		changed.emit()


## The value to use for a knob whose player's setting is `wanted`: no more than the steps taken.
func limit(knob: String, wanted: float) -> float:
	wanted = AddonRequests.lighter(knob, wanted)  # an add-on's lighter updates (a timelapse), under the setting
	if not _caps.has(knob):
		return wanted
	var cap := float(_caps[knob])
	if knob == "map" or knob == "rate":
		return maxf(wanted, cap)  # a refresh multiplier and a slow-down level: held back means larger
	if knob == "fps":
		cap = maxf(cap, float(AddonRequests.fps_floor()))  # an add-on recording needs its frames
		if wanted <= 0.0:
			return cap  # unlimited
	return minf(wanted, cap)


## What is held back now, for the F4 line ("" when nothing is).
func status() -> String:
	var parts: Array = []
	for knob in _caps:
		if absf(limit(knob, _player(knob)) - _player(knob)) < 0.001:
			continue  # a step the player's own setting was already under
		var v := float(_caps[knob])
		parts.append(LABELS[knob] % (str(int(v)) if v == floorf(v) else str(v)))
	return "" if parts.is_empty() else "holding back for UPS: " + ", ".join(parts)


func _process(delta: float) -> void:
	if not Bridge.world_ready:
		if not _samples.is_empty():
			_samples.clear()
			_ready_for = 0.0
		_budget_sent = -1  # a new session starts at the bridge's default: send ours again
		return
	var q = Bridge.work_budget.get("q", {})
	queued = 0
	if q is Dictionary:
		for v in q.values():
			queued += int(v)
	feed(Bridge.server_tick, delta)


## One frame's measurement: the server's latest tick and the frame's seconds. Separate from
## _process so the UI test can drive it with made-up ticks.
func feed(tick: int, delta: float) -> void:
	_clock += delta
	_ready_for += delta
	_since_step += delta
	if _samples.is_empty() or _clock - float(_samples[-1][0]) >= 0.25:
		_samples.append([_clock, tick])
	while _samples.size() > 2 and _clock - float(_samples[1][0]) >= LONG_WINDOW:
		_samples.pop_front()
	ups = _measure(WINDOW)
	ups_long = _measure(LONG_WINDOW)
	_keep_budget(delta)
	if not enabled or _ready_for < START_DELAY or ups <= 0.0:
		_low_for = 0.0
		_high_for = 0.0
		return
	_low_for = _low_for + delta if ups < LOW else 0.0
	_high_for = _high_for + delta if ups_long >= HIGH else 0.0
	if _clock < _no_gain_until:
		# The steps bought nothing: the game is slow for its own reasons. Back to the player's
		# settings, a step at a time, and nothing held back for a while.
		if level > 0 and _since_step >= PAUSE_DOWN:
			_step(-1)
		return
	var hold := HOLD_DOWN_AFTER_UP if _clock - _last_up < AFTER_UP else HOLD_DOWN
	if _low_for >= hold and _since_step >= (PAUSE_DOWN_FAR if ups < FAR_BELOW else PAUSE_DOWN):
		if _next_down() >= 0:
			if level == 0:
				_ups_before = ups
			if _clock - _last_up < UNDONE:
				_hold_up = minf(_hold_up * 2.0, HOLD_UP_MAX)
			_step(1)
		elif _since_step >= NO_GAIN_WAIT and ups < _ups_before + NO_GAIN:
			_no_gain_until = _clock + NO_GAIN_RETRY
			_step(-1)
	elif _high_for >= _hold_up and _since_step >= _hold_up and level > 0:
		_last_up = _clock
		_step(-1)


## Keeps the work budget to the game's room now, so the next request is already paced to it.
func _keep_budget(delta: float) -> void:
	_budget_for += delta
	if _budget_for < BUDGET_EVERY and _budget_sent >= 0:
		return
	_budget_for = 0.0
	var want := budget
	if not enabled:
		want = BUDGET_DEFAULT
	elif ups > 0.0 and ups < BUDGET_TIGHT:
		want = maxi(BUDGET_FLOOR, int(budget * BUDGET_CUT))
	elif ups_long >= HIGH:
		var top := BUDGET_MAX if queued > 0 else BUDGET_DEFAULT
		if budget < top:
			want = mini(top, int(budget * BUDGET_GROW) + 10)
		elif budget > top:
			want = maxi(top, int(budget / BUDGET_GROW))
	budget = want
	if _budget_sent < 0 or absi(budget - _budget_sent) >= maxi(10, _budget_sent / 10):
		_budget_sent = budget
		budget_changed.emit(budget)


## UPS over the last `window` seconds, or 0 while there aren't that many yet or the ticks stalled
## (a save, a pause).
func _measure(window: float) -> float:
	var from := _samples.size() - 1  # the newest sample at least `window` old
	while from > 0 and _clock - float(_samples[from][0]) < window:
		from -= 1
	var first: Array = _samples[from]
	var last: Array = _samples[-1]
	var secs := float(last[0]) - float(first[0])
	if secs < window * 0.9:
		return 0.0
	for i in range(from + 1, _samples.size()):
		if int(_samples[i][1]) <= int(_samples[i - 1][1]) and float(_samples[i][0]) - float(_samples[i - 1][0]) > 0.2:
			return 0.0
	return (int(last[1]) - int(first[1])) / secs


## The next step down that changes anything with the player's settings now, or -1.
func _next_down() -> int:
	for i in range(level, STEPS.size()):
		if _changes_at(i):
			return i
	return -1


static func limit_with(knob: String, now: float, value: float) -> float:
	if knob == "map" or knob == "rate":
		return maxf(now, value)
	if knob == "fps" and now <= 0.0:
		return value
	return minf(now, value)


## The player's own value of a knob.
static func _player(knob: String) -> float:
	match knob:
		"entity": return float(Settings.get_value("graphics", "entity_radius"))
		"far": return float(Settings.get_value("graphics", "belt_distance"))
		"updates": return BeltCaps.cap_wanted(float(Settings.get_value("graphics", "belt_updates")))
		"view": return float(Settings.get_value("graphics", "view_radius"))
		"fps": return float(Settings.get_value("graphics", "fps_cap"))
		"rate": return 0.0
	return 1.0


func _step(dir: int) -> void:
	if dir > 0:
		level = _next_down() + 1
	else:
		# Back to the step before the last one that changed anything.
		var i := level - 1
		while i > 0 and not _changes_at(i):
			i -= 1
		level = maxi(0, i)
	_caps = {}
	for i in level:
		_caps[STEPS[i][0]] = STEPS[i][1]  # each knob's steps go one way, so the last one taken holds
	_since_step = 0.0
	_low_for = 0.0
	_high_for = 0.0
	changed.emit()


## Whether the step at i, given the steps before it, changed anything for the player's settings.
func _changes_at(i: int) -> bool:
	var knob: String = STEPS[i][0]
	var now := _player(knob)
	for j in i:
		if STEPS[j][0] == knob:
			now = limit_with(knob, now, float(STEPS[j][1]))
	return absf(limit_with(knob, now, float(STEPS[i][1])) - now) > 0.001
