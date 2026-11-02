"""Where the Space Age models' Factorio sprites are: one place for sprite_projection.py (the
client's projection data) and gallery.py (compare.py arguments). Plain Python, no bpy.

Numbers are copied from data/space-age/prototypes/entity/*.lua and the sprite_load .lua files
next to the sheets: `shift` is the .lua's by_pixel shift plus the prototype's own shift (in
tiles times 32), in util.by_pixel units like everywhere else in sprite_projection.json. Only
file names and numbers: the sheets are read from the player's install.
"""

import os

SA = "space-age/graphics/entity/"
SD = "space-age/graphics/decorative/"
BUILDING_ANCHOR = 0.3
NATURE_ANCHOR = 0.0


def layer(file, w, h, shift=(0.0, 0.0), line=0, index=0, scale=0.5, tint=None):
    out = {"file": file, "frame": [w, h], "line": line, "index": index, "shift": [float(shift[0]), float(shift[1])],
           "scale": scale}
    if tint is not None:
        out["tint"] = [round(c, 4) for c in tint]
    return out


def single(*layers, anchor=BUILDING_ANCHOR):
    return {"anchor": anchor, "cells": [list(layers)]}


def directional(n, e, s, w, anchor=BUILDING_ANCHOR):
    """Four cells (north, east, south, west), each a list of layers."""
    return {"anchor": anchor, "mode": "direction", "cells": [list(n), list(e), list(s), list(w)]}


ENTRIES = {}

# --- Space platform (space_platform.py) ----------------------------------------------------------
_HUB = SA + "cargo-hubs/hubs/platform-hub-"
ENTRIES["space-platform-hub"] = single(
    layer(_HUB + "0-A.png", 290, 106, (-39.5, 63.5)), layer(_HUB + "0-B.png", 66, 194, (-99, -75.5)),
    layer(_HUB + "0-C.png", 66, 112, (105, -65.5)), layer(_HUB + "0-D.png", 96, 210, (103, 33)),
    layer(_HUB + "1-A.png", 196, 58, (-23, 72)), layer(_HUB + "1-B.png", 234, 176, (-45, 17.5)),
    layer(_HUB + "1-C.png", 96, 120, (97.5, -114.5)), layer(_HUB + "2.png", 476, 504, (6, -35)),
    layer(_HUB + "3.png", 492, 516, (2, -35)))
ENTRIES["cargo-bay"] = single(
    layer(SA + "cargo-hubs/bays/shared-cargo-bay-0.png", 86, 52, (-32.5, 12)),
    layer(SA + "cargo-hubs/bays/platform-cargo-bay-3.png", 220, 226, (-4, -31.5)))
# The cargo area's edge pieces: the tileset's four layers for one frame of each (base's
# cargo-hubs/connections/connections.lua with space-age's platform- sheets), drawn at the cell's middle.
_CON = SA + "cargo-hubs/connections/platform-connections-"
_CON_LAYERS = [(222, 270, (2.5, -1.0)), (220, 168, (0.5, -24.0)), (148, 198, (-2.5, -6.0)), (152, 164, (-1.0, -20.5))]
for _piece, _frame in (("wall-n", 5), ("wall-e", 1), ("wall-s", 9), ("wall-w", 13), ("corner-nw", 19),
                       ("corner-ne", 17), ("corner-sw", 23), ("corner-se", 21), ("inner-nw", 27),
                       ("inner-ne", 25), ("inner-sw", 31), ("inner-se", 29)):
    ENTRIES["cargo-bay-" + _piece] = single(*[layer(_CON + "%d.png" % i, w, h, sh, line=8, index=_frame - 1)
                                             for i, (w, h, sh) in enumerate(_CON_LAYERS)])
# The thruster only faces north (it pushes the platform north); its nozzle overhangs the deck's
# south edge.
ENTRIES["thruster"] = single(layer(SA + "thruster/thruster-1.png", 264, 542, (1.5, 57), line=8))
_AC = SA + "asteroid-collector/asteroid-collector-"
ENTRIES["asteroid-collector"] = directional(*(
    [layer(_AC + "bottom.png", 322, 106, (0, 64), line=4, index=i),
     layer(_AC + "middle.png", 322, 140, (0, 44), line=4, index=i),
     layer(_AC + "top-%s-base.png" % d, w, h, sh, line=1)]
    for i, (d, w, h, sh) in enumerate((("north", 236, 266, (0, -11)), ("east", 280, 228, (10.5, 2)),
                                       ("south", 238, 254, (0.5, 6)), ("west", 280, 256, (-10.5, -2))))))
# Crusher: one picture for north and south, one for east and west (2x3, long side north-south).
_CV = layer(SA + "crusher/crusher-vertical.png", 140, 194, (2, -7.5), line=8)
_CH = layer(SA + "crusher/crusher-horizontal.png", 200, 162, (2.5, -5), line=8)
# The client draws a model for each picture, unturned (model_library.gd FACING_MODELS): the
# north one facing north and south, crusher-east facing east and west.
ENTRIES["crusher"] = single(_CV)
ENTRIES["crusher-east"] = single(_CH)

# --- Vulcanus (vulcanus.py) ----------------------------------------------------------------------
# Foundry: the same building every way round; only the pipe connections on top change.
_FB = [layer(SA + "foundry/foundry-base.png", 356, 384, (-0.5, -9.5)),
       layer(SA + "foundry/foundry-anim-1.png", 338, 354, (-3.5, -8), line=8)]
ENTRIES["foundry"] = directional(
    _FB + [layer(SA + "foundry/foundry-pipe-connections-north.png", 176, 50, (1, -77.5))],
    _FB, _FB, _FB)
ENTRIES["foundry"]["stretch"] = 1.346  # like the big drill below: modelled at its true proportions
# Factorio draws it the same every way round (only the pipe connections on top change), and so
# does the client (model_library.gd PICTURES).
ENTRIES["foundry"]["pictures"] = 1
# Big mining drill, as big-mining-drill.lua draws it standing still: its frame, the reel (east
# and west), the output chute, the drill head, the carriage's wheels, its support, the frame's
# front, the top nozzle and the drill's top. The head, wheels, support and top ride the
# carriage, which stops at waypoints; all four are drawn at its first stop (lerp 0.5 of the
# waypoint range: 0.3 tiles south for north, 0.325 west for east...), the head also at its own
# north_position. Frame 0 of each animation.
_BMD = SA + "big-mining-drill/"
_BMD_STOP = {"N": (0, 9.6), "E": (-10.4, 0), "S": (0, -9.6), "W": (10.4, 0)}
_BMD_HEAD = {"N": (0, 4.8), "E": (0, 0), "S": (0, 4.8), "W": (0, 0)}


def _bmd(d, folder, still, support, front, nozzle, top, wheels, output, reel=None):
    sx, sy = _BMD_STOP[d]
    hx, hy = _BMD_HEAD[d]

    def moved(spec, dx=0.0, dy=0.0):
        w, h, (x, y) = spec
        return w, h, (x + sx + dx, y + sy + dy)
    out = [layer(_BMD + "%s/big-mining-drill-%s-still.png" % (folder, d), *still, line=1)]
    if reel:
        out.append(layer(_BMD + "%s/big-mining-drill-%s-still-reel.png" % (folder, d), *reel, line=1))
    return out + [
        layer(_BMD + "%s/big-mining-drill-%s-output.png" % (folder, d), *output, line=6 if d in "NS" else 1),
        layer(_BMD + "big-mining-drill-drill.png", *moved((168, 226, (0, -23.5)), hx, hy), line=6),
        layer(_BMD + "%s/big-mining-drill-%s-wheels.png" % (folder, d), *moved(wheels), line=3),
        layer(_BMD + "%s/big-mining-drill-%s-support.png" % (folder, d), *moved(support), line=3),
        layer(_BMD + "%s/big-mining-drill-%s-still-front.png" % (folder, d), *front, line=1),
        layer(_BMD + "%s/big-mining-drill-%s-top-nozzle.png" % (folder, d), *nozzle, line=6),
        layer(_BMD + "%s/big-mining-drill-%s-top.png" % (folder, d), *moved(top), line=6)]


ENTRIES["big-mining-drill"] = directional(
    _bmd("N", "North", (324, 324, (0, -12)), (290, 190, (0.5, -21)), (320, 302, (0, 0.5)), (40, 142, (-18, -73.5)),
         (150, 176, (1, -61.5)), (298, 150, (0, -11)), (128, 88, (-2, -66.5))),
    _bmd("E", "East", (318, 326, (0, -4)), (208, 306, (16, -20)), (188, 352, (32, -10.5)), (118, 68, (38.5, -67.5)),
         (212, 160, (8.5, -56)), (208, 296, (13, -3)), (84, 110, (65.5, -2.5)), reel=(284, 38, (0.5, 42))),
    _bmd("S", "South", (324, 294, (0, -5)), (294, 190, (0, -20.5)), (322, 176, (0, 31)), (40, 192, (18.5, -37.5)),
         (152, 174, (-1, -52.5)), (300, 150, (0, 8)), (134, 78, (1, 65))),
    _bmd("W", "West", (318, 326, (0, -4)), (186, 306, (-10.5, -20)), (188, 352, (-32, -10.5)), (118, 68, (-38, -67.5)),
         (214, 158, (-8.5, -56)), (208, 296, (-13, -3)), (86, 108, (-65.5, -2.5)), reel=(284, 40, (0.5, 41.5))),
)
# Like Wube's own renders (sprite_projection.py TRUE_PROPORTIONS), the drill's pictures draw the
# ground's north-south distances at full length. Measured: the voxels inside all four outlines
# reproduce them to 0.998 / 0.96 / 0.995 / 0.96 (N E S W) with this stretch, against 0.96 / 0.90 /
# 0.92 / 0.90 without it (the front feet, and the far rail in the east and west pictures, then
# had to reach under the ground).
ENTRIES["big-mining-drill"]["stretch"] = 1.346

# --- Fulgora (fulgora.py) ------------------------------------------------------------------------
ENTRIES["electromagnetic-plant"] = single(
    layer(SA + "electromagnetic-plant/electromagnetic-plant-base.png", 238, 252, (2.5, 6)),
    layer(SA + "electromagnetic-plant/electromagnetic-plant-main-rotate-1.png", 226, 312, (0, -14.5), line=8))
_RC = "recycler/graphics/entity/recycler/recycler-"
ENTRIES["recycler"] = directional(
    [layer(_RC + "N.png", 170, 304, (2, -6.5), line=8)], [layer(_RC + "E.png", 286, 204, (1, -8.5), line=8)],
    [layer(_RC + "S.png", 168, 290, (-0.5, 1.5), line=8)], [layer(_RC + "W.png", 284, 186, (0.5, -4.5), line=8)])
ENTRIES["lightning-rod"] = single(layer(SA + "lightning-rod/lightning-rod.png", 108, 352, (-2, -62)))
ENTRIES["lightning-collector"] = single(layer(SA + "lightning-collector/lightning-collector.png", 180, 434, (2.5, -66.5)))
# Tesla turret: the base and the raised head facing north (64 directions, north first).
ENTRIES["tesla-turret"] = single(
    layer(SA + "tesla-turret/tesla-turret-base.png", 268, 258, (-1, -0.5)),
    layer(SA + "tesla-turret/tesla-turret-head-attacking.png", 130, 134, (0, -74.5), line=8))

# --- Nature (space_nature.py, fulgora.py, vulcanus.py): anchored on the ground; frame 0 of each. ----
_VR = SD + "vulcanus-rocks/vulcanus-rock-"
for _n, _f, _w, _h, _sh in (("big-volcanic-rock", "big", 258, 178, (7.5, 1.75)), ("huge-volcanic-rock", "huge", 524, 268, (-6.5, 1.5))):
    ENTRIES[_n] = single(layer(_VR + _f + "-1.png", _w, _h, _sh, line=1), anchor=NATURE_ANCHOR)
    ENTRIES[_n + "-hot"] = single(layer(_VR + _f + "-1.png", _w, _h, _sh, line=1), anchor=NATURE_ANCHOR)
_VC = SD + "vulcanus-chimney/"
for _n, _f in (("vulcanus-chimney", "sulfuric-chimney"), ("vulcanus-chimney-faded", "sulfuric-chimney-faded"),
               ("vulcanus-chimney-cold", "cold-chimney")):
    ENTRIES[_n] = single(layer(_VC + _f + "-lower-1.png", 348, 282, (10.5, 21.5), line=1),
                         layer(_VC + _f + "-upper-1.png", 280, 284, (13, -43.5), line=1), anchor=NATURE_ANCHOR)
for _n, _f in (("vulcanus-chimney-short", "sulfuric-chimney-short"), ("vulcanus-chimney-truncated", "sulfuric-chimney-truncated")):
    ENTRIES[_n] = single(layer(_VC + _f + "-lower-1.png", 296, 238, (-0.5, -14), line=1),
                         layer(_VC + _f + "-upper-1.png", 196, 172, (-1, -24.5), line=1), anchor=NATURE_ANCHOR)
_FR = SD + "fulgoran-ruin/fulgoran-ruin-"
for _n, _w, _h, _line, _sh, _sc in (("tiny", 128, 128, 7, (0, 0), 0.3), ("small", 192, 192, 9, (7.5, -5.5), 0.5),
                                     ("medium", 256, 256, 5, (8.25, -11.75), 0.5), ("stonehenge", 512, 448, 4, (29, -26.25), 0.5),
                                     ("big", 448, 320, 4, (22.25, -3.75), 0.5), ("huge", 576, 512, 4, (21, -15.25), 0.5),
                                     ("colossal", 832, 576, 1, (62.75, -26.75), 0.5), ("vault", 960, 640, 1, (9.25, -3), 0.5)):
    ENTRIES["fulgoran-ruin-" + _n] = single(layer(_FR + _n + ".png", _w, _h, _sh, line=_line, scale=_sc), anchor=NATURE_ANCHOR)

_RUIN_FLOODED = SD + "fulgora-ruin-flooded/"
ENTRIES["fulgora-sunk-ruin-big"] = single(
    layer(_RUIN_FLOODED + "big/sunken-ruin-big-1.png", 508, 400, (-12.5, -2.5)), anchor=NATURE_ANCHOR)
ENTRIES["fulgora-sunk-ruin-medium-tall"] = single(
    layer(_RUIN_FLOODED + "medium/sunken-ruin-medium-0004.png", 272, 198, (27.2, -12.8)), anchor=NATURE_ANCHOR)

ENTRIES["fulgoran-ruin-attractor"] = single(layer(_FR + "attractor.png", 448, 384, (51.5, -50), line=4), anchor=NATURE_ANCHOR)
ENTRIES["fulgurite"] = single(layer(SD + "fulgurite/fulgurite.png", 284, 298, (-6, -13.5), line=4), anchor=NATURE_ANCHOR)
ENTRIES["fulgurite-small"] = single(layer(SD + "fulgurite/fulgurite-small.png", 150, 152, (-2, 0), line=4), anchor=NATURE_ANCHOR)
# Space Age stromatolites and ore patches use the same sprites and projection as the client.
ENTRIES["copper-stromatolite"] = single(
    layer(SA + "stromatolite/copper/copper-stromatolite-1.png", 246, 174, (2.75, 0.75), line=1, scale=0.4),
    anchor=NATURE_ANCHOR)
ENTRIES["iron-stromatolite"] = single(
    layer(SA + "stromatolite/iron/iron-stromatolite-1.png", 258, 204, (0.75, 3.5), line=1, scale=0.4),
    anchor=NATURE_ANCHOR)
for _ore in ("tungsten-ore", "calcite"):
    ENTRIES[_ore] = {"anchor": NATURE_ANCHOR, "mode": "variation", "cells": [
        [layer(SA + "%s/%s.png" % (_ore, _ore), 128, 128, line=8, index=16 + _v)] for _v in range(8)]}
for _n in ("ashland-lichen-tree", "ashland-lichen-tree-flaming"):
    ENTRIES[_n] = single(layer(SA + "plant/ashland-trees/ashland-tree_00.png", 296, 274, (-2, -23), line=1), anchor=NATURE_ANCHOR)
ENTRIES["sulfuric-acid-geyser"] = single(layer(SA + "sulfuric-acid-geyser/sulfuric-acid-geyser.png", 254, 178, (9.5, 5), line=4),
                                         anchor=NATURE_ANCHOR)
# Scrap: like the ores, eight variations of one richness stage (row 2 of the 8x8 sheet).
ENTRIES["scrap"] = {"anchor": NATURE_ANCHOR, "mode": "variation",
                    "cells": [[layer(SA + "scrap/scrap.png", 128, 128, line=8, index=16 + v)] for v in range(8)]}

# Asteroids: the first colour variation of each, centred on the rock (the models are centred too).
_AST_FRAME = {"small": (128, 0.5), "medium": (230, 0.5), "big": (304, 0.6), "huge": (512, 0.75)}
for _kind in ("metallic", "carbonic", "oxide", "promethium"):
    for _size, (_px, _sc) in _AST_FRAME.items():
        ENTRIES["%s-%s-asteroid" % (_size, _kind)] = single(
            layer(SA + "asteroid/%s/%s/asteroid-%s-%s-colour-01.png" % (_kind, _size, _kind, _size), _px, _px, scale=_sc),
            anchor=0.0)

# Demolishers (vulcanus.py): 128 directions in sheets of 12 (6 rows of 2); every other one makes
# the 64 cells of "rotation" mode, clockwise from north. At the big demolisher's scale (1), the
# models' scale; the client scales the instance, and the projection with it.
def _lavaslug(part, w, h, shift):
    def cell(i):
        d = i * 2
        return [layer(SA + "lavaslug/lavaslug-%s-%d.png" % (part, d // 12 + 1), w, h, shift, line=2, index=d % 12)]
    return {"anchor": 0.0, "mode": "rotation", "cells": [cell(i) for i in range(64)], "atlas_scale": 0.25}


ENTRIES["demolisher-head"] = _lavaslug("head", 610, 586, (0.5, -27.5))
ENTRIES["demolisher-segment"] = _lavaslug("segment", 606, 586, (0, -37.5))
ENTRIES["demolisher-tail"] = _lavaslug("tail", 812, 616, (0.5, -5))

# Which cell compare.py shows for each model, and the model's turn for it (degrees clockwise).
COMPARE_CELL = {}


def compare_args(name, factorio, cell=None):
    """gallery.py's argument list for `name`: [sheet relative to the install, --frame, ...]."""
    entry = ENTRIES[name]
    k = COMPARE_CELL.get(name, 0) if cell is None else cell
    layers = entry["cells"][k]
    first, rest = layers[0], layers[1:]

    def spec(lay):
        return "|".join((os.path.join(factorio, "data", lay["file"]), "%dx%d" % tuple(lay["frame"]), str(lay["index"]),
                         str(lay["line"]), "%g,%g" % tuple(lay["shift"])))

    args = ["data/" + first["file"], "--frame=%dx%d" % tuple(first["frame"]), "--line=%d" % first["line"],
            "--index=%d" % first["index"], "--shift=%g,%g" % tuple(first["shift"]), "--anchor=%g" % entry["anchor"],
            "--scale=%g" % first["scale"]]
    if entry.get("mode") == "direction":
        args.append("--rot=%d" % (90 * (k % entry.get("pictures", 4))))
    if "stretch" in entry:
        args.append("--stretch=%g" % entry["stretch"])
    args += ["--layer=" + spec(lay) for lay in rest]
    return args

# Pentapods (gleba.py): the torso's 64 directions (Factorio draws the legs as separate entities,
# which these leave out), its main layer under the tier's tint, the mask's overlay left out. The
# models' torsos are lifted by the prototype's `height`: so are these pictures.
_UP = 0.669  # a tile of height, in tiles up the screen (cos 48 deg)
_PENTAPOD_TINTS = {"small": (0.49, 0.486, 0.435), "medium": (0.453, 0.492, 0.437), "big": (0.463, 0.459, 0.417)}
_STRAFER_TINTS = {"small": (0.49, 0.486, 0.435), "medium": (0.451, 0.478, 0.447), "big": (0.463, 0.459, 0.417)}
for _tier, _k in (("small", 0.5625), ("medium", 0.75), ("big", 1.0)):
    ENTRIES[_tier + "-stomper-pentapod"] = {"anchor": 0.0, "mode": "rotation", "atlas_scale": 0.5, "cells": [
        [layer(SA + "stomper/torso/head-main.png", 412, 368, (6, -33 - 0.7 * _UP * 32), line=8, index=i, scale=0.66 * _k,
               tint=_PENTAPOD_TINTS[_tier])] for i in range(64)]}
    ENTRIES[_tier + "-strafer-pentapod"] = {"anchor": 0.0, "mode": "rotation", "atlas_scale": 0.5, "cells": [
        [layer(SA + "strafer/torso/torso-main.png", 168, 154, (0, -1.5 * _UP * 32), line=8, index=i, scale=0.48 * _k,
               tint=_STRAFER_TINTS[_tier]),
         layer(SA + "strafer/torso/head-main.png", 400, 306, (0, -22 - 1.5 * _UP * 32), line=8, index=i, scale=0.48 * _k,
               tint=_STRAFER_TINTS[_tier])] for i in range(64)]}
# The wriggler: the run animation's first frame each of 16 ways (21 frames a direction, sheets
# of 17 rows of 5); the small and medium tiers are its model scaled and tinted in the client.
ENTRIES["big-wriggler-pentapod"] = {"anchor": 0.0, "mode": "rotation", "atlas_scale": 0.5, "cells": [
    [layer(SA + "wriggler/wriggler-run-%d.png" % (d * 21 // 85 + 1), 284, 228, (0, -5.5), line=5, index=d * 21 % 85,
           scale=0.6, tint=(0.459, 0.455, 0.408))] for d in range(16)]}
# Gleba spawners: the first variation's first frame, where Factorio draws it (the models were
# measured from it with the entity's position on the ground); the corpse's splash at 0.9.
ENTRIES["gleba-spawner"] = single(layer(SA + "gleba-spawner/spawner-upper-1.png", 330, 284, (5, 17), line=8),
                                  anchor=NATURE_ANCHOR)
ENTRIES["gleba-spawner-small"] = single(layer(SA + "gleba-spawner/small/spawner-upper-small-1.png", 132, 102, (-2, 0),
                                              line=8), anchor=NATURE_ANCHOR)
ENTRIES["gleba-spawner-corpse"] = single(layer(SA + "gleba-spawner/gleba-spawner-corpse.png", 448, 448, scale=0.9),
                                         anchor=NATURE_ANCHOR)
