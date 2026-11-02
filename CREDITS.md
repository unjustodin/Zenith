# Credits and licences

Zenith's own code, scripts, shaders, docs and the models it generates are under the MIT
licence in [LICENSE](LICENSE). A few things in or used by this project aren't ours, and keep
their own terms:

## Factorio (Wube Software)

Factorio and its graphics, sounds, fonts, map data and prototype definitions are © Wube
Software. **None of them are in this repository.** The client reads them at runtime from the
player's own Factorio install (item icons, terrain, GUI atlas and fonts, sounds and effects,
and the sprites when a model is set to wear them). The models' part colours are sampled from
Factorio's sprites when a model is built; only the numbers are stored in the `.glb`. Never commit files from a Factorio install, extracted frames,
or reference renders: references for modelling live in the git-ignored `art-src/`.

"Factorio" is a trademark of Wube Software. This is an unofficial fan project, not made,
endorsed or supported by Wube. You need your own copy of Factorio to play it.

## Models converted from Wube's printable release

Wube published 3D-printable models of some Factorio entities on Printables
(https://www.printables.com/@WubeSoftware/models, FFF #447). Their licence is listed there as
**CC BY-NC (non-commercial)**, which is not an open-source licence. Every `.glb` converted from
those files (belts, undergrounds, chests, furnaces, assembling machine 1, inserters, the small
pole, walls, the electric mining drill, the character, biters, spitters and the biter spawner)
keeps Wube's licence, not MIT: each is listed, with its source files, in
[client/assets/models/CREDITS.md](client/assets/models/CREDITS.md). Check each model's page for
its exact terms before converting it.

## Models converted from FUE5

FUE5 (https://github.com/FUE5BASE/FUE5), a fan project that rebuilt Factorio in Unreal Engine 5,
by Hurricane and Nuke, publishes its 3D models and textures under **CC BY-NC-SA 3.0**
(https://creativecommons.org/licenses/by-nc-sa/3.0/): non-commercial, share-alike. The models in
[client/assets/models/fue5/](client/assets/models/fue5/README.md) were converted from its FBX files
and textures by `tools/models/fue5.py` (scaled to tiles, turned to face north, cut at the ground,
decimated, their textures baked into one atlas each). They keep that licence, not MIT, and the
client draws them in place of our own models of the same name. The original files aren't in this
repository.

## Tools and libraries

- [Godot Engine](https://godotengine.org) (MIT), the client.
- Python packages used by the tools: lupa (MIT), gdtoolkit (MIT), numpy (BSD), scipy (BSD),
  scikit-image (BSD), trimesh (MIT), fast-simplification (MIT), Pillow (MIT-CMU).
- [Blender](https://www.blender.org) (GPL) runs the model scripts; the models it outputs are ours.
