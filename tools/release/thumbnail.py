"""Draws the mod portal thumbnail (mod/factorio-3d-bridge/thumbnail.png, 144x144): a cube and
"3D" in Factorio-ish colours, drawn here so nothing of Wube's is used.

    python3 tools/release/thumbnail.py
"""

import pathlib

from PIL import Image, ImageDraw, ImageFont

OUT = pathlib.Path(__file__).resolve().parents[2] / "mod" / "factorio-3d-bridge" / "thumbnail.png"
SIZE = 144
SCALE = 4  # drawn large and scaled down, for smooth edges


def main():
    s = SIZE * SCALE
    img = Image.new("RGB", (s, s), (49, 48, 49))
    d = ImageDraw.Draw(img)
    # An isometric cube: top, left and right faces, like a machine seen from Factorio's angle.
    cx, cy, r = s // 2, int(s * 0.42), int(s * 0.26)
    top = [(cx, cy - r), (cx + r, cy - r // 2), (cx, cy), (cx - r, cy - r // 2)]
    left = [(cx - r, cy - r // 2), (cx, cy), (cx, cy + r), (cx - r, cy + r // 2)]
    right = [(cx + r, cy - r // 2), (cx, cy), (cx, cy + r), (cx + r, cy + r // 2)]
    d.polygon(top, fill=(255, 166, 39))
    d.polygon(left, fill=(201, 114, 20))
    d.polygon(right, fill=(150, 82, 14))
    for face in (top, left, right):
        d.line(face + face[:1], fill=(30, 28, 26), width=SCALE * 2)
    font = ImageFont.load_default(size=int(s * 0.2))
    text = "3D"
    w = d.textlength(text, font=font)
    d.text(((s - w) / 2, s * 0.74), text, font=font, fill=(255, 230, 192))
    img.resize((SIZE, SIZE), Image.LANCZOS).save(OUT)
    print("wrote", OUT)


if __name__ == "__main__":
    main()
