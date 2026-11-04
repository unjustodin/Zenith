"""Throws malformed packets at the bridge mod (against fake_factorio.lua) and checks it survives.

    python3 tools/mod_tests/test_fuzz.py [--rounds N] [--seed S]

Every command handler gets fields of the wrong type, missing, huge, negative, deeply nested or
absurd; raw payloads come truncated, binary, empty or oversized; hellos, resyncs and subs arrive
out of order and duplicated. After each batch the game ticks, because a handler that stores
garbage in `storage` would crash the next on_tick, which no pcall protects. Afterwards a normal
client must still connect, walk and get chunks.

A handler error caught by session.on_packet (a "Bridge error" msg) is allowed but counted: it is
a bug in input checking, so the report lists them.
"""

import argparse
import json
import pathlib
import random
import re
import sys

from lupa import lua52

ROOT = pathlib.Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))
import protocol  # noqa: E402

MOD = ROOT / "mod" / "factorio-3d-bridge"
FAKE = pathlib.Path(__file__).with_name("fake_factorio.lua")
CLIENT_PORT = 34201

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


def from_json(text):
    try:
        data = json.loads(text)
    except (ValueError, RecursionError):
        return None
    try:
        return lua.table_from(data, recursive=True) if isinstance(data, (dict, list)) else data
    except RecursionError:
        return None


g = lua.globals()
g.F_to_json = lambda t: json.dumps(to_py(t), separators=(",", ":"))
g.F_from_json = from_json
lua.execute(FAKE.read_text())
g.package.path = str(MOD / "?.lua") + ";" + g.package.path
lua.execute((MOD / "control.lua").read_text())
# As in Factorio, `require` works only while control.lua is being loaded (a module requiring another
# from inside a function stops the game).
lua.execute('require = function(name) error("Require can not be used outside of control.lua parsing: " .. tostring(name)) end')
F = g.F

# Command names and the fields the mod reads, taken from its source so new commands are fuzzed too.
SESSION = (MOD / "scripts" / "session.lua").read_text()
COMMANDS = sorted(set(re.findall(r"handlers\.([a-z_0-9]+) =", SESSION)) | set(re.findall(r"function handlers\.([a-z_0-9]+)", SESSION)))
FIELDS = sorted({f for p in (MOD / "scripts").glob("*.lua") for f in re.findall(r"\b(?:cmd|msg)\.([a-z_0-9]+)", p.read_text())})

failures = []
bridge_errors = {}


def check(cond, what):
    if not cond:
        failures.append(what)
        print("FAIL:", what)


def junk(rng, depth=0):
    """A random JSON value, biased towards the shapes that break naive code."""
    choices = [
        lambda: None, lambda: True, lambda: 0, lambda: -1, lambda: 1, lambda: rng.randint(-2**53, 2**53),
        lambda: 1e308, lambda: -1e308, lambda: 0.5, lambda: rng.uniform(-1e6, 1e6), lambda: "",
        lambda: "x" * rng.choice([1, 100, 70000]), lambda: "\u0000￿퟿", lambda: rng.choice(COMMANDS),
        lambda: "iron-plate", lambda: "transport-belt", lambda: [], lambda: {},
    ]
    if depth < 4:
        choices += [
            lambda: [junk(rng, depth + 1) for _ in range(rng.randint(0, 5))],
            lambda: {rng.choice(FIELDS + ["1", "t"]): junk(rng, depth + 1) for _ in range(rng.randint(0, 4))},
            lambda: [[junk(rng, depth + 1), junk(rng, depth + 1)] for _ in range(rng.randint(0, 3))],
        ]
    return rng.choice(choices)()


def command(rng):
    msg = {"t": rng.choice(COMMANDS)}
    for f in rng.sample(FIELDS, rng.randint(0, min(8, len(FIELDS)))):
        msg[f] = junk(rng)
    return msg


def raw(rng):
    """A payload that isn't a well-formed command."""
    good = json.dumps(command(rng))
    return rng.choice([
        "", " ", "null", "[]", "1", '"t"', "{", '{"t":', good[: rng.randint(0, len(good))], good + "}}}",
        bytes(rng.getrandbits(8) for _ in range(rng.randint(1, 200))).decode("latin-1"),
        json.dumps({"t": junk(rng)}), json.dumps({"t": "walk", "d": "x" * 60000}),
        "[" * 5000 + "]" * 5000, json.dumps([command(rng)]),
    ])


def send(payload, port=CLIENT_PORT):
    try:
        F.packet(payload if isinstance(payload, str) else json.dumps(payload), port)
    except Exception as e:  # noqa: BLE001 - anything escaping on_packet would crash the game
        check(False, f"on_packet raised for {str(payload)[:200]!r}: {str(e).splitlines()[0][:300]}")


def tick(n, what):
    for _ in range(n):
        try:
            F.tick()
        except Exception as e:  # noqa: BLE001
            check(False, f"on_tick raised after {what}: {str(e).splitlines()[0][:300]}")
            return False
    return True


def take():
    out = []
    for item in F.take_sent().values():
        msg = json.loads(item[2])
        for problem in protocol.problems(msg):
            check(False, f"protocol after fuzzing: {problem}")
        out.append(msg)
    return out


def note_errors(msgs, cmd):
    for m in msgs:
        if m.get("t") == "msg" and str(m.get("text", "")).startswith("Bridge error"):
            bridge_errors.setdefault(cmd, set()).add(m["text"].split("\n")[0][:160])


def hello(sid="fuzz", w=1):
    send({"t": "hello", "v": 1, "sid": sid, "w": w})


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--rounds", type=int, default=3000)
    parser.add_argument("--seed", type=int, default=1)
    args = parser.parse_args()
    rng = random.Random(args.seed)

    F.spawn("wooden-chest", 2.5, 2.5, lua.table_from({"force": "player"}))
    F.spawn("assembling-machine-1", 6.5, 6.5, lua.table_from({"force": "player"}))
    F.spawn("transport-belt", 3.5, 6.5, lua.table_from({"force": "player"}))
    F.on_init()
    hello("fuzz", 0)
    tick(3, "the first hello")
    send({"t": "sub", "c": [[0, 0], [-1, 0], [0, -1], [-1, -1]]})
    tick(5, "the first sub")
    take()

    for i in range(args.rounds):
        kind = rng.random()
        if kind < 0.75:
            msg = command(rng)
            send(msg)
            what = msg["t"]
        elif kind < 0.9:
            send(raw(rng))
            what = "a raw payload"
        else:
            # Out of order and duplicated: hellos with other sessions or ports, resyncs, subs.
            pick = rng.choice(["hello", "resync", "sub", "dup"])
            if pick == "hello":
                send({"t": "hello", "v": junk(rng), "sid": rng.choice(["fuzz", "other", junk(rng)]), "w": junk(rng)},
                     rng.choice([CLIENT_PORT, CLIENT_PORT, 40000]))
                tick(1, "a stranger's hello")
                hello()  # the real client takes the session back, so the next commands count
            elif pick == "resync":
                send({"t": "resync", "full": rng.choice([0, 1, junk(rng)]), "c": junk(rng)})
            elif pick == "sub":
                send({"t": "sub", "c": [[rng.randint(-50, 50), rng.randint(-50, 50)] for _ in range(rng.randint(0, 40))]})
            else:
                msg = command(rng)
                for _ in range(3):
                    send(msg)
            what = pick
        if not tick(rng.choice([1, 1, 2, 5]), what):
            break
        note_errors(take(), what)
        client = g.storage.f3d.client
        if not client or client.port != CLIENT_PORT:
            hello()  # after a bye or a stranger's hello: reconnect, so the next commands count
            tick(1, "a reconnect")
            take()

    # The session recovers: a fresh client connects, gets the world and can walk.
    hello("after-fuzz", 0)
    tick(3, "a new hello")
    msgs = take()
    check(any(m.get("t") == "welcome" for m in msgs), "a new client gets a welcome after fuzzing")
    send({"t": "sub", "c": [[0, 0]]})
    tick(6, "a sub")
    msgs = take()
    check(any(m.get("t") == "chunk" for m in msgs), "and its chunk")
    for _ in range(3):
        send({"t": "walk", "d": 4})
        tick(3, "walking")
    c = g.storage.f3d.puppet
    walking = c and c.valid and c.walking_state
    check(bool(walking) and walking.walking and walking.direction == 4, "and walks east (walking_state)")

    print(f"{args.rounds} rounds over {len(COMMANDS)} commands and {len(FIELDS)} fields (seed {args.seed})")
    for cmd, texts in sorted(bridge_errors.items()):
        print(f"  caught by on_packet in {cmd}: {sorted(texts)[0]}" + (f" (+{len(texts) - 1} more)" if len(texts) > 1 else ""))
    if failures:
        print(f"\n{len(failures)} check(s) failed")
        sys.exit(1)
    print("fuzz: the bridge survived")


if __name__ == "__main__":
    main()
