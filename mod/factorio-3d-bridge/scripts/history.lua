-- Undo and redo for what Factorio keeps in a player's undo queue: blueprints (and pastes) placed,
-- deconstruction and upgrade marks (and their cancelling), entity settings pasted, rotations.
-- LuaPlayer::undo_redo_stack belongs to a player and the bridge's character has none, so the mod
-- keeps its own entries here and tells the client each one's id (`hist`); the client keeps one
-- undo order for these and its own building and mining, and sends `undo` / `redo` with the id.
--
-- Entries hold the entities they touched (LuaEntity references survive in storage), so undo
-- touches exactly those, as Factorio's does: a mark this action added is removed again, a mark
-- that was there before stays.

local transport = require("scripts.transport")
local tracker = require("scripts.tracker")
local puppet = require("scripts.puppet")

local M = {}

local KEEP = 100 -- entries kept; older ones can no longer be undone

local function state()
  local s = storage.f3d
  s.hist = s.hist or { next = 1, entries = {} }
  return s.hist
end

-- A stack in a script inventory for rebuilding blueprints and taking settings snapshots.
local function scratch()
  local s = storage.f3d
  if not (s.hist_scratch and s.hist_scratch.valid) then
    s.hist_scratch = game.create_inventory(1)
  end
  return s.hist_scratch[1]
end
M.scratch = scratch

-- Stores an entry and tells the client its id. `what` names it for the client's messages.
function M.record(entry)
  local h = state()
  local id = h.next
  h.next = id + 1
  h.entries[id] = entry
  h.entries[id - KEEP] = nil
  transport.send_reliable({ t = "hist", h = id, what = entry.what })
  return id
end

local function valid(list)
  local out = {}
  for _, e in pairs(list or {}) do
    if e.valid then
      out[#out + 1] = e
    end
  end
  return out
end

---------------------------------------------------------------------------------------------
-- Recording

-- After build_blueprint: the ghosts it made (with what they stand for, so robots having built
-- one doesn't lose it) and the trees, rocks and buildings it marked for deconstruction.
function M.blueprint(c, ghosts, marked, data, spec)
  if #ghosts == 0 and #marked == 0 then
    return
  end
  local placed = {}
  for _, g in pairs(ghosts) do
    if g.valid then
      local name = g.type == "entity-ghost" and g.ghost_name or g.name
      placed[#placed + 1] = { e = g, name = name, position = g.position, surface = g.surface.index }
    end
  end
  M.record({ what = "blueprint", force = c.force.name, placed = placed, marked = marked, data = data, spec = spec })
end

-- Entities in an area that aren't marked for deconstruction (or upgrade) yet, to compare after.
function M.unmarked(surface, area, upgrade)
  local out = {}
  for _, e in pairs(surface.find_entities_filtered({ area = area })) do
    local marked = upgrade and e.to_be_upgraded() or (not upgrade and e.to_be_deconstructed())
    if not marked then
      out[#out + 1] = e
    end
  end
  return out
end

function M.marked(surface, area, upgrade)
  local out = {}
  for _, e in pairs(surface.find_entities_filtered({ area = area })) do
    if (upgrade and e.to_be_upgraded()) or (not upgrade and e.to_be_deconstructed()) then
      out[#out + 1] = e
    end
  end
  return out
end

-- After a deconstruction or upgrade planner: which of `before` changed their mark. `cancel`: the
-- action took marks away.
function M.marks(c, before, upgrade, cancel)
  local changed = {}
  for _, e in pairs(before) do
    if e.valid then
      local now = upgrade and e.to_be_upgraded() or (not upgrade and e.to_be_deconstructed())
      if now ~= cancel then
        local rec = { e = e }
        if upgrade and not cancel then
          local ok, proto, quality = pcall(function() return e.get_upgrade_target() end)
          if ok and proto then
            rec.target = { name = proto.name, quality = quality and quality.name or nil }
          end
        end
        changed[#changed + 1] = rec
      end
    end
  end
  if #changed > 0 then
    M.record({ what = (cancel and "cancel " or "") .. (upgrade and "upgrade" or "deconstruction"), force = c.force.name,
      upgrade = upgrade, cancel = cancel, list = changed })
  end
end

-- A one-entity blueprint of the entity's settings, as an exchange string ("" if it can't).
function M.snapshot(e)
  local stack = scratch()
  stack.set_stack({ name = "blueprint", count = 1 })
  local p = e.position
  local ok = pcall(function()
    stack.create_blueprint({ surface = e.surface, force = e.force,
      area = { { p.x - 0.05, p.y - 0.05 }, { p.x + 0.05, p.y + 0.05 } },
      include_modules = true, include_station_names = true, include_trains = false, include_fuel = false })
  end)
  if not (ok and stack.is_blueprint_setup()) then
    stack.clear()
    return ""
  end
  local data = stack.export_stack()
  stack.clear()
  return data
end

function M.settings(c, e, before, after)
  if before ~= "" and after ~= "" then
    M.record({ what = "settings", force = c.force.name, e = e, name = e.name, position = e.position,
      surface = e.surface.index, before = before, after = after })
  end
end

function M.rotate(e, reverse)
  M.record({ what = "rotation", force = e.force.name, e = e, reverse = reverse })
end

-- How far a blueprint reaches from where it is placed, whichever way it is turned (tiles).
local function reach_of(bp)
  local r = 1
  local ok, entities = pcall(function() return bp.get_blueprint_entities() end)
  for _, e in pairs(ok and entities or {}) do
    r = math.max(r, math.abs(e.position.x), math.abs(e.position.y))
  end
  local ok_t, tiles = pcall(function() return bp.get_blueprint_tiles() end)
  for _, t in pairs(ok_t and tiles or {}) do
    r = math.max(r, math.abs(t.position.x), math.abs(t.position.y))
  end
  return r + 6
end

-- Builds a blueprint stack as a player would, remembering it for undo. `mode`: a defines.build_mode.
function M.place(c, bp, position, direction, mode, what)
  local r = reach_of(bp)
  local area = { { position[1] - r, position[2] - r }, { position[1] + r, position[2] + r } }
  local before = M.unmarked(puppet.surface(c), area, false)
  local ghosts = bp.build_blueprint({
    surface = puppet.surface(c), force = c.force, position = position, direction = direction,
    build_mode = mode, raise_built = true,
  })
  local marked = {}
  for _, e in pairs(before) do
    if e.valid and e.to_be_deconstructed() then
      marked[#marked + 1] = e
    end
  end
  local ok, data = pcall(function() return bp.export_stack() end)
  M.blueprint(c, ghosts, marked, ok and data or nil, { surface = puppet.surface(c).index, position = position,
    direction = direction, mode = mode, area = area, what = what })
  return ghosts
end

---------------------------------------------------------------------------------------------
-- Undoing

-- Puts a settings snapshot back onto the entity: the one-entity blueprint built over it pastes
-- its settings, as building a blueprint over a matching entity does in the game.
local function apply_snapshot(entry, data)
  local e = entry.e
  if not (e and e.valid) then
    return false
  end
  local stack = scratch()
  if stack.import_stack(data) == 1 then
    return false
  end
  pcall(function()
    stack.build_blueprint({ surface = e.surface, force = e.force, position = e.position,
      build_mode = defines.build_mode.forced, raise_built = true })
  end)
  stack.clear()
  tracker.changed(e)
  return true
end

-- What an entry's ghosts became: still a ghost, or a building the robots finished.
local function placed_now(rec)
  if rec.e.valid then
    return rec.e
  end
  local surface = game.get_surface(rec.surface)
  return surface and surface.find_entity(rec.name, rec.position) or nil
end

local function rebuild_blueprint(c, entry)
  local stack = scratch()
  if stack.import_stack(entry.data) == 1 then
    return
  end
  local spec = entry.spec
  local surface = game.get_surface(spec.surface)
  local before = surface and M.unmarked(surface, spec.area, false) or {}
  local ok, ghosts = pcall(function()
    return stack.build_blueprint({ surface = surface, force = c.force, position = spec.position, direction = spec.direction,
      build_mode = spec.mode, raise_built = true })
  end)
  stack.clear()
  entry.placed = {}
  for _, g in pairs(ok and ghosts or {}) do
    if g.valid then
      local name = g.type == "entity-ghost" and g.ghost_name or g.name
      entry.placed[#entry.placed + 1] = { e = g, name = name, position = g.position, surface = g.surface.index }
    end
  end
  entry.marked = {}
  for _, e in pairs(before) do
    if e.valid and e.to_be_deconstructed() then
      entry.marked[#entry.marked + 1] = e
    end
  end
end

local function reverse(entry, back)
  local c = puppet.get()
  local force = entry.force
  if entry.what == "blueprint" then
    if back then
      for _, rec in pairs(entry.placed) do
        local e = placed_now(rec)
        if e and e.valid then
          if e.type == "entity-ghost" or e.type == "tile-ghost" then
            e.destroy({ raise_destroy = true })
          else
            e.order_deconstruction(force)
          end
        end
      end
      for _, e in pairs(valid(entry.marked)) do
        e.cancel_deconstruction(force)
      end
    elseif c and entry.data then
      rebuild_blueprint(c, entry)
    end
  elseif entry.what == "settings" then
    apply_snapshot(entry, back and entry.before or entry.after)
  elseif entry.what == "rotation" then
    if entry.e.valid then
      local r = entry.reverse
      if back then
        r = not r
      end
      entry.e.rotate({ reverse = r })
      tracker.changed(entry.e)
    end
  else -- marks
    local add = (entry.cancel == back) -- undoing a cancel puts marks back
    for _, rec in pairs(entry.list) do
      local e = rec.e
      if e.valid then
        if entry.upgrade then
          if add and rec.target then
            pcall(function() e.order_upgrade({ target = rec.target, force = force }) end)
          elseif not add then
            e.cancel_upgrade(force)
          end
        elseif add then
          e.order_deconstruction(force)
        else
          e.cancel_deconstruction(force)
        end
      end
    end
  end
end

-- {h}: undoes that entry.
function M.undo(cmd)
  local entry = state().entries[math.floor(tonumber(cmd.h) or 0)]
  if not entry then
    return puppet.message("That can no longer be undone")
  end
  reverse(entry, true)
end

-- {h}: does it again.
function M.redo(cmd)
  local entry = state().entries[math.floor(tonumber(cmd.h) or 0)]
  if not entry then
    return puppet.message("That can no longer be redone")
  end
  reverse(entry, false)
end

return M
