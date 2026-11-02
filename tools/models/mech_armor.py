"""The character in mech armour (Space Age): Factorio draws a character wearing `mech-armor` with
its own sprites (space-age/graphics/entity/mech-armor/, mech-armor-animations.lua), a walking
suit about one and a half times the plain character's height. Modelled from mech-idle's frames
(all eight directions) and checked against mech-run's: an egg-shaped cockpit pod with a hood
over its front, two thruster nozzles on a pack behind it, broad shoulders, the right forearm a
perforated gun held out in front, the left a claw hanging forward, and thick armoured legs.
The mask layer (the player's colour) covers the hood, the lower front panel, the back plates
under the nozzles, the claw's fingers and the gun's shoulder: `mech_paint`.

It is skinned to the character's skeleton (the same bone names, so character_anim.gd's poses
drive it), placed at the mech's joints, with the same encoding as wube_rig.py's skinned rigs
(TEXCOORD_0: bone a + 16 * bone b, a's weight). Armour plates follow one bone rigidly, as a
machine's would; only the joints' fillers blend between bones (wube_rig.skin_weights).
"""

import math

import bmesh
import numpy as np
from mathutils import Vector

import kit
import wube_rig
from kit import Part, model

# The sprite's metal: rusty brown armour, darker joints, black in the nozzles and the visor.
kit.MATERIALS.setdefault("mech_armor", ("6d5040", 0.6, 0.7, None, 0))
kit.MATERIALS.setdefault("mech_joint", ("4a3b33", 0.6, 0.75, None, 0))
kit.MATERIALS.setdefault("mech_light", ("9a8576", 0.5, 0.75, None, 0))
kit.MATERIALS.setdefault("mech_dark", ("221c19", 0.7, 0.6, None, 0))
# The mask layer, as part_colors.py samples it with Factorio's default player colour on.
kit.MATERIALS.setdefault("mech_paint", ("b9875a", 0.55, 0.5, None, 0))

# Bones as the character's (wube_recipes._CHAR_BONES), at the mech's joints: (name, parent,
# head, tail, radius), given here in Blender's frame (x east, y north = forward, z up) and
# written to creature_rigs.json in glTF's (x, z, -y).
BONES = [
    ("root", None, (0.0, 0.0, 1.30), (0.0, 0.0, 1.42), (0.24, 0.2, 0.16)),
    ("spine", "root", (0.0, 0.0, 1.45), (0.0, 0.0, 2.30), (0.3, 0.32, 0.3)),
    ("head", "spine", (0.0, 0.0, 2.5), (0.0, -0.03, 2.75), 0.15),
    # The shoulders sit behind the pod's middle (higher on screen from the front than the back).
    ("upper_arm_r", "spine", (0.44, -0.34, 2.08), (0.56, -0.26, 1.72), 0.12),
    ("forearm_r", "upper_arm_r", (0.56, -0.26, 1.72), (0.56, 0.8, 1.71), 0.12),
    ("upper_arm_l", "spine", (-0.44, -0.34, 2.08), (-0.6, -0.2, 1.8), 0.12),
    ("forearm_l", "upper_arm_l", (-0.6, -0.2, 1.8), (-0.64, 0.34, 1.62), 0.12),
    ("thigh_r", "root", (0.30, -0.06, 1.32), (0.35, 0.0, 0.80), 0.14),
    ("shin_r", "thigh_r", (0.35, 0.0, 0.80), (0.36, -0.08, 0.16), 0.14),
    ("thigh_l", "root", (-0.30, -0.06, 1.32), (-0.35, 0.0, 0.80), 0.14),
    ("shin_l", "thigh_l", (-0.35, 0.0, 0.80), (-0.36, -0.08, 0.16), 0.14),
]
BONE_INDEX = {b[0]: i for i, b in enumerate(BONES)}


def _gltf(p):
    return (p[0], p[2], -p[1])


GLTF_BONES = [(n, parent, _gltf(h), _gltf(t), r if isinstance(r, (int, float)) else (r[0], r[2], r[1]))
              for n, parent, h, t, r in BONES]


# The sprite's idle stance, as turns of the bones built above (character_pose.gd's terms: Euler
# YXZ in glTF's frame, about each bone's head, children with their parents), fitted to mech-idle's
# eight directions by silhouette (turntable_anim.py's character fitter on this rig) and baked into
# the rest pose: the right foot a step forward, the knees bent, the arms as the sprite holds them.
REST = {"root_dy": 0.013, "turns": {
    "spine": (0.05, 0.05, 0.0), "upper_arm_r": (-0.176, -0.074, -0.05), "forearm_r": (-0.024, 0.0, 0.424),
    "upper_arm_l": (0.0, -0.05, 0.15), "forearm_l": (-0.2, 0.15, -0.1),
    "thigh_r": (0.2, 0.0, 0.0), "shin_r": (-0.3, 0.0, 0.0), "thigh_l": (0.05, 0.0, 0.0), "shin_l": (-0.15, 0.0, 0.0)}}

def _euler_yxz(e):
    x, y, z = e
    cx, sx, cy, sy, cz, sz = math.cos(x), math.sin(x), math.cos(y), math.sin(y), math.cos(z), math.sin(z)
    rx = np.array([[1, 0, 0], [0, cx, -sx], [0, sx, cx]])
    ry = np.array([[cy, 0, sy], [0, 1, 0], [-sy, 0, cy]])
    rz = np.array([[cz, -sz, 0], [sz, cz, 0], [0, 0, 1]])
    return ry @ rx @ rz


def _skins(turns, root_dy=0.0):
    """Per bone, its 4x4 rest -> posed matrix in glTF's frame (character_pose.gd compute())."""
    out = []
    for name, parent, head, _tail, _r in GLTF_BONES:
        r = _euler_yxz(turns.get(name, (0.0, 0.0, 0.0)))
        h = np.asarray(head, dtype=float)
        local = np.eye(4)
        local[:3, :3] = r
        local[:3, 3] = h - r @ h
        if parent is None:
            base = np.eye(4)
            base[1, 3] = root_dy
        else:
            base = out[BONE_INDEX[parent]]
        out.append(base @ local)
    return out


class Rigged:
    """A Part whose pieces are added for a bone (`with rig.on("shin_r"): ...`); `on(None)` pieces
    blend between the nearest bones. The bones of every vertex go into TEXCOORD_0 at export."""

    def __init__(self, part):
        self.part = part
        self.bone_of = {}  # vertex position -> bone index, or None to blend
        self._bone = None
        self._start = 0
        self.bones = GLTF_BONES
        part.uv_fn = self.uv

    def on(self, bone):
        self._bone = bone
        return self

    def __enter__(self):
        self.part.bm.verts.ensure_lookup_table()
        self._start = len(self.part.bm.verts)
        return self.part

    def __exit__(self, *exc):
        bm = self.part.bm
        bm.verts.ensure_lookup_table()
        code = None if self._bone is None else BONE_INDEX[self._bone]
        for v in bm.verts[self._start:]:
            self.bone_of[_key(v.co)] = code
        return False

    def weights(self, co):
        code = self.bone_of.get(_key(co))
        if isinstance(code, tuple):
            return code
        if code is None:
            a, b, w = wube_rig.skin_weights(np.array([_gltf(co)]), GLTF_BONES, band=0.6)
            return int(a[0]), int(b[0]), float(w[0])
        return code, code, 1.0

    def bake(self, turns, root_dy=0.0):
        """Moves every vertex and bone into the pose `turns` and makes it the rest pose."""
        skins = _skins(turns, root_dy)
        moved = {}
        for v in self.part.bm.verts:
            a, b, w = self.weights(v.co)
            p = np.append(np.asarray(_gltf(v.co), dtype=float), 1.0)
            q = (skins[a] @ p) * w + (skins[b] @ p) * (1.0 - w)
            v.co = Vector((q[0], -q[2], q[1]))
            moved[_key(v.co)] = (a, b, w)
        self.bone_of = moved
        self.bones = []
        for i, (name, parent, head, tail, r) in enumerate(GLTF_BONES):
            h = skins[i] @ np.append(np.asarray(head, dtype=float), 1.0)
            t = skins[i] @ np.append(np.asarray(tail, dtype=float), 1.0)
            self.bones.append((name, parent, tuple(h[:3]), tuple(t[:3]), r))

    def uv(self, co):
        a, b, w = self.weights(co)
        # The glTF exporter writes Blender's v as 1 - v.
        return (a + 16.0 * b, 1.0 - w)


def _key(co):
    return (round(co.x, 4), round(co.y, 4), round(co.z, 4))

def loft(part, rings, mat, segs=16, power=3.0):
    """A closed shell through horizontal rounded rectangles: rings of (z, half width, half depth,
    y centre); `power` squares the corners off (2 is an ellipse)."""
    bm = bmesh.new()
    loops = []
    for z, hx, hy, cy in rings:
        loop = []
        for i in range(segs):
            a = 2 * math.pi * i / segs
            c, s = math.cos(a), math.sin(a)
            x = hx * math.copysign(abs(c) ** (2.0 / power), c)
            y = cy + hy * math.copysign(abs(s) ** (2.0 / power), s)
            loop.append(bm.verts.new((x, y, z)))
        loops.append(loop)
    for lo, hi in zip(loops, loops[1:]):
        for i in range(segs):
            j = (i + 1) % segs
            bm.faces.new([lo[i], lo[j], hi[j], hi[i]])
    bm.faces.new(list(reversed(loops[0])))
    bm.faces.new(loops[-1])
    part.merge(bm, mat)
    bm.free()


def _leg(rig, side):
    x = 0.35 * side
    s = "r" if side > 0 else "l"
    with rig.on("root") as p:
        # The hip's drum, where the thigh turns.
        p.cyl((0.27 * side, -0.06, 1.32), 0.12, 0.14, "mech_joint", segs=10, axis="X", bevel=0.02)
    with rig.on("thigh_" + s) as p:
        p.beam((0.31 * side, -0.06, 1.36), (x, 0.0, 0.84), 0.24, 0.3, "mech_armor", up=(0, 1, 0), bevel=0.03)
        # The thigh's outer plate, a little lighter where the sprite catches the light.
        p.beam((0.43 * side, -0.05, 1.26), (0.45 * side, 0.0, 0.92), 0.06, 0.26, "mech_light", up=(0, 1, 0), bevel=0.015)
    with rig.on("shin_" + s) as p:
        p.sphere((x, 0.0, 0.8), 0.15, "mech_joint", segs=10, rings=6)
        # The knee's guard, out in front.
        p.box((x, 0.12, 0.76), (0.22, 0.12, 0.22), "mech_light", bevel=0.03)
        p.beam((x, 0.0, 0.78), (x, -0.06, 0.2), 0.28, 0.32, "mech_armor", up=(0, 1, 0), bevel=0.03)
        p.beam((x, 0.15, 0.62), (x, 0.11, 0.3), 0.18, 0.06, "mech_joint", up=(0, 1, 0), bevel=0.01)
        # The foot: a broad sole with a toe cap and a heel spur.
        p.box((x, 0.03, 0.08), (0.3, 0.42, 0.16), "mech_joint", bevel=0.03)
        p.box((x, 0.17, 0.13), (0.26, 0.14, 0.12), "mech_armor", bevel=0.03)
        p.box((x, -0.17, 0.12), (0.18, 0.08, 0.14), "mech_armor", bevel=0.02)


def _gun_arm(rig):
    with rig.on("upper_arm_r") as p:
        # The shoulder: a rounded pauldron behind the pod's middle, in the player's colour on top.
        p.box((0.42, -0.32, 2.02), (0.26, 0.32, 0.26), "mech_armor", bevel=0.06)
        p.box((0.43, -0.32, 2.16), (0.2, 0.24, 0.04), "mech_paint", bevel=0.015)
        p.beam((0.46, -0.34, 2.02), (0.56, -0.26, 1.76), 0.18, 0.22, "mech_joint", up=(0, 1, 0), bevel=0.02)
    with rig.on("forearm_r") as p:
        p.sphere((0.56, -0.26, 1.72), 0.13, "mech_joint", segs=10, rings=6)
        # The gun: a boxy body along the forearm, a perforated sleeve, the barrel's end.
        p.box((0.56, -0.04, 1.71), (0.28, 0.5, 0.3), "mech_armor", bevel=0.04)
        p.box((0.56, -0.08, 1.88), (0.18, 0.3, 0.05), "mech_light", bevel=0.015)
        p.cyl((0.56, 0.38, 1.71), 0.13, 0.36, "mech_light", segs=12, axis="Y", bevel=0.01)
        for i in range(3):
            for k in range(6):
                a = 2 * math.pi * (k + 0.5 * (i % 2)) / 6
                p.cyl((0.56 + 0.13 * math.cos(a), 0.27 + 0.11 * i, 1.71 + 0.13 * math.sin(a)), 0.026, 0.03,
                      "mech_dark", segs=6, axis="X" if abs(math.cos(a)) > 0.7 else "Z")
        p.cyl((0.56, 0.67, 1.71), 0.09, 0.24, "mech_armor", segs=12, axis="Y", bevel=0.01)
        p.cyl((0.56, 0.79, 1.71), 0.055, 0.02, "mech_dark", segs=10, axis="Y")


def _claw_arm(rig):
    with rig.on("upper_arm_l") as p:
        p.box((-0.42, -0.32, 2.02), (0.26, 0.32, 0.26), "mech_armor", bevel=0.06)
        p.box((-0.56, -0.32, 1.98), (0.05, 0.24, 0.18), "mech_paint", bevel=0.015)
        p.beam((-0.46, -0.34, 2.02), (-0.6, -0.2, 1.82), 0.17, 0.2, "mech_joint", up=(0, 1, 0), bevel=0.02)
    with rig.on("forearm_l") as p:
        p.sphere((-0.6, -0.2, 1.8), 0.12, "mech_joint", segs=10, rings=6)
        p.beam((-0.6, -0.2, 1.8), (-0.64, 0.3, 1.66), 0.2, 0.2, "mech_armor", up=(0, 1, 0), bevel=0.03)
        # The claw: a palm, and five long fingers fanned out sideways and down in front of it
        # (wide from in front and behind), in the player's colour.
        p.box((-0.64, 0.34, 1.62), (0.24, 0.14, 0.18), "mech_joint", bevel=0.03)
        for k in range(5):
            a = math.radians(-70 + 35 * k)  # 0 points straight down, - inwards
            knuckle = (-0.64 + 0.09 * math.sin(a), 0.38, 1.6 - 0.06 * math.cos(a))
            tip = (-0.66 + 0.26 * math.sin(a), 0.46, 1.6 - 0.4 * math.cos(a))
            p.beam(knuckle, tip, 0.06, 0.06, "mech_paint", up=(0, 1, 0), bevel=0.01)

def _torso(rig):
    with rig.on("root") as p:
        # The pelvis between the hips, dark plates hanging under the pod.
        p.box((0.0, -0.04, 1.32), (0.44, 0.38, 0.3), "mech_joint", bevel=0.04)
        for k in range(5):
            p.box((-0.16 + 0.08 * k, 0.15, 1.24), (0.06, 0.05, 0.2), "mech_dark", bevel=0.01)
    with rig.on("spine") as p:
        # The cockpit pod: an egg, narrow at the bottom, broad at the shoulders, a dome on top.
        loft(p, [(1.42, 0.17, 0.2, 0.02), (1.6, 0.25, 0.28, 0.02), (1.85, 0.32, 0.35, 0.0),
                 (2.2, 0.34, 0.36, -0.02), (2.5, 0.31, 0.33, -0.03), (2.68, 0.22, 0.26, -0.04),
                 (2.78, 0.12, 0.15, -0.04)], "mech_armor", segs=16, power=2.6)
        # The hood over the pod's front (player's colour) and the visor slit under it.
        loft(p, [(2.08, 0.25, 0.08, 0.3), (2.36, 0.27, 0.08, 0.29), (2.58, 0.23, 0.07, 0.22),
                 (2.72, 0.14, 0.06, 0.12)], "mech_paint", segs=12, power=3.0)
        p.box((0.0, 0.35, 1.99), (0.4, 0.04, 0.07), "mech_dark", bevel=0.01)
        # The lower front panel (player's colour) with a dark vent in it.
        p.box((0.0, 0.29, 1.68), (0.26, 0.06, 0.28), "mech_paint", bevel=0.02)
        p.box((0.0, 0.32, 1.66), (0.1, 0.03, 0.14), "mech_dark", bevel=0.005)
        # The pack behind the pod, its plates (player's colour) under two thrusters that point
        # back and up (round from behind, rings over the pod's top from the front).
        p.box((0.0, -0.5, 1.98), (0.5, 0.3, 0.76), "mech_armor", bevel=0.06)
        p.box((-0.125, -0.66, 1.9), (0.23, 0.05, 0.5), "mech_paint", bevel=0.02)
        p.box((0.125, -0.66, 1.9), (0.23, 0.05, 0.5), "mech_paint", bevel=0.02)
        axis = Vector((0.0, -1.0, 1.0)).normalized()
        for x in (-0.16, 0.16):
            face = Vector((x, -0.58, 2.44))
            p.tube(face - axis * 0.4, face, 0.14, "mech_light", segs=14, bevel=0.02)
            p.tube(face - axis * 0.02, face + axis * 0.004, 0.105, "mech_dark", segs=12)
            p.tube(face - axis * 0.06, face + axis * 0.01, 0.035, "mech_joint", segs=8)
        # Pipes from the pack round the pod's sides.
        for x in (-0.27, 0.27):
            p.pipe([(x, -0.42, 2.3), (x * 1.08, -0.2, 2.42), (x * 1.08, 0.05, 2.3)], 0.035, "mech_light", segs=6)
    with rig.on("head") as p:
        # The dome's crest, a lighter cap on top of the pod.
        p.box((0.0, -0.04, 2.79), (0.18, 0.24, 0.04), "mech_light", bevel=0.015)
    with rig.on(None) as p:
        # Fillers where the pod meets the pelvis: they stretch between the two bones.
        p.cyl((0.0, -0.02, 1.43), 0.18, 0.12, "mech_joint", segs=10)


@model("character-mech-armor")
def character_mech_armor():
    part = Part("body")
    rig = Rigged(part)
    _torso(rig)
    for side in (1, -1):
        _leg(rig, side)
    _gun_arm(rig)
    _claw_arm(rig)
    rig.bake(REST.get("turns", {}), REST.get("root_dy", 0.0))
    wube_rig.write_pose_table("character-mech-armor", rig.bones)
    return part
