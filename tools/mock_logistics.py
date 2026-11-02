"""Logistics entities for the mock server, animated (movers.lua's `st` for signals, accumulators,
power switches and pumps; planets.lua's `lt` for lightning).

With --logistics, a showcase north-east of the start (look from about 76,-26): splitters and
loaders of every tier, belts and underground belts of every tier, linked belts, pumps, a storage
tank, a power switch turning on and off, an accumulator charging and discharging, a burner
generator, infinity pipes, the five logistic chests with robots flying over them, a lightning rod
and collector struck in turn, and rail and chain signals by a track going through their colours.
"""

# name, type, width, height (selection box), colour: merged into mock_server.ENTITY_PROTOS.
ENTITY_PROTOS = [
    ("lane-splitter", "lane-splitter", 1, 1, (250, 200, 40)),
    ("fast-splitter", "splitter", 2, 1, (220, 70, 50)),
    ("express-splitter", "splitter", 2, 1, (60, 140, 210)),
    ("turbo-splitter", "splitter", 2, 1, (120, 180, 60)),
    ("loader", "loader", 1, 2, (250, 200, 40)),
    ("fast-loader", "loader", 1, 2, (220, 70, 50)),
    ("express-loader", "loader", 1, 2, (60, 140, 210)),
    ("turbo-loader", "loader", 1, 2, (120, 180, 60)),
    ("loader-1x1", "loader-1x1", 1, 1, (250, 200, 40)),
    ("express-transport-belt", "transport-belt", 1, 1, (60, 140, 210)),
    ("turbo-transport-belt", "transport-belt", 1, 1, (120, 180, 60)),
    ("fast-underground-belt", "underground-belt", 1, 1, (220, 70, 50)),
    ("express-underground-belt", "underground-belt", 1, 1, (60, 140, 210)),
    ("turbo-underground-belt", "underground-belt", 1, 1, (120, 180, 60)),
    ("linked-belt", "linked-belt", 1, 1, (160, 160, 160)),
    ("burner-generator", "burner-generator", 3, 5, (140, 140, 140)),
    ("infinity-pipe", "infinity-pipe", 1, 1, (128, 128, 255)),
    ("lightning-collector", "lightning-attractor", 2, 2, (140, 140, 150)),
    ("rail-signal", "rail-signal", 1, 1, (90, 160, 90)),
    ("rail-chain-signal", "rail-chain-signal", 1, 1, (90, 160, 160)),
]

DX = 40.0  # the showcase's positions below are shifted this far east (clear of the iron patch)
CLEAR = (18.0 + DX, -40.0, 60.0 + DX, -10.0)  # trees and rocks cleared round the showcase
TIERS = ("", "fast-", "express-", "turbo-")

# name, x, y, direction (16-way), extra
SHOWCASE = (
    [(t + "splitter", 23.0 + 3 * i, -35.5, 0, None) for i, t in enumerate(TIERS)]
    + [("lane-splitter", 35.5, -35.5, 0, None)]
    + [(t + "loader", 22.5 + 2 * i, -31.0, 0, None) for i, t in enumerate(TIERS)]
    + [("loader-1x1", 30.5, -30.5, 0, None), ("linked-belt", 32.5, -30.5, 0, {"u": "i"}),
       ("linked-belt", 33.5, -30.5, 0, {"u": "o"})]
    + [(t + "transport-belt", 35.5 + i, -30.5, 0, {"s": "s"}) for i, t in enumerate(TIERS)]
    + [(t + "underground-belt", 40.5 + i, -31.5, 0, {"u": "o"}) for i, t in enumerate(TIERS)]
    + [(t + "underground-belt", 40.5 + i, -29.5, 0, {"u": "i"}) for i, t in enumerate(TIERS)]
    + [("pump", 22.5, -25.0, 0, None), ("offshore-pump", 25.5, -25.0, 0, None), ("storage-tank", 30.5, -24.5, 0, None),
       ("power-switch", 35.0, -25.0, 0, None), ("accumulator", 39.0, -25.0, 0, None),
       ("burner-generator", 44.5, -24.5, 0, None)]
    # Infinity pipes: a little run with a corner, connections as the mod sends them (`pc`).
    + [("infinity-pipe", 48.5, -26.5, 0, {"pc": 2}), ("infinity-pipe", 49.5, -26.5, 0, {"pc": 10}),
       ("infinity-pipe", 50.5, -26.5, 0, {"pc": 12}), ("infinity-pipe", 50.5, -25.5, 0, {"pc": 5}),
       ("infinity-pipe", 50.5, -24.5, 0, {"pc": 1})]
    + [(name, 22.5 + 2 * i, -19.5, 0, None) for i, name in enumerate(
        ("passive-provider-chest", "active-provider-chest", "storage-chest", "buffer-chest", "requester-chest"))]
    + [("lightning-rod", 35.5, -19.5, 0, None), ("lightning-collector", 39.0, -19.0, 0, None)]
    # A track running east, its signals beside it on the south (facing west, for trains going west).
    + [("straight-rail", 23.0 + 2 * i, -13.0, 4, None) for i in range(8)]
    + [("rail-signal", 25.5, -11.5, 12, None), ("rail-chain-signal", 29.5, -11.5, 12, None),
       ("rail-signal", 33.5, -11.5, 12, None)]
)
ROBOTS = [(990 + i, 22.5, 30.5, -19.5, i * 80) for i in range(2)]  # unit, from x, to x, y, phase
SIGNAL_STEP = 120  # ticks each colour shows
STRIKE_EVERY = 180


def build_showcase(game, entity_class):
    game.logistics = {"units": {}, "sent": {}}
    game.clear_areas.append(CLEAR)
    x0, y0, x1, y1 = CLEAR
    for e in [e for e in game.entities.values() if e.type in ("tree", "simple-entity", "fish", "resource")
              and x0 <= e.x <= x1 and y0 <= e.y <= y1]:
        game.remove(e, announce=False)
    for name, x, y, d, extra in SHOWCASE:
        e = entity_class(game._unit(), name, x + DX, y, d, dict(extra) if extra else None)
        game.add(e)
        game.logistics["units"].setdefault(name, []).append(e.unit)
        if name == "storage-tank":
            game.fluids[e.unit] = [("water", 16000, 25000, 15)]
    for unit, ax, bx, y, phase in ROBOTS:
        game.movers.append({"unit": unit, "name": "logistic-robot", "kind": "shuttle", "ax": ax + DX, "ay": y - 0.2,
                            "bx": bx + DX, "by": y - 0.2, "phase": phase})


def states(game):
    """unit -> the state `st` reports now (the mod's values: PROTOCOL.md)."""
    t, units, out = game.tick, game.logistics["units"], {}
    for name in ("pump", "offshore-pump", "burner-generator"):
        for u in units.get(name, []):
            out[u] = 0 if (t // 600) % 4 == 3 else 1  # a pause every 40 s
    for u in units.get("power-switch", []):
        out[u] = (t // 480) % 2
    for u in units.get("accumulator", []):
        out[u] = (1, 2, 0)[(t // 240) % 3]
    for k, u in enumerate(units.get("rail-signal", [])):
        out[u] = (1, 2, 3)[(t // SIGNAL_STEP + k) % 3]
    for u in units.get("rail-chain-signal", []):
        out[u] = (1, 2, 3, 4)[(t // SIGNAL_STEP) % 4]
    return out


def tick(game):
    if not getattr(game, "logistics", None) or game.surface != "nauvis":
        return
    if game.tick % 30 == 0:
        now = states(game)
        sent = game.logistics["sent"]
        changes = []
        for u, v in sorted(now.items()):
            if sent.get(u) != v or game.tick % 300 == 0:
                sent[u] = v
                changes += [u, v]
        if changes:
            game.send_reliable({"t": "st", "l": changes})
    if game.tick % STRIKE_EVERY == 0:
        targets = [game.entities.get(u) for name in ("lightning-rod", "lightning-collector")
                   for u in game.logistics["units"].get(name, [])]
        targets = [e for e in targets if e is not None]
        if targets:
            e = targets[(game.tick // STRIKE_EVERY) % len(targets)]
            game.send_now({"t": "lt", "l": [[int(e.x * 256), int(e.y * 256), 1]]})
