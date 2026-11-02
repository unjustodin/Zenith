"""--vehicles: every animated vehicle and robot in a cleared field east of the start, for watching
the client's vehicle_anim.gd against the mock (look from about 30,16):

- a spidertron walking a circle, its feet sent as the mod sends them (`legs`, from a small copy
  of Factorio's spider engine: two walking groups in turn, each foot back to its ground position
  when it strays), and one standing still that gets no feet (the client steps it itself);
- a tank driving a circle (treads, road wheels);
- construction robots, two hovering in place (working) and one flying back and forth; logistic
  robots flying with and without cargo (`rc`); a capture robot;
- a cargo pod going up out of sight and coming back down, over and over (`cp`: rockets.gd lifts
  it, the client opens it high up);
- a train with an infinity cargo wagon behind its locomotive, driving east and west.
"""

import math

# name, type, width, height (selection box), colour: merged into mock_server.ENTITY_PROTOS.
ENTITY_PROTOS = [
    ("construction-robot", "construction-robot", 0.5, 0.5, (230, 200, 90)),
    ("capture-robot", "capture-robot", 1, 1, (120, 160, 150)),
    ("infinity-cargo-wagon", "cargo-wagon", 2, 6, (120, 110, 200)),
]

CLEAR = (14.0, 4.0, 52.0, 34.0)
WALKER, STANDER = 660, 661
POD = 670
POD_CYCLE = 900  # ticks: up for half, down for half
LEGS_INTERVAL = 4
# Factorio's spidertron legs (spider_engine.legs): ground position (x east, y south) and walking group.
LEGS = [((2.25, -2.5), 1), ((3.0, -1.0), 2), ((3.0, 1.0), 1), ((2.25, 2.5), 2),
        ((-2.25, -2.5), 2), ((-3.0, -1.0), 1), ((-3.0, 1.0), 2), ((-2.25, 2.5), 1)]
STEP = 1.0  # minimal_step_size
FOOT_SPEED = 0.3  # tiles a tick
LEAD = 20  # ticks of the body's motion a foot steps ahead


def build_showcase(game):
    game.clear_areas.append(CLEAR)
    x0, y0, x1, y1 = CLEAR
    for e in [e for e in game.entities.values() if e.type in ("tree", "simple-entity") and x0 <= e.x <= x1 and y0 <= e.y <= y1]:
        game.remove(e, announce=False)
    m = game.movers
    m.append({"unit": WALKER, "name": "spidertron", "kind": "circle", "cx": 24.0, "cy": 16.0, "r": 6.0, "speed": 0.004,
              "phase": 0, "oriented": True})
    m.append({"unit": STANDER, "name": "spidertron", "kind": "parked", "x": 38.0, "y": 10.0, "o": 0.1, "speed": 0.0,
              "oriented": True})
    m.append({"unit": 662, "name": "tank", "kind": "circle", "cx": 42.0, "cy": 24.0, "r": 5.0, "speed": 0.006, "phase": 1.0,
              "oriented": True})
    for i, (ax, ay, bx, by) in enumerate(((30.0, 20.0, 30.0, 20.0), (31.5, 21.0, 31.5, 21.0), (26.0, 28.0, 36.0, 28.0))):
        m.append({"unit": 663 + i, "name": "construction-robot", "kind": "shuttle", "ax": ax, "ay": ay, "bx": bx, "by": by,
                  "phase": i * 50})
    m.append({"unit": 666, "name": "logistic-robot", "kind": "shuttle", "ax": 18.0, "ay": 30.0, "bx": 30.0, "by": 32.0,
              "phase": 0})
    m.append({"unit": 667, "name": "capture-robot", "kind": "parked", "x": 20.0, "y": 8.0, "o": 0.0, "speed": 0.0})
    m.append({"unit": POD, "name": "cargo-pod", "kind": "parked", "x": 46.0, "y": 12.0, "o": 0.0, "speed": 0.0})
    # The infinity wagon runs on the mock's track (y -48) behind the train's last wagon.
    m.append({"unit": 703, "name": "infinity-cargo-wagon", "kind": "train", "offset": 21.0, "oriented": True})
    game.showcase_feet = {}


def tick(game):
    feet = getattr(game, "showcase_feet", None)
    if feet is None:
        return
    if game.tick % 60 == 0:
        # Down for the first half of the cycle (rockets.gd drops it from on high), up for the second.
        state = "descending" if (game.tick // (POD_CYCLE // 2)) % 2 == 0 else "ascending"
        game.send_now({"t": "cp", "l": [[POD, state, "nauvis", "nauvis"]]})
    if game.tick % LEGS_INTERVAL:
        return
    walker = next((m for m in game.movers if m["unit"] == WALKER), None)
    if walker is None:
        return
    x, y, o = game.mover_state(walker)
    x2, y2, _ = game.mover_state(dict(walker, phase=walker["phase"] + walker["speed"] * LEAD))
    feet_of = feet.setdefault(WALKER, {"at": None, "to": None, "group": 2})
    a = o * 2 * math.pi
    rest = [(x2 + gx * math.cos(a) - gy * math.sin(a), y2 + gx * math.sin(a) + gy * math.cos(a)) for (gx, gy), _ in LEGS]
    if feet_of["at"] is None:
        feet_of["at"] = list(rest)
        feet_of["to"] = list(rest)
    at, to = feet_of["at"], feet_of["to"]
    moving = any(math.dist(at[i], to[i]) > 1e-3 for i in range(len(LEGS)))
    if not moving:
        nxt = 1 if feet_of["group"] == 2 else 2
        if any(g == nxt and math.dist(at[i], rest[i]) > STEP for i, (_, g) in enumerate(LEGS)):
            feet_of["group"] = nxt
            for i, (_, g) in enumerate(LEGS):
                if g == nxt:
                    to[i] = rest[i]
    for i in range(len(LEGS)):
        d = math.dist(at[i], to[i])
        step = FOOT_SPEED * LEGS_INTERVAL
        if d <= step:
            at[i] = to[i]
        else:
            at[i] = (at[i][0] + (to[i][0] - at[i][0]) * step / d, at[i][1] + (to[i][1] - at[i][1]) * step / d)
    flat = []
    for fx, fy in at:
        flat += [int(fx * 256), int(fy * 256)]
    game.send_now({"t": "legs", "l": [[WALKER, flat]]})
