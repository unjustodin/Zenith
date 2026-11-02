-- Asteroid collectors near the client's camera (`acol`), so the client can draw their arms
-- reaching for asteroid chunks, catching them and pulling them in, as Factorio does.
--
-- 2.1.23 shows nothing of a collector's arms to scripts (no arm count, positions or targets), so
-- this sends what decides them: each collector's arm count and speed (prototype and quality),
-- whether its arms can move now (power, a full output, the circuit network) and its chunk
-- filters; and which chunks it caught. A chunk an arm grabs leaves the platform's chunk list the
-- tick the head reaches it (measured in 2.1.23: a still chunk 6 tiles out goes after 30 ticks,
-- 0.2 tiles a tick, and lands in the output when the arm is back 1.5 tiles from the centre), so
-- a chunk inside a collector's catch circle that is gone where it should have drifted to was
-- caught there. Chunks move in straight lines, which makes that prediction exact.
--
-- Everything is kept in storage.f3d and changed only on_tick, so every peer computes the same.

local transport = require("scripts.transport")
local world = require("scripts.world")
local platforms = require("scripts.platforms")

local M = {}

local INTERVAL = 10        -- ticks between looks, as `ach`
local REFRESH = 60         -- ticks between looking for collectors near the focus
local FULL = 120           -- ticks between resending the rows when nothing changed
local MATCH = 0.06         -- tiles: a chunk is where its movement says, to this much (positions are 1/256 tile)
local MAX_COLLECTORS = 64  -- nearest the focus first
-- The prototype's catch circle when it can't be read: collection_radius 7.5 round a point
-- collection_box_offset 5 tiles in front; head_collection_radius 0.6 reaches past it.
local RADIUS, OFFSET, HEAD = 7.5, 5.0, 0.6

local function try(fn, ...)
  local ok, v = pcall(fn, ...)
  if ok then
    return v
  end
  return nil
end

-- defines.entity_status by value (only from defines, so the same on every peer).
local status_names
local function status_name(v)
  if not status_names then
    status_names = {}
    for name, value in pairs(defines.entity_status) do
      status_names[value] = name
    end
  end
  return status_names[v]
end

-- Statuses whose arms move: working, or slowed by low power. A full output holds them where
-- they are; switched off (no power, the circuit network, a script, marked for deconstruction) they
-- fold back home.
local MOVING = { working = 1, normal = 1, low_power = 1 }
local FOLDED = { no_power = 1, disabled_by_control_behavior = 1, disabled_by_script = 1, disabled = 1,
  marked_for_deconstruction = 1, frozen = 1 }

-- The catch circle's centre and radius for a collector facing `direction` (16-way).
local function catch(e)
  local p = e.prototype
  local radius = try(function() return p.collection_radius end) or RADIUS
  local offset = try(function() return p.collection_box_offset end) or OFFSET
  local a = (e.direction or 0) / 16 * 2 * math.pi
  return e.position.x + math.sin(a) * offset, e.position.y - math.cos(a) * offset, radius
end

-- [u, arms, speed (1/1000 tile a tick), 1 moving / 0 held / 2 folded, [chunk filter, ...]]: no
-- filters takes all.
local function row(e)
  local p = e.prototype
  local level = try(function() return e.quality.level end) or 0
  local arms = (try(function() return p.arm_count_base end) or 1) + level * (try(function() return p.arm_count_quality_scaling end) or 1)
  local speed = (try(function() return p.arm_speed_base end) or 0.2) + level * (try(function() return p.arm_speed_quality_scaling end) or 0.05)
  local status = status_name(e.status)
  if status == "low_power" then
    speed = speed * (try(function() return p.unpowered_arm_speed_scale end) or 0.3)
  end
  local filters = {}
  for i = 1, 8 do
    local f = try(function() return e.get_filter(i) end)
    if f then
      filters[#filters + 1] = type(f) == "string" and f or f.name
    end
  end
  return { e.unit_number, arms, math.floor(speed * 1000 + 0.5), MOVING[status] and 1 or (FOLDED[status] and 2 or 0), filters }
end

local function find(s, surface)
  local f = s.focus
  local found = surface.find_entities_filtered({ type = "asteroid-collector",
    area = { { f.x - f.r, f.y - f.r }, { f.x + f.r, f.y + f.r } } })
  table.sort(found, function(a, b)
    local da = (a.position.x - f.x) ^ 2 + (a.position.y - f.y) ^ 2
    local db = (b.position.x - f.x) ^ 2 + (b.position.y - f.y) ^ 2
    if da ~= db then
      return da < db
    end
    return a.unit_number < b.unit_number
  end)
  s.collectors = {}
  for i = 1, math.min(#found, MAX_COLLECTORS) do
    s.collectors[#s.collectors + 1] = found[i]
  end
end

-- The chunks in the square round a collector's catch circle, a tile past a head's reach:
-- {name, x, y, vx, vy}. The margin keeps a chunk drifting out of the circle in the next look.
local function chunks_near(platform, cx, cy, radius)
  local r = radius + HEAD + 1
  local found = try(function()
    return platform.find_asteroid_chunks_filtered({ area = { { cx - r, cy - r }, { cx + r, cy + r } } })
  end) or {}
  local out = {}
  for _, ch in pairs(found) do
    local mv = ch.movement or {}
    out[#out + 1] = { ch.name, ch.position.x, ch.position.y, mv.x or mv[1] or 0, mv.y or mv[2] or 0 }
  end
  return out
end

-- Chunks of `before` (INTERVAL ticks ago) that were in the catch circle (cx, cy, radius) and
-- have nothing of theirs in `now` where they drifted to.
local function caught(before, now, cx, cy, radius)
  local gone = {}
  for _, b in ipairs(before) do
    local x, y = b[2] + b[4] * INTERVAL, b[3] + b[5] * INTERVAL
    local found = (b[2] - cx) ^ 2 + (b[3] - cy) ^ 2 > (radius + HEAD) ^ 2
    for _, n in ipairs(now) do
      if n[1] == b[1] and math.abs(n[2] - x) <= MATCH and math.abs(n[3] - y) <= MATCH then
        found = true
        break
      end
    end
    if not found then
      gone[#gone + 1] = { b[1], x, y }
    end
  end
  return gone
end

function M.tick()
  local s = storage.f3d
  if not s.client or game.tick % INTERVAL ~= 0 then
    return
  end
  local surface = world.surface()
  local platform = surface and platforms.of_surface(surface)
  if not platform then
    if s.collector_rows and s.collector_rows ~= "" then
      transport.send_now({ t = "acol", l = {} })
    end
    s.collectors, s.collector_chunks, s.collector_rows = nil, nil, nil
    return
  end
  if not s.collectors or game.tick % REFRESH == 0 then
    find(s, surface)
  end
  local rows, grabs = {}, {}
  local before = s.collector_chunks or {}
  local now = {}
  for _, e in ipairs(s.collectors) do
    if e.valid then
      local u = e.unit_number
      local r = row(e)
      rows[#rows + 1] = r
      local cx, cy, radius = catch(e)
      now[u] = chunks_near(platform, cx, cy, radius)
      if before[u] then
        for _, g in ipairs(caught(before[u], now[u], cx, cy, radius)) do
          grabs[#grabs + 1] = { u, g[1], world.fixed(g[2]), world.fixed(g[3]) }
        end
      end
    end
  end
  s.collector_chunks = now
  -- A chunk in two collectors' circles counts once: the first (nearest the focus) claims it.
  local seen = {}
  local unique = {}
  for _, g in ipairs(grabs) do
    local key = g[2] .. ":" .. g[3] .. ":" .. g[4]
    if not seen[key] then
      seen[key] = true
      unique[#unique + 1] = g
    end
  end
  local key = {}
  for i, r in ipairs(rows) do
    key[i] = table.concat({ r[1], r[2], r[3], r[4], table.concat(r[5], ",") }, " ")
  end
  local text = table.concat(key, ";")
  local msg = { t = "acol" }
  if text ~= s.collector_rows or (game.tick % FULL == 0 and text ~= "") then
    msg.l = rows
    s.collector_rows = text
  end
  if #unique > 0 then
    msg.g = unique
  end
  if msg.l or msg.g then
    transport.send_now(msg)
  end
end

-- After a handshake, a surface change or when the client leaves: the rows are sent again, or
-- an empty list once if the client's world is not on a platform now.
function M.reset()
  local s = storage.f3d
  s.collectors, s.collector_chunks, s.collector_rows = nil, nil, "?"
end

return M
