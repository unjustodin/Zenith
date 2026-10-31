# Running Zenith

Three pieces run on the same computer:

1. **Factorio**, usually headless with no window, runs the actual game.
2. The **factorio-3d-bridge** mod (`mod/`) inside it streams the world over localhost UDP and
   moves a character on the client's behalf.
3. The **Godot client** (`client/`) draws the world in 3D and sends your input back.

You need Godot 4.4 or newer and Factorio 2.1 (the mod is marked for 2.1, and 2.1 won't load 2.0 mods). Python 3.9+ is only needed for the
mock server and the tests.

## Start here: the client's menu

Start the client (`godot --path client`, or F5 in the editor). Like Factorio, it opens on a main
menu over a live 3D scene (a recorded corner of the mock's factory, `client/data/menu_world.json`,
made by `tools/record_menu_world.py`):

- **Continue** loads the server save played last.
- **Single player**:
  - **New game** opens Factorio's map generator: name, preset (all nine of
    `base/prototypes/map-gen-presets.lua`), seed, and the tabs **Resources** (frequency, size and
    richness of every resource, with the planet it appears on: Nauvis and, with Space Age on, Vulcanus,
    Gleba, Fulgora, Aquilo), **Terrain** (map type normal / lakes / island, starting area, water,
    trees, rocks and the planets' terrain controls as scale and coverage, cliffs' frequency and
    continuity, Nauvis moisture and terrain type), **Enemy** (bases, peaceful mode, no enemies,
    expansion, evolution) and **Advanced** (map size, pollution, technology price, spoiling rate,
    asteroids, or a map exchange string instead of all of it). "[modified]" and Reset show and undo
    changes from the preset. **Preview** asks Factorio itself (`--generate-map-preview`) for the
    picked planet, about 15 s. Play writes `map-presets/create-gen.json` and `create-map.json` in
    the server's data folder and runs `factorio.exe --create` with them, so every option shapes the
    real map. The last choices are remembered.
  - **Load game**: the server's saves (`server/saves/*.zip`) and your own Factorio saves
    (`%APPDATA%\Factorio\saves`, with their preview picture; loading one copies it into
    `server/saves` first, the original is never touched), with the date last played and size.
    **Load** (or double-click) starts headless Factorio on the save and connects to it; **Delete**
    moves a server save to the recycle bin (after asking).
  - **Single-player (hybrid)**: how to set up your own game, and a Connect button. Hybrid mode is
    new: it has been played once (see below).
- **Multiplayer**:
  - **Host new game** / **Host saved game**: name, description, port (34197), password, player limit
    and LAN visibility, then the map generator or a save. The server is bound to every network
    address on that port, so friends join with normal Factorio (Connect to address); the 3D client
    plays as the bridge's character. RCON and the bridge stay on 127.0.0.1.
  - **Connect to address**: `host:port` of a bridge that is already running (a server started by
    hand, `server/run-server.ps1`, or the mock: `127.0.0.1:34200`). Joining a normal Factorio
    server isn't possible: the bridge only talks to a client on the same computer.
- **Settings**: as in Factorio, a list of pages (Graphics, Controls, Sounds, Interface, Other, Mod settings, then ours: Camera, Factorio install), each opening alone with Back and Confirm; every option is wired to what it changes:
  - **Graphics**: a **Preset** (Low, Medium, High, Ultra, or Custom once anything differs; it sets
    shadows, SSAO, level of detail, the view, entity, belt and decorative distances, decorative
    density and clouds together; High is the defaults) and **For this PC** (Recommended: the preset
    this PC should hold at a steady 60 UPS and 60 FPS, from its CPU threads and graphics card; in a
    game it measures six seconds first; it also turns on the two belt and UPS options below); full
    screen (windowed, borderless, exclusive), resolution, preferred screen, minimize on focus loss,
    VSync, FPS limit, game render scaling (50% to 200%), view distance (2 to 20 chunks round the
    camera, default 10), entity distance (32 to 256 tiles, default 192; the server's "Max
    live-update radius" caps it), belt items in full (8 to 96 tiles, default 24), belt items far
    away (one icon per lane, 0 off to 640 tiles, default 160), smooth belt items (on: belt items
    read in one tick every update, so they follow curves; off: read a little each tick, lighter
    for a busy server), hold the game at 60 UPS (on; see Troubleshooting), smoke and particles,
    items on belts (3D models or icons), clouds, decoratives, decorative density and distance (64
    to 320 tiles, default 192), item icons, model look (each part in Factorio's colours, or
    Factorio's sprite projected on). **Advanced:** anti-aliasing (FXAA, TAA, MSAA), shadows (off,
    low, medium, high, ultra: the sun's shadow map is fitted to the ground in view, one map from
    the angled view and Godot's splits when the view reaches the horizon; Low one 2048 map out to
    80 tiles, Medium 4096 to 110, High 4096 to 150, Ultra 8192 to 200,
    `scripts/world/sun_shadows.gd`), level of detail (low, medium, high: how soon far models and
    their shadows are drawn simpler: 4, 4 and 1 pixels of error), merge far buildings (on: past
    128 tiles from the camera, or the shadow distance if further, and 40 tiles from the character,
    each chunk's buildings are one simplified mesh with no moving parts; trees, ore and nests keep
    their own; `scripts/world/far_chunks.gd`),
    merged materials (off: each model drawn as one surface with one material, fewer draws and
    less render CPU for a little more GPU time; after a restart; `-- --merged-materials` or
    `--no-merged-materials` override it; Recommended turns it on for a big desktop GPU whose frames
    the CPU holds up, the presets leave it), SSAO, render on a separate thread (off: Godot's experimental mode, after a restart).
    **Accessibility:** brightness, contrast, saturation and Factorio's colour filters
    (protanopia, deuteranopia, tritanopia and their corrections, over the whole window).
  - **Sound**: master, game effects and its parts (walking, environment = machines and vehicles,
    weapons, explosions, enemies), music and GUI effects, each with a mute box; preferred output
    device; machine sounds at once.
  - **Controls**: Factorio's groups and names, a primary and an alternative binding per control, with
    Shift / Ctrl / Alt; right click clears, clashing bindings are red; mouse and fixed keys are
    listed greyed. `client/scripts/menu/controls_info.gd` says where an action goes.
  - **Interface**: under Factorio's headings: show minimap, control hints (F1; the help panel is off
    by default and hides while a window is open), fade tall entities in the way (the shortcut bar's
    tall-entities toggle), Alt-mode, smart belt building, lock belt building to a straight line, UI scale, tooltip delay, the entity tooltip,
    chat message delay; then the client's own: shortcut bar, research, alerts, debug line (F4), the
    minimap's size, zoom and tags, and the map view's switches.
  - **Other**: the server's autosave interval and slots and verbose logging (written into the
    `server-settings.json` the menu puts in the server's data folder; from the next start).
  - **Mod settings**: the bridge mod's map settings, changed over RCON in a game started from the menu.
  - **Camera**: the view a game starts in (Angled view, Factorio's view or First person), the
    angled view's projection (Perspective or Orthographic; Factorio's view, F6, is always
    orthographic), the map's remote view's projection (F7 switches the view in use and keeps it),
    the furthest zoom (60-400 tiles, 140 by default), mouse sensitivity, invert mouse look.
  - **Factorio install**: path to `factorio.exe` (or its folder; empty finds it), the server's
    data and saves folders, the first port servers use.
- **Mods**: base, the DLC and the mods in the server's mods folder, with versions and on/off boxes,
  written to the server's `mods/mod-list.json` (Space Age brings Quality and Elevated rails along;
  the bridge is always on). The map generator leaves Space Age's planets out while it is off.
- **About**: versions, licences and Factorio's own credits from your install.
- **Exit**.

Every setting is in one file, `user://settings.cfg`
(`%APPDATA%\Godot\app_userdata\Zenith\settings.cfg`; sections graphics, sound, interface, map,
controls, camera, factorio, alerts, new_game). The older `ui.cfg` and `audio.cfg` are read into it
once and then left alone. Settings from the project's old name (`app_userdata\Factorio 3D`) are
copied over once. Most settings apply
at once, the UI scale too (Settings → Interface, or Factorio's keys Ctrl+= / Ctrl+- / Ctrl+0 in
the game and the menus; "Automatic" follows the window's height as it's resized). The UI is built
at the scale it started with and scaled from there, so after a big change text is a little softer
until the next start. The model look applies after a restart (`-- --model-look=colours|sprite|palette`
overrides it). `-- --settings-file=user://other.cfg`
uses another file (tests and screenshots).

Starting a save runs Factorio exactly as `server/run-server.ps1` does (same `server/data` write-data
folder, mod junction, `--enable-lua-udp`, RCON on 127.0.0.1 with the password in
`server/data/rcon-password.txt`), but on free ports from 34500 up (Settings → Factorio install; UDP, game port, RCON, then the
client's own port), so servers started by hand keep theirs. A progress window shows Creating map →
Starting server → Loading map → Connecting → Loading world; Cancel stops it. Errors (Factorio not
found, map creation failed, the server stopping, no free ports, another Factorio using
`server/data`) come up as a message with the relevant lines of `server/data/factorio-current.log`.

In the game, **Esc** (with no window open) opens Factorio's "Game menu": Resume, **Load game** (asks to save, then the saves), **Save game** (RCON
`/server-save`), **Save as** (a name or an existing save to overwrite: `/server-save <name>` writes
it in the data folder's `saves`, then it is copied into the saves folder; the game goes on in its
own save, as on a Factorio server), Settings, Players (with other players in the game), and the red
**Exit** at the bottom: **Exit to menu** or **Quit game**. Leaving asks whether to save: "Save
and exit" stops the server with `/quit` (Factorio saves as it quits), "Don't save" ends the process.
Closing the window saves and stops the server too. If the client crashes or is ended from the Task
Manager, a small watchdog started with the server stops it a few seconds later (without saving:
Factorio's last autosave is what's left). A bridge you only connected to keeps running.

The console (` or /) runs Factorio's commands wherever they can run (`/help` lists them in these
groups; Tab completes a command's name, Up and Down go back through what you typed):
- **In the client:** `/help`, `/clear`, `/color`, `/shout`, `/ignore`, `/unignore`, `/ignores`, `/permissions`.
- **By the bridge**, with or without RCON: `/cheat` (researches everything; `all` also gives power
  armour MK2, equipment and robots; `off`; a planet or platform name moves the character there),
  the `/f3d-*` commands; and, without RCON, `/version`, `/seed`, `/time`, `/evolution`, `/players`,
  `/admins`, `/server-save`. Cheat mode itself is a player's setting: the bridge's own character on
  a map nobody has joined gets the research and the kit but still crafts at the normal speed.
- **Over RCON** (a server the menu started): Lua (`/c`, `/sc`, `/mc`) and the server's commands
  (`/kick`, `/ban`, `/promote`, `/whisper`, `/config get`, ...). In Lua, `game.player` is the player
  whose character the client plays; on a map nobody has joined it stands for the bridge's own
  character (`game.player.insert{...}`, `.surface`, `.position` work; player-only fields say so).
  `game.print` and `game.player.print` answer in the console, and so do Lua errors. Lua never goes
  through the bridge's UDP: anything on the machine can send UDP, and Lua is for admins.
- **In Factorio itself:** `/editor`, `/screenshot`, `/reply`, `/open`, `/admin`, `/alerts`, the tips
  commands and the others that need a player's game window: the console says to press Ctrl+F9
  (Show in Factorio), which opens the same game in Factorio, and type it there.

Options that only make sense in a game skip the menu and connect straight to
`127.0.0.1:<--factorio-port, 34200>` as before: `--factorio-port`, `--port`, `--open`, `--ui...`,
`--camera=...`, `--fx-demo`, `--no-menu`. The manual ways below still work.

Menu options for tests and screenshots (after `--`):
`--menu=worlds|new[:tab]|host|connect|hybrid|single|multi|mods|about|settings[:tab]|progress` opens
that page (`--menu-preview` makes the map generator ask for its preview), `--menu=esc` opens the
in-game menu once in a game and `--menu=save-as` its Save as window; `--menu-launch=<save>`,
`--menu-new=<name>[:<preset or last>[:<seed>]]`, `--menu-host=<save>[:<port>]` and
`--menu-connect=<host:port>` start a game as the buttons would; `--menu-save-after=<s>` (with
`--menu-save-as=<name>`: Save as), `--menu-exit-after=<s>` and `--menu-quit-after-exit` save, return
to the menu (saving and stopping the server) and quit. `--factorio=<exe>`, `--server-data=<dir>`,
`--saves-dir=<dir>` and `--port-base=<port>` keep a test away from the normal folders and ports.

### The download

`python3 tools/release/package.py` (`--platform windows|linux|all`) exports the client with
Godot and writes `dist/Zenith-<version>-<platform>.zip`. It needs Godot's export templates for the
editor's version. The zip holds one folder: `Zenith.exe` (Linux: `Zenith.x86_64`), the bridge mod
in `mod/factorio-3d-bridge`, the server scripts in `server/`, the licence, credits, this project's
player's guide and `START HERE.txt`. The exported client finds `mod/` and `server/` next to its own
executable, so its servers keep their data in `server/data` and saves in `server/saves` there.
The Linux build has not been run yet. `python3 tools/release/build_mod_zip.py` builds just the mod
(`dist/factorio-3d-bridge_<version>.zip`) for Factorio's own mods folder.

## Quick start without Factorio (mock server)

```
python3 tools/mock_server.py
```

Then open `client/project.godot` in Godot, press **F5** and use Play → Connect to address
(`127.0.0.1:34200`), or start the client with `-- --factorio-port=34200` to skip the menu. The mock generates a world with
lakes, forests, ore, a small factory, a train, a car, robots and biters, so the client can be
worked on without the game. `--day-length 1200` makes a day last 20 seconds instead of seven
minutes, to see night fall. The chest, assemblers, furnaces and lab open as machine screens with
made-up contents; `--start 5,-1` starts the character next to an assembler (`4,9`: the chest).
`--belt-field 24x16 --start=24,-8` adds a block of full belts (about 3,000 items of 24 types)
to watch the client draw items on belts; the client's `--item-bench` prints frame times and the
belt items' own time every 5 s, and `--item-models=off` draws icons instead of 3D models for
comparing. `--item-showcase --start=-20.5,7.5` lays one of every item that has a 3D model on the
ground in a grid. (Much bigger fields don't help: Windows keeps only ~64 KB of a burst of UDP,
about 3,000 items per update.)

## Headless Factorio (the main setup)

The server runs your save with no window and nobody logged in. The 3D client plays your own
character, as follows.

**Your save's character.** On a server a player who isn't connected has their character "logged
off": Factorio takes it out of the world, so nothing can walk or mine with it, but their inventory,
armour, guns, ammo, trash, logistic requests, crafting queue and quickbar stay with the player. So
the bridge stands in for them: its character appears where theirs was (on whatever planet or
platform) and their things move onto it; their quickbar is the client's. When that player joins the
server with the real game, everything moves back onto their character, which stands where the
stand-in was, and the client plays that character from then on. If the stand-in dies, its things
are in its corpse, as with any death, and a new stand-in starts where the player was.

Whose character: the player who was online last (in a save played alone, its owner). On a save with
several players, pick one with `/f3d-player <name>` (on the server console or RCON;
`/f3d-player` lists them) or the map setting "Player to play as" (`f3d-player`); `/f3d-player none`
gives everything back and plays the bridge's own character. A new map nobody has joined gets the
bridge's own character with freeplay's starter kit, as before.

**Linux** (the headless build is a free download):

```
server/download-headless.sh      # once
server/run-headless.sh           # new map in server/saves/world.zip, or load it
server/run-headless.sh ~/my-base.zip
```

**Windows** (uses your installed game; no window opens):

```
powershell -ExecutionPolicy Bypass -File server\run-server.ps1
powershell -ExecutionPolicy Bypass -File server\run-server.ps1 -Save C:\path\to\my-base.zip
```

The script finds the game in any Steam library (or `C:\Program Files\Factorio`). Pass
`-Factorio C:\path\to\factorio.exe` to use another copy. `factorio.exe` is a windowed program,
so the script returns while the server keeps running in the background; stop it with
`python tools\rcon.py /quit` or Task Manager.

Both scripts:

- keep the server's config, logs and mods in `server/data/`, apart from your normal game, so
  the two can run at the same time;
- link `mod/factorio-3d-bridge` into the server's mods, so edits apply on the next restart;
- start the server with `--enable-lua-udp 34200`, `auto_pause` off, and bound to 127.0.0.1.

Then start the client and use Play → Connect to address (`127.0.0.1:34200`), or start it with
`-- --factorio-port=34200`. The status line in the top-left corner shows the connection. (Or let the
menu start the server for you: Play → Load.)

`/f3d-status` shows whether a client is connected, how many chunks are subscribed, and where
the character is. Both scripts enable RCON on 127.0.0.1:34198 with a random password in
`server/data/rcon-password.txt`, so console commands work from another terminal:

```
python3 tools/rcon.py /f3d-status
python3 tools/live_check.py     # plays the client over UDP: walking, building, mining, machine screens
```

`live_check.py` needs the Godot client closed (it uses the client's port) and gives the
bridge's character a few chests and inserters to build with. For a second server on other ports
(`run-server.ps1 -UdpPort 34210 -GamePort 34297 -RconPort 34298`), pass the same ports:
`live_check.py --factorio-port 34210 --client-port 34211 --rcon-port 34298`; `--only platforms`
runs just the space platform checks. `--only save` checks a loaded save (use a copy: it moves the
player's things back and forth): the stand-in's inventory, armour, guns, requests, quickbar,
logistic chests, the map's other surfaces, remote ghosts, and the trains overview, a train's and a
stop's window data, interrupts and temporary stops on a real train. `--only enemies` spawns
biters by a wall, a worm and a spawner next to the character and checks that their attacks arrive
(`en`) and that the spawner's and worm's decals reach a client that asks for decoratives.

### Space platforms (Space Age)

You get to a platform as in Factorio: build a rocket silo, let it make a rocket, and with a platform
in orbit open the silo (or press Enter beside it) and click **Ride** by the platform. The character
walks into the rocket and the client follows the real launch (`launch_rocket` with the character, the
game's own timing: about 8 s on the pad, 20 s climbing), fades out high in the sky and in again in
space, where the cargo pod comes down onto the platform's hub and docks. The character then sits in
the hub, as a player does: no avatar, the view stays round the platform (WASD moves it, Esc on the
hub opens the menu), building places ghosts and the platform's buildings open from there. Factorio's
platform panel (under the minimap, or beside it on a short window) shows whenever the view is on a
platform: on board, in the remote view of one, and in the right column of the map view and the space
map. Stopped it reads "Stopped at Nauvis" with the planet's icon (and, ours alone, the next stop of
its schedule); travelling, the planet it left, a bar with the distance come and the planet it goes
to; then its speed and mass. On board it has **Drop to a planet**: pick a planet, and a cargo pod
takes the character down to the force's landing pad there (or beside the spawn) once the platform is
stopped over it; the red cross cancels. Where the platform goes and its pause are set in its hub's
screen, as in Factorio. Input to the world is locked during the rides; the world is reloaded for each
new surface and the inventory comes along.

To get a platform without building a rocket, on the server console or over RCON:

```
python3 tools/rcon.py /f3d-platform new        # build one in orbit (starter pack applied)
python3 tools/rcon.py /f3d-platform board 1    # put the character on platform 1 (a teleport, for tests)
python3 tools/rcon.py /f3d-platform leave      # back down to the planet below (or: leave nauvis)
python3 tools/rcon.py /f3d-platform            # list the platforms
```

The mock can show every turret, a tank and a spidertron aiming and firing at its biters:
`tools/mock_server.py --turrets --start 69,40` (`tools/mock_turrets.py`, Factorio's rotation
speeds and cooldowns; they do no damage).

The mock has the other planets too: `tools/mock_server.py --planet vulcanus` (or `fulgora`, `gleba`,
`aquilo`) starts on a small surface with its tiles, a few buildings and its data (a crawling
demolisher, lightning on rods, growing yumako and a pentapod, frozen inserters), and `land` from
the platform goes down to whichever planet it is stopped at.
The mock has a platform too (`tools/mock_server.py --platform` starts on it), and the client's
`-- --plat-board=1@5` boards platform 1 after 5 seconds (0 goes back down), for screenshots. The
mock flies `ride` and `land` on a shortened timeline. `-- --ride=1@8` rides the nearest silo's rocket
to platform 1 after 8 seconds and `-- --land=50` goes back down at 50 s, without clicking;
`live_check.py --only ride` checks both against a real server.

Space Age's screens open like any machine's: the platform hub (the platform, its schedule with
interrupts, its requests from planets), a rocket silo (parts, automatic launch, **Launch** to a
platform in orbit), cargo landing pads and bays, asteroid collectors. **Space map** (at the top of
the remote view's Surfaces panel, the map's surface switcher) shows the solar system, the routes and their
asteroid danger, and the platforms; click a planet or platform to look at it, and **New platform**
makes one over this planet that waits for a starter pack (put one in a rocket silo's rocket and
the game launches it). In the mock a silo and a landing pad stand west and north of the start;
`--auto-launch` launches the silo's rocket whenever it is ready (a rocket rising, then a cargo pod
coming down on the pad), and the client's `-- --ui=space` opens the space map after 3 seconds.

### What the bridge costs

`/f3d-profile` turns per-module timing on (and off); after 10 s `/f3d-status` lists each module's
average script time per tick (`transport`, `world` (chunk snapshots), `movers`, `belt_items`,
`inserters`, ...). To try it on a busy base, `python3 tools/busy_base.py` builds one next to the
bridge's character on a test save (loops of belts full of moving plates, a block of assemblers
fed by inserters, power), profiles for 12 s and prints the report; `--clear` removes it again.
`--big` adds a main bus, a train, a robot network and a block of walls (20,000+ entities), and
`--measure out.json` connects a client of its own instead of needing one: it records each
module's time, the game's UPS with and without the bridge serving, chunk snapshot time, bytes per
second by message type and a call-by-call breakdown of reading belt items. CI's `busy` job runs
`--big --measure` against `tools/busy_budget.json` and fails when the bridge costs more than
twice the budget. On CI's runners the bridge costs about 6 ms per tick with 3,700 belt items in
view, nearly all of it `belt_items`; the game keeps 60 UPS. On a laptop with `--big` (about 25,000
entities) and the windowed client connected it costs about 15 ms a tick. If a module is expensive, the "Belt item, ground item and inserter radius" and "update interval"
settings below are the first things to turn down.

Two things keep the bridge from making a slow tick. **The work budget** (`scripts/budget.lua`):
everything that can be big (chunk snapshots, map charts, the handshake, another planet's remote
view, Factoriopedia, statistics, the trains on the map, hover info) is done in slices, paid from
300 work units a tick by default (about one entity read each); the client may change it
(`budget`, 50 to 20000) and hears once a second how it is used (`wb`, docs/PROTOCOL.md "Work
budget"). **Update rates** (`scripts/rate.lua`): at `rate` level 1 to 3 the costliest periodic
updates (belt items, far lanes, movers, then machine states, enemies, then fluids, trains, turrets,
inserter hands) come less often, each level doubling their interval; the character's own
updates never slow. Hold the game at 60 UPS sets both; `/f3d-rate 0-3` sets the level by hand.

### Watching with the normal game

The server also accepts regular Factorio clients on `127.0.0.1:34197` (Multiplayer → Connect to
address; a server the menu started uses the free game port it picked, 34501 or so, or the port
you host on). You get your own character next to the 3D client's, with all the normal GUIs.

**Ctrl+F9** (Show in Factorio) in the client brings Factorio's window to the front, or starts
Factorio joined to the server the client started. While you play there, the bridge drives your
player's character, so both windows show the same one. The mod adds the same key in Factorio
("Show in Zenith"), which brings the client back. The swap with a real Factorio window hasn't been
tried yet.

### Several 3D clients on one server

Start a second client on the same machine and connect it to the same server: it binds the next
free UDP port (34202, 34203, ... up to 34208) and gets a character of its own. Each client sees
the others walking around. `/f3d-status` lists them. Single-player plays one character, so there
the newest client takes over instead.

## Single-player (hybrid mode)

**New.** The owner has played it once, side by side with Factorio's window, on Factorio 2.1.24:
`send_udp` and `recv_udp` work without a player argument in single-player. It hasn't been tried
much beyond that, so the headless server above is still the main setup.

The 3D client can also drive your own character in a normal single-player game:

1. Copy or link `mod/factorio-3d-bridge` into your mods folder (`%APPDATA%\Factorio\mods` on
   Windows, `~/.factorio/mods` on Linux).
2. Add `--enable-lua-udp 34200` to Factorio's launch options (Steam: Properties → Launch Options).
3. Load a save, then start the client and use Single player → Single-player (hybrid) → Connect
   (`127.0.0.1:34200`).

Inventory, crafting and machine GUIs work in the Factorio window as usual; the 3D client's own
machine screens work too.

The 3D client's quickbar is your character's own (both windows show the same one). The bridge
doesn't chart the map around you here; your player does. To check that the bridge's calls work
on your own character, type `/f3d-selftest` in the game's console (`~`): it prints one PASS or FAIL
line per check (reach, selecting an aim target, the quickbar, charting, sending to the client) and
puts back what it borrowed. On a server the same command answers over RCON
(`python3 tools/rcon.py /f3d-selftest`).

## Client controls

| Input | Action |
|---|---|
| WASD / arrows (or a gamepad's left stick) | Walk, relative to the camera, at any angle (the bridge steers Factorio's 8-way character to follow it) |
| Right mouse (hold) | Mine what's under the cursor |
| Enter | Get into the nearest vehicle (car, tank, train, spidertron) or out of it |
| Spidertron remote (shortcut bar) | Drag: select spidertrons · Shift+drag: add · right-drag: remove · click: send them there · Shift+click: queue a waypoint |
| WASD in a vehicle | W accelerate, S reverse, A/D steer (relative to the vehicle) |
| F (hold) | Pick up items lying on the ground next to the character |
| Space (hold) | Shoot at enemies near the character (the game picks the target) |
| C (hold) | Shoot at the cursor |
| Tab | Switch to the next gun (or click a gun in the weapon slots left of the quickbar) |
| E | Open the character window (inventory and armour/weapons/ammo on the left, hand-crafting on the right); over a building with a screen, open that instead. With any window open, E closes it |
| Esc | Close the open window, machine screen, map view, chooser or remote view; with none open, the Game menu (Resume, Load game, Save game, Save as, Settings, Exit; Players when others play too) |
| T | The technology screen: the research in progress and queue, the selected technology (cost, time, prerequisites) with Start research / Add to queue / Cancel, and the tree on the right. T, E, Esc or × closes it |
| M | The map view: the charted map over the whole window (north up) with your character's arrow, the map tags and trains. Drag (left or middle mouse) or WASD/arrows move it (Shift: faster), the wheel zooms about the mouse. Right click: on a tag, edit or delete it; on a ghost, remove it; elsewhere, create a tag there (icon, name, Confirm). Double click also creates or edits a tag. M or Esc closes it (Esc closes the tag dialog first). The game keeps running underneath, and the character doesn't walk while it is open |
| Minimap (top right) | The charted map around the character (in the map view or remote view, around what that looks at), north up, with tags and trains. Click it to open the map; the wheel or its + / − buttons zoom it |
| Click a stack (inventory or machine) | Pick it up into the cursor, as in Factorio (right click: half). The cursor shows its icon and count; its slot shows Factorio's hand |
| With a stack in the cursor, click a slot | Put it there (a different item swaps, so the other stack is now in the cursor); right click drops one; click its own slot, or Q, to put it back. Left mouse in the world builds it (only stacks from the inventory) |
| Shift+click a stack | Move it between the inventory and the open machine (Ctrl+click: all of that item) |
| Click a recipe | Hand-craft one (right click: five, Shift: as many as possible). Hover for ingredients (red where short), time and products |
| Crafting queue (bottom left) | Each queued craft with its count; the first fills with Factorio's orange pie. Click cancels one, right click five, Shift+click the whole entry |
| 1 – 0 | Hold the item pinned to that quickbar slot (again: put it away). With the character window open: pin the hovered item, or the held one, to that slot |
| Click a quickbar slot | Hold its item; with an item held, pin that item there. Right click clears the slot. Inventory items can also be dragged onto it |
| Left mouse (hold and drag) | Build the held item along the way, as Factorio drags: belts follow the cursor and turn corners (with Smart belt building, Settings → Interface, an obstacle or a crossing belt is jumped with undergrounds), pipes go in a line (pipes-to-ground over obstacles), poles at their wire reach, anything else one footprint after another; a faster belt dragged over a line replaces it. Its ghost is green where it can go, red where it can't (none left, beyond the 10-tile build reach, something in the way). Over a window the mouse only works the window: nothing behind it is hovered, built or mined |
| Holding a blueprint, left click | Place its ghosts there (shown under the mouse first; robots build them; building the item over its ghost fills it in yourself). Ctrl+Shift+click: super-forced (trees and rocks in the way are marked). A book places its active page; Shift+mouse wheel picks the page |
| Holding a deconstruction or upgrade planner, left drag | Mark the area (Shift: cancel the marks). What it will take is highlighted in its colour while dragging |
| B | Blueprint library: My blueprints (kept by the client in `user://blueprint-library.json`), the save's Game blueprints and, when the bridge plays the save's own player, that player's library. Click takes one into the cursor, right click opens it (books open in place), drag moves it or drops it into a book, Del deletes; Import string takes a string copied from Factorio or a website; New book / planner buttons |
| Right click a blueprint, book or planner in the inventory | Its window: label, icons, description; a blueprint's components (click one to take it out), what it includes, snap to grid and absolute snapping; a book's pages; a deconstruction planner's filters, whitelist / blacklist, trees and rocks only, tile mode; an upgrade planner's from → to rows. Save writes it back; Export string copies Factorio's string |
| Ctrl+mouse wheel | The held item's quality (the qualities your force has) |
| Ctrl+Shift+left | Super-forced build: a ghost, and what stands in the way is marked for deconstruction |
| Holding tiles (stone brick, concrete, landfill, foundation...) | The brush shows at the cursor (green, red where the tile can't go, blue as ghosts with Shift). Left mouse paints, right mouse mines placed tiles back; Numpad + / - change the tile area; R turns hazard concrete |
| Holding rails | Click a rail end to start the rail planner there: the path of straight and curved rails to the cursor shows, click (or drag from the end) builds it and carries on from its end; ghosts where your rails run out. Alt+R (while holding rails; otherwise it gives red wire): rail layer (a ramp up, elevated rails with supports). Right click lets go |
| Holding grenades, cliff explosives, capsules | The throw range and blast show; left click throws at the cursor (hold to keep throwing). Fish heal you |
| R / Shift+R | Rotate the held item (rails by 45°), or the hovered entity. Building the same belt over a belt turns it; a faster belt (or anything that fast-replaces) replaces it |
| E, or left mouse with nothing held | Open the hovered building's screen (chests, assemblers, furnaces, labs, drills, boilers...) beside your inventory: its name, status (Working, No ingredients, No fuel, No power...), energy, slots and fluid boxes. E, Esc or its × closes it |
| Recipe slot in an assembler's screen | Click to pick its recipe from the grid below; right click clears it. Items it was holding come back to you |
| Q | Put the held item (the cursor stack) away; with nothing held over an entity, the pipette: hold its item, turned the same way (a ghost cursor when you have none) |
| Z (hold) | Drop one of the held item: into the machine or chest under the mouse, onto a belt, or on the ground |
| Shift+left click | Holding an item: build a ghost of it for robots. Holding nothing: paste the settings copied with Shift+right click (recipe, filters, requests, combinator settings) |
| Ctrl+left / Ctrl+right click an entity | Fast transfer: the held stack (half) into it, or with nothing held its output (half) into your inventory |
| H / V | Flip the item being built, or the entity under the mouse (machines with fluid boxes) |
| Alt | Alt-mode: recipe and filter icons over machines (kept between games); it toggles when Alt is let go, unless Alt was held for an Alt+click |
| Alt+click | Factoriopedia's page of the thing under the mouse (in the world, or a slot or technology in a window) |
| F2 | Factoriopedia |
| L | Logistic networks: every network of the force, its robots and items |
| Ctrl+C / Ctrl+X, drag | Copy or cut an area to the clipboard; then left click pastes it (R turns it), right click puts the tool away. Ctrl+V pastes the clipboard again |
| Ctrl+Z / Ctrl+Y | Undo / redo your own building (marks it for deconstruction) and mining (puts a ghost back), blueprints placed, planner marks, pasted settings and rotations |
| Alt+B / Alt+D / Alt+U, drag | A new blueprint of the area in your inventory (its window opens) / mark the area for deconstruction (Shift: cancel) / the upgrade planner (a new one if you have none) |
| Alt+R / Alt+G / Alt+C (or the shortcut bar) | Red, green or copper wire: click an entity, then another to connect them (the same pair again disconnects them); the wire then hangs from the second, so a row is wired click by click. The hanging wire is drawn to the mouse with a ring for its reach (grey past it). Click a combinator's front (output) or back (input) half, a power switch's left or right side. Right click lets go of the wire, again puts the tool away |
| Shift+click a pole | Remove its copper cables |
| Open anything on a circuit network | Its circuit connection (enable/disable condition, read modes, set recipe / filters / stack size...) and logistic connection settings; combinators in full (decider conditions with and/or and red/green inputs, outputs; every selector mode; constant combinator sections); lamp and train stop colour, speaker, pump filter, turret priority targets, display panel messages |
| P / K | Production statistics (items, fluids, pollution, building counts; this surface or all; Factorio's graphs: click a row's box to draw it) / kill statistics, over Factorio's 8 time scales |
| ` or / | Chat (a line starting with / is a console command, run over RCON when this client started the server) |
| Ctrl+F | Search the crafting recipes |
| Shift+1 – 0, X | Show quickbar page 1–10, swap the two quickbar rows |
| Middle click an inventory slot | Filter it to its item (or the held one); again clears it |
| Click a car or wagon | Open it: fuel, trunk, ammo, cargo; a train's window has Factorio's schedule (every wait condition, and/or), interrupts, Go to station now (a temporary stop), the whole train's cargo and fuel, and a camera above it. A train stop's: name, limit, priority, circuit settings |
| Map: zoom in past the closest zoom | Remote view there (in Factorio's angle, F6's view), on any surface the map shows: WASD moves it, Esc or M goes back to the character. Ground no working radar, roboport (its construction area) or the character sees lies under a dark fog, with nothing moving there |
| Ctrl+F9 | Show in Factorio: bring Factorio's window to the front on the same game (or start it joined to the server the client started) |
| , / . | Turn the camera 90° |
| Middle-mouse drag | Turn the camera freely (left/right) and tilt it (up/down) |
| Page Up / Page Down | Tilt the camera |
| Mouse wheel | Zoom |
| F6 | Jump to Factorio's own view (north up, from above at Factorio's angle and default zoom); again to go back |
| F5 | First person: see through the character's eyes, mouse looks, aim with the crosshair; F5 again to go back. The mouse is freed while a window is open |
| F7 | Perspective or orthographic for the view in use: in the map's remote view it changes the map's projection, elsewhere the normal view's (in Factorio's view, F6, used on leaving it); kept in Settings > Camera |
| F1 | Show or hide the client's help panel (off by default) |
| F4 | Show or hide the debug line (tick, chunks, entities, packets, the game's UPS, FPS) |

Client command-line options go after `--` (Godot: Project → Project Settings → Run, or the
command line): `--factorio-port=34200 --port=34201 --models=/path/to/glb/folder
--factorio-data=/path/to/Factorio/data`. `--models=` only fills in entities without a model of
their own; add `--models-first` to let the folder's models replace the built-in ones.
`--addons=<folder>[,<folder>...]` loads add-ons from those folders (an add-on's own folder or a
folder of add-ons), always on, ahead of installed ones with the same id ([ADDONS.md](ADDONS.md)). `--camera=factorio`, `--camera=first-person` or
`--camera=<yaw>,<pitch>,<distance>[,ortho]` start in that view instead of the Camera setting's
(`--camera=0,48,14,ortho` is close to Factorio's own). `--screenshot=<file.png>[@seconds]` saves
the window once (default after 10 s; needs a window). `--open=<unit>` opens that entity's machine screen once
it has loaded (for screenshots and debugging). Also for screenshots: `--ui=inventory` opens the
character window at start, `--ui-sample` feeds sample recipe details (crafting tabs, ingredients)
through the hooks the mod's full UI data will use and pins a few quickbar items,
`--ui=research` opens the technology screen, `--ui-hold=<item>` picks up that item's first stack after 4 s,
`--ui-craft=<recipe>:<n>` hand-crafts after 3 s (to see the queue), `--ui-hover=<x>,<y>` keeps the mouse
there from 5 s on (tooltips, the cursor stack, the build ghost), `--ui-hover-unit=<unit>` keeps it over that entity
wherever it is drawn (its entity info), `--ui-press=<node name>` clicks that
button or slot after 7 s (popups: `SecondOperand`, `Signals`, `ChangeGroup`), `--map` opens the map view at start
(`--map-zoom=<GUI pixels per tile>`, 0.25 to 8; `--map-tag=<x>,<y>,<icon item>,<text>` adds a tag
after 3 s; `--map-edit=<x>,<y>` opens the tag dialog at that window point after 5 s), and `--ui-scale=1.25`
overrides the UI scale (by default 100% up to a 1080-line window, then in steps of 25%, like
Factorio's automatic scale: 150% at 2880x1659). `--alt-mode`, `--stats=<item|fluid|kill>`,
`--chat=<text>` and `--remote=<x>,<y>` turn on Alt-mode, open statistics (also `pollution`,
`build`), say a line, or look somewhere in remote view after 3 s. `--ui=networks` opens the logistic
networks window, `--pedia=<kind>:<name>` Factoriopedia on a page after 4 s (`item:assembling-machine-2`,
`technology:mining-productivity-3`), `--research=<technology>` selects one in the technology screen.

The inventory, crafting, quickbar, weapon slots, crafting queue, technology screen and machine
screens are drawn with Factorio's own GUI graphics, fonts and names (technology icons, status
dots, the hand, empty-slot pictures, locale files), read from your install like the item icons (`core/graphics/gui-new.png`, laid out as
`core/prototypes/style.lua` does, and `core/fonts`); nothing of the game's is copied into this
repo. Without an install they fall back to flat panels in Factorio's colours. The quickbar is kept
by the client (in Godot's `user://quickbar.cfg`) until the mod sends one.

Networks and ghosts are drawn like Factorio's: copper wires sag between the poles' insulators (red
and green circuit wires beside them), a machine with no power blinks Factorio's red lightning icon
(one tile wide; low power has no icon, as in Factorio: it only slows machines), lamps without power
stay dark, storage tanks show their level in the fluid's colour through a window on their south
side, and hovering an entity with fluid or a power problem lists it by the cursor. The entity info
panel on the right (Settings → Interface → Entity tooltip on the side) shows the hovered entity as
Factorio does: its status (No power, Low power...), recipe, modules, the beacons reaching it and
their effects (a beacon: its modules and the machines it reaches), and for a powered building
Factorio's "Consumes electricity" (Max. and Min. consumption and the Electricity bar from its
buffer). Hovering a roboport draws orange lines to the roboports it is linked to; holding one
draws the links round where it would go. Ghosts are the entity in translucent blue-white; entities
marked for deconstruction get the red cross, for upgrade the green arrow. The icons come from your
install's `core/graphics` (plain coloured discs without one).

Items on belts and on the ground are drawn as cards with the item's icon, read from your Factorio install (the
client looks in the usual Steam and standalone locations; `--factorio-data` points it at the
`data` folder otherwise). Without icons, items are small coloured blocks. The headless build
has no graphics, so it can't supply icons.

The ground uses Factorio's own tile pictures from the same install: `base/prototypes/tile/tiles.lua`
(and Space Age's) say which picture, variant sizes, weights and layer each tile has, and the
pictures come from `*/graphics/terrain/`. Each tile shows one of Factorio's 1x1, 2x2 or 4x4
variants, picked per position the way the game does, so fields don't look tiled; higher tiles
(by Factorio's layer order: grass over dirt over sand, floors over ground) spread over their
lower neighbours with a ragged edge like Factorio's transitions; concrete and other floors keep
crisp edges. Water uses Factorio's water pictures with deep and shallow water blending, and the
coast wanders off the tile grid with a wet rim instead of square banks. Pictures are loaded the
first time a tile type appears (the console prints `Terrain: <tile> ...`). Without an install,
or with `--plain-terrain`, the ground is the map colours with procedural detail.

### The map and the minimap

The map and minimap show what your force has charted, drawn by the mod like Factorio's map (tile
colours, then ore, trees and rocks, then buildings in their map colours; see "Map" in
docs/PROTOCOL.md). The mod sends at most 2 tiles per pixel and 4 chunks a tick, so the client asks
only for what is on screen, a 32 x 32 chunk block at a time from the middle out, asks again every
4 s (minimap) or 6 s (map view) for the same area, and skips ground it knows is uncharted except
at the edge of charted ground and in a full pass once a minute. Every 30 s, when it is idle, the
minimap also asks for the area the map view opens on, so the map opens filled in. Uncharted ground
is black, and charted ground no working radar (or the character) sees is dimmed, as on Factorio's
map. In Zenith roboports reveal too (Factorio's don't): ground whose chunk has its middle in a
roboport's construction area counts as seen, on the map, the minimap and in the 3D remote view.
The bridge's character has no player, so the mod charts around it itself while a client is
connected. While the map view is open the minimap shows what the map looks at, and in the 3D
remote view what that looks at, as in Factorio.

Over the chart, the map view draws what Factorio's map view settings switch (Factorio's grid of
icon buttons under the side menu, lit orange when on; also in Settings → Interface): tags, electric
networks (poles' supply areas and their copper wires), logistic networks (roboports' logistic and
construction areas), turret coverage, train stop names, worker robots, rail signal states, recipe
icons and pollution. Trains are drawn live in their own colours where radars see them. The mod sends them with each chunk's chart (`ov`, see
docs/PROTOCOL.md "Map"); the minimap shows the same layers. The logistic layer shows every roboport
on the surface, not only those on the charts loaded: the client asks the mod for the whole list
(`mrp`) every 10 s while a map or the remote view needs it. Overlapping areas read as one region,
as on Factorio's map.

**Other surfaces.** The map view's top-left panel lists the planets that have a surface and your
space platforms (Factorio's surface switcher); clicking one shows that surface's map and tags (tags
added there go on that surface). A planet's map centres on your cargo landing pad there (its middle
when there is none), a platform's on its hub. Closing the map goes back to the character's surface. Zooming in past the closest zoom on another surface opens the remote view
there: the mod streams that surface's world until the remote view ends.

**Building from the map.** Zooming in past the closest zoom goes to remote view (the camera moves,
the character stays). There, as in Factorio 2.0, whatever you place is a ghost for the robots,
blueprints and the copy / paste tools place ghosts, the deconstruction and upgrade planners mark
areas, and right-click (mining) marks the entity under the mouse for deconstruction. All of it only
on ground the force has charted ("You can't build in an uncharted area"), and on another surface
too. On a platform only what the platform can build is placed: nothing over empty space, nothing
its gravity forbids (both red in the preview). Mining by hand, picking up, shooting, dropping, fast
transfers, wires and throwing wait until you are back with the character. Buildings where radars
or roboports see open from the remote view for their settings; their items stay out of reach. Holding a module and
clicking a building or ghost asks for it (an item request, brought by robots or a platform's hub;
within reach it goes straight in), and so does clicking a module slot of a screen opened from the
remote view; right click on that slot takes the request back.

**Trains.** The side menu's Trains button, or "All trains" in a train's or stop's window, opens
Factorio's trains overview: every train of the force with its state, stop, size and cargo, a switch
between automatic and manual, and View (remote view at the train).

The map's options are in the `[map]` section of `user://settings.cfg`;
`client/scripts/ui/ui_settings.gd` gives them limits and a `changed` signal
(`UiSettings.shared().set_value("map/minimap", false)`):

```
[map]
minimap=true        ; show the minimap
minimap_size=240    ; its side in Factorio GUI pixels (times the UI scale), 120 to 480
minimap_zoom=1.0    ; GUI pixels per tile, 0.25 to 4 (the minimap's + / - buttons change it)
minimap_tags=true   ; tags on the minimap
show_tags=true      ; the map view's switches (both views): show_tags, show_electric,
show_turrets=false  ; show_logistic, show_turrets, show_stops, show_robots, show_signals,
                    ; show_recipes, show_pollution (off by default)
```

### Sound and effects

The client plays Factorio's own sounds and draws its smoke, explosions and flashes, read from your
install at runtime like the icons (`data/base/sound`, `data/core/sound`, and sprite sheets in
`data/base/graphics/entity`); nothing of the game's is copied into this repo. Working machines
near the camera hum with their prototype's `working_sound` (assemblers, furnaces, drills, boilers,
steam engines, labs, pumps, radars...; at most 12 at once, nearest and loudest first, at most 3
of the same sound), and cars and trains have engine sounds while they move. The character has
footsteps by ground (grass, sand, dirt, concrete, belts, rails, ore), mining hits, building,
rotating and mined-out sounds, gunshots, and biters call and die. Burner furnaces, boilers and
burner drills smoke while they work, steam engines steam, shots flash at the muzzle and where they
land, and things that die explode and leave a scorch mark and a burnt remnant for a while. Biters
and spitters collapse into their corpse, which lies in a blood puddle for Factorio's 15 minutes;
worms leave theirs too. Without an install the client is silent and the effects are plain soft blobs.

Volumes are in the `[sound]` section of `user://settings.cfg` (Settings → Sound):

```
[sound]
master=0.8      ; everything
effects=1.0     ; game effects: the five below and everything else in the world
walking=1.0     ; footsteps          environment=1.0 ; machines and vehicles
weapons=1.0     ; shots              explosions=1.0  ; explosions
enemies=1.0     ; biters
ambient=1.0     ; wind and the planet's background sounds
music=0.0       ; Factorio's soundtrack (the planet's own tracks), off by default
ui=1.0          ; window clicks
walking_on=true ; <name>_on=false mutes that slider
max_voices=12   ; machine and vehicle loops playing at once
output_device="Default"
[graphics]
effects=true    ; smoke, flashes, explosions, corpses
```

Command-line options (after `--`) override the file for that run: `--volume=0.5` (master),
`--sfx-volume=`, `--music-volume=0.3` (turns the soundtrack on), `--ui-volume=`, `--mute`,
`--max-voices=8`, `--no-fx` (no smoke or explosions). For debugging, `--sfx-log` prints every
sound started and, every 5 s, how many voices are busy, and `--fx-demo` plays the character
through a short script (walk, mine, build, rotate, shoot, then a staged explosion; `--fx-demo=space`
shoots at enemies instead) so sounds and effects can be checked without input. The UI plays
Factorio's GUI sounds through `Sfx.play_ui("gui-click")` (`client/scripts/fx/sfx.gd`).

Sounds follow Factorio's own rules, read from its prototypes (`client/scripts/fx/sound_bank.gd`):
each sound's volume, variations and pitch range; `audible_distance_modifier` and the attenuation
curve over the audible distance (40 tiles, heard from the middle of the view, quieter zoomed out);
`aggregation` (at most `max_count` of one sound at once, the rest dropped or quieter); working
sounds limited to `max_sounds_per_prototype` per kind of machine, faded in and out over the
prototype's `fade_in_ticks`/`fade_out_ticks`, with idle and activate/deactivate sounds; a limit per
category with `priority`; a limiter on the master output so nothing clips. Each planet plays its
`persistent_ambient_sounds` (ambience and wind crossfaded by zoom, the occasional distant sound)
and its own music (`client/scripts/fx/ambience.gd`). The engine's own constants (audible distance,
default curve, category limits) aren't in the data and are chosen by ear. `--fx-demo=stress` adds
ten volleys of 30 biter deaths, 8 explosions and 12 shots, to measure with `--sfx-log` (which also
prints the most voices at once, peaks per bus and sounds started over the same file).

What weapons fire is drawn from Factorio's own prototypes and sheets
(`client/scripts/fx/weapon_fx.gd`, data in `client/data/weapon_fx.json` from
`tools/weapon_fx_index.py`): each shot's muzzle flash, bullet hit and shell casing at the gun's own
rate; rockets with their smoke trail and light, shotgun pellets, cannon and artillery shells,
grenades and capsules on their arc, flamethrower streams, tesla and laser beams, the railgun's beam;
every explosion prototype's animation, scorch marks, fires with burnt patches, poison and slowdown
clouds, and each entity's dying explosion. A headless server doesn't make the explosions Factorio
marks "only when visible" (muzzle flashes, bullet hits, a rocket's explosion), so the client plays
them itself. `--weapons-demo` fires the character's three guns in turn and throws a grenade and a
poison capsule, printing what it drew; against the mock use
`tools/mock_server.py --guns shotgun,rocket-launcher,flamethrower` (the mock's version is
`tools/mock_shots.py`), against a server give the character guns first.

## Add-ons

Add-ons ([ADDONS.md](ADDONS.md)) are folders with an `addon.json`, found at start-up in
`user://addons` (on Windows `%APPDATA%\Godot\app_userdata\Zenith\addons`), in `addons/` beside
the executable (in a checkout, the repo's root), and in any `--addons=<folder>`. The main menu's
Mods window lists them with a switch each (saved in the settings file's `[addons]` section, on
when absent) and why one wasn't loaded (a newer add-on API than this Zenith's, a broken
`addon.json`, an entry script with an error). The log says which started. Their keys show in
Settings → Controls under each add-on's name; their data is kept in `user://addons-data/<id>/`.
An add-on with the camera turns the player's controls off until it hands it back; Zenith takes it
back itself for a ride to a space platform.

## VR (experimental)

The client can draw the game in a VR headset through OpenXR: SteamVR (Index, Vive, Quest over
Link), Meta Quest Link or Air Link, Windows Mixed Reality. It runs on the PC next to Factorio (the
bridge is localhost-only), so a standalone headset streams from the PC. Start the headset's
runtime, then:

    godot --path client --xr-mode on -- --vr --factorio-port=34200               # tabletop
    godot --path client --xr-mode on -- --vr=first-person --factorio-port=34200  # first person
    ... --vr --vr-hand=left                                                      # left-handed

(`--factorio-port` connects at once; the menu is only on the desktop window. Without
`--xr-mode on`, or without a headset, `--vr` only prints a warning and the game runs as usual.)

**Tabletop** (the default) works like a map editor: the factory is a model on a table at waist
height in front of you. Grab it with a grip and drag it around; grab with both grips to move,
zoom (pull your hands apart or together) and turn it in one go. The chunks and live data (belts,
trains, robots) follow the table's centre, so you can look over the whole base while your
character stays where it is; clicking the other stick puts the table back on your character at
your height. **First person:** you stand where your character stands, a tile to a metre.

| | Pointer hand (right; `--vr-hand=left` swaps) | Other hand |
|---|---|---|
| Trigger | Left click: build, open, select (hold to drag-build) | Shift, while held |
| A / X | Right click: mine, cancel (hold to keep mining) | Character screen (E) |
| B / Y | Rotate (R) | Show the HUD panel in front of you, or hide it |
| Stick | Tabletop: turn the table 45° (left/right), zoom (up/down). First person: turn 30°. On the panel: scroll | Walk, the way you look |
| Stick press | Pipette (Q) | Tabletop: the table back on your character |
| Grip | Grab the table | Grab the table (both grips: move, zoom, turn) |
| Menu | | Esc |

The laser from the pointer hand is the mouse: where it meets the ground is where you build and
mine, and on the HUD panel (Factorio's windows, quickbar, minimap) it clicks like the mouse. The
desktop keyboard keeps working.

Not done yet: the main menu and the in-game Esc menu stay on the desktop window, Alt-mode labels
aren't placed on the panel, first person has no movement prediction (you feel the bridge's
delay) and no comfort options (vignette, smooth turn). Nothing of this has been tried in a
headset yet.

## Sky and clouds

Each planet has its own sky (`client/scripts/world/sky.gd`): a gradient with the sun, stars at night
and clouds, following the game's time of day. Clouds use Factorio's own cloud noise from the
install (`core/graphics/clouds-noise.png`, a generated noise without one) and cast soft shadows
that drift over the ground, as Factorio's do on Nauvis, Gleba and Fulgora (opacity 0.25, from the
planets' `surface_render_parameters`). Vulcanus and Gleba have a coloured haze (Factorio's fog),
Aquilo a cold one; Fulgora's nights have lightning flashes. Settings → Graphics → Clouds turns
clouds, shadows and haze off (`[graphics] clouds=false`); `--clean-shot` and `--review-shots` do too.
`--sky=<planet>[@<daytime>]` shows another planet's sky and holds the time of day (0 noon, 0.5
midnight), for screenshots against the mock: `--sky=fulgora@0.45`.

## Decoratives

Grass, flowers, small rocks and decals lie on the ground as in Factorio, with the pictures from
your install (which picture each has is in `client/data/decoratives.json`, written by
`tools/decor_index.py` from `factorio --dump-data`; CI regenerates it and prints it when it
differs). Gleba's plants, corals and icebergs (Factorio's "object" layer) stand up as cards.
Settings → Graphics → Decoratives turns them off (`[graphics] decoratives=false`; the client then
stops asking for them, `dc` in the hello), and Decorative density draws a share of them (the
same ones each time). They are drawn round the character (or the remote view's point) out to
Decorative distance (64 to 320 tiles, default 192): all of them to 80 tiles, then half, then a
quarter past 136. The bridge sends a chunk's decoratives again when a tile is placed or mined in
it or something is built there; ones another mod's script removes stay drawn until the chunk's
next refresh.

## Mod settings

In a game the client's menu started: the client's Settings → Mod settings, sent over RCON at once.
In Factorio: Settings → Mod settings → Map. On a headless server started by hand, set them from
the server console or RCON, for example `/c settings.global["f3d-chunks-per-tick"] = {value = 2}`.

| Setting | Default | |
|---|---|---|
| Surface to stream | nauvis | Where the server's character lives |
| Chunk snapshots per tick | 1 | Faster world loading vs. script time per tick |
| Bytes sent per tick | 32768 | Caps queued world data per tick |
| Max live-update radius | 192 | Movers and machine states beyond this aren't sent; caps the client's "Entity distance" (Settings → Graphics, default 192). A save keeps the value it had; on a server raise it with `/c settings.global["f3d-max-focus-radius"] = {value = 192}` |
| Moving entity update interval | 2 | Ticks between mover updates |
| Belt item, ground item and inserter radius | 24 | Items on belts, items on the ground and inserter hands within this many tiles of the camera are sent; 0 turns them off. Lower it if a dense base costs too much script time |
| Belt item and inserter update interval | 6 | Ticks between updates; the client glides items and arms in between |
| Starter kit | on | Freeplay items for the bridge's own character |
| Player to play as | (empty) | Whose character the client plays on a server; empty: the player who was online last. `/f3d-player` changes it while the game runs |

## Troubleshooting

- **"Waiting for Factorio on 127.0.0.1:34200"**: Factorio isn't running with
  `--enable-lua-udp 34200`, or the mod isn't enabled. Check `server/data/factorio-current.log`
  for `factorio-3d-bridge` and for "UDP is unavailable".
- **"Can't open UDP port 34201"**: the client tries 34202 to 34208 by itself, so all nine are
  taken: close other clients (or the mock server's test).
- **"Incompatible Factorio version"**: the mod is marked for 2.1. A 2.0 game won't load it;
  change `factorio_version` in `info.json` to "2.0" to try (untested).
- **Server exits with "Can't bind socket: Error code 10013"** (Windows): another program has
  one of the ports. `Get-NetTCPConnection -LocalPort 34198` / `Get-NetUDPEndpoint` shows who.
- **Stutter while the world loads**: lower "Chunk snapshots per tick", or the client's "View
  distance" and "Entity distance" (Settings → Graphics).
- **The game runs slowly with the client connected on a big base**: what the client asks for
  (every item on belts near you, far belt lanes, moving things within the entity distance, new
  chunks, the minimap's charts) is worked out in the game's tick. Settings → Graphics → Hold the
  game at 60 UPS (on by default) steps in while the game runs under 57 UPS, one step every few
  seconds: first the bridge sends its costliest updates less often and the minimap refreshes less
  (`rate` 1 to 3: the world may glide further, the game keeps its speed), then the entity, belt
  and view distances go below your settings (floors 64 tiles, 8, 32, 5 chunks), then a 45 FPS cap; it gives a step back after 30 s at 60. It also keeps
  the bridge's work budget to the room the game has, so a big request doesn't make a slow tick.
  Your settings stay as they are; the F4 line says what it holds back. Otherwise `/f3d-profile`, then `/f3d-status`, shows which module costs most: lower "Belt
  item, ground item and inserter radius", or the client's "Belt items in full", "Belt items far
  away" and "Entity distance". `python tools/ups_probe.py --port <rcon> --seconds 30 --profile`
  measures the server's UPS and the bridge's cost; `-- --ups-probe=out.json[@walk]` lowers each
  of the client's knobs in turn and prints the UPS each buys (`@governed=<s>` logs the governor).
- **No icons, flat-coloured ground, no sound**: the client didn't find your Factorio install.
  Set it in Settings → Factorio install, or pass `--factorio-data=<Factorio>/data`.
- **Hybrid single-player doesn't connect**: check that Factorio was started with
  `--enable-lua-udp 34200`, that a game is loaded (the port opens then), and that the bridge mod
  is enabled in Factorio's own mods folder; `/f3d-selftest` in Factorio's console checks the
  rest. Hybrid mode has only been played once, so a server (Single player → New game or Load
  game) is the safer choice.
- **Low frame rate on a busy base or in a forest**: Settings → Graphics → Preset sets shadows,
  ambient occlusion, level of detail, the distances and clouds together (High is the defaults;
  Medium turns ambient occlusion off, Low also halves the shadow detail and the distances). Most of
  the GPU's time in a dense view goes to ambient occlusion (about 3 ms a frame on the owner's base
  at High), trees' leaves and shadows (about 1.5 ms since they are fitted to the view).
- **Crashes, a hang on quitting or flickering with Render on a separate thread**: that mode
  (Godot's own, experimental, off by default) measured no faster here and can hang on quitting.
  Untick Settings → Graphics → Render on a separate thread and restart (it is written to
  `user://engine.cfg`), or start once with `--render-thread safe` before the `--`.

### Measuring the client

`-- --stutter-probe=<out.json>[@route]` (client/scripts/debug/stutter_probe.gd) records every
frame's time and what ran in it, then quits: `@busy` walks through the mock's `--busy` base,
`@stand` stays put, `@variants` with `--probe-variants` (or `--probe-variants=ssao off,trees
hidden`) prices render settings and hides models one kind at a time and lists the models in view.
Variants combine with `+`; `fit [quality] atlas=4096 splits=1 ...` tries sun_shadows.gd's fitting
with other settings, `legacy render` the shadows and levels of detail from before it, `lod
threshold 4`, `shadow distance 60`, `arms|items|wires|movers|terrain no shadow` and others (see
`_set_variant`). `--probe-ab=3` measures each variant three times between two "base" steps, which
cancels the graphics card's drift (compare each with the bases beside it), `--probe-timing=2,4`
sets the seconds to settle and to measure, `--probe-warmup=30` waits longer and until no chunk is
left to build, `--probe-shots=<dir>` saves a screenshot of each step. Each step's medians (frame,
GPU, render CPU, draw calls and triangles of the view and of the shadow passes, casting chunks)
are printed and kept in the JSON's `variants`. `--legacy-render` starts with the shadows and levels
of detail from before sun_shadows.gd, for a whole run.
With the separate render thread the renderer's own times are only read with
`--probe-render-times` (each read waits for that thread). `--belt-items-sync` handles belt items on
the main thread instead of a worker, for comparing.

Items on belts glide along their lanes between updates (client/scripts/world/belt_paths.gd). To
measure how far they stray from them: `python tools/belt_path_check.py layout --rcon-port <port>`
builds a test row per belt tier (both curves, a splitter, an underground, side-loading) on a running
server, `record --out truth.json` records the belts, every lane's line and every item's place each
tick, and `check truth.json drawn.json` compares where the client drew them: from a replay without
a server (`godot --headless --path client res://tests/belt_path_replay.tscn -- --truth=truth.json
--out=drawn.json --period=6`, `--straight` for straight glides, `--lead=20` for the mod's light mode)
or from the client against that server, `-- --belt-path-probe=drawn.json@20` (records 20 s after
10 s, prints belt items' main-thread and worker time, then quits; `-` as the path for the costs only).

## Tests

```
python3 -m venv .venv && .venv/bin/pip install lupa "gdtoolkit==4.*"   # once (Windows: .venv\Scripts\pip)
.venv/bin/python tools/mod_tests/test_bridge.py   # the mod, against a fake Factorio API
python3 tools/test_mock_server.py                 # the mock server, over real UDP
for f in $(find client -name '*.gd'); do .venv/bin/gdparse "$f" >/dev/null || echo "FAIL $f"; done
godot --headless --path client res://tests/ui_test.tscn   # the UI's input paths; exits 1 on failure
godot --headless --path client res://tests/addon_test.tscn   # add-ons: loading, keys, the camera, data
godot --headless --path client -s res://tests/model_load_test.gd   # after model changes: every model loads the same both ways
```

The first two check every message against the protocol (`tools/protocol.py`). `lupa` embeds Lua
5.2, the version Factorio uses. `tools/live_check.py` (above) checks the mod in real Factorio.

## Not done yet

- Fluid in pipes and machine windows (Factorio's pipe windows; the mod sends the fluids, the hover
  line shows them, storage tanks show their level), glowing heat pipes (the hover line shows the
  temperature), the "not connected" power icon (the hover line says so). Items in machines.
- Space platforms: flying up to or past a planet needs smoothing; the rocket silo's launch needs an
  overhaul. Train and platform schedules don't look and feel quite like Factorio's yet.
- Train stops are drawn in their model's colour, not the one given to them (trains wear theirs).
- Models: the electromagnetic plant and the electric furnace need work, pentapods' shells have no
  models, and several of FUE5's models haven't got their moving parts or glow back (the roboport's
  doors, the pump's pistons, the pumpjack's beam, the reactor's, lab's and beacon's glow). Ground
  clutter has no 3D foliage.
- Forests are the graphics card's biggest cost on High.
- Tips and tricks has no pictures (Factorio's tips are simulations the client can't play).
- Hybrid single-player has only been played once (on Factorio 2.1.24); Ctrl+F9's swap to a real
  Factorio window hasn't been tried.
