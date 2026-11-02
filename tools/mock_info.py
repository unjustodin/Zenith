"""The mock server's information windows: Factoriopedia (`pidx`, `pedia`), the logistic networks
window (`lnets`, `lnet`), alerts (`al`) and the richer statistics (build counts, pollution, all
surfaces, graph lines). Kept apart from mock_server.py, which calls in here; the data is made up
in the shapes the mod sends (docs/PROTOCOL.md).
"""

import math

# Groups as Factorio orders its tabs, and where the mock's things go.
GROUPS = [["logistics", "a"], ["production", "b"], ["intermediate-products", "c"], ["combat", "d"], ["fluids", "e"],
          ["environment", "f"], ["enemies", "g"], ["tiles", "h"], ["space", "i"], ["other", "z"], ["technologies", "zzz"]]
ITEM_GROUP = {
    "transport-belt": ("logistics", "belt"), "fast-transport-belt": ("logistics", "belt"), "underground-belt": ("logistics", "belt"),
    "splitter": ("logistics", "belt"), "burner-inserter": ("logistics", "inserter"), "inserter": ("logistics", "inserter"),
    "wooden-chest": ("logistics", "storage"), "iron-chest": ("logistics", "storage"), "small-electric-pole": ("logistics", "energy-pipe-distribution"),
    "pipe": ("logistics", "energy-pipe-distribution"), "stone-furnace": ("production", "smelting-machine"),
    "burner-mining-drill": ("production", "extraction-machine"), "electric-mining-drill": ("production", "extraction-machine"),
    "assembling-machine-1": ("production", "production-machine"), "assembling-machine-2": ("production", "production-machine"),
    "lab": ("production", "production-machine"), "boiler": ("production", "energy"), "steam-engine": ("production", "energy"),
    "gun-turret": ("combat", "turret"), "stone-wall": ("combat", "defensive-structure"), "firearm-magazine": ("combat", "ammo"),
    "pistol": ("combat", "gun"),
}
# Stats Factoriopedia shows, for the mock's entities.
ENTITY_STATS = {
    "assembling-machine-1": {"hp": 300, "craft": 0.5, "energy": 77500, "drain": 2500, "etype": "electric", "poll": {"pollution": 4},
                             "cats": ["crafting", "basic-crafting", "advanced-crafting"], "size": [3, 3]},
    "assembling-machine-2": {"hp": 350, "craft": 0.75, "energy": 157500, "drain": 5000, "etype": "electric", "poll": {"pollution": 3},
                             "modules": 2, "effects": ["consumption", "pollution", "productivity", "quality", "speed"], "size": [3, 3]},
    "stone-furnace": {"hp": 200, "craft": 1, "energy": 90000, "etype": "burner", "fuels": ["chemical"], "poll": {"pollution": 2},
                      "res": [["fire", 0, 90], ["explosion", 0, 30], ["impact", 0, 30]], "size": [2, 2]},
    "burner-mining-drill": {"hp": 150, "mine_speed": 0.25, "energy": 150000, "etype": "burner", "fuels": ["chemical"],
                            "poll": {"pollution": 12}, "mradius": 2, "size": [2, 2]},
    "electric-mining-drill": {"hp": 300, "mine_speed": 0.5, "energy": 90000, "etype": "electric", "poll": {"pollution": 10},
                              "modules": 3, "mradius": 5, "size": [3, 3]},
    "transport-belt": {"hp": 150, "belt": 15, "res": [["fire", 0, 90]], "size": [1, 1], "next": "fast-transport-belt"},
    "fast-transport-belt": {"hp": 160, "belt": 30, "res": [["fire", 0, 50]], "size": [1, 1]},
    "inserter": {"hp": 150, "energy": 13200, "drain": 400, "etype": "electric", "rot": 302.4, "size": [1, 1]},
    "burner-inserter": {"hp": 100, "energy": 94200, "etype": "burner", "fuels": ["chemical"], "rot": 216, "size": [1, 1]},
    "wooden-chest": {"hp": 100, "inv": 16, "size": [1, 1]}, "iron-chest": {"hp": 200, "inv": 32, "size": [1, 1]},
    "lab": {"hp": 150, "energy": 60000, "etype": "electric", "research": 1, "modules": 2, "packs": ["automation-science-pack"], "size": [3, 3]},
    "boiler": {"hp": 200, "energy": 1800000, "etype": "burner", "poll": {"pollution": 30}, "size": [3, 2]},
    "steam-engine": {"hp": 400, "power": 900000, "size": [3, 5]},
    "gun-turret": {"hp": 400, "range": 18, "size": [2, 2]}, "stone-wall": {"hp": 350, "res": [["physical", 3, 20], ["impact", 45, 60]], "size": [1, 1]},
    "small-electric-pole": {"hp": 100, "wire": 7.5, "supply": 5, "size": [1, 1]},
    "small-biter": {"hp": 15, "speed": 12.96, "res": []}, "tree-01": {"hp": 50, "mine": [["item", "wood", 4]], "mtime": 0.55},
    "big-rock": {"mine": [["item", "stone", 20]], "mtime": 2}, "iron-ore": {"mine": [["item", "iron-ore", 1]], "mtime": 1},
}
FUEL = {"coal": 4e6, "wood": 2e6}
QUALITIES = [["normal", 0, "uncommon", 0.1, [1, 1, 1]], ["uncommon", 1, "rare", 0.1, [0.37, 0.89, 0.37]],
             ["rare", 2, "epic", 0.1, [0.17, 0.53, 1]], ["epic", 3, "legendary", 0.1, [0.67, 0.17, 1]],
             ["legendary", 5, "", 0, [1, 0.5, 0.11]]]


def _group(name, entity_type=None):
    if name in ITEM_GROUP:
        return ITEM_GROUP[name]
    if entity_type in ("tree", "simple-entity", "cliff", "resource", "fish", "plant"):
        return ("environment", entity_type)
    if entity_type in ("unit", "unit-spawner", "turret", "segmented-unit", "spider-unit"):
        return ("enemies", entity_type)
    return ("intermediate-products", "raw-material")


class InfoMixin:
    """Methods for MockServer; it provides send_now, send_parts, entities, player and the tables."""

    def info_command(self, t, msg, protos):
        if t == "pedia_index":
            self.send_pedia_index(protos)
        elif t == "pedia":
            self.send_pedia_page(str(msg.get("kind", "")), str(msg.get("name", "")), protos)
        elif t == "lnets":
            rp = self.roboport
            x, y = (int(rp.x * 256), int(rp.y * 256)) if rp is not None else (0, 0)
            self.send_now({"t": "lnets", "l": [[1, 1, "nauvis", [3, 3], [0, 0], 1, 1, 0, 1, x, y, ""],
                                               [2, 1, "nauvis", [10, 12], [4, 5], 4, 6, 2, 9, 0, 0, "[item=iron-plate] Mall"]]})
        elif t == "lnet":
            nid = int(msg.get("id", 0)) if isinstance(msg.get("id"), int) else 0
            if nid == 1:
                self.send_now(dict(self.network_summary(True), t="lnet", found=1))
            elif nid == 2:
                self.send_now({"t": "lnet", "id": 2, "found": 1, "log": [10, 12], "con": [4, 5],
                               "items": [["iron-plate", 1200], ["copper-plate", 800], ["electronic-circuit", 400], ["repair-pack", 20]]})
            else:
                self.send_now({"t": "lnet", "id": nid, "found": 0})

    # --- Factoriopedia -----------------------------------------------------------------------

    def send_pedia_index(self, protos):
        entity_protos, items, fluids, tiles, recipes, techs, planets = protos
        l = []
        for name in items:
            g, sg = _group(name)
            l.append(["item", name, g, sg, "a"])
        for name, _ in fluids:
            l.append(["fluid", name, "fluids", "fluid", "a"])
        for name, etype, *_ in entity_protos:
            if name not in items and etype not in ("entity-ghost", "segment", "character", "cargo-pod"):
                g, sg = _group(name, etype)
                l.append(["entity", name, g, sg, "a"])
        for name, _ in tiles:
            l.append(["tile", name, "tiles", "tiles", "a"])
        for name in planets:
            l.append(["planet", name, "space", "planets", "a"])
        for q in QUALITIES:
            l.append(["quality", q[0], "other", "qualities", "%03d" % q[1]])
        for name in recipes:
            if name not in items:
                l.append(["recipe", name, "intermediate-products", "recipes", "a"])
        for name in techs:
            l.append(["technology", name, "technologies", "technologies", "a-" + name])
        order = {g[0]: g[1] for g in GROUPS}
        l.sort(key=lambda r: (order.get(r[2], "z"), r[3], r[4], r[1]))
        parts = [l[i:i + 120] for i in range(0, len(l), 120)] or [[]]
        for i, part in enumerate(parts):
            m = {"t": "pidx", "part": i + 1, "parts": len(parts), "l": part}
            if i == 0:
                m["g"] = GROUPS
            self.send_reliable(m)

    def send_pedia_page(self, kind, name, protos):
        entity_protos, items, fluids, tiles, recipes, techs, planets = protos
        etypes = {p[0]: p[1] for p in entity_protos}
        made = sorted(r for r, (_, (product, _n)) in recipes.items() if product == name)
        used = sorted(r for r, (needs, _) in recipes.items() if name in needs)
        d = None
        if kind == "item" and name in items:
            g, sg = _group(name)
            d = {"group": g, "sub": sg, "type": "item", "stack": 100 if name.endswith("plate") or name == "iron-gear-wheel" else 50,
                 "weight": 1000 if name.endswith("plate") or name == "iron-gear-wheel" else 20000,
                 "made": made, "used": used, "mined": sorted(e for e, s in ENTITY_STATS.items()
                                                             if any(m[1] == name for m in s.get("mine", [])))}
            if name in FUEL:
                d.update(fuel=FUEL[name], fcat=["chemical"])
            if name in etypes:
                d["place"] = name
                d["entity"] = dict(ENTITY_STATS.get(name, {}), type=etypes[name], items=[name])
        elif kind == "fluid" and name in [f[0] for f in fluids]:
            d = {"group": "fluids", "sub": "fluid", "temp": 15, "max_temp": 100, "heat": 2000, "made": made, "used": used,
                 "tiles": ["water"] if name == "water" else []}
        elif kind == "entity" and name in etypes:
            g, sg = _group(name, etypes[name])
            d = dict(ENTITY_STATS.get(name, {}), group=g, sub=sg, type=etypes[name], items=[])
        elif kind == "recipe" and name in recipes:
            needs, (product, count) = recipes[name]
            d = {"group": "intermediate-products", "sub": "recipes", "ing": [["item", k, v] for k, v in needs.items()],
                 "prod": [["item", product, count]], "time": 0.5, "cats": ["crafting"],
                 "made_in": ["assembling-machine-1", "assembling-machine-2", "character"], "unlocked": [], "enabled": 1}
        elif kind == "technology" and name in techs:
            pre, ings, count, seconds = techs[name]
            d = {"group": "technologies", "sub": "technologies", "pre": pre, "succ": sorted(t for t, v in techs.items() if name in v[0]),
                 "cost": ings, "count": count, "time": seconds, "effects": [["unlock-recipe", "iron-gear-wheel", 0]] if name == "automation" else [],
                 "level": 1, "max_level": 1, "state": 2 if name in self.researched else 1, "saved": 0}
        elif kind == "tile" and name in [t[0] for t in tiles]:
            d = {"group": "tiles", "sub": "tiles", "walk": 1.0, "friction": 1.0, "absorb": {"pollution": 0.4} if "grass" in name else {},
                 "items": [], "fluid": "water" if "water" in name else None}
            d = {k: v for k, v in d.items() if v is not None}
        elif kind == "planet" and name in planets:
            d = {"group": "space", "sub": "planets", "props": planets[name]["props"], "kind": "planet", "solar": 1,
                 "links": [[p, 15000] for p in planets if p != name][:2]}
        elif kind == "quality" and name in [q[0] for q in QUALITIES]:
            q = next(q for q in QUALITIES if q[0] == name)
            d = {"group": "other", "sub": "qualities", "level": q[1], "prob": q[3], "color": q[4], "mult": {"default_multiplier": 1 + 0.3 * q[1]}}
            if q[2]:
                d["next"] = q[2]
        if d is None:
            self.send_now({"t": "pedia", "kind": kind, "name": name, "found": 0, "d": {}})
        else:
            self.send_now({"t": "pedia", "kind": kind, "name": name, "found": 1, "d": d})

    # --- alerts --------------------------------------------------------------------------------

    def alert_message(self):
        """The mock's alerts: its gun turret is out of ammo (it never has any), a chest east of
        the start was destroyed, ghosts lack material, and the stone furnaces are out of fuel
        until the character fills them."""
        l = []

        def rec(e, extra=None):
            r = [int(e.x * 256), int(e.y * 256), 1, e.name, e.unit]
            if extra is not None:
                r.append(extra)
            return r
        if self.surface != "nauvis":
            return {"t": "al", "l": []}
        turrets = [e for e in self.entities.values() if e.type == "ammo-turret"]
        empty = [e for e in turrets if not self.machine(e).get("inv", {}).get("turret_ammo")]
        if empty:
            l.append(["no_ammo", len(empty), [rec(e) for e in empty[:40]]])
        l.append(["destroyed", 1, [[int(6.5 * 256), int(-4.5 * 256), 1, "wooden-chest", 0]]])
        ghosts = [e for e in self.entities.values() if e.name == "entity-ghost"]
        if ghosts:
            l.append(["no_material", len(ghosts), [[int(e.x * 256), int(e.y * 256), 1, "transport-belt", e.unit, "transport-belt"]
                                                   for e in ghosts[:40]]])
        furnaces = [e for e in self.entities.values() if e.name == "stone-furnace" and not self.machine(e).get("inv", {}).get("fuel")]
        if furnaces:
            l.append(["no_fuel", len(furnaces), [rec(e, "no_fuel") for e in furnaces[:40]]])
        return {"t": "al", "l": l}

    # --- statistics ----------------------------------------------------------------------------

    @staticmethod
    def stats_extra(kind, msg, rows, surface_index):
        """Building counts and pollution rows, the surface and graph lines for a `stats` reply."""
        out = {}
        if kind != "electric":
            si = msg.get("si")
            out["si"] = si if isinstance(si, int) else surface_index
        else:
            out["st"] = [["accumulator", 3200000, 3400000]]
        g = msg.get("g")
        if isinstance(g, list):
            names = [str(n) for n in g] or [r[0] for r in rows[:5]]
            lines = []
            for n in names[:8]:
                row = next((r for r in rows if r[0] == n), None)
                if row is None:
                    continue
                lines.append([n, [round(row[1] * (1 + 0.3 * math.sin(i / 6)), 2) for i in range(60)],
                              [round(row[2] * (1 + 0.3 * math.cos(i / 7)), 2) for i in range(60)]])
            out["gr"] = lines
        return out


STATS_MORE = {"build": [["transport-belt", 4.0, 0.2, 400, 20], ["inserter", 1.0, 0.0, 120, 3], ["stone-furnace", 0.2, 0.0, 24, 0]],
              "pollution": [["stone-furnace", 6.0, 0.0, 3600, 0], ["boiler", 30.0, 0.0, 18000, 0], ["grass-1", 0.0, 20.0, 0, 12000],
                            ["tree-01", 0.0, 4.0, 0, 2400]]}
