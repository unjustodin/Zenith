#!/usr/bin/env python3
"""A stand-in for Factorio + the bridge mod, so the 3D client can be developed without the game.

    python3 tools/mock_server.py                 # listen on 127.0.0.1:34200
    python3 tools/mock_server.py --drop 0.05     # lose 5% of packets, to exercise resyncs

It speaks the same protocol as the mod (docs/PROTOCOL.md) over a generated world: grass,
lakes, forests, ore patches, a small starter factory, a rail line with a train, a car, robots
and wandering biters, and a few items lying on the ground next to the start. The inventory
is kept slot by slot, with a quickbar, recipe details, a crafting queue and a small research
tree. The character walks, mines, builds, rotates, crafts, picks items up (F), shoots (biters
bite back, die and respawn at their nest) and drives the car parked south-west of the start
(Enter, WASD), loosely. Chests, assemblers, furnaces and the lab open as machine screens with
made-up contents that recipes, take and put change. `--start X,Y` puts the character somewhere
else (in tiles; the default is -3,0.5), for example next to the chest (4,9) or an assembler (5,-1).
A space platform orbits the planet: plat_board goes up to it and back, plat_go sends it on a
30-second trip, and `--platform` starts on it. `ride` (the silo screen's Ride button) flies the
character up to its hub on the 2.1.23 timeline, shortened, and `land` brings it down by cargo pod
(see RIDE_UP and RIDE_DOWN).
Python 3.9+, standard library only.
"""

import argparse
import base64
import contextlib
import copy
import json
import math
import os
import random
import socket
import time
import zlib

import mock_space
import mock_machines
import mock_vehicles
import mock_turrets
import mock_vehicle_showcase
import mock_creature_showcase
import mock_enemy_showcase
import mock_logistics
import mock_shots

import mock_info

PROTOCOL = 1
TICKS_PER_SECOND = 60
CHUNK = 32
BYTES_PER_TICK = 32768
CHUNKS_PER_TICK = 2
MAX_BACKLOG = 64
ENTITIES_PER_MESSAGE = 120
DECORATIVES_PER_MESSAGE = 1000  # 4 numbers each, as the mod
RECORDS_PER_MESSAGE = 80
MOVERS_PER_MESSAGE = 200
MAX_EXTRA_CLIENTS = 7
# What each client has of its own (MockGame.serving swaps these); the rest is the shared world.
PER_CLIENT = ("client", "rseq", "outbox", "subs", "queue", "focus", "player", "guns_sig", "inv_sig", "layout",
              "slots_sig", "craftable_sig", "quickbar", "queue_sent", "screen", "char_logistics", "char_color", "map_queue",
              "map_res", "tags_dirty", "map_si", "alt", "filters", "clipboard", "remote_view", "work_budget")
EQUIPMENT_SHAPES = {"solar-panel-equipment": (1, 1), "battery-equipment": (1, 2), "energy-shield-equipment": (2, 2),
                    "personal-roboport-equipment": (2, 2)}
ITEMS_PER_MESSAGE = 300
WORK_BUDGET, WORK_BUDGET_FLOOR, WORK_BUDGET_CEILING = 300, 50, 20000  # as budget.lua
BELT_ITEM_INTERVAL = 6
BELT_ITEM_RADIUS = 24
GROUND_ITEM_INTERVAL = 30
# The mod's rate.lua for the jobs the mock has: the level a job first slows down at, its longest
# period and the tick it runs on while stretched (the client's `rate` command, 0-3). After a
# slow-down movers and belt items also keep their old ticks for RATE_EASE_TICKS, as the mod's do.
RATE_JOBS = {"mv": (1, 16, 1), "bi": (1, 48, 1), "ih": (3, 24, 3)}
RATE_EASE = {"mv", "bi"}
RATE_EASE_TICKS = 120
PICKUP_DISTANCE = 1.5  # the character's item_pickup_distance plus the mod's slack
PICKUPS_PER_TICK = 2
BELT_SPEED = 0.03125  # tiles per tick, a yellow belt
SWING_TICKS = 80  # one inserter round trip
SKY_INTERVAL = 60
# Entity types the mod reports working states for (registry.lua ANIMATED_TYPES).
ANIMATED_TYPES = ("assembling-machine", "furnace", "mining-drill", "lab", "boiler", "generator", "reactor",
                  "radar", "rocket-silo", "pump", "offshore-pump", "beacon", "burner-generator", "fusion-reactor",
                  "fusion-generator", "agricultural-tower", "asteroid-collector", "lamp", "thruster")
TIMEOUT_TICKS = 600
HOLD_TICKS = 30
BATCH_BYTES = 60000  # a datagram of messages joined by newlines, for a client whose hello says b
WALK_SPEED = 0.15  # tiles per tick, like the Factorio character
# Combat, roughly a pistol with firearm magazines against small and medium biters.
GUN_RANGE = 15.0
SHOT_TICKS = 15
SHOT_DAMAGE = 5
ROUNDS_PER_MAGAZINE = 10
FIRING_TICKS = 20
BITER_HEALTH = {"small-biter": 15, "medium-biter": 75}
BITE_RANGE = 1.5
BITE_DAMAGE = 0.2  # per tick
CHARACTER_HEALTH = 250
RESPAWN_TICKS = 600
HEALTH_INTERVAL = 10
GUNS_INTERVAL = 10
# The drivable car, roughly Factorio's: tiles per tick, and turns per tick at speed.
ENTER_DISTANCE = 5.0
CAR_ACCELERATION = 0.003
CAR_MAX_SPEED = 0.5
CAR_REVERSE_SPEED = 0.15
CAR_BRAKE = 0.01
CAR_FRICTION = 0.99
CAR_TURN = 0.006

# name, type, width, height (selection box), color, tile width, tile height
ENTITY_PROTOS = [
    ("character", "character", 0.4, 0.4, (255, 165, 0)),
    ("transport-belt", "transport-belt", 1, 1, (250, 200, 40)),
    ("fast-transport-belt", "transport-belt", 1, 1, (220, 70, 50)),
    ("entity-ghost", "entity-ghost", 1, 1, (120, 160, 220)),
    ("underground-belt", "underground-belt", 1, 1, (250, 200, 40)),
    ("splitter", "splitter", 2, 1, (250, 200, 40)),
    ("burner-inserter", "inserter", 1, 1, (120, 100, 60)),
    ("inserter", "inserter", 1, 1, (200, 180, 60)),
    ("wooden-chest", "container", 1, 1, (150, 110, 60)),
    ("iron-chest", "container", 1, 1, (140, 140, 150)),
    ("stone-furnace", "furnace", 2, 2, (170, 150, 120)),
    ("burner-mining-drill", "mining-drill", 2, 2, (120, 100, 80)),
    ("electric-mining-drill", "mining-drill", 3, 3, (90, 110, 140)),
    ("assembling-machine-1", "assembling-machine", 3, 3, (150, 160, 120)),
    ("assembling-machine-2", "assembling-machine", 3, 3, (110, 140, 170)),
    ("small-electric-pole", "electric-pole", 1, 1, (120, 90, 60)),
    ("small-lamp", "lamp", 1, 1, (230, 225, 160)),
    ("constant-combinator", "constant-combinator", 1, 1, (130, 130, 120)),
    ("arithmetic-combinator", "arithmetic-combinator", 1, 2, (130, 130, 120)),
    ("pipe", "pipe", 1, 1, (110, 130, 150)),
    ("lab", "lab", 3, 3, (200, 200, 255)),
    ("boiler", "boiler", 3, 2, (160, 100, 80)),
    ("steam-engine", "generator", 3, 5, (140, 140, 140)),
    ("stone-wall", "wall", 1, 1, (200, 200, 190)),
    ("gun-turret", "ammo-turret", 2, 2, (200, 120, 60)),
    ("tree-01", "tree", 1, 1, (40, 110, 40)),
    ("tree-02", "tree", 1, 1, (60, 130, 50)),
    ("dead-tree-desert", "tree", 1, 1, (120, 100, 70)),
    ("big-rock", "simple-entity", 2, 2, (130, 120, 110)),
    ("huge-rock", "simple-entity", 3, 3, (120, 110, 100)),
    ("cliff", "cliff", 3, 3, (144, 119, 87)),
    ("iron-ore", "resource", 1, 1, (105, 130, 150)),
    ("copper-ore", "resource", 1, 1, (205, 100, 60)),
    ("coal", "resource", 1, 1, (30, 30, 30)),
    ("stone", "resource", 1, 1, (175, 145, 100)),
    ("straight-rail", "straight-rail", 2, 2, (130, 120, 110)),
    ("small-biter", "unit", 0.6, 0.6, (180, 60, 60)),
    ("medium-biter", "unit", 0.9, 0.9, (170, 50, 70)),
    ("biter-spawner", "unit-spawner", 5, 5, (150, 40, 60)),
    ("car", "car", 1.4, 2, (200, 80, 40)),
    ("locomotive", "locomotive", 2, 6, (200, 50, 50)),
    ("cargo-wagon", "cargo-wagon", 2, 6, (150, 120, 80)),
    ("train-stop", "train-stop", 2, 2, (180, 40, 40)),
    ("heat-pipe", "heat-pipe", 1, 1, (150, 80, 60)),
    ("small-demolisher", "segmented-unit", 6, 6, (90, 60, 50)),
    ("big-volcanic-rock", "simple-entity", 3, 3, (70, 60, 55)),
    ("lightning-rod", "lightning-attractor", 1, 1, (140, 140, 150)),
    ("fulgoran-ruin-small", "simple-entity", 2, 2, (120, 100, 90)),
    ("yumako-tree", "plant", 2, 2, (150, 60, 80)),
    ("agricultural-tower", "agricultural-tower", 3, 3, (110, 120, 90)),
    ("small-stomper-pentapod", "spider-unit", 2, 2, (160, 120, 60)),
    ("gleba-spawner", "unit-spawner", 5, 5, (130, 110, 70)),
    ("heating-tower", "reactor", 3, 3, (160, 90, 70)),
    ("cargo-pod", "cargo-pod", 2, 2, (180, 180, 190)),
    ("logistic-robot", "logistic-robot", 0.5, 0.5, (230, 200, 90)),
    ("requester-chest", "logistic-container", 1, 1, (60, 120, 200)),
    ("storage-chest", "logistic-container", 1, 1, (210, 180, 60)),
    ("roboport", "roboport", 4, 4, (150, 150, 120)),
    ("space-platform-hub", "space-platform-hub", 8, 8, (127, 127, 127)),
    ("asteroid-collector", "asteroid-collector", 3, 3, (110, 110, 120)),
    ("thruster", "thruster", 4, 5, (120, 110, 100)),
    ("crusher", "assembling-machine", 2, 3, (115, 115, 110)),
    ("cargo-bay", "cargo-bay", 4, 4, (125, 125, 125)),
    ("medium-metallic-asteroid", "asteroid", 2, 2, (110, 90, 80)),
    ("small-carbonic-asteroid", "asteroid", 1, 1, (60, 60, 60)),
    ("decider-combinator", "decider-combinator", 1, 2, (130, 130, 120)),
    ("selector-combinator", "selector-combinator", 1, 2, (130, 130, 120)),
    ("programmable-speaker", "programmable-speaker", 1, 1, (120, 120, 110)),
    ("display-panel", "display-panel", 1, 1, (90, 90, 90)),
    ("pump", "pump", 1, 2, (110, 130, 150)),
    ("power-switch", "power-switch", 2, 2, (120, 110, 90)),
    # Tiles, the rail planner, drag building and capsules (tiles.lua, rail_planner.lua, capsules.lua).
    ("tile-ghost", "tile-ghost", 1, 1, (120, 160, 220)),
    ("half-diagonal-rail", "half-diagonal-rail", 2, 2, (130, 120, 110)),
    ("curved-rail-a", "curved-rail-a", 2, 2, (130, 120, 110)),
    ("curved-rail-b", "curved-rail-b", 2, 2, (130, 120, 110)),
    ("elevated-straight-rail", "elevated-straight-rail", 2, 2, (130, 120, 110)),
    ("elevated-half-diagonal-rail", "elevated-half-diagonal-rail", 2, 2, (130, 120, 110)),
    ("elevated-curved-rail-a", "elevated-curved-rail-a", 2, 2, (130, 120, 110)),
    ("elevated-curved-rail-b", "elevated-curved-rail-b", 2, 2, (130, 120, 110)),
    ("rail-ramp", "rail-ramp", 4, 16, (130, 120, 110)),
    ("rail-support", "rail-support", 2, 2, (120, 120, 120)),
    ("pipe-to-ground", "pipe-to-ground", 1, 1, (110, 130, 150)),
    ("land-mine", "land-mine", 1, 1, (90, 90, 70)),
    *mock_space.ENTITY_PROTOS,
    *mock_machines.ENTITY_PROTOS,
    *mock_vehicles.ENTITY_PROTOS,
    *mock_turrets.ENTITY_PROTOS,
    *mock_vehicle_showcase.ENTITY_PROTOS,
    *mock_creature_showcase.ENTITY_PROTOS,
    *mock_enemy_showcase.ENTITY_PROTOS,
    *mock_logistics.ENTITY_PROTOS,
    # Remnants (corpses buildings leave; extra.rm names what left them, 0 when shared).
    ("assembling-machine-1-remnants", "corpse", 3, 3, (100, 90, 80)),
    ("gun-turret-remnants", "corpse", 2, 2, (100, 90, 80)),
    ("small-remnants", "corpse", 1, 1, (100, 90, 80)),
]
FLUID_PROTOS = [("water", (0, 87, 153)), ("steam", (128, 128, 128)), ("crude-oil", (25, 25, 25))]
FLUID_INTERVAL = 60
TILE_PROTOS = [
    ("grass-1", (60, 90, 30)), ("grass-2", (70, 95, 35)), ("dirt-1", (110, 85, 50)),
    ("sand-1", (190, 160, 100)), ("water", (50, 80, 120)), ("deepwater", (35, 60, 100)),
    ("stone-path", (110, 105, 95)), ("concrete", (120, 120, 120)),
    ("space-platform-foundation", (56, 56, 60)), ("empty-space", (0, 0, 0)),
    ("volcanic-ash-flats", (70, 55, 50)), ("lava", (200, 70, 20)), ("lava-hot", (240, 120, 30)),
    ("fulgoran-rock", (110, 80, 70)), ("oil-ocean-shallow", (30, 25, 30)),
    ("wetland-yumako", (110, 60, 90)), ("lowland-olive-blubber", (100, 110, 60)),
    ("snow-flat", (220, 225, 235)), ("ice-smooth", (170, 200, 220)), ("ammoniacal-ocean", (40, 70, 80)),
    ("hazard-concrete-left", (130, 120, 70)), ("hazard-concrete-right", (130, 120, 70)), ("landfill", (95, 85, 60)),
]
# Items laid as tiles (`iuse` "t"): item -> (tile, other direction's tile, may go on water).
TILE_ITEMS = {"stone-brick": ("stone-path", "", False), "concrete": ("concrete", "", False),
              "hazard-concrete": ("hazard-concrete-left", "hazard-concrete-right", False),
              "landfill": ("landfill", "", True)}
WATER_TILES = {"water", "deepwater", "oil-ocean-shallow", "ammoniacal-ocean"}
# Capsules (`iuse` "c"): item -> (action type, range, radius), as Factorio 2.1.23 has them.
CAPSULES = {"grenade": ("throw", 15, 6.5), "cliff-explosives": ("destroy-cliffs", 10, 1.5), "raw-fish": ("use-on-self", 0, 0)}
CAPSULES.update({name: ("throw", 25 if "capsule" in name else 20, 0) for name in mock_shots.CAPSULES if name not in CAPSULES})
# Rails each rail planner piece costs.
RAIL_COST = {"straight-rail": 1, "half-diagonal-rail": 2, "curved-rail-a": 3, "curved-rail-b": 3}
# The mock's space platform: where it can go, how long a trip takes, its deck (rectangles of
# foundation in tiles, x1, y1, x2, y2) and what stands on it.
PLATFORM_SURFACE = "platform-1"
PLATFORM_DESTINATIONS = ["aquilo", "fulgora", "gleba", "nauvis", "vulcanus"]
PLATFORM_TRIP_TICKS = 30 * 60
PLATFORM_TRIP_KM = 15000
PLATFORM_DECK = [(-14, -12, 14, 16), (-21, -4, 21, 4)]
# Bays touch the hub, as Factorio requires: one in line with it, one half past its corner, one
# down its west side, so the cargo area's frame (the client's CARGO_PIECES) has joins to show.
PLATFORM_BUILDINGS = [("space-platform-hub", 0.0, 0.0, 0), ("cargo-bay", 0.0, -6.0, 0), ("cargo-bay", 4.0, -6.0, 0),
                      ("cargo-bay", -6.0, 2.0, 0),
                      ("asteroid-collector", -18.5, 0.5, 12), ("asteroid-collector", 18.5, 0.5, 4),
                      ("asteroid-collector", -6.5, -10.5, 0), ("asteroid-collector", 6.5, -10.5, 0),
                      ("crusher", -9.0, 4.5, 0), ("crusher", 9.0, 4.5, 0),
                      ("thruster", -5.0, 13.5, 0), ("thruster", 5.0, 13.5, 0)]
PLATFORM_START = (2.5, 6.5)
# Riding to the platform and back, as 2.1.23 does it but quicker: [(pod state, ticks), ...]. The
# pod's position runs north of its ground point by its height (Factorio's drawing), and `me` carries
# pod, ps, up, gx, gy meanwhile, then hub inside the hub. Measured in 2.1.23: up 450 / 1200 / 25 /
# 350 / 80 ticks, down 85 / 400 / 25 / 600.
RIDE_UP = [("awaiting_launch", 120), ("ascending", 300), ("surface_transition", 10), ("descending", 150), ("parking", 50)]
RIDE_DOWN = [("awaiting_launch", 60), ("ascending", 180), ("surface_transition", 10), ("descending", 240)]
RIDE_CLIMB = 200.0     # tiles a rocket climbs before it changes surface
POD_CLIMB = 26.0       # off a hub
POD_DROP = 230.0       # onto a planet
HUB_DROP = 40.0        # onto a hub
HUB_HATCH = (0.5, -3.5)
# What the world keeps per surface; switch_surface swaps it.
SURFACE_STATE = ("entities", "by_chunk", "generated", "tile_overrides", "working", "movers", "belt", "inserters",
                 "fluids", "heat", "ground", "belt_lanes", "frozen", "belt_field")
# The other planets (`--planet`, or `land` from the platform when it is stopped at one): a small
# surface each, with its tiles, a few of its buildings and its data. Surface properties and day
# lengths are close to Space Age's (day in ticks); mb and sol are min brightness and solar power
# in thousandths, as the mod sends them.
PLANETS = {
    "nauvis": {"props": {"gravity": 10, "pressure": 1000, "magnetic-field": 90, "solar-power": 100, "day-night-cycle": 25000},
               "day": 25000, "mb": 150, "sol": 1000},
    "vulcanus": {"props": {"gravity": 40, "pressure": 4000, "magnetic-field": 25, "solar-power": 400, "day-night-cycle": 5400},
                 "day": 5400, "mb": 200, "sol": 4000, "tiles": ("volcanic-ash-flats", "lava", "lava-hot"),
                 "buildings": [("big-volcanic-rock", 8.5, -6.5, 0), ("big-volcanic-rock", -9.5, 7.5, 0)]},
    "fulgora": {"props": {"gravity": 8, "pressure": 800, "magnetic-field": 99, "solar-power": 20, "day-night-cycle": 10800},
                "day": 10800, "mb": 100, "sol": 200, "tiles": ("fulgoran-rock", "oil-ocean-shallow"),
                "buildings": [("lightning-rod", 6.5, 4.5, 0), ("lightning-rod", -10.5, -8.5, 0), ("fulgoran-ruin-small", 3.0, -9.0, 0)]},
    "gleba": {"props": {"gravity": 20, "pressure": 2000, "magnetic-field": 10, "solar-power": 50, "day-night-cycle": 36000},
              "day": 36000, "mb": 200, "sol": 500, "tiles": ("wetland-yumako", "lowland-olive-blubber"),
              "buildings": [("agricultural-tower", 6.5, 6.5, 0), *[("yumako-tree", 3.0 + 2 * (i % 3), 10.0 + 2 * (i // 3), 0) for i in range(6)],
                            ("gleba-spawner", -16.5, -14.5, 0), ("wooden-chest", 2.5, 3.5, 0)]},
    "aquilo": {"props": {"gravity": 15, "pressure": 300, "magnetic-field": 10, "solar-power": 1, "day-night-cycle": 72000},
               "day": 72000, "mb": 50, "sol": 10, "tiles": ("snow-flat", "ice-smooth", "ammoniacal-ocean"),
               "buildings": [("heating-tower", 4.5, 4.5, 0), *[("heat-pipe", 6.5 + i, 4.5, 0) for i in range(4)],
                             ("inserter", 5.5, 7.5, 0), ("inserter", 20.5, 7.5, 0), ("inserter", 22.5, 7.5, 0)]},
}
HEATING_RADII = {"heating-tower": 12, "heat-pipe": 1}
SPOILING = {"yumako", "jellynut"}
SEG_INTERVAL = 2
LIGHTNING_EVERY = 180
LEGS_INTERVAL = 4
ITEM_YIELD = {"tree": ("wood", 4), "simple-entity": ("stone", 20)}
MINING_SECONDS = {"tree": 1.0, "simple-entity": 2.0, "resource": 2.0}
RECIPES = {
    "iron-gear-wheel": ({"iron-plate": 2}, ("iron-gear-wheel", 1)),
    "transport-belt": ({"iron-gear-wheel": 1, "iron-plate": 1}, ("transport-belt", 2)),
    "stone-furnace": ({"stone": 5}, ("stone-furnace", 1)),
    "wooden-chest": ({"wood": 2}, ("wooden-chest", 1)),
    "iron-chest": ({"iron-plate": 8}, ("iron-chest", 1)),
    "burner-mining-drill": ({"iron-gear-wheel": 3, "stone-furnace": 1, "iron-plate": 3}, ("burner-mining-drill", 1)),
}
# Machine screens: what assemblers can make (ingredients, product) on top of the hand recipes,
# what furnaces smelt, what burns.
MACHINE_RECIPES = {
    **RECIPES,
    "copper-cable": ({"copper-plate": 1}, ("copper-cable", 2)),
    "electronic-circuit": ({"iron-plate": 1, "copper-cable": 3}, ("electronic-circuit", 1)),
    "inserter": ({"electronic-circuit": 1, "iron-gear-wheel": 1, "iron-plate": 1}, ("inserter", 1)),
    "automation-science-pack": ({"copper-plate": 1, "iron-gear-wheel": 1}, ("automation-science-pack", 1)),
    **mock_machines.RECIPES,
}
SMELTING = {"iron-ore": "iron-plate", "copper-ore": "copper-plate", "stone": "stone-brick"}
FUELS = {"coal", "wood"}
CRAFT_TICKS = 60
SCREEN_INTERVAL = 30
RECIPE_LIST_EVERY = 10
REACH = 10.0  # to the entity's edge, like LuaControl::can_reach_entity
SCREEN_KINDS = {"container": "container", "assembling-machine": "crafter", "furnace": "furnace", "lab": "lab",
                "constant-combinator": "combinator", "arithmetic-combinator": "combinator",
                "decider-combinator": "combinator", "selector-combinator": "combinator", "lamp": "other", "pump": "other",
                "programmable-speaker": "other", "display-panel": "panel", "power-switch": "switch", "transport-belt": "other",
                "locomotive": "train", "cargo-wagon": "train", "train-stop": "stop",
                "inserter": "inserter", "splitter": "splitter", "ammo-turret": "turret", "electric-pole": "pole",
                "car": "vehicle", "logistic-container": "container", "roboport": "roboport", **mock_space.SPACE_KINDS,
                **mock_vehicles.SCREEN_KINDS}
# Circuit connection settings by entity type, as circuit_settings.lua sends them (`gui.cc`):
# the behaviour type's name and its fields' defaults.
COND = {"comparator": "<", "constant": 0}
CC_ON_OFF = {"circuit_enable_disable": 0, "circuit_condition": COND, "connect_to_logistic_network": 0, "logistic_condition": COND}
CRAFTER_CC = {"circuit_read_contents": 0, "include_in_crafting": 0, "circuit_read_ingredients": 0,
              "circuit_read_recipe_finished": 0, "circuit_recipe_finished_signal": {}, "circuit_read_working": 0,
              "circuit_working_signal": {}, "read_fuel": 0}
CC_DEFAULTS = {
    "inserter": ("inserter", {**CC_ON_OFF, "circuit_set_filters": 0, "circuit_read_hand_contents": 0, "circuit_hand_read_mode": "pulse",
                              "circuit_set_stack_size": 0, "circuit_stack_control_signal": {}}),
    "transport-belt": ("transport_belt", {**CC_ON_OFF, "read_contents": 0, "read_contents_mode": "pulse"}),
    "assembling-machine": ("assembling_machine", {**CC_ON_OFF, "circuit_set_recipe": 0, **CRAFTER_CC}),
    "furnace": ("furnace", {**CC_ON_OFF, **CRAFTER_CC}),
    "lamp": ("lamp", {**CC_ON_OFF, "use_colors": 0, "color_mode": "color_mapping", "red_signal": {"type": "virtual", "name": "signal-red"},
                      "green_signal": {"type": "virtual", "name": "signal-green"}, "blue_signal": {"type": "virtual", "name": "signal-blue"},
                      "rgb_signal": {"type": "virtual", "name": "signal-white"}}),
    "mining-drill": ("mining_drill", {**CC_ON_OFF, "circuit_read_resources": 1, "resource_read_mode": "this_miner"}),
    "pump": ("pump", {**CC_ON_OFF, "set_filter": 0}),
    "power-switch": ("generic_on_off", dict(CC_ON_OFF)),
    "container": ("container", {"read_contents": 1, "read_empty_slots": 0, "empty_slots_signal": {}}),
    "logistic-container": ("logistic_container", {"read_contents": 1, "set_requests": 0, "circuit_condition_enabled": 0,
                                                  "circuit_condition": COND, "read_empty_slots": 0, "empty_slots_signal": {}}),
    "train-stop": ("train_stop", dict(CC_ON_OFF)),
    "ammo-turret": ("turret", {**CC_ON_OFF, "read_ammo": 1, "set_priority_list": 0, "set_ignore_unlisted_targets": 0,
                               "ignore_unlisted_targets_condition": COND}),
    "programmable-speaker": ("programmable_speaker", {"circuit_condition": COND}),
    "splitter": ("splitter", {"set_input_side": 0, "input_left_condition": COND, "input_right_condition": COND,
                              "set_output_side": 0, "output_left_condition": COND, "output_right_condition": COND, "set_filter": 0}),
    "roboport": ("roboport", {"read_logistics": 1, "read_items_mode": "logistics", "read_robot_stats": 0,
                              "available_logistic_output_signal": {"type": "virtual", "name": "signal-X"},
                              "total_logistic_output_signal": {"type": "virtual", "name": "signal-Y"},
                              "available_construction_output_signal": {"type": "virtual", "name": "signal-Z"},
                              "total_construction_output_signal": {"type": "virtual", "name": "signal-T"},
                              "roboport_count_output_signal": {"type": "virtual", "name": "signal-R"}}),
    "wall": ("wall", {"open_gate": 0, "circuit_condition": COND, "read_sensor": 0, "output_signal": {"type": "virtual", "name": "signal-G"}}),
}
SPEAKER_INSTRUMENTS = [["alarms", ["alarm-1", "alarm-2", "buzzer-1", "buzzer-2", "buzzer-3", "ring", "siren"]],
                       ["miscellaneous", ["achievement-unlocked", "alert-destroyed", "armor-insert", "cannot-build", "console-message"]],
                       ["drum-kit", ["kick-1", "kick-2", "snare-1", "snare-2", "hat-1", "clap", "cowbell"]],
                       ["piano", ["F3", "F#3", "G3", "G#3", "A3", "A#3", "B3", "C4", "C#4", "D4", "D#4", "E4"]]]
# Factorio's world controls (ui_actions.lua): Alt-mode icons once a second, the statistics.
ALT_INTERVAL = 60
FAST_INSERTERS = {"inserter"}  # filter slots in the mock: the plain inserter has five, for the screen
STATS = {"item": [["iron-plate", 42.0, 11.5, 2520, 690], ["iron-gear-wheel", 6.0, 4.0, 360, 240], ["copper-plate", 30.0, 0.0, 1800, 0]],
         "fluid": [["water", 1200.0, 1200.0, 72000, 72000], ["steam", 1200.0, 1150.0, 72000, 69000]],
         "kill": [["small-biter", 0.5, 0.0, 12, 0]],
         "electric": [["steam-engine", 0.0, 540.0, 0, 32400], ["assembling-machine-1", 75.0, 0.0, 4500, 0], ["inserter", 13.2, 0.0, 792, 0]]}
STATS.update(mock_info.STATS_MORE)
# The logistic network around the starter roboport: what its chests are, how far it reaches from
# the roboport (a square, like a logistic area), how often `ln` and `rc` go out.
LOGISTIC_MODES = {"requester-chest": "requester", "storage-chest": "storage", **mock_machines.LOGISTIC_MODES}
LOGISTIC_REACH = 25.0
NETWORK_INTERVAL = 60
CARGO_INTERVAL = 10
# The train shuttling along the rail line (movers 700-702) between two stops, and how often
# `tr` is sent.
TRAIN_UNITS = (700, 701, 702)
TRAIN_SPEED = 0.15
TRAIN_INTERVAL = 30
# What a pipe connects to on a neighbouring tile (extra.pc: 1 north, 2 east, 4 south, 8 west).
PIPE_TARGETS = {"pipe", "boiler", "generator", "storage-tank", "pump", "offshore-pump"}
PIPE_SIDES = ((0, -1, 1), (1, 0, 2), (0, 1, 4), (-1, 0, 8))
# What items build when it isn't the entity of the same name, and which entities fast-replace
# each other.
PLACE_RESULT = {"rail": "straight-rail"}
FAST_GROUP = {"transport-belt": "belt", "fast-transport-belt": "belt", "underground-belt": "belt"}
# The mock's one blueprint: two belts running east into a chest. (entity, dx, dy, direction)
BLUEPRINT = [("transport-belt", -1, 0, 4), ("transport-belt", 0, 0, 4), ("wooden-chest", 1, 0, 0)]
UPGRADES = {"transport-belt": "fast-transport-belt"}
# Factorio's exchange strings ("0" + base64 of zlib JSON), as the mod's export_stack writes them.
PLANNER_ITEMS = {"blueprint": "blueprint", "blueprint_book": "blueprint-book",
                 "deconstruction_planner": "deconstruction-planner", "upgrade_planner": "upgrade-planner"}
PLANNER_KEYS = {v: k for k, v in PLANNER_ITEMS.items()}
BP_PART = 16000
GAME_VERSION = (2 << 48) | (1 << 32) | (23 << 16)


def bp_encode(record):
    return "0" + base64.b64encode(zlib.compress(json.dumps(record, separators=(",", ":")).encode(), 9)).decode()


def bp_decode(text):
    try:
        return json.loads(zlib.decompress(base64.b64decode(text.strip()[1:])))
    except (ValueError, zlib.error, TypeError):
        return {}


def bp_kind(record):
    return next((k for k in PLANNER_ITEMS if isinstance(record, dict) and isinstance(record.get(k), dict)), "")


def bp_entities(rows):
    return [{"entity_number": n + 1, "name": name, "position": {"x": x + 0.5, "y": y + 0.5}, "direction": d}
            for n, (name, x, y, d) in enumerate(rows)]


def default_planner(item):
    """What a planner in the mock's inventory holds until the client writes another string."""
    kind = PLANNER_KEYS[item]
    body = {"item": item, "version": GAME_VERSION}
    if kind == "blueprint":
        body.update(label="Belts into a chest", entities=bp_entities(BLUEPRINT),
                    icons=[{"signal": {"name": "transport-belt"}, "index": 1}])
    elif kind == "upgrade_planner":
        body["settings"] = {"mappers": [{"from": {"type": "entity", "name": "transport-belt"},
                                         "to": {"type": "entity", "name": "fast-transport-belt"}, "index": 0}]}
    elif kind == "deconstruction_planner":
        body["settings"] = {}
    elif kind == "blueprint_book":
        body["blueprints"] = []
    return {kind: body}


# The game's library tab ("game blueprints"): a blueprint and a book of two pages.
GAME_LIBRARY = [
    {"blueprint": {"item": "blueprint", "label": "Chest row", "version": GAME_VERSION,
                   "icons": [{"signal": {"name": "wooden-chest"}, "index": 1}],
                   "entities": bp_entities([("wooden-chest", 0, 0, 0), ("wooden-chest", 1, 0, 0), ("wooden-chest", 2, 0, 0)])}},
    {"blueprint_book": {"item": "blueprint-book", "label": "Belts", "version": GAME_VERSION, "active_index": 0, "blueprints": [
        {"index": 0, "blueprint": {"item": "blueprint", "label": "Belt line", "version": GAME_VERSION,
                                   "entities": bp_entities([("transport-belt", x, 0, 4) for x in range(4)])}},
        {"index": 1, "blueprint": {"item": "blueprint", "label": "Belt corner", "version": GAME_VERSION,
                                   "entities": bp_entities([("transport-belt", 0, 0, 4), ("transport-belt", 1, 0, 8),
                                                            ("transport-belt", 1, 1, 8)])}}]}},
]
STARTING_ITEMS = {
    "fast-transport-belt": 10, "rail": 20, "blueprint": 1, "deconstruction-planner": 1, "upgrade-planner": 1,
    "iron-plate": 60, "wood": 10, "stone": 20, "transport-belt": 50, "wooden-chest": 5,
    "stone-furnace": 5, "inserter": 10, "burner-mining-drill": 2, "small-electric-pole": 10,
    "assembling-machine-1": 2, "speed-module": 4, "productivity-module": 2,
    "stone-brick": 100, "concrete": 100, "hazard-concrete": 50, "landfill": 50, "underground-belt": 10, "pipe": 50,
    "pipe-to-ground": 10, "grenade": 10, "cliff-explosives": 5, "land-mine": 10, "rail-support": 5,
}
# The UI data: inventory slots, the quickbar, hand-recipe details, a small technology tree.
MAIN_SLOTS = 80
QUICKBAR_SIZE = 100
# Entity types Factorio 2.1.23 opens no window for (entity_ui.lua NO_WINDOW).
NO_WINDOW = {"fluid-wagon", "lightning-attractor", "fusion-generator", "thruster"}
# Modules (`iuse` "m") and their category; `modreq` asks for them (F6).
MODULES = {"speed-module": "speed", "productivity-module": "productivity"}

SLOT_SIZES = {"chest": 16, "input": 4, "output": 4, "fuel": 1, "burnt": 1, "modules": 2, "cargo": 40, "trash": 10, "robots": 7, "repair": 7,
              "turret_ammo": 1, "trunk": 20, "car_ammo": 1, "rocket": 10}
BIG_STACKS = {"iron-plate", "copper-plate", "iron-gear-wheel", "transport-belt", "wood", "copper-cable"}
RECIPE_GROUPS = {"transport-belt": ("logistics", "b", "belt", "b"), "wooden-chest": ("logistics", "b", "storage", "a"),
                 "iron-chest": ("logistics", "b", "storage", "a"), "stone-furnace": ("production", "c", "smelting-machine", "c"),
                 "burner-mining-drill": ("production", "c", "extraction-machine", "d")}
SCIENCE = [["automation-science-pack", 1]]
TECHS = {  # name: (prerequisites, ingredients, unit count, seconds per unit)
    "automation": ([], SCIENCE, 10, 10), "logistics": ([], SCIENCE, 25, 15), "electronics": (["automation"], SCIENCE, 30, 15),
    "steel-processing": ([], SCIENCE, 50, 5),
    "logistics-2": (["logistics", "electronics"], SCIENCE + [["logistic-science-pack", 1]], 200, 30),
    "steam-power": ([], [], 1, 0), "mining-productivity-3": (["steel-processing"], SCIENCE + [["logistic-science-pack", 1]], 250, 60),
}
# A deeper piece of Factorio's tree (its real prerequisites), for the technology screen's layout.
GREEN = SCIENCE + [["logistic-science-pack", 1]]
TECHS.update({
    "logistic-science-pack": (["automation"], SCIENCE, 75, 5), "fast-inserter": (["automation"], SCIENCE, 30, 15),
    "automation-2": (["electronics", "steel-processing", "logistic-science-pack"], GREEN, 40, 15),
    "advanced-material-processing": (["steel-processing", "logistic-science-pack"], GREEN, 75, 30),
    "engine": (["steel-processing", "logistic-science-pack"], GREEN, 100, 15),
    "fluid-handling": (["automation-2", "engine"], GREEN, 50, 15),
    "oil-processing": (["fluid-handling"], GREEN, 100, 30),
    "railway": (["logistics-2", "engine"], GREEN, 75, 30),
    "automobilism": (["logistics-2", "engine"], GREEN, 100, 30),
    "physical-projectile-damage-1": (["military"], SCIENCE, 10, 30), "military": ([], SCIENCE, 10, 15),
})
# Extras of the 14-value `techs` record: [effects, level, max level (-1 infinite), trigger detail, saved progress, formula].
TECH_EXTRAS = {
    "automation": [[["unlock-recipe", "iron-gear-wheel", 0]], 1, 1, [], 0, ""],
    "steam-power": [[["unlock-recipe", "boiler", 0], ["unlock-recipe", "steam-engine", 0]], 1, 1, ["craft-item", "iron-plate", 50], 0, ""],
    "mining-productivity-3": [[["mining-drill-productivity-bonus", "", 0.1]], 3, -1, [], 250, "250*(L-2)"],
    "logistics": [[["unlock-recipe", "underground-belt", 0], ["unlock-recipe", "splitter", 0]], 1, 1, [], 400, ""],
}
# Technologies Factorio marks essential (the 15th value).
ESSENTIAL = {"automation", "electronics", "logistics-2"}
RESEARCH_TICKS = 600  # every mock technology takes 10 s
UI_INTERVAL = 30


def stack_size(item):
    return 100 if item in BIG_STACKS else 50


def fill_slots(contents, size):
    """An inventory's slots from its totals ({item: count}), stack by stack, for display."""
    slots = [0] * size
    i = 0
    for item, count in contents.items():
        while count > 0 and i < size:
            n = min(count, stack_size(item))
            # Spoiling items (Gleba) carry their freshness; the mock's are part spoiled.
            slots[i], count, i = ([item, n, "normal", 640] if item in SPOILING else [item, n]), count - n, i + 1
    return slots


ORE_PATCHES = [("iron-ore", 30, -25, 10), ("copper-ore", -35, 15, 9), ("coal", 12, 38, 8), ("stone", -22, -36, 6)]
# --belt-field: a block of full belts for watching the client draw thousands of items.
BELT_FIELD_ITEMS = ("iron-plate", "copper-plate", "iron-gear-wheel", "electronic-circuit", "iron-ore", "copper-ore",
                    "coal", "stone", "copper-cable", "steel-plate", "advanced-circuit", "plastic-bar", "sulfur",
                    "automation-science-pack", "logistic-science-pack", "processing-unit", "stone-brick", "wood",
                    "battery", "engine-unit", "firearm-magazine", "transport-belt", "inserter", "pipe")
# The character's gear (`eq`): power armour with a 10x10 grid, some equipment in it and some in
# the inventory. name: (width, height, max energy J, max shield, movement bonus)
EQUIPMENT = {
    "fission-reactor-equipment": (4, 4, 0, 0, 0.0), "energy-shield-mk2-equipment": (2, 2, 360000, 150, 0.0),
    "energy-shield-equipment": (2, 2, 120000, 50, 0.0), "battery-mk2-equipment": (1, 2, 100000000, 0, 0.0),
    "battery-equipment": (1, 2, 20000000, 0, 0.0), "exoskeleton-equipment": (2, 4, 400000, 0, 0.3),
    "night-vision-equipment": (2, 2, 120000, 0, 0.0), "personal-roboport-mk2-equipment": (2, 2, 35000000, 0, 0.0),
    "solar-panel-equipment": (1, 1, 0, 0, 0.0),
}
ARMOR = "power-armor-mk2"
GEAR_START = [("fission-reactor-equipment", 0, 0), ("energy-shield-mk2-equipment", 4, 0), ("energy-shield-mk2-equipment", 6, 0),
              ("battery-mk2-equipment", 8, 0), ("battery-mk2-equipment", 9, 0), ("exoskeleton-equipment", 0, 4),
              ("exoskeleton-equipment", 2, 4), ("night-vision-equipment", 4, 2), ("personal-roboport-mk2-equipment", 6, 2)]
GEAR_ITEMS = {"energy-shield-equipment": 2, "battery-equipment": 2, "solar-panel-equipment": 4}
VEHICLE_GRIDS = {601: (4, 4)}  # the parked car has a grid, like a car with equipment in 2.x
MOCK_PLAYERS = [  # [index, name, connected, r, g, b, character mover unit, surface, admin, afk ticks, tag, armour]
    [1, "Engineer", 1, 255, 160, 40, 900, "nauvis", 1, 0, "", "power-armor"],
    [2, "Away", 0, 90, 140, 255, 0, "nauvis", 0, 0, "afk", ""],
]
CHARACTER_RESPAWN_TICKS = 600  # Factorio character respawn_time: 10 s
ITEM_PROTOS = sorted({"iron-plate", "copper-plate", "iron-gear-wheel", "coal", "iron-ore", "copper-ore", "stone", "wood",
                      "yumako", "jellynut", "stone-brick", *STARTING_ITEMS, *MACHINE_RECIPES, *BELT_FIELD_ITEMS,
                      *EQUIPMENT, ARMOR, *mock_space.ITEMS, *mock_shots.GUNS, *(a for a, _, _ in mock_shots.GUNS.values()),
                      *mock_shots.CAPSULES})

# The map (`chart`, `tags`): chunks within MAP_START_RADIUS of the origin start charted, and the
# player charts MAP_CHART_RADIUS chunks around itself every MAP_CHART_INTERVAL ticks. Entities are
# drawn in their prototype colour (the mod uses Factorio's map colours); movers aren't drawn.
MAP_START_RADIUS = 4
MAP_CHART_RADIUS = 3
MAP_CHART_INTERVAL = 120
MAP_CHUNKS_PER_TICK = 4
MAP_MAX_CHUNKS = 1024
MAP_RESOLUTIONS = (2, 4, 8, 16, 32)
MAP_GHOST = (145, 97, 145)
MAP_LAYERS = {"resource": 1, "tree": 2, "simple-entity": 2}
MAP_SKIP = {"character", "unit", "car", "locomotive", "cargo-wagon", "logistic-robot"}
EID = {p[0]: i + 1 for i, p in enumerate(ENTITY_PROTOS)}
mock_creature_showcase.EID.update(EID)
mock_enemy_showcase.EID.update(EID)
# `eprops`, as Factorio 2.1.23 sends them: reaches, and the overlays drawn on hover and while placing.
EPROPS = [
    [EID["underground-belt"], 5, 0, 0], [EID["small-electric-pole"], 0, 7.5, 2.5, {"cw": 7.5}], [EID["pipe-to-ground"], 10, 0, 0],
    [EID["inserter"], 0, 0, 0, {"ip": [0, -1], "id": [0, 1.2], "cw": 9}],
    [EID["burner-inserter"], 0, 0, 0, {"ip": [0, -1], "id": [0, 1.2]}],
    [EID["roboport"], 0, 0, 0, {"lr": 25, "cr": 55}],
    [EID["electric-mining-drill"], 0, 0, 0, {"mr": 2.49, "vp": [0, -1.85],
                                             "fb": [[-1, 0, 12, "b"], [1, 0, 4, "b"], [0, 1, 8, "b"]], "fo": 1}],
    [EID["burner-mining-drill"], 0, 0, 0, {"mr": 0.99, "vp": [-0.35, -1.3]}],
    [EID["assembling-machine-2"], 0, 0, 0, {"fb": [[0, -1, 0, "i"], [0, 1, 8, "o"]], "fo": 1}],
    [EID["boiler"], 0, 0, 0, {"fb": [[-1, 0.5, 12, "b"], [1, 0.5, 4, "b"], [0, -0.5, 0, "o"]]}],
    [EID["steam-engine"], 0, 0, 0, {"fb": [[0, 2, 8, "b"], [0, -2, 0, "b"]]}],
    # Circuit wire reach (get_max_circuit_wire_distance) of what can take a circuit wire.
    *[[EID[n], 0, 0, 0, {"cw": 9}] for n in ("constant-combinator", "arithmetic-combinator", "decider-combinator",
                                             "selector-combinator", "small-lamp", "programmable-speaker", "display-panel",
                                             "pump", "transport-belt", "wooden-chest", "iron-chest", "gun-turret",
                                             "assembling-machine-1", "train-stop", "stone-wall")],
    [EID["power-switch"], 0, 0, 0, {"cw": 9, "ww": 10}],
]
ETYPE = {p[0]: p[1] for p in ENTITY_PROTOS}
ESIZE = {p[0]: (p[2], p[3]) for p in ENTITY_PROTOS}
TID = {p[0]: i + 1 for i, p in enumerate(TILE_PROTOS)}
# Nauvis decoratives the mock scatters on grass and dirt (sent only to clients with `dc`).
DECORATIVE_PROTOS = ["green-carpet-grass", "green-hairy-grass", "green-small-grass", "brown-asterisk",
                     "red-asterisk", "green-bush-mini", "small-rock", "tiny-rock"]
DID = {name: i + 1 for i, name in enumerate(DECORATIVE_PROTOS)}
FID = {p[0]: i + 1 for i, p in enumerate(FLUID_PROTOS)}
IID = {name: i + 1 for i, name in enumerate(ITEM_PROTOS)}



def angle_step(walk):
    """The 8-way direction for this tick of a walk at an angle ([dir, until, thousandths, err]), as
    puppet.lua's angle_step: whichever neighbour brings the sideways drift back towards the line."""
    turn = walk[2] / 1000 * 8
    lo = math.floor(turn) % 8
    hi = (lo + 1) % 8
    rad = walk[2] / 1000 * 2 * math.pi
    slo, shi = (math.sin(e / 8 * 2 * math.pi - rad) for e in (lo, hi))
    pick, step = (hi, shi) if abs(walk[3] + shi) < abs(walk[3] + slo) else (lo, slo)
    walk[3] += step
    return pick * 2

def fixed(v):
    return int(math.floor(v * 256 + 0.5))


def hash01(x, y, salt):
    h = (x * 374761393 + y * 668265263 + salt * 2147483647) & 0xFFFFFFFF
    h = ((h ^ (h >> 13)) * 1274126177) & 0xFFFFFFFF
    return (h ^ (h >> 16)) / 0xFFFFFFFF


def noise(x, y, scale, salt):
    """Smooth value noise in 0..1."""
    fx, fy = x / scale, y / scale
    x0, y0 = math.floor(fx), math.floor(fy)
    tx, ty = fx - x0, fy - y0
    tx, ty = tx * tx * (3 - 2 * tx), ty * ty * (3 - 2 * ty)
    a, b = hash01(x0, y0, salt), hash01(x0 + 1, y0, salt)
    c, d = hash01(x0, y0 + 1, salt), hash01(x0 + 1, y0 + 1, salt)
    return (a * (1 - tx) + b * tx) * (1 - ty) + (c * (1 - tx) + d * tx) * ty


class Entity:
    def __init__(self, unit, name, x, y, direction=0, extra=None):
        self.unit, self.name, self.x, self.y, self.dir = unit, name, x, y, direction
        self.extra = extra or {}

    @property
    def type(self):
        return ETYPE[self.name]

    def key(self):
        return self.unit if self.unit else (EID[self.name], fixed(self.x), fixed(self.y))

    def record(self):
        rec = [self.unit, EID[self.name], fixed(self.x), fixed(self.y), self.dir]
        if self.extra:
            rec.append(self.extra)
        return rec

    def box(self):
        w, h = ESIZE[self.name]
        if self.dir in (4, 12):
            w, h = h, w
        return self.x - w / 2, self.y - h / 2, self.x + w / 2, self.y + h / 2


def darkness_at(daytime):
    """Factorio's default day: light until dusk (0.25), dark from evening (0.45) to morning
    (0.55), light again from dawn (0.75). Full night is 0.85 dark."""
    if daytime <= 0.25 or daytime >= 0.75:
        return 0.0
    if daytime < 0.45:
        return 0.85 * (daytime - 0.25) / 0.2
    if daytime <= 0.55:
        return 0.85
    return 0.85 * (0.75 - daytime) / 0.2


class MockGame(mock_info.InfoMixin):
    def __init__(self, seed, drop, day_length=25000, start=(-3.0, 0.5)):
        self.seed, self.drop, self.day_length = seed, drop, day_length
        self.rng = random.Random(seed)
        self.tick = 0
        self.next_unit = 1000
        self.client = None  # {"addr", "sid", "last_seen"}
        self.rseq = 0
        self.outbox = []
        self.batches = {}  # client address -> [datagrams waiting to be joined, bytes] (send_raw)
        self.subs, self.queue = {}, []
        self.focus = (0.0, 0.0, 48.0)
        self.remote_view = False  # focus rv = 1: movers only where radars or the character see
        self.generated = set()
        self.entities = {}  # key -> Entity
        self.by_chunk = {}  # (cx, cy) -> set of keys
        self.tile_overrides = {}
        self.working = {}
        self.always_working = False  # review.py: machines never stop, to watch their animation
        self.player = {"x": float(start[0]), "y": float(start[1]), "dir": 8, "walk": None, "mining": None,
                       "inventory": dict(STARTING_ITEMS), "craft": [], "unit": self._unit(), "pickup": None,
                       "hp": float(CHARACTER_HEALTH), "guns": [["pistol", "firearm-magazine", 10], ["", "", 0], ["", "", 0]],
                       "sel": 0, "rounds": ROUNDS_PER_MAGAZINE, "shoot": None, "fired": -1000,
                       "vehicle": None, "drive": None}
        self.guns_sig = None
        self.inv_sig = None
        self.layout = [None] * MAIN_SLOTS  # the main inventory's slots as the client arranged them
        self.slots_sig = self.craftable_sig = None
        self.quickbar = {"page": 1, "sel": 0, "items": [""] * QUICKBAR_SIZE}
        self.researched, self.research, self.research_queue, self.research_progress = {"automation"}, None, [], 0
        self.queue_sent = False
        self.machines = {}  # unit -> {"recipe", "progress", "inv": {role: {item: count}}}, made on first open
        self.screen = None  # {"unit", "sent", "due"} while the client has a machine screen open
        self.movers = self._make_movers()
        mock_vehicles.machines(self)
        self.belt = []  # the starter base's belt, north to south
        self.belt_field = []  # --belt-field: columns of belts, each north to south
        self.belt_field_rect = None  # (x0, y0, x1, y1) kept clear of trees, with a margin
        self.inserters = []  # (entity, item it carries)
        self.wired = {}  # combinator unit -> the constant combinator feeding it (red)
        # The character's logistic requests (`clog`): its sections (space.lua's form) and the force's groups.
        self.char_logistics = {"on": 1, "trash": 0, "sec": [{"i": 1, "g": "", "on": 1, "m": 1, "man": 1, "f": []}],
                               "lgs": ["Main", "Mall"]}
        self.char_color = [255, 161, 66]  # Factorio's default player colour (`ccol`)
        self.roboport = self.storage_chest = None
        self.train = {"id": 1, "manual": False, "current": 1, "east": True,
                      "records": [{"station": "East", "wait_conditions": [{"type": "time", "compare_type": "or", "ticks": 300}]},
                                  {"station": "West", "wait_conditions": [{"type": "time", "compare_type": "or", "ticks": 300}]}]}
        self.charted = {(cx, cy) for cx in range(-MAP_START_RADIUS, MAP_START_RADIUS + 1)
                        for cy in range(-MAP_START_RADIUS, MAP_START_RADIUS + 1)}
        self.map_queue, self.map_res = [], 4
        self.work_budget = WORK_BUDGET  # units a tick (budget.lua); the mock only reports it in `wb`
        # Tags by surface index: [id, x, y, text, icon type, icon name]. map_si: the surface the
        # map asked for (None: the character's).
        self.surface_tags, self.next_tag, self.tags_dirty, self.map_si = {1: [], 2: [], 3: []}, 0, False, None
        self.ground = []  # [item, x, y]: items lying on the ground
        self.surface = "nauvis"
        self.belt_lanes = ("iron-plate", "copper-plate")  # what the starter belt carries (Gleba's spoils)
        self.frozen = set()  # units of frozen machines (Aquilo)
        self.worlds = {}  # surface name -> its SURFACE_STATE while the character is elsewhere
        # `hold`: it never leaves its stop (--wait, --depart), for the travel panel's waiting states.
        self.platform = {"i": 1, "n": "Mock Orbiter", "loc": "nauvis", "from": None, "to": None, "d": 0.0,
                         "pa": 1, "sched": None, "hub": 0, "hold": False}
        # A ride in progress: {"legs", "leg", "t", "up", "ground", "unit", "to" (surface), "land"}, or
        # None; `hub` is set while the character sits in the platform's hub.
        self.trip = None
        self.in_hub = False
        self.alt = False  # Alt-mode: `ai` once a second
        self.filters = {}  # main inventory slot -> item filter (middle click)
        self.clipboard = []  # [[proto id, dx, dy, direction]] from `copy`, relative to the area's centre (fixed)
        # Grids by owner: "char" (the armour's) and vehicle units. Each {"w", "h", "eq": [[name, x, y, energy, shield]],
        # "rb" (roboport on), "mvon" (exoskeletons on)}.
        self.grids = {"char": {"w": 10, "h": 10, "rb": True, "mvon": True,
                               "eq": [[n, x, y, EQUIPMENT[n][2] // 2, 0] for n, x, y in GEAR_START]}}
        for unit, (w, h) in VEHICLE_GRIDS.items():
            self.grids[unit] = {"w": w, "h": h, "rb": True, "mvon": True, "eq": []}
        for item, n in GEAR_ITEMS.items():
            self.player["inventory"][item] = n
        self.gear_sent = {}
        self.die_after = None  # --die-at: ticks after the first handshake until the character dies
        self.die_at = None
        self.clear_areas = []  # [(x0, y0, x1, y1)] where nothing grows (mock_turrets' showcase)
        self.mortal = False  # --mortal: biters can kill the character
        self.dead = None  # {"until", "x", "y"} while the character is dead
        self.planner_data = {}  # main inventory slot -> exchange string written there (bp_set)
        self.lib_cursor = None  # the library's stack in the cursor (slot -1)
        self.bp_upload = None  # a bp_set string arriving in parts
        self.history, self.next_hist = {}, 0  # undo entries by id (history.lua)
        self.sock = None
        self.space = mock_space.Space(self, PLATFORM_DESTINATIONS, PLANETS)  # Space Age's screens (mock_space.py)
        # Several clients, as the mod does it (session.lua): another client on its own address gets
        # a state of its own (PER_CLIENT) and a character, swapped in while it is served. The world
        # is shared; the second client stays on the first one's surface.
        self.extras = {}  # addr -> {attribute: value}
        self.fresh = {a: copy.deepcopy(getattr(self, a)) for a in PER_CLIENT}
        self.characters = {self.player["unit"]: self.player}  # unit -> player, for each other's movers

    # --- world ----------------------------------------------------------------------------

    def _unit(self):
        self.next_unit += 1
        return self.next_unit

    def tile_at(self, x, y):
        key = (x, y)
        if key in self.tile_overrides:
            return self.tile_overrides[key]
        if self.surface in PLANETS and self.surface != "nauvis":
            tiles = PLANETS[self.surface]["tiles"]
            if abs(x) < 24 and abs(y) < 24:
                return tiles[0]
            v = noise(x, y, 20, self.seed + 5)
            return tiles[-1] if v > 0.7 else tiles[1] if v > 0.6 and len(tiles) > 2 else tiles[0]
        if self.surface != "nauvis":
            on_deck = any(x1 <= x < x2 and y1 <= y < y2 for x1, y1, x2, y2 in PLATFORM_DECK)
            return "space-platform-foundation" if on_deck else "empty-space"
        if x * x + y * y < 30 * 30:
            return "grass-1" if hash01(x, y, 7) < 0.7 else "grass-2"
        lake = noise(x, y, 45, self.seed + 1)
        if lake > 0.78:
            return "deepwater"
        if lake > 0.72:
            return "water"
        if lake > 0.68:
            return "sand-1"
        if noise(x, y, 25, self.seed + 2) > 0.62:
            return "dirt-1"
        return "grass-1" if hash01(x, y, 7) < 0.7 else "grass-2"

    def add(self, entity, announce=False):
        key = entity.key()
        self.entities[key] = entity
        chunk = (math.floor(entity.x / CHUNK), math.floor(entity.y / CHUNK))
        self.by_chunk.setdefault(chunk, set()).add(key)
        if entity.type == "pipe":
            entity.extra["pc"] = self.pipe_mask(entity)
        if announce and self.watched(entity):
            self.send_reliable({"t": "add", "e": entity.record()})
            if self.client and self.client.get("dc") and chunk in self.subs:
                self.send_decoratives(*chunk)  # building removes the decoratives under it
        self.refresh_pipes(entity, announce)
        return entity

    def remove(self, entity, announce=True):
        key = entity.key()
        self.entities.pop(key, None)
        chunk = (math.floor(entity.x / CHUNK), math.floor(entity.y / CHUNK))
        self.by_chunk.get(chunk, set()).discard(key)
        if announce and self.watched(entity):
            self.send_reliable({"t": "del", "u": entity.unit, "p": EID[entity.name],
                                "x": fixed(entity.x), "y": fixed(entity.y)})
        self.refresh_pipes(entity, announce)

    def entities_at(self, x, y):
        for key in self.by_chunk.get((math.floor(x / CHUNK), math.floor(y / CHUNK)), ()):
            e = self.entities.get(key)
            if e is not None:
                x1, y1, x2, y2 = e.box()
                if x1 < x < x2 and y1 < y < y2:
                    yield e

    def pipe_mask(self, pipe):
        return sum(bit for dx, dy, bit in PIPE_SIDES
                   if any(e.type in PIPE_TARGETS for e in self.entities_at(pipe.x + dx, pipe.y + dy)))

    def refresh_pipes(self, entity, announce):
        """Pipes around an entity that can hold fluid connect to it, or stop connecting."""
        if entity.type not in PIPE_TARGETS:
            return
        x1, y1, x2, y2 = entity.box()
        for ty in range(math.floor(y1) - 1, math.ceil(y2) + 1):
            for tx in range(math.floor(x1) - 1, math.ceil(x2) + 1):
                for e in list(self.entities_at(tx + 0.5, ty + 0.5)):
                    if e.type == "pipe" and e is not entity:
                        mask = self.pipe_mask(e)
                        if e.extra.get("pc") != mask:
                            e.extra["pc"] = mask
                            if announce and self.watched(e):
                                self.send_reliable({"t": "upd", "e": e.record()})

    def watched(self, entity):
        return self.client is not None and (math.floor(entity.x / CHUNK), math.floor(entity.y / CHUNK)) in self.subs

    def generate_chunk(self, cx, cy):
        if (cx, cy) in self.generated:
            return
        self.generated.add((cx, cy))
        if self.surface != "nauvis":
            return  # nothing grows in space
        for ty in range(cy * CHUNK, cy * CHUNK + CHUNK):
            for tx in range(cx * CHUNK, cx * CHUNK + CHUNK):
                if self.tile_at(tx, ty) in ("water", "deepwater"):
                    continue
                for name, ox, oy, r in ORE_PATCHES:
                    d = math.hypot(tx + 0.5 - ox, ty + 0.5 - oy)
                    if d < r:
                        amount = int(200 + 1500 * (1 - d / r))
                        self.add(Entity(0, name, tx + 0.5, ty + 0.5, 0, {"a": amount}))
                if (tx * tx + ty * ty < 28 * 28 or self._in_belt_field(tx, ty)
                        or (-34 <= tx < 6 and 8 <= ty < 54)
                        or any(x0 <= tx <= x1 and y0 <= ty <= y1 for x0, y0, x1, y1 in self.clear_areas)):
                    continue  # the starting area, the belt field, room round the cliffs (build_cliffs), showcases
                forest = noise(tx, ty, 30, self.seed + 3)
                roll = hash01(tx, ty, self.seed + 4)
                if forest > 0.55 and roll < (forest - 0.55) * 1.4:
                    name = "tree-01" if hash01(tx, ty, 9) < 0.6 else "tree-02"
                    jx, jy = hash01(tx, ty, 11) * 0.6 - 0.3, hash01(tx, ty, 12) * 0.6 - 0.3
                    self.add(Entity(0, name, tx + 0.5 + jx, ty + 0.5 + jy))
                elif roll > 0.9985:
                    self.add(Entity(0, "big-rock" if roll < 0.9995 else "huge-rock", tx + 1.0, ty + 1.0))
                elif forest < 0.2 and roll < 0.002:
                    self.add(Entity(0, "dead-tree-desert", tx + 0.5, ty + 0.5))

    def build_cliffs(self):
        """A plateau shaped like a plus south-west of the base, ringed by cliffs, and a short
        cliff with both ends free: every piece of a cliff chain. Factorio puts cliffs on a 4x4 grid
        (centres at 4i + 2, 4j + 2.5); each runs between two edges of its cell with the high
        ground on its left. Worked out from the high blocks round each grid point, like marching
        squares: block (i, j) has its corners on the grid points (i, j) to (i + 1, j + 1)."""
        high = {(-4, y) for y in range(3, 8)} | {(x, 5) for x in range(-6, -1)}
        # (NW, NE, SW, SE) high -> orientation; the rest (no edge, or a saddle) get no cliff.
        cases = {
            (1, 1, 0, 0): "west-to-east", (0, 0, 1, 1): "east-to-west",
            (0, 1, 0, 1): "north-to-south", (1, 0, 1, 0): "south-to-north",
            (1, 0, 0, 0): "west-to-north", (0, 1, 0, 0): "north-to-east",
            (0, 0, 0, 1): "east-to-south", (0, 0, 1, 0): "south-to-west",
            (1, 1, 1, 0): "west-to-south", (0, 1, 1, 1): "north-to-west",
            (1, 0, 1, 1): "east-to-north", (1, 1, 0, 1): "south-to-east",
        }
        for i in range(-8, 1):
            for j in range(1, 10):
                key = tuple(int(b in high) for b in ((i - 1, j - 1), (i, j - 1), (i - 1, j), (i, j)))
                if key in cases:
                    self.add(Entity(0, "cliff", 4 * i + 2, 4 * j + 2.5, 0, {"co": cases[key]}))
        for i, co in ((-7, "none-to-east"), (-6, "west-to-east"), (-5, "west-to-none")):
            self.add(Entity(0, "cliff", 4 * i + 2, 4 * 11 + 2.5, 0, {"co": co}))

    def build_starter_base(self):
        add = lambda name, x, y, d=0, extra=None: self.add(Entity(self._unit(), name, x, y, d, extra))
        self.belt = [add("transport-belt", 5.5, -4.5 + i, 8, {"s": "s"}) for i in range(15)]
        add("wooden-chest", 5.5, 10.5)
        for i in range(3):
            add("assembling-machine-1", 8.5, -2.5 + 4 * i)
            self.inserters.append((add("inserter", 6.5, -2.5 + 4 * i, 4), "iron-plate"))
        for i in range(5):
            add("stone-furnace", 2.0, -4.0 + 2 * i)
            self.inserters.append((add("burner-inserter", 3.5, -4.5 + 2 * i, 4), "coal"))
        poles = []
        for y in (-4.5, 2.5, 9.5):
            poles.append(add("small-electric-pole", 11.5, y))
            add("small-lamp", 13.5, y)
        # Copper wires along the line of poles; each pole lists its neighbours, like the mod.
        for i, pole in enumerate(poles):
            pole.extra = {"w": [other.unit for other in poles[max(0, i - 1):i + 2] if other is not pole]}
        self.low_power = self.entities[next(k for k, e in self.entities.items() if e.name == "assembling-machine-1")]
        add("lab", 16.5, 0.5)
        # A small logistic network: a roboport, a requester and a storage chest.
        self.roboport = add("roboport", 22.0, -6.0)
        add("requester-chest", 19.5, -2.5)
        self.storage_chest = add("storage-chest", 20.5, -2.5)
        # A constant combinator wired (red) into an arithmetic combinator that doubles its signal.
        const = add("constant-combinator", 14.5, 6.5)
        arith = add("arithmetic-combinator", 16.5, 6.0, 4)
        const.extra, arith.extra = {"r": [arith.unit]}, {"r": [const.unit]}
        self.wired = {arith.unit: const.unit}
        # More of the circuit network: a decider and a selector fed by the same constant, a
        # programmable speaker, a display panel, a pump and a power switch.
        decider = add("decider-combinator", 14.5, 9.0)
        add("selector-combinator", 16.5, 9.0)
        add("programmable-speaker", 18.5, 6.5)
        add("display-panel", 18.5, 8.5)
        add("pump", 20.5, 9.0)
        add("power-switch", 20.0, 6.0)
        const.extra["r"].append(decider.unit)
        lamp = next(e for e in self.entities.values() if e.unit and e.name == "small-lamp" and (e.x, e.y) == (13.5, 9.5))
        decider.extra = {"r": [const.unit], "g": [lamp.unit]}  # its output switches the lamp beside it
        lamp.extra = {"g": [decider.unit]}
        self.wired[decider.unit] = const.unit
        boiler = add("boiler", -10.5, -10.0)
        engine = add("steam-engine", -10.5, -6.5)
        # Water piped in from the north; the boiler makes steam for the engine.
        self.fluids = {boiler.unit: [("water", 180, 200, 15), ("steam", 150, 200, 165)], engine.unit: [("steam", 120, 200, 165)]}
        for i in range(4):
            pipe = add("pipe", -10.5, -11.5 - i)
            self.fluids[pipe.unit] = [("water", 100 - 5 * i, 100, 15)]
        # Heat pipes cooling off away from a (missing) reactor, and a lamp nobody wired up.
        self.heat = {add("heat-pipe", -16.5 - i, -12.5).unit: 600 - 40 * i for i in range(4)}
        self.unplugged = add("small-lamp", -6.5, -14.5)
        for i in range(20):
            add("stone-wall", 30.5, 10.5 + i)
        add("gun-turret", 28.0, 18.0)
        add("gun-turret", 31.0, 18.0)
        add("splitter", 22.0, 4.5, 8)
        # What an attack on the defences left: remnants of an assembler, a turret and a chest.
        for name, x, y, rm in (("assembling-machine-1-remnants", 24.5, 13.5, "assembling-machine-1"),
                               ("gun-turret-remnants", 25.0, 18.0, "gun-turret"), ("small-remnants", 26.5, 10.5, None)):
            self.add(Entity(0, name, x, y, 0, {"rm": EID[rm] if rm else 0}))
        add("biter-spawner", 72.5, 62.5)
        # A little spill south-west of the start, as if a chest had been mined with a full inventory.
        for i in range(12):
            item = ("iron-plate", "copper-plate", "coal", "iron-gear-wheel")[i % 4]
            self.ground.append([item, -5.0 + (i % 4) * 0.45, 3.0 + (i // 4) * 0.4])
        for x in range(-100, 101, 2):
            self.add(Entity(self._unit(), "straight-rail", float(x), -48.0, 4))
        add("train-stop", -82.0, -46.0, 12, {"n": "West"})
        add("train-stop", 82.0, -46.0, 4, {"n": "East"})
        self.space.build_nauvis(add)

    # --- space platform -------------------------------------------------------------------

    def surface_fields(self, msg):
        msg["surface"] = self.surface
        if self.surface in PLANETS:
            msg["si"], msg["planet"] = 1 if self.surface == "nauvis" else 3 + list(PLANETS).index(self.surface), self.surface
        else:
            msg["si"], msg["pf"] = 2, self.platform["i"]
        return msg

    def switch_surface(self, name, x, y, view=False):
        """Moves the character to another surface, like the mod's change_surface: the world is
        swapped, subscriptions are dropped, and the client is told with `surface`."""
        self.worlds[self.surface] = {k: getattr(self, k) for k in SURFACE_STATE}
        self.surface = name
        if name in self.worlds:
            for k, v in self.worlds.pop(name).items():
                setattr(self, k, v)
        else:
            self.entities, self.by_chunk, self.generated, self.tile_overrides, self.working = {}, {}, set(), {}, {}
            self.belt, self.inserters, self.fluids, self.heat, self.ground = [], [], {}, {}, []
            self.belt_field = []
            self.belt_lanes, self.frozen = ("iron-plate", "copper-plate"), set()
            if name in PLANETS:
                self.build_planet(name)
            else:
                self.movers = self._make_asteroids()
            for bname, bx, by, d in (PLATFORM_BUILDINGS if name not in PLANETS else []):
                e = self.add(Entity(self._unit(), bname, bx, by, d))
                if bname == "space-platform-hub":
                    self.platform["hub"] = e.unit
        p = self.player
        p.update(x=float(x), y=float(y), walk=None, mining=None, pickup=None, shoot=None)
        self.subs, self.queue = {}, []
        self.screen = None
        msg = self.surface_fields({"t": "surface", "x": fixed(x), "y": fixed(y)})
        if view:
            msg["view"] = 1
        self.send_reliable(msg)
        self.send_platforms()
        self.send_planet()
        self.territories_due = True

    def _make_asteroids(self):
        rng = random.Random(self.seed + 5)
        out = []
        for i in range(14):
            side = -1 if i % 2 else 1
            out.append({"unit": 900 + i, "name": "medium-metallic-asteroid" if i % 3 else "small-carbonic-asteroid",
                        "kind": "drift", "x": side * rng.uniform(23.0, 45.0), "speed": rng.uniform(0.03, 0.08),
                        "phase": rng.uniform(0, 120), "dead_until": 0})
        return out

    def platform_state(self):
        pf = self.platform
        if pf["pa"]:
            return "paused"
        if not pf["sched"]:
            return "no_schedule"
        if pf["to"]:
            return "on_the_path"
        # Its stop is done and the next is elsewhere: Factorio holds it while cargo is on its way.
        sched = pf["sched"]
        return "waiting_for_departure" if sched["l"][sched["c"] - 1] != pf["loc"] else "waiting_at_station"

    def platform_record(self):
        pf = self.platform
        rec = {"i": pf["i"], "n": pf["n"], "st": self.platform_state(), "pa": pf["pa"], "hub": pf["hub"],
               "sp": 120.0 if pf["to"] and not pf["pa"] else 0.0, "w": 86600}
        if pf["to"]:
            rec.update({"from": pf["from"], "to": pf["to"], "d": int(pf["d"] * 1000), "len": PLATFORM_TRIP_KM})
        else:
            rec["loc"] = pf["loc"]
            nx = self.platform_next(pf)
            if nx:
                rec["nx"] = nx
        if pf["sched"]:
            rec["sch"] = {"c": pf["sched"]["c"], "l": list(pf["sched"]["l"])}
        return rec

    @staticmethod
    def platform_next(pf):
        """platforms.lua's next_stop: where a stopped platform's schedule takes it next, or None."""
        sched = pf["sched"]
        if not sched or not sched["l"]:
            return None
        names, cur = sched["l"], sched["c"]
        if names[cur - 1] != pf["loc"]:
            return names[cur - 1]
        for k in range(1, len(names)):
            name = names[(cur - 1 + k) % len(names)]
            if name != pf["loc"]:
                return name
        return None

    def send_platforms(self):
        # The remote view moves the mock's character to the viewed surface, the mod's stays put.
        on = self.platform["i"] if self.surface not in PLANETS and getattr(self, "viewing_from", None) is None else 0
        msg = {"t": "plat", "on": on, "l": [self.platform_record()],
               "dest": PLATFORM_DESTINATIONS}
        if self.surface == "nauvis":
            msg["here"] = "nauvis"
        self.send_now(msg)

    # --- the other planets -------------------------------------------------------------------

    def send_planet(self):
        spec = PLANETS.get(self.surface)
        name = self.surface if spec else "space"
        spec = spec or {"props": {"gravity": 0, "pressure": 0, "magnetic-field": 0, "solar-power": 300}, "day": 25000, "mb": 1000, "sol": 3000}
        self.send_reliable({"t": "planet", "name": name, "props": spec["props"], "day": spec["day"], "always": 0 if name != "space" else 1,
                            "mb": spec["mb"], "sol": spec["sol"], "dusk": 250, "evening": 450, "morning": 550, "dawn": 750,
                            "heat": [[EID[n], r] for n, r in HEATING_RADII.items()],
                            "nb": self.space.blocked(name == "space", EID)})

    def send_territories(self):
        """Vulcanus' demolisher territories, as planets.lua sends them: one territory of chunks east
        of the start area (empty elsewhere, which clears them)."""
        l = []
        if self.surface == "vulcanus":
            l.append([v for cx in range(2, 6) for cy in range(-2, 2) for v in (cx, cy)])
        self.send_now({"t": "terr", "part": 1, "parts": 1, "si": self.surface_index(), "l": l})

    def build_planet(self, name):
        spec = PLANETS[name]
        self.movers = []
        for bname, bx, by, d in spec.get("buildings", []):
            e = self.add(Entity(self._unit(), bname, bx, by, d))
            if bname == "heat-pipe":
                self.heat[e.unit] = 520
            elif bname == "inserter" and abs(bx - 4.5) > HEATING_RADII["heating-tower"]:
                self.frozen.add(e.unit)
            elif bname == "wooden-chest":
                self.machines[e.unit] = {"recipe": None, "progress": 0, "inv": {"chest": {"yumako": 40, "jellynut": 12}}}
        if name == "gleba":
            add = lambda bname, x, y, d=0, extra=None: self.add(Entity(self._unit(), bname, x, y, d, extra))
            self.belt = [add("transport-belt", -4.5, -4.5 + i, 8, {"s": "s"}) for i in range(8)]
            self.belt_lanes = ("yumako", "jellynut")
            self.movers.append({"unit": self._unit(), "name": "small-stomper-pentapod", "kind": "circle", "cx": -10.0, "cy": 10.0,
                                "r": 6.0, "speed": 0.01, "phase": 0})

    def demolisher(self):
        """Vulcanus' small demolisher crawling round the start area: [segment proto id, x, y,
        orientation, ...], head first (mock_creature_showcase's chain)."""
        return mock_creature_showcase.demolisher(self, "small", 0.0, 0.0, 30.0, 0.004)

    def tick_planet(self):
        if getattr(self, "territories_due", False) or self.tick % 3600 == 0:
            self.territories_due = False
            self.send_territories()
        if self.surface == "vulcanus" and self.tick % SEG_INTERVAL == 0:
            self.send_now({"t": "seg", "l": [[90000, EID["small-demolisher"], self.demolisher()]]})
        elif self.surface == "fulgora" and self.tick % LIGHTNING_EVERY == 0:
            # Every other strike hits a rod (caught), the rest land on open ground.
            rods = [e for e in self.entities.values() if e.name == "lightning-rod"]
            if (self.tick // LIGHTNING_EVERY) % 2 and rods:
                rod = rods[(self.tick // LIGHTNING_EVERY // 2) % len(rods)]
                strike = [fixed(rod.x), fixed(rod.y), 1]
            else:
                strike = [fixed(self.rng.uniform(-30, 30)), fixed(self.rng.uniform(-30, 30)), 0]
            self.send_now({"t": "lt", "l": [strike]})
        elif self.surface == "gleba":
            if self.tick % 60 == 0:
                growth = []
                for i, e in enumerate(e for e in self.entities.values() if e.name == "yumako-tree"):
                    growth += [e.unit, fixed(e.x), fixed(e.y), ((self.tick + i * 100) % 600) * 1000 // 600]
                self.send_now({"t": "pg", "l": growth})
                spawners = [e.unit for e in self.entities.values() if e.name == "gleba-spawner"]
                self.send_now({"t": "sp", "l": [v for u in spawners for v in (u, 2)]})
            if self.tick % LEGS_INTERVAL == 0:
                out = []
                for m in self.movers:
                    if m["name"] == "small-stomper-pentapod":
                        x, y, _ = self.mover_state(m)
                        # Five feet round the body; every other one steps forward in turn.
                        step = (self.tick // 20) % 2
                        feet = []
                        for k, (fx, fy) in enumerate(((-1.2, -1.2), (1.2, -1.2), (1.2, 1.2), (-1.2, 1.2), (0.0, 1.6))):
                            feet += [fixed(x + fx + (0.3 if (k + step) % 2 else 0.0)), fixed(y + fy)]
                        out.append([m["unit"], feet])
                self.send_now({"t": "legs", "l": out})
        elif self.surface == "aquilo" and self.tick % 60 == 0:
            self.send_now({"t": "fz", "l": sorted(u for u in self.frozen if u in self.entities)})

    def tick_platform(self):
        pf = self.platform
        before = self.platform_state()
        self.tick_platform_motion()
        after = self.platform_state()
        if after != before:
            self.send_now({"t": "pst", "i": pf["i"], "st": after, "old": before, "loc": pf["loc"] or ""})
        if self.tick % 60 == 0:
            self.send_platforms()

    def tick_platform_motion(self):
        pf = self.platform
        if pf["to"] and not pf["pa"]:
            pf["d"] += 1 / PLATFORM_TRIP_TICKS
            if pf["d"] >= 1:
                pf.update(loc=pf["to"], to=None, d=0.0)
                pf["from"] = None
        elif pf["sched"] and not pf["pa"] and not pf["hold"]:
            want = pf["sched"]["l"][pf["sched"]["c"] - 1]
            if want != pf["loc"]:
                pf.update({"from": pf["loc"], "to": want, "loc": None, "d": 0.0})

    def platform_command(self, t, msg):
        pf = self.platform
        if t != "plat_board" and msg.get("i") != pf["i"]:
            self.message("No such platform")
            return
        if t == "plat_go":
            to = str(msg.get("to", ""))
            if to not in PLATFORM_DESTINATIONS:
                self.message(f"Can't travel to {to}")
                return
            pf["sched"], pf["pa"] = {"c": 1, "l": [to]}, 0
        elif t == "plat_sched":
            names = [str(n) for n in msg.get("l", []) if str(n) in PLATFORM_DESTINATIONS] if isinstance(msg.get("l"), list) else []
            c = msg.get("c", 1)
            pf["sched"] = {"c": c if isinstance(c, int) and 1 <= c <= len(names) else 1, "l": names} if names else None
        elif t == "plat_pause":
            pf["pa"] = 1 if msg.get("p") in (1, True) else 0
        elif t == "plat_board":
            i = msg.get("i", 0)
            if i == 0:
                if self.surface == "nauvis":
                    self.message("You're not on a platform")
                elif pf["loc"] not in PLANETS:
                    self.message("The platform must be stopped at a planet to drop to it")
                else:
                    self.switch_surface(pf["loc"], 0.5, 0.5)
            elif i != pf["i"]:
                self.message("No such platform")
            elif self.surface in PLANETS and pf["loc"] != self.surface:
                self.message("That platform isn't in orbit here")
            elif self.surface in PLANETS:
                self.switch_surface(PLATFORM_SURFACE, *PLATFORM_START)
            return
        self.send_platforms()

    def _make_movers(self):
        movers = []
        for i in range(10):
            name = "small-biter" if i % 3 else "medium-biter"
            movers.append({"unit": 500 + i, "name": name, "hp": BITER_HEALTH[name], "dead_until": 0,
                           "kind": "circle", "cx": 72.0, "cy": 62.0, "r": 6 + i * 0.7, "speed": 0.02 + 0.004 * i, "phase": i})
        movers.append({"unit": 600, "name": "car", "kind": "circle", "cx": -15.0, "cy": 22.0, "r": 10.0, "speed": 0.012, "phase": 0, "oriented": True})
        movers.append({"unit": 601, "name": "car", "kind": "parked", "x": -8.0, "y": 6.0, "o": 0.25, "speed": 0.0, "oriented": True})
        for i, name in enumerate(["locomotive", "cargo-wagon", "cargo-wagon"]):
            movers.append({"unit": 700 + i, "name": name, "kind": "train", "offset": i * 7.0, "oriented": True})
        movers += mock_vehicles.movers()
        # Another player's character (MOCK_PLAYERS), walking round near the start.
        movers.append({"unit": 900, "name": "character", "kind": "circle", "cx": -10.0, "cy": -6.0, "r": 4.0, "speed": 0.01, "phase": 0})
        for i in range(3):
            movers.append({"unit": 800 + i, "name": "logistic-robot", "kind": "shuttle", "ax": 8.5, "ay": -2.5 + 4 * i, "bx": 16.5, "by": 0.5, "phase": i * 40})
        return movers

    def mover_state(self, m):
        t = self.tick
        if m["kind"] == "drift":  # an asteroid passing the platform, north to south
            return m["x"], -60.0 + (m["phase"] + t * m["speed"]) % 120.0, 0.0
        if m["kind"] in ("parked", "spider"):
            return m["x"], m["y"], m["o"]
        if m["kind"] == "circle":
            a = m["phase"] + t * m["speed"]
            x, y = m["cx"] + math.cos(a) * m["r"], m["cy"] + math.sin(a) * m["r"]
            # moving counter-clockwise on screen: velocity direction gives the orientation
            vx, vy = -math.sin(a), math.cos(a)
            orientation = (math.atan2(vx, -vy) / (2 * math.pi)) % 1.0
            return x, y, orientation
        if m["kind"] == "train":
            span = 160.0
            p = (t * 0.15) % (2 * span)
            heading_east = p < span
            head = -80.0 + (p if heading_east else 2 * span - p)
            x = head - m["offset"] if heading_east else head + m["offset"]
            return x, -48.0, 0.25 if heading_east else 0.75
        p = ((t + m["phase"]) % 240) / 120.0
        f = p if p <= 1 else 2 - p
        return m["ax"] + (m["bx"] - m["ax"]) * f, m["ay"] + (m["by"] - m["ay"]) * f, 0.0

    def belt_items(self):
        """Items riding the starter belt south on both lanes, wrapping round at its end.
        An item that wraps gets a new id, like a new item put on the belt. Mined belt tiles
        lose their items. Returns [(unique id, item, x, y), ...]."""
        if not self.belt:
            return []
        length = len(self.belt)
        top = self.belt[0].y - 0.5
        out = []
        for lane, (dx, item) in enumerate(((0.25, self.belt_lanes[0]), (-0.25, self.belt_lanes[1]))):
            for i in range(length * 2):  # half-full lanes: 2 items per tile
                travelled = i * 0.5 + lane * 0.25 + self.tick * BELT_SPEED
                cycle, s = divmod(travelled, length)
                belt = self.belt[int(s)]
                if belt.key() not in self.entities:
                    continue
                name = "iron-gear-wheel" if i % 5 == 0 and item not in SPOILING else item
                out.append((lane * 10_000_000 + int(cycle) * length * 2 + i + 1, name, belt.x + dx, top + s))
        return out

    def send_far_belts(self):
        """belt_items.lua's far_tick: what each belt's two lanes carry (`bfar`), per subscribed chunk
        within far_r of the focus, when it changed."""
        fx, fy, _ = self.focus
        lanes = {}  # chunk -> [x, y, d, a, b, ...]
        counts = {}  # chunk -> [lane 1 count, lane 2 count, ...]: the starter belt is half full, the field full
        starter = [(b, IID[self.belt_lanes[1]], IID[self.belt_lanes[0]], 2) for b in self.belt]
        field = [(b, IID[BELT_FIELD_ITEMS[(c * 2) % len(BELT_FIELD_ITEMS)]], IID[BELT_FIELD_ITEMS[(c * 2 + 1) % len(BELT_FIELD_ITEMS)]], 4)
                 for c, column in enumerate(self.belt_field) for b in column]
        for belt, a, b, n in starter + field:
            if belt.key() not in self.entities:
                continue
            chunk = (math.floor(belt.x / 32), math.floor(belt.y / 32))
            if chunk not in self.subs or math.hypot(belt.x - fx, belt.y - fy) > self.far_r + 48:
                continue
            lanes.setdefault(chunk, []).extend([fixed(belt.x), fixed(belt.y), belt.dir, a, b])
            counts.setdefault(chunk, []).extend([n, n])
        sent = self.__dict__.setdefault("far_sent", {})
        for chunk in list(sent):
            if chunk not in self.subs:  # sent again when it comes back, as world.lua's subscribe
                del sent[chunk]
        for chunk in set(lanes) | set(sent):
            l = lanes.get(chunk, [])
            if sent.get(chunk) != l and chunk in self.subs:
                sent[chunk] = l
                self.send_now({"t": "bfar", "cx": chunk[0], "cy": chunk[1], "l": l, "c": counts.get(chunk, [])})

    def build_belt_field(self, cols, rows, x0=12, y0=-16):
        """Full belts side by side running south (--belt-field), every lane its own item."""
        add = lambda name, x, y: self.add(Entity(self._unit(), name, x, y, 8, {"s": "s"}))
        self.belt_field_rect = (x0 - 12, y0 - 12, x0 + cols + 12, y0 + rows + 12)
        self.belt_field = [[add("transport-belt", x0 + c + 0.5, y0 + r + 0.5) for r in range(rows)] for c in range(cols)]

    def build_busy_base(self, cols=60, rows=40, x0=-150, y0=40, robots=300):
        """--busy: a factory of about 20,000 entities south of the base for measuring the bridge's
        traffic (tools/net_cost.py). Each 5x6 cell is an assembler fed by an inserter from a belt
        and a pole; logistic robots shuttle across it. Belts here are empty: --belt-field fills."""
        add = lambda name, x, y, d=0, extra=None: self.add(Entity(self._unit(), name, x, y, d, extra))
        for c in range(cols):
            for r in range(rows):
                cx, cy = x0 + c * 5, y0 + r * 6
                add("assembling-machine-1", cx + 1.5, cy + 1.5)
                self.inserters.append((add("inserter", cx + 1.5, cy + 3.5, 0), "iron-plate"))
                for i in range(5):
                    add("transport-belt", cx + i + 0.5, cy + 4.5, 4, {"s": "s"})
                add("small-electric-pole", cx + 4.5, cy + 0.5)
        for i in range(robots):
            ax, ay = x0 + (i * 37) % (cols * 5), y0 + (i * 53) % (rows * 6)
            self.movers.append({"unit": self._unit(), "name": "logistic-robot", "kind": "shuttle", "ax": ax, "ay": ay,
                                "bx": ax + 20 - (i % 40), "by": ay - 30 + (i % 7) * 9, "phase": i * 13})

    def build_robot_swarm(self, count, cx=-3.0, cy=0.5):
        """--robots N: N robots flying round the start (the frame rate with many robots in view):
        logistic robots shuttling (carrying plates on the way out, `rc`), construction robots
        shuttling and one in twenty hovering in place, working."""
        for i in range(count):
            a = i * 2.39996  # the golden angle: an even spread
            r = 3.0 + 18.0 * math.sqrt((i + 0.5) / count)
            ax, ay = cx + math.cos(a) * r, cy + math.sin(a) * r * 0.7
            span = 4.0 + (i % 9)
            bx, by = ax + math.cos(a * 3.0) * span, ay + math.sin(a * 3.0) * span
            name = "logistic-robot" if i % 4 else "construction-robot"
            if i % 20 == 0:
                name, bx, by = "construction-robot", ax, ay
            self.movers.append({"unit": self._unit(), "name": name, "kind": "shuttle", "ax": ax, "ay": ay,
                                "bx": bx, "by": by, "phase": i * 13})

    def build_radar_outpost(self, x, y):
        """--radar: a radar at (x, y) and a row of assemblers on a belt running east past the edge of
        the 7 x 7 chunks it reveals, so the remote view shows covered and uncovered ground side by side."""
        add = lambda name, ax, ay, d=0, extra=None: self.add(Entity(self._unit(), name, ax, ay, d, extra))
        add("radar", math.floor(x) + 1.5, math.floor(y) + 1.5)
        edge = (math.floor(x / 32) + 4) * 32  # the first chunk east of the coverage
        for i in range(int(edge - x) - 40, int(edge - x) + 40, 4):
            add("assembling-machine-1", math.floor(x) + i + 1.5, math.floor(y) + 6.5)
            for k in range(4):
                add("transport-belt", math.floor(x) + i + k + 0.5, math.floor(y) + 9.5, 4, {"s": "s"})

    def lay_item_showcase(self, x0, y0, names, per_row=16, gap=0.6):
        """--item-showcase: one of every item in a grid on the ground, for looking at the item
        models (client/assets/models/items/) side by side."""
        for i, name in enumerate(names):
            self.ground.append([name, x0 + (i % per_row) * gap, y0 + (i // per_row) * gap])

    def _in_belt_field(self, tx, ty):
        r = self.belt_field_rect
        return r is not None and r[0] <= tx < r[2] and r[1] <= ty < r[3]

    def belt_field_items(self):
        out = []
        n = len(BELT_FIELD_ITEMS)
        for c, column in enumerate(self.belt_field):
            length = len(column)
            top = column[0].y - 0.5
            for lane, dx in enumerate((-0.25, 0.25)):
                item = BELT_FIELD_ITEMS[(c * 2 + lane) % n]
                base = 20_000_000 + (c * 2 + lane) * 1_000_000
                for i in range(length * 4):  # full lanes: 4 items per tile
                    cycle, s = divmod(i * 0.25 + self.tick * BELT_SPEED, length)
                    belt = column[int(s)]
                    if belt.key() in self.entities:
                        out.append((base + (int(cycle) * length * 4 + i) % 1_000_000, item, belt.x + dx, top + s))
        return out

    def inserter_hands(self):
        """Each inserter swings from the tile behind it to the tile in front (the way it
        faces), over its left side, carrying its item, then back empty. Returns
        [(unit, x, y, item or None), ...]."""
        out = []
        for e, item in self.inserters:
            if e.key() not in self.entities:
                continue
            a = e.dir / 16 * 2 * math.pi
            ux, uy = math.sin(a), -math.cos(a)  # towards the drop side
            vx, vy = uy, -ux  # 90 degrees to the left of it
            p = ((self.tick + e.unit * 7) % SWING_TICKS) / SWING_TICKS
            s = p * 2 if p < 0.5 else 2 - p * 2
            s = s * s * (3 - 2 * s)
            phi = math.pi * (1 - s)  # pi: over the pickup, 0: over the drop
            x = e.x + math.cos(phi) * ux + math.sin(phi) * vx
            y = e.y + math.cos(phi) * uy + math.sin(phi) * vy
            out.append((e.unit, x, y, item if p < 0.5 else None))
        return out

    def daytime(self):
        return (0.15 + self.tick / self.day_length) % 1.0

    # --- networking -----------------------------------------------------------------------

    def send_raw(self, msg):
        if self.client is None:
            return 0
        msg["k"] = self.tick
        data = json.dumps(msg, separators=(",", ":")).encode()
        addr = self.client["addr"]
        if self.client.get("b") and len(data) < BATCH_BYTES:
            # A client whose hello says b gets the tick's messages joined by newlines, like the mod's
            # transport.lua (sending a datagram costs Factorio about a millisecond).
            batch = self.batches.get(addr)
            if batch and batch[1] + len(data) + 1 > BATCH_BYTES:
                self.send_batch(addr)
                batch = None
            if batch is None:
                batch = self.batches[addr] = [[], 0]
            batch[0].append(data)
            batch[1] += len(data) + 1
            return len(data)
        self.send_batch(addr)
        if self.rng.random() >= self.drop:
            self.sock.sendto(data, addr)
        return len(data)

    def send_batch(self, addr):
        batch = self.batches.pop(addr, None)
        if batch and self.rng.random() >= self.drop:
            self.sock.sendto(b"\n".join(batch[0]), addr)

    def send_now(self, msg):
        self.send_raw(msg)

    def rate_period(self, job, interval, level=None):
        """Ticks between runs of `job` at the client's `rate` level, as rate.lua works it out."""
        tier, longest, _ = RATE_JOBS[job]
        over = (getattr(self, "rate", 0) if level is None else level) - tier + 1
        return interval if over <= 0 else max(interval, min(interval * 2 ** over, longest))

    def rate_due(self, job, interval):
        def on_ticks(level):
            p = self.rate_period(job, interval, level)
            return self.tick % p == (0 if p == interval else RATE_JOBS[job][2] % p)
        level = getattr(self, "rate", 0)
        old = getattr(self, "rate_from", 0)
        easing = job in RATE_EASE and old < level and self.tick < getattr(self, "rate_at", -10 ** 9) + RATE_EASE_TICKS
        return on_ticks(level) or (easing and on_ticks(old))

    def send_list(self, t, part, parts, l, width=None, extra=None):
        """One part of a bi, ih or mv update; delta-coded like the mod's transport.send_groups and
        send_records for a client whose hello says z: each number minus the same field of the
        record before it (flat groups of `width`, or a record's first four numbers)."""
        msg = {"t": t, "part": part, "parts": parts, **(extra or {})}
        if self.client and self.client.get("z"):
            msg["z"] = 1
            if width:
                l = l[:width] + [v - l[j] for j, v in enumerate(l[width:])]
            else:
                l = l[:1] + [[v - p[j] if j < 4 else v for j, v in enumerate(r)] for p, r in zip(l, l[1:])]
        msg["l"] = l
        self.send_now(msg)

    def send_reliable(self, msg):
        if self.client is None:
            return
        self.rseq += 1
        msg["r"] = self.rseq
        self.outbox.append(msg)

    def flush(self):
        sent = 0
        while self.outbox and sent < BYTES_PER_TICK:
            sent += self.send_raw(self.outbox.pop(0))

    def handshake(self):
        self.rseq, self.outbox = 0, []
        self.subs, self.queue = {}, []
        p = self.player
        self.send_reliable(self.surface_fields({"t": "welcome", "v": PROTOCOL, "mod": "mock", "u": p["unit"],
                                                "x": fixed(p["x"]), "y": fixed(p["y"]), "mp": True}))
        recs = []
        for name, etype, w, h, color in ENTITY_PROTOS:
            recs.append([EID[name], name, etype, -w / 2, -h / 2, w / 2, h / 2, *color, math.ceil(w), math.ceil(h)])
        self.send_parts("protos", recs)
        self.send_parts("tprotos", [[TID[name], name, *color] for name, color in TILE_PROTOS])
        self.send_parts("fprotos", [[FID[name], name, *color] for name, color in FLUID_PROTOS])
        if self.client and self.client.get("dc"):
            self.send_parts("dprotos", [[DID[name], name] for name in DECORATIVE_PROTOS])
        self.send_parts("iprotos", [[IID[name], name, PLACE_RESULT[name]] if name in PLACE_RESULT else [IID[name], name]
                                    for name in ITEM_PROTOS])
        self.send_reliable({"t": "ready"})
        self.send_reliable({"t": "eprops", "l": EPROPS})
        self.send_reliable({"t": "quals", "l": [["normal", 0, 1, "cccccc"], ["uncommon", 1, 1, "33e633"], ["rare", 2, 0, "1a66ff"],
                                                ["epic", 3, 0, "b23aff"], ["legendary", 5, 0, "ff7f00"]]})
        self.send_item_uses()
        self.inv_sig = None
        self.guns_sig = None
        self.screen = None
        self.send_reliable({"t": "recipes", "l": sorted(RECIPES)})
        self.slots_sig = self.craftable_sig = None
        self.send_slots()
        self.send_quickbar()
        self.send_recipe_details()
        self.send_techs()
        self.map_queue, self.tags_dirty, self.map_si = [], False, None
        self.send_char_logistics()
        self.send_reliable({"t": "ccol", "c": self.char_color})
        self.send_surfaces()
        self.send_planet()
        self.territories_due = True
        self.gear_sent = {}
        if self.die_after is not None:
            self.die_at, self.die_after = self.tick + self.die_after, None

    def send_parts(self, kind, records):
        parts = max(1, math.ceil(len(records) / RECORDS_PER_MESSAGE))
        for i in range(parts):
            self.send_reliable({"t": kind, "part": i + 1, "parts": parts,
                                "l": records[i * RECORDS_PER_MESSAGE:(i + 1) * RECORDS_PER_MESSAGE]})

    def snapshot(self, cx, cy):
        self.generate_chunk(cx, cy)
        rle, last, count = [], None, 0
        for ty in range(cy * CHUNK, cy * CHUNK + CHUNK):
            for tx in range(cx * CHUNK, cx * CHUNK + CHUNK):
                tid = TID[self.tile_at(tx, ty)]
                if tid == last:
                    count += 1
                else:
                    if last is not None:
                        rle += [last, count]
                    last, count = tid, 1
        rle += [last, count]
        records = [self.entities[k].record() for k in self.by_chunk.get((cx, cy), set())]
        parts = max(1, math.ceil(len(records) / ENTITIES_PER_MESSAGE))
        self.send_reliable({"t": "chunk", "cx": cx, "cy": cy, "tiles": rle, "parts": parts})
        for i in range(parts):
            self.send_reliable({"t": "ents", "cx": cx, "cy": cy, "part": i + 1, "parts": parts,
                                "e": records[i * ENTITIES_PER_MESSAGE:(i + 1) * ENTITIES_PER_MESSAGE]})
        if self.client and self.client.get("dc"):
            self.send_decoratives(cx, cy)

    def decoratives(self, cx, cy):
        """[id, x, y, amount, ...] for the chunk: a few per hundred tiles on Nauvis grass and dirt,
        none under entities, the same every time."""
        if self.surface != "nauvis":
            return []
        taken = set()
        for k in self.by_chunk.get((cx, cy), set()):
            e = self.entities[k]
            taken.add((math.floor(e.x), math.floor(e.y)))
        out = []
        for ly in range(CHUNK):
            for lx in range(CHUNK):
                x, y = cx * CHUNK + lx, cy * CHUNK + ly
                if (x, y) in taken or self.tile_at(x, y) not in ("grass-1", "grass-2", "dirt-1"):
                    continue
                if hash01(x, y, 31) < 0.06:
                    name = DECORATIVE_PROTOS[int(hash01(x, y, 32) * len(DECORATIVE_PROTOS))]
                    out += [DID[name], lx, ly, 1 + int(hash01(x, y, 33) * 3)]
        return out

    def send_decoratives(self, cx, cy):
        flat = self.decoratives(cx, cy)
        per = DECORATIVES_PER_MESSAGE * 4
        parts = max(1, math.ceil(len(flat) / per))
        for i in range(parts):
            self.send_reliable({"t": "dec", "cx": cx, "cy": cy, "part": i + 1, "parts": parts, "l": flat[i * per:(i + 1) * per]})

    def receive(self):
        while True:
            try:
                data, addr = self.sock.recvfrom(65536)
            except BlockingIOError:
                return
            except ConnectionResetError:
                continue  # Windows: an earlier send hit a closed port (client gone)
            if self.rng.random() < self.drop:
                continue
            try:
                msg = json.loads(data)
            except ValueError:
                continue
            if isinstance(msg, dict):
                self.on_message(msg, addr)

    def on_message(self, msg, addr):
        """Like the mod's session.on_packet, which runs each handler inside pcall: a command with
        fields of the wrong type answers with a "Bridge error" msg instead of stopping the mock."""
        if addr in self.extras:
            with self.serving(self.extras[addr]):
                return self.guarded(msg, addr)
        if msg.get("t") == "hello" and self.client is not None and self.client["addr"] != addr:
            return self.add_client(msg, addr)
        self.guarded(msg, addr)

    def guarded(self, msg, addr):
        try:
            self.handle_message(msg, addr)
        except (TypeError, ValueError, KeyError, IndexError, AttributeError, OverflowError) as e:
            print(f"error handling {str(msg.get('t'))[:40]!r}: {e!r}")
            if self.client is not None and self.client["addr"] == addr:
                self.send_now({"t": "msg", "text": f"Bridge error: {e}"[:300]})

    def handle_message(self, msg, addr):
        t = msg.get("t")
        if t == "hello":
            sid = str(msg.get("sid", ""))
            if self.client is None or self.client["sid"] != sid or self.client["addr"] != addr:
                print(f"client {addr[0]}:{addr[1]} connected (session {sid})")
                self.client = {"addr": addr, "sid": sid, "last_seen": self.tick, "handshake": self.tick, "resync": -1000,
                               "chat_at": self.tick + 240,
                               "z": msg.get("z") == 1, "dc": msg.get("dc") == 1, "b": msg.get("b") == 1}
                self.rate, self.rate_from, self.rate_at = 0, 0, -10 ** 9
                self.handshake()
            else:
                self.client["last_seen"] = self.tick
                self.client["z"] = msg.get("z") == 1
                self.client["b"] = msg.get("b") == 1
                if msg.get("dc") == 1 and not self.client.get("dc"):
                    self.client["dc"] = True
                    self.send_parts("dprotos", [[DID[name], name] for name in DECORATIVE_PROTOS])
                    self.queue = list(self.subs)
                elif msg.get("dc") != 1:
                    self.client["dc"] = False
                if msg.get("w") == 0 and self.tick - self.client["handshake"] > 120:
                    self.client["handshake"] = self.tick
                    self.handshake()
            return
        if self.client is None or self.client["addr"] != addr:
            return
        if t == "set_section" and int(msg.get("u", 0) or 0) == 0:
            self.char_section(msg)
            return
        if mock_machines.command(self, t, msg):
            return
        if mock_vehicles.command(self, t, msg):
            return
        if self.space.command(t, msg):
            return
        p = self.player
        if t == "bye":
            print("client said bye")
            self.client = None
        elif t == "sub":
            # Same rules as the mod: newly subscribed chunks are queued nearest first.
            wanted = [(int(c[0]), int(c[1])) for c in msg.get("c", []) if isinstance(c, list) and len(c) >= 2]
            old = self.subs
            self.subs = {c: True for c in wanted}
            self.queue = [c for c in self.queue if c in self.subs]
            for c in wanted:
                if c not in old and c not in self.queue:
                    self.queue.append(c)
        elif t == "focus":
            self.focus = (msg.get("x", 0) / 256, msg.get("y", 0) / 256, min(float(msg.get("r", 48)), 64.0))
            was = self.remote_view
            self.remote_view = msg.get("rv") == 1
            if self.remote_view and not was:
                self.send_view_coverage()
        elif t == "resync":
            if msg.get("full") != 1 and isinstance(msg.get("c"), list):
                for c in msg["c"]:
                    if isinstance(c, list) and len(c) >= 2:
                        c = (int(c[0]), int(c[1]))
                        if c in self.subs and c not in self.queue:
                            self.queue.append(c)
            elif self.tick - self.client["resync"] >= 120:
                self.client["resync"] = self.tick
                if msg.get("full") == 1:
                    self.handshake()
                else:
                    self.queue = list(self.subs)
        elif self.trip and t in ("walk", "mine", "build", "pickup", "enter", "ride"):
            if t != "walk":
                self.message("Not while flying")
        elif self.in_hub and t in ("walk", "mine", "pickup", "enter", "ride", "plat_board"):
            if t != "walk":
                self.message("Not from inside the hub")
        elif t == "ride":
            self.start_ride(msg)
        elif t == "walk" and p["vehicle"] is not None:
            pass  # the character sits in a car
        elif t == "walk":
            d, a = msg.get("d", -1), msg.get("a")
            if isinstance(a, (int, float)) and 0 <= a < 1000 and not (isinstance(d, (int, float)) and d < 0):
                # Any angle, stepped between its two 8-way neighbours as the mod does
                w = p["walk"]
                err = w[3] if w and len(w) > 2 and self.tick <= w[1] else 0.0
                p["walk"] = [w[0] if w else 0, self.tick + HOLD_TICKS, int(a), err]
            else:
                p["walk"] = (int(d) // 2 * 2 % 16, self.tick + HOLD_TICKS) if isinstance(d, (int, float)) and d >= 0 else None
        elif t == "mine":
            self.start_mining(msg)
        elif t == "mine_stop":
            p["mining"] = None
        elif t == "pickup":
            p["pickup"] = self.tick + HOLD_TICKS
        elif t == "enter":
            self.enter()
        elif t == "drive":
            a, steer = msg.get("a", 0), msg.get("s", 0)
            if a in (1, 2, 3) or steer in (-1, 1):
                p["drive"] = {"a": a if a in (1, 2, 3) else 0, "s": steer if steer in (-1, 1) else 0,
                              "until": self.tick + HOLD_TICKS}
            else:
                p["drive"] = None
        elif t == "build" and msg.get("sf") == 1:
            # Ctrl+Shift+click: a ghost, and trees and rocks in the way marked for deconstruction.
            name = PLACE_RESULT.get(str(msg.get("item", "")), str(msg.get("item", "")))
            if name in EID:
                rec = {"blueprint": {"entities": [{"name": name, "position": {"x": 0, "y": 0}, "direction": int(msg.get("d", 0))}]}}
                args = (rec, msg.get("x", 0) / 256, msg.get("y", 0) / 256, 0, True)
                self.record_history({"what": "blueprint", "ghosts": self.place_blueprint(*args), "redo": args})
        elif t == "build":
            self.build(msg)
        elif t == "rotate":
            target = self.find(msg)
            if target is not None and target.unit:
                target.dir = (target.dir + (12 if msg.get("rev") else 4)) % 16
                self.send_reliable({"t": "upd", "e": target.record()})
                self.record_history({"what": "rotation", "e": target, "rev": bool(msg.get("rev"))})
        elif t in ("bp_get", "bp_set", "bp_page", "bp_lib", "bp_rec", "bp_del", "undo", "redo"):
            self.library_command(t, msg)
        elif t == "craft":
            self.craft(str(msg.get("recipe", "")), int(msg.get("n", 1)))
        elif t == "shoot":
            m = msg.get("m", -1)
            if isinstance(m, int) and m >= 0:
                old = p["shoot"] or {"next": 0}
                p["shoot"] = {"selected": m == 1, "x": msg.get("x", 0) / 256, "y": msg.get("y", 0) / 256,
                              "until": self.tick + HOLD_TICKS, "next": old["next"], "warned": old.get("warned", False)}
            else:
                p["shoot"] = None
        elif t == "gun":
            i = int(msg.get("i", 0)) - 1
            if 0 <= i < len(p["guns"]) and p["guns"][i][0]:
                p["sel"] = i
        elif t == "open":
            self.open_screen(msg)
        elif t == "close":
            self.screen = None
        elif t == "map":
            self.request_map(msg)
        elif t == "cmd":
            # console.lua: the commands the bridge runs for its character; Lua never.
            words = str(msg.get("text", "")).lstrip("/").split()
            answers = {"version": ["2.1.23"], "seed": ["123456789"], "time": [f"{self.tick // 60} seconds"],
                       "players": ["Players (0):"], "admins": ["Admins (0):"],
                       "cheat": ["Researched every technology", "Cheat mode is a player's: the bridge's own character has none, so crafting still takes time"],
                       "f3d-status": ["[Zenith] the mock server"]}
            name = words[0] if words else ""
            reply = {"t": "cmdr", "id": int(msg.get("id", 0)), "l": answers.get(name, [])}
            if name not in answers:
                reply["ok"] = 0
            self.send_reliable(reply)
        elif t == "unghost":
            x, y = msg.get("x", 0) / 256, msg.get("y", 0) / 256
            hit = next((e for e in list(self.entities.values()) if e.type == "entity-ghost"
                        and e.box()[0] <= x <= e.box()[2] and e.box()[1] <= y <= e.box()[3]), None)
            if hit is not None:
                self.remove(hit)
            self.send_now({"t": "unghost", "q": int(msg.get("q", 0)), "n": 1 if hit is not None else 0})
        elif t == "hinfo":
            self.send_now(self.hover_info(msg))
        elif t == "view":
            # session.lua's view: the remote view looks at another surface. The mock moves its one
            # world there (and the character with it, unlike the mod) and back on si 0.
            si = int(msg.get("si", 0) or 0)
            names = {1: "nauvis", 2: "platform"} | {3 + i: n for i, n in enumerate(PLANETS)}
            name = names.get(si)
            viewing = getattr(self, "viewing_from", None)
            if name and name != (viewing or (self.surface,))[0] and si != self.surface_index():
                if viewing is None:
                    self.viewing_from = (self.surface, self.player["x"], self.player["y"])
                self.switch_surface(name, msg.get("x", 0) / 256, msg.get("y", 0) / 256, view=True)
            elif viewing is not None and (si == 0 or name == viewing[0]):
                self.viewing_from = None
                self.switch_surface(*viewing)
        elif t == "rate":
            level = msg.get("l")
            level = max(0, min(3, int(level))) if isinstance(level, (int, float)) else 0
            if level != getattr(self, "rate", 0):
                self.rate_from, self.rate_at = getattr(self, "rate", 0), self.tick
            self.rate = level
        elif t == "bfar":
            self.far_r = max(0, min(1024, int(msg.get("r", 0) or 0)))
            n = msg.get("n")
            self.near_r = max(0, min(96, int(n))) if isinstance(n, (int, float)) else None
        elif t == "budget":
            u = msg.get("u")
            if isinstance(u, (int, float)) and u == u:
                self.work_budget = max(WORK_BUDGET_FLOOR, min(WORK_BUDGET_CEILING, int(u)))
        elif t == "mtr":
            si = msg.get("si") if isinstance(msg.get("si"), int) else self.surface_index()
            cars = []
            if si == self.surface_index():
                for m in self.movers:
                    if m["kind"] == "train":
                        x, y, o = self.mover_state(m)
                        colour = 0xEB1200 if m["name"] == "locomotive" else 0x9A9A9A
                        cars += [round(x * 256), round(y * 256), round(o * 1000) % 1000, round(5.8 * 256), round(1.8 * 256), colour]
            # No radars in the mock: only the ground round the character is covered (cov empty).
            self.send_now({"t": "mtr", "si": si, "part": 1, "parts": 1, "l": cars, "cov": []})
        elif t == "mrp":
            # map.lua's roboport listing (H13): every roboport on the surface, in one part here.
            si = msg.get("si") if isinstance(msg.get("si"), int) else self.surface_index()
            ports = []
            if si == self.surface_index():
                for x, y, lr, cr in self.roboports():
                    ports += [fixed(x), fixed(y), fixed(lr), fixed(cr)]
            self.send_now({"t": "mrp", "si": si, "q": (int(msg["q"]) if isinstance(msg.get("q"), int) else 0), "part": 1, "last": 1, "l": ports})
        elif t == "lpad":
            # Where the map centres on switching to a planet (H23): its landing pad.
            si = msg.get("si") if isinstance(msg.get("si"), int) else 0
            out = {"t": "lpad", "si": si, "q": (int(msg["q"]) if isinstance(msg.get("q"), int) else 0)}
            if si == self.surface_index():
                ents = self.entities
            elif si == 1:
                ents = self.worlds.get("nauvis", {}).get("entities", {})
            else:
                ents = {}
            pads = sorted((e for e in ents.values() if e.type == "cargo-landing-pad"), key=lambda e: e.unit)
            if pads:
                out["x"], out["y"] = fixed(pads[0].x), fixed(pads[0].y)
            self.send_now(out)
        elif t == "tag_add":
            x, y = msg.get("x"), msg.get("y")
            si = msg.get("si") if msg.get("si") in self.surface_tags else self.surface_index()
            self.surface_tags.setdefault(si, [])
            if isinstance(x, (int, float)) and isinstance(y, (int, float)):
                if si == self.surface_index() and (math.floor(x / 256 / CHUNK), math.floor(y / 256 / CHUNK)) not in self.charted:
                    self.message("Can't put a tag there (not charted yet?)")
                else:
                    icon = msg.get("icon") if isinstance(msg.get("icon"), list) and len(msg["icon"]) == 2 else ["", ""]
                    self.next_tag += 1
                    self.surface_tags[si].append([self.next_tag, int(x), int(y), str(msg.get("text", "")), str(icon[0]), str(icon[1])])
                self.tags_dirty = True
        elif t == "tag_del":
            for si, tags in self.surface_tags.items():
                self.surface_tags[si] = [tag for tag in tags if tag[0] != msg.get("id")]
            self.tags_dirty = True
        elif t in ("set_requests", "set_storage_filter"):
            self.chest_command(t, msg)
        elif t == "set_char_color":
            c = msg.get("c")
            if isinstance(c, list) and len(c) >= 3:
                self.char_color = [max(0, min(255, int(v))) for v in c[:3]]
                self.send_reliable({"t": "ccol", "c": self.char_color})
        elif t == "set_char_requests":
            cl = self.char_logistics
            if isinstance(msg.get("l"), list):
                target = next((sec for sec in cl["sec"] if not sec["g"]), None)
                if target is None:
                    target = {"i": len(cl["sec"]) + 1, "g": "", "on": 1, "m": 1, "man": 1, "f": []}
                    cl["sec"].append(target)
                for sec in cl["sec"]:
                    sec["f"] = []
                target["f"] = [[r[0], "normal", int(r[1]), int(r[2]), "", -1] for r in msg["l"]
                               if isinstance(r, list) and len(r) >= 3 and r[0] in ITEM_PROTOS]
            for key in ("on", "trash"):
                if key in msg:
                    cl[key] = 1 if msg[key] in (1, True) else 0
            self.send_char_logistics()
        elif t == "land":
            pf = self.platform
            if self.trip:
                self.message("You're already on your way")
            elif self.surface in PLANETS or pf["loc"] not in PLANETS:
                self.message("Land from a platform that is stopped at a planet")
            else:
                self.message(f"Going down to {pf['loc']} in a cargo pod")
                self.in_hub = False
                p = self.player
                p.update(x=HUB_HATCH[0] - 2.0, y=0.0)
                self.trip = {"legs": RIDE_DOWN, "leg": 0, "t": 0, "up": True, "ground": (0.0, 0.0), "unit": self._unit(),
                             "to": pf["loc"], "land": (0.5, 0.5), "start": (p["x"], p["y"])}
        elif t in ("plat_go", "plat_sched", "plat_pause", "plat_board"):
            self.platform_command(t, msg)
        elif t in ("set_schedule", "train_go", "train_mode", "set_stop", "set_interrupts", "train_temp"):
            self.train_command(t, msg)
        elif t == "trains_list":
            self.send_train_list()
        elif t == "train_mode_id":
            if msg.get("id") == self.train["id"]:
                self.train["manual"] = msg.get("auto") not in (1, True)
                self.send_train_list()
            else:
                self.message("No such train")
        elif t in ("pedia_index", "pedia", "lnets", "lnet"):
            self.info_command(t, msg, (ENTITY_PROTOS, ITEM_PROTOS, FLUID_PROTOS, TILE_PROTOS, RECIPES, TECHS, PLANETS))
        elif t in ("drop", "fast", "paste_settings", "flip", "copy", "paste", "alt", "chat", "stats", "tile", "tile_mine", "throw", "rails"):
            self.world_control(t, msg)
        elif t == "bonuses":
            self.send_now({"t": "bonus", "l": [["inserter_stack_size_bonus", 1, ["inserter", "fast-inserter"]],
                                               ["mining_drill_productivity_bonus", 0.2, ["electric-mining-drill", "burner-mining-drill"]],
                                               ["ammo_damage:bullet", 0.8, ["firearm-magazine", "piercing-rounds-magazine"]],
                                               ["gun_speed:bullet", 1.1, ["firearm-magazine", "piercing-rounds-magazine"]],
                                               ["turret_attack:gun-turret", 0.4, ["gun-turret"]]]})
        elif t == "perms":
            self.send_now({"t": "perms", "me": "", "l": [["Default", ["Alice"]], ["Admin", []]]})
        elif t in ("set_inserter", "set_splitter", "set_bar", "set_switch", "set_panel", "set_cc", "set_color",
                   "set_speaker", "set_pump", "set_targets", "set_lamp", "set_desc"):
            self.entity_setting(t, msg)
        elif t in ("wire", "wire_clear"):
            self.wire_command(t, msg)
        elif t == "set_cb":
            sc = self.screen
            entity = self.entities.get(sc["unit"]) if sc and int(msg.get("u", 0)) == sc["unit"] else None
            m = self.machine(entity) if entity else None
            if m is None or "cb" not in m or not isinstance(msg.get("cb"), dict):
                self.message("That isn't a combinator")
            else:
                m["cb"] = msg["cb"]
                sc["due"] = self.tick
        elif t in ("set_recipe", "take", "put"):
            self.screen_command(t, msg)
        elif t == "modreq":
            self.module_request(msg)
        elif t == "move":
            self.move(msg)
        elif t == "xfer":
            self.xfer(msg)
        elif t in ("blueprint", "decon", "upgrade"):
            self.planner(t, msg)
        elif t in ("eq_put", "eq_take", "eq_move", "eq_toggle", "respawn"):
            self.gear_command(t, msg)
        elif t == "sort":
            if msg.get("inv", "main") == "main":
                self.layout = [None] * MAIN_SLOTS
                inv = self.player["inventory"]
                self.player["inventory"] = dict(sorted(inv.items()))
                self.send_slots()
        elif t == "inv_filter":
            i, item = int(msg.get("i", 0)), str(msg.get("item", ""))
            if 1 <= i <= MAIN_SLOTS:
                if item:
                    self.filters[i] = item
                else:
                    self.filters.pop(i, None)
                self.slots_sig = None
                self.send_slots()
        elif t in ("qb_set", "qb_sel", "qb_page"):
            self.quickbar_command(t, msg)
        elif t == "cancel_craft":
            self.cancel_craft(int(msg.get("i", 0)), int(msg.get("n", 1)))
        elif t == "research":
            name = str(msg.get("name", ""))
            if name not in TECHS or name in self.researched:
                self.message(f"Can't research {name}")
            elif self.research is None:
                self.research, self.research_progress = name, 0
            elif name != self.research and name not in self.research_queue:
                self.research_queue.append(name)
            self.send_research_status()
        elif t == "research_cancel":
            name = str(msg.get("name", ""))
            if name == self.research:
                self.research = self.research_queue.pop(0) if self.research_queue else None
                self.research_progress = 0
            elif name in self.research_queue:
                self.research_queue.remove(name)
            self.send_research_status()

    # --- the character --------------------------------------------------------------------

    def find(self, msg):
        unit = int(msg.get("u", 0))
        if unit:
            return self.entities.get(unit) or self.mover_entity(unit)
        return self.entities.get((int(msg.get("p", 0)), int(msg.get("x", 0)), int(msg.get("y", 0))))

    def message(self, text):
        self.send_now({"t": "msg", "text": text})

    def start_mining(self, msg):
        p = self.player
        target = self.find(msg)
        if target is None:
            p["mining"] = None
            return
        if p["mining"] and p["mining"]["entity"] is target:
            p["mining"]["until"] = self.tick + HOLD_TICKS
            return
        if math.hypot(target.x - p["x"], target.y - p["y"]) > (4.2 if target.type == "resource" else 11.5):
            self.message("Out of reach")
            return
        seconds = MINING_SECONDS.get(target.type, 0.5)
        p["mining"] = {"entity": target, "progress": 0, "time": int(seconds * TICKS_PER_SECOND), "until": self.tick + HOLD_TICKS}

    def finish_mining(self, target):
        inv = self.player["inventory"]
        if target.type == "resource":
            inv[target.name] = inv.get(target.name, 0) + 1
            target.extra["a"] -= 1
            if target.extra["a"] <= 0:
                self.remove(target)
                return False
            if self.watched(target):
                self.send_reliable({"t": "upd", "e": target.record()})
            return True
        item, count = ITEM_YIELD.get(target.type, (target.name, 1))
        inv[item] = inv.get(item, 0) + count
        self.remove(target)
        return False

    def build_demo(self, x, y):
        """--build-demo: tiles and a rail to look at near (x, y), as tiles.lua and the planner lay them."""
        x0, y0 = math.floor(x) - 9, math.floor(y) + 3
        for dy in range(4):
            for dx in range(5):
                self.tile_overrides[(x0 + dx, y0 + dy)] = "concrete"
            self.tile_overrides[(x0 + 5, y0 + dy)] = "hazard-concrete-left"
            self.tile_overrides[(x0 - 1, y0 + dy)] = "stone-path"
        for dy in range(3):
            for dx in range(3):
                self.add(Entity(self._unit(), "tile-ghost", x0 + 7.5 + dx, y0 + 0.5 + dy, 0, {"tg": TID["concrete"]}))
        rx, ry = math.floor((x + 8) / 2) * 2 + 1, math.floor((y + 6) / 2) * 2 + 1
        for k in range(3):
            self.add(Entity(self._unit(), "straight-rail", rx, ry + 2 * k, 0))

    def send_item_uses(self):
        """`iuse`: tiles, capsules, the rail planner and the belts' and pipes' undergrounds."""
        uses = []
        for item, (tile, other, water) in sorted(TILE_ITEMS.items()):
            on = sorted(TID[n] for n, _ in TILE_PROTOS if n != tile and (n in WATER_TILES) == water)
            uses.append([item, "t", tile, other, on])
        for item, (kind, rng, radius) in sorted(CAPSULES.items()):
            uses.append([item, "c", kind, rng, radius])
        uses += [["rail", "r", "rail-support", 1], ["transport-belt", "b", "underground-belt"],
                 ["fast-transport-belt", "b", "underground-belt"], ["pipe", "p", "pipe-to-ground"]]
        uses += [[item, "m", cat] for item, cat in sorted(MODULES.items())]
        self.send_reliable({"t": "iuse", "part": 1, "parts": 1, "l": uses})

    @staticmethod
    def brush(x, y, n):
        if n % 2:
            x0, y0 = math.floor(x) - (n - 1) // 2, math.floor(y) - (n - 1) // 2
        else:
            x0, y0 = math.floor(x + 0.5) - n // 2, math.floor(y + 0.5) - n // 2
        return [(x0 + dx, y0 + dy) for dy in range(n) for dx in range(n)]

    def place_tiles(self, msg):
        """Like tiles.lua: the item's tile under the brush where it may go, one item each; ghosts
        are tile-ghost entities. Tiles laid over a placed tile hand that one's item back."""
        item = str(msg.get("item", ""))
        if item not in TILE_ITEMS:
            return self.message(f"Can't place {item} as tiles")
        tile, other, water = TILE_ITEMS[item]
        if msg.get("r") == 1 and other:
            tile = other
        n = max(1, min(32, int(msg.get("n", 1))))
        inv, p = self.player["inventory"], self.player
        changed = []
        for tx, ty in self.brush(msg.get("x", 0) / 256, msg.get("y", 0) / 256, n):
            old = self.tile_at(tx, ty)
            if old == tile or (old in WATER_TILES) != water:
                continue
            if msg.get("ghost") == 1:
                self.add(Entity(self._unit(), "tile-ghost", tx + 0.5, ty + 0.5, 0, {"tg": TID[tile]}), announce=True)
                continue
            if inv.get(item, 0) < 1 or math.hypot(tx + 0.5 - p["x"], ty + 0.5 - p["y"]) > 11.5:
                continue
            inv[item] -= 1
            back = next((i for i, (t, o, _) in TILE_ITEMS.items() if old in (t, o)), None)
            if back:
                inv[back] = inv.get(back, 0) + 1
            self.tile_overrides[(tx, ty)] = tile
            changed.append((tx, ty))
        self.send_tile_changes(changed)

    def mine_tiles(self, msg):
        """Like tiles.lua: placed tiles under the brush back to the inventory, the ground back."""
        n = max(1, min(32, int(msg.get("n", 1))))
        inv, changed = self.player["inventory"], []
        for tx, ty in self.brush(msg.get("x", 0) / 256, msg.get("y", 0) / 256, n):
            for e in list(self.entities_at(tx + 0.5, ty + 0.5)):
                if e.type == "tile-ghost":
                    self.remove(e)
            tile = self.tile_overrides.get((tx, ty))
            back = next((i for i, (t, o, _) in TILE_ITEMS.items() if tile in (t, o)), None)
            if back:
                del self.tile_overrides[(tx, ty)]
                inv[back] = inv.get(back, 0) + 1
                changed.append((tx, ty))
        self.send_tile_changes(changed)

    def send_tile_changes(self, changed):
        if changed:
            flat = []
            for tx, ty in changed:
                flat += [tx, ty, TID[self.tile_at(tx, ty)]]
                for e in list(self.entities_at(tx + 0.5, ty + 0.5)):
                    if e.type == "tile-ghost" and e.extra.get("tg") == TID[self.tile_at(tx, ty)]:
                        self.remove(e, announce=False)  # robots don't say either
            self.send_reliable({"t": "tiles", "l": flat})

    def throw(self, msg):
        """Like capsules.lua: one of the item at the target if it is in range."""
        item = str(msg.get("item", ""))
        if item not in CAPSULES:
            return self.message(f"Can't use {item}")
        kind, rng, radius = CAPSULES[item]
        p, inv = self.player, self.player["inventory"]
        x, y = msg.get("x", 0) / 256, msg.get("y", 0) / 256
        if kind != "use-on-self" and math.hypot(x - p["x"], y - p["y"]) > rng + 0.5:
            return self.message("Out of range")
        if inv.get(item, 0) < 1:
            return self.message(f"You have no {item}")
        if kind == "destroy-cliffs":
            cliffs = [e for e in self.entities.values() if e.type == "cliff" and math.hypot(e.x - x, e.y - y) <= radius + 1]
            if not cliffs:
                return self.message("No cliff there")
            for e in cliffs:
                self.remove(e)
        inv[item] -= 1
        mock_shots.thrown(self, item, x, y)

    def build_rails(self, msg):
        """Like rail_planner.lua: the planner's pieces in order, from rails while they last and in
        reach, ghosts after that."""
        p, inv = self.player, self.player["inventory"]
        ghosts = 0
        for rec in msg.get("l", [])[:200]:
            name = str(rec[0])
            if name not in EID or not (name in RAIL_COST or name.startswith("elevated-") or name in ("rail-ramp", "rail-support")):
                return self.message("Can't build that with rail")
            x, y, d = rec[1] / 256, rec[2] / 256, int(rec[3]) % 16
            if any(e.name == name and e.dir == d for e in self.entities_at(x, y)):
                continue
            item = "rail-support" if name == "rail-support" else "rail-ramp" if name == "rail-ramp" else "rail"
            cost = 1 if item != "rail" else RAIL_COST.get(name.replace("elevated-", ""), 1)
            real = msg.get("ghost") != 1 and inv.get(item, 0) >= cost and math.hypot(x - p["x"], y - p["y"]) <= 11.5
            if real:
                inv[item] -= cost
                self.add(Entity(self._unit(), name, x, y, d), announce=True)
            else:
                ghosts += 1
                self.add(Entity(self._unit(), "entity-ghost", x, y, d, {"gh": EID[name]}), announce=True)
        if ghosts and msg.get("ghost") != 1:
            self.message(f"{ghosts} rail pieces placed as ghosts")

    def build(self, msg):
        """Like the mod: snapped to the grid (rails to the two-tile grid, centres on odd tiles),
        the same entity turned instead of built twice, and fast-replace within a group."""
        p, inv = self.player, self.player["inventory"]
        item = str(msg.get("item", ""))
        name = PLACE_RESULT.get(item, item)
        if name not in EID:
            return self.message(f"Can't build {item}")
        if inv.get(item, 0) < 1:
            return self.message(f"You have no {item}")
        d = int(msg.get("d", 0)) % 16
        w, h = ESIZE[name]
        tw, th = math.ceil(w), math.ceil(h)
        if d in (4, 12):
            tw, th = th, tw
        rail = ETYPE[name] == "straight-rail"
        if rail:
            snap = lambda v, n: math.floor(v / 2) * 2 + 1
        else:
            snap = lambda v, n: math.floor(v) + 0.5 if n % 2 else math.floor(v + 0.5)
        x, y = snap(msg.get("x", 0) / 256, tw), snap(msg.get("y", 0) / 256, th)
        if math.hypot(x - p["x"], y - p["y"]) > 11.5:
            return self.message("Out of reach")
        why = self.space.cant_build(self.surface not in PLANETS, name)
        if why:
            return self.message(why)
        new = Entity(self._unit(), name, x, y, d, {"s": "s"} if ETYPE[name] == "transport-belt" else None)
        if ETYPE[name] == "underground-belt":
            # The exit of the nearest one behind facing the same way when that is an entrance.
            new.extra["u"] = "i"
            bx, by = {0: (0, 1), 4: (-1, 0), 8: (0, -1), 12: (1, 0)}.get(d, (0, 0))
            for i in range(1, 6):
                behind = [e for e in self.entities_at(x + bx * i, y + by * i) if e.name == name and e.dir == d]
                if behind:
                    new.extra["u"] = "o" if behind[0].extra.get("u") == "i" else "i"
                    break
        ax1, ay1, ax2, ay2 = new.box()
        blocking = []
        for k in list(self.by_chunk.get((math.floor(x / CHUNK), math.floor(y / CHUNK)), set())):
            other = self.entities[k]
            if other.type == "entity-ghost" and (other.x, other.y) == (x, y):
                self.remove(other)  # building over a ghost fills it in
                continue
            if other.type in ("resource", "entity-ghost") or (other.type == "straight-rail") != rail:
                continue
            bx1, by1, bx2, by2 = other.box()
            if ax1 < bx2 - 0.01 and ax2 > bx1 + 0.01 and ay1 < by2 - 0.01 and ay2 > by1 + 0.01:
                blocking.append(other)
        if len(blocking) == 1 and (blocking[0].x, blocking[0].y) == (x, y):
            old = blocking[0]
            if old.name == name:
                if old.dir != d:
                    old.dir = d
                    self.send_reliable({"t": "upd", "e": old.record()})
                return
            if FAST_GROUP.get(old.name) and FAST_GROUP.get(old.name) == FAST_GROUP.get(name):
                self.remove(old)
                inv[old.name] = inv.get(old.name, 0) + 1
                blocking = []
        if blocking:
            return self.message("Can't place that there")
        inv[item] -= 1
        self.add(new, announce=True)

    def planner(self, t, msg):
        """blueprint: ghosts of BLUEPRINT at the cursor; decon / upgrade: mark (or unmark) an area."""
        i = int(msg.get("i", 0))
        slots = self.main_slots()
        item = slots[i - 1][0] if 1 <= i <= len(slots) and slots[i - 1] else ""
        if i == -1:
            item = PLANNER_ITEMS.get(bp_kind(bp_decode(self.lib_cursor or "")), "")
        if t == "blueprint":
            record = bp_decode(self.planner_string(i) or "")
            book = record.get("blueprint_book")
            if book:  # its active page
                pages = {p.get("index", 0): p for p in book.get("blueprints", [])}
                record = pages.get(book.get("active_index", 0), {})
            if "blueprint" not in record:
                return self.message("That isn't a blueprint")
            args = (record, msg.get("x", 0) / 256, msg.get("y", 0) / 256, int(msg.get("d", 0)) % 16, msg.get("sf") == 1,
                    msg.get("m") == 1)
            ghosts = self.place_blueprint(*args)
            if ghosts:
                self.record_history({"what": "blueprint", "ghosts": ghosts, "redo": args})
            return
        if t == "decon" and i != 0 and item != "deconstruction-planner":
            return self.message("That isn't a deconstruction planner")
        if t == "upgrade" and item != "upgrade-planner":
            return self.message("That isn't an upgrade planner")
        x1, x2 = sorted((msg.get("x1", 0) / 256, msg.get("x2", 0) / 256))
        y1, y2 = sorted((msg.get("y1", 0) / 256, msg.get("y2", 0) / 256))
        cancel = bool(msg.get("cancel"))
        # down: Factorio's right-drag downgrade, the mappings the other way round.
        mapping = {v: k for k, v in UPGRADES.items()} if msg.get("down") == 1 else UPGRADES
        if t == "decon" and not cancel:
            self.remove_ghosts(x1, y1, x2, y2)
        changed = []
        for e in list(self.entities.values()):
            if not (x1 <= e.x <= x2 and y1 <= e.y <= y2) or e.type in ("resource", "entity-ghost", "tile-ghost"):
                continue
            key = "d" if t == "decon" else "up"
            if t == "upgrade" and e.name not in mapping and not cancel:
                continue
            had = e.extra.get(key)
            if cancel:
                e.extra.pop(key, None)
            else:
                e.extra[key] = 1 if t == "decon" else EID[mapping[e.name]]
            if (had is not None) != (key in e.extra):
                changed.append((e, had if cancel else e.extra[key]))
                if self.watched(e):
                    self.send_reliable({"t": "upd", "e": e.record()})
        if changed:
            what = ("cancel " if cancel else "") + ("deconstruction" if t == "decon" else "upgrade")
            self.record_history({"what": what, "key": key, "cancel": cancel, "list": changed})

    def remove_ghosts(self, x1, y1, x2, y2):
        """Deconstructing an area deletes its ghosts at once, as Factorio does (tracker.deconstructing)."""
        for e in list(self.entities.values()):
            if e.type in ("entity-ghost", "tile-ghost") and x1 <= e.x <= x2 and y1 <= e.y <= y2:
                self.remove(e)

    # --- exchange strings, the blueprint library, undo (planners.lua, history.lua) -----------

    def planner_string(self, i):
        """The exchange string of the planner at slot i (-1: the library one in the cursor)."""
        if i == -1:
            return self.lib_cursor
        slots = self.main_slots()
        item = slots[i - 1][0] if 1 <= i <= len(slots) and slots[i - 1] else ""
        if item not in PLANNER_KEYS:
            return None
        return self.planner_data.get(i) or bp_encode(default_planner(item))

    def send_string(self, q, data, item, i, **extra):
        n = max(1, math.ceil(len(data) / BP_PART))
        for k in range(n):
            self.send_reliable({"t": "bp", "q": q, "part": k + 1, "parts": n, "s": data[k * BP_PART:(k + 1) * BP_PART],
                                "item": item, "i": i, **extra})

    def record_history(self, entry):
        self.next_hist += 1
        self.history[self.next_hist] = entry
        self.history.pop(self.next_hist - 100, None)
        self.send_reliable({"t": "hist", "h": self.next_hist, "what": entry["what"]})

    def place_blueprint(self, record, x, y, d, superforced=False, mirror=False):
        """A blueprint's entities as ghosts around (x, y), mirrored east-west with `mirror` (the
        mod's flip, without its rail and splitter cases), turned by d; returns them."""
        body = record.get("blueprint") or {}
        ents = [e for e in body.get("entities", []) if e.get("name") in EID]
        if not ents:
            return []
        cx = sum(e["position"]["x"] for e in ents) / len(ents)
        cy = sum(e["position"]["y"] for e in ents) / len(ents)
        made = []
        for e in ents:
            ox, oy = e["position"]["x"] - cx, e["position"]["y"] - cy
            ed = int(e.get("direction", 0))
            if mirror:
                ox, ed = -ox, (16 - ed) % 16
            for _ in range(d // 4):
                ox, oy = -oy, ox
            gx, gy = math.floor(x + ox) + 0.5, math.floor(y + oy) + 0.5
            if superforced:
                for other in list(self.entities_at(gx, gy)):
                    if other.type in ("tree", "simple-entity") and "d" not in other.extra:
                        other.extra["d"] = 1
                        self.send_reliable({"t": "upd", "e": other.record()})
            made.append(self.add(Entity(self._unit(), "entity-ghost", gx, gy, (ed + d) % 16,
                                        {"gh": EID[e["name"]]}), announce=True))
        return made

    def library_command(self, t, msg):
        q = int(msg.get("q", 0))
        if t == "bp_get":
            i = int(msg.get("i", 0))
            data = self.planner_string(i)
            if not data:
                return self.send_string(q, "", "", i, err="Nothing to export there")
            self.send_string(q, data, PLANNER_ITEMS[bp_kind(bp_decode(data))], i)
        elif t == "bp_set":
            if isinstance(msg.get("s"), str):
                data = msg["s"]
            else:
                up = self.bp_upload
                if up is None or up["id"] != msg.get("id"):
                    up = self.bp_upload = {"id": msg.get("id"), "parts": {}}
                up["parts"][int(msg.get("part", 0))] = str(msg.get("d", ""))
                if len(up["parts"]) < int(msg.get("parts", 1)):
                    return
                self.bp_upload = None
                data = "".join(up["parts"][k] for k in sorted(up["parts"]))
            record = bp_decode(data)
            kind = bp_kind(record)
            if not kind:
                return self.message("That isn't a blueprint string Factorio can import")
            item, i = PLANNER_ITEMS[kind], int(msg.get("i", 0))
            if i == -1:
                self.lib_cursor = data
            elif i == 0:
                inv = self.player["inventory"]
                taken = {k for k in self.planner_data}
                inv[item] = inv.get(item, 0) + 1
                slots = self.main_slots()
                i = next((k + 1 for k in range(len(slots) - 1, -1, -1) if slots[k] and slots[k][0] == item and k + 1 not in taken), 0)
                self.planner_data[i] = data
                self.send_slots()
            else:
                self.planner_data[i] = data
                self.send_slots()  # its icons (the mod notices within half a second)
            self.send_reliable({"t": "bp_ok", "q": q, "i": i, "item": item})
        elif t == "bp_del":
            # The planner window's delete button: the planner at slot i is destroyed.
            i = int(msg.get("i", 0))
            if i == -1:
                self.lib_cursor = None
                return
            slots = self.main_slots()
            item = slots[i - 1][0] if 1 <= i <= len(slots) and slots[i - 1] else ""
            if item in PLANNER_KEYS:
                self.layout[i - 1] = None
                inv = self.player["inventory"]
                inv[item] = inv.get(item, 0) - 1
                if inv[item] <= 0:
                    inv.pop(item)
                self.planner_data.pop(i, None)
                self.send_slots()
        elif t == "bp_page":
            i = int(msg.get("i", 0))
            data = self.planner_string(i)
            record = bp_decode(data) if data else {}
            if "blueprint_book" in record:
                record["blueprint_book"]["active_index"] = int(msg.get("a", 1)) - 1
                data = bp_encode(record)
                if i == -1:
                    self.lib_cursor = data
                else:
                    self.planner_data[i] = data
        elif t == "bp_lib":
            self.send_reliable({"t": "bpl", "src": "game", "who": "", "l": [
                [ix + 1, PLANNER_ITEMS[bp_kind(r)], r[bp_kind(r)].get("label", ""), [["item", "transport-belt"]]]
                for ix, r in enumerate(GAME_LIBRARY)]})
        elif t == "bp_rec":
            ix = int(msg.get("ix", 0))
            if msg.get("src") != "game" or not 1 <= ix <= len(GAME_LIBRARY):
                return self.send_string(q, "", "", 0, err="That record can't be read")
            data = bp_encode(GAME_LIBRARY[ix - 1])
            if msg.get("to") == -1:
                self.lib_cursor = data
                return self.send_reliable({"t": "bp_ok", "q": q, "i": -1, "item": PLANNER_ITEMS[bp_kind(GAME_LIBRARY[ix - 1])]})
            self.send_string(q, data, "", 0, src="game", ix=ix)
        elif t in ("undo", "redo"):
            entry = self.history.get(int(msg.get("h", 0)))
            if entry is None:
                return self.message("That can no longer be undone" if t == "undo" else "That can no longer be redone")
            back = t == "undo"
            if entry["what"] == "blueprint":
                if back:
                    for g in entry["ghosts"]:
                        if g.key() in self.entities:
                            self.remove(g)
                else:
                    entry["ghosts"] = self.place_blueprint(*entry["redo"])
            elif entry["what"] == "rotation":
                e = entry["e"]
                e.dir = (e.dir + (4 if entry["rev"] == back else 12)) % 16
                self.send_reliable({"t": "upd", "e": e.record()})
            else:
                key, add = entry["key"], entry["cancel"] == back
                for e, value in entry["list"]:
                    if add:
                        e.extra[key] = value
                    else:
                        e.extra.pop(key, None)
                    if self.watched(e):
                        self.send_reliable({"t": "upd", "e": e.record()})

    def enter(self):
        """Into the parked car if it is near, or out of it, two tiles to its side."""
        p = self.player
        car = p["vehicle"]
        if car is not None:
            p["vehicle"], p["drive"] = None, None
            p["x"], p["y"] = car["x"] + 2.0, car["y"]
            return
        cars = [m for m in self.movers if m["kind"] == "parked" and math.hypot(m["x"] - p["x"], m["y"] - p["y"]) <= ENTER_DISTANCE]
        if not cars:
            return self.message("No vehicle nearby")
        p["vehicle"], p["walk"] = cars[0], None

    def tick_cars(self):
        """The parked car drives while the client holds a key, and coasts to a stop."""
        p = self.player
        for m in self.movers:
            if m["kind"] != "parked":
                continue
            d = p["drive"] if p["vehicle"] is m else None
            if d and self.tick > d["until"]:
                p["drive"] = d = None
            v = m["speed"]
            a = d["a"] if d else 0
            if a == 1:
                v = min(CAR_MAX_SPEED, v + CAR_ACCELERATION)
            elif a == 3:
                v = max(-CAR_REVERSE_SPEED, v - CAR_ACCELERATION) if v <= 0 else max(0.0, v - CAR_BRAKE)
            elif a == 2:
                v = max(0.0, abs(v) - CAR_BRAKE) * (1 if v >= 0 else -1)
            else:
                v *= CAR_FRICTION
                if abs(v) < 0.001:
                    v = 0.0
            if d and d["s"]:
                m["o"] = (m["o"] + d["s"] * CAR_TURN * min(1.0, abs(v) / 0.1) * (1 if v >= 0 else -1)) % 1.0
            m["speed"] = v
            angle = m["o"] * 2 * math.pi
            m["x"] += math.sin(angle) * v
            m["y"] -= math.cos(angle) * v
        if p["vehicle"] is not None:
            p["x"], p["y"] = p["vehicle"]["x"], p["vehicle"]["y"]

    def craft(self, recipe, n):
        if recipe not in RECIPES:
            return self.message(f"Recipe not available: {recipe}")
        self.player["craft"] += [recipe] * max(1, min(n, 100))

    # --- machine screens --------------------------------------------------------------------

    def machine(self, entity):
        """The made-up insides of an entity, or None if it has no screen."""
        if entity.unit in self.machines:
            return self.machines[entity.unit]
        space = self.space.machine(entity)
        if space is not None:
            self.machines[entity.unit] = space
            return space
        kind = SCREEN_KINDS.get(entity.type, "other")
        m = {"recipe": None, "progress": 0, "inv": {}}
        if kind == "container":
            m["inv"] = {"chest": {"iron-plate": 50, "copper-plate": 30, "coal": 10}}
            m["bar"] = SLOT_SIZES["chest"]
        elif kind == "crafter":
            m["recipe"] = "iron-gear-wheel"
            m["inv"] = {"input": {"iron-plate": 40}, "output": {"iron-gear-wheel": 3}, "modules": {}}
        elif kind == "furnace":
            m["recipe"] = "iron-plate"
            m["inv"] = {"input": {"iron-ore": 12}, "output": {"iron-plate": 7}, "fuel": {"coal": 4}}
        elif kind == "lab":
            m["inv"] = {"input": {"automation-science-pack": 6}, "modules": {}}
        elif kind == "combinator":
            if entity.type == "constant-combinator":
                m["cb"] = {"enabled": True, "signals": [["item", "iron-plate", 10]],
                           "sections": [{"g": "", "on": 1, "m": 1, "s": [["item", "iron-plate", 10]]}]}
            elif entity.type == "decider-combinator":
                m["cb"] = {"conditions": [{"first_signal": {"type": "item", "name": "iron-plate"}, "comparator": ">", "constant": 5,
                                           "first_signal_networks": {"red": True, "green": True}}],
                           "outputs": [{"signal": {"type": "virtual", "name": "signal-A"}, "copy_count_from_input": False, "constant": 1}]}
            elif entity.type == "selector-combinator":
                m["cb"] = {"operation": "select", "select_max": True, "index_constant": 0}
            else:
                m["cb"] = {"first_signal": {"type": "item", "name": "iron-plate"}, "second_constant": 2, "operation": "*",
                           "output_signal": {"type": "item", "name": "iron-plate"}}
            m["desc"] = ""
        elif kind == "roboport":
            m["inv"] = {"robots": {"logistic-robot": 3}, "repair": {}}
            m["lg"] = {"mode": "roboport"}
        elif kind == "train":
            m["inv"] = {"fuel": {"coal": 20}} if entity.type == "locomotive" else {"cargo": {"iron-plate": 400}}
            if entity.type == "locomotive":
                m["col"] = [242, 120, 0]
                m["bu"] = 640
            else:
                m["bar"] = SLOT_SIZES["cargo"]
        elif kind == "stop":
            m["stop"] = {"name": entity.extra.get("n", ""), "limit": -1, "pri": 50, "train": 0,
                         "cb": {"wired": 0, "en": 0, "send": 1, "read": 0, "stopped": 0, "limit": 0, "count": 0, "pri": 0}}
        elif kind == "inserter":
            n = 5 if entity.name in FAST_INSERTERS else 0
            m["ins"] = {"n": n, "f": [""] * n, "st": 0, "max": 3, "h": ["iron-plate", 1]}
            if entity.name == "burner-inserter":
                m["inv"] = {"fuel": {"coal": 2}}
                m["bu"] = 450
            if n:
                m["ins"].update({"use": 0, "m": "whitelist"})
        elif kind == "splitter":
            m["spl"] = {"i": "none", "o": "none", "f": ""}
        elif kind == "turret":
            # The second turret (east) has run out, for the alerts (`al`, no_ammo).
            m["inv"] = {"turret_ammo": {"firearm-magazine": 10} if entity.x < 30 else {}}
        elif kind == "vehicle":
            m["inv"] = {"fuel": {"coal": 5}, "trunk": {"iron-plate": 20}, "car_ammo": {}}
            m["guns"] = ["vehicle-machine-gun"]
            m["bu"] = 800
        elif kind == "pole":
            pass
        elif entity.name in ("burner-mining-drill", "boiler"):
            m["inv"] = {"fuel": {"coal": 5}}
        elif entity.type in ("lamp", "pump", "programmable-speaker", "display-panel", "power-switch", "transport-belt",
                             "pipe", "pipe-to-ground", "heat-pipe", "land-mine", "storage-tank"):
            pass
        else:
            return None
        self.circuit_defaults(entity, m)
        if entity.name in LOGISTIC_MODES:
            mode = LOGISTIC_MODES[entity.name]
            m["lg"] = {"mode": mode, **({"requests": []} if mode == "requester" else {"filter": ""})}
            m["inv"] = {"chest": {"iron-plate": 120, "copper-plate": 60}} if mode == "storage" else {"chest": {}, "trash": {}}
            if mode == "requester":  # its request sections and settings (machine_info.lua's lc)
                m["sec"] = [{"i": 1, "g": "", "on": 1, "m": 1, "man": 1, "f": [["iron-plate", "", 100, -1, "", -1]]}]
                m["tu"], m["rb"] = 0, 0
        self.machines[entity.unit] = m
        return m

    def circuit_defaults(self, entity, m):
        """The settings circuit_settings.lua and entity_ui.lua add for this entity's type."""
        if entity.type in CC_DEFAULTS and "cc" not in m:
            o, fields = CC_DEFAULTS[entity.type]
            m["cc"] = {"o": o, "f": json.loads(json.dumps(fields))}
        if entity.type in ("lamp", "train-stop") and "col" not in m:
            m["col"] = [255, 255, 255] if entity.type == "lamp" else [242, 0, 0]
        if entity.type == "lamp":
            m.setdefault("ao", 0)
        if entity.type == "pump":
            m.setdefault("pf", "")
        if entity.type == "programmable-speaker":
            m.setdefault("spk", {"vol": 1.0, "mode": "local", "poly": 0, "vctl": 0, "vsig": {}, "inst": 0, "note": 0,
                                 "pitch": 0, "stop": 0, "al": {"show": 0, "map": 1, "icon": {}, "msg": ""},
                                 "il": SPEAKER_INSTRUMENTS})
        if entity.type == "display-panel":
            m.setdefault("dp", {"text": "", "icon": {}, "show": 0, "chart": 0, "msgs": []})
        if entity.type == "power-switch":
            m.setdefault("sw", 0)
        if entity.type == "ammo-turret":
            m.setdefault("tgt", {"l": [], "ign": 0})

    def circuit_networks(self, entity):
        """Network ids for the entity's red and green wires: the smallest unit on that network."""
        ids = {}
        for wire in ("r", "g"):
            if not entity.extra.get(wire):
                continue
            seen, todo = set(), [entity.unit]
            while todo:
                u = todo.pop()
                if u in seen:
                    continue
                seen.add(u)
                e = self.entities.get(u)
                if e is not None:
                    todo += e.extra.get(wire, [])
            ids[wire] = min(seen)
        return ids

    def wire_command(self, t, msg):
        """wire / wire_clear (wiring.lua): connect or disconnect two ends, or a pole's cables."""
        kind = msg.get("k")
        if t == "wire_clear":
            pole = self.find(msg)
            if pole is None or pole.type != "electric-pole":
                return self.message("Only electric poles have cables to remove")
            for u in list(pole.extra.get("w", [])):
                other = self.entities.get(u)
                if other is not None:
                    other.extra["w"] = [v for v in other.extra.get("w", []) if v != pole.unit]
                    self.send_reliable({"t": "upd", "e": other.record()})
            pole.extra.pop("w", None)
            self.send_reliable({"t": "upd", "e": pole.record()})
            return
        a = self.find(msg.get("a") or {}) if isinstance(msg.get("a"), dict) else None
        b = self.find(msg.get("b") or {}) if isinstance(msg.get("b"), dict) else None
        if kind not in ("r", "g", "w") or a is None or b is None or not a.unit or not b.unit:
            return self.message("Nothing to wire there")
        if not (self.in_reach(a) and self.in_reach(b)):
            return self.message("Out of reach")
        if kind == "w" and not all(e.type in ("electric-pole", "power-switch") for e in (a, b)):
            return self.message("Copper wire connects electric poles and power switches")
        if kind != "w" and not all(e.type in CC_DEFAULTS or SCREEN_KINDS.get(e.type) == "combinator"
                                   or e.type in ("electric-pole", "display-panel") for e in (a, b)):
            return self.message("That can't take a circuit wire")
        if a is b:
            return self.message("That can't take a circuit wire")
        if math.hypot(a.x - b.x, a.y - b.y) > (7.5 if kind == "w" else 10):
            return self.message("Wire can't reach that far")
        if b.unit in a.extra.get(kind, []) or a.unit in b.extra.get(kind, []):
            for x, y in ((a, b), (b, a)):
                x.extra[kind] = [u for u in x.extra.get(kind, []) if u != y.unit]
                if not x.extra[kind]:
                    del x.extra[kind]
        else:
            a.extra.setdefault(kind, []).append(b.unit)
            b.extra.setdefault(kind, []).append(a.unit)
        for e in (a, b):
            self.send_reliable({"t": "upd", "e": e.record()})
        if self.screen:
            self.screen["due"] = self.tick

    def in_reach(self, entity):
        x1, y1, x2, y2 = entity.box()
        p = self.player
        dx = max(x1 - p["x"], 0, p["x"] - x2)
        dy = max(y1 - p["y"], 0, p["y"] - y2)
        return math.hypot(dx, dy) <= REACH

    def radars(self):
        """[cx, cy, d, ...] for the radars in the mock's world (each reveals 3 chunks round its own)."""
        out = []
        for e in self.entities.values():
            if e.type == "radar":
                out += [math.floor(e.x / 32), math.floor(e.y / 32), 3]
        return out

    def roboports(self):
        """[(x, y, logistic radius, construction radius), ...] for the roboports in the mock's world."""
        return [(e.x, e.y, 25, 55) for e in self.entities.values() if e.type == "roboport"]

    def roboport_sees(self, cx, cy):
        """map.lua's roboport_sees: the chunk's centre in a roboport's construction area (H13)."""
        x, y = cx * 32 + 16, cy * 32 + 16
        return any(abs(x - rx) <= cr and abs(y - ry) <= cr for rx, ry, _, cr in self.roboports())

    def view_seen(self, x, y):
        """map.lua's view_filter: what the 3D remote view shows moving things in."""
        if not self.remote_view:
            return True
        cx, cy = math.floor(x / 32), math.floor(y / 32)
        if math.hypot(cx * 32 + 16 - self.player["x"], cy * 32 + 16 - self.player["y"]) <= 96 + 16:
            return True
        r = self.radars()
        if any(abs(cx - r[i]) <= r[i + 2] and abs(cy - r[i + 1]) <= r[i + 2] for i in range(0, len(r), 3)):
            return True
        return self.roboport_sees(cx, cy)

    def send_view_coverage(self):
        """`cov`, as map.lua sends it about once a second while the 3D remote view is on."""
        self.send_now({"t": "cov", "si": self.surface_index(), "l": self.radars(),
                       "x": fixed(self.player["x"]), "y": fixed(self.player["y"]), "cr": 96})

    def covered(self, entity):
        """map.lua's covered: the ground round the character (96 tiles), radars' and roboports' chunks."""
        if math.hypot(entity.x - self.player["x"], entity.y - self.player["y"]) <= 96:
            return True
        cx, cy = math.floor(entity.x / 32), math.floor(entity.y / 32)
        r = self.radars()
        if any(abs(cx - r[i]) <= r[i + 2] and abs(cy - r[i + 1]) <= r[i + 2] for i in range(0, len(r), 3)):
            return True
        return self.roboport_sees(cx, cy)

    def open_screen(self, msg):
        target = self.find(msg)
        if target is not None and target.type == "cargo-bay":  # a bay opens its hub's window, as in Factorio
            target = self.entities.get(self.platform.get("hub") or 0) or target
        if target is not None and target.type in NO_WINDOW:
            return  # entity_ui.lua: Factorio opens nothing for these
        if target is None or not target.unit or self.machine(target) is None:
            return self.message("Nothing to open there")
        remote = False
        if not self.in_reach(target):
            if not (msg.get("rv") and self.covered(target)):
                return self.message("Not in radar or roboport coverage" if msg.get("rv") else "Out of reach")
            remote = True  # from the remote view: settings only
        self.screen = {"unit": target.unit, "sent": 0, "due": self.tick, "remote": remote}

    def close_screen(self, why=None):
        unit = self.screen["unit"]
        self.screen = None
        if why:
            self.message(why)
        self.send_now({"t": "gui", "u": unit, "closed": True})

    def give(self, item, count):
        inv = self.player["inventory"]
        inv[item] = inv.get(item, 0) + count

    def module_request(self, msg):
        """`modreq`: a module asked for in a module slot (the mod's item request proxy or ghost's
        insert plan), shown in the screen's `mrq`. Within reach the module goes straight in."""
        entity = self.entities.get(int(msg.get("u", 0)))
        m = self.machine(entity) if entity else None
        if m is None or "modules" not in m["inv"]:
            return self.message("That has no module slots")
        n = SLOT_SIZES["modules"]
        mrq = m.setdefault("mrq", [""] * n)
        slot = int(msg["s"]) - 1 if "s" in msg else None
        if msg.get("clr") == 1:
            for i in range(n):
                if slot is None or i == slot:
                    mrq[i] = ""
        else:
            item = str(msg.get("item", ""))
            if item not in MODULES:
                return self.message("That isn't a module")
            inv = self.player["inventory"]
            if slot is None and self.in_reach(entity) and inv.get(item, 0) > 0 and sum(m["inv"]["modules"].values()) < n:
                inv[item] -= 1
                m["inv"]["modules"][item] = m["inv"]["modules"].get(item, 0) + 1
            else:
                free = [i for i in range(n) if not mrq[i] and i >= sum(m["inv"]["modules"].values())]
                at = slot if slot is not None else (free[0] if free else None)
                if at is None:
                    return self.message("The module slots are full")
                mrq[at] = item
                self.message("Module requested: %d of %d slots" % (sum(1 for r in mrq if r), n))
        if self.screen and self.screen["unit"] == entity.unit:
            self.screen["due"] = self.tick

    def screen_command(self, t, msg):
        sc = self.screen
        entity = self.entities.get(sc["unit"]) if sc else None
        if entity is None or int(msg.get("u", 0)) != sc["unit"]:
            return
        if not self.in_reach(entity):
            if not (sc.get("remote") and self.covered(entity)):
                return self.close_screen("Out of reach")
            if t in ("take", "put"):
                return self.message("Out of reach")
        sc["due"] = self.tick
        m, kind, inv = self.machine(entity), SCREEN_KINDS.get(entity.type, "other"), self.player["inventory"]
        item, n = str(msg.get("item", "")), max(1, int(msg.get("n", 1)))
        if t == "set_recipe":
            recipe = str(msg.get("recipe", ""))
            if kind != "crafter":
                return self.message("This machine's recipe can't be changed")
            if m.get("fixed_recipe"):
                return self.message("This machine's recipe can't be changed")
            if recipe and recipe not in MACHINE_RECIPES:
                return self.message(f"Can't make {recipe} here")
            for role in ("input", "output"):
                for k, v in m["inv"][role].items():
                    self.give(k, v)
                m["inv"][role] = {}
            m["recipe"], m["progress"] = recipe or None, 0
        elif t == "take":
            for role, contents in m["inv"].items():
                if msg.get("inv") in (None, role) and contents.get(item, 0) > 0 and n > 0:
                    moved = min(n, contents[item])
                    contents[item] -= moved
                    if not contents[item]:
                        del contents[item]
                    self.give(item, moved)
                    n -= moved
        elif t == "put":
            moved = min(n, inv.get(item, 0))
            role = None
            if kind == "container":
                role = "chest"
            elif item in FUELS and "fuel" in m["inv"]:
                role = "fuel"
            elif kind == "furnace" and item in SMELTING:
                role = "input"
            elif kind == "crafter" and m["recipe"] and item in MACHINE_RECIPES[m["recipe"]][0]:
                role = "input"
            elif kind == "lab" and item.endswith("science-pack"):
                role = "input"
            if not moved or role is None:
                return self.message(f"Can't put {item} in there")
            inv[item] -= moved
            m["inv"][role][item] = m["inv"][role].get(item, 0) + moved
        self.send_inventory()

    def run_machine(self, m, kind):
        """Crafts the open machine's recipe while it has what it needs."""
        if m.get("gallery"):
            return  # the gallery's machines stay as they were made (mock_machines.py)
        inp, out = m["inv"].get("input", {}), m["inv"].get("output", {})
        if kind == "crafter" and m["recipe"]:
            needs, (product, count) = MACHINE_RECIPES[m["recipe"]]
        elif kind == "furnace":
            ore = next((k for k in inp if k in SMELTING and inp[k] > 0), None)
            fuel = m["inv"]["fuel"]
            if ore is None or not any(fuel.values()):
                return
            needs, (product, count) = {ore: 1}, (SMELTING[ore], 1)
            m["recipe"] = product
        else:
            return
        if not all(inp.get(k, 0) >= v for k, v in needs.items()):
            return
        m["progress"] += 1
        if m["progress"] >= CRAFT_TICKS:
            m["progress"] = 0
            for k, v in needs.items():
                inp[k] -= v
                if not inp[k]:
                    del inp[k]
            out[product] = out.get(product, 0) + count
            if kind == "furnace" and self.rng.random() < 0.25:
                fuel = m["inv"]["fuel"]
                k = next(k for k in fuel if fuel[k] > 0)
                fuel[k] -= 1
                if not fuel[k]:
                    del fuel[k]

    def tick_screen(self):
        sc = self.screen
        if sc is None:
            return
        entity = self.entities.get(sc["unit"]) or self.mover_entity(sc["unit"])
        if entity is None:
            return self.close_screen()
        m, kind = self.machine(entity), SCREEN_KINDS.get(entity.type, "other")
        self.run_machine(m, kind)
        if self.tick < sc["due"]:
            return
        if not self.in_reach(entity) and not (sc.get("remote") and self.covered(entity)):
            return self.close_screen("Out of reach")
        sc["due"] = self.tick + SCREEN_INTERVAL
        msg = {"t": "gui", "u": entity.unit, "p": EID[entity.name], "kind": kind,
               "inv": {role: [[k, v] for k, v in contents.items() if v > 0] for role, contents in m["inv"].items()},
               "slots": {role: fill_slots(contents, m.get("sizes", {}).get(role) or mock_machines.slot_count(m, role, SLOT_SIZES.get(role, 4), entity.type))
                         for role, contents in m["inv"].items()}}
        msg["status"] = "low_power" if entity is self.low_power and self.low_power_now() else "working"
        if "cb" in m:
            msg["cb"] = m["cb"]
        for field in ("ins", "spl", "bar", "col", "pf", "spk", "dp", "sw", "tgt", "ao", "bu", "guns", "desc", "veh", "art", "pl"):
            if field in m:
                msg[field] = m[field]
        if any(m.get("mrq", [])):
            msg["mrq"] = m["mrq"]
        if sc.get("remote") and not self.in_reach(entity):
            msg["far"] = 1
        if "cc" in m:
            nets = self.circuit_networks(entity)
            msg["cc"] = {"o": m["cc"]["o"], "w": 1 if nets else 0, "nets": {"r": nets.get("r", 0), "g": nets.get("g", 0)},
                         "f": m["cc"]["f"]}
            if "connect_to_logistic_network" in m["cc"]["f"]:
                msg["cc"]["ln"] = 1 if self.roboport is not None and abs(entity.x - self.roboport.x) <= LOGISTIC_REACH                     and abs(entity.y - self.roboport.y) <= LOGISTIC_REACH else 0
        if "lg" in m:
            msg["lg"] = dict(m["lg"], net=self.network_summary(True))
        if kind == "train":
            msg["tr"] = self.train_info()
        elif kind == "stop":
            # The mock's one train has every stop in its schedule; it heads for the current one.
            tr = self.train_info()
            here = tr["dest"] == m["stop"]["name"] and not self.train["manual"]
            msg["stop"] = dict(m["stop"], count=1 if here else 0, trs=[[tr["id"], tr["state"], 1 if here else 0, TRAIN_UNITS[0]]])
        # What a wired constant combinator puts on the entity's red network (and the network ids).
        nets = self.circuit_networks(entity)
        if nets:
            red = []
            for u in entity.extra.get("r", []):
                src = self.entities.get(u)
                if src is not None and src.type == "constant-combinator" and self.machine(src)["cb"].get("enabled", True):
                    red += [list(x[:3]) for x in self.machine(src)["cb"]["signals"]]
            msg["sig"] = {"r": red, "g": []}
            for wire in ("r", "g"):
                if wire in nets:
                    msg["sig"][wire + "i"] = nets[wire]
        if kind == "crafter":
            msg["pw"] = 400 if msg["status"] == "low_power" else 1000
        if entity.unit in self.fluids:
            msg["fb"] = [[name, amount, cap, temp] for name, amount, cap, temp in self.fluids[entity.unit]]
        if kind in ("crafter", "furnace"):
            if m["recipe"]:
                msg["recipe"] = m["recipe"]
            msg["pr"] = int(m["progress"] * 1000 / CRAFT_TICKS)
        if kind == "crafter" and sc["sent"] % RECIPE_LIST_EVERY == 0:
            msg["rl"] = list(MACHINE_RECIPES)
        extra = self.space.gui_fields(entity, m, kind)
        quality_slot = extra.pop("quality_slot", None)
        if quality_slot and isinstance(msg["slots"].get(quality_slot[0], [0])[quality_slot[1]], list):
            msg["slots"][quality_slot[0]][quality_slot[1]] = msg["slots"][quality_slot[0]][quality_slot[1]][:2] + [quality_slot[2]]
        msg.update(extra)
        mock_machines.fill(msg, entity, m, kind, MACHINE_RECIPES, SMELTING, "rl" in msg or sc["sent"] % RECIPE_LIST_EVERY == 0)
        sc["sent"] += 1
        self.send_now(msg)

    # --- Factorio's world controls and entity windows (ui_actions.lua, entity_ui.lua) --------

    def world_control(self, t, msg):
        p, inv = self.player, self.player["inventory"]
        if t == "drop":
            item = str(msg.get("item", ""))
            if inv.get(item, 0) < 1:
                return self.message(f"You have no {item}")
            x, y = msg.get("x", 0) / 256, msg.get("y", 0) / 256
            if math.hypot(x - p["x"], y - p["y"]) > 10.5:
                return self.message("Out of reach")
            inv[item] -= 1
            self.ground.append([item, x, y])
            self.send_inventory()
        elif t == "fast":
            target = self.find(msg)
            m = self.machine(target) if target is not None and target.unit else None
            if m is None:
                return
            if not self.in_reach(target):
                return self.message("Out of reach")
            item = msg.get("item")
            half = msg.get("half") == 1
            if item:
                n = min(inv.get(item, 0), int(msg.get("n", 0)) or stack_size(item))
                n = math.ceil(n / 2) if half else n
                role = "chest" if "chest" in m["inv"] else ("fuel" if item in FUELS and "fuel" in m["inv"] else "input")
                if n <= 0 or role not in m["inv"]:
                    return self.message(f"Can't put {item} in there")
                inv[item] -= n
                m["inv"][role][item] = m["inv"][role].get(item, 0) + n
            else:
                for role in ("output", "chest"):
                    for k, v in list(m["inv"].get(role, {}).items()):
                        n = math.ceil(v / 2) if half else v
                        m["inv"][role][k] = v - n
                        if not m["inv"][role][k]:
                            del m["inv"][role][k]
                        self.give(k, n)
            self.send_inventory()
            if self.screen:
                self.screen["due"] = self.tick
        elif t == "paste_settings":
            f = msg.get("f")
            source = self.find({"u": f[0], "p": f[1], "x": f[2], "y": f[3]}) if isinstance(f, list) and len(f) == 4 else None
            target = self.find(msg)
            if source is None or target is None:
                return self.message("Nothing to paste to")
            ms, mt = self.machine(source), self.machine(target)
            if ms is not None and mt is not None and SCREEN_KINDS.get(source.type) == SCREEN_KINDS.get(target.type) == "crafter":
                mt["recipe"], mt["progress"] = ms["recipe"], 0
            self.message("Settings pasted")
        elif t == "flip":
            target = self.find(msg)
            if target is not None:
                if msg.get("v") == 1:  # the mock has no mirroring; a vertical flip still turns it
                    target.dir = (target.dir + 8) % 16
                self.send_reliable({"t": "upd", "e": target.record()})
        elif t == "copy":
            x1, x2 = sorted((msg.get("x1", 0) / 256, msg.get("x2", 0) / 256))
            y1, y2 = sorted((msg.get("y1", 0) / 256, msg.get("y2", 0) / 256))
            cx, cy = (x1 + x2) / 2, (y1 + y2) / 2
            found = [e for e in self.entities.values() if e.unit and x1 <= e.x <= x2 and y1 <= e.y <= y2
                     and e.type not in ("resource", "tree", "simple-entity", "entity-ghost", "unit-spawner")]
            if msg.get("cut") == 1:  # the mock doesn't copy ghosts, but cutting still deletes them
                self.remove_ghosts(x1, y1, x2, y2)
            if not found:
                self.send_now({"t": "clip", "l": []})
                return self.message("Nothing to copy there")
            to = int(msg.get("to", 0))
            if msg.get("bp") == 1 and to != 0:
                # Select new contents: into that blueprint, its name kept.
                old = bp_decode(self.planner_string(to) or "")
                if "blueprint" not in old:
                    return self.message("That isn't a blueprint")
                body = {"item": "blueprint", "version": GAME_VERSION,
                        "entities": [{"entity_number": n + 1, "name": e.name, "position": {"x": e.x - cx, "y": e.y - cy},
                                      "direction": e.dir} for n, e in enumerate(found)]}
                for k in ("label", "description", "icons"):
                    if k in old["blueprint"]:
                        body[k] = old["blueprint"][k]
                data = bp_encode({"blueprint": body})
                if to == -1:
                    self.lib_cursor = data
                else:
                    self.planner_data[to] = data
                self.send_reliable({"t": "bp_ok", "q": 0, "i": to, "item": "blueprint", "new": 1})
                return self.message("Blueprint contents replaced")
            if msg.get("bp") == 1:
                inv["blueprint"] = inv.get("blueprint", 0) + 1
                self.send_inventory()
                return self.message("Blueprint added to the inventory")
            # Around the middle of the footprints, as the mod sends it (ui_actions.send_clip).
            boxes = [e.box() for e in found]
            mx = (min(b[0] for b in boxes) + max(b[2] for b in boxes)) / 2
            my = (min(b[1] for b in boxes) + max(b[3] for b in boxes)) / 2
            self.clipboard = [[EID[e.name], fixed(e.x - mx), fixed(e.y - my), e.dir] for e in found]
            self.send_now({"t": "clip", "l": self.clipboard})
            if msg.get("cut") == 1:
                for e in found:
                    e.extra["d"] = 1
                    self.send_reliable({"t": "upd", "e": e.record()})
        elif t == "paste":
            if not self.clipboard:
                return self.message("The clipboard is empty")
            x, y, d = msg.get("x", 0) / 256, msg.get("y", 0) / 256, int(msg.get("d", 0)) % 16
            turned = []
            for pid, dx, dy, ed in self.clipboard:
                ox, oy = dx / 256, dy / 256
                for _ in range(d // 4):
                    ox, oy = -oy, ox
                turned.append((pid, ox, oy, (ed + d) % 16))
            # Moved as little as puts the first entity on the tile grid, as Factorio pastes.
            pid, ox, oy, ed = turned[0]
            w, h = ESIZE[ENTITY_PROTOS[pid - 1][0]]
            if ed % 8 == 4:
                w, h = h, w
            snap = lambda v, size: math.floor(v) + 0.5 if size % 2 == 1 else math.floor(v + 0.5)
            x, y = snap(x + ox, w) - ox, snap(y + oy, h) - oy
            for pid, ox, oy, ed in turned:
                ghost = Entity(self._unit(), "entity-ghost", x + ox, y + oy, ed, {"gh": pid})
                self.add(ghost, announce=True)
        elif t == "alt":
            self.alt = msg.get("on") == 1
        elif t == "chat":
            text = str(msg.get("text", ""))[:500]
            if text:
                print(f"chat: {text}")
                self.send_now({"t": "chat", "from": "3D", "text": text})
        elif t == "tile":
            self.place_tiles(msg)
        elif t == "tile_mine":
            self.mine_tiles(msg)
        elif t == "throw":
            self.throw(msg)
        elif t == "rails":
            self.build_rails(msg)
        elif t == "stats":
            kind = msg.get("kind") if msg.get("kind") in STATS else "item"
            prec = max(1, min(9, int(msg.get("prec", 2)))) if isinstance(msg.get("prec"), int) else 2
            scale = [1, 1, 1.1, 0.9, 1.2, 1.0, 0.8, 1.0, 1.0][prec - 1]
            rows = [[r[0], round(r[1] * scale, 2), round(r[2] * scale, 2), r[3], r[4]] for r in STATS[kind]]
            if prec == 9:  # "All": the rows by all-time totals
                rows.sort(key=lambda r: -max(r[3], r[4]))
            extra = self.stats_extra(kind, msg, rows, self.surface_index())
            if kind == "electric":
                # flow_last_tick in joules per tick: met, demand, used, available, stored, capacity
                demand = sum(r[1] for r in rows) / 60 / 60
                avail = sum(r[2] for r in rows) / 60 / 60
                extra["ef"] = [round(min(demand, avail), 2), round(demand, 2), round(min(demand, avail), 2),
                               round(avail, 2), 2500000.0, 5000000.0]
            self.send_now(dict({"t": "stats", "kind": kind, "prec": prec, "l": rows}, **extra))

    def entity_setting(self, t, msg):
        sc = self.screen
        entity = (self.entities.get(sc["unit"]) or self.mover_entity(sc["unit"])) if sc and int(msg.get("u", 0)) == sc["unit"] else None
        m = self.machine(entity) if entity else None
        if m is None:
            return
        sc["due"] = self.tick
        if t == "set_inserter":
            if "ins" not in m:
                return self.message("That isn't an inserter")
            ins = m["ins"]
            if isinstance(msg.get("f"), list) and ins["n"]:
                ins["f"] = [str(v) if isinstance(v, str) and v in IID else "" for v in (msg["f"] + [""] * ins["n"])[:ins["n"]]]
            if msg.get("m") in ("whitelist", "blacklist") and ins["n"]:
                ins["m"] = msg["m"]
            if msg.get("use") in (0, 1) and ins["n"]:
                ins["use"] = msg["use"]
            if msg.get("sp") in ("none", "fresh-first", "spoiled-first"):
                ins["sp"] = msg["sp"]
            if isinstance(msg.get("st"), int):
                ins["st"] = max(0, msg["st"])
        elif t == "set_splitter":
            if "spl" not in m:
                return self.message("That isn't a splitter")
            for k in ("i", "o"):
                if msg.get(k) in ("left", "none", "right"):
                    m["spl"][k] = msg[k]
            if isinstance(msg.get("f"), str):
                m["spl"]["f"] = msg["f"] if msg["f"] in IID else ""
        elif t == "set_bar":
            if "bar" not in m:
                return self.message("This chest has no limit")
            size = SLOT_SIZES["cargo" if "cargo" in m["inv"] else "chest"]
            m["bar"] = max(1, min(size, int(msg.get("n", size))))
        elif t == "set_lamp":
            if "ao" not in m:
                return self.message("That isn't a lamp")
            m["ao"] = 1 if msg.get("ao") == 1 else 0
        elif t == "set_desc":
            if "desc" not in m:
                return self.message("That isn't a combinator")
            m["desc"] = str(msg.get("text", ""))[:2000]
        elif t == "set_switch":
            if "sw" not in m:
                return self.message("That isn't a power switch")
            m["sw"] = 1 if msg.get("on") == 1 else 0
        elif t == "set_panel":
            if "dp" not in m:
                return self.message("That isn't a display panel")
            dp = m["dp"]
            if isinstance(msg.get("text"), str):
                dp["text"] = msg["text"][:500]
            if isinstance(msg.get("icon"), dict):
                dp["icon"] = msg["icon"]
            for k in ("show", "chart"):
                if msg.get(k) in (0, 1):
                    dp[k] = msg[k]
            if isinstance(msg.get("msgs"), list):
                dp["msgs"] = [{"text": str(r.get("text", ""))[:500], "icon": r.get("icon") if isinstance(r.get("icon"), dict) else {},
                               "cond": r.get("cond") if isinstance(r.get("cond"), dict) else dict(COND)}
                              for r in msg["msgs"] if isinstance(r, dict)]
        elif t == "set_cc":
            if "cc" not in m or not isinstance(msg.get("f"), dict):
                return self.message("Can't set that: No circuit settings here")
            for k, v in msg["f"].items():
                if k in m["cc"]["f"]:
                    m["cc"]["f"][k] = v
        elif t == "set_color":
            if "col" not in m or not (isinstance(msg.get("c"), list) and len(msg["c"]) == 3):
                return self.message("That has no colour to set")
            m["col"] = [max(0, min(255, int(v))) for v in msg["c"]]
        elif t == "set_pump":
            if "pf" not in m:
                return self.message("That isn't a pump")
            m["pf"] = msg.get("f") if msg.get("f") in FID else ""
        elif t == "set_targets":
            if "tgt" not in m:
                return self.message("That isn't a turret")
            if isinstance(msg.get("l"), list):
                m["tgt"]["l"] = [n for n in msg["l"] if n in EID]
            if msg.get("ign") in (0, 1):
                m["tgt"]["ign"] = msg["ign"]
        elif t == "set_speaker":
            if "spk" not in m:
                return self.message("That isn't a programmable speaker")
            spk = m["spk"]
            for k in ("poly", "vctl", "pitch", "stop"):
                if msg.get(k) in (0, 1):
                    spk[k] = msg[k]
            if isinstance(msg.get("vol"), (int, float)):
                spk["vol"] = max(0.0, min(1.0, float(msg["vol"])))
            if msg.get("mode") in ("local", "surface", "global"):
                spk["mode"] = msg["mode"]
            if isinstance(msg.get("vsig"), dict):
                spk["vsig"] = msg["vsig"]
            if isinstance(msg.get("inst"), int) and 0 <= msg["inst"] < len(SPEAKER_INSTRUMENTS):
                if spk["inst"] != msg["inst"]:
                    spk["note"] = 0
                spk["inst"] = msg["inst"]
            if isinstance(msg.get("note"), int) and 0 <= msg["note"] < len(SPEAKER_INSTRUMENTS[spk["inst"]][1]):
                spk["note"] = msg["note"]
            if isinstance(msg.get("al"), dict):
                for k in ("show", "map"):
                    if msg["al"].get(k) in (0, 1):
                        spk["al"][k] = msg["al"][k]
                if isinstance(msg["al"].get("icon"), dict):
                    spk["al"]["icon"] = msg["al"]["icon"]
                if isinstance(msg["al"].get("msg"), str):
                    spk["al"]["msg"] = msg["al"]["msg"][:200]

    def tick_alt(self):
        if not self.alt or self.tick % ALT_INTERVAL:
            return
        fx, fy, fr = self.focus
        icons = []
        for e in self.entities.values():
            if e.unit and abs(e.x - fx) <= fr and abs(e.y - fy) <= fr:
                m = self.machines.get(e.unit)
                kind = SCREEN_KINDS.get(e.type)
                if kind in ("crafter", "furnace"):
                    # Unopened machines have the recipe their screen will show; one whose recipe was
                    # cleared shows nothing, like the mod.
                    recipe = m["recipe"] if m is not None else ("iron-gear-wheel" if kind == "crafter" else "iron-plate")
                    if recipe:
                        icons.append([e.unit, "recipe", recipe])
                elif kind == "inserter" and m and m["ins"]["n"] and any(m["ins"]["f"]):
                    names = [f for f in m["ins"]["f"] if f]
                    icons.append([e.unit, "item", names[0]] + ([names[1:]] if len(names) > 1 else []))
                elif kind == "splitter" and m and m["spl"]["f"]:
                    icons.append([e.unit, "item", m["spl"]["f"]])
        self.send_now({"t": "ai", "l": icons[:400]})

    # --- the UI data ------------------------------------------------------------------------

    def main_slots(self):
        """The main inventory slot by slot. The rest of the mock adds and removes totals in
        player["inventory"]; this keeps the layout the client arranged and fits changes into it."""
        inv, layout = self.player["inventory"], self.layout
        for i in range(len(layout) - 1, -1, -1):  # too much of something: take from the last stacks
            slot = layout[i]
            if slot:
                extra = sum(s[1] for s in layout if s and s[0] == slot[0]) - inv.get(slot[0], 0)
                if extra > 0:
                    slot[1] -= min(extra, slot[1])
                    if slot[1] == 0:
                        layout[i] = None
        for item, total in inv.items():  # too little: top up stacks, then fill empty slots
            missing = total - sum(s[1] for s in layout if s and s[0] == item)
            for i, slot in enumerate(layout):
                if missing > 0 and slot and slot[0] == item:
                    n = min(missing, stack_size(item) - slot[1])
                    slot[1], missing = slot[1] + n, missing - n
            for i, slot in enumerate(layout):
                if missing > 0 and slot is None:
                    n = min(missing, stack_size(item))
                    layout[i], missing = [item, n], missing - n
        return layout

    def planner_icons(self, slots):
        """The icons of the planners in the main inventory, as the mod's `ic` (inventory.lua)."""
        out = []
        for i, s in enumerate(slots, 1):
            if not s or s[0] not in PLANNER_ITEMS.values() or i not in self.planner_data:
                continue
            record = bp_decode(self.planner_data[i]) or {}
            body = next(iter(record.values()), {}) if record else {}
            icons = body.get("icons") or (body.get("settings") or {}).get("icons") or []
            icons = sorted((ic for ic in icons if isinstance(ic, dict) and "signal" in ic), key=lambda ic: ic.get("index", 0))
            if icons:
                out.append([i, [[ic["signal"].get("type", "item"), ic["signal"]["name"]] for ic in icons]])
        return out

    def send_slots(self):
        slots = [list(s) if s else 0 for s in self.main_slots()]
        filters = [[i, item] for i, item in sorted(self.filters.items())]
        icons = self.planner_icons(slots)
        sig = json.dumps([slots, filters, icons])
        if sig != self.slots_sig:
            self.slots_sig = sig
            msg = {"t": "slots", "l": {"main": slots, "armor": [[ARMOR, 1] if ARMOR else 0]}}
            if filters:
                msg["fl"] = filters
            if icons:
                msg["ic"] = icons
            self.send_reliable(msg)

    def move(self, msg):
        """Like the mod's move: main to main by slot; to and from the open machine by totals."""
        inv, layout = self.player["inventory"], self.main_slots()
        src_role, dst_role = str(msg.get("from", "")), str(msg.get("to", ""))
        fi, ti, n = int(msg.get("fi", 0)) - 1, int(msg.get("ti", 0)) - 1, int(msg.get("n", 0))
        machine = None
        if "main" not in (src_role, dst_role):
            return
        if src_role != "main" or dst_role != "main":
            sc = self.screen
            entity = self.entities.get(sc["unit"]) if sc and int(msg.get("u", 0)) == sc["unit"] else None
            machine = self.machine(entity) if entity else None
            role = dst_role if src_role == "main" else src_role
            if machine is None or role not in machine["inv"]:
                return
        if src_role == "main":
            if not (0 <= fi < MAIN_SLOTS) or layout[fi] is None:
                return
            item, count = layout[fi]
            n = count if n <= 0 or n > count else n
            if machine is None:
                if not 0 <= ti < MAIN_SLOTS or fi == ti:
                    return
                dst = layout[ti]
                if dst is None or dst[0] == item:
                    moved = min(n, stack_size(item) - (dst[1] if dst else 0))
                    layout[ti] = [item, (dst[1] if dst else 0) + moved]
                    layout[fi][1] -= moved
                    if layout[fi][1] == 0:
                        layout[fi] = None
                elif n == count:
                    layout[fi], layout[ti] = layout[ti], layout[fi]
            else:
                contents = machine["inv"][dst_role]
                contents[item] = contents.get(item, 0) + n
                inv[item] -= n
                layout[fi][1] -= n
                if layout[fi][1] == 0:
                    layout[fi] = None
        else:
            shown = fill_slots(machine["inv"][src_role], SLOT_SIZES.get(src_role, 4))
            if not (0 <= fi < len(shown)) or shown[fi] == 0 or not 0 <= ti < MAIN_SLOTS:
                return
            item, count = shown[fi]
            n = count if n <= 0 or n > count else n
            contents = machine["inv"][src_role]
            contents[item] -= n
            if not contents[item]:
                del contents[item]
            inv[item] = inv.get(item, 0) + n
            if layout[ti] is None:
                layout[ti] = [item, n]
            if self.screen:
                self.screen["due"] = self.tick
        self.send_slots()
        self.send_inventory()

    def xfer(self, msg):
        """Like the mod's xfer (Shift / Ctrl clicks): between the main inventory and the open
        machine, by totals through take and put. Without a machine the mock has no gun or ammo
        slots to send things to."""
        kind, role, fi = str(msg.get("k", "")), str(msg.get("from", "")), int(msg.get("fi", 0)) - 1
        if kind not in ("stack", "half", "all", "allhalf") or not self.screen or "u" not in msg:
            return
        half = kind in ("half", "allhalf")
        if role == "main":
            layout = self.main_slots()
            if not 0 <= fi < MAIN_SLOTS:
                return
            first = layout[fi]
            stacks = [layout[fi]] if kind in ("stack", "half") else [s for s in layout if s and (first is None or s[0] == first[0])]
            for st in [s for s in stacks if s]:
                n = max(1, st[1] // 2) if half else st[1]
                self.screen_command("put", {"u": msg["u"], "item": st[0], "n": n})
        else:
            entity = self.entities.get(self.screen["unit"])
            m = self.machine(entity) if entity is not None else None
            if m is None or role not in m["inv"]:
                return
            shown = fill_slots(m["inv"][role], SLOT_SIZES.get(role, 4))
            if not 0 <= fi < len(shown):
                return
            first = shown[fi] or None
            stacks = [shown[fi]] if kind in ("stack", "half") else [s for s in shown if s and (first is None or s[0] == first[0])]
            for st in [s for s in stacks if s]:
                n = max(1, st[1] // 2) if half else st[1]
                self.screen_command("take", {"u": msg["u"], "inv": role, "item": st[0], "n": n})
        self.send_slots()
        self.send_inventory()

    def quickbar_command(self, t, msg):
        qb = self.quickbar
        if t == "qb_set":
            i, item = int(msg.get("i", 0)), str(msg.get("item", ""))
            if not 1 <= i <= QUICKBAR_SIZE or (item and item not in IID):
                return
            qb["items"][i - 1] = item
        elif t == "qb_sel" and 0 <= int(msg.get("i", -1)) <= QUICKBAR_SIZE:
            qb["sel"] = int(msg["i"])
        elif t == "qb_page" and 1 <= int(msg.get("p", 0)) <= QUICKBAR_SIZE // 10:
            qb["page"] = int(msg["p"])
        else:
            return
        self.send_quickbar()

    def send_quickbar(self):
        qb = self.quickbar
        held = qb["items"][qb["sel"] - 1] if qb["sel"] else ""
        self.send_reliable({"t": "qb", "p": qb["page"], "sel": qb["sel"], "held": held, "l": list(qb["items"])})

    def send_recipe_details(self):
        recs = []
        for name in sorted(RECIPES):
            needs, (product, count) = RECIPES[name]
            group, gorder, sub, sorder = RECIPE_GROUPS.get(name, ("intermediate-products", "d", "intermediate-product", "a"))
            recs.append([name, 0.5, ["crafting"], group, gorder, sub, sorder, "a[%s]" % name,
                         [["item", k, v] for k, v in needs.items()], [["item", product, count]]])
        self.send_parts("rdet", recs)

    def send_craftable(self):
        inv = self.player["inventory"]
        counts = [[name, min(inv.get(k, 0) // v for k, v in needs.items())] for name, (needs, _) in sorted(RECIPES.items())]
        counts = [c for c in counts if c[1] > 0]
        sig = json.dumps(counts)
        if sig != self.craftable_sig:
            self.craftable_sig = sig
            self.send_reliable({"t": "craftable", "l": counts})

    def craft_queue(self):
        """[[index, recipe, count, 0], ...]: runs of the same recipe in the queue."""
        runs = []
        for recipe in self.player["craft"]:
            if runs and runs[-1][1] == recipe:
                runs[-1][2] += 1
            else:
                runs.append([len(runs) + 1, recipe, 1, 0])
        return runs

    def cancel_craft(self, index, n):
        queue, start = self.player["craft"], 0
        for i, recipe, count, _ in self.craft_queue():
            if i == index:
                del queue[start:start + min(n, count)]
                break
            start += count
        self.send_queue(force=True)

    def send_queue(self, force=False):
        runs = self.craft_queue()
        if runs or self.queue_sent or force:
            self.queue_sent = bool(runs)
            self.send_now({"t": "cq", "pr": int((self.tick % 30) * 1000 / 30) if runs else 0, "l": runs})

    def send_techs(self):
        recs = []
        for name, (pre, ings, count, seconds) in sorted(TECHS.items()):
            state = 2 if name in self.researched else 1 if all(p in self.researched for p in pre) else 0
            extra = TECH_EXTRAS.get(name, [[], 1, 1, [], 0, ""])
            recs.append([name, "a-" + name, pre, ings, count, seconds, state, extra[3][0] if extra[3] else ""] + extra
                        + [1 if name in ESSENTIAL else 0])
        self.send_parts("techs", recs)

    def send_research_status(self):
        labs = [[e.unit, "working" if self.research else "no_research_in_progress"]
                for e in self.entities.values() if e.type == "lab" and self.watched(e)]
        self.send_now({"t": "rs", "cur": self.research or "", "pr": int(self.research_progress * 1000 / RESEARCH_TICKS),
                       "q": list(self.research_queue), "labs": labs})

    def tick_ui(self):
        if self.research:
            self.research_progress += 1
            if self.research_progress >= RESEARCH_TICKS:
                self.researched.add(self.research)
                self.send_now({"t": "msg", "text": f"Research completed: {self.research}", "tech": self.research, "unlocks": []})
                self.research = self.research_queue.pop(0) if self.research_queue else None
                self.research_progress = 0
                self.send_techs()
                self.send_research_status()
        if self.tick % UI_INTERVAL == 0:
            self.send_slots()
            self.send_craftable()
        if self.tick % 10 == 0:
            self.send_queue()
        if self.tick % 60 == 0:
            self.send_research_status()

    def send_inventory(self):
        items = [[k, v] for k, v in self.player["inventory"].items() if v > 0]
        sig = json.dumps(items)
        if sig != self.inv_sig:
            self.inv_sig = sig
            self.send_reliable({"t": "inv", "l": items})

    def start_ride(self, msg):
        """`ride` {u, to}: into the rocket of the silo the client has open (the mock has none, so the
        silo stands where the character is), up to the platform's hub."""
        pf, p = self.platform, self.player
        if msg.get("to") != pf["i"]:
            self.message("No such platform")
        elif self.surface not in PLANETS or pf["loc"] != self.surface:
            self.message("That platform isn't in orbit here")
        else:
            ground = (p["x"] + 6.0, p["y"])
            p.update(x=ground[0], y=ground[1] - 4.8, walk=None, mining=None)
            self.trip = {"legs": RIDE_UP, "leg": 0, "t": 0, "up": True, "ground": ground, "unit": self._unit(),
                         "to": PLATFORM_SURFACE, "land": HUB_HATCH, "start": (p["x"], p["y"])}
            self.send_now({"t": "rk", "u": 0, "x": fixed(ground[0]), "y": fixed(ground[1]), "s": self.surface})

    def step_trip(self):
        """Moves the riding character along its pod's track; changes surface halfway."""
        tr, p = self.trip, self.player
        state, ticks = tr["legs"][tr["leg"]]
        tr["t"] += 1
        f = min(1.0, tr["t"] / ticks)
        gx, gy = tr["ground"]
        if state == "ascending":
            climb = (RIDE_CLIMB if tr["legs"] is RIDE_UP else POD_CLIMB) * f * f
            p["x"], p["y"] = tr["start"][0] - (0.0 if tr["legs"] is RIDE_UP else 60.0 * f * f), tr["start"][1] - climb
        elif state == "descending":
            drop = (HUB_DROP if tr["legs"] is RIDE_UP else POD_DROP) * (1 - f) ** 2
            lx, ly = tr["land"]
            p["x"], p["y"] = lx - 40.0 * (1 - f) ** 2, ly - drop
        if tr["t"] < ticks:
            return
        tr["leg"] += 1
        tr["t"] = 0
        if tr["leg"] >= len(tr["legs"]):
            self.trip = None
            if tr["legs"] is RIDE_UP:
                self.in_hub = True
                p.update(x=0.0, y=0.0)
            else:
                p.update(x=tr["land"][0], y=tr["land"][1])
            return
        if tr["legs"][tr["leg"]][0] == "descending":
            # Through the surface: the world changes, the pod comes down onto its ground point.
            tr["up"] = False
            tr["ground"] = (0.0, 0.0) if tr["legs"] is RIDE_UP else tr["land"]
            lx, ly = tr["land"]
            drop = HUB_DROP if tr["legs"] is RIDE_UP else POD_DROP
            self.switch_surface(tr["to"], lx - 40.0, ly - drop)

    def ride_fields(self, msg):
        if self.trip:
            tr = self.trip
            gx, gy = tr["ground"]
            msg.update(pod=tr["unit"], ps=tr["legs"][tr["leg"]][0], up=1 if tr["up"] else 0, gx=fixed(gx), gy=fixed(gy))
        elif self.in_hub:
            msg["hub"] = self.platform["hub"] or 1

    def tick_player(self):
        p, inv = self.player, self.player["inventory"]
        if self.trip:
            self.step_trip()
        if p["walk"] and self.tick <= p["walk"][1]:
            if len(p["walk"]) > 2:
                p["walk"][0] = angle_step(p["walk"])
            d = p["walk"][0]
            angle = d / 16 * 2 * math.pi
            p["x"] += math.sin(angle) * WALK_SPEED
            p["y"] -= math.cos(angle) * WALK_SPEED
            p["dir"] = d
        else:
            p["walk"] = None
        m = p["mining"]
        if m:
            if self.tick > m["until"] or m["entity"].key() not in self.entities:
                p["mining"] = None
            else:
                m["progress"] += 1
                if m["progress"] >= m["time"]:
                    keep = self.finish_mining(m["entity"])
                    m["progress"] = 0
                    if not keep:
                        p["mining"] = None
        if p["pickup"] is not None:
            if self.tick > p["pickup"]:
                p["pickup"] = None
            else:
                near = [g for g in self.ground if math.hypot(g[1] - p["x"], g[2] - p["y"]) <= PICKUP_DISTANCE]
                for g in near[:PICKUPS_PER_TICK]:
                    self.ground.remove(g)
                    inv[g[0]] = inv.get(g[0], 0) + 1
        if p["craft"] and self.tick % 30 == 0:
            recipe = p["craft"][0]
            needs, (product, count) = RECIPES[recipe]
            if all(inv.get(k, 0) >= v for k, v in needs.items()):
                for k, v in needs.items():
                    inv[k] -= v
                inv[product] = inv.get(product, 0) + count
            else:
                self.message(f"Missing ingredients for {recipe}")
            p["craft"].pop(0)
        if self.tick % 2 == 0:
            msg = {"t": "me", "u": p["unit"], "x": fixed(p["x"]), "y": fixed(p["y"]), "d": p["dir"],
                   "w": 1 if p["walk"] else 0, "hp": int(p["hp"]), "mhp": CHARACTER_HEALTH, "q": len(p["craft"]),
                   "sh": 1 if self.tick - p["fired"] <= FIRING_TICKS else 0}
            if p["walk"] and len(p["walk"]) > 2:
                msg["a"] = p["walk"][2]
            sd, msd = self.shields()
            if msd:
                msg.update(sd=sd, msd=msd)
            if p["mining"]:
                e = p["mining"]["entity"]
                msg.update(m=int(p["mining"]["progress"] * 100 / p["mining"]["time"]), mx=fixed(e.x), my=fixed(e.y))
            if p["vehicle"] is not None:
                msg.update(v=p["vehicle"]["unit"], vs=int(round(p["vehicle"]["speed"] * 1000)))
            self.ride_fields(msg)
            self.send_now(msg)
        if self.tick % 30 == 0:
            self.send_inventory()

    # --- gear: equipment grids, character info, players, death -------------------------------

    def grid_owner(self, kind, unit=0):
        """The grid key a command or message names: "char", or a vehicle unit the client has open."""
        if kind == "veh":
            sc = self.screen
            v = self.player["vehicle"]
            open_unit = sc["unit"] if sc else (v["unit"] if v else 0)
            return open_unit if open_unit in self.grids and (not unit or unit == open_unit) else None
        return "char"

    def grid_message(self, kind):
        key = self.grid_owner(kind)
        msg = {"t": "eq", "kind": kind, "u": (self.player["unit"] if key == "char" else key) if key else 0, "w": 0, "h": 0, "l": []}
        g = self.grids.get(key) if key else None
        if g is None:
            return msg
        recs, sh, msh, bat, mbat, mv, nv = [], 0, 0, 0, 0, 0.0, 0
        for name, x, y, energy, shield in g["eq"]:
            w, h, emax, smax, move = EQUIPMENT[name]
            recs.append([name, x, y, w, h, "normal", int(energy), emax, int(shield), smax, 0])
            sh, msh = sh + int(shield), msh + smax
            if name.startswith("battery"):
                bat, mbat = bat + int(energy), mbat + emax
            if g["mvon"]:
                mv += move
            if name == "night-vision-equipment" and energy > 0:
                nv = 1
        gen = sum(750000 if n == "fission-reactor-equipment" else 30000 if n == "solar-panel-equipment" else 0 for n, *_ in g["eq"])
        msg.update(w=g["w"], h=g["h"], l=recs, sh=sh, msh=msh, bat=bat, mbat=mbat, gen=gen, mv=int(round(mv * 1000)), inv=0,
                   mvon=1 if g["mvon"] else 0, nv=nv, rb=1 if g["rb"] else 0)
        return msg

    def send_gear(self, force=False):
        for kind in ("char", "veh"):
            msg = self.grid_message(kind)
            sig = json.dumps([msg["u"], msg["l"] and [[r[0], r[1], r[2], r[6] * 100 // max(1, r[7]), r[8]] for r in msg["l"]],
                              msg.get("rb"), msg.get("mvon")])
            last = self.gear_sent.get(kind)
            if force or not last or last[0] != sig or self.tick - last[1] >= 300:
                self.gear_sent[kind] = (sig, self.tick)
                self.send_now(msg)

    def shields(self):
        g = self.grids["char"]
        return sum(int(e[4]) for e in g["eq"]), sum(EQUIPMENT[e[0]][3] for e in g["eq"])

    def hurt(self, amount):
        """Damage: the armour's shields take it first, as in Factorio."""
        for e in self.grids["char"]["eq"]:
            if amount > 0 and e[4] > 0:
                taken = min(e[4], amount)
                e[4], amount = e[4] - taken, amount - taken
        self.player["hp"] -= amount

    def character_info(self):
        g = self.grids["char"]
        mv = sum(EQUIPMENT[e[0]][4] for e in g["eq"]) if g["mvon"] else 0.0
        return {"t": "cinfo", "craft": 1000, "mine": 1500, "run": 1000, "speed": int(round(WALK_SPEED * (1 + mv) * 1000)),
                "eqmv": int(round(mv * 1000)), "reach": int(REACH * 10), "build": 100, "rreach": 27, "pick": 11, "loot": 20, "drop": 100,
                "invb": 10, "eqinv": 0, "trash": 10, "hp": CHARACTER_HEALTH, "hpb": 0, "robots": 0, "slots": MAIN_SLOTS}

    def gear_command(self, t, msg):
        kind = str(msg.get("kind", "char"))
        key = self.grid_owner(kind, int(msg.get("u", 0) or 0))
        g = self.grids.get(key) if key else None
        if t == "respawn":
            return
        if g is None:
            return self.message("No equipment grid")

        def at(x, y):
            for e in g["eq"]:
                w, h = EQUIPMENT[e[0]][:2]
                if e[1] <= x < e[1] + w and e[2] <= y < e[2] + h:
                    return e
            return None

        def fits(name, x, y, skip=None):
            w, h = EQUIPMENT[name][:2]
            if x < 0 or y < 0 or x + w > g["w"] or y + h > g["h"]:
                return False
            return all(at(x + dx, y + dy) in (None, skip) for dx in range(w) for dy in range(h))

        if t == "eq_put":
            layout, fi = self.main_slots(), int(msg.get("fi", 0)) - 1
            item = layout[fi][0] if 0 <= fi < len(layout) and layout[fi] else None
            if item not in EQUIPMENT:
                return self.message("That isn't equipment")
            if "x" in msg and "y" in msg:
                spot = (int(msg["x"]), int(msg["y"])) if fits(item, int(msg["x"]), int(msg["y"])) else None
            else:
                spot = next(((x, y) for y in range(g["h"]) for x in range(g["w"]) if fits(item, x, y)), None)
            if spot is None:
                return self.message("No room for that in the grid")
            g["eq"].append([item, spot[0], spot[1], 0, 0])
            self.player["inventory"][item] -= 1
            layout[fi][1] -= 1
            if layout[fi][1] == 0:
                layout[fi] = None
        elif t == "eq_take":
            e = at(int(msg.get("x", -1)), int(msg.get("y", -1)))
            if e is None:
                return
            g["eq"].remove(e)
            inv = self.player["inventory"]
            inv[e[0]] = inv.get(e[0], 0) + 1
            ti = int(msg.get("ti", 0)) - 1
            if 0 <= ti < MAIN_SLOTS and self.layout[ti] is None:
                self.layout[ti] = [e[0], 1]
        elif t == "eq_move":
            e = at(int(msg.get("x", -1)), int(msg.get("y", -1)))
            tx, ty = int(msg.get("tx", -1)), int(msg.get("ty", -1))
            if e is None:
                return
            if not fits(e[0], tx, ty, e):
                return self.message("Can't put that there")
            e[1], e[2] = tx, ty
        elif t == "eq_toggle":
            on = msg.get("on") in (1, True)
            if msg.get("what") == "roboport":
                g["rb"] = on
            elif msg.get("what") == "movement":
                g["mvon"] = on
        self.send_gear(force=True)
        self.send_slots()
        self.send_inventory()

    def die(self):
        p = self.player
        self.dead = {"until": self.tick + CHARACTER_RESPAWN_TICKS, "x": p["x"], "y": p["y"]}
        p.update(walk=None, mining=None, shoot=None, drive=None)
        self.screen = None
        print("the character died")

    def respawn(self):
        """A new character at the spawn: a new unit, so the client starts over (as the mod does)."""
        p = self.player
        self.dead = None
        p.update(x=0.5, y=0.5, hp=float(CHARACTER_HEALTH), unit=self._unit(), vehicle=None)
        for e in self.grids["char"]["eq"]:
            e[4] = 0
        self.handshake()

    def tick_gear(self):
        """Returns False while the character is dead (nothing else of it is sent)."""
        if self.dead is not None:
            if self.tick >= self.dead["until"]:
                self.respawn()
            elif self.tick % 30 == 0:
                self.send_now({"t": "dead", "left": self.dead["until"] - self.tick, "x": fixed(self.dead["x"]), "y": fixed(self.dead["y"])})
            return False
        if self.die_at is not None and self.tick >= self.die_at:
            self.die_at = None
            self.player["hp"] = 0
        if self.player["hp"] <= 0:
            self.die()
            return False
        # Shields recharge from the reactor (slowly: they start empty), batteries fill.
        for e in self.grids["char"]["eq"]:
            w, h, emax, smax, _ = EQUIPMENT[e[0]]
            if smax:
                e[4] = min(smax, e[4] + 0.02)
            if emax:
                e[3] = min(emax, e[3] + emax / 1800)
        if self.tick % 30 == 0:
            self.send_gear()
        if self.tick % 60 == 0:
            self.send_now(self.character_info())
            self.send_now({"t": "pl", "me": 0, "u": self.player["unit"], "l": MOCK_PLAYERS})
        return True

    # --- combat ----------------------------------------------------------------------------

    def alive_enemies(self):
        for m in self.movers:
            if m["name"] in BITER_HEALTH and m["dead_until"] <= self.tick:
                x, y, _ = self.mover_state(m)
                yield m, x, y

    def tick_combat(self):
        p = self.player
        # Dead biters come back at their nest as new units.
        for m in self.movers:
            if m["name"] in BITER_HEALTH and m["dead_until"] and m["dead_until"] <= self.tick:
                m.update(dead_until=0, hp=BITER_HEALTH[m["name"]], unit=self._unit())
        near = [(m, x, y) for m, x, y in self.alive_enemies() if math.hypot(x - p["x"], y - p["y"]) <= BITE_RANGE]
        if near and self.tick % 10 == 0:
            # The biters biting are attacking the character (the mod's `en`).
            self.send_now({"t": "en", "l": [v for m, _, _ in near for v in (m["unit"], fixed(p["x"]), fixed(p["y"]))]})
        if near:
            self.hurt(BITE_DAMAGE * len(near))
            if not self.mortal:
                p["hp"] = max(1.0, p["hp"])  # the mock character dies only with --mortal
        else:
            p["hp"] = min(float(CHARACTER_HEALTH), p["hp"] + 0.05)
        sh = p["shoot"]
        if sh and self.tick > sh["until"]:
            p["shoot"] = sh = None
        gun = p["guns"][p["sel"]]
        if sh and self.tick >= sh["next"]:
            if not gun[1] or gun[2] <= 0:
                if not sh["warned"]:
                    sh["warned"] = True
                    self.message("Out of ammo")
            else:
                self.fire(sh, gun)
        if self.tick % GUNS_INTERVAL == 0:
            sig = json.dumps([p["sel"], p["guns"], p["rounds"]])
            if sig != self.guns_sig:
                self.guns_sig = sig
                self.send_reliable({"t": "guns", "sel": p["sel"] + 1, "l": [self.gun_record(i, g) for i, g in enumerate(p["guns"])]})
        if self.tick % HEALTH_INTERVAL == 0:
            fx, fy, fr = self.focus
            flat = []
            for m, x, y in self.alive_enemies():
                if m["hp"] < BITER_HEALTH[m["name"]] and abs(x - fx) <= fr and abs(y - fy) <= fr:
                    flat += [m["unit"], int(m["hp"] * 1000 / BITER_HEALTH[m["name"]])]
            if p["hp"] < CHARACTER_HEALTH:
                flat += [p["unit"], int(p["hp"] * 1000 / CHARACTER_HEALTH)]
            self.send_now({"t": "hp", "part": 1, "parts": 1, "l": flat})

    def gun_record(self, i, g):
        """[gun, ammo, magazines, rounds left in the magazine in use, magazine size]: the mock tracks
        rounds for the selected gun only; the others' magazines are full."""
        p = self.player
        if not g[1] or g[2] <= 0:
            return [g[0], g[1], g[2], 0, 0]
        return [g[0], g[1], g[2], p["rounds"] if i == p["sel"] else ROUNDS_PER_MAGAZINE, ROUNDS_PER_MAGAZINE]

    def fire(self, sh, gun):
        """One shot: at the nearest biter in range (Space), or at the aim point and whatever is
        on it (C). Like the game, Space doesn't fire without a target."""
        p = self.player
        in_range = [(math.hypot(x - p["x"], y - p["y"]), m, x, y) for m, x, y in self.alive_enemies()]
        reach = mock_shots.gun_range(gun[0])
        in_range = [t for t in in_range if t[0] <= reach]
        if sh["selected"]:
            if math.hypot(sh["x"] - p["x"], sh["y"] - p["y"]) > reach:
                return
            hits = sorted((math.hypot(x - sh["x"], y - sh["y"]), m, x, y) for _, m, x, y in in_range)
            target = hits[0][1:] if hits and hits[0][0] <= 1.0 else None
        else:
            if not in_range:
                return
            target = min(in_range, key=lambda t: t[0])[1:]
        sh["next"] = self.tick + mock_shots.cooldown(gun[0])
        p["fired"] = self.tick
        mock_shots.fired(self, gun[0], gun[1], target[1:] if target else None, (sh["x"], sh["y"]))
        p["rounds"] -= 1
        if p["rounds"] <= 0:
            gun[2] -= 1
            p["rounds"] = ROUNDS_PER_MAGAZINE
            if gun[2] <= 0:
                gun[1], gun[2] = "", 0
        if target is None:
            return
        m, x, y = target
        m["hp"] -= SHOT_DAMAGE
        if m["hp"] <= 0:
            m["dead_until"] = self.tick + RESPAWN_TICKS
            fx, fy, fr = self.focus
            if abs(x - fx) <= fr and abs(y - fy) <= fr:
                self.send_now({"t": "died", "u": m["unit"], "p": EID[m["name"]], "x": fixed(x), "y": fixed(y)})

    # --- main loop ------------------------------------------------------------------------

    def step(self):
        self.tick += 1
        self.receive()
        self.update()
        for addr, state in list(self.extras.items()):
            with self.serving(state):
                self.update()
                gone = self.client is None
            if gone:
                print(f"client {addr[0]}:{addr[1]} dropped")
                del self.extras[addr]
                self.characters.pop(state["player"]["unit"], None)
        for addr in list(self.batches):
            self.send_batch(addr)

    @contextlib.contextmanager
    def serving(self, state):
        """Swaps an extra client's state in for the duration (like session.serve in the mod)."""
        saved = {a: getattr(self, a) for a in PER_CLIENT}
        for a in PER_CLIENT:
            setattr(self, a, state[a])
        try:
            yield
        finally:
            for a in PER_CLIENT:
                state[a] = getattr(self, a)
                setattr(self, a, saved[a])

    def add_client(self, msg, addr):
        """A second (third...) client: fresh state, its own character a little east of the first."""
        if len(self.extras) >= MAX_EXTRA_CLIENTS:
            return
        state = copy.deepcopy(self.fresh)
        state["player"]["unit"] = self._unit()
        state["player"]["x"] = self.player["x"] + 2.0 + len(self.extras)
        state["player"]["y"] = self.player["y"]
        self.extras[addr] = state
        self.characters[state["player"]["unit"]] = state["player"]
        with self.serving(state):
            self.handle_message(msg, addr)

    def update(self):
        """One tick of the world and everything sent (step() without the socket)."""
        if self.client is None:
            return
        if self.tick - self.client["last_seen"] > TIMEOUT_TICKS:
            print("client timed out")
            self.client = None
            return
        self.flush()
        self.tick_cars()
        mock_vehicles.tick(self)
        mock_turrets.tick(self)
        mock_vehicle_showcase.tick(self)
        mock_creature_showcase.tick(self, Entity)
        mock_enemy_showcase.tick(self)
        mock_logistics.tick(self)
        if self.tick_gear():
            self.tick_player()
            self.tick_combat()
        mock_shots.tick(self)
        self.tick_ui()
        if self.tick % 60 == 0:
            self.send_now(self.alert_message())
            # What the bridge did each tick (budget.lua): the mock does its work in one go, so none.
            self.send_now({"t": "wb", "b": self.work_budget, "avg": 0, "max": 0, "over": 0, "n": 60,
                           "q": {"chunks": len(self.queue), "map": len(self.map_queue), "reqs": 0, "radars": 0, "techs": 0}})
            if self.remote_view:
                self.send_view_coverage()
        if self.tick == self.client.get("chat_at", -1):
            # A player's line with rich text, as Factorio's chat carries it.
            self.send_now({"t": "chat", "from": "Alice", "c": [1, 0.5, 0], "text":
                           "Iron ore at [gps=30,-25,nauvis] [item=iron-ore], [color=red]bring[/color] [font=default-bold]coal[/font]"})
        self.tick_screen()
        self.tick_alt()
        self.tick_map()
        self.tick_platform()
        self.tick_planet()
        self.space.tick()
        if self.surface == "nauvis":
            self.tick_trains()
            self.tick_logistics()
        budget = CHUNKS_PER_TICK
        while budget and self.queue and len(self.outbox) < MAX_BACKLOG:
            c = self.queue.pop(0)
            if c in self.subs:
                self.snapshot(*c)
                budget -= 1
        if self.rate_due("mv", 2):
            fx, fy, fr = self.focus
            recs = []
            for m in self.movers:
                if m.get("dead_until", 0) > self.tick:
                    continue
                x, y, o = self.mover_state(m)
                if abs(x - fx) <= fr and abs(y - fy) <= fr and self.view_seen(x, y):
                    rec = [m["unit"], EID[m["name"]], fixed(x), fixed(y)]
                    if m.get("oriented"):
                        rec.append(int(o * 1000 + 0.5))
                    recs.append(rec)
            for unit, other in self.characters.items():  # the other clients' characters
                if other is not self.player and abs(other["x"] - fx) <= fr and abs(other["y"] - fy) <= fr:
                    recs.append([unit, EID["character"], fixed(other["x"]), fixed(other["y"])])
            parts = max(1, math.ceil(len(recs) / MOVERS_PER_MESSAGE))
            for i in range(parts):
                self.send_list("mv", i + 1, parts, recs[i * MOVERS_PER_MESSAGE:(i + 1) * MOVERS_PER_MESSAGE], None,
                               {"p": self.rate_period("mv", 2)})
        if self.tick % 60 == 30 and getattr(self, "far_r", 0) > 0:
            self.send_far_belts()
        near = getattr(self, "near_r", None)
        if self.rate_due("bi", BELT_ITEM_INTERVAL):
            fx, fy, fr = self.focus
            r = min(BELT_ITEM_RADIUS if near is None else near, fr)
            flat = []
            fresh = []
            for uid, name, x, y in self.belt_items() + self.belt_field_items():
                if abs(x - fx) <= r and abs(y - fy) <= r:
                    flat += [uid, IID[name], fixed(x), fixed(y)]
                    if name in SPOILING:
                        fresh += [uid, 1000 - (self.tick + uid * 97) % 1000]
            if fresh:
                self.send_now({"t": "bf", "part": 1, "parts": 1, "l": fresh})
            self.space.belt_quality(flat[0::4])
            per = ITEMS_PER_MESSAGE * 4
            parts = max(1, math.ceil(len(flat) / per))
            for i in range(parts):
                self.send_list("bi", i + 1, parts, flat[i * per:(i + 1) * per], 4,
                               {"fx": fixed(fx), "fy": fixed(fy), "fr": int(r), "p": self.rate_period("bi", BELT_ITEM_INTERVAL)})
        if self.rate_due("ih", BELT_ITEM_INTERVAL):
            fx, fy, fr = self.focus
            r = min(BELT_ITEM_RADIUS if near is None else near, fr)
            hands = []
            for unit, x, y, item in self.inserter_hands():
                if abs(x - fx) <= r and abs(y - fy) <= r:
                    hands += [unit, fixed(x), fixed(y), IID[item] if item else 0]
            self.send_list("ih", 1, 1, hands, 4, {"p": self.rate_period("ih", BELT_ITEM_INTERVAL)})
        if self.tick % (BELT_ITEM_INTERVAL if self.player["pickup"] is not None else GROUND_ITEM_INTERVAL) == 0:
            fx, fy, fr = self.focus
            r = min(BELT_ITEM_RADIUS, fr)
            flat = []
            for name, x, y in self.ground:
                if abs(x - fx) <= r and abs(y - fy) <= r:
                    flat += [IID[name], fixed(x), fixed(y)]
            self.send_now({"t": "gi", "part": 1, "parts": 1, "l": flat})
        if self.tick % FLUID_INTERVAL == 0:
            fx, fy, fr = self.focus
            r = min(BELT_ITEM_RADIUS, fr)
            flat = []
            for unit, boxes in self.fluids.items():
                e = self.entities.get(unit)
                if e and abs(e.x - fx) <= r and abs(e.y - fy) <= r:
                    for i, (name, amount, cap, temp) in enumerate(boxes):
                        flat += [unit, i + 1, FID[name], amount, cap, temp]
            self.send_now({"t": "fl", "part": 1, "parts": 1, "l": flat})
            heat = []
            for unit, temperature in self.heat.items():
                e = self.entities.get(unit)
                if e and abs(e.x - fx) <= r and abs(e.y - fy) <= r:
                    heat += [unit, temperature]
            self.send_now({"t": "ht", "part": 1, "parts": 1, "l": heat})
            low = self.low_power if self.low_power_now() and self.low_power.key() in self.entities else None
            power = [low.unit, 1] if low else []
            if self.unplugged.key() in self.entities:
                power += [self.unplugged.unit, 2]
            self.send_now({"t": "pw", "part": 1, "parts": 1, "l": power})
        if self.tick % SKY_INTERVAL == 0:
            # A platform's surface is always at noon (daytime 0, no darkness), as in 2.1.23.
            d = self.daytime() if self.surface == "nauvis" else (self.tick % PLANETS[self.surface]["day"]) / PLANETS[self.surface]["day"] \
                if self.surface in PLANETS else 0.0
            self.send_now({"t": "sky", "d": int(d * 1000) % 1000, "n": int(darkness_at(d) * 1000 + 0.5)})
        if self.tick % 30 == 0:
            changes = []
            for e in self.entities.values():
                if e.unit and e.type in ANIMATED_TYPES:
                    on = 1 if e.type == "lamp" or self.always_working or (self.tick // 300 + e.unit) % 3 else 0
                    if self.working.get(e.unit) != on:
                        self.working[e.unit] = on
                        changes += [e.unit, on]
            if changes:
                self.send_reliable({"t": "st", "l": changes})

    # --- map ------------------------------------------------------------------------------

    def request_map(self, msg):
        def num(k, default):
            v = msg.get(k, default)
            return math.floor(v) if isinstance(v, (int, float)) else default
        x1, y1 = num("cx1", 0), num("cy1", 0)
        x2, y2 = num("cx2", x1), num("cy2", y1)
        x1, x2, y1, y2 = min(x1, x2), max(x1, x2), min(y1, y2), max(y1, y2)
        mx, my = (x1 + x2) / 2, (y1 + y2) / 2
        half = int(math.sqrt(MAP_MAX_CHUNKS) / 2)
        x1, x2 = max(x1, math.floor(mx) - half + 1), min(x2, math.floor(mx) + half)
        y1, y2 = max(y1, math.floor(my) - half + 1), min(y2, math.floor(my) + half)
        chunks = [(cx, cy) for cy in range(y1, y2 + 1) for cx in range(x1, x2 + 1)]
        chunks.sort(key=lambda c: ((c[0] - mx) ** 2 + (c[1] - my) ** 2, c[1], c[0]))
        self.map_queue = chunks
        self.map_res = msg.get("res") if msg.get("res") in MAP_RESOLUTIONS else 4
        self.map_si = msg.get("si") if msg.get("si") in self.surface_tags else None
        self.tags_dirty = True

    # The beacon --beacon puts by the starter assemblers: two speed modules 3 (+50% speed, +70%
    # consumption each). Real 2.1.23 reports a beacon's effects before its distribution effectivity
    # (1.5) and a machine's after it.
    BEACON_EFFECT = {"sp": 1000, "co": 1400}
    # Factorio's energy use (W) of the mock's electric machines, for the hover panel's electricity.
    ELECTRIC_WATTS = {"assembling-machine-1": 75000, "assembling-machine-2": 150000, "assembling-machine-3": 375000,
                      "electric-furnace": 180000, "electric-mining-drill": 90000, "lab": 60000, "inserter": 13200,
                      "fast-inserter": 46000, "radar": 300000, "beacon": 480000, "small-lamp": 5000, "roboport": 50000,
                      "laser-turret": 2400000, "pump": 30000}

    def hover_info(self, msg):
        """modules.lua's hover: a beacon's or a machine's effects, modules and the beacons between them."""
        out = {"t": "hinfo", "q": int(msg.get("q", 0)), "u": int(msg.get("u", 0))}
        e = self.entities.get(out["u"])
        if e is None:
            return out
        # H20: what draws electricity, as modules.lua's electricity(): the buffer (two ticks' worth here),
        # Max. consumption with the drain (a thirtieth of the use, Factorio's usual) and Min. consumption.
        watts = self.ELECTRIC_WATTS.get(e.name)
        if watts:
            drain = watts // 30 if e.type in ("assembling-machine", "furnace") else 0
            buffer = (watts + drain) // 30
            full = 0.0 if e is self.unplugged else (0.35 if e is self.low_power and self.low_power_now() else 1.0)
            out["el"] = {"e": int(buffer * full), "b": buffer, "mx": watts + drain, "mn": drain}
        if e.type == "roboport":
            # H14: the roboports whose logistic squares meet this one's (modules.lua reads the game's cells).
            out["rn"] = [v for o in self.entities.values() if o is not e and o.type == "roboport"
                         and abs(o.x - e.x) <= 2 * LOGISTIC_REACH and abs(o.y - e.y) <= 2 * LOGISTIC_REACH
                         for v in (int(o.x * 256), int(o.y * 256))]
        near = lambda types: [o for o in self.entities.values() if o is not e and o.type in types
                              and abs(o.x - e.x) <= 5.5 and abs(o.y - e.y) <= 5.5]
        if e.type == "beacon":
            if e.extra.get("mods") is None:
                out.update(eff=dict(self.BEACON_EFFECT), m=[["speed-module-3", 2]], de=1500)
            else:
                out["de"] = 1500
            out["n"] = len(near(("assembling-machine", "furnace", "mining-drill", "lab")))
        elif e.type in ("assembling-machine", "furnace", "mining-drill", "lab", "rocket-silo"):
            beacons = [b for b in near(("beacon",)) if b.extra.get("mods") is None]
            if beacons:
                out["b"] = len(beacons)
                out["eff"] = {k: v * 3 // 2 * len(beacons) for k, v in self.BEACON_EFFECT.items()}
        return out

    def surface_index(self):
        """The same index surface_fields gives the client (on another planet its own, not the platform's)."""
        return self.surface_fields({})["si"]

    def send_surfaces(self):
        """The map's surface switcher (map.lua's `surfs`): Nauvis, the mock's platform and an "Other" surface."""
        self.send_reliable({"t": "surfs", "l": [[1, "nauvis", "nauvis", "", 0],
                                                [2, "platform-1", "", self.platform["n"], self.platform["i"]],
                                                [3, "f3d-lab", "", "", 0]]})

    def chart(self, cx, cy, res):
        si = self.map_si or self.surface_index()
        if si != self.surface_index():
            return self.chart_elsewhere(si, cx, cy, res)
        if (cx, cy) not in self.charted:
            self.send_now({"t": "chart", "cx": cx, "cy": cy, "n": 0, "si": si})
            return
        self.generate_chunk(cx, cy)
        n = CHUNK // res
        x0, y0 = cx * CHUNK, cy * CHUNK
        pal, index = [], {}

        def colour_index(c):
            c = tuple(c)
            if c not in index:
                index[c] = len(pal)
                pal.append(list(c))
            return index[c]
        tile_colour = dict(TILE_PROTOS)
        half = res // 2
        px = [colour_index(tile_colour[self.tile_at(x0 + i * res + half, y0 + j * res + half)])
              for j in range(n) for i in range(n)]
        layers = [0] * (n * n)
        colour = {p[0]: p[4] for p in ENTITY_PROTOS}
        for key in self.by_chunk.get((cx, cy), ()):
            e = self.entities.get(key)
            if e is None or e.type in MAP_SKIP:
                continue
            c = MAP_GHOST if e.type == "entity-ghost" else colour[e.name]
            layer = MAP_LAYERS.get(e.type, 3)
            bx1, by1, bx2, by2 = e.box()
            for j in range(max(0, math.floor((by1 - y0) / res)), min(n - 1, math.floor((by2 - y0 - 0.001) / res)) + 1):
                for i in range(max(0, math.floor((bx1 - x0) / res)), min(n - 1, math.floor((bx2 - x0 - 0.001) / res)) + 1):
                    if layer >= layers[j * n + i]:
                        px[j * n + i], layers[j * n + i] = colour_index(c), layer
        msg = {"t": "chart", "cx": cx, "cy": cy, "n": n, "pal": pal, "px": px, "si": si}
        # Pollution round the start (the furnaces), fading with distance, as map.lua's pol.
        pol = int(4000 / (1 + cx * cx + cy * cy))
        if pol > 0 and si == self.surface_index():
            msg["pol"] = pol
        ov = self.map_overlay(cx, cy)
        if ov:
            msg["ov"] = ov
        self.send_now(msg)

    def chart_elsewhere(self, si, cx, cy, res):
        """A chart of the surface the character isn't on: the platform's deck (grey within 24 tiles
        of its middle), or Nauvis's charted chunks from the world kept for it."""
        n = CHUNK // res
        if si == 2:
            if not (-1 <= cx <= 0 and -1 <= cy <= 0):
                return self.send_now({"t": "chart", "cx": cx, "cy": cy, "n": 0, "si": si})
            px = [1 if abs(cx * CHUNK + i * res + res // 2) < 24 and abs(cy * CHUNK + j * res + res // 2) < 24 else 0
                  for j in range(n) for i in range(n)]
            return self.send_now({"t": "chart", "cx": cx, "cy": cy, "n": n, "pal": [[0, 0, 0], [96, 96, 100]], "px": px, "si": si})
        saved = {k: getattr(self, k) for k in SURFACE_STATE}
        here, self.surface = self.surface, "nauvis"
        for k, v in self.worlds.get("nauvis", {}).items():
            setattr(self, k, v)
        map_si, self.map_si = self.map_si, None
        try:
            self.chart(cx, cy, res)
        finally:
            self.surface, self.map_si = here, map_si
            for k, v in saved.items():
                setattr(self, k, v)

    def map_overlay(self, cx, cy):
        """The map view's layers in a chunk, as map.lua sends them: poles, turrets, train stops,
        machines' recipes."""
        out = []
        for key in self.by_chunk.get((cx, cy), ()):
            e = self.entities.get(key)
            if e is None or not (cx * CHUNK <= e.x < (cx + 1) * CHUNK and cy * CHUNK <= e.y < (cy + 1) * CHUNK):
                continue
            x, y = fixed(e.x), fixed(e.y)
            if e.type == "electric-pole":
                out.append(["e", x, y, 2.5])
                for other in self.entities.values():  # its copper wires, once each, as map.lua
                    if other.type == "electric-pole" and other.unit in (e.extra.get("w") or []) and other.unit > e.unit:
                        out.append(["w", x, y, fixed(other.x), fixed(other.y)])
            elif e.type == "ammo-turret":
                out.append(["t", x, y, 18])
            elif e.type == "train-stop":
                out.append(["s", x, y, str(e.extra.get("n", "Stop"))])
            elif e.type in ("assembling-machine", "furnace") and self.machines.get(e.unit, {}).get("recipe"):
                out.append(["c", x, y, self.machines[e.unit]["recipe"]])
        return out

    def tick_map(self):
        if self.tick % MAP_CHART_INTERVAL == 0:
            pcx, pcy = math.floor(self.player["x"] / CHUNK), math.floor(self.player["y"] / CHUNK)
            self.charted |= {(pcx + dx, pcy + dy) for dx in range(-MAP_CHART_RADIUS, MAP_CHART_RADIUS + 1)
                             for dy in range(-MAP_CHART_RADIUS, MAP_CHART_RADIUS + 1)}
        if self.tags_dirty:
            self.tags_dirty = False
            si = self.map_si or self.surface_index()
            self.send_now({"t": "tags", "l": self.surface_tags.get(si, []), "si": si})
        for _ in range(MAP_CHUNKS_PER_TICK):
            if not self.map_queue:
                break
            self.chart(*self.map_queue.pop(0), self.map_res)

    # --- trains -----------------------------------------------------------------------------

    def mover_entity(self, unit):
        """A train carriage or the parked car as an Entity where it is now, or None."""
        for m in self.movers:
            if m["unit"] == unit and m["kind"] in ("train", "parked", "spider"):
                x, y, _ = self.mover_state(m)
                return Entity(unit, m["name"], x, y, 4)
        return None

    def train_info(self):
        tr = self.train
        current = tr["records"][tr["current"] - 1] if 0 < tr["current"] <= len(tr["records"]) else {}
        front = self.mover_entity(TRAIN_UNITS[0])
        stops = sorted({e.extra.get("n", "") for e in self.entities.values() if e.type == "train-stop"} - {""})
        info = {"id": tr["id"], "state": "manual_control" if tr["manual"] else "on_the_path", "manual": 1 if tr["manual"] else 0,
                "station": "", "dest": current.get("station", ""), "name": "Mock train",
                "sched": {"current": tr["current"], "records": tr["records"], "group": "", "interrupts": tr.get("interrupts", [])},
                "cargo": [["iron-plate", 400]], "fluids": [], "fuel": [["coal", 20]], "stops": stops,
                "speed": 0 if tr["manual"] else int(TRAIN_SPEED * 1000)}
        if front is not None:
            info["pos"] = [fixed(front.x), fixed(front.y)]
        mock_vehicles.train_fields(self, info)
        return info

    def send_train_list(self):
        """The trains overview (`trl`): the mock's one train."""
        tr, info = self.train, self.train_info()
        front = self.mover_entity(TRAIN_UNITS[0])
        x, y = (fixed(front.x), fixed(front.y)) if front else (0, 0)
        self.send_now({"t": "trl", "part": 1, "parts": 1, "l": [[tr["id"], info["state"], info["manual"], info["dest"], "",
                                                                 len(TRAIN_UNITS), TRAIN_UNITS[0], x, y, 1, info["speed"],
                                                                 [["iron-plate", 400]], []]]})

    # --- logistics --------------------------------------------------------------------------

    def send_char_logistics(self):
        cl = self.char_logistics
        requests = [[f[0], f[2], f[3]] for sec in cl["sec"] if sec["on"] for f in sec["f"]]
        self.send_reliable({"t": "clog", "on": cl["on"], "trash": cl["trash"], "l": requests, "sec": cl["sec"], "lgs": cl["lgs"]})

    def char_section(self, msg):
        """set_section with u = 0: the character's own sections (logistics.lua's set_char_section)."""
        secs = self.char_logistics["sec"]
        i = int(msg.get("i", 0))
        if msg.get("del") == 1:
            if 1 <= i <= len(secs):
                secs.pop(i - 1)
        else:
            if i == 0:
                g = msg.get("g") if isinstance(msg.get("g"), str) else ""
                secs.append({"i": 0, "g": g, "on": 1, "m": 1, "man": 1, "f": []})
                if g and g not in self.char_logistics["lgs"]:
                    self.char_logistics["lgs"].append(g)
                i = len(secs)
            if 1 <= i <= len(secs):
                sec = secs[i - 1]
                if isinstance(msg.get("f"), list):
                    sec["f"] = [[str(f[0]), str(f[1] or "normal"), int(f[2]), int(f[3]), str(f[4]), int(f[5])]
                                for f in msg["f"] if isinstance(f, list) and len(f) == 6 and f[0] in ITEM_PROTOS]
                if isinstance(msg.get("g"), str) and int(msg.get("i", 0)):
                    sec["g"] = msg["g"]
                    if msg["g"] and msg["g"] not in self.char_logistics["lgs"]:
                        self.char_logistics["lgs"].append(msg["g"])
                if msg.get("on") in (0, 1):
                    sec["on"] = msg["on"]
                if isinstance(msg.get("m"), (int, float)) and msg["m"] >= 0:
                    sec["m"] = msg["m"]
        for k, sec in enumerate(secs):
            sec["i"] = k + 1
        self.send_char_logistics()

    def network_summary(self, with_items):
        out = {"id": 1, "log": [3, 3], "con": [0, 0]}
        if with_items:
            contents = self.machine(self.storage_chest)["inv"]["chest"]
            out["items"] = sorted(([k, v] for k, v in contents.items() if v > 0), key=lambda r: (-r[1], r[0]))
        return out

    def chest_command(self, t, msg):
        sc = self.screen
        entity = self.entities.get(sc["unit"]) if sc and int(msg.get("u", 0)) == sc["unit"] else None
        lg = self.machine(entity).get("lg", {}) if entity else {}
        if t == "set_requests":
            if lg.get("mode") != "requester" or not isinstance(msg.get("l"), list):
                return self.message("That chest doesn't take requests")
            lg["requests"] = [[r[0], int(r[1]), int(r[2])] for r in msg["l"]
                              if isinstance(r, list) and len(r) >= 3 and r[0] in ITEM_PROTOS]
        else:
            if lg.get("mode") != "storage":
                return self.message("That isn't a storage chest")
            item = str(msg.get("item", ""))
            if item == "" or item in ITEM_PROTOS:
                lg["filter"] = item
        sc["due"] = self.tick

    def tick_logistics(self):
        p = self.player
        if self.tick % NETWORK_INTERVAL == 0:
            inside = self.roboport is not None and abs(p["x"] - self.roboport.x) <= LOGISTIC_REACH and abs(p["y"] - self.roboport.y) <= LOGISTIC_REACH
            self.send_now(dict(self.network_summary(False), t="ln") if inside else {"t": "ln", "id": 0})
        if self.tick % CARGO_INTERVAL == 0:
            fx, fy, fr = self.focus
            r = min(BELT_ITEM_RADIUS, fr)
            flat = []
            # The shuttling robots carry plates on the way out (a to b) and come back empty.
            for m in self.movers:
                if m["kind"] == "shuttle" and ((self.tick + m["phase"]) % 240) < 120:
                    x, y, _ = self.mover_state(m)
                    if abs(x - fx) <= r and abs(y - fy) <= r:
                        flat += [m["unit"], IID["iron-plate"], 4]
            self.send_now({"t": "rc", "l": flat})

    def tick_trains(self):
        tr = self.train
        _, _, o = self.mover_state(next(m for m in self.movers if m["unit"] == TRAIN_UNITS[0]))
        east = o < 0.5
        if east != tr["east"] and tr["records"]:
            tr["east"], tr["current"] = east, tr["current"] % len(tr["records"]) + 1
        if self.tick % TRAIN_INTERVAL:
            return
        fx, fy, fr = self.focus
        near = False
        for unit in TRAIN_UNITS:
            e = self.mover_entity(unit)
            near = near or (abs(e.x - fx) <= fr and abs(e.y - fy) <= fr)
        info = self.train_info()
        speed = int(TRAIN_SPEED * 1000)
        self.send_now({"t": "tr", "l": [[tr["id"], info["state"], info["manual"], speed, 0, info["dest"], list(TRAIN_UNITS)]] if near else []})

    def train_command(self, t, msg):
        sc = self.screen
        entity = None
        if sc and int(msg.get("u", 0)) == sc["unit"]:
            entity = self.entities.get(sc["unit"]) or self.mover_entity(sc["unit"])
        kind = SCREEN_KINDS.get(entity.type) if entity else None
        if t == "set_stop":
            if kind != "stop":
                return self.message("That isn't a train stop")
            m = self.machine(entity)
            if isinstance(msg.get("name"), str) and msg["name"]:
                entity.extra["n"] = m["stop"]["name"] = msg["name"]
                if self.watched(entity):
                    self.send_reliable({"t": "upd", "e": entity.record()})
            if isinstance(msg.get("limit"), int):
                m["stop"]["limit"] = max(-1, msg["limit"])
            if isinstance(msg.get("pri"), int):
                m["stop"]["pri"] = max(0, min(255, msg["pri"]))
            if isinstance(msg.get("cb"), dict):
                m["stop"]["cb"].update({k: v for k, v in msg["cb"].items() if k != "wired"})
        elif kind != "train":
            return self.message("That isn't a train")
        elif t == "set_schedule":
            records = msg.get("records")
            if not (isinstance(records, list) and all(isinstance(r, dict) and (isinstance(r.get("station"), str) or "rail" in r)
                                                      for r in records)):
                return self.message("Can't set the schedule: bad records")
            self.train["records"] = records
            self.train["current"] = min(max(self.train["current"], 1), max(len(records), 1))
        elif t == "train_go":
            i = msg.get("i")
            if not (isinstance(i, int) and 1 <= i <= len(self.train["records"])):
                return self.message("Can't go there: no such record")
            self.train["current"] = i
        elif t == "train_mode":
            self.train["manual"] = msg.get("auto") not in (1, True)
        elif t == "set_interrupts":
            ints = msg.get("interrupts")
            if not (isinstance(ints, list) and all(isinstance(i, dict) and isinstance(i.get("name", ""), str) for i in ints)):
                return self.message("Can't set the interrupts: bad interrupts")
            self.train["interrupts"] = ints
        elif t == "train_temp":
            if not (isinstance(msg.get("station"), str) and msg["station"]) and not isinstance(msg.get("rail"), list):
                return self.message("Go where?")
            rec = {"station": msg["station"]} if isinstance(msg.get("station"), str) and msg["station"] else {"rail": msg["rail"]}
            rec["temporary"] = True
            at = min(self.train["current"] + 1, len(self.train["records"]) + 1)
            self.train["records"].insert(at - 1, rec)
            self.train["current"], self.train["manual"] = at, False
        sc["due"] = self.tick

    def low_power_now(self):
        """One assembler runs short of power for 10 s out of every 20."""
        return (self.tick // 600) % 2 == 1

    def run(self, host, port):
        self.sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self.sock.bind((host, port))
        self.sock.setblocking(False)
        if hasattr(socket, "SIO_UDP_CONNRESET"):
            # Windows reports "port unreachable" for an earlier send as an error on recvfrom.
            self.sock.ioctl(socket.SIO_UDP_CONNRESET, False)
        print(f"mock Factorio listening on {host}:{port} (drop rate {self.drop:.0%}). Start the client.")
        next_tick = time.perf_counter()
        while True:
            self.step()
            next_tick += 1 / TICKS_PER_SECOND
            delay = next_tick - time.perf_counter()
            if delay > 0:
                time.sleep(delay)
            else:
                next_tick = time.perf_counter()


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=34200, help="port the client sends to (Factorio's --enable-lua-udp port)")
    parser.add_argument("--seed", type=int, default=1)
    parser.add_argument("--drop", type=float, default=0.0, help="fraction of packets to lose, both ways")
    parser.add_argument("--day-length", type=int, default=25000, help="ticks per day; Factorio's is 25000 (about 7 minutes)")
    parser.add_argument("--start", default="-3,0.5", help="the character's starting position X,Y in tiles")
    parser.add_argument("--platform", action="store_true", help="start on the space platform (at --start when given)")
    parser.add_argument("--auto-launch", action="store_true", help="the rocket silo launches to the platform whenever "
                        "its rocket is ready (mock_space.py)")
    parser.add_argument("--item-showcase", action="store_true", help="every item that has a 3D model lying on the "
                        "ground in a grid west of the start (use --start=-20,8 to look at it)")
    parser.add_argument("--belt-field", metavar="COLSxROWS", help="a block of full belts east of the base (e.g. 40x30) "
                        "for watching thousands of items; use --start 32,0 to stand in it")
    parser.add_argument("--build-demo", action="store_true", help="concrete, hazard concrete, tile ghosts and a rail "
                        "south-west of the start, to look at tiles and the rail planner")
    parser.add_argument("--planet", choices=[p for p in PLANETS if p != "nauvis"], help="start on another planet's surface")
    parser.add_argument("--mortal", action="store_true", help="biters can kill the character (it respawns after 10 s)")
    parser.add_argument("--die-at", type=float, metavar="SECONDS", help="the character dies this long after the client "
                        "connects, to see the respawn screen")
    parser.add_argument("--busy", action="store_true", help="a 20,000-entity factory south of the base (assemblers, "
                        "inserters, belts, poles, 300 robots), for tools/net_cost.py")
    parser.add_argument("--robots", type=int, default=0, metavar="N", help="N logistic and construction robots "
                        "flying round the start (mock_server.build_robot_swarm), for measuring the client with many robots in view")
    parser.add_argument("--reach", type=float, help="the character's reach in tiles (default 10); a big one lets "
                        "tools/ui_reference/ours.py open any entity's screen without walking")
    parser.add_argument("--machine-gallery", action="store_true", help="every production machine whose window "
                        "tools/ui_reference compares, in rows south-west of the start (mock_machines.py; use --reach 200)")
    parser.add_argument("--armor", help="the armour the character wears instead of power armour MK2, or none (each "
                        "armour has its look: light-armor plain, heavy-armor and modular-armor level 2, power-armor level 3, "
                        "mech-armor the mech)")
    parser.add_argument("--other-armor", help="the armour the other player's character (walking round near the start) "
                        "wears instead of power armour, or none")
    parser.add_argument("--vehicles", action="store_true", help="a walking spidertron, a driving tank, working "
                        "construction robots, logistic and capture robots, a cargo pod going up and down and an infinity "
                        "cargo wagon on the train, in a field east of the start (mock_vehicle_showcase.py; look from about 30,16)")
    parser.add_argument("--creatures", action="store_true", help="Space Age's creatures west and south of the start: "
                        "walking pentapods with their feet, wrigglers, Gleba spawners (one dying and coming back), "
                        "demolishers crawling (mock_creature_showcase.py; look from about -45,28 and -45,95)")
    parser.add_argument("--enemies", action="store_true", help="Nauvis's biters, spitters and worms of every tier "
                        "attacking walls, others dying every 15 s, both spawners, north of the start "
                        "(mock_enemy_showcase.py; look from about 32,-62)")
    parser.add_argument("--logistics", action="store_true", help="splitters, loaders, belts of every tier, pumps, "
                        "a power switch, an accumulator, logistic chests with robots, lightning rods and signals, all "
                        "animating (mock_logistics.py; look from about 76,-26)")
    parser.add_argument("--turrets", action="store_true", help="every turret, a tank and a spidertron between the "
                        "start and the biter nest, aiming and firing (mock_turrets.py; look from about 70,45)")
    parser.add_argument("--wait", metavar="PLACE", help="the platform waits at Nauvis with PLACE next in its "
                        "schedule (and never leaves), for the travel panel's waiting state")
    parser.add_argument("--depart", metavar="PLACE", help="the platform is done at Nauvis and waits for its cargo "
                        "before leaving for PLACE (and never leaves): Factorio's waiting_for_departure")
    parser.add_argument("--travel", metavar="PLACE", help="the platform sets off for this place at the start "
                        "(a 30 s trip), for its journey in the map view and the platform panel")
    parser.add_argument("--beacon", action="store_true", help="a beacon with two speed modules north of the "
                        "starter assemblers, for the hover panel's effects")
    parser.add_argument("--radar", action="append", metavar="X,Y", help="a working radar there with a row of "
                        "assemblers and belts across the edge of its coverage, for the 3D remote view (repeatable)")
    parser.add_argument("--guns", metavar="GUN,GUN,GUN", help="these guns with ammo in the character's gun slots, and "
                        "grenades and capsules in its inventory (mock_shots.py), e.g. shotgun,rocket-launcher,flamethrower")
    args = parser.parse_args()
    if args.reach:
        global REACH
        REACH = args.reach
    if args.armor:
        global ARMOR
        ARMOR = "" if args.armor == "none" else args.armor
    if args.other_armor:
        MOCK_PLAYERS[0][11] = "" if args.other_armor == "none" else args.other_armor
    for armor in (ARMOR, MOCK_PLAYERS[0][11]):
        if armor and armor not in IID:
            ITEM_PROTOS.append(armor)
            IID[armor] = len(ITEM_PROTOS)
    showcase = []
    if args.item_showcase:
        folder = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "client", "assets", "models", "items")
        showcase = sorted(f[:-4] for f in os.listdir(folder) if f.endswith(".glb"))
        for name in showcase:
            if name not in IID:
                ITEM_PROTOS.append(name)
                IID[name] = len(ITEM_PROTOS)
    start = tuple(float(v) for v in args.start.split(","))
    game = MockGame(args.seed, args.drop, args.day_length, start)
    game.build_starter_base()
    game.build_cliffs()
    game.mortal = args.mortal
    if args.guns:
        mock_shots.arm(game, args.guns.split(","))
        for name in mock_shots.CAPSULES:
            game.player["inventory"][name] = 10
    if args.die_at is not None:
        game.die_after = int(args.die_at * 60)
    if showcase:
        game.lay_item_showcase(-25.0, 4.0, showcase)
    if args.build_demo:
        game.build_demo(*start)
    if args.belt_field:
        cols, rows = (int(v) for v in args.belt_field.lower().split("x"))
        game.build_belt_field(cols, rows)
    if args.auto_launch:
        game.machine(game.space.silo)["auto"] = 1
    if args.busy:
        game.build_busy_base()
    if args.robots:
        game.build_robot_swarm(args.robots)
    if args.travel:
        game.platform["sched"], game.platform["pa"] = {"c": 1, "l": [args.travel]}, 0
    if args.wait or args.depart:
        # Waiting at its stop (H7): the schedule's current record is where it is and the next one
        # elsewhere; or done there, the current record the next stop, held for cargo on its way.
        game.platform["sched"] = {"c": 2 if args.depart else 1, "l": [game.platform["loc"], args.depart or args.wait]}
        game.platform["pa"], game.platform["hold"] = 0, True
    if args.beacon:
        game.add(Entity(game._unit(), "beacon", 8.5, -6.5))
    for spot in args.radar or []:
        game.build_radar_outpost(*(float(v) for v in spot.split(",")))
    if args.machine_gallery:
        mock_machines.build_gallery(game, Entity)
        mock_vehicles.build_gallery(game, Entity)
    if args.turrets:
        mock_turrets.build_showcase(game, Entity)
    if args.vehicles:
        mock_vehicle_showcase.build_showcase(game)
    if args.creatures:
        mock_creature_showcase.build_showcase(game, Entity)
    if args.enemies:
        mock_enemy_showcase.build_showcase(game, Entity)
    if args.logistics:
        mock_logistics.build_showcase(game, Entity)
    if args.platform:
        # no client yet: nothing is sent; --start puts the character elsewhere on the deck
        game.switch_surface(PLATFORM_SURFACE, *(start if args.start != parser.get_default("start") else PLATFORM_START))
    elif args.planet:
        game.platform["loc"] = args.planet  # the platform waits above it, so plat_board goes up
        game.switch_surface(args.planet, 0.5, 0.5)
    try:
        game.run(args.host, args.port)
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
