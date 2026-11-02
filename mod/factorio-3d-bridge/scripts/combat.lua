-- Combat: the character shoots while the client holds a key (the game aims and fires through
-- `shooting_state`, as for a player), its guns and ammo go to the client's HUD, and the client
-- hears about damaged entities near the camera (health bars) and deaths (effects).

local registry = require("scripts.registry")
local transport = require("scripts.transport")
local world = require("scripts.world")
local tracker = require("scripts.tracker")
local puppet = require("scripts.puppet")
local alerts = require("scripts.alerts")
local turrets = require("scripts.turrets")

local M = {}

local HOLD_TICKS = 30      -- a shoot command lasts this long unless the client repeats it
local FIRING_TICKS = 20    -- `me.sh` stays 1 this long after the ammo last went down
local HEALTH_INTERVAL = 10
local GUNS_INTERVAL = 10
local PAIRS_PER_MESSAGE = 400

-- Within the live-update square around the client's camera.
local function near_focus(entity)
  local s = storage.f3d
  if not s.client or entity.surface.index ~= s.surface_index then
    return false
  end
  local f, p = s.focus, entity.position
  return math.abs(p.x - f.x) <= f.r and math.abs(p.y - f.y) <= f.r
end

local function inventories(c)
  return c.get_inventory(defines.inventory.character_guns), c.get_inventory(defines.inventory.character_ammo)
end

local function selected_gun(c)
  local ok, i = pcall(function() return c.selected_gun_index end)
  return ok and i or nil
end

-- Bullets left with the selected gun: magazines and the rounds in the one in use. It only
-- matters that it goes down when the character fires.
local function ammo_left(c)
  local _, ammo = inventories(c)
  local i = selected_gun(c)
  if not (ammo and i and i >= 1 and i <= #ammo) then
    return 0
  end
  local stack = ammo[i]
  if not stack.valid_for_read then
    return 0
  end
  local ok, rounds = pcall(function() return stack.ammo end)
  return stack.count * 1000 + (ok and rounds or 0)
end

---------------------------------------------------------------------------------------------
-- Commands

-- m = 0 shoots at enemies near the character (Factorio's Space), 1 at the aim point (C), -1 stops.
function M.shoot(cmd)
  local s = storage.f3d
  local m = tonumber(cmd.m) or -1
  local x, y = tonumber(cmd.x), tonumber(cmd.y)
  if m < 0 or not x or not y then
    s.shooting = nil
    return
  end
  local sh = s.shooting or { fired_tick = -FIRING_TICKS }
  sh.selected = m == 1
  sh.x, sh.y = x / 256, y / 256
  sh.until_tick = game.tick + HOLD_TICKS
  s.shooting = sh
end

-- i: the gun slot to use (1-based). Empty slots are ignored.
function M.gun(cmd)
  local c = puppet.get()
  local i = math.floor(tonumber(cmd.i) or 0)
  local guns = c and inventories(c)
  if guns and i >= 1 and i <= #guns and guns[i].valid_for_read then
    pcall(function() c.selected_gun_index = i end)
    storage.f3d.guns_sig = nil
  end
end

---------------------------------------------------------------------------------------------
-- Events

function M.on_damaged(event)
  alerts.on_damaged(event)
  local e = event.entity
  turrets.on_hit(event)
  -- Damage cues are also used for creature blood, fire hits and ground scorch/fire marks.
  -- Keep these sparse and local; the client pools their sprite cards.
  if e.valid and near_focus(e) and (e.type == "unit" or e.type == "spider-unit" or e.type == "character") then
    local p = e.position
    local source = event.source
    local source_name = source and source.valid and source.name or ""
    local burning = source and source.valid and (source.type == "fire" or string.find(source_name, "flame", 1, true) ~= nil)
    local s = storage.f3d
    s.hit_fx_ticks = s.hit_fx_ticks or {}
    local hit_key = e.unit_number or ("character:" .. math.floor(p.x) .. ":" .. math.floor(p.y))
    if game.tick - (s.hit_fx_ticks[hit_key] or -3) >= 3 then
      s.hit_fx_ticks[hit_key] = game.tick
      transport.send_now({ t = "afx", fx = burning and "burn" or "blood", u = e.unit_number or 0,
        x = world.fixed(p.x), y = world.fixed(p.y) })
    end
  end
  if e.valid and e.unit_number and near_focus(e) then
    storage.f3d.damaged[e.unit_number] = e
  end
end

function M.on_died(event)
  alerts.on_died(event)
  local e = event.entity
  if e.type == "character" then
    puppet.on_died(e)
  end
  tracker.removed(e)
  if e.unit_number then
    storage.f3d.damaged[e.unit_number] = nil
    if storage.f3d.hit_fx_ticks then
      storage.f3d.hit_fx_ticks[e.unit_number] = nil
    end
    turrets.on_removed(e.unit_number)
  end
  if near_focus(e) then
    local p = e.position
    transport.send_now({
      t = "died",
      u = e.unit_number or 0,
      p = registry.entity_id(e.name),
      x = world.fixed(p.x),
      y = world.fixed(p.y),
    })
  end
end

function M.register()
  script.on_event(defines.events.on_entity_damaged, M.on_damaged)
  script.on_event(defines.events.on_entity_died, M.on_died)
end

---------------------------------------------------------------------------------------------

-- The damageable entity of another force closest to the aim point, within AIM_RADIUS tiles.
local AIM_RADIUS = 1.5
local function aim_target(c, x, y)
  local best, best_d
  for _, e in pairs(c.surface.find_entities_filtered({ position = { x, y }, radius = AIM_RADIUS })) do
    if e.valid and e ~= c and e.force ~= c.force and e.force.name ~= "neutral" and e.health then
      local p = e.position
      local d = (p.x - x) ^ 2 + (p.y - y) ^ 2
      if not best_d or d < best_d then
        best, best_d = e, d
      end
    end
  end
  return best
end

-- The selected gun's name and attack parameters (cached per gun: they come from prototypes).
local gun_params = {}
local function selected_gun_params(c)
  local guns = inventories(c)
  local i = selected_gun(c)
  local g = guns and i and i >= 1 and i <= #guns and guns[i]
  if not (g and g.valid_for_read) then
    return nil
  end
  local name = g.name
  if gun_params[name] == nil then
    local ok, ap = pcall(function() return g.prototype.attack_parameters end)
    gun_params[name] = ok and ap and { type = ap.type, range = ap.range or 15 } or false
  end
  return name, gun_params[name]
end

local function ammo_name(c)
  local _, ammo = inventories(c)
  local i = selected_gun(c)
  local stack = ammo and i and i >= 1 and i <= #ammo and ammo[i]
  return stack and stack.valid_for_read and stack.name or nil
end

-- Each shot the character fires (its ammo went down this tick), so the client can draw the
-- muzzle flash, casing and hit Factorio would: a headless server makes none of them (only when
-- visible). The target is the selected enemy, or the one nearest the character within the gun's
-- range, as the game picks for shooting_enemies. Flamethrowers fire every tick: their streams
-- come in `pj` instead.
local function send_shot(c, sh, state)
  local gun, params = selected_gun_params(c)
  if not gun or (params and params.type == "stream") then
    return
  end
  local target
  if state == defines.shooting.shooting_selected then
    local ok, sel = pcall(function() return c.selected end)
    target = ok and sel and sel.valid and sel.position
  end
  if not target then
    local enemy = c.surface.find_nearest_enemy({ position = c.position, max_distance = params and params.range or 15, force = c.force })
    target = enemy and enemy.position
  end
  target = target or { x = sh.x, y = sh.y }
  transport.send_now({ t = "shot", u = c.unit_number, g = gun, a = sh.ammo_name or ammo_name(c) or "",
    x = world.fixed(target.x), y = world.fixed(target.y) })
end

local function tick_shooting(c, s)
  local sh = s.shooting
  if sh and game.tick > sh.until_tick then
    s.shooting = nil
    sh = nil
  end
  if not sh then
    if s.shot then
      c.shooting_state = { state = defines.shooting.not_shooting, position = c.position }
      s.shot = nil
    end
    return
  end
  -- shooting_selected fires at the character's `selected` entity, which only a player sets, so
  -- select the enemy under the aim point ourselves (writable on a player-less character, checked
  -- in 2.1.23; in hybrid mode through the player if the character refuses, see /f3d-selftest).
  -- With nothing there, shoot at the nearest enemies instead.
  local state = defines.shooting.shooting_enemies
  if sh.selected then
    local target = aim_target(c, sh.x, sh.y)
    local player = target and puppet.player_of(c)
    if target and (pcall(function() c.selected = target end) or (player and pcall(function() player.selected = target end))) then
      state = defines.shooting.shooting_selected
    end
  end
  c.shooting_state = { state = state, position = { x = sh.x, y = sh.y } }
  s.shot = true
  local left = ammo_left(c)
  if left == 0 and not sh.warned then
    sh.warned = true
    puppet.message("Out of ammo")
  end
  if sh.ammo and left < sh.ammo then
    sh.fired_tick = game.tick
    send_shot(c, sh, state)
  end
  sh.ammo = left
  sh.ammo_name = ammo_name(c)
  sh.firing = game.tick - sh.fired_tick <= FIRING_TICKS
end

-- Rounds left in the magazine in use and the magazine's size (LuaItemStack.ammo,
-- LuaItemPrototype.magazine_size), for the ammo slot's green bar.
local function rounds_of(stack)
  local ok, rounds = pcall(function() return stack.ammo end)
  local ok2, size = pcall(function() return stack.prototype.magazine_size end)
  return ok and math.floor(rounds or 0) or 0, ok2 and math.floor(size or 0) or 0
end

-- [[gun, ammo, magazines, rounds, magazine size], ...] per gun slot ("" for empty), and the
-- selected slot.
local function send_guns(c, s)
  local guns, ammo = inventories(c)
  if not (guns and ammo) then
    return
  end
  local list, parts = {}, {}
  for i = 1, #guns do
    local g = guns[i]
    local a = i <= #ammo and ammo[i] or nil
    local rec = {
      g.valid_for_read and g.name or "",
      a and a.valid_for_read and a.name or "",
      a and a.valid_for_read and a.count or 0,
    }
    if a and a.valid_for_read then
      rec[4], rec[5] = rounds_of(a)
    else
      rec[4], rec[5] = 0, 0
    end
    list[i] = rec
    parts[i] = table.concat(rec, "/")
  end
  local sel = selected_gun(c) or 1
  local sig = sel .. ":" .. table.concat(parts, ",")
  if sig ~= s.guns_sig then
    s.guns_sig = sig
    transport.send_reliable({ t = "guns", sel = sel, l = list })
  end
end

-- Every damaged entity near the camera with its health, as a full list each time; an entity
-- that healed, died or left the area drops out.
local function send_health(s)
  local flat = {}
  for unit, e in pairs(s.damaged) do
    local ratio = e.valid and near_focus(e) and e.get_health_ratio()
    if ratio and ratio < 1 then
      flat[#flat + 1] = unit
      flat[#flat + 1] = math.floor(ratio * 1000 + 0.5)
    else
      s.damaged[unit] = nil
    end
  end
  local per = PAIRS_PER_MESSAGE * 2
  local parts = math.max(1, math.ceil(#flat / per))
  for part = 1, parts do
    local slice = {}
    for i = (part - 1) * per + 1, math.min(part * per, #flat) do
      slice[#slice + 1] = flat[i]
    end
    transport.send_now({ t = "hp", part = part, parts = parts, l = slice })
  end
end

function M.tick()
  local s = storage.f3d
  local c = puppet.get()
  if c then
    tick_shooting(c, s)
    if game.tick % GUNS_INTERVAL == 0 then
      send_guns(c, s)
    end
  end
  if game.tick % HEALTH_INTERVAL == 0 then
    send_health(s)
  end
end

-- After a handshake or when the client leaves.
function M.reset()
  local s = storage.f3d
  s.shooting = nil
  s.guns_sig = nil
  s.damaged = {}
  local c = s.puppet
  if s.shot and c and c.valid then
    c.shooting_state = { state = defines.shooting.not_shooting, position = c.position }
  end
  s.shot = nil
end

return M
