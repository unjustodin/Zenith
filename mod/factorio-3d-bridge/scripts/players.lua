-- The other players on the server, for Factorio's players list and the names over their
-- characters (the characters themselves come with the movers). Read-only.

local transport = require("scripts.transport")
local puppet = require("scripts.puppet")

local M = {}

local INTERVAL = 60
local RESEND_TICKS = 600

local function get(obj, key)
  local ok, v = pcall(function() return obj[key] end)
  if ok then
    return v
  end
  return nil
end

local function byte(v)
  v = tonumber(v) or 0
  if v <= 1 then
    v = v * 255 -- colours may be 0-1 or 0-255
  end
  return math.max(0, math.min(255, math.floor(v + 0.5)))
end

-- The armour a character wears (item name, "" for none): the client draws its look.
local function armor_of(c)
  if not (c and c.valid) then
    return ""
  end
  local inv = c.get_inventory(defines.inventory.character_armor)
  local stack = inv and inv[1]
  return (stack and stack.valid_for_read and stack.name) or ""
end

-- [index, name, connected 0/1, r, g, b, character unit (0: none), surface name, admin 0/1,
-- afk ticks, tag, armour] per player, and which of them the client plays (0: the bridge's own
-- character).
local function player_list()
  local list = {}
  for _, p in pairs(game.players) do
    local color = get(p, "color") or {}
    local c = get(p, "character")
    local surface = get(p, "physical_surface") or get(p, "surface")
    list[#list + 1] = {
      p.index, p.name, p.connected and 1 or 0,
      byte(color.r or color[1]), byte(color.g or color[2]), byte(color.b or color[3]),
      (c and c.valid and c.unit_number) or 0,
      surface and surface.name or "",
      get(p, "admin") and 1 or 0,
      math.floor(tonumber(get(p, "afk_time")) or 0),
      tostring(get(p, "tag") or ""),
      armor_of(c),
    }
  end
  local c = puppet.get()
  local me = c and (puppet.player_of(c) or puppet.held_for())
  return list, me and me.index or 0, c and c.unit_number or 0
end

function M.tick()
  -- Its own phase: the bridge's periodic jobs all fell on the same tick once a second (budget.lua).
  if (game.tick + 31) % INTERVAL ~= 0 then
    return
  end
  local s = storage.f3d
  local list, me, unit = player_list()
  local parts = { me, unit }
  for _, r in ipairs(list) do
    -- afk time changes every tick; only whether someone is away counts.
    parts[#parts + 1] = table.concat({ r[1], r[2], r[3], r[4], r[5], r[6], r[7], r[8], r[9], r[10] > 18000 and 1 or 0, r[11], r[12] }, "/")
  end
  local sig = table.concat(parts, ",")
  if s.pl_sig == sig and game.tick - (s.pl_tick or 0) < RESEND_TICKS then
    return
  end
  s.pl_sig, s.pl_tick = sig, game.tick
  transport.send_now({ t = "pl", me = me, u = unit, l = list })
end

function M.send_initial()
  storage.f3d.pl_sig = nil
  storage.f3d.pl_tick = -RESEND_TICKS
end

return M
