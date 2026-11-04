#!/usr/bin/env python3
"""What Alt-mode costs the bridge (issue #9): a client without a window that streams the chunks
round a spot the way the 3D client does, then measures the bridge's per-module time with Alt-mode
off and on.

    python3 tools/alt_cost.py --factorio-port 35890 --client-port 35891 --rcon-port 35893 \\
        --x -272 --y -16 [--chunks 10] [--seconds 40] [--legacy-alt]

It moves the bridge's character to (x, y), subscribes the (2 * chunks + 1)^2 chunks round it nearest
first (the client's View distance, 10 by default) with the focus radius the client uses (192), and
waits until all have arrived, timing that load and counting the bytes of the chunk messages. Then
`--seconds` with Alt-mode off and the same on, reading /f3d-status's 10-second averages (profiling
on). `--legacy-alt` sends the old `alt` command to switch Alt-mode on (what 0.1.1's client does);
without it Alt-mode on sends nothing, as the client after issue #9 does (its icons come with the
entity records). Prints one JSON line with everything, and the counts of Alt-mode icons seen
(records' extra.ai, `aiu`, `ai`).
"""

import argparse
import json
import pathlib
import re
import sys
import time

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import live_check  # noqa: E402
import rcon  # noqa: E402

LINE = re.compile(r"\[Zenith\] (\w+): Duration: ([0-9.]+)ms per tick")


def modules():
    return {m.group(1): float(m.group(2)) for m in LINE.finditer(rcon.run("/f3d-status"))}


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--factorio-port", type=int, default=35890)
    ap.add_argument("--client-port", type=int, default=35891)
    ap.add_argument("--rcon-port", type=int, default=35893)
    ap.add_argument("--x", type=float, default=-272.0)
    ap.add_argument("--y", type=float, default=-16.0)
    ap.add_argument("--surface", default="nauvis")
    ap.add_argument("--chunks", type=int, default=10)
    ap.add_argument("--seconds", type=float, default=40.0)
    ap.add_argument("--legacy-alt", action="store_true")
    ap.add_argument("--max-load", type=float, default=300.0)
    ap.add_argument("--label", default="")
    args = ap.parse_args()
    rcon.PORT = args.rcon_port
    live_check.FACTORIO_PORT, live_check.CLIENT_PORT = args.factorio_port, args.client_port
    rcon.run("/c rcon.print('ok')")
    c = live_check.Client(args.factorio_port, args.client_port)
    if not live_check.handshake(c):
        sys.exit("no handshake")
    hello = (1.0, {"t": "hello", "v": 1, "sid": c.sid, "w": 1})
    c.pump(1.0, every=hello)
    # The owner's save leaves its player on Aquilo; the busy belts are on Nauvis.
    live_check.mod_lua(f"storage.f3d.puppet.teleport({{ {args.x}, {args.y} }}, '{args.surface}') rcon.print('ok')")
    c.pump(3.0, every=hello)
    cx, cy = int(args.x // 32), int(args.y // 32)
    r = args.chunks
    wanted = sorted(([cx + dx, cy + dy] for dy in range(-r, r + 1) for dx in range(-r, r + 1)),
                    key=lambda k: (k[0] - cx) ** 2 + (k[1] - cy) ** 2)
    if "off" in rcon.run("/f3d-profile"):
        rcon.run("/f3d-profile")
    c.send({"t": "sub", "c": wanted})
    c.send({"t": "focus", "x": int(args.x * 256), "y": int(args.y * 256), "r": 192})
    done, parts, chunk_bytes, records, with_ai = set(), {}, 0, 0, 0
    icons = {}  # unit -> icon, from records, aiu and ai
    t0 = time.time()
    world_ms = 0.0
    next_status = t0 + 10.0
    resent = t0
    while len(done) < len(wanted) and time.time() - t0 < args.max_load:
        # A teleport to another surface resets the subscription a moment later: ask again.
        if not done and time.time() - resent > 10.0:
            c.send({"t": "sub", "c": wanted})
            c.send({"t": "focus", "x": int(args.x * 256), "y": int(args.y * 256), "r": 192})
            resent = time.time()
        for m in c.pump(0.5, every=hello):
            t = m.get("t")
            if t == "chunk":
                chunk_bytes += len(json.dumps(m))
                if m.get("none"):
                    done.add((m["cx"], m["cy"]))
                else:
                    parts[(m["cx"], m["cy"])] = m.get("parts", 1)
            elif t == "ents":
                chunk_bytes += len(json.dumps(m))
                for e in m["e"]:
                    records += 1
                    if len(e) > 5 and isinstance(e[5], dict) and "ai" in e[5]:
                        with_ai += 1
                        icons[e[0]] = e[5]["ai"]
                if m["part"] == m["parts"]:
                    done.add((m["cx"], m["cy"]))
        if time.time() >= next_status:
            world_ms += modules().get("world", 0.0) * 600
            next_status += 10.0
    load_s = time.time() - t0
    c.pump(11.0, every=hello)
    world_ms += modules().get("world", 0.0) * 600

    def measure(seconds):
        rows = []
        end = time.time() + seconds
        while time.time() < end:
            for m in c.pump(10.0, every=hello):
                if m.get("t") == "aiu":
                    for row in m.get("l", []):
                        icons[row[0]] = row[1:]
                elif m.get("t") == "ai":
                    seen_ai.update(row[0] for row in m.get("l", []))
            tick = int(rcon.run("/sc rcon.print(game.tick)").strip())
            rows.append((time.time(), tick, modules()))
        ups = (rows[-1][1] - rows[0][1]) / (rows[-1][0] - rows[0][0]) if len(rows) > 1 else 0
        keys = set().union(*(r[2].keys() for r in rows))
        avg = {k: round(sum(r[2].get(k, 0.0) for r in rows[1:]) / max(1, len(rows) - 1), 3) for k in keys}
        return {"ups": round(ups, 2), "ui_actions": avg.get("ui_actions", 0.0), "world": avg.get("world", 0.0),
                "total": round(sum(avg.values()), 3)}

    seen_ai = set()
    off = measure(args.seconds)
    if args.legacy_alt:
        c.send({"t": "alt", "on": 1})
    on = measure(args.seconds)
    if args.legacy_alt:
        c.send({"t": "alt", "on": 0})
    rcon.run("/f3d-profile")
    c.send({"t": "bye"})
    print(json.dumps({"label": args.label, "chunks": len(wanted), "load_s": round(load_s, 1),
                      "world_ms_during_load": round(world_ms, 1), "chunk_bytes": chunk_bytes, "records": records,
                      "records_with_ai": with_ai, "legacy_ai_units": len(seen_ai), "alt_off": off, "alt_on": on}))


if __name__ == "__main__":
    main()
