# Writing add-ons for Zenith

> The code isn't published yet: this repository has the documentation only for now. This
> page shows how it will work once Zenith is out.

An add-on is a small program that runs inside Zenith, the 3D view for Factorio, and adds to what
the client does: a camera for filming, an overlay, a window of your own. It is written in
GDScript, Godot's scripting language, and gets one object from Zenith, the add-on API, through
which it reads what the client knows of the game and changes what the client shows.

**Nothing an add-on does changes the game.** The API only reads the client's own copy of the
world and moves the camera, the interface and what is drawn. Everyone else in the game sees
nothing of it, and Factorio's simulation is untouched.

The [Cinematic camera](https://github.com/unjustodin/Zenith-Cinematic-Camera) add-on (free
camera, timelapses, tracking shots, paths, idle mode) is the worked example: everything below is
what it uses.

## Installing an add-on

An add-on is a folder with an `addon.json` in it. Put the folder in one of these places:

| Where | For |
|---|---|
| `%APPDATA%\Godot\app_userdata\Zenith\addons\` (Windows), `~/.local/share/godot/app_userdata/Zenith/addons/` (Linux) | Your own add-ons, kept across Zenith updates |
| `addons\` beside `Zenith.exe` | Add-ons that come with a copy of Zenith |
| `--addons=<folder>` on the command line | Development: an add-on's own folder, or a folder of add-ons (several, separated by commas) |

Zenith looks for add-ons when it starts. The main menu's **Mods** window lists them under *Zenith
add-ons*, with a switch for each (it applies at once, in a game too), the version, an **Options**
button when the add-on has options, and the reason when one couldn't load. An add-on given with
`--addons` is always on, and takes the place of an installed one with the same id.

An add-on's keys are in **Settings → Controls**, under the add-on's name, and are rebound there
like Zenith's own.

## The folder

```
my-addon/
  addon.json
  main.gd          the entry script
  scripts/...      anything else it needs
```

`addon.json`:

```json
{
	"id": "my-addon",
	"name": "My add-on",
	"version": "1.0.0",
	"api": 1,
	"entry": "main.gd",
	"author": "you",
	"description": "One line for the Mods window."
}
```

| Field | |
|---|---|
| `id` | Lower case letters, digits, `-` and `_`. Names the add-on's keys, data folder and node |
| `name`, `version`, `description`, `author` | Shown in the Mods window and Settings → Controls |
| `api` | The add-on API version it was written for. Zenith refuses an add-on that needs a newer API than it has, and says so in the Mods window: update Zenith |
| `entry` | The entry script, a `.gd` file in the folder |

This page describes add-on API **1**.

## The entry script

The entry script extends `Node`. Zenith adds it to the scene when the add-on starts and calls
`addon_start(api)`; when the player switches the add-on off it calls `addon_stop()` (if there is
one) and frees the node. Everything set up through the API (the camera, keys, windows, requests)
is undone by Zenith then, so `addon_stop` only needs to save the add-on's own state.

```gdscript
extends Node

var api

func addon_start(a) -> void:
	api = a
	api.keys.add("hello", "Say hello", [KEY_F10])

func _unhandled_input(event: InputEvent) -> void:
	if api.keys.pressed(event, "hello"):
		var me: Dictionary = api.world.character()
		api.ui.message("Hello from %s" % str(me.get("position", "the menu")))
```

The node gets `_process`, `_input` and `_unhandled_input` as any node does, and gets input before
Zenith's own controls and menus. Add-ons start at Zenith's start-up, before any game: listen to
`api.game_started` and `api.game_ended`, and check `api.in_game()`.

A few GDScript notes:

- Don't use `class_name`: scripts loaded from outside Zenith's own project can't rely on Godot's
  global class list. Load your other scripts with a path relative to the script doing it
  (`const Orbit := preload("scripts/orbit.gd")`) or with `api.load_script("scripts/orbit.gd")`.
- Zenith's own scripts can be preloaded by their `res://` paths, but only the API below is
  promised to stay the same within an API version.
- Don't infer a type from a Variant (`var x := api.world.trains()` is an error): write the type
  (`var x: Array = ...`) or leave it out (`var x = ...`).

## The API

`api` has these parts. Positions are Godot's: `x` east and `z` south, in tiles, `y` up; Factorio's
`(x, y)` is `(x, z)` here and the ground is at `y = 0`.

| | |
|---|---|
| `api.version` | The add-on API this Zenith offers (1) |
| `api.zenith_version` | Zenith's version, for messages |
| `api.id`, `api.name`, `api.addon_version`, `api.dir` | From your `addon.json`, and the add-on's folder |
| `api.in_game()` | A game is on |
| `api.game_started`, `api.game_ended` | Signals |
| `api.note(text)` | A line in Zenith's log, marked with the add-on's id |
| `api.load_script(path)` | One of the add-on's own scripts, by its path in its folder |

### Camera: `api.camera`

One add-on has the camera at a time. While it does, the player's own view (the angled view,
Factorio's view, first person, the zoom) is kept as it was, and comes back exactly so.

| | |
|---|---|
| `take(options = {})` | Takes the camera; false when it can't now (no game, another add-on has it, a ride to a space platform, VR). Options: `"input"` (default `true`: the player's controls are off and the character stops; your `"camera"` keys work), `"focus"` (`"camera"`, the default: the world loads round the ground in the middle of the picture; `"character"`: round the character) |
| `release()` | Back to the player's view |
| `has()`, `has_input()` | Whether this add-on has it, and the player's controls are off |
| `node()` | The `Camera3D` itself while you have it (else null): set its `global_transform`, `fov`, `projection`, `size`, `near`, `far`, `attributes` (depth of field). All of it is put back on release |
| `set_transform(t)`, `look_from(eye, at)` | Where it is and where it looks |
| `transform()`, `fov()` | The camera now (also while the player has it: where to start a shot from) |
| `player_view()`, `player_fov()`, `player_orthographic()` | Where the player's own view would put the camera now: glide there before `release()` for a seamless hand-back |
| `set_focus(point)` | Where the world loads and live data is asked for (a `Vector2` in tiles), or `null` for take()'s choice |
| `focus()` | The point the world is loaded round now |
| `capture_mouse(on)`, `mouse_captured()` | The mouse hidden and captured (its motion arrives as `InputEventMouseMotion.relative`, for mouse look) while you have the camera; Zenith gives it back while a window or menu is open |
| `ground_point(screen_pos)`, `center_ground()` | The ground under a point of the screen, or its middle (`null` above the horizon) |
| `lost` | Signal: Zenith took the camera back (a ride to a platform started, the game ended) |

The world is only loaded and sent round one point. A camera far from the character makes Zenith
load the world there (the bridge sends what is near the focus), so flying far is fine; but
anything you read through `api.world` is what is near the focus.

### Keys: `api.keys`

| | |
|---|---|
| `add(name, label, keys = [], context = "global")` | A control in Settings → Controls under your add-on's name. `keys`: up to two defaults, as key codes with modifier masks (`KEY_F8 \| KEY_MASK_SHIFT`) or names (`"Shift+F8"`). Returns the input action's name |
| `pressed(event, name)`, `released(event, name)` | The event pressed or let go of the control |
| `held(name)` | It is held down now |
| `text(name)` | Its keys for hints: `"F8"`, `"W / Up"` |
| `conflicts(name)` | Other controls sharing one of its keys where both work |
| `action_of(name)` | Its input action, for `Input` |

Where a control works (`context`):

- `"global"`: always in a game. Its defaults mustn't be any of Zenith's keys or another add-on's
  global keys: a default that is already taken is left unbound (the log says so), so an add-on
  can't take a key from the player. They can still bind it in Settings → Controls (it shows red).
- `"camera"`: only while your add-on has the camera with the player's controls off. These may
  share keys with Zenith's controls (WASD to fly), and Zenith doesn't see those keys meanwhile
  (E flies up instead of opening the inventory).

Neither works while the player types in a text box or Zenith's menu is open. A control is
pressed when its modifiers are held; more modifiers held only count against it when another of
your controls has exactly those (so Shift+= still counts as `=`, but Shift+F8 isn't F8 when
Shift+F8 is a control of its own).

### The world, read-only: `api.world`

What the client knows of the game: buildings in the chunks drawn round the focus, moving things
and trains within the entity distance of it (Settings → Graphics), the players. Every function
returns copies.

| | |
|---|---|
| `character()` | The client's own character: `{unit, position, forward, vehicle, visible}` (`{}` outside a game) |
| `movers(types = [])` | Moving things of these prototype types (all when empty): `[{unit, type, name, position, forward}]`. Types: `locomotive`, `cargo-wagon`, `fluid-wagon`, `artillery-wagon`, `car`, `spider-vehicle`, `character` (other players), `logistic-robot`, `construction-robot`, `combat-robot`, `unit` (biters, spitters), `spider-unit`, `rocket-silo-rocket`, `cargo-pod` |
| `mover(unit)` | One of them, or `{}` when it's gone or too far |
| `trains()` | `[{id, state, manual, speed (tiles a tick, negative backwards), station (the stop's unit, 0 none), destination, carriages (units, front first)}]` |
| `train_of(unit)` | The train a carriage belongs to |
| `players()` | `[{index, name, connected, color, unit, surface, me}]` |
| `rockets()` | Rockets climbing from their silos now, as drawn: `[Vector3]` |
| `chunks()` | The chunks drawn now (`Vector2i`, 32 tiles each) |
| `entities_in_chunk(chunk, types = [])` | Its buildings, trees, rocks...: `[{unit, name, type, position (Vector2), direction (0-15), working (true, false, or null)}]` |
| `entities_near(point, radius, types = [])` | The same round a ground point |
| `focus()` | The point the world is loaded round |
| `daytime()`, `darkness()` | The time of day as drawn (0 noon, 0.5 midnight) and how dark it is (0 to 0.85) |
| `planet()`, `on_platform()` | The planet shown, and whether it's a space platform |

A chunk can hold thousands of entities: spread big searches over several frames.

### Events: `api.events`

Worked out by the client from what the bridge already sends; nothing extra is asked of the game.

| Signal | |
|---|---|
| `train_departed(train_id, stop_unit, position)`, `train_arrived(...)` | A train near the focus left a stop or arrived at one |
| `rocket_launched(silo_unit, position)` | A launch was ordered on the surface shown (it lifts off a few seconds later) |
| `fight_started(position, size)`, `fight_ended(position)` | Enemies started attacking, or turrets firing, where nothing had for 10 s; the fight ended after 10 s of quiet |
| `platform_departed(platform, location)`, `platform_arrived(platform, location)` | A space platform left a planet or arrived at one |
| `player_joined(name)`, `player_left(name)` | |

`recent(seconds = 60)` lists the last events, newest first, each `{kind, time, age, position, ...}`
with the signal's values by name; `fights()` the fights going on, `[{position, since, size}]`.

### What is shown: `api.view`

| | |
|---|---|
| `hide_interface(on)`, `interface_hidden()` | Zenith's interface and the cursor hidden for a clean shot. Your windows hide too; your overlay layer stays |
| `save_frame(path, viewport = null)` | The window (or a viewport of yours) saved as a PNG, written on a worker thread so a frame every few seconds costs the game little. `path`: `user://...` or a full path; folders are made |
| `frames_pending()` | Frames still being written |
| `world_3d()` | The 3D world, for a `SubViewport` and `Camera3D` of your own (a second shot drawn off screen) |
| `hold_daytime(t)`, `daytime_held()` | The time of day as drawn held still (0 noon, 0.25 dusk, 0.5 midnight); negative lets it run. The game's own time runs on |
| `screen_size()` | |

### Windows and messages: `api.ui`

Windows look like the rest of Zenith (Factorio's frames, title bars, buttons, sliders, from the
player's own install). Their title bar drags them; the × and Esc close them.

| | |
|---|---|
| `window(title)` | A new window, hidden: `{frame, box, close}`. Put its content in `box` |
| `show(frame, on = true)`, `toggle(frame)`, `is_open(frame)` | |
| `layer()` | A `CanvasLayer` of your own over the world (letterbox bars, a recording mark); it stays when the interface hides |
| `message(text)` | A message over the quickbar, as Zenith's own |
| `typing()`, `menu_open()`, `windows_open()` | The player is typing; Zenith's menu is open; a window is open |
| `set_options(builder)` | Your options in the Mods window: `builder` is called with an empty `VBoxContainer` |
| `label`, `heading`, `note`, `button`, `checkbox`, `slider`, `dropdown`, `textbox`, `row` | Controls in Zenith's style (see `client/scripts/addons/addon_ui.gd`) |
| `kit`, `menu_kit` | Zenith's UI kits, for anything else |

### Lighter updates: `api.updates`

While something long runs (a timelapse left for hours), an add-on can ask the bridge to send less,
so the game keeps its speed. The request lowers the player's own settings while it stands; Zenith's
*Hold the game at 60 UPS* still lowers them further when the game runs slow, and wins where both
ask.

| | |
|---|---|
| `request(knobs)` | `rate` (0-3: moving things, belt items, machine states sent less often), `entity` (tiles with moving things), `near` (tiles with every item on belts, at least 8), `far` (tiles with far belt icons), `view` (chunks drawn), `map` (how many times longer the minimap waits). Leave out what you don't need |
| `clear()`, `current()` | |
| `governor_status()` | What *Hold the game at 60 UPS* holds back now |

### Data: `api.storage`

JSON files in Zenith's user data: one set per save, and one for every save.

| | |
|---|---|
| `read(name = "data")`, `write(data, name = "data")` | The current save's data (`{}` before any). Under `user://addons-data/<id>/saves/<save>/<name>.json` |
| `read_global(name = "settings")`, `write_global(data, ...)` | For every save: `user://addons-data/<id>/<name>.json` |
| `save_key()` | The save's name for a game started from Zenith's menu, else the bridge's address |
| `folder()` | Your data folder (for files of your own, such as saved frames) |

Values are plain JSON: numbers (they come back as floats), strings, booleans, arrays and
dictionaries. Store a `Vector3` as `[x, y, z]`.

## Good manners

- Leave the camera, the keys and the mouse alone unless the player asked (a key, a button).
- Work in small steps: `_process` runs every frame, and anything slow there is a stutter.
- Say what your keys are (`api.keys.text`) rather than naming them in your text: the player may
  have rebound them.
- Keep your add-on's own files inside its folder and its data in `api.storage`.

## Testing

Run Zenith from its project with your add-on's folder:

```
godot --path client -- --addons=C:/my-addon
```

Zenith's log (the console it was started from) says which add-ons started, which were refused
and why, and the add-on's own `api.note` lines. Script errors show there too, with the line. The
project's own add-on test (`client/tests/addon_test.tscn`) loads a small add-on from
`client/tests/addon_fixtures/` and is a compact example of each part of the API.
