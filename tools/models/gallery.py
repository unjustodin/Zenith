#!/usr/bin/env python3
"""Builds a local comparison page: every model in client/assets/models next to Factorio's own
sprite, rendered from Factorio's camera, and tagged with where the model came from.

    python tools/models/gallery.py [names...]      -> art-src/compare/index.html

Each card also shows the model's screenshots from the client, if art-src/shots/<model>/ has any
(factorio.png, north/east/south/west.png, low.png, close.png, night.png; see shot_strip).

Tags: "Wube 3D release" (converted by tools/models/wube.py from Wube's printable models),
"Built from sprite reference" (rebuilt against the sprites, see tools/models/model_sources.json),
"Old generated placeholder" (made before the art rule, still to redo).

The sprites are read from the player's Factorio install by tools/models/compare.py and
tools/models/nature/compare.py, so the images and the page go to the git-ignored art-src/:
they contain Factorio's art and must never be committed or uploaded.
"""

import base64
import html
import io
import json
import os
import re
import struct
import subprocess
import sys

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
MODELS = os.path.join(REPO, "client", "assets", "models")
OUT = os.path.join(REPO, "art-src", "compare")
SOURCES = os.path.join(HERE, "model_sources.json")
BLENDER = os.environ.get("BLENDER", r"C:\Program Files\Blender Foundation\Blender 5.2\blender.exe")
FACTORIO = os.environ.get("FACTORIO", r"C:\Program Files (x86)\Steam\steamapps\common\Factorio")
WUBE_GENERATOR = "factorio-3d tools/models/wube.py"

# compare.py arguments per building, copied from Factorio's prototype definitions
# (data/base/prototypes/entity/*.lua and the sprite_load .lua files next to the sheets).
G = "data/base/graphics/entity/"
BUILDINGS = {
    "lab": [G + "lab/lab.png", "--frame=194x174", "--line=11", "--shift=0,1.5"],
    "boiler": [G + "boiler/boiler-N-idle.png", "--frame=269x221", "--shift=-1.25,5.25"],
    "steam-engine": [G + "steam-engine/steam-engine-V.png", "--frame=225x391", "--line=8", "--shift=4.75,-6.25"],
    "gun-turret": [G + "gun-turret/gun-turret-base.png", "--frame=150x118", "--shift=0.5,-1",
                   "--layer=" + os.path.join(FACTORIO, G, "gun-turret/gun-turret-shooting-1.png") + "|132x130|0|2|0,-27.5"],
    "burner-mining-drill": [G + "burner-mining-drill/burner-mining-drill-N.png", "--frame=174x188", "--line=4", "--shift=2.75,0.5"],
    "wooden-chest": [G + "wooden-chest/wooden-chest.png", "--frame=62x72", "--shift=0.5,-2"],
    "iron-chest": [G + "iron-chest/iron-chest.png", "--frame=66x76", "--shift=-0.5,-0.5"],
    "steel-chest": [G + "steel-chest/steel-chest.png", "--frame=64x80", "--shift=-0.25,-0.5"],
    "stone-furnace": [G + "stone-furnace/stone-furnace.png", "--frame=151x146", "--shift=-0.25,6"],
    "small-electric-pole": [G + "small-electric-pole/small-electric-pole.png", "--frame=72x220", "--line=4", "--shift=1.5,-42.5"],
    "assembling-machine-1": [G + "assembling-machine-1/assembling-machine-1-base.png", "--frame=198x184", "--line=1", "--shift=0,4"],
    "electric-mining-drill": [G + "electric-mining-drill/electric-mining-drill-N.png", "--frame=190x208", "--line=1", "--shift=0,-4",
                              "--layer=" + os.path.join(FACTORIO, G, "electric-mining-drill/electric-mining-drill.png") + "|162x156|0|6|1,-11"],
    "splitter": [G + "splitter/splitter-north.png", "--frame=160x70", "--line=8", "--shift=7,0"],
    "stone-wall": [G + "wall/wall-single.png", "--frame=64x86", "--line=2", "--shift=0,-5"],
    # Belt sheet: 16 animation frames per row, one row per shape (transport-belts.lua): north is
    # row 3; rows are named by the edge items come in from, so west-to-north (row 7) is a left
    # turn into north and east-to-north (row 5) a right turn.
    "transport-belt": [G + "transport-belt/transport-belt.png", "--frame=128x128", "--line=16", "--index=32"],
    "transport-belt-curve-left": [G + "transport-belt/transport-belt.png", "--frame=128x128", "--line=16", "--index=96"],
    "transport-belt-curve-right": [G + "transport-belt/transport-belt.png", "--frame=128x128", "--line=16", "--index=64"],
    # Underground structure sheet: columns are directions (north first), row 1 the entrance, row 0
    # the exit. It's only the hood; the belt under it is drawn from the belt sheet in the game.
    "underground-belt-input": [G + "underground-belt/underground-belt-structure.png", "--frame=192x192", "--line=4", "--index=4"],
    "underground-belt-output": [G + "underground-belt/underground-belt-structure.png", "--frame=192x192", "--line=4", "--index=0"],
}
_E = os.path.join(FACTORIO, G)
BUILDINGS.update({
    "offshore-pump": [G + "offshore-pump/offshore-pump_North.png", "--frame=90x162", "--line=8", "--shift=-1,-15"],
    "pipe": [G + "pipe/pipe-straight-vertical.png", "--frame=128x128"],
    "pipe-to-ground": [G + "pipe-to-ground/pipe-to-ground-up.png", "--frame=128x128"],
    "pipe-to-ground-east": [G + "pipe-to-ground/pipe-to-ground-right.png", "--frame=128x128"],
    "pipe-to-ground-south": [G + "pipe-to-ground/pipe-to-ground-down.png", "--frame=128x128"],
    "pipe-to-ground-west": [G + "pipe-to-ground/pipe-to-ground-left.png", "--frame=128x128"],
    "storage-tank": [G + "storage-tank/storage-tank.png", "--frame=219x235", "--line=2", "--shift=-0.25,-1.25"],
    "medium-electric-pole": [G + "medium-electric-pole/medium-electric-pole.png", "--frame=84x252", "--line=4", "--shift=3.5,-44"],
    "big-electric-pole": [G + "big-electric-pole/big-electric-pole.png", "--frame=148x312", "--line=4", "--shift=0,-51"],
    "substation": [G + "substation/substation.png", "--frame=138x270", "--line=4", "--shift=0,-31"],
    "small-lamp": [G + "small-lamp/lamp.png", "--frame=83x70", "--shift=0.25,3"],
    "solar-panel": [G + "solar-panel/solar-panel.png", "--frame=230x224", "--shift=-3,3.5"],
    "accumulator": [G + "accumulator/accumulator.png", "--frame=130x189", "--shift=0,-11"],
    "radar": [G + "radar/radar.png", "--frame=196x254", "--line=8", "--shift=1,-16"],
    "pumpjack": [G + "pumpjack/pumpjack-base.png", "--frame=261x273", "--line=4", "--shift=-2.25,-4.75",
                 "--layer=" + _E + "pumpjack/pumpjack-horsehead.png|206x172|0|8|-4.5,-29"],
    "chemical-plant": [G + "chemical-plant/chemical-plant-north-base.png", "--frame=204x292", "--line=1", "--shift=1,-9",
                       "--layer=" + _E + "chemical-plant/chemical-plant-north-anim-1.png|114x68|0|4|-0.5,-36"],
    "oil-refinery": [G + "oil-refinery/north/oil-refinery-north.png", "--frame=356x446", "--line=1", "--shift=0,-10"],
    "car": [G + "car/car-1.png", "--frame=201x172", "--line=2", "--shift=2,-3",
            "--layer=" + _E + "car/car-turret-1.png|71x57|0|1|2,-25"],
    # Trains at orientation 0.25 (east): their north and south frames are drawn stretched.
    "locomotive": [G + "locomotive/locomotive-3.png", "--frame=474x458", "--line=4", "--shift=0,-16", "--rot=90"],
    "cargo-wagon": [G + "cargo-wagon/cargo-wagon-3.png", "--frame=442x408", "--line=4", "--shift=0,-25", "--rot=90"],
    "fluid-wagon": [G + "fluid-wagon/fluid-wagon-3.png", "--frame=416x420", "--line=4", "--shift=0,-31.5", "--rot=90"],
})
# Factorio draws the trains' wheels as their own layer at each bogie (sprite_projection.py).
for _train in ("locomotive", "cargo-wagon", "fluid-wagon"):
    BUILDINGS[_train] += ["--layer=" + _E + "train-wheel/train-wheel-3.png|230x228|0|4|%g,1" % x for x in (64.5, -63.5)]
# Logistics, circuits and mid-game machines (circuits.py, logistics.py).
BUILDINGS.update({
    "arithmetic-combinator": [G + "combinator/arithmetic-combinator.png", "--frame=144x124", "--line=4", "--shift=0.5,7.5"],
    "decider-combinator": [G + "combinator/decider-combinator.png", "--frame=156x132", "--line=4", "--shift=0.5,7.5"],
    "selector-combinator": [G + "combinator/selector-combinator.png", "--frame=154x160", "--line=4", "--shift=1,-1"],
    "constant-combinator": [G + "combinator/constant-combinator.png", "--frame=114x102", "--line=4", "--shift=0,5"],
    "power-switch": [G + "power-switch/power-switch.png", "--frame=168x138", "--line=2", "--shift=-3,2"],
    "programmable-speaker": [G + "programmable-speaker/programmable-speaker.png", "--frame=59x178", "--shift=-2.25,-39.5"],
    "display-panel": [G + "display-panel/display-panel.png", "--frame=128x128", "--line=4"],
    "one-way-valve": [G + "one-way-valve/one-way-valve-north.png", "--frame=64x64"],
    "overflow-valve": [G + "overflow-valve/overflow-valve-north.png", "--frame=64x64"],
    "top-up-valve": [G + "top-up-valve/top-up-valve-north.png", "--frame=64x64"],
    "pump": [G + "pump/pump-north.png", "--frame=103x164", "--line=8", "--shift=8,-0.85"],
    "electric-furnace": [G + "electric-furnace/electric-furnace.png", "--frame=239x219", "--shift=0.75,5.75"],
    "beacon": [G + "beacon/beacon-bottom.png", "--frame=212x192", "--shift=0.5,1",
               "--layer=" + _E + "beacon/beacon-top.png|96x140|0|1|3,-19"],
    "assembling-machine-2": [G + "assembling-machine-2/assembling-machine-2-base.png", "--frame=200x188", "--line=1", "--shift=0,2.5",
                             "--layer=" + _E + "assembling-machine-2/assembling-machine-2-anim.png|148x158|0|8|1.5,-15.5"],
    "assembling-machine-3": [G + "assembling-machine-3/assembling-machine-3-base.png", "--frame=196x192", "--line=1", "--shift=-0.5,2.5",
                             "--layer=" + _E + "assembling-machine-3/assembling-machine-3-anim.png|140x160|0|8|1,-16"],
    "roboport": [G + "roboport/roboport-base.png", "--frame=228x277", "--shift=2,-2.25",
                 "--layer=" + _E + "roboport/roboport-door-up.png|97x38|0|16|-0.25,-39.5",
                 "--layer=" + _E + "roboport/roboport-door-down.png|97x41|0|16|-0.25,-19.75"],
    "logistic-robot": [G + "logistic-robot/logistic-robot.png", "--frame=80x84", "--line=16", "--index=16", "--shift=0,-3", "--anchor=0.1"],
    "construction-robot": [G + "construction-robot/construction-robot.png", "--frame=66x76", "--line=16", "--shift=0,-4.5", "--anchor=0.1"],
    "crude-oil": [G + "crude-oil/crude-oil.png", "--frame=168x124", "--line=4", "--shift=0.5,-2", "--anchor=0"],
})
for _shape in ("straight-vertical-single", "straight-vertical", "straight-horizontal", "corner-up-right",
               "corner-up-left", "corner-down-right", "corner-down-left", "t-up", "t-down", "t-left", "t-right",
               "cross", "ending-up", "ending-down", "ending-left", "ending-right"):
    _px = 160 if _shape == "straight-vertical-single" else 128
    BUILDINGS["pipe-" + _shape] = [G + "pipe/pipe-%s.png" % _shape, "--frame=%dx%d" % (_px, _px)]
# Wube's logistic chests (first lid frame), steel furnace and inserter platforms (north picture).
for _chest in ("passive-provider-chest", "active-provider-chest", "storage-chest", "buffer-chest", "requester-chest"):
    BUILDINGS[_chest] = [G + "logistic-chest/%s.png" % _chest, "--frame=66x74", "--line=7", "--shift=0,-2"]
BUILDINGS["steel-furnace"] = [G + "steel-furnace/steel-furnace.png", "--frame=171x174", "--shift=-1.25,2"]
for _ins in ("burner-inserter", "inserter", "long-handed-inserter", "fast-inserter", "bulk-inserter"):
    BUILDINGS[_ins] = [G + "%s/%s-platform.png" % (_ins, _ins), "--frame=105x79", "--line=4", "--shift=1.5,6.5"]
BUILDINGS["stack-inserter"] = ["data/space-age/graphics/entity/stack-inserter/stack-inserter-platform.png",
                               "--frame=105x79", "--line=4", "--shift=1.5,6.5"]
# Gleba plants: (scale multiplier, frame width, height, shift) from gleba_tree_variations in plants.lua;
# sheets are drawn at 0.33 x the multiplier. Variation 1 (the sheet's first frame) fits the model.
GLEBA_PLANTS = {
    "yumako-tree": (1.3, 640, 560, (52, -73)), "jellystem": (1.3, 640, 560, (52, -73)), "cuttlepop": (1, 640, 560, (52, -40)),
    "slipstack": (1, 640, 560, (52, -65)), "funneltrunk": (1, 640, 560, (52, -65)), "hairyclubnub": (1, 640, 560, (52, -65)),
    "teflilly": (1, 640, 560, (52, -60)), "lickmaw": (1, 640, 560, (52, -60)), "stingfrond": (1.1, 640, 560, (52, -60)),
    "boompuff": (0.9, 640, 560, (49, -40)), "sunnycomb": (1, 640, 560, (52, -60)), "water-cane": (1, 340, 290, (30, -28)),
}
# Space Age, Gleba and Aquilo (tools/models/gleba.py, aquilo.py; m-space2).
SA = "data/space-age/graphics/entity/"
_SA = os.path.join(FACTORIO, SA)
BUILDINGS.update({
    "biochamber": [SA + "biochamber/biochamber.png", "--frame=238x268", "--shift=-0.5,-7.5",
                   "--layer=" + _SA + "biochamber/biochamber-animation.png|92x144|0|8|23.5,-9.5",
                   "--layer=" + _SA + "biochamber/biochamber-animation-dome.png|92x148|0|8|-15.5,-14"],
    "agricultural-tower": [SA + "agricultural-tower/agricultural-tower-base.png", "--frame=228x330", "--shift=-2.5,-17.5"],
    "heating-tower": [SA + "heating-tower/heating-tower-main.png", "--frame=214x320", "--shift=-1,-22.5"],
    "biolab": [SA + "biolab/biolab-anim.png", "--frame=366x404", "--line=8", "--shift=2,-5"],
    "captive-biter-spawner": [SA + "captive-spawner/captive-anim.png", "--frame=380x338", "--line=8", "--shift=-2.5,-1.5"],
    # sprite_load adds the prototype's shift (-20 px) to the .lua file's own.
    "rocket-turret": [SA + "rocket-turret/rocket-turret-base.png", "--frame=202x168", "--shift=-0.5,4.5",
                      "--layer=" + _SA + "rocket-turret/rocket-turret-shooting-1.png|160x164|0|1|0,-28.5"],
    "cryogenic-plant": [SA + "cryogenic-plant/cryogenic-plant-main.png", "--frame=380x396", "--shift=3,-3.5",
                        "--layer=" + _SA + "cryogenic-plant/cryogenic-plant-glass.png|274x228|0|1|4,-7.5",
                        "--stretch=1.346"],
    "lithium-iceberg-big": ["data/space-age/graphics/decorative/lithium-iceberg-big/lithium-iceberg-big-1.png", "--frame=230x156",
                            "--shift=3.2,-8", "--anchor=0"],
    "lithium-iceberg-huge": ["data/space-age/graphics/decorative/lithium-iceberg-huge/lithium-iceberg-huge-2.png", "--frame=640x310",
                             "--shift=20.8,-24", "--anchor=0"],
    **{_n: [SA + "plant/%s/%s-trunk.png" % (_n, _n), "--frame=%dx%d" % (_w, _h), "--line=1", "--shift=%s,%s" % _sh,
            "--scale=%.4f" % (0.33 * _m), "--anchor=0",
            "--layer=" + _SA + "plant/%s/%s-harvest.png|%dx%d|0|1|%s,%s" % (_n, _n, _w, _h, _sh[0], _sh[1])]
       for _n, (_m, _w, _h, _sh) in GLEBA_PLANTS.items()},
    "gleba-spawner": [SA + "gleba-spawner/spawner-upper-1.png", "--frame=330x284", "--line=8", "--shift=5,17"],
    "gleba-spawner-small": [SA + "gleba-spawner/small/spawner-upper-small-1.png", "--frame=132x102", "--line=8", "--shift=-2,0"],
    # Flying: its sheet is drawn 66.5 px up, the model sits on its origin (the client lifts it).
    "capture-robot": [SA + "capture-robot-rocket/capture-robot.png", "--frame=190x184", "--line=8", "--shift=0,-66.5", "--anchor=-2.55"],
    "lithium-brine": [SA + "lithium-brine/lithium-brine.png", "--frame=166x120", "--line=4", "--shift=1.5,4.5", "--anchor=0"],
    "fluorine-vent": [SA + "fluorine-vent/fluorine-vent.png", "--frame=194x136", "--line=4", "--shift=-0.5,-3", "--anchor=0"],
    "railgun-turret": [SA + "railgun-turret/railgun-turret-base.png", "--frame=416x354", "--line=4", "--shift=15,-3.5",
                       "--layer=" + _SA + "railgun-turret/railgun-turret-shooting-N.png|258x214|9|7|-2,-52"],
    "fusion-generator": [SA + "fusion-generator/north/fusion-generator-north.png", "--frame=244x376", "--line=3", "--shift=-2,-2",
                         "--stretch=1.346"],
    "fusion-reactor": [SA + "fusion-reactor/fusion-reactor-main.png", "--frame=444x456", "--shift=1,-5.5",
                       "--layer=" + _SA + "fusion-reactor/fusion-reactor-connection-1.png|124x94|0|5|-50.5,-90.5",
                       "--layer=" + _SA + "fusion-reactor/fusion-reactor-connection-2.png|108x58|0|5|51.5,-103.5",
                       "--layer=" + _SA + "fusion-reactor/fusion-reactor-connection-3.png|94x144|0|5|86,-56",
                       "--layer=" + _SA + "fusion-reactor/fusion-reactor-connection-4.png|84x160|0|5|91,47",
                       "--layer=" + _SA + "fusion-reactor/fusion-reactor-connection-5.png|174x136|0|5|58,83",
                       "--layer=" + _SA + "fusion-reactor/fusion-reactor-connection-6.png|128x146|0|5|-47.5,78",
                       "--layer=" + _SA + "fusion-reactor/fusion-reactor-connection-7.png|52x156|0|5|-101.5,47.5",
                       "--layer=" + _SA + "fusion-reactor/fusion-reactor-connection-8.png|124x128|0|5|-82,-61.5",
                       "--stretch=1.346"],
})

# Railway (tools/models/railway.py) and the wall pieces (Wube's walls set). Rails are drawn
# straight down in Factorio, which this camera can't show: they're checked in the client.
_ER = "data/elevated-rails/graphics/entity/"
BUILDINGS.update({
    "rail-signal": [G + "rail-signal/rail-signal.png", "--frame=128x128", "--line=3"],
    "rail-chain-signal": [G + "rail-chain-signal/rail-chain-signal.png", "--frame=100x98", "--line=4", "--shift=0.5,0"],
    "train-stop": [G + "train-stop/train-stop-bottom.png", "--frame=140x291", "--line=4", "--shift=-0.5,-26.75",
                   "--layer=" + os.path.join(FACTORIO, G, "train-stop/train-stop-top.png") + "|312x306|0|4|0.5,-50.5"],
    "gate": [G + "gate/gate-vertical.png", "--frame=78x120", "--line=8", "--shift=-1,-13"],
    "rail-support": [_ER + "elevated-rail-pylon/elevated-rail-pylon.png", "--frame=280x430", "--line=4", "--shift=0,-36"],
})
_WALL_PICTURES = {
    0: ("single", 86, 2, -5), 4: ("vertical", 134, 5, 8), 10: ("horizontal", 92, 6, -2),
    6: ("corner-right", 128, 2, 7), 12: ("corner-left", 134, 2, 7), 14: ("t", 134, 4, 7),
    2: ("ending-right", 92, 2, -3), 8: ("ending-left", 92, 2, -3),
}
_WALL_SHAPES = ("pylon", "n", "e", "ne", "s", "ns", "es", "nes", "w", "nw", "ew", "new", "sw", "nsw", "esw", "nesw")
for _mask, _shape in enumerate(_WALL_SHAPES):
    _picture = _WALL_PICTURES[_mask & 14]
    _sprite = G + "wall/wall-%s.png" % _picture[0]
    _wall = ["--frame=64x%d" % _picture[1], "--line=%d" % _picture[2], "--shift=0,%d" % _picture[3]]
    BUILDINGS["stone-wall-" + _shape] = [_sprite, *_wall]
    _fill_name = "stone-wall-%s-fill" % _shape
    if _mask & 6 == 6 and os.path.exists(os.path.join(MODELS, _fill_name + ".glb")):
        BUILDINGS[_fill_name] = [_sprite, *_wall,
                                 "--layer=" + os.path.join(FACTORIO, G, "wall/wall-filling.png") + "|48x56|0|8|16,15"]

# Stretched like sprite_projection.py's TRUE_PROPORTIONS.
for _name in ("assembling-machine-1", "stone-furnace", "steel-furnace", "wooden-chest", "iron-chest", "steel-chest",
              "small-electric-pole", "electric-mining-drill", "splitter", "boiler", "storage-tank", "chemical-plant",
              "transport-belt", "transport-belt-curve-left", "transport-belt-curve-right",
              "passive-provider-chest", "active-provider-chest", "storage-chest", "buffer-chest", "requester-chest"):
    if _name in BUILDINGS:
        BUILDINGS[_name] = BUILDINGS[_name] + ["--stretch=1.346"]
# Fitted like sprite_projection.py's PIPE_FIT: their tiles are square on screen.
for _name in [n for n in BUILDINGS if n.startswith("pipe")] + ["offshore-pump"]:
    BUILDINGS[_name] = BUILDINGS[_name] + ["--anchor=0.375", "--stretch=1.346"]

# Military (military.py). Turret heads and cannons as layers at rest, pointing north; the
# artillery cannon sits cannon_base_shift (0.97 tiles) up, the wagon's 1.67 up and 2.07 tiles back.
_AW = "artillery-wagon/artillery-wagon-cannon-"
BUILDINGS.update({
    "laser-turret": [G + "laser-turret/laser-turret-base.png", "--frame=138x104", "--shift=-0.5,2",
                     "--layer=" + _E + "laser-turret/laser-turret-shooting.png|126x120|0|8|0,-35"],
    "flamethrower-turret": [G + "flamethrower-turret/flamethrower-turret-base-north.png", "--frame=158x196", "--shift=-1,13",
                            "--layer=" + _E + "flamethrower-turret/flamethrower-turret-gun.png|158x128|0|8|-1,-31"],
    "land-mine": [G + "land-mine/land-mine.png", "--frame=64x64"],
    "artillery-turret": [G + "artillery-turret/artillery-turret-base.png", "--frame=207x199",
                         "--layer=" + _E + _AW + "base-1.png|378x280|0|4|0,-74.6",
                         "--layer=" + _E + _AW + "barrel-1.png|530x384|0|4|0,-87.1"],
    "tank": [G + "tank/tank-base-1.png", "--frame=270x212", "--line=2", "--shift=0,-10",
             "--layer=" + _E + "tank/tank-turret.png|179x132|0|8|0.25,-34.5"],
    "spidertron": [G + "spidertron/torso/spidertron-body-bottom.png", "--frame=126x106", "--shift=0,-48",
                   "--layer=" + _E + "spidertron/torso/spidertron-body.png|132x138|0|8|0,-67"],
    "artillery-wagon": [G + "artillery-wagon/artillery-wagon-base-3.png", "--frame=476x410", "--line=4", "--shift=0.5,-27.5",
                        "--rot=90", "--layer=" + _E + _AW + "base-3.png|378x280|0|4|-66.2,-97",
                        "--layer=" + _E + _AW + "barrel-3.png|530x384|0|4|-66.2,-109.5"],
    "defender": [G + "defender-robot/defender-robot.png", "--frame=56x59", "--line=16", "--shift=0,0.25", "--anchor=0.3"],
    "distractor": [G + "distractor-robot/distractor-robot.png", "--frame=72x62", "--line=16", "--shift=0,-2.5", "--anchor=0.35"],
    "destroyer": [G + "destroyer-robot/destroyer-robot.png", "--frame=88x77", "--line=32", "--index=32", "--shift=2.5,-1.25",
                  "--anchor=0.28"],
})
# Nuclear (nuclear.py).
BUILDINGS.update({
    "nuclear-reactor": [G + "nuclear-reactor/reactor.png", "--frame=302x318", "--shift=-5,-7"],
    "heat-exchanger": [G + "heat-exchanger/heatex-N-idle.png", "--frame=270x206", "--line=1", "--shift=-1,9.5"],
    "steam-turbine": [G + "steam-turbine/steam-turbine-V.png", "--frame=217x374", "--line=4", "--shift=4.75,0"],
    "centrifuge": [G + "centrifuge/centrifuge-ABC.png", "--frame=194x248", "--line=8", "--shift=-2.5,-18"],
    "heat-pipe": [G + "heat-pipe/heat-pipe-straight-vertical-1.png", "--frame=64x64"],
})
for _shape in ("straight-vertical", "straight-horizontal", "corner-up-right", "corner-up-left", "corner-down-right",
               "corner-down-left", "t-up", "t-down", "t-left", "t-right", "ending-up", "ending-down", "ending-left",
               "ending-right"):
    BUILDINGS["heat-pipe-" + _shape] = [G + "heat-pipe/heat-pipe-%s-1.png" % _shape, "--frame=64x64"]
BUILDINGS["heat-pipe-cross"] = [G + "heat-pipe/heat-pipe-t-1.png", "--frame=64x64"]
BUILDINGS["heat-pipe-straight-vertical-single"] = [G + "heat-pipe/heat-pipe-straight-vertical-single.png", "--frame=64x64"]
# Rockets and odds and ends (rocket.py). The silo with its doors closed; the pad's two main layers.
_RS = _E + "rocket-silo/"
BUILDINGS.update({
    "rocket-silo": [G + "rocket-silo/04-door-back.png", "--frame=312x286", "--shift=37,12",
                    "--layer=" + _RS + "05-door-front.png|332x300|0|1|-28,33",
                    "--layer=" + _RS + "06-rocket-silo.png|628x612|0|1|2,3.5",
                    "--layer=" + _RS + "14-rocket-silo-front.png|586x262|0|1|1,78"],
    "rocket-silo-rocket": [G + "rocket-silo/rocket-static-pod.png", "--frame=308x752", "--shift=-4,85", "--anchor=12.7"],
    "cargo-pod": [G + "cargo-pod/pod-static-detached.png", "--frame=78x172", "--shift=1,3", "--anchor=1.3"],
    "cargo-landing-pad": [G + "cargo-hubs/hubs/planet-hub-2.png", "--frame=476x500", "--shift=5.5,-34",
                          "--layer=" + _E + "cargo-hubs/hubs/planet-hub-3.png|498x506|0|1|0,-33"],
    "market": [G + "market/market.png", "--frame=156x127", "--shift=30.4,6.4", "--scale=1"],
    "loader": [G + "loader/loader-structure.png", "--frame=64x64", "--line=4", "--scale=1"],
})

# Space Age (tools/models/space_sprites.py).
import space_sprites  # noqa: E402
BUILDINGS.update({_n: space_sprites.compare_args(_n, FACTORIO) for _n in space_sprites.ENTRIES})

# Crash-site ship and wreck pieces: single frames and offsets from crash-site.lua,
# shared with sprite_projection.py.
_CRASH = G + "crash-site-spaceship/"
for _name, _file, _w, _h, _shift in (
        ("crash-site-spaceship", _CRASH + "spaceship.png", 1228, 790, (-13, 34)),
        ("crash-site-spaceship-wreck-big-1", _CRASH + "spaceship-wreck-big-1.png", 234, 280, (-7, -8)),
        ("crash-site-spaceship-wreck-big-2", _CRASH + "spaceship-wreck-big-2.png", 242, 258, (-13, -7)),
        ("crash-site-spaceship-wreck-medium-1", _CRASH + "spaceship-wreck-medium-1.png", 228, 120, (-14, -4)),
        ("crash-site-spaceship-wreck-medium-2", _CRASH + "spaceship-wreck-medium-2.png", 194, 150, (-15, 8)),
        ("crash-site-spaceship-wreck-medium-3", _CRASH + "spaceship-wreck-medium-3.png", 224, 236, (-30, 4)),
        ("crash-site-spaceship-wreck-small-1", _CRASH + "spaceship-wreck-small-1.png", 156, 152, (-9, -1)),
        ("crash-site-spaceship-wreck-small-2", _CRASH + "spaceship-wreck-small-2.png", 146, 102, (-8, 16)),
        ("crash-site-spaceship-wreck-small-3", _CRASH + "spaceship-wreck-small-3.png", 164, 148, (5, -1)),
        ("crash-site-spaceship-wreck-small-4", _CRASH + "spaceship-wreck-small-4.png", 168, 142, (1, -3)),
        ("crash-site-spaceship-wreck-small-5", _CRASH + "spaceship-wreck-small-5.png", 164, 120, (-6, -6)),
        ("crash-site-spaceship-wreck-small-6", _CRASH + "spaceship-wreck-small-6.png", 166, 114, (10, 9)),
        ("crash-site-chest-1", G + "crash-site-chests/crash-site-chest-1.png", 120, 76, (2, 8)),
        ("crash-site-chest-2", G + "crash-site-chests/crash-site-chest-2.png", 116, 88, (0, 8))):
    BUILDINGS[_name] = [_file, "--frame=%dx%d" % (_w, _h), "--shift=%g,%g" % _shift]

# Additional placeholder assets with sprite metadata in sprite_projection.py.
BUILDINGS["fish"] = [G + "fish/fish-1.png", "--frame=22x36", "--scale=1", "--anchor=0"]
BUILDINGS["lane-splitter"] = [G + "splitter/splitter-north.png", "--frame=160x70", "--line=8",
                              "--shift=3.5,0", "--scale=0.25"]
BUILDINGS["cargo-pod-container"] = [G + "cargo-pod/pod-landing.png", "--frame=192x258", "--line=7", "--index=12",
                                     "--shift=-10.5,8"]
BUILDINGS["landing-pad-unloading-bay"] = [SA + "cargo-hubs/extractor/extractor-n-1.png",
                                           "--frame=256x264", "--shift=-2,-44.5",
                                           "--layer=" + os.path.join(FACTORIO, "data/space-age/graphics/entity/cargo-hubs/extractor/extractor-n-4.png") + "|226x252|0|0|-1.5,-40"]
BUILDINGS["tree-plant"] = [SA + "plant/planted-tree/planted-tree-trunk.png", "--frame=640x560",
                           "--line=4", "--shift=70,-40", "--scale=0.429", "--anchor=0",
                           "--layer=" + os.path.join(FACTORIO, "data/space-age/graphics/entity/plant/planted-tree/planted-tree-harvest.png") + "|640x560|0|4|70,-40"]
BUILDINGS["loader-1x1"] = [G + "loader/loader-structure.png", "--frame=64x64", "--line=4", "--scale=1"]
BUILDINGS["big-biter"] = [G + "biter/biter-run-1.png", "--frame=398x310", "--line=8", "--index=0",
                          "--shift=-1,-5", "--scale=0.5", "--anchor=0"]
BUILDINGS["big-spitter"] = [G + "spitter/spitter-run-1.png", "--frame=250x220", "--line=6", "--index=0",
                            "--shift=0,-11", "--scale=0.5", "--anchor=0"]
BUILDINGS["biter-spawner"] = [G + "spawner/spawner-idle.png", "--frame=520x376", "--line=4", "--index=0",
                              "--shift=4,-3", "--scale=0.5", "--anchor=0"]
BUILDINGS["big-worm-turret"] = [G + "worm/worm-prepared.png", "--frame=190x300", "--line=9", "--index=0",
                                "--shift=-3,-41", "--scale=0.5", "--anchor=0"]
# The wriggler: the big tier (the client scales and tints the others from it).
BUILDINGS["big-wriggler-pentapod"] = [SA + "wriggler/wriggler-run-1.png", "--frame=284x228", "--line=5", "--index=0",
                                      "--shift=0,-5.5", "--scale=0.6", "--anchor=0"]

# Rail pieces use top-down sprite projection in the client. Build their comparison layers from
# the same frame metadata as sprite_projection.py instead of forcing them into the 48° building
# camera: rails are the exception whose source art and in-game projection are straight down.
_RAIL_PROJECTION = os.path.join(REPO, "client", "data", "sprite_projection.json")
with open(_RAIL_PROJECTION, encoding="utf-8") as _f:
    _projection_entries = json.load(_f)
for _name, _entry in _projection_entries.items():
    if not _name.startswith(("straight-rail", "half-diagonal-rail", "curved-rail-")) or _entry.get("projection") != "top":
        continue
    _layers = _entry["cells"][0]
    _primary = _layers[0]
    _w, _h = _primary["frame"]
    _line = 1
    _index = "@%d,%d" % tuple(_primary["xy"])
    _frame = "%dx%d" % (_w, _h)
    _shift = "%g,%g" % tuple(_primary.get("shift", (0, 0)))
    _args = ["--frame=" + _frame, "--line=" + str(_line), "--index=" + str(_index),
             "--shift=" + _shift, "--scale=" + str(_primary.get("scale", 0.5)), "--anchor=0",
             "--pitch=90", "--stretch=" + str(_entry.get("across", 1.0))]
    for _layer in _layers[1:]:
        _lw, _lh = _layer["frame"]
        _ll = 1
        _li = "@%d,%d" % tuple(_layer["xy"])
        _ls = "%g,%g" % tuple(_layer.get("shift", (0, 0)))
        _path = os.path.join(FACTORIO, "data", _layer["file"])
        _args.append("--layer=" + _path + "|%dx%d|%s|%d|%s" % (_lw, _lh, _li, _ll, _ls))
    BUILDINGS[_name] = [os.path.join(FACTORIO, "data", _primary["file"]), *_args]

# The ramp's sprite climbs through the whole 16-tile entity, so the client deliberately does not
# project it onto the mesh. Keep a side-by-side reference for the actual sprite and both layers.
_RAMP = "elevated-rails/graphics/entity/elevated-rail-ramp/"
BUILDINGS["rail-ramp"] = [os.path.join(FACTORIO, "data", _RAMP + "elevated-rail-ramp-base.png"),
                          "--frame=1036x1218", "--line=2",
                          "--shift=0,-44.5", "--scale=0.5", "--anchor=0",
                          "--layer=" + os.path.join(FACTORIO, "data", _RAMP + "elevated-rail-ramp.png") +
                          "|1036x1218|0|2|0,-44.5"]

# Inserter arm pieces are drawn independently around their joints by the client. Use the exact
# base/open/closed sprite frames and the prototype quarter-size scale for each model component.
_INSERTER_ARMS = {
    "basic": (G + "inserter/inserter-hand-base.png", 32, 136,
              G + "inserter/inserter-hand-open.png", 72, 164,
              G + "inserter/inserter-hand-closed.png", 72, 164),
    "long": (G + "long-handed-inserter/long-handed-inserter-hand-base.png", 32, 136,
             G + "long-handed-inserter/long-handed-inserter-hand-open.png", 72, 164,
             G + "long-handed-inserter/long-handed-inserter-hand-closed.png", 72, 164),
    "bulk": (G + "bulk-inserter/bulk-inserter-hand-base.png", 32, 136,
             G + "bulk-inserter/bulk-inserter-hand-open.png", 130, 164,
             G + "bulk-inserter/bulk-inserter-hand-closed.png", 100, 164),
    "stack": (SA + "stack-inserter/stack-inserter-hand-base.png", 32, 136,
              SA + "stack-inserter/stack-inserter-hand-open.png", 134, 164,
              SA + "stack-inserter/stack-inserter-hand-closed.png", 112, 164),
}
for _family, (_base_file, _bw, _bh, _open_file, _ow, _oh, _closed_file, _cw, _ch) in _INSERTER_ARMS.items():
    for _piece, _file, _w, _h in (("upper", _base_file, _bw, _bh),
                                  ("hand-open", _open_file, _ow, _oh),
                                  ("hand-closed", _closed_file, _cw, _ch)):
        BUILDINGS["inserter-arm-%s-%s" % (_family, _piece)] = [
            _file, "--frame=%dx%d" % (_w, _h), "--scale=0.25", "--anchor=0"]

# Default north frames for the player and corpse, with their color-mask layers composited over
# the base sprite. These use the same frames and pixel shifts as sprite_projection.py.
BUILDINGS["character"] = [G + "character/level1_idle.png", "--frame=92x116", "--line=22", "--shift=0,-21",
                          "--scale=0.5", "--anchor=0",
                          "--layer=" + os.path.join(FACTORIO, G, "character/level1_idle_mask.png") + "|56x90|0|22|0,-26"]
BUILDINGS["character-gun"] = [G + "character/level1_idle_gun.png", "--frame=110x128", "--line=22", "--shift=0,-22",
                              "--scale=0.5", "--anchor=0",
                              "--layer=" + os.path.join(FACTORIO, G, "character/level1_idle_gun_mask.png") + "|72x88|0|22|-0.5,-22"]
# Armour looks (armour_looks.py): the plain character's idle frame with the level 2 add-on (heavy and
# modular armour) or the level 3 one (power armour) and their masks over it.
for _level, _add, _mask in ((2, "level2addon_idle.png|56x86|0|22|0.5,-27.5", "level2addon_idle_mask.png|52x84|0|22|0,-28"),
                            (3, "level3addon_idle.png|74x86|0|22|0,-28", "level3addon_idle_mask.png|74x72|0|22|0,-31.5")):
    BUILDINGS["character-armor-%d" % _level] = BUILDINGS["character"] + [
        "--layer=" + os.path.join(FACTORIO, G, "character/" + _add), "--layer=" + os.path.join(FACTORIO, G, "character/" + _mask)]
# Mech armour (Space Age): mech-idle's first frame, 8 directions of 22 frames in rows of 11.
BUILDINGS["character-mech-armor"] = [SA + "mech-armor/mech-idle.png", "--frame=142x176", "--line=11", "--shift=1,-25.5",
                                     "--scale=0.5", "--anchor=0",
                                     "--layer=" + os.path.join(FACTORIO, SA, "mech-armor/mech-idle-mask.png") + "|134x150|0|11|0.5,-32"]
BUILDINGS["character-corpse"] = [G + "character/level1_dead.png", "--frame=114x112", "--line=2", "--shift=-7,-5.5",
                                 "--scale=0.5", "--anchor=0",
                                 "--layer=" + os.path.join(FACTORIO, G, "character/level1_dead_mask.png") + "|88x70|0|2|-2.5,-6.5",
                                 "--layer=" + os.path.join(FACTORIO, G, "character/level1_dead_shadow.png") + "|108x106|0|2|-3.5,-3"]

# Cliff pieces use the exact two-layer atlas frames from sprite_projection.py. Render their north
# cell here; the other three directions are separate runtime projection cells for the same model.
_CLIFF_PIECES = {"sides": ("sides", 0, (2, 3, 0, 1)), "outer": ("outer", 0, (3, 0, 1, 2)),
                 "inner": ("inner", 0, (0, 1, 2, 3)), "exit": ("entrance", 2, (0, 3, 2, 1)),
                 "entrance": ("entrance", 0, (0, 3, 2, 1))}
for _planet, _dir, _px in (("", "data/base/graphics/terrain/cliffs/cliff-", 256),
                           ("vulcanus-", "data/space-age/graphics/terrain/cliffs/vulcanus/cliff-vulcanus-", 512),
                           ("gleba-", "data/space-age/graphics/terrain/cliffs/gleba/cliff-gleba-", 512),
                           ("fulgora-", "data/space-age/graphics/terrain/cliffs/fulgora/cliff-fulgora-", 512)):
    for _kind, (_sheet, _col, _rows) in _CLIFF_PIECES.items():
        _line = 4 if _sheet == "entrance" else 8
        _index = _rows[0] * _line + _col
        _frame = "%dx%d" % (_px, _px)
        _lower = _dir + _sheet + "-lower.png"
        _upper = os.path.join(FACTORIO, _dir + _sheet + ".png")
        BUILDINGS["cliff-" + _planet + _kind] = [
            _lower, "--frame=" + _frame, "--line=" + str(_line), "--index=" + str(_index),
            "--scale=0.5", "--anchor=0",
            "--layer=" + _upper + "|" + _frame + "|" + str(_index) + "|" + str(_line) + "|0,0"]

NATURE = (["tree-0%d" % i for i in range(1, 10)]
          + ["dead-dry-hairy-tree", "dead-grey-trunk", "dead-tree-desert", "dry-hairy-tree", "dry-tree",
             "big-rock", "huge-rock", "big-sand-rock", "iron-ore", "copper-ore", "coal", "stone", "uranium-ore",
             "tree-02-red", "tree-06-brown", "tree-08-brown", "tree-08-red", "tree-09-brown", "tree-09-red"])
TAGS = {
    "wube": ("Wube 3D release", "#2f7d4a"),
    "sprite": ("Built from sprite reference", "#2c5c9c"),
    "old": ("Old generated placeholder", "#a2442e"),
}


def generator(path):
    try:
        with open(path, "rb") as f:
            head = f.read(20)
            doc = json.loads(f.read(struct.unpack_from("<I", head, 12)[0]))
        return doc.get("asset", {}).get("generator", "")
    except (OSError, ValueError, struct.error):
        return ""


def tag_for(name, sources):
    if generator(os.path.join(MODELS, name + ".glb")) == WUBE_GENERATOR:
        return "wube"
    return "sprite" if sources.get(name, sources.get("*", "")).startswith("Matched") else "old"


def render(name, out_png):
    """Runs the right comparison tool; returns an error string or None."""
    if name in BUILDINGS:
        sheet, *rest = BUILDINGS[name]
        args = ["tools/models/compare.py", "--", out_png, name, "--sprite=" + os.path.join(FACTORIO, sheet), *rest]
    elif name in NATURE:
        args = ["tools/models/nature/compare.py", "--", out_png, name, "--factorio", FACTORIO]
    else:
        return "no sprite comparison set up for this model yet"
    run = subprocess.run([BLENDER, "--background", "--factory-startup", "--python", *args],
                         cwd=REPO, capture_output=True, text=True)
    if run.returncode != 0 or not os.path.exists(out_png):
        tail = (run.stderr or run.stdout).strip().splitlines()[-3:]
        return "render failed: " + " / ".join(tail)
    overlap = re.findall(r"silhouette overlap ([\d.]+)", run.stdout)
    if overlap:
        print("%-28s silhouette overlap %s" % (name, overlap[-1]))
    return None


def main(argv):
    os.makedirs(OUT, exist_ok=True)
    sources = json.load(open(SOURCES, encoding="utf-8")) if os.path.exists(SOURCES) else {}
    names = argv[1:] or sorted(f[:-4] for f in os.listdir(MODELS) if f.endswith(".glb"))
    results = {}
    for name in names:
        png = os.path.join(OUT, name + ".png")
        if os.path.exists(png):
            os.remove(png)
        error = render(name, png)
        results[name] = (tag_for(name, sources), error)
        print("%-28s %-28s %s" % (name, TAGS[results[name][0]][0], error or "ok"))
    write_page(sources)


## Screenshots of a finished model in the client, saved by whoever finished it as
## art-src/shots/<model>/<view>.png; the views below come first in this order, others after.
SHOTS = os.path.join(REPO, "art-src", "shots")
SHOT_ORDER = ("factorio", "north", "east", "south", "west", "low", "close", "night")


def shot_strip(name):
    folder = os.path.join(SHOTS, name)
    if not os.path.isdir(folder):
        return ""
    views = sorted((f[:-4] for f in os.listdir(folder) if f.lower().endswith(".png")),
                   key=lambda v: (SHOT_ORDER.index(v) if v in SHOT_ORDER else len(SHOT_ORDER), v))
    figures = []
    for view in views:
        image = Image.open(os.path.join(folder, view + ".png")).convert("RGB")
        image.thumbnail((480, 480))
        buf = io.BytesIO()
        image.save(buf, "JPEG", quality=80)
        figures.append('<figure><img src="data:image/jpeg;base64,%s" alt="%s, %s"><figcaption>%s</figcaption></figure>'
                       % (base64.b64encode(buf.getvalue()).decode(), html.escape(name), html.escape(view), html.escape(view)))
    return '<h3>In the client</h3><div class="shots">%s</div>' % "".join(figures) if figures else ""


def write_page(sources):
    names = sorted(f[:-4] for f in os.listdir(MODELS) if f.endswith(".glb"))
    order = {"old": 0, "sprite": 1, "wube": 2}
    rows = sorted(((tag_for(n, sources), n) for n in names), key=lambda t: (order[t[0]], t[1]))
    counts = {k: sum(1 for t, _ in rows if t == k) for k in TAGS}
    cards = []
    for tag, name in rows:
        label, colour = TAGS[tag]
        png = os.path.join(OUT, name + ".png")
        if os.path.exists(png):
            # Embedded as JPEG, so the page is one small file (previews don't load files next to it).
            buf = io.BytesIO()
            Image.open(png).convert("RGB").save(buf, "JPEG", quality=82)
            data = base64.b64encode(buf.getvalue()).decode()
            body = '<img src="data:image/jpeg;base64,%s" alt="%s: Factorio sprite, our model, outlines">' % (data, html.escape(name))
        else:
            body = '<p class="none">No sprite comparison for this model yet.</p>'
        body += shot_strip(name)
        cards.append('<section class="card"><h2>%s <span class="tag" style="background:%s">%s</span></h2>%s</section>'
                     % (html.escape(name), colour, label, body))
    legend = " ".join('<span class="tag" style="background:%s">%s: %d</span>' % (c, l, counts[k]) for k, (l, c) in TAGS.items())
    page = """<!doctype html><meta charset="utf-8"><title>Model comparisons</title>
<style>
body { font: 15px/1.4 system-ui, sans-serif; margin: 0; padding: 16px; background: #1d1f1b; color: #e8e6df; }
h1 { font-size: 20px; margin: 0 0 6px; } p.lede { margin: 0 0 12px; color: #b9b6ab; max-width: 70ch; }
.tag { display: inline-block; font-size: 12px; font-weight: 600; padding: 2px 8px; border-radius: 10px; color: #fff; vertical-align: middle; }
.card { background: #2a2c27; border: 1px solid #3b3d36; border-radius: 8px; padding: 10px 12px; margin: 12px 0; }
.card h2 { font-size: 16px; margin: 0 0 8px; } .card img { max-width: 100%%; height: auto; display: block; }
.none { color: #b9b6ab; margin: 0; }
.card h3 { font-size: 13px; margin: 10px 0 6px; color: #b9b6ab; font-weight: 600; }
.shots { display: flex; flex-wrap: wrap; gap: 8px; } .shots figure { margin: 0; flex: 1 1 220px; max-width: 320px; }
.shots figcaption { font-size: 12px; color: #b9b6ab; }
</style>
<h1>Model comparisons</h1>
<p class="lede">Each row: Factorio's sprite, our model from the same camera, and both outlines (sprite cyan, model red).
Built on this PC from your Factorio install; it contains Factorio's art, so it stays here and is never committed.</p>
<p>%s</p>
%s
""" % (legend, "\n".join(cards))
    with open(os.path.join(OUT, "index.html"), "w", encoding="utf-8") as f:
        f.write(page)
    print("page: %s" % os.path.join(OUT, "index.html"))


if __name__ == "__main__":
    main(sys.argv)
