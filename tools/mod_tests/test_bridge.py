"""Runs the bridge mod's control.lua against fake_factorio.lua and checks what it sends.

    pip install lupa
    python3 tools/mod_tests/test_bridge.py

Lupa embeds Lua 5.2, the version Factorio uses. The fake API raises on unknown keys like the
real one, so wrong property reads show up here instead of as an in-game crash.
"""

import json
import math
import pathlib
import sys

from lupa import lua52

ROOT = pathlib.Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))
import protocol  # noqa: E402
MOD = ROOT / "mod" / "factorio-3d-bridge"
FAKE = pathlib.Path(__file__).with_name("fake_factorio.lua")
CLIENT_PORT = 34201
MAX_DATAGRAM = 16 * 1024

lua = lua52.LuaRuntime(unpack_returned_tuples=True)


def to_py(value):
    if lua52.lua_type(value) == "table":
        items = list(value.items())
        if not items:
            return []
        keys = [k for k, _ in items]
        if all(isinstance(k, (int, float)) for k in keys) and sorted(keys) == list(range(1, len(keys) + 1)):
            return [to_py(value[i]) for i in range(1, len(keys) + 1)]
        return {str(k): to_py(v) for k, v in items}
    if isinstance(value, float) and value.is_integer():
        return int(value)
    return value


def to_json(table):
    return json.dumps(to_py(table), separators=(",", ":"))


def from_json(text):
    try:
        data = json.loads(text)
    except ValueError:
        return None
    return lua.table_from(data, recursive=True)


g = lua.globals()
g.F_to_json = to_json
g.F_from_json = from_json
lua.execute(FAKE.read_text())
g.package.path = str(MOD / "?.lua") + ";" + g.package.path
lua.execute((MOD / "control.lua").read_text())
F = g.F

failures = []


def check(cond, what):
    if not cond:
        failures.append(what)
        print("FAIL:", what)


def tick(n=1):
    for _ in range(n):
        F.tick()


def send(msg, port=CLIENT_PORT):
    F.packet(json.dumps(msg), port)


expected_r = 1
most_batched = 0  # the most messages seen in one datagram (a client whose hello says b)


def take():
    """Everything sent since the last call. Checks ports, sizes and that reliable messages are
    numbered without gaps (a welcome restarts the numbering at 1)."""
    global expected_r
    out = []
    for item in F.take_sent().values():
        port, data = item[1], item[2]
        check(port == CLIENT_PORT, f"sent to wrong port {port}")
        check(len(data) <= MAX_DATAGRAM, f"datagram too large: {len(data)} bytes")
        global most_batched
        lines = protocol.split_datagram(data)
        most_batched = max(most_batched, len(lines))
        for msg in lines:
            for problem in protocol.problems(msg):
                check(False, f"protocol: {problem}")
            if "r" in msg:
                if msg["t"] == "welcome":
                    expected_r = msg["r"]
                check(msg["r"] == expected_r, f"reliable sequence gap: got {msg['r']}, expected {expected_r} ({msg['t']})")
                expected_r = msg["r"] + 1
            out.append(msg)
    return out


def of_type(msgs, t):
    return [m for m in msgs if m.get("t") == t]


def spawn(name, x, y, **extra):
    return F.spawn(name, x, y, lua.table_from(extra, recursive=True))


def fixed(v):
    return int(math.floor(v * 256 + 0.5))


# --- world setup ------------------------------------------------------------------------------
spawn("tree-01", 5.3, 7.9)
spawn("iron-ore", 2.5, 1.5, amount=2)
spawn("assembling-machine-1", 10.5, 10.5, force="player")
spawn("transport-belt", 40.5, 3.5, force="player", direction=4)  # chunk (1, 0)
spawn("cliff", 46.0, 10.5, cliff_orientation="north-to-west")  # chunk (1, 0)
spawn("small-biter", 6.0, 6.0, force="enemy")
spawn("car", 3.0, 3.0, force="player")
spawn("explosion", 4.0, 4.0)
spawn("assembling-machine-1-remnants", 20.5, 20.5)  # left by a destroyed assembler
spawn("small-biter-corpse", 22.0, 22.0)  # a corpse, not a remnant: not streamed
spawn("linked-belt", 24.5, 3.5, force="player", linked_belt_type="output")
F.surface.set_tile(1, 1, "concrete")

F.on_init()
tick(5)
check(take() == [], "nothing should be sent before a client says hello")

# --- handshake ----------------------------------------------------------------------------------
send({"t": "hello", "v": 1, "sid": "s1", "w": 0})
tick(4)  # the handshake goes out a few stages a tick under the work budget
msgs = take()
welcome = of_type(msgs, "welcome")
check(len(welcome) == 1, "one welcome after hello")
check(msgs and msgs[0]["t"] == "welcome" and msgs[0]["r"] == 1, "welcome is the first reliable message, r=1")
check(welcome and welcome[0]["u"] > 0, "welcome names the puppet character")
protos = [rec for m in of_type(msgs, "protos") for rec in m["l"]]
names = {rec[1]: rec for rec in protos}
check("assembling-machine-1" in names, "entity prototypes are sent")
check(names.get("assembling-machine-1", [0] * 12)[3:7] == [-1.5, -1.5, 1.5, 1.5], "prototype box is the selection box")
tprotos = [rec for m in of_type(msgs, "tprotos") for rec in m["l"]]
check({rec[1] for rec in tprotos} == {"grass-1", "water", "concrete", "stone-path", "space-platform-foundation", "empty-space"}, "tile prototypes are sent")
check(of_type(msgs, "ready"), "ready marks the end of the handshake")
eprops = of_type(msgs, "eprops")
ep = {rec[0]: rec for rec in eprops[0]["l"]} if eprops else {}
pid = {rec[1]: rec[0] for m in of_type(msgs, "protos") for rec in m["l"]}
check(ep.get(pid["underground-belt"], [0, 0])[1] == 5 and ep.get(pid["small-electric-pole"], [0, 0, 0, 0])[2:] == [7.5, 2.5],
      f"eprops gives underground reach and pole wire reach and supply area: {eprops[:1]}")
over = {name: (ep.get(pid[name]) or [0] * 5)[4:] for name in ("inserter", "roboport", "offshore-pump")}
check(over["inserter"] == [{"ip": [0, -1], "id": [0, 1.2]}] and over["roboport"] == [{"lr": 25, "cr": 55}]
      and over["offshore-pump"] == [{"fb": [[0, -0.5, 0, "o"]]}],
      f"eprops' overlay: inserter pickup and drop, roboport areas, fluid connections: {over}")
iuse = {(rec[0], rec[1]): rec for m in of_type(msgs, "iuse") for rec in m["l"]}
tid = {rec[1]: rec[0] for rec in tprotos}
check(iuse.get(("speed-module", "m")) == ["speed-module", "m", "speed"] and ("wooden-chest", "m") not in iuse,
      f"iuse: modules and their category (F6: the client asks for them by clicking): {iuse.get(('speed-module', 'm'))}")
# Concrete goes where water doesn't collide: not on water, nor on empty space (it collides like water).
check(iuse.get(("concrete", "t")) == ["concrete", "t", "concrete", "", sorted(tid[n] for n in ("grass-1", "stone-path", "space-platform-foundation"))]
      and iuse.get(("grenade", "c")) == ["grenade", "c", "throw", 15, 0] and iuse.get(("cliff-explosives", "c")) == ["cliff-explosives", "c", "destroy-cliffs", 10, 1.5]
      and iuse.get(("rail", "r")) == ["rail", "r", "rail-support", 0] and iuse.get(("transport-belt", "b")) == ["transport-belt", "b", "underground-belt"],
      f"iuse: tiles (what they may go on), capsules, the rail planner, a belt's underground: {sorted(iuse.values())}")
inv = of_type(msgs, "inv")
check(inv and ["iron-plate", 8] in inv[0]["l"], "starter kit shows up in the inventory")
recipes = of_type(msgs, "recipes")
check(recipes and sorted(recipes[0]["l"]) == ["iron-gear-wheel", "transport-belt"],
      "recipe list has enabled hand-craftable recipes only (2.1 'categories' API)")
eid = {rec[1]: rec[0] for rec in protos}
iprotos = [rec for m in of_type(msgs, "iprotos") for rec in m["l"]]
iid = {rec[1]: rec[0] for rec in iprotos}
fid = {rec[1]: rec[0] for m in of_type(msgs, "fprotos") for rec in m["l"]}
check(set(fid) == {"water", "steam"}, f"fluid prototypes are sent: {sorted(fid)}")
check({"iron-plate", "iron-gear-wheel", "transport-belt"} <= set(iid), "item prototypes are sent")
planet = of_type(msgs, "planet")
check(planet and planet[-1]["name"] == "nauvis" and planet[-1]["props"].get("gravity") == 10 and planet[-1]["day"] == 25000
      and planet[-1]["dusk"] == 250 and [eid["heating-tower"], 12] in planet[-1]["heat"],
      f"planet: the surface's planet, properties, day and heating radii come with the handshake: {planet[-1:]}")
check(msgs.index(of_type(msgs, "iprotos")[0]) < msgs.index(of_type(msgs, "ready")[0]), "item prototypes come before ready")
check(not of_type(msgs, "clog"), "no clog before the force has character logistic requests (no requester point)")

# --- chunk subscription ----------------------------------------------------------------------
send({"t": "sub", "c": [[0, 0], [1, 0], [9, 9]]})
send({"t": "focus", "x": 0, "y": 0, "r": 48})
tick(25)  # long enough to include a machine-state report (every 30 ticks)
msgs = take()
chunks = {(m["cx"], m["cy"]): m for m in of_type(msgs, "chunk")}
check(set(chunks) == {(0, 0), (1, 0), (9, 9)}, f"one chunk message per subscription, got {sorted(chunks)}")
check(chunks.get((9, 9), {}).get("none") is True, "ungenerated chunk is reported as none")
c00 = chunks.get((0, 0), {})
rle = c00.get("tiles", [])
check(sum(rle[1::2]) == 1024, "tile RLE covers all 32x32 tiles")
tile_id = {rec[1]: rec[0] for rec in tprotos}
check(rle[:6] == [tile_id["grass-1"], 33, tile_id["concrete"], 1, tile_id["grass-1"], 990],
      f"tile RLE is row-major with the concrete tile at (1, 1): {rle[:6]}")
ents = {}
for m in of_type(msgs, "ents"):
    for rec in m["e"]:
        ents.setdefault((m["cx"], m["cy"]), []).append(rec)
static00 = {rec[1] for rec in ents.get((0, 0), [])}
check(static00 == {eid["tree-01"], eid["iron-ore"], eid["assembling-machine-1"], eid["assembling-machine-1-remnants"],
                   eid["linked-belt"]},
      f"chunk (0,0) holds the tree, ore, assembler, remnants and linked belt, not movers, effects or corpses: {static00}")
remnant = [rec for rec in ents.get((0, 0), []) if rec[1] == eid["assembling-machine-1-remnants"]]
check(remnant and remnant[0][0] == 0 and remnant[0][5] == {"rm": eid["assembling-machine-1"]},
      f"remnants carry what they were left by: {remnant}")
linked = [rec for rec in ents.get((0, 0), []) if rec[1] == eid["linked-belt"]]
check(linked and linked[0][5].get("u") == "o", f"a linked belt carries its end: {linked}")
gone = spawn("small-remnants", 12.5, 14.5)  # what a destroyed chest leaves
F["raise"]("on_post_entity_died", lua.table_from({"corpses": lua.table_from([gone])}))
tick(1)
added = [m for m in of_type(take(), "add") if m["e"][1] == eid["small-remnants"]]
check(added and added[0]["e"][5] == {"rm": 0},
      f"a death's remnants are sent as they appear; shared ones name no single source: {added}")
# The queue follows the client's order (nearest the character first) whatever queued a chunk:
# after a jump, chunks still queued for the old place and land generated later go by distance.
queue_after = lua.eval("""function()
  local W = package.loaded["scripts.world"]
  local s = storage.f3d
  local saved_subs, saved_queue, saved_queued, saved_rank = s.subs, s.queue, s.queued, s.rank
  s.subs, s.queue, s.queued, s.rank = {}, {}, {}, {}
  W.subscribe({ { 0, 0 }, { 1, 0 }, { 2, 0 }, { 3, 0 } })
  W.subscribe({ { 3, 0 }, { 4, 0 }, { 2, 0 }, { 5, 0 }, { 1, 0 } })  -- jumped east: 0,0 dropped
  local first = table.concat(s.queue, " ")
  table.remove(s.queue, 1)  -- 3,0 sent
  s.queued["3,0"] = nil
  W.on_chunk_generated(game.surfaces[1], { x = 3, y = 0 })  -- generated again: first again
  W.enqueue("9,9")  -- not subscribed: last
  local second = table.concat(s.queue, " ")
  s.subs, s.queue, s.queued, s.rank = saved_subs, saved_queue, saved_queued, saved_rank
  return first .. "|" .. second
end""")()
check(queue_after == "3,0 4,0 2,0 5,0 1,0|3,0 4,0 2,0 5,0 1,0 9,9",
      f"the chunk queue keeps the client's nearest-first order after a jump and as chunks are generated: {queue_after}")
belt = [rec for rec in ents.get((1, 0), []) if rec[1] == eid["transport-belt"]]
check(belt and belt[0][2:5] == [40 * 256 + 128, 3 * 256 + 128, 4] and belt[0][5] == {"s": "s"},
      "belt record: fixed-point position, direction, shape")
cliff = [rec for rec in ents.get((1, 0), []) if rec[1] == eid["cliff"]]
check(cliff and cliff[0][0] == 0 and cliff[0][5] == {"co": "north-to-west"}, f"a cliff carries its orientation: {cliff}")
ore = [rec for rec in ents.get((0, 0), []) if rec[1] == eid["iron-ore"]]
check(ore and ore[0][0] == 0 and ore[0][5] == {"a": 2}, "ore has no unit number and carries its amount")
movers = [rec for m in of_type(msgs, "mv") for rec in m["l"]]
mover_protos = {rec[1] for rec in movers}
# A rocket waiting in its silo has no unit number in 2.1.23; it gets a stable id above
# every unit number.
waiting = spawn("rocket-silo-rocket", 4.5, -6.5, force="player")
tick(12)  # movers.lua searches for new movers every 8 ticks
rk_ids = [rec[0] for m in of_type(take(), "mv") for rec in m["l"] if rec[1] == eid["rocket-silo-rocket"]]
check(rk_ids and all(i == rk_ids[0] and i > 2 ** 40 for i in rk_ids), f"a rocket waiting in a silo is sent as a mover with a stable id: {rk_ids[:3]}")
waiting.destroy()
check(eid["small-biter"] in mover_protos and eid["car"] in mover_protos and eid["character"] in mover_protos,
      "movers stream the biter, car and puppet")
car = [rec for rec in movers if rec[1] == eid["car"]]
check(car and car[0][4] == 250, "car orientation is sent in thousandths")
check(of_type(msgs, "me"), "puppet state is streamed")
st = of_type(msgs, "st")
check(st and st[0]["l"][1] == 1, "working machines are reported")
bi = of_type(msgs, "bi")
check(bi and all(m["l"] == [] for m in bi), "belt item updates are sent, empty while no belt near the focus has items")
check(not of_type(msgs, "dec") and not of_type(msgs, "dprotos"), "no decoratives for a client that didn't ask for them (dc)")

# --- decoratives --------------------------------------------------------------------------------
F.add_decorative(F.surface, "green-carpet-grass", 3, 4, 2)
F.add_decorative(F.surface, "small-rock", 40, 5)
F.add_decorative(F.surface, "brown-asterisk", 300, 300)  # in no subscribed chunk
send({"t": "hello", "v": 1, "sid": "s1", "w": 1, "dc": 1})
tick(25)
msgs = take()
did = {rec[1]: rec[0] for m in of_type(msgs, "dprotos") for rec in m["l"]}
check(set(did) == {"green-carpet-grass", "brown-asterisk", "small-rock"}, f"dc in the hello sends the decorative dictionary: {did}")
dec = {}
for m in of_type(msgs, "dec"):
    dec.setdefault((m["cx"], m["cy"]), []).extend(m["l"])
check(dec.get((0, 0)) == [did.get("green-carpet-grass"), 3, 4, 2] and dec.get((1, 0)) == [did.get("small-rock"), 8, 5, 1]
      and set(dec) == {(0, 0), (1, 0)},
      f"and the subscribed chunks again with their decoratives (id, tile in the chunk, amount): {dec}")
lua.eval("function(s, n) local keep = {} for _, d in ipairs(s.decoratives) do if d.name ~= n then keep[#keep + 1] = d end end s.decoratives = keep end")(
    F.surface, "green-carpet-grass")
F["raise"]("on_player_built_tile", lua.table_from({"surface_index": 1, "tiles": lua.table_from([lua.table_from(
    {"position": lua.table_from({"x": 3, "y": 4}), "old_tile": "grass-1"})])}))
tick(30)
dec = [m for m in of_type(take(), "dec")]
check(len(dec) == 1 and (dec[0]["cx"], dec[0]["cy"]) == (0, 0) and dec[0]["l"] in ([], {}),
      f"a tile placed in a chunk sends its decoratives again (now none): {dec}")
F["raise"]("script_raised_built", lua.table_from({"entity": spawn("wooden-chest", 40.5, 5.5, force="player")}))
tick(30)
dec = [(m["cx"], m["cy"]) for m in of_type(take(), "dec")]
check(dec == [(1, 0)], f"building in a chunk sends its decoratives again: {dec}")
send({"t": "hello", "v": 1, "sid": "s1", "w": 1})
tick(30)
F["raise"]("script_raised_built", lua.table_from({"entity": spawn("wooden-chest", 41.5, 5.5, force="player")}))
tick(30)
check(not of_type(take(), "dec"), "a hello without dc turns decoratives off")

# --- items on belts ---------------------------------------------------------------------------
belt_e = spawn("transport-belt", 8.5, 2.5, force="player", direction=4)
under_e = spawn("underground-belt", 9.5, 2.5, force="player", direction=4)
F.put_on_belt(belt_e, 1, "iron-plate", 0.25, 7)
F.put_on_belt(belt_e, 2, "iron-gear-wheel", 0.75, 8)
F.put_on_belt(under_e, 1, "iron-plate", 0.2, 9)
F.put_on_belt(under_e, 3, "iron-plate", 0.5, 10)  # in the tunnel
far_e = spawn("transport-belt", 40.5, 10.5, force="player")  # outside the 24-tile item radius
F.put_on_belt(far_e, 1, "iron-plate", 0.5, 11)
tick(6)
msgs = take()
bi = of_type(msgs, "bi")
check(len(bi) == 1, f"one belt item update every 6 ticks, got {len(bi)}")
items = {}
for m in bi:
    l = m["l"]
    for i in range(0, len(l), 4):
        items[l[i]] = l[i + 1:i + 4]
check(set(items) == {7, 8, 9}, f"items on belts near the focus are sent, not the tunnel or far ones: {sorted(items)}")
check(all(m.get("fx") == fixed(0) and m.get("fy") == fixed(0) and m.get("fr") == 24 for m in bi),
      f"each bi part says which square it covers (focus, radius), for the hand-over to lane icons: {[(m.get('fx'), m.get('fy'), m.get('fr')) for m in bi]}")
# Line positions count from the exit edge (2.1.23): 0.25 is a quarter tile before the east edge.
check(items.get(7) == [iid["iron-plate"], 8 * 256 + 192, 580],
      f"left lane of an east belt is north of its centre: {items.get(7)}")
check(items.get(8) == [iid["iron-gear-wheel"], 8 * 256 + 64, 700],
      f"right lane is south; position 0.75 is nearer the entry edge: {items.get(8)}")
# Too many items: the square shrinks to the last whole ring round the focus instead of stopping
# wherever Factorio's belt order got to (whole patches of a dense base went bare).
belt_mod = lua.eval('package.loaded["scripts.belt_items"]')
belt_mod.max_items = 2
tick(12)
capped = of_type(take(), "bi")
capped_items = {capped[0]["l"][i] for i in range(0, len(capped[0]["l"]), 4)} if capped else set()
check(capped_items == {7, 8} and all(m.get("fr") == 9 for m in capped),
      f"over the cap, the nearest whole rings are sent (8 tiles out) and fr says the square shrank to 9: {sorted(capped_items)} {[m.get('fr') for m in capped]}")
belt_mod.max_items = 6000
tick(6)
plain = take()
send({"t": "hello", "v": 1, "sid": "s1", "w": 1, "z": 1})
tick(6)
coded_msgs = take()
bi = of_type(coded_msgs, "bi")
coded = {}
for m in bi:
    l, prev = m["l"], [0, 0, 0, 0]
    for i in range(0, len(l), 4):
        prev = [p + d for p, d in zip(prev, l[i:i + 4])]
        coded[prev[0]] = prev[1:]
check(bi and all(m.get("z") == 1 for m in bi) and coded == items,
      f"a client that asks for z gets the same items delta-coded: {coded}")

# Belts far away as one icon per lane (bfar), by what each lane carries, when it changes.
send({"t": "bfar", "r": 200})
tick(3)
far_msgs = of_type(take(), "bfar")
far = {(m["cx"], m["cy"]): m["l"] for m in far_msgs}
far_counts = {(m["cx"], m["cy"]): m.get("c") for m in far_msgs}
far_row = next((far[(1, 0)][i:i + 5] for i in range(0, len(far.get((1, 0), [])), 5) if far[(1, 0)][i:i + 2] == [fixed(40.5), fixed(10.5)]), None)
near_row = next((far[(0, 0)][i:i + 5] for i in range(0, len(far.get((0, 0), [])), 5) if far[(0, 0)][i:i + 2] == [fixed(8.5), fixed(2.5)]), None)
check(far_row == [fixed(40.5), fixed(10.5), 0, iid["iron-plate"], 0] and near_row == [fixed(8.5), fixed(2.5), 4, iid["iron-plate"], iid["iron-gear-wheel"]],
      f"bfar: each belt's place, direction and what its two lanes carry: {far}")
near_i = next((i // 5 for i in range(0, len(far.get((0, 0), [])), 5) if far[(0, 0)][i:i + 2] == [fixed(8.5), fixed(2.5)]), None)
check(far_counts.get((1, 0)) == [1, 0] and near_i is not None and far_counts[(0, 0)][near_i * 2:near_i * 2 + 2] == [1, 1],
      f"bfar c: how many items each lane holds, so a full belt is drawn full: {far_counts}")
tick(3)
check(not of_type(take(), "bfar"), "bfar: a chunk is sent again only when what it carries changes")
# A chunk dropped and subscribed again inside one round is sent again (the client forgot its lanes).
send({"t": "sub", "c": [[0, 0], [9, 9]]})
tick(3)
send({"t": "sub", "c": [[0, 0], [1, 0], [9, 9]]})
tick(200)
check([(m["cx"], m["cy"]) for m in of_type(take(), "bfar")] == [(1, 0)],
      "bfar: a chunk subscribed again gets its lanes again, though they didn't change")
# A chunk's belts are read over several ticks, a few a tick (one busy chunk read whole took 48 ms).
far_mod = lua.eval('package.loaded["scripts.belt_items"]')
far_mod.far_belts_per_tick = 1
send({"t": "sub", "c": [[1, 0], [9, 9]]})
tick(3)
send({"t": "sub", "c": [[0, 0], [1, 0], [9, 9]]})
steps, sent = [], []
for _ in range(400):
    cur = g.storage.f3d.far.cur
    before = (cur.key, cur.i) if cur else None
    tick()
    cur = g.storage.f3d.far.cur
    if before and cur and cur.key == before[0]:
        steps.append(cur.i - before[1])
    sent += of_type(take(), "bfar")
    if sent:
        break
far00 = [m for m in sent if (m["cx"], m["cy"]) == (0, 0)]
check(far00 and len(far00[0]["l"]) == 10 and steps and max(steps) <= 1,
      f"bfar: a chunk is read a slice of belts a tick and sent whole: steps {steps}, {far00[:1]}")
far_mod.far_belts_per_tick = 100
send({"t": "bfar", "r": 0})
tick(3)
check(not of_type(take(), "bfar"), "bfar r 0 stops it")
# The client's "Belt items in full" distance (bfar n) replaces the map setting for belt items.
send({"t": "bfar", "r": 0, "n": 4})
tick(6)
check(not any(m["l"] for m in of_type(take(), "bi")), "bfar n 4: no items 8 tiles away are sent")
send({"t": "bfar", "r": 0})
tick(6)
check(any(m["l"] for m in of_type(take(), "bi")), "bfar without n: back to f3d-detail-radius")

# Belt items are read over several ticks (a round), a slice of work units a tick, and sent as one
# update stamped with the tick it is sent on: an item read early in the round is carried on to that
# tick at the speed it moved between its reads.


def bi_items(msgs):
    """{k: {unique id: [item id, x, y]}} and {k: [(uid) ...]} from bi parts, plain or delta-coded."""
    by_k, order = {}, {}
    for m in of_type(msgs, "bi"):
        l, prev = m["l"], [0, 0, 0, 0]
        for i in range(0, len(l), 4):
            rec = [p + d for p, d in zip(prev, l[i:i + 4])] if m.get("z") == 1 else l[i:i + 4]
            prev = rec
            by_k.setdefault(m["k"], {})[rec[0]] = rec[1:]
            order.setdefault(m["k"], []).append(rec[0])
    return by_k, order


take()
belt_mod.units_per_tick = 40
row = []
for i in range(12):
    e = spawn("transport-belt", 10.5 + i, 7.5, force="player", direction=4)
    F.put_on_belt(e, 1, "iron-plate", 0.2, 600 + 2 * i)
    F.put_on_belt(e, 2, "copper-plate", 0.6, 601 + 2 * i)
    row.append(e)
mover = row[0]  # ring 10: read in a round's first ticks
pos = 0.99
F.put_on_belt(mover, 2, "iron-gear-wheel", pos, 700)
truth, slices, msgs = {}, [], []
for _ in range(90):
    now = int(lua.eval("game.tick")) + 1
    pos -= 0.01
    F.move_on_belt(mover, 2, 700, pos)
    truth[now] = fixed(10.5 + (0.5 - pos))  # an east belt's line runs from its west edge to position 0 at the east
    before = belt_mod.round()
    start, units = (before.start, before.units) if before else (None, 0)
    F.tick()
    after = belt_mod.round()
    got = take()
    msgs += got
    if after:
        slices.append(after.units - (units if after.start == start else 0))
    elif of_type(got, "bi") and before:
        slices.append(None)  # sent this tick: the round is gone; its last slice was read on this tick
by_k, order = bi_items(msgs)
ks = sorted(by_k)
round_ticks = [n for n in slices if n is not None]
check(len(ks) >= 5 and max(round_ticks) <= 40 + 20 and sum(1 for n in round_ticks if n > 0) >= 2 * len(ks),
      f"bi rounds: each read over several ticks, no tick past its slice (40 units, plus the last belt): {round_ticks[:20]}")
check(all(len(order[k]) == len(set(order[k])) for k in ks) and all(set(by_k[k]) == set(by_k[ks[-1]]) for k in ks[1:]),
      f"each update has every item once: {[len(order[k]) for k in ks]}")
check({m.get("parts") for m in of_type(msgs, "bi")} == {1} and len(of_type(msgs, "bi")) == len(ks),
      "one update a round, sent on one tick")
off = [(k, by_k[k].get(700, [0, None])[1] - truth[k]) for k in ks[2:]]
check(off and all(abs(d) <= 1 for _, d in off),
      f"an item read ticks before the update is where it is on the update's tick (1/256 tiles off): {off}")
raw_off = [(k, by_k[k][700][1] - truth[k]) for k in ks[:1]]
check(raw_off and raw_off[0][1] != 0, f"(the first update, with nothing to go on, has it where it was read: {raw_off})")
gaps = {b - a for a, b in zip(ks, ks[1:])}
ps = {m.get("p") for m in of_type(msgs, "bi")}
check(gaps == ps and len(ps) == 1, f"updates come every p ticks: gaps {gaps}, p {ps}")
# An item missing from a round (it moved on to a belt read earlier, or was taken off) is carried on
# along its way once, so the client doesn't stop it, and then dropped.
last_x = by_k[ks[-1]][700][1]
F.move_on_belt(mover, 2, 700, None)
msgs = []
for _ in range(40):
    tick()
    msgs += take()
by_k, _ = bi_items(msgs)
ks = sorted(by_k)
present = [700 in by_k[k] for k in ks]
carried = [by_k[k][700][1] for k in ks if 700 in by_k[k]]
check(len(ks) >= 3 and present[0] and not any(present[2:]) and carried[-1] > last_x,
      f"an item gone from the belt is carried on for one update, then dropped: {present} {carried} (last {last_x})")
# A big round takes several of the job's ticks (m), and `rate` still stretches them.
belt_mod.units_per_tick = 6
spread = {}
for level in (0, 1):
    send({"t": "hello", "v": 1, "sid": "s1", "w": 1, "z": 1})  # keep-alive
    send({"t": "rate", "l": level})
    tick(300)  # past the change (the old ticks a while, m settling)
    take()
    send({"t": "hello", "v": 1, "sid": "s1", "w": 1, "z": 1})
    tick(300)
    msgs = take()
    ks = sorted({m["k"] for m in of_type(msgs, "bi")})[2:]
    spread[level] = ({b - a for a, b in zip(ks, ks[1:])}, {m.get("p") for m in of_type(msgs, "bi") if m["k"] in ks[:-1]})
check(spread[0][0] == spread[0][1] and min(spread[0][0]) > 6 and min(spread[0][0]) % 6 == 0
      and spread[1][0] == spread[1][1] and min(spread[1][0]) % 12 == 0 and min(spread[1][0]) >= min(spread[0][0]),
      f"a round that needs more ticks than the job's period takes several periods, rate 1 stretches them: {spread}")
send({"t": "rate", "l": 0})
# Parts are written as items are read; one that reaches into a ring the cap then drops is written
# again: rings 8-11 hold 7 items (each sent once, in parts of 2); ring 12 holds two belts: the first
# makes 9 (written out), the second 11, past the cap.
belt_mod.units_per_tick = 40
belt_mod.items_per_message = 2
belt_mod.max_items = 10
extra = spawn("transport-belt", 12.5, -3.5, force="player", direction=4)
F.put_on_belt(extra, 1, "iron-plate", 0.3, 800)
F.put_on_belt(extra, 2, "iron-plate", 0.3, 801)
row.append(extra)
g.storage.f3d.bi = None
tick(60)
by_k, order = bi_items(take())
ks = sorted(by_k)
want = {7, 8, 9, 600, 601, 602, 603}  # (700 was taken off above)
check(len(ks) > 2 and all(set(by_k[k]) == want and len(order[k]) == 7 for k in ks[1:]),  # the first round had no estimate: cut for time
      f"a round cut by the cap sends the whole rings before it, each item once: {[sorted(by_k[k]) for k in ks][1:3]}")
belt_mod.items_per_message = 300
belt_mod.max_items = 6000
# The client's Smooth belt items (`bfar` u): a round is read in one tick, so updates come every
# interval again even where the mod's own slices (40 units here) take several ticks.
send({"t": "bfar", "r": 0, "n": 24, "u": 10000000})
g.storage.f3d.bi = None
tick(60)
smooth_ps = {m.get("p") for m in of_type(take(), "bi")}
check(g.storage.f3d.bi_units == 10000000 and smooth_ps == {6}, f"bfar u: smooth belt items read a round a tick, every 6 ticks: {smooth_ps}")
send({"t": "bfar", "r": 0})
check(g.storage.f3d.bi_units is None, "bfar without u: back to the mod's slices")
belt_mod.units_per_tick = 1500
for e in row:
    e.destroy()
g.storage.f3d.bi = None
tick(6)
take()

# `rate`: a server under load sends its costliest updates less often (rate.lua). Each level doubles
# the interval of the jobs at its tier and above; the character's own `me` never slows down.
rate = g.require("scripts.rate")


def spacing(msgs, t):
    ks = sorted({m["k"] for m in of_type(msgs, t)})
    return {b - a for a, b in zip(ks, ks[1:])}, ks


expected = {0: {"bi": 6, "mv": 2, "ih": 6}, 1: {"bi": 12, "mv": 4, "ih": 6},
            2: {"bi": 24, "mv": 8, "ih": 6}, 3: {"bi": 48, "mv": 16, "ih": 12}}
seen_ticks = {}
changes = []  # every bi and mv message across the level changes, in order
for level in range(4):
    send({"t": "hello", "v": 1, "sid": "s1", "w": 1, "z": 1})  # keep-alive: 10 s without one drops the client
    send({"t": "rate", "l": level})
    tick(170)  # past the change: belt items and movers keep the old rate 120 ticks while the client eases in
    changes += [m for m in take() if m["t"] in ("bi", "mv")]
    tick(240)
    msgs = take()
    changes += [m for m in msgs if m["t"] in ("bi", "mv")]
    for t, every in expected[level].items():
        gaps, ks = spacing(msgs, t)
        seen_ticks[(level, t)] = set(ks)
        check(gaps == {every}, f"rate {level}: {t} every {every} ticks (got gaps {gaps})")
        ps = {m.get("p") for m in of_type(msgs, t)}
        check(ps == {every}, f"rate {level}: {t} says p = {every}, the ticks until the next (got {ps})")
    me_gaps, _ = spacing(msgs, "me")
    check(me_gaps == {2}, f"rate {level}: the character's me stays every 2 ticks (got {me_gaps})")
check(not (seen_ticks[(3, "bi")] & seen_ticks[(3, "ih")]) and all(k % 48 == 1 for k in seen_ticks[(3, "bi")])
      and all(k % 16 == 1 for k in seen_ticks[(3, "mv")]),
      "rate 3: stretched jobs run on ticks of their own, off the 30th and 60th")
check(all(k % 6 == 1 for k in seen_ticks[(0, "bi")]) and all(k % 2 == 1 for k in seen_ticks[(0, "mv")]),
      "rate 0: jobs keep their phase (off the ticks the once-a-second jobs share)")
# Across the changes (and back down to 0) the client is never kept waiting past what an update said
# (after a slow-down belt items and movers come at the old rate a while, already saying the new one).
send({"t": "rate", "l": 0})
tick(120)
changes += [m for m in take() if m["t"] in ("bi", "mv")]
late = []
for t in ("bi", "mv"):
    firsts = {}
    for m in changes:
        if m["t"] == t and m.get("part", 1) == 1:
            firsts.setdefault(m["k"], m.get("p"))
    ks = sorted(firsts)
    for a, b in zip(ks, ks[1:]):
        if b - a > firsts[a]:
            late.append((t, a, firsts[a], b))
check(not late, f"rate changes: each bi and mv comes no later than the last one said (late: {late[:5]})")
periods = {}
for level in range(4):
    g.storage.f3d.rate = level or None
    periods[level] = {job: rate.period(job, every) for job, every in
                      (("st", 30), ("wires", 30), ("en", 10), ("seg", 2), ("life", 60), ("fp", 60), ("tr", 30), ("ts", 6), ("gi", 30), ("rc", 10))}
check(periods[0] == {"st": 30, "wires": 30, "en": 10, "seg": 2, "life": 60, "fp": 60, "tr": 30, "ts": 6, "gi": 30, "rc": 10}
      and periods[1] == periods[0]
      and periods[2] == dict(periods[0], st=60, wires=60, en=20, seg=4, life=120)
      and periods[3] == {"st": 120, "wires": 120, "en": 40, "seg": 8, "life": 240, "fp": 120, "tr": 60, "ts": 12, "gi": 60, "rc": 20},
      f"rate: tier 2 jobs slow from level 2, tier 3 from level 3, each up to its longest: {periods}")
g.storage.f3d.rate = None
# Far belt lanes: rounds start less often and read fewer belts a tick.
check(rate.factor("lanes") == 1, "rate 0: far lanes as before")
send({"t": "rate", "l": 9})
tick(1)
check(rate.level() == 3, "rate: levels past 3 are 3")
send({"t": "rate", "l": -1})
tick(1)
check(rate.level() == 0, "rate: a level under 0 is 0")
F.commands["f3d-rate"](lua.table_from({"name": "f3d-rate", "parameter": "2"}))
check(rate.level() == 2, "/f3d-rate 2 sets the level from the console")
send({"t": "hello", "v": 1, "sid": "s1", "w": 1, "z": 1})
tick(1)
check(rate.level() == 2, "rate: the level stays while the same client says hello")
F.commands["f3d-rate"](lua.table_from({"name": "f3d-rate", "parameter": "0"}))
take()

# A client that says b gets each tick's messages joined by newlines (a datagram costs the game
# about a millisecond to send, whatever its size).
send({"t": "hello", "v": 1, "sid": "s1", "w": 1, "b": 1})
tick(1)
take()
most_batched = 0
tick(6)
msgs = take()
check(most_batched > 1 and of_type(msgs, "me") and of_type(msgs, "bi"), f"b: several messages to a datagram, each one whole: up to {most_batched}")
send({"t": "hello", "v": 1, "sid": "s1", "w": 1})
tick(1)
take()
most_batched = 0
tick(6)
take()
check(most_batched == 1, "without b, one message a datagram")


def last_frame(msgs, t):
    frames = {}
    for m in of_type(msgs, t):
        frames.setdefault(m["k"], []).append(m)
    return frames[max(frames)] if frames else []


def decode_groups(parts, width=4):
    out = []
    for m in parts:
        prev = [0] * width
        for i in range(0, len(m["l"]), width):
            group = m["l"][i:i + width]
            prev = [p + d for p, d in zip(prev, group)] if m.get("z") else group
            out.append(tuple(prev))
    return sorted(out)


def decode_records(parts):
    out = []
    for m in parts:
        prev = [0, 0, 0, 0]
        for rec in m["l"]:
            if m.get("z"):
                rec = [p + d for p, d in zip(prev, rec[:4])] + rec[4:]
                prev = rec[:4]
            out.append(tuple(rec))
    return sorted(out)


hands_plain, hands_coded = last_frame(plain, "ih"), last_frame(coded_msgs, "ih")
check(hands_coded and all(m.get("z") == 1 for m in hands_coded) and decode_groups(hands_coded) == decode_groups(hands_plain),
      f"and the inserter hands: {decode_groups(hands_coded)[:3]}")
movers_plain, movers_coded = last_frame(plain, "mv"), last_frame(coded_msgs, "mv")
check(len(decode_records(movers_plain)) >= 2 and all(m.get("z") == 1 for m in movers_coded)
      and decode_records(movers_coded) == decode_records(movers_plain), f"and the movers: {decode_records(movers_coded)} vs {decode_records(movers_plain)}")
send({"t": "hello", "v": 1, "sid": "s1", "w": 1})
g.settings["global"]["f3d-detail-radius"].value = 0
tick(12)
check(not of_type(take(), "bi"), "radius 0 turns belt items off")
g.settings["global"]["f3d-detail-radius"].value = 24
for e in (belt_e, under_e, far_e):
    e.destroy()

# --- inserter hands, lamps, time of day -----------------------------------------------------------
ins = spawn("inserter", 12.5, 2.5, force="player", direction=4)
lamp = spawn("small-lamp", 14.5, 2.5, force="player")
F.set_hand(ins, 12.9, 2.1, "iron-plate")
F.surface.daytime = 0.5
F.surface.darkness = 0.85
tick(60)
msgs = take()
hands = {}
for m in of_type(msgs, "ih"):
    l = m["l"]
    for i in range(0, len(l), 4):
        hands[l[i]] = l[i + 1:i + 4]
unit = ins.unit_number
check(hands.get(unit) == [int(12.9 * 256 + 0.5), int(2.1 * 256 + 0.5), iid["iron-plate"]],
      f"inserter hand position and held item are sent: {hands.get(unit)}")
F.set_hand(ins, 12.0, 2.5, None)
tick(6)
l = [m["l"] for m in of_type(take(), "ih")][-1:]
check(l and l[0][l[0].index(unit) + 3] == 0, "an empty hand is sent with item 0")
sky = of_type(msgs, "sky")
check(sky and sky[-1]["d"] == 500 and sky[-1]["n"] == 850, f"time of day is sent once a second: {sky[-1:]}")
lamp_states = [m["l"] for m in of_type(msgs, "st")]
check(any(lamp.unit_number in l[::2] for l in lamp_states), "a powered lamp is reported as working")
for e in (ins, lamp):
    e.destroy()

# Signals, accumulators and power switches report a state, not just working or not (`st`).
sig = spawn("rail-signal", 12.5, 4.5, force="player")
chain = spawn("rail-chain-signal", 13.5, 4.5, force="player")
acc = spawn("accumulator", 16, 4, force="player")
switch = spawn("power-switch", 19, 4, force="player")
acc.status = g.defines.entity_status.discharging
switch.power_switch_state = True
take()
tick(30 * 10)
states = {}
for m in of_type(take(), "st"):
    for i in range(0, len(m["l"]), 2):
        states[m["l"][i]] = m["l"][i + 1]
check(states.get(sig.unit_number) == 3 and states.get(chain.unit_number) == 3 and states.get(acc.unit_number) == 2
      and states.get(switch.unit_number) == 1, f"signals send red (3), an accumulator discharging (2), a switch on (1): {states}")
sig.signal_state = g.defines.signal_state.open
chain.signal_state = g.defines.signal_state.open
chain.chain_signal_state = g.defines.chain_signal_state.partially_open
acc.status = g.defines.entity_status.charging
switch.power_switch_state = False
tick(31)
states = {}
for m in of_type(take(), "st"):
    for i in range(0, len(m["l"]), 2):
        states[m["l"][i]] = m["l"][i + 1]
mine = {u: v for u, v in states.items() if u in (sig.unit_number, chain.unit_number, acc.unit_number, switch.unit_number)}
check(mine == {sig.unit_number: 1, chain.unit_number: 4, acc.unit_number: 1, switch.unit_number: 0},
      f"and their changes after: green (1), blue (4), charging (1), off (0): {mine}")
sig.signal_state = g.defines.signal_state.reserved
tick(31)
check(any(l[l.index(sig.unit_number) + 1] == 2 for l in (m["l"] for m in of_type(take(), "st")) if sig.unit_number in l[::2]),
      "a reserved signal is yellow (2)")
for e in (sig, chain, acc, switch):
    e.destroy()
send({"t": "hello", "v": 1, "sid": "s1", "w": 1})  # keep-alive: the client times out after 600 ticks
tick(1)
take()

# --- walking ------------------------------------------------------------------------------------
puppet = g.storage.f3d.puppet
send({"t": "walk", "d": 3})  # odd: rounds to an even walking direction
tick(1)
check(puppet.walking_state.walking and puppet.walking_state.direction == 4, "walk command sets walking_state")
tick(40)
check(not puppet.walking_state.walking, "walking stops when the client stops repeating the command")
take()
# An angle walks between the two 8-way directions either side of it, so the path follows it.
for a, want in ((55, (0, 2)), (125, (2,)), (980, (14, 0)), (600, (8, 10)), (250, (4,))):
    dirs = []
    for i in range(60):  # the fake session times out 600 ticks after its hello
        if i % 10 == 0:
            send({"t": "walk", "d": 2, "a": a})
        tick(1)
        dirs.append(puppet.walking_state.direction)
    sx = sum(math.sin(d / 16 * 2 * math.pi) for d in dirs)
    sy = sum(math.cos(d / 16 * 2 * math.pi) for d in dirs)
    got = math.degrees(math.atan2(sx, sy)) % 360
    off = abs((got - a * 0.36 + 180) % 360 - 180)
    check(set(dirs) <= set(want) and off < 1.5, f"walking at {a / 1000} turns steps {sorted(set(dirs))}, path {got:.2f} degrees ({off:.2f} off)")
mes = of_type(take(), "me")
check(mes and mes[-1].get("a") == 250 and mes[-1]["w"] == 1, f"me carries the walk's angle: {mes[-1:]}")
send({"t": "walk", "d": -1})
tick(1)
check(not puppet.walking_state.walking, "walk -1 stops an angled walk at once")
tick(4)
mes = of_type(take(), "me")
check(mes and "a" not in mes[-1], f"a stopped character's me has no angle: {mes[-1:]}")

# --- items on the ground ------------------------------------------------------------------------
def ground_items(msgs):
    l = [v for m in of_type(msgs, "gi") for v in m["l"]]
    return sorted(l[i:i + 3] for i in range(0, len(l), 3))


send({"t": "hello", "v": 1, "sid": "s1", "w": 1})  # keep-alive: the client times out after 600 ticks
plate_e = spawn("item-on-ground", 0.6, 0.3, stack={"name": "iron-plate", "count": 1})
gear_e = spawn("item-on-ground", -0.4, 0.9, stack={"name": "iron-gear-wheel", "count": 1})
wood_e = spawn("item-on-ground", 6.5, 0.5, stack={"name": "wood", "count": 1})  # out of pickup range
far_item = spawn("item-on-ground", 30.5, 0.5, stack={"name": "wood", "count": 1})  # outside the detail radius
tick(30)
msgs = take()
check(len(of_type(msgs, "gi")) == 1, f"ground items are sent every 30 ticks: {len(of_type(msgs, 'gi'))}")
expect = sorted([[iid["iron-plate"], fixed(0.6), fixed(0.3)], [iid["iron-gear-wheel"], fixed(-0.4), fixed(0.9)],
                 [iid["wood"], fixed(6.5), fixed(0.5)]])
check(ground_items(msgs) == expect, f"items on the ground near the focus are sent with item ids and positions: {ground_items(msgs)}")

inv = puppet.get_main_inventory()
before = {n: inv.get_item_count(n) for n in ("iron-plate", "iron-gear-wheel", "wood")}
for _ in range(3):
    send({"t": "pickup"})
    tick(9)
msgs = take()
check(not plate_e.valid and not gear_e.valid and wood_e.valid,
      "pickup takes the items within the character's item_pickup_distance, not the one further away")
check([inv.get_item_count(n) - before[n] for n in ("iron-plate", "iron-gear-wheel", "wood")] == [1, 1, 0],
      "picked-up items go to the inventory (mine_entity on the item-entity)")
check(len(of_type(msgs, "gi")) >= 4, f"ground items are sent every detail interval while picking up: {len(of_type(msgs, 'gi'))}")
check(ground_items(of_type(msgs, "gi")[-1:]) == [[iid["wood"], fixed(6.5), fixed(0.5)]], "picked-up items drop out of the list")
tick(40)
check(g.storage.f3d.pickup is None, "pickup stops when the client stops repeating it")
take()
tick(60)
check(len(of_type(take(), "gi")) == 2, "and ground items go back to twice a second")

F.inventory_space = 0
full_e = spawn("item-on-ground", 0.2, -0.5, stack={"name": "iron-plate", "count": 1})
for _ in range(4):
    send({"t": "pickup"})
    tick(9)
msgs = take()
fulls = [m for m in of_type(msgs, "msg") if m["text"] == "Inventory full"]
check(full_e.valid and len(fulls) == 1, f"a full inventory leaves the item and says so once per press: {len(fulls)} messages")
F.inventory_space = float("inf")
tick(40)
send({"t": "pickup"})
tick(9)
check(not full_e.valid, "pickup works again after letting go")
take()
g.settings["global"]["f3d-detail-radius"].value = 0
tick(60)
check(not of_type(take(), "gi"), "radius 0 turns ground items off")
g.settings["global"]["f3d-detail-radius"].value = 24
for e in (wood_e, far_item):
    e.destroy()
tick(30)
check([m["l"] for m in of_type(take(), "gi")] == [[]], "an empty update means no items on the ground")
send({"t": "hello", "v": 1, "sid": "s1", "w": 1})

# --- combat -------------------------------------------------------------------------------------
send({"t": "hello", "v": 1, "sid": "s1", "w": 1})  # keep-alive: the client times out after 600 ticks
shooting = g.defines.shooting
gun_slots, ammo_slots = F.slots[puppet].guns, F.slots[puppet].ammo
g.storage.f3d.guns_sig = None
tick(11)  # checked every 10 ticks; reliable messages go out on the next tick
msgs = take()
guns = of_type(msgs, "guns")
check(guns and guns[-1]["sel"] == 1 and [r[:3] for r in guns[-1]["l"]] == [["pistol", "firearm-magazine", 10], ["", "", 0], ["", "", 0]],
      f"guns: the starter pistol and magazines, per gun slot: {guns[-1:]}")
check(guns and guns[-1]["l"][0][4] == 10 and guns[-1]["l"][1][3:] == [0, 0],
      f"guns: rounds left and the magazine size for the ammo slot's bar: {guns[-1:]}")
me = of_type(msgs, "me")[-1]
check(me.get("mhp") == 250 and me.get("sh") == 0, f"me carries max health and whether the character is firing: {me}")

biter = spawn("small-biter", 3.0, 0.0, force="enemy")
send({"t": "shoot", "m": 0, "x": 3 * 256, "y": 0})
tick(2)
st = puppet.shooting_state
check(st.state == shooting.shooting_enemies and st.position.x == 3.0, "shoot m=0 sets shooting_state to shooting_enemies")
ammo_slots[1].ammo = 9  # the game fired a round
tick(4)  # me goes out every 2 ticks, before combat looks at the ammo
msgs = take()
check(of_type(msgs, "me")[-1].get("sh") == 1, "me.sh is 1 once the ammo goes down")
shots = of_type(msgs, "shot")
check(len(shots) == 1 and shots[0]["g"] == "pistol" and shots[0]["a"] == "firearm-magazine"
      and (shots[0]["x"], shots[0]["y"]) == (3 * 256, 0) and shots[0]["u"] == puppet.unit_number,
      f"shot: the round fired, with the gun, ammo and the nearest enemy (find_nearest_enemy) as its target: {shots}")
tick(10)
guns = of_type(msgs + take(), "guns")
check(guns and guns[-1]["l"][0][3:] == [9, 10], f"guns: a round fired shows in the magazine's rounds: {guns[-1:]}")
send({"t": "shoot", "m": 1, "x": 3 * 256, "y": 256})
tick(2)
st = puppet.shooting_state
check(st.state == shooting.shooting_selected and st.position.y == 1.0, "shoot m=1 shoots at the aim point (shooting_selected)")
tick(40)
check(puppet.shooting_state.state == shooting.not_shooting, "shooting stops when the client stops repeating it")
check(of_type(take(), "me")[-1].get("sh") == 0, "and me.sh goes back to 0")
send({"t": "shoot", "m": 0, "x": 0, "y": 0})
tick(2)
send({"t": "shoot", "m": -1})
tick(2)
check(puppet.shooting_state.state == shooting.not_shooting, "shoot m=-1 stops at once")
take()

enemy_chest = spawn("wooden-chest", 2.5, 2.5, force="enemy")
biter.health, enemy_chest.health = 6, 50
for e in (biter, enemy_chest):
    F["raise"]("on_entity_damaged", lua.table_from({"entity": e}))
tick(10)
hp = [m["l"] for m in of_type(take(), "hp")]
check(hp and sorted(zip(hp[-1][::2], hp[-1][1::2])) == sorted([(biter.unit_number, 60), (enemy_chest.unit_number, 500)]),
      f"hp: damaged entities near the camera with their health in thousandths: {hp[-1:]}")
enemy_chest.health = 100
tick(10)
hp = [m["l"] for m in of_type(take(), "hp")]
check(hp and hp[-1] == [biter.unit_number, 60], f"an entity back at full health drops out: {hp[-1:]}")
unit = biter.unit_number
for e in (biter, enemy_chest):
    F["raise"]("on_entity_died", lua.table_from({"entity": e}))
    e.destroy()
tick(10)
msgs = take()
died = [(m["u"], m["p"], m["x"], m["y"]) for m in of_type(msgs, "died")]
check((unit, eid["small-biter"], 3 * 256, 0) in died, f"died: a biter's death is reported where it died: {died}")
check(any(d["p"] == eid["wooden-chest"] for d in of_type(msgs, "del")) and any(d[1] == eid["wooden-chest"] for d in died),
      "a building that dies is deleted and its death reported")
check([m["l"] for m in of_type(msgs, "hp")][-1:] == [[]], "the dead biter drops out of hp")

ammo_slots[1].name = None
send({"t": "shoot", "m": 0, "x": 0, "y": 0})
tick(10)
send({"t": "shoot", "m": 0, "x": 0, "y": 0})
tick(10)
msgs = take()
check(sum(m["text"] == "Out of ammo" for m in of_type(msgs, "msg")) == 1, "shooting without ammo says so once per press")
check(of_type(msgs, "guns")[-1:] and of_type(msgs, "guns")[-1]["l"][0][:3] == ["pistol", "", 0], "guns follows the ammo inventory")
send({"t": "shoot", "m": -1})
gun_slots[2].name, gun_slots[2].count = "submachine-gun", 1
send({"t": "gun", "i": 2})
send({"t": "gun", "i": 3})  # empty: ignored
tick(11)
guns = of_type(take(), "guns")
check(puppet.selected_gun_index == 2 and guns and guns[-1]["sel"] == 2, f"gun selects a gun slot: {guns[-1:]}")
gun_slots[2].name = None
puppet.selected_gun_index = 1
ammo_slots[1].name, ammo_slots[1].count = "firearm-magazine", 10
tick(10)

# --- what weapons fire (shots.lua) -------------------------------------------------------------
send({"t": "hello", "v": 1, "sid": "s1", "w": 1})
take()
rocket = spawn("rocket", 2.0, 1.0)
beam_target = spawn("small-biter", 6.0, 0.0, force="enemy")
beam = spawn("chain-tesla-gun-beam-start", 4.0, 0.0, source=puppet, target=beam_target)
boom = spawn("grenade-explosion", -3.0, 2.0)
tick(4)
pj = of_type(take(), "pj")
rid = next((m["p"][0] for m in pj if m["p"]), None)
check(pj and pj[-1]["p"][1:] == ["rocket", 512, 256] and isinstance(rid, int),
      f"pj: a projectile in flight with its register_on_object_destroyed id and position: {pj[-1:]}")
check(pj and pj[-1]["b"][1:] == ["chain-tesla-gun-beam-start", fixed(puppet.position.x), fixed(puppet.position.y), 6 * 256, 0],
      f"pj.b: a beam from its source entity to its target (get_beam_source / get_beam_target): {pj[-1:]}")
check(sum(len(m["x"]) for m in pj) == 3 and pj[0]["x"] == ["grenade-explosion", -768, 512],
      f"pj.x: an explosion is reported once, while it lasts: {[m['x'] for m in pj]}")
rocket.position = lua.table_from({"x": 2.5, "y": 1.0})
tick(2)
rocket.destroy()
tick(2)
pj = of_type(take(), "pj")
check(pj and pj[-1]["e"] == [rid, 640, 256] and pj[-1]["p"] == [],
      f"pj.e: a projectile that is gone ended where it was last seen (on_object_destroyed): {[m['e'] for m in pj]}")
for e in (beam, boom, beam_target):
    e.destroy()
tick(2)
pj = of_type(take(), "pj")
check(len(pj) == 1 and pj[0]["p"] == [] and pj[0]["b"] == [], f"pj: one empty update when nothing is flying any more: {pj}")
tick(4)
check(not of_type(take(), "pj"), "pj: then nothing while nothing flies")
fire = spawn("fire-flame", 1.0, -2.0)
cloud = spawn("poison-cloud", -2.0, -2.0, time_to_live=900)
tick(16)
gf = of_type(take(), "gf")
fl = gf[-1]["l"] if gf else []
check(len(fl) == 10 and fl[1:5] == ["fire-flame", 256, -512, -1] and fl[6:10] == ["poison-cloud", -512, -512, 900],
      f"gf: fires and clouds on the ground with ids, a cloud's time_to_live: {gf[-1:]}")
fire.destroy()
cloud.destroy()
tick(15)
gf = of_type(take(), "gf")
check(gf and gf[-1]["l"] in ([], {}), f"gf: an empty list once they are gone: {gf[-1:]}")
tick(15)
check(not of_type(take(), "gf"), "gf: then nothing")

# --- driving ------------------------------------------------------------------------------------
send({"t": "hello", "v": 1, "sid": "s1", "w": 1})  # keep-alive: the client times out after 600 ticks
riding = g.defines.riding
same = lua.eval("function(a, b) return a == b end")  # Lua identity; Python's == compares wrappers
car = next(e for e in F.surface.entities.values() if e.name == "car")  # at (3, 3), 4.2 tiles away
send({"t": "enter"})
tick(4)
me = of_type(take(), "me")[-1]
check(same(car.get_driver(), puppet) and same(puppet.vehicle, car), "enter puts the character in the driver's seat of the nearest vehicle")
check(me.get("v") == car.unit_number and me.get("vs") == 0 and (me["x"], me["y"]) == (3 * 256, 3 * 256),
      f"me carries the vehicle, its speed, and the vehicle's position: {me}")
send({"t": "drive", "a": 1, "s": 1})
tick(2)
st = puppet.riding_state
check(st.acceleration == riding.acceleration.accelerating and st.direction == riding.direction.right,
      "drive sets riding_state (accelerate, turn right)")
car.speed = 0.25
send({"t": "drive", "a": 1, "s": 0})
tick(4)
msgs = take()
check(of_type(msgs, "me")[-1].get("vs") == 250, "me.vs is the vehicle's speed in thousandths of a tile per tick")
check(sum(m["text"] == "No fuel" for m in of_type(msgs, "msg")) == 1, "driving a car with no fuel says so once per press")
tick(40)
st = puppet.riding_state
check(st.acceleration == riding.acceleration.nothing and st.direction == riding.direction.straight,
      "riding stops when the client stops repeating drive")
car.burner.inventory.insert(lua.table_from({"name": "coal", "count": 5}))
send({"t": "drive", "a": 3, "s": -1})
tick(2)
check(puppet.riding_state.acceleration == riding.acceleration.reversing and puppet.riding_state.direction == riding.direction.left,
      "drive a=3 reverses, s=-1 turns left")
send({"t": "drive", "a": 0, "s": 0})
tick(2)
check(puppet.riding_state.acceleration == riding.acceleration.nothing, "drive 0, 0 stops at once")
check(not [m for m in of_type(take(), "msg") if m["text"] == "No fuel"], "no fuel message once there is fuel")
send({"t": "enter"})
tick(4)
me = of_type(take(), "me")[-1]
check(car.get_driver() is None and puppet.vehicle is None and "v" not in me, f"enter again gets out: {me}")
check(me["x"] == 5 * 256, "the character stands next to the vehicle")

other = spawn("character", 3.0, 3.0, force="player")
car.set_driver(other)
send({"t": "enter"})
tick(2)
check(same(car.get_passenger(), puppet), "with someone driving, enter takes a car's passenger seat")
send({"t": "enter"})
tick(2)
check(car.get_passenger() is None and same(car.get_driver(), other) and puppet.vehicle is None, "and gets out of it")
car.set_driver(None)
other.destroy()
puppet.position = lua.table_from({"x": 0, "y": 0})
loco = spawn("locomotive", -2.0, 0.0, force="player")  # nearer than the car
send({"t": "enter"})
send({"t": "drive", "a": 1, "s": 0})
tick(2)
check(same(loco.get_driver(), puppet) and loco.train.manual_mode is True, "driving a locomotive switches its train to manual mode")
send({"t": "enter"})
tick(2)
loco.destroy()
puppet.position = lua.table_from({"x": 30, "y": 0})
send({"t": "enter"})
tick(2)
check(any(m["text"] == "No vehicle nearby" for m in of_type(take(), "msg")), "enter with nothing near says so")
puppet.position = lua.table_from({"x": 0, "y": 0})
tick(2)
take()

# --- mining a tree -------------------------------------------------------------------------
tree = [rec for rec in ents[(0, 0)] if rec[1] == eid["tree-01"]][0]
for _ in range(4):
    send({"t": "mine", "u": 0, "p": tree[1], "x": tree[2], "y": tree[3]})
    tick(10)
tick(30)  # inventory is reported every 30 ticks
msgs = take()
dels = of_type(msgs, "del")
check(any(d["p"] == eid["tree-01"] and d["x"] == tree[2] for d in dels), "mined tree is deleted on the client")
inv = of_type(msgs, "inv")
check(inv and ["wood", 5] in inv[-1]["l"], "wood lands in the inventory")

# --- mining ore down to nothing ----------------------------------------------------------------
ore = ore[0]
for _ in range(20):
    send({"t": "mine", "u": 0, "p": ore[1], "x": ore[2], "y": ore[3]})
    tick(15)
tick(30)
msgs = take()
check(of_type(msgs, "upd"), "ore amount update is sent while mining")
check(any(d["p"] == eid["iron-ore"] for d in of_type(msgs, "del")), "depleted ore is deleted")
inv = of_type(msgs, "inv")
check(inv and ["iron-ore", 2] in inv[-1]["l"], "both ore units were mined")

# --- building, rotating ----------------------------------------------------------------------
puppet.insert(lua.table_from({"name": "transport-belt", "count": 5}))
send({"t": "build", "item": "transport-belt", "x": 2 * 256 + 40, "y": 5 * 256 + 200, "d": 4})
tick(2)
msgs = take()
adds = of_type(msgs, "add")
check(adds and adds[0]["e"][1] == eid["transport-belt"] and adds[0]["e"][2:5] == [2 * 256 + 128, 5 * 256 + 128, 4],
      "built belt is snapped to the tile centre and added")
send({"t": "build", "item": "assembling-machine-1", "x": 10 * 256, "y": 10 * 256, "d": 0})
tick(2)
msgs = take()
check(any(m.get("text") == "You have no assembling-machine-1" for m in of_type(msgs, "msg")),
      "building without the item explains why")
new_belt = adds[0]["e"]
send({"t": "rotate", "u": new_belt[0], "p": new_belt[1], "x": new_belt[2], "y": new_belt[3]})
tick(2)
msgs = take()
upd = of_type(msgs, "upd")
check(upd and upd[0]["e"][4] == 8, "rotated belt now faces south")
# Undergrounds: the second one built ahead of an entrance facing the same way is its exit.
puppet.insert(lua.table_from({"name": "underground-belt", "count": 2}))
send({"t": "build", "item": "underground-belt", "x": 3 * 256 + 128, "y": 7 * 256 + 128, "d": 4})
send({"t": "build", "item": "underground-belt", "x": 6 * 256 + 128, "y": 7 * 256 + 128, "d": 4})
tick(2)
pair = sorted((e for e in F.surface.entities.values() if e.name == "underground-belt" and e.position.y == 7.5),
              key=lambda e: e.position.x)
check([e.belt_to_ground_type for e in pair] == ["input", "output"],
      f"an underground built ahead of an entrance is its exit: {[e.belt_to_ground_type for e in pair]}")
for e in pair:
    e.destroy()
take()
send({"t": "build", "item": "underground-belt", "x": 3 * 256 + 128, "y": 7 * 256 + 128, "d": 4, "ghost": 1})
send({"t": "build", "item": "underground-belt", "x": 6 * 256 + 128, "y": 7 * 256 + 128, "d": 4, "ghost": 1})
tick(2)
ghost_ends = [a["e"][5].get("u") for a in of_type(take(), "add") if len(a["e"]) > 5 and a["e"][5].get("gh") == eid["underground-belt"]]
check(ghost_ends == ["i", "o"], f"underground ghosts are entrance then exit, sent as extra.u: {ghost_ends}")
for e in [e for e in F.surface.entities.values() if e.name == "entity-ghost" and e.position.y == 7.5]:
    e.destroy()
take()

# --- crafting ---------------------------------------------------------------------------------
send({"t": "craft", "recipe": "iron-gear-wheel", "n": 2})
send({"t": "craft", "recipe": "laser-turret", "n": 1})
tick(3)
msgs = take()
check(any("laser-turret" in m.get("text", "") for m in of_type(msgs, "msg")), "locked recipe is refused")
check(any(m.get("q") == 2 for m in of_type(msgs, "me")), "crafting queue size is reported")

# --- machine screens --------------------------------------------------------------------------
def fill(entity, role, name, count):
    F.inventories[entity][role].insert(lua.table_from({"name": name, "count": count}))


def open_cmd(entity):
    p = entity.position
    return {"t": "open", "u": entity.unit_number, "p": eid[entity.name],
            "x": int(p.x * 256 + 0.5), "y": int(p.y * 256 + 0.5)}


def guis(msgs, entity=None):
    return [m for m in of_type(msgs, "gui") if entity is None or m["u"] == entity.unit_number]


def last_inv(msgs):
    inv = of_type(msgs, "inv")
    return dict(map(tuple, inv[-1]["l"])) if inv else {}


send({"t": "hello", "v": 1, "sid": "s1", "w": 1})  # keep-alive: the client times out after 600 ticks
take()
chest = spawn("wooden-chest", 3.5, 0.5, force="player")
asm = spawn("assembling-machine-1", 4.5, -4.5, force="player")
furnace = spawn("stone-furnace", -3.0, -3.0, force="player")
lab = spawn("lab", -5.5, 3.5, force="player")
far_asm = spawn("assembling-machine-1", 20.5, 0.5, force="player")
enemy_chest = spawn("wooden-chest", 1.5, 1.5, force="enemy")
fill(chest, "chest", "iron-plate", 20)
fill(chest, "chest", "copper-plate", 3)

send(open_cmd(chest))
tick(2)
msgs = take()
g0 = guis(msgs, chest)
check(len(g0) == 1 and g0[0]["kind"] == "container" and g0[0]["p"] == eid["wooden-chest"],
      f"opening a chest sends its screen at once: {g0}")
check(g0 and g0[0]["inv"] == {"chest": [["iron-plate", 20], ["copper-plate", 3]]}, f"chest contents by role: {g0[:1]}")
check(g0 and not ({"recipe", "pr", "rl"} & set(g0[0])), "a chest has no recipe, progress or recipe list")
tick(30)
check(len(guis(take(), chest)) == 1, "the open screen is re-sent every 30 ticks")

plates = puppet.get_main_inventory().get_item_count("iron-plate")
send({"t": "take", "u": chest.unit_number, "inv": "chest", "item": "iron-plate", "n": 5})
tick(2)
msgs = take()
g1 = guis(msgs, chest)
check(g1 and g1[-1]["inv"]["chest"][0] == ["iron-plate", 15], f"take removes from the chest: {g1[-1:]}")
check(last_inv(msgs).get("iron-plate") == plates + 5, f"taken plates reach the character's inventory at once: {of_type(msgs, 'inv')}")
plates += 5
send({"t": "take", "u": chest.unit_number, "item": "copper-plate", "n": 100})
send({"t": "put", "u": chest.unit_number, "item": "wood", "n": 1})
tick(2)
msgs = take()
g2 = guis(msgs, chest)
check(g2 and dict(map(tuple, g2[-1]["inv"]["chest"])) == {"iron-plate": 15, "wood": 1},
      f"take without inv takes what there is; put adds to the chest: {g2[-1:]}")
wood = puppet.get_main_inventory().get_item_count("wood")
check(last_inv(msgs).get("copper-plate") == 3 and last_inv(msgs).get("wood", 0) == wood, f"inventory follows: {last_inv(msgs)}")
send({"t": "take", "u": 999999, "item": "iron-plate", "n": 1})
send({"t": "put", "u": chest.unit_number, "item": "laser-turret", "n": 1})
tick(2)
msgs = take()
check(guis(msgs, chest)[-1]["inv"]["chest"][0] == ["iron-plate", 15], "commands for another unit are ignored")
check(any("laser-turret" in m["text"] for m in of_type(msgs, "msg")), "putting an item you don't have explains why")

send(open_cmd(asm))
tick(2)
msgs = take()
g3 = guis(msgs, asm)
check(g3 and g3[0]["kind"] == "crafter" and "recipe" not in g3[0] and g3[0].get("pr") == 0, f"assembler screen: {g3[:1]}")
check(g3 and sorted(g3[0].get("rl", [])) == ["iron-gear-wheel", "transport-belt"],
      f"recipe list: enabled recipes in the machine's categories only: {g3[0].get('rl') if g3 else None}")
check(g3 and set(g3[0]["inv"]) == {"input", "output", "modules"}, f"assembler inventories: {g3[0]['inv'] if g3 else None}")
rg = dict(zip(g3[0].get("rl", []), g3[0].get("rg", []))) if g3 else {}
check(rg.get("transport-belt") == ["logistics", "b", "b belt", "a[transport-belt]"] and len(rg) == 2,
      f"the recipe chooser's groups ride with the list (machine_info.lua): {g3[0].get('rg') if g3 else None}")
check(g3 and "rd" not in g3[0] and "fixed" not in g3[0], "no recipe: no recipe details")
check(not guis(msgs, chest), "opening another entity closes the first screen")
send({"t": "set_recipe", "u": asm.unit_number, "recipe": "oil-processing"})
send({"t": "set_recipe", "u": asm.unit_number, "recipe": "laser-turret"})
tick(2)
msgs = take()
check(sum("Can't make" in m["text"] for m in of_type(msgs, "msg")) == 2, "recipes of another category or locked ones are refused")
send({"t": "set_recipe", "u": asm.unit_number, "recipe": "iron-gear-wheel"})
tick(2)
asm.crafting_progress = 0.25
send({"t": "put", "u": asm.unit_number, "item": "iron-plate", "n": 4})
tick(2)
msgs = take()
g4 = guis(msgs, asm)
check(g4 and g4[-1].get("recipe") == "iron-gear-wheel" and g4[-1].get("pr") == 250,
      f"set_recipe, get_recipe and crafting_progress: {g4[-1:]}")
check(g4 and g4[-1]["inv"]["input"] == [["iron-plate", 4]], f"put goes where entity.insert puts it: {g4[-1:]}")
check(last_inv(msgs).get("iron-plate") == plates - 4, f"put takes from the character: {last_inv(msgs)}")
check(all("rl" not in m for m in g4), "the recipe list isn't repeated every time")
check(g4 and g4[-1].get("rd") == {"i": [["item", "iron-plate", 2]], "o": [["item", "iron-gear-wheel", 1]], "e": 0.5},
      f"the recipe's ingredients, products and time for the recipe row and slots: {g4[-1].get('rd') if g4 else None}")
send({"t": "set_recipe", "u": asm.unit_number, "recipe": ""})
tick(2)
msgs = take()
g5 = guis(msgs, asm)
check(g5 and "recipe" not in g5[-1] and g5[-1]["inv"]["input"] == [], f"an empty recipe clears it and empties the machine: {g5[-1:]}")
check(last_inv(msgs).get("iron-plate") == plates, "items the machine gives back return to the character")

g.defines.inventory.assembling_machine_input = None
g.defines.inventory.crafter_input = 2
tick(30)
g6 = guis(take(), asm)
check(g6 and "input" in g6[-1]["inv"], "inputs are found through crafter_input when assembling_machine_input is gone")
g.defines.inventory.assembling_machine_input = 2

# F6: a module clicked on a building: within reach it goes in from the inventory; out of reach (or
# from the machine screen's slot) it is requested through an item request proxy, as Factorio does.
def texts(msgs):
    return [m["text"] for m in of_type(msgs, "msg")]


puppet.insert(lua.table_from({"name": "speed-module", "count": 3}))
asm_at ={"u": asm.unit_number, "p": eid["assembling-machine-1"], "x": fixed(asm.position.x), "y": fixed(asm.position.y)}
send({"t": "modreq", "item": "speed-module", **asm_at})
tick(2)
msgs = take()
mods = F.inventories[asm]["modules"]
check(mods.get_item_count("speed-module") == 1 and puppet.get_main_inventory().get_item_count("speed-module") == 2
      and asm.item_request_proxy is None, f"modreq within reach puts the module in: {texts(msgs)}")
g7 = guis(msgs, asm)
check(g7 and g7[-1]["slots"]["modules"][0] == ["speed-module", 1] and "mrq" not in g7[-1] and "far" not in g7[-1],
      f"the screen shows the module, with nothing requested: {g7[-1:]}")
send({"t": "modreq", "item": "speed-module", "s": 1, **asm_at})
send({"t": "modreq", "item": "speed-module", "s": 2, **asm_at})
tick(2)
msgs = take()
proxy = asm.item_request_proxy
plan = [(p.id.name, at.inventory, at.stack) for p in proxy.insert_plan.values() for at in p["items"].in_inventory.values()] if proxy else []
check(plan == [("speed-module", 25, 1)] and "That slot has a module in it" in texts(msgs),
      f"modreq on a slot: the free one gets a request proxy, the filled one is refused: {plan} {texts(msgs)}")
g8 = guis(msgs, asm)
check(g8 and g8[-1].get("mrq") == ["", "speed-module"], f"gui mrq: each module slot's requested module: {g8[-1:]}")
send({"t": "modreq", "item": "productivity-module", "u": lab.unit_number, "p": eid["lab"], "x": fixed(lab.position.x), "y": fixed(lab.position.y)})
far_at = {"u": far_asm.unit_number, "p": eid["assembling-machine-1"], "x": fixed(far_asm.position.x), "y": fixed(far_asm.position.y)}
send({"t": "modreq", "item": "speed-module", **far_at})
tick(2)
said = texts(take())
far_proxy = far_asm.item_request_proxy
check(far_proxy is not None and F.inventories[far_asm]["modules"].get_item_count("speed-module") == 0
      and any("productivity isn't allowed" in t for t in said), f"out of reach a request; a lab takes no productivity: {said}")
send({"t": "modreq", "clr": 1, **far_at})
send({"t": "modreq", "clr": 1, "s": 2, **asm_at})
tick(2)
take()
check(not far_proxy.valid and asm.item_request_proxy is None, "clr takes the requests back: the proxies go")

puppet.insert(lua.table_from({"name": "coal", "count": 5}))
fill(furnace, "input", "iron-ore", 7)
fill(furnace, "output", "iron-plate", 2)
send(open_cmd(furnace))
send({"t": "put", "u": furnace.unit_number, "item": "coal", "n": 2})
tick(2)
g7 = guis(take(), furnace)
check(g7 and g7[-1]["kind"] == "furnace" and g7[-1].get("recipe") == "iron-plate" and "rl" not in g7[-1],
      f"furnace: current recipe, no recipe list: {g7[-1:]}")
check(g7 and g7[-1]["inv"] == {"input": [["iron-ore", 7]], "output": [["iron-plate", 2]], "fuel": [["coal", 2]]},
      f"furnace inventories, coal goes to the fuel slot: {g7[-1:]}")
send({"t": "set_recipe", "u": furnace.unit_number, "recipe": "iron-gear-wheel"})
tick(2)
check(any("can't be changed" in m["text"] for m in of_type(take(), "msg")), "a furnace's recipe can't be set")

send(open_cmd(lab))
tick(2)
g8 = guis(take(), lab)
check(g8 and g8[-1]["kind"] == "lab" and set(g8[-1]["inv"]) == {"input", "modules"} and not ({"recipe", "pr", "rl"} & set(g8[-1])),
      f"lab: input and modules, no recipe: {g8[-1:]}")
check(g8 and g8[0].get("li") == ["automation-science-pack", "logistic-science-pack"], f"a lab's science packs: {g8[:1]}")

puppet.position = lua.table_from({"x": 30, "y": 0})
tick(31)
msgs = take()
check(any(m.get("closed") is True for m in guis(msgs, lab)) and any(m["text"] == "Out of reach" for m in of_type(msgs, "msg")),
      "walking out of reach closes the screen")
puppet.position = lua.table_from({"x": 0, "y": 0})
tick(31)
check(not guis(take()), "nothing is sent once closed")

for target, why in ((far_asm, "Out of reach"), (enemy_chest, "another force")):
    send(open_cmd(target))
    tick(2)
    msgs = take()
    check(not guis(msgs) and any(why in m["text"] for m in of_type(msgs, "msg")), f"open refused: {why}")
# From the remote view (rv) a building out of reach opens where radars cover it, or near the
# character, for its settings; items stay out of reach. A headless server reveals nothing itself.
send(dict(open_cmd(far_asm), rv=1))
tick(2)
check(bool(guis(take(), far_asm)), "rv: a building out of reach but near the character opens from the remote view")
covered_asm = spawn("assembling-machine-1", 300.5, 0.5, force="player")
radar = spawn("radar", 330.5, 40.5, force="player")
F["raise"]("script_raised_built", lua.table_from({"entity": radar}))  # the bridge keeps radars from build events
bare_asm = spawn("assembling-machine-1", 600.5, 0.5, force="player")
send(dict(open_cmd(covered_asm), rv=1))
tick(2)
msgs = take()
check(bool(guis(msgs, covered_asm)), f"rv: a building in a working radar's nearby chunks opens: {of_type(msgs, 'msg')}")
send({"t": "set_recipe", "u": covered_asm.unit_number, "recipe": "iron-gear-wheel"})
send({"t": "take", "u": covered_asm.unit_number, "inv": "output", "item": "iron-gear-wheel", "n": 1})
tick(31)
msgs = take()
g_rv = guis(msgs, covered_asm)
check(g_rv and g_rv[-1].get("recipe") == "iron-gear-wheel" and any("Out of reach" in m["text"] for m in of_type(msgs, "msg")),
      f"rv: its settings change from afar, items don't move, and it stays open: {g_rv[-1:]}")
send(dict(open_cmd(bare_asm), rv=1))
tick(2)
msgs = take()
check(not guis(msgs, bare_asm) and any("roboport coverage" in m["text"] for m in of_type(msgs, "msg")),
      "rv: a building no radar (or roboport) covers doesn't open")
send(open_cmd(covered_asm))
tick(2)
msgs = take()
check(not guis(msgs, covered_asm) and any("Out of reach" in m["text"] for m in of_type(msgs, "msg")),
      "without rv (the character's own view) it is out of reach, as before")
for e in (covered_asm, radar, bare_asm):
    e.destroy()
send({"t": "close"})
# 2.1.23 opens a plain belt too (its status; tools/ui_reference rules_openable).
send({"t": "open", "u": new_belt[0], "p": new_belt[1], "x": new_belt[2], "y": new_belt[3]})
tick(2)
check(bool(guis(take())), "a belt without wires opens, as in 2.1.23")
send({"t": "close"})

send(open_cmd(chest))
tick(2)
send({"t": "close"})
tick(31)
msgs = take()
check(len(guis(msgs, chest)) == 1, "close stops the screen")
send(open_cmd(chest))
tick(2)
take()
chest.destroy()
tick(31)
msgs = take()
check([m.get("closed") for m in guis(msgs)] == [True], f"a removed entity closes the screen: {guis(msgs)}")
for e in (asm, furnace, lab, far_asm, enemy_chest):
    e.destroy()
send({"t": "hello", "v": 1, "sid": "s1", "w": 1})

# --- inventory slots, moving stacks, quickbar ----------------------------------------------------
send({"t": "hello", "v": 1, "sid": "s1", "w": 1})


def main_slots():
    g.storage.f3d.slots_sig = None
    tick(31)
    msgs = of_type(take(), "slots")
    return msgs[-1]["l"]["main"] if msgs else []


def slot_of(slots, name):
    return next((i + 1 for i, v in enumerate(slots) if v != 0 and v[0] == name), None)


slots = main_slots()
inv = puppet.get_main_inventory()
check(len(slots) == 80 and slots[slot_of(slots, "iron-plate") - 1][1] == inv.get_item_count("iron-plate"),
      f"slots: the main inventory slot by slot: {slots[:4]}")
wood_at = slot_of(slots, "wood")
send({"t": "move", "from": "main", "fi": wood_at, "to": "main", "ti": 80})
tick(2)
slots = [m for m in of_type(take(), "slots")][-1]["l"]["main"]
check(slots[wood_at - 1] == 0 and slots[79][0] == "wood", f"move: a whole stack to an empty slot, sent at once: {slots[79]}")
plate_at = slot_of(slots, "iron-plate")
plates = slots[plate_at - 1][1]
send({"t": "move", "from": "main", "fi": plate_at, "to": "main", "ti": 79, "n": 3})
tick(2)
slots = of_type(take(), "slots")[-1]["l"]["main"]
check(slots[78] == ["iron-plate", 3] and slots[plate_at - 1] == ["iron-plate", plates - 3], f"move n=3 splits a stack: {slots[78]}")
send({"t": "move", "from": "main", "fi": 80, "to": "main", "ti": 79})
tick(2)
slots = of_type(take(), "slots")[-1]["l"]["main"]
check(slots[78][0] == "wood" and slots[79] == ["iron-plate", 3], "moving onto a different item swaps them")
send({"t": "sort", "inv": "main"})
tick(2)
slots = of_type(take(), "slots")[-1]["l"]["main"]
names = [v[0] for v in slots if v != 0]
check(names == sorted(names) and slots[-1] == 0, f"sort merges and sorts: {names}")

box = spawn("wooden-chest", 2.5, -1.5, force="player")
send(open_cmd(box))
tick(2)
take()
coal_at = slot_of(slots, "coal")
send({"t": "move", "from": "main", "fi": coal_at, "to": "chest", "ti": 3})  # no u: ignored
tick(2)
check(not of_type(take(), "slots"), "a move into a machine needs the open screen's u")
send({"t": "move", "from": "main", "fi": coal_at, "to": "chest", "ti": 3, "u": box.unit_number})
tick(2)
msgs = take()
gui = guis(msgs, box)
check(gui and gui[-1]["slots"]["chest"][2] == ["coal", 3] and gui[-1]["slots"]["chest"][0] == 0
      and of_type(msgs, "slots")[-1]["l"]["main"][coal_at - 1] == 0,
      f"move into an open chest's slot; gui carries its slots: {gui[-1:]}")
send({"t": "move", "from": "chest", "fi": 3, "to": "main", "ti": 80, "u": box.unit_number})
tick(2)
check(of_type(take(), "slots")[-1]["l"]["main"][79] == ["coal", 3], "and back out of it")

# xfer: Factorio's Shift / Ctrl clicks (stack_transfers' four actions, emulated without a player)
def chest_slots():
    g.storage.f3d.screen.due = 0
    tick(2)
    gui = guis(take(), box)
    return gui[-1]["slots"]["chest"] if gui else []


box_inv = box.get_inventory(1)
inv.insert(lua.table_from({"name": "iron-plate", "count": 40}))
slots = main_slots()
plate_at = slot_of(slots, "iron-plate")
plate_n = slots[plate_at - 1][1]
plates_before = inv.get_item_count("iron-plate")
send({"t": "xfer", "from": "main", "fi": plate_at, "k": "half", "u": box.unit_number})
tick(2)
take()
check(box_inv.get_item_count("iron-plate") == plate_n // 2 and inv.get_item_count("iron-plate") == plates_before - plate_n // 2,
      f"xfer half: the smaller half of the clicked stack into the open chest ({plate_n} -> {box_inv.get_item_count('iron-plate')})")
send({"t": "xfer", "from": "main", "fi": slot_of(main_slots(), "iron-plate"), "k": "all", "u": box.unit_number})
tick(2)
take()
check(inv.get_item_count("iron-plate") == 0 and box_inv.get_item_count("iron-plate") == plates_before,
      "xfer all: every stack of the item into the chest")
send({"t": "xfer", "from": "chest", "fi": 1, "k": "stack", "u": box.unit_number})
tick(2)
take()
check(inv.get_item_count("iron-plate") > 0 and box_inv.get_item_count("iron-plate") < plates_before, "xfer stack: a chest stack into the character")
send({"t": "xfer", "from": "chest", "fi": 1, "k": "all"})
tick(2)
check(not of_type(take(), "slots"), "xfer from a screen's inventory needs its u")
empty_at = next(i + 1 for i, v in enumerate(main_slots()) if v == 0)
send({"t": "xfer", "from": "chest", "fi": len(box_inv), "k": "all", "u": box.unit_number})
tick(2)
take()
check(box_inv.is_empty(), "xfer all from an empty slot moves everything")
guns = puppet.get_inventory(g.defines.inventory.character_guns)
inv.insert(lua.table_from({"name": "pistol", "count": 1}))
had_guns = guns.get_item_count("pistol")
send({"t": "close"})
tick(2)
take()
send({"t": "xfer", "from": "main", "fi": slot_of(main_slots(), "pistol"), "k": "stack"})
tick(2)
take()
check(guns.get_item_count("pistol") == had_guns + 1 or guns.find_empty_stack() is None,
      f"xfer with nothing open: a gun goes to the gun slots ({had_guns} -> {guns.get_item_count('pistol')})")
send({"t": "xfer", "from": "main", "fi": slot_of(main_slots(), "coal") or 1, "k": "stack"})
tick(2)
check(any("Nowhere" in m["text"] for m in of_type(take(), "msg")), "xfer with nothing open: other items stay")
send(open_cmd(box))
tick(2)
take()
send({"t": "move", "from": "main", "fi": 80, "to": "chest", "ti": 1, "u": box.unit_number})
send({"t": "close"})
tick(2)
take()
send({"t": "move", "from": "chest", "fi": 1, "to": "main", "ti": 80, "u": box.unit_number})
tick(2)
check(not of_type(take(), "slots"), "a closed screen's inventory can't be used")
box.destroy()

send({"t": "qb_set", "i": 1, "item": "transport-belt"})
send({"t": "qb_set", "i": 2, "item": "no-such-item"})
send({"t": "qb_sel", "i": 1})
send({"t": "qb_page", "p": 2})
tick(2)
qb = of_type(take(), "qb")
check(len(qb) == 3 and qb[-1]["l"][0] == "transport-belt" and qb[-1]["l"][1] == "" and qb[-1]["held"] == "transport-belt"
      and qb[-1]["sel"] == 1 and qb[-1]["p"] == 2, f"quickbar: set, select (held item), page; unknown items refused: {qb[-1:]}")

# --- recipe details, craftable counts, the crafting queue -------------------------------------------
g.storage.f3d.rdet_sig = None
g.storage.f3d.craftable_sig = None
tick(31)
msgs = take()
details = {r[0]: r for m in of_type(msgs, "rdet") for r in m["l"]}
check(set(details) == {"iron-gear-wheel", "transport-belt"}, f"rdet: enabled hand-craftable recipes only: {sorted(details)}")
belt_r = details.get("transport-belt", [None] * 10)
check(belt_r[1] == 0.5 and belt_r[2] == ["crafting"] and belt_r[3:8] == ["logistics", "b", "belt", "b", "a[transport-belt]"]
      and belt_r[8] == [["item", "iron-gear-wheel", 1], ["item", "iron-plate", 1]] and belt_r[9] == [["item", "transport-belt", 2]],
      f"rdet: time, categories, group, subgroup, order, ingredients, products: {belt_r}")
craftable = dict(map(tuple, of_type(msgs, "craftable")[-1]["l"])) if of_type(msgs, "craftable") else {}
check(craftable.get("iron-gear-wheel") == inv.get_item_count("iron-plate") // 2,
      f"craftable: how many the character can make now: {craftable}")
# The counts are worked out again only when the inventory changes (230 recipes cost ~22 ms a time
# on the owner's save).
# A stale signature shows whether they were worked out: unchanged contents send nothing.
g.storage.f3d.craftable_sig = "stale"
tick(60)
quiet = of_type(take(), "craftable")
puppet.get_main_inventory().insert(lua.table_from({"name": "iron-plate", "count": 10}))
tick(30)
again = of_type(take(), "craftable")
check(not quiet and again
      and dict(map(tuple, again[-1]["l"])).get("iron-gear-wheel") == craftable.get("iron-gear-wheel", 0) + 5,
      f"craftable: not worked out again while the inventory stays the same, then again when it changes: {quiet}, {again[-1:]}")
puppet.get_main_inventory().remove(lua.table_from({"name": "iron-plate", "count": 10}))
tick(30)
take()
puppet.crafting_queue_progress = 0.25
tick(10)
cq = of_type(take(), "cq")
check(cq and cq[-1]["l"] == [[1, "iron-gear-wheel", 2, 0]] and cq[-1]["pr"] == 250, f"cq: the crafting queue with progress: {cq[-1:]}")
send({"t": "cancel_craft", "i": 1, "n": 1})
tick(2)
cq = of_type(take(), "cq")
check(cq and cq[-1]["l"] == [[1, "iron-gear-wheel", 1, 0]], f"cancel_craft takes crafts off the queue: {cq[-1:]}")
send({"t": "cancel_craft", "i": 1, "n": 5})
tick(30)
cq = of_type(take(), "cq")
check([m["l"] for m in cq] == [[]], f"an empty queue is sent once: {cq}")

# Finished hand-crafts go into the production statistics (2.1.23 leaves a player-less character's
# out, and with them "craft an item" research triggers such as the lab for red science, issue #7).
lua.eval("function() for i = #F.flowed, 1, -1 do F.flowed[i] = nil end end")()
send({"t": "craft", "recipe": "transport-belt", "n": 1})
send({"t": "craft", "recipe": "iron-gear-wheel", "n": 3})
tick(2)
# The game finishing crafts, as the fake shows it: entries leave the front (cancel_crafting called
# here, not through the bridge's command, so the bridge sees only a shorter queue).
finish = lua.eval("""function(gone, left)
  local c = storage.f3d.puppet
  for _ = 1, gone do local f = c.crafting_queue[1]; c.cancel_crafting({ index = f.index, count = f.count }) end
  if left then local f = c.crafting_queue[1]; c.cancel_crafting({ index = f.index, count = f.count - left }) end
end""")
flowed = lambda: [tuple(r.values()) for r in F.flowed.values()]
check(flowed() == [], f"nothing counted while the queue only grows by commands: {flowed()}")
finish(1, 2)
tick(1)
check(flowed() == [("item", "transport-belt", 2), ("item", "iron-gear-wheel", -1), ("item", "iron-plate", -1),
                   ("item", "iron-gear-wheel", 1), ("item", "iron-plate", -2)],
      f"a finished belt and one of three gears counted, products in and ingredients out: {flowed()}")
finish(1, None)
tick(1)
check(flowed()[-2:] == [("item", "iron-gear-wheel", 2), ("item", "iron-plate", -4)] and len(flowed()) == 7,
      f"the last two gears counted when the queue empties: {flowed()}")
tick(5)
check(len(flowed()) == 7, "nothing more once the queue is empty")

# --- research ---------------------------------------------------------------------------------------
lua.eval("function() storage.f3d.techs_dirty = true end")()
tick(2)
techs = {r[0]: r for m in of_type(take(), "techs") for r in m["l"]}
check(set(techs) == {"automation", "logistics", "steel-processing"}, f"techs: every shown technology: {sorted(techs)}")
check(techs.get("logistics", [0] * 8)[2:8] == [["automation"], [["automation-science-pack", 1]], 10, 10, 0, ""]
      and techs["automation"][6] == 1 and techs["steel-processing"][6] == 2,
      f"techs: prerequisites, cost, time, state (locked/available/researched): {techs.get('logistics')}")
check(len(techs.get("automation", [])) == 15 and techs["automation"][8] == [["unlock-recipe", "iron-gear-wheel", 0]]
      and techs["automation"][9:] == [1, 1, [], 0, "", 1] and techs["logistics"][14] == 0,
      f"techs: effects, level, max level, trigger detail, saved progress, formula, essential: {techs.get('automation')}")
send({"t": "research", "name": "automation"})
send({"t": "research", "name": "logistics"})
send({"t": "research", "name": "secret"})
tick(2)
msgs = take()
rs = of_type(msgs, "rs")
check(rs and rs[-1]["cur"] == "automation" and rs[-1]["q"] == ["logistics"], f"research starts one and queues the next: {rs[-1:]}")
research_lab = spawn("lab", 6.5, 4.5, force="player")
tick(60)
rs = of_type(take(), "rs")
check(rs and [research_lab.unit_number, "missing_science_packs"] in rs[-1]["labs"], f"rs: labs near the camera with their status: {rs[-1:]}")
research_lab.destroy()
check(any(m["text"] == "Can't research secret" for m in of_type(msgs, "msg")), "hidden technologies can't be researched")
g.game.forces.player.research_progress = 0.4
send({"t": "research_cancel", "name": "logistics"})
tick(2)
rs = of_type(take(), "rs")
check(rs and rs[-1]["q"] == [] and rs[-1]["pr"] == 400, f"research_cancel takes it off the queue: {rs[-1:]}")
send({"t": "research_cancel", "name": "automation"})
tick(2)
rs = of_type(take(), "rs")
check(rs and rs[-1]["cur"] == "", "and stops the current research")
g.game.forces.player.technologies.automation.researched = True
F["raise"]("on_research_finished", lua.table_from({"research": g.game.forces.player.technologies.automation}))
tick(2)
msgs = take()
techs = {r[0]: r[6] for m in of_type(msgs, "techs") for r in m["l"]}
check(techs.get("automation") == 2 and techs.get("logistics") == 1, f"finished research resends the tree: {techs}")
done = [m for m in of_type(msgs, "msg") if m.get("tech")]
check(done and done[0]["tech"] == "automation" and done[0]["unlocks"] == ["iron-gear-wheel"] and "automation" in done[0]["text"],
      f"research completed: a msg naming the technology and the recipes it unlocks: {done}")
g.game.forces.player.technologies.automation.researched = False

# --- fast-replace, rails, rolling stock, quality ----------------------------------------------------
send({"t": "hello", "v": 1, "sid": "s1", "w": 1})
take()
inv = puppet.get_main_inventory()
belts = inv.get_item_count("transport-belt")
spot = {"x": new_belt[2], "y": new_belt[3]}  # the belt built and turned south above
send({"t": "build", "item": "transport-belt", "d": 4, **spot})
tick(2)
msgs = take()
upd = of_type(msgs, "upd")
check(upd and upd[-1]["e"][4] == 4 and not of_type(msgs, "add") and inv.get_item_count("transport-belt") == belts,
      f"building a belt over the same belt turns it, for free: {upd[-1:]}")
send({"t": "build", "item": "transport-belt", "d": 4, **spot})
tick(2)
msgs = take()
check(not (of_type(msgs, "upd") or of_type(msgs, "add") or of_type(msgs, "msg")), "and over itself facing the same way does nothing")
puppet.insert(lua.table_from({"name": "fast-transport-belt", "count": 2}))
send({"t": "build", "item": "fast-transport-belt", "d": 4, **spot})
tick(2)
msgs = take()
dels, adds = of_type(msgs, "del"), of_type(msgs, "add")
check(dels and dels[0]["u"] == new_belt[0] and adds and adds[0]["e"][1] == eid["fast-transport-belt"] and adds[0]["e"][2:5] == [spot["x"], spot["y"], 4],
      f"a faster belt fast-replaces it: del then add: {dels[:1]} {adds[:1]}")
check(inv.get_item_count("fast-transport-belt") == 1 and inv.get_item_count("transport-belt") == belts + 1,
      "the fast belt is used and the old belt comes back")

puppet.insert(lua.table_from({"name": "rail", "count": 3}))
send({"t": "build", "item": "rail", "x": int(4.2 * 256), "y": int(3.7 * 256), "d": 0})
tick(2)
adds = of_type(take(), "add")
check(adds and adds[0]["e"][1] == eid["straight-rail"] and adds[0]["e"][2:4] == [5 * 256, 3 * 256],
      f"rail (a 2.x rail planner) builds a straight rail on the two-tile grid: {adds[:1]}")
puppet.insert(lua.table_from({"name": "locomotive", "count": 2}))
send({"t": "build", "item": "locomotive", "x": int(5.4 * 256), "y": int(3.8 * 256), "d": 12})
send({"t": "build", "item": "locomotive", "x": int(-6 * 256), "y": int(-6 * 256), "d": 0})
tick(2)
msgs = take()
locos = [e for e in F.surface.entities.values() if e.name == "locomotive"]
check(len(locos) == 1 and (locos[0].position.x, locos[0].position.y, locos[0].direction) == (5, 3, 0),
      "rolling stock goes onto the nearest rail, along it")
check(any(m["text"] == "Rolling stock goes on rails" for m in of_type(msgs, "msg")), "and not where there is no rail")

inv.remove(lua.table_from({"name": "transport-belt", "count": 999}))
puppet.insert(lua.table_from({"name": "transport-belt", "count": 2, "quality": "rare"}))
puppet.insert(lua.table_from({"name": "transport-belt", "count": 1}))
send({"t": "build", "item": "transport-belt", "x": int(0.5 * 256), "y": int(7.5 * 256), "d": 0, "q": "rare"})
send({"t": "build", "item": "transport-belt", "x": int(1.5 * 256), "y": int(7.5 * 256), "d": 0})
send({"t": "build", "item": "transport-belt", "x": int(2.5 * 256), "y": int(7.5 * 256), "d": 0})
tick(2)
adds = [m["e"] for m in of_type(take(), "add")]
check([a[5].get("q") for a in adds] == ["rare", None, "rare"],
      f"q picks the stack's quality; without it normal comes first, then what there is: {[a[5] for a in adds]}")
contents = {(it["name"], it["quality"]): it["count"] for it in inv.get_contents().values() if it["name"] == "transport-belt"}
check(not contents, f"each build used its own stack: {contents}")
for e in list(F.surface.entities.values()):
    if e.name in ("locomotive", "straight-rail") or (e.name == "transport-belt" and e.position.y == 7.5):
        e.destroy()

# --- tiles, capsules, the rail planner ----------------------------------------------------------
send({"t": "hello", "v": 1, "sid": "s1", "w": 1})
take()
puppet.insert(lua.table_from({"name": "concrete", "count": 5}))
puppet.insert(lua.table_from({"name": "stone-brick", "count": 1}))
F.surface.set_tile(4, 3, "stone-path")
send({"t": "tile", "item": "concrete", "x": fixed(4.6), "y": fixed(3.6), "n": 2})
tick(2)
msgs = take()
flat = [v for m in of_type(msgs, "tiles") for v in m["l"]]
laid = {(flat[i], flat[i + 1]): flat[i + 2] for i in range(0, len(flat), 3)}
check(laid == {(x, y): tid["concrete"] for x in (4, 5) for y in (3, 4)} and inv.get_item_count("concrete") == 1
      and inv.get_item_count("stone-brick") == 2,
      f"tile: a 2x2 brush on the nearest corner, one concrete each, the stone path under it comes back: {laid}")
send({"t": "tile", "item": "concrete", "x": fixed(-45.5), "y": fixed(0.5), "n": 1})
send({"t": "tile", "item": "concrete", "x": fixed(4.5), "y": fixed(3.5), "n": 1})
tick(2)
check(not of_type(take(), "tiles") and inv.get_item_count("concrete") == 1, "not on water (its condition), nor on itself")
send({"t": "tile", "item": "concrete", "x": fixed(8.5), "y": fixed(12.5), "n": 3, "ghost": 1})
tick(2)
ghosts = [m["e"] for m in of_type(take(), "add") if m["e"][1] == eid["tile-ghost"]]
check(len(ghosts) == 9 and all(g[5].get("tg") == tid["concrete"] for g in ghosts) and inv.get_item_count("concrete") == 1,
      f"ghost: tile ghosts for the robots (extra.tg), no items: {ghosts[:1]}")
send({"t": "tile_mine", "x": fixed(4.5), "y": fixed(3.5), "n": 1})
send({"t": "tile_mine", "x": fixed(8.5), "y": fixed(12.5), "n": 3})
tick(2)
msgs = take()
flat = [v for m in of_type(msgs, "tiles") for v in m["l"]]
check(flat == [4, 3, tid["grass-1"]] and inv.get_item_count("concrete") == 2 and len(of_type(msgs, "del")) == 9,
      f"tile_mine: the tile back into the inventory (LuaControl.mine_tile), tile ghosts removed: {flat}")
for e in list(F.surface.entities.values()):
    if e.type == "tile-ghost":
        e.destroy()

puppet.insert(lua.table_from({"name": "grenade", "count": 2}))
send({"t": "throw", "item": "grenade", "x": fixed(puppet.position.x + 5), "y": fixed(puppet.position.y)})
send({"t": "throw", "item": "grenade", "x": fixed(puppet.position.x + 30), "y": fixed(puppet.position.y)})
tick(2)
msgs = take()
check(len(F.capsules) == 1 and F.capsules[1].name == "grenade" and inv.get_item_count("grenade") == 1
      and any(m["text"] == "Out of range" for m in of_type(msgs, "msg")),
      "throw: LuaItemStack.use_capsule at the target in range (one used), not out of range")
puppet.insert(lua.table_from({"name": "cliff-explosives", "count": 1}))
send({"t": "throw", "item": "cliff-explosives", "x": fixed(puppet.position.x + 3), "y": fixed(puppet.position.y)})
tick(2)
check(len(F.capsules) == 1 and any(m["text"] == "No cliff there" for m in of_type(take(), "msg")),
      "cliff explosives need a cliff in their radius")

inv.remove(lua.table_from({"name": "rail", "count": 999}))
puppet.insert(lua.table_from({"name": "rail", "count": 3}))
px, py = puppet.position.x, puppet.position.y
rx, ry = math.floor(px / 2) * 2 + 1, math.floor(py / 2) * 2 + 1
path = [["straight-rail", fixed(rx), fixed(ry + 6), 0], ["curved-rail-a", fixed(rx), fixed(ry + 9), 8],
        ["straight-rail", fixed(rx), fixed(ry + 24), 0]]
send({"t": "rails", "item": "rail", "l": path})
tick(2)
msgs = take()
adds = [m["e"] for m in of_type(msgs, "add")]
got = sorted((a[1], a[5].get("gh") if len(a) > 5 else None) for a in adds)
check(got == sorted([(eid["straight-rail"], None), (eid["entity-ghost"], eid["curved-rail-a"]), (eid["entity-ghost"], eid["straight-rail"])])
      and inv.get_item_count("rail") == 2 and any("2 rail pieces placed as ghosts" in m["text"] for m in of_type(msgs, "msg")),
      f"rails: the planner's pieces in order, ghosts where rails run out (a curve costs 3) or out of reach: {got}")
send({"t": "rails", "item": "rail", "l": [["assembling-machine-1", fixed(rx), fixed(ry), 0]]})
tick(2)
check(any(m["text"] == "Can't build that with rail" for m in of_type(take(), "msg")), "and nothing the planner can't build")
for e in list(F.surface.entities.values()):
    if e.type in ("straight-rail", "curved-rail-a") or (e.type == "entity-ghost" and e.ghost_name in ("straight-rail", "curved-rail-a")):
        e.destroy()

# --- fluids, wires, power ------------------------------------------------------------------------
send({"t": "hello", "v": 1, "sid": "s1", "w": 1})
take()
pole_a = spawn("small-electric-pole", 14.5, 5.5, force="player")
pole_b = spawn("small-electric-pole", 18.5, 5.5, force="player")
F.connect(pole_a, pole_b, g.defines.wire_type.copper)
F.connect(pole_a, pole_b, g.defines.wire_type.red)
pipe = spawn("pipe", 12.5, 6.5, force="player")
F.set_fluid(pipe, 1, lua.table_from({"name": "water", "amount": 80, "temperature": 15}))
send({"t": "resync", "full": 0, "c": [[0, 0]]})
tick(60)
msgs = take()
recs = {r[0]: r for m in of_type(msgs, "ents") for r in m["e"]}
check(recs.get(pole_a.unit_number, [None] * 6)[5:] == [{"w": [pole_b.unit_number], "r": [pole_b.unit_number]}],
      f"pole records carry their copper and red wires by unit number: {recs.get(pole_a.unit_number)}")
fl = [m["l"] for m in of_type(msgs, "fl")]
check(fl and [pipe.unit_number, 1, fid["water"], 80, 100, 15] == fl[-1][fl[-1].index(pipe.unit_number):fl[-1].index(pipe.unit_number) + 6],
      f"fl: fluid in a pipe near the camera (box, fluid, amount, capacity, temperature): {fl[-1:]}")
power_asm = spawn("assembling-machine-1", 16.5, 9.5, force="player")
power_asm.status = g.defines.entity_status.no_power
tick(60)
pw = [m["l"] for m in of_type(take(), "pw")]
check(pw and pw[-1][pw[-1].index(power_asm.unit_number) + 1] == 0, f"pw: a machine without power: {pw[-1:]}")
power_asm.status = g.defines.entity_status.low_power
tick(60)
pw = [m["l"] for m in of_type(take(), "pw")]
check(pw and pw[-1][pw[-1].index(power_asm.unit_number) + 1] == 1, "pw: and with low power")
power_asm.status = g.defines.entity_status.working
F.set_fluid(power_asm, 1, lua.table_from({"name": "water", "amount": 50}), 200)
power_asm.energy = 500
puppet.position = lua.table_from({"x": 14, "y": 8})
send(open_cmd(power_asm))
tick(60)
msgs = take()
pw = [m["l"] for m in of_type(msgs, "pw")]
check(pw and power_asm.unit_number not in pw[-1][::2], "a powered machine drops out of pw")
gui = guis(msgs, power_asm)
check(gui and gui[-1].get("fb") == [["water", 50, 200, 15]] and gui[-1].get("status") == "working" and gui[-1].get("pw") == 500,
      f"gui: fluid boxes, status and how full the power buffer is: {gui[-1:]}")
send({"t": "close"})
puppet.position = lua.table_from({"x": 0, "y": 0})
for e in (pole_a, pole_b, pipe, power_asm):
    e.destroy()
tick(2)
take()

# --- blueprints, ghosts, planners -----------------------------------------------------------------
send({"t": "hello", "v": 1, "sid": "s1", "w": 1})
take()
F.blueprint = lua.table_from([{"name": "transport-belt", "x": 0, "y": 0}, {"name": "wooden-chest", "x": 1, "y": 0}], recursive=True)
for name in ("blueprint", "deconstruction-planner", "upgrade-planner"):
    puppet.insert(lua.table_from({"name": name, "count": 1}))
inv = puppet.get_main_inventory()
size = lua.eval("function(t) return #t end")(inv)  # Python's len() skips the __len metamethod
slot = {name: next(i for i in range(1, size + 1) if inv[i].valid_for_read and inv[i].name == name)
        for name in ("blueprint", "deconstruction-planner", "upgrade-planner", "wood")}
send({"t": "blueprint", "i": slot["blueprint"], "x": int(1.5 * 256), "y": int(8.5 * 256), "d": 0})
send({"t": "blueprint", "i": slot["wood"], "x": 0, "y": 0, "d": 0})
tick(2)
msgs = take()
ghosts = [m["e"] for m in of_type(msgs, "add") if m["e"][1] == eid["entity-ghost"]]
check(sorted((g[2], g[3], g[5].get("gh")) for g in ghosts) == [(384, 2176, eid["transport-belt"]), (640, 2176, eid["wooden-chest"])],
      f"blueprint places ghosts, sent as static entities with the entity they stand for: {ghosts}")
check(any(m["text"] == "That isn't a blueprint" for m in of_type(msgs, "msg")), "a slot without a blueprint is refused")
check(F.last_build_mode == 1, "a blueprint without bm is placed forced, as older clients expect")
for bm, mode in ((0, 0), (1, 1), (2, 2)):
    send({"t": "blueprint", "i": slot["blueprint"], "x": int(1.5 * 256), "y": int(30.5 * 256), "d": 0, "bm": bm})
    tick(1)
    check(F.last_build_mode == mode, f"bm {bm}: build_mode {mode} (click normal, Shift forced, Ctrl+Shift super-forced)")
for e in list(F.surface.entities.values()):
    if e.position.y == 30.5:
        e.destroy()
take()
belt_ghost = next(g for g in ghosts if g[5]["gh"] == eid["transport-belt"])
puppet.insert(lua.table_from({"name": "transport-belt", "count": 1}))
belts = inv.get_item_count("transport-belt")
send({"t": "build", "item": "transport-belt", "x": belt_ghost[2], "y": belt_ghost[3], "d": 0})
tick(2)
msgs = take()
check(any(d["u"] == belt_ghost[0] for d in of_type(msgs, "del")) and any(a["e"][1] == eid["transport-belt"] and a["e"][2:4] == belt_ghost[2:4] for a in of_type(msgs, "add"))
      and inv.get_item_count("transport-belt") == belts - 1, "building over a ghost revives it: the ghost's del, the belt's add")
belt_real = next(e for e in F.surface.entities.values() if e.name == "transport-belt" and e.position.y == 8.5)
area = {"x1": 0, "y1": 8 * 256, "x2": 3 * 256, "y2": 9 * 256}
chest_ghost = next(g for g in ghosts if g[5]["gh"] == eid["wooden-chest"])
send({"t": "decon", "i": 0, **area})
tick(2)
msgs = take()
upd = [m["e"] for m in of_type(msgs, "upd") if m["e"][0] == belt_real.unit_number]
check(upd and upd[-1][5].get("d") == 1, f"decon without a planner marks the area; the record says so: {upd[-1:]}")
# Factorio deletes the ghosts in the area with no event, so the client must be told.
check(any(d["u"] == chest_ghost[0] for d in of_type(msgs, "del")), f"decon (Alt+D) removes the ghosts in the area and sends their del: {of_type(msgs, 'del')}")
send({"t": "decon", "i": slot["deconstruction-planner"], "cancel": 1, **area})
tick(2)
upd = [m["e"] for m in of_type(take(), "upd") if m["e"][0] == belt_real.unit_number]
check(upd and "d" not in upd[-1][5], "a deconstruction planner's cancel unmarks it")
F.upgrades = lua.table_from({"transport-belt": "fast-transport-belt"})
send({"t": "upgrade", "i": slot["upgrade-planner"], **area})
tick(2)
upd = [m["e"] for m in of_type(take(), "upd") if m["e"][0] == belt_real.unit_number]
check(upd and upd[-1][5].get("up") == eid["fast-transport-belt"], f"upgrade marks it with its target: {upd[-1:]}")
send({"t": "upgrade", "i": slot["upgrade-planner"], "cancel": 1, **area})
send({"t": "upgrade", "i": slot["wood"], **area})
tick(2)
msgs = take()
check(any("up" not in m["e"][5] for m in of_type(msgs, "upd") if m["e"][0] == belt_real.unit_number), "cancelling the upgrade unmarks it")
check(any(m["text"] == "That isn't an upgrade planner" for m in of_type(msgs, "msg")), "a slot without an upgrade planner is refused")
# Downgrade (right-drag): the planner's mappings the other way round.
up = inv[slot["upgrade-planner"]]
up.set_mapper(1, "from", lua.table_from({"type": "entity", "name": "transport-belt"}))
up.set_mapper(1, "to", lua.table_from({"type": "entity", "name": "fast-transport-belt"}))
fast = spawn("fast-transport-belt", 0.5, 8.5)
take()
send({"t": "upgrade", "i": slot["upgrade-planner"], "down": 1, **area})
tick(2)
msgs = take()
upd = [m["e"] for m in of_type(msgs, "upd") if m["e"][0] == fast.unit_number]
check(upd and upd[-1][5].get("up") == eid["transport-belt"], f"down: 1 marks by the reversed mappings (fast belt -> belt): {upd[-1:]}")
check(not any(m["e"][0] == belt_real.unit_number and m["e"][5].get("up") for m in of_type(msgs, "upd")), "and not the plain belt")
check(up.mapper_count == 1 and up.get_mapper(1, "from").name == "transport-belt", "the planner itself keeps its mappings")
send({"t": "upgrade", "i": slot["upgrade-planner"], "cancel": 1, **area})
tick(2)
take()
# bp_del: the planner window's delete button destroys the planner; anything else stays.
puppet.insert(lua.table_from({"name": "blueprint-book", "count": 1}))
spare = next(i for i in range(1, size + 1) if inv[i].valid_for_read and inv[i].name == "blueprint-book")
# The icons a book was given are drawn over it in the inventory, so they go with `slots`.
inv[spare].preview_icons = lua.eval('{{signal = {type = "virtual", name = "signal-A"}, index = 2}, {signal = {name = "iron-plate"}, index = 1}}')
tick(31)
ic = [m.get("ic") for m in of_type(take(), "slots")]
check(ic and [spare, [["item", "iron-plate"], ["virtual", "signal-A"]]] in (ic[-1] or []),
      f"slots carries a book's icons in their order (ic): {ic[-1:]}")
send({"t": "bp_del", "i": spare})
send({"t": "bp_del", "i": slot["wood"]})
tick(1)
check(not inv[spare].valid_for_read and inv[slot["wood"]].valid_for_read, "bp_del destroys a planner, not other items")
for e in list(F.surface.entities.values()):
    if e.position.y == 8.5 and e.position.x < 3:
        e.destroy()

# --- exchange strings, the library, undo, super-forced build, qualities -------------------------
take()
g.package.loaded["scripts.planners"].send_initial()  # sent at every handshake
tick(1)
quals = of_type(take(), "quals")
check(quals and [q[0] for q in quals[-1]["l"]] == ["normal", "uncommon", "rare", "epic", "legendary"]
      and quals[-1]["l"][2][2] == 1 and quals[-1]["l"][3][2] == 0,
      f"quals lists the qualities in order, unlocked ones marked, without quality-unknown: {quals[-1:]}")
inv[slot["blueprint"]].import_stack("0FAKE|blueprint|Belt and chest|transport-belt,wooden-chest")
send({"t": "bp_get", "q": 7, "i": slot["blueprint"]})
tick(2)
bp = of_type(take(), "bp")
check(len(bp) == 1 and bp[0]["q"] == 7 and bp[0]["s"].startswith("0FAKE|blueprint|Belt and chest") and bp[0]["item"] == "blueprint",
      f"bp_get exports the blueprint as its string: {bp}")
send({"t": "bp_get", "q": 8, "i": slot["wood"]})
tick(2)
bp = of_type(take(), "bp")
check(bp and bp[0]["s"] == "" and bp[0].get("err"), f"bp_get on something else says so: {bp}")
long_label = "x" * 40000
inv[slot["blueprint"]].import_stack("0FAKE|blueprint|" + long_label + "|transport-belt")
send({"t": "bp_get", "q": 9, "i": slot["blueprint"]})
tick(2)
bp = of_type(take(), "bp")
check(len(bp) == 3 and [m["part"] for m in bp] == [1, 2, 3] and all(m["parts"] == 3 for m in bp)
      and "".join(m["s"] for m in bp) == "0FAKE|blueprint|" + long_label + "|transport-belt",
      "a long string comes in parts that join up again")
inv[slot["blueprint"]].import_stack("0FAKE|blueprint|Belt and chest|transport-belt,wooden-chest")
# bp_set: a new one in the inventory, in parts; the cursor's library stack (-1)
data = "0FAKE|blueprint|From the library|transport-belt,wooden-chest"
send({"t": "bp_set", "q": 3, "i": 0, "id": 41, "part": 2, "parts": 2, "d": data[20:]})
send({"t": "bp_set", "q": 3, "i": 0, "id": 41, "part": 1, "parts": 2, "d": data[:20]})
tick(2)
ok = of_type(take(), "bp_ok")
check(ok and ok[-1]["q"] == 3 and ok[-1]["item"] == "blueprint" and inv[ok[-1]["i"]].valid_for_read
      and inv[ok[-1]["i"]].export_stack().startswith("0FAKE|blueprint|From the library"),
      f"bp_set in parts makes a new blueprint in the inventory and says which slot: {ok}")
new_slot = ok[-1]["i"] if ok else 0
send({"t": "bp_set", "q": 4, "i": slot["wood"], "s": data})
send({"t": "bp_set", "q": 5, "i": 0, "s": "not a blueprint string"})
tick(2)
msgs = take()
check(not of_type(msgs, "bp_ok") and any(m["text"] == "That slot holds something else" for m in of_type(msgs, "msg"))
      and any("can import" in m["text"] for m in of_type(msgs, "msg")), "bp_set refuses another item's slot and a bad string")
send({"t": "bp_set", "q": 6, "i": -1, "s": data})
tick(2)
ok = of_type(take(), "bp_ok")
check(ok and ok[-1]["i"] == -1 and g.storage.f3d.lib_cursor[1].valid_for_read, f"bp_set -1 fills the library stack in the cursor: {ok}")
send({"t": "blueprint", "i": -1, "x": fixed(2.5), "y": fixed(26.5), "d": 0})
tick(2)
msgs = take()
placed = [m["e"] for m in of_type(msgs, "add") if m["e"][1] == eid["entity-ghost"]]
hist = of_type(msgs, "hist")
check(len(placed) == 2 and hist and hist[-1]["what"] == "blueprint", f"the cursor's library blueprint places ghosts, remembered for undo: {hist}")
send({"t": "undo", "h": hist[-1]["h"] if hist else 0})
tick(2)
dels = [m["u"] for m in of_type(take(), "del")]
check(sorted(dels) == sorted(p[0] for p in placed), f"undo takes the placed ghosts away: {dels}")
send({"t": "redo", "h": hist[-1]["h"] if hist else 0})
tick(2)
again = [m["e"] for m in of_type(take(), "add") if m["e"][1] == eid["entity-ghost"]]
check(len(again) == 2, "redo places them again")
# m: 1, a held blueprint flipped: a mirrored copy is placed; the blueprint itself stays as it was.
lib = g.storage.f3d.lib_cursor[1]
lib.set_blueprint_entities(lua.table_from([
    {"entity_number": 1, "name": "transport-belt", "position": {"x": -1.5, "y": 0.5}, "direction": 4},
    {"entity_number": 2, "name": "assembling-machine-1", "position": {"x": 2.5, "y": 0.5}},
], recursive=True))
send({"t": "blueprint", "i": -1, "x": fixed(40.5), "y": fixed(40.5), "d": 0, "m": 1})
tick(2)
take()
built = {b.name: b for b in F.last_built.values()}
belt_b, asm_b2 = built.get("transport-belt"), built.get("assembling-machine-1")
check(belt_b and belt_b.position.x == 1.5 and belt_b.direction == 12 and asm_b2 and asm_b2.position.x == -2.5 and asm_b2.mirror is True,
      "m: 1 places the blueprint mirrored: x negated, east becomes west, the assembler's mirror flag set")
check(lib.get_blueprint_entities()[1].position.x == -1.5, "and the held blueprint itself is unchanged")
for e in list(F.surface.entities.values()):
    if e.position.y == 40.5 or e.position.y == 41.5 or e.position.y == 39.5:
        e.destroy()
take()
send({"t": "undo", "h": 99999})
tick(2)
check(any(m["text"] == "That can no longer be undone" for m in of_type(take(), "msg")), "an unknown undo entry is refused")
# Deconstruction marks: undo removes exactly the marks that action added.
chest_a = spawn("wooden-chest", 40.5, 40.5, force="player")
chest_b = spawn("wooden-chest", 41.5, 40.5, force="player")
chest_b.order_deconstruction("player")
send({"t": "decon", "i": 0, "x1": fixed(40), "y1": fixed(40), "x2": fixed(42), "y2": fixed(41)})
tick(2)
hist = of_type(take(), "hist")
check(hist and hist[-1]["what"] == "deconstruction" and F.decon_marks[chest_a] is True, f"decon is remembered: {hist}")
send({"t": "undo", "h": hist[-1]["h"] if hist else 0})
tick(2)
check(F.decon_marks[chest_a] is None and F.decon_marks[chest_b] is True, "undo removes its own marks and keeps the older one")
send({"t": "redo", "h": hist[-1]["h"] if hist else 0})
tick(2)
check(F.decon_marks[chest_a] is True, "redo marks it again")
send({"t": "decon", "i": 0, "cancel": 1, "x1": fixed(40), "y1": fixed(40), "x2": fixed(42), "y2": fixed(41)})
tick(2)
hist = of_type(take(), "hist")
check(hist and hist[-1]["what"] == "cancel deconstruction" and F.decon_marks[chest_b] is None, "cancelling is remembered too")
send({"t": "undo", "h": hist[-1]["h"] if hist else 0})
tick(2)
check(F.decon_marks[chest_a] is True and F.decon_marks[chest_b] is True, "undoing a cancel puts the marks back")
# Upgrade marks
belt_u = spawn("transport-belt", 44.5, 40.5, force="player")
send({"t": "upgrade", "i": slot["upgrade-planner"], "x1": fixed(44), "y1": fixed(40), "x2": fixed(45), "y2": fixed(41)})
tick(2)
hist = of_type(take(), "hist")
check(hist and hist[-1]["what"] == "upgrade" and F.upgrade_marks[belt_u] is not None, "upgrade is remembered")
send({"t": "undo", "h": hist[-1]["h"] if hist else 0})
tick(2)
check(F.upgrade_marks[belt_u] is None, "undo cancels the upgrade")
send({"t": "redo", "h": hist[-1]["h"] if hist else 0})
tick(2)
check(F.upgrade_marks[belt_u] is not None and F.upgrade_marks[belt_u].name == "fast-transport-belt", "redo marks the upgrade again, to the same target")
# Rotation
d0 = belt_u.direction
send({"t": "rotate", "u": belt_u.unit_number, "p": eid["transport-belt"], "x": fixed(44.5), "y": fixed(40.5), "rev": 0})
tick(2)
hist = of_type(take(), "hist")
check(hist and hist[-1]["what"] == "rotation" and belt_u.direction == (d0 + 4) % 16, "a rotation is remembered")
send({"t": "undo", "h": hist[-1]["h"] if hist else 0})
tick(2)
check(belt_u.direction == d0, "undo turns it back")
# Super-forced build (Ctrl+Shift+click): a ghost through a one-entity blueprint
puppet.insert(lua.table_from({"name": "wooden-chest", "count": 1}))
send({"t": "build", "item": "wooden-chest", "x": fixed(10.5), "y": fixed(26.5), "d": 0, "ghost": 1, "sf": 1})
tick(2)
msgs = take()
sf = [m["e"] for m in of_type(msgs, "add") if m["e"][1] == eid["entity-ghost"] and m["e"][5].get("gh") == eid["wooden-chest"]]
check(sf and sf[0][2:4] == [fixed(10.5), fixed(26.5)] and of_type(msgs, "hist"), f"super-forced build places a ghost there, undoably: {sf}")
# The game's and an offline player's libraries
F.game_blueprints[1] = F.make_record("blueprint", "Smelting", "0FAKE|blueprint|Smelting|stone-furnace")
F.game_blueprints[2] = F.make_record("blueprint-book", "Trains", "0FAKE|blueprint-book|Trains|")
send({"t": "bp_lib"})
tick(2)
bpl = of_type(take(), "bpl")
check(bpl and bpl[0]["src"] == "game" and bpl[0]["l"][0][:3] == [1, "blueprint", "Smelting"] and bpl[0]["l"][1][1] == "blueprint-book"
      and bpl[0]["l"][0][3] == [["item", "transport-belt"]], f"bp_lib lists the game's library: {bpl}")
send({"t": "bp_rec", "q": 11, "src": "game", "ix": 1})
tick(2)
bp = of_type(take(), "bp")
check(bp and bp[0]["s"] == "0FAKE|blueprint|Smelting|stone-furnace" and bp[0]["src"] == "game" and bp[0]["ix"] == 1,
      f"bp_rec sends a record's string: {bp}")
send({"t": "bp_rec", "q": 12, "src": "game", "ix": 2, "to": -1})
tick(2)
ok = of_type(take(), "bp_ok")
check(ok and ok[-1]["i"] == -1 and ok[-1]["item"] == "blueprint-book", f"bp_rec with to = -1 takes it into the cursor: {ok}")
send({"t": "bp_page", "i": -1, "a": 2})
tick(2)
check(g.storage.f3d.lib_cursor[1].active_index == 2, "bp_page picks the book's page")
send({"t": "bp_rec", "q": 13, "src": "player", "ix": 1})
tick(2)
bp = of_type(take(), "bp")
check(bp and bp[0]["s"] == "" and bp[0].get("err"), "without a player taken over there is no player library")
for e in (chest_a, chest_b, belt_u):
    e.destroy()
for e in list(F.surface.entities.values()):
    if e.type == "entity-ghost" and e.position.y == 26.5:
        e.destroy()
take()

# --- circuit network ------------------------------------------------------------------------------
send({"t": "hello", "v": 1, "sid": "s1", "w": 1})
take()
ids = g.defines.wire_connector_id
arith = spawn("arithmetic-combinator", 4.5, 3.0, force="player")
const = spawn("constant-combinator", 6.5, 3.5, force="player")
F.signals[arith] = lua.table_from({ids.circuit_red: [{"signal": {"type": "item", "name": "iron-plate"}, "count": 40}]}, recursive=True)
send(open_cmd(arith))
tick(2)
gui = guis(take(), arith)
check(gui and gui[-1]["kind"] == "combinator" and gui[-1]["cb"].get("operation") == "*" and gui[-1]["cb"].get("second_constant") == 2,
      f"an arithmetic combinator opens with its parameters: {gui[-1:]}")
check(gui and gui[-1].get("sig") == {"r": [["item", "iron-plate", 40]], "g": []}, f"and the signals on its networks: {gui[-1:]}")
params = dict(gui[-1]["cb"]) if gui else {}
params["operation"] = "+"
send({"t": "set_cb", "u": arith.unit_number, "cb": params})
tick(2)
gui = guis(take(), arith)
check(gui and gui[-1]["cb"]["operation"] == "+" and arith.get_control_behavior().parameters.operation == "+",
      "set_cb writes the parameters back")
send(open_cmd(const))
send({"t": "set_cb", "u": const.unit_number, "cb": {"enabled": True, "signals": [["item", "iron-plate", 5], ["virtual", "signal-A", -3]]}})
tick(2)
gui = guis(take(), const)
check(gui and gui[-1]["cb"]["enabled"] is True and gui[-1]["cb"]["signals"] == [["item", "iron-plate", 5], ["virtual", "signal-A", -3]],
      f"a constant combinator's signals are set and read back: {gui[-1:]}")
# Sections: a second one, inactive with a multiplier; then back to one (the extra is removed).
two = [{"g": "", "on": 1, "m": 1, "s": [["item", "iron-plate", 5]]}, {"g": "", "on": 0, "m": 2, "s": [["virtual", "signal-B", 7, "rare"]]}]
send({"t": "set_cb", "u": const.unit_number, "cb": {"enabled": True, "sections": two}})
tick(2)
gui = guis(take(), const)
check(gui and gui[-1]["cb"]["sections"] == two and gui[-1]["cb"]["signals"] == [["item", "iron-plate", 5]],
      f"constant combinator sections (add_section, active, multiplier, quality) read back: {gui[-1:]}")
send({"t": "set_cb", "u": const.unit_number, "cb": {"enabled": False, "sections": two[:1]}})
tick(2)
gui = guis(take(), const)
check(gui and len(gui[-1]["cb"]["sections"]) == 1 and gui[-1]["cb"]["enabled"] is False, f"remove_section drops the extra one: {gui[-1:]}")
send({"t": "set_cb", "u": const.unit_number, "cb": "nonsense"})
tick(2)
check(any(m["text"] == "That isn't a combinator" for m in of_type(take(), "msg")), "bad settings are refused")
send({"t": "close"})

# Wire tools: red wire from the constant combinator to the arithmetic one's input, again to undo.
def wire_end(entity, dx=0.0, dy=0.0):
    p = entity.position
    return {"u": entity.unit_number, "p": eid[entity.name], "x": fixed(p.x), "y": fixed(p.y),
            "mx": fixed(p.x + dx), "my": fixed(p.y + dy)}


send({"t": "wire", "k": "r", "a": wire_end(const), "b": wire_end(arith, 0, 0.4)})
tick(2)
msgs = take()
red = arith.get_wire_connector(ids.combinator_input_red, False)
check(red.is_connected_to(const.get_wire_connector(ids.circuit_red, False)), "wire: a red wire connects two combinators (connect_to)")
check({m["e"][0] for m in of_type(msgs, "upd")} >= {arith.unit_number, const.unit_number}
      and arith.unit_number in of_type(msgs, "upd")[-1]["e"][5].get("r", []) + [m["e"][5].get("r", [0])[0] for m in of_type(msgs, "upd")],
      f"and both ends are sent again with their wires: {of_type(msgs, 'upd')}")
send({"t": "wire", "k": "r", "a": wire_end(const), "b": wire_end(arith, 0, 0.4)})
tick(2)
take()
check(not red.is_connected_to(const.get_wire_connector(ids.circuit_red, False)), "wire: the same pair again disconnects them")
send({"t": "wire", "k": "w", "a": wire_end(const), "b": wire_end(arith)})
tick(2)
check(any("Copper wire" in m["text"] for m in of_type(take(), "msg")), "copper wire on combinators is refused")
pole_a = spawn("small-electric-pole", -2.5, 4.5, force="player")
pole_b = spawn("small-electric-pole", 3.5, 4.5, force="player")
pole_far = spawn("small-electric-pole", 6.5, -4.5, force="player")
send({"t": "wire", "k": "w", "a": wire_end(pole_a), "b": wire_end(pole_b)})
tick(2)
take()
copper = pole_a.get_wire_connector(ids.pole_copper, False)
check(copper.is_connected_to(pole_b.get_wire_connector(ids.pole_copper, False)), "copper wire connects two poles")
F.wire_reach = 7.5
send({"t": "wire", "k": "w", "a": wire_end(pole_a), "b": wire_end(pole_far)})
tick(2)
check(any(m["text"] == "Wire can't reach that far" for m in of_type(take(), "msg")), "a wire that can't reach is refused (can_wire_reach)")
send({"t": "wire_clear", **{k: v for k, v in wire_end(pole_a).items() if k in ("u", "p", "x", "y")}})
tick(2)
msgs = take()
check(len(copper.connections) == 0 and len(pole_b.get_wire_connector(ids.pole_copper, False).connections) == 0,
      "wire_clear removes a pole's copper cables (disconnect_all)")
check(any(m["e"][0] == pole_b.unit_number for m in of_type(msgs, "upd")), "and the pole at the other end is sent again")

# Circuit settings (gui.cc / set_cc): an inserter's enable condition and read modes.
ins_c = spawn("inserter", 2.5, 6.5, force="player")
F.networks[ins_c] = lua.table_from({ids.circuit_red: lua.table_from({"network_id": 12})})
send(open_cmd(ins_c))
tick(2)
gui = guis(take(), ins_c)
cc = gui[-1].get("cc") if gui else None
check(cc and cc["o"] == "inserter" and cc["w"] == 1 and cc["nets"] == {"r": 12, "g": 0}
      and cc["f"].get("circuit_hand_read_mode") == "hold" and cc["f"].get("circuit_enable_disable") == 0,
      f"gui.cc: an inserter's circuit settings, wired to network 12: {cc}")
send({"t": "set_cc", "u": ins_c.unit_number, "f": {
    "circuit_enable_disable": 1, "circuit_condition": {"first_signal": {"type": "item", "name": "iron-plate"}, "comparator": ">", "constant": 50},
    "circuit_hand_read_mode": "pulse", "circuit_read_hand_contents": 1, "circuit_set_stack_size": 1,
    "circuit_stack_control_signal": {"type": "virtual", "name": "signal-S"}, "not_a_field": 1}})
tick(2)
gui = guis(take(), ins_c)
f = gui[-1]["cc"]["f"] if gui else {}
check(f.get("circuit_enable_disable") == 1 and f.get("circuit_condition", {}).get("first_signal") == {"type": "item", "name": "iron-plate"}
      and f["circuit_condition"].get("constant") == 50 and f.get("circuit_hand_read_mode") == "pulse"
      and f.get("circuit_stack_control_signal") == {"type": "virtual", "name": "signal-S"}, f"set_cc writes the behaviour's fields: {f}")
send({"t": "set_cc", "u": ins_c.unit_number, "f": {"circuit_stack_control_signal": {}}})
tick(2)
gui = guis(take(), ins_c)
check(gui and gui[-1]["cc"]["f"].get("circuit_stack_control_signal") in ({}, []), "an empty signal clears it")

# A lamp's colour and its circuit colour settings.
lamp_c = spawn("small-lamp", 4.5, 6.5, force="player")
send(open_cmd(lamp_c))
tick(2)
gui = guis(take(), lamp_c)
check(gui and gui[-1].get("col") == [255, 255, 255] and gui[-1]["cc"]["o"] == "lamp" and gui[-1]["cc"]["w"] == 0,
      f"a lamp opens with its colour and circuit settings: {gui[-1:]}")
send({"t": "set_color", "u": lamp_c.unit_number, "c": [255, 64, 0]})
send({"t": "set_cc", "u": lamp_c.unit_number, "f": {"use_colors": 1, "color_mode": "components", "red_signal": {"type": "virtual", "name": "signal-R"}}})
tick(2)
gui = guis(take(), lamp_c)
check(gui and gui[-1]["col"] == [255, 64, 0] and gui[-1]["cc"]["f"].get("use_colors") == 1 and gui[-1]["cc"]["f"].get("color_mode") == "components",
      f"set_color and the lamp's colour mode: {gui[-1:]}")
check(gui and gui[-1].get("ao") == 0, f"a lamp sends Always on: {gui[-1:]}")
send({"t": "set_lamp", "u": lamp_c.unit_number, "ao": 1})
tick(2)
gui = guis(take(), lamp_c)
check(gui and gui[-1].get("ao") == 1 and lamp_c.always_on, f"set_lamp turns Always on on: {gui[-1:]}")

# A rail signal opens (status only); a combinator sends and takes its description.
rsig = spawn("rail-signal", 6.5, 6.5, force="player")
send(open_cmd(rsig))
tick(2)
check(bool(guis(take(), rsig)), "a rail signal opens a window")
rod = spawn("lightning-rod", 5.5, 8.5, force="player")
send(open_cmd(rod))
tick(2)
msgs = take()
check(not guis(msgs, rod) and not [m for m in of_type(msgs, "msg") if "open" in m["text"]],
      "a lightning rod opens no window and says nothing, as in 2.1.23")
rod.destroy()
desc_c = spawn("constant-combinator", 3.5, 7.5, force="player")
send(open_cmd(desc_c))
tick(2)
gui = guis(take(), desc_c)
check(gui and gui[-1].get("desc") == "", f"a combinator sends its description: {gui[-1:]}")
send({"t": "set_desc", "u": desc_c.unit_number, "text": "Outpost"})
tick(2)
gui = guis(take(), desc_c)
check(gui and gui[-1].get("desc") == "Outpost" and desc_c.combinator_description == "Outpost", f"set_desc: {gui[-1:]}")
send({"t": "close"})
tick(1)
take()
for e in (rsig, desc_c):
    e.destroy()

# Turret priority targets.
tur_c = spawn("gun-turret", -4.0, 7.0, force="player")
send(open_cmd(tur_c))
send({"t": "set_targets", "u": tur_c.unit_number, "l": ["small-biter", "nonsense"], "ign": 1})
tick(2)
gui = guis(take(), tur_c)
check(gui and gui[-1].get("tgt") == {"l": ["small-biter"], "ign": 1}, f"set_targets: priority targets and ignore the rest: {gui[-1:]}")
send({"t": "set_targets", "u": tur_c.unit_number, "l": []})
tick(2)
gui = guis(take(), tur_c)
check(gui and gui[-1]["tgt"]["l"] in ([], {}), f"and clears them (set_priority_target without an entity): {gui[-1:]}")
send({"t": "close"})
for e in (arith, const, pole_a, pole_b, pole_far, ins_c, lamp_c, tur_c):
    e.destroy()
tick(2)
take()

# Spidertrons (entity_ui.lua veh, set_vehicle; spiders.lua spider_go / spider_q), artillery's auto
# targeting (art, set_artillery), a storage tank's pipeline and flush (pl, flush), a train's group.
spider = spawn("spidertron", -3.0, 4.0, force="player")
send(open_cmd(spider))
tick(2)
gui = guis(take(), spider)
check(gui and gui[-1].get("kind") == "vehicle" and gui[-1].get("veh") == {"grid": 0, "lbl": "", "at": [1, 0]} and gui[-1].get("col") == [255, 128, 0],
      f"a spidertron opens with its name, auto targeting and colour: {gui[-1:]}")
send({"t": "set_vehicle", "u": spider.unit_number, "lbl": "Spidey", "wi": 1})
send({"t": "set_color", "u": spider.unit_number, "c": [0, 0, 255]})
tick(2)
gui = guis(take(), spider)
check(gui and gui[-1]["veh"] == {"grid": 0, "lbl": "Spidey", "at": [1, 1]} and gui[-1]["col"] == [0, 0, 255] and spider.entity_label == "Spidey",
      f"set_vehicle names it and turns targeting with a gunner on; set_color colours it: {gui[-1:]}")
send({"t": "close"})
send({"t": "spider_go", "l": [spider.unit_number, 999999], "x": fixed(20), "y": fixed(-5)})
tick(1)
spd = of_type(take(), "spd")
check(spd and spd[-1]["l"] == [[spider.unit_number, [[fixed(20), fixed(-5)]]]], f"spider_go sends it there (autopilot_destination): {spd[-1:]}")
send({"t": "spider_go", "l": [spider.unit_number], "x": fixed(25), "y": fixed(-5), "q": 1})
send({"t": "spider_q", "l": [spider.unit_number]})
tick(1)
spd = of_type(take(), "spd")
check(spd and spd[-1]["l"][0][1] == [[fixed(20), fixed(-5)], [fixed(25), fixed(-5)]], f"Shift queues a waypoint (add_autopilot_destination): {spd[-1:]}")
send({"t": "spider_go", "l": [spider.unit_number], "x": fixed(1), "y": fixed(1)})
tick(1)
spd = of_type(take(), "spd")
check(spd and spd[-1]["l"][0][1] == [[fixed(1), fixed(1)]], f"a plain click replaces the queue: {spd[-1:]}")
spider.destroy()
art = spawn("artillery-turret", -8.5, 4.5, force="player")
send(open_cmd(art))
tick(2)
gui = guis(take(), art)
check(gui and gui[-1].get("art") == 1, f"artillery sends its auto targeting: {gui[-1:]}")
send({"t": "set_artillery", "u": art.unit_number, "on": 0})
tick(2)
gui = guis(take(), art)
check(gui and gui[-1].get("art") == 0 and art.artillery_auto_targeting is False, f"set_artillery turns it off: {gui[-1:]}")
send({"t": "close"})
art.destroy()
tank = spawn("storage-tank", -3.5, 8.5, force="player")
F.set_fluid(tank, 1, lua.table_from({"name": "crude-oil", "amount": 2000}), 25000)
F.segments[tank] = lua.table_from({"fluid": lua.table_from({"name": "crude-oil", "amount": 6000}), "capacity": 40000})
send(open_cmd(tank))
tick(2)
gui = guis(take(), tank)
check(gui and gui[-1].get("pl") == ["crude-oil", 6000, 40000], f"a storage tank sends its pipeline's contents (get_fluid_segment_fluid): {gui[-1:]}")
send({"t": "flush", "u": tank.unit_number, "pipe": 0})
tick(2)
gui = guis(take(), tank)
check(tank.get_fluid(1) is None, f"flush empties the tank (remove_fluid): {gui[-1:]}")
send({"t": "flush", "u": tank.unit_number, "pipe": 1})
tick(2)
gui = guis(take(), tank)
check(gui and gui[-1].get("pl") == ["", 0, 25000], f"flush with pipe 1 empties the pipeline (clear_fluid_segment_fluid): {gui[-1:]}")
send({"t": "close"})
tank.destroy()
tick(2)
take()

# --- map: charts and tags -------------------------------------------------------------------------
send({"t": "hello", "v": 1, "sid": "s1", "w": 1})
take()
F.charted["0,0"] = True
g.storage.f3d.explored = None  # what the character charted itself, tested below
wall = spawn("stone-wall", 28.5, 28.5, force="player")
ore = spawn("iron-ore", 29.5, 28.5, amount=100)
send({"t": "map", "cx1": 0, "cy1": 0, "cx2": 1, "cy2": 0, "res": 2})
tick(2)
msgs = take()
charts = {(m["cx"], m["cy"]): m for m in of_type(msgs, "chart")}
c00 = charts.get((0, 0))
check(c00 and c00["n"] == 16 and len(c00["px"]) == 256, f"a charted chunk comes as 16 x 16 pixels at 2 tiles each: {c00}")
check(charts.get((1, 0), {}).get("n") == 0, "a chunk not charted yet says so (n = 0)")
check(c00 and c00["pal"][c00["px"][14 * 16 + 14]] == [204, 217, 204],
      "a wall without a map colour gets Factorio's wall colour, over the ore under it")
check(c00 and [51, 128, 26] in c00["pal"], "tiles are drawn in their map colour")
check(of_type(msgs, "tags") and of_type(msgs, "tags")[-1]["l"] in ([], {}), "a map request sends the tags (none yet)")
send({"t": "map", "cx1": 0, "cy1": 0, "cx2": 0, "cy2": 0, "res": 3})
tick(1)
c00 = [m for m in of_type(take(), "chart") if (m["cx"], m["cy"]) == (0, 0)]
check(c00 and c00[0]["n"] == 8, "an unknown resolution falls back to 4 tiles per pixel")
send({"t": "map", "cx1": -100, "cy1": -100, "cx2": 100, "cy2": 100, "res": 32})
tick(1)
check(len(g.storage.f3d.map.queue) <= 1024, "a huge request is cut to the 1024 chunks nearest its centre")
send({"t": "map", "cx1": 0, "cy1": 0, "cx2": 0, "cy2": 0, "res": 32})
tick(2)
c00 = [m for m in of_type(take(), "chart") if (m["cx"], m["cy"]) == (0, 0)]
check(c00 and c00[0]["n"] == 1 and len(c00[0]["px"]) == 1, "32 tiles per pixel is one pixel per chunk")
wall.destroy()
ore.destroy()

# The work budget (budget.lua): a busy chunk's chart and snapshot are read in slices over several
# ticks, and no tick spends more than the budget; `budget` sets it (clamped), `wb` reports it.
start_tick = g.game.tick
send({"t": "budget", "u": 400})
tick(1)
check(g.storage.f3d.bud.limit == 400, f"budget sets the work budget: {g.storage.f3d.bud.limit}")
F.charted["-3,3"] = True
dense = [spawn("stone-wall", -95.5 + i % 32, 96.5 + i // 32, force="player") for i in range(1000)]
take()
send({"t": "map", "cx1": -3, "cy1": 3, "cx2": -3, "cy2": 3, "res": 2})
used, got, ticks = [], None, 0
while got is None and ticks < 40:
    tick(1)
    ticks += 1
    used.append(g.storage.f3d.bud.used)
    got = next((m for m in of_type(take(), "chart") if (m["cx"], m["cy"]) == (-3, 3)), None)
check(got and got["n"] == 16 and sum(1 for p in got["px"] if got["pal"][p] == [204, 217, 204]) == 256,
      f"a chart read in strips still has every wall: {got and got['pal']}")
check(ticks >= 4 and max(used) <= 400, f"a 1000-entity chart takes several ticks, none over the budget: {ticks} ticks, {used}")
old_subs = [[int(c[1]), int(c[2])] for c in g.storage.f3d.subs.values()]
send({"t": "sub", "c": old_subs + [[-3, 3]]})
used, ents, head, ticks = [], [], None, 0
while not (head and len(ents) == head.get("parts", -1)) and ticks < 200:
    tick(1)
    ticks += 1
    used.append(g.storage.f3d.bud.used)
    msgs = take()
    head = next((m for m in of_type(msgs, "chunk") if (m["cx"], m["cy"]) == (-3, 3)), head)
    ents += [m for m in of_type(msgs, "ents") if (m["cx"], m["cy"]) == (-3, 3)]
records = [rec for m in ents for rec in m["e"]]
check(head and len(records) == 1000, f"a snapshot read in strips has every entity once: {len(records)} {head}")
check(max(used) <= 400, f"no tick of the snapshot over the budget: {max(used)}")
send({"t": "sub", "c": old_subs})
for e in dense:
    e.destroy()
for u, want in ((5, 50), (10 ** 9, 20000), ("x", 20000), (500, 500)):
    send({"t": "budget", "u": u})
    tick(1)
    check(g.storage.f3d.bud.limit == want, f"budget {u!r} -> {want}: {g.storage.f3d.bud.limit}")
tick(60)
wb = of_type(take(), "wb")
check(wb and wb[-1]["b"] == 500 and wb[-1]["n"] == 60 and {"chunks", "map", "reqs", "radars", "techs"} <= set(wb[-1]["q"]),
      f"wb once a second: the budget, the units used and the queues: {wb[-1:]}")
# The checks below count on the tick staying in step: on to a whole number of 600 ticks.
pad = -(g.game.tick - start_tick) % 600
while pad > 0:
    send({"t": "hello", "v": 1, "sid": "s1", "w": 1})
    tick(min(pad, 100))
    pad -= min(pad, 100)
take()

# A chart is kept while its chunk looks the same, and made again once something is built there.
keep = spawn("stone-wall", 28.5, 28.5, force="player")
send({"t": "map", "cx1": 0, "cy1": 0, "cx2": 0, "cy2": 0, "res": 2})
tick(2)
take()
keep.destroy()
chest = spawn("wooden-chest", 28.5, 28.5, force="player")  # as many entities, and no event
send({"t": "map", "cx1": 0, "cy1": 0, "cx2": 0, "cy2": 0, "res": 2})
tick(2)
kept = [m for m in of_type(take(), "chart") if (m["cx"], m["cy"]) == (0, 0)]
check(kept and kept[0]["pal"][kept[0]["px"][14 * 16 + 14]] == [204, 217, 204],
      "a chunk with as many entities and no event since is sent from its kept chart")
F["raise"]("script_raised_built", lua.table_from({"entity": chest}))
take()
send({"t": "map", "cx1": 0, "cy1": 0, "cx2": 0, "cy2": 0, "res": 2})
tick(2)
redone = [m for m in of_type(take(), "chart") if (m["cx"], m["cy"]) == (0, 0)]
check(redone and redone[0]["pal"][redone[0]["px"][14 * 16 + 14]] != [204, 217, 204],
      "... and charted again once something is built in it")
chest.destroy()

# The map view's layers ride with the chart: poles, turrets, roboports, stops, signals, robots.
layer_ents = [spawn("small-electric-pole", 20.5, 20.5, force="player"), spawn("gun-turret", 22, 22, force="player"),
              spawn("roboport", 26, 26, force="player"), spawn("train-stop", 16, 16, force="player", backer_name="Iron"),
              spawn("rail-signal", 12.5, 12.5, force="player"), spawn("construction-robot", 10.5, 10.5, force="player"),
              spawn("gun-turret", 6, 6, force="enemy"), spawn("small-electric-pole", 40.5, 20.5, force="player")]
send({"t": "map", "cx1": 0, "cy1": 0, "cx2": 0, "cy2": 0, "res": 4})
tick(2)
c00 = [m for m in of_type(take(), "chart") if (m["cx"], m["cy"]) == (0, 0)]
ov = sorted(c00[0].get("ov", []), key=lambda r: r[0]) if c00 else []
check(["e", fixed(20.5), fixed(20.5), 2.5] in ov, f"a pole comes with its supply radius: {ov}")
check(["t", fixed(22), fixed(22), 18] in ov, "a turret with its range")
check(["l", fixed(26), fixed(26), 25, 55] in ov, "a roboport with its logistic and construction radius")
check(["s", fixed(16), fixed(16), "Iron"] in ov, "a train stop with its name")
check(["g", fixed(12.5), fixed(12.5), 1] in ov, "a rail signal with its state")
check(["b", fixed(10.5), fixed(10.5)] in ov, "a worker robot")
check(len(ov) == 6, "nothing of other forces, nothing from the next chunk")
# The copper wires between poles, each once.
wired = spawn("small-electric-pole", 25.5, 20.5, force="player")
layer_ents[0].get_wire_connector(5, True).connect_to(wired.get_wire_connector(5, True))
send({"t": "map", "cx1": 0, "cy1": 0, "cx2": 0, "cy2": 0, "res": 4})
tick(2)
c00 = [m for m in of_type(take(), "chart") if (m["cx"], m["cy"]) == (0, 0)]
wires = [r for r in (c00[0].get("ov", []) if c00 else []) if r[0] == "w"]
check(wires == [["w", fixed(20.5), fixed(20.5), fixed(25.5), fixed(20.5)]], f"a copper wire between two poles, once: {wires}")
layer_ents.append(wired)
for e in layer_ents:
    e.destroy()

# A chart carries its chunk's pollution.
F.pollution = lua.eval('{["0,0"] = 1234.4}')
send({"t": "map", "cx1": 0, "cy1": 0, "cx2": 1, "cy2": 0, "res": 32})
tick(2)
pols = {(m["cx"], m["cy"]): m.get("pol") for m in of_type(take(), "chart")}
check(pols.get((0, 0)) == 1234 and pols.get((1, 0)) is None, f"charts carry their chunk's pollution (pol), none where there is none: {pols}")
F.pollution = lua.eval("{}")

# Vulcanus' demolisher territories, as their chunks, so the client draws the red borders.
F.territories = lua.eval("{{{x = 1, y = 2}, {x = 2, y = 2}}, {{x = -5, y = 0}}}")
g.package.loaded["scripts.planets"].territories_soon()
tick(1)
terr = of_type(take(), "terr")
check(terr and terr[-1]["parts"] == 1 and terr[-1]["l"] == [[1, 2, 2, 2], [-5, 0]] and terr[-1].get("si") == 1,
      f"terr: every territory's chunks, with the surface they are on: {terr[-1:]}")
F.territories = lua.eval("{}")
g.package.loaded["scripts.planets"].territories_soon()
tick(1)
terr = of_type(take(), "terr")
check(terr and terr[-1]["l"] == [], "a surface without territories sends an empty list (it clears them)")

# Right-click on the map removes the ghost there (and says so), else nothing.
map_ghost = spawn("entity-ghost", 7.5, 6.5, inner_name="wooden-chest", force="player")
gu = map_ghost.unit_number
send({"t": "unghost", "q": 7, "x": fixed(7.6), "y": fixed(6.4)})
tick(1)
msgs = take()
check(not map_ghost.valid and [m["n"] for m in of_type(msgs, "unghost")] == [1] and any(d["u"] == gu for d in of_type(msgs, "del")),
      f"unghost removes the ghost under the click and sends its del: {of_type(msgs, 'unghost')}")
send({"t": "unghost", "q": 8, "x": fixed(30.5), "y": fixed(30.5)})
tick(1)
check([(m["q"], m["n"]) for m in of_type(take(), "unghost")] == [(8, 0)], "no ghost there: n = 0, so the client adds a tag")
send({"t": "tag_add", "x": 5 * 256, "y": 6 * 256, "text": "base", "icon": ["item", "iron-plate"]})
tick(1)
tags = of_type(take(), "tags")
check(tags and tags[-1]["l"] == [[1, 5 * 256, 6 * 256, "base", "item", "iron-plate"]], f"tag_add puts a tag on the map: {tags[-1:]}")
send({"t": "tag_add", "x": 50 * 256, "y": 0, "text": "far"})
tick(1)
check(any("Can't put a tag there" in m["text"] for m in of_type(take(), "msg")), "a tag where the map isn't charted is refused")
F["raise"]("on_chart_tag_modified", lua.table_from({}))
tick(1)
check(of_type(take(), "tags"), "the tags are sent again when they change in the game")
send({"t": "tag_del", "id": 1})
tick(1)
tags = of_type(take(), "tags")
check(tags and tags[-1]["l"] in ([], {}), "tag_del removes it")

px, py = g.storage.f3d.puppet.position.x, g.storage.f3d.puppet.position.y
F.chart_requests = lua.table_from([])
tick(121)
take()
reqs = list(F.chart_requests.values())
check(reqs and reqs[0][1][1] + 96 == px and reqs[0][2][2] - 96 == py,
      "the force charts around a player-less character every 2 seconds")
# A headless server with nobody connected never carries those requests out: the chunks the
# character was near count as charted anyway.
send({"t": "map", "cx1": 1, "cy1": 0, "cx2": 1, "cy2": 0, "res": 32})
tick(1)
c10 = [m for m in of_type(take(), "chart") if (m["cx"], m["cy"]) == (1, 0)]
check(c10 and c10[0]["n"] == 1 and not F.charted["1,0"],
      f"a chunk the character has been near is charted even if the game never charted it: {c10}")
# The map's surface switcher: the surfaces it can show, and charts of a surface by index.
g.storage.f3d.surfs_sig = None
tick(1)
while g.game.tick % 300:
    tick(1)
tick(1)
surfs = of_type(take(), "surfs")
check(surfs and [1, "nauvis", "nauvis", "", 0] in surfs[-1]["l"], f"the surfaces the map can show are sent when they change: {surfs}")
send({"t": "hello", "v": 1, "sid": "s1", "w": 1})  # keep-alive: the waits above add up past the timeout
other = F.make_surface(50, "f3d-other")
g.storage.f3d.surfs_sig = None
tick(1)
while g.game.tick % 300:
    tick(1)
tick(1)
surfs = of_type(take(), "surfs")
check(surfs and surfs[-1]["l"][-1] == [50, "f3d-other", "", "", 0], f"a surface that is no planet nor platform comes last (Factorio's Other): {surfs[-1:]}")
F.game_surfaces[50] = None
send({"t": "map", "cx1": 0, "cy1": 0, "cx2": 0, "cy2": 0, "res": 32, "si": 1})
tick(2)
msgs = take()
c00 = [m for m in of_type(msgs, "chart") if (m["cx"], m["cy"]) == (0, 0)]
check(c00 and c00[0]["si"] == 1 and of_type(msgs, "tags") and of_type(msgs, "tags")[-1]["si"] == 1,
      "a map request names its surface (si), and its charts and tags say which surface they are")
send({"t": "map", "cx1": 0, "cy1": 0, "cx2": 0, "cy2": 0, "res": 32, "si": 99})
tick(2)
c00 = [m for m in of_type(take(), "chart") if (m["cx"], m["cy"]) == (0, 0)]
check(c00 and c00[0]["si"] == 1, "an unknown surface falls back to the character's")
# Remote building: ghosts only where the map is charted, as in the game.
send({"t": "build", "item": "assembling-machine-1", "x": 5000 * 256, "y": 5000 * 256, "d": 0, "ghost": 1})
tick(1)
msgs = take()
check(any("uncharted" in m["text"] for m in of_type(msgs, "msg")), "a ghost far away on uncharted ground is refused")

# --- trains: stops, train state, schedules, wagons --------------------------------------------------
send({"t": "hello", "v": 1, "sid": "s1", "w": 1})
take()
px, py = g.storage.f3d.puppet.position.x, g.storage.f3d.puppet.position.y
stop = spawn("train-stop", px + 3, py + 3, force="player", backer_name="Iron")
F["raise"]("script_raised_built", lua.table_from({"entity": stop}))
tick(1)
adds = [m["e"] for m in of_type(take(), "add") if m["e"][0] == stop.unit_number]
check(adds and adds[0][5].get("n") == "Iron", f"a train stop's record has its name: {adds}")
loco2 = spawn("locomotive", px + 6, py + 1, force="player")
wagon = spawn("cargo-wagon", px + 6, py + 8, force="player")
rail = spawn("straight-rail", px + 20, py, force="player")
train = F.couple(loco2, wagon)
td = F.train_data[train]
td.state = g.defines.train_state.wait_station
td.station = stop
td.path_end_stop = stop
td.speed = 0.25
tick(31)  # trains are looked at once every 30 ticks, on a phase of their own
tr = [r for m in of_type(take(), "tr") for r in m["l"] if r[0] == train.id]
check(tr and tr[-1] == [train.id, "wait_station", 0, 250, stop.unit_number, "Iron", [loco2.unit_number, wagon.unit_number]],
      f"tr: a train's state, speed, stop, destination and carriages: {tr[-1:]}")

# The map draws trains live; the client asks with `mtr` while a map is open.
send({"t": "mtr"})
tick(1)
mtr = of_type(take(), "mtr")
cars = mtr[-1]["l"] if mtr else []
check(mtr and mtr[-1]["parts"] == 1 and len(cars) == 12 and cars[0] == fixed(px + 6) and cars[1] == fixed(py + 1)
      and cars[3] > cars[4] > 0 and cars[5] == 0xEB1200 and cars[11] == 0x9A9A9A,
      f"mtr: each carriage's place, turn, size and map colour: {mtr[-1:]}")
send({"t": "mtr"})
tick(1)
check(not of_type(take(), "mtr"), "mtr: asks closer together than a third of a second are ignored")
# Only what radars (or the character) see: a train far away shows once a radar covers it, and
# the first part lists the working radars (cov) so the map dims the rest.
far_loco = spawn("locomotive", px + 400, py + 1, force="player")
tick(25)
send({"t": "mtr"})
tick(1)
m1 = of_type(take(), "mtr")
far_radar = spawn("radar", px + 420, py + 20, force="player")
F["raise"]("script_raised_built", lua.table_from({"entity": far_radar}))
tick(301)
send({"t": "mtr"})
tick(1)
m2 = of_type(take(), "mtr")
fx_far = fixed(px + 400)
check(m1 and fx_far not in m1[-1]["l"][0::6] and m1[-1].get("cov") in ([], {}),
      f"mtr: a train no radar covers isn't sent, and no radars means an empty cov: {m1[-1:]}")
rcx, rcy = math.floor((px + 420) / 32), math.floor((py + 20) / 32)
check(m2 and fx_far in m2[-1]["l"][0::6] and m2[-1].get("cov") == [rcx, rcy, 3],
      f"mtr: a working radar's chunks show their trains, and cov lists it: {m2[-1:]}")
# H13: the map's logistic layer shows every roboport on the surface (`mrp`), read from the force's
# logistic networks' cells rather than the charts the client loaded; a personal roboport's cell isn't one.
rp_near = spawn("roboport", px + 30, py + 30, force="player")
rp_far = spawn("roboport", px + 900, py - 700, force="player")
F.lnets = lua.table_from({"nauvis": lua.table_from([
    F.make_network(3, lua.table_from([0, 0, 0, 0]), lua.table(),
                   lua.table_from([F.make_cell(rp_near, 25, 55), F.make_cell(rp_far, 25, 55)])),
    F.make_network(4, lua.table_from([0, 0, 0, 0]), lua.table(), lua.table_from([F.make_cell(far_loco, 0, 10)]))])})
send({"t": "mrp", "q": 5})
tick(2)
rp = of_type(take(), "mrp")
check(rp and rp[-1].get("last") == 1 and rp[-1].get("q") == 5 and rp[-1].get("si") == 1
      and rp[-1].get("l") == [fixed(px + 30), fixed(py + 30), fixed(25), fixed(55), fixed(px + 900), fixed(py - 700), fixed(25), fixed(55)],
      f"mrp: every roboport of the surface's networks with its logistic and construction radius: {rp[-1:]}")
send({"t": "mrp", "q": 6})
tick(2)
check(not of_type(take(), "mrp"), "mrp: asks within a second for the same surface are ignored")
send({"t": "hello", "v": 1, "sid": "s1", "w": 1})  # keep-alive: the waits here add up past the timeout
# Ground in a roboport's construction area counts as seen, like a radar's (H13): the map's trains
# there, the remote view's movers and buildings to open; a mobile cell (a personal roboport) doesn't.
# Chunks are seen by their centres: these are chunk centres inside (in_x, in_x2) and past (out_x) the
# far roboport's construction square (55 tiles round px + 900, py - 700).
rx, ry = px + 900, py - 700
mid_y = math.floor(ry / 32) * 32 + 16
in_x, in_x2 = math.floor((rx + 30) / 32) * 32 + 16, math.floor((rx - 30) / 32) * 32 + 16
out_x = math.floor((rx + 90) / 32) * 32 + 16
rp_loco = spawn("locomotive", rx, ry + 10, force="player")
mobile_car = spawn("car", px - 900, py + 700, force="player")
mobile_loco = spawn("locomotive", px - 900, py + 690, force="player")
F.lnets["nauvis"][3] = F.make_network(5, lua.table_from([0, 0, 0, 0]), lua.table(),
                                      lua.table_from([F.make_cell(mobile_car, 15, 30)]))
tick(21)
send({"t": "mtr"})
tick(1)
mt = of_type(take(), "mtr")
mt_x = mt[-1]["l"][0::6] if mt else []
check(mt and fixed(rx) in mt_x and fixed(px - 900) not in mt_x,
      f"mtr: a train in a roboport's construction area is shown, one by a personal roboport isn't: {mt_x}")
rp_asm = spawn("assembling-machine-1", in_x + 0.5, mid_y + 0.5, force="player")
far_asm2 = spawn("assembling-machine-1", out_x + 0.5, mid_y + 0.5, force="player")
send(dict(open_cmd(rp_asm), rv=1))
tick(2)
check(bool(guis(take(), rp_asm)), "rv: a building in a roboport's construction area opens from the remote view")
send(dict(open_cmd(far_asm2), rv=1))
tick(2)
check(not guis(take(), far_asm2), "rv: one past the construction area doesn't")
send({"t": "close"})
rp_car = spawn("car", in_x2, mid_y)
past_car = spawn("car", out_x, mid_y)
send({"t": "focus", "x": fixed(rx), "y": fixed(ry), "r": 128, "rv": 1})
tick(61)
rp_units = {rec[0] for rec in decode_records(last_frame(take(), "mv"))}
check(rp_car.unit_number in rp_units and past_car.unit_number not in rp_units,
      f"remote view: a mover in a roboport's construction area is sent, one past it isn't: {sorted(rp_units)}")
send({"t": "focus", "x": fixed(px), "y": fixed(py), "r": 32})
tick(2)
take()
for e in (rp_loco, mobile_car, mobile_loco, rp_asm, far_asm2, rp_car, past_car):
    e.destroy()
tick(91)  # 180 ticks in all here: the checks further on wait for ticks on a phase of their own
F.lnets = lua.table()
send({"t": "hello", "v": 1, "sid": "s1", "w": 1})  # keep-alive
send({"t": "mrp", "q": 7})
tick(2)
rp = of_type(take(), "mrp")
check(rp and rp[-1].get("q") == 7 and rp[-1].get("last") == 1 and rp[-1].get("l") in ([], {}),
      f"mrp: no networks, an empty last part: {rp[-1:]}")
# H23: switching the map to a planet centres on the force's landing pad there (`lpad`).
pad = spawn("cargo-landing-pad", px + 60, py - 40, force="player")
F["raise"]("script_raised_built", lua.table_from({"entity": pad}))
send({"t": "lpad", "si": 1, "q": 11})
tick(2)
lp = of_type(take(), "lpad")
check(lp and lp[-1].get("q") == 11 and lp[-1].get("si") == 1 and lp[-1].get("x") == fixed(px + 60) and lp[-1].get("y") == fixed(py - 40),
      f"lpad: the landing pad's position on that surface: {lp[-1:]}")
send({"t": "lpad", "si": 999, "q": 12})
tick(2)
lp = of_type(take(), "lpad")
check(lp and lp[-1].get("q") == 12 and "x" not in lp[-1], f"lpad: no such surface, no position: {lp[-1:]}")
pad.destroy()
# The 3D remote view (focus rv = 1) sends moving things only where radars or the character see,
# and `cov` about once a second; the normal view sends everything.
seen_car = spawn("car", px + 450, py + 30)  # the radar at px + 420 reveals 3 chunks round its own
unseen_car = spawn("car", px + 555, py + 30)
send({"t": "focus", "x": fixed(px + 500), "y": fixed(py), "r": 64, "rv": 1})
tick(61)
rv_msgs = take()
rv_units = {rec[0] for rec in decode_records(last_frame(rv_msgs, "mv"))}
covs = of_type(rv_msgs, "cov")
check(seen_car.unit_number in rv_units and unseen_car.unit_number not in rv_units,
      f"remote view: a mover a radar sees is sent, one no radar sees isn't: {sorted(rv_units)}")
check(covs and covs[-1]["l"] == [rcx, rcy, 3] and covs[-1]["x"] == fixed(px) and covs[-1]["cr"] == 96 and covs[-1]["si"] == 1,
      f"remote view: cov lists the radars and the character's place and radius: {covs[-1:]}")
send({"t": "focus", "x": fixed(px + 500), "y": fixed(py), "r": 64})
tick(61)
plain_msgs = take()
plain_units = {rec[0] for rec in decode_records(last_frame(plain_msgs, "mv"))}
check({seen_car.unit_number, unseen_car.unit_number} <= plain_units and not of_type(plain_msgs, "cov"),
      f"outside the remote view every mover is sent and no cov: {sorted(plain_units)}")
send({"t": "focus", "x": fixed(px), "y": fixed(py), "r": 32, "rv": 1})
tick(4)
near_units = {rec[0] for rec in decode_records(last_frame(take(), "mv"))}
check(bool(near_units), f"remote view round the character: nothing is left out: {sorted(near_units)}")
send({"t": "focus", "x": fixed(px), "y": fixed(py), "r": 32})
seen_car.destroy()
unseen_car.destroy()
far_loco.destroy()
far_radar.destroy()

send(open_cmd(loco2))
tick(2)
gui = guis(take(), loco2)
check(gui and gui[-1]["kind"] == "train" and gui[-1]["tr"]["id"] == train.id and gui[-1]["tr"]["station"] == "Iron"
      and gui[-1]["tr"]["sched"]["records"] in ([], {}), f"a locomotive opens as a train with an empty schedule: {gui[-1:]}")
records = [{"station": "Iron", "wait_conditions": [{"type": "time", "compare_type": "or", "ticks": 300}]},
           {"rail": [fixed(px + 20), fixed(py)], "temporary": True}]
send({"t": "set_schedule", "u": loco2.unit_number, "records": records})
send({"t": "train_go", "u": loco2.unit_number, "i": 2})
send({"t": "train_mode", "u": loco2.unit_number, "auto": 0})
tick(2)
gui = guis(take(), loco2)
sched = gui[-1]["tr"]["sched"] if gui else {}
check(sched.get("records") == records and sched.get("current") == 2,
      f"set_schedule and train_go: records (a temporary stop's rail as a position) and the current one: {sched}")
check(train.manual_mode is True and gui[-1]["tr"]["manual"] == 1, "train_mode 0 is manual")
send({"t": "train_mode", "u": loco2.unit_number, "auto": 1})
send({"t": "set_schedule", "u": loco2.unit_number, "records": [{"wait_conditions": []}]})
send({"t": "set_stop", "u": loco2.unit_number, "name": "x"})
tick(2)
texts = [m["text"] for m in of_type(take(), "msg")]
check(train.manual_mode is False, "train_mode 1 is automatic")
interrupts = [{"name": "Refuel", "conditions": [{"type": "fuel_item_count_any", "compare_type": "and",
               "condition": {"first_signal": {"type": "item", "name": "coal"}, "comparator": "<", "constant": 5}}],
               "targets": [{"station": "Iron", "wait_conditions": [{"type": "inactivity", "compare_type": "and", "ticks": 120}]}],
               "inside_interrupt": False}]
send({"t": "set_interrupts", "u": loco2.unit_number, "interrupts": interrupts})
send({"t": "train_temp", "u": loco2.unit_number, "station": "Iron"})
tick(2)
gui = guis(take(), loco2)
tri = gui[-1]["tr"] if gui else {}
sched = tri.get("sched", {})
check(sched.get("interrupts") == interrupts, f"set_interrupts: the interrupts come back in the same shape: {sched.get('interrupts')}")
check(len(sched.get("records", [])) == 3 and sched["records"][sched["current"] - 1].get("temporary") is True
      and sched["records"][sched["current"] - 1]["station"] == "Iron", f"train_temp: a temporary stop after the current one, and it goes there: {sched}")
check(tri.get("stops") == ["Iron"] and tri.get("pos") == [fixed(loco2.position.x), fixed(loco2.position.y)] and tri.get("fuel") in ([], {}),
      f"a train's screen lists the force's stops, the front's position and the fuel: {tri}")
send({"t": "trains_list"})
tick(1)
got = take()
trl = [r for m in of_type(got, "trl") for r in m["l"]]
mine = [r for r in trl if r[0] == train.id]
check(mine and mine[0][3] == "Iron" and mine[0][5] == 2 and mine[0][6] == loco2.unit_number, f"trains_list: every train of the force (trl): {trl}")
send({"t": "train_mode_id", "id": train.id, "auto": 0})
tick(1)
check(train.manual_mode is True and of_type(take(), "trl"), "train_mode_id switches a train from the overview")
# Train groups: "Change train group" joins one (gc: trains in it, groups: the force's), Ctrl renames them all.
other = spawn("locomotive", px - 30, py + 30, force="player")
other.train.group = "Copper"
send({"t": "set_train_group", "u": loco2.unit_number, "g": "Copper"})
tick(2)
gui = guis(take(), loco2)
tri = gui[-1]["tr"] if gui else {}
check(train.group == "Copper" and tri.get("sched", {}).get("group") == "Copper" and tri.get("gc") == 2 and ["Copper", 2] in tri.get("groups", []),
      f"set_train_group: the train joins the group; gc counts its trains: {tri.get('gc')} {tri.get('groups')}")
send({"t": "set_train_group", "u": loco2.unit_number, "g": "Copper ore", "all": 1})
tick(2)
gui = guis(take(), loco2)
tri = gui[-1]["tr"] if gui else {}
check(train.group == "Copper ore" and other.train.group == "Copper ore" and ["Copper ore", 2] in tri.get("groups", [])
      and not any(g[0] == "Copper" for g in tri.get("groups", [])),
      f"and with all 1 renames the whole group: {tri.get('groups')}")
send({"t": "set_train_group", "u": loco2.unit_number, "g": ""})
tick(2)
gui = guis(take(), loco2)
check(train.group == "" and gui and gui[-1]["tr"].get("gc") is None, "an empty name leaves the group")
other.destroy()
send({"t": "train_mode_id", "id": train.id, "auto": 1})
tick(1)
take()
check(any(t.startswith("Can't set the schedule") for t in texts) and "That isn't a train stop" in texts,
      f"a bad schedule and a stop command on a train are refused: {texts}")

F.inventories[wagon].cargo.insert(lua.table_from({"name": "iron-plate", "count": 80}))
send(open_cmd(wagon))
tick(2)
gui = guis(take(), wagon)
check(gui and gui[-1]["kind"] == "train" and gui[-1]["inv"].get("cargo") == [["iron-plate", 80]] and len(gui[-1]["slots"]["cargo"]) == 40,
      f"a cargo wagon shows its cargo: {gui[-1:]}")
check(gui and gui[-1]["tr"].get("cargo") == [["iron-plate", 80]], "and the whole train's cargo")

send(open_cmd(stop))
tick(2)
gui = guis(take(), stop)
st = gui[-1]["stop"] if gui else {}
check(gui and gui[-1]["kind"] == "stop" and st.get("name") == "Iron" and st.get("limit") == -1 and st.get("count") == 0
      and st.get("pri") == 50 and st.get("cb", {}).get("wired") == 0 and st.get("cb", {}).get("send") == 1, f"a train stop's screen (send to train is on by default): {gui[-1:]}")
send({"t": "set_stop", "u": stop.unit_number, "pri": 80, "cb": {"en": 1, "cond": {"first_signal": {"type": "item", "name": "iron-plate"},
      "comparator": ">", "constant": 10}, "limit": 1, "limit_sig": {"type": "virtual", "name": "signal-L"}, "read": 1}})
tick(2)
st = guis(take(), stop)[-1]["stop"]
cb = st["cb"]
check(stop.train_stop_priority == 80 and st["pri"] == 80 and cb["en"] == 1 and cb["cond"]["constant"] == 10
      and cb["cond"]["first_signal"]["name"] == "iron-plate" and cb["limit"] == 1 and cb["limit_sig"]["name"] == "signal-L" and cb["read"] == 1,
      f"set_stop sets the priority and the circuit settings: {st}")
send({"t": "set_stop", "u": stop.unit_number, "name": "Copper", "limit": 2})
tick(2)
msgs = take()
gui = guis(msgs, stop)
upds = [m["e"] for m in of_type(msgs, "upd") if m["e"][0] == stop.unit_number]
check(stop.backer_name == "Copper" and stop.trains_limit == 2 and gui and gui[-1]["stop"]["limit"] == 2, "set_stop renames and limits")
check(upds and upds[-1][5].get("n") == "Copper", "and the stop's record follows")
send({"t": "set_stop", "u": stop.unit_number, "limit": -1})
tick(2)
check(stop.trains_limit is None, "limit -1 removes the limit")
stop.trains_limit = 4294967295  # how 2.1 reads a stop without a limit
tick(31)
gui = guis(take(), stop)
check(gui and gui[-1]["stop"]["limit"] == -1, f"2.1's no-limit value (uint32 max) is sent as -1: {gui[-1:]}")
stop.trains_limit = None
F["raise"]("on_entity_renamed", lua.table_from({"entity": stop}))
tick(1)
check([m for m in of_type(take(), "upd") if m["e"][0] == stop.unit_number], "a rename in the game updates the record")
send({"t": "close"})
for e in (stop, loco2, wagon, rail):
    e.destroy()
tick(2)
take()

# --- network data: pipe connections, unplugged machines, heat, wires added later --------------------
send({"t": "hello", "v": 1, "sid": "s1", "w": 1})
take()
p1 = spawn("pipe", 20.5, 25.5, force="player")
F["raise"]("script_raised_built", lua.table_from({"entity": p1}))
p2 = spawn("pipe", 21.5, 25.5, force="player")
F["raise"]("script_raised_built", lua.table_from({"entity": p2}))
tick(1)
msgs = take()
p2_add = [m["e"] for m in of_type(msgs, "add") if m["e"][0] == p2.unit_number]
p1_upd = [m["e"] for m in of_type(msgs, "upd") if m["e"][0] == p1.unit_number]
check(p2_add and p2_add[0][5].get("pc") == 8, f"a pipe's record says which sides connect (8 = west): {p2_add}")
check(p1_upd and p1_upd[-1][5].get("pc") == 2, f"building a pipe updates the pipe it joins (2 = east): {p1_upd}")
F["raise"]("script_raised_destroy", lua.table_from({"entity": p2}))
p2.destroy()
tick(2)
p1_upd = [m["e"] for m in of_type(take(), "upd") if m["e"][0] == p1.unit_number]
check(p1_upd and p1_upd[-1][5].get("pc") == 0, f"and removing it updates it again: {p1_upd}")

lamp2 = spawn("small-lamp", 22.5, 27.5, force="player")
lamp2.status = g.defines.entity_status.not_plugged_in_electric_network
# 2.1 says no_power for a consumer out of reach of every pole; it has no electric network then.
lamp3 = spawn("small-lamp", 21.5, 27.5, force="player")
lamp3.status = g.defines.entity_status.no_power
lamp3.electric_network_id = None
hot = spawn("heat-pipe", 12.5, 12.5, force="player", temperature=512.4)
pa = spawn("small-electric-pole", 24.5, 28.5, force="player")
pb = spawn("small-electric-pole", 27.5, 28.5, force="player")
for e in (pa, pb):
    F["raise"]("script_raised_built", lua.table_from({"entity": e}))
tick(1)
take()
while g.game.tick % 60:
    tick(1)
msgs = take()
pw = [v for m in of_type(msgs, "pw") for v in m["l"]]
check([lamp2.unit_number, 2] in [pw[i:i + 2] for i in range(0, len(pw), 2)], f"pw: 2 for a machine not connected to any pole: {pw}")
check([lamp3.unit_number, 2] in [pw[i:i + 2] for i in range(0, len(pw), 2)], f"pw: 2 for no_power without an electric network (2.1): {pw}")
ht = [v for m in of_type(msgs, "ht") for v in m["l"]]
check(ht == [hot.unit_number, 512], f"ht: a heat pipe's temperature: {ht}")
F.connect(pa, pb, g.defines.wire_type.copper)
tick(31)
upds = {m["e"][0]: m["e"] for m in of_type(take(), "upd")}
check(upds.get(pa.unit_number, [0] * 6)[5].get("w") == [pb.unit_number] and pb.unit_number in upds,
      f"a wire added between two existing poles updates both within half a second: {upds}")
for e in (p1, lamp2, lamp3, hot, pa, pb):
    e.destroy()
tick(2)
take()

# --- Factorio's world controls and entity windows (ui_actions.lua, entity_ui.lua) -------------------
send({"t": "hello", "v": 1, "sid": "s1", "w": 1})
take()
puppet.position = lua.table_from({"x": 0, "y": 0})
inv = puppet.get_main_inventory()

# Drop (Z): one item into the chest under the mouse, else onto the ground.
box_chest = spawn("wooden-chest", 2.5, 2.5, force="player")
puppet.insert(lua.table_from({"name": "iron-plate", "count": 10}))
plates = inv.get_item_count("iron-plate")
send({"t": "drop", "item": "iron-plate", "x": fixed(2.5), "y": fixed(2.5)})
tick(2)
check(F.inventories[box_chest]["chest"].get_item_count("iron-plate") == 1 and inv.get_item_count("iron-plate") == plates - 1,
      "Z over a chest puts one item in it")
spilled = len(F.spilled)
send({"t": "drop", "item": "iron-plate", "x": fixed(5.5), "y": fixed(-1.5)})
tick(2)
check(len(F.spilled) == spilled + 1 and inv.get_item_count("iron-plate") == plates - 2, "Z over nothing drops it on the ground")
send({"t": "drop", "item": "iron-plate", "x": fixed(40), "y": 0})
tick(2)
check(any(m["text"] == "Out of reach" for m in of_type(take(), "msg")), "dropping beyond the drop distance is refused")

# Fast transfer (Ctrl+click): a stack in, everything out; half with right click.
def target_of(e):
    return {"u": e.unit_number, "p": eid[e.name], "x": fixed(e.position.x), "y": fixed(e.position.y)}

have = inv.get_item_count("iron-plate")
send({"t": "fast", **target_of(box_chest), "item": "iron-plate", "half": 1})
tick(2)
check(F.inventories[box_chest]["chest"].get_item_count("iron-plate") == 1 + math.ceil(min(have, 100) / 2),
      "Ctrl+right click puts half of a stack in")
send({"t": "fast", **target_of(box_chest), "half": 0})
tick(2)
check(F.inventories[box_chest]["chest"].get_item_count("iron-plate") == 0 and inv.get_item_count("iron-plate") == plates - 1,
      "Ctrl+click with nothing held takes everything out")

# Copy and paste settings (Shift+right / left click): an assembler's recipe.
asm_a = spawn("assembling-machine-1", 6.5, 6.5, force="player")
asm_b = spawn("assembling-machine-1", 9.5, 6.5, force="player")
asm_a.set_recipe("iron-gear-wheel")
send({"t": "paste_settings", "f": [asm_a.unit_number, eid[asm_a.name], fixed(6.5), fixed(6.5)], **target_of(asm_b)})
tick(2)
check(asm_b.get_recipe() and asm_b.get_recipe()[0].name == "iron-gear-wheel", "paste_settings copies the recipe (2.x: recipe, quality)")

# Flip (H / V).
send({"t": "flip", **target_of(asm_b), "v": 0})
tick(2)
check(asm_b.mirroring is True and any(m["e"][0] == asm_b.unit_number for m in of_type(take(), "upd")), "flip mirrors the entity and sends its upd")

# Building a ghost (Shift+click) and a flipped entity.
send({"t": "build", "item": "assembling-machine-1", "x": fixed(14.5), "y": fixed(14.5), "d": 0, "ghost": 1})
tick(2)
adds = [m["e"] for m in of_type(take(), "add")]
check(any(a[1] == eid["entity-ghost"] and a[5].get("gh") == eid["assembling-machine-1"] for a in adds),
      f"build with ghost = 1 places a ghost, without the item and out of reach: {adds}")

# The clipboard: copy an area, see its entities, paste them as ghosts; cut marks the area too.
send({"t": "copy", "x1": fixed(5), "y1": fixed(5), "x2": fixed(11), "y2": fixed(8), "cut": 0, "bp": 0})
tick(2)
clip = of_type(take(), "clip")
check(clip and sorted(e[0] for e in clip[-1]["l"]) == [eid["assembling-machine-1"]] * 2, f"copy sends the clipboard's entities: {clip}")
# The blueprint holds map positions; the client needs them around the copy's middle.
xs = [e[1] for e in clip[-1]["l"]] if clip else [0]
ys = [e[2] for e in clip[-1]["l"]] if clip else [0]
check(clip and abs(min(xs) + max(xs)) <= 1 and abs(min(ys) + max(ys)) <= 1 and max(map(abs, xs + ys)) < 256 * 8,
      f"the clipboard's positions are around its centre, not on the map: {clip[-1]['l'] if clip else clip}")
send({"t": "paste", "x": fixed(20.5), "y": fixed(20.5), "d": 0})
tick(2)
adds = [m["e"] for m in of_type(take(), "add") if m["e"][1] == eid["entity-ghost"]]
check(len(adds) == 2, f"paste places the clipboard's ghosts: {adds}")
send({"t": "copy", "x1": fixed(5), "y1": fixed(5), "x2": fixed(11), "y2": fixed(8), "cut": 1, "bp": 0})
tick(2)
check(F.decon_marks[asm_a] is True and F.decon_marks[asm_b] is True, "cut marks the area for deconstruction")
send({"t": "copy", "x1": fixed(14), "y1": fixed(14), "x2": fixed(27), "y2": fixed(27), "cut": 1, "bp": 0})
tick(2)
dels = {d["u"] for d in of_type(take(), "del")}
check(all(a[0] in dels for a in adds), f"cut (Ctrl+X) over ghosts removes them and sends their del: {dels}")
send({"t": "copy", "x1": fixed(5), "y1": fixed(5), "x2": fixed(11), "y2": fixed(8), "cut": 0, "bp": 1})
tick(2)
bp_slots = [i for i in range(1, 81) if inv[i].valid_for_read and inv[i].name == "blueprint"]
check(len(bp_slots) >= 1 and any(m["text"] == "Blueprint added to the inventory" for m in of_type(take(), "msg")),
      "Alt+B's area becomes a blueprint in the inventory")
# to: Select new contents, into that blueprint, its name kept.
inv[bp_slots[0]].label = "Keep me"
before = len([i for i in range(1, 81) if inv[i].valid_for_read and inv[i].name == "blueprint"])
send({"t": "copy", "x1": fixed(5), "y1": fixed(5), "x2": fixed(8), "y2": fixed(8), "cut": 0, "bp": 1, "to": bp_slots[0]})
tick(2)
msgs = take()
ok = of_type(msgs, "bp_ok")
after = len([i for i in range(1, 81) if inv[i].valid_for_read and inv[i].name == "blueprint"])
check(ok and ok[-1]["i"] == bp_slots[0] and ok[-1].get("new") == 1 and after == before and inv[bp_slots[0]].label == "Keep me"
      and len(inv[bp_slots[0]].get_blueprint_entities()) >= 1, f"copy with to: the same blueprint gets the new contents, its name kept: {ok}")
send({"t": "copy", "x1": fixed(-30), "y1": fixed(-30), "x2": fixed(-29), "y2": fixed(-29), "cut": 0, "bp": 0})
tick(2)
check(any(m["text"] == "Nothing to copy there" for m in of_type(take(), "msg")), "copying an empty area says so")

# Alt-mode: recipe icons near the focus, and every filter of a filter inserter.
fins = spawn("fast-inserter", 3.5, 3.5, force="player")
fins.set_filter(2, "iron-plate")
fins.set_filter(4, "copper-plate")
fins.set_filter(5, "coal")
send({"t": "alt", "on": 1})
tick(2)
ai = of_type(take(), "ai")
check(ai and [asm_b.unit_number, "recipe", "iron-gear-wheel"] in ai[-1]["l"], f"Alt-mode lists recipe icons: {ai[-1:]}")
check(ai and [fins.unit_number, "item", "iron-plate", ["copper-plate", "coal"]] in ai[-1]["l"],
      f"a filter inserter's Alt-mode icon carries all its filters, the first even when slot 1 is empty: {[r for r in ai[-1]['l'] if r[0] == fins.unit_number] if ai else ai}")
fins.destroy()
send({"t": "alt", "on": 0})
tick(70)
check(not of_type(take(), "ai"), "Alt-mode off stops the icons")

# Chat: the client's line goes to the game's chat; players' lines come back.
F.printed = lua.table()
send({"t": "chat", "text": "hello factory"})
tick(2)
check(any("hello factory" in str(p) for p in F.printed.values()), f"chat prints in the game: {list(F.printed.values())}")
check(any(m["text"] == "hello factory" for m in of_type(take(), "chat")), "and echoes to the client")

# Statistics.
send({"t": "stats", "kind": "item", "prec": 2})
tick(2)
st = of_type(take(), "stats")
check(st and st[-1]["l"][0][0] == "iron-plate" and st[-1]["l"][0][3] == 120, f"production statistics, most first: {st[-1:]}")
send({"t": "stats", "kind": "kill", "prec": 1})
tick(2)
st = of_type(take(), "stats")
check(st and st[-1]["kind"] == "kill" and st[-1]["l"][0][0] == "small-biter", "kill statistics")
send({"t": "stats", "kind": "build", "prec": 1})
send({"t": "stats", "kind": "pollution", "prec": 3, "si": 0, "g": []})
send({"t": "stats", "kind": "item", "prec": 2, "g": ["iron-gear-wheel"]})
tick(6)  # answered under the work budget (requests.lua), a few a tick
st = of_type(take(), "stats")
build = [m for m in st if m["kind"] == "build"]
poll = [m for m in st if m["kind"] == "pollution"]
items = [m for m in st if m["kind"] == "item"]
check(build and build[-1]["l"][0][:4] == ["transport-belt", 4, 0.2, 40] and build[-1]["si"] == 1,
      f"building counts: built and removed, on the character's surface: {build[-1:]}")
check(poll and poll[-1]["si"] == 0 and {r[0] for r in poll[-1]["l"]} == {"assembling-machine-1", "grass-1"}
      and poll[-1]["gr"] and len(poll[-1]["gr"][0][1]) == 60 and len(poll[-1]["gr"][0][2]) == 60,
      f"pollution over all surfaces, with graph lines for the busiest: {poll[-1:]}")
check(items and [g[0] for g in items[-1]["gr"]] == ["iron-gear-wheel"] and items[-1]["gr"][0][1][0] == 1,
      f"graph lines for the items asked for: {items[-1:]}")

# An electric network's statistics from one of its poles, with its accumulators' storage.
epole = spawn("small-electric-pole", 30.5, 30.5, force="player")
send(dict(open_cmd(epole), t="stats", kind="electric", prec=1))
tick(2)
st = [m for m in of_type(take(), "stats") if m["kind"] == "electric"]
check(st and {r[0] for r in st[-1]["l"]} >= {"assembling-machine-1", "steam-engine"} and "si" not in st[-1]
      and st[-1].get("st") == [["accumulator", 1250000, 2500000]],
      f"electric network statistics: consumption, production and accumulator storage (st): {st[-1:]}")
check(st and st[-1].get("ef") == [500, 1000, 500, 2000, 2500000, 5000000],
      f"and the network's last update (flow_last_tick) for the summary bars: {st[-1:]}")
epole.destroy()
send({"t": "stats", "kind": "item", "prec": 9})
tick(2)
st = of_type(take(), "stats")
check(st and st[-1]["prec"] == 9 and st[-1]["l"][0][0] == "iron-plate" and st[-1]["l"][0][3] == 120,
      f"All (prec 9): rows by all-time totals: {st[-1:]}")

# The Bonuses and Permissions windows.
send({"t": "bonuses"})
send({"t": "perms"})
tick(2)
msgs = take()
bonus = of_type(msgs, "bonus")
kinds = {r[0]: r for r in bonus[-1]["l"]} if bonus else {}
check(kinds.get("inserter_stack_size_bonus", [0, 0])[1] == 1 and kinds.get("ammo_damage:bullet", [0, 0, 0])[1:] == [0.8, ["firearm-magazine"]]
      and kinds.get("turret_attack:gun-turret", [0, 0])[1] == 0.4 and "gun_speed:bullet" not in kinds,
      f"bonus: the force's bonuses that aren't zero, with their items: {bonus[-1:]}")
perms = of_type(msgs, "perms")
check(perms and perms[-1]["l"][0][0] == "Default" and len(perms[-1]["l"]) == 2, f"perms: the permission groups and their players: {perms[-1:]}")

# Factoriopedia: the index, and pages.
send({"t": "pedia_index"})
tick(3)
pidx = of_type(take(), "pidx")
entries = [r for m in pidx for r in m["l"]]
check(pidx and pidx[0]["part"] == 1 and pidx[0]["g"] and ["item", "iron-plate"] == [r for r in entries if r[1] == "iron-plate"][0][:2]
      and any(r[0] == "technology" and r[1] == "automation" for r in entries)
      and any(r[0] == "quality" and r[1] == "normal" for r in entries)
      and any(r[0] == "planet" and r[1] == "vulcanus" for r in entries)
      and not any(r[0] == "entity" and r[1] == "transport-belt" for r in entries),
      f"pidx lists items, technologies, qualities, planets; a placed entity is on its item's page: {entries[:8]}")
send({"t": "pedia", "kind": "item", "name": "transport-belt"})
send({"t": "pedia", "kind": "recipe", "name": "iron-gear-wheel"})
send({"t": "pedia", "kind": "technology", "name": "automation"})
send({"t": "pedia", "kind": "planet", "name": "nauvis"})
send({"t": "pedia", "kind": "item", "name": "no-such-item"})
tick(6)  # answered under the work budget (requests.lua), a few a tick
pages = {(m["kind"], m["name"]): m for m in of_type(take(), "pedia")}
belt = pages.get(("item", "transport-belt"), {}).get("d", {})
check(belt.get("made") == ["transport-belt"] and belt.get("entity", {}).get("type") == "transport-belt"
      and belt.get("used") == [], f"an item's page: made by, used in, the entity it builds: {belt}")
gear = pages.get(("recipe", "iron-gear-wheel"), {}).get("d", {})
check(gear.get("ing") == [["item", "iron-plate", 2]] and gear.get("unlocked") == ["automation"]
      and "assembling-machine-1" in gear.get("made_in", []) and gear.get("time") == 0.5,
      f"a recipe's page: ingredients, made in, unlocked by: {gear}")
auto = pages.get(("technology", "automation"), {}).get("d", {})
check(auto.get("effects") == [["unlock-recipe", "iron-gear-wheel", 0]] and auto.get("cost") == [["automation-science-pack", 1]],
      f"a technology's page: {auto}")
nauvis = pages.get(("planet", "nauvis"), {}).get("d", {})
check(["vulcanus", 15000] in nauvis.get("links", []) and ["solar-system-edge", 100000] in nauvis.get("links", []),
      f"a planet's page: its connections: {nauvis}")
check(pages.get(("item", "no-such-item"), {}).get("found") == 0, "an unknown page answers found 0")

# The logistic networks window (L).
F.lnets = lua.table_from({"nauvis": lua.table_from([F.make_network(7, lua.table_from([1, 2, 3, 4]),
                                                                    lua.table_from([lua.table_from(["iron-plate", 50])]))])})
send({"t": "lnets"})
send({"t": "lnet", "id": 7})
send({"t": "lnet", "id": 99})
tick(6)  # answered under the work budget (requests.lua), a few a tick
msgs = take()
nets = of_type(msgs, "lnets")
check(nets and nets[-1]["l"] == [[7, 1, "nauvis", [1, 2], [3, 4], 0, 0, 0, 0, 0, 0, ""]], f"lnets lists every network: {nets[-1:]}")
one = {m["id"]: m for m in of_type(msgs, "lnet")}
check(one.get(7, {}).get("items") == [["iron-plate", 50]] and one.get(99, {}).get("found") == 0,
      f"lnet: one network's contents, or found 0: {one}")
F.lnets = lua.table()

# Alerts: computed for the force from events and scans.
turret = spawn("gun-turret", 6.0, 6.0, force="player")
asm_off = spawn("assembling-machine-1", 9.5, 9.5, force="player")
asm_off.status = g.defines.entity_status.no_power
asm_off.electric_network_id = None
hurt = spawn("wooden-chest", 12.5, 12.5, force="player")
F["raise"]("on_entity_damaged", lua.table_from({"entity": hurt, "force": g.game.forces.enemy, "final_damage_amount": 10}))
# A turret's hit: a firing cue from the turret to its target, and blood on the biter.
take()
biter = spawn("small-biter", 8.0, 8.0, force="enemy")
turret.shooting_target = biter
F["raise"]("on_entity_damaged", lua.table_from({"entity": biter, "cause": turret, "force": g.game.forces.player, "final_damage_amount": 5}))
F["raise"]("on_entity_damaged", lua.table_from({"entity": biter, "cause": turret, "force": g.game.forces.player, "final_damage_amount": 5}))
msgs = take()
tf = of_type(msgs, "tf")
check(len(tf) == 1 and tf[0]["u"] == turret.unit_number and tf[0]["w"] == "bullet" and tf[0]["x"] == 8 * 256,
      f"a turret's hit sends one firing cue per interval, aimed at its target: {tf}")
afx = of_type(msgs, "afx")
check(len(afx) == 1 and afx[0]["fx"] == "blood" and afx[0]["u"] == biter.unit_number, f"a hit biter bleeds once per interval: {afx}")
# Turret states (turrets.lua): where each turret points, its target, shots counted from its ammo
# (or from its hits, for a laser), sent every 6 ticks while it has a target.
laser = spawn("laser-turret", 3.0, 6.0, force="player")
tank_ = spawn("tank", 2.0, 9.0, force="player")
tank_.relative_turret_orientation = 0.5
turret.get_inventory(g.defines.inventory.turret_ammo).insert(lua.table_from({"name": "firearm-magazine", "count": 10}))
turret.orientation = 0.25
tick(61)
take()
turret.get_inventory(g.defines.inventory.turret_ammo).remove(lua.table_from({"name": "firearm-magazine", "count": 2}))
F["raise"]("on_entity_damaged", lua.table_from({"entity": biter, "cause": laser, "force": g.game.forces.player, "final_damage_amount": 5}))
tick(6)
ts = {rec[0]: rec for m in of_type(take(), "ts") for rec in m["l"]}
check(ts.get(turret.unit_number) == [turret.unit_number, 250, 2, 0, 8 * 256, 8 * 256],
      f"ts: a gun turret's orientation, the shots taken from its ammo and its target: {ts}")
check(ts.get(laser.unit_number, [0, 0, 0])[2] == 1, f"ts: a laser turret's hit counts as a shot: {ts}")
turret.shooting_target = None
tick(6)
ts = {rec[0]: rec for m in of_type(take(), "ts") for rec in m["l"]}
check(turret.unit_number not in ts, f"ts: an idle turret that didn't turn isn't reported: {ts}")
tick(120)
ts = {rec[0]: rec for m in of_type(take(), "ts") for rec in m["l"]}
check(ts.get(turret.unit_number) == [turret.unit_number, 250, 0, 0], f"ts: every turret now and then, idle ones too: {ts}")
check(ts.get(tank_.unit_number) == [tank_.unit_number, 500, 0, 1], f"ts: a vehicle's turret relative to its body and its gun: {ts}")
tank_.destroy()
laser.destroy()
turret.get_inventory(g.defines.inventory.turret_ammo).remove(lua.table_from({"name": "firearm-magazine", "count": 8}))
turret.orientation = 0
F["raise"]("on_entity_died", lua.table_from({"entity": biter}))
biter.destroy()
# Enemies' attacks (`en`): a biter in range of its attack target, a spitter at range and a worm's
# shooting target are listed with the target's position; one still walking to its target and one
# wandering aren't.
take()
wall = spawn("stone-wall", 20.5, 6.5, force="player")
biter_at = spawn("small-biter", 21.2, 6.5, force="enemy")
biter_at.commandable.distraction_command = lua.table_from({"type": g.defines.command.attack, "target": wall})
biter_far = spawn("small-biter", 26.0, 6.5, force="enemy")
biter_far.commandable.distraction_command = lua.table_from({"type": g.defines.command.attack, "target": wall})
spitter = spawn("small-spitter", 20.5, 16.5, force="enemy")
spitter.commandable.command = lua.table_from({"type": g.defines.command.attack, "target": wall})
idle = spawn("small-biter", 22.0, 9.0, force="enemy")
idle.commandable.command = lua.table_from({"type": g.defines.command.wander})
worm = spawn("small-worm-turret", 18.0, 14.0, force="enemy")
worm.shooting_target = wall
tick(10)
en = of_type(take(), "en")
rows = sorted(tuple(en[-1]["l"][i:i + 3]) for i in range(0, len(en[-1]["l"]), 3)) if en else []
want = sorted((u, fixed(20.5), fixed(6.5)) for u in (biter_at.unit_number, spitter.unit_number, worm.unit_number))
check(len(en) == 1 and rows == want, f"en: attacking enemies and their targets, every 10 ticks: {en}")
for e in (biter_at, biter_far, spitter, idle, worm, wall):
    e.destroy()
tick(10)
check(not of_type(take(), "en"), "no en while nothing attacks")
doomed = spawn("wooden-chest", 13.5, 12.5, force="player")
F["raise"]("on_entity_died", lua.table_from({"entity": doomed}))
doomed.destroy()
F.construction_networks = lua.table_from([F.make_network(5, lua.table_from([0, 0, 0, 1]), lua.table())])
ghost = spawn("entity-ghost", 15.5, 12.5, force="player", inner_name="transport-belt")
F.printed = lua.table()
send({"t": "hello", "v": 1, "sid": "s1", "w": 1})  # keep-alive: the client times out after 600 ticks
# Hit again: "under attack" lasts 300 ticks, and the weapons and enemies checks above take longer.
F["raise"]("on_entity_damaged", lua.table_from({"entity": hurt, "force": g.game.forces.enemy, "final_damage_amount": 10}))
# A pass over the entities starts at most every 600 ticks: start one now, whatever ran before.
g.package.loaded["scripts.alerts"].reset()
tick(130)
al = of_type(take(), "al")
kinds = {a[0]: a for a in al[-1]["l"]} if al else {}
check("no_ammo" in kinds and kinds["no_ammo"][2][0][3] == "gun-turret" and kinds["no_ammo"][2][0][4] == turret.unit_number,
      f"a turret without ammo: {kinds.get('no_ammo')}")
check("unplugged" in kinds and kinds["unplugged"][2][0][4] == asm_off.unit_number, f"a machine out of reach of poles: {kinds.get('unplugged')}")
check("attack" in kinds and kinds["attack"][2][0][4] == hurt.unit_number, f"under attack: {kinds.get('attack')}")
check("destroyed" in kinds and kinds["destroyed"][2][0][3] == "wooden-chest", f"destroyed: {kinds.get('destroyed')}")
check("no_material" in kinds and ["transport-belt", ghost.unit_number, "transport-belt"] in [e[3:] for e in kinds["no_material"][2]],
      f"a ghost in a construction area whose network lacks its item: {kinds.get('no_material')}")
check(not any("alert scan" in str(p) or "alert pass" in str(p) for p in F.printed.values()), f"no alert scan fails: {[p for p in F.printed.values() if 'alert' in str(p)]}")
send({"t": "hello", "v": 1, "sid": "s1", "w": 1})
tick(60 * 6)
send({"t": "hello", "v": 1, "sid": "s1", "w": 1})
al = of_type(take(), "al")
kinds = {a[0]: a for a in al[-1]["l"]} if al else {}
check("attack" not in kinds and "destroyed" in kinds, "under attack ends a few seconds after the last hit; destroyed stays longer")
# An entity mined since the last pass leaves its alert at once, not when the next pass
# ends (seconds later on a big base), so no icon is left over empty ground.
turret.destroy()
tick(60)
al = of_type(take(), "al")
kinds = {a[0]: a for a in al[-1]["l"]} if al else {}
check("no_ammo" not in kinds and "unplugged" in kinds, f"a mined turret's alert goes before the next pass: {list(kinds)}")
for e in (asm_off, hurt, ghost):
    e.destroy()
F.construction_networks = lua.table()

# Inserter, splitter, power switch, turret screens; a chest's limit bar.
fins = spawn("fast-inserter", 1.5, -1.5, force="player")
send(open_cmd(fins))
tick(2)
gui = guis(take(), fins)
check(gui and gui[-1]["kind"] == "inserter" and gui[-1]["ins"]["n"] == 5 and gui[-1]["ins"]["m"] == "whitelist",
      f"an inserter opens with its filters: {gui[-1:]}")
send({"t": "set_inserter", "u": fins.unit_number, "f": ["iron-plate", "", "nonsense"], "m": "blacklist", "use": 1, "st": 2})
tick(2)
gui = guis(take(), fins)
check(gui and gui[-1]["ins"]["f"][:3] == ["iron-plate", "", ""] and gui[-1]["ins"]["m"] == "blacklist" and gui[-1]["ins"]["use"] == 1
      and gui[-1]["ins"]["st"] == 2, f"set_inserter sets filters, mode and stack size: {gui[-1:]}")
spl = spawn("splitter", -1.0, 2.5, force="player")
send(open_cmd(spl))
send({"t": "set_splitter", "u": spl.unit_number, "i": "left", "o": "right", "f": "iron-plate"})
tick(2)
gui = guis(take(), spl)
check(gui and gui[-1]["spl"] == {"i": "left", "o": "right", "f": "iron-plate"}, f"set_splitter: {gui[-1:]}")
sw = spawn("power-switch", -3.0, -1.0, force="player")
send(open_cmd(sw))
send({"t": "set_switch", "u": sw.unit_number, "on": 1})
tick(2)
gui = guis(take(), sw)
check(gui and gui[-1]["kind"] == "switch" and gui[-1]["sw"] == 1, f"a power switch turns on: {gui[-1:]}")
turret = spawn("gun-turret", 4.0, -2.0, force="player")
send(open_cmd(turret))
puppet.insert(lua.table_from({"name": "firearm-magazine", "count": 5}))
tick(2)
gui = guis(take(), turret)
check(gui and gui[-1]["kind"] == "turret" and "turret_ammo" in gui[-1]["slots"], f"a turret shows its ammo slot: {gui[-1:]}")
send(open_cmd(box_chest))
send({"t": "set_bar", "u": box_chest.unit_number, "n": 4})
tick(2)
gui = guis(take(), box_chest)
check(gui and gui[-1].get("bar") == 4, f"a chest's limit bar: {gui[-1:]}")
send({"t": "set_inserter", "u": box_chest.unit_number, "st": 3})
tick(2)
check(any(m["text"] == "That isn't an inserter" for m in of_type(take(), "msg")), "inserter settings on a chest are refused")
send({"t": "inv_filter", "i": 7, "item": "iron-plate"})
tick(2)
sl = of_type(take(), "slots")
check(sl and sl[-1].get("fl") == [[7, "iron-plate"]], f"inv_filter sets a main inventory slot filter: {sl[-1:]}")
send({"t": "inv_filter", "i": 7, "item": ""})
tick(2)
sl = of_type(take(), "slots")
check(sl and "fl" not in sl[-1], "and an empty item clears it")
send({"t": "close"})
for e in (box_chest, asm_a, asm_b, fins, spl, sw, turret):
    e.destroy()
for e in list(F.surface.entities.values()):
    if e.type == "entity-ghost":
        e.destroy()
tick(2)
take()
# --- logistics: chests, roboports, the character's requests, networks, robot cargo -----------------
send({"t": "hello", "v": 1, "sid": "s1", "w": 1})
tick(2)
take()
send({"t": "set_char_requests", "l": [["iron-plate", 1, -1]]})
tick(1)
msgs = take()
check(not of_type(msgs, "clog") and any(m["text"].startswith("No logistic requests yet") for m in of_type(msgs, "msg")),
      f"set_char_requests before the research says so: {msgs}")
g.game.forces.player.character_logistic_requests = True
tick(30)
clog = of_type(take(), "clog")
check(clog and clog[-1]["on"] == 1 and clog[-1]["trash"] == 0 and clog[-1]["l"] in ([], {}),
      f"clog: the character's requests arrive once researched: {clog}")
send({"t": "set_char_requests", "l": [["iron-plate", 100, 200], ["no-such-item", 1, 1]], "trash": 1})
tick(1)
clog = of_type(take(), "clog")
check(clog and clog[-1]["l"] == [["iron-plate", 100, 200]] and clog[-1]["trash"] == 1,
      f"set_char_requests sets requests (unknown items left out) and auto-trash: {clog}")
send({"t": "set_char_requests", "on": 0})
tick(1)
clog = of_type(take(), "clog")
check(clog and clog[-1]["on"] == 0 and clog[-1]["l"] == [["iron-plate", 100, 200]], "and turns them off, keeping them")
check(clog and [s_["f"] for s_ in clog[-1].get("sec", [])] == [[["iron-plate", "normal", 100, 200, "", -1]]],
      f"clog.sec: the character's sections one by one: {clog[-1:]}")
send({"t": "set_section", "u": 0, "i": 0, "g": "Mall"})
tick(1)
clog = of_type(take(), "clog")
check(clog and [s_["g"] for s_ in clog[-1]["sec"]] == ["", "Mall"] and isinstance(clog[-1].get("lgs"), (list, dict)),
      f"set_section u=0 adds a section to the character, in a group: {clog[-1:]}")
send({"t": "set_section", "u": 0, "i": 2, "on": 0, "f": [["iron-gear-wheel", "normal", 50, -1, "", -1]]})
tick(1)
clog = of_type(take(), "clog")
check(clog and clog[-1]["sec"][1]["on"] == 0 and clog[-1]["sec"][1]["f"][0][:3] == ["iron-gear-wheel", "normal", 50],
      f"set_section u=0 turns a character section off and sets its requests: {clog[-1:]}")
send({"t": "set_section", "u": 0, "i": 2, "del": 1})
tick(1)
clog = of_type(take(), "clog")
check(clog and len(clog[-1]["sec"]) == 1, f"set_section u=0 del removes the character's section: {clog[-1:]}")
send({"t": "set_char_color", "c": [10, 200, 30]})
tick(1)
ccol = of_type(take(), "ccol")
pc = g.storage.f3d.puppet.color
check(ccol and ccol[-1]["c"] == [10, 200, 30] and abs(pc.g - 200 / 255) < 1e-6,
      f"set_char_color sets the character's colour and ccol says so: {ccol}")

F.network = F.make_network(7, lua.table_from([3, 5, 1, 2]), lua.table_from([lua.table_from(["iron-plate", 50]), lua.table_from(["copper-plate", 80])]))
px, py = g.storage.f3d.puppet.position.x, g.storage.f3d.puppet.position.y
req = spawn("requester-chest", px + 2.5, py + 1.5, force="player")
sto = spawn("storage-chest", px + 3.5, py + 1.5, force="player")
port = spawn("roboport", px + 6.0, py + 3.0, force="player")
robot = spawn("logistic-robot", px + 1.5, py - 1.5, force="player")
robot.get_inventory(g.defines.inventory.robot_cargo).insert(lua.table_from({"name": "iron-plate", "count": 4}))
while g.game.tick % 60:
    tick(1)
msgs = take()
ln = of_type(msgs, "ln")
check(ln and ln[-1]["id"] == 7 and ln[-1]["log"] == [3, 5] and ln[-1]["con"] == [1, 2], f"ln: the network the character stands in: {ln[-1:]}")
rc = [v for m in of_type(msgs, "rc") for v in m["l"]]
check([robot.unit_number, iid["iron-plate"], 4] in [rc[i:i + 3] for i in range(0, len(rc), 3)], f"rc: what a robot near the focus carries: {rc}")

send(open_cmd(req))
send({"t": "set_requests", "u": req.unit_number, "l": [["iron-gear-wheel", 10, -1], ["wood", 5, 20]]})
tick(2)
gui = guis(take(), req)
lg = gui[-1].get("lg", {}) if gui else {}
check(lg.get("mode") == "requester" and lg.get("requests") == [["iron-gear-wheel", 10, -1], ["wood", 5, 20]],
      f"a requester chest's screen: its requests, set by set_requests: {lg}")
check(lg.get("net", {}).get("items") == [["copper-plate", 80], ["iron-plate", 50]] and "trash" in gui[-1]["slots"],
      f"and its network's contents (most first) and its trash slots: {gui[-1:]}")
lc = gui[-1].get("lc", {}) if gui else {}
check(lc.get("tu") == 0 and lc.get("rb") == 0 and lc.get("sec", [{}])[0].get("f", [[None]])[0][::2] == ["iron-gear-wheel", 10, ""],
      f"lc: the requester's sections, trash unrequested and request from buffers (machine_info.lua): {lc}")
send({"t": "set_chest_logistics", "u": req.unit_number, "tu": 1, "rb": 1})
send({"t": "set_section", "u": req.unit_number, "i": 0})
tick(2)
gui = guis(take(), req)
lc = gui[-1].get("lc", {}) if gui else {}
check(lc.get("tu") == 1 and lc.get("rb") == 1 and len(lc.get("sec", [])) == 2,
      f"set_chest_logistics ticks both boxes; set_section adds a section to a chest: {lc}")
send({"t": "set_section", "u": req.unit_number, "i": 2, "g": "Bus"})
tick(2)
gui = guis(take(), req)
lc = gui[-1].get("lc", {}) if gui else {}
check([sec.get("g") for sec in lc.get("sec", [])] == ["", "Bus"], f"set_section g puts a section in a logistic group: {lc}")
send({"t": "close"})
send(open_cmd(req))
tick(2)
gui = guis(take(), req)
check(gui and "Bus" in gui[0].get("lgs", []), f"lgs: the force's logistic groups ride with the first message: {gui[:1]}")
send(open_cmd(sto))
send({"t": "set_storage_filter", "u": sto.unit_number, "item": "iron-plate"})
send({"t": "set_requests", "u": sto.unit_number, "l": [["wood", 1, -1]]})
tick(2)
msgs = take()
gui = guis(msgs, sto)
check(gui and gui[-1]["lg"]["mode"] == "storage" and gui[-1]["lg"]["filter"] == "iron-plate", f"a storage chest's filter is set and shown: {gui[-1:]}")
check(any(m["text"] == "That chest doesn't take requests" for m in of_type(msgs, "msg")), "a storage chest takes no requests")
send({"t": "set_storage_filter", "u": sto.unit_number, "item": ""})
tick(2)
gui = guis(take(), sto)
check(gui and gui[-1]["lg"]["filter"] == "", "and cleared")
send(open_cmd(port))
tick(2)
gui = guis(take(), port)
check(gui and gui[-1]["kind"] == "roboport" and {"robots", "repair"} <= set(gui[-1]["slots"]) and gui[-1]["lg"]["net"]["id"] == 7,
      f"a roboport's screen: robots, repair packs and its network: {gui[-1:]}")
send({"t": "close"})
for e in (req, sto, port, robot):
    e.destroy()
F.network = None
tick(60)
ln = of_type(take(), "ln")
check(ln and ln[-1]["id"] == 0 and "log" not in ln[-1], f"ln: id 0 outside any network: {ln[-1:]}")

# --- qualities, for cycling the one to build with ---------------------------------------------------
lua.eval("function() storage.f3d.techs_dirty = true end")()
tick(2)  # reliable: out with the next tick's flush
quals = of_type(take(), "quals")
check(quals and quals[-1]["l"] == [["normal", 0, 1, "ffffff"], ["uncommon", 1, 1, "ffffff"], ["rare", 2, 1, "ffffff"],
                                  ["epic", 3, 0, "ffffff"], ["legendary", 5, 0, "ffffff"]],
      f"quals: the qualities by level, which are unlocked, their colours; hidden ones left out: {quals[-1:]}")

# --- two clients on one server ---------------------------------------------------------------------
PORT_B = CLIENT_PORT + 1


def take_by_port():
    """Everything sent, by port; reliable numbering checked per client."""
    by, seq = {}, {}
    for item in F.take_sent().values():
        port, data = item[1], item[2]
        for msg in protocol.split_datagram(data):
            for problem in protocol.problems(msg):
                check(False, f"protocol: {problem}")
            if "r" in msg:
                if msg["t"] == "welcome":
                    seq[port] = msg["r"]
                elif port in seq:
                    check(msg["r"] == seq[port], f"reliable gap on port {port}: {msg['r']} after {seq[port] - 1}")
                seq[port] = msg["r"] + 1
            by.setdefault(port, []).append(msg)
    return by


take()
send({"t": "hello", "v": 1, "sid": "s1", "w": 1})
send({"t": "hello", "v": 1, "sid": "b", "w": 0, "z": 1}, port=PORT_B)
tick(3)
by = take_by_port()
first, second = by.get(CLIENT_PORT, []), by.get(PORT_B, [])
a_unit = g.storage.f3d.puppet.unit_number
welcome_b = of_type(second, "welcome")
check(welcome_b and not of_type(first, "welcome") and welcome_b[0]["u"] != a_unit and of_type(second, "protos"),
      f"two clients: the second gets a welcome, prototypes and a character of its own; the first goes on: {welcome_b}")
b_state = g.storage.f3d_extra[PORT_B]
check(b_state and b_state.puppet and b_state.puppet.unit_number == welcome_b[0]["u"], "and its state lives in storage.f3d_extra by port")
send({"t": "sub", "c": [[0, 0]]}, port=PORT_B)
send({"t": "walk", "d": 4}, port=PORT_B)
tick(4)
by = take_by_port()
check(of_type(by.get(PORT_B, []), "chunk") and not of_type(by.get(CLIENT_PORT, []), "chunk"),
      "each client gets the chunks it subscribed to")
check(b_state.puppet.walking_state.walking and not g.storage.f3d.puppet.walking_state.walking,
      "each client walks its own character")
check(any(m["u"] == a_unit for m in of_type(by.get(CLIENT_PORT, []), "me")) and any(m["u"] == b_state.puppet.unit_number for m in of_type(by.get(PORT_B, []), "me")),
      "and each hears about its own character in `me`")
made = spawn("wooden-chest", 3.5, 3.5, force="player")
F["raise"]("script_raised_built", lua.table_from({"entity": made}))
send({"t": "hello", "v": 1, "sid": "s1", "w": 1})
send({"t": "hello", "v": 1, "sid": "b", "w": 1, "z": 1}, port=PORT_B)
tick(2)
by = take_by_port()
adds = {port: [m for m in of_type(msgs, "add") if m["e"][0] == made.unit_number] for port, msgs in by.items()}
check(adds.get(CLIENT_PORT) and adds.get(PORT_B), f"a building event reaches both clients: {sorted(adds)}")
b_unit = b_state.puppet.unit_number
send({"t": "bye"}, port=PORT_B)
tick(1)
check(len(g.storage.f3d_extra) == 0 and g.storage.f3d.client and g.storage.f3d.client.port == CLIENT_PORT,
      "bye drops only the second client")
send({"t": "hello", "v": 1, "sid": "b", "w": 0}, port=PORT_B)
tick(3)
by = take_by_port()
check(of_type(by.get(PORT_B, []), "welcome") and of_type(by[PORT_B], "welcome")[0]["u"] == b_unit,
      "the same client coming back gets its character back")
send({"t": "bye"}, port=PORT_B)
old_subs = [[int(v) for v in k.split(",")] for k in g.storage.f3d.subs.keys()]
old_focus = {"x": int(g.storage.f3d.focus.x * 256), "y": int(g.storage.f3d.focus.y * 256), "r": int(g.storage.f3d.focus.r)}
F.multiplayer = False
send({"t": "hello", "v": 1, "sid": "c", "w": 0}, port=PORT_B + 1)
tick(1)
check(len(g.storage.f3d_extra) == 0 and g.storage.f3d.client.port == PORT_B + 1,
      "in single-player a new port takes over instead of adding a client (the game plays one character)")
send({"t": "bye"}, port=PORT_B + 1)
tick(1)
F.multiplayer = True
take_by_port()
send({"t": "hello", "v": 1, "sid": "s1", "w": 0})  # the first client again, as the tests below expect
tick(3)
send({"t": "sub", "c": old_subs})
send({"t": "focus", **old_focus})
tick(30)
take()
made.destroy()

# --- the other planets: demolishers, lightning, Gleba, Aquilo, travel --------------------------------
send({"t": "hello", "v": 1, "sid": "s1", "w": 1})
tick(2)
take()
px, py = g.storage.f3d.puppet.position.x, g.storage.f3d.puppet.position.y
demo = F.add_segmented_unit(F.surface, "small-demolisher", "small-demolisher-segment",
                            lua.table_from([lua.table_from([px + 6, py, 0.25]), lua.table_from([px + 11, py, 0.25])]))
tick(2)
seg = [r for m in of_type(take(), "seg") for r in m["l"] if r[0] == demo.unit_number]
check(seg and seg[-1][1] == eid["small-demolisher"] and seg[-1][2] == [eid["small-demolisher-segment"], fixed(px + 6), fixed(py), 250,
                                                                     eid["small-demolisher-segment"], fixed(px + 11), fixed(py), 250],
      f"seg: a demolisher's segments in order, with their orientation: {seg[-1:]}")
F.surface.segmented = lua.table_from([])
tick(2)
seg = of_type(take(), "seg")
check(seg and seg[-1]["l"] in ([], {}), "and an empty seg once it is gone")

# A lightning entity stands where its bolt starts, 25 tiles up (y) and up to 15 aside (x) of
# where it strikes: one pulled onto the rod, one striking the ground, and one far from the focus.
rod = spawn("lightning-rod", px + 10.5, py + 10.5, force="player")
bolt = spawn("lightning", px + 14.5, py + 10.5 - 24)
stray = spawn("lightning", px - 18.5, py - 12.5 - 23)
far = spawn("lightning", px + 120.5, py - 25)
# No lightning seen yet: the search idles at every 12th tick.
tick(12)
lt = [r for m in of_type(take(), "lt") for r in m["l"]]
check(sorted(lt) == sorted([[fixed(px + 10.5), fixed(py + 10.5), 1], [fixed(px - 18.5), fixed(py - 10.5), 0]]),
      f"lt: strikes near the focus on the ground below the bolt, or on the rod that caught them: {lt}")
# Lightning was seen, so the next strike is looked for at the full rate (every 3 ticks).
second = spawn("lightning", px - 4.5, py - 30.5)
while g.game.tick % 3:
    tick(1)
tick(3)
lt = [r for m in of_type(take(), "lt") for r in m["l"]]
check(lt == [[fixed(px - 4.5), fixed(py - 5.5), 0]], f"lt: once lightning was seen, strikes are looked for every 3 ticks again: {lt}")
second.destroy()
tick(3)
check(not of_type(take(), "lt"), "each strike is sent once")
for e in (bolt, stray, far):
    e.destroy()

plant = spawn("yumako-tree", px + 4.5, py + 4.5, force="player", tick_grown=g.game.tick + 300)
tower = spawn("agricultural-tower", px + 2.5, py + 6.5, force="player")
tower.owned_plants = lua.table_from([plant])
pod = spawn("small-stomper-pentapod", px + 8.0, py - 6.0, force="enemy")
nest = spawn("gleba-spawner", px + 14.5, py - 8.5, force="enemy")
nest.units = lua.table_from([pod])
cold = spawn("inserter", px - 3.5, py + 3.5, force="player", frozen=True)
F["raise"]("on_tower_planted_seed", lua.table_from({"tower": tower, "plant": plant, "seed": lua.table_from({"name": "yumako-seed"})}))
tick(1)
check([m for m in of_type(take(), "add") if m["e"][2:4] == [fixed(px + 4.5), fixed(py + 4.5)]], "a plant the tower planted is added to the world")
while g.game.tick % 60:
    tick(1)
msgs = take()
pg = [v for m in of_type(msgs, "pg") for v in m["l"]]
groups = [pg[i:i + 4] for i in range(0, len(pg), 4)]
mine = [gr for gr in groups if gr[1:3] == [fixed(px + 4.5), fixed(py + 4.5)]]
check(mine and 400 <= mine[0][3] <= 600, f"pg: a plant halfway grown: {mine}")
sp = [v for m in of_type(msgs, "sp") for v in m["l"]]
check([nest.unit_number, 1] in [sp[i:i + 2] for i in range(0, len(sp), 2)], f"sp: a spawner and its units out: {sp}")
fz = [v for m in of_type(msgs, "fz") for v in m["l"]]
check(cold.unit_number in fz, f"fz: a frozen inserter: {fz}")
tick(4)
legs = [r for m in of_type(take(), "legs") for r in m["l"] if r[0] == pod.unit_number]
check(legs and len(legs[-1][1]) == 10 and legs[-1][1][:2] == [fixed(px + 8.0 - 3.7), fixed(py - 6.0 - 5.1)],
      f"legs: a pentapod's five feet, from the spider-leg entities after it (no get_spider_legs on a spider unit): {legs[-1:]}")
send(open_cmd(tower))
tick(2)
gui = guis(take(), tower)
check(gui and gui[-1].get("ag") == {"plants": 1, "ready": 0}, f"an agricultural tower's screen counts its plants: {gui[-1:]}")
send({"t": "close"})

puppet = g.storage.f3d.puppet
puppet.get_main_inventory().insert(lua.table_from({"name": "yumako", "count": 5}))
lua.eval("""function(inv)
  for i = 1, #inv do
    if inv[i].valid_for_read and inv[i].name == "yumako" then inv[i].spoil_percent = 0.25 end
  end
end""")(puppet.get_main_inventory())
tick(31)
slots = [m["l"]["main"] for m in of_type(take(), "slots")]
check(slots and ["yumako", 5, "normal", 750] in slots[-1], f"slots: a spoiling stack carries its freshness: {[s for s in (slots[-1] if slots else []) if s]}")
belt2 = spawn("transport-belt", px + 1.5, py + 2.5, force="player")
F.put_on_belt(belt2, 1, "yumako", 0.5, 4242, 0.5)
tick(12)
bf = [v for m in of_type(take(), "bf") for v in m["l"]]
check([4242, 500] in [bf[i:i + 2] for i in range(0, len(bf), 2)], f"bf: freshness of spoiling items on belts: {bf[:8]}")

silo = spawn("wooden-chest", px + 3.5, py - 3.5, force="player")
F["raise"]("on_rocket_launch_ordered", lua.table_from({"rocket": silo, "rocket_silo": silo}))
cargo = spawn("cargo-pod", px - 2.0, py - 2.0, force="player")
# No pod seen yet: the search idles at every 30th tick.
tick(1)
while g.game.tick % 30:
    tick(1)
msgs = take()
rk = of_type(msgs, "rk")
check(rk and rk[-1]["u"] == silo.unit_number and rk[-1]["s"] == "nauvis", f"rk: a rocket launch at a silo: {rk}")
cp = [r for m in of_type(msgs, "cp") for r in m["l"] if r[0] == cargo.unit_number]
check(cp and cp[-1][1:] == ["awaiting_launch", "invalid", ""], f"cp: a cargo pod near the focus: {cp}")
send({"t": "land"})
tick(1)
check(any("Land from a platform" in m["text"] for m in of_type(take(), "msg")), "land on a planet is refused")
for e in (rod, plant, tower, pod, nest, cold, belt2, silo, cargo):
    e.destroy()
tick(61)
take()

# --- strangers, junk, resync ---------------------------------------------------------------------
F.packet("not json at all", CLIENT_PORT)
send({"t": "walk", "d": 0}, port=40000)
send({"t": "nonsense"})
tick(2)
check(not puppet.walking_state.walking, "commands from another port are ignored")
take()
send({"t": "resync"})
tick(10)
msgs = take()
check({(m["cx"], m["cy"]) for m in of_type(msgs, "chunk")} == {(0, 0), (1, 0), (9, 9)}, "resync resends subscribed chunks")
send({"t": "resync", "full": 0, "c": [[1, 0], [5, 5], "junk"]})
tick(10)
msgs = take()
resent = [(m["cx"], m["cy"]) for m in of_type(msgs, "chunk")]
# The mod also refreshes one subscribed chunk every 5 s, which may land in these ticks.
check((1, 0) in resent and (5, 5) not in resent and len(resent) <= 2,
      f"resync with a list resends those subscribed chunks, without waiting for the cooldown: {resent}")

# --- /f3d-status from RCON or the server console -------------------------------------------------
F.printed = lua.table()
F.command(lua.table_from({"name": "f3d-status"}))
printed = list(F.printed.values())
check(any(p.startswith("RCON [Zenith] client on port") for p in printed), "/f3d-status answers RCON")
check(any(p.startswith("STDOUT [Zenith] character at") for p in printed), "/f3d-status prints to the server console")
check(any("profiling off" in str(p) for p in printed), "/f3d-status says profiling is off")
F.printed = lua.table()
F.commands["f3d-profile"](lua.table_from({"name": "f3d-profile"}))
before = F.profilers
send({"t": "hello", "v": 1, "sid": "s1", "w": 1})
tick(601)
F.printed = lua.table()
F.command(lua.table_from({"name": "f3d-status"}))
lines = [p for p in F.printed.values()]
check(F.profilers > before and any("RCON" in str(p) for p in lines) and len(lines) > 12,
      f"with /f3d-profile on, /f3d-status reports a time for every module ({F.profilers - before} profilers, {len(lines)} lines)")
F.commands["f3d-profile"](lua.table_from({"name": "f3d-profile"}))
take()

# --- space platforms -------------------------------------------------------------------------------
def platform_console(parameter):
    before = len(F.printed)
    F.commands["f3d-platform"](lua.table_from({"name": "f3d-platform", "parameter": parameter}))
    return [str(p) for p in list(F.printed.values())[before:]]


def next_plat():
    """Ticks to the next platform message and returns it."""
    tick(1)
    while g.game.tick % 60:
        tick(1)
    plats = of_type(take(), "plat")
    return plats[-1] if plats else {}


def texts(msgs):
    return [m["text"] for m in of_type(msgs, "msg")]


send({"t": "hello", "v": 1, "sid": "s1", "w": 1})
tick(1)
take()
puppet = g.storage.f3d.puppet
lines = platform_console("new")
check(any("platform 1 (Platform 1) built in orbit of nauvis" in l for l in lines), f"/f3d-platform new builds a platform: {lines}")
plat = g.game.forces.player.platforms[1]
check(plat.hub is not None and plat.surface.name == "platform-1", "with the starter pack applied it has a hub and a surface")
pm = next_plat()
rec = (pm.get("l") or [{}])[0]
check(pm.get("on") == 0 and pm.get("here") == "nauvis" and pm.get("dest") == ["nauvis", "vulcanus"],
      f"plat: on a planet, with the unlocked destinations: {pm}")
check(rec.get("i") == 1 and rec.get("st") == "paused" and rec.get("loc") == "nauvis" and rec.get("hub") == plat.hub.unit_number
      and rec.get("pa") == 1 and "from" not in rec and "sch" not in rec, f"plat: a new platform waits in orbit, paused: {rec}")
check(rec.get("w") == 1250000, f"plat: the platform's mass (weight, kg) for the remote view's info panel: {rec}")

# The remote view looks at the platform from Nauvis: its world is streamed (surface, view = 1),
# world-changing commands wait, and si 0 goes back to the character's surface.
send({"t": "view", "si": plat.surface.index, "x": 3 * 256, "y": 4 * 256})
tick(2)
msgs = take()
vs = of_type(msgs, "surface")
check(vs and vs[0]["si"] == plat.surface.index and vs[0].get("view") == 1 and vs[0]["x"] == 3 * 256 and puppet.surface.name == "nauvis",
      f"view: the platform's world is streamed while the character stays on Nauvis: {vs}")
# H25: a full resync (lost packets) keeps the remote view on that surface instead of dropping back
# to the character's planet.
lua.eval("function() storage.f3d.resync_tick = -1000000 end")()
send({"t": "resync", "full": 1})
tick(2)
take()
check(lua.eval("function() return storage.f3d.view_si end")() == plat.surface.index,
      "a full resync keeps the remote view of another surface (H25)")
# From the remote view, building on that surface places a ghost there (never the item),
# while what needs the character's hands still waits.
send({"t": "sub", "c": [[0, 0]]})
tick(2)
take()
send({"t": "build", "item": "wooden-chest", "x": 5 * 256 + 128, "y": 2 * 256 + 128, "d": 0})
tick(1)
msgs = take()
ghosts = [e for e in plat.surface.entities.values() if e.name == "entity-ghost" and e.ghost_name == "wooden-chest"]
check(len(ghosts) == 1 and not any(e.name == "wooden-chest" for e in plat.surface.entities.values())
      and not any(e.name == "entity-ghost" and e.ghost_name == "wooden-chest" for e in F.surface.entities.values()),
      f"view: building from the remote view puts a ghost on the shown surface: {texts(msgs)}")
check(any(m["e"][1] == eid["entity-ghost"] for m in of_type(msgs, "add")), "view: the ghost reaches the client")
# F6: the platform is uncharted (a headless server charts nothing), so the script check stands in
# for the manual one, but not over empty space or against the platform's conditions: those ghosts
# would never be built.
send({"t": "build", "item": "wooden-chest", "x": 10 * 256 + 128, "y": 2 * 256 + 128, "d": 0})
puppet.insert(lua.table_from({"name": "burner-inserter", "count": 1}))
plat.surface.props.gravity = 0  # a platform's, as in the game
send({"t": "build", "item": "burner-inserter", "x": 6 * 256 + 128, "y": 2 * 256 + 128, "d": 0})
tick(1)
plat.surface.props.gravity = 10
said = texts(take())
ghost_names = sorted(e.ghost_name for e in plat.surface.entities.values() if e.name == "entity-ghost")
check(ghost_names == ["wooden-chest"] and "Can't place that there" in said and any("gravity" in t for t in said),
      f"view: no ghost on empty space, nor one the platform's gravity forbids (F6): {ghost_names} {said}")
# F6: modules from the remote view: a ghost keeps them in its insert plan.
send({"t": "build", "item": "assembling-machine-1", "x": 5 * 256 + 128, "y": -5 * 256 - 128, "d": 0})
tick(1)
take()
am_ghost = next((e for e in plat.surface.entities.values() if e.name == "entity-ghost" and e.ghost_name == "assembling-machine-1"), None)
check(am_ghost is not None, "view: an assembler's ghost on the platform's foundation")
mod_at = {"u": am_ghost.unit_number, "p": eid["entity-ghost"], "x": fixed(am_ghost.position.x), "y": fixed(am_ghost.position.y)} if am_ghost else {}
for _ in range(3):
    send({"t": "modreq", "item": "speed-module", **mod_at})
tick(1)
said = texts(take())
plan = [(p.id.name, at.inventory, at.stack) for p in am_ghost.insert_plan.values() for at in p["items"].in_inventory.values()] if am_ghost else []
check(sorted(plan) == [("speed-module", 25, 0), ("speed-module", 25, 1)] and "Module requested: 2 of 2 slots" in said
      and "The module slots are full" in said, f"modreq: a ghost's insert plan gets a module per slot, no more (F6): {plan} {said}")
send({"t": "modreq", "item": "wooden-chest", **mod_at})
send({"t": "modreq", "clr": 1, "s": 1, **mod_at})
tick(1)
said = texts(take())
plan = [(p.id.name, at.stack) for p in am_ghost.insert_plan.values() for at in p["items"].in_inventory.values()] if am_ghost else []
check(plan == [("speed-module", 1)] and "That isn't a module" in said, f"modreq: clr takes a slot's request back; no chests in module slots: {plan} {said}")
# The platform's map past its generated chunks is empty, not an error (F6: get_tile there is invalid).
send({"t": "map", "si": plat.surface.index, "cx1": 10, "cy1": 10, "res": 8})
tick(2)
msgs = take()
charts = of_type(msgs, "chart")
check(charts and charts[0]["n"] == 0 and not any("Map error" in t for t in texts(msgs)),
      f"map: an ungenerated chunk of a platform charts as unknown: {charts} {texts(msgs)}")
send({"t": "mine", "u": 0, "p": 0, "x": 2 * 256, "y": 2 * 256})
tick(1)
check(any("another surface" in x for x in texts(take())), "view: mining by hand waits while another surface is shown")
check(g.storage.f3d.act_si is None, "view: the surface override ends with the command")
send({"t": "view", "si": 0})
tick(2)
vs = of_type(take(), "surface")
check(vs and vs[0]["surface"] == "nauvis" and "view" not in vs[0], f"view 0: back to the character's surface: {vs}")

send({"t": "plat_board", "i": 1})
tick(2)
msgs = take()
surf = of_type(msgs, "surface")
check(surf and surf[0]["surface"] == "platform-1" and surf[0]["pf"] == 1 and "planet" not in surf[0] and surf[0]["si"] == plat.surface.index,
      f"plat_board: the character moves to the platform and the client is told (surface): {surf}")
check(puppet.surface.name == "platform-1" and not of_type(msgs, "welcome"), "a surface change is not a new handshake")
check(len(list(g.storage.f3d.subs.items())) == 0, "the old surface's subscriptions are dropped")
send({"t": "sub", "c": [[0, 0], [-1, -1]]})
tick(6)
msgs = take()
tids = {rec[1]: rec[0] for rec in tprotos}
chunk00 = [m for m in of_type(msgs, "chunk") if (m["cx"], m["cy"]) == (0, 0)]
tile_ids = set(chunk00[0]["tiles"][0::2]) if chunk00 else set()
check(tile_ids == {tids["space-platform-foundation"], tids["empty-space"]}, f"a platform chunk: foundation and empty space: {tile_ids}")
hub_recs = [e for m in of_type(msgs, "ents") for e in m["e"] if e[1] == {r[1]: r[0] for r in protos}["space-platform-hub"]]
check(len(hub_recs) == 1 and hub_recs[0][0] == plat.hub.unit_number, f"the hub is in the platform's snapshot: {hub_recs}")
pm = next_plat()
check(pm.get("on") == 1 and "here" not in pm, f"plat: on the platform, on names it: {pm}")

send({"t": "plat_go", "i": 1, "to": "vulcanus"})
send({"t": "plat_go", "i": 1, "to": "aquilo"})
send({"t": "plat_go", "i": 7, "to": "vulcanus"})
tick(1)
msgs = take()
check("Can't travel to aquilo" in texts(msgs) and "No such platform" in texts(msgs), f"plat_go refuses unknown places and platforms: {texts(msgs)}")
rec = next_plat()["l"][0]
check(rec.get("sch") == {"c": 1, "l": ["vulcanus"]} and rec.get("pa") == 0 and rec.get("st") == "waiting_at_station",
      f"plat_go: a one-stop schedule and unpaused: {rec}")
# H7: stopped, a platform names where its schedule takes it next.
check(rec.get("loc") == "nauvis" and rec.get("nx") == "vulcanus", f"plat: waiting at nauvis, the next stop: {rec}")
pdata = F.platform_data[plat]
pdata.schedule = lua.table_from({"current": 2, "records": lua.table_from([lua.table_from({"station": "vulcanus"}),
                                                                          lua.table_from({"station": "nauvis"})])})
rec = next_plat()["l"][0]
check(rec.get("nx") == "vulcanus", f"plat: waiting at its current stop, the next record: {rec}")
pdata.schedule = lua.table_from({"current": 1, "records": lua.table_from([lua.table_from({"station": "nauvis"})])})
rec = next_plat()["l"][0]
check("nx" not in rec, f"plat: a schedule of only here has no next stop: {rec}")
# Done at its stop, the schedule already on the next one (Factorio's waiting_for_departure, while
# cargo is still on its way): that one is where it goes.
pdata.schedule = lua.table_from({"current": 2, "records": lua.table_from([lua.table_from({"station": "nauvis"}),
                                                                          lua.table_from({"station": "vulcanus"})])})
rec = next_plat()["l"][0]
check(rec.get("loc") == "nauvis" and rec.get("nx") == "vulcanus" and "to" not in rec,
      f"plat: about to leave, the current record is the next stop: {rec}")
pdata.schedule = lua.table_from({"current": 1, "records": lua.table_from([lua.table_from({"station": "vulcanus"})])})
F.platform_travel(plat, "nauvis-vulcanus", 0.25, 2.5)
rec = next_plat()["l"][0]
check(rec.get("from") == "nauvis" and rec.get("to") == "vulcanus" and rec.get("d") == 250 and rec.get("len") == 15000
      and rec.get("sp") == 150 and rec.get("st") == "on_the_path" and "loc" not in rec,
      f"plat: travelling, with the way done in thousandths and the speed in km/s: {rec}")
# A platform sent the other way along its connection (to its `from` end) counts its
# distance down in 2.1.23; the journey reads from where it left to where it goes, d counting up.
send({"t": "hello", "v": 1, "sid": "s1", "w": 1})  # keep-alive: these checks take a few seconds
pdata = F.platform_data[plat]
pdata.schedule = lua.table_from({"current": 1, "records": lua.table_from([lua.table_from({"station": "nauvis"})])})
F.platform_travel(plat, "nauvis-vulcanus", 0.75, 2.5)
rec = next_plat()["l"][0]
check(rec.get("from") == "vulcanus" and rec.get("to") == "nauvis" and rec.get("d") == 250 and rec.get("len") == 15000,
      f"plat: heading to the connection's from end, the journey is turned round: {rec}")
# A stop that is neither end (a trip of several legs): the way distance moves says it.
pdata.schedule = lua.table_from({"current": 1, "records": lua.table_from([lua.table_from({"station": "solar-system-edge"})])})
pdata.distance = 0.8
rec = next_plat()["l"][0]
check(rec.get("from") == "nauvis" and rec.get("d") == 800, f"plat: distance going up reads forwards: {rec}")
pdata.distance = 0.7
rec = next_plat()["l"][0]
check(rec.get("from") == "vulcanus" and rec.get("to") == "nauvis" and rec.get("d") == 300, f"plat: distance going down reads backwards: {rec}")
rec = next_plat()["l"][0]
check(rec.get("from") == "vulcanus" and rec.get("d") == 300, f"plat: and stays so while it stands still: {rec}")
pdata.schedule = lua.table_from({"current": 1, "records": lua.table_from([lua.table_from({"station": "vulcanus"})])})
pdata.distance = 0.25
send({"t": "hello", "v": 1, "sid": "s1", "w": 1})
send({"t": "plat_board", "i": 0})
tick(1)
check("The platform must be stopped at a planet to drop to it" in texts(take()) and puppet.surface.name == "platform-1",
      "plat_board 0 while travelling is refused")
F.platform_arrive(plat, "vulcanus")
send({"t": "plat_board", "i": 0})
tick(2)
surf = of_type(take(), "surface")
check(surf and surf[0]["surface"] == "vulcanus" and surf[0]["planet"] == "vulcanus" and "pf" not in surf[0] and puppet.surface.name == "vulcanus",
      f"plat_board 0 drops to the planet the platform is stopped at, making its surface: {surf}")
send({"t": "plat_board", "i": 1})
tick(2)
check(puppet.surface.name == "platform-1", "and plat_board takes it back up to the platform in orbit there")
planet = of_type(take(), "planet")
check(planet and planet[-1]["name"] == "space", f"planet: on a platform it is space: {planet[-1:]}")
# In the hub (where a rocket leaves it) the character can't be a passenger or move on its surface,
# so land hops it to the planet and back beside the hub first.
F.entity_data(puppet).hub = plat.hub
send({"t": "land"})
tick(1)
check(any(m["text"] == "Going down to vulcanus in a cargo pod" for m in of_type(take(), "msg")) and same(F.pod_passenger, puppet)
      and puppet.surface.name == "platform-1" and puppet.hub is None,
      "land: from inside the hub down to the planet the platform is stopped at, in a cargo pod with the character inside")
tick(2)
me = of_type(take(), "me")
pod = puppet.cargo_pod
check(pod is not None and me and me[-1].get("pod") == pod.unit_number and me[-1].get("ps") == "awaiting_launch" and me[-1].get("up") == 1
      and (me[-1].get("gx"), me[-1].get("gy")) == (fixed(plat.hub.position.x), fixed(plat.hub.position.y)) and "hub" not in me[-1],
      f"me: the pod, its state and the hub it leaves from: {me[-1:]}")
pod_data = F.entity_data(pod)
land_at = pod_data.cargo_pod_destination.position
pod_data.cargo_pod_state = "descending"
pod_data.surface = g.game.planets["vulcanus"].surface
send({"t": "walk", "d": 4})
send({"t": "mine", "u": 0, "p": 0, "x": 0, "y": 0})
tick(2)
msgs = take()
me = of_type(msgs, "me")
check(me and me[-1].get("up") == 0 and (me[-1]["gx"], me[-1]["gy"]) == (fixed(land_at.x), fixed(land_at.y)) and "Not while flying" in texts(msgs)
      and me[-1]["w"] == 0, f"me: coming down, the spot it lands on; walking and mining wait: {me[-1:]} {texts(msgs)}")
F.pod_arrive(pod)
tick(2)
msgs = take()
me = of_type(msgs, "me")
check(puppet.surface.name == "vulcanus" and me and "pod" not in me[-1] and of_type(msgs, "surface"),
      f"the pod lands and the character stands on the planet: {me[-1:]}")
send({"t": "plat_board", "i": 1})
tick(2)
take()
F["raise"]("on_space_platform_changed_state", lua.table_from({"platform": plat, "old_state": g.defines.space_platform_state.on_the_path}))
tick(1)
pst = of_type(take(), "pst")
check(pst and pst[-1]["i"] == 1 and pst[-1]["old"] == "on_the_path" and pst[-1]["loc"] == "vulcanus", f"pst: a platform arriving: {pst}")

send({"t": "plat_pause", "i": 1, "p": 1})
send({"t": "plat_sched", "i": 1, "l": ["nauvis", "vulcanus", "nowhere"], "c": 2})
tick(1)
take()
rec = next_plat()["l"][0]
check(rec.get("pa") == 1 and rec.get("st") == "paused" and rec.get("sch") == {"c": 2, "l": ["nauvis", "vulcanus"]},
      f"plat_pause and plat_sched (unknown places dropped, current record set): {rec}")
lines = platform_console("leave nauvis")
tick(2)
surf = of_type(take(), "surface")
check(any("moved to nauvis" in l for l in lines) and surf and surf[0]["planet"] == "nauvis" and puppet.surface.name == "nauvis",
      f"/f3d-platform leave <planet> brings the character home: {lines} {surf}")
send({"t": "plat_board", "i": 1})
tick(1)
check("That platform isn't in orbit here" in texts(take()) and puppet.surface.name == "nauvis",
      "plat_board refuses a platform orbiting another planet")
lines = platform_console("list")
check(any("platform 1 Platform 1: paused at vulcanus" in l for l in lines), f"/f3d-platform list: {lines}")
send({"t": "sub", "c": [[0, 0]]})
tick(3)
take()

# --- Space Age screens: space map, new platforms, silo, hub, landing pad, collector, quality ------
send({"t": "smap"})
tick(1)
sm = of_type(take(), "smap")
locs = {r[0]: r for r in (sm[0]["loc"] if sm else [])}
cons = {(r[0], r[1]): r for r in (sm[0]["con"] if sm else [])}
check(sm and locs.get("nauvis") == ["nauvis", "planet", 0, -5000, 1, 1, 1000, 1, 250] and locs.get("vulcanus", [0] * 9)[4] == 1
      and locs.get("vulcanus", [0] * 9)[6] == 1500 and locs.get("solar-system-edge", [0] * 9)[7] == 0
      and locs.get("solar-system-edge", [0] * 6)[4] == 0,
      f"smap: space locations with star map positions, unlocked and surfaces: {sm}")
check(cons.get(("nauvis", "solar-system-edge"), [0] * 4)[3] == 1000 and 0 < cons.get(("nauvis", "vulcanus"), [0] * 4)[3] < 1000
      and cons.get(("nauvis", "vulcanus"), [0] * 4)[2] == 15000, f"smap: connections with length and asteroid danger: {cons}")

send({"t": "plat_new"})
tick(1)
check("You need a space platform starter pack" in texts(take()), "plat_new needs a starter pack")
puppet.insert(lua.table_from({"name": "space-platform-starter-pack", "count": 1}))
send({"t": "plat_new"})
tick(1)
msgs = take()
plat2 = g.game.forces.player.platforms[2]
check(plat2 is not None and plat2.state == g.defines.space_platform_state.waiting_for_starter_pack and plat2.space_location.name == "nauvis"
      and puppet.get_main_inventory().get_item_count("space-platform-starter-pack") == 1,
      f"plat_new: a platform over the planet waits for the pack, which stays in the inventory: {texts(msgs)}")

pp = puppet.position
silo_e = spawn("rocket-silo", pp.x + 7.5, pp.y + 0.5, force="player")
send(open_cmd(silo_e))
tick(2)
gs = guis(take(), silo_e)
rk = gs[-1].get("rk", {}) if gs else {}
check(gs and gs[-1]["kind"] == "silo" and rk.get("st") == "building_rocket" and rk.get("auto") == 0
      and [2, "Platform 2", "waiting_for_starter_pack"] in rk.get("to", []) and "rocket" in gs[-1].get("slots", {}),
      f"a silo's screen: status, automatic launch, platforms to launch to, the rocket's cargo: {gs[-1:]}")
send({"t": "set_silo", "u": silo_e.unit_number, "auto": 1})
send({"t": "silo_launch", "u": silo_e.unit_number, "to": 2})
tick(1)
check(silo_e.send_to_orbit_automatically and "The rocket isn't ready" in texts(take()),
      "set_silo turns automatic launches on; silo_launch without a rocket ready is refused")
silo_e.rocket_silo_status = g.defines.rocket_silo_status.rocket_ready
send({"t": "silo_launch", "u": silo_e.unit_number, "to": 2})
tick(1)
take()
check(F.launched and F.launched.type == g.defines.cargo_destination.space_platform and same(F.launched.space_platform, plat2),
      "silo_launch to a platform waiting for its starter pack sends the pack to it")
plat2.apply_starter_pack()
silo_e.rocket_silo_status = g.defines.rocket_silo_status.rocket_ready
send({"t": "silo_launch", "u": silo_e.unit_number, "to": 2})
tick(1)
take()
check(F.launched.type == g.defines.cargo_destination.station and same(F.launched.station, plat2.hub),
      "silo_launch to a built platform lands at its hub")

# Riding the rocket up: into its pod, up to the platform's hub, and inside the hub.
send({"t": "ride", "u": silo_e.unit_number, "to": 2})
tick(1)
check("The rocket isn't ready" in texts(take()) and puppet.cargo_pod is None, "ride: no rocket ready, no ride")
silo_e.rocket_silo_status = g.defines.rocket_silo_status.rocket_ready
send({"t": "ride", "u": silo_e.unit_number, "to": 2})
tick(2)
msgs = take()
me = of_type(msgs, "me")
pod = puppet.cargo_pod
check(pod is not None and same(F.launched.station, plat2.hub) and me and me[-1].get("pod") == pod.unit_number
      and me[-1].get("up") == 1 and (me[-1]["gx"], me[-1]["gy"]) == (fixed(silo_e.position.x), fixed(silo_e.position.y)),
      f"ride: the character is in the rocket's cargo pod, seen from the silo: {me[-1:]} {texts(msgs)}")
send({"t": "ride", "u": silo_e.unit_number, "to": 2})
tick(1)
check("Not while flying" in texts(take()), "ride: one ride at a time")
F.pod_arrive(pod)
tick(2)
msgs = take()
me = of_type(msgs, "me")
surf = of_type(msgs, "surface")
check(surf and surf[0].get("pf") == 2 and me and me[-1].get("hub") == plat2.hub.unit_number and "pod" not in me[-1],
      f"the pod docks: the character is inside the platform's hub (me.hub): {surf} {me[-1:]}")
send({"t": "sub", "c": [[0, 0], [-1, -1], [-1, 0], [0, -1]]})
tick(3)
take()
at = (puppet.position.x, puppet.position.y)
send({"t": "walk", "d": 4})
tick(3)
send({"t": "walk", "d": -1})
send({"t": "mine", "u": 0, "p": 0, "x": fixed(at[0] + 3), "y": fixed(at[1])})
puppet.insert(lua.table_from({"name": "wooden-chest", "count": 1}))
chests = puppet.get_main_inventory().get_item_count("wooden-chest")
send({"t": "build", "item": "wooden-chest", "x": fixed(at[0] + 6.5), "y": fixed(at[1] + 0.5), "d": 0})
tick(2)
msgs = take()
ghosts = [e for e in puppet.surface.entities.values() if e.name == "entity-ghost"]
check((puppet.position.x, puppet.position.y) == at and "Not from inside the hub" in texts(msgs) and ghosts
      and puppet.get_main_inventory().get_item_count("wooden-chest") == chests,
      f"in the hub: no walking or mining; building places a ghost: {texts(msgs)} {len(ghosts)} ghosts")
for e in ghosts:
    e.destroy()
send({"t": "land"})
tick(2)
pod = puppet.cargo_pod
check(pod is not None and puppet.hub is None and "Going down to nauvis in a cargo pod" in texts(take()),
      "land from the hub over Nauvis: into a pod")
F.pod_arrive(pod)
puppet.teleport(lua.table_from({"x": pp.x, "y": pp.y}), F.surface)
tick(3)
take()
send({"t": "sub", "c": [[0, 0]]})
tick(3)
take()
send(open_cmd(silo_e))
tick(1)
take()
send({"t": "close"})

F.effects = lua.table_from({"quality": 0.025, "speed": -0.05})
qasm = spawn("assembling-machine-1", pp.x - 6.5, pp.y + 0.5, force="player")
F.effects = None
send(open_cmd(qasm))
send({"t": "set_recipe", "u": qasm.unit_number, "recipe": "iron-gear-wheel", "q": "uncommon"})
tick(2)
gs = guis(take(), qasm)
check(gs and gs[-1].get("rq") == "uncommon" and gs[-1].get("ql") == ["normal", "uncommon", "rare"]
      and gs[-1].get("eff") == {"q": 25, "sp": -50},
      f"a machine's screen: the recipe's quality, the qualities to choose from, module effects: {gs[-1:]}")

send({"t": "set_recipe", "u": qasm.unit_number, "recipe": "iron-gear-wheel", "q": "epic"})
tick(1)
check("That quality isn't researched" in texts(take()), "set_recipe refuses a quality the force hasn't researched")
# The hover panel's beacon and module effects (`hinfo`): a machine's effects, modules and the
# beacons reaching it; a beacon's effects, modules, the machines it reaches and its effectivity.
F.effects = lua.table_from({"speed": 0.5, "consumption": 1.2})
hbeacon = spawn("beacon", qasm.position.x + 3, qasm.position.y, force="player")
F.effects = None
hbeacon.get_module_inventory().insert(lua.table_from({"name": "speed-module", "count": 2}))
send({"t": "hinfo", "q": 3, "u": qasm.unit_number, "p": 0, "x": fixed(qasm.position.x), "y": fixed(qasm.position.y)})
send({"t": "hinfo", "q": 4, "u": hbeacon.unit_number, "p": 0, "x": fixed(hbeacon.position.x), "y": fixed(hbeacon.position.y)})
send({"t": "hinfo", "q": 5, "u": 999999, "p": 0, "x": fixed(500), "y": fixed(500)})
tick(1)
hi = {m["q"]: m for m in of_type(take(), "hinfo")}
check(hi.get(3, {}).get("eff") == {"q": 25, "sp": -50} and hi[3].get("b") == 1 and "n" not in hi[3],
      f"hinfo for a machine: its effects and the beacons reaching it: {hi.get(3)}")
check(hi.get(4, {}).get("eff") == {"sp": 500, "co": 1200} and hi[4].get("m") == [["speed-module", 2]]
      and hi[4].get("n") == 1 and hi[4].get("de") == 1500,
      f"hinfo for a beacon: what it hands on, its modules, the machines it reaches, its effectivity: {hi.get(4)}")
check(hi.get(5) is not None and not any(k in hi[5] for k in ("eff", "m", "b", "n", "de", "el")),
      f"hinfo for nothing there answers with nothing: {hi.get(5)}")
# H20: what the entity info's "Consumes electricity" shows: the buffer (the Electricity bar), Max.
# consumption (75 kW and the 2.5 kW drain) and Min. consumption (the drain); a beacon here has no
# electric source in the fake, so none.
check(hi.get(3, {}).get("el") == {"e": 1000, "b": 1000, "mx": 77500, "mn": 2500} and "el" not in hi.get(4, {}),
      f"hinfo for a powered machine: its energy, buffer, max. and min. consumption: {hi.get(3)}")
# H14: a hovered roboport's links to the roboports its logistic cell is joined to (the game's
# LuaLogisticCell.neighbours): one 45 tiles away is, one 120 tiles away isn't.
rp1 = spawn("roboport", pp.x + 400, pp.y, force="player")
rp2 = spawn("roboport", pp.x + 445, pp.y + 10, force="player")
spawn("roboport", pp.x + 520, pp.y, force="player")
send({"t": "hinfo", "q": 8, "u": rp1.unit_number, "p": 0, "x": fixed(rp1.position.x), "y": fixed(rp1.position.y)})
tick(1)
hr = {m["q"]: m for m in of_type(take(), "hinfo")}.get(8, {})
check(hr.get("rn") == [fixed(rp2.position.x), fixed(rp2.position.y)],
      f"hinfo for a roboport: the roboports it links to (H14): {hr}")

send({"t": "close"})

pad = spawn("cargo-landing-pad", pp.x + 0.5, pp.y + 6.5, force="player")
send(open_cmd(pad))
tick(2)
gs = guis(take(), pad)
# Opening it makes its control behaviour, as Factorio does (circuit_settings.lua), so `cb` is there
# with everything off.
check(gs and gs[-1]["kind"] == "pad" and gs[-1].get("pad", {}).get("sec") == []
      and gs[-1]["pad"].get("cb", {}).get("req", 0) == 0 and gs[-1]["pad"].get("cb", {}).get("empty", 0) == 0
      and "chest" in gs[-1].get("slots", {}) and "trash" in gs[-1].get("slots", {}),
      f"a landing pad's screen: inventory, trash, requests, its circuit settings: {gs[-1:]}")
send({"t": "set_pad", "u": pad.unit_number, "read": 0, "req": 1})
send({"t": "set_section", "u": pad.unit_number, "i": 0, "f": [["iron-plate", "normal", 200, -1, "", -1]]})
tick(31)
gs = guis(take(), pad)
p_ = gs[-1].get("pad", {}) if gs else {}
check(p_.get("cb") == {"read": 0, "req": 1, "empty": 0} and p_.get("sec", [{}])[0].get("f") == [["iron-plate", "normal", 200, -1, "", -1]],
      f"set_pad and set_section on a landing pad: {p_}")
send({"t": "close"})

col = spawn("asteroid-collector", pp.x - 3.5, pp.y - 5.5, force="player")
send(open_cmd(col))
send({"t": "set_collector", "u": col.unit_number, "f": ["metallic-asteroid-chunk", "made-up-chunk"]})
tick(2)
gs = guis(take(), col)
check(gs and gs[-1]["kind"] == "collector" and gs[-1].get("col") == {"n": 3, "f": ["metallic-asteroid-chunk", "", ""]},
      f"an asteroid collector's chunk filters (unknown chunks cleared): {gs[-1:]}")
send({"t": "close"})

qbelt = spawn("transport-belt", pp.x + 2.5, pp.y - 2.5, force="player", direction=4)
F.put_on_belt(qbelt, 1, "iron-plate", 0.25, 77, None, "rare")
F.put_on_belt(qbelt, 2, "iron-plate", 0.5, 78)
tick(6)
bq = of_type(take(), "bq")
check(bq and bq[-1]["l"] == [[77, "rare"]], f"bq: the quality of belt items better than normal: {bq}")
qbelt.destroy()
tick(12)
bq = of_type(take(), "bq")
check(bq and bq[0]["l"] == [] and len(bq) == 1, f"bq: one empty list clears it, then nothing: {bq}")

send({"t": "plat_board", "i": 2})
tick(2)
msgs = take()
planet = of_type(msgs, "planet")
check(puppet.surface.name == "platform-2", "the character boards the new platform")
plat2.surface.props.gravity = 0
puppet.insert(lua.table_from({"name": "burner-inserter", "count": 1}))
hub = plat2.hub
hp = hub.position
send({"t": "build", "item": "burner-inserter", "x": fixed(hp.x + 5.5), "y": fixed(hp.y + 0.5), "d": 0})
tick(1)
check(any(t.startswith("Can't build here: gravity is 0") for t in texts(take())),
      "building something that needs gravity on a platform says why it can't")
nb = g.package.loaded["scripts.space"].blocked(plat2.surface)
check(to_py(nb) == [[eid["burner-inserter"], "gravity", 0.1, 1e9]], f"planet.nb: what can't be built on this surface: {to_py(nb)}")

send(open_cmd(hub))
tick(2)
gs = guis(take(), hub)
h = gs[-1].get("hub", {}) if gs else {}
check(gs and gs[-1]["kind"] == "hub" and h.get("i") == 2 and h.get("w") == 1250000 and h.get("th") == [0, 0]
      and h.get("prov") == 0 and h.get("sec") == [] and h.get("dest") == ["nauvis", "vulcanus"] and h.get("loc") == "nauvis"
      and "chest" in gs[-1].get("slots", {}) and "trash" in gs[-1].get("slots", {}),
      f"a hub's screen: its platform's state, weight, thrusters, requests, inventory and trash: {gs[-1:]}")
send({"t": "set_section", "u": hub.unit_number, "i": 0,
      "f": [["iron-plate", "uncommon", 100, 400, "vulcanus", 50], ["no-such-item", "", 1, -1, "", -1]]})
send({"t": "set_hub", "u": hub.unit_number, "prov": 1})
waits = [{"type": "all_requests_satisfied", "compare_type": "and"}, {"type": "time", "compare_type": "or", "ticks": 1800}]
send({"t": "set_schedule", "u": hub.unit_number, "records": [{"station": "vulcanus", "wait_conditions": waits}, {"station": "nowhere"}]})
send({"t": "set_interrupts", "u": hub.unit_number, "interrupts": [
    {"name": "Refuel", "conditions": [{"type": "any_request_zero", "compare_type": "and"}], "targets": [{"station": "nauvis"}]}]})
tick(31)
gs = guis(take(), hub)
h = gs[-1].get("hub", {}) if gs else {}
sec = (h.get("sec") or [{}])[0]
check(sec.get("f") == [["iron-plate", "uncommon", 100, 400, "vulcanus", 50]] and sec.get("on") == 1 and sec.get("man") == 1,
      f"set_section on a hub: a request from a planet with quality, max and a minimum delivery: {h.get('sec')}")
check(hub.providing_to_other_platforms and h.get("prov") == 1, "set_hub: provide to other platforms")
sched = h.get("sched", {})
check([r["station"] for r in sched.get("records", [])] == ["vulcanus"] and sched["records"][0]["wait_conditions"] == waits
      and sched.get("interrupts", [{}])[0].get("name") == "Refuel" and sched["interrupts"][0]["targets"][0]["station"] == "nauvis",
      f"the hub edits its platform's schedule and interrupts like a train's (unknown places dropped): {sched}")
send({"t": "set_section", "u": hub.unit_number, "i": 1, "on": 0, "m": 2})
send({"t": "set_section", "u": hub.unit_number, "i": 0})
tick(31)
gs = guis(take(), hub)
secs = gs[-1].get("hub", {}).get("sec", []) if gs else []
check(len(secs) == 2 and secs[0]["on"] == 0 and secs[0]["m"] == 2, f"set_section: off, a multiplier, a second section: {secs}")
send({"t": "set_section", "u": hub.unit_number, "i": 2, "del": 1})
tick(31)
gs = guis(take(), hub)
check(gs and len(gs[-1]["hub"]["sec"]) == 1, "set_section del removes a section")
send({"t": "set_silo", "u": hub.unit_number, "auto": 1})
tick(1)
check("That isn't a rocket silo" in texts(take()), "space commands check what the open screen is")
send({"t": "close"})

data2 = F.platform_data[plat2]
data2.chunks[1] = lua.table_from({"name": "metallic-asteroid-chunk", "position": {"x": hp.x + 10, "y": hp.y - 4},
                                  "movement": {"x": 0, "y": 0.05}}, recursive=True)
tick(10)
ach = of_type(take(), "ach")
check(ach and ach[-1]["l"] == [["metallic-asteroid-chunk", fixed(hp.x + 10), fixed(hp.y - 4), 0, 768]],
      f"ach: asteroid chunks near the focus on a platform, moving 0.05 tiles a tick: {ach}")
data2.chunks[1] = None
tick(20)
ach = of_type(take(), "ach")
check(len(ach) == 1 and ach[0]["l"] == [], f"ach: one empty list once they're gone: {ach}")

# Asteroid collectors' arms (`acol`, F3): their arms, speed and filters, and the chunks they catch,
# seen as chunks gone from their catch circle (5 tiles in front, radius 7.5).
def made(name, x, y, **extra):
    return puppet.surface.create_entity(lua.table_from({"name": name, "position": {"x": x, "y": y}, "force": "player", **extra},
                                                       recursive=True))


acol_n = made("asteroid-collector", hp.x, hp.y - 8)
acol_r = made("asteroid-collector", hp.x + 20, hp.y, direction=4, quality="rare")
acol_r.set_filter(1, "carbonic-asteroid-chunk")
tick(60)  # the mod looks for collectors near the focus once a second
rows = {r[0]: r for m in of_type(take(), "acol") for r in m.get("l", [])}
check(rows.get(acol_n.unit_number) == [acol_n.unit_number, 1, 200, 1, []]
      and rows.get(acol_r.unit_number) == [acol_r.unit_number, 3, 300, 1, ["carbonic-asteroid-chunk"]],
      f"acol: each collector's arms and arm speed by quality, moving, its filters: {rows}")
caught_chunk = lua.table_from({"name": "metallic-asteroid-chunk", "position": {"x": hp.x + 1, "y": hp.y - 15},
                               "movement": {"x": 0.01, "y": 0}}, recursive=True)
data2.chunks[1] = caught_chunk
# Inside the east-facing collector's box but outside its circle: not caught when it goes.
data2.chunks[2] = lua.table_from({"name": "carbonic-asteroid-chunk", "position": {"x": hp.x + 33.5, "y": hp.y + 6.5},
                                  "movement": {"x": 0, "y": 0}}, recursive=True)
tick(10)
take()
caught_chunk.position = lua.table_from({"x": hp.x + 1.1, "y": hp.y - 15})
tick(10)
check(not any(m.get("g") for m in of_type(take(), "acol")), "acol: a chunk where its movement takes it isn't caught")
data2.chunks[1] = None
data2.chunks[2] = None
tick(10)
msgs = of_type(take(), "acol")
check([g for m in msgs for g in m.get("g", [])] == [[acol_n.unit_number, "metallic-asteroid-chunk", fixed(hp.x + 1.2), fixed(hp.y - 15)]],
      f"acol g: the chunk gone from a collector's circle, caught where it had drifted to (not the one outside it): {msgs}")
acol_n.status = g.defines.entity_status.low_power
acol_r.status = g.defines.entity_status.disabled_by_control_behavior
tick(10)
rows = {r[0]: r for m in of_type(take(), "acol") for r in m.get("l", [])}
check(rows.get(acol_n.unit_number, [0] * 4)[2:4] == [60, 1] and rows.get(acol_r.unit_number, [0] * 4)[3] == 2,
      f"acol: low power slows the arms (unpowered_arm_speed_scale); switched off by the circuit network they fold home (2): {rows}")
acol_n.destroy()
acol_r.destroy()
send({"t": "plat_board", "i": 0})
tick(2)
take()
check(puppet.surface.name == "nauvis", "and back down to Nauvis")
send({"t": "sub", "c": [[0, 0]]})
tick(3)
take()

# --- client restart and timeout ------------------------------------------------------------------
send({"t": "rate", "l": 2})
send({"t": "hello", "v": 1, "sid": "s2", "w": 0})
tick(3)
msgs = take()
check(msgs and msgs[0]["t"] == "welcome" and msgs[0]["r"] == 1, "a new client session restarts the sequence")
check(rate.level() == 0, "and starts at rate 0 (the old session's `rate` doesn't carry over)")
tick(700)
check(g.storage.f3d.client is None, "client is dropped after 10 s without hello")
check(g.storage.f3d.screen is None, "a dropped client's machine screen is closed")
take()
tick(5)
check(take() == [], "nothing is sent after the client is dropped")

# --- /f3d-selftest and a respawn on a server -------------------------------------------------------
def selftest(**cmd):
    before = len(F.printed)
    F.commands["f3d-selftest"](lua.table_from(dict(cmd, name="f3d-selftest")))
    return [str(p) for p in list(F.printed.values())[before:]]


send({"t": "hello", "v": 1, "sid": "s1", "w": 1})
tick(2)
take()
puppet = g.storage.f3d.puppet
chest = spawn("wooden-chest", puppet.position.x + 2, puppet.position.y + 1, force="player")
lines = selftest()
check(any("PASS the bridge's character has no player" in l for l in lines) and any("PASS character.selected can be set" in l for l in lines)
      and not any("FAIL" in l for l in lines), f"/f3d-selftest on a server: {lines}")
chest.destroy()
old_unit = puppet.unit_number
puppet.destroy()
tick(2)
welcome = of_type(take(), "welcome")
check(welcome and welcome[-1]["u"] != old_unit and welcome[-1]["u"] == g.storage.f3d.puppet.unit_number,
      "a new character after the old one died starts over with a welcome naming it")
puppet = g.storage.f3d.puppet

# --- the character's gear: armour grid, toggles, character info, players, death ----------------------
grid = F.make_grid(10, 10)
puppet.grid = grid
main = puppet.get_main_inventory()
main.insert(lua.table_from({"name": "energy-shield-equipment", "count": 2}))
main.insert(lua.table_from({"name": "exoskeleton-equipment", "count": 1}))
main.insert(lua.table_from({"name": "battery-equipment", "count": 1}))
gear_slots = {main[i].name: i for i in range(1, 81) if main[i].valid_for_read}
# As after a handshake: everything once.
g.storage.f3d.eq_sent = lua.table_from({})
g.storage.f3d.info_sig = None
g.storage.f3d.pl_sig = None
tick(61)
msgs = take()
eqs = [m for m in of_type(msgs, "eq") if m["kind"] == "char"]
check(eqs and eqs[-1]["w"] == 10 and eqs[-1]["h"] == 10 and eqs[-1]["l"] == [] and eqs[-1]["u"] == puppet.unit_number,
      f"eq: the character's empty 10x10 armour grid: {eqs[-1:]}")
veh = [m for m in of_type(msgs, "eq") if m["kind"] == "veh"]
check(veh and veh[-1]["w"] == 0 and veh[-1]["u"] == 0, f"eq: no vehicle grid: {veh[-1:]}")
cinfo = of_type(msgs, "cinfo")
check(cinfo and cinfo[-1]["reach"] == 100 and cinfo[-1]["craft"] == 1000 and cinfo[-1]["slots"] == 80 and cinfo[-1]["hp"] == 250,
      f"cinfo: reach, crafting speed, slots and health: {cinfo[-1:]}")
pl = of_type(msgs, "pl")
check(pl and pl[-1]["me"] == 0 and pl[-1]["u"] == puppet.unit_number, f"pl: the bridge's own character plays no player: {pl[-1:]}")
send({"t": "eq_put", "kind": "char", "fi": gear_slots["energy-shield-equipment"], "x": 2, "y": 0})
send({"t": "eq_put", "kind": "char", "fi": gear_slots["exoskeleton-equipment"]})  # Shift+click: the first place it fits
send({"t": "eq_put", "kind": "char", "fi": gear_slots["energy-shield-equipment"], "x": 3, "y": 1})  # overlaps the first
send({"t": "eq_put", "kind": "char", "fi": gear_slots["battery-equipment"], "x": 9, "y": 9})  # doesn't fit at the edge
tick(1)
msgs = take()
placed = sorted((e.name, e.position.x, e.position.y) for e in grid.equipment.values())
check(placed == [("energy-shield-equipment", 2, 0), ("exoskeleton-equipment", 0, 0)],
      f"eq_put: at a position, Shift+click in the first place it fits, refusals where it overlaps or sticks out: {placed}")
check(main.get_item_count("energy-shield-equipment") == 1 and main.get_item_count("exoskeleton-equipment") == 0
      and main.get_item_count("battery-equipment") == 1, "eq_put takes one from the inventory slot only when it was placed")
check(texts(msgs).count("No room for that in the grid") == 2, f"refusals say so: {texts(msgs)}")
eqs = [m for m in of_type(msgs, "eq") if m["kind"] == "char"]
rec = {r[0]: r for r in (eqs[-1]["l"] if eqs else [])}
check(eqs and rec.get("energy-shield-equipment", [])[:6] == ["energy-shield-equipment", 2, 0, 2, 2, "normal"]
      and rec["energy-shield-equipment"][8:10] == [25, 50] and eqs[-1]["msh"] == 50 and eqs[-1]["sh"] == 25
      and eqs[-1]["mv"] == 300 and eqs[-1]["mvon"] == 1 and eqs[-1]["rb"] == 1,
      f"eq is sent at once after a change, with shields, movement bonus and the roboport switch: {eqs[-1:]}")
mes = of_type(msgs, "me") or of_type((tick(2), take())[1], "me")
check(mes and mes[-1].get("sd") == 25 and mes[-1].get("msd") == 50, f"me carries the armour's shields: {mes[-1:]}")
send({"t": "eq_move", "kind": "char", "x": 3, "y": 1, "tx": 6, "ty": 6})
send({"t": "eq_move", "kind": "char", "x": 0, "y": 0, "tx": 5, "ty": 5})  # onto the shield
tick(1)
placed = sorted((e.name, e.position.x, e.position.y) for e in grid.equipment.values())
check(placed == [("energy-shield-equipment", 6, 6), ("exoskeleton-equipment", 0, 0)],
      f"eq_move: by any cell of it, refused where it overlaps: {placed}")
empty = next(i for i in range(1, 81) if not main[i].valid_for_read)
send({"t": "eq_take", "kind": "char", "x": 7, "y": 7, "ti": empty})
tick(1)
check(len(grid.equipment) == 1 and main[empty].valid_for_read and main[empty].name == "energy-shield-equipment",
      "eq_take: by any cell, into the slot asked for")
send({"t": "eq_toggle", "what": "roboport", "on": 0})
send({"t": "eq_toggle", "what": "movement", "on": 0})
tick(1)
eqs = [m for m in of_type(take(), "eq") if m["kind"] == "char"]
check(not puppet.allow_dispatching_robots and grid.inhibit_movement_bonus and eqs and eqs[-1]["rb"] == 0 and eqs[-1]["mvon"] == 0
      and eqs[-1]["mv"] == 0, f"eq_toggle: Alt+F turns the personal roboport off, Alt+E the exoskeletons: {eqs[-1:]}")
send({"t": "eq_toggle", "what": "movement", "on": 1})
tick(1)
take()
car = F.spawn("car", puppet.position.x + 2, puppet.position.y, lua.table_from({"force": "player"}))
car.grid = F.make_grid(4, 4)
send(open_cmd(car))
tick(31)
veh = [m for m in of_type(take(), "eq") if m["kind"] == "veh"]
check(veh and veh[-1]["u"] == car.unit_number and veh[-1]["w"] == 4, f"eq: the open car's grid: {veh[-1:]}")
send({"t": "eq_put", "kind": "veh", "u": car.unit_number, "fi": gear_slots["battery-equipment"], "x": 0, "y": 0})
tick(1)
check(len(car.grid.equipment) == 1 and main.get_item_count("battery-equipment") == 0, "eq_put into a vehicle's grid")
send({"t": "close"})
tick(1)
take()
# Death: the bridge's own character waits out the respawn time, then comes back at the spawn.
dead_unit = puppet.unit_number
puppet.teleport(lua.table_from({"x": 30, "y": 30}))
F["raise"]("on_entity_died", lua.table_from({"entity": puppet}))
puppet.destroy()
tick(30)
msgs = take()
dead = of_type(msgs, "dead")
check(dead and 560 <= dead[-1]["left"] <= 600 and dead[-1]["x"] == fixed(30) and not of_type(msgs, "me") and not of_type(msgs, "welcome"),
      f"dead: while dead the client hears how long until the respawn, and where it died: {dead[-1:]}")
send({"t": "respawn"})
for _ in range(5):
    send({"t": "hello", "v": 1, "sid": "s1", "w": 1})
    tick(100)
check(not (g.storage.f3d.puppet and g.storage.f3d.puppet.valid), "Respawn before the time is up does nothing")
take()
send({"t": "hello", "v": 1, "sid": "s1", "w": 1})
tick(80)
msgs = take()
new = g.storage.f3d.puppet
welcome = of_type(msgs, "welcome")
check(new and new.valid and new.unit_number != dead_unit and new.position.x == 0 and new.position.y == 0
      and welcome and welcome[-1]["u"] == new.unit_number, "after the respawn time a new character at the spawn, with a welcome")
check(g.storage.f3d.respawn is None and g.storage.f3d.death is None, "and the death is forgotten")
puppet = new

# --- taking over a save's character (a single-player save on a server) -----------------------------
def player_console(parameter):
    before = len(F.printed)
    F.commands["f3d-player"](lua.table_from({"name": "f3d-player", "parameter": parameter}))
    return [str(p) for p in list(F.printed.values())[before:]]


owner = F.make_offline_player(1, "owner", 20.5, 5.5)
owner.get_main_inventory().insert(lua.table_from({"name": "iron-gear-wheel", "count": 20}))
owner.get_main_inventory().set_filter(5, "wood")
owner.get_inventory(g.defines.inventory.character_armor).insert(lua.table_from({"name": "light-armor", "count": 1}))
owner.get_requester_point().add_section("Main").filters = lua.table_from(
    [{"value": {"type": "item", "name": "iron-plate", "quality": "normal", "comparator": "="}, "min": 100}], recursive=True)
owner.set_quick_bar_slot(1, 1, "transport-belt")
old_puppet = puppet
lines = player_console("")
check(any("owner, not connected" in l for l in lines), f"/f3d-player lists the save's players: {lines}")
lines = player_console("owner")
stand_in = g.storage.f3d.puppet
check(stand_in != old_puppet and not old_puppet.valid and stand_in.position.x == 20.5 and stand_in.position.y == 5.5
      and g.storage.f3d.held_for == 1 and any("(playing as)" in l for l in lines),
      f"/f3d-player owner: a stand-in where the owner's character was, the old bridge character gone: {lines}")
tick(2)
msgs = take()
welcome = of_type(msgs, "welcome")
check(welcome and welcome[-1]["u"] == stand_in.unit_number and welcome[-1]["x"] == fixed(20.5),
      "a new handshake names the stand-in")
tick(60)
msgs += take()
main = stand_in.get_main_inventory()
check(main.get_item_count("iron-gear-wheel") == 20 and owner.get_main_inventory().get_item_count("iron-gear-wheel") == 0,
      "the owner's inventory moved onto the stand-in")
check(main.get_filter(5) is not None and main.get_filter(5)["name"] == "wood", "slot filters moved too")
armor = stand_in.get_inventory(g.defines.inventory.character_armor)
check(armor[1].valid_for_read and armor[1].name == "light-armor", "the armour moved")
check(main.get_item_count("iron-plate") >= 1, "what the old bridge character carried was kept")
clog = of_type(msgs, "clog")
check(clog and ["iron-plate", 100, -1] in clog[-1]["l"], f"the owner's logistic requests (a group section) are the stand-in's: {clog}")
qb = of_type(msgs, "qb")
check(qb and qb[-1]["l"][0] == "transport-belt", "the quickbar is the owner's")
send({"t": "set_char_requests", "l": [["iron-plate", 150, -1], ["iron-gear-wheel", 10, -1]]})
tick(1)
point = stand_in.get_requester_point()
groups = [s.group for s in point.sections.values()]
main_group = F.logistic_groups["Main"]
check(len(main_group) == 1 and main_group[1].min == 150 and groups == ["Main", ""] and point.get_section(2).filters[1].value.name == "iron-gear-wheel",
      f"editing the requests keeps each in its section, new ones in a section of their own ({groups})")
take()
# The owner joins with the real game: everything goes back, and the bridge plays their character.
real = spawn("character", 30.5, 5.5, force="player")
F.connect_player(owner, real)
tick(2)
msgs = take()
check(g.storage.f3d.puppet.unit_number == real.unit_number and not stand_in.valid and g.storage.f3d.held_for is None
      and real.get_main_inventory().get_item_count("iron-gear-wheel") == 20 and real.position.x == 20.5,
      "when the owner joins, their things move back onto their character, which stands where the stand-in was")
welcome = of_type(msgs, "welcome")
check(welcome and welcome[-1]["u"] == real.unit_number, "and the client plays it")
# "Show in Zenith" in the real game brings the client playing that player to the front.
F.handlers["f3d-show-3d"](lua.table_from({"player_index": 1, "input_name": "f3d-show-3d"}))
check(of_type(take(), "raise"), "Ctrl+F9 in the real game tells the client to come to the front (raise)")
# Each player's row says what armour their character wears (the client draws its look).
g.storage.f3d.pl_sig = None
tick(60)
pl = of_type(take(), "pl")
rows = {r[1]: r for r in (pl[-1]["l"] if pl else [])}
check(len(rows.get("owner", [])) == 12 and rows["owner"][11] == "light-armor",
      f"pl: a player's row ends with their character's armour: {pl[-1:]}")
# Leave the harness as before for the single-player checks.
F.players[1] = None
F.players_by[1] = None
F.players_by["owner"] = None
puppet = real

# --- the client's console: cmd / cmdr, and the zenith remote interface -------------------------
send({"t": "hello", "v": 1, "sid": "s1", "w": 1})
tick(1)
take()


def console(text, cid):
    send({"t": "cmd", "id": cid, "text": text})
    tick(1)
    replies = [m for m in of_type(take(), "cmdr") if m["id"] == cid]
    return replies[-1] if replies else None


r = console("/version", 1)
check(r and r["l"] == ["2.1.23"] and "ok" not in r, f"cmd /version: the bridge answers with cmdr: {r}")
r = console("/seed", 2)
check(r and r["l"] == ["123456789"], f"cmd /seed: {r}")
r = console("/time", 3)
check(r and r["l"] == ["1 hour, 2 minutes and 5 seconds"], f"cmd /time in Factorio's words: {r}")
r = console("/evolution", 4)
check(r and "Evolution factor: 0.2500. (Time 60%) (Pollution 20%) (Spawner kills 20%)" in r["l"][0], f"cmd /evolution: {r}")
r = console("/players", 5)
check(r and r["l"][0].startswith("Players ("), f"cmd /players: {r}")
r = console("/f3d-status", 6)
check(r and any(str(l).startswith("[Zenith] client on port") for l in r["l"]), f"cmd /f3d-status: its lines come back, not to RCON: {r}")
r = console("/no-such-command", 7)
check(r and r.get("ok") == 0 and r["l"] == [], f"cmd: an unknown command answers ok = 0: {r}")
r = console("/c game.print(1)", 8)
check(r and r.get("ok") == 0, "cmd: Lua is never run from a packet")
F.researched_all = False
r = console("/cheat", 9)
zenith = F.remote["zenith"]
same = lua.eval("function(a, b) return a == b end")
owner = zenith.player() or g.package.loaded["scripts.puppet"].held_for()
check(F.researched_all and r and r["l"][0] == "Researched every technology"
      and (r["l"][1] == "Cheat mode on for " + owner.name if owner else "crafting still takes time" in r["l"][1]),
      f"cmd /cheat: research, and cheat mode for the character's player (none for the bridge's own): {r}")
r = console("/cheat all", 10)
check(r and r["l"][-1].startswith("Gave the character ") and not r["l"][-1].startswith("Gave the character 0 "), f"cmd /cheat all gives the kit: {r}")
r = console("/cheat nowhere", 11)
check(r and r["l"] == ["No planet or platform called nowhere"], f"cmd /cheat <unknown place>: {r}")
check(same(zenith.character(), g.storage.f3d.puppet) and zenith.name() == (owner.name if owner else None),
      "remote zenith: the client's character, and the name of its player")

# --- single-player (hybrid) mode -----------------------------------------------------------------
F.multiplayer = False
player = F.make_player(puppet)
player.set_quick_bar_slot(1, 3, "iron-plate")
send({"t": "hello", "v": 1, "sid": "sp", "w": 0})
tick(3)
msgs = take()
check(of_type(msgs, "welcome"), "single-player handshake works (send_udp without for_player)")
qb = of_type(msgs, "qb")
check(qb and qb[-1]["l"][2] == "iron-plate", "hybrid: the quickbar is the player's own")
send({"t": "qb_set", "i": 12, "item": "transport-belt"})
send({"t": "qb_page", "p": 3})
tick(1)
qb = of_type(take(), "qb")
check(F.quickbar[12] == "transport-belt" and player.get_active_quick_bar_page(1) == 3 and qb and qb[-1]["l"][11] == "transport-belt"
      and qb[-1]["p"] == 3, "hybrid: qb_set and qb_page change the player's quickbar")
send({"t": "qb_set", "i": 12, "item": ""})
tick(1)
check(F.quickbar[12] is None, "hybrid: and qb_set \"\" clears a slot")
player.set_quick_bar_slot(1, 5, "wood")
tick(31)
qb = of_type(take(), "qb")
check(qb and qb[-1]["l"][4] == "wood", "hybrid: a change made in the Factorio window is sent")
F.chart_requests = lua.table_from([])
tick(121)
take()
check(len(F.chart_requests) == 0, "hybrid: the bridge doesn't chart (the player does)")
F.charted["0,0"] = True
chest = spawn("wooden-chest", puppet.position.x + 2, puppet.position.y + 1, force="player")
check(same(F.remote["zenith"].player(), player) and F.remote["zenith"].name() == player.name,
      "hybrid: remote zenith's player is the player (game.player in the client's Lua commands)")
send({"t": "cmd", "id": 20, "text": "/cheat"})
tick(1)
take()
check(F.cheat_mode is True, "hybrid: /cheat turns the player's cheat mode on")
send({"t": "cmd", "id": 21, "text": "/cheat off"})
tick(1)
take()
check(F.cheat_mode is False, "hybrid: /cheat off turns it off")
lines = selftest(player_index=1)
check(lines and all(l.startswith("PLAYER ") for l in lines) and any("PASS the player's quickbar can be read and written" in l for l in lines)
      and any("PASS character.player is the player playing it" in l for l in lines) and not any("FAIL" in l for l in lines),
      f"/f3d-selftest in single-player, answered in the game's console: {lines}")
check(F.quickbar[100] is None, "the self-test puts the quickbar slot it borrowed back")
chest.destroy()

if failures:
    print(f"\n{len(failures)} check(s) failed")
    sys.exit(1)
print("all bridge checks passed")
