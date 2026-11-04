-- Walks through every Factorio GUI a script can open and screenshots each one with the GUI
-- drawn (game.take_screenshot{show_gui = true}). Run by tools/ui_reference/capture.py, which
-- writes config.lua next to this file, starts the windowed game on a copy of a save, waits
-- for done.txt and copies script-output/ui_reference/*.png to art-src/ui_reference/.
--
-- Entities come from the save when it has them (so screens show real contents), otherwise
-- they are built on a flat lab surface. Nothing here is meant to be saved: the game is
-- killed afterwards.

local ok_cfg, config = pcall(require, "config")
if not ok_cfg then config = {} end
local OUT = "ui_reference/"
local RES = config.resolution or {1920, 1080}
local OPEN_TICKS = 3     -- after the previous step was closed
local SHOT_TICKS = 16    -- after opening: let the window lay out and animations settle
local STEP_TICKS = 24
local START_DELAY = 90   -- let the first frames render (and the save's own GUIs appear)
local LAB = "f3d-ui-lab"

local function only_wanted(name)
	if not config.only or #config.only == 0 then return true end
	for _, n in pairs(config.only) do
		if name == n or name:find(n, 1, true) then return true end
	end
	return false
end

-- --- the lab surface -------------------------------------------------------------------

local function lab()
	local s = game.surfaces[LAB]
	if s then return s end
	s = game.create_surface(LAB, {
		width = 512, height = 512, seed = 1, peaceful_mode = true,
		default_enable_all_autoplace_controls = false,
		autoplace_settings = {
			tile = {treat_missing_as_default = false, settings = {["grass-1"] = {}}},
			entity = {treat_missing_as_default = false, settings = {}},
			decorative = {treat_missing_as_default = false, settings = {}},
		},
	})
	s.always_day = true
	s.request_to_generate_chunks({96, 96}, 8)
	s.force_generate_chunk_requests()
	-- some starting water for pumps
	local water = {}
	for x = -8, -1 do for y = -8, 8 do water[#water + 1] = {name = "water", position = {x, y}} end end
	s.set_tiles(water)
	local eei = s.create_entity{name = "electric-energy-interface", position = {2, -4}, force = "player"}
	if eei then
		eei.electric_buffer_size = 1e12
		eei.power_production = 1e10
		eei.energy = 1e12
	end
	-- a substation grid over the lab, so every machine is powered
	for x = 0, 13 do
		for y = 0, 13 do
			s.create_entity{name = "substation", position = {x * 16 + 8, y * 16 + 8}, force = "player"}
		end
	end
	s.create_entity{name = "substation", position = {2, -1}, force = "player"}
	return s
end

local function next_slot()
	storage.slot = (storage.slot or 0) + 1
	local k = storage.slot
	-- slots between the substations: 13 columns, 16 tiles apart
	return {(k % 13) * 16 + 16, math.floor(k / 13) * 16 + 16}
end

-- --- helpers ---------------------------------------------------------------------------

local function player() return game.get_player(1) end

local function character_of(p)
	-- a fresh map starts in the crash site's cutscene
	if p.controller_type == defines.controllers.cutscene then pcall(function() p.exit_cutscene() end) end
	if p.controller_type == defines.controllers.remote then p.exit_remote_view() end
	if not p.character then
		if storage.character and storage.character.valid then
			p.set_controller{type = defines.controllers.character, character = storage.character}
		else
			p.create_character()
		end
	end
	storage.character = p.character
	return p.character
end

local function move_next_to(p, entity)
	local c = character_of(p)
	if not c then return end
	local surface = entity.surface
	local box = entity.bounding_box
	local target = {x = entity.position.x, y = box.right_bottom.y + 1.5}
	local at = surface.find_non_colliding_position("character", target, 12, 0.5) or target
	if c.surface ~= surface or c.position.x ~= at.x or c.position.y ~= at.y then
		if c.vehicle then c.vehicle.set_driver(nil) end
		p.teleport(at, surface)
	end
end

local function surfaces_in_order(p)
	local out = {}
	local seen = {}
	local function add(s)
		if s and s.valid and not seen[s.index] and not s.platform and s.name ~= LAB then
			seen[s.index] = true
			out[#out + 1] = s
		end
	end
	add(p.physical_surface or p.surface)
	add(game.surfaces.nauvis)
	for _, s in pairs(game.surfaces) do add(s) end
	return out
end

-- An entity of this prototype: the save's own (nearest surface first) or a new one in the lab.
local function find_or_make(p, name, prep, opts)
	opts = opts or {}
	if not prototypes.entity[name] then error("no prototype " .. name) end
	if not opts.fresh then
		for _, s in pairs(surfaces_in_order(p)) do
			local found = s.find_entities_filtered{name = name, force = p.force, limit = 1}
			if found[1] then return found[1], "save" end
		end
	end
	local s = lab()
	local pos = next_slot()
	local e = s.create_entity{name = name, position = pos, force = p.force,
		direction = opts.direction, raise_built = false}
	if not e then error("could not create " .. name) end
	if prep then pcall(prep, e, s) end
	return e, "lab"
end

local function open_entity(p, name, prep, opts)
	local e, where = find_or_make(p, name, prep, opts)
	move_next_to(p, e)
	if opts and opts.before_open then opts.before_open(e) end
	p.opened = e
	if p.opened ~= e then error("did not open (" .. where .. ")") end
	return {source = where, entity = name}
end

local function insert(e, items)
	for _, it in pairs(items) do pcall(function() e.insert(it) end) end
end

local function wire(a, b)
	local ra = a.get_wire_connector(defines.wire_connector_id.circuit_red, true)
	local rb = b.get_wire_connector(defines.wire_connector_id.circuit_red, true)
	ra.connect_to(rb)
end

local function scratch()
	if not storage.inv or not storage.inv.valid then storage.inv = game.create_inventory(20) end
	return storage.inv
end

local function tech_to_research(force)
	for _, t in pairs(force.technologies) do
		if t.enabled and not t.researched and t.research_unit_count_formula == nil then
			local ready = true
			for _, pre in pairs(t.prerequisites) do
				if not pre.researched then ready = false break end
			end
			if ready and #t.research_unit_ingredients > 0 then return t end
		end
	end
end

-- --- the steps -------------------------------------------------------------------------
-- Each returns a table of extra take_screenshot options (and notes for the manifest), or
-- raises an error, which is recorded and the step skipped.

local steps = {}
local function step(name, fn, shot, opt_in) steps[#steps + 1] = {name = name, fn = fn, shot = shot or {}, opt_in = opt_in} end
-- The technology screen doesn't close when `opened` is cleared, and would cover every later
-- picture: it goes last, after Factoriopedia (which close_factoriopedia_gui does close).
local LAST = {factoriopedia_item = 1, factoriopedia_entity = 2, factoriopedia_recipe = 3, research_tree = 4,
	research_tree_researched = 5, factoriopedia_fluid = 6, factoriopedia_planet = 7, factoriopedia_tile = 8,
	factoriopedia_route = 9}

-- the HUD on its own
step("hud", function(p) character_of(p) return {} end)
step("hud_research", function(p)
	character_of(p)
	local f = p.force
	if not f.current_research then
		local t = tech_to_research(f)
		if t then f.add_research(t) end
	end
	return {note = f.current_research and f.current_research.name or "no research available"}
end)
step("hud_crafting_queue", function(p)
	character_of(p)
	local n = 0
	for _, r in pairs({"iron-gear-wheel", "electronic-circuit", "transport-belt", "pipe"}) do
		pcall(function() n = n + p.begin_crafting{count = 5, recipe = r} end)
	end
	if n == 0 then
		-- not enough ingredients in the save: give the character some
		p.insert{name = "iron-plate", count = 200}
		p.insert{name = "copper-plate", count = 200}
		n = p.begin_crafting{count = 5, recipe = "iron-gear-wheel"}
		pcall(function() p.begin_crafting{count = 5, recipe = "electronic-circuit"} end)
	end
	return {note = "queued " .. n}
end)
step("hud_alerts", function(p)
	local c = character_of(p)
	local near = c.surface.find_entities_filtered{position = c.position, radius = 30, force = p.force, limit = 3}
	for i, e in pairs(near) do
		if e ~= c then
			p.add_custom_alert(e, {type = "virtual", name = "signal-" .. tostring(i)}, "Custom alert " .. i, true)
		end
	end
	return {}
end)
step("hud_selected", function(p)
	local c = character_of(p)
	local near = c.surface.find_entities_filtered{position = c.position, radius = 20, force = p.force,
		type = {"assembling-machine", "furnace", "mining-drill", "container", "inserter"}, limit = 1}
	if not near[1] then error("nothing selectable near the character") end
	-- the mouse decides the selection every frame: keep setting it until the screenshot
	storage.keep_selected = near[1]
	p.selected = near[1]
	return {note = near[1].name}
end)
step("hud_cursor_building", function(p)
	character_of(p)
	p.cursor_stack.set_stack{name = "assembling-machine-2", count = 10}
	return {}
end, {show_cursor_building_preview = true})
step("hud_cursor_item", function(p)
	character_of(p)
	p.cursor_stack.set_stack{name = "iron-plate", count = 100}
	return {}
end, {show_cursor_building_preview = true})
step("hud_chat", function(p)
	character_of(p)
	p.print("[color=yellow]Chat line[/color] from the UI capture script.")
	p.print("A second line with an [item=iron-plate] icon.")
	return {}
end)
step("alt_mode", function(p)
	character_of(p)
	p.game_view_settings.show_entity_info = true
	return {}
end, {show_entity_info = true})
-- Issue #9: Alt-mode's arrows (Interface settings: inserter, pump and machine arrows, the player's
-- own defaults): inserters four ways, machines with fluid recipes, a boiler, pumps and a recycler,
-- on the lab. Opt-in: --only alt_arrows.
step("alt_arrows", function(p)
	local s = lab()
	local o = {x = 120, y = 120}
	for _, e in pairs(s.find_entities_filtered{area = {{o.x - 32, o.y - 20}, {o.x + 32, o.y + 20}}, type = "character", invert = true}) do
		e.destroy()
	end
	p.force.enable_all_recipes()
	local function make(name, x, y, dir, recipe)
		local e = s.create_entity{name = name, position = {o.x + x, o.y + y}, direction = dir or defines.direction.north, force = "player"}
		if e and recipe then pcall(function() e.set_recipe(recipe) end) end
		return e
	end
	-- inserters between chests, each way round
	for i, d in ipairs({defines.direction.north, defines.direction.east, defines.direction.south, defines.direction.west}) do
		local x = -24 + i * 3
		make("iron-chest", x, -8)
		make(i % 2 == 0 and "fast-inserter" or "inserter", x, -7, d)
		make("iron-chest", x, -6)
		make("long-handed-inserter", x, -3, d)
	end
	make("chemical-plant", -8, -6, defines.direction.north, "sulfuric-acid")
	make("chemical-plant", -4, -6, defines.direction.east, "lubricant")
	make("oil-refinery", 3, -6, defines.direction.north, "advanced-oil-processing")
	make("assembling-machine-2", 9, -7, defines.direction.north, "electric-engine-unit")
	make("boiler", 14, -7, defines.direction.north)
	make("pump", 18, -7, defines.direction.north)
	make("pump", 20, -7, defines.direction.east)
	make("foundry", -9, 3, defines.direction.north, "molten-iron")
	make("recycler", -3, 3, defines.direction.north)
	make("recycler", 1, 3, defines.direction.east)
	make("cryogenic-plant", 7, 3, defines.direction.north, "ammonia-rocket-fuel")
	make("electromagnetic-plant", 14, 3, defines.direction.north, "holmium-solution")
	make("storage-tank", 20, 3, defines.direction.north)
	local c = character_of(p)
	if c then p.teleport({o.x, o.y + 9}, s) end
	p.game_view_settings.show_entity_info = true
	return {}
end, {show_entity_info = true, position = {120, 118}, zoom = 0.9}, true)
step("remote_view", function(p)
	local c = character_of(p)
	p.set_controller{type = defines.controllers.remote, position = {c.position.x + 20, c.position.y}, surface = c.surface}
	p.zoom = 0.5
	return {}
end, {zoom = 0.5})
step("map_view", function(p)
	local c = character_of(p)
	p.set_controller{type = defines.controllers.remote, position = c.position, surface = c.surface}
	p.zoom = 0.08
	return {note = "render_mode " .. tostring(p.render_mode)}
end, {zoom = 0.08})
step("map_view_zoomed_in", function(p)
	local c = character_of(p)
	p.set_controller{type = defines.controllers.remote, position = c.position, surface = c.surface}
	p.zoom = 0.25
	return {note = "render_mode " .. tostring(p.render_mode)}
end, {zoom = 0.25})

-- windows by GUI type
local function gui_step(name, gui)
	step(name, function(p)
		character_of(p)
		p.opened = gui
		if p.opened_gui_type ~= gui then error("opened_gui_type is " .. tostring(p.opened_gui_type)) end
		return {}
	end)
end
gui_step("character", defines.gui_type.controller)
gui_step("production", defines.gui_type.production)
step("logistic_networks", function(p)
	-- gui_type.logistic can't be opened by a script; a network can
	for _, s in pairs(surfaces_in_order(p)) do
		local nets = p.force.logistic_networks[s.name]
		if nets and nets[1] then
			move_next_to(p, nets[1].cells[1].owner)
			p.opened = nets[1]
			return {note = s.name}
		end
	end
	error("no logistic network")
end)
gui_step("trains", defines.gui_type.trains)
gui_step("achievements", defines.gui_type.achievement)
gui_step("blueprint_library", defines.gui_type.blueprint_library)
gui_step("bonuses", defines.gui_type.bonus)
gui_step("permissions", defines.gui_type.permissions)
gui_step("players", defines.gui_type.player_management)
gui_step("alerts_config", defines.gui_type.alerts_config)
gui_step("global_electric_network", defines.gui_type.global_electric_network)

step("research_tree", function(p)
	character_of(p)
	local t = p.force.current_research or tech_to_research(p.force) or p.force.technologies["automation"]
	p.open_technology_gui(t)
	return {note = t.name}
end)
step("research_tree_researched", function(p)
	character_of(p)
	p.open_technology_gui("automation")
	return {}
end)
step("factoriopedia_item", function(p)
	character_of(p)
	p.open_factoriopedia_gui(prototypes.item["iron-plate"])
	return {}
end)
step("factoriopedia_entity", function(p)
	character_of(p)
	p.open_factoriopedia_gui(prototypes.entity["assembling-machine-2"])
	return {}
end)
step("factoriopedia_recipe", function(p)
	character_of(p)
	p.open_factoriopedia_gui(prototypes.recipe["electronic-circuit"])
	return {}
end)

step("factoriopedia_fluid", function(p)
	character_of(p)
	p.open_factoriopedia_gui(prototypes.fluid["petroleum-gas"])
	return {}
end)
step("factoriopedia_planet", function(p)
	character_of(p)
	p.open_factoriopedia_gui(prototypes.space_location["vulcanus"])
	return {}
end)
step("factoriopedia_tile", function(p)
	character_of(p)
	p.open_factoriopedia_gui(prototypes.tile["concrete"])
	return {}
end)
step("factoriopedia_route", function(p)
	character_of(p)
	p.open_factoriopedia_gui(prototypes.space_connection["nauvis-vulcanus"])
	return {}
end)

-- item windows
local function item_step(name, make)
	step(name, function(p)
		character_of(p)
		local stack = make(p, scratch())
		p.opened = stack
		if p.opened_gui_type ~= defines.gui_type.item then
			error("opened_gui_type is " .. tostring(p.opened_gui_type))
		end
		return {}
	end)
end
local function blueprint_of(p, stack)
	stack.set_stack{name = "blueprint"}
	local c = character_of(p)
	local pos = c.position
	stack.create_blueprint{surface = c.surface, force = p.force,
		area = {{pos.x - 12, pos.y - 12}, {pos.x + 12, pos.y + 12}}}
	if not stack.is_blueprint_setup() then
		-- nothing around the character: take the lab's corner instead
		local s = lab()
		local e = s.create_entity{name = "assembling-machine-1", position = {40, 200}, force = p.force}
		s.create_entity{name = "inserter", position = {42, 200}, force = p.force, direction = defines.direction.east}
		stack.create_blueprint{surface = s, force = p.force, area = {{36, 196}, {46, 204}}}
	end
	stack.label = "UI reference blueprint"
	return stack
end
item_step("blueprint", function(p, inv) return blueprint_of(p, inv[1]) end)
item_step("blueprint_empty", function(p, inv) inv[2].set_stack{name = "blueprint"} return inv[2] end)
item_step("blueprint_book", function(p, inv)
	local book = inv[3]
	book.set_stack{name = "blueprint-book"}
	local contents = book.get_inventory(defines.inventory.item_main)
	blueprint_of(p, inv[4])
	contents.insert(inv[4])
	contents.insert{name = "deconstruction-planner"}
	contents.insert{name = "upgrade-planner"}
	book.label = "UI reference book"
	return book
end)
item_step("deconstruction_planner", function(p, inv)
	local d = inv[5]
	d.set_stack{name = "deconstruction-planner"}
	d.set_entity_filter(1, {name = "tree-01"})
	d.set_entity_filter(2, {name = "transport-belt"})
	return d
end)
item_step("upgrade_planner", function(p, inv)
	local u = inv[6]
	u.set_stack{name = "upgrade-planner"}
	u.set_mapper(1, "from", {type = "entity", name = "transport-belt"})
	u.set_mapper(1, "to", {type = "entity", name = "fast-transport-belt"})
	u.set_mapper(2, "from", {type = "entity", name = "assembling-machine-1"})
	u.set_mapper(2, "to", {type = "entity", name = "assembling-machine-2"})
	return u
end)
-- planners in the world (ui-planners): a blueprint held over the game (its ghosts at the mouse, when
-- the mouse is over the window), and what deconstruction and upgrade marks look like
step("cursor_blueprint", function(p)
	character_of(p)
	blueprint_of(p, p.cursor_stack)
	return {note = tostring(p.cursor_stack.valid_for_read and p.cursor_stack.is_blueprint_setup())}
end, {show_cursor_building_preview = true})
-- an empty blueprint in the cursor (Alt+B): where Factorio shows what a new blueprint includes
step("cursor_blank_blueprint", function(p)
	character_of(p)
	p.cursor_stack.set_stack{name = "blueprint"}
	return {}
end, {show_cursor_building_preview = true})
local function mark_near(p, how)
	local c = character_of(p)
	local near = c.surface.find_entities_filtered{position = c.position, radius = 12, force = p.force,
		type = {"assembling-machine", "furnace", "inserter", "transport-belt", "container", "electric-pole", "pipe"}, limit = 40}
	storage.marked = storage.marked or {}
	local n = 0
	for _, e in pairs(near) do
		if how(e) then
			storage.marked[#storage.marked + 1] = e
			n = n + 1
		end
	end
	return {note = n .. " marked"}
end
step("marks_deconstruction", function(p)
	return mark_near(p, function(e) return e.order_deconstruction(p.force, p) end)
end)
step("marks_upgrade", function(p)
	local next_of = {["transport-belt"] = "fast-transport-belt", ["fast-transport-belt"] = "express-transport-belt",
		["inserter"] = "fast-inserter", ["assembling-machine-1"] = "assembling-machine-2", ["assembling-machine-2"] = "assembling-machine-3",
		["small-electric-pole"] = "medium-electric-pole", ["stone-furnace"] = "steel-furnace"}
	return mark_near(p, function(e)
		local t = next_of[e.name]
		return t ~= nil and e.order_upgrade{target = t, force = p.force, player = p}
	end)
end)
step("armor_grid", function(p)
	character_of(p)
	local inv = scratch()
	local a = inv[7]
	a.set_stack{name = "power-armor-mk2"}
	local g = a.grid
	for _, n in pairs({"fusion-reactor-equipment", "personal-roboport-mk2-equipment", "energy-shield-mk2-equipment",
		"battery-mk2-equipment", "exoskeleton-equipment", "night-vision-equipment", "personal-laser-defense-equipment"}) do
		pcall(function() g.put{name = n} end)
	end
	p.opened = a
	return {note = tostring(p.opened_gui_type)}
end)

-- entity windows: name, optional preparation, options
local function ent(name, prep, opts)
	step("entity_" .. name:gsub("-", "_"), function(p) return open_entity(p, name, prep, opts) end)
end
local fill_chest = function(e) insert(e, {{name = "iron-plate", count = 400}, {name = "copper-cable", count = 200}, {name = "iron-gear-wheel", count = 50}}) end

ent("wooden-chest", fill_chest)
ent("iron-chest", fill_chest)
ent("steel-chest", fill_chest)
ent("passive-provider-chest", fill_chest)
ent("active-provider-chest", fill_chest)
ent("storage-chest", fill_chest)
ent("buffer-chest")
ent("requester-chest", function(e)
	local sec = e.get_requester_point().add_section()
	sec.set_slot(1, {value = "iron-plate", min = 100})
	sec.set_slot(2, {value = "electronic-circuit", min = 50})
end)
ent("assembling-machine-1", function(e) e.set_recipe("iron-gear-wheel") insert(e, {{name = "iron-plate", count = 20}}) end)
ent("assembling-machine-2", function(e) e.set_recipe("electronic-circuit") end)
ent("assembling-machine-3", function(e) e.set_recipe("engine-unit") end)
ent("stone-furnace", function(e) insert(e, {{name = "coal", count = 20}, {name = "iron-ore", count = 30}}) end)
ent("steel-furnace", function(e) insert(e, {{name = "coal", count = 20}, {name = "iron-ore", count = 30}}) end)
ent("electric-furnace", function(e) insert(e, {{name = "iron-ore", count = 30}}) end)
ent("burner-mining-drill", function(e) insert(e, {{name = "coal", count = 10}}) end)
ent("electric-mining-drill")
ent("pumpjack")
ent("offshore-pump", nil, {})
ent("boiler", function(e) insert(e, {{name = "coal", count = 20}}) end)
ent("steam-engine")
ent("steam-turbine")
ent("solar-panel")
ent("accumulator")
ent("nuclear-reactor")
ent("heat-exchanger")
ent("oil-refinery", function(e) e.set_recipe("basic-oil-processing") end)
ent("chemical-plant", function(e) e.set_recipe("plastic-bar") end)
ent("centrifuge")
ent("lab", function(e) insert(e, {{name = "automation-science-pack", count = 10}}) end)
ent("beacon")
ent("radar")
ent("small-lamp")
ent("programmable-speaker")
ent("power-switch")
ent("display-panel")
ent("pump")
ent("storage-tank")
-- windows the openable rules found (rules_openable): pipes, heat pipes, land mines and plain belts open too
ent("pipe")
ent("pipe-to-ground")
ent("heat-pipe")
ent("land-mine")
ent("burner-inserter")
ent("inserter")
ent("long-handed-inserter")
ent("fast-inserter")
ent("bulk-inserter")
ent("stack-inserter")
ent("splitter")
ent("fast-splitter")
-- a belt only has a window when it is wired to a circuit network
step("entity_transport_belt_wired", function(p)
	local s = lab()
	local pos = next_slot()
	local belt = s.create_entity{name = "transport-belt", position = pos, force = p.force}
	local cc = s.create_entity{name = "constant-combinator", position = {pos[1] + 2, pos[2]}, force = p.force}
	wire(belt, cc)
	move_next_to(p, belt)
	p.opened = belt
	if p.opened ~= belt then error("belt did not open") end
	return {source = "lab"}
end)
ent("arithmetic-combinator")
ent("decider-combinator")
ent("constant-combinator")
ent("selector-combinator")
ent("small-electric-pole")
ent("medium-electric-pole")
ent("big-electric-pole")
ent("substation")
ent("roboport", function(e) insert(e, {{name = "construction-robot", count = 10}, {name = "logistic-robot", count = 10}}) end)
ent("gun-turret", function(e) insert(e, {{name = "firearm-magazine", count = 20}}) end)
ent("laser-turret")
ent("flamethrower-turret")
ent("artillery-turret")
ent("rocket-turret")
ent("tesla-turret")
ent("railgun-turret")
ent("train-stop")
ent("rail-signal")
ent("rail-chain-signal")
ent("locomotive")
ent("cargo-wagon")
ent("fluid-wagon")
ent("artillery-wagon")
ent("car", function(e) insert(e, {{name = "coal", count = 10}}) end)
ent("tank", function(e) insert(e, {{name = "coal", count = 10}}) end)
ent("spidertron")
ent("rocket-silo")
ent("cargo-landing-pad")
ent("cargo-bay")
ent("foundry")
ent("electromagnetic-plant")
ent("cryogenic-plant")
ent("biochamber")
ent("biolab")
ent("recycler")
ent("big-mining-drill")
ent("agricultural-tower")
ent("heating-tower")
ent("captive-biter-spawner")
ent("lightning-collector")
ent("fusion-reactor")
ent("fusion-generator")
ent("crusher")
ent("asteroid-collector")
ent("thruster")

-- space platform hub: opened from remote view, since characters can't stand on platforms
step("entity_space_platform_hub", function(p)
	character_of(p)
	local hub
	for _, pl in pairs(p.force.platforms) do
		if pl.valid and pl.hub and pl.hub.valid then hub = pl.hub break end
	end
	if not hub then
		local pl = p.force.create_space_platform{name = "UI reference", planet = "nauvis", starter_pack = "space-platform-starter-pack"}
		pl.apply_starter_pack()
		hub = pl.hub
	end
	if not hub then error("no hub") end
	p.set_controller{type = defines.controllers.remote, position = hub.position, surface = hub.surface}
	p.opened = hub
	if p.opened ~= hub then error("hub did not open") end
	return {source = "platform"}
end)
step("space_map", function(p)
	character_of(p)
	local pl
	for _, x in pairs(p.force.platforms) do if x.valid and x.hub then pl = x break end end
	if not pl then error("no platform") end
	p.set_controller{type = defines.controllers.remote, position = pl.hub.position, surface = pl.surface}
	p.zoom = 0.05
	return {}
end, {zoom = 0.05})

-- The entity windows the steps above can't reach (none in the save, or they need rails, a platform
-- or a partner): built where they work. Each opens what Factorio opens for it and notes what that
-- was, since some (cargo bay, thruster) open another entity's window or none.
local function opened_note(p, e)
	local o = p.opened
	local what = o and (o.object_name == "LuaEntity" and o.name or tostring(o.object_name)) or "nothing"
	return {source = "built", entity = e.name, opened = what, gui = tostring(p.opened_gui_type)}
end

local function wagon_on_rails(name)
	return function(p)
		local s = lab()
		local pos = next_slot()
		local y = math.floor(pos[2] / 2) * 2 + 1
		for x = pos[1] - 14, pos[1] + 14, 2 do
			s.create_entity{name = "straight-rail", position = {x + 1, y}, direction = defines.direction.east, force = p.force}
		end
		local e = s.create_entity{name = name, position = {pos[1] + 1, y}, direction = defines.direction.east, force = p.force}
		if not e then error("could not place " .. name .. " on the rails") end
		if name == "fluid-wagon" then pcall(function() e.insert_fluid({name = "crude-oil", amount = 20000}) end) end
		if name == "artillery-wagon" then insert(e, {{name = "artillery-shell", count = 5}}) end
		move_next_to(p, e)
		p.opened = e
		return opened_note(p, e)
	end
end
step("entity_fluid_wagon_lab", wagon_on_rails("fluid-wagon"))
step("entity_artillery_wagon_lab", wagon_on_rails("artillery-wagon"))

local function in_lab(name, prep)
	return function(p)
		local s = lab()
		local pos = next_slot()
		local e = s.create_entity{name = name, position = pos, force = p.force}
		if not e then error("could not create " .. name) end
		if prep then pcall(prep, e, s) end
		move_next_to(p, e)
		p.opened = e
		return opened_note(p, e)
	end
end
step("entity_lightning_collector_lab", in_lab("lightning-collector"))
step("entity_fusion_generator_lab", in_lab("fusion-generator", function(e, s)
	-- its plasma comes from a fusion reactor north of it
	s.create_entity{name = "fusion-reactor", position = {e.position.x, e.position.y - 6}, force = e.force}
end))

-- On a space platform (in remote view, as the hub is): a cargo bay against the hub, a thruster at the back.
local function on_platform(name, offset)
	return function(p)
		character_of(p)
		local pl
		for _, x in pairs(p.force.platforms) do if x.valid and x.hub and x.hub.valid then pl = x break end end
		if not pl then
			pl = p.force.create_space_platform{name = "UI reference", planet = "nauvis", starter_pack = "space-platform-starter-pack"}
			pl.apply_starter_pack()
		end
		if not (pl and pl.hub) then error("no platform") end
		local s, hub = pl.surface, pl.hub
		local tiles = {}
		for x = -24, 24 do for y = -24, 32 do
			tiles[#tiles + 1] = {name = "space-platform-foundation", position = {hub.position.x + x, hub.position.y + y}}
		end end
		s.set_tiles(tiles)
		local at = {hub.position.x + offset[1], hub.position.y + offset[2]}
		local e = s.find_entities_filtered{name = name, position = at, radius = 1, limit = 1}[1]
			or s.create_entity{name = name, position = at, force = p.force}
		if not e then error("could not place " .. name) end
		p.set_controller{type = defines.controllers.remote, position = e.position, surface = s}
		p.opened = e
		return opened_note(p, e)
	end
end
step("entity_cargo_bay_platform", on_platform("cargo-bay", {0, 6}))
step("entity_thruster_platform", on_platform("thruster", {-8, 22}))

-- The platform's panel in each of its states (`--only platform_panel`, owner's H3 and H7): stopped,
-- paused, waiting at a stop with another next, waiting for departure (a rocket on its way up), travelling
-- (in the world and in the map view, both ways along a connection), and on board. A step may hold its
-- picture until `ready` says the platform got there.
local STATE_NAMES = {}
for k, v in pairs(defines.space_platform_state) do STATE_NAMES[v] = k end

local function ref_platform(p)
	for _, l in pairs({"vulcanus", "gleba", "fulgora", "aquilo"}) do pcall(function() p.force.unlock_space_location(l) end) end
	for _, x in pairs(p.force.platforms) do
		if x.valid and x.hub and x.hub.valid then return x end
	end
	local pl = p.force.create_space_platform{name = "UI reference", planet = "nauvis", starter_pack = "space-platform-starter-pack"}
	pl.apply_starter_pack()
	if not (pl and pl.hub) then error("no platform") end
	return pl
end

local function watch(p, pl, zoom)
	p.set_controller{type = defines.controllers.remote, position = pl.hub.position, surface = pl.surface}
	if zoom then p.zoom = zoom end
end

-- At `where` with `records` as its schedule (nil: none).
local function park(pl, where, records, paused)
	pl.schedule = nil
	if pl.space_location == nil or pl.space_location.name ~= where then pl.space_location = where end
	pl.paused = paused or false
	if records then pl.schedule = {current = 1, records = records} end
end

local function state_is(pl, name)
	return function() return pl.valid and STATE_NAMES[pl.state] == name end
end

local function note(pl)
	return function()
		local conn = pl.space_connection
		return {state = STATE_NAMES[pl.state], loc = pl.space_location and pl.space_location.name,
			conn = conn and conn.name, d = pl.distance, speed = pl.speed}
	end
end

local WAIT_LONG = {{type = "time", compare_type = "or", ticks = 60 * 600}}

step("platform_panel_1_stopped", function(p)
	character_of(p)
	local pl = ref_platform(p)
	park(pl, "nauvis", nil, false)
	watch(p, pl)
	return {after = note(pl)}
end)
step("platform_panel_2_paused", function(p)
	character_of(p)
	local pl = ref_platform(p)
	park(pl, "nauvis", {{station = "nauvis", wait_conditions = WAIT_LONG}, {station = "vulcanus"}}, true)
	watch(p, pl)
	return {after = note(pl)}
end)
step("platform_panel_3_waiting", function(p)
	character_of(p)
	local pl = ref_platform(p)
	park(pl, "nauvis", {{station = "nauvis", wait_conditions = WAIT_LONG}, {station = "vulcanus"}})
	watch(p, pl)
	return {ready = state_is(pl, "waiting_at_station"), after = note(pl)}
end)
step("platform_panel_4_waiting_map", function(p)
	character_of(p)
	local pl = ref_platform(p)
	park(pl, "nauvis", {{station = "nauvis", wait_conditions = WAIT_LONG}, {station = "vulcanus"}})
	watch(p, pl, 0.05)
	return {ready = state_is(pl, "waiting_at_station"), after = note(pl)}
end, {zoom = 0.05})
-- Waiting for departure: a rocket is on its way up with cargo for the platform, whose schedule now
-- wants it elsewhere, so it holds until the pod has docked.
step("platform_panel_5_departure", function(p)
	local c = character_of(p)
	local pl = ref_platform(p)
	park(pl, "nauvis", nil, false)
	local s = game.surfaces.nauvis
	local at = s.find_non_colliding_position("rocket-silo", {c.position.x + 20, c.position.y}, 60, 1) or {c.position.x + 20, c.position.y}
	local silo = s.create_entity{name = "rocket-silo", position = at, force = p.force}
	if not silo then error("no silo") end
	local eei = s.create_entity{name = "electric-energy-interface", position = {at.x - 8, at.y + 8}, force = p.force}
	eei.power_production = 1e9
	eei.electric_buffer_size = 1e10
	s.create_entity{name = "substation", position = {at.x - 5, at.y + 8}, force = p.force}
	s.create_entity{name = "substation", position = {at.x + 3, at.y + 8}, force = p.force}
	silo.rocket_parts = silo.prototype.rocket_parts_required
	watch(p, pl)
	local launched = false
	return {ready = function()
		if not silo.valid then return true end
		if not launched then
			if silo.rocket_silo_status ~= defines.rocket_silo_status.rocket_ready then return false end
			local inv = silo.get_inventory(defines.inventory.rocket_silo_rocket)
			if inv then inv.insert{name = "iron-plate", count = 50} end
			-- a built platform takes rockets at its hub (as the bridge's space.lua launches them)
			launched = silo.launch_rocket({type = defines.cargo_destination.station, station = pl.hub})
			if launched then
				pl.schedule = {current = 1, records = {{station = "vulcanus"}}}
			end
			return false
		end
		return STATE_NAMES[pl.state] == "waiting_for_departure"
	end, after = function()
		local out = note(pl)()
		out.launched = launched
		out.silo = silo.valid and silo.rocket_silo_status or -1
		return out
	end, timeout = 60 * 60}
end)
local function travelling(conn, d, to, zoom, speed)
	return function(p)
		character_of(p)
		local pl = ref_platform(p)
		pl.schedule = {current = 1, records = {{station = to}}}
		pl.paused = false
		pl.space_connection = conn
		pl.distance = d
		pl.speed = speed or 2
		watch(p, pl, zoom)
		return {after = note(pl)}
	end
end
step("platform_panel_6_travelling", travelling("nauvis-vulcanus", 0.3, "vulcanus"))
step("platform_panel_7_travelling_map", travelling("nauvis-vulcanus", 0.3, "vulcanus", 0.05), {zoom = 0.05})
-- The owner's example, Aquilo to Gleba: along gleba-aquilo backwards, its distance counting down.
step("platform_panel_8_travelling_back", travelling("gleba-aquilo", 0.7, "gleba"))
step("platform_panel_9_travelling_slow", travelling("nauvis-vulcanus", 0.6, "vulcanus", nil, 0.01))
-- On board: the character in the hub, stopped, then travelling.
step("platform_panel_a_onboard_stopped", function(p)
	character_of(p)
	local pl = ref_platform(p)
	park(pl, "nauvis", {{station = "nauvis", wait_conditions = WAIT_LONG}, {station = "vulcanus"}})
	if not p.enter_space_platform(pl) then error("could not enter the platform") end
	return {ready = state_is(pl, "waiting_at_station"), after = note(pl)}
end)
step("platform_panel_b_onboard_travelling", function(p)
	local pl = ref_platform(p)
	if p.physical_surface ~= pl.surface then
		character_of(p)
		if not p.enter_space_platform(pl) then error("could not enter the platform") end
	end
	pl.schedule = {current = 1, records = {{station = "vulcanus"}}}
	pl.paused = false
	pl.space_connection = "nauvis-vulcanus"
	pl.distance = 0.3
	pl.speed = 2
	return {after = note(pl)}
end)
step("platform_panel_c_onboard_map", function(p)
	local pl = ref_platform(p)
	if p.physical_surface ~= pl.surface then error("not on board") end
	watch(p, pl, 0.05)
	return {after = note(pl)}
end, {zoom = 0.05})

-- inventory rules (rules.lua): the game's own slot actions, recorded for the client to copy
require("rules").add(step, character_of, lab)

-- What opening each buildable entity opens (opt-in, `--only rules_openable`): every entity
-- prototype with an item that places it is built on the lab surface (on rails for rolling stock),
-- opened as a click would (p.opened = e), and what `p.opened` then is gets recorded: the entity
-- itself, another entity (a cargo bay's hub), something else, or nothing. The client's
-- entity_ui.lua NO_WINDOW and its window kinds are checked against this list.
step("rules_openable", function(p)
	local c = character_of(p)
	local s = lab()
	p.teleport({8, 8}, s)
	local found = {}
	local names = {}
	for name, proto in pairs(prototypes.entity) do
		if proto.items_to_place_this and #proto.items_to_place_this > 0 and not proto.hidden then
			names[#names + 1] = name
		end
	end
	table.sort(names)
	local ROLLING = {locomotive = true, ["cargo-wagon"] = true, ["fluid-wagon"] = true, ["artillery-wagon"] = true}
	local at = {x = 40, y = 41}
	for x = at.x - 16, at.x + 16, 2 do
		s.create_entity{name = "straight-rail", position = {x + 1, at.y}, direction = defines.direction.east, force = p.force}
	end
	for _, name in pairs(names) do
		local proto = prototypes.entity[name]
		local r = {name = name, type = proto.type}
		local ok, err = pcall(function()
			local pos = ROLLING[proto.type] and {at.x + 1, at.y} or {at.x, at.y + 12}
			local dir = ROLLING[proto.type] and defines.direction.east or nil
			local e = s.create_entity{name = name, position = pos, direction = dir, force = p.force, raise_built = false}
			if not e then r.opened = "not built" return end
			p.teleport({e.position.x, e.position.y + 5}, s)
			pcall(function() p.opened = e end)
			local o = p.opened
			if o == nil then
				r.opened = "nothing"
			elseif o.object_name == "LuaEntity" then
				r.opened = (o == e) and "itself" or o.name
			else
				r.opened = tostring(o.object_name)
			end
			r.gui = tostring(p.opened_gui_type)
			pcall(function() p.opened = nil end)
			-- what else creating it brought along (a rocket silo's rocket, a hub's bays) goes too
			for _, other in pairs(s.find_entities_filtered{area = {{at.x - 12, at.y + 3}, {at.x + 12, at.y + 24}}}) do
				if other.valid and other.type ~= "character" then other.destroy() end
			end
			if e.valid then e.destroy() end
		end)
		if not ok then r.opened = "error: " .. tostring(err) end
		found[#found + 1] = r
	end
	p.teleport({8, 8}, s)
	helpers.write_file(OUT .. "rules_openable.json", helpers.table_to_json(found))
	return {note = #found .. " entities"}
end, nil, true)

-- --- the driver ------------------------------------------------------------------------

local function wanted_steps()
	local out, last = {}, {}
	for _, s in pairs(steps) do
		-- opt-in steps (scripted checks rather than pictures) run only when --only names them
		if only_wanted(s.name) and not (s.opt_in and not (config.only and #config.only > 0)) then
			if LAST[s.name] then last[LAST[s.name]] = s else out[#out + 1] = s end
		end
	end
	-- Factoriopedia closes, the technology screen doesn't: Factoriopedia's later pages go before it
	for _, i in ipairs({1, 2, 3, 6, 7, 8, 9, 4, 5}) do if last[i] then out[#out + 1] = last[i] end end
	return out
end

local function reset(p)
	storage.keep_selected = nil
	for _, e in pairs(storage.marked or {}) do
		if e.valid then
			pcall(function() e.cancel_deconstruction(p.force, p) end)
			pcall(function() e.cancel_upgrade(p.force, p) end)
		end
	end
	storage.marked = nil
	if p.opened then pcall(function() p.opened = nil end) end
	pcall(function() p.close_factoriopedia_gui() end)
	if p.controller_type == defines.controllers.remote then pcall(function() p.exit_remote_view() end) end
	pcall(function() p.clear_cursor() end)
	pcall(function() p.selected = nil end)
	p.game_view_settings.show_entity_info = false
end

local function finish(list)
	helpers.write_file(OUT .. "manifest.json", helpers.table_to_json(storage.results or {}))
	helpers.write_file(OUT .. "done.txt", "done " .. #list)
	storage.done = true
end

-- A step's `ready` and `after` (functions can't go in storage; the game is never saved).
local held = {}

script.on_event(defines.events.on_tick, function()
	if storage.done then return end
	local p = player()
	if not p or not p.connected then return end
	storage.t = (storage.t or 0) + 1
	if storage.t < START_DELAY then return end
	local list = wanted_steps()
	storage.idx = storage.idx or 1
	storage.phase = (storage.phase or -1) + 1
	local s = list[storage.idx]
	if not s then finish(list) return end
	local phase = storage.phase
	storage.results = storage.results or {}
	if storage.keep_selected and storage.keep_selected.valid then p.selected = storage.keep_selected end
	if phase == 0 then
		reset(p)
		storage.shot_at = nil
		held = {}
	elseif phase == OPEN_TICKS then
		local ok, res = pcall(s.fn, p)
		storage.current_ok = ok
		if ok and type(res) == "table" then
			held = {ready = res.ready, after = res.after, timeout = res.timeout}
			res.ready, res.after, res.timeout = nil, nil, nil
		end
		storage.results[#storage.results + 1] = {name = s.name, ok = ok,
			error = (not ok) and tostring(res) or nil, info = ok and res or nil}
		if not ok then log("[f3d-ui-capture] " .. s.name .. ": " .. tostring(res)) end
	elseif phase >= SHOT_TICKS and storage.current_ok and not storage.shot_at then
		-- a step that waits for something holds its picture until then (or its timeout)
		if held.ready then
			local ok, ready = pcall(held.ready, p)
			if not ok then storage.results[#storage.results].ready_error = tostring(ready) end
			if ok and not ready and phase < SHOT_TICKS + (held.timeout or 600) then return end
		end
		local opts = {player = p, show_gui = true, resolution = RES, zoom = 1, force_render = true,
			path = OUT .. s.name .. ".png", hide_clouds = true}
		for k2, v in pairs(s.shot) do opts[k2] = v end
		game.take_screenshot(opts)
		storage.shot_at = phase
		if held.after then
			local ok, found = pcall(held.after, p)
			storage.results[#storage.results].shot = ok and found or tostring(found)
		end
	end
	-- the next step as many ticks after the picture as before (STEP_TICKS in all, unheld)
	if phase >= (storage.shot_at or SHOT_TICKS) + (STEP_TICKS - SHOT_TICKS) - 1 then
		storage.idx = storage.idx + 1
		storage.phase = -1
	end
end)

-- --- hover mode (tools/ui_reference/hover.py) ------------------------------------------
-- Tooltips, hover and clicks can't be scripted, and a script's p.selected is replaced by the
-- mouse every frame. In hover mode (config.hover) each step prepares the game, then writes
-- ui_reference/hover_<n>.json with actions in GUI pixels of the 1920x1080 window for hover.py,
-- which moves and clicks the real mouse, presses keys and grabs the window from the screen,
-- then presses Ctrl+Shift+F9 (data.lua's f3d-ui-next): the next step starts after that.

local hover_steps = {}
local function hover(name, ticks, fn) hover_steps[#hover_steps + 1] = {name = name, ticks = ticks, fn = fn} end
local function grab_at(name, x, y, extra)
	local a = {{"move", x, y}, {"wait", 1.4}, {"grab", name}}
	for _, e in pairs(extra or {}) do a[#a + 1] = e end
	return a
end

-- The screen position (GUI pixels) of a map position at zoom 1, the character in the middle.
local function screen_of(p, pos)
	local c = p.character or p
	return math.floor(960 + (pos.x - c.position.x) * 32), math.floor(540 + (pos.y - c.position.y) * 32)
end

local function near(p, types, radius)
	local c = character_of(p)
	local found = c.surface.find_entities_filtered{position = c.position, radius = radius or 14, force = p.force,
		type = types, limit = 1}
	if not found[1] then error("nothing of that type near the character") end
	return found[1]
end

local function hud_at(name, x, y)
	hover(name, 150, function(p) character_of(p) return grab_at(name, x, y) end)
end

-- the tool bar, quickbar and shortcut bar (positions measured on hud.png)
hud_at("hover_tool_character", 33, 1010)
hud_at("hover_tool_gun", 80, 1010)
hud_at("hover_tool_ammo", 160, 1052)
hud_at("hover_tool_armor", 40, 1052)
hud_at("hover_quickbar_item", 780, 1052)
hud_at("hover_quickbar_empty", 1100, 1052)
hud_at("hover_quickbar_page", 730, 1052)
hover("click_quickbar_page", 200, function(p)
	character_of(p)
	return {{"move", 730, 1052}, {"wait", 0.3}, {"click", "left"}, {"wait", 1.0}, {"grab", "click_quickbar_page"},
		{"move", 760, 900}, {"wait", 1.4}, {"grab", "click_quickbar_page_hover"}, {"key", "escape"}}
end)
hud_at("hover_shortcut_alt", 1197, 1010)
hud_at("hover_shortcut_blueprint", 1357, 1010)
hover("click_shortcut_expand", 200, function(p)
	character_of(p)
	return {{"move", 1546, 999}, {"wait", 1.4}, {"grab", "hover_shortcut_expand"}, {"click", "left"}, {"wait", 1.0},
		{"grab", "click_shortcut_expand"}, {"move", 1300, 600}, {"wait", 1.0}, {"grab", "click_shortcut_expand_hover"},
		{"key", "escape"}, {"wait", 0.4}}
end)
-- top right: research, side menu buttons, minimap
hover("hover_research", 150, function(p)
	character_of(p)
	if not p.force.current_research then
		local t = tech_to_research(p.force)
		if t then p.force.add_research(t) end
	end
	return grab_at("hover_research", 1790, 28)
end)
hud_at("hover_side_button", 1691, 76)
hud_at("hover_side_mute", 1811, 116)
hud_at("hover_minimap", 1790, 270)
-- the world: the entity info panel and tooltips, with and without Alt-mode
-- The player's real zoom isn't readable and setting it may not take: hover the entity at a few
-- scales (pixels per tile 32 at zoom 1) and grab each; one of <name>_32/_48/_64 hits it.
local function world_at(name, types, radius, alt)
	hover(name, 150, function(p)
		local e = near(p, types, radius)
		p.zoom = 1
		if alt then p.game_view_settings.show_entity_info = true end
		local c = p.character or p
		local actions = {}
		for _, ppt in pairs({32, 48, 64}) do
			local x = math.floor(960 + (e.position.x - c.position.x) * ppt)
			local y = math.floor(540 + (e.position.y - c.position.y) * ppt)
			actions[#actions + 1] = {"move", x, y}
			actions[#actions + 1] = {"wait", 1.4}
			actions[#actions + 1] = {"grab", name .. "_" .. ppt}
		end
		return actions
	end)
end
world_at("hover_entity", {"assembling-machine", "furnace"}, 14)
world_at("hover_entity_alt", {"assembling-machine", "furnace"}, 14, true)
world_at("hover_entity_belt", {"transport-belt"}, 20)
world_at("hover_entity_pole", {"electric-pole"}, 20)
world_at("hover_entity_pipe", {"pipe"}, 20, true)
-- the character screen (positions measured on character.png)
local function controller_at(name, x, y)
	hover(name, 150, function(p)
		character_of(p)
		p.opened = defines.gui_type.controller
		return grab_at(name, x, y)
	end)
end
controller_at("hover_character_slot", 344, 250)
controller_at("hover_character_recipe", 1215, 290)
controller_at("hover_character_recipe_red", 1215, 610)
controller_at("hover_character_group", 1308, 222)
controller_at("hover_character_request", 780, 280)
controller_at("hover_character_pipette", 678, 205)
controller_at("hover_character_color", 710, 205)
controller_at("hover_character_add_section", 960, 641)
controller_at("hover_character_trash", 780, 716)
controller_at("hover_character_empty_row", 520, 700)
hover("click_character_color", 200, function(p)
	character_of(p)
	p.opened = defines.gui_type.controller
	return {{"move", 710, 205}, {"wait", 0.3}, {"click", "left"}, {"wait", 1.0}, {"grab", "click_character_color"},
		{"key", "escape"}}
end)
hover("click_character_search", 200, function(p)
	character_of(p)
	p.opened = defines.gui_type.controller
	return {{"move", 1563, 163}, {"wait", 0.3}, {"click", "left"}, {"wait", 0.3}, {"type", "iron"}, {"wait", 0.8},
		{"grab", "click_character_search"}, {"key", "escape"}}
end)
-- the crafting queue
hover("hover_crafting_queue", 200, function(p)
	character_of(p)
	p.insert{name = "iron-plate", count = 200}
	p.insert{name = "copper-plate", count = 200}
	pcall(function() p.begin_crafting{count = 5, recipe = "iron-gear-wheel"} end)
	pcall(function() p.begin_crafting{count = 5, recipe = "electronic-circuit"} end)
	return {{"wait", 0.5}, {"grab", "crafting_queue"}, {"move", 215, 1060}, {"wait", 1.4}, {"grab", "hover_crafting_queue"}}
end)
-- alerts: custom alerts show after a moment
hover("alerts_bar", 300, function(p)
	local c = character_of(p)
	local found = c.surface.find_entities_filtered{position = c.position, radius = 30, force = p.force, limit = 4}
	local n = 0
	for _, e in pairs(found) do
		if e ~= c then
			n = n + 1
			p.add_custom_alert(e, {type = "virtual", name = "signal-" .. tostring(n)}, "Custom alert " .. n, true)
		end
	end
	return {{"move", 960, 300}, {"wait", 2.5}, {"grab", "alerts_bar"}}
end)
-- chat: printed lines, then the console opened with its key
hover("chat_open", 260, function(p)
	character_of(p)
	p.print("[color=yellow]Chat line[/color] from the UI capture script.")
	p.print("A second line with an [item=iron-plate] icon.")
	return {{"move", 960, 300}, {"wait", 0.8}, {"grab", "chat_lines"}, {"key", "grave"}, {"wait", 0.8},
		{"grab", "chat_open"}, {"type", "hello"}, {"wait", 0.4}, {"grab", "chat_typing"}, {"key", "escape"},
		{"wait", 0.2}, {"key", "escape"}}
end)

-- the ammo slot with a magazine part used (Factorio's green bar), and its tooltip
hover("hud_ammo_partial", 200, function(p)
	local c = character_of(p)
	local ammo = c.get_inventory(defines.inventory.character_ammo)
	local slot
	for i = 1, #ammo do
		if not slot and ammo[i].valid_for_read then slot = i end
	end
	if not slot then error("no ammo in the save's character") end
	ammo[slot].ammo = math.max(1, math.floor(prototypes.item[ammo[slot].name].magazine_size * 0.4))
	local x = 40 + 40 * slot
	return {{"move", 960, 300}, {"wait", 0.8}, {"grab", "hud_ammo_partial"}, {"move", x - 4, 1052}, {"move", x, 1052},
		{"wait", 1.4}, {"grab", "hover_ammo_partial"}}
end)
-- tips and tricks from the side menu (second row, first button)
hover("click_tips", 260, function(p)
	character_of(p)
	return {{"move", 1691, 116}, {"wait", 0.3}, {"click", "left"}, {"wait", 1.5}, {"grab", "click_tips"},
		{"key", "escape"}, {"wait", 0.4}}
end)
-- the Esc menu (pauses the game: grabbed while paused, then closed so the steps go on)
hover("esc_menu", 260, function(p)
	character_of(p)
	return {{"move", 300, 300}, {"wait", 0.3}, {"key", "escape"}, {"wait", 1.2}, {"grab", "esc_menu"},
		{"key", "escape"}, {"wait", 0.6}}
end)

-- the in-game settings: Esc, then Settings, then each page of it (the game stays paused while they
-- are open). Esc on a page goes back to the list, Esc on the list to the game menu, Esc there resumes.
hover("esc_settings", 300, function(p)
	character_of(p)
	local a = {{"move", 300, 300}, {"wait", 0.3}, {"key", "escape"}, {"wait", 1.0}, {"move", 959, 640}, {"wait", 0.8},
		{"grab", "esc_menu_hover"}, {"click", "left"}, {"wait", 1.2}, {"grab", "esc_settings"}}
	for i, page in ipairs({"graphics", "controls", "sounds", "interface", "other"}) do
		local y = 397 + (i - 1) * 54
		for _, act in ipairs({{"move", 959, y}, {"wait", 0.3}, {"click", "left"}, {"wait", 1.5},
				{"grab", "esc_settings_" .. page}, {"key", "escape"}, {"wait", 0.8}}) do
			a[#a + 1] = act
		end
	end
	for _, act in ipairs({{"key", "escape"}, {"wait", 0.6}, {"key", "escape"}, {"wait", 0.6}}) do a[#a + 1] = act end
	return a
end)

-- entity windows' popups (positions measured on the entity_* pictures of the same entities): a
-- constant combinator's signal value, a decider's constant operand, a train's "Change train group"
local function click_in(name, entity, x, y, extra)
	hover(name, 200, function(p)
		open_entity(p, entity)
		local a = {{"move", x, y}, {"wait", 0.3}, {"click", "left"}, {"wait", 1.0}, {"grab", name}}
		for _, e in pairs(extra or {}) do a[#a + 1] = e end
		a[#a + 1] = {"key", "escape"}
		return a
	end)
end
click_in("click_constant_signal", "constant-combinator", 785, 625)
click_in("click_decider_constant", "decider-combinator", 848, 560)
click_in("click_train_group", "locomotive", 112, 97)

-- the space map: remote view on a platform, then the Surfaces panel's "Space map" (no script can
-- open it); then a platform chosen in the Surfaces panel
hover("space_map_solar", 400, function(p)
	character_of(p)
	local pl
	for _, x in pairs(p.force.platforms) do if x.valid and x.hub then pl = x break end end
	if not pl then error("no platform") end
	p.set_controller{type = defines.controllers.remote, position = pl.hub.position, surface = pl.surface}
	-- a first click on the title bar brings the game window to the front
	return {{"move", 700, 18}, {"wait", 0.5}, {"click", "left"}, {"wait", 1.0}, {"move", 64, 94}, {"wait", 0.6},
		{"click", "left"}, {"move", 960, 800}, {"wait", 3.0}, {"grab", "space_map_solar"}, {"move", 960, 540}, {"wait", 1.4},
		{"grab", "space_map_solar_center"}, {"move", 140, 240}, {"wait", 1.4}, {"grab", "space_map_solar_hover"},
		{"click", "left"}, {"move", 960, 800}, {"wait", 2.5}, {"grab", "space_map_solar_platform"}}
end)
-- the trains overview on another planet (the save's player stands on Vulcanus, which has none):
-- the surface dropdown opened, its second entry chosen, then a card hovered
hover("trains_cards", 400, function(p)
	character_of(p)
	p.opened = defines.gui_type.trains
	return {{"move", 233, 83}, {"wait", 0.4}, {"click", "left"}, {"wait", 0.8}, {"grab", "trains_dropdown"},
		{"move", 233, 112}, {"wait", 0.3}, {"click", "left"}, {"move", 1000, 600}, {"wait", 1.5}, {"grab", "trains_nauvis"},
		{"move", 745, 330}, {"wait", 1.4}, {"grab", "trains_card_hover"}, {"key", "escape"}}
end)
-- the logistic networks window from the side menu, in Factorio's remote view
hover("logistic_networks_click", 300, function(p)
	character_of(p)
	return {{"move", 1731, 116}, {"wait", 0.6}, {"click", "left"}, {"wait", 1.5}, {"grab", "logistic_networks_click"},
		{"move", 140, 120}, {"click", "left"}, {"wait", 1.5}, {"grab", "logistic_networks_click_net"}, {"key", "escape"}}
end)

local function hover_wanted()
	local out = {}
	for _, s in pairs(hover_steps) do
		if only_wanted(s.name) then out[#out + 1] = s end
	end
	return out
end

local function hover_tick()
	if storage.done then return end
	local p = player()
	if not p or not p.connected then return end
	storage.t = (storage.t or 0) + 1
	if storage.t < START_DELAY then return end
	local list = hover_wanted()
	storage.hi = storage.hi or 1
	storage.h_at = storage.h_at or storage.t
	local s = list[storage.hi]
	if not s then finish(list) return end
	storage.results = storage.results or {}
	local k = storage.t - storage.h_at
	if k == 0 then
		reset(p)
		if p.character then p.character.surface.always_day = true end  -- a copy of the save
	elseif k == OPEN_TICKS then
		local ok, res = pcall(s.fn, p)
		storage.results[#storage.results + 1] = {name = s.name, ok = ok, error = (not ok) and tostring(res) or nil}
		if ok then
			helpers.write_file(OUT .. string.format("hover_%03d.json", storage.hi),
				helpers.table_to_json({name = s.name, actions = res}))
		else
			log("[f3d-ui-capture] " .. s.name .. ": " .. tostring(res))
		end
	elseif (storage.acked and k > OPEN_TICKS + 10) or k >= s.ticks * 8 then
		storage.acked = nil
		storage.hi = storage.hi + 1
		storage.h_at = storage.t + 1
	end
end

if config.hover then
	script.on_event(defines.events.on_tick, hover_tick)
	script.on_event("f3d-ui-next", function() storage.acked = true end)
end
