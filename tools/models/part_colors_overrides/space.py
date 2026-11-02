"""Part colour tuning for the Space Age machines and buildings (space_platform.py, vulcanus.py,
fulgora.py, gleba.py machines, aquilo.py machines). Format: tools/models/PART_COLORS.md.

These models are built by hand from the sprites, so their parts rarely sit exactly where the
sprite paints them and the sampler's densest colour is often the sprite's shadowed mid-tone (or a
neighbour's colour). Where that misreads a part, its material is given the colour the sprite
paints it in its lit areas (picked from the sprite's pixels of that hue), so that the client's own
light and weathering bring back the shading. The values are albedos for the light balance of core
fix 1 (a top face shows about the stored colour), checked in the client from Factorio's view.
"""

OVERRIDES = {
    # --- Space platform ---------------------------------------------------------------------------
    # Cream plates over dark machinery: blue panels, yellow brackets and the upper ring's dark red
    # rim read black from the sampler (they're small and sit in shadow).
    "space-platform-hub": {
        "colors": {
            "paint_platform": "#ada48e", "paint_blue_dark": "#33475a", "brass_yellow": "#ab9051",
            "rust_ring": "#43291f", "rust": "#5d3925", "glass_blue": "#5d849c",
            # The shut lower hatch's stripes (platform-lower-hatch-front, frame 0): the hub's own
            # sprite shows the open shaft there, so the sampler finds only black.
            "hazard": "#9c7a2c", "hazard_black": "#24211e", "wire_red": "#8a2f24", "wire_green": "#4a7c3a",
        },
    },
    # Cream (the sampler took its shadowed grey), a rust-red grille.
    "cargo-bay": {
        "colors": {"paint_platform": "#a29985", "rust_brown": "#77463a", "brass_yellow": "#ab9051"},
    },
    # Orange flexible hoses over the engine (the sampler took the dark machinery round them).
    "thruster": {
        "colors": {"copper_dull": "#83482a", "paint_cream": "#a89f88", "paint_platform": "#a29985",
                   "wire_blue": "#3d5a9a", "wire_red": "#8a2f24", "wire_green": "#4a7c3a"},
    },
    # The arm is stowed inside the intake at rest, where the sprite shows the dark housing; its
    # links and head are pale steel and its fingers lined in brass (asteroid-collector-link.png
    # and -head.png, their lit pixels).
    "asteroid-collector": {
        "colors": {"steel_arm": "#8f8a84", "brass_arm": "#6e5630"},
    },
    # Light silver frame round the dark rollers.
    "crusher": {
        "colors": {"steel_platform": "#949497", "copper_dull": "#895d3d", "rust_brown": "#624531"},
    },
    # Its own picture is darker steel: the copper and rust as the north one's, the frame sampled.
    "crusher-east": {
        "colors": {"copper_dull": "#895d3d", "rust_brown": "#624531"},
    },
    # --- Vulcanus ----------------------------------------------------------------------------------
    # Rust-red chimney, green-grey panels, cream boxes; the sampler took everything to dark brown.
    "foundry": {
        "colors": {
            "paint_foundry_red": "#794130", "paint_foundry_green": "#55634e", "paint_foundry_cream": "#978b75",
            "steel_dark": "#413d3a", "rust_drill": "#5c3b2a", "copper_dull": "#7d5c47", "steel_light": "#91918b",
        },
        # Rebuilt with big lit surfaces (the plinth's top): darker, as the picture's machinery is.
        "exposure": 0.72,
    },
    # Red-brown rusted frame with red paint on its top beams.
    "big-mining-drill": {
        "colors": {
            "steel_dark": "#3c3935", "paint_foundry_red": "#713c2f",
            "steel_drill_teeth": "#423d3f", "paint_foundry_green": "#525e4c",
        },
        # The frame is one material: red rust on the top beams, grey-brown down the legs.
        "two_tone": ["rust_drill"],
        "exposure": 1.05,
    },
    # Lofted through rings measured from the sprites (creature_profiles.py), so the parts sit where
    # Factorio paints them: every corner takes the colour under it (rock, the lava in its seams, the
    # head's bone mandibles).
    "demolisher-*": {"two_tone": "*", "two_tone_blur": 0.2},
    # A grey machine whose sprite is mostly dark crevices round bright riveted plates: the sampler
    # took the crevices (the whole turret read black in the client, the helmet too).
    "tesla-turret": {
        "colors": {
            # The sprite's grey is deep in shadow between the machinery: darker than its lit panels.
            "steel_platform": "#58595d", "steel_dark": "#34353a", "steel_light": "#85878a",

            "steel_black": "#26272a", "copper_coil": "#7c4c31", "rust_brown": "#62422f",

            "paint_blue_dark": "#41526c",
        },
    },
    # Fulgora's blue paint over dark steel and copper-brown pipework.
    "electromagnetic-plant": {
        "colors": {"paint_fulgora_blue": "#44557a", "copper_coil": "#885639", "paint_fulgora_cream": "#cfc6c0",
                   "rust_brown": "#6a3d2c", "brass": "#7a6846", "wire_yellow": "#c8a032"},
        # The detailed housings show more lit faces than the sprite's shaded ones: a little darker.
        "exposure": 0.85,
    },
    # A steel-blue ring and column (the sampler took the ring's grey shadows), olive domed tanks,
    # bone-white tanks.
    "fusion-reactor": {
        "colors": {
            "paint_fusion": "#586c82", "paint_aquilo_dark": "#465667", "olive_steel": "#646152",
            "paint_bone": "#b1ac9f", "steel_cold": "#74797e", "brass_dull": "#74644a",
            # The ribbed hoses are the sprite's dull yellow (the thin hoses sampled the dark gaps).
            "hazard": "#8f7d3c", "wire_red": "#8a3a2c", "wire_green": "#4f7a3a", "wire_yellow": "#a8903c",
        },
    },
    # The same blue as the reactor, olive tanks, an orange band of coils.
    "fusion-generator": {
        "colors": {
            "paint_fusion": "#586c82", "olive_steel": "#646152", "copper": "#82573f",
            "brass_dull": "#74644a", "steel_cold": "#74797e", "hazard": "#8f7d3c",
        },
        "exposure": 0.85,
    },
    # Teal-blue paint (the sampler took the grey-beige of its hoses and shadows), tan hoses.
    "cryogenic-plant": {
        "colors": {
            "paint_aquilo": "#57787a", "paint_aquilo_dark": "#455e63", "steel_cold": "#777d7e",
            "hose_tan": "#836e4e", "steel_dark": "#484645", "paint_bone": "#b3afa2",
        },
    },
    # Mossy green paint mottled with rust, not the palette's olive-yellow.
    "recycler": {
        # Darker than the paint's own colour: the sprite's green is worn through to rust in most places.
        "colors": {"paint_recycler_green": "#545634", "rust_recycler": "#5a3b2e"},

    },
    # --- Gleba ---------------------------------------------------------------------------------------
    # Bright orange ribbed hoses, a dark smoked-glass dome, green column.
    "agricultural-tower": {
        "colors": {
            "hose_orange": "#b0622a", "glass_smoke": "#3f423b", "paint_gleba": "#626c3c",
            "copper_pipe_dark": "#533f30", "copper_pipe": "#78563f",
        },
    },
    # Violet-grey steel with copper pipes and brass burners (the sampler took it to brown).
    "heating-tower": {
        "colors": {
            "steel_violet": "#564b56", "steel_violet_dark": "#3b343a", "copper_pipe": "#80513a",
            "copper_pipe_dark": "#594235", "brass_dull": "#87683f",
            # Glowing parts (their material's colour is the glow's): the copper and barrel at rest.
            "copper_hot": "#80513a", "ember": "#594235",
        },
    },
    # A pink-purple brain under a weathered steel cage; the machinery round it is rusty
    # brown-grey, the tube a deep blue (the sampler took the steel to a clean pale grey).
    "biolab": {
        "colors": {
            "flesh_pink": "#8b6372", "flesh_purple": "#6d526f", "flesh_dark": "#5c424b",
            "steel_teal": "#6b6560", "steel_dark": "#3f3632", "glass_pale": "#a39c90", "glow_cyan": "#3f6c9c",
            "glass_bulb": "#a39c90",  # the brain's bulbs at rest (they glow blue-violet while working)
        },
    },
    # Peach flesh with dark brown folds and claws, pale pads in reddish rims, black hoses.
    "captive-biter-spawner": {
        "colors": {"flesh_tan": "#8c5c3e", "flesh_dark": "#4c3020", "steel_teal": "#717a78", "flesh_pad": "#b4947c",
                   "flesh_red": "#84483a", "rubber": "#2b2826"},
    },
    # Gunmetal plates over dark machinery, rust-brown hoses and toothed ring, a pale green tank
    # (the sampler took the green and the rust to grey).
    "rocket-turret": {
        "colors": {"steel_grey": "#636263", "steel_grey_dark": "#3e3d3e", "rust_brown": "#694633",
                   "paint_green": "#7b8a68", "steel_black": "#262626"},
    },
    # Teal-green metal body under the pale ribbed capsule; black hoses (the thin hoses took the
    # tanks' grey), orange copper rails in the hatch and a verdigris-green plate on the rusty front.
    "capture-robot": {
        "colors": {"steel_teal": "#676f69", "paint_bone": "#a09c93", "brass": "#a8742e", "rubber": "#2b2826",
                   "copper_pipe": "#8f5a2c", "paint_green": "#61806f"},
    },
}

# Stack inserter (Wube's inserter base): worn dark steel with a rusty brown turntable; the shared
# Wube tuning's saturation left it a pale cool grey.
# The turntable is the sprite's worn grey-brown (the mean of its pixels over the four pictures, as
# the other tiers' in wube.py), not rust.
for _sfx in ("", "-east", "-south", "-west"):  # a model per direction (wube_recipes.py)
    OVERRIDES["stack-inserter" + _sfx] = {"saturation": 1.2,
                                          "sprite_colors": {"steel_light": "#776f6c", "bronze": "#837263"}}
