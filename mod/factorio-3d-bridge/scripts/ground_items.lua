-- Items lying on the ground (item-entity) near the client's camera. They don't move, so the
-- list goes out twice a second, or every detail interval while the character is picking up so
-- picked-up items vanish promptly. Item-entities have no unit number; the client just redraws
-- the whole list.
--
-- Read-only: nothing here touches `storage`, so it is safe in multiplayer.

local registry = require("scripts.registry")
local transport = require("scripts.transport")
local world = require("scripts.world")
local rate = require("scripts.rate")

local M = {}

local INTERVAL = 30
local ITEMS_PER_MESSAGE = 300
-- A spilled chest can leave thousands of items; past this the list is cut short.
local MAX_ITEMS = 3000

local function collect(surface, f, r)
  local flat, n = {}, 0
  local found = surface.find_entities_filtered({
    area = { { f.x - r, f.y - r }, { f.x + r, f.y + r } },
    type = "item-entity",
  })
  for _, e in pairs(found) do
    local stack = e.stack
    if stack.valid_for_read then
      local p = e.position
      flat[#flat + 1] = registry.item_id(stack.name)
      flat[#flat + 1] = world.fixed(p.x)
      flat[#flat + 1] = world.fixed(p.y)
      n = n + 1
      if n >= MAX_ITEMS then
        return flat
      end
    end
  end
  return flat
end

-- Like `bi`, every update is the full list, split into parts that share the tick `k`.
local function send(flat)
  local per = ITEMS_PER_MESSAGE * 3
  local parts = math.max(1, math.ceil(#flat / per))
  for part = 1, parts do
    local slice = {}
    for i = (part - 1) * per + 1, math.min(part * per, #flat) do
      slice[#slice + 1] = flat[i]
    end
    transport.send_now({ t = "gi", part = part, parts = parts, l = slice })
  end
end

function M.tick()
  local r = math.min(settings.global["f3d-detail-radius"].value, storage.f3d.focus.r)
  local interval = storage.f3d.pickup and settings.global["f3d-detail-interval"].value or INTERVAL
  if r <= 0 or not rate.due("gi", interval) then
    return
  end
  send(collect(world.surface(), storage.f3d.focus, r))
end

return M
