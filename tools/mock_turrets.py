"""Turrets and vehicle guns for the mock server (turrets.lua's `ts`, combat.lua's `tf`).

With --turrets, a row of every turret stands between the start and the biter nest, with a tank and
a spidertron beside it. Each one turns towards the nearest biter in range at its prototype's
rotation speed and fires at its cooldown (Factorio 2.1.23's numbers), so the client can be watched
raising, aiming and firing them. The mock's turrets do no damage: the biters keep coming round.
"""

import math

# name, type, width, height (selection box), colour: merged into mock_server.ENTITY_PROTOS.
ENTITY_PROTOS = [
    ("laser-turret", "electric-turret", 2, 2, (120, 120, 130)),
    ("flamethrower-turret", "fluid-turret", 2, 3, (140, 110, 90)),
    ("rocket-turret", "ammo-turret", 3, 3, (110, 110, 110)),
    ("tesla-turret", "electric-turret", 2, 2, (110, 110, 120)),
    ("railgun-turret", "ammo-turret", 3, 5, (90, 90, 95)),
]

# Prototype values: range, min_range, rotation (turns per tick), cooldown (ticks), the `tf` kind
# its hits send (None for weapons whose damage lands later), turn_range (None: all round).
WEAPONS = {
    "gun-turret": (18, 0, 0.015, 6, "bullet", None),
    "laser-turret": (24, 0, 0.01, 40, "laser", None),
    "flamethrower-turret": (30, 6, 0.015, 4, "flame", 1 / 3),
    "rocket-turret": (36, 15, 0.005, 120, None, None),
    "tesla-turret": (30, 0, 0.005, 120, None, None),
    "railgun-turret": (40, 3.5, 0.005, 170, None, 0.2),
    "artillery-turret": (224, 32, 0.001, 200, None, None),
    # Vehicles: [(gun's range, min range, cooldown, tf kind), ...] by selected gun; turret turning.
    "tank": [(30, 5, 90, None), (20, 0, 4, None), (9, 3, 1, None)],
    "spidertron": [(36, 0, 60, None)],
}
VEHICLE_TURN = {"tank": 0.0058333, "spidertron": 0.005}
SWEEP = 6
FULL = 120
GUN_SWITCH = 300  # ticks: the showcase tank goes through its three guns in turn

# The showcase: name, x, y, direction (16-way) for turrets.
ROW = [("gun-turret", 58.0, 44.0, 0), ("laser-turret", 62.0, 44.0, 0), ("flamethrower-turret", 66.0, 44.5, 8),
       ("rocket-turret", 70.5, 43.5, 0), ("tesla-turret", 75.0, 44.0, 0), ("railgun-turret", 80.5, 43.5, 8),
       ("artillery-turret", 100.5, 30.5, 0)]
TANK_UNIT, SPIDER_UNIT = 650, 651
AMMO = {"gun-turret": "firearm-magazine", "rocket-turret": "rocket", "railgun-turret": "railgun-ammo"}


CLEAR = (52.0, 24.0, 108.0, 50.0)  # trees and rocks cleared round the showcase, to see it


def build_showcase(game, entity_class):
    game.turrets = {}
    game.clear_areas.append(CLEAR)
    x0, y0, x1, y1 = CLEAR
    for e in [e for e in game.entities.values() if e.type in ("tree", "simple-entity") and x0 <= e.x <= x1 and y0 <= e.y <= y1]:
        game.remove(e, announce=False)
    for name, x, y, d in ROW:
        e = entity_class(game._unit(), name, x, y, d)
        game.add(e)
        if name in AMMO:
            game.machine(e)["inv"] = {"turret_ammo": {AMMO[name]: 10}}  # loaded: no no-ammo alerts
        game.turrets[e.unit] = {"name": name, "x": x, "y": y, "o": d / 16.0, "rounds": 0, "next": 0, "base": d / 16.0}
    game.movers.append({"unit": TANK_UNIT, "name": "tank", "kind": "parked", "x": 64.0, "y": 39.0, "o": 0.25,
                        "speed": 0.0, "oriented": True})
    game.movers.append({"unit": SPIDER_UNIT, "name": "spidertron", "kind": "spider", "x": 76.0, "y": 38.0, "o": 0.0,
                        "speed": 0.0, "oriented": False, "dest": []})
    game.turrets[TANK_UNIT] = {"name": "tank", "vehicle": True, "o": 0.0, "next": 0, "gun": 1}
    game.turrets[SPIDER_UNIT] = {"name": "spidertron", "vehicle": True, "o": 0.0, "next": 0, "gun": 1}


def orientation(dx, dy):
    return (math.atan2(dx, -dy) / (2 * math.pi)) % 1.0


def turn(o, goal, rate):
    diff = (goal - o + 0.5) % 1.0 - 0.5
    return (o + max(-rate, min(rate, diff))) % 1.0, abs(diff) <= rate


def tick(game):
    turrets = getattr(game, "turrets", None)
    if not turrets or game.tick % SWEEP:
        return
    full = game.tick % FULL == 0
    enemies = list(game.alive_enemies())
    out = []
    for unit, t in sorted(turrets.items()):
        if t.get("vehicle"):
            m = next((m for m in game.movers if m["unit"] == unit), None)
            if m is None:
                continue
            x, y, body = game.mover_state(m)
            if t["name"] == "tank" and game.tick % GUN_SWITCH == 0:
                t["gun"] = t["gun"] % 3 + 1
            guns = WEAPONS[t["name"]]
            reach, low, cooldown, kind = guns[min(t["gun"], len(guns)) - 1]
            rate, arc = VEHICLE_TURN[t["name"]], None
            body = body if t["name"] == "tank" else 0.0
        else:
            x, y = t["x"], t["y"]
            reach, low, rate, cooldown, kind, arc = WEAPONS[t["name"]]
            body = t["base"]
        best = None
        for m, ex, ey in enemies:
            d = math.hypot(ex - x, ey - y)
            if low <= d <= reach and (best is None or d < best[0]):
                goal = orientation(ex - x, ey - y)
                if arc is None or abs((goal - t["base"] + 0.5) % 1.0 - 0.5) <= arc:
                    best = (d, ex, ey)
        was = t["o"]
        shots = 0
        if best:
            goal = orientation(best[1] - x, best[2] - y)
            absolute = (t["o"] + body) % 1.0 if t.get("vehicle") else t["o"]
            absolute, aimed = turn(absolute, goal, rate * SWEEP)
            t["o"] = (absolute - body) % 1.0 if t.get("vehicle") else absolute
            if aimed:
                while t["next"] <= game.tick:
                    t["next"] += cooldown
                    shots += 1
                t["next"] = max(t["next"], game.tick - cooldown)
                if kind:
                    game.send_now({"t": "tf", "u": unit, "w": kind, "sx": int(x * 256), "sy": int(y * 256),
                                   "x": int(best[1] * 256), "y": int(best[2] * 256)})
        else:
            t["next"] = game.tick
        o = int(round(t["o"] * 1000)) % 1000
        if not (full or best or shots or o != int(round(was * 1000)) % 1000):
            continue
        rec = [unit, o, min(shots, 50), t.get("gun", 0) if t.get("vehicle") else 0]
        if best:
            rec += [int(best[1] * 256), int(best[2] * 256)]
        out.append(rec)
    if out:
        game.send_now({"t": "ts", "l": out})
