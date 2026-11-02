"""The mock's side of the vehicle, artillery, pipeline and train-group windows (entity_ui.lua's
veh, art and pl; spiders.lua's spider_go / spider_q; trains.lua's train groups): a tank and a
spidertron parked near the start (the spidertron walks to the waypoints the remote gives it), and
with --machine-gallery an artillery turret and wagon, a storage tank, a pipe, a pipe-to-ground, a
heat pipe and a land mine in a row south-west of the start.
"""

import math

# name, type, width, height (selection box), colour: merged into mock_server.ENTITY_PROTOS.
ENTITY_PROTOS = [
    ("tank", "car", 2, 3, (110, 120, 90)),
    ("spidertron", "spider-vehicle", 3, 3, (60, 60, 70)),
    ("artillery-turret", "artillery-turret", 3, 3, (110, 110, 100)),
    ("artillery-wagon", "artillery-wagon", 2, 6, (120, 110, 100)),
    ("storage-tank", "storage-tank", 3, 3, (130, 130, 120)),
]
SCREEN_KINDS = {"spider-vehicle": "vehicle", "artillery-turret": "turret", "artillery-wagon": "train", "storage-tank": "other",
                "pipe": "other", "pipe-to-ground": "other", "heat-pipe": "other", "land-mine": "other"}

TANK, SPIDER = 602, 610
SPIDER_SPEED = 0.15  # tiles per tick
# The gallery row: name, x, y and the window's insides.
GALLERY = [
    ("artillery-turret", -40.5, 71.5, {"inv": {"turret_ammo": {"artillery-shell": 5}}, "art": 1}),
    ("artillery-wagon", -35.0, 71.0, {"inv": {"ammo": {"artillery-shell": 5}}, "art": 1, "sizes": {"ammo": 1}}),
    ("storage-tank", -30.5, 71.5, {"fb": [["crude-oil", 25000, 25000, 25]], "pl": ["crude-oil", 106100, 106100]}),
    ("pipe", -27.5, 71.5, {"fb": [["", 0, 100, 0]], "pl": ["", 0, 4800]}),
    ("pipe-to-ground", -26.5, 71.5, {"fb": [["water", 60, 100, 15]], "pl": ["water", 1200, 4800]}),
    ("heat-pipe", -24.5, 71.5, {"temp": 65613, "tmax": 1000}),
    ("land-mine", -22.5, 71.5, {}),
]
# The force's other trains' groups (the mock train is in "Copper" too, as the captured one is).
OTHER_GROUPS = {"": 3, "Copper": 1, "Iron": 2}


def movers():
    """The tank and the spidertron, parked near the start (mock_server.mover_state reads x, y, o)."""
    return [{"unit": TANK, "name": "tank", "kind": "parked", "x": -4.0, "y": 9.0, "o": 0.0, "speed": 0.0, "oriented": True},
            {"unit": SPIDER, "name": "spidertron", "kind": "spider", "x": -14.0, "y": 10.0, "o": 0.0, "speed": 0.0,
             "oriented": False, "dest": []}]


def machines(game):
    """The tank's and spidertron's insides (vehicle windows), keyed by unit."""
    game.machines[TANK] = {"recipe": None, "progress": 0, "inv": {"fuel": {"solid-fuel": 20}, "trunk": {"iron-plate": 20}, "car_ammo": {}},
                           "guns": ["tank-cannon", "tank-machine-gun", "tank-flamethrower"], "bu": 700, "veh": {"grid": 1},
                           "fuel_slots": 2, "sizes": {"car_ammo": 3, "trunk": 80}}
    game.machines[SPIDER] = {"recipe": None, "progress": 0, "inv": {"trunk": {}, "car_ammo": {}},
                             "guns": ["spidertron-rocket-launcher-1", "spidertron-rocket-launcher-2", "spidertron-rocket-launcher-3",
                                      "spidertron-rocket-launcher-4"], "col": [229, 113, 0],
                             "veh": {"grid": 1, "lbl": "", "at": [1, 0]}, "sizes": {"car_ammo": 4, "trunk": 80}}


def build_gallery(game, entity_class):
    units = []
    for name, x, y, insides in GALLERY:
        e = entity_class(game._unit(), name, x, y, 4 if name == "artillery-wagon" else 0)
        game.add(e)
        m = {"recipe": None, "progress": 0, "inv": {}, "gallery": True}
        for k, v in insides.items():
            m[k] = {r: dict(c) for r, c in v.items()} if k == "inv" else (list(v) if isinstance(v, list) else v)
        if "fb" in m:
            game.fluids[e.unit] = [tuple(b) for b in m.pop("fb")]
        game.machines[e.unit] = m
        units.append(e.unit)
    return units


def tick(game):
    """The spidertron walks to its first waypoint, then the next."""
    for m in game.movers:
        if m.get("kind") != "spider" or not m["dest"]:
            continue
        tx, ty = m["dest"][0]
        dx, dy = tx - m["x"], ty - m["y"]
        d = math.hypot(dx, dy)
        if d <= SPIDER_SPEED:
            m["x"], m["y"] = tx, ty
            m["dest"].pop(0)
        else:
            m["x"] += dx / d * SPIDER_SPEED
            m["y"] += dy / d * SPIDER_SPEED
            m["o"] = (math.atan2(dx, -dy) / (2 * math.pi)) % 1.0


def spider_waypoints(game, units):
    out = []
    for m in game.movers:
        if m.get("kind") == "spider" and m["unit"] in units:
            out.append([m["unit"], [[int(x * 256), int(y * 256)] for x, y in m["dest"]]])
    return out


def train_fields(game, info):
    """trains.lua's group fields on the mock train's `tr`."""
    group = game.train.get("group", "Copper")
    info["sched"]["group"] = group
    counts = dict(OTHER_GROUPS)
    counts[group] = counts.get(group, 0) + 1
    if group:
        info["gc"] = counts[group]
    info["groups"] = [[g, n] for g, n in sorted(counts.items())]


def command(game, t, msg):
    """The commands of these windows and the remote; True if handled here."""
    if t == "spider_q":
        game.send_now({"t": "spd", "l": spider_waypoints(game, [int(u) for u in msg.get("l", []) if isinstance(u, int)])})
        return True
    if t == "spider_go":
        units = [int(u) for u in msg.get("l", []) if isinstance(u, int)]
        spiders = [m for m in game.movers if m.get("kind") == "spider" and m["unit"] in units]
        if not spiders:
            game.message("No spidertron selected")
            return True
        x, y = int(msg.get("x", 0)) / 256, int(msg.get("y", 0)) / 256
        for m in spiders:
            if msg.get("q") == 1:
                m["dest"].append((x, y))
            else:
                m["dest"] = [(x, y)]
        game.send_now({"t": "spd", "l": spider_waypoints(game, units)})
        return True
    if t not in ("set_vehicle", "set_artillery", "flush", "set_train_group"):
        return False
    sc = game.screen
    if sc is None or int(msg.get("u", 0)) != sc["unit"]:
        return True
    entity = game.entities.get(sc["unit"]) or game.mover_entity(sc["unit"])
    m = game.machine(entity) if entity is not None else None
    if m is None:
        return True
    sc["due"] = game.tick
    if t == "set_vehicle":
        veh = m.get("veh")
        if veh is None or entity.type != "spider-vehicle":
            game.message("That isn't a vehicle")
            return True
        if isinstance(msg.get("lbl"), str):
            veh["lbl"] = msg["lbl"][:200]
        for i, k in enumerate(("wo", "wi")):
            if msg.get(k) in (0, 1):
                veh["at"][i] = msg[k]
    elif t == "set_artillery":
        if "art" not in m:
            game.message("That isn't artillery")
            return True
        m["art"] = 1 if msg.get("on") == 1 else 0
    elif t == "flush":
        boxes = game.fluids.get(entity.unit)
        if not boxes or "pl" not in m:
            game.message("That holds no fluid to flush")
            return True
        name, amount, cap, temp = boxes[0]
        if msg.get("pipe") == 1:
            game.fluids[entity.unit] = [("", 0, cap, 0)]
            m["pl"] = ["", 0, m["pl"][2]]
        else:
            game.fluids[entity.unit] = [("", 0, cap, 0)]
            left = max(0, m["pl"][1] - amount)
            m["pl"] = [m["pl"][0] if left else "", left, m["pl"][2]]
    elif t == "set_train_group":
        if entity.type != "locomotive" and entity.type != "cargo-wagon":
            game.message("That isn't a train")
            return True
        name = str(msg.get("g", ""))[:200]
        old = game.train.get("group", "Copper")
        if msg.get("all") == 1 and old and old in OTHER_GROUPS:
            OTHER_GROUPS[name] = OTHER_GROUPS.pop(old)
        game.train["group"] = name
    return True
