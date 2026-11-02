-- Capsules used from the cursor, as a player throws them: grenades, cliff explosives, poison and
-- slowdown capsules, defender/distractor/destroyer capsules at the cursor, fish and health items on
-- the character. LuaItemStack.use_capsule does what the game does (the projectile, the cooldown
-- is the client's), and takes the item when the capsule says so.

local puppet = require("scripts.puppet")

local M = {}

local RANGE_SLACK = 0.5

-- {item, x, y (fixed target)}: throws one of the item at the target if it is in range.
function M.throw(cmd)
  local c = puppet.get()
  if not c then
    return
  end
  local item_name = tostring(cmd.item or "")
  local item = prototypes.item[item_name]
  local ok, action = pcall(function() return item and item.capsule_action end)
  if not ok or not action then
    return puppet.message("Can't use " .. item_name)
  end
  local x, y = tonumber(cmd.x), tonumber(cmd.y)
  if not x or not y then
    return
  end
  local target = { x = x / 256, y = y / 256 }
  if action.type == "use-on-self" then
    target = c.position
  else
    local range = action.attack_parameters and action.attack_parameters.range or 0
    local dx, dy = target.x - c.position.x, target.y - c.position.y
    if range > 0 and math.sqrt(dx * dx + dy * dy) > range + RANGE_SLACK then
      return puppet.message("Out of range")
    end
  end
  local inventory = c.get_main_inventory()
  local stack = inventory and inventory.find_item_stack(item_name)
  if not stack then
    return puppet.message("You have no " .. item_name)
  end
  if action.type == "destroy-cliffs" then
    -- Cliff explosives need a cliff in their radius, like the game's "no cliff there".
    local r = action.radius or 1.5
    if c.surface.count_entities_filtered({ type = "cliff", position = target, radius = r + 1, limit = 1 }) == 0 then
      return puppet.message("No cliff there")
    end
  end
  local used, err = pcall(stack.use_capsule, c, target)
  if not used then
    log("[factorio-3d-bridge] use_capsule: " .. tostring(err))
    puppet.message("Can't use " .. item_name)
  end
end

return M
