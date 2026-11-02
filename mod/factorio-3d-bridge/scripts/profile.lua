-- What the bridge costs per tick, module by module: `/f3d-profile` turns timing on, and
-- `/f3d-status` then shows each module's average over the last 10 seconds.
--
-- Measuring only: the timers live here, not in `storage`, and nothing they read changes the
-- game, so peers that differ (one profiling, one not) still stay in sync.

local M = {}

local WINDOW = 600 -- ticks averaged in a report

local enabled = false
local order = {}   -- module names in the order they first ran
local timers = {}  -- name -> LuaProfiler for one call
local totals = {}  -- name -> LuaProfiler summed over the current window
local last = nil   -- name -> LuaProfiler, average per tick over the last full window
local ticks = 0
-- `/f3d-profile trace`: each tick's time per module also goes to the game's log, one line a
-- tick ("f3d-trace <tick> name Elapsed: x ms ..."), so the worst ticks can be found afterwards (a
-- LuaProfiler can't be read as a number in Lua, only printed). Short runs: it writes a lot.
local tracing = false

-- Trace mode (`/f3d-profile trace N`): for N ticks, every module's and packet's time is written to
-- the log, one line each, so single slow ticks can be found (a profiler can't be read as a number,
-- only printed). tools/tick_trace.py reads the lines back.
local trace_left = 0
local trace_tick = {}  -- this tick's {name, profiler} in order

function M.trace(n)
  trace_left = math.max(0, math.floor(tonumber(n) or 0))
  trace_tick = {}
  return trace_left
end

function M.tracing()
  return trace_left > 0
end

function M.toggle(trace)
  enabled = not enabled or (trace and not tracing) or false
  tracing = enabled and trace or false
  order, timers, totals, last, ticks = {}, {}, {}, nil, 0
  return enabled, tracing
end

-- Runs fn (one module's tick) and, while profiling, adds its time to the module's total.
function M.run(name, fn, ...)
  if trace_left > 0 then
    local t = helpers.create_profiler()
    fn(...)
    t.stop()
    trace_tick[#trace_tick + 1] = { name, t }
    if not enabled then
      return
    end
  elseif not enabled then
    return fn(...)
  end
  local t = timers[name]
  if not t then
    t = helpers.create_profiler(true)
    timers[name] = t
    totals[name] = helpers.create_profiler(true)
    order[#order + 1] = name
  end
  -- reset, not restart: restart carries on from the last call's time, so every call would add
  -- all the ones before it.
  t.reset()
  fn(...)
  t.stop()
  totals[name].add(t)
end

-- Call once per tick, after the modules ran.
function M.end_tick()
  if trace_left > 0 then
    trace_left = trace_left - 1
    local total = helpers.create_profiler(true)
    for _, row in ipairs(trace_tick) do
      total.add(row[2])
      log({ "", "f3dtrace ", game.tick, " ", row[1], " ", row[2] })
    end
    log({ "", "f3dtrace ", game.tick, " TOTAL ", total })
    trace_tick = {}
  end
  if not enabled then
    return
  end
  if tracing then
    -- A localised string takes at most 20 parameters: modules go in nested groups of 8.
    local line, group = { "", "f3d-trace ", game.tick }, nil
    for i, name in ipairs(order) do
      if (i - 1) % 8 == 0 then
        group = { "" }
        line[#line + 1] = group
      end
      group[#group + 1] = { "", " ", name, " ", timers[name] }
    end
    log(line)
  end
  ticks = ticks + 1
  if ticks < WINDOW then
    return
  end
  for _, total in pairs(totals) do
    total.divide(WINDOW)
  end
  last, totals, ticks = totals, {}, 0
  for name in pairs(last) do
    totals[name] = helpers.create_profiler(true)
  end
end

-- Lines for /f3d-status (localised strings: a profiler only prints itself).
function M.report()
  if not enabled then
    return { "[Zenith] profiling off (/f3d-profile turns it on)" }
  end
  if not last then
    return { "[Zenith] profiling: the first average is ready after " .. WINDOW .. " ticks" }
  end
  local lines = {}
  for _, name in ipairs(order) do
    if last[name] then
      lines[#lines + 1] = { "", "[Zenith] ", name, ": ", last[name], " per tick" }
    end
  end
  return lines
end

return M
