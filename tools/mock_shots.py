"""The mock's side of shots.lua and combat.lua's `shot`: what the character's guns and capsules
fire, flown as the game does (Factorio 2.1.23's speeds and cooldowns, from its prototypes), and
reported as the mod does: `pj` every other tick while anything flies, `gf` (fires and clouds)
four times a second, `shot` for each round of a gun that isn't a stream.

`--guns shotgun,rocket-launcher,flamethrower` puts those guns (and their ammo) in the character's
gun slots instead of the pistol, for trying each weapon against the mock.
"""

import math
import random

# gun -> (ammo, cooldown in ticks, range): Factorio's attack_parameters.
GUNS = {
    "pistol": ("firearm-magazine", 15, 15),
    "submachine-gun": ("firearm-magazine", 6, 18),
    "shotgun": ("shotgun-shell", 40, 15),
    "combat-shotgun": ("shotgun-shell", 30, 15),
    "rocket-launcher": ("rocket", 60, 36),
    "flamethrower": ("flamethrower-ammo", 1, 15),
    "railgun": ("railgun-ammo", 120, 40),
    "teslagun": ("tesla-ammo", 60, 24),
}
STREAM_GUNS = {"flamethrower"}
PELLETS = 12
PELLET_SPEED = 1.0  # tiles per tick, shotgun-pellet's starting_speed
ROCKET_SPEED, ROCKET_ACCELERATION = 0.1, 0.01
GRENADE_SPEED, GRENADE_ACCELERATION = 0.3, 0.005
STREAM_SPEED = 0.25  # particle_horizontal_speed
STREAM_TICKS = 20  # how long a stream outlasts the last tick the gun fed it (its particles land)
FIRE_INTERVAL = 10
BEAM_TICKS = 30
FIRE_TICKS = 600
CLOUD_TICKS = 1200
GROUND_INTERVAL = 15

# capsule -> (projectile, explosion where it lands or None, cloud it leaves or None)
CAPSULES = {
    "grenade": ("grenade", "grenade-explosion", None),
    "cluster-grenade": ("cluster-grenade", "grenade-explosion", None),
    "poison-capsule": ("poison-capsule", None, "poison-cloud"),
    "slowdown-capsule": ("slowdown-capsule", None, "slowdown-capsule"),
    "defender-capsule": ("defender-capsule", None, None),
    "distractor-capsule": ("distractor-capsule", None, None),
    "destroyer-capsule": ("destroyer-capsule", None, None),
}


def fixed(v):
    return int(math.floor(v * 256 + 0.5))


def state(srv):
    st = getattr(srv, "_shots", None)
    if st is None:
        st = srv._shots = {"next_id": 1, "flying": [], "beams": [], "booms": [], "ended": [], "ground": [], "sent": False, "grounded": False}
    return st


def arm(srv, guns):
    """The --guns option: those guns with a stack of their ammo each, in the gun slots."""
    slots = []
    for name in guns[:3]:
        if name in GUNS:
            slots.append([name, GUNS[name][0], 200 if name in STREAM_GUNS else 20])
    while len(slots) < 3:
        slots.append(["", "", 0])
    srv.player["guns"] = slots


def cooldown(gun):
    return GUNS.get(gun, (None, 15, 15))[1]


def gun_range(gun):
    return GUNS.get(gun, (None, 15, 15))[2]


def _id(st):
    st["next_id"] += 1
    return st["next_id"]


def _fly(st, name, x, y, tx, ty, speed, acceleration=0.0, then=None):
    d = math.hypot(tx - x, ty - y) or 1.0
    st["flying"].append({"id": _id(st), "name": name, "x": x, "y": y, "dx": (tx - x) / d, "dy": (ty - y) / d,
                         "left": d, "speed": speed, "acc": acceleration, "then": then or {}})


def fired(srv, gun, ammo, target, aim):
    """One round of `gun`: the `shot` report, and what it sends flying. `target` is (x, y) of the
    enemy hit or None; `aim` the point aimed at."""
    p, st = srv.player, state(srv)
    tx, ty = target if target else aim
    if gun not in STREAM_GUNS:
        srv.send_now({"t": "shot", "u": p["unit"], "g": gun, "a": ammo, "x": fixed(tx), "y": fixed(ty)})
    x, y = p["x"], p["y"]
    if gun in ("shotgun", "combat-shotgun"):
        for _ in range(PELLETS):
            a = math.atan2(ty - y, tx - x) + random.uniform(-0.18, 0.18)
            r = gun_range(gun) * random.uniform(0.85, 1.0)
            _fly(st, "shotgun-pellet", x, y, x + math.cos(a) * r, y + math.sin(a) * r, PELLET_SPEED * random.uniform(0.9, 1.1))
    elif gun == "rocket-launcher":
        _fly(st, "rocket", x, y, tx, ty, ROCKET_SPEED, ROCKET_ACCELERATION)
    elif gun == "flamethrower":
        # As in 2.1.23: one stream entity that stays put (here halfway to the target) while the gun
        # keeps feeding it; its particles fly inside it, and fire catches where they land.
        sm = st.get("stream")
        if not sm or sm["until"] < srv.tick:
            sm = st["stream"] = {"id": _id(st), "x": (x + tx) / 2, "y": (y + ty) / 2}
        sm["until"] = srv.tick + STREAM_TICKS
        sm["tx"], sm["ty"] = tx, ty
    elif gun == "teslagun" and target:
        st["beams"].append({"id": _id(st), "name": "chain-tesla-gun-beam-start", "src": None, "tx": tx, "ty": ty,
                            "until": srv.tick + BEAM_TICKS})


def thrown(srv, item, x, y):
    """A capsule from the character to (x, y), as use_capsule makes one."""
    spec = CAPSULES.get(item)
    if not spec:
        return
    p = srv.player
    projectile, boom, cloud = spec
    _fly(state(srv), projectile, p["x"], p["y"], x, y, GRENADE_SPEED, GRENADE_ACCELERATION, then={"boom": boom, "cloud": cloud})


def tick(srv):
    st = state(srv)
    p = srv.player
    for f in list(st["flying"]):
        f["speed"] += f["acc"]
        step = min(f["speed"], f["left"])
        f["x"] += f["dx"] * step
        f["y"] += f["dy"] * step
        f["left"] -= step
        if f["left"] <= 1e-6:
            st["flying"].remove(f)
            st["ended"] += [f["id"], fixed(f["x"]), fixed(f["y"])]
            then = f["then"]
            if then.get("boom"):
                st["booms"].append((then["boom"], f["x"], f["y"]))
            if then.get("cloud"):
                st["ground"].append({"id": _id(st), "name": then["cloud"], "x": f["x"], "y": f["y"], "until": srv.tick + CLOUD_TICKS, "ttl": True})
            if then.get("fire") and not any(math.hypot(g["x"] - f["x"], g["y"] - f["y"]) < 0.7 for g in st["ground"]):
                st["ground"].append({"id": _id(st), "name": then["fire"], "x": f["x"], "y": f["y"], "until": srv.tick + FIRE_TICKS, "ttl": False})
    sm = st.get("stream")
    if sm and sm["until"] < srv.tick:
        st["ended"] += [sm["id"], fixed(sm["x"]), fixed(sm["y"])]
        st["stream"] = sm = None
    if sm and srv.tick % FIRE_INTERVAL == 0 and not any(math.hypot(g["x"] - sm["tx"], g["y"] - sm["ty"]) < 0.7 for g in st["ground"]):
        st["ground"].append({"id": _id(st), "name": "fire-flame", "x": sm["tx"], "y": sm["ty"], "until": srv.tick + FIRE_TICKS, "ttl": False})
    st["beams"] = [b for b in st["beams"] if b["until"] > srv.tick]
    st["ground"] = [g for g in st["ground"] if g["until"] > srv.tick]
    if srv.tick % 2 == 0:
        pj = {"t": "pj", "p": [], "b": [], "x": [], "e": st["ended"]}
        for f in st["flying"]:
            pj["p"] += [f["id"], f["name"], fixed(f["x"]), fixed(f["y"])]
        if sm:
            pj["p"] += [sm["id"], "handheld-flamethrower-fire-stream", fixed(sm["x"]), fixed(sm["y"])]
        for b in st["beams"]:
            pj["b"] += [b["id"], b["name"], fixed(p["x"]), fixed(p["y"]), fixed(b["tx"]), fixed(b["ty"])]
        for name, x, y in st["booms"]:
            pj["x"] += [name, fixed(x), fixed(y)]
        st["booms"], st["ended"] = [], []
        busy = any(pj[k] for k in ("p", "b", "x", "e"))
        if busy or st["sent"]:
            srv.send_now(pj)
        st["sent"] = busy
    if srv.tick % GROUND_INTERVAL == 0:
        l = []
        for g in st["ground"]:
            l += [g["id"], g["name"], fixed(g["x"]), fixed(g["y"]), g["until"] - srv.tick if g["ttl"] else -1]
        if l or st["grounded"]:
            srv.send_now({"t": "gf", "l": l})
        st["grounded"] = bool(l)
