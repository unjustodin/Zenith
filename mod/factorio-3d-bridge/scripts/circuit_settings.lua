-- The circuit (and logistic) connection settings of every entity that has them, as Factorio's
-- entity windows show them: enable/disable conditions, read modes, set recipe / filters / stack
-- size and the rest. Each LuaControlBehavior class has its own fields; FIELDS lists them by
-- defines.control_behavior.type name with how each is written on the wire, so one message shape
-- (`gui.cc`) and one command (`set_cc`) cover them all. Combinators (circuits.lua), train stops'
-- own fields (trains.lua) and display panel messages (entity_ui.lua) have their own.
--
-- Fields a game version lacks are skipped: each one is read inside pcall.

local M = {}

-- b: boolean (0/1 on the wire); s: SignalID ({type, name} or {}); c: circuit condition
-- ({first_signal?, comparator, constant? | second_signal?, ful: 0/1}); e:<define>: an enum from
-- defines.control_behavior.<define>, by name; n: CircuitNetworkSelection ({r, g}: 0/1).
local G = {
  { "circuit_enable_disable", "b" }, { "circuit_condition", "c" },
  { "connect_to_logistic_network", "b" }, { "logistic_condition", "c" },
}

local function with_g(list)
  local out = {}
  for _, f in ipairs(G) do
    out[#out + 1] = f
  end
  for _, f in ipairs(list) do
    out[#out + 1] = f
  end
  return out
end

local CRAFTER = {
  { "circuit_read_contents", "b" }, { "include_in_crafting", "b" }, { "circuit_read_ingredients", "b" },
  { "circuit_read_recipe_finished", "b" }, { "circuit_recipe_finished_signal", "s" },
  { "circuit_read_working", "b" }, { "circuit_working_signal", "s" }, { "read_fuel", "b" },
}
local ASSEMBLER = { { "circuit_set_recipe", "b" } }
for _, f in ipairs(CRAFTER) do
  ASSEMBLER[#ASSEMBLER + 1] = f
end
local CHEST = { { "read_contents", "b" }, { "read_empty_slots", "b" }, { "empty_slots_signal", "s" } }
local SIGNAL_COLOURS = {
  { "close_signal", "b" }, { "circuit_condition", "c" }, { "read_signal", "b" },
  { "red_signal", "s" }, { "orange_signal", "s" }, { "green_signal", "s" }, { "blue_signal", "s" },
}

M.FIELDS = {
  generic_on_off = G,
  land_mine = G,
  inserter = with_g({
    { "circuit_set_filters", "b" }, { "circuit_read_hand_contents", "b" }, { "circuit_hand_read_mode", "e:inserter.hand_read_mode" },
    { "circuit_set_stack_size", "b" }, { "circuit_stack_control_signal", "s" },
  }),
  transport_belt = with_g({ { "read_contents", "b" }, { "read_contents_mode", "e:transport_belt.content_read_mode" } }),
  assembling_machine = with_g(ASSEMBLER),
  furnace = with_g(CRAFTER),
  lamp = with_g({
    { "use_colors", "b" }, { "color_mode", "e:lamp.color_mode" }, { "red_signal", "s" }, { "green_signal", "s" },
    { "blue_signal", "s" }, { "rgb_signal", "s" },
  }),
  mining_drill = with_g({ { "circuit_read_resources", "b" }, { "resource_read_mode", "e:mining_drill.resource_read_mode" } }),
  pump = with_g({ { "set_filter", "b" } }),
  train_stop = with_g({}),
  turret = with_g({
    { "read_ammo", "b" }, { "set_priority_list", "b" }, { "set_ignore_unlisted_targets", "b" },
    { "ignore_unlisted_targets_condition", "c" },
  }),
  artillery_turret = with_g({ { "read_ammo", "b" } }),
  boiler = with_g({ { "read_fuel", "b" } }),
  loader = with_g({ { "circuit_set_filters", "b" }, { "circuit_read_transfers", "b" } }),
  agricultural_tower = with_g({
    { "read_contents", "b" }, { "enable_planting_condition", "b" }, { "planting_condition", "c" },
    { "enable_harvesting_condition", "b" }, { "harvesting_condition", "c" },
  }),
  asteroid_collector = with_g({ { "set_filter", "b" }, { "read_content", "b" }, { "include_hands", "b" } }),
  rail_signal = SIGNAL_COLOURS,
  rail_chain_signal = SIGNAL_COLOURS,
  container = CHEST,
  proxy_container = CHEST,
  logistic_container = {
    { "read_contents", "b" }, { "set_requests", "b" }, { "circuit_condition_enabled", "b" }, { "circuit_condition", "c" },
    { "read_empty_slots", "b" }, { "empty_slots_signal", "s" },
  },
  roboport = {
    { "read_logistics", "b" }, { "read_items_mode", "e:roboport.read_items_mode" }, { "read_robot_stats", "b" },
    { "available_logistic_output_signal", "s" }, { "total_logistic_output_signal", "s" },
    { "available_construction_output_signal", "s" }, { "total_construction_output_signal", "s" },
    { "roboport_count_output_signal", "s" },
  },
  accumulator = { { "read_charge", "b" }, { "output_signal", "s" } },
  wall = { { "open_gate", "b" }, { "circuit_condition", "c" }, { "read_sensor", "b" }, { "output_signal", "s" } },
  programmable_speaker = { { "circuit_condition", "c" } },
  reactor = { { "read_fuel", "b" }, { "read_temperature", "b" }, { "temperature_signal", "s" } },
  heat_pipe = { { "read_temperature", "b" }, { "temperature_signal", "s" } },
  single_fluid_box = {
    { "circuit_exclusive_mode_of_operation", "e:single_fluid_box.exclusive_mode" }, { "read_temperature", "b" },
    { "temperature_signal", "s" },
  },
  radar = { { "mode", "e:radar.mode" }, { "universe_channel", "s" } },
  lab = {
    { "read_contents", "b" }, { "read_fuel", "b" }, { "read_research_cost", "b" }, { "read_technology_level", "b" },
    { "technology_level_signal", "s" }, { "set_research", "b" },
  },
  splitter = {
    { "set_input_side", "b" }, { "input_left_condition", "c" }, { "input_right_condition", "c" },
    { "set_output_side", "b" }, { "output_left_condition", "c" }, { "output_right_condition", "c" },
    { "set_filter", "b" },
  },
  rocket_silo = { { "read_mode", "e:rocket_silo.read_mode" }, { "read_launched", "b" }, { "launched_signal", "s" } },
  -- A landing pad also takes its requests from the circuit network.
  cargo_landing_pad = { { "read_contents", "b" }, { "set_requests", "b" }, { "read_empty_slots", "b" }, { "empty_slots_signal", "s" } },
  space_platform_hub = {
    { "read_contents", "b" }, { "set_requests", "b" }, { "send_to_platform", "b" }, { "read_moving_from", "b" },
    { "read_moving_to", "b" }, { "read_speed", "b" }, { "speed_signal", "s" }, { "read_damage_taken", "b" },
    { "damage_taken_signal", "s" }, { "read_empty_slots", "b" }, { "empty_slots_signal", "s" },
  },
}
-- Behaviour types that have their own windows (combinators in circuits.lua, display panels in
-- entity_ui.lua).
local OWN = { arithmetic_combinator = true, decider_combinator = true, selector_combinator = true,
  constant_combinator = true, display_panel = true }

local type_names
local function type_name(behavior)
  if not type_names then
    type_names = {}
    for name, value in pairs(defines.control_behavior.type) do
      type_names[value] = name
    end
  end
  return type_names[behavior.type]
end

-- defines.control_behavior.<path> as {name -> value} and {value -> name}.
local enums = {}
local function enum(path)
  if not enums[path] then
    local t = defines.control_behavior
    for part in path:gmatch("[^.]+") do
      t = t and t[part]
    end
    local by_value = {}
    for name, value in pairs(t or {}) do
      by_value[value] = name
    end
    enums[path] = { names = t or {}, values = by_value }
  end
  return enums[path]
end

-- SignalID -> {type, name} (item signals read with a nil type), {} when unset.
function M.signal_out(s)
  if type(s) ~= "table" or not s.name then
    return {}
  end
  local out = { type = s.type or "item", name = s.name }
  if s.quality and s.quality ~= "normal" then
    out.quality = type(s.quality) == "table" and s.quality.name or s.quality
  end
  return out
end

function M.signal_in(v)
  if type(v) ~= "table" or type(v.name) ~= "string" or v.name == "" then
    return nil
  end
  local s = { type = type(v.type) == "string" and v.type or "item", name = v.name }
  if type(v.quality) == "string" and v.quality ~= "" then
    s.quality = v.quality
  end
  return s
end

-- 2.x reads a CircuitConditionDefinition (1.1 wrapped it as {condition, fulfilled}).
function M.condition_out(c)
  if type(c) ~= "table" then
    return { comparator = "<", constant = 0 }
  end
  local fulfilled = c.fulfilled
  if type(c.condition) == "table" then
    c = c.condition
  end
  local out = { comparator = c.comparator or "<" }
  if c.first_signal and c.first_signal.name then
    out.first_signal = M.signal_out(c.first_signal)
  end
  if c.second_signal and c.second_signal.name then
    out.second_signal = M.signal_out(c.second_signal)
  else
    out.constant = math.floor(tonumber(c.constant) or 0)
  end
  if fulfilled ~= nil then
    out.ful = fulfilled and 1 or 0
  end
  return out
end

local COMPARATORS = { ["<"] = true, [">"] = true, ["="] = true, ["≥"] = true, ["≤"] = true, ["≠"] = true,
  [">="] = true, ["<="] = true, ["!="] = true }

function M.condition_in(v)
  if type(v) ~= "table" then
    return { comparator = "<", constant = 0 }
  end
  local c = { comparator = COMPARATORS[v.comparator] and v.comparator or "<" }
  c.first_signal = M.signal_in(v.first_signal)
  c.second_signal = M.signal_in(v.second_signal)
  if not c.second_signal then
    c.constant = math.floor(tonumber(v.constant) or 0)
  end
  return c
end

local function value_out(kind, v)
  if kind == "b" then
    return v and 1 or 0
  elseif kind == "s" then
    return M.signal_out(v)
  elseif kind == "c" then
    return M.condition_out(v)
  elseif kind == "n" then
    return { r = (type(v) ~= "table" or v.red ~= false) and 1 or 0, g = (type(v) ~= "table" or v.green ~= false) and 1 or 0 }
  end
  return enum(kind:sub(3)).values[v]
end

-- The value to write, or nil to leave the field alone (a bad value).
local function value_in(kind, v)
  if kind == "b" then
    if v == 1 or v == true then
      return true
    elseif v == 0 or v == false then
      return false
    end
    return nil
  elseif kind == "s" then
    return M.signal_in(v) or false -- false: clear it
  elseif kind == "c" then
    return M.condition_in(v)
  elseif kind == "n" then
    return type(v) == "table" and { red = v.r ~= 0, green = v.g ~= 0 } or nil
  end
  return type(v) == "string" and enum(kind:sub(3)).names[v] or nil
end

-- Which connectors read the circuit: a combinator's input side, everything else its own.
local function network_id(e, id)
  local ok, net = pcall(function() return e.get_circuit_network(id) end)
  return ok and net and net.network_id or 0
end

-- The entity's red and green network ids (0: not on one), and its output side's for combinators.
function M.networks(e)
  local ids = defines.wire_connector_id
  local r, g = network_id(e, ids.circuit_red), network_id(e, ids.circuit_green)
  return r, g
end

local function in_logistic_network(e)
  local ok, net = pcall(function() return e.surface.find_logistic_network_by_position(e.position, e.force) end)
  return ok and net ~= nil
end

-- `gui.cc`: {o (behaviour type), w (0/1: on a circuit network), ln (0/1: inside a logistic
-- network), nets = {r, g} (network ids, 0 none), f = {field = value}}, or nil when the entity
-- has no circuit connection of this kind. Factorio makes the behaviour when its window opens;
-- this does the same (from on_tick, so every peer does it).
function M.info(e)
  local ok, b = pcall(function() return e.get_control_behavior() or e.get_or_create_control_behavior() end)
  if not (ok and b) then
    return nil
  end
  local name = type_name(b)
  local fields = name and M.FIELDS[name]
  if not fields or OWN[name] then
    return nil
  end
  local r, g = M.networks(e)
  local out = { o = name, w = (r ~= 0 or g ~= 0) and 1 or 0, nets = { r = r, g = g }, f = {} }
  for _, f in ipairs(fields) do
    local okv, v = pcall(function() return b[f[1]] end)
    if okv then
      local okc, wire = pcall(value_out, f[2], v)
      if okc and wire ~= nil then
        out.f[f[1]] = wire
      end
    end
  end
  if out.f.connect_to_logistic_network ~= nil then
    out.ln = in_logistic_network(e) and 1 or 0
  end
  return out
end

-- {u, f = {field = value}} on the open screen: writes the fields its behaviour type has; the
-- rest are ignored. Returns the first error, if any.
function M.apply(e, f)
  local b = e.get_or_create_control_behavior()
  local name = b and type_name(b)
  local fields = name and M.FIELDS[name]
  if not fields or OWN[name] or type(f) ~= "table" then
    return "No circuit settings here"
  end
  local first_err
  for _, spec in ipairs(fields) do
    if f[spec[1]] ~= nil then
      local v = value_in(spec[2], f[spec[1]])
      if v ~= nil then
        if v == false and spec[2] == "s" then
          v = nil
        end
        local ok, err = pcall(function() b[spec[1]] = v end)
        if not ok and not first_err then
          first_err = err
        end
      end
    end
  end
  return first_err
end

return M
