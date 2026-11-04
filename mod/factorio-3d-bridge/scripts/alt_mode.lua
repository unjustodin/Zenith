-- Alt-mode's icons (issue #9): what each machine is set to make or let through, an assembler's or
-- furnace's recipe, an inserter's, loader's, splitter's, storage chest's or drill's filters, a
-- requester or buffer chest's first four requests.
--
-- They ride on the entity records (`extra.ai`, world.lua), so every building the client has loaded
-- has its icon from the moment it arrives, with no scanning and no limit. What changes them:
--   * with an event: building (a new record), Shift+paste and the bridge's own settings (tracker
--     sends `upd`), a player closing the entity's window in the real game (on_gui_closed), the
--     screen the client has open (screens.lua checks its entity twice a second);
--   * without one: a furnace picks its recipe from what is put in, and a circuit network can set
--     an assembler's recipe or an inserter's, loader's or splitter's filters. Those entities (a
--     furnace, or one with a red or green wire) are watched: each record of one puts it in
--     storage.f3d.altw, and a few of them a tick are read again under the work budget, `aiu`
--     carrying what changed. Scripts changing the rest are seen when the chunk is next sent.
--
-- Everything here runs from events and on_tick, and what it keeps (storage.f3d.altw) only from
-- the records the client is sent, so it stays the same on every peer.

local transport = require("scripts.transport")
local budget = require("scripts.budget")

local M = {}

local CHUNK = 32
-- Read again per tick at most (the work budget may allow fewer): with a few thousand watched
-- machines each is looked at every few seconds.
local WATCH_PER_TICK = 24
-- A watched machine's look costs about as much as a record (budget.lua's units).
local WATCH_PRICE = 2
-- A round over the watched machines starts at most this often.
local ROUND_TICKS = 120

local TYPES = {
  ["assembling-machine"] = true, furnace = true, ["rocket-silo"] = true, inserter = true, loader = true,
  ["loader-1x1"] = true, splitter = true, ["lane-splitter"] = true, ["logistic-container"] = true,
  ["mining-drill"] = true,
}
M.TYPES = TYPES
-- Their recipe or filters can change with no event if the circuit network sets them.
local CIRCUIT_SET = {
  ["assembling-machine"] = true, inserter = true, loader = true, ["loader-1x1"] = true, splitter = true,
  ["lane-splitter"] = true, ["mining-drill"] = true, ["logistic-container"] = true,
}

local function signal_name(f)
  if type(f) ~= "table" then
    return nil
  end
  local name = f.name
  if type(name) ~= "string" and name ~= nil then -- a prototype (LuaObjects aren't tables)
    local ok, n = pcall(function() return name.name end)
    name = ok and n or nil
  end
  return type(name) == "string" and name or nil
end

-- Every filter set on the entity, in slot order: Alt-mode shows them all, shrunk to fit.
local function filter_names(e)
  local names = {}
  local ok, n = pcall(function() return e.filter_slot_count end)
  for i = 1, ok and n or 0 do
    local ok_f, f = pcall(function() return e.get_filter(i) end)
    local name = ok_f and signal_name(f)
    if name then
      names[#names + 1] = name
    end
  end
  return names
end

-- A requester or buffer chest's requested items, the first `n` different ones in the order of its
-- active sections (owner: a mixed chest shows its first four, each a quarter of the icon). (Read
-- here, not through logistics.lua: world.lua requires this file, and logistics.lua world.lua.)
local function requested_names(e, n)
  local names, seen = {}, {}
  -- A chest's LuaLogisticSections (logistics.lua reads chests the same way).
  local ok, point = pcall(function() return e.get_logistic_sections() end)
  if not (ok and point) then
    return names
  end
  local ok2, sections = pcall(function() return point.sections end)
  for _, section in pairs(ok2 and sections or {}) do
    local ok3, active = pcall(function() return section.active end)
    if not ok3 or active ~= false then
      for _, f in pairs(section.filters or {}) do
        local v = f.value
        local name = v and (v.type == nil or v.type == "item") and v.name
        if name and not seen[name] then
          seen[name] = true
          names[#names + 1] = name
          if #names >= n then
            return names
          end
        end
      end
    end
  end
  return names
end

-- [icon type, name, more?] for an entity's Alt-mode icon (more: the other filters' item names),
-- or nil.
function M.icon(e)
  local t = e.type
  if t == "assembling-machine" or t == "furnace" or t == "rocket-silo" then
    local ok, recipe = pcall(function() return e.get_recipe() end)
    -- An idle furnace's previous_recipe isn't shown: with no recipe Factorio shows nothing.
    if ok and recipe then
      return { "recipe", recipe.name }
    end
  elseif t == "inserter" or t == "loader" or t == "loader-1x1" then
    local names = filter_names(e)
    if #names > 0 then
      local first = table.remove(names, 1)
      return { "item", first, #names > 0 and names or nil }
    end
  elseif t == "splitter" or t == "lane-splitter" then
    local ok, f = pcall(function() return e.splitter_filter end)
    local name = ok and signal_name(f)
    if name then
      return { "item", name }
    end
  elseif t == "logistic-container" or t == "mining-drill" then
    local ok, f = pcall(function() return e.filter_slot_count > 0 and e.get_filter(1) end)
    local name = ok and signal_name(f)
    if name then
      return { "item", name }
    end
    if t == "logistic-container" then
      local names = requested_names(e, 4)
      if #names > 0 then
        local first = table.remove(names, 1)
        return { "item", first, #names > 0 and names or nil }
      end
    end
  end
  return nil
end

-- Alt-mode's machine arrows (issue #9 part 2, Factorio's "Show machine arrows in Alt-mode"): the
-- client draws them at the prototype's fluid connections (`eprops` fb). A crafting machine shows
-- only those its recipe uses, as Factorio does (checked in 2.1.23: with any fluid ingredient every
-- input connection, with any fluid product every output one), so its record carries `fa`, a mask:
-- 1 the recipe takes fluid, 2 it makes fluid. 2.1 has no LuaEntity.fluidbox, so it comes from the
-- recipe. Other machines (boilers, pumps) show all their connections and need nothing here.
local CRAFTERS = { ["assembling-machine"] = true, furnace = true }
M.CRAFTERS = CRAFTERS

function M.arrows(e)
  if not CRAFTERS[e.type] then
    return nil
  end
  local ok, recipe = pcall(function() return e.get_recipe() end)
  if not (ok and recipe) then
    return nil
  end
  local mask = 0
  for _, i in pairs(recipe.ingredients) do
    if i.type == "fluid" then
      mask = 1
      break
    end
  end
  for _, p in pairs(recipe.products) do
    if p.type == "fluid" then
      mask = mask + 2
      break
    end
  end
  return mask > 0 and mask or nil
end

-- The icon as one string, to see whether it changed ("" for none).
function M.signature(icon, arrows)
  local s = ""
  if icon then
    s = icon[1] .. ":" .. icon[2]
    if icon[3] then
      s = s .. ":" .. table.concat(icon[3], ",")
    end
  end
  if arrows then
    s = s .. "|" .. arrows
  end
  return s
end

-- What Alt-mode shows over the entity: its icon and its arrows (either may be nil), and their signature.
function M.state(e)
  local icon = TYPES[e.type] and M.icon(e) or nil
  local arrows = CRAFTERS[e.type] and M.arrows(e) or nil
  return icon, arrows, M.signature(icon, arrows)
end

local function chunk_key(p)
  return math.floor(p.x / CHUNK) .. "," .. math.floor(p.y / CHUNK)
end

-- world.record calls this for each record it makes of an Alt-mode type, with its icon and extra
-- (wires in r / g): a furnace, or one a circuit network may set, is watched from then on. Only
-- for a client's own records (storage.f3d has its subscriptions).
function M.recorded(e, icon, extra, arrows)
  local s = storage.f3d
  local unit = e.unit_number
  if not (s and s.subs and unit) then
    return
  end
  if e.type == "furnace" or (CIRCUIT_SET[e.type] and extra and (extra.r or extra.g)) then
    s.altw = s.altw or {}
    s.altw[unit] = { e = e, v = M.signature(icon, arrows), k = chunk_key(e.position) }
  elseif s.altw and s.altw[unit] then
    s.altw[unit] = nil -- its wires went: an event or the chunk's next sending tells the rest
  end
end

local function row(unit, icon)
  if not icon then
    return { unit, "" }
  end
  return { unit, icon[1], icon[2], icon[3] }
end

-- The entity's icon now, sent if it differs from what the client was last told (an event that may
-- have changed it: a window closed in the real game, the open screen's commands). `known` is the
-- signature the caller kept, or nil to send it whatever it was.
function M.check(e, known)
  local s = storage.f3d
  if not (s and s.client and e and e.valid and e.unit_number and TYPES[e.type]) then
    return known
  end
  -- world.is_subscribed, here: world requires this module, and `require` at run time stops the game.
  if e.surface.index ~= s.surface_index or not s.subs[chunk_key(e.position)] then
    return known
  end
  local icon, arrows, v = M.state(e)
  local w = s.altw and s.altw[e.unit_number]
  if w then
    w.v = v
  end
  if v ~= known then
    transport.send_reliable({ t = "aiu", l = { row(e.unit_number, icon) }, fa = { { e.unit_number, arrows or 0 } } })
  end
  return v
end

-- A few watched machines a tick, a round at most every ROUND_TICKS: those whose icon changed are
-- sent in one `aiu`. Entries gone or no longer streamed are dropped when the round ends (clearing
-- keys behind the cursor while it walks would break `next`).
function M.tick()
  local s = storage.f3d
  local w = s.altw
  if not w or game.tick < (s.altw_due or 0) then
    return
  end
  if s.altw_cursor ~= nil and not w[s.altw_cursor] then
    s.altw_cursor = nil -- its entry went (M.recorded): start the round again
  end
  local out, fa
  for _ = 1, WATCH_PER_TICK do
    if not budget.can(WATCH_PRICE, "alt", 0.1) then
      break
    end
    local unit, entry = next(w, s.altw_cursor)
    if unit == nil then
      s.altw_cursor = nil
      for _, u in ipairs(s.altw_dead or {}) do
        w[u] = nil
      end
      s.altw_dead = nil
      s.altw_due = game.tick + ROUND_TICKS
      break
    end
    s.altw_cursor = unit
    budget.spend(WATCH_PRICE, "alt")
    local e = entry.e
    if not (e.valid and s.subs[entry.k]) then
      s.altw_dead = s.altw_dead or {}
      s.altw_dead[#s.altw_dead + 1] = unit
    else
      local icon, arrows, v = M.state(e)
      if v ~= entry.v then
        entry.v = v
        out = out or {}
        out[#out + 1] = row(unit, icon)
        fa = fa or {}
        fa[#fa + 1] = { unit, arrows or 0 }
      end
    end
  end
  if out then
    transport.send_reliable({ t = "aiu", l = out, fa = fa })
  end
end

-- How many machines are watched, for /f3d-status.
function M.watched()
  local n = 0
  for _ in pairs(storage.f3d.altw or {}) do
    n = n + 1
  end
  return n
end

return M
