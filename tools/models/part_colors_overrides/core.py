"""Core part-colour tuning (the core session's file): models with no sprite entry of their own.

Belts, their curves, undergrounds and loaders: Factorio's frames and grey belt, measured from
transport-belt.png and underground-belt-structure.png and given as sprite colours, so they get
the same light correction and grading as sampled ones. A belt's frame is bare dark steel (the
belt sheet has no paint on it: its tier shows in the yellow chevrons, which the client's shader
draws on the slats); an underground's hood is the tier's paint. Faster undergrounds and splitters
reuse these models with their `tier_paint` recoloured by the client (model_library.gd
TIER_TINTS); faster belts keep the steel and take their own chevrons (BELT_CHEVRONS).
"""

# The frame's mid tone along a belt's side (east-facing frames, rows of rivets and all), the slats'
# median.
BELT = {"tier_paint": "#4b4341", "belt_surface": "#615450"}
# The loader's frame keeps the yellow of the old belts' rails until it has its own measurement.
LOADER = {"tier_paint": "#fcbe01", "belt_surface": "#615450"}
# The hood: its mid tone (the densest sample, #e2b953, is the lit top and reads pale on the model).
UNDERGROUND = {"tier_paint": "#d6a32e", "belt_surface": "#4f4844"}

OVERRIDES = {
    "transport-belt": {"sprite_colors": dict(BELT)},
    "transport-belt-curve-*": {"sprite_colors": dict(BELT)},
    "underground-belt-*": {"sprite_colors": dict(UNDERGROUND)},
    "loader": {"sprite_colors": dict(LOADER)},
}
