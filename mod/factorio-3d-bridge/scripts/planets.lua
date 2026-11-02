-- The other planets (Space Age), what the client needs to draw them:
--   planet   the surface's planet, its properties (gravity, pressure, ...), day length and light,
--            and the heating radius of heat sources (Aquilo), at the handshake and on a surface
--            change
--   seg      Vulcanus' demolishers: each segmented unit's segments in order (2.x keeps them out of
--            the entity list as one LuaSegmentedUnit)
--   lt       Fulgora's lightning strikes near the focus, and whether a lightning rod caught them
--   pg, sp   Gleba: plants' growth, spawners (egg rafts) and how many units they have out
--   legs     the feet of spider units (pentapods) and spidertrons
--   fz       Aquilo: which machines near the focus are frozen
--   rk, cp   rocket launches and cargo pods in flight; pst a platform arriving or leaving
--   terr     Vulcanus' demolisher territories, each as its chunks, so the client draws their red
--            borders; on arrival and once a minute (territories grow as the planet is explored)
-- and the `land` command, which lands the character from a platform the way a player goes down:
-- in a cargo pod.
--
-- Everything sent here is immediate (not in storage) except `planet`; the module-local caches
-- only decide what is sent, never what is stored, so peers can't drift apart.

local registry = require("scripts.registry")
local transport = require("scripts.transport")
local world = require("scripts.world")
local puppet = require("scripts.puppet")
local tracker = require("scripts.tracker")
local platforms = require("scripts.platforms")
local space = require("scripts.space")
local rate = require("scripts.rate")

local M = {}

local SEG_INTERVAL = 2
local LIGHTNING_INTERVAL = 3
local LEGS_INTERVAL = 4
local POD_INTERVAL = 10
-- Most surfaces have none of these (no lightning on Nauvis, no spiders in most bases), and each
-- look is an area search around the focus. A stream that found nothing looks again only every
-- IDLE ticks; once it finds something it runs at its own rate for BUSY_FOR ticks. Lightning
-- idles shortest so the first strike of a storm is still seen while it lasts.
local IDLE = { lt = 12, legs = 30, cp = 30 }
local BUSY_FOR = 1800
local LIFE_INTERVAL = 60
local STRIKE_MEMORY = 120     -- ticks a strike is remembered so it is sent once
local MAX_LIST = 2000
local TERRITORY_INTERVAL = 3600
local TERRITORY_PART = 1500  -- chunks a message carries at most
local territories_due = false  -- only decides when they are sent, so module-local is fine

local function near(p, f, r)
  return math.abs(p.x - f.x) <= r and math.abs(p.y - f.y) <= r
end

local function area(f, r)
  return { { f.x - r, f.y - r }, { f.x + r, f.y + r } }
end

local function detail_radius()
  return math.min(settings.global["f3d-detail-radius"].value, storage.f3d.focus.r)
end

---------------------------------------------------------------------------------------------
-- The planet

-- [[entity prototype id, heating radius], ...]: what keeps machines from freezing on Aquilo.
-- Derived only from prototypes.
local heaters
local function heating_radii()
  if not heaters then
    heaters = {}
    for name, proto in pairs(prototypes.entity) do
      local ok, r = pcall(function() return proto.heating_radius end)
      if ok and type(r) == "number" and r > 0 then
        heaters[#heaters + 1] = { registry.entity_id(name), r }
      end
    end
  end
  return heaters
end

-- Names of entities that freeze without heat (prototype heating_energy > 0).
local freezers
local function freezing_names()
  if not freezers then
    freezers = {}
    for name, proto in pairs(prototypes.entity) do
      local ok, e = pcall(function() return proto.heating_energy end)
      if ok and type(e) == "number" and e > 0 then
        freezers[#freezers + 1] = name
      end
    end
  end
  return freezers
end

local function thousandths(v)
  return math.floor((tonumber(v) or 0) * 1000 + 0.5)
end

-- {name, props, day, always, mb, sol, dusk, evening, morning, dawn, heat}; see PROTOCOL.md.
function M.planet_message(surface)
  local name = platforms.planet_of(surface) or (platforms.of_surface(surface) and "space") or surface.name
  local props = {}
  for prop in pairs(prototypes.surface_property) do
    local ok, v = pcall(function() return surface.get_property(prop) end)
    if ok and type(v) == "number" then
      props[prop] = v
    end
  end
  local msg = { t = "planet", name = name, props = props, heat = heating_radii(), nb = space.blocked(surface) }
  pcall(function()
    msg.day = surface.ticks_per_day
    msg.always = surface.always_day and 1 or 0
    msg.mb = thousandths(surface.min_brightness)
    msg.sol = thousandths(surface.solar_power_multiplier)
    msg.dusk, msg.evening = thousandths(surface.dusk), thousandths(surface.evening)
    msg.morning, msg.dawn = thousandths(surface.morning), thousandths(surface.dawn)
  end)
  return msg
end

function M.send_planet()
  transport.send_reliable(M.planet_message(world.surface()))
end

---------------------------------------------------------------------------------------------
-- Streams near the focus

-- storage.f3d.planets_sent: message type -> true when the last one listed something (so an empty
-- one clears it); per client, like everything in storage.f3d.

local function send_list(t, list)
  local sent_last = storage.f3d.planets_sent or {}
  storage.f3d.planets_sent = sent_last
  if #list > 0 or sent_last[t] then
    transport.send_now({ t = t, l = list })
  end
  sent_last[t] = #list > 0
end

-- Whether stream `t` (running every `interval` ticks while busy) looks this tick. Kept in
-- storage, like everything that decides what this module does, so every peer agrees.
local function due(t, interval)
  local busy = storage.f3d.planets_busy or {}
  storage.f3d.planets_busy = busy
  local now = game.tick
  if (busy[t] or -1) >= now then
    return now % interval == 0
  end
  return now % IDLE[t] == 0
end

local function found(t, n)
  if n > 0 then
    storage.f3d.planets_busy[t] = game.tick + BUSY_FOR
  end
end

-- [[unit, prototype id, [segment prototype id, x, y, orientation, ...]], ...] for segmented units
-- with a segment near the focus, head first.
local function segments(surface, f)
  local out = {}
  local ok, units = pcall(function() return surface.get_segmented_units() end)
  for _, u in pairs(ok and units or {}) do
    local flat, close = {}, false
    for _, seg in ipairs(u.segments) do
      local p = seg.position
      if p then
        close = close or near(p, f, f.r)
        flat[#flat + 1] = registry.entity_id(seg.prototype.name)
        flat[#flat + 1] = world.fixed(p.x)
        flat[#flat + 1] = world.fixed(p.y)
        flat[#flat + 1] = thousandths(seg.orientation or 0) % 1000
      end
    end
    if close then
      out[#out + 1] = { u.unit_number, registry.entity_id(u.prototype.name), flat }
    end
  end
  return out
end

-- A lightning entity stands where its bolt starts, up in the sky: the prototype's source_offset
-- (0, -25 for Fulgora's) from where it strikes, give or take half its source_variance (30 x 6),
-- and it stays put for its few ticks. 2.1 has no event or field for where the bolt lands, so the
-- ground point is estimated as the entity's position less the offset (within 3 tiles in y and
-- 15 in x). A strike that an attractor pulled in lands on the attractor, so an
-- attractor inside that window is taken to have caught it and is sent as the place it struck.
-- Derived only from prototypes.
local bolt_shapes = {}
local function bolt_shape(name)
  local shape = bolt_shapes[name]
  if not shape then
    local ok, off, var = pcall(function()
      local p = prototypes.entity[name]
      return p.source_offset, p.source_variance
    end)
    off = ok and type(off) == "table" and off or {}
    var = ok and type(var) == "table" and var or {}
    shape = { off[1] or off.x or 0, off[2] or off.y or 0, (var[1] or var.x or 0) / 2 + 0.5, (var[2] or var.y or 0) / 2 + 0.5 }
    bolt_shapes[name] = shape
  end
  return shape
end

-- The bolt's reach above the ground, the most a source can sit from the focus area.
local SKY_MARGIN = 45

-- Each strike is sent once, keyed by its (fixed) source position.
-- storage.f3d.strikes_seen: "x,y" -> tick seen, per client (each client is sent each strike once).
-- Returns the new strikes and how many bolts are in the sky (sent before or not).
local function lightning(surface, f)
  local out = {}
  if not registry.has_type("lightning") then
    return out, 0
  end
  local now = game.tick
  local strikes = storage.f3d.strikes_seen or {}
  storage.f3d.strikes_seen = strikes
  for key, t in pairs(strikes) do
    if now - t > STRIKE_MEMORY then
      strikes[key] = nil
    end
  end
  local attractors = registry.has_type("lightning-attractor")
  local bolts = surface.find_entities_filtered({ area = area(f, f.r + SKY_MARGIN), type = "lightning" })
  for _, e in pairs(bolts) do
    local p = e.position
    local key = world.fixed(p.x) .. "," .. world.fixed(p.y)
    local shape = bolt_shape(e.name)
    local x, y = p.x - shape[1], p.y - shape[2]
    if not strikes[key] and near({ x = x, y = y }, f, f.r) then
      strikes[key] = now
      local caught
      if attractors then
        local best = math.huge
        for _, a in pairs(surface.find_entities_filtered({
          area = { { x - shape[3], y - shape[4] }, { x + shape[3], y + shape[4] } }, type = "lightning-attractor",
        })) do
          local ap = a.position
          local d = (ap.x - x) ^ 2 + (ap.y - y) ^ 2
          if d < best then
            best, caught = d, ap
          end
        end
      end
      if caught then
        x, y = caught.x, caught.y
      end
      out[#out + 1] = { world.fixed(x), world.fixed(y), caught and 1 or 0 }
    end
  end
  return out, #bolts
end

-- [unit or 0, x, y, growth (thousandths), ...] for plants near the focus.
local function plants(surface, f, r)
  local flat = {}
  if not registry.has_type("plant") then
    return flat
  end
  local now = game.tick
  for _, e in pairs(surface.find_entities_filtered({ area = area(f, r), type = "plant", limit = MAX_LIST })) do
    local ok, grown, ticks = pcall(function() return e.tick_grown, e.prototype.growth_ticks end)
    if ok and grown and ticks and ticks > 0 then
      local p = e.position
      flat[#flat + 1] = e.unit_number or 0
      flat[#flat + 1] = world.fixed(p.x)
      flat[#flat + 1] = world.fixed(p.y)
      flat[#flat + 1] = math.max(0, math.min(1000, thousandths(1 - (grown - now) / ticks)))
    end
  end
  return flat
end

-- [unit, units out, ...] for spawners (biter nests, Gleba's egg rafts) near the focus.
local function spawners(surface, f)
  local flat = {}
  if not registry.has_type("unit-spawner") then
    return flat
  end
  for _, e in pairs(surface.find_entities_filtered({ area = area(f, f.r), type = "unit-spawner", limit = MAX_LIST })) do
    local ok, units = pcall(function() return e.units end)
    if e.unit_number then
      flat[#flat + 1] = e.unit_number
      flat[#flat + 1] = ok and #units or 0
    end
  end
  return flat
end

-- [[unit, [x, y, ...]], ...]: each leg's foot for spider units (pentapods) and spidertrons.
-- A leg is a spider-leg entity standing where its foot is. get_spider_legs only works on
-- spider-vehicles (spidertrons); a spider unit's legs have no link back to it in the 2.1 API, but
-- the game creates them right after the body, so they carry the next unit numbers (seen in
-- 2.1.23 for every pentapod, whether a spawner or a script made it).
local LEGGED = { "spider-unit", "spider-vehicle" }
local LEG_REACH = 16 -- tiles from the focus area a foot can stand

-- spider-unit prototype name -> how many legs it has. Derived only from prototypes.
local leg_counts = {}
local function leg_count(name)
  local n = leg_counts[name]
  if not n then
    local ok, engine = pcall(function() return prototypes.entity[name].spider_engine end)
    n = ok and type(engine) == "table" and type(engine.legs) == "table" and #engine.legs or 0
    leg_counts[name] = n
  end
  return n
end

local function feet_of(list)
  local feet = {}
  for _, leg in ipairs(list) do
    local p = leg.position
    feet[#feet + 1] = world.fixed(p.x)
    feet[#feet + 1] = world.fixed(p.y)
  end
  return feet
end

local function legs(surface, f)
  local out = {}
  local types = {}
  for _, t in ipairs(LEGGED) do
    if registry.has_type(t) then
      types[#types + 1] = t
    end
  end
  if #types == 0 then
    return out
  end
  local by_number -- unit number -> spider-leg entity, read once if a spider unit is near
  for _, e in pairs(surface.find_entities_filtered({ area = area(f, f.r), type = types, limit = MAX_LIST })) do
    local n = e.unit_number
    if n and e.type == "spider-vehicle" then
      local ok, list = pcall(function() return e.get_spider_legs() end)
      if ok and list then
        out[#out + 1] = { n, feet_of(list) }
      end
    elseif n then
      if not by_number then
        by_number = {}
        if registry.has_type("spider-leg") then
          for _, leg in pairs(surface.find_entities_filtered({ area = area(f, f.r + LEG_REACH), type = "spider-leg" })) do
            if leg.unit_number then
              by_number[leg.unit_number] = leg
            end
          end
        end
      end
      local list = {}
      for i = 1, leg_count(e.name) do
        list[#list + 1] = by_number[n + i]
        if not list[i] then
          break
        end
      end
      if #list > 0 then
        out[#out + 1] = { n, feet_of(list) }
      end
    end
  end
  return out
end

-- Units of machines near the focus that are frozen (Aquilo).
local function frozen(surface, f)
  local out = {}
  local names = freezing_names()
  if #names == 0 then
    return out
  end
  for _, e in pairs(surface.find_entities_filtered({ area = area(f, f.r), name = names, limit = MAX_LIST })) do
    local ok, cold = pcall(function() return e.frozen end)
    if ok and cold and e.unit_number then
      out[#out + 1] = e.unit_number
    end
  end
  return out
end

local destination_names
local function destination_name(t)
  if not destination_names then
    destination_names = {}
    for name, value in pairs(defines.cargo_destination) do
      destination_names[value] = name
    end
  end
  return destination_names[t] or ""
end

-- [[unit, state, destination type, destination surface or ""], ...] for cargo pods near the focus.
local function cargo_pods(surface, f)
  local out = {}
  if not registry.has_type("cargo-pod") then
    return out
  end
  for _, e in pairs(surface.find_entities_filtered({ area = area(f, f.r), type = "cargo-pod", limit = MAX_LIST })) do
    local ok, state, dest = pcall(function() return e.cargo_pod_state, e.cargo_pod_destination end)
    if ok and e.unit_number then
      local to = dest and dest.surface
      out[#out + 1] = { e.unit_number, state or "", dest and destination_name(dest.type) or "", to and to.valid and to.name or "" }
    end
  end
  return out
end

-- For an agricultural tower's screen: {plants, ready} (plants it owns, how many are grown).
function M.tower_info(e)
  local ok, owned = pcall(function() return e.owned_plants end)
  if not ok then
    return nil
  end
  local ready = 0
  for _, plant in pairs(owned) do
    local ok2, grown = pcall(function() return plant.tick_grown end)
    if ok2 and grown and grown <= game.tick then
      ready = ready + 1
    end
  end
  return { plants = #owned, ready = ready }
end

---------------------------------------------------------------------------------------------
-- Events

local function client()
  return storage.f3d and storage.f3d.client
end

function M.on_rocket_launch_ordered(event)
  local silo = event.rocket_silo
  if client() and silo and silo.valid then
    local p = silo.position
    transport.send_now({ t = "rk", u = silo.unit_number or 0, x = world.fixed(p.x), y = world.fixed(p.y), s = silo.surface.name })
  end
end

function M.on_platform_state(event)
  local p = event.platform
  if client() and p and p.valid then
    local loc = p.space_location
    transport.send_now({ t = "pst", i = p.index, st = platforms.state_name(p.state), old = platforms.state_name(event.old_state), loc = loc and loc.name or "" })
  end
end

function M.register()
  script.on_event(defines.events.on_rocket_launch_ordered, M.on_rocket_launch_ordered)
  script.on_event(defines.events.on_space_platform_changed_state, M.on_platform_state)
  -- An agricultural tower's plants appear and go without the usual build and mine events.
  script.on_event(defines.events.on_tower_planted_seed, function(event) tracker.added(event.plant) end)
  script.on_event(defines.events.on_tower_pre_mined_plant, function(event) tracker.removed(event.plant) end)
end

---------------------------------------------------------------------------------------------
-- Landing on a planet

-- Where a cargo pod from a platform comes down on `surface`: the force's landing pad there if it
-- has one (a station, as Factorio sends a player to it), else a free spot by the force's spawn.
local function landing(c, surface)
  local pads = surface.find_entities_filtered({ type = "cargo-landing-pad", force = c.force, limit = 1 })
  if pads[1] then
    return { type = defines.cargo_destination.station, station = pads[1] }, pads[1].position
  end
  local spawn = c.force.get_spawn_position(surface)
  local spot = surface.find_non_colliding_position("character", spawn, 32, 0.5) or spawn
  return { type = defines.cargo_destination.surface, surface = surface, position = spot }, spot
end

-- {}: from a platform stopped at a planet, down to its surface in a cargo pod, as a player does
-- from the hub. Seen in 2.1.23: a character inside a hub can't be a pod's passenger (set_passenger
-- does nothing) and can't be teleported on its own surface; a teleport to another surface takes it
-- out. So it hops to the planet and straight back beside the hub within the tick (nothing is drawn
-- in between), gets into a pod the hub makes, and the pod is sent off: it waits about 1.5 s, climbs
-- for 7, changes surface and comes down in 10. If the pod can't take it, the character is moved
-- down directly (platforms.descend), and the message says which happened.
function M.land()
  local c = puppet.get()
  if not c then
    return
  end
  if puppet.pod(c) then
    return puppet.message("You're already on your way")
  end
  local p = platforms.of_surface(c.surface)
  local loc = p and p.space_location
  if not (p and loc and game.planets[loc.name]) then
    return puppet.message("Land from a platform that is stopped at a planet")
  end
  local planet = game.planets[loc.name]
  local surface = planet.surface or planet.create_surface()
  local dest, spot = landing(c, surface)
  local ok, err = pcall(function()
    local hub = p.hub
    if puppet.hub(c) then
      assert(c.teleport(spot, surface), "couldn't leave the hub")
      local beside = p.surface.find_non_colliding_position("character", hub.position, 16, 0.5) or hub.position
      assert(c.teleport(beside, p.surface), "couldn't come back beside the hub")
    end
    local pod = hub.create_cargo_pod()
    assert(pod, "the hub made no cargo pod")
    pod.set_passenger(c)
    if pod.get_passenger() ~= c then
      pod.destroy()
      error("the pod didn't take the character")
    end
    pod.cargo_pod_destination = dest
  end)
  if ok then
    storage.f3d.trip = { up = false, si = surface.index, land = { x = spot.x, y = spot.y } }
    puppet.message("Going down to " .. loc.name .. " in a cargo pod")
    return
  end
  local moved, why = platforms.descend(c, loc.name)
  puppet.message(moved and ("Landed on " .. loc.name .. " directly (a cargo pod ride failed: " .. tostring(err) .. ")") or why)
end

---------------------------------------------------------------------------------------------

function M.tick()
  local s = storage.f3d
  local f = s.focus
  local t = game.tick
  local surface = world.surface()
  if rate.due("seg", SEG_INTERVAL) then
    send_list("seg", segments(surface, f))
  end
  if due("lt", LIGHTNING_INTERVAL) then
    local new, any = lightning(surface, f)
    found("lt", any)
    if #new > 0 then
      transport.send_now({ t = "lt", l = new })
    end
  end
  if due("legs", LEGS_INTERVAL) then
    local list = legs(surface, f)
    found("legs", #list)
    send_list("legs", list)
  end
  if due("cp", POD_INTERVAL) then
    local list = cargo_pods(surface, f)
    found("cp", #list)
    send_list("cp", list)
  end
  if territories_due or t % TERRITORY_INTERVAL == 0 then
    territories_due = false
    M.send_territories()
  end
  if rate.due("life", LIFE_INTERVAL) then
    local r = detail_radius()
    if r > 0 then
      send_list("pg", plants(surface, f, r))
    end
    send_list("sp", spawners(surface, f))
    send_list("fz", frozen(surface, f))
  end
end

-- `terr` {part, parts, si, l: [[x1, y1, x2, y2, ...], ...]}: every demolisher territory on the
-- world's surface (`si`) as its chunks (LuaSurface.get_territories, 2.1). Immediate and sent again
-- each minute, so a lost part is made good; an empty `l` clears them (a surface without any).
function M.send_territories()
  local surface = world.surface()
  local ok, territories = pcall(function() return surface.get_territories() end)
  local parts, current, count = {}, {}, 0
  for _, territory in pairs(ok and territories or {}) do
    local okc, chunks = pcall(function() return territory.get_chunks() end)
    if okc and #chunks > 0 then
      local flat = {}
      for _, c in pairs(chunks) do
        flat[#flat + 1] = c.x
        flat[#flat + 1] = c.y
      end
      if count > 0 and count + #chunks > TERRITORY_PART then
        parts[#parts + 1] = current
        current, count = {}, 0
      end
      current[#current + 1] = flat
      count = count + #chunks
    end
  end
  parts[#parts + 1] = current
  for i, l in ipairs(parts) do
    transport.send_now({ t = "terr", part = i, parts = #parts, si = surface.index, l = l })
  end
end

-- On a surface change: the new surface's territories with the next tick.
function M.territories_soon()
  territories_due = true
end

-- After a handshake: the planet again, and every stream sends once even if empty.
function M.send_initial()
  storage.f3d.planets_sent = { seg = true, legs = true, cp = true, pg = true, sp = true, fz = true }
  M.send_planet()
  territories_due = true  -- next tick: after the handshake's welcome
end

return M
