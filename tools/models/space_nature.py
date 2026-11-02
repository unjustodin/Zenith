"""Space Age rocks, chimneys and ruins, fitted to their sprites' silhouettes.

Their sprites are single irregular lumps, so instead of placing primitives by hand they are
built from the silhouette Factorio's camera sees (space_profiles.py: per 1/8-tile column, the
runs of the sprite in tiles up the screen):

- `heightfield`: rocks and ruins. Each column's run is a cross-section from the ground at its
  front (the run's bottom edge is where it meets the ground) back over a set depth, its height
  solved so the top of the run is the top of the silhouette; the shape across (dome for rocks,
  steep walls and a flat top for ruins) is a parameter. The cross-sections make one height
  field, jittered for rock, which the client then paints with the sprite.
- `revolve`: chimneys. A cone whose radius at each height is half the silhouette's width at
  that height, with a crater sunk into its top.

Measure a new silhouette with the scratch tool (frame, alpha over 0.75 so the drawn-in shadow
is left out, 1/8-tile columns) the same way: numbers only, nothing from the image is kept.
"""

import math

from mathutils import Vector, noise

import kit
from kit import Part, model
from space_profiles import GLOW, PROFILES, RINGS

SIN_P, COS_P = math.sin(math.radians(48)), math.cos(math.radians(48))

kit.MATERIALS.update({
    "rock_basalt": ("3b3532", 0.95, 0.0, None, 0),
    "rock_basalt_light": ("57504a", 0.95, 0.0, None, 0),
    "lava_glow": ("ff7a22", 0.7, 0.0, "ff5a0a", 2.5),
    "stone_sulfur": ("c2b04a", 0.9, 0.0, None, 0),
    "stone_chimney": ("4a3f38", 0.95, 0.0, None, 0),
    "stone_chimney_cold": ("4d4846", 0.95, 0.0, None, 0),
    "stone_chimney_stain": ("6a4a2a", 0.95, 0.0, None, 0),  # sulfur crust running down the rock
    "concrete_ruin": ("9a6a52", 0.95, 0.0, None, 0),     # Fulgora's ruins are rust-pink brick
    "concrete_ruin_dark": ("6a4a3c", 0.95, 0.0, None, 0),
})


def _solve_height(y_f, depth, top, shape):
    """Height h so that the cross-section's highest point on screen is `top`."""
    ts = [i / 24 for i in range(25)]

    def screen_top(h):
        return max(SIN_P * (y_f + t * depth) + COS_P * h * shape(t) for t in ts)

    lo, hi = 0.0, 12.0
    if screen_top(0.0) >= top:
        return 0.0
    for _ in range(40):
        mid = (lo + hi) / 2
        if screen_top(mid) < top:
            lo = mid
        else:
            hi = mid
    return (lo + hi) / 2


def dome(power=0.6):
    return lambda t: math.sin(math.pi * min(1.0, max(0.0, t))) ** power


def walls(k=7.0):
    return lambda t: max(0.0, min(1.0, k * t, k * (1.0 - t)))


def heightfield(name, depth, shape, mat, back=None, jitter=0.0, seed=1, step=0.125, sink=0.05, mat_fn=None, smooth=1,
                tight=True, smooth_y=0, vent=None):
    """A height field fitted to the silhouette of `name` (see the module's docstring). `depth`:
    how far back from its front each column reaches (tiles), or a function of x; `back`: no
    point further north than this; `smooth_y`: passes of smoothing front to back as well (a
    mound rather than walls); `vent`: (x, screen u, hole radius, rim radius, depth) of a crater."""
    cols = PROFILES[name]
    xs = [c[0] for c in cols]
    x0, x1 = min(xs) - step, max(xs) + step
    sections = []  # (x, y_f, d, h)
    for x, runs in cols:
        for top, bot in runs:
            y_f = bot / SIN_P
            d = depth(x) if callable(depth) else depth
            if back is not None:
                d = max(0.15, min(d, back - y_f))
            # The top of the run can't be lower than the back of the cross-section's ground.
            d = max(0.15, min(d, (top - 0.02) / SIN_P - y_f)) if top / SIN_P - y_f < d else d
            h = _solve_height(y_f, d, top, shape)
            sections.append((x, y_f, d, h))
    ys0 = min(s[1] for s in sections) - step
    ys1 = max(s[1] + s[2] for s in sections) + step
    nx = int(round((x1 - x0) / step)) + 1
    ny = int(round((ys1 - ys0) / step)) + 1
    grid = [[0.0] * ny for _ in range(nx)]
    for x, y_f, d, h in sections:
        i = int(round((x - x0) / step))
        for j in range(ny):
            y = ys0 + j * step
            t = (y - y_f) / d
            if 0.0 <= t <= 1.0:
                z = h * shape(t)
                for di in (0,):
                    grid[i + di][j] = max(grid[i + di][j], z)
    # Fill single-column gaps between measured columns.
    for i in range(1, nx - 1):
        for j in range(ny):
            if grid[i][j] == 0.0 and grid[i - 1][j] > 0 and grid[i + 1][j] > 0:
                grid[i][j] = (grid[i - 1][j] + grid[i + 1][j]) / 2
    # Smooth across columns: neighbouring columns are measured independently, and left raw they
    # make a comb of spikes whose side faces streak the projected sprite.
    for _ in range(smooth):
        g2 = [row[:] for row in grid]
        for i in range(1, nx - 1):
            for j in range(ny):
                if grid[i][j] > 0:
                    g2[i][j] = 0.25 * grid[i - 1][j] + 0.5 * grid[i][j] + 0.25 * grid[i + 1][j]
        grid = g2
    for _ in range(smooth_y):
        g2 = [row[:] for row in grid]
        for i in range(nx):
            for j in range(1, ny - 1):
                if grid[i][j] > 0:
                    g2[i][j] = 0.25 * grid[i][j - 1] + 0.5 * grid[i][j] + 0.25 * grid[i][j + 1]
        grid = g2
    hole = None
    if vent is not None:
        # A crater sunk where the surface over column x shows at screen height u (from the
        # front): the rim levelled off round it, the hole falling `deep` to its floor.
        vx, vu, r_hole, r_rim, deep = vent
        i = int(round((vx - x0) / step))
        j = next(j for j in range(ny) if grid[i][j] > 0 and SIN_P * (ys0 + j * step) + COS_P * grid[i][j] >= vu)
        hx, hy, hz = vx, ys0 + j * step, grid[i][j]
        hole = (hx, hy, r_hole)
        for i in range(nx):
            for j in range(ny):
                dd = math.hypot(x0 + i * step - hx, ys0 + j * step - hy)
                if dd < r_hole:
                    grid[i][j] = max(0.01, hz - deep * (1.0 - (dd / r_hole) ** 2))
                elif dd < r_rim and grid[i][j] > 0:
                    grid[i][j] = max(grid[i][j] * 0.4, min(grid[i][j], hz + 0.06))
    p = Part()
    bm = p.bm
    verts = {}

    def vert(i, j):
        key = (i, j)
        v = verts.get(key)
        if v is None:
            x, y, z = x0 + i * step, ys0 + j * step, grid[i][j]
            if z <= 0.0 and tight:
                # A ground vertex beside a raised one: pull it half a step in, to the measured
                # column's edge, or the slope down to it fattens the outline by half a column.
                for di, dj in ((-1, 0), (1, 0), (0, -1), (0, 1)):
                    if 0 <= i + di < nx and 0 <= j + dj < ny and grid[i + di][j + dj] > 0 \
                            and not (0 <= i - di < nx and 0 <= j - dj < ny and grid[i - di][j - dj] > 0):
                        x += di * step / 2
                        y += dj * step / 2
            if jitter:
                n = noise.noise(Vector((x * 1.7 + seed, y * 1.7, z * 1.7)))
                n2 = noise.noise(Vector((x * 4.1, y * 4.1 + seed, z * 4.1)))
                z = z + (jitter * n + jitter * 0.4 * n2) * min(1.0, z * 2.0) if z > 0 else z
                x += jitter * 0.5 * noise.noise(Vector((y * 3.0, z * 3.0, seed)))
            if z <= 0.0:
                z = -sink
            v = bm.verts.new((x, y, z))
            verts[key] = v
        return v

    for i in range(nx - 1):
        for j in range(ny - 1):
            zs_ = (grid[i][j], grid[i + 1][j], grid[i + 1][j + 1], grid[i][j + 1])
            if max(zs_) <= 0.0:
                continue
            f = bm.faces.new((vert(i, j), vert(i + 1, j), vert(i + 1, j + 1), vert(i, j + 1)))
            m = mat
            if mat_fn is not None:
                cx, cy = x0 + (i + 0.5) * step, ys0 + (j + 0.5) * step
                m = mat_fn(cx, cy, sum(zs_) / 4) or mat
            if hole is not None and math.hypot(x0 + (i + 0.5) * step - hole[0], ys0 + (j + 0.5) * step - hole[1]) < hole[2] * 0.8:
                m = "soot"
            f.material_index = p._mat_index(m)
    bm.normal_update()
    for f in bm.faces:
        if f.normal.z < 0:
            f.normal_flip()
    return p


def silhouette_width(name, u):
    """(left, right) x of the silhouette at screen height u, or None."""
    xs = [x for x, runs in PROFILES[name] if any(bot <= u <= top for top, bot in runs)]
    return (min(xs) - 0.0625, max(xs) + 0.0625) if xs else None


def revolve(name, mat, crater=0.5, crater_mat=None, segs=28, base_r=None, rim_mat=None, cy=0.0, crust=0.0,
            stain=0.0, stain_mat=None):
    """A chimney: rings whose radius at height z is half the silhouette's width at that height
    on screen, centred on the silhouette, with a crater `crater` deep in its top. `crust`: the top
    this share of the height is `rim_mat` too (the sulfur crust round the crater), and the `stain`
    share below that `stain_mat` (where the crust runs down the rock). A chimney in RINGS has
    its rings fitted to the sprite's outline instead (space_profiles.py), each with its own centre,
    so the lumpy base spreading towards the camera and the lean of the cone come out."""
    if name in RINGS:
        out = []
        for (za, xa, ya, ra), (zb, xb, yb, rb) in zip(RINGS[name], RINGS[name][1:]):
            n = max(1, int(math.ceil((zb - za) / 0.18)))
            out += [(za + (zb - za) * t, xa + (xb - xa) * t, ya + (yb - ya) * t, ra + (rb - ra) * t)
                    for t in (i / n for i in range(n))]
        out.append(tuple(RINGS[name][-1]))
        return _rings(out, mat, crater, crater_mat, segs, rim_mat, crust, stain, stain_mat)
    cols = PROFILES[name]
    top = max(r[0] for _, runs in cols for r in runs)
    # Highest ring: the back rim shows at `top`.
    rings = []
    for k in range(80):
        z = k * 0.15
        w = silhouette_width(name, COS_P * z + SIN_P * cy)
        if w is not None:
            rings.append((z, (w[0] + w[1]) / 2, (w[1] - w[0]) / 2))
    # Below the lowest measured height (hidden by the floor layer in Factorio) keep widening.
    if base_r is not None:
        # Flare smoothly out to base_r at the ground, like a cone of spilled rock.
        rings = [r for r in rings if r[0] > 0.3]
        z1, cx1, r1 = rings[0] if rings else (0.6, 0.0, base_r * 0.5)
        flare = [(z1 * t, cx1, r1 + (base_r - r1) * (1 - t) ** 1.1) for t in (0.0, 0.25, 0.5, 0.75)]
        rings = flare + rings
    # Trim to the top: the back rim of the last ring sits at `top` on screen.
    out = []
    for z, cx, r in rings:
        if COS_P * z + SIN_P * (cy + r * 0.6) <= top + 0.05:
            out.append((z, cx, cy, r))
    return _rings(out, mat, crater, crater_mat, segs, rim_mat, crust, stain, stain_mat)


def _rings(out, mat, crater, crater_mat, segs, rim_mat, crust, stain, stain_mat):
    """The chimney's mesh from its rings (z, centre x, centre y, radius), bottom first."""
    p = Part()
    bm = p.bm
    loops = []
    for z, cx, cy, r in out:
        loop = []
        for k in range(segs):
            a = 2 * math.pi * k / segs
            # Broad lumps, then the sprite's craggy ribs running down the rock.
            jr = 1.0 + 0.08 * noise.noise(Vector((math.cos(a) * 2, math.sin(a) * 2, z * 1.5)))                 + 0.05 * noise.noise(Vector((math.cos(a) * 7, math.sin(a) * 7, z * 0.8)))
            loop.append(bm.verts.new((cx + r * jr * math.cos(a), cy + r * jr * math.sin(a) * 0.9, z)))
        loops.append(loop)
    mi = p._mat_index(mat)
    zt_ = out[-1][0]
    z_crust = zt_ * (1.0 - crust) if crust else zt_ + 1.0
    z_stain = zt_ * (1.0 - crust - stain) if stain else z_crust
    for (za, _, _, _), la, lb in zip(out, loops, loops[1:]):
        m = p._mat_index(rim_mat) if za >= z_crust else p._mat_index(stain_mat) if za >= z_stain else mi
        for k in range(segs):
            f = bm.faces.new((la[k], la[(k + 1) % segs], lb[(k + 1) % segs], lb[k]))
            f.material_index = m
    # Crater: a lip of the crust round the top, then a dark throat down to its floor.
    zt, cxt, cy, rt = out[-1]

    def ring(f, dz):
        return [bm.verts.new((cxt + rt * f * math.cos(2 * math.pi * k / segs),
                              cy + rt * f * math.sin(2 * math.pi * k / segs) * 0.9, zt + dz)) for k in range(segs)]
    lip, inner = ring(0.78, -0.04), ring(0.5, -crater)
    for la, lb, m in ((loops[-1], lip, p._mat_index(rim_mat or mat)), (lip, inner, p._mat_index("soot"))):
        for k in range(segs):
            f = bm.faces.new((la[k], la[(k + 1) % segs], lb[(k + 1) % segs], lb[k]))
            f.material_index = m
    floor = bm.faces.new(list(reversed(inner)))
    floor.material_index = p._mat_index(crater_mat or mat)
    bm.normal_update()
    return p


# ---------------------------------------------------------------------------------------------
# Vulcanus rocks.

def _glow(name, seed):
    """Molten rock where the sprite's emissive layer glows (space_profiles.GLOW: cells of
    Factorio's view), broken into veins by a noise field so it reads as cracks, not tiles."""
    cells = {(math.floor(x / 0.125), math.floor(u / 0.125)) for x, u in GLOW[name]}

    def fn(x, y, z):
        u = SIN_P * y + COS_P * z
        if (math.floor(x / 0.125), math.floor(u / 0.125)) not in cells:
            return None
        n = noise.noise(Vector((x * 3.0 + seed, y * 3.0, z * 3.0)))
        return "lava_glow" if abs(n) < 0.1 else None
    return fn


@model("big-volcanic-rock")
def big_volcanic_rock():
    """Vulcanus' big rock: a black basalt heap of flaky slabs, fitted to its sprite."""
    return heightfield("big-volcanic-rock", 1.6, dome(0.5), "rock_basalt", jitter=0.08, seed=3)


@model("big-volcanic-rock-hot")
def big_volcanic_rock_hot():
    """The big volcanic rock with molten cracks glowing through it where its sprite glows."""
    return heightfield("big-volcanic-rock", 1.6, dome(0.5), "rock_basalt", jitter=0.08, seed=3,
                       mat_fn=_glow("big-volcanic-rock", 5))


@model("huge-volcanic-rock")
def huge_volcanic_rock():
    """Vulcanus' huge rock: a wide basalt outcrop of layered slabs."""
    return heightfield("huge-volcanic-rock", 2.4, dome(0.45), "rock_basalt", jitter=0.1, seed=7)


@model("huge-volcanic-rock-hot")
def huge_volcanic_rock_hot():
    """The huge volcanic rock with molten cracks glowing through it where its sprite glows."""
    return heightfield("huge-volcanic-rock", 2.4, dome(0.45), "rock_basalt", jitter=0.1, seed=7,
                       mat_fn=_glow("huge-volcanic-rock", 9))


# ---------------------------------------------------------------------------------------------
# Vulcanus chimneys.

@model("vulcanus-chimney")
def vulcanus_chimney():
    """A sulfuric chimney: a tall cone of dark rock crusted yellow round its crater."""
    return revolve("vulcanus-chimney", "stone_chimney", crater=0.6, crater_mat="lava_glow", rim_mat="stone_sulfur",
                   base_r=1.2, crust=0.22, stain=0.2, stain_mat="stone_chimney_stain")


@model("vulcanus-chimney-faded")
def vulcanus_chimney_faded():
    """A sulfuric chimney gone quiet: taller, its crust faded."""
    return revolve("vulcanus-chimney-faded", "stone_chimney", crater=0.6, crater_mat="soot", rim_mat="stone_sulfur",
                   base_r=1.2, crust=0.16)


@model("vulcanus-chimney-cold")
def vulcanus_chimney_cold():
    """A cold chimney: grey ridged rock, no crust."""
    return revolve("vulcanus-chimney-cold", "stone_chimney_cold", crater=0.6, crater_mat="soot", base_r=1.2)


@model("vulcanus-chimney-short")
def vulcanus_chimney_short():
    """A short sulfuric chimney. Its sprite stands a tile north of the entity's position, so the
    model does too."""
    return revolve("vulcanus-chimney-short", "stone_chimney", crater=0.35, crater_mat="soot", base_r=0.85, cy=1.1)


@model("vulcanus-chimney-truncated")
def vulcanus_chimney_truncated():
    """A broken-off chimney: a wide stump round a big crater."""
    return revolve("vulcanus-chimney-truncated", "stone_chimney", crater=0.9, crater_mat="soot", base_r=0.95)


# ---------------------------------------------------------------------------------------------
# Fulgoran ruins: rust-pink brick and rusted iron.

_RUINS = {
    # name: (depth, wall steepness, column width). The smaller ruins are measured in 1/16-tile
    # columns: at 1/8 their struts and spikes come out as blobs.
    "fulgoran-ruin-small": (1.3, 3.0, 0.0625),
    "fulgoran-ruin-medium": (1.6, 5.0, 0.0625),
    "fulgoran-ruin-stonehenge": (1.2, 6.0, 0.0625),  # an arch: the top of it is kept over the legs (back)
    "fulgoran-ruin-big": (2.6, 5.0, 0.0625),
    "fulgoran-ruin-huge": (3.6, 6.0, 0.125),
    "fulgoran-ruin-colossal": (4.5, 6.0, 0.125),
    "fulgoran-ruin-vault": (7.0, 8.0, 0.125),
}


def _ruin(name):
    depth, k, step = _RUINS[name]

    def fn(x, y, z):
        n = noise.noise(Vector((x * 1.3, y * 1.3, 4.0)))
        return "concrete_ruin_dark" if n > 0.35 else None
    back = 1.6 if name == "fulgoran-ruin-stonehenge" else None
    return heightfield(name, depth, walls(k), "concrete_ruin", jitter=0.04, seed=11, step=step, mat_fn=fn, back=back)


for _name in _RUINS:
    model(_name)(lambda _n=_name: _ruin(_n))


@model("fulgoran-ruin-tiny")
def fulgoran_ruin_tiny():
    """A single fallen brick block (the sprite is 0.6 tiles wide at scale 0.3: too small for the
    1/8-tile height field). Tipped back and turned as fitted to the sprite's outline, so its lid,
    its lit south-west face and its dark east face show."""
    p = Part()
    m = kit.T(0.008, -0.04, 0.075) @ kit.R("Z", 32) @ kit.R("X", -23)
    p.box((0, 0, 0), (0.4, 0.5, 0.37), "concrete_ruin", bevel=0.05, matrix=m)
    p.box((0.0, -0.25, -0.03), (0.3, 0.02, 0.025), "concrete_ruin_dark", matrix=m)  # mortar joints
    p.box((0.2, 0.0, -0.03), (0.02, 0.38, 0.025), "concrete_ruin_dark", matrix=m)
    return p


# ---------------------------------------------------------------------------------------------
# Sulfuric acid geyser and scrap (resources).

@model("sulfuric-acid-geyser")
def sulfuric_acid_geyser():
    """A sulfuric acid geyser: a low mound of yellow sulfur crust round a dark vent."""
    # Its crust crumbles off in flakes at the edge: measured in 1/24-tile columns, alpha over 0.5.
    # The vent is a crater in the mound, as the sprite: a crusted rim round a dark hole, the hole
    # on screen at the entity's position.
    return heightfield("sulfuric-acid-geyser", 3.0, dome(0.6), "stone_sulfur", back=1.0, jitter=0.03, seed=13,
                       step=0.041666667, smooth_y=2, vent=(0.03, -0.05, 0.32, 0.55, 0.4))


kit.MATERIALS.update({
    "paint_scrap_red": ("8a2626", 0.6, 0.3, None, 0),
    "paint_scrap_blue": ("4a64a8", 0.6, 0.3, None, 0),
    "paint_scrap_mark": ("c9b04a", 0.7, 0.25, None, 0),
    "scrap_dark": ("33363a", 0.6, 0.6, None, 0),
    "scrap_crate": ("3d3631", 0.8, 0.4, None, 0),
})


@model("scrap")
def scrap():
    """A scrap tile, piece by piece as the sprite's first variation (scrap.png row 2): a red
    panel with a yellow chevron (west), a dark drum looking up at the camera, a small blue chip
    and a long dark crate behind them (north), a big blue panel with yellow marks leaning up
    (east), a ribbed pipe and a rusty shard in front (south). Positions were measured on the
    sprite: screen up = 0.743 y + 0.669 z. The client draws one per tile, turned and sized at
    random."""
    p = Part()
    # Red panel lying almost flat, its yellow chevron on top.
    red = kit.T(-0.55, 0.05, 0.08) @ kit.R("Z", -8) @ kit.R("X", 20)
    p.box((0, 0, 0), (0.48, 0.3, 0.14), "paint_scrap_red", bevel=0.045, matrix=red)
    chev = Part()
    for a, b in (((-0.2, 0.08), (0.02, -0.05)), ((0.02, -0.05), (0.22, 0.02))):
        chev.beam((a[0], a[1], 0.072), (b[0], b[1], 0.072), 0.045, 0.008, "paint_scrap_mark")
    p.add_part(chev, red)
    # The drum: a short pipe tilted towards the camera, its bore dark.
    axis = kit.R("X", 42)
    drum = kit.T(-0.13, 0.1, 0.13) @ axis
    p.cyl((0, 0, 0), 0.125, 0.2, "scrap_dark", segs=14, bevel=0.02, matrix=drum)
    p.cyl((0, 0, 0.06), 0.07, 0.1, "soot", segs=10, matrix=drum)
    # Small blue chip standing up, a yellow edge on its west side.
    chip = kit.T(-0.16, 0.62, 0.11) @ kit.R("Z", -18) @ kit.R("X", 55)
    p.box((0, 0, 0), (0.22, 0.24, 0.06), "paint_scrap_blue", bevel=0.02, matrix=chip)
    p.box((-0.09, 0, 0.032), (0.035, 0.2, 0.01), "paint_scrap_mark", matrix=chip)
    # The long dark crate, lying north-east behind the blue panel.
    crate = kit.T(0.4, 0.55, 0.09) @ kit.R("Z", 45)
    p.box((0, 0, 0), (0.26, 0.64, 0.16), "scrap_crate", bevel=0.03, matrix=crate)
    p.box((0, 0.2, 0.082), (0.24, 0.05, 0.01), "scrap_dark", matrix=crate)
    # Big blue panel leaning up against the crate, a yellow band along its foot, a yellow spot.
    blue = kit.T(0.3, 0.12, 0.16) @ kit.R("Z", 22) @ kit.R("X", 40)
    p.box((0, 0, 0), (0.54, 0.42, 0.1), "paint_scrap_blue", bevel=0.035, matrix=blue)
    p.box((0, -0.15, 0.052), (0.5, 0.04, 0.01), "paint_scrap_mark", matrix=blue)
    p.cyl((0.12, 0.1, 0.053), 0.06, 0.01, "paint_scrap_mark", segs=10, matrix=blue @ kit.S(1.4, 0.8, 1))
    # Ribbed pipe lying south-east in front of the red panel.
    a, b = (-0.47, -0.17, 0.085), (-0.16, -0.48, 0.07)
    p.tube(a, b, 0.085, "scrap_dark", segs=12, bevel=0.015)
    for t in (0.2, 0.45, 0.7, 0.92):
        c = tuple(a[i] + (b[i] - a[i]) * t for i in range(3))
        d = tuple((b[i] - a[i]) * 0.04 for i in range(3))
        p.tube(tuple(c[i] - d[i] for i in range(3)), tuple(c[i] + d[i] for i in range(3)), 0.098, "scrap_dark", segs=12)
    # Rusty shard pointing north-east.
    p.tube((0.0, -0.42, 0.03), (0.19, -0.2, 0.08), 0.06, "rust", segs=6, radius_top=0.025)
    return p
