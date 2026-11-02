-- One-off answers the client asks for (Factoriopedia's index and pages, the logistic networks, the
-- statistics, the bonuses, the trains overview, the hovered machine's effects...) are queued and
-- answered from on_tick under the work budget (budget.lua), instead of inside the packet's event:
-- a burst of asks (opening Factoriopedia while the map loads) is spread over ticks, and an answer
-- never runs in a tick that has already spent its budget.
--
-- Each kind has a price in work units, fixed, so the queue moves the same way on every peer. The
-- queue keeps the commands as the client sent them (small tables) in storage.f3d.reqs.

local budget = require("scripts.budget")
local transport = require("scripts.transport")

local M = {}

local MAX_QUEUED = 32
local SHARE = 0.6

-- kind -> {handler, price in units}; filled by session.lua.
local kinds = {}

function M.add(name, handler, price)
  kinds[name] = { handler, price }
end

local function queue()
  local s = storage.f3d
  s.reqs = s.reqs or {}
  return s.reqs
end

-- The packet handler for a queued kind: remembers the ask. An ask the same as one still waiting
-- (the same kind and fields but its `q`) takes its place; a full queue drops its oldest.
local function same(a, b)
  for k, v in pairs(a) do
    if k ~= "q" and k ~= "k" and b[k] ~= v and type(v) ~= "table" then
      return false
    end
  end
  for k in pairs(b) do
    if a[k] == nil then
      return false
    end
  end
  return true
end

function M.handler(name)
  return function(msg)
    local q = queue()
    for i, entry in ipairs(q) do
      if entry[1] == name and same(entry[2], msg) then
        q[i] = { name, msg }
        return
      end
    end
    if #q >= MAX_QUEUED then
      table.remove(q, 1)
    end
    q[#q + 1] = { name, msg }
  end
end

function M.length()
  local s = storage.f3d
  return s.reqs and #s.reqs or 0
end

budget.register_queue("reqs", M.length)

function M.reset()
  storage.f3d.reqs = nil
end

-- Answers asks in order while the budget lasts; the first always runs in a tick whose budget is
-- untouched, so a price above the budget can't block the queue.
function M.tick()
  local q = storage.f3d.reqs
  if not q or #q == 0 then
    return
  end
  while #q > 0 do
    local entry = q[1]
    local kind = kinds[entry[1]]
    local price = kind and kind[2] or 1
    if not budget.can(price, "reqs", SHARE) then
      return
    end
    table.remove(q, 1)
    budget.spend(price, "reqs")
    if kind then
      local ok, err = pcall(kind[1], entry[2])
      if not ok then
        log("[factorio-3d-bridge] error answering '" .. entry[1] .. "': " .. tostring(err))
        transport.send_now({ t = "msg", text = "Bridge error: " .. tostring(err) })
      end
    end
  end
end

return M
