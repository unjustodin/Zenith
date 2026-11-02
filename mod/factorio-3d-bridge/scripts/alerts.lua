-- Factorio's alerts for the bridge's force. LuaPlayer.get_alerts needs a player, which the
-- bridge's character hasn't, so the same alerts are worked out here: from events (entity
-- destroyed, under attack, turret firing) and from scans of the force's entities on every
-- surface (turret out of ammo, machines without power or fuel or with their output full, ghosts
-- missing material or robots, damaged buildings without repair packs, trains out of fuel or
-- without a path, platform, asteroid collector and rocket silo problems).
--
-- Event alerts live in `storage` (written only from events and on_tick). Scan results only feed
-- the `al` message, so they stay module-local. One kind of scan runs per SCAN_STEP ticks, so a
-- busy base's cost is spread out.

local transport = require("scripts.transport")
local world = require("scripts.world")
local puppet = require("scripts.puppet")

local M = {}

local SEND_INTERVAL = 60
local SCAN_STEP = 40         -- the small scans (repair packs, trains, platforms), one each this often
local PER_KIND = 40          -- entities listed per kind (the count is the full number)
local GHOSTS_MAX = 3000      -- ghosts looked at per pass
local CHUNKS_PER_TICK = 32   -- the entity pass's budget per tick: chunks looked in,
local ENTITIES_PER_TICK = 40 -- and entities checked (a ghost counts 4)
local PASS_INTERVAL = 600    -- a pass starts at most this often (a large real save: ~0.35 ms a tick for ~7 s)
-- How long an event alert stays after its last event (ticks); Factorio's own timings aren't in
-- the API, these are close to what the game shows.
local LIFETIME = { destroyed = 30 * 60, attack = 5 * 60, fire = 5 * 60 }

-- Machines whose status says no power, no fuel or output full.
local PASS_TYPES = { "ammo-turret", "entity-ghost", "assembling-machine", "furnace", "mining-drill", "lab", "inserter",
  "boiler", "beacon", "radar", "rocket-silo", "asteroid-collector", "agricultural-tower", "burner-generator", "reactor",
  "pump", "roboport" }
local NOT_DESTROYED_ALERT = { ["entity-ghost"] = true, ["tile-ghost"] = true, ["character-corpse"] = true, corpse = true,
  ["item-entity"] = true, projectile = true, ["combat-robot"] = true }

local scans = {}       -- kind -> {entries}, refreshed by the scans
-- entry -> the entity it is about, for the scans' entries: a pass is seconds old by the time it is
-- sent, and an entity mined or destroyed since is left out (icons over empty ground).
-- Weak keys: entries go with the scan results that hold them.
local subjects = setmetatable({}, { __mode = "k" })
local status_names
local present_types    -- filters out types this game hasn't got (find_entities_filtered rejects unknown types)
local repair_items

local function force()
  local c = puppet.get()
  return c and c.force or game.forces.player
end

local function state()
  local s = storage.f3d
  s.al = s.al or { destroyed = {}, attack = {}, fire = {}, hurt = {} }
  s.al.hurt = s.al.hurt or {}
  return s.al
end

-- [x, y, surface index, name (a ghost's: what it will build), unit, subject?]
local function entry(e, extra)
  local p = e.position
  local name = e.type == "entity-ghost" and e.ghost_name or e.name
  local rec = { world.fixed(p.x), world.fixed(p.y), e.surface.index, name, e.unit_number or 0 }
  if extra then
    rec[6] = extra
  end
  subjects[rec] = e
  return rec
end

-- A scan's entries whose entity is still there.
local function still_there(list)
  local out = {}
  for _, rec in ipairs(list) do
    local e = subjects[rec]
    if e == nil or e.valid then
      out[#out + 1] = rec
    end
  end
  return out
end

local function key_of(e)
  if e.unit_number then
    return e.unit_number
  end
  local p = e.position
  return e.surface.index .. ":" .. e.name .. ":" .. p.x .. "," .. p.y
end

local function types(list)
  if not present_types then
    present_types = {}
    for _, proto in pairs(prototypes.entity) do
      present_types[proto.type] = true
    end
  end
  local out = {}
  for _, t in ipairs(list) do
    if present_types[t] then
      out[#out + 1] = t
    end
  end
  return out
end

local function status_name(status)
  if not status_names then
    status_names = {}
    for name, value in pairs(defines.entity_status) do
      status_names[value] = name
    end
  end
  return status and status_names[status] or nil
end

---------------------------------------------------------------------------------------------
-- Events (called from combat.lua, which owns on_entity_damaged and on_entity_died)

-- A big attack on a big base remembers at most this many of each (a fixed cap, so
-- storage can't grow without bound between expiries).
local MAX_REMEMBERED = 500

local function remember(list, key, value)
  if list[key] ~= nil or table_size(list) < MAX_REMEMBERED then
    list[key] = value
  end
end

local function ours(e)
  return e.valid and e.force and e.force.name == force().name
end

function M.on_damaged(event)
  local e = event.entity
  if not (storage.f3d.client and e and e.valid) then
    return
  end
  local al = state()
  local by = event.force
  if ours(e) and by and by.name ~= e.force.name then
    local rec = al.attack[key_of(e)] or {}
    rec.t = game.tick
    rec.e = entry(e)
    remember(al.attack, key_of(e), rec)
    if e.unit_number then
      remember(al.hurt, e.unit_number, e)
    end
  end
  local cause = event.cause
  if cause and cause.valid and cause.type:find("turret") and ours(cause) then
    remember(al.fire, key_of(cause), { t = game.tick, e = entry(cause) })
  end
end

function M.on_died(event)
  local e = event.entity
  if not (storage.f3d.client and e and e.valid and ours(e)) or NOT_DESTROYED_ALERT[e.type] then
    return
  end
  local al = state()
  local key = key_of(e)
  remember(al.destroyed, key, { t = game.tick, e = entry(e) })
  al.attack[key] = nil
  if e.unit_number then
    al.hurt[e.unit_number] = nil
  end
end

---------------------------------------------------------------------------------------------
-- Scans

-- Factorio's warnings over machines: no power (unplugged when no pole reaches it), no fuel,
-- output full.
local STATUS_KINDS = { no_power = "no_power", not_plugged_in_electric_network = "unplugged", no_fuel = "no_fuel",
  full_output = "output_full", full_burnt_result_output = "output_full", low_power = "low_power" }
local PASS_KINDS = { "no_ammo", "no_power", "unplugged", "no_fuel", "output_full", "low_power", "launch", "collector",
  "no_material", "no_robots" }

local function networks_at(e)
  local ok, nets = pcall(function() return e.surface.find_logistic_networks_by_construction_area(e.position, e.force) end)
  return ok and nets or {}
end

-- A ghost inside a construction area: missing the item to build it, or no robot free to.
local function check_ghost(g, found)
  local nets = networks_at(g)
  if #nets == 0 then
    return
  end
  local items = g.ghost_prototype.items_to_place_this or {}
  local item = items[1] and (items[1].name or items[1])
  local have, free = false, false
  for _, net in pairs(nets) do
    if item and net.get_item_count(item) > 0 then
      have = true
    end
    if net.available_construction_robots > 0 then
      free = true
    end
  end
  if item and not have then
    table.insert(found.no_material, entry(g, item))
  elseif not free then
    table.insert(found.no_robots, entry(g, item))
  end
end

-- What one entity of the pass adds; returns its cost in the per-tick budget.
local function check_entity(e, found)
  if e.type == "ammo-turret" then
    local inv = e.get_inventory(defines.inventory.turret_ammo)
    if inv and inv.is_empty() then
      table.insert(found.no_ammo, entry(e))
    end
    return 1
  elseif e.type == "entity-ghost" then
    check_ghost(e, found)
    return 4
  end
  local name = status_name(e.status)
  local kind = name and STATUS_KINDS[name]
  if kind == "no_power" and not e.electric_network_id then
    kind = "unplugged"
  end
  if e.type == "rocket-silo" and (name == "waiting_for_space_in_destination" or name == "not_connected_to_hub_or_pad") then
    kind = "launch"
  elseif e.type == "asteroid-collector" and (name == "full_output" or name == "waiting_for_space_in_destination") then
    kind = "collector"
  end
  if kind then
    table.insert(found[kind], entry(e, name))
  end
  return 1
end

-- The entity scans go through every surface chunk by chunk, a few each tick (a busy base has
-- tens of thousands of entities: one scan of them all took 145 ms in a large real save, 10456
-- chunks), and replace the last results when a pass is complete.
local pass

local next_pass = 0

local function start_pass()
  next_pass = game.tick + PASS_INTERVAL
  local list = {}
  for _, surface in pairs(game.surfaces) do
    list[#list + 1] = surface.index
  end
  local found = {}
  for _, k in ipairs(PASS_KINDS) do
    found[k] = {}
  end
  pass = { surfaces = list, i = 1, iter = nil, found = found, seen = {}, types = types(PASS_TYPES), ghosts = 0 }
end

local function step_pass(now)
  if not pass then
    if not now and game.tick < next_pass then
      return
    end
    start_pass()
  end
  local f = force()
  local chunks, cost = 0, 0
  while chunks < CHUNKS_PER_TICK and cost < ENTITIES_PER_TICK do
    local si = pass.surfaces[pass.i]
    if not si then
      for k, v in pairs(pass.found) do
        scans[k] = v
      end
      pass = nil
      return
    end
    local surface = game.get_surface(si)
    local chunk = nil
    if surface and surface.valid then
      pass.iter = pass.iter or surface.get_chunks()
      chunk = pass.iter()
    end
    if not chunk then
      pass.i, pass.iter = pass.i + 1, nil
    else
      chunks = chunks + 1
      for _, e in pairs(surface.find_entities_filtered({ area = chunk.area, force = f, type = pass.types })) do
        local key = e.unit_number or key_of(e)
        if not pass.seen[key] then
          pass.seen[key] = true
          if e.type == "entity-ghost" then
            pass.ghosts = pass.ghosts + 1
            if pass.ghosts <= GHOSTS_MAX then
              cost = cost + check_entity(e, pass.found)
            end
          else
            cost = cost + check_entity(e, pass.found)
          end
        end
      end
    end
  end
end

local function repair_item_names()
  if not repair_items then
    repair_items = {}
    for name, item in pairs(prototypes.item) do
      if item.type == "repair-tool" then
        repair_items[#repair_items + 1] = name
      end
    end
  end
  return repair_items
end

-- Damaged buildings in a construction area with no repair packs anywhere in its networks.
local function scan_repair()
  local al = state()
  local out = {}
  local packs = repair_item_names()
  for unit, e in pairs(al.hurt) do
    if not e.valid or e.get_health_ratio() == nil or e.get_health_ratio() >= 1 then
      al.hurt[unit] = nil
    else
      local nets = networks_at(e)
      local have = #nets == 0
      for _, net in pairs(nets) do
        for _, p in ipairs(packs) do
          if net.get_item_count(p) > 0 then
            have = true
          end
        end
      end
      if not have then
        out[#out + 1] = entry(e)
      end
    end
  end
  scans.no_repair = out
end

local function out_of_fuel(train)
  local any = false
  for _, list in pairs({ train.locomotives.front_movers or {}, train.locomotives.back_movers or {} }) do
    for _, loco in pairs(list) do
      any = true
      local burner = loco.burner
      if not burner then
        return false
      end
      local inv = burner.inventory
      if burner.remaining_burning_fuel > 0 or (inv and not inv.is_empty()) then
        return false
      end
    end
  end
  return any
end

local function scan_trains()
  local fuel, path = {}, {}
  local trains = game.train_manager.get_trains({ force = force() })
  for _, train in pairs(trains) do
    local front = train.front_stock
    if front and front.valid then
      if not train.manual_mode and out_of_fuel(train) then
        fuel[#fuel + 1] = entry(front, train.id)
      elseif train.state == defines.train_state.no_path then
        path[#path + 1] = entry(front, train.id)
      end
    end
  end
  scans.train_fuel = fuel
  scans.train_path = path
end

local function scan_platforms()
  local path, storage_full = {}, {}
  local ok, platforms = pcall(function() return force().platforms end)
  for _, p in pairs(ok and platforms or {}) do
    local hub = p.valid and p.hub
    if hub and hub.valid then
      if p.state == defines.space_platform_state.no_path then
        path[#path + 1] = entry(hub, p.name)
      end
      local inv = hub.get_inventory(defines.inventory.hub_main)
      if inv and inv.is_full() then
        storage_full[#storage_full + 1] = entry(hub, p.name)
      end
    end
  end
  scans.platform_path = path
  scans.platform_storage = storage_full
end

local SCANS = { scan_repair, scan_trains, scan_platforms }

---------------------------------------------------------------------------------------------

-- The order of Factorio's alert bar, then the machine warnings.
local ORDER = { "destroyed", "attack", "fire", "no_ammo", "no_material", "no_robots", "no_repair", "train_fuel", "train_path",
  "platform_path", "platform_storage", "collector", "launch", "no_power", "unplugged", "low_power", "no_fuel", "output_full" }

local function from_events(al, kind)
  local list = {}
  for key, rec in pairs(al[kind]) do
    if game.tick - rec.t > LIFETIME[kind] then
      al[kind][key] = nil
    else
      list[#list + 1] = rec.e
    end
  end
  return list
end

local function message()
  local al = state()
  local here = puppet.get()
  local si = here and here.surface.index or 0
  local l = {}
  for _, kind in ipairs(ORDER) do
    local list = LIFETIME[kind] and from_events(al, kind) or (scans[kind] and still_there(scans[kind]))
    if list and #list > 0 then
      -- The character's surface first, nearest the camera first (only PER_KIND are listed, and
      -- the client draws icons over those).
      local f = storage.f3d.focus
      local fx, fy = world.fixed(f.x), world.fixed(f.y)
      local function d2(e)
        return (e[1] - fx) ^ 2 + (e[2] - fy) ^ 2
      end
      table.sort(list, function(a, b)
        if (a[3] == si) ~= (b[3] == si) then
          return a[3] == si
        end
        local da, db = d2(a), d2(b)
        if da ~= db then
          return da < db
        end
        return a[5] < b[5]
      end)
      local shown = {}
      for i = 1, math.min(#list, PER_KIND) do
        shown[i] = list[i]
      end
      l[#l + 1] = { kind, #list, shown }
    end
  end
  return { t = "al", l = l }
end

function M.tick()
  local t = game.tick
  local ok, err = pcall(step_pass)
  if not ok then
    pass = nil
    log("[factorio-3d-bridge] alert pass: " .. tostring(err))
  end
  if t % SCAN_STEP == 0 then
    local i = (t / SCAN_STEP) % #SCANS + 1
    ok, err = pcall(SCANS[i])
    if not ok then
      log("[factorio-3d-bridge] alert scan " .. i .. ": " .. tostring(err))
    end
  end
  -- Its own phase: the bridge's periodic jobs all fell on the same tick once a second (budget.lua).
  if (t + 29) % SEND_INTERVAL == 0 then
    transport.send_now(message())
  end
end

-- What the next `al` would say (live_check, /c).
function M.current()
  for _, scan in ipairs(SCANS) do
    scan()
  end
  pass = nil
  repeat
    step_pass(true)
  until not pass
  return message()
end

function M.reset()
  scans = {}
  pass = nil
  next_pass = 0
end

-- For measuring a pass's cost (/c): one step, and whether the pass just finished.
function M.tick_pass()
  step_pass(true)
end

function M.pass_done()
  return pass == nil
end

return M
