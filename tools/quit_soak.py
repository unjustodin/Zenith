"""Starts and quits the windowed client many times and times each shutdown (exit hangs).

    python tools/quit_soak.py --godot <godot.exe> --factorio-port 34200 --port 34201 --runs 30 [--safe]

Each run starts the client connected to a running server (or the mock), lets it play for a random
number of seconds (--min/--max), and quits through `--quit-probe`, which leaves the exit guard out,
so a shutdown that never ends shows: a run still alive --hang seconds after it began quitting is
counted as hung and killed. `--safe` runs Godot's renderer on the main thread (`--render-thread
safe`) to compare with the separate render thread. Also counts script errors and the engine's
errors while playing (not the leak reports Godot prints at exit). Prints a summary and writes every
run to --out (JSON).
"""

import argparse
import json
import random
import re
import subprocess
import sys
import threading
import time

EXIT_NOISE = re.compile(r"Unreferenced static string|were leaked|leaked at exit|still in use at exit|Pages in use exist|"
                        r"ObjectDB instances|RID allocations|^\s+at: ")


def run_once(args, seconds):
    cmd = [args.godot]
    if args.safe:
        cmd += ["--render-thread", "safe"]
    cmd += ["--path", "client", "--", f"--factorio-port={args.factorio_port}", f"--port={args.port}",
            f"--settings-file={args.settings_file}", f"--quit-probe={seconds:.1f}"]
    start = time.monotonic()
    proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, encoding="utf-8", errors="replace")
    lines = []
    quit_at = [None]

    def read():
        for line in proc.stdout:
            lines.append((time.monotonic(), line.rstrip("\n")))
            if line.startswith("QUITPROBE quitting") and quit_at[0] is None:
                quit_at[0] = time.monotonic()

    reader = threading.Thread(target=read, daemon=True)
    reader.start()
    hung = False
    while proc.poll() is None:
        now = time.monotonic()
        if quit_at[0] is not None and now - quit_at[0] > args.hang:
            hung = True
            break
        if now - start > seconds + args.startup_limit:
            break  # never got to quitting
        time.sleep(0.1)
    if proc.poll() is None:
        subprocess.run(["taskkill", "/F", "/T", "/PID", str(proc.pid)], capture_output=True)
        proc.wait()
    reader.join(timeout=5)
    end = time.monotonic()
    quitting = [t for t, l in lines if l.startswith("QUITPROBE quitting")]
    errors = []
    in_shutdown = False
    for i, (t, l) in enumerate(lines):
        if l.startswith("QUITPROBE quitting"):
            in_shutdown = True
        if ("ERROR" in l or "SCRIPT ERROR" in l) and not EXIT_NOISE.search(l):
            # with where it came from: Godot's "at:" line and the script backtrace's first frame
            where = " | ".join(x.strip() for _, x in lines[i + 1:i + 4] if x.strip().startswith(("at:", "[0]", "GDScript")))
            errors.append(("exit " if in_shutdown else "") + l.strip()[:300] + (" @ " + where if where else ""))
    return {
        "seconds": seconds,
        "quit_line": next((l for t, l in lines if l.startswith("QUITPROBE quitting")), ""),
        "reached_quit": bool(quitting),
        "exit_s": round(end - quitting[0], 2) if quitting else None,
        "hung": hung,
        "code": proc.returncode,
        "errors": errors,
    }


def main():
    p = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    p.add_argument("--godot", required=True)
    p.add_argument("--factorio-port", type=int, default=34200)
    p.add_argument("--port", type=int, default=34201)
    p.add_argument("--settings-file", default="user://quit-soak.cfg")
    p.add_argument("--runs", type=int, default=20)
    p.add_argument("--min", type=float, default=8.0, help="shortest play before quitting, seconds")
    p.add_argument("--max", type=float, default=40.0)
    p.add_argument("--hang", type=float, default=15.0, help="seconds after quitting that count as a hang")
    p.add_argument("--startup-limit", type=float, default=90.0)
    p.add_argument("--safe", action="store_true", help="the renderer on the main thread (--render-thread safe)")
    p.add_argument("--seed", type=int, default=1)
    p.add_argument("--out")
    args = p.parse_args()
    rnd = random.Random(args.seed)
    runs = []
    for i in range(args.runs):
        r = run_once(args, rnd.uniform(args.min, args.max))
        runs.append(r)
        print(f"run {i + 1}/{args.runs}: play {r['seconds']:.1f} s, exit {r['exit_s']} s, hung {r['hung']}, "
              f"code {r['code']}, errors {len(r['errors'])} | {r['quit_line']}", flush=True)
        for e in r["errors"][:5]:
            print("    ", e, flush=True)
    exits = sorted(r["exit_s"] for r in runs if r["exit_s"] is not None and not r["hung"])
    summary = {
        "mode": "safe" if args.safe else "separate",
        "runs": len(runs),
        "hung": sum(r["hung"] for r in runs),
        "never_quit": sum(not r["reached_quit"] for r in runs),
        "with_errors": sum(bool(r["errors"]) for r in runs),
        "exit_s_median": exits[len(exits) // 2] if exits else None,
        "exit_s_max": exits[-1] if exits else None,
    }
    print("QUIT SOAK", json.dumps(summary), flush=True)
    if args.out:
        with open(args.out, "w", encoding="utf-8") as f:
            json.dump({"summary": summary, "runs": runs}, f, indent=1)
    return 1 if summary["hung"] else 0


if __name__ == "__main__":
    sys.exit(main())
