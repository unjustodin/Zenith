-- How often the periodic jobs run, slowed down on the client's word (`rate` command, level 0-3):
-- when the server is under load the bridge sends its costliest updates less often rather than
-- sending less of the world, so the game keeps its speed and the client glides further between
-- updates ("the world may lag but the server won't"). The character's own updates (`me`) never
-- slow down.
--
-- Jobs are ranked by what they cost on the owner's save (/f3d-profile trace): the costliest (tier 1)
-- stretch from level 1, the next from level 2, the rest from level 3, each doubling its interval per
-- level past its first, up to its own longest period. A stretched job runs on a tick of its own
-- (`phase`), at every level, so jobs that used to land together on every 30th or 60th tick don't.
--
-- What the client glides (`mv`, `bi`, `ih`) says how far apart its updates are (`p`). Movers and
-- belt items are drawn behind the game's clock by about that much, so after a slow-down the client
-- has to draw them further behind: those (`ease`) keep their old rate for EASE_TICKS while already
-- saying the new one, and the client eases its delay in meanwhile instead of running out of
-- positions and stopping.
--
-- Deterministic: the level lives in storage.f3d (set from a client command, like `focus`), each
-- job's last runs too (from on_tick), and everything else is worked out from them and game.tick.

local M = {}

M.MAX_LEVEL = 3
local EASE_TICKS = 120

-- tier: the level a job first slows down at. max: its longest period, in ticks. phase: the tick
-- (modulo its period) a stretched job runs on; odd, so off the 30th and 60th ticks where
-- crafting, research, trains and the rest land, and apart from each other.
local JOBS = {
  bi = { tier = 1, max = 48, phase = 1, ease = true },  -- items on belts: the costliest by far
  lanes = { tier = 1, max = 8, phase = 0 },   -- far belt lanes: a factor on their rounds, not a tick
  mv = { tier = 1, max = 16, phase = 1, ease = true },  -- movers' positions (and how often they are searched)
  st = { tier = 2, max = 120, phase = 17 },   -- machine working states
  wires = { tier = 2, max = 120, phase = 23 }, -- tracker's look for changed wires
  seg = { tier = 2, max = 8, phase = 1 },     -- demolishers' segments (planets.lua)
  en = { tier = 2, max = 40, phase = 7 },     -- enemies attacking
  life = { tier = 2, max = 240, phase = 43 }, -- plants, spawners, frozen machines (planets.lua): ~30 ms a run on the owner's save
  fp = { tier = 3, max = 240, phase = 41 },   -- fluids, heat, power (fluids_power.lua)
  tr = { tier = 3, max = 120, phase = 37 },   -- trains
  ts = { tier = 3, max = 24, phase = 5 },     -- turrets' aim
  ih = { tier = 3, max = 24, phase = 3 },     -- inserter hands
  gi = { tier = 3, max = 120, phase = 29 },   -- items on the ground
  rc = { tier = 3, max = 40, phase = 13 },    -- robots' cargo
}
M.JOBS = JOBS

function M.level()
  local s = storage.f3d
  return s and s.rate or 0
end

-- {l}: the client's slow-down level, 0 (normal) to MAX_LEVEL.
function M.set(cmd)
  local s = storage.f3d
  local l = math.max(0, math.min(M.MAX_LEVEL, math.floor(tonumber(cmd.l) or 0)))
  local old = s.rate or 0
  if l ~= old then
    s.rate_from, s.rate_at = old, game.tick
  end
  s.rate = l > 0 and l or nil
end

local function factor_at(name, level)
  local over = level - JOBS[name].tier + 1
  if over <= 0 then
    return 1
  end
  return math.floor(2 ^ over + 0.5)
end

-- How many times longer job `name` waits between runs at the current level: 1, 2, 4 or 8.
function M.factor(name)
  return factor_at(name, M.level())
end

-- `double`: the job doubles its own period too (belt items on a busy base), within its longest
-- (or twice its interval, as it always did).
local function period_at(name, interval, level, double)
  local job = JOBS[name]
  local p = interval
  if factor_at(name, level) > 1 then
    p = math.max(interval, math.min(interval * factor_at(name, level), job.max))
  end
  if double then
    p = math.max(p, math.min(p * 2, math.max(job.max, interval * 2)))
  end
  return p
end

-- Ticks between runs of a job that runs every `interval` ticks at level 0, at the current level:
-- what its messages' `p` says.
function M.period(name, interval, double)
  return period_at(name, interval, M.level(), double)
end

-- Whether a job with this period runs this tick at `level`.
local function on_ticks(name, interval, level, double)
  local p = period_at(name, interval, level, double)
  -- Every job on its own phase, at level 0 too: on main's ticks they all fell together once a
  -- second (the bridge budget's finding: 190-250 ms ticks on the owner's save).
  local phase = JOBS[name].phase
  return game.tick % p == phase % p, p
end

-- Whether job `name` (every `interval` ticks at level 0) runs this tick. For EASE_TICKS after a
-- slow-down an `ease` job also still runs on its old ticks, so no gap is ever longer than its `p`.
function M.due(name, interval, double)
  local s = storage.f3d
  local now, p = on_ticks(name, interval, s.rate or 0, double)
  local t = game.tick
  if not now and JOBS[name].ease and s.rate_at and (s.rate_from or 0) < (s.rate or 0) and t < s.rate_at + EASE_TICKS then
    now = on_ticks(name, interval, s.rate_from or 0, double)
  end
  if not now then
    return false
  end
  local s = storage.f3d
  s.rate_jobs = s.rate_jobs or {}
  local j = s.rate_jobs[name]
  s.rate_jobs[name] = { prev = j and j.last or t - p, last = t }
  return true
end

-- Whether a multiple of `every` passed since the job's run before this one (due just said yes):
-- for work a job did on `game.tick % every == 0`, which a stretched job's ticks may never land on.
function M.crossed(name, every)
  local j = storage.f3d.rate_jobs[name]
  return math.floor(j.last / every) ~= math.floor(j.prev / every)
end

-- A new world (handshake, resync): each job starts over.
function M.reset()
  storage.f3d.rate_jobs = nil
end

return M
