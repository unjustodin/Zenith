"""Recipes for tools/models/wube.py: how each client model is made from Wube's printable STLs.

A recipe lists its parts by STL file name, each with a palette material (kit.py's MATERIALS,
plus EXTRA_MATERIALS below) and these optional steps, applied in this order:

  pick       print plates: keep these connected pieces, by rank (0 = most triangles)
  pick_box   print plates: keep the pieces whose middle lies in (x0, y0, x1, y1), plate mm
  drop       rule(centroids, normals, lo, hi) -> faces to throw away (print-only bits)
  pivot      (x, y) plate mm: a moving part's joint, put at the origin; the part isn't centred
  cut_below  mm above the part's lowest point; everything below goes (grid pegs)
  mirror     "x", "y" or "z": mirror the part
  scale      number or (x, y, z), before standing it up
  tilt       [(axis, degrees), ...] stand up a part printed lying down (right-handed, glTF axes)
  yaw        degrees about +y (counter-clockwise from above); default: the recipe's `yaw`
  raw_frame  keep the part where the print file has it instead of centring it (walls are
             modelled around their tile's centre)
  trim       (half_x, half_z) in tiles: cut away anything beyond, e.g. joining tabs
  on, inset  stack on an earlier part (by index): lowest point at that part's top minus inset
  offset     (x, y, z) tiles
  trim       is applied after the offset
  paint      [(material, rule), ...]: faces the rule picks (in the placed part's frame) get that
             material instead of the part's own

Then for the whole model: `untaper`, `scale` and `shift` fit it to Factorio's sprite (see
wube.assemble), and `budget` overrides specs.py's triangle budget.

Every part is centred on the tile before stacking and offsets, so offsets are relative to the
entity's own centre. Orientation: models face north; things that can't rotate keep their front
(door, fire hatch) to the south, towards the default camera, like Factorio's sprites. In the
print files belts run east, so straight belt parts turn 90 degrees.

Assembly values were found by rendering the parts (and cross-checked against the Factorio2IRL
viewer, which assembles the same print files). Every model here was looked at in a render, except
those marked `"checked": False`, which still need a look.
"""

import math

import numpy as np

COPYRIGHT = "Wube Software, CC BY-NC (printables.com/@WubeSoftware); converted by factorio-3d"

# Materials not in kit.py: (sRGB hex, roughness, metallic, emission hex or None, strength).
EXTRA_MATERIALS = {
    # Hues from the sprites (their median saturated colour), about twice as bright since the
    # client lights them again.
    "logistic_red": ("a8352a", 0.55, 0.35, None, 0),
    "logistic_purple": ("74378a", 0.55, 0.35, None, 0),
    "logistic_yellow": ("b09028", 0.55, 0.35, None, 0),
    "logistic_green": ("3a8a48", 0.55, 0.35, None, 0),
    "logistic_blue": ("33808f", 0.55, 0.35, None, 0),
    # Inserter platforms, by tier (their legs and ring; the turntable is bronze).
    "inserter_yellow": ("c88a1e", 0.5, 0.45, None, 0),
    "inserter_red": ("b2271a", 0.5, 0.45, None, 0),
    "inserter_blue": ("2f82a8", 0.5, 0.45, None, 0),
    "inserter_green": ("7a9c2c", 0.5, 0.45, None, 0),
    # Factorio's wall: weathered beige-grey concrete (the sprites' lit faces, lighting taken out).
    "concrete_wall": ("9c907f", 0.9, 0.0, None, 0),
}
LOGISTIC_SCALE, LOGISTIC_UNTAPER, LOGISTIC_SHIFT = (1.184, 1.120, 0.891), 0.078, (-0.006, -0.082)

BELTS = "Belts High Precision"
RECIPES = {}

# --- Belts: a frame ("Bottom") and the moving surface ("Top") that sits in it -----------------

# Wube's belt stands 0.35 tall, the surface riding above the side rails; Factorio's belts lie
# nearly flat, so every belt model is squashed to BELT_HEIGHT of that (surface top 0.19, which
# belt_items.gd reads as the height items ride at). The print's joining tabs are trimmed off.
BELT_HEIGHT = 0.55
# Fitted to Factorio's belt sheet in all four directions (tools/models/fit.py; score.py's
# BELT_ANCHOR): the belt is drawn a little wider than its tile (no untaper: it would
# lengthen them too). Straight belts keep their length so they still join; curves grow about their inner corner, which keeps their ends
# on the tile's edges.
BELT_WIDTH = 1.08
CURVE_SCALE, CURVE_HEIGHT = 1.08, 1.086
RECIPES["transport-belt"] = {
    "yaw": 90, "scale": (BELT_WIDTH, BELT_HEIGHT, 1),
    "parts": [
        {"file": "Straight Bottom.stl", "material": "tier_paint", "trim": (0.5, 0.5)},
        {"file": "Straight Top.stl", "material": "belt_surface", "on": 0, "inset": 0.037},
    ],
}
# Both turns share one frame, a quarter circle round the corner the belt turns about. The left
# turn enters from the west and leaves north (as printed, round the north-west corner); the right
# turn is the frame turned -90 degrees, round the north-east corner, entering from the east. Each
# has its own surface (the slats' chevrons point along the turn).
for _side, _top, _yaw, _x in (("left", "Turn L Top.stl", 0, -1), ("right", "Turn R Top.stl", -90, 1)):
    _grow = (CURVE_SCALE - 1) / 2  # scaled about the inner corner: north-west (left), north-east (right)
    RECIPES["transport-belt-curve-" + _side] = {
        "yaw": _yaw, "scale": (CURVE_SCALE, BELT_HEIGHT * CURVE_HEIGHT, CURVE_SCALE),
        "shift": (-_x * _grow, _grow),
        "parts": [
            {"file": "Turn Bottom.stl", "material": "tier_paint", "offset": (0.075 * _x, 0, -0.075), "trim": (0.5, 0.5)},
            {"file": _top, "material": "belt_surface", "on": 0, "inset": 0.037, "offset": (0.062 * _x, 0, -0.062),
             "trim": (0.5, 0.5)},
        ],
    }

# Undergrounds: a belt frame and a hood printed standing on its mouth. Tilted 101 degrees onto
# the frame (its mouth is cut at a slant), the hood's lip rests on the ground. Both ends face
# their sprite's way at rest: the entrance's mouth opens south to the belt that feeds it, its
# chevrons pointing north; the exit as Factorio's 1.x exit sprite for "north" (mouth open south,
# chevrons pointing south, back at its entrance). In 2.x an exit's direction is the way items
# travel, so the client turns exits round and reverses their scroll (model_library.gd). The belt under the hood is
# squashed like the belts (BELT_HEIGHT); the hood to 0.93 of its print height, as its sprite.
# Model-level scale and untaper fitted to the structure sheet over its belt (fit.py, BELT_ANCHOR).
for _end, _name, _yaw, _fit in (("In", "input", -90, ((1.018, 0.958, 1), -0.16)),
                                ("Out", "output", -90, ((1.042, 0.991, 1), -0.2))):
    RECIPES["underground-belt-" + _name] = {
        "yaw": _yaw, "scale": _fit[0], "untaper": _fit[1],
        "parts": [
            {"file": "Underground %s Bottom.stl" % _end, "material": "belt_surface", "scale": (1, BELT_HEIGHT, 1)},
            {"file": "Underground %s Top.stl" % _end, "material": "tier_paint", "tilt": [("z", 101)],
             "scale": (1, 0.93, 1)},
        ],
    }

# Not yet: "Splitter Top" is the belts and their mechanism laid out flat for printing, and it
# needs taking apart and assembling on its deck. The procedural splitter stays until then.

# --- Chests ----------------------------------------------------------------------------------
# The "Closed" files are each chest in one piece, lid shut (the "Open" folder has the bodies and
# lids apart, for the opened look). Printed, they're about 0.75 tiles across and drafted narrower
# at the top; Factorio draws them nearly a tile wide and squarer, so each is scaled to its sprite
# (`scale`, `untaper`, `shift`: fitted to the silhouette from Factorio's camera with the
# projection's north-south stretch, sprite_projection.py TRUE_PROPORTIONS, with tools/models/fit.py,
# counting what sticks out of the sprite's frame). The machines too.

RECIPES["wooden-chest"] = {"scale": (1.13, 0.876, 0.908), "untaper": 0.149, "shift": (0.016, -0.035),
                           "parts": [{"file": "Wooden Closed.stl", "material": "wood_light"}]}
RECIPES["iron-chest"] = {"scale": (1.195, 0.938, 1.134), "untaper": -0.006, "shift": (-0.024, -0.103),
                         "parts": [{"file": "Iron Closed.stl", "material": "iron_rust"}]}
RECIPES["steel-chest"] = {"scale": (1.219, 1.153, 0.936), "untaper": 0.045, "shift": (-0.001, 0.019),
                          "parts": [{"file": "Steel Closed.stl", "material": "steel_light"}]}


# Logistic chests: a dark steel body; the lid plate (round the grey hatch) and the slatted side
# panels wear the chest's colour, as in the sprites. Rules in the part's own frame (tiles, centred
# on the ground; the body is 0.84 wide, 0.68 tall, its lid plate from 0.56 up).
def _logistic_panel(c, n, lo, hi):
    side = np.abs(n[:, 1]) < 0.6
    along = np.where(np.abs(n[:, 0]) > np.abs(n[:, 2]), np.abs(c[:, 2]), np.abs(c[:, 0]))
    return side & (c[:, 1] > 0.18) & (c[:, 1] < 0.52) & (along < 0.25)


def _logistic_lid(c, n, lo, hi):
    r = np.hypot(c[:, 0], c[:, 2])
    corner = (np.abs(c[:, 0]) > 0.29) & (np.abs(c[:, 2]) > 0.29)
    return (c[:, 1] > 0.575) & (r > 0.185) & ~corner & (np.maximum(np.abs(c[:, 0]), np.abs(c[:, 2])) < 0.37)


# The round hatch in the lid: pale steel, as the sprites'.
def _logistic_hatch(c, n, lo, hi):
    return (c[:, 1] > 0.5) & (np.hypot(c[:, 0], c[:, 2]) < 0.2)


# The hatch: a plate with a cross in relief, sunk 0.07 into the lid inside a pale rim. It opens for
# robots: its halves slide apart (anim_hatch_e, anim_hatch_w, anim.gd) over a dark well (a copy of
# the plate left lower down).
def _logistic_plate(c, n, lo, hi):
    return _logistic_hatch(c, n, lo, hi) & (np.hypot(c[:, 0], c[:, 2]) < 0.167)


def _logistic_hatch_e(c, n, lo, hi):
    return _logistic_plate(c, n, lo, hi) & (c[:, 0] >= 0)


def _logistic_hatch_w(c, n, lo, hi):
    return _logistic_plate(c, n, lo, hi) & (c[:, 0] < 0)


for _chest, _colour in (("passive-provider-chest", "logistic_red"), ("active-provider-chest", "logistic_purple"),
                        ("storage-chest", "logistic_yellow"), ("buffer-chest", "logistic_green"),
                        ("requester-chest", "logistic_blue")):
    RECIPES[_chest] = {"scale": LOGISTIC_SCALE, "untaper": LOGISTIC_UNTAPER, "shift": LOGISTIC_SHIFT, "parts": [
        {"file": "Logistics Closed.stl", "material": "olive_dark",
         "paint": [("steel_light", _logistic_hatch_e, "anim_hatch_e", ("steel_black", -0.1)),
                   ("steel_light", _logistic_hatch_w, "anim_hatch_w", ("steel_black", -0.1)),
                   ("steel_light", _logistic_hatch), (_colour, _logistic_panel), (_colour, _logistic_lid)]},
    ]}

# --- Machines --------------------------------------------------------------------------------

# Scaled and placed to their sprites (silhouette fits from Factorio's camera). The print files
# are dense (the assembler has 470k triangles), so wube.py decimates them in Blender.
#
# The assembler's two meshing gears in the north-west of its works (Factorio's anim layer turns
# its gears, about a turn a loop) are printed fused to the rest: cut out by where they are (the
# part's frame: centred, on the ground), each turning about its own axle. The west gear (ten
# teeth, 0.412-0.458 up) lies a little over the east one (a toothed ring with a star on it,
# 0.373-0.458), its teeth over the east one's; the crank arm lying across both (0.469 up) stays.
AM1_GEAR_W, AM1_GEAR_E, AM1_GEAR_R = (-0.4375, -0.43), (-0.15, -0.425), 0.21


def _am1_gear_w(c, n, lo, hi):
    rw = np.hypot(c[:, 0] - AM1_GEAR_W[0], c[:, 2] - AM1_GEAR_W[1])
    re = np.hypot(c[:, 0] - AM1_GEAR_E[0], c[:, 2] - AM1_GEAR_E[1])
    upper = (c[:, 1] > 0.428) | ((n[:, 1] < -0.5) & (c[:, 1] > 0.405))  # its side faces and underside
    return (rw < AM1_GEAR_R - 0.005) & (c[:, 1] > 0.405) & (c[:, 1] < 0.466) & ((re >= AM1_GEAR_R) | upper)


def _am1_gear_e(c, n, lo, hi):
    re = np.hypot(c[:, 0] - AM1_GEAR_E[0], c[:, 2] - AM1_GEAR_E[1])
    post = (c[:, 0] > -0.26) & (c[:, 0] < -0.13) & (c[:, 2] > -0.32) & (c[:, 2] < -0.25)  # a block in front, not the gear
    return (re < AM1_GEAR_R) & (c[:, 1] > 0.365) & (c[:, 1] < 0.466) & ~post


RECIPES["assembling-machine-1"] = {"scale": (1.009, 1.166, 0.898), "untaper": 0.039, "shift": (-0.002, 0.046), "budget": 14500,
                                   "parts": [{"file": "Assembling Machine.stl", "material": "olive_steel",
                                              "nodes": [("anim_gear_am1_w", _am1_gear_w), ("anim_gear_am1_e", _am1_gear_e)]}],
                                   "node_budgets": {"anim_gear_am1_w": 700, "anim_gear_am1_e": 800},
                                   # Each gear's axle in the model frame: the centres above scaled,
                                   # untapered at the gears' height (x1.012) and shifted.
                                   "pivots": {k: (x * 1.009 * 1.012 - 0.002, 0.53, z * 0.898 * 1.012 + 0.046)
                                              for k, (x, z) in (("anim_gear_am1_w", AM1_GEAR_W), ("anim_gear_am1_e", AM1_GEAR_E))}}


# The stone furnace's fire: Factorio draws it in the mouth (stone-furnace-fire, 48 frames). The
# print's mouth is a tunnel into the body; its walls, floor and back (and the hollow's floor seen
# through it) are painted with the emissive `fire`, which the client lights and flickers while the
# furnace works.
def _sf_mouth(c, n, lo, hi):
    tunnel = (np.abs(c[:, 0]) < 0.115) & (c[:, 1] > 0.19) & (c[:, 1] < 0.6) & (c[:, 2] > -0.5) & (c[:, 2] < 0.45)
    floor = (np.abs(c[:, 0]) < 0.13) & (c[:, 1] < 0.25) & (c[:, 2] > -0.5) & (c[:, 2] < 0.38) & (n[:, 1] > 0.5)
    return tunnel | floor


RECIPES["stone-furnace"] = {"scale": (1.192, 1.219, 0.92), "untaper": 0.009, "shift": (-0.005, 0.167),
                            "parts": [{"file": "Stone Furnace.stl", "material": "stone", "refine": 0.04,
                                       "paint": [("fire", _sf_mouth)]}]}
# The plate holds the body and its three pipes, each printed as two half-shells lying flat (cut
# face down; the collars are moulded on). Each pipe stands up (tilted onto its edge) with its
# partner turned round behind it, cut faces meeting: the long pipe from the back socket over to
# the chimney, the middle pipe from the west socket into the chimney's side, the small bend on the
# west side. Placed against the sprite with tools/models/fit.py (0.945 -> 0.959).
_SF, _SF_HALF = "Steel Furnace.stl", 0.03


def _sf_pipe(halves, offset, yaw=0):
    a, b = halves
    x, y, z = offset
    return [{"file": _SF, "material": "bronze", "pick": [a], "tilt": [("x", -90)], "yaw": yaw, "offset": (x, y, z - _SF_HALF)},
            {"file": _SF, "material": "bronze", "pick": [b], "tilt": [("x", -90)], "yaw": yaw + 180,
             "offset": (x, y, z + _SF_HALF)}]


# The fire: Factorio draws it in the firebox door low on the front (steel-furnace-fire, 48
# frames). The print's door is a panel recessed into the front's frame; the panel and the
# recess's sides are painted with the emissive `fire`, lit and flickering while the furnace works.
def _stf_firebox(c, n, lo, hi):
    return (c[:, 0] > -0.255) & (c[:, 0] < 0.285) & (c[:, 1] > 0.18) & (c[:, 1] < 0.41) & (c[:, 2] > 0.54) & (c[:, 2] < 0.70)


RECIPES["steel-furnace"] = {"scale": (1.229, 1.233, 0.930), "untaper": -0.011, "shift": (-0.009, 0.053),
                            "parts": [{"file": _SF, "material": "steel_dark", "pick": [0], "refine": 0.04,
                                       "paint": [("fire", _stf_firebox)]}]
                            + _sf_pipe((3, 4), (0.05, 0.76, -0.2))
                            + _sf_pipe((1, 2), (0.0, 0.62, 0.12), yaw=180)
                            + _sf_pipe((5, 6), (-0.6, 0.5, 0.3))}

# --- Inserters: the platform; the client draws the arm --------------------------------------
# "Base Single" is the platform in one piece (legs, ring, turntable; "Base" is the same split for
# printing, "Tile" a print base). It already matches the north-facing sprite: one leg north, two
# south. The legs and ring wear the tier's colour, the turntable (inside the ring) is bronze.
# (The recipes are further down, after the pole's helpers.)

POLE_SCALE, POLE_SHIFT = (1.02, 1.2, 1.0), (0.32, -0.18)


# The pole's wooden post; the metal cap and crossarm (top 0.55 of the print) are steel and the
# insulators ceramic, as in the sprite.
def _pole_metal(c, n, lo, hi):
    return c[:, 1] > POLE_METAL_FROM


def _pole_insulator(c, n, lo, hi):
    return c[:, 1] > POLE_INSULATOR_FROM


POLE_METAL_FROM, POLE_INSULATOR_FROM = 2.55, 3.17
POLE_PAINT = [("ceramic", _pole_insulator), ("steel", _pole_metal)]

# Factorio draws the platform as four separate renders (one per direction), and they don't sit
# alike: the platform's place moves by up to 0.045 tiles and its size by 3% between them, more
# than one turned model can follow (overlap 0.86-0.87 at best). So each direction has its own
# model, drawn unturned (model_library.gd FACING_MODELS): the print turned to that direction,
# then scaled, widened towards the top (`untaper`) and shifted to fit that picture alone
# (fit.py's overlap with the projection's anchor 0.325 and stretch 0.955, sprite_projection.py,
# the model's silhouette rasterised 4x4 and averaged as Blender's anti-aliased render is: for a
# shape this thin fit.py's plain fill reads about 0.02 higher than score_proto.py).
# Factorio's platform pictures are flatter north to south than its other buildings (stretch
# 0.955, not 1.346): at true proportions the best fit needs the platform squashed to 0.73 of its
# depth in every direction. The sprites' feet reach about 0.08 tiles past the tile, as the
# models' now do (specs.py `overhang`). Numbers per direction, in the print's own (north) frame:
# scale x, y, z, untaper, shift x, z. The turntable stays within 0.05 tiles of the entity's
# position, where the client's arm turns.
INSERTER_FITS = {
    "": (1.298, 1.161, 1.344, 0.105, 0.012, -0.023),
    "-east": (1.331, 1.160, 1.341, 0.144, 0.003, -0.042),
    "-south": (1.311, 1.156, 1.377, 0.089, -0.027, -0.052),
    "-west": (1.343, 1.147, 1.335, 0.142, -0.015, -0.010),
}
INSERTER_TURNTABLE_Z = 0.031
# The arm's slot goes right through the print's turntable; the sprite draws it closed (dark), so
# a dark floor closes it at the turntable's bottom (print frame, tiles; the turntable stands on
# the ring 0.168 above the ground, between the legs).
INSERTER_SLOT = (-0.058, 0.168, -0.018, 0.058, 0.21, 0.08)


def _inserter_variant(colour, turn, fit):
    """One direction's platform: the print turned `turn` quarter turns clockwise."""
    yaw = -90 * turn
    a = math.radians(yaw)
    sx, sy, sz, untaper, dx, dz = fit
    if turn % 2:
        sx, sz = sz, sx
    # The turntable's centre, and the fitted shift, turned with the print (wube.yaw_matrix).
    tx, tz = math.sin(a) * INSERTER_TURNTABLE_Z, math.cos(a) * INSERTER_TURNTABLE_Z

    def turntable(c, n, lo, hi):
        return np.hypot(c[:, 0] - tx, c[:, 2] - tz) < 0.185
    return {"yaw": yaw, "scale": (sx, sy, sz), "untaper": untaper,
            "shift": (math.cos(a) * dx + math.sin(a) * dz, -math.sin(a) * dx + math.cos(a) * dz), "parts": [
        {"file": "Base Single.stl", "material": colour, "paint": [("bronze", turntable)]},
        {"box": INSERTER_SLOT, "material": "steel_black"}]}


INSERTER_FACINGS = ("", "-east", "-south", "-west")
for _inserter, _colour in (("burner-inserter", "rust_light"), ("inserter", "inserter_yellow"),
                           ("long-handed-inserter", "inserter_red"), ("fast-inserter", "inserter_blue"),
                           ("bulk-inserter", "inserter_green"), ("stack-inserter", "steel_light")):
    for _turn, _sfx in enumerate(INSERTER_FACINGS):
        RECIPES[_inserter + _sfx] = _inserter_variant(_colour, _turn, INSERTER_FITS[_sfx])

# --- Power -----------------------------------------------------------------------------------

# The plate holds three pieces: the pole split lengthwise into two half-shells lying flat (post,
# crossarm and insulators; the flat faces are the cut, glued back to back), and the cast foot, a
# socket the post stands in with a brace to the west, standing upright. Each half stands up with
# its crossarm end on top: the larger half (crossarm at the print's +z end) is the north half, the
# other the south half; both crossarms reach west, as in the sprite. The post (0.167 across) sits
# in the socket's bore, whose floor is 0.167 above the ground; parts are centred on their own
# bounds, so the offsets put the post's axis and the socket's bore at the origin.
_POST = 0.2735     # post axis east of each half's bounds centre (tiles, print scale)
_BORE = 0.1423     # socket bore east of the foot's bounds centre
_HALF = 0.047      # half the shell's thickness: moves each cut face onto the centre plane
RECIPES["small-electric-pole"] = {"scale": POLE_SCALE, "shift": POLE_SHIFT, "parts": [
    {"file": "Small Electric Pole.stl", "material": "wood_orange", "pick": [1], "tilt": [("x", -90)],
     "offset": (-_POST, 0.167, -_HALF), "paint": POLE_PAINT},
    {"file": "Small Electric Pole.stl", "material": "wood_orange", "pick": [2], "tilt": [("x", 90)],
     "offset": (-_POST, 0.167, _HALF), "paint": POLE_PAINT},
    {"file": "Small Electric Pole.stl", "material": "blue_steel", "pick": [0], "offset": (-_BORE, 0, 0)},
]}

# --- Electric mining drill -------------------------------------------------------------------

# One print plate of 16 loose pieces (electric-mining-drill-main.stl), picked by size rank: the
# U-shaped base frame (rails east and west, the output rollers and motor across the north end),
# the drill head (motor, crown with its hoses, auger), its two sloping arms and their shoes on
# the rails, the yellow corner brackets, the output chute and the status lamp. The grid tile it
# stands on (electric-miner-high-*.stl) and the brim helpers are left out. The auger is the
# separate `anim_spin_drill` node the client spins while the drill works.
_EMD = "electric-mining-drill-main.stl"


# The frame's outer rails are painted hazard orange on their outside and top, as the sprite's (its
# tracks and the inside stay dark steel). Only the wide northern half of each rail: the southern
# half is all track teeth, which a face rule can't paint cleanly.
def _emd_frame_paint(c, n, lo, hi):
    out = np.sign(c[:, 0]) * n[:, 0] > 0.4
    return (np.abs(c[:, 0]) > EMD_RAIL_X) & (out | (n[:, 1] > 0.6))


EMD_RAIL_X = 1.12
# Placed against Factorio 2.0's four direction pictures (tools/models/fit.py, the parts moved as
# groups: the frame on the ground, the head as one, arms, racks and brackets as mirrored pairs):
# the frame widened to the sprite's broad tracks (as far as its 3x3 tiles allow), the head lower,
# the arms higher.
EMD_FRAME = (1.1, 1, 1.03)
EMD_HEAD = (0, 0.92 - 0.18, 0)
RECIPES["electric-mining-drill"] = {"parts": [
    {"file": _EMD, "pick": [1], "material": "steel_dark", "yaw": 180, "scale": EMD_FRAME, "offset": (0, 0, -0.12),
     "paint": [("hazard", _emd_frame_paint)]},
    {"file": _EMD, "pick": [4], "material": "blue_steel", "offset": EMD_HEAD},
    {"file": _EMD, "pick": [0], "material": "rust_orange", "offset": (0, 1.44 - 0.18, 0)},
    {"file": _EMD, "pick": [5], "material": "steel", "offset": (0, 0.12 - 0.18, 0), "node": "anim_spin_drill"},
    # The drive shaft between the auger and the motor (on the brim helpers' plate).
    {"file": "electric-mining-drill-add-brim.stl", "pick": [0], "material": "steel_dark", "offset": (0, 0.55 - 0.18, 0),
     "node": "anim_spin_drill"},
    # Arms: the upper arm (hose elbow at the crown) with the rack sliding out of it down to its
    # roller on the rail.
    {"file": _EMD, "pick": [2], "material": "blue_steel", "tilt": [("z", -50)], "offset": (0.52, 0.86 + 0.27, 0.12)},
    {"file": _EMD, "pick": [3], "material": "blue_steel", "tilt": [("z", 50)], "offset": (-0.52, 0.86 + 0.27, 0.12)},
    {"file": _EMD, "pick": [11], "material": "steel_dark", "tilt": [("z", -50)], "offset": (0.85, 0.46, 0.24)},
    {"file": _EMD, "pick": [10], "material": "steel_dark", "tilt": [("z", 50)], "offset": (-0.85, 0.46, 0.24)},
    {"file": _EMD, "pick": [14], "material": "hazard", "tilt": [("x", 90)], "offset": (-1.24, 0.16, -1.24)},
    {"file": _EMD, "pick": [15], "material": "hazard", "tilt": [("x", 90)], "offset": (1.24, 0.16, -1.24)},
    {"file": _EMD, "pick": [13], "material": "steel_light", "offset": (0.66, 0.3, -1.1)},
    {"file": _EMD, "pick": [12], "material": "steel_black", "offset": (1.26, 0.58, -1.03)},
]}
# --- Inserter arms: the arm and hand pieces of the inserters set -----------------------------
#
# Each print file is one inserter's arm laid flat on the plate, running +y from the base: a tab
# that plugs into the base, the upper arm (a fork at its shoulder end, a pin at its elbow end),
# the hand (a fork round that pin, then the forearm and the fingers or the claw). The client
# draws each piece itself (inserter_arms.gd), turning it about its joint, so every piece is
# exported with its joint at the origin (`pivot`, plate millimetres), lying flat and pointing
# north. Joints were read off the pieces' width profiles: shoulder fork and tab pin at y -11.9
# (-20.9 on the long arm), elbow pin at y 7.9. The arm's colour is `tier_paint`, recoloured per
# inserter by the client; fingers and claws are steel, as the sprites draw them. Basic arms are
# shared by the burner, yellow and fast inserters (their sprites differ only in colour).
# "High Precision" files: pieces of one plate are told apart by where they lie (`pick_box`).
INSERTERS = "Inserters High Precision"
_ARMS = {
    # family: (file stem, shoulder y, elbow y, upper-arm box, hand box, claw box or None)
    "basic": ("basic-inserter", -11.9, 7.9, (-41, -10, -35, 10.5), (-41, 5, -35, 24.5), (-45, 23.5, -31, 31)),
    "long": ("long-inserter", -20.9, 7.9, (-41, -15, -35, 10.5), (-41, 5, -35, 33.5), (-45, 32.5, -31, 40)),
    "bulk": ("bulk-inserter", -11.9, 7.9, (-41, -10, -35, 10.5), (-41, 4.5, -35, 15), (-50, 15, -26, 30)),
    "stack": ("stack-inserter", -11.9, 7.9, (-41, -10, -35, 10.5), (-42, 4.5, -34, 15), (-50, 15, -26, 30)),
}
# The basic and long hands are narrower than their sprites (hand-open.png, hand-closed.png at 128
# pixels a tile; Factorio stretches the arm's pictures only along their length): the forearm plate
# is 0.17 tiles wide in the sprite, 0.107 in the print; the crossbar with its fingers 0.55 open
# and 0.37 closed, 0.45 and 0.29 in the print. Widened to the sprite's: per band along the hand
# (z, placed: the crossbar ends at `bar`, the elbow fork starts at -0.19).
_HAND_WIDEN = {"basic": (-0.53, 1.59), "long": (-0.89, 1.59)}
_BAR_WIDEN = {"open": 1.23, "closed": 1.29}


def _hand_warp(bar, fore, cross):
    def warp(v):
        z, near = v[:, 2], np.abs(v[:, 0]) < 0.07
        k = np.where((z > bar - 0.01) & (z < -0.19) & near, fore, np.where(z < bar + 0.01, cross, 1.0))
        v[:, 0] *= k
        return v
    return warp


for _family, (_stem, _shoulder, _elbow, _upper, _hand, _claw) in _ARMS.items():
    RECIPES["inserter-arm-%s-upper" % _family] = {"budget": 700, "parts": [
        {"file": _stem + "-open.stl", "material": "tier_paint", "pick_box": _upper, "pivot": (-38.15, _shoulder)}]}
    for _state in ("open", "closed"):
        _parts = [
            {"file": "%s-%s.stl" % (_stem, _state), "material": "tier_paint", "pick_box": _hand, "pivot": (-38.15, _elbow)},
            {"file": "%s-%s.stl" % (_stem, _state), "material": "steel_light", "pick_box": _claw, "pivot": (-38.15, _elbow)},
        ]
        if _family in _HAND_WIDEN:
            for _p in _parts:
                _p["warp"] = _hand_warp(*_HAND_WIDEN[_family], _BAR_WIDEN[_state])
        RECIPES["inserter-arm-%s-hand-%s" % (_family, _state)] = {"budget": 1200, "parts": _parts}

# --- Walls: a piece per connection shape --------------------------------------------------------

# The walls set has one print per shape, already modelled round its tile's centre (`raw_frame`),
# with joining tabs reaching 0.2 tiles into the east and north neighbours: trimmed to the tile.
# Named by the sides each joins (north, east, south, west), as the client picks them
# (model_library.gd, WALL_SHAPES). An "ending" piece is named for the end it shows: ending-n
# joins only to the south.
WALL_PIECES = {
    "pylon": "walls-pylon.stl",
    "n": "walls-ending-s.stl", "e": "walls-ending-w.stl", "s": "walls-ending-n.stl", "w": "walls-ending-e.stl",
    "ns": "walls-straight-ns.stl", "ew": "walls-straight-we.stl",
    "ne": "walls-corner-ne.stl", "nw": "walls-corner-nw.stl", "es": "walls-corner-se.stl", "sw": "walls-corner-sw.stl",
    "new": "walls-t-junction-n.stl", "nes": "walls-t-junction-e.stl", "esw": "walls-t-junction-s.stl",
    "nsw": "walls-t-junction-w.stl", "nesw": "walls-x-junction.stl",
}


# The wall's cap and every upward face are pale, weathered concrete; its faces and buttresses are
# dark, streaked with grime (the sprites: their lit tops are three times as bright as their fronts).
def _wall_cap(c, n, lo, hi):
    return (n[:, 1] > 0.8) | (c[:, 1] > WALL_CAP)


WALL_CAP = 1.17
EXTRA_MATERIALS["concrete_wall_top"] = ("c4b9a3", 0.9, 0.0, None, 0)
_WALL_PAINT = [("concrete_wall_top", _wall_cap)]
for _shape, _file in WALL_PIECES.items():
    RECIPES["stone-wall-" + _shape] = {"parts": [
        {"file": _file, "material": "concrete_wall", "raw_frame": True, "trim": (0.5, 0.5), "paint": _WALL_PAINT}]}
# A 2x2 block of walls has a gap in its middle: the north-west wall of the block carries the
# fill-in piece on its south-east corner (the client adds bit 16, model_library.gd).
for _shape in ("es", "nes", "esw", "nesw"):
    RECIPES["stone-wall-%s-fill" % _shape] = {"parts": [
        {"file": WALL_PIECES[_shape], "material": "concrete_wall", "raw_frame": True, "trim": (0.5, 0.5), "paint": _WALL_PAINT},
        {"file": "walls-fill-in.stl", "material": "concrete_wall", "raw_frame": True, "offset": (0.5, 0, 0.5),
         "paint": _WALL_PAINT}]}
RECIPES["stone-wall"] = {"parts": [
    {"file": "walls-pylon.stl", "material": "concrete_wall", "raw_frame": True, "trim": (0.5, 0.5), "paint": _WALL_PAINT}]}

# --- Creatures (rigged for the client's animation, tools/models/wube_rig.py) -------------------
#
# Wube's biter, spitter, worm, spawner and character are statues, one pose per file. The walking
# pose is cut into a body and limbs (`rig`); the other poses are whole models the client swaps
# in (`-attack` while biting or spitting, `-corpse` where one died). Each is built at the big
# tier's size; small, medium and behemoth units are the same model scaled and tinted by the
# client, as Factorio does with one sprite sheet (creatures.gd). Their body was printed upside
# down (legs up) with the shell as a separate piece, fitted on by tools in art-src (a search for
# where the shell's underside groove hugs the body's spine), and the print faces south.

EXTRA_MATERIALS.update({
    # From the biter and spitter sprites: dark red flesh, pale tan legs; the carapace takes the
    # tier's colour (Factorio's mask1 tint), shown here for the big tier.
    "flesh_biter": ("7a3a30", 0.7, 0.0, None, 0),
    "flesh_leg": ("a8705a", 0.7, 0.0, None, 0),
    "chitin_big": ("5a5c86", 0.45, 0.1, None, 0),
    "chitin_spitter": ("4a6f86", 0.45, 0.1, None, 0),
    "flesh_spitter": ("6e4a40", 0.7, 0.0, None, 0),
    "flesh_worm": ("b8705a", 0.65, 0.0, None, 0),
    # The worm carved from its sprites (worm.py): the untinted ribbed belly and face, the horns.
    "belly_worm": ("c07a62", 0.6, 0.0, None, 0),
    "horn_worm": ("6e6460", 0.45, 0.05, None, 0),
    "mouth_worm": ("2a1416", 0.3, 0.0, None, 0),
    "flesh_spawner": ("a9705e", 0.7, 0.0, None, 0),
    "flesh_spawner_dome": ("c79a8e", 0.55, 0.0, None, 0),
    "stone_spawner_dirt": ("5e4a36", 0.95, 0.0, None, 0),
    "flesh_spawner_hollow": ("5a3350", 0.35, 0.0, None, 0),  # a dead spawner's caved-in middle
    "stone_worm_dirt": ("4a3828", 0.95, 0.0, None, 0),
    # The character's armour suit: dull orange-brown, as the level 1 sprite.
    "paint_character": ("8a6a4c", 0.6, 0.3, None, 0),
    "steel_pack": ("6a6660", 0.55, 0.6, None, 0),
})

# The print is about half the size of the big biter's sprite (its shell measured from Factorio's camera).
BITER_SCALE = 1.8
_BITER_RIG = {
    "material": "flesh_biter",
    # The thorax and abdomen under the shell, and the head; the six legs leave it at these hips.
    "core": [((0.0, 0.55, 0.05), (0.23, 0.3, 0.92)), ((0.0, 0.42, -0.7), (0.25, 0.32, 0.3))],
    "hips": {"leg_la": (-0.2, 0.5, -0.4), "leg_lb": (-0.2, 0.5, -0.12), "leg_lc": (-0.2, 0.5, 0.18),
             "leg_ra": (0.2, 0.5, -0.38), "leg_rb": (0.2, 0.5, -0.05), "leg_rc": (0.2, 0.5, 0.3)},
    "seeds": {"leg_la": (-0.42, -0.55), "leg_lb": (-0.52, -0.05), "leg_lc": (-0.3, 0.7),
              "leg_ra": (0.48, -0.36), "leg_rb": (0.55, 0.07), "leg_rc": (0.25, 0.7)},
    "materials": {"leg": "flesh_leg"}, "leg_swing": 16.0, "leg_lift": 14.0,
    # The print's legs are folded under the shell; the running sprite's are long and splayed, the
    # knees high beside the body and the feet a tile out, carrying the body a third of a tile
    # higher. New legs, measured against all 16 frames x 16 directions of the run by silhouette
    # overlap (tools/models/turntable_anim.py; wube_rig.long_legs).
    "long_legs": {"a": (0.46, 0.0, 0.28, 0.55, 0.3), "b": (0.71, 0.48, 0.32, 0.55, 0.0),
                  "c": (0.64, -0.46, 0.37, 0.75, -0.76)},
    # The middle legs stand nearly upright from the knee down: still swing them about the up axis
    # and lift them outwards, as the others.
    "swing": {"leg_lb": (0.0, 1.0, 0.0), "leg_rb": (0.0, 1.0, 0.0)},
    "lift": {"leg_lb": (0.0, 0.0, -1.0), "leg_rb": (0.0, 0.0, 1.0)},
    "long_legs_body": (1.0, 0.32), "long_legs_centre": (0.0, 0.9, -0.1), "leg_radius": (0.06, 0.05, 0.025),
}
RECIPES["big-biter"] = {
    "yaw": 180, "scale": BITER_SCALE, "rig": _BITER_RIG, "budget": 9000,
    "parts": [
        {"file": "biter-idle-body.stl", "material": "flesh_biter", "pick": [0], "tilt": [("z", 180)]},
        {"file": "biter-idle-shell.stl", "material": "chitin_big", "pick": [0], "tilt": [("x", 13)],
         "offset": (-0.04, 0.5656, 0.0482)},
    ],
}
# Wube also printed a biter attacking and dead and a spitter dead, but those statues don't take
# the sprites' poses (the dead biter is curled up at two thirds the size: IoU 0.33 against the
# corpse sprite; the attack keeps its legs folded, 0.50). The attack and corpse models are the
# walking model posed instead, on the client's own rig, fitted to the sprite's frame in every
# direction (creature_pose.py; the numbers in creature_poses.py). `"posed"` names the source,
# which must be built first.
RECIPES["big-biter-attack"] = {"posed": "big-biter", "parts": []}
RECIPES["big-biter-corpse"] = {"posed": "big-biter", "parts": []}
# Four corpses: Factorio's dying sheets take turns with four falls round the 16 directions.
for _v in (1, 2, 3):
    RECIPES["big-biter-corpse-%d" % _v] = {"posed": "big-biter", "parts": []}

# Spawners: Factorio draws both from one sprite sheet, the spitter's with a red mask tint
# (creature_models.gd tints the dome). The dome breathes: everything near its axis swells from
# the ground up, a little, about twice a second as the sprite's idle loop.
RECIPES["biter-spawner"] = {
    "budget": 12000, "scale": 0.8,
    # Factorio's spawner-idle: 7 frames forward-then-backward at 0.18 a tick, 12 steps = 0.9 s.
    "rig": {"mode": "idle", "rate": 0.9, "soft": (0.6, 2.2),
            "limbs": {"sac_dome": [(0.0, 0.0, 0.0), (0.0, 2.3, 0.0)]},
            "body": [[(3.3 * math.cos(a * math.pi / 4), 0.2, 3.3 * math.sin(a * math.pi / 4)) for a in range(9)]],
            "gait": {"sac_dome": (0.0, 0.0, 0.0, 0.045)},
            # The pale dome with its holes, and the dirt the spawner sits in (print frame, tiles).
            "zones": [("flesh_spawner_dome", ((0.0, 1.0, 0.0), (2.4, 1.3, 2.2))),
                      ("stone_spawner_dirt", ("below", 0.18))]},
    "parts": [{"file": "biter-spawner.stl", "material": "flesh_spawner", "pick": [0]}],
}

# The spawner's corpse (Factorio's spawner-death sheets): the same mound with its dome caved in,
# the hollow wet and dark purple inside the ring of tentacles. Wube printed no
# dead spawner; this is the print collapsed, fitted by eye and creature_score.py (0.85) to the
# last frame of the dying animation.
def _spawner_hollow(c, n, lo, hi):
    mid = (lo + hi) / 2
    return np.hypot(c[:, 0] - mid[0], c[:, 2] - mid[2]) < 0.2 * (hi[0] - lo[0])


def _spawner_dirt(c, n, lo, hi):
    return c[:, 1] < lo[1] + 0.08 * (hi[1] - lo[1])


RECIPES["biter-spawner-corpse"] = {
    "budget": 12000, "scale": (0.8, 0.55, 0.8), "crater": (1.9, 0.3),
    "parts": [{"file": "biter-spawner.stl", "material": "flesh_spawner", "pick": [0],
               "paint": [("stone_spawner_dirt", _spawner_dirt), ("flesh_spawner_hollow", _spawner_hollow)]}],
}

# Worms: Wube's printed worm is a slim column in a ring of spikes, and no refit of it reaches
# Factorio's fat, ribbed worm (0.59), so the worm is built from the sprites by worm.py (0.88);
# its corpse is that worm fallen over (creature_pose.py). Mode "worm" in creature_rigs.json (kept
# from the print's rig): the client bends it by position alone (folded into its hole, prepared and
# swaying, attacking), so it needs no limb data.
RECIPES["big-worm-turret"] = {"built_by": "worm", "parts": []}
RECIPES["big-worm-turret-corpse"] = {"posed": "big-worm-turret", "parts": []}

# The character (Wube's "player" set): the idle pose with its legs and arms rigged to swing as it
# walks, the stand-and-shoot pose while firing, and the dead pose. The print faces south; the
# backpack (with the pickaxe and tools the sprite shows) is a separate print laid out in front of
# its chest, turned round: it goes on the back (`spin`), lifted to the shoulders as the sprite has
# it. Painted as the level 1 sprite: the player's colour (orange) on the helmet, the jacket and the
# knee pads, a light grey collar, face guard, gloves and thighs, dark grey trousers and belt,
# black boots.
CHARACTER_SCALE = 1.0
EXTRA_MATERIALS.update({
    "paint_character": ("b86a2c", 0.6, 0.3, None, 0),
    "rubber_suit_dark": ("3c3c40", 0.8, 0.1, None, 0),
    "rubber_suit_grey": ("8e8e8a", 0.75, 0.1, None, 0),
    "rubber_boot": ("232325", 0.8, 0.1, None, 0),
    "steel_gun": ("74786e", 0.5, 0.6, None, 0),
})


def _character_paint(c, n, gun=False):
    """Material per face of a standing character (model frame: facing north, feet on the ground)."""
    x, y, z = c[:, 0], c[:, 1], c[:, 2]
    front = n[:, 2] < -0.3
    out = np.full(len(c), "paint_character", dtype=object)
    out[y < CHAR_HIP] = "rubber_suit_dark"
    out[(y < CHAR_HIP) & (y >= CHAR_KNEE[1]) & front] = "rubber_suit_grey"
    out[(y < CHAR_KNEE[1]) & (y >= CHAR_KNEE[0]) & front] = "paint_character"
    out[y < CHAR_ANKLE] = "rubber_boot"
    out[(y >= CHAR_HIP) & (y < CHAR_BELT)] = "rubber_suit_dark"
    if not gun:
        out[(y >= CHAR_HIP) & (y < CHAR_CUFF) & (np.abs(x) > CHAR_ARM_X)] = "rubber_suit_grey"
    out[(y >= CHAR_COLLAR[0]) & (y < CHAR_COLLAR[1])] = "rubber_suit_grey"
    out[(y >= CHAR_COLLAR[1]) & (y < CHAR_VISOR) & (n[:, 2] < -0.5)] = "rubber_suit_grey"
    if gun:  # the gun, held out in front of the chest, and the hands on it
        out[(z < CHAR_GUN_Z) & (y > CHAR_BELT)] = "steel_gun"
    return out


CHAR_ANKLE, CHAR_KNEE, CHAR_HIP, CHAR_BELT, CHAR_CUFF = 0.2, (0.4, 0.55), 0.8, 0.9, 1.1
CHAR_ARM_X, CHAR_COLLAR, CHAR_VISOR, CHAR_GUN_Z = 0.22, (1.42, 1.52), 1.68, -0.22
_CHAR_ZONES = [(m, ("rule", (lambda c, n, m=m: _character_paint(c, n) == m)))
               for m in ("rubber_suit_dark", "rubber_suit_grey", "rubber_boot")]
_CHAR_PAINT = [(m, (lambda c, n, lo, hi, m=m: _character_paint(c, n, gun=True) == m))
               for m in ("rubber_suit_dark", "rubber_suit_grey", "rubber_boot", "steel_gun")]
# The print's backpack is bigger than the sprite's (about 0.9 wide with its tools and 0.55 deep,
# measured against the running sprites by tools/models/turntable_anim.py): shrunk to 0.7.
_PACK = {"material": "steel_pack", "pick": [0], "with_part": 0, "spin": 180, "offset": (0.0, 0.6, -0.12),
         "resize": 0.7}
def _smooth(e0, e1, t):
    t = np.clip((t - e0) / (e1 - e0), 0.0, 1.0)
    return t * t * (3 - 2 * t)


def _character_penalty(v):
    """The print's arms hang free of the body from the elbow up but their hands rest on the hips:
    below the shoulders, arm bones stay off the middle and the body's bones off the arms."""
    ax, y = np.abs(v[:, 0]), v[:, 1]
    below = 1.0 - _smooth(1.28, 1.38, y)
    arm_off = 3.0 * _smooth(0.21, 0.17, ax) * below
    body_off = 3.0 * _smooth(0.2, 0.24, ax) * below * _smooth(0.6, 0.68, y)
    out = {n: arm_off for n in ("upper_arm_r", "forearm_r", "upper_arm_l", "forearm_l")}
    out.update({n: body_off for n in ("root", "spine", "thigh_r", "shin_r", "thigh_l", "shin_l")})
    # The legs stand apart below the crotch (the boots nearly touch): each keeps to its side.
    low = 1.0 - _smooth(0.6, 0.7, y)
    x = v[:, 0]
    for n in ("thigh_l", "shin_l"):
        out[n] = out[n] + 3.0 * _smooth(-0.035, -0.005, x) * low
    for n in ("thigh_r", "shin_r"):
        out[n] = out[n] + 3.0 * _smooth(-0.005, -0.035, x) * low
    return out


# The character faces north (-z); its right is +x. Joints measured on the print (sections through
# the body: arms free of it between 0.85 and 1.3, hands on the hips).
_CHAR_BONES = [
    ("root", None, (0.0, 0.84, 0.0), (0.0, 0.92, 0.0), (0.17, 0.12, 0.15)),
    ("spine", "root", (0.0, 0.95, 0.0), (0.0, 1.38, 0.0), (0.2, 0.2, 0.16)),
    ("head", "spine", (0.0, 1.47, 0.0), (0.0, 1.72, 0.03), 0.13),
    ("upper_arm_r", "spine", (0.22, 1.36, 0.05), (0.25, 1.07, 0.07), 0.08),
    ("forearm_r", "upper_arm_r", (0.25, 1.07, 0.07), (0.26, 0.74, -0.03), 0.08),
    ("upper_arm_l", "spine", (-0.23, 1.36, 0.05), (-0.26, 1.07, 0.07), 0.08),
    ("forearm_l", "upper_arm_l", (-0.26, 1.07, 0.07), (-0.27, 0.74, -0.05), 0.08),
    ("thigh_r", "root", (0.12, 0.82, 0.0), (0.13, 0.47, -0.02), 0.1),
    ("shin_r", "thigh_r", (0.13, 0.47, -0.02), (0.11, 0.08, -0.06), 0.1),
    ("thigh_l", "root", (-0.15, 0.82, 0.0), (-0.17, 0.47, -0.02), 0.1),
    ("shin_l", "thigh_l", (-0.17, 0.47, -0.02), (-0.14, 0.08, -0.06), 0.1),
]
RECIPES["character"] = {
    "yaw": 180, "scale": CHARACTER_SCALE, "budget": 9000,
    "skin": {"material": "paint_character", "zones": _CHAR_ZONES, "bones": _CHAR_BONES,
             "fixed": {"steel_pack": "spine"}, "penalty": _character_penalty, "band": 1.0,
             # The hands rest on the hips and the elbows touch the chest: cut them free (below the
             # shoulders only).
             "separate": [((("root", "spine", "thigh_r", "thigh_l", "shin_r", "shin_l"),
                            ("upper_arm_r", "forearm_r", "upper_arm_l", "forearm_l")),
                           lambda c: c[:, 1] < 1.26)]},
    "parts": [{"file": "player-idle-body.stl", "material": "paint_character", "pick": [0]},
              dict(_PACK, file="player-idle-backpack.stl")],
}
# Armour looks (armour_looks.py): the character with the add-on layer Factorio draws over it in
# heavy or modular armour (level 2) and in power armour MK1 or MK2 (level 3), on the same skeleton.
# The body keeps a little less of its budget: the plates cover part of it.
import armour_looks  # noqa: E402
EXTRA_MATERIALS.update(armour_looks.MATERIALS)
for _level, _pieces in ((2, armour_looks.level2), (3, armour_looks.level3)):
    RECIPES["character-armor-%d" % _level] = dict(RECIPES["character"], budget=7400,
                                                   skin=dict(RECIPES["character"]["skin"], armour=_pieces))
RECIPES["character-gun"] = {
    "yaw": 180, "scale": CHARACTER_SCALE, "budget": 8700,
    "parts": [{"file": "player-stand-gun-body.stl", "material": "paint_character", "pick": [0], "paint": _CHAR_PAINT},
              dict(_PACK, file="player-stand-gun-backpack.stl", offset=(0.0, 0.55, 0.42))],
}


def _corpse_paint(c, n, lo=None, hi=None):
    """The dead character lies on its back: the standing character's bands measured along its
    length from the feet (`_character_paint`), faces looking up for its front; its arm flung out
    to the east and the hand on its belly are gloved."""
    xz = c[:, [0, 2]]
    centre = xz.mean(axis=0)
    _w, vecs = np.linalg.eigh(np.cov((xz - centre).T))
    head = vecs[:, -1] * np.sign(vecs[:, -1] @ CORPSE_HEAD)
    t = (xz - centre) @ head
    east = (xz - centre) @ np.array([-head[1], head[0]])
    height = (t - t.min()) * 1.8 / max(t.max() - t.min(), 1e-6)  # as if standing, 1.8 tall
    standing = np.column_stack([np.zeros(len(c)), height, -n[:, 1]])  # (x, y, z) for the rules
    up = np.column_stack([n[:, 0], n[:, 2], -n[:, 1]])  # looking up = looking north when standing
    out = _character_paint(standing, up)
    arms = (height > CHAR_BELT) & (height < CHAR_COLLAR[0])
    out[arms & (((np.abs(east) > CORPSE_ARM) & (height < CHAR_CUFF + 0.1)) | (east > CORPSE_GLOVE))] = "rubber_suit_grey"
    return out


# Lying as its sprite: head to the north-east, the flung arm reaching south (yaw -57).
CORPSE_HEAD, CORPSE_ARM, CORPSE_GLOVE = np.array([0.67, -0.74]), 0.28, 0.5
RECIPES["character-corpse"] = {
    "yaw": -57, "scale": CHARACTER_SCALE, "budget": 7000,
    "parts": [{"file": "player-dead.stl", "material": "paint_character", "pick": [0],
               "paint": [(m, (lambda c, n, lo, hi, m=m: _corpse_paint(c, n) == m))
                         for m in ("rubber_suit_dark", "rubber_suit_grey", "rubber_boot")]}],
}

# Spitters: the same build as the biters, a body printed legs-up and its segmented shell (fitted
# on by the same search, turned 10 degrees along the body). Many short legs, found automatically.
# The print is a little over half the size of the big spitter's sprite (compare.py).
SPITTER_SCALE = 1.8
_SPITTER_RIG = {
    "material": "flesh_spitter",
    "core": [((0.0, 0.5, 0.0), (0.3, 0.32, 0.85))],
    "reach": 0.2, "min_faces": 40, "max_faces": 400, "ground": 1.0, "per_side": 6, "materials": {"leg": "flesh_leg"}, "leg_swing": 18.0, "leg_lift": 16.0,
}
RECIPES["big-spitter"] = {
    "yaw": -90, "scale": SPITTER_SCALE, "rig": _SPITTER_RIG, "budget": 9000,
    "parts": [
        {"file": "spitter-walk-body.stl", "material": "flesh_spitter", "pick": [0], "tilt": [("z", 180)]},
        {"file": "spitter-walk-shell.stl", "material": "chitin_spitter", "pick": [0], "tilt": [("z", 10)],
         "offset": (0.0, 0.522, 0.0)},
    ],
}
# Posed from the walking spitter, as the biter's (above): the corpse, and the attack at the top of
# its rear, which Wube didn't print.
RECIPES["big-spitter-attack"] = {"posed": "big-spitter", "parts": []}
RECIPES["big-spitter-corpse"] = {"posed": "big-spitter", "parts": []}
for _v in (1, 2, 3):
    RECIPES["big-spitter-corpse-%d" % _v] = {"posed": "big-spitter", "parts": []}
