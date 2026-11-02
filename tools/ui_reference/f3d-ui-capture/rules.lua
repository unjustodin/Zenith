-- The inventory rules of the real game, for the 3D client's slot clicks to copy: each scenario
-- fills the character's main inventory (and a chest, furnace or assembler in the lab), plays one
-- or more of the game's own inventory actions through LuaPlayer (cursor_transfer is a left click
-- on a slot, cursor_split a right click, stack_transfers the Shift / Ctrl clicks, clear_cursor Q,
-- pipette Q over an entity), and records what the cursor, the hand and the inventories hold
-- afterwards. The results go into the manifest (info.rules) as the oracle for
-- client/tests/ui_test.gd, tools/live_check.py --only input and docs/UI-DIFFERENCES.md ("Input").
--
-- Opt-in (`--only rules_inventory`): it empties the character's inventory while it runs and
-- puts it back after, but nothing else should run beside it.

local M = {}

local function stack_of(s)
	if s and s.valid_for_read then
		local q = "normal"
		pcall(function() q = s.quality.name end)
		return {s.name, s.count, q ~= "normal" and q or nil}
	end
	return 0
end

local function slots(inv, n)
	local out = {}
	for i = 1, math.min(n, #inv) do out[i] = stack_of(inv[i]) end
	return out
end

local function inv_name(index)
	for k, v in pairs(defines.inventory) do
		if v == index then return k end
	end
	return tostring(index)
end

function M.add(step, character_of, lab)
	step("rules_inventory", function(p)
		-- a fresh Space Age map starts in the landing cutscene, without a character
		if p.controller_type == defines.controllers.cutscene then pcall(function() p.exit_cutscene() end) end
		if not p.character then
			pcall(function() p.set_controller{type = defines.controllers.god} end)
			pcall(function() p.create_character() end)
		end
		local c = character_of(p)
		local main = p.get_main_inventory()
		local keep = game.create_inventory(#main)
		for i = 1, #main do keep[i].transfer_stack(main[i]) end
		local guns = c.get_inventory(defines.inventory.character_guns)
		local ammo = c.get_inventory(defines.inventory.character_ammo)
		local keep_guns = game.create_inventory(#guns + #ammo)
		for i = 1, #guns do keep_guns[i].transfer_stack(guns[i]) end
		for i = 1, #ammo do keep_guns[#guns + i].transfer_stack(ammo[i]) end
		local s = lab()
		p.teleport({20, 44}, s)
		local x = 0
		local function machine(name, prep)
			x = x + 6
			local e = s.create_entity{name = name, position = {x, 40}, force = p.force}
			if prep then prep(e) end
			return e
		end
		local results = {}
		local scenario_body
		local function scenario(name, setup, actions, target_name)
			local ok, err = pcall(scenario_body, name, setup, actions, target_name)
			if not ok then
				results[#results + 1] = {name = name, error = tostring(err)}
				pcall(function() if p.opened then p.opened = nil end end)
			end
		end
		scenario_body = function(name, setup, actions, target_name)
			p.clear_cursor()
			main.clear()
			guns.clear()
			ammo.clear()
			local target = target_name and machine(target_name) or nil
			local tinv
			for _, id in pairs({"chest", "furnace_source", "crafter_input", "assembling_machine_input"}) do
				if target and not tinv and defines.inventory[id] then tinv = target.get_inventory(defines.inventory[id]) end
			end
			for i, st in pairs(setup.main or {}) do if st ~= 0 then main[i].set_stack{name = st[1], count = st[2]} end end
			if target and setup.recipe then target.set_recipe(setup.recipe) end
			for i, st in pairs(setup.target or {}) do if st ~= 0 then tinv[i].set_stack{name = st[1], count = st[2]} end end
			if target and setup.open then p.opened = target end
			local log = {}
			for _, a in ipairs(actions) do
				local ok, r = pcall(a[2], p, main, target, tinv, guns, ammo)
				log[#log + 1] = {a[1], ok and (type(r) == "table" and r or tostring(r)) or ("error: " .. tostring(r))}
			end
			local hand = p.hand_location
			local out = {name = name, actions = log, cursor = stack_of(p.cursor_stack),
				ghost = p.cursor_ghost and p.cursor_ghost.name and p.cursor_ghost.name.name or nil,
				hand = hand and {inv_name(hand.inventory), hand.slot} or nil,
				main = slots(main, 6), guns = slots(guns, 3), ammo = slots(ammo, 3)}
			if target then
				out.target = {}
				for _, inv_id in pairs({"chest", "furnace_source", "fuel", "furnace_result", "crafter_input", "crafter_output",
						"assembling_machine_input", "assembling_machine_output"}) do
					local ok, inv = pcall(function() return defines.inventory[inv_id] and target.get_inventory(defines.inventory[inv_id]) end)
					if ok and inv then out.target[inv_id] = slots(inv, 4) end
				end
			end
			if p.opened then p.opened = nil end
			if target then target.destroy() end
			results[#results + 1] = out
		end
		local function click(i) return {"left " .. i, function(pl, m) return pl.cursor_transfer(m, i) end} end
		local function rclick(i) return {"right " .. i, function(pl, m) return pl.cursor_split(m, i) end} end
		local function xfer(kind, i, from_target)
			return {kind .. " " .. i .. (from_target and " (from target)" or ""), function(pl, m, t, ti)
				return pl.stack_transfers{source_inventory = from_target and ti or m, index = i,
					target = from_target and pl or t, transfer_type = defines.inventory_actions[kind]}
			end}
		end
		local function xfer_self(kind, i)
			return {kind .. " " .. i .. " (to self)", function(pl, m)
				return pl.stack_transfers{source_inventory = m, index = i, target = pl, transfer_type = defines.inventory_actions[kind]}
			end}
		end
		local clear = {"clear_cursor", function(pl) return pl.clear_cursor() end}
		local plate, copper = "iron-plate", "copper-plate"

		-- left click
		scenario("pick_up", {main = {{plate, 37}}}, {click(1)})
		scenario("put_down_empty", {main = {{plate, 37}}}, {click(1), click(3)})
		scenario("put_back_own_slot", {main = {{plate, 37}}}, {click(1), click(1)})
		scenario("merge_fits", {main = {{plate, 30}, {plate, 50}}}, {click(1), click(2)})
		scenario("merge_overflow", {main = {{plate, 80}, {plate, 50}}}, {click(1), click(2)})
		scenario("merge_into_full", {main = {{plate, 80}, {plate, 100}}}, {click(1), click(2)})
		scenario("swap", {main = {{plate, 10}, {copper, 20}}}, {click(1), click(2)})
		scenario("swap_then_clear", {main = {{plate, 10}, {copper, 20}}}, {click(1), click(2), clear})
		scenario("put_down_then_pick_again", {main = {{plate, 37}}}, {click(1), click(3), click(3)})
		-- right click
		scenario("half_odd", {main = {{plate, 37}}}, {rclick(1)})
		scenario("half_even", {main = {{plate, 36}}}, {rclick(1)})
		scenario("half_of_one", {main = {{plate, 1}}}, {rclick(1)})
		scenario("place_one_empty", {main = {{plate, 37}}}, {click(1), rclick(3)})
		scenario("place_one_twice", {main = {{plate, 37}}}, {click(1), rclick(3), rclick(3)})
		scenario("place_one_same", {main = {{plate, 37}, {plate, 5}}}, {click(1), rclick(2)})
		scenario("place_one_other_item", {main = {{plate, 37}, {copper, 5}}}, {click(1), rclick(2)})
		scenario("place_one_own_slot", {main = {{plate, 37}}}, {click(1), rclick(1)})
		scenario("half_then_left_other", {main = {{plate, 37}}}, {rclick(1), click(3)})
		scenario("half_then_left_own", {main = {{plate, 37}}}, {rclick(1), click(1)})
		scenario("half_then_right_own", {main = {{plate, 37}}}, {rclick(1), rclick(1)})
		scenario("right_on_stack_holding_same", {main = {{plate, 10}, {plate, 20}}}, {click(1), rclick(2)})
		-- Q
		scenario("clear_whole", {main = {{plate, 37}}}, {click(1), clear})
		scenario("clear_half", {main = {{plate, 37}}}, {rclick(1), clear})
		scenario("clear_after_put_one", {main = {{plate, 37}}}, {click(1), rclick(3), clear})
		scenario("clear_hand_slot_taken", {main = {{plate, 37}}}, {click(1),
			{"put copper in the hand slot", function(pl, m) return m[1].set_stack{name = copper, count = 5} end}, clear})
		-- Shift / Ctrl with a chest open
		local chest = "iron-chest"
		scenario("shift_left_to_chest", {main = {{plate, 37}, {plate, 30}}, open = true}, {xfer("stack_transfer", 1)}, chest)
		scenario("shift_right_to_chest", {main = {{plate, 37}, {plate, 30}}, open = true}, {xfer("stack_split", 1)}, chest)
		scenario("ctrl_left_to_chest", {main = {{plate, 37}, {plate, 30}, {copper, 5}}, open = true}, {xfer("inventory_transfer", 1)}, chest)
		scenario("ctrl_right_to_chest", {main = {{plate, 37}, {plate, 30}, {copper, 5}}, open = true}, {xfer("inventory_split", 1)}, chest)
		scenario("ctrl_left_empty_slot_to_chest", {main = {{plate, 37}, 0, {copper, 5}}, open = true}, {xfer("inventory_transfer", 2)}, chest)
		scenario("ctrl_right_empty_slot_to_chest", {main = {{plate, 37}, 0, {copper, 5}}, open = true}, {xfer("inventory_split", 2)}, chest)
		scenario("shift_left_empty_slot_to_chest", {main = {{plate, 37}, 0, {copper, 5}}, open = true}, {xfer("stack_transfer", 2)}, chest)
		scenario("shift_left_from_chest", {target = {{plate, 37}, {plate, 30}}, open = true}, {xfer("stack_transfer", 1, true)}, chest)
		scenario("shift_right_from_chest", {target = {{plate, 37}, {plate, 30}}, open = true}, {xfer("stack_split", 1, true)}, chest)
		scenario("ctrl_left_from_chest", {target = {{plate, 37}, {plate, 30}, {copper, 5}}, open = true}, {xfer("inventory_transfer", 1, true)}, chest)
		scenario("ctrl_right_from_chest", {target = {{plate, 37}, {plate, 30}, {copper, 5}}, open = true}, {xfer("inventory_split", 1, true)}, chest)
		scenario("ctrl_left_empty_from_chest", {target = {{plate, 37}, 0, {copper, 5}}, open = true}, {xfer("inventory_transfer", 2, true)}, chest)
		scenario("left_in_chest", {target = {{plate, 37}}, open = true}, {{"left chest 1", function(pl, m, t, ti) return pl.cursor_transfer(ti, 1) end}}, chest)
		scenario("chest_to_main_click", {target = {{plate, 37}}, open = true}, {{"left chest 1", function(pl, m, t, ti) return pl.cursor_transfer(ti, 1) end}, click(2)}, chest)
		scenario("chest_pick_then_clear", {target = {{plate, 37}}, open = true}, {{"left chest 1", function(pl, m, t, ti) return pl.cursor_transfer(ti, 1) end}, clear}, chest)
		-- Shift / Ctrl into machines (smart insertion)
		scenario("shift_ore_to_furnace", {main = {{"iron-ore", 80}, {"coal", 30}}, open = true}, {xfer("stack_transfer", 1), xfer("stack_transfer", 2)}, "stone-furnace")
		scenario("ctrl_coal_to_furnace", {main = {{"coal", 50}, {"coal", 50}}, open = true}, {xfer("inventory_transfer", 1)}, "stone-furnace")
		scenario("shift_plate_to_furnace", {main = {{plate, 80}}, open = true}, {xfer("stack_transfer", 1)}, "stone-furnace")
		scenario("shift_plate_to_gear_assembler", {main = {{plate, 100}, {plate, 100}}, recipe = "iron-gear-wheel", open = true},
			{xfer("stack_transfer", 1)}, "assembling-machine-1")
		scenario("ctrl_plate_to_gear_assembler", {main = {{plate, 100}, {plate, 100}}, recipe = "iron-gear-wheel", open = true},
			{xfer("inventory_transfer", 1)}, "assembling-machine-1")
		scenario("shift_copper_to_gear_assembler", {main = {{copper, 100}}, recipe = "iron-gear-wheel", open = true},
			{xfer("stack_transfer", 1)}, "assembling-machine-1")
		-- Shift without another window: the character's own inventories
		scenario("shift_gun_self", {main = {{"pistol", 1}, {"firearm-magazine", 10}}}, {xfer_self("stack_transfer", 1), xfer_self("stack_transfer", 2)})
		scenario("shift_plate_self", {main = {{plate, 37}}}, {xfer_self("stack_transfer", 1)})
		scenario("ctrl_plate_self", {main = {{plate, 37}}}, {xfer_self("inventory_transfer", 1)})
		-- pipette
		scenario("pipette_have", {main = {{plate, 5}, {"transport-belt", 30}, {"transport-belt", 100}}},
			{{"pipette transport-belt", function(pl) return pl.pipette(prototypes.entity["transport-belt"]) end}})
		scenario("pipette_none", {main = {{plate, 5}}},
			{{"pipette transport-belt", function(pl) return pl.pipette(prototypes.entity["transport-belt"], nil, true) end}})
		scenario("pipette_while_holding", {main = {{plate, 5}, {"transport-belt", 30}}},
			{click(1), {"pipette transport-belt", function(pl) return pl.pipette(prototypes.entity["transport-belt"]) end}})
		scenario("pipette_same_held", {main = {{"transport-belt", 30}}},
			{click(1), {"pipette transport-belt", function(pl) return pl.pipette(prototypes.entity["transport-belt"]) end}})

		-- put the character's things back
		main.clear()
		guns.clear()
		ammo.clear()
		p.clear_cursor()
		for i = 1, #main do main[i].transfer_stack(keep[i]) end
		for i = 1, #guns do guns[i].transfer_stack(keep_guns[i]) end
		for i = 1, #ammo do ammo[i].transfer_stack(keep_guns[#guns + i]) end
		keep.destroy()
		keep_guns.destroy()
		helpers.write_file("ui_reference/rules_inventory.json", helpers.table_to_json(results))
		return {rules = results}
	end, nil, true)
end

return M
