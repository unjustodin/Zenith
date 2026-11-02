-- The force's game-wide windows that only read: Factorio's Bonuses window (research bonuses of the
-- bridge's force) and its Permissions window (the permission groups and who is in them).
-- Read-only; answered on request.

local transport = require("scripts.transport")
local puppet = require("scripts.puppet")

local M = {}

local function get(obj, key)
  local ok, v = pcall(function() return obj[key] end)
  if ok then
    return v
  end
  return nil
end

-- Force modifiers Factorio's Bonuses window lists, with the items it draws over each.
local MODIFIERS = {
  { "inserter_stack_size_bonus", { "inserter", "fast-inserter", "long-handed-inserter" } },
  { "bulk_inserter_capacity_bonus", { "bulk-inserter", "stack-inserter" } },
  { "belt_stack_size_bonus", { "turbo-transport-belt" } },
  { "mining_drill_productivity_bonus", { "electric-mining-drill", "burner-mining-drill", "big-mining-drill" } },
  { "laboratory_speed_modifier", { "lab", "biolab" } },
  { "laboratory_productivity_bonus", { "lab", "biolab" } },
  { "worker_robots_speed_modifier", { "logistic-robot", "construction-robot" } },
  { "worker_robots_storage_bonus", { "logistic-robot", "construction-robot" } },
  { "worker_robots_battery_modifier", { "logistic-robot", "construction-robot" } },
  { "following_robots_lifetime_modifier", { "defender-capsule", "distractor-capsule", "destroyer-capsule" } },
  { "character_inventory_slots_bonus", { "wooden-chest" } },
  { "character_health_bonus", { "heavy-armor" } },
  { "manual_crafting_speed_modifier", { "iron-gear-wheel" } },
  { "manual_mining_speed_modifier", { "iron-ore" } },
  { "train_braking_force_bonus", { "locomotive" } },
  { "artillery_range_modifier", { "artillery-turret", "artillery-wagon" } },
  { "beacon_distribution_modifier", { "beacon" } },
  { "character_reach_distance_bonus", { "steel-axe" } },
}

local function valid_items(names)
  local out = {}
  for _, n in ipairs(names) do
    if prototypes.item[n] then
      out[#out + 1] = n
    end
  end
  return out
end

-- The ammo items of each ammo category (for the damage and shooting speed rows' icons).
local function ammo_by_category()
  local out = {}
  local ok, items = pcall(function() return prototypes.get_item_filtered({ { filter = "type", type = "ammo" } }) end)
  if not ok or not items then
    return out
  end
  for name, item in pairs(items) do
    -- 2.1: LuaItemPrototype.ammo_category (a prototype); older: get_ammo_type().category.
    local got, cat = pcall(function() return item.ammo_category.name end)
    if not got then
      local ok2, ammo = pcall(function() return item.get_ammo_type() end)
      cat = ok2 and ammo and ammo.category or nil
    end
    if cat then
      out[cat] = out[cat] or {}
      if #out[cat] < 4 then
        out[cat][#out[cat] + 1] = name
      end
    end
  end
  for _, list in pairs(out) do
    table.sort(list)
  end
  return out
end

-- {}: `bonus` with l = [[kind, value, [item names to draw]], ...]: the force modifiers that aren't
-- zero ("inserter_stack_size_bonus", ...), and per ammo category "ammo_damage:<category>" and
-- "gun_speed:<category>", per turret "turret_attack:<turret>". Values as the API gives them
-- (fractions for modifiers, counts for bonuses).
function M.bonuses(_cmd)
  local c = puppet.get()
  local force = c and c.force or game.forces.player
  local list = {}
  for _, m in ipairs(MODIFIERS) do
    local v = tonumber(get(force, m[1]))
    if v and math.abs(v) > 1e-9 then
      list[#list + 1] = { m[1], math.floor(v * 1000 + 0.5) / 1000, valid_items(m[2]) }
    end
  end
  local ammo = ammo_by_category()
  local names = {}
  for cat in pairs(ammo) do
    names[#names + 1] = cat
  end
  table.sort(names)
  for _, cat in ipairs(names) do
    local okd, dmg = pcall(function() return force.get_ammo_damage_modifier(cat) end)
    if okd and dmg and math.abs(dmg) > 1e-9 then
      list[#list + 1] = { "ammo_damage:" .. cat, math.floor(dmg * 1000 + 0.5) / 1000, ammo[cat] }
    end
    local oks, spd = pcall(function() return force.get_gun_speed_modifier(cat) end)
    if oks and spd and math.abs(spd) > 1e-9 then
      list[#list + 1] = { "gun_speed:" .. cat, math.floor(spd * 1000 + 0.5) / 1000, ammo[cat] }
    end
  end
  for _, turret in ipairs({ "gun-turret", "laser-turret", "flamethrower-turret", "rocket-turret", "tesla-turret", "railgun-turret" }) do
    if prototypes.entity[turret] then
      local ok, v = pcall(function() return force.get_turret_attack_modifier(turret) end)
      if ok and v and math.abs(v) > 1e-9 then
        list[#list + 1] = { "turret_attack:" .. turret, math.floor(v * 1000 + 0.5) / 1000, prototypes.item[turret] and { turret } or {} }
      end
    end
  end
  transport.send_now({ t = "bonus", l = list })
end

-- {}: `perms` with l = [[group name, [player names]], ...] (Factorio's permission groups) and
-- `me` the group of the client's player ("" for the bridge's own character).
function M.permissions(_cmd)
  local list = {}
  local ok, groups = pcall(function() return game.permissions.groups end)
  for _, g in ipairs(ok and groups or {}) do
    local members = {}
    for _, p in pairs(get(g, "players") or {}) do
      members[#members + 1] = p.name
    end
    table.sort(members)
    list[#list + 1] = { g.name, members }
  end
  local c = puppet.get()
  local p = c and puppet.player_of(c)
  local group = p and get(p, "permission_group")
  transport.send_now({ t = "perms", l = list, me = group and group.name or "" })
end

return M
