-- The logistic network: what logistic chests and roboports show in their screens (mode, requests,
-- a storage chest's filter, the network's robots and contents), the character's own logistic
-- requests (`clog`), the network the character stands in (`ln`) and what robots near the focus
-- carry (`rc`). 2.x keeps requests in logistic sections: section 1 is the one the client edits.

local registry = require("scripts.registry")
local transport = require("scripts.transport")
local world = require("scripts.world")
local puppet = require("scripts.puppet")
local space = require("scripts.space")
local rate = require("scripts.rate")

local M = {}

local NETWORK_INTERVAL = 60
local CHARACTER_INTERVAL = 30
local CARGO_INTERVAL = 10
local MAX_ITEMS = 200       -- network contents listed in a screen
local MAX_ROBOTS = 2000
local NO_MAX = -1

local ROBOT_TYPES = { "logistic-robot", "construction-robot" }

---------------------------------------------------------------------------------------------
-- Requests as plain data: [[item, min, max (-1 for none), quality?], ...]

-- `owner` has sections (LuaLogisticSections or LuaLogisticPoint). A save's requests are often in
-- several sections, and in groups shared between characters and chests ("Main" in one tested
-- save), so every active section counts, not only section 1.
local function active_sections(owner)
  local ok, sections = pcall(function() return owner.sections end)
  local out = {}
  if ok and sections then
    for _, section in pairs(sections) do
      local ok2, active = pcall(function() return section.active end)
      if not ok2 or active ~= false then
        out[#out + 1] = section
      end
    end
    return out
  end
  -- Older fakes and builds: only get_section.
  local ok3, first = pcall(function() return owner.get_section(1) end)
  if ok3 and first then
    out[1] = first
  end
  return out
end

local function item_filter(f)
  local v = f.value
  return v and v.name and (v.type == nil or v.type == "item") and v or nil
end

local function key_of(name, quality)
  return name .. "/" .. ((quality and quality ~= "") and quality or "normal")
end

local function requests_of(owner)
  local out = {}
  for _, section in ipairs(active_sections(owner)) do
    for _, f in pairs(section.filters or {}) do
      local v = item_filter(f)
      if v then
        local rec = { v.name, f.min or 0, f.max or NO_MAX }
        if v.quality and v.quality ~= "normal" then
          rec[4] = v.quality
        end
        out[#out + 1] = rec
      end
    end
  end
  return out
end

local function filter_of(r)
  local f = {
    value = { type = "item", name = r[1], quality = type(r[4]) == "string" and r[4] or "normal", comparator = "=" },
    min = math.max(0, math.floor(tonumber(r[2]) or 0)),
  }
  local max = math.floor(tonumber(r[3]) or NO_MAX)
  if max >= 0 then
    f.max = math.max(max, f.min)
  end
  return f
end

-- The client sends the whole list it shows (every active section's requests). Each section keeps
-- its own: requests still listed get the new amounts in the section they are in, ones no longer
-- listed leave it, and new ones go into the first section that isn't a shared group (one is made
-- when there is none). Other sections' filters that aren't items (signals) stay as they are.
local function write_requests(owner, list)
  local wanted, order = {}, {}
  for _, r in ipairs(list) do
    if type(r) == "table" and type(r[1]) == "string" and prototypes.item[r[1]] then
      local k = key_of(r[1], r[4])
      if not wanted[k] then
        order[#order + 1] = k
      end
      wanted[k] = filter_of(r)
    end
  end
  local placed, target = {}, nil
  for _, section in ipairs(active_sections(owner)) do
    local filters, changed = {}, false
    for _, f in pairs(section.filters or {}) do
      local v = item_filter(f)
      if v then
        local k = key_of(v.name, v.quality)
        local w = wanted[k]
        if w and not placed[k] then
          placed[k] = true
          filters[#filters + 1] = w
          changed = changed or w.min ~= (f.min or 0) or w.max ~= f.max
        else
          changed = true
        end
      else
        filters[#filters + 1] = f
      end
    end
    local ok, group = pcall(function() return section.group end)
    if not target and not (ok and group and group ~= "") then
      target = { section = section, filters = filters }
    end
    if changed then
      section.filters = filters
    end
  end
  local new = {}
  for _, k in ipairs(order) do
    if not placed[k] then
      new[#new + 1] = wanted[k]
    end
  end
  if #new == 0 then
    return
  end
  if not target then
    local section = owner.add_section()
    target = { section = section, filters = {} }
  end
  for _, f in ipairs(new) do
    target.filters[#target.filters + 1] = f
  end
  target.section.filters = target.filters
end

---------------------------------------------------------------------------------------------
-- Networks

-- {id, log = [available, all], con = [available, all], items?}: a network's robots and, with
-- items, what is in its storage and provider chests (most first).
local function summary(net, with_items)
  if not (net and net.valid) then
    return nil
  end
  local out = {
    id = net.network_id,
    log = { net.available_logistic_robots, net.all_logistic_robots },
    con = { net.available_construction_robots, net.all_construction_robots },
  }
  if with_items then
    local items = {}
    for _, entry in pairs(net.get_contents()) do
      local rec = { entry.name, entry.count }
      if entry.quality and entry.quality ~= "normal" then
        rec[3] = entry.quality
      end
      items[#items + 1] = rec
    end
    table.sort(items, function(a, b)
      if a[2] ~= b[2] then
        return a[2] > b[2]
      end
      return a[1] < b[1]
    end)
    for i = MAX_ITEMS + 1, #items do
      items[i] = nil
    end
    out.items = items
  end
  return out
end

local function logistic_mode(e)
  if e.type == "roboport" then
    return "roboport"
  end
  if e.type ~= "logistic-container" then
    return nil
  end
  local ok, mode = pcall(function() return e.prototype.logistic_mode end)
  return ok and mode or nil
end

function M.is_roboport(e)
  return e.type == "roboport"
end

-- For machine screens: {mode, requests?, filter?, net?} for logistic chests and roboports, else nil.
function M.screen_info(e)
  local mode = logistic_mode(e)
  if not mode then
    return nil
  end
  local info = { mode = mode }
  if mode == "requester" or mode == "buffer" then
    local sections = e.get_logistic_sections()
    info.requests = sections and requests_of(sections) or {}
  elseif mode == "storage" then
    -- 2.1 returns {name = LuaItemPrototype, quality = LuaQualityPrototype}, not names.
    local ok, filter = pcall(function() return e.get_filter(1) end)
    local name = ok and filter and filter.name
    if name and type(name) ~= "string" then
      name = name.name
    end
    info.filter = name or ""
  end
  local ok, net = pcall(function() return e.logistic_network end)
  info.net = ok and summary(net, true) or nil
  return info
end

-- {l: requests}: a requester or buffer chest's requests (section 1).
function M.set_requests(e, cmd)
  local mode = logistic_mode(e)
  if not (mode == "requester" or mode == "buffer") or type(cmd.l) ~= "table" then
    return puppet.message("That chest doesn't take requests")
  end
  local ok, err = pcall(write_requests, e.get_logistic_sections(), cmd.l)
  if not ok then
    puppet.message("Can't set the requests: " .. tostring(err))
  end
end

-- {item ("" clears)}: what a storage chest takes.
function M.set_storage_filter(e, cmd)
  if logistic_mode(e) ~= "storage" then
    return puppet.message("That isn't a storage chest")
  end
  local item = tostring(cmd.item or "")
  if item == "" then
    e.set_filter(1)
  elseif prototypes.item[item] then
    e.set_filter(1, item)
  end
end

---------------------------------------------------------------------------------------------
-- The character's logistics

-- {on, trash, l, sec, lgs}: whether its requests are active, whether unrequested items go to the
-- trash, its requests (every active section's), its logistic sections one by one (space.lua's
-- form: group, on, multiplier, filters) and the force's logistic group names; nil without a
-- requester point, which a character only has once its force has character_logistic_requests
-- (the logistic robotics research).
local function character_state(c)
  local ok, point = pcall(function() return c.get_requester_point() end)
  if not (ok and point) then
    return nil
  end
  local ok2, sec = pcall(space.sections_list, point)
  local ok3, groups = pcall(function() return c.force.get_logistic_groups() end)
  return { on = point.enabled and 1 or 0, trash = point.trash_not_requested and 1 or 0, l = requests_of(point),
    sec = ok2 and sec or nil, lgs = ok3 and groups or nil }
end

local function signature(state)
  local parts = { state.on, state.trash }
  for _, r in ipairs(state.l) do
    parts[#parts + 1] = table.concat(r, ":")
  end
  for _, sec in ipairs(state.sec or {}) do
    parts[#parts + 1] = table.concat({ sec.i, sec.g, sec.on, sec.m, sec.man, #sec.f }, "/")
    for _, f in ipairs(sec.f) do
      parts[#parts + 1] = table.concat(f, ":")
    end
  end
  parts[#parts + 1] = table.concat(state.lgs or {}, "|")
  return table.concat(parts, ",")
end

local function send_character(c, force)
  local s = storage.f3d
  local state = c and character_state(c)
  if not state then
    return
  end
  local sig = signature(state)
  if force or sig ~= s.clog_sig then
    s.clog_sig = sig
    transport.send_reliable({ t = "clog", on = state.on, trash = state.trash, l = state.l, sec = state.sec, lgs = state.lgs })
  end
end

-- set_section with u = 0: the character's own logistic sections (add, delete, group, on/off,
-- multiplier, filters), as the hub's and chests' are edited.
function M.set_char_section(cmd)
  local c = puppet.get()
  local ok, point = pcall(function() return c and c.get_requester_point() end)
  if not (ok and point) then
    return puppet.message("No logistic requests yet (research them first)")
  end
  local ok2, err = pcall(space.write_section, point, cmd)
  if not ok2 then
    puppet.message("Can't change that section: " .. tostring(err))
  end
  send_character(c, false)
end

-- {c = [r, g, b]}: the character's colour, and its player's (and chat colour) when a player
-- plays it.
function M.set_char_color(cmd)
  local c = puppet.get()
  local col = cmd.c
  if not (c and type(col) == "table" and #col >= 3) then
    return
  end
  local color = {}
  for i, k in ipairs({ "r", "g", "b" }) do
    color[k] = math.max(0, math.min(255, tonumber(col[i]) or 0)) / 255
  end
  color.a = 1
  local ok, err = pcall(function() c.color = color end)
  if not ok then
    return puppet.message("Can't set the colour: " .. tostring(err))
  end
  local okp, p = pcall(function() return c.player end)
  if okp and p then
    pcall(function()
      p.color = color
      p.chat_color = color
    end)
  end
  M.send_color(c, true)
end

-- `ccol`: the character's colour as [r, g, b] in 0-255, when it changes.
function M.send_color(c, force)
  if not c then
    return
  end
  local ok, col = pcall(function() return c.color end)
  if not (ok and col) then
    return
  end
  local rgb = { math.floor((col.r or 0) * 255 + 0.5), math.floor((col.g or 0) * 255 + 0.5), math.floor((col.b or 0) * 255 + 0.5) }
  local sig = table.concat(rgb, ",")
  local s = storage.f3d
  if force or sig ~= s.ccol_sig then
    s.ccol_sig = sig
    transport.send_reliable({ t = "ccol", c = rgb })
  end
end

-- {l?, on?, trash?}: the character's requests, whether they are on, and auto-trash.
function M.set_char_requests(cmd)
  local c = puppet.get()
  local ok, point = pcall(function() return c and c.get_requester_point() end)
  if not (ok and point) then
    return puppet.message("No logistic requests yet (research them first)")
  end
  local ok2, err = pcall(function()
    if type(cmd.l) == "table" then
      write_requests(point, cmd.l)
    end
    if cmd.on ~= nil then
      point.enabled = cmd.on == 1 or cmd.on == true
    end
    if cmd.trash ~= nil then
      point.trash_not_requested = cmd.trash == 1 or cmd.trash == true
    end
  end)
  if not ok2 then
    puppet.message("Can't set the requests: " .. tostring(err))
  end
  send_character(c, false)
end

---------------------------------------------------------------------------------------------

-- [unit, item id, count, ...] for robots near the focus that carry something.
local function robot_cargo(s, r)
  local flat = {}
  local types = {}
  for _, t in ipairs(ROBOT_TYPES) do
    if registry.is_mover(t) then
      types[#types + 1] = t
    end
  end
  if #types == 0 then
    return flat
  end
  local f = s.focus
  local index = defines.inventory.robot_cargo
  local found = world.surface().find_entities_filtered({
    area = { { f.x - r, f.y - r }, { f.x + r, f.y + r } }, type = types, limit = MAX_ROBOTS,
  })
  for _, robot in pairs(found) do
    local inventory = robot.get_inventory(index)
    local stack = inventory and inventory[1]
    if robot.unit_number and stack and stack.valid_for_read then
      flat[#flat + 1] = robot.unit_number
      flat[#flat + 1] = registry.item_id(stack.name)
      flat[#flat + 1] = stack.count
    end
  end
  return flat
end

function M.tick()
  local s = storage.f3d
  local c = puppet.get()
  if not c then
    return
  end
  local t = game.tick
  if t % CHARACTER_INTERVAL == 0 then
    send_character(c, false)
    M.send_color(c, false)
  end
  if t % NETWORK_INTERVAL == 0 then
    local ok, net = pcall(function() return c.force.find_logistic_network_by_position(c.position, c.surface) end)
    local info = ok and summary(net, false) or nil
    transport.send_now(info and { t = "ln", id = info.id, log = info.log, con = info.con } or { t = "ln", id = 0 })
  end
  if rate.due("rc", CARGO_INTERVAL) then
    local r = math.min(settings.global["f3d-detail-radius"].value, s.focus.r)
    if r > 0 then
      transport.send_now({ t = "rc", l = robot_cargo(s, r) })
    end
  end
end

---------------------------------------------------------------------------------------------
-- The logistic networks window (L): every network of the force

local function count(list)
  return list and #list or 0
end

-- {}: `lnets` with [[id, surface index, surface name, [log available, all], [con available, all],
-- cells, storages, providers, requesters, x, y, name], ...]; x, y is a roboport's position (the
-- first cell's), for looking at it.
function M.networks()
  local c = puppet.get()
  local force = c and c.force or game.forces.player
  local l = {}
  for surface_name, nets in pairs(force.logistic_networks or {}) do
    local surface = game.get_surface(surface_name)
    for _, net in pairs(nets) do
      if net.valid then
        local cells = net.cells
        local x, y = 0, 0
        local owner = cells[1] and cells[1].owner
        if owner and owner.valid then
          x, y = world.fixed(owner.position.x), world.fixed(owner.position.y)
        end
        local ok, name = pcall(function() return net.custom_name end)
        l[#l + 1] = {
          net.network_id, surface and surface.index or 0, surface_name,
          { net.available_logistic_robots, net.all_logistic_robots },
          { net.available_construction_robots, net.all_construction_robots },
          #cells, count(net.storages), count(net.providers), count(net.requesters), x, y, ok and name or "",
        }
      end
    end
  end
  table.sort(l, function(a, b) return a[1] < b[1] end)
  transport.send_now({ t = "lnets", l = l })
end

-- {id}: `lnet` with that network's contents ({id, log, con, items}, as in screens), or
-- `found = 0`.
function M.network(cmd)
  local c = puppet.get()
  local force = c and c.force or game.forces.player
  local id = math.floor(tonumber(cmd.id) or 0)
  for _, nets in pairs(force.logistic_networks or {}) do
    for _, net in pairs(nets) do
      if net.valid and net.network_id == id then
        local info = summary(net, true)
        info.t = "lnet"
        info.found = 1
        transport.send_now(info)
        return
      end
    end
  end
  transport.send_now({ t = "lnet", id = id, found = 0 })
end

-- After a handshake: the character's requests again.
function M.send_initial()
  storage.f3d.clog_sig = nil
  send_character(puppet.get(), true)
  M.send_color(puppet.get(), true)
end

return M
