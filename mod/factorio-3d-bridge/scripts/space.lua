-- Space Age's gameplay screens and what they need, for machine screens (screens.lua) and the
-- client's space map:
--   hub        a space platform hub: the platform's state, speed, weight, thrusters and their
--              fuel, its schedule (records, wait conditions, interrupts), its requests from
--              planets (logistic sections with "import from", minimum delivery counts), and
--              whether it provides to other platforms
--   silo       a rocket silo: its status, automatic launches, and where its rocket can go; `ride`
--              takes the character up in the rocket
--   pad        a cargo landing pad: its requests and its circuit settings; bays show their owner
--   collector  an asteroid collector's chunk filters
--   eff, rq    a machine's module effects (quality among them) and its recipe's quality
--   smap       the solar system: space locations with their star map positions, the connections
--              between them with their length and asteroid danger (on request)
--   ach        asteroid chunks floating near the focus on a platform
--   nb         (in `planet`) the entities that can't be built on this surface, and why
-- and the commands that change them. Commands run from on_udp_packet_received, which every peer
-- replays alike; nothing here keeps module state except prototype-derived caches.

local registry = require("scripts.registry")
local transport = require("scripts.transport")
local world = require("scripts.world")
local puppet = require("scripts.puppet")
local platforms = require("scripts.platforms")
local modules = require("scripts.modules")

local M = {}

local CHUNK_INTERVAL = 10
local MAX_CHUNKS = 300
local MAX_SECTIONS = 20
local MAX_FILTERS = 100

local function define_index(name)
  local ok, index = pcall(function() return defines.inventory[name] end)
  return ok and index or nil
end

local function try(fn, ...)
  local ok, v = pcall(fn, ...)
  if ok then
    return v
  end
  return nil
end

local function bit(v)
  return v and 1 or 0
end

-- A prototype's name: 2.1 gives LuaObjects (userdata) where names were asked for (a filter's
-- import_from, get_recipe's quality, a collector's filter).
local function name_of(v)
  if type(v) == "table" or type(v) == "userdata" then
    return v.name
  end
  return v
end

-- The screen kind for Space Age's entities, or nil.
function M.kind(e)
  local t = e.type
  if t == "space-platform-hub" then
    return "hub"
  elseif t == "cargo-landing-pad" then
    return "pad"
  elseif t == "cargo-bay" then
    return "bay"
  elseif t == "asteroid-collector" then
    return "collector"
  end
  return nil
end

-- Kinds whose get_output_inventory isn't shown as "output".
function M.no_output(kind)
  return kind == "hub" or kind == "pad" or kind == "bay"
end

-- Adds this module's inventories through add(role, inventory): the hub's and pad's trash, the
-- silo's rocket cargo and trash.
function M.add_inventories(e, kind, add)
  local names
  if kind == "hub" then
    names = { { "trash", "hub_trash" } }
  elseif kind == "pad" then
    names = { { "trash", "cargo_landing_pad_trash" } }
  elseif kind == "silo" then
    names = { { "rocket", "rocket_silo_rocket" }, { "trash", "rocket_silo_trash" } }
  end
  for _, pair in ipairs(names or {}) do
    local index = define_index(pair[2])
    local inv = index and try(function() return e.get_inventory(index) end)
    if inv then
      add(pair[1], inv)
    end
  end
end

---------------------------------------------------------------------------------------------
-- Qualities

-- The names of the qualities the force has unlocked, normal first (by level).
local function qualities(force)
  local out = {}
  pcall(function()
    local list = {}
    for name, q in pairs(prototypes.quality) do
      if not q.hidden and force.is_quality_unlocked(name) then
        list[#list + 1] = { name, q.level }
      end
    end
    table.sort(list, function(a, b) return a[2] < b[2] end)
    for _, q in ipairs(list) do
      out[#out + 1] = q[1]
    end
  end)
  return out
end

M.qualities = qualities

local function quality_ok(name)
  return type(name) == "string" and name ~= "" and try(function() return prototypes.quality[name] end) ~= nil
end

---------------------------------------------------------------------------------------------
-- Logistic sections (the hub's requests from planets, a landing pad's requests from orbit)

-- One filter: [item, quality ("" any), min, max (-1 none), import from ("" anywhere), minimum
-- delivery count (-1 the default)].
local function filter_out(f)
  local v = f.value
  if type(v) ~= "table" or not v.name then
    return nil
  end
  return {
    name_of(v.name), name_of(v.quality) or "", math.floor(f.min or 0), f.max and math.floor(f.max) or -1,
    name_of(f.import_from) or "", f.minimum_delivery_count and math.floor(f.minimum_delivery_count) or -1,
  }
end

-- [{i, g (group), on, m (multiplier), man (can be edited), f = [filter, ...]}, ...]
function M.sections_of(e)
  local secs = try(function() return e.get_logistic_sections() end)
  if not secs then
    return nil
  end
  return M.sections_list(secs)
end

-- The same from anything with `sections` (LuaLogisticSections, or a character's requester
-- LuaLogisticPoint).
function M.sections_list(secs)
  local out = {}
  for i, sec in ipairs(try(function() return secs.sections end) or {}) do
    if #out >= MAX_SECTIONS then
      break
    end
    local rec = { i = i, g = sec.group or "", on = bit(sec.active), m = sec.multiplier or 1, man = 1, f = {} }
    local manual = try(function() return sec.is_manual end)
    if manual == false then
      rec.man = 0
    end
    for _, f in pairs(sec.filters or {}) do
      local entry = filter_out(f)
      if entry and #rec.f < MAX_FILTERS then
        rec.f[#rec.f + 1] = entry
      end
    end
    out[#out + 1] = rec
  end
  return out
end

local function filter_in(entry)
  if type(entry) ~= "table" or type(entry[1]) ~= "string" or not prototypes.item[entry[1]] then
    return nil
  end
  local quality = quality_ok(entry[2]) and entry[2] or "normal"
  local f = { value = { type = "item", name = entry[1], quality = quality, comparator = "=" },
    min = math.max(0, math.floor(tonumber(entry[3]) or 0)) }
  local max = tonumber(entry[4])
  if max and max >= 0 then
    f.max = math.max(f.min, math.floor(max))
  end
  local from = entry[5]
  if type(from) == "string" and from ~= "" and prototypes.space_location[from] then
    f.import_from = from
  end
  local mdc = tonumber(entry[6])
  if mdc and mdc >= 0 then
    f.minimum_delivery_count = math.floor(mdc)
  end
  return f
end

-- {u, i (section index, 0 adds one), del? 1, f? [filters], g? group, on? 0/1, m? multiplier}
function M.set_section(e, cmd)
  M.write_section(e.get_logistic_sections(), cmd)
end

-- set_section on anything with add_section / get_section / remove_section (an entity's
-- LuaLogisticSections or the character's requester LuaLogisticPoint).
function M.write_section(secs, cmd)
  local i = math.floor(tonumber(cmd.i) or 0)
  if cmd.del == 1 then
    if not secs.remove_section(i) then
      puppet.message("That section can't be removed")
    end
    return
  end
  local sec
  if i == 0 then
    if type(cmd.g) == "string" and cmd.g ~= "" then
      sec = secs.add_section(cmd.g)
    else
      sec = secs.add_section()
    end
    if not sec then
      return puppet.message("No more sections fit")
    end
  else
    sec = secs.get_section(i)
    if not sec then
      return puppet.message("No such section")
    end
  end
  if type(cmd.f) == "table" then
    local list = {}
    for _, entry in ipairs(cmd.f) do
      local f = filter_in(entry)
      if f and #list < MAX_FILTERS then
        list[#list + 1] = f
      end
    end
    sec.filters = list
  end
  -- A section's group: one of the force's groups or a new name ("" takes it out of its group).
  if i ~= 0 and type(cmd.g) == "string" and #cmd.g <= 200 then
    sec.group = cmd.g
  end
  if cmd.on == 0 or cmd.on == 1 then
    sec.active = cmd.on == 1
  end
  local m = tonumber(cmd.m)
  if m and m >= 0 then
    sec.multiplier = m
  end
end

---------------------------------------------------------------------------------------------
-- The space platform hub

-- Platform schedules are LuaSchedules like a train's, with space locations for stations.
local function schedule_of(p)
  local sched = try(function() return p.get_schedule() end)
  if not sched then
    return nil
  end
  local records = {}
  for _, rec in pairs(try(function() return sched.get_records() end) or {}) do
    records[#records + 1] = { station = rec.station or "", wait_conditions = rec.wait_conditions or {},
      temporary = rec.temporary or nil, allows_unloading = rec.allows_unloading }
  end
  local interrupts = {}
  for _, int in pairs(try(function() return sched.get_interrupts() end) or {}) do
    local targets = {}
    for _, rec in pairs(int.targets or {}) do
      targets[#targets + 1] = { station = rec.station or "", wait_conditions = rec.wait_conditions or {} }
    end
    interrupts[#interrupts + 1] = { name = int.name or "", conditions = int.conditions or {}, targets = targets,
      inside_interrupt = int.inside_interrupt and true or false }
  end
  return { current = try(function() return sched.current end) or 0, records = records,
    group = try(function() return sched.group end) or "", interrupts = interrupts }
end

-- Thrusters on the platform: [count, working], and their fuel and oxidizer [[fluid, amount, capacity]].
local function thrusters(surface)
  local count, working, fluids, order = 0, 0, {}, {}
  if not registry.has_type("thruster") then
    return { 0, 0 }, {}
  end
  for _, t in pairs(surface.find_entities_filtered({ type = "thruster" })) do
    count = count + 1
    if t.status == defines.entity_status.working then
      working = working + 1
    end
    for i = 1, (try(function() return t.fluids_count end) or 0) do
      local fl = try(function() return t.get_fluid(i) end)
      local cap = try(function() return t.get_fluid_capacity(i) end) or 0
      if fl then
        local acc = fluids[fl.name]
        if not acc then
          acc = { fl.name, 0, 0 }
          fluids[fl.name] = acc
          order[#order + 1] = fl.name
        end
        acc[2] = acc[2] + fl.amount
        acc[3] = acc[3] + cap
      end
    end
  end
  local out = {}
  table.sort(order)
  for _, name in ipairs(order) do
    local acc = fluids[name]
    out[#out + 1] = { name, math.floor(acc[2] + 0.5), math.floor(acc[3] + 0.5) }
  end
  return { count, working }, out
end

local function destinations(force)
  local out = {}
  pcall(function()
    for name in pairs(prototypes.space_location) do
      if force.is_space_location_unlocked(name) then
        out[#out + 1] = name
      end
    end
  end)
  table.sort(out)
  return out
end

-- gui.hub: {i, n, st, pa, sp, w, loc?, from?, to?, d?, len?, th: [count, working], fuel, sched,
-- sec, prov, dest}
local function hub_info(e)
  local p = platforms.of_surface(e.surface)
  if not p then
    return nil
  end
  local info = { i = p.index, n = p.name, st = platforms.state_name(p.state), pa = bit(p.paused),
    sp = math.floor((p.speed or 0) * 600 + 0.5) / 10, w = math.floor((try(function() return p.weight end) or 0) + 0.5) }
  local loc = p.space_location
  if loc then
    info.loc = loc.name
  end
  info.from, info.to, info.d, info.len = platforms.journey(p)
  info.th, info.fuel = thrusters(e.surface)
  info.sched = schedule_of(p)
  info.sec = M.sections_of(e)
  info.prov = bit(try(function() return e.providing_to_other_platforms end))
  info.dest = destinations(e.force)
  return info
end

-- The platform's schedule from its hub's screen: {u, records} / {u, i} / {u, interrupts}, in the
-- shapes gui.hub.sched has. Records name space locations; anything else is refused.
local function record_in(force, rec)
  if type(rec) ~= "table" or type(rec.station) ~= "string" then
    return nil
  end
  local ok = false
  for _, d in ipairs(destinations(force)) do
    ok = ok or d == rec.station
  end
  if not ok then
    return nil
  end
  local out = { station = rec.station }
  if type(rec.wait_conditions) == "table" then
    out.wait_conditions = rec.wait_conditions
  end
  if rec.allows_unloading == false then
    out.allows_unloading = false
  end
  return out
end

function M.set_schedule(e, cmd)
  local p = platforms.of_surface(e.surface)
  if type(cmd.records) ~= "table" then
    return puppet.message("That isn't a schedule")
  end
  local records = {}
  for _, rec in ipairs(cmd.records) do
    local r = record_in(e.force, rec)
    if r then
      records[#records + 1] = r
    end
  end
  p.get_schedule().set_records(records)
end

function M.go_to(e, cmd)
  platforms.of_surface(e.surface).get_schedule().go_to_station(math.floor(tonumber(cmd.i) or 1))
end

function M.set_interrupts(e, cmd)
  if type(cmd.interrupts) ~= "table" then
    return puppet.message("Those aren't interrupts")
  end
  local list = {}
  for _, int in ipairs(cmd.interrupts) do
    if type(int) == "table" then
      local targets = {}
      for _, rec in ipairs(type(int.targets) == "table" and int.targets or {}) do
        targets[#targets + 1] = record_in(e.force, rec)
      end
      list[#list + 1] = { name = tostring(int.name or ""), conditions = type(int.conditions) == "table" and int.conditions or {},
        targets = targets, inside_interrupt = int.inside_interrupt == true or int.inside_interrupt == 1 }
    end
  end
  platforms.of_surface(e.surface).get_schedule().set_interrupts(list)
end

-- {u, prov?: 0/1, pa?: 0/1}: provide to other platforms; pause the platform.
function M.set_hub(e, cmd)
  if cmd.prov == 0 or cmd.prov == 1 then
    e.providing_to_other_platforms = cmd.prov == 1
  end
  if cmd.pa == 0 or cmd.pa == 1 then
    platforms.of_surface(e.surface).paused = cmd.pa == 1
  end
end

---------------------------------------------------------------------------------------------
-- Rocket silos

local silo_states
local function silo_status(e)
  if not silo_states then
    silo_states = {}
    for name, v in pairs(defines.rocket_silo_status) do
      silo_states[v] = name
    end
  end
  local s = try(function() return e.rocket_silo_status end)
  return s and silo_states[s] or ""
end

local function launch_targets(e)
  local out = {}
  local planet = platforms.planet_of(e.surface)
  local list = try(function() return e.force.platforms end) or {}
  for _, p in pairs(list) do
    if p.valid and p.scheduled_for_deletion == 0 then
      local loc = p.space_location
      if planet and loc and loc.name == planet then
        out[#out + 1] = { p.index, p.name, platforms.state_name(p.state) }
      end
    end
  end
  table.sort(out, function(a, b) return a[1] < b[1] end)
  return out
end

-- Adds to gui.rk: st (rocket_silo_status), auto (sends to orbit by itself), to (platforms in orbit
-- that a rocket can go to: [[index, name, state], ...]).
function M.silo_info(e, rk)
  rk.st = silo_status(e)
  rk.auto = bit(try(function() return e.send_to_orbit_automatically end))
  rk.to = launch_targets(e)
  return rk
end

-- {u, auto: 0/1}
function M.set_silo(e, cmd)
  if cmd.auto == 0 or cmd.auto == 1 then
    e.send_to_orbit_automatically = cmd.auto == 1
  end
end

-- {u, to: platform index}: launch the rocket that stands ready to platform `to`, orbiting this
-- planet: its hub when it has one, else the starter pack the platform is waiting for.
function M.launch(e, cmd)
  local target
  for _, p in pairs(try(function() return e.force.platforms end) or {}) do
    if p.valid and p.index == math.floor(tonumber(cmd.to) or -1) then
      target = p
    end
  end
  if not target then
    return puppet.message("No such platform")
  end
  local loc = target.space_location
  if not (loc and loc.name == platforms.planet_of(e.surface)) then
    return puppet.message("That platform isn't in orbit here")
  end
  -- A platform still waiting for its starter pack gets it from any rocket that carries one: the
  -- game launches that by itself (seen in 2.1.23).
  local dest
  if target.hub and target.hub.valid then
    dest = { type = defines.cargo_destination.station, station = target.hub }
  else
    dest = { type = defines.cargo_destination.space_platform, space_platform = target }
  end
  -- launch_rocket(destination?, character?) takes its arguments in order (2.1.23).
  local ok, launched = pcall(function() return e.launch_rocket(dest) end)
  if not ok then
    return puppet.message("Can't launch: " .. tostring(launched))
  end
  if not launched then
    puppet.message("The rocket isn't ready")
  end
end

-- {u, to: platform index}: the character gets into the rocket standing ready and rides it up to
-- platform `to`'s hub, as a player does from the silo. launch_rocket's second argument puts a
-- character in the rocket's cargo pod; it works without a player (2.1.23): the pod climbs with the
-- character for about 20 s, changes surface, comes down onto the platform and leaves the
-- character inside the hub (LuaControl.hub). The client follows it all through `me`.
function M.ride(e, cmd)
  local c = puppet.get()
  if not c then
    return
  end
  if puppet.pod(c) or puppet.hub(c) then
    return puppet.message("You're already on your way")
  end
  if puppet.vehicle(c) then
    return puppet.message("Get out of the vehicle first")
  end
  if not c.can_reach_entity(e) then
    return puppet.message("The rocket silo is out of reach")
  end
  local target
  for _, p in pairs(try(function() return e.force.platforms end) or {}) do
    if p.valid and p.index == math.floor(tonumber(cmd.to) or -1) then
      target = p
    end
  end
  if not target then
    return puppet.message("No such platform")
  end
  local loc = target.space_location
  if not (loc and loc.name == platforms.planet_of(e.surface)) then
    return puppet.message("That platform isn't in orbit here")
  end
  if not (target.hub and target.hub.valid) then
    return puppet.message("That platform has no hub yet: send it its starter pack first")
  end
  local ok, launched = pcall(function()
    return e.launch_rocket({ type = defines.cargo_destination.station, station = target.hub }, c)
  end)
  if not ok then
    return puppet.message("Can't launch: " .. tostring(launched))
  end
  if not launched or not puppet.pod(c) then
    return puppet.message("The rocket isn't ready")
  end
  storage.f3d.trip = { up = true }
end

---------------------------------------------------------------------------------------------
-- Cargo landing pads, bays, asteroid collectors

-- gui.pad: {cb?: {read, req, empty}, sec}
local function pad_info(e)
  local info = { sec = M.sections_of(e) }
  local cb = try(function() return e.get_control_behavior() end)
  if cb then
    info.cb = {
      read = bit(try(function() return cb.read_contents end)),
      req = bit(try(function() return cb.set_requests end)),
      empty = bit(try(function() return cb.read_empty_slots end)),
    }
  end
  return info
end

-- {u, read?, req?, empty?: 0/1}: the pad's circuit settings.
function M.set_pad(e, cmd)
  local cb = e.get_or_create_control_behavior()
  if cmd.read == 0 or cmd.read == 1 then
    cb.read_contents = cmd.read == 1
  end
  if cmd.req == 0 or cmd.req == 1 then
    cb.set_requests = cmd.req == 1
  end
  if cmd.empty == 0 or cmd.empty == 1 then
    cb.read_empty_slots = cmd.empty == 1
  end
end

-- How many chunk filters a collector shows: in 2.1.23 filter_slot_count is how many are set (0
-- for a new collector) and set_filter takes any slot, so one per asteroid chunk kind.
local function collector_slots(e)
  local n = 0
  for name, chunk in pairs(prototypes.asteroid_chunk) do
    if not chunk.hidden and name:sub(-15) == "-asteroid-chunk" then
      n = n + 1
    end
  end
  return math.max(e.filter_slot_count, math.min(n, 8), 1)
end

-- gui.col: {n, f: [chunk name or "", ...]}
local function collector_info(e)
  local n = collector_slots(e)
  local f = {}
  for i = 1, n do
    f[i] = name_of(try(function() return e.get_filter(i) end)) or ""
  end
  return { n = n, f = f }
end

-- {u, f: [chunk name or "", ...]}
function M.set_collector(e, cmd)
  if type(cmd.f) ~= "table" then
    return
  end
  for i = 1, collector_slots(e) do
    local name = cmd.f[i]
    if type(name) == "string" and name ~= "" and prototypes.asteroid_chunk[name] then
      e.set_filter(i, name)
    else
      e.set_filter(i, nil)
    end
  end
end

-- Adds Space Age's fields to a `gui` message.
function M.fill(msg, e, kind)
  if kind == "hub" then
    msg.hub = try(hub_info, e)
    local q = qualities(e.force)
    if #q > 1 then
      msg.ql = q
    end
  elseif kind == "pad" then
    msg.pad = try(pad_info, e)
    local q = qualities(e.force)
    if #q > 1 then
      msg.ql = q
    end
  elseif kind == "bay" then
    local owner = try(function() return e.cargo_bay_connection_owner end)
    msg.bay = { owner = owner and owner.valid and owner.unit_number or 0 }
  elseif kind == "collector" then
    msg.col = try(collector_info, e)
  elseif kind == "silo" and msg.rk then
    pcall(M.silo_info, e, msg.rk)
  end
  if kind == "crafter" or kind == "furnace" or kind == "lab" or kind == "other" or kind == "silo" then
    msg.eff = modules.effects_of(e)
  end
  if kind == "crafter" or kind == "furnace" then
    local ok, _, quality = pcall(function() return e.get_recipe() end)
    local qn = ok and name_of(quality)
    if qn and qn ~= "normal" then
      msg.rq = qn
    end
    if kind == "crafter" then
      local q = qualities(e.force)
      if #q > 1 then
        msg.ql = q
      end
    end
  end
end

---------------------------------------------------------------------------------------------
-- The solar system (smap) and new platforms

-- {t = "smap", loc = [[name, type, x, y (thousandths of a star map unit), unlocked, has surface,
--  magnitude (thousandths), draw orbit, label orientation (thousandths of a turn)]],
--  con = [[from, to, length (km), danger (0-1000)]]}
function M.smap_message(force)
  local msg = { t = "smap", loc = {}, con = {} }
  for name, loc in pairs(try(function() return prototypes.space_location end) or {}) do
    -- Hidden ones ("space-location-unknown") aren't on Factorio's star map.
    if try(function() return loc.hidden end) then
      goto continue
    end
    local pos = try(function() return loc.position end) or { x = 0, y = 0 }
    local unlocked = try(function() return force.is_space_location_unlocked(name) end)
    local planet = game.planets[name]
    local has_surface = planet and try(function() return planet.surface end) and 1 or 0
    -- How Factorio's star map draws it: its size, whether its orbit is drawn, where its label goes.
    local function thousandths(key, default)
      local v = try(function() return loc[key] end)
      return math.floor((type(v) == "number" and v or default) * 1000 + 0.5)
    end
    local orbit = try(function() return loc.draw_orbit end)
    msg.loc[#msg.loc + 1] = { name, loc.type or "planet", math.floor((pos.x or pos[1] or 0) * 1000 + 0.5),
      math.floor((pos.y or pos[2] or 0) * 1000 + 0.5), bit(unlocked), has_surface, thousandths("magnitude", 1),
      orbit == false and 0 or 1, thousandths("label_orientation", 0.25) }
    ::continue::
  end
  table.sort(msg.loc, function(a, b) return a[1] < b[1] end)
  local raw, most = {}, 0
  for _, c in pairs(try(function() return prototypes.space_connection end) or {}) do
    -- Danger: how many asteroids a platform meets along it, from the spawn definitions.
    local danger = 0
    for _, def in pairs(try(function() return c.asteroid_spawn_definitions end) or {}) do
      for _, point in pairs(def.spawn_points or {}) do
        danger = danger + (point.probability or 0) * math.max(0.1, point.speed or 0)
      end
    end
    most = math.max(most, danger)
    raw[#raw + 1] = { c.from.name, c.to.name, math.floor((c.length or 0) + 0.5), danger }
  end
  for _, r in ipairs(raw) do
    r[4] = most > 0 and math.floor(r[4] / most * 1000 + 0.5) or 0
    msg.con[#msg.con + 1] = r
  end
  table.sort(msg.con, function(a, b) return a[1] .. a[2] < b[1] .. b[2] end)
  return msg
end

-- {}: the client asks for the solar system when it opens the space map.
function M.smap_request()
  local c = puppet.get()
  transport.send_now(M.smap_message(c and c.force or game.forces.player))
end

-- {planet?, q?}: Factorio's "new platform": a platform over the planet, waiting for one of the
-- character's starter packs (a rocket silo then takes it up). The pack stays in the inventory
-- until it is launched, as in the game.
function M.new_platform(cmd)
  local c = puppet.get()
  if not c then
    return
  end
  local pack
  local main = c.get_main_inventory()
  for name, item in pairs(prototypes.item) do
    if item.type == "space-platform-starter-pack" and main and main.get_item_count(name) > 0 then
      pack = pack or name
    end
  end
  if not pack then
    return puppet.message("You need a space platform starter pack")
  end
  local planet = type(cmd.planet) == "string" and cmd.planet ~= "" and cmd.planet or platforms.planet_of(c.surface)
  if not (planet and game.planets[planet]) then
    return puppet.message("Platforms are made over a planet")
  end
  local spec = { planet = planet, starter_pack = pack }
  if quality_ok(cmd.q) then
    spec.starter_pack = { name = pack, quality = cmd.q }
  end
  local ok, p = pcall(function() return c.force.create_space_platform(spec) end)
  if not (ok and p) then
    return puppet.message("Can't make a platform there: " .. tostring(p))
  end
  puppet.message("New platform " .. p.name .. " over " .. planet .. ": launch its starter pack from a rocket silo")
  platforms.send()
end

---------------------------------------------------------------------------------------------
-- Asteroid chunks near the focus (on a platform)

local sent_chunks = false

-- [[name, x, y, vx, vy], ...]: positions fixed, movement in 1/256 tile per second.
local function chunks(surface, f)
  local out = {}
  local p = platforms.of_surface(surface)
  if not p then
    return out
  end
  local found = try(function()
    return p.find_asteroid_chunks_filtered({ area = { { f.x - f.r, f.y - f.r }, { f.x + f.r, f.y + f.r } }, limit = MAX_CHUNKS })
  end) or {}
  for _, ch in pairs(found) do
    local mv = ch.movement or { x = 0, y = 0 }
    out[#out + 1] = { ch.name, world.fixed(ch.position.x), world.fixed(ch.position.y),
      math.floor((mv.x or mv[1] or 0) * 60 * 256 + 0.5), math.floor((mv.y or mv[2] or 0) * 60 * 256 + 0.5) }
  end
  return out
end

function M.tick()
  if game.tick % CHUNK_INTERVAL ~= 0 then
    return
  end
  local list = chunks(world.surface(), storage.f3d.focus)
  if #list > 0 or sent_chunks then
    transport.send_now({ t = "ach", l = list })
  end
  sent_chunks = #list > 0
end

---------------------------------------------------------------------------------------------
-- Surface conditions: what can't be built here

-- The first surface condition `proto` fails on `surface`, as {property, min, max, value}, or nil.
local function failed_condition(surface, proto)
  local conds = try(function() return proto.surface_conditions end)
  if not conds or try(function() return surface.ignore_surface_conditions end) then
    return nil
  end
  for _, cond in pairs(conds) do
    local value = try(function() return surface.get_property(cond.property) end)
    if value and (value < cond.min or value > cond.max) then
      return { cond.property, cond.min, cond.max, value }
    end
  end
  return nil
end

local UNITS = { pressure = " hPa", gravity = " m/s²", ["magnetic-field"] = " μT", ["solar-power"] = "%" }
local function num(v)
  if v >= 1e6 then
    return "∞"
  end
  return tostring(math.floor(v * 10 + 0.5) / 10)
end

-- "Can't build here: ..." for an entity the surface's conditions forbid, or nil.
function M.cant_build(surface, proto)
  local f = failed_condition(surface, proto)
  if not f then
    return nil
  end
  local unit = UNITS[f[1]] or ""
  local name = f[1]:gsub("-", " ")
  if f[4] < f[2] then
    return string.format("Can't build here: %s is %s%s, it needs at least %s%s", name, num(f[4]), unit, num(f[2]), unit)
  end
  return string.format("Can't build here: %s is %s%s, it needs at most %s%s", name, num(f[4]), unit, num(f[3]), unit)
end

-- For `planet`: [[entity proto id, property, min, max], ...] for the buildable entities this
-- surface's conditions forbid.
function M.blocked(surface)
  local out = {}
  pcall(function()
    for name, proto in pairs(prototypes.entity) do
      local items = try(function() return proto.items_to_place_this end)
      if items and #items > 0 then
        local f = failed_condition(surface, proto)
        if f then
          out[#out + 1] = { registry.entity_id(name), f[1], f[2], math.min(f[3], 1e9) }
        end
      end
    end
  end)
  table.sort(out, function(a, b) return a[1] < b[1] end)
  return out
end

---------------------------------------------------------------------------------------------

function M.add_handlers(handlers, screens)
  handlers.smap = M.smap_request
  handlers.plat_new = M.new_platform
  handlers.set_section = screens.space_command({ hub = true, pad = true, container = true, silo = true }, M.set_section, "That has no requests")
  handlers.set_hub = screens.space_command({ hub = true }, M.set_hub, "That isn't a platform hub")
  handlers.set_silo = screens.space_command({ silo = true }, M.set_silo, "That isn't a rocket silo")
  handlers.silo_launch = screens.space_command({ silo = true }, M.launch, "That isn't a rocket silo")
  handlers.ride = screens.space_command({ silo = true }, M.ride, "That isn't a rocket silo")
  handlers.set_pad = screens.space_command({ pad = true }, M.set_pad, "That isn't a landing pad")
  handlers.set_collector = screens.space_command({ collector = true }, M.set_collector, "That isn't an asteroid collector")
end

function M.reset()
  sent_chunks = false
end

return M
