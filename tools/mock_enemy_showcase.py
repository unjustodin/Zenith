"""--enemies: Nauvis's enemies of every tier in a cleared field north of the start, for watching the
client's creatures.gd and anim.gd against the mock (look from about 32,-62):

- a row of biters (small, medium, big, behemoth) biting a wall each, and behind them a row of
  spitters spitting at walls from 7 tiles, all sent in `en` as the mod sends attacks;
- a row of worms (small to behemoth) attacking walls south of them (towards the camera), and
  every 30 seconds folding away for 10 (no `en`, the client folds them as Factorio does);
- east of them a biter and a spitter of each tier that die every 15 seconds (`died`, so the client
  plays their dying and leaves the corpse in its puddle) and come back 5 seconds later;
- a biter spawner and a spitter spawner.
"""

EID = {}  # prototype name -> id: mock_server sets it
TIERS = ("small", "medium", "big", "behemoth")

ENTITY_PROTOS = [
    ("big-biter", "unit", 1.0, 1.0, (180, 60, 60)),
    ("behemoth-biter", "unit", 1.2, 1.2, (180, 60, 60)),
    ("small-spitter", "unit", 0.6, 0.6, (180, 60, 60)),
    ("medium-spitter", "unit", 0.9, 0.9, (180, 60, 60)),
    ("big-spitter", "unit", 1.0, 1.0, (180, 60, 60)),
    ("behemoth-spitter", "unit", 1.2, 1.2, (180, 60, 60)),
    ("small-worm-turret", "turret", 2, 2, (180, 70, 60)),
    ("medium-worm-turret", "turret", 2, 2, (180, 70, 60)),
    ("big-worm-turret", "turret", 3, 3, (180, 70, 60)),
    ("behemoth-worm-turret", "turret", 3, 3, (180, 70, 60)),
    ("spitter-spawner", "unit-spawner", 5, 5, (150, 40, 60)),
]

CLEAR = (8.0, -86.0, 72.0, -54.0)
X0, GAP = 14.0, 7.0               # the tiers' columns
WALL_Y, BITER_Y, SPITTER_Y = -82.5, -81.2, -75.0
WORM_Y, WORM_TARGET_Y = -66.0, -58.5
DIE_X0, DIE_GAP = 46.0, 5.0       # the dying rows' columns
DIE_CYCLE, DEAD_TICKS = 900, 300
WORM_CYCLE, WORM_REST = 1800, 600
UNIT0 = 7500


def _clear(game):
    game.clear_areas.append(CLEAR)
    x0, y0, x1, y1 = CLEAR
    for tx in range(int(x0), int(x1)):
        for ty in range(int(y0), int(y1)):
            game.tile_overrides[(tx, ty)] = "dirt-1"
    for e in [e for e in game.entities.values() if e.type in ("tree", "simple-entity", "fish", "cliff", "resource")
              and x0 <= e.x <= x1 and y0 <= e.y <= y1]:
        game.remove(e, announce=False)


def build_showcase(game, entity_cls):
    _clear(game)
    m = game.movers
    game.enemy_show = {"attacks": [], "worms": [], "dying": []}
    show = game.enemy_show
    for i, tier in enumerate(TIERS):
        x = X0 + i * GAP
        game.add(entity_cls(game._unit(), "stone-wall", x + 0.5, WALL_Y, 0))
        game.add(entity_cls(game._unit(), "stone-wall", x + 3.5, WALL_Y, 0))
        biter = {"unit": UNIT0 + i, "name": "%s-biter" % tier, "kind": "parked", "x": x + 0.5, "y": BITER_Y,
                 "o": 0.0, "speed": 0.0, "oriented": True, "dead_until": 0, "hp": 1e9}
        spitter = {"unit": UNIT0 + 10 + i, "name": "%s-spitter" % tier, "kind": "parked", "x": x + 3.5,
                   "y": SPITTER_Y, "o": 0.0, "speed": 0.0, "oriented": True, "dead_until": 0, "hp": 1e9}
        m += [biter, spitter]
        show["attacks"] += [(biter["unit"], x + 0.5, WALL_Y), (spitter["unit"], x + 3.5, WALL_Y)]
        worm = entity_cls(game._unit(), "%s-worm-turret" % tier, x + 2.0, WORM_Y, 0)
        game.add(worm)
        game.add(entity_cls(game._unit(), "stone-wall", x + 2.5, WORM_TARGET_Y, 0))
        show["worms"].append((worm.unit, x + 2.5, WORM_TARGET_Y))
        for k, family in enumerate(("biter", "spitter")):
            d = {"unit": UNIT0 + 20 + 2 * i + k, "name": "%s-%s" % (tier, family), "kind": "parked",
                 "x": DIE_X0 + i * DIE_GAP, "y": -80.0 + 8.0 * k, "o": 0.35 + 0.1 * i, "speed": 0.0,
                 "oriented": True, "dead_until": 0, "hp": 1e9, "offset": i * 60 + k * 30}
            m.append(d)
            show["dying"].append(d)
    game.add(entity_cls(game._unit(), "biter-spawner", 50.5, -62.5, 0))
    game.add(entity_cls(game._unit(), "spitter-spawner", 62.5, -62.5, 0))


def tick(game):
    show = getattr(game, "enemy_show", None)
    if show is None:
        return
    for d in show["dying"]:
        phase = (game.tick + d["offset"]) % DIE_CYCLE
        if phase == 0 and not d["dead_until"]:
            d["dead_until"] = game.tick + DEAD_TICKS
            game.send_now({"t": "died", "u": d["unit"], "p": EID[d["name"]], "x": int(d["x"] * 256),
                           "y": int(d["y"] * 256)})
        elif d["dead_until"] and game.tick >= d["dead_until"]:
            d["dead_until"] = 0
            d["unit"] = game._unit()  # Factorio's new unit at the nest
    if game.tick % 10:
        return
    out = []
    for unit, x, y in show["attacks"]:
        out += [unit, int(x * 256), int(y * 256)]
    if game.tick % WORM_CYCLE < WORM_CYCLE - WORM_REST:
        for unit, x, y in show["worms"]:
            out += [unit, int(x * 256), int(y * 256)]
    game.send_now({"t": "en", "l": out})
