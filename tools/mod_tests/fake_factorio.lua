-- A small stand-in for the Factorio runtime API: just enough of it to run the bridge mod's
-- control.lua outside the game. Like the real API, reading a key an object doesn't have is an
-- error, so typos and wrong-type property reads fail the tests instead of passing silently.
--
-- The harness (test_bridge.py) drives it through the global table F.

F = {
  sent = {},          -- {port, data} for every send_udp call
  registered = setmetatable({}, { __mode = "k" }), -- entity -> register_on_object_destroyed number
  next_registration = 0,
  destroyed_queue = {}, -- registration numbers of destroyed entities, raised at the next tick
  spilled = {},       -- stacks spilled on the ground
  inventory_space = math.huge, -- items the character can still take when it mines something
  inventories = setmetatable({}, { __mode = "k" }), -- entity -> {role -> inventory}, for the harness
  slots = setmetatable({}, { __mode = "k" }), -- character -> {guns = slots, ammo = slots}, for the harness
  signals = setmetatable({}, { __mode = "k" }), -- entity -> {connector id -> {{signal = {type, name}, count}, ...}}
  networks = setmetatable({}, { __mode = "k" }), -- entity -> {connector id -> LuaCircuitNetwork-like {network_id}}
  stop_trains = setmetatable({}, { __mode = "k" }), -- train stop -> {LuaTrain-like, ...} (get_train_stop_trains)
  decon_marks = setmetatable({}, { __mode = "k" }), -- entity -> true when marked for deconstruction
  upgrade_marks = setmetatable({}, { __mode = "k" }), -- entity -> target prototype
  blueprint = {}, -- what the blueprint item holds: {{name, x, y}, ...} relative to its centre
  upgrades = {}, -- what the upgrade planner maps: entity name -> entity name
  game_blueprints = {}, -- game.blueprints: LuaRecords (F.make_record)
  player_blueprints = {}, -- an offline player's library (make_offline_player)
  fluid_setters = setmetatable({}, { __mode = "k" }), -- entity -> function(box, fluid, capacity)
  connectors = setmetatable({}, { __mode = "k" }), -- entity -> function(wire type) -> its connector
  printed = {},
  multiplayer = true,
  next_unit = 100,
  handlers = {},
  commands = {}, -- console command name -> handler
  profilers = 0, -- how many profilers the mod made
  train_data = setmetatable({}, { __mode = "k" }), -- LuaTrain -> its fields, for the harness to change
  train_setters = setmetatable({}, { __mode = "k" }), -- carriage -> function(train)
  next_train = 0,
  network = nil, -- the logistic network every entity and position is in (F.make_network), or nil
  charted = {}, -- "cx,cy" -> true for chunks the player force has charted
  chart_requests = {}, -- areas passed to force.chart
  tags = {}, -- the player force's chart tags
  tag_number = 0,
  on_init = nil,
  players = {}, -- game.players: index -> LuaPlayer (F.make_offline_player)
  players_by = {}, -- index and name -> LuaPlayer
  game_surfaces = {}, -- game.surfaces: index -> LuaSurface
  trains = {}, -- id -> LuaTrain, for game.train_manager
  segments = setmetatable({}, { __mode = "k" }), -- entity -> {fluid, capacity}: its pipeline (fluid segment)
  by_unit = setmetatable({}, { __mode = "v" }), -- unit number -> vehicle, for game.get_entity_by_unit_number
  capsules = {}, -- capsules used: {name, x, y}
}

local function strict(name, t)
  return setmetatable(t, {
    __index = function(_, k)
      error(name .. " doesn't contain key " .. tostring(k), 2)
    end,
  })
end

---------------------------------------------------------------------------------------------
-- defines

local event_names = {
  "on_tick", "on_udp_packet_received", "on_built_entity", "on_robot_built_entity",
  "on_space_platform_built_entity", "script_raised_built", "script_raised_revive",
  "on_entity_cloned", "on_player_mined_entity", "on_robot_mined_entity",
  "on_space_platform_mined_entity", "on_entity_died", "on_post_entity_died", "script_raised_destroy",
  "on_resource_depleted", "on_player_rotated_entity", "on_player_flipped_entity",
  "on_player_built_tile", "on_robot_built_tile", "on_space_platform_built_tile",
  "on_player_mined_tile", "on_robot_mined_tile", "on_space_platform_mined_tile",
  "script_raised_set_tiles", "on_chunk_generated", "on_entity_damaged", "on_research_finished",
  "on_research_reversed", "on_marked_for_deconstruction", "on_cancelled_deconstruction",
  "on_marked_for_upgrade", "on_cancelled_upgrade", "on_chart_tag_added", "on_chart_tag_modified",
  "on_chart_tag_removed", "on_entity_renamed", "on_console_chat", "on_rocket_launch_ordered",
  "on_space_platform_changed_state", "on_tower_planted_seed", "on_tower_pre_mined_plant",
  "on_player_joined_game", "on_player_left_game", "on_player_respawned", "on_runtime_mod_setting_changed",
  "on_object_destroyed",
}
local events = {}
for i, n in ipairs(event_names) do
  events[n] = i
end

defines = strict("defines", {
  events = strict("defines.events", events),
  direction = strict("defines.direction", {
    north = 0, northnortheast = 1, northeast = 2, eastnortheast = 3, east = 4, eastsoutheast = 5,
    southeast = 6, southsoutheast = 7, south = 8, southsouthwest = 9, southwest = 10,
    westsouthwest = 11, west = 12, westnorthwest = 13, northwest = 14, northnorthwest = 15,
  }),
  -- Only the ones the mod reads; 2.1.23's attack is 1 (seen on units' distraction_command).
  command = strict("defines.command", { attack = 1, go_to_location = 2, wander = 6, stop = 8 }),
  entity_status = strict("defines.entity_status", { working = 1, no_power = 2, no_ingredients = 3, low_power = 4, no_research_in_progress = 5, missing_science_packs = 6, not_plugged_in_electric_network = 7,
    no_fuel = 8, full_output = 9, no_ammo = 10, charging = 11, discharging = 12, fully_charged = 13,
    disabled_by_control_behavior = 14 }),
  signal_state = strict("defines.signal_state", { open = 0, closed = 1, reserved = 2, reserved_by_circuit_network = 3 }),
  chain_signal_state = strict("defines.chain_signal_state", { none = 0, all_open = 1, partially_open = 2, none_open = 3 }),
  wire_type = strict("defines.wire_type", { red = 1, green = 2, copper = 3 }),
  -- A combinator's input connectors share the ids of everything else's red and green ones.
  wire_connector_id = strict("defines.wire_connector_id", { circuit_red = 1, circuit_green = 2, combinator_input_red = 1,
    combinator_input_green = 2, combinator_output_red = 3, combinator_output_green = 4, pole_copper = 5,
    power_switch_left_copper = 5, power_switch_right_copper = 6 }),
  wire_origin = strict("defines.wire_origin", { player = 0, script = 1, radars = 2 }),
  control_behavior = strict("defines.control_behavior", {
    type = strict("defines.control_behavior.type", { generic_on_off = 0, inserter = 1, lamp = 2, constant_combinator = 3,
      arithmetic_combinator = 4, train_stop = 5 }),
    inserter = strict("defines.control_behavior.inserter", {
      hand_read_mode = strict("defines.control_behavior.inserter.hand_read_mode", { hold = 0, pulse = 1 }),
    }),
    lamp = strict("defines.control_behavior.lamp", {
      color_mode = strict("defines.control_behavior.lamp.color_mode", { color_mapping = 0, components = 1, packed_rgb = 2 }),
    }),
  }),
  build_check_type = strict("defines.build_check_type", { script = 0, manual = 1, manual_ghost = 2 }),
  build_mode = strict("defines.build_mode", { normal = 0, forced = 1, superforced = 2 }),
  logistic_member_index = strict("defines.logistic_member_index", { logistic_container = 0, logistic_container_trash_provider = 1 }),
  flow_precision_index = strict("defines.flow_precision_index", {
    five_seconds = 0, one_minute = 1, ten_minutes = 2, one_hour = 3, ten_hours = 4, fifty_hours = 5,
    two_hundred_fifty_hours = 6, one_thousand_hours = 7,
  }),
  shooting = strict("defines.shooting", { not_shooting = 0, shooting_enemies = 1, shooting_selected = 2 }),
  riding = strict("defines.riding", {
    acceleration = strict("defines.riding.acceleration", { nothing = 0, accelerating = 1, braking = 2, reversing = 3 }),
    direction = strict("defines.riding.direction", { left = 0, straight = 1, right = 2 }),
  }),
  controllers = strict("defines.controllers", { ghost = 0, character = 1, god = 2, editor = 4, spectator = 5, cutscene = 6, remote = 7 }),
  -- 2.0 names. The harness swaps assembling_machine_input for crafter_input to check the fallback.
  inventory = strict("defines.inventory", {
    chest = 1, furnace_source = 2, assembling_machine_input = 2, lab_input = 2, character_guns = 3, character_ammo = 4,
    cargo_wagon = 5, logistic_container_trash = 6, roboport_robot = 7, roboport_material = 8, robot_cargo = 9, turret_ammo = 10,
    character_main = 11, character_armor = 12, character_trash = 13, item_main = 20,
    -- Space Age (space.lua): the hub's, the landing pad's and the silo's.
    hub_main = 14, hub_trash = 15, cargo_landing_pad_main = 16, cargo_landing_pad_trash = 17,
    rocket_silo_rocket = 18, rocket_silo_trash = 19,
    -- Turrets' and vehicles' ammo (turrets.lua).
    car_ammo = 21, spider_ammo = 22, artillery_turret_ammo = 23, artillery_wagon_ammo = 24,
    -- Module slots (modules.lua): 2.1's crafter_modules is 4 in the game.
    crafter_modules = 25, lab_modules = 26, mining_drill_modules = 27, beacon_modules = 28,
  }),
  rocket_silo_status = strict("defines.rocket_silo_status", {
    building_rocket = 0, create_rocket = 1, lights_blinking_open = 2, doors_opening = 3, doors_opened = 4,
    rocket_rising = 5, arms_advance = 6, rocket_ready = 7, launch_starting = 8, engine_starting = 9, arms_retract = 10,
    rocket_flying = 11, lights_blinking_close = 12, doors_closing = 13, launch_started = 14,
  }),
  -- 2.1's train states (no path_lost or destination_full any more).
  train_state = strict("defines.train_state", {
    on_the_path = 0, no_schedule = 1, no_path = 2, arrive_signal = 3, wait_signal = 4, arrive_station = 5,
    manual_control_stop = 6, manual_control = 7, wait_station = 8, destination_full = 9,
  }),
  -- As 2.1.23 numbers them.
  cargo_destination = strict("defines.cargo_destination", { invalid = 0, orbit = 1, station = 2, surface = 3, space_platform = 4 }),
  space_platform_state = strict("defines.space_platform_state", {
    waiting_for_starter_pack = 0, starter_pack_on_the_way = 1, on_the_path = 2, waiting_for_departure = 3,
    no_schedule = 4, no_path = 5, waiting_at_station = 6, paused = 7, starter_pack_requested = 8,
  }),
})

---------------------------------------------------------------------------------------------
-- script, commands, settings, log

script = strict("LuaBootstrap", {
  active_mods = { ["factorio-3d-bridge"] = "0.1.0", base = "2.1.23" },
  on_init = function(f) F.on_init = f end,
  on_configuration_changed = function(f) F.on_config = f end,
  on_load = function(f) F.on_load = f end,
  on_event = function(ids, f)
    if type(ids) ~= "table" then
      ids = { ids }
    end
    for i = 1, #ids do
      -- A custom input's name (data.lua) is an event too.
      if type(ids[i]) ~= "number" and not (type(ids[i]) == "string" and ids[i]:sub(1, 4) == "f3d-") then
        error("on_event: bad event id at " .. i)
      end
      F.handlers[ids[i]] = f
    end
  end,
  get_event_handler = function(id)
    assert(type(id) == "number", "get_event_handler(event id)")
    return F.handlers[id]
  end,
  -- The same number each time the same entity is registered (as in 2.1.23); on_object_destroyed
  -- names it when the entity goes.
  register_on_object_destroyed = function(e)
    assert(type(e) == "table" and e.valid, "register_on_object_destroyed(valid object)")
    local n = F.registered[e]
    if not n then
      F.next_registration = F.next_registration + 1
      n = F.next_registration
      F.registered[e] = n
    end
    return n, e.unit_number or 0, 1
  end,
})

commands = strict("LuaCommandProcessor", {
  add_command = function(name, help, f)
    F.commands[name] = f
    if name == "f3d-status" then
      F.command = f
    end
  end,
})

settings = strict("LuaSettings", {
  global = {
    ["f3d-surface"] = { value = "nauvis" },
    ["f3d-chunks-per-tick"] = { value = 1 },
    ["f3d-bytes-per-tick"] = { value = 32768 },
    ["f3d-max-focus-radius"] = { value = 64 },
    ["f3d-mover-interval"] = { value = 2 },
    ["f3d-detail-radius"] = { value = 24 },
    ["f3d-detail-interval"] = { value = 6 },
    ["f3d-starter-kit"] = { value = true },
    ["f3d-player"] = { value = "" },
  },
})

function log(msg)
  F.printed[#F.printed + 1] = "LOG " .. tostring(msg)
end

function print(msg)
  F.printed[#F.printed + 1] = "STDOUT " .. tostring(msg)
end

-- remote.add_interface: the `zenith` interface (console.lua); F.remote[name][fn] calls it.
F.remote = {}
remote = strict("LuaRemote", {
  add_interface = function(name, functions)
    assert(type(name) == "string" and type(functions) == "table", "add_interface(name, functions)")
    assert(not F.remote[name], "add_interface: interface " .. name .. " already exists")
    F.remote[name] = functions
  end,
})

rcon = strict("LuaRCON", {
  print = function(msg) F.printed[#F.printed + 1] = "RCON " .. tostring(msg) end,
})

storage = {}

---------------------------------------------------------------------------------------------
-- prototypes

local function box(w, h)
  return { left_top = { x = -w / 2, y = -h / 2 }, right_bottom = { x = w / 2, y = h / 2 } }
end

local function entity_proto(name, type, w, h, extra)
  local p = {
    name = name, type = type, selection_box = box(w, h), collision_box = box(w - 0.2, h - 0.2),
    map_color = { r = 0.5, g = 0.5, b = 0.5, a = 1 }, friendly_map_color = { r = 0.2, g = 0.6, b = 0.9, a = 1 },
    tile_width = math.ceil(w), tile_height = math.ceil(h),
    mineable_properties = { minable = true, mining_time = 0.5, products = { { type = "item", name = name, amount = 1 } } },
    infinite_resource = false, mining_speed = nil, crafting_categories = nil,
    unit_numbered = true, rotatable = false, build_grid_size = 1,
    items_to_place_this = { { name = name, count = 1 } },
  }
  for k, v in pairs(extra or {}) do
    p[k] = v
  end
  return p
end

local entity_protos = {
  character = entity_proto("character", "character", 0.4, 0.4, { mining_speed = 0.5, crafting_categories = { crafting = true } }),
  ["transport-belt"] = entity_proto("transport-belt", "transport-belt", 1, 1, { rotatable = true, fast_replaceable_group = "transport-belt" }),
  ["fast-transport-belt"] = entity_proto("fast-transport-belt", "transport-belt", 1, 1, { rotatable = true, fast_replaceable_group = "transport-belt" }),
  ["straight-rail"] = entity_proto("straight-rail", "straight-rail", 2, 2, { rotatable = true, build_grid_size = 2 }),
  ["underground-belt"] = entity_proto("underground-belt", "underground-belt", 1, 1, { rotatable = true, max_underground_distance = 5 }),
  ["assembling-machine-1"] = entity_proto("assembling-machine-1", "assembling-machine", 3, 3, {
    crafting_categories = { crafting = true, ["basic-crafting"] = true, ["advanced-crafting"] = true },
  }),
  ["stone-furnace"] = entity_proto("stone-furnace", "furnace", 2, 2, { crafting_categories = { smelting = true } }),
  ["wooden-chest"] = entity_proto("wooden-chest", "container", 1, 1),
  lab = entity_proto("lab", "lab", 3, 3, { lab_inputs = { "automation-science-pack", "logistic-science-pack" } }),
  inserter = entity_proto("inserter", "inserter", 1, 1, { rotatable = true,
    inserter_pickup_position = { x = 0, y = -1 }, inserter_drop_position = { x = 0, y = 1.2 } }),
  ["fast-inserter"] = entity_proto("fast-inserter", "inserter", 1, 1, { rotatable = true, bulk = false, filter_count = 5,
    inserter_pickup_position = { 0, -1 }, inserter_drop_position = { 0, 1.2 } }),
  -- 2.x lists each pipe connection's position for all four directions (north first).
  ["offshore-pump"] = entity_proto("offshore-pump", "offshore-pump", 1, 2, { rotatable = true,
    fluidbox_prototypes = { { pipe_connections = { { connection_type = "normal", flow_direction = "output", direction = 0,
      positions = { { x = 0, y = -0.5 }, { x = 0.5, y = 0 }, { x = 0, y = 0.5 }, { x = -0.5, y = 0 } } } } } } }),
  splitter = entity_proto("splitter", "splitter", 2, 1, { rotatable = true }),
  ["power-switch"] = entity_proto("power-switch", "power-switch", 2, 2),
  ["gun-turret"] = entity_proto("gun-turret", "ammo-turret", 2, 2),
  ["small-lamp"] = entity_proto("small-lamp", "lamp", 1, 1),
  pipe = entity_proto("pipe", "pipe", 1, 1),
  ["arithmetic-combinator"] = entity_proto("arithmetic-combinator", "arithmetic-combinator", 1, 2, { rotatable = true }),
  ["constant-combinator"] = entity_proto("constant-combinator", "constant-combinator", 1, 1, { rotatable = true }),
  ["entity-ghost"] = entity_proto("entity-ghost", "entity-ghost", 1, 1),
  ["tile-ghost"] = entity_proto("tile-ghost", "tile-ghost", 1, 1),
  -- The rail planner's pieces (2.x) and the elevated rails' supports.
  ["half-diagonal-rail"] = entity_proto("half-diagonal-rail", "half-diagonal-rail", 2, 2, { rotatable = true }),
  ["curved-rail-a"] = entity_proto("curved-rail-a", "curved-rail-a", 2, 2, { rotatable = true }),
  ["elevated-straight-rail"] = entity_proto("elevated-straight-rail", "elevated-straight-rail", 2, 2, { rotatable = true }),
  ["rail-support"] = entity_proto("rail-support", "rail-support", 2, 2, { rotatable = true }),
  -- 2.x reads the supply area and wire reach through methods (they depend on quality).
  ["small-electric-pole"] = entity_proto("small-electric-pole", "electric-pole", 1, 1, {
    get_max_wire_distance = function() return 7.5 end, get_supply_area_distance = function() return 2.5 end,
  }),
  ["gun-turret"] = entity_proto("gun-turret", "ammo-turret", 2, 2, { attack_parameters = { range = 18 } }),
  roboport = entity_proto("roboport", "roboport", 4, 4, { logistic_radius = 25, construction_radius = 55 }),
  ["rail-signal"] = entity_proto("rail-signal", "rail-signal", 1, 1, { rotatable = true }),
  ["rail-chain-signal"] = entity_proto("rail-chain-signal", "rail-chain-signal", 1, 1, { rotatable = true }),
  accumulator = entity_proto("accumulator", "accumulator", 2, 2),
  ["construction-robot"] = entity_proto("construction-robot", "construction-robot", 0.5, 0.5),
  ["tree-01"] = entity_proto("tree-01", "tree", 1, 1, {
    unit_numbered = false,
    mineable_properties = { minable = true, mining_time = 0.3, products = { { type = "item", name = "wood", amount = 4 } } },
  }),
  ["iron-ore"] = entity_proto("iron-ore", "resource", 1, 1, {
    unit_numbered = false,
    mineable_properties = { minable = true, mining_time = 1, products = { { type = "item", name = "iron-ore", amount = 1 } } },
  }),
  ["small-biter"] = entity_proto("small-biter", "unit", 0.5, 0.5, { attack_parameters = { range = 0.5 } }),
  -- What weapons fire: none of these has a unit_number.
  ["shotgun-pellet"] = entity_proto("shotgun-pellet", "projectile", 0.2, 0.5, { unit_numbered = false }),
  ["rocket"] = entity_proto("rocket", "projectile", 0.2, 0.5, { unit_numbered = false }),
  ["handheld-flamethrower-fire-stream"] = entity_proto("handheld-flamethrower-fire-stream", "stream", 0, 0, { unit_numbered = false }),
  ["chain-tesla-gun-beam-start"] = entity_proto("chain-tesla-gun-beam-start", "beam", 0, 0, { unit_numbered = false }),
  ["grenade-explosion"] = entity_proto("grenade-explosion", "explosion", 0, 0, { unit_numbered = false }),
  ["fire-flame"] = entity_proto("fire-flame", "fire", 0, 0, { unit_numbered = false }),
  ["poison-cloud"] = entity_proto("poison-cloud", "smoke-with-trigger", 0, 0, { unit_numbered = false }),
  ["small-spitter"] = entity_proto("small-spitter", "unit", 0.5, 0.5, { attack_parameters = { range = 13 } }),
  ["small-worm-turret"] = entity_proto("small-worm-turret", "turret", 1.4, 1.4),
  car = entity_proto("car", "car", 2, 3),
  locomotive = entity_proto("locomotive", "locomotive", 2, 6),
  explosion = entity_proto("explosion", "explosion", 1, 1),
  ["item-on-ground"] = entity_proto("item-on-ground", "item-entity", 0.3, 0.3, { unit_numbered = false }),
  ["stone-wall"] = entity_proto("stone-wall", "wall", 1, 1),
  ["cargo-wagon"] = entity_proto("cargo-wagon", "cargo-wagon", 2, 6),
  radar = entity_proto("radar", "radar", 3, 3, { max_distance_of_nearby_sector_revealed = 3 }),
  spidertron = entity_proto("spidertron", "spider-vehicle", 3, 3),
  ["artillery-turret"] = entity_proto("artillery-turret", "artillery-turret", 3, 3),
  ["laser-turret"] = entity_proto("laser-turret", "electric-turret", 2, 2),
  ["flamethrower-turret"] = entity_proto("flamethrower-turret", "fluid-turret", 2, 3),
  tank = entity_proto("tank", "car", 3, 4),
  ["storage-tank"] = entity_proto("storage-tank", "storage-tank", 3, 3),
  ["heat-pipe"] = entity_proto("heat-pipe", "heat-pipe", 1, 1),
  ["requester-chest"] = entity_proto("requester-chest", "logistic-container", 1, 1, { logistic_mode = "requester" }),
  ["storage-chest"] = entity_proto("storage-chest", "logistic-container", 1, 1, { logistic_mode = "storage" }),
  ["logistic-robot"] = entity_proto("logistic-robot", "logistic-robot", 0.5, 0.5),
  -- Space Age: Vulcanus, Fulgora, Gleba, Aquilo, travel.
  ["small-demolisher"] = entity_proto("small-demolisher", "segmented-unit", 6, 6),
  ["small-demolisher-segment"] = entity_proto("small-demolisher-segment", "segment", 5, 5, { unit_numbered = false }),
  -- A lightning entity stands where its bolt starts: source_offset above where it strikes, give
  -- or take half of source_variance (Fulgora's values, as 2.1.23 reads them).
  lightning = entity_proto("lightning", "lightning", 1, 1, { unit_numbered = false,
    source_offset = { 0, -25 }, source_variance = { 30, 6 } }),
  ["lightning-rod"] = entity_proto("lightning-rod", "lightning-attractor", 1, 1),
  ["yumako-tree"] = entity_proto("yumako-tree", "plant", 1, 1, { growth_ticks = 600 }),
  ["agricultural-tower"] = entity_proto("agricultural-tower", "agricultural-tower", 3, 3),
  -- A pentapod's five legs are spider-leg entities standing on its feet, made right after the
  -- body (so with the next unit numbers, as in 2.1.23); it has no get_spider_legs.
  ["small-stomper-pentapod"] = entity_proto("small-stomper-pentapod", "spider-unit", 2, 2, { spider_engine = { legs = {
    { leg = "small-stomper-pentapod-leg", ground_position = { -3.7, -5.1 } }, { leg = "small-stomper-pentapod-leg", ground_position = { -6, 1.9 } },
    { leg = "small-stomper-pentapod-leg", ground_position = { 0, 6.3 } }, { leg = "small-stomper-pentapod-leg", ground_position = { 6, 1.9 } },
    { leg = "small-stomper-pentapod-leg", ground_position = { 3.7, -5.1 } },
  } } }),
  ["small-stomper-pentapod-leg"] = entity_proto("small-stomper-pentapod-leg", "spider-leg", 0.5, 0.5),
  ["gleba-spawner"] = entity_proto("gleba-spawner", "unit-spawner", 5, 5),
  ["heating-tower"] = entity_proto("heating-tower", "reactor", 3, 3, { heating_radius = 12 }),
  ["cargo-pod"] = entity_proto("cargo-pod", "cargo-pod", 2, 2),
  ["train-stop"] = entity_proto("train-stop", "train-stop", 2, 2, { rotatable = true }),
  cliff = entity_proto("cliff", "cliff", 3, 3, { unit_numbered = false }),
  ["space-platform-hub"] = entity_proto("space-platform-hub", "space-platform-hub", 8, 8),
  -- 2.1.23's prototype reads these; collection_radius throws there ("doesn't contain key").
  ["asteroid-collector"] = entity_proto("asteroid-collector", "asteroid-collector", 3, 3, { rotatable = true,
    arm_count_base = 1, arm_count_quality_scaling = 1, arm_speed_base = 0.2, arm_speed_quality_scaling = 0.05,
    collection_box_offset = 5, unpowered_arm_speed_scale = 0.3 }),
  ["rocket-silo"] = entity_proto("rocket-silo", "rocket-silo", 9, 9, { rocket_parts_required = 50 }),
  -- The rocket waiting in a silo has no unit number (2.1.23).
  ["rocket-silo-rocket"] = entity_proto("rocket-silo-rocket", "rocket-silo-rocket", 3, 9, { unit_numbered = false }),
  ["cargo-landing-pad"] = entity_proto("cargo-landing-pad", "cargo-landing-pad", 8, 8),
  ["cargo-bay"] = entity_proto("cargo-bay", "cargo-bay", 4, 4),
  -- Needs gravity (as most of Nauvis' buildings do), so it can't go on a platform.
  ["burner-inserter"] = entity_proto("burner-inserter", "inserter", 1, 1, {
    surface_conditions = { { property = "gravity", min = 0.1, max = 1e300 } },
  }),
  ["medium-metallic-asteroid"] = entity_proto("medium-metallic-asteroid", "asteroid", 2, 2),
  -- What a building waits for (modules.lua): no unit number, made with a target and `modules`.
  ["item-request-proxy"] = entity_proto("item-request-proxy", "item-request-proxy", 1, 1, { unit_numbered = false }),
}
-- A beacon: its two module slots and how much of their effect it hands on.
entity_protos.beacon = entity_proto("beacon", "beacon", 3, 3, { distribution_effectivity = 1.5, supply_area_distance = 3 })
-- Module slots (LuaEntityPrototype.module_inventory_size, allowed_effects; nil = every category).
for _, n in pairs({ "assembling-machine-1", "lab", "beacon" }) do
  entity_protos[n].module_inventory_size = 2
  entity_protos[n].allowed_effects = { speed = true, productivity = n == "assembling-machine-1", consumption = true, pollution = true, quality = true }
end
-- What an assembler draws (H20's entity info): 75 kW at most (joules a tick, by quality) and a
-- 2.5 kW drain; consumers' electric sources have an input priority.
entity_protos["assembling-machine-1"].energy_usage = 1250
entity_protos["assembling-machine-1"].get_max_energy_usage = function(quality)
  assert(quality == nil or type(quality) == "table" or type(quality) == "string", "get_max_energy_usage(quality?)")
  return 1250
end
entity_protos["assembling-machine-1"].electric_energy_source_prototype = { usage_priority = "secondary-input", drain = 2500 / 60,
  buffer_capacity = 1000, render_no_power_icon = true, render_no_network_icon = true }
-- What stands on tiles (tiles the entity's layers hit are where it can't be built, e.g. empty space).
for _, n in pairs({ "wooden-chest", "assembling-machine-1", "burner-inserter" }) do
  entity_protos[n].collision_mask = { layers = { object = true, item = true, player = true, water_tile = true } }
end
-- Like most real prototypes, the wall has no map colour of its own: the map uses its type's.
entity_protos["stone-wall"].map_color = nil
entity_protos["stone-wall"].friendly_map_color = nil

local decorative_protos = {}
for _, n in pairs({ "green-carpet-grass", "brown-asterisk", "small-rock" }) do
  decorative_protos[n] = strict("LuaDecorativePrototype", { name = n })
end

local tile_protos = {
  ["grass-1"] = { name = "grass-1", map_color = { r = 0.2, g = 0.5, b = 0.1, a = 1 } },
  water = { name = "water", map_color = { r = 0.1, g = 0.2, b = 0.6, a = 1 } },
  concrete = { name = "concrete", map_color = { r = 0.4, g = 0.4, b = 0.4, a = 1 } },
  ["stone-path"] = { name = "stone-path", map_color = { r = 0.4, g = 0.38, b = 0.35, a = 1 } },
  ["space-platform-foundation"] = { name = "space-platform-foundation", map_color = { r = 0.3, g = 0.3, b = 0.32, a = 1 } },
  ["empty-space"] = { name = "empty-space", map_color = { r = 0, g = 0, b = 0, a = 1 } },
}
-- What tile building reads (LuaTilePrototype): collision layers, mining, foundation.
for name, t in pairs(tile_protos) do
  t.collision_mask = { layers = name == "water" and { water_tile = true, player = true }
    or name == "empty-space" and { empty_space = true, object = true, item = true, player = true, water_tile = true }
    or { ground_tile = true } }
  local placed = name == "concrete" or name == "stone-path"
  t.mineable_properties = { minable = placed, products = placed and { { type = "item", name = name == "concrete" and "concrete" or "stone-brick", amount = 1 } } or nil }
  t.is_foundation = false
  strict("LuaTilePrototype", t)
end

local item_protos = {}
for _, n in pairs({ "transport-belt", "fast-transport-belt", "underground-belt", "assembling-machine-1", "stone-furnace", "locomotive" }) do
  item_protos[n] = { name = n, place_result = entity_protos[n] }
end
-- 2.x: the rail item is a rail planner; its place_result is empty and `rails` lists what it builds.
for _, n in pairs({ "blueprint", "deconstruction-planner", "upgrade-planner", "blueprint-book" }) do
  item_protos[n] = { name = n, place_result = nil }
end
item_protos["wooden-chest"] = { name = "wooden-chest", place_result = entity_protos["wooden-chest"] }
-- Modules (LuaItemPrototype.type, category, module_effects as 2.x's plain numbers).
item_protos["speed-module"] = { name = "speed-module", type = "module", category = "speed", place_result = nil,
  module_effects = { speed = 0.2, consumption = 0.5, quality = -0.1 } }
item_protos["productivity-module"] = { name = "productivity-module", type = "module", category = "productivity",
  place_result = nil, module_effects = { productivity = 0.04, speed = -0.05, consumption = 0.4, pollution = 0.05 } }
item_protos.rail = { name = "rail", place_result = nil, rails = { entity_protos["straight-rail"], entity_protos["half-diagonal-rail"],
  entity_protos["curved-rail-a"], entity_protos["elevated-straight-rail"] }, support = entity_protos["rail-support"] }
for _, n in pairs({ "straight-rail", "elevated-straight-rail" }) do
  entity_protos[n].items_to_place_this = { { name = "rail", count = 1 } }
end
entity_protos["half-diagonal-rail"].items_to_place_this = { { name = "rail", count = 2 } }
entity_protos["curved-rail-a"].items_to_place_this = { { name = "rail", count = 3 } }
entity_protos["rail-support"].items_to_place_this = { { name = "rail-support", count = 1 } }
item_protos["rail-support"] = { name = "rail-support", place_result = entity_protos["rail-support"] }
entity_protos["transport-belt"].related_underground_belt = entity_protos["underground-belt"]
entity_protos["underground-belt"].items_to_place_this = { { name = "underground-belt", count = 1 } }
-- Tiles (place_as_tile_result: a tile that can't go where the condition's layers are) and capsules.
-- Both are plain tables in the game (PlaceAsTileResult, CapsuleAction), so missing keys read nil.
for item, tile in pairs({ concrete = "concrete", ["stone-brick"] = "stone-path" }) do
  item_protos[item] = { name = item, place_result = nil, place_as_tile_result = ({
    result = tile_protos[tile], condition_size = 1, condition = { layers = { water_tile = true } }, invert = false, tile_condition = {},
  }) }
end
item_protos.grenade = { name = "grenade", place_result = nil, capsule_action = ({
  type = "throw", attack_parameters = { range = 15 }, uses_stack = true }) }
item_protos["cliff-explosives"] = { name = "cliff-explosives", place_result = nil, capsule_action = ({
  type = "destroy-cliffs", attack_parameters = { range = 10 }, radius = 1.5, timeout = 0 }) }
item_protos["burner-inserter"] = { name = "burner-inserter", place_result = entity_protos["burner-inserter"] }
entity_protos["burner-inserter"].items_to_place_this = { { name = "burner-inserter", count = 1 } }
for _, n in pairs({ "iron-plate", "wood", "pistol", "firearm-magazine", "burner-mining-drill", "iron-ore", "iron-gear-wheel",
  "space-platform-starter-pack" }) do
  item_protos[n] = { name = n, place_result = nil }
end
item_protos["space-platform-starter-pack"].type = "space-platform-starter-pack"
item_protos["pistol"].type = "gun"
item_protos["pistol"].attack_parameters = { type = "projectile", range = 15, cooldown = 15 }
item_protos["firearm-magazine"].type = "ammo"
item_protos["firearm-magazine"].ammo_category = { name = "bullet" }
item_protos["firearm-magazine"].magazine_size = 10

-- Equipment (LuaEquipmentPrototype) and the items that place it.
local equipment_protos = {
  ["energy-shield-equipment"] = { type = "energy-shield-equipment", w = 2, h = 2, max_energy = 120000, max_shield = 50 },
  ["battery-equipment"] = { type = "battery-equipment", w = 1, h = 2, max_energy = 20000000 },
  ["exoskeleton-equipment"] = { type = "movement-bonus-equipment", w = 2, h = 4, max_energy = 400000, movement = 0.3 },
  ["night-vision-equipment"] = { type = "night-vision-equipment", w = 2, h = 2, max_energy = 120000 },
  ["personal-roboport-equipment"] = { type = "roboport-equipment", w = 2, h = 2, max_energy = 35000000 },
}
for name, e in pairs(equipment_protos) do
  e.name = name
  e.shape = { width = e.w, height = e.h }
  item_protos[name] = { name = name, place_result = nil, place_as_equipment_result = strict("LuaEquipmentPrototype",
    { name = name, type = e.type, shape = e.shape }) }
end
item_protos["power-armor"] = { name = "power-armor", place_result = nil }
F.equipment_protos = equipment_protos
item_protos["repair-pack"] = { name = "repair-pack", place_result = nil, type = "repair-tool" }

local fluid_protos = {
  water = { name = "water", base_color = { r = 0, g = 0.34, b = 0.6, a = 1 } },
  steam = { name = "steam", base_color = { r = 0.5, g = 0.5, b = 0.5, a = 1 } },
}

-- Space locations (LuaSpaceLocationPrototype) and the connections between them.
local space_locations = {}
for _, loc in pairs({ { "nauvis", "planet", 0, -5 }, { "vulcanus", "planet", 8.5, 3 }, { "solar-system-edge", "space-location", 0, 60 } }) do
  -- How the star map draws it (magnitude, draw_orbit, label_orientation); the edge has no orbit.
  space_locations[loc[1]] = strict("LuaSpaceLocationPrototype", { name = loc[1], type = loc[2], position = { x = loc[3], y = loc[4] },
    magnitude = loc[1] == "vulcanus" and 1.5 or 1, draw_orbit = loc[1] ~= "solar-system-edge", label_orientation = 0.25 })
end
local space_connections = {
  ["nauvis-vulcanus"] = strict("LuaSpaceConnectionPrototype", {
    name = "nauvis-vulcanus", from = space_locations.nauvis, to = space_locations.vulcanus, length = 15000,
    asteroid_spawn_definitions = { { asteroid = "metallic-asteroid-chunk", type = "asteroid-chunk",
      spawn_points = { { probability = 0.01, speed = 0.02, distance = 0.1 }, { probability = 0.02, speed = 0.02, distance = 0.9 } } } },
  }),
  ["nauvis-solar-system-edge"] = strict("LuaSpaceConnectionPrototype", {
    name = "nauvis-solar-system-edge", from = space_locations.nauvis, to = space_locations["solar-system-edge"], length = 100000,
    asteroid_spawn_definitions = { { asteroid = "metallic-asteroid-chunk", type = "asteroid-chunk",
      spawn_points = { { probability = 0.2, speed = 0.05, distance = 0.5 } } } },
  }),
}
local asteroid_chunks = {
  ["metallic-asteroid-chunk"] = strict("LuaAsteroidChunkPrototype", { name = "metallic-asteroid-chunk", hidden = false }),
  ["carbonic-asteroid-chunk"] = strict("LuaAsteroidChunkPrototype", { name = "carbonic-asteroid-chunk", hidden = false }),
  ["oxide-asteroid-chunk"] = strict("LuaAsteroidChunkPrototype", { name = "oxide-asteroid-chunk", hidden = false }),
}
-- Qualities (Space Age): the hidden quality-unknown is left out by the mod. Epic and legendary
-- aren't researched in the fake's force.
local qualities = {}
-- Factoriopedia (pedia.lua) reads order, next_probability, colour and the multiplier too.
for i, n in ipairs({ "normal", "uncommon", "rare", "epic", "legendary", "quality-unknown" }) do
  local level = ({ 0, 1, 2, 3, 5, 0 })[i]
  qualities[n] = strict("LuaQualityPrototype", { name = n, level = level, hidden = n == "quality-unknown",
    order = string.char(96 + i), next_probability = 0.1, color = { r = 1, g = 1, b = 1, a = 1 }, default_multiplier = 1 + 0.3 * level })
end

-- Remnants: corpses buildings leave (LuaEntityPrototype.corpses: name -> prototype). The
-- assembler's are its own; the chest and the lab share small-remnants.
entity_protos["linked-belt"] = entity_proto("linked-belt", "linked-belt", 1, 1, { rotatable = true })
entity_protos["assembling-machine-1-remnants"] = entity_proto("assembling-machine-1-remnants", "corpse", 3, 3,
  { unit_numbered = false })
entity_protos["small-remnants"] = entity_proto("small-remnants", "corpse", 1, 1, { unit_numbered = false })
entity_protos["small-biter-corpse"] = entity_proto("small-biter-corpse", "corpse", 1, 1, { unit_numbered = false })
entity_protos["assembling-machine-1"].corpses = { ["assembling-machine-1-remnants"] = entity_protos["assembling-machine-1-remnants"] }
entity_protos["wooden-chest"].corpses = { ["small-remnants"] = entity_protos["small-remnants"] }
entity_protos.lab.corpses = { ["small-remnants"] = entity_protos["small-remnants"] }
entity_protos["small-biter"].corpses = { ["small-biter-corpse"] = entity_protos["small-biter-corpse"] }

-- Machines freeze on Aquilo without heat: inserters do (heating_energy > 0).
entity_protos.inserter.heating_energy = 50000
item_protos.yumako = { name = "yumako", place_result = nil, get_spoil_ticks = function() return 3600 end }
-- Items that build an entity of their name (ghosts read it to say what they need).
for name, proto in pairs(entity_protos) do
  if rawget(proto, "items_to_place_this") == nil then
    proto.items_to_place_this = item_protos[name] and { { name = name, count = 1 } } or {}
  end
end
-- Filled from the player force's recipes below: what never changes of them (name, hidden, the
-- 2.1 `categories`).
local recipe_protos = {}

local surface_properties = {}
for _, n in pairs({ "gravity", "pressure", "magnetic-field", "solar-power", "day-night-cycle" }) do
  surface_properties[n] = strict("LuaSurfacePropertyPrototype", { name = n })
end

prototypes = strict("LuaPrototypes", {
  entity = entity_protos, tile = tile_protos, item = item_protos, fluid = fluid_protos,
  space_location = space_locations, space_connection = space_connections, surface_property = surface_properties,
  asteroid_chunk = asteroid_chunks, quality = qualities, recipe = recipe_protos, decorative = decorative_protos, technology = {},
  -- Only the "type" filter (repair tools for the alerts).
  get_item_filtered = function(filters)
    assert(#filters == 1 and filters[1].filter == "type", "get_item_filtered: only {filter = \"type\"} is faked")
    local out = {}
    for name, item in pairs(item_protos) do
      if item.type == filters[1].type then
        out[name] = item
      end
    end
    return out
  end,
})

-- Factorio's global: the number of keys in a table.
function table_size(t)
  local n = 0
  for _ in pairs(t) do
    n = n + 1
  end
  return n
end

---------------------------------------------------------------------------------------------
-- forces

local function group(name, order)
  return strict("LuaGroup", { name = name, order = order })
end

local function make_recipe(name, enabled, category, extra)
  -- 2.1 shape: `categories`; reading `category` is an error, like the real 2.1 API.
  local r = {
    name = name, enabled = enabled, hidden = false, categories = { category }, energy = 0.5, order = "a",
    group = group("intermediate-products", "c"), subgroup = group("intermediate-product", "a"),
    ingredients = {}, products = { { type = "item", name = name, amount = 1 } },
  }
  for k, v in pairs(extra or {}) do
    r[k] = v
  end
  return strict("LuaRecipe", r)
end

local function make_tech(name, prerequisites, extra)
  local t = {
    name = name, order = "a-" .. name, researched = false, enabled = true, visible_when_disabled = false,
    prerequisites = prerequisites, research_unit_count = 10, research_unit_energy = 600,
    research_unit_ingredients = { { type = "item", name = "automation-science-pack", amount = 1 } },
    prototype = strict("LuaTechnologyPrototype", { hidden = false, essential = false, effects = {} }),
  }
  for k, v in pairs(extra or {}) do
    t[k] = v
  end
  return setmetatable(t, {
    __index = function(_, k)
      if k == "research_trigger" then
        return nil
      end
      error("LuaTechnology doesn't contain key " .. tostring(k), 2)
    end,
  })
end

local forces = {}
local techs = {}
techs.automation = make_tech("automation", {}, {
  prototype = strict("LuaTechnologyPrototype", { hidden = false, essential = true,
    effects = { { type = "unlock-recipe", recipe = "iron-gear-wheel" } } }),
})
techs.logistics = make_tech("logistics", { automation = techs.automation })
techs["steel-processing"] = make_tech("steel-processing", {}, { researched = true })
techs["secret"] = make_tech("secret", {}, { prototype = strict("LuaTechnologyPrototype", { hidden = true, effects = {} }) })

-- current_research is nil when nothing is being researched; anything else unknown is an error.
forces.player = setmetatable({
  name = "player",
  rail_planner_allow_elevated_rails = false,
  technologies = techs,
  research_progress = 0,
  research_queue = {},
  -- Starts the research if none is running, otherwise queues it (2.x).
  add_research = function(name)
    local f = forces.player
    local tech = techs[name]
    assert(tech, "add_research: unknown technology " .. tostring(name))
    if f.current_research == nil then
      rawset(f, "current_research", tech)
    else
      table.insert(f.research_queue, tech)
    end
    return true
  end,
  cancel_current_research = function()
    rawset(forces.player, "current_research", nil)
  end,
  manual_mining_speed_modifier = 0,
  character_logistic_requests = false,
  recipes = {
    ["iron-gear-wheel"] = make_recipe("iron-gear-wheel", true, "crafting", {
      ingredients = { { type = "item", name = "iron-plate", amount = 2 } },
    }),
    ["transport-belt"] = make_recipe("transport-belt", true, "crafting", {
      group = group("logistics", "b"), subgroup = group("belt", "b"), order = "a[transport-belt]",
      ingredients = { { type = "item", name = "iron-gear-wheel", amount = 1 }, { type = "item", name = "iron-plate", amount = 1 } },
      products = { { type = "item", name = "transport-belt", amount = 2 } },
    }),
    ["oil-processing"] = make_recipe("oil-processing", true, "oil-processing"),
    ["laser-turret"] = make_recipe("laser-turret", false, "crafting"),
    ["iron-plate"] = make_recipe("iron-plate", true, "smelting"),
  },
  get_spawn_position = function(surface) return { x = 0, y = 0 } end,
  find_logistic_network_by_position = function(position, surface)
    assert(position and surface and surface.index, "find_logistic_network_by_position(position, surface)")
    return F.network
  end,
  -- Space platforms by index; F.create_space_platform makes them.
  platforms = {},
  unlocked_locations = { nauvis = true, vulcanus = true },
  is_space_location_unlocked = function(name)
    assert(type(name) == "string", "is_space_location_unlocked takes a name")
    return forces.player.unlocked_locations[name] == true
  end,
  create_space_platform = function(p) return F.create_space_platform(p) end,
  -- Logistic groups' names (2.1: get_logistic_groups(type?), with_trash by default).
  get_logistic_groups = function(...)
    assert(select("#", ...) == 0, "get_logistic_groups: leave the type out for request groups")
    local out = {}
    for name in pairs(F.logistic_groups) do
      out[#out + 1] = name
    end
    table.sort(out)
    return out
  end,
  is_quality_unlocked = function(q)
    assert(type(q) == "string" and qualities[q], "is_quality_unlocked: a quality name")
    return q ~= "epic" and q ~= "legendary"
  end,
  -- Charting: F.charted["cx,cy"] marks charted chunks; chart() records the areas asked for.
  is_chunk_charted = function(surface, c)
    assert(surface and surface.index, "is_chunk_charted: surface first")
    local cx, cy = c.x or c[1], c.y or c[2]
    return F.charted[cx .. "," .. cy] == true
  end,
  -- A headless server with no player reveals nothing, even beside a working radar (2.1.23).
  is_chunk_visible = function(surface, c)
    assert(surface and surface.index and (c.x or c[1]), "is_chunk_visible(surface, chunk)")
    return false
  end,
  chart = function(surface, area)
    assert(surface and surface.index and area[1] and area[2], "chart(surface, area)")
    F.chart_requests[#F.chart_requests + 1] = area
  end,
  -- Chart tags (LuaCustomChartTag): position, text, icon (SignalID or nil), tag_number, destroy.
  find_chart_tags = function(surface, area)
    assert(surface and surface.index, "find_chart_tags: surface first")
    local out = {}
    for _, tag in ipairs(F.tags) do
      out[#out + 1] = tag
    end
    return out
  end,
  add_chart_tag = function(surface, spec)
    assert(surface and surface.index, "add_chart_tag: surface first")
    local x, y = spec.position.x or spec.position[1], spec.position.y or spec.position[2]
    assert(spec.icon == nil or (spec.icon.name and spec.icon.type), "add_chart_tag: icon is a SignalID")
    if not F.charted[math.floor(x / 32) .. "," .. math.floor(y / 32)] then
      return nil
    end
    F.tag_number = F.tag_number + 1
    local tag
    tag = strict("LuaCustomChartTag", {
      valid = true, tag_number = F.tag_number, position = { x = x, y = y }, text = spec.text or "",
      icon = spec.icon,
      destroy = function()
        for i, t in ipairs(F.tags) do
          if t == tag then
            table.remove(F.tags, i)
          end
        end
      end,
    })
    F.tags[#F.tags + 1] = tag
    return tag
  end,
}, {
  __index = function(_, k)
    if k == "current_research" then
      return nil
    end
    error("LuaForce doesn't contain key " .. tostring(k), 2)
  end,
})
for name, r in pairs(forces.player.recipes) do
  prototypes.recipe[name] = r
end
for name, t in pairs(techs) do
  prototypes.technology[name] = t.prototype
end
forces.neutral = strict("LuaForce", { name = "neutral" })
for name, r in pairs(forces.player.recipes) do
  -- The force's LuaRecipe stands in for the prototype: Factoriopedia (pedia.lua) reads its
  -- ingredients and products too.
  recipe_protos[name] = r
end
forces.enemy = strict("LuaForce", { name = "enemy",
  -- /evolution (console.lua): the factor and its parts, per surface.
  get_evolution_factor = function(surface) assert(surface and surface.index, "get_evolution_factor(surface)") return 0.25 end,
  get_evolution_factor_by_time = function(surface) return 0.15 end,
  get_evolution_factor_by_pollution = function(surface) return 0.05 end,
  get_evolution_factor_by_killing_spawners = function(surface) return 0.05 end,
})
-- /cheat (console.lua)
rawset(forces.player, "research_all_technologies", function()
  F.researched_all = true
  for _, t in pairs(techs) do
    t.researched = true
  end
end)

---------------------------------------------------------------------------------------------
-- entities

local surfaces = {}

local function raise(name, data)
  local f = F.handlers[defines.events[name]]
  if f then
    data.name = defines.events[name]
    data.tick = game.tick
    f(data)
  end
end
F.raise = raise

local STACK_SIZE = { ["iron-plate"] = 100, ["copper-plate"] = 100, wood = 100, coal = 50, ["iron-ore"] = 50,
  ["iron-gear-wheel"] = 100, ["transport-belt"] = 100, pistol = 5, ["firearm-magazine"] = 200 }

local function stack_size(name)
  return STACK_SIZE[name] or 50
end
for name, proto in pairs(prototypes.item) do
  proto.stack_size = stack_size(name)
end

-- Blueprint and planner methods on item stacks, by item (filled in once surfaces exist).
F.planner_methods = {}

local stack_handles = setmetatable({}, { __mode = "k" }) -- LuaItemStack view -> {slots, index}

-- A view of one slot, like LuaItemStack: reads follow the slot, count is writable, and
-- transfer_stack / swap_stack / set_stack / clear change it. Reading an empty stack's item is
-- an error, as in the game.
local function item_stack(slots, i)
  local methods = {}
  local view = setmetatable({}, {
    __index = function(_, k)
      if methods[k] then
        return methods[k]
      end
      local slot = slots[i]
      if k == "valid_for_read" then
        return slot ~= nil
      end
      if not slot then
        error("LuaItemStack: can't read " .. tostring(k) .. " of an empty stack", 2)
      end
      if k == "name" or k == "count" then
        return slot[k]
      elseif k == "is_blueprint" then
        return slot.name == "blueprint"
      elseif k == "is_blueprint_book" then
        return slot.name == "blueprint-book"
      elseif k == "export_stack" then
        return function() return F.export(slot) end
      elseif slot.name == "blueprint-book" and k == "get_inventory" then
        return function(id)
          assert(id == defines.inventory.item_main, "a book has only item_main")
          return slot.pages
        end
      elseif slot.name == "blueprint-book" and k == "active_index" then
        return slot.active or 1
      elseif slot.name == "blueprint" and k == "set_blueprint_entities" then
        return function(list) slot.bp = list end
      elseif slot.name == "blueprint" and k == "get_blueprint_tiles" then
        return function() return {} end
      elseif k == "is_deconstruction_item" then
        return slot.name == "deconstruction-planner"
      elseif k == "is_upgrade_item" then
        return slot.name == "upgrade-planner"
      elseif k == "label" and (slot.name == "blueprint" or slot.name == "blueprint-book") then
        return slot.label
      elseif slot.name == "upgrade-planner" and k == "mapper_count" then
        return #(slot.mappers or {})
      elseif slot.name == "upgrade-planner" and k == "get_mapper" then
        -- 2.x: past mapper_count is out of bounds; an undefined source reads {type = "item"}.
        return function(index, kind)
          assert(kind == "from" or kind == "to", "get_mapper(index, 'from' | 'to')")
          local m = (slot.mappers or {})[index]
          assert(m, "get_mapper: index out of bounds")
          if kind == "from" then
            return m.from or { type = "item" }
          end
          return m.to
        end
      elseif slot.name == "upgrade-planner" and k == "set_mapper" then
        return function(index, kind, mapper)
          assert(kind == "from" or kind == "to", "set_mapper(index, 'from' | 'to', mapper)")
          slot.mappers = slot.mappers or {}
          for j = #slot.mappers + 1, index do
            slot.mappers[j] = {}
          end
          slot.mappers[index][kind] = mapper
        end
      elseif k == "preview_icons" and (slot.name == "blueprint" or slot.name == "blueprint-book"
          or slot.name == "deconstruction-planner" or slot.name == "upgrade-planner") then
        return slot.icons or {}
      elseif slot.name == "blueprint" and slot.bp and F.stack_blueprint[k] then
        return function(p) return F.stack_blueprint[k](slot, p) end
      elseif slot.name == "blueprint" and k == "create_blueprint" then
        return function(p) return F.stack_blueprint.create_blueprint(slot, p) end
      elseif F.planner_methods[k] and F.planner_methods[k].item == slot.name then
        return F.planner_methods[k].fn
      elseif k == "quality" then
        return strict("LuaQualityPrototype", { name = slot.quality or "normal" })
      elseif k == "spoil_percent" then
        return slot.spoil or 0
      elseif k == "prototype" then
        local ip = item_protos[slot.name]
        return strict("LuaItemPrototype", { stack_size = stack_size(slot.name),
          place_as_equipment_result = ip and ip.place_as_equipment_result or nil, type = ip and ip.type or "item" })
      end
      error("LuaItemStack doesn't contain key " .. tostring(k), 2)
    end,
    __newindex = function(_, k, v)
      if k == "label" and slots[i] and (slots[i].name == "blueprint" or slots[i].name == "blueprint-book") then
        slots[i].label = v
        return
      end
      if k == "preview_icons" and slots[i] then
        slots[i].icons = v
        return
      end
      if k == "active_index" and slots[i] and slots[i].name == "blueprint-book" then
        slots[i].active = v
        return
      end
      if k == "spoil_percent" and slots[i] then
        assert(v >= 0 and v <= 1, "spoil_percent is 0..1")
        slots[i].spoil = v
        return
      end
      if k == "preview_icons" and slots[i] then
        slots[i].icons = v
        return
      end
      if k == "active_index" and slots[i] and slots[i].name == "blueprint-book" then
        assert(type(v) == "number" and v >= 1 and v <= 6, "active_index: a page of the book")
        slots[i].active = v
        return
      end
      assert(k == "count" and slots[i] and v >= 1, "LuaItemStack: can't write " .. tostring(k))
      slots[i].count = v
    end,
  })
  stack_handles[view] = { slots, i }
  local function same(a, b)
    return a.name == b.name and (a.quality or "normal") == (b.quality or "normal")
  end
  -- 2.x: transfer_stack(stack, amount?) moves as much as fits; true if all of it moved.
  methods.transfer_stack = function(src, amount)
    local h = stack_handles[src]
    local from = h[1][h[2]]
    if not from then
      return false
    end
    local want = math.min(amount or from.count, from.count)
    local to = slots[i]
    if to and not same(to, from) then
      return false
    end
    local n = math.min(want, stack_size(from.name) - (to and to.count or 0))
    if n <= 0 then
      return false
    end
    if to then
      to.count = to.count + n
    else
      slots[i] = { name = from.name, count = n, quality = from.quality }
    end
    from.count = from.count - n
    if from.count == 0 then
      h[1][h[2]] = nil
    end
    return n == want
  end
  methods.swap_stack = function(other)
    local h = stack_handles[other]
    slots[i], h[1][h[2]] = h[1][h[2]], slots[i]
    return true
  end
  methods.set_stack = function(spec)
    local h = spec and stack_handles[spec]
    if h then -- another LuaItemStack: a copy of it, blueprint and all
      local from = h[1][h[2]]
      slots[i] = from and { name = from.name, count = from.count, quality = from.quality, bp = from.bp } or nil
      return true
    end
    slots[i] = spec and { name = spec.name, count = spec.count or 1, quality = spec.quality } or nil
    return true
  end
  methods.clear = function()
    slots[i] = nil
  end
  -- Exchange strings: the fake's own format (F.export / F.import); 1 for anything else.
  methods.import_stack = function(data)
    local slot = F.import(data)
    if not slot then
      return 1
    end
    slots[i] = slot
    return 0
  end
  -- LuaItemStack.use_capsule(entity, position): what was thrown is kept in F.capsules; a throw
  -- takes one from the stack.
  methods.use_capsule = function(entity, position)
    assert(entity and entity.valid and position and (position.x or position[1]), "use_capsule(entity, target_position)")
    local stack = slots[i]
    local proto = prototypes.item[stack.name]
    assert(rawget(proto, "capsule_action"), "use_capsule: " .. stack.name .. " isn't a capsule")
    F.capsules[#F.capsules + 1] = { name = stack.name, x = position.x or position[1], y = position.y or position[2] }
    stack.count = stack.count - 1
    if stack.count <= 0 then
      slots[i] = nil
    end
    return {}
  end
  return view
end

-- (F.make_inventory, below, for books' pages.)
-- An inventory of `size` slots, like LuaInventory: inv[i] and #inv give its stacks; insert fills
-- stacks of the same item first, then empty slots.
local function make_inventory(size)
  size = size or 16
  local slots = {} -- index -> {name, count, quality} or nil
  local inv = {}
  -- An item name, or {name, quality} (2.x ItemWithQualityID: only that quality).
  inv.get_item_count = function(name)
    local n = 0
    local q = nil
    if type(name) == "table" then
      q = name.quality ~= "normal" and name.quality or false
      name = name.name
    end
    for i = 1, size do
      if slots[i] and slots[i].name == name and (q == nil or (slots[i].quality or false) == q) then
        n = n + slots[i].count
      end
    end
    return n
  end
  -- Normal quality is stored as nil.
  local function quality_of(stack)
    local q = stack.quality
    if type(q) == "table" then -- a LuaItemStack's LuaQualityPrototype
      q = q.name
    end
    return q ~= "normal" and q or nil
  end
  inv.insert = function(stack)
    local quality = quality_of(stack)
    local left = stack.count or 1
    for pass = 1, 2 do
      for i = 1, size do
        local slot = slots[i]
        if left > 0 and pass == 1 and slot and slot.name == stack.name and slot.quality == quality then
          local n = math.min(left, stack_size(stack.name) - slot.count)
          slot.count, left = slot.count + n, left - n
        elseif left > 0 and pass == 2 and not slot then
          local n = math.min(left, stack_size(stack.name))
          slots[i], left = { name = stack.name, count = n, quality = quality }, left - n
        end
      end
    end
    return (stack.count or 1) - left
  end
  inv.remove = function(stack)
    local quality = quality_of(stack)
    local left = stack.count or 1
    for i = size, 1, -1 do
      local slot = slots[i]
      if left > 0 and slot and slot.name == stack.name and slot.quality == quality then
        local n = math.min(left, slot.count)
        slot.count, left = slot.count - n, left - n
        if slot.count == 0 then
          slots[i] = nil
        end
      end
    end
    return (stack.count or 1) - left
  end
  inv.get_contents = function()
    local out, at = {}, {}
    for i = 1, size do
      local slot = slots[i]
      if slot then
        local key = slot.name .. "/" .. (slot.quality or "normal")
        if not at[key] then
          out[#out + 1] = { name = slot.name, count = 0, quality = slot.quality or "normal" }
          at[key] = out[#out]
        end
        at[key].count = at[key].count + slot.count
      end
    end
    return out
  end
  inv.is_empty = function()
    return next(slots) == nil
  end
  inv.find_item_stack = function(name)
    for k = 1, size do
      if slots[k] and slots[k].name == name then
        return item_stack(slots, k), k
      end
    end
    return nil
  end
  inv.find_empty_stack = function()
    for i = 1, size do
      if not slots[i] then
        return item_stack(slots, i), i
      end
    end
    return nil
  end
  -- Slot filters (the character's middle click): item name by slot.
  local filters = {}
  inv.supports_filters = function() return true end
  inv.get_filter = function(i)
    assert(i >= 1 and i <= size, "get_filter: index out of range")
    return filters[i] and { name = filters[i], quality = "normal", comparator = "=" } or nil
  end
  inv.set_filter = function(i, f)
    assert(i >= 1 and i <= size, "set_filter: index out of range")
    assert(f == nil or type(f) == "string", "set_filter: an item name or nil")
    filters[i] = f
    return true
  end
  -- The red limit bar of a chest: get_bar() is the first slot machines may not use.
  local bar = size + 1
  inv.supports_bar = function() return true end
  inv.get_bar = function() return bar end
  inv.set_bar = function(b)
    assert(b == nil or (b >= 1 and b <= size + 1), "set_bar: out of range")
    bar = b or size + 1
  end
  inv.valid = true
  inv.sort_and_merge = function()
    local contents = inv.get_contents()
    table.sort(contents, function(a, b) return a.name < b.name end)
    for i = 1, size do
      slots[i] = nil
    end
    for _, item in ipairs(contents) do
      inv.insert({ name = item.name, count = item.count, quality = item.quality })
    end
  end
  return setmetatable(inv, {
    __index = function(_, k)
      if type(k) == "number" then
        assert(k >= 1 and k <= size, "LuaInventory: index out of range")
        return item_stack(slots, k)
      end
      error("LuaInventory doesn't contain key " .. tostring(k), 2)
    end,
    __len = function() return size end,
  })
end
F.make_inventory = function(size) return make_inventory(size) end

F.make_inventory = make_inventory -- for blueprint books' pages (item_stack is defined first)

-- A gun or ammo inventory: numbered slots, read as inv[i] and #inv like the real LuaInventory.
-- The harness changes the slots ({name, count, ammo}) directly.
local function make_slots(size)
  local slots = {}
  for i = 1, size do
    slots[i] = {}
  end
  local inv = setmetatable({}, {
    __index = function(_, k)
      if type(k) ~= "number" then
        error("LuaInventory doesn't contain key " .. tostring(k), 2)
      end
      assert(k >= 1 and k <= size, "LuaInventory: index out of range")
      local slot = slots[k]
      if not slot.name then
        return strict("LuaItemStack", { valid_for_read = false })
      end
      local stack = { valid_for_read = true, name = slot.name, count = slot.count }
      if slot.ammo then
        stack.ammo = slot.ammo
      end
      local ip = item_protos[slot.name]
      stack.prototype = strict("LuaItemPrototype", { name = slot.name, magazine_size = ip and ip.magazine_size or nil })
      return strict("LuaItemStack", stack)
    end,
    __len = function() return size end,
  })
  -- Shift+click with nothing open sends guns and ammo here (inventory.lua's xfer).
  rawset(inv, "insert", function(stack)
    local left = stack.count or 1
    for k = 1, size do
      local slot = slots[k]
      if left > 0 and (not slot.name or slot.name == stack.name) then
        local n = math.min(left, stack_size(stack.name) - (slot.count or 0))
        slot.name, slot.count, left = stack.name, (slot.count or 0) + n, left - n
      end
    end
    return (stack.count or 1) - left
  end)
  rawset(inv, "get_item_count", function(name)
    local n = 0
    for k = 1, size do
      if slots[k].name == name then
        n = n + slots[k].count
      end
    end
    return n
  end)
  return inv, slots
end

-- Transport lines run straight through the entity along its direction. Line 1 is the left lane,
-- line 2 the right. An underground belt's lines 3 and 4 stand for the tunnel: they start at the
-- front edge of the entity and run away from it, so their items are outside it.
local belt_lines = setmetatable({}, { __mode = "k" }) -- entity -> {line index -> items}

local function make_transport_line(e, index)
  local items = belt_lines[e][index]
  local angle = e.direction / 16 * 2 * math.pi
  local fx, fy = math.sin(angle), -math.cos(angle)
  local rx, ry = -fy, fx
  -- As measured in 2.1.23 (live_check): a line's position 0 is at the belt's exit edge and grows
  -- backwards; the lanes are 0.234 tiles either side of the centre.
  local lane = (index % 2 == 1) and -0.234 or 0.234
  return strict("LuaTransportLine", {
    line_length = 1,
    get_detailed_contents = function()
      local out = {}
      for _, it in ipairs(items) do
        out[#out + 1] = strict("DetailedItemOnLine", {
          stack = strict("LuaItemStack", { valid_for_read = true, name = it.name, count = 1, spoil_percent = it.spoil or 0,
            quality = strict("LuaQualityPrototype", { name = it.quality or "normal" }) }),
          position = it.position,
          unique_id = it.unique_id,
        })
      end
      return out
    end,
    -- Fast transfer on belts (ui_actions.lua): totals, taking items off, putting them on.
    get_contents = function()
      local out, at = {}, {}
      for _, it in ipairs(items) do
        local key = it.name .. "/" .. (it.quality or "normal")
        if not at[key] then
          out[#out + 1] = { name = it.name, count = 0, quality = it.quality or "normal" }
          at[key] = out[#out]
        end
        at[key].count = at[key].count + 1
      end
      return out
    end,
    remove_item = function(stack)
      assert(type(stack) == "table" and stack.name, "remove_item(items)")
      local left = stack.count or 1
      for k = #items, 1, -1 do
        if left > 0 and items[k].name == stack.name and (items[k].quality or "normal") == (stack.quality or "normal") then
          table.remove(items, k)
          left = left - 1
        end
      end
      return (stack.count or 1) - left
    end,
    can_insert_at_back = function()
      return #items < 4
    end,
    insert_at_back = function(stack)
      assert(type(stack) == "table" and stack.name and (stack.count or 1) == 1, "insert_at_back(items)")
      if #items >= 4 then
        return false
      end
      F.next_item_id = (F.next_item_id or 9000) + 1
      items[#items + 1] = { name = stack.name, quality = stack.quality ~= "normal" and stack.quality or nil, position = 0.125 * #items,
        unique_id = F.next_item_id }
      return true
    end,
    get_line_item_position = function(position)
      local p = e.position
      local along = index <= 2 and 0.5 - position or 0.5 + position
      return { x = p.x + fx * along + rx * lane, y = p.y + fy * along + ry * lane }
    end,
  })
end

-- A LuaTrain of these carriages. Its schedule is a 2.x LuaSchedule: get_records (nil when
-- empty), set_records, go_to_station, current and group. The harness changes the rest through
-- F.train_data[train].
local function make_train(carriages)
  F.next_train = F.next_train + 1
  local sched = { current = 1, records = {}, group = "" }
  local schedule = setmetatable({}, {
    __index = function(_, k)
      if k == "current" or k == "group" then
        return sched[k]
      elseif k == "get_records" then
        return function()
          if #sched.records == 0 then
            return nil
          end
          local out = {}
          for i, r in ipairs(sched.records) do
            out[i] = r
          end
          return out
        end
      elseif k == "set_records" then
        return function(records)
          for _, r in ipairs(records) do
            assert(r.station or r.rail, "set_records: a record needs a station or a rail")
            assert(r.rail == nil or r.rail.valid, "set_records: rail must be a LuaEntity")
            for _, w in ipairs(r.wait_conditions or {}) do
              assert(type(w.type) == "string", "set_records: a wait condition needs a type")
            end
          end
          sched.records = records
          sched.current = math.min(math.max(sched.current, 1), math.max(#records, 1))
        end
      elseif k == "go_to_station" then
        return function(i)
          assert(i >= 1 and i <= #sched.records, "go_to_station: no record " .. tostring(i))
          sched.current = i
        end
      elseif k == "get_record_count" then
        return function() return #sched.records end
      elseif k == "add_record" then
        return function(d)
          assert(d.station or (d.rail and d.rail.valid), "add_record: station or rail")
          local at = d.index and d.index.schedule_index or #sched.records + 1
          assert(at >= 1 and at <= #sched.records + 1, "add_record: index out of range")
          local rec = { station = d.station, rail = d.rail, temporary = d.temporary, wait_conditions = d.wait_conditions }
          table.insert(sched.records, at, rec)
        end
      elseif k == "get_interrupts" then
        return function() return sched.interrupts or {} end
      elseif k == "set_interrupts" then
        return function(list)
          for _, int in ipairs(list) do
            assert(type(int.name) == "string", "set_interrupts: an interrupt needs a name")
            for _, w in ipairs(int.conditions or {}) do
              assert(type(w.type) == "string", "set_interrupts: a condition needs a type")
            end
            for _, r in ipairs(int.targets or {}) do
              assert(r.station or (r.rail and r.rail.valid), "set_interrupts: a target needs a station or a rail")
            end
          end
          sched.interrupts = list
        end
      end
      error("LuaSchedule doesn't contain key " .. tostring(k), 2)
    end,
  })
  local td = {
    id = F.next_train, state = defines.train_state.no_schedule, manual_mode = false, speed = 0, valid = true,
    carriages = carriages, get_schedule = function() return schedule end, group = "",
  }
  td.front_stock = carriages[1]
  -- Items in its cargo wagons ({name, count, quality}); no fluids.
  td.get_contents = function()
    local out = {}
    for _, c in ipairs(td.carriages) do
      local inv = F.inventories[c] and F.inventories[c].cargo
      for _, it in ipairs(inv and inv.get_contents() or {}) do
        out[#out + 1] = it
      end
    end
    return out
  end
  td.get_fluid_contents = function() return {} end
  td.locomotives = { front_movers = {}, back_movers = {} }
  local optional = { station = true, path_end_stop = true }
  local train = setmetatable({}, {
    __index = function(_, k)
      local v = td[k]
      if v == nil and not optional[k] then
        error("LuaTrain doesn't contain key " .. tostring(k), 2)
      end
      return v
    end,
    __newindex = function(_, k, v)
      if k == "group" then
        -- 2.1: joining a group takes the group's schedule; the schedule says the group too
        assert(type(v) == "string", "LuaTrain.group is a string")
        td.group, sched.group = v, v
        return
      end
      assert(k == "manual_mode", "LuaTrain: can't write " .. tostring(k))
      td.manual_mode = v
    end,
  })
  F.train_data[train] = td
  F.trains[td.id] = train
  return train
end

-- Makes one train of these carriages (rolling stock entities, front first).
function F.couple(...)
  local carriages = { ... }
  -- The trains they made alone are gone, as in the game.
  for id, old in pairs(F.trains) do
    for _, c in ipairs(F.train_data[old].carriages) do
      for _, mine in ipairs(carriages) do
        if c == mine then
          F.trains[id] = nil
        end
      end
    end
  end
  local train = make_train(carriages)
  for _, carriage in ipairs(carriages) do
    F.train_setters[carriage](train)
  end
  return train
end

-- A logistic section: `filters` as LogisticFilter ({value = {type, name, quality, comparator},
-- min, max?}), checked when written.
-- A section in a group shares its filters with every other section of that group
-- (F.logistic_groups[name]).
F.logistic_groups = {}
local function make_section(group)
  local filters = group and (F.logistic_groups[group] or {}) or {}
  local fields = { active = true, multiplier = 1, group = group or "" }
  return setmetatable({}, {
    __index = function(_, k)
      if k == "filters" then
        return group and (F.logistic_groups[group] or {}) or filters
      elseif fields[k] ~= nil then
        return fields[k]
      end
      error("LuaLogisticSection doesn't contain key " .. tostring(k), 2)
    end,
    __newindex = function(_, k, v)
      if k == "active" or k == "multiplier" then
        fields[k] = v
        return
      end
      if k == "group" then
        -- Joining a group takes its filters (a new name makes the group); "" leaves it, keeping them.
        assert(type(v) == "string", "LuaLogisticSection.group is a string")
        if v == "" then
          filters = group and (F.logistic_groups[group] or {}) or filters
          group = nil
        else
          F.logistic_groups[v] = F.logistic_groups[v] or filters
          group = v
        end
        fields.group = v
        return
      end
      assert(k == "filters", "LuaLogisticSection: can't write " .. tostring(k))
      for _, f in ipairs(v) do
        assert(f.value and f.value.name and f.value.type and f.value.quality, "a logistic filter needs value {type, name, quality}")
        assert(item_protos[f.value.name], "unknown item " .. tostring(f.value.name))
        assert(type(f.min) == "number" and (f.max == nil or f.max >= f.min), "a logistic filter needs min <= max")
      end
      filters = v
      if group then
        F.logistic_groups[group] = v
      end
    end,
  })
end

-- Something with logistic sections: a requester chest's LuaLogisticSections or the character's
-- requester LuaLogisticPoint (which also has enabled and trash_not_requested).
local function make_sections(point)
  local sections = {}
  local fields = { enabled = true, trash_not_requested = false }
  return setmetatable({}, {
    __index = function(_, k)
      if k == "get_section" then
        return function(i) return sections[i] end
      elseif k == "add_section" then
        return function(group)
          assert(group == nil or type(group) == "string", "add_section(group?)")
          sections[#sections + 1] = make_section(group ~= "" and group or nil)
          return sections[#sections]
        end
      elseif k == "remove_section" then
        return function(i)
          assert(sections[i], "remove_section: no section " .. tostring(i))
          table.remove(sections, i)
          return true
        end
      elseif k == "sections" then
        local copy = {}
        for i, sec in ipairs(sections) do
          copy[i] = sec
        end
        return copy
      elseif k == "sections_count" then
        return #sections
      elseif point and fields[k] ~= nil then
        return fields[k]
      end
      error((point and "LuaLogisticPoint" or "LuaLogisticSections") .. " doesn't contain key " .. tostring(k), 2)
    end,
    __newindex = function(_, k, v)
      assert(point and fields[k] ~= nil, "can't write " .. tostring(k))
      fields[k] = v
    end,
  })
end

-- A LuaLogisticCell of a roboport (or another owner) with its two radii (squares round the owner).
local function in_square(owner, r, position)
  assert(type(position) == "table", "a position")
  local x, y = position.x or position[1], position.y or position[2]
  return math.abs(x - owner.position.x) <= r and math.abs(y - owner.position.y) <= r
end

function F.make_cell(owner, logistic_radius, construction_radius)
  return strict("LuaLogisticCell", {
    valid = true, owner = owner, logistic_radius = logistic_radius, construction_radius = construction_radius,
    mobile = owner.type ~= "roboport",
    is_in_construction_range = function(position) return in_square(owner, construction_radius, position) end,
    is_in_logistic_range = function(position) return in_square(owner, logistic_radius, position) end,
  })
end

-- A LuaLogisticNetwork for F.network: robot counts and contents ({{name, count}, ...}).
-- `cells` (optional): its LuaLogisticCells (F.make_cell).
function F.make_network(id, robots, contents, cells)
  local own_cells = cells or F.network_cells or {}
  return strict("LuaLogisticNetwork", {
    find_cell_closest_to = function(position)
      assert(type(position) == "table", "find_cell_closest_to(position)")
      local x, y = position.x or position[1], position.y or position[2]
      local best, best_d
      for _, c in pairs(own_cells) do
        local d = (c.owner.position.x - x) ^ 2 + (c.owner.position.y - y) ^ 2
        if not best_d or d < best_d then
          best, best_d = c, d
        end
      end
      return best
    end,
    valid = true, network_id = id,
    available_logistic_robots = robots[1], all_logistic_robots = robots[2],
    available_construction_robots = robots[3], all_construction_robots = robots[4],
    get_contents = function()
      local out = {}
      for _, c in ipairs(contents) do
        out[#out + 1] = { name = c[1], count = c[2], quality = "normal" }
      end
      return out
    end,
    get_item_count = function(item)
      assert(type(item) == "string" or type(item) == "table", "get_item_count(item)")
      local n = 0
      for _, c in ipairs(contents) do
        if c[1] == (type(item) == "table" and item.name or item) then
          n = n + c[2]
        end
      end
      return n
    end,
    cells = own_cells, storages = {}, providers = {}, requesters = {}, custom_name = "",
  })
end

F.proxies = setmetatable({}, { __mode = "k" }) -- target -> its item-request-proxy
local function make_entity(surface, params)
  local proto = entity_protos[params.name]
  assert(proto, "unknown entity " .. tostring(params.name))
  local pos = params.position
  local data = {
    valid = true, name = proto.name, type = proto.type,
    position = { x = pos.x or pos[1], y = pos.y or pos[2] },
    direction = params.direction or 0, surface = surface,
    force = params.force and (type(params.force) == "string" and forces[params.force] or params.force) or forces.neutral,
    prototype = proto, health = 100, max_health = 100, minable = true, rotatable = proto.rotatable,
    quality = qualities[params.quality or "normal"] or strict("LuaQualityPrototype", { name = params.quality }),
  }
  data.get_health_ratio = function() return data.health / data.max_health end
  if proto.type == "rail-signal" or proto.type == "rail-chain-signal" then
    data.signal_state = 1 -- defines.signal_state.closed
  end
  if proto.type == "rail-chain-signal" then
    data.chain_signal_state = 3 -- defines.chain_signal_state.none_open
  end
  data.to_be_deconstructed = function() return F.decon_marks[data.self] == true end
  data.to_be_upgraded = function() return F.upgrade_marks[data.self] ~= nil end
  data.get_upgrade_target = function() return F.upgrade_marks[data.self] end
  data.order_deconstruction = function(force)
    assert(force, "order_deconstruction(force)")
    F.decon_marks[data.self] = true
    raise("on_marked_for_deconstruction", { entity = data.self })
    return true
  end
  data.cancel_deconstruction = function(force)
    assert(force, "cancel_deconstruction(force)")
    F.decon_marks[data.self] = nil
    raise("on_cancelled_deconstruction", { entity = data.self })
  end
  data.order_upgrade = function(p)
    assert(p.force and p.target and p.target.name, "order_upgrade{target, force}")
    F.upgrade_marks[data.self] = entity_protos[p.target.name]
    raise("on_marked_for_upgrade", { entity = data.self, target = entity_protos[p.target.name] })
    return true
  end
  data.cancel_upgrade = function(force)
    assert(force, "cancel_upgrade(force)")
    F.upgrade_marks[data.self] = nil
    raise("on_cancelled_upgrade", { entity = data.self })
    return true
  end
  if proto.type == "tile-ghost" then
    assert(tile_protos[params.inner_name], "tile-ghost: unknown tile " .. tostring(params.inner_name))
    data.ghost_name = params.inner_name
  end
  if proto.type == "item-request-proxy" then
    assert(params.target and params.target.valid and type(params.modules) == "table",
      "item-request-proxy: create_entity{target = entity, modules = {BlueprintInsertPlan...}}")
    data.proxy_target = params.target
    data.insert_plan = params.modules
  end
  if proto.type == "entity-ghost" then
    -- 2.x: the modules it is to get (BlueprintInsertPlan), and what they add up to.
    data.insert_plan = {}
    data.ghost_name = params.inner_name
    data.ghost_prototype = entity_protos[params.inner_name]
    data.ghost_type = entity_protos[params.inner_name].type
    if data.ghost_type == "underground-belt" then
      data.belt_to_ground_type = params.type or "input"
    end
    -- Fills the ghost in: the real entity where it stood (2.x returns collided items, the entity
    -- and an item request proxy).
    data.revive = function(p)
      local spec = { name = data.ghost_name, position = data.position, direction = data.direction, force = data.force,
        type = data.belt_to_ground_type }
      data.destroy()
      local real = surface.create_entity(spec)
      if p and p.raise_revive then
        raise("script_raised_revive", { entity = real })
      end
      return {}, real, nil
    end
  end
  -- Units are commandable; the harness sets the command and distraction (LuaCommandable's
  -- command / distraction_command, nil when it has none).
  if proto.type == "unit" then
    local cmds = {}
    data.commandable = setmetatable({}, {
      __index = function(_, k)
        if k == "command" or k == "distraction_command" then
          return cmds[k]
        end
        error("LuaCommandable doesn't contain key " .. tostring(k), 2)
      end,
      __newindex = function(_, k, v)
        assert(k == "command" or k == "distraction_command", "LuaCommandable: can't write " .. tostring(k))
        cmds[k] = v  -- harness only (the real ones take set_command / set_distraction_command)
      end,
    })
  end
  if proto.heating_energy then
    data.frozen = params.frozen or false
  end
  if proto.type == "beam" then
    local source, target = params.source, params.target
    data.get_beam_source = function()
      return source and { entity = source } or { position = params.source_position }
    end
    data.get_beam_target = function()
      return target and { entity = target } or { position = params.target_position }
    end
  end
  if proto.type == "smoke-with-trigger" then
    data.time_to_live = params.time_to_live or 1200
  end
  local optional = {
    unit_number = true, status = true, vehicle = true, crafting_queue = true, player = true, trains_limit = true, grid = true,
    selected = true, electric_network_id = true, logistic_network = true, signal_state = true, splitter_filter = true,
    shooting_target = true, commandable = true, chain_signal_state = true, item_request_proxy = true,
    -- A character's hub and cargo pod (LuaControl), nil when it sits in neither.
    hub = true, cargo_pod = true, cargo_pod_origin = true,
  }
  local writable = {
    amount = true, walking_state = true, direction = true, health = true, riding_state = true,
    shooting_state = true, selected_gun_index = true, selected = true, backer_name = true, trains_limit = true,
    train_stop_priority = true, always_on = true, combinator_description = true,
    entity_label = true, artillery_auto_targeting = true, insert_plan = true,
    player = "harness", frozen = "harness", tick_grown = true, units = "harness", owned_plants = "harness",
    cargo_pod_destination = true, cargo_pod_state = "harness",
    held_stack = "harness", held_stack_position = "harness", position = "harness", crafting_progress = "harness",
    speed = "harness", shooting_target = "harness", orientation = "harness",
    relative_turret_orientation = true, torso_orientation = "harness", driver_is_gunner = true,
    crafting_queue_progress = "harness", status = "harness", energy = "harness",
    signal_state = "harness", chain_signal_state = "harness",
    electric_network_id = "harness",
    color = true, character_inventory_slots_bonus = true, grid = "harness", allow_dispatching_robots = true,
    ignore_unprioritised_targets = true,
    mirroring = true, use_filters = true, inserter_filter_mode = true, inserter_stack_size_override = true,
    request_from_buffers = true,
    splitter_input_priority = true, splitter_output_priority = true, splitter_filter = true, power_switch_state = true,
    rocket_silo_status = "harness", send_to_orbit_automatically = true, providing_to_other_platforms = true,
    ignore_unprioritised_targets = true,
  }
  -- Fluid storages (pipes one, machines as the harness sets) and wire connectors, empty until the
  -- harness fills them (F.set_fluid, F.connect). 2.1 has no LuaEntity.fluidbox: storages are read
  -- by index with get_fluid / get_fluid_capacity up to fluids_count, and written with set_fluid.
  local boxes, capacities = {}, {}
  local box_count = (proto.type == "pipe" or proto.type == "storage-tank") and 1 or 0
  local function storage_index(i)
    assert(type(i) == "number" and i >= 1 and i <= box_count, "fluid storage index out of range: " .. tostring(i))
  end
  data.fluids_count = box_count
  data.get_fluid = function(i)
    storage_index(i)
    return boxes[i]
  end
  data.get_fluid_capacity = function(i)
    storage_index(i)
    return capacities[i] or 100
  end
  -- 2.x fluid segments: the harness's F.segments[entity] = {fluid, capacity} stands for the
  -- pipeline the first storage is in (or the entity alone).
  if box_count > 0 then
    data.has_fluid_segment = function(i)
      storage_index(i)
      return true
    end
    data.get_fluid_segment_fluid = function(i)
      storage_index(i)
      local seg = F.segments[data.self]
      return seg and seg.fluid or boxes[i]
    end
    data.get_fluid_segment_capacity = function(i)
      storage_index(i)
      local seg = F.segments[data.self]
      return seg and seg.capacity or capacities[i] or 100
    end
    data.clear_fluid_segment_fluid = function(i)
      storage_index(i)
      local old = boxes[i]
      F.segments[data.self] = nil
      boxes[i] = nil
      return old
    end
    data.remove_fluid = function(spec)
      assert(type(spec) == "table" and type(spec.index) == "number" and type(spec.amount) == "number",
        "remove_fluid{index, amount}")
      storage_index(spec.index)
      local f = boxes[spec.index]
      if f then
        local left = f.amount - spec.amount
        boxes[spec.index] = left > 0 and strict("Fluid", { name = f.name, amount = left, temperature = f.temperature }) or nil
      end
    end
  end
  local function set_fluid(i, fluid, capacity)
    box_count = math.max(box_count, i)
    data.fluids_count = box_count
    boxes[i] = fluid and strict("Fluid", { name = fluid.name, amount = fluid.amount, temperature = fluid.temperature or 15 }) or nil
    capacities[i] = capacity or capacities[i]
  end
  local connectors = {} -- wire type -> {wire_type, connections, owner}
  data.get_wire_connectors = function(create)
    assert(create == false, "get_wire_connectors: pass false")
    local out = {}
    for wire_type, c in pairs(connectors) do
      out[wire_type] = c
    end
    return out
  end
  local function connector(wire_type)
    if not connectors[wire_type] then
      local c = { wire_type = wire_type, connections = {}, owner = false }
      local function index_of(target)
        for i, conn in ipairs(c.connections) do
          if conn.target == target then
            return i
          end
        end
      end
      c.is_connected_to = function(target, ...)
        assert(select("#", ...) == 0 and target and target.wire_type, "is_connected_to(connector)")
        return index_of(target) ~= nil
      end
      c.can_wire_reach = function(target)
        local a, b = c.owner.position, target.owner.position
        return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2) <= (F.wire_reach or 9)
      end
      c.connect_to = function(target, reach_check, ...)
        assert(select("#", ...) == 0 and target and target.wire_type == c.wire_type, "connect_to(connector of the same wire type, reach_check?)")
        if index_of(target) then
          return false
        end
        table.insert(c.connections, { target = target })
        table.insert(target.connections, { target = c })
        return true
      end
      c.disconnect_from = function(target, ...)
        assert(select("#", ...) == 0, "disconnect_from(connector)")
        local i, j = index_of(target), nil
        for k, conn in ipairs(target.connections) do
          if conn.target == c then
            j = k
          end
        end
        if i then
          table.remove(c.connections, i)
        end
        if j then
          table.remove(target.connections, j)
        end
        return i ~= nil
      end
      c.disconnect_all = function(...)
        assert(select("#", ...) == 0, "disconnect_all()")
        for _, conn in ipairs(c.connections) do
          local other = conn.target.connections
          for k = #other, 1, -1 do
            if other[k].target == c then
              table.remove(other, k)
            end
          end
        end
        c.connections = {}
        return true
      end
      connectors[wire_type] = strict("LuaWireConnector", c)
    end
    return connectors[wire_type]
  end
  if proto.unit_numbered then
    data.unit_number = F.next_unit
    F.next_unit = F.next_unit + 1
  end
  local sb = proto.selection_box
  data.selection_box = {
    left_top = { x = data.position.x + sb.left_top.x, y = data.position.y + sb.left_top.y },
    right_bottom = { x = data.position.x + sb.right_bottom.x, y = data.position.y + sb.right_bottom.y },
  }
  local t = proto.type
  local e = {}
  if t == "transport-belt" or t == "underground-belt" or t == "splitter" or t == "linked-belt" then
    local count = (t == "underground-belt") and 4 or 2
    belt_lines[e] = {}
    for i = 1, count do
      belt_lines[e][i] = {}
    end
    data.get_max_transport_line_index = function() return count end
    data.get_transport_line = function(i)
      assert(belt_lines[e][i], "get_transport_line: no line " .. tostring(i))
      return make_transport_line(e, i)
    end
  end
  if t == "transport-belt" then
    data.belt_shape = "straight"
  elseif t == "underground-belt" then
    data.belt_to_ground_type = params.type or "input"
  elseif t == "linked-belt" then
    data.linked_belt_type = params.linked_belt_type or "input"
  elseif t == "resource" then
    data.amount = params.amount or 3
  elseif t == "car" or t == "locomotive" or t == "cargo-wagon" then
    -- A vehicle: a driver's seat (and a car's passenger seat), a burner, speed. Getting in moves
    -- the character to the vehicle; getting out puts it two tiles east of it.
    data.orientation = 0.25
    data.speed = 0
    data.burner = strict("LuaBurner", { remaining_burning_fuel = 0, inventory = make_inventory() })
    local seats = {}
    local function seat(name, who)
      local old = seats[name]
      if old then
        old.vehicle_seat(nil)
      end
      seats[name] = who
      if who then
        assert(who.type == "character", "set_" .. name .. ": expected a character")
        who.vehicle_seat(e)
      end
    end
    data.get_driver = function() return seats.driver end
    data.set_driver = function(who) seat("driver", who) end
    if t == "car" then
      data.get_passenger = function() return seats.passenger end
      data.set_passenger = function(who) seat("passenger", who) end
    else
      data.train = make_train({ e })
      F.train_setters[e] = function(train) data.train = train end
    end
  elseif t == "spider-vehicle" then
    -- A spidertron: its name, colour, auto targeting and autopilot waypoints (2.1's SpiderVehicle).
    data.entity_label = ""
    data.orientation, data.speed = 0, 0
    data.color = { r = 1, g = 0.5, b = 0, a = 1 }
    local targeting = { auto_target_without_gunner = true, auto_target_with_gunner = false }
    local waypoints = {}
    data.add_autopilot_destination = function(p)
      assert(type(p) == "table" and type(p.x or p[1]) == "number", "add_autopilot_destination(MapPosition)")
      waypoints[#waypoints + 1] = { x = p.x or p[1], y = p.y or p[2] }
    end
    F.spider_fields = F.spider_fields or setmetatable({}, { __mode = "k" })
    F.spider_fields[data] = {
      get = function(k)
        if k == "vehicle_automatic_targeting_parameters" then
          return { auto_target_without_gunner = targeting.auto_target_without_gunner,
            auto_target_with_gunner = targeting.auto_target_with_gunner }
        elseif k == "autopilot_destinations" then
          local out = {}
          for i, w in ipairs(waypoints) do
            out[i] = { x = w.x, y = w.y }
          end
          return out
        elseif k == "autopilot_destination" then
          return waypoints[1]
        end
      end,
      set = function(k, v)
        if k == "vehicle_automatic_targeting_parameters" then
          assert(type(v) == "table" and type(v.auto_target_with_gunner) == "boolean"
            and type(v.auto_target_without_gunner) == "boolean", "VehicleAutomaticTargetingParameters")
          targeting = { auto_target_without_gunner = v.auto_target_without_gunner, auto_target_with_gunner = v.auto_target_with_gunner }
          return true
        elseif k == "autopilot_destination" then
          waypoints = v and { { x = v.x or v[1], y = v.y or v[2] } } or {}
          return true
        end
      end,
    }
  elseif t == "artillery-turret" or t == "artillery-wagon" then
    data.artillery_auto_targeting = true
  elseif t == "heat-pipe" then
    data.temperature = params.temperature or 15
  elseif t == "pipe" then
    -- 2.x: a pipe's four ordinary connections, each to whatever pipe stands on the next tile.
    data.get_fluid_box_pipe_connections = function(i)
      assert(i == 1, "get_fluid_box_pipe_connections: a pipe has one fluid box")
      local out = {}
      for _, d in ipairs({ { 0, -1 }, { 1, 0 }, { 0, 1 }, { -1, 0 } }) do
        local tx, ty = data.position.x + d[1], data.position.y + d[2]
        local target = nil
        for _, other in ipairs(surface.entities) do
          if other.valid and other.type == "pipe" and other.position.x == tx and other.position.y == ty then
            target = other
          end
        end
        -- A plain table: `target` is optional (nil when nothing is connected there).
        out[#out + 1] = {
          connection_type = "normal", flow_direction = "input-output",
          position = { x = data.position.x + d[1] * 0.5, y = data.position.y + d[2] * 0.5 },
          target_position = { x = tx, y = ty }, target = target,
        }
      end
      return out
    end
  elseif t == "logistic-container" or t == "roboport" then
    data.logistic_network = F.network
    if t == "roboport" then
      -- Its logistic cell (H14): neighbours are the roboports whose logistic squares meet its own.
      local r = proto.logistic_radius or 25
      data.logistic_cell = setmetatable({ valid = true, object_name = "LuaLogisticCell", logistic_radius = r,
        construction_radius = proto.construction_radius or 55, logistics_connection_distance = r }, {
        __index = function(_, k)
          if k == "owner" then
            return data.self
          elseif k == "neighbours" then
            local out, p = {}, data.position
            for _, o in pairs(data.surface.find_entities_filtered({ area = { { p.x - 2 * r, p.y - 2 * r }, { p.x + 2 * r, p.y + 2 * r } },
              type = "roboport" })) do
              if o ~= data.self then
                out[#out + 1] = o.logistic_cell
              end
            end
            return out
          end
          error("LuaLogisticCell doesn't contain key " .. tostring(k), 2)
        end,
      })
    end
    if proto.logistic_mode == "requester" then
      -- The requester point carries the sections and "trash unrequested" (machine_info.lua).
      local sections = make_sections(true)
      data.get_logistic_sections = function() return sections end
      data.get_logistic_point = function(i)
        assert(i == defines.logistic_member_index.logistic_container, "get_logistic_point(logistic_container)")
        return sections
      end
      data.request_from_buffers = false
    elseif proto.logistic_mode == "storage" then
      local filter = nil
      data.get_filter = function(i)
        assert(i == 1, "a storage chest has one filter")
        -- 2.1 gives prototypes, not names (seen in 2.1.23).
        return filter and { name = item_protos[filter], quality = { name = "normal" } } or nil
      end
      data.set_filter = function(...)
        local i, item = ...
        assert(i == 1 and (select("#", ...) == 1 or item ~= nil), "set_filter(1) clears; set_filter(1, item) sets")
        assert(item == nil or item_protos[item], "unknown item " .. tostring(item))
        filter = item
      end
    end
  elseif t == "cliff" then
    data.cliff_orientation = params.cliff_orientation or "west-to-east"
  elseif t == "plant" then
    data.tick_grown = params.tick_grown or 0
  elseif t == "unit-spawner" then
    data.units = {}
  elseif t == "agricultural-tower" then
    data.owned_plants = {}
  elseif t == "cargo-pod" then
    local passenger = nil
    data.cargo_pod_state = "awaiting_launch"
    data.cargo_pod_destination = { type = defines.cargo_destination.invalid }
    data.cargo_pod_origin = params.origin
    -- As in 2.1.23, a character sitting in a hub can't become a passenger: nothing happens.
    data.set_passenger = function(who)
      assert(who == nil or who.type == "character", "set_passenger: a character")
      if who and who.hub then
        return
      end
      if passenger and passenger.valid then
        F.entity_data(passenger).cargo_pod = nil
      end
      passenger = who
      F.pod_passenger = who
      if who then
        F.entity_data(who).cargo_pod = e
        F.entity_data(who).position = { x = data.position.x, y = data.position.y }
      end
    end
    data.get_passenger = function() return passenger end
    data.force_finish_ascending = function()
      assert(data.cargo_pod_destination.type ~= defines.cargo_destination.invalid, "force_finish_ascending: no destination")
      data.cargo_pod_state = "descending"
    end
  elseif t == "space-platform-hub" then
    data.create_cargo_pod = function(...)
      assert(select("#", ...) == 0, "create_cargo_pod: leave the optional params out")
      return surface.create_entity({ name = "cargo-pod", position = { x = data.position.x - 2, y = data.position.y }, force = data.force, origin = e })
    end
    local sections = make_sections(false)
    data.get_logistic_sections = function() return sections end
    data.providing_to_other_platforms = false
    data.status = defines.entity_status.working
  elseif t == "cargo-landing-pad" then
    local sections = make_sections(false)
    data.get_logistic_sections = function() return sections end
    local behavior = nil
    data.get_control_behavior = function() return behavior end
    data.get_or_create_control_behavior = function()
      behavior = behavior or strict("LuaCargoLandingPadControlBehavior", { read_contents = true, set_requests = false, read_empty_slots = false })
      return behavior
    end
  elseif t == "radar" then
    data.status = defines.entity_status.working
  elseif t == "rocket-silo" then
    data.rocket_parts = 0
    data.rocket_silo_status = defines.rocket_silo_status.building_rocket
    data.send_to_orbit_automatically = false
    data.status = defines.entity_status.working
    -- false while no rocket stands ready, as in the game; the harness sets rocket_silo_status.
    -- launch_rocket(destination?, character?): positional in 2.1.23.
    data.launch_rocket = function(dest, character)
      assert(type(dest) == "table" and dest.type and dest.destination == nil, "launch_rocket(destination {type, ...}, character?)")
      if data.rocket_silo_status ~= defines.rocket_silo_status.rocket_ready then
        return false
      end
      F.launched = dest
      data.rocket_silo_status = defines.rocket_silo_status.launch_started
      if character then
        -- The character goes into the rocket's cargo pod, at the top of the rocket.
        local pod = surface.create_entity({ name = "cargo-pod", position = { x = data.position.x, y = data.position.y - 4.8 }, force = data.force, origin = e })
        pod.cargo_pod_destination = dest
        pod.set_passenger(character)
      end
      return true
    end
  elseif t == "asteroid-collector" then
    local filters = {}
    -- 2.1.23 says 0 filter slots for a collector, yet set_filter takes any slot.
    data.filter_slot_count = 0
    data.status = defines.entity_status.working
    data.get_filter = function(i)
      assert(i >= 1, "get_filter: slot out of range")
      return filters[i] and asteroid_chunks[filters[i]] or nil
    end
    data.set_filter = function(...)
      local i, f = ...
      assert(i >= 1, "set_filter: slot out of range")
      assert(select("#", ...) == 2, "set_filter(i, nil) clears")
      assert(f == nil or asteroid_chunks[f], "set_filter: an asteroid chunk name")
      filters[i] = f
    end
  elseif t == "train-stop" then
    data.backer_name = params.backer_name or "Stop"
    data.trains_count = 0
    data.train_stop_priority = 50
    -- LuaTrainStopControlBehavior: made on first use, like the game's get_or_create.
    local behavior = nil
    local fields = { circuit_enable_disable = false, send_to_train = true, read_from_train = false, read_stopped_train = false,
      set_trains_limit = false, read_trains_count = false, set_priority = false }
    local signals = { stopped_train_signal = true, trains_limit_signal = true, trains_count_signal = true, priority_signal = true,
      circuit_condition = true }
    local function make_behavior()
      local vals = {}
      return setmetatable({}, {
        __index = function(_, k)
          if fields[k] ~= nil then
            return vals[k] == nil and fields[k] or vals[k]
          elseif signals[k] then
            return vals[k]
          end
          error("LuaTrainStopControlBehavior doesn't contain key " .. tostring(k), 2)
        end,
        __newindex = function(_, k, v)
          assert(fields[k] ~= nil or signals[k], "LuaTrainStopControlBehavior: can't write " .. tostring(k))
          if fields[k] ~= nil then
            assert(type(v) == "boolean", k .. " is a boolean")
          elseif v ~= nil and k ~= "circuit_condition" then
            assert(type(v.name) == "string" and type(v.type) == "string", k .. " is a SignalID")
          end
          vals[k] = v
        end,
      })
    end
    data.get_control_behavior = function() return behavior end
    data.get_or_create_control_behavior = function()
      behavior = behavior or make_behavior()
      return behavior
    end
    data.get_circuit_network = function(id)
      assert(id == defines.wire_connector_id.circuit_red or id == defines.wire_connector_id.circuit_green, "get_circuit_network(wire connector id)")
      return nil
    end
    data.get_stopped_train = function() return nil end
    data.get_train_stop_trains = function() return F.stop_trains[e] or {} end
  elseif t == "item-entity" then
    local st = params.stack
    data.stack = strict("LuaItemStack", { valid_for_read = true, name = st.name, count = st.count or 1 })
  elseif t == "lab" then
    data.status = defines.entity_status.missing_science_packs
    data.electric_network_id = 1
  elseif t == "assembling-machine" or t == "furnace" or t == "lamp" then
    data.status = defines.entity_status.working
    -- Within reach of a pole; nil (2.1) when out of reach of every pole.
    data.electric_network_id = 1
    if t == "assembling-machine" then
      data.electric_buffer_size, data.energy = 1000, 1000
      -- Joules a tick (2.5 kW), and the modules' and beacons' consumption effect (-0.8 at the most).
      data.electric_drain, data.consumption_bonus = 2500 / 60, 0
    end
  elseif t == "electric-pole" then
    -- The pole's network: consumption and production, and its accumulators' storage.
    data.electric_network_statistics = F.flow_statistics and F.flow_statistics("electric") or nil
    -- 2.1: the pole's sub network, whose parent has the last update's flow (joules per tick).
    local network = strict("LuaElectricNetwork", { valid = true, object_name = "LuaElectricNetwork",
      flow_last_tick = { maximum_consumption = 1000, consumption_satisfaction = 0.5, maximum_production = 2000,
        production_satisfaction = 0.25, accumulator_energy = 2500000, accumulator_capacity = 5000000,
        total_transfer = 500, primary_output = 0, secondary_output = 2000, tertiary_output = 0, solar_output = 0,
        primary_demand = 0, secondary_demand = 1000, tertiary_demand = 0, lamp_satisfaction = 1 } })
    data.electric_network = strict("LuaElectricSubNetwork", { valid = true, object_name = "LuaElectricSubNetwork",
      id = 1, parent_network = network })
  elseif t == "power-switch" then
    data.power_switch_state = false
  elseif t == "ammo-turret" then
    -- Priority targets by index (set_priority_target(i) clears one and closes the gap).
    local targets = {}
    data.ignore_unprioritised_targets = false
    -- 2.1.23 counts arguments: clearing a slot needs an explicit nil.
    data.set_priority_target = function(...)
      local i, name = ...
      assert(select("#", ...) == 2 and type(i) == "number" and i >= 1 and i <= #targets + 1, "set_priority_target(index, entity_id or nil)")
      if name == nil then
        table.remove(targets, i)
      else
        assert(entity_protos[name], "set_priority_target: unknown entity " .. tostring(name))
        targets[i] = entity_protos[name]
      end
    end
    setmetatable(data, { __index = function(_, k)
      if k == "priority_targets" then
        local out = {}
        for i, proto in ipairs(targets) do
          out[i] = proto
        end
        return out
      end
    end })
  elseif t == "splitter" then
    data.splitter_input_priority, data.splitter_output_priority = "none", "none"
  elseif t == "inserter" then
    -- Filters by slot (fast and bulk inserters have five); the rest have none.
    local filters = {}
    data.filter_slot_count = proto.filter_count or 0
    data.use_filters = false
    data.inserter_filter_mode = "whitelist"
    data.inserter_stack_size_override = 0
    data.inserter_target_pickup_count = 1
    data.get_filter = function(i)
      assert(i >= 1 and i <= data.filter_slot_count, "get_filter: slot out of range")
      return filters[i] and { name = filters[i], quality = "normal", comparator = "=" } or nil
    end
    data.set_filter = function(i, f)
      assert(i >= 1 and i <= data.filter_slot_count, "set_filter: slot out of range")
      assert(f == nil or type(f) == "string", "set_filter: an item name or nil")
      filters[i] = f
    end
    -- An empty hand resting over the pickup side.
    local d = data.direction / 16 * 2 * math.pi
    data.held_stack_position = { x = data.position.x - math.sin(d), y = data.position.y + math.cos(d) }
    data.held_stack = strict("LuaItemStack", { valid_for_read = false })
    -- No control behaviour until it is wired or asked for (get_or_create_control_behavior).
    local behavior = nil
    local function check_condition(c)
      assert(type(c) == "table" and type(c.comparator) == "string" and type(c.constant) == "number",
        "a CircuitConditionDefinition {first_signal?, comparator, constant, second_signal?}")
      for _, k in pairs({ "first_signal", "second_signal" }) do
        assert(c[k] == nil or (type(c[k].type) == "string" and type(c[k].name) == "string"), k .. " is a SignalID")
      end
    end
    data.get_control_behavior = function() return behavior end
    data.get_or_create_control_behavior = function()
      if not behavior then
        local vals = { circuit_enable_disable = false, connect_to_logistic_network = false,
          circuit_condition = { comparator = "<", constant = 0 }, logistic_condition = { comparator = "<", constant = 0 } }
        behavior = setmetatable({}, {
          __index = function(_, k)
            assert(vals[k] ~= nil, "LuaInserterControlBehavior doesn't contain key " .. tostring(k))
            return vals[k]
          end,
          __newindex = function(_, k, v)
            assert(vals[k] ~= nil, "LuaInserterControlBehavior: can't write " .. tostring(k))
            if k == "circuit_condition" or k == "logistic_condition" then
              check_condition(v)
            else
              assert(type(v) == "boolean", k .. " is a boolean")
            end
            vals[k] = v
          end,
        })
      end
      return behavior
    end
  end

  if t == "inserter" or t == "lamp" then
    -- LuaInserterControlBehavior / LuaLampControlBehavior: made on first use; every field typed.
    local fields = { circuit_enable_disable = "b", circuit_condition = "c", connect_to_logistic_network = "b",
      logistic_condition = "c" }
    if t == "inserter" then
      for k, v in pairs({ circuit_set_filters = "b", circuit_read_hand_contents = "b", circuit_hand_read_mode = "n",
        circuit_set_stack_size = "b", circuit_stack_control_signal = "s" }) do
        fields[k] = v
      end
    else
      for k, v in pairs({ use_colors = "b", color_mode = "n", red_signal = "s", green_signal = "s", blue_signal = "s",
        rgb_signal = "s" }) do
        fields[k] = v
      end
    end
    local defaults = { b = false, n = 0 }
    local behavior = nil
    local function make_behavior()
      local vals = { type = defines.control_behavior.type[t] }
      return setmetatable({}, {
        __index = function(_, k)
          if k == "type" then
            return vals.type
          elseif fields[k] then
            if vals[k] == nil and fields[k] == "c" then
              return { comparator = "<", constant = 0, fulfilled = false }
            end
            return vals[k] == nil and defaults[fields[k]] or vals[k]
          end
          error("Lua" .. (t == "lamp" and "Lamp" or "Inserter") .. "ControlBehavior doesn't contain key " .. tostring(k), 2)
        end,
        __newindex = function(_, k, v)
          local kind = fields[k]
          assert(kind, "control behaviour: can't write " .. tostring(k))
          if kind == "b" then
            assert(type(v) == "boolean", k .. " is a boolean")
          elseif kind == "n" then
            assert(type(v) == "number", k .. " is a define")
          elseif kind == "s" then
            assert(v == nil or (type(v.name) == "string" and type(v.type) == "string"), k .. " is a SignalID or nil")
          else
            assert(type(v) == "table" and type(v.comparator) == "string", k .. " is a CircuitConditionDefinition")
          end
          vals[k] = v
        end,
      })
    end
    data.get_control_behavior = function() return behavior end
    data.get_or_create_control_behavior = function()
      behavior = behavior or make_behavior()
      return behavior
    end
    data.get_circuit_network = function(id)
      assert(id == defines.wire_connector_id.circuit_red or id == defines.wire_connector_id.circuit_green, "get_circuit_network(wire connector id)")
      return F.networks[e] and F.networks[e][id] or nil
    end
    if t == "lamp" then
      data.color = { r = 1, g = 1, b = 1, a = 1 }
      data.always_on = false
    end
  end

  -- Inventories by role. get_inventory knows two indexes: 1 (chest) and 2 (crafter, furnace or
  -- lab input), the way defines.inventory numbers them in 2.0.
  local invs = {}
  if t == "container" or t == "logistic-container" then
    invs.chest = make_inventory()
    if proto.logistic_mode == "requester" then
      invs.trash = make_inventory(10)
    end
  elseif t == "roboport" then
    invs.robots, invs.repair = make_inventory(7), make_inventory(7)
  elseif t == "logistic-robot" then
    invs.robot_cargo = make_inventory(1)
  elseif t == "cargo-wagon" then
    invs.cargo = make_inventory(40)
  elseif t == "assembling-machine" then
    invs.input, invs.output, invs.modules = make_inventory(6), make_inventory(4), make_inventory(2)
    rawset(invs.modules, "index", defines.inventory.crafter_modules)
  elseif t == "space-platform-hub" then
    invs.chest, invs.trash = make_inventory(40), make_inventory(10)
  elseif t == "cargo-landing-pad" then
    invs.chest, invs.trash = make_inventory(40), make_inventory(10)
  elseif t == "rocket-silo" then
    invs.input, invs.rocket, invs.trash = make_inventory(3), make_inventory(10), make_inventory(2)
  elseif t == "furnace" then
    invs.input, invs.output, invs.fuel = make_inventory(1), make_inventory(1), make_inventory(1)
  elseif t == "lab" then
    invs.input, invs.modules = make_inventory(3), make_inventory(2)
    rawset(invs.modules, "index", defines.inventory.lab_modules)
  elseif t == "beacon" then
    invs.modules = make_inventory(2)
    rawset(invs.modules, "index", defines.inventory.beacon_modules)
  end
  if t == "ammo-turret" then
    invs.turret_ammo = make_inventory(1)
  elseif t == "car" or t == "spider-vehicle" or t == "artillery-turret" or t == "artillery-wagon" then
    invs.vehicle_ammo = make_inventory(t == "artillery-turret" and 1 or 3)
  end
  -- Where turrets point (the weapon's orientation; a vehicle's turret relative to its body), as
  -- turrets.lua reads them; the harness turns them.
  if t == "ammo-turret" or t == "electric-turret" or t == "fluid-turret" then
    data.orientation = 0
  elseif t == "car" or t == "artillery-turret" or t == "artillery-wagon" then
    data.relative_turret_orientation = 0
  end
  if t == "spider-vehicle" then
    data.torso_orientation = 0
  end
  if t == "car" or t == "spider-vehicle" then
    data.driver_is_gunner = true
    data.selected_gun_index = 1
  end
  data.self = e
  F.datas[e] = data
  if t == "car" or t == "spider-vehicle" or t == "locomotive" or t == "cargo-wagon" then
    F.by_unit[data.unit_number] = e
  end
  F.inventories[e] = invs
  data.mirroring = false
  -- Copies what the fake knows of settings: an assembler's recipe (the old ingredients come back).
  data.copy_settings = function(source)
    assert(source and source.valid, "copy_settings: a valid entity")
    if t == "assembling-machine" and source.type == "assembling-machine" then
      local r = source.get_recipe()
      return data.set_recipe(r and r.name or nil)
    end
    return {}
  end
  -- Circuit signals the harness puts on the entity's networks (F.signals[e][connector id]).
  data.get_signals = function(connector)
    local by = F.signals[e]
    return by and by[connector] or nil
  end
  if t == "arithmetic-combinator" or t == "decider-combinator" or t == "constant-combinator" or t == "selector-combinator" then
    data.combinator_description = ""
  end
  if t == "arithmetic-combinator" then
    local behavior = { parameters = { first_signal = { type = "item", name = "iron-plate" }, second_constant = 2, operation = "*",
      output_signal = { type = "item", name = "iron-plate" } } }
    data.get_control_behavior = function() return behavior end
  elseif t == "constant-combinator" then
    -- Sections: filters, group ("" none), active, multiplier; logistic groups are shared.
    local function new_section(group)
      return strict("LuaLogisticSection", { filters = {}, group = group or "", active = true, multiplier = 1, is_manual = true })
    end
    local sections = { new_section() }
    local behavior = setmetatable({ enabled = true }, {
      __index = function(_, k)
        if k == "get_section" then
          return function(i) return sections[i] end
        elseif k == "sections_count" then
          return #sections
        elseif k == "add_section" then
          return function(group)
            sections[#sections + 1] = new_section(group)
            return sections[#sections]
          end
        elseif k == "remove_section" then
          return function(i)
            assert(sections[i], "remove_section: no section " .. tostring(i))
            table.remove(sections, i)
            return true
          end
        end
        error("LuaConstantCombinatorControlBehavior doesn't contain key " .. tostring(k), 2)
      end,
    })
    data.get_control_behavior = function() return behavior end
  end
  F.fluid_setters[e] = set_fluid
  -- By connector id: the fake keeps one connector per wire type (no combinator output side).
  data.get_wire_connector = function(id, create)
    assert(type(id) == "number" and type(create) == "boolean", "get_wire_connector(id, or_create)")
    local ids = defines.wire_connector_id
    local wire_type = (id == ids.circuit_red or id == ids.combinator_output_red) and defines.wire_type.red
      or (id == ids.circuit_green or id == ids.combinator_output_green) and defines.wire_type.green
      or defines.wire_type.copper
    if wire_type == defines.wire_type.copper and t ~= "electric-pole" and t ~= "power-switch" then
      return nil
    end
    local c = connector(wire_type)
    rawset(c, "owner", e)
    return c
  end
  F.connectors[e] = function(wire_type)
    local c = connector(wire_type)
    rawset(c, "owner", e)
    return c
  end
  data.get_inventory = function(i)
    local by_define = { [14] = "chest", [15] = "trash", [16] = "chest", [17] = "trash", [18] = "rocket", [19] = "trash" }
    if by_define[i] then
      local here = (t == "space-platform-hub" and i <= 15) or (t == "cargo-landing-pad" and (i == 16 or i == 17))
        or (t == "rocket-silo" and i >= 18)
      return here and invs[by_define[i]] or nil
    end
    if i == defines.inventory.turret_ammo then
      return invs.turret_ammo
    elseif (i == defines.inventory.car_ammo and t == "car") or (i == defines.inventory.spider_ammo and t == "spider-vehicle")
      or (i == defines.inventory.artillery_turret_ammo and t == "artillery-turret")
      or (i == defines.inventory.artillery_wagon_ammo and t == "artillery-wagon") then
      return invs.vehicle_ammo
    elseif i == 1 then
      return invs.chest
    elseif i == 2 then
      return invs.input
    elseif i == 5 then
      return invs.cargo
    elseif i == 6 then
      return invs.trash
    elseif i == 7 then
      return invs.robots
    elseif i == 8 then
      return invs.repair
    elseif i == 9 then
      return invs.robot_cargo
    end
    return nil
  end
  data.get_output_inventory = function() return invs.output end
  data.get_fuel_inventory = function() return invs.fuel end
  data.get_burnt_result_inventory = function() return nil end
  data.get_module_inventory = function() return invs.modules end

  local recipe = nil
  if t == "container" or t == "assembling-machine" or t == "furnace" or t == "lab" or t == "ammo-turret" then
    -- Where the game would put an inserted item: fuel in the fuel slot, ingredients (any item,
    -- here) in the input once a recipe is set.
    data.insert = function(stack)
      local target = invs.chest or invs.input or invs.turret_ammo
      if t == "furnace" and (stack.name == "coal" or stack.name == "wood") then
        target = invs.fuel
      elseif t == "assembling-machine" and not recipe then
        return 0
      end
      return target.insert(stack)
    end
    data.can_insert = function(stack) return true end
  end
  local recipe_quality = qualities.normal
  if t == "assembling-machine" or t == "furnace" then
    data.crafting_progress = 0
    -- 2.x returns the recipe and its quality.
    data.get_recipe = function()
      if t == "furnace" then
        return invs.input.get_item_count("iron-ore") > 0 and forces.player.recipes["iron-plate"] or nil, qualities.normal
      end
      return recipe, recipe and recipe_quality or nil
    end
    -- Module and beacon effects (2.x: plain numbers); the harness sets F.effects.
    data.effects = F.effects or {}
  end
  -- Beacons and what they reach: within 5 tiles here; the game uses the beacon's supply area.
  local function near(types)
    local p = data.position
    return data.surface.find_entities_filtered({ area = { { p.x - 5, p.y - 5 }, { p.x + 5, p.y + 5 } }, type = types })
  end
  if t == "assembling-machine" or t == "furnace" or t == "lab" or t == "mining-drill" or t == "rocket-silo" then
    data.get_beacons = function() return near("beacon") end
  elseif t == "beacon" then
    data.effects = F.effects or {}
    data.get_beacon_effect_receivers = function() return near({ "assembling-machine", "furnace", "lab", "mining-drill" }) end
  end
  if t == "assembling-machine" then
    -- Changing the recipe empties the machine and returns what was in it (2.x shape).
    data.set_recipe = function(name, quality)
      assert(quality == nil or (name ~= nil and qualities[quality]), "set_recipe(name, quality?)")
      recipe_quality = qualities[quality or "normal"]
      if name ~= nil and not forces.player.recipes[name] then
        error("Unknown recipe " .. tostring(name))
      end
      local returned = {}
      for _, inv in pairs({ invs.input, invs.output }) do
        for _, it in pairs(inv.get_contents()) do
          returned[#returned + 1] = { name = it.name, count = it.count, quality = it.quality }
          inv.remove(it)
        end
      end
      recipe = name and forces.player.recipes[name] or nil
      data.crafting_progress = 0
      return returned
    end
  end

  data.destroy = function(p)
    if p and p.raise_destroy then
      raise("script_raised_destroy", { entity = e })
    end
    if F.registered[e] then
      F.destroyed_queue[#F.destroyed_queue + 1] = F.registered[e]
    end
    for i, other in ipairs(data.surface.entities) do
      if other == e then
        table.remove(data.surface.entities, i)
        break
      end
    end
    data.valid = false
    return true
  end
  data.teleport = function(position, to)
    assert(type(position) == "table", "teleport(position, surface?)")
    to = to or data.surface
    -- 2.1.23: a character in a hub doesn't move on its own surface; another surface takes it out.
    if data.hub and to == data.surface then
      return false
    end
    data.hub = nil
    if to ~= data.surface then
      assert(t == "character" or t == "car", "teleport: only characters and cars cross surfaces")
      for i, other in ipairs(data.surface.entities) do
        if other == e then
          table.remove(data.surface.entities, i)
          break
        end
      end
      to.entities[#to.entities + 1] = e
      data.surface = to
    end
    data.position = { x = position.x or position[1], y = position.y or position[2] }
    return true
  end
  data.rotate = function(p)
    data.direction = (data.direction + ((p and p.reverse) and -4 or 4)) % 16
    return true
  end
  data.deplete = function()
    raise("on_resource_depleted", { entity = e })
    data.destroy()
  end

  if t == "character" then
    local requester = make_sections(true)
    data.color = { r = 1, g = 0.63, b = 0.26, a = 1 }  -- the default player colour
    -- Only once the force has researched character logistics (2.1.23: nil before).
    data.get_requester_point = function()
      if forces.player.character_logistic_requests then
        return requester
      end
      return nil
    end
    data.clear_selected_entity = function() data.selected = nil end
    local inventory = make_inventory(80)
    local queue = {}
    data.crafting_queue_progress = 0
    local guns, gun_slots = make_slots(3)
    local ammo, ammo_slots = make_slots(3)
    F.slots[e] = { guns = gun_slots, ammo = ammo_slots }
    data.health, data.max_health = 250, 250
    data.shooting_state = { state = defines.shooting.not_shooting, position = { x = 0, y = 0 } }
    data.selected_gun_index = 1
    local armor, trash = make_inventory(1), make_inventory(10)
    data.character_inventory_slots_bonus = 0
    data.get_inventory = function(i)
      if i == defines.inventory.character_guns then
        return guns
      elseif i == defines.inventory.character_ammo then
        return ammo
      elseif i == defines.inventory.character_main then
        return inventory
      elseif i == defines.inventory.character_armor then
        return armor
      elseif i == defines.inventory.character_trash then
        return trash
      end
      return nil
    end
    data.walking_state = { walking = false, direction = 0 }
    data.riding_state = { acceleration = defines.riding.acceleration.nothing, direction = defines.riding.direction.straight }
    data.vehicle_seat = function(v)
      if v then
        data.position = { x = v.position.x, y = v.position.y }
      elseif data.vehicle then
        data.position = { x = data.vehicle.position.x + 2, y = data.vehicle.position.y }
      end
      data.vehicle = v
    end
    data.allow_dispatching_robots = true
    data.reach_distance = 10
    data.build_distance = 10
    data.drop_item_distance = 10
    data.resource_reach_distance = 2.7
    data.item_pickup_distance = 1
    data.character_mining_speed_modifier = 0
    data.crafting_queue_size = 0
    data.get_main_inventory = function() return inventory end
    -- Guns and ammo go to their own inventories, the way the game sorts them.
    data.insert = function(stack)
      local slots = (stack.name == "pistol" and gun_slots) or (stack.name == "firearm-magazine" and ammo_slots) or nil
      if not slots then
        return inventory.insert(stack)
      end
      for _, slot in ipairs(slots) do
        if not slot.name or slot.name == stack.name then
          slot.name, slot.count = stack.name, (slot.count or 0) + (stack.count or 1)
          slot.ammo = slots == ammo_slots and 10 or nil
          return stack.count or 1
        end
      end
      return 0
    end
    data.can_insert = function(stack) return true end
    -- Reach is measured to the target's selection box, like the game.
    data.can_reach_entity = function(target)
      local b, p = target.selection_box, data.position
      local dx = math.max(b.left_top.x - p.x, 0, p.x - b.right_bottom.x)
      local dy = math.max(b.left_top.y - p.y, 0, p.y - b.right_bottom.y)
      return math.sqrt(dx * dx + dy * dy) <= data.reach_distance
    end
    -- LuaControl.mine_tile: the tile's item back, the ground it was laid on back.
    data.mine_tile = function(tile)
      assert(tile.prototype, "mine_tile takes a LuaTile")
      local mp = tile.prototype.mineable_properties
      if not mp.minable then
        return false
      end
      for _, product in pairs(mp.products) do
        inventory.insert({ name = product.name, count = product.amount })
      end
      data.surface.tiles[tile.position.x .. "," .. tile.position.y] = nil
      return true
    end
    -- Without `force` it fails when the products don't fit.
    data.mine_entity = function(target, force)
      assert(force == nil, "mine_entity: leave out force")
      local products = {}
      if target.type == "item-entity" then
        products[1] = { name = target.stack.name, amount = target.stack.count }
      else
        for _, product in pairs(target.prototype.mineable_properties.products) do
          products[#products + 1] = { name = product.name, amount = product.amount }
        end
      end
      for _, product in pairs(products) do
        if F.inventory_space < product.amount then
          return false
        end
        F.inventory_space = F.inventory_space - product.amount
        inventory.insert({ name = product.name, count = product.amount })
      end
      target.destroy()
      return true
    end
    data.begin_crafting = function(p)
      if not forces.player.recipes[p.recipe] then
        error("Unknown recipe " .. p.recipe)
      end
      queue[#queue + 1] = { index = #queue + 1, recipe = p.recipe, count = p.count, prerequisite = false }
      data.crafting_queue_size = data.crafting_queue_size + p.count
      data.crafting_queue = #queue > 0 and queue or nil
      return p.count
    end
    data.cancel_crafting = function(p)
      for k, item in ipairs(queue) do
        if item.index == p.index then
          assert(p.count >= 1 and p.count <= item.count, "cancel_crafting: bad count")
          item.count = item.count - p.count
          data.crafting_queue_size = data.crafting_queue_size - p.count
          if item.count == 0 then
            table.remove(queue, k)
          end
        end
      end
      data.crafting_queue = #queue > 0 and queue or nil
    end
    -- Limited by the ingredients in the main inventory.
    data.get_craftable_count = function(name)
      local recipe = forces.player.recipes[name]
      local n = nil
      for _, ing in pairs(recipe.ingredients) do
        local can = math.floor(inventory.get_item_count(ing.name) / ing.amount)
        n = n and math.min(n, can) or can
      end
      return n or 0
    end
  end

  setmetatable(e, {
    __index = function(_, k)
      if k == "bounding_box" then
        local b, p = proto.collision_box, data.position
        return { left_top = { x = p.x + b.left_top.x, y = p.y + b.left_top.y },
                 right_bottom = { x = p.x + b.right_bottom.x, y = p.y + b.right_bottom.y } }
      end
      local spider = F.spider_fields and F.spider_fields[data]
      if spider and spider.get(k) ~= nil then
        return spider.get(k)
      end
      if k == "item_request_proxy" then
        local proxy = F.proxies[e]
        return proxy and proxy.valid and proxy or nil
      end
      local v = data[k]
      if v == nil and not optional[k] and not (spider and k == "autopilot_destination") then
        error("LuaEntity (" .. t .. ") doesn't contain key " .. tostring(k), 2)
      end
      return v
    end,
    __newindex = function(_, k, v)
      local spider = F.spider_fields and F.spider_fields[data]
      if spider and spider.set(k, v) then
        return
      end
      if not writable[k] then
        error("LuaEntity: can't write " .. tostring(k), 2)
      end
      data[k] = v
    end,
  })
  surface.entities[#surface.entities + 1] = e
  if t == "item-request-proxy" then
    F.proxies[params.target] = e
  end
  if proto.spider_engine and t == "spider-unit" then
    for _, leg in ipairs(proto.spider_engine.legs) do
      make_entity(surface, { name = leg.leg, force = params.force,
        position = { x = data.position.x + leg.ground_position[1], y = data.position.y + leg.ground_position[2] } })
    end
  end
  return e
end

local function bounds(e)
  local b = e.prototype.collision_box
  local p = e.position
  return p.x + b.left_top.x, p.y + b.left_top.y, p.x + b.right_bottom.x, p.y + b.right_bottom.y
end

local function list_has(list, v)
  if type(list) == "string" then
    return list == v
  end
  for _, x in pairs(list) do
    if x == v then
      return true
    end
  end
  return false
end

local function make_surface(index, name, default_tile)
  local surface = {
    index = index, name = name, entities = {}, tiles = {}, daytime = 0.2, darkness = 0, valid = true,
    ticks_per_day = 25000, always_day = false, min_brightness = 0.15, solar_power_multiplier = 1,
    dusk = 0.25, evening = 0.45, morning = 0.55, dawn = 0.75,
    map_gen_settings = { seed = 123456789 }, -- /seed (console.lua)
  }
  -- Surface properties (F.surface_props on the harness side); Nauvis's by default.
  surface.props = { gravity = 10, pressure = 1000, ["magnetic-field"] = 90, ["solar-power"] = 100, ["day-night-cycle"] = 25000 }
  surface.get_property = function(prop)
    assert(prototypes.surface_property[prop], "get_property: unknown surface property " .. tostring(prop))
    return surface.props[prop] or 0
  end
  -- LuaSegmentedUnit: F.add_segmented_unit puts them here.
  surface.segmented = {}
  surface.get_segmented_units = function() return surface.segmented end
  surface.get_tile = function(x, y)
    local n = surface.tiles[x .. "," .. y] or default_tile or ((x < -40) and "water" or "grass-1")
    return strict("LuaTile", { name = n, position = { x = x, y = y }, valid = true, prototype = tile_protos[n],
      get_tile_ghosts = function(force)
        local out = {}
        for _, e in ipairs(surface.entities) do
          if e.type == "tile-ghost" and math.floor(e.position.x) == x and math.floor(e.position.y) == y then
            out[#out + 1] = e
          end
        end
        return out
      end,
      has_tile_ghost = function(force)
        for _, e in ipairs(surface.entities) do
          if e.type == "tile-ghost" and math.floor(e.position.x) == x and math.floor(e.position.y) == y then
            return true
          end
        end
        return false
      end })
  end
  -- 2.x signature: (tiles, correct_tiles, remove_colliding_entities, remove_colliding_decoratives, raise_event).
  surface.set_tiles = function(tiles, correct, remove_entities, remove_decoratives, raise_event)
    assert(type(tiles) == "table" and correct ~= nil and remove_entities ~= nil and remove_decoratives ~= nil and raise_event ~= nil,
      "set_tiles: pass every argument")
    local changed = {}
    for _, t in pairs(tiles) do
      assert(tile_protos[t.name], "set_tiles: unknown tile " .. tostring(t.name))
      surface.tiles[t.position.x .. "," .. t.position.y] = t.name
      changed[#changed + 1] = { position = t.position, old_tile = tile_protos["grass-1"] }
    end
    F.set_tiles_calls = (F.set_tiles_calls or 0) + 1
    if raise_event then
      raise("script_raised_set_tiles", { surface_index = surface.index, tiles = changed })
    end
  end
  surface.count_entities_filtered = function(f)
    local n = 0
    for _, e in pairs(surface.find_entities_filtered(f)) do
      local layers = e.prototype.collision_mask and e.prototype.collision_mask.layers
      local hit = f.collision_mask == nil
      for _, layer in pairs(f.collision_mask or {}) do
        hit = hit or (layers and layers[layer]) or false
      end
      if hit then
        n = n + 1
      end
    end
    return f.limit and math.min(n, f.limit) or n
  end
  surface.count_tiles_filtered = function(f)
    for k in pairs(f) do
      assert(k == "area" or k == "collision_mask" or k == "limit", "count_tiles_filtered: unexpected filter " .. tostring(k))
    end
    local a = f.area
    local x1, y1 = a[1][1] or a[1].x, a[1][2] or a[1].y
    local x2, y2 = a[2][1] or a[2].x, a[2][2] or a[2].y
    local n = 0
    for ty = math.floor(y1), math.ceil(y2) - 1 do
      for tx = math.floor(x1), math.ceil(x2) - 1 do
        local layers = surface.get_tile(tx, ty).prototype.collision_mask.layers
        local hit = f.collision_mask == nil
        for layer in pairs(f.collision_mask or {}) do
          hit = hit or layers[layer] == true
        end
        if hit then
          n = n + 1
        end
      end
    end
    return f.limit and math.min(n, f.limit) or n
  end
  surface.set_tile = function(x, y, n)
    surface.tiles[x .. "," .. y] = n
  end
  -- Decoratives: F.add_decorative puts {name, x, y, amount} here. find_decoratives_filtered
  -- takes only an area (the bridge's one use) and returns 2.x DecorativeResults.
  surface.decoratives = {}
  surface.find_decoratives_filtered = function(f)
    assert(type(f) == "table" and f.area, "find_decoratives_filtered: the bridge passes an area")
    for k in pairs(f) do
      assert(k == "area", "find_decoratives_filtered: unexpected filter " .. tostring(k))
    end
    local a = f.area
    local x1, y1 = a[1][1] or a[1].x, a[1][2] or a[1].y
    local x2, y2 = a[2][1] or a[2].x, a[2][2] or a[2].y
    local out = {}
    for _, d in ipairs(surface.decoratives) do
      if d.x >= x1 and d.x < x2 and d.y >= y1 and d.y < y2 then
        out[#out + 1] = {
          position = { x = d.x, y = d.y },
          decorative = strict("LuaDecorativePrototype", { name = d.name }),
          amount = d.amount,
        }
      end
    end
    return out
  end
  surface.is_chunk_generated = function(c)
    local cx, cy = c.x or c[1], c.y or c[2]
    return math.abs(cx) <= 3 and math.abs(cy) <= 3
  end
  surface.request_to_generate_chunks = function() end
  -- LuaChunkIterator: called again and again, it gives each generated chunk, then nil.
  surface.get_chunks = function()
    local cx, cy = -4, -3
    return function()
      cx = cx + 1
      if cx > 3 then
        cx, cy = -3, cy + 1
      end
      if cy > 3 then
        return nil
      end
      return { x = cx, y = cy, area = { left_top = { x = cx * 32, y = cy * 32 }, right_bottom = { x = cx * 32 + 32, y = cy * 32 + 32 } } }
    end
  end
  surface.find_non_colliding_position = function(name, center) return center end
  surface.find_nearest_enemy = function(p)
    assert(p.position and p.force and p.max_distance, "find_nearest_enemy{position, max_distance, force}")
    local best, best_d
    local px, py = p.position.x or p.position[1], p.position.y or p.position[2]
    local force = type(p.force) == "string" and p.force or p.force.name
    for _, e in ipairs(surface.entities) do
      if e.force.name ~= force and e.force.name ~= "neutral" and (e.type == "unit" or e.type == "unit-spawner" or e.type == "turret") then
        local d = (e.position.x - px) ^ 2 + (e.position.y - py) ^ 2
        if d <= p.max_distance ^ 2 and (not best_d or d < best_d) then
          best, best_d = e, d
        end
      end
    end
    return best
  end
  surface.find_entity = function(name, position)
    for _, e in ipairs(surface.entities) do
      if e.name == name and e.position.x == (position.x or position[1]) and e.position.y == (position.y or position[2]) then
        return e
      end
    end
    return nil
  end
  surface.find_logistic_networks_by_construction_area = function(position, force)
    assert(position and force, "find_logistic_networks_by_construction_area(position, force)")
    if F.construction_networks then
      return F.construction_networks
    end
    -- The force's networks (F.lnets) with a cell whose construction area holds the point.
    local out = {}
    for _, net in pairs(F.lnets[surface.name] or {}) do
      for _, c in pairs(net.cells) do
        if c.is_in_construction_range(position) then
          out[#out + 1] = net
          break
        end
      end
    end
    return out
  end
  surface.find_entities_filtered = function(f)
    local out = {}
    for _, e in ipairs(surface.entities) do
      local ok = true
      local x1, y1, x2, y2 = bounds(e)
      if f.area then
        local a1, a2 = f.area[1] or f.area.left_top, f.area[2] or f.area.right_bottom
        local ax1, ay1 = a1.x or a1[1], a1.y or a1[2]
        local ax2, ay2 = a2.x or a2[1], a2.y or a2[2]
        ok = x1 < ax2 and x2 > ax1 and y1 < ay2 and y2 > ay1
      end
      if ok and f.position and not f.radius then
        local px, py = f.position.x or f.position[1], f.position.y or f.position[2]
        ok = px >= x1 and px <= x2 and py >= y1 and py <= y2
      end
      if ok and f.position and f.radius then
        local px, py = f.position.x or f.position[1], f.position.y or f.position[2]
        local p = e.position
        ok = (p.x - px) ^ 2 + (p.y - py) ^ 2 <= f.radius ^ 2
      end
      if ok then
        local match = true
        if f.type then
          match = match and list_has(f.type, e.type)
        end
        if f.name then
          match = match and list_has(f.name, e.name)
        end
        if f.ghost_name then
          match = match and e.type == "entity-ghost" and list_has(f.ghost_name, e.ghost_name)
        end
        if f.force then
          local want = type(f.force) == "string" and f.force or f.force.name
          match = match and e.force.name == want
        end
        if f.invert then
          match = not match
        end
        ok = match
      end
      if ok then
        out[#out + 1] = e
      end
    end
    return out
  end
  surface.can_place_entity = function(p)
    assert(p.build_check_type ~= nil, "expected a build_check_type")
    local x, y = p.position.x or p.position[1], p.position.y or p.position[2]
    -- Rails are on a layer of their own: only other rails collide with them.
    local rail = entity_protos[p.name].type == "straight-rail"
    -- Space Age: the surface's properties must meet the prototype's surface conditions, and the
    -- tiles mustn't collide with it (empty space). The script check looks at neither (2.1.23).
    local manual = p.build_check_type ~= defines.build_check_type.script
    for _, cond in ipairs(manual and entity_protos[p.name].surface_conditions or {}) do
      local v = surface.props[cond.property] or 0
      if v < cond.min or v > cond.max then
        return false
      end
    end
    local mask = entity_protos[p.name].collision_mask
    if manual and mask then
      local w, h = entity_protos[p.name].tile_width, entity_protos[p.name].tile_height
      if surface.count_tiles_filtered({ area = { { x - w / 2 + 0.1, y - h / 2 + 0.1 }, { x + w / 2 - 0.1, y + h / 2 - 0.1 } },
          collision_mask = mask.layers, limit = 1 }) > 0 then
        return false
      end
    end
    -- 2.1 answers true where the entity could fast-replace what stands there.
    if surface.can_fast_replace({ name = p.name, position = p.position, direction = p.direction, force = p.force }) then
      return true
    end
    for _, e in ipairs(surface.entities) do
      if e.type ~= "resource" and e.type ~= "character" and e.type ~= "entity-ghost" and (e.type == "straight-rail") == rail then
        local x1, y1, x2, y2 = bounds(e)
        if x > x1 and x < x2 and y > y1 and y < y2 then
          return false
        end
      end
    end
    return true
  end
  surface.spill_item_stack = function(p)
    assert(p.position and p.stack, "spill_item_stack takes {position, stack}")
    F.spilled[#F.spilled + 1] = p.stack
    return {}
  end
  -- Fast-replace: an entity of the same fast-replaceable group standing there, of another kind or
  -- quality.
  local function replaceable(p)
    local group = entity_protos[p.name].fast_replaceable_group
    local x, y = p.position.x or p.position[1], p.position.y or p.position[2]
    for _, e in ipairs(surface.entities) do
      if group and e.prototype.fast_replaceable_group == group and e.position.x == x and e.position.y == y
          and (e.name ~= p.name or e.quality.name ~= (p.quality or "normal")) then
        return e
      end
    end
    return nil
  end
  surface.can_fast_replace = function(p)
    assert(p.build_check_type == nil, "can_fast_replace takes no build_check_type")
    return replaceable(p) ~= nil
  end
  surface.create_entity = function(p)
    if p.fast_replace then
      assert(p.spill == false, "fast_replace without a player: pass spill = false")
      local old = replaceable(p)
      assert(old, "create_entity: nothing to fast-replace")
      old.destroy()
    elseif p.name ~= "entity-ghost" and replaceable(p) then
      -- Without fast_replace the game won't build over an entity it would replace: nil.
      return nil
    end
    local e = make_entity(surface, p)
    if p.raise_built then
      raise("script_raised_built", { entity = e })
    end
    return e
  end
  -- Marks what the area holds (not characters, resources or ghosts), raising the game's events.
  local function in_area(area)
    local a1, a2 = area[1], area[2]
    local out = {}
    for _, e in ipairs(surface.entities) do
      local p = e.position
      if p.x >= a1[1] and p.x <= a2[1] and p.y >= a1[2] and p.y <= a2[2]
          and e.type ~= "character" and e.type ~= "resource" and e.type ~= "entity-ghost" and e.type ~= "tile-ghost" then
        out[#out + 1] = e
      end
    end
    return out
  end
  local function mark(p, on)
    assert(p.area and p.force and p.surface == nil, "deconstruct_area takes {area, force}")
    if on then
      -- Ghosts aren't marked: Factorio deletes them at once, with no event (2.1.23).
      local a1, a2 = p.area[1], p.area[2]
      local ghosts = {}
      for _, e in ipairs(surface.entities) do
        local q = e.position
        if (e.type == "entity-ghost" or e.type == "tile-ghost") and q.x >= a1[1] and q.x <= a2[1] and q.y >= a1[2] and q.y <= a2[2] then
          ghosts[#ghosts + 1] = e
        end
      end
      for _, e in ipairs(ghosts) do
        e.destroy()
      end
    end
    for _, e in ipairs(in_area(p.area)) do
      if (F.decon_marks[e] == true) ~= on then
        F.decon_marks[e] = on or nil
        raise(on and "on_marked_for_deconstruction" or "on_cancelled_deconstruction", { entity = e })
      end
    end
  end
  surface.deconstruct_area = function(p) mark(p, true) end
  -- Pollution by chunk "cx,cy" (F.pollution), at any position in it.
  surface.get_pollution = function(p)
    local x, y = p.x or p[1], p.y or p[2]
    return (F.pollution or {})[math.floor(x / 32) .. "," .. math.floor(y / 32)] or 0
  end
  -- 2.1: Vulcanus' demolisher territories; F.territories = {{{x=, y=}, ...}, ...} chunk lists.
  surface.get_territories = function()
    local out = {}
    for i, chunks in ipairs(F.territories or {}) do
      out[i] = strict("LuaTerritory", { get_chunks = function() return chunks end })
    end
    return out
  end
  surface.cancel_deconstruct_area = function(p) mark(p, false) end
  local function planner(p)
    assert(p.surface == surface and p.force and p.area, "planner methods take {surface, force, area}")
    local copy = { area = p.area, force = p.force }
    return copy
  end
  F.planner_methods.build_blueprint = { item = "blueprint", fn = function(p)
    assert(p.surface and p.force and p.position and p.build_mode ~= nil, "build_blueprint takes {surface, force, position, build_mode}")
    F.last_build_mode = p.build_mode
    local made = {}
    for _, b in ipairs(F.blueprint) do
      made[#made + 1] = p.surface.create_entity({
        name = "entity-ghost", inner_name = b.name, force = p.force, raise_built = p.raise_built,
        position = { x = p.position[1] + b.x, y = p.position[2] + b.y },
      })
    end
    return made
  end }
  F.planner_methods.is_blueprint_setup = { item = "blueprint", fn = function() return #F.blueprint > 0 end }
  F.planner_methods.deconstruct_area = { item = "deconstruction-planner", fn = function(p) mark(planner(p), true) end }
  F.planner_methods.cancel_deconstruct_area = { item = "deconstruction-planner", fn = function(p) mark(planner(p), false) end }
  local function upgrade(p, on)
    -- The planner's own mappings when it has any (set_mapper), else the test's F.upgrades.
    local map = F.upgrades
    local h = p.item and stack_handles[p.item]
    local slot = h and h[1][h[2]]
    if slot and slot.mappers and #slot.mappers > 0 then
      map = {}
      for _, m in ipairs(slot.mappers) do
        if m.from and m.from.name and m.to and m.to.name then
          map[m.from.name] = m.to.name
        end
      end
    end
    for _, e in ipairs(in_area(planner(p).area)) do
      local target = map[e.name] and entity_protos[map[e.name]]
      if target and (F.upgrade_marks[e] ~= nil) ~= on then
        F.upgrade_marks[e] = on and target or nil
        raise(on and "on_marked_for_upgrade" or "on_cancelled_upgrade", { entity = e, target = target })
      end
    end
  end
  -- Upgrade planners have no area methods of their own in 2.1: the surface takes the planner as
  -- `item`.
  local function upgrade_spec(p)
    assert(p.area and p.force and p.surface == nil, "upgrade_area takes {area, force, item}")
    assert(p.item and p.item.valid_for_read and p.item.is_upgrade_item, "upgrade_area: item must be an upgrade planner stack")
    return { surface = surface, area = p.area, force = p.force, item = p.item }
  end
  surface.upgrade_area = function(p) upgrade(upgrade_spec(p), true) end
  surface.cancel_upgrade_area = function(p) upgrade(upgrade_spec(p), false) end
  surfaces[index] = surface
  surfaces[name] = surface
  F.game_surfaces[index] = surface
  -- A planet's surface has `planet`, a platform's `platform`; reading the other gives nil.
  return setmetatable(surface, {
    __index = function(_, k)
      if k == "platform" or k == "planet" then
        return nil
      end
      error("LuaSurface doesn't contain key " .. tostring(k), 2)
    end,
  })
end

local nauvis = make_surface(1, "nauvis")
F.make_surface = make_surface
F.surface = nauvis
F.surface_list = {}
local planets = {}
planets.nauvis = strict("LuaPlanet", {
  name = "nauvis", prototype = space_locations.nauvis, surface = nauvis,
  create_surface = function() return nauvis end,
})
rawset(nauvis, "planet", planets.nauvis)
-- Vulcanus's surface doesn't exist until something asks for it.
local vulcanus_surface
planets.vulcanus = setmetatable({ name = "vulcanus", prototype = space_locations.vulcanus }, {
  __index = function(_, k)
    if k == "surface" then
      return vulcanus_surface
    elseif k == "create_surface" then
      return function()
        if not vulcanus_surface then
          vulcanus_surface = make_surface(#F.surface_list + 2, "vulcanus")
          rawset(vulcanus_surface, "planet", planets.vulcanus)
          F.surface_list[#F.surface_list + 1] = vulcanus_surface
        end
        return vulcanus_surface
      end
    end
    error("LuaPlanet doesn't contain key " .. tostring(k), 2)
  end,
})

---------------------------------------------------------------------------------------------
-- space platforms

F.platform_data = setmetatable({}, { __mode = "k" })

-- LuaSpacePlatform. The harness moves it with F.platform_travel and F.platform_arrive.
function F.create_space_platform(p)
  assert(type(p) == "table" and p.planet and p.starter_pack, "create_space_platform{planet, starter_pack}")
  assert(space_locations[p.planet], "create_space_platform: unknown planet " .. tostring(p.planet))
  local pack = type(p.starter_pack) == "table" and p.starter_pack.name or p.starter_pack
  assert(item_protos[pack], "create_space_platform: unknown starter pack " .. tostring(pack))
  local index = #forces.player.platforms + 1
  local data = {
    valid = true, index = index, name = p.name or ("Platform " .. index), force = forces.player,
    state = defines.space_platform_state.waiting_for_starter_pack, paused = true,
    space_location = space_locations[p.planet], speed = 0, scheduled_for_deletion = 0, weight = 1250000,
  }
  local interrupts = {}
  -- Asteroid chunks floating over the platform ({name, position, movement}); the harness adds them.
  data.chunks = {}
  data.find_asteroid_chunks_filtered = function(f)
    assert(type(f) == "table" and f.area, "find_asteroid_chunks_filtered{area, limit?}")
    local a1, a2 = f.area[1], f.area[2]
    local out = {}
    for _, ch in ipairs(data.chunks) do
      if ch.position.x >= a1[1] and ch.position.x <= a2[1] and ch.position.y >= a1[2] and ch.position.y <= a2[2] then
        out[#out + 1] = ch
      end
    end
    return out
  end
  local optional = { space_location = true, space_connection = true, distance = true, hub = true, surface = true, schedule = true }
  local writable = { paused = true, schedule = true, name = true, speed = true }
  local platform = setmetatable({}, {
    __index = function(_, k)
      local v = data[k]
      if v == nil and not optional[k] then
        error("LuaSpacePlatform doesn't contain key " .. tostring(k), 2)
      end
      return v
    end,
    __newindex = function(_, k, v)
      assert(writable[k], "LuaSpacePlatform: can't write " .. tostring(k))
      if k == "schedule" and v ~= nil then
        assert(type(v.records) == "table" and v.current, "schedule = {current, records}")
        local records = {}
        for i, rec in ipairs(v.records) do
          assert(type(rec.station) == "string" and space_locations[rec.station], "schedule record station " .. tostring(rec.station))
          records[i] = { station = rec.station, wait_conditions = {}, allows_unloading = true, temporary = false, created_by_interrupt = false }
        end
        v = { current = v.current, records = records }
      end
      data[k] = v
      if k == "paused" or k == "schedule" then
        F.platform_state(data)
      end
    end,
  })
  data.apply_starter_pack = function()
    if data.hub then
      return nil
    end
    local surface = make_surface(#F.surface_list + 2, "platform-" .. index, "empty-space")
    for y = -8, 7 do
      for x = -8, 7 do
        surface.tiles[x .. "," .. y] = "space-platform-foundation"
      end
    end
    rawset(surface, "platform", platform)
    F.surface_list[#F.surface_list + 1] = surface
    data.surface = surface
    data.hub = surface.create_entity({ name = "space-platform-hub", position = { 0, 0 }, force = forces.player })
    F.platform_state(data)
    return data.hub
  end
  data.get_schedule = function()
    return strict("LuaSchedule", {
      current = data.schedule and data.schedule.current or 0,
      group = "",
      go_to_station = function(i)
        assert(data.schedule and data.schedule.records[i], "go_to_station: no record " .. tostring(i))
        data.schedule = { current = i, records = data.schedule.records }
        F.platform_state(data)
      end,
      get_records = function() return data.schedule and data.schedule.records or {} end,
      set_records = function(records)
        for _, rec in ipairs(records) do
          assert(type(rec.station) == "string" and space_locations[rec.station], "set_records: a space location " .. tostring(rec.station))
          for _, w in ipairs(rec.wait_conditions or {}) do
            assert(type(w.type) == "string", "a wait condition needs a type")
          end
        end
        data.schedule = #records > 0 and { current = 1, records = records } or nil
        F.platform_state(data)
      end,
      get_interrupts = function() return interrupts end,
      set_interrupts = function(list)
        for _, int in ipairs(list) do
          assert(type(int.name) == "string" and type(int.conditions) == "table" and type(int.targets) == "table", "an interrupt")
        end
        interrupts = list
      end,
    })
  end
  F.platform_data[platform] = data
  forces.player.platforms[index] = platform
  return platform
end

-- The state the game would give it: paused, no schedule, waiting where it is, or under way.
function F.platform_state(data)
  local st = defines.space_platform_state
  if not data.hub then
    data.state = st.waiting_for_starter_pack
  elseif data.paused then
    data.state = st.paused
  elseif not data.schedule then
    data.state = st.no_schedule
  elseif data.space_connection then
    data.state = st.on_the_path
  else
    data.state = st.waiting_at_station
  end
end

-- Sets a platform off along a connection, `distance` (0..1) of the way.
function F.platform_travel(platform, connection, distance, speed)
  local data = F.platform_data[platform]
  data.space_location, data.space_connection = nil, space_connections[connection]
  data.distance, data.speed = distance, speed
  F.platform_state(data)
end

-- An entity's fields as the harness sees them (writable whatever the API allows).
F.datas = setmetatable({}, { __mode = "k" })
function F.entity_data(e)
  return F.datas[e]
end

-- A cargo pod at the end of its trip, as 2.1.23 ends one: its passenger lands where the pod was
-- sent (inside the hub when that was a platform's hub) and the pod goes.
function F.pod_arrive(pod)
  local data = F.datas[pod]
  local who = pod.get_passenger()
  local dest = data.cargo_pod_destination
  if who then
    local w = F.datas[who]
    w.cargo_pod = nil
    if dest.type == defines.cargo_destination.station then
      who.teleport(dest.station.position, dest.station.surface)
      w.hub = dest.station.type == "space-platform-hub" and dest.station or nil
    else
      who.teleport(dest.position or { 0, 0 }, dest.surface)
    end
  end
  pod.destroy()
end

function F.platform_arrive(platform, location)
  local data = F.platform_data[platform]
  data.space_location, data.space_connection, data.distance, data.speed = space_locations[location], nil, nil, 0
  F.platform_state(data)
end

---------------------------------------------------------------------------------------------
-- blueprints held in a stack (the bridge's clipboard): create_blueprint stores what the area holds,
-- relative to the area's centre

F.stack_blueprint = {
  create_blueprint = function(slot, p)
    assert(p.surface and p.force and p.area, "create_blueprint takes {surface, force, area}")
    local a1, a2 = p.area[1], p.area[2]
    -- 2.1.23 keeps the entities at their map positions; build_blueprint centres them.
    slot.bp = {}
    for _, e in ipairs(p.surface.entities) do
      local q = e.position
      if q.x >= a1[1] and q.x <= a2[1] and q.y >= a1[2] and q.y <= a2[2] and e.type ~= "character"
          and e.type ~= "resource" and e.type ~= "tile-ghost" and e.unit_number and e.force == p.force then
        -- Ghosts are copied as the entity they stand for (2.1.23).
        slot.bp[#slot.bp + 1] = { entity_number = #slot.bp + 1, name = e.type == "entity-ghost" and e.ghost_name or e.name, position = { x = q.x, y = q.y },
          direction = e.direction }
      end
    end
    return {}
  end,
  -- A copy, as the game's is: changing it doesn't change the blueprint.
  get_blueprint_entities = function(slot)
    local out = {}
    for n, b in ipairs(slot.bp) do
      local e = {}
      for k, v in pairs(b) do
        e[k] = type(v) == "table" and { x = v.x or v[1], y = v.y or v[2] } or v
      end
      out[n] = e
    end
    return out
  end,
  is_blueprint_setup = function(slot) return #slot.bp > 0 end,
  build_blueprint = function(slot, p)
    assert(p.surface and p.force and p.position and p.build_mode ~= nil, "build_blueprint takes {surface, force, position, build_mode}")
    local made = {}
    local x1, y1, x2, y2 = math.huge, math.huge, -math.huge, -math.huge
    for _, b in ipairs(slot.bp) do
      local bx, by = b.position.x or b.position[1], b.position.y or b.position[2]
      x1, y1, x2, y2 = math.min(x1, bx), math.min(y1, by), math.max(x2, bx), math.max(y2, by)
    end
    local cx, cy = math.floor((x1 + x2) / 2), math.floor((y1 + y2) / 2)
    for _, b in ipairs(slot.bp) do
      made[#made + 1] = p.surface.create_entity({
        name = "entity-ghost", inner_name = b.name, force = p.force, raise_built = p.raise_built,
        position = { x = p.position[1] + (b.position.x or b.position[1]) - cx, y = p.position[2] + (b.position.y or b.position[2]) - cy },
        direction = b.direction,
      })
      if #made == 1 then F.last_built = {} end
      F.last_built[#made] = b
    end
    return made
  end,
}

-- Exchange strings in the fake's own format: "0FAKE|item|label|entity,entity,...". Real strings
-- are base64 zlib JSON; the mod never looks inside them, so any format the fake can read back does.
function F.export(slot)
  local names = {}
  for _, b in ipairs(slot.bp or {}) do
    names[#names + 1] = b.name
  end
  return "0FAKE|" .. slot.name .. "|" .. (slot.label or "") .. "|" .. table.concat(names, ",")
end

function F.import(data)
  local item, label, entities = string.match(tostring(data), "^0FAKE|([^|]*)|([^|]*)|(.*)$")
  if not item_protos[item or ""] then
    return nil
  end
  local slot = { name = item, count = 1, label = label ~= "" and label or nil }
  if item == "blueprint" then
    slot.bp = {}
    for name in string.gmatch(entities, "[^,]+") do
      slot.bp[#slot.bp + 1] = { entity_number = #slot.bp + 1, name = name, position = { x = #slot.bp, y = 0 }, direction = 0 }
    end
  elseif item == "blueprint-book" then
    slot.pages = F.make_inventory(3)
    slot.pages[1].set_stack({ name = "blueprint", count = 1 })
    slot.pages[2].set_stack({ name = "blueprint", count = 1 })
  end
  return slot
end

-- A blueprint library record (LuaRecord) holding an exchange string.
function F.make_record(type_name, label, data)
  return strict("LuaRecord", {
    type = type_name, label = label, export_record = function() return data end,
    preview_icons = { { signal = { type = "item", name = "transport-belt" }, index = 1 } },
  })
end

-- LuaFlowStatistics: counts by name the harness sets in F.flow[kind] = {name = {in, out}}.
F.flow = { item = { ["iron-plate"] = { 120, 30 }, ["iron-gear-wheel"] = { 10, 4 } }, fluid = {}, kill = { ["small-biter"] = { 3, 0 } } }
local function flow_statistics(kind)
  local counts = F.flow[kind]
  local input, output = {}, {}
  for name, c in pairs(counts) do
    input[name], output[name] = c[1], c[2]
  end
  -- Only electric network statistics store anything (accumulators): {name = {in, out, stored}}.
  local storage = {}
  for name, c in pairs(counts) do
    if kind == "electric" and c[3] then
      storage[name] = c[3]
    end
  end
  return strict("LuaFlowStatistics", {
    input_counts = input, output_counts = output, storage_counts = storage,
    get_input_count = function(name) return input[name] or 0 end,
    get_output_count = function(name) return output[name] or 0 end,
    get_storage_count = function(name) return storage[name] or 0 end,
    get_flow_count = function(p)
      assert(p.name and (p.category == "input" or p.category == "output" or p.category == "storage") and p.precision_index,
        "get_flow_count takes {name, category, precision_index}")
      assert(p.sample_index == nil or (p.sample_index >= 1 and p.sample_index <= 300), "sample_index is 1..300")
      local c = counts[p.name]
      if p.category == "storage" then
        return (storage[p.name] or 0) / 2
      end
      return c and (p.category == "input" and c[1] or c[2]) / 10 or 0
    end,
  })
end
F.flow.electric = { ["assembling-machine-1"] = { 600, 0 }, ["steam-engine"] = { 0, 900 }, accumulator = { 0, 0, 2500000 } }
F.flow_statistics = flow_statistics
rawset(forces.player, "get_item_production_statistics", function(surface)
  assert(surface and surface.index, "get_item_production_statistics(surface)")
  return flow_statistics("item")
end)
rawset(forces.player, "get_fluid_production_statistics", function(surface) return flow_statistics("fluid") end)
rawset(forces.player, "get_kill_count_statistics", function(surface) return flow_statistics("kill") end)
F.flow.build = { ["transport-belt"] = { 40, 2 } }
F.flow.pollution = { ["assembling-machine-1"] = { 12, 0 }, ["grass-1"] = { 0, 9 } }
rawset(forces.player, "get_entity_build_count_statistics", function(surface)
  assert(surface and surface.index, "get_entity_build_count_statistics(surface)")
  return flow_statistics("build")
end)
-- The force's logistic networks by surface name (the L window); F.lnets sets them.
F.lnets = {}
rawset(forces.player, "logistic_networks", setmetatable({}, { __pairs = function() return pairs(F.lnets) end,
  __index = function(_, k) return F.lnets[k] end }))
rawset(forces.player, "inserter_stack_size_bonus", 1)
rawset(forces.player, "bulk_inserter_capacity_bonus", 0)
-- Research bonuses by ammo category and turret (the Bonuses window).
rawset(forces.player, "get_ammo_damage_modifier", function(cat) return cat == "bullet" and 0.8 or 0 end)
rawset(forces.player, "get_gun_speed_modifier", function(cat) return 0 end)
rawset(forces.player, "get_turret_attack_modifier", function(turret) return turret == "gun-turret" and 0.4 or 0 end)

---------------------------------------------------------------------------------------------
-- game, helpers

game = strict("LuaGameScript", {
  tick = 0,
  ticks_played = 3725 * 60, -- /time (console.lua): 1 hour, 2 minutes and 5 seconds
  server_save = function(name) F.server_saved = true end,
  forces = forces,
  is_multiplayer = function() return F.multiplayer end,
  -- Permission groups (the Permissions window): Default with the harness's player.
  permissions = strict("LuaPermissionGroups", { groups = { strict("LuaPermissionGroup", { name = "Default", players = { F.player } }),
    strict("LuaPermissionGroup", { name = "Admin", players = {} }) } }),
  get_player = function(i) return F.players_by[i] or F.player end,
  -- Only prototypes flagged get-by-unit-number (vehicles) are found, as in the game.
  get_entity_by_unit_number = function(u)
    assert(type(u) == "number", "get_entity_by_unit_number(uint32)")
    local e = F.by_unit[u]
    return e and e.valid and e or nil
  end,
  players = F.players,
  surfaces = F.game_surfaces,
  train_manager = strict("LuaTrainManager", {
    get_trains = function(filter)
      assert(type(filter) == "table", "get_trains(TrainFilter)")
      local out = {}
      for _, train in pairs(F.trains) do
        local front = F.train_data[train].carriages[1]
        if front.valid and (not filter.force or front.force == filter.force)
            and (not filter.surface or front.surface == filter.surface) then
          out[#out + 1] = train
        end
      end
      return out
    end,
    get_train_by_id = function(id)
      local train = F.trains[id]
      return train and F.train_data[train].carriages[1].valid and train or nil
    end,
    get_train_stops = function(filter)
      assert(type(filter) == "table", "get_train_stops(TrainStopFilter)")
      local out = {}
      for _, e in ipairs((filter.surface or F.surface).entities) do
        if e.valid and e.type == "train-stop" and (not filter.force or e.force == filter.force) then
          out[#out + 1] = e
        end
      end
      return out
    end,
  }),
  get_surface = function(id) return surfaces[id] end,
  get_pollution_statistics = function(surface)
    assert(surface and surface.index, "get_pollution_statistics(surface)")
    return flow_statistics("pollution")
  end,
  planets = planets,
  print = function(msg)
    if type(msg) == "table" then -- a localised string {"", ...}: its pieces
      local parts = {}
      for i = 2, #msg do
        parts[#parts + 1] = tostring(msg[i])
      end
      msg = table.concat(parts)
    end
    F.printed[#F.printed + 1] = tostring(msg)
  end,
  blueprints = F.game_blueprints,
  create_inventory = function(size)
    assert(type(size) == "number" and size >= 1, "create_inventory: a size")
    return make_inventory(size)
  end,
})

-- LuaProfiler: only its methods; the game prints it inside a localised string.
local function make_profiler(stopped)
  F.profilers = F.profilers + 1
  local p = { ms = 0, running = not stopped }
  return strict("LuaProfiler", {
    -- As in the game: restart carries on from the time it had, reset starts again from zero.
    restart = function() p.running = true end,
    stop = function() p.running = false end,
    add = function(other) end,
    divide = function(n) assert(type(n) == "number" and n > 0, "divide by a positive number") end,
    reset = function() p.ms = 0 p.running = true end,
  })
end

helpers = strict("LuaHelpers", {
  create_profiler = make_profiler,
  table_to_json = function(t) return F_to_json(t) end,
  json_to_table = function(s) return F_from_json(s) end,
  send_udp = function(port, data, who)
    assert(type(port) == "number", "send_udp: port must be a number")
    assert(type(data) == "string", "send_udp: data must be a string")
    if F.multiplayer then
      assert(who == 0, "send_udp: on a server the bridge must send from the server (0)")
    else
      assert(who == nil, "send_udp: single-player must not pass for_player")
    end
    F.sent[#F.sent + 1] = { port, data }
  end,
  recv_udp = function(who) end,
})

---------------------------------------------------------------------------------------------
-- harness entry points

function F.tick()
  game.tick = game.tick + 1
  -- The game raises on_object_destroyed later, not inside destroy().
  local queue = F.destroyed_queue
  F.destroyed_queue = {}
  for _, n in ipairs(queue) do
    raise("on_object_destroyed", { registration_number = n, useful_id = 0, type = 1 })
  end
  raise("on_tick", {})
end

function F.packet(payload, port)
  raise("on_udp_packet_received", { payload = payload, source_port = port, player_index = 0 })
end

-- A LuaSegmentedUnit (a demolisher) on a surface: segments {{x, y, orientation}, ...}, head first.
function F.add_segmented_unit(surface, name, segment_name, segments)
  local list = {}
  for i, sg in ipairs(segments) do
    list[i] = strict("LuaSegment", { prototype = entity_protos[segment_name], position = { x = sg[1], y = sg[2] }, orientation = sg[3] })
  end
  F.next_unit = F.next_unit + 1
  local unit = strict("LuaSegmentedUnit", { valid = true, unit_number = F.next_unit, prototype = entity_protos[name], segments = list })
  table.insert(surface.segmented, unit)
  return unit
end

function F.spawn(name, x, y, extra)
  local p = { name = name, position = { x = x, y = y }, force = (extra and extra.force) or "neutral" }
  for k, v in pairs(extra or {}) do
    p[k] = v
  end
  return make_entity(nauvis, p)
end

-- Puts an item on one of a belt's transport lines, `position` tiles from the line's start.
function F.add_decorative(surface, name, x, y, amount)
  assert(prototypes.decorative[name], "add_decorative: no decorative " .. name)
  surface.decoratives[#surface.decoratives + 1] = { name = name, x = x, y = y, amount = amount or 1 }
end

function F.put_on_belt(entity, line, name, position, unique_id, spoil, quality)
  local items = belt_lines[entity][line]
  items[#items + 1] = { name = name, position = position, unique_id = unique_id, spoil = spoil, quality = quality }
end

-- Moves an item along its line (as the belt carries it), or off the belt with position nil.
function F.move_on_belt(entity, line, unique_id, position)
  local items = belt_lines[entity][line]
  for k, it in ipairs(items) do
    if it.unique_id == unique_id then
      if position then
        it.position = position
      else
        table.remove(items, k)
      end
      return
    end
  end
end

-- Puts fluid in an entity's box i ({name, amount, temperature}, or nil to empty it).
function F.set_fluid(entity, i, fluid, capacity)
  F.fluid_setters[entity](i, fluid, capacity)
end

-- Connects two entities with a wire (defines.wire_type), both ways, as 2.x connectors do.
function F.connect(a, b, wire_type)
  local ca, cb = F.connectors[a](wire_type), F.connectors[b](wire_type)
  table.insert(ca.connections, { target = cb })
  table.insert(cb.connections, { target = ca })
end

-- Moves an inserter's hand and puts an item in it (`name` nil for an empty hand).
function F.set_hand(entity, x, y, name)
  entity.held_stack_position = { x = x, y = y }
  entity.held_stack = name and strict("LuaItemStack", { valid_for_read = true, name = name, count = 1 })
    or strict("LuaItemStack", { valid_for_read = false })
end

-- A LuaPlayer playing this character (single-player, hybrid mode), with a quickbar of 10 pages
-- of 10 item filters. game.get_player returns it.
function F.make_player(character)
  local quickbar, active = {}, { 1 }
  local selected = nil
  local function key(page, slot)
    assert(type(page) == "number" and page >= 1 and page <= 10, "quick bar page " .. tostring(page))
    assert(type(slot) == "number" and slot >= 1 and slot <= 10, "quick bar slot " .. tostring(slot))
    return (page - 1) * 10 + slot
  end
  local player = setmetatable({}, {
    __index = function(_, k)
      if k == "character" then
        return character
      elseif k == "index" then
        return 1
      elseif k == "connected" then
        return true
      elseif k == "name" then
        return "player"
      elseif k == "chat_color" then
        return { r = 1, g = 0.5, b = 0, a = 1 }
      elseif k == "selected" then
        return selected
      elseif k == "print" then
        return function(msg) F.printed[#F.printed + 1] = "PLAYER " .. tostring(msg) end
      elseif k == "get_quick_bar_slot" then
        return function(page, slot)
          local name = quickbar[key(page, slot)]
          return name and { type = "filter", filter = { name = name, quality = "normal" } } or nil
        end
      elseif k == "set_quick_bar_slot" then
        return function(page, slot, filter)
          assert(select("#", page, slot, filter) == 3 or filter == nil, "set_quick_bar_slot(page, slot, filter)")
          if type(filter) == "table" then
            filter = filter.name
          end
          assert(filter == nil or item_protos[filter], "set_quick_bar_slot: unknown item " .. tostring(filter))
          quickbar[key(page, slot)] = filter
        end
      elseif k == "get_active_quick_bar_page" then
        return function(i) return active[i] end
      elseif k == "set_active_quick_bar_page" then
        return function(i, page) active[i] = page end
      end
      error("LuaPlayer doesn't contain key " .. tostring(k), 2)
    end,
    __newindex = function(_, k, v)
      if k == "cheat_mode" then -- /cheat (console.lua)
        F.cheat_mode = v
        return
      end
      assert(k == "selected", "LuaPlayer: can't write " .. tostring(k))
      selected = v
    end,
  })
  character.player = player
  F.player = player
  F.quickbar = quickbar
  return player
end

-- A player of a save who isn't connected (a single-player save loaded on a server): their
-- character is logged off, so `character` is nil, but the LuaPlayer still has its inventories,
-- logistic requests and quickbar (as 2.1.23 does). F.connect_player brings them in with a character.
function F.make_offline_player(index, name, x, y)
  local main, guns, ammo, armor, trash = make_inventory(80), make_inventory(3), make_inventory(3), make_inventory(1), make_inventory(10)
  local requester = make_sections(true)
  local quickbar, active = {}, { 1 }
  local d = {
    index = index, name = name, connected = false, controller_type = defines.controllers.character,
    last_online = 50, physical_surface = surfaces[1], physical_position = { x = x, y = y },
    force = forces.player, color = { r = 1, g = 0.5, b = 0, a = 0.5 }, character_inventory_slots_bonus = 0,
    blueprints = F.player_blueprints,
  }
  d.get_main_inventory = function() return main end
  d.get_inventory = function(i)
    return ({ [defines.inventory.character_main] = main, [defines.inventory.character_guns] = guns,
      [defines.inventory.character_ammo] = ammo, [defines.inventory.character_armor] = armor,
      [defines.inventory.character_trash] = trash })[i]
  end
  d.get_requester_point = function() return requester end
  d.insert = function(stack) return main.insert(stack) end
  d.print = function(msg) F.printed[#F.printed + 1] = "PLAYER " .. tostring(msg) end
  d.get_quick_bar_slot = function(page, slot)
    local n = quickbar[(page - 1) * 10 + slot]
    return n and { type = "filter", filter = { name = n, quality = "normal" } } or nil
  end
  d.set_quick_bar_slot = function(page, slot, filter)
    quickbar[(page - 1) * 10 + slot] = type(filter) == "table" and filter.name or filter
  end
  d.get_active_quick_bar_page = function(i) return active[i] end
  d.set_active_quick_bar_page = function(i, page) active[i] = page end
  local optional = { character = true, crafting_queue = true }
  local player = setmetatable({}, {
    __index = function(_, k)
      local v = d[k]
      if v == nil and not optional[k] then
        error("LuaPlayer doesn't contain key " .. tostring(k), 2)
      end
      return v
    end,
    __newindex = function(_, k, v)
      assert(k == "character_inventory_slots_bonus" or k == "cheat_mode", "LuaPlayer: can't write " .. tostring(k))
      d[k] = v
    end,
  })
  F.players[index] = player
  F.players_by[index] = player
  F.players_by[name] = player
  F.player_data = F.player_data or {}
  F.player_data[player] = d
  return player
end

-- The player joins with this character (logged on again).
function F.connect_player(player, character)
  local d = F.player_data[player]
  d.connected = true
  d.character = character
  character.player = player
  raise("on_player_joined_game", { player_index = d.index })
end

-- A LuaEquipmentGrid of w x h cells (the harness gives it to a character or car as `grid`).
-- Equipment occupies rectangles; put, take and move take tables as in 2.1. Batteries hold energy,
-- shields add up, exoskeletons add movement unless inhibit_movement_bonus is set.
function F.make_grid(w, h)
  local list = {}
  local inhibit = false
  local function eq_at(x, y)
    for _, e in ipairs(list) do
      local p, sh = e.position, e.shape
      if x >= p.x and x < p.x + sh.width and y >= p.y and y < p.y + sh.height then
        return e
      end
    end
    return nil
  end
  local function fits(name, x, y, except)
    local pr = equipment_protos[name]
    if x < 0 or y < 0 or x + pr.w > w or y + pr.h > h then
      return false
    end
    for dx = 0, pr.w - 1 do
      for dy = 0, pr.h - 1 do
        local o = eq_at(x + dx, y + dy)
        if o and o ~= except then
          return false
        end
      end
    end
    return true
  end
  local function make_equipment(name, x, y, quality)
    local pr = equipment_protos[name]
    local d = { name = name, type = pr.type, position = { x = x, y = y }, shape = { width = pr.w, height = pr.h },
      energy = pr.max_energy / 2, max_energy = pr.max_energy, shield = (pr.max_shield or 0) / 2, max_shield = pr.max_shield or 0,
      movement_bonus = pr.movement or 0, quality = strict("LuaQualityPrototype", { name = quality or "normal" }), valid = true }
    return setmetatable({}, {
      __index = function(_, k)
        if d[k] == nil then
          error("LuaEquipment doesn't contain key " .. tostring(k), 2)
        end
        return d[k]
      end,
      __newindex = function(_, k, v)
        assert(k == "energy" or k == "shield" or k == "position", "LuaEquipment: can't write " .. tostring(k))
        d[k] = v
      end,
    })
  end
  local methods = {
    put = function(p)
      assert(type(p) == "table" and p.name, "put{name, position?, quality?}")
      assert(equipment_protos[p.name], "put: unknown equipment " .. tostring(p.name))
      local at = p.position
      if not at then
        for y = 0, h - 1 do
          for x = 0, w - 1 do
            if not at and fits(p.name, x, y) then
              at = { x = x, y = y }
            end
          end
        end
      end
      if not at or not fits(p.name, at.x, at.y) then
        return nil
      end
      local e = make_equipment(p.name, at.x, at.y, p.quality)
      list[#list + 1] = e
      return e
    end,
    get = function(position)
      assert(type(position) == "table" and position.x, "get(position)")
      return eq_at(position.x, position.y)
    end,
    take = function(p)
      assert(type(p) == "table", "take{equipment or position}")
      local e = p.equipment or (p.position and eq_at(p.position.x, p.position.y))
      for i, o in ipairs(list) do
        if o == e then
          table.remove(list, i)
          return { name = e.name, count = 1, quality = e.quality.name }
        end
      end
      return nil
    end,
    move = function(p, extra)
      assert(type(p) == "table" and extra == nil and p.equipment and p.position, "move{equipment, position} (2.1 takes a table)")
      local e, to = p.equipment, p.position
      if not fits(e.name, to.x, to.y, e) then
        return false
      end
      e.position = { x = to.x, y = to.y }
      return true
    end,
    get_generator_energy = function() return 0 end,
  }
  local sums = { shield = true, max_shield = true, movement_bonus = true }
  return setmetatable({}, {
    __index = function(_, k)
      if methods[k] then
        return methods[k]
      elseif k == "width" then
        return w
      elseif k == "height" then
        return h
      elseif k == "valid" then
        return true
      elseif k == "equipment" then
        local out = {}
        for i, e in ipairs(list) do
          out[i] = e
        end
        return out
      elseif k == "inhibit_movement_bonus" then
        return inhibit
      elseif sums[k] then
        local n = 0
        for _, e in ipairs(list) do
          if k ~= "movement_bonus" or not inhibit then
            n = n + e[k]
          end
        end
        return n
      elseif k == "available_in_batteries" or k == "battery_capacity" then
        local n = 0
        for _, e in ipairs(list) do
          if e.type == "battery-equipment" then
            n = n + (k == "battery_capacity" and e.max_energy or e.energy)
          end
        end
        return n
      elseif k == "inventory_bonus" then
        return 0
      end
      error("LuaEquipmentGrid doesn't contain key " .. tostring(k), 2)
    end,
    __newindex = function(_, k, v)
      assert(k == "inhibit_movement_bonus", "LuaEquipmentGrid: can't write " .. tostring(k))
      inhibit = v
    end,
  })
end

function F.take_sent()
  local out = F.sent
  F.sent = {}
  return out
end
