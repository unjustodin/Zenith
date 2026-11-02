"""Throws malformed commands at the mock server and checks it survives, like the mod's
tools/mod_tests/test_fuzz.py. The mock is what the client is tested against, so a command that
crashes it would hide client bugs behind a dead server.

    python3 tools/test_mock_fuzz.py [--rounds N] [--seed S]
"""

import argparse
import json
import pathlib
import random
import re
import sys
import traceback

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import mock_server  # noqa: E402

ROOT = pathlib.Path(__file__).resolve().parents[1]
SESSION = (ROOT / "mod" / "factorio-3d-bridge" / "scripts" / "session.lua").read_text()
COMMANDS = sorted(set(re.findall(r"handlers\.([a-z_0-9]+) =", SESSION)) | set(re.findall(r"function handlers\.([a-z_0-9]+)", SESSION)))
FIELDS = sorted(set(re.findall(r'msg\.get\("([a-z_0-9]+)"', (ROOT / "tools" / "mock_server.py").read_text())) | {"u", "p", "x", "y", "i", "n", "l", "c"})
ADDR = ("127.0.0.1", 34201)


def junk(rng, depth=0):
    choices = [lambda: None, lambda: True, lambda: 0, lambda: -1, lambda: 10**18, lambda: 1e308, lambda: 0.5, lambda: "",
               lambda: "x" * 5000, lambda: "iron-plate", lambda: [], lambda: {}]
    if depth < 3:
        choices += [lambda: [junk(rng, depth + 1) for _ in range(rng.randint(0, 4))],
                    lambda: {rng.choice(FIELDS): junk(rng, depth + 1) for _ in range(rng.randint(0, 3))}]
    return rng.choice(choices)()


class Silent(mock_server.MockGame):
    def send_raw(self, msg):  # no socket: just check the message can be encoded
        json.dumps(msg)
        return 0


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--rounds", type=int, default=3000)
    parser.add_argument("--seed", type=int, default=1)
    args = parser.parse_args()
    rng = random.Random(args.seed)
    game = Silent(seed=1, drop=0.0)
    game.build_starter_base()
    game.on_message({"t": "hello", "v": 1, "sid": "fuzz", "w": 0}, ADDR)
    mock_server.print = lambda *a, **k: None  # the mock's console lines
    errors = {}
    for i in range(args.rounds):
        msg = {"t": rng.choice(COMMANDS)}
        for f in rng.sample(FIELDS, rng.randint(0, min(6, len(FIELDS)))):
            msg[f] = junk(rng)
        try:
            game.on_message(msg, ADDR)
        except Exception:  # noqa: BLE001 - on_message must catch what a handler raises
            errors.setdefault("on_message " + msg["t"], traceback.format_exc().strip().splitlines()[-1][:200])
        try:
            # A command that stored garbage shows up here, in the ticks after it.
            for _ in range(rng.choice([1, 2])):
                game.tick += 1
                game.update()
        except Exception:  # noqa: BLE001
            errors.setdefault("tick after " + msg["t"], traceback.format_exc().strip().splitlines()[-1][:200])
            game = Silent(seed=1, drop=0.0)
            game.build_starter_base()
            game.on_message({"t": "hello", "v": 1, "sid": "fuzz", "w": 0}, ADDR)
        if i % 300 == 0:
            game.on_message({"t": "hello", "v": 1, "sid": "fuzz", "w": 1}, ADDR)
    print(f"{args.rounds} rounds over {len(COMMANDS)} commands (seed {args.seed})")
    for t, e in sorted(errors.items()):
        print(f"FAIL: {t}: {e}")
    if errors:
        sys.exit(1)
    print("mock fuzz: the mock survived")


if __name__ == "__main__":
    main()
