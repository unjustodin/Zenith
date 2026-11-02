-- Fast-changing state near the client's camera: positions of moving things every few ticks,
-- and which machines are working (for animation) twice a second.

local registry = require("scripts.registry")
local transport = require("scripts.transport")
local world = require("scripts.world")
local map = require("scripts.map")
local rate = require("scripts.rate")

local M = {}

local MOVERS_PER_MESSAGE = 200
local STATE_INTERVAL = 30

local function focus_area(s)
  local f = s.focus
  return { { f.x - f.r, f.y - f.r }, { f.x + f.r, f.y + f.r } }
end

-- Sends the full list of movers in range, split into parts that share the same tick `k`.
-- The client drops a mover after it has been missing from a few frames in a row.
-- Ids for movers Factorio gives no unit number (a rocket waiting in its silo, 2.1.23): the object's
-- registration number, the same every time it is asked for, above any unit number.
local NO_UNIT_BASE = 2 ^ 40

function M.mover_id(e)
  local unit = e.unit_number
  if unit then
    return unit
  end
  local ok, reg = pcall(script.register_on_object_destroyed, e)
  return ok and reg and NO_UNIT_BASE + reg or nil
end

-- Searching the focus area (384 tiles across by default) is most of what movers cost on a big
-- base: 4.6 ms for 20 movers among 25,000 entities in 2.1.23, every other tick. So the movers found
-- are kept and only their positions read in between; the area is searched again every SCAN_TICKS,
-- or at once when the focus, its radius or the surface changes. A mover that appears meanwhile (a
-- robot leaving its roboport) shows up to SCAN_TICKS late (times the `rate` factor while slowed
-- down). Only what is sent depends on this.
local SCAN_TICKS = 8
local scan = { tick = -SCAN_TICKS }

local function movers_in_focus(surface, s)
  local f = s.focus
  if game.tick - scan.tick >= SCAN_TICKS * rate.factor("mv") or scan.surface ~= surface.index or scan.x ~= f.x or scan.y ~= f.y or scan.r ~= f.r then
    scan = {
      tick = game.tick, surface = surface.index, x = f.x, y = f.y, r = f.r,
      list = surface.find_entities_filtered({ area = focus_area(s), type = registry.mover_types() }),
    }
    return scan.list
  end
  local list = {}
  for _, e in pairs(scan.list) do
    if e.valid then
      list[#list + 1] = e
    end
  end
  return list
end

-- A new client or world: search again before the next send.
function M.reset()
  scan = { tick = -SCAN_TICKS }
end

local function send_movers(surface, s, every)
  local found = map.view_only(movers_in_focus(surface, s))
  local list = {}
  for _, e in pairs(found) do
    local unit = M.mover_id(e)
    if unit then
      local p = e.position
      local rec = { unit, registry.entity_id(e.name), world.fixed(p.x), world.fixed(p.y) }
      if registry.ORIENTED[e.type] then
        rec[5] = math.floor(e.orientation * 1000 + 0.5)
      end
      list[#list + 1] = rec
    end
  end
  -- p: the ticks between updates at the client's `rate` level, so it draws movers that far behind
  -- (just after a slow-down they still come at the old rate for a moment while it eases in).
  transport.send_records("mv", list, MOVERS_PER_MESSAGE, every)
end

-- A defines table's value -> its name, so states are compared by name (2.0 and 2.1 may number
-- them differently).
local function names(t)
  local out = {}
  for k, v in pairs(t or {}) do
    out[v] = k
  end
  return out
end

-- Entities that report more than working or not (PROTOCOL.md, `st`). Signals: 1 green, 2 yellow,
-- 3 red, 4 blue (a chain signal with some exits open). Accumulators: 1 charging, 2 discharging.
-- Power switches: 1 on.
local signal_states, chain_states  -- from defines, on first use

local function signal_colour(e)
  signal_states = signal_states or names(defines.signal_state)
  local states = signal_states
  local ok, state = pcall(function() return states[e.signal_state] end)
  if ok and state == "reserved" then
    return 2
  end
  if e.type == "rail-chain-signal" then
    chain_states = chain_states or names(defines.chain_signal_state)
    local chains = chain_states
    local ok2, chain = pcall(function() return chains[e.chain_signal_state] end)
    if ok2 and chain == "partially_open" then
      return 4
    elseif ok2 and chain == "none_open" then
      return 3
    end
  end
  if ok and (state == "closed" or state == "reserved_by_circuit_network") then
    return 3
  end
  return 1
end

local STATE_OF = {
  ["rail-signal"] = signal_colour,
  ["rail-chain-signal"] = signal_colour,
  accumulator = function(e)
    local status = e.status
    if status == defines.entity_status.charging then
      return 1
    elseif status == defines.entity_status.discharging then
      return 2
    end
    return 0
  end,
  ["power-switch"] = function(e)
    return e.power_switch_state and 1 or 0
  end,
}

-- Sends only machines whose working state changed since the last report.
local function send_states(surface, s)
  -- Every few seconds report everything, so machines in freshly loaded chunks catch up.
  if rate.crossed("st", STATE_INTERVAL * 10) then
    s.working = {}
  end
  local found = surface.find_entities_filtered({ area = focus_area(s), type = registry.animated_types() })
  local working = defines.entity_status.working
  local changes = {}
  local seen = {}
  for _, e in pairs(found) do
    local unit = e.unit_number
    if unit then
      local state_of = STATE_OF[e.type]
      local on
      if state_of then
        local ok, v = pcall(state_of, e)
        on = ok and v or 0
      else
        on = (e.status == working) and 1 or 0
      end
      seen[unit] = on
      if s.working[unit] ~= on then
        changes[#changes + 1] = unit
        changes[#changes + 1] = on
      end
    end
  end
  s.working = seen
  if #changes > 0 then
    transport.send_reliable({ t = "st", l = changes })
  end
end

function M.tick()
  local s = storage.f3d
  local surface = world.surface()
  local interval = settings.global["f3d-mover-interval"].value
  if rate.due("mv", interval) then
    send_movers(surface, s, rate.period("mv", interval))
  end
  if rate.due("st", STATE_INTERVAL) then
    send_states(surface, s)
  end
end

return M
