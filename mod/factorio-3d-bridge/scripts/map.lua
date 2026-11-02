-- The map: a low-resolution chart of an area for a minimap or map view, drawn like Factorio's map
-- (tiles in their map colours, then ore, then trees and rocks, then buildings), and the map's
-- tags. Charts are sent on request, a few chunks per tick, and only for chunks the force has
-- charted, as in the game.
--
-- A player charts the map around themselves; a player-less character doesn't, so while a client
-- is connected the force charts around the bridge's character itself. A headless server with no
-- player connected queues those requests but never carries them out (is_chunk_charted stays false),
-- so the chunks the character has been near are also kept in storage and count as charted.

local transport = require("scripts.transport")
local registry = require("scripts.registry")
local world = require("scripts.world")
local puppet = require("scripts.puppet")
local tracker = require("scripts.tracker")
local budget = require("scripts.budget")

local M = {}

local CHUNK = 32
local MAX_CHUNKS = 1024        -- per request; the nearest to its centre are kept
local CHART_INTERVAL = 120
local CHART_RADIUS = 96        -- tiles charted around a player-less character
local RESOLUTIONS = { 2, 4, 8, 16, 32 } -- tiles per pixel

-- Factorio's own chart colours (core/prototypes/utility-constants.lua, `chart`) for entities
-- whose prototype has no map colour.
local DEFAULT_FRIENDLY = { 0, 97, 145 }
local DEFAULT_ENEMY = { 255, 26, 26 }
local GHOST = { 145, 97, 145 }
local TREE = { 48, 99, 48 }
local FRIENDLY_BY_TYPE = {
  ["ammo-turret"] = { 202, 167, 24 }, ["electric-turret"] = { 217, 46, 46 },
  ["fluid-turret"] = { 235, 117, 26 }, ["transport-belt"] = { 204, 161, 71 },
  ["splitter"] = { 255, 209, 0 }, ["underground-belt"] = { 112, 92, 0 },
  ["solar-panel"] = { 31, 33, 36 }, ["accumulator"] = { 122, 122, 122 }, ["wall"] = { 204, 217, 204 },
  ["gate"] = { 128, 128, 128 }, ["heat-pipe"] = { 58, 130, 172 }, ["pipe"] = { 69, 130, 165 },
  ["pipe-to-ground"] = { 25, 103, 150 }, ["pump"] = { 109, 154, 181 }, ["storage-tank"] = { 131, 166, 188 },
  ["beacon"] = { 7, 68, 104 }, ["generator"] = { 0, 127, 160 }, ["fusion-generator"] = { 0, 127, 160 },
  ["fusion-reactor"] = { 140, 160, 20 }, ["cargo-bay"] = { 78, 146, 198 },
  ["cargo-landing-pad"] = { 103, 178, 235 }, ["space-platform-hub"] = { 103, 178, 235 },
  ["roboport"] = { 211, 207, 136 },
  ["straight-rail"] = { 140, 140, 140 }, ["half-diagonal-rail"] = { 140, 140, 140 },
  ["curved-rail-a"] = { 140, 140, 140 }, ["curved-rail-b"] = { 140, 140, 140 },
  ["legacy-straight-rail"] = { 140, 140, 140 }, ["legacy-curved-rail"] = { 140, 140, 140 },
  ["elevated-straight-rail"] = { 186, 186, 186 }, ["elevated-half-diagonal-rail"] = { 186, 186, 186 },
  ["elevated-curved-rail-a"] = { 186, 186, 186 }, ["elevated-curved-rail-b"] = { 186, 186, 186 },
  ["rail-ramp"] = { 166, 166, 166 },
}

-- Drawing order: a pixel shows the highest layer covering it.
local LAYER_ORE, LAYER_NATURE, LAYER_BUILDING = 1, 2, 3
local NATURE = { tree = true, ["simple-entity"] = true, cliff = true, fish = true, plant = true }

local function rgb(color)
  if not color then
    return nil
  end
  local r, g, b = color.r or color[1] or 0, color.g or color[2] or 0, color.b or color[3] or 0
  local scale = (r > 1 or g > 1 or b > 1) and 1 or 255
  return { math.floor(r * scale + 0.5), math.floor(g * scale + 0.5), math.floor(b * scale + 0.5) }
end

local function not_on_map(proto)
  local ok, flags = pcall(function() return proto.flags end)
  return ok and type(flags) == "table" and flags["not-on-map"] == true
end

-- Derived only from prototypes (see registry.lua): name .. "|" .. side -> {colour, layer} or false.
local styles = {}
local tile_colours = {}

-- side: "own" (the character's force), "neutral" or "enemy".
local function style(e, side)
  local key = e.name .. "|" .. side
  local s = styles[key]
  if s ~= nil then
    return s
  end
  local proto = e.prototype
  local t = e.type
  local colour
  if t == "entity-ghost" then
    colour = GHOST
  elseif not not_on_map(proto) then
    if side == "own" then
      colour = rgb(proto.friendly_map_color) or rgb(proto.map_color) or FRIENDLY_BY_TYPE[t] or DEFAULT_FRIENDLY
    elseif side == "enemy" then
      colour = rgb(proto.enemy_map_color) or rgb(proto.map_color) or DEFAULT_ENEMY
    else
      colour = rgb(proto.map_color) or (t == "tree" and TREE or nil)
    end
  end
  local layer = t == "resource" and LAYER_ORE or (NATURE[t] and LAYER_NATURE or LAYER_BUILDING)
  s = colour and { colour, layer } or false
  styles[key] = s
  return s
end

local function tile_colour(name)
  local c = tile_colours[name]
  if not c then
    c = rgb(prototypes.tile[name].map_color) or { 0, 0, 0 }
    tile_colours[name] = c
  end
  return c
end

-- storage.f3d.explored[surface index][cx][cy] = true: chunks the bridge's character has charted
-- around itself. Kept across clients, like the game's own chart.
local function explore(c)
  local s = storage.f3d
  s.explored = s.explored or {}
  local surface = c.surface
  local seen = s.explored[surface.index] or {}
  s.explored[surface.index] = seen
  local p = c.position
  local r = CHART_RADIUS / CHUNK
  local cx0, cy0 = math.floor(p.x / CHUNK), math.floor(p.y / CHUNK)
  for cx = cx0 - r, cx0 + r do
    for cy = cy0 - r, cy0 + r do
      if surface.is_chunk_generated({ cx, cy }) then
        seen[cx] = seen[cx] or {}
        seen[cx][cy] = true
      end
    end
  end
end

local function charted(surface, force, cx, cy)
  if force.is_chunk_charted(surface, { cx, cy }) then
    return true
  end
  -- A force sees all of its own platforms (a headless server never charts them: 2.1.23), as far as
  -- they are generated: an ungenerated chunk's tiles are invalid, which stopped the map (F6).
  local ok, platform = pcall(function() return surface.platform end)
  if ok and platform and platform.valid and platform.force == force then
    return surface.is_chunk_generated({ cx, cy })
  end
  local seen = storage.f3d.explored and storage.f3d.explored[surface.index]
  return seen ~= nil and seen[cx] ~= nil and seen[cx][cy] == true
end

-- Whether the force has charted the chunk at a map position (remote building needs it, as in the
-- game).
function M.is_charted(surface, force, position)
  local x = position.x or position[1]
  local y = position.y or position[2]
  return charted(surface, force, math.floor(x / CHUNK), math.floor(y / CHUNK))
end

-- Remote building (ghosts, blueprints, planners away from the character) only on charted ground,
-- as in the game. Says so and returns false otherwise.
function M.check_charted(c, position)
  if M.is_charted(puppet.surface(c), c.force, position) then
    return true
  end
  puppet.message("You can't build in an uncharted area")
  return false
end

-- Factorio's remote view opens what radars cover (and what is near a player's character). A
-- headless server with no player connected reveals nothing: in 2.1.23 is_chunk_visible stays false
-- beside a working radar. So the coverage is worked out here: the ground round the character (as
-- `charted` counts it), and the chunks within a working radar's nearby reveal distance.
---------------------------------------------------------------------------------------------
-- Radars. Looking for every radar on a surface reads every entity there: 67 ms on the owner's
-- save (381,000 entities), and the map's trains, the 3D remote view and its `cov` all need them.
-- So each surface's radars are kept in storage.f3d_radars[surface index] (one list for every
-- client): found once by a scan that walks squares of RADAR_REGION tiles in rings out from the
-- map's centre, a few squares a tick under the work budget, until a whole ring holds nothing; and
-- kept current by tracker.listeners (built and removed radars; a removed one is dropped once it is
-- no longer valid). The scan starts again now and then (RADAR_RESCAN_TICKS) for radars made
-- without an event. The same scan finds the cargo landing pads (reg.pads), which the map view
-- centres on when it switches to a planet (H23).
local SCANNED = { "radar", "cargo-landing-pad" }
local RADAR_REGION = 4 * CHUNK
local RADAR_REGION_PRICE = 32       -- units for one square (16 chunks; ~0.4 ms on a busy base)
local RADAR_SHARE = 0.3
local RADAR_RESCAN_TICKS = 36000

local function radar_registry(surface)
  storage.f3d_radars = storage.f3d_radars or {}
  local reg = storage.f3d_radars[surface.index]
  if not reg then
    reg = { list = {}, pads = {}, ring = 0, i = 0, empty = true, done = false }
    storage.f3d_radars[surface.index] = reg
  elseif not reg.pads then
    -- Kept from before the scan also looked for landing pads: scan again.
    reg.pads, reg.done, reg.ring, reg.i, reg.empty = {}, false, 0, 0, true
  end
  return reg
end

-- Square i of ring `ring` (max(|x|, |y|) == ring), in region coordinates.
local function ring_square(ring, i)
  if ring == 0 then
    return 0, 0
  end
  local side = 2 * ring
  local leg, at = math.floor(i / side), i % side
  if leg == 0 then
    return -ring + at, -ring
  elseif leg == 1 then
    return ring, -ring + at
  elseif leg == 2 then
    return ring - at, ring
  end
  return -ring, ring - at
end

-- One slice of the surface's scan: squares while the budget allows.
local function scan_radars(surface)
  local reg = radar_registry(surface)
  if reg.done then
    if game.tick - (reg.done_tick or 0) < RADAR_RESCAN_TICKS then
      return
    end
    reg.done, reg.ring, reg.i, reg.empty = false, 0, 0, true
  end
  while budget.can(RADAR_REGION_PRICE, "radars", RADAR_SHARE) do
    budget.spend(RADAR_REGION_PRICE, "radars")
    local rx, ry = ring_square(reg.ring, reg.i)
    local area = { { rx * RADAR_REGION, ry * RADAR_REGION }, { (rx + 1) * RADAR_REGION, (ry + 1) * RADAR_REGION } }
    if surface.count_entities_filtered({ area = area, limit = 1 }) > 0 then
      reg.empty = false
      for _, r in pairs(surface.find_entities_filtered({ area = area, type = SCANNED })) do
        if r.unit_number then
          if r.type == "radar" then
            reg.list[r.unit_number] = r
          else
            reg.pads[r.unit_number] = r
          end
        end
      end
    end
    reg.i = reg.i + 1
    if reg.i >= math.max(1, 8 * reg.ring) then
      if reg.empty and reg.ring > 0 then
        reg.done, reg.done_tick = true, game.tick
        return
      end
      reg.ring, reg.i, reg.empty = reg.ring + 1, 0, true
    end
  end
end

-- Built or removed radars and landing pads (tracker.listeners), on surfaces being kept.
local function radar_touched(entity)
  if not (entity and entity.valid and entity.unit_number) then
    return
  end
  local reg = storage.f3d_radars and storage.f3d_radars[entity.surface.index]
  if reg and entity.type == "radar" then
    reg.list[entity.unit_number] = entity
  elseif reg and reg.pads and entity.type == "cargo-landing-pad" then
    reg.pads[entity.unit_number] = entity
  end
end
tracker.listeners[#tracker.listeners + 1] = radar_touched

-- The force's radars on the surface, as far as they are known (valid ones).
local function radars_of(surface, force)
  local out = {}
  local reg = radar_registry(surface)
  for unit, r in pairs(reg.list) do
    if not r.valid then
      reg.list[unit] = nil
    elseif r.force == force then
      out[#out + 1] = r
    end
  end
  return out
end

-- Surfaces whose radars are still being looked for.
function M.radar_queue()
  local n = 0
  for _, reg in pairs(storage.f3d_radars or {}) do
    if not reg.done then
      n = n + 1
    end
  end
  return n
end
budget.register_queue("radars", M.radar_queue)

-- Roboports reveal too (owner's H13; Factorio's own don't): a chunk counts as seen when its centre
-- lies in a roboport's construction area, the larger of its two and where its robots reach, so a
-- network shows whole. Mobile cells (a character's or a spidertron's personal roboport) don't count.
-- Read from the game (a few API calls), so it is the same on every peer.
local function roboport_sees(surface, force, cx, cy)
  local centre = { x = cx * CHUNK + CHUNK / 2, y = cy * CHUNK + CHUNK / 2 }
  local ok, nets = pcall(surface.find_logistic_networks_by_construction_area, centre, force)
  if not (ok and nets) then
    return false
  end
  for _, net in pairs(nets) do
    local okc, inside = pcall(function()
      local cell = net.valid and net.find_cell_closest_to(centre)
      return cell and cell.valid and not cell.mobile and cell.is_in_construction_range(centre)
    end)
    if okc and inside then
      return true
    end
  end
  return false
end

-- roboport_sees for what is only sent (the remote view's filter, the map's trains): kept one to two
-- seconds per chunk (spread, so the chunks round the view aren't all read again in one tick).
local ROBOPORT_SEEN_TICKS = 60
local rp_seen = {}  -- "si,force,cx,cy" -> {seen, until}
local rp_seen_count = 0

local function roboport_seen(surface, force, cx, cy)
  local key = surface.index .. "," .. force.name .. "," .. cx .. "," .. cy
  local hit = rp_seen[key]
  if hit and game.tick < hit[2] then
    return hit[1]
  end
  if not hit then
    if rp_seen_count >= 8192 then
      rp_seen, rp_seen_count = {}, 0
    end
    rp_seen_count = rp_seen_count + 1
  end
  local seen = roboport_sees(surface, force, cx, cy)
  rp_seen[key] = { seen, game.tick + ROBOPORT_SEEN_TICKS + (cx * 7 + cy * 13) % ROBOPORT_SEEN_TICKS }
  return seen
end

function M.covered(surface, force, position)
  local x = position.x or position[1]
  local y = position.y or position[2]
  local c = puppet.get()
  if c and c.valid and c.surface == surface then
    local dx, dy = c.position.x - x, c.position.y - y
    if dx * dx + dy * dy <= CHART_RADIUS * CHART_RADIUS then
      return true
    end
  end
  -- A force sees all of its own platforms (the remote view from the hub reaches every building).
  local okp, platform = pcall(function() return surface.platform end)
  if okp and platform and platform.valid and platform.force == force then
    return true
  end
  local cx, cy = math.floor(x / CHUNK), math.floor(y / CHUNK)
  local ok, visible = pcall(function() return force.is_chunk_visible(surface, { cx, cy }) end)
  if ok and visible then
    return true
  end
  local working, low = defines.entity_status.working, defines.entity_status.low_power
  for _, r in pairs(radars_of(surface, force)) do
    local status = r.status
    if status == working or status == low then
      local okd, d = pcall(function() return r.prototype.max_distance_of_nearby_sector_revealed end)
      d = okd and tonumber(d) or 3
      if math.abs(math.floor(r.position.x / CHUNK) - cx) <= d and math.abs(math.floor(r.position.y / CHUNK) - cy) <= d then
        return true
      end
    end
  end
  return roboport_sees(surface, force, cx, cy)
end

local function state()
  local s = storage.f3d
  s.map = s.map or { queue = {}, head = 1, res = 4 }
  return s.map
end

function M.reset()
  storage.f3d.map = nil
  storage.f3d.map_rp = nil
  storage.f3d.map_rp_next = nil
  storage.f3d.lpad_wait = nil
end

---------------------------------------------------------------------------------------------
-- Map view layers: what Factorio's map view switches show over the chart (electric networks,
-- logistic networks, turret coverage, train stop names, rail signal states, recipe icons, worker
-- robots), sent with each chunk's chart.

local MAX_OVERLAY = 400 -- per chunk
local TURRET_TYPES = { ["ammo-turret"] = true, ["electric-turret"] = true, ["fluid-turret"] = true }
local SIGNAL_TYPES = { ["rail-signal"] = true, ["rail-chain-signal"] = true }
local ROBOT_TYPES = { "construction-robot", "logistic-robot" }

-- Derived only from prototypes: name -> radius (or {logistic, construction}), false for none.
local radii = {}

local function first_number(proto, getters)
  for _, get in ipairs(getters) do
    local ok, v = pcall(get, proto)
    if ok and type(v) == "number" then
      return v
    end
  end
  return nil
end

local function radius(proto, t)
  local r = radii[proto.name]
  if r ~= nil then
    return r
  end
  if t == "electric-pole" then
    r = first_number(proto, {
      function(p) return p.get_supply_area_distance() end,
      function(p) return p.supply_area_distance end,
    })
  elseif TURRET_TYPES[t] then
    r = first_number(proto, {
      function(p) return p.attack_parameters.range end,
      function(p) return p.turret_range end,
    })
  elseif t == "roboport" then
    local l = first_number(proto, {
      function(p) return p.logistic_radius end,
      function(p) return p.get_logistic_radius() end,
    })
    local c = first_number(proto, {
      function(p) return p.construction_radius end,
      function(p) return p.get_construction_radius() end,
    })
    r = (l or c) and { l or 0, c or 0 } or false
  end
  radii[proto.name] = r or false
  return radii[proto.name]
end

local function rounded(v)
  return math.floor(v * 100 + 0.5) / 100
end

-- [[kind, x, y (fixed), ...], ...] for the chunk at x0, y0: "e" pole and supply radius, "w" a copper
-- wire from a pole to x2, y2, "t" turret
-- and range, "l" roboport and logistic and construction radius, "s" train stop and name, "g" rail
-- signal and state (defines.signal_state), "c" machine and recipe, "b" worker robot.
-- Adds what stays put to `out`, and the signals ({entity, x, y}) whose state is read when it is
-- sent to `signals`, for entities whose centre lies in the chunk's rows ya..yb (a chart is read in
-- strips, and an entity across two strips is found in both).
local function overlay(found, own, x0, y0, ya, yb, out, signals)
  local function inside(p)
    return p.x >= x0 and p.x < x0 + CHUNK and p.y >= ya and p.y < yb
  end
  for _, e in pairs(found) do
    if #out + #signals >= MAX_OVERLAY then
      break
    end
    if e.force.name == own and inside(e.position) then
      local t = e.type
      local x, y = world.fixed(e.position.x), world.fixed(e.position.y)
      if t == "electric-pole" or TURRET_TYPES[t] then
        local r = radius(e.prototype, t)
        if r then
          out[#out + 1] = { t == "electric-pole" and "e" or "t", x, y, rounded(r) }
        end
        if t == "electric-pole" then
          -- Its copper wires, each once (from the pole with the lower unit number).
          local ok, connector = pcall(e.get_wire_connector, defines.wire_connector_id.pole_copper, false)
          for _, c in pairs(ok and connector and connector.connections or {}) do
            local other = c.target.owner
            if other.unit_number and e.unit_number and other.unit_number > e.unit_number and #out < MAX_OVERLAY then
              out[#out + 1] = { "w", x, y, world.fixed(other.position.x), world.fixed(other.position.y) }
            end
          end
        end
      elseif t == "roboport" then
        local r = radius(e.prototype, t)
        if r then
          out[#out + 1] = { "l", x, y, rounded(r[1]), rounded(r[2]) }
        end
      elseif t == "train-stop" then
        out[#out + 1] = { "s", x, y, e.backer_name or "" }
      elseif SIGNAL_TYPES[t] then
        signals[#signals + 1] = { e, x, y }
      elseif t == "assembling-machine" or t == "furnace" then
        local ok, recipe = pcall(e.get_recipe)
        if ok and recipe then
          out[#out + 1] = { "c", x, y, recipe.name }
        end
      end
    end
  end
end

-- The overlay as sent: what stays put, the signals' states now, and the robots there now.
local function live_overlay(surface, own, x0, y0, fixed_part, signals)
  local out = {}
  for i, row in ipairs(fixed_part) do
    out[i] = row
  end
  for _, sig in ipairs(signals) do
    if #out >= MAX_OVERLAY then
      break
    end
    local e = sig[1]
    if e.valid then
      local ok, state = pcall(function() return e.signal_state end)
      out[#out + 1] = { "g", sig[2], sig[3], ok and state or 0 }
    end
  end
  if #out < MAX_OVERLAY then
    local robots = surface.find_entities_filtered({
      area = { { x0, y0 }, { x0 + CHUNK, y0 + CHUNK } }, type = ROBOT_TYPES, force = own, limit = MAX_OVERLAY - #out,
    })
    for _, e in pairs(robots) do
      if #out >= MAX_OVERLAY then
        break
      end
      out[#out + 1] = { "b", world.fixed(e.position.x), world.fixed(e.position.y) }
    end
  end
  return out
end

---------------------------------------------------------------------------------------------
-- Charts

-- A busy chunk's chart costs about 4 ms (13 us an entity in 2.1.23 on a laptop, tools/busy_base.py
-- --big), and the minimap asks for its area again every few seconds, so a chunk's picture is kept
-- and sent again while the chunk looks the same: as many entities in it, nothing built, mined,
-- rotated or destroyed there since (tracker.listeners), and younger than CHART_KEEP_TICKS. What
-- changes without an event is read each time: pollution, signal states, robots. Only what is sent
-- depends on this cache.
local CHART_KEEP_TICKS = 1800
local CHART_CACHE_MAX = 4096
local chart_cache = {}  -- "si,cx,cy,res" -> {tick, count, own, pal, px, ov, signals}
local chart_cached = 0

local function chart_key(si, cx, cy, res)
  return si .. "," .. cx .. "," .. cy .. "," .. res
end

-- Something was built, mined, rotated or destroyed: its chunk's charts are made again.
local function chunk_touched(entity)
  if not (entity and entity.valid) then
    return
  end
  local p, si = entity.position, entity.surface.index
  local cx, cy = math.floor(p.x / CHUNK), math.floor(p.y / CHUNK)
  for _, res in ipairs(RESOLUTIONS) do
    local key = chart_key(si, cx, cy, res)
    if chart_cache[key] then
      chart_cache[key] = nil
      chart_cached = chart_cached - 1
    end
  end
end
tracker.listeners[#tracker.listeners + 1] = chunk_touched

-- {t = "chart", cx, cy, n, pal, px}: n x n pixels (32 / res), row by row from the north-west,
-- each an index into pal ([[r, g, b], ...], 0-based). n = 0 for a chunk not charted yet.
--
-- A chunk is charted as a job in slices under the work budget (budget.lua), so a busy chunk (a
-- thousand entities and more) never makes one slow tick: first how many entities it has and its
-- tiles, then its entities in strips of rows (1, 2, 4 or 8 strips, so each holds about half a
-- budget's worth), then the message. The job's place (storage.f3d.map.job) and its price come from
-- the game only (counts), so it moves the same way on every peer; the pixels being built are
-- module-local (`scratches`, one per client), as they only decide what is sent. A cached chart (chart_cache) is still
-- walked through slice by slice and priced the same, it just reads nothing.
local MAP_SHARE = 0.6
local scratches = {}  -- client port -> {id, cached, pal, index, px, layers, ov, signals}

local function strips_for(count)
  local per = budget.slice(50)
  local strips = 1
  while strips < 8 and count > per * strips do
    strips = strips * 2
  end
  return strips
end

-- What the job's next slice costs, in units.
local function job_price(job, res)
  if job.step < 0 then
    return 2
  elseif job.step == 0 then
    local n = CHUNK / res
    return 1 + math.ceil(n * n / budget.TILES_PER_UNIT)
  end
  return 2 + math.ceil(job.count / job.strips)
end

local function colour_index(sc, c)
  local ckey = c[1] * 65536 + c[2] * 256 + c[3]
  local i = sc.index[ckey]
  if not i then
    sc.pal[#sc.pal + 1] = c
    i = #sc.pal - 1
    sc.index[ckey] = i
  end
  return i
end

local function send_chart(surface, own, cx, cy, n, hit)
  local x0, y0 = cx * CHUNK, cy * CHUNK
  local msg = { t = "chart", cx = cx, cy = cy, n = n, pal = hit.pal, px = hit.px, si = surface.index }
  -- The chunk's pollution, for the map view's pollution layer.
  local okp, pollution = pcall(surface.get_pollution, { x0 + 16, y0 + 16 })
  if okp and pollution and pollution >= 0.5 then
    msg.pol = math.floor(pollution + 0.5)
  end
  local ov = live_overlay(surface, own, x0, y0, hit.ov, hit.signals)
  if #ov > 0 then
    msg.ov = ov
  end
  transport.send_now(msg)
end

-- One slice of the job in m.job; clears m.job when the chart is sent.
local function chart_step(surface, force, m)
  local job, res = m.job, m.res
  local cx, cy = job.cx, job.cy
  local n = CHUNK / res
  local x0, y0 = cx * CHUNK, cy * CHUNK
  local own = force.name
  local area = { { x0, y0 }, { x0 + CHUNK, y0 + CHUNK } }
  local key = chart_key(surface.index, cx, cy, res)
  local id = key .. "@" .. job.started
  if job.step < 0 then
    if not charted(surface, force, cx, cy) then
      transport.send_now({ t = "chart", cx = cx, cy = cy, n = 0, si = surface.index })
      m.job = nil
      return
    end
    job.count = surface.count_entities_filtered({ area = area, type = registry.excluded_types(), invert = true })
    job.strips = strips_for(job.count)
    job.step = 0
    return
  end
  local port = storage.f3d.client and storage.f3d.client.port or 0
  local sc = scratches[port]
  if job.step == 0 then
    local hit = chart_cache[key]
    if hit and hit.count == job.count and hit.own == own and game.tick - hit.tick < CHART_KEEP_TICKS then
      scratches[port] = { id = id, cached = hit }
    else
      sc = { id = id, pal = {}, index = {}, px = {}, layers = {}, ov = {}, signals = {} }
      local half = math.floor(res / 2)
      for py = 0, n - 1 do
        for pxx = 0, n - 1 do
          local tile = surface.get_tile(x0 + pxx * res + half, y0 + py * res + half)
          sc.px[py * n + pxx + 1] = colour_index(sc, tile_colour(tile.name))
          sc.layers[py * n + pxx + 1] = 0
        end
      end
      scratches[port] = sc
    end
    job.step = 1
    return
  end
  -- A strip of rows. Without the job's scratch (the game was loaded part way) nothing is read and
  -- nothing sent; the client asks again.
  if sc and sc.id == id and not sc.cached then
    local h = CHUNK / job.strips
    local ya = y0 + (job.step - 1) * h
    local yb = ya + h
    local found = surface.find_entities_filtered({ area = { { x0, ya }, { x0 + CHUNK, yb } },
      type = registry.excluded_types(), invert = true })
    for _, e in pairs(found) do
      local f = e.force.name
      local st = style(e, f == own and "own" or (f == "neutral" and "neutral" or "enemy"))
      if st then
        local box = e.bounding_box
        local i1 = math.max(0, math.floor((box.left_top.x - x0) / res))
        local i2 = math.min(n - 1, math.floor((box.right_bottom.x - x0 - 0.001) / res))
        local j1 = math.max(0, math.floor((box.left_top.y - y0) / res))
        local j2 = math.min(n - 1, math.floor((box.right_bottom.y - y0 - 0.001) / res))
        local ci, layer = nil, st[2]
        for j = j1, j2 do
          for i = i1, i2 do
            local k = j * n + i + 1
            if layer >= sc.layers[k] then
              ci = ci or colour_index(sc, st[1])
              sc.px[k], sc.layers[k] = ci, layer
            end
          end
        end
      end
    end
    overlay(found, own, x0, y0, ya, yb, sc.ov, sc.signals)
  end
  if job.step < job.strips then
    job.step = job.step + 1
    return
  end
  m.job = nil
  if not (sc and sc.id == id) then
    return
  end
  scratches[port] = nil
  local hit = sc.cached
  if not hit then
    if not chart_cache[key] then
      if chart_cached >= CHART_CACHE_MAX then
        chart_cache, chart_cached = {}, 0
      end
      chart_cached = chart_cached + 1
    end
    hit = { tick = game.tick, count = job.count, own = own, pal = sc.pal, px = sc.px, ov = sc.ov, signals = sc.signals }
    chart_cache[key] = hit
  end
  send_chart(surface, own, cx, cy, n, hit)
end

---------------------------------------------------------------------------------------------
-- Tags

-- {t = "tags", l = [[id, x, y, text, icon type, icon name], ...]}: every tag on the surface,
-- positions fixed, "" for no icon.
local function send_tags(surface)
  local c = puppet.get()
  if not c then
    return
  end
  surface = surface or c.surface
  local list = {}
  for _, tag in pairs(c.force.find_chart_tags(surface)) do
    local icon = tag.icon
    list[#list + 1] = {
      tag.tag_number, world.fixed(tag.position.x), world.fixed(tag.position.y), tag.text or "",
      icon and (icon.type or "item") or "", icon and icon.name or "",
    }
  end
  transport.send_now({ t = "tags", l = list, si = surface.index })
end

---------------------------------------------------------------------------------------------
-- Surfaces the map can show (Factorio's map surface switcher): the planets that exist and the
-- force's space platforms.

local SURFACES_INTERVAL = 300

-- The surface a command names by index (`si`), else the character's.
local function surface_of(cmd, c)
  local si = tonumber(cmd and cmd.si)
  local surface = si and game.get_surface(math.floor(si))
  return surface or (c and c.surface) or world.surface()
end

-- [[index, name, planet ("" on a platform), platform name ("" on a planet), platform index (0)]].
-- Surfaces that are neither (a mod's, an editor's) come last with both "": Factorio's "Other".
local function surface_list(force)
  local out, others = {}, {}
  for _, surface in pairs(game.surfaces) do
    local okp, platform = pcall(function() return surface.platform end)
    local okq, planet = pcall(function() return surface.planet end)
    platform = okp and platform or nil
    planet = okq and planet or nil
    if platform and platform.valid and platform.force == force then
      out[#out + 1] = { surface.index, surface.name, "", platform.name, platform.index }
    elseif planet or surface.index == 1 then
      out[#out + 1] = { surface.index, surface.name, planet and planet.name or surface.name, "", 0 }
    elseif not platform then
      others[#others + 1] = { surface.index, surface.name, "", "", 0 }
    end
  end
  for _, r in ipairs(others) do
    out[#out + 1] = r
  end
  return out
end

local function send_surfaces(force, always)
  local s = storage.f3d
  local list = surface_list(force)
  local parts = {}
  for i, r in ipairs(list) do
    parts[i] = table.concat(r, ":")
  end
  local sig = table.concat(parts, ",")
  if always or sig ~= s.surfs_sig then
    s.surfs_sig = sig
    transport.send_reliable({ t = "surfs", l = list })
  end
end

function M.send_initial()
  local c = puppet.get()
  storage.f3d.surfs_sig = nil
  send_surfaces(c and c.force or game.forces.player, true)
end

function M.on_tags_changed()
  if storage.f3d and storage.f3d.client then
    state().tags_dirty = true
  end
end

function M.register()
  script.on_event({
    defines.events.on_chart_tag_added,
    defines.events.on_chart_tag_modified,
    defines.events.on_chart_tag_removed,
  }, M.on_tags_changed)
end

---------------------------------------------------------------------------------------------
-- Commands

-- {cx1, cy1, cx2, cy2 (chunks, inclusive), res (tiles per pixel: 2, 4, 8, 16 or 32)}: charts
-- for that area, nearest its centre first. A new request replaces the one still being sent.
-- A chunk coordinate from the client, or nil. Huge floats would make `cx + 1 == cx` and the loops
-- below endless; Factorio's maps end at 2^20 tiles, 32768 chunks from the centre.
local function chunk_coord(v)
  v = tonumber(v)
  if v and v == v and v > -40000 and v < 40000 then
    return math.floor(v)
  end
  return nil
end

function M.request(cmd)
  local x1, y1 = chunk_coord(cmd.cx1) or 0, chunk_coord(cmd.cy1) or 0
  local x2, y2 = chunk_coord(cmd.cx2) or x1, chunk_coord(cmd.cy2) or y1
  x1, x2 = math.min(x1, x2), math.max(x1, x2)
  y1, y2 = math.min(y1, y2), math.max(y1, y2)
  local res = 4
  for _, r in ipairs(RESOLUTIONS) do
    if tonumber(cmd.res) == r then
      res = r
    end
  end
  local mx, my = (x1 + x2) / 2, (y1 + y2) / 2
  -- Only the MAX_CHUNKS nearest the centre: a square of that many chunks around it.
  local half = math.floor(math.sqrt(MAX_CHUNKS) / 2)
  x1, x2 = math.max(x1, math.floor(mx) - half + 1), math.min(x2, math.floor(mx) + half)
  y1, y2 = math.max(y1, math.floor(my) - half + 1), math.min(y2, math.floor(my) + half)
  local queue = {}
  for cy = y1, y2 do
    for cx = x1, x2 do
      queue[#queue + 1] = { cx, cy, (cx - mx) ^ 2 + (cy - my) ^ 2 }
    end
  end
  table.sort(queue, function(a, b)
    if a[3] ~= b[3] then
      return a[3] < b[3]
    end
    if a[2] ~= b[2] then
      return a[2] < b[2]
    end
    return a[1] < b[1]
  end)
  local m = state()
  m.queue, m.head, m.res, m.job = queue, 1, res, nil
  -- `si`: another surface's map (the map view's surface switcher); else the character's.
  local si = tonumber(cmd.si)
  m.si = si and game.get_surface(math.floor(si)) and math.floor(si) or nil
  m.tags_dirty = true
end

-- {x, y (fixed), text, icon: [type, name] (optional)}: a new tag on the map.
function M.add_tag(cmd)
  local c = puppet.get()
  local x, y = tonumber(cmd.x), tonumber(cmd.y)
  if not (c and x and y) then
    return
  end
  local spec = { position = { x / 256, y / 256 }, text = tostring(cmd.text or "") }
  if type(cmd.icon) == "table" and cmd.icon[2] then
    spec.icon = { type = tostring(cmd.icon[1] or "item"), name = tostring(cmd.icon[2]) }
  end
  local surface = surface_of(cmd, c)
  local tag = c.force.add_chart_tag(surface, spec)
  if not tag then
    puppet.message("Can't put a tag there (not charted yet?)")
  end
  state().tags_dirty = true
end

-- {x, y, si?, q}: right-click on the map. Removes the character's force's ghost under that point
-- (a building's before a tile's), as Factorio does, and answers `unghost` {q, n} (n removed: the
-- client adds a tag where there was none).
function M.unghost(cmd)
  local c = puppet.get()
  local x, y = tonumber(cmd.x), tonumber(cmd.y)
  if not (c and x and y) then
    return
  end
  local at = { x / 256, y / 256 }
  local surface = surface_of(cmd, c)
  local n = 0
  for _, kind in ipairs({ "entity-ghost", "tile-ghost" }) do
    local found = surface.find_entities_filtered({ position = at, type = kind, force = c.force })
    if #found == 0 and kind == "entity-ghost" then
      -- position only finds what covers the point's exact spot; ghosts' boxes are often a hair short.
      found = surface.find_entities_filtered({ area = { { at[1] - 0.3, at[2] - 0.3 }, { at[1] + 0.3, at[2] + 0.3 } }, type = kind, force = c.force })
    end
    local g = found[1]
    if g and g.valid then
      tracker.removed(g)
      g.destroy()
      n = 1
      break
    end
  end
  transport.send_now({ t = "unghost", q = math.floor(tonumber(cmd.q) or 0), n = n })
end

-- {si?}: the trains on the map, which Factorio draws live where radars see them. The client asks
-- about once a second while its map view or minimap is open, and gets `mtr` {si, part, parts, l:
-- [x, y, orientation (1/1000 turn), length, width (1/256 tile), colour 0xRRGGBB, ...]}: one
-- carriage per six numbers, in parts small enough for a datagram. The first part also carries
-- `cov`: [cx, cy, d, ...], each working radar's chunk and how many chunks round it it keeps
-- revealed, so the map can dim what no radar covers (with the ground round the character).
local TRAIN_PART = 400
local TRAIN_ASK_TICKS = 20     -- more asks than this are ignored (a client can't make it busy)
local LOCO_COLOR = 0xEB1200    -- Factorio's default locomotive colour {0.92, 0.07, 0}
local WAGON_COLOR = 0x9A9A9A
local carriage_size = {}       -- prototype name -> {length, width}: prototypes only
local last_train_ask = -TRAIN_ASK_TICKS
local COVERAGE_TICKS = 60      -- the radars' statuses are read at most this often (only what is sent)
local coverage = { tick = -COVERAGE_TICKS }

-- [cx, cy, d, ...] for the force's working radars on the surface (as far as the scan has found
-- them), and a set of the chunks they cover ("cx,cy" -> true). Kept a second; it only decides what
-- is sent, never what is stored.
local function radar_coverage(surface, force)
  if coverage.surface == surface.index and coverage.force == force.name and game.tick - coverage.tick < COVERAGE_TICKS then
    return coverage.list, coverage.set
  end
  local list, set = {}, {}
  local working, low = defines.entity_status.working, defines.entity_status.low_power
  for _, r in pairs(radars_of(surface, force)) do
    local status = r.status
    if status == working or status == low then
      local okd, d = pcall(function() return r.prototype.max_distance_of_nearby_sector_revealed end)
      d = okd and tonumber(d) or 3
      local rx, ry = math.floor(r.position.x / CHUNK), math.floor(r.position.y / CHUNK)
      list[#list + 1] = rx
      list[#list + 1] = ry
      list[#list + 1] = d
      for cx = rx - d, rx + d do
        for cy = ry - d, ry + d do
          set[cx .. "," .. cy] = true
        end
      end
    end
  end
  coverage = { tick = game.tick, surface = surface.index, force = force.name, list = list, set = set }
  return list, set
end

-- The 3D remote view (`focus` with rv = 1) shows moving things only where radars or the character
-- see, as Factorio's remote view does elsewhere: there the client greys the world out. A chunk is
-- seen when a working radar covers it or its centre lies within the character's charting radius
-- (as the map's dimming counts it). Platforms are always seen. Only what is sent depends on this.
local VIEW_NEAR = (CHART_RADIUS + CHUNK / 2) ^ 2
local view = { tick = -1 }

-- nil outside the remote view (everything is sent), else a function (x, y) -> whether that map
-- position is seen. Built once a tick, chunks memoised.
function M.view_filter()
  local s = storage.f3d
  if not s.remote_view then
    return nil
  end
  if view.tick == game.tick then
    return view.fn
  end
  view.tick = game.tick
  view.fn = nil
  local surface = world.surface()
  local okp, platform = pcall(function() return surface.platform end)
  if okp and platform then
    return nil
  end
  local c = puppet.get()
  local force = c and c.force or game.forces.player
  local _, set = radar_coverage(surface, force)
  local near = c and c.valid and c.surface == surface and c.position or nil
  local f = s.focus
  if near and f then
    -- The whole focus square inside the character's sight: nothing to leave out.
    local dx, dy = math.abs(near.x - f.x) + f.r + CHUNK, math.abs(near.y - f.y) + f.r + CHUNK
    if dx * dx + dy * dy <= CHART_RADIUS * CHART_RADIUS then
      return nil
    end
  end
  local floor, memo = math.floor, {}
  view.fn = function(x, y)
    local cx, cy = floor(x / CHUNK), floor(y / CHUNK)
    local row = memo[cx]
    if not row then
      row = {}
      memo[cx] = row
    end
    local seen = row[cy]
    if seen == nil then
      seen = set[cx .. "," .. cy] == true
      if not seen and near then
        local dx, dy = near.x - (cx * CHUNK + CHUNK / 2), near.y - (cy * CHUNK + CHUNK / 2)
        seen = dx * dx + dy * dy <= VIEW_NEAR
      end
      if not seen then
        seen = roboport_seen(surface, force, cx, cy)
      end
      row[cy] = seen
    end
    return seen
  end
  return view.fn
end

-- The entities of a list the remote view sees (all of them outside it).
function M.view_only(entities)
  local seen = M.view_filter()
  if not seen then
    return entities
  end
  local out = {}
  for _, e in pairs(entities) do
    local p = e.position
    if seen(p.x, p.y) then
      out[#out + 1] = e
    end
  end
  return out
end

-- `cov` {si, l: [cx, cy, d, ...], x?, y?, cr?}: what the 3D remote view sees, about once a second
-- while it is on: each working radar's chunk and reveal distance, and the character's position
-- (1/256 tile) and charting radius (tiles) when it is on that surface. `all` = 1 on a platform.
local COV_TICKS = 60
local cov_sent = false

local function send_view_coverage(c)
  local on = storage.f3d.remote_view ~= nil
  if not on then
    cov_sent = false
    return
  end
  if cov_sent and game.tick % COV_TICKS ~= 0 then
    return
  end
  cov_sent = true
  local surface = world.surface()
  local msg = { t = "cov", si = surface.index }
  local okp, platform = pcall(function() return surface.platform end)
  if okp and platform then
    msg.l = {}
    msg.all = 1
  else
    local force = c and c.force or game.forces.player
    msg.l = radar_coverage(surface, force)
    if c and c.valid and c.surface == surface then
      msg.x, msg.y, msg.cr = world.fixed(c.position.x), world.fixed(c.position.y), CHART_RADIUS
    end
  end
  transport.send_now(msg)
end

local function size_of(car)
  local size = carriage_size[car.name]
  if not size then
    local box = car.prototype.collision_box
    size = { world.fixed(box.right_bottom.y - box.left_top.y), world.fixed(box.right_bottom.x - box.left_top.x) }
    carriage_size[car.name] = size
  end
  return size
end

local function colour_of(car)
  local ok, c = pcall(function() return car.color end)
  if ok and c then
    local r, g, b = c.r or c[1] or 0, c.g or c[2] or 0, c.b or c[3] or 0
    if r <= 1 and g <= 1 and b <= 1 then
      r, g, b = r * 255, g * 255, b * 255
    end
    return math.floor(r + 0.5) * 65536 + math.floor(g + 0.5) * 256 + math.floor(b + 0.5)
  end
  return car.type == "locomotive" and LOCO_COLOR or WAGON_COLOR
end

function M.trains(cmd)
  if game.tick - last_train_ask < TRAIN_ASK_TICKS then
    return
  end
  last_train_ask = game.tick
  local c = puppet.get()
  local surface = surface_of(cmd, c)
  local force = c and c.force or game.forces.player
  local ok, list = pcall(function() return game.train_manager.get_trains({ surface = surface, force = force }) end)
  local radars, covered_set = radar_coverage(surface, force)
  local near = c and c.valid and c.surface == surface and c.position or nil
  local parts, current = {}, {}
  for _, train in pairs(ok and list or {}) do
    for _, car in pairs(train.carriages) do
      local p = car.position
      local cx, cy = math.floor(p.x / CHUNK), math.floor(p.y / CHUNK)
      local seen = covered_set[cx .. "," .. cy]
      if not seen and near then
        local dx, dy = near.x - p.x, near.y - p.y
        seen = dx * dx + dy * dy <= CHART_RADIUS * CHART_RADIUS
      end
      if not seen then
        seen = roboport_seen(surface, force, cx, cy)
      end
      if seen then
        local size = size_of(car)
        local n = #current
        current[n + 1] = world.fixed(p.x)
        current[n + 2] = world.fixed(p.y)
        current[n + 3] = math.floor(car.orientation * 1000 + 0.5) % 1000
        current[n + 4] = size[1]
        current[n + 5] = size[2]
        current[n + 6] = colour_of(car)
        if n + 6 >= TRAIN_PART * 6 then
          parts[#parts + 1] = current
          current = {}
        end
      end
    end
  end
  if #current > 0 or #parts == 0 then
    parts[#parts + 1] = current
  end
  for i, l in ipairs(parts) do
    local msg = { t = "mtr", si = surface.index, part = i, parts = #parts, l = l }
    if i == 1 then
      msg.cov = radars
    end
    transport.send_now(msg)
  end
end

-- The map's logistic networks layer (H13): Factorio's map draws every roboport's logistic and
-- construction area on the surface, not only the ones in the charts the client happened to load,
-- and the client counts the ground in their construction areas as seen (roboport_sees).
-- {si?, q}: the client asks every few seconds while a map or the remote view needs them, and gets
-- `mrp` {si, q, part, last, l: [x, y, logistic radius, construction radius, ...]} (all 1/256 tile),
-- the force's roboports from its logistic networks' cells (no entity search), ROBOPORT_PART to a
-- part, `last` 1 on the final one. Cells are read in slices under the work budget
-- (storage.f3d.map_rp is the job: which network and cell is next). An ask for another surface while
-- one is listed waits for it (map_rp_next); asks for the same surface within ROBOPORT_ASK_TICKS of
-- the last are ignored.
-- A request id or surface index from a packet: a whole number, 0 for anything else (NaN, huge).
local function small_int(v)
  v = tonumber(v)
  if v and v == v and v > -2147483648 and v < 2147483648 then
    return math.floor(v)
  end
  return 0
end

local ROBOPORT_PART = 500
local ROBOPORT_ASK_TICKS = 60
local ROBOPORT_SHARE = 0.3
local CELLS_PER_UNIT = 4            -- a cell's owner, position and two radii: a few API reads

local function start_roboports(si, q)
  storage.f3d.map_rp = { si = si, q = q, net = 1, cell = 1, part = 0, l = {}, started = game.tick }
end

function M.roboports(cmd)
  local s = storage.f3d
  local surface = surface_of(cmd, puppet.get())
  local q = small_int(cmd.q)
  local job = s.map_rp
  if job and not job.done then
    if job.si ~= surface.index then
      s.map_rp_next = { si = surface.index, q = q }
    end
    return
  end
  if job and job.si == surface.index and game.tick - job.started < ROBOPORT_ASK_TICKS then
    return
  end
  start_roboports(surface.index, q)
end

local function send_roboports(job, last)
  job.part = job.part + 1
  transport.send_now({ t = "mrp", si = job.si, q = job.q, part = job.part, last = last and 1 or 0, l = job.l })
  job.l = {}
end

local function roboports_step(force)
  local s = storage.f3d
  local job = s.map_rp
  if job and job.done and s.map_rp_next then
    local nxt = s.map_rp_next
    s.map_rp_next = nil
    start_roboports(nxt.si, nxt.q)
    job = s.map_rp
  end
  if not job or job.done then
    return
  end
  local surface = game.get_surface(job.si)
  if not (surface and surface.valid) then
    s.map_rp = nil
    return
  end
  local nets = (force.logistic_networks or {})[surface.name] or {}
  while true do
    local net = nets[job.net]
    if not net then
      send_roboports(job, true)
      job.done = true
      return
    end
    -- net.cells makes a table of every cell each time it is read: priced in.
    local cells = net.valid and net.cells or {}
    local count = math.max(0, math.min(#cells - job.cell + 1, budget.slice(25) * CELLS_PER_UNIT))
    local price = 1 + math.ceil(count / CELLS_PER_UNIT) + math.floor(#cells / (8 * CELLS_PER_UNIT))
    if not budget.can(price, "roboports", ROBOPORT_SHARE) then
      return
    end
    budget.spend(price, "roboports")
    for i = job.cell, job.cell + count - 1 do
      local cell = cells[i]
      local owner = cell and cell.valid and cell.owner
      if owner and owner.valid and owner.type == "roboport" then
        local lr, cr = tonumber(cell.logistic_radius), tonumber(cell.construction_radius)
        if not (lr and cr) then
          local r = radius(owner.prototype, "roboport") or { 0, 0 }
          lr, cr = lr or r[1], cr or r[2]
        end
        local p = owner.position
        local l = job.l
        local n = #l
        l[n + 1] = world.fixed(p.x)
        l[n + 2] = world.fixed(p.y)
        l[n + 3] = world.fixed(lr)
        l[n + 4] = world.fixed(cr)
        if n + 4 >= ROBOPORT_PART * 4 then
          send_roboports(job, false)
        end
      end
    end
    job.cell = job.cell + count
    if job.cell > #cells then
      job.net, job.cell = job.net + 1, 1
    end
  end
end

function M.roboport_queue()
  local s = storage.f3d
  local job = s and s.map_rp
  return ((job and not job.done) and 1 or 0) + ((s and s.map_rp_next) and 1 or 0)
end
budget.register_queue("roboports", M.roboport_queue)

-- {si, q}: where the map view centres on switching to a planet (H23), the force's cargo landing pad
-- there (the lowest unit number if there are several): `lpad` {si, q, x?, y?} (1/256 tile), without
-- x, y when the surface has none. The pads come from the radars' scan of that surface (started now
-- if it hasn't been), so the answer waits until a pad is found or the scan is done (at most
-- LPAD_WAIT_TICKS).
local LPAD_WAIT_TICKS = 600

function M.landing_pad(cmd)
  local si = small_int(cmd.si)
  local surface = si > 0 and game.get_surface(si) or nil
  local q = small_int(cmd.q)
  if not (surface and surface.valid) then
    transport.send_now({ t = "lpad", si = si, q = q })
    return
  end
  radar_registry(surface)
  storage.f3d.lpad_wait = { si = si, q = q, tick = game.tick }
end

local function answer_landing_pad(force)
  local s = storage.f3d
  local wait = s.lpad_wait
  if not wait then
    return
  end
  local surface = game.get_surface(wait.si)
  if not (surface and surface.valid) then
    s.lpad_wait = nil
    transport.send_now({ t = "lpad", si = wait.si, q = wait.q })
    return
  end
  local reg = radar_registry(surface)
  local best
  for unit, pad in pairs(reg.pads) do
    if not pad.valid then
      reg.pads[unit] = nil
    elseif pad.force == force and (not best or unit < best.unit_number) then
      best = pad
    end
  end
  if not (best or reg.done or game.tick - wait.tick >= LPAD_WAIT_TICKS) then
    return
  end
  s.lpad_wait = nil
  local msg = { t = "lpad", si = wait.si, q = wait.q }
  if best then
    msg.x, msg.y = world.fixed(best.position.x), world.fixed(best.position.y)
  end
  transport.send_now(msg)
end

-- {id}: removes that tag.
function M.remove_tag(cmd)
  local c = puppet.get()
  local id = tonumber(cmd.id)
  if not (c and id) then
    return
  end
  for _, tag in pairs(c.force.find_chart_tags(surface_of(cmd, c))) do
    if tag.tag_number == id then
      tag.destroy()
    end
  end
  state().tags_dirty = true
end

---------------------------------------------------------------------------------------------

function M.tick()
  local m = storage.f3d.map
  local c = puppet.get()
  if not c then
    return
  end
  if game.tick % CHART_INTERVAL == 0 and not c.player then
    local p = c.position
    pcall(c.force.chart, c.surface, { { p.x - CHART_RADIUS, p.y - CHART_RADIUS }, { p.x + CHART_RADIUS, p.y + CHART_RADIUS } })
    explore(c)
  end
  if game.tick % SURFACES_INTERVAL == 0 then
    send_surfaces(c.force, false)
  end
  send_view_coverage(c)
  for _, step in ipairs({ roboports_step, answer_landing_pad }) do
    local ok, err = pcall(step, c.force)
    if not ok then
      storage.f3d.map_rp, storage.f3d.map_rp_next, storage.f3d.lpad_wait = nil, nil, nil
      transport.send_now({ t = "msg", text = "Map error: " .. tostring(err) })
    end
  end
  -- Radars still being looked for on any surface (radars_of starts a surface's scan when asked).
  radar_registry(world.surface())
  for si, reg in pairs(storage.f3d_radars) do
    if not reg.done or game.tick - (reg.done_tick or 0) >= RADAR_RESCAN_TICKS then
      local surface = game.get_surface(si)
      if surface and surface.valid then
        scan_radars(surface)
      else
        storage.f3d_radars[si] = nil
      end
    end
  end
  if not m then
    return
  end
  local surface = (m.si and game.get_surface(m.si)) or world.surface()
  if m.tags_dirty then
    m.tags_dirty = nil
    local ok, err = pcall(send_tags, surface)
    if not ok then
      transport.send_now({ t = "msg", text = "Map error: " .. tostring(err) })
    end
  end
  local force = c.force
  while true do
    if not m.job then
      local entry = m.queue[m.head]
      if not entry then
        m.queue, m.head = {}, 1
        return
      end
      m.queue[m.head] = nil
      m.head = m.head + 1
      m.job = { cx = entry[1], cy = entry[2], step = -1, started = game.tick }
    end
    local price = job_price(m.job, m.res)
    if not budget.can(price, "map", MAP_SHARE) then
      return
    end
    budget.spend(price, "map")
    -- This runs in on_tick, where an error would stop the game: report it and drop the request.
    local ok, err = pcall(chart_step, surface, force, m)
    if not ok then
      m.queue, m.head, m.job = {}, 1, nil
      transport.send_now({ t = "msg", text = "Map error: " .. tostring(err) })
      return
    end
  end
end

-- Chunks still to chart (the one being charted counts).
function M.chart_queue()
  local m = storage.f3d.map
  if not m then
    return 0
  end
  return #m.queue - m.head + 1 + (m.job and 1 or 0)
end
budget.register_queue("map", M.chart_queue)

return M
