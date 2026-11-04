-- Zenith bridge: streams the game to the 3D client over localhost UDP and applies its input.
-- Factorio must be launched with --enable-lua-udp <port>; the client sends to that port.

local transport = require("scripts.transport")
local world = require("scripts.world")
local tracker = require("scripts.tracker")
local movers = require("scripts.movers")
local belt_items = require("scripts.belt_items")
local ground_items = require("scripts.ground_items")
local fluids_power = require("scripts.fluids_power")
local inserters = require("scripts.inserters")
local sky = require("scripts.sky")
local puppet = require("scripts.puppet")
local driving = require("scripts.driving")
local screens = require("scripts.screens")
local combat = require("scripts.combat")
local turrets = require("scripts.turrets")
local shots = require("scripts.shots")
local inventory = require("scripts.inventory")
local crafting = require("scripts.crafting")
local research = require("scripts.research")
local map = require("scripts.map")
local trains = require("scripts.trains")
local logistics = require("scripts.logistics")
local platforms = require("scripts.platforms")
local planets = require("scripts.planets")
local space = require("scripts.space")
local collectors = require("scripts.collectors")
local ui_actions = require("scripts.ui_actions")
local equipment = require("scripts.equipment")
local players = require("scripts.players")
local alerts = require("scripts.alerts")
local enemies = require("scripts.enemies")
local session = require("scripts.session")
local console = require("scripts.console")
local profile = require("scripts.profile")
local budget = require("scripts.budget")
local requests = require("scripts.requests")
local alt_mode = require("scripts.alt_mode")

script.on_init(session.init_storage)
script.on_configuration_changed(function() session.each_client(session.init_storage) end)

script.on_event(defines.events.on_udp_packet_received, session.on_packet)

-- In this order: queued world data goes first, so a fresh client gets its welcome before any
-- live state.
local STEPS = {
  { "transport", transport.flush }, { "tracker", tracker.tick }, { "puppet", puppet.tick },
  { "combat", combat.tick }, { "turrets", turrets.tick }, { "shots", shots.tick },
  { "driving", driving.tick }, { "screens", screens.tick },
  { "inventory", inventory.tick }, { "crafting", crafting.tick }, { "research", research.tick },
  { "map", map.tick }, { "trains", trains.tick }, { "logistics", logistics.tick }, { "platforms", platforms.tick },
  { "planets", planets.tick }, { "space", space.tick }, { "collectors", collectors.tick },
  { "world", world.tick }, { "movers", movers.tick }, { "belt_items", belt_items.tick }, { "belt_lanes", belt_items.far_tick },
  { "ground_items", ground_items.tick }, { "fluids_power", fluids_power.tick },
  { "inserters", inserters.tick }, { "sky", sky.tick }, { "ui_actions", ui_actions.tick }, { "alt_mode", alt_mode.tick },
  { "alerts", alerts.tick }, { "equipment", equipment.tick }, { "players", players.tick },
  { "enemies", enemies.tick }, { "requests", requests.tick },
}

local function serve()
  if not storage.f3d.client or not session.tick() then
    return
  end
  -- The tick's work budget (budget.lua): jobs that can be big take their slices from it.
  budget.begin()
  if session.handshaking() then
    profile.run("transport", transport.flush)
    profile.run("handshake", session.handshake_tick)
  else
    for _, step in ipairs(STEPS) do
      profile.run(step[1], step[2])
    end
  end
  budget.finish()
end

-- Lists made from prototypes alone (the handshake's dictionaries, Factoriopedia's index) cost 8-38
-- ms each the first time. They are made one a tick from the first ticks after loading, before a
-- client asks, so no request pays for them (budget.lua). Module-local, nothing in `storage`.
local registry = require("scripts.registry")
local tiles = require("scripts.tiles")
local pedia = require("scripts.pedia")
local WARM = {
  registry.entity_records,
  function() ui_actions.send_eprops(true) end,
  function() tiles.warm_item_uses(false) end,
  function() tiles.warm_item_uses(true) end,
  pedia.warm_lookups,
  pedia.warm_index,
}
local warmed = 0

script.on_event(defines.events.on_tick, function()
  if warmed < #WARM then
    warmed = warmed + 1
    profile.run("warm", WARM[warmed])
  end
  profile.run("poll", transport.poll)
  profile.run("bridge", function() session.each_client(serve) end)
  profile.run("transport", transport.end_tick)
  profile.end_tick()
end)

tracker.register()
puppet.register()
combat.register()
shots.register()
research.register()
map.register()
planets.register()
trains.register()
script.on_event(defines.events.on_console_chat, ui_actions.on_console_chat)

commands.add_command("f3d-status", { "command-help.f3d-status" }, session.status_command)
commands.add_command("f3d-selftest", { "command-help.f3d-selftest" }, session.selftest_command)
commands.add_command("f3d-platform", { "command-help.f3d-platform" }, session.platform_command)
commands.add_command("f3d-player", { "command-help.f3d-player" }, session.player_command)
commands.add_command("f3d-profile", { "command-help.f3d-profile" }, session.profile_command)
commands.add_command("f3d-rate", { "command-help.f3d-rate" }, session.rate_command)
-- game.player for the client's Lua commands over RCON (console.lua).
console.register_remote()

-- Several clients (session.lua): every game event reaches each client's state in turn.
for _, id in pairs(defines.events) do
  if id ~= defines.events.on_tick and id ~= defines.events.on_udp_packet_received then
    local handler = script.get_event_handler(id)
    if handler then
      script.on_event(id, function(event) session.each_client(handler, event) end)
    end
  end
end

-- The real game's "Show in Zenith" key (data.lua): the client playing that player's character
-- comes to the front.
script.on_event("f3d-show-3d", function(event) session.each_client(session.show_3d, event) end)
