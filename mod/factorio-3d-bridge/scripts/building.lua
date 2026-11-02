-- Building from the character's inventory, as a player does: snapped to the grid (rails to their
-- two-tile grid), fast-replace (a faster belt over a belt, the same belt turned), rolling stock
-- put on the nearest rail, and the quality of the stack it is built from.

local registry = require("scripts.registry")
local transport = require("scripts.transport")
local tracker = require("scripts.tracker")
local puppet = require("scripts.puppet")
local map = require("scripts.map")
local space = require("scripts.space")

local M = {}

local REACH_SLACK = 1.5 -- reach is measured to the entity's edge in-game; we measure to its centre
local RAIL_SEARCH = 3   -- how far from the cursor rolling stock looks for a rail
local ROLLING_STOCK = {
  locomotive = true, ["cargo-wagon"] = true, ["fluid-wagon"] = true, ["artillery-wagon"] = true,
}

local function distance(a, b)
  local dx, dy = a.x - b.x, a.y - b.y
  return math.sqrt(dx * dx + dy * dy)
end

-- Odd sizes centre on a tile, even sizes on a tile corner, like the game. Rails sit on a two-tile
-- grid with their centres on odd coordinates.
local function snap(v, size, grid)
  if grid == 2 then
    return math.floor(v / 2) * 2 + 1
  end
  if size % 2 == 1 then
    return math.floor(v) + 0.5
  end
  return math.floor(v + 0.5)
end

local function grid_size(proto)
  local ok, g = pcall(function() return proto.build_grid_size end)
  return ok and g or 1
end

-- An underground belt becomes the exit of the nearest underground of its kind behind it facing the
-- same way (or its ghost), when that one is an entrance; otherwise an entrance, as when a player
-- builds one.
-- create_entity makes every underground an entrance unless told (checked in 2.1.23).
local BEHIND = { [0] = { 0, 1 }, [4] = { -1, 0 }, [8] = { 0, -1 }, [12] = { 1, 0 } }
local function underground_type(surface, proto, position, direction)
  local back = BEHIND[direction]
  local ok, reach = pcall(function() return proto.max_underground_distance end)
  if not back or not ok or not reach then
    return "input"
  end
  for i = 1, reach do
    local at = { x = position.x + back[1] * i, y = position.y + back[2] * i }
    local other = surface.find_entities_filtered({ name = proto.name, position = at })[1]
      or surface.find_entities_filtered({ ghost_name = proto.name, position = at })[1]
    if other and other.direction == direction then
      return other.belt_to_ground_type == "input" and "output" or "input"
    end
  end
  return "input"
end

-- The quality to build with: the one asked for if the character has it, else normal, else the
-- first the character has (by name, so every peer picks the same).
local function pick_quality(inventory, item_name, wanted)
  local have = {}
  for _, it in pairs(inventory.get_contents()) do
    if it.name == item_name and it.count > 0 then
      have[it.quality or "normal"] = true
    end
  end
  if wanted and have[wanted] then
    return wanted
  end
  if have.normal then
    return "normal"
  end
  local names = {}
  for q in pairs(have) do
    names[#names + 1] = q
  end
  table.sort(names)
  return names[1]
end

local function quality_name(e)
  local ok, q = pcall(function() return e.quality.name end)
  return ok and q or "normal"
end

-- Rolling stock goes on the nearest straight rail, facing along it (the client's direction picks
-- which way along).
local function on_rail(surface, position, direction)
  local types = registry.rail_types()
  if #types == 0 then
    return nil
  end
  local best, best_d = nil, RAIL_SEARCH
  for _, rail in pairs(surface.find_entities_filtered({
    area = { { position.x - RAIL_SEARCH, position.y - RAIL_SEARCH }, { position.x + RAIL_SEARCH, position.y + RAIL_SEARCH } },
    type = types,
  })) do
    local d = distance(position, rail.position)
    if d <= best_d then
      best, best_d = rail, d
    end
  end
  if not best then
    return nil
  end
  local axis = best.direction % 8
  local facing = direction
  if axis ~= direction % 8 then
    facing = axis
  end
  return { x = best.position.x, y = best.position.y }, facing
end

-- The entity of the same prototype standing exactly there, if any.
local function same_entity(surface, proto, position)
  for _, e in pairs(surface.find_entities_filtered({
    area = { { position.x - 0.1, position.y - 0.1 }, { position.x + 0.1, position.y + 0.1 } },
    name = proto.name,
  })) do
    if e.position.x == position.x and e.position.y == position.y then
      return e
    end
  end
  return nil
end

-- A ghost of this entity standing exactly there, if any.
local function ghost_at(surface, proto, position)
  for _, g in pairs(surface.find_entities_filtered({
    area = { { position.x - 0.1, position.y - 0.1 }, { position.x + 0.1, position.y + 0.1 } },
    type = "entity-ghost",
  })) do
    if g.ghost_name == proto.name and g.position.x == position.x and g.position.y == position.y then
      return g
    end
  end
  return nil
end

-- What a fast-replace would remove: an entity there of the same fast-replaceable group.
local function replaced_entity(surface, proto, position)
  local group = proto.fast_replaceable_group
  if not group or group == "" then
    return nil
  end
  for _, e in pairs(surface.find_entities_filtered({
    area = { { position.x - 0.1, position.y - 0.1 }, { position.x + 0.1, position.y + 0.1 } },
  })) do
    if e.prototype.fast_replaceable_group == group then
      return e
    end
  end
  return nil
end

-- Items go to the character; what doesn't fit is spilled at its feet, as the game does.
local function give(c, stack)
  local inserted = c.insert(stack)
  if inserted < stack.count then
    stack.count = stack.count - inserted
    pcall(function() c.surface.spill_item_stack({ position = c.position, stack = stack }) end)
  end
end

---------------------------------------------------------------------------------------------

-- Whether a tile under the footprint is one the entity can't stand on (empty space round a
-- platform, water): the script check below doesn't look at tiles (2.1.23 answers true over space).
local function on_bad_tiles(surface, proto, position, direction)
  local ok, mask = pcall(function() return proto.collision_mask end)
  local layers = ok and mask and mask.layers
  if not layers or next(layers) == nil then
    return false
  end
  local w, h = proto.tile_width, proto.tile_height
  if direction == defines.direction.east or direction == defines.direction.west then
    w, h = h, w
  end
  local okc, n = pcall(function()
    return surface.count_tiles_filtered({
      area = { { position.x - w / 2 + 0.1, position.y - h / 2 + 0.1 }, { position.x + w / 2 - 0.1, position.y + h / 2 - 0.1 } },
      collision_mask = layers, limit = 1,
    })
  end)
  return okc and n > 0
end

-- Factorio's manual check, and where the force hasn't charted the chunk (a headless server charts
-- nothing by itself) the script check, which leaves out what manual checks for: the tiles and the
-- surface's conditions (a chest needs gravity, so not on a platform) are checked here instead.
-- Without them ghosts went onto empty space or broke a platform's rules and never got built (F6).
local function can_place(surface, proto, position, direction, force, check)
  local spec = { name = proto.name, position = position, direction = direction, force = force, build_check_type = check }
  if surface.can_place_entity(spec) then
    return true
  end
  if force.is_chunk_charted(surface, { math.floor(position.x / 32), math.floor(position.y / 32) }) then
    return false
  end
  if space.cant_build(surface, proto) or on_bad_tiles(surface, proto, position, direction) then
    return false
  end
  spec.build_check_type = defines.build_check_type.script
  return surface.can_place_entity(spec)
end

-- A ghost of the entity for robots to build (Shift+click, or a pipette with none in the
-- inventory), like a player's; no reach limit and no item needed. Super-forced (Ctrl+Shift+click)
-- marks what stands in the way for deconstruction and puts the ghost there anyway, as 2.x does.
local function build_ghost(c, proto, position, direction, mirror, super)
  local surface = puppet.surface(c)
  if ghost_at(surface, proto, position) or same_entity(surface, proto, position) then
    return
  end
  if not map.check_charted(c, position) then
    return
  end
  local spec = { name = "entity-ghost", inner_name = proto.name, position = position, direction = direction,
    force = c.force, raise_built = true }
  if mirror then
    spec.mirror = true
  end
  if proto.type == "underground-belt" then
    spec.type = underground_type(surface, proto, position, direction)
  end
  if super and not can_place(surface, proto, position, direction, c.force, defines.build_check_type.manual_ghost) then
    local w, h = proto.tile_width, proto.tile_height
    if direction == defines.direction.east or direction == defines.direction.west then
      w, h = h, w
    end
    surface.deconstruct_area({ area = { { position.x - w / 2 + 0.1, position.y - h / 2 + 0.1 },
      { position.x + w / 2 - 0.1, position.y + h / 2 - 0.1 } }, force = c.force })
    if surface.create_entity(spec) then
      return
    end
  end
  if not can_place(surface, proto, position, direction, c.force, defines.build_check_type.manual)
      or not surface.create_entity(spec) then
    puppet.message(space.cant_build(surface, proto) or "Can't place that there")
  end
end

-- {item, x, y (fixed cursor position), d, q? (quality), ghost? (1: a ghost), sf? (1: super-forced
-- ghost), m? (1: flipped)}: places one of the item's entity.
function M.build(cmd)
  local c = puppet.get()
  if not c then
    return
  end
  local item_name = tostring(cmd.item or "")
  local item = prototypes.item[item_name]
  local proto = item and registry.place_result(item)
  if not proto then
    return puppet.message("Can't build " .. item_name)
  end
  local inventory = c.get_main_inventory()
  local quality = inventory and pick_quality(inventory, item_name, cmd.q and tostring(cmd.q))
  if not quality and cmd.ghost ~= 1 then
    return puppet.message("You have no " .. item_name)
  end
  local fx, fy = tonumber(cmd.x), tonumber(cmd.y)
  if not fx or not fy then
    return
  end
  local direction = math.floor(tonumber(cmd.d) or 0) % 16
  local w, h = proto.tile_width, proto.tile_height
  if direction == defines.direction.east or direction == defines.direction.west then
    w, h = h, w
  end
  local grid = grid_size(proto)
  local position = { x = snap(fx / 256, w, grid), y = snap(fy / 256, h, grid) }
  local surface = puppet.surface(c)
  if ROLLING_STOCK[proto.type] then
    position, direction = on_rail(surface, { x = fx / 256, y = fy / 256 }, direction)
    if not position then
      return puppet.message("Rolling stock goes on rails")
    end
  end
  if cmd.ghost == 1 then
    return build_ghost(c, proto, position, direction, cmd.m == 1, cmd.sf == 1)
  end
  if distance(c.position, position) > c.build_distance + REACH_SLACK then
    return puppet.message("Out of reach")
  end

  -- Building over a ghost of it fills the ghost in (keeping its settings), like a player does.
  local ghost = ghost_at(surface, proto, position)
  if ghost then
    local removal = tracker.removal_message(ghost)
    local ok, collided, revived = pcall(function() return ghost.revive({ raise_revive = true }) end)
    if ok and revived then
      if removal then
        transport.send_reliable(removal)
      end
      for name, count in pairs(collided or {}) do
        give(c, { name = name, count = count })
      end
      local stack = { name = item_name, count = 1 }
      if quality ~= "normal" then
        stack.quality = quality
      end
      inventory.remove(stack)
      return
    end
  end

  -- The same entity already there: turn it (like building a belt over itself), costing nothing.
  local same = same_entity(surface, proto, position)
  if same and quality_name(same) == quality then
    if same.direction ~= direction and same.rotatable and same.force == c.force then
      same.direction = direction
      tracker.changed(same)
    end
    return
  end

  local spec = { name = proto.name, position = position, direction = direction, force = c.force, raise_built = true }
  if cmd.m == 1 then
    spec.mirror = true
  end
  if proto.type == "underground-belt" then
    spec.type = underground_type(surface, proto, position, direction)
  end
  if quality ~= "normal" then
    spec.quality = quality
  end
  -- Fast-replace first: can_place_entity also answers true where the entity would replace what
  -- stands there (2.1), but create_entity without fast_replace then builds nothing.
  local old = replaced_entity(surface, proto, position)
  local entity
  if old and surface.can_fast_replace({ name = proto.name, position = position, direction = direction, force = c.force }) then
    -- Fast-replace without a player: the old entity's items are ours to hand back, and its
    -- removal ours to report (the game raises no destroy event for it).
    local removal = tracker.removal_message(old)
    local products = old.prototype.mineable_properties.products or {}
    local old_quality = quality_name(old)
    spec.fast_replace = true
    spec.spill = false
    entity = surface.create_entity(spec)
    if entity then
      if removal and not old.valid then
        transport.send_reliable(removal)
      end
      for _, product in pairs(products) do
        if product.type == "item" then
          local stack = { name = product.name, count = product.amount or product.amount_min or 1 }
          if old_quality ~= "normal" then
            stack.quality = old_quality
          end
          give(c, stack)
        end
      end
    end
  elseif surface.can_place_entity({
    name = proto.name, position = position, direction = direction, force = c.force,
    build_check_type = defines.build_check_type.manual,
  }) then
    entity = surface.create_entity(spec)
  else
    -- Space Age: the planet's pressure, gravity or magnetic field may be what forbids it.
    return puppet.message(space.cant_build(surface, proto) or "Can't place that there")
  end
  if not entity then
    return puppet.message("Can't place that there")
  end
  local stack = { name = item_name, count = 1 }
  if quality ~= "normal" then
    stack.quality = quality
  end
  inventory.remove(stack)
end

return M
