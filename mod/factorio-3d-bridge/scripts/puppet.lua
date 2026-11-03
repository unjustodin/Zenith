-- The character the 3D client controls.
--
-- Single-player (hybrid mode): the player's own character, with the Factorio window still open.
-- Server (headless mode): a character the bridge creates and owns; nobody needs to be connected.

local registry = require("scripts.registry")
local transport = require("scripts.transport")
local world = require("scripts.world")
local tracker = require("scripts.tracker")
local takeover = require("scripts.takeover")

local M = {}

-- What a new freeplay player starts with.
local STARTER_KIT = {
  { name = "iron-plate", count = 8 },
  { name = "wood", count = 1 },
  { name = "pistol", count = 1 },
  { name = "firearm-magazine", count = 10 },
  { name = "burner-mining-drill", count = 1 },
  { name = "stone-furnace", count = 1 },
}

local HOLD_TICKS = 30      -- a walk, mine or pickup command lasts this long unless the client repeats it
local REACH_SLACK = 1.5    -- reach is measured to the entity's edge in-game; we measure to its centre
local PICKUP_SLACK = 0.5   -- the same for picking up items on the ground
local PICKUPS_PER_TICK = 2
local STATE_INTERVAL = 2
local INVENTORY_INTERVAL = 30
local RECIPES_INTERVAL = 600

local function message(text)
  transport.send_now({ t = "msg", text = text })
end
M.message = message

-- The player playing this character in single-player (hybrid mode), or nil for the bridge's own
-- player-less character on a server.
function M.player_of(c)
  local ok, p = pcall(function() return c.player end)
  return ok and p or nil
end

local function distance(a, b)
  local dx, dy = a.x - b.x, a.y - b.y
  return math.sqrt(dx * dx + dy * dy)
end

-- Walking supports 8 of the 16 directions: the even ones.
local function walk_direction(d)
  return (math.floor(d / 2 + 0.5) * 2) % 16
end

local function create_character(surface, near, force)
  local position = surface.find_non_colliding_position("character", near, 32, 0.5) or near
  return surface.create_entity({ name = "character", position = position, force = force })
end

-- The player whose character the bridge plays (see takeover.lua), deciding once per game.
function M.owner()
  local s = storage.f3d
  if s.extra then
    return nil -- a second client plays a character of its own (session.lua)
  end
  if not game.is_multiplayer() then
    return game.get_player(1) -- single-player (hybrid mode): always the player
  end
  if not s.owner_checked then
    s.owner_checked = true
    local p = takeover.choose(s)
    s.owner_index = p and p.index or nil
  end
  return s.owner_index and game.get_player(s.owner_index) or nil
end

-- Decide again who to play as (after /f3d-player, the setting, or a player joining or leaving).
function M.recheck(choose_again)
  local s = storage.f3d
  s.recheck = true
  if choose_again then
    s.owner_checked = nil
  end
end

-- The player whose things the bridge's own character holds while they are away, or nil.
function M.held_for()
  local s = storage.f3d
  return s.held_for and game.get_player(s.held_for) or nil
end

-- The character the client controls:
-- - the owner's own character while they are connected (single-player, hybrid mode, or a player
--   who joined the server with the real game); a stand-in's things move back onto it first;
-- - while the owner is away, the bridge's stand-in holding their things, where they were;
-- - with no owner (a new map), the bridge's own character with a starter kit, as before.
function M.get()
  local s = storage.f3d
  -- A save moving between a server and single-player decides again.
  local mp = game.is_multiplayer()
  if s.puppet and s.puppet.valid and (s.owner_checked or not mp) and not s.recheck and s.was_mp == mp then
    return s.puppet
  end
  s.recheck = nil
  s.was_mp = mp
  local owner = M.owner()
  local old = s.puppet and s.puppet.valid and s.puppet or nil
  s.puppet = nil

  if owner and owner.connected then
    local c = owner.character
    if not c and old and s.held_for == owner.index then
      s.puppet = old -- they have no character yet (dead, or still in the menu): keep standing in
      return old
    end
    -- A player joining a new map takes over the bridge's own character's things and place too,
    -- so swapping between the real game and the client carries on where the client was.
    if old and c and old ~= c and (s.held_for == owner.index or (not s.held_for and s.own_character == old)) then
      takeover.move_all(old, c, c)
      pcall(c.teleport, old.position, old.surface)
      pcall(old.destroy)
    end
    if c then
      s.held_for = nil
      s.own_character = nil
    end
    s.puppet = c -- nil while dead: wait for the respawn
    return s.puppet
  end

  if owner then
    if old and s.held_for == owner.index then
      s.puppet = old
      return old
    end
    if M.waiting_to_respawn() then
      return nil
    end
    -- Stand in for the owner where their character was (after a death: at the spawn).
    local surface = owner.physical_surface or game.get_surface(1)
    local at = owner.physical_position or { x = 0, y = 0 }
    surface, at = M.respawn_place(surface, at, owner.force)
    local c = create_character(surface, at, owner.force)
    if not c then
      s.puppet = old
      return old
    end
    takeover.move_all(owner, c, c)
    pcall(function() c.color = owner.color end)
    if old then
      local before = s.held_for and game.get_player(s.held_for)
      if before and not before.connected then
        takeover.move_all(old, before, old)
      end
      takeover.absorb(old, c)
    end
    s.held_for = owner.index
    s.puppet = c
    return c
  end

  -- No owner: the bridge's own character. Hand anything held for someone back first.
  if old and s.held_for then
    local before = game.get_player(s.held_for)
    if before and not before.connected then
      takeover.move_all(old, before, old)
    end
    s.held_for = nil
  end
  if old then
    s.puppet = old
    return old
  end
  if not game.is_multiplayer() then
    return nil
  end
  if M.waiting_to_respawn() then
    return nil
  end
  local surface = game.get_surface(settings.global["f3d-surface"].value) or game.get_surface(1)
  local force = game.forces.player
  local at = force.get_spawn_position(surface)
  surface, at = M.respawn_place(surface, at, force)
  local character = create_character(surface, at, force)
  if not character then
    return nil
  end
  if settings.global["f3d-starter-kit"].value then
    for _, stack in pairs(STARTER_KIT) do
      if prototypes.item[stack.name] then
        character.insert(stack)
      end
    end
  end
  s.own_character = character
  s.puppet = character
  return character
end

-- The surface a command works on: while the remote view shows another surface, what may be done
-- from there (ghosts, marks, rotating, settings: session.lua REMOTE_OK) goes to that surface, as
-- in Factorio's remote view; everything else to the character's own.
function M.surface(c)
  local si = storage.f3d.act_si
  local s = si and game.get_surface(si)
  if s and s.valid then
    return s
  end
  return c.surface
end

---------------------------------------------------------------------------------------------
-- Death and respawn
--
-- A player's character respawns by the game's own rules (LuaPlayer::ticks_to_respawn). The
-- bridge's own character (no player, or standing in for one who is away) has nobody to respawn
-- it, so the bridge does: after the character prototype's respawn time, at the force's spawn on
-- the planet it died on (Nauvis when it died on a space platform), as Factorio does for players.

local DEFAULT_RESPAWN_TICKS = 600
local DEAD_INTERVAL = 30

local function respawn_ticks(c)
  local ok, t = pcall(function() return c.prototype.respawn_time end)
  t = ok and tonumber(t) or nil
  if not t or t <= 0 then
    return DEFAULT_RESPAWN_TICKS
  end
  return t < 120 and math.floor(t * 60) or math.floor(t) -- seconds in data, ticks at runtime
end

-- on_entity_died (combat.lua): the character the client plays died.
function M.on_died(e)
  local s = storage.f3d
  if not (s.puppet and s.puppet.valid and s.puppet == e) then
    return
  end
  local surface = e.surface
  local ok, platform = pcall(function() return surface.platform end)
  if ok and platform then
    surface = game.get_surface(1)
  end
  s.mining, s.walk, s.pickup = nil, nil, nil
  local p = e.position
  s.death = { tick = game.tick, x = p.x, y = p.y, surface = e.surface.index }
  -- A connected player's character is respawned by the game; only the bridge's own waits here.
  if not M.player_of(e) then
    s.respawn = { tick = game.tick + respawn_ticks(e), surface = surface.index }
  end
end

-- True while the bridge's own character is dead and its respawn time hasn't run out.
function M.waiting_to_respawn()
  local r = storage.f3d.respawn
  return r ~= nil and game.tick < r.tick
end

-- Where a character the bridge creates goes: after a death the force's spawn on the planet it
-- died on (clearing the death), otherwise where it was asked to go.
function M.respawn_place(surface, at, force)
  local s = storage.f3d
  local r = s.respawn
  if not r then
    return surface, at
  end
  s.respawn = nil
  s.death = nil
  local there = game.get_surface(r.surface) or surface
  local ok, spawn = pcall(force.get_spawn_position, there)
  return there, ok and spawn or at
end

-- Ticks until the client's character respawns while it is dead, else nil; 0 means waiting for
-- the player to press Respawn (single-player).
function M.respawn_left()
  local s = storage.f3d
  if s.respawn then
    return math.max(0, s.respawn.tick - game.tick)
  end
  local owner = game.is_multiplayer() and M.owner() or game.get_player(1)
  if owner and owner.connected and not owner.character then
    local ok, left = pcall(function() return owner.ticks_to_respawn end)
    local ok2, controller = pcall(function() return owner.controller_type end)
    if ok and left then
      return left
    end
    if ok2 and controller == defines.controllers.ghost then
      return 0
    end
  end
  return nil
end

-- {t = "dead", left (ticks), x, y}: while the character is dead, every half second.
local function send_dead(s)
  local left = M.respawn_left()
  if not left then
    return
  end
  local msg = { t = "dead", left = left }
  if s.death then
    msg.x, msg.y = world.fixed(s.death.x), world.fixed(s.death.y)
  end
  transport.send_now(msg)
end

-- The client's Respawn button: a player waiting on it (single-player) respawns now; the bridge's
-- own character only once its time is up.
function M.respawn()
  local s = storage.f3d
  if s.respawn then
    if game.tick >= s.respawn.tick then
      M.get()
    end
    return
  end
  local owner = game.is_multiplayer() and M.owner() or game.get_player(1)
  if owner and owner.connected and not owner.character then
    local ok, left = pcall(function() return owner.ticks_to_respawn end)
    if not (ok and left and left > 0) then
      pcall(function() owner.ticks_to_respawn = nil end)
    end
  end
end

function M.reset()
  local s = storage.f3d
  s.walk = nil
  s.mining = nil
  s.pickup = nil
  s.inv_sig = nil
  s.recipes_sig = nil
  local c = s.puppet
  if c and c.valid then
    c.walking_state = { walking = false, direction = c.direction }
  end
end

-- Finds the entity the client clicked: by unit number when it has one, otherwise by
-- prototype and exact position (the same identity the client uses).
function M.find_target(surface, cmd)
  local fx, fy = tonumber(cmd.x), tonumber(cmd.y)
  if not fx or not fy then
    return nil
  end
  local x, y = fx / 256, fy / 256
  local unit = tonumber(cmd.u) or 0
  local name = registry.entity_name(tonumber(cmd.p) or 0)
  -- With a unit number the match is exact, so search wider: a train or car may have moved on
  -- from where the client saw it.
  local r = unit > 0 and 3 or 0.05
  local found = surface.find_entities_filtered({ area = { { x - r, y - r }, { x + r, y + r } } })
  for _, e in pairs(found) do
    if unit > 0 then
      if e.unit_number == unit then
        return e
      end
    elseif e.name == name and world.fixed(e.position.x) == fx and world.fixed(e.position.y) == fy then
      return e
    end
  end
  return nil
end

---------------------------------------------------------------------------------------------
-- Commands

-- `walk` with `a` (thousandths of a turn clockwise from north) walks at any angle.
-- Factorio's character walks only 8 ways, so each tick steps one of the two 8-way directions either
-- side of the angle, whichever brings the sideways drift accumulated so far (`err`, in steps) back
-- towards the line: the path zig-zags a few hundredths of a tile about the line while the game's own
-- collisions and speed stay as they are. Against a wall the blocked direction simply doesn't move,
-- so the character slides along it at the other direction's share.
function M.walk(cmd)
  local s = storage.f3d
  local d = tonumber(cmd.d)
  local a = tonumber(cmd.a)
  if a and a >= 0 and a < 1000 and (not d or d >= 0) then
    local w = s.walk
    local err = (w and w.angle and game.tick <= w.until_tick) and w.err or 0
    s.walk = { dir = w and w.dir or walk_direction(math.floor(a * 16 / 1000 + 0.5)), angle = math.floor(a),
      err = err, until_tick = game.tick + HOLD_TICKS }
  elseif d and d >= 0 then
    s.walk = { dir = walk_direction(d), until_tick = game.tick + HOLD_TICKS }
  elseif s.walk then
    s.walk.until_tick = 0
  end
end

local function can_hand_mine(c, e)
  if not (e.valid and e.minable) then
    return false, "Can't mine that"
  end
  if e.force ~= c.force and e.force.name ~= "neutral" then
    return false, "Can't mine that"
  end
  local props = e.prototype.mineable_properties
  if not props.minable then
    return false, "Can't mine that"
  end
  if e.type == "resource" then
    if props.required_fluid or e.prototype.infinite_resource then
      return false, "This needs a mining drill"
    end
    for _, product in pairs(props.products or {}) do
      if product.type ~= "item" then
        return false, "This needs a pump or drill"
      end
    end
  end
  local reach = (e.type == "resource") and c.resource_reach_distance or c.reach_distance
  if distance(c.position, e.position) > reach + REACH_SLACK then
    return false, "Out of reach"
  end
  return true
end

function M.mine(cmd)
  local s = storage.f3d
  local c = M.get()
  if not c then
    return
  end
  local e = M.find_target(c.surface, cmd)
  if not e then
    s.mining = nil
    return
  end
  if s.mining and s.mining.entity.valid and s.mining.entity == e then
    s.mining.until_tick = game.tick + HOLD_TICKS
    return
  end
  local ok, why = can_hand_mine(c, e)
  if not ok then
    s.mining = nil
    message(why)
    return
  end
  s.mining = {
    entity = e,
    progress = 0,
    time = math.max(e.prototype.mineable_properties.mining_time, 0.01),
    until_tick = game.tick + HOLD_TICKS,
  }
end

function M.mine_stop()
  storage.f3d.mining = nil
end

-- Like holding F: picks up items on the ground near the character while the client repeats it.
function M.pickup()
  local s = storage.f3d
  if s.pickup then
    s.pickup.until_tick = game.tick + HOLD_TICKS
  else
    s.pickup = { until_tick = game.tick + HOLD_TICKS }
  end
end

-- Hand-mining one unit of ore: products go to the inventory, the patch shrinks by one.
local function mine_resource(c, e)
  local products = e.prototype.mineable_properties.products or {}
  for _, product in pairs(products) do
    local stack = { name = product.name, count = product.amount or product.amount_min or 1 }
    if not c.can_insert(stack) then
      return false, "Inventory full"
    end
  end
  for _, product in pairs(products) do
    c.insert({ name = product.name, count = product.amount or product.amount_min or 1 })
  end
  if e.amount > 1 then
    e.amount = e.amount - 1
    tracker.changed(e)
  else
    e.deplete() -- raises on_resource_depleted, which sends the removal
  end
  return true
end

local function finish_mining(c, e)
  if e.type == "resource" then
    return mine_resource(c, e)
  end
  local removal = tracker.removal_message(e)
  if not c.mine_entity(e) then
    return false, "Inventory full"
  end
  if removal and not e.valid then
    transport.send_reliable(removal)
  end
  return true
end

function M.rotate(cmd)
  local c = M.get()
  if not c then
    return
  end
  local e = M.find_target(M.surface(c), cmd)
  if e and e.rotatable and e.force == c.force then
    e.rotate({ reverse = cmd.rev == 1 or cmd.rev == true })
    tracker.changed(e)
  end
end

function M.craft(cmd)
  local c = M.get()
  if not c then
    return
  end
  local name = tostring(cmd.recipe or "")
  local recipe = c.force.recipes[name]
  if not (recipe and recipe.enabled) then
    return message("Recipe not available: " .. name)
  end
  local count = math.max(1, math.min(100, math.floor(tonumber(cmd.n) or 1)))
  -- The queue grows here, not by crafting: crafting.lua looks at it afresh (see count_crafts).
  storage.f3d.craft_seen = nil
  if c.begin_crafting({ recipe = name, count = count, silent = true }) == 0 then
    message("Missing ingredients for " .. name)
  end
end

---------------------------------------------------------------------------------------------
-- State sent to the client

-- LuaEntity::max_health is new in 2.0 (quality changes it); older builds only have the
-- prototype's.
local function max_health(c)
  local ok, v = pcall(function() return c.max_health end)
  if ok and v then
    return v
  end
  ok, v = pcall(function() return c.prototype.get_max_health() end)
  return ok and v or nil
end

-- The vehicle the character sits in, or nil.
function M.vehicle(c)
  local ok, v = pcall(function() return c.vehicle end)
  return ok and v or nil
end

-- The space platform hub the character sits in, or nil (2.1: LuaControl.hub). A character rides a
-- rocket up into one (space.ride) and stays inside it, as a player does.
function M.hub(c)
  local ok, hub = pcall(function() return c.hub end)
  return ok and hub and hub.valid and hub or nil
end

-- The cargo pod the character rides in, or nil (LuaControl.cargo_pod): up from a silo in its
-- rocket, or between a hub and a planet.
function M.pod(c)
  local ok, pod = pcall(function() return c.cargo_pod end)
  return ok and pod and pod.valid and pod or nil
end

local LEAVING = { awaiting_launch = true, ascending = true, surface_transition = true }

-- me.pod, ps, gx, gy, up: the pod, its state, and the point on the ground the flight is seen from.
-- Factorio draws a pod's height as a shift up the screen, so its position runs north of that point
-- as it climbs: leaving (up = 1), the point is where it set off (the silo or hub); arriving, where
-- it comes down (the hub it docks in, or the spot space.lua / planets.lua chose to land on).
local function pod_fields(c, s, msg)
  local pod = M.pod(c)
  if not pod then
    s.trip = nil  -- arrived
    return
  end
  local ok, state = pcall(function() return pod.cargo_pod_state end)
  state = ok and state or ""
  local ground
  if LEAVING[state] then
    local oko, origin = pcall(function() return pod.cargo_pod_origin end)
    if oko and origin and origin.valid and origin.surface == pod.surface then
      ground = origin.position
    end
    msg.up = 1
  else
    local okd, dest = pcall(function() return pod.cargo_pod_destination end)
    local station = okd and dest and dest.station
    if station and station.valid and station.surface == pod.surface then
      ground = station.position
    elseif s.trip and s.trip.land and s.trip.si == pod.surface.index then
      ground = s.trip.land
    end
    msg.up = 0
  end
  ground = ground or pod.position
  msg.pod = pod.unit_number or 0
  msg.ps = state
  msg.gx = world.fixed(ground.x)
  msg.gy = world.fixed(ground.y)
end

-- In a vehicle the position is the vehicle's, which the camera follows.
local function send_state(c, s)
  local v = M.vehicle(c)
  local p = (v or c).position
  local msg = {
    t = "me",
    u = c.unit_number,
    x = world.fixed(p.x),
    y = world.fixed(p.y),
    d = c.direction,
    w = c.walking_state.walking and 1 or 0,
    hp = math.floor(c.health or 0),
    q = c.crafting_queue_size,
    sh = (s.shooting and s.shooting.firing) and 1 or 0,
  }
  -- An angled walk's angle: the client draws the character along it, not along the zig-zag.
  if s.walk and s.walk.angle and msg.w == 1 and not v then
    msg.a = s.walk.angle
  end
  local mhp = max_health(c)
  if mhp then
    msg.mhp = math.floor(mhp)
  end
  -- The armour's shields, over the health bar.
  local ok, grid = pcall(function() return c.grid end)
  if ok and grid and grid.valid and (grid.max_shield or 0) > 0 then
    msg.sd = math.floor(grid.shield + 0.5)
    msg.msd = math.floor(grid.max_shield + 0.5)
  end
  if v then
    msg.v = v.unit_number or 0
    msg.vs = math.floor(v.speed * 1000 + 0.5)
  end
  local hub = M.hub(c)
  if hub then
    msg.hub = hub.unit_number or 0
  end
  pod_fields(c, s, msg)
  if s.mining and s.mining.entity.valid then
    local mp = s.mining.entity.position
    msg.m = math.floor(s.mining.progress / s.mining.time * 100)
    msg.mx = world.fixed(mp.x)
    msg.my = world.fixed(mp.y)
  end
  transport.send_now(msg)
end

-- An inventory's contents as [[name, count], ...] in the order they first appear, qualities summed.
function M.contents(inventory)
  local totals, order = {}, {}
  for _, item in pairs(inventory.get_contents()) do
    if not totals[item.name] then
      order[#order + 1] = item.name
      totals[item.name] = 0
    end
    totals[item.name] = totals[item.name] + item.count
  end
  local list = {}
  for _, name in pairs(order) do
    list[#list + 1] = { name, totals[name] }
  end
  return list
end

-- The main inventory's contents. Only sent when it changed.
local function send_inventory(c, s)
  local inventory = c.get_main_inventory()
  if not inventory then
    return
  end
  local list, parts = M.contents(inventory), {}
  for _, entry in pairs(list) do
    parts[#parts + 1] = entry[1] .. "=" .. entry[2]
  end
  local sig = table.concat(parts, ",")
  if sig ~= s.inv_sig then
    s.inv_sig = sig
    transport.send_reliable({ t = "inv", l = list })
  end
end

-- 2.1 has LuaRecipe::categories, 2.0 has LuaRecipe::category. Reading a key an object
-- doesn't have is an error, so ask for both safely.
function M.recipe_categories(recipe)
  local ok, cats = pcall(function() return recipe.categories end)
  if ok and cats then
    return cats
  end
  local ok2, cat = pcall(function() return recipe.category end)
  if ok2 and cat then
    return { cat }
  end
  return {}
end

-- character prototype name -> names of the visible recipes in its crafting categories, sorted.
-- Derived only from prototypes (like registry.lua), so a check only reads `enabled` for these
-- instead of every recipe of the force (over a thousand with Space Age).
local hand_recipes = {}

function M.hand_recipe_names(c)
  local proto = c.prototype
  local list = hand_recipes[proto.name]
  if not list then
    local hand = proto.crafting_categories or {}
    list = {}
    for name, recipe in pairs(prototypes.recipe) do
      if not recipe.hidden then
        for _, cat in pairs(M.recipe_categories(recipe)) do
          if hand[cat] then
            list[#list + 1] = name
            break
          end
        end
      end
    end
    table.sort(list)
    hand_recipes[proto.name] = list
  end
  return list
end

-- Names of the recipes this character can craft by hand right now.
local function send_recipes(c, s)
  local recipes = c.force.recipes
  local names = {}
  for _, name in ipairs(M.hand_recipe_names(c)) do
    local recipe = recipes[name]
    if recipe and recipe.enabled and not recipe.hidden then
      names[#names + 1] = name
    end
  end
  local sig = table.concat(names, ",")
  if sig ~= s.recipes_sig then
    s.recipes_sig = sig
    transport.send_reliable({ t = "recipes", l = names })
  end
end

---------------------------------------------------------------------------------------------

-- The 8-way direction (an even one of the 16) for this tick of an angled walk; see M.walk.
local function angle_step(w)
  local turn = w.angle / 1000 * 8 -- in eighths of a turn
  local lo = math.floor(turn) % 8
  local hi = (lo + 1) % 8
  local rad = w.angle / 1000 * 2 * math.pi
  -- Each candidate's sideways step off the line, as a fraction of a step (right of the line positive).
  local function side(eighth)
    return math.sin(eighth / 8 * 2 * math.pi - rad)
  end
  local slo, shi = side(lo), side(hi)
  local pick, step = lo, slo
  if math.abs(w.err + shi) < math.abs(w.err + slo) then
    pick, step = hi, shi
  end
  w.err = w.err + step
  return pick * 2
end

local function tick_walk(c, s)
  if not s.walk then
    return
  end
  if game.tick <= s.walk.until_tick then
    if s.walk.angle then
      s.walk.dir = angle_step(s.walk)
    end
    c.walking_state = { walking = true, direction = s.walk.dir }
  else
    c.walking_state = { walking = false, direction = s.walk.dir }
    s.walk = nil
  end
end

local function tick_mining(c, s)
  local m = s.mining
  if not m then
    return
  end
  if game.tick > m.until_tick or not m.entity.valid then
    s.mining = nil
    return
  end
  local ok, why = can_hand_mine(c, m.entity)
  if not ok then
    s.mining = nil
    message(why)
    return
  end
  local speed = (c.prototype.mining_speed or 0.5)
    * (1 + c.character_mining_speed_modifier + c.force.manual_mining_speed_modifier)
  m.progress = m.progress + speed / 60
  if m.progress >= m.time then
    local done, reason = finish_mining(c, m.entity)
    if not done then
      s.mining = nil
      message(reason)
    elseif m.entity.valid then
      m.progress = 0 -- ore patch: keep mining while the client holds the button
    else
      s.mining = nil
    end
  end
end

-- Mining an item-entity puts its stack in the inventory, and mine_entity works without a
-- player, so that is how a player-less character picks up. Once the inventory is full it stops
-- trying (and says so once) until the client lets go.
local function tick_pickup(c, s)
  local p = s.pickup
  if not p then
    return
  end
  if game.tick > p.until_tick then
    s.pickup = nil
    return
  end
  if p.full then
    return
  end
  local pos = c.position
  local r = c.item_pickup_distance + PICKUP_SLACK
  local found = c.surface.find_entities_filtered({
    area = { { pos.x - r, pos.y - r }, { pos.x + r, pos.y + r } },
    type = "item-entity",
  })
  local picked = 0
  for _, e in pairs(found) do
    if picked >= PICKUPS_PER_TICK then
      return
    end
    if distance(pos, e.position) <= r then
      if not c.mine_entity(e) then
        p.full = true
        message("Inventory full")
        return
      end
      picked = picked + 1
    end
  end
end

function M.tick()
  local s = storage.f3d
  local c = M.get()
  if not c then
    if game.tick % DEAD_INTERVAL == 0 then
      send_dead(s)
    end
    return
  end
  s.death = nil
  tick_walk(c, s)
  tick_mining(c, s)
  tick_pickup(c, s)
  if game.tick % STATE_INTERVAL == 0 then
    send_state(c, s)
  end
  if game.tick % INVENTORY_INTERVAL == 0 then
    send_inventory(c, s)
  end
  if game.tick % RECIPES_INTERVAL == 0 then
    send_recipes(c, s)
  end
end

-- Reports the inventory now if it changed (after the client moved items in or out of a machine).
function M.send_inventory_now()
  local c = M.get()
  if c then
    send_inventory(c, storage.f3d)
  end
end

-- Whether the character can reach an entity to open it or move items in and out: the game's own
-- check (LuaControl::can_reach_entity, measured to the entity's edge) when it answers, otherwise
-- the same centre distance as mining.
function M.can_reach(c, e)
  local ok, reach = pcall(function() return c.can_reach_entity(e) end)
  if ok and type(reach) == "boolean" then
    return reach
  end
  return distance(c.position, e.position) <= c.reach_distance + REACH_SLACK
end

-- Force a full inventory and recipe report on the next tick they're due.
function M.invalidate()
  local s = storage.f3d
  s.inv_sig = nil
  s.recipes_sig = nil
end

-- A player joining or leaving may hand the character over (see M.get).
function M.register()
  local function again()
    M.recheck(false)
  end
  script.on_event(defines.events.on_player_joined_game, again)
  script.on_event(defines.events.on_player_left_game, again)
  script.on_event(defines.events.on_player_respawned, again)
  script.on_event(defines.events.on_runtime_mod_setting_changed, function(event)
    if event.setting == "f3d-player" then
      storage.f3d.owner_pick = nil
      M.recheck(true)
    end
  end)
end

-- /f3d-player [name | index | none]: lists the players, or picks whose character to play.
function M.player_command(cmd)
  local s = storage.f3d
  local arg = cmd.parameter and cmd.parameter:match("^%s*(.-)%s*$") or ""
  if arg == "none" then
    s.owner_pick = 0
    M.recheck(true)
  elseif arg ~= "" then
    local p = game.get_player(tonumber(arg) or arg)
    if not p then
      return { "[Zenith] no player " .. arg }
    end
    s.owner_pick = p.index
    M.recheck(true)
  end
  if arg ~= "" then
    M.get()
  end
  return takeover.describe(s)
end

function M.send_initial()
  local c = M.get()
  if c then
    local s = storage.f3d
    M.invalidate()
    send_inventory(c, s)
    send_recipes(c, s)
  end
end

return M
