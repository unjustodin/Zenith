-- Blueprints and planners: place a blueprint's ghosts, mark an area for deconstruction or upgrade
-- or cancel that, super-forced building, and moving blueprints, books and planners to and from
-- the client as Factorio's exchange strings (LuaItemStack.export_stack / import_stack), which is
-- how the client's blueprint library, blueprint editor, book window and planner windows read and
-- write them. A player-less character has no cursor, so the client names the main inventory slot
-- holding the planner (`i`), or -1 for the stack it took from its library (the mod keeps that one
-- in a script inventory, like the clipboard). Robots do the building and removing, as they do for
-- a player. Undo entries go to history.lua.

local puppet = require("scripts.puppet")
local map = require("scripts.map")
local world = require("scripts.world")
local transport = require("scripts.transport")
local history = require("scripts.history")
local tracker = require("scripts.tracker")
local ui_actions = require("scripts.ui_actions")

local M = {}

-- Strings go to the client in parts of this many characters (reliable messages; a datagram can't
-- carry more than 64 KB, and a player's book can be several hundred).
local PART = 16000

-- The stack the client took from its library (i = -1): a blueprint, book or planner that isn't in
-- the inventory, as a library record in Factorio's cursor isn't.
local function cursor_stack()
  local s = storage.f3d
  if not (s.lib_cursor and s.lib_cursor.valid) then
    s.lib_cursor = game.create_inventory(1)
  end
  return s.lib_cursor[1]
end

-- The stack at `i` (main inventory slot, or -1 for the library one); with `empty`, also an empty one.
local function stack_at(c, i, empty)
  i = math.floor(tonumber(i) or 0)
  local stack
  if i == -1 then
    stack = cursor_stack()
  else
    local inventory = c.get_main_inventory()
    if not inventory or i < 1 or i > #inventory then
      return nil
    end
    stack = inventory[i]
  end
  if empty or stack.valid_for_read then
    return stack
  end
  return nil
end
M.stack_at = stack_at
-- ui_actions.copy writes a reselected blueprint through this (planners requires ui_actions).
ui_actions.blueprint_stack = stack_at

-- A book stands for its active page.
local function blueprint_of(stack)
  if stack.is_blueprint_book then
    local ok, page = pcall(function()
      return stack.get_inventory(defines.inventory.item_main)[stack.active_index]
    end)
    return ok and page or nil
  end
  return stack
end

local function area_of(cmd)
  local x1, y1 = (tonumber(cmd.x1) or 0) / 256, (tonumber(cmd.y1) or 0) / 256
  local x2, y2 = (tonumber(cmd.x2) or 0) / 256, (tonumber(cmd.y2) or 0) / 256
  return { { math.min(x1, x2), math.min(y1, y2) }, { math.max(x1, x2), math.max(y1, y2) } }
end

local function centre_of(area)
  return { x = (area[1][1] + area[2][1]) / 2, y = (area[1][2] + area[2][2]) / 2 }
end

-- Factorio's three ways of placing a blueprint: a click (normal: only where nothing is in the
-- way), Shift+click (forced: trees and rocks in the way are marked for deconstruction), and
-- Ctrl+Shift+click (super-forced). `bm` 0, 1, 2; without it forced, as older clients expect.
local function build_mode(cmd)
  local bm = tonumber(cmd.bm)
  if cmd.sf == 1 or bm == 2 then
    return defines.build_mode.superforced
  elseif bm == 0 then
    return defines.build_mode.normal
  end
  return defines.build_mode.forced
end

---------------------------------------------------------------------------------------------
-- Commands

-- Flipping a held blueprint (H / V): build_blueprint has no mirror, so the blueprint's entities and
-- tiles are mirrored into a copy (east-west: x to -x, directions reflected, Factorio's `mirror`
-- flag on the machines that flip, splitter sides swapped, custom inserter vectors mirrored). A
-- vertical flip is this turned half way round (the client adds 8 to the direction). Rails mirror
-- to other directions of the same rail (found in the real game: tools/live_check.py check_flips).
-- Signals, train stops and rolling stock are refused (FLIP_REFUSED): which side of the track they
-- stand on changes, and that hasn't been checked against the game.
local MIRROR_TYPES = { ["assembling-machine"] = true, ["furnace"] = true }
local FLIP_REFUSED = { ["rail-signal"] = true, ["rail-chain-signal"] = true, ["train-stop"] = true, ["locomotive"] = true,
  ["cargo-wagon"] = true, ["fluid-wagon"] = true, ["artillery-wagon"] = true }
local RAIL_MIRROR = {
  ["straight-rail"] = function(d) return (16 - d) % 8 end, ["elevated-straight-rail"] = function(d) return (16 - d) % 8 end,
  ["half-diagonal-rail"] = function(d) return (18 - d) % 8 end, ["elevated-half-diagonal-rail"] = function(d) return (18 - d) % 8 end,
  ["curved-rail-a"] = function(d) return (18 - d) % 16 end, ["elevated-curved-rail-a"] = function(d) return (18 - d) % 16 end,
  ["curved-rail-b"] = function(d) return (18 - d) % 16 end, ["elevated-curved-rail-b"] = function(d) return (18 - d) % 16 end,
}
M.FLIP_REFUSED = FLIP_REFUSED

local function flip_side(v)
  if v == "left" then
    return "right"
  elseif v == "right" then
    return "left"
  end
  return v
end

local function mirror_vector(v)
  if type(v) ~= "table" then
    return v
  end
  if v.x then
    return { x = -v.x, y = v.y }
  end
  return { -v[1], v[2] }
end

-- A copy of bp mirrored east-west in the history's scratch stack, or nil and why not.
local function mirrored(bp)
  local entities = bp.get_blueprint_entities() or {}
  for _, e in pairs(entities) do
    local proto = prototypes.entity[e.name]
    local t = proto and proto.type or ""
    if FLIP_REFUSED[t] then
      return nil, "Blueprints with " .. t .. " can't be flipped here"
    end
    e.position = mirror_vector(e.position)
    e.direction = RAIL_MIRROR[t] and RAIL_MIRROR[t](e.direction or 0) or (16 - (e.direction or 0)) % 16
    if MIRROR_TYPES[t] then
      e.mirror = not e.mirror or nil
    end
    if t == "splitter" or t == "lane-splitter" then
      e.input_priority = flip_side(e.input_priority)
      e.output_priority = flip_side(e.output_priority)
    elseif t == "inserter" then
      e.pickup_position = e.pickup_position and mirror_vector(e.pickup_position) or nil
      e.drop_position = e.drop_position and mirror_vector(e.drop_position) or nil
    end
  end
  local tiles = bp.get_blueprint_tiles() or {}
  for _, tile in pairs(tiles) do
    local x = tile.position.x or tile.position[1]
    local y = tile.position.y or tile.position[2]
    tile.position = { x = -x - 1, y = y }
  end
  local copy = history.scratch()
  copy.set_stack({ name = "blueprint", count = 1 })
  copy.set_blueprint_entities(entities)
  if #tiles > 0 then
    copy.set_blueprint_tiles(tiles)
  end
  return copy
end
M.mirrored = mirrored

-- {i (main inventory slot, -1 the library one), x, y (fixed), d, sf? (1: super-forced), bm? (0
-- normal, 1 forced, 2 super-forced), m? (1: flipped east-west)}: the blueprint's ghosts, centred
-- there.
function M.blueprint(cmd)
  local c = puppet.get()
  local stack = c and stack_at(c, cmd.i)
  local bp = stack and blueprint_of(stack)
  if not (bp and bp.valid_for_read and bp.is_blueprint and bp.is_blueprint_setup()) then
    return puppet.message("That isn't a blueprint")
  end
  local fx, fy = tonumber(cmd.x), tonumber(cmd.y)
  if not fx or not fy then
    return
  end
  if not map.check_charted(c, { x = fx / 256, y = fy / 256 }) then
    return
  end
  local flipped
  if cmd.m == 1 then
    local why
    flipped, why = mirrored(bp)
    if not flipped then
      return puppet.message(why)
    end
    bp = flipped
  end
  local ghosts = history.place(c, bp, { fx / 256, fy / 256 }, math.floor(tonumber(cmd.d) or 0) % 16, build_mode(cmd))
  if flipped then
    flipped.clear()
  end
  if #ghosts == 0 then
    puppet.message("Nothing to place there")
  end
end

-- {item, x, y, d, q?, m?}: Ctrl+Shift+click, Factorio's super-forced build: a ghost of the held
-- item's entity, and whatever stands in the way (trees, rocks, buildings) marked for
-- deconstruction. Built through a one-entity blueprint, which is how the game does it.
function M.superforced(cmd)
  local c = puppet.get()
  if not c then
    return
  end
  local item = prototypes.item[tostring(cmd.item or "")]
  local proto = item and item.place_result
  local fx, fy = tonumber(cmd.x), tonumber(cmd.y)
  if not proto or not fx or not fy then
    return puppet.message("That can't be built")
  end
  local at = { fx / 256, fy / 256 }
  if not map.check_charted(c, { x = at[1], y = at[2] }) then
    return
  end
  local stack = history.scratch()
  stack.set_stack({ name = "blueprint", count = 1 })
  local e = { entity_number = 1, name = proto.name, position = { x = 0, y = 0 }, direction = math.floor(tonumber(cmd.d) or 0) % 16 }
  if cmd.q and cmd.q ~= "normal" then
    e.quality = tostring(cmd.q)
  end
  if cmd.m == 1 then
    e.mirror = true
  end
  stack.set_blueprint_entities({ e })
  local ghosts = history.place(c, stack, at, 0, defines.build_mode.superforced)
  stack.clear()
  if #ghosts == 0 then
    puppet.message("Can't build there")
  end
end

-- {i (slot of a deconstruction planner, -1 the library one, or 0 for everything), x1, y1, x2, y2,
-- cancel, nh? (1: not remembered for undo)}: marks the area for deconstruction, or with cancel = 1 unmarks it. Without a planner it
-- works like Factorio's deconstruction shortcut, on everything of the character's force and trees
-- and rocks.
function M.decon(cmd)
  local c = puppet.get()
  if not c then
    return
  end
  local spec = { surface = puppet.surface(c), force = c.force, area = area_of(cmd) }
  if not map.check_charted(c, centre_of(spec.area)) then
    return
  end
  local cancel = cmd.cancel == 1 or cmd.cancel == true
  local stack
  if (tonumber(cmd.i) or 0) ~= 0 then
    stack = stack_at(c, cmd.i)
    if not (stack and stack.is_deconstruction_item) then
      return puppet.message("That isn't a deconstruction planner")
    end
  end
  local before = cancel and history.marked(puppet.surface(c), spec.area, false) or history.unmarked(puppet.surface(c), spec.area, false)
  if cancel then
    if stack then
      stack.cancel_deconstruct_area(spec)
    else
      spec.surface = nil
      puppet.surface(c).cancel_deconstruct_area(spec)
    end
  elseif (tonumber(cmd.u) or 0) > 0 then
    -- One entity by its unit number (a train mined from the remote view: not the rail under it).
    local at = centre_of(spec.area)
    local e = puppet.find_target(puppet.surface(c), { x = world.fixed(at.x), y = world.fixed(at.y), u = cmd.u, p = cmd.p })
    if e and e.valid and e.force == c.force then
      e.order_deconstruction(c.force)
    end
  else
    tracker.deconstructing(puppet.surface(c), spec.area, c.force, function()
      if stack then
        stack.deconstruct_area(spec)
      else
        spec.surface = nil
        puppet.surface(c).deconstruct_area(spec)
      end
    end)
  end
  -- nh: the client's own undo of a building sends this; it isn't an action of its own.
  if cmd.nh ~= 1 then
    history.marks(c, before, false, cancel)
  end
end

-- A copy of an upgrade planner with every mapping the other way round (in the history's scratch
-- stack): Factorio's downgrade, its right-drag.
local function reversed(stack)
  local copy = history.scratch()
  copy.set_stack({ name = "upgrade-planner", count = 1 })
  for i = 1, stack.mapper_count do
    local from, to = stack.get_mapper(i, "from"), stack.get_mapper(i, "to")
    if from and from.name and to and to.name then
      copy.set_mapper(i, "from", to)
      copy.set_mapper(i, "to", from)
    end
  end
  return copy
end

-- {i (slot of an upgrade planner, -1 the library one), x1, y1, x2, y2, cancel, down? (1: the
-- mappings the other way round, Factorio's right-drag downgrade)}: marks the area for upgrade by
-- the planner's mappings, or with cancel = 1 unmarks it.
function M.upgrade(cmd)
  local c = puppet.get()
  if not c then
    return
  end
  local stack = stack_at(c, cmd.i)
  if not (stack and stack.is_upgrade_item) then
    return puppet.message("That isn't an upgrade planner")
  end
  -- Unlike deconstruction planners, upgrade planners have no area methods (2.1): the surface
  -- takes the planner as `item`.
  local spec = { force = c.force, area = area_of(cmd), item = stack }
  if not map.check_charted(c, centre_of(spec.area)) then
    return
  end
  local cancel = cmd.cancel == 1 or cmd.cancel == true
  local down = cmd.down == 1 and not cancel
  local before = cancel and history.marked(puppet.surface(c), spec.area, true) or history.unmarked(puppet.surface(c), spec.area, true)
  if cancel then
    puppet.surface(c).cancel_upgrade_area(spec)
  elseif down then
    spec.item = reversed(stack)
    puppet.surface(c).upgrade_area(spec)
    spec.item.clear()
  else
    puppet.surface(c).upgrade_area(spec)
  end
  history.marks(c, before, true, cancel)
end

-- {i}: the planner window's delete button: the blueprint, book or planner at slot `i` (-1 the
-- library one) is destroyed, as Factorio's red trash button does.
function M.delete(cmd)
  local c = puppet.get()
  local stack = c and stack_at(c, cmd.i)
  if stack and (stack.is_blueprint or stack.is_blueprint_book or stack.is_deconstruction_item or stack.is_upgrade_item) then
    stack.clear()
  end
end

-- {u, p, x, y, rev}: R over an entity, remembered for undo.
function M.rotate(cmd)
  local c = puppet.get()
  local e = c and puppet.find_target(puppet.surface(c), cmd)
  local was = e and e.direction
  puppet.rotate(cmd)
  if e and e.valid and e.direction ~= was then
    history.rotate(e, cmd.rev == 1 or cmd.rev == true)
  end
end

-- Shift+left click (ui_actions.paste_settings), with the target's settings before and after kept
-- for undo.
function M.paste_settings(cmd)
  local c = puppet.get()
  local e = c and puppet.find_target(puppet.surface(c), cmd)
  local before = e and history.snapshot(e) or ""
  ui_actions.paste_settings(cmd)
  if e and e.valid then
    history.settings(c, e, before, history.snapshot(e))
  end
end

---------------------------------------------------------------------------------------------
-- Exchange strings: the client's library and editors

-- Sends a string in parts: `bp` {q, part, parts, s, item, i, ...extra}.
local function send_string(q, data, item, i, extra)
  local n = math.max(1, math.ceil(#data / PART))
  for k = 1, n do
    local msg = { t = "bp", q = q, part = k, parts = n, s = data:sub((k - 1) * PART + 1, k * PART), item = item or "", i = i or 0 }
    for key, v in pairs(extra or {}) do
      msg[key] = v
    end
    transport.send_reliable(msg)
  end
end

-- {q, i}: the blueprint, book or planner at slot `i` (-1 the library one) as an exchange string.
function M.get(cmd)
  local c = puppet.get()
  local stack = c and stack_at(c, cmd.i)
  local q = math.floor(tonumber(cmd.q) or 0)
  local ok, data = false, nil
  if stack and (stack.is_blueprint or stack.is_blueprint_book or stack.is_deconstruction_item or stack.is_upgrade_item) then
    ok, data = pcall(function() return stack.export_stack() end)
  end
  if not ok or type(data) ~= "string" or data == "" then
    return send_string(q, "", "", math.floor(tonumber(cmd.i) or 0), { err = "Nothing to export there" })
  end
  send_string(q, data, stack.name, math.floor(tonumber(cmd.i)))
end

-- Parts of a string the client sends (`bp_set` with id, part, parts, d): kept until all have arrived.
local function assemble(cmd)
  if type(cmd.s) == "string" then
    return cmd.s
  end
  local s = storage.f3d
  local id = math.floor(tonumber(cmd.id) or 0)
  local n = math.floor(tonumber(cmd.parts) or 0)
  local k = math.floor(tonumber(cmd.part) or 0)
  if n < 1 or k < 1 or k > n or n > 4096 or type(cmd.d) ~= "string" then
    return nil
  end
  if not (s.bp_up and s.bp_up.id == id) then
    s.bp_up = { id = id, n = n, got = 0, parts = {} }
  end
  local up = s.bp_up
  if not up.parts[k] then
    up.parts[k] = cmd.d
    up.got = up.got + 1
  end
  if up.got < up.n then
    return nil
  end
  s.bp_up = nil
  return table.concat(up.parts)
end

-- Imports a string into a stack: into slot `i`, an empty slot of the main inventory (i = 0), or the
-- library one (-1). Returns the slot it went to, or nil.
local function import_into(c, i, data)
  i = math.floor(tonumber(i) or 0)
  local stack, slot = nil, i
  if i == 0 then
    local inventory = c.get_main_inventory()
    if inventory then
      stack, slot = inventory.find_empty_stack()
    end
    if not stack then
      puppet.message("Inventory full")
      return nil
    end
  else
    stack = stack_at(c, i, true)
  end
  if not stack then
    return nil
  end
  -- import_stack turns any stack into the string's item; a stack of something else is left alone.
  if stack.valid_for_read and not (stack.is_blueprint or stack.is_blueprint_book or stack.is_deconstruction_item
      or stack.is_upgrade_item) then
    puppet.message("That slot holds something else")
    return nil
  end
  local ok, result = pcall(function() return stack.import_stack(data) end)
  if not ok or result == 1 then
    puppet.message("That isn't a blueprint string Factorio can import")
    return nil
  end
  if result == -1 then
    puppet.message("Imported, with errors (some of it isn't in this game)")
  end
  if i ~= -1 then
    puppet.send_inventory_now()
  end
  return slot
end

-- {q, i, s} or {q, i, id, part, parts, d} (the string in parts): writes the string into slot `i` (0: a new
-- one in the main inventory, -1: the library one in the cursor). Answers `bp_ok` {q, i, item}.
function M.set(cmd)
  local c = puppet.get()
  local data = assemble(cmd)
  if not (c and data) then
    return
  end
  local slot = import_into(c, cmd.i, data)
  if slot then
    local stack = stack_at(c, slot)
    transport.send_reliable({ t = "bp_ok", q = math.floor(tonumber(cmd.q) or 0), i = slot, item = stack and stack.name or "" })
  end
end

-- {i, a}: a book's active page (1-based), as Factorio's book cycling sets it.
function M.page(cmd)
  local c = puppet.get()
  local stack = c and stack_at(c, cmd.i)
  if not (stack and stack.is_blueprint_book) then
    return
  end
  local inventory = stack.get_inventory(defines.inventory.item_main)
  local a = math.floor(tonumber(cmd.a) or 1)
  if inventory and a >= 1 and a <= #inventory and inventory[a].valid_for_read then
    stack.active_index = a
  end
end

-- The blueprint library records the mod can read: the game's ("game blueprints", kept in the
-- save) and, when the bridge plays a save's own player (takeover.lua), that player's library,
-- which a multiplayer save keeps for offline players (checked in 2.1.23: readable and exportable).
local function libraries()
  local out = {}
  local ok, game_records = pcall(function() return game.blueprints end)
  out[#out + 1] = { src = "game", who = "", records = ok and game_records or {} }
  local owner = storage.f3d.owner_index and game.get_player(storage.f3d.owner_index)
  if owner then
    local ok_p, records = pcall(function() return owner.blueprints end)
    out[#out + 1] = { src = "player", who = owner.name, records = ok_p and records or {} }
  end
  return out
end

local function record_of(src, ix)
  for _, lib in pairs(libraries()) do
    if lib.src == src then
      return lib.records[ix]
    end
  end
  return nil
end

local function icons_of(r)
  local out = {}
  local ok, icons = pcall(function() return r.preview_icons end)
  for _, icon in pairs(ok and icons or {}) do
    local sig = icon.signal or {}
    if sig.name then
      out[#out + 1] = { sig.type or "item", sig.name }
    end
  end
  return out
end

-- {}: lists those libraries: `bpl` {src, who, l: [[index, type, label, icons]]} each.
function M.library(_)
  for _, lib in pairs(libraries()) do
    local l = {}
    for ix, r in pairs(lib.records) do
      local ok, t = pcall(function() return r.type end)
      if ok then
        local ok_l, label = pcall(function() return r.label end)
        l[#l + 1] = { ix, t, ok_l and label or "", icons_of(r) }
      end
    end
    transport.send_reliable({ t = "bpl", src = lib.src, who = lib.who, l = l })
  end
end

-- {q, src, ix, to?}: one of those records as an exchange string (`bp` with src and ix); with
-- to = -1 it also goes straight into the library stack in the cursor, without the round trip.
function M.record(cmd)
  local c = puppet.get()
  local r = record_of(tostring(cmd.src or ""), math.floor(tonumber(cmd.ix) or 0))
  local q = math.floor(tonumber(cmd.q) or 0)
  local ok, data = false, nil
  if r then
    ok, data = pcall(function() return r.export_record() end)
  end
  if not ok or type(data) ~= "string" then
    return send_string(q, "", "", 0, { err = "That record can't be read" })
  end
  if c and tonumber(cmd.to) == -1 then
    local slot = import_into(c, -1, data)
    if slot then
      local stack = cursor_stack()
      transport.send_reliable({ t = "bp_ok", q = q, i = -1, item = stack.valid_for_read and stack.name or "" })
    end
    return
  end
  send_string(q, data, "", 0, { src = cmd.src, ix = cmd.ix })
end

-- The qualities in Factorio's order and whether the force has them (cycling the held item's
-- quality), at the handshake and after research: `quals` {l: [[name, level, unlocked, colour "rrggbb"]]}.
function M.send_initial()
  local c = puppet.get()
  local force = c and c.force or game.forces.player
  local list = {}
  for name, q in pairs(prototypes.quality) do
    if name ~= "quality-unknown" and not q.hidden then
      local ok, unlocked = pcall(function() return force.is_quality_unlocked(name) end)
      local okc, col = pcall(function() return q.color end)
      local function hex(v)
        v = v or 1
        return string.format("%02x", math.floor((v > 1 and v / 255 or v) * 255 + 0.5))
      end
      col = okc and col or {}
      list[#list + 1] = { name, q.level, (ok and unlocked) and 1 or 0, hex(col.r) .. hex(col.g) .. hex(col.b) }
    end
  end
  table.sort(list, function(a, b) return a[2] < b[2] end)
  transport.send_reliable({ t = "quals", l = list })
end


return M
