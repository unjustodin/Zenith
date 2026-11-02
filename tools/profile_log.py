#!/usr/bin/env python3
"""Logs the bridge's per-module cost and the game's UPS every 10 s until stopped (or --minutes).

    python3 tools/profile_log.py out.jsonl [--port 34198] [--minutes 10]

Each line: {"unix": wall-clock time, "tick": game.tick, "ups": ticks per real second since the line
before, "modules": {name: ms per tick over the last 10 s}, "total": their sum}. Turns /f3d-profile
on at the start and off at the end. Match it to a client probe's windows by "unix".
"""

import argparse
import json
import pathlib
import re
import sys
import time

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import rcon  # noqa: E402

LINE = re.compile(r"\[Zenith\] (\w+): Duration: ([0-9.]+)ms per tick")


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("out")
    parser.add_argument("--port", type=int, default=rcon.PORT)
    parser.add_argument("--password-file", default=str(rcon.DEFAULT_PASSWORD_FILE))
    parser.add_argument("--minutes", type=float, default=60.0)
    args = parser.parse_args()
    password = pathlib.Path(args.password_file).read_text().strip()

    def cmd(c):
        return rcon.run(c, port=args.port, password=password)

    cmd("/sc rcon.print(1)")
    if "off" in cmd("/f3d-profile"):
        cmd("/f3d-profile")
    end = time.time() + args.minutes * 60.0
    last = None
    try:
        while time.time() < end:
            time.sleep(10.0)
            now = time.time()
            tick = int(cmd("/sc rcon.print(game.tick)").strip())
            modules = {m.group(1): float(m.group(2)) for m in LINE.finditer(cmd("/f3d-status"))}
            row = {"unix": round(now, 1), "tick": tick, "modules": modules, "total": round(sum(modules.values()), 2)}
            if last:
                row["ups"] = round((tick - last[1]) / (now - last[0]), 2)
            last = (now, tick)
            with open(args.out, "a", encoding="utf-8") as f:
                f.write(json.dumps(row) + "\n")
    finally:
        cmd("/f3d-profile")


if __name__ == "__main__":
    main()
