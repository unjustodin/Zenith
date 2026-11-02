-- Fluids, heat and power near the client's camera, for drawing: what is in each pipe, tank and
-- machine fluid box (`fl`), how hot heat pipes and reactors are (`ht`), and which machines are
-- short of electricity or not connected to it (`pw`). Wires between poles ride in the entity
-- records (world.lua). All change slowly, so once a second is enough.
--
-- Read-only: nothing here touches `storage`, so it is safe in multiplayer.

local registry = require("scripts.registry")
local transport = require("scripts.transport")
local world = require("scripts.world")
local rate = require("scripts.rate")

local M = {}

local INTERVAL = 60
local BOXES_PER_MESSAGE = 200

local function area(f, r)
  return { { f.x - r, f.y - r }, { f.x + r, f.y + r } }
end

local function send_parts(t, flat, width)
  local per = BOXES_PER_MESSAGE * width
  local parts = math.max(1, math.ceil(#flat / per))
  for part = 1, parts do
    local slice = {}
    for i = (part - 1) * per + 1, math.min(part * per, #flat) do
      slice[#slice + 1] = flat[i]
    end
    transport.send_now({ t = t, part = part, parts = parts, l = slice })
  end
end

-- The entity's fluid storages, by index: fluid (nil when empty) and capacity. 2.1 has no
-- LuaEntity.fluidbox; storages are read one by one up to fluids_count.
function M.storages(e)
  local out = {}
  for i = 1, e.fluids_count do
    out[i] = { fluid = e.get_fluid(i), capacity = e.get_fluid_capacity(i) }
  end
  return out
end

-- [unit, box, fluid id, amount, capacity, temperature, ...] for every box with fluid in it.
local function collect_fluids(surface, f, r)
  local flat = {}
  local types = registry.fluid_types()
  if #types == 0 then
    return flat
  end
  for _, e in pairs(surface.find_entities_filtered({ area = area(f, r), type = types })) do
    local unit = e.unit_number
    if unit then
      for i, box in ipairs(M.storages(e)) do
        local fluid = box.fluid
        if fluid then
          flat[#flat + 1] = unit
          flat[#flat + 1] = i
          flat[#flat + 1] = registry.fluid_id(fluid.name)
          flat[#flat + 1] = math.floor(fluid.amount + 0.5)
          flat[#flat + 1] = math.floor(box.capacity + 0.5)
          flat[#flat + 1] = math.floor((fluid.temperature or 0) + 0.5)
        end
      end
    end
  end
  return flat
end

-- [unit, temperature (whole degrees), ...] for every entity with a heat buffer.
local function collect_heat(surface, f, r)
  local flat = {}
  local types = registry.heat_types()
  if #types == 0 then
    return flat
  end
  for _, e in pairs(surface.find_entities_filtered({ area = area(f, r), type = types })) do
    local ok, temperature = pcall(function() return e.temperature end)
    if e.unit_number and ok and temperature then
      flat[#flat + 1] = e.unit_number
      flat[#flat + 1] = math.floor(temperature + 0.5)
    end
  end
  return flat
end

-- entity_status -> what `pw` says: 0 no power, 1 low power, 2 not connected to any pole.
local POWER_STATES
local function power_states()
  if not POWER_STATES then
    local st = defines.entity_status
    POWER_STATES = { [st.no_power] = 0, [st.low_power] = 1 }
    local ok, unplugged = pcall(function() return st.not_plugged_in_electric_network end)
    if ok and unplugged then
      POWER_STATES[unplugged] = 2
    end
  end
  return POWER_STATES
end

-- [unit, 0 (no power), 1 (low power) or 2 (not connected), ...]; machines with enough power are
-- left out. 2.1 gives a consumer out of reach of every pole no_power too (not_plugged_in_electric_network
-- is only for generators), so no_power without an electric network id also counts as 2.
local function collect_power(surface, f, r)
  local flat = {}
  local types = registry.electric_types()
  if #types == 0 then
    return flat
  end
  local states = power_states()
  for _, e in pairs(surface.find_entities_filtered({ area = area(f, r), type = types })) do
    local state = states[e.status]
    if state == 0 and e.electric_network_id == nil then
      state = 2
    end
    if e.unit_number and state then
      flat[#flat + 1] = e.unit_number
      flat[#flat + 1] = state
    end
  end
  return flat
end

function M.tick()
  if not rate.due("fp", INTERVAL) then
    return
  end
  local s = storage.f3d
  local r = math.min(settings.global["f3d-detail-radius"].value, s.focus.r)
  local surface = world.surface()
  if r > 0 then
    send_parts("fl", collect_fluids(surface, s.focus, r), 6)
    send_parts("ht", collect_heat(surface, s.focus, r), 2)
  end
  send_parts("pw", collect_power(surface, s.focus, s.focus.r), 2)
end

return M
