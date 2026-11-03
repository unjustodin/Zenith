# Contributing

Zenith is a personal project, and I'm keeping it that way for now: I don't take pull requests or feature
requests. Bug reports are welcome in the issue tracker.

You're free to fork it. The code is under the GPL-3.0: a fork can go wherever you like, as long as
what you share stays open source under the GPL too ([LICENSING.md](LICENSING.md)). Wube's printable
models and FUE5's models keep their own non-commercial licences, and the logo and icon are David's,
so a fork needs its own unless he agrees: see [CREDITS.md](CREDITS.md). The rest
of this page is for anyone working on a fork.

## Working on the code

Zenith draws a running Factorio game in 3D: Factorio stays the simulation (normally a headless
server), a bridge mod streams its state over localhost UDP, and a Godot 4 client draws it.
[docs/RUNNING.md](docs/RUNNING.md) gets it running and [ARCHITECTURE.md](ARCHITECTURE.md) explains how
the pieces fit together.

- You can work on most of the client without Factorio: `python tools/mock_server.py` plays a fake
  game that speaks the same protocol.
- Run the tests after a change (the bridge mod against a fake Factorio, the mock server, a GDScript
  parse, the client's UI test and the add-on test; [docs/RUNNING.md](docs/RUNNING.md) lists the
  commands), and try it against real Factorio, not only the mock, before you rely on it. They need
  a venv in `.venv` with `lupa` and `gdtoolkit==4.*`.
- The protocol lives in five places (mod, client, mock server, validator, PROTOCOL.md): change
  them together.

## Add-ons: adding to Zenith without forking it

Most ideas don't need a fork. An add-on is a small GDScript program that runs inside Zenith: a
camera of your own, an overlay, a window, a recorder. Zenith gives it one versioned API (add-on
API 1.1): the camera (take it and hand it back), keys that show in Settings → Controls, settings
on its page in the Add-ons menu, the world read-only (trains, players, buildings, moving things),
events (a train arriving, a rocket launching, a fight starting), hiding the interface, saving
frames, asking the bridge for lighter updates, and data kept per save.

- **Making one:** a folder with an `addon.json` (its id, name, version, the API version it needs)
  and an entry script. [docs/ADDONS.md](docs/ADDONS.md) is the guide, with every call and an example.
- **Trying it:** start Zenith with `--addons=<your folder>` while you work on it; the Add-ons menu
  shows it, its settings and keys, and why it didn't load if something's wrong.
- **Sharing it:** zip the folder. Players drop the zip, as it is, into Zenith's `addons` folder
  (beside `Zenith.exe`, or in Zenith's user folder); no unpacking. An add-on lives in its own
  repository, under your own licence, and needs nothing from this one. The
  [Cinematic camera](https://github.com/unjustodin/Zenith-Cinematic-Camera) add-on is the worked example.
- **If the API can't do what you need,** a fork is the way for now; say what was missing in a bug
  report so later versions of the API can cover it.

## Other Factorio mods

Zenith draws whatever the real game runs, so Factorio mods work alongside it:

- **Playing with mods:** the main menu's Mods window turns them on, and the server it starts loads
  them with the bridge mod. Their entities work as their mods intend, because Factorio runs them.
- **How they look:** a modded entity is a box sized from its selection box until it has a model,
  and its icons are plain squares for now. Its screens are picked by its Factorio type (a modded
  furnace gets the furnace screen); a mod's own GUI doesn't show in Zenith.
- **Models for a mod's entities:** name a `.glb` after the entity's prototype and load the folder
  with `--models=<folder>` ([docs/MODELLERS.md](docs/MODELLERS.md) has the rules). Packs a mod can
  ship itself are planned ([MODDING.md](MODDING.md) says what's next).
- **Testing with mods is the most useful thing to report:** what breaks, and with which mods.

## Art

Models should look like Factorio: convert Wube's printable model where one exists, otherwise
match Factorio's own sprites as closely as you can (see `client/assets/models/README.md`).
Models for other Factorio mods and the client's add-ons are in [MODDING.md](MODDING.md).

**Never commit anything from Factorio's install** (graphics, sounds, fonts, extracted sprite
frames, comparison renders). The client loads them from each player's own copy at runtime;
keep references in the git-ignored `art-src/`. See [CREDITS.md](CREDITS.md).
