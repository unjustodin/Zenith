"""Part colour tuning for the vehicles family (tools/models/PART_COLORS.md): car, locomotive,
wagons, tank, spidertron, artillery; turrets, land mine and combat robots; logistic and
construction robots; nuclear; rocket silo, rocket, cargo pod and landing pad; market, loader.

Forced colours are albedo (sRGB), which a top face shows about as given since core fix 1 (they
were picked against the client's look before it and brightened 1.6x in linear light with it).
Most of these models were built by hand from the sprites and their parts don't sit exactly where
the sprite paints them, so the sampler snaps a material to whatever its parts land on: where
that was another part's paint (a hull's rust read as the tracks' black, a body read as the
engine behind it), the material's colour is set here from the sprite by eye.
"""

OVERRIDES = {
    # The buggy: a silver-cream body (the sampler took the dark engine bay behind the cockpit).
    "car": {
        "colors": {
            "paint_cream": "#848079",
            "steel_dark": "#4e4a45",
            "steel": "#77736d",
            "rust_brown": "#5d4134",
            "hazard": "#896c20",
        },
    },
    # Rust-red plated hull and fenders, grey steel, cream fuel tanks; the turret (own materials)
    # a grey studded steel dome.
    "tank": {
        "colors": {
            "rust_dark": "#4a3d36",
            "rust_brown": "#5a463b",
            "steel_dark": "#4c4a47",
            "steel": "#6d6a66",
            "steel_light": "#73726d",
            "tank_white": "#837e63",
            "steel_light_turret": "#73736f",
            "steel_turret": "#5f5e5c",
            "rust_brown_turret": "#594036",
            "rust_dark_turret": "#4e3f37",
        },
    },
    # Spidertron: the legs are separate entities in Factorio (their sprites aren't in the
    # torso's picture): grey steel with coils, darker sleeves, measured off the leg sprites.
    "spidertron": {
        "colors": {
            "steel_dark_leg": "#716e6f",
            "rust_brown_leg": "#5f5757",
            "steel_light_leg": "#979799",
            "steel_black_leg": "#4a4242",
        },
    },
    # Hazard paint: the black stripes read yellow where the bands are narrower than the
    # sprite's (the sampler finds the yellow under them).
    "artillery-turret": {
        "colors": {
            "hazard_black": "#312e2a",
        },
    },
    "artillery-wagon": {
        "colors": {
            "hazard_black": "#312e2a",
            "hazard_strong": "#c6970d",
            # The racked shells are brass in the sprite; the sampler took the dark rack round them.
            "brass": "#9c7d3c",
            "copper_dull": "#7a5636",
        },
    },
    # Laser turret: the base's frame is dark rusty steel (it read white off the head), the
    # head's bands a deeper ochre, the capacitor pale green.
    "laser-turret": {
        "colors": {
            "steel_light": "#66584e",
            "paint_ochre": "#be8639",
            "paint_green_pale": "#77a46e",
        },
    },
    # Flamethrower turret: the pale olive-grey tank, rusty gun body.
    "flamethrower-turret": {
        "colors": {
            "olive_steel": "#777867",
            "rust_dark": "#614c3f",
            "rust_brown": "#755641",
        },
    },
    # Land mine: ochre-rusty spikes and rim, a sage-grey pressure plate.
    "land-mine": {
        "colors": {
            "rust_brown": "#97713b",
            "rust_light": "#89846c",
            "rust": "#735d42",
        },
    },
    # Combat robots: the distractor's pale body (read as the dark fan), the destroyer's
    # blue-grey dome.
    "distractor": {
        "colors": {
            "copper_dull": "#948878",
            "steel_dark": "#5d5851",
        },
    },
    "destroyer": {
        "colors": {
            "steel_spider": "#86939f",
            "steel_dark": "#575d64",
            "copper_dull": "#896745",
        },
    },
    # Nuclear: the heat exchanger and turbine are pale grey-green (both read brown or dark off
    # their pipes and shadows), the exchanger's radiator plates copper-red.
    "heat-exchanger": {
        "colors": {
            "paint_heatex": "#737a6c",
            "copper_red": "#863c30",
            "steel_dark": "#51534c",
            "steel": "#6a6d63",
        },
    },
    "steam-turbine": {
        "colors": {
            "paint_heatex": "#8f9785",
            "steel_dark": "#5d6157",
        },
    },
    # Rocket silo: a blue-grey deck, copper hoses.
    "rocket-silo": {
        "colors": {
            # Darker and browner: the deck is weathered steel, rust streaked (the picture's mean
            # colour is a dark brown).
            "concrete_dark": "#46423c",
            "rust": "#5e3a26",
            "copper_hose": "#86573d",
            "hazard": "#a68219",
            # The yellow-green boxes and the blue control box sampled the grey deck round them.
            "paint_olive": "#6c6c42",
            "paint_blue": "#55708a",
        },
    },
    # The rocket and its cargo pod: silver-grey bodies, dark green panels.
    "rocket-silo-rocket": {
        # The sampler read the cage's frame, panels and fittings near black (they sit among the
        # sprite's shadows): the picture's rust-yellow frame, green louvres and red cables.
        "colors": {
            "rocket_white": "#4c4a42", "rust_brown": "#433424", "paint_green": "#36402c",
            "steel_light": "#57574f", "steel_dark": "#2b2a27", "paint_red": "#5c201b", "steel": "#444540",
        },
    },
    "cargo-pod": {
        "colors": {
            "rocket_white": "#5f615a",
            "paint_green": "#3c5538",
        },
    },
    # Landing pad: the red control tower (read grey), olive fan ring and boxes.
    "cargo-landing-pad": {
        "colors": {
            "paint_rose": "#754039",
            "paint_olive": "#545744", "olive_pale": "#858461", "paint_blue_dark": "#33475a",
            # The hub's pieces it shares: the shaft's rust ring, yellow tabs, cables.
            "rust_ring": "#43291f", "brass_yellow": "#9c8550", "wire_red": "#8a2f24", "wire_green": "#4a7c3a",
            "paint_blue": "#47627e",
        },
    },
    # Centrifuge: chrome rotor rings (the sampler found the dark gaps between them), pale cream
    # drums, dark olive machinery underneath.
    "centrifuge": {
        "colors": {
            "steel_polished": "#9b9e99",
            "paint_centrifuge": "#999985",
            "steel_dark": "#57574a",
        },
    },
    # Market: bright green corrugated walls and ribs (read grey off the shadow under the roof),
    # dark green scaffolds.
    "market": {
        "colors": {
            # The sprite's green is a dull olive (#44591b in shadow, #808a38 lit): it read neon. The walls face
            # the sun, so their albedo sits darker than the sprite's mid tone.
            "paint_market": "#43531c",
            "olive_dark": "#323f14",
            "paint_green": "#4c6c42",
        },
    },
    # Loader: the black arrow and corner bolts on the grey plate (read grey off the plate).
    "loader": {
        "colors": {
            "steel_black": "#252423",
        },
    },
    # Robots: a whiter logistic robot with red feet, a cream construction robot.
    "logistic-robot": {
        "colors": {
            "robot_white": "#b0b0ab",
            "robot_red": "#ab251e",
        },
    },
    "construction-robot": {
        "colors": {
            "robot_cream": "#c9c0a6",
        },
    },
    # Locomotive: the coiled hoses are brass and the ribbed dome a dark rusty red in the sprite (the
    # sampler took the pale highlights on the thin coils and the grey hood beside the dome).
    "locomotive": {
        "colors": {
            "brass": "#8c6d33",
            "rust": "#553a2e",
        },
    },
    # Wagons: Factorio's are darker and browner than the sampled roof and tanks read lit.
    "cargo-wagon": {"exposure": 0.78},
    "fluid-wagon": {"exposure": 0.82},
}
