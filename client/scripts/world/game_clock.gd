extends RefCounted
## The game's tick as the client draws moving things: it runs on between messages at the rate the
## game's ticks actually arrive, not a fixed 60 a second. A busy save runs the server below 60 UPS
## (and /c game.speed changes it either way); at a fixed 60 the drawn clock ran ahead of the
## messages, waited at its limit for the next one and lurched on, so robots and biters stopped and
## jumped. The rate is measured over half a second of arrivals, so a message's own jitter (frames,
## the UDP thread) doesn't move it.

## How many sends behind the newest message things are drawn, so there are positions either side.
const DELAY_SENDS := 2.0
const RATE_WINDOW := 0.5  # seconds of arrivals per rate measurement
const RATE_MIN := 6.0
const RATE_MAX := 600.0
## The longest gap a message's `p` may set (the mod's slowest movers are 16 ticks apart).
const GAP_MAX := 120.0

## The clock in ticks, running on with real time; -1 before the first message.
var tick := -1.0
## The newest message's tick, and the usual ticks between messages.
var newest := -1.0
var gap := 2.0
## Game ticks per real second, as measured.
var rate := 60.0

var _anchor_k := -1.0
var _anchor_t := 0.0
var _now := 0.0  # seconds of frames (advance), when messages arrive: they're handed over once a frame
var _newest_t := 0.0
var _measured := false
var _gap_goal := -1.0  # the gap the messages' `p` asks for, or -1 when it is measured
## How fast a longer gap is taken up, in ticks of gap per game tick: what is drawn `behind` gaps
## behind slows to 1 - behind * ease of its speed meanwhile (movers: 2 gaps behind, half speed).
var ease := 0.25


## A message stamped with game tick `k` arrived (this frame). `period`, when the message says (`p`):
## the ticks until the next one, which the mod stretches while it is slowed down (`rate`). The gap
## then eases to it (advance) instead of being learnt over a dozen messages, during which things
## would reach their newest position and stop.
func heard(k: float, period := 0.0) -> void:
	var now := _now
	if k <= newest and tick >= 0.0:
		return
	if period > 0.0:
		_gap_goal = clampf(period, 1.0, GAP_MAX)
	elif newest >= 0.0 and k - newest <= 60.0:
		gap = lerpf(gap, clampf(k - newest, 1.0, 30.0), 0.2)
		_gap_goal = -1.0
	newest = k
	_newest_t = now
	if tick < 0.0 or absf(tick - k) > maxf(60.0, gap * 4.0):
		tick = k  # the first message, or the game jumped (a save loaded, a long pause)
		if _gap_goal > 0.0:
			gap = _gap_goal
		_anchor_k = k
		_anchor_t = now
		return
	var span := now - _anchor_t
	if span > 2.0:
		_anchor_k = k  # paused or stalled: don't count the wait as a slow game
		_anchor_t = now
	elif span >= RATE_WINDOW:
		var measured := (k - _anchor_k) / span
		# The first measurement is taken as it is; after that they're smoothed.
		rate = clampf(measured if not _measured else lerpf(rate, measured, 0.3), RATE_MIN, RATE_MAX)
		_measured = true
		_anchor_k = k
		_anchor_t = now


## The gap the clock's `gap` eases to (advance): what the messages' `p` asks for, else the gap itself.
func gap_goal() -> float:
	return _gap_goal if _gap_goal > 0.0 else gap


## Moves the clock on by `delta` seconds and returns the tick to draw (DELAY_SENDS sends behind).
func advance(delta: float) -> float:
	_now += delta
	if tick < 0.0:
		return -1.0
	if _gap_goal > 0.0 and gap != _gap_goal:
		# A longer gap draws further behind: eased in, so what is drawn slows down meanwhile and
		# never stops or runs backwards (the mod keeps its old rate a while: rate.lua). A shorter
		# one is taken up as fast as the game runs.
		var up := _gap_goal > gap
		gap = move_toward(gap, _gap_goal, delta * rate * (ease if up else 1.0))
	# Steered gently towards where the game is now (the newest message, run on at the measured
	# rate), so a rate a little off doesn't pile the clock up against its limit and step it.
	var expected := newest + (_now - _newest_t) * rate
	tick += delta * rate + (expected - tick) * minf(1.0, delta * 2.0)
	# Never far past the newest message (a paused or stalled game).
	tick = minf(tick, newest + gap * DELAY_SENDS)
	return tick - gap * DELAY_SENDS
