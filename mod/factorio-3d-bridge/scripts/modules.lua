-- Modules where the hands can't reach, Factorio 2.x's way: a module held and clicked
-- on a building out of reach, on one seen from the remote view (another surface, a platform's hub)
-- or on a ghost asks for it, and the robots (or a platform's hub) bring it. A ghost keeps the
-- request in its insert plan; a building gets an item request proxy, as a player's does. All of it
-- works without a player in 2.1.23 (LuaEntity.insert_plan, item_request_proxy, create_entity of
-- an item-request-proxy with `modules`). Within reach the module goes straight in, as a click does.
--
-- {u, p, x, y (the target, as `open` finds it), item, q? (quality), s? (a module slot from the
-- machine screen, 1-based), clr? (1: take the requests back: slot s's, or all)}.

local puppet = require("scripts.puppet")
local transport = require("scripts.transport")
local world = require("scripts.world")

local M = {}

-- The module inventory a ghost's entity will have (a built one says so itself). crafter_modules is
-- 2.1's name; 2.0 had one per type.
local INVENTORY = {
  ["assembling-machine"] = { "crafter_modules", "assembling_machine_modules" },
  furnace = { "crafter_modules", "furnace_modules" },
  ["rocket-silo"] = { "crafter_modules", "assembling_machine_modules" },
  ["mining-drill"] = { "mining_drill_modules" },
  lab = { "lab_modules" },
  beacon = { "beacon_modules" },
}

local function try(fn)
  local ok, v = pcall(fn)
  if ok then
    return v
  end
  return nil
end

-- {speed, productivity, consumption, pollution, quality} in thousandths, or nil without effects.
local EFFECTS = { { "speed", "sp" }, { "productivity", "pr" }, { "consumption", "co" }, { "pollution", "po" }, { "quality", "q" } }
function M.effects_of(e)
  local fx = try(function() return e.effects end)
  if type(fx) ~= "table" then
    return nil
  end
  local out, any = {}, false
  for _, pair in ipairs(EFFECTS) do
    local v = fx[pair[1]]
    if type(v) == "table" then
      v = v.bonus -- 1.1's shape
    end
    if type(v) == "number" and v ~= 0 then
      out[pair[2]] = math.floor(v * 1000 + 0.5)
      any = true
    end
  end
  return any and out or nil
end

local function round(v)
  return math.floor(v + 0.5)
end

-- What Factorio's entity info shows under "Consumes electricity" (H20) for something that draws
-- power: {e (joules in its buffer), b (the buffer's size: the Electricity bar is e / b), mx (Max.
-- consumption: the most it uses with its modules and beacons, plus its drain, in watts), mn (Min.
-- consumption: its drain, watts)}; nil for generators, accumulators and what isn't electric.
function M.electricity(e)
  local size = try(function() return e.electric_buffer_size end)
  if type(size) ~= "number" or size <= 0 then
    return nil
  end
  local source = try(function() return e.prototype.electric_energy_source_prototype end)
  local priority = source and try(function() return source.usage_priority end) or ""
  if not (priority:find("input", 1, true) or priority == "lamp") then
    return nil
  end
  local drain = (try(function() return e.electric_drain end) or 0) * 60
  local quality = try(function() return e.quality end)
  local usage = try(function() return e.prototype.get_max_energy_usage(quality) end)
    or try(function() return e.prototype.energy_usage end) or 0
  -- Factorio stops a consumption bonus at -80%.
  local bonus = try(function() return e.consumption_bonus end) or 0
  return { e = round(e.energy), b = round(size), mx = round(usage * 60 * math.max(0.2, 1 + bonus) + drain), mn = round(drain) }
end

-- The roboports a roboport's logistic cell is joined to (H14: Factorio draws the links when one is
-- hovered): [x, y, ...] in 1/256 tiles, from LuaLogisticCell.neighbours, so the game's own rule
-- decides; nil when it has no cell.
function M.roboport_links(e)
  local cell = try(function() return e.logistic_cell end)
  local near = cell and try(function() return cell.neighbours end)
  if type(near) ~= "table" then
    return nil
  end
  local out = {}
  for _, n in pairs(near) do
    local owner = try(function() return n.owner end)
    if owner and owner.valid and owner.type == "roboport" then
      out[#out + 1] = world.fixed(owner.position.x)
      out[#out + 1] = world.fixed(owner.position.y)
    end
  end
  return out
end

-- What Factorio's entity info shows for a machine with module slots or a beacon, answering
-- the client's `hinfo` {q, u, p, x, y} for the entity under the mouse: `hinfo` {q, u, eff? (its
-- effects: a machine's from its modules and beacons; a beacon's its modules' sum, before the
-- distribution effectivity, as 2.1.23 reports it), m? (its modules
-- [[name, count, quality?], ...]), b? (beacons reaching a machine), n? (machines a beacon reaches),
-- de? (a beacon's distribution effectivity, thousandths), el? (its electricity, M.electricity),
-- rn? (a roboport's links to other roboports, M.roboport_links)}.
-- Reads only.
function M.hover(cmd)
  local q = math.floor(tonumber(cmd.q) or 0)
  local e = puppet.find_target(world.surface(), cmd)
  local msg = { t = "hinfo", q = q, u = math.floor(tonumber(cmd.u) or 0) }
  if e and e.valid and e.type ~= "entity-ghost" then
    msg.el = M.electricity(e)
    msg.eff = M.effects_of(e)
    local inv = try(function() return e.get_module_inventory() end)
    if inv then
      local m = {}
      for _, it in pairs(try(function() return inv.get_contents() end) or {}) do
        local row = { it.name, it.count }
        local quality = type(it.quality) == "string" and it.quality or (it.quality and it.quality.name)
        if quality and quality ~= "normal" then
          row[3] = quality
        end
        m[#m + 1] = row
      end
      if #m > 0 then
        msg.m = m
      end
    end
    if e.type == "roboport" then
      msg.rn = M.roboport_links(e)
    end
    if e.type == "beacon" then
      local receivers = try(function() return e.get_beacon_effect_receivers() end)
      msg.n = receivers and #receivers or nil
      local de = try(function() return e.prototype.distribution_effectivity end)
      if type(de) == "number" then
        msg.de = math.floor(de * 1000 + 0.5)
      end
    else
      local beacons = try(function() return e.get_beacons() end)
      if beacons and #beacons > 0 then
        msg.b = #beacons
      end
    end
  end
  transport.send_now(msg)
end

local function inventory_index(e, proto)
  if e.type ~= "entity-ghost" then
    local inv = try(function() return e.get_module_inventory() end)
    if inv then
      return inv.index
    end
  end
  for _, name in ipairs(INVENTORY[proto.type] or {}) do
    local index = try(function() return defines.inventory[name] end)
    if index then
      return index
    end
  end
  return nil
end

local function slot_count(proto)
  return try(function() return proto.module_inventory_size end) or 0
end

-- Why the module can't go in there, or nil: every effect it raises must be one the machine (and
-- its recipe) allows, and its category one the machine takes.
local function refusal(item, proto, e)
  if item.type ~= "module" then
    return "That isn't a module"
  end
  local effects = try(function() return item.module_effects end) or {}
  local allowed = { try(function() return proto.allowed_effects end) }
  local recipe = e.type ~= "entity-ghost" and try(function() return e.get_recipe() end)
  if recipe then
    allowed[#allowed + 1] = try(function() return recipe.prototype.allowed_effects end)
  end
  for effect, v in pairs(effects) do
    if v > 0 then
      for _, a in pairs(allowed) do
        if a[effect] == false then
          return "That module's " .. effect .. " isn't allowed there"
        end
      end
    end
  end
  local cats = try(function() return proto.allowed_module_categories end)
  local cat = try(function() return item.category end)
  if cats and cat and not cats[cat] then
    return "That module doesn't fit there"
  end
  return nil
end

-- Where the requests are kept: the ghost itself, or the building's request proxy (nil: none yet).
local function holder(e)
  if e.type == "entity-ghost" then
    return e
  end
  local proxy = try(function() return e.item_request_proxy end)
  return proxy and proxy.valid and proxy or nil
end

-- The insert plan as {name, quality, inventory, stack (0-based)} rows, one per item.
local function rows_of(plans)
  local rows = {}
  for _, plan in pairs(plans or {}) do
    local id = plan.id or {}
    local name = id.name
    local quality = id.quality
    if type(quality) ~= "string" then
      quality = quality and quality.name or "normal"
    end
    for _, at in pairs(plan.items and plan.items.in_inventory or {}) do
      for _ = 1, at.count or 1 do
        rows[#rows + 1] = { name, quality, at.inventory, at.stack }
      end
    end
  end
  return rows
end

local function plans_of(rows)
  local plans, by = {}, {}
  for _, r in ipairs(rows) do
    local key = r[1] .. "/" .. r[2]
    local plan = by[key]
    if not plan then
      plan = { id = { name = r[1], quality = r[2] }, items = { in_inventory = {} } }
      by[key] = plan
      plans[#plans + 1] = plan
    end
    local list = plan.items.in_inventory
    list[#list + 1] = { inventory = r[3], stack = r[4], count = 1 }
  end
  return plans
end

local function read(e)
  local h = holder(e)
  return h and rows_of(try(function() return h.insert_plan end)) or {}
end

local function write(c, e, rows)
  local h = holder(e)
  local plans = plans_of(rows)
  if h then
    if #plans == 0 and h ~= e then
      h.destroy()
    else
      h.insert_plan = plans
    end
  elseif #plans > 0 then
    e.surface.create_entity({ name = "item-request-proxy", position = e.position, force = e.force, target = e, modules = plans })
  end
  local sc = storage.f3d.screen
  if sc and sc.entity == e then
    sc.due = game.tick
  end
end

-- For the machine screen (`gui` mrq): each module slot's requested module, "" where none is.
function M.slots(e)
  local proto = e.type == "entity-ghost" and e.ghost_prototype or e.prototype
  local index = inventory_index(e, proto)
  local n = slot_count(proto)
  if not index or n == 0 then
    return nil
  end
  local out, any = {}, false
  for i = 1, n do
    out[i] = ""
  end
  for _, r in ipairs(read(e)) do
    if r[3] == index and r[4] and r[4] >= 0 and r[4] < n then
      out[r[4] + 1] = r[1]
      any = true
    end
  end
  return any and out or nil
end

local function target(c, cmd)
  local sc = storage.f3d.screen
  if sc and sc.entity.valid and tonumber(cmd.u) == sc.unit and tonumber(cmd.u) ~= 0 then
    return sc.entity
  end
  return puppet.find_target(puppet.surface(c), cmd)
end

function M.request(cmd)
  local c = puppet.get()
  if not c then
    return
  end
  local e = target(c, cmd)
  if not (e and e.valid) then
    return puppet.message("Nothing there to put modules in")
  end
  if e.force ~= c.force then
    return puppet.message("That belongs to another force")
  end
  local ghost = e.type == "entity-ghost"
  local proto = ghost and e.ghost_prototype or e.prototype
  local index = inventory_index(e, proto)
  local n = slot_count(proto)
  if not index or n == 0 then
    return puppet.message("That has no module slots")
  end
  local slot = tonumber(cmd.s) and math.floor(tonumber(cmd.s)) - 1 or nil
  if slot and (slot < 0 or slot >= n) then
    return
  end
  local rows = read(e)
  if cmd.clr == 1 then
    local kept = {}
    for _, r in ipairs(rows) do
      if not (r[3] == index and (slot == nil or r[4] == slot)) then
        kept[#kept + 1] = r
      end
    end
    return write(c, e, kept)
  end
  local item = prototypes.item[tostring(cmd.item or "")]
  if not item then
    return
  end
  local why = refusal(item, proto, e)
  if why then
    return puppet.message(why)
  end
  local quality = type(cmd.q) == "string" and prototypes.quality[cmd.q] and cmd.q or "normal"
  local stack = { name = item.name, count = 1, quality = quality }
  local inv = not ghost and try(function() return e.get_module_inventory() end)
  -- Within the character's reach, on its own surface: the module goes in from the inventory.
  if inv and not slot and not storage.f3d.act_si and not puppet.hub(c) and e.surface == c.surface
      and puppet.can_reach(c, e) then
    local main = c.get_main_inventory()
    if main and main.get_item_count({ name = item.name, quality = quality }) > 0 then
      if inv.insert(stack) == 0 then
        return puppet.message("The module slots are full")
      end
      main.remove(stack)
      puppet.send_inventory_now()
      local sc = storage.f3d.screen
      if sc and sc.entity == e then
        sc.due = game.tick
      end
      return
    end
  end
  local taken = {}
  if inv then
    for i = 1, math.min(#inv, n) do
      if inv[i].valid_for_read then
        taken[i - 1] = "module"
      end
    end
  end
  for _, r in ipairs(rows) do
    if r[3] == index and r[4] then
      taken[r[4]] = taken[r[4]] or "request"
    end
  end
  if slot then
    if taken[slot] == "module" then
      return puppet.message("That slot has a module in it")
    end
    -- A request already in that slot is replaced.
    local kept = {}
    for _, r in ipairs(rows) do
      if not (r[3] == index and r[4] == slot) then
        kept[#kept + 1] = r
      end
    end
    rows = kept
  else
    for i = 0, n - 1 do
      if not taken[i] then
        slot = i
        break
      end
    end
    if not slot then
      return puppet.message("The module slots are full")
    end
  end
  rows[#rows + 1] = { item.name, quality, index, slot }
  write(c, e, rows)
  local asked = 0
  for _, r in ipairs(rows) do
    if r[3] == index then
      asked = asked + 1
    end
  end
  puppet.message(string.format("Module requested: %d of %d slots", asked, n))
end

return M
