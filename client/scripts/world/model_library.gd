extends RefCounted
## Finds the 3D model for a prototype and flattens it into one Mesh, so it can be drawn with
## MultiMesh instancing. Looked up by prototype name:
##
##   res://assets/models/<name>.glb or .gltf   (imported by the Godot editor)
##   <dir>/<name>.glb or .gltf                 (loaded at runtime, with --models=<dir>; first with --models-first)
##
## Models follow docs/PLAN.md §4: 1 unit = 1 tile, origin at the footprint centre on the
## ground, facing north (-Z). Anything without a model is drawn as a placeholder.
##
## Some entities pick a variant model from their record (see model_name): curved belts and
## underground entrances/exits. Higher belt tiers reuse the yellow tier's model with its
## `tier_paint` material recoloured (TIER_TINTS; a belt's frame stays steel, its chevrons take the
## tier's colour), until they get models of their own.
##
## Every surface is drawn with the Factorio material (shaders/factorio_material.gdshader). By
## default ("Factorio colours", look "colours") each part wears its own colour, sampled from
## Factorio's sprite when the model was built (tools/models/part_colors.py, CUSTOM1), weathered
## procedurally like Factorio's art. With look "sprite" the player's Factorio install's sprite is
## also projected onto the faces Factorio's camera sees (sprite_projection.gd); "palette" shows the
## models' own palette colours (for comparing). How a surface weathers depends on its material
## class, picked from the glTF material's name (MATERIAL_CLASSES).
##
## A model is drawn as one surface per shader (solid, see-through, leaf cards), not one per glTF
## material: each draw of a MultiMesh is per surface, and per shadow split again. Its materials
## become the rows of one material (material_rows.gd), each vertex carrying its row (Load.combined).
##
## Moving parts (assets/models/README.md) are nodes named `anim_<kind>`, pivot at the node's
## origin. They are left out of the static mesh and kept as AnimParts (parts_for), each its own
## mesh in model space at rest, which chunk_view.gd draws as one MultiMesh per part and anim.gd
## turns. `anim_glow_*` nodes stay in the static mesh but glow only while the machine works, as
## do emissive materials (furnace fire): the shader reads the activity from INSTANCE_CUSTOM.a.
## Belt surfaces (`belt_surface`) scroll at their tier's speed in the shader (_setup_belt).

## Prototype name prefix -> [prototype whose model to use, colour for its tier_paint]. Each colour
## is the paint's median in that tier's own sprite sheet, picked the way the yellow tier's part
## colours are (the faster splitters are lighter and the faster undergrounds darker than their
## belts, as in Factorio). Factorio's loaders are one grey plate for every tier, the tier showing
## in the belt under it: theirs follow the belts.
const TIER_TINTS := {
	"fast-transport-belt": ["transport-belt", Color("d41001")],
	"express-transport-belt": ["transport-belt", Color("009ccf")],
	"turbo-transport-belt": ["transport-belt", Color("86b52c")],
	"fast-underground-belt": ["underground-belt", Color("a5342a")],
	"express-underground-belt": ["underground-belt", Color("58a4ca")],
	"turbo-underground-belt": ["underground-belt", Color("8ba847")],
	"fast-splitter": ["splitter", Color("e14c44")],
	"express-splitter": ["splitter", Color("5db4d7")],
	"turbo-splitter": ["splitter", Color("a7be52")],
	"fast-loader": ["loader", Color("d41001")],
	"express-loader": ["loader", Color("009ccf")],
	"turbo-loader": ["loader", Color("86b52c")],
	# Factorio's linked belt is an underground belt's end in bare steel (linked-belt-structure.png).
	"linked-belt": ["underground-belt", Color("9ea3a6")],
}
## Prototype name prefix -> [prototype whose model to use, colour multiplying all of it]: Factorio
## draws the infinity pipe with the pipe's pictures tinted (0.5, 0.5, 1).
const WHOLE_TINTS := {"infinity-pipe": ["pipe", Color(0.5, 0.5, 1.0)]}
## Prototypes drawn with another's model as it is: Factorio draws them with its sprites.
const MODEL_ALIASES := {
	"burner-generator": "steam-engine",  # the steam engine's animation (entities.lua)
	"burner-generator-east": "steam-engine-east",
}
## Editor and internal prototypes that are never drawn (logos, proxies, invisible helpers), and
## names starting with "dummy-" (stand-ins the game uses internally).
const HIDDEN_PROTOS := {"proxy-container": true, "hidden-electric-energy-interface": true,
	"factorio-logo-11tiles": true, "factorio-logo-16tiles": true, "factorio-logo-22tiles": true,
	"wube-logo-space-platform": true}
## Editor test entities with no model of their own: a plain grey box rather than a coloured one.
const NEUTRAL_PROTOS := {"bottomless-chest": true, "electric-energy-interface": true, "heat-interface": true,
	"simple-entity-with-owner": true, "simple-entity-with-force": true}
const NEUTRAL_COLOR := Color(0.42, 0.42, 0.4)
const TIER_MATERIAL := "tier_paint"
const BELT_MATERIAL := "belt_surface"
## Belt speed in tiles per second by prototype name prefix (Factorio: 0.03125 tiles per tick for
## yellow, then x2, x3, x4); anything else with a belt surface runs at yellow speed.
const BELT_SPEEDS := {"fast-": 3.75, "express-": 5.625, "turbo-": 7.5}
const BELT_SPEED := 1.875
## The chevrons on every belt surface by tier: the median of each tier's belt sheet's paint.
const BELT_CHEVRONS := {"fast-": Color("e21400"), "express-": Color("00a4dd"), "turbo-": Color("91c42e")}
const BELT_CHEVRON := Color("edac04")
## Models whose tier_paint is bare steel on every tier (Factorio's belts have no painted frame:
## their tier shows in the chevrons alone).
const STEEL_FRAMES := ["transport-belt"]
## Moving part kinds that turn about the node's X axis (east-west); the rest turn about Y.
const X_AXIS_KINDS := {"spin_flywheel": true}
## ... and these about the node's Z axis (north-south): the pumpjack's crank and walking beam,
## the flywheel of a steam engine lying east-west.
const Z_AXIS_KINDS := {"spin_crank": true, "rock_beam": true, "spin_flywheel_ns": true}
## Parts named `anim_upright_<kind>` keep facing north whatever way the entity faces, as
## Factorio draws them (the pumpjack's beam, post and gearbox are one layer for every
## direction; only its ground pipes turn). Their sprite is the model's `<name>.upright` entry.
const UPRIGHT_PREFIX := "upright_"
## Moving part kinds that slide instead of turning: the offset (model space) per unit of
## "angle" (anim.gd counts roboport doors in tiles and gates from 0 to 1 of the way).
const SLIDE_KINDS := {"door_n": Vector3(0.0, -0.45, -0.89), "door_s": Vector3(0.0, -0.45, 0.89),
	"gate_door": Vector3(0.0, -1.27, 0.0),
	# A power switch's contact drops east into the gap between its cabinets; a logistic chest's
	# hatch halves slide apart under its rim.
	"switch": Vector3(0.3, -0.3, 0.0), "hatch_e": Vector3(0.19, 0.0, 0.0), "hatch_w": Vector3(-0.19, 0.0, 0.0)}
## Moving part kinds that cycle while the machine works (anim.gd `_cycle`), once per loop of
## Factorio's animation: `period` seconds (frame_count / animation_speed / 60). A part with
## `slide` moves that far (model space) and back; one with `angle` turns that many radians about
## `axis` (the node's frame). `wave` "out" goes there and back once a loop (0 -> 1 -> 0), "swing"
## either way of rest (-1 -> 1), "spin" round and round (`angle` a loop: TAU, negative for
## clockwise looking down `axis`). `phase` (0-1) puts parts of one machine out of step.
const CYCLES := {
	# Burner mining drill, 32 frames at 0.5 played forward then backward: the head's gears turn
	# one way and back (the small ones against the big), and the rod on top bobs.
	"gear_bmd_ns": {"axis": Vector3(0, 0, 1), "angle": TAU * 0.25, "period": 2.133, "wave": "swing"},
	"gear_bmd_ew": {"axis": Vector3(1, 0, 0), "angle": TAU * 0.25, "period": 2.133, "wave": "swing"},
	"gear_bmd_r_ns": {"axis": Vector3(0, 0, 1), "angle": -TAU * 0.25 * 0.17 / 0.13, "period": 2.133, "wave": "swing"},
	"gear_bmd_r_ew": {"axis": Vector3(1, 0, 0), "angle": -TAU * 0.25 * 0.17 / 0.13, "period": 2.133, "wave": "swing"},
	"slide_bmd_rod": {"slide": Vector3(0, 0.06, 0), "period": 1.067},
	# Assembling machine 1, 64 frames at 1: its two meshing gears. Oil refinery, 40 and 20 frames
	# at 0.75: three gears (speeds by radius) and the rocking yoke.
	"gear_am1_w": {"axis": Vector3.UP, "angle": -TAU, "period": 1.067, "wave": "spin"},
	"gear_am1_e": {"axis": Vector3.UP, "angle": TAU * 0.9, "period": 1.067, "wave": "spin"},
	"gear_refinery_a": {"axis": Vector3(0, 0, 1), "angle": TAU, "period": 0.889, "wave": "spin"},
	"gear_refinery_b": {"axis": Vector3(0, 0, 1), "angle": -TAU * 0.2 / 0.15, "period": 0.889, "wave": "spin"},
	"gear_refinery_c": {"axis": Vector3(0, 0, 1), "angle": -TAU * 0.2 / 0.13, "period": 0.889, "wave": "spin"},
	"yoke_refinery": {"axis": Vector3(0, 0, 1), "angle": 0.12, "period": 0.444, "wave": "swing"},
	# Gleba: biochamber 64 frames at 0.75; captive spawner 32 at 0.4; biolab 32 at 0.2.
	"fan_biochamber": {"axis": Vector3(0, 0, 1), "angle": TAU, "period": 0.356, "wave": "spin"},
	"bellows_captive": {"slide": Vector3(-0.184, -0.055, 0.055), "period": 1.333, "phase": 0.2},
	"pads_captive": {"slide": Vector3(0, 0.04, 0), "period": 1.333},
	"bellows_biolab": {"slide": Vector3(-0.177, -0.088, 0.032), "period": 2.667, "phase": 0.2},
	"vial_biolab_fw": {"axis": Vector3(-0.474, 0, -0.880), "angle": -0.7, "period": 2.667, "phase": 0.5},
	"vial_biolab_fe": {"axis": Vector3(-0.474, 0, 0.880), "angle": -0.7, "period": 2.667, "phase": 0.5},
	"vial_biolab_bw": {"axis": Vector3(0.673, 0, -0.740), "angle": -0.7, "period": 2.667, "phase": 0.5},
	"vial_biolab_be": {"axis": Vector3(0.673, 0, 0.740), "angle": -0.7, "period": 2.667, "phase": 0.5},
	# Foundry 128 frames at 0.16; cryogenic plant 192 at 0.5; fusion generator 6 at 1 (a tooth,
	# or a coil, a loop); recycler 64 at 4.
	"tilt_foundry_ladle": {"axis": Vector3(0, 0, 1), "angle": 0.45, "period": 13.333, "wave": "swing"},
	"slide_foundry_plate": {"slide": Vector3(0.55, 0, 0), "period": 6.667},
	"slide_cryo_drawers": {"slide": Vector3(0, 0, 0.3), "period": 6.4},
	"slide_cryo_hatch": {"slide": Vector3(0, 0, 0.5), "period": 3.2},
	"roll_fusion_gear": {"axis": Vector3(0, 0, 1), "angle": 0.2244, "period": 0.1, "wave": "spin"},
	"roll_fusion_coils": {"axis": Vector3(0, 0, 1), "angle": 0.2793, "period": 0.1, "wave": "spin"},
	"slide_recycler_drum": {"slide": Vector3(0, -0.35, 0), "period": 0.267},
	"slide_recycler_panel": {"slide": Vector3(0, 0.08, 0), "period": 0.267, "phase": 0.5},
	"roll_recycler": {"axis": Vector3(1, 0, 0), "angle": -TAU, "period": 1.067, "wave": "spin"},
	# Space: crusher 48 frames at 0.5 (a third of a turn a loop); silo crafting 64 frames at 0.65.
	# (The asteroid collector's arm, anim_reach_collector_*, is collectors.gd's.)
	"roll_crusher_n": {"axis": Vector3(1, 0, 0), "angle": TAU, "wave": "spin", "period": 4.8},
	"roll_crusher_s": {"axis": Vector3(1, 0, 0), "angle": -TAU, "wave": "spin", "period": 4.8},
	"roll_crusher_w": {"axis": Vector3(0, 0, 1), "angle": TAU, "wave": "spin", "period": 4.8},
	"roll_crusher_e": {"axis": Vector3(0, 0, 1), "angle": -TAU, "wave": "spin", "period": 4.8},
	"lift_silo": {"slide": Vector3(0, 0.9, 0), "period": 1.64},
	# Splitter: its structure's 32 frames at 0.7 a tick at yellow speed (speed x 32 x
	# structure_animation_speed_coefficient), 0.76 s. Each pair of oval cranks lifts its inner ends
	# about 55 degrees and lays them down once a loop, the west pair up at frame 0, the east pair
	# half a loop later; the rack housing slides 0.9 tiles west along the rod and back (frame 16).
	"crank_split_wa": {"axis": Vector3(0, 0, 1), "angle": 0.96, "period": 0.762, "phase": 0.5},
	"crank_split_wb": {"axis": Vector3(0, 0, 1), "angle": -0.96, "period": 0.762, "phase": 0.5},
	"crank_split_ea": {"axis": Vector3(0, 0, 1), "angle": 0.96, "period": 0.762},
	"crank_split_eb": {"axis": Vector3(0, 0, 1), "angle": -0.96, "period": 0.762},
	"slide_split_rack": {"slide": Vector3(-0.9, 0, 0), "period": 0.762},
	"fan_silo": {"axis": Vector3(1, 0, 0), "angle": TAU, "wave": "spin", "period": 1.33},
	# Fish: a slow sway of the tail fin, each fish at its own point of the loop (`scatter`).
	# Factorio's fish are still pictures; this is the client's own touch of life.
	"tail_fish": {"axis": Vector3.UP, "angle": 0.3, "period": 1.7, "wave": "swing", "scatter": true},
}
## Hatches and doors that slide open (`slide`, model space) or swing open (`angle` radians about
## `axis`) while a mover of one of `types` is within `reach` tiles of the entity, taking `time`
## seconds (anim.gd `_hatch`): the rocket silo's doors for its rocket (door_opening_speed 1/255),
## cargo hatches for pods. The hub's upper hatch is for pods arriving and its lower for pods
## leaving in Factorio; the client can't tell them apart, so both open.
const HATCHES := {
	"hatch_bay": {"slide": Vector3(1.2, 0, 0), "types": ["cargo-pod"], "reach": 3.0, "time": 0.7},
	"lid_hub_upper": {"axis": Vector3(-0.7071, 0, -0.7071), "angle": 1.6, "types": ["cargo-pod"], "reach": 5.0, "time": 0.35},
	"lid_hub_lower_ne": {"axis": Vector3(0.7071, 0, 0.7071), "angle": 1.2, "types": ["cargo-pod"], "reach": 5.0, "time": 0.35},
	"lid_hub_lower_sw": {"axis": Vector3(-0.7071, 0, -0.7071), "angle": 1.2, "types": ["cargo-pod"], "reach": 5.0, "time": 0.35},
	"lid_pad": {"axis": Vector3(-0.7071, 0, -0.7071), "angle": 1.6, "types": ["cargo-pod"], "reach": 5.0, "time": 0.35},
	"door_silo_e": {"slide": Vector3(1.45, -0.3, -0.6), "types": ["rocket-silo-rocket"], "reach": 2.0, "time": 4.25},
	"door_silo_w": {"slide": Vector3(-1.45, -0.3, 0.6), "types": ["rocket-silo-rocket"], "reach": 2.0, "time": 4.25},
}
## Glow styles (factorio_material's glow_* uniforms) by `anim_glow_<style>` node name. Emissive
## materials whose name says fire, flame or molten flicker as "fire".
const GLOW_STYLES := {
	"fire": {"glow_flicker": 0.45},
	"lab": {"glow_pulse": 0.5, "glow_rate": 0.606},
	"heatex": {"glow_pulse": 0.3, "glow_rate": 0.9375},
	"chem_lamp": {"glow_pulse": 0.8, "glow_rate": 2.5},
	"biochamber": {"glow_pulse": 0.12, "glow_rate": 0.703},
	"biolab": {"glow_pulse": 0.45, "glow_rate": 0.375, "glow_flicker": 0.15},
	"cryo_gauge": {"glow_pulse": 0.6, "glow_rate": 0.3125},
	"plasma": {"glow_pulse": 0.35, "glow_rate": 1.0},
	"plume": {"glow_flicker": 0.45, "glow_pulse": 0.25, "glow_rate": 1.9},
	"cockpit": {"glow_pulse": 0.7, "glow_rate": 0.4},
	"panel": {"glow_flicker": 0.7},
}
const FIRE_MATERIALS := ["fire", "flame", "molten"]
## Sliding parts whose travel differs by model: pump pistons run north along their windows (the
## pump's cylinders lean 16 degrees, tools/models/circuits.py).
const MODEL_SLIDES := {
	"pump": {"bob_a": Vector3(0.0, -0.055, -0.192), "bob_b": Vector3(0.0, -0.055, -0.192)},
	"offshore-pump": {"bob_a": Vector3(0.0, 0.0, -0.16), "bob_b": Vector3(0.0, 0.0, -0.16)},
	"offshore-pump-east": {"bob_a": Vector3(0.16, 0.0, 0.0), "bob_b": Vector3(0.16, 0.0, 0.0)},
	"offshore-pump-south": {"bob_a": Vector3(0.0, 0.0, 0.16), "bob_b": Vector3(0.0, 0.0, 0.16)},
	"offshore-pump-west": {"bob_a": Vector3(-0.16, 0.0, 0.0), "bob_b": Vector3(-0.16, 0.0, 0.0)},
}
## Parts named `anim_lit_<colour or state>` are hidden until their state lights them (anim.gd).
const LIT_PREFIX := "lit_"
## Where a hidden lit part goes: shrunk to nothing at the model's origin, inside the body.
const HIDDEN := Transform3D(Vector3(0.001, 0.0, 0.0), Vector3(0.0, 0.001, 0.0), Vector3(0.0, 0.0, 0.001), Vector3.ZERO)
const ANIM_PREFIX := "anim_"
const GLOW_PREFIX := "anim_glow"


## A moving part of a model: everything under a node named anim_<kind>. The mesh is in model
## space at rest, so the sprite projection and weathering stay put on it; it is drawn turned
## about `pivot` (the node's transform in the model): pivot * rotation(axis, angle) * pivot^-1.
class AnimPart:
	var kind := ""  # "spin_drill", "spin_arms", "spin_flywheel", "turret_head", ...
	var model := ""  # the model it belongs to
	var mesh: Mesh
	var pivot := Transform3D.IDENTITY
	var axis := Vector3.UP  # in the pivot's frame
	var upright := false  # drawn facing north whatever way the entity faces
	var slide := Vector3.ZERO  # sliding parts (SLIDE_KINDS): the offset when fully open
	var lit := false  # `lit_*`: shown (angle 1) or hidden (0) by the entity's state
	## How the shader moves it (anim.gd setup_part: its MOTION_* codes, -1 until set up), loops of
	## its motion a second at full speed and where in the loop it starts.
	var motion := -1
	var rate := 0.0
	var phase := 0.0

	## The part's transform in the model, turned by `angle` radians (slid by `angle` of the way,
	## 0 to 1, for sliding parts; shown when not 0 for lit parts).
	func turned(angle: float) -> Transform3D:
		if lit:
			return Transform3D.IDENTITY if angle != 0.0 else HIDDEN
		if angle == 0.0:
			return Transform3D.IDENTITY
		if slide != Vector3.ZERO:
			return Transform3D(Basis.IDENTITY, slide * angle)
		return pivot * Transform3D(Basis(axis, angle), Vector3.ZERO) * pivot.affine_inverse()

const SpriteProjection := preload("res://scripts/world/sprite_projection.gd")
const ModelLods := preload("res://scripts/world/model_lods.gd")
const MaterialRows := preload("res://scripts/world/material_rows.gd")
const ModelTextures := preload("res://scripts/world/model_textures.gd")
## Folders under res://assets/models/ looked in first, in order: models brought in from elsewhere
## under their own licence (fue5/: the FUE5 fan project's, CC BY-NC-SA 3.0) replace ours there.
const MODEL_SUBDIRS := ["fue5/"]
const CreatureModels := preload("res://scripts/world/creature_models.gd")
const FactorioShader := preload("res://shaders/factorio_material.gdshader")
const FactorioAlphaShader := preload("res://shaders/factorio_material_alpha.gdshader")
## Trees' leaf cards (tools/models/nature/geo.py `card`): leaves cut out, both sides drawn.
const FactorioLeafShader := preload("res://shaders/factorio_material_leaf.gdshader")

## Material name fragments -> class, first match wins (names from tools/models/kit.py's palette
## and tools/models/nature/). Anything else is painted metal.
const MATERIAL_CLASSES := [
	["fulgurite", "fulgurite"], ["scrap", "scrap"], ["wreck_yellow", "wreck_paint"],
	["glass", "glass"], ["leaf", "foliage"], ["flesh", "organic"], ["chitin", "organic"],
	["ice", "ice"],  # Aquilo ice (m-space2)
	["rubber", "dark"], ["belt_surface", "dark"], ["hazard_black", "dark"], ["soot", "dark"],
	["steel_black", "dark"],
	["bark", "wood"], ["wood", "wood"],
	["rock_carbonic", "asteroid"], ["rock_metallic", "asteroid"], ["rock_oxide", "asteroid"],
	["rock_promethium", "asteroid"],
	["rock", "stone"], ["stone", "stone"], ["concrete", "stone"], ["ceramic", "stone"],
	["-chunk", "ore"], ["-dust", "stone"],
	["copper", "copper"], ["brass", "copper"], ["bronze", "copper"],
	["rust", "rusty"],
	["steel", "steel"], ["iron", "steel"],
]
## Weathering per class: shader uniforms over the defaults in factorio_material.gdshaderinc.
## Colours are sRGB.
const CLASS_PARAMS := {
	"paint": {"rust": 0.55, "streaks": 0.35, "edge_wear": 0.75, "grime": 0.75, "dust": 0.3,
		"desaturate": 0.18, "value": 0.86},
	# The crash site's yellow plates: Factorio paints them clean and bright between their dark
	# seams, the grime already in the part colours; less rust, grime and dust laid on top.
	"wreck_paint": {"rust": 0.15, "streaks": 0.1, "edge_wear": 0.5, "grime": 0.35, "dust": 0.05,
		"desaturate": 0.05, "value": 0.95, "grain": 0.04},
	"steel": {"rust": 0.8, "streaks": 0.45, "edge_wear": 0.6, "grime": 0.8, "dust": 0.25,
		"edge_color": Color("b9b6ad"), "desaturate": 0.1, "value": 0.85},
	"rusty": {"rust": 0.5, "streaks": 0.3, "edge_wear": 0.35, "grime": 0.85, "dust": 0.2,
		"rust_color": Color("4f2a15"), "edge_color": Color("8a7461"), "edge_metallic": 0.5,
		"desaturate": 0.08, "value": 0.85},
	"copper": {"rust": 0.0, "streaks": 0.0, "edge_wear": 0.7, "grime": 0.75, "dust": 0.2,
		"edge_color": Color("d79a68"), "edge_metallic": 0.95, "desaturate": 0.1, "value": 0.85},
	"dark": {"rust": 0.0, "streaks": 0.0, "edge_wear": 0.25, "grime": 0.4, "dust": 0.35,
		"edge_color": Color("5a5856"), "edge_metallic": 0.3, "desaturate": 0.0, "value": 1.0},
	"wood": {"rust": 0.0, "streaks": 0.0, "edge_wear": 0.45, "grime": 0.7, "dust": 0.2,
		"edge_color": Color("b08a5c"), "edge_metallic": 0.0, "desaturate": 0.12, "value": 0.88},
	"stone": {"rust": 0.0, "streaks": 0.0, "edge_wear": 0.4, "grime": 0.6, "dust": 0.25,
		"edge_color": Color("b7a993"), "edge_metallic": 0.0, "desaturate": 0.1, "value": 0.9},
	# Asteroids: Factorio's are speckled and pitted all over, dark in their craters, with pale
	# crystal edges; no dust or rust in space.
	"asteroid": {"rust": 0.0, "streaks": 0.0, "edge_wear": 0.6, "grime": 1.0, "dust": 0.0,
		"edge_color": Color("b8b2ab"), "edge_metallic": 0.0, "desaturate": 0.0, "value": 1.0,
		"grain": 0.3, "ground_grime_height": 0.01},
	# Ore chunks keep their colour: coal stays black, iron ore blue-grey.
	"ore": {"rust": 0.0, "streaks": 0.0, "edge_wear": 0.0, "grime": 0.3, "dust": 0.1,
		"desaturate": 0.0, "value": 0.95},
	"glass": {"rust": 0.0, "streaks": 0.0, "edge_wear": 0.0, "grime": 0.35, "dust": 0.4,
		"desaturate": 0.1, "value": 1.0, "grain": 0.03},
	"foliage": {"rust": 0.0, "streaks": 0.0, "edge_wear": 0.0, "grime": 0.25, "dust": 0.0,
		"ao_strength": 0.45, "desaturate": 0.06, "value": 0.95, "grain": 0.1},
	# Creatures (creature_models.gd): no rust or bare metal, a wet sheen kept, dirt from the ground.
	"organic": {"rust": 0.0, "streaks": 0.0, "edge_wear": 0.15, "grime": 0.5, "dust": 0.12,
		"edge_color": Color("c99a86"), "edge_metallic": 0.0, "desaturate": 0.05, "value": 0.95,
		"grain": 0.12},
	# Fulgora's scrap (space_nature.py scrap): Factorio's pieces are grimy, rust-streaked and
	# chipped, half under dithered dirt; not the clean paint the sun showed.
	"scrap": {"rust": 0.75, "streaks": 0.45, "edge_wear": 0.85, "grime": 1.0, "dust": 0.6,
		"rust_color": Color("4f2a15"), "edge_color": Color("8f8a80"), "edge_metallic": 0.6,
		"dust_color": Color("5c4c3e"), "desaturate": 0.2, "value": 0.85, "grain": 0.32,
		# Kept over the part colours (rust and streaks, worn edges, grime, dust), which are the
		# sprite's paint: the wear is what was missing.
		"part_weathering": Vector4(0.85, 0.8, 1.0, 0.75)},
	# Fulgurite: fused glass under a dusty crust, speckled pale (the sprite's), not smooth pink.
	"fulgurite": {"rust": 0.0, "streaks": 0.0, "edge_wear": 0.55, "grime": 0.85, "dust": 0.5,
		"edge_color": Color("cdb9be"), "edge_metallic": 0.0, "dust_color": Color("7d6d6a"),
		"desaturate": 0.08, "value": 0.92, "grain": 0.45, "part_weathering": Vector4(0.0, 0.8, 0.9, 0.8)},
	# Aquilo ice: clean, a little dust in the crevices, bright edges.
	"ice": {"rust": 0.0, "streaks": 0.0, "edge_wear": 0.35, "grime": 0.2, "dust": 0.15,
		"edge_color": Color("eef8ff"), "edge_metallic": 0.0, "desaturate": 0.0, "value": 1.0},
	"emissive": {"rust": 0.0, "streaks": 0.0, "edge_wear": 0.0, "grime": 0.0, "dust": 0.0,
		"ao_strength": 0.3, "desaturate": 0.0, "value": 1.0, "grain": 0.0},
}

static var external_dir := ""
## One material per model (Settings > Graphics > Merged materials, off by default; read when models
## load, so a change applies after a restart). --merged-materials / --no-merged-materials override it.
static var merge_materials := false
## --models-first: a model in external_dir replaces the project's own model of that name (for a
## modeller trying a new version), instead of only filling in prototypes without one.
static var external_first := false


## The model file of `file` in external_dir, or "".
static func _external_path(file: String) -> String:
	if external_dir == "":
		return ""
	for ext in ["glb", "gltf"]:
		var path := external_dir.path_join("%s.%s" % [file, ext])
		if FileAccess.file_exists(path):
			return path
	return ""
## The models' look: "colours" (part colours), "sprite" (part colours and the projected sprite) or
## "palette" (neither). Set from Settings → Graphics before the first model is built.
const LOOKS := ["colours", "sprite", "palette"]
static var look := "colours"
static var _cache := {}  # name -> Mesh, or null when there is no model
static var _parts := {}  # name -> Array of AnimPart (empty for models without moving parts)
static var _glowing := {}  # Mesh -> true when it has surfaces that glow while working
## Height in tiles above which a model counts as tall (Factorio's tall-entities toggle).
static var _factorio_cache := {}  # [imported material, has COLOR, UV2, CUSTOM0] -> ShaderMaterial


static func configure_from_command_line() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--models="):
			external_dir = arg.get_slice("=", 1)
		elif arg == "--models-first":
			external_first = true
		elif arg == "--no-merged-materials":
			merge_materials = false
		elif arg == "--merged-materials":
			merge_materials = true
		elif arg.begins_with("--model-look="):
			set_look(arg.get_slice("=", 1))
	SpriteProjection.configure_from_command_line()
	SpriteProjection.build_all()
	warm_up()


## The first material made with each Factorio shader costs about 50 ms on the main thread (Godot
## sets the shader up then), which was a hitch when the first model of each kind appeared: made
## here at start-up instead, one of each (solid, see-through, leaf cards).
static func warm_up() -> void:
	var solid := StandardMaterial3D.new()
	var clear := StandardMaterial3D.new()
	clear.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var leaf := StandardMaterial3D.new()
	leaf.resource_name = "leafcard"
	for m in [solid, clear, leaf]:
		_factorio(m, true, true, true, "", true)


## Chooses the look (LOOKS); the sprite is only projected with "sprite".
static func set_look(value: String) -> void:
	look = value if LOOKS.has(value) else "colours"
	SpriteProjection.disabled = look != "sprite"


## True when the model wears Factorio's sprite: then it is drawn as the sprite shows it, without
## the random turn trees and rocks otherwise get (chunk_view.gd).
static func projected(name: String) -> bool:
	return SpriteProjection.has_entry(name)


## Factorio's pipe pictures by connection mask (world.gd: extra.pc, bits north 1, east 2,
## south 4, west 8), each a model of its own (tools/models/fluids.py).
const PIPE_SHAPES := ["straight-vertical-single", "ending-up", "ending-right", "corner-up-right",
	"ending-down", "straight-vertical", "corner-down-right", "t-right",
	"ending-left", "corner-up-left", "straight-horizontal", "t-up",
	"corner-down-left", "t-left", "t-down", "cross"]

## Wall pieces by connection mask (world.gd: extra.wc, bits north 1, east 2, south 4, west 8),
## named by the sides each joins (Wube's walls set, tools/models/wube_recipes.py). Bit 16 adds
## the block that fills the middle of a 2x2 group of walls (`-fill`, on the south-east corner).
const WALL_SHAPES := ["pylon", "n", "e", "ne", "s", "ns", "es", "nes", "w", "nw", "ew", "new",
	"sw", "nsw", "esw", "nesw"]


## The cargo area of a hub, its bays and a landing pad is framed by Factorio's connection tileset,
## one piece per 2x2 cell: a wall on each side of a cell that faces no cargo area, an outer corner
## where two such sides meet, an inner corner where two joined sides leave the cell between them
## empty (base's cargo-hubs/connections/connections.lua; tools/models/space_platform.py). Bays
## draw theirs: extra.cb holds a neighbour mask per cell (world.gd), 8 bits each for the cells
## NW, N, NE, E, SE, S, SW, W round it (bit 0..7), for the bay's cells NW, NE, SW, SE in turn.
const CARGO_TYPES := {"cargo-bay": true, "space-platform-hub": true, "cargo-landing-pad": true}
## The bay's cells' middles, Factorio's axes (y south), in cb's order.
const CARGO_CELLS := [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]


## The edge pieces (model names) for one cell's neighbour mask.
static func cargo_pieces(mask: int) -> Array:
	var n := mask & 2 != 0
	var e := mask & 8 != 0
	var s := mask & 32 != 0
	var w := mask & 128 != 0
	var out := []
	for side in [[n, w, e, "n"], [s, w, e, "s"]]:
		if side[0]:
			continue
		if not side[1]:
			out.append("cargo-bay-corner-%sw" % side[3])
		if not side[2]:
			out.append("cargo-bay-corner-%se" % side[3])
		if side[1] and side[2]:
			out.append("cargo-bay-wall-" + side[3])
	if not e and n and s:
		out.append("cargo-bay-wall-e")
	if not w and n and s:
		out.append("cargo-bay-wall-w")
	for corner in [[n, w, 1, "nw"], [n, e, 4, "ne"], [s, w, 64, "sw"], [s, e, 16, "se"]]:
		if corner[0] and corner[1] and mask & corner[2] == 0:
			out.append("cargo-bay-inner-" + corner[3])
	return out


## Where a bay's edge pieces go for its mask `cb` (extra.cb) round its middle `origin`: [model, place].
static func cargo_places(cb: int, origin: Vector3) -> Array:
	var out := []
	for k in 4:
		var cell: Vector2 = CARGO_CELLS[k]
		for piece in cargo_pieces((cb >> (8 * k)) & 255):
			out.append([piece, origin + Vector3(cell.x, 0.0, cell.y)])
	return out


## The model an entity record is drawn with. Belts carry their shape in extra.s ("s", "l",
## "r": straight, left or right curve) and undergrounds their end in extra.u ("i" entrance,
## "o" exit). Curves are modelled facing their output direction, like straight belts. Pipes
## pick a piece of the pipe kit from their connections (extra.pc, worked out in world.gd).
static func model_name(proto_name: String, proto_type: String, extra: Dictionary, dir := 0) -> String:
	if RAIL_TYPES.has(proto_type) and dir % 4 == 2:
		return proto_name + "-ne"
	if FACING_MODELS.has(proto_name) and dir % 4 == 0:
		return proto_name + str(FACING_MODELS[proto_name][(dir >> 2) % 4])
	match proto_type:
		"transport-belt":
			var shape := str(extra.get("s", "s"))
			if shape == "l":
				return proto_name + "-curve-left"
			if shape == "r":
				return proto_name + "-curve-right"
		"underground-belt", "linked-belt":
			return proto_name + ("-output" if str(extra.get("u", "i")) == "o" else "-input")
		"pipe", "heat-pipe", "infinity-pipe":
			if extra.has("pc"):
				return proto_name + "-" + PIPE_SHAPES[int(extra["pc"]) & 15]
		"wall":
			if extra.has("wc"):
				var wc := int(extra["wc"])
				return proto_name + "-" + WALL_SHAPES[wc & 15] + ("-fill" if wc & 16 else "")
		"cliff":
			if CLIFF_PIECES.has(str(extra.get("co", ""))):
				return proto_name + "-" + str(CLIFF_PIECES[str(extra["co"])][0])
		"resource":
			if ORE_STAGES.has(proto_name) and extra.has("a"):
				var amount := int(extra["a"])
				if amount >= ORE_RICH:
					return proto_name + "-rich"
				if amount < ORE_SPARSE:
					return proto_name + "-sparse"
	return proto_name


## Nauvis ores modelled at three of Factorio's eight richness stages (tools/models/nature/rocks.py
## STAGES): "-rich" from the fourth stage up (Factorio's stage_counts for them: 15000, 9500, 5500,
## 2900, 1300, 400, 150, 80 per tile; uranium's about a third lower), "-sparse" under the sixth,
## the plain model in between.
const ORE_STAGES := {"iron-ore": true, "copper-ore": true, "coal": true, "stone": true, "uranium-ore": true}
const ORE_RICH := 2900
const ORE_SPARSE := 400


## A cliff's orientation (extra.co: it runs from the middle of one edge of its 4x4 cell to
## another, high ground on its left) -> [piece, direction the piece is turned to]. Each piece is
## modelled for its first orientation (tools/models/nature/cliffs.py); the rest are it turned
## clockwise in quarter turns. world.gd turns the record's direction to match.
const CLIFF_PIECES := {
	"west-to-east": ["sides", 0], "north-to-south": ["sides", 4], "east-to-west": ["sides", 8], "south-to-north": ["sides", 12],
	"west-to-north": ["outer", 0], "north-to-east": ["outer", 4], "east-to-south": ["outer", 8], "south-to-west": ["outer", 12],
	"west-to-south": ["inner", 0], "north-to-west": ["inner", 4], "east-to-north": ["inner", 8], "south-to-east": ["inner", 12],
	"west-to-none": ["exit", 0], "north-to-none": ["exit", 4], "east-to-none": ["exit", 8], "south-to-none": ["exit", 12],
	"none-to-east": ["entrance", 0], "none-to-south": ["entrance", 4], "none-to-west": ["entrance", 8], "none-to-north": ["entrance", 12],
}


## Rail pieces (tools/models/rails.py) come in eight directions (0, 2, ... 14): each has a model
## for direction 0 and one for direction 2 (`-ne`), turned by the rest in quarter turns.
const RAIL_TYPES := {"straight-rail": true, "half-diagonal-rail": true, "curved-rail-a": true,
	"curved-rail-b": true, "elevated-straight-rail": true, "elevated-half-diagonal-rail": true,
	"elevated-curved-rail-a": true, "elevated-curved-rail-b": true,
	"legacy-straight-rail": true, "legacy-curved-rail": true}  # 1.1's pieces, in old saves


## The direction an entity's model is turned by (Visuals.direction_yaw): rail pieces turn only
## in quarter turns, their `-ne` models cover the directions between. An underground exit's
## direction is the way its items travel, like its entrance's (checked in 2.1.23), but its model
## (as Factorio's 1.x exit sprite) faces back at its entrance, so it turns half way round.
## Factorio draws these with fewer pictures than directions (tools/models/space_sprites.py
## `pictures`): the crusher one per axis (south looks like north, west like east: a model each,
## FACING_MODELS), the foundry one
## for all four. The model turns only as far as the pictures do.
const PICTURES := {"crusher": 1, "foundry": 1, "burner-mining-drill": 1,
	"boiler": 1, "steam-engine": 1, "burner-generator": 1, "offshore-pump": 1,
	"pipe-to-ground": 1, "one-way-valve": 1, "overflow-valve": 1, "top-up-valve": 1,
	"burner-inserter": 1, "inserter": 1, "long-handed-inserter": 1, "fast-inserter": 1, "bulk-inserter": 1,
	"stack-inserter": 1, "pumpjack": 1, "chemical-plant": 1}
## Models drawn with a model per direction instead of turned (model_name): Factorio draws the
## burner drill's stand the same every way round, only its duct and fuel box move. The boiler's,
## steam engine's and offshore pump's directions are separate renders that one turned model
## can't match (tools/models/facings.py); the steam engine has one per axis (V and H). The
## pipe-to-ground's four pictures were rendered apart and don't turn into each other; a valve's
## picture is a square plate whatever its pipe's direction (tools/models/fluids.py, circuits.py).
## The inserters' four platform renders sit and size a little differently each (wube_recipes.py
## INSERTER_FITS). The pumpjack's beam is the same every way round, its ground pipes and motor
## routed anew for each; the chemical plant's four renders put its tanks, chimney and pipes in
## different places (tools/models/oil.py).
const FACING_MODELS := {"burner-mining-drill": ["", "-east", "-south", "-west"],
	"boiler": ["", "-east", "-south", "-west"], "offshore-pump": ["", "-east", "-south", "-west"],
	"steam-engine": ["", "-east", "", "-east"], "burner-generator": ["", "-east", "", "-east"],
	"pipe-to-ground": ["", "-east", "-south", "-west"],
	"one-way-valve": ["", "-east", "-south", "-west"],
	"overflow-valve": ["", "-east", "-south", "-west"],
	"top-up-valve": ["", "-east", "-south", "-west"],
	"burner-inserter": ["", "-east", "-south", "-west"], "inserter": ["", "-east", "-south", "-west"],
	"long-handed-inserter": ["", "-east", "-south", "-west"], "fast-inserter": ["", "-east", "-south", "-west"],
	"bulk-inserter": ["", "-east", "-south", "-west"], "stack-inserter": ["", "-east", "-south", "-west"],
	"pumpjack": ["", "-east", "-south", "-west"], "chemical-plant": ["", "-east", "-south", "-west"],
	"crusher": ["", "-east", "", "-east"]}
## Factorio draws each of a rail signal's 16 pictures about its own point (2.0 sets a signal
## beside the rail it guards, and each picture's housings sit where that direction puts them), so
## one model turned about the entity's position misses most of them. Per direction, the model's
## offset in its own frame before it is turned (tiles, x east, z south), fitted to each picture
## (tools/models/fit_cells.py --offsets).
const PLACEMENT_OFFSETS := {
	"rail-signal": [[0.048, -0.100], [-0.180, -0.050], [0.293, 0.035], [-0.112, -0.075],
		[0.263, -0.008], [-0.145, 0.035], [0.188, -0.117], [-0.220, 0.200],
		[0.013, 0.062], [-0.082, 0.258], [0.168, 0.077], [-0.050, 0.087],
		[0.095, 0.010], [-0.022, -0.030], [0.150, -0.100], [-0.027, -0.112]],
	"rail-chain-signal": [[0.193, 0.030], [-0.135, -0.015], [0.125, 0.025], [-0.052, 0.035],
		[0.125, 0.025], [-0.100, 0.000], [0.087, 0.050], [-0.238, 0.100],
		[0.157, 0.112], [-0.062, 0.130], [0.210, 0.115], [-0.075, 0.142],
		[0.127, 0.052], [-0.062, -0.012], [0.163, -0.100], [-0.065, 0.038]],
}


## The model's transform for an entity at `at` facing `dir`: turned by turn_dir (as
## Visuals.direction_yaw) and moved by its PLACEMENT_OFFSETS, if it has any. `flip` mirrors the build preview.
static func placed(proto_name: String, proto_type: String, dir: int, extra: Dictionary, at: Vector3, flip := Basis.IDENTITY) -> Transform3D:
	var basis := Basis(Vector3.UP, -float(turn_dir(proto_type, dir, extra, proto_name)) / 16.0 * TAU)
	var table: Array = PLACEMENT_OFFSETS.get(proto_name, [])
	if not table.is_empty():
		var o: Array = table[posmod(dir, table.size())]
		at += basis * (flip * Vector3(float(o[0]), 0.0, float(o[1])))
	return Transform3D(basis * flip, at)


static func turn_dir(proto_type: String, dir: int, extra := {}, proto_name := "") -> int:
	if PICTURES.has(proto_name):
		return dir % (4 * int(PICTURES[proto_name]))
	if RAIL_TYPES.has(proto_type):
		return dir - dir % 4
	if (proto_type == "underground-belt" or proto_type == "linked-belt") and str(extra.get("u", "i")) == "o":
		return (dir + 8) % 16
	return dir


## Demolishers come as a head, segments and a tail, each its own prototype at its own scale
## (`small-demolisher`, `small-demolisher-segment-x0_545`, `big-demolisher-tail-x0_64`). They
## share three models made at the big demolisher's scale: [model name, scale], or [] for others.
const DEMOLISHER_SCALES := {"small-demolisher": 0.5, "medium-demolisher": 0.75, "big-demolisher": 1.0}


static func mover_model(proto_name: String) -> Array:
	if DEMOLISHER_SCALES.has(proto_name):
		return ["demolisher-head", DEMOLISHER_SCALES[proto_name]]
	for part in ["-segment-x", "-tail-x"]:
		var at := proto_name.find("-demolisher" + part)
		if at >= 0:
			var scale := proto_name.substr(at + ("-demolisher" + part).length()).replace("_", ".").to_float()
			if scale > 0.0:
				return ["demolisher-" + part.substr(1, part.length() - 3), scale]
	return []


## Mesh for an entity record: its variant model if there is one, else the prototype's.
static func mesh_for_entity(proto_name: String, proto_type: String, extra: Dictionary, dir := 0) -> Mesh:
	var variant := model_name(proto_name, proto_type, extra, dir)
	if variant != proto_name:
		var mesh := mesh_for(variant)
		if mesh != null:
			return mesh
	return mesh_for(proto_name)


## The moving parts drawn with an entity record's mesh (mesh_for_entity).
static func parts_for_entity(proto_name: String, proto_type: String, extra: Dictionary, dir := 0) -> Array:
	var variant := model_name(proto_name, proto_type, extra, dir)
	if variant != proto_name and mesh_for(variant) != null:
		return parts_for(variant)
	return parts_for(proto_name)


## The moving parts of a model (AnimPart), empty when it has none or there is no model.
static func parts_for(name: String) -> Array:
	mesh_for(name)
	return _parts.get(name, [])


## True when some of the mesh's surfaces glow only while the machine works (INSTANCE_CUSTOM.a).
static func glows(mesh: Mesh) -> bool:
	return _glowing.has(mesh)


## Main-thread time spent making models the first time they are asked for, and how many (for
## --stutter-probe and tests).
static var load_usec := 0
static var loads := 0
static var _load_depth := 0
## The slowest of those: [ms, name, caller, its caller, how], for --stutter-probe. A release export
## has no script stack, so `how` says it anyway: "worker" (poll() finishing a worker's parse),
## "direct" (asked for straight away, parsed on a worker before) or "parsed here" (its .glb read on
## the main thread: a caller that didn't wait for ready()).
static var slowest: Array = []
static var _polling := false
static var _parsed_here := false


static func mesh_for(name: String) -> Mesh:
	if _cache.has(name):
		return _cache[name]
	var t0 := Time.get_ticks_usec()
	if _load_depth == 0:
		_parsed_here = false
	_load_depth += 1
	var mesh := _make(name)
	_load_depth -= 1
	if _load_depth == 0:
		var spent := Time.get_ticks_usec() - t0
		load_usec += spent
		loads += 1
		if spent > 2000:
			var stack := get_stack()
			var how := "parsed here" if _parsed_here else ("worker" if _polling else "direct")
			slowest.append([spent / 1000.0, name, stack[1] if stack.size() > 1 else {}, stack[2] if stack.size() > 2 else {}, how])
	return mesh


static func _make(name: String) -> Mesh:
	var mesh: Mesh = null
	var parts: Array = []
	var source := _source(name)
	var built: Load = _built(name) if source.begins_with(GLTF_SOURCE) else null
	if built != null and not built.ok:
		built = null
	var root: Node = _load_scene(name) if source.begins_with(SCENE_SOURCE) else null
	if root == null and built == null and MODEL_ALIASES.has(name):
		mesh = mesh_for(MODEL_ALIASES[name])
		_cache[name] = mesh
		_parts[name] = _parts.get(MODEL_ALIASES[name], [])
		return mesh
	if root != null or built != null:
		if built != null:
			mesh = _commit_load(built, parts)
		else:
			mesh = _flatten(root, parts)
			root.free()
		# Creatures: a tier is its family's model scaled and tinted; limbs move in the shader.
		mesh = CreatureModels.prepare(mesh as ArrayMesh, name)
		if mesh != null:
			_project_sprite(mesh as ArrayMesh, name)
			for part: AnimPart in parts:
				part.model = name
				part.slide = MODEL_SLIDES.get(name, {}).get(part.kind, part.slide)
				var upright_name := name + ".upright"
				var shown := upright_name if part.upright and SpriteProjection.has_entry(upright_name) else name
				_project_sprite(part.mesh as ArrayMesh, shown)
				_mark_animated(part.mesh as ArrayMesh)
	if mesh == null:
		mesh = _tier_variant(name)
		parts = _parts.get(_tier_base(name), [])
	if mesh != null:
		_setup_belt(mesh as ArrayMesh, name)
		for i in mesh.get_surface_count():
			var material := mesh.surface_get_material(i) as ShaderMaterial
			if material != null and material.get_shader_parameter("activity_glow"):
				_glowing[mesh] = true
	_cache[name] = mesh
	_parts[name] = parts
	return mesh


## The base tier's model name for a higher tier without its own model, or "".
static func _tier_base(name: String) -> String:
	for table in [TIER_TINTS, WHOLE_TINTS]:
		for prefix in table:
			if name.begins_with(prefix):
				return str(table[prefix][0]) + name.substr(prefix.length())
	return ""


## Belt surfaces move the way items travel at the tier's speed: the shader scrolls Factorio's
## slats along the belt (belt_speed; belt_shape follows the curves' arcs).
static func _setup_belt(mesh: ArrayMesh, name: String) -> void:
	if mesh == null:
		return
	var speed := BELT_SPEED
	for prefix in BELT_SPEEDS:
		if name.begins_with(prefix):
			speed = BELT_SPEEDS[prefix]
	var chevron := BELT_CHEVRON
	for prefix in BELT_CHEVRONS:
		if name.begins_with(prefix):
			chevron = BELT_CHEVRONS[prefix]
	# An underground exit's model faces back at its entrance (turn_dir turns it round), so its
	# belt runs the other way, south in model space.
	if name.ends_with("-output"):
		speed = -speed
	var shape := 0
	if name.ends_with("-curve-left"):
		shape = 1
	elif name.ends_with("-curve-right"):
		shape = 2
	var pick := func(m: ShaderMaterial) -> bool: return m.resource_name.contains(BELT_MATERIAL)
	var change := func(m: ShaderMaterial) -> void:
		m.set_shader_parameter("belt_speed", speed)
		m.set_shader_parameter("belt_shape", shape)
		m.set_shader_parameter("belt_chevron", chevron)
	edit_materials(mesh, pick, change)


## A moving part's materials take the entity's position and direction from INSTANCE_CUSTOM,
## since the part's own transform turns.
static func _mark_animated(mesh: ArrayMesh) -> void:
	for i in mesh.get_surface_count():
		var material := mesh.surface_get_material(i) as ShaderMaterial
		if material != null:
			var copy := ModelLods.copy_material(material)
			copy.set_shader_parameter("animated", true)
			mesh.surface_set_material(i, copy)


## A higher tier without its own model: the base tier's mesh with the tier colour swapped in.
static func _tier_variant(name: String) -> Mesh:
	for prefix in TIER_TINTS:
		if name.begins_with(prefix):
			var entry: Array = TIER_TINTS[prefix]
			var base_name := str(entry[0]) + name.substr(prefix.length())
			var base := mesh_for(base_name)
			if base is ArrayMesh:
				if str(entry[0]) in STEEL_FRAMES:
					return _copy(base as ArrayMesh)
				return _tinted(base as ArrayMesh, entry[1])
	for prefix in WHOLE_TINTS:
		if name.begins_with(prefix):
			var whole: Array = WHOLE_TINTS[prefix]
			var model := mesh_for(str(whole[0]) + name.substr(prefix.length()))
			if model is ArrayMesh:
				var out := _copy(model as ArrayMesh)
				for i in out.get_surface_count():
					var material := out.surface_get_material(i) as ShaderMaterial
					if material != null:
						# The model's own uniform: on a merged material as on any other.
						var tinted := ModelLods.copy_material(material)
						tinted.set_shader_parameter("model_tint", whole[1])
						out.surface_set_material(i, tinted)
				return out
	return null


static func _tinted(base: ArrayMesh, color: Color) -> ArrayMesh:
	var out := _copy(base)
	var pick := func(m: ShaderMaterial) -> bool: return m.resource_name == TIER_MATERIAL
	var change := func(m: ShaderMaterial) -> void:
		var alpha: Color = m.get_shader_parameter("albedo")
		m.set_shader_parameter("albedo", Color(color, alpha.a))
		m.set_shader_parameter("sprite_cells", 0)  # the sprite shows the base tier's colour
		m.set_shader_parameter("part_colors", false)  # ... and so do the part colours
	edit_materials(out, pick, change)
	return out


## A copy of a model with the same surfaces and materials, made from its arrays on the CPU
## (ModelLods.arrays_of): Resource.duplicate() reads an ArrayMesh's surfaces back from the GPU.
static func _copy(base: ArrayMesh) -> ArrayMesh:
	var out := ArrayMesh.new()
	var kept: Array = []
	for i in base.get_surface_count():
		var arrays := ModelLods.arrays_of(base, i)
		out.add_surface_from_arrays(base.surface_get_primitive_type(i), arrays, [], {}, base.surface_get_format(i) & ModelLods.CUSTOM_FORMATS)
		out.surface_set_material(i, base.surface_get_material(i))
		out.surface_set_name(i, base.surface_get_name(i))
		kept.append(arrays)
	out.set_meta(ModelLods.ARRAYS_META, kept)
	return out


## Gives every surface of a model its own copy of the material with the model's sprite.
## A vehicle's projection is still being built on a thread: its materials get their own copies
## now and the sprite once it's ready (changing a material shows on meshes already drawn).
static func _project_sprite(mesh: ArrayMesh, name: String) -> void:
	var pending := SpriteProjection.pending(name)
	var projection: SpriteProjection.SpriteSheet = null
	if not pending:
		projection = SpriteProjection.for_model(name)
		if projection == null:
			return
	var copies: Array[ShaderMaterial] = []
	for i in mesh.get_surface_count():
		var material := mesh.surface_get_material(i) as ShaderMaterial
		if material != null:
			var copy := ModelLods.copy_material(material)
			if projection != null:
				SpriteProjection.apply(copy, projection)
			mesh.surface_set_material(i, copy)
			copies.append(copy)
	if pending:
		SpriteProjection.when_ready(name, _apply_projection.bind(copies, name))


static func _apply_projection(materials: Array[ShaderMaterial], name: String) -> void:
	var projection := SpriteProjection.for_model(name)
	if projection != null:
		for material in materials:
			SpriteProjection.apply(material, projection)


# --- Loading on worker threads ------------------------------------------------------------------
## A model's first appearance cost 20-250 ms on the main thread: loading the imported scene, then
## SurfaceTool reading every mesh back from the GPU to merge it. Now its .glb is parsed and merged on
## a worker thread (Load: CPU arrays only, nothing touches the GPU), and the main thread only makes
## the ArrayMesh and its materials (poll(), within FINISH_USEC a frame). Chunks, ghosts and movers ask
## with ready() and draw nothing of a model until it is; mesh_for() still answers at once for
## everything else, finishing (or doing) the work there. An exported game ships the .glb files too
## (addons/zenith_export); only an imported scene without its .glb loads the old way (SCENE_SOURCE).
const GLTF_SOURCE := "gltf:"
const SCENE_SOURCE := "scene:"
## Models parsed at once (terrain meshing and LODs share the worker pool).
const LOAD_JOBS := 3
## Main-thread time a frame spends making the models whose jobs are done (at least one).
const FINISH_USEC := 4000  # its slice in frame_budget.gd
const FrameBudget := preload("res://scripts/world/frame_budget.gd")
static var _sources := {}  # name -> GLTF_SOURCE + path, SCENE_SOURCE + path, or ""
static var _jobs := {}  # name -> [task id (-1 while queued), Load]
static var _job_order: Array[String] = []
## Goes up whenever models become ready, so whatever skipped them can be drawn again.
static var generation := 0


## A model's .glb read and merged on a worker thread: per surface [keys, arrays, custom formats],
## a key = [imported material, has COLOR, UV2, CUSTOM0, glow style, has CUSTOM1] as _factorio()
## takes them; and per moving part [node name, pivot, its surfaces]. Pure CPU work. A surface has
## more than one key when the materials of one shader were merged into it (combined()): CUSTOM2.r
## is then each vertex's key, its row of the merged material (material_rows.gd).
class Load:
	var path := ""
	var ok := false
	var groups: Array = []
	var parts: Array = []
	var usec := 0
	## Off: a surface per material, as before the merge (for comparisons).
	var combine := true
	## The format bits of CUSTOM0 and CUSTOM1 (the baked views and part colours).
	const CUSTOM_KEEP := (Mesh.ARRAY_FORMAT_CUSTOM_MASK << Mesh.ARRAY_FORMAT_CUSTOM_BASE) \
		| (Mesh.ARRAY_FORMAT_CUSTOM_MASK << (Mesh.ARRAY_FORMAT_CUSTOM_BASE + Mesh.ARRAY_FORMAT_CUSTOM_BITS))

	func run() -> void:
		var t0 := Time.get_ticks_usec()
		var doc := GLTFDocument.new()
		var state := GLTFState.new()
		if doc.append_from_file(path, state) == OK:
			ModelTextures.prepare(path, state)
			var nodes := state.get_nodes()
			var meshes := state.get_meshes()
			var tools := {}
			var order: Array = []
			for r in state.root_nodes:
				_walk(nodes, meshes, r, Transform3D.IDENTITY, tools, order, true, "")
			groups = combined(merged(tools, order), combine)
			for p: Array in parts:
				p[2] = combined(p[2], combine)
			ok = true
		usec = Time.get_ticks_usec() - t0

	## As ModelLibrary._collect, over the glTF's nodes: `in_parts` false inside a moving part.
	func _walk(nodes: Array, meshes: Array, i: int, parent: Transform3D, tools: Dictionary, order: Array, in_parts: bool, glow: String) -> void:
		var node: GLTFNode = nodes[i]
		var xform := parent * node.xform
		var node_name := str(node.resource_name) if str(node.resource_name) != "" else str(node.original_name)
		if node_name.begins_with("anim_glow"):
			glow = kind(node_name).trim_prefix("glow").trim_prefix("_")
			if glow == "":
				glow = "on"
		elif node_name.begins_with("anim_") and in_parts:
			var part_tools := {}
			var part_order: Array = []
			_walk(nodes, meshes, i, parent, part_tools, part_order, false, glow)
			parts.append([node_name, xform, merged(part_tools, part_order)])
			return
		if node.mesh >= 0 and node.mesh < meshes.size():
			var gltf_mesh: GLTFMesh = meshes[node.mesh]
			var mesh: ImporterMesh = gltf_mesh.mesh
			var overrides: Array = gltf_mesh.instance_materials
			for k in mesh.get_surface_count():
				if mesh.get_surface_primitive_type(k) != Mesh.PRIMITIVE_TRIANGLES:
					continue
				var arrays := mesh.get_surface_arrays(k)
				var material: Material = mesh.get_surface_material(k)
				if k < overrides.size() and overrides[k] != null:
					material = overrides[k]
				var key := [material, arrays[Mesh.ARRAY_COLOR] != null, arrays[Mesh.ARRAY_TEX_UV2] != null,
					arrays[Mesh.ARRAY_CUSTOM0] != null, glow, arrays[Mesh.ARRAY_CUSTOM1] != null]
				var flags := mesh.get_surface_format(k) & (0xFFF << Mesh.ARRAY_FORMAT_CUSTOM_BASE)
				var at := key + [flags]
				if not tools.has(at):
					tools[at] = []
					order.append(at)
				(tools[at] as Array).append([arrays, xform])
		for c in node.children:
			_walk(nodes, meshes, c, xform, tools, order, in_parts, glow)

	## Each group's surfaces in one set of arrays, moved by their nodes' transforms (as
	## SurfaceTool.append_from): [[key, arrays, custom formats], ...].
	static func merged(tools: Dictionary, order: Array) -> Array:
		var out: Array = []
		for at: Array in order:
			var members: Array = tools[at]
			var present := {}  # array type -> [an array of it, values per vertex]
			for m: Array in members:
				var a: Array = m[0]
				for t in Mesh.ARRAY_MAX:
					if t != Mesh.ARRAY_INDEX and t != Mesh.ARRAY_TANGENT and a[t] != null:
						present[t] = [a[t], a[t].size() / maxi((a[Mesh.ARRAY_VERTEX] as PackedVector3Array).size(), 1)]
			var arrays := []
			arrays.resize(Mesh.ARRAY_MAX)
			var index := PackedInt32Array()
			for t in present:
				arrays[t] = present[t][0].duplicate()
				arrays[t].clear()
			for m: Array in members:
				var a: Array = m[0]
				var xform: Transform3D = m[1]
				var verts: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
				var n := verts.size()
				var base: int = (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
				var normal_basis := xform.basis.inverse().transposed()
				for t in present:
					var src = a[t]
					if t == Mesh.ARRAY_VERTEX:
						arrays[t].append_array(xform * verts)
					elif t == Mesh.ARRAY_NORMAL and src != null:
						# A copy: the glTF's arrays are shared with every node using the same mesh.
						var normals: PackedVector3Array = (src as PackedVector3Array).duplicate()
						for v in normals.size():
							normals[v] = (normal_basis * normals[v]).normalized()
						arrays[t].append_array(normals)
					elif src != null:
						arrays[t].append_array(src)
					else:
						# Missing in this member: zeros of the others' size per vertex.
						var fill = present[t][0].duplicate()
						fill.resize(0)
						fill.resize(n * maxi(int(present[t][1]), 1))
						arrays[t].append_array(fill)
				var idx = a[Mesh.ARRAY_INDEX]
				if idx is PackedInt32Array and not (idx as PackedInt32Array).is_empty():
					for k in (idx as PackedInt32Array):
						index.append(base + k)
				else:
					for k in n:
						index.append(base + k)
			arrays[Mesh.ARRAY_INDEX] = index
			out.append([at.slice(0, 6), arrays, int(at[6])])
		return out

	## merged()'s groups drawn with one shader (variant()) in one surface each, each vertex's group
	## (its row) in CUSTOM2.r, up to MaterialRows.MAX_ROWS groups a surface: [[keys], arrays, custom
	## formats], in the order of each shader's first group. A group alone keeps its arrays as they
	## are. Groups whose custom channels differ in format from the rest stay apart, and so does a
	## textured material's (FUE5's models, model_textures.gd): its textures are its own uniforms.
	static func combined(groups: Array, combine := true) -> Array:
		var by_shader := {}
		var order: Array = []
		for g: Array in groups:
			var v: Variant = variant(g[0][0]) if combine and not textured(g[0][0]) else "alone %d" % order.size()
			if not by_shader.has(v):
				by_shader[v] = []
				order.append(v)
			(by_shader[v] as Array).append(g)
		var out: Array = []
		for v in order:
			var members: Array = by_shader[v]
			var same := true
			for g: Array in members:
				var arrays: Array = g[1]
				same = same and arrays[Mesh.ARRAY_CUSTOM2] == null and arrays[Mesh.ARRAY_CUSTOM3] == null
				for c in [0, 1]:
					if arrays[Mesh.ARRAY_CUSTOM0 + c] != null and _custom_format(int(g[2]), c) != Mesh.ARRAY_CUSTOM_RGBA_FLOAT:
						same = false
			if members.size() == 1 or not same:
				for g: Array in members:
					out.append([[g[0]], g[1], g[2]])
				continue
			for k in range(0, members.size(), MaterialRows.MAX_ROWS):
				out.append(_joined(members.slice(k, k + MaterialRows.MAX_ROWS)))
		return out

	## The shader a key's material is drawn with, as _factorio() picks it: 0 solid, 1 see-through,
	## 2 leaf cards.
	static func variant(material: Material) -> int:
		var base := material as BaseMaterial3D
		if base == null:
			return 0
		if base.resource_name.begins_with("leafcard"):
			return 2
		return 1 if base.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED else 0

	## True for a material with a base colour or roughness texture.
	static func textured(material: Material) -> bool:
		var base := material as BaseMaterial3D
		return base != null and (base.albedo_texture != null or base.roughness_texture != null)

	static func _custom_format(flags: int, c: int) -> int:
		return (flags >> (Mesh.ARRAY_FORMAT_CUSTOM_BASE + c * Mesh.ARRAY_FORMAT_CUSTOM_BITS)) & Mesh.ARRAY_FORMAT_CUSTOM_MASK

	## Groups (all RGBA_FLOAT custom channels or none) one after another in one set of arrays, a
	## missing array zeros (its key says so: _factorio's vertex_data and the rest), CUSTOM2 the rows.
	static func _joined(members: Array) -> Array:
		var present := {}  # array type -> an empty array of its kind, values per vertex
		for g: Array in members:
			var a: Array = g[1]
			for t in Mesh.ARRAY_MAX:
				if t != Mesh.ARRAY_INDEX and t != Mesh.ARRAY_TANGENT and a[t] != null and not present.has(t):
					var empty = a[t].duplicate()
					empty.clear()
					present[t] = [empty, a[t].size() / maxi((a[Mesh.ARRAY_VERTEX] as PackedVector3Array).size(), 1)]
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		for t in present:
			arrays[t] = present[t][0].duplicate()
		var rows := PackedFloat32Array()
		var index := PackedInt32Array()
		var keys: Array = []
		var flags := 0
		for row in members.size():
			var g: Array = members[row]
			var a: Array = g[1]
			keys.append(g[0])
			flags |= int(g[2])
			var n := (a[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
			var base := rows.size()
			for t in present:
				if a[t] != null:
					arrays[t].append_array(a[t])
				else:
					arrays[t].append_array(_none(t, present[t][0], n * maxi(int(present[t][1]), 1)))
			rows.resize(base + n)
			if row > 0:
				for k in range(base, base + n):
					rows[k] = float(row)
			var idx: PackedInt32Array = a[Mesh.ARRAY_INDEX]
			var from := index.size()
			index.append_array(idx)
			if base > 0:
				for k in range(from, index.size()):
					index[k] += base
		arrays[Mesh.ARRAY_INDEX] = index
		arrays[Mesh.ARRAY_CUSTOM2] = rows
		flags = (flags & CUSTOM_KEEP) | (Mesh.ARRAY_CUSTOM_R_FLOAT << (Mesh.ARRAY_FORMAT_CUSTOM_BASE + 2 * Mesh.ARRAY_FORMAT_CUSTOM_BITS))
		return [keys, arrays, flags]

	## `count` values of array type `t` that read as "none" in factorio_material (the shader drops
	## the data flags on merged surfaces): white COLOR (no tint, open), UV2 (0, 0.5) (no worn edge,
	## the middle random), CUSTOM0 1 (seen from Factorio's camera: the face's angle decides); zeros
	## for the rest (no part colour).
	static func _none(t: int, empty: Variant, count: int) -> Variant:
		var fill = empty.duplicate()
		fill.resize(count)
		match t:
			Mesh.ARRAY_COLOR:
				fill.fill(Color(1, 1, 1, 1))
			Mesh.ARRAY_TEX_UV2:
				fill.fill(Vector2(0.0, 0.5))
			Mesh.ARRAY_CUSTOM0:
				fill.fill(1.0)
		return fill

	static func kind(node_name: String) -> String:
		var k := node_name.substr(5).get_slice(".", 0)
		while k.length() > 0 and k[k.length() - 1].is_valid_int():
			k = k.substr(0, k.length() - 1)
		return k.trim_suffix("_")


## Where a model comes from: GLTF_SOURCE + its .glb or .gltf (readable as a file: the project's own
## models, also in an exported game, and --models=<dir>), SCENE_SOURCE + an imported scene without
## its file, or "" (no model of that name).
static func _source(name: String) -> String:
	if _sources.has(name):
		return _sources[name]
	var file := name
	var family := CreatureModels.base_model(name)
	if family != "":
		file = family
	var found := ""
	var external := _external_path(file)
	if external_first and external != "":
		found = GLTF_SOURCE + external
	for sub in MODEL_SUBDIRS:
		if found == "" and FileAccess.file_exists("res://assets/models/%s%s.glb" % [sub, file]):
			found = GLTF_SOURCE + "res://assets/models/%s%s.glb" % [sub, file]
	for ext in ["glb", "gltf"]:
		if found != "":
			break
		var res_path := "res://assets/models/%s.%s" % [file, ext]
		# An exported game has the .glb itself (addons/zenith_export) and no imported scene.
		if FileAccess.file_exists(res_path):
			found = GLTF_SOURCE + res_path
			break
		if ResourceLoader.exists(res_path):
			found = SCENE_SOURCE + res_path
			break
	if found == "" and external != "":
		found = GLTF_SOURCE + external
	_sources[name] = found
	return found


## True when the model of `name` (or the knowledge that there is none) is ready: mesh_for() then
## answers at once. Otherwise starts making it on a worker thread and returns false; `generation`
## goes up once it is ready.
static func ready(name: String) -> bool:
	if _cache.has(name):
		return true
	var source := _source(name)
	if source.begins_with(GLTF_SOURCE):
		if not _jobs.has(name):
			var load := Load.new()
			load.path = source.substr(GLTF_SOURCE.length())
			load.combine = merge_materials
			_jobs[name] = [-1, load]
			_job_order.append(name)
		return false
	if source == "":
		if MODEL_ALIASES.has(name) and not ready(MODEL_ALIASES[name]):
			return false
		var base := _tier_base(name)
		if base != "" and not ready(base):
			return false
	mesh_for(name)  # an exported game's scene, an alias or tier of a ready model, or nothing
	return true


## ready() for an entity record's model (mesh_for_entity: its variant, else the prototype's).
static func entity_ready(proto_name: String, proto_type: String, extra: Dictionary, dir := 0) -> bool:
	var variant := model_name(proto_name, proto_type, extra, dir)
	if variant != proto_name:
		if not ready(variant):
			return false
		if _cache[variant] != null:
			return true
	return ready(proto_name)


## Starts waiting jobs and makes the models whose jobs are done, within FINISH_USEC. True when
## some became ready (`generation` went up).
static func poll() -> bool:
	var running := 0
	for name in _job_order:
		var entry: Array = _jobs[name]
		if int(entry[0]) >= 0:
			running += 1
	for name in _job_order:
		if running >= LOAD_JOBS:
			break
		var entry: Array = _jobs[name]
		if int(entry[0]) < 0:
			entry[0] = WorkerThreadPool.add_task((entry[1] as Load).run, false, "model " + name)
			running += 1
	var start := Time.get_ticks_usec()
	var made := 0
	var done := 0  # jobs finished on their worker, waiting to be made here
	for name in _job_order:
		var entry: Array = _jobs[name]
		if int(entry[0]) >= 0 and WorkerThreadPool.is_task_completed(entry[0]):
			done += 1
	if done == 0 and _remnant_jobs.is_empty():
		FrameBudget.waiting(&"models", 0)
		return false
	var allow := FrameBudget.grant(&"models")
	for name in _job_order.duplicate():
		if allow <= 0 or (made > 0 and Time.get_ticks_usec() - start > allow):
			break
		var entry: Array = _jobs.get(name, [])
		if entry.is_empty() or int(entry[0]) < 0 or not WorkerThreadPool.is_task_completed(entry[0]):
			continue
		_polling = true
		mesh_for(name)
		_polling = false
		made += 1
		done -= 1
	if allow > 0:
		made += _finish_remnants()
	FrameBudget.spent(&"models", Time.get_ticks_usec() - start, maxi(done, 0))
	if made > 0:
		generation += 1
	return made > 0


## True while models are being made on worker threads.
static func loading() -> bool:
	return not _jobs.is_empty()


## The finished Load for a model: waits for its job, runs it here if it hasn't started, or (with
## no job) reads the file here.
static func _built(name: String) -> Load:
	var load: Load = null
	if _jobs.has(name):
		var entry: Array = _jobs[name]
		_jobs.erase(name)
		_job_order.erase(name)
		load = entry[1]
		if int(entry[0]) >= 0:
			WorkerThreadPool.wait_for_task_completion(entry[0])
		else:
			_parsed_here = true
			load.run()
	else:
		load = Load.new()
		load.path = _source(name).substr(GLTF_SOURCE.length())
		load.combine = merge_materials
		_parsed_here = true
		load.run()
	return load


## The model's mesh and moving parts (into `parts`) from its Load, on the main thread.
static func _commit_load(load: Load, parts: Array) -> Mesh:
	var first := parts.size()
	var mesh := _commit_groups(load.groups)
	for p: Array in load.parts:
		var part := _new_part(str(p[0]), p[1])
		part.mesh = _commit_groups(p[2])
		if part.mesh != null:
			parts.append(part)
	return mesh


## An ArrayMesh of merged surfaces ([keys, arrays, custom formats]), keeping its arrays on the CPU
## (ModelLods.arrays_of) so nothing reads them back from the GPU later. A surface of several keys
## gets one material with a row for each (material_rows.gd).
static func _commit_groups(groups: Array) -> ArrayMesh:
	if groups.is_empty():
		return null
	var out := ArrayMesh.new()
	var kept: Array = []
	for g: Array in groups:
		var rows: Array = []
		for key: Array in g[0]:
			rows.append(_factorio(key[0], key[1], key[2], key[3], key[4], key[5]))
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, g[1], [], {}, int(g[2]))
		out.surface_set_material(out.get_surface_count() - 1, rows[0] if rows.size() == 1 else MaterialRows.make(rows))
		kept.append(g[1])
	out.set_meta(ModelLods.ARRAYS_META, kept)
	return out


## Every surface's material changed by MaterialRows.edit (the rows `pick` chooses, or the surface's
## own material if picked, each changed on a copy by `change`).
static func edit_materials(mesh: ArrayMesh, pick: Callable, change: Callable) -> void:
	if mesh == null:
		return
	for i in mesh.get_surface_count():
		var material := mesh.surface_get_material(i)
		var edited := MaterialRows.edit(material, pick, change)
		if edited != material:
			mesh.surface_set_material(i, edited)


## The materials (or rows) named `material_name` given `param` = `value` (inserter_arms.gd).
static func set_named(mesh: ArrayMesh, material_name: String, param: String, value: Variant) -> void:
	var pick := func(m: ShaderMaterial) -> bool: return m.resource_name == material_name
	var change := func(m: ShaderMaterial) -> void: m.set_shader_parameter(param, value)
	edit_materials(mesh, pick, change)


static func _load_scene(name: String) -> Node:
	var family := CreatureModels.base_model(name)
	if family != "":
		name = family
	var external := _external_path(name)
	if not (external_first and external != ""):
		for sub in MODEL_SUBDIRS:
			if ResourceLoader.exists("res://assets/models/%s%s.glb" % [sub, name]):
				var sub_packed := load("res://assets/models/%s%s.glb" % [sub, name]) as PackedScene
				if sub_packed != null:
					return sub_packed.instantiate()
		for ext in ["glb", "gltf"]:
			var res_path := "res://assets/models/%s.%s" % [name, ext]
			if ResourceLoader.exists(res_path):
				var packed := load(res_path) as PackedScene
				if packed != null:
					return packed.instantiate()
	if external != "":
		var doc := GLTFDocument.new()
		var state := GLTFState.new()
		if doc.append_from_file(external, state) == OK:
			return doc.generate_scene(state)
	return null


## Merges every MeshInstance3D under `root` into one ArrayMesh, one surface per material.
## Skeletons and animations are dropped: this is for static, instanced drawing. Moving parts
## (`anim_*` nodes other than `anim_glow_*`) are left out and flattened on their own into `parts`.
static func _flatten(root: Node, parts: Array) -> Mesh:
	var tools := {}  # Material (or null) -> SurfaceTool
	var order: Array = []
	var first := parts.size()
	_collect(root, Transform3D.IDENTITY, tools, order, parts, "")
	var mesh := _commit(tools, order)
	return mesh


static func _commit(tools: Dictionary, order: Array) -> ArrayMesh:
	if order.is_empty():
		return null
	var out := ArrayMesh.new()
	for material in order:
		var st: SurfaceTool = tools[material]
		st.commit(out)
		out.surface_set_material(out.get_surface_count() - 1, material)
	return out


## `parts` collects moving parts; null inside a moving part (nested ones turn with it). `glow`
## is the style of the `anim_glow_*` node it is under ("on" for a plain one), "" outside one.
static func _collect(node: Node, parent: Transform3D, tools: Dictionary, order: Array, parts, glow: String) -> void:
	var xform := parent
	if node is Node3D:
		xform = parent * (node as Node3D).transform
	var node_name := str(node.name)
	if node_name.begins_with(GLOW_PREFIX):
		glow = anim_kind(node_name).trim_prefix("glow").trim_prefix("_")
		if glow == "":
			glow = "on"
	elif node_name.begins_with(ANIM_PREFIX) and parts != null:
		var part := _new_part(node_name, xform)
		var part_tools := {}
		var part_order: Array = []
		_collect(node, parent, part_tools, part_order, null, glow)
		part.mesh = _commit(part_tools, part_order)
		if part.mesh != null:
			parts.append(part)
		return
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.mesh != null:
			for i in mi.mesh.get_surface_count():
				var format := int(mi.mesh.surface_get_format(i))
				var material := _factorio(mi.get_active_material(i), (format & Mesh.ARRAY_FORMAT_COLOR) != 0,
					(format & Mesh.ARRAY_FORMAT_TEX_UV2) != 0, (format & Mesh.ARRAY_FORMAT_CUSTOM0) != 0, glow,
					(format & Mesh.ARRAY_FORMAT_CUSTOM1) != 0)
				if not tools.has(material):
					var st := SurfaceTool.new()
					st.begin(Mesh.PRIMITIVE_TRIANGLES)
					tools[material] = st
					order.append(material)
				var tool: SurfaceTool = tools[material]
				tool.append_from(mi.mesh, i, xform)
	for child in node.get_children():
		_collect(child, xform, tools, order, parts, glow)


## The moving part a node named `anim_<kind>` makes, its pivot at `xform`; its mesh comes after.
static func _new_part(node_name: String, xform: Transform3D) -> AnimPart:
	var part := AnimPart.new()
	part.kind = anim_kind(node_name)
	if part.kind.begins_with(UPRIGHT_PREFIX):
		part.upright = true
		part.kind = part.kind.substr(UPRIGHT_PREFIX.length())
	part.pivot = xform
	part.axis = Vector3.UP
	if X_AXIS_KINDS.has(part.kind):
		part.axis = Vector3.RIGHT
	elif Z_AXIS_KINDS.has(part.kind):
		part.axis = Vector3.BACK
	part.slide = SLIDE_KINDS.get(part.kind, Vector3.ZERO)
	var moves: Dictionary = CYCLES.get(part.kind, HATCHES.get(part.kind, {}))
	if moves.has("slide"):
		part.slide = moves["slide"]
	if moves.has("axis"):
		part.axis = moves["axis"]
	part.lit = part.kind.begins_with(LIT_PREFIX)
	return part


## A moving part's kind from its node name: "anim_spin_drill" -> "spin_drill". Godot names
## duplicates "anim_spin_drill2" and Blender "anim_spin_drill.001": both drop the number.
static func anim_kind(node_name: String) -> String:
	var kind := node_name.substr(ANIM_PREFIX.length()).get_slice(".", 0)
	while kind.length() > 0 and kind[kind.length() - 1].is_valid_int():
		kind = kind.substr(0, kind.length() - 1)
	return kind.trim_suffix("_")


## The Factorio material for an imported one: same colour, roughness, metallic and emission,
## weathered by its material class. Shared by every surface with the same material and data.
## Emissive materials, and anything under an `anim_glow_*` node (`glow`), light up only while
## the machine works.
static func _factorio(material: Material, has_color: bool, has_uv2: bool, has_views: bool, glow := "",
		has_parts := false) -> Material:
	var key := [material, has_color, has_uv2, has_views, glow, has_parts]
	if _factorio_cache.has(key):
		return _factorio_cache[key]
	var base := material as BaseMaterial3D
	var out := ShaderMaterial.new()
	var name := base.resource_name if base != null else ""
	out.resource_name = name
	var see_through := base != null and base.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED
	out.shader = FactorioAlphaShader if see_through else FactorioShader
	if name.begins_with("leafcard"):
		out.shader = FactorioLeafShader
	# Cliffs' rock sits on the low ground when there are hills (ground_height.gd).
	if name.begins_with("cliff-"):
		out.set_shader_parameter("ground_low", true)
	if base != null:
		out.set_shader_parameter("albedo", base.albedo_color)
		out.set_shader_parameter("roughness", base.roughness)
		out.set_shader_parameter("metallic", base.metallic)
		# A model's own pictures (model_textures.gd): base colour, and glTF's metallic-roughness.
		if base.albedo_texture != null:
			out.set_shader_parameter("albedo_tex", base.albedo_texture)
			out.set_shader_parameter("use_albedo_tex", true)
		if base.roughness_texture != null:
			out.set_shader_parameter("orm_tex", base.roughness_texture)
			out.set_shader_parameter("use_orm_tex", true)
		if base.emission_enabled:
			out.set_shader_parameter("emission", base.emission)
			out.set_shader_parameter("emission_energy", base.emission_energy_multiplier)
			out.set_shader_parameter("activity_glow", true)
			out.set_shader_parameter("glow_fades", see_through)
		elif glow != "":
			out.set_shader_parameter("emission", base.albedo_color)
			out.set_shader_parameter("emission_energy", 1.5)
	if glow != "":
		out.set_shader_parameter("activity_glow", true)
	var style: Dictionary = GLOW_STYLES.get(glow, {})
	if style.is_empty() and base != null and base.emission_enabled:
		for word in FIRE_MATERIALS:
			if name.contains(word):
				style = GLOW_STYLES["fire"]
	for param in style:
		out.set_shader_parameter(param, style[param])
	out.set_shader_parameter("vertex_data", 1.0 if has_color else 0.0)
	out.set_shader_parameter("edge_data", 1.0 if has_uv2 else 0.0)
	out.set_shader_parameter("view_data", 1.0 if has_views else 0.0)
	out.set_shader_parameter("part_data", 1.0 if has_parts else 0.0)
	out.set_shader_parameter("part_colors", look != "palette")
	var params: Dictionary = CLASS_PARAMS[material_class(name, base != null and base.emission_enabled)]
	for param in params:
		out.set_shader_parameter(param, params[param])
	_factorio_cache[key] = out
	return out


## How a material weathers, from its name: a key of CLASS_PARAMS.
static func material_class(material_name: String, emissive := false) -> String:
	if emissive:
		return "emissive"
	var lower := material_name.to_lower()
	for entry in MATERIAL_CLASSES:
		if lower.contains(str(entry[0])):
			return str(entry[1])
	return "paint"


## True for prototypes that are never drawn (HIDDEN_PROTOS, "dummy-...").
static func hidden(proto_name: String) -> bool:
	return HIDDEN_PROTOS.has(proto_name) or proto_name.begins_with("dummy-")


# --- Remnants ------------------------------------------------------------------------------------
## What a destroyed building leaves on the ground: corpse and rail-remnants records carry the
## prototype id of what died in extra.rm (world.lua). Factorio draws them as the building's own
## picture knocked down, broken and burnt; here its model, flattened (REMNANT_SQUASH), pieces of
## it pushed about and some dropped, darkened and grimed (remnant_mesh). Without a model, a low
## heap of rubble (rubble_mesh), sized to the entity by the caller. Made once per model.
const REMNANT_TYPES := {"corpse": true, "rail-remnants": true}
const REMNANT_SQUASH := 0.22
## Pieces are 0.6-tile cells of the model: each sinks, tilts and slides as one.
const REMNANT_CELL := 0.6
## Share of the upper pieces knocked away, and of all triangles.
const REMNANT_DROP_HIGH := 0.45
const REMNANT_DROP := 0.12
static var _remnant_cache := {}  # model name -> Mesh or null
static var _remnant_jobs := {}  # model name -> [task id, the job's result]
static var _rubble: ArrayMesh


static func remnant_mesh(name: String) -> Mesh:
	if _remnant_cache.has(name):
		return _remnant_cache[name]
	var src := mesh_for(name) as ArrayMesh
	var t0 := Time.get_ticks_usec()
	var out: Mesh = null
	if src != null:
		var job: Array = _remnant_jobs.get(name, [])
		_remnant_jobs.erase(name)
		var result := {}
		if job.is_empty():
			_broken_arrays(_surfaces_of(src), maxf(src.get_aabb().end.y, 0.1), hash(name), result)
		else:
			WorkerThreadPool.wait_for_task_completion(job[0])
			result = job[1]
		out = _broken_mesh(src, result)
	load_usec += Time.get_ticks_usec() - t0
	_remnant_cache[name] = out
	return out


## ready() for a remnant: true once remnant_mesh(name) answers at once; otherwise its model and then
## its breaking up are done on worker threads (20-30 ms a big model on the main thread before).
static func remnant_ready(name: String) -> bool:
	if _remnant_cache.has(name):
		return true
	if not ready(name):
		return false
	var src := mesh_for(name) as ArrayMesh
	if src == null:
		_remnant_cache[name] = null
		return true
	if not _remnant_jobs.has(name):
		var result := {}
		var task := WorkerThreadPool.add_task(_broken_arrays.bind(_surfaces_of(src), maxf(src.get_aabb().end.y, 0.1), hash(name), result), false, "remnant " + name)
		_remnant_jobs[name] = [task, result]
	return false


## Makes the remnants whose jobs are done (poll()); how many.
static func _finish_remnants() -> int:
	var made := 0
	for name in _remnant_jobs.keys():
		if WorkerThreadPool.is_task_completed(_remnant_jobs[name][0]):
			remnant_mesh(name)
			made += 1
	return made


static func _surfaces_of(src: ArrayMesh) -> Array:
	var out: Array = []
	for i in src.get_surface_count():
		out.append(ModelLods.arrays_of(src, i))
	return out


static func _cell_rand(cell: Vector2i, seed: int, k: int) -> float:
	return float(hash([cell.x, cell.y, seed, k]) & 0xffff) / 65535.0


## The model's surfaces broken up (pure arithmetic, run on a worker thread): `out` gets each
## surface's index -> its new arrays, for the surfaces with anything left.
static func _broken_arrays(surfaces: Array, top: float, seed: int, out: Dictionary) -> void:
	for i in surfaces.size():
		var arrays: Array = surfaces[i]
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var index := PackedInt32Array()
		if arrays[Mesh.ARRAY_INDEX] != null:
			index = arrays[Mesh.ARRAY_INDEX]
		if index.is_empty():
			index.resize(verts.size())
			for v in verts.size():
				index[v] = v
		# Whole pieces of the upper part go, and odd triangles anywhere.
		var kept := PackedInt32Array()
		for t in range(0, index.size() - 2, 3):
			var c := (verts[index[t]] + verts[index[t + 1]] + verts[index[t + 2]]) / 3.0
			var cell := Vector2i(floori(c.x / REMNANT_CELL), floori(c.z / REMNANT_CELL))
			var r := float(hash([t, seed]) & 0xffff) / 65535.0
			if (c.y > top * 0.3 and _cell_rand(cell, seed, 9) < REMNANT_DROP_HIGH) or r < REMNANT_DROP:
				continue
			kept.append(index[t])
			kept.append(index[t + 1])
			kept.append(index[t + 2])
		if kept.is_empty():
			continue
		# The rest squashed flat, each piece sunk, tilted and slid (higher parts further).
		for v in verts.size():
			var p := verts[v]
			var cell := Vector2i(floori(p.x / REMNANT_CELL), floori(p.z / REMNANT_CELL))
			var sink := 0.5 + _cell_rand(cell, seed, 1)
			var slide := Vector2(_cell_rand(cell, seed, 2) - 0.5, _cell_rand(cell, seed, 3) - 0.5) * 0.35 * minf(p.y, 1.5)
			var tilt := Vector2(_cell_rand(cell, seed, 4) - 0.5, _cell_rand(cell, seed, 5) - 0.5) * 0.25
			var y := p.y * REMNANT_SQUASH * sink + tilt.x * (p.x - cell.x * REMNANT_CELL) + tilt.y * (p.z - cell.y * REMNANT_CELL)
			verts[v] = Vector3(p.x + slide.x, maxf(y, 0.0), p.z + slide.y)
		if arrays[Mesh.ARRAY_NORMAL] is PackedVector3Array:
			var n: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			for v in n.size():
				n[v] = Vector3(n[v].x * REMNANT_SQUASH, n[v].y, n[v].z * REMNANT_SQUASH).normalized()
			arrays[Mesh.ARRAY_NORMAL] = n
		arrays[Mesh.ARRAY_VERTEX] = verts
		arrays[Mesh.ARRAY_INDEX] = kept
		arrays[Mesh.ARRAY_TANGENT] = null
		out[i] = arrays


## The remnant mesh from _broken_arrays' surfaces, with burnt materials (main thread).
static func _broken_mesh(src: ArrayMesh, broken: Dictionary) -> ArrayMesh:
	var out := ArrayMesh.new()
	var kept: Array = []
	for i in src.get_surface_count():
		if not broken.has(i):
			continue
		var format := src.surface_get_format(i)
		var flags := 0
		for k in 4:
			var shift: int = Mesh.ARRAY_FORMAT_CUSTOM_BASE + k * Mesh.ARRAY_FORMAT_CUSTOM_BITS
			flags |= format & (Mesh.ARRAY_FORMAT_CUSTOM_MASK << shift)
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, broken[i], [], {}, flags)
		out.surface_set_material(out.get_surface_count() - 1, _burnt(src.surface_get_material(i)))
		kept.append(broken[i])
	out.set_meta(ModelLods.ARRAYS_META, kept)
	return out if out.get_surface_count() > 0 else null


## The model's material, burnt: darker, greyer, sooty and rusty, with no sprite and no glow.
static func _burnt(material: Material) -> Material:
	var m := material as ShaderMaterial
	if m == null:
		return material
	var key := [m, "burnt"]
	if _factorio_cache.has(key):
		return _factorio_cache[key]
	var burn := func(b: ShaderMaterial) -> void:
		b.set_shader_parameter("sprite_cells", 0)
		b.set_shader_parameter("depth_on", false)
		b.set_shader_parameter("activity_glow", false)
		b.set_shader_parameter("animated", false)
		b.set_shader_parameter("emission_energy", 0.0)
		b.set_shader_parameter("value", 0.45)
		b.set_shader_parameter("desaturate", 0.45)
		b.set_shader_parameter("part_light", Vector2(0.95, 0.6) * 0.42)
		b.set_shader_parameter("grime", 1.0)
		b.set_shader_parameter("grime_color", Color(0.06, 0.05, 0.045))
		b.set_shader_parameter("ground_grime_height", 1.5)
		b.set_shader_parameter("rust", 0.45)
		b.set_shader_parameter("dust", 0.35)
		b.set_shader_parameter("dust_color", Color(0.3, 0.27, 0.23))
	# Every row of a merged material (each loses its sprite and glow), else the material itself.
	var burnt := MaterialRows.edit_all(m, burn)
	_factorio_cache[key] = burnt
	return burnt


## A heap of broken plates and blocks a tile across, for remnants without a model.
static func rubble_mesh() -> ArrayMesh:
	if _rubble != null:
		return _rubble
	# Nine boxes merged from BoxMesh's CPU arrays (SurfaceTool.append_from would read them back
	# from the RenderingServer, a wait for the render thread when it runs on its own).
	var box := BoxMesh.new()
	box.size = Vector3.ONE
	var src := box.get_mesh_arrays()
	var src_verts: PackedVector3Array = src[Mesh.ARRAY_VERTEX]
	var src_normals: PackedVector3Array = src[Mesh.ARRAY_NORMAL]
	var src_index: PackedInt32Array = src[Mesh.ARRAY_INDEX]
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var index := PackedInt32Array()
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for k in 9:
		var size := Vector3(rng.randf_range(0.15, 0.4), rng.randf_range(0.04, 0.12), rng.randf_range(0.12, 0.35))
		var at := Vector3(rng.randf_range(-0.35, 0.35), size.y * 0.4, rng.randf_range(-0.35, 0.35))
		var basis := Basis(Vector3.UP, rng.randf() * TAU) * Basis(Vector3.RIGHT, rng.randf_range(-0.3, 0.3))
		var xform := Transform3D(basis * Basis.from_scale(size), at)
		var normal_basis := xform.basis.inverse().transposed()
		var base := verts.size()
		verts.append_array(xform * src_verts)
		for n in src_normals:
			normals.append((normal_basis * n).normalized())
		for i in src_index:
			index.append(base + i)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = index
	_rubble = ArrayMesh.new()
	_rubble.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_rubble.set_meta(ModelLods.ARRAYS_META, [arrays])
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.16, 0.14, 0.12)
	m.roughness = 0.95
	_rubble.surface_set_material(0, m)
	return _rubble
