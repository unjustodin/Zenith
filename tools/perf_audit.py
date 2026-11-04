#!/usr/bin/env python3
"""Breaks a stutter-probe run's average frame into milliseconds (docs/PERFORMANCE-AUDIT.md).

    python3 tools/perf_audit.py run1.json [run2.json ...] [--bridge run1.bridge.jsonl ...] [--md] [--json out.json]

The runs are made with the client started with Godot's `--gpu-profile` and the probe's
`--probe-fine` (client/scripts/debug/stutter_probe.gd): each frame then carries every script
subtree's _process, the frame's phases outside _process (deferred calls, the renderer's draw, the
time until the next frame), and Godot's own render timestamps, as GPU and CPU time per render step.
Several runs of one scenario are pooled (every frame of each).

Two tables, each adding up to the average frame:
- the main thread: scripts by subtree, deferred calls, the renderer's CPU work by step, then what
  is left of the draw (presenting and waiting for the GPU) and the time between frames (input,
  physics, the OS);
- the GPU: each render step's time, and the GPU's idle time (the frame minus all steps).
--bridge adds the server's side from tools/profile_log.py (ms per tick per module) and the game's
UPS (from the ticks the client saw).
"""

import argparse
import json
import statistics
import sys

# Godot's render steps (the names of its RENDER_TIMESTAMP marks), grouped as rows.
GPU_GROUPS = [
    ("GPU: depth pre-pass", ["Render Depth Pre-Pass"]),
    ("GPU: sun shadows", ["Render Directional/SpotLight Shadows", "Setup Shadows"]),
    ("GPU: lamp (omni) shadows", ["Render OmniLight Shadows"]),
    ("GPU: SSAO", ["Prepare Depth for SSAO/SSIL", "Process SSAO"]),
    ("GPU: opaque pass", ["Render Opaque Pass"]),
    ("GPU: sky", ["Setup Sky", "Render Sky"]),
    ("GPU: transparent pass", ["Render 3D Transparent Pass"]),
    ("GPU: lights clustering", ["> Bake 3D Cluster", "Pack 3D Cluster Elements", "Render 3D Cluster Elements", "< Bake 3D Cluster"]),
    ("GPU: resolve, depth copy", ["Resolve", "Copy Depth Texture"]),
    ("GPU: tonemap and post", ["Tonemap", "Process Post Transparent Compositor Effects", "Glow", "SSR"]),
    ("GPU: UI (canvas)", ["Render CanvasItems"]),
]
CPU_GROUPS = [
    ("Render CPU: culling (view, sun, lamps)", ["Cull 3D Scene", "Update Occlusion Buffer", "Update Visibility Dependencies", "Cull DirectionalLight3D", "Cull OmniLight3D", "Cull SpotLight3D"]),
    ("Render CPU: frame setup (instances, materials)", ["Prepare Render Frame", "Setup 3D Scene", "Prepare 3D Scene", "Render 3D Scene", "Pre Opaque Render", "Setup Sky"]),
    ("Render CPU: shadow passes", ["Render Directional/SpotLight Shadows", "Render OmniLight Shadows", "Setup Shadows"]),
    ("Render CPU: depth pre-pass", ["Render Depth Pre-Pass"]),
    ("Render CPU: opaque pass", ["Render Opaque Pass"]),
    ("Render CPU: transparent pass", ["Render 3D Transparent Pass"]),
    ("Render CPU: UI (canvas)", ["Render CanvasItems", "Cull CanvasItem Tree", "Cull 2D Lights"]),
]
# Script subtrees named as the game's systems.
SCRIPT_NAMES = {"World itself": "world.gd (chunks, rebuilds, terrain, far chunks)", "World": "world.gd's children after the animator", "Animator": "anim.gd (machine animations)",
                "Movers": "movers (robots, creatures, vehicles)", "Decoratives": "decoratives", "Hud": "HUD and Factorio UI, minimap",
                "Input": "input", "InserterArms": "inserter arms", "BeltItems": "belt items", "BeltLanes": "far belt lanes",
                "Wires": "wires", "Fx": "sound and effects", "Ghosts": "ghosts", "WorkingGlow": "working glow", "Rockets": "rockets",
                "Avatar": "avatar (the character)", "UpsGovernor": "UPS governor",
                "rest at priority 0": "other small subtrees", "fx.gd (priority 2)": "sound and effects (fx.gd)",
                "sun_shadows.gd, vehicle_anim.gd (priority 10)": "sun shadow fitting, vehicle and robot rigs (vehicle_anim.gd)",
                "Fx": "sound and effects (children)"}


def group_of(name, groups):
    for row, prefixes in groups:
        for p in prefixes:
            if name == p or name.startswith(p):
                return row
    return None


def pct(values, p):
    if not values:
        return 0.0
    s = sorted(values)
    return s[min(len(s) - 1, max(0, int(round(p * len(s))) - 1))]


def frame_rows(f):
    """{row: ms} for one frame on the main thread, {row: ms} on the GPU."""
    main, gpu = {}, {}
    segs = f[14] if len(f) > 14 else {}
    handle = f[5]
    for k, v in segs.items():
        if k == "before":
            main["messages (Bridge, handled)"] = main.get("messages (Bridge, handled)", 0) + min(v, handle)
            main["main.gd and other autoloads"] = main.get("main.gd and other autoloads", 0) + max(0.0, v - handle)
        else:
            row = "script: " + SCRIPT_NAMES.get(k, k)
            main[row] = main.get(row, 0) + v
    main["script: not between marks (under 0.005 ms each)"] = max(0.0, f[12] - sum(segs.values()))
    ph = f[19] if len(f) > 19 and isinstance(f[19], dict) else {}
    main["deferred calls, freed nodes"] = ph.get("flush", 0.0)
    draw = ph.get("draw", 0.0)
    cpu_span = 0.0
    if len(f) > 22:
        for k, v in f[22].items():
            row = group_of(k, CPU_GROUPS) or "Render CPU: other steps"
            main[row] = main.get(row, 0) + v
            cpu_span += v
        for k, v in f[21].items():
            row = group_of(k, GPU_GROUPS) or "GPU: other steps"
            gpu[row] = gpu.get(row, 0) + v
    main["draw: presenting, waiting for the GPU (draw minus render CPU)"] = max(0.0, draw - cpu_span)
    present = ph.get("present", 0.0)
    main["physics"] = min(f[13], present)
    main["between frames: input, OS, frame pacing"] = max(0.0, present - f[13])
    return main, gpu


def analyse(paths, bridge_paths):
    frames = []
    ups = []
    for p in paths:
        d = json.load(open(p))
        F = [f for f in d["frames"] if len(f) > 22]
        frames += F
        secs = sum(f[0] for f in d["frames"]) / 1000.0
        ups.append((d["frames"][-1][11] - d["frames"][0][11]) / secs)
    n = len(frames)
    ms = [f[0] for f in frames]
    avg = statistics.mean(ms)
    main_rows, gpu_rows = {}, {}
    for f in frames:
        m, g = frame_rows(f)
        for k, v in m.items():
            main_rows.setdefault(k, []).append(v)
        for k, v in g.items():
            gpu_rows.setdefault(k, []).append(v)

    def table(rows):
        out = []
        for k, vals in rows.items():
            vals = vals + [0.0] * (n - len(vals))
            out.append({"row": k, "avg": statistics.mean(vals), "p99": pct(vals, 0.99)})
        out.sort(key=lambda r: -r["avg"])
        return out

    main = table(main_rows)
    gpu = table(gpu_rows)
    gpu_busy = sum(r["avg"] for r in gpu)
    bridge = {}
    for bp in bridge_paths:
        lines = [json.loads(l) for l in open(bp) if l.strip()]
        lines = [l for l in lines if len(l.get("modules", {})) > 5][1:]  # once the client is in, past its join
        for l in lines:
            for k, v in l["modules"].items():
                bridge.setdefault(k, []).append(v)
    bridge_rows = sorted(((k, statistics.mean(v)) for k, v in bridge.items()), key=lambda r: -r[1])
    # "bridge" times the whole of each client's work (the other modules run inside it); "poll",
    # "transport" (partly) and "warm" run outside it.
    top = {k: v for k, v in bridge_rows}
    bridge_total = top.get("bridge", 0.0) + top.get("poll", 0.0) + top.get("warm", 0.0) + top.get("handshake", 0.0)
    return {"runs": paths, "frames": n, "avg_ms": avg, "fps": 1000.0 / avg, "p50": pct(ms, 0.5), "p99": pct(ms, 0.99),
            "over_16_7": sum(1 for m in ms if m > 16.7) / n, "over_33": sum(1 for m in ms if m > 33.0) / n,
            "ups": statistics.mean(ups), "main": main, "main_sum": sum(r["avg"] for r in main), "gpu": gpu,
            "gpu_busy": gpu_busy, "gpu_p99": pct([sum(f[21].values()) for f in frames], 0.99),
            "draw_calls": statistics.mean(f[16] for f in frames), "primitives": statistics.mean(f[17] for f in frames),
            "bridge": bridge_rows, "bridge_total": bridge_total}


def how(row):
    if row.startswith("GPU"):
        return "render timestamp (GPU)"
    if row.startswith("Render CPU"):
        return "render timestamp (CPU)"
    if row.startswith("script") or row.startswith("main.gd"):
        return "probe marker"
    if row.startswith("messages"):
        return "Bridge's own timer"
    if row.startswith("physics"):
        return "Godot monitor"
    if row.startswith("draw"):
        return "frame_pre/post_draw minus timestamps"
    return "probe (frame phases)"


def markdown(r):
    a = r["avg_ms"]
    lines = [f"Average frame **{a:.2f} ms** ({r['fps']:.0f} fps), p50 {r['p50']:.1f}, p99 {r['p99']:.1f} ms; "
             f"{100 * r['over_16_7']:.0f}% of frames over 16.7 ms, {100 * r['over_33']:.1f}% over 33 ms; "
             f"{r['frames']} frames; draw calls {r['draw_calls']:.0f}, primitives {r['primitives'] / 1e6:.2f} M; game {r['ups']:.1f} UPS.",
             "", "| Main thread | avg ms | % of frame | p99 ms | measured by |", "|---|---:|---:|---:|---|"]
    shown = 0.0
    for row in r["main"]:
        if row["avg"] < 0.05:
            continue
        shown += row["avg"]
        lines.append(f"| {row['row']} | {row['avg']:.2f} | {100 * row['avg'] / a:.1f}% | {row['p99']:.1f} | {how(row['row'])} |")
    lines.append(f"| rows under 0.05 ms together | {r['main_sum'] - shown:.2f} | {100 * (r['main_sum'] - shown) / a:.1f}% | | |")
    lines.append(f"| left over (frame minus all rows) | {a - r['main_sum']:.2f} | {100 * (a - r['main_sum']) / a:.1f}% | | frame minus the rows |")
    lines += ["", "| GPU | avg ms | % of frame | p99 ms | measured by |", "|---|---:|---:|---:|---|"]
    shown = 0.0
    for row in r["gpu"]:
        if row["avg"] < 0.02:
            continue
        shown += row["avg"]
        lines.append(f"| {row['row']} | {row['avg']:.2f} | {100 * row['avg'] / a:.1f}% | {row['p99']:.1f} | {how(row['row'])} |")
    lines.append(f"| steps under 0.02 ms together | {r['gpu_busy'] - shown:.2f} | {100 * (r['gpu_busy'] - shown) / a:.1f}% | | |")
    lines.append(f"| GPU busy (all steps) | {r['gpu_busy']:.2f} | {100 * r['gpu_busy'] / a:.1f}% | {r['gpu_p99']:.1f} | render timestamps |")
    lines.append(f"| GPU idle (frame minus busy) | {max(0.0, a - r['gpu_busy']):.2f} | {100 * max(0.0, a - r['gpu_busy']) / a:.1f}% | | frame minus busy |")
    if r["bridge"]:
        lines += ["", f"Server: the bridge about {r['bridge_total']:.1f} ms a tick (its whole per-client work and the UDP poll); inside it: " +
                  ", ".join(f"{k} {v:.2f}" for k, v in r["bridge"][:12] if v >= 0.05 and k not in ("bridge", "poll")) + "."]
    return "\n".join(lines)


def variants(paths):
    """With --probe-variants runs: each variant's settled frames, averaged; GPU by step and the main
    thread's big parts, so a feature switched off shows where its time was."""
    by = {}
    for p in paths:
        for f in json.load(open(p))["frames"]:
            if len(f) > 22 and isinstance(f[18], dict) and f[18].get("settled"):
                by.setdefault(f[18]["variant"], []).append(f)
    cols = ["GPU: depth pre-pass", "GPU: opaque pass", "GPU: sun shadows", "GPU: SSAO", "GPU: transparent pass", "GPU: UI (canvas)"]
    lines = ["| variant | frames | frame avg | GPU busy | " + " | ".join(c[5:] for c in cols) + " | render CPU | scripts | draw calls | primitives (M) |",
             "|---|---:|---:|---:|" + "---:|" * len(cols) + "---:|---:|---:|---:|"]
    for name, F in by.items():
        g = {}
        rc = 0.0
        for f in F:
            _, gpu = frame_rows(f)
            for k, v in gpu.items():
                g[k] = g.get(k, 0.0) + v / len(F)
            rc += sum(f[22].values()) / len(F)
        lines.append(f"| {name} | {len(F)} | {statistics.mean(f[0] for f in F):.2f} | {sum(g.values()):.2f} | "
                     + " | ".join(f"{g.get(c, 0.0):.2f}" for c in cols)
                     + f" | {rc:.2f} | {statistics.mean(f[12] for f in F):.2f} | {statistics.mean(f[16] for f in F):.0f} | {statistics.mean(f[17] for f in F) / 1e6:.2f} |")
    return "\n".join(lines)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("runs", nargs="+")
    ap.add_argument("--bridge", nargs="*", default=[])
    ap.add_argument("--json")
    ap.add_argument("--variants", action="store_true", help="the runs are --probe-variants runs: a table per variant")
    args = ap.parse_args()
    if args.variants:
        print(variants(args.runs))
        return
    r = analyse(args.runs, args.bridge)
    print(markdown(r))
    if args.json:
        json.dump(r, open(args.json, "w"), indent=1)


if __name__ == "__main__":
    sys.exit(main())
