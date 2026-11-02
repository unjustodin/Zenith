# Zenith

Play your real Factorio game in 3D, with an angled camera close to your
character and a 3D model for every entity.

This isn't a remake. Factorio itself still runs the game, unchanged, as a headless server with
no window. A bridge mod streams the live game state to a separate 3D client built in Godot 4.
The client draws it and sends your input back. Saves, research, belts, trains, biters and Space
Age all work the way the real game does them, because the real game is the one doing them.

You need your own copy of Factorio 2.1. Space Age is supported but not required.

## Download

Get the latest release from the [Releases page](../../releases/latest):

- **Zenith-<version>-windows.zip** or **Zenith-<version>-linux.zip**: the game. Unzip it anywhere
  and start `Zenith.exe` (Windows) or `Zenith.x86_64` (Linux); `START HERE.txt` inside says the rest.
  The bridge mod and the server scripts come with it.
- **factorio-3d-bridge_<version>.zip**: the bridge mod on its own, for a server you run yourself.
- **cinematic-camera_<version>.zip**: an optional camera add-on (free camera, tracking shots,
  timelapses, recording). Drop the zip, as it is, into Zenith's `addons` folder.

## What works today

- **Your own saves.** Load any save from the main menu: the client copies it, starts headless
  Factorio and takes over your save's character, with its inventory, armour and logistic
  requests. Your original save is never touched.
- **Factorio's interface, rebuilt in 3D.** The inventory, crafting, machine screens, research,
  map and minimap, blueprints and planners, the circuit network, train schedules, logistics,
  Factoriopedia, alerts and tooltips. They are drawn with Factorio's own GUI art and fonts from
  your install, and use Factorio's hotkeys.
- **A 3D model for every entity** in the base game and Space Age, over 400 files with their variants. Belts,
  inserters, walls, logistic chests, the character and biters are converted from the 3D-printable
  models Wube released. 39
  base-game buildings and vehicles (assemblers, furnaces, chests, power, oil, trains and more) use
  the textured models of [FUE5](https://github.com/FUE5BASE/FUE5), the fan remake of Factorio in
  Unreal Engine 5. Everything else is modelled to match Factorio's own sprites, and coloured from them.
- **The world, live.** Items ride the belts, inserters swing, machines animate, trains and cars
  drive, biters attack and turrets fire. Day and night with working lamps. Factorio's own terrain
  textures, water, cliffs, decoratives, sky and clouds for each planet, and Factorio's sounds
  played by its own rules.
- **Space Age.** Space platforms, travel between planets, Vulcanus, Fulgora, Gleba and Aquilo,
  quality and spoilage.

Press **F6** at any time to jump to Factorio's own camera angle for comparison.

## What still needs work

This is an early release, and it still has rough edges:

- Some models still differ from Factorio's sprites in shape or colour (the inventory in
  [docs/ASSET-INVENTORY.md](docs/ASSET-INVENTORY.md) says which), and several animations haven't
  been watched against a real game yet.
- Big bases are heavy. Zenith holds the game at 60 UPS by asking for less when it has to, and
  walking around a large save is mostly smooth now, but dense forests and long view distances
  still cost the graphics card a lot.
- FUE5's models follow older Factorio designs in places, and a few of their moving parts aren't
  back yet.
- The models will keep improving: I'm working with 3D modellers to refine them a few at a time,
  worst first, and each release ships the ones finished since the last.
  [docs/MODELLERS.md](docs/MODELLERS.md) is the guide for anyone making them.
- Single-player "hybrid" mode, where the 3D client attaches to a normal Factorio window, has
  been played once, side by side, but not tried much yet.
- It's only been tested on Windows 11 with Factorio 2.1.23.

Known bugs are on the issue tracker.

## Quick start

Players: [download a release](../../releases/latest), unzip it and start Zenith. Its main menu
makes or loads a world and starts Factorio for you; [docs/USER-GUIDE.md](docs/USER-GUIDE.md) has the
rest.

From the source: open `client/project.godot` in Godot 4.4+ and press F5 for the same main menu. With
no Factorio at hand, run `python3 tools/mock_server.py` first for a fake world.
[docs/RUNNING.md](docs/RUNNING.md) has the details, the tests and running a server yourself.

## Why I made this

I'm a software developer, and I like building things that push at what should be possible.
The idea came from the Factorio fan remake in Unreal Engine 5 and from mods that give other games
a new camera. I wanted that feel with the real Factorio underneath, so it would be the real game
and not a lookalike.

I thought it would be a renderer. Instead it became most of a game client: Factorio can't
draw 3D and mods can't touch its renderer, so every menu, every hotkey, every screen and every
interaction had to be rebuilt from scratch. On top of that, every entity needed a 3D model.

## How it was made, including AI

I want to be upfront about this, because I know AI use is a sore point for a lot of people.

**Most of the code and models were written by AI coding agents that I directed.** The main
one was Anthropic's Claude, through Claude Code. OpenAI's ChatGPT did a pass on model detail
and animations, and Google's Gemini (through the Antigravity CLI) built one UI feature.

My part:
- the idea, the architecture decisions and the art direction;
- deciding what to build, in what order, and what "done" means;
- playing it on my own saves and writing up what was wrong, then checking the fixes;
- reviewing the models against Factorio's sprites.

None of it is generated blind and shipped. Every feature has to pass:
- tests of the mod against a strict fake of Factorio's API;
- a mock server and protocol validator that check every message;
- a UI test that clicks through the interface (nearly 1,000 checks);
- a checker for every model's scale, origin and triangle budget;
- a live check against a real Factorio 2.1 server (361 checks on the last full run).

All of these run on every push.

The art has one rule: **it should look like Factorio, not like AI art.** The models are built
from code in Blender (the scripts are in `tools/models/`), not generated by image-to-3D, and
each one is compared side by side with Factorio's own sprite. Where Wube released a
real 3D model, that comes first. The FUE5 models are the work of that project's own modellers,
Hurricane and Nuke, converted to Zenith's scale and kept under their licence.

## Where it's going

**Open source, one maintainer.** The code is MIT-licensed and you're welcome to fork it, but
Zenith stays a personal project: I don't take pull requests or feature requests. Bug reports are
welcome. [CONTRIBUTING.md](CONTRIBUTING.md) has notes for working on a fork; you don't need
Factorio for most client work, since a mock server plays a fake game.

**Your own models, add-ons and mods.** Today:
- Any `.glb` named after a prototype replaces that entity's model, from the project or from
  your own folder (`--models=/path/to/folder`, and `--models-first` to replace built-in ones).
  Models may bring their own textures.
- Add-ons: small GDScript programs in a folder of their own that add to the client without
  forking it, through one versioned API (the camera, keys, windows, the world read-only, events).
  The first is a cinematic camera for filming (free camera, timelapses, tracking shots, paths).
  [docs/ADDONS.md](docs/ADDONS.md) is for add-on authors.
- The menu's Mods window runs other Factorio mods on the server. Their entities appear as boxes
  sized and coloured from the game until someone models them. Nobody has tried a big overhaul
  mod yet.

Next for modding: model packs for other mods, their icons, and more hooks as add-ons need them.
[MODDING.md](MODDING.md) covers what works today, how other mods behave, and what's planned.

Also planned: smoother play in forests and at long view distances, and the last models that
still differ from their sprites.

## Docs

- [docs/USER-GUIDE.md](docs/USER-GUIDE.md): for players: install, first game, controls, settings
- [docs/RUNNING.md](docs/RUNNING.md): setup, controls, troubleshooting
- [ARCHITECTURE.md](ARCHITECTURE.md): how the pieces fit together, for anyone reading the code
- [docs/PROTOCOL.md](docs/PROTOCOL.md): messages between the mod and the client
- [docs/PLAN.md](docs/PLAN.md): the approach, where each part stands, the art pipeline and risks
- [docs/ASSET-INVENTORY.md](docs/ASSET-INVENTORY.md): every entity's 3D model, family by family
- [CONTRIBUTING.md](CONTRIBUTING.md): no pull requests; notes for working on a fork
- [MODDING.md](MODDING.md): your own models, other Factorio mods, and add-ons
- [docs/ADDONS.md](docs/ADDONS.md): writing add-ons for the client
- [docs/MODELLERS.md](docs/MODELLERS.md): making 3D models for Zenith (what each model needs, belts, pipes and other pieces)

```
mod/factorio-3d-bridge/   Factorio mod: world streaming + a character the client controls
client/                   Godot 4 project: the 3D client
server/                   scripts to run headless Factorio with the mod and UDP enabled
tools/                    mock server (no Factorio needed), protocol checks, tests, model scripts
docs/                     guides, protocol, plan, asset inventory
```

## Licence

The code is MIT-licensed ([LICENSE](LICENSE)). You need your own copy of Factorio: the client
reads Factorio's graphics, sounds and fonts from your install at runtime, and none of Wube's
assets are in this repository. Models converted from Wube's printable release keep Wube's
non-commercial licence, and those from FUE5 keep theirs (CC BY-NC-SA 3.0); see
[CREDITS.md](CREDITS.md).

This is an unofficial fan project. "Factorio" is a trademark of Wube Software; this project is
not made, endorsed or supported by Wube.
