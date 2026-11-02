-- Space platforms (Space Age): what the client's platform panel shows, commands to send a
-- platform somewhere, and moving the bridge's character between a platform and the planet it
-- orbits. A player makes that trip by rocket and cargo pod; the bridge's character has no player
-- to ride them, so it is teleported, but only where the trip is possible in the game: up to a
-- platform orbiting the character's planet, and down from a platform stopped at a planet.
--
-- The panel data is read-only. The commands run from on_udp_packet_received (or a console
-- command), which every peer replays alike.

local transport = require("scripts.transport")
local world = require("scripts.world")
local puppet = require("scripts.puppet")

local M = {}

local INTERVAL = 60
local IDLE_INTERVAL = 600 -- without any platforms, just now and then so the client knows
local MAX_PLATFORMS = 32
local MAX_RECORDS = 16
local STARTER_PACK = "space-platform-starter-pack"

local state_names
local function state_name(state)
  if not state_names then
    state_names = {}
    for name, value in pairs(defines.space_platform_state) do
      state_names[value] = name
    end
  end
  return state_names[state] or tostring(state)
end

M.state_name = state_name

-- The force's platforms, or nil without Space Age (the API is there in 2.x, but guard anyway).
local function platforms_of(force)
  local ok, list = pcall(function() return force.platforms end)
  return ok and list or nil
end

-- The platform whose surface this is, or nil on a planet.
function M.of_surface(surface)
  local ok, p = pcall(function() return surface.platform end)
  return ok and p or nil
end

-- The planet a surface belongs to, by name, or nil (platforms and script surfaces).
function M.planet_of(surface)
  local ok, planet = pcall(function() return surface.planet end)
  return ok and planet and planet.name or nil
end

-- Which way a platform travels its connection, by index: {conn, d, back}. Module-local: it only
-- shapes what is sent.
local headings = {}

-- A travelling platform's journey as Factorio shows it: where it left, where it is heading, how
-- far it has come (thousandths) and the connection's length (km); nil when not travelling.
-- `distance` runs 0 at the connection's `from` to 1 at its `to`, and a platform sent the other
-- way along it counts down (checked in 2.1.23: heading to nauvis on nauvis-vulcanus, 0.500 ->
-- 0.493, speed still positive), so going Fulgora -> Gleba on gleba-fulgora read backwards (owner's
-- G9). The schedule's current stop says the way when it is one of the two ends; otherwise (a trip
-- of several legs) the way `distance` moves since the last look.
function M.journey(p)
  local conn = p.space_connection
  if not conn then
    headings[p.index] = nil
    return nil
  end
  local d = p.distance or 0
  local seen = headings[p.index]
  if seen and seen.conn ~= conn.name then
    seen = nil
  end
  local back = seen and seen.back or false
  local sched = p.schedule
  local rec = sched and sched.records and sched.records[sched.current or 1]
  local stop = rec and rec.station
  if stop == conn.from.name then
    back = true
  elseif stop == conn.to.name then
    back = false
  elseif seen and d ~= seen.d then
    back = d < seen.d
  end
  headings[p.index] = { conn = conn.name, d = d, back = back }
  local from, to = conn.from.name, conn.to.name
  if back then
    from, to, d = to, from, 1 - d
  end
  return from, to, math.floor(d * 1000 + 0.5), math.floor(conn.length + 0.5)
end

local function find(force, i)
  local list = platforms_of(force)
  local p = list and list[math.floor(tonumber(i) or 0)]
  return p and p.valid and p or nil
end

local function stations(p)
  local sched = p.schedule
  if not sched then
    return nil
  end
  local names = {}
  for _, rec in ipairs(sched.records or {}) do
    if #names >= MAX_RECORDS then
      break
    end
    names[#names + 1] = rec.station or ""
  end
  return { c = sched.current or 1, l = names }
end

-- Where a platform stopped at `loc` goes next by its schedule (H7: the client's panel says so while
-- it waits, which Factorio's doesn't): the current record when that is somewhere else (it is about
-- to leave, or has no path), else the next record that isn't here. nil without one.
local function next_stop(p, loc)
  local sched = p.schedule
  local records = sched and sched.records
  local n = records and #records or 0
  if n == 0 then
    return nil
  end
  local cur = sched.current or 1
  local rec = records[cur]
  if rec and rec.station and rec.station ~= loc then
    return rec.station
  end
  for k = 1, n - 1 do
    local r = records[(cur - 1 + k) % n + 1]
    if r.station and r.station ~= loc then
      return r.station
    end
  end
  return nil
end

-- {i, n, st, loc?, nx?, from?, to?, d?, len?, sp, w?, pa, hub, sch?}: one platform, see PROTOCOL.md.
local function summary(p)
  local rec = { i = p.index, n = p.name, st = state_name(p.state), pa = p.paused and 1 or 0, hub = 0 }
  local loc = p.space_location
  if loc then
    rec.loc = loc.name
    rec.nx = next_stop(p, loc.name)
  end
  rec.from, rec.to, rec.d, rec.len = M.journey(p)
  -- speed is in km per tick; Factorio shows km/s.
  rec.sp = math.floor((p.speed or 0) * 600 + 0.5) / 10
  -- the mass Factorio's remote view shows for a platform (kg)
  local okw, w = pcall(function() return p.weight end)
  rec.w = okw and type(w) == "number" and math.floor(w + 0.5) or nil
  local hub = p.hub
  if hub and hub.valid then
    rec.hub = hub.unit_number or 0
  end
  rec.sch = stations(p)
  return rec
end

-- Where platforms can be sent: the planets and other space locations this force has unlocked.
local function destinations(force)
  local out = {}
  local ok = pcall(function()
    for name in pairs(prototypes.space_location) do
      if force.is_space_location_unlocked(name) then
        out[#out + 1] = name
      end
    end
  end)
  table.sort(out)
  return ok and out or {}
end

-- {t = "plat", on, here?, l = [...], dest = [...]}
function M.message()
  local c = puppet.get()
  local force = c and c.force or game.forces.player
  local list = platforms_of(force)
  if not list then
    return nil
  end
  local surface = c and c.surface or world.surface()
  local on = M.of_surface(surface)
  local out = { t = "plat", on = on and on.valid and on.index or 0, l = {}, dest = destinations(force) }
  local here = M.planet_of(surface)
  if here then
    out.here = here
  end
  for _, p in pairs(list) do
    if #out.l >= MAX_PLATFORMS then
      break
    end
    -- Platforms waiting for their starter pack have no surface yet; the panel lists them too.
    if p.valid and p.scheduled_for_deletion == 0 then
      out.l[#out.l + 1] = summary(p)
    end
  end
  table.sort(out.l, function(a, b) return a.i < b.i end)
  return out
end

function M.send()
  local msg = M.message()
  if msg then
    transport.send_now(msg)
  end
  return msg
end

function M.tick()
  local s = storage.f3d
  if game.tick % INTERVAL ~= 0 then
    return
  end
  local c = puppet.get()
  local busy = c and M.of_surface(c.surface) ~= nil
  if not busy then
    local list = c and platforms_of(c.force)
    busy = list and next(list) ~= nil
  end
  if busy or game.tick - (s.plat_sent or -IDLE_INTERVAL) >= IDLE_INTERVAL then
    s.plat_sent = game.tick
    M.send()
  end
end

---------------------------------------------------------------------------------------------
-- Moving the character

local function land(c, surface, near)
  local pos = surface.find_non_colliding_position("character", near, 32, 0.5) or near
  -- Cross-surface teleport works for a character (checked in 2.1.23 by live_check.py).
  if not c.teleport(pos, surface) then
    return false
  end
  puppet.reset()
  return true
end

-- Puts the character on platform p, beside its hub.
function M.board(c, p)
  if not (p.surface and p.surface.valid) then
    return false, "That platform isn't built yet"
  end
  local hub = p.hub
  local near = hub and hub.valid and hub.position or { x = 0, y = 0 }
  if not land(c, p.surface, near) then
    return false, "Couldn't move there"
  end
  return true
end

-- Puts the character on the surface of `planet` (a name), at the force's spawn point there.
function M.descend(c, planet)
  local lp = game.planets[planet]
  if not lp then
    return false, "There is no planet " .. tostring(planet)
  end
  local surface = lp.surface or lp.create_surface()
  local spawn = c.force.get_spawn_position(surface)
  if not land(c, surface, spawn) then
    return false, "Couldn't move there"
  end
  return true
end

---------------------------------------------------------------------------------------------
-- Commands from the client: plat_go, plat_sched, plat_pause, plat_board

local function command_platform(cmd)
  local c = puppet.get()
  if not c then
    return nil
  end
  local p = find(c.force, cmd.i)
  if not p then
    puppet.message("No such platform")
    return nil
  end
  return p, c
end

local function set_records(p, names)
  local records = {}
  for _, name in ipairs(names) do
    records[#records + 1] = { station = name }
  end
  if #records == 0 then
    p.schedule = nil
  else
    p.schedule = { current = 1, records = records }
  end
end

local function known_destination(force, name)
  for _, d in ipairs(destinations(force)) do
    if d == name then
      return true
    end
  end
  return false
end

-- {i, to}: travel to one place and stay there (a one-stop schedule), and stop pausing.
function M.go(cmd)
  local p, c = command_platform(cmd)
  if not p then
    return
  end
  local to = tostring(cmd.to or "")
  if not known_destination(c.force, to) then
    return puppet.message("Can't travel to " .. to)
  end
  local ok, err = pcall(function()
    set_records(p, { to })
    p.paused = false
  end)
  if not ok then
    puppet.message("Can't set the destination: " .. tostring(err))
  end
  M.send()
end

-- {i, l = [location names], c?}: the platform's schedule as a list of stops (no wait conditions).
function M.set_schedule(cmd)
  local p, c = command_platform(cmd)
  if not p or type(cmd.l) ~= "table" then
    return
  end
  local names = {}
  for _, name in ipairs(cmd.l) do
    if #names < MAX_RECORDS and known_destination(c.force, tostring(name)) then
      names[#names + 1] = tostring(name)
    end
  end
  local ok, err = pcall(function()
    set_records(p, names)
    local current = math.floor(tonumber(cmd.c) or 1)
    if #names > 0 and current >= 1 and current <= #names then
      p.get_schedule().go_to_station(current)
    end
  end)
  if not ok then
    puppet.message("Can't set the schedule: " .. tostring(err))
  end
  M.send()
end

-- {i, p = 1 pause / 0 resume}
function M.pause(cmd)
  local p = command_platform(cmd)
  if p then
    p.paused = cmd.p == 1 or cmd.p == true
    M.send()
  end
end

-- {i}: i > 0 boards platform i, which must orbit the character's planet (where a rocket would
-- take it); i = 0 drops to the planet the character's platform is stopped at. The surface change
-- itself is noticed by session.tick, which tells the client.
function M.board_command(cmd)
  local c = puppet.get()
  if not c then
    return
  end
  local i = math.floor(tonumber(cmd.i) or 0)
  local ok, err
  if i == 0 then
    local p = M.of_surface(c.surface)
    if not p then
      return puppet.message("You're not on a platform")
    end
    local loc = p.space_location
    if not (loc and loc.type == "planet") then
      return puppet.message("The platform must be stopped at a planet to drop to it")
    end
    ok, err = M.descend(c, loc.name)
  else
    local p = find(c.force, i)
    if not p then
      return puppet.message("No such platform")
    end
    local here = M.planet_of(c.surface)
    local loc = p.space_location
    if not (here and loc and loc.name == here) then
      return puppet.message("That platform isn't in orbit here")
    end
    ok, err = M.board(c, p)
  end
  if not ok then
    puppet.message(err)
  end
end

---------------------------------------------------------------------------------------------
-- /f3d-platform, for testing: new [planet] | board <index or name> | leave [planet] | list

function M.by_name(force, arg)
  local list = platforms_of(force) or {}
  local i = tonumber(arg)
  if i then
    return find(force, i)
  end
  for _, p in pairs(list) do
    if p.valid and p.name == arg then
      return p
    end
  end
  return nil
end

function M.console(cmd)
  local words = {}
  for w in string.gmatch(cmd.parameter or "", "%S+") do
    words[#words + 1] = w
  end
  local c = puppet.get()
  if not c then
    return { "[Zenith] no character" }
  end
  local force = c.force
  local verb = words[1] or "list"
  if verb == "new" then
    if not prototypes.item[STARTER_PACK] then
      return { "[Zenith] no space platforms here (Space Age isn't enabled)" }
    end
    local planet = words[2] or M.planet_of(c.surface) or "nauvis"
    local p = force.create_space_platform({ planet = planet, starter_pack = STARTER_PACK })
    if not p then
      return { "[Zenith] couldn't create a platform at " .. planet }
    end
    p.apply_starter_pack()
    return { string.format("[Zenith] platform %d (%s) built in orbit of %s", p.index, p.name, planet) }
  elseif verb == "board" then
    local p = M.by_name(force, words[2] or "1")
    if not p then
      return { "[Zenith] no such platform" }
    end
    local ok, err = M.board(c, p)
    return { ok and ("[Zenith] character moved to platform " .. p.name) or ("[Zenith] " .. err) }
  elseif verb == "leave" then
    local p = M.of_surface(c.surface)
    local planet = words[2] or (p and p.space_location and p.space_location.name) or "nauvis"
    local ok, err = M.descend(c, planet)
    return { ok and ("[Zenith] character moved to " .. planet) or ("[Zenith] " .. err) }
  end
  local lines = {}
  for _, rec in ipairs((M.message() or { l = {} }).l) do
    lines[#lines + 1] = string.format("[Zenith] platform %d %s: %s at %s", rec.i, rec.n, rec.st,
      rec.loc or ((rec.from or "?") .. " -> " .. (rec.to or "?")))
  end
  if #lines == 0 then
    lines[1] = "[Zenith] no platforms (/f3d-platform new builds one)"
  end
  return lines
end

return M
