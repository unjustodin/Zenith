-- The client's console: the console commands the bridge runs for the character it plays (`cmd`,
-- answered with `cmdr`), and the `zenith` remote interface that the client's Lua commands over
-- RCON use for `game.player` (RCON has no player of its own).
--
-- Lua itself never runs from a packet: anything on localhost can send UDP, and /c is for admins.
-- Lua commands go over RCON (a password) or into Factorio itself (Ctrl+F9).

local transport = require("scripts.transport")
local puppet = require("scripts.puppet")
local platforms = require("scripts.platforms")

local M = {}

-- Commands of the mod's own (/f3d-status...), filled in by session.lua: name -> fn(cmd).
M.extra = {}
-- While a command runs for the client, session.reply adds its lines here instead of printing.
M.capture = nil

-- The kit /cheat all gives the bridge's character. Factorio's own kit is chosen inside the
-- engine and isn't listed anywhere the mod can read, so this one is ours: armour, its equipment
-- and robots to fill it.
local CHEAT_KIT = {
  { "power-armor-mk2", 1 }, { "fusion-reactor-equipment", 2 }, { "exoskeleton-equipment", 4 },
  { "personal-roboport-mk2-equipment", 2 }, { "battery-mk2-equipment", 2 }, { "energy-shield-mk2-equipment", 2 },
  { "personal-laser-defense-equipment", 2 }, { "construction-robot", 50 }, { "night-vision-equipment", 1 },
}

local function words_of(text)
  local w = {}
  for word in string.gmatch(text or "", "%S+") do
    w[#w + 1] = word
  end
  return w
end

-- The LuaPlayer whose character the client plays, if any: the owner while connected, the player
-- in single-player. The bridge's own character on a new map (or a stand-in while the owner is
-- away) has none.
function M.player()
  local c = puppet.get()
  return c and puppet.player_of(c) or nil
end

-- The name the console calls the character by: its player's, the player it stands in for, or nil.
local function name_of(c)
  local p = c and puppet.player_of(c) or puppet.held_for()
  return p and p.name or nil
end

---------------------------------------------------------------------------------------------
-- The commands

local commands = {}

local function seconds_text(ticks)
  local s = math.floor(ticks / 60)
  local parts = {}
  local units = { { 86400, "day" }, { 3600, "hour" }, { 60, "minute" }, { 1, "second" } }
  for _, u in ipairs(units) do
    local n = math.floor(s / u[1])
    s = s - n * u[1]
    if n > 0 then
      parts[#parts + 1] = n .. " " .. u[2] .. (n == 1 and "" or "s")
    end
  end
  if #parts == 0 then
    return "0 seconds"
  end
  if #parts == 1 then
    return parts[1]
  end
  return table.concat(parts, ", ", 1, #parts - 1) .. " and " .. parts[#parts]
end

function commands.version()
  return { tostring(script.active_mods["base"] or "?") }
end

function commands.seed()
  local nauvis = game.surfaces["nauvis"] or game.surfaces[1]
  return { tostring(nauvis.map_gen_settings.seed) }
end

function commands.time()
  return { seconds_text(game.ticks_played) }
end

-- Factorio's line: "[planet=nauvis] Nauvis - Evolution factor: 0.0001. (Time 100%) ...", each
-- part's share of the factor.
function commands.evolution(words)
  local c = puppet.get()
  local surface = words[1] and game.surfaces[words[1]] or (c and c.surface) or game.surfaces[1]
  if not surface then
    return { "No surface " .. tostring(words[1]) }
  end
  local enemy = game.forces["enemy"]
  local ok, factor, t, p, k = pcall(function()
    return enemy.get_evolution_factor(surface), enemy.get_evolution_factor_by_time(surface),
      enemy.get_evolution_factor_by_pollution(surface), enemy.get_evolution_factor_by_killing_spawners(surface)
  end)
  if not ok then
    return { "No evolution on " .. surface.name }
  end
  local sum = t + p + k
  local function share(x)
    return string.format("%d%%", sum > 0 and math.floor(x / sum * 100 + 0.5) or 0)
  end
  local okp, lp = pcall(function() return surface.planet end)
  local planet = okp and lp and string.format("[planet=%s] ", lp.name) or ""
  -- Factorio writes the planet's locale name, which the mod can't read as text; for the five
  -- planets it is their name with a capital.
  local name = okp and lp and (surface.name:sub(1, 1):upper() .. surface.name:sub(2)) or surface.name
  return { string.format("%s%s - Evolution factor: %.4f. (Time %s) (Pollution %s) (Spawner kills %s)",
    planet, name, factor, share(t), share(p), share(k)) }
end

function commands.players(words)
  local only_online = words[1] == "online" or words[1] == "o"
  local list = {}
  for _, p in pairs(game.players) do
    if p.connected or not only_online then
      list[#list + 1] = "  " .. p.name .. (p.connected and " (online)" or "")
    end
  end
  local lines = { string.format("Players (%d):", #list) }
  if words[1] == "count" or words[1] == "c" then
    return lines
  end
  for _, l in ipairs(list) do
    lines[#lines + 1] = l
  end
  return lines
end

function commands.admins(words)
  local only_online = words[1] == "online" or words[1] == "o"
  local lines = {}
  for _, p in pairs(game.players) do
    if p.admin and (p.connected or not only_online) then
      lines[#lines + 1] = "  " .. p.name .. (p.connected and " (online)" or "")
    end
  end
  table.insert(lines, 1, string.format("Admins (%d):", #lines))
  return lines
end

commands["server-save"] = function()
  if not game.is_multiplayer() then
    return { "Only a multiplayer game saves on the server" }
  end
  game.server_save()
  return { "Saving the map on the server" }
end

-- Factorio's /cheat for the character the bridge plays: research everything and cheat mode
-- (a player's setting: only when a player plays the character); `all` also gives a kit;
-- `off` ends cheat mode; a planet or platform name moves the character there.
function commands.cheat(words)
  local c = puppet.get()
  if not c then
    return { "No character to cheat for" }
  end
  local arg = words[1]
  local player = M.player() or puppet.held_for()
  if arg == "off" then
    if not player then
      return { "The bridge's own character has no cheat mode to turn off" }
    end
    player.cheat_mode = false
    return { "Cheat mode off" }
  end
  if arg and arg ~= "all" then
    local planet = game.planets and game.planets[arg]
    local ok, err
    if planet then
      ok, err = platforms.descend(c, arg)
    else
      local p = platforms.by_name(c.force, arg)
      if not p then
        return { "No planet or platform called " .. arg }
      end
      ok, err = platforms.board(c, p)
    end
    return { ok and ("Moved to " .. arg) or err }
  end
  c.force.research_all_technologies()
  local lines = { "Researched every technology" }
  if player then
    player.cheat_mode = true
    lines[#lines + 1] = "Cheat mode on for " .. player.name
  else
    lines[#lines + 1] = "Cheat mode is a player's: the bridge's own character has none, so crafting still takes time"
  end
  if arg == "all" then
    local given = 0
    for _, kit in ipairs(CHEAT_KIT) do
      if prototypes.item[kit[1]] then
        given = given + c.insert({ name = kit[1], count = kit[2] })
      end
    end
    lines[#lines + 1] = string.format("Gave the character %d items: power armour MK2, equipment and robots", given)
  end
  return lines
end

---------------------------------------------------------------------------------------------
-- {id, text}: one console line from the client ("/cheat all"). Answered with {t = "cmdr", id,
-- l = lines, ok = 0 when the bridge doesn't know the command}.

function M.run(cmd)
  local text = tostring(cmd.text or ""):gsub("^%s*/", "")
  local words = words_of(text)
  local name = table.remove(words, 1) or ""
  local reply = { t = "cmdr", id = tonumber(cmd.id) or 0 }
  local fn = commands[name]
  if fn then
    local ok, lines = pcall(fn, words)
    reply.l = ok and lines or { "Error: " .. tostring(lines) }
  elseif M.extra[name] then
    M.capture = {}
    local ok, err = pcall(M.extra[name], { name = name, parameter = table.concat(words, " ") ~= "" and table.concat(words, " ") or nil })
    reply.l = M.capture
    M.capture = nil
    if not ok then
      reply.l[#reply.l + 1] = "Error: " .. tostring(err)
    end
  else
    reply.l = {}
    reply.ok = 0
  end
  transport.send_reliable(reply)
end

---------------------------------------------------------------------------------------------
-- remote.call("zenith", ...): for the client's Lua commands over RCON.

function M.register_remote()
  remote.add_interface("zenith", {
    -- The LuaPlayer playing the client's character, or nil.
    player = function() return M.player() end,
    -- The client's character (LuaEntity), or nil.
    character = function() return puppet.get() end,
    -- The name of the player the character is, or stands in for (nil: the bridge's own).
    name = function() return name_of(puppet.get()) end,
  })
end

return M
