"""The mock's side of machine_info.lua: what Factorio's production windows show beyond inventories
(recipe details, burner fuel left, productivity, drill progress, lab packs, temperature, the recipe
chooser's groups, a logistic chest's request settings), and with --machine-gallery a row of every
machine whose window tools/ui_reference compares.
"""

# name, type, width, height (selection box), colour: merged into mock_server.ENTITY_PROTOS.
ENTITY_PROTOS = [
    ("steel-chest", "container", 1, 1, (150, 150, 160)),
    ("passive-provider-chest", "logistic-container", 1, 1, (200, 60, 60)),
    ("active-provider-chest", "logistic-container", 1, 1, (160, 60, 200)),
    ("buffer-chest", "logistic-container", 1, 1, (60, 180, 80)),
    ("assembling-machine-3", "assembling-machine", 3, 3, (110, 150, 90)),
    ("oil-refinery", "assembling-machine", 5, 5, (130, 100, 80)),
    ("chemical-plant", "assembling-machine", 3, 3, (110, 130, 120)),
    ("steel-furnace", "furnace", 2, 2, (150, 120, 100)),
    ("electric-furnace", "furnace", 3, 3, (150, 110, 100)),
    ("pumpjack", "mining-drill", 3, 3, (90, 130, 60)),
    ("nuclear-reactor", "reactor", 5, 5, (150, 150, 140)),
    ("heat-exchanger", "boiler", 3, 2, (150, 110, 90)),
    ("offshore-pump", "offshore-pump", 1, 2, (110, 130, 150)),
    ("accumulator", "accumulator", 2, 2, (120, 120, 130)),
    ("radar", "radar", 3, 3, (130, 130, 120)),
    ("beacon", "beacon", 3, 3, (130, 120, 130)),
    ("foundry", "assembling-machine", 5, 5, (140, 90, 70)),
    ("electromagnetic-plant", "assembling-machine", 4, 4, (110, 110, 140)),
    ("cryogenic-plant", "assembling-machine", 5, 5, (120, 150, 170)),
    ("biochamber", "assembling-machine", 3, 3, (130, 110, 90)),
    ("recycler", "furnace", 2, 4, (120, 120, 110)),
    ("biolab", "lab", 5, 5, (150, 110, 130)),
    ("big-mining-drill", "mining-drill", 5, 5, (130, 90, 80)),
    ("captive-biter-spawner", "assembling-machine", 5, 5, (150, 100, 90)),
    ("fusion-reactor", "fusion-reactor", 6, 6, (110, 120, 140)),
    ("fusion-generator", "fusion-generator", 3, 5, (110, 120, 140)),
]

# Recipes the gallery's machines make, in mock_server.MACHINE_RECIPES' shape, plus the fluids that
# rd lists ([type, name, amount]) for recipes with fluids.
RECIPES = {
    "engine-unit": ({"steel-plate": 1, "iron-gear-wheel": 1, "pipe": 2}, ("engine-unit", 1)),
    "tungsten-plate": ({"tungsten-ore": 4}, ("tungsten-plate", 1)),
    "biter-egg": ({}, ("biter-egg", 5)),
}
FLUID_RECIPES = {
    "advanced-oil-processing": ([["fluid", "water", 50], ["fluid", "crude-oil", 100]],
                                [["fluid", "heavy-oil", 25], ["fluid", "light-oil", 45], ["fluid", "petroleum-gas", 55]]),
    "lubricant": ([["fluid", "heavy-oil", 10]], [["fluid", "lubricant", 10]]),
    "tungsten-plate": ([["item", "tungsten-ore", 4], ["fluid", "sulfuric-acid", 10]], [["item", "tungsten-plate", 1]]),
}
# Item groups of the recipe chooser: recipe -> [group, group order, subgroup key, order].
GROUPS = {
    "iron-gear-wheel": ["intermediate-products", "c", "b intermediate-product", "c[iron-gear-wheel]"],
    "copper-cable": ["intermediate-products", "c", "b intermediate-product", "a[copper-cable]"],
    "electronic-circuit": ["intermediate-products", "c", "b intermediate-product", "e[electronic-circuit]"],
    "engine-unit": ["intermediate-products", "c", "b intermediate-product", "h[engine-unit]"],
    "automation-science-pack": ["intermediate-products", "c", "y science-pack", "a[automation-science-pack]"],
    "inserter": ["logistics", "a", "c inserter", "b[inserter]"],
    "transport-belt": ["logistics", "a", "b belt", "a[transport-belt]"],
    "wooden-chest": ["logistics", "a", "a storage", "a[wooden-chest]"],
    "iron-chest": ["logistics", "a", "a storage", "b[iron-chest]"],
    "stone-furnace": ["production", "b", "c smelting-machine", "a[stone-furnace]"],
    "burner-mining-drill": ["production", "b", "b extraction-machine", "a[burner-mining-drill]"],
}
# Logistic groups the mock's force has (Factorio's are per force; LuaForce.get_logistic_groups).
GROUPS_MADE = {"Science", "Mall"}
LOGISTIC_MODES = {"passive-provider-chest": "passive-provider", "active-provider-chest": "active-provider",
                  "buffer-chest": "buffer"}
LAB_INPUTS = ["automation-science-pack", "logistic-science-pack", "military-science-pack", "chemical-science-pack",
              "production-science-pack", "utility-science-pack", "space-science-pack"]
BIOLAB_INPUTS = LAB_INPUTS + ["metallurgic-science-pack", "agricultural-science-pack", "electromagnetic-science-pack",
                              "cryogenic-science-pack", "promethium-science-pack"]

# The gallery: name, x, y and the machine's made-up insides (merged into mock_server.machine's).
GALLERY = [
    ("iron-chest", -40.5, 30.5, {"inv": {"chest": {"iron-plate": 100}}}),
    ("steel-chest", -38.5, 30.5, {"inv": {"chest": {"steel-plate": 50, "iron-gear-wheel": 30}}}),
    ("passive-provider-chest", -36.5, 30.5, {"inv": {"chest": {"copper-cable": 200}}}),
    ("active-provider-chest", -34.5, 30.5, {"inv": {"chest": {}}}),
    ("buffer-chest", -32.5, 30.5, {"inv": {"chest": {}, "trash": {}}}),
    ("assembling-machine-2", -40.5, 35.5, {"recipe": "electronic-circuit", "status": "item_ingredient_shortage",
                                           "inv": {"input": {"iron-plate": 5}, "output": {"electronic-circuit": 24},
                                                   "modules": {}}}),
    ("assembling-machine-3", -36.5, 35.5, {"recipe": "engine-unit", "status": "item_ingredient_shortage",
                                           "inv": {"input": {}, "output": {}, "modules": {}}, "mods": 4}),
    ("oil-refinery", -30.5, 35.5, {"recipe": "advanced-oil-processing", "status": "full_output", "progress": 60,
                                   "inv": {"input": {}, "output": {}, "modules": {}}, "mods": 3,
                                   "fb": [["water", 200, 1000, 15], ["crude-oil", 400, 1000, 15], ["heavy-oil", 0, 1000, 15],
                                          ["light-oil", 0, 1000, 15], ["petroleum-gas", 0, 1000, 15]]}),
    ("chemical-plant", -25.5, 35.5, {"recipe": "lubricant", "inv": {"input": {}, "output": {}, "modules": {}}, "mods": 3,
                                     "fb": [["heavy-oil", 195, 1000, 15], ["lubricant", 0, 1000, 15]]}),
    ("steel-furnace", -40.5, 40.5, {"recipe": "iron-plate", "inv": {"input": {"iron-ore": 29}, "output": {},
                                                                   "fuel": {"coal": 19}}, "bn": 990}),
    ("electric-furnace", -37.5, 40.5, {"recipe": "copper-plate", "inv": {"input": {"copper-ore": 10},
                                                                        "output": {"copper-plate": 3}, "modules": {}}}),
    ("burner-mining-drill", -34.5, 40.5, {"status": "no_minable_resources", "inv": {"fuel": {"coal": 9}}, "bn": 1000,
                                          "drill": {}}),
    ("electric-mining-drill", -31.5, 40.5, {"status": "working", "inv": {"modules": {}}, "mods": 3,
                                            "drill": {"mp": 450, "mt": "iron-ore"}, "pb": 300, "bp": 600}),
    ("pumpjack", -27.5, 40.5, {"status": "waiting_for_space_in_destination", "inv": {"modules": {}}, "mods": 2,
                               "drill": {"mp": 0, "mt": "crude-oil", "mr": 430}, "pb": 300, "bp": 750,
                               "fb": [["crude-oil", 100, 100, 15]]}),
    ("nuclear-reactor", -40.5, 47.5, {"status": "working", "inv": {"fuel": {"uranium-fuel-cell": 1}, "burnt": {}},
                                      "bn": 400, "temp": 67215, "tmax": 1000}),
    ("heat-exchanger", -35.0, 47.0, {"status": "working", "temp": 50010, "tmax": 1000,
                                     "fb": [["water", 200, 200, 15], ["steam", 150, 200, 500]]}),
    ("offshore-pump", -31.5, 47.0, {"status": "working", "fb": [["water", 100, 100, 15]]}),
    ("accumulator", -29.0, 47.0, {"status": "fully_charged", "pw": 1000}),
    ("radar", -25.5, 47.5, {"status": "working", "pw": 1000}),
    ("beacon", -21.5, 47.5, {"status": "no_modules_to_transmit", "inv": {"modules": {}}, "mods": 2}),
    ("lab", -17.5, 47.5, {"status": "working", "inv": {"input": {"automation-science-pack": 3, "logistic-science-pack": 3},
                                                       "modules": {}}, "mods": 2}),
    ("foundry", -40.5, 55.5, {"recipe": "tungsten-plate", "status": "full_output", "inv": {"input": {"tungsten-ore": 40},
                              "output": {"tungsten-plate": 6}, "modules": {}}, "mods": 4, "pb": 500, "bp": 200,
                              "fb": [["sulfuric-acid", 0, 1000, 15]]}),
    ("electromagnetic-plant", -34.5, 55.5, {"status": "no_recipe", "inv": {"input": {}, "output": {}, "modules": {}}, "mods": 5}),
    ("cryogenic-plant", -28.5, 55.5, {"status": "no_recipe", "inv": {"input": {}, "output": {}, "modules": {}}, "mods": 8}),
    ("biochamber", -23.5, 55.5, {"status": "no_recipe", "inv": {"input": {}, "output": {}, "modules": {}, "fuel": {}}, "mods": 4,
                                 "bn": 0}),
    ("recycler", -19.5, 55.5, {"status": "no_ingredients", "inv": {"input": {}, "output": {}, "modules": {}}, "mods": 4,
                               "out_slots": 12}),
    ("crusher", -16.5, 55.5, {"status": "no_recipe", "inv": {"input": {}, "output": {}, "modules": {}}, "mods": 2}),
    ("biolab", -40.5, 63.5, {"status": "no_research_in_progress", "inv": {"input": {}, "modules": {}}, "mods": 4,
                             "lab_slots": len(BIOLAB_INPUTS)}),
    ("big-mining-drill", -34.5, 63.5, {"status": "working", "inv": {"modules": {}}, "mods": 4,
                                       "drill": {"mp": 900, "mt": "tungsten-ore"}, "pb": 400, "bp": 250}),
    ("heating-tower", -28.5, 63.5, {"status": "no_fuel", "inv": {"fuel": {}, "burnt": {}}, "fuel_slots": 2, "burnt_slots": 2,
                                    "bn": 0, "temp": 1500, "tmax": 1000}),
    ("captive-biter-spawner", -22.5, 63.5, {"recipe": "biter-egg", "status": "no_fuel",
                                            "inv": {"input": {}, "output": {}, "fuel": {}}, "bn": 0, "fixed_recipe": True}),
    ("fusion-reactor", -15.5, 63.5, {"status": "no_fuel", "inv": {"fuel": {}}, "bn": 0,
                                     "fb": [["fluoroketone-cold", 0, 1000, -150], ["fusion-plasma", 0, 1000, 1000000]]}),
    ("fusion-generator", -9.5, 63.5, {"status": "no_input_fluid",
                                      "fb": [["fusion-plasma", 0, 1000, 1000000], ["fluoroketone-hot", 0, 1000, 180]]}),
    ("agricultural-tower", -4.5, 63.5, {"status": "no_ingredients", "inv": {"input": {}, "output": {}}}),
]
# Slot counts the gallery's inventories have (beyond mock_server.SLOT_SIZES).
ROLE_SLOTS = {"modules": "mods", "output": "out_slots", "fuel": "fuel_slots", "burnt": "burnt_slots"}


def build_gallery(game, entity_class):
    """Places the gallery and gives each machine its insides; returns their units."""
    units = []
    for name, x, y, insides in GALLERY:
        e = entity_class(game._unit(), name, x, y, 0)
        game.add(e)
        m = {"recipe": None, "progress": 0, "inv": {}}
        m.update({k: (v if not isinstance(v, dict) else {r: dict(c) if isinstance(c, dict) else c for r, c in v.items()})
                  for k, v in insides.items()})
        m["gallery"] = True
        if e.type == "container" or e.type == "logistic-container":
            m["bar"] = 48 if name == "steel-chest" else 32 if name == "iron-chest" else 48
        if name in LOGISTIC_MODES:
            mode = LOGISTIC_MODES[name]
            m["lg"] = {"mode": mode}
            if mode == "buffer":
                m["sec"] = [{"i": 1, "g": "", "on": 1, "m": 1, "man": 1, "f": [["firearm-magazine", "", 100, -1, "", -1]]}]
                m["tu"] = 0
        if "fb" in m:
            game.fluids[e.unit] = [tuple(b) for b in m.pop("fb")]
        game.machines[e.unit] = m
        units.append(e.unit)
    return units


def slot_count(m, role, default, entity_type=""):
    key = ROLE_SLOTS.get(role)
    if key and key in m:
        return m[key]
    if entity_type == "lab" and role == "input":
        return m.get("lab_slots", len(LAB_INPUTS))  # one slot per science pack the lab takes
    if entity_type == "furnace" and role in ("input", "output"):
        return 1  # a furnace has one source and one result slot
    if role in ("chest",) and "bar" in m:
        return m["bar"]
    return default


def recipe_details(name, machine_recipes):
    if name in FLUID_RECIPES:
        i, o = FLUID_RECIPES[name]
        return {"i": i, "o": o, "e": 5}
    if name in machine_recipes:
        needs, (product, count) = machine_recipes[name]
        return {"i": [["item", k, v] for k, v in needs.items()], "o": [["item", product, count]], "e": 0.5}
    return None


def fill(msg, entity, m, kind, machine_recipes, smelting, with_lists):
    """machine_info.lua's fields for the open machine."""
    if "status" in m:
        msg["status"] = m["status"]
    if kind == "container":
        msg.pop("status", None)  # chests have no status: Factorio says "Normal"
    if kind in ("crafter", "furnace"):
        name = m.get("recipe")
        if kind == "furnace" and not name:
            name = next((smelting[k] for k in m["inv"].get("input", {}) if k in smelting), None)
        if kind == "furnace" and name in smelting.values():
            ore = next(k for k, v in smelting.items() if v == name)
            msg["rd"] = {"i": [["item", ore, 1]], "o": [["item", name, 1]], "e": 3.2}
        elif name:
            rd = recipe_details(name, machine_recipes)
            if rd:
                msg["rd"] = rd
        if m.get("fixed_recipe"):
            msg["fixed"] = 1
    if kind == "silo":  # rocket parts, crafted like an assembler's recipe
        msg["recipe"] = "rocket-part"
        msg["rd"] = {"i": [["item", "processing-unit", 1], ["item", "low-density-structure", 1], ["item", "rocket-fuel", 1]],
                     "o": [["item", "rocket-part", 1]], "e": 3}
        msg["pr"] = (entity.unit * 37 + m.get("parts", 0) * 100) % 1000
    for k in ("pb", "bp", "bn"):
        if k in m:
            msg[k] = m[k]
    if "fuel" in m["inv"] and "bn" not in m:
        msg["bn"] = 700 if any(m["inv"]["fuel"].values()) else 0
    drill = m.get("drill")
    if isinstance(drill, dict):
        msg.update(drill)
    if "temp" in m:
        msg["tc"] = m["temp"]
        msg["temp"] = m["temp"] // 100
        msg["tmax"] = m.get("tmax", 1000)
    if "pw" in m:
        msg["pw"] = m["pw"]
    if kind == "lab" and m["inv"].get("input"):  # partly used packs: Factorio's orange pie
        msg["ld"] = [[i + 1, 900 - 230 * i] for i in range(min(3, len(m["inv"]["input"])))]
    if kind == "lab" and with_lists:
        msg["li"] = BIOLAB_INPUTS if entity.name == "biolab" else LAB_INPUTS
    if with_lists and "rl" in msg:
        msg["rg"] = [GROUPS.get(r, ["intermediate-products", "c", "b intermediate-product", r]) for r in msg["rl"]]
    if with_lists and ("sec" in m or kind in ("hub", "pad")):
        names = set(GROUPS_MADE)
        for sec in m.get("sec", []):
            if sec.get("g"):
                names.add(sec["g"])
        msg["lgs"] = sorted(names)
    if kind == "silo":
        m.setdefault("sec", [])
        weights = {"space-platform-starter-pack": 1000000}
        rocket = m["inv"].get("rocket", {})
        msg["rw"] = [sum(weights.get(k, 10000) * v for k, v in rocket.items()), 1000000]
    if "sec" in m:
        msg["lc"] = {"tu": m.get("tu", 0), "sec": m["sec"]}
        if m.get("lg", {}).get("mode") == "requester":
            msg["lc"]["rb"] = m.get("rb", 0)


def command(game, t, msg):
    """set_chest_logistics and set_section on a logistic chest; True if it was handled here."""
    sc = game.screen
    entity = game.entities.get(sc["unit"]) if sc else None
    if t not in ("set_chest_logistics", "set_section") or entity is None or int(msg.get("u", 0)) != sc["unit"]:
        return False
    m = game.machine(entity)
    if m is not None and entity.type == "rocket-silo":
        m.setdefault("sec", [])
    with_requests = ("logistic-container", "rocket-silo") if t == "set_section" else ("logistic-container", "rocket-silo",
                                                                                         "cargo-landing-pad")
    if m is None or "sec" not in m or entity.type not in with_requests:
        if t == "set_chest_logistics":
            game.message("That chest has no requests")
            return True
        return False
    sc["due"] = game.tick
    if t == "set_chest_logistics":
        for k in ("tu", "rb"):
            if msg.get(k) in (0, 1):
                m[k] = msg[k]
        return True
    i = int(msg.get("i", 0))
    if msg.get("del") == 1:
        if 1 <= i <= len(m["sec"]):
            m["sec"].pop(i - 1)
    else:
        if i == 0:
            m["sec"].append({"i": 0, "g": str(msg.get("g", "")), "on": 1, "m": 1, "man": 1, "f": []})
            i = len(m["sec"])
        if 1 <= i <= len(m["sec"]):
            sec = m["sec"][i - 1]
            if isinstance(msg.get("f"), list):
                sec["f"] = [[str(f[0]), str(f[1] or ""), int(f[2]), int(f[3]), str(f[4]), int(f[5])]
                            for f in msg["f"] if isinstance(f, list) and len(f) == 6]
            if isinstance(msg.get("g"), str) and int(msg.get("i", 0)):
                sec["g"] = msg["g"]
                if msg["g"]:
                    GROUPS_MADE.add(msg["g"])
            if msg.get("on") in (0, 1):
                sec["on"] = msg["on"]
            if isinstance(msg.get("m"), (int, float)):
                sec["m"] = msg["m"]
    for k, sec in enumerate(m["sec"]):
        sec["i"] = k + 1
    return True
