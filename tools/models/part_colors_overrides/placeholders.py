"""Part colours for the placeholder audit's models (tools/models/placeholders.py)."""

from .core import BELT

LEGACY_RAIL = {"stone_ballast": "#5c554b", "stone_ballast_light": "#564e45", "wood_tie": "#98772f",
               "steel_dark": "#595654", "steel_light": "#6a645c", "steel_rail": "#909090"}

OVERRIDES = {
    # The 1x1 loader is the loader squeezed: the same belt-tinted sides.
    "loader-1x1": {"sprite_colors": dict(BELT)},
    # Legacy rails share the 2.x rails' materials; their own sheets are per-direction files the
    # sampler doesn't read, and the 2.x sprites fit their shapes badly. They take the colours the
    # 2.x straight rail sampled from its sprite (its TEXCOORD_4/5 per material, as sRGB).
    "legacy-*-rail*": {"colors": dict(LEGACY_RAIL)},
    # The ruin's iron band is green-pink in the sprite; sampled, its thin top reads brick brown.
    # Fitted to the sprite's outline like the ruins (space_nature.heightfield): every corner takes
    # the sprite's colour where it lands, finely blurred, for the carved blocks and patches.
    "fulgora-sunk-ruin-big": {"sprite_colors": {"rust_ruin_green": "#4b5f4c"}, "two_tone": "*", "two_tone_blur": 0.1},
    # Grown along its sprite's skeleton like the Gleba plants: the sprite's mottling, finely.
    "tree-plant": {"two_tone": "*", "two_tone_blur": 0.1},
}
