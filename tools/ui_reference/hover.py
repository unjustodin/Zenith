"""Factorio's tooltips, hover states and click results, as reference for the 3D client's UI.

A script can't show a tooltip, and the mouse replaces a script's selection every frame, so
capture.py can't take these. This runs the same windowed Factorio (capture.py's config, mod and
save copy) in the mod's hover mode: each step prepares the game and writes
script-output/ui_reference/hover_<n>.json with actions in the 1920x1080 window's GUI pixels;
this script then moves and clicks the real mouse over the game window, presses keys, and grabs
the window from the screen (the GUI as drawn, tooltips included).

    python tools/ui_reference/hover.py                         # every hover step
    python tools/ui_reference/hover.py --only hover_entity,chat

Each step waits for this script's Ctrl+Shift+F9 (the mod's f3d-ui-next) before the next one.
It takes over the mouse and keyboard for a few minutes: don't use the PC meanwhile. Windows
only. The pictures go to art-src/ui_reference/ (git-ignored: they show Factorio's art).
"""

import argparse
import ctypes
import ctypes.wintypes as wt
import json
import shutil
import subprocess
import sys
import time
from pathlib import Path

from PIL import Image, ImageGrab

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from capture import DEFAULT_FACTORIO, RUN, default_save, env, factorio_cmd, main_checkout, write_setup  # noqa: E402

user32 = ctypes.windll.user32
W, H = 1920, 1080
VK = {"escape": 0x1B, "grave": 0xC0, "enter": 0x0D, "e": 0x45, "alt": 0x12}


def window_of(pid: int):
    found = []

    @ctypes.WINFUNCTYPE(wt.BOOL, wt.HWND, wt.LPARAM)
    def each(hwnd, _):
        owner = wt.DWORD()
        user32.GetWindowThreadProcessId(hwnd, ctypes.byref(owner))
        if owner.value == pid and user32.IsWindowVisible(hwnd):
            r = wt.RECT()
            user32.GetClientRect(hwnd, ctypes.byref(r))
            if r.right > 200:
                found.append(hwnd)
        return True

    user32.EnumWindows(each, 0)
    return found[0] if found else None


def client_rect(hwnd) -> tuple[int, int, int, int]:
    r = wt.RECT()
    user32.GetClientRect(hwnd, ctypes.byref(r))
    pt = wt.POINT(0, 0)
    user32.ClientToScreen(hwnd, ctypes.byref(pt))
    return pt.x, pt.y, r.right, r.bottom


def focus(hwnd) -> None:
    if user32.GetForegroundWindow() == hwnd:
        return
    me = ctypes.windll.kernel32.GetCurrentThreadId()
    fg = user32.GetWindowThreadProcessId(user32.GetForegroundWindow(), None)
    user32.AttachThreadInput(me, fg, True)
    user32.SetForegroundWindow(hwnd)
    user32.BringWindowToTop(hwnd)
    user32.AttachThreadInput(me, fg, False)


class NotInFront(RuntimeError):
    pass


def ensure_front(hwnd, under_cursor: bool = False) -> None:
    """Real input goes to whatever window is in front, so nothing is pressed, clicked or grabbed
    unless the game's window is the foreground window (and, for a click, the one under the
    mouse). Once it was another app and a click landed there: stop instead."""
    for attempt in range(2):
        ok = user32.GetForegroundWindow() == hwnd
        if ok and under_cursor:
            pt = wt.POINT(0, 0)
            user32.GetCursorPos(ctypes.byref(pt))
            under = user32.GetAncestor(user32.WindowFromPoint(pt), 2)  # GA_ROOT
            ok = under == hwnd
        if ok:
            return
        if attempt == 0:
            focus(hwnd)
            time.sleep(0.3)
    raise NotInFront("the game's window isn't in front (or isn't under the mouse); stopped before "
                     "sending input to another app")


def key(vk: int) -> None:
    scan = user32.MapVirtualKeyW(vk, 0)
    user32.keybd_event(vk, scan, 0, 0)
    time.sleep(0.05)
    user32.keybd_event(vk, scan, 2, 0)
    time.sleep(0.05)


def next_step() -> None:
    """Ctrl+Shift+F9: the mod's f3d-ui-next input, which starts the next step."""
    for vk in (0x11, 0x10, 0x78):
        user32.keybd_event(vk, user32.MapVirtualKeyW(vk, 0), 0, 0)
        time.sleep(0.03)
    for vk in (0x78, 0x10, 0x11):
        user32.keybd_event(vk, user32.MapVirtualKeyW(vk, 0), 2, 0)
        time.sleep(0.03)


def type_text(text: str) -> None:
    for ch in text:
        vk = user32.VkKeyScanW(ord(ch)) & 0xFF
        key(vk)


def click(button: str) -> None:
    down, up = (0x0002, 0x0004) if button == "left" else (0x0008, 0x0010)
    user32.mouse_event(down, 0, 0, 0, 0)
    time.sleep(0.06)
    user32.mouse_event(up, 0, 0, 0, 0)


def run_actions(hwnd, actions: list, out: Path) -> list[str]:
    grabbed = []
    focus(hwnd)
    for a in actions:
        kind = a[0]
        x0, y0, cw, ch = client_rect(hwnd)
        sx, sy = cw / W, ch / H
        if kind == "move":
            tx, ty = x0 + round(a[1] * sx), y0 + round(a[2] * sy)
            user32.SetCursorPos(tx + 2, ty + 2)  # a real move, so the game sees motion
            time.sleep(0.05)
            user32.SetCursorPos(tx, ty)
        elif kind == "wait":
            time.sleep(float(a[1]))
        elif kind == "click":
            ensure_front(hwnd, under_cursor=True)
            click(str(a[1]))
        elif kind == "key":
            ensure_front(hwnd)
            key(VK[str(a[1])])
        elif kind == "type":
            ensure_front(hwnd)
            type_text(str(a[1]))
        elif kind == "grab":
            ensure_front(hwnd)
            im = ImageGrab.grab(bbox=(x0, y0, x0 + cw, y0 + ch), all_screens=True)
            if im.size != (W, H):
                im = im.resize((W, H), Image.LANCZOS)
            im.save(out / (str(a[1]) + ".png"))
            grabbed.append(str(a[1]))
    return grabbed


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--save", type=Path, help="save to copy and load (default: the newest save in server/saves)")
    ap.add_argument("--only", default="", help="comma-separated step names (substrings)")
    ap.add_argument("--out", type=Path, default=None, help="where the pictures go (default: <main>/art-src/ui_reference)")
    ap.add_argument("--factorio", type=Path, default=DEFAULT_FACTORIO)
    ap.add_argument("--timeout", type=float, default=900)
    args = ap.parse_args()
    try:
        ctypes.windll.shcore.SetProcessDpiAwareness(2)  # screen coordinates in real pixels
    except OSError:
        user32.SetProcessDPIAware()

    out = args.out or main_checkout() / "art-src" / "ui_reference"
    out.mkdir(parents=True, exist_ok=True)
    only = [s.strip() for s in args.only.split(",") if s.strip()]
    write_setup(args.factorio, only, hover=True)
    source = args.save or default_save()
    save = RUN / "saves" / ("copy-" + source.name)
    shutil.copyfile(source, save)
    shots = RUN / "script-output" / "ui_reference"
    if shots.exists():
        shutil.rmtree(shots)

    print(f"Starting Factorio on {save.name}; it takes over the mouse once loaded...")
    proc = subprocess.Popen(factorio_cmd(args.factorio, "--load-game", str(save), "--window-size", f"{W}x{H}"),
                            env=env())
    print("pid", proc.pid)
    done = shots / "done.txt"
    start = time.time()
    n = 1
    grabbed: list[str] = []
    try:
        while time.time() - start < args.timeout:
            spec = shots / f"hover_{n:03d}.json"
            if spec.exists():
                time.sleep(0.1)
                step = json.loads(spec.read_text(encoding="utf-8"))
                hwnd = window_of(proc.pid)
                if hwnd is None:
                    print("no game window")
                    return 1
                actions = step.get("actions") or []
                if isinstance(actions, dict):
                    actions = [actions[k] for k in sorted(actions, key=int)]
                if n == 1:
                    print("game window client area:", client_rect(hwnd))
                got = run_actions(hwnd, actions, out)
                ensure_front(hwnd)
                next_step()
                print(step.get("name"), "->", ", ".join(got))
                grabbed += got
                n += 1
                continue
            if done.exists():
                break
            if proc.poll() is not None:
                print("Factorio exited early; see", RUN / "factorio-current.log")
                return 1
            time.sleep(0.1)
        else:
            print("Timed out")
    finally:
        if proc.poll() is None:
            proc.kill()  # only the game this script started
            proc.wait(30)
    manifest = shots / "manifest.json"
    if manifest.exists():
        for r in json.loads(manifest.read_text(encoding="utf-8") or "[]"):
            if isinstance(r, dict) and not r.get("ok"):
                print(f"  failed {r.get('name')}: {r.get('error')}")
    print(f"{len(grabbed)} pictures in {out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
