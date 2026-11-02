"""Space Age's screens for the mock server (mock_server.py), like the mod's space.lua: the space
platform hub (state, weight, thrusters, schedule with interrupts, requests from planets), the
rocket silo (parts, status, automatic launch, launch to a platform), cargo landing pads (requests,
circuit settings), cargo bays, asteroid collectors (chunk filters), module effects and recipe
quality, the solar system (`smap`), new platforms (`plat_new`), asteroid chunks on the platform
(`ach`) caught by the platform's asteroid collectors (`acol`: an arm each reaching 0.2 tiles a tick
for a chunk in its catch circle, as in 2.1.23), quality on belt items (`bq`) and what can't be built on a surface (`planet.nb`).

A launch is drawn: `rk` and a rocket mover rising from the silo, then a cargo pod coming down on
the landing pad (`cp` and a cargo-pod mover)."""

import math

QUALITIES = ["normal", "uncommon", "rare"]
# Entity type -> screen kind, merged into mock_server.SCREEN_KINDS.
SPACE_KINDS = {"space-platform-hub": "hub", "cargo-landing-pad": "pad", "cargo-bay": "bay",
               "asteroid-collector": "collector", "rocket-silo": "silo"}
ENTITY_PROTOS = [
    ("rocket-silo", "rocket-silo", 9, 9, (130, 130, 135)),
    ("cargo-landing-pad", "cargo-landing-pad", 8, 8, (120, 120, 125)),
    ("rocket-silo-rocket", "rocket-silo-rocket", 2, 2, (220, 220, 225)),
]
ITEMS = ["space-platform-starter-pack", "quality-module", "metallic-asteroid-chunk", "carbonic-asteroid-chunk",
         "oxide-asteroid-chunk", "rocket-part", "processing-unit", "low-density-structure", "rocket-fuel"]
CHUNKS = ["metallic-asteroid-chunk", "carbonic-asteroid-chunk", "oxide-asteroid-chunk"]
# Factorio 2.1's star map (distance, orientation from the prototypes): positions, then magnitude, orbit, label orientation.
LOCATIONS = [("nauvis", "planet", 14.815, 2.347),
             ("vulcanus", "planet", 5.878, -8.09),
             ("gleba", "planet", 17.82, -9.08),
             ("fulgora", "planet", 22.275, 11.35),
             ("aquilo", "planet", 34.569, -5.475),
             ("solar-system-edge", "space-location", 50.0, -0.0),
             ("shattered-planet", "space-location", 80.0, -0.0)]
LOCATION_LOOK = {"nauvis": (1, 1, 0.25), "vulcanus": (1.5, 1, 0.25), "gleba": (1.1, 1, 0.15), "fulgora": (0.9, 1, 0.35), "aquilo": (1.0, 1, 0.15), "solar-system-edge": (1.0, 1, 0.15), "shattered-planet": (1.0, 0, 0.25)}
CONNECTIONS = [("nauvis", "vulcanus", 15000, 120), ("nauvis", "gleba", 15000, 140), ("nauvis", "fulgora", 15000, 180),
               ("vulcanus", "gleba", 20000, 260), ("gleba", "fulgora", 20000, 300), ("fulgora", "aquilo", 30000, 650),
               ("gleba", "aquilo", 30000, 600), ("aquilo", "solar-system-edge", 100000, 850),
               ("solar-system-edge", "shattered-planet", 4000000, 1000)]
SILO_AT, PAD_AT = (-18.5, -1.5), (-6.0, -21.0)
PARTS_NEEDED = 50
PART_TICKS = 6
ROCKET_TICKS = 600   # the rocket is drawn rising and leaving for this long
POD_DELAY = 300      # after the launch, a cargo pod comes down on the pad
POD_TICKS = 240
CHUNK_INTERVAL = 10
# Asteroid collectors as 2.1.23's prototype has them: the catch circle 7.5 tiles round a point 5
# tiles in front, a head that grabs within 0.6, one arm at 0.2 tiles a tick that drops its chunk
# 1.5 tiles from the centre.
COLLECT_RADIUS, COLLECT_OFFSET, HEAD_RADIUS, ARM_SPEED, DEPOSIT = 7.5, 5.0, 0.6, 0.2, 1.5
# What can't be built on a platform (no gravity): [entity, property, min, max].
PLATFORM_BLOCKED = [("burner-mining-drill", "gravity", 0.1, 1e9), ("straight-rail", "gravity", 0.1, 1e9),
                    ("car", "gravity", 0.1, 1e9)]


def section(filters, i=1):
    return {"i": i, "g": "", "on": 1, "m": 1, "man": 1, "f": filters}


class Space:
    def __init__(self, server, destinations, planets):
        self.s = server
        self._destinations, self.planets = destinations, planets
        self.silo = None
        self.pad = None
        self.launches = []   # [{"at": tick, "x", "y", "rocket": mover unit, "pod": mover unit}]
        self.sent_chunks = False
        self.sent_quality = False
        self.floating = None    # asteroid chunks over the platform: [{"name", "x", "y", "vx", "vy"}]
        self.arms = {}          # collector unit -> {"hx", "hy", "target" (a chunk), "carry" (its name)}
        self.grabs = []         # [[unit, chunk, x, y], ...] caught since the last `acol`
        self.collector_rows = None
        self.new_platforms = []  # platforms made with plat_new, waiting for their starter pack

    # --- the world --------------------------------------------------------------------------

    def build_nauvis(self, add):
        self.silo = add("rocket-silo", *SILO_AT)
        self.pad = add("cargo-landing-pad", *PAD_AT)

    def machine(self, entity):
        kind = SPACE_KINDS.get(entity.type)
        if kind is None:
            return None
        m = {"recipe": None, "progress": 0, "inv": {}}
        if kind == "hub":
            m["inv"] = {"chest": {"iron-plate": 400, "metallic-asteroid-chunk": 12,
                                  "rocket-fuel": 20}, "trash": {}}
            m["sec"] = [section([["iron-plate", "normal", 200, -1, "nauvis", -1],
                                 ["rocket-fuel", "normal", 50, 100, "nauvis", 20]])]
            m["prov"] = 0
            m["interrupts"] = []
            m["waits"] = {}
        elif kind == "pad":
            m["inv"] = {"chest": {"iron-plate": 100, "processing-unit": 20}, "trash": {}}
            m["sec"] = [section([["processing-unit", "normal", 50, -1, "", -1]])]
            m["pcb"] = None
        elif kind == "silo":
            m["inv"] = {"input": {"processing-unit": 40, "low-density-structure": 40, "rocket-fuel": 40},
                        "rocket": {"space-platform-starter-pack": 1}}
            m["auto"] = 0
        elif kind == "collector":
            m["inv"] = {"output": {"metallic-asteroid-chunk": 3, "carbonic-asteroid-chunk": 1}}
            m["col"] = {"n": 3, "f": ["metallic-asteroid-chunk", "", ""]}
        return m

    def destinations(self):
        return self._destinations

    def hub_info(self, m):
        s = self.s
        pf = s.platform
        rec = s.platform_record()
        names = pf["sched"]["l"] if pf["sched"] else []
        records = [{"station": n, "wait_conditions": m["waits"].get(n, [{"type": "all_requests_satisfied", "compare_type": "and"}])}
                   for n in names]
        info = {k: rec[k] for k in ("i", "n", "st", "pa", "sp") if k in rec}
        for k in ("loc", "from", "to", "d", "len"):
            if k in rec:
                info[k] = rec[k]
        info.update({"w": 1250000, "th": [2, 2 if rec["sp"] > 0 else 0],
                     "fuel": [["thruster-fuel", 1600, 2000], ["thruster-oxidizer", 1400, 2000]],
                     "sched": {"current": pf["sched"]["c"] if pf["sched"] else 0, "records": records, "group": "",
                               "interrupts": m["interrupts"]},
                     "sec": m["sec"], "prov": m["prov"], "dest": self.destinations()})
        return info

    def gui_fields(self, entity, m, kind):
        out = {}
        if kind == "hub":
            out["hub"] = self.hub_info(m)
            out["ql"] = QUALITIES
            # The hub's first stack is rare, to show quality in slots.
            out["quality_slot"] = ("chest", 0, "rare")
        elif kind == "pad":
            out["pad"] = {"sec": m["sec"]}
            if m["pcb"] is not None:
                out["pad"]["cb"] = m["pcb"]
            out["ql"] = QUALITIES
        elif kind == "bay":
            out["bay"] = {"owner": self.s.platform["hub"] or 0}
        elif kind == "collector":
            out["col"] = m["col"]
        elif kind == "silo":
            out["rk"] = {"parts": m.get("parts", 0), "need": PARTS_NEEDED, "st": m.get("st", "building_rocket"),
                         "auto": m["auto"], "to": self.launch_targets()}
        elif kind == "crafter":
            out["ql"] = QUALITIES
            if m.get("q") and m["q"] != "normal":
                out["rq"] = m["q"]
            if any(m["inv"].get("modules", {}).values()):
                out["eff"] = {"q": 25, "sp": -50}
        return out

    def launch_targets(self):
        pf = self.s.platform
        out = []
        if pf["loc"] == "nauvis":
            out.append([pf["i"], pf["n"], self.s.platform_state()])
        for p in self.new_platforms:
            out.append([p["i"], p["n"], "waiting_for_starter_pack"])
        return out

    # --- commands ---------------------------------------------------------------------------

    def open_entity(self, msg):
        s = self.s
        sc = s.screen
        entity = s.entities.get(sc["unit"]) if sc else None
        if entity is None or int(msg.get("u", 0)) != sc["unit"]:
            return None, None, None
        sc["due"] = s.tick
        return entity, s.machine(entity), SPACE_KINDS.get(entity.type)

    def command(self, t, msg):
        """Handles a space command; returns True if it was one."""
        s = self.s
        if t == "smap":
            s.send_now({"t": "smap",
                        "loc": [[n, typ, int(x * 1000), int(y * 1000), int(n in self.destinations() or n == "nauvis"),
                                 int(n in ("nauvis",) or n in s.worlds or n == s.surface),
                                 int(LOCATION_LOOK[n][0] * 1000), LOCATION_LOOK[n][1], int(LOCATION_LOOK[n][2] * 1000)]
                                for n, typ, x, y in LOCATIONS],
                        "con": [list(c) for c in CONNECTIONS]})
            return True
        if t == "plat_new":
            inv = s.player["inventory"]
            if inv.get("space-platform-starter-pack", 0) < 1:
                s.message("You need a space platform starter pack")
            else:
                i = 2 + len(self.new_platforms)
                self.new_platforms.append({"i": i, "n": f"Platform {i}"})
                s.message(f"New platform Platform {i} over nauvis: launch its starter pack from a rocket silo")
            return True
        if t not in ("set_section", "set_hub", "set_silo", "silo_launch", "set_pad", "set_collector",
                     "set_schedule", "train_go", "set_interrupts", "set_recipe"):
            return False
        entity, m, kind = self.open_entity(msg)
        if entity is None:
            return t != "set_recipe" and t not in ("set_schedule", "train_go", "set_interrupts")
        if t == "set_recipe":
            q = msg.get("q")
            if q and q not in QUALITIES:
                s.message("That quality isn't researched")
                return True
            m["q"] = q if q in QUALITIES else "normal"
            return False  # the mock's machine screens set the recipe itself
        if t in ("set_schedule", "train_go", "set_interrupts"):
            if kind != "hub":
                return False
            pf = s.platform
            if t == "set_schedule" and isinstance(msg.get("records"), list):
                recs = [r for r in msg["records"] if isinstance(r, dict) and r.get("station") in self.destinations()]
                pf["sched"] = {"c": 1, "l": [r["station"] for r in recs]} if recs else None
                m["waits"] = {r["station"]: r.get("wait_conditions", []) for r in recs}
            elif t == "train_go" and pf["sched"]:
                i = int(msg.get("i", 1))
                if 1 <= i <= len(pf["sched"]["l"]):
                    pf["sched"]["c"] = i
            elif t == "set_interrupts" and isinstance(msg.get("interrupts"), list):
                m["interrupts"] = [x for x in msg["interrupts"] if isinstance(x, dict)]
            s.send_platforms()
            return True
        needs = {"set_section": ("hub", "pad"), "set_hub": ("hub",), "set_silo": ("silo",), "silo_launch": ("silo",),
                 "set_pad": ("pad",), "set_collector": ("collector",)}[t]
        if kind not in needs:
            s.message("That can't be set here")
            return True
        if t == "set_section":
            i = int(msg.get("i", 0))
            if msg.get("del") == 1:
                if 1 <= i <= len(m["sec"]):
                    m["sec"].pop(i - 1)
            else:
                if i == 0:
                    m["sec"].append(section([], len(m["sec"]) + 1))
                    i = len(m["sec"])
                if 1 <= i <= len(m["sec"]):
                    sec = m["sec"][i - 1]
                    if isinstance(msg.get("f"), list):
                        sec["f"] = [[str(f[0]), str(f[1] or "normal"), int(f[2]), int(f[3]), str(f[4]), int(f[5])]
                                    for f in msg["f"] if isinstance(f, list) and len(f) == 6]
                    if isinstance(msg.get("g"), str) and int(msg.get("i", 0)):
                        sec["g"] = msg["g"]
                    if msg.get("on") in (0, 1):
                        sec["on"] = msg["on"]
                    if isinstance(msg.get("m"), (int, float)):
                        sec["m"] = msg["m"]
            for k, sec in enumerate(m["sec"]):
                sec["i"] = k + 1
        elif t == "set_hub":
            if msg.get("prov") in (0, 1):
                m["prov"] = msg["prov"]
            if msg.get("pa") in (0, 1):
                s.platform["pa"] = msg["pa"]
        elif t == "set_silo":
            if msg.get("auto") in (0, 1):
                m["auto"] = msg["auto"]
        elif t == "silo_launch":
            if m.get("st") != "rocket_ready":
                s.message("The rocket isn't ready")
            elif not any(p[0] == msg.get("to") for p in self.launch_targets()):
                s.message("That platform isn't in orbit here")
            else:
                self.launch(entity, m, int(msg.get("to")))
        elif t == "set_pad":
            cb = m["pcb"] or {"read": 1, "req": 0, "empty": 0}
            for k in ("read", "req", "empty"):
                if msg.get(k) in (0, 1):
                    cb[k] = msg[k]
            m["pcb"] = cb
        elif t == "set_collector" and isinstance(msg.get("f"), list):
            f = [str(x) if x in CHUNKS else "" for x in msg["f"][:3]]
            m["col"]["f"] = f + [""] * (3 - len(f))
        return True

    def launch(self, silo, m, to):
        s = self.s
        m["parts"], m["st"] = 0, "launch_started"
        waiting = [p for p in self.new_platforms if p["i"] == to]
        if waiting:
            self.new_platforms.remove(waiting[0])
            m["inv"]["rocket"] = {}
            s.message(f"{waiting[0]['n']}'s starter pack is on its way")
        else:
            m["inv"]["rocket"] = {}
        s.send_now({"t": "rk", "u": silo.unit, "x": round(silo.x * 256), "y": round(silo.y * 256), "s": s.surface})
        rocket = s._unit()
        s.movers.append({"unit": rocket, "name": "rocket-silo-rocket", "kind": "parked", "x": silo.x, "y": silo.y, "o": 0.0,
                         "speed": 0.0, "space_until": s.tick + ROCKET_TICKS})
        self.launches.append({"at": s.tick, "pod": None})

    # --- every tick -------------------------------------------------------------------------

    def tick(self):
        s = self.s
        if s.surface == "nauvis" and self.silo is not None:
            m = s.machine(self.silo)
            if m.get("st", "building_rocket") == "building_rocket" and s.tick % PART_TICKS == 0:
                m["parts"] = m.get("parts", 0) + 1
                if m["parts"] >= PARTS_NEEDED:
                    m["parts"], m["st"] = PARTS_NEEDED, "rocket_ready"
            elif m.get("st") == "launch_started" and not any(x.get("name") == "rocket-silo-rocket" for x in s.movers):
                m["st"] = "building_rocket"
            if m.get("st") == "rocket_ready" and m["auto"] == 1 and s.platform["loc"] == "nauvis":
                self.launch(self.silo, m, s.platform["i"])
            s.movers[:] = [x for x in s.movers if x.get("space_until", s.tick + 1) > s.tick]
            for launch in self.launches:
                if launch["pod"] is None and s.tick - launch["at"] >= POD_DELAY and self.pad is not None:
                    launch["pod"] = s._unit()
                    s.movers.append({"unit": launch["pod"], "name": "cargo-pod", "kind": "parked", "x": self.pad.x,
                                     "y": self.pad.y, "o": 0.0, "speed": 0.0, "space_until": s.tick + POD_TICKS})
            live = [x for x in self.launches if x["pod"] is None or s.tick - x["at"] < POD_DELAY + POD_TICKS]
            pods = [x["pod"] for x in live if x["pod"] is not None]
            if s.tick % 10 == 0 and (pods or len(live) != len(self.launches)):
                s.send_now({"t": "cp", "l": [[u, "descending", "station", "nauvis"] for u in pods]})
            self.launches = live
        on_platform = s.surface not in self.planets
        if on_platform:
            self.drift()
            self.collect()
        if s.tick % CHUNK_INTERVAL == 0:
            chunks = self.chunks() if on_platform else []
            if chunks or self.sent_chunks:
                s.send_now({"t": "ach", "l": chunks})
            self.sent_chunks = bool(chunks)
            self.send_collectors(on_platform)

    def drift(self):
        """Chunks drifting past the platform, north to south; one caught or gone south starts
        again at the north edge."""
        if self.floating is None:
            self.floating = [{"name": CHUNKS[i % 3], "x": -20.0 + i * 3.6, "y": -40.0 + (i * 7.3) % 80.0,
                              "vx": 0.0, "vy": 0.03} for i in range(12)]
        for c in self.floating:
            c["x"] += c["vx"]
            c["y"] += c["vy"]
            if c["y"] > 40.0:
                c["y"] -= 80.0

    def collectors(self):
        return [e for e in self.s.entities.values() if e.name == "asteroid-collector"]

    def collect(self):
        """Each collector's arm reaches for the nearest chunk its filters take in its catch circle,
        grabs it when the head gets there, pulls it in and drops it in the output."""
        for e in self.collectors():
            m = self.s.machine(e)
            arm = self.arms.setdefault(e.unit, {"hx": e.x, "hy": e.y, "target": None, "carry": None})
            filters = [f for f in m["col"]["f"] if f]
            if arm["carry"] is None and arm["target"] is None:
                a = e.dir / 16 * 2 * math.pi
                cx, cy = e.x + math.sin(a) * COLLECT_OFFSET, e.y - math.cos(a) * COLLECT_OFFSET
                taken = {id(o["target"]) for o in self.arms.values() if o["target"] is not None}
                free = [c for c in self.floating if id(c) not in taken and (not filters or c["name"] in filters)
                        and (c["x"] - cx) ** 2 + (c["y"] - cy) ** 2 <= COLLECT_RADIUS ** 2]
                if free:
                    arm["target"] = min(free, key=lambda c: (c["x"] - e.x) ** 2 + (c["y"] - e.y) ** 2)
            if arm["target"] is not None:
                c = arm["target"]
                if self.step(arm, c["x"], c["y"]) <= HEAD_RADIUS:
                    self.grabs.append([e.unit, c["name"], round(c["x"] * 256), round(c["y"] * 256)])
                    arm["carry"], arm["target"] = c["name"], None
                    c["y"] = -40.0
            elif self.step(arm, e.x, e.y) <= DEPOSIT and arm["carry"]:
                out = m["inv"]["output"]
                out[arm["carry"]] = out.get(arm["carry"], 0) + 1
                arm["carry"] = None

    @staticmethod
    def step(arm, x, y):
        """Moves the arm's head a tick towards (x, y); how far from there it is left."""
        dx, dy = x - arm["hx"], y - arm["hy"]
        d = math.hypot(dx, dy)
        k = min(1.0, ARM_SPEED / d) if d > 0 else 0.0
        arm["hx"] += dx * k
        arm["hy"] += dy * k
        return d * (1.0 - k)

    def send_collectors(self, on_platform):
        """`acol` as the mod sends it: the collectors' rows when they change, what they caught."""
        s = self.s
        rows = []
        if on_platform:
            for e in sorted(self.collectors(), key=lambda e: e.unit):
                rows.append([e.unit, 1, round(ARM_SPEED * 1000), 1, [f for f in s.machine(e)["col"]["f"] if f]])
        msg = {"t": "acol"}
        if rows != self.collector_rows and (rows or self.collector_rows):
            msg["l"] = rows
        self.collector_rows = rows
        if self.grabs and on_platform:
            msg["g"] = self.grabs
        self.grabs = []
        if len(msg) > 1:
            s.send_now(msg)

    def chunks(self):
        """[[name, x, y, vx, vy], ...] in 1/256 tile, movement per second."""
        return [[c["name"], round(c["x"] * 256), round(c["y"] * 256), round(c["vx"] * 60 * 256), round(c["vy"] * 60 * 256)]
                for c in self.floating or []]

    def belt_quality(self, items):
        """[[unique id, quality], ...] for some of the belt items (every 7th uncommon, every 23rd rare)."""
        out = [[uid, "rare" if uid % 23 == 0 else "uncommon"] for uid in items if uid % 7 == 0 or uid % 23 == 0]
        if out or self.sent_quality:
            self.s.send_now({"t": "bq", "l": out})
        self.sent_quality = bool(out)

    def blocked(self, surface_is_platform, eid):
        if not surface_is_platform:
            return []
        return [[eid[n], p, lo, hi] for n, p, lo, hi in PLATFORM_BLOCKED if n in eid]

    def cant_build(self, surface_is_platform, name):
        for n, prop, lo, _ in PLATFORM_BLOCKED:
            if surface_is_platform and n == name:
                return f"Can't build here: {prop} is 0 m/s², it needs at least {lo} m/s²"
        return None
