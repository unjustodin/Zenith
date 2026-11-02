"""The client's per-direction model offsets (model_library.gd PLACEMENT_OFFSETS), read for the
scorers so they place a model as the client does. Plain Python: Blender and the venv both use it."""

import os
import re

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
LIBRARY = os.path.join(REPO, "client", "scripts", "world", "model_library.gd")


def offsets():
    """{model: [[dx, dz] per direction]} (tiles, the model's own frame before it is turned)."""
    src = open(LIBRARY, encoding="utf-8").read()
    m = re.search(r"const PLACEMENT_OFFSETS := \{(.*?)\n\}", src, re.S)
    out = {}
    for name, body in re.findall(r'"([\w-]+)": \[(.*?)\]\]', m.group(1) if m else "", re.S):
        out[name] = [[float(a), float(b)] for a, b in re.findall(r"\[(-?[\d.]+), (-?[\d.]+)", body)]
    return out
