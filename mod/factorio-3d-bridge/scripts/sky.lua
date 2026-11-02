-- Time of day, so the client can move its sun and dim its light. Lamps come with the machine
-- states (movers.lua), and the client lights them when it is dark enough.
--
-- Read-only: nothing here touches `storage`, so it is safe in multiplayer.

local transport = require("scripts.transport")
local world = require("scripts.world")

local M = {}

local INTERVAL = 60

function M.tick()
  if game.tick % INTERVAL ~= 0 then
    return
  end
  local surface = world.surface()
  -- daytime: 0 is noon, 0.5 midnight. darkness: 0 in daylight up to ~0.85 at night.
  transport.send_now({
    t = "sky",
    d = math.floor(surface.daytime * 1000 + 0.5) % 1000,
    n = math.floor(surface.darkness * 1000 + 0.5),
  })
end

return M
