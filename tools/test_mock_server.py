"""Drives tools/mock_server.py tick by tick over real localhost UDP and checks its messages
against the protocol, so the mock stays a faithful stand-in for the mod.

    python3 tools/test_mock_server.py
"""

import json
import math
import pathlib
import socket
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import mock_server  # noqa: E402
import mock_space  # noqa: E402
import mock_vehicles  # noqa: E402
import mock_turrets  # noqa: E402
import mock_shots  # noqa: E402
import protocol  # noqa: E402

failures = []


def check(cond, what):
    if not cond:
        failures.append(what)
        print("FAIL:", what)


game = mock_server.MockGame(seed=1, drop=0.0)
game.build_starter_base()
game.build_cliffs()
game.sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
game.sock.bind(("127.0.0.1", 0))
game.sock.setblocking(False)
server = game.sock.getsockname()

client = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
client.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, 8 * 1024 * 1024)
client.bind(("127.0.0.1", 0))
client.setblocking(False)

expected_r = 1


def send(msg):
    client.sendto(json.dumps(msg).encode(), server)


# As the client asks: z delta-coded bi, ih, mv; b several messages to a datagram, joined by newlines.
HELLO = {"t": "hello", "v": 1, "sid": "test", "w": 1, "z": 1, "b": 1}


def step(n=1):
    for _ in range(n):
        # The real client says hello once a second as a keep-alive.
        if game.tick % 60 == 0:
            send(HELLO)
        game.step()


def decode(msg):
    """Undoes the delta coding the hello asked for (z), in place; z stays to show it was coded."""
    l = msg["l"]
    if msg["t"] == "mv":
        prev = [0, 0, 0, 0]
        for i, rec in enumerate(l):
            l[i] = [p + d for p, d in zip(prev, rec[:4])] + rec[4:]
            prev = l[i][:4]
    else:
        for i in range(4, len(l)):
            l[i] += l[i - 4]


batched = 0  # the most messages seen in one datagram


def take():
    global expected_r
    out = []
    while True:
        try:
            data, _ = client.recvfrom(65536)
        except BlockingIOError:
            return out
        global batched
        lines = protocol.split_datagram(data)
        batched = max(batched, len(lines))
        for msg in lines:
            for problem in protocol.problems(msg):
                check(False, f"protocol: {problem}")
            if msg.get("z") == 1:
                decode(msg)
            if "r" in msg:
                if msg["t"] == "welcome":
                    expected_r = msg["r"]
                check(msg["r"] == expected_r, f"sequence gap: got {msg['r']}, expected {expected_r}")
                expected_r = msg["r"] + 1
            out.append(msg)


def of_type(msgs, t):
    return [m for m in msgs if m["t"] == t]


# handshake
send({"t": "hello", "v": 1, "sid": "test", "w": 0})
step(3)
msgs = take()
hs_msgs = msgs
check(msgs and msgs[0]["t"] == "welcome", "welcome first")
protos = {rec[1]: rec[0] for m in of_type(msgs, "protos") for rec in m["l"]}
check("transport-belt" in protos and "tree-01" in protos, "prototype dictionary sent")
check(of_type(msgs, "ready") and of_type(msgs, "recipes"), "ready and recipes sent")
items = {rec[0]: rec[1] for m in of_type(msgs, "iprotos") for rec in m["l"]}
check("iron-plate" in items.values(), "item dictionary sent")
check(any(rec[1:] == ["rail", "straight-rail"] for m in of_type(msgs, "iprotos") for rec in m["l"]),
      "item records name the entity an item builds when it differs (rail -> straight-rail)")
hs_slots = of_type(msgs, "slots")
check(hs_slots and len(hs_slots[0]["l"]["main"]) == 80, "the handshake sends the inventory slot by slot")
check(of_type(msgs, "qb") and of_type(msgs, "rdet") and of_type(msgs, "techs"), "and the quickbar, recipe details and technologies")

# subscribe to a 5x5 area, nearest first
center = (0, 0)
wanted = sorted(((x, y) for x in range(-2, 3) for y in range(-2, 3)), key=lambda c: c[0] ** 2 + c[1] ** 2)
send({"t": "sub", "c": [list(c) for c in wanted]})
send({"t": "focus", "x": 0, "y": 0, "r": 48})
step(40)
msgs = take()
chunks = [(m["cx"], m["cy"]) for m in of_type(msgs, "chunk")]
check(sorted(chunks) == sorted(wanted), f"every subscribed chunk arrives once ({len(chunks)} of {len(wanted)})")
check(chunks[:1] == [(0, 0)], "nearest chunk first")
ents = [rec for m in of_type(msgs, "ents") for rec in m["e"]]
check(any(r[1] == protos["assembling-machine-1"] for r in ents), "starter base is in the snapshot")
check(any(r[1] == protos["iron-ore"] for r in ents), "ore patch is in the snapshot")
cliffs = {r[5]["co"] for r in ents if r[1] == protos["cliff"]}
check(len(cliffs) == 14, f"the cliffs round the plateau show every straight, outer and inner piece, the free one both ends: {sorted(cliffs)}")
check(of_type(msgs, "mv"), "movers are streamed")
check(of_type(msgs, "me"), "character state is streamed")
check(not of_type(msgs, "dec"), "no decoratives unless the hello asks (dc)")

# decoratives: dc in the hello sends the dictionary and every subscribed chunk again
HELLO["dc"] = 1
send(HELLO)
step(60)
dmsgs = take()
did = {rec[1]: rec[0] for m in of_type(dmsgs, "dprotos") for rec in m["l"]}
check("green-carpet-grass" in did and "small-rock" in did, f"decorative dictionary sent: {sorted(did)}")
dec = {}
for m in of_type(dmsgs, "dec"):
    dec.setdefault((m["cx"], m["cy"]), []).extend(m["l"])
check(set(dec) == set(wanted), f"every subscribed chunk's decoratives ({len(dec)} of {len(wanted)})")
n = sum(len(v) // 4 for v in dec.values())
check(n > 100 and all(v in did.values() for l in dec.values() for v in l[0::4]), f"decoratives on the grass, with dictionary ids ({n})")
del HELLO["dc"]
send(HELLO)
step(2)
take()

# items ride the starter belt south
frames = {}
for m in of_type(msgs, "bi"):
    l = m["l"]
    frames.setdefault(m["k"], {}).update({l[i]: l[i + 1:i + 4] for i in range(0, len(l), 4)})
ticks = sorted(frames)
check(len(ticks) >= 2 and frames[ticks[-1]], "belt items are streamed")
check(all(m.get("z") == 1 for m in of_type(msgs, "bi")), "delta-coded, as the hello asked (z)")
if len(ticks) >= 2:
    a, b = frames[ticks[-2]], frames[ticks[-1]]
    check(all(items.get(v[0]) for v in b.values()), "belt items use ids from the item dictionary")
    check(all(abs(v[1] - (5 * 256 + 128)) == 64 for v in b.values()), "belt items sit on the two lanes of the belt at x=5.5")
    moved = [b[u][2] - a[u][2] for u in a if u in b]
    step_y = round((ticks[-1] - ticks[-2]) * mock_server.BELT_SPEED * 256)
    check(moved and all(abs(d - step_y) <= 1 for d in moved), f"belt items keep their ids and move south at belt speed: {moved[:3]}")

# `rate` 3: belt items, movers and inserter hands less often, each saying how far apart (p), as
# the mod's rate.lua; the character's own state as often as ever.
send({"t": "rate", "l": 3})
step(125)  # movers and belt items keep their old ticks too for 120 ticks after a slow-down
take()
step(130)
rmsgs = take()
for t, every in (("bi", 48), ("mv", 16), ("ih", 12)):
    ks = sorted({m["k"] for m in of_type(rmsgs, t)})
    gaps = {b - a for a, b in zip(ks, ks[1:])}
    check(gaps == {every} and {m.get("p") for m in of_type(rmsgs, t)} == {every},
          f"rate 3: {t} every {every} ticks with p = {every} (gaps {gaps})")
me_ks = sorted({m["k"] for m in of_type(rmsgs, "me")})
check(me_ks and max(b - a for a, b in zip(me_ks, me_ks[1:])) <= 2, "rate 3: me as often as ever")
send({"t": "rate", "l": 0})
step(2)
take()

# inserter hands swing around their inserters; the sky reports the time of day
units = {r[0]: r for r in ents}
hands = [m["l"] for m in of_type(msgs, "ih")]
last = hands[-1] if hands else []
recs = [last[i:i + 4] for i in range(0, len(last), 4)]
check(len(recs) == 8, f"all eight starter inserters report a hand: {len(recs)}")
check(all(r[0] in units and math.hypot(r[1] - units[r[0]][2], r[2] - units[r[0]][3]) <= 256 + 2 for r in recs),
      "each hand is within a tile of its inserter")
check(any(r[3] for m in hands for r in [m[i:i + 4] for i in range(0, len(m), 4)]), "some hands carry items")
step(60)
later = take()
sky = of_type(later, "sky")
check(sky and 0 <= sky[-1]["d"] < 1000 and sky[-1]["n"] == 0, f"sky: daytime sent, no darkness at the start: {sky[-1:]}")
check(mock_server.darkness_at(0.5) == 0.85 and mock_server.darkness_at(0.1) == 0, "night is dark, noon is not")

# items lying on the ground next to the start, picked up with F
def ground(msgs):
    gi = of_type(msgs, "gi")
    l = gi[-1]["l"] if gi else []
    return [l[i:i + 3] for i in range(0, len(l), 3)]


lying = ground(msgs)
check(len(lying) == 12 and all(items.get(r[0]) for r in lying), f"items on the ground are streamed with item ids: {len(lying)}")
check(all(-5.1 <= r[1] / 256 <= -3.5 and 2.9 <= r[2] / 256 <= 3.9 for r in lying), "at the spill south-west of the start")
coal = game.player["inventory"].get("coal", 0)
game.player["x"], game.player["y"] = -4.3, 3.4
for _ in range(3):
    send({"t": "pickup"})
    step(9)
step(30)
msgs = take()
check(ground(msgs) == [], f"pickup takes every item in reach: {len(ground(msgs))} left")
check(of_type(msgs, "inv") and dict(map(tuple, of_type(msgs, "inv")[-1]["l"])).get("coal") == coal + 3,
      "picked-up items are in the inventory")
check(game.player["pickup"] is None, "pickup stops when the client stops repeating it")
game.player["x"], game.player["y"] = -3.0, 0.5
msgs = []

# walking east moves the character east
step(2)
start = of_type(take(), "me")[-1]
for _ in range(10):
    send({"t": "walk", "d": 4})
    step(6)
msgs = take()
end = of_type(msgs, "me")[-1]
check(end["x"] - start["x"] > 256 * 5 and abs(end["y"] - start["y"]) < 10, "walking east moves the character east")
send({"t": "walk", "d": -1})
step(2)
take()
# Walking at 20 degrees (0.055 turns) follows that line, and me says the angle
x0, y0 = game.player["x"], game.player["y"]
for _ in range(10):
    send({"t": "walk", "d": 2, "a": 55})
    step(6)
dx, dy = game.player["x"] - x0, y0 - game.player["y"]
mes = of_type(take(), "me")
check(abs(math.degrees(math.atan2(dx, dy)) - 19.8) < 1.0 and mes[-1].get("a") == 55,
      f"walking at an angle follows it: {math.degrees(math.atan2(dx, dy)):.2f} degrees, me {mes[-1:]}")
send({"t": "walk", "d": -1})
step(2)
take()
game.player["x"], game.player["y"] = x0, y0
step(2)
take()

# mine the nearest tree in reach (walk there first if needed)
me = end
trees = [r for r in ents if r[1] in (protos["tree-01"], protos["tree-02"])]
if trees:
    tree = min(trees, key=lambda r: math.hypot(r[2] - me["x"], r[3] - me["y"]))
    game.player["x"], game.player["y"] = tree[2] / 256 - 2, tree[3] / 256
    for _ in range(12):
        send({"t": "mine", "u": 0, "p": tree[1], "x": tree[2], "y": tree[3]})
        step(9)
    step(30)
    msgs = take()
    check(any(d["p"] == tree[1] and d["x"] == tree[2] for d in of_type(msgs, "del")), "mined tree is removed")
    inv = of_type(msgs, "inv")
    check(inv and any(e[0] == "wood" and e[1] >= 14 for e in inv[-1]["l"]), "wood added to the inventory")
else:
    check(False, "expected trees in the subscribed area")

# build a belt next to the character
game.player["x"], game.player["y"] = -3.0, 20.5
send({"t": "build", "item": "transport-belt", "x": -5 * 256, "y": 20 * 256 + 100, "d": 4})
step(3)
msgs = take()
adds = of_type(msgs, "add")
check(adds and adds[0]["e"][1] == protos["transport-belt"] and adds[0]["e"][2:5] == [-5 * 256 + 128, 20 * 256 + 128, 4],
      "belt built and snapped")

# fast-replace and rails
belts = game.player["inventory"]["transport-belt"]
send({"t": "build", "item": "transport-belt", "x": -5 * 256 + 128, "y": 20 * 256 + 128, "d": 8})
step(3)
msgs = take()
check(of_type(msgs, "upd") and of_type(msgs, "upd")[-1]["e"][4] == 8 and not of_type(msgs, "add")
      and game.player["inventory"]["transport-belt"] == belts, "the same belt over a belt turns it, for free")
send({"t": "build", "item": "fast-transport-belt", "x": -5 * 256 + 128, "y": 20 * 256 + 128, "d": 8})
step(3)
msgs = take()
check(of_type(msgs, "del") and of_type(msgs, "add") and of_type(msgs, "add")[0]["e"][1] == protos["fast-transport-belt"]
      and game.player["inventory"]["transport-belt"] == belts + 1, "a fast belt fast-replaces it and the old one comes back")
send({"t": "build", "item": "rail", "x": int(-1.3 * 256), "y": int(22.6 * 256), "d": 0})
step(3)
adds = of_type(take(), "add")
check(adds and adds[0]["e"][1] == protos["straight-rail"] and adds[0]["e"][2:4] == [-256, 23 * 256],
      f"rail builds a straight rail on the two-tile grid: {adds[:1]}")

# machine screens: a chest, an assembler, a furnace, reach
def find_ent(name, x, y):
    return next((r for r in ents if r[1] == protos[name] and r[2] == int(x * 256) and r[3] == int(y * 256)), None)


def open_cmd(rec):
    return {"t": "open", "u": rec[0], "p": rec[1], "x": rec[2], "y": rec[3]}


def screens(msgs, rec):
    return [m for m in of_type(msgs, "gui") if m["u"] == rec[0]]


def last_inv(msgs):
    inv = of_type(msgs, "inv")
    return {k: v for k, v in inv[-1]["l"]} if inv else {}


chest = find_ent("wooden-chest", 5.5, 10.5)
asm = find_ent("assembling-machine-1", 8.5, -2.5)
furnace = find_ent("stone-furnace", 2.0, -4.0)
lab = find_ent("lab", 16.5, 0.5)
check(chest and asm and furnace and lab, "the starter base has a chest, assembler, furnace and lab")
game.player["x"], game.player["y"] = 4.0, 9.0
step(2)
take()
plates = game.player["inventory"]["iron-plate"]
copper = game.player["inventory"].get("copper-plate", 0)
send(open_cmd(chest))
step(2)
msgs = take()
g = screens(msgs, chest)
check(g and g[0]["kind"] == "container" and dict(map(tuple, g[0]["inv"]["chest"])).get("iron-plate") == 50,
      f"chest screen with its contents: {g[:1]}")
send({"t": "take", "u": chest[0], "inv": "chest", "item": "iron-plate", "n": 20})
send({"t": "take", "u": chest[0], "item": "copper-plate", "n": 10})
send({"t": "put", "u": chest[0], "item": "wood", "n": 2})
step(2)
msgs = take()
g = screens(msgs, chest)
contents = dict(map(tuple, g[-1]["inv"]["chest"])) if g else {}
check(contents.get("iron-plate") == 30 and contents.get("copper-plate") == 20 and contents.get("wood") == 2,
      f"take and put change the chest: {contents}")
check(last_inv(msgs).get("iron-plate") == plates + 20 and last_inv(msgs).get("copper-plate") == copper + 10,
      f"and the character's inventory, at once: {last_inv(msgs)}")
step(31)
check(len(screens(take(), chest)) == 1, "the screen is re-sent twice a second")

game.player["x"], game.player["y"] = 5.0, -1.0
send(open_cmd(asm))
step(2)
msgs = take()
g = screens(msgs, asm)
check(g and g[0]["kind"] == "crafter" and g[0].get("recipe") == "iron-gear-wheel" and "electronic-circuit" in g[0].get("rl", []),
      f"assembler screen with its recipe and the recipe list: {g[:1]}")
check(not screens(msgs, chest), "opening another screen replaces the first")
send({"t": "set_recipe", "u": asm[0], "recipe": "copper-cable"})
send({"t": "put", "u": asm[0], "item": "copper-plate", "n": 5})
send({"t": "put", "u": asm[0], "item": "stone", "n": 5})
step(2)
msgs = take()
g = screens(msgs, asm)
check(g and g[-1].get("recipe") == "copper-cable" and g[-1]["inv"]["input"] == [["copper-plate", 5]] and g[-1]["inv"]["output"] == [],
      f"set_recipe empties the machine, put adds ingredients: {g[-1:]}")
check(last_inv(msgs).get("iron-gear-wheel", 0) >= 3, "the old recipe's items come back to the character")
check(any(m["text"] == "Can't put stone in there" for m in of_type(msgs, "msg")), "non-ingredients are refused")
step(70)
g = screens(take(), asm)
check(g and g[-1]["inv"]["output"] == [["copper-cable", 2]] and g[-1]["inv"]["input"] == [["copper-plate", 4]],
      f"the open assembler crafts: {g[-1:]}")
# F6: modules: one clicked within reach goes in; one asked for in a slot is shown as requested (mrq).
send({"t": "modreq", "item": "speed-module", "u": asm[0], "p": asm[1], "x": asm[2], "y": asm[3]})
send({"t": "modreq", "item": "productivity-module", "s": 2, "u": asm[0], "p": asm[1], "x": asm[2], "y": asm[3]})
step(2)
g = screens(take(), asm)
check(g and g[-1]["inv"]["modules"] == [["speed-module", 1]] and g[-1].get("mrq") == ["", "productivity-module"] and "far" not in g[-1],
      f"modreq: in reach the module goes in, a slot's request shows in mrq: {g[-1:]}")
send({"t": "modreq", "clr": 1, "u": asm[0], "p": asm[1], "x": asm[2], "y": asm[3]})
step(2)
g = screens(take(), asm)
check(g and "mrq" not in g[-1], f"modreq clr takes the requests back: {g[-1:]}")

game.player["x"], game.player["y"] = 0.0, -2.0
send(open_cmd(furnace))
step(2)
g = screens(take(), furnace)
check(g and g[0]["kind"] == "furnace" and g[0].get("recipe") == "iron-plate" and set(g[0]["inv"]) == {"input", "output", "fuel"}
      and "rl" not in g[0], f"furnace screen: {g[:1]}")
game.player["x"] = 40.0
step(31)
msgs = take()
check(any(m.get("closed") is True for m in screens(msgs, furnace)) and any(m["text"] == "Out of reach" for m in of_type(msgs, "msg")),
      "walking away closes the screen")
send(open_cmd(lab))
step(31)
msgs = take()
check(not of_type(msgs, "gui") and any(m["text"] == "Out of reach" for m in of_type(msgs, "msg")), "a lab out of reach won't open")
send(dict(open_cmd(lab), rv=1))
send({"t": "take", "u": lab[0], "item": "automation-science-pack", "n": 1})
step(31)
msgs = take()
check(screens(msgs, lab) and any(m["text"] == "Out of reach" for m in of_type(msgs, "msg")),
      "from the remote view (rv) the lab opens out of reach, for settings only")
send({"t": "close"})
game.player["x"], game.player["y"] = 14.0, 4.0
send(open_cmd(lab))
step(2)
g = screens(take(), lab)
check(g and g[0]["kind"] == "lab" and "recipe" not in g[0], f"lab screen: {g[:1]}")
send({"t": "close"})
step(31)
check(not of_type(take(), "gui"), "close stops the screen")

# combat: shoot the biters circling their nest, get bitten
game.player["x"], game.player["y"] = 72.0, 62.0
send({"t": "focus", "x": 72 * 256, "y": 62 * 256, "r": 48})
step(12)
take()
for _ in range(60):
    send({"t": "shoot", "m": 0, "x": 72 * 256, "y": 62 * 256})
    step(9)
msgs = take()
check(any(m.get("sh") == 1 for m in of_type(msgs, "me")), "me.sh is 1 while firing")
damaged = [l[i:i + 2] for l in (m["l"] for m in of_type(msgs, "hp")) for i in range(0, len(l), 2)]
check(any(0 < h < 1000 for _, h in damaged), f"hp: damaged biters report their health: {damaged[:3]}")
died = of_type(msgs, "died")
check(len(died) >= 2 and all(d["p"] in (protos["small-biter"], protos["medium-biter"]) for d in died),
      f"died: biters die when shot: {len(died)}")
after = msgs[msgs.index(died[0]) + 1:] if died else []
check(died and all(r[0] != died[0]["u"] for m in of_type(after, "mv") for r in m["l"]), "a dead biter leaves the movers")
guns = of_type(msgs, "guns")
check(guns and guns[-1]["sel"] == 1 and guns[-1]["l"][0][0] == "pistol" and 0 < guns[-1]["l"][0][2] < 10,
      f"guns: magazines get used up: {guns[-1:]}")
shots = of_type(msgs, "shot")
check(shots and all(m["g"] == "pistol" and m["a"] == "firearm-magazine" for m in shots),
      f"shot: each pistol round with its gun and ammo: {shots[:1]}")
gaps = [b["k"] - a["k"] for a, b in zip(shots, shots[1:])]
check(gaps and min(gaps) >= 15, f"shot: the pistol fires every 15 ticks at most (its cooldown): {gaps[:6]}")
send({"t": "shoot", "m": -1})
step(30)
check(of_type(take(), "me")[-1].get("sh") == 0, "shoot -1 stops firing")

# what weapons fire (mock_shots.py): shotgun pellets and a rocket fly and end, a grenade explodes
saved_guns = [list(g) for g in game.player["guns"]]
mock_shots.arm(game, ["shotgun", "rocket-launcher", "flamethrower"])
for sel in range(3):
    game.player["sel"] = sel
    for _ in range(12):
        send({"t": "shoot", "m": 0, "x": 72 * 256, "y": 62 * 256})
        step(9)
    send({"t": "shoot", "m": -1})
    step(80)
    msgs = take()
    flying = {m["p"][i + 1] for m in of_type(msgs, "pj") for i in range(0, len(m["p"]), 4)}
    ended = [e for m in of_type(msgs, "pj") for e in m["e"]]
    want = ["shotgun-pellet", "rocket", "handheld-flamethrower-fire-stream"][sel]
    check(want in flying and ended, f"pj: {want} in flight and ending: {sorted(flying)}, {len(ended) // 3} ended")
    if sel == 2:
        fires = [m["l"][i + 1] for m in of_type(msgs, "gf") for i in range(0, len(m["l"]), 5)]
        check("fire-flame" in fires and not of_type(msgs, "shot"), f"gf: the stream leaves fire-flame, and no shot for a stream gun: {fires[:3]}")
game.player["guns"], game.player["sel"] = saved_guns, 0
game.player["inventory"]["grenade"] = 2
send({"t": "throw", "item": "grenade", "x": 78 * 256, "y": 62 * 256})
step(3)
step(60)
msgs = take()
booms = [m["x"][i] for m in of_type(msgs, "pj") for i in range(0, len(m["x"]), 3)]
check(booms == ["grenade-explosion"], f"pj.x: a thrown grenade's explosion where it lands: {booms} {[m['text'] for m in of_type(msgs, 'msg')]} {game.player['x']}")
step(1300)
take()
biter = next(m for m in game.movers if m["name"] == "small-biter" and m["dead_until"] <= game.tick)
for e in game.grids["char"]["eq"]:
    e[4] = 0  # the armour's shields take damage first: empty them
game.player["x"], game.player["y"] = game.mover_state(biter)[:2]
step(1)
game.player["x"], game.player["y"] = game.mover_state(biter)[:2]
step(20)
msgs = take()
me = of_type(msgs, "me")[-1]
check(me["hp"] < me["mhp"] == 250, f"biters bite: the character's health goes down: {me['hp']} of {me.get('mhp')}")
check(any(game.player["unit"] in m["l"][::2] for m in of_type(msgs, "hp")), "and the character shows up in hp")
en = of_type(msgs, "en")
check(en and abs(en[-1]["l"][1] / 256 - game.player["x"]) < 1 and abs(en[-1]["l"][2] / 256 - game.player["y"]) < 1,
      f"en: biting biters attack the character: {en[-1:]} at {game.player['x']}, {game.player['y']}")
check("sd" in me and "msd" in me and me["msd"] == 300, f"me: the armour's shields: {me}")
game.player["x"], game.player["y"] = -3.0, 0.5
send({"t": "focus", "x": 0, "y": 0, "r": 48})
step(2)
take()

# the character's gear: its power armour's grid, putting, moving, taking, toggles; info and players
game.gear_sent = {}  # as after a handshake
step(61)
msgs = take()
eq = [m for m in of_type(msgs, "eq") if m["kind"] == "char"]
check(eq and eq[-1]["w"] == 10 and len(eq[-1]["l"]) == len(mock_server.GEAR_START) and eq[-1]["nv"] == 1 and eq[-1]["mv"] == 600,
      f"eq: the armour's grid with its equipment, night vision and two exoskeletons: {eq[-1:]}")
check(of_type(msgs, "cinfo") and of_type(msgs, "cinfo")[-1]["eqmv"] == 600, "cinfo: the exoskeletons' running bonus")
pl = of_type(msgs, "pl")
check(pl and pl[-1]["l"][0][1] == "Engineer" and pl[-1]["l"][0][6] == 900, f"pl: the other players and their characters: {pl[-1:]}")
main = game.main_slots()
fi = next(i for i, s in enumerate(main) if s and s[0] == "energy-shield-equipment") + 1
send({"t": "eq_put", "kind": "char", "fi": fi, "x": 4, "y": 6})
send({"t": "eq_move", "kind": "char", "x": 5, "y": 7, "tx": 8, "ty": 8})
send({"t": "eq_toggle", "what": "roboport", "on": 0})
step(2)
eq = [m for m in of_type(take(), "eq") if m["kind"] == "char"]
placed = [r[:3] for r in eq[-1]["l"]] if eq else []
check(["energy-shield-equipment", 8, 8] in placed and eq[-1]["rb"] == 0 and game.player["inventory"]["energy-shield-equipment"] == 1,
      f"eq_put, eq_move and eq_toggle: {placed}")
send({"t": "eq_take", "kind": "char", "x": 9, "y": 9})
step(2)
eq = [m for m in of_type(take(), "eq") if m["kind"] == "char"]
check(eq and ["energy-shield-equipment", 8, 8] not in [r[:3] for r in eq[-1]["l"]]
      and game.player["inventory"]["energy-shield-equipment"] == 2, "eq_take puts it back in the inventory")

# driving the parked car: Enter, W, A, Enter
car = next(m for m in game.movers if m["kind"] == "parked")
game.player["x"], game.player["y"] = car["x"], car["y"] - 2.0
send({"t": "enter"})
step(4)
me = of_type(take(), "me")[-1]
check(me.get("v") == car["unit"] and me.get("vs") == 0, f"enter gets into the parked car: {me}")
start_x = me["x"]
for _ in range(8):
    send({"t": "drive", "a": 1, "s": 0})
    step(9)
msgs = take()
me = of_type(msgs, "me")[-1]
check(me["x"] - start_x > 2 * 256 and me["vs"] > 0, f"accelerating drives the car east and me follows it: {(me['x'] - start_x) / 256:.1f} tiles, vs {me['vs']}")
heading = [r[4] for m in of_type(msgs, "mv") for r in m["l"] if r[0] == car["unit"]]
for _ in range(6):
    send({"t": "drive", "a": 1, "s": -1})
    step(9)
msgs = take()
turned = [r[4] for m in of_type(msgs, "mv") for r in m["l"] if r[0] == car["unit"]]
turn = (turned[-1] - heading[-1] + 500) % 1000 - 500 if heading and turned else 0
check(turn < -50, f"steering left turns the car anticlockwise: {heading[-1:]} -> {turned[-1:]}")
for _ in range(6):
    send({"t": "drive", "a": 2, "s": 0})
    step(9)
me = of_type(take(), "me")[-1]
check(me["vs"] == 0, f"braking stops the car: vs {me['vs']}")
send({"t": "drive", "a": 0, "s": 0})
send({"t": "enter"})
step(4)
me = of_type(take(), "me")[-1]
check("v" not in me and abs(me["x"] / 256 - (car["x"] + 2.0)) < 0.01, f"enter again gets out, next to the car: {me}")
game.player["x"], game.player["y"] = -3.0, 0.5
send({"t": "enter"})
step(2)
check(any(m["text"] == "No vehicle nearby" for m in of_type(take(), "msg")), "enter with no vehicle near says so")

# the UI data: slots, moving stacks, quickbar, recipe details, crafting queue, research
def main_slots(msgs):
    sl = of_type(msgs, "slots")
    return sl[-1]["l"]["main"] if sl else []


game.slots_sig = None
step(30)
slots = main_slots(take())
inv = game.player["inventory"]
check(sum(v[1] for v in slots if v and v[0] == "iron-plate") == inv["iron-plate"], "slots add up to the inventory")
wood_at = next(i for i, v in enumerate(slots) if v and v[0] == "wood") + 1
send({"t": "move", "from": "main", "fi": wood_at, "to": "main", "ti": 80})
step(2)
slots = main_slots(take())
check(slots[wood_at - 1] == 0 and slots[79][0] == "wood", f"move: a stack to another slot: {slots[79]}")
plate_at = next(i for i, v in enumerate(slots) if v and v[0] == "iron-plate") + 1
send({"t": "move", "from": "main", "fi": plate_at, "to": "main", "ti": 79, "n": 5})
step(2)
slots = main_slots(take())
check(slots[78] == ["iron-plate", 5], f"move n=5 splits a stack: {slots[78]}")
inv["iron-plate"] += 1
step(30)
slots = main_slots(take())
check(slots[78] == ["iron-plate", 5] and slots[79][0] == "wood", "the client's layout survives the inventory changing")
game.player["x"], game.player["y"] = 4.0, 9.0
send(open_cmd(chest))
send({"t": "move", "from": "main", "fi": 80, "to": "chest", "ti": 1, "u": chest[0]})
step(2)
msgs = take()
g = screens(msgs, chest)
check(main_slots(msgs)[79] == 0 and g and any(v and v[0] == "wood" for v in g[-1]["slots"]["chest"]),
      f"move into the open chest; gui carries slots: {g[-1:]}")
send({"t": "close"})
send({"t": "qb_set", "i": 3, "item": "transport-belt"})
send({"t": "qb_sel", "i": 3})
step(2)
qb = of_type(take(), "qb")
check(qb and qb[-1]["held"] == "transport-belt" and qb[-1]["l"][2] == "transport-belt", f"quickbar: set and select: {qb[-1:]}")
send({"t": "craft", "recipe": "iron-gear-wheel", "n": 3})
step(10)
cq = of_type(take(), "cq")
check(cq and cq[-1]["l"][:1] == [[1, "iron-gear-wheel", 3, 0]] or cq and cq[-1]["l"][:1] == [[1, "iron-gear-wheel", 2, 0]],
      f"cq: the crafting queue: {cq[-1:]}")
send({"t": "cancel_craft", "i": 1, "n": 99})
step(2)
cq = of_type(take(), "cq")
check(cq and cq[-1]["l"] == [], f"cancel_craft empties it: {cq[-1:]}")
game.slots_sig = game.craftable_sig = None
step(30)
craftable = dict(map(tuple, of_type(take(), "craftable")[-1]["l"]))
check(craftable.get("iron-gear-wheel") == game.player["inventory"]["iron-plate"] // 2, f"craftable counts: {craftable}")
send({"t": "research", "name": "logistics"})
send({"t": "research", "name": "electronics"})
send({"t": "research", "name": "automation"})
step(2)
msgs = take()
rs = of_type(msgs, "rs")
check(rs and rs[-1]["cur"] == "logistics" and rs[-1]["q"] == ["electronics"], f"research and its queue: {rs[-1:]}")
check(any(m["text"] == "Can't research automation" for m in of_type(msgs, "msg")), "researched technologies are refused")
send({"t": "research_cancel", "name": "electronics"})
step(600)
msgs = take()
techs = {r[0]: r[6] for m in of_type(msgs, "techs") for r in m["l"]}
check(techs.get("logistics") == 2 and techs.get("logistics-2") == 0 and of_type(msgs, "rs")[-1]["cur"] == "",
      f"finished research resends the tree: {techs}")
check(any(m.get("tech") == "logistics" for m in of_type(msgs, "msg")), "and says so, naming the technology")
check(any(l[1] == "working" for m in of_type(msgs, "rs") for l in m["labs"]), "rs: the starter lab works while research runs")

# blueprints, ghosts and planners
game.player["x"], game.player["y"] = -1.0, 24.0
take()
slots_now = game.main_slots()
slot_of = {name: i + 1 for i, v in enumerate(slots_now) if v for name in [v[0]]}
send({"t": "blueprint", "i": slot_of["blueprint"], "x": 256 * 1, "y": 256 * 26, "d": 0})
step(3)
ghosts = [m["e"] for m in of_type(take(), "add") if m["e"][1] == protos["entity-ghost"]]
check(len(ghosts) == 3 and {g[5]["gh"] for g in ghosts} == {protos["transport-belt"], protos["wooden-chest"]},
      f"blueprint places ghosts of its entities: {ghosts}")
belt_ghost = next(g for g in ghosts if g[5]["gh"] == protos["transport-belt"])
send({"t": "build", "item": "transport-belt", "x": belt_ghost[2], "y": belt_ghost[3], "d": 4})
step(3)
msgs = take()
check(any(d["u"] == belt_ghost[0] for d in of_type(msgs, "del")) and of_type(msgs, "add"), "building over a ghost replaces it")
area = {"x1": -3 * 256, "y1": 25 * 256, "x2": 3 * 256, "y2": 27 * 256}
send({"t": "decon", "i": 0, **area})
step(3)
msgs = take()
upd = [m["e"] for m in of_type(msgs, "upd")]
check(upd and all(e[5].get("d") == 1 for e in upd), f"decon marks the area: {len(upd)} entities")
gone = {d["u"] for d in of_type(msgs, "del")}
check(all(g[0] in gone for g in ghosts if g is not belt_ghost), f"decon deletes the ghosts in the area, as Factorio does: {gone}")
send({"t": "decon", "i": slot_of["deconstruction-planner"], "cancel": 1, **area})
send({"t": "upgrade", "i": slot_of["upgrade-planner"], **area})
step(3)
upd = [m["e"] for m in of_type(take(), "upd")]
check(any(e[5].get("up") == protos["fast-transport-belt"] for e in upd) and any("d" not in e[5] for e in upd),
      "cancel unmarks; upgrade marks belts with their target")
send({"t": "upgrade", "i": slot_of["upgrade-planner"], "cancel": 1, **area})
step(2)
take()
fast_belt = [e for e in game.entities.values() if e.name == "fast-transport-belt"]
send({"t": "upgrade", "i": slot_of["upgrade-planner"], "down": 1, "x1": -1000 * 256, "y1": -1000 * 256, "x2": 1000 * 256, "y2": 1000 * 256})
step(3)
take()
check(fast_belt and all(e.extra.get("up") == protos["transport-belt"] for e in fast_belt),
      f"down: 1 (right-drag) marks by the mappings the other way round ({len(fast_belt)} fast belts)")
send({"t": "upgrade", "i": slot_of["upgrade-planner"], "cancel": 1, "x1": -1000 * 256, "y1": -1000 * 256, "x2": 1000 * 256, "y2": 1000 * 256})
step(2)
take()

# exchange strings, the library, undo, super-forced build (planners.lua / history.lua)
send({"t": "bp_get", "q": 1, "i": slot_of["blueprint"]})
step(2)
bp = of_type(take(), "bp")
record = mock_server.bp_decode("".join(m["s"] for m in bp))
check(bp and bp[0]["item"] == "blueprint" and record["blueprint"]["label"] == "Belts into a chest",
      f"bp_get: the blueprint as a real exchange string: {record}")
record["blueprint"]["label"] = "Edited"
record["blueprint"]["icons"] = [{"signal": {"type": "virtual", "name": "signal-B"}, "index": 2}, {"signal": {"name": "transport-belt"}, "index": 1}]
data = mock_server.bp_encode(record)
send({"t": "bp_set", "q": 2, "i": slot_of["blueprint"], "id": 5, "part": 1, "parts": 2, "d": data[:10]})
send({"t": "bp_set", "q": 2, "i": slot_of["blueprint"], "id": 5, "part": 2, "parts": 2, "d": data[10:]})
send({"t": "bp_get", "q": 3, "i": slot_of["blueprint"]})
step(2)
msgs = take()
again = mock_server.bp_decode("".join(m["s"] for m in of_type(msgs, "bp")))
check(of_type(msgs, "bp_ok") and again["blueprint"]["label"] == "Edited", "bp_set in parts writes it back")
ic = [m.get("ic") for m in of_type(msgs, "slots")]
check(ic and [slot_of["blueprint"], [["item", "transport-belt"], ["virtual", "signal-B"]]] in (ic[-1] or []),
      f"slots carries the blueprint's icons in their order (ic): {ic[-1:]}")
send({"t": "copy", "cut": 0, "bp": 1, "to": slot_of["blueprint"], **area})
step(2)
ok = [m for m in of_type(take(), "bp_ok") if m.get("new") == 1]
send({"t": "bp_get", "q": 31, "i": slot_of["blueprint"]})
step(2)
moved = mock_server.bp_decode("".join(m["s"] for m in of_type(take(), "bp")))
check(ok and ok[-1]["i"] == slot_of["blueprint"] and moved["blueprint"]["label"] == "Edited" and moved["blueprint"]["entities"],
      "copy with to: Select new contents fills the same blueprint, its name kept")
send({"t": "blueprint", "i": slot_of["blueprint"], "x": 40 * 256, "y": 40 * 256, "d": 0, "m": 1})
step(2)
flipped = [m["e"] for m in of_type(take(), "add") if m["e"][1] == protos["entity-ghost"]]
check(flipped, "blueprint with m: 1 places a mirrored copy")
send({"t": "bp_lib"})
step(2)
bpl = of_type(take(), "bpl")
check(bpl and [r[1] for r in bpl[0]["l"]] == ["blueprint", "blueprint-book"], f"bp_lib lists the game's library: {bpl}")
send({"t": "bp_rec", "q": 4, "src": "game", "ix": 2, "to": -1})
step(2)
ok = of_type(take(), "bp_ok")
check(ok and ok[0]["i"] == -1 and ok[0]["item"] == "blueprint-book", "bp_rec to -1: the book into the cursor")
send({"t": "bp_page", "i": -1, "a": 2})
send({"t": "blueprint", "i": -1, "x": 256 * 2, "y": 256 * 30, "d": 0})
step(3)
msgs = take()
ghosts = [m["e"] for m in of_type(msgs, "add") if m["e"][1] == protos["entity-ghost"]]
hist = of_type(msgs, "hist")
check(len(ghosts) == 3 and hist and hist[-1]["what"] == "blueprint", f"the book's second page places its three ghosts: {ghosts}")
send({"t": "undo", "h": hist[-1]["h"] if hist else 0})
step(2)
check(len(of_type(take(), "del")) == 3, "undo takes them away")
send({"t": "build", "item": "wooden-chest", "x": 256 * 8 + 128, "y": 256 * 30 + 128, "d": 0, "ghost": 1, "sf": 1})
step(2)
msgs = take()
check(any(m["e"][5].get("gh") == protos["wooden-chest"] for m in of_type(msgs, "add")) and of_type(msgs, "hist"),
      "super-forced build: a ghost, undoably")

# circuit network: the starter combinators
arith = next(r for r in ents if r[1] == protos["arithmetic-combinator"])
const = next(r for r in ents if r[1] == protos["constant-combinator"])
check(arith[5].get("r") == [const[0]], "the arithmetic combinator's record lists its red wire")
game.player["x"], game.player["y"] = 15.0, 4.0
send({"t": "open", "u": arith[0], "p": arith[1], "x": arith[2], "y": arith[3]})
step(2)
g = [m for m in of_type(take(), "gui") if m["u"] == arith[0]]
check(g and g[-1]["kind"] == "combinator" and g[-1]["cb"]["operation"] == "*" and g[-1]["sig"]["r"] == [["item", "iron-plate", 10]],
      f"combinator screen: settings and the signals it sees: {g[-1:]}")
send({"t": "open", "u": const[0], "p": const[1], "x": const[2], "y": const[3]})
send({"t": "set_cb", "u": const[0], "cb": {"enabled": True, "signals": [["item", "copper-plate", 7]]}})
step(2)
g = [m for m in of_type(take(), "gui") if m["u"] == const[0]]
check(g and g[-1]["cb"]["signals"] == [["item", "copper-plate", 7]], "set_cb changes a constant combinator")
send({"t": "set_desc", "u": const[0], "text": "Outpost"})
step(2)
g = [m for m in of_type(take(), "gui") if m["u"] == const[0]]
check(g and g[-1].get("desc") == "Outpost", f"set_desc: a combinator's description: {g[-1:]}")
# Wire tools: a green wire from the constant combinator to the lamp beside it, then off again.
lamp = find_ent("small-lamp", 13.5, 2.5)
game.player["x"], game.player["y"] = 14.0, 4.0
end = lambda r: {"u": r[0], "p": r[1], "x": r[2], "y": r[3], "mx": r[2], "my": r[3]}
send({"t": "wire", "k": "g", "a": end(const), "b": end(lamp)})
step(2)
upd = {m["e"][0]: m["e"] for m in of_type(take(), "upd")}
check(upd.get(lamp[0], [0] * 6)[5:] and upd[lamp[0]][5].get("g") == [const[0]], f"wire: a green wire's ends are sent again: {upd}")
send(open_cmd(lamp))
step(2)
g = screens(take(), lamp)
check(g and g[-1]["cc"]["o"] == "lamp" and g[-1]["cc"]["w"] == 1 and g[-1]["cc"]["nets"]["g"] > 0 and g[-1].get("col") == [255, 255, 255],
      f"a wired lamp shows its circuit settings, network and colour: {g[-1:]}")
send({"t": "set_cc", "u": lamp[0], "f": {"use_colors": 1, "circuit_enable_disable": 1}})
send({"t": "set_color", "u": lamp[0], "c": [10, 20, 30]})
step(2)
g = screens(take(), lamp)
check(g and g[-1]["cc"]["f"]["use_colors"] == 1 and g[-1]["col"] == [10, 20, 30], f"set_cc and set_color: {g[-1:]}")
send({"t": "set_lamp", "u": lamp[0], "ao": 1})
step(2)
g = screens(take(), lamp)
check(g and g[-1].get("ao") == 1, f"set_lamp: a lamp's Always on: {g[-1:]}")
send({"t": "wire", "k": "g", "a": end(const), "b": end(lamp)})
step(2)
upd = {m["e"][0]: m["e"] for m in of_type(take(), "upd")}
check(lamp[0] in upd and "g" not in (upd[lamp[0]][5:] or [{}])[0], "the same wire again removes it")
send({"t": "close"})
game.player["x"], game.player["y"] = -3.0, 0.5
step(2)
take()

# map: charts and tags
send({"t": "map", "cx1": 0, "cy1": 0, "cx2": 0, "cy2": 0, "res": 2})
send({"t": "map", "cx1": 9, "cy1": 0, "cx2": 10, "cy2": 0, "res": 2})
step(2)
msgs = take()
check(not [m for m in of_type(msgs, "chart") if (m["cx"], m["cy"]) == (0, 0)], "a new map request replaces the last one")
charts = {(m["cx"], m["cy"]): m for m in of_type(msgs, "chart")}
check(charts.get((10, 0), {}).get("n") == 0, "chunks far from the start aren't charted")
send({"t": "map", "cx1": 0, "cy1": 0, "cx2": 0, "cy2": 0, "res": 2})
step(2)
msgs = take()
c00 = next((m for m in of_type(msgs, "chart") if (m["cx"], m["cy"]) == (0, 0)), None)
check(c00 and c00["n"] == 16 and c00["pal"][c00["px"][1 * 16 + 2]] == [250, 200, 40],
      f"the starter belt is on the map: {c00 and c00['pal']}")
check(of_type(msgs, "tags"), "a map request sends the tags")
send({"t": "map", "cx1": -1, "cy1": -1, "cx2": 0, "cy2": 0, "res": 4})
step(3)
ov = [r for m in of_type(take(), "chart") for r in m.get("ov", [])]
check(any(r[0] == "e" and r[3] == 2.5 for r in ov), f"charts carry the map view's layers (poles): {ov[:4]}")
send({"t": "unghost", "q": 3, "x": 300 * 256, "y": 300 * 256})
step(1)
check([(m["q"], m["n"]) for m in of_type(take(), "unghost")] == [(3, 0)], "unghost with no ghost there answers n = 0")
# The hover panel's beacon effects (`hinfo`), with --beacon's beacon by the starter assemblers.
hb = game.add(mock_server.Entity(game._unit(), "beacon", 8.5, -6.5))
send({"t": "hinfo", "q": 6, "u": hb.unit, "p": 0, "x": 0, "y": 0})
send({"t": "hinfo", "q": 7, "u": find_ent("assembling-machine-1", 8.5, -2.5)[0], "p": 0, "x": 0, "y": 0})
step(1)
hi = {m["q"]: m for m in of_type(take(), "hinfo")}
check(hi.get(6, {}).get("eff") == {"sp": 1000, "co": 1400} and hi[6].get("n") == 1 and hi[6].get("m") == [["speed-module-3", 2]]
      and hi.get(7, {}).get("b") == 1 and hi[7].get("eff") == {"sp": 1500, "co": 2100},
      f"hinfo: a beacon's effects and the machines it reaches, a machine's beacons: {hi}")
el = hi.get(7, {}).get("el", {})
check(el.get("mx") == 77500 and el.get("mn") == 2500 and el.get("b", 0) > 0 and 0 <= el.get("e", -1) <= el["b"]
      and hi.get(6, {}).get("el", {}).get("mn") == 0,
      f"hinfo: an assembler's and a beacon's electricity (H20): {hi}")
game.remove(hb)
rp = game.add(mock_server.Entity(game._unit(), "roboport", 60.0, -6.0))
send({"t": "hinfo", "q": 8, "u": game.roboport.unit, "p": 0, "x": 0, "y": 0})
step(1)
hr = {m["q"]: m for m in of_type(take(), "hinfo")}.get(8, {})
check(hr.get("rn") == [60 * 256, -6 * 256], f"hinfo: a roboport's links to the roboports beside it (H14): {hr}")
game.remove(rp)
step(1)
take()
send({"t": "cmd", "id": 4, "text": "/version"})
send({"t": "cmd", "id": 5, "text": "/editor"})
step(1)
cmdr = {m["id"]: m for m in of_type(take(), "cmdr")}
check(cmdr.get(4, {}).get("l") == ["2.1.23"] and cmdr.get(5, {}).get("ok") == 0, f"cmd: the mock answers the bridge's console commands: {cmdr}")
send({"t": "mtr"})
step(1)
mtr = of_type(take(), "mtr")
check(mtr and len(mtr[-1]["l"]) == 18 and mtr[-1]["l"][5] == 0xEB1200, f"mtr: the mock's train, three carriages: {mtr[-1:]}")
send({"t": "mrp", "q": 2})
send({"t": "lpad", "si": 1, "q": 3})
step(1)
msgs = take()
rp = of_type(msgs, "mrp")
check(rp and rp[-1]["last"] == 1 and rp[-1]["q"] == 2 and rp[-1]["l"][:4] == [22 * 256, -6 * 256, 25 * 256, 55 * 256],
      f"mrp: the mock's roboport with its logistic and construction radius: {rp[-1:]}")
lp = of_type(msgs, "lpad")
check(lp and lp[-1]["q"] == 3 and (lp[-1].get("x"), lp[-1].get("y")) == (-6 * 256, -21 * 256),
      f"lpad: Nauvis' landing pad: {lp[-1:]}")
send({"t": "tag_add", "x": 5 * 256, "y": 6 * 256, "text": "belt", "icon": ["item", "transport-belt"]})
send({"t": "tag_add", "x": 500 * 256, "y": 0, "text": "far"})
step(2)
msgs = take()
tags = of_type(msgs, "tags")
check(tags and tags[-1]["l"] == [[1, 5 * 256, 6 * 256, "belt", "item", "transport-belt"]], f"tag_add: {tags[-1:]}")
check(any("Can't put a tag there" in m["text"] for m in of_type(msgs, "msg")), "no tags where it isn't charted")
send({"t": "tag_del", "id": 1})
step(2)
tags = of_type(take(), "tags")
check(tags and tags[-1]["l"] == [], "tag_del removes it")
send({"t": "map", "cx1": -1, "cy1": -1, "cx2": 0, "cy2": 0, "res": 4, "si": 2})
send({"t": "tag_add", "x": 3 * 256, "y": 3 * 256, "text": "hub", "si": 2})
step(3)
msgs = take()
charts = [m for m in of_type(msgs, "chart") if m.get("si") == 2 and m["n"] > 0]
tags = of_type(msgs, "tags")
check(len(charts) == 4 and tags and tags[-1]["si"] == 2 and tags[-1]["l"][0][3] == "hub",
      f"the map of the platform from Nauvis (si 2), with its own tags: {len(charts)} charts, {tags[-1:]}")

# two clients at once: the second on its own port gets its own handshake, character and chunks,
# and each sees the other's character as a mover
client2 = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
client2.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, 8 * 1024 * 1024)
client2.bind(("127.0.0.1", 0))
client2.setblocking(False)


def take2():
    out = []
    while True:
        try:
            data, _ = client2.recvfrom(65536)
        except BlockingIOError:
            return out
        msg = json.loads(data)
        for problem in protocol.problems(msg):
            check(False, f"protocol (second client): {problem}")
        out.append(msg)


take()
client2.sendto(json.dumps({"t": "hello", "v": 1, "sid": "second", "w": 0}).encode(), server)
step(3)
msgs2 = take2()
w2 = of_type(msgs2, "welcome")
check(w2 and w2[0]["u"] != game.player["unit"] and of_type(msgs2, "protos") and not of_type(take(), "welcome"),
      f"a second client gets its own welcome and character; the first gets no new handshake: {w2}")
client2.sendto(json.dumps({"t": "sub", "c": [[0, 0]]}).encode(), server)
client2.sendto(json.dumps({"t": "focus", "x": 0, "y": 0, "r": 48}).encode(), server)
msgs1, msgs2 = [], []
for _ in range(10):
    client2.sendto(json.dumps({"t": "hello", "v": 1, "sid": "second", "w": 1}).encode(), server)
    step(6)
    # Both read every few ticks: Linux caps a socket's receive buffer near 208 KB, and a client
    # that waits too long loses datagrams (a "sequence gap" in CI).
    msgs1 += take()
    msgs2 += take2()
check(of_type(msgs2, "chunk") and not of_type(msgs1, "chunk"), "each client gets the chunks it subscribed to")
mv2 = [m for m in of_type(msgs2, "mv")]
seen2 = set()
for m in mv2:
    prev = [0, 0, 0, 0]
    for r in m["l"]:
        if m.get("z") == 1:
            r = [p + d for p, d in zip(prev, r[:4])] + r[4:]
            prev = r[:4]
        seen2.add(r[0])
seen1 = {r[0] for m in of_type(msgs1, "mv") for r in m["l"]}  # take() already decoded the first client's
check(game.player["unit"] in seen2 and w2[0]["u"] in seen1, f"each sees the other's character as a mover")
client2.sendto(json.dumps({"t": "bye"}).encode(), server)
step(2)
check(not game.extras, "bye drops the second client only")
check(game.client is not None, "and the first stays")
client2.close()

# trains: stops, tr, train screens and schedules
west = game.entities[next(k for k, e in game.entities.items() if e.name == "train-stop" and e.extra.get("n") == "West")]
loco = game.mover_entity(700)
game.player["x"], game.player["y"] = loco.x, loco.y - 3
send({"t": "focus", "x": int(loco.x * 256), "y": int(loco.y * 256), "r": 48})
step(31)
msgs = take()
tr = of_type(msgs, "tr")
check(tr and tr[-1]["l"] and tr[-1]["l"][0][6] == [700, 701, 702] and tr[-1]["l"][0][5] in ("East", "West"),
      f"tr: the train near the focus, its carriages and where it is heading: {tr[-1:]}")
# The 3D remote view far from the character: the train runs through the starter roboport's
# construction area, which counts as seen (H13); with the roboport away no radar sees it.
game.player["x"] -= 300
send({"t": "focus", "x": int(loco.x * 256), "y": int(loco.y * 256), "r": 48, "rv": 1})
step(62)
units = {rec[0] for m in of_type(take(), "mv") for rec in m["l"]}
check(700 in units, f"remote view: movers in a roboport's construction area are sent: {sorted(units)[:5]}")
robo_x = game.roboport.x
game.roboport.x = 5000.0
step(62)
msgs = take()
units = {rec[0] for m in of_type(msgs, "mv") for rec in m["l"]}
cov = of_type(msgs, "cov")
check(700 not in units and cov and cov[-1]["l"] == [] and cov[-1]["cr"] == 96,
      f"remote view: movers no radar sees aren't sent, and cov says what is seen: {sorted(units)[:5]} {cov[-1:]}")
game.roboport.x = robo_x
send({"t": "focus", "x": int(loco.x * 256), "y": int(loco.y * 256), "r": 48})
step(4)
check(700 in {rec[0] for m in of_type(take(), "mv") for rec in m["l"]}, "outside the remote view the train is sent again")
game.player["x"] += 300
loco = game.mover_entity(700)
game.player["x"], game.player["y"] = loco.x, loco.y - 3
send({"t": "open", "u": 700, "p": protos["locomotive"], "x": int(loco.x * 256), "y": int(loco.y * 256)})
step(2)
g = [m for m in of_type(take(), "gui") if m["u"] == 700]
check(g and g[-1]["kind"] == "train" and g[-1]["tr"]["sched"]["records"][0]["station"] == "East" and g[-1]["inv"]["fuel"] == [["coal", 20]],
      f"a locomotive's screen: schedule and fuel: {g[-1:]}")
records = [{"station": "West", "wait_conditions": [{"type": "full", "compare_type": "or"}]}]
send({"t": "set_schedule", "u": 700, "records": records})
send({"t": "train_mode", "u": 700, "auto": 0})
send({"t": "set_stop", "u": 700, "name": "nope"})
game.player["x"], game.player["y"] = game.mover_entity(700).x, loco.y - 3
step(2)
msgs = take()
g = [m for m in of_type(msgs, "gui") if m["u"] == 700]
check(g and g[-1]["tr"]["sched"]["records"] == records and g[-1]["tr"]["manual"] == 1, f"set_schedule and train_mode: {g[-1:]}")
check(any(m["text"] == "That isn't a train stop" for m in of_type(msgs, "msg")), "set_stop on a train is refused")
check(g and g[-1]["tr"]["cargo"] and g[-1]["tr"]["fuel"] == [["coal", 20]] and "East" in g[-1]["tr"]["stops"] and len(g[-1]["tr"]["pos"]) == 2,
      "a train's screen: its cargo, fuel, the stops to go to and where it is")
send({"t": "set_interrupts", "u": 700, "interrupts": [{"name": "Fuel", "conditions": [{"type": "fuel_item_count_any", "compare_type": "and"}],
                                                       "targets": [{"station": "East"}], "inside_interrupt": False}]})
send({"t": "train_temp", "u": 700, "station": "East"})
game.player["x"], game.player["y"] = game.mover_entity(700).x, game.mover_entity(700).y - 3
step(2)
g = [m for m in of_type(take(), "gui") if m["u"] == 700]
sch = g[-1]["tr"]["sched"] if g else {}
check(sch.get("interrupts") and sch["interrupts"][0]["name"] == "Fuel" and sch["records"][sch["current"] - 1].get("temporary"),
      f"set_interrupts and train_temp: {sch}")
send({"t": "trains_list"})
step(1)
trl = of_type(take(), "trl")
check(trl and trl[-1]["l"][0][0] == 1 and trl[-1]["l"][0][6] == 700, f"trains_list: the overview (trl): {trl}")
send({"t": "set_schedule", "u": 700, "records": records})
send({"t": "train_mode", "u": 700, "auto": 1})
game.player["x"], game.player["y"] = west.x, west.y + 2
send({"t": "open", "u": west.unit, "p": protos["train-stop"], "x": int(west.x * 256), "y": int(west.y * 256)})
send({"t": "set_stop", "u": west.unit, "name": "Smelting", "limit": 1})
step(2)
g = [m for m in of_type(take(), "gui") if m["u"] == west.unit]
st = g[-1]["stop"] if g else {}
check(g and g[-1]["kind"] == "stop" and st["name"] == "Smelting" and st["limit"] == 1 and st["count"] == 0 and st["pri"] == 50,
      f"a train stop's screen and set_stop: {g[-1:]}")
send({"t": "set_stop", "u": west.unit, "pri": 70, "cb": {"en": 1, "send": 0}})
step(2)
st = [m for m in of_type(take(), "gui") if m["u"] == west.unit][-1]["stop"]
check(st["pri"] == 70 and st["cb"]["en"] == 1 and st["cb"]["send"] == 0, f"set_stop: priority and circuit settings: {st}")
send({"t": "close"})
game.player["x"], game.player["y"] = -3.0, 0.5
send({"t": "focus", "x": -3 * 256, "y": 128, "r": 48})
step(2)
take()

# logistics: the character's requests, the network, chests, the roboport, robot cargo
clog = of_type(hs_msgs, "clog")
check(clog and clog[-1]["on"] == 1 and clog[-1]["trash"] == 0 and clog[-1]["l"] == [] and len(clog[-1]["sec"]) == 1,
      f"clog comes with the handshake, with its one section: {clog}")
check(of_type(hs_msgs, "ccol") and of_type(hs_msgs, "ccol")[-1]["c"] == [255, 161, 66], "ccol: the character's colour at the handshake")
send({"t": "set_char_color", "c": [20, 40, 250]})
step(2)
check(of_type(take(), "ccol")[-1:] and game.char_color == [20, 40, 250], "set_char_color changes the character's colour")
send({"t": "set_section", "u": 0, "i": 0, "g": "Mall"})
step(2)
clog = of_type(take(), "clog")
check(clog and [x["g"] for x in clog[-1]["sec"]] == ["", "Mall"], f"set_section u=0 adds a character section: {clog[-1:]}")
send({"t": "set_section", "u": 0, "i": 2, "del": 1})
step(2)
clog = of_type(take(), "clog")
check(clog and len(clog[-1]["sec"]) == 1, "and del removes it")
send({"t": "set_char_requests", "l": [["iron-plate", 50, 100]], "trash": 1})
step(2)
clog = of_type(take(), "clog")
check(clog and clog[-1]["l"] == [["iron-plate", 50, 100]] and clog[-1]["trash"] == 1, f"set_char_requests: {clog}")
req = next(r for r in ents if r[1] == protos["requester-chest"])
sto = next(r for r in ents if r[1] == protos["storage-chest"])
port = next(r for r in ents if r[1] == protos["roboport"])
game.player["x"], game.player["y"] = 20.0, -1.0
send({"t": "focus", "x": 20 * 256, "y": -1 * 256, "r": 48})
send({"t": "open", "u": req[0], "p": req[1], "x": req[2], "y": req[3]})
send({"t": "set_requests", "u": req[0], "l": [["iron-gear-wheel", 20, -1]]})
step(61)
msgs = take()
g = [m for m in of_type(msgs, "gui") if m["u"] == req[0]]
check(g and g[-1]["lg"]["requests"] == [["iron-gear-wheel", 20, -1]] and g[-1]["lg"]["net"]["items"][0] == ["iron-plate", 120],
      f"a requester chest: requests and the network's contents: {g[-1:]}")
ln = of_type(msgs, "ln")
check(ln and ln[-1]["id"] == 1 and ln[-1]["log"] == [3, 3], f"ln inside the roboport's area: {ln[-1:]}")
check(any(m["l"] for m in of_type(msgs, "rc")), "rc: shuttling robots carry plates")
send({"t": "open", "u": sto[0], "p": sto[1], "x": sto[2], "y": sto[3]})
send({"t": "set_storage_filter", "u": sto[0], "item": "copper-plate"})
step(2)
g = [m for m in of_type(take(), "gui") if m["u"] == sto[0]]
check(g and g[-1]["lg"] == dict(g[-1]["lg"], mode="storage", filter="copper-plate"), f"a storage chest's filter: {g[-1:]}")
send({"t": "open", "u": port[0], "p": port[1], "x": port[2], "y": port[3]})
step(2)
g = [m for m in of_type(take(), "gui") if m["u"] == port[0]]
check(g and g[-1]["kind"] == "roboport" and g[-1]["inv"]["robots"] == [["logistic-robot", 3]], f"the roboport's screen: {g[-1:]}")
send({"t": "close"})
game.player["x"], game.player["y"] = -3.0, 0.5
send({"t": "focus", "x": -3 * 256, "y": 128, "r": 48})
step(2)
take()

# fluids, wires and power
fids = {rec[1]: rec[0] for rec in [r for m in of_type(hs_msgs, "fprotos") for r in m["l"]]}
check({"water", "steam"} <= set(fids), "fluid prototypes are sent")
poles = [r for r in ents if r[1] == protos["small-electric-pole"]]
check(len(poles) == 3 and all(len(r) == 6 and r[5].get("w") for r in poles), "poles list their copper wires")
game.player["x"], game.player["y"] = -9.0, -9.0
send({"t": "focus", "x": -9 * 256, "y": -9 * 256, "r": 48})
step(61)
msgs = take()
fl = of_type(msgs, "fl")[-1]["l"] if of_type(msgs, "fl") else []
boxes = [fl[i:i + 6] for i in range(0, len(fl), 6)]
check(any(b[2] == fids["steam"] and b[5] == 165 for b in boxes) and any(b[2] == fids["water"] for b in boxes),
      f"fl: water in the pipes and boiler, steam at 165 degrees: {boxes[:3]}")
pipes = [r for r in ents if r[1] == protos["pipe"]]
check(sorted(r[5].get("pc") for r in pipes) == [4, 5, 5, 5], f"pipes say which sides connect (north and south, the open end only south): {[r[5] for r in pipes]}")
ht = of_type(msgs, "ht")[-1]["l"] if of_type(msgs, "ht") else []
check(len(ht) == 8 and ht[1] == 600, f"ht: heat pipe temperatures: {ht}")
pw = of_type(msgs, "pw")[-1]["l"] if of_type(msgs, "pw") else []
check(2 in pw[1::2], f"pw: 2 for the lamp nobody wired up: {pw}")
boiler = next(r for r in ents if r[1] == protos["boiler"])
send({"t": "open", "u": boiler[0], "p": boiler[1], "x": boiler[2], "y": boiler[3]})
step(2)
g = [m for m in of_type(take(), "gui") if m["u"] == boiler[0]]
check(g and g[-1].get("fb", [[None]])[0][0] == "water" and g[-1].get("status") == "working", f"gui: the boiler's fluid boxes: {g[-1:]}")
send({"t": "close"})
# A whole low-power cycle (low_power_now), whatever tick this starts on, read as it goes: 20 s
# unread overflow a CI runner's receive buffer.
pw = []
for _ in range(20):
    step(60)
    pw += [m["l"] for m in of_type(take(), "pw")]
check(any(l[1:2] == [1] for l in pw), f"pw: an assembler runs low on power now and then: {pw[-1:]}")
game.player["x"], game.player["y"] = -3.0, 0.5
send({"t": "focus", "x": 0, "y": 0, "r": 48})
step(2)
take()

# the space platform: up, its deck, a trip, back down
tile_ids = {rec[1]: rec[0] for m in of_type(hs_msgs, "tprotos") for rec in m["l"]}
step(60)
pm = of_type(take(), "plat")
check(pm and pm[-1]["on"] == 0 and pm[-1]["here"] == "nauvis" and pm[-1]["l"][0]["loc"] == "nauvis",
      f"plat: the mock's platform waits in orbit: {pm[-1:]}")
# H7: waiting at its stop with another next (nx), then done there and held for
# cargo on its way (waiting_for_departure), still at its stop.
game.platform.update(sched={"c": 1, "l": ["nauvis", "vulcanus"]}, pa=0, hold=True)
step(60)
rec = of_type(take(), "plat")[-1]["l"][0]
check(rec["st"] == "waiting_at_station" and rec["loc"] == "nauvis" and rec.get("nx") == "vulcanus",
      f"plat: waiting at Nauvis, Vulcanus next: {rec}")
game.platform["sched"]["c"] = 2
step(60)
rec = of_type(take(), "plat")[-1]["l"][0]
check(rec["st"] == "waiting_for_departure" and rec["loc"] == "nauvis" and rec.get("nx") == "vulcanus" and "to" not in rec,
      f"plat: done at Nauvis, held for its cargo before leaving for Vulcanus: {rec}")
game.platform.update(sched=None, pa=1, hold=False)
send({"t": "plat_board", "i": 1})
step(2)
msgs = take()
surf = of_type(msgs, "surface")
check(surf and surf[0]["pf"] == 1 and surf[0]["surface"] == "platform-1" and of_type(msgs, "plat")[-1]["on"] == 1,
      f"plat_board: surface, then plat with on = 1: {surf}")
send({"t": "sub", "c": [[0, 0], [-1, -1]]})
send({"t": "focus", "x": 0, "y": 0, "r": 48})
step(10)
msgs = take()
tiles = {t for m in of_type(msgs, "chunk") for t in m["tiles"][0::2]}
hub = [e for m in of_type(msgs, "ents") for e in m["e"] if e[1] == protos["space-platform-hub"]]
check(tiles == {tile_ids["space-platform-foundation"], tile_ids["empty-space"]} and len(hub) == 1,
      f"the platform's chunks: foundation, empty space and the hub: {tiles} {hub}")
asteroids = [r for m in of_type(msgs, "mv") for r in m["l"] if r[1] == protos["medium-metallic-asteroid"]]
check(asteroids and not [m for m in of_type(msgs, "bi") if m["l"]], f"asteroids fly past as movers, and no belt items from the planet: {len(asteroids)}")
send({"t": "plat_go", "i": 1, "to": "vulcanus"})
step(60 * 16)
rec = of_type(take(), "plat")[-1]["l"][0]
check(rec["st"] == "on_the_path" and rec["from"] == "nauvis" and rec["to"] == "vulcanus" and 400 < rec["d"] < 600,
      f"plat_go: the platform travels: {rec}")
send({"t": "plat_board", "i": 0})
step(1)
check(any(m["text"] == "The platform must be stopped at a planet to drop to it" for m in of_type(take(), "msg")),
      "plat_board 0 is refused while travelling")
send({"t": "plat_go", "i": 1, "to": "nauvis"})
send({"t": "plat_pause", "i": 1, "p": 1})
step(61)
rec = of_type(take(), "plat")[-1]["l"][0]
check(rec["st"] == "paused" and rec["sch"] == {"c": 1, "l": ["nauvis"]}, f"plat_pause and the new destination: {rec}")
game.platform.update(loc="nauvis", to=None, d=0.0)
game.platform["from"] = None
send({"t": "plat_board", "i": 0})
step(2)
surf = of_type(take(), "surface")
check(surf and surf[0].get("planet") == "nauvis" and game.surface == "nauvis", f"plat_board 0 drops back to the planet: {surf}")
# Riding up and life in the hub, then down by cargo pod, on the mock's short timeline.
send({"t": "ride", "u": 0, "to": 1})
step(4)
msgs = take()
me = of_type(msgs, "me")
check(me and me[-1].get("ps") == "awaiting_launch" and me[-1].get("up") == 1 and of_type(msgs, "rk"),
      f"ride: into the rocket's pod (me.pod, up 1) and the launch (rk): {me[-1:]}")
step(sum(n for _, n in mock_server.RIDE_UP[:2]) - 4)
me = of_type(take(), "me")
check(me and (me[-1]["gy"] - me[-1]["y"]) / 256 > 150, f"ride: the pod climbs north of the silo: {me[-1:]}")
step(sum(n for _, n in mock_server.RIDE_UP[2:]) + 4)
msgs = take()
surf = of_type(msgs, "surface")
me = of_type(msgs, "me")
check(surf and surf[0]["pf"] == 1 and me and me[-1].get("hub") and "pod" not in me[-1] and any(m.get("ps") == "parking" for m in me),
      f"ride: onto the platform and into its hub (me.hub): {surf} {me[-1:]}")
send({"t": "walk", "d": 4})
send({"t": "mine", "u": 0, "p": 0, "x": 0, "y": 0})
step(10)
msgs = take()
check(of_type(msgs, "me")[-1]["x"] == 0 and any(m["text"] == "Not from inside the hub" for m in of_type(msgs, "msg")),
      "in the hub: no walking or mining")
send({"t": "land"})
step(sum(n for _, n in mock_server.RIDE_DOWN) + 4)
msgs = take()
me = of_type(msgs, "me")
check(any(m.get("up") == 0 and m.get("ps") == "descending" for m in me) and "pod" not in me[-1] and "hub" not in me[-1]
      and of_type(msgs, "surface")[-1]["planet"] == "nauvis", f"land: from the hub down to Nauvis in a cargo pod: {me[-1:]}")
game.player["x"], game.player["y"] = -3.0, 0.5
send({"t": "sub", "c": [list(c) for c in wanted]})
send({"t": "focus", "x": 0, "y": 0, "r": 48})
step(80)
take()

# Factorio's world controls and entity windows: drop, fast transfer, settings, clipboard, Alt-mode,
# chat, statistics, inserter / splitter / chest bar screens
game.player["x"], game.player["y"] = 7.0, 0.0
step(2)
take()
ins = find_ent("inserter", 6.5, -2.5)
send(open_cmd(ins))
step(2)
g = screens(take(), ins)
check(g and g[-1]["kind"] == "inserter" and g[-1]["ins"]["n"] == 5, f"an inserter's screen with its filters: {g[-1:]}")
send({"t": "set_inserter", "u": ins[0], "f": ["iron-plate"], "m": "blacklist", "use": 1, "st": 2})
step(2)
g = screens(take(), ins)
check(g and g[-1]["ins"]["f"][0] == "iron-plate" and g[-1]["ins"]["m"] == "blacklist" and g[-1]["ins"]["st"] == 2,
      f"set_inserter: {g[-1:]}")
send({"t": "alt", "on": 1})
step(61)
ai = of_type(take(), "ai")
check(ai and [ins[0], "item", "iron-plate"] in ai[-1]["l"] and any(r[1] == "recipe" for r in ai[-1]["l"]),
      f"Alt-mode icons: recipes and inserter filters: {ai[-1:]}")
send({"t": "set_inserter", "u": ins[0], "f": ["iron-plate", "", "coal"], "m": "blacklist", "use": 1, "st": 2})
step(61)
ai = of_type(take(), "ai")
check(ai and [ins[0], "item", "iron-plate", ["coal"]] in ai[-1]["l"], f"Alt-mode: every filter of an inserter: {ai[-1:]}")
send({"t": "set_inserter", "u": ins[0], "f": ["iron-plate"], "m": "blacklist", "use": 1, "st": 2})
send({"t": "alt", "on": 0})
plates = game.player["inventory"]["iron-plate"]
send({"t": "fast", "u": asm[0], "p": asm[1], "x": asm[2], "y": asm[3]})
step(2)
check(last_inv(take()).get("iron-gear-wheel", 0) > 0, "Ctrl+click takes an assembler's output")
send({"t": "alt", "on": 1})
send(open_cmd(asm))
send({"t": "set_recipe", "u": asm[0], "recipe": ""})
step(61)
ai = of_type(take(), "ai")
check(ai and all(r[0] != asm[0] for r in ai[-1]["l"]), f"Alt-mode: nothing over a machine with no recipe: {ai[-1:]}")
send({"t": "set_recipe", "u": asm[0], "recipe": "iron-gear-wheel"})
step(2)
take()
plate_slot = next(i + 1 for i, v in enumerate(game.main_slots()) if v and v[0] == "iron-plate")
before = game.player["inventory"].get("iron-plate", 0)
send({"t": "xfer", "from": "main", "fi": plate_slot, "k": "half", "u": asm[0]})
step(2)
take()
moved = before - game.player["inventory"].get("iron-plate", 0)
check(moved > 0, f"xfer half (Shift+right click) puts part of the stack into the open machine: {moved}")
plates -= moved
send({"t": "close"})
send({"t": "alt", "on": 0})
step(2)
take()
send({"t": "drop", "item": "iron-plate", "x": 8 * 256, "y": 0})
step(2)
check(game.player["inventory"]["iron-plate"] == plates - 1 and game.ground[-1][0] == "iron-plate", "Z drops one item")
send({"t": "copy", "x1": 6 * 256, "y1": -4 * 256, "x2": 11 * 256, "y2": -1 * 256, "cut": 0, "bp": 0})
step(2)
clip = of_type(take(), "clip")
check(clip and {r[0] for r in clip[-1]["l"]} >= {protos["assembling-machine-1"], protos["inserter"]}, f"copy: {clip[-1:]}")
send({"t": "paste", "x": 40 * 256, "y": 40 * 256, "d": 4})
step(2)
ghosts = [m["e"] for m in of_type(take(), "add") if m["e"][1] == protos["entity-ghost"]]
check(len(ghosts) == len(clip[-1]["l"]) if clip else False, f"paste places ghosts: {ghosts}")
asm_ghost = next((g for g in ghosts if g[5]["gh"] == protos["assembling-machine-1"]), None)
check(asm_ghost and asm_ghost[2] % 256 == 128 and asm_ghost[3] % 256 == 128, f"a pasted 3x3 machine sits on its tiles: {asm_ghost}")
send({"t": "chat", "text": "hi"})
send({"t": "stats", "kind": "item", "prec": 3})
step(2)
msgs = take()
check(any(m["text"] == "hi" for m in of_type(msgs, "chat")), "chat echoes")
st = of_type(msgs, "stats")
check(st and st[-1]["kind"] == "item" and st[-1]["l"][0][0] == "iron-plate", f"statistics: {st[-1:]}")
send({"t": "stats", "kind": "pollution", "prec": 2, "si": 0, "g": []})
send({"t": "pedia_index"})
send({"t": "pedia", "kind": "item", "name": "stone-furnace"})
send({"t": "pedia", "kind": "technology", "name": "automation"})
send({"t": "pedia", "kind": "item", "name": "nothing"})
send({"t": "lnets"})
send({"t": "lnet", "id": 2})
step(61 - game.tick % 60)
msgs = take()
st = of_type(msgs, "stats")
check(st and st[-1]["kind"] == "pollution" and st[-1]["si"] == 0 and len(st[-1]["gr"]) >= 1 and len(st[-1]["gr"][0][1]) == 60,
      f"pollution statistics with graph lines: {st[-1:]}")
pidx = [r for m in of_type(msgs, "pidx") for r in m["l"]]
check(any(r[:2] == ["item", "iron-plate"] for r in pidx) and any(r[0] == "technology" for r in pidx), f"pidx: {pidx[:4]}")
pages = {(m["kind"], m["name"]): m for m in of_type(msgs, "pedia")}
furnace = pages.get(("item", "stone-furnace"), {}).get("d", {})
check(furnace.get("entity", {}).get("hp") == 200 and furnace.get("made") == ["stone-furnace"], f"pedia item page: {furnace}")
check(pages.get(("item", "nothing"), {}).get("found") == 0 and pages.get(("technology", "automation"), {}).get("found") == 1,
      "pedia: unknown pages answer found 0")
nets = of_type(msgs, "lnets")
check(nets and len(nets[-1]["l"]) == 2, f"lnets: {nets[-1:]}")
check(any(m["id"] == 2 and m["items"][0] == ["iron-plate", 1200] for m in of_type(msgs, "lnet")), "lnet: a network's items")
al = of_type(msgs, "al")
check(al and any(a[0] == "no_ammo" and a[2][0][3] == "gun-turret" for a in al[-1]["l"]) and any(a[0] == "destroyed" for a in al[-1]["l"]), f"al: {al[-1:]}")
spl = find_ent("splitter", 22.0, 4.5)
game.player["x"], game.player["y"] = 20.0, 4.0
send(open_cmd(spl))
send({"t": "set_splitter", "u": spl[0], "i": "left", "o": "right", "f": "iron-plate"})
step(2)
g = screens(take(), spl)
check(g and g[-1]["spl"] == {"i": "left", "o": "right", "f": "iron-plate"}, f"set_splitter: {g[-1:]}")
game.player["x"], game.player["y"] = 4.0, 9.0
send(open_cmd(chest))
send({"t": "set_bar", "u": chest[0], "n": 6})
step(2)
g = screens(take(), chest)
check(g and g[-1].get("bar") == 6, f"set_bar: {g[-1:]}")
car = next(m for m in game.movers if m["unit"] == 601)  # parked wherever the driving checks left it
game.player["x"], game.player["y"] = car["x"] + 2, car["y"]
send({"t": "open", "u": 601, "p": protos["car"], "x": int(car["x"] * 256), "y": int(car["y"] * 256)})
step(2)
g = [m for m in of_type(take(), "gui") if m["u"] == 601]
check(g and g[-1]["kind"] == "vehicle" and set(g[-1]["inv"]) == {"fuel", "trunk", "car_ammo"}, f"a car opens with fuel, trunk and ammo: {g[-1:]}")
send({"t": "close"})
# The spidertron: its window (name, colour, auto targeting) and the remote (mock_vehicles.py).
spider = next(m for m in game.movers if m["unit"] == mock_vehicles.SPIDER)
game.player["x"], game.player["y"] = spider["x"] + 2, spider["y"]
send({"t": "open", "u": spider["unit"], "p": protos["spidertron"], "x": int(spider["x"] * 256), "y": int(spider["y"] * 256)})
send({"t": "set_vehicle", "u": spider["unit"], "lbl": "Spidey", "wi": 1})
step(2)
g = [m for m in of_type(take(), "gui") if m["u"] == spider["unit"]]
check(g and g[-1]["kind"] == "vehicle" and g[-1].get("veh") == {"grid": 1, "lbl": "Spidey", "at": [1, 1]} and len(g[-1]["guns"]) == 4,
      f"a spidertron opens with its name, targeting and four guns; set_vehicle changes them: {g[-1:]}")
send({"t": "close"})
send({"t": "spider_go", "l": [spider["unit"]], "x": int((spider["x"] + 3) * 256), "y": int(spider["y"] * 256)})
send({"t": "spider_go", "l": [spider["unit"]], "x": int((spider["x"] + 3) * 256), "y": int((spider["y"] + 3) * 256), "q": 1})
step(1)
spd = of_type(take(), "spd")
check(spd and len(spd[-1]["l"][0][1]) == 2, f"spider_go sends it, Shift queues: {spd[-1:]}")
step(60)
check(not spider["dest"], f"and it walks there: {spider['dest']}")
game.player["x"], game.player["y"] = 4.0, 9.0
send({"t": "inv_filter", "i": 3, "item": "iron-plate"})
step(2)
sl = of_type(take(), "slots")
check(sl and sl[-1].get("fl") == [[3, "iron-plate"]], f"inv_filter sets a slot filter: {sl[-1:]}")
send({"t": "inv_filter", "i": 3, "item": ""})
step(2)
sl = of_type(take(), "slots")
check(sl and "fl" not in sl[-1], "and clears it")
send({"t": "close"})
step(2)
take()

# resync resends chunks
step(130)
take()
send({"t": "resync", "full": 0})
step(40)
msgs = take()
check(len(of_type(msgs, "chunk")) == len(wanted), "resync resends all subscribed chunks")
send({"t": "resync", "full": 0, "c": [list(wanted[0]), [999, 999]]})
step(10)
msgs = take()
check([(m["cx"], m["cy"]) for m in of_type(msgs, "chunk")] == [tuple(wanted[0])], "resync with a list resends only those chunks")

# a full resync starts the stream over
step(130)
take()
send({"t": "resync", "full": 1})
step(60)
msgs = take()
check(msgs and of_type(msgs, "welcome"), "full resync restarts with a welcome")

# the other planets: each one's surface, planet data and streams; landing from the platform
def visit(planet, ticks):
    game.platform["loc"] = planet
    game.switch_surface(planet, 0.5, 0.5)
    step(ticks)
    return take()


hs_planet = of_type(hs_msgs, "planet")
check(hs_planet and hs_planet[-1]["name"] == "nauvis" and hs_planet[-1]["day"] == 25000, f"planet with the handshake: {hs_planet}")
msgs = visit("vulcanus", 4)
planet = of_type(msgs, "planet")
check(planet and planet[-1]["name"] == "vulcanus" and planet[-1]["props"]["gravity"] == 40 and planet[-1]["day"] == 5400,
      f"planet on arriving at Vulcanus: {planet}")
surf = of_type(msgs, "surface")
check(surf and surf[-1]["planet"] == "vulcanus", f"surface names the planet: {surf}")
seg = of_type(msgs, "seg")
check(seg and len(seg[-1]["l"][0][2]) == 4 * 42 and seg[-1]["l"][0][1] == protos["small-demolisher"]
      and seg[-1]["l"][0][2][0] == protos["small-demolisher"] and seg[-1]["l"][0][2][-4] == protos["small-demolisher-tail-x0_32"],
      f"seg: the demolisher's head, 40 segments and tail: {seg[-1:]}")
msgs = visit("fulgora", 361)
lt = [r for m in of_type(msgs, "lt") for r in m["l"]]
check({r[2] for r in lt} == {0, 1}, f"lt: strikes on Fulgora, some caught by a rod: {lt}")
msgs = visit("gleba", 61)
pg = of_type(msgs, "pg")[-1]["l"] if of_type(msgs, "pg") else []  # once a second: the window may hold two
check(len(pg) == 24, f"pg: six yumako trees growing: {pg}")
check(any(m["l"] for m in of_type(msgs, "legs")) and any(m["l"] for m in of_type(msgs, "sp")), "legs and sp on Gleba")
send({"t": "sub", "c": [[-1, -1], [0, 0], [-1, 0], [0, -1]]})
send({"t": "focus", "x": -4 * 256, "y": 0, "r": 48})
step(20)
msgs = take()
check(any(m["l"] for m in of_type(msgs, "bf")), "bf: spoiling items ride Gleba's belt")
chest = next(e for e in game.entities.values() if e.name == "wooden-chest")
game.player["x"], game.player["y"] = chest.x, chest.y + 1
send({"t": "open", "u": chest.unit, "p": protos["wooden-chest"], "x": mock_server.fixed(chest.x), "y": mock_server.fixed(chest.y)})
step(2)
g = [m for m in of_type(take(), "gui") if m["u"] == chest.unit]
check(g and ["yumako", 40, "normal", 640] in g[-1]["slots"]["chest"], f"a chest of yumako shows its freshness: {g[-1:]}")
send({"t": "close"})
msgs = visit("aquilo", 61)
fz = [v for m in of_type(msgs, "fz") for v in m["l"]]
check(len(fz) == 2, f"fz: two inserters out of the heating tower's reach are frozen: {fz}")
planet = of_type(msgs, "planet")
check(planet and [protos["heating-tower"], 12] in planet[-1]["heat"] and planet[-1]["sol"] == 10, f"planet: Aquilo's dim sun and heating radii: {planet}")
send({"t": "land"})
step(2)
check(any("Land from a platform" in m["text"] for m in of_type(take(), "msg")), "land on a planet is refused")
send({"t": "plat_board", "i": 1})
step(2)
take()
game.platform.update(pa=1, sched=None)
step(1)
send({"t": "land"})
step(sum(n for _, n in mock_server.RIDE_DOWN) + 4)
msgs = take()
check(any(m["text"] == "Going down to aquilo in a cargo pod" for m in of_type(msgs, "msg"))
      and of_type(msgs, "surface")[-1]["planet"] == "aquilo", f"land: from the platform down to Aquilo in a cargo pod: {[m['t'] for m in msgs]}")
game.platform.update(pa=0, sched={"c": 1, "l": ["vulcanus"]})
step(2)
pst = of_type(take(), "pst")
check(pst and pst[0]["st"] == "on_the_path" and pst[0]["loc"] == "", f"pst: the platform leaves: {pst}")

# death (--die-at): dead messages with the time left, then a new character at the spawn
old_unit = game.player["unit"]
game.die_at = game.tick
step(31)
msgs = take()
dead = of_type(msgs, "dead")
check(dead and 0 < dead[-1]["left"] <= mock_server.CHARACTER_RESPAWN_TICKS and not of_type(msgs[1:], "me"),
      f"dead: the respawn countdown, and no `me` while dead: {dead[-1:]}")
step(mock_server.CHARACTER_RESPAWN_TICKS)
welcome = of_type(take(), "welcome")
check(welcome and welcome[-1]["u"] != old_unit and game.player["hp"] == mock_server.CHARACTER_HEALTH,
      f"respawn: a new character, so a new welcome: {welcome[-1:]}")

# Space Age's screens (mock_space.py): the space map, a silo launching to the platform, the hub,
# the landing pad, a collector, quality, asteroid chunks
game.platform.update(loc="nauvis", to=None, d=0.0, pa=1, sched=None)
game.switch_surface("nauvis", -12.5, -1.5)
send({"t": "smap"})
step(2)
msgs = take()
sm = of_type(msgs, "smap")
check(sm and any(r[0] == "aquilo" for r in sm[0]["loc"]) and any(r[3] == 1000 for r in sm[0]["con"]),
      f"smap: the solar system with its connections: {sm[:1]}")
silo = game.space.silo
game.machine(silo).update(parts=0, st="building_rocket")
send({"t": "open", "u": silo.unit, "p": protos["rocket-silo"], "x": mock_server.fixed(silo.x), "y": mock_server.fixed(silo.y)})
step(2)
g = [m for m in of_type(take(), "gui") if m["u"] == silo.unit]
check(g and g[-1]["kind"] == "silo" and g[-1]["rk"]["to"] and "rocket" in g[-1]["slots"], f"the silo's screen: {g[-1:]}")
send({"t": "silo_launch", "u": silo.unit, "to": 1})
step(1)
check(any(m["text"] == "The rocket isn't ready" for m in of_type(take(), "msg")), "silo_launch before the rocket is built")
step(mock_space.PARTS_NEEDED * mock_space.PART_TICKS)
take()
send({"t": "silo_launch", "u": silo.unit, "to": 1})
step(4)
msgs = take()
rocket_id = protos["rocket-silo-rocket"]
check(of_type(msgs, "rk") and any(r[1] == rocket_id for m in of_type(msgs, "mv") for r in m["l"]),
      f"silo_launch: rk, and the rocket rises as a mover: {[m['t'] for m in msgs][:20]}")
step(mock_space.POD_DELAY + 10)
msgs = take()
check(any(m["l"] for m in of_type(msgs, "cp")) and any(r[1] == protos["cargo-pod"] for m in of_type(msgs, "mv") for r in m["l"]),
      "then a cargo pod comes down on the landing pad")
send({"t": "close"})
pad = game.space.pad
game.player["x"], game.player["y"] = pad.x, pad.y + 5
send({"t": "open", "u": pad.unit, "p": protos["cargo-landing-pad"], "x": mock_server.fixed(pad.x), "y": mock_server.fixed(pad.y)})
send({"t": "set_pad", "u": pad.unit, "req": 1})
step(2)
g = [m for m in of_type(take(), "gui") if m["u"] == pad.unit]
check(g and g[-1]["pad"]["cb"] == {"read": 1, "req": 1, "empty": 0} and g[-1]["pad"]["sec"], f"the landing pad's screen: {g[-1:]}")
send({"t": "close"})
step(12)
bq = of_type(take(), "bq")
check(any(m["l"] for m in bq), f"bq: some belt items are uncommon or rare: {bq[-1:]}")

send({"t": "plat_board", "i": 1})
step(12)
msgs = take()
planet = of_type(msgs, "planet")
check(planet and [protos["burner-mining-drill"], "gravity", 0.1, 1e9] in planet[-1].get("nb", []), f"planet.nb on the platform: {planet[-1:]}")
check(any(m["l"] for m in of_type(msgs, "ach")), "ach: asteroid chunks drift past the platform")
cols = sorted(e.unit for e in game.entities.values() if e.name == "asteroid-collector")
rows = [r for m in of_type(msgs, "acol") for r in m.get("l", [])]
check(cols and sorted(r[0] for r in rows) == cols and all(r[1:4] == [1, 200, 1] for r in rows),
      f"acol: every collector on the platform, an arm at 0.2 tiles a tick: {rows}")
step(1500)
msgs = take()
grabs = [g for m in of_type(msgs, "acol") for g in m.get("g", [])]
check(grabs and all(g[0] in cols and g[1] in mock_space.CHUNKS for g in grabs),
      f"acol g: the collectors catch the chunks drifting through their circles: {grabs[:4]}")
hub = game.entities[next(k for k, e in game.entities.items() if e.name == "space-platform-hub")]
send({"t": "open", "u": hub.unit, "p": protos["space-platform-hub"], "x": 0, "y": 0})
send({"t": "set_section", "u": hub.unit, "i": 0, "f": [["iron-gear-wheel", "rare", 10, -1, "vulcanus", 5]]})
send({"t": "set_schedule", "u": hub.unit, "records": [{"station": "vulcanus", "wait_conditions": [{"type": "time", "ticks": 600}]},
                                                      {"station": "nowhere"}]})
step(2)
g = [m for m in of_type(take(), "gui") if m["u"] == hub.unit]
h = g[-1]["hub"] if g else {}
check(h and len(h["sec"]) == 2 and h["sec"][1]["f"] == [["iron-gear-wheel", "rare", 10, -1, "vulcanus", 5]]
      and [r["station"] for r in h["sched"]["records"]] == ["vulcanus"] and g[-1]["slots"]["chest"][0][2] == "rare",
      f"the hub: requests, schedule, a rare stack: {h}")
send({"t": "close"})
send({"t": "plat_board", "i": 0})
step(2)
take()

check(batched > 1, f"a client that says b in its hello gets several messages to a datagram: up to {batched}")

if failures:
    print(f"\n{len(failures)} check(s) failed")
    sys.exit(1)
print("all mock server checks passed")
