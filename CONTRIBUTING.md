# Contributing

Zenith is a personal project, and I'm keeping it that way for now: I don't take pull requests or feature
requests. Bug reports are welcome in the [issue tracker](https://github.com/unjustodin/Zenith/issues).

> The code isn't published yet: this repository has the documentation only for now.

You're free to fork it. The code is MIT-licensed, so a fork can go wherever you like (Wube's
printable models and FUE5's models keep their own non-commercial licences: see [CREDITS.md](CREDITS.md)). The rest
of this page is for anyone working on a fork.

## Working on the code

Zenith draws a running Factorio game in 3D: Factorio stays the simulation (normally a headless
server), a bridge mod streams its state over localhost UDP, and a Godot 4 client draws it.
[docs/RUNNING.md](docs/RUNNING.md) gets it running and [ARCHITECTURE.md](ARCHITECTURE.md) explains how
the pieces fit together.

- You can work on most of the client without Factorio: `python tools/mock_server.py` plays a fake
  game that speaks the same protocol.
- Run the tests after a change (`./quickstart.sh test` runs them all: the bridge mod against a fake
  Factorio, the mock server, a GDScript parse and the client's UI test), and try it against real
  Factorio, not only the mock, before you rely on it. They need a venv in `.venv` with `lupa` and
  `gdtoolkit==4.*`.
- The protocol lives in five places (mod, client, mock server, validator, PROTOCOL.md): change
  them together.

## Art

Models should look like Factorio: convert Wube's printable model where one exists, otherwise
match Factorio's own sprites as closely as you can (see `client/assets/models/README.md`).
Models for other Factorio mods and the client's add-ons are in [MODDING.md](MODDING.md).

**Never commit anything from Factorio's install** (graphics, sounds, fonts, extracted sprite
frames, comparison renders). The client loads them from each player's own copy at runtime;
keep references in the git-ignored `art-src/`. See [CREDITS.md](CREDITS.md).
