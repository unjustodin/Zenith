-- What weapons fire, near the client's camera: projectiles, flamethrower streams and beams in
-- flight (`pj`, every other tick while there are any), the projectiles that just ended and the
-- explosions the game made, and the fires and clouds on the ground (`gf`, a full list four times
-- a second). Whoever fired them: the character, turrets, vehicles, biters' acid.
--
-- None of these has a unit_number, so each is known by its register_on_object_destroyed number,
-- which is the same every time the same entity is registered (checked in 2.1.23) and tells us
-- when it is gone. A headless server with no player never creates the explosions marked
-- only_when_visible (the muzzle flash and bullet hits, a rocket's explosion: checked in 2.1.23),
-- so `pj.e` reports where each projectile ended and the client plays its effects itself.
--
-- storage.f3d.shots changes only in on_tick and on_object_destroyed, from what the game has, so
-- it stays the same on every peer.

local transport = require("scripts.transport")
local world = require("scripts.world")
local map = require("scripts.map")

local M = {}

local SCAN_INTERVAL = 2
-- After QUIET_TICKS with nothing in flight the search runs every QUIET_INTERVAL ticks instead: on a
-- busy base it costs ~1 ms a time (0.5 ms a tick), mostly for nothing. Explosions last longer than
-- that, so the first shot of a fight is seen a few ticks late at most, and then every 2 ticks.
local QUIET_INTERVAL = 6
local QUIET_TICKS = 60
local GROUND_INTERVAL = 15
local MAX_RADIUS = 48
local MAX_FLYING = 400
local MAX_GROUND = 300
local FLYING_TYPES = { "projectile", "artillery-projectile", "stream", "beam", "explosion" }
local GROUND_TYPES = { "fire", "smoke-with-trigger" }

local function state()
  local s = storage.f3d
  s.shots = s.shots or { live = {}, seen = {}, ended = {} }
  return s.shots
end

local function area(r)
  local f = storage.f3d.focus
  return { { f.x - r, f.y - r }, { f.x + r, f.y + r } }
end

local function radius()
  local f = storage.f3d.focus
  return f and math.min(f.r, MAX_RADIUS) or 0
end

-- Where a beam starts or ends: the entity it is attached to, else its position.
local function beam_end(e, getter)
  local ok, t = pcall(getter)
  if not ok or not t then
    return e.position
  end
  if t.entity and t.entity.valid then
    return t.entity.position
  end
  return t.position or e.position
end

local fixed = world.fixed

-- The records of a flat list (`size` values each, x at `at` and y after it, 1/256 tile) the remote
-- view sees. Only what is sent: what is stored about shots stays the same.
local function only_seen(seen, flat, size, at)
  local out = {}
  for i = 1, #flat, size do
    if seen(flat[i + at - 1] / 256, flat[i + at] / 256) then
      for j = i, i + size - 1 do
        out[#out + 1] = flat[j]
      end
    end
  end
  return out
end

local function scan(sh, r)
  local p, b, x = {}, {}, {}
  local live, seen = {}, {}
  local found = world.surface().find_entities_filtered({ area = area(r), type = FLYING_TYPES })
  for _, e in pairs(found) do
    local id = script.register_on_object_destroyed(e)
    local t = e.type
    local pos = e.position
    if t == "explosion" then
      seen[id] = true
      if not sh.seen[id] then
        x[#x + 1] = e.name
        x[#x + 1] = fixed(pos.x)
        x[#x + 1] = fixed(pos.y)
      end
    elseif t == "beam" then
      if #b < MAX_FLYING * 6 then
        local s0 = beam_end(e, e.get_beam_source)
        local t0 = beam_end(e, e.get_beam_target)
        b[#b + 1] = id
        b[#b + 1] = e.name
        b[#b + 1] = fixed(s0.x)
        b[#b + 1] = fixed(s0.y)
        b[#b + 1] = fixed(t0.x)
        b[#b + 1] = fixed(t0.y)
      end
    elseif #p < MAX_FLYING * 4 then
      p[#p + 1] = id
      p[#p + 1] = e.name
      p[#p + 1] = fixed(pos.x)
      p[#p + 1] = fixed(pos.y)
      live[id] = { pos.x, pos.y }
    end
  end
  -- Ones that left the area aren't ending: forget them without a report.
  sh.live = live
  sh.seen = seen
  local ended = sh.ended
  sh.ended = {}
  local any = #p > 0 or #b > 0 or #x > 0 or #ended > 0
  if any or sh.flying then
    local seen = map.view_filter()
    if seen then
      p, b, x, ended = only_seen(seen, p, 4, 3), only_seen(seen, b, 6, 3), only_seen(seen, x, 3, 2), only_seen(seen, ended, 3, 2)
    end
    transport.send_now({ t = "pj", p = p, b = b, x = x, e = ended })
  end
  sh.flying = any or nil
  if any or #found > 0 then
    sh.busy_tick = game.tick
  end
end

local function scan_ground(sh, r)
  local l = {}
  local found = world.surface().find_entities_filtered({ area = area(r), type = GROUND_TYPES })
  for _, e in pairs(found) do
    if #l >= MAX_GROUND * 5 then
      break
    end
    local pos = e.position
    local ttl = -1
    if e.type == "smoke-with-trigger" then
      local ok, v = pcall(function() return e.time_to_live end)
      ttl = ok and v or -1
    end
    l[#l + 1] = script.register_on_object_destroyed(e)
    l[#l + 1] = e.name
    l[#l + 1] = fixed(pos.x)
    l[#l + 1] = fixed(pos.y)
    l[#l + 1] = ttl
  end
  if #l > 0 or sh.grounded then
    local seen = map.view_filter()
    transport.send_now({ t = "gf", l = seen and only_seen(seen, l, 5, 3) or l })
  end
  sh.grounded = #l > 0 or nil
end

function M.tick()
  local r = radius()
  if r <= 0 then
    return
  end
  local sh = state()
  local quiet = game.tick - (sh.busy_tick or 0) > QUIET_TICKS
  if game.tick % (quiet and QUIET_INTERVAL or SCAN_INTERVAL) == 0 then
    scan(sh, r)
  end
  if game.tick % GROUND_INTERVAL == 0 then
    scan_ground(sh, r)
  end
end

-- A projectile or stream we last saw in flight is gone: it hit or ran out of range there.
function M.on_object_destroyed(event)
  local s = storage.f3d
  local sh = s and s.shots
  local last = sh and sh.live[event.registration_number]
  if not last then
    return
  end
  sh.live[event.registration_number] = nil
  local e = sh.ended
  e[#e + 1] = event.registration_number
  e[#e + 1] = fixed(last[1])
  e[#e + 1] = fixed(last[2])
end

function M.register()
  script.on_event(defines.events.on_object_destroyed, M.on_object_destroyed)
end

function M.reset()
  storage.f3d.shots = nil
end

return M
