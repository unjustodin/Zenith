-- The character's gear: its armour's equipment grid (and the grid of the vehicle it sits in or has
-- open), putting, taking and moving equipment, Factorio's personal roboport (Alt+F) and
-- exoskeleton (Alt+E) toggles, and the character screen's info tab (bonuses and distances).
--
-- Commands change the game only from on_udp_packet_received, and what is sent depends only on the
-- game, so this stays deterministic in multiplayer.

local transport = require("scripts.transport")
local puppet = require("scripts.puppet")

local M = {}

local GRID_INTERVAL = 30   -- grids twice a second (energy and shields change all the time)
local INFO_INTERVAL = 60
local RESEND_TICKS = 300   -- unchanged data again every 5 s, as these are sent unreliably

local function get(obj, key)
  local ok, v = pcall(function() return obj[key] end)
  if ok then
    return v
  end
  return nil
end

-- An entity's equipment grid (a character's is its armour's), or nil.
function M.grid_of(e)
  if not (e and e.valid) then
    return nil
  end
  local g = get(e, "grid")
  return (g and g.valid) and g or nil
end

-- The vehicle whose grid the client sees: the open screen's, else the one the character sits in.
local function vehicle_of(c)
  local sc = storage.f3d.screen
  if sc and sc.entity and sc.entity.valid and M.grid_of(sc.entity) and sc.entity.type ~= "character" then
    return sc.entity
  end
  local v = puppet.vehicle(c)
  if v and M.grid_of(v) then
    return v
  end
  return nil
end

local function round(v)
  return math.floor((tonumber(v) or 0) + 0.5)
end

-- {t = "eq", ...}: the grid's size and every piece of equipment with its energy and shield, and
-- the grid's totals. A missing grid is w = h = 0.
local function grid_message(kind, owner, g)
  local msg = { t = "eq", kind = kind, u = owner and owner.unit_number or 0, w = 0, h = 0, l = {} }
  if not g then
    return msg
  end
  msg.w, msg.h = g.width, g.height
  local night = 0
  for _, eq in pairs(g.equipment) do
    local name = eq.name
    local ghost = 0
    if eq.type == "equipment-ghost" then
      name = get(eq, "ghost_name") or name
      ghost = 1
    end
    local shape = eq.shape or {}
    local q = get(eq, "quality")
    local rec = {
      name, eq.position.x, eq.position.y, shape.width or 1, shape.height or 1,
      q and q.name or "normal",
      round(get(eq, "energy")), round(get(eq, "max_energy")),
      round(get(eq, "shield")), round(get(eq, "max_shield")), ghost,
    }
    msg.l[#msg.l + 1] = rec
    if eq.type == "night-vision-equipment" and ghost == 0 and (get(eq, "energy") or 0) > 0 then
      night = 1
    end
  end
  msg.sh, msg.msh = round(g.shield), round(g.max_shield)
  msg.bat, msg.mbat = round(g.available_in_batteries), round(g.battery_capacity)
  local ok, gen = pcall(g.get_generator_energy)
  msg.gen = ok and round((gen or 0) * 60) or 0 -- watts
  msg.mv = round((get(g, "movement_bonus") or 0) * 1000)
  msg.inv = round(get(g, "inventory_bonus") or 0)
  msg.mvon = get(g, "inhibit_movement_bonus") and 0 or 1
  msg.nv = night
  if owner then
    local rb = get(owner, "allow_dispatching_robots")
    if rb ~= nil then
      msg.rb = rb and 1 or 0
    end
  end
  return msg
end

-- What changes the picture: energy and shields in hundredths of their maximum.
local function signature(msg)
  local parts = { msg.kind, msg.u, msg.w, msg.h, msg.sh or "", msg.mvon or "", msg.rb or "", msg.nv or "",
    math.floor((msg.bat or 0) * 100 / math.max(1, msg.mbat or 1)) }
  for _, r in ipairs(msg.l) do
    parts[#parts + 1] = table.concat({ r[1], r[2], r[3], r[6], r[11],
      math.floor(r[7] * 100 / math.max(1, r[8])), r[9] }, "/")
  end
  return table.concat(parts, ",")
end

local function send_if_changed(s, key, msg, sig)
  s.eq_sent = s.eq_sent or {}
  local last = s.eq_sent[key]
  if last and last.sig == sig and game.tick - last.tick < RESEND_TICKS then
    return
  end
  s.eq_sent[key] = { sig = sig, tick = game.tick }
  transport.send_now(msg)
end

local function send_grids(c, s, force)
  if force then
    s.eq_sent = {}
  end
  local own = grid_message("char", c, M.grid_of(c))
  send_if_changed(s, "char", own, signature(own))
  local v = vehicle_of(c)
  local veh = grid_message("veh", v, v and M.grid_of(v))
  send_if_changed(s, "veh", veh, signature(veh))
end

---------------------------------------------------------------------------------------------
-- Character info: Factorio's character tab

local function number(v)
  return tonumber(v) or 0
end

local function send_info(c, s, force)
  local f = c.force
  local g = M.grid_of(c)
  local mhp = get(c, "max_health") or 0
  local info = {
    t = "cinfo",
    -- Multipliers in thousandths (1000 = 100 %): Factorio's character tab shows them as bonuses.
    craft = round(1000 * (1 + number(get(c, "character_crafting_speed_modifier")) + number(get(f, "manual_crafting_speed_modifier")))),
    mine = round(1000 * (1 + number(get(c, "character_mining_speed_modifier")) + number(get(f, "manual_mining_speed_modifier")))),
    run = round(1000 * (1 + number(get(c, "character_running_speed_modifier")) + number(get(f, "character_running_speed_modifier")))),
    -- The character's speed now (tiles per tick, x1000), with exoskeletons, tiles and stickers.
    speed = round(1000 * number(get(c, "character_running_speed"))),
    eqmv = g and round(1000 * number(get(g, "movement_bonus"))) or 0,
    -- Distances in tenths of a tile.
    reach = round(10 * number(get(c, "reach_distance"))),
    build = round(10 * number(get(c, "build_distance"))),
    rreach = round(10 * number(get(c, "resource_reach_distance"))),
    pick = round(10 * number(get(c, "item_pickup_distance"))),
    loot = round(10 * number(get(c, "loot_pickup_distance"))),
    drop = round(10 * number(get(c, "drop_item_distance"))),
    invb = round(number(get(c, "character_inventory_slots_bonus")) + number(get(f, "character_inventory_slots_bonus"))),
    eqinv = g and round(number(get(g, "inventory_bonus"))) or 0,
    trash = round(number(get(f, "character_trash_slot_count")) + number(get(c, "character_trash_slot_count_bonus"))),
    hp = round(mhp),
    hpb = round(number(get(c, "character_health_bonus")) + number(get(f, "character_health_bonus"))),
    robots = round(number(get(c, "character_maximum_following_robot_count_bonus")) + number(get(f, "maximum_following_robot_count"))),
  }
  local main = c.get_main_inventory()
  info.slots = main and #main or 0
  local parts = {}
  for _, k in ipairs({ "craft", "mine", "run", "speed", "eqmv", "reach", "build", "rreach", "pick", "loot", "drop",
      "invb", "eqinv", "trash", "hp", "hpb", "robots", "slots" }) do
    parts[#parts + 1] = info[k]
  end
  local sig = table.concat(parts, ",")
  if not force and s.info_sig == sig and game.tick - (s.info_tick or 0) < RESEND_TICKS then
    return
  end
  s.info_sig, s.info_tick = sig, game.tick
  transport.send_now(info)
end

---------------------------------------------------------------------------------------------
-- Commands

-- The grid a command names: kind "char" (the character's armour) or "veh" with the vehicle's unit.
local function grid_for(cmd)
  local c = puppet.get()
  if not c then
    return nil
  end
  if tostring(cmd.kind or "char") == "veh" then
    local v = vehicle_of(c)
    if not (v and v.unit_number == tonumber(cmd.u)) then
      return nil
    end
    if puppet.vehicle(c) ~= v and not puppet.can_reach(c, v) then
      puppet.message("Out of reach")
      return nil
    end
    return c, M.grid_of(v), v
  end
  return c, M.grid_of(c), c
end

local function position_of(cmd, xk, yk)
  local x, y = tonumber(cmd[xk]), tonumber(cmd[yk])
  if x and y then
    return { x = math.floor(x), y = math.floor(y) }
  end
  return nil
end

local function changed()
  storage.f3d.eq_sent = {}
  storage.f3d.info_sig = nil
end

-- {kind, u?, fi, x?, y?}: equipment from main inventory slot fi into the grid at x, y (without a
-- position: the first place it fits, like Shift+click in Factorio).
function M.put(cmd)
  local c, g = grid_for(cmd)
  if not g then
    return puppet.message("No equipment grid")
  end
  local main = c.get_main_inventory()
  local fi = math.floor(tonumber(cmd.fi) or 0)
  if not (main and fi >= 1 and fi <= #main and main[fi].valid_for_read) then
    return
  end
  local stack = main[fi]
  local eq = get(stack.prototype, "place_as_equipment_result")
  if not eq then
    return puppet.message("That isn't equipment")
  end
  local q = get(stack, "quality")
  local spec = { name = eq.name, quality = q and q.name or "normal" }
  spec.position = position_of(cmd, "x", "y")
  local ok, placed = pcall(g.put, spec)
  if not (ok and placed) then
    return puppet.message("No room for that in the grid")
  end
  if stack.count > 1 then
    stack.count = stack.count - 1
  else
    stack.clear()
  end
  changed()
  puppet.send_inventory_now()
end

-- {kind, u?, x, y, ti?}: takes the equipment at x, y into the main inventory (slot ti when it is
-- empty, else wherever it fits; what doesn't fit goes on the ground).
function M.take(cmd)
  local c, g = grid_for(cmd)
  local at = position_of(cmd, "x", "y")
  if not (g and at) then
    return
  end
  local eq = g.get(at)
  if not eq then
    return
  end
  local ok, item = pcall(g.take, { equipment = eq })
  if not (ok and item) then
    return puppet.message("Can't take that out")
  end
  local stack = { name = item.name, count = item.count or 1, quality = item.quality or "normal" }
  local main = c.get_main_inventory()
  local ti = math.floor(tonumber(cmd.ti) or 0)
  local done = 0
  if main and ti >= 1 and ti <= #main and not main[ti].valid_for_read and main[ti].set_stack(stack) then
    done = stack.count
  end
  if done < stack.count then
    stack.count = stack.count - done
    local n = c.insert(stack)
    if n < stack.count then
      stack.count = stack.count - n
      pcall(function() c.surface.spill_item_stack({ position = c.position, stack = stack }) end)
    end
  end
  changed()
  puppet.send_inventory_now()
end

-- {kind, u?, x, y, tx, ty}: moves the equipment at x, y so its top left is at tx, ty.
function M.move(cmd)
  local _, g = grid_for(cmd)
  local from, to = position_of(cmd, "x", "y"), position_of(cmd, "tx", "ty")
  if not (g and from and to) then
    return
  end
  local eq = g.get(from)
  if not eq then
    return
  end
  -- 2.1 takes a table; older builds took (equipment, position).
  local ok, moved = pcall(g.move, { equipment = eq, position = to })
  if not ok then
    ok, moved = pcall(g.move, eq, to)
  end
  if not (ok and moved) then
    puppet.message("Can't put that there")
  end
  changed()
end

-- {what = "roboport" | "movement", on = 0/1}: Factorio's Alt+F and Alt+E toggles, on the
-- character (or the vehicle the command names with kind "veh").
function M.toggle(cmd)
  local c, g, owner = grid_for(cmd)
  if not c then
    return
  end
  local on = tonumber(cmd.on) == 1
  local what = tostring(cmd.what or "")
  if what == "roboport" then
    pcall(function() owner.allow_dispatching_robots = on end)
  elseif what == "movement" and g then
    pcall(function() g.inhibit_movement_bonus = not on end)
  end
  changed()
end

---------------------------------------------------------------------------------------------

function M.tick()
  local s = storage.f3d
  local c = puppet.get()
  if not c then
    return
  end
  if game.tick % GRID_INTERVAL == 0 or not s.eq_sent or not next(s.eq_sent) then
    send_grids(c, s, false)
  end
  -- Its own phase: the bridge's periodic jobs all fell on the same tick once a second (budget.lua).
  if (game.tick + 53) % INFO_INTERVAL == 0 or not s.info_sig then
    send_info(c, s, false)
  end
end

function M.send_initial()
  local s = storage.f3d
  s.eq_sent = {}
  s.info_sig = nil
end

return M
