-- Factorio's world controls that a player gets from the game's own GUI and cursor, rebuilt for
-- the bridge's player-less character: dropping an item (Z), fast transfer (Ctrl+click), copying
-- and pasting entity settings (Shift+right/left click), flipping (H/V), the clipboard (Ctrl+C /
-- Ctrl+X / Ctrl+V, Alt+B), Alt-mode's icons, chat, and the statistics windows. A player keeps the
-- cursor stack, clipboard and statistics GUI state per player; here the client holds what it can
-- and the mod keeps the clipboard in a script inventory in `storage`.
--
-- Everything here runs from client commands and on_tick, so `storage` stays deterministic.

local registry = require("scripts.registry")
local transport = require("scripts.transport")
local world = require("scripts.world")
local puppet = require("scripts.puppet")
local tracker = require("scripts.tracker")
local screens = require("scripts.screens")
local map = require("scripts.map")
local history = require("scripts.history")

local M = {}

local ALT_INTERVAL = 60 -- Alt-mode icons once a second while it is on
local ALT_MAX = 400
local STATS_MAX = 60 -- items per statistics reply, most produced or consumed first
local CHAT_MAX = 500 -- characters

local function distance(a, b)
  local dx, dy = a.x - b.x, a.y - b.y
  return math.sqrt(dx * dx + dy * dy)
end

local function stack_size(name)
  local proto = prototypes.item[name]
  return proto and proto.stack_size or 1
end

-- Gives items to the character; what doesn't fit is spilled at its feet.
local function give(c, stack)
  local inserted = stack.count > 0 and c.insert(stack) or 0
  if inserted < stack.count then
    stack.count = stack.count - inserted
    pcall(function() c.surface.spill_item_stack({ position = c.position, stack = stack }) end)
  end
end

local function position_of(cmd)
  local fx, fy = tonumber(cmd.x), tonumber(cmd.y)
  if not fx or not fy then
    return nil
  end
  return { x = fx / 256, y = fy / 256 }
end

-- The entity a command names, if it is the character's force's.
local function target(c, cmd)
  local e = puppet.find_target(puppet.surface(c), cmd)
  if not (e and e.valid) then
    return nil
  end
  if e.force ~= c.force then
    puppet.message("That belongs to another force")
    return nil
  end
  return e
end

---------------------------------------------------------------------------------------------
-- Drop (Z)

-- {item, x, y}: one of the item from the main inventory into the entity at that spot if it takes
-- it (Factorio's Z over a machine or chest), else onto a belt or the ground there.
function M.drop(cmd)
  local c = puppet.get()
  local at = c and position_of(cmd)
  local item = tostring(cmd.item or "")
  if not (at and prototypes.item[item]) then
    return
  end
  local main = c.get_main_inventory()
  if not main or main.get_item_count(item) == 0 then
    return puppet.message("You have no " .. item)
  end
  if distance(c.position, at) > c.drop_item_distance + 0.5 then
    return puppet.message("Out of reach")
  end
  local stack = { name = item, count = 1 }
  for _, e in pairs(c.surface.find_entities_filtered({ position = at })) do
    if e.valid and e.unit_number and e.force == c.force and e ~= c then
      local ok, inserted = pcall(function()
        if e.can_insert(stack) then
          return e.insert(stack)
        end
        return 0
      end)
      if ok and inserted > 0 then
        main.remove(stack)
        puppet.send_inventory_now()
        return
      end
    end
  end
  main.remove(stack)
  c.surface.spill_item_stack({ position = at, stack = stack, allow_belts = true, max_radius = 0, use_start_position_on_failure = true })
  puppet.send_inventory_now()
end

---------------------------------------------------------------------------------------------
-- Fast transfer (Ctrl+click)

-- The inventories a fast transfer takes from, "whatever an inserter would take": a machine's
-- output and burnt fuel, else what it holds (a chest, a car's trunk, a wagon's cargo, a lab's
-- science packs).
local HOLDERS = { "chest", "car_trunk", "cargo_wagon", "spider_trunk", "lab_input" }

local function take_inventories(e)
  local out = {}
  for _, getter in ipairs({ "get_output_inventory", "get_burnt_result_inventory" }) do
    local ok, inv = pcall(function() return e[getter]() end)
    if ok and inv and #inv > 0 then
      out[#out + 1] = inv
    end
  end
  if #out == 0 then
    for _, name in ipairs(HOLDERS) do
      local ok, inv = pcall(function() return e.get_inventory(defines.inventory[name]) end)
      if ok and inv then
        out[#out + 1] = inv
        break
      end
    end
  end
  return out
end

local BELTS = { ["transport-belt"] = true, ["underground-belt"] = true, splitter = true }

-- Ctrl+click on a belt: its items into the character (half of each with `half`), or the held
-- stack onto it, as many as its lanes take.
local function belt_transfer(c, e, main, item, n, quality)
  local lines = e.get_max_transport_line_index()
  if item ~= "" then
    local moved = 0
    for i = 1, lines do
      local line = e.get_transport_line(i)
      while moved < n and line.can_insert_at_back() do
        if not line.insert_at_back({ name = item, count = 1, quality = quality }) then
          break
        end
        moved = moved + 1
      end
    end
    if moved == 0 then
      return puppet.message("No room on the belt")
    end
    main.remove({ name = item, count = moved, quality = quality })
    return
  end
  local moved = 0
  for i = 1, lines do
    local line = e.get_transport_line(i)
    for _, entry in pairs(line.get_contents()) do
      local stack = { name = entry.name, count = n > 0 and math.ceil(entry.count / 2) or entry.count, quality = entry.quality }
      local inserted = c.insert(stack)
      if inserted > 0 then
        stack.count = inserted
        line.remove_item(stack)
        moved = moved + inserted
      end
    end
  end
  if moved == 0 then
    puppet.message("Nothing to take")
  end
end

-- {u, p, x, y, item?, n?, q?, half}: with `item`, the held stack (`n` of it, else a full stack;
-- half of that with half = 1, in quality `q`) from the main inventory into the entity wherever
-- an inserter would put it; without, everything (half of each) out of its output or chest. On a
-- belt the items go on or come off its lanes.
function M.fast(cmd)
  local c = puppet.get()
  local e = c and target(c, cmd)
  if not e then
    return
  end
  if not puppet.can_reach(c, e) then
    return puppet.message("Out of reach")
  end
  local half = cmd.half == 1
  local main = c.get_main_inventory()
  if not main then
    return
  end
  local item = cmd.item and tostring(cmd.item) or ""
  local quality = type(cmd.q) == "string" and prototypes.quality[cmd.q] and cmd.q or "normal"
  if item ~= "" and not prototypes.item[item] then
    return
  end
  if BELTS[e.type] then
    local n = 0
    if item ~= "" then
      n = math.min(main.get_item_count({ name = item, quality = quality }), tonumber(cmd.n) or stack_size(item))
      n = half and math.ceil(n / 2) or n
      if n <= 0 then
        return puppet.message("You have no " .. item)
      end
    else
      n = half and 1 or 0
    end
    local ok, err = pcall(belt_transfer, c, e, main, item, n, quality)
    if not ok then
      log("[f3d] belt fast transfer: " .. tostring(err))
    end
    puppet.send_inventory_now()
    return
  end
  if item ~= "" then
    local have = main.get_item_count({ name = item, quality = quality })
    local n = math.min(have, math.max(1, math.floor(tonumber(cmd.n) or stack_size(item))))
    if half then
      n = math.ceil(n / 2)
    end
    if n <= 0 then
      return puppet.message("You have no " .. item)
    end
    local ok, inserted = pcall(function() return e.insert({ name = item, count = n, quality = quality }) end)
    if not ok or inserted == 0 then
      return puppet.message("Can't put " .. item .. " in there")
    end
    main.remove({ name = item, count = inserted, quality = quality })
  else
    local moved = 0
    for _, inv in ipairs(take_inventories(e)) do
      for _, entry in pairs(inv.get_contents()) do
        local n = half and math.ceil(entry.count / 2) or entry.count
        local stack = { name = entry.name, count = n, quality = entry.quality }
        local removed = inv.remove(stack)
        if removed > 0 then
          stack.count = removed
          local inserted = c.insert(stack)
          if inserted < removed then
            stack.count = removed - inserted
            inv.insert(stack)
          end
          moved = moved + inserted
        end
      end
    end
    if moved == 0 then
      return puppet.message("Nothing to take")
    end
  end
  puppet.send_inventory_now()
  screens.refresh()
end

---------------------------------------------------------------------------------------------
-- Entity settings (Shift+right click copies, Shift+left click pastes) and flipping (H / V)

-- {f = [u, p, x, y] (the source), u, p, x, y (the target)}: LuaEntity.copy_settings, which copies
-- recipes, filters, requests, combinator settings and the rest the game knows how to.
function M.paste_settings(cmd)
  local c = puppet.get()
  local f = cmd.f
  if not (c and type(f) == "table") then
    return
  end
  local source = target(c, { u = f[1], p = f[2], x = f[3], y = f[4] })
  local dest = target(c, cmd)
  if not (source and dest) then
    return puppet.message("Nothing to paste to")
  end
  local ok, removed = pcall(function() return dest.copy_settings(source) end)
  if not ok then
    return puppet.message("Can't paste those settings here")
  end
  -- Items the old settings held (an assembler's ingredients) come back to the character.
  for _, stack in pairs(removed or {}) do
    give(c, { name = stack.name, count = stack.count, quality = stack.quality })
  end
  tracker.changed(dest)
  screens.refresh()
end

-- {u, p, x, y, v}: flips an entity (2.x `mirroring`); a vertical flip also turns it half way.
function M.flip(cmd)
  local c = puppet.get()
  local e = c and target(c, cmd)
  if not e then
    return
  end
  local ok = pcall(function()
    local before = e.mirroring
    e.mirroring = not before
    -- Entities that can't be flipped (2.x flips fluid-box machines) keep their state.
    assert(e.mirroring ~= before, "not flippable")
    if cmd.v == 1 and e.rotatable then
      e.direction = (e.direction + 8) % 16
    end
  end)
  if not ok then
    return puppet.message("This can't be flipped")
  end
  tracker.changed(e)
end

---------------------------------------------------------------------------------------------
-- The clipboard (Ctrl+C, Ctrl+X, Ctrl+V) and blueprints from an area (Alt+B; `to`: into that
-- blueprint, the blueprint window's "Select new contents")

local function clipboard()
  local s = storage.f3d
  if not (s.clipboard and s.clipboard.valid) then
    s.clipboard = game.create_inventory(1)
  end
  return s.clipboard[1]
end

local function area_of(cmd)
  local x1, y1 = (tonumber(cmd.x1) or 0) / 256, (tonumber(cmd.y1) or 0) / 256
  local x2, y2 = (tonumber(cmd.x2) or 0) / 256, (tonumber(cmd.y2) or 0) / 256
  return { { math.min(x1, x2), math.min(y1, y2) }, { math.max(x1, x2), math.max(y1, y2) } }
end

-- The clipboard's entities for the client to draw while pasting: [[proto id, x, y, d], ...],
-- positions relative to the blueprint's centre in 1/256 tiles.
-- The blueprint keeps the copied entities at their map positions (2.1.23), so they are moved to
-- be around the middle of their footprints, where Factorio holds a blueprint at the cursor.
local function send_clip(bp)
  local l = {}
  local ok, entities = pcall(function() return bp.get_blueprint_entities() end)
  local x1, y1, x2, y2 = math.huge, math.huge, -math.huge, -math.huge
  for _, b in pairs(ok and entities or {}) do
    local id = registry.entity_id(b.name)
    if id > 0 then
      local proto = prototypes.entity[b.name]
      local w, h = proto.tile_width, proto.tile_height
      if (b.direction or 0) % 8 == 4 then
        w, h = h, w
      end
      x1, x2 = math.min(x1, b.position.x - w / 2), math.max(x2, b.position.x + w / 2)
      y1, y2 = math.min(y1, b.position.y - h / 2), math.max(y2, b.position.y + h / 2)
      l[#l + 1] = { id, b.position.x, b.position.y, b.direction or 0 }
    end
  end
  local cx, cy = (x1 + x2) / 2, (y1 + y2) / 2
  for _, e in ipairs(l) do
    e[2], e[3] = world.fixed(e[2] - cx), world.fixed(e[3] - cy)
  end
  transport.send_now({ t = "clip", l = l })
end

-- {x1, y1, x2, y2, cut, bp}: copies the area into the clipboard (cut = 1 also marks it for
-- deconstruction, as Factorio's cut does), or with bp = 1 makes a new blueprint of it in the main
-- inventory.
function M.copy(cmd)
  local c = puppet.get()
  if not c then
    return
  end
  local stack = clipboard()
  stack.set_stack({ name = "blueprint", count = 1 })
  local area = area_of(cmd)
  stack.create_blueprint({ surface = puppet.surface(c), force = c.force, area = area, include_modules = true,
    include_station_names = true, include_trains = true, include_fuel = true })
  if not stack.is_blueprint_setup() then
    stack.clear()
    transport.send_now({ t = "clip", l = {} })
    return puppet.message("Nothing to copy there")
  end
  if cmd.bp == 1 then
    local main = c.get_main_inventory()
    local slot, index
    local to = math.floor(tonumber(cmd.to) or 0)
    if to ~= 0 then
      -- Select new contents: into that blueprint (a main slot, or -1 the library one), keeping its
      -- name and description.
      slot, index = M.blueprint_stack and M.blueprint_stack(c, to), to
      if not (slot and slot.valid_for_read and slot.is_blueprint) then
        return puppet.message("That isn't a blueprint")
      end
      local label = slot.label
      local _, description = pcall(function() return slot.blueprint_description end)
      slot.set_stack(stack)
      slot.label = label
      pcall(function() slot.blueprint_description = description end)
      puppet.send_inventory_now()
      transport.send_reliable({ t = "bp_ok", q = 0, i = index, item = "blueprint", new = 1 })
      return puppet.message("Blueprint contents replaced")
    end
    if main then
      slot, index = main.find_empty_stack()
    end
    if not slot then
      return puppet.message("Inventory full")
    end
    slot.set_stack(stack)
    puppet.send_inventory_now()
    -- Its slot, so the client can open the blueprint's window as Factorio does after a selection.
    transport.send_reliable({ t = "bp_ok", q = 0, i = index or 0, item = "blueprint", new = 1 })
    return puppet.message("Blueprint added to the inventory")
  end
  send_clip(stack)
  if cmd.cut == 1 then
    tracker.deconstructing(puppet.surface(c), area, c.force, function()
      puppet.surface(c).deconstruct_area({ area = area, force = c.force })
    end)
  end
end

-- {x, y, d}: the clipboard's ghosts, centred there.
function M.paste(cmd)
  local c = puppet.get()
  local at = c and position_of(cmd)
  local s = storage.f3d
  if not at then
    return
  end
  local stack = s.clipboard and s.clipboard.valid and s.clipboard[1]
  if not (stack and stack.valid_for_read and stack.is_blueprint_setup()) then
    return puppet.message("The clipboard is empty")
  end
  if not map.check_charted(c, at) then
    return
  end
  local ghosts = history.place(c, stack, { at.x, at.y }, math.floor(tonumber(cmd.d) or 0) % 16,
    defines.build_mode.forced)
  if #ghosts == 0 then
    puppet.message("Nothing to place there")
  end
end

---------------------------------------------------------------------------------------------
-- Alt-mode (Alt): what each machine near the focus shows over itself

local function signal_name(f)
  if type(f) ~= "table" then
    return nil
  end
  local name = f.name
  if type(name) ~= "string" and name ~= nil then -- a prototype (LuaObjects aren't tables)
    local ok, n = pcall(function() return name.name end)
    name = ok and n or nil
  end
  return type(name) == "string" and name or nil
end

-- Every filter set on the entity, in slot order: Alt-mode shows them all, shrunk to fit.
local function filter_names(e)
  local names = {}
  local ok, n = pcall(function() return e.filter_slot_count end)
  for i = 1, ok and n or 0 do
    local ok_f, f = pcall(function() return e.get_filter(i) end)
    local name = ok_f and signal_name(f)
    if name then
      names[#names + 1] = name
    end
  end
  return names
end

-- [icon type, name, more?] for an entity's Alt-mode icon (more: the other filters' item names),
-- or nil.
local function alt_icon(e)
  local t = e.type
  if t == "assembling-machine" or t == "furnace" or t == "rocket-silo" then
    local ok, recipe = pcall(function() return e.get_recipe() end)
    -- An idle furnace's previous_recipe isn't shown: with no recipe Factorio shows nothing.
    if ok and recipe then
      return { "recipe", recipe.name }
    end
  elseif t == "inserter" or t == "loader" or t == "loader-1x1" then
    local names = filter_names(e)
    if #names > 0 then
      local first = table.remove(names, 1)
      return { "item", first, #names > 0 and names or nil }
    end
  elseif t == "splitter" or t == "lane-splitter" then
    local ok, f = pcall(function() return e.splitter_filter end)
    local name = ok and signal_name(f)
    if name then
      return { "item", name }
    end
  elseif t == "logistic-container" or t == "mining-drill" then
    local ok, f = pcall(function() return e.filter_slot_count > 0 and e.get_filter(1) end)
    local name = ok and signal_name(f)
    if name then
      return { "item", name }
    end
  end
  return nil
end

local ALT_TYPES = {
  "assembling-machine", "furnace", "rocket-silo", "inserter", "loader", "loader-1x1", "splitter",
  "lane-splitter", "logistic-container", "mining-drill",
}
local alt_types

-- {on}: Alt-mode on or off. While on, `ai` lists the icons near the focus once a second.
function M.alt(cmd)
  local s = storage.f3d
  s.alt = cmd.on == 1 or nil
  s.alt_due = game.tick
end

function M.tick()
  local s = storage.f3d
  if not s.alt or game.tick < (s.alt_due or 0) then
    return
  end
  s.alt_due = game.tick + ALT_INTERVAL
  if not alt_types then
    alt_types = {}
    for _, t in ipairs(ALT_TYPES) do
      for _, proto in pairs(prototypes.entity) do
        if proto.type == t then
          alt_types[#alt_types + 1] = t
          break
        end
      end
    end
  end
  local f = s.focus
  local l = {}
  local found = world.surface().find_entities_filtered({
    area = { { f.x - f.r, f.y - f.r }, { f.x + f.r, f.y + f.r } }, type = alt_types,
  })
  for _, e in pairs(found) do
    if #l >= ALT_MAX then
      break
    end
    local icon = e.unit_number and alt_icon(e)
    if icon then
      l[#l + 1] = { e.unit_number, icon[1], icon[2], icon[3] }
    end
  end
  transport.send_now({ t = "ai", l = l })
end

---------------------------------------------------------------------------------------------
-- Chat

-- {text}: says it in the game's chat, as the 3D client's character (it has no player name).
function M.chat(cmd)
  local text = tostring(cmd.text or ""):sub(1, CHAT_MAX)
  if text == "" then
    return
  end
  game.print({ "", "[color=0.6,0.8,1][3D][/color]: ", text })
  transport.send_now({ t = "chat", from = "3D", text = text })
end

-- What players type in the game's chat reaches the client, with the player's colour (Factorio
-- draws the name in it).
function M.on_console_chat(event)
  if not storage.f3d.client then
    return
  end
  local player = event.player_index and game.get_player(event.player_index)
  local msg = { t = "chat", from = player and player.name or "", text = tostring(event.message or "") }
  local ok, color = pcall(function() return player and player.chat_color end)
  if ok and color then
    msg.c = { math.floor((color.r or color[1] or 1) * 1000 + 0.5) / 1000, math.floor((color.g or color[2] or 1) * 1000 + 0.5) / 1000,
      math.floor((color.b or color[3] or 1) * 1000 + 0.5) / 1000 }
  end
  transport.send_now(msg)
end

---------------------------------------------------------------------------------------------
-- Statistics (P, K, and an electric pole's network)

local PRECISIONS = { "five_seconds", "one_minute", "ten_minutes", "one_hour", "ten_hours", "fifty_hours",
  "two_hundred_fifty_hours", "one_thousand_hours" }
local GRAPH_POINTS = 60 -- of the 300 samples each time scale keeps
local GRAPH_MAX = 8 -- lines

local function sum_over(flows, f)
  local total = 0
  for _, flow in ipairs(flows) do
    total = total + f(flow)
  end
  return total
end

-- [[name, in per minute, out per minute, in total, out total], ...] from flow statistics (summed
-- over several surfaces' when there are several), most first (by all-time totals when `by_total`:
-- Factorio's "All").
local function flow_rows(flows, precision, by_total)
  local names, rows = {}, {}
  for _, flow in ipairs(flows) do
    for name in pairs(flow.input_counts) do
      names[name] = true
    end
    for name in pairs(flow.output_counts) do
      names[name] = true
    end
  end
  for name in pairs(names) do
    local rate_in = sum_over(flows, function(f) return f.get_flow_count({ name = name, category = "input", precision_index = precision }) end)
    local rate_out = sum_over(flows, function(f) return f.get_flow_count({ name = name, category = "output", precision_index = precision }) end)
    rows[#rows + 1] = { name, rate_in, rate_out, sum_over(flows, function(f) return f.get_input_count(name) end),
      sum_over(flows, function(f) return f.get_output_count(name) end) }
  end
  table.sort(rows, function(a, b)
    local wa, wb = math.max(a[2], a[3]), math.max(b[2], b[3])
    if by_total then
      wa, wb = math.max(a[4], a[5]), math.max(b[4], b[5])
    end
    if wa ~= wb then
      return wa > wb
    end
    return a[1] < b[1]
  end)
  local out = {}
  for i = 1, math.min(#rows, STATS_MAX) do
    local r = rows[i]
    out[i] = { r[1], math.floor(r[2] * 100 + 0.5) / 100, math.floor(r[3] * 100 + 0.5) / 100, math.floor(r[4]), math.floor(r[5]) }
  end
  return out
end

-- [[name, [in...], [out...]], ...]: Factorio's graph lines, GRAPH_POINTS samples each, oldest first.
local function graph(flows, precision, names)
  local out = {}
  local step = math.floor(300 / GRAPH_POINTS)
  for i = 1, math.min(#names, GRAPH_MAX) do
    local name = names[i]
    local series = { {}, {} }
    -- A name the statistics don't know (or that isn't a prototype) gets no line.
    local ok = pcall(function()
      for c, category in ipairs({ "input", "output" }) do
        -- Each point averages the samples it stands for, oldest first.
        for p = GRAPH_POINTS, 1, -1 do
          local v = 0
          for k = 1, step do
            local sample = (p - 1) * step + k
            v = v + sum_over(flows, function(f)
              return f.get_flow_count({ name = name, category = category, precision_index = precision, sample_index = sample })
            end)
          end
          series[c][#series[c] + 1] = math.floor(v / step * 100 + 0.5) / 100
        end
      end
    end)
    if ok then
      out[#out + 1] = { name, series[1], series[2] }
    end
  end
  return out
end

-- An electric network's accumulators, Factorio's third panel: [[name, stored joules (averaged over
-- the time scale), stored joules now]], at most STATS_MAX. Statistics without storage give [].
local function storage_rows(flow, precision)
  local out = {}
  local ok, counts = pcall(function() return flow.storage_counts end)
  if not ok or type(counts) ~= "table" then
    return out
  end
  for name in pairs(counts) do
    local got, avg = pcall(function() return flow.get_flow_count({ name = name, category = "storage", precision_index = precision }) end)
    local now = flow.get_storage_count(name)
    out[#out + 1] = { name, got and math.floor(avg + 0.5) or 0, math.floor(now + 0.5) }
    if #out >= STATS_MAX then
      break
    end
  end
  return out
end

local SURFACE_STATS = {
  item = function(f, surface) return f.get_item_production_statistics(surface) end,
  fluid = function(f, surface) return f.get_fluid_production_statistics(surface) end,
  kill = function(f, surface) return f.get_kill_count_statistics(surface) end,
  build = function(f, surface) return f.get_entity_build_count_statistics(surface) end,
  pollution = function(_, surface) return game.get_pollution_statistics(surface) end,
}

-- The network's last update (LuaElectricNetwork.flow_last_tick, 2.1): what Factorio's three
-- summary bars show, in joules per tick: [consumption met, demand, production used, production
-- available, accumulators stored, accumulators' capacity]. nil where the API doesn't have it.
local function electric_flow(e)
  local ok, f = pcall(function()
    local net = e.electric_network
    if net and net.object_name == "LuaElectricSubNetwork" then
      net = net.parent_network
    end
    return net and net.flow_last_tick
  end)
  if not (ok and type(f) == "table") then
    return nil
  end
  local function n(v) return math.floor((tonumber(v) or 0) * 100 + 0.5) / 100 end
  local demand, avail = tonumber(f.maximum_consumption) or 0, tonumber(f.maximum_production) or 0
  return { n(demand * (tonumber(f.consumption_satisfaction) or 0)), n(demand),
    n(avail * (tonumber(f.production_satisfaction) or 0)), n(avail), n(f.accumulator_energy), n(f.accumulator_capacity) }
end

-- {kind ("item", "fluid", "kill", "build", "pollution", or "electric" with u, p, x, y of a pole),
-- prec (1-8, Factorio's time scales from 5 seconds to 1000 hours; 9 "All": the 1000 hour rates and
-- graph, rows chosen and ordered by all-time totals), si? (a surface index, 0 for all;
-- the character's by default), g? (names to draw graph lines for; [] for the busiest)}: `stats`
-- with the rows of that window.
function M.stats(cmd)
  local c = puppet.get()
  if not c then
    return
  end
  local kind = tostring(cmd.kind or "item")
  local prec = math.max(1, math.min(#PRECISIONS + 1, math.floor(tonumber(cmd.prec) or 2)))
  local precision = defines.flow_precision_index[PRECISIONS[math.min(prec, #PRECISIONS)]]
  local flows = {}
  local pole
  local si = c.surface.index
  if kind == "electric" then
    local e = target(c, cmd)
    pole = e
    local ok, stats = pcall(function() return e and e.electric_network_statistics end)
    if not (ok and stats) then
      return puppet.message("That isn't on an electric network")
    end
    flows[1] = stats
  elseif SURFACE_STATS[kind] then
    si = math.floor(tonumber(cmd.si) or si)
    for _, surface in pairs(game.surfaces) do
      if si == 0 or surface.index == si then
        flows[#flows + 1] = SURFACE_STATS[kind](c.force, surface)
      end
    end
  else
    return
  end
  local rows = flow_rows(flows, precision, prec > #PRECISIONS)
  local msg = { t = "stats", kind = kind, prec = prec, si = kind ~= "electric" and si or nil, l = rows }
  if kind == "electric" then
    msg.st = storage_rows(flows[1], precision)
    msg.ef = electric_flow(pole)
  end
  if type(cmd.g) == "table" then
    local names = {}
    for _, n in ipairs(cmd.g) do
      names[#names + 1] = tostring(n)
    end
    if #names == 0 then
      for i = 1, math.min(5, #rows) do
        names[i] = rows[i][1]
      end
    end
    msg.gr = graph(flows, precision, names)
  end
  transport.send_now(msg)
end

---------------------------------------------------------------------------------------------
-- Build cursor previews: entity prototype properties the client needs (reliable, at the handshake)

-- A MapPosition ({x, y} or {x = , y = }, both occur) rounded to hundredths.
local function vec(p)
  return { math.floor((p.x or p[1]) * 100 + 0.5) / 100, math.floor((p.y or p[2]) * 100 + 0.5) / 100 }
end

-- Fluid connections drawn as arrows on hover: [x, y (from the centre, facing north), direction the
-- pipe leaves by, "i" | "o" | "b" (input, output, both)] for ordinary connections, or nil.
local FLOWS = { input = "i", output = "o", ["input-output"] = "b" }
local NO_FLUID_ARROWS = { pipe = true, ["pipe-to-ground"] = true, ["infinity-pipe"] = true, ["storage-tank"] = true,
  valve = true, ["fluid-wagon"] = true }
local function fluid_connections(proto)
  if NO_FLUID_ARROWS[proto.type] then
    return nil
  end
  local ok, boxes = pcall(function() return proto.fluidbox_prototypes end)
  if not ok or not boxes then
    return nil
  end
  local out = {}
  for _, box in pairs(boxes) do
    for _, conn in pairs(box.pipe_connections or {}) do
      if conn.connection_type == "normal" and conn.positions and conn.positions[1] and not conn.hide_connection_info then
        local p = vec(conn.positions[1])
        out[#out + 1] = { p[1], p[2], conn.direction, FLOWS[conn.flow_direction] or "b" }
      end
    end
  end
  return #out > 0 and out or nil
end

-- What hover and the build cursor draw for a prototype besides its reach (`eprops`' fifth entry):
-- an inserter's pickup and drop vectors, a roboport's logistic and construction radius, a mining
-- drill's mining radius and where it drops, fluid connections. nil when none.
local function overlay(proto)
  local t = proto.type
  local x = {}
  if t == "inserter" then
    local ok, p, d = pcall(function() return proto.inserter_pickup_position, proto.inserter_drop_position end)
    if ok and p and d then
      x.ip, x.id = vec(p), vec(d)
    end
  elseif t == "roboport" then
    local ok, lr, cr = pcall(function() return proto.logistic_radius, proto.construction_radius end)
    if ok and lr then
      x.lr, x.cr = lr, cr or 0
    end
  elseif t == "mining-drill" then
    local ok, r, v = pcall(function() return proto.mining_drill_radius, proto.vector_to_place_result end)
    if ok and r then
      x.mr = math.floor(r * 100 + 0.5) / 100
      x.vp = v and vec(v) or nil
    end
  end
  x.fb = fluid_connections(proto)
  -- Wire tools: how far a circuit wire reaches from it (and a power switch's copper wire).
  local okc, cw = pcall(function() return proto.get_max_circuit_wire_distance() end)
  if okc and type(cw) == "number" and cw > 0 then
    x.cw = math.floor(cw * 10 + 0.5) / 10
  end
  if t == "power-switch" then
    local okw, ww = pcall(function() return proto.get_max_wire_distance() end)
    x.ww = okw and type(ww) == "number" and math.floor(ww * 10 + 0.5) / 10 or nil
  end
  -- Assemblers' and drills' pipe connections show only while their recipe (resource) needs fluid.
  local ok, off = pcall(function() return proto.fluid_boxes_off_when_no_fluid_recipe end)
  if x.fb and ((ok and off) or t == "mining-drill") then
    x.fo = 1
  end
  return next(x) and x or nil
end

-- `eprops`: [[proto id, underground belt or pipe-to-ground reach (tiles, 0 none), pole wire reach,
-- pole supply area (half side, tiles), overlay?], ...] for the prototypes that have any.
-- Prototypes only, so read once per load (7 ms on Space Age, every handshake).
local eprops_cache

function M.send_eprops(warm_only)
  if eprops_cache then
    if not warm_only then
      transport.send_reliable({ t = "eprops", l = eprops_cache })
    end
    return
  end
  local l = {}
  eprops_cache = l
  for name, proto in pairs(prototypes.entity) do
    local t = proto.type
    local extra = overlay(proto)
    if t == "underground-belt" or t == "pipe-to-ground" or t == "electric-pole" then
      local under, wire, supply = 0, 0, 0
      if t == "underground-belt" then
        local ok, d = pcall(function() return proto.max_underground_distance end)
        under = ok and d or 0
      elseif t == "pipe-to-ground" then
        local ok, d = pcall(function()
          local box = proto.fluidbox_prototypes[1]
          for _, conn in pairs(box.pipe_connections) do
            if conn.connection_type == "underground" then
              return conn.max_underground_distance
            end
          end
          return 0
        end)
        under = ok and d or 0
      else
        local ok, d = pcall(function() return proto.get_max_wire_distance() end)
        wire = ok and d or 0
        local ok2, a = pcall(function() return proto.get_supply_area_distance() end)
        supply = ok2 and a or 0
      end
      l[#l + 1] = { registry.entity_id(name), under or 0, math.floor((wire or 0) * 10 + 0.5) / 10, math.floor((supply or 0) * 10 + 0.5) / 10, extra }
    elseif extra then
      l[#l + 1] = { registry.entity_id(name), 0, 0, 0, extra }
    end
  end
  if not warm_only then
    transport.send_reliable({ t = "eprops", l = l })
  end
end

function M.reset()
  storage.f3d.alt = nil
end

return M
