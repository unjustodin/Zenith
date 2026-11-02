"""Part colour tuning for the models converted from Wube's printable files (tools/models/wube.py),
the crash site and the fish. Format: tools/models/PART_COLORS.md.

The dense converted models gather their colours from many small patches that each pick their lit
paint, and came out greyer than their sprites: the machines and chests are saturated a little
and take the sprite's colour round each corner (`two_tone`) for the paint's variation inside one
print piece.

The fish has no entry: Factorio draws it as a see-through black shape under the water, so nothing
can be sampled; it keeps its dark palette colour.
"""

_CHESTS = ("wooden-chest", "iron-chest", "steel-chest", "passive-provider-chest", "active-provider-chest",
           "storage-chest", "buffer-chest", "requester-chest")
_INSERTERS = ("burner-inserter", "inserter", "long-handed-inserter", "fast-inserter", "bulk-inserter",
              "stack-inserter")

OVERRIDES = {
    # The wall pieces stand side by side, but each samples its own picture: a north-south piece
    # sees mostly lit tops, an east-west one its dark front. One colour for all of them, picked
    # from the east-west sprite: its dark, grimy face (its darkest common shade: the face came out
    # light) and its pale cap.
    "stone-wall*": {"sprite_colors": {"concrete_wall": "#2c261f", "concrete_wall_top": "#b6ac9f"}},
    "assembling-machine-1": {"two_tone": "*", "saturation": 1.5},
    # Ochre stones: the sprite's flanks and bricks are strongly yellow.
    "stone-furnace": {"two_tone": "*", "saturation": 1.8},
    "steel-furnace": {"two_tone": "*", "saturation": 1.5},
    # The creatures' and the character's paint is strongly coloured in their sprites (red-brown
    # flesh, the orange suit) and came out pale.
    "biter-spawner": {"two_tone": "*", "saturation": 1.4},
    "big-worm-turret": {"saturation": 1.5},
    "character": {"saturation": 1.5},
    "character-gun": {"saturation": 1.5},
    # Armour looks (armour_looks.py): the dark plates, the visor and the helmet sampled brown from
    # the orange and shade round them; picked from the add-ons' sprites (the paint is the mask's
    # one player colour, Factorio's default orange).
    "character-armor-2": {"saturation": 1.5, "colors": {"armour_visor": "#1b1c1e", "armour_paint": "#c4692a"}},
    "character-armor-3": {"saturation": 1.5, "colors": {"armour_dark": "#3e4044", "armour_visor": "#1b1c1e",
                                                        "armour_paint": "#c4692a"}},
}
for _chest in _CHESTS:
    OVERRIDES[_chest] = {"two_tone": "*", "saturation": 1.3}
# The logistic chests' dark steel body took on their paint's colour; the storage chest's gold
# came out khaki. Both picked from the sprites.
for _chest in _CHESTS[3:]:
    OVERRIDES[_chest]["sprite_colors"] = {"olive_dark": "#2d2d25"}
OVERRIDES["storage-chest"]["sprite_colors"]["logistic_yellow"] = "#a8860e"
# Inserter platforms: strongly coloured paint (yellow, red, blue, green) that came out pale.
# Few of the thin platform's patches are seen whole at sprite size, so the samples swung with
# each refit (the burner's dark legs came out orange-brown): the paint and the turntable are
# the mean colours (linear light) of the legs (outside the ring) and of the turntable over the
# four pictures (tier paint, turntable).
_PLATFORM_PAINT = {
    "burner-inserter": ("rust_light", "#594a45", "#907a66"), "inserter": ("inserter_yellow", "#a26813", "#a9835a"),
    "long-handed-inserter": ("inserter_red", "#98251c", "#a5725c"),
    "fast-inserter": ("inserter_blue", "#2f6891", "#888384"), "bulk-inserter": ("inserter_green", "#618529", "#928e5f"),
}
for _name in _INSERTERS:
    for _sfx in ("", "-east", "-south", "-west"):  # a model per direction (wube_recipes.py)
        OVERRIDES[_name + _sfx] = {"saturation": 1.4}
        if _name in _PLATFORM_PAINT:
            _mat, _paint, _table = _PLATFORM_PAINT[_name]
            # Picked colours need less extra saturation than sampled ones.
            OVERRIDES[_name + _sfx] = {"saturation": 1.2, "sprite_colors": {_mat: _paint, "bronze": _table}}

# The crash site: worn yellow paint over grey and burnt steel. Built from slabs, so the sprite's
# patches of bare metal, scorch and lit paint come back as soft regions round each corner
# (`two_tone`). The cargo pods' barrels sampled their shadowed side and came out brown: Factorio's
# are a grimy olive-gold (the mid tone under their highlights) with dark bands.
# The plate seams cut as grooves (crash_site.py `_groove_finish`) keep the sprite's dark seam colour:
# sampled, their pixel-wide channels would take the paint either side.
OVERRIDES["crash-site-*"] = {"two_tone": "*", "two_tone_blur": 0.06, "sprite_colors": {"soot_seam": "#2c2311"}}
# The ship's panelled skin: its seams are the sprite's dark grime lines, its paint the saturated,
# worn yellow between them (the sampler alone took a pale tan from the lit plates). Its plates are
# a clean gold: their soft regions only lighten and darken them, keeping little of the olive and
# green the sprite's straps, machinery and shadows put round them (`two_tone_tint`).
OVERRIDES["crash-site-spaceship"] = {"two_tone": "*", "two_tone_blur": 0.15, "saturation": 1.1, "exposure": 0.82,
                                     "two_tone_tint": {"wreck_yellow": 0.4, "wreck_yellow_side": 0.4},
                                     "sprite_colors": {"steel_scorched": "#2b2722", "soot_seam": "#2c2311"}}
for _pod in ("crash-site-chest-1", "crash-site-chest-2"):
    OVERRIDES[_pod] = {"two_tone": "*", "two_tone_blur": 0.06,
                       "sprite_colors": {"wreck_yellow": "#524629", "steel_burnt": "#3a3126"}}
# The second pod lies in the light: its paint the brighter olive-gold of its lit plates.
OVERRIDES["crash-site-chest-2"]["sprite_colors"]["wreck_yellow"] = "#6a5733"
OVERRIDES["crash-site-chest-2"]["exposure"] = 1.3
# The torn rib and the radiator are dark rust and soot all over; the sampler took their lit edges.
OVERRIDES["crash-site-spaceship-wreck-small-4"] = {"two_tone": "*", "two_tone_blur": 0.06,
                                                   "sprite_colors": {"rust_brown": "#3d3025"}}
OVERRIDES["crash-site-spaceship-wreck-medium-1"] = {"two_tone": "*", "two_tone_blur": 0.06,
                                                    "sprite_colors": {"steel_burnt": "#4c4031"}}
# The loose yellow plates lie in the light: Factorio's are a bright, clean gold, the sampler's
# average of lit plate and dark seam a duller tan.
OVERRIDES["crash-site-spaceship-wreck-small-6"] = {"exposure": 1.15}
OVERRIDES["crash-site-spaceship-wreck-small-1"] = {"exposure": 1.1}
OVERRIDES["crash-site-spaceship-wreck-medium-3"] = {"exposure": 1.1}
