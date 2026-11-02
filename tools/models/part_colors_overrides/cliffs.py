"""Part-colour tuning for the cliffs on every planet (tools/models/nature/cliffs.py; format in
tools/models/PART_COLORS.md).

Like the rocks: the stone takes the sprite's colour round where each corner lands, heavily
blurred, so faces are mottled light and dark as the sprites' broken columns and strata are.
Each piece is sampled only from its own orientation's picture (cell 0, the model facing north):
the other three are the same model turned, and seen from the high side the sprites show little
but the crest.
"""

SOFT = {"two_tone": "*", "two_tone_blur": 0.3, "cells": [0]}

OVERRIDES = {"cliff-*": dict(SOFT)}
OVERRIDES.update({
    # Gleba's roots are thin tubes the sampler rarely finds: the sprite's orange.
    "cliff-gleba-*": dict(SOFT, sprite_colors={"cliff-gleba-flesh-root": "#9a6224"}),
})
