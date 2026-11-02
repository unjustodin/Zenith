-- More of Factorio's entity windows for machine screens (screens.lua): inserters (filters,
-- whitelist/blacklist, stack size), splitters (priorities, filter), a chest's limit bar, power
-- switches, turrets' and vehicles' inventories, rocket silos' rocket parts, display panels, and
-- the kinds that only show their status, energy or circuit signals (accumulators, radars, lamps,
-- pumps, tanks, poles). Also the settings Factorio's windows have for lamps (colour), train stops
-- (colour), programmable speakers (sound and alert), pumps (fluid filter), turrets (priority
-- targets) and display panels (messages with conditions). The setters act on the open screen
-- only, like screens.lua's.

local circuit_settings = require("scripts.circuit_settings")

local M = {}

local TURRETS = { ["ammo-turret"] = "turret_ammo", ["artillery-turret"] = "artillery_turret_ammo",
  ["electric-turret"] = false, ["fluid-turret"] = false }
local VEHICLES = { car = { "car_trunk", "car_ammo" }, ["spider-vehicle"] = { "spider_trunk", "spider_ammo" } }
-- Entities with no inventory worth a screen of its own that Factorio still opens: their status,
-- energy, fluid and circuit signals.
local STATUS_ONLY = {
  accumulator = true, radar = true, lamp = true, pump = true, ["offshore-pump"] = true, ["storage-tank"] = true,
  ["programmable-speaker"] = true, ["electric-energy-interface"] = true, ["heat-interface"] = true,
  beacon = true, ["agricultural-tower"] = true, ["asteroid-collector"] = true, ["cargo-landing-pad"] = true,
  ["space-platform-hub"] = true, ["cargo-bay"] = true,
  ["rail-signal"] = true, ["rail-chain-signal"] = true,
  -- 2.1.23 opens these too, unwired (tools/ui_reference rules_openable): their fluid, heat or status.
  pipe = true, ["pipe-to-ground"] = true, ["heat-pipe"] = true, ["land-mine"] = true, ["transport-belt"] = true,
}
-- Entity types Factorio 2.1.23 opens no window for (clicking them does nothing; every buildable
-- type was opened by tools/ui_reference's rules_openable and these left `player.opened` empty).
M.NO_WINDOW = { ["fluid-wagon"] = true, ["lightning-attractor"] = true, ["fusion-generator"] = true, thruster = true,
  generator = true, ["solar-panel"] = true, wall = true, gate = true, ["underground-belt"] = true, plant = true,
  ["straight-rail"] = true, ["curved-rail-a"] = true, ["curved-rail-b"] = true, ["half-diagonal-rail"] = true,
  ["elevated-straight-rail"] = true, ["elevated-curved-rail-a"] = true, ["elevated-curved-rail-b"] = true,
  ["elevated-half-diagonal-rail"] = true, ["rail-ramp"] = true, ["rail-support"] = true,
  ["construction-robot"] = true, ["logistic-robot"] = true, ["cargo-bay"] = true }
-- Entities whose window shows their fluid segment ("Pipeline contents") and the flush buttons.
local PIPELINE = { ["storage-tank"] = true, pipe = true, ["pipe-to-ground"] = true }
local HUB_INVENTORIES = { ["cargo-landing-pad"] = "cargo_landing_pad_main", ["space-platform-hub"] = "hub_main" }

local function define_index(name)
  local ok, index = pcall(function() return defines.inventory[name] end)
  return ok and index or nil
end

-- The screen kind for the entities this module adds, or nil.
function M.kind(e)
  local t = e.type
  if t == "inserter" then
    return "inserter"
  elseif t == "splitter" or t == "lane-splitter" then
    return "splitter"
  elseif t == "power-switch" then
    return "switch"
  elseif TURRETS[t] ~= nil then
    return "turret"
  elseif VEHICLES[t] then
    return "vehicle"
  elseif t == "electric-pole" then
    return "pole"
  elseif t == "rocket-silo" then
    return "silo"
  elseif t == "display-panel" then
    return "panel"
  end
  return nil
end

-- Kinds that open even without inventories or circuit signals.
function M.openable(e)
  return M.kind(e) ~= nil or STATUS_ONLY[e.type] == true
end

-- Kinds whose get_output_inventory shouldn't be shown as "output" (a car's trunk would be twice).
function M.no_output(kind)
  return kind == "turret" or kind == "vehicle" or kind == "inserter" or kind == "splitter" or kind == "switch"
    or kind == "pole" or kind == "panel"
end

-- Adds this module's inventories through add(role, inventory).
function M.add_inventories(e, kind, add)
  if kind == "turret" then
    local name = TURRETS[e.type]
    local index = name and define_index(name)
    add("turret_ammo", index and e.get_inventory(index))
  elseif kind == "vehicle" then
    local names = VEHICLES[e.type]
    local trunk, ammo = define_index(names[1]), define_index(names[2])
    add("trunk", trunk and e.get_inventory(trunk))
    add("car_ammo", ammo and e.get_inventory(ammo))
  elseif kind == "silo" then
    local index = define_index("crafter_input") or define_index("assembling_machine_input")
    add("input", index and e.get_inventory(index))
  elseif HUB_INVENTORIES[e.type] then
    local index = define_index(HUB_INVENTORIES[e.type])
    add("chest", index and e.get_inventory(index))
  end
end

local function filter_name(f)
  if type(f) == "string" then
    return f
  end
  if type(f) ~= "table" then
    return ""
  end
  local name = f.name
  if type(name) == "table" then
    name = name.name
  end
  return name or ""
end

local function inserter_info(e)
  local n = e.filter_slot_count
  local filters = {}
  for i = 1, n do
    filters[i] = filter_name(e.get_filter(i))
  end
  local info = { n = n, f = filters, st = e.inserter_stack_size_override }
  -- What the hand holds: [item, count], or nothing.
  local okh, held = pcall(function() return e.held_stack end)
  if okh and held and held.valid_for_read then
    info.h = { held.name, held.count }
  end
  if n > 0 then
    info.use = e.use_filters and 1 or 0
    info.m = e.inserter_filter_mode or "whitelist"
  end
  -- Space Age: which spoiling items it takes first ("none" otherwise).
  local oks, sp = pcall(function() return e.inserter_spoil_priority end)
  if oks and type(sp) == "string" then
    info.sp = sp
  end
  -- The most it can carry: what it aims for when not overridden, else the force's bonus.
  local ok, target = pcall(function() return e.inserter_target_pickup_count end)
  local ok2, bonus = pcall(function()
    if e.prototype.bulk then
      return e.force.bulk_inserter_capacity_bonus + 1
    end
    return math.floor(e.force.inserter_stack_size_bonus) + 1
  end)
  info.max = math.max(info.st, ok and info.st == 0 and target or 0, ok2 and bonus or 1)
  return info
end

-- Colours are [r, g, b] in 0-255 on the wire; the game gives 0-1 (or 0-255 when written so).
function M.color_out(c)
  local r, g, b = c.r or c[1] or 0, c.g or c[2] or 0, c.b or c[3] or 0
  local scale = (r > 1 or g > 1 or b > 1) and 1 or 255
  return { math.floor(r * scale + 0.5), math.floor(g * scale + 0.5), math.floor(b * scale + 0.5) }
end

local function color_in(v)
  if type(v) ~= "table" then
    return nil
  end
  local function part(x)
    return math.max(0, math.min(255, math.floor(tonumber(x) or 0))) / 255
  end
  return { r = part(v[1]), g = part(v[2]), b = part(v[3]), a = 1 }
end

-- gui.dp: {text, icon ({type, name} or {}), show (always in Alt-mode), chart (show on the map),
-- msgs = [{text, icon, cond}, ...] (shown while their condition holds, with a circuit network)}.
function M.panel_info(e)
  local info = { text = e.display_panel_text or "" }
  local ok, icon = pcall(function() return e.display_panel_icon end)
  info.icon = ok and circuit_settings.signal_out(icon) or {}
  local ok2, show = pcall(function() return e.display_panel_always_show end)
  info.show = ok2 and show and 1 or 0
  local ok3, chart = pcall(function() return e.display_panel_show_in_chart end)
  info.chart = ok3 and chart and 1 or 0
  local ok4, records = pcall(function()
    local b = e.get_control_behavior()
    return b and b.records or {}
  end)
  info.msgs = {}
  for _, r in ipairs(ok4 and records or {}) do
    info.msgs[#info.msgs + 1] = { text = r.text or "", icon = circuit_settings.signal_out(r.icon),
      cond = circuit_settings.condition_out(r.condition) }
  end
  return info
end

-- gui.tgt: {l = [entity names], ign (0/1: shoot only those)}.
function M.targets_info(e)
  local list = {}
  for _, proto in pairs(e.priority_targets or {}) do
    list[#list + 1] = proto.name
  end
  local ok, ign = pcall(function() return e.ignore_unprioritised_targets end)
  return { l = list, ign = ok and ign and 1 or 0 }
end

-- gui.spk: the speaker's parameters, alert, what it plays and the instruments it has:
-- {vol (0-1), mode (local | surface | global), poly, vctl, vsig, inst, note, pitch, stop (0/1),
-- al = {show, map, icon, msg}, il = [[instrument, [note, ...]], ...]}. inst and note count from 0.
function M.speaker_info(e)
  local p = e.parameters
  local b = e.get_control_behavior() or e.get_or_create_control_behavior()
  local cp = b.circuit_parameters
  local a = e.alert_parameters
  local info = {
    vol = math.floor((p.playback_volume or 1) * 100 + 0.5) / 100, mode = p.playback_mode or "local",
    poly = p.allow_polyphony and 1 or 0, vctl = p.volume_controlled_by_signal and 1 or 0,
    vsig = circuit_settings.signal_out(p.volume_signal_id),
    inst = cp.instrument_id or 0, note = cp.note_id or 0, pitch = cp.signal_value_is_pitch and 1 or 0,
    stop = cp.stop_playing_sounds and 1 or 0,
    al = { show = a.show_alert and 1 or 0, map = a.show_on_map and 1 or 0,
      icon = circuit_settings.signal_out(a.icon_signal_id), msg = a.alert_message or "" },
    il = {},
  }
  for _, inst in ipairs(e.prototype.instruments or {}) do
    info.il[#info.il + 1] = { inst.name, inst.notes or {} }
  end
  return info
end

-- How much of the burning fuel item is left, in thousandths (Factorio's red bar beside a burner's
-- fuel slot); nil without a burner.
function M.burner_left(e)
  local ok, burner = pcall(function() return e.burner end)
  if not (ok and burner) then
    return nil
  end
  local cur = burner.currently_burning
  if not cur then
    return 0
  end
  local proto = cur.name
  if type(proto) == "string" then
    proto = prototypes.item[proto]
  end
  local value = proto and proto.fuel_value or 0
  if value <= 0 then
    return 0
  end
  return math.max(0, math.min(1000, math.floor(burner.remaining_burning_fuel / value * 1000 + 0.5)))
end

local function t_art(e)
  return e.type == "artillery-turret" or e.type == "artillery-wagon"
end

-- gui.veh: {grid (0/1: it has an equipment grid), lbl (a spidertron's name), at = [without
-- gunner, with gunner] (0/1, a spidertron's auto targeting)}.
function M.vehicle_info(e)
  local info = { grid = e.grid and 1 or 0 }
  if e.type == "spider-vehicle" then
    info.lbl = e.entity_label or ""
    local p = e.vehicle_automatic_targeting_parameters
    info.at = { p.auto_target_without_gunner and 1 or 0, p.auto_target_with_gunner and 1 or 0 }
  end
  return info
end

-- gui.pl: [fluid or "", amount, capacity] of the fluid segment the entity's first fluid box is in
-- (Factorio's "Pipeline contents"); nil without one.
function M.pipeline_info(e)
  if not e.has_fluid_segment(1) then
    return nil
  end
  local f = e.get_fluid_segment_fluid(1)
  return { f and f.name or "", f and math.floor(f.amount + 0.5) or 0, math.floor(e.get_fluid_segment_capacity(1) + 0.5) }
end

-- Adds the kind's own fields to a `gui` message.
function M.fill(msg, e, kind, inventories)
  local okb, left = pcall(M.burner_left, e)
  msg.bu = okb and left or nil
  if kind == "inserter" then
    local ok, info = pcall(inserter_info, e)
    msg.ins = ok and info or nil
  elseif kind == "splitter" then
    local ok, info = pcall(function()
      return { i = e.splitter_input_priority, o = e.splitter_output_priority, f = filter_name(e.splitter_filter) }
    end)
    msg.spl = ok and info or nil
  elseif kind == "switch" then
    local ok, on = pcall(function() return e.power_switch_state end)
    msg.sw = ok and (on and 1 or 0) or nil
  elseif kind == "silo" then
    local ok, parts = pcall(function() return { parts = e.rocket_parts, need = e.prototype.rocket_parts_required } end)
    msg.rk = ok and parts or nil
  elseif kind == "panel" then
    local ok, info = pcall(M.panel_info, e)
    msg.dp = ok and info or nil
  elseif kind == "turret" then
    local ok, info = pcall(M.targets_info, e)
    msg.tgt = ok and info or nil
  end
  if kind == "vehicle" then
    -- The guns, in their slots' order (each over its ammo slot).
    local okg, guns = pcall(function()
      local out = {}
      for i, g in ipairs(e.prototype.indexed_guns or {}) do
        out[i] = g.name
      end
      return out
    end)
    msg.guns = okg and guns or nil
    local okv, veh = pcall(M.vehicle_info, e)
    msg.veh = okv and veh or nil
  end
  if t_art(e) then
    local oka, on = pcall(function() return e.artillery_auto_targeting end)
    msg.art = oka and (on and 1 or 0) or nil
  end
  if PIPELINE[e.type] then
    local okp, pl = pcall(M.pipeline_info, e)
    msg.pl = okp and pl or nil
  end
  local t = e.type
  if t == "lamp" or t == "train-stop" or t == "locomotive" or t == "spider-vehicle" then
    local ok, col = pcall(function() return e.color or e.prototype.color end)
    msg.col = ok and col and M.color_out(col) or { 255, 255, 255 }
    if t == "lamp" then
      local oka, on = pcall(function() return e.always_on end)
      msg.ao = oka and (on and 1 or 0) or nil
    end
  elseif t == "programmable-speaker" then
    local ok, info = pcall(M.speaker_info, e)
    msg.spk = ok and info or nil
  elseif t == "pump" then
    local ok, f = pcall(function() return e.get_fluid_filter(1) end)
    if ok then
      msg.pf = f and f.name or ""
    end
  end
  -- A chest's or cargo wagon's limit bar: how many slots machines may use.
  if kind == "container" or kind == "train" then
    for _, pair in ipairs(inventories) do
      if pair[1] == "chest" or pair[1] == "cargo" then
        local ok, bar = pcall(function()
          return pair[2].supports_bar() and pair[2].get_bar() - 1 or nil
        end)
        if ok and bar then
          msg.bar = bar
        end
      end
    end
  end
end

---------------------------------------------------------------------------------------------
-- Commands on the open screen (screens.lua checks it is open and in reach)

-- {u, f?: [item or "", ...] (filters by slot), m?: "whitelist"|"blacklist", use?: 0/1, st?: stack size (0 default)}
function M.set_inserter(e, cmd)
  if type(cmd.f) == "table" then
    for i = 1, e.filter_slot_count do
      local name = cmd.f[i]
      if type(name) == "string" and name ~= "" and prototypes.item[name] then
        e.set_filter(i, name)
      else
        e.set_filter(i, nil)
      end
    end
  end
  if cmd.m == "whitelist" or cmd.m == "blacklist" then
    e.inserter_filter_mode = cmd.m
  end
  if cmd.use == 0 or cmd.use == 1 then
    e.use_filters = cmd.use == 1
  end
  if tonumber(cmd.st) then
    e.inserter_stack_size_override = math.max(0, math.floor(tonumber(cmd.st)))
  end
  if cmd.sp == "none" or cmd.sp == "fresh-first" or cmd.sp == "spoiled-first" then
    e.inserter_spoil_priority = cmd.sp
  end
end

local PRIORITIES = { left = true, none = true, right = true }

-- {u, i?, o?: "left"|"none"|"right", f?: item or "" (no filter)}
function M.set_splitter(e, cmd)
  if PRIORITIES[cmd.i] then
    e.splitter_input_priority = cmd.i
  end
  if PRIORITIES[cmd.o] then
    e.splitter_output_priority = cmd.o
  end
  if type(cmd.f) == "string" then
    if cmd.f ~= "" and prototypes.item[cmd.f] then
      e.splitter_filter = { name = cmd.f }
    else
      e.splitter_filter = nil
    end
  end
end

-- {u, n}: the chest's limit bar (n slots usable; the inventory size or more: no limit).
function M.set_bar(inventory, cmd)
  local n = math.floor(tonumber(cmd.n) or #inventory)
  inventory.set_bar(math.max(1, math.min(#inventory, n) + 1))
end

-- {u, on}
function M.set_switch(e, cmd)
  e.power_switch_state = cmd.on == 1
end

-- {u, text?, icon? ({type, name} or {}), show?, chart? (0/1), msgs? ([{text, icon, cond}, ...])}
function M.set_panel(e, cmd)
  if cmd.text ~= nil then
    e.display_panel_text = tostring(cmd.text or ""):sub(1, 500)
  end
  if type(cmd.icon) == "table" then
    e.display_panel_icon = circuit_settings.signal_in(cmd.icon)
  end
  if cmd.show == 0 or cmd.show == 1 then
    e.display_panel_always_show = cmd.show == 1
  end
  if cmd.chart == 0 or cmd.chart == 1 then
    e.display_panel_show_in_chart = cmd.chart == 1
  end
  if type(cmd.msgs) == "table" then
    local records = {}
    for _, m in ipairs(cmd.msgs) do
      if type(m) == "table" then
        local r = { text = tostring(m.text or ""):sub(1, 500), condition = circuit_settings.condition_in(m.cond) }
        r.icon = circuit_settings.signal_in(m.icon)
        records[#records + 1] = r
      end
    end
    e.get_or_create_control_behavior().records = records
  end
end

-- {u, ao (0/1)}: a lamp's "Always on".
function M.set_lamp(e, cmd)
  if cmd.ao == 0 or cmd.ao == 1 then
    e.always_on = cmd.ao == 1
  end
end

-- {u, text}: a combinator's description.
function M.set_desc(e, cmd)
  e.combinator_description = tostring(cmd.text or ""):sub(1, 2000)
end

-- {u, c = [r, g, b]}: a lamp's, train stop's or locomotive's colour.
function M.set_color(e, cmd)
  local c = color_in(cmd.c)
  if c then
    e.color = c
  end
end

-- {u, lbl? (a spidertron's name), wo?, wi? (0/1: auto targeting without / with a gunner)}
function M.set_vehicle(e, cmd)
  if type(cmd.lbl) == "string" and e.type == "spider-vehicle" then
    e.entity_label = cmd.lbl:sub(1, 200)
  end
  if (cmd.wo == 0 or cmd.wo == 1 or cmd.wi == 0 or cmd.wi == 1) and e.type == "spider-vehicle" then
    local p = e.vehicle_automatic_targeting_parameters
    if cmd.wo == 0 or cmd.wo == 1 then
      p.auto_target_without_gunner = cmd.wo == 1
    end
    if cmd.wi == 0 or cmd.wi == 1 then
      p.auto_target_with_gunner = cmd.wi == 1
    end
    e.vehicle_automatic_targeting_parameters = p
  end
end

-- {u, on (0/1)}: an artillery turret's or wagon's auto targeting.
function M.set_artillery(e, cmd)
  e.artillery_auto_targeting = cmd.on == 1
end

-- {u, pipe (0/1)}: flush the open tank's or pipe's fluid (pipe 1: its whole fluid segment, as
-- Factorio's "Pipeline contents" button; else what the entity itself holds).
function M.flush(e, cmd)
  if cmd.pipe == 1 then
    e.clear_fluid_segment_fluid(1)
    return
  end
  local f = e.get_fluid(1)
  if f and f.amount > 0 then
    e.remove_fluid({ index = 1, amount = f.amount })
  end
end

local PLAYBACK = { ["local"] = true, surface = true, global = true }

-- {u, vol?, mode?, poly?, vctl?, vsig?, inst?, note?, pitch?, stop?, al? = {show?, map?, icon?, msg?}}
function M.set_speaker(e, cmd)
  local p = e.parameters
  if tonumber(cmd.vol) then
    p.playback_volume = math.max(0, math.min(1, tonumber(cmd.vol)))
  end
  if PLAYBACK[cmd.mode] then
    p.playback_mode = cmd.mode
  end
  if cmd.poly == 0 or cmd.poly == 1 then
    p.allow_polyphony = cmd.poly == 1
  end
  if cmd.vctl == 0 or cmd.vctl == 1 then
    p.volume_controlled_by_signal = cmd.vctl == 1
  end
  if type(cmd.vsig) == "table" then
    p.volume_signal_id = circuit_settings.signal_in(cmd.vsig)
  end
  e.parameters = p
  local b = e.get_or_create_control_behavior()
  local cp = b.circuit_parameters
  local inst = e.prototype.instruments or {}
  local want = tonumber(cmd.inst) and math.floor(tonumber(cmd.inst))
  if want and inst[want + 1] then
    if cp.instrument_id ~= want then
      cp.note_id = 0
    end
    cp.instrument_id = want
  end
  local current = inst[(cp.instrument_id or 0) + 1]
  local notes = current and current.notes or {}
  local note = tonumber(cmd.note) and math.floor(tonumber(cmd.note))
  if note and notes[note + 1] then
    cp.note_id = note
  end
  if cmd.pitch == 0 or cmd.pitch == 1 then
    cp.signal_value_is_pitch = cmd.pitch == 1
  end
  if cmd.stop == 0 or cmd.stop == 1 then
    cp.stop_playing_sounds = cmd.stop == 1
  end
  b.circuit_parameters = cp
  if type(cmd.al) == "table" then
    local a = e.alert_parameters
    if cmd.al.show == 0 or cmd.al.show == 1 then
      a.show_alert = cmd.al.show == 1
    end
    if cmd.al.map == 0 or cmd.al.map == 1 then
      a.show_on_map = cmd.al.map == 1
    end
    if type(cmd.al.icon) == "table" then
      a.icon_signal_id = circuit_settings.signal_in(cmd.al.icon)
    end
    if cmd.al.msg ~= nil then
      a.alert_message = tostring(cmd.al.msg):sub(1, 200)
    end
    e.alert_parameters = a
  end
end

-- {u, f}: a pump's fluid filter ("" none).
function M.set_pump(e, cmd)
  local name = tostring(cmd.f or "")
  if name ~= "" and prototypes.fluid[name] then
    e.set_fluid_filter(1, name)
  else
    e.set_fluid_filter(1)
  end
end

-- {u, l? = [entity names], ign? (0/1)}: a turret's priority targets.
function M.set_targets(e, cmd)
  if type(cmd.l) == "table" then
    local old = #(e.priority_targets or {})
    local n = 0
    for _, name in ipairs(cmd.l) do
      if type(name) == "string" and prototypes.entity[name] then
        n = n + 1
        e.set_priority_target(n, name)
      end
    end
    -- 2.1.23 wants the nil spelled out here ("Expected 2 arguments"); it clears that slot.
    for i = old, n + 1, -1 do
      e.set_priority_target(i, nil)
    end
  end
  if cmd.ign == 0 or cmd.ign == 1 then
    e.ignore_unprioritised_targets = cmd.ign == 1
  end
end

return M
