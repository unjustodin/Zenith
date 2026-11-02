-- Research for Factorio's technology screen: every technology with its prerequisites, cost and
-- state, the current research with its progress and queue, and commands to queue or cancel.
--
-- The tree is resent when research finishes or is undone (a flag in storage set from the events),
-- so it stays deterministic.

local transport = require("scripts.transport")
local world = require("scripts.world")
local puppet = require("scripts.puppet")
local crafting = require("scripts.crafting")
local pedia = require("scripts.pedia")
local planners = require("scripts.planners")
local budget = require("scripts.budget")

local M = {}

local STATUS_INTERVAL = 60
local TECHS_PER_MESSAGE = 40

local function force()
  local c = puppet.get()
  return c and c.force or game.forces.player
end

local function shown(tech)
  local ok, hidden = pcall(function() return tech.prototype.hidden end)
  return not (ok and hidden) and (tech.enabled or tech.visible_when_disabled)
end

-- 0 locked (a prerequisite is missing), 1 available, 2 researched.
local function state(tech)
  if tech.researched then
    return 2
  end
  for _, pre in pairs(tech.prerequisites) do
    if not pre.researched then
      return 0
    end
  end
  return 1
end

-- Technologies unlocked by doing something (crafting, mining, launching) instead of science
-- packs name the trigger type here (2.x).
local function trigger(tech)
  local ok, t = pcall(function() return tech.prototype.research_trigger end)
  return ok and t and t.type or ""
end

local function read(obj, key)
  local ok, v = pcall(function() return obj[key] end)
  return ok and v or nil
end

-- [name, order, prerequisites, ingredients [[name, amount], ...], unit count, seconds per unit,
--  state, trigger, effects [[type, recipe or modifier target, value], ...], level, max level (-1
--  infinite), trigger detail [type, target, count] or [], saved progress (thousandths), count
--  formula or "", essential (1: shown with "Show only essential technologies", else 0)]
local INFINITE = 4294967295

local function record(tech)
  local pre = {}
  for name in pairs(tech.prerequisites) do
    pre[#pre + 1] = name
  end
  table.sort(pre)
  local ingredients = {}
  for _, ing in pairs(tech.research_unit_ingredients) do
    ingredients[#ingredients + 1] = { ing.name, ing.amount }
  end
  local proto = tech.prototype
  local okfx, effects = pcall(pedia.effects_of, proto)
  local max_level = read(proto, "max_level") or 1
  return {
    tech.name, tech.order, pre, ingredients, tech.research_unit_count, tech.research_unit_energy / 60,
    state(tech), trigger(tech), okfx and effects or {}, read(tech, "level") or 1,
    max_level >= INFINITE and -1 or max_level, pedia.trigger_of(proto) or {},
    math.floor((read(tech, "saved_progress") or 0) * 1000 + 0.5), read(proto, "research_unit_count_formula") or "",
    read(proto, "essential") and 1 or 0,
  }
end

-- The whole tree is about 300 records on Space Age and took 36 ms in one tick on the owner's save,
-- so it is sent a part a tick under the work budget (budget.lua): the names in storage.f3d.techs_job,
-- each part read when it is sent. The client gathers the parts whatever tick they come in.
local TECH_PRICE = 6   -- units per technology record (measured 60-300 us each on the owner's save)

local function start_techs()
  local names = {}
  for _, tech in pairs(force().technologies) do
    if shown(tech) then
      names[#names + 1] = tech.name
    end
  end
  table.sort(names)
  storage.f3d.techs_job = { names = names, part = 1, parts = math.max(1, math.ceil(#names / TECHS_PER_MESSAGE)) }
end

-- Sends parts while the budget lasts; true when the last one went.
local function send_tech_parts()
  local s = storage.f3d
  local job = s.techs_job
  local techs = force().technologies
  while job.part <= job.parts do
    if not budget.can(TECHS_PER_MESSAGE * TECH_PRICE, "techs", 0.5) then
      return false
    end
    budget.spend(TECHS_PER_MESSAGE * TECH_PRICE, "techs")
    local slice = {}
    for i = (job.part - 1) * TECHS_PER_MESSAGE + 1, math.min(job.part * TECHS_PER_MESSAGE, #job.names) do
      local tech = techs[job.names[i]]
      if tech then
        slice[#slice + 1] = record(tech)
      end
    end
    transport.send_reliable({ t = "techs", part = job.part, parts = job.parts, l = slice })
    job.part = job.part + 1
  end
  s.techs_job = nil
  return true
end

function M.queue_length()
  local job = storage.f3d.techs_job
  return job and (job.parts - job.part + 1) or 0
end
budget.register_queue("techs", M.queue_length)

local function queue_names(f)
  local names = {}
  local ok, queue = pcall(function() return f.research_queue end)
  for _, tech in pairs(ok and queue or {}) do
    names[#names + 1] = type(tech) == "string" and tech or tech.name
  end
  return names
end

-- What is being researched now (or ""), its progress, and the queue.
-- defines.entity_status number -> name, built once from the defines.
local STATUS_NAMES
local function status_name(status)
  if not STATUS_NAMES then
    STATUS_NAMES = {}
    for name, value in pairs(defines.entity_status) do
      STATUS_NAMES[value] = name
    end
  end
  return status and STATUS_NAMES[status] or "unknown"
end

-- [[unit, status name], ...] for labs near the camera: "working", "missing_science_packs",
-- "no_research_in_progress", "no_power"... what keeps research from going.
local function labs()
  local s = storage.f3d
  local f = s.focus
  local out = {}
  for _, lab in pairs(world.surface().find_entities_filtered({
    area = { { f.x - f.r, f.y - f.r }, { f.x + f.r, f.y + f.r } },
    type = "lab",
  })) do
    if lab.unit_number then
      out[#out + 1] = { lab.unit_number, status_name(lab.status) }
    end
  end
  return out
end

local function send_status()
  local f = force()
  local current = f.current_research
  transport.send_now({
    t = "rs",
    cur = current and current.name or "",
    pr = current and math.floor(f.research_progress * 1000 + 0.5) or 0,
    q = queue_names(f),
    labs = labs(),
  })
end

-- The recipes a technology unlocks, for the "research completed" notification.
local function unlocks(tech)
  local out = {}
  for _, effect in pairs(tech.prototype.effects or {}) do
    if effect.type == "unlock-recipe" then
      out[#out + 1] = effect.recipe
    end
  end
  return out
end

---------------------------------------------------------------------------------------------
-- Commands

-- Starts researching a technology, or adds it to the end of the queue.
function M.research(cmd)
  local f = force()
  local name = type(cmd.name) == "string" and cmd.name or ""
  local tech = f.technologies[name]
  if not (tech and shown(tech) and tech.enabled and not tech.researched) then
    return puppet.message("Can't research " .. name)
  end
  if not f.add_research(name) then
    puppet.message("Can't research " .. name .. " yet")
  end
  send_status()
end

-- Takes a technology off the queue, or stops it if it is the current research.
function M.research_cancel(cmd)
  local f = force()
  local name = type(cmd.name) == "string" and cmd.name or ""
  local current = f.current_research
  if current and current.name == name then
    f.cancel_current_research()
  else
    local keep = {}
    for _, queued in ipairs(queue_names(f)) do
      if queued ~= name then
        keep[#keep + 1] = queued
      end
    end
    pcall(function() f.research_queue = keep end)
  end
  send_status()
end

---------------------------------------------------------------------------------------------
-- Events

-- Research finished or was undone: the tree, and what can be hand-crafted, need sending again.
function M.on_research_changed(event)
  storage.f3d.techs_dirty = true
  crafting.invalidate()
  -- A notification for the client; `tech` and `unlocks` let it show names in the player's
  -- language (the text is internal names, a headless server can't translate).
  local tech = event.research
  if event.name == defines.events.on_research_finished and tech and storage.f3d.client then
    local ok, list = pcall(unlocks, tech)
    transport.send_now({ t = "msg", text = "Research completed: " .. tech.name, tech = tech.name, unlocks = ok and list or {} })
  end
end

function M.register()
  script.on_event({
    defines.events.on_research_finished,
    defines.events.on_research_reversed,
  }, M.on_research_changed)
end

function M.tick()
  local s = storage.f3d
  if s.techs_dirty and not s.techs_job then
    s.techs_dirty = nil
    start_techs()
  end
  if s.techs_job then
    if send_tech_parts() then
      send_status()
      -- Research can unlock qualities: `quals` again.
      planners.send_initial()
    end
  elseif (game.tick + 37) % STATUS_INTERVAL == 0 then
    send_status()
  end
end

-- A new client gets the whole tree.
function M.send_initial()
  storage.f3d.techs_dirty = true
  storage.f3d.techs_job = nil
end

return M
