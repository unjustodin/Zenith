-- The bridge's work budget per tick. A big request from the client (a map view's charts, the chunks
-- after a jump or a join, another planet's remote view, Factoriopedia, the trains on the map...) must
-- never make one slow tick, so every job that can be big works through a queue in slices, and each
-- slice is paid for from this budget. When the tick's budget is spent, the rest waits for the next
-- tick.
--
-- Mods can't read a clock (it would differ between peers), so the budget is counted in work units:
-- one unit is about one entity read and painted into a chart (15-30 us on the laptop, measured on
-- the owner's save in 2.1.23; a chunk snapshot's record is two), TILES_PER_UNIT tiles read are one
-- unit, and other slices are priced the same way from what they read. Everything here lives in the client's state (storage.f3d.bud) and only
-- changes from on_tick and packets, so it is the same on every peer.
--
-- Once a second the client gets `wb`: the budget, the units used per tick (average and most), how
-- many ticks went over it (a job's last slice may run past what is left), and how long each queue
-- is. The client may set the budget with `budget` {u}; it is clamped to FLOOR..CEILING.

local transport = require("scripts.transport")
local profile = require("scripts.profile")

local M = {}

M.DEFAULT = 300
M.FLOOR = 50
M.CEILING = 20000
M.TILES_PER_UNIT = 16
local REPORT_TICKS = 60

-- name -> function() -> how long that queue is now (registered by the modules that own them).
local queues = {}
local queue_order = {}

function M.register_queue(name, fn)
  if not queues[name] then
    queue_order[#queue_order + 1] = name
  end
  queues[name] = fn
end

local function state()
  local s = storage.f3d
  local b = s.bud
  if not b then
    b = { limit = M.DEFAULT, used = 0, sum = 0, max = 0, n = 0, over = 0, jobs = {} }
    s.bud = b
  end
  return b
end

function M.limit()
  return state().limit
end

-- Called before the client's modules run each tick.
function M.begin()
  local b = state()
  b.used = 0
  for k in pairs(b.jobs) do
    b.jobs[k] = 0
  end
end

-- Units left this tick. With `job` and `share` (0-1), also no more than that share of the budget
-- for this job, so one long queue can't starve the others.
function M.left(job, share)
  local b = state()
  local free = b.limit - b.used
  if job and share then
    free = math.min(free, math.floor(b.limit * share) - (b.jobs[job] or 0))
  end
  return free
end

-- Whether a slice of `price` units may run now: when it fits what is left, or, when it doesn't,
-- as the job's first slice this tick while anything is left (so a slice dearer than the whole
-- budget still moves; that tick goes over by at most that slice, and `wb` counts it).
function M.can(price, job, share)
  local left = M.left(job, share)
  if price <= left then
    return true
  end
  return left > 0 and (state().jobs[job] or 0) == 0
end

function M.spend(units, job)
  local b = state()
  units = math.max(0, math.floor(units or 0))
  b.used = b.used + units
  if job then
    b.jobs[job] = (b.jobs[job] or 0) + units
  end
end

-- How big one slice of a job may be: half the budget, so a tick fits about two, at least `least`.
function M.slice(least)
  return math.max(least or 25, math.floor(state().limit / 2))
end

-- Called after the client's modules ran: the tick's figures, and `wb` once a second.
function M.finish()
  local b = state()
  if profile.tracing() and b.used > 0 then
    -- Beside /f3d-profile trace's times, to price the units (tools/request_spikes.py).
    local parts = {}
    for job, n in pairs(b.jobs) do
      if n > 0 then
        parts[#parts + 1] = job .. "=" .. n
      end
    end
    log("f3dunits " .. game.tick .. " " .. b.used .. " " .. table.concat(parts, " "))
  end
  b.sum = b.sum + b.used
  b.n = b.n + 1
  if b.used > b.max then
    b.max = b.used
  end
  if b.used > b.limit then
    b.over = b.over + 1
  end
  if b.n < REPORT_TICKS then
    return
  end
  local q = {}
  for _, name in ipairs(queue_order) do
    local ok, n = pcall(queues[name])
    q[name] = ok and math.floor(tonumber(n) or 0) or 0
  end
  transport.send_now({ t = "wb", b = b.limit, avg = math.floor(b.sum / b.n + 0.5), max = b.max, over = b.over,
    n = b.n, q = q })
  b.sum, b.n, b.max, b.over = 0, 0, 0, 0
end

-- `budget` {u}: the client sets the budget in units per tick (clamped).
function M.set(cmd)
  local u = tonumber(cmd.u)
  if not u or u ~= u then
    return
  end
  state().limit = math.max(M.FLOOR, math.min(M.CEILING, math.floor(u)))
end

-- Lines for /f3d-status.
function M.report()
  local b = storage.f3d and storage.f3d.bud
  if not b then
    return {}
  end
  local parts = {}
  for _, name in ipairs(queue_order) do
    local ok, n = pcall(queues[name])
    parts[#parts + 1] = name .. " " .. (ok and tostring(n) or "?")
  end
  return { string.format("[Zenith] work budget %d units a tick; queues: %s", b.limit, table.concat(parts, ", ")) }
end

return M
