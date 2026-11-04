-- Items on belts near the client's camera, a few times a second. Positions come from the game
-- (`get_line_item_position`), so curves, splitters and undergrounds need no geometry here; the
-- client glides each item, tracked by its `unique_id`, between updates.
--
-- This is the bridge's busiest module on a big base: reading every item near the focus, and
-- writing them out, in the tick an update was due cost 40-75 ms on the owner's save at its
-- busiest belts (5,600 items), the server's worst tick. So an update is read over several ticks,
-- a few milliseconds a tick (a round): belts are found a band of rings at a time from the focus
-- outwards, their items read and the message text written as they go, timed to end on the tick
-- the update is sent. Each item is carried on from the tick it was read to the update's tick at
-- the speed it moved between its last two reads, so the update is one moment of the game.
--
-- Lanes that didn't change aren't read again (for a client that says `bl` in its hello). On a busy
-- base most lanes are backed up: on the owner's save at its busiest belts 86% of 3,352 lanes held
-- the same items in the same places between two reads seconds apart, 11% were empty and only 3-5%
-- moved (2.1.23). Reading a lane's items costs about 11 us; its count (`#line`) and its front and
-- back items' positions (`get_item_position`) about 2. So each lane is checked that cheaply first,
-- and read in full only when the check differs from the last read, or once more after a change to
-- see that it has settled, or every LANE_REFRESH updates; the client keeps a lane's items until it
-- is sent again (`ln`) or dropped (`dl`). (Factorio itself stores a lane as the gaps between its
-- items and touches only what changes: FFF #176.)
--
-- Multiplayer: what decides when and how much is read (the round: where it got to, its belts,
-- the counts; each lane's last check, storage.f3d.bl) lives in storage and changes only from
-- on_tick, from game reads. What is sent (the items read so far, their last positions, the text)
-- is module-local: a peer that loaded mid-round only sends less, and only the host sends at all.

local spoilage = require("scripts.spoilage")
local registry = require("scripts.registry")
local transport = require("scripts.transport")
local world = require("scripts.world")
local map = require("scripts.map")
local rate = require("scripts.rate")

local M = {}

local floor = math.floor
local ceil = math.ceil

-- Items a `bi` part holds (a field for tests).
M.items_per_message = 300
-- A fully compressed 48x48 area is ~18k items. Past this the square is made smaller rather than
-- stalling the game: belts are read from the focus outwards, ring by ring, and the update stops at
-- the last whole ring, saying so in `fr`, so the far lane icons take over from there. (Cut short
-- in the order Factorio lists belts, whole patches of a dense base went bare: items neither drawn
-- nor shown as far icons.)
M.max_items = 6000
-- Every lane checked counts one towards the cap as well as its items: a sparse area of empty belts
-- costs a check a lane, and the moving area may reach as far as the client draws belt items.
M.lane_weight = 1
-- The cap's edge holds still (owner: the two zones went back and forth standing still, as the count
-- near the cap moved by a few items each update): the last update's edge is kept while its rings
-- hold up to KEEP times the cap, and it grows only by rings that fit within GROW times the cap.
local KEEP, GROW = 1.25, 0.85
-- A belt line that moved on by whole slots looks the same to the cheap check on every belt (the
-- items shuffled forward one place each), so every lane is held; when one of them is read in full
-- later (a refresh, a change) it lists items the client still has on the lane behind, which then
-- showed one item short until its own read (owner: items "stop and jump", lines not moving together
-- "over time"). So a lane read in full whose front or back item is another one than at its last
-- full read has the same lane of the belts either side (belt_neighbours) read in full too, in the
-- same update, and so on along the line as far as the items shifted. At most FORCE_MAX such lanes an update.
local FORCE_MAX = 4000
-- Factorio's utility constant max_belt_stack_size: a stack inserter puts up to 4 items in one place.
local MAX_STACK = 4

-- How much is read a tick, in work units of 1.5-2.5 us (2.1.23, the owner's save at its busiest
-- belts): an item read is one, written out three more, one more off a straight belt (the game is
-- asked for its position); a belt and each of its transport lines cost a few (API calls), and a
-- belt found one. A round takes as many ticks as its units fill. Only what the game holds is
-- counted, never what this peer happens to have written, so every peer reads the same slices.
M.units_per_tick = 1000
local BELT_UNITS = 2
local LINE_UNITS = 2
local OFF_STRAIGHT_UNITS = 1
local WRITE_UNITS = 3
local FIND_UNITS = 5  -- per find_entities_filtered call, besides 1 per belt found
-- Belts are found a band of this many rings at a time, so a round cut short (the cap, or time)
-- never looked for the belts it doesn't read.
local BAND = 4
-- On the tick an update is due, whatever is left of the round is read up to this many times a
-- tick's units; past it the square shrinks to the last whole ring read (`fr`), as at the cap.
local DUE_BURST = 2
-- A lane checked by its count and end items costs about this many units (#line and two
-- get_item_position, about 2 us in 2.1.23).
local CHECK_UNITS = 1
-- Every lane is read in full at least every this many updates even when it looks the same (on a
-- busy base updates come every 12-30 ticks: 15-30 s): the
-- client may have missed it (bi isn't resent), or its items changed kind without moving.
M.lane_refresh = 64
-- Lane keys: unit number * LANE_KEYS + line index (a splitter has 8 lines).
local LANE_KEYS = 8
-- An item moving faster than this (tiles a tick) between two reads was moved some other way.
local FASTEST = 0.2
-- A lane flowing full looks exactly the same whenever its items moved a whole number of item gaps
-- (0.25 on a full lane) since the last check: a turbo belt every 2 ticks, red every 4, yellow and
-- blue every 8. Checked every 12 or 24 ticks, full belts that flowed were held still on the client
-- (seen in 2.1.23). So rounds start a tick earlier every other update (the time between two checks
-- of a lane is then odd: never a whole number of gaps at these speeds), and a check whose time is
-- a whole number of gaps anyway (a round read over several ticks, other mods' speeds) reads the
-- lane in full rather than trusting it. BLIND is how near a whole number of gaps counts.
M.lane_jitter = true
local GAP = 0.25
local BLIND = 0.02

-- Underground belts also hold the items travelling under the ground. Those belong to the
-- entrance's lines but sit outside its tile, so anything outside the entity is dropped.
local function inside(box, x, y)
  return x >= box.left_top.x - 0.05 and x <= box.right_bottom.x + 0.05
    and y >= box.left_top.y - 0.05 and y <= box.right_bottom.y + 0.05
end

-- unique_id -> {item id, spoils, quality, x, y, tick read, speed x, speed y, carried}: an item
-- keeps its id while it rides (verified in 2.1.23), and spoiling turns it into a new item. Rebuilt
-- every update from the items seen, so it stays small. The last place an item was read, and when,
-- gives how it moves.
local known = {}
-- Lane key -> the unique ids its last full read sent (kept in `known` while it is held), and
-- lanes whose items have a quality or spoil: those are always read in full for what is sent (bq
-- and bf are whole lists every update), though counted as the check decided.
local lane_uids = {}
local lane_special = {}
-- Unit number -> the belt's LuaTransportLines, for the belts the last round and this one read (a
-- belt not read in a round is forgotten: gone, or out of the square).
local line_cache = {}
local next_cache = {}
-- Lanes checked, held and read in full (for quality or spoiling items, or settling, or changed),
-- and items read, since loading: module-local, for /c probes.
M.counts = { checked = 0, held = 0, blind = 0, special = 0, full = 0, items = 0, belts = 0 }

-- A straight belt's lines run straight along it, so an item's map position is where its line
-- starts plus its position along the belt. Where the lines start, relative to the belt's centre
-- and turned with it, is read from the game on the first straight belt of each update (the
-- same for every straight belt), instead of asking for every item.
local DIR = {}
for d = 0, 15, 4 do
  local a = d / 16 * 2 * math.pi
  DIR[d] = { math.floor(math.sin(a) + 0.5), math.floor(-math.cos(a) + 0.5) }
end

-- {along, across, step} of line i in the belt's own frame (forward, right): where position 0 is,
-- and how far forward one unit of position goes. Both are read, not assumed: in 2.1.23 a line's
-- positions don't run the way the fake API had them.
local function line_starts(belt)
  local d = DIR[belt.direction]
  if not d then
    return nil
  end
  local c = belt.position
  local starts = {}
  for i = 1, 2 do
    local line = belt.get_transport_line(i)
    local p0, p1 = line.get_line_item_position(0), line.get_line_item_position(1)
    local dx, dy = p0.x - c.x, p0.y - c.y
    starts[i] = { dx * d[1] + dy * d[2], -dx * d[2] + dy * d[1], (p1.x - p0.x) * d[1] + (p1.y - p0.y) * d[2] }
  end
  return starts
end

-- For tools/busy_base.py and live_check.py: the positions the shortcut above gives for a
-- straight belt's items next to the game's own, [[x, y, game x, game y], ...].
function M.check_straight(belt)
  local starts = line_starts(belt)
  local d = DIR[belt.direction]
  local c = belt.position
  local out = {}
  for i = 1, 2 do
    local line = belt.get_transport_line(i)
    local s = starts[i]
    for _, item in pairs(line.get_detailed_contents()) do
      local g = line.get_line_item_position(item.position)
      local sx = c.x + d[1] * s[1] - d[2] * s[2]
      local sy = c.y + d[2] * s[1] + d[1] * s[2]
      out[#out + 1] = { sx + d[1] * s[3] * item.position, sy + d[2] * s[3] * item.position, g.x, g.y }
    end
  end
  return out
end

---------------------------------------------------------------------------------------------
-- A round.
--
-- storage.f3d.bi = {m, dues, last, work, round}: m, how many of the job's due ticks (rate.lua) an
-- update takes (more on a big base); dues, due ticks since the last update; last, its tick; work,
-- the last round's units. round = {start, si, fx, fy, r, target (the tick it is meant to be sent
-- on), band (the next band's first ring), last_band, belts and rings (the band being read), i
-- (next belt), ring (being read), ring_items, items (read so far: the cap's count), units, cut
-- (fr when cut short), short (cut short for time), done}.

-- What a round has read, for sending: module-local, keyed by the round's start tick. Items are
-- [unique id, item id, x, y] in `raw` (x, y as read) with their speed and read tick in vx, vy, at,
-- written as text at the target tick into `bodies`, 300 at a time, as they are read; `mark`, the
-- counts where the ring being read began (what a cut goes back to).
local pay = nil
-- Whether the last update sent qualities (one empty `bq` clears them): only what is sent.
local bq_sent = false

local function payload(round)
  return pay and pay.id == round.start and pay or nil
end

-- The next band of rings: finds its belts (in up to four rectangles round the ones before) and
-- lists them nearest ring first. Returns the units it cost.
local function find_band(round, surface)
  local types = registry.belt_types()
  local a = round.band
  local b = math.min(a + BAND, round.r)
  local last = b >= round.r
  local fx, fy = round.fx, round.fy
  local areas
  if a == 0 then
    areas = { { { fx - b, fy - b }, { fx + b, fy + b } } }
  else
    areas = {
      { { fx - b, fy - b }, { fx + b, fy - a } },
      { { fx - b, fy + a }, { fx + b, fy + b } },
      { { fx - b, fy - a }, { fx - a, fy + a } },
      { { fx + a, fy - a }, { fx + b, fy + a } },
    }
  end
  -- A belt is found by every rectangle its box touches, so it is kept only in the band its centre
  -- is in (the last band keeps what sticks out past the square, as one search of it did).
  local buckets, seen, top, units = {}, {}, a, 0
  for _, area in ipairs(areas) do
    units = units + FIND_UNITS
    if #types > 0 then
      for _, belt in pairs(map.view_only(surface.find_entities_filtered({ area = area, type = types }))) do
        units = units + 1
        local p = belt.position
        local dx, dy = p.x - fx, p.y - fy
        local ring = floor(math.max(dx < 0 and -dx or dx, dy < 0 and -dy or dy))
        local id = belt.unit_number
        if ring >= a and (last or ring < b) and not seen[id] then
          seen[id] = true
          local list = buckets[ring]
          if not list then
            list = {}
            buckets[ring] = list
            if ring > top then
              top = ring
            end
          end
          list[#list + 1] = belt
        end
      end
    end
  end
  local belts, rings = {}, {}
  for ring = a, top do
    for _, belt in ipairs(buckets[ring] or {}) do
      belts[#belts + 1] = belt
      rings[#belts] = ring
    end
  end
  round.belts, round.rings, round.i = belts, rings, 1
  round.band, round.last_band = b, last
  return units
end

-- Writes the next part's text: up to M.items_per_message items at the target tick, delta-coded
-- for a `z` client (transport.encode_groups, written straight from what was read).
local function write_part(p, target)
  local raw, vx, vy, at = p.raw, p.vx, p.vy, p.at
  local first = p.written + 1
  local last = math.min(#vx, p.written + M.items_per_message)
  local out, n = {}, 0
  local z, small = transport.compact(), transport.small
  local pu, pi, px, py = 0, 0, 0, 0
  local st, sts = p.st, nil
  for j = first, last do
    local m = j * 4
    local dt = target - at[j]
    local u, i = raw[m - 3], raw[m - 2]
    if st[j] then
      sts = sts or {}
      sts[#sts + 1] = u
      sts[#sts + 1] = st[j]
    end
    local x = floor((raw[m - 1] + vx[j] * dt) * 256 + 0.5)
    local y = floor((raw[m] + vy[j] * dt) * 256 + 0.5)
    if z and j > first then
      local du, di, dx, dy = u - pu, i - pi, x - px, y - py
      out[n + 1], out[n + 2], out[n + 3], out[n + 4] = small[du] or du, small[di] or di, small[dx] or dx, small[dy] or dy
    else
      out[n + 1], out[n + 2], out[n + 3], out[n + 4] = u, i, x, y
    end
    n = n + 4
    pu, pi, px, py = u, i, x, y
  end
  p.bodies[#p.bodies + 1] = table.concat(out, ",")
  -- Stacks of more than one item (a stack inserter's), by unique id; an item not listed is one.
  local tail = sts and (',"st":[' .. table.concat(sts, ",") .. "]") or ""
  if p.lanes then
    -- Which lane each run of this part's items came from: [key, count, ...] (0: none, an item
    -- carried on); lanes read with nothing to send since the part before come first, with count 0.
    -- (Only the first part had them, and lanes read later in the round, the lines read along their
    -- length at its end above all, were never told: the client kept their old items, a belt one
    -- short or doubled.)
    local lk, ln, m = p.lk, {}, 0
    local part = #p.bodies
    for x = (p.emptied_upto[part - 1] or 0) + 1, #p.emptied do
      ln[m + 1], ln[m + 2] = p.emptied[x], 0
      m = m + 2
    end
    p.emptied_upto[part] = #p.emptied
    local j = first
    while j <= last do
      local key, c = lk[j], 0
      while j <= last and lk[j] == key do
        c = c + 1
        j = j + 1
      end
      ln[m + 1], ln[m + 2] = key, c
      m = m + 2
    end
    p.tails[#p.bodies] = ',"ln":[' .. table.concat(ln, ",") .. "]" .. tail
  elseif tail ~= "" then
    p.tails[#p.bodies] = tail
  end
  p.written = last
end

-- Reads one belt's items into the round (and `p`, what is sent, when this peer has it). Returns
-- the items counted and the units spent.
local function read_belt(belt, p, now, round, lanes, force)
  local items, units, held = 0, 0, 0
  local unit = belt.unit_number
  -- A belt's line objects are kept from round to round (getting them cost about 2 us a line, as
  -- much as the check), and its kind, shape and place read only for a lane read in full.
  local lines = unit and line_cache[unit]
  if not lines then
    lines = {}
    for i = 1, belt.get_max_transport_line_index() do
      lines[i] = belt.get_transport_line(i)
    end
    -- Tiles (line positions) its items move a tick: a prototype's, the same on every peer.
    lines.v = belt.prototype.belt_speed
    if unit then
      line_cache[unit] = lines
    end
  end
  if unit then
    next_cache[unit] = lines
  end
  local known_belt, underground, box, d, c, starts = false, false, nil, nil, nil, nil
  local raw, vx, vy, at, seen = p and p.raw, p and p.vx, p and p.vy, p and p.at, p and p.seen
  for i = 1, #lines do
    if force and not force[i] then
      goto next_line
    end
    do
    units = units + LINE_UNITS
    local line = lines[i]
    local key, full = nil, true
    if lanes and unit then
      -- The cheap check first (storage: only game reads decide it).
      key = unit * LANE_KEYS + i
      -- n counts stacks (2.1.23: a stack inserter's stack of up to 4 is one entry); the lane's
      -- items too, since an inserter taking part of a stack moves nothing.
      local n = #line
      local p1, pn, total = -1, -1, 0
      if n > 0 then
        p1 = line.get_item_position(1)
        pn = n > 1 and line.get_item_position(n) or p1
        total = line.get_item_count()
      end
      units = units + CHECK_UNITS
      local rec = lanes[key]
      -- rec: {count, front, back, round checked, settled, tick checked, items}
      local same = rec and rec[6] and rec[1] == n and rec[2] == p1 and rec[3] == pn and rec[7] == total
      local blind = false
      if same and n > 0 then
        -- Would a lane flowing at its belt's speed look the same after this long? (Whole gaps on a
        -- full lane, or whole average gaps between its end items on one evenly filled.)
        local moved = (now - rec[6]) * (lines.v or 0)
        local slots = moved / GAP
        blind = slots - floor(slots + 0.5) < BLIND and slots - floor(slots + 0.5) > -BLIND
        if not blind and n > 1 and pn ~= p1 then
          slots = moved * (n - 1) / (pn > p1 and pn - p1 or p1 - pn)
          blind = slots - floor(slots + 0.5) < BLIND and slots - floor(slots + 0.5) > -BLIND
        end
      end
      local counts = M.counts
      counts.checked = counts.checked + 1
      if force then
        if not rec then
          rec = { n, p1, pn, 0, false }
          lanes[key] = rec
        end
      elseif blind then
        counts.blind = counts.blind + 1  -- read in full, settled or not as it was
      elseif same and rec[5] and (key + round.count) % M.lane_refresh ~= 0 then
        full = false
        held = held + n
        counts.held = counts.held + 1
      elseif same then
        rec[5] = true  -- read again unchanged: settled, held from the next update
      else
        -- Changed: a fresh record, keeping the end items of its last full read (FORCE_MAX).
        rec = { n, p1, pn, 0, false, nil, nil, rec and rec[8], rec and rec[9], rec and rec[10] }
        lanes[key] = rec
      end
      rec[4] = round.start
      rec[6] = now
      rec[7] = total
      local keys = round.ring_keys
      keys[#keys + 1] = key
      if not full and p then
        if lane_special[key] then
          full = "send"  -- read for what is sent only: counted as held
          M.counts.special = M.counts.special + 1
        else
          -- Its items stay as the client has them: kept in `known`, not carried on as missing
          -- (and written after all if a lane read in full later this update has them: held_only).
          local seen, held_only = p.seen, p.held_only
          for _, uid in ipairs(lane_uids[key] or {}) do
            seen[uid] = known[uid]
            held_only[uid] = true
          end
        end
      end
    end
    if full then
    if not known_belt then
      known_belt = true
      underground = belt.type == "underground-belt"
      box = underground and belt.selection_box
      if belt.type == "transport-belt" and belt.belt_shape == "straight" then
        d = DIR[belt.direction]
        if p and d and not p.starts then
          p.starts = line_starts(belt)
        end
        c = belt.position
      end
      starts = p and p.starts
    end
    local s = d and starts and starts[i]
    -- The start of this line on the map, and its direction.
    local sx, sy, fx, fy
    if s then
      sx = c.x + d[1] * s[1] - d[2] * s[2]
      sy = c.y + d[2] * s[1] + d[1] * s[2]
      fx, fy = d[1] * s[3], d[2] * s[3]
    end
    M.counts.full = M.counts.full + 1
    local sent_uids, special = key and p and {}, false
    local wrote_from = p and #p.raw
    local counted = full ~= "send"
    local first_uid, last_uid = 0, 0
    local held_only = p and p.held_only
    for _, item in pairs(line.get_detailed_contents()) do
      if first_uid == 0 then
        first_uid = item.unique_id
      end
      last_uid = item.unique_id
      -- The hottest loop in the bridge: plain locals, few tables. (What is counted depends only
      -- on the game, never on `p`, so every peer's round goes the same way.)
      local x, y
      if s then
        x, y = sx + fx * item.position, sy + fy * item.position
      elseif not d then
        local q = line.get_line_item_position(item.position)
        x, y = q.x, q.y
        if counted then
          units = units + OFF_STRAIGHT_UNITS
        end
      end
      if not underground or inside(box, x, y) then
        if counted then
          items = items + 1
        end
        local uid = item.unique_id
        -- An item that moved on to a belt read later in the round is sent once, from its first read
        -- (one only kept with a held lane is written here: it moved on to this lane).
        if p and (not seen[uid] or held_only[uid]) then
          held_only[uid] = nil
          local k = known[uid]
          local ux, uy = 0, 0
          if not k then
            local name = item.stack.name
            -- An item's quality doesn't change while it rides, so it is read once too.
            k = { registry.item_id(name), spoilage.spoils(name), item.stack.quality.name }
          elseif k[6] then
            local dt = now - k[6]
            if dt > 0 and dt <= 240 then
              ux, uy = (x - k[4]) / dt, (y - k[5]) / dt
              if ux > FASTEST or ux < -FASTEST or uy > FASTEST or uy < -FASTEST then
                ux, uy = 0, 0
              end
            end
          end
          k[4], k[5], k[6], k[7], k[8], k[9] = x, y, now, ux, uy, nil
          local stack = item.stack.count
          k[10] = stack > 1 and (stack < MAX_STACK and stack or MAX_STACK) or nil
          seen[uid] = k
          local m = #raw
          raw[m + 1] = uid
          raw[m + 2] = k[1]
          raw[m + 3] = x
          raw[m + 4] = y
          local j = m / 4 + 1
          vx[j], vy[j], at[j] = ux, uy, now
          p.lk[j] = key or 0
          p.st[j] = k[10]
          if sent_uids then
            sent_uids[#sent_uids + 1] = uid
            special = special or k[2] or k[3] ~= "normal"
          end
          if k[2] then
            local fr = spoilage.freshness(item.stack)
            if fr then
              local fresh = p.fresh
              fresh[#fresh + 1] = uid
              fresh[#fresh + 1] = fr
            end
          end
          if k[3] ~= "normal" then
            p.quality[#p.quality + 1] = { uid, k[3] }
          end
        elseif sent_uids and seen[uid] then
          -- Read already this round (it moved on to this lane): it belongs here now.
          sent_uids[#sent_uids + 1] = uid
        end
      end
    end
    -- Read in full: if its end items are other items than last time, the line moved on by whole
    -- slots and the lanes either side are read in full too (FORCE_MAX). From game reads only.
    local rec = key and lanes and lanes[key]
    if rec then
      local shifted = rec[8] ~= nil and (rec[8] ~= first_uid or rec[9] ~= last_uid)
      rec[8], rec[9], rec[10] = first_uid, last_uid, round.start
      if shifted and (round.forced or 0) < FORCE_MAX then
        -- The belts either side (belt_neighbours: LuaTransportLine's input_lines and output_lines
        -- name the ends of the whole segment of straight belts in 2.1.23, skipping the belts between).
        local q = round.force_q or {}
        round.force_q = q
        -- A splitter's or an underground's lanes don't line up with a belt's by number (a belt's
        -- lane 1 feeds a splitter's 3; a splitter moves items from its lane 4 to its 6): with
        -- more than two lanes on either side, every lane of it is read (2.1.23, the owner's save).
        if #lines > 2 then
          for o = 1, #lines do
            if o ~= i then
              q[#q + 1] = { belt, o }
            end
          end
        end
        local ok, nb = pcall(function() return belt.belt_neighbours end)
        if ok and nb then
          for _, list in pairs({ nb.inputs or {}, nb.outputs or {} }) do
            for _, e in pairs(list) do
              local count = #lines > 2 and 8 or (e.valid and e.get_max_transport_line_index() or 0)
              if count > 2 then
                for o = 1, count do
                  q[#q + 1] = { e, o }
                end
              else
                q[#q + 1] = { e, i }
              end
            end
          end
        end
      end
    end
    if sent_uids then
      lane_uids[key] = sent_uids
      lane_special[key] = special or nil
      if #p.raw == wrote_from then
        p.emptied[#p.emptied + 1] = key
      end
    end
    end
    end
    ::next_line::
  end
  -- What counts towards the cap: its items (stacks), held ones too, and a weight a lane.
  return items + held + #lines * M.lane_weight, units + items * (1 + WRITE_UNITS)
end

-- Ends the round at the start of ring `ring`: what was read of it is dropped, and `fr` says the
-- square reaches only that far.
local function cut(round, ring)
  round.cut, round.done = ring, true
  round.items = round.ring_items
  -- Lanes checked in the ring that is dropped are read in full next time: the client won't have
  -- what they hold now.
  local lanes = storage.f3d.bl
  if lanes then
    for _, key in ipairs(round.ring_keys) do
      lanes[key] = nil
    end
  end
  local p = payload(round)
  if not p then
    return
  end
  local n = p.mark[1]
  for j = n * 4 + 1, #p.raw do
    p.raw[j] = nil
  end
  for j = n + 1, #p.vx do
    p.vx[j], p.vy[j], p.at[j], p.lk[j], p.st[j] = nil, nil, nil, nil, nil
  end
  for j = p.mark[4] + 1, #p.emptied do
    p.emptied[j] = nil
  end
  for j = p.mark[2] + 1, #p.fresh do
    p.fresh[j] = nil
  end
  for j = p.mark[3] + 1, #p.quality do
    p.quality[j] = nil
  end
  -- Parts already written that reach into the dropped ring are written again.
  if p.written > n then
    local keep = floor(n / M.items_per_message)
    for j = keep + 1, #p.bodies do
      p.bodies[j], p.tails[j], p.emptied_upto[j] = nil, nil, nil
    end
    if (p.emptied_upto[keep] or 0) > #p.emptied then
      p.emptied_upto[keep] = #p.emptied
    end
    p.written = keep * M.items_per_message
  end
end

-- Writes out every whole part read (all that is left with `all`).
local function write_parts(p, target, all)
  while #p.vx - p.written >= M.items_per_message or (all and #p.vx > p.written) do
    write_part(p, target)
  end
end

-- One lane queued by a line that moved on (read_belt's FORCE_MAX): {belt, line index}, read in
-- full if it is within the square and wasn't read in full this round. Returns what read_belt does,
-- or 0, 0.
local function force_lane(entry, p, now, round)
  local belt, i = entry[1], entry[2]
  if not (belt and belt.valid and belt.unit_number) or i > belt.get_max_transport_line_index() then
    return 0, 0
  end
  local pos = belt.position
  local dx, dy = pos.x - round.fx, pos.y - round.fy
  local ring = floor(math.max(dx < 0 and -dx or dx, dy < 0 and -dy or dy))
  if ring >= (round.cut or round.r) then
    return 0, 0
  end
  local lanes = storage.f3d.bl
  if not lanes then
    return 0, 0
  end
  local rec = lanes[belt.unit_number * LANE_KEYS + i]
  if rec and rec[10] == round.start then
    return 0, 0  -- read in full already this round
  end
  round.forced = (round.forced or 0) + 1
  if round.forced > FORCE_MAX then
    return 0, 0
  end
  return read_belt(belt, p, now, round, lanes, { [i] = true })
end

-- Reads belts (finding the next band's when one runs out) until `budget` units are spent or the
-- round is done.
local function read(round, budget, now, surface)
  local p = payload(round)
  -- The client's Belt updates (-1: Unlimited, every belt within its distance), else the mod's own.
  local cap = storage.f3d.bi_cap or M.max_items
  if cap < 0 then
    cap = math.huge
  end
  local spent = 0
  while spent < budget do
    if round.i > #round.belts then
      if round.last_band then
        -- Lanes along lines that moved on, read in full before the update goes (see FORCE_MAX).
        local q = round.force_q
        if q and #q > 0 then
          local nl = table.remove(q)
          spent = spent + BELT_UNITS
          round.units = round.units + BELT_UNITS
          local n, units = force_lane(nl, p, now, round)
          round.items = round.items + n
          round.units = round.units + units
          spent = spent + units
          if p then
            write_parts(p, round.target)
          end
          goto continue
        end
        round.done = true
        return
      end
      local units = find_band(round, surface)
      round.units = round.units + units
      spent = spent + units
    else
      local ring = round.rings[round.i]
      if ring ~= round.ring then
        round.ring, round.ring_items, round.ring_keys = ring, round.items, {}
        if p then
          p.mark = { #p.raw / 4, #p.fresh, #p.quality, #p.emptied }
        end
      end
      local belt = round.belts[round.i]
      round.i = round.i + 1
      spent = spent + BELT_UNITS
      round.units = round.units + BELT_UNITS
      if belt.valid then
        local n, units = read_belt(belt, p, now, round, storage.f3d.bl)
        round.items = round.items + n
        round.units = round.units + units
        spent = spent + units
        local limit = cap
        if round.prev then
          limit = ring < round.prev and cap * KEEP or cap * GROW
        end
        if round.items > limit then
          -- Back to the last whole ring: everything inside it, nothing of this one.
          cut(round, ring)
          return
        end
        -- Written out as they come (a cut writes again what it drops): their cost is counted
        -- with their reading, so the text is spread over the round's ticks too.
        if p then
          write_parts(p, round.target)
        end
      end
    end
    ::continue::
  end
end

-- On the tick an update is due and the round isn't finished: the ring being read is left out
-- unless it was just finished.
local function cut_short(round)
  round.short = true
  local next_ring = round.i <= #round.belts and round.rings[round.i] or round.band
  if next_ring ~= round.ring then
    round.cut, round.done = next_ring, true
  else
    cut(round, round.ring)
  end
end

-- Sends the round as one update, stamped `now`. What was written out for another tick (the
-- `rate` level changed the job's ticks meanwhile) is written again.
local function emit(round, now, period, lanes_left)
  local p = payload(round)
  pay = nil
  line_cache, next_cache = next_cache, {}
  if not p then
    return -- loaded mid-round: nothing to send this time
  end
  local k = now
  if round.target ~= now then
    p.bodies, p.tails, p.written, p.emptied_upto = {}, {}, 0, {}
  end
  -- An item that moved from a belt read later in the round on to one read earlier was read on
  -- neither. Missing from an update, the client would stop it for one and then jump it on, so an
  -- item read last time and not this time is carried on along its way, once, where it would be.
  -- (An item taken off the belt goes on for one update too, and then is gone.)
  local edge = floor(round.cut or round.r)
  local seen, raw, vx, vy, at = p.seen, p.raw, p.vx, p.vy, p.at
  for uid, c in pairs(known) do
    if not seen[uid] and not c[9] and c[6] and c[7] then
      local dt = k - c[6]
      local x, y = c[4] + c[7] * dt, c[5] + c[8] * dt
      if math.abs(x - round.fx) < edge and math.abs(y - round.fy) < edge then
        c[9] = true
        seen[uid] = c
        local m = #raw
        raw[m + 1], raw[m + 2], raw[m + 3], raw[m + 4] = uid, c[1], c[4], c[5]
        local j = m / 4 + 1
        vx[j], vy[j], at[j] = c[7], c[8], c[6]
        p.lk[j] = 0
        p.st[j] = c[10]
      end
    end
  end
  write_parts(p, k, true)
  if p.lanes and #p.emptied > (p.emptied_upto[#p.bodies] or 0) then
    -- Lanes read with nothing to send after the last part: one more part, with no items.
    local ln = {}
    for x = (p.emptied_upto[#p.bodies] or 0) + 1, #p.emptied do
      ln[#ln + 1] = p.emptied[x] .. ",0"
    end
    p.bodies[#p.bodies + 1] = ""
    p.tails[#p.bodies] = ',"ln":[' .. table.concat(ln, ",") .. "]"
    p.emptied_upto[#p.bodies] = #p.emptied
  end
  known = seen
  if p.lanes then
    -- Lanes no longer read (out of the square, their belt gone): the client drops their items.
    local dropped = {}
    for key, rec in pairs(lanes_left or {}) do
      dropped[#dropped + 1] = key
    end
    table.sort(dropped)
    for _, key in ipairs(dropped) do
      lane_uids[key], lane_special[key] = nil, nil
    end
    p.tails[1] = (p.tails[1] or ',"ln":[]') .. ',"dl":[' .. table.concat(dropped, ",") .. "]"
  end
  -- Like `mv`, every update is the full list, split into parts that share the tick `k`. Each part
  -- says which square it covers, so the client hands over to the far lane icons exactly where
  -- these items stop rather than round its own focus, which runs ahead while panning, and
  -- `p`, the ticks between updates, so the client draws items far enough behind to glide evenly.
  transport.send_parts("bi", k, p.bodies,
    ',"fx":' .. world.fixed(round.fx) .. ',"fy":' .. world.fixed(round.fy) .. ',"fr":' .. floor(round.cut or round.r) .. ',"p":' .. period,
    p.tails)
  -- Quality (Space Age) only where some item has one, plus one empty list to clear it.
  local quality, fresh = p.quality, p.fresh
  if #quality > 0 or bq_sent then
    transport.send_now({ t = "bq", l = quality })
  end
  bq_sent = #quality > 0
  -- Only where something spoils, so other bases send nothing extra.
  local per = 600  -- numbers a part: 300 items
  local parts = math.ceil(#fresh / per)
  for part = 1, parts do
    local slice = {}
    for i = (part - 1) * per + 1, math.min(part * per, #fresh) do
      slice[#slice + 1] = fresh[i]
    end
    transport.send_now({ t = "bf", part = part, parts = parts, l = slice })
  end
end

-- Tiles round the focus within which every item is sent: the client's choice (`bfar` n) if it
-- made one, as it asked (owner: the setting goes as far as it says, no other cap than its own Belt
-- updates); else the map setting, within the focus radius.
local function near_radius()
  local s = storage.f3d
  if s.near_r then
    return s.near_r
  end
  return math.min(settings.global["f3d-detail-radius"].value, s.focus.r)
end

-- Units read a tick: the client's choice (`bfar` u) if it made one. A big u reads a round in one
-- tick, as before the slices: items update every interval, smooth on curves, at the cost of one
-- long tick per round on a busy base.
local function units_per_tick()
  return storage.f3d.bi_units or M.units_per_tick
end

-- How many ticks a round of `work` units takes.
local function ticks_for(work)
  return math.max(1, ceil(work / units_per_tick()))
end

-- For tests: the round in progress, or nil.
function M.round()
  return storage.f3d.bi and storage.f3d.bi.round
end

function M.tick()
  local r = near_radius()
  local s = storage.f3d
  if r <= 0 then
    s.bi, pay = nil, nil
    return
  end
  local interval = settings.global["f3d-detail-interval"].value
  local b = s.bi
  if not b then
    b = { m = 1, dues = 0, work = 0 }
    s.bi = b
  end
  -- Lanes are kept for a client that keeps them (`bl` in its hello).
  if s.client and s.client.bl then
    s.bl = s.bl or {}
  else
    s.bl = nil
  end
  local now = game.tick
  -- The job's ticks: every detail interval, stretched by the client's `rate` level. An update is
  -- sent on every m-th of them, m as many as a round of this size needs.
  local period = rate.period("bi", interval)
  if rate.due("bi", interval) then
    b.dues = b.dues + 1
  end
  local due = b.dues >= b.m
  local surface = world.surface()
  local round = b.round
  if round and round.si ~= surface.index then
    round, b.round = nil, nil
  end
  -- A round starts as late as it can and still be read by the tick it is due; with lanes kept, a
  -- tick earlier every other update (M.lane_jitter: the time between a lane's checks is then odd).
  local target = b.last and b.last + b.m * period
  local early = (s.bl and M.lane_jitter and (b.count or 0) % 2 == 1) and 1 or 0
  if not round and (due or (target and now >= target - ticks_for(b.work) + 1 - early)) then
    local f = s.focus
    round = { start = now, si = surface.index, fx = f.x, fy = f.y, r = r, target = due and now or target,
      band = 0, belts = {}, rings = {}, i = 1, ring = -1, ring_items = 0, items = 0, units = 0,
      ring_keys = {}, count = b.count or 0, prev = b.fr }
    b.round = round
    pay = { id = now, raw = {}, vx = {}, vy = {}, at = {}, bodies = {}, written = 0, lk = {}, st = {}, tails = {}, emptied = {},
      lanes = s.bl ~= nil,
      fresh = {}, quality = {}, seen = {}, held_only = {}, emptied_upto = {}, mark = { 0, 0, 0 } }
  end
  if round and not round.done then
    read(round, due and units_per_tick() * DUE_BURST or units_per_tick(), now, surface)
    if due and not round.done then
      cut_short(round)
    end
  elseif round and not due and payload(round) then
    -- Read ahead of time: the last part is written now rather than on the tick it is sent.
    write_parts(pay, round.target, true)
  end
  if not due then
    return
  end
  -- What the next round will need, from this one. It takes more due ticks at once when it needs
  -- them; fewer only once it fits well within them, so m doesn't flip back and forth (each change
  -- moves the client's glide). A round cut short for time would have needed more: it is taken as
  -- needing up to twice what it read (by the area it covered), so m catches up in a few rounds.
  local work = round.units
  if round.short and round.cut < round.r then
    work = ceil(round.units * math.min(2, (round.r * round.r) / math.max(1, round.cut * round.cut)))
  end
  local need = ceil(ticks_for(work) / period)
  if need > b.m then
    b.m = need
  elseif need < b.m and ticks_for(work * 1.1) <= (b.m - 1) * period then
    b.m = b.m - 1
  end
  -- Lanes not checked this round are forgotten (and the client told to drop them).
  local left = nil
  if s.bl then
    left = {}
    for key, rec in pairs(s.bl) do
      if rec[4] ~= round.start then
        left[key] = true
      end
    end
    for key in pairs(left) do
      s.bl[key] = nil
    end
  end
  -- Lanes along lines that moved on, not read yet (the cap or time ended the round first): read
  -- now, so the update has whole lines (FORCE_MAX).
  local q = round.force_q
  if q and #q > 0 then
    local p = payload(round)
    while #q > 0 do
      local _, units = force_lane(table.remove(q), p, now, round)
      round.units = round.units + units
    end
    if p then
      write_parts(p, round.target)
    end
  end
  emit(round, now, b.m * period, left)
  b.round, b.dues, b.last, b.work = nil, 0, now, work
  -- Where this update stopped, if the cap stopped it: the next keeps it unless well past the cap.
  b.fr = round.cut and not round.short and floor(round.cut) or nil
  b.count = (b.count or 0) + 1
end


---------------------------------------------------------------------------------------------
-- Belts far away (`bfar`): past the detail radius the client draws each lane as one icon of what
-- it carries, as Factorio's zoomed-out view reads. The client sets how far (`bfar` command, r in
-- tiles, 0 off). Subscribed chunks within r of the focus are read a few dozen belts per tick,
-- round and round, and a chunk is sent only when what its lanes carry changed:
-- {t = "bfar", cx, cy, l = [x, y (1/256 tile), direction, lane 1 item id, lane 2 item id, ...],
-- c = [lane 1 count, lane 2 count, ...]}, 0 for an empty lane; an empty l clears the chunk. The
-- counts (items on that lane of that belt, at most 4) let the client draw a full belt full,
-- and h how high to pile them when there are more items than that (stack inserters' stacks). By
-- items, not stacks: counted by stacks, a lane of a few stacks of 4 drew a few icons with holes
-- between them, which from afar read as gaps on a full belt (owner: "we didn't have gaps in 0.1.1").

-- What a far lane carries changes slowly and is drawn small, so a round over the chunks starts at
-- most every FAR_ROUND_TICKS, reading far_belts_per_tick belts a tick. A belt costs about 12-25 us
-- (two get_contents) on the owner's save, and a busy chunk holds 700: read whole in one tick (and
-- written out at its end), one chunk cost up to 48 ms. So a chunk is read over as many ticks as it
-- needs too.
M.far_belts_per_tick = 100
local FAR_ROUND_TICKS = 180
local FAR_MIN_BELTS = 10
-- Finding a chunk's belts costs about a twentieth of reading them.
local FAR_FIND_PER_BELT = 20
-- Chunks this far past r are read too (a chunk's half diagonal is 23): the round is fixed round the
-- focus where it began, and while the camera pans chunks coming into r must already be there.
local FAR_MARGIN = 48

-- The round in progress (queue, next; cur, the chunk being read: {key, c, belts, i, l, counts}) and
-- what each chunk last sent, per client (storage.f3d is the client being served), changed only
-- from on_tick and commands.
local function far_state()
  local s = storage.f3d
  s.far = s.far or { queue = {}, next = 1, sent = {} }
  return s.far
end

-- A full lane holds 4 items (or stacks) a belt.
local FAR_MAX_COUNT = 4

-- The item a lane carries most of, by id (0: empty), how many icons it gets (its items, at most
-- FAR_MAX_COUNT) and how high they are piled (the items over those icons, rounded up: 1 to MAX_STACK).
local function lane_item(line)
  local best, most, all = nil, 0, 0
  for _, it in pairs(line.get_contents()) do
    all = all + it.count
    if it.count > most then
      best, most = it.name, it.count
    end
  end
  local icons = math.min(all, FAR_MAX_COUNT)
  local pile = icons > 0 and math.min(MAX_STACK, ceil(all / icons)) or 1
  return best and registry.item_id(best) or 0, icons, pile
end

-- Starts reading a chunk: its belts. Returns the chunk and the belts it holds.
local function far_find(surface, types, key, c)
  local x0, y0 = c[1] * 32, c[2] * 32
  local found = surface.find_entities_filtered({ area = { { x0, y0 }, { x0 + 32, y0 + 32 } }, type = types })
  local belts = {}
  for _, belt in pairs(found) do
    local p = belt.position
    if p.x >= x0 and p.x < x0 + 32 and p.y >= y0 and p.y < y0 + 32 then
      belts[#belts + 1] = belt
    end
  end
  return { key = key, c = c, belts = belts, i = 1, l = {}, counts = {}, piles = {} }, #found
end

-- Reads up to `budget` of the chunk's belts; returns how many it read. Each belt's numbers are
-- written as text as it is read: turning a busy chunk's 5,000 numbers into text at its end cost
-- 7 ms in one tick (2.1.23, the owner's save).
local function far_read(cur, budget)
  -- (A chunk begun before piles were read has none yet.)
  cur.piles = cur.piles or {}
  local belts, l, counts, piles = cur.belts, cur.l, cur.counts, cur.piles
  local small = transport.small
  local read = 0
  while read < budget and cur.i <= #belts do
    local belt = belts[cur.i]
    cur.i = cur.i + 1
    read = read + 1
    if belt.valid then
      local p = belt.position
      local a, na, ha = lane_item(belt.get_transport_line(1))
      local b, nb, hb = lane_item(belt.get_transport_line(2))
      if a ~= 0 or b ~= 0 then
        l[#l + 1] = world.fixed(p.x) .. "," .. world.fixed(p.y) .. "," .. small[belt.direction] .. ","
          .. (small[a] or a) .. "," .. (small[b] or b)
        counts[#counts + 1] = small[na] .. "," .. small[nb]
        piles[#piles + 1] = small[ha] .. "," .. small[hb]
        cur.stacked = cur.stacked or ha > 1 or hb > 1
      end
    end
  end
  return read
end

-- A chunk read whole: sent if what its lanes carry changed.
local function far_finish(cur, far_sent)
  local l, counts = table.concat(cur.l, ","), table.concat(cur.counts, ",")
  -- How high each lane's stacks are piled, only where some are (a stack inserter's).
  local h = cur.stacked and #cur.piles == #cur.counts and (',"h":[' .. table.concat(cur.piles, ",") .. "]") or ""
  local sig = l .. ";" .. counts .. h
  if sig ~= (far_sent[cur.key] or ";") then
    far_sent[cur.key] = sig
    transport.send_text("bfar", ',"cx":' .. cur.c[1] .. ',"cy":' .. cur.c[2] .. ',"l":[' .. l .. '],"c":[' .. counts .. "]" .. h)
  end
end

-- {r, n, m, u}: how far (tiles) the client draws belt lanes, 0 stopping them; n, optional, how far
-- every item may be sent moving (MAX_NEAR at most; without n the map setting f3d-detail-radius,
-- within the focus radius); m, optional, the most items (stacks) and lanes an update reads before
-- it stops at the last whole ring (the client's Belt updates; 0: no cap, every belt within n;
-- without m, M.max_items): items move as far out as m allows and the far lane icons start there;
-- u, optional, the units of belt items read a tick (units_per_tick).
local MAX_NEAR = 640
local MIN_CAP, MAX_CAP = 200, 100000

function M.set_far(cmd)
  local s = storage.f3d
  s.far_r = math.max(0, math.min(1024, math.floor(tonumber(cmd.r) or 0)))
  local n = tonumber(cmd.n)
  s.near_r = n and math.max(0, math.min(MAX_NEAR, math.floor(n))) or nil
  local m = tonumber(cmd.m)
  if m == 0 then
    s.bi_cap = -1  -- Unlimited
  else
    s.bi_cap = m and m > 0 and math.max(MIN_CAP, math.min(MAX_CAP, math.floor(m))) or nil
  end
  local u = tonumber(cmd.u)
  s.bi_units = u and u > 0 and math.max(100, math.min(10000000, math.floor(u))) or nil
  local far = far_state()
  far.queue, far.next, far.started, far.cur = {}, 1, nil, nil
end

function M.far_tick()
  local s = storage.f3d
  local r = s.far_r or 0
  local types = registry.belt_types()
  if r <= 0 or #types == 0 or not s.subs then
    return
  end
  local far = far_state()
  if far.next > #far.queue and not far.cur then
    if far.started and game.tick - far.started < FAR_ROUND_TICKS * rate.factor("lanes") then
      return
    end
    far.started = game.tick
    -- The next round: subscribed chunks within r, nearest first; forget chunks no longer subscribed
    -- (the client dropped them, so they are sent again when they come back).
    local f = s.focus
    far.queue, far.next = {}, 1
    for key, c in pairs(s.subs) do
      local dx, dy = c[1] * 32 + 16 - f.x, c[2] * 32 + 16 - f.y
      if dx * dx + dy * dy <= (r + FAR_MARGIN) * (r + FAR_MARGIN) then
        far.queue[#far.queue + 1] = { key, c, dx * dx + dy * dy }
      end
    end
    -- Nearest first; the key breaks ties so every peer sorts the same.
    table.sort(far.queue, function(a, b) return a[3] < b[3] or (a[3] == b[3] and a[1] < b[1]) end)
    for key in pairs(far.sent) do
      if not s.subs[key] then
        far.sent[key] = nil
      end
    end
  end
  local surface = world.surface()
  -- Slowed down (rate.lua): rounds start less often and read fewer belts a tick.
  local per = M.far_belts_per_tick
  local budget = math.max(math.min(FAR_MIN_BELTS, per), math.floor(per / rate.factor("lanes")))
  while budget > 0 do
    local cur = far.cur
    if cur then
      budget = budget - far_read(cur, budget)
      if cur.i > #cur.belts then
        far.cur = nil
        -- A chunk the client dropped meanwhile is left for when it comes back.
        if s.subs[cur.key] then
          far_finish(cur, far.sent)
        end
      end
    elseif far.next <= #far.queue then
      local entry = far.queue[far.next]
      far.next = far.next + 1
      if s.subs[entry[1]] then
        local found
        far.cur, found = far_find(surface, types, entry[1], entry[2])
        budget = budget - math.max(1, ceil(found / FAR_FIND_PER_BELT))
      end
    else
      return
    end
  end
end

-- A new world (handshake, surface change, resync): everything is sent again, and a round of belt
-- items in progress starts over.
function M.far_reset()
  storage.f3d.far = nil
  storage.f3d.bi = nil
  storage.f3d.bl = nil
  pay = nil
end

return M
