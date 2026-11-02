"""An example of a family's tuning for tools/models/part_colors.py (files starting with "_" are
not loaded). Copy it to <family>.py in this folder, one file per family, so no two people edit the
same file. Format and keys: tools/models/PART_COLORS.md.
"""

OVERRIDES = {
    # Every logistic chest: their coloured lids are one patch with the frame round them, so let
    # the corners take the sprite's colour where they land (soft, blurred), on that material only.
    "*-provider-chest": {"two_tone": ["paint_logistic"]},
    # One model: sample only the north picture, nudge it less, treat two rusts as one material,
    # split patches at gentler edges, and paint the glass a fixed colour.
    "oil-refinery": {
        "cells": [0],
        "align": 3,
        "merge_materials": [["rust", "iron_rust"]],
        "crease": 25,
        "colors": {"glass_dark": "#22303a"},
    },
}
