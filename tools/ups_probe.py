#!/usr/bin/env python3
"""Measures a running server's speed (UPS) over RCON, and optionally what the bridge costs.

    python3 tools/ups_probe.py --seconds 30 [--profile] [--port 34198] [--json out.json]

Reads game.tick about twice a second and reports the game's ticks per real second: the mean,
the slowest one-second window (p5 and min) and how much the one-second windows vary (stdev).
--profile turns the bridge's /f3d-profile on first, waits the whole time and prints /f3d-status
(each module's time per tick over the last 10 s) at the end, then turns it off again.
--teleport X,Y moves the bridge's character there on Nauvis first.
--speed-test N then runs the game as fast as it can for N seconds (game.speed 20) and reports the
ticks per second it reached: 1000 / that is what one tick costs in ms (Factorio and the bridge
together), which shows load while the server still holds 60.
"""

import argparse
import json
import pathlib
import statistics
import sys
import time

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import rcon  # noqa: E402


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--port", type=int, default=rcon.PORT)
    parser.add_argument("--password-file", default=str(rcon.DEFAULT_PASSWORD_FILE))
    parser.add_argument("--seconds", type=float, default=30.0)
    parser.add_argument("--profile", action="store_true")
    parser.add_argument("--teleport", default="")
    parser.add_argument("--speed-test", type=float, default=0.0)
    parser.add_argument("--json", default="")
    parser.add_argument("--label", default="")
    args = parser.parse_args()
    password = pathlib.Path(args.password_file).read_text().strip()

    def cmd(c):
        return rcon.run(c, port=args.port, password=password)

    cmd("/sc rcon.print(1)")  # the first /sc in a save only warns about achievements
    if args.teleport:
        x, y = args.teleport.split(",")
        cmd("/c __factorio-3d-bridge__ package.loaded['__factorio-3d-bridge__/scripts/puppet.lua'].get()"
            f".teleport({{{x}, {y}}}, game.surfaces.nauvis)")
    if args.profile:
        reply = cmd("/f3d-profile")
        if "off" in reply:  # it was on already: turn it on again, fresh
            cmd("/f3d-profile")

    samples = []  # (wall seconds, tick)
    start = time.perf_counter()
    while time.perf_counter() - start < args.seconds:
        t = time.perf_counter()
        tick = int(cmd("/sc rcon.print(game.tick)").strip())
        samples.append((t, tick))
        time.sleep(max(0.0, 0.5 - (time.perf_counter() - t)))

    windows = []  # ticks per second over each 1 s window
    j = 0
    for i in range(len(samples)):
        while j < len(samples) and samples[j][0] - samples[i][0] < 1.0:
            j += 1
        if j >= len(samples):
            break
        dt = samples[j][0] - samples[i][0]
        windows.append((samples[j][1] - samples[i][1]) / dt)
    total = (samples[-1][1] - samples[0][1]) / (samples[-1][0] - samples[0][0])
    windows.sort()
    result = {
        "label": args.label,
        "seconds": round(samples[-1][0] - samples[0][0], 1),
        "ups": round(total, 2),
        "ups_p5": round(windows[max(0, len(windows) // 20)], 1) if windows else 0,
        "ups_min": round(windows[0], 1) if windows else 0,
        "ups_stdev": round(statistics.pstdev(windows), 2) if windows else 0,
    }
    if args.profile:
        status = cmd("/f3d-status")
        result["profile"] = status
        cmd("/f3d-profile")
    if args.speed_test > 0:
        cmd("/sc game.speed = 20")
        try:
            t0, k0 = time.perf_counter(), int(cmd("/sc rcon.print(game.tick)").strip())
            time.sleep(args.speed_test)
            t1, k1 = time.perf_counter(), int(cmd("/sc rcon.print(game.tick)").strip())
        finally:
            cmd("/sc game.speed = 1")
        result["max_ups"] = round((k1 - k0) / (t1 - t0), 1)
        result["tick_ms"] = round(1000.0 * (t1 - t0) / max(1, k1 - k0), 2)
    print(json.dumps({k: v for k, v in result.items() if k != "profile"}))
    if args.profile:
        print(result["profile"])
    if args.json:
        with open(args.json, "a", encoding="utf-8") as f:
            f.write(json.dumps(result) + "\n")


if __name__ == "__main__":
    main()
