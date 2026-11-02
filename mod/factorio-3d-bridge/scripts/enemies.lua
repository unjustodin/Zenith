-- What enemies near the client's camera are attacking, so the client doesn't have to guess:
-- biters and spitters that are in range of the target of their attack command (a unit's
-- `distraction_command`, or its own command), and worms with a `shooting_target`. The list goes
-- out a few times a second; the client lets an attack lapse when it stops being listed.
--
-- Read-only: nothing here touches `storage`, so it is safe in multiplayer.

local transport = require("scripts.transport")
local world = require("scripts.world")
local map = require("scripts.map")
local rate = require("scripts.rate")

local M = {}

local INTERVAL = 10
local MAX_ATTACKERS = 1000
-- Slack on the attack range, in tiles: units start their attack from just outside it.
local SLACK = 0.75

-- Attack ranges by unit prototype, derived from prototypes only (the same on every peer).
local ranges = {}

local function range_of(e)
  local r = ranges[e.name]
  if r == nil then
    r = 1
    local ok, params = pcall(function() return e.prototype.attack_parameters end)
    if ok and params and params.range then
      r = params.range
    end
    ranges[e.name] = r
  end
  return r
end

local function attack_target(e)
  local c = e.commandable
  if not c then
    return nil
  end
  local attack = defines.command.attack
  local cmd = c.distraction_command
  if not (cmd and cmd.type == attack) then
    cmd = c.command
    if not (cmd and cmd.type == attack) then
      return nil
    end
  end
  local t = cmd.target
  if t and t.valid then
    return t
  end
  return nil
end

-- Distance from a unit to the nearest edge of the target's box (its centre for small things).
local function gap(e, t)
  local p, q = e.position, t.position
  local box = t.bounding_box
  local dx = math.max(box.left_top.x - p.x, 0, p.x - box.right_bottom.x)
  local dy = math.max(box.left_top.y - p.y, 0, p.y - box.right_bottom.y)
  if box.left_top.x == box.right_bottom.x then
    dx, dy = p.x - q.x, p.y - q.y
  end
  return math.sqrt(dx * dx + dy * dy)
end

local function collect(surface, f, r)
  local flat, n = {}, 0
  local found = map.view_only(surface.find_entities_filtered({
    area = { { f.x - r, f.y - r }, { f.x + r, f.y + r } },
    type = { "unit", "turret" },
  }))
  for _, e in pairs(found) do
    local unit = e.unit_number
    local t
    if e.type == "turret" then
      t = e.shooting_target
    else
      t = attack_target(e)
      if t and gap(e, t) > range_of(e) + SLACK then
        t = nil
      end
    end
    if unit and t and t.valid then
      local p = t.position
      flat[#flat + 1] = unit
      flat[#flat + 1] = world.fixed(p.x)
      flat[#flat + 1] = world.fixed(p.y)
      n = n + 1
      if n >= MAX_ATTACKERS then
        break
      end
    end
  end
  return flat
end

function M.tick()
  if not rate.due("en", INTERVAL) then
    return
  end
  local f = storage.f3d.focus
  if f.r <= 0 then
    return
  end
  local flat = collect(world.surface(), f, f.r)
  if #flat > 0 then
    transport.send_now({ t = "en", l = flat })
  end
end

return M
