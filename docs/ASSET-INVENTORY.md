# Asset Inventory: 2D sprites → 3D models

Every visible Factorio entity that needs a 3D model, grouped into **families** so that tier
variants share one mesh and differ only by tint or material. This list was built from Wube's
public prototype definitions for **Factorio 2.1.23** (base, Space Age, Elevated Rails).
For the authoritative list, including other mods, run `factorio --dump-data` and read
`script-output/data-raw-dump.json`.

Conventions, workflow and budgets are in [PLAN.md §4 and §6](PLAN.md#6-converting-the-2d-sprites-into-3d-models).
The models are built by `tools/models/` (see `client/assets/models/README.md`): Wube's printable
models converted by `wube.py` where they exist, the rest built in Blender from Factorio's sprites.
For 39 base-game entities the client draws the FUE5 fan project's textured models instead (my
choice; `fue5.py`, `client/assets/models/fue5/`, CC BY-NC-SA 3.0): they are marked **FUE5** below.
Ours stay in `client/assets/models/` beside them; FUE5's outlines follow the sprites more loosely
(its README gives each one's overlap, ours and theirs).
Each model is scored against its sprite in every direction by silhouette overlap (`compare.py`
and the scorers beside it).

Nearly every family has a real model now: `client/assets/models/` holds 437 `.glb` files
(directions, belt curves, wall pieces, corpses and poses count separately), `fue5/` 49 more for
those 39 entities, and `items/` 198 small item models. Crude oil is the one entity still without a
model fitted to its sprite.

**Status legend:** `todo` → `blockout` → `modelled` → `textured` → `animated` → `in-client`

- `blockout`: procedural or unchecked against the sprite.
- `modelled`: the shape matches Factorio's sprite or Wube's model.
- `textured`: colours sampled from the sprite, but they still differ in places.
- `animated`: moves the way Factorio's animation does (drawn in the client too).
- `in-client`: shape and materials match, checked in the client.

| Tier | Meaning | Families |
|---|---|---|
| P0 | On screen in the first hour | 26 |
| P1 | Mid-game base | 12 |
| P2 | Late base game | 6 |
| ER | Elevated Rails | 1 |
| P3 | Space Age | 27 |
| | **Total** | **72**: 42 in-client, 21 animated, 7 textured, 2 modelled |

Models are flattened into one mesh for instanced drawing, so glTF skeletons and clips aren't
used (FUE5's moving parts are cut out of its animated files by bone when converted). Moving parts
are separate `anim_*` nodes that the model shader turns, slides or lights from the machine's state;
creatures' limbs move in the material's vertex shader; turrets, vehicles and robots are driven
from what the mod reports.

---

## P0: First hour

| Family | Prototypes | Models | Technique | Status |
|---|---|---|---|---|
| Character | `character` | 1 rig (+ gun, corpse) | Wube's print on the client's own rig: idle, run (Factorio's 4.77 tiles a loop), mine, shoot; flashlight | animated |
| Transport belt | `transport-belt`, `fast-transport-belt`, `express-transport-belt` | 1 (straight, left and right curves) | Slats and the tier's chevrons scroll in the shader | in-client (Wube's belt and curves; fast, express and turbo in their own paint) |
| Underground belt | `underground-belt`, `fast-underground-belt`, `express-underground-belt` | 1 (entrance, exit) | Belt inside scrolls, tier paint | in-client (Wube's entrance and exit; higher tiers in their own paint) |
| Splitter | `splitter`, `fast-splitter`, `express-splitter` | 1 | Belts scroll; gear wheels and cranks turn on its 32-frame loop | in-client (rebuilt from its four sprites; higher tiers in their own paint) |
| Inserters | `burner-inserter`, `inserter`, `long-handed-inserter`, `fast-inserter`, `bulk-inserter` | Wube's platform, one per direction; arm pieces per family (basic, long, bulk) | The client swings the upper arm and hand to the hand position the mod reports, stretched to the reach; the hand closes on an item | animated |
| Chests | `wooden-chest`, `iron-chest`, `steel-chest` | 3 | none | in-client (**FUE5**; Wube's, 0.95-0.97, kept beside them) |
| Mining drills | `burner-mining-drill`, `electric-mining-drill` | 2 (burner drill one per direction) | Auger turns while working; the burner drill's gears rock, rod bobs, fire flickers | modelled (burner drill 0.74-0.80; electric drill **FUE5**, its drill turning from FUE5's own file) |
| Furnaces | `stone-furnace`, `steel-furnace` | 2 | Fire flickers while working | in-client (**FUE5**; Wube's kept beside them) |
| Assemblers | `assembling-machine-1`, `assembling-machine-2`, `assembling-machine-3` | 3 | Parts turn while crafting | animated (1 is **FUE5**, still for now; 2 and 3 rebuilt from their sprites) |
| Steam power | `offshore-pump`, `boiler`, `steam-engine` | 3 (boiler and offshore pump one per direction, steam engine two) | Boiler fire, flywheel spin, pump pistons | in-client (boiler and steam engine **FUE5**, FUE5's one model turned per direction; its steam engine's wheels turn) |
| Electric poles | `small-electric-pole`, `medium-electric-pole`, `big-electric-pole`, `substation` | 4 | Wires hang between Factorio's connection points | modelled (all four **FUE5**; wires against its insulators not checked yet) |
| Pipes | `pipe`, `pipe-to-ground` | Pipe kit of 16 pieces, pipe-to-ground one per direction | Piece chosen by connections (`extra.pc`, from the mod) | in-client |
| Lab | `lab` | 1 | Lights pulse while researching | in-client (**FUE5**; its glow not back yet) |
| Gun turret | `gun-turret` | 1 | Head turns to the mod's real aim, raises and folds, recoils, muzzle flash (`turrets.gd`) | textured (**FUE5**, its head as the turning part) |
| Wall & gate | `stone-wall`, `gate` | Wall pieces per connection shape; gate | Piece chosen by neighbours; the gate opens for the character or a friendly vehicle | in-client (Wube's wall pieces) |
| Car | `car` | 1 | Turret part follows its aim | textured |
| Ores | `iron-ore`, `copper-ore`, `coal`, `stone` | 1 nugget set × 4 materials, 3 richness stages | Instanced, stage picked by the tile's amount | in-client |
| Trees | `tree-01` … `tree-09` (+ colour variants) | 9 | Leaf-card crowns cut ragged in the shader; no wind yet | in-client (`-red`/`-brown` variants are the same models in their own colours) |
| Dead trees | `dead-dry-hairy-tree`, `dead-grey-trunk`, `dead-tree-desert`, `dry-hairy-tree`, `dry-tree` | 5 | none | textured (the sprites' fine twigs aren't modelled) |
| Rocks | `big-rock`, `huge-rock`, `big-sand-rock` | 3 | none | in-client |
| Cliffs | `cliff` (+ `cliff-vulcanus`, `cliff-gleba`, `cliff-fulgora`) | 5 pieces per planet (sides, outer, inner, exit, entrance), turned for the 20 orientations | none | in-client: Nauvis shaped from the sprites seen from the low side; the planets' layered versions are blockouts |
| Fish | `fish` | 1 | Tail sway (ours: Factorio's fish are still pictures) | in-client |
| Biters | `small-biter`, `medium-biter`, `big-biter`, `behemoth-biter` | 1 (Wube's print, scaled and tinted per tier), attack pose, 4 corpses | Limbs move in the vertex shader; bites timed to the attack cooldown; dying biters fall into one of four corpse poses fitted to the sprites | animated |
| Spitters | `small-spitter`, `medium-spitter`, `big-spitter`, `behemoth-spitter` | 1 (Wube's print), attack stance, 4 corpses | As biters | animated |
| Spawners | `biter-spawner`, `spitter-spawner` | 1 + corpse | Pulses at Factorio's 0.9 Hz | animated |
| Worms | `small-worm-turret`, `medium-worm-turret`, `big-worm-turret`, `behemoth-worm-turret` | 1 (rebuilt from the sprites) + corpse | Folds, rises and lunges at its target at the prototype's speeds; falls over as it dies | animated |
| Crash site | `crash-site-spaceship`, `crash-site-spaceship-wreck-big-1/2`, `-medium-1/2/3`, `-small-1…6`, `crash-site-chest-1/2` | 14 | none | textured (the ship's seams read partly as cracks; some olive paint left) |

## P1: Mid-game base

| Family | Prototypes | Models | Technique | Status |
|---|---|---|---|---|
| Oil | `pumpjack`, `oil-refinery`, `chemical-plant`, `storage-tank`, `pump`, `crude-oil` (resource) | 6 (pumpjack and chemical plant one per direction) | Pumpjack beam rocks, refinery flare, pump pistons | pumpjack, oil-refinery, chemical-plant, storage-tank, pump animated, all five **FUE5** (their beam, pistons, gears and lamp not back yet); crude-oil blockout (procedural, not fitted) |
| Electric | `solar-panel`, `accumulator`, `electric-furnace`, `small-lamp` | 4 | Lamp light; accumulator glows while charging and arcs while discharging (state from the mod); the electric furnace's fans turn | animated, all four **FUE5** (the accumulator's sparks not back yet) |
| Logistic network | `roboport`, `logistic-robot`, `construction-robot` | 3 | Robots' thrusters swing and glow, antenna lamp red with cargo, construction sparks; robots drawn together and animated in the shader | animated (roboport **FUE5**, its doors and charging lights not back yet) |
| Logistic chests | `active-provider-chest`, `passive-provider-chest`, `storage-chest`, `buffer-chest`, `requester-chest` | 1 + 5 colours | Hatch slides open while a robot is over the chest | in-client (Wube's chest) |
| Circuit network | `arithmetic-combinator`, `decider-combinator`, `selector-combinator`, `constant-combinator`, `power-switch`, `programmable-speaker`, `display-panel` | 7 | Indicator lights; the power switch's contact closes | in-client (the three combinators and the speaker **FUE5**) |
| Valves | `one-way-valve`, `overflow-valve`, `top-up-valve` | 1 per direction | none | in-client |
| Rails | `straight-rail`, `half-diagonal-rail`, `curved-rail-a`, `curved-rail-b` | 1 per piece, with a diagonal variant (+ legacy rails) | none | in-client |
| Rail props | `rail-signal`, `rail-chain-signal`, `train-stop` | 3 | Signals placed per direction as Factorio draws them; lamps lit by the mod's reported colour | animated (train stop **FUE5**) |
| Trains | `locomotive`, `cargo-wagon`, `fluid-wagon` (+ `infinity-cargo-wagon`) | 4 | Orientation from the mod; wheels roll; locomotive headlights at night | textured (locomotive, cargo and fluid wagons **FUE5**) |
| Defence | `laser-turret`, `flamethrower-turret`, `land-mine`, `tank` | 4 | Turret heads aim at the mod's real targets: the laser head rises, the flamethrower's nozzle slides out; the tank's turret aims, its treads slide and wheels roll | in-client |
| Combat robots | `defender`, `distractor`, `destroyer` | 3 | Hover | in-client |
| Radar & beacon | `radar`, `beacon` | 2 | Dish spins, beacon glow | in-client (both **FUE5**; the beacon's glow not back yet) |

## P2: Late base game

| Family | Prototypes | Models | Technique | Status |
|---|---|---|---|---|
| Nuclear | `nuclear-reactor`, `heat-pipe`, `heat-exchanger`, `steam-turbine`, `centrifuge`, `uranium-ore` | 4 + heat pipe kit of 17 pieces; uranium ore at 3 richness stages | Heat glow; heat pipe piece chosen by neighbours; rotors turn | animated (reactor, centrifuge and steam turbine **FUE5**; the reactor's glow not back yet) |
| Rocket | `rocket-silo`, `rocket-silo-rocket`, `cargo-pod`, `cargo-landing-pad` | 4 | Silo doors open with a rocket ready; launch and the ride up; cargo pod panels and thruster; landing pad hatch | in-client (rocket silo **FUE5**, its hatch cut into two doors; the rocket stays ours) |
| Artillery | `artillery-turret`, `artillery-wagon` | 2 | Cannon turns and recoils, muzzle flash | in-client |
| Spidertron | `spidertron` | 1 body, legs in two parts | Each leg bent between hip, knee and the foot the mod reports; the shell turns with the torso | animated |
| Armour looks | `character` in light/heavy, modular, power armour | 2 plate sets (light armour keeps the plain look) | Plates on the character's own skeleton, so every animation carries over | animated |
| Misc | `market`, `lane-splitter`, `loader`, `fast-loader`, `express-loader`, `loader-1x1` | 4 (market, lane splitter, loader, 1x1 loader) | Loaders' belts move | in-client |

## ER: Elevated Rails

| Family | Prototypes | Models | Technique | Status |
|---|---|---|---|---|
| Elevated rails | `elevated-straight-rail`, `elevated-half-diagonal-rail`, `elevated-curved-rail-a`, `elevated-curved-rail-b`, `rail-ramp`, `rail-support` | 1 per deck piece, with a diagonal variant; ramp; support | none | in-client |

## P3: Space Age

| Family | Prototypes | Models | Technique | Status |
|---|---|---|---|---|
| Machines | `foundry`, `electromagnetic-plant`, `cryogenic-plant`, `biochamber`, `crusher`, `recycler`, `big-mining-drill`, `agricultural-tower`, `heating-tower`, `captive-biter-spawner`, `biolab`, `fusion-reactor`, `fusion-generator` | 13 | Parts turn, slide and glow while working, timed from each prototype's animation; crane for the agricultural tower | foundry and big-mining-drill animated; the other eleven in-client |
| Logistics tier | `turbo-transport-belt`, `turbo-underground-belt`, `turbo-splitter`, `turbo-loader`, `stack-inserter` | 1 (stack inserter, one per direction; the rest are P0 models in their own paint) | Arm as the other inserters | stack-inserter animated |
| Space platform | `space-platform-hub`, `cargo-bay`, `thruster`, `asteroid-collector` | 4 | Thruster plume; hub and bay hatches open while a pod passes; collector arms fly out and catch real chunks (`collectors.gd`) | in-client |
| Turrets | `railgun-turret`, `rocket-turret`, `tesla-turret` | 3 | Heads aim at the mod's targets: the railgun lowers from upright, the rocket pods open, the tesla head rises | railgun-turret and rocket-turret in-client; tesla-turret animated |
| Lightning | `lightning-rod`, `lightning-collector` | 2 | Sparks after a strike lands on it | in-client |
| Capture robot | `capture-robot` | 1 | Hover; hanging cables sway | in-client |
| Mech armour look | `character` in mech armour | 1 | Idle, run, mining and aiming on its own model; flight not drawn | animated |
| Vulcanus | `small-demolisher`, `medium-demolisher`, `big-demolisher`; `big-volcanic-rock`, `huge-volcanic-rock` (+`-hot`); `vulcanus-chimney` (+`-cold`, `-faded`, `-short`, `-truncated`); `ashland-lichen-tree` (+`-flaming`); `tungsten-ore`, `calcite`; `sulfuric-acid-geyser` | Demolisher head, segment and tail; 2 rocks (+ hot); 5 chimneys; lichen (+ flaming); geyser; 2 ores | Demolisher parts glide after the head at their prototypes' scales (`demolishers.gd`); hot and flaming ones glow | demolishers animated (against the mock only); rocks, chimneys, lichen and geyser in-client; tungsten-ore and calcite have models too |
| Fulgora | `fulgoran-ruin-tiny/small/small-tall/medium/medium-tall/big/huge/huge-tall/colossal/stonehenge/vault/attractor`, `fulgora-sunk-ruin-big`, `fulgora-sunk-ruin-medium-tall`, `fulgurite`, `fulgurite-small`, `scrap` | 11 ruins, 2 fulgurites, scrap | none | in-client |
| Gleba flora | `yumako-tree`, `jellystem`, `boompuff`, `cuttlepop`, `funneltrunk`, `hairyclubnub`, `lickmaw`, `slipstack`, `stingfrond`, `sunnycomb`, `teflilly`, `water-cane`, `copper-stromatolite`, `iron-stromatolite` (`tree-plant` reuses the P0 trees) | 14 | none yet (no wind) | textured (lickmaw and funneltrunk paler than their sprites; thin strands) |
| Gleba enemies | `small/medium/big-wriggler-pentapod`, `small/medium/big-strafer-pentapod`, `small/medium/big-stomper-pentapod`, `gleba-spawner`, `gleba-spawner-small` | Wriggler, 3 strafers, 3 stompers; 2 spawners + corpse | Strafers' and stompers' legs bent between hip, knee and the mod's feet; wrigglers on the shader's limb rig; spawners' sacs swell, a dying spawner slumps into its corpse | animated (against the mock only) |
| Aquilo | `lithium-iceberg-big`, `lithium-iceberg-huge`, `lithium-brine`, `fluorine-vent` | 4 | none | in-client |
| Asteroids | `small/medium/big/huge` × `metallic/carbonic/oxide/promethium-asteroid` | 16 | Tumble rotation | textured (lighter and smoother than the pitted sprites) |

---

## Not models (handled by the client)

| What | How |
|---|---|
| Terrain tiles (grass, dirt, sand, desert, water, …) | Factorio's own tile textures from the install on the per-chunk terrain mesh, with ragged transitions, an irregular coast and a water shader |
| Player floors (`stone-path`, `concrete`, `refined-concrete`, hazard concrete, space platform foundation) | Factorio's tile textures, like the terrain |
| Decoratives (grass tufts, pebbles, …) | Factorio's pictures, one MultiMesh per chunk per decorative (`decoratives.gd`), thinned with distance |
| Items on belts, on the ground, in inserter hands | Small models for 198 items (`items/`, `tools/models/items.py`); icon cards for the rest and for belts far away |
| Explosions, fire, smoke, projectiles, beams, streams | Factorio's own sprite sheets from the install, played on cards (`weapon_fx.gd`, `sprite_fx.gd`) |
| Remnants | The parent model flattened, broken and rusted |

## Skipped (editor, test or hidden)

`bottomless-chest`, `infinity-chest`, `linked-chest`, `electric-energy-interface`,
`heat-interface`, `simple-entity-with-force`, `simple-entity-with-owner`,
`factorio-logo-11tiles/16tiles/22tiles`, `wube-logo-space-platform`, all `dummy-*` and
`parameter-*` entities. These get the automatic placeholder box.

Drawn after all with other models: `infinity-cargo-wagon` (the cargo wagon tinted as Factorio
draws it), `infinity-pipe` (the pipe kit tinted), `burner-generator` (the steam engine, as Factorio
draws it), `linked-belt` (a steel underground end).
