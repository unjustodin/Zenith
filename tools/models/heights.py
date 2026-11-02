#!/usr/bin/env python3
"""Heights: how tall each model is against how tall Factorio draws it.

    python tools/models/heights.py [names...] [--dump raw.json] [--csv OUT.csv] [--pitch 48]
        [--png DIR]

For every model with a sprite (the prototype's whole layer stack where score_proto.py knows the
model, otherwise client/data/sprite_projection.json's cells), the sprite (baked shadows left
out, as fit.py and compare.py) and the model are put in the same frame, with the camera the
model was fitted with: pitch 48 below the horizon, the entry's north-south `stretch` and
`anchor`. Measured per cell, then the median over cells:

  roof   the gap between the sprite's top edge and the model's, column by column (median over
         the columns both cover), in tiles of height: positive when the sprite stands taller.
         Thin things sticking up (an antenna, a chimney) don't sway it, as they would the top row.
  ratio  (model height + roof) / model height: 1.00 as tall as Factorio draws it, 0.90 a tenth
         too tall, 1.10 a tenth short.
  peak   the same gap between the topmost points only.
  base   the sprite's lowest row against the footprint's south edge (half its depth below the
         entity's position): 1.00 when the drawn building starts at its footprint's edge.

--pitch tries another pitch with everything else kept (how much the heights depend on it).
--png writes the overlays (sprite grey, model outline red) into a git-ignored folder.

Factorio's projection, as measured from its sprites (REPORT-ACCT2.md): an orthographic camera
about 45-48 degrees below the horizon, unstretched (round pipes are as tall in section as they
are wide, the lab's dome is round on top, car wheels seen on end are as tall as they are wide);
buildings drawn so their footprint fills their tiles on screen (base 1.00); rolling stock
rendered stretched north-south (train wheels seen side-on are nearly round).
"""

import argparse
import csv
import json
import math
import os
import re
import sys

import numpy as np
from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, HERE)

import fit  # noqa: E402
import fit_cells  # noqa: E402
import score_proto  # noqa: E402

MODELS = os.path.join(REPO, "client", "assets", "models")
ENTRIES = os.path.join(REPO, "client", "data", "sprite_projection.json")
SUFFIX = re.compile(r"-(east|south|west|ne|nw|se|sw|corner-\w+|inner-\w+|wall-\w+|flaming|hot|gun|armor-\d|mech-armor)$")


def prototypes(raw):
    """name -> prototype for every entity-like prototype with a collision box."""
    out = {}
    for group in raw.values():
        if isinstance(group, dict):
            for n, p in group.items():
                if isinstance(p, dict) and "collision_box" in p and n not in out:
                    out[n] = p
    return out


def footprint(name, protos):
    """(width, depth) in tiles the entity takes, facing north, or None."""
    n = name
    while n not in protos:
        m = SUFFIX.search(n)
        if not m:
            return None
        n = n[:m.start()]
    p = protos[n]
    if "tile_width" in p and "tile_height" in p:
        return float(p["tile_width"]), float(p["tile_height"])
    (x0, y0), (x1, y1) = p["collision_box"]
    return max(1.0, math.ceil(x1 - x0 - 1e-3)), max(1.0, math.ceil(y1 - y0 - 1e-3))


def jobs(name, entry, raw):
    """[(cell, camera, sprite mask, its centre, pixels a tile, offset, model file)]."""
    out = []
    for dn, args in score_proto.jobs_for(name, raw):
        opts, specs = fit.parse(score_proto.camera_args(name) + args)
        scale = float(opts["scale"])
        ppt = 32.0 / scale
        mask, centre = fit.sprite_mask(specs, ppt, scale)
        out.append((dn, opts, mask, centre, ppt, (0.0, 0.0), score_proto.model_of(name, dn)))
    if out or not entry:
        return out
    return [j + (name,) for j in fit_cells.jobs(name, step=max(1, len(entry["cells"]) // 8))]


def project(v, opts, off, pitch):
    """Screen x and up (tiles, up from the entity's position) of glTF vertices."""
    r = math.radians(float(opts["rot"]))
    p = math.radians(pitch)
    bx, by, bz = v[:, 0] + off[0], -(v[:, 2] + off[1]), v[:, 1]
    cs, sn = math.cos(-r), math.sin(-r)
    x, y = cs * bx - sn * by, sn * bx + cs * by
    up = y * float(opts["stretch"]) * math.sin(p) + bz * math.cos(p) - float(opts["anchor"]) * math.cos(p)
    return x, up


def raster(x, up, faces, shape, centre, ppt):
    """The model's mask in the sprite's frame (as fit.model_mask, any pitch)."""
    h, w = shape
    col = w / 2 + x * ppt - centre[0]
    row = h / 2 - up * ppt - centre[1]
    img = Image.new("L", (w, h), 0)
    draw = ImageDraw.Draw(img)
    for tri in np.stack([col, row], axis=1)[faces].tolist():
        draw.polygon([tuple(q) for q in tri], fill=255)
    return np.asarray(img) > 127


def tops(mask):
    """Per column, the first row covered (or -1)."""
    return np.where(mask.any(axis=0), mask.argmax(axis=0), -1)


def measure(meshes, js, pitch):
    """Per cell: (roof gap, peak gap) in tiles of height, sprite bottom (tiles below the
    entity's position), and the model's mask for overlays."""
    b = math.cos(math.radians(pitch))
    out = []
    for _cell, opts, mask, centre, ppt, off, model in js:
        if model not in meshes or not mask.any():
            continue
        v, faces = meshes[model]
        x, up = project(v, opts, off, pitch)
        m = raster(x, up, faces, mask.shape, centre, ppt)
        ts, tm = tops(mask), tops(m)
        both = (ts >= 0) & (tm >= 0)
        if both.sum() < 3:
            continue
        roof = float(np.median(tm[both] - ts[both])) / ppt / b
        rows_s, rows_m = np.where(mask.sum(axis=1) >= 2)[0], np.where(m.any(axis=1))[0]
        peak = float(rows_m.min() - rows_s.min()) / ppt / b if len(rows_s) and len(rows_m) else 0.0
        bottom = (rows_s.max() + 1 - (mask.shape[0] / 2 - centre[1])) / ppt
        out.append((roof, peak, bottom, m))
    return out


def overlay(name, js, results, out_dir):
    os.makedirs(out_dir, exist_ok=True)
    tiles = []
    for (_c, _o, mask, _ce, _p, _off, _m), (_r, _pk, _b, m) in list(zip(js, results))[:4]:
        img = np.zeros(mask.shape + (3,), np.uint8)
        img[mask] = (110, 110, 110)
        edge = m & ~(np.roll(m, 1, 0) & np.roll(m, -1, 0) & np.roll(m, 1, 1) & np.roll(m, -1, 1))
        img[edge] = (255, 40, 40)
        tiles.append(img)
    if tiles:
        h = max(t.shape[0] for t in tiles)
        row = np.concatenate([np.pad(t, ((0, h - t.shape[0]), (0, 4), (0, 0))) for t in tiles], axis=1)
        Image.fromarray(row).save(os.path.join(out_dir, name + ".png"))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("names", nargs="*")
    ap.add_argument("--dump")
    ap.add_argument("--csv")
    ap.add_argument("--pitch", type=float, default=48.0)
    ap.add_argument("--faces", type=int, default=6000)
    ap.add_argument("--png", help="overlays here (a git-ignored folder: they show the sprites' outlines)")
    a = ap.parse_args()
    raw = json.load(open(a.dump, encoding="utf-8")) if a.dump else __import__("icon_index").dump(fit_cells.FACTORIO)
    protos = prototypes(raw)
    entries = json.load(open(ENTRIES, encoding="utf-8"))
    names = a.names or sorted(set(entries) | set(score_proto.PICTURES) | set(score_proto.BELT_ROWS))
    rows = []
    print("%-36s %-4s %5s %6s %5s %6s %6s %6s %5s" % ("model", "game", "fp", "h", "str", "roof", "ratio", "peak", "base"))
    for name in names:
        e = entries.get(name)
        if (e or {}).get("projection") == "top":
            continue
        try:
            js = jobs(name, e, raw)
        except Exception as ex:  # noqa: BLE001  (a sheet missing from this install)
            print("%-36s skipped: %s" % (name, ex))
            continue
        meshes = {}
        for model in {j[6] for j in js}:
            glb = os.path.join(MODELS, model + ".glb")
            if os.path.exists(glb):
                meshes[model] = fit.load_mesh(glb, a.faces)
        if not meshes:
            continue
        res = measure(meshes, js, a.pitch)
        if not res:
            continue
        if a.png:
            overlay(name, js, res, a.png)
        h = float(max(v[:, 1].max() for v, _f in meshes.values()))
        fp = footprint(name, protos)
        files = [l["file"] for c in (e or {}).get("cells", []) for l in c] + [str(j[1].get("sprite", "")) for j in js]
        game = "SA" if any("space-age" in f for f in files) else "base"
        roof = float(np.median([r[0] for r in res]))
        peak = float(np.median([r[1] for r in res]))
        base = float(np.median([r[2] for r in res])) / (fp[1] / 2) if fp else float("nan")
        row = {"model": name, "game": game, "footprint": "%gx%g" % fp if fp else "", "height": round(h, 3),
               "stretch": float(js[0][1]["stretch"]), "anchor": float(js[0][1]["anchor"]),
               "roof": round(roof, 3), "ratio": round((h + roof) / h, 3) if h > 0.05 else float("nan"),
               "peak": round(peak, 3), "base": round(base, 3)}
        rows.append(row)
        print("%-36s %-4s %5s %6.2f %5.3g %+6.2f %6.2f %+6.2f %5.2f" % (
            name, game, row["footprint"], h, row["stretch"], roof, row["ratio"], peak, base), flush=True)
    for game in ("base", "SA"):
        r = [x for x in rows if x["game"] == game and x["height"] >= 0.5]
        if r:
            ratio = [x["ratio"] for x in r]
            print("%s: %d models 0.5 tiles or taller: ratio median %.3f (quartiles %.3f, %.3f), roof median %+.3f tiles; "
                  "a tenth or more short: %d, a tenth or more tall: %d" % (
                      game, len(r), np.median(ratio), np.percentile(ratio, 25), np.percentile(ratio, 75),
                      np.median([x["roof"] for x in r]), sum(x >= 1.1 for x in ratio), sum(x <= 0.9 for x in ratio)))
    if a.csv and rows:
        with open(a.csv, "w", newline="", encoding="utf-8") as fh:
            w = csv.DictWriter(fh, fieldnames=list(rows[0]))
            w.writeheader()
            w.writerows(rows)


if __name__ == "__main__":
    main()
