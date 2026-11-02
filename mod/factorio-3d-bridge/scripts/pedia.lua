-- Factoriopedia's data, from `prototypes.*`: an index of everything it lists (items, fluids,
-- entities without an item of their own, tiles, recipes not named after their product,
-- technologies, planets and other space locations, qualities), and one page on request with what
-- Factoriopedia shows: stats, made in, used in, recipes, mining results, unlocked by...
--
-- Answers only requests and keeps nothing in `storage`. The reverse lookups (which recipes make an
-- item, which machines craft a category) are module-local caches built from prototypes alone, so
-- they are the same on every peer. Prototype keys differ by type and between 2.0 and 2.1, and
-- reading one a prototype doesn't have throws, so every read goes through `get`.

local transport = require("scripts.transport")
local puppet = require("scripts.puppet")

local M = {}

local INDEX_PER_MESSAGE = 120
local LIST_MAX = 150

local function get(obj, key)
  local ok, v = pcall(function() return obj[key] end)
  if ok then
    return v
  end
  return nil
end

-- A prototype method called without arguments (2.x methods taking an optional quality).
local function call(obj, key, ...)
  local args = { ... }
  local ok, v = pcall(function() return obj[key](table.unpack(args)) end)
  if ok then
    return v
  end
  return nil
end

local function round(v, places)
  if type(v) ~= "number" then
    return nil
  end
  local m = 10 ^ (places or 3)
  return math.floor(v * m + 0.5) / m
end

local function hidden(proto)
  return get(proto, "hidden") == true or get(proto, "hidden_in_factoriopedia") == true or get(proto, "parameter") == true
end

local function group_of(proto)
  local g, sg = get(proto, "group"), get(proto, "subgroup")
  return g and g.name or "other", sg and sg.name or "other", g and g.order or "z", sg and sg.order or "z"
end

local function table_of(kind)
  local ok, t = pcall(function() return prototypes[kind] end)
  return ok and t or {}
end

---------------------------------------------------------------------------------------------
-- Reverse lookups, built once per load from prototypes

local lookups

local function amounts(list)
  local out = {}
  for _, p in pairs(list or {}) do
    local amount = p.amount
    if amount == nil and p.amount_min and p.amount_max then
      amount = (p.amount_min + p.amount_max) / 2
    end
    amount = (amount or 1) * (p.probability or 1)
    out[#out + 1] = { p.type or "item", p.name, round(amount, 3) }
  end
  return out
end

local function build()
  local l = { made = {}, used = {}, recycled = {}, machines = {}, unlocked = {}, mined = {}, placed_by = {} }
  for name, r in pairs(table_of("recipe")) do
    local recycling = false
    for _, cat in pairs(get(r, "categories") or { get(r, "category") }) do
      if cat == "recycling" or cat == "recycling-or-hand-crafting" then
        recycling = true
      end
    end
    for _, p in pairs(get(r, "products") or {}) do
      local key = (p.type or "item") .. "/" .. p.name
      local into = recycling and l.recycled or l.made
      into[key] = into[key] or {}
      table.insert(into[key], name)
    end
    if not recycling then
      for _, i in pairs(get(r, "ingredients") or {}) do
        local key = (i.type or "item") .. "/" .. i.name
        l.used[key] = l.used[key] or {}
        table.insert(l.used[key], name)
      end
    end
  end
  for name, e in pairs(table_of("entity")) do
    for cat in pairs(get(e, "crafting_categories") or {}) do
      l.machines[cat] = l.machines[cat] or {}
      table.insert(l.machines[cat], name)
    end
    local mp = get(e, "mineable_properties")
    if mp and mp.minable and not hidden(e) then
      for _, p in pairs(mp.products or {}) do
        local key = (p.type or "item") .. "/" .. p.name
        l.mined[key] = l.mined[key] or {}
        table.insert(l.mined[key], name)
      end
    end
  end
  for name, t in pairs(table_of("technology")) do
    for _, effect in pairs(get(t, "effects") or {}) do
      if effect.type == "unlock-recipe" and effect.recipe then
        l.unlocked[effect.recipe] = l.unlocked[effect.recipe] or {}
        table.insert(l.unlocked[effect.recipe], name)
      end
    end
  end
  for _, list in pairs({ l.made, l.used, l.recycled, l.machines, l.unlocked, l.mined }) do
    for _, names in pairs(list) do
      table.sort(names)
    end
  end
  return l
end

local function lookup()
  if not lookups then
    lookups = build()
  end
  return lookups
end

local function capped(list)
  local out = {}
  for i = 1, math.min(#(list or {}), LIST_MAX) do
    out[i] = list[i]
  end
  return out
end

---------------------------------------------------------------------------------------------
-- The index

-- [kind, name, group, subgroup, order]: what Factoriopedia's grid lists. An entity placed by an
-- item, and a recipe named after its product, are on that item's page instead.
local function index_records()
  local out, groups = {}, {}
  local function add(kind, name, proto, order_prefix)
    local g, sg, go, sgo = group_of(proto)
    groups[g] = go
    out[#out + 1] = { kind, name, g, sg, sgo .. "|" .. (order_prefix or "") .. (get(proto, "order") or "") }
  end
  for name, p in pairs(table_of("item")) do
    if not hidden(p) then
      add("item", name, p)
    end
  end
  for name, p in pairs(table_of("fluid")) do
    if not hidden(p) then
      add("fluid", name, p)
    end
  end
  local items = table_of("item")
  for name, p in pairs(table_of("entity")) do
    if not hidden(p) then
      local placed = false
      for _, it in pairs(get(p, "items_to_place_this") or {}) do
        local item = items[type(it) == "table" and it.name or it]
        if item and not hidden(item) then
          placed = true
        end
      end
      if not placed and get(p, "selectable_in_game") ~= false then
        add("entity", name, p)
      end
    end
  end
  for name, p in pairs(table_of("tile")) do
    if not hidden(p) and #(get(p, "items_to_place_this") or {}) == 0 then
      add("tile", name, p)
    end
  end
  local fluids = table_of("fluid")
  for name, p in pairs(table_of("recipe")) do
    if not hidden(p) and not items[name] and not fluids[name] then
      add("recipe", name, p)
    end
  end
  for name, p in pairs(table_of("space_location")) do
    if not hidden(p) then
      add(get(p, "type") == "planet" and "planet" or "space-location", name, p)
    end
  end
  for name, p in pairs(table_of("quality")) do
    if not hidden(p) then
      add("quality", name, p, string.format("%03d", get(p, "level") or 0))
    end
  end
  for name, p in pairs(table_of("technology")) do
    if not hidden(p) then
      out[#out + 1] = { "technology", name, "technologies", "technologies", get(p, "order") or "" }
    end
  end
  groups.technologies = "zzz"
  table.sort(out, function(a, b)
    if a[3] ~= b[3] then
      return a[3] < b[3]
    end
    if a[5] ~= b[5] then
      return a[5] < b[5]
    end
    return a[2] < b[2]
  end)
  local g = {}
  for name, order in pairs(groups) do
    g[#g + 1] = { name, order }
  end
  table.sort(g, function(a, b) return a[2] == b[2] and a[1] < b[1] or a[2] < b[2] end)
  return out, g
end

-- {}: the whole index as `pidx` parts (reliable), the item groups (tabs) with the first part.
-- Prototypes only: made once per load (16-38 ms on Space Age).
local index_cache

-- control.lua's warm-up: the index and the reverse lookups made before a client asks.
function M.warm_index()
  index_cache = index_cache or { index_records() }
end

function M.warm_lookups()
  lookup()
end

function M.index()
  index_cache = index_cache or { index_records() }
  local list, groups = index_cache[1], index_cache[2]
  local parts = math.max(1, math.ceil(#list / INDEX_PER_MESSAGE))
  for part = 1, parts do
    local slice = {}
    for i = (part - 1) * INDEX_PER_MESSAGE + 1, math.min(part * INDEX_PER_MESSAGE, #list) do
      slice[#slice + 1] = list[i]
    end
    local msg = { t = "pidx", part = part, parts = parts, l = slice }
    if part == 1 then
      msg.g = groups
    end
    transport.send_reliable(msg)
  end
end

---------------------------------------------------------------------------------------------
-- Pages

local function pollution(dict, per)
  local out = {}
  for k, v in pairs(dict or {}) do
    if type(v) == "number" and v ~= 0 then
      out[k] = round(v * per, 4)
    end
  end
  return next(out) and out or nil
end

local function resistances(proto)
  local out = {}
  for damage, r in pairs(get(proto, "resistances") or {}) do
    if (r.decrease or 0) ~= 0 or (r.percent or 0) ~= 0 then
      out[#out + 1] = { damage, round(r.decrease or 0, 2), round((r.percent or 0) * 100, 1) }
    end
  end
  table.sort(out, function(a, b) return a[1] < b[1] end)
  return #out > 0 and out or nil
end

-- Names from an array of names or of prototypes / {name = ...} tables, or from a dictionary keyed
-- by name (prerequisites).
local function names_of(list)
  local out = {}
  for k, v in pairs(list or {}) do
    if type(v) == "string" then
      out[#out + 1] = v
    elseif type(k) == "string" then
      out[#out + 1] = k
    else
      out[#out + 1] = v.name
    end
  end
  table.sort(out)
  return out
end

local function energy_source(e)
  if get(e, "electric_energy_source_prototype") then
    local src = get(e, "electric_energy_source_prototype")
    return "electric", src and round((get(src, "drain") or 0) * 60, 1)
  elseif get(e, "burner_prototype") then
    return "burner"
  elseif get(e, "heat_energy_source_prototype") then
    return "heat"
  elseif get(e, "fluid_energy_source_prototype") then
    return "fluid"
  elseif get(e, "void_energy_source_prototype") then
    return "void"
  end
  return nil
end

local function item_page(name, p, d)
  local l = lookup()
  local key = "item/" .. name
  d.type = get(p, "type")
  d.stack = get(p, "stack_size")
  local fuel = get(p, "fuel_value") or 0
  if fuel > 0 then
    d.fuel = fuel
    d.fcat = names_of(get(p, "fuel_categories"))
    d.facc = round(get(p, "fuel_acceleration_multiplier"), 2)
    d.ftop = round(get(p, "fuel_top_speed_multiplier"), 2)
  end
  local burnt = get(p, "burnt_result")
  d.burnt = burnt and burnt.name or nil
  local place = get(p, "place_result")
  d.place = place and place.name or nil
  local tile = get(p, "place_as_tile_result")
  d.tile = tile and tile.result and tile.result.name or nil
  local equipment = get(p, "place_as_equipment_result")
  d.equip = equipment and equipment.name or nil
  d.weight = get(p, "weight")
  local spoil = call(p, "get_spoil_ticks") or get(p, "spoil_ticks") or 0
  if spoil > 0 then
    d.spoil = spoil
    local into = get(p, "spoil_result")
    d.spoil_to = into and into.name or nil
  end
  local effects = get(p, "module_effects")
  if type(effects) == "table" and next(effects) then
    local fx = {}
    for k, v in pairs(effects) do
      fx[k] = round(type(v) == "table" and v.bonus or v, 3)
    end
    d.module = fx
    d.mcat = get(p, "category")
    d.tier = get(p, "tier")
  end
  local ammo = get(p, "ammo_category")
  d.ammo = ammo and ammo.name or nil
  d.made = capped(l.made[key])
  d.used = capped(l.used[key])
  d.recycle = capped(l.recycled[key])
  d.mined = capped(l.mined[key])
  d.rocket = nil
  local launch = get(p, "rocket_launch_products")
  if launch and #launch > 0 then
    d.rocket = amounts(launch)
  end
  -- The entity the item builds: its stats go on the same page, as in Factoriopedia.
  if place and not hidden(place) then
    d.entity = {}
    M.entity_page(place.name, place, d.entity)
  end
end

local function fluid_page(name, p, d)
  local l = lookup()
  local key = "fluid/" .. name
  d.temp = round(get(p, "default_temperature"), 1)
  d.max_temp = round(get(p, "max_temperature"), 1)
  d.heat = get(p, "heat_capacity")
  local fuel = get(p, "fuel_value") or 0
  d.fuel = fuel > 0 and fuel or nil
  d.made = capped(l.made[key])
  d.used = capped(l.used[key])
  d.mined = capped(l.mined[key])
  local pumped = {}
  for ename, e in pairs(table_of("entity")) do
    if get(e, "type") == "offshore-pump" and not hidden(e) then
      pumped[#pumped + 1] = ename
    end
  end
  local tiles = {}
  for tname, t in pairs(table_of("tile")) do
    local f = get(t, "fluid")
    if f and f.name == name and not hidden(t) then
      tiles[#tiles + 1] = tname
    end
  end
  table.sort(tiles)
  d.tiles = capped(tiles)
  d.pumped = #tiles > 0 and pumped or nil
end

function M.entity_page(name, e, d)
  local l = lookup()
  d.type = get(e, "type")
  local hp = call(e, "get_max_health") or get(e, "max_health")
  d.hp = hp and hp > 0 and round(hp, 1) or nil
  d.res = resistances(e)
  d.size = { get(e, "tile_width"), get(e, "tile_height") }
  local energy, drain = energy_source(e)
  d.etype = energy
  d.drain = drain and drain > 0 and drain or nil
  local usage = call(e, "get_max_energy_usage") or get(e, "energy_usage") or 0
  if usage > 0 then
    d.energy = round(usage * 60, 1) -- watts
  end
  local power = call(e, "get_max_power_output") or 0
  if power > 0 then
    d.power = round(power * 60, 1)
  end
  d.poll = pollution(get(e, "emissions_per_second"), 60)
  local speed = call(e, "get_crafting_speed")
  if speed and speed > 0 then
    d.craft = round(speed, 3)
  end
  local mining = get(e, "mining_speed")
  if mining and mining > 0 then
    d.mine_speed = round(mining, 3)
  end
  local belt = get(e, "belt_speed")
  if belt and belt > 0 then
    d.belt = round(belt * 60 * 8, 2) -- items per second for a full belt (8 per tile, two lanes)
  end
  local research = call(e, "get_researching_speed")
  if research and research > 0 then
    d.research = round(research, 3)
  end
  local rot = call(e, "get_inserter_rotation_speed")
  if rot and rot > 0 then
    d.rot = round(rot * 60 * 360, 1) -- degrees per second
  end
  local slots = get(e, "module_inventory_size") or 0
  d.modules = slots > 0 and slots or nil
  local effects = get(e, "allowed_effects")
  if type(effects) == "table" and slots > 0 then
    local fx = {}
    for k, v in pairs(effects) do
      if v then
        fx[#fx + 1] = k
      end
    end
    table.sort(fx)
    d.effects = fx
  end
  local cats = get(e, "crafting_categories")
  if cats and d.type ~= "character" then
    local recipes, seen = {}, {}
    local names = {}
    for cat in pairs(cats) do
      names[#names + 1] = cat
    end
    table.sort(names)
    for _, cat in ipairs(names) do
      for rname, r in pairs(table_of("recipe")) do
        if not seen[rname] and not hidden(r) then
          for _, rc in pairs(get(r, "categories") or {}) do
            if rc == cat then
              seen[rname] = true
              recipes[#recipes + 1] = rname
              break
            end
          end
        end
      end
    end
    table.sort(recipes)
    d.cats = names
    d.recipes = capped(recipes)
  end
  local mp = get(e, "mineable_properties")
  if mp and mp.minable then
    d.mine = amounts(mp.products)
    d.mtime = round(mp.mining_time, 2)
    d.fluid_req = mp.required_fluid
  end
  d.items = names_of(get(e, "items_to_place_this"))
  local up = get(e, "next_upgrade")
  d.next = up and up.name or nil
  -- Every circuit-connectable entity has a wire reach; Factorio lists it for poles only.
  local wire = d.type == "electric-pole" and call(e, "get_max_wire_distance")
  if wire and wire > 0 then
    d.wire = round(wire, 1)
  end
  local supply = call(e, "get_supply_area_distance")
  if supply and supply > 0 then
    d.supply = round(supply * 2, 1)
  end
  local range = get(e, "turret_range")
  d.range = range and range > 0 and range or nil
  local under = get(e, "max_underground_distance")
  d.under = under and under > 0 and under or nil
  local inv = call(e, "get_inventory_size", defines.inventory.chest)
  d.inv = inv and inv > 0 and inv or nil
  local radius = call(e, "get_mining_drill_radius") or get(e, "mining_drill_radius")
  d.mradius = radius and radius > 0 and round(radius * 2, 1) or nil
  local resource_cats = get(e, "resource_categories")
  if resource_cats then
    local can = {}
    for rname, r in pairs(table_of("entity")) do
      local rc = get(r, "type") == "resource" and get(r, "resource_category")
      if rc and resource_cats[rc] and not hidden(r) then
        can[#can + 1] = rname
      end
    end
    table.sort(can)
    d.can_mine = capped(can)
  end
  local lab_inputs = get(e, "lab_inputs")
  d.packs = lab_inputs and names_of(lab_inputs) or nil
  local burner = get(e, "burner_prototype")
  if burner then
    local fc = {}
    for c in pairs(get(burner, "fuel_categories") or {}) do
      fc[#fc + 1] = c
    end
    table.sort(fc)
    d.fuels = fc
  end
  local max_speed = get(e, "speed")
  if d.type == "unit" and max_speed then
    d.speed = round(max_speed * 60, 2)
  end
  return d
end

local function recipe_page(name, r, d)
  local l = lookup()
  d.ing = amounts(get(r, "ingredients"))
  d.prod = amounts(get(r, "products"))
  d.time = round(get(r, "energy"), 3)
  d.cats = get(r, "categories") or { get(r, "category") }
  local made_in, seen = {}, {}
  for _, cat in pairs(d.cats or {}) do
    for _, m in ipairs(l.machines[cat] or {}) do
      if not seen[m] and not hidden(prototypes.entity[m]) then
        seen[m] = true
        made_in[#made_in + 1] = m
      end
    end
  end
  table.sort(made_in)
  d.made_in = made_in
  d.unlocked = capped(l.unlocked[name])
  local c = puppet.get()
  local force = c and c.force or game.forces.player
  local fr = force and get(force, "recipes") and force.recipes[name]
  d.enabled = fr and (get(fr, "enabled") and 1 or 0) or nil
  d.poll_mult = round(get(r, "emissions_multiplier"), 2)
  d.max_prod = round(get(r, "maximum_productivity"), 2)
  local effects = get(r, "allowed_effects")
  if type(effects) == "table" then
    local fx = {}
    for k, v in pairs(effects) do
      if v then
        fx[#fx + 1] = k
      end
    end
    table.sort(fx)
    d.effects = fx
  end
end

-- [type, target, count]: what a trigger technology needs done (2.x research_trigger).
function M.trigger_of(proto)
  local t = get(proto, "research_trigger")
  if not t then
    return nil
  end
  local target = t.item or t.entity or t.fluid or t.tile
  if type(target) == "table" then
    target = target.name
  end
  return { t.type or "", target or "", t.count or t.amount or 1 }
end

-- [[type, recipe or modifier target, value], ...] for a technology's effects.
function M.effects_of(proto)
  local out = {}
  for _, e in pairs(get(proto, "effects") or {}) do
    if e.type == "unlock-recipe" then
      out[#out + 1] = { e.type, e.recipe or "", 0 }
    else
      local target = e.ammo_category or e.turret_id or e.item or e.space_location or e.quality or e.recipe or ""
      out[#out + 1] = { e.type or "", tostring(target), round(type(e.modifier) == "number" and e.modifier or (e.change or 0), 4) or 0 }
    end
  end
  return out
end

local function technology_page(name, t, d)
  local c = puppet.get()
  local force = c and c.force or game.forces.player
  local tech = force.technologies[name]
  d.pre = names_of(get(t, "prerequisites"))
  local succ = {}
  for sname in pairs(get(t, "successors") or {}) do
    succ[#succ + 1] = sname
  end
  table.sort(succ)
  d.succ = succ
  local ings = {}
  for _, i in pairs((tech and get(tech, "research_unit_ingredients")) or get(t, "research_unit_ingredients") or {}) do
    ings[#ings + 1] = { i.name, i.amount }
  end
  d.cost = ings
  d.count = tech and get(tech, "research_unit_count") or get(t, "research_unit_count")
  d.time = round(((tech and get(tech, "research_unit_energy")) or get(t, "research_unit_energy") or 0) / 60, 2)
  d.formula = get(t, "research_unit_count_formula")
  d.level = tech and get(tech, "level") or get(t, "level")
  d.max_level = get(t, "max_level")
  d.effects = M.effects_of(t)
  d.trigger = M.trigger_of(t)
  if tech then
    d.state = get(tech, "researched") and 2 or 1
    d.saved = round(get(tech, "saved_progress") or 0, 3)
  end
end

local function tile_page(name, t, d)
  d.walk = round(get(t, "walking_speed_modifier"), 2)
  d.friction = round(get(t, "vehicle_friction_modifier"), 2)
  d.absorb = pollution(get(t, "absorptions_per_second"), 60)
  d.items = names_of(get(t, "items_to_place_this"))
  local mp = get(t, "mineable_properties")
  if mp and mp.minable then
    d.mine = amounts(mp.products)
    d.mtime = round(mp.mining_time, 2)
  end
  local f = get(t, "fluid")
  d.fluid = f and f.name or nil
  local c = get(t, "map_color")
  d.color = c and { round(c.r, 3), round(c.g, 3), round(c.b, 3) } or nil
  d.foundation = get(t, "is_foundation") and 1 or nil
end

local function location_page(name, p, d)
  d.props = {}
  for k, v in pairs(get(p, "surface_properties") or {}) do
    d.props[k] = round(v, 3)
  end
  d.dist = round(get(p, "distance"), 2)
  d.solar = round(get(p, "solar_power_in_space"), 2)
  d.kind = get(p, "type")
  local links = {}
  for cname, conn in pairs(table_of("space_connection")) do
    local from, to = get(conn, "from"), get(conn, "to")
    if from and to and (from.name == name or to.name == name) then
      links[#links + 1] = { from.name == name and to.name or from.name, round(get(conn, "length"), 0) or 0 }
    end
  end
  table.sort(links, function(a, b) return a[1] < b[1] end)
  d.links = links
end

local QUALITY_KEYS = { "default_multiplier", "crafting_machine_speed_multiplier", "crafting_machine_energy_usage_multiplier",
  "inventory_size_multiplier", "range_multiplier", "module_speed_multiplier", "beacon_power_usage_multiplier",
  "mining_drill_resource_drain_multiplier", "accumulator_capacity_multiplier", "lab_research_speed_multiplier" }

local function quality_page(name, q, d)
  d.level = get(q, "level")
  local nxt = get(q, "next")
  d.next = nxt and nxt.name or nil
  d.prob = round(get(q, "next_probability"), 3)
  local c = get(q, "color")
  d.color = c and { round(c.r, 3), round(c.g, 3), round(c.b, 3) } or nil
  local mult = {}
  for _, k in ipairs(QUALITY_KEYS) do
    local v = get(q, k)
    if type(v) == "number" then
      mult[k] = round(v, 3)
    end
  end
  d.mult = mult
end

local PAGES = {
  item = { "item", item_page }, fluid = { "fluid", fluid_page }, entity = { "entity", M.entity_page },
  recipe = { "recipe", recipe_page }, technology = { "technology", technology_page }, tile = { "tile", tile_page },
  planet = { "space_location", location_page }, ["space-location"] = { "space_location", location_page },
  quality = { "quality", quality_page },
}

-- Pages read only prototypes, but for recipes and technologies (the force's), so the rest are kept
-- once made (an entity's page looks through every recipe: 5-15 ms).
local FORCE_PAGES = { recipe = true, technology = true }
local page_cache = {}

-- {kind, name}: `pedia` with that page, or `found = 0` when there is no such prototype.
function M.page(cmd)
  local kind, name = tostring(cmd.kind or ""), tostring(cmd.name or "")
  local spec = PAGES[kind]
  local proto = spec and table_of(spec[1])[name]
  if not proto then
    transport.send_now({ t = "pedia", kind = kind, name = name, found = 0, d = {} })
    return
  end
  local key = kind .. "/" .. name
  local d = page_cache[key]
  if not d then
    d = {}
    local g, sg = group_of(proto)
    d.group, d.sub = g, sg
    spec[2](name, proto, d)
    if not FORCE_PAGES[kind] then
      page_cache[key] = d
    end
  end
  transport.send_now({ t = "pedia", kind = kind, name = name, found = 1, d = d })
end

return M
