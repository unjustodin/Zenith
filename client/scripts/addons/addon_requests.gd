extends RefCounted
## Lighter updates that add-ons ask for (api.updates.request): a timelapse left running for hours
## can ask the bridge to send moving things less often and nearer. They are applied like the
## player's own settings, under them, and the UPS governor (ups_governor.gd) still holds the game
## back further when it runs slow: its limit() starts from what this gives.
##
## Knobs (the governor's names): rate (0-3: the bridge's costliest updates sent less often),
## entity (tiles with moving things and machine states), near (tiles within which belt items may
## move), far (tiles with belt items at all), updates (the most belt items sent moving), view (chunks drawn), map (how much longer the minimap waits).

const KNOBS := ["rate", "entity", "near", "far", "view", "map", "updates"]
## Knobs that are held back by going up (a slow-down level, a refresh multiplier); the others by
## going down.
const UPWARD := ["rate", "map"]

## add-on id -> {knob: value}.
static var requests := {}
## add-on id -> the frame rate it needs kept (api.view.keep_drawing, API 1.1): a recorder filming
## in the background. While any is set the UPS governor's frame rate cap stays at or above the
## highest, and Zenith isn't minimised when it loses focus (a minimised window draws nothing).
static var drawing := {}


## The frame rate add-ons need kept (0: none asks).
static func fps_floor() -> int:
	var out := 0
	for id in drawing:
		out = maxi(out, int(drawing[id]))
	return out


## An add-on is keeping Zenith drawing (it may need fewer frames than 1 a second: still counts).
static func keeps_drawing() -> bool:
	return not drawing.is_empty()


## The value for a knob whose setting is `wanted`, under every add-on's request.
static func lighter(knob: String, wanted: float) -> float:
	for id in requests:
		var r: Dictionary = requests[id]
		if not r.has(knob):
			continue
		var v := float(r[knob])
		wanted = maxf(wanted, v) if knob in UPWARD else minf(wanted, v)
	return wanted


## Sets an add-on's request (knobs it leaves out aren't touched); {} clears it. True when it changed.
static func set_request(id: String, knobs: Dictionary) -> bool:
	var clean := {}
	for k in knobs:
		if str(k) in KNOBS:
			clean[str(k)] = clampf(float(knobs[k]), 0.0, 3.0) if str(k) == "rate" else maxf(float(knobs[k]), 0.0)
	var before: Dictionary = requests.get(id, {})
	if clean.is_empty():
		requests.erase(id)
	else:
		requests[id] = clean
	return before != clean


## What is asked for now, all add-ons together: {knob: value}.
static func combined() -> Dictionary:
	var out := {}
	for id in requests:
		var r: Dictionary = requests[id]
		for k in r:
			var v := float(r[k])
			out[k] = (maxf(float(out[k]), v) if k in UPWARD else minf(float(out[k]), v)) if out.has(k) else v
	return out
