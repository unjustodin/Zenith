"""Which client requests make one slow server tick: each request is sent while the bridge traces
every tick's module and packet times into the log (`/f3d-profile trace N`), and the slowest tick
round it is reported with what took the time.

    python tools/request_spikes.py --port 35900 --rcon-port 35903 [--only map,join] [--json out.json]

Run it against a headless server (server/run-server.ps1) on a save with a base; it connects like
the client (hello, the chunks of a 10-chunk view, focus, far belt lanes), waits for the stream to
settle, then sends one request at a time. Nothing in the game is changed except where the
`jump` step teleports the bridge's character (and back).
"""

import argparse
import json
import math
import pathlib
import re
import socket
import sys
import time

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import rcon  # noqa: E402

LOG = pathlib.Path(__file__).resolve().parent.parent / "server" / "data" / "factorio-current.log"
TRACE = re.compile(r"f3dtrace (\d+) (\S+) (?:Duration|Elapsed): ([\d.]+)ms")


class Client:
    def __init__(self, server_port, port, view):
        self.sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self.sock.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, 16 * 1024 * 1024)
        self.sock.bind(("127.0.0.1", port))
        self.sock.setblocking(False)
        self.dest = ("127.0.0.1", server_port)
        self.view = view
        self.sid = f"spikes-{int(time.time())}"
        self.pos = (0.0, 0.0)
        self.welcome = False
        self.last = {}
        self.next_keepalive = 0.0
        self.counts = {}
        self.wb = []
        self.mrp = []     # `mrp` parts, for the remote view's spot in a roboport network
        self.look = None  # the remote view's point (rv = 1), or None: the character's

    def send(self, msg):
        self.sock.sendto(json.dumps(msg).encode(), self.dest)

    def hello(self, w=1):
        self.send({"t": "hello", "v": 1, "sid": self.sid, "w": w, "z": 1, "b": 1, "dc": 1})

    def focus(self):
        at = self.look or self.pos
        msg = {"t": "focus", "x": int(at[0] * 256), "y": int(at[1] * 256), "r": 192}
        if self.look:
            msg["rv"] = 1
        self.send(msg)

    def subscribe(self):
        at = self.look or self.pos
        cx, cy = math.floor(at[0] / 32), math.floor(at[1] / 32)
        v = self.view
        chunks = [[cx + dx, cy + dy] for dy in range(-v, v + 1) for dx in range(-v, v + 1)]
        chunks.sort(key=lambda c: (c[0] - cx) ** 2 + (c[1] - cy) ** 2)
        self.send({"t": "sub", "c": chunks})
        self.focus()

    def pump(self, seconds, until=None):
        end = time.time() + seconds
        while time.time() < end:
            if time.time() >= self.next_keepalive:
                self.hello()
                self.focus()
                self.next_keepalive = time.time() + 1.0
            try:
                data, _ = self.sock.recvfrom(65536)
            except (BlockingIOError, ConnectionResetError):
                time.sleep(0.002)
                continue
            for line in data.split(b"\n"):
                msg = json.loads(line)
                t = msg.get("t")
                self.counts[t] = self.counts.get(t, 0) + 1
                self.last[t] = msg
                if t == "welcome":
                    self.welcome = True
                    self.pos = (msg["x"] / 256, msg["y"] / 256)
                elif t == "me" and "x" in msg:
                    self.pos = (msg["x"] / 256, msg["y"] / 256)
                elif t == "wb":
                    self.wb.append(msg)
                elif t == "mrp":
                    self.mrp.append(msg)
                if until and until(msg):
                    return msg
        return None


def lua(code, port):
    return rcon.run("/sc " + code, port=port, timeout=60.0).strip()


def mod_lua(code, port):
    return rcon.run("/c __factorio-3d-bridge__ " + code, port=port, timeout=60.0).strip()


def log_size():
    return LOG.stat().st_size if LOG.exists() else 0


def read_trace(start):
    with open(LOG, "rb") as f:
        f.seek(start)
        text = f.read().decode(errors="replace")
    ticks = {}
    for m in TRACE.finditer(text):
        tick, name, ms = int(m.group(1)), m.group(2), float(m.group(3))
        ticks.setdefault(tick, []).append((name, ms))
    return ticks


def summarise(ticks):
    if not ticks:
        return {"ticks": 0}
    totals = {t: dict(rows).get("TOTAL", 0.0) for t, rows in ticks.items()}
    worst = max(totals, key=totals.get)
    rows = sorted((r for r in ticks[worst] if r[0] != "TOTAL"), key=lambda r: -r[1])
    values = sorted(totals.values())
    module_max = {}
    for rows_ in ticks.values():
        for n, ms in rows_:
            if n != "TOTAL":
                module_max[n] = max(module_max.get(n, 0.0), ms)
    return {
        "module_max": {n: round(v, 2) for n, v in module_max.items()},
        "ticks": len(totals),
        "worst_ms": round(totals[worst], 2),
        "worst_tick": worst,
        "p50_ms": round(values[len(values) // 2], 2),
        "over_5ms": sum(1 for v in values if v > 5),
        "over_16ms": sum(1 for v in values if v > 16.7),
        "top": [(n, round(ms, 2)) for n, ms in rows[:5]],
    }


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--port", type=int, default=35900, help="the bridge's UDP port")
    ap.add_argument("--client-port", type=int, default=35901)
    ap.add_argument("--rcon-port", type=int, default=35903)
    ap.add_argument("--view", type=int, default=10, help="chunks subscribed round the character (the client's default 10)")
    ap.add_argument("--only", help="comma-separated steps")
    ap.add_argument("--settle", type=float, default=20.0, help="seconds for the first snapshots before measuring")
    ap.add_argument("--trace", type=int, default=300, help="ticks traced per step")
    ap.add_argument("--json")
    args = ap.parse_args()
    rcon.PORT = args.rcon_port
    port = args.rcon_port

    c = Client(args.port, args.client_port, args.view)
    c.hello(w=0)
    c.pump(5.0, until=lambda m: m.get("t") == "ready")
    if not c.welcome:
        print("no welcome: is the server running on that port?")
        return 1
    c.subscribe()
    c.send({"t": "bfar", "r": 160, "n": 24})
    print(f"connected, character at {c.pos[0]:.0f}, {c.pos[1]:.0f}; settling {args.settle:.0f} s")
    c.pump(args.settle)
    home = c.pos

    cx, cy = math.floor(home[0] / 32), math.floor(home[1] / 32)
    surfs = (c.last.get("surfs") or {}).get("l") or []
    here_si = (c.last.get("welcome") or {}).get("si", 1)
    other = next((s for s in surfs if s[0] != here_si and s[2]), None) or next((s for s in surfs if s[0] != here_si), None)

    def jump():
        mod_lua("local c = package.loaded['__factorio-3d-bridge__/scripts/puppet.lua'].get() "
                "c.teleport({c.position.x + 3000, c.position.y}, c.surface)", port)
        c.pos = (home[0] + 3000, home[1])
        c.subscribe()

    def jump_back():
        mod_lua(f"local c = package.loaded['__factorio-3d-bridge__/scripts/puppet.lua'].get() "
                f"c.teleport({{{home[0]}, {home[1]}}}, c.surface)", port)
        c.pos = home
        c.subscribe()

    def hover():
        # An assembler near the character, by RCON, then the client's hover ask for it.
        out = mod_lua("local c = package.loaded['__factorio-3d-bridge__/scripts/puppet.lua'].get() "
                      "local e = c.surface.find_entities_filtered({position = c.position, radius = 64, "
                      "type = {'assembling-machine', 'beacon'}, limit = 1})[1] "
                      "rcon.print(e and (e.unit_number .. ' ' .. e.position.x .. ' ' .. e.position.y) or '')", port)
        if not out:
            return
        u, x, y = out.split()
        c.send({"t": "hinfo", "q": 1, "u": int(u), "p": 0, "x": int(float(x) * 256), "y": int(float(y) * 256)})

    steps = {
        "baseline": lambda: None,
        "map": lambda: c.send({"t": "map", "cx1": cx - 16, "cy1": cy - 16, "cx2": cx + 16, "cy2": cy + 16, "res": 4}),
        "map_fine": lambda: c.send({"t": "map", "cx1": cx - 8, "cy1": cy - 8, "cx2": cx + 8, "cy2": cy + 8, "res": 2}),
        "mtr": lambda: c.send({"t": "mtr"}),
        "trains_list": lambda: c.send({"t": "trains_list"}),
        "pedia_index": lambda: c.send({"t": "pedia_index"}),
        "pedia": lambda: c.send({"t": "pedia", "kind": "entity", "name": "assembling-machine-2"}),
        "lnets": lambda: c.send({"t": "lnets"}),
        "stats": lambda: c.send({"t": "stats", "kind": "item", "prec": 9}),
        "bonuses": lambda: c.send({"t": "bonuses"}),
        "hinfo": hover,
        "resync": lambda: c.send({"t": "resync", "full": 0}),
        "resync_full": lambda: c.send({"t": "resync", "full": 1}),
        "jump": jump,
        "jump_back": jump_back,
        "view": (lambda: c.send({"t": "view", "si": other[0], "x": 0, "y": 0})) if other else None,
        "view_back": lambda: c.send({"t": "view", "si": 0}),
        "join": None,  # below
    }

    def join():
        c.sid = f"spikes-{int(time.time())}-2"
        c.hello(w=0)
        c.pump(3.0, until=lambda m: m.get("t") == "ready")
        c.subscribe()

    def remote():
        # The 3D remote view over the furthest roboport (within 1,000 tiles) the last `mrp` listed:
        # the view filter asks the game whether roboports see each chunk with something moving.
        ports = [v for m in c.mrp for v in m.get("l", [])]
        best = None
        for i in range(0, len(ports) - 3, 4):
            x, y = ports[i] / 256, ports[i + 1] / 256
            d = math.hypot(x - home[0], y - home[1])
            if d < 1000 and (best is None or d > best[0]):
                best = (d, x, y)
        if best:
            print(f"remote view at a roboport {best[0]:.0f} tiles away ({best[1]:.0f}, {best[2]:.0f})")
            c.look = (best[1], best[2])
            c.focus()  # no new chunks: only what the view filter costs

    def remote_back():
        c.look = None
        c.focus()

    steps["join"] = join
    steps["mrp"] = lambda: c.send({"t": "mrp", "q": 1})
    steps["lpad"] = lambda: c.send({"t": "lpad", "si": here_si, "q": 1})
    steps["remote"] = remote
    steps["remote_back"] = remote_back
    order = ["baseline", "map", "map_fine", "mtr", "mrp", "lpad", "remote", "remote_back", "trains_list", "pedia_index",
             "pedia", "lnets", "stats", "bonuses", "hinfo", "resync", "jump", "jump_back", "view", "view_back",
             "resync_full", "join"]
    if args.only:
        order = [s for s in args.only.split(",")]
    results = {}
    for name in order:
        fn = steps.get(name)
        if fn is None:
            print(f"{name}: skipped")
            continue
        start = log_size()
        wb_from = len(c.wb)
        rcon.run(f"/f3d-profile trace {args.trace}", port=port)
        c.pump(0.3)
        fn()
        c.pump(args.trace / 60 + 1.5)
        res = summarise(read_trace(start))
        results[name] = res
        base = results.get("baseline", {}).get("module_max", {})
        # What this request added: modules (and packets) slower than in the baseline's worst tick.
        added = sorted(((round(v - base.get(n, 0.0), 1), n) for n, v in res.get("module_max", {}).items()
                        if v - base.get(n, 0.0) > 1.0 or (n.startswith("pkt:") and v > 0.5)), reverse=True)[:5]
        res["added"] = added
        # The bridge's own count (wb, after this branch): the most work units in one tick.
        wbs = c.wb[wb_from:]
        if wbs:
            res["units_max"] = max(m["max"] for m in wbs)
            res["ticks_over"] = sum(m["over"] for m in wbs)
            res["budget"] = wbs[-1]["b"]
        print(f"{name:<12} worst {res.get('worst_ms', 0):>7.2f} ms  p50 {res.get('p50_ms', 0):>5.2f}  "
              f">16.7ms {res.get('over_16ms', 0):>3}  units max {res.get('units_max', '-')}  above baseline {added}")
        c.pump(1.0)
    if c.wb:
        print("last wb:", json.dumps(c.wb[-1]))
    c.send({"t": "bye"})
    if args.json:
        pathlib.Path(args.json).write_text(json.dumps(results, indent=1))
    return 0


if __name__ == "__main__":
    sys.exit(main())
