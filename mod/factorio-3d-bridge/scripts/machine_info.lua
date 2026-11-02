-- What Factorio's production windows show beyond inventories, for the open machine screen (gui):
-- the recipe's ingredients and products (the recipe row, ghost slots and missing ingredients), the
-- burner's fuel left, the productivity bar, a drill's progress and resource, a lab's packs, the
-- temperature bar, the recipe chooser's groups, and a logistic chest's request settings.
-- Read-only except for set_chest_logistics. Every read is guarded: what a version or entity lacks
-- is left out.

local M = {}

local function try(fn)
  local ok, v = pcall(fn)
  if ok then
    return v
  end
  return nil
end

local function thousandths(v)
  return math.max(0, math.min(1000, math.floor(v * 1000 + 0.5)))
end

local function name_of(v)
  if type(v) == "string" then
    return v
  end
  return v and try(function() return v.name end) or nil
end

-- [[type, name, amount], ...]; products with a range or a probability give their average.
local function amounts(list)
  local out = {}
  for _, x in ipairs(list or {}) do
    local amount = x.amount
    if not amount and x.amount_min then
      amount = (x.amount_min + (x.amount_max or x.amount_min)) / 2
    end
    amount = (amount or 0) * (x.probability or 1)
    out[#out + 1] = { x.type or "item", x.name, math.floor(amount * 100 + 0.5) / 100 }
  end
  return out
end

-- A recipe (LuaRecipe or LuaRecipePrototype) -> {i, o, e}.
function M.recipe_details(recipe)
  if not recipe then
    return nil
  end
  return try(function()
    return { i = amounts(recipe.ingredients), o = amounts(recipe.products), e = recipe.energy }
  end)
end

-- [group, group order, subgroup order .. " " .. subgroup, recipe order] for the recipe chooser.
function M.recipe_group(recipe)
  return try(function()
    return { recipe.group.name, recipe.group.order, recipe.subgroup.order .. " " .. recipe.subgroup.name, recipe.order }
  end) or { "", "", "", "" }
end

-- The furnace's last recipe (2.x: {name, quality}), for its product row while it is idle.
local function previous_recipe(e)
  local prev = try(function() return e.previous_recipe end)
  if not prev then
    return nil
  end
  local name = name_of(prev.name) or name_of(prev)
  return name and try(function() return e.force.recipes[name] end) or nil
end

-- How much of the burning fuel item is left, in thousandths; nil without a burner.
local function burner_left(e)
  local burner = try(function() return e.burner end)
  if not burner then
    return nil
  end
  local burning = try(function() return burner.currently_burning end)
  if not burning then
    return 0
  end
  local proto = try(function() return burning.name end) or burning
  local value = try(function() return proto.fuel_value end)
  if type(value) ~= "number" then
    value = try(function() return prototypes.item[proto].fuel_value end)
  end
  local left = try(function() return burner.remaining_burning_fuel end) or 0
  if type(value) ~= "number" or value <= 0 then
    return 0
  end
  return thousandths(left / value)
end

local function drill_fields(msg, e)
  local target = try(function() return e.mining_target end)
  local progress = try(function() return e.mining_progress end) or try(function() return e.crafting_progress end)
  if type(progress) == "number" then
    msg.mp = thousandths(progress)
  end
  if not (target and target.valid) then
    return
  end
  msg.mt = target.name
  -- A fluid resource (crude oil): its yield per second, in hundredths, like the pumpjack's "4.3/s".
  local rate = try(function()
    local mp = target.prototype.mineable_properties
    local product = mp.products and mp.products[1]
    if not (product and product.type == "fluid") then
      return nil
    end
    local normal = target.prototype.normal_resource_amount
    local yield = normal and normal > 0 and target.amount / normal or 1
    return e.prototype.mining_speed * yield * (product.amount or product.amount_max or 1) / (mp.mining_time or 1)
  end)
  if type(rate) == "number" then
    msg.mr = math.floor(rate * 100 + 0.5)
  end
end

-- The requester point that carries "trash unrequested", by entity type.
local REQUESTER_POINTS = {
  ["logistic-container"] = "logistic_container", ["cargo-landing-pad"] = "cargo_landing_pad_requester",
  ["rocket-silo"] = "rocket_silo_requester",
}

-- {tu (trash unrequested), rb? (request from buffers), sec} for requester and buffer chests, landing
-- pads and rocket silos.
local function chest_logistics(e, space)
  local point_name = REQUESTER_POINTS[e.type]
  if not point_name then
    return nil
  end
  if e.type == "logistic-container" then
    local mode = try(function() return e.prototype.logistic_mode end)
    if mode ~= "requester" and mode ~= "buffer" then
      return nil
    end
  end
  local sec = space.sections_of(e)
  if not sec then
    return nil
  end
  local info = { sec = sec }
  local point = try(function() return e.get_logistic_point(defines.logistic_member_index[point_name]) end)
  local trash = point and try(function() return point.trash_not_requested end)
  info.tu = trash and 1 or 0
  if e.type == "logistic-container" and try(function() return e.prototype.logistic_mode end) == "requester" then
    info.rb = try(function() return e.request_from_buffers end) and 1 or 0
  end
  return info
end

-- [grams in the rocket, grams it can lift] for a rocket silo's "Rocket capacity usage".
local function rocket_weight(e)
  local inv = try(function() return e.get_inventory(defines.inventory.rocket_silo_rocket) end)
  if not inv then
    return nil
  end
  local used = 0
  for i = 1, #inv do
    local stack = inv[i]
    if stack.valid_for_read then
      used = used + stack.count * (try(function() return stack.prototype.weight end) or 0)
    end
  end
  local lift = try(function() return prototypes.utility_constants.default_rocket_lift_weight end) or 1000000
  return { math.floor(used + 0.5), math.floor(lift + 0.5) }
end


-- [[slot, thousandths], ...]: what is left of the pack the lab has started on, for each slot
-- holding that pack (Factorio's orange pie over the slot). 2.1 keeps it in the lab
-- (LuaEntity.get_stored_durability), as a share of the pack's durability (1 for science packs, which
-- are plain items there). Packs not started are left out.
local function lab_durability(e)
  local inv = try(function() return e.get_inventory(defines.inventory.lab_input) end)
  if not inv then
    return nil
  end
  local out = {}
  for i = 1, #inv do
    local stack = inv[i]
    if stack.valid_for_read then
      local stored = try(function() return e.get_stored_durability(stack.name) end)
      local left = stored and stored.durability
      local full = try(function() return stack.prototype.get_durability() end) or 1
      if type(left) == "number" and left > 0 and left < full then
        out[#out + 1] = { i, thousandths(left / full) }
      end
    end
  end
  return out
end

function M.fill(msg, e, kind, space, with_lists)
  if kind == "crafter" or kind == "furnace" or kind == "silo" then
    local recipe = try(function() return e.get_recipe() end)
    if not recipe and kind == "furnace" then
      recipe = previous_recipe(e)
      if recipe then
        msg.rp = recipe.name
      end
    end
    msg.rd = M.recipe_details(recipe)
    -- A rocket silo crafts rocket parts like an assembler (screens.lua sets these for crafters).
    if kind == "silo" and recipe then
      msg.recipe = recipe.name
      local progress = try(function() return e.crafting_progress end)
      if type(progress) == "number" then
        msg.pr = thousandths(progress)
      end
    end
    -- A fixed recipe (the captive biter spawner's) has no "change recipe" button.
    if kind == "crafter" and try(function() return e.prototype.fixed_recipe end) then
      msg.fixed = 1
    end
  end
  if kind == "crafter" or kind == "furnace" or e.type == "mining-drill" or kind == "silo" then
    local bonus = try(function() return e.productivity_bonus end)
    if type(bonus) == "number" and bonus > 0 then
      msg.pb = math.floor(bonus * 1000 + 0.5)
      local progress = try(function() return e.bonus_progress end)
      if e.type == "mining-drill" then
        local target = try(function() return e.mining_target end)
        local raw = try(function() return e.bonus_mining_progress end)
        local time = target and try(function() return target.prototype.mineable_properties.mining_time end)
        progress = raw and time and time > 0 and raw / time or nil
      end
      if type(progress) == "number" then
        msg.bp = thousandths(progress)
      end
    end
  end
  if e.type == "mining-drill" then
    drill_fields(msg, e)
  end
  msg.bn = burner_left(e)
  local temperature = try(function() return e.temperature end)
  if type(temperature) == "number" then
    msg.tc = math.floor(temperature * 100 + 0.5)
    msg.tmax = try(function() return e.prototype.heat_buffer_prototype.max_temperature end)
  end
  if with_lists and (e.type == "lab") then
    msg.li = try(function() return e.prototype.lab_inputs end)
  end
  if e.type == "lab" then
    local ld = lab_durability(e)
    if ld and #ld > 0 then
      msg.ld = ld
    end
  end
  msg.lc = chest_logistics(e, space)
  if kind == "silo" then
    msg.rw = rocket_weight(e)
  end
  -- The force's logistic groups, for the section header's group picker (with the recipe list).
  if with_lists and try(function() return e.get_logistic_sections() end) then
    msg.lgs = try(function() return e.force.get_logistic_groups() end)
  end
end

-- The hub or landing pad a cargo bay is part of (nil for anything else, or a loose bay).
function M.bay_owner(e)
  if e.type ~= "cargo-bay" then
    return nil
  end
  local owner = try(function() return e.cargo_bay_connection_owner end)
  return owner and owner.valid and owner.unit_number and owner or nil
end

-- {u, tu? 0/1, rb? 0/1}: a requester or buffer chest's "Trash unrequested" and "Request from buffer
-- chests" boxes.
function M.set_chest_logistics(e, cmd)
  local point_name = REQUESTER_POINTS[e.type]
  if not point_name then
    error("nothing with requests")
  end
  if cmd.tu ~= nil then
    local point = e.get_logistic_point(defines.logistic_member_index[point_name])
    point.trash_not_requested = cmd.tu == 1
  end
  if cmd.rb ~= nil then
    e.request_from_buffers = cmd.rb == 1
  end
end

return M
