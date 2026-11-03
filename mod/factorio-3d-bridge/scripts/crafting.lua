-- Hand-crafting for Factorio's crafting window: every hand-craftable recipe with its ingredients,
-- products, time and place in the crafting tabs; how many of each the character can make now; and
-- the crafting queue, which the client can cancel entries from.
--
-- Signatures live in storage and change only in on_tick and events, so this is deterministic.

local transport = require("scripts.transport")
local puppet = require("scripts.puppet")

local M = {}

local DETAILS_INTERVAL = 600   -- research unlocks recipes; research.lua also asks for a resend
local CRAFTABLE_INTERVAL = 30
local QUEUE_INTERVAL = 10
local RECIPES_PER_MESSAGE = 40

-- The force's enabled, visible recipes the character can craft by hand, sorted by name. The
-- candidates come from prototypes (puppet.hand_recipe_names), so this reads `enabled` for those
-- only, not every recipe of the force.
local function hand_recipes(c)
  local recipes = c.force.recipes
  local list = {}
  for _, name in ipairs(puppet.hand_recipe_names(c)) do
    local recipe = recipes[name]
    if recipe and recipe.enabled and not recipe.hidden then
      list[#list + 1] = recipe
    end
  end
  return list
end

local function amounts(list)
  local out = {}
  for _, x in pairs(list or {}) do
    local amount = x.amount
    if amount == nil and x.amount_min and x.amount_max then
      amount = (x.amount_min + x.amount_max) / 2
    end
    amount = (amount or 1) * (x.probability or 1)
    out[#out + 1] = { x.type, x.name, amount }
  end
  return out
end

local function group_of(recipe, key)
  local ok, g = pcall(function() return recipe[key] end)
  if ok and g then
    return g.name, g.order
  end
  return "", ""
end

-- [name, energy (seconds), categories, group, group order, subgroup, subgroup order, order,
--  ingredients [[type, name, amount], ...], products [[type, name, amount], ...]]
function M.record(recipe)
  local group, group_order = group_of(recipe, "group")
  local subgroup, subgroup_order = group_of(recipe, "subgroup")
  return {
    recipe.name, recipe.energy, puppet.recipe_categories(recipe), group, group_order, subgroup,
    subgroup_order, recipe.order, amounts(recipe.ingredients), amounts(recipe.products),
  }
end

local function send_details(c, s, recipes)
  local names = {}
  for i, recipe in ipairs(recipes) do
    names[i] = recipe.name
  end
  s.hand_recipes = names
  local sig = table.concat(names, ",")
  if sig == s.rdet_sig then
    return
  end
  s.rdet_sig = sig
  local parts = math.max(1, math.ceil(#recipes / RECIPES_PER_MESSAGE))
  for part = 1, parts do
    local slice = {}
    for i = (part - 1) * RECIPES_PER_MESSAGE + 1, math.min(part * RECIPES_PER_MESSAGE, #recipes) do
      slice[#slice + 1] = M.record(recipes[i])
    end
    transport.send_reliable({ t = "rdet", part = part, parts = parts, l = slice })
  end
end

-- What the counts depend on: the main inventory's contents and the recipe list. Reading every
-- hand recipe's get_craftable_count cost ~22 ms in one tick on the owner's save (230 recipes, a full
-- inventory), twice a second; this signature costs a fraction of that, so the counts are only
-- worked out again when it changes.
local function contents_sig(c, s)
  local inv = c.get_main_inventory()
  local parts = { s.rdet_sig or "" }
  for _, it in ipairs(inv and inv.get_contents() or {}) do
    parts[#parts + 1] = it.name .. "/" .. (it.quality or "") .. "=" .. it.count
  end
  return table.concat(parts, ",")
end

-- [[recipe, how many the character could craft now], ...] for every non-zero count. The names
-- come from the last details check, so the recipe list isn't walked twice a second.
local function send_craftable(c, s)
  local inv_sig = contents_sig(c, s)
  if inv_sig == s.craftable_inv and s.craftable_sig ~= nil then
    return
  end
  s.craftable_inv = inv_sig
  local list, parts = {}, {}
  for _, name in ipairs(s.hand_recipes or {}) do
    local n = c.get_craftable_count(name)
    if n > 0 then
      list[#list + 1] = { name, n }
      parts[#parts + 1] = name .. "=" .. n
    end
  end
  local sig = table.concat(parts, ",")
  if sig ~= s.craftable_sig then
    s.craftable_sig = sig
    transport.send_reliable({ t = "craftable", l = list })
  end
end

-- The queue while it has something in it, and once more when it empties.
local function send_queue(c, s)
  local queue = c.crafting_queue or {}
  if #queue == 0 and not s.queue_sent then
    return
  end
  local list = {}
  for _, item in ipairs(queue) do
    list[#list + 1] = { item.index, item.recipe, item.count, item.prerequisite and 1 or 0 }
  end
  s.queue_sent = #queue > 0
  local progress = #queue > 0 and c.crafting_queue_progress or 0
  transport.send_now({ t = "cq", pr = math.floor(progress * 1000 + 0.5), l = list })
end

-- Factorio puts a player's hand-crafting in the force's production statistics, and that is also
-- what sets off "craft an item" research triggers (2.x: a lab unlocks red science). A character
-- with no player gets neither (checked in 2.1.23: a lab hand-crafted, the statistics still 0 and
-- the trigger never fired; recording it with on_flow fired it), so the bridge records its
-- character's finished crafts itself. A character a player is in is left to Factorio.
local function record_crafts(c, done)
  local stats = c.force.get_item_production_statistics(c.surface)
  for _, d in ipairs(done) do
    local recipe = prototypes.recipe[d[1]]
    if recipe then
      for _, p in pairs(recipe.products or {}) do
        if p.type == "item" then
          local amount = p.amount or ((p.amount_min or 1) + (p.amount_max or 1)) / 2
          stats.on_flow(p.name, amount * (p.probability or 1) * d[2])
        end
      end
      for _, i in pairs(recipe.ingredients or {}) do
        if i.type == "item" then
          stats.on_flow(i.name, -i.amount * d[2])
        end
      end
    end
  end
end

-- Between commands the queue only changes by crafting, which finishes its front: whole entries
-- gone, then fewer of the next. A command that adds or cancels crafts clears the last look
-- (`craft_seen`), so that tick is only looked at, not counted.
local function count_crafts(c, s)
  local seen = s.craft_seen
  if seen == nil and c.crafting_queue_size == 0 then
    return
  end
  local now = {}
  for i, item in ipairs(c.crafting_queue or {}) do
    now[i] = { item.recipe, item.count }
  end
  if seen and s.craft_unit == c.unit_number and #now <= #seen and not c.player then
    local done = {}
    local gone = #seen - #now
    for i = 1, gone do
      done[#done + 1] = seen[i]
    end
    local next, left = seen[gone + 1], now[1]
    if next and left and next[1] == left[1] and left[2] < next[2] then
      done[#done + 1] = { next[1], next[2] - left[2] }
    end
    if #done > 0 then
      record_crafts(c, done)
    end
  end
  s.craft_seen = #now > 0 and now or nil
  s.craft_unit = c.unit_number
end

---------------------------------------------------------------------------------------------
-- Commands

-- Cancels n crafts of queue entry i (the index from `cq`); ingredients go back to the character.
function M.cancel_craft(cmd)
  local c = puppet.get()
  local i, n = math.floor(tonumber(cmd.i) or 0), math.floor(tonumber(cmd.n) or 1)
  if not (c and i >= 1 and n >= 1) then
    return
  end
  for _, item in ipairs(c.crafting_queue or {}) do
    if item.index == i then
      c.cancel_crafting({ index = i, count = math.min(n, item.count) })
      storage.f3d.craft_seen = nil
      send_queue(c, storage.f3d)
      return
    end
  end
end

---------------------------------------------------------------------------------------------

function M.tick()
  local s = storage.f3d
  local c = puppet.get()
  if not c then
    return
  end
  count_crafts(c, s)
  if game.tick % DETAILS_INTERVAL == 0 or s.rdet_sig == nil then
    send_details(c, s, hand_recipes(c))
  end
  if game.tick % CRAFTABLE_INTERVAL == 0 then
    send_craftable(c, s)
  end
  if game.tick % QUEUE_INTERVAL == 0 then
    send_queue(c, s)
  end
end

-- Everything again: a new client, or research changed what can be crafted.
function M.invalidate()
  local s = storage.f3d
  s.rdet_sig = nil
  s.craftable_sig = nil
  s.craftable_inv = nil
  s.queue_sent = true
end

return M
