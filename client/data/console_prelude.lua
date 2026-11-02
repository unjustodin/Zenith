local __zr = remote.interfaces["zenith"] and remote
local __zc = __zr and __zr.call("zenith", "character")
local __zp = __zr and __zr.call("zenith", "player")
local function __zprint(m, ...) rcon.print(m) if __zp and __zp.object_name == "LuaPlayer" then __zp.print(m, ...) end end
local function __zgprint(m, ...) rcon.print(m) game.print(m, ...) end
if not __zp then __zp = setmetatable({}, {
  __index = function(_, k)
    if k == "character" then return __zc end
    if k == "print" then return __zprint end
    if k == "name" then return (__zr and __zr.call("zenith", "name")) or "Zenith" end
    if k == "admin" or k == "connected" then return true end
    if not __zc then error("game.player: the 3D client has no character" .. (__zr and "" or " (the Zenith bridge mod isn't loaded)"), 2) end
    local ok, v = pcall(function() return __zc[k] end)
    if ok then return v end
    error("game.player." .. tostring(k) .. ": the 3D client's character has no player here (the bridge's own character, on a map nobody has joined), so game.player stands for its character: use the character's fields", 2)
  end,
  __newindex = function(_, k, v) if __zc then __zc[k] = v end end,
}) end
local __zok, __zerr = pcall(function() %USER%
end) if not __zok then rcon.print("Error: " .. tostring(__zerr)) end
