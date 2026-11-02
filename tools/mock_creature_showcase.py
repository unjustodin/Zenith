"""--creatures: Space Age's creatures in cleared fields west and south of the start, for watching
the client's demolishers.gd, vehicle_anim.gd (pentapod legs) and creatures.gd against the mock
(look from about -45,28 for Gleba's, -45,95 for the small demolisher):

- a big stomper and a big strafer walking circles, their feet sent as the mod sends them
  (`legs`, from a small copy of Factorio's spider engine: walking groups 1 to 5 in turn, each foot
  back to its ground position when it strays more than minimal_step_size); a medium stomper and a
  small strafer standing, which get no feet (the client steps them itself);
- a wriggler of each tier scuttling round;
- a Gleba spawner and a small one, the small one dying every 20 seconds (`died`, then `del`) and
  coming back 10 seconds later;
- a small demolisher crawling a circle and a big one a wider circle round it (`seg`), their
  segments spaced along the path as Factorio's segment engine spaces them (each one's
  collision half-length and paddings, from the prototypes).

mock_server.demolisher() on Vulcanus uses the same chain.
"""

import math

EID = {}  # prototype name -> id: mock_server sets it

# Factorio's segment_engine (`factorio --dump-data`): the small demolisher's segment scales, head
# to tail; the medium's are 1.5 times these, the big's twice. Its head's collision half-length is
# 1.5 x tier and its backward_padding -1.25 x tier; each segment's half-length is its scale, its
# forward_padding -0.5 x scale and backward_padding 1.5 x scale; the tail's half-length 3 x its
# scale and forward_padding -2.75 x it.
SMALL_SEGMENTS = [0.545, 0.635, 0.68, 0.68, 0.68, 0.68, 0.665, 0.65, 0.685, 0.76, 0.76, 0.7, 0.705, 0.64, 0.64, 0.585,
                  0.55, 0.54, 0.54, 0.545, 0.6, 0.6, 0.55, 0.55, 0.495, 0.495, 0.495, 0.435, 0.435, 0.485, 0.435, 0.485,
                  0.495, 0.435, 0.435, 0.435, 0.435, 0.385, 0.385, 0.325]
SMALL_TAIL = 0.32
TIERS = {"small": 1.0, "medium": 1.5, "big": 2.0}


def _scale_name(scale):
    return ("%.4f" % scale).rstrip("0").rstrip(".").replace(".", "_")


def chain(tier):
    """[(prototype name, half-length, forward padding, backward padding), ...] head to tail."""
    k = TIERS[tier]
    out = [("%s-demolisher" % tier, 1.5 * k, 0.0, -1.25 * k)]
    for s in SMALL_SEGMENTS:
        s *= k
        out.append(("%s-demolisher-segment-x%s" % (tier, _scale_name(s)), s, -0.5 * s, 1.5 * s))
    t = SMALL_TAIL * k
    out.append(("%s-demolisher-tail-x%s" % (tier, _scale_name(t)), 3.0 * t, -2.75 * t, 0.0))
    return out


ENTITY_PROTOS = [
    ("medium-demolisher", "segmented-unit", 9, 9, (90, 60, 50)),
    ("big-demolisher", "segmented-unit", 12, 12, (90, 60, 50)),
    ("small-wriggler-pentapod", "unit", 1, 1, (120, 140, 60)),
    ("medium-wriggler-pentapod", "unit", 1.4, 1.4, (120, 140, 60)),
    ("big-wriggler-pentapod", "unit", 1.8, 1.8, (120, 140, 60)),
    ("small-strafer-pentapod", "spider-unit", 2.7, 2.7, (140, 130, 80)),
    ("medium-strafer-pentapod", "spider-unit", 3.6, 3.6, (140, 130, 80)),
    ("big-strafer-pentapod", "spider-unit", 4.8, 4.8, (140, 130, 80)),
    ("medium-stomper-pentapod", "spider-unit", 6, 6, (160, 120, 60)),
    ("big-stomper-pentapod", "spider-unit", 8, 8, (160, 120, 60)),
    ("gleba-spawner-small", "unit-spawner", 3, 3, (130, 110, 70)),
]
_seen = set()
for _tier in TIERS:
    for _name, _half, _f, _b in chain(_tier)[1:]:
        if _name not in _seen:
            _seen.add(_name)
            ENTITY_PROTOS.append((_name, "segment", 2 * _half, 2 * _half, (90, 60, 50)))

CLEAR_GLEBA = (-80.0, 8.0, -20.0, 50.0)
CLEAR_DEMOLISHERS = (-95.0, 50.0, 5.0, 145.0)
LEGS_INTERVAL = 4
SPAWNER_CYCLE = 1800  # ticks: the small spawner dies 1200 ticks in, is back at 0
# spider_engine.legs (big tiers): ground position (x east, y south) and walking group, the order
# the mod sends feet in; minimal_step_size; tiles a tick a foot moves.
PENTAPODS = {
    "big-stomper-pentapod": ([((-6.5832, -9.0610), 1), ((-10.6518, 3.4610), 3), ((0.0, 11.2), 5),
                              ((10.6518, 3.4610), 2), ((6.5832, -9.0610), 4)], 1.76, 0.17),
    "big-strafer-pentapod": ([((-6.4721, -4.7023), 1), ((-6.4721, 4.7023), 3), ((2.4721, 7.6085), 5),
                              ((8.0, 0.0), 2), ((2.4721, -7.6085), 4)], 1.6, 0.33),
}
LEAD = 24  # ticks of the body's motion a foot steps ahead
SPAWNER_SMALL = 7100
DEMOLISHERS = [(9000, "small", -45.0, 97.0, 20.0, 0.0012), (9001, "big", -45.0, 97.0, 44.0, 0.0005)]


def build_showcase(game, entity_cls):
    for area in (CLEAR_GLEBA, CLEAR_DEMOLISHERS):
        game.clear_areas.append(area)
        x0, y0, x1, y1 = area
        for tx in range(int(x0), int(x1)):  # dry ground: the mock's lakes are out here
            for ty in range(int(y0), int(y1)):
                game.tile_overrides[(tx, ty)] = "dirt-1"
        for e in [e for e in game.entities.values() if e.type in ("tree", "simple-entity", "fish", "cliff")
                  and x0 <= e.x <= x1 and y0 <= e.y <= y1]:
            game.remove(e, announce=False)
    m = game.movers
    m.append({"unit": 7000, "name": "big-stomper-pentapod", "kind": "circle", "cx": -45.0, "cy": 30.0, "r": 7.0,
              "speed": 0.0025, "phase": 0, "oriented": True})
    m.append({"unit": 7001, "name": "big-strafer-pentapod", "kind": "circle", "cx": -62.0, "cy": 22.0, "r": 5.0,
              "speed": 0.006, "phase": 1.0, "oriented": True})
    m.append({"unit": 7002, "name": "medium-stomper-pentapod", "kind": "parked", "x": -58.0, "y": 44.0, "o": 0.1,
              "speed": 0.0, "oriented": True})
    m.append({"unit": 7003, "name": "small-strafer-pentapod", "kind": "parked", "x": -73.0, "y": 40.0, "o": 0.6,
              "speed": 0.0, "oriented": True})
    for i, tier in enumerate(("small", "medium", "big")):
        m.append({"unit": 7010 + i, "name": "%s-wriggler-pentapod" % tier, "kind": "circle", "cx": -30.0 + i * 3.0,
                  "cy": 16.0, "r": 2.0 + i, "speed": 0.03 - 0.006 * i, "phase": i * 2.0, "oriented": True})
    game.add(entity_cls(game._unit(), "gleba-spawner", -26.5, 42.5, 0))
    game.add(entity_cls(SPAWNER_SMALL, "gleba-spawner-small", -35.5, 47.5, 0))
    game.creature_feet = {}


def demolisher(game, tier, cx, cy, r, speed):
    """[segment prototype id, x, y, orientation, ...] for a demolisher crawling a circle, head first."""
    flat = []
    a = game.tick * speed
    links = chain(tier)
    prev = None
    for name, half, fwd, back in links:
        if prev is not None:
            a -= (prev[1] + prev[3] + fwd + half) / r
        prev = (name, half, fwd, back)
        x, y = cx + math.cos(a) * r, cy + math.sin(a) * r
        # Travelling counter-clockwise on the map (y south): heading along (-sin a, cos a).
        o = (math.atan2(-math.sin(a), -math.cos(a)) / (2 * math.pi)) % 1.0
        flat += [EID[name], int(x * 256), int(y * 256), int(o * 1000) % 1000]
    return flat


def _feet(game, m, legs, step, speed):
    x, y, o = game.mover_state(m)
    x2, y2, _ = game.mover_state(dict(m, phase=m["phase"] + m["speed"] * LEAD))
    st = game.creature_feet.setdefault(m["unit"], {"at": None, "to": None, "group": 0})
    a = o * 2 * math.pi
    rest = [(x2 + gx * math.cos(a) - gy * math.sin(a), y2 + gx * math.sin(a) + gy * math.cos(a)) for (gx, gy), _ in legs]
    if st["at"] is None:
        st["at"], st["to"] = list(rest), list(rest)
    at, to = st["at"], st["to"]
    if not any(math.dist(at[i], to[i]) > 1e-3 for i in range(len(legs))):
        for _ in range(5):  # the next group (1 to 5 in turn) that has strayed steps
            st["group"] = st["group"] % 5 + 1
            mine = [i for i, (_, g) in enumerate(legs) if g == st["group"]]
            if any(math.dist(at[i], rest[i]) > step for i in mine):
                for i in mine:
                    to[i] = rest[i]
                break
    for i in range(len(legs)):
        d = math.dist(at[i], to[i])
        s = speed * LEGS_INTERVAL
        at[i] = to[i] if d <= s else (at[i][0] + (to[i][0] - at[i][0]) * s / d, at[i][1] + (to[i][1] - at[i][1]) * s / d)
    return [v for fx, fy in at for v in (int(fx * 256), int(fy * 256))]


def tick(game, entity_cls):
    feet = getattr(game, "creature_feet", None)
    if feet is None:
        return
    if game.tick % 2 == 0:
        game.send_now({"t": "seg", "l": [[u, EID["%s-demolisher" % tier], demolisher(game, tier, cx, cy, r, sp)]
                                        for u, tier, cx, cy, r, sp in DEMOLISHERS]})
    phase = game.tick % SPAWNER_CYCLE
    small = game.entities.get(SPAWNER_SMALL)
    if phase == 1200 and small is not None:
        game.send_now({"t": "died", "u": SPAWNER_SMALL, "p": EID["gleba-spawner-small"],
                       "x": int(small.x * 256), "y": int(small.y * 256)})
        game.remove(small)
    elif phase == 0 and small is None and game.tick > 0:
        game.add(entity_cls(SPAWNER_SMALL, "gleba-spawner-small", -35.5, 47.5, 0), announce=True)
    if game.tick % LEGS_INTERVAL:
        return
    out = []
    for m in game.movers:
        spec = PENTAPODS.get(m["name"])
        if spec is not None and m["kind"] == "circle":
            out.append([m["unit"], _feet(game, m, *spec)])
    game.send_now({"t": "legs", "l": out})
