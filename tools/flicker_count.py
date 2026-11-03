#!/usr/bin/env python3
"""Counts flicker in frames saved by the client's --flicker-probe (the camera turning slowly over a
forest): a pixel flickers when its brightness jumps one way and back again, three times or more
over the frames (turning moves things smoothly; flicker flips back and forth).

    python3 tools/flicker_count.py <folder> [--threshold 0.08]

Frames from --flicker-probe=<folder>@pan (Factorio's view moved a pixel a frame) are lined up first with
--pan: frame k shifted k pixels right, so what stays put on the ground stays put in the stack and only
real flicker is left. --crop x0,y0,x1,y1 counts inside that rectangle only (leave the HUD out: it doesn't
move with the ground); --heat out.png marks the flickering pixels on the first frame.
"""
import argparse
import pathlib

import numpy as np
from PIL import Image


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("folder")
    ap.add_argument("--threshold", type=float, default=0.08, help="a brightness jump (0-1) that counts")
    ap.add_argument("--pan", action="store_true", help="frames from the @pan probe: line them up first")
    ap.add_argument("--crop", help="x0,y0,x1,y1: count inside this rectangle only")
    ap.add_argument("--heat", help="save the first frame with flickering pixels in magenta here")
    a = ap.parse_args()
    files = sorted(pathlib.Path(a.folder).glob("f*.png"))
    frames = [np.asarray(Image.open(f).convert("L"), dtype=np.float32) / 255.0 for f in files]
    if a.pan:
        # The view moved east a pixel a frame, so the ground moved left: what frame 0 shows in column
        # x, frame k shows in column x - k. Keep the ground every frame shows (frame 0's columns from n - 1).
        n = len(frames)
        frames = [f[:, n - 1 - k:f.shape[1] - k] for k, f in enumerate(frames)]
    stack = np.stack(frames)
    if a.crop:
        x0, y0, x1, y1 = (int(v) for v in a.crop.split(","))
        stack = stack[:, y0:y1, x0:x1]
    d = np.diff(stack, axis=0)
    sign = np.where(d > a.threshold, 1, np.where(d < -a.threshold, -1, 0))
    flips = np.zeros(stack.shape[1:], dtype=np.int32)
    last = np.zeros(stack.shape[1:], dtype=np.int32)
    for s in sign:
        flips += (s != 0) & (last != 0) & (s != last)
        last = np.where(s != 0, s, last)
    total = flips.size
    if a.heat:
        first = np.asarray(Image.open(files[0]).convert("RGB")).copy()
        if a.pan:
            first = first[:, len(files) - 1:]
        view = first[y0:y1, x0:x1] if a.crop else first[:, :flips.shape[1]]
        view[flips >= 3] = [255, 0, 255]
        Image.fromarray(np.ascontiguousarray(view)).save(a.heat)
    print(f"{len(files)} frames, {total} pixels: flipped back 3+ times {np.mean(flips >= 3) * 100:.2f}%, "
          f"1+ times {np.mean(flips >= 1) * 100:.2f}%")


if __name__ == "__main__":
    main()
