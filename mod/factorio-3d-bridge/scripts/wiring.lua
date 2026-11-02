-- Red, green and copper wires, as Factorio's wire tools make them (Alt+R / Alt+G / Alt+C): click
-- one entity, then another, to connect them; the same pair again disconnects them. Shift+click on
-- a pole removes its copper cables. In 2.x wires cost nothing; the shortcuts need their research
-- (electronics for copper, circuit network for red and green), as in Factorio.
--
-- Commands run from on_packet, which every peer replays in the same order.

local puppet = require("scripts.puppet")
local world = require("scripts.world")
local transport = require("scripts.transport")

local M = {}

local COMBINATORS = { ["arithmetic-combinator"] = true, ["decider-combinator"] = true, ["selector-combinator"] = true }
local RESEARCH = { w = "electronics", r = "circuit-network", g = "circuit-network" }

-- Which of the entity's connectors a click at (mx, my) means: a combinator's output is on the side
-- it faces, its input the other; a power switch has a copper connector on each side.
function M.connector_id(e, kind, mx, my)
  local ids = defines.wire_connector_id
  local p = e.position
  if kind == "w" then
    if e.type == "power-switch" then
      return (mx or p.x) < p.x and ids.power_switch_left_copper or ids.power_switch_right_copper
    end
    return ids.pole_copper
  end
  if COMBINATORS[e.type] then
    local a = (e.direction or 0) / 16 * 2 * math.pi
    local along = ((mx or p.x) - p.x) * math.sin(a) - ((my or p.y) - p.y) * math.cos(a)
    if along > 0 then
      return kind == "r" and ids.combinator_output_red or ids.combinator_output_green
    end
    return kind == "r" and ids.combinator_input_red or ids.combinator_input_green
  end
  return kind == "r" and ids.circuit_red or ids.circuit_green
end

local function researched(c, kind)
  local ok, done = pcall(function() return c.force.technologies[RESEARCH[kind]].researched end)
  return not ok or done ~= false
end

-- The entity at one end ({u, p, x, y, mx?, my?}), if the character can reach it.
local function end_entity(c, ref)
  if type(ref) ~= "table" then
    return nil
  end
  local e = puppet.find_target(c.surface, ref)
  if not (e and e.valid) then
    puppet.message("Nothing to wire there")
    return nil
  end
  if not puppet.can_reach(c, e) then
    puppet.message("Out of reach")
    return nil
  end
  return e
end

local function resend(...)
  local s = storage.f3d
  for _, e in ipairs({ ... }) do
    if e.valid and e.unit_number and world.is_subscribed(e.surface, e.position) then
      transport.send_reliable({ t = "upd", e = world.record(e) })
      if s.wire_sigs then
        s.wire_sigs[e.unit_number] = world.wire_signature(e)
      end
    end
  end
end

-- {k = "r" | "g" | "w", a = {u, p, x, y, mx?, my?}, b = {...}}: connects the two ends, or
-- disconnects them if that wire is already there.
function M.wire(cmd)
  local c = puppet.get()
  local kind = cmd.k
  if not (c and RESEARCH[kind]) then
    return
  end
  if not researched(c, kind) then
    return puppet.message("Requires research: " .. (kind == "w" and "Electronics" or "Circuit network"))
  end
  local a = end_entity(c, cmd.a)
  local b = a and end_entity(c, cmd.b)
  if not b then
    return
  end
  local ca = a.get_wire_connector(M.connector_id(a, kind, (tonumber(cmd.a.mx) or 0) / 256, (tonumber(cmd.a.my) or 0) / 256), true)
  local cb = b.get_wire_connector(M.connector_id(b, kind, (tonumber(cmd.b.mx) or 0) / 256, (tonumber(cmd.b.my) or 0) / 256), true)
  if not (ca and cb) or ca == cb then
    return puppet.message(kind == "w" and "Copper wire connects electric poles and power switches" or "That can't take a circuit wire")
  end
  if ca.is_connected_to(cb) then
    ca.disconnect_from(cb)
  else
    if not ca.can_wire_reach(cb) then
      return puppet.message("Wire can't reach that far")
    end
    if not ca.connect_to(cb, false) then
      return puppet.message("Can't connect these")
    end
  end
  resend(a, b)
end

-- {u, p, x, y}: removes every copper cable of a pole (Factorio's "remove pole cables").
function M.clear(cmd)
  local c = puppet.get()
  if not c then
    return
  end
  local e = end_entity(c, cmd)
  if not e then
    return
  end
  if e.type ~= "electric-pole" then
    return puppet.message("Only electric poles have cables to remove")
  end
  local conn = e.get_wire_connector(defines.wire_connector_id.pole_copper, false)
  if not conn then
    return
  end
  local others = {}
  for _, connection in pairs(conn.connections) do
    others[#others + 1] = connection.target.owner
  end
  conn.disconnect_all()
  resend(e, table.unpack(others))
end

return M
