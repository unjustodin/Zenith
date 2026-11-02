#!/usr/bin/env python3
"""Writes client/data/sprite_projection.json: where each model's Factorio sprite is in the game's
files and how it lines up, so the client can project the sprite onto the model at runtime.

    python tools/models/sprite_projection.py [--factorio DIR]

Only numbers and file names go into the JSON: the client reads the sheets from the player's own
Factorio install, and no image made from them is ever written here. The buildings' numbers are
copied from data/base/prototypes/entity/*.lua (the same ones tools/models/gallery.py passes to
compare.py); trees, dead trees, rocks and ores are read from trees.lua, decoratives.lua and
resources.lua the way tools/models/nature/compare.py does. The format is described in
client/assets/models/README.md.
"""

import json
import math
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
OUT = os.path.join(REPO, "client", "data", "sprite_projection.json")
FACTORIO = r"C:\Program Files (x86)\Steam\steamapps\common\Factorio"
BUILDING_ANCHOR = 0.3   # tools/models/compare.py FACTORIO_ANCHOR_Z
NATURE_ANCHOR = 0.0     # tools/models/nature/compare.py anchors on the ground
G = "base/graphics/entity/"


def layer(file, w, h, shift=(0.0, 0.0), line=0, index=0, scale=0.5, tint=None):
    out = {"file": file, "frame": [w, h], "line": line, "index": index, "shift": list(shift), "scale": scale}
    if tint is not None:
        out["tint"] = [round(c, 4) for c in tint]
    return out


def single(*layers, anchor=BUILDING_ANCHOR):
    return {"anchor": anchor, "cells": [list(layers)]}


def directional(n, e, s, w, anchor=BUILDING_ANCHOR):
    """One cell per direction the entity faces: north, east, south, west."""
    return {"anchor": anchor, "mode": "direction", "cells": [[n], [e], [s], [w]]}


BUILDINGS = {
    "lab": single(layer(G + "lab/lab.png", 194, 174, (0, 1.5), line=11)),
    # Steam power: a model per direction (power.py, facings.py), drawn unturned, each with its own
    # picture. The steam engine has one picture per axis (V for north and south, H for east and west).
    "boiler": single(layer(G + "boiler/boiler-N-idle.png", 269, 221, (-1.25, 5.25))),
    "boiler-east": single(layer(G + "boiler/boiler-E-idle.png", 216, 301, (-3, 1.25))),
    "boiler-south": single(layer(G + "boiler/boiler-S-idle.png", 260, 192, (4, 13))),
    "boiler-west": single(layer(G + "boiler/boiler-W-idle.png", 196, 273, (1.5, 7.75))),
    "steam-engine": single(layer(G + "steam-engine/steam-engine-V.png", 225, 391, (4.75, -6.25), line=8)),
    "steam-engine-east": single(layer(G + "steam-engine/steam-engine-H.png", 352, 257, (1, -4.75), line=8)),
    # The base and the raised head, as the model has it: the prepared animation's first frame
    # facing north (gun-turret-shooting-1.png: 64 directions in four sheets of 16 rows, two
    # frames per row, north first).
    "gun-turret": single(layer(G + "gun-turret/gun-turret-base.png", 150, 118, (0.5, -1)),
                         layer(G + "gun-turret/gun-turret-shooting-1.png", 132, 130, (0, -27.5), line=2)),
    # The burner drill: a model per direction (machines.py DRILL_FACINGS), drawn unturned.
    "burner-mining-drill": single(layer(G + "burner-mining-drill/burner-mining-drill-N.png", 174, 188, (2.75, 0.5), line=4)),
    "burner-mining-drill-east": single(layer(G + "burner-mining-drill/burner-mining-drill-E.png", 186, 168, (2.75, 1), line=4)),
    "burner-mining-drill-south": single(layer(G + "burner-mining-drill/burner-mining-drill-S.png", 174, 174, (0.5, -0.5), line=4)),
    "burner-mining-drill-west": single(layer(G + "burner-mining-drill/burner-mining-drill-W.png", 180, 176, (-1.5, 0), line=4)),
    "wooden-chest": single(layer(G + "wooden-chest/wooden-chest.png", 62, 72, (0.5, -2))),
    "iron-chest": single(layer(G + "iron-chest/iron-chest.png", 66, 76, (-0.5, -0.5))),
    "steel-chest": single(layer(G + "steel-chest/steel-chest.png", 64, 80, (-0.25, -0.5))),
    "stone-furnace": single(layer(G + "stone-furnace/stone-furnace.png", 151, 146, (-0.25, 6))),
    "small-electric-pole": single(layer(G + "small-electric-pole/small-electric-pole.png", 72, 220, (1.5, -42.5), line=4)),
    "assembling-machine-1": single(layer(G + "assembling-machine-1/assembling-machine-1-base.png", 198, 184, (0, 4), line=1)),
    "splitter": directional(
        layer(G + "splitter/splitter-north.png", 160, 70, (7, 0), line=8),
        layer(G + "splitter/splitter-east.png", 90, 84, (4, 13), line=8),
        layer(G + "splitter/splitter-south.png", 164, 64, (4, 0), line=8),
        layer(G + "splitter/splitter-west.png", 90, 86, (6, 12), line=8)),
    "stone-wall": single(layer(G + "wall/wall-single.png", 64, 86, (0, -5), line=2)),
    "steel-furnace": single(layer(G + "steel-furnace/steel-furnace.png", 171, 174, (-1.25, 2))),
}

# Electric mining drill (Wube's printable model, wube_recipes.py): the frame for the direction,
# then the drill head over it in its resting place (the first frame of the working animation:
# the vertical sheet facing north or south, the horizontal one and its front east or west), and
# the frame's front pieces (mining-drill.lua).
_EMD = G + "electric-mining-drill/electric-mining-drill"
_EMD_HEAD = layer(_EMD + ".png", 162, 156, (1, -11), line=6)
_EMD_SIDE = [layer(_EMD + "-horizontal.png", 80, 160, (2, -12), line=6),
             layer(_EMD + "-horizontal-front.png", 66, 154, (-3, 3), line=6)]
BUILDINGS["electric-mining-drill"] = {"anchor": BUILDING_ANCHOR, "mode": "direction", "cells": [
    [layer(_EMD + "-N.png", 190, 208, (0, -4), line=1), layer(_EMD + "-N-output.png", 60, 66, (-3, -44), line=5),
     _EMD_HEAD],
    [layer(_EMD + "-E.png", 192, 188, (0, -4), line=1), layer(_EMD + "-E-output.png", 50, 74, (30, -8), line=5),
     *_EMD_SIDE, layer(_EMD + "-E-front.png", 136, 148, (21, 10), line=1)],
    [layer(_EMD + "-S.png", 184, 192, (0, -1), line=1), _EMD_HEAD,
     layer(_EMD + "-S-output.png", 84, 56, (-1, 34), line=5), layer(_EMD + "-S-front.png", 190, 104, (0, 27), line=1)],
    [layer(_EMD + "-W.png", 192, 188, (0, -4), line=1), layer(_EMD + "-W-output.png", 50, 60, (-31, -13), line=5),
     *_EMD_SIDE, layer(_EMD + "-W-front.png", 134, 140, (-22, 12), line=1)]]}
# Converted from Wube's printable models (tools/models/wube_recipes.py): logistic chests (the
# first of seven lid frames, closed) and the inserters' platforms (their arms are drawn apart).
for _chest in ("passive-provider-chest", "active-provider-chest", "storage-chest", "buffer-chest", "requester-chest"):
    BUILDINGS[_chest] = single(layer(G + "logistic-chest/%s.png" % _chest, 66, 74, (0, -2), line=7))
## The platform sheet has one picture per direction the inserter faces: north, east, south, west.
## Each has its own model, drawn unturned (wube_recipes.py INSERTER_FITS), fitted with this
## anchor and stretch (fit.py): Factorio's platform renders are flatter than its other buildings.
def _platform(name, file):
    for i, sfx in enumerate(("", "-east", "-south", "-west")):
        BUILDINGS[name + sfx] = dict(single(layer(file, 105, 79, (1.5, 6.5), line=4, index=i), anchor=0.325),
                                     stretch=0.955)


for _ins in ("burner-inserter", "inserter", "long-handed-inserter", "fast-inserter", "bulk-inserter"):
    _platform(_ins, G + "%s/%s-platform.png" % (_ins, _ins))
_platform("stack-inserter", "space-age/graphics/entity/stack-inserter/stack-inserter-platform.png")

# Fluids (tools/models/fluids.py). Pipes: one model per picture of Factorio's pipe kit, the
# client picks one from the pipe's connections; all are 128x128 except the lone pipe.
PIPE_SHAPES = ("straight-vertical-single", "straight-vertical", "straight-horizontal", "corner-up-right",
               "corner-up-left", "corner-down-right", "corner-down-left", "t-up", "t-down", "t-left", "t-right",
               "cross", "ending-up", "ending-down", "ending-left", "ending-right")
for _shape in PIPE_SHAPES:
    _size = 160 if _shape == "straight-vertical-single" else 128
    BUILDINGS["pipe-" + _shape] = single(layer(G + "pipe/pipe-%s.png" % _shape, _size, _size))
BUILDINGS["pipe"] = single(layer(G + "pipe/pipe-straight-vertical.png", 128, 128))
# Pipe-to-ground: a model per direction (fluids.py PTG_FACINGS), each with its own picture, at the
# pipe kit's camera (PIPE_FIT below), so its joint flange sits where the kit's do.
for _sfx, _d in (("", "up"), ("-east", "right"), ("-south", "down"), ("-west", "left")):
    BUILDINGS["pipe-to-ground" + _sfx] = single(layer(G + "pipe-to-ground/pipe-to-ground-%s.png" % _d, 128, 128))
# A model per direction (fluids.py, facings.py), drawn unturned.
BUILDINGS["offshore-pump"] = single(layer(G + "offshore-pump/offshore-pump_North.png", 90, 162, (-1, -15), line=8))
BUILDINGS["offshore-pump-east"] = single(layer(G + "offshore-pump/offshore-pump_East.png", 124, 102, (15, -2), line=8))
BUILDINGS["offshore-pump-south"] = single(layer(G + "offshore-pump/offshore-pump_South.png", 92, 192, (-1, 0), line=8))
BUILDINGS["offshore-pump-west"] = single(layer(G + "offshore-pump/offshore-pump_West.png", 124, 102, (-15, -2), line=8))
# Two frames: north-south and east-west (the tank only turns two ways).
_TANK = [layer(G + "storage-tank/storage-tank.png", 219, 235, (-0.25, -1.25), line=2, index=i) for i in (0, 1)]
BUILDINGS["storage-tank"] = directional(_TANK[0], _TANK[1], _TANK[0], _TANK[1])
# Both frames draw the same drum, wider east-west than the camera would show a round one, with
# only its connections turned: the model's drum is round, unstretched, and the sprite's origin sits
# high on it (fitted with score.py: every direction 0.88-0.90).
BUILDINGS["storage-tank"]["anchor"] = 0.6

# Electric network (tools/models/electric.py). Poles' sheets hold four pictures for the ways their
# wires run; the first fits the model.
BUILDINGS.update({
    "medium-electric-pole": single(layer(G + "medium-electric-pole/medium-electric-pole.png", 84, 252, (3.5, -44), line=4)),
    # Its feet stand square round the centre; the sprite draws them that way 0.26 tiles lower.
    "big-electric-pole": single(layer(G + "big-electric-pole/big-electric-pole.png", 148, 312, (0, -51), line=4),
                                anchor=0.04),
    "substation": single(layer(G + "substation/substation.png", 138, 270, (0, -31), line=4)),
    "small-lamp": single(layer(G + "small-lamp/lamp.png", 83, 70, (0.25, 3))),
    "solar-panel": single(layer(G + "solar-panel/solar-panel.png", 230, 224, (-3, 3.5))),
    "accumulator": single(layer(G + "accumulator/accumulator.png", 130, 189, (0, -11))),
    # 64 frames of the dish turning; the first faces north, as the model's dish does.
    "radar": single(layer(G + "radar/radar.png", 196, 254, (1, -16), line=8)),
})

# Oil (tools/models/oil.py). The pumpjack's beam and horse head are one layer for every direction:
# the models' upright parts wear it as `<model>.upright` (model_library.gd). Its base is four
# separate renders with the pipes and motor in other places, so each direction is a model of its
# own (oil.py PJ_FACINGS), drawn unturned with its own picture. The chemical plant's and
# refinery's directions are separate renders.
for _i, _sfx in enumerate(("", "-east", "-south", "-west")):
    BUILDINGS["pumpjack" + _sfx] = single(layer(G + "pumpjack/pumpjack-base.png", 261, 273, (-2.25, -4.75),
                                                line=4, index=_i))
    BUILDINGS["pumpjack%s.upright" % _sfx] = single(layer(G + "pumpjack/pumpjack-horsehead.png", 206, 172,
                                                          (-4.5, -29), line=8))
_CP = {"north": ((204, 292, (1, -9)), (114, 68, (-0.5, -36))), "east": ((208, 264, (0, -10.5)), (62, 104, (-10.5, -37))),
       "south": ((208, 266, (1, -2.5)), (66, 44, (0, 18.5))), "west": ((218, 236, (0.5, -7.5)), (90, 68, (10.5, -39.5)))}
# A model per direction (oil.py CP_FACINGS), each with its own picture, drawn unturned.
for _sfx, (d, (b, a)) in zip(("", "-east", "-south", "-west"), _CP.items()):
    BUILDINGS["chemical-plant" + _sfx] = single(
        layer(G + "chemical-plant/chemical-plant-%s-base.png" % d, b[0], b[1], b[2], line=1),
        layer(G + "chemical-plant/chemical-plant-%s-anim-1.png" % d, a[0], a[1], a[2], line=4))
BUILDINGS["oil-refinery"] = directional(*(
    layer(G + "oil-refinery/%s/oil-refinery-%s.png" % (d, d), w, h, sh, line=1)
    for d, w, h, sh in (("north", 356, 446, (0, -10)), ("east", 374, 454, (0, -19)),
                        ("south", 356, 446, (-0.5, -9.5)), ("west", 376, 420, (0, -12)))))

# Pipe pictures and the offshore pump draw their tiles square on screen, longer north-south than
# Factorio's camera gives: the projection stretches the ground to match (1 / sin 48 degrees), and
# the pipes' anchor sits a little higher. Fitted with compare.py --stretch --anchor over the pipe
# kit (mean overlap 0.69 -> 0.76) and the offshore pump's north and east frames.
PIPE_FIT = {"anchor": 0.375, "stretch": 1.346}
for _name in ["pipe", "offshore-pump", "offshore-pump-east", "offshore-pump-south", "offshore-pump-west"] + \
        ["pipe-" + _s for _s in PIPE_SHAPES]:
    BUILDINGS[_name].update(PIPE_FIT)
for _sfx in ("", "-east", "-south", "-west"):
    BUILDINGS["pipe-to-ground" + _sfx].update(PIPE_FIT)

# Factorio's sprites draw the ground's north-south distances at full length, as if the camera
# looked straight down at the ground and only heights were foreshortened: Wube's printable models,
# true to the game's geometry, fit their sprites best with the same stretch at any pitch from 44
# to 52 degrees (mean overlap over assembler 1, both furnaces, three chests and the small pole
# 0.64 -> 0.72; compare.py --stretch). Models built at their true proportions use it; most of the
# procedural ones were squeezed to fit the camera without it, so they keep 1 until refitted.
TRUE_PROPORTIONS = ["assembling-machine-1", "stone-furnace", "steel-furnace", "wooden-chest", "iron-chest",
                    "steel-chest", "passive-provider-chest", "active-provider-chest", "storage-chest", "buffer-chest",
                    "requester-chest", "small-electric-pole", "electric-mining-drill",
                    # procedural ones that fit better stretched as they are
                    "splitter", "boiler", "chemical-plant", "chemical-plant-east", "chemical-plant-south",
                    "chemical-plant-west",
                    "boiler-east", "boiler-south", "boiler-west",  # steam power (facings.py)
                    # rebuilt at true proportions (models-production; tools/models/score_proto.py)
                    "arithmetic-combinator", "decider-combinator", "selector-combinator", "constant-combinator",
                    "power-switch", "programmable-speaker", "display-panel", "small-lamp", "burner-mining-drill",
                    "burner-mining-drill-east", "burner-mining-drill-south", "burner-mining-drill-west",
                    "pumpjack", "pumpjack-east", "pumpjack-south", "pumpjack-west", "pumpjack.upright",
                    "pumpjack-east.upright", "pumpjack-south.upright", "pumpjack-west.upright",
                    "assembling-machine-2", "assembling-machine-3", "lane-splitter", "loader", "market",
                    "train-stop"]  # its north picture, rail overlay included (railway.py)
# Not the inserter platforms: their four direction pictures fit the round platform best unstretched
# (mean overlap over the four, shadows left out, 0.73 unstretched, 0.68 stretched; m-wube).
for _name in TRUE_PROPORTIONS:
    if _name in BUILDINGS:
        BUILDINGS[_name]["stretch"] = PIPE_FIT["stretch"]
# The oil refinery is built at true proportions too (refitted stretched, oil.py).
BUILDINGS["oil-refinery"]["stretch"] = PIPE_FIT["stretch"]


# Stone wall pieces (Wube's walls set, wube_recipes.py), one per connection shape. Factorio draws
# a wall from its east, south and west neighbours only (the north one's picture covers the join),
# so pieces share its nine pictures: (file, width, height, frames per row, shift).
_WALL_PICTURES = {
    0: ("single", 64, 86, 2, (0, -5)), 4: ("vertical", 64, 134, 5, (0, 8)), 10: ("horizontal", 64, 92, 6, (0, -2)),
    6: ("corner-right", 64, 128, 2, (0, 7)), 12: ("corner-left", 64, 134, 2, (0, 7)), 14: ("t", 64, 134, 4, (0, 7)),
    2: ("ending-right", 64, 92, 2, (0, -3)), 8: ("ending-left", 64, 92, 2, (0, -3)),
}
_WALL_SHAPES = ("pylon", "n", "e", "ne", "s", "ns", "es", "nes", "w", "nw", "ew", "new", "sw", "nsw", "esw", "nesw")
for _mask, _shape in enumerate(_WALL_SHAPES):
    _f, _w, _h, _line, _shift = _WALL_PICTURES[_mask & 14]
    BUILDINGS["stone-wall-" + _shape] = single(layer(G + "wall/wall-%s.png" % _f, _w, _h, _shift, line=_line))
    if _mask & 6 == 6:
        # With the fill-in block on the south-east corner (Factorio's "filling", drawn there).
        BUILDINGS["stone-wall-%s-fill" % _shape] = single(
            layer(G + "wall/wall-%s.png" % _f, _w, _h, _shift, line=_line),
            layer(G + "wall/wall-filling.png", 48, 56, (16, 15), line=8))


# Rails (tools/models/rails.py). Factorio draws rails straight down, layer by layer (stones,
# ties, plates, rails), each piece's frame cut from one big sheet per layer at (x, y): numbers
# from base/prototypes/entity/rail-pictures.lua (new_rail_pictures), variation 0. A model covers
# four directions a quarter turn apart: `<name>` 0, 4, 8, 12 and `<name>-ne` 2, 6, 10, 14.
# Straight and half-diagonal pieces have only four pictures (south equals north). The sheets
# are huge, so the client builds these on its loading thread ("deferred"). The track's centre line
# is drawn where the game has it, but distances across it are squashed north-south by 0.72 (an
# east-west track's rails are 0.84 tiles apart in its sprite, a north-south one's 1.17): the
# models carry their centre line in UV for this ("across").
_RAIL_LAYERS = ("rail-stone-path", "rail-stone-path-inside", "rail-ties", "rail-backplates", "rail-metals")
_RAIL_FRAMES = {  # piece -> frame sizes and (x, y) for N, NE, E, SE, S, SW, W, NW
    "straight": ([256, 384] * 4, [(0, 256), (0, 2048), (0, 0), (0, 896)] * 2),
    "half-diagonal": ([384] * 8, [(0, 1280), (0, 1664), (0, 2432), (0, 512)] * 2),
    "curved-a": ([512] * 8, [(2048, p * 512) for p in (3, 12, 7, 0, 11, 4, 15, 8)]),
    "curved-b": ([512] * 8, [(2048, p * 512) for p in (2, 13, 6, 1, 10, 5, 14, 9)]),
}


def _rail_frames(size, xys, layers):
    return [{"file": G + "rails/rail/%s.png" % name, "frame": [size, size], "xy": list(xy), "shift": [0.0, 0.0],
             "scale": 0.5} for name in layers for xy in [xys]]


for _piece, (_sizes, _xys) in _RAIL_FRAMES.items():
    _proto = {"straight": "straight-rail", "half-diagonal": "half-diagonal-rail"}.get(_piece, "curved-rail-" + _piece[-1])
    for _suffix, _first in (("", 0), ("-ne", 1)):
        _dirs = [(_sizes[_first + 2 * k], _xys[_first + 2 * k]) for k in range(4)]
        # Elevated pieces: the same track on their deck (ties, plates and rails; the deck itself
        # wears its material). Their own sheets draw it 3 tiles up and are as big again.
        for _prefix, _layers in (("", _RAIL_LAYERS), ("elevated-", _RAIL_LAYERS[2:])):
            BUILDINGS[_prefix + _proto + _suffix] = {
                "anchor": 0.0, "projection": "top", "across": 0.72, "deferred": True, "mode": "direction",
                "cells": [[_rail_frames(size, xy, [name])[0] for name in _layers] for size, xy in _dirs]}


# Railway buildings (tools/models/railway.py).
_ER = "elevated-rails/graphics/entity/"
# Signals turn 16 ways: frame i of the 16 is row i of the sheet (its first column: green).
BUILDINGS["rail-signal"] = {"anchor": BUILDING_ANCHOR, "mode": "rotation", "cells": [
    [layer(G + "rail-signal/rail-signal.png", 128, 128, line=3, index=i * 3)] for i in range(16)]}
BUILDINGS["rail-chain-signal"] = {"anchor": BUILDING_ANCHOR, "mode": "rotation", "cells": [
    [layer(G + "rail-chain-signal/rail-chain-signal.png", 100, 98, (0.5, 0), line=4, index=i * 4)] for i in range(16)]}
BUILDINGS["train-stop"] = {"anchor": BUILDING_ANCHOR, "mode": "direction", "cells": [
    [layer(G + "train-stop/train-stop-ground.png", 386, 377, (0, -0.75), line=4, index=d),
     layer(G + "train-stop/train-stop-bottom.png", 140, 291, (-0.5, -26.75), line=4, index=d),
     layer(G + "train-stop/train-stop-top.png", 312, 306, (0.5, -50.5), line=4, index=d)] for d in range(4)]}
# The gate's door closed: the vertical picture facing north or south, the horizontal one east or west.
_GATE_V = layer(G + "gate/gate-vertical.png", 78, 120, (-1, -13), line=8)
_GATE_H = layer(G + "gate/gate-horizontal.png", 66, 90, (0, -3), line=8)
BUILDINGS["gate"] = directional(_GATE_V, _GATE_H, _GATE_V, _GATE_H)
# Supports turn 16 ways with 8 pictures (back equals front).
BUILDINGS["rail-support"] = {"anchor": BUILDING_ANCHOR, "mode": "rotation", "cells": [
    [layer(_ER + "elevated-rail-pylon/elevated-rail-pylon.png", 280, 430, (0, -36), line=4, index=i % 8)] for i in range(16)]}
# Ramps: one picture per direction at (column, row) N (0, 0), E (1, 1), S (0, 1), W (1, 0); big frames.
# Not used: the ramp's sprite climbs 3 tiles up the screen over 16 tiles, and projected onto the
# model (whose deck rises 4.5 tiles, like the other elevated pieces) it smears the track over the
# embankment. The ramp wears its materials.
_RAMP_UNUSED = {"anchor": BUILDING_ANCHOR, "mode": "direction", "deferred": True, "atlas_scale": 0.5, "cells": [
    [layer(_ER + "elevated-rail-ramp/elevated-rail-ramp-base.png", 1036, 1218, (0, -44.5), line=2, index=i),
     layer(_ER + "elevated-rail-ramp/elevated-rail-ramp.png", 1036, 1218, (0, -44.5), line=2, index=i)] for i in (0, 3, 2, 1)]}


def rotation(frames, anchor=BUILDING_ANCHOR, atlas_scale=1.0):
    """A vehicle: `frames(i)` gives the layers of frame i of 64 round the turn, clockwise from
    north; the client projects the one nearest the vehicle's orientation."""
    out = {"anchor": anchor, "mode": "rotation", "cells": [frames(i) for i in range(64)]}
    if atlas_scale != 1.0:
        out["atlas_scale"] = atlas_scale
    return out


def _car(i):
    """Car body: 64 directions in six sheets of 11 rows, 2 animation frames per row; the turret
    (64 directions, 32 rows a sheet) drawn facing the way the car does."""
    return [layer(G + "car/car-%d.png" % (i // 11 + 1), 201, 172, (2, -3), line=2, index=(i % 11) * 2),
            layer(G + "car/car-turret-%d.png" % (i // 32 + 1), 71, 57, (2, -25), line=1, index=i % 32)]


def _rolling(name, w, h, shift, directions, tint=None):
    """Rolling stock: sprite_load sheets of 32 frames (4 a row); wagons draw only half a turn
    (back equals front), so their frame for orientation o is round(o * 256) mod 128. Under the
    body, Factorio draws the wheels as a layer of their own (train-wheel, 256 directions) at each
    bogie, 2 tiles either way along the train; they're placed where the model's bogies project
    (north-south distances foreshortened by Factorio's camera), so the bogies wear them."""
    def frames(i):
        d = (i * 256 // 64) % directions
        return _train_wheels(i) + [layer(G + "%s/%s-%d.png" % (name, name, d // 32 + 1), w, h, shift, line=4,
                                         index=d % 32, tint=tint)]
    return frames


def _train_wheels(i):
    """The two train-wheel layers of rotation frame i (of 64), one at each bogie (see _rolling)."""
    wd = i * 256 // 64
    a = 2 * math.pi * i / 64
    wheels = []
    for k in (1, -1):
        sx = 0.5 + k * 64 * math.sin(a)
        sy = 1 - k * 64 * math.cos(a) * math.sin(math.radians(48))
        wheels.append(layer(G + "train-wheel/train-wheel-%d.png" % (wd // 32 + 1), 230, 228, (sx, sy),
                            line=4, index=wd % 32))
    return wheels


# Vehicles (tools/models/vehicles.py). Train frames are big, so their atlases are halved.
BUILDINGS["car"] = rotation(_car)
BUILDINGS["locomotive"] = rotation(_rolling("locomotive", 474, 458, (0, -16), 256), atlas_scale=0.5)
BUILDINGS["cargo-wagon"] = rotation(_rolling("cargo-wagon", 442, 408, (0, -25), 128), atlas_scale=0.5)
BUILDINGS["fluid-wagon"] = rotation(_rolling("fluid-wagon", 416, 420, (0, -31.5), 128), atlas_scale=0.5)
# The infinity cargo wagon is the cargo wagon's picture tinted (0.5, 0.5, 1) (its prototype).
BUILDINGS["infinity-cargo-wagon"] = rotation(_rolling("cargo-wagon", 442, 408, (0, -25), 128, tint=(0.5, 0.5, 1.0)),
                                             atlas_scale=0.5)

# Logistics, circuits and mid-game machines (tools/models/circuits.py, logistics.py).
# Combinators, displays: their sheets hold the four directions in a row (north first).
for _name, _w, _h, _shift in (("arithmetic-combinator", 144, 124, (0.5, 7.5)), ("decider-combinator", 156, 132, (0.5, 7.5)),
                              ("selector-combinator", 154, 160, (1, -1)), ("constant-combinator", 114, 102, (0, 5))):
    BUILDINGS[_name] = directional(*(layer(G + "combinator/%s.png" % _name, _w, _h, _shift, line=4, index=i) for i in range(4)))
BUILDINGS["display-panel"] = directional(*(layer(G + "display-panel/display-panel.png", 128, 128, line=4, index=i)
                                           for i in range(4)))
BUILDINGS["power-switch"] = single(layer(G + "power-switch/power-switch.png", 168, 138, (-3, 2), line=2))
BUILDINGS["programmable-speaker"] = single(layer(G + "programmable-speaker/programmable-speaker.png", 59, 178, (-2.25, -39.5)))
# Valves: a model per direction (circuits.py), its housing's top and front filling the picture's
# plate from the pipe kit's camera, so each wears its own picture.
for _n in ("one-way-valve", "overflow-valve", "top-up-valve"):
    for _sfx, _d in (("", "north"), ("-east", "east"), ("-south", "south"), ("-west", "west")):
        BUILDINGS[_n + _sfx] = single(layer(G + "%s/%s-%s.png" % (_n, _n, _d), 64, 64), anchor=PIPE_FIT["anchor"])
        BUILDINGS[_n + _sfx]["stretch"] = PIPE_FIT["stretch"]
BUILDINGS["pump"] = directional(
    layer(G + "pump/pump-north.png", 103, 164, (8, -0.85), line=8),
    layer(G + "pump/pump-east.png", 130, 109, (-0.5, 1.75), line=8),
    layer(G + "pump/pump-south.png", 114, 160, (12.5, -8), line=8),
    layer(G + "pump/pump-west.png", 131, 111, (-0.25, 1.25), line=8))
# The pump is modelled at true proportions and joins pipes, so it is projected like them.
BUILDINGS["pump"].update(PIPE_FIT)
BUILDINGS["electric-furnace"] = single(layer(G + "electric-furnace/electric-furnace.png", 239, 219, (0.75, 5.75)))
BUILDINGS["beacon"] = single(layer(G + "beacon/beacon-bottom.png", 212, 192, (0.5, 1)),
                             layer(G + "beacon/beacon-top.png", 96, 140, (3, -19)))
# The beacon's sprite draws its frame deeper than the camera gives (fitted with score.py).
BUILDINGS["beacon"].update(stretch=1.12, anchor=0.1)
# Assemblers: the box and the first frame of the machinery inside it.
BUILDINGS["assembling-machine-2"] = single(
    layer(G + "assembling-machine-2/assembling-machine-2-base.png", 200, 188, (0, 2.5), line=1),
    layer(G + "assembling-machine-2/assembling-machine-2-anim.png", 148, 158, (1.5, -15.5), line=8))
BUILDINGS["assembling-machine-3"] = single(
    layer(G + "assembling-machine-3/assembling-machine-3-base.png", 196, 192, (-0.5, 2.5), line=1),
    layer(G + "assembling-machine-3/assembling-machine-3-anim.png", 140, 160, (1, -16), line=8))
# The roboport with its doors closed (the first frames of both door animations).
BUILDINGS["roboport"] = single(layer(G + "roboport/roboport-base.png", 228, 277, (2, -2.25)),
                               layer(G + "roboport/roboport-door-up.png", 97, 38, (-0.25, -39.5), line=16),
                               layer(G + "roboport/roboport-door-down.png", 97, 41, (-0.25, -19.75), line=16))
# Robots: 16 directions, clockwise from north (logistic robot: its idle row, the second).
ROBOT_ANCHOR = 0.1  # the sprite's centre sits a little higher than the model's middle
BUILDINGS["logistic-robot"] = {"anchor": ROBOT_ANCHOR, "mode": "rotation", "cells": [
    [layer(G + "logistic-robot/logistic-robot.png", 80, 84, (0, -3), line=16, index=16 + i)] for i in range(16)]}
BUILDINGS["construction-robot"] = {"anchor": ROBOT_ANCHOR, "mode": "rotation", "cells": [
    [layer(G + "construction-robot/construction-robot.png", 66, 76, (0, -4.5), line=16, index=i)] for i in range(16)]}
# Crude oil: four variations of the stain, one picked per patch.
BUILDINGS["crude-oil"] = {"anchor": NATURE_ANCHOR, "mode": "variation", "cells": [
    [layer(G + "crude-oil/crude-oil.png", 168, 124, (0.5, -2), line=4, index=i)] for i in range(4)]}

# Space Age, Gleba and Aquilo (tools/models/gleba.py, aquilo.py; m-space2). util.sprite_load adds a
# prototype's own `shift` to the one in the sheet's .lua file (the rocket turret's -20 px).
SA = "space-age/graphics/entity/"
_FR_CONN = {1: (124, 94, -50.5, -90.5), 2: (108, 58, 51.5, -103.5), 3: (94, 144, 86, -56), 4: (84, 160, 91, 47),
            5: (174, 136, 58, 83), 6: (128, 146, -47.5, 78), 7: (52, 156, -101.5, 47.5), 8: (124, 128, -82, -61.5)}
BUILDINGS.update({
    "biochamber": single(layer(SA + "biochamber/biochamber.png", 238, 268, (-0.5, -7.5)),
                         layer(SA + "biochamber/biochamber-animation.png", 92, 144, (23.5, -9.5), line=8),
                         layer(SA + "biochamber/biochamber-animation-dome.png", 92, 148, (-15.5, -14), line=8)),
    "agricultural-tower": single(layer(SA + "agricultural-tower/agricultural-tower-base.png", 228, 330, (-2.5, -17.5))),
    "heating-tower": single(layer(SA + "heating-tower/heating-tower-main.png", 214, 320, (-1, -22.5))),
    "biolab": single(layer(SA + "biolab/biolab-anim.png", 366, 404, (2, -5), line=8)),
    "captive-biter-spawner": single(layer(SA + "captive-spawner/captive-anim.png", 380, 338, (-2.5, -1.5), line=8)),
    "rocket-turret": single(layer(SA + "rocket-turret/rocket-turret-base.png", 202, 168, (-0.5, 4.5)),
                            layer(SA + "rocket-turret/rocket-turret-shooting-1.png", 160, 164, (0, -28.5), line=1)),
    "cryogenic-plant": single(layer(SA + "cryogenic-plant/cryogenic-plant-main.png", 380, 396, (3, -3.5)),
                              layer(SA + "cryogenic-plant/cryogenic-plant-glass.png", 274, 228, (4, -7.5))),
    "fusion-reactor": single(layer(SA + "fusion-reactor/fusion-reactor-main.png", 444, 456, (1, -5.5)),
                             *(layer(SA + "fusion-reactor/fusion-reactor-connection-%d.png" % i, w, h, (x, y), line=5)
                               for i, (w, h, x, y) in _FR_CONN.items())),
    "fusion-generator": directional(*(
        layer(SA + "fusion-generator/%s/fusion-generator-%s.png" % (d, d), w, h, sh, line=3)
        for d, w, h, sh in (("north", 244, 376, (-2, -2)), ("east", 370, 230, (0, -1)),
                            ("south", 252, 360, (0, 6)), ("west", 370, 240, (-0.5, -4))))),
    # Eight-way: the base's frames 0/2/4/6 face north/east/south/west; the gun aims straight
    # ahead (the middle of each direction's 19 aiming frames).
    "railgun-turret": {"anchor": BUILDING_ANCHOR, "mode": "direction", "cells": [
        [layer(SA + "railgun-turret/railgun-turret-base.png", 416, 354, (15, -3.5), line=4, index=2 * k),
         layer(SA + "railgun-turret/railgun-turret-shooting-%s.png" % d, w, h, sh, line=7, index=9)]
        for k, (d, w, h, sh) in enumerate((("N", 258, 214, (-2, -52)), ("E", 290, 284, (33, -32)),
                                           ("S", 260, 238, (1, -5.5)), ("W", 288, 284, (-29.5, -27))))]},
    # Flying: drawn 66.5 px up; the model sits on its own origin and the client lifts it.
    "capture-robot": single(layer(SA + "capture-robot-rocket/capture-robot.png", 190, 184, (0, -66.5), line=8), anchor=-2.55),
    "lithium-brine": single(layer(SA + "lithium-brine/lithium-brine.png", 166, 120, (1.5, 4.5), line=4), anchor=NATURE_ANCHOR),
    "fluorine-vent": single(layer(SA + "fluorine-vent/fluorine-vent.png", 194, 136, (-0.5, -3), line=4), anchor=NATURE_ANCHOR),
    "lithium-iceberg-big": single(layer("space-age/graphics/decorative/lithium-iceberg-big/lithium-iceberg-big-1.png",
                                        230, 156, (3.2, -8)), anchor=NATURE_ANCHOR),
    "lithium-iceberg-huge": single(layer("space-age/graphics/decorative/lithium-iceberg-huge/lithium-iceberg-huge-2.png",
                                         640, 310, (20.8, -24)), anchor=NATURE_ANCHOR),
})
# Space Age machines rebuilt at their true proportions: like Wube's renders, their pictures draw
# the ground's north-south distances at full length (the fusion generator's four pictures agree on
# one solid to 0.98-0.99 stretched, 0.88-0.94 not).
for _name in ("fusion-generator", "cryogenic-plant", "fusion-reactor"):
    BUILDINGS[_name]["stretch"] = PIPE_FIT["stretch"]
# Gleba plants (plants.lua, gleba_tree_variations): trunk and leaves of variation 1, drawn at
# 0.33 x the plant's scale multiplier.
for _n, (_m, _w, _h, _sh) in {
        "yumako-tree": (1.3, 640, 560, (52, -73)), "jellystem": (1.3, 640, 560, (52, -73)), "cuttlepop": (1, 640, 560, (52, -40)),
        "slipstack": (1, 640, 560, (52, -65)), "funneltrunk": (1, 640, 560, (52, -65)), "hairyclubnub": (1, 640, 560, (52, -65)),
        "teflilly": (1, 640, 560, (52, -60)), "lickmaw": (1, 640, 560, (52, -60)), "stingfrond": (1.1, 640, 560, (52, -60)),
        "boompuff": (0.9, 640, 560, (49, -40)), "sunnycomb": (1, 640, 560, (52, -60)), "water-cane": (1, 340, 290, (30, -28))}.items():
    BUILDINGS[_n] = single(layer(SA + "plant/%s/%s-trunk.png" % (_n, _n), _w, _h, _sh, line=1, scale=round(0.33 * _m, 4)),
                           layer(SA + "plant/%s/%s-harvest.png" % (_n, _n), _w, _h, _sh, line=1, scale=round(0.33 * _m, 4)),
                           anchor=NATURE_ANCHOR)

# Military (tools/models/military.py). Turret heads and cannons are the prepared frame facing
# north, the way the models' heads rest. The flamethrower turret's gun sits on its own spot per
# direction (fireutil.turret_gun_shift) and its sheet runs counter-clockwise.
BUILDINGS["laser-turret"] = single(layer(G + "laser-turret/laser-turret-base.png", 138, 104, (-0.5, 2)),
                                   layer(G + "laser-turret/laser-turret-shooting.png", 126, 120, (0, -35), line=8))
_FT = G + "flamethrower-turret/flamethrower-turret-"
BUILDINGS["flamethrower-turret"] = {"anchor": BUILDING_ANCHOR, "mode": "direction", "cells": [
    [layer(_FT + "base-%s.png" % d, w, h, sh, line=1), layer(_FT + "gun.png", 158, 128, gun, line=8, index=i)]
    for d, w, h, sh, gun, i in (("north", 158, 196, (-1, 13), (-1, -31), 0), ("east", 216, 169, (-6, -2.75), (17.5, -15.5), 48),
                                ("south", 168, 190, (0, -2), (-1, -6), 32), ("west", 208, 160, (7, -5), (-13, -19.5), 16))]}
BUILDINGS["land-mine"] = single(layer(G + "land-mine/land-mine.png", 64, 64))
# The artillery cannon stands cannon_base_shift (0.9722 tiles) up: 31.1 px higher on screen.
_AW = G + "artillery-wagon/artillery-wagon-cannon-"
BUILDINGS["artillery-turret"] = single(layer(G + "artillery-turret/artillery-turret-base.png", 207, 199),
                                       layer(_AW + "base-1.png", 378, 280, (0, -74.6), line=4),
                                       layer(_AW + "barrel-1.png", 530, 384, (0, -87.1), line=4))


def _tank(i):
    """Tank body: 64 directions in four sheets of 16 rows, 2 animation frames per row; the turret
    (64 directions, 8 a row) facing the way the tank does."""
    return [layer(G + "tank/tank-base-%d.png" % (i // 16 + 1), 270, 212, (0, -10), line=2, index=(i % 16) * 2),
            layer(G + "tank/tank-turret.png", 179, 132, (0.25, -34.5), line=8, index=i)]


def _spidertron(i):
    """The torso, raised its body height (1.5 tiles): the bottom ring (one picture) and the body
    (64 directions). The legs are separate entities in Factorio, so they wear the fallback."""
    return [layer(G + "spidertron/torso/spidertron-body-bottom.png", 126, 106, (0, -48)),
            layer(G + "spidertron/torso/spidertron-body.png", 132, 138, (0, -67), line=8, index=i)]


def _artillery_wagon(i):
    """Wagon (256 directions, 32 a sheet) on its wheels (standard_train_wheels, like the other
    rolling stock) and its cannon parked facing forward on its ring. Placed by the prototype's
    cannon_base_shift (2.07 tiles behind the middle across the screen, 2.54 along it, 1.67 up)
    the cannon floats above the wagon's empty ring in every frame facing south of east-west (by
    up to 1.5 tiles at south-east); the sheets' rings line up when it stands 2.07 tiles behind
    the middle in every direction and 1.17 up, measured on the axis frames and checked on the
    diagonals."""
    d = i * 4
    o = 2 * math.pi * i / 64
    fx, fy = math.sin(o), -math.cos(o)
    ox, oy = -32 * 2.07 * fx, 32 * (-2.07 * fy - 1.17)
    sheet = d // 32 + 1
    return _train_wheels(i) + [
            layer(G + "artillery-wagon/artillery-wagon-base-%d.png" % sheet, 476, 410, (0.5, -27.5), line=4, index=d % 32),
            layer(_AW + "base-%d.png" % sheet, 378, 280, (round(ox, 2), round(oy - 43.5, 2)), line=4, index=d % 32),
            layer(_AW + "barrel-%d.png" % sheet, 530, 384, (round(ox, 2), round(oy - 56, 2)), line=4, index=d % 32)]


def _robot(name, w, h, shift, count, row):
    """A combat robot's idle frames: `count` directions round the turn, one row of the sheet."""
    return lambda i: [layer(G + "%s-robot/%s-robot.png" % (name, name), w, h, shift, line=count, index=row * count + i)]


BUILDINGS["tank"] = rotation(_tank)
BUILDINGS["spidertron"] = rotation(_spidertron)
BUILDINGS["artillery-wagon"] = rotation(_artillery_wagon, atlas_scale=0.5)
for _name, _w, _h, _shift, _count, _row, _anchor in (("defender", 56, 59, (0, 0.25), 16, 0, 0.33),
                                                      ("distractor", 72, 62, (0, -2.5), 16, 0, 0.323),
                                                      ("destroyer", 88, 77, (2.5, -1.25), 32, 1, 0.155)):
    _frames = _robot(_name, _w, _h, _shift, _count, _row)
    BUILDINGS[_name] = {"anchor": _anchor, "mode": "rotation", "cells": [_frames(i) for i in range(_count)]}

# Nuclear (tools/models/nuclear.py). Heat pipes: one model per heat pipe picture, as the pipes.
BUILDINGS["nuclear-reactor"] = single(layer(G + "nuclear-reactor/reactor.png", 302, 318, (-5, -7)))
BUILDINGS["heat-exchanger"] = directional(*(layer(G + "heat-exchanger/heatex-%s-idle.png" % d, w, h, sh, line=1)
                                            for d, w, h, sh in (("N", 270, 206, (-1, 9.5)), ("E", 212, 270, (-1.5, 9.5)),
                                                                ("S", 260, 202, (4, 11)), ("W", 196, 274, (1.5, 8)))))
_TV = layer(G + "steam-turbine/steam-turbine-V.png", 217, 374, (4.75, 0), line=4)
_TH = layer(G + "steam-turbine/steam-turbine-H.png", 320, 245, (0, -2.75), line=4)
BUILDINGS["steam-turbine"] = directional(_TV, _TH, _TV, _TH)
# The turbine is modelled at its true length; its pictures fill the footprint drawn square.
BUILDINGS["steam-turbine"]["stretch"] = 1.346
BUILDINGS["centrifuge"] = single(layer(G + "centrifuge/centrifuge-ABC.png", 194, 248, (-2.5, -18), line=8))
for _shape in PIPE_SHAPES:
    _file = {"straight-vertical-single": "straight-vertical-single", "cross": "t-1"}.get(_shape, _shape + "-1")
    BUILDINGS["heat-pipe-" + _shape] = single(layer(G + "heat-pipe/heat-pipe-%s.png" % _file, 64, 64))
BUILDINGS["heat-pipe"] = single(layer(G + "heat-pipe/heat-pipe-straight-vertical-1.png", 64, 64))
# Heat pipe pictures look almost straight down with tiles square on screen: the pipes' stretch,
# and the anchor at the pipes' axis (nuclear.py HP_Z), where the pictures centre them.
for _name in ["heat-pipe"] + ["heat-pipe-" + _s for _s in PIPE_SHAPES]:
    BUILDINGS[_name].update({"anchor": 0.075, "stretch": 1.346})

# Rockets and odds and ends (tools/models/rocket.py). sprite_load sheets add their .lua shift
# to the prototype's; the silo is drawn with its doors closed. The market's and loader's
# sheets are low resolution (scale 1).
_RS = G + "rocket-silo/"
BUILDINGS["rocket-silo"] = single(layer(_RS + "04-door-back.png", 312, 286, (37, 12)),
                                  layer(_RS + "05-door-front.png", 332, 300, (-28, 33)),
                                  layer(_RS + "06-rocket-silo.png", 628, 612, (2, 3.5)),
                                  layer(_RS + "14-rocket-silo-front.png", 586, 262, (1, 78)))
# Drawn at true proportions, as Wube's models (TRUE_PROPORTIONS): its front machinery reaches
# 1.5 tiles below the footprint on screen.
BUILDINGS["rocket-silo"]["stretch"] = PIPE_FIT["stretch"]
BUILDINGS["rocket-silo-rocket"] = single(layer(_RS + "rocket-static-pod.png", 308, 752, (-4, 85)), anchor=12.7)
BUILDINGS["cargo-pod"] = single(layer(G + "cargo-pod/pod-static-detached.png", 78, 172, (1, 3)), anchor=1.3)
BUILDINGS["cargo-landing-pad"] = single(layer(G + "cargo-hubs/hubs/planet-hub-2.png", 476, 500, (5.5, -34)),
                                        layer(G + "cargo-hubs/hubs/planet-hub-3.png", 498, 506, (0, -33)))
BUILDINGS["market"] = single(layer(G + "market/market.png", 156, 127, (30.4, 6.4), scale=1))
BUILDINGS["loader"] = directional(*(layer(G + "loader/loader-structure.png", 64, 64, line=4, index=i, scale=1)
                                    for i in range(4)))

# Space Age: space platform, Vulcanus, Fulgora (tools/models/space_sprites.py).
import space_sprites  # noqa: E402
BUILDINGS.update(space_sprites.ENTRIES)

# Placeholder audit (tools/models/placeholders.py). The lane splitter wears the splitter's
# pictures at half scale and the 1x1 loader the loader's, as the prototypes draw them; the
# unloading bay its extractor layers per direction; the landed pod the first frame of its landing.
_SPL = G + "splitter/splitter-"
BUILDINGS["lane-splitter"] = directional(
    layer(_SPL + "north.png", 160, 70, (3.5, 0), line=8, scale=0.25), layer(_SPL + "east.png", 90, 84, (2, 7.5), line=8, scale=0.25),
    layer(_SPL + "south.png", 164, 64, (2, 0), line=8, scale=0.25), layer(_SPL + "west.png", 90, 86, (3, 6), line=8, scale=0.25))
_EXT = "space-age/graphics/entity/cargo-hubs/extractor/extractor-"
BUILDINGS["landing-pad-unloading-bay"] = {"anchor": BUILDING_ANCHOR, "mode": "direction", "cells": [
    [layer(_EXT + "n-1.png", 256, 264, (-2, -44.5)), layer(_EXT + "n-4.png", 226, 252, (-1.5, -40))],
    [layer(_EXT + "e-2.png", 280, 276, (25.5, -4)), layer(_EXT + "e-3.png", 300, 296, (27, 1)),
     layer(_EXT + "e-4.png", 290, 318, (23.5, -15.5))],
    [layer(_EXT + "s-3.png", 252, 360, (0.5, 14.5)), layer(_EXT + "s-4.png", 264, 358, (0, 9.5))],
    [layer(_EXT + "w-1.png", 316, 290, (-31.5, -4.5)), layer(_EXT + "w-3.png", 284, 280, (-23.5, -4.5)),
     layer(_EXT + "w-4.png", 292, 328, (-21.5, -17))]]}
BUILDINGS["cargo-pod-container"] = single(layer(G + "cargo-pod/pod-landing.png", 192, 258, (-10.5, 8), line=7, index=12))
# Gleba's planted tree, as the Gleba plants: trunk and leaves of variation 1 at 0.33 x 1.3.
BUILDINGS["tree-plant"] = single(
    layer(SA + "plant/planted-tree/planted-tree-trunk.png", 640, 560, (70, -40), line=4, scale=round(0.33 * 1.3, 4)),
    layer(SA + "plant/planted-tree/planted-tree-harvest.png", 640, 560, (70, -40), line=4, scale=round(0.33 * 1.3, 4)),
    anchor=NATURE_ANCHOR)
_RUIN = "space-age/graphics/decorative/fulgora-ruin-flooded/"
BUILDINGS["fulgora-sunk-ruin-big"] = single(layer(_RUIN + "big/sunken-ruin-big-1.png", 508, 400, (-12.5, -2.5)),
                                            anchor=NATURE_ANCHOR)
BUILDINGS["fulgora-sunk-ruin-medium-tall"] = single(layer(_RUIN + "medium/sunken-ruin-medium-0004.png", 272, 198,
                                                          (27.2, -12.8)), anchor=NATURE_ANCHOR)
# Stromatolites: sprite_load at scale 0.4 with multiply_shift 0.5.
BUILDINGS["copper-stromatolite"] = single(layer(SA + "stromatolite/copper/copper-stromatolite-1.png", 246, 174,
                                                (2.75, 0.75), scale=0.4), anchor=NATURE_ANCHOR)
BUILDINGS["iron-stromatolite"] = single(layer(SA + "stromatolite/iron/iron-stromatolite-1.png", 258, 204,
                                              (0.75, 3.5), scale=0.4), anchor=NATURE_ANCHOR)
# Space Age ores, as ore_entry: eight variations of one richness stage.
for _ore in ("tungsten-ore", "calcite"):
    BUILDINGS[_ore] = {"anchor": NATURE_ANCHOR, "mode": "variation", "cells": [
        [layer(SA + "%s/%s.png" % (_ore, _ore), 128, 128, line=8, index=2 * 8 + _v)] for _v in range(8)]}

DEAD = ("dead-dry-hairy-tree", "dead-grey-trunk", "dead-tree-desert", "dry-hairy-tree", "dry-tree")
ROCKS = ("big-rock", "huge-rock", "big-sand-rock")
# Factorio's colour variants of trees: the same sprites with their own leaf colours.
TREE_VARIANTS = ("tree-02-red", "tree-06-brown", "tree-08-brown", "tree-08-red", "tree-09-brown", "tree-09-red")
ORES = ("iron-ore", "copper-ore", "coal", "stone", "uranium-ore")
ORE_STAGE = 2  # row of the ore sheets the client uses (0 = richest), as nature/compare.py


def by_pixel(body):
    m = re.search(r"shift = util\.by_pixel\((-?[\d.]+), (-?[\d.]+)\)", body)
    if m:
        return float(m.group(1)), float(m.group(2))
    m = re.search(r"shift = \{(-?[\d.]+), (-?[\d.]+)\}", body)
    return (float(m.group(1)) * 32, float(m.group(2)) * 32) if m else (0.0, 0.0)


def tree_entry(trees_lua, name):
    """Variation a of tree-NN (or of its colour variant, tree-NN-brown...): trunk, then leaves tinted with the mean of the prototype's
    `colors` (the game picks one of them per tree)."""
    number = name[5:7]
    block = trees_lua[trees_lua.index("{ -- tree-%s" % number):]
    block = block[block.index("{ -- a"):]
    layers = []
    for part in ("trunk", "leaves"):
        m = re.search(part + r"\s*=\s*\{\s*width = (\d+),\s*height = (\d+),\s*(shift = [^\n]+)", block)
        tint = tree_tint(trees_lua, name) if part == "leaves" else None
        layers.append(layer("base/graphics/entity/tree/%s/tree-%s-a-%s.png" % (number, number, part),
                            int(m.group(1)), int(m.group(2)), by_pixel(m.group(3)), tint=tint))
    return single(*layers, anchor=NATURE_ANCHOR)


def tree_tint(trees_lua, name):
    """The mean leaf colour of tree-NN, or of its variant tree-NN-<identifier>."""
    base, identifier = name[:7], name[8:]
    start = trees_lua.index("define_trees{")
    for block in re.split(r"\n  \{\n", trees_lua[start:])[1:]:
        t = re.search(r"type\s*=\s*(\d+)", block)
        ident = re.search(r'identifier\s*=\s*"([a-z]+)"', block.split("colors")[0])
        if t and "tree-%02d" % int(t.group(1)) == base and (ident.group(1) if ident else "") == identifier:
            cols = re.findall(r"\{r\s*=\s*(\d+),\s*g\s*=\s*(\d+),\s*b\s*=\s*(\d+)\}", block.split("get_water_reflection")[0])
            if cols:
                return [sum(float(c[i]) for c in cols) / len(cols) / 255.0 for i in range(3)]
    return None


def picture_entry(src, name):
    """The first of a dead tree's or rock's `pictures`."""
    i = src.index('name = "%s"' % name)
    j = src.find("pictures", i)
    block = src[j:src.find("\n  }", j)]
    # Up to the picture's own closing brace: a rock's shift is a {x, y} table of its own.
    m = re.search(r'filename = "([^"]+)",(.*?)\n\s*\}', block, re.S)
    body = m.group(2)
    w = int(re.search(r"width = (\d+)", body).group(1))
    h = int(re.search(r"height = (\d+)", body).group(1))
    return single(layer(m.group(1).replace("__base__/", "base/"), w, h, by_pixel(body)), anchor=NATURE_ANCHOR)


def ore_entry(name):
    """Eight variations of one richness stage; the client picks one per tile."""
    cells = [[layer("base/graphics/entity/%s/%s.png" % (name, name), 128, 128, line=8, index=ORE_STAGE * 8 + v)]
             for v in range(8)]
    return {"anchor": NATURE_ANCHOR, "mode": "variation", "cells": cells}


# Creatures (tools/models/wube_recipes.py, client/scripts/world/creature_models.gd). Each tier is
# its family's model scaled, so each gets the sheet at its own scale (multiply_shift too) and its
# carapace mask tinted (Factorio's tint1; the overlay tint2 is left out). Units turn freely: the
# run animation's first frame for each of 16 directions, clockwise from north; sheets are
# sprite_load files of `lines` rows of `line` frames, frames in order (direction x 16 + frame).
def _unit(base, size, shift, line, per_file, mask_size, mask_shift, scale, tint):
    def frame(sheet, w_h, sh, i):
        k = i * 16
        return layer(G + "%s-%d.png" % (sheet, k // per_file + 1), w_h[0], w_h[1],
                     (sh[0] * scale, sh[1] * scale), line=line, index=k % per_file, scale=0.5 * scale,
                     tint=None if sheet == base else tint)
    cells = [[frame(base, size, shift, i), frame(base + "-mask1", mask_size, mask_shift, i)] for i in range(16)]
    return {"anchor": 0.0, "mode": "rotation", "cells": cells, "atlas_scale": 0.5}


for _tier, _scale, _tint in (("small", 0.5, (0.60, 0.58, 0.51)), ("medium", 0.7, (0.49, 0.46, 0.51)),
                             ("big", 1.0, (0.37, 0.40, 0.72)), ("behemoth", 1.2, (0.2, 0.25, 0.2))):
    BUILDINGS[_tier + "-biter"] = _unit("biter/biter-run", (398, 310), (-1, -5), 8, 64, (238, 182), (-1, -37),
                                        _scale, _tint)

# Spawners: one sheet for both, the mask (the dome's veins) tinted per kind; the first frame of
# the first variation, as the model was matched to (compare.py, overlap 0.85).
for _name, _tint in (("biter-spawner", (0.96, 0.77, 0.5)), ("spitter-spawner", (0.99, 0.09, 0.09))):
    BUILDINGS[_name] = {"anchor": 0.0, "cells": [[
        layer(G + "spawner/spawner-idle.png", 520, 376, (4, -3), line=4),
        layer(G + "spawner/spawner-idle-mask.png", 270, 230, (0, -12.5), line=4, tint=_tint)]]}

# Worms: the prepared animation's first frame, its mask tinted per tier.
for _tier, _scale, _tint in (("small", 0.65, (0.7, 1, 0.3)), ("medium", 0.83, (0.9, 0.15, 0.3)),
                             ("big", 1.0, (0.34, 0.68, 0.9)), ("behemoth", 1.2, (0.3, 1, 0))):
    BUILDINGS[_tier + "-worm-turret"] = {"anchor": 0.0, "cells": [[
        layer(G + "worm/worm-prepared.png", 190, 300, (-3 * _scale, -41 * _scale), line=9, scale=0.5 * _scale),
        layer(G + "worm/worm-prepared-mask.png", 190, 268, (-3 * _scale, -33 * _scale), line=9, scale=0.5 * _scale,
              tint=_tint)]]}

for _tier, _scale, _tint in (("small", 0.5, (0.8, 0.45, 0)), ("medium", 0.7, (0.7, 0.2, 0.3)),
                             ("big", 1.0, (0.1, 0.4, 0.6)), ("behemoth", 1.2, (0.3, 0.2, 0.06))):
    BUILDINGS[_tier + "-spitter"] = _unit("spitter/spitter-run", (250, 220), (0, -11), 6, 90, (250, 196), (0, -17),
                                          _scale, _tint)

# The character: 8 directions, one row of 22 frames each (north first, clockwise); the first frame
# of the idle animation, and of the idle-with-gun one for the shooting pose. The mask takes the
# player's colour (Factorio's default orange here).
_PLAYER = (0.87, 0.55, 0.24)
for _name, _base, _bsize, _bshift, _mask, _msize, _mshift in (
        ("character", "level1_idle", (92, 116), (0, -21), "level1_idle_mask", (56, 90), (0, -26)),
        ("character-gun", "level1_idle_gun", (110, 128), (0, -22), "level1_idle_gun_mask", (72, 88), (-0.5, -22))):
    BUILDINGS[_name] = {"anchor": 0.0, "mode": "rotation", "cells": [[
        layer(G + "character/%s.png" % _base, _bsize[0], _bsize[1], _bshift, line=22, index=d * 22),
        layer(G + "character/%s.png" % _mask, _msize[0], _msize[1], _mshift, line=22, index=d * 22, tint=_PLAYER)]
        for d in range(8)]}
# Armour looks: the add-on layer Factorio draws over the plain character in heavy or modular armour
# (level 2) and in power armour (level 3), with its mask, over the plain character's layers.
for _level, _add, _asize, _ashift, _mask, _msize, _mshift in (
        (2, "level2addon_idle", (56, 86), (0.5, -27.5), "level2addon_idle_mask", (52, 84), (0, -28)),
        (3, "level3addon_idle", (74, 86), (0, -28), "level3addon_idle_mask", (74, 72), (0, -31.5))):
    BUILDINGS["character-armor-%d" % _level] = {"anchor": 0.0, "mode": "rotation", "cells": [
        BUILDINGS["character"]["cells"][d] + [
            layer(G + "character/%s.png" % _add, _asize[0], _asize[1], _ashift, line=22, index=d * 22),
            layer(G + "character/%s.png" % _mask, _msize[0], _msize[1], _mshift, line=22, index=d * 22, tint=_PLAYER)]
        for d in range(8)]}
# Mech armour (mech-armor-animations.lua): mech-idle's first frame each way, rows of 11 frames.
BUILDINGS["character-mech-armor"] = {"anchor": 0.0, "mode": "rotation", "cells": [[
    layer(SA + "mech-armor/mech-idle.png", 142, 176, (1, -25.5), line=11, index=d * 22),
    layer(SA + "mech-armor/mech-idle-mask.png", 134, 150, (0.5, -32), line=11, index=d * 22, tint=_PLAYER)]
    for d in range(8)]}

# The crash site (tools/models/crash_site.py): one picture each, numbers from crash-site.lua.
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
    BUILDINGS[_name] = single(layer(_file, _w, _h, _shift))
# Fish: two pictures at normal resolution, one per fish, centred on the water's surface (0.2
# under the ground in the client, terrain_mesher.gd WATER_Y; Factorio's water is at ground level).
BUILDINGS["fish"] = {"anchor": -0.2, "mode": "variation", "cells": [
    [layer(G + "fish/fish-1.png", 22, 36, scale=1.0)], [layer(G + "fish/fish-2.png", 32, 32, scale=1.0)]]}


# Cliffs (nature/cliffs.py): each piece is one orientation, turned in quarter turns for the rest
# (model_library.gd CLIFF_PIECES), so its four direction cells are the sheet rows of those
# orientations: (sheet, column, rows for the model facing north, east, south, west). The sprite's
# lower layer (the foot of the face) goes under the upper one. Space Age's frames are twice as
# big, at the same scale (more room round the rocks).
_CLIFF_PIECES = {"sides": ("sides", 0, (2, 3, 0, 1)), "outer": ("outer", 0, (3, 0, 1, 2)),
                 "inner": ("inner", 0, (0, 1, 2, 3)), "exit": ("entrance", 2, (0, 3, 2, 1)),
                 "entrance": ("entrance", 0, (0, 3, 2, 1))}
for _planet, _dir, _px in (("", "base/graphics/terrain/cliffs/cliff-", 256),
                           ("vulcanus-", "space-age/graphics/terrain/cliffs/vulcanus/cliff-vulcanus-", 512),
                           ("gleba-", "space-age/graphics/terrain/cliffs/gleba/cliff-gleba-", 512),
                           ("fulgora-", "space-age/graphics/terrain/cliffs/fulgora/cliff-fulgora-", 512)):
    for _kind, (_sheet, _col, _rows) in _CLIFF_PIECES.items():
        _line = 4 if _sheet == "entrance" else 8
        BUILDINGS["cliff-" + _planet + _kind] = {"anchor": NATURE_ANCHOR, "mode": "direction", "cells": [
            [layer(_dir + _sheet + "-lower.png", _px, _px, line=_line, index=_row * _line + _col, scale=0.5),
             layer(_dir + _sheet + ".png", _px, _px, line=_line, index=_row * _line + _col, scale=0.5)]
            for _row in _rows]}


def main(argv):
    root = FACTORIO
    if "--factorio" in argv:
        root = argv[argv.index("--factorio") + 1]
    base = os.path.join(root, "data", "base", "prototypes")
    trees_lua = open(os.path.join(base, "entity", "trees.lua"), encoding="utf-8").read()
    deco_lua = open(os.path.join(base, "decorative", "decoratives.lua"), encoding="utf-8").read()
    out = dict(BUILDINGS)
    for i in range(1, 10):
        out["tree-0%d" % i] = tree_entry(trees_lua, "tree-0%d" % i)
    for name in TREE_VARIANTS:
        out[name] = tree_entry(trees_lua, name)
    for name in DEAD:
        out[name] = picture_entry(trees_lua, name)
    for name in ROCKS:
        out[name] = picture_entry(deco_lua, name)
    for name in ORES:
        out[name] = ore_entry(name)
    for name in TRUE_PROPORTIONS:  # entries added after the list was applied
        if name in out:
            out[name]["stretch"] = PIPE_FIT["stretch"]
    missing = []
    for name, entry in out.items():
        for cell in entry["cells"]:
            for lay in cell:
                if not os.path.exists(os.path.join(root, "data", lay["file"])):
                    missing.append("%s: %s" % (name, lay["file"]))
    for m in missing:
        print("missing in this install: " + m)
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, "w", encoding="utf-8", newline="\n") as f:
        f.write("{\n")
        items = sorted(out.items())
        for k, (name, entry) in enumerate(items):
            f.write("  %s: %s%s\n" % (json.dumps(name), json.dumps(entry, separators=(", ", ": ")),
                                      "," if k + 1 < len(items) else ""))
        f.write("}\n")
    print("wrote %s (%d models)" % (OUT, len(out)))
    return 1 if missing else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
