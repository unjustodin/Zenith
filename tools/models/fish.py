"""Fish: Factorio draws each as one of two still pictures (base/graphics/entity/fish): a soft
black oval at a third opacity (alpha 0.36) lying in the water, about 8 by 13 pixels where it is
at least half as dark as its middle (0.25 tiles wide, 0.41 high on screen), with no fins or tail
to be seen. Here: a flat dark fish, see-through like the pictures, lying in the water's surface
(the client's water is 0.2 under the ground, terrain_mesher.gd WATER_Y; its lower half is under
the opaque water), head north as the pictures stand. A body 0.44 long and 0.23 wide narrowing
to the tail, small pectoral fins and a forked tail fin (`anim_tail_fish`, swayed
gently by the client: model_library.gd CYCLES). Factorio's fish don't move; the sway is ours."""

from kit import ALPHA, MATERIALS, Part, model

MATERIALS.setdefault("fish_scales", ("141c1b", 0.35, 0.0, None, 0))
ALPHA.setdefault("fish_scales", 0.6)

WATER = -0.2  # the client's water surface (terrain_mesher.gd WATER_Y)
FIN = 0.012  # the fins' thickness
MID, HALF_LEN, HALF_W, HALF_H = 0.02, 0.22, 0.115, 0.04  # the body's ellipsoid (north is +y)
TAIL_ROOT = MID - HALF_LEN  # the body's tail end, where the tail fin turns


def _taper(co):
    """A spindle: a blunt snout, widest a little ahead of the middle, narrowing and flattening to
    the tail."""
    t = max(0.0, (MID - co.y) / HALF_LEN)  # 0 at the middle, 1 at the tail end
    h = max(0.0, (co.y - MID) / HALF_LEN)  # 0 at the middle, 1 at the snout
    k = t ** 1.6
    return (co.x * (1.0 - 0.5 * k) * (1.0 - 0.15 * h * h), co.y,
            WATER + (co.z - WATER) * (1.0 - 0.4 * k))


@model("fish")
def fish():
    body = Part()
    body.sphere((0.0, MID, WATER), 1.0, "fish_scales", segs=16, rings=8, scale=(HALF_W, HALF_LEN, HALF_H))
    body.warp(_taper)
    # Pectoral fins just behind the head, swept back, flat in the water. They start at the body's
    # edge: see-through pieces drawn over each other show as darker patches.
    for side in (1, -1):
        pts = [(side * 0.108, 0.06), (side * 0.145, -0.02), (side * 0.11, -0.005)]
        if side > 0:
            pts.reverse()
        body.prism(pts, WATER - FIN / 2, WATER + FIN / 2, "fish_scales")
    tail = Part("anim_tail_fish", pivot=(0.0, TAIL_ROOT, WATER))
    tail.prism([(0.0, TAIL_ROOT + 0.005), (-0.075, TAIL_ROOT - 0.085), (0.0, TAIL_ROOT - 0.055),
                (0.075, TAIL_ROOT - 0.085)], WATER - FIN / 2, WATER + FIN / 2, "fish_scales")
    return [body, tail]
