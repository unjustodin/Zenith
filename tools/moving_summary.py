"""Summaries of --stutter-probe runs for docs/PERFORMANCE-AUDIT.md "While moving".

    python tools/moving_summary.py run1.json [run2.json ...] [--systems] [--label NAME]

For each run (and the runs pooled): the whole frame, the main thread's own work and the GPU's
time, p50 / p99 / worst; frames over 16.7 and 33 ms; how fast the character went; the sliced
systems' time together (frame_budget.gd's books); chunks wanted but not drawn yet and the time from
a chunk being wanted to its buildings being drawn. --systems adds a table per system: how much it
used on average and in the slowest frames, how often it used its whole slice with work still
waiting.

The main thread's work in a frame is the frame less the time the renderer's draw spent waiting
(its whole draw on the main thread, frame_pre_draw to frame_post_draw, less its own CPU time,
viewport_get_measured_render_time_cpu): scripts, deferred calls and frees, the renderer's CPU side,
input and the OS. With vsync off and no FPS cap nothing else waits.
"""
import argparse
import json
import math


def pct(values, p):
    if not values:
        return float("nan")
    s = sorted(values)
    return s[max(0, min(len(s) - 1, math.ceil(p * len(s)) - 1))]


def frame_parts(r):
    """[frame ms, main ms, gpu ms, x, y, tick, phases dict]"""
    ms = float(r[0])
    render_cpu = max(float(r[6]), 0.0)
    gpu = float(r[7])
    phases = r[19] if len(r) > 19 and isinstance(r[19], dict) else {}
    # The frame less the time the renderer's draw waited (for the GPU, for presenting): the draw
    # beyond its own CPU time. Godot's physics monitor isn't used: it keeps the last physics step's
    # time in frames without one.
    wait = max(float(phases.get("draw", 0.0)) - render_cpu, 0.0)
    return ms, ms - wait, gpu, float(r[9]), float(r[10]), int(r[11]), phases


def summarize(frames, latency):
    rows = [frame_parts(r) for r in frames]
    ms = [r[0] for r in rows]
    main = [r[1] for r in rows]
    gpu = [r[2] for r in rows if r[2] >= 0]
    total_s = sum(ms) / 1000.0
    dist = 0.0
    for a, b in zip(rows, rows[1:]):
        d = math.hypot(b[3] - a[3], b[4] - a[4])
        if d < 20:  # a teleport isn't walking
            dist += d
    ticks = rows[-1][5] - rows[0][5] if rows else 0
    sliced = []
    undrawn = []
    near_undrawn = []
    for r in rows:
        fb = r[6].get("fb", {})
        sliced.append(sum(v[0] for k, v in fb.items() if k != "pool") / 1000.0)
        if "q_undrawn" in r[6]:
            undrawn.append(int(r[6]["q_undrawn"]))
            near_undrawn.append(int(r[6].get("q_near_undrawn", 0)))
    lat = [float(x[0]) for x in latency]
    # Chunks that came within two chunks of the focus (in view) before they were drawn: from then.
    near = [float(x[2]) for x in latency if len(x) > 2 and float(x[2]) >= 0]
    return {
        "frames": len(ms), "seconds": total_s,
        "fps": len(ms) / total_s if total_s else 0,
        "frame": [pct(ms, .5), pct(ms, .99), max(ms) if ms else 0],
        "main": [pct(main, .5), pct(main, .99), max(main) if main else 0],
        "gpu": [pct(gpu, .5), pct(gpu, .99), max(gpu) if gpu else 0],
        "over16": sum(1 for x in ms if x > 16.7) / max(len(ms), 1) * 100,
        "over33": sum(1 for x in ms if x > 33.0),
        "main_over16": sum(1 for x in main if x > 16.7) / max(len(main), 1) * 100,
        "speed": dist / total_s if total_s else 0,
        "ups": ticks / total_s if total_s else 0,
        "sliced": [sum(sliced) / max(len(sliced), 1), pct(sliced, .5), pct(sliced, .99), max(sliced) if sliced else 0],
        "undrawn": [pct(undrawn, .5), pct(undrawn, .99)] if undrawn else [float("nan")] * 2,
        "near_undrawn": [pct(near_undrawn, .5), pct(near_undrawn, .99), sum(1 for x in near_undrawn if x > 0) / max(len(near_undrawn), 1) * 100] if near_undrawn else [float("nan")] * 3,
        "latency": [len(lat), pct(lat, .5) / 1000, pct(lat, .99) / 1000, max(lat) / 1000 if lat else float("nan")],
        "latency_near": [len(near), pct(near, .5) / 1000, pct(near, .99) / 1000, max(near) / 1000 if near else float("nan")],
    }


def systems(frames):
    """{system: [mean ms used, p99 ms, % frames with work waiting, % frames it used its whole grant with work waiting,
    mean ms used in frames over 16.7 ms]}"""
    out = {}
    n = len(frames)
    slow = [r for r in frames if float(r[0]) > 16.7]
    names = set()
    for r in frames:
        fb = (r[19] if len(r) > 19 and isinstance(r[19], dict) else {}).get("fb", {})
        names.update(k for k in fb if k != "pool")
    for s in sorted(names):
        used, full, waiting, slow_used = [], 0, 0, 0.0
        for r in frames:
            v = (r[19] if len(r) > 19 and isinstance(r[19], dict) else {}).get("fb", {}).get(s)
            u = v[0] / 1000.0 if v else 0.0
            used.append(u)
            if v and v[2] > 0:
                waiting += 1
                if v[1] > 0 and v[0] >= v[1] * 0.9:
                    full += 1
        for r in slow:
            v = r[19].get("fb", {}).get(s) if isinstance(r[19], dict) else None
            slow_used += v[0] / 1000.0 if v else 0.0
        out[s] = [sum(used) / n, pct(used, .99), waiting / n * 100, full / n * 100, slow_used / max(len(slow), 1)]
    return out


def fmt3(v):
    return "%.1f / %.1f / %.1f" % tuple(v)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("runs", nargs="+")
    ap.add_argument("--systems", action="store_true")
    ap.add_argument("--load", action="store_true", help="the first frames after joining (the warm-up) instead")
    args = ap.parse_args()
    pooled, pooled_lat = [], []
    for path in args.runs:
        data = json.load(open(path))
        frames = data["load_frames" if args.load else "frames"]
        lat = [] if args.load else data.get("latency", [])
        pooled += frames
        pooled_lat += lat
        s = summarize(frames, lat)
        print("%s (%s): %d frames, %.0f fps, %.1f tiles/s, %.1f UPS | frame p50/p99/worst %s ms | main %s | gpu %s | >16.7 %.1f%% (main %.1f%%), >33 %d | "
              "sliced mean %.2f p99 %.1f worst %.1f ms | undrawn p50 %s p99 %s, near p50 %s p99 %s (%.1f%% of frames) | wanted->drawn n %d p50 %.2f p99 %.2f worst %.2f s, near n %d p50 %.2f p99 %.2f worst %.2f s"
              % (path, data.get("frame_budget", "?"), s["frames"], s["fps"], s["speed"], s["ups"], fmt3(s["frame"]), fmt3(s["main"]), fmt3(s["gpu"]),
                 s["over16"], s["main_over16"], s["over33"], s["sliced"][0], s["sliced"][2], s["sliced"][3], s["undrawn"][0], s["undrawn"][1],
                 *s["near_undrawn"], *s["latency"], *s["latency_near"]))
    if len(args.runs) > 1:
        s = summarize(pooled, pooled_lat)
        print("POOLED: frame %s | main %s | gpu %s | >16.7 %.1f%% >33 %d | fps %.0f" % (fmt3(s["frame"]), fmt3(s["main"]), fmt3(s["gpu"]), s["over16"], s["over33"], s["fps"]))
    if args.systems:
        print("| system | mean ms | p99 ms | frames with work waiting | frames using its whole slice with work waiting | mean ms in frames over 16.7 ms |")
        print("|---|---:|---:|---:|---:|---:|")
        for k, v in sorted(systems(pooled).items(), key=lambda kv: -kv[1][0]):
            print("| %s | %.2f | %.2f | %.0f%% | %.0f%% | %.2f |" % (k, *v))


if __name__ == "__main__":
    main()
