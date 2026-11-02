#!/usr/bin/env python3
"""Builds a defended wall east of the bridge's character and sends waves of biters and spitters at
it over RCON, to measure what fights cost (the client's frame time, the bridge's script time).

    powershell -ExecutionPolicy Bypass -File server\\run-server.ps1     (a test save: it uses /c)
    python3 tools/attack_wave.py --build                  # the wall, turrets, power and ammo
    python3 tools/attack_wave.py --wave 150               # 150 enemies from the east, then waits
    python3 tools/attack_wave.py --wave 150 --profile     # and /f3d-profile while they fight
    python3 tools/attack_wave.py --clear                  # everything it built, and the enemies

The wall runs north-south 20 tiles east of where the character was (it is then moved 10 tiles in front of it), 48 tiles long, with gun turrets (piercing
ammo), laser turrets (an electric energy interface and substations) and two flamethrower turrets
(light oil put straight in) behind it. Enemies (a mix of small, medium and big biters and spitters)
appear 40-60 tiles east of the wall and are told to attack the area behind it. The character is
made indestructible, the day stays light and the turrets are refilled before every wave.
"""

import argparse
import pathlib
import sys
import time

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import rcon  # noqa: E402

MOD = "__factorio-3d-bridge__"
PORT = None


def lua(code):
    return rcon.run(f"/c {MOD} " + " ".join(line.strip() for line in code.strip().splitlines()), port=PORT, timeout=60.0).strip()


PRELUDE = """
local c = storage.f3d.puppet local s = c.surface local f = c.force
storage.f3d_wave = storage.f3d_wave or {}
storage.f3d_wave_o = storage.f3d_wave_o or { math.floor(c.position.x) + 20, math.floor(c.position.y) }
local ox, oy = storage.f3d_wave_o[1], storage.f3d_wave_o[2]
local function mk(spec)
  spec.force = spec.force or f spec.raise_built = true
  local e = s.create_entity(spec)
  if e then table.insert(storage.f3d_wave, e) end
  return e
end
"""

BUILD = PRELUDE + """
c.destructible = false
s.always_day = true
for y = oy - 24, oy + 24 do
  for _, x in pairs({ ox, ox + 1 }) do
    local area = { { x - 0.5, y - 0.5 }, { x + 0.5, y + 0.5 } }
    for _, e in pairs(s.find_entities_filtered({ area = area, type = { "tree", "simple-entity", "cliff" } })) do e.destroy() end
    mk({ name = "stone-wall", position = { x + 0.5, y + 0.5 } })
  end
end
for y = oy - 26, oy + 26, 1 do
  for x = ox - 8, ox - 1 do
    for _, e in pairs(s.find_entities_filtered({ area = { { x, y }, { x + 1, y + 1 } }, type = { "tree", "simple-entity", "cliff" } })) do e.destroy() end
  end
end
local n = 0
for y = oy - 22, oy + 22, 4 do
  mk({ name = "gun-turret", position = { ox - 2, y } })
  mk({ name = "laser-turret", position = { ox - 2, y + 2 } })
  n = n + 2
end
mk({ name = "flamethrower-turret", position = { ox - 3, oy - 6 }, direction = defines.direction.east })
mk({ name = "flamethrower-turret", position = { ox - 3, oy + 6 }, direction = defines.direction.east })
for y = oy - 18, oy + 18, 18 do
  mk({ name = "substation", position = { ox - 6, y } })
end
local eei = mk({ name = "electric-energy-interface", position = { ox - 8, oy } })
if eei then eei.power_production = 1e9 / 60 eei.electric_buffer_size = 1e9 end
c.teleport({ ox - 10, oy })  -- the wall in the client's default view
rcon.print("built " .. #storage.f3d_wave)
"""

REFILL = PRELUDE + """
local n = 0
for _, e in pairs(storage.f3d_wave) do
  if e.valid and e.force == f then
    if e.name == "gun-turret" then
      e.insert({ name = "piercing-rounds-magazine", count = 200 - e.get_item_count("piercing-rounds-magazine") }) n = n + 1
    elseif e.name == "flamethrower-turret" then
      e.insert_fluid({ name = "light-oil", amount = 1000 }) n = n + 1
    end
    if e.health then e.health = e.max_health end
  end
end
rcon.print("refilled " .. n)
"""

WAVE = PRELUDE + """
local kinds = { "small-biter", "small-biter", "medium-biter", "medium-biter", "big-biter",
  "small-spitter", "medium-spitter", "big-spitter" }
local made = 0
local units = {}
local i = 0
local tries = 0
while made < %(n)d and tries < %(n)d * 4 do
  tries = tries + 1
  i = i + 1
  local name = kinds[(i - 1) %% #kinds + 1]
  local p = { ox + 40 + math.random() * 20, oy - 20 + math.random() * 40 }
  local at = s.find_non_colliding_position(name, p, 6, 0.5)
  if at then
    local e = s.create_entity({ name = name, position = at, force = "enemy" })
    if e then made = made + 1 table.insert(units, e) end
  end
end
local group = s.create_unit_group({ position = { ox + 45, oy }, force = "enemy" })
for _, e in pairs(units) do group.add_member(e) end
group.set_command({ type = defines.command.attack_area, destination = { ox - 4, oy }, radius = 16,
  distraction = defines.distraction.by_enemy })
group.start_moving()
rcon.print("wave " .. made)
"""

COUNT = PRELUDE + """
local n = s.count_entities_filtered({ force = "enemy", type = { "unit" }, position = { ox, oy }, radius = 120 })
local corpses = s.count_entities_filtered({ type = "corpse", position = { ox, oy }, radius = 120 })
rcon.print(n .. " " .. corpses .. " " .. game.tick)
"""

CLEAR = PRELUDE + """
local n = 0
for _, e in pairs(storage.f3d_wave) do if e.valid then e.destroy() n = n + 1 end end
storage.f3d_wave = {}
storage.f3d_wave_o = nil
for _, e in pairs(s.find_entities_filtered({ force = "enemy", type = "unit", position = { ox, oy }, radius = 150 })) do e.destroy() n = n + 1 end
for _, e in pairs(s.find_entities_filtered({ type = "corpse", position = { ox, oy }, radius = 150 })) do e.destroy() end
rcon.print("cleared " .. n)
"""


def main():
    global PORT
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--rcon-port", type=int, default=None)
    ap.add_argument("--build", action="store_true")
    ap.add_argument("--clear", action="store_true")
    ap.add_argument("--wave", type=int, default=0, help="send this many enemies")
    ap.add_argument("--wait", type=float, default=60.0, help="seconds to watch a wave (the enemies left are printed)")
    ap.add_argument("--delay", type=float, default=0.0, help="seconds to wait first (a client probe warming up)")
    ap.add_argument("--profile", action="store_true", help="/f3d-profile during the wave: /f3d-status at 20 s and at the end")
    a = ap.parse_args()
    PORT = a.rcon_port
    time.sleep(a.delay)
    if a.clear:
        print(lua(CLEAR))
    if a.build:
        print(lua(BUILD))
    if a.wave:
        print(lua(REFILL))
        print(lua(WAVE % {"n": a.wave}))
        if a.profile:
            print(rcon.run("/f3d-profile", port=PORT, timeout=30.0))
        start = time.time()
        profiled = False
        while time.time() - start < a.wait:
            time.sleep(2.0)
            line = lua(COUNT)
            print(f"{time.time() - start:5.1f} s: enemies, corpses, tick = {line}", flush=True)
            if a.profile and not profiled and time.time() - start > 20.0:
                profiled = True  # the wave at the wall: each module's time per tick over 10 s
                print(rcon.run("/f3d-status", port=PORT, timeout=30.0))
        if a.profile:
            print(rcon.run("/f3d-status", port=PORT, timeout=30.0))
            print(rcon.run("/f3d-profile", port=PORT, timeout=30.0))


if __name__ == "__main__":
    main()
