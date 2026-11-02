#!/usr/bin/env python3
"""Counts flicker in frames saved by the client's --flicker-probe (the camera turning slowly over a
forest): a pixel flickers when its brightness jumps one way and back again, three times or more
over the frames (turning moves things smoothly; flicker flips back and forth).

    python3 tools/flicker_count.py <folder> [--threshold 0.08]
"""
import argparse
import pathlib

import numpy as np
from PIL import Image


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("folder")
    ap.add_argument("--threshold", type=float, default=0.08, help="a brightness jump (0-1) that counts")
    a = ap.parse_args()
    files = sorted(pathlib.Path(a.folder).glob("f*.png"))
    frames = [np.asarray(Image.open(f).convert("L"), dtype=np.float32) / 255.0 for f in files]
    stack = np.stack(frames)
    d = np.diff(stack, axis=0)
    sign = np.where(d > a.threshold, 1, np.where(d < -a.threshold, -1, 0))
    flips = np.zeros(stack.shape[1:], dtype=np.int32)
    last = np.zeros(stack.shape[1:], dtype=np.int32)
    for s in sign:
        flips += (s != 0) & (last != 0) & (s != last)
        last = np.where(s != 0, s, last)
    total = flips.size
    print(f"{len(files)} frames, {total} pixels: flipped back 3+ times {np.mean(flips >= 3) * 100:.2f}%, "
          f"1+ times {np.mean(flips >= 1) * 100:.2f}%")


if __name__ == "__main__":
    main()
