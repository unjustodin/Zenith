-- The rail planner (Factorio 2.x): the client works out the path of straight, half-diagonal and
-- curved pieces from a rail end to the cursor with the game's own extension table (the pieces
-- LuaRailEnd.get_rail_extensions offers from each end direction), and sends the pieces; this
-- builds them in order from the character's rails, as ghosts where there are too few rails or
-- they are out of reach, as the planner does. Elevated rails come with their supports, which the
-- client lists first: an elevated rail needs a support in range along the track already built.

local puppet = require("scripts.puppet")
local map = require("scripts.map")

local M = {}

M.MAX_PIECES = 200
local REACH_SLACK = 1.5

-- The rail and support prototypes a planner item may build.
local function allowed(item)
  local out = {}
  local ok, rails = pcall(function() return item.rails end)
  for _, r in pairs(ok and rails or {}) do
    out[r.name] = true
  end
  local oks, support = pcall(function() return item.support end)
  if oks and support then
    out[support.name] = true
  end
  return out
end

local function cost(proto)
  local need = proto.items_to_place_this and proto.items_to_place_this[1]
  if need then
    return need.name, need.count or 1
  end
  return nil, 0
end

local function exists(surface, name, position, direction)
  for _, e in pairs(surface.find_entities_filtered({ name = name, position = position })) do
    if e.direction == direction then
      return true
    end
  end
  for _, g in pairs(surface.find_entities_filtered({ ghost_name = name, position = position })) do
    if g.direction == direction then
      return true
    end
  end
  return false
end

-- {item, l: [[entity name, x, y (fixed), direction], ...], ghost? (1: all ghosts)}: builds the
-- planner's path. Pieces already there are skipped; the rest are built from the character's
-- items while they last and in reach, ghosts after that. Nothing is built if a piece can't go
-- where it should (the client draws that path red).
function M.build(cmd)
  local c = puppet.get()
  if not c then
    return
  end
  local item_name = tostring(cmd.item or "")
  local item = prototypes.item[item_name]
  if not item then
    return
  end
  local ok_names = allowed(item)
  local pieces = {}
  local surface = puppet.surface(c)
  for i, rec in pairs(type(cmd.l) == "table" and cmd.l or {}) do
    if i > M.MAX_PIECES then
      break
    end
    local name = tostring(rec[1] or "")
    local proto = prototypes.entity[name]
    local x, y = tonumber(rec[2]), tonumber(rec[3])
    if not proto or not ok_names[name] or not x or not y then
      return puppet.message("Can't build that with " .. item_name)
    end
    local position = { x = x / 256, y = y / 256 }
    local direction = math.floor(tonumber(rec[4]) or 0) % 16
    if not exists(surface, name, position, direction) then
      pieces[#pieces + 1] = { proto = proto, position = position, direction = direction }
    end
  end
  if #pieces == 0 then
    return
  end
  local all_ghosts = cmd.ghost == 1
  if all_ghosts and not map.check_charted(c, pieces[1].position) then
    return
  end
  for _, p in pairs(pieces) do
    -- An elevated rail can only be placed next to the track a support already holds up, which
    -- the pieces before it make: check those as ghosts here; one that still can't be built when
    -- its turn comes becomes a ghost.
    local elevated = string.sub(p.proto.name, 1, 9) == "elevated-"
    local check = (all_ghosts or elevated) and defines.build_check_type.manual_ghost or defines.build_check_type.manual
    if not surface.can_place_entity({ name = p.proto.name, position = p.position, direction = p.direction,
        force = c.force, build_check_type = check }) then
      return puppet.message("Can't place that there")
    end
  end
  local inventory = c.get_main_inventory()
  local ghosts = 0
  for _, p in pairs(pieces) do
    local need_name, need = cost(p.proto)
    local dx, dy = p.position.x - c.position.x, p.position.y - c.position.y
    local reach = math.sqrt(dx * dx + dy * dy) <= c.build_distance + REACH_SLACK
    local real = not all_ghosts and reach and need_name and inventory and inventory.get_item_count(need_name) >= need
      and surface.can_place_entity({ name = p.proto.name, position = p.position, direction = p.direction, force = c.force,
        build_check_type = defines.build_check_type.manual })
    local spec = { position = p.position, direction = p.direction, force = c.force, raise_built = true }
    if real then
      spec.name = p.proto.name
    else
      spec.name = "entity-ghost"
      spec.inner_name = p.proto.name
    end
    local ok, e = pcall(surface.create_entity, spec)
    if ok and e then
      if real then
        inventory.remove({ name = need_name, count = need })
      else
        ghosts = ghosts + 1
      end
    end
  end
  if ghosts > 0 and not all_ghosts then
    puppet.message(ghosts .. " rail pieces placed as ghosts")
  end
end

return M
