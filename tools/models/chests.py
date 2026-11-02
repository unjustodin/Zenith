"""Chests, matched to Factorio's sprites. They can't be rotated, so like the sprites their front
(the steel chest's latch) faces south, towards the default camera."""

from kit import Part, R, model

W = 0.80  # footprint of the box, leaving a gap between neighbouring chests


def framed_face(p, half, z0, z1, mat_frame, mat_panel, frame=0.08, depth=0.03, slats=0, slat_mat=None,
                vertical=False):
    """The four side faces of a box: a frame round each face, the panel set back inside it, and
    optional slats across the panel."""
    for rot in (0, 90, 180, 270):
        m = R("Z", rot)
        p.slab(-half, -half, z0, half, -half + depth, z0 + frame, mat_frame, matrix=m)
        p.slab(-half, -half, z1 - frame, half, -half + depth, z1, mat_frame, matrix=m)
        p.slab(-half, -half, z0, -half + frame, -half + depth, z1, mat_frame, matrix=m)
        p.slab(half - frame, -half, z0, half, -half + depth, z1, mat_frame, matrix=m)
        p.slab(-half + frame, -half + depth * 0.6, z0 + frame, half - frame, -half + depth, z1 - frame, mat_panel,
               matrix=m)
        for i in range(slats):
            if vertical:
                w = (2 * half - 2 * frame) / slats
                x0 = -half + frame + i * w
                p.slab(x0 + 0.012, -half + depth * 0.4, z0 + frame, x0 + w - 0.012, -half + depth * 0.9, z1 - frame,
                       slat_mat or mat_panel, matrix=m)
            else:
                hgt = (z1 - z0 - 2 * frame) / slats
                zz = z0 + frame + i * hgt
                p.slab(-half + frame, -half + depth * 0.4, zz + 0.01, half - frame, -half + depth * 0.9, zz + hgt - 0.01,
                       slat_mat or mat_panel, matrix=m)


@model("wooden-chest")
def wooden_chest():
    """A crate: light boards framing every face, darker planks set inside."""
    p = Part()
    h = W / 2
    top = 0.62
    p.slab(-h + 0.03, -h + 0.03, 0.0, h - 0.03, h - 0.03, top, "wood_dark")
    framed_face(p, h, 0.0, top, "wood_light", "wood_dark", frame=0.09, depth=0.04, slats=3, slat_mat="wood")
    # Lid: a frame of boards round four planks running east-west.
    p.slab(-h, -h, top, h, h, top + 0.03, "wood_dark")
    for x0, y0, x1, y1 in ((-h, -h, h, -h + 0.1), (-h, h - 0.1, h, h), (-h, -h, -h + 0.1, h), (h - 0.1, -h, h, h)):
        p.slab(x0, y0, top + 0.03, x1, y1, top + 0.1, "wood_light", bevel=0.01)
    for i in range(4):
        y0 = -h + 0.1 + i * (W - 0.2) / 4
        p.slab(-h + 0.1, y0 + 0.01, top + 0.03, h - 0.1, y0 + (W - 0.2) / 4 - 0.01, top + 0.075, "wood", bevel=0.006)
    return p


@model("iron-chest")
def iron_chest():
    """A rusty iron box: a raised lid frame with a handle, riveted bands round the sides."""
    p = Part()
    h = W / 2
    top = 0.62
    p.box((0, 0, top / 2), (W - 0.02, W - 0.02, top), "iron_rust", bevel=0.02)
    for z in (0.06, top - 0.08):
        p.slab(-h, -h, z - 0.05, h, h, z + 0.05, "steel_dark", bevel=0.01)
        for rot in (0, 90, 180, 270):
            for x in (-0.3, -0.15, 0.0, 0.15, 0.3):
                p.cyl((x, -h - 0.005, z), 0.018, 0.012, "steel_light", segs=6, axis="Y", matrix=R("Z", rot))
    # Lid: a light raised frame round a rusty panel, and a handle.
    p.slab(-h, -h, top, h, h, top + 0.04, "steel_dark", bevel=0.01)
    for x0, y0, x1, y1 in ((-h, -h, h, -h + 0.07), (-h, h - 0.07, h, h), (-h, -h, -h + 0.07, h), (h - 0.07, -h, h, h)):
        p.slab(x0, y0, top + 0.04, x1, y1, top + 0.09, "steel", bevel=0.01)
    p.slab(-h + 0.07, -h + 0.07, top + 0.04, h - 0.07, h - 0.07, top + 0.06, "iron_rust")
    p.slab(-0.12, -0.12, top + 0.06, 0.12, -0.05, top + 0.08, "steel_dark")
    for x in (-0.1, 0.1):
        p.slab(x - 0.02, -0.11, top + 0.06, x + 0.02, -0.07, top + 0.15, "steel_light")
    p.slab(-0.1, -0.11, top + 0.13, 0.1, -0.07, top + 0.16, "steel_light")
    return p


@model("steel-chest")
def steel_chest():
    """Steel: a heavy frame with corner brackets, ribbed panels, a corrugated lid, a latch."""
    p = Part()
    h = W / 2 + 0.02
    top = 0.64
    p.slab(-h + 0.03, -h + 0.03, 0.0, h - 0.03, h - 0.03, top, "steel_dark")
    framed_face(p, h, 0.0, top, "steel", "steel_dark", frame=0.07, depth=0.04, slats=6, slat_mat="paint_grey",
                vertical=True)
    for sx in (-1, 1):
        for sy in (-1, 1):
            for z0, z1 in ((0.0, 0.14), (top - 0.12, top + 0.02)):
                p.slab(sx * (h + 0.01), sy * (h + 0.01), z0, sx * (h - 0.12), sy * (h - 0.12), z1, "steel_light",
                       bevel=0.012)
    p.slab(-h, -h, top, h, h, top + 0.03, "steel")
    for i in range(6):
        x = -h + 0.1 + i * (2 * h - 0.2) / 5
        p.cyl((x, 0, top + 0.03), 0.04, 2 * h - 0.14, "steel", segs=6, axis="Y")
    # Latch at the top of the front.
    p.slab(-0.1, -h - 0.03, top - 0.2, 0.1, -h, top - 0.08, "brass", bevel=0.008)
    p.slab(-0.06, -h - 0.04, top - 0.17, 0.06, -h - 0.02, top - 0.11, "steel_black")
    return p
