-- The connection to the 3D client: handshake, keep-alive, and dispatch of incoming commands.
--
-- All of this runs from on_udp_packet_received and on_tick, which every peer replays in the
-- same order, so the state it keeps in `storage` stays deterministic in multiplayer.

local registry = require("scripts.registry")
local transport = require("scripts.transport")
local world = require("scripts.world")
local puppet = require("scripts.puppet")
local screens = require("scripts.screens")
local profile = require("scripts.profile")
local building = require("scripts.building")
local planners = require("scripts.planners")
local history = require("scripts.history")
local combat = require("scripts.combat")
local turrets = require("scripts.turrets")
local collectors = require("scripts.collectors")
local shots = require("scripts.shots")
local driving = require("scripts.driving")
local inventory = require("scripts.inventory")
local crafting = require("scripts.crafting")
local research = require("scripts.research")
local map = require("scripts.map")
local trains = require("scripts.trains")
local logistics = require("scripts.logistics")
local planets = require("scripts.planets")
local platforms = require("scripts.platforms")
local selftest = require("scripts.selftest")
local ui_actions = require("scripts.ui_actions")
local equipment = require("scripts.equipment")
local wiring = require("scripts.wiring")
local players = require("scripts.players")
local tiles = require("scripts.tiles")
local capsules = require("scripts.capsules")
local rail_planner = require("scripts.rail_planner")
local space = require("scripts.space")
local alerts = require("scripts.alerts")
local pedia = require("scripts.pedia")
local force_info = require("scripts.force_info")
local spiders = require("scripts.spiders")
local belt_items = require("scripts.belt_items")
local movers = require("scripts.movers")
local console = require("scripts.console")
local modules = require("scripts.modules")
local rate = require("scripts.rate")
local budget = require("scripts.budget")
local requests = require("scripts.requests")

local M = {}

M.PROTOCOL = 1

local TIMEOUT = 600          -- drop the client after 10 s without a hello
local MAX_EXTRA = 7          -- clients beyond the first, on a server
local RECORDS_PER_MESSAGE = 80
local RESYNC_COOLDOWN = 120

function M.init_storage()
  storage.f3d = storage.f3d or {}
  local s = storage.f3d
  s.subs = s.subs or {}
  s.queue = s.queue or {}
  s.queued = s.queued or {}
  s.rseq = s.rseq or 0
  s.outbox = s.outbox or {}
  s.outbox_head = s.outbox_head or 1
  s.outbox_tail = s.outbox_tail or 0
  s.focus = s.focus or { x = 0, y = 0, r = 32 }
  s.working = s.working or {}
  s.belt_refresh = s.belt_refresh or {}
  s.pipe_refresh = s.pipe_refresh or {}
  s.wire_sigs = s.wire_sigs or {}
  s.surface_index = s.surface_index or 1
  s.handshake_tick = s.handshake_tick or 0
  s.resync_tick = s.resync_tick or 0
  s.damaged = s.damaged or {}
end

local function send_records(kind, records)
  local parts = math.max(1, math.ceil(#records / RECORDS_PER_MESSAGE))
  for part = 1, parts do
    local slice = {}
    for i = (part - 1) * RECORDS_PER_MESSAGE + 1, math.min(part * RECORDS_PER_MESSAGE, #records) do
      slice[#slice + 1] = records[i]
    end
    transport.send_reliable({ t = kind, part = part, parts = parts, l = slice })
  end
end

-- Starts the stream over: welcome, prototype dictionaries, then the client subscribes to chunks.
-- A full resync keeps the remote view of another surface (`keep_view`): clearing it there sent the
-- client back to the character's planet whenever packets were lost (H25: zooming into a planet
-- sometimes jumped back to Nauvis).
function M.handshake(keep_view)
  local s = storage.f3d
  if not (keep_view and s.view_si and game.get_surface(s.view_si)) then
    s.view_si, s.view_at, s.view_from = nil, nil, nil
  end
  s.remote_view = nil
  belt_items.far_reset()
  movers.reset()
  rate.reset()
  transport.reset()
  world.clear()
  puppet.reset()
  screens.reset()
  combat.reset()
  turrets.reset()
  collectors.reset()
  shots.reset()
  driving.reset()
  map.reset()
  ui_actions.reset()
  alerts.reset()
  requests.reset()
  s.working = {}
  s.belt_refresh = {}
  s.pipe_refresh = {}
  s.wire_sigs = {}
  s.handshake_tick = game.tick
  local c = puppet.get()
  local surface = world.surface()
  s.surface_index = surface.index
  local p = c and c.position or { x = 0, y = 0 }
  s.focus = { x = p.x, y = p.y, r = 32 }
  s.puppet_unit = c and c.unit_number or 0
  transport.send_reliable(M.surface_fields(surface, {
    t = "welcome",
    v = M.PROTOCOL,
    mod = script.active_mods["factorio-3d-bridge"],
    u = c and c.unit_number or 0,
    x = world.fixed(p.x),
    y = world.fixed(p.y),
    mp = game.is_multiplayer(),
  }))
  -- The rest a stage a tick (handshake_tick): together they took 35 ms in one tick on the owner's
  -- save. Meanwhile only the transport and the stages run (control.lua), as before for one tick.
  s.hs_stage = 1
end

-- The handshake after the welcome, in order, with each stage's price in work units.
-- The dictionaries are made once per load (control.lua's warm-up), so these prices are their
-- sending: building the messages' slices.
local HANDSHAKE_STAGES = {
  { 100, function() send_records("protos", registry.entity_records()) end },
  { 100, function(s)
    send_records("tprotos", registry.tile_records())
    send_records("iprotos", registry.item_records())
    send_records("fprotos", registry.fluid_records())
    if s.client and s.client.dc then
      send_records("dprotos", registry.decorative_records())
    end
  end },
  { 100, function()
    transport.send_reliable({ t = "ready" })
    ui_actions.send_eprops()
  end },
  { 100, function() tiles.item_uses() end },
  { 400, function(s)
    puppet.send_initial()
    inventory.send_initial()
    crafting.invalidate()
    research.send_initial()
    planners.send_initial()
    logistics.send_initial()
    map.send_initial()
    planets.send_initial()
    equipment.send_initial()
    players.send_initial()
    s.plat_sent = nil -- platforms.tick sends the panel's data within a second
  end },
}

function M.handshaking()
  return storage.f3d.hs_stage ~= nil
end

-- Stages of the handshake while the budget allows (one always runs in its tick).
function M.handshake_tick()
  local s = storage.f3d
  while s.hs_stage do
    local stage = HANDSHAKE_STAGES[s.hs_stage]
    if not stage then
      s.hs_stage = nil
      return
    end
    if not budget.can(stage[1], "handshake") then
      return
    end
    budget.spend(stage[1], "handshake")
    s.hs_stage = s.hs_stage + 1
    if not HANDSHAKE_STAGES[s.hs_stage] then
      s.hs_stage = nil
    end
    stage[2](s)
  end
end

-- The surface's name and index, and on a platform its index (pf), else the planet's name.
function M.surface_fields(surface, msg)
  msg.surface = surface.name
  msg.si = surface.index
  local p = platforms.of_surface(surface)
  if p then
    msg.pf = p.index
  else
    msg.planet = platforms.planet_of(surface)
  end
  return msg
end

-- The character moved to another surface (a platform and back, or the player's own trip in
-- single-player), or the remote view looks at another one (`view`). Lighter than a handshake:
-- the prototypes stay, and so do the inventory, the quickbar and research; the world is dropped
-- and the client subscribes again. Everything reliable from the old surface was queued before the
-- `surface` message, so the client can drop the old world when it arrives.
function M.change_surface(c)
  local s = storage.f3d
  local surface = world.surface()
  local p = c.position
  if surface ~= c.surface and s.view_at then
    p = s.view_at
  end
  belt_items.far_reset()
  movers.reset()
  world.clear()
  screens.reset()
  combat.reset()
  turrets.reset()
  collectors.reset()
  shots.reset()
  driving.reset()
  map.reset()
  puppet.reset()
  s.working = {}
  s.belt_refresh = {}
  s.pipe_refresh = {}
  s.wire_sigs = {}
  s.surface_index = surface.index
  s.focus = { x = p.x, y = p.y, r = 32 }
  local msg = M.surface_fields(surface, { t = "surface", x = world.fixed(p.x), y = world.fixed(p.y) })
  if surface ~= c.surface then
    msg.view = 1
  end
  transport.send_reliable(msg)
  puppet.send_initial()
  platforms.send()
  planets.send_planet()
  planets.territories_soon()
end

---------------------------------------------------------------------------------------------
-- Several clients. The first client's state is storage.f3d, as it always was. On a server, a
-- hello from another port starts another client with a whole state of its own (and its own
-- character), kept in storage.f3d_extra by port; while it is served (its packets, its tick, each
-- game event) it is swapped in as storage.f3d, so every module works on "the client" unchanged.

local function extras()
  storage.f3d_extra = storage.f3d_extra or {}
  return storage.f3d_extra
end

-- Runs fn(...) with `state` as storage.f3d.
function M.serve(state, fn, ...)
  local primary = storage.f3d
  storage.f3d = state
  local ok, err = pcall(fn, ...)
  storage.f3d = primary
  if not ok then
    error(err, 0)
  end
end

-- Runs fn(...) for the first client's state (connected or not, as before), then for each other
-- client's.
function M.each_client(fn, ...)
  fn(...)
  for _, state in pairs(extras()) do
    M.serve(state, fn, ...)
  end
end

-- {player_index}: the player pressed "Show in Zenith" in the real game; the client playing their
-- character (single-player: the one client) is told to come to the front.
function M.show_3d(event)
  local s = storage.f3d
  if s.client and (not game.is_multiplayer() or puppet.owner() == game.get_player(event.player_index)) then
    transport.send_now({ t = "raise" })
  end
end

function M.client_count()
  return (storage.f3d.client and 1 or 0) + table_size(extras())
end

local function drop_client()
  local s = storage.f3d
  local port = s.client and s.client.port
  s.rate = nil
  puppet.reset()
  screens.reset()
  combat.reset()
  turrets.reset()
  collectors.reset()
  shots.reset()
  driving.reset()
  map.reset()
  world.clear()
  transport.reset()
  if s.extra and port then
    -- Its character waits for the same client (session id) to come back.
    storage.f3d_parked = storage.f3d_parked or {}
    if s.puppet and s.puppet.valid then
      storage.f3d_parked[s.client.sid] = s.puppet
    end
    extras()[port] = nil
  end
  s.client = nil
end

---------------------------------------------------------------------------------------------
-- Commands from the client

local handlers = {}

function handlers.hello(msg, port)
  local s = storage.f3d
  local sid = tostring(msg.sid or "")
  if not s.client or s.client.sid ~= sid or s.client.port ~= port then
    s.client = { sid = sid, port = port, last_seen = game.tick, z = msg.z == 1, dc = msg.dc == 1, b = msg.b == 1 }
    s.rate = nil -- a new client starts at full rate; it sends `rate` if it wants another
    M.handshake()
    return
  end
  s.client.last_seen = game.tick
  s.client.z = msg.z == 1
  s.client.b = msg.b == 1
  -- Decoratives turned on in the client's settings: send the dictionary and resend the chunks.
  if msg.dc == 1 and not s.client.dc then
    s.client.dc = true
    send_records("dprotos", registry.decorative_records())
    world.resend_all()
  elseif msg.dc ~= 1 then
    s.client.dc = false
  end
  -- The client never got the welcome (lost packet): start over, at most every 2 seconds.
  if msg.w == 0 and game.tick - s.handshake_tick > 120 then
    M.handshake()
  end
end

function handlers.bye()
  drop_client()
end

function handlers.sub(msg)
  if type(msg.c) == "table" then
    world.subscribe(msg.c)
  end
end

function handlers.focus(msg)
  local s = storage.f3d
  local x, y, r = tonumber(msg.x), tonumber(msg.y), tonumber(msg.r)
  if x and y then
    local max_r = settings.global["f3d-max-focus-radius"].value
    s.focus = { x = x / 256, y = y / 256, r = math.max(8, math.min(r or 32, max_r)) }
  end
  -- rv = 1: the 3D remote view, which shows moving things only where radars see (map.view_filter).
  s.remote_view = tonumber(msg.rv) == 1 or nil
end

-- The client saw a gap in the reliable sequence. full = 1 restarts everything (it is missing
-- prototypes or the server went back in time); otherwise its chunks are sent again: the ones
-- listed in `c`, or all of them. A list is cheap and already-queued chunks aren't queued twice,
-- so it skips the cooldown; that lets a lossy link converge chunk by chunk.
function handlers.resync(msg)
  local s = storage.f3d
  if msg.full ~= 1 and type(msg.c) == "table" then
    world.resend(msg.c)
    return
  end
  if game.tick - s.resync_tick < RESYNC_COOLDOWN then
    return
  end
  s.resync_tick = game.tick
  if msg.full == 1 then
    M.handshake(true)
  else
    world.resend_all()
    belt_items.far_reset()
    movers.reset()
  end
end

handlers.walk = puppet.walk
handlers.mine = puppet.mine
handlers.mine_stop = puppet.mine_stop
handlers.pickup = puppet.pickup
handlers.build = function(cmd)
  if cmd.sf == 1 then
    return planners.superforced(cmd)
  end
  return building.build(cmd)
end
handlers.blueprint = planners.blueprint
handlers.decon = planners.decon
handlers.upgrade = planners.upgrade
handlers.rotate = planners.rotate
handlers.bp_get = planners.get
handlers.bp_set = planners.set
handlers.bp_page = planners.page
handlers.bp_lib = planners.library
handlers.bp_rec = planners.record
handlers.bp_del = planners.delete
handlers.undo = history.undo
handlers.redo = history.redo
handlers.craft = puppet.craft
handlers.shoot = combat.shoot
handlers.gun = combat.gun
handlers.enter = driving.enter
handlers.drive = driving.drive
handlers.open = screens.open
handlers.close = screens.close
handlers.set_recipe = screens.set_recipe
handlers.take = screens.take
handlers.put = screens.put
handlers.set_cb = screens.set_combinator
handlers.set_schedule = screens.set_schedule
handlers.train_go = screens.train_go
handlers.train_mode = screens.train_mode
handlers.set_stop = screens.set_stop
handlers.set_interrupts = screens.set_interrupts
handlers.train_temp = screens.train_temp
requests.add("trains_list", trains.list, 100)
handlers.trains_list = requests.handler("trains_list")
handlers.train_mode_id = trains.set_mode_by_id
handlers.set_requests = screens.set_requests
handlers.set_storage_filter = screens.set_storage_filter
handlers.set_chest_logistics = screens.set_chest_logistics
handlers.set_char_requests = logistics.set_char_requests
handlers.land = planets.land
handlers.move = inventory.move
handlers.xfer = inventory.xfer
handlers.sort = inventory.sort
handlers.inv_filter = inventory.set_filter
handlers.qb_set = inventory.qb_set
handlers.qb_sel = inventory.qb_sel
handlers.qb_page = inventory.qb_page
handlers.cancel_craft = crafting.cancel_craft
handlers.research = research.research
handlers.research_cancel = research.research_cancel
handlers.map = map.request
handlers.tag_add = map.add_tag
handlers.tag_del = map.remove_tag
handlers.unghost = map.unghost
handlers.mtr = map.trains
handlers.mrp = map.roboports
handlers.lpad = map.landing_pad
handlers.bfar = belt_items.set_far
handlers.rate = rate.set
handlers.budget = budget.set

-- {si, x, y}: the remote view looks at another surface (a planet or one of the force's
-- platforms), so the world streamed is that surface's, round (x, y); si 0 (or the character's)
-- goes back. The tick sees the change and sends `surface` with `view` set.
function handlers.view(cmd)
  local s = storage.f3d
  local c = puppet.get()
  local si = math.floor(tonumber(cmd.si) or 0)
  local surface = si > 0 and game.get_surface(si) or nil
  local allowed = false
  if surface and c and surface ~= c.surface then
    local okp, platform = pcall(function() return surface.platform end)
    local okq, planet = pcall(function() return surface.planet end)
    allowed = (okp and platform ~= nil and platform.valid and platform.force == c.force) or (okq and planet ~= nil)
  end
  if allowed then
    s.view_si, s.view_from = si, c.surface.index
    s.view_at = { x = (tonumber(cmd.x) or 0) / 256, y = (tonumber(cmd.y) or 0) / 256 }
  else
    s.view_si, s.view_at, s.view_from = nil, nil, nil
  end
end

-- While the remote view shows another surface, what Factorio's remote view allows goes to that
-- surface (puppet.surface): ghosts, planners, rotating, settings, copy and paste, undo. Building
-- there only ever places ghosts. What needs the character's hands waits (opening buildings there
-- works: screens.lua takes the surface).
local VIEW_BLOCKED = {}
for _, t in ipairs({ "mine", "pickup", "shoot", "drop", "fast", "wire", "wire_clear", "throw" }) do
  VIEW_BLOCKED[t] = true
end
local REMOTE_OK = {}
for _, t in ipairs({ "build", "blueprint", "decon", "upgrade", "rotate", "undo", "redo", "paste_settings",
                     "flip", "copy", "paste", "tile", "tile_mine", "rails", "unghost", "modreq" }) do
  REMOTE_OK[t] = true
end
local GHOST_ONLY = { build = true, tile = true, rails = true }
-- Also refused while riding a rocket or pod, or sitting in a hub (dispatch).
local RIDE_BLOCKED = {}
for _, t in ipairs({ "walk", "enter", "ride", "plat_board" }) do
  RIDE_BLOCKED[t] = true
end
handlers.plat_go = platforms.go
handlers.plat_sched = platforms.set_schedule
handlers.plat_pause = platforms.pause
handlers.plat_board = platforms.board_command
handlers.set_inserter = screens.set_inserter
handlers.set_splitter = screens.set_splitter
handlers.set_switch = screens.set_switch
handlers.set_panel = screens.set_panel
handlers.set_bar = screens.set_bar
handlers.set_cc = screens.set_circuit
handlers.set_color = screens.set_color
handlers.set_lamp = screens.set_lamp
handlers.set_desc = screens.set_desc
handlers.set_speaker = screens.set_speaker
handlers.set_pump = screens.set_pump
handlers.set_targets = screens.set_targets
handlers.set_vehicle = screens.set_vehicle
handlers.set_artillery = screens.set_artillery
handlers.flush = screens.flush
handlers.set_train_group = screens.set_train_group
handlers.spider_go = spiders.go
handlers.spider_q = spiders.query
handlers.wire = wiring.wire
handlers.wire_clear = wiring.clear
handlers.drop = ui_actions.drop
handlers.fast = ui_actions.fast
handlers.paste_settings = planners.paste_settings
handlers.flip = ui_actions.flip
handlers.copy = ui_actions.copy
handlers.paste = ui_actions.paste
handlers.alt = ui_actions.alt
handlers.chat = ui_actions.chat
requests.add("stats", ui_actions.stats, 300)
handlers.stats = requests.handler("stats")
handlers.eq_put = equipment.put
handlers.eq_take = equipment.take
handlers.eq_move = equipment.move
handlers.eq_toggle = equipment.toggle
handlers.respawn = puppet.respawn
handlers.tile = tiles.place
handlers.tile_mine = tiles.mine
handlers.throw = capsules.throw
handlers.rails = rail_planner.build
space.add_handlers(handlers, screens)
-- set_section with u = 0 is the character's own sections; any other u is the open entity's.
local entity_section = handlers.set_section
handlers.set_section = function(cmd)
  if tonumber(cmd.u) == 0 then
    return logistics.set_char_section(cmd)
  end
  return entity_section(cmd)
end
handlers.set_char_color = logistics.set_char_color
requests.add("pedia_index", pedia.index, 300)
handlers.pedia_index = requests.handler("pedia_index")
requests.add("pedia", pedia.page, 150)
handlers.pedia = requests.handler("pedia")
requests.add("lnets", logistics.networks, 300)
handlers.lnets = requests.handler("lnets")
requests.add("lnet", logistics.network, 150)
handlers.lnet = requests.handler("lnet")
requests.add("bonuses", force_info.bonuses, 300)
handlers.bonuses = requests.handler("bonuses")
requests.add("perms", force_info.permissions, 100)
handlers.perms = requests.handler("perms")
handlers.cmd = console.run
handlers.modreq = modules.request
requests.add("hinfo", modules.hover, 50)
handlers.hinfo = requests.handler("hinfo")

local function dispatch(handler, msg, port)
  local s = storage.f3d
  if msg.t ~= "hello" and not (s.client and s.client.port == port) then
    return
  end
  if s.view_si and VIEW_BLOCKED[msg.t] then
    transport.send_now({ t = "msg", text = "Not from another surface: that works where the character is" })
    return
  end
  if s.view_si and REMOTE_OK[msg.t] then
    s.act_si = s.view_si
    if GHOST_ONLY[msg.t] then
      msg.ghost = 1
    end
  end
  -- Riding a rocket or cargo pod nothing acts on the world; inside a platform's hub the platform
  -- is worked as from the remote view, as a player in a hub does: ghosts, not hands.
  local c = (RIDE_BLOCKED[msg.t] or VIEW_BLOCKED[msg.t] or REMOTE_OK[msg.t]) and puppet.get()
  if c then
    local pod, hub = puppet.pod(c), puppet.hub(c)
    if pod or (hub and (RIDE_BLOCKED[msg.t] or VIEW_BLOCKED[msg.t])) then
      if msg.t ~= "walk" then
        transport.send_now({ t = "msg", text = pod and "Not while flying" or "Not from inside the hub" })
      end
      return
    end
    if hub and GHOST_ONLY[msg.t] then
      msg.ghost = 1
    end
  end
  local ok, err = pcall(handler, msg, port)
  s.act_si = nil
  if not ok then
    log("[factorio-3d-bridge] error handling '" .. msg.t .. "': " .. tostring(err))
    transport.send_now({ t = "msg", text = "Bridge error: " .. tostring(err) })
  end
end

-- A new client next to the first: a fresh state, with its old character if it was here before.
local function add_client(msg, port)
  local state = { extra = true }
  local parked = storage.f3d_parked or {}
  local sid = tostring(msg.sid or "")
  local c = parked[sid]
  parked[sid] = nil
  extras()[port] = state
  M.serve(state, function()
    M.init_storage()
    if c and c.valid then
      state.puppet = c
    end
    dispatch(handlers.hello, msg, port)
  end)
end

function M.on_packet(event)
  local ok_decode, msg = pcall(helpers.json_to_table, event.payload)
  if not ok_decode or type(msg) ~= "table" or type(msg.t) ~= "string" then
    return
  end
  local handler = handlers[msg.t]
  if not handler then
    return
  end
  local port = event.source_port
  local extra = extras()[port]
  if extra then
    return M.serve(extra, dispatch, handler, msg, port)
  end
  local s = storage.f3d
  -- In single-player the game plays one character, so a new port takes over, as before.
  if msg.t == "hello" and s.client and s.client.port ~= port and game.is_multiplayer() then
    if table_size(extras()) < MAX_EXTRA then
      add_client(msg, port)
    end
    return
  end
  profile.run("pkt:" .. msg.t, dispatch, handler, msg, port)
end

-- Returns false when there is no live client this tick.
function M.tick()
  local s = storage.f3d
  if game.tick - s.client.last_seen > TIMEOUT then
    drop_client()
    return false
  end
  -- A new character (a respawn after death) starts over, so the client's avatar is the new one.
  -- The same character on another surface (a space platform, or in single-player wherever the
  -- player went) only changes the world.
  local c = puppet.get()
  if c and s.view_si and c.surface.index ~= s.view_from then
    s.view_si, s.view_at, s.view_from = nil, nil, nil  -- the character went somewhere itself
  end
  if c and c.unit_number ~= s.puppet_unit then
    M.handshake()
  elseif c and world.surface().index ~= s.surface_index then
    M.change_surface(c)
  end
  return true
end

function M.status_command(cmd)
  local s = storage.f3d
  local lines = {}
  for port, state in pairs(extras()) do
    local c = state.puppet
    lines[#lines + 1] = string.format("[Zenith] another client on port %d, its character at %s", port,
      c and c.valid and string.format("%.1f, %.1f on %s", c.position.x, c.position.y, c.surface.name) or "none yet")
  end
  if s.client then
    local subs = 0
    for _ in pairs(s.subs) do
      subs = subs + 1
    end
    lines[#lines + 1] = string.format(
      "[Zenith] client on port %d, last seen %d ticks ago; %d chunks subscribed, %d queued, %d messages waiting",
      s.client.port, game.tick - s.client.last_seen, subs, #s.queue, transport.backlog())
    if rate.level() > 0 then
      lines[#lines + 1] = "[Zenith] slowed down to rate level " .. rate.level() .. " (the client's `rate`)"
    end
  else
    lines[#lines + 1] = "[Zenith] no client connected. Is Factorio running with --enable-lua-udp <port>?"
  end
  local c = puppet.get()
  if c then
    lines[#lines + 1] = string.format("[Zenith] character at %.1f, %.1f on %s", c.position.x, c.position.y, c.surface.name)
    local held = puppet.held_for()
    local player = held or puppet.player_of(c)
    lines[#lines + 1] = player and string.format("[Zenith] playing as %s%s", player.name,
      held and " (standing in while they're not connected)" or "") or "[Zenith] playing the bridge's own character"
  end
  for _, line in ipairs(budget.report()) do
    lines[#lines + 1] = line
  end
  for _, line in ipairs(profile.report()) do
    lines[#lines + 1] = line
  end
  M.reply(cmd, lines)
end

function M.selftest_command(cmd)
  M.reply(cmd, selftest.run())
end

-- Without a player the command came from the server console or RCON (or the client's console,
-- through `cmd`: console.capture). rcon.print answers RCON,
-- and print reaches the console's stdout (plain strings only); game.print would only go to the
-- chat.
function M.reply(cmd, lines)
  if console.capture then
    for _, line in ipairs(lines) do
      console.capture[#console.capture + 1] = line
    end
    return
  end
  local player = cmd.player_index and game.get_player(cmd.player_index)
  for _, line in ipairs(lines) do
    if player then
      player.print(line)
    else
      rcon.print(line)
      if type(line) == "string" then
        print(line)
      end
    end
  end
end

function M.platform_command(cmd)
  M.reply(cmd, platforms.console(cmd))
end

function M.player_command(cmd)
  M.reply(cmd, puppet.player_command(cmd))
end

-- /f3d-rate <0-3>: every client's slow-down level, as its `rate` command would set it (for
-- measuring; the client sets its own).
function M.rate_command(cmd)
  local l = tonumber(cmd.parameter) or 0
  M.each_client(rate.set, { l = l })
  M.reply(cmd, { "[Zenith] rate level " .. rate.level() })
end

function M.profile_command(cmd)
  local n = tostring(cmd.parameter or ""):match("^%s*trace%s*(%d*)")
  if n then
    local ticks = profile.trace(n ~= "" and n or 600)
    M.reply(cmd, { "[Zenith] tracing each module's time for " .. ticks .. " ticks into the log (f3dtrace lines)" })
    return
  end
  local on = profile.toggle()
  M.reply(cmd, { on and "[Zenith] profiling on: /f3d-status shows each module's time per tick after 10 s"
    .. (trace and "; each tick's times also go to the log (f3d-trace lines)" or "")
    or "[Zenith] profiling off" })
end

console.extra["f3d-status"] = M.status_command
console.extra["f3d-selftest"] = M.selftest_command
console.extra["f3d-platform"] = M.platform_command
console.extra["f3d-player"] = M.player_command
console.extra["f3d-profile"] = M.profile_command
console.extra["f3d-rate"] = M.rate_command

return M
