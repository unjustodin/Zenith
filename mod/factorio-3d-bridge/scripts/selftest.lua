-- /f3d-selftest: checks in the running game the API the bridge uses on its character that behaves
-- differently with and without a player. On a server tools/live_check.py covers it over RCON, but
-- a single-player game (hybrid mode) has no RCON, so type this in its console instead. One PASS or
-- FAIL line per check; the game is left as it was (the quickbar slot and selection it borrows are
-- put back).

local puppet = require("scripts.puppet")

local M = {}

local TEST_SLOT = { 10, 10 } -- the quickbar slot borrowed in hybrid mode (page 10, slot 10)
local TEST_ITEM = "iron-plate"

local function nearby_entity(c)
  local p = c.position
  for _, e in pairs(c.surface.find_entities_filtered({ area = { { p.x - 8, p.y - 8 }, { p.x + 8, p.y + 8 } } })) do
    if e.valid and e ~= c and e.unit_number and e.type ~= "character" then
      return e
    end
  end
  return nil
end

function M.run()
  local lines = {}
  local function check(ok, what, detail)
    lines[#lines + 1] = (ok and "[Zenith] PASS " or "[Zenith] FAIL ") .. what .. (detail and (" (" .. tostring(detail) .. ")") or "")
  end
  local function try(what, f)
    local ok, result = pcall(f)
    if not ok then
      check(false, what, result)
    end
    return ok, result
  end

  local hybrid = not game.is_multiplayer()
  local c = puppet.get()
  check(c ~= nil, "the bridge has a character", hybrid and "single-player: the player's own" or "server: the bridge's own")
  if not c then
    return lines
  end
  local player = puppet.player_of(c)
  if hybrid then
    check(player ~= nil and player.character == c, "character.player is the player playing it")
  else
    check(player == nil, "the bridge's character has no player")
  end

  local target = nearby_entity(c)
  if target then
    local ok, reach = try("can_reach_entity", function() return c.can_reach_entity(target) end)
    if ok then
      check(type(reach) == "boolean", "can_reach_entity answers", target.name .. ": " .. tostring(reach))
    end
    -- What combat relies on for shooting_selected: selecting an entity on the character (or, in
    -- hybrid mode, on the player).
    local ok2, before = pcall(function() return c.selected end)
    local set = pcall(function() c.selected = target end)
    local now = set and select(2, pcall(function() return c.selected end))
    check(set and now == target, "character.selected can be set", not set and "refused" or nil)
    if hybrid and player and not (set and now == target) then
      local pset = pcall(function() player.selected = target end)
      check(pset and player.selected == target, "player.selected can be set instead")
    end
    pcall(function()
      if ok2 and before then
        c.selected = before
      else
        c.clear_selected_entity()
      end
    end)
  else
    lines[#lines + 1] = "[Zenith] SKIP reach and selection: nothing within 8 tiles of the character to try them on"
  end

  local s = storage.f3d
  if not s.shooting then
    try("shooting_state can be written", function()
      c.shooting_state = { state = defines.shooting.not_shooting, position = c.position }
    end)
  end
  try("walking_state and crafting_queue_size can be read", function()
    return c.walking_state.walking, c.crafting_queue_size
  end)

  if hybrid and player then
    local page, slot = TEST_SLOT[1], TEST_SLOT[2]
    local ok, old = try("get_quick_bar_slot", function() return player.get_quick_bar_slot(page, slot) end)
    if ok then
      local old_name = old and old.filter and old.filter.name or nil
      local set = try("set_quick_bar_slot", function() player.set_quick_bar_slot(page, slot, TEST_ITEM) end)
      if set then
        local now = player.get_quick_bar_slot(page, slot)
        check(now and now.filter and now.filter.name == TEST_ITEM, "the player's quickbar can be read and written")
        pcall(player.set_quick_bar_slot, page, slot, old_name)
      end
    end
    local okp, active = try("get_active_quick_bar_page", function() return player.get_active_quick_bar_page(1) end)
    if okp then
      check(type(active) == "number", "the quickbar's active page can be read", active)
    end
    local cx, cy = math.floor(c.position.x / 32), math.floor(c.position.y / 32)
    local okc, charted = try("is_chunk_charted", function() return c.force.is_chunk_charted(c.surface, { cx, cy }) end)
    if okc then
      check(charted == true, "the player charts the map around the character")
    end
    local oku = try("send_udp without for_player (single-player)", function()
      helpers.send_udp(s.client and s.client.port or 34201, helpers.table_to_json({ t = "msg", text = "Self-test from the game", k = game.tick }))
    end)
    if oku then
      check(true, "send_udp without for_player (single-player)", "a connected client shows \"Self-test from the game\"")
    end
  end
  return lines
end

return M
