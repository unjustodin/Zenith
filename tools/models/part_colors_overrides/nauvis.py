"""Part-colour tuning for the procedural Nauvis buildings (machines.py, power.py, fluids.py,
electric.py, oil.py, circuits.py, logistics.py, defence.py, rails.py, railway.py and the splitter).
Format: tools/models/PART_COLORS.md. Forced colours are mostly `sprite_colors`: picked from the
sprite (the median of its pixels of that hue, or of the part where it can be found) and corrected
for light like a sampled colour. Force only what the sampler can't find: thin parts lying on
another colour, parts whose sprite has no picture.
"""

# Circuit wires, picked from the combinators' sprites (their red and green wires).
WIRE_RED = "#7a2520"
WIRE_GREEN = "#3a6a26"
WIRES = {"rubber_red": WIRE_RED, "rubber_green": WIRE_GREEN}

# Pipes: the sprite's steel is a grey-brown with a bright highlight band; the bend and the caps
# sampled that highlight and came out cream next to brown pipe. One steel for the whole kit, the
# valves included, as albedo: `sprite_colors` corrects each patch by its average facing, and a
# pipe's whole round barrel is one patch whose average normal points nowhere in particular (the
# straight pipe came out near black beside a pale cap).
PIPE_STEEL = "#7a6e5a"
# The flanges: as the cross sampled them (the straight pieces' came out near black).
PIPE_FLANGE = "#685542"
PIPE = {"steel": PIPE_STEEL, "rust_brown": PIPE_FLANGE}

# Elevated rails: their sprite entry is the track only, so the deck under it would sample the
# rails' colours. Factorio's deck (elevated-rail-base) is a dark brown-grey with a red railing
# (elevated-rail-fence); the rail ramp's deck wears the same.
DECK = {"steel_dark": "#3a2e25", "paint_rail_red": "#b25648"}

OVERRIDES = {
    # Combinators and the other circuit boxes: red and green wires.
    "*-combinator": {"sprite_colors": dict(WIRES)},
    "power-switch": {"sprite_colors": dict(WIRES)},
    "programmable-speaker": {"sprite_colors": dict(WIRES)},
    "display-panel": {"sprite_colors": dict(WIRES)},

    # The splitters' gearbox lid is the sprite's dark grey (it sampled the brown of the rack and
    # chain round it).
    "splitter": {"sprite_colors": {"steel_dark": "#47413f"}},
    "lane-splitter": {"sprite_colors": {"steel_dark": "#47413f"}},

    "pipe": {"colors": dict(PIPE)},
    "pipe-*": {"colors": dict(PIPE)},
    "pipe-to-ground": {"colors": dict(PIPE)},
    # Valves: the housing's top and front fill the picture's plate (circuits.py), so the black
    # markings sample from it; the pipe under it, hidden in the picture, is the kit's. The plate's
    # grey sampled near white in the client's sun: a shade darker (#686b6a before read too dark).
    "*-valve": {"colors": dict(PIPE, steel_light="#9b9581", paint_valve="#8a8d8c")},
    "*-valve-*": {"colors": dict(PIPE, steel_light="#9b9581", paint_valve="#8a8d8c")},

    # The four drums are one blue-grey; the north-east one sampled the red and yellow cables lying
    # over it and came out pink.
    "accumulator": {"sprite_colors": {"blue_steel": "#58606e"}},
    # Gears and fittings on the head sampled the sprite's highlights and read white from above.
    "burner-mining-drill*": {"sprite_colors": {"steel_light": "#625f57", "bronze": "#625f57"}},
    # The dome's struts are cream-bronze in the sprite; they sampled the dark glass between them.
    "lab": {"sprite_colors": {"frame_cream": "#bba083"}},
    # Corrugated hoses: the sprite's are a bright copper-orange, the sample a dull brown.
    "offshore-pump*": {"sprite_colors": {"rust_orange": "#a6725a"}},
    # The ochre collar round the hatch and the bands, the blue arms and their red cables: thin
    # or dark-shadowed in the sprite, sampled as the dark body.
    "roboport": {"sprite_colors": {"paint_robo": "#9e8240", "paint_robo_blue": "#485f82", "rubber_red": "#641a1a"}},
    "radar": {"sprite_colors": {"bronze": "#7a6444"}},
    "beacon": {"sprite_colors": {"rubber_red": "#70362f", "copper_hose": "#5c3a28", "cable_tan": "#9a8060"}},
    # The base's sprite is pipes on a dark ground plate, so they sampled near black; the beam and
    # horse head are Factorio's dark green (pumpjack-horsehead), which the sample browned.
    "pumpjack*": {"sprite_colors": {"iron_rust": "#4f473e", "paint_green": "#34491f", "olive_dark": "#232a16"}},
    # The chemical plant's tanks and lids are a warm yellow-orange in every picture; sampled one
    # direction at a time, the yellow took the brown of the pipes crossing it.
    "chemical-plant*": {"sprite_colors": {"hazard": "#a8721e"}},
    # Rust running down the pale tanks.
    "steam-engine*": {"two_tone": ["tank_grey"]},
    # The name board is in the station's colour, a mask Factorio tints at runtime (default red);
    # the sprite the sampler reads is the grey one under it.
    "train-stop": {"colors": {"paint_stop": "#b03426"}},
    # Yellow and black hazard stripes; the sample greyed the yellow to mud.
    "gate": {"sprite_colors": {"hazard": "#a08650", "hazard_black": "#2a2620"}},
    "elevated-*": {"sprite_colors": dict(DECK)},
    # The ramp has no sprite entry (its picture smears over the embankment): the ground rails'
    # ballast, ties and rails, the elevated deck, and the supports' stone, as those models sampled
    # them (area-weighted albedo).
    "rail-ramp": {"sprite_colors": dict(DECK), "colors": {
        "stone_ballast": "#5c544a", "stone_ballast_light": "#564e44", "wood_tie": "#98772e", "steel_light": "#6a635c",
        "steel_rail": "#8f8f8f", "stone_block": "#59493c", "steel": "#504c4a"}},
    # The rail signal's bent mounting plates are bright bare steel in the sprite (its brightest
    # grey pixels), the housings dark; the plates are thin and sampled the shadow under them.
    "rail-signal": {"sprite_colors": {"steel_light": "#bdbeb9"}},
}
