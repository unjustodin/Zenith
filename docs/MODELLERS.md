# Making models for Zenith

> The code isn't published yet: this repository has the documentation only for now. This
> page shows how it will work once Zenith is out.

A guide for 3D modellers. Zenith draws every Factorio entity with a 3D model; this page says what a
model needs so the game can use it. The full technical reference, with every table, is
`client/assets/models/README.md`.

## The look

Models should look like Factorio. Match Factorio's own sprites in shape, proportions, colour and
wear: the high-resolution sprite sheets are in your Factorio install under
`data/base/graphics/entity/` (and `data/space-age/...`). Look at the sprite from Factorio's camera
angle (about 45 degrees down, from the south) and make the model read the same from there. Don't
redistribute Factorio's pictures: look at them, don't put them in your files.

## Every model

- **File:** one glTF file per entity, `.glb`, named after Factorio's internal name for it:
  `assembling-machine-2.glb`, `storage-tank.glb`. The names are the ones in Factorio's prototypes
  (the same as in `/c` commands and on the wiki's "internal name" line).
- **Scale and origin:** 1 unit = 1 tile. The origin is the centre of the entity's footprint, on
  the ground. A 3x3 machine fills about 3 x 3 units, with a small inset so neighbours read as
  separate (belts and walls go edge to edge so lines join up).
- **Facing:** the model faces north: Blender +Y (export with +Y up), Godot -Z. The game turns it
  for other directions. Things that can't turn (chests, furnaces, labs) keep their front to the
  south, towards the camera, as Factorio's sprites do.
- **Triangles:** keep within the budget `tools/models/check.py` reports: around 10,000 for a typical
  machine, less for small things, up to 16,000-20,000 for the biggest. The game draws thousands of
  buildings at once, so fewer is better.
- **Materials and textures:** a base colour texture (and optionally a roughness/metal one: glTF's
  green = roughness, blue = metal), embedded in the `.glb`, read through the first UV map. One
  material with one texture atlas per model is cheapest. Keep the material's base colour white.
  Normal maps are ignored for now. A model without textures is coloured from its materials'
  colours.
- **One mesh:** the game flattens each model into one mesh for speed, so skeletons and animations
  in the file are ignored. Anything that moves is a separate object (below).

## Moving parts

A part that moves is a separate object named `anim_<kind>`, with its origin at the point it turns
about. The game moves it from the game's state (working, aiming, a robot nearby...). Some kinds:

| Name | What the game does with it |
|---|---|
| `anim_spin_fan`, `anim_spin_rotor`, `anim_spin_drill` | spins about its own up axis while the machine works |
| `anim_spin_flywheel` | spins about its east-west axis while working |
| `anim_turret_head` | turns and aims where the turret aims; barrels point north at rest |
| `anim_glow_<style>` | glows while working, dark when idle (`fire` flickers, others pulse) |
| `anim_door_n`, `anim_door_s`, `anim_hatch_e`, `anim_hatch_w` | slide open (roboport doors, logistic chest hatches) |
| `anim_lit_green` / `_yellow` / `_red` | shown and lit by a signal's colour |

The full list, with axes and timings, is in the models README ("Moving parts"). If a model needs a
kind of movement that isn't there, ask: new kinds are added in the game's code.

## Entities built from several models

Some entities are drawn from a set of pieces the game picks between. Deliver every piece, named
exactly:

| Entity | Files | Notes |
|---|---|---|
| Transport belt | `transport-belt.glb`, `transport-belt-curve-left.glb`, `transport-belt-curve-right.glb` | Everything that moves with the belt (the slats) uses a material named `belt_surface`: the game scrolls it at each tier's speed and paints Factorio's chevrons on it. The frame uses `tier_paint`, which the game recolours for fast, express and turbo. Curves face their output: `-curve-left` takes items in from the west edge and out of the north edge. Items ride on the belt's top surface, so its height shows. |
| Underground belt | `underground-belt-input.glb` (entrance), `underground-belt-output.glb` (exit) | Both modelled as Factorio's picture for "north": the hood's mouth opens south. The game turns the exit round. |
| Splitter | `splitter.glb` | Two tiles wide (east-west). Its belts use `belt_surface`; gears and cranks are `anim_` parts. |
| Pipe | 16 files, `pipe-<shape>.glb`, one per Factorio pipe picture: `straight-vertical`, `straight-horizontal`, `corner-up-right`, `t-left`, `cross`, `ending-down`, `straight-vertical-single`, ... | The game picks one by which neighbours connect. "up" is north, as in Factorio's sprite names. Heat pipes are the same 16 shapes, `heat-pipe-<shape>.glb`. |
| Stone wall | `stone-wall-<sides>.glb` named by the sides it joins (`pylon`, `n`, `ew`, `es`, `nesw`, ...) and `stone-wall-fill.glb` | The fill block sits in the middle of a 2x2 group of walls. |
| Rails | `straight-rail`, `half-diagonal-rail`, `curved-rail-a`, `curved-rail-b` and their `elevated-` versions, each as `<name>.glb` (direction north) and `<name>-ne.glb` (north-east) | The game turns them in quarter turns for the other directions. |
| Inserters | the base: `<name>.glb`, `-east`, `-south`, `-west`; the arm: `inserter-arm-<family>-upper`, `-hand-open`, `-hand-closed` | The game stretches the arm pieces from the base's shoulder to the inserter's reach. Families: `basic`, `long`, `bulk`, `stack`. |
| Boiler, steam engine, offshore pump, pipe-to-ground, valves, burner drill, pumpjack, chemical plant | `<name>.glb` (north), `<name>-east`, `-south`, `-west.glb` | Factorio drew each direction separately, so each gets its own model, drawn unturned. |
| Cargo bay | `cargo-bay.glb` plus edge pieces (`cargo-bay-wall-n`, `cargo-bay-corner-nw`, `cargo-bay-inner-nw`, ...) | Bays join each other and the hub like Factorio's tileset; see the models README. |
| Biter and spitter corpses | `<name>-corpse.glb` and `-corpse-1` to `-3` | Factorio's four falls. |

**Electric poles:** wires attach at Factorio's own connection points, so the insulators must sit
there (the points are listed in `client/scripts/world/wires.gd`).

**Creatures and the character** are rigged on the game's own skeleton and bend in the shader. Talk
to the maintainer before starting one.

## Trying a model in the game

1. Put your `.glb` files in a folder of your own.
2. Start Zenith with `--models=<that folder> --models-first` (from the command line, or the
   shortcut's target). Your models then replace the built-in ones of the same name.
3. Look at it from the default view and from Factorio's view (F6), beside the real entities.

With the source code, `python3 tools/models/check.py <name>` checks the name, footprint, origin,
facing and triangle budget, and `tools/models/review.py <name>` takes screenshots in the game.

## Licence

Zenith is open source (MIT). Before you send models, agree with the maintainer how they're
licensed: under MIT with the rest, or under a licence of your own in a folder of their own with a
README and a credit, as FUE5's models are (`client/assets/models/fue5/`, CC BY-NC-SA 3.0).
Everyone credited is listed in [CREDITS.md](../CREDITS.md).
