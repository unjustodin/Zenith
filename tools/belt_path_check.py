#!/usr/bin/env python3
"""How far items on belts are drawn from their lanes (owner: items floated off belts on a dense
base, cutting across curves, over splitters and undergrounds).

    python tools/belt_path_check.py layout [--rcon-port 34198] [--x 0 --y 20]
        builds a test layout in real Factorio over RCON: for each belt tier, a row with a right
        and a left curve, a splitter, an underground and side-loading, fed with items on both lanes
    python tools/belt_path_check.py record --out truth.json [--rcon-port 34198] [--area x0,y0,x1,y1] [--ticks 600]
        records the belts there, every lane's line (get_line_item_position along it) and every
        item's place each tick: the truth the client's drawing is measured against
    python tools/belt_path_check.py check truth.json drawn.json [...]
        compares where the client drew each item (client/tests/belt_path_replay.tscn, or
        --belt-path-probe in the client against the same server) with the lanes: the distance from
        each drawn item to the nearest lane's centre line where items show, items drawn over an
        underground's gap, and items hidden where they should show

Positions are tiles; lanes and tracks are recorded in 1/256 tile, as the mod sends them.
"""

import argparse
import json
import math
import pathlib
import sys
import time

ROOT = pathlib.Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tools"))

LAYOUT_LUA = r"""
local s = game.surfaces.nauvis
local f = game.forces.player
local X, Y = %(x)d, %(y)d
local area = {{X - 2, Y - 2}, {X + 18, Y + 40}}
for _, e in pairs(s.find_entities_filtered({area = area})) do if e.type ~= "character" then e.destroy() end end
local tiles = {}
for x = X - 2, X + 17 do for y = Y - 2, Y + 39 do tiles[#tiles + 1] = {name = "refined-concrete", position = {x, y}} end end
s.set_tiles(tiles)
local N, E, W = defines.direction.north, defines.direction.east, defines.direction.west
local S = defines.direction.south
local function put(name, x, y, d, extra)
  local t = {name = name, position = {X + x, Y + y}, direction = d, force = f}
  if extra then for k, v in pairs(extra) do t[k] = v end end
  local e = s.create_entity(t)
  if not e then error("could not place " .. name) end
  return e
end
local tiers = {{"transport-belt", "underground-belt", "splitter"}, {"fast-transport-belt", "fast-underground-belt", "fast-splitter"},
  {"express-transport-belt", "express-underground-belt", "express-splitter"}, {"turbo-transport-belt", "turbo-underground-belt", "turbo-splitter"}}
storage.f3d_belt_test = {sources = {}, sinks = {}, items = {"iron-plate", "copper-plate", "iron-gear-wheel", "electronic-circuit"}, every = %(every)d}
local bt = storage.f3d_belt_test
for i, t in ipairs(tiers) do
  if prototypes.entity[t[1]] then
    local belt, ug, sp = t[1], t[2], t[3]
    local y0 = (i - 1) * 10
    for x = 0, 2 do put(belt, x + 0.5, y0 + 0.5, E) end
    for y = 0, 2 do put(belt, 3.5, y0 + y + 0.5, S) end
    put(belt, 3.5, y0 + 3.5, E)
    put(belt, 4.5, y0 + 3.5, E)
    put(sp, 5.5, y0 + 3, E)
    put(belt, 6.5, y0 + 2.5, E)
    put(belt, 7.5, y0 + 2.5, N)
    put(belt, 7.5, y0 + 1.5, N)
    put(belt, 6.5, y0 + 3.5, E)
    put(ug, 7.5, y0 + 3.5, E, {type = "input"})
    put(ug, 10.5, y0 + 3.5, E, {type = "output"})
    put(belt, 11.5, y0 + 3.5, E)
    put(belt, 12.5, y0 + 3.5, E)
    for y = 1, 6 do put(belt, 13.5, y0 + y + 0.5, N) end
    put(belt, 13.5, y0 + 0.5, W)
    put(belt, 12.5, y0 + 0.5, W)
    bt.sources[#bt.sources + 1] = s.find_entity(belt, {X + 0.5, Y + y0 + 0.5})
    bt.sinks[#bt.sinks + 1] = s.find_entity(belt, {X + 7.5, Y + y0 + 1.5})
    bt.sinks[#bt.sinks + 1] = s.find_entity(belt, {X + 12.5, Y + y0 + 0.5})
  end
end
script.on_nth_tick(1, function()
  local bt = storage.f3d_belt_test
  if not bt then return end
  local t = game.tick
  if t %% bt.every == 0 then
    for k, src in pairs(bt.sources) do
      if src.valid then
        for i = 1, 2 do
          src.get_transport_line(i).insert_at(0.0, {name = bt.items[(k + i + t / bt.every) %% 4 + 1], count = 1})
        end
      end
    end
  end
  for _, sink in pairs(bt.sinks) do
    if sink.valid then
      for i = 1, 2 do
        local l = sink.get_transport_line(i)
        for _, it in pairs(l.get_detailed_contents()) do
          if it.position < 0.3 then l.remove_item({name = it.stack.name, count = 1}) end
        end
      end
    end
  end
end)
rcon.print("built " .. #bt.sources .. " rows at " .. X .. "," .. Y)
"""

RECORD_LUA = r"""
local s = game.surfaces.nauvis
local area = {{%(x0)f, %(y0)f}, {%(x1)f, %(y1)f}}
local types = {"transport-belt", "underground-belt", "splitter"}
local belts, lanes = {}, {}
local function extra(e)
  if e.type == "transport-belt" then return string.sub(e.belt_shape, 1, 1) end
  if e.type == "underground-belt" then return string.sub(e.belt_to_ground_type, 1, 1) end
  return ""
end
for _, e in pairs(s.find_entities_filtered({area = area, type = types})) do
  belts[#belts + 1] = {e.name, e.type, e.position.x, e.position.y, e.direction, extra(e)}
  for i = 1, e.get_max_transport_line_index() do
    local l = e.get_transport_line(i)
    local len = l.line_length
    local pts = {}
    local n = math.max(2, math.ceil(len / 0.02))
    for k = 0, n do
      local p = l.get_line_item_position(len * k / n)
      pts[#pts + 1] = math.floor(p.x * 256 + 0.5)
      pts[#pts + 1] = math.floor(p.y * 256 + 0.5)
    end
    lanes[#lanes + 1] = {e.type, i, pts, extra(e), e.name}
  end
end
storage.f3d_rec = {belts = belts, lanes = lanes, tracks = {}, from = game.tick + 1, to = game.tick + %(ticks)d}
script.on_nth_tick(1, function()
  local bt = storage.f3d_belt_test
  if bt then
    local t = game.tick
    if t %% bt.every == 0 then
      for k, src in pairs(bt.sources) do
        if src.valid then
          for i = 1, 2 do
            src.get_transport_line(i).insert_at(0.0, {name = bt.items[(k + i + t / bt.every) %% 4 + 1], count = 1})
          end
        end
      end
    end
    for _, sink in pairs(bt.sinks) do
      if sink.valid then
        for i = 1, 2 do
          local l = sink.get_transport_line(i)
          for _, it in pairs(l.get_detailed_contents()) do
            if it.position < 0.3 then l.remove_item({name = it.stack.name, count = 1}) end
          end
        end
      end
    end
  end
  local r = storage.f3d_rec
  if not r then return end
  local t = game.tick
  if t < r.from or t > r.to then return end
  for _, e in pairs(s.find_entities_filtered({area = area, type = types})) do
    local box = e.selection_box
    local ug_in = e.type == "underground-belt" and e.belt_to_ground_type == "input"
    for i = 1, e.get_max_transport_line_index() do
      local l = e.get_transport_line(i)
      for _, it in pairs(l.get_detailed_contents()) do
        local p = l.get_line_item_position(it.position)
        -- 1: under the ground (an entrance's lines 3 and 4); 2: outside the entity (not sent)
        local flags = 0
        if ug_in and i >= 3 then flags = 1 end
        if e.type == "underground-belt" and (p.x < box.left_top.x - 0.05 or p.x > box.right_bottom.x + 0.05
            or p.y < box.left_top.y - 0.05 or p.y > box.right_bottom.y + 0.05) then flags = flags + 2 end
        local tr = r.tracks[it.unique_id]
        if not tr then tr = {} r.tracks[it.unique_id] = tr end
        local m = #tr
        if m == 0 or tr[m - 3] ~= t then
          tr[m + 1] = t
          tr[m + 2] = math.floor(p.x * 256 + 0.5)
          tr[m + 3] = math.floor(p.y * 256 + 0.5)
          tr[m + 4] = flags
        end
      end
    end
  end
  if t == r.to then
    local tracks = {}
    for uid, tr in pairs(r.tracks) do tracks[#tracks + 1] = {uid, tr} end
    helpers.write_file("%(file)s", helpers.table_to_json({belts = r.belts, lanes = r.lanes, tracks = tracks}), false)
    storage.f3d_rec = nil
  end
end)
rcon.print("recording ticks " .. storage.f3d_rec.from .. " to " .. storage.f3d_rec.to .. ", " .. #belts .. " belts")
"""


def rcon_run(lua, port):
    import rcon
    lines = [l for l in lua.splitlines() if l.strip() and not l.strip().startswith("--")]
    cmd = "/sc " + " ".join(lines)
    out = rcon.run(cmd, port=port, timeout=60.0)
    if not out.strip():  # the first /sc in a save only warns about achievements
        out = rcon.run(cmd, port=port, timeout=60.0)
    return out


# --- Geometry ------------------------------------------------------------------------------------

class Lanes:
    """Lane centre lines as segments, bucketed by tile for nearest-distance queries."""

    def __init__(self, lanes):
        self.cells = {}
        self.segs = []
        for lane in lanes:
            pts = lane[2]
            xs = [pts[i] / 256 for i in range(0, len(pts), 2)]
            ys = [pts[i] / 256 for i in range(1, len(pts), 2)]
            for k in range(len(xs) - 1):
                seg = (xs[k], ys[k], xs[k + 1], ys[k + 1])
                i = len(self.segs)
                self.segs.append(seg)
                for tx in range(math.floor(min(seg[0], seg[2])) - 1, math.floor(max(seg[0], seg[2])) + 2):
                    for ty in range(math.floor(min(seg[1], seg[3])) - 1, math.floor(max(seg[1], seg[3])) + 2):
                        self.cells.setdefault((tx, ty), []).append(i)

    def distance(self, x, y):
        best = math.inf
        for i in self.cells.get((math.floor(x), math.floor(y)), ()):
            ax, ay, bx, by = self.segs[i]
            dx, dy = bx - ax, by - ay
            ll = dx * dx + dy * dy
            t = 0.0 if ll == 0 else max(0.0, min(1.0, ((x - ax) * dx + (y - ay) * dy) / ll))
            d = math.hypot(ax + dx * t - x, ay + dy * t - y)
            if d < best:
                best = d
        return best


def is_hidden_lane(lane):
    # An entrance's lines 3 and 4 run under the ground; an exit's 3 and 4 are its unused back half.
    return lane[0] == "underground-belt" and lane[1] >= 3


def feature_of(belts):
    """tile -> (kind, tier) for each belt's tiles."""
    tiles = {}
    for name, typ, x, y, d, extra in belts:
        tier = name.split("-")[0] if name.split("-")[0] in ("fast", "express", "turbo") else "basic"
        if typ == "splitter":
            kind = "splitter"
            if d in (0, 8):
                cells = [(math.floor(x - 0.5), math.floor(y)), (math.floor(x + 0.5), math.floor(y))]
            else:
                cells = [(math.floor(x), math.floor(y - 0.5)), (math.floor(x), math.floor(y + 0.5))]
        else:
            kind = {"l": "curve", "r": "curve", "i": "underground", "o": "underground"}.get(extra, "straight")
            cells = [(math.floor(x), math.floor(y))]
        for c in cells:
            tiles[c] = (kind, tier)
    return tiles


def pct(values, p):
    if not values:
        return float("nan")
    s = sorted(values)
    return s[min(len(s) - 1, int(len(s) * p))]


def check(truth_path, drawn_path, warmup=60):
    truth = json.loads(pathlib.Path(truth_path).read_text())
    drawn = json.loads(pathlib.Path(drawn_path).read_text())
    visible = Lanes([l for l in truth["lanes"] if not is_hidden_lane(l)])
    tiles = feature_of(truth["belts"])
    # Sideload targets: straight belts whose side another belt points into are counted apart.
    by_tile = {}
    for name, typ, x, y, d, extra in truth["belts"]:
        by_tile[(math.floor(x), math.floor(y))] = (typ, d, extra)
    step = {0: (0, -1), 4: (1, 0), 8: (0, 1), 12: (-1, 0)}
    for (tx, ty), (typ, d, extra) in list(by_tile.items()):
        if typ == "transport-belt" and extra == "s":
            dx, dy = step[d]
            ahead = by_tile.get((tx + dx, ty + dy))
            if ahead and ahead[0] == "transport-belt" and ahead[2] == "s" and ahead[1] not in (d, (d + 8) % 16):
                tiles[(tx + dx, ty + dy)] = ("side-load", tiles[(tx + dx, ty + dy)][1])
    tracks = {}
    for uid, l in truth["tracks"]:
        tracks[uid] = {l[i]: (l[i + 1] / 256, l[i + 2] / 256, l[i + 3]) for i in range(0, len(l), 4)}
    dist = {}
    over_gap = 0
    hidden_wrong = 0
    hidden_right = 0
    hidden_examples = {}
    shown_n = 0
    lag = []
    worst = []
    frames = drawn["frames"]
    for row in frames[warmup:]:
        tick, drawn_tick = row[0], row[1]
        for i in range(2, len(row), 4):
            uid, x, y, shown = row[i], row[i + 1], row[i + 2], row[i + 3]
            tr = tracks.get(uid)
            if tr is None:
                continue
            # Where the game had it at the drawn tick.
            t0 = math.floor(drawn_tick)
            a, b = tr.get(t0), tr.get(t0 + 1)
            truth_at = None
            if a and b:
                u = drawn_tick - t0
                truth_at = (a[0] + (b[0] - a[0]) * u, a[1] + (b[1] - a[1]) * u, a[2] | b[2])
            elif a:
                truth_at = a
            if not shown:
                if truth_at is not None and not (truth_at[2] & 1):
                    # Shown in the game: wrong unless it is at an underground's middle (where it goes
                    # under or comes up) give or take a glide's step.
                    kind = tiles.get((math.floor(truth_at[0]), math.floor(truth_at[1])), ("", ""))[0]
                    if kind != "underground":
                        hidden_wrong += 1
                        if uid not in hidden_examples:
                            hidden_examples[uid] = (tick, uid, truth_at[0], truth_at[1])
                    else:
                        hidden_right += 1
                else:
                    hidden_right += 1
                continue
            shown_n += 1
            d = visible.distance(x, y)
            key = tiles.get((math.floor(x), math.floor(y)), ("off belts", ""))
            dist.setdefault(key[0], []).append(d)
            dist.setdefault("tier " + (key[1] or "-"), []).append(d)
            dist.setdefault("all", []).append(d)
            if d > 0.1:
                worst.append((d, tick, uid, x, y, key[0]))
            if truth_at is not None and truth_at[2] & 1:
                over_gap += 1
            if truth_at is not None:
                lag.append(math.hypot(x - truth_at[0], y - truth_at[1]))
    print("%s: period %s%s%s, %d frames, %d drawn items, %d hidden" % (
        pathlib.Path(drawn_path).name, drawn.get("period"), ", straight" if drawn.get("straight") else "",
        ", read %s ticks early" % drawn.get("lead") if drawn.get("lead") else "", len(frames) - warmup, shown_n,
        hidden_right + hidden_wrong))
    print("  distance from the nearest lane's centre line (tiles):")
    for k in sorted(dist, key=lambda k: (k.startswith("tier"), k)):
        v = dist[k]
        print("    %-12s n=%6d  p50 %.3f  p99 %.3f  max %.3f  over 0.1: %5.2f%%" % (
            k, len(v), pct(v, 0.5), pct(v, 0.99), max(v), 100.0 * sum(1 for d in v if d > 0.1) / len(v)))
    print("  shown while under the ground (in the game): %d; hidden where the game shows it: %d" % (over_gap, hidden_wrong))
    if lag:
        print("  from where the game had it at the drawn tick: p50 %.3f  p99 %.3f" % (pct(lag, 0.5), pct(lag, 0.99)))
    for e in list(hidden_examples.values())[:6]:
        print("    hidden at tick %d: item %d, the game had it at (%.2f, %.2f)" % e)
    for w in sorted(worst, reverse=True)[:8]:
        print("    worst: %.3f at tick %d, item %d (%.2f, %.2f) on %s" % w)
    st = drawn.get("stats")
    if st:
        print("  jobs %d, worker %.1f ms (%.2f a job, worst %.1f); glides: %s (not known, straight, path, snapped, too far)" % (
            st["jobs"], st["worker_usec"] / 1000, st["worker_usec"] / 1000 / max(1, st["jobs"]), st["worst_job_usec"] / 1000,
            st.get("routes")))
    return dist


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    lay = sub.add_parser("layout")
    lay.add_argument("--rcon-port", type=int, default=34198)
    lay.add_argument("--x", type=int, default=0)
    lay.add_argument("--y", type=int, default=20)
    lay.add_argument("--every", type=int, default=20, help="ticks between items put on each lane")
    rec = sub.add_parser("record")
    rec.add_argument("--rcon-port", type=int, default=34198)
    rec.add_argument("--area", default="-2,18,18,60")
    rec.add_argument("--ticks", type=int, default=600)
    rec.add_argument("--out", required=True)
    rec.add_argument("--script-output", default=str(ROOT / "server" / "data" / "script-output"))
    chk = sub.add_parser("check")
    chk.add_argument("truth")
    chk.add_argument("drawn", nargs="+")
    a = ap.parse_args()
    if a.cmd == "layout":
        print(rcon_run(LAYOUT_LUA % {"x": a.x, "y": a.y, "every": a.every}, a.rcon_port))
    elif a.cmd == "record":
        x0, y0, x1, y1 = (float(v) for v in a.area.split(","))
        name = "belt_truth_%d.json" % int(time.time())
        print(rcon_run(RECORD_LUA % {"x0": x0, "y0": y0, "x1": x1, "y1": y1, "ticks": a.ticks, "file": name}, a.rcon_port))
        path = pathlib.Path(a.script_output) / name
        deadline = time.time() + a.ticks / 60.0 * 3 + 30
        while time.time() < deadline and not path.exists():
            time.sleep(1.0)
        time.sleep(1.0)
        pathlib.Path(a.out).write_text(path.read_text())
        print("wrote", a.out)
    else:
        for d in a.drawn:
            check(a.truth, d)


if __name__ == "__main__":
    main()
