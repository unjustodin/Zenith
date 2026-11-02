-- Trains: what every train near the focus is doing (`tr`), and for machine screens a train's
-- schedule and mode (any of its rolling stock opened) or a train stop's name and limit, with the
-- commands that change them. 2.x keeps a train's schedule in a LuaSchedule (train.get_schedule()).

local registry = require("scripts.registry")
local transport = require("scripts.transport")
local world = require("scripts.world")
local puppet = require("scripts.puppet")
local tracker = require("scripts.tracker")
local rate = require("scripts.rate")

local M = {}

local INTERVAL = 30
local NO_LIMIT = -1

local ROLLING_STOCK = {
  locomotive = true, ["cargo-wagon"] = true, ["fluid-wagon"] = true, ["artillery-wagon"] = true,
}

function M.is_rolling_stock(e)
  return ROLLING_STOCK[e.type] == true
end

function M.is_stop(e)
  return e.type == "train-stop"
end

-- defines.train_state number -> name ("on_the_path", "wait_station", ...), built once.
local STATE_NAMES
local function state_name(train)
  if not STATE_NAMES then
    STATE_NAMES = {}
    for name, value in pairs(defines.train_state) do
      STATE_NAMES[value] = name
    end
  end
  return STATE_NAMES[train.state] or ""
end

local function stop_name(stop)
  return stop and stop.valid and stop.backer_name or ""
end

-- [id, state, manual 0/1, speed (thousandths of a tile per tick, negative backwards),
--  unit of the stop it is at or 0, name of the stop it is heading for or "", [carriage units]]
local function train_record(train)
  local units = {}
  for _, carriage in pairs(train.carriages) do
    units[#units + 1] = carriage.unit_number
  end
  local station = train.station
  return {
    train.id, state_name(train), train.manual_mode and 1 or 0, math.floor(train.speed * 1000 + 0.5),
    station and station.unit_number or 0, stop_name(train.path_end_stop), units,
  }
end

---------------------------------------------------------------------------------------------
-- Schedules as plain data

-- A record as the client sees it: the game's, with a temporary stop's rail (a LuaEntity) as its
-- position [x, y] (fixed).
local function record_out(rec)
  local out = {}
  for k, v in pairs(rec) do
    if k == "rail" then
      out.rail = { world.fixed(v.position.x), world.fixed(v.position.y) }
    else
      out[k] = v
    end
  end
  return out
end

local function rail_at(surface, xy)
  local x, y = tonumber(xy[1]), tonumber(xy[2])
  if not (x and y) then
    return nil
  end
  for _, e in pairs(surface.find_entities_filtered({ position = { x / 256, y / 256 } })) do
    if string.find(e.type, "rail", 1, true) and not string.find(e.type, "signal", 1, true) then
      return e
    end
  end
  return nil
end

local function record_in(surface, rec)
  local out = {}
  for k, v in pairs(rec) do
    if k == "rail" then
      out.rail = type(v) == "table" and rail_at(surface, v) or nil
    else
      out[k] = v
    end
  end
  return out
end

-- An interrupt as the client sees it: its targets' rails as positions.
local function interrupt_out(int)
  local targets = {}
  for _, rec in pairs(int.targets or {}) do
    targets[#targets + 1] = record_out(rec)
  end
  return { name = int.name or "", conditions = int.conditions or {}, targets = targets,
    inside_interrupt = int.inside_interrupt and true or false }
end

-- {current, records = [...], group, interrupts = [{name, conditions, targets, inside_interrupt}]}.
local function schedule_of(train)
  local schedule = train.get_schedule()
  local records = {}
  for _, rec in pairs(schedule.get_records() or {}) do
    records[#records + 1] = record_out(rec)
  end
  local ok, group = pcall(function() return schedule.group end)
  local interrupts = {}
  local ok2, list = pcall(function() return schedule.get_interrupts() end)
  for _, int in pairs(ok2 and list or {}) do
    interrupts[#interrupts + 1] = interrupt_out(int)
  end
  return { current = schedule.current, records = records, group = ok and group or "", interrupts = interrupts }
end

-- [[name, count, quality?], ...] most first, from get_contents() (2.x: {name, count, quality}).
local function item_list(contents)
  local out = {}
  for _, it in pairs(contents or {}) do
    local rec = { it.name, it.count }
    if it.quality and it.quality ~= "normal" then
      rec[3] = it.quality
    end
    out[#out + 1] = rec
  end
  table.sort(out, function(a, b)
    if a[2] ~= b[2] then
      return a[2] > b[2]
    end
    return a[1] < b[1]
  end)
  return out
end

-- What the whole train carries: items, fluids [[name, amount]], and every locomotive's fuel.
local function cargo_of(train)
  local ok, items = pcall(function() return train.get_contents() end)
  local fluids = {}
  local okf, fl = pcall(function() return train.get_fluid_contents() end)
  for name, amount in pairs(okf and fl or {}) do
    fluids[#fluids + 1] = { name, math.floor(amount + 0.5) }
  end
  table.sort(fluids, function(a, b) return a[2] > b[2] end)
  local fuel, totals = {}, {}
  local okl, locos = pcall(function() return train.locomotives end)
  for _, side in pairs(okl and locos or {}) do
    for _, loco in pairs(side) do
      local okv, inv = pcall(function() return loco.get_fuel_inventory() end)
      if okv and inv then
        for _, it in pairs(inv.get_contents()) do
          local key = it.name .. "/" .. (it.quality or "normal")
          if not totals[key] then
            totals[key] = { name = it.name, count = 0, quality = it.quality }
            fuel[#fuel + 1] = totals[key]
          end
          totals[key].count = totals[key].count + it.count
        end
      end
    end
  end
  return ok and item_list(items) or {}, fluids, item_list(fuel)
end

-- The names of the force's train stops on a surface, sorted, each once (for "go to station" and
-- new schedule records).
local MAX_STOP_NAMES = 400
local function stop_names(surface, force)
  local ok, stops = pcall(function()
    return game.train_manager.get_train_stops({ surface = surface, force = force })
  end)
  local seen, out = {}, {}
  for _, stop in pairs(ok and stops or {}) do
    local name = stop.backer_name or ""
    if name ~= "" and not seen[name] and #out < MAX_STOP_NAMES then
      seen[name] = true
      out[#out + 1] = name
    end
  end
  table.sort(out)
  return out
end

-- For the gui of an open rolling stock: {id, state, manual, station, dest, sched}.
function M.train_info(e)
  local train = e.train
  if not train then
    return nil
  end
  local info = {
    id = train.id, state = state_name(train), manual = train.manual_mode and 1 or 0,
    station = stop_name(train.station), dest = stop_name(train.path_end_stop),
  }
  local ok, sched = pcall(schedule_of, train)
  info.sched = ok and sched or nil
  info.cargo, info.fluids, info.fuel = cargo_of(train)
  info.stops = stop_names(e.surface, e.force)
  info.speed = math.floor(train.speed * 1000 + 0.5)
  local okn, name = pcall(function() return e.backer_name end)
  info.name = okn and name or nil
  -- The force's train groups with their train counts ([[name, count], ...]): Factorio's "[2]" after
  -- the group's name and its "Change train group" list.
  local okg, groups = pcall(M.groups, e.force)
  if okg then
    info.groups = groups
    local mine = info.sched and info.sched.group or ""
    for _, g in ipairs(groups) do
      if g[1] == mine and mine ~= "" then
        info.gc = g[2]
      end
    end
  end
  local okf, front = pcall(function() return train.front_stock end)
  if okf and front and front.valid then
    info.pos = { world.fixed(front.position.x), world.fixed(front.position.y) }
  end
  return info
end

local MAX_STOP_TRAINS = 30

-- For the gui of an open train stop: {name, limit (-1 for none), count (trains heading there)}.
-- 2.1 reads no limit as the largest uint32 rather than nil.
function M.stop_info(e)
  local limit = e.trains_limit
  if limit and limit >= 4294967295 then
    limit = nil
  end
  local ok, count = pcall(function() return e.trains_count end)
  local info = { name = e.backer_name or "", limit = limit or NO_LIMIT, count = ok and count or 0 }
  local okp, priority = pcall(function() return e.train_stop_priority end)
  info.pri = okp and priority or 50
  info.cb = M.stop_circuit(e)
  local okt, stopped = pcall(function() return e.get_stopped_train() end)
  info.train = okt and stopped and stopped.id or 0
  -- The trains with this stop in their schedule, for the window's train cards: [[id, state,
  -- heading here (0/1), its front stock's unit], ...].
  local oks, list = pcall(function() return e.get_train_stop_trains() end)
  info.trs = {}
  for _, t in ipairs(oks and list or {}) do
    if #info.trs >= MAX_STOP_TRAINS then
      break
    end
    local here = t.path_end_stop and t.path_end_stop == e
    local front = t.front_stock
    info.trs[#info.trs + 1] = { t.id, state_name(t), here and 1 or 0, front and front.unit_number or 0 }
  end
  return info
end

-- The stop's circuit settings as Factorio's train stop window shows them: {wired (on a circuit
-- network), en (enable/disable), cond (its condition), send (send to train), read (read train
-- contents), stopped (read stopped train) + stopped_sig, limit (set trains limit) + limit_sig,
-- count (read trains count) + count_sig, pri (set priority) + pri_sig}.
local STOP_FLAGS = { send = "send_to_train", read = "read_from_train", stopped = "read_stopped_train",
  limit = "set_trains_limit", count = "read_trains_count", pri = "set_priority" }
local STOP_SIGNALS = { stopped_sig = "stopped_train_signal", limit_sig = "trains_limit_signal",
  count_sig = "trains_count_signal", pri_sig = "priority_signal" }

local function signal_out(sig)
  if type(sig) ~= "table" or not sig.name then
    return nil
  end
  local name = sig.name
  if type(name) ~= "string" then
    name = name.name
  end
  return { type = sig.type or "item", name = name }
end

function M.stop_circuit(e)
  -- Without a control behavior the stop has Factorio's defaults: only "send to train" is on.
  local out = { wired = 0, en = 0, send = 1, read = 0, stopped = 0, limit = 0, count = 0, pri = 0 }
  local okw, red = pcall(function() return e.get_circuit_network(defines.wire_connector_id.circuit_red) end)
  local okg, green = pcall(function() return e.get_circuit_network(defines.wire_connector_id.circuit_green) end)
  out.wired = ((okw and red) or (okg and green)) and 1 or 0
  local ok, cb = pcall(function() return e.get_control_behavior() end)
  if not (ok and cb) then
    return out
  end
  pcall(function() out.en = cb.circuit_enable_disable and 1 or 0 end)
  pcall(function()
    local c = cb.circuit_condition
    if c then
      out.cond = { first_signal = signal_out(c.first_signal), second_signal = signal_out(c.second_signal),
        constant = c.constant, comparator = c.comparator }
    end
  end)
  for k, key in pairs(STOP_FLAGS) do
    pcall(function() out[k] = cb[key] and 1 or 0 end)
  end
  for k, key in pairs(STOP_SIGNALS) do
    pcall(function() out[k] = signal_out(cb[key]) end)
  end
  return out
end

local function signal_in(v)
  if type(v) ~= "table" or type(v.name) ~= "string" or v.name == "" then
    return nil
  end
  return { type = type(v.type) == "string" and v.type or "item", name = v.name }
end

-- {key = value} from the client's stop window: flags 0/1, signals {type, name} ({} clears), en,
-- cond {first_signal, comparator, constant | second_signal}.
local function set_stop_circuit(e, cb_in)
  local cb = e.get_or_create_control_behavior()
  if not cb then
    return puppet.message("That stop has no circuit settings")
  end
  for k, v in pairs(cb_in) do
    if STOP_FLAGS[k] then
      cb[STOP_FLAGS[k]] = v == 1 or v == true
    elseif STOP_SIGNALS[k] then
      cb[STOP_SIGNALS[k]] = signal_in(v)
    elseif k == "en" then
      cb.circuit_enable_disable = v == 1 or v == true
    elseif k == "cond" and type(v) == "table" then
      local c = { comparator = type(v.comparator) == "string" and v.comparator or "<", first_signal = signal_in(v.first_signal) }
      if signal_in(v.second_signal) then
        c.second_signal = signal_in(v.second_signal)
      else
        c.constant = math.floor(tonumber(v.constant) or 0)
      end
      cb.circuit_condition = c
    end
  end
end

---------------------------------------------------------------------------------------------
-- Commands, on the open screen's entity (screens.lua checks it is open and in reach)

-- {records}: the train's new schedule records, in the shape `gui.tr.sched.records` has.
function M.set_schedule(e, cmd)
  if type(cmd.records) ~= "table" then
    return puppet.message("That isn't a schedule")
  end
  local records = {}
  for _, rec in ipairs(cmd.records) do
    if type(rec) == "table" then
      records[#records + 1] = record_in(e.surface, rec)
    end
  end
  local ok, err = pcall(function() e.train.get_schedule().set_records(records) end)
  if not ok then
    puppet.message("Can't set the schedule: " .. tostring(err))
  end
end

-- {i}: send the train to its schedule's record i.
function M.go_to(e, cmd)
  local i = math.floor(tonumber(cmd.i) or 0)
  local ok, err = pcall(function() e.train.get_schedule().go_to_station(i) end)
  if not ok then
    puppet.message("Can't go there: " .. tostring(err))
  end
end

-- [[group, trains in it], ...] of the force's trains, by name; "" counts the trains in no group
-- (Factorio's "[No group assigned]" row).
function M.groups(force)
  local counts = {}
  for _, train in pairs(game.train_manager.get_trains({ force = force })) do
    local g = train.group or ""
    counts[g] = (counts[g] or 0) + 1
  end
  local out = {}
  for g, n in pairs(counts) do
    out[#out + 1] = { g, n }
  end
  table.sort(out, function(a, b) return a[1] < b[1] end)
  return out
end

-- {g, all? (0/1)}: Factorio's "Change train group": the train joins group g ("" leaves its group;
-- a new name makes a group of it). all = 1 (Ctrl while submitting) renames the train's whole group.
function M.set_group(e, cmd)
  local train = e.train
  local name = type(cmd.g) == "string" and cmd.g:sub(1, 200) or ""
  local old = train.group or ""
  if cmd.all == 1 and old ~= "" then
    for _, t in pairs(game.train_manager.get_trains({ force = e.force })) do
      if t.group == old then
        t.group = name
      end
    end
  else
    train.group = name
  end
end

-- {auto}: 1 automatic (follow the schedule), 0 manual.
function M.set_mode(e, cmd)
  e.train.manual_mode = not (cmd.auto == 1 or cmd.auto == true)
end

-- {name?, limit? (-1 for none)}: rename a train stop or change its trains limit.
function M.set_stop(e, cmd)
  if type(cmd.name) == "string" and cmd.name ~= "" then
    e.backer_name = cmd.name
  end
  local limit = tonumber(cmd.limit)
  if limit then
    if limit < 0 then
      e.trains_limit = nil
    else
      e.trains_limit = math.floor(limit)
    end
  end
  local priority = tonumber(cmd.pri)
  if priority then
    e.train_stop_priority = math.max(0, math.min(255, math.floor(priority)))
  end
  if type(cmd.cb) == "table" then
    local ok, err = pcall(set_stop_circuit, e, cmd.cb)
    if not ok then
      puppet.message("Can't change the circuit settings: " .. tostring(err))
    end
  end
  tracker.changed(e)
end

-- {interrupts: [{name, conditions, targets, inside_interrupt}]}: the train's interrupts, in the
-- shape `gui.tr.sched.interrupts` has.
function M.set_interrupts(e, cmd)
  if type(cmd.interrupts) ~= "table" then
    return puppet.message("Those aren't interrupts")
  end
  local list = {}
  for _, int in ipairs(cmd.interrupts) do
    if type(int) == "table" then
      local targets = {}
      for _, rec in ipairs(type(int.targets) == "table" and int.targets or {}) do
        if type(rec) == "table" then
          targets[#targets + 1] = record_in(e.surface, rec)
        end
      end
      list[#list + 1] = { name = tostring(int.name or ""), conditions = type(int.conditions) == "table" and int.conditions or {},
        targets = targets, inside_interrupt = int.inside_interrupt == true or int.inside_interrupt == 1 }
    end
  end
  local ok, err = pcall(function() e.train.get_schedule().set_interrupts(list) end)
  if not ok then
    puppet.message("Can't set the interrupts: " .. tostring(err))
  end
end

-- {station? (a stop's name) | rail? [x, y] (fixed)}: Factorio's "go to" (Ctrl+click on the map):
-- a temporary record after the current one, and the train goes there now, in automatic.
function M.temp_stop(e, cmd)
  local data = { temporary = true }
  if type(cmd.station) == "string" and cmd.station ~= "" then
    data.station = cmd.station
  elseif type(cmd.rail) == "table" then
    data.rail = rail_at(e.surface, cmd.rail)
    if not data.rail then
      return puppet.message("No rail there")
    end
  else
    return puppet.message("Go where?")
  end
  local ok, err = pcall(function()
    local schedule = e.train.get_schedule()
    local at = math.min((schedule.current or 0) + 1, schedule.get_record_count() + 1)
    data.index = { schedule_index = at }
    schedule.add_record(data)
    schedule.go_to_station(at)
  end)
  if not ok then
    puppet.message("Can't go there: " .. tostring(err))
  end
end

---------------------------------------------------------------------------------------------
-- Factorio's trains overview: every train of the force, on every surface

local TRAINS_PER_MESSAGE = 40

-- [id, state, manual 0/1, the stop it is at or heading for ("" none), group, carriages, front
--  unit, x, y (fixed), surface index, speed, [[item, count] x up to 3], [[fluid, amount] x up to 1]]
local function overview_record(train)
  local okf, front = pcall(function() return train.front_stock end)
  front = okf and front and front.valid and front or nil
  local p = front and front.position or { x = 0, y = 0 }
  local items, fluids = cargo_of(train)
  local top = {}
  for i = 1, math.min(3, #items) do
    top[i] = { items[i][1], items[i][2] }
  end
  local okg, group = pcall(function() return train.group end)
  local here = stop_name(train.station)
  return {
    train.id, state_name(train), train.manual_mode and 1 or 0, here ~= "" and here or stop_name(train.path_end_stop),
    okg and group or "", #train.carriages, front and front.unit_number or 0, world.fixed(p.x), world.fixed(p.y),
    front and front.surface.index or 0, math.floor(train.speed * 1000 + 0.5), top, { fluids[1] },
  }
end

-- {}: sends `trl`, every train of the character's force, in parts.
function M.list(cmd)
  local c = puppet.get()
  local force = c and c.force or game.forces.player
  local ok, list = pcall(function() return game.train_manager.get_trains({ force = force }) end)
  local records = {}
  for _, train in pairs(ok and list or {}) do
    if train.valid then
      records[#records + 1] = overview_record(train)
    end
  end
  table.sort(records, function(a, b) return a[1] < b[1] end)
  local parts = math.max(1, math.ceil(#records / TRAINS_PER_MESSAGE))
  for part = 1, parts do
    local slice = {}
    for i = (part - 1) * TRAINS_PER_MESSAGE + 1, math.min(part * TRAINS_PER_MESSAGE, #records) do
      slice[#slice + 1] = records[i]
    end
    transport.send_now({ t = "trl", part = part, parts = parts, l = slice })
  end
end

-- {id, auto}: the overview's automatic / manual switch, on any train of the force.
function M.set_mode_by_id(cmd)
  local c = puppet.get()
  local ok, train = pcall(function() return game.train_manager.get_train_by_id(math.floor(tonumber(cmd.id) or 0)) end)
  if not (ok and train and train.valid and c) then
    return puppet.message("No such train")
  end
  local front = train.front_stock
  if not (front and front.force == c.force) then
    return puppet.message("Not your train")
  end
  train.manual_mode = not (cmd.auto == 1 or cmd.auto == true)
  M.list(cmd)
end

---------------------------------------------------------------------------------------------

function M.register()
  script.on_event(defines.events.on_entity_renamed, function(event)
    tracker.changed(event.entity)
  end)
end

function M.tick()
  if not rate.due("tr", INTERVAL) then
    return
  end
  local s = storage.f3d
  local f = s.focus
  local types = registry.rolling_stock_types()
  if #types == 0 then
    return
  end
  local found = world.surface().find_entities_filtered({
    area = { { f.x - f.r, f.y - f.r }, { f.x + f.r, f.y + f.r } },
    type = types,
  })
  local seen, list = {}, {}
  for _, e in pairs(found) do
    local train = e.train
    if train and not seen[train.id] then
      seen[train.id] = true
      list[#list + 1] = train_record(train)
    end
  end
  table.sort(list, function(a, b) return a[1] < b[1] end)
  transport.send_now({ t = "tr", l = list })
end

return M
