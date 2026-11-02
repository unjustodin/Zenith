"""What the bridge sends to a client: bytes and messages per type, per second.

    python3 tools/net_cost.py                      # the mock with a busy base, run in-process
    python3 tools/net_cost.py --belt-field 0x0     # the mock's plain starter base
    python3 tools/net_cost.py --port 34200         # a running server (mock or real Factorio)

It connects like the client (hello, sub for the chunks around the character, a walk now and
then), lets the handshake and the first chunk snapshots arrive, then counts everything for
--seconds. The handshake and the snapshots are reported apart from the steady stream, because
they cost once while the stream costs every second.
"""

import argparse
import json
import math
import pathlib
import socket
import sys
import time

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import protocol  # noqa: E402

TICKS_PER_SECOND = 60


class Tally:
    def __init__(self):
        self.types = {}
        self.packets = 0
        self.bytes = 0

    def add(self, msg, size):
        self.packets += 1
        self.bytes += size
        rec = self.types.setdefault(msg.get("t", "?"), {"n": 0, "bytes": 0, "max": 0, "reliable": 0})
        rec["n"] += 1
        rec["bytes"] += size
        rec["max"] = max(rec["max"], size)
        rec["reliable"] += 1 if "r" in msg else 0

    def report(self, title, seconds=None):
        print(f"\n{title}: {self.packets} packets, {self.bytes / 1024:.1f} KB"
              + (f" in {seconds:.0f} s = {self.bytes / 1024 / seconds:.1f} KB/s, {self.packets / seconds:.0f} packets/s"
                 if seconds else ""))
        print(f"  {'type':<10}{'msgs':>7}{'KB':>9}{'share':>7}{'avg B':>8}{'max B':>8}" + ("  KB/s" if seconds else ""))
        for t, rec in sorted(self.types.items(), key=lambda kv: -kv[1]["bytes"]):
            line = (f"  {t:<10}{rec['n']:>7}{rec['bytes'] / 1024:>9.1f}{100 * rec['bytes'] / max(1, self.bytes):>6.0f}%"
                    f"{rec['bytes'] // rec['n']:>8}{rec['max']:>8}")
            if seconds:
                line += f"{rec['bytes'] / 1024 / seconds:>6.1f}"
            print(line + ("  reliable" if rec["reliable"] == rec["n"] else ""))

    def as_dict(self, seconds=None):
        return {"packets": self.packets, "bytes": self.bytes, "seconds": seconds, "types": self.types}


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--port", type=int, help="measure a running server on this port instead of an in-process mock")
    parser.add_argument("--seconds", type=float, default=10.0)
    parser.add_argument("--view", type=int, default=5, help="chunks subscribed around the character (the client's view distance)")
    parser.add_argument("--belt-field", default="40x30", help="mock only: COLSxROWS of full belts next to the base")
    parser.add_argument("--quiet", action="store_true", help="mock only: no 20,000-entity factory (mock_server.py --busy)")
    parser.add_argument("--plain", action="store_true", help="don't ask for delta-coded lists (z), like an old client")
    parser.add_argument("--still", action="store_true", help="don't walk (tools/busy_base.py measures a base next to the character)")
    parser.add_argument("--json", help="also write the tallies to this file")
    args = parser.parse_args()

    client = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    client.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, 16 * 1024 * 1024)
    client.bind(("127.0.0.1", 0 if args.port is None else 34201))
    client.setblocking(False)

    game = None
    if args.port is None:
        import mock_server
        game = mock_server.MockGame(seed=1, drop=0.0)
        game.build_starter_base()
        game.build_cliffs()
        cols, rows = (int(v) for v in args.belt_field.lower().split("x"))
        if cols and rows:
            game.build_belt_field(cols, rows)
        if not args.quiet:
            game.build_busy_base()
        game.sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        game.sock.setsockopt(socket.SOL_SOCKET, socket.SO_SNDBUF, 16 * 1024 * 1024)
        game.sock.bind(("127.0.0.1", 0))
        game.sock.setblocking(False)
        server = game.sock.getsockname()
    else:
        server = ("127.0.0.1", args.port)

    def send(msg):
        client.sendto(json.dumps(msg).encode(), server)

    problems = []

    def drain(tally):
        n = 0
        while True:
            try:
                data, _ = client.recvfrom(65536)
            except (BlockingIOError, ConnectionResetError):
                return n
            msg = json.loads(data)
            problems.extend(protocol.problems(msg))
            tally.add(msg, len(data))
            n += 1
            if msg.get("t") == "me" and "x" in msg:
                state["pos"] = (msg["x"] / 256, msg["y"] / 256)
            elif msg.get("t") == "welcome":
                state["welcome"] = True

    state = {"pos": (0.0, 0.0), "welcome": False}
    clock = {"tick": 0}

    def run(seconds, tally, walk=False):
        """Steps the mock tick by tick, or waits in real time for a real server."""
        ticks = int(seconds * TICKS_PER_SECOND)
        start = time.monotonic()
        for i in range(ticks):
            t = clock["tick"]
            if t % 60 == 0:
                send(dict(hello, w=1))
                cx, cy = math.floor(state["pos"][0] / 32), math.floor(state["pos"][1] / 32)
                send({"t": "sub", "c": [[cx + dx, cy + dy] for dy in range(-args.view, args.view + 1)
                                        for dx in range(-args.view, args.view + 1)]})
                send({"t": "focus", "x": int(state["pos"][0] * 256), "y": int(state["pos"][1] * 256), "r": 96})
            if walk and t % 30 == 0:
                # Back and forth along the base, as a player would: east for 4 s, then west.
                send({"t": "walk", "d": 4 if (t // 240) % 2 == 0 else 12})
            clock["tick"] += 1
            if game is not None:
                game.step()
            else:
                time.sleep(max(0.0, start + (i + 1) / TICKS_PER_SECOND - time.monotonic()))
            drain(tally)

    hello = {"t": "hello", "v": 1, "sid": "net-cost", "w": 0}
    if not args.plain:
        hello["z"] = 1
    setup = Tally()
    send(hello)
    run(5.0, setup)
    if not state["welcome"]:
        print("no welcome: is the server running and is the port right?")
        sys.exit(1)
    steady = Tally()
    run(args.seconds, steady, walk=not args.still)
    send({"t": "walk", "d": -1})
    send({"t": "bye"})

    where = (f"the mock ({len(game.entities)} entities, {args.belt_field} belt field)" if game else f"port {args.port}")
    print(f"Measured {where}, view {args.view} chunks ({(2 * args.view + 1) ** 2} subscribed)")
    setup.report("Handshake and first snapshots (first 5 s)")
    steady.report("Steady stream" + ("" if args.still else ", walking"), args.seconds)
    if problems:
        print(f"\n{len(problems)} protocol problem(s), first: {problems[0]}")
    if args.json:
        pathlib.Path(args.json).write_text(json.dumps({"setup": setup.as_dict(5.0), "steady": steady.as_dict(args.seconds)}, indent=1))


if __name__ == "__main__":
    main()
