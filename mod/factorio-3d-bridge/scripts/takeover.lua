-- Taking over a save's own character on a headless server.
--
-- When a player disconnects, Factorio "logs off" their character: it leaves the world
-- (LuaPlayer::character is nil, get_associated_characters is empty), so nothing can walk or mine
-- with it. Its inventories, logistic requests, crafting queue and quickbar stay with the
-- LuaPlayer, which is a LuaControl and can still be read and written (checked in 2.1.23 on a
-- real save). So the bridge stands in for that player: its own character appears where the
-- player's was and the player's things move onto it. When the player connects again (with the
-- real game) everything moves back onto their character, and the bridge controls that one, as in
-- single-player.
--
-- Everything here runs from on_tick or from commands and events, and only touches storage, so
-- it stays deterministic in multiplayer.

local M = {}

-- The armour last: see move_all.
local INVENTORIES = { "character_guns", "character_ammo", "character_trash", "character_main", "character_armor" }

-- Per-character bonuses a script may have set on the player's character (LuaControl).
local BONUSES = {
  "character_inventory_slots_bonus", "character_trash_slot_count_bonus", "character_crafting_speed_modifier",
  "character_mining_speed_modifier", "character_running_speed_modifier", "character_build_distance_bonus",
  "character_item_drop_distance_bonus", "character_reach_distance_bonus", "character_resource_reach_distance_bonus",
  "character_item_pickup_distance_bonus", "character_loot_pickup_distance_bonus",
  "character_maximum_following_robot_count_bonus", "character_health_bonus",
}

local function get(obj, key)
  local ok, v = pcall(function() return obj[key] end)
  if ok then
    return v
  end
  return nil
end

local function inventory(control, name)
  local id = defines.inventory[name]
  if not id then
    return nil
  end
  local ok, inv = pcall(control.get_inventory, id)
  return ok and inv or nil
end

-- Where things that don't fit go: on the ground at `at` (an entity), so nothing is lost.
local function spill(stack, at)
  if at and at.valid then
    pcall(function()
      at.surface.spill_item_stack({ position = at.position, stack = stack, enable_looted = true, allow_belts = false })
    end)
  end
end

-- Inserts a stack into `to` (its main inventory, or guns and ammo where they go) and spills
-- the rest at `ground`, then empties it.
local function give(stack, to, ground)
  local ok, n = pcall(to.insert, stack)
  n = ok and n or 0
  if n < stack.count then
    stack.count = stack.count - n
    spill(stack, ground)
  end
  stack.clear()
end

-- Moves one inventory's stacks slot for slot (swap_stack keeps armour grids, blueprints and
-- spoilage), then its slot filters. What doesn't fit goes into `to`'s main inventory or on the
-- ground at `ground`.
local function move_inventory(a, b, to, ground)
  local moved = 0
  for i = 1, #a do
    local ok = pcall(function()
      local stack = a[i]
      if stack.valid_for_read then
        local done = false
        if i <= #b and not b[i].valid_for_read then
          done = stack.swap_stack(b[i])
        end
        if not done then
          give(stack, to, ground)
        end
        moved = moved + 1
      end
    end)
    if not ok then
      log("[factorio-3d-bridge] couldn't move slot " .. i)
    end
  end
  local ok, filters = pcall(function() return a.supports_filters() end)
  if ok and filters then
    for i = 1, math.min(#a, #b) do
      local okf, f = pcall(a.get_filter, i)
      if okf and f then
        local name = type(f) == "table" and f.name or f
        if type(name) ~= "string" then
          name = name and name.name
        end
        if name and pcall(b.set_filter, i, name) then
          pcall(a.set_filter, i, nil)
        end
      end
    end
  end
  return moved
end

-- Copies logistic requests: every section (groups by name, so they stay linked to the group),
-- whether requests are on, and auto-trash.
function M.copy_requests(from, to)
  local oka, a = pcall(function() return from.get_requester_point() end)
  local okb, b = pcall(function() return to.get_requester_point() end)
  if not (oka and a and okb and b) then
    return false
  end
  pcall(function()
    for i = b.sections_count, 1, -1 do
      b.remove_section(i)
    end
  end)
  for _, sec in pairs(a.sections or {}) do
    pcall(function()
      local group = sec.group
      local new
      if group and group ~= "" then
        new = b.add_section(group)
      else
        new = b.add_section()
        new.filters = sec.filters
      end
      if new then
        new.active = sec.active
        new.multiplier = sec.multiplier
      end
    end)
  end
  pcall(function() b.enabled = a.enabled end)
  pcall(function() b.trash_not_requested = a.trash_not_requested end)
  return true
end

-- Cancels `from`'s crafting queue (refunding its ingredients) and returns what was queued, to
-- start again on the other character once the ingredients moved too.
local function take_queue(from)
  local queue = get(from, "crafting_queue")
  if not queue then
    return {}
  end
  local out = {}
  for _, item in ipairs(queue) do
    if not item.prerequisite then
      out[#out + 1] = { recipe = item.recipe, count = item.count }
    end
  end
  for _ = 1, 200 do
    local q = get(from, "crafting_queue")
    if not q or #q == 0 then
      break
    end
    local last = q[#q]
    if not pcall(from.cancel_crafting, { index = last.index, count = last.count }) then
      return {} -- left with the player; nothing is lost
    end
  end
  return out
end

local function restart_queue(to, queue)
  for _, item in ipairs(queue) do
    pcall(to.begin_crafting, { recipe = item.recipe, count = item.count, silent = true })
  end
end

-- Moves everything a character carries from one LuaControl to another: a player (connected or
-- not) or a character entity. `ground` is where overflow is spilled. Returns the number of
-- stacks moved.
function M.move_all(from, to, ground)
  for _, key in ipairs(BONUSES) do
    local v = get(from, key)
    if v ~= nil then
      pcall(function() to[key] = v end)
    end
  end
  local queue = take_queue(from)
  -- Armour adds main inventory slots, and taking it off a character whose extra slots are in use
  -- would lose their place. So `to` gets as many main slots as `from` for the move, the main
  -- inventory moves before the armour, and the bonus goes back afterwards (by then the extra
  -- slots past the armour's are empty).
  local bonus = get(to, "character_inventory_slots_bonus")
  local am, bm = inventory(from, "character_main"), inventory(to, "character_main")
  if bonus and am and bm and #am > #bm then
    pcall(function() to.character_inventory_slots_bonus = bonus + #am - #bm end)
  end
  local moved = 0
  for _, name in ipairs(INVENTORIES) do
    local a, b = inventory(from, name), inventory(to, name)
    if a and b then
      moved = moved + move_inventory(a, b, to, ground)
    end
  end
  if bonus then
    pcall(function() to.character_inventory_slots_bonus = bonus end)
  end
  M.copy_requests(from, to)
  restart_queue(to, queue)
  return moved
end

-- Puts whatever an unrelated character carries (an earlier bridge character in this save) into
-- `to`, then removes it.
function M.absorb(old, to)
  for _, name in ipairs(INVENTORIES) do
    local a = inventory(old, name)
    if a then
      for i = 1, #a do
        pcall(function()
          local stack = a[i]
          if stack.valid_for_read then
            give(stack, to, to)
          end
        end)
      end
    end
  end
  pcall(old.destroy)
end

---------------------------------------------------------------------------------------------
-- Whose character

-- Which player the bridge plays as: in single-player the player; on a server the f3d-player
-- setting or /f3d-player when set, otherwise the player who was online last among those with a
-- character (in a save played alone, that is its owner). nil on a new map nobody joined.
function M.choose(s)
  if not game.is_multiplayer() then
    return game.get_player(1)
  end
  if s.owner_pick == 0 then
    return nil
  end
  if s.owner_pick then
    return game.get_player(s.owner_pick)
  end
  local wanted = settings.global["f3d-player"] and settings.global["f3d-player"].value or ""
  if wanted ~= "" then
    local p = game.get_player(wanted)
    if p then
      return p
    end
  end
  local best, best_seen
  for _, p in pairs(game.players) do
    local controller = get(p, "controller_type")
    local seen = p.connected and game.tick or (get(p, "last_online") or 0)
    if controller == defines.controllers.character and (not best or seen > best_seen) then
      best, best_seen = p, seen
    end
  end
  return best
end

-- A line per player for /f3d-player.
function M.describe(s)
  local lines = {}
  for _, p in pairs(game.players) do
    local mark = (s.owner_index == p.index) and " (playing as)" or ""
    lines[#lines + 1] = string.format("[Zenith] %d %s, %s%s", p.index, p.name,
      p.connected and "connected" or "not connected", mark)
  end
  if #lines == 0 then
    lines[1] = "[Zenith] no players in this game: the bridge plays its own character"
  end
  return lines
end

return M
