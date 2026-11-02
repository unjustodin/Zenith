"""Armour looks: the character as Factorio draws it in each armour (entities.lua's character
animations). Light armour keeps the plain look; heavy and modular armour draw the level 2 add-on
layer over the plain character, power armour MK1 and MK2 the level 3 one (and Space Age's mech
armour is a model of its own, mech_armor.py). Modelled from the add-ons' idle frames in all eight
directions and checked against their running frames:

- level 2: an orange shell over the helmet with a dark visor slot, round orange shoulder pads, a
  grey breastplate crossed by two orange bands, an orange belt, padded orange thighs, orange cuffs
  on the forearms and shins;
- level 3: a bigger domed helmet with a dark face opening and a grey crest, orange shoulder pads
  on grey rims, an orange collar over a dark grey chest, an orange shell of three ribs over the
  whole back, an orange waist band, armoured grey arms and legs with orange knee caps.

Each piece is a closed superquadric that follows one bone of the character's skeleton rigidly
(wube_rig.build_skinned adds them to the converted body), so the looks share the character's rig
and character_anim.gd's animations. Plain Python: numpy and trimesh.
"""

import math

import numpy as np
import trimesh

PAINT, PLATE, DARK, VISOR = "armour_paint", "armour_plate", "armour_dark", "armour_visor"
MATERIALS = {
    # The add-ons' mask takes the player's colour (Factorio's default orange); the metal is the
    # sprites' cool grey, the joints and the lower chest a darker grey.
    PAINT: ("c0712c", 0.55, 0.3, None, 0),
    PLATE: ("8c8e8c", 0.5, 0.55, None, 0),
    DARK: ("4a4b4e", 0.6, 0.45, None, 0),
    VISOR: ("18191b", 0.3, 0.2, None, 0),
}


def superquadric(centre, radii, e1=1.0, e2=1.0, segs=12, rings=8, basis=None):
    """A closed superquadric: `e1` squares it off up and down (1 round, small boxy), `e2` around.
    `basis` (3x3, columns are the shape's x, y, z) turns it."""
    def spow(c, e):
        return np.sign(c) * np.abs(c) ** e

    verts = [(0.0, -1.0, 0.0)]
    for k in range(1, rings):
        v = -math.pi / 2 + math.pi * k / rings
        for i in range(segs):
            u = 2 * math.pi * i / segs
            cv = spow(math.cos(v), e1)
            verts.append((cv * spow(math.cos(u), e2), spow(math.sin(v), e1), cv * spow(math.sin(u), e2)))
    verts.append((0.0, 1.0, 0.0))
    faces = []
    top = len(verts) - 1
    for i in range(segs):
        j = (i + 1) % segs
        faces.append((0, 1 + i, 1 + j))
        base = 1 + (rings - 2) * segs
        faces.append((top, base + j, base + i))
    for k in range(rings - 2):
        a, b = 1 + k * segs, 1 + (k + 1) * segs
        for i in range(segs):
            j = (i + 1) % segs
            faces.append((a + i, b + i, b + j))
            faces.append((a + i, b + j, a + j))
    v = np.asarray(verts) * np.asarray(radii, dtype=float)
    if basis is not None:
        v = v @ np.asarray(basis, dtype=float).T
    mesh = trimesh.Trimesh(v + np.asarray(centre, dtype=float), np.asarray(faces), process=False)
    if mesh.volume < 0:
        mesh.invert()
    return mesh


def along(direction, forward=(0.0, 0.0, -1.0)):
    """A basis whose y runs along `direction` (a limb), z as close to `forward` as it can."""
    y = np.asarray(direction, dtype=float)
    y = y / np.linalg.norm(y)
    z = np.asarray(forward, dtype=float)
    z = z - y * (z @ y)
    z = z / np.linalg.norm(z)
    return np.column_stack([np.cross(y, z), y, z])


class Look:
    """Pieces for one look: (material, mesh, bone)."""

    def __init__(self, bones):
        self.bones = {b[0]: (np.asarray(b[2], dtype=float), np.asarray(b[3], dtype=float)) for b in bones}
        self.pieces = []

    def at(self, bone, t, offset=(0.0, 0.0, 0.0)):
        """A point `t` of the way down `bone`, moved by `offset` (x mirrored on the left side)."""
        head, tail = self.bones[bone]
        off = np.asarray(offset, dtype=float).copy()
        if bone.endswith("_l"):
            off[0] = -off[0]
        return head + (tail - head) * t + off

    def limb(self, bone):
        head, tail = self.bones[bone]
        return along(tail - head)

    def add(self, material, bone, centre, radii, **kw):
        self.pieces.append((material, superquadric(centre, radii, **kw), bone))

    def both(self, material, bone, t, offset, radii, on_limb=False, **kw):
        """The same piece on the right and left limb."""
        for side in ("_r", "_l"):
            b = bone + side
            if on_limb:
                kw["basis"] = self.limb(b)
            self.add(material, b, self.at(b, t, offset), radii, **kw)


# The head as converted (character.glb): centred at x -0.02, z 0.06 (the helmet runs back), from
# 1.5 to 1.8 up; the face's front at z -0.07. The chest's front is at z -0.17 to -0.19 between
# 1.0 and 1.2, the back at 0.15; the pack fills x -0.18..0.2, z 0.11..0.49 from 1.1 to 1.8.
HEAD = (-0.02, 1.645, 0.055)


def level2(bones):
    """Heavy and modular armour (level2addon)."""
    k = Look(bones)
    hx, hy, hz = HEAD
    # Helmet: an orange shell over the plain helmet, a squared face plate with a dark visor slot.
    k.add(PAINT, "head", (hx, hy + 0.045, hz - 0.02), (0.13, 0.15, 0.14), e1=0.8, e2=0.9)
    k.add(PAINT, "head", (hx, hy + 0.01, -0.07), (0.11, 0.1, 0.05), e1=0.4, e2=0.5, segs=10, rings=6)
    k.add(VISOR, "head", (hx, hy + 0.03, -0.115), (0.08, 0.018, 0.025), e1=0.3, e2=0.5, segs=8, rings=4)
    # Round shoulder pads.
    k.both(PAINT, "upper_arm", 0.0, (0.03, 0.06, -0.02), (0.11, 0.08, 0.12), e1=0.7, e2=0.9)
    # The breastplate: grey, over the chest's front, two orange bands across it.
    k.add(PLATE, "spine", (-0.01, 1.23, -0.06), (0.2, 0.18, 0.125), e1=0.45, e2=0.75, segs=14)
    for y in (1.31, 1.15):
        k.add(PAINT, "spine", (-0.01, y, -0.07), (0.205, 0.028, 0.13), e1=0.25, e2=0.75, segs=14, rings=4)
    # Belt round the waist.
    k.add(PAINT, "root", (-0.015, 0.94, -0.01), (0.24, 0.055, 0.175), e1=0.3, e2=0.8, segs=14, rings=4)
    # Padded thighs: orange guards on the front and outside of each thigh.
    k.both(PAINT, "thigh", 0.3, (0.012, 0.0, -0.045), (0.11, 0.16, 0.09), on_limb=True, e1=0.5, e2=0.75)
    # Cuffs on the forearms and the shins.
    k.both(PAINT, "forearm", 0.32, (0.0, 0.0, 0.0), (0.085, 0.045, 0.085), on_limb=True, e1=0.25, e2=1.0, rings=4)
    k.both(PAINT, "shin", 0.38, (0.0, 0.0, 0.0), (0.098, 0.045, 0.098), on_limb=True, e1=0.25, e2=1.0, rings=4)
    return k.pieces


def level3(bones):
    """Power armour MK1 and MK2 (level3addon)."""
    k = Look(bones)
    hx, hy, hz = HEAD
    # Helmet: a big orange dome, a dark face opening, a grey crest along the top.
    k.add(PAINT, "head", (hx, hy + 0.06, hz), (0.16, 0.17, 0.175), e1=0.85, e2=0.9, segs=14, rings=10)
    k.add(VISOR, "head", (hx, hy + 0.005, -0.1), (0.07, 0.055, 0.045), e1=0.5, e2=0.6, segs=10, rings=6)
    k.add(PLATE, "head", (hx, hy + 0.22, hz + 0.01), (0.028, 0.03, 0.14), e1=0.6, e2=0.6, segs=8, rings=6)
    # Orange shoulder pads on grey rims, and an orange collar across the upper chest.
    k.both(PAINT, "upper_arm", 0.0, (0.04, 0.07, -0.005), (0.125, 0.1, 0.13), e1=0.75, e2=0.9, segs=14)
    k.both(PLATE, "upper_arm", 0.12, (0.045, 0.0, -0.005), (0.115, 0.03, 0.125), e1=0.35, e2=0.9, segs=14, rings=4)
    k.add(PAINT, "spine", (-0.01, 1.41, -0.04), (0.2, 0.08, 0.15), e1=0.5, e2=0.8, segs=14, rings=6)
    # Chest: dark grey plating over the torso's front and sides.
    k.add(DARK, "spine", (-0.01, 1.16, -0.04), (0.23, 0.2, 0.15), e1=0.5, e2=0.65, segs=14)
    # The shell over the backpack: three orange ribs from the shoulders to the hips, as wide as
    # the shoulders.
    for y, r in ((1.42, (0.24, 0.12, 0.19)), (1.24, (0.27, 0.13, 0.21)), (1.05, (0.24, 0.11, 0.185))):
        k.add(PAINT, "spine", (0.0, y, 0.25), r, e1=0.6, e2=0.85, segs=16, rings=8)
    # Orange band round the waist.
    k.add(PAINT, "root", (-0.015, 0.92, -0.005), (0.245, 0.07, 0.175), e1=0.35, e2=0.8, segs=14, rings=4)
    # Arms: grey upper arms and silver gauntlets.
    k.both(DARK, "upper_arm", 0.6, (0.005, 0.0, 0.0), (0.072, 0.12, 0.072), on_limb=True, e1=0.6, e2=1.0)
    k.both(PLATE, "forearm", 0.45, (0.0, 0.0, 0.0), (0.082, 0.16, 0.082), on_limb=True, e1=0.55, e2=0.9)
    # Legs: silver thigh and shin plates, orange knee caps.
    k.both(PLATE, "thigh", 0.4, (0.005, 0.0, -0.01), (0.1, 0.16, 0.095), on_limb=True, e1=0.55, e2=0.85)
    k.both(PAINT, "shin", 0.0, (0.0, 0.0, -0.095), (0.07, 0.06, 0.05), on_limb=True, e1=0.7, e2=0.8, segs=10, rings=6)
    k.both(PLATE, "shin", 0.45, (0.0, 0.0, -0.01), (0.095, 0.15, 0.095), on_limb=True, e1=0.55, e2=0.85)
    return k.pieces
