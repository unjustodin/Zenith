#!/usr/bin/env python3
"""Builds a dense, running test base next to the bridge's character over RCON, then measures what
the bridge costs per tick with it in view.

    powershell -ExecutionPolicy Bypass -File server\\run-server.ps1     (or server/run-headless.sh)
    godot --path client                    # optional: a client connected, looking at it
    python3 tools/busy_base.py             # build, then profile for 12 s and print /f3d-status
    python3 tools/busy_base.py --clear     # remove what it built
    python3 tools/busy_base.py --big --measure out.json   # 20k+ entities, measured without a client
    python3 tools/busy_base.py --no-build --measure out.json --budget tools/busy_budget.json

What it builds, south-east of the character (about 60 x 40 tiles, a few thousand entities):
- belt loops (`--loops`, each two belts wide and 40 long) packed with iron plates that keep
  circulating, so belt items (`bi`) change every update;
- a block of assembling machines making gears (`--assemblers`), each fed from an infinity chest
  by an inserter and emptied onto a belt loop by a second one, so inserter hands (`ih`) and
  machine states (`st`) keep changing;
- an electric energy interface and substations powering it.

--big adds, around the character (still within 5 chunks of it, so all of it is in view): a main
bus west of it (`--bus` lanes of belt loops 120 long, full of plates, circuits, coal...), a
double-headed train running between two stops to the north, a logistic network east of the
loops whose robots carry plates from a provider to a requester all the time, and a block of
stone walls that brings the count past 20,000 entities.

--measure connects a client of its own (tools/net_cost.py, standing still), profiles the bridge
per module for 12 s with /f3d-profile, times the chunk snapshots around the character, counts
what is near it and writes it all as JSON. With --budget it fails (exit 1) when the bridge's
script time per tick or its bytes per second is over the budget times --tolerance: CI's busy
job runs it on every push to catch a big regression.

Everything is made with raise_built, so a connected client gets it as normal `add`s. Every entity
is kept in storage.f3d_busy for --clear (get_entity_by_unit_number finds only vehicles and a few
more). Run it on a test save: it uses /c, which turns achievements off for the save.
"""

import argparse
import json
import pathlib
import re
import subprocess
import sys
import tempfile
import time

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import rcon  # noqa: E402

MOD = "__factorio-3d-bridge__"


def lua(code):
    """Runs Lua in the mod's state (so storage is the bridge's) and returns what it rcon.prints."""
    return rcon.run(f"/c {MOD} " + " ".join(line.strip() for line in code.strip().splitlines())).strip()


# Shared helpers, defined again in every command (each /c is its own chunk). `mk` creates an
# entity owned by the character's force, raises built, and is remembered for --clear.
PRELUDE = """
local c = storage.f3d.puppet local s = c.surface local f = c.force
storage.f3d_busy = storage.f3d_busy or {}
local made = 0
local function mk(spec)
  spec.force = f spec.raise_built = true
  local e = s.create_entity(spec)
  if e then made = made + 1 table.insert(storage.f3d_busy, e) end
  return e
end
local ox, oy = math.floor(c.position.x) + 4, math.floor(c.position.y) + 4
local function eei(x, y)
  local e = mk({ name = "electric-energy-interface", position = { x, y } })
  if e then e.power_production = 1e9 / 60 e.electric_buffer_size = 1e9 end
  return e
end
local function ins(name, x, y, tx, ty, d)
  local e = mk({ name = name, position = { x, y }, direction = d })
  if e then
    local p = e.drop_position
    if (p.x - tx) ^ 2 + (p.y - ty) ^ 2 > 0.5 then e.direction = (d + 8) % 16 end
  end
  return e
end
"""

E, S, W, N = "defines.direction.east", "defines.direction.south", "defines.direction.west", "defines.direction.north"


def build_power_at(width, height, y):
    return lua(PRELUDE + f"""
eei(ox - 2, oy + {y} - 2)
for x = 0, {width}, 16 do for y = 0, {height}, 16 do mk({{ name = "substation", position = {{ ox + x + 1, oy + {y} + y + 1 }} }}) end end
rcon.print(made)
""")


def build_power(width, height):
    return lua(PRELUDE + f"""
eei(ox - 2, oy - 2)
for x = 0, {width}, 16 do for y = 0, {height}, 16 do mk({{ name = "substation", position = {{ ox + x + 1, oy + y + 1 }} }}) end end
rcon.print(made)
""")


def build_loop(i, length):
    """One loop: east along row y, south, west along row y + 1, north; then filled with plates."""
    return lua(PRELUDE + f"""
local y = oy + 4 + {i} * 3 local x0 = ox + 2 local L = {length}
local belts = {{}}
for x = 0, L - 1 do
  belts[#belts + 1] = mk({{ name = "transport-belt", position = {{ x0 + x + 0.5, y + 0.5 }}, direction = x == L - 1 and {S} or {E} }})
  belts[#belts + 1] = mk({{ name = "transport-belt", position = {{ x0 + x + 0.5, y + 1.5 }}, direction = x == 0 and {N} or {W} }})
end
local items = 0
for _, b in pairs(belts) do
  if b then for l = 1, 2 do local line = b.get_transport_line(l)
    for p = 0, 0.75, 0.25 do if line.insert_at(p, {{ name = "iron-plate", count = 1 }}) then items = items + 1 end end
  end end
end
rcon.print(made .. " entities, " .. items .. " items")
""")


def build_assemblers(count, loops, top=None):
    """Rows of assemblers south of the loops: infinity chest -> inserter -> assembler -> inserter -> belt.
    Inserters are turned round if their drop position isn't where it should be (ins). No Lua comments in these strings:
    lua() joins the lines, so a comment would swallow the rest of the command."""
    return lua(PRELUDE + f"""
local top = {f"oy + {top}" if top is not None else f"oy + 4 + {loops} * 3 + 2"}
for i = 0, {count} - 1 do
  local x = ox + 2 + (i % 12) * 5 local y = top + math.floor(i / 12) * 7
  local chest = mk({{ name = "infinity-chest", position = {{ x + 1.5, y + 0.5 }} }})
  if chest then chest.set_infinity_container_filter(1, {{ name = "iron-plate", count = 100, index = 1 }}) end
  ins("inserter", x + 1.5, y + 1.5, x + 1.5, y + 2.5, {S})
  local a = mk({{ name = "assembling-machine-2", position = {{ x + 1.5, y + 3.5 }} }})
  if a then a.set_recipe("iron-gear-wheel") end
  ins("fast-inserter", x + 1.5, y + 5.5, x + 1.5, y + 6.5, {S})
  mk({{ name = "transport-belt", position = {{ x + 1.5, y + 6.5 }}, direction = {E} }})
end
rcon.print(made)
""")


def build_bus(lanes, length):
    """A main bus west of the character: lanes in pairs, each pair a loop (north up the first
    lane, south down the second), filled with a different item per pair."""
    return lua(PRELUDE + f"""
local items = {{ "iron-plate", "copper-plate", "iron-gear-wheel", "electronic-circuit", "coal", "stone", "steel-plate", "copper-cable" }}
local x0 = ox - 16 - {lanes} local y0 = oy - {length // 2} local L = {length}
local placed = 0
for p = 0, {lanes // 2} - 1 do
  local x = x0 + 2 * p local item = items[p % #items + 1]
  local belts = {{}}
  for y = 0, L - 1 do
    belts[#belts + 1] = mk({{ name = "transport-belt", position = {{ x + 0.5, y0 + y + 0.5 }}, direction = y == 0 and {E} or {N} }})
    belts[#belts + 1] = mk({{ name = "transport-belt", position = {{ x + 1.5, y0 + y + 0.5 }}, direction = y == L - 1 and {W} or {S} }})
  end
  for _, b in pairs(belts) do
    if b then for l = 1, 2 do local line = b.get_transport_line(l)
      for q = 0, 0.75, 0.25 do if line.insert_at(q, {{ name = item, count = 1 }}) then placed = placed + 1 end end
    end end
  end
end
rcon.print(made .. " entities, " .. placed .. " items")
""")


def build_train():
    """Rails east-west north of the base, a stop at each end and a double-headed train (a
    locomotive facing each way, two wagons between) running between them on a schedule."""
    return lua(PRELUDE + f"""
local x0 = 2 * math.floor(ox / 2) + 1 local y0 = 2 * math.floor(oy / 2) - 71
for i = -30, 20 do mk({{ name = "straight-rail", position = {{ x0 + 2 * i, y0 }}, direction = {E} }}) end
local east = mk({{ name = "train-stop", position = {{ x0 + 36, y0 + 2 }}, direction = {E} }})
local west = mk({{ name = "train-stop", position = {{ x0 - 56, y0 - 2 }}, direction = {W} }})
if east then east.backer_name = "F3D busy east" end
if west then west.backer_name = "F3D busy west" end
local front = mk({{ name = "locomotive", position = {{ x0, y0 }}, direction = {E} }})
mk({{ name = "cargo-wagon", position = {{ x0 - 7, y0 }}, direction = {E} }})
mk({{ name = "cargo-wagon", position = {{ x0 - 14, y0 }}, direction = {E} }})
local back = mk({{ name = "locomotive", position = {{ x0 - 21, y0 }}, direction = {W} }})
for _, l in pairs({{ front, back }}) do if l then l.get_fuel_inventory().insert({{ name = "coal", count = 50 }}) end end
local records = {{
  {{ station = "F3D busy east", wait_conditions = {{ {{ type = "time", compare_type = "or", ticks = 60 }} }} }},
  {{ station = "F3D busy west", wait_conditions = {{ {{ type = "time", compare_type = "or", ticks = 60 }} }} }},
}}
local state = "no train"
if front and front.train then
  local ok = pcall(function() front.train.get_schedule().set_records(records) end)
  if not ok then ok = pcall(function() front.train.schedule = {{ current = 1, records = records }} end) end
  front.train.manual_mode = false
  state = (ok and "scheduled, " or "no schedule, ") .. #front.train.carriages .. " carriages"
end
rcon.print(made .. " entities, " .. state)
""")


def build_robots(x, y):
    """A powered roboport with 50 logistic robots, an infinity chest feeding a passive provider
    and a requester emptied into an infinity chest that destroys what it gets, so robots fly
    plates across all the time."""
    return lua(PRELUDE + f"""
local x, y = ox + {x}, oy + {y}
eei(x - 4, y)
mk({{ name = "substation", position = {{ x - 1, y }} }})
local port = mk({{ name = "roboport", position = {{ x + 3, y }} }})
if port then port.get_inventory(defines.inventory.roboport_robot).insert({{ name = "logistic-robot", count = 50 }}) end
local src = mk({{ name = "infinity-chest", position = {{ x - 3.5, y + 6.5 }} }})
if src then src.set_infinity_container_filter(1, {{ name = "iron-plate", count = 100, index = 1 }}) end
ins("fast-inserter", x - 2.5, y + 6.5, x - 1.5, y + 6.5, {E})
mk({{ name = "passive-provider-chest", position = {{ x - 1.5, y + 6.5 }} }})
local req = mk({{ name = "requester-chest", position = {{ x + 7.5, y + 12.5 }} }})
local ok = req and pcall(function()
  local sec = req.get_logistic_sections().add_section()
  sec.filters = {{ {{ value = {{ type = "item", name = "iron-plate", quality = "normal", comparator = "=" }}, min = 200 }} }}
end)
ins("fast-inserter", x + 8.5, y + 12.5, x + 9.5, y + 12.5, {E})
local sink = mk({{ name = "infinity-chest", position = {{ x + 9.5, y + 12.5 }} }})
if sink then sink.remove_unfiltered_items = true end
rcon.print(made .. " entities, request " .. (ok and "set" or "failed"))
""")


def build_walls(x, y, width, height):
    """A solid block of stone walls: static entities that only cost snapshots and memory."""
    out = []
    for y0 in range(0, height, 25):
        out.append(lua(PRELUDE + f"""
for dy = {y0}, math.min({height}, {y0} + 25) - 1 do for dx = 0, {width} - 1 do
  mk({{ name = "stone-wall", position = {{ ox + {x} + dx + 0.5, oy + {y} + dy + 0.5 }} }})
end end
rcon.print(made)
"""))
    return sum(int(v) for v in out if v.isdigit())


def clear():
    return lua("""
local n = 0
for _, e in pairs(storage.f3d_busy or {}) do
  if e and e.valid then e.destroy() n = n + 1 end
end
storage.f3d_busy = nil
rcon.print(n .. " removed")
""")


def count_near():
    """What the bridge has to look at near the character, and how long the chunk snapshots
    around it take (world.record for every entity, the tiles' ids)."""
    out = lua("""
local world = package.loaded["__factorio-3d-bridge__/scripts/world.lua"]
local registry = package.loaded["__factorio-3d-bridge__/scripts/registry.lua"]
local c = storage.f3d.puppet local s = c.surface
local ccx, ccy = math.floor(c.position.x / 32), math.floor(c.position.y / 32)
local profiler = helpers.create_profiler()
local n, chunks = 0, 0
for cy = ccy - 5, ccy + 5 do for cx = ccx - 5, ccx + 5 do
  local x0, y0 = cx * 32, cy * 32
  chunks = chunks + 1
  for y = y0, y0 + 31 do for x = x0, x0 + 31 do registry.tile_id(s.get_tile(x, y).name) end end
  for _, e in pairs(s.find_entities_filtered({ area = { { x0, y0 }, { x0 + 32, y0 + 32 } }, type = registry.excluded_types(), invert = true })) do
    world.record(e) n = n + 1
  end
end end
profiler.stop()
local items = 0
local belts = s.find_entities_filtered({ position = c.position, radius = 24, type = { "transport-belt", "underground-belt", "splitter" } })
for _, b in pairs(belts) do for l = 1, b.get_max_transport_line_index() do items = items + #b.get_transport_line(l).get_detailed_contents() end end
local inserters = s.count_entities_filtered({ position = c.position, radius = 24, type = "inserter" })
local robots = s.count_entities_filtered({ position = c.position, radius = 96, type = { "logistic-robot", "construction-robot" } })
rcon.print({ "", chunks .. " " .. n .. " " .. #belts .. " " .. items .. " " .. inserters .. " " .. robots .. " ", profiler })
""")
    m = re.match(r"(\d+) (\d+) (\d+) (\d+) (\d+) (\d+) Duration: ([\d.]+) ?ms", out)
    if not m:
        raise RuntimeError("counting failed: " + out)
    chunks, entities, belts, items, inserters, robots = (int(v) for v in m.groups()[:6])
    ms = float(m.group(7))
    return {"chunks": chunks, "entities": entities, "snapshot_ms": round(ms, 2),
            "snapshot_ms_per_chunk": round(ms / chunks, 3), "belts_r24": belts, "belt_items_r24": items,
            "inserters_r24": inserters, "robots_r96": robots}


def belt_breakdown():
    """What reading the belt items near the character costs, call by call (one pass each), to see
    where belt_items.lua's time goes."""
    out = lua("""
local c = storage.f3d.puppet local s = c.surface
local belts = s.find_entities_filtered({ position = c.position, radius = 24, type = { "transport-belt", "underground-belt", "splitter" } })
local function time(fn) local p = helpers.create_profiler() fn() p.stop() return p end
local lines = {}
local t_lines = time(function() for _, b in pairs(belts) do for l = 1, b.get_max_transport_line_index() do lines[#lines + 1] = b.get_transport_line(l) end end end)
local contents = {}
local t_contents = time(function() for i, line in ipairs(lines) do contents[i] = line.get_detailed_contents() end end)
local t_names = time(function() for _, list in ipairs(contents) do for _, it in pairs(list) do local n = it.stack.name end end end)
local t_pos = time(function() for i, list in ipairs(contents) do local line = lines[i] for _, it in pairs(list) do local p = line.get_line_item_position(it.position) end end end)
local t_box = time(function() for _, b in pairs(belts) do local box = b.selection_box end end)
local registry = package.loaded["__factorio-3d-bridge__/scripts/registry.lua"]
local world = package.loaded["__factorio-3d-bridge__/scripts/world.lua"]
local spoilage = package.loaded["__factorio-3d-bridge__/scripts/spoilage.lua"]
local flat = {}
local t_flat = time(function() for i, list in ipairs(contents) do local line = lines[i] for _, it in pairs(list) do
  flat[#flat + 1] = it.unique_id flat[#flat + 1] = registry.item_id(it.stack.name)
  local p = line.get_line_item_position(it.position) flat[#flat + 1] = world.fixed(p.x) flat[#flat + 1] = world.fixed(p.y)
  local f = spoilage.freshness(it.stack) end end end)
local t_json = time(function() for i = 1, #flat, 1200 do local slice = {} for j = i, math.min(i + 1199, #flat) do slice[#slice + 1] = flat[j] end local json = helpers.table_to_json({ t = "bi", l = slice }) end end)
local bi = package.loaded["__factorio-3d-bridge__/scripts/belt_items.lua"]
local worst, checked = 0, 0
if bi.check_straight then for _, b in pairs(belts) do if b.type == "transport-belt" and b.belt_shape == "straight" then
  for _, r in pairs(bi.check_straight(b)) do worst = math.max(worst, math.abs(r[1] - r[3]), math.abs(r[2] - r[4])) checked = checked + 1 end
end end end
local t_concat = time(function() for i = 1, #flat, 1200 do local body = table.concat(flat, ",", i, math.min(i + 1199, #flat)) local json = '{"t":"bi","l":[' .. body .. "]}" end end)
local one = helpers.create_profiler() for i = 1, 100000 do local x = i * i end one.stop()
local avg = helpers.create_profiler(true) for i = 1, 600 do avg.add(one) end avg.divide(600)
rcon.print({ "", { "", "lines ", t_lines, "; get_detailed_contents ", t_contents, "; stack.name ", t_names, "; get_line_item_position ", t_pos, "; selection_box ", t_box },
  { "", "; records ", t_flat, "; json ", t_json, "; concat ", t_concat, "; check_one ", one, "; check_avg600 ", avg, "; straight shortcut error ", string.format("%.4f", worst), " tiles over " .. checked .. " items" } })
""")
    print("belt items, call by call:", out)
    return {name.strip(): float(ms) for name, ms in re.findall(r"([\w_. ]+) Duration: ([\d.]+) ?ms", out)}


def game_tick():
    return int(lua("rcon.print(game.tick)"))


def ups(seconds=5.0):
    """Game ticks per second over a few seconds (60 unless the game can't keep up)."""
    tick0, t0 = game_tick(), time.monotonic()
    time.sleep(seconds)
    return round((game_tick() - tick0) / (time.monotonic() - t0), 1)


def parse_profile(status):
    """{module: ms per tick} from /f3d-status's profiling lines."""
    return {name: float(ms) for name, ms in re.findall(r"\[Zenith\] ([\w-]+): Duration: ([\d.]+) ?ms per tick", status)}


def measure(seconds, path):
    """Connects a client (net_cost.py, standing still) and profiles the bridge while it streams
    the base, then writes everything as JSON."""
    # The game's own speed with nobody connected, then with the bridge serving a client.
    result = {"near": count_near(), "belt_calls_ms": belt_breakdown(), "ups_no_client": ups()}
    with tempfile.TemporaryDirectory() as tmp:
        tallies = pathlib.Path(tmp) / "net.json"
        client = subprocess.Popen([sys.executable, str(pathlib.Path(__file__).with_name("net_cost.py")), "--port", "34200",
                                   "--still", "--seconds", str(seconds + 30), "--json", str(tallies)],
                                  stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
        # net_cost spends 5 s on the handshake and the first snapshots before it counts.
        time.sleep(6)
        tick0, t0 = game_tick(), time.monotonic()
        rcon.run("/f3d-profile")
        # The first average needs 600 game ticks: longer than 10 s when the game runs slow.
        time.sleep(seconds)
        status = rcon.run("/f3d-status")
        while not parse_profile(status) and time.monotonic() - t0 < seconds + 24:
            time.sleep(2)
            status = rcon.run("/f3d-status")
        rcon.run("/f3d-profile")
        result["ups"] = round((game_tick() - tick0) / (time.monotonic() - t0), 1)
        result["robots"] = lua("""
local c = storage.f3d.puppet local s = c.surface
local flying = s.count_entities_filtered({ position = c.position, radius = 120, type = "logistic-robot" })
local net = ""
for _, port in pairs(s.find_entities_filtered({ position = c.position, radius = 120, name = "roboport", limit = 1 })) do
  local n = port.logistic_network
  local prov = s.find_entities_filtered({ position = port.position, radius = 20, name = "passive-provider-chest", limit = 1 })[1]
  local req = s.find_entities_filtered({ position = port.position, radius = 20, name = "requester-chest", limit = 1 })[1]
  net = (n and (n.all_logistic_robots .. " robots, " .. n.available_logistic_robots .. " idle") or "no network")
    .. "; provider " .. (prov and prov.get_item_count() or -1) .. ", requester " .. (req and req.get_item_count() or -1)
end
rcon.print(flying .. " flying; " .. net)
""")
        print("robots after the measurement:", result["robots"])
        report, _ = client.communicate(timeout=180)
        print(report)
        if client.returncode != 0 or not tallies.exists():
            raise RuntimeError("the measuring client failed")
        net = json.loads(tallies.read_text())
    print(status)
    modules = parse_profile(status)
    if not modules:
        raise RuntimeError("no profile in /f3d-status (was the client connected for 10 s?)")
    steady = net["steady"]
    result.update({
        "modules_ms": modules,
        "total_ms": round(sum(modules.values()), 3),
        "kb_per_s": round(steady["bytes"] / 1024 / steady["seconds"], 1),
        "packets_per_s": round(steady["packets"] / steady["seconds"], 1),
        "kb_per_s_by_type": {t: round(r["bytes"] / 1024 / steady["seconds"], 2) for t, r in steady["types"].items()},
        "handshake_kb": round(net["setup"]["bytes"] / 1024, 1),
    })
    pathlib.Path(path).write_text(json.dumps(result, indent=1))
    return result


def check_budget(result, budget_path, tolerance):
    """Problems where the result is over the budget times the tolerance."""
    budget = json.loads(pathlib.Path(budget_path).read_text())
    problems = []
    for key in ("total_ms", "kb_per_s", "snapshot_ms_per_chunk"):
        got = result.get(key, result["near"].get(key))
        if key in budget and got is not None and got > budget[key] * tolerance:
            problems.append(f"{key} {got} is over {tolerance} x the budget {budget[key]}")
    for name, ms in budget.get("modules_ms", {}).items():
        got = result["modules_ms"].get(name, 0.0)
        # A floor, so a module that costs next to nothing can't fail on noise.
        if got > max(ms * tolerance, 0.1):
            problems.append(f"module {name}: {got} ms per tick is over {tolerance} x the budget {ms}")
    if result["near"]["entities"] < budget.get("min_entities", 0):
        problems.append(f"only {result['near']['entities']} entities near the character (the base wasn't built?)")
    return problems


def profile(seconds):
    print(rcon.run("/f3d-profile"))
    time.sleep(seconds)
    print(rcon.run("/f3d-status"))
    print(rcon.run("/f3d-profile"))


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--loops", type=int, default=8, help="belt loops (each 2 x 40 belts, full of plates)")
    parser.add_argument("--length", type=int, default=40)
    parser.add_argument("--assemblers", type=int, default=36)
    parser.add_argument("--seconds", type=float, default=12.0, help="how long to profile (the report needs 10 s)")
    parser.add_argument("--clear", action="store_true", help="remove what an earlier run built, and stop")
    parser.add_argument("--no-build", action="store_true", help="only profile")
    parser.add_argument("--big", action="store_true", help="also a main bus, a train, robots and walls: 20,000+ entities")
    parser.add_argument("--bus", type=int, default=24, help="--big: main bus lanes")
    parser.add_argument("--measure", metavar="OUT.json", help="measure with a client of its own instead of printing /f3d-status")
    parser.add_argument("--budget", help="with --measure: fail when over this budget (JSON) times --tolerance")
    parser.add_argument("--tolerance", type=float, default=2.0)
    args = parser.parse_args()
    if args.big:
        args.loops, args.length, args.assemblers = max(args.loops, 20), max(args.length, 60), max(args.assemblers, 120)

    rcon.run("/c rcon.print('ok')")  # the first /c in a save only warns about achievements
    if args.measure and lua("rcon.print(storage.f3d.puppet and storage.f3d.puppet.valid and 1 or 0)") != "1":
        # The bridge makes its character for the first client: connect once to get one.
        subprocess.run([sys.executable, str(pathlib.Path(__file__).with_name("net_cost.py")), "--port", "34200",
                        "--still", "--seconds", "1"], check=True, stdout=subprocess.DEVNULL)
    if args.clear:
        print(clear())
        return
    if not args.no_build:
        print("power:", build_power(args.length + 4, args.loops * 3 + 8 + (args.assemblers // 12 + 1) * 7))
        for i in range(args.loops):
            print(f"loop {i + 1}:", build_loop(i, args.length))
        print("assemblers:", build_assemblers(args.assemblers, args.loops))
        if args.big:
            print("bus:", build_bus(args.bus, 120))
            print("train:", build_train())
            print("robots:", build_robots(args.length + 8, 0))
            # A block next to the character, inside the detail radius, so inserter hands (`ih`)
            # are measured too; its own power, north of the character.
            print("power north:", build_power_at(args.length + 4, 28, -30))
            print("assemblers north:", build_assemblers(36, args.loops, top=-28))
            print("walls:", build_walls(args.length + 30, -100, 70, 200))
    if not args.measure:
        profile(args.seconds)
        return
    result = measure(args.seconds, args.measure)
    print(json.dumps({k: v for k, v in result.items() if k != "kb_per_s_by_type"}, indent=1))
    if args.budget:
        problems = check_budget(result, args.budget, args.tolerance)
        for p in problems:
            print("OVER BUDGET:", p)
        if problems:
            sys.exit(1)
        print(f"within {args.tolerance} x the budget in {args.budget}")


if __name__ == "__main__":
    main()
