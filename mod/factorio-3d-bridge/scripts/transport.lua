-- Moves JSON messages between the mod and the 3D client over localhost UDP.
--
-- Two kinds of outgoing messages:
--   * reliable: world data (chunks, entity adds/removes). Numbered with `r`, queued in
--     storage, and sent at a bounded byte rate. The client asks for a resync on a gap.
--   * immediate: frequent state that the next update replaces anyway (player, movers).

local M = {}

local warned = false

-- On a server only the server instance talks to the client. Single-player has no separate
-- server, so the local instance sends.
local function instance()
  if game.is_multiplayer() then
    return 0
  end
  return nil
end

local function encode(msg)
  msg.k = game.tick
  return helpers.table_to_json(msg)
end

-- Optional arguments are left out rather than passed as nil.
local function send_datagram(port, data)
  local who = instance()
  local ok, err
  if who then
    ok, err = pcall(helpers.send_udp, port, data, who)
  else
    ok, err = pcall(helpers.send_udp, port, data)
  end
  if not ok and not warned then
    warned = true
    log("[factorio-3d-bridge] send_udp failed: " .. tostring(err))
  end
end

-- Sending a datagram costs the game about a millisecond whatever its size (helpers.send_udp in
-- 2.1.23 on a laptop: 0.6 to 2.7 ms for 100 bytes to 60 KB), and the bridge sent one per message:
-- on a big base belt items alone took 20 a tick, 50 ms. A client that says `b` in its hello gets
-- the messages joined by newlines into datagrams of up to BATCH_BYTES, sent when one fills and at
-- the end of each tick (end_tick). Only what is sent depends on this buffer, never storage.
local BATCH_BYTES = 60000
local batches = {}  -- port -> {parts, bytes}

local function send_batch(port)
  local b = batches[port]
  if b then
    batches[port] = nil
    send_datagram(port, table.concat(b[1], "\n"))
  end
end

local function send_raw(port, data)
  local client = storage.f3d and storage.f3d.client
  if not (client and client.b and client.port == port) or #data >= BATCH_BYTES then
    send_batch(port)  -- what was queued goes first
    send_datagram(port, data)
    return
  end
  local b = batches[port]
  if b and b[2] + #data + 1 > BATCH_BYTES then
    send_batch(port)
    b = nil
  end
  if not b then
    b = { {}, 0 }
    batches[port] = b
  end
  b[1][#b[1] + 1] = data
  b[2] = b[2] + #data + 1
end

-- Sends what is waiting for every client; once a tick, after the modules ran.
function M.end_tick()
  for port in pairs(batches) do
    send_batch(port)
  end
end

-- Reads pending packets; each one arrives later as on_udp_packet_received.
function M.poll()
  local who = instance()
  local ok, err
  if who then
    ok, err = pcall(helpers.recv_udp, who)
  else
    ok, err = pcall(helpers.recv_udp)
  end
  if not ok and not warned then
    warned = true
    log("[factorio-3d-bridge] UDP is unavailable (" .. tostring(err) .. "). Launch Factorio with --enable-lua-udp <port>.")
  end
end

-- A message written as JSON text by its module: `fields`, the fields after t and k, starting
-- with a comma (big lists cost far less as table.concat than through helpers.table_to_json).
function M.send_text(t, fields)
  local client = storage.f3d.client
  if client then
    send_raw(client.port, '{"t":"' .. t .. '","k":' .. game.tick .. fields .. "}")
  end
end

function M.send_now(msg)
  local client = storage.f3d.client
  if client then
    send_raw(client.port, encode(msg))
  end
end

function M.send_reliable(msg)
  local s = storage.f3d
  if not s.client then
    return
  end
  s.rseq = s.rseq + 1
  msg.r = s.rseq
  s.outbox_tail = s.outbox_tail + 1
  s.outbox[s.outbox_tail] = msg
end

-- Lists for a client that says `z` in its hello are delta-coded: in each part, every number is
-- the difference from the same field of the record before it. Neighbours in these lists sit
-- next to each other in the world (items lane by lane, inserters and movers by chunk), so the
-- differences are short: belt items take about 12 bytes instead of 27.
local function compact()
  local c = storage.f3d.client
  return c and c.z
end

-- Text of the small numbers delta-coded lists are mostly made of.
local small = {}
for v = -4096, 4096 do
  small[v] = tostring(v)
end

-- For lists written elsewhere (belt items write their parts over the ticks they are read in):
-- whether the client wants them delta-coded, and the text of small numbers.
M.compact = compact
M.small = small

-- The text of one part: numbers first..last of `flat` (groups of `width`), delta-coded for a `z`
-- client.
function M.encode_groups(flat, width, first, last)
  if not compact() then
    return table.concat(flat, ",", first, last)
  end
  local slice = {}
  for i = first, math.min(first + width - 1, last) do
    slice[i - first + 1] = flat[i]
  end
  -- Differences are mostly small: their text comes from a table, which is faster than
  -- table.concat formatting each number.
  for i = first + width, last do
    local v = flat[i] - flat[i - width]
    slice[i - first + 1] = small[v] or v
  end
  return table.concat(slice, ",")
end

-- Sends parts made by encode_groups as `t` messages stamped with tick `k` (at least one, empty).
-- `extra`, optional: more fields for every part, as JSON text starting with a comma; `tails`,
-- optional: more for single parts, by part, written after the list.
function M.send_parts(t, k, bodies, extra, tails)
  local client = storage.f3d.client
  if not client then
    return
  end
  local parts = math.max(1, #bodies)
  local head = '{"t":"' .. t .. '","k":' .. k .. ',"parts":' .. parts .. (client.z and ',"z":1' or "") .. (extra or "") .. ',"part":'
  for part = 1, parts do
    send_raw(client.port, head .. part .. ',"l":[' .. (bodies[part] or "") .. "]" .. (tails and tails[part] or "") .. "}")
  end
end

-- `flat` is groups of `width` numbers; sent as `t` messages of at most `per` groups, parts
-- sharing the tick `k`. An empty list is still sent, as one empty part.
--
-- These are the biggest messages (thousands of belt items ten times a second), and
-- helpers.table_to_json was most of their cost (measured with tools/busy_base.py), so the JSON is
-- written here: the numbers are integers, which table.concat writes as JSON does.
-- `extra`, optional: more fields for every part, as JSON text starting with a comma.
function M.send_groups(t, flat, width, per, extra)
  if not storage.f3d.client then
    return
  end
  local n = per * width
  local bodies = {}
  for part = 1, math.max(1, math.ceil(#flat / n)) do
    bodies[part] = M.encode_groups(flat, width, (part - 1) * n + 1, math.min(part * n, #flat))
  end
  M.send_parts(t, game.tick, bodies, extra)
end

-- `list` is records (arrays) whose first four numbers are delta-coded for a `z` client; anything
-- after them (a mover's orientation) stays as is.
-- `p`, optional: the ticks until the next such list (rate.lua), for the client's gliding.
function M.send_records(t, list, per, p)
  local z = compact()
  local parts = math.max(1, math.ceil(#list / per))
  for part = 1, parts do
    local slice = {}
    local first = (part - 1) * per + 1
    for i = first, math.min(part * per, #list) do
      local rec = list[i]
      if z and i > first then
        local prev, coded = list[i - 1], {}
        for j = 1, #rec do
          coded[j] = j <= 4 and rec[j] - prev[j] or rec[j]
        end
        rec = coded
      end
      slice[#slice + 1] = rec
    end
    M.send_now({ t = t, part = part, parts = parts, z = z and 1 or nil, p = p, l = slice })
  end
end

function M.backlog()
  local s = storage.f3d
  return s.outbox_tail - s.outbox_head + 1
end

function M.reset()
  local s = storage.f3d
  s.rseq = 0
  s.outbox = {}
  s.outbox_head = 1
  s.outbox_tail = 0
end

function M.flush()
  local s = storage.f3d
  local client = s.client
  local budget = settings.global["f3d-bytes-per-tick"].value
  local sent = 0
  while s.outbox_head <= s.outbox_tail and sent < budget do
    local msg = s.outbox[s.outbox_head]
    s.outbox[s.outbox_head] = nil
    s.outbox_head = s.outbox_head + 1
    local data = encode(msg)
    sent = sent + #data
    if client then
      send_raw(client.port, data)
    end
  end
  if s.outbox_head > s.outbox_tail then
    s.outbox_head = 1
    s.outbox_tail = 0
  end
end

return M
