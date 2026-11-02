-- Getting in and out of vehicles and driving them: Factorio's Enter key and WASD. The character
-- drives through `riding_state`, as a player does, so cars, tanks, spidertrons and trains all
-- behave as the game makes them.

local registry = require("scripts.registry")
local puppet = require("scripts.puppet")

local M = {}

local HOLD_TICKS = 30      -- a drive command lasts this long unless the client repeats it
local ENTER_DISTANCE = 5   -- from the character's centre to the vehicle's
-- The numbers the client sends, by their defines.riding names.
local ACCELERATION = { [0] = "nothing", [1] = "accelerating", [2] = "braking", [3] = "reversing" }
local DIRECTION = { [-1] = "left", [0] = "straight", [1] = "right" }

local function distance(a, b)
  local dx, dy = a.x - b.x, a.y - b.y
  return math.sqrt(dx * dx + dy * dy)
end

local function nearest_vehicle(c)
  local types = registry.vehicle_types()
  if #types == 0 then
    return nil
  end
  local p, r = c.position, ENTER_DISTANCE
  local best, best_d = nil, r
  for _, v in pairs(c.surface.find_entities_filtered({ area = { { p.x - r, p.y - r }, { p.x + r, p.y + r } }, type = types })) do
    local d = distance(p, v.position)
    if d <= best_d then
      best, best_d = v, d
    end
  end
  return best
end

-- get_driver gives the character, or the player when a player sits in it (single-player).
local function is_driver(v, c)
  local d = v.get_driver()
  if d == nil then
    return false
  end
  if d == c then
    return true
  end
  local ok, character = pcall(function() return d.character end)
  return ok and character == c
end

local function stop_riding(c)
  c.riding_state = {
    acceleration = defines.riding.acceleration.nothing,
    direction = defines.riding.direction.straight,
  }
end

-- A burner vehicle with nothing burning and nothing to burn.
local function out_of_fuel(v)
  local ok, empty = pcall(function()
    local burner = v.burner
    return burner ~= nil and burner.remaining_burning_fuel <= 0 and burner.inventory.is_empty()
  end)
  return ok and empty
end

---------------------------------------------------------------------------------------------
-- Commands

-- Gets out of the vehicle the character is in, or into the nearest one: the driver's seat, or a
-- car's passenger seat if someone is driving.
function M.enter()
  local s = storage.f3d
  local c = puppet.get()
  if not c then
    return
  end
  local v = puppet.vehicle(c)
  if v then
    s.drive = nil
    stop_riding(c)
    if v.type == "car" and not is_driver(v, c) then
      v.set_passenger(nil)
    else
      v.set_driver(nil)
    end
    return
  end
  v = nearest_vehicle(c)
  if not v then
    return puppet.message("No vehicle nearby")
  end
  if v.force ~= c.force and v.force.name ~= "neutral" then
    return puppet.message("That vehicle belongs to someone else")
  end
  if not v.get_driver() then
    v.set_driver(c)
  elseif v.type == "car" and not v.get_passenger() then
    v.set_passenger(c)
  else
    return puppet.message("That vehicle is full")
  end
  if puppet.vehicle(c) ~= v then
    puppet.message("Can't get in")
  end
end

-- a: 0 nothing, 1 accelerate, 2 brake, 3 reverse; s: -1 left, 0 straight, 1 right. Both 0 stops.
function M.drive(cmd)
  local s = storage.f3d
  local a = math.floor(tonumber(cmd.a) or 0)
  local d = math.floor(tonumber(cmd.s) or 0)
  if not (ACCELERATION[a] and DIRECTION[d]) or (a == 0 and d == 0) then
    s.drive = nil
    return
  end
  local drive = s.drive or {}
  drive.a, drive.d = a, d
  drive.until_tick = game.tick + HOLD_TICKS
  s.drive = drive
end

---------------------------------------------------------------------------------------------

function M.tick()
  local s = storage.f3d
  local c = puppet.get()
  if not c then
    return
  end
  local drive = s.drive
  if drive and game.tick > drive.until_tick then
    s.drive = nil
    drive = nil
  end
  local v = puppet.vehicle(c)
  if not (v and drive) then
    if s.riding then
      stop_riding(c)
      s.riding = nil
    end
    return
  end
  c.riding_state = {
    acceleration = defines.riding.acceleration[ACCELERATION[drive.a]],
    direction = defines.riding.direction[DIRECTION[drive.d]],
  }
  s.riding = true
  if drive.a ~= 0 then
    if v.type == "locomotive" then
      -- A train only takes the driver's input in manual mode, as when a player starts driving.
      pcall(function()
        if not v.train.manual_mode then
          v.train.manual_mode = true
        end
      end)
    end
    if not drive.warned and out_of_fuel(v) then
      drive.warned = true
      puppet.message("No fuel")
    end
  end
end

-- After a handshake or when the client leaves. The character stays in its vehicle.
function M.reset()
  local s = storage.f3d
  s.drive = nil
  local c = s.puppet
  if s.riding and c and c.valid then
    stop_riding(c)
  end
  s.riding = nil
end

return M
