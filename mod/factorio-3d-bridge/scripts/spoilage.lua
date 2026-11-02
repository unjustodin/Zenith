-- Spoilage (Space Age, Gleba): how fresh a stack of a spoiling item is, for slots, machine screens
-- and belts. Items that don't spoil have no freshness.

local M = {}

-- item name -> true if it spoils. Derived only from prototypes, like registry.lua.
local spoils = {}

local function spoilable(name)
  local s = spoils[name]
  if s == nil then
    local ok, ticks = pcall(function() return prototypes.item[name].get_spoil_ticks() end)
    s = ok and type(ticks) == "number" and ticks > 0
    spoils[name] = s
  end
  return s
end

M.spoils = spoilable

-- Freshness in thousandths (1000 just made, 0 about to spoil), or nil for an item that doesn't
-- spoil. LuaItemStack.spoil_percent is how far it has spoiled.
function M.freshness(stack)
  if not spoilable(stack.name) then
    return nil
  end
  local ok, spoiled = pcall(function() return stack.spoil_percent end)
  if not (ok and type(spoiled) == "number") then
    return nil
  end
  return math.max(0, math.min(1000, math.floor((1 - spoiled) * 1000 + 0.5)))
end

return M
