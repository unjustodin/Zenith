-- Tiles from the character's inventory, as a player paints them: stone brick, concrete, landfill,
-- foundation and the rest, in a square brush (Factorio's "larger/smaller tile area"); tile ghosts
-- for the robots; and mining placed tiles back. Also `iuse`, what the client needs to know about
-- items that aren't built as entities (tiles, capsules, rail planners) and the parts drag
-- building puts in by itself (a belt's underground, a pipe's pipe-to-ground).

local registry = require("scripts.registry")
local transport = require("scripts.transport")
local puppet = require("scripts.puppet")
local world = require("scripts.world")
local map = require("scripts.map")
local tracker = require("scripts.tracker")

local M = {}

M.MAX_BRUSH = 32 -- the client clamps too; a bigger brush only costs more script time
local REACH_SLACK = 1.5

local function placement(item_name)
  local item = prototypes.item[item_name]
  if not item then
    return nil
  end
  local ok, r = pcall(function() return item.place_as_tile_result end)
  return ok and r or nil
end

local function intersects(a, b)
  for layer in pairs(a or {}) do
    if b and b[layer] then
      return true
    end
  end
  return false
end

-- Whether an item's tile may go on a tile, by its place_as_tile condition: the tile it goes on
-- must not collide with the condition's layers (inverted: must), and when a tile_condition list is
-- given, must be one of those.
local function allowed_on(result, tile_proto)
  local mask = tile_proto.collision_mask
  local hit = intersects(result.condition and result.condition.layers, mask and mask.layers)
  if hit ~= (result.invert == true) then
    return false
  end
  local list = result.tile_condition
  if list and #list > 0 then
    for _, t in pairs(list) do
      if t.name == tile_proto.name then
        return true
      end
    end
    return false
  end
  return true
end

-- The tile an item paints: hazard concrete's other direction when `alt` (R turns the stripes).
local function tile_for(result, alt)
  local tile = result.result
  if alt then
    local ok, other = pcall(function() return tile.next_direction end)
    if ok and other then
      return other
    end
  end
  return tile
end

-- The tile positions of an n-tile square brush at (x, y): odd sizes centre on the tile under the
-- cursor, even sizes on the nearest tile corner, as in Factorio.
function M.brush(x, y, n)
  local x0, y0
  if n % 2 == 1 then
    x0, y0 = math.floor(x) - (n - 1) / 2, math.floor(y) - (n - 1) / 2
  else
    x0, y0 = math.floor(x + 0.5) - n / 2, math.floor(y + 0.5) - n / 2
  end
  local out = {}
  for dy = 0, n - 1 do
    for dx = 0, n - 1 do
      out[#out + 1] = { x = x0 + dx, y = y0 + dy }
    end
  end
  return out
end

local function in_reach(c, p)
  if storage.f3d.act_si then
    return false -- from the remote view on another surface only ghosts go down
  end
  local dx, dy = p.x + 0.5 - c.position.x, p.y + 0.5 - c.position.y
  return math.sqrt(dx * dx + dy * dy) <= c.build_distance + REACH_SLACK
end

-- An entity in the way of the new tile (an entity that collides with it), so the tile isn't laid.
local function blocked(surface, tile_proto, p)
  local mask = tile_proto.collision_mask
  local layers = {}
  for layer in pairs(mask and mask.layers or {}) do
    layers[#layers + 1] = layer
  end
  if #layers == 0 then
    return false
  end
  local ok, n = pcall(function()
    return surface.count_entities_filtered({
      area = { { p.x + 0.05, p.y + 0.05 }, { p.x + 0.95, p.y + 0.95 } },
      collision_mask = layers, limit = 1,
    })
  end)
  return ok and n > 0
end

-- Items go to the character; what doesn't fit is spilled at its feet.
local function give(c, stack)
  local inserted = c.insert(stack)
  if inserted < stack.count then
    stack.count = stack.count - inserted
    pcall(function() c.surface.spill_item_stack({ position = c.position, stack = stack }) end)
  end
end

local function ghost_tile(surface, force, name, p)
  local ok = pcall(function()
    surface.create_entity({ name = "tile-ghost", inner_name = name, position = { p.x + 0.5, p.y + 0.5 }, force = force,
      raise_built = true })
  end)
  return ok
end

-- {item, x, y (fixed: the brush's centre), n (brush size), ghost? (1: tile ghosts), r? (1: hazard
-- concrete's other direction)}: lays the item's tile under the brush where it may go, one item
-- each, handing back what the old tile is mined into. Ghosts need no items or reach.
function M.place(cmd)
  local c = puppet.get()
  if not c then
    return
  end
  local item_name = tostring(cmd.item or "")
  local result = placement(item_name)
  if not result then
    return puppet.message("Can't place " .. item_name .. " as tiles")
  end
  local x, y = tonumber(cmd.x), tonumber(cmd.y)
  if not x or not y then
    return
  end
  local n = math.max(1, math.min(M.MAX_BRUSH, math.floor(tonumber(cmd.n) or 1)))
  local tile = tile_for(result, cmd.r == 1)
  local surface = puppet.surface(c)
  local ghost = cmd.ghost == 1
  if ghost and not map.check_charted(c, { x = x / 256, y = y / 256 }) then
    return
  end
  local inventory = c.get_main_inventory()
  local have = (not ghost and inventory) and inventory.get_item_count(item_name) or 0
  local tiles, ghosts, refunds = {}, {}, {}
  local skipped_reach = false
  for _, p in pairs(M.brush(x / 256, y / 256, n)) do
    local old = surface.get_tile(p.x, p.y)
    local old_proto = old.valid and old.prototype
    if old_proto and old_proto.name ~= tile.name and allowed_on(result, old_proto)
        and not blocked(surface, tile, p) then
      if ghost then
        if not old.has_tile_ghost(c.force) then
          ghosts[#ghosts + 1] = p
        end
      elseif not in_reach(c, p) then
        skipped_reach = true
      elseif #tiles < have then
        tiles[#tiles + 1] = { name = tile.name, position = p }
        -- A mineable tile under it comes back as its item, as when a player paints over it.
        local mp = old_proto.mineable_properties
        if mp and mp.minable and not old_proto.is_foundation then
          for _, product in pairs(mp.products or {}) do
            if product.type == "item" then
              refunds[product.name] = (refunds[product.name] or 0) + (product.amount or product.amount_min or 1)
            end
          end
        end
      end
    end
  end
  for _, p in pairs(ghosts) do
    ghost_tile(surface, c.force, tile.name, p)
  end
  if #tiles > 0 then
    surface.set_tiles(tiles, true, false, true, true)
    inventory.remove({ name = item_name, count = #tiles })
    for name, count in pairs(refunds) do
      give(c, { name = name, count = count })
    end
  elseif not ghost and #ghosts == 0 then
    if have == 0 then
      puppet.message("You have no " .. item_name)
    elseif skipped_reach then
      puppet.message("Out of reach")
    end
  end
end

-- {x, y (fixed), n}: mines the placed tiles under the brush back into the inventory, as a
-- player's right click does with a tile in hand (LuaControl.mine_tile gives the item and puts
-- back the tile underneath), and removes tile ghosts there.
function M.mine(cmd)
  local c = puppet.get()
  if not c then
    return
  end
  local x, y = tonumber(cmd.x), tonumber(cmd.y)
  if not x or not y then
    return
  end
  local n = math.max(1, math.min(M.MAX_BRUSH, math.floor(tonumber(cmd.n) or 1)))
  local surface = puppet.surface(c)
  local changed = {}
  for _, p in pairs(M.brush(x / 256, y / 256, n)) do
    local tile = surface.get_tile(p.x, p.y)
    for _, g in pairs(tile.get_tile_ghosts(c.force)) do
      local removal = tracker.removal_message(g)
      g.destroy()
      if removal then
        transport.send_reliable(removal)
      end
    end
    local mp = tile.valid and tile.prototype.mineable_properties
    if mp and mp.minable and in_reach(c, p) then
      local ok, mined = pcall(c.mine_tile, tile)
      if ok and mined then
        changed[#changed + 1] = p
      end
    end
  end
  if #changed > 0 then
    world.tiles_changed(surface, changed)
  end
end

---------------------------------------------------------------------------------------------

-- What a capsule does when used, for the client's cursor: [type, range, radius].
local function capsule_info(item)
  local ok, action = pcall(function() return item.capsule_action end)
  if not ok or not action then
    return nil
  end
  local range = action.attack_parameters and action.attack_parameters.range or 0
  local radius = action.radius or 0
  if radius == 0 then
    -- A grenade's blast: the area of the projectile's explosion isn't exposed; use the
    -- attack's own area when it has one.
    pcall(function()
      for _, a in pairs(action.attack_parameters.ammo_type.action or {}) do
        for _, d in pairs(a.action_delivery or {}) do
          if d.target_effects then
            for _, e in pairs(d.target_effects) do
              if e.radius then
                radius = e.radius
              end
            end
          end
        end
      end
    end)
  end
  return { action.type, math.floor(range * 10 + 0.5) / 10, math.floor(radius * 10 + 0.5) / 10 }
end

-- `iuse`: [[item, kind, ...], ...] for the items the client uses other than by building their
-- entity: "t" tiles [item, "t", tile, other direction's tile or "", [tile ids it may go on]];
-- "c" capsules [item, "c", action type, range, radius]; "r" rail planners [item, "r", support
-- entity or "", elevated rails allowed 0/1]; "b" belts [item, "b", their underground belt's item];
-- "p" pipes [item, "p", their pipe-to-ground's item]; "m" modules [item, "m", module category].
-- Prototypes only but for the force's elevated rails, so kept per that (12 ms on Space Age, every
-- handshake).
local iuse_cache = {}

local function build_item_uses(allow_elevated)
  local tile_protos = {}
  for _, t in pairs(prototypes.tile) do
    tile_protos[#tile_protos + 1] = t
  end
  local l = {}
  for name, item in pairs(prototypes.item) do
    local result = placement(name)
    if result then
      local on = {}
      for _, t in pairs(tile_protos) do
        if t.name ~= result.result.name and allowed_on(result, t) then
          on[#on + 1] = registry.tile_id(t.name)
        end
      end
      table.sort(on)
      local other = tile_for(result, true)
      l[#l + 1] = { name, "t", result.result.name, other.name ~= result.result.name and other.name or "", on }
    end
    local cap = capsule_info(item)
    if cap then
      l[#l + 1] = { name, "c", cap[1], cap[2], cap[3] }
    end
    local okr, rails = pcall(function() return item.rails end)
    if okr and rails and #rails > 0 and registry.place_result(item) and registry.place_result(item).type == "straight-rail" then
      local oks, support = pcall(function() return item.support end)
      local elevated = allow_elevated and 1 or 0
      l[#l + 1] = { name, "r", oks and support and support.name or "", elevated }
    end
    if item.type == "module" then
      local okm, cat = pcall(function() return item.category end)
      l[#l + 1] = { name, "m", okm and cat or "" }
    end
    local place = registry.place_result(item)
    if place and place.type == "transport-belt" then
      local ok, ub = pcall(function() return place.related_underground_belt end)
      local ub_item = ok and ub and ub.items_to_place_this and ub.items_to_place_this[1]
      if ub_item then
        l[#l + 1] = { name, "b", ub_item.name }
      end
    elseif place and place.type == "pipe" and prototypes.item[name .. "-to-ground"] then
      l[#l + 1] = { name, "p", name .. "-to-ground" }
    end
  end
  table.sort(l, function(a, b) return a[1] < b[1] or (a[1] == b[1] and a[2] < b[2]) end)
  return l
end

-- control.lua's warm-up: both lists made before a client asks.
function M.warm_item_uses(elevated)
  iuse_cache[elevated] = iuse_cache[elevated] or build_item_uses(elevated)
end

function M.item_uses()
  local c = puppet.get()
  local elevated = (c and c.force.rail_planner_allow_elevated_rails) and true or false
  local l = iuse_cache[elevated]
  if not l then
    l = build_item_uses(elevated)
    iuse_cache[elevated] = l
  end
  local per = 20
  local parts = math.max(1, math.ceil(#l / per))
  for i = 1, parts do
    local chunk = {}
    for k = (i - 1) * per + 1, math.min(#l, i * per) do
      chunk[#chunk + 1] = l[k]
    end
    transport.send_reliable({ t = "iuse", part = i, parts = parts, l = chunk })
  end
end

return M
