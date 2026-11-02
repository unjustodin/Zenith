-- Turrets and vehicle guns near the client's camera: where each one's weapon points, what it is
-- aiming at and how many shots it fired, so the client can turn, raise and fire them as
-- Factorio draws them (`ts`). Also the firing cue `tf` from damage events (exact hit points).

local transport = require("scripts.transport")
local world = require("scripts.world")
local map = require("scripts.map")
local rate = require("scripts.rate")

local M = {}

local SWEEP = 6          -- ticks between reports (a gun turret fires every 6)
local REFRESH = 60       -- ticks between looking for the turrets in range
local FULL = 120         -- ticks between reports of every turret, idle ones too
local RECORDS_PER_MESSAGE = 200

-- Entity type -> how to read it: the inventory with its ammo, and where its weapon points.
local KINDS = {
  ["ammo-turret"] = { inv = "turret_ammo", aim = "orientation" },
  ["electric-turret"] = { aim = "orientation", hits = true },
  ["fluid-turret"] = { aim = "orientation", hits = true },
  ["artillery-turret"] = { inv = "artillery_turret_ammo", aim = "relative_turret_orientation" },
  ["artillery-wagon"] = { inv = "artillery_wagon_ammo", aim = "relative_turret_orientation", vehicle = true },
  ["car"] = { inv = "car_ammo", aim = "relative_turret_orientation", vehicle = true, gunner = true },
  ["spider-vehicle"] = { inv = "spider_ammo", aim = "torso_orientation", vehicle = true, gunner = true },
}
local TYPES = {}
for t in pairs(KINDS) do
  TYPES[#TYPES + 1] = t
end
table.sort(TYPES)

local function near_focus(entity)
  local s = storage.f3d
  if not s.client or entity.surface.index ~= s.surface_index then
    return false
  end
  local f, p = s.focus, entity.position
  return math.abs(p.x - f.x) <= f.r and math.abs(p.y - f.y) <= f.r
end

local function read(e, key)
  local ok, v = pcall(function() return e[key] end)
  if ok then
    return v
  end
  return nil
end

-- Rounds in an ammo inventory: whole magazines plus what is left in each one in use. Only its
-- going down matters (a shot), so an inserter's refill in the same sweep can hide one.
local function rounds(e, kind)
  if not kind.inv then
    return nil
  end
  local index = defines.inventory[kind.inv]
  local inv = index and e.get_inventory(index)
  if not inv then
    return nil
  end
  local n = 0
  for i = 1, #inv do
    local stack = inv[i]
    if stack.valid_for_read then
      local ok, left = pcall(function() return stack.ammo end)
      local ok2, size = pcall(function() return stack.prototype.magazine_size end)
      if ok and ok2 and left and size then
        n = n + (stack.count - 1) * size + left
      else
        n = n + stack.count
      end
    end
  end
  return n
end

-- Who fires a vehicle's guns: its driver, or the passenger when there is one and the driver
-- isn't the gunner.
-- Where they shoot, or nil.
local function gunner_aim(e)
  -- 2.1.23 says driver_is_gunner = false for a tank with only a driver, who still fires.
  local driver
  if read(e, "driver_is_gunner") == false then
    local ok, passenger = pcall(function() return e.get_passenger() end)
    driver = ok and passenger or nil
  end
  driver = driver or e.get_driver()
  if driver and driver.valid and read(driver, "object_name") == "LuaPlayer" then
    driver = driver.character
  end
  if not (driver and driver.valid) then
    return nil
  end
  -- A character's shooting_state lasts the tick it is set (combat.lua sets the bridge's own every
  -- tick while the client shoots), so for that one use where the client aims.
  local sh = storage.f3d.shooting
  if sh and driver == storage.f3d.puppet then
    return { x = sh.x, y = sh.y }
  end
  local state = read(driver, "shooting_state")
  if state and state.state ~= defines.shooting.not_shooting then
    return state.position
  end
  return nil
end

local function find(s)
  s.turrets = {}
  local surface = world.surface()
  if not (s.client and surface) then
    return
  end
  local f = s.focus
  local area = { { f.x - f.r, f.y - f.r }, { f.x + f.r, f.y + f.r } }
  for _, e in pairs(surface.find_entities_filtered({ area = area, type = TYPES })) do
    if e.unit_number then
      s.turrets[e.unit_number] = e
    end
  end
end

-- [unit, orientation (thousandths of a turn), shots since the last report, selected gun,
--  target x, target y (1/256 tiles; left out without a target)]
local function record(e, kind, last, hits, full)
  local unit = e.unit_number
  local o = read(e, kind.aim) or 0
  local o_fixed = math.floor(o * 1000 + 0.5) % 1000
  local target
  if kind.gunner then
    target = gunner_aim(e)
  else
    local t = read(e, "shooting_target")
    target = t and t.valid and t.position or nil
  end
  local shots = 0
  local now = rounds(e, kind)
  local prev = last[unit]
  if now then
    if prev and prev.rounds and now < prev.rounds then
      shots = prev.rounds - now
    end
  elseif kind.hits and hits[unit] then
    shots = 1
  end
  hits[unit] = nil
  last[unit] = { rounds = now, o = o_fixed }
  if not (full or target or shots > 0 or (prev and prev.o ~= o_fixed)) then
    return nil
  end
  local gun = kind.vehicle and (read(e, "selected_gun_index") or 1) or 0
  local rec = { unit, o_fixed, math.min(shots, 50), gun }
  if target then
    rec[5] = world.fixed(target.x)
    rec[6] = world.fixed(target.y)
  end
  return rec
end

function M.tick()
  local s = storage.f3d
  if not s.client then
    return
  end
  if not s.turrets or game.tick % REFRESH == 0 then
    find(s)
  end
  if not rate.due("ts", SWEEP) then
    return
  end
  s.turret_last = s.turret_last or {}
  s.turret_hits = s.turret_hits or {}
  local full = rate.crossed("ts", FULL)
  local list = {}
  -- The remote view leaves out what no radar sees (only what is sent; `record` keeps counting).
  local seen = map.view_filter()
  for unit, e in pairs(s.turrets) do
    if e.valid and near_focus(e) then
      local rec = record(e, KINDS[e.type], s.turret_last, s.turret_hits, full)
      if rec and seen and not seen(e.position.x, e.position.y) then
        rec = nil
      end
      if rec then
        list[#list + 1] = rec
      end
    else
      s.turrets[unit] = nil
      s.turret_last[unit] = nil
    end
  end
  table.sort(list, function(a, b) return a[1] < b[1] end)
  for first = 1, #list, RECORDS_PER_MESSAGE do
    local slice = {}
    for i = first, math.min(first + RECORDS_PER_MESSAGE - 1, #list) do
      slice[#slice + 1] = list[i]
    end
    transport.send_now({ t = "ts", l = slice })
  end
end

-- A turret's damage event (combat.lua's on_entity_damaged): a firing cue for the client, and a
-- shot for the next report of turrets that have no ammo to count (lasers, tesla, flamethrowers).
function M.on_hit(event)
  local cause = event.cause
  if not (cause and cause.valid and cause.unit_number and near_focus(cause)) then
    return
  end
  local kind
  if cause.type == "ammo-turret" then
    kind = "bullet"
  elseif cause.type == "electric-turret" then
    kind = "laser"
  elseif cause.type == "fluid-turret" and event.source and event.source.valid and event.source.type == "stream" then
    -- Ignore lingering ground fire: only the live stream is the turret firing now.
    kind = "flame"
  end
  if not kind then
    return
  end
  local s = storage.f3d
  local unit = cause.unit_number
  if kind ~= "bullet" then
    s.turret_hits = s.turret_hits or {}
    s.turret_hits[unit] = true
  end
  s.turret_fire_ticks = s.turret_fire_ticks or {}
  local interval = kind == "flame" and 6 or (kind == "laser" and 4 or 2)
  if game.tick - (s.turret_fire_ticks[unit] or -interval) >= interval then
    s.turret_fire_ticks[unit] = game.tick
    local target = cause.shooting_target
    if not (target and target.valid) then target = event.entity end
    local p = target.position
    local seen = map.view_filter()
    if seen and not seen(cause.position.x, cause.position.y) then
      return
    end
    transport.send_now({
      t = "tf",
      u = unit,
      w = kind,
      sx = world.fixed(cause.position.x),
      sy = world.fixed(cause.position.y),
      x = world.fixed(p.x),
      y = world.fixed(p.y),
    })
  end
end

function M.on_removed(unit)
  local s = storage.f3d
  if s.turret_fire_ticks then
    s.turret_fire_ticks[unit] = nil
  end
  if s.turret_last then
    s.turret_last[unit] = nil
  end
  if s.turret_hits then
    s.turret_hits[unit] = nil
  end
end

-- After a handshake, a surface change or when the client leaves.
function M.reset()
  local s = storage.f3d
  s.turrets = nil
  s.turret_last = {}
  s.turret_hits = {}
end

return M
