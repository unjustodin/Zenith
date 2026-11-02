# Models from FUE5

These models come from **FUE5** (https://github.com/FUE5BASE/FUE5), a fan remake of Factorio in
Unreal Engine 5 by **Hurricane and Nuke**, whose models and textures are licensed under
**Creative Commons Attribution-NonCommercial-ShareAlike 3.0** (CC BY-NC-SA 3.0,
https://creativecommons.org/licenses/by-nc-sa/3.0/). They are not under Zenith's MIT licence:
these files, and anything made from them, may be shared only under the same licence, with this
credit, and not for commercial use.

Changes made to the originals (`tools/models/fue5.py` and `fue5_blender.py`, from FUE5's
`Content/MyStuff/ENTITIES/STRUCTURES` and `VEHICLES` FBX files and their .jpg textures):
scaled from FUE5's units (2 to a tile) into tiles and evenly to fit the entity's footprint, turned
to face north, centred on the footprint, cut at the ground (or lifted onto it), ground decals
removed, decimated to the client's triangle budget, and every texture baked into one atlas
(embedded in the .glb as JPEG) on a new UV map.

| File | FUE5 source |
|---|---|
| `electric-furnace.glb` | `STRUCTURES/electric-furnace/static.fbx`, its fans from `animated1.fbx` |
| `rocket-silo.glb` | `STRUCTURES/rocket-silo/static.fbx` (its ring on the ground; FUE5 sinks the hatch into a hole in its ground, so the hatch is raised to just over it, cut into two doors, over a dark pit floor; the pointed pod in its south-west corner left out) |
| `locomotive.glb` | `VEHICLES/locomotive/static.fbx` (its wheel sets as moving parts) |
| `oil-refinery.glb` | `STRUCTURES/oil-refinery/static.fbx` |
| `wooden-chest.glb`, `iron-chest.glb`, `steel-chest.glb` | `STRUCTURES/<name>/static.fbx` |
| `small-lamp.glb`, `solar-panel.glb`, `lab.glb`, `beacon.glb`, `accumulator.glb` (its lightning cards left out) | `STRUCTURES/<name>/static.fbx` |
| `stone-furnace.glb`, `steel-furnace.glb`, `storage-tank.glb`, `programmable-speaker.glb` | `STRUCTURES/<name>/static.fbx` |
| `arithmetic-combinator.glb`, `decider-combinator.glb`, `constant-combinator.glb` | `STRUCTURES/<name>/static.fbx` |
| `small-electric-pole.glb`, `medium-electric-pole.glb`, `big-electric-pole.glb`, `substation.glb` | `STRUCTURES/<name>/static.fbx` |
| `roboport.glb`, `train-stop.glb`, `pump.glb`, `nuclear-reactor.glb` | `STRUCTURES/<name>/static.fbx` |
| `radar.glb` | `STRUCTURES/radar/static1.fbx`, its dish (`static2.fbx`) as the turning part |
| `gun-turret.glb` | `STRUCTURES/gun-turret/static1.fbx`, its head (`static2.fbx`) as the turning part |
| `centrifuge.glb`, `steam-turbine.glb` | `STRUCTURES/<name>/static.fbx`, their rotors and fan from `animated1.fbx` |
| `electric-mining-drill.glb` | `STRUCTURES/electric-mining-drill/static.fbx`, `animated1.fbx` (the turning drill) and `animated2.fbx` |
| `cargo-wagon.glb`, `fluid-wagon.glb` | `VEHICLES/<name>/static.fbx` (their wheel sets as moving parts) |
| `boiler*.glb`, `chemical-plant*.glb`, `pumpjack*.glb` (and `-east`, `-south`, `-west`) | `STRUCTURES/<name>/static.fbx` (the pumpjack with `animated1.fbx` at rest), turned for each direction |
| `rocket-silo-rocket.glb` | `VEHICLES/rocket/static.fbx`, stretched to Factorio's height (2.89x up, 1.40x across: FUE5's rocket is 5.9 tiles tall, Factorio's 16.9) |
| `steam-engine.glb`, `steam-engine-east.glb` | `STRUCTURES/steam-engine/static.fbx`, `animated1.fbx` (its wheels turning), `animated2.fbx` |

Sizes: each model is then matched to the size of our model it replaces (`fue5.py` `our_size`, an
axis more than 8% off, all axes alike when that is enough, never narrower than 0.9 of its footprint);
the locomotive and wagons exactly, their wheel sets moved to our bogies (1.5 and 2.5 tiles either
side). The silo (round) and the rocket keep their own. The electric poles and the substation instead
have their insulators moved onto Factorio's wire connection points (client `wires.gd`), copies of
the copper insulator making the big pole's and substation's red and green ones.

The client looks here before `client/assets/models/` (`model_library.gd` `MODEL_SUBDIRS`), so a
model here replaces ours of the same name; ours stay in the folder above and in their Blender
recipes. Delete a file here to go back to ours.
