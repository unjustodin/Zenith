#!/usr/bin/env python3
"""Writes client/data/decoratives.json: which pictures each decorative (grass, flowers, small
rocks, decals) has, read from Factorio's own prototype data like tools/icon_index.py.

    python tools/decor_index.py [--factorio DIR] [--out FILE]

Runs `factorio --dump-data` (no window; the headless build works too) and keeps only file names
and numbers: the client loads the pictures from the player's own install at runtime
(decoratives.gd).

Format: {name: {"layer": render layer, "box": [x1, y1, x2, y2] (collision box, tiles),
"pics": [[file, x, y, width, height, scale, shift x, shift y], ...]}} where file is relative to
Factorio's data folder ("base/graphics/decorative/..."), x and y the picture's corner in the file
(sheets hold several), width and height in pixels, scale as in the prototype (0.5 for the usual
high-resolution pictures, so 32 pixels a tile at 1) and shift in tiles. At most MAX_PICS variants
per decorative.
"""

import argparse
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import icon_index  # noqa: E402

OUT = os.path.join(icon_index.REPO, "client", "data", "decoratives.json")
MAX_PICS = 8


def sprites(pictures):
    """The pictures of a SpriteVariations as plain sprites: a list of sprites, or one sheet with
    variation_count variants in rows of line_length. A sprite with layers uses its first."""
    if isinstance(pictures, dict):
        if "sheet" in pictures:
            return sprites(pictures["sheet"])
        if "layers" in pictures:
            return sprites(pictures["layers"][0])
        count = int(pictures.get("variation_count", 1))
        if count > 1 and "filename" in pictures:
            per_row = int(pictures.get("line_length", count)) or count
            out = []
            for i in range(min(count, MAX_PICS)):
                s = dict(pictures)
                s["x"] = int(pictures.get("x", 0)) + (i % per_row) * int(pictures["width"])
                s["y"] = int(pictures.get("y", 0)) + (i // per_row) * int(pictures["height"])
                out.append(s)
            return out
        return [pictures]
    out = []
    for p in pictures or []:
        out += sprites(p)
    return out


def record(s):
    if "filename" not in s or "width" not in s or "height" not in s:
        size = s.get("size")
        if "filename" not in s or size is None:
            return None
        w, h = (size, size) if isinstance(size, (int, float)) else size
    else:
        w, h = s["width"], s["height"]
    shift = icon_index.shift_of(s.get("shift")) or [0, 0]
    return [icon_index.file_of(s["filename"]), int(s.get("x", 0)), int(s.get("y", 0)), int(w), int(h),
            float(s.get("scale", 1)), round(float(shift[0]), 4), round(float(shift[1]), 4)]


def box_of(b):
    if not b:
        return [-0.5, -0.5, 0.5, 0.5]
    a, z = b[0], b[1]
    a = [a.get("x", 0), a.get("y", 0)] if isinstance(a, dict) else a
    z = [z.get("x", 0), z.get("y", 0)] if isinstance(z, dict) else z
    return [round(float(v), 3) for v in (a[0], a[1], z[0], z[1])]


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--factorio", default=os.environ.get("FACTORIO", icon_index.FACTORIO))
    parser.add_argument("--out", default=OUT)
    args = parser.parse_args()
    raw = icon_index.dump(args.factorio)
    index, empty = {}, []
    for name, proto in sorted(raw.get("optimized-decorative", {}).items()):
        pics = [r for r in (record(s) for s in sprites(proto.get("pictures"))) if r][:MAX_PICS]
        if not pics:
            empty.append(name)
            continue
        index[name] = {"layer": proto.get("render_layer", "decorative"), "box": box_of(proto.get("collision_box")),
                       "pics": pics}
    with open(args.out, "w", encoding="utf-8") as f:
        json.dump(index, f, separators=(",", ":"), sort_keys=True)
        f.write("\n")
    print("%d decoratives written to %s; %d without pictures: %s" % (len(index), args.out, len(empty), ", ".join(empty[:10])))


if __name__ == "__main__":
    main()
