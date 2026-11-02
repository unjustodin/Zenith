-- Inserter hands near the client's camera: where each hand is and what it holds, sent with
-- belt items. The client turns each arm towards its hand and glides it between updates.
--
-- Read-only: nothing here touches `storage`, so it is safe in multiplayer.

local registry = require("scripts.registry")
local transport = require("scripts.transport")
local world = require("scripts.world")
local map = require("scripts.map")
local rate = require("scripts.rate")

local M = {}

local HANDS_PER_MESSAGE = 300

local function collect(surface, f, r)
  local flat = {}
  local found = map.view_only(surface.find_entities_filtered({
    area = { { f.x - r, f.y - r }, { f.x + r, f.y + r } },
    type = "inserter",
  }))
  for _, e in pairs(found) do
    local unit = e.unit_number
    if unit then
      local p = e.held_stack_position
      local stack = e.held_stack
      flat[#flat + 1] = unit
      flat[#flat + 1] = world.fixed(p.x)
      flat[#flat + 1] = world.fixed(p.y)
      flat[#flat + 1] = stack.valid_for_read and registry.item_id(stack.name) or 0
    end
  end
  return flat
end

function M.tick()
  local r = math.min(settings.global["f3d-detail-radius"].value, storage.f3d.focus.r)
  local interval = settings.global["f3d-detail-interval"].value
  if r <= 0 or not rate.due("ih", interval) then
    return
  end
  -- Like `mv`, every update is the full list, split into parts that share the tick `k`; `p`, the
  -- ticks between updates.
  transport.send_groups("ih", collect(world.surface(), storage.f3d.focus, r), 4, HANDS_PER_MESSAGE,
    ',"p":' .. rate.period("ih", interval))
end

return M
