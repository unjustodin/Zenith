# Zenith: player's guide

Zenith lets you play Factorio in 3D, with an angled camera close to your character. Factorio itself still runs the game: a small mod (the **bridge**) streams the world to
the **Zenith client**, a separate program that draws it in 3D and sends your keys and clicks
back. Everything stays on your computer.

This guide is for playing. [RUNNING.md](RUNNING.md) has every detail (all controls, settings and
command-line options); [ARCHITECTURE.md](../ARCHITECTURE.md) is for people working on it.

## What you need

- **Factorio 2.1** (Space Age is optional). Your own copy: the client reads Factorio's graphics,
  sounds, fonts and names from your install and never copies them.
- **Zenith itself:** the download (`Zenith-<version>-windows.zip`, or `-linux`), or this
  repository with [Godot 4.4 or newer](https://godotengine.org/download).
- Windows or Linux. The client and Factorio must run on the same computer.

## Installing

**From the download** (the easy way):

1. Unpack the zip anywhere you can write to (your Documents, say): it is one folder with
   `Zenith.exe` (on Linux `Zenith.x86_64`), the bridge mod in `mod/` and the server scripts in
   `server/`. Your servers' data and saves go in `server/data` and `server/saves` there.
2. Start `Zenith.exe`. That's all: when you start a game from its menu, it runs Factorio in the
   background with the bridge mod and connects by itself. If it can't find Factorio, set
   Factorio's folder in Settings → Factorio install. (The Linux download hasn't been tried yet.)

**From the repository** (to change it, or on a system the download doesn't cover):

1. Start the client once with `godot --headless --path client --import` so Godot imports the
   models, then `godot --path client`. `python3 tools/release/package.py` builds the download.
2. The menu uses the mod in `mod/` the same way.

**Playing in your own Factorio window** (single-player "hybrid" mode, or joining someone's
server) needs the bridge mod in Factorio's own `mods` folder: get *Zenith Bridge* from the mod
portal (Factorio: Mods → Install), or put `factorio-3d-bridge_<version>.zip` there (built with
`python3 tools/release/build_mod_zip.py`). Factorio must also open its UDP port for the bridge:
add `--enable-lua-udp 34200` to its command line (Steam: Properties → Launch options). Without it
the mod does nothing. Hybrid mode works (it has been played side by side with Factorio's
window), but it is new and hasn't been tried much.

## First game

Start the client. Its main menu works like Factorio's:

- **Single player → New game** makes a map with Factorio's map generator and starts it (a
  headless Factorio runs in the background; the client connects by itself).
- **Single player → Load game** continues one of your saves. Your original save is copied first,
  never changed.
- **Multiplayer → Host new game** (or **Host saved game**) starts a server friends can join with
  normal Factorio, while you play in 3D.
- **Multiplayer → Connect to address** joins a bridge that is already running, for example
  `127.0.0.1:34200`.

Leaving a game asks whether to save; the server the client started stops with it, even if the
client crashes.

The first time, Settings → Factorio install lets you point the client at your Factorio install if
it wasn't found (Steam installs usually are).

## Playing

Factorio's keys work as in Factorio: WASD walks, the right mouse button mines, E opens your
inventory or the building under the mouse, the left mouse builds what you hold, R rotates, Q
picks up the item under the mouse (pipette), T is the technology screen, M the map, 1–0 the
quickbar, Enter gets in and out of vehicles, Esc closes windows or opens the game menu. The game
starts in the angled view, and the camera is yours to move:

| Input | Camera |
|---|---|
| Mouse wheel | Zoom |
| Middle mouse drag | Turn around the character and tilt |
| , and . | Turn 90° |
| Page Up / Page Down | Tilt |
| F6 | Factorio's own view from above, and back |
| F5 | First person, and back |
| F7 | Perspective or orthographic, for the view you're in (the map's remote view or the normal one) |

Hovering a building shows Factorio's entity info on the right: its status, recipe, modules and
beacons, and for powered buildings "Consumes electricity" with the Electricity bar; hovering a
roboport draws lines to the roboports it is linked to. On a space platform (and in the map view of
one) Factorio's platform panel under the minimap says where it is stopped or what it is travelling
between, its speed and mass, and on board has **Drop to a planet**.

Settings → Controls lists and rebinds everything. F1 shows the help, F4 a status line (the
game's UPS beside the frame rate, and what Hold the game at 60 UPS holds back). Ctrl+F9
opens the same game in Factorio itself, and Ctrl+F9 there comes back (not yet tried with a real
Factorio window).

## Settings worth knowing

- **Graphics → View distance** (chunks drawn around you) and **Entity distance** (how far moving
  things and machine states are streamed). Lower them if the game stutters.
- **Graphics → Level of detail**: how soon far-away models are drawn simpler.
- **Graphics → Merge far buildings** (on): past about four chunks from the camera (and away from
  your character), each chunk's buildings are drawn as one simplified mesh with no moving parts,
  which costs far fewer draws when the camera is pulled back over a big base. Trees, ore and nests
  keep their own models. Off draws every building in full however far it is.
- **Graphics → Preset** (Low, Medium, High, Ultra) sets shadows, ambient occlusion, level of detail,
  the distances and clouds together; **Shadows** alone (Off to Ultra) sets how far and how sharp
  the sun's shadows are.
- **Graphics → Merged materials (may help when CPU-bound)** (off): each model is drawn as one
  surface with one material instead of one per material, so the renderer has far fewer draws to
  send, at the cost of a little more GPU time. Try it if your graphics card idles while the frame
  rate is low. Takes effect after a restart. Recommended turns it on for a big desktop graphics card
  when the game measures the CPU holding the frames up.
- **Graphics → Recommended**: picks the preset this PC holds at a steady 60 UPS and 60 FPS (from its
  CPU and graphics card), with Hold the game at 60 UPS and Smooth belt items on, and Merged
  materials as above. Pressed in a game,
  it measures for six seconds first and goes a preset lower if the game or the frames fall short.
- **Graphics → Smooth belt items** (on): items on belts update five times a second and follow the
  curves. Off, the server reads them a little each tick on a busy base and they update less often
  (on my own save it made no measurable difference to UPS).
- **Graphics → Hold the game at 60 UPS** (on): when the game runs slow on a big base, the client
  asks the bridge for less for a while (shorter distances, fewer minimap refreshes, then a lower
  frame rate) and gives it back when the game recovers. Your settings stay as they are; F4 shows
  what is held back.
- **Graphics → Items on belts**: 3D models or Factorio's icons. **Belt items in full** and **Belt
  items far away** set how far they are drawn.
- **Camera → View when a game starts** (Angled view, Factorio's view or First person) and
  **Projection** (the angled view in perspective or orthographic), **Projection on the map** (the
  remote view you zoom into from the map; F7 switches whichever view you're in) and **Furthest
  zoom** (how far the wheel zooms out, 60 to 400 tiles; 140 by default).
- **Interface → UI scale**, and Ctrl+= / Ctrl+- / Ctrl+0 while playing.
- **The bridge's own settings** are in Factorio's Mod settings (Map tab), or Settings → Mod
  settings in a game the menu started: how much it sends per tick, how far moving things are
  streamed, which player the client plays as on a server.

## Add-ons

Add-ons add to what Zenith does, for example a cinematic camera for filming your base. One is a
folder or a .zip of it (no need to unpack it): put it in Zenith's add-ons folder, `%APPDATA%\Godot\app_userdata\Zenith\addons\` on
Windows (or an `addons` folder beside `Zenith.exe`), and start Zenith. The **Add-ons** menu (on
the main menu, in the game menu that Esc opens, and at the bottom of Settings) lists every add-on
found with its version, whether it's on, and why it couldn't load (for example one that needs a
newer Zenith). Click one for its page: its switch, its settings (changed there at once, in a game
too, and kept for next time) and its keys, rebound as in Settings → Controls (click, press the
key; right click clears). With two copies of one add-on (a folder and a zip, say), the newer
version is used and its page says so. The Mods window lists them as well. Add-ons can move the camera and
change what is shown, never the game itself. Writing one: [ADDONS.md](ADDONS.md).

An add-on that records in the background (the Cinematic camera's recorder) keeps Zenith drawing
while its window is behind Factorio's: Zenith isn't minimised when it loses focus while it
records. Don't minimise Zenith yourself while recording: a minimised window draws nothing, so
nothing is recorded meanwhile.

## Several players

- **With friends in normal Factorio**: host a multiplayer game from the client's menu; they join
  the server with Factorio as usual and see your character.
- **Several 3D players**: on a server (headless or hosted), more 3D clients on the same computer
  connect to the same bridge. Each gets its own character; they see each other walking around.
- **Single-player (hybrid)**: start Factorio normally with `--enable-lua-udp 34200` and connect
  the client (Single player → Single-player (hybrid) → Connect). It plays your own character; both
  windows show the same game. This mode is new (played once so far): if it doesn't work, use
  Single player → New game or Load game instead.

## When something goes wrong

| Problem | What to try |
|---|---|
| "Waiting for Factorio on 127.0.0.1:34200" | Is Factorio running with `--enable-lua-udp 34200`, and the bridge mod enabled? In Factorio's console, `/f3d-status` says whether a client is connected |
| A game from the menu doesn't start | The message shows the lines of Factorio's log that matter. Check Settings → Factorio install, and that no other Factorio uses the same server data folder |
| "Can't open UDP port 34201" | Other programs have it and 34202–34208, which the client tries by itself. Close other clients |
| No item icons, flat-coloured ground, no sound | The client didn't find your Factorio install: set it in Settings → Factorio install |
| The game stutters on a big base | Try Settings → Graphics → Recommended, or a lower Preset; keep Hold the game at 60 UPS on; lower View distance, Entity distance and Belt items in full |
| Something else | `/f3d-selftest` in Factorio's console checks the bridge in your game; RUNNING.md's Troubleshooting section has more |

Zenith is a fan project, not made or endorsed by Wube Software. Factorio is theirs.
