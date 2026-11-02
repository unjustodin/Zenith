-- The character's inventories slot by slot, moving stacks between slots (its own, or an open
-- machine screen's), sorting, and a quickbar. Everything Factorio's inventory window needs; the
-- older `inv` message (totals) stays for old clients.
--
-- The quickbar lives in storage and changes only from client commands, so it is deterministic.
-- A player-less character has no quickbar of its own; this one outlives client restarts.

local transport = require("scripts.transport")
local puppet = require("scripts.puppet")
local screens = require("scripts.screens")

local M = {}

local SLOTS_INTERVAL = 30
local QUICKBAR_SIZE = 100 -- 10 pages of 10

-- Character inventories by role, with the defines.inventory name of each.
local ROLES = {
  { "main", "character_main" },
  { "guns", "character_guns" },
  { "ammo", "character_ammo" },
  { "armor", "character_armor" },
  { "trash", "character_trash" },
}

local function character_inventory(c, role)
  if role == "main" then
    return c.get_main_inventory()
  end
  for _, pair in ipairs(ROLES) do
    if pair[1] == role then
      local ok, index = pcall(function() return defines.inventory[pair[2]] end)
      return ok and index and c.get_inventory(index) or nil
    end
  end
  return nil
end

-- A character inventory, or the open machine screen's inventory with that role (chest, input...).
local function inventory_for(c, role, cmd)
  return character_inventory(c, role) or screens.inventory(role, cmd)
end

local function quality_of(stack)
  local ok, q = pcall(function() return stack.quality.name end)
  return ok and q or "normal"
end

local function same_item(a, b)
  return a.name == b.name and quality_of(a) == quality_of(b)
end

local function take_from(src, n)
  if n >= src.count then
    src.clear()
  else
    src.count = src.count - n
  end
end

-- Moves up to `n` from one stack into another (as much as fits), keeping the item's own data
-- (ammo, health, spoilage) where the game allows. LuaItemStack::transfer_stack takes an amount
-- in 2.x; if it doesn't, a part is moved by counts.
local function transfer(dst, src, n)
  if n >= src.count then
    dst.transfer_stack(src)
    return
  end
  if pcall(function() dst.transfer_stack(src, n) end) then
    return
  end
  if dst.valid_for_read then
    local room = math.min(n, dst.prototype.stack_size - dst.count)
    if room > 0 then
      dst.count = dst.count + room
      take_from(src, room)
    end
  elseif dst.set_stack({ name = src.name, count = n, quality = quality_of(src) }) then
    take_from(src, n)
  end
end

---------------------------------------------------------------------------------------------
-- State sent to the client

local function signature(lists)
  local parts = {}
  for role, list in pairs(lists) do
    local slots = {}
    for i, slot in ipairs(list) do
      slots[i] = slot == 0 and "" or table.concat(slot, "/")
    end
    parts[#parts + 1] = role .. "=" .. table.concat(slots, ",")
  end
  table.sort(parts)
  return table.concat(parts, ";")
end

-- The main inventory's slot filters (Factorio's middle click): [[slot, item], ...].
local function filter_list(inventory)
  local out = {}
  local ok, supports = pcall(function() return inventory.supports_filters() end)
  if not (ok and supports) then
    return out
  end
  for i = 1, #inventory do
    local f = inventory.get_filter(i)
    local name = type(f) == "table" and f.name or f
    if type(name) == "table" then
      name = name.name
    end
    if type(name) == "string" then
      out[#out + 1] = { i, name }
    end
  end
  return out
end

local PLANNERS = { blueprint = true, ["blueprint-book"] = true, ["deconstruction-planner"] = true, ["upgrade-planner"] = true }

-- The icons the player gave each blueprint, book and planner in the main inventory, which Factorio
-- draws over the item: [[slot, [[type, name], ...]], ...] in their order, and a signature of them.
local function planner_icons(inventory)
  local out, sig = {}, {}
  for i = 1, #inventory do
    local stack = inventory[i]
    if stack.valid_for_read and PLANNERS[stack.name] then
      local ok, icons = pcall(function() return stack.preview_icons end)
      local list = {}
      for _, icon in pairs(ok and icons or {}) do
        local signal = icon.signal or {}
        if signal.name then
          list[#list + 1] = { icon.index or #list + 1, signal.type or "item", signal.name }
        end
      end
      table.sort(list, function(a, b) return a[1] < b[1] end)
      if #list > 0 then
        local pairs_ = {}
        for j, l in ipairs(list) do
          pairs_[j] = { l[2], l[3] }
          sig[#sig + 1] = i .. ":" .. l[2] .. ":" .. l[3]
        end
        out[#out + 1] = { i, pairs_ }
      end
    end
  end
  return out, table.concat(sig, ",")
end

local function send_slots(c, s)
  local lists = {}
  for _, pair in ipairs(ROLES) do
    local inventory = character_inventory(c, pair[1])
    if inventory then
      lists[pair[1]] = screens.slot_list(inventory)
    end
  end
  local main = character_inventory(c, "main")
  local filters = main and filter_list(main) or {}
  local fsig = {}
  for i, f in ipairs(filters) do
    fsig[i] = f[1] .. "=" .. f[2]
  end
  local icons, isig = {}, ""
  if main then
    icons, isig = planner_icons(main)
  end
  local sig = signature(lists) .. "|" .. table.concat(fsig, ",") .. "|" .. isig
  if sig ~= s.slots_sig then
    s.slots_sig = sig
    local msg = { t = "slots", l = lists }
    if #filters > 0 then
      msg.fl = filters
    end
    if #icons > 0 then
      msg.ic = icons
    end
    transport.send_reliable(msg)
  end
end

-- The quickbar: 10 pages of 10. In single-player (hybrid mode) the character's player has a real
-- one, which the Factorio window shows too, so the bridge reads and writes that; for a player-less
-- character the bridge keeps its own in storage. The selected slot is the bridge's either way.
local function quickbar()
  local s = storage.f3d
  s.quickbar = s.quickbar or { page = 1, sel = 0, items = {} }
  return s.quickbar
end

-- The player whose quickbar this is: the one playing the character, or the one the bridge's
-- character stands in for on a server (their quickbar stays with them while they're away).
local function quickbar_player()
  local c = puppet.get()
  return c and (puppet.player_of(c) or puppet.held_for())
end

local function page_and_slot(i)
  return math.ceil(i / 10), (i - 1) % 10 + 1
end

-- The item in the player's slot i, or "" (empty, or something that isn't an item filter).
local function player_slot(p, i)
  local ok, slot = pcall(p.get_quick_bar_slot, page_and_slot(i))
  if not (ok and slot) then
    return ""
  end
  local ok2, name = pcall(function() return slot.filter and slot.filter.name end)
  return ok2 and name or ""
end

local function quickbar_state()
  local qb = quickbar()
  local p = quickbar_player()
  local list = {}
  for i = 1, QUICKBAR_SIZE do
    list[i] = p and player_slot(p, i) or (qb.items[i] or "")
  end
  local page = qb.page
  if p then
    local ok, active = pcall(p.get_active_quick_bar_page, 1)
    page = ok and active or page
  end
  return list, page
end

local function send_quickbar()
  local qb = quickbar()
  local list, page = quickbar_state()
  qb.sig = table.concat(list, ",") .. "|" .. page .. "|" .. qb.sel
  transport.send_reliable({ t = "qb", p = page, sel = qb.sel, held = list[qb.sel] or "", l = list })
end

-- Right after a command: the client sees the result on the next tick instead of within half a
-- second.
local function changed()
  local c = puppet.get()
  if c then
    send_slots(c, storage.f3d)
  end
  puppet.send_inventory_now()
  screens.refresh()
end

---------------------------------------------------------------------------------------------
-- Commands

-- Moves the stack in slot `fi` of inventory `from` to slot `ti` of inventory `to`, like clicking
-- in Factorio: into an empty slot or onto the same item (as much as fits), or swapping with a
-- different item. `n` moves only that many (0 or absent: the whole stack). Roles are the
-- character's (main, guns, ammo, armor, trash) or the open screen's (chest, input, output, fuel,
-- burnt, modules), which also need `u`.
function M.move(cmd)
  local c = puppet.get()
  if not c then
    return
  end
  local from = inventory_for(c, tostring(cmd.from or ""), cmd)
  local to = inventory_for(c, tostring(cmd.to or ""), cmd)
  local fi, ti = math.floor(tonumber(cmd.fi) or 0), math.floor(tonumber(cmd.ti) or 0)
  if not (from and to and fi >= 1 and fi <= #from and ti >= 1 and ti <= #to) then
    return
  end
  local src, dst = from[fi], to[ti]
  if not src.valid_for_read or (from == to and fi == ti) then
    return
  end
  local before = src.count
  local n = math.floor(tonumber(cmd.n) or 0)
  if n <= 0 or n > before then
    n = before
  end
  local moved
  if dst.valid_for_read and not same_item(src, dst) then
    moved = n == before and src.swap_stack(dst)
  else
    transfer(dst, src, n)
    moved = not src.valid_for_read or src.count < before
  end
  if not moved then
    puppet.message("Can't put that there")
  end
  changed()
end

-- Factorio's Shift and Ctrl clicks on a slot (LuaPlayer::stack_transfers' four actions): `k`
-- "stack" (Shift+click: this stack), "half" (Shift+right click: half of it), "all" (Ctrl+click:
-- every stack of the item, or of everything from an empty slot) or "allhalf" (Ctrl+right click:
-- half of each). They go to "the other inventory": from the character to the open screen's entity
-- (wherever the game puts it, like an inserter: fuel to fuel, ingredients to the input), from the
-- screen to the character, or with no screen open between the main inventory and the guns, ammo
-- and armour. With a player playing the character (hybrid mode) the game does it itself.
local XFER_ACTIONS = { stack = "stack_transfer", half = "stack_split", all = "inventory_transfer", allhalf = "inventory_split" }
local TOOLBELT = { gun = "guns", ammo = "ammo", armor = "armor" }

-- What Shift+right and Ctrl+right clicks move of a stack: the smaller half, the bigger one staying
-- (37 moves 18, as 2.1.23's stack_transfers does; the cursor's right click takes the bigger half).
local function half_of(n)
  return math.max(1, math.floor(n / 2))
end

-- Where a stack from the character goes with no screen open: the gun, ammo or armour slots for
-- those, back to the main inventory from them.
local function toolbelt_target(c, role, stack)
  if role ~= "main" then
    return character_inventory(c, "main")
  end
  local ok, kind = pcall(function() return stack.prototype.type end)
  local to = ok and TOOLBELT[kind]
  return to and character_inventory(c, to) or nil
end

function M.xfer(cmd)
  local c = puppet.get()
  local kind = tostring(cmd.k or "")
  local role = tostring(cmd.from or "")
  if not (c and XFER_ACTIONS[kind]) then
    return
  end
  local mine = character_inventory(c, role)
  local from = mine or screens.inventory(role, cmd)
  local fi = math.floor(tonumber(cmd.fi) or 0)
  if not (from and fi >= 1 and fi <= #from) then
    return
  end
  local e = cmd.u and screens.entity(cmd) or nil
  if not mine and not e then
    return
  end
  local p = puppet.player_of(c)
  if p then
    local ok, moved = pcall(function()
      return p.stack_transfers({ source_inventory = from, index = fi, target = (mine and e) or p,
        transfer_type = defines.inventory_actions[XFER_ACTIONS[kind]] })
    end)
    if ok then
      changed()
      return
    end
  end
  local first = from[fi]
  local slots = {}
  if kind == "stack" or kind == "half" then
    if first.valid_for_read then
      slots[1] = fi
    end
  else
    for i = 1, #from do
      local st = from[i]
      if st.valid_for_read and (not first.valid_for_read or same_item(st, first)) then
        slots[#slots + 1] = i
      end
    end
  end
  local moved = 0
  for _, i in ipairs(slots) do
    local st = from[i]
    local n = (kind == "half" or kind == "allhalf") and half_of(st.count) or st.count
    local dst = (mine and e) or (not mine and c) or nil
    local inserted = 0
    local before = st.count
    local ok = pcall(function()
      if dst then
        inserted = dst.insert(n == st.count and st or { name = st.name, count = n, quality = quality_of(st) })
      else
        local inv = toolbelt_target(c, role, st)
        inserted = inv and inv.insert(n == st.count and st or { name = st.name, count = n, quality = quality_of(st) }) or 0
      end
    end)
    if ok and inserted > 0 then
      -- Inserting a LuaItemStack itself (to keep its spoilage and the like) already takes the
      -- items out of it in 2.1.23; a table doesn't.
      if st.valid_for_read and st.count == before then
        take_from(st, inserted)
      end
      moved = moved + inserted
    end
  end
  if moved == 0 and #slots > 0 then
    puppet.message(mine and e and "Can't put that in there" or (mine and "Nowhere to put that" or "Inventory full"))
  end
  changed()
end

-- {i, item}: sets the filter of slot i of the character's main inventory ("" clears it), like
-- Factorio's middle click on a slot.
function M.set_filter(cmd)
  local c = puppet.get()
  local main = c and c.get_main_inventory()
  local i = math.floor(tonumber(cmd.i) or 0)
  if not (main and i >= 1 and i <= #main) then
    return
  end
  local item = tostring(cmd.item or "")
  local ok, set = pcall(function()
    if item == "" then
      return main.set_filter(i, nil)
    end
    return main.set_filter(i, item)
  end)
  if not (ok and set ~= false) then
    puppet.message("Can't filter that slot")
  end
  changed()
end

-- Sorts and merges an inventory: the character's main one, or the open chest.
function M.sort(cmd)
  local c = puppet.get()
  local inventory = c and inventory_for(c, tostring(cmd.inv or "main"), cmd)
  if inventory then
    inventory.sort_and_merge()
    changed()
  end
end

-- Puts an item in quickbar slot i (1-100), or clears it with "".
function M.qb_set(cmd)
  local qb = quickbar()
  local i = math.floor(tonumber(cmd.i) or 0)
  local item = tostring(cmd.item or "")
  if i < 1 or i > QUICKBAR_SIZE or (item ~= "" and not prototypes.item[item]) then
    return
  end
  local p = quickbar_player()
  if p then
    local page, slot = page_and_slot(i)
    -- The filter is required but may be nil (clears the slot).
    local ok, err = pcall(p.set_quick_bar_slot, page, slot, item ~= "" and item or nil)
    if not ok then
      puppet.message("Can't set the quickbar: " .. tostring(err))
    end
  else
    qb.items[i] = item ~= "" and item or nil
  end
  send_quickbar()
end

-- Selects a quickbar slot (0 for none); its item is what the character holds for building.
function M.qb_sel(cmd)
  local qb = quickbar()
  local i = math.floor(tonumber(cmd.i) or 0)
  if i >= 0 and i <= QUICKBAR_SIZE then
    qb.sel = i
    send_quickbar()
  end
end

-- Shows quickbar page p (1-10).
function M.qb_page(cmd)
  local qb = quickbar()
  local p = math.floor(tonumber(cmd.p) or 0)
  if p >= 1 and p <= QUICKBAR_SIZE / 10 then
    qb.page = p
    local player = quickbar_player()
    if player then
      pcall(player.set_active_quick_bar_page, 1, p)
    end
    send_quickbar()
  end
end

---------------------------------------------------------------------------------------------

function M.tick()
  local c = puppet.get()
  if c and game.tick % SLOTS_INTERVAL == 0 then
    send_slots(c, storage.f3d)
    -- In hybrid mode the player can change the quickbar in the Factorio window too.
    if quickbar_player() then
      local list, page = quickbar_state()
      local qb = quickbar()
      if table.concat(list, ",") .. "|" .. page .. "|" .. qb.sel ~= qb.sig then
        send_quickbar()
      end
    end
  end
end

-- After a handshake: everything again for the new client.
function M.send_initial()
  storage.f3d.slots_sig = nil
  local c = puppet.get()
  if c then
    send_slots(c, storage.f3d)
  end
  send_quickbar()
end

return M
