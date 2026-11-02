"""Part-colour tuning for nature on every planet (tools/models/PART_COLORS.md): Nauvis trees,
rocks, ores and crude oil; Vulcanus, Fulgora and Aquilo terrain features; asteroids; Gleba
plants, spawners and pentapods.

Organic and rocky models aren't flat paint: by default every part takes the sprite's colour round
where each corner lands, heavily blurred (two_tone), so canopies, rocks and flesh are mottled the
way the sprite is instead of one colour per material. Where the sampled colour is wrong (parts
that don't sit where the sprite has them: ores and scrap, one model for every variation; small
parts the sampler misses; two-coloured rocks whose average is the grey between) the colour is
picked from the sprite's own palette (its mid tones) and given as `sprite_colors`.
"""

import importlib.util
import os

SOFT = {"two_tone": "*", "two_tone_blur": 0.3}


def _tree_trunks():
    """nature/tree_trunks.py (fit_trunks.py's numbers), loaded by path: tools/models/nature has
    modules named like tools/models' own (compare.py), so it can't go on sys.path here."""
    path = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "nature", "tree_trunks.py")
    spec = importlib.util.spec_from_file_location("tree_trunks", path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


TREE_TRUNKS = _tree_trunks()
# Height fields fitted to the sprite's silhouette have a vertex every 1/8 tile: a finer blur
# carries the sprite's light and dark patches onto them.
FINE = {"two_tone": "*", "two_tone_blur": 0.1}

FAMILY = [
    # Nauvis
    "tree-0[1-9]", "tree-0[1-9]-*", "dead-dry-hairy-tree", "dead-grey-trunk", "dead-tree-desert", "dry-hairy-tree", "dry-tree",
    "big-rock", "huge-rock", "big-sand-rock", "crude-oil",
    # Vulcanus
    "ashland-lichen-tree*",
    # Fulgora
    "fulgurite*",
    # Space
    "*-carbonic-asteroid", "*-metallic-asteroid", "*-oxide-asteroid", "*-promethium-asteroid",
    # Gleba
    "yumako-tree", "jellystem", "cuttlepop", "slipstack", "funneltrunk", "hairyclubnub", "teflilly", "lickmaw",
    "stingfrond", "boompuff", "sunnycomb", "water-cane", "gleba-spawner*", "*-stomper-pentapod", "*-strafer-pentapod",
    "big-wriggler-pentapod",
    # Aquilo
    "lithium-iceberg-*", "lithium-brine", "fluorine-vent",
]

OVERRIDES = {pattern: dict(SOFT) for pattern in FAMILY}
# Pentapods: the torsos are lofted where their sprites draw them (creature_hull.py); the legs reach
# far past the torso pictures, which leave them out, and would only pull the fit off.
for _pattern in ("*-stomper-pentapod", "*-strafer-pentapod"):
    OVERRIDES[_pattern]["align"] = 0
for _pattern in ("*-volcanic-rock", "*-volcanic-rock-hot", "fulgoran-ruin-*"):
    OVERRIDES[_pattern] = dict(FINE)

OVERRIDES.update({
    # Dead wood and rocks: the sprites' are weathered grey-brown and deeply shadowed; the sun lit
    # ours pale, smooth and yellow (judged against the sprites in the client's shots).
    **{_n: dict(SOFT, exposure=0.72, saturation=0.8) for _n in ("dead-dry-hairy-tree", "dead-tree-desert",
                                                               "dry-hairy-tree", "dry-tree")},
    **{_n: dict(SOFT, exposure=0.85, saturation=0.9) for _n in ("big-rock", "huge-rock")},
    "big-sand-rock": dict(SOFT, exposure=0.72, saturation=0.7),
    # Nauvis. The weeping tree's leaves hang where its sprite has bark: olive green, as the sprite.
    # Leafy crowns (trees.leafy_crown): their cards' light and shade come from the model, and the
    # sun lights them brighter than the sprite's dark, muted leaves: darker and duller.
    **{"tree-0%d%s" % (_i, _v): dict(SOFT, exposure=0.62, saturation=0.85) for _i in (1, 2, 3, 4, 7, 8, 9)
       for _v in ("", "-*")},
    "tree-05": dict(SOFT, exposure=0.55, saturation=0.85),
    # Their bark: the trunk sprite's own mid tone (fit_trunks.py), as an albedo, so the leaves'
    # darkening above doesn't reach it and the leaves over the trunk in the sprite don't tint it;
    # the grooves and ridges are in the model's corner colours.
    **{"tree-0%d%s" % (_i, _v): dict(SOFT, exposure=0.55 if _i == 5 else 0.62, saturation=0.85,
                                    colors={"bark-0%d" % _i: TREE_TRUNKS.BARK["tree-0%d" % _i][1]})
       for _i in (1, 2, 3, 4, 5, 7, 8, 9) for _v in ("", "-*")},
    "tree-06": dict(SOFT, sprite_colors={"leaf-06": "#56602e"}),
    # Colour variants (the same models, their own leaf tint): the brown weeping tree's leaves hang
    # where the sprite has bark, like tree-06's, so its colour is picked from the sprite too.
    "tree-06-brown": dict(SOFT, sprite_colors={"leaf-06": "#6a4826"}),
    "dead-grey-trunk": dict(SOFT, sprite_colors={"wood-grey-trunk": "#6d5a3e"}, exposure=0.72, saturation=0.8),

    # Ores: one model for every variation, so its chunks don't sit on the sprite's: no two-tone
    # (it paints chunks with the dirt between them), chunks and dust in the sprite's colours.
    "iron-ore": {"sprite_colors": {"iron-ore-chunk": "#6f8590", "iron-ore-dust": "#3a2e24"}},
    "copper-ore": {"sprite_colors": {"copper-ore-chunk": "#c05b39", "copper-ore-dust": "#442015"}},
    "stone": {"sprite_colors": {"stone-chunk": "#8c7748", "stone-dust": "#382e1f"}},
    "coal": {"sprite_colors": {"coal-chunk": "#36332f", "coal-dust": "#231d14"}},
    # Uranium: the sprite's crystals are a deep green lit at the edges, not neon.
    "uranium-ore": {"exposure": 0.7, "saturation": 0.8},

    # Vulcanus. Chimneys: rings round the crater; the sulfur crust and the stain it leaves down the
    # rock are bands of their own in the model (space_nature.revolve).
    # Their outlines are fitted (space_profiles.RINGS), so the sprite's pale slabs and dark
    # clefts land on the rock: every corner takes the colour under it.
    "vulcanus-chimney*": {"two_tone": "*", "two_tone_blur": 0.12},
    "vulcanus-chimney": {"sprite_colors": {"stone_chimney_stain": "#4e3c2c"}},
    "vulcanus-chimney-faded": {"sprite_colors": {"stone_sulfur": "#5e5444"}},
    # The sulfur crust is an ochre, duller than the lemon it read in the client.
    "sulfuric-acid-geyser": dict(FINE, sprite_colors={"soot": "#2a2109"}, saturation=0.82),

    # Fulgora. Scrap: one model for every variation (and turned at random): the sprite's paint
    # and metal.
    "scrap": {"sprite_colors": {"paint_scrap_red": "#6a2826", "paint_scrap_blue": "#435573", "rust": "#4a3226",
                                "rust_brown": "#3e3024", "steel_dark": "#313233", "steel": "#55554f",
                                "paint_scrap_mark": "#a99b59"},
              # The client's sun lit the paint clean and bright; the sprite's is dull and grimy.
              "exposure": 0.8},
    # Fulgurite: dark crimson glass under a dusty crust (the client's fulgurite class speckles it).
    "fulgurite*": dict(SOFT, exposure=0.62, saturation=1.1),

    # Asteroids: the sampled colour of a two-coloured rock is the grey between them; their own
    # colours instead, the rock's and its veins', without two-tone (it pulled them back to the
    # grey). The veins are single faces with hard edges, so their colour sits only a step from the
    # rock's (the sprite's specks and veins are fine).
    # Darker than their mid tones (exposure): the client's sun lit them pale and clean, and the
    # sprites are pitted and shadowed all over; promethium's red is a deep crimson.
    "*-carbonic-asteroid": dict(exposure=0.9, sprite_colors={"rock_carbonic": "#5a565b", "rock_carbonic_vein": "#78765e"}),
    "*-metallic-asteroid": dict(exposure=0.9, sprite_colors={"rock_metallic": "#4e555c", "rock_metallic_vein": "#7a5a4a"}),
    "*-oxide-asteroid": dict(exposure=0.9, sprite_colors={"rock_oxide": "#546769", "rock_oxide_vein": "#6c7e84"}),
    "*-promethium-asteroid": dict(exposure=0.85, saturation=0.8, sprite_colors={"rock_promethium": "#5e2c32", "rock_promethium_vein": "#7a5a5c"}),

    # Gleba plants: grown along their sprites' skeletons (gleba.skeleton_plant), so every part
    # lands on its own place in the sprite; the fine blur carries the sprite's mottling onto them.
    **{_n: dict(FINE) for _n in ("yumako-tree", "jellystem", "cuttlepop", "slipstack", "funneltrunk", "hairyclubnub",
                                 "teflilly", "lickmaw", "stingfrond", "boompuff", "sunnycomb", "water-cane")},
    # Lickmaw's and funneltrunk's flesh is a deep crimson and a dark olive in their sprites; the sun
    # lit them pale pink and khaki.
    "lickmaw": dict(FINE, exposure=0.72, saturation=1.1),
    "funneltrunk": dict(FINE, exposure=0.8),

    # Aquilo: pale ice round darker blue, not the other way round.
    # The icebergs are fitted to their silhouettes: sampled finely, they keep the sprite's pale ridges.
    "lithium-iceberg-*": dict(FINE, exposure=1.3),
    # The vent: a white frost plate round the pit (the plate was dark blue), the pit's slabs
    # blue-grey with the dark crack across them.
    "fluorine-vent": dict(SOFT, sprite_colors={"ice": "#c3cbdc", "ice_blue": "#7480a2", "ice_shadow": "#4c5a82"}),
    # The brine's rim is snow-white round the pool.
    "lithium-brine": dict(SOFT, sprite_colors={"ice": "#d4dbdf", "ice_blue": "#acbac2"}, exposure=1.15, saturation=0.85),
})
# The ores' richest and poorest stages (nature/rocks.py STAGES) are coloured as their middle one,
# from its sprite.
for _ore in ("iron-ore", "copper-ore", "stone", "coal", "uranium-ore"):
    for _stage in ("-rich", "-sparse"):
        OVERRIDES[_ore + _stage] = dict(OVERRIDES[_ore], entry=_ore)
