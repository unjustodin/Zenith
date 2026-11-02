"""Builds art-src/ui_reference/index.html: Factorio's window and ours side by side, with the
differences listed in docs/UI-DIFFERENCES.md (if you keep one) under each pair. Self-contained (the pictures are
embedded as JPEG), so it opens anywhere; it shows Factorio's art, so it stays out of git.

    python tools/ui_reference/compare.py

docs/UI-DIFFERENCES.md sections look like:

    ## Character window
    Pictures: `character`, `character_tab`
    - **unowned** Something that differs.
    - **fixed** Something that was fixed.

Needs Pillow (`pip install pillow`).
"""

import base64
import html
import io
import json
import re
import sys
from pathlib import Path

from PIL import Image

HERE = Path(__file__).resolve().parent
REPO = HERE.parent.parent
sys.path.insert(0, str(HERE))
from capture import main_checkout  # noqa: E402

WIDTH = 1280


def embed(path: Path) -> str:
    im = Image.open(path).convert("RGB")
    if im.width > WIDTH:
        im = im.resize((WIDTH, round(im.height * WIDTH / im.width)), Image.LANCZOS)
    buf = io.BytesIO()
    im.save(buf, "JPEG", quality=76)
    return "data:image/jpeg;base64," + base64.b64encode(buf.getvalue()).decode()


def parse_differences(md: str) -> list[dict]:
    sections = []
    cur = None
    for line in md.splitlines():
        if line.startswith("## "):
            cur = {"title": line[3:].strip(), "pictures": [], "items": [], "text": []}
            sections.append(cur)
        elif cur is None:
            continue
        elif line.startswith("Pictures:"):
            cur["pictures"] = re.findall(r"`([^`]+)`", line)
        elif line.startswith("- "):
            cur["items"].append(line[2:].strip())
        elif line.startswith("  ") and cur["items"]:
            cur["items"][-1] += " " + line.strip()
        elif line.strip():
            cur["text"].append(line.strip())
    return sections


def inline(md: str) -> str:
    s = html.escape(md)
    s = re.sub(r"\*\*([^*]+)\*\*", lambda m: f'<b class="tag {m.group(1).split()[0].lower()}">{m.group(1)}</b>', s)
    s = re.sub(r"`([^`]+)`", r"<code>\1</code>", s)
    return s


def main() -> int:
    root = main_checkout() / "art-src" / "ui_reference"
    ours_dir = root / "ours"
    refs = sorted(p.stem for p in root.glob("*.png"))
    ours = {p.stem for p in ours_dir.glob("*.png")}
    manifest = {}
    if (root / "manifest.json").exists():
        for r in json.loads((root / "manifest.json").read_text(encoding="utf-8")):
            manifest[r.get("name")] = r
    md_path = REPO / "docs" / "UI-DIFFERENCES.md"
    sections = parse_differences(md_path.read_text(encoding="utf-8")) if md_path.exists() else []
    covered = set()
    for s in sections:
        covered.update(s["pictures"])

    def pair(name: str) -> str:
        info = manifest.get(name, {}).get("info") or {}
        src = f' <span class="src">({html.escape(str(info.get("source")))})</span>' if isinstance(info, dict) and info.get("source") else ""
        left = f'<img loading="lazy" src="{embed(root / (name + ".png"))}">' if (root / (name + ".png")).exists() else '<div class="none">no Factorio picture</div>'
        right = f'<img loading="lazy" src="{embed(ours_dir / (name + ".png"))}">' if name in ours else '<div class="none">no picture of ours (no equivalent window, or the mock lacks the entity)</div>'
        return (f'<div class="pair"><div><h4>Factorio: <code>{name}</code>{src}</h4>{left}</div>'
                f'<div><h4>Ours</h4>{right}</div></div>')

    out = ["<!doctype html><html><head><meta charset='utf-8'><title>UI reference</title><style>",
           "body{background:#1e1e1e;color:#ddd;font:14px/1.45 system-ui,sans-serif;margin:0 16px 40px}",
           "h1{color:#ffe6c0}h2{color:#ffe6c0;border-top:2px solid #444;padding-top:16px;margin-top:32px}",
           "h4{margin:6px 0;color:#bbb;font-weight:600}.pair{display:grid;grid-template-columns:1fr 1fr;gap:12px;margin:8px 0}",
           "img{width:100%;border:1px solid #444;cursor:zoom-in}img.big{position:fixed;inset:0;width:auto;max-width:100vw;max-height:100vh;margin:auto;z-index:9;cursor:zoom-out;border:0;box-shadow:0 0 0 100vmax #000c}",
           ".none{border:1px dashed #555;padding:40px;text-align:center;color:#888}code{color:#ffcf7a}",
           "ul{margin:6px 0 0 0}.tag{padding:0 5px;border-radius:3px;font-size:12px}.tag.fixed{background:#2f6b33}",
           ".tag.unowned{background:#6b4a1f}.tag.circuits,.tag.planners,.tag.tiles,.tag.info,.tag.space{background:#2b4a6b}",
           ".src{color:#888;font-weight:400}nav a{color:#9cf;margin-right:10px}</style></head><body>",
           "<h1>Factorio's UI and ours, side by side</h1>",
           f"<p>{len(refs)} Factorio pictures (tools/ui_reference/capture.py), {len(ours)} of ours (ours.py), both 1920x1080 at UI scale 100%. "
           "Differences come from docs/UI-DIFFERENCES.md; click a picture to enlarge.</p><nav>"]
    for i, s in enumerate(sections):
        out.append(f'<a href="#s{i}">{html.escape(s["title"])}</a>')
    out.append('<a href="#rest">Other pictures</a></nav>')
    for i, s in enumerate(sections):
        out.append(f'<h2 id="s{i}">{html.escape(s["title"])}</h2>')
        for t in s["text"]:
            out.append(f"<p>{inline(t)}</p>")
        if s["items"]:
            out.append("<ul>" + "".join(f"<li>{inline(it)}</li>" for it in s["items"]) + "</ul>")
        for name in s["pictures"]:
            out.append(pair(name))
    rest = [n for n in refs if n not in covered and not n.startswith("fresh_")]
    out.append('<h2 id="rest">Other pictures</h2><p>Captured, not yet reviewed in UI-DIFFERENCES.md.</p>')
    for name in rest:
        out.append(f"<h3>{name}</h3>" + pair(name))
    out.append("<script>document.addEventListener('click',e=>{if(e.target.tagName==='IMG')e.target.classList.toggle('big')})</script></body></html>")
    (root / "index.html").write_text("\n".join(out), encoding="utf-8")
    print(f"{root / 'index.html'}: {len(sections)} sections, {len(refs)} references, {len(ours)} of ours")
    return 0


if __name__ == "__main__":
    sys.exit(main())
