-- Factorio's spidertron remote: the client keeps which spidertrons are selected (a player-less
-- character has no remote selection of its own) and sends them somewhere, or queues another
-- waypoint (Shift). Commands only, and the destinations they ask about (`spd`).

local transport = require("scripts.transport")
local world = require("scripts.world")
local puppet = require("scripts.puppet")

local M = {}

local MAX = 100 -- spidertrons per command

-- The character's force's spidertrons among the unit numbers in `list`.
local function spiders_of(list)
  local c = puppet.get()
  local out = {}
  if not (c and type(list) == "table") then
    return out
  end
  for i, u in ipairs(list) do
    if i > MAX then
      break
    end
    local e = tonumber(u) and game.get_entity_by_unit_number(math.floor(tonumber(u)))
    if e and e.valid and e.type == "spider-vehicle" and e.force == c.force then
      out[#out + 1] = e
    end
  end
  return out
end

-- {l = [unit, ...]}: sends `spd`, each spidertron's queued destinations:
-- {l = [[unit, [[x, y], ...]], ...]} (fixed point).
function M.query(cmd)
  local l = {}
  for _, e in ipairs(spiders_of(cmd.l)) do
    local points = {}
    for i, p in ipairs(e.autopilot_destinations or {}) do
      points[i] = { world.fixed(p.x), world.fixed(p.y) }
    end
    l[#l + 1] = { e.unit_number, points }
  end
  transport.send_now({ t = "spd", l = l })
end

-- {l = [unit, ...], x, y (fixed), q? (0/1)}: Factorio's click with the remote: the selected
-- spidertrons walk there (their old waypoints dropped), or with q (Shift) it is added to each
-- one's queue. Several spidertrons keep their formation round the point, as the game's remote does.
function M.go(cmd)
  local list = spiders_of(cmd.l)
  if #list == 0 then
    return puppet.message("No spidertron selected")
  end
  local x, y = (tonumber(cmd.x) or 0) / 256, (tonumber(cmd.y) or 0) / 256
  local cx, cy = 0, 0
  for _, e in ipairs(list) do
    cx, cy = cx + e.position.x / #list, cy + e.position.y / #list
  end
  for _, e in ipairs(list) do
    local at = { x = x, y = y }
    if #list > 1 then
      at = { x = x + e.position.x - cx, y = y + e.position.y - cy }
    end
    if cmd.q == 1 then
      e.add_autopilot_destination(at)
    else
      e.autopilot_destination = nil
      e.add_autopilot_destination(at)
    end
  end
  M.query(cmd)
end

return M
