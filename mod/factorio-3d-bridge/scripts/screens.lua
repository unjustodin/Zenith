-- Machine screens: the client opens one entity (a chest, assembler, furnace, lab...) to see what
-- is inside, pick a recipe and move items between it and the character. A headless server has no
-- GUI of its own, so this stands in for Factorio's entity windows.
--
-- The open entity lives in storage and only changes from client commands and on_tick, which every
-- peer replays in the same order, so it stays deterministic in multiplayer.

local registry = require("scripts.registry")
local transport = require("scripts.transport")
local puppet = require("scripts.puppet")
local fluids_power = require("scripts.fluids_power")
local circuits = require("scripts.circuits")
local circuit_settings = require("scripts.circuit_settings")
local spoilage = require("scripts.spoilage")
local planets = require("scripts.planets")
local trains = require("scripts.trains")
local entity_ui = require("scripts.entity_ui")
local logistics = require("scripts.logistics")
local space = require("scripts.space")
local machine_info = require("scripts.machine_info")
local map = require("scripts.map")
local modules = require("scripts.modules")

local M = {}

local INTERVAL = 30          -- state twice a second while a screen is open
local RECIPE_LIST_EVERY = 10 -- the recipe list rides along with the first state and every 10th after
local MAX_MOVE = 100000

local CONTAINER_TYPES = {
  container = true, ["logistic-container"] = true, ["linked-container"] = true, ["infinity-container"] = true,
}
local KINDS = { ["assembling-machine"] = "crafter", furnace = "furnace", lab = "lab" }

local function kind_of(e)
  if CONTAINER_TYPES[e.type] then
    return "container"
  end
  if circuits.is_combinator(e) then
    return "combinator"
  end
  if trains.is_rolling_stock(e) then
    return "train"
  end
  if trains.is_stop(e) then
    return "stop"
  end
  if logistics.is_roboport(e) then
    return "roboport"
  end
  return space.kind(e) or entity_ui.kind(e) or KINDS[e.type] or "other"
end

-- defines.inventory names differ between versions (2.0 has assembling_machine_input and
-- furnace_source; newer versions may only have crafter_input), so take the first that exists.
-- Reading a missing define is nil or an error depending on the version; pcall covers both.
local function inventory_index(names)
  for _, name in ipairs(names) do
    local ok, index = pcall(function() return defines.inventory[name] end)
    if ok and index then
      return index
    end
  end
  return nil
end

local INPUT_NAMES = {
  crafter = { "assembling_machine_input", "crafter_input" },
  furnace = { "furnace_source", "crafter_input" },
  lab = { "lab_input" },
  container = { "chest" },
}

-- Wagons: a cargo wagon's cargo, an artillery wagon's shells.
local WAGON_INVENTORIES = {
  ["cargo-wagon"] = { "cargo", "cargo_wagon" }, ["artillery-wagon"] = { "ammo", "artillery_wagon_ammo" },
}

-- {{role, LuaInventory}, ...} in display order. Roles: chest, input, output, fuel, burnt, modules,
-- cargo, ammo.
local function inventories(e, kind)
  local out = {}
  local function add(role, inventory)
    if inventory then
      out[#out + 1] = { role, inventory }
    end
  end
  local names = INPUT_NAMES[kind]
  local index = names and inventory_index(names)
  if index then
    add(kind == "container" and "chest" or "input", e.get_inventory(index))
  end
  -- Logistic chests' trash (requester and buffer chests in 2.x); a roboport's robots and repair packs.
  if e.type == "logistic-container" then
    local trash = inventory_index({ "logistic_container_trash" })
    add("trash", trash and e.get_inventory(trash))
  elseif kind == "roboport" then
    for _, pair in ipairs({ { "robots", "roboport_robot" }, { "repair", "roboport_material" } }) do
      local index = inventory_index({ pair[2] })
      add(pair[1], index and e.get_inventory(index))
    end
  end
  local wagon = kind == "train" and WAGON_INVENTORIES[e.type]
  if wagon then
    local wagon_index = inventory_index({ wagon[2] })
    add(wagon[1], wagon_index and e.get_inventory(wagon_index))
  end
  if kind ~= "container" and kind ~= "lab" and kind ~= "train" and kind ~= "stop" and kind ~= "roboport"
      and not entity_ui.no_output(kind) and not space.no_output(kind) then
    add("output", e.get_output_inventory())
  end
  add("fuel", e.get_fuel_inventory())
  add("burnt", e.get_burnt_result_inventory())
  add("modules", e.get_module_inventory())
  entity_ui.add_inventories(e, kind, add)
  space.add_inventories(e, kind, add)
  return out
end

-- LuaEntity::get_recipe returns the recipe (and in 2.x its quality as a second value).
local function current_recipe(e)
  local ok, recipe = pcall(function() return e.get_recipe() end)
  if ok and recipe then
    return recipe.name
  end
  return nil
end

local function machine_categories(e)
  local ok, cats = pcall(function() return e.prototype.crafting_categories end)
  return ok and cats or {}
end

local function can_make(e, recipe)
  if not (recipe and recipe.enabled and not recipe.hidden) then
    return false
  end
  local cats = machine_categories(e)
  for _, cat in pairs(puppet.recipe_categories(recipe)) do
    if cats[cat] then
      return true
    end
  end
  return false
end

-- Names of the force's enabled recipes that this machine's crafting categories allow.
local function recipe_names(c, e)
  local names = {}
  for name, recipe in pairs(c.force.recipes) do
    if can_make(e, recipe) then
      names[#names + 1] = name
    end
  end
  return names
end

local function close(s, why)
  local sc = s.screen
  s.screen = nil
  if why then
    puppet.message(why)
  end
  transport.send_now({ t = "gui", u = sc.unit, closed = true })
end

-- [[item, count] or [item, count, quality] or, for a spoiling item, [item, count, quality,
-- freshness (thousandths)], or 0 for an empty slot, ...] for every slot.
function M.slot_list(inventory)
  local list = {}
  for i = 1, #inventory do
    local stack = inventory[i]
    if stack.valid_for_read then
      local ok, q = pcall(function() return stack.quality.name end)
      local fresh = spoilage.freshness(stack)
      if fresh then
        list[i] = { stack.name, stack.count, ok and q or "normal", fresh }
      else
        list[i] = (not ok or q == "normal") and { stack.name, stack.count } or { stack.name, stack.count, q }
      end
    else
      list[i] = 0
    end
  end
  return list
end

-- defines.entity_status number -> name ("working", "no_power", ...), built once from the defines.
local STATUS_NAMES
local function status_name(e)
  if not STATUS_NAMES then
    STATUS_NAMES = {}
    for name, value in pairs(defines.entity_status) do
      STATUS_NAMES[value] = name
    end
  end
  local status = e.status
  return status and STATUS_NAMES[status] or nil
end

-- [[fluid or "", amount, capacity, temperature], ...] for every fluid box.
local function fluid_boxes(e)
  local out = {}
  for i, box in ipairs(fluids_power.storages(e)) do
    local fluid = box.fluid
    out[i] = {
      fluid and fluid.name or "", fluid and math.floor(fluid.amount + 0.5) or 0,
      math.floor(box.capacity + 0.5), fluid and math.floor((fluid.temperature or 0) + 0.5) or 0,
    }
  end
  return out
end

-- How full an electric machine's buffer is, in thousandths; nil if it doesn't run on electricity.
local function power_fill(e)
  local ok, size = pcall(function() return e.electric_buffer_size end)
  if not (ok and size and size > 0) then
    return nil
  end
  return math.max(0, math.min(1000, math.floor(e.energy / size * 1000 + 0.5)))
end

local function send_state(c, e, sc)
  local kind = kind_of(e)
  local inv, slots = {}, {}
  local list = inventories(e, kind)
  for _, pair in ipairs(list) do
    inv[pair[1]] = puppet.contents(pair[2])
    slots[pair[1]] = M.slot_list(pair[2])
  end
  local msg = { t = "gui", u = sc.unit, p = registry.entity_id(e.name), kind = kind, inv = inv, slots = slots }
  if kind == "crafter" or kind == "furnace" then
    msg.recipe = current_recipe(e)
    local ok, progress = pcall(function() return e.crafting_progress end)
    if ok and type(progress) == "number" then
      msg.pr = math.max(0, math.min(1000, math.floor(progress * 1000 + 0.5)))
    end
  end
  msg.status = status_name(e)
  -- Opened from the remote view out of reach (`far`): items can't move, modules are requested
  -- instead (`mrq`, each module slot's requested module or "").
  if sc.remote and not puppet.can_reach(c, e) then
    msg.far = 1
  end
  if slots.modules then
    local okm, requested = pcall(modules.slots, e)
    msg.mrq = okm and requested or nil
  end
  local ok, boxes = pcall(fluid_boxes, e)
  if ok and #boxes > 0 then
    msg.fb = boxes
  end
  msg.pw = power_fill(e)
  if e.type == "agricultural-tower" then
    msg.ag = planets.tower_info(e)
  end
  local ok_t, temperature = pcall(function() return e.temperature end)
  if ok_t and type(temperature) == "number" then
    msg.temp = math.floor(temperature + 0.5)
  end
  if kind == "combinator" then
    local ok2, cb = pcall(circuits.settings, e)
    msg.cb = ok2 and cb or nil
    local okd, desc = pcall(function() return e.combinator_description end)
    msg.desc = okd and desc or nil
  end
  if kind == "train" then
    local ok3, info = pcall(trains.train_info, e)
    msg.tr = ok3 and info or nil
  elseif kind == "stop" then
    local ok3, info = pcall(trains.stop_info, e)
    msg.stop = ok3 and info or nil
  end
  if kind == "container" or kind == "roboport" then
    local ok4, info = pcall(logistics.screen_info, e)
    msg.lg = ok4 and info or nil
  end
  msg.sig = circuits.signals(e)
  if kind ~= "combinator" then
    local ok5, cc = pcall(circuit_settings.info, e)
    msg.cc = ok5 and cc or nil
  end
  entity_ui.fill(msg, e, kind, list)
  space.fill(msg, e, kind)
  machine_info.fill(msg, e, kind, space, sc.sent % RECIPE_LIST_EVERY == 0)
  if kind == "crafter" and sc.sent % RECIPE_LIST_EVERY == 0 then
    msg.rl = recipe_names(c, e)
    -- The chooser's item group tabs: [group, group order, subgroup key, order] by recipe.
    msg.rg = {}
    for i, name in ipairs(msg.rl) do
      msg.rg[i] = machine_info.recipe_group(c.force.recipes[name])
    end
  end
  sc.sent = sc.sent + 1
  transport.send_now(msg)
end

-- Whether a screen opened from the remote view may stay open out of reach (radars cover it).
local function remote_ok(c, sc)
  return sc.remote and map.covered(sc.entity.surface, c.force, sc.entity.position)
end

-- The open screen's entity, if `cmd.u` names it and the character can still reach it. A screen
-- opened from the remote view out of reach takes settings but not items (`items`), as Factorio's.
local function open_entity(cmd, items)
  local s = storage.f3d
  local sc = s.screen
  local c = puppet.get()
  if not (sc and c and sc.entity.valid and tonumber(cmd.u) == sc.unit) then
    return nil
  end
  if not puppet.can_reach(c, sc.entity) then
    if not remote_ok(c, sc) then
      close(s, "Out of reach")
      return nil
    end
    if items then
      puppet.message("Out of reach")
      return nil
    end
  end
  sc.due = game.tick -- show the result on the next tick
  return c, sc.entity, kind_of(sc.entity)
end

local function count_arg(cmd)
  return math.max(1, math.min(MAX_MOVE, math.floor(tonumber(cmd.n) or 1)))
end

-- Gives items to the character; what doesn't fit is spilled at its feet, as the game does.
local function give(c, name, count, quality)
  local stack = { name = name, count = count }
  if type(quality) == "string" then
    stack.quality = quality
  end
  local inserted = count > 0 and c.insert(stack) or 0
  if inserted < count then
    stack.count = count - inserted
    pcall(function() c.surface.spill_item_stack({ position = c.position, stack = stack }) end)
  end
end

-- The open screen's inventory with that role, if `cmd.u` names the open entity and it is in reach.
function M.inventory(role, cmd)
  local c, e, kind = open_entity(cmd, true)
  if not e then
    return nil
  end
  for _, pair in ipairs(inventories(e, kind)) do
    if pair[1] == role then
      return pair[2]
    end
  end
  return nil
end

-- The open screen's entity, if `cmd.u` names it and it is in reach (inventory.lua's transfers).
function M.entity(cmd)
  local _, e = open_entity(cmd, true)
  return e
end

-- Sends the open screen on the next tick (after its contents changed).
function M.refresh()
  local sc = storage.f3d.screen
  if sc then
    sc.due = game.tick
  end
end

---------------------------------------------------------------------------------------------
-- Commands

function M.open(cmd)
  local s = storage.f3d
  local c = puppet.get()
  if not c then
    return
  end
  -- From the remote view (`rv`), on the surface the map shows (`si`).
  local surface = c.surface
  if cmd.rv and tonumber(cmd.si) then
    surface = game.get_surface(math.floor(tonumber(cmd.si))) or surface
  end
  local e = puppet.find_target(surface, cmd)
  if not (e and e.valid and e.unit_number) then
    return puppet.message("Nothing to open there")
  end
  -- A cargo bay opens its hub's or landing pad's window, as Factorio does (seen in 2.1.23); one on
  -- its own opens nothing.
  e = machine_info.bay_owner(e) or e
  if entity_ui.NO_WINDOW[e.type] then
    return -- 2.1.23 opens no window for these
  end
  if e.force ~= c.force then
    return puppet.message("That belongs to another force")
  end
  local remote = false
  if not puppet.can_reach(c, e) then
    if not (cmd.rv and map.covered(e.surface, c.force, e.position)) then
      return puppet.message(cmd.rv and "Not in radar or roboport coverage" or "Out of reach")
    end
    remote = true
  end
  local kind = kind_of(e)
  if kind == "other" and #inventories(e, kind) == 0 and not circuits.signals(e) and not entity_ui.openable(e) then
    return puppet.message("Nothing to open there")
  end
  s.screen = { entity = e, unit = e.unit_number, sent = 0, due = game.tick, remote = remote or nil }
end

function M.close()
  storage.f3d.screen = nil
end

-- {u, cb}: a combinator's new settings, in the shape `gui.cb` has.
function M.set_combinator(cmd)
  local _, e, kind = open_entity(cmd)
  if not e then
    return
  end
  if kind ~= "combinator" or type(cmd.cb) ~= "table" then
    return puppet.message("That isn't a combinator")
  end
  local ok, err = pcall(circuits.apply, e, cmd.cb)
  if not ok then
    puppet.message("Can't set that: " .. tostring(err))
  end
end

-- Train commands on the open rolling stock ({u, ...}, see trains.lua) or train stop. A space
-- platform hub's screen edits its platform's schedule with the same commands (`hub_fn`, space.lua).
local function train_command(kind_needed, fn, hub_fn)
  return function(cmd)
    local _, e, kind = open_entity(cmd)
    if not e then
      return
    end
    if kind == "hub" and hub_fn then
      local ok, err = pcall(hub_fn, e, cmd)
      if not ok then
        puppet.message("Can't change the schedule: " .. tostring(err))
      end
      return
    end
    if kind ~= kind_needed then
      return puppet.message(kind_needed == "stop" and "That isn't a train stop" or "That isn't a train")
    end
    fn(e, cmd)
  end
end

M.set_schedule = train_command("train", trains.set_schedule, space.set_schedule)
M.train_go = train_command("train", trains.go_to, space.go_to)
M.train_mode = train_command("train", trains.set_mode)
M.set_stop = train_command("stop", trains.set_stop)
M.set_interrupts = train_command("train", trains.set_interrupts, space.set_interrupts)
M.set_train_group = train_command("train", trains.set_group)
M.train_temp = train_command("train", trains.temp_stop)

-- Commands for space.lua's screens: kinds is a set of the kinds that take it.
function M.space_command(kinds, fn, refusal)
  return function(cmd)
    local _, e, kind = open_entity(cmd)
    if not e then
      return
    end
    if not kinds[kind] then
      return puppet.message(refusal)
    end
    local ok, err = pcall(fn, e, cmd)
    if not ok then
      puppet.message("Can't set that: " .. tostring(err))
    end
  end
end

-- Commands for entity_ui.lua's kinds, on the open screen.
local function kind_command(kind_needed, fn, refusal)
  return function(cmd)
    local _, e, kind = open_entity(cmd)
    if not e then
      return
    end
    if kind ~= kind_needed then
      return puppet.message(refusal)
    end
    local ok, err = pcall(fn, e, cmd)
    if not ok then
      puppet.message("Can't set that: " .. tostring(err))
    end
  end
end

-- Logistic chest commands on the open screen (see logistics.lua); the chest checks its own mode.
local function chest_command(fn)
  return function(cmd)
    local _, e = open_entity(cmd)
    if e then
      fn(e, cmd)
    end
  end
end

M.set_inserter = kind_command("inserter", entity_ui.set_inserter, "That isn't an inserter")
M.set_splitter = kind_command("splitter", entity_ui.set_splitter, "That isn't a splitter")
M.set_switch = kind_command("switch", entity_ui.set_switch, "That isn't a power switch")
M.set_panel = kind_command("panel", entity_ui.set_panel, "That isn't a display panel")

-- Settings that go by entity type rather than screen kind (a lamp or pump opens as "other").
local function type_command(types, fn, refusal)
  return function(cmd)
    local _, e = open_entity(cmd)
    if not e then
      return
    end
    if not types[e.type] then
      return puppet.message(refusal)
    end
    local ok, err = pcall(fn, e, cmd)
    if not ok then
      puppet.message("Can't set that: " .. tostring(err))
    end
  end
end

M.set_color = type_command({ lamp = true, ["train-stop"] = true, locomotive = true, ["spider-vehicle"] = true },
  entity_ui.set_color, "That has no colour to set")
M.set_vehicle = kind_command("vehicle", entity_ui.set_vehicle, "That isn't a vehicle")
M.set_artillery = type_command({ ["artillery-turret"] = true, ["artillery-wagon"] = true }, entity_ui.set_artillery, "That isn't artillery")
M.flush = type_command({ ["storage-tank"] = true, pipe = true, ["pipe-to-ground"] = true }, entity_ui.flush, "That holds no fluid to flush")
M.set_lamp = type_command({ lamp = true }, entity_ui.set_lamp, "That isn't a lamp")
M.set_desc = kind_command("combinator", entity_ui.set_desc, "That isn't a combinator")
M.set_speaker = type_command({ ["programmable-speaker"] = true }, entity_ui.set_speaker, "That isn't a programmable speaker")
M.set_pump = type_command({ pump = true }, entity_ui.set_pump, "That isn't a pump")
M.set_targets = kind_command("turret", entity_ui.set_targets, "That isn't a turret")

-- {u, f = {field = value}}: the open entity's circuit and logistic connection settings.
function M.set_circuit(cmd)
  local _, e, kind = open_entity(cmd)
  if not e then
    return
  end
  if kind == "combinator" then
    return puppet.message("Combinators are set with set_cb")
  end
  local ok, err = pcall(circuit_settings.apply, e, cmd.f)
  if not ok or err then
    puppet.message("Can't set that: " .. tostring(err))
  end
end

-- {u, n}: the open chest's limit bar.
function M.set_bar(cmd)
  local inventory = M.inventory("chest", cmd) or M.inventory("cargo", cmd)
  if not inventory then
    return
  end
  local ok = pcall(entity_ui.set_bar, inventory, cmd)
  if not ok then
    puppet.message("This chest has no limit")
  end
end

M.set_requests = chest_command(logistics.set_requests)
M.set_chest_logistics = chest_command(function(e, cmd)
  local ok = pcall(machine_info.set_chest_logistics, e, cmd)
  if not ok then
    puppet.message("That chest has no requests")
  end
end)
M.set_storage_filter = chest_command(logistics.set_storage_filter)

-- Sets an assembler's recipe ("" clears it). Items the machine gives back go to the character.
function M.set_recipe(cmd)
  local c, e, kind = open_entity(cmd)
  if not e then
    return
  end
  if kind ~= "crafter" then
    return puppet.message("This machine's recipe can't be changed")
  end
  local name = tostring(cmd.recipe or "")
  if name ~= "" and not can_make(e, c.force.recipes[name]) then
    return puppet.message("Can't make " .. name .. " here")
  end
  -- {u, recipe, q?}: the recipe's quality (Space Age), from the qualities the force has.
  local quality = type(cmd.q) == "string" and cmd.q ~= "" and cmd.q ~= "normal" and cmd.q or nil
  if quality and not c.force.is_quality_unlocked(quality) then
    return puppet.message("That quality isn't researched")
  end
  local ok, returned = pcall(function()
    if name == "" then
      return e.set_recipe()
    elseif quality then
      return e.set_recipe(name, quality)
    end
    return e.set_recipe(name)
  end)
  if not ok then
    return puppet.message("Can't set the recipe: " .. tostring(returned))
  end
  -- 2.x returns {{name, count, quality}, ...}; 1.1 returned {name = count}.
  for k, v in pairs(returned or {}) do
    if type(v) == "table" then
      give(c, v.name, v.count, v.quality)
    else
      give(c, k, v)
    end
  end
  puppet.send_inventory_now()
end

-- Takes up to n of an item out of the machine (from inventory `inv` if given) into the character.
function M.take(cmd)
  local c, e, kind = open_entity(cmd, true)
  if not e then
    return
  end
  local item = tostring(cmd.item or "")
  local want = count_arg(cmd)
  local moved, full = 0, false
  for _, pair in ipairs(inventories(e, kind)) do
    if cmd.inv == nil or cmd.inv == pair[1] then
      local inventory = pair[2]
      for _, entry in pairs(inventory.get_contents()) do
        if entry.name == item and moved < want and not full then
          local stack = { name = item, count = math.min(want - moved, entry.count), quality = entry.quality }
          local removed = inventory.remove(stack)
          if removed > 0 then
            stack.count = removed
            local inserted = c.insert(stack)
            if inserted < removed then
              stack.count = removed - inserted
              inventory.insert(stack)
              full = true
            end
            moved = moved + inserted
          end
        end
      end
    end
  end
  if full and moved == 0 then
    puppet.message("Inventory full")
  end
  puppet.send_inventory_now()
end

-- Puts up to n of an item from the character's main inventory into the machine, wherever the
-- game puts it (fuel into the fuel slot, ingredients into the input).
function M.put(cmd)
  local c, e = open_entity(cmd, true)
  if not e then
    return
  end
  local main = c.get_main_inventory()
  if not main then
    return
  end
  local item = tostring(cmd.item or "")
  local want = count_arg(cmd)
  local moved = 0
  for _, entry in pairs(main.get_contents()) do
    if entry.name == item and moved < want then
      local stack = { name = item, count = math.min(want - moved, entry.count), quality = entry.quality }
      local inserted = e.insert(stack)
      if inserted > 0 then
        stack.count = inserted
        main.remove(stack)
        moved = moved + inserted
      end
    end
  end
  if moved == 0 then
    puppet.message("Can't put " .. item .. " in there")
  end
  puppet.send_inventory_now()
end

---------------------------------------------------------------------------------------------

function M.tick()
  local s = storage.f3d
  local sc = s.screen
  if not sc or game.tick < sc.due then
    return
  end
  local c = puppet.get()
  if not (c and sc.entity.valid) then
    return close(s)
  end
  if not puppet.can_reach(c, sc.entity) and not remote_ok(c, sc) then
    return close(s, "Out of reach")
  end
  sc.due = game.tick + INTERVAL
  send_state(c, sc.entity, sc)
end

function M.reset()
  storage.f3d.screen = nil
end

return M
