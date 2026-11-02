"""Models drawn with one model per direction (client/scripts/world/model_library.gd FACING_MODELS):
Factorio renders each direction of some entities on its own, and the renders don't agree with
one turned model (the boiler, steam engine and offshore pump). Each variant here is the north
model's named groups of parts, each group moved and scaled to fit that direction's picture
(scaled about the middle of its bottom, so grounded groups stay on the ground), the whole
stretched, then turned to face its way. The client draws the variant unturned.

The fits are found against the sprites' silhouettes with grouped exports of the north model
(`F3D_GROUPS=1` makes `variant` return the groups unfitted and unturned, one node per group,
for a fitting script) and kept here as numbers, so a build needs no sprites.
"""

import os

from mathutils import Vector

from kit import Part, R, S, T

SUFFIXES = ("", "-east", "-south", "-west")
GROUPED = bool(os.environ.get("F3D_GROUPS"))


def _bottom_centre(part):
    """The middle of the part's bounding box's bottom face."""
    vs = [v.co for v in part.bm.verts]
    if not vs:
        return Vector((0, 0, 0))
    lo = Vector((min(v.x for v in vs), min(v.y for v in vs), min(v.z for v in vs)))
    hi = Vector((max(v.x for v in vs), max(v.y for v in vs), max(v.z for v in vs)))
    return Vector(((lo.x + hi.x) / 2, (lo.y + hi.y) / 2, lo.z))


def _move(part, matrix):
    part.transform(matrix)
    part.pivot = matrix @ part.pivot


def variant(groups, facing, fit=None, scale=(1.0, 1.0, 1.0), anims=None):
    """The model facing `facing` (quarter turns clockwise from north).

    groups: {name: Part} of static geometry facing north. anims: {group name: [anim Parts]}
    that move with that group. fit: {name: (dx, dy, dz, sx, sy, sz)}: the group scaled about the
    middle of its bounding box's bottom, then moved (tiles; x east, y north, z up). scale: the
    whole model stretched about its origin before it is turned. Returns [body, anim parts...]."""
    anims = anims or {}
    if GROUPED:
        out = []
        for name, part in groups.items():
            part.name = "g_" + name
            out.append(part)
            for k, a in enumerate(anims.get(name, [])):
                g = Part("g_%s~%d" % (name, k))  # (an anim part's bmesh is in model space)
                g.add_part(a)
                out.append(g)
        return out
    fit = fit or {}
    whole = R("Z", -90 * facing) @ S(*scale)
    body = Part()
    moving = []
    for name, part in groups.items():
        dx, dy, dz, sx, sy, sz = fit.get(name, (0, 0, 0, 1, 1, 1))
        c = _bottom_centre(part)
        # Nothing is pushed into the ground: a group moved below it stands on it instead.
        dz = max(dz, -c.z)
        m = whole @ T(c.x + dx, c.y + dy, c.z + dz) @ S(sx, sy, sz) @ T(-c.x, -c.y, -c.z)
        body.add_part(part, m)
        for a in anims.get(name, []):
            _move(a, m)
            moving.append(a)
    return [body] + moving
