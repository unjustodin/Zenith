-- Prototype dictionaries: entity, tile and item names map to small integer ids for compact
-- messages.
--
-- The cache is module-local and rebuilt after each load. It is derived only from prototypes,
-- so it is identical on every peer and never needs to live in `storage`.

local M = {}

-- Visual effects and helper entities. Never sent to the client. (Entity and tile ghosts are sent:
-- they are what blueprints and the tile brush place.)
local EFFECT_TYPES = {
  "arrow", "artillery-flare", "artillery-projectile", "beam", "character-corpse", "corpse",
  "deconstructible-tile-proxy", "explosion", "fire", "highlight-box",
  "item-entity", "item-request-proxy", "lightning", "particle-source", "projectile",
  "rocket-silo-rocket-shadow", "smoke-with-trigger", "speech-bubble", "spider-leg", "sticker",
  "stream",
}

-- Their corpses aren't remnants: they are left lying by the thousand and the client draws its own.
local CREATURE_TYPES = {
  ["unit"] = true, ["character"] = true, ["spider-unit"] = true, ["segmented-unit"] = true, ["segment"] = true,
  ["tree"] = true, ["plant"] = true, ["fish"] = true, ["asteroid"] = true, ["unit-spawner"] = true,
}

-- Things that move. Streamed every few ticks near the focus instead of in chunk snapshots.
local MOVER_TYPES = {
  "unit", "character", "car", "spider-vehicle", "locomotive", "cargo-wagon", "fluid-wagon",
  "artillery-wagon", "logistic-robot", "construction-robot", "combat-robot", "capture-robot",
  "spider-unit", "segmented-unit", "segment", "asteroid", "cargo-pod", "rocket-silo-rocket",
}

-- Movers whose facing the client can't infer from motion alone.
M.ORIENTED = {
  ["car"] = true, ["spider-vehicle"] = true, ["locomotive"] = true, ["cargo-wagon"] = true,
  ["fluid-wagon"] = true, ["artillery-wagon"] = true,
}

-- Machines whose working state drives client-side animation. A working lamp is one with power;
-- the client lights it only when it is dark.
local ANIMATED_TYPES = {
  "assembling-machine", "furnace", "mining-drill", "lab", "boiler", "generator", "reactor",
  "radar", "rocket-silo", "pump", "offshore-pump", "beacon", "burner-generator",
  "fusion-reactor", "fusion-generator", "agricultural-tower", "asteroid-collector", "lamp",
  "thruster", "rail-signal", "rail-chain-signal", "accumulator", "power-switch",
}

-- What a character can get into.
local VEHICLE_TYPES = {
  "car", "spider-vehicle", "locomotive", "cargo-wagon", "fluid-wagon", "artillery-wagon",
}

-- Entities that hold fluids in pipes and boxes worth drawing (fluid in pipes, tank levels).
local FLUID_TYPES = {
  "pipe", "pipe-to-ground", "storage-tank", "pump", "offshore-pump", "boiler", "generator",
  "assembling-machine", "furnace", "mining-drill", "fluid-turret", "reactor", "heat-exchanger",
  "fusion-reactor", "fusion-generator", "infinity-pipe", "valve",
}

-- Machines that can run short of electricity, to report low or no power for.
local ELECTRIC_TYPES = {
  "assembling-machine", "furnace", "mining-drill", "lab", "inserter", "lamp", "radar", "beacon",
  "roboport", "electric-turret", "pump", "offshore-pump", "rocket-silo", "agricultural-tower",
  "asteroid-collector", "arithmetic-combinator", "decider-combinator", "selector-combinator",
}

-- Pipes, whose record carries which sides they connect on (world.lua, extra.pc).
local PIPE_TYPES = { "pipe", "infinity-pipe", "pipe-to-ground" }

-- Entities with a heat buffer (2.x: heat pipes, reactors, heat interfaces).
local HEAT_TYPES = { "heat-pipe", "reactor", "heat-interface" }

-- Entities whose wires are watched near the focus: 2.x raises no event when a wire is added
-- between two existing entities.
local WIRED_TYPES = {
  "electric-pole", "power-switch", "arithmetic-combinator", "decider-combinator", "selector-combinator",
  "constant-combinator",
}

-- Train carriages.
local ROLLING_STOCK_TYPES = { "locomotive", "cargo-wagon", "fluid-wagon", "artillery-wagon" }

-- Rails rolling stock can be put on.
local RAIL_TYPES = { "straight-rail", "legacy-straight-rail" }

-- Entities that carry items on transport lines.
local BELT_TYPES = {
  "transport-belt", "underground-belt", "splitter", "lane-splitter", "loader", "loader-1x1",
  "linked-belt",
}

local cache

-- find_entities_filtered rejects unknown type names, so only keep types that some loaded
-- prototype actually uses.
local function existing(list, present)
  local out = {}
  for _, t in pairs(list) do
    if present[t] then
      out[#out + 1] = t
    end
  end
  return out
end

local function build()
  local c = {
    entity_ids = {}, entities = {}, tile_ids = {}, tiles = {}, item_ids = {}, items = {},
    present = {}, movers = {},
  }
  for name, proto in pairs(prototypes.entity) do
    c.entities[#c.entities + 1] = proto
    c.entity_ids[name] = #c.entities
    c.present[proto.type] = true
  end
  for name, proto in pairs(prototypes.tile) do
    c.tiles[#c.tiles + 1] = proto
    c.tile_ids[name] = #c.tiles
  end
  for name in pairs(prototypes.item) do
    c.items[#c.items + 1] = name
    c.item_ids[name] = #c.items
  end
  -- Decoratives (grass, flowers, small rocks): only the ones a map can place, by name.
  c.decoratives, c.decorative_ids = {}, {}
  local ok, decoratives = pcall(function() return prototypes.decorative end)
  for name in pairs(ok and decoratives or {}) do
    c.decoratives[#c.decoratives + 1] = name
    c.decorative_ids[name] = #c.decoratives
  end
  c.fluids, c.fluid_ids = {}, {}
  for name, proto in pairs(prototypes.fluid) do
    c.fluids[#c.fluids + 1] = proto
    c.fluid_ids[name] = #c.fluids
  end
  c.fluid_types = existing(FLUID_TYPES, c.present)
  c.electric_types = existing(ELECTRIC_TYPES, c.present)
  c.mover_types = existing(MOVER_TYPES, c.present)
  c.animated_types = existing(ANIMATED_TYPES, c.present)
  c.belt_types = existing(BELT_TYPES, c.present)
  c.rail_types = existing(RAIL_TYPES, c.present)
  c.rolling_stock_types = existing(ROLLING_STOCK_TYPES, c.present)
  c.pipe_types = existing(PIPE_TYPES, c.present)
  c.heat_types = existing(HEAT_TYPES, c.present)
  c.wired_types = existing(WIRED_TYPES, c.present)
  c.fluid_set = {}
  for _, t in pairs(c.fluid_types) do
    c.fluid_set[t] = true
  end
  c.pipe_set = {}
  for _, t in pairs(c.pipe_types) do
    c.pipe_set[t] = true
  end
  c.vehicle_types = existing(VEHICLE_TYPES, c.present)
  local excluded = existing(EFFECT_TYPES, c.present)
  for _, t in pairs(c.mover_types) do
    excluded[#excluded + 1] = t
    c.movers[t] = true
  end
  c.excluded_types = excluded
  -- Remnants: corpses some building leaves when destroyed (named "...remnants"; biters' and
  -- trees' corpses aren't streamed). remnant_of maps one to what died, for the client to draw that
  -- entity's model broken: the entity of the same name, else the only one that leaves it; 0 for
  -- shared ones (small-remnants...). Corpses are excluded from snapshots by type, so the corpse
  -- names are looked up on their own (remnant_names).
  c.remnant_of, c.remnant_names = {}, {}
  local sources = {}
  for name, proto in pairs(prototypes.entity) do
    if not CREATURE_TYPES[proto.type] then
      local ok, corpses = pcall(function() return proto.corpses end)
      for cname, cproto in pairs(ok and corpses or {}) do
        if (cproto.type == "corpse" or cproto.type == "rail-remnants") and string.find(cname, "remnants", 1, true) then
          local s = sources[cname] or {}
          sources[cname] = s
          s[#s + 1] = name
        end
      end
    end
  end
  for cname, list in pairs(sources) do
    local of = (#list == 1) and list[1] or nil
    for _, name in pairs(list) do
      if cname == name .. "-remnants" then
        of = name
      end
    end
    c.remnant_of[cname] = of and c.entity_ids[of] or 0
    if prototypes.entity[cname].type == "corpse" then
      c.remnant_names[#c.remnant_names + 1] = cname
    end
  end
  table.sort(c.remnant_names)
  c.excluded = {}
  for _, t in pairs(excluded) do
    c.excluded[t] = true
  end
  cache = c
end

local function get()
  if not cache then
    build()
  end
  return cache
end

function M.entity_id(name)
  return get().entity_ids[name] or 0
end

function M.entity_name(id)
  local proto = get().entities[id]
  return proto and proto.name
end

function M.tile_id(name)
  return get().tile_ids[name] or 0
end

function M.item_id(name)
  return get().item_ids[name] or 0
end

function M.mover_types()
  return get().mover_types
end

function M.belt_types()
  return get().belt_types
end

function M.vehicle_types()
  return get().vehicle_types
end

function M.animated_types()
  return get().animated_types
end

-- The prototype id of what a remnants corpse is left by (0: shared by several), or nil if it is
-- no remnant.
function M.remnant_of(name)
  return get().remnant_of[name]
end

-- Names of the corpse prototypes that are remnants, for find_entities_filtered.
function M.remnant_names()
  return get().remnant_names
end

function M.excluded_types()
  return get().excluded_types
end

function M.is_mover(type_name)
  return get().movers[type_name] == true
end

-- True for entities that belong in chunk snapshots and add/remove deltas.
-- Some loaded prototype has this type (find_entities_filtered rejects unknown type names).
function M.has_type(type_name)
  return get().present[type_name] == true
end

function M.is_static(type_name)
  return not get().excluded[type_name]
end

local function round3(v)
  return math.floor(v * 1000 + 0.5) / 1000
end

local function rgb(color)
  if not color then
    return 128, 128, 128
  end
  local r, g, b = color.r or color[1] or 0, color.g or color[2] or 0, color.b or color[3] or 0
  -- Colors are normally 0..1, but tolerate 0..255.
  local scale = (r > 1 or g > 1 or b > 1) and 1 or 255
  return math.floor(r * scale + 0.5), math.floor(g * scale + 0.5), math.floor(b * scale + 0.5)
end

local function box_size(box)
  return box.right_bottom.x - box.left_top.x, box.right_bottom.y - box.left_top.y
end

-- [id, name, type, x1, y1, x2, y2, r, g, b, tile_width, tile_height]
-- The box is the selection box (what the player sees and clicks), or the collision box if the
-- entity has no selection box.
local function entity_record(id, proto)
  local box = proto.selection_box
  local w, h = box_size(box)
  if w <= 0 or h <= 0 then
    box = proto.collision_box
  end
  local r, g, b = rgb(proto.map_color or proto.friendly_map_color)
  return {
    id, proto.name, proto.type,
    round3(box.left_top.x), round3(box.left_top.y), round3(box.right_bottom.x), round3(box.right_bottom.y),
    r, g, b, proto.tile_width, proto.tile_height,
  }
end

-- Prototypes only, so made once per load (8 ms on Space Age: every handshake used to pay it).
local entity_records_cache

function M.entity_records()
  if entity_records_cache then
    return entity_records_cache
  end
  local out = {}
  for id, proto in pairs(get().entities) do
    out[#out + 1] = entity_record(id, proto)
  end
  entity_records_cache = out
  return out
end

-- [id, name, r, g, b]
function M.decorative_id(name)
  return get().decorative_ids[name] or 0
end

-- [id, name]. The client finds each one's pictures by name (client/data/decoratives.json).
function M.decorative_records()
  local out = {}
  for id, name in pairs(get().decoratives) do
    out[#out + 1] = { id, name }
  end
  return out
end

function M.tile_records()
  local out = {}
  for id, proto in pairs(get().tiles) do
    local r, g, b = rgb(proto.map_color)
    out[#out + 1] = { id, proto.name, r, g, b }
  end
  return out
end

-- [id, name]. Items have no map colour; the client picks an icon or a colour by name.
-- What an item builds: its place_result, or for a 2.x rail planner (whose place_result may be
-- empty) its straight rail. Nil for items that build nothing.
function M.place_result(item)
  local ok, proto = pcall(function() return item.place_result end)
  if ok and proto then
    return proto
  end
  local ok2, rails = pcall(function() return item.rails end)
  for _, rail in pairs(ok2 and rails or {}) do
    if rail.type == "straight-rail" or rail.type == "legacy-straight-rail" then
      return rail
    end
  end
  return nil
end

function M.fluid_id(name)
  return get().fluid_ids[name] or 0
end

function M.fluid_types()
  return get().fluid_types
end

function M.electric_types()
  return get().electric_types
end

-- [id, name, r, g, b]: the fluid's base colour.
function M.fluid_records()
  local out = {}
  for id, proto in pairs(get().fluids) do
    local r, g, b = rgb(proto.base_color)
    out[#out + 1] = { id, proto.name, r, g, b }
  end
  return out
end

function M.rail_types()
  return get().rail_types
end

function M.rolling_stock_types()
  return get().rolling_stock_types
end

function M.pipe_types()
  return get().pipe_types
end

function M.is_pipe(type_name)
  return get().pipe_set[type_name] == true
end

-- Has fluid boxes a pipe can connect to.
function M.is_fluid(type_name)
  return get().fluid_set[type_name] == true
end

function M.heat_types()
  return get().heat_types
end

function M.wired_types()
  return get().wired_types
end

-- [id, name] or, when the item builds something with another name (rail -> straight-rail),
-- [id, name, entity name].
function M.item_records()
  local out = {}
  for id, name in pairs(get().items) do
    local place = M.place_result(prototypes.item[name])
    if place and place.name ~= name then
      out[#out + 1] = { id, name, place.name }
    else
      out[#out + 1] = { id, name }
    end
  end
  return out
end

return M
