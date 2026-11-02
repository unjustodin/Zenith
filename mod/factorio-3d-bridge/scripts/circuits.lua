-- The circuit network for machine screens: the signals on an entity's red and green networks,
-- and combinators' settings, which the client can change. Wires themselves ride in the entity
-- records (world.lua, extra.r and extra.g).

local M = {}

local COMBINATORS = {
  ["arithmetic-combinator"] = true, ["decider-combinator"] = true, ["selector-combinator"] = true,
  ["constant-combinator"] = true,
}

function M.is_combinator(e)
  return COMBINATORS[e.type] == true
end

local function signal_list(e, connector)
  local out = {}
  for _, s in pairs(e.get_signals(connector) or {}) do
    out[#out + 1] = { s.signal.type or "item", s.signal.name, s.count }
  end
  return out
end

local function network_id(e, connector)
  local ok, net = pcall(function() return e.get_circuit_network(connector) end)
  return ok and net and net.network_id or nil
end

-- {r = [[type, name, count], ...], g = ..., ri?, gi? (network ids)}: what the entity sees on its
-- red and green networks (a combinator's input side), or nil when it is on none. Combinators add
-- `out` = {r, g, ri?, gi?}, their output side.
function M.signals(e)
  local ids = defines.wire_connector_id
  local ok, red = pcall(signal_list, e, ids.circuit_red)
  local ok2, green = pcall(signal_list, e, ids.circuit_green)
  local ri, gi = network_id(e, ids.circuit_red), network_id(e, ids.circuit_green)
  local out_side
  if COMBINATORS[e.type] and e.type ~= "constant-combinator" then
    local ok3, ro = pcall(signal_list, e, ids.combinator_output_red)
    local ok4, go = pcall(signal_list, e, ids.combinator_output_green)
    local roi, goi = network_id(e, ids.combinator_output_red), network_id(e, ids.combinator_output_green)
    if ok3 and ok4 and (roi or goi) then
      out_side = { r = ro, g = go, ri = roi, gi = goi }
    end
  end
  if not (ok and ok2) or (#red == 0 and #green == 0 and not ri and not gi and not out_side) then
    return nil
  end
  return { r = red, g = green, ri = ri, gi = gi, out = out_side }
end

local function section_filters(section)
  local list = {}
  for _, f in pairs(section and section.filters or {}) do
    if f.value and f.value.name then
      local q = f.value.quality
      q = type(q) == "table" and q.name or q
      local entry = { f.value.type or "item", f.value.name, f.min or 0 }
      if q and q ~= "normal" then
        entry[4] = q
      end
      list[#list + 1] = entry
    end
  end
  return list
end

-- A combinator's settings as plain data: for arithmetic, decider and selector combinators their
-- `parameters` as the game gives them (the client sends the same shape back); for a constant
-- combinator {enabled, signals = [[type, name, count, quality?], ...] (its first section),
-- sections = [{g (group, "" none), on (0/1), m (multiplier), s (signals)}, ...]}.
function M.settings(e)
  local b = e.get_control_behavior()
  if not b then
    return nil
  end
  if e.type == "constant-combinator" then
    local sections = {}
    local ok, count = pcall(function() return b.sections_count end)
    for i = 1, ok and count or 1 do
      local section = b.get_section(i)
      if section then
        local okg, g = pcall(function() return section.group end)
        local oka, on = pcall(function() return section.active end)
        local okm, m = pcall(function() return section.multiplier end)
        sections[#sections + 1] = { g = okg and g or "", on = (not oka or on ~= false) and 1 or 0,
          m = okm and m or 1, s = section_filters(section) }
      end
    end
    return { enabled = b.enabled, signals = sections[1] and sections[1].s or {}, sections = sections }
  end
  return b.parameters
end

local function filters_of(list)
  local filters = {}
  for _, sig in ipairs(list or {}) do
    if type(sig) == "table" and type(sig[2]) == "string" then
      local q = type(sig[4]) == "string" and sig[4] or "normal"
      filters[#filters + 1] = { value = { type = sig[1], name = sig[2], quality = q, comparator = "=" },
        min = math.floor(tonumber(sig[3]) or 0) }
    end
  end
  return filters
end

-- Sets what M.settings returns. With `sections` every section is rewritten (and extra ones
-- removed); with only `signals`, the first. Errors (a bad signal name, a wrong shape) are the
-- caller's to report.
function M.apply(e, cb)
  local b = e.get_control_behavior()
  if e.type == "constant-combinator" then
    b = b or e.get_or_create_control_behavior()
    b.enabled = cb.enabled ~= false
    if type(cb.sections) == "table" then
      local want = #cb.sections
      for i, sec in ipairs(cb.sections) do
        local section = b.get_section(i) or b.add_section()
        local group = type(sec.g) == "string" and sec.g or ""
        -- A section joined to a group takes the group's signals; editing them edits the group,
        -- as in Factorio.
        if section.group ~= group then
          section.group = group
        elseif type(sec.s) == "table" then
          section.filters = filters_of(sec.s)
        end
        section.active = sec.on ~= 0
        if tonumber(sec.m) then
          section.multiplier = tonumber(sec.m)
        end
      end
      local ok, count = pcall(function() return b.sections_count end)
      for i = (ok and count or want), want + 1, -1 do
        b.remove_section(i)
      end
      return
    end
    local section = b.get_section(1) or b.add_section()
    section.filters = filters_of(cb.signals)
    return
  end
  b = b or e.get_or_create_control_behavior()
  b.parameters = cb
end

return M
