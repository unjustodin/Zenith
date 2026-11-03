"""What each exported model must look like, shared by build.py (Blender) and check.py (plain
Python). No bpy here.

`size` is the footprint in tiles of the north-facing entity's selection box: (east-west,
north-south). `budget` is the LOD0 triangle budget from docs/PLAN.md §6.4. `base` names the
prototype a variant model belongs to (curved belts, underground entrance and exit).
`fill` is the smallest share of the footprint the model must cover on each axis, so a model at
the wrong scale fails; thin things like poles cover less.
"""

LOGISTICS = 1500
MACHINE = 10000
LANDMARK = 40000

SPECS = {
    "transport-belt": {"size": (1, 1), "budget": LOGISTICS},
    "transport-belt-curve-left": {"size": (1, 1), "budget": LOGISTICS, "base": "transport-belt"},
    "transport-belt-curve-right": {"size": (1, 1), "budget": LOGISTICS, "base": "transport-belt"},
    "underground-belt-input": {"size": (1, 1), "budget": LOGISTICS, "base": "underground-belt"},
    "underground-belt-output": {"size": (1, 1), "budget": LOGISTICS, "base": "underground-belt"},
    "splitter": {"size": (2, 1), "budget": LOGISTICS},
    "wooden-chest": {"size": (1, 1), "budget": LOGISTICS},
    "iron-chest": {"size": (1, 1), "budget": LOGISTICS},
    "steel-chest": {"size": (1, 1), "budget": LOGISTICS},
    "stone-furnace": {"size": (2, 2), "budget": MACHINE},
    "burner-mining-drill": {"size": (2, 2), "budget": MACHINE},
    "electric-mining-drill": {"size": (3, 3), "budget": MACHINE},
    "assembling-machine-1": {"size": (3, 3), "budget": MACHINE},
    "small-electric-pole": {"size": (1, 1), "budget": LOGISTICS, "fill": (0.5, 0.1)},
    "lab": {"size": (3, 3), "budget": MACHINE},
    "boiler": {"size": (3, 2), "budget": MACHINE},
    "steam-engine": {"size": (3, 5), "budget": MACHINE, "overhang": 0.5},
    "gun-turret": {"size": (2, 2), "budget": MACHINE},
    "stone-wall": {"size": (1, 1), "budget": LOGISTICS},
}

# Nature (tools/models/nature/): trunks and rocks sit a little into the ground so nothing floats
# on uneven terrain, and leaning trees aren't centred. Factorio's trees are far bigger than their
# 1x1 footprint (tree-09's crown is five tiles across, see trees.py), and ore tiles spread chunks
# into their neighbours as the 2x2-tile sprites do.
NATURE = 3000
_LOOSE = {"budget": NATURE, "sink": 0.2, "overhang": 5.2, "fill": (0.0, 0.0), "centre": 0.6}
# The colour variants (tree-08-brown...) are their tree's model with their own leaf colours.
for _name in ["tree-0%d" % i for i in range(1, 10)] + [
        "tree-02-red", "tree-06-brown", "tree-08-brown", "tree-08-red", "tree-09-brown", "tree-09-red",
        "dead-dry-hairy-tree", "dead-grey-trunk", "dead-tree-desert", "dry-hairy-tree", "dry-tree"]:
    SPECS[_name] = dict(_LOOSE, size=(1, 1))
for _name, _size in (("big-rock", (2, 2)), ("huge-rock", (3, 3)), ("big-sand-rock", (2, 2))):
    SPECS[_name] = dict(_LOOSE, size=_size, overhang=0.6)
for _name in ("iron-ore", "copper-ore", "coal", "stone"):
    SPECS[_name] = dict(_LOOSE, size=(1, 1), overhang=0.8, centre=0.15)
# The richest and poorest of the Nauvis ores' richness stages (nature/rocks.py STAGES).
for _name in ("iron-ore", "copper-ore", "coal", "stone", "uranium-ore"):
    for _stage in ("-rich", "-sparse"):
        SPECS[_name + _stage] = dict(_LOOSE, size=(1, 1), overhang=0.8, centre=0.15)

# Converted from Wube's printable models (tools/models/wube.py).
SPECS["steel-furnace"] = {"size": (2, 2), "budget": MACHINE}
for _name in ("passive-provider-chest", "active-provider-chest", "storage-chest", "buffer-chest",
              "requester-chest"):
    SPECS[_name] = {"size": (1, 1), "budget": LOGISTICS}
# Inserters: the base only; the client draws the arm.
for _name in ("burner-inserter", "inserter", "long-handed-inserter", "fast-inserter", "bulk-inserter",
              "stack-inserter"):
    # A model per direction (wube_recipes.py INSERTER_FITS). The sprites' feet reach about 0.08
    # tiles past the tile at each end, and so do the models' (1.17 tiles from foot to foot).
    SPECS[_name] = {"size": (1, 1), "budget": LOGISTICS, "overhang": 0.2}
    for _sfx in ("-east", "-south", "-west"):
        SPECS[_name + _sfx] = dict(SPECS[_name], base=_name)
# Wube's pole stands where its sprite has it, north-east of the tile's centre, and its crossarm
# reaches west.
SPECS["small-electric-pole"]["centre"] = 0.3
# Wube's assembler is a dense model: its gears and pipes need more than the usual machine budget.
SPECS["assembling-machine-1"]["budget"] = 16000

# Default fill and how far a model may stray from its footprint (tiles).
DEFAULT_FILL = (0.6, 0.6)
OVERHANG = 0.03
CENTRE_TOLERANCE = 0.15
GROUND_TOLERANCE = 0.02

# Modelled from the sprites, not in Wube's release (fluids.py, electric.py, oil.py, vehicles.py).
# The offshore pump stands on its land tile (the entity's position) and reaches north over the
# water, past its selection box; the client places it by that position.
SPECS["offshore-pump"] = {"size": (1.2, 2.0), "budget": MACHINE, "overhang": 0.8, "centre": 0.5}
SPECS["pipe"] = {"size": (1, 1), "budget": LOGISTICS, "fill": (0.4, 0.9), "overhang": 0.15}
# The pipe kit: one model per Factorio pipe picture, picked from the pipe's neighbours (fluids.py).
for _shape in ("straight-vertical-single", "straight-vertical", "straight-horizontal", "corner-up-right",
               "corner-up-left", "corner-down-right", "corner-down-left", "t-up", "t-down", "t-left", "t-right",
               "cross", "ending-up", "ending-down", "ending-left", "ending-right"):
    # North flanges straddle the tile edge, as Factorio draws them (fluids.py).
    SPECS["pipe-" + _shape] = {"size": (1, 1), "budget": LOGISTICS, "fill": (0.4, 0.4), "base": "pipe", "overhang": 0.15}
# Its ground flange sits north of the middle in the north picture (fluids.py PTG_FACINGS).
SPECS["pipe-to-ground"] = {"size": (1, 1), "budget": LOGISTICS, "fill": (0.4, 0.6), "overhang": 0.15, "centre": 0.25}
for _sfx in ("-east", "-south", "-west"):  # its other directions (fluids.py PTG_FACINGS)
    SPECS["pipe-to-ground" + _sfx] = dict(SPECS["pipe-to-ground"], base="pipe-to-ground")
SPECS["storage-tank"] = {"size": (3, 3), "budget": MACHINE, "overhang": 0.15}
SPECS["medium-electric-pole"] = {"size": (1, 1), "budget": 2500, "fill": (0.3, 0.3), "overhang": 0.3, "centre": 0.3}
SPECS["big-electric-pole"] = {"size": (2, 2), "budget": MACHINE, "fill": (0.4, 0.3), "overhang": 0.4}
SPECS["substation"] = {"size": (2, 2), "budget": MACHINE}
SPECS["small-lamp"] = {"size": (1, 1), "budget": LOGISTICS, "fill": (0.5, 0.5)}
SPECS["solar-panel"] = {"size": (3, 3), "budget": MACHINE}
SPECS["accumulator"] = {"size": (2, 2), "budget": MACHINE}
SPECS["radar"] = {"size": (3, 3), "budget": MACHINE}
SPECS["pumpjack"] = {"size": (3, 3), "budget": MACHINE, "overhang": 0.4}  # its pipes run past the edges, as drawn
SPECS["oil-refinery"] = {"size": (5, 5), "budget": MACHINE, "sink": 0.2}  # port bells half sunk, as drawn
SPECS["chemical-plant"] = {"size": (3, 3), "budget": MACHINE, "sink": 0.2}  # port bells half sunk, as drawn
# Vehicles' sprites are bigger than their selection boxes (the car's tyres, the trains' couplers).
SPECS["car"] = {"size": (1.4, 2.0), "budget": MACHINE, "overhang": 0.7}
for _name in ("locomotive", "cargo-wagon", "fluid-wagon", "infinity-cargo-wagon"):
    SPECS[_name] = {"size": (2.0, 6.0), "budget": 16000, "overhang": 1.2}  # rolling stock: riveted, planked, piped
# Wube's printable drill is an open frame of many small parts (rails, racks, arms, hoses): at
# 10k triangles the decimation melts them, so it gets twice the machine budget.
SPECS["electric-mining-drill"]["budget"] = 20000
# The burner drill's legs reach past the corners of its 2x2 box, as its sprite's do.
SPECS["burner-mining-drill"]["overhang"] = 0.5
for _sfx in ("-east", "-south", "-west"):  # its other directions (machines.py DRILL_FACINGS)
    SPECS["burner-mining-drill" + _sfx] = dict(SPECS["burner-mining-drill"], base="burner-mining-drill")
# The pumpjack's and chemical plant's other directions (oil.py PJ_FACINGS, CP_FACINGS).
for _base in ("pumpjack", "chemical-plant"):
    for _sfx in ("-east", "-south", "-west"):
        SPECS[_base + _sfx] = dict(SPECS[_base], base=_base)

# Steam power, a model per direction (power.py, fluids.py, facings.py): east and west lie across.
# The steam engine's rivets, valve gear and gear train take it past the machine budget. Each
# picture draws the pipe connections reaching a little past the tiles, as the models do.
SPECS["steam-engine"].update(budget=14000, overhang=0.85)
SPECS["boiler"]["overhang"] = 0.15
for _base, _sfxs in (("boiler", ("-east", "-south", "-west")), ("steam-engine", ("-east",)),
                     ("offshore-pump", ("-east", "-south", "-west"))):
    for _sfx in _sfxs:
        _w, _d = SPECS[_base]["size"]
        SPECS[_base + _sfx] = dict(SPECS[_base], base=_base, size=(_d, _w) if _sfx in ("-east", "-west") else (_w, _d))

# Inserter arm pieces (wube_recipes.py): drawn by the client about their joint, so the origin is
# the joint, not the footprint centre, and they reach north from it.
for _family, _reach in (("basic", 1.0), ("long", 1.5), ("bulk", 0.9), ("stack", 0.9)):
    for _piece in ("upper", "hand-open", "hand-closed"):
        SPECS["inserter-arm-%s-%s" % (_family, _piece)] = {
            "size": (0.5, _reach), "budget": LOGISTICS, "fill": (0.0, 0.0), "overhang": 1.0, "centre": 2.0,
            "base": "inserter"}

# Circuit network, valves and pump (circuits.py). Combinators run north-south; their wires and
# posts reach a little past the selection box, as in the sprites.
for _name in ("arithmetic-combinator", "decider-combinator", "selector-combinator"):
    SPECS[_name] = {"size": (1, 2), "budget": MACHINE, "fill": (0.6, 0.6)}
SPECS["constant-combinator"] = {"size": (1, 1), "budget": MACHINE}
SPECS["power-switch"] = {"size": (2, 2), "budget": MACHINE, "fill": (0.5, 0.6)}
SPECS["programmable-speaker"] = {"size": (1, 1), "budget": MACHINE, "fill": (0.4, 0.4), "overhang": 0.4}
SPECS["display-panel"] = {"size": (1, 1), "budget": MACHINE}
for _name in ("one-way-valve", "overflow-valve", "top-up-valve"):
    SPECS[_name] = {"size": (1, 1), "budget": LOGISTICS * 2, "overhang": 0.1}  # its flange straddles the edge
    for _sfx in ("-east", "-south", "-west"):  # its other directions (circuits.py VALVE_BARS)
        SPECS[_name + _sfx] = dict(SPECS[_name], base=_name)
SPECS["pump"] = {"size": (1, 2), "budget": MACHINE}

# Logistics and mid-game machines (logistics.py). The roboport's arms reach a little past its
# 4x4 box, as in the sprite; robots fly, so their "footprint" is just their size.
SPECS["roboport"] = {"size": (4, 4), "budget": MACHINE, "overhang": 0.3}
SPECS["logistic-robot"] = {"size": (0.8, 0.8), "budget": LOGISTICS * 2, "overhang": 0.2, "centre": 0.3}
SPECS["construction-robot"] = {"size": (0.6, 0.6), "budget": LOGISTICS * 2, "overhang": 0.2, "centre": 0.3}
SPECS["electric-furnace"] = {"size": (3, 3), "budget": MACHINE}
SPECS["beacon"] = {"size": (3, 3), "budget": MACHINE}
SPECS["assembling-machine-2"] = {"size": (3, 3), "budget": MACHINE}
SPECS["assembling-machine-3"] = {"size": (3, 3), "budget": MACHINE}
SPECS["crude-oil"] = {"size": (3, 3), "budget": LOGISTICS * 2, "fill": (0.5, 0.5), "sink": 0.05}

# Space Age, Gleba and Aquilo (gleba.py, aquilo.py). Their sprites spill a little past the
# selection box (pipes, hoses), as the base game's do.
SPECS["biochamber"] = {"size": (3, 3), "budget": MACHINE, "overhang": 0.15}
# The tower's crane reaches north past the footprint, the hose reel lies south of it.
SPECS["agricultural-tower"] = {"size": (3, 3), "budget": MACHINE, "overhang": 2.6, "centre": 0.7}
SPECS["heating-tower"] = {"size": (3, 3), "budget": MACHINE, "overhang": 0.15}
SPECS["biolab"] = {"size": (5, 5), "budget": MACHINE, "overhang": 0.4}
SPECS["captive-biter-spawner"] = {"size": (5, 5), "budget": MACHINE, "overhang": 1.0}  # its claws spill a tile south in the sprite
SPECS["rocket-turret"] = {"size": (3, 3), "budget": MACHINE}
SPECS["cryogenic-plant"] = {"size": (5, 5), "budget": MACHINE, "overhang": 0.25}
SPECS["fusion-reactor"] = {"size": (6, 6), "budget": MACHINE, "overhang": 0.8}
SPECS["fusion-generator"] = {"size": (3, 5), "budget": MACHINE, "overhang": 0.15}
# The railgun's barrel reaches past the north edge of its selection box.
SPECS["railgun-turret"] = {"size": (3, 5), "budget": MACHINE, "overhang": 0.7, "centre": 0.35}
for _name, _over in (("lithium-brine", 1.2), ("fluorine-vent", 1.4)):
    SPECS[_name] = {"size": (1, 1), "budget": NATURE, "overhang": _over, "centre": 0.3, "sink": 0.12}
SPECS["lithium-iceberg-big"] = {"size": (2, 1.5), "budget": NATURE, "overhang": 0.6, "sink": 0.12, "centre": 0.3}
SPECS["lithium-iceberg-huge"] = {"size": (3.7, 2.5), "budget": NATURE, "overhang": 1.2, "sink": 0.12, "centre": 0.4}
# Gleba plants: like the Nauvis trees, far bigger than their footprint and drawn south of it.
for _name in ("yumako-tree", "jellystem", "cuttlepop", "slipstack", "funneltrunk", "hairyclubnub", "teflilly", "lickmaw",
              "stingfrond", "boompuff", "sunnycomb", "water-cane"):
    SPECS[_name] = dict(_LOOSE, size=(1, 1), budget=5000)
# Pentapods (gleba.py): the selection box, and the five legs in their rest pose reaching far past
# it (a big stomper's feet stand 11.2 tiles out). Wrigglers: the big tier (the client scales the
# others), its tentacle legs splayed two tiles round it.
for _prefix, _k in (("small-", 0.5625), ("medium-", 0.75), ("big-", 1.0)):
    SPECS[_prefix + "stomper-pentapod"] = {"size": (8 * _k, 8 * _k), "budget": MACHINE, "fill": (0.5, 0.5),
                                           "overhang": 17 * _k, "centre": 1.0 * _k}
    SPECS[_prefix + "strafer-pentapod"] = {"size": (4.8 * _k, 4.8 * _k), "budget": MACHINE, "fill": (0.5, 0.5),
                                           "overhang": 11 * _k, "centre": 1.0 * _k}
# A dead stomper's shell (gleba.py): its collision box (1.8 x 1.45 either side at the tier's
# stomper_scale, 1.1 x 0.9 / 1.2 / 1.6), the torso squashed to it, lying a little past it and sunk.
for _prefix, _ss in (("small-", 0.99), ("medium-", 1.32), ("big-", 1.76)):
    SPECS[_prefix + "stomper-shell"] = {"size": (3.6 * _ss, 2.9 * _ss), "budget": MACHINE, "fill": (0.5, 0.5),
                                        "overhang": 1.0 * _ss, "centre": 0.6 * _ss, "sink": 0.3 * _ss}
SPECS["big-wriggler-pentapod"] = {"size": (1.8, 1.8), "budget": LOGISTICS * 2, "fill": (0.5, 0.5), "overhang": 2.5,
                                  "centre": 0.3, "sink": 0.05}
# Gleba spawners, measured from their pictures (creature_hull.py): the small one's heap is smaller
# than its 3x3 box; the corpse is a splash lying round where the big one stood.
SPECS["gleba-spawner"] = {"size": (5, 5), "budget": MACHINE, "overhang": 0.8, "centre": 0.6, "sink": 0.2}
SPECS["gleba-spawner-small"] = {"size": (3, 3), "budget": MACHINE, "fill": (0.4, 0.4), "overhang": 0.3, "centre": 0.4,
                                "sink": 0.15}
SPECS["gleba-spawner-corpse"] = {"size": (5, 5), "budget": MACHINE, "fill": (0.0, 0.0), "overhang": 6.5, "centre": 1.5,
                                 "lift": 0.07, "base": "gleba-spawner"}
SPECS["capture-robot"] = {"size": (2.0, 2.0), "budget": LOGISTICS * 3, "overhang": 0.8, "centre": 0.4}
# Its capture cables hang to the ground from its flying height (gleba.py CAPTURE_HEIGHT).
SPECS["capture-robot"]["sink"] = 1.6
SPECS["capture-robot"]["overhang"] = 1.0

# Stone wall pieces converted from Wube's walls set (wube_recipes.py), one per connection shape,
# picked by the client from the wall's neighbours (model_library.gd). Walls run edge to edge.
for _shape in ("pylon", "n", "e", "s", "w", "ns", "ew", "ne", "nw", "es", "sw", "new", "nes", "esw", "nsw", "nesw"):
    SPECS["stone-wall-" + _shape] = {"size": (1, 1), "budget": LOGISTICS, "base": "stone-wall", "fill": (0.3, 0.3)}
SPECS["stone-wall"]["fill"] = (0.3, 0.3)

# Rails (rails.py): sizes are the pieces' extents (rails reach past their selection boxes), and
# pieces aren't centred on their position: the curves bend to one side of it.
_RAIL = {"budget": 6000, "fill": (0.3, 0.3), "overhang": 0.3, "centre": 0.5}
for _proto, _size in (("straight-rail", (2.4, 2.1)), ("half-diagonal-rail", (4.1, 5.1)), ("curved-rail-a", (3.2, 5.6)),
                      ("curved-rail-b", (4.9, 5.4))):
    SPECS[_proto] = dict(_RAIL, size=_size)
    SPECS[_proto + "-ne"] = dict(_RAIL, size=_size if _proto != "straight-rail" else (3.7, 3.7), base=_proto)
    SPECS["elevated-" + _proto] = dict(SPECS[_proto], budget=9000, lift=4.2)
    SPECS["elevated-" + _proto + "-ne"] = dict(SPECS[_proto + "-ne"], budget=9000, lift=4.2, base="elevated-" + _proto)
# Railway buildings (railway.py). The train stop's arm reaches over the track two tiles west of
# its 2x2 footprint, and the ramp is 16 tiles long; signals are small on their tile.
SPECS["rail-support"] = {"size": (3, 3), "budget": MACHINE, "fill": (0.6, 0.6), "overhang": 1.0}  # its stone mound, as the sprite
SPECS["rail-ramp"] = {"size": (3.6, 16), "budget": LANDMARK, "fill": (0.5, 0.9), "overhang": 0.3}
SPECS["rail-signal"] = {"size": (0.9, 1.3), "budget": LOGISTICS * 2, "fill": (0.25, 0.4)}
SPECS["rail-chain-signal"] = {"size": (1, 1), "budget": LOGISTICS * 2, "fill": (0.5, 0.4)}
SPECS["train-stop"] = {"size": (1.8, 1.8), "budget": MACHINE, "overhang": 2.0, "centre": 1.0, "fill": (0.5, 0.4)}
SPECS["gate"] = {"size": (1, 1), "budget": LOGISTICS * 2, "fill": (0.6, 0.6)}
for _shape in ("es", "nes", "esw", "nesw"):
    SPECS["stone-wall-%s-fill" % _shape] = {"size": (1, 1), "budget": LOGISTICS, "base": "stone-wall", "fill": (0.3, 0.3),
                                            "overhang": 0.4, "centre": 0.3}

# The splitter is two belt tiles under a gearbox.
SPECS["splitter"]["budget"] = LOGISTICS * 2


# Creatures, converted from Wube's printable models and rigged (wube_recipes.py, wube_rig.py), posed
# from them (creature_pose.py) or, for the worm, built from the sprites (worm.py). Their sprites
# spread well past their selection boxes (legs, horns, the spawner's dirt); the pose variants
# (-attack, -corpse, the character's -gun) belong to their family. Corpses lie where Factorio's
# picture of them lies: off the creature's position as they fell (the worm's three tiles out).
CREATURE = 9000
_CREATURE = {"budget": CREATURE, "fill": (0.0, 0.0), "centre": 0.5}
SPECS["big-biter"] = dict(_CREATURE, size=(1.4, 1.8), overhang=1.7)
SPECS["big-biter-attack"] = dict(SPECS["big-biter"], base="big-biter", overhang=2.6)
SPECS["big-biter-corpse"] = dict(SPECS["big-biter"], base="big-biter", centre=1.2, overhang=2.4)
for _v in (1, 2, 3):
    SPECS["big-biter-corpse-%d" % _v] = SPECS["big-biter-corpse"]
SPECS["big-spitter"] = dict(_CREATURE, size=(1.4, 2.0), overhang=1.4)
SPECS["big-spitter-attack"] = dict(SPECS["big-spitter"], base="big-spitter", overhang=2.4)
SPECS["big-spitter-corpse"] = dict(SPECS["big-spitter"], base="big-spitter", centre=1.2, overhang=2.0)
for _v in (1, 2, 3):
    SPECS["big-spitter-corpse-%d" % _v] = SPECS["big-spitter-corpse"]
SPECS["big-worm-turret"] = dict(_CREATURE, size=(2.8, 2.8), overhang=2.7)
SPECS["big-worm-turret-corpse"] = dict(SPECS["big-worm-turret"], base="big-worm-turret", centre=3.2)
SPECS["biter-spawner"] = dict(_CREATURE, budget=12000, size=(5.0, 5.0), overhang=1.8)
SPECS["biter-spawner-corpse"] = dict(SPECS["biter-spawner"], base="biter-spawner")
SPECS["character"] = dict(_CREATURE, size=(0.8, 0.8), overhang=0.3)
SPECS["character-gun"] = dict(SPECS["character"], base="character", overhang=0.65)  # gun out in front, pack behind
SPECS["character-corpse"] = dict(SPECS["character"], base="character", overhang=1.0)
# Mech armour: half as tall again, the gun held out in front and the claw out to the side.
# Armour looks (armour_looks.py): the character with its plates; power armour's shoulders and the
# shell over the pack stand out further.
SPECS["character-armor-2"] = dict(SPECS["character"], base="character", budget=11000, overhang=0.35)
SPECS["character-armor-3"] = dict(SPECS["character"], base="character", budget=11000, overhang=0.4)
SPECS["character-mech-armor"] = dict(SPECS["character"], base="character", overhang=0.9)

# The crash site (crash_site.py): wreckage drawn round its entity's position, which isn't its
# selection box's centre, and spreading past it as the sprites do.
_WRECK = {"budget": MACHINE, "fill": (0.0, 0.0), "centre": 1.2, "overhang": 2.5}
for _name, _size in (("crash-site-chest-1", (1.0, 1.0)), ("crash-site-chest-2", (1.0, 1.0)),
                     ("crash-site-spaceship-wreck-big-1", (2.3, 1.3)), ("crash-site-spaceship-wreck-big-2", (2.9, 2.9)),
                     ("crash-site-spaceship-wreck-medium-1", (2.4, 1.7)), ("crash-site-spaceship-wreck-medium-2", (2.1, 1.6)),
                     ("crash-site-spaceship-wreck-medium-3", (1.5, 2.8)), ("crash-site-spaceship-wreck-small-1", (1.8, 1.8)),
                     ("crash-site-spaceship-wreck-small-2", (1.4, 0.8)), ("crash-site-spaceship-wreck-small-3", (1.9, 1.4)),
                     ("crash-site-spaceship-wreck-small-4", (2.0, 1.4)), ("crash-site-spaceship-wreck-small-5", (1.7, 0.8)),
                     ("crash-site-spaceship-wreck-small-6", (1.9, 1.0))):
    SPECS[_name] = dict(_WRECK, size=_size, budget=LOGISTICS * 2)
SPECS["crash-site-spaceship"] = dict(_WRECK, size=(15.6, 7.8), budget=LANDMARK, overhang=5.1, centre=1.5)
SPECS["fish"] = {"size": (1.0, 1.0), "budget": LOGISTICS, "fill": (0.0, 0.0), "sink": 0.3}


# Military, nuclear and rocket (military.py, nuclear.py, rocket.py). Turret barrels, the tank's
# mudguards and the spidertron's legs reach past their selection boxes, as in the sprites.
SPECS["laser-turret"] = {"size": (2, 2), "budget": MACHINE, "overhang": 0.3}
SPECS["flamethrower-turret"] = {"size": (2, 3), "budget": MACHINE, "overhang": 0.4}
SPECS["land-mine"] = {"size": (1, 1), "budget": LOGISTICS, "fill": (0.5, 0.5)}
SPECS["artillery-turret"] = {"size": (3, 3), "budget": MACHINE, "overhang": 3.0, "centre": 0.5}
SPECS["tank"] = {"size": (1.8, 2.6), "budget": MACHINE, "overhang": 1.1}
SPECS["spidertron"] = {"size": (2, 2), "budget": MACHINE, "overhang": 4.5}
SPECS["artillery-wagon"] = {"size": (2.0, 6.0), "budget": MACHINE, "overhang": 1.2}
for _name in ("defender", "distractor", "destroyer"):
    SPECS[_name] = {"size": (0.8, 0.8), "budget": LOGISTICS, "fill": (0.5, 0.5), "overhang": 0.5}
# The destroyer's four guns reach 1.33 tiles across in its sprite (88 px frames at scale 0.5).
SPECS["destroyer"]["overhang"] = 0.6
SPECS["nuclear-reactor"] = {"size": (5, 5), "budget": MACHINE, "sink": 0.3}
SPECS["heat-exchanger"] = {"size": (3, 2), "budget": MACHINE, "overhang": 0.2}
SPECS["steam-turbine"] = {"size": (3, 5), "budget": MACHINE, "overhang": 0.4}
SPECS["centrifuge"] = {"size": (3, 3), "budget": MACHINE, "overhang": 0.15}
SPECS["heat-pipe"] = {"size": (1, 1), "budget": LOGISTICS, "fill": (0.3, 0.9)}
for _shape in ("straight-vertical-single", "straight-vertical", "straight-horizontal", "corner-up-right",
               "corner-up-left", "corner-down-right", "corner-down-left", "t-up", "t-down", "t-left", "t-right",
               "cross", "ending-up", "ending-down", "ending-left", "ending-right"):
    SPECS["heat-pipe-" + _shape] = {"size": (1, 1), "budget": LOGISTICS, "fill": (0.25, 0.25), "base": "heat-pipe",
                                    "centre": 0.3}
# The drum in its south-east hole (anim_lift_silo) reaches down into the deck, out of sight.
SPECS["rocket-silo"] = {"size": (9, 9), "budget": MACHINE, "sink": 0.55}
SPECS["rocket-silo-rocket"] = {"size": (4.2, 4.2), "budget": MACHINE, "fill": (0.5, 0.5), "overhang": 0.4}
SPECS["cargo-pod"] = {"size": (1.2, 1.2), "budget": LOGISTICS * 2, "fill": (0.5, 0.5), "overhang": 0.3,
                      "sink": 0.9}  # panels folded on its sides, the thruster flame under it
SPECS["cargo-landing-pad"] = {"size": (8, 8), "budget": 20000, "overhang": 0.3}  # the hub's twin (its budget)
SPECS["market"] = {"size": (3, 3), "budget": MACHINE}
SPECS["loader"] = {"size": (1, 2), "budget": LOGISTICS}


# Space Age (space_platform.py, vulcanus.py, fulgora.py), matched to the Space Age sprites.
SPECS["space-platform-hub"] = {"size": (8, 8), "budget": 20000, "overhang": 0.15}
# The cargo bay's sprite covers about 3 x 2.3 of its 4 x 4 tiles; its connections draw the rest.
SPECS["cargo-bay"] = {"size": (4, 4), "budget": MACHINE, "sink": 0.05, "fill": (0.7, 0.5)}
# The cargo area's edge pieces, one 2x2 cell each (space_platform.py, model_library.gd CARGO_PIECES);
# a wall fills only its edge of the cell.
for _piece in ("wall-n", "wall-e", "wall-s", "wall-w", "corner-nw", "corner-ne", "corner-sw", "corner-se",
               "inner-nw", "inner-ne", "inner-sw", "inner-se"):
    SPECS["cargo-bay-" + _piece] = {"size": (2, 2), "budget": 3000, "fill": (0.0, 0.0), "overhang": 0.1, "centre": 0.6}
# The thruster's bell hangs off the deck's south edge (its selection box reaches 5.5 tiles south of
# its position), below the deck: nothing is drawn under a platform's edge. Its exhaust plume
# (anim_glow_plume) streams 5 tiles further south.
SPECS["thruster"] = {"size": (4, 8), "budget": 16000,  # tangled pipework, ribbed bell and hoses
                      "overhang": 4.0, "centre": 0.45, "sink": 2.9}
# The collector stands on the deck's edge, its chute hanging off it below the deck.
SPECS["asteroid-collector"] = {"size": (3, 3), "budget": MACHINE, "overhang": 1.1, "centre": 0.5, "sink": 2.8}
SPECS["crusher"] = {"size": (2, 3), "budget": MACHINE, "overhang": 0.3}  # its drum and pipes stand out at the sides
SPECS["crusher-east"] = {"size": (3, 2), "budget": MACHINE, "overhang": 0.3, "base": "crusher"}  # the hose stands out east
SPECS["foundry"] = {"size": (5, 5), "budget": MACHINE, "overhang": 0.6, "centre": 0.2}
# Its output chute pokes out north of the footprint.
SPECS["big-mining-drill"] = {"size": (5, 5), "budget": MACHINE, "overhang": 0.2}
SPECS["electromagnetic-plant"] = {"size": (4, 4), "budget": MACHINE, "overhang": 0.6, "centre": 0.2}
SPECS["recycler"] = {"size": (1.8, 3.7), "budget": MACHINE, "overhang": 0.36}
SPECS["lightning-rod"] = {"size": (1, 1), "budget": LOGISTICS * 2, "fill": (0.5, 0.5), "overhang": 0.2}
SPECS["lightning-collector"] = {"size": (2, 2), "budget": MACHINE, "overhang": 0.25}
SPECS["tesla-turret"] = {"size": (4, 4), "budget": MACHINE, "overhang": 0.5}
# Space Age nature (space_nature.py): sizes from the collision boxes; fitted to sprites that spill
# past them, so loose like the Nauvis rocks.
for _name, _size in (("big-volcanic-rock", (1.5, 1.5)), ("big-volcanic-rock-hot", (1.5, 1.5)),
                     ("huge-volcanic-rock", (3.0, 2.2)), ("huge-volcanic-rock-hot", (3.0, 2.2)),
                     ("vulcanus-chimney", (2.4, 2.4)), ("vulcanus-chimney-faded", (2.4, 2.4)),
                     ("vulcanus-chimney-cold", (2.4, 2.4)), ("vulcanus-chimney-short", (1.8, 1.4)),
                     ("vulcanus-chimney-truncated", (1.8, 1.4)),  # the short one stands north of its box
                     ("fulgoran-ruin-tiny", (0.9, 0.9)), ("fulgoran-ruin-small", (1.54, 1.36)),
                     ("fulgoran-ruin-medium", (2.42, 1.72)), ("fulgoran-ruin-stonehenge", (3.12, 2.64)),
                     ("fulgoran-ruin-big", (3.54, 2.98)), ("fulgoran-ruin-huge", (5.56, 4.66)),
                     ("fulgoran-ruin-colossal", (6.94, 5.32)), ("fulgoran-ruin-vault", (13.76, 8.0)),
                     ("fulgoran-ruin-attractor", (2.42, 2.42)), ("fulgurite", (2.0, 1.8)), ("fulgurite-small", (1.0, 1.0)),
                     ("ashland-lichen-tree", (1.0, 1.0)), ("ashland-lichen-tree-flaming", (1.0, 1.0)),
                     ("sulfuric-acid-geyser", (2.8, 2.8)), ("scrap", (1.0, 1.0))):
    SPECS[_name] = {"size": _size, "budget": 8000, "sink": 0.2, "overhang": max(_size) * 0.8 + 2.5,
                    "fill": (0.0, 0.0), "centre": 0.6}
# Asteroids are movers centred on their position (the client floats them); sized like their sprites.
for _kind in ("metallic", "carbonic", "oxide", "promethium"):
    for _size, _d in (("small", 1.6), ("medium", 3.0), ("big", 4.6), ("huge", 9.5)):
        SPECS["%s-%s-asteroid" % (_size, _kind)] = {"size": (_d, _d), "budget": 6000, "sink": _d * 0.7,
                                                     "overhang": _d * 0.4, "fill": (0.5, 0.5), "centre": 0.2}
# Demolishers at the big one's scale (selection boxes: head and tail 6x6, a segment 6x2); their
# sprites are wider than the boxes.
SPECS["demolisher-head"] = {"size": (6, 6), "budget": MACHINE, "overhang": 3.5, "fill": (0.5, 0.5), "centre": 0.35, "sink": 0.45}
# The segment is a crescent: its sides sweep back far behind its 9 x 3 box (creature_profiles.py).
SPECS["demolisher-segment"] = {"size": (9.12, 3.04), "budget": MACHINE, "overhang": 4.5, "fill": (0.5, 0.5), "centre": 0.6,
                               "sink": 0.1}
SPECS["demolisher-tail"] = {"size": (6, 6), "budget": MACHINE, "overhang": 3.0, "fill": (0.5, 0.5), "centre": 1.6, "sink": 0.1}
SPECS["fulgoran-ruin-vault"]["budget"] = 20000
SPECS["vulcanus-chimney-short"]["centre"] = 0.9  # its sprite stands over a tile north of its position
# Cliffs (nature/cliffs.py): one 4x4 cell of a cliff chain each, the high ground's slope reaching
# back and the fallen stones forward past the cell; loose like the rocks.
for _planet in ("", "vulcanus-", "gleba-", "fulgora-"):
    for _kind in ("sides", "outer", "inner", "exit", "entrance"):
        SPECS["cliff-%s%s" % (_planet, _kind)] = {"size": (4, 4), "budget": NATURE, "sink": 0.2, "overhang": 1.5,
                                                   "fill": (0.0, 0.0), "centre": 0.6, "base": "cliff"}

# The placeholder audit (placeholders.py, nature/rocks.py).
SPECS["lane-splitter"] = {"size": (1, 1), "budget": LOGISTICS * 2}
SPECS["loader-1x1"] = {"size": (1, 1), "budget": LOGISTICS}
# The bay's side tanks stand a little past its box; the landed pod's panels lie open round it.
SPECS["landing-pad-unloading-bay"] = {"size": (4.3, 5), "budget": MACHINE, "centre": 0.6, "overhang": 0.2}
SPECS["cargo-pod-container"] = {"size": (3.3, 2.8), "budget": LOGISTICS * 2, "fill": (0.3, 0.3), "overhang": 1.0, "centre": 0.6}
SPECS["tree-plant"] = dict(_LOOSE, size=(1.6, 1.6), budget=3500)
for _name in ("uranium-ore", "tungsten-ore", "calcite"):
    SPECS[_name] = dict(_LOOSE, size=(1, 1), overhang=0.8, centre=0.15)
for _name, _size in (("fulgora-sunk-ruin-big", (5.0, 3.44)), ("fulgora-sunk-ruin-medium-tall", (2.0, 2.0)),
                     ("copper-stromatolite", (1.4, 1.4)), ("iron-stromatolite", (1.4, 1.4))):
    SPECS[_name] = {"size": _size, "budget": 8000, "sink": 0.2, "overhang": max(_size) * 0.8 + 2.5,
                    "fill": (0.0, 0.0), "centre": 0.6}
for _proto, _size in (("legacy-straight-rail", (2.4, 2.1)), ("legacy-curved-rail", (4.8, 7.8))):
    SPECS[_proto] = dict(_RAIL, size=_size, budget=9000)
    SPECS[_proto + "-ne"] = dict(_RAIL, size=_size if _proto != "legacy-straight-rail" else (2.5, 2.5), base=_proto,
                                 budget=9000)
# The detail pass on the big Space Age machines (their sprites' plates, rivets, seams, ribbed hoses,
# cages and grilles) needs more than the usual machine budget, like assembler 1 and the drill.
for _name in ("foundry", "biochamber", "agricultural-tower", "heating-tower", "biolab", "captive-biter-spawner",
              "cryogenic-plant", "fusion-reactor", "fusion-generator"):
    SPECS[_name]["budget"] = 14000
