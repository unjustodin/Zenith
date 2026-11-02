# Part colours: how to run the tool and tune a family

`tools/models/part_colors.py` gives every part of a model its own colour, sampled once from
Factorio's sprite, and stores it in the model's `.glb` (`TEXCOORD_4`/`_5`, the shader's
`CUSTOM1`). The client's default look ("Factorio colours", Settings → Graphics → Model look)
draws those colours with light weathering; "Factorio sprite projected" is the old look. How the
colours are chosen is in the tool's docstring and in `client/assets/models/README.md` (Materials).

## Running it

Needs the venv (numpy, scipy, pillow, trimesh) and a Factorio install (default Steam path, or
`--factorio DIR` / the `FACTORIO` environment variable). Models with an entry in
`client/data/sprite_projection.json` (or in `DONORS`) are sampled. A model without one is
coloured only if an override gives it an `entry` to sample or forced `colors`/`sprite_colors`
(the rest of it keeps its palette); belts, undergrounds and the loader get theirs from
`part_colors_overrides/core.py`.

```bash
python tools/models/part_colors.py lab boiler            # colour these models (writes the .glb)
python tools/models/part_colors.py lab --check           # report only, write nothing
python tools/models/part_colors.py lab --check --debug DIR   # DIR/<name>.png: sprite | sampled colours relit
python tools/models/part_colors.py                       # every model (only the core session does this)
godot --headless --path client --import                  # then re-import, as after any .glb change
```

Each line it prints: patches, how many were seen, `own colours` (a well-fitting Wube conversion:
every patch keeps its sampled colour) or `by material` (hand-built models: each material snaps to
the sprite's colour nearest its palette colour), the silhouette fit per picture with the nudge in
pixels, and `tuned: ...` when an override applies. Re-running is safe: it overwrites its own data
in place. Run it again after anything rewrites a `.glb` (`build.py`, `build_nature.py`; `wube.py`
runs it itself). The `--debug` pictures show Factorio's sprites: keep them in `art-src/` or a
scratch folder, never in the repo.

Look at the result in the client: `python tools/models/review.py <names> --port <yours>
--views factorio,south,east --out <scratch dir>` (`--client-arg=--model-look=sprite` shows the
old projected look for comparing, `palette` the plain palette).

## Overrides: one file per family

`tools/models/part_colors_overrides/<family>.py` (any name not starting with `_`) defines
`OVERRIDES = {pattern: {key: value}}`. A pattern is a model name or an `fnmatch` pattern
(`"stone-wall-*"`); every matching entry applies, an exact name last. See `_example.py`.

| Key | Value | Effect |
|---|---|---|
| `cells` | list of picture indices | sample only these pictures (direction entries: 0 N, 1 E, 2 S, 3 W; rotation entries: every eighth frame, 0 = north) |
| `align` | int, pixels | how far the model may be nudged to fit the sprite's silhouette (default 5; 0 = never) |
| `crease` | degrees | patches split at edges bending more than this (default 35): lower splits more, higher merges |
| `merge_materials` | list of lists of material names | sample and colour each group as one material |
| `free` | bool | `true`: every patch keeps its own sampled colour (as Wube conversions do); `false`: by material |
| `colors` | `{material name: "#rrggbb"}` | force a material's colour: sRGB, the albedo as is, which a top face shows about as given from Factorio's view (sides darker, as lit) |
| `sprite_colors` | `{material name: "#rrggbb"}` | force a colour as the sprite shows it (picked from the sprite): it gets the same light correction (averaged over each part's triangles, so round parts work) and grading as a sampled colour |
| `two_tone` | list of material names, or `"*"` | soft two-colour regions: those parts' corners take the sprite's colour where they land, blurred, within 30 CIELAB of the part's colour (painted bands, coloured lids). Only on parts with enough vertices; low-poly boxes can't show a stripe |
| `two_tone_blur` | tiles | the blur for `two_tone` (default 0.2) |
| `two_tone_tint` | `{material name: 0..1}` | how far `two_tone` may move those materials' corners from their part's hue and chroma (0: only lighter or darker; default 1). Keeps clean paint from taking the tints of things lying over it in the sprite |
| `exposure`, `saturation` | factor | scale the model's brightness / colourfulness (default 1) |
| `entry` | model name | sample another model's sprite entry |

## Brightness

The client balances part colours against Godot's sun (`part_light` in the material shader): a top
face shows its colour about as stored, sides a little darker. Before core fix 1 (the "Part colours:
core fix" commits) tops showed about 1.6-1.8 times brighter (linear) than stored, so forced colours
tuned before it need brightening by about that much; or use `sprite_colors` with a colour picked
from the sprite, which needs no guessing.

Forced colours apply even when nothing could be sampled (the fish's sprite is all soft edges).
Writing a model also lifts the baked occlusion on long faces whose corners all sit in a joint
(`bake.py` LONG_FACE: a lone pipe's barrel read dark from end to end); new builds bake it so.

Thin parts (wires, cables, collars) are only sampled from their own interior pixels; too thin to
have any, they take their material's colour (force it with `colors` when that's wrong).

## Stored data

`TEXCOORD_4` = (r, g) / 4, `TEXCOORD_5` = (b / 4, share * 0.25), normalised 16-bit, so a colour can
be divided by a dark baked tint (the nature models' COLOR_0) without clipping. Files written before
core fix 1 store rgb and the share as is (share mostly 1); the client reads both, telling them apart
by the share, but they had clipped colours on dark-tinted models: re-run the tool on them.

Material names are the glTF material names (`python -c` with the tool's `Model`, or the `--debug`
picture, shows them; `tools/models/kit.py` has the palette). Keep the material names unchanged:
`MATERIAL_CLASSES` in `model_library.gd` picks the weathering from them.

Licences don't change: a Wube-derived model stays CC BY-NC after recolouring.
