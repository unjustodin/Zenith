"""Space platform: hub, cargo bay, thruster, asteroid collector, crusher; asteroids.

Each model is matched to Factorio's HR sprite with compare.py (client/assets/models/README.md,
"Matching a sprite"); the sprite numbers are in space_sprites.py. As in oil.py, parts are placed
from where they show in the sprite: Factorio's camera shows a point (x, y, z) at x tiles right
and SIN_P * y + COS_P * z tiles up the screen, so a part's depth `y` gives its height from its
screen height (`zs`) and a part on a known height gives its depth (`ys`).

The platform's machines are cream-painted and riveted with dark steel and rusty pipework, the
hub's upper hatch ring rust red, the asteroid collector bare grey steel.
"""

import math

import bmesh
from mathutils import Matrix, Vector, noise

import detail
import kit
import space_kit as sk
from kit import Part, R, S, T, model

SIN_P, COS_P = math.sin(math.radians(48)), math.cos(math.radians(48))

kit.MATERIALS.update({
    # Picked against the Space Age sprites.
    "paint_platform": ("bdb4a0", 0.6, 0.35, None, 0),   # the platform machines' cream panels
    "steel_platform": ("858789", 0.55, 0.45, None, 0),  # grey steel housings (collector, crusher)
    "steel_arm": ("8c8781", 0.5, 0.5, None, 0),       # the collector arm's pale links and head
    "brass_arm": ("66502a", 0.45, 0.6, None, 0),      # the brass lining of its fingers
    "soot_deep": ("1d1e20", 0.7, 0.6, None, 0),        # the inside of hatches and chutes
    "rust_ring": ("5e3426", 0.7, 0.5, None, 0),         # the hub's upper hatch ring
    "paint_blue_dark": ("3e5266", 0.55, 0.45, None, 0),
    "brass_yellow": ("b39a52", 0.45, 0.7, None, 0),     # yellow brackets on the hub
    "glass_blue": ("8fb3c4", 0.2, 0.2, None, 0),        # cockpit windows (opaque: the sprite shows them)
    "thruster_glow": ("8fa8ff", 0.4, 0.0, "6f8cff", 2.5),
    "flame_blue": ("b9c8ff", 0.5, 0.0, "7a96ff", 4.0),
    # The thruster's exhaust plume: see-through, lit only while it fires (anim_glow_plume).
    "plume_flame": ("1c2340", 0.9, 0.0, "6f8cff", 5.0),
    "plume_core": ("39457a", 0.9, 0.0, "c9b8ff", 6.0),
    # The hub's cockpit screens and indicator lights (violet in the cockpit emission sheets).
    "lamp_violet": ("3a2f55", 0.4, 0.1, "9478e0", 3.0),
})
kit.ALPHA.update({"plume_flame": 0.3, "plume_core": 0.45})


def zs(u, y):
    """Height of a point at depth `y` that shows `u` tiles up the screen in the sprite."""
    return (u - SIN_P * y) / COS_P


def ys(u, z):
    """Depth of a point at height `z` that shows `u` tiles up the screen in the sprite."""
    return (u - COS_P * z) / SIN_P


def ring(p, center, r0, r1, z0, z1, mat, segs=24, a0=0, a1=360, bevel=0.0):
    band = Part()
    band.ring_band((0, 0), r0, r1, z0, z1, a0, a1, mat, segs=segs, bevel=bevel)
    p.add_part(band, T(center[0], center[1], 0))


def hatch(p, cx, cy, r_in, r_out, z_top, rim_mat, wall_mat="soot_deep", floor=0.12, segs=28):
    """An open cargo hatch: a thick rim round a deep hole whose walls drop to the floor."""
    ring(p, (cx, cy), r_out - 0.12, r_out, floor, z_top - 0.08, wall_mat, segs=segs)
    ring(p, (cx, cy), r_in, r_out, z_top - 0.16, z_top, rim_mat, segs=segs, bevel=0.02)
    ring(p, (cx, cy), r_in - 0.05, r_in + 0.03, floor, z_top - 0.1, wall_mat, segs=segs)
    p.cyl((cx, cy, floor + 0.01), r_in, 0.02, "soot_deep", segs=segs)
    # Ribs down the inside wall.
    for k in range(10):
        a = 2 * math.pi * (k + 0.5) / 10
        p.box((cx + (r_in - 0.08) * math.cos(a), cy + (r_in - 0.08) * math.sin(a), (floor + z_top) / 2 - 0.05),
              (0.08, 0.12, z_top - floor - 0.2), "steel_dark", rz=math.degrees(a))


def back_detail(p, a0, a1, face, z0, z1, axis="y", mat="steel_dark", pipe="rust", step=0.55):
    """Ribs, a pipe run and a grille on a face Factorio's camera never sees (north, east or
    west sides), so the model doesn't look unfinished from behind. `face` is the face's y (axis
    "y", facing north) or x (axis "x"); the detail spans a0..a1 along the face."""
    sign = 1 if face > 0 else -1
    n = max(1, int((a1 - a0) / step))
    for k in range(n + 1):
        a = a0 + (a1 - a0) * k / n
        if axis == "y":
            p.slab(a - 0.04, face, z0, a + 0.04, face + sign * 0.05, z1, mat)
        else:
            p.slab(face, a - 0.04, z0, face + sign * 0.05, a + 0.04, z1, mat)
    zp = z0 + (z1 - z0) * 0.35
    if axis == "y":
        p.cyl(((a0 + a1) / 2, face + sign * 0.1, zp), 0.06, a1 - a0, pipe, segs=8, axis="X")
        m = (a0 + a1) / 2
        p.slab(m - 0.3, face, z1 - 0.45, m + 0.3, face + sign * 0.06, z1 - 0.1, mat)
        for k in range(4):
            p.slab(m - 0.25, face + sign * 0.06, z1 - 0.4 + k * 0.08, m + 0.25, face + sign * 0.08, z1 - 0.37 + k * 0.08,
                   "steel_light")
    else:
        p.cyl((face + sign * 0.1, (a0 + a1) / 2, zp), 0.06, a1 - a0, pipe, segs=8, axis="Y")
        m = (a0 + a1) / 2
        p.slab(face, m - 0.3, z1 - 0.45, face + sign * 0.06, m + 0.3, z1 - 0.1, mat)


# ---------------------------------------------------------------------------------------------
# Space platform hub (and what the planet's cargo landing pad shares with it).

def rivet_rect(p, x0, y0, x1, y1, z, step=0.25, inset=0.07, mat="steel_light", sides="sn"):
    """Rivets along the edges of a top face x0..x1, y0..y1 at height z (s, n, w, e)."""
    nx = max(2, int((x1 - x0) / step) + 1)
    ny = max(2, int((y1 - y0) / step) + 1)
    if "s" in sides:
        detail.rivet_line(p, (x0 + inset, y0 + inset, z), (x1 - inset, y0 + inset, z), nx, "Z", mat)
    if "n" in sides:
        detail.rivet_line(p, (x0 + inset, y1 - inset, z), (x1 - inset, y1 - inset, z), nx, "Z", mat)
    if "w" in sides:
        detail.rivet_line(p, (x0 + inset, y0 + inset, z), (x0 + inset, y1 - inset, z), ny, "Z", mat)
    if "e" in sides:
        detail.rivet_line(p, (x1 - inset, y0 + inset, z), (x1 - inset, y1 - inset, z), ny, "Z", mat)


def upper_shaft(p, ux, uy, uz):
    """The upper cargo shaft both hubs draw (the platform hub's and the landing pad's): a rusty
    drum on the deck holding the hatch's rim, a dark steel band of clamp blocks round it, a latch
    box on its south side (the upper hatch's front sheet), and inside, seen while the lid is up,
    dark wall panels with rust-red pipes looping round them and dropping down the wall, as the
    sprites draw the open shaft."""
    p.cyl((ux, uy, uz / 2), 1.86, uz - 0.2, "rust_ring", segs=28, caps=False)
    hatch(p, ux, uy, 1.48, 1.84, uz, "rust_ring")
    ring(p, (ux, uy), 1.84, 1.95, uz - 0.5, uz - 0.3, "steel_dark", segs=28)
    for a in (35, 90, 145, 0, 320):
        r = math.radians(a)
        p.box((ux + 1.9 * math.cos(r), uy + 1.9 * math.sin(r), uz - 0.35), (0.25, 0.3, 0.7), "steel_dark",
              bevel=0.03, rz=a)
        p.box((ux + 1.97 * math.cos(r), uy + 1.97 * math.sin(r), uz - 0.25), (0.06, 0.16, 0.3), "steel_light",
              rz=a)
    # Bolts round the rim's top and round the drum under the band, a pale steel lip inside.
    p.bolts_ring((ux, uy, uz + 0.005), 1.76, 36, radius=0.03)
    ring(p, (ux, uy), 1.46, 1.52, uz - 0.22, uz - 0.02, "steel_light", segs=28)
    for k in range(28):
        a = 2 * math.pi * (k + 0.5) / 28
        p.box((ux + 1.87 * math.cos(a), uy + 1.87 * math.sin(a), uz - 0.75), (0.04, 0.04, 0.04), "steel_light",
              rz=math.degrees(a))
    # Inside: pipes round the wall at three heights, risers between them, dark panels behind.
    for z, mat in ((uz - 0.45, "rust"), (uz - 0.8, "rust_ring"), (uz - 1.25, "rust")):
        detail.hose_arc(p, (ux, uy), 1.36, z, 20, 340, 0.05, mat, rib=0.4)
    for k in range(9):
        a = math.radians(15 + k * 40)
        x, y = ux + 1.38 * math.cos(a), uy + 1.38 * math.sin(a)
        p.pipe([(x, y, uz - 0.3), (x, y, uz - 0.9), (x * 0.98 + ux * 0.02, y * 0.98 + uy * 0.02, 0.4)],
               0.035, "rust", segs=6, joints=False)
    for k in range(12):
        a = math.radians(k * 30 + 15)
        p.box((ux + 1.43 * math.cos(a), uy + 1.43 * math.sin(a), uz - 1.0), (0.04, 0.42, 0.6), "steel_black",
              rz=math.degrees(a))
    # The latch on the drum's south side: a box with a grille, a round lock under it.
    lx, ly = ux - 0.35, uy - 1.92
    p.slab(lx - 0.42, ly - 0.16, uz - 0.6, lx + 0.42, ly + 0.12, uz + 0.08, "steel_platform", bevel=0.03)
    detail.slots(p, (lx - 0.36, ly - 0.16, uz - 0.5), (lx + 0.36, ly + 0.12, uz), "-y", 6)
    p.cyl((lx, ly - 0.2, uz - 0.72), 0.13, 0.16, "steel_light", segs=10, axis="Y", bevel=0.02)
    for sx in (-1, 1):
        p.slab(lx + sx * 0.36 - 0.03, ly - 0.2, uz - 0.6, lx + sx * 0.36 + 0.03, ly - 0.16, uz + 0.1, "steel_light")


def upper_lid(name, ux, uy, uz, lid_r=1.62):
    """The upper giga hatch's lid, shut, as its back sheet's first frame draws it: a riveted grey
    disc, a raised plate in the middle with a second rivet ring, blue painted bands on its east and
    west segments, braces across it running north-east to the hinge, where a block with two
    pistons holds it. It hinges up about its north-east edge. Returns (part, hinge point)."""
    ne = Vector((math.sqrt(0.5), math.sqrt(0.5), 0.0))
    lid = Part(name)
    lid.cyl((ux, uy, uz + 0.05), lid_r, 0.1, "steel_platform", segs=32, bevel=0.03)
    lid.cyl((ux, uy, uz + 0.11), 0.95, 0.04, "steel_light", segs=24, bevel=0.01)
    lid.bolts_ring((ux, uy, uz + 0.1), lid_r - 0.12, 24, radius=0.035)
    lid.bolts_ring((ux, uy, uz + 0.135), 0.85, 14, radius=0.03, mat="steel_dark")
    for a0 in (130, 280):   # blue segments across the lid's sides, as the sheet paints them
        band = Part()
        band.ring_band((ux, uy), lid_r - 0.42, lid_r - 0.02, uz + 0.1, uz + 0.115, a0, a0 + 75, "paint_blue_dark", segs=8)
        lid.add_part(band)
    for off in (-0.45, 0.45):
        c = Vector((ux, uy, 0)) + Vector((-ne.y, ne.x, 0)) * off
        lid.box((c.x, c.y, uz + 0.13), (0.16, 2.6, 0.06), "steel_dark", rz=-45, bevel=0.02)
        for k in range(5):
            q = c + ne * (-1.0 + 0.5 * k)
            lid.box((q.x, q.y, uz + 0.17), (0.05, 0.05, 0.02), "steel_light")
    hinge = Vector((ux, uy, uz + 0.05)) + ne * lid_r
    lid.box(tuple(hinge - ne * 0.12 + Vector((0, 0, 0.08))), (0.5, 0.25, 0.2), "rust", rz=-45, bevel=0.03)
    for off in (-0.3, 0.3):
        a = hinge - ne * 0.7 + Vector((-ne.y, ne.x, 0)) * off + Vector((0, 0, 0.18))
        b = hinge - ne * 0.1 + Vector((-ne.y, ne.x, 0)) * off + Vector((0, 0, 0.22))
        lid.tube(a, b, 0.05, "steel_light", segs=8)
        lid.tube(a, a + (b - a) * 0.45, 0.065, "steel_dark", segs=8)
    return lid, hinge


def dish_block(p, paint, panel="paint_blue_dark"):
    """The south-east block both hubs share: a stepped housing in `paint` with a screen panel on
    its face, boxes on its top, rivets along its edges, and the radar dish on its mast."""
    p.slab(0.9, -3.3, 0.1, 3.7, -0.4, 1.25, paint, bevel=0.06)
    p.side_prism([(-3.3, 1.2), (-0.4, 1.2), (-0.4, 1.95), (-1.6, 2.1), (-2.95, 1.95), (-3.3, 1.55)],
                 1.05, 3.55, paint, bevel=0.05)
    p.slab(1.6, -3.33, 0.35, 3.3, -3.29, 0.95, panel)
    p.slab(1.1, -2.6, 1.95, 2.0, -1.9, 2.35, "steel_light", bevel=0.04)
    p.slab(2.2, -2.3, 1.95, 2.9, -1.5, 2.4, "steel_platform", bevel=0.04)
    detail.slots(p, (2.2, -2.3, 1.95), (2.9, -1.5, 2.4), "-y", 4)
    p.cyl((0.5, -2.2, 0.5), 0.12, 0.8, "steel_dark", segs=10, axis="X")
    p.cyl((1.4, -3.45, 0.22), 0.1, 0.4, "steel_dark", segs=8, axis="Y")
    # Seams and rivets on the housing; a vent grille down its east end; the screen's frame.
    detail.rivet_line(p, (1.0, -3.31, 1.15), (3.6, -3.31, 1.15), 12, "Y")
    detail.rivet_line(p, (1.0, -3.31, 0.2), (3.6, -3.31, 0.2), 12, "Y")
    detail.slots(p, (3.0, -3.3, 0.15), (3.6, -0.5, 1.1), "+x", 5, along=1)
    p.slab(1.55, -3.34, 0.3, 3.35, -3.31, 0.35, "steel_light")
    p.slab(1.55, -3.34, 0.95, 3.35, -3.31, 1.0, "steel_light")
    for x in (1.15, 3.55):
        p.slab(x - 0.02, -3.32, 1.25, x + 0.02, -0.5, 1.27, "steel_dark")
    # Radar dish, facing up and to the north-west, ribbed underneath.
    mx, my = 2.55, -1.2
    p.cyl((mx, my, 2.35), 0.12, 0.9, "steel_dark", segs=10)
    p.cyl((mx, my, 2.05), 0.3, 0.3, paint, segs=12, bevel=0.04)
    p.sphere((mx, my, 2.85), 0.16, "steel_light", segs=10, rings=5)
    dish = Part()
    dish.sphere((0, 0, 0), 0.85, "paint_platform", segs=20, rings=6, scale=(1, 1, 0.22), hemisphere=True)
    dish.cyl((0, 0, 0.05), 0.08, 0.6, "steel_light", segs=6)
    for k in range(10):   # the star of ribs round the hub of the dish
        a = math.radians(36 * k)
        dish.beam((0.12 * math.cos(a), 0.12 * math.sin(a), 0.03), (0.45 * math.cos(a), 0.45 * math.sin(a), 0.1),
                  0.05, 0.025, "steel_light")
    dish.cyl((0, 0, 0.04), 0.14, 0.05, "steel_dark", segs=10)
    detail.rivet_line(dish, (-0.8, 0, 0.18), (0.8, 0, 0.18), 2, "Z")
    p.add_part(dish, T(mx + 0.05, my + 0.05, 3.05) @ R("Z", 135) @ R("X", 180 - 40))


@model("space-platform-hub")
def space_platform_hub():
    """Factorio's platform hub: an 8x8 block of cream machinery round two cargo hatches, the
    lower one in the south-west at deck height with a cream rim, the upper one in the north-east
    raised on a rusty drum. The cockpit (a windowed cabin with antennas) stands at the north-west,
    a stepped machinery block with a radar dish at the south-east, pipework between.

    Both hatches are shut, as Factorio draws them while no pod passes (their giga hatch sheets'
    first frame: the upper one's riveted lid with its blue bands, the lower one's two plates
    striped yellow and black). The hub's own sprite leaves them out, so it shows both shafts open;
    the shafts are modelled inside (pipes, ribs, panels) for when the lids open.

    Moving parts: the upper hatch's round lid (anim_lid_hub_upper) hinges up about its
    north-east edge for cargo pods; the lower hatch's two trapdoor halves (anim_lid_hub_lower_ne,
    _sw) swing down into the shaft about their outer edges. The cockpit's violet screens and lights
    (anim_glow_cockpit) and the indicator panel on the south-east block (anim_glow_panel) blink
    as Factorio's cockpit sheets do."""
    p = Part()
    # Deck plate.
    p.slab(-3.92, -3.6, 0.0, 3.92, 3.92, 0.12, "steel_dark", bevel=0.03)

    # Lower hatch (south-west) with its cream rim and the yellow clamps on it.
    lx, ly = -1.85, -1.95
    hatch(p, lx, ly, 1.42, 1.95, 1.15, "paint_platform")
    for a, s in ((200, 0.36), (240, 0.3), (160, 0.3), (330, 0.32)):
        r = math.radians(a)
        p.box((lx + 1.75 * math.cos(r), ly + 1.75 * math.sin(r), 1.08), (0.42, s, 0.32), "brass_yellow",
              bevel=0.03, rz=a)
        for k in range(3):   # dark slots across each clamp
            t = (k - 1) * 0.1
            p.box((lx + (1.75 + t) * math.cos(r), ly + (1.75 + t) * math.sin(r), 1.245), (0.04, s * 0.7, 0.012),
                  "grime", rz=a)
    # The rim is plated: seams between its segments, a rivet ring, pipes inside the shaft.
    for k in range(10):
        a = math.radians(k * 36 + 10)
        p.box((lx + 1.7 * math.cos(a), ly + 1.7 * math.sin(a), 1.155), (0.5, 0.03, 0.01), "steel_dark",
              rz=math.degrees(a))
    p.bolts_ring((lx, ly, 1.155), 1.85, 30, radius=0.026)
    p.bolts_ring((lx, ly, 1.155), 1.52, 26, radius=0.024)
    for z in (0.75, 0.45):
        detail.hose_arc(p, (lx, ly), 1.3, z, 0, 360, 0.045, "rust", rib=0.4, steps=30)
    # Upper hatch (north-east) on a rusty drum.
    ux, uy, uz = 1.18, 1.72, 2.7
    upper_shaft(p, ux, uy, uz)
    # Yellow brackets up the north-east corner posts.
    for x, y, z in ((2.9, 3.6, 3.05), (3.55, 2.8, 2.7)):
        p.slab(x - 0.22, y - 0.2, 0.1, x + 0.22, y + 0.2, z - 0.35, "steel_dark", bevel=0.04)
        p.slab(x - 0.25, y - 0.22, z - 0.4, x + 0.25, y + 0.22, z, "brass_yellow", bevel=0.05)
        p.cyl((x, y - 0.23, z - 0.2), 0.08, 0.04, "steel_black", segs=8, axis="Y")
    # The east side under the upper hatch.
    p.slab(3.0, -0.2, 0.1, 3.88, 3.3, 2.2, "steel_platform", bevel=0.05)
    detail.slots(p, (3.0, -0.2, 0.2), (3.88, 3.3, 2.0), "+x", 7, along=1)

    # Cockpit: a windowed cabin on a pedestal at the north-west, antennas on its roof.
    p.slab(-3.0, 1.0, 0.1, -0.95, 3.7, 1.7, "steel_platform", bevel=0.05)
    cab = Part()
    cab.prism([(-2.95, 1.35), (-1.0, 1.35), (-0.95, 1.6), (-0.95, 3.45), (-1.2, 3.65), (-2.75, 3.65),
               (-2.95, 3.45)], 1.65, 3.05, "paint_platform", bevel=0.08)
    p.add_part(cab)
    p.slab(-2.8, 1.33, 1.95, -1.1, 1.37, 2.75, "glass_blue")
    p.slab(-2.65, 1.6, 3.04, -1.25, 3.4, 3.12, "paint_platform", bevel=0.03)
    # Skylights on the roof (the sprite's pale blue glass), windows down the west side, the
    # cream frame's rivets and a yellow bracket.
    for x0, y0, x1, y1 in ((-2.55, 2.55, -1.95, 3.3), (-1.85, 2.55, -1.35, 3.3), (-2.55, 1.7, -2.0, 2.4)):
        p.slab(x0, y0, 3.12, x1, y1, 3.14, "glass_blue")
        p.slab(x0 - 0.04, y0 - 0.04, 3.115, x1 + 0.04, y0, 3.15, "steel_light")
    for y0, y1 in ((1.6, 2.4), (2.6, 3.4)):
        p.slab(-2.97, y0, 2.0, -2.94, y1, 2.75, "glass_blue")
    rivet_rect(p, -2.9, 1.4, -1.0, 3.6, 3.06, sides="snwe")
    detail.rivet_line(p, (-2.85, 1.33, 1.85), (-1.05, 1.33, 1.85), 8, "Y")
    p.slab(-3.1, 2.0, 1.75, -2.93, 2.6, 2.55, "brass_yellow", bevel=0.03)
    p.cyl((-1.55, 1.35, 2.05), 0.3, 0.3, "steel_light", segs=16, axis="Y", bevel=0.03)
    p.cyl((-1.55, 1.18, 2.05), 0.16, 0.06, "paint_blue_dark", segs=12, axis="Y")
    p.bolts_ring((-1.55, 1.19, 2.05), 0.24, 8, axis="Y", radius=0.02)
    for x, y, h in ((-1.85, 2.4, 1.8), (-2.05, 2.55, 1.2)):
        p.cyl((x, y, 3.1 + h / 2), 0.025, h, "steel_light", segs=6)
    p.cyl((-1.85, 2.4, 3.3), 0.09, 0.4, "paint_platform", segs=10)
    detail.cable(p, [(-1.7, 2.3, 3.15), (-1.55, 2.0, 3.1), (-1.0, 1.6, 2.6), (-0.9, 1.3, 1.8)], 0.025, "wire_green")
    # Pedestal: dark machinery under the cab, pipes and a blue box on its south face.
    p.slab(-2.4, 0.98, 0.3, -1.85, 1.02, 1.0, "paint_blue_dark")
    detail.slots(p, (-2.4, 0.98, 0.3), (-1.85, 1.02, 1.0), "-y", 4)
    for x in (-2.7, -1.2):
        p.cyl((x, 0.95, 0.85), 0.08, 1.4, "steel_dark", segs=8)
    # Machinery west of the cockpit and down the west edge.
    p.slab(-3.88, 0.4, 0.1, -2.95, 3.3, 2.15, "steel_platform", bevel=0.05)
    detail.slots(p, (-3.88, 0.4, 0.3), (-2.95, 3.3, 1.9), "-x", 6, along=1)
    p.slab(-3.8, -0.5, 0.1, -3.2, 0.6, 1.35, "paint_platform", bevel=0.04)
    rivet_rect(p, -3.8, -0.5, -3.2, 0.6, 1.36, step=0.2, sides="we")
    p.cyl((-3.55, 0.0, 1.4), 0.2, 0.5, "steel_dark", segs=10)
    p.pipe([(-3.3, 0.55, 1.0), (-2.9, 0.75, 1.0), (-2.6, 0.95, 0.6)], 0.07, "steel_black", segs=8)

    # Middle: tanks and pipework between the hatches.
    p.slab(-1.0, -0.2, 0.1, 0.25, 1.3, 1.45, "steel_platform", bevel=0.05)
    p.sphere((-0.15, 0.55, 1.55), 0.42, "paint_platform", segs=14, rings=7, scale=(1.0, 1.3, 0.8))
    p.cyl((-0.15, 0.1, 1.55), 0.13, 0.25, "steel_dark", segs=10, axis="Y")
    p.cyl((-0.15, -0.03, 1.55), 0.08, 0.04, "grime", segs=8, axis="Y")
    p.slab(0.2, -0.55, 0.1, 1.2, 0.0, 1.35, "steel_platform", bevel=0.05)
    p.slab(0.35, -0.2, 1.3, 1.0, 0.25, 1.75, "steel_light", bevel=0.05)
    detail.slots(p, (0.35, -0.2, 1.3), (1.0, 0.25, 1.75), "+z", 4)
    p.slab(-0.2, -1.4, 0.1, 0.55, -0.4, 1.05, "paint_platform", bevel=0.05)
    p.slab(-0.1, -1.0, 1.0, 0.45, -0.55, 1.35, "brass_yellow", bevel=0.04)
    detail.slots(p, (-0.1, -1.0, 1.0), (0.45, -0.55, 1.35), "-y", 3)
    p.pipe([(-0.35, -0.2, 1.2), (0.0, -0.3, 1.5), (0.3, -0.1, 1.55)], 0.06, "rust", segs=8)
    # Red and green cables and rusty pipes over the middle, as the sprite's tangle.
    detail.cable(p, [(-0.9, 1.2, 1.5), (-0.5, 0.0, 1.6), (0.2, -0.45, 1.4), (0.9, -0.6, 1.3)], 0.03, "wire_red")
    detail.cable(p, [(-0.8, 1.25, 1.5), (-0.35, 0.05, 1.62), (0.3, -0.4, 1.42), (1.0, -0.5, 1.32)], 0.03, "wire_green")
    detail.cable(p, [(0.2, -0.5, 1.2), (0.6, -1.0, 1.1), (0.9, -1.6, 1.3)], 0.03, "wire_red")
    p.pipe([(0.25, 0.9, 1.0), (0.6, 0.6, 1.4), (1.1, 0.3, 1.3), (1.6, 0.2, 1.4)], 0.07, "rust", segs=8)
    p.pipe([(-0.95, -0.3, 0.9), (-0.5, -0.7, 0.9), (-0.25, -1.2, 0.7)], 0.06, "steel_dark", segs=8)

    # South-east machinery: a stepped block with blue panels, the radar dish on its mast.
    dish_block(p, "paint_platform")
    # Its south face's ribbed lavender hose and the pipes down to the deck edge.
    sk.hose(p, [(0.0, -3.3, 0.3), (0.5, -3.55, 0.35), (1.0, -3.45, 0.55), (1.4, -3.35, 0.4)], 0.12, "steel_platform",
            rib=0.08)
    for x in (1.95, 2.25):
        p.pipe([(x, -3.32, 0.9), (x, -3.5, 0.5), (x, -3.55, 0.1)], 0.05, "rust", segs=6)

    # Front edge pieces of the deck, pipes along the south.
    p.slab(-3.7, -3.5, 0.1, -2.4, -2.9, 0.55, "steel_platform", bevel=0.04)
    detail.slots(p, (-3.7, -3.5, 0.1), (-2.4, -2.9, 0.55), "-y", 3)
    p.slab(-0.6, -3.5, 0.1, 0.6, -3.05, 0.4, "steel_platform", bevel=0.04)
    p.pipe([(-3.6, -3.3, 0.5), (-3.6, -2.6, 0.5), (-3.6, -2.0, 1.0)], 0.07, "steel_dark", segs=8)
    detail.cable(p, [(-3.45, -3.45, 0.35), (-3.0, -3.6, 0.3), (-2.5, -3.55, 0.25)], 0.03, "wire_red")
    detail.cable(p, [(-0.5, -3.52, 0.3), (-0.1, -3.62, 0.25), (0.3, -3.55, 0.2)], 0.03, "wire_green")
    # Detail on the sides Factorio's camera doesn't see.
    back_detail(p, -2.9, -1.1, 3.7, 0.15, 1.6)
    back_detail(p, 0.6, 2.8, 3.62, 0.15, 1.2, pipe="steel_dark")
    back_detail(p, 0.0, 3.2, 3.88, 0.15, 2.1, axis="x")
    back_detail(p, 0.5, 3.2, -3.88, 0.15, 2.0, axis="x")
    back_detail(p, -0.4, 0.6, -3.8, 0.15, 1.3, axis="x")

    # The hatches' lids, shut.
    upper, hinge_u = upper_lid("anim_lid_hub_upper", ux, uy, uz)
    # Lower: two trapdoor halves under the rim, split along a north-west to south-east seam as
    # Factorio's two plates are: dark frames with a grid of ribs, striped yellow and black
    # diagonally, a rail along the seam.
    ne = Vector((math.sqrt(0.5), math.sqrt(0.5), 0.0))
    halves = []
    zl0, zl1 = 1.15 - 0.1, 1.15 - 0.03
    for name, n in (("anim_lid_hub_lower_ne", ne), ("anim_lid_hub_lower_sw", -ne)):
        half = Part(name)
        a0 = math.degrees(math.atan2(n.y, n.x)) - 90
        r = 1.42 - 0.03
        pts = [(lx + r * math.cos(math.radians(a0 + 180 * k / 14)), ly + r * math.sin(math.radians(a0 + 180 * k / 14)))
               for k in range(15)]
        half.prism(pts, zl0, zl1, "steel_dark", bevel=0.015)
        # Stripes: bands running north-south across the half (diagonal to its seam), clipped
        # to the half disc, yellow and black in turn.
        for k in range(-6, 7):
            x0 = k * 0.22
            ys_ = [t / 20.0 for t in range(-30, 31)
                   if (x0 + 0.08) ** 2 + (t / 20.0) ** 2 < (r - 0.12) ** 2
                   and (Vector((x0 + 0.08, t / 20.0, 0)).dot(n)) > 0.1]
            if len(ys_) < 2:
                continue
            half.slab(lx + x0, ly + min(ys_), zl1, lx + x0 + 0.16, ly + max(ys_), zl1 + 0.008,
                      "hazard" if k % 2 == 0 else "hazard_black")
        # A frame of ribs over the stripes.
        side = Vector((-n.y, n.x, 0))
        rz = math.degrees(math.atan2(n.y, n.x)) - 90
        for d in (0.55, 1.05):
            w = math.sqrt(max(0.0, r * r - d * d)) - 0.05
            c = Vector((lx, ly, 0)) + n * d
            half.box((c.x, c.y, zl1 + 0.025), (2 * w, 0.06, 0.04), "steel_black", rz=rz)
        for s_ in (-0.6, 0.6):
            c = Vector((lx, ly, 0)) + side * s_ + n * 0.6
            half.box((c.x, c.y, zl1 + 0.025), (0.06, 1.1, 0.04), "steel_black", rz=rz)
        c = Vector((lx, ly, 0)) + n * 0.05
        half.box((c.x, c.y, zl1 + 0.02), (2 * r - 0.1, 0.1, 0.05), "steel_light", rz=rz)
        halves.append((half, Vector((lx, ly, (zl0 + zl1) / 2)) + n * r))

    # Cockpit lights: violet screen strips and lamps on the cab's front under the window and on
    # its roof (Factorio's cockpit-A sheets), and the indicator lamps on the south-east block's
    # blue panel (cockpit-B).
    cockpit = Part("anim_glow_cockpit")
    for x in (-2.55, -2.2, -1.85):
        cockpit.slab(x, 1.31, 1.75, x + 0.25, 1.35, 1.85, "lamp_violet")
    for x, y in ((-2.45, 1.75), (-2.1, 1.75), (-1.45, 3.2), (-2.4, 3.25), (-1.4, 1.8)):
        cockpit.box((x, y, 3.14), (0.14, 0.14, 0.05), "lamp_violet")
    cockpit.slab(-2.6, 1.55, 3.11, -1.3, 1.62, 3.15, "lamp_violet")
    panel = Part("anim_glow_panel")
    for row, z in enumerate((0.75, 0.52)):
        for k in range(5):
            x = 1.8 + 0.3 * k + 0.12 * row
            panel.slab(x, -3.35, z, x + 0.14, -3.32, z + 0.1, "lamp_violet")

    # Fitted to the sprite, which covers about 7 of the 8 tiles (the deck's tiles show round it).
    fit = T(0.1, 0.0, 0.0) @ S(0.91, 0.91, 1.12)
    p.transform(fit)
    upper.transform(fit)
    upper.pivot = fit @ hinge_u
    out = [p, upper]
    for half, hinge in halves:
        half.transform(fit)
        half.pivot = fit @ hinge
        out.append(half)
    for glow in (cockpit, panel):
        glow.transform(fit)
        out.append(glow)
    return out


# ---------------------------------------------------------------------------------------------
# Cargo bay.

@model("cargo-bay")
def cargo_bay():
    """The platform cargo bay: a cream block with a long trough on top (its lid open on dark
    pipework), a rounded tower on the east, a ribbed drum and machinery along the south face, a
    pipe hooking down at the south-west. The sprite covers about 3x3 of its 4x4 tiles: the rest
    is drawn by the connections to the hub and neighbouring bays.

    Moving part: the trough's hatch (anim_hatch_bay), a yellow lid with a steel roller along its
    west edge. Factorio draws it shut (its hatch sheet's first frame) and slides it 1.2 tiles
    east (77 px at 64 px a tile over its 21 frames) to let a cargo pod in."""
    p = Part()
    p.slab(-1.55, -1.0, 0.0, 1.55, 1.8, 0.1, "steel_dark", bevel=0.03)
    # Main block with the trough recessed into its top.
    top = 1.5
    p.slab(-1.6, -0.25, 0.08, 0.6, 1.75, top - 0.4, "paint_platform", bevel=0.06)
    p.slab(-1.6, -0.25, top - 0.3, -1.15, 1.75, top, "paint_platform", bevel=0.06)
    p.slab(0.35, -0.25, top - 0.3, 0.6, 1.75, top, "paint_platform", bevel=0.06)
    p.slab(-1.4, 1.45, top - 0.3, 0.6, 1.75, top, "paint_platform", bevel=0.06)
    p.slab(-1.4, -0.25, top - 0.3, 0.6, 0.05, top, "paint_platform", bevel=0.06)
    p.slab(-1.15, 0.05, top - 0.42, 0.35, 1.45, top - 0.38, "soot_deep")
    # Dark plates, valves and rusty pipes down in the trough.
    for x in (-0.95, -0.55, -0.15, 0.2):
        p.slab(x - 0.15, 0.6, top - 0.4, x + 0.15, 1.35, top - 0.3, "paint_blue_dark", bevel=0.02)
    for k in range(3):
        p.cyl((-0.4 + 0.25 * k, 0.55, top - 0.33), 0.05, 0.9, "rust", segs=6, axis="Y")
    p.pipe([(-1.1, 0.35, top - 0.33), (-0.2, 0.3, top - 0.33), (0.3, 0.45, top - 0.3)], 0.06, "rust", segs=6)
    # The capsule end at the north-west (the yellow hatch on its end).
    p.cyl((-1.15, 1.2, top - 0.25), 0.28, 0.5, "brass_yellow", segs=14, axis="X", bevel=0.03)
    # Rounded tower on the east.
    tw = Part()
    tw.slab(0.55, -0.45, 0.08, 1.62, 1.75, top - 0.5, "paint_platform", bevel=0.08)
    tw.slab(0.55, -0.85, 0.08, 1.42, -0.4, top - 0.5, "paint_platform", bevel=0.08)
    tw.slab(0.6, -0.4, top - 0.55, 1.45, 1.75, top - 0.08, "paint_platform", bevel=0.18)
    tw.cyl((1.08, 0.45, top - 0.5), 0.54, 2.6, "paint_platform", segs=16, axis="Y", bevel=0.05)
    p.add_part(tw)
    p.slab(0.72, 0.9, top - 0.36, 1.2, 1.5, top - 0.3, "soot_deep")
    p.cyl((1.0, -0.6, 1.0), 0.18, 0.3, "steel_light", segs=12, axis="Y")
    p.cyl((1.0, -0.82, 1.0), 0.1, 0.12, "soot_deep", segs=10, axis="Y")
    p.cyl((1.15, -0.85, 0.45), 0.14, 0.5, "steel_dark", segs=10)
    # South face: a cream arch over a rust-red grille, machinery boxes west of it.
    arch = Part()
    arch.ring_band((0, 0), 0.45, 0.58, -0.3, 0.3, 0, 180, "paint_platform", segs=12, bevel=0.02)
    arch.ring_band((0, 0), 0.0, 0.46, -0.25, 0.25, 0, 180, "rust_brown", segs=12)
    for k in range(7):
        arch.box((-0.36 + 0.12 * k, 0.2, 0.26), (0.03, 0.4, 0.02), "rust")
    p.add_part(arch, T(0.15, -0.55, 0.34) @ R("X", 90))
    for sx in (-1, 1):
        p.slab(0.15 + sx * 0.45, -0.85, 0.1, 0.15 + sx * 0.58, -0.25, 0.34, "paint_platform", bevel=0.02)
    p.slab(-0.31, -0.8, 0.1, 0.61, -0.3, 0.34, "rust_brown")
    # Above and west of it the face is dark machinery: plates, pipes and valves under the lid.
    p.slab(-1.55, -0.33, 0.1, 0.55, -0.25, top - 0.42, "steel_dark")
    for z in (0.5, 0.68):
        p.cyl((-0.5, -0.38, z), 0.05, 2.0, "rust", segs=6, axis="X")
    for x in (-0.95, -0.35, 0.35):
        p.cyl((x, -0.4, 0.45), 0.06, 0.6, "rust", segs=6)
        p.box((x, -0.38, 0.75), (0.16, 0.1, 0.1), "steel_light")
    p.slab(-1.4, -0.8, 0.08, -0.3, -0.25, 0.9, "steel_platform", bevel=0.04)
    for x in (-1.15, -0.85, -0.55):
        p.cyl((x, -0.82, 0.6), 0.12, 0.08, "steel_light", segs=10, axis="Y")
    p.pipe([(-1.3, -0.5, 0.75), (-1.45, -0.7, 0.6), (-1.78, -1.0, 0.35), (-1.75, -1.4, 0.12)], 0.1, "steel_dark", segs=10)
    p.cyl((-1.75, -1.25, 0.25), 0.13, 0.12, "brass_yellow", segs=10)
    # Rivets round the trough's rim and down the cream corners, rust-streaked seams, rivets on the
    # trough's dark plates, the tower's panel seams and its round port's bolts.
    for y in (-0.18, 1.68):
        detail.rivet_line(p, (-1.5, y, top + 0.005), (0.5, y, top + 0.005), 11, "Z")
    for x in (-1.52, 0.52):
        detail.rivet_line(p, (x, 0.05, top + 0.005), (x, 1.45, top + 0.005), 7, "Z")
    for x in (-0.95, -0.55, -0.15, 0.2):
        detail.rivet_line(p, (x - 0.1, 0.65, top - 0.295), (x - 0.1, 1.3, top - 0.295), 3, "Z")
        detail.rivet_line(p, (x + 0.1, 0.65, top - 0.295), (x + 0.1, 1.3, top - 0.295), 3, "Z")
    for x in (-0.95, -0.2):
        p.slab(x - 0.012, -0.27, 0.95, x + 0.012, -0.24, top - 0.02, "rust")
    detail.rivet_line(p, (-1.5, -0.27, top - 0.35), (0.5, -0.27, top - 0.35), 11, "Y")
    for y in (0.2, 1.1):
        p.slab(1.6, y - 0.012, 0.15, 1.64, y + 0.012, top - 0.6, "steel_dark")
    detail.rivet_line(p, (1.63, -0.3, top - 0.6), (1.63, 1.65, top - 0.6), 9, "X")
    p.bolts_ring((1.0, -0.79, 1.0), 0.15, 8, axis="Y", radius=0.018)
    detail.slots(p, (0.6, -0.86, 0.15), (1.4, -0.45, 0.5), "-y", 3)
    back_detail(p, -1.45, 0.45, 1.75, 0.15, 1.2)
    back_detail(p, 0.0, 1.6, -1.6, 0.15, 1.1, axis="x")
    # The hatch over the trough, shut: a yellow panel framed and ribbed, the roller along its
    # west edge, a dark latch plate on it.
    lid = Part("anim_hatch_bay")
    lid.slab(-1.3, -0.02, top + 0.02, 0.45, 1.52, top + 0.08, "brass_yellow", bevel=0.02)
    for y0, y1 in ((-0.02, 0.06), (1.44, 1.52)):
        lid.slab(-1.3, y0, top + 0.08, 0.45, y1, top + 0.12, "brass_yellow", bevel=0.015)
    lid.slab(0.37, -0.02, top + 0.08, 0.45, 1.52, top + 0.12, "brass_yellow", bevel=0.015)
    lid.cyl((-1.22, 0.75, top + 0.12), 0.13, 1.6, "steel_light", segs=12, axis="Y", bevel=0.02)
    for y in (0.0, 1.5):
        lid.cyl((-1.22, y, top + 0.12), 0.15, 0.08, "rust", segs=12, axis="Y")
    lid.slab(-0.95, 1.05, top + 0.08, -0.6, 1.3, top + 0.1, "steel_dark")
    # The shared bay hatch sheet's roller is banded and its lid ribbed, a round dark lock at its
    # north-east corner.
    for y in (0.25, 0.5, 0.75, 1.0, 1.25):
        lid.cyl((-1.22, y, top + 0.12), 0.14, 0.04, "steel_dark", segs=12, axis="Y")
    for x in (-0.6, -0.1, 0.25):
        lid.slab(x - 0.03, 0.08, top + 0.08, x + 0.03, 1.42, top + 0.105, "brass_yellow")
    lid.cyl((0.2, 1.3, top + 0.1), 0.1, 0.04, "steel_black", segs=10)
    # Fitted to the sprite: its picture is 2.9 tiles wide (the connections draw the rest), its
    # south face 0.5 tiles south of the centre and its lid 1.4 tiles deep (1.8 up).
    fit = T(0.0, 0.173, 0) @ S(0.89, 0.693, 1.2)
    p.transform(fit)
    lid.transform(fit)
    return [p, lid]


# ---------------------------------------------------------------------------------------------
# The cargo area's edges. Factorio draws a bay's picture over about 3x3 of its 4x4 tiles and the
# rest from a tileset ("connections", cargo-hubs/connections/platform-connections-*.png) that it
# lays round the whole cargo area of a hub and its bays, one piece per 2x2 cell: a wall on each
# cell side facing no cargo area, an outer corner where two such sides meet, an inner corner
# where two joined sides leave the cell between them empty. So a lone bay is framed on all four
# sides, bays side by side share one frame with the deck showing between their machines, and
# no wall stands where a bay meets the hub or another bay. The client picks the pieces per cell
# from the neighbours (model_library.gd CARGO_PIECES) and draws each unturned on its cell.
#
# Each piece is modelled on one 2x2 cell centred on the origin, from the frame of the tileset it
# stands for (space_sprites.py). Factorio's walls differ per side, as its camera sees them: the
# top wall a low rail, the side walls narrow strips of machinery, the bottom wall the deep south
# face of machinery under the bay; so do these.

def _bay_pipe(p, pts, r=0.05, mat="rust"):
    p.pipe(pts, r, mat, segs=8)


def _side_strip(p, sx, y0, y1, cream_at, grille=True):
    """A side wall's machinery along the cell's east (sx 1) or west (sx -1) edge from y0 to y1:
    a dark sill, a cream panel with a grille where the sprite has it (`cream_at`: its y range),
    dark boxes and a rusty pipe run along the outside."""
    xo, xi = sx * 0.98, sx * 0.25
    lo, hi = min(xo, xi), max(xo, xi)
    p.slab(lo, y0, 0.0, hi, y1, 0.18, "steel_dark", bevel=0.03)
    c0, c1 = cream_at
    p.slab(lo + 0.04, c0, 0.18, hi - 0.04, c1, 0.82, "paint_platform", bevel=0.06)
    if grille:
        detail.slots(p, (lo + 0.04, c0 + 0.1, 0.3), (hi - 0.04, c1 - 0.1, 0.78), "+z", 5, mat="soot_deep", along=0)
    detail.rivet_line(p, (xo + sx * 0.005 - sx * 0.04, c0 + 0.08, 0.7), (xo - sx * 0.04 + sx * 0.005, c1 - 0.08, 0.7),
                      max(2, int((c1 - c0) / 0.2)), "X")
    rest = [(y0, c0), (c1, y1)]
    for a, b in rest:
        if b - a > 0.15:
            p.slab(lo + 0.08, a + 0.04, 0.18, hi - 0.08, b - 0.04, 0.55, "steel_dark", bevel=0.04)
            p.slab(lo + 0.14, a + 0.1, 0.55, hi - 0.14, b - 0.1, 0.6, "paint_blue_dark")
    _bay_pipe(p, [(xo, y0, 0.35), (xo, y1, 0.35)], 0.055)
    _bay_pipe(p, [(xo - sx * 0.08, y0, 0.22), (xo - sx * 0.08, y1, 0.22)], 0.04, "steel_light")


def _top_rail(p, x0, x1):
    """The top wall: a low sill and rail along the cell's north edge."""
    p.slab(x0, 0.82, 0.0, x1, 0.98, 0.12, "steel_dark", bevel=0.02)
    p.beam((x0, 0.9, 0.24), (x1, 0.9, 0.24), 0.08, 0.07, "steel_platform", bevel=0.01)
    for x in (x0 + 0.15, x1 - 0.15):
        p.slab(x - 0.05, 0.84, 0.1, x + 0.05, 0.96, 0.3, "steel_dark")


def _bottom_block(p, x0, x1, vent_x=None):
    """The bottom wall: the deep south face of machinery from the cell's south edge back to
    where the bay's machine stands (0.45 north of the cell's middle): dark plant on a rusty
    frame, a ribbed cream vent box, pipe runs and fittings along the front."""
    p.slab(x0, -0.98, 0.0, x1, 0.45, 0.15, "steel_dark", bevel=0.03)
    p.slab(x0 + 0.03, -0.55, 0.15, x1 - 0.03, 0.45, 0.85, "steel_dark", bevel=0.05)
    p.slab(x0 + 0.05, -0.62, 0.15, x1 - 0.05, -0.55, 0.62, "rust_brown")
    detail.slots(p, (x0 + 0.05, -0.64, 0.2), (x1 - 0.05, -0.6, 0.6), "-y", 4, mat="soot_deep", along=0)
    if vent_x is not None:
        v0, v1 = vent_x
        p.slab(v0, -0.5, 0.15, v1, 0.45, 1.05, "paint_platform", bevel=0.08)
        detail.slots(p, (v0 + 0.06, -0.52, 0.6), (v1 - 0.06, -0.48, 0.98), "-y", 5, mat="soot_deep", along=0)
        detail.rivet_line(p, (v0 + 0.06, -0.505, 0.45), (v1 - 0.06, -0.505, 0.45), 4, "Y")
    for z in (0.3, 0.48):
        _bay_pipe(p, [(x0, -0.7, z), (x1, -0.7, z)], 0.05)
    n = max(1, int((x1 - x0) / 0.5))
    for k in range(n):
        x = x0 + (x1 - x0) * (k + 0.5) / n
        p.slab(x - 0.12, -0.95, 0.15, x + 0.12, -0.75, 0.38, "steel_light", bevel=0.02)
        p.cyl((x + 0.18, -0.85, 0.3), 0.06, 0.3, "steel_dark", segs=8)
    p.slab(x0 + 0.1, 0.0, 0.85, x1 - 0.1, 0.4, 0.9, "steel_platform")


@model("cargo-bay-wall-n")
def cargo_bay_wall_n():
    """The cargo area's top wall over one cell: a low rail along the north edge with a valve."""
    p = Part()
    _top_rail(p, -1.0, 1.0)
    p.cyl((0.2, 0.9, 0.22), 0.12, 0.08, "rust", segs=12)
    p.cyl((0.2, 0.9, 0.38), 0.07, 0.3, "rust_brown", segs=10)
    p.sphere((0.2, 0.9, 0.55), 0.08, "rust", segs=10, rings=4)
    p.bolts_ring((0.2, 0.9, 0.27), 0.1, 6, radius=0.015)
    return p


@model("cargo-bay-wall-e")
def cargo_bay_wall_e():
    """The cargo area's east wall over one cell: a strip of machinery down the east edge."""
    p = Part()
    _side_strip(p, 1, -1.0, 1.0, (0.15, 0.9))
    return p


@model("cargo-bay-wall-s")
def cargo_bay_wall_s():
    """The cargo area's bottom wall over one cell: the deep south face of machinery."""
    p = Part()
    _bottom_block(p, -1.0, 1.0, vent_x=(0.15, 0.75))
    return p


@model("cargo-bay-wall-w")
def cargo_bay_wall_w():
    """The cargo area's west wall over one cell: cream ribbed panels and machinery."""
    p = Part()
    _side_strip(p, -1, -1.0, 1.0, (-0.2, 0.9))
    for y in (0.0, 0.3, 0.6):
        p.slab(-0.94, y, 0.82, -0.56, y + 0.12, 0.86, "steel_platform")
    return p


@model("cargo-bay-corner-nw")
def cargo_bay_corner_nw():
    """The cargo area's north-west outer corner: the rail and the west strip joined by a cream
    duct bent round the corner."""
    p = Part()
    _top_rail(p, -0.4, 1.0)
    _side_strip(p, -1, -1.0, 0.4, (-0.55, 0.2), grille=False)
    sk_pts = [(-0.75, -0.1, 0.7), (-0.75, 0.55, 0.7), (-0.45, 0.85, 0.6), (0.2, 0.88, 0.45)]
    p.pipe(sk_pts, 0.13, "paint_platform", segs=12)
    for q in sk_pts[1:3]:
        p.cyl(q, 0.15, 0.06, "steel_dark", segs=12)
    p.slab(-0.98, 0.4, 0.0, -0.5, 0.98, 0.2, "steel_dark", bevel=0.03)
    detail.cable(p, [(-0.6, -0.4, 0.6), (-0.55, 0.1, 0.75), (-0.5, 0.5, 0.65)], 0.025, "paint_blue_dark")
    return p


@model("cargo-bay-corner-ne")
def cargo_bay_corner_ne():
    """The cargo area's north-east outer corner: the rail and the east strip meeting in a dark
    housing with a cream plate."""
    p = Part()
    _top_rail(p, -1.0, 0.5)
    _side_strip(p, 1, -1.0, 1.0, (-0.6, 0.1))
    p.slab(0.48, 0.3, 0.0, 0.98, 0.98, 0.75, "steel_dark", bevel=0.05)
    p.slab(0.52, 0.4, 0.75, 0.94, 0.9, 0.8, "paint_platform", bevel=0.02)
    _bay_pipe(p, [(-0.6, 0.9, 0.45), (0.3, 0.9, 0.45), (0.5, 0.75, 0.6)], 0.05)
    return p


@model("cargo-bay-corner-sw")
def cargo_bay_corner_sw():
    """The cargo area's south-west outer corner: the bottom wall's machinery ending in a tall
    ribbed cream tower at the west, with the west strip running north from it."""
    p = Part()
    _bottom_block(p, -0.45, 1.0)
    _side_strip(p, -1, 0.4, 1.0, (0.5, 0.95), grille=False)
    p.slab(-0.98, -0.95, 0.0, -0.4, 0.45, 1.3, "paint_platform", bevel=0.1)
    for z in (0.5, 0.75, 1.0):
        p.slab(-0.99, -0.85, z, -0.38, 0.35, z + 0.06, "steel_platform")
    detail.panel(p, (-0.98, -0.95, 0.15), (-0.4, 0.45, 1.3), "-y", "steel_platform", margin=0.08, rivet="steel_light")
    p.slab(-0.9, 0.2, 1.3, -0.5, 0.45, 1.42, "brass_yellow", bevel=0.02)
    p.bolts_ring((-0.7, -0.3, 1.31), 0.12, 6, radius=0.02)
    return p


@model("cargo-bay-corner-se")
def cargo_bay_corner_se():
    """The cargo area's south-east outer corner: the bottom wall's machinery under a big cream
    duct curving down at the east, a blue hose looping over it."""
    p = Part()
    _bottom_block(p, -1.0, 0.45)
    _side_strip(p, 1, 0.45, 1.0, (0.5, 0.95), grille=False)
    duct = [(0.7, 0.6, 1.0), (0.7, 0.1, 1.15), (0.7, -0.5, 0.85), (0.7, -0.85, 0.35)]
    p.pipe(duct, 0.24, "paint_platform", segs=14)
    for q in duct[1:3]:
        p.cyl(q, 0.27, 0.08, "steel_platform", segs=14, axis="Y")
    p.slab(0.42, -0.95, 0.0, 0.98, 0.45, 0.45, "steel_dark", bevel=0.04)
    detail.hose_arc(p, (0.55, 0.45), 0.3, 1.25, 0, 180, 0.06, "paint_blue_dark")
    return p


@model("cargo-bay-inner-nw")
def cargo_bay_inner_nw():
    """An inner corner at the cell's north-west, where the walls of the cells north and west of
    it meet: a cream elbow on a dark foot."""
    p = Part()
    p.slab(-0.98, 0.75, 0.0, -0.4, 1.3, 0.25, "steel_dark", bevel=0.03)
    p.pipe([(-0.75, 0.8, 0.3), (-0.75, 1.0, 0.6), (-0.5, 1.2, 0.6)], 0.1, "paint_platform", segs=10)
    p.bolts_ring((-0.75, 1.0, 0.26), 0.15, 5, radius=0.018)
    return p


@model("cargo-bay-inner-ne")
def cargo_bay_inner_ne():
    """An inner corner at the cell's north-east: a grey motor and its bracket."""
    p = Part()
    p.slab(0.45, 0.8, 0.0, 0.98, 1.25, 0.25, "steel_dark", bevel=0.03)
    p.cyl((0.72, 1.02, 0.42), 0.16, 0.3, "steel_platform", segs=12, axis="X")
    p.cyl((0.72, 1.02, 0.42), 0.08, 0.34, "steel_light", segs=10, axis="X")
    return p


@model("cargo-bay-inner-sw")
def cargo_bay_inner_sw():
    """An inner corner at the cell's south-west: a cream panelled strip with dark plant below it,
    where the bottom wall of the cell west of it meets the side wall of the cell south of it."""
    p = Part()
    p.slab(-0.98, -1.4, 0.0, -0.3, 0.45, 0.2, "steel_dark", bevel=0.03)
    p.slab(-0.95, -0.4, 0.2, -0.35, 0.45, 0.95, "paint_platform", bevel=0.06)
    p.slab(-0.95, -1.35, 0.2, -0.35, -0.45, 0.6, "steel_dark", bevel=0.04)
    detail.panel(p, (-0.95, -0.4, 0.2), (-0.35, 0.45, 0.95), "+z", "steel_platform", margin=0.06)
    _bay_pipe(p, [(-0.42, -1.35, 0.35), (-0.42, 0.4, 0.35)], 0.05)
    return p


@model("cargo-bay-inner-se")
def cargo_bay_inner_se():
    """An inner corner at the cell's south-east: cream plates over dark plant."""
    p = Part()
    p.slab(0.3, -1.4, 0.0, 0.98, 0.45, 0.2, "steel_dark", bevel=0.03)
    p.slab(0.35, -0.3, 0.2, 0.95, 0.45, 0.95, "paint_platform", bevel=0.06)
    p.slab(0.35, -1.35, 0.2, 0.95, -0.35, 0.55, "steel_dark", bevel=0.04)
    for z in (0.45, 0.7):
        p.slab(0.34, -0.25, z, 0.96, 0.4, z + 0.05, "steel_platform")
    _bay_pipe(p, [(0.42, -1.35, 0.35), (0.42, 0.4, 0.35)], 0.05)
    return p


# ---------------------------------------------------------------------------------------------
# Thruster.

@model("thruster")
def thruster():
    """Factorio's thruster: a long cream engine casing in tangled pipework, two coil springs at
    its north end where fuel and oxidizer come in, tanks at the corners and ribbed hoses down the
    sides; at its south end a huge ribbed bell nozzle hangs out past the deck's edge, its mouth
    tilted up towards the camera as the sprite draws it, ringed by combustion chambers (three over
    the mouth, one down each side, two under it), glowing blue while it fires. The glow is a
    separate part (anim_glow_flame), lit while it works and flickering as Factorio's light sheet
    (64 frames at 0.5, 2.1 s); the exhaust plume streaming south out of the bell is another
    (anim_glow_plume): two see-through cones, a pale core in a wider blue sheath, that flicker
    along their length while it fires."""
    p = Part()
    # Only the engine stands on the deck: the platform's tiles show either side of it.
    p.slab(-1.3, -2.3, 0.0, 1.3, 2.45, 0.15, "steel_dark", bevel=0.04)
    p.slab(-1.15, 1.9, 0.1, 1.15, 2.45, 1.3, "steel_dark", bevel=0.05)
    for sx in (-1, 1):
        p.slab(sx * 1.45, -3.0, 0.1, sx * 1.95, -0.9, 0.9, "steel_dark", bevel=0.05)
        p.slab(sx * 1.25, 1.1, 0.1, sx * 1.75, 1.6, 0.8, "steel_platform", bevel=0.05)
        # Dark machinery packed between the casing and the tanks.
        p.slab(sx * 1.05, -0.95, 0.1, sx * 1.6, 1.15, 1.0, "steel_dark", bevel=0.04)
        for k in range(3):
            p.cyl((sx * 1.35, -0.6 + k * 0.6, 1.05), 0.12, 0.3, "steel_light", segs=10)
        for k in range(7):
            p.cyl((sx * 1.72, -2.85 + k * 0.3, 1.0), 0.15, 0.42, "steel_black", segs=10, axis="X")
    # The two coil springs at the north end.
    for x in (-0.6, 0.6):
        p.cyl((x, 2.15, 1.4), 0.15, 0.9, "steel_dark", segs=10)
        for k in range(6):
            p.cyl((x, 2.15, 1.0 + k * 0.16), 0.27, 0.09, "steel_platform", segs=14, bevel=0.02)
    # The engine casing: a long cream body narrowing to the south.
    # The sprite shows it mostly as dark machinery: cream only on the riveted head plate at the
    # north end, the bullet-shaped tank in the middle and the bracket band at the south end.
    body = Part()
    body.prism([(-1.0, -1.6), (1.0, -1.6), (1.25, 0.2), (1.1, 1.9), (-1.1, 1.9), (-1.25, 0.2)], 0.15, 1.45,
               "steel_dark", bevel=0.1)
    p.add_part(body)
    head = Part()
    head.prism([(-0.55, 0.35), (0.55, 0.35), (0.85, 1.0), (0.95, 1.9), (-0.95, 1.9), (-0.85, 1.0)], 1.4, 1.62,
               "paint_platform", bevel=0.05)
    p.add_part(head)
    p.slab(-0.25, 0.1, 1.55, 0.25, 1.8, 1.9, "paint_platform", bevel=0.08)
    for side in (-1, 1):
        detail.rivet_line(p, (side * 0.6, 1.8, 1.625), (side * 0.75, 0.75, 1.625), 6, "Z")
        detail.rivet_line(p, (side * 0.32, 1.75, 1.905), (side * 0.32, 0.2, 1.905), 7, "Z")
        p.slab(side * 0.9 - 0.1, 1.2, 1.3, side * 0.9 + 0.1, 1.8, 1.66, "steel_light", bevel=0.03)
    p.sphere((-0.15, -0.9, 1.55), 0.35, "paint_cream", segs=12, rings=6, scale=(1.0, 1.4, 0.8))
    p.cyl((-0.15, -0.45, 1.55), 0.16, 0.12, "steel_light", segs=10, axis="Y")
    # Grey pipe bodies and valves standing out of the machinery, blue, green and red cables.
    for x, y0, y1, z, r in ((-0.55, -0.3, 0.6, 1.6, 0.13), (0.35, -0.1, 0.9, 1.65, 0.14), (0.75, -0.8, 0.2, 1.5, 0.11),
                            (-0.95, -0.6, 0.2, 1.45, 0.1), (0.05, 0.0, 0.4, 1.85, 0.09)):
        p.cyl((x, (y0 + y1) / 2, z), r, y1 - y0, "steel_light", segs=10, axis="Y", bevel=0.02)
        p.cyl((x, y0 + 0.05, z), r * 1.25, 0.06, "steel_dark", segs=10, axis="Y")
        p.cyl((x, y1 - 0.05, z), r * 1.25, 0.06, "steel_dark", segs=10, axis="Y")
    for pts, mat in (([(-1.2, 1.0, 1.4), (-0.8, 0.9, 1.7), (-0.3, 0.7, 1.7), (0.1, 0.9, 1.6)], "wire_blue"),
                     ([(-1.2, 0.9, 1.35), (-0.7, 0.75, 1.62), (-0.35, 0.55, 1.65)], "wire_green"),
                     ([(-1.2, 0.8, 1.3), (-0.75, 0.6, 1.55), (-0.4, 0.4, 1.55)], "wire_red"),
                     ([(0.6, 1.6, 1.7), (0.55, 0.8, 1.75), (0.45, -0.2, 1.7), (0.2, -1.2, 1.5)], "wire_blue"),
                     ([(-0.4, -0.3, 1.7), (-0.6, -1.0, 1.6), (-0.7, -1.5, 1.3)], "wire_blue")):
        detail.cable(p, pts, 0.03, mat)
    # Tanks at the corners (fuel and oxidizer).
    for x, y in ((-1.45, 0.55), (1.45, 0.6), (-1.5, -0.9), (1.5, -0.8)):
        p.cyl((x, y, 0.8), 0.3, 1.0, "steel_platform", segs=14, bevel=0.04)
        p.cyl((x, y, 1.32), 0.24, 0.06, "paint_blue_dark", segs=14)
    # Pipework over the engine: orange flexible hoses and steel pipes.
    # The orange flexible hoses are ribbed (corrugated), as the sprite draws them.
    for pts, r in (([(-1.2, 0.8, 1.2), (-0.6, 0.5, 1.75), (-0.2, -0.2, 1.65), (-0.1, -0.9, 1.4)], 0.1),
                   ([(1.2, 1.0, 1.2), (0.7, 0.6, 1.75), (0.3, -0.2, 1.65), (0.15, -0.9, 1.4)], 0.1),
                   ([(-0.3, -0.5, 1.8), (-0.25, -1.4, 1.5), (-0.4, -1.9, 1.0)], 0.08),
                   ([(0.3, -0.5, 1.8), (0.35, -1.4, 1.5), (0.5, -1.9, 1.0)], 0.08),
                   ([(1.25, 0.1, 1.3), (1.0, -0.15, 1.7), (0.6, -0.2, 1.65)], 0.09)):
        sk.hose(p, pts, r, "copper_dull", segs=6, rib=0.1, smooth=3)
    for pts in (([(-1.3, -0.5, 1.1), (-0.9, -1.0, 1.0), (-0.5, -1.4, 0.9)]),
                ([(1.3, -0.3, 1.1), (0.9, -1.0, 1.0), (0.5, -1.4, 0.9)])):
        p.pipe(pts, 0.07, "steel_dark", segs=8)
    # A cream bracket band across the engine's south end, the chambers hung from it.
    p.slab(-1.35, -2.25, 0.1, 1.35, -1.6, 1.2, "paint_platform", bevel=0.06)
    detail.rivet_line(p, (-1.25, -2.26, 1.05), (1.25, -2.26, 1.05), 14, "Y")
    detail.rivet_line(p, (-1.25, -1.7, 1.21), (1.25, -1.7, 1.21), 14, "Z")
    for x in (-0.95, -0.5, 0.45, 0.9):
        p.slab(x - 0.012, -2.27, 0.2, x + 0.012, -2.24, 1.15, "steel_dark")
    for sx in (-1, 1):   # the dark valve blocks on the band's corners
        p.slab(sx * 1.05 - 0.2, -2.1, 1.15, sx * 1.05 + 0.2, -1.7, 1.45, "steel_dark", bevel=0.04)
        p.cyl((sx * 1.05, -1.9, 1.5), 0.1, 0.12, "steel_light", segs=8)
    # The sprite's engine is low (about a tile high): built at the old proportions, squashed.
    p.transform(S(1.0, 1.0, 0.6))
    # The bell, built along -y from its throat and tilted up 20 degrees (the sprite looks right
    # into its mouth): it flares from 0.9 to 1.9 tiles over 2 tiles, ribbed outside and in.
    bell = Part()
    n, length = 7, 2.0

    def rad(s):
        return 0.9 + 1.0 * s ** 1.6

    for i in range(n):
        s0, s1 = i / n, (i + 1) / n
        ya, yb = -length * s0, -length * s1
        bell.cyl((0, (ya + yb) / 2, 0), rad(s1), ya - yb, "steel_black", segs=32, axis="Y", radius_top=rad(s0),
                 caps=False)
        bell.cyl((0, (ya + yb) / 2, 0), rad(s1) - 0.07, ya - yb, "soot_deep", segs=32, axis="Y",
                 radius_top=rad(s0) - 0.07, caps=False)
        band = Part()
        band.ring_band((0, 0), rad(s1) - 0.07, rad(s1) + 0.06, -0.05, 0.05, 0, 360, "steel_dark", segs=32)
        bell.add_part(band, T(0, yb, 0) @ R("X", 90))
    # Ribs down the inside of the mouth.
    for k in range(24):
        a = 2 * math.pi * k / 24
        bell.beam((math.cos(a) * 1.25, -0.9, math.sin(a) * 1.25), (math.cos(a) * 1.8, -1.95, math.sin(a) * 1.8),
                  0.06, 0.08, "steel_dark")
    bell.cyl((0, 0.1, 0), 0.9, 0.25, "steel_dark", segs=32, axis="Y")
    tilt = T(0, -3.07, -0.98) @ R("X", -20)
    bell.transform(tilt)
    p.add_part(bell)
    # Combustion chambers round the mouth, leaning down and out: purple-grey, scorched blue at
    # their ends. The three over the mouth stop at its upper rim, as the sprite draws them, clear
    # of the plume streaming out below them (they used to reach into the middle of the mouth).
    d = Vector((0.0, -0.6, -0.8))
    chambers = []
    for x, start, length_ in ((-0.95, (-3.9, 1.3), 0.72), (-0.05, (-3.9, 1.35), 0.72), (0.9, (-3.9, 1.3), 0.72),
                              (-1.7, (-4.3, 0.2), 1.9), (1.7, (-4.3, 0.2), 1.9),
                              (-0.8, (-5.45, -1.6), 0.4), (0.45, (-5.45, -1.6), 0.4)):
        p0 = Vector((x, start[0], start[1]))
        p1 = p0 + d * length_
        p.tube(p0, p1, 0.24, "steel_platform", segs=10, radius_top=0.3)
        p.tube(p1 - d * 0.25, p1, 0.31, "steel_dark", segs=10)
        chambers.append(p1)
    # A sloping mount from the engine's south end up onto the bell, cream brackets round the
    # chambers' tops.
    p.side_prism([(-3.95, 0.9), (-3.75, 1.4), (-2.2, 0.75), (-2.2, 0.1), (-3.2, 0.1)], -1.75, 1.75, "steel_dark",
                 bevel=0.04)
    for x in (-0.95, -0.05, 0.9):
        p.box((x, -3.55, 1.35), (0.62, 0.55, 0.45), "paint_platform", bevel=0.05, matrix=None)
    for sx in (-1, 1):
        p.beam((sx * 1.7, -2.9, 0.3), (sx * 1.75, -4.2, 0.1), 0.3, 0.2, "steel_dark")
    # Hoses from the engine's south end down to the chambers.
    for x in (-0.95, -0.05, 0.9):
        p.pipe([(x * 0.8, -2.2, 0.5), (x, -3.3, 1.1), (x, -3.85, 1.3)], 0.08, "steel_dark", segs=8)
    # The exhaust: a blue glow deep in the throat and at the chambers' ends, lit only while the
    # thruster fires (dark when idle).
    flame = Part("anim_glow_flame")
    disc = Part()
    disc.cyl((0, -0.25, 0), 0.82, 0.04, "flame_blue", segs=24, axis="Y")
    disc.transform(tilt)
    flame.add_part(disc)
    for c in chambers:
        flame.tube(c, c + d * 0.04, 0.26, "flame_blue", segs=10)
    # The plume: from inside the bell, where it is 2.3 wide (under the chambers' tips), streaming
    # level to the south as Factorio's light sheet draws it (about 5 tiles past the mouth), narrowing.
    plume = Part("anim_glow_plume")
    start = tilt @ Vector((0, -1.3, 0))
    plume.tube(start, start + Vector((0, -5.0, 0)), 1.15, "plume_flame", segs=24, radius_top=0.75, caps=False)
    plume.tube(start, start + Vector((0, -3.8, 0)), 0.65, "plume_core", segs=16, radius_top=0.12, caps=False)
    return [p, flame, plume]


# ---------------------------------------------------------------------------------------------
# Asteroid collector.

# Where the grabber head rests (on the intake) and the chain's links are stowed (inside the
# intake housing); the client (collectors.gd) reads both from the parts' pivots.
HEAD_REST = (0.02, 1.5, 1.15)
LINK_REST = (0.02, 1.47, 0.5)
# 24 links of about 0.5 tiles reach past the catch circle's far edge (12.5 tiles from the centre).
LINK_NAMES = "abcdefghijklmnopqrstuvwx"


@model("asteroid-collector")
def asteroid_collector():
    """Factorio's asteroid collector: a grey steel machine on the deck's edge, facing out into
    space (north). A tall housing with a rounded hood at the back holds the arm's reel; stacked
    gear wheels stand either side, an open bay of gears at the front, flexible pipes curling round
    its foot. The arm's grabber head rests at the intake on the north edge. A chute hangs off the
    edge below the intake.

    Moving parts, driven by the client's collectors.gd from the mod's `acol`: the grabber head
    (anim_reach_collector_head), its two fingers (anim_reach_collector_claw_l and _r) and the 24
    links of its chain (anim_reach_collector_link_a to _x). The head flies out to an asteroid
    chunk, the fingers close on it and the chain strings out behind, bending from the intake
    towards the head, then everything is pulled back in."""
    p = Part()
    p.slab(-1.42, -1.42, 0.0, 1.42, 1.42, 0.18, "steel_dark", bevel=0.04)
    # Main housing, its hood rounded over the top, a lid plate on it.
    hood = Part()
    hood.slab(-0.72, -0.35, 0.15, 0.78, 1.35, 1.2, "steel_platform", bevel=0.06)
    hood.cyl((0.03, 0.5, 1.2), 0.8, 1.7, "steel_platform", segs=18, axis="Y", bevel=0.05)
    p.add_part(hood)
    p.slab(-0.4, 0.2, 1.85, 0.45, 1.15, 1.98, "steel_light", bevel=0.03)
    p.slab(-0.55, -0.4, 1.35, 0.6, -0.3, 1.75, "steel_light", bevel=0.03)
    # The hood's riveted seams and bands (the sprite's plated housing), the lid plate's rivets, a
    # small toothed wheel under the hood's south edge, red and green wires over the top.
    for y in (-0.2, 0.5, 1.2):
        p.cyl((0.03, y, 1.2), 0.815, 0.05, "steel_dark", segs=18, axis="Y")
        detail.rivet_line(p, (-0.6, y, 1.83), (0.66, y, 1.83), 4, "Z")
    rivet_rect(p, -0.4, 0.2, 0.45, 1.15, 1.985, step=0.28, sides="sn")
    detail.rivet_line(p, (-0.5, -0.41, 1.7), (0.55, -0.41, 1.7), 6, "Y")
    detail.slots(p, (-0.55, -0.4, 1.35), (0.6, -0.3, 1.75), "-y", 3)
    wheel = Part()
    detail.gear(wheel, (0, 0), 0.2, -0.03, 0.03, "steel_light", teeth=14, holes=4)
    p.add_part(wheel, T(0.05, -0.43, 1.2) @ R("X", 90))
    detail.cable(p, [(-0.7, 0.9, 1.3), (-0.45, 0.4, 1.95), (-0.1, 0.0, 1.95), (0.2, -0.35, 1.6)], 0.022, "wire_green")
    # Intake at the north edge, the lip over the edge, the grabber head folded into it.
    p.slab(-0.6, 1.2, 0.1, 0.65, 1.75, 0.9, "steel_dark", bevel=0.04)
    p.slab(-0.7, 1.55, 0.6, 0.75, 1.8, 1.0, "steel_platform", bevel=0.04)
    # The grabber head (Factorio's arm_head_animation, 5 frames from closed to open): a palm
    # with a pale spike pointing out and two curved fingers lined in brass either side of it,
    # closed at rest. The fingers are their own parts so the client can open them.
    head = Part("anim_reach_collector_head", pivot=HEAD_REST)
    head.box((0, -0.05, 0), (0.4, 0.3, 0.28), "steel_arm", bevel=0.05)
    head.box((0, -0.05, -0.13), (0.3, 0.24, 0.06), "steel_dark", bevel=0.02)
    head.cyl((0, 0.32, 0.02), 0.075, 0.5, "steel_arm", segs=8, axis="Y", radius_top=0.02)
    head.box((0, 0.12, 0.02), (0.12, 0.16, 0.12), "steel_dark", bevel=0.02)
    head.transform(T(*HEAD_REST))
    claws = []
    for side, sx in (("l", -1), ("r", 1)):
        claw = Part("anim_reach_collector_claw_" + side, pivot=(HEAD_REST[0] + sx * 0.17, HEAD_REST[1] + 0.05, HEAD_REST[2]))
        knuckle = (sx * 0.17, 0.05, 0.0)
        tip = (sx * 0.06, 0.52, 0.03)
        bend = (sx * 0.24, 0.3, 0.02)
        claw.beam(knuckle, bend, 0.09, 0.13, "steel_arm", bevel=0.02)
        claw.beam(bend, tip, 0.07, 0.11, "steel_arm", bevel=0.02)
        claw.beam((sx * 0.13, 0.12, 0.0), (sx * 0.17, 0.3, 0.01), 0.025, 0.09, "brass_arm")
        claw.beam((sx * 0.17, 0.3, 0.01), (sx * 0.07, 0.48, 0.02), 0.025, 0.08, "brass_arm")
        claw.transform(T(*HEAD_REST))
        claws.append(claw)
    # The chain's links (Factorio's arm_link, a pale vertebra with a knuckle, about half a tile),
    # stowed inside the intake housing at rest; the client strings them out behind the head.
    links = []
    for name in LINK_NAMES:
        link = Part("anim_reach_collector_link_" + name, pivot=LINK_REST)
        link.box(LINK_REST, (0.36, 0.34, 0.24), "steel_arm", bevel=0.05)
        link.box((LINK_REST[0], LINK_REST[1] - 0.04, LINK_REST[2] + 0.1), (0.3, 0.2, 0.08), "steel_dark", bevel=0.02)
        link.cyl((LINK_REST[0], LINK_REST[1] + 0.15, LINK_REST[2] + 0.04), 0.07, 0.38, "steel_arm", segs=8, axis="X")
        links.append(link)
    # Under the intake a housing hangs off the deck's edge, rust-red vents down its sides (the
    # sprites' middle and bottom layers), and at its foot a scoop juts out, open to the top: the
    # asteroid chunks come in there from below the platform.
    # It is deepest under the deck edge and shallower out at its face. All four pictures are cut
    # at the same line on the screen, but they don't agree on one shape: facing east or west the
    # chute reaches that line 1 to 2 tiles out, facing south it stops at it already at its face.
    # This depth is the compromise between them.
    p.side_prism([(0.55, 0.15), (2.1, 0.15), (2.1, -1.8), (1.5, -2.45), (1.0, -2.75), (0.55, -2.0)], -0.85, 0.85,
                 "steel_dark", bevel=0.05)
    # Rust-brown plates banded down its face, as the sprite's bottom layer.
    for z0, z1 in ((-0.25, -0.75), (-0.85, -1.3), (-1.4, -1.75)):
        p.slab(-0.82, 2.1, z1, 0.82, 2.13, z0, "rust_brown")
        detail.rivet_line(p, (-0.75, 2.135, z0 - 0.05), (0.75, 2.135, z0 - 0.05), 4, "Y")
    for sx in (-1, 1):
        p.slab(sx * 0.85, 1.1, -1.5, sx * 0.9, 2.0, -0.3, "rust_brown")
        for k in range(4):
            for j in range(3):
                p.cyl((sx * 0.91, 1.3 + j * 0.27, -0.6 - k * 0.27), 0.06, 0.02, "soot_deep", segs=6, axis="X")
    # Its top is the open mouth (dark), framed, with louvred plates on brackets either side.
    p.slab(-0.7, 1.5, 0.15, 0.7, 2.0, 0.17, "soot_deep")
    p.slab(-0.85, 1.95, 0.1, 0.85, 2.12, 0.3, "steel_light", bevel=0.03)
    for sx in (-1, 1):
        p.slab(sx * 0.85, 1.35, -0.95, sx * 1.22, 1.95, 0.35, "steel_light", bevel=0.03)
        for k in range(4):
            p.slab(sx * 1.22, 1.42 + k * 0.13, -0.8, sx * 1.24, 1.5 + k * 0.13, 0.25, "soot_deep")
    scoop = Part()
    scoop.slab(-0.9, 1.95, -1.55, 0.8, 2.4, -1.35, "steel_platform", bevel=0.04)
    for sx in (-0.9, 0.68):
        scoop.slab(sx, 1.95, -1.55, sx + 0.12, 2.4, -0.65, "steel_platform", bevel=0.03)
    scoop.slab(-0.9, 2.28, -1.55, 0.8, 2.4, -0.85, "steel_light", bevel=0.03)
    scoop.slab(-0.78, 1.95, -1.36, 0.68, 2.28, -1.34, "soot_deep")
    p.add_part(scoop)
    p.slab(-0.85, 2.1, -1.2, 0.75, 2.12, -0.2, "soot_deep")
    # Gear stacks either side: discs on a shaft, in a frame.
    for sx in (-1, 1):
        x = sx * 1.1
        p.slab(x - 0.25, -1.1, 0.15, x + 0.25, 1.15, 0.7, "steel_dark", bevel=0.03)
        for k, y in enumerate((-0.85, -0.45, -0.05, 0.35)):
            p.cyl((x, y, 1.0), 0.36 - 0.02 * k, 0.18, "steel_platform", segs=16, axis="Y", bevel=0.02)
            p.cyl((x, y, 1.0), 0.38 - 0.02 * k, 0.05, "steel_black", segs=16, axis="Y")
        p.cyl((x, -0.25, 1.0), 0.07, 1.5, "steel_light", segs=8, axis="Y")
        p.slab(x * 0.86 - 0.1, 1.15, 0.15, x * 0.86 + 0.1, 1.5, 1.2, "steel_platform", bevel=0.03)
        p.cyl((x * 0.86, 1.32, 1.2), 0.17, 0.25, "steel_light", segs=12, axis="X")
    # Open bay of gears at the front.
    p.slab(-0.7, -1.3, 0.15, 0.75, -0.35, 0.35, "soot_deep")
    # Toothed wheels with cut-outs, a spiral-cut bevel gear on its shaft between them (the
    # sprite's open gear bay).
    for x, z, r in ((-0.25, 0.55, 0.25), (0.3, 0.6, 0.3), (0.0, 0.95, 0.22)):
        g = Part()
        detail.gear(g, (0, 0), r, -0.06, 0.06, "steel_light", teeth=12, holes=4, segs=16)
        p.add_part(g, T(x, -0.85, z) @ R("X", 90))
    p.cyl((0.02, -0.75, 0.75), 0.06, 0.8, "steel_dark", segs=8, axis="Y")
    for k in range(4):
        p.cyl((0.02, -0.55 - 0.1 * k, 0.75), 0.17 - 0.02 * k, 0.05, "steel_light", segs=10, axis="Y")
    detail.rivet_line(p, (-0.66, -1.36, 0.95), (-0.66, -1.36, 0.25), 4, "Y")
    detail.rivet_line(p, (0.71, -1.36, 0.95), (0.71, -1.36, 0.25), 4, "Y")
    p.slab(-0.72, -1.35, 0.15, -0.6, -0.35, 1.0, "steel_platform", bevel=0.02)
    p.slab(0.65, -1.35, 0.15, 0.78, -0.35, 1.0, "steel_platform", bevel=0.02)
    # Flexible pipes round the foot.
    sk.hose(p, [(-1.3, 0.3, 0.3), (-1.3, -0.6, 0.3), (-1.0, -1.25, 0.25), (-0.6, -1.35, 0.25)], 0.11, "steel_dark",
            segs=6, rib=0.12, smooth=3)
    sk.hose(p, [(0.45, -1.35, 0.25), (1.0, -1.3, 0.3), (1.3, -0.8, 0.35)], 0.11, "steel_dark", segs=6, rib=0.12, smooth=3)
    return [p, head] + claws + links


# ---------------------------------------------------------------------------------------------
# Crusher.

@model("crusher")
def crusher():
    """Factorio's crusher (2x3), as its north picture draws it: a light steel frame round a big
    open hopper, two toothed rolls lying east-west in it; on the north end a motor with a drum
    (east) and an orange coiled hose (west) either side of a block; a dark drum lies along the
    east side, copper pipes run down the west; a gearbox with a grille and a box on the south
    face, the frame's south corners cut off. Factorio draws the same picture facing north and
    south (and one for east and west), so turned south the motor ends up in the south.

    Moving parts: the two rolls (anim_roll_crusher_n, anim_roll_crusher_s) turn about their
    east-west shafts towards each other while it works, as the teeth crawl in Factorio's sheet
    (48 frames at 0.5: a third of a turn, two teeth, every 1.6 s)."""
    p = Part()
    top = 0.8
    # Lower body, its south corners chamfered, and the rim round the hopper.
    body = Part()
    body.prism([(-0.85, -1.15), (-0.6, -1.4), (0.55, -1.4), (0.8, -1.2), (0.82, 1.05), (-0.85, 1.05)], 0.0, 0.12,
               "steel_platform", bevel=0.04)
    p.add_part(body)
    for x0, y0, x1, y1 in ((-0.85, -1.3, 0.82, -1.18), (-0.85, 0.82, 0.82, 1.05), (-0.85, -1.2, -0.66, 0.85),
                           (0.66, -1.2, 0.82, 0.85)):
        p.slab(x0, y0, 0.1, x1, y1, top, "steel_platform", bevel=0.04)
    p.slab(-0.66, -1.2, 0.1, 0.66, 0.84, 0.14, "soot_deep")
    # The two toothed rolls: blocky six-sided discs on a shaft, the teeth staggered.
    rolls = []
    for k, (y, name) in enumerate(((0.5, "n"), (-0.38, "s"))):
        roll = Part("anim_roll_crusher_" + name, pivot=(0, y, 0.45))
        roll.cyl((0, y, 0.45), 0.22, 1.3, "steel_black", segs=10, axis="X")
        for j in range(6):
            x = -0.55 + j * 0.22
            disc = Part()
            disc.cyl((0, 0, 0), 0.4, 0.15, "steel_dark", segs=6, axis="X", bevel=0.02)
            roll.add_part(disc, T(x, y, 0.45) @ R("X", 30 * ((j + k) % 2)))
        rolls.append(roll)
    # North end: the motor and its drum (east), a block, the coiled hose (west).
    p.slab(0.26, 1.0, 0.1, 0.98, 1.38, 1.1, "steel_light", bevel=0.05)
    p.cyl((0.62, 1.2, 1.15), 0.18, 0.7, "steel_dark", segs=14, axis="X", bevel=0.02)
    p.slab(0.38, 0.98, 0.5, 0.82, 1.02, 0.95, "steel_dark")
    p.slab(-0.2, 1.0, 0.1, 0.28, 1.35, 1.0, "steel_platform", bevel=0.04)
    for x in (-0.08, 0.05, 0.18):
        p.cyl((x, 1.0, 0.75), 0.04, 0.04, "soot_deep", segs=8, axis="Y")
    p.pipe([(-0.5, 0.95, 0.8), (-0.45, 1.15, 1.15), (-0.28, 1.25, 1.2), (-0.15, 1.15, 0.95)], 0.15, "copper_dull", segs=10)
    p.cyl((-0.42, 1.0, 0.85), 0.2, 0.15, "steel_light", segs=12)
    # A dark drum lies along the east side, banded.
    p.cyl((0.84, -0.15, 0.32), 0.24, 1.9, "steel_black", segs=16, axis="Y", bevel=0.03)
    for y in (-0.95, -0.15, 0.65):
        p.cyl((0.84, y, 0.32), 0.26, 0.08, "steel_dark", segs=16, axis="Y")
    # Copper pipes down the west side.
    p.pipe([(-0.6, 1.3, 0.9), (-0.88, 1.15, 0.8), (-0.9, 0.2, 0.6), (-0.86, -0.95, 0.4)], 0.07, "copper_dull", segs=8)
    p.pipe([(-0.85, 0.9, 0.35), (-0.88, -1.0, 0.3)], 0.06, "rust_brown", segs=8)
    # A rusty pipe runs down the east side past the flywheel.
    p.pipe([(0.9, 1.4, 0.95), (1.0, 1.1, 0.85), (1.02, -0.9, 0.5)], 0.07, "rust_brown", segs=8)
    # South face: the gearbox with its grille, a box east of it.
    p.slab(-0.3, -1.42, 0.1, 0.25, -1.15, 0.9, "steel_light", bevel=0.04)
    for k in range(5):
        p.slab(-0.25 + k * 0.1, -1.44, 0.2, -0.2 + k * 0.1, -1.42, 0.55, "soot_deep")
    p.slab(0.27, -1.4, 0.1, 0.7, -1.15, 0.95, "steel_platform", bevel=0.04)
    p.slab(0.35, -1.41, 0.45, 0.55, -1.4, 0.62, "soot_deep")
    return [p] + rolls


@model("crusher-east")
def crusher_east():
    """The crusher facing east or west (3x2), as Factorio's horizontal picture draws it: not a
    turn of the north one but its own render. The hopper fills the west two thirds, its two
    toothed rolls lying north-south; the east end is machinery: a tall grey housing with a coil
    spring and a motor, an orange coiled hose curling down its south-east corner, a grey box at
    its foot; a toothed chain runs over the north rim from a gearbox plate to the housing; pipes
    and a valve box along the south face, a grey box at the south-west, its corner cut.

    Moving parts: the two rolls (anim_roll_crusher_w, anim_roll_crusher_e) turn about their
    north-south shafts towards each other while it works."""
    p = Part()
    top = 0.8
    body = Part()
    body.prism([(-1.45, -0.75), (-1.2, -1.0), (0.95, -1.0), (1.45, -0.85), (1.45, 0.95), (-1.45, 0.95)], 0.0, 0.12,
               "steel_platform", bevel=0.04)
    p.add_part(body)
    # The hopper's rim: west wall, north and south rails, the wall between hopper and machinery.
    for x0, y0, x1, y1 in ((-1.45, -0.8, -1.25, 0.95), (-1.45, 0.75, 0.62, 0.95), (-1.3, -0.95, 0.62, -0.75),
                           (0.45, -0.95, 0.65, 0.95)):
        p.slab(x0, y0, 0.1, x1, y1, top, "steel_platform", bevel=0.04)
    p.slab(-1.25, -0.75, 0.1, 0.45, 0.75, 0.14, "soot_deep")
    detail.rivet_line(p, (-1.35, 0.85, top + 0.005), (0.55, 0.85, top + 0.005), 9, "Z")
    detail.rivet_line(p, (-1.2, -0.85, top + 0.005), (0.55, -0.85, top + 0.005), 9, "Z")
    # The two toothed rolls, lying north-south.
    rolls = []
    for k, (x, name) in enumerate(((-0.82, "w"), (0.02, "e"))):
        roll = Part("anim_roll_crusher_" + name, pivot=(x, 0, 0.34))
        roll.cyl((x, 0, 0.34), 0.17, 1.45, "steel_black", segs=10, axis="Y")
        for j in range(6):
            y = -0.6 + j * 0.24
            disc = Part()
            disc.cyl((0, 0, 0), 0.32, 0.16, "steel_dark", segs=6, axis="Y", bevel=0.02)
            roll.add_part(disc, T(x, y, 0.34) @ R("Y", 30 * ((j + k) % 2)))
        rolls.append(roll)
    # East end: the tall housing, its coil spring and motor on the west face, a lid on top.
    p.slab(0.65, -0.55, 0.1, 1.42, 0.95, 1.1, "steel_light", bevel=0.06)
    p.slab(0.7, 0.2, 1.1, 1.35, 0.9, 1.6, "steel_platform", bevel=0.04)
    p.cyl((1.02, 0.55, 1.65), 0.16, 0.12, "steel_dark", segs=12)
    for k in range(6):
        p.cyl((0.95, -0.05, 0.3 + 0.1 * k), 0.17, 0.035, "steel_light", segs=12)
    p.cyl((0.95, -0.05, 0.55), 0.09, 0.6, "steel_dark", segs=8)
    p.cyl((1.2, 0.5, 0.75), 0.2, 0.5, "steel_dark", segs=14, axis="X", bevel=0.02)
    detail.slots(p, (0.75, -0.57, 0.5), (1.35, -0.53, 0.95), "-y", 4, mat="soot_deep", along=0)
    # The orange coiled hose curls down the south-east corner to the floor.
    hose = [(1.32, 0.1, 0.85), (1.42, -0.25, 0.7), (1.38, -0.6, 0.45), (1.2, -0.85, 0.25), (0.8, -0.95, 0.15)]
    p.pipe(hose, 0.13, "copper_dull", segs=10)
    for k, q in enumerate([(1.4, -0.2, 0.68), (1.42, -0.42, 0.56), (1.33, -0.65, 0.4), (1.15, -0.85, 0.24),
                           (0.92, -0.93, 0.17)]):
        p.cyl(q, 0.145, 0.05, "rust_brown", segs=10, axis="X" if k < 2 else "Y")
    p.slab(0.95, -1.0, 0.1, 1.42, -0.6, 0.5, "steel_light", bevel=0.04)
    # The chain over the north rim, from the gearbox plate to the housing.
    p.slab(-0.6, 0.75, top, 0.1, 1.0, top + 0.12, "steel_light", bevel=0.03)
    for k in range(10):
        p.box((-0.05 + k * 0.08, 0.88, top + 0.15 + 0.7 * min(k / 3, 1)), (0.07, 0.14, 0.05), "rust_brown")
    # Pipes and a valve box along the south face, a grey box at the south-west.
    p.pipe([(-1.15, -1.02, 0.3), (0.85, -1.02, 0.3)], 0.06, "copper_dull", segs=8)
    p.pipe([(-1.0, -1.05, 0.5), (-0.2, -1.05, 0.5), (0.0, -0.95, 0.65)], 0.05, "rust_brown", segs=8)
    for x in (-0.6, -0.1, 0.4):
        p.cyl((x, -1.05, 0.3), 0.09, 0.08, "steel_light", segs=10, axis="Y")
    p.slab(-0.45, -1.02, 0.1, 0.15, -0.95, 0.42, "steel_dark")
    # Below the south rail the picture runs a low strip of gears and pipe ends out past the footprint.
    p.slab(-0.8, -1.15, 0.0, 0.75, -0.95, 0.3, "rust_brown", bevel=0.03)
    for x in (-0.55, -0.15, 0.3):
        p.cyl((x, -1.12, 0.2), 0.12, 0.08, "steel_dark", segs=8, axis="Y")
    p.prism([(-1.45, -0.75), (-1.25, -0.95), (-0.85, -0.95), (-0.85, -0.2), (-1.45, -0.2)], 0.1, 0.72,
            "steel_light", bevel=0.04)
    # Copper pipes up the west end.
    p.pipe([(-1.4, -0.6, 0.35), (-1.4, 0.6, 0.45), (-1.3, 0.88, 0.6)], 0.06, "copper_dull", segs=8)
    # Fitted to the picture: it stands lower than the north one's (its rim three quarters as high).
    p.transform(S(1, 1, 0.75))
    return [p] + rolls


# ---------------------------------------------------------------------------------------------
# Asteroids (movers): small, medium, big and huge of each kind.

kit.MATERIALS.update({
    "rock_metallic": ("4f6676", 0.6, 0.45, None, 0),       # blue-grey metal-bearing rock
    "rock_metallic_vein": ("a8602e", 0.75, 0.35, None, 0),  # its orange rust patches
    "rock_carbonic": ("57505c", 0.9, 0.05, None, 0),        # purple-grey, sooty
    "rock_carbonic_vein": ("b7b46a", 0.7, 0.05, None, 0),   # yellowish specks
    "rock_oxide": ("47666f", 0.3, 0.1, None, 0),            # blue-green ice crystals
    "rock_oxide_vein": ("8fb2bd", 0.25, 0.1, None, 0),      # their pale edges
    "rock_promethium": ("7c2a30", 0.6, 0.2, None, 0),       # deep red block
    "rock_promethium_vein": ("cfc8c8", 0.5, 0.1, None, 0),  # white crust along its seams
})
ASTEROID_KINDS = ("metallic", "carbonic", "oxide", "promethium")
ASTEROID_SIZES = ("small", "medium", "big", "huge")

# Each asteroid's outline in its sprite (the first colour variation, which the client's first
# frame matches): the distance from the rock's centre to its edge, in hundredths of a tile, at 48
# angles counter-clockwise from screen right. Measured from the sheets' alpha; the rock is then
# built so that Factorio's camera sees exactly this outline (asteroids tumble in the game, so one
# shape per kind and size, its face towards the camera as the sprite shows it).
ASTEROID_OUTLINES = {
    ("metallic", "small"): (83, 80, 65, 59, 54, 55, 57, 55, 52, 51, 51, 61, 64, 73, 80, 84, 81, 78, 80, 86, 97, 100, 100,
                            98, 88, 83, 72, 67, 69, 74, 92, 95, 92, 84, 80, 83, 84, 84, 83, 87, 94, 104, 116, 118, 112,
                            101, 92, 89),
    ("metallic", "medium"): (112, 141, 166, 170, 169, 169, 156, 147, 146, 142, 140, 145, 145, 142, 146, 147, 146, 142, 166,
                             166, 159, 173, 173, 145, 139, 146, 168, 172, 170, 155, 168, 169, 177, 177, 173, 167, 148, 106,
                             59, 59, 66, 70, 70, 70, 69, 74, 88, 95),
    ("metallic", "big"): (240, 229, 223, 228, 230, 236, 244, 252, 252, 242, 239, 217, 201, 196, 191, 211, 232, 236, 254,
                          262, 294, 290, 262, 255, 244, 238, 231, 209, 195, 195, 187, 181, 190, 227, 236, 246, 249, 264,
                          273, 279, 281, 287, 287, 283, 283, 271, 267, 250),
    ("metallic", "huge"): (328, 334, 334, 313, 380, 427, 495, 546, 580, 580, 529, 550, 550, 502, 475, 489, 492, 449, 449,
                           434, 427, 425, 412, 389, 373, 382, 395, 536, 620, 650, 656, 647, 622, 619, 477, 430, 375, 366,
                           346, 400, 510, 514, 548, 548, 506, 539, 558, 382),
    ("carbonic", "small"): (86, 78, 73, 69, 64, 62, 60, 59, 62, 64, 71, 75, 86, 86, 87, 87, 81, 78, 77, 76, 71, 64, 59, 57,
                            53, 54, 54, 54, 54, 53, 52, 53, 54, 57, 60, 62, 67, 74, 84, 88, 90, 93, 97, 101, 101, 99, 95,
                            91),
    ("carbonic", "medium"): (175, 178, 178, 161, 177, 177, 175, 175, 174, 175, 174, 167, 167, 161, 144, 136, 122, 109, 89,
                             81, 88, 104, 123, 138, 155, 169, 173, 176, 193, 199, 201, 200, 197, 177, 159, 154, 136, 133,
                             134, 134, 129, 120, 113, 107, 115, 116, 134, 162),
    ("carbonic", "big"): (174, 212, 262, 274, 274, 281, 286, 281, 259, 248, 236, 242, 246, 246, 237, 239, 233, 225, 213,
                          194, 186, 186, 183, 225, 249, 262, 279, 281, 279, 254, 229, 199, 194, 225, 245, 278, 280, 276,
                          275, 268, 249, 223, 199, 174, 167, 167, 162, 158),
    ("carbonic", "huge"): (340, 525, 593, 611, 636, 641, 635, 604, 570, 584, 584, 527, 488, 488, 484, 477, 510, 532, 568,
                           573, 587, 599, 599, 575, 499, 452, 490, 582, 630, 648, 668, 668, 657, 629, 581, 557, 544, 480,
                           435, 432, 430, 404, 394, 386, 360, 364, 363, 355),
    ("oxide", "small"): (45, 52, 56, 60, 68, 82, 103, 98, 77, 59, 50, 42, 39, 34, 30, 28, 28, 28, 28, 28, 30, 32, 34, 38,
                         44, 52, 58, 62, 68, 80, 99, 96, 88, 76, 61, 50, 43, 38, 36, 34, 32, 31, 30, 31, 32, 34, 36, 41),
    ("oxide", "medium"): (103, 116, 123, 162, 178, 183, 185, 183, 177, 165, 165, 155, 144, 125, 114, 109, 108, 108, 111,
                          116, 125, 138, 145, 156, 161, 165, 152, 97, 126, 152, 163, 169, 168, 167, 155, 138, 116, 102, 92,
                          85, 81, 79, 78, 79, 81, 84, 88, 95),
    ("oxide", "big"): (246, 236, 232, 232, 232, 236, 247, 248, 248, 238, 207, 190, 180, 161, 147, 140, 135, 137, 144, 151,
                       165, 173, 187, 199, 219, 234, 253, 274, 277, 270, 271, 271, 266, 255, 251, 245, 221, 204, 197, 196,
                       202, 209, 214, 217, 224, 232, 247, 249),
    ("oxide", "huge"): (564, 570, 564, 503, 444, 404, 334, 334, 332, 326, 348, 387, 417, 432, 514, 546, 600, 676, 676, 620,
                        478, 415, 380, 478, 534, 538, 541, 541, 513, 493, 473, 458, 431, 408, 420, 424, 443, 470, 506, 548,
                        566, 552, 533, 532, 530, 539, 539, 527),
    ("promethium", "small"): (67, 59, 55, 55, 55, 56, 59, 63, 70, 70, 72, 77, 75, 72, 66, 66, 67, 69, 70, 75, 77, 77, 76,
                              65, 67, 66, 57, 57, 55, 58, 60, 64, 70, 77, 82, 76, 69, 64, 60, 59, 59, 62, 64, 66, 66, 69,
                              71, 68),
    ("promethium", "medium"): (127, 112, 110, 111, 116, 124, 152, 152, 137, 134, 125, 124, 123, 123, 130, 141, 155, 161,
                               159, 149, 141, 134, 137, 139, 141, 143, 147, 143, 116, 114, 114, 109, 127, 145, 147, 143,
                               130, 136, 136, 128, 129, 133, 137, 141, 142, 139, 130, 127),
    ("promethium", "big"): (227, 217, 192, 169, 169, 176, 188, 202, 220, 235, 240, 242, 236, 231, 232, 235, 248, 259, 259,
                            214, 162, 125, 129, 176, 261, 261, 252, 249, 248, 262, 266, 273, 273, 257, 249, 242, 231, 225,
                            231, 247, 254, 264, 270, 270, 268, 262, 261, 242),
    ("promethium", "huge"): (502, 520, 534, 559, 575, 567, 532, 488, 551, 552, 512, 428, 410, 410, 415, 444, 488, 495, 495,
                             430, 397, 391, 381, 394, 548, 534, 557, 582, 582, 550, 518, 507, 476, 400, 384, 436, 499, 511,
                             524, 530, 524, 511, 493, 423, 391, 370, 389, 389),
}


def _outline_radius(outline, t):
    """The outline's radius (tiles) at screen angle `t`, interpolated round the circle."""
    n = len(outline)
    f = (t / (2 * math.pi)) % 1.0 * n
    i = int(f)
    a = f - i
    return (outline[i % n] * (1 - a) + outline[(i + 1) % n] * a) / 100.0


def _blocks(rng, count, axis=None):
    """The chunks of a faceted face, one per cell round a seed point (in the outline's unit disc):
    (seed x, seed y, height, tilt x, tilt y, crystal axis or None). Promethium's are flat faces
    tilted every way; oxide's are crystals, ridged along an axis near the outline's long one."""
    out = []
    for _ in range(count):
        a, r = rng.uniform(0, 2 * math.pi), math.sqrt(rng.uniform(0, 0.75))
        t, g = rng.uniform(0, 2 * math.pi), rng.uniform(0.5, 1.1)
        ax = None if axis is None else axis + math.radians(rng.uniform(-25, 25))
        out.append((r * math.cos(a), r * math.sin(a), rng.uniform(0.6, 1.1), g * math.cos(t), g * math.sin(t), ax))
    return out


def _block_face(blocks, px, py, stretch):
    """Height of the face at (px, py) and how far it is from the seam with the next cell."""
    best = []
    for cx, cy, h, gx, gy, ax in blocks:
        dx, dy = px - cx, py - cy
        if ax is None:
            d = math.hypot(dx, dy)
            w = h - gx * dx - gy * dy
        else:
            # Crystals: cells long along their axis; a roof of two faces either side of the ridge.
            along = dx * math.cos(ax) + dy * math.sin(ax)
            across = -dx * math.sin(ax) + dy * math.cos(ax)
            d = math.hypot(along / stretch, across)
            w = h - 2.2 * min(abs(across), 0.25) - 0.15 * abs(along)
        best.append((d, w))
    best.sort()
    return best[0][1], (best[1][0] - best[0][0]) if len(best) > 1 else 1.0


def asteroid(kind, size, seed):
    """An asteroid as its sprite draws it, its outline the sprite's: metallic ones lumpy and
    cratered, blue-grey with rust patches; carbonic ones rounded purple-grey lumps flecked yellow;
    promethium ones blocky red chunks of flat faces, crusted white along the seams; oxide ones
    blue-green crystals, their long flat faces meeting in pale edges.

    Built in the camera's frame (u right, v up the screen, w towards the camera) from a sphere:
    each point's (u, v) is stretched to the outline at its angle, so its silhouette from
    Factorio's camera is exactly the outline, and w gives the rock its thickness. Lumps, craters
    and facets only move points along w (scaled by how far from the edge they are), so they shape
    the face without breaking the outline."""
    outline = ASTEROID_OUTLINES[kind, size]
    rng = kit.rng(seed)
    mean = sum(outline) / len(outline) / 100.0
    off = Vector((seed * 3.1, seed * 1.7, seed * 2.3))
    # The outline's long axis (second moments of its points), for the crystals' faces.
    pts = [(r * math.cos(2 * math.pi * i / len(outline)), r * math.sin(2 * math.pi * i / len(outline)))
           for i, r in enumerate(outline)]
    sxx = sum(x * x for x, _ in pts)
    syy = sum(y * y for _, y in pts)
    sxy = sum(x * y for x, y in pts)
    axis = 0.5 * math.atan2(2 * sxy, sxx - syy)
    faceted = kind in ("promethium", "oxide")
    depth = {"metallic": 0.72, "carbonic": 0.78, "promethium": 0.8, "oxide": 0.6}[kind] * mean
    blocks = {}
    if faceted:
        n = {"promethium": {"small": 3, "medium": 5, "big": 8, "huge": 14},
             "oxide": {"small": 1, "medium": 2, "big": 7, "huge": 18}}[kind][size]
        for side in (1, -1):
            blocks[side] = _blocks(rng, n, axis if kind == "oxide" else None)
    craters = []
    if kind in ("metallic", "carbonic"):
        count = {"small": 4, "medium": 7, "big": 10, "huge": 16}[size] * (3 if kind == "metallic" else 1)
        for _ in range(count):
            a, r = rng.uniform(0, 2 * math.pi), math.sqrt(rng.uniform(0, 0.7))
            craters.append((r * math.cos(a), r * math.sin(a), rng.uniform(0.1, 0.28), rng.choice((1, 1, -1))))

    bm = bmesh.new()
    bmesh.ops.create_icosphere(bm, subdivisions=5 if size != "small" else 4, radius=1.0)
    seam = {}
    for v in bm.verts:
        d = v.co.normalized()
        px, py, pz = d.x, d.y, d.z
        side = 1 if pz >= 0 else -1
        rho = math.hypot(px, py)
        t = math.atan2(py, px)
        rad = _outline_radius(outline, t)
        dome = abs(pz)
        tie = 1.0
        if faceted:
            # Each cell's face, rounded off towards the outline by the dome.
            face, tie = _block_face(blocks[side], px, py, 2.5)
            dome = min(dome * 3.5, max(0.0, face), 1.0)
        else:
            q = Vector((px, py, pz)) * 1.4 + off
            lump = noise.noise(q) * 0.22 + noise.noise(q * 2.6) * 0.1 + noise.noise(q * 6.0) * 0.04
            dome *= 1.0 + lump * (1.0 if kind == "carbonic" else 0.8)
            for cx, cy, cr, cs in craters:
                if cs != side:
                    continue
                e = math.hypot(px - cx, py - cy) / cr
                if e < 1.0:
                    # A bowl with a raised rim.
                    dome -= (0.9 * (1 - e * e) - 0.2 * math.exp(-((e - 0.95) / 0.12) ** 2)) * cr
                elif e < 1.3:
                    dome += 0.15 * cr * (1.3 - e) / 0.3
            dome = max(dome, 0.0)
        # Points at the edge stay on the outline; the face rises towards the camera.
        u, vv = px * rad, py * rad
        w = side * dome * depth * (0.6 + 0.4 * rad / mean)
        v.co = Vector((u, vv, w))
        seam[v] = tie
    # From the camera's frame to the model's: v up the screen, w towards the camera.
    up = Vector((0.0, SIN_P, COS_P))
    back = Vector((0.0, -COS_P, SIN_P))
    for v in bm.verts:
        u, vv, w = v.co
        v.co = Vector((u, 0, 0)) + up * vv + back * w
    p = Part()
    if faceted:
        p.sharp_angle = 12.0  # the crystals' faces meet at shallow ridges: shade each face flat
    p.merge(bm, "rock_" + kind)
    # Patches, flecks or seams. Faces are matched to the source by order (merge keeps it).
    vi = p._mat_index("rock_%s_vein" % kind)
    for f, src in zip(p.bm.faces, bm.faces):
        c = src.calc_center_median() / mean
        if faceted:
            hit = min(seam[v] for v in src.verts) < (0.045 if kind == "promethium" else 0.03)
        elif kind == "carbonic":
            hit = noise.noise(c * 11.0 + off) > 0.3
        else:
            hit = noise.noise(c * 1.6 + off) + noise.noise(c * 5.0 - off) * 0.5 > 0.0
        if hit:
            f.material_index = vi
    bm.free()
    return p


for _i, _kind in enumerate(ASTEROID_KINDS):
    for _j, _size in enumerate(ASTEROID_SIZES):
        model("%s-%s-asteroid" % (_size, _kind))(lambda k=_kind, s=_size, seed=_i * 4 + _j + 1: asteroid(k, s, seed))
