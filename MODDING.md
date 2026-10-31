# Modding and add-ons

Zenith draws whatever the real Factorio game is running, so it already works alongside
other Factorio mods to a point. This page says what you can change or add today, what happens
with other mods, and where modding is going.

Client add-ons, small GDScript programs that run inside Zenith (a camera of your own, an
overlay, a window), have an API of their own: [docs/ADDONS.md](docs/ADDONS.md). Models work by
dropping files in the right place. Anything else means changing the project itself, which is
open source (MIT): fork it and build on it (the project doesn't take pull requests; see
[CONTRIBUTING.md](CONTRIBUTING.md)).

## What works today

| You want to... | How | Status |
|---|---|---|
| Give an entity a 3D model, or replace one | A `.glb` named after the entity's prototype | Works |
| Keep your models outside the project | Start the client with `--models=<folder>` | Works |
| Make parts of a model move | Name the nodes `anim_*` | Works, for the kinds listed below |
| Play with other Factorio mods | Turn them on in the menu's Mods window | Works; their entities are boxes until modelled |
| Add your own camera, windows, overlays or behaviour | An add-on: a folder with an `addon.json` and a script ([docs/ADDONS.md](docs/ADDONS.md)) | Works (add-on API 1) |
| Add effects or sounds to the world itself | Change the client's code | No add-on hooks yet |

## Adding a 3D model

Modellers: [docs/MODELLERS.md](docs/MODELLERS.md) is the short guide to what a model needs.

Every entity is looked up by its **prototype name**, the internal name Factorio uses (the
`name` in the mod's `data.lua`, like `assembling-machine-1` or `my-mod-big-furnace`). If a model
with that name exists, every entity of that prototype uses it. If not, the entity is drawn as a
box sized from its selection box and tinted with its map colour.

Put the model in either place:

- `client/assets/models/<prototype-name>.glb`: part of the project; Godot imports it. Models
  under a licence of their own sit in a subfolder the client looks in first (`fue5/`, FUE5's
  models: `its README`).
- Any folder of your own, loaded at runtime with `--models=<folder>`:

  ```bash
  godot --path client -- --models=C:/my-models
  ```

  The folder only fills in prototypes the project has no model for: a model in
  `client/assets/models/` with the same name wins. To try a replacement for a built-in model,
  add `--models-first`: then the folder's model wins (this also works with the downloaded
  game: `Zenith.exe -- --models=C:/my-models --models-first`).

### The rules a model has to follow

- **glTF 2.0** (`.glb` or `.gltf`), exported from Blender with +Y up.
- **1 unit = 1 tile.** A 3x3 assembler is 3 units across.
- **Origin at the centre of the footprint, at ground level.**
- **Facing north** (Blender +Y, Godot -Z). The client turns it for the other directions.
  Entities that can't rotate (chests, furnaces) keep their front to the south, as Factorio's
  sprites do.
- **The footprint matches the selection box**, with a small inset so neighbours look separate.
- **One mesh.** The client flattens each model into one mesh so it can draw thousands of them
  cheaply, so skeletons and glTF animations are ignored. Moving parts work differently (below).
- **Textures are optional.** A material may carry a base colour texture (and a
  metallic-roughness one), embedded in the `.glb`; the client draws it with mipmaps in place of
  the part colour. One material with one atlas is cheapest. Normal maps are ignored.

`python tools/models/check.py <name>` checks the name, footprint, origin, rotation and triangle
count of a model in the project.

### Matching Factorio's look

The project's rule for its own models is that they should look like Factorio: matching the
entity's sprite in shape, proportions, colour and wear. The same goes for models contributed
back. A model in your own folder can look however you like.

Surfaces are drawn with the project's Factorio material, which adds weathering (lightly, over a
model's own textures). How a surface
weathers depends on words in its **material name** in the glTF (`glass`, `wood`, `rubber`,
`leaf` and so on; the list is `MATERIAL_CLASSES` in `client/scripts/world/model_library.gd`). Materials named
`belt_surface` scroll like a moving belt; emissive materials glow only while the machine works.

### Moving parts

Name a node `anim_<kind>` and put its origin on the point it turns around. The client cuts it
out of the static mesh and moves it itself:

| Node name | What it does |
|---|---|
| `anim_spin_<anything>` | Spins while the machine works (known names like `anim_spin_drill` have their own speeds, others a default) |
| `anim_glow_<anything>` | Glows while the machine works, dark when idle |
| `anim_turret_head` | Turns where the game says the turret aims (`ts` from the bridge) |
| `anim_door_n`, `anim_door_s`, `anim_gate_door` | Slide open (roboport hatch, gate) |
| `anim_upright_*` | Keeps facing north whichever way the entity faces |
| `anim_lit_green`, `anim_lit_charge`, ... | Shown and lit while the entity's reported state matches (signals, accumulators) |
| `anim_hatch_e`, `anim_hatch_w` | Slide apart while a robot is close (logistic chests) |
| Kinds listed in `CYCLES` | Slide, swing or spin once per loop of Factorio's animation while the machine works (pistons, cranks, arms) |

The full table, with speeds and which models use each, is in
`client/assets/models/README.md`.

### Variants

Some entities use a different model depending on their state, such as curved belts
(`<name>-curve-left.glb`), underground entrances and exits (`<name>-input.glb`,
`<name>-output.glb`), pipe shapes (`pipe-corner-up-right.glb`), wall connections, and a model
per direction drawn unturned (`<name>-east.glb`, `-south`, `-west`) for the entities in
`FACING_MODELS` (boiler, chemical plant, inserters...), where Factorio's four pictures are separate
renders. A modded
belt or pipe gets its curves and shapes the same way, by name. The list is in
`client/assets/models/README.md`.

## Playing with other Factorio mods

The main menu's **Mods** window lists the mods in the server's mods folder, the same way
Factorio's does. Turn them on there, and the headless game the menu starts loads them. The
bridge mod is always on.

What happens to a mod's content today:

- **Its entities work in the game.** Factorio runs them, so they work as the mod intends.
- **They are drawn as boxes** sized from their selection box and coloured with their map colour,
  until someone makes a model for them.
- **Their icons are plain coloured squares.** The client finds icons through an index of the
  base game and Space Age, so a mod's icons aren't found yet.
- **Their screens are picked by Factorio type**, so a modded furnace gets the furnace screen and
  a modded assembler the assembler screen. Mods that open their own GUI in Factorio don't show it here,
  because there is no player for Factorio to draw it for.
- **Big overhaul mods haven't been tried.** Small mods that add entities of normal types are the
  most likely to work.

Testing with a mod is the most useful thing anyone can do right now: report what breaks.

## Where modding is going

The goal is that mod authors can ship 3D content for their own mods, and players can add their
own ideas to the client, without forking the project. Client add-ons are the first part of that
and work today ([docs/ADDONS.md](docs/ADDONS.md), add-on API 1: the camera, keys, windows, the
world read-only, events, frames, lighter updates and data); more hooks come as add-ons need them.

Planned, roughly in order:

1. **Model packs.** A folder (or zip) of models, loaded alongside the built-in ones, with a small
   manifest saying which mod they're for and which version. A Factorio mod could carry its own
   pack.
2. **Icons from any mod.** Reading every mod's icons from the game's prototype data, so modded
   items show their real icons.
3. **Animations.** More `anim_*` kinds, and parts driven by what the machine is doing (its
   recipe, its fluid levels, its circuit signals).
4. **Effects and sounds.** Smoke, sparks and sounds for modded machines, from the mod's own
   prototypes, as the client already does for the base game, and add-on hooks for them.
