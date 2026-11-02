-- Turns game events into add / remove / update deltas for chunks the client is watching.

local registry = require("scripts.registry")
local transport = require("scripts.transport")
local world = require("scripts.world")
local rate = require("scripts.rate")

local M = {}

local WIRE_INTERVAL = 30

-- Belt shapes depend on their neighbours, so a change to one belt can bend the ones next to it.
local BELT_TYPES = { ["transport-belt"] = true, ["underground-belt"] = true, ["splitter"] = true, ["lane-splitter"] = true, ["loader"] = true, ["loader-1x1"] = true }

local function watched(entity)
  return entity and entity.valid and registry.is_static(entity.type) and world.is_subscribed(entity.surface, entity.position)
end

local function refresh_neighbour_belts(entity)
  local p = entity.position
  local belts = entity.surface.find_entities_filtered({
    area = { { p.x - 1.5, p.y - 1.5 }, { p.x + 1.5, p.y + 1.5 } },
    type = "transport-belt",
  })
  for _, belt in pairs(belts) do
    if belt ~= entity and watched(belt) then
      transport.send_reliable({ t = "upd", e = world.record(belt) })
    end
  end
end

-- Pipes next to an entity with fluid boxes connect to it (or stop connecting when it goes), so
-- their records change. Removals are looked at next tick, once the entity is gone.
local function refresh_pipes_near(surface, box)
  local types = registry.pipe_types()
  if #types == 0 then
    return
  end
  local pipes = surface.find_entities_filtered({
    area = { { box.left_top.x - 1, box.left_top.y - 1 }, { box.right_bottom.x + 1, box.right_bottom.y + 1 } },
    type = types,
  })
  for _, pipe in pairs(pipes) do
    if watched(pipe) then
      transport.send_reliable({ t = "upd", e = world.record(pipe) })
    end
  end
end

local function fluid_neighbours_changed(entity, later)
  if not (entity and entity.valid and registry.is_fluid(entity.type)) then
    return
  end
  local b = entity.bounding_box
  if later then
    local s = storage.f3d
    s.pipe_refresh[#s.pipe_refresh + 1] = {
      surface = entity.surface.index,
      box = { left_top = { x = b.left_top.x, y = b.left_top.y }, right_bottom = { x = b.right_bottom.x, y = b.right_bottom.y } },
    }
  else
    refresh_pipes_near(entity.surface, b)
  end
end

-- Functions called with each entity built, changed or removed (map.lua forgets its charts there).
M.listeners = {}

local function tell(entity)
  world.touched(entity)
  for _, f in ipairs(M.listeners) do
    f(entity)
  end
end

function M.added(entity)
  tell(entity)
  fluid_neighbours_changed(entity, false)
  -- Building removes the decoratives under the entity.
  if entity and entity.valid then
    world.decoratives_changed(entity.surface, entity.position)
  end
  if watched(entity) then
    transport.send_reliable({ t = "add", e = world.record(entity) })
    if BELT_TYPES[entity.type] then
      refresh_neighbour_belts(entity)
    end
  end
end

function M.changed(entity)
  tell(entity)
  fluid_neighbours_changed(entity, false)
  if watched(entity) then
    transport.send_reliable({ t = "upd", e = world.record(entity) })
    if BELT_TYPES[entity.type] then
      refresh_neighbour_belts(entity)
    end
  end
end

-- The "del" message for an entity, built while it is still valid. Nil if the client can't see it.
function M.removal_message(entity)
  if not watched(entity) then
    return nil
  end
  local p = entity.position
  return {
    t = "del",
    u = entity.unit_number or 0,
    p = registry.entity_id(entity.name),
    x = world.fixed(p.x),
    y = world.fixed(p.y),
  }
end

-- Called while the entity is still valid (before it is removed).
function M.removed(entity)
  tell(entity)
  fluid_neighbours_changed(entity, true)
  local msg = M.removal_message(entity)
  if msg then
    transport.send_reliable(msg)
    -- Neighbouring belts only change shape once this one is gone, so look at them next tick.
    if BELT_TYPES[entity.type] then
      local s = storage.f3d
      local p = entity.position
      s.belt_refresh[#s.belt_refresh + 1] = { surface = entity.surface.index, x = p.x, y = p.y }
    end
  end
end

-- Deconstructing an area (planner, shortcut, cut) deletes the ghosts in it at once and raises no
-- event for them, so `act` runs between a look at the ghosts before and after: those gone get `del`.
function M.deconstructing(surface, area, force, act)
  local before = {}
  for _, g in pairs(surface.find_entities_filtered({ area = area, type = { "entity-ghost", "tile-ghost" }, force = force })) do
    local msg = M.removal_message(g)
    if msg then
      before[#before + 1] = { g, msg }
    end
  end
  act()
  for _, b in ipairs(before) do
    if not b[1].valid then
      transport.send_reliable(b[2])
    end
  end
end

-- Wires added or removed between existing poles and combinators near the focus raise no event in
-- 2.x, so their wires are compared with the last look every half second; a change sends `upd`.
-- The last look is kept in storage (it decides what goes into the reliable stream).
local function watch_wires(s)
  local types = registry.wired_types()
  if #types == 0 then
    return
  end
  local f = s.focus
  local seen = {}
  local found = world.surface().find_entities_filtered({
    area = { { f.x - f.r, f.y - f.r }, { f.x + f.r, f.y + f.r } },
    type = types,
  })
  for _, e in pairs(found) do
    local unit = e.unit_number
    if unit then
      local sig = world.wire_signature(e)
      local before = s.wire_sigs[unit]
      seen[unit] = sig
      if before and before ~= sig and watched(e) then
        transport.send_reliable({ t = "upd", e = world.record(e) })
      end
    end
  end
  s.wire_sigs = seen
end

function M.tick()
  local s = storage.f3d
  if rate.due("wires", WIRE_INTERVAL) then
    watch_wires(s)
  end
  if #s.pipe_refresh > 0 then
    local pending = s.pipe_refresh
    s.pipe_refresh = {}
    for _, at in pairs(pending) do
      local surface = game.get_surface(at.surface)
      if surface then
        refresh_pipes_near(surface, at.box)
      end
    end
  end
  if #s.belt_refresh == 0 then
    return
  end
  local pending = s.belt_refresh
  s.belt_refresh = {}
  for _, at in pairs(pending) do
    local surface = game.get_surface(at.surface)
    if surface then
      local belts = surface.find_entities_filtered({
        area = { { at.x - 1.5, at.y - 1.5 }, { at.x + 1.5, at.y + 1.5 } },
        type = "transport-belt",
      })
      for _, belt in pairs(belts) do
        if watched(belt) then
          transport.send_reliable({ t = "upd", e = world.record(belt) })
        end
      end
    end
  end
end

function M.register()
  local function on_added(event)
    M.added(event.entity or event.destination)
  end
  script.on_event({
    defines.events.on_built_entity,
    defines.events.on_robot_built_entity,
    defines.events.on_space_platform_built_entity,
    defines.events.script_raised_built,
    defines.events.script_raised_revive,
    defines.events.on_entity_cloned,
  }, on_added)

  script.on_event({
    defines.events.on_player_mined_entity,
    defines.events.on_robot_mined_entity,
    defines.events.on_space_platform_mined_entity,
    defines.events.script_raised_destroy,
    defines.events.on_resource_depleted,
  }, function(event)
    M.removed(event.entity)
  end)
  -- on_entity_died is registered by combat.lua, which also tells the client about the death.
  -- What a building leaves when destroyed: its remnants, sent like a new entity.
  script.on_event(defines.events.on_post_entity_died, function(event)
    for _, corpse in pairs(event.corpses or {}) do
      if corpse.valid and registry.remnant_of(corpse.name)
          and world.is_subscribed(corpse.surface, corpse.position) then
        transport.send_reliable({ t = "add", e = world.record(corpse) })
      end
    end
  end)

  -- Marks for deconstruction and upgrade show in the record (extra.d, extra.up).
  script.on_event({
    defines.events.on_player_rotated_entity,
    defines.events.on_player_flipped_entity,
    defines.events.on_marked_for_deconstruction,
    defines.events.on_cancelled_deconstruction,
    defines.events.on_marked_for_upgrade,
    defines.events.on_cancelled_upgrade,
  }, function(event)
    M.changed(event.entity)
  end)

  local function on_tiles(event)
    local surface = game.get_surface(event.surface_index)
    if not surface then
      return
    end
    local positions = {}
    for _, t in pairs(event.tiles) do
      positions[#positions + 1] = t.position
    end
    world.tiles_changed(surface, positions)
  end
  script.on_event({
    defines.events.on_player_built_tile,
    defines.events.on_robot_built_tile,
    defines.events.on_space_platform_built_tile,
    defines.events.on_player_mined_tile,
    defines.events.on_robot_mined_tile,
    defines.events.on_space_platform_mined_tile,
    defines.events.script_raised_set_tiles,
  }, on_tiles)

  script.on_event(defines.events.on_chunk_generated, function(event)
    world.on_chunk_generated(event.surface, event.position)
  end)
end

return M
