// Factorio's look for every model. Each part has its own colour, sampled from Factorio's sprite
// when the model was built (CUSTOM1, tools/models/part_colors.py; the material's palette colour
// without one), and a procedural layer paints what the sprites show over it: dark ambient
// occlusion, grime in the crevices and round the base, worn bright edges, rust patches and
// streaks, dust on top, from vertex data baked by tools/models/bake.py (lighter over part colours,
// which carry Factorio's wear already). With the "sprite" look (model_library.gd), the sprite itself
// (sprite_projection.gd builds an atlas from the player's install) is also projected onto the
// model from Factorio's own camera, on the faces that camera sees.
//
// Vertex data (client/assets/models/README.md):
//   COLOR.rgb   albedo multiplier (the nature models' own shading), COLOR.a  ambient occlusion
//   UV2.x       worn edge (1 on bevels and rims)                     UV2.y  random per part
//   CUSTOM0     how much Factorio's camera sees of the vertex with the model facing north, east,
//               south, west (TEXCOORD_2 and _3 in the .glb)
//   CUSTOM1     the part's colour sampled from Factorio's sprite (rgb, linear) and how much of it
//               comes from the sprite (a), by tools/models/part_colors.py (TEXCOORD_4 and _5)
// Missing data (vertex_data / edge_data = 0) means a plain, unoccluded surface.
//
// The weathering uniforms come per material class from model_library.gd: steel rusts, paint
// chips to bare metal, wood and stone only gather dirt, foliage only gets its occlusion.
// Everything varies per instance with a hash of the instance's position, so neighbouring
// machines drawn from one MultiMesh don't look stamped out.
//
// Animation (anim.gd, chunk_view.gd):
//   animated        a moving part (a drill head, a turret head): its mesh is in model space at
//                   rest and its transform turns, so the entity's position (x, z) and direction
//                   (0-3) come from INSTANCE_CUSTOM.rgb instead of MODEL_MATRIX; the sprite and
//                   weathering stay painted on the part as it turns. Parts the shader moves itself
//                   (anim_mode, below) are drawn at the entity's own transform instead.
//   activity_glow   emissive surfaces (fire, anim_glow_* parts) glow by INSTANCE_CUSTOM.a, the
//                   machine's activity (0 idle, 1 working), and darken when idle.
//   glow_flicker    fire (furnaces, boilers, flares): how much the glow flickers, licking up
//                   the surface, at a rate of its own per instance.
//   glow_pulse      lights that breathe (lab, biochamber, fusion): how deep each pulse dims,
//                   glow_rate pulses a second (Factorio's loop: 60 * animation_speed / frames).
//   glow_fades      a see-through emissive material (a plume) is only there while it glows.
//   belt_speed      tiles per second: the belt surface's slats move north (-Z; south when
//                   negative, for underground exits), or round the
//                   arc on curves (belt_shape 1: left curve, 2: right curve).

//
// Tall entities (Factorio's "Toggle visibility of tall entities" shortcut, tall_fade.gd): models
// taller than 2 tiles get `tall` (model_library.gd). While f3d_fade is on, an instance whose middle
// lies near the line from the camera to the character or to the cursor, on the camera's side, is
// dithered away (a 4x4 ordered dither), so what is behind it shows. One value per instance, from
// its position, so whole buildings and trees fade, not slices of them.

#include "res://shaders/noise.gdshaderinc"
#ifdef MOVER
#include "res://shaders/mover_records.gdshaderinc"
#endif

uniform bool tall = false;
global uniform float f3d_fade;
global uniform vec3 f3d_fade_eye;
global uniform vec3 f3d_fade_target;
global uniform vec3 f3d_fade_cursor;
const float FADE_NEAR = 1.6;  // tiles from the line: fully faded inside, none past FADE_FAR
const float FADE_FAR = 2.8;
const float FADE_MOST = 0.8;  // the most that is dithered away: the outline stays faintly

uniform vec4 albedo : source_color = vec4(1.0);
uniform float roughness : hint_range(0.0, 1.0) = 0.6;
uniform float metallic : hint_range(0.0, 1.0) = 0.0;
uniform vec3 emission : source_color = vec3(0.0);
uniform float emission_energy = 0.0;
// 1 when the mesh has the baked COLOR, UV2 and CUSTOM0 data.
uniform float vertex_data = 1.0;
uniform float edge_data = 1.0;
uniform float view_data = 1.0;
// 1 when the mesh has part colours (CUSTOM1); part_colors 0 ignores them (the palette look, and
// tier and creature tints, which recolour the material).
uniform float part_data = 0.0;
uniform bool part_colors = true;
// Multiplies the whole model's colour: Factorio's tinted copies of another entity's pictures
// (the infinity pipe is the pipe tinted blue; model_library.gd WHOLE_TINTS).
uniform vec3 model_tint : source_color = vec3(1.0);
// A model's own textures (model_textures.gd): its base colour picture stands in for the part colour
// (the paint as it looks, wear and all); glTF's metallic-roughness picture (G rough, B metal) for those.
uniform bool use_albedo_tex = false;
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform bool use_orm_tex = false;
uniform sampler2D orm_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
// The sampled colours already carry Factorio's grime and wear on average: the weathering on top of
// them is scaled by these (rust and streaks, worn edges, grime, dust), and they skip the palette's
// greying (desaturate, value). Worn edges and dust most of all: converted models are full of small
// bevels, and pale dust on every top read as a lighter colour.
uniform vec4 part_weathering = vec4(0.4, 0.2, 0.6, 0.1);
// Godot's sun lights tops far harder than the sides (about 3 to 1 from Factorio's view at noon,
// where Factorio's own renders have 1.3 to 1): part colours, which are Factorio's colours as its
// view shows them, are balanced back by the way the surface faces (x sides, y tops), so a forced
// colour shows about as given on a top and the sides keep their share.
uniform vec2 part_light = vec2(0.95, 0.6);
const float PART_RANGE = 4.0;
const float PART_SHARE = 0.25;

uniform float ao_strength = 1.0;
uniform float grime = 0.5;
uniform vec3 grime_color : source_color = vec3(0.13, 0.11, 0.09);
// Grime rising from the ground: how high (tiles) it reaches.
uniform float ground_grime_height = 0.45;
uniform float edge_wear = 0.5;
uniform vec3 edge_color : source_color = vec3(0.62, 0.6, 0.56);
uniform float edge_metallic = 0.7;
uniform float rust = 0.0;
uniform vec3 rust_color : source_color = vec3(0.36, 0.19, 0.09);
uniform float streaks = 0.0;
uniform float dust = 0.25;
uniform vec3 dust_color : source_color = vec3(0.5, 0.46, 0.38);
uniform float desaturate = 0.15;
uniform float value = 0.9;
uniform float grain = 0.08;

// The sprite projection (sprite_projection.gd). sprite_cells = 0: none.
uniform int sprite_cells = 0;
// 0: one cell; 1: a cell per direction the instance faces (N, E, S, W); 2: a cell per variation.
uniform int sprite_mode = 0;
uniform sampler2D sprite_tex : source_color, filter_linear_mipmap, repeat_disable;
uniform vec2 sprite_anchor[8];
// sprite_mode 3 (vehicles): sprite_frames frames evenly round the turn, clockwise from north,
// laid out sprite_grid to a row of sprite_slot pixels; sprite_anchor[0] is frame 0's anchor.
uniform int sprite_frames = 1;
uniform int sprite_grid = 1;
uniform vec2 sprite_slot = vec2(0.0);
uniform vec2 sprite_atlas_size = vec2(1.0);
uniform float sprite_ppt = 64.0;
uniform float sprite_anchor_z = 0.3;
// Sprites drawn straight down (rails): projected along -Y, heights ignored, onto top faces only.
uniform bool sprite_top_down = false;
// Rail sprites keep the track's centre line where the game has it but draw distances across it
// north-south squashed (as seen at Factorio's camera): the centre line is in UV (x, z - 1), and
// north-south offsets from it are scaled by this.
uniform float sprite_across = 1.0;
// Scales north-south ground distances before projecting: pipe sprites draw their tiles square on
// screen, longer north-south than Factorio's camera gives (tools/models/compare.py --stretch).
uniform float sprite_stretch = 1.0;
uniform float sprite_mean_luminance = 0.25;
// How much of the sprite's baked-in light and shade to flatten (Godot lights the model again),
// and the mip level that stands for "the light falling on this area".
uniform float sprite_delight = 0.4;
uniform float sprite_light_lod = 4.0;
uniform float sprite_gain = 0.8;
// How far the fallback's colour leans towards the sprite's nearby colour, so seams don't show.
uniform float sprite_fallback_tint = 0.6;
// ... and how far its brightness moves to the sprite's (0: keeps the material's own). Without it
// a light pipe's hidden underside stays the palette's dark steel.
uniform float sprite_fallback_luma = 0.5;
uniform bool sprite_debug = false;
// Per-pixel occlusion for the projection (tools/models/projector_depth.py): the frontmost
// surface's closeness to Factorio's camera (tiles) per projector pixel, a cell per direction.
// A fragment clearly behind it doesn't take the sprite (it would get its occluder's pixels).
uniform bool depth_on = false;
uniform sampler2D depth_tex : filter_nearest, repeat_disable;
uniform vec2 depth_size = vec2(1.0);
uniform vec2 depth_cell[4];
uniform float depth_ppt = 32.0;

uniform bool animated = false;
uniform bool activity_glow = false;
// Movers are single MeshInstance3Ds with no INSTANCE_CUSTOM: vehicle_anim.gd sets their glow
// here instead (0 to 1; below 0, INSTANCE_CUSTOM.a as for buildings).
instance uniform float f3d_glow = -1.0;
// The colour a player painted a train or stop (movers.gd sets it; white leaves the model as it is).
instance uniform vec3 f3d_paint : source_color = vec3(1.0);
uniform float glow_flicker = 0.0;
uniform float glow_pulse = 0.0;
uniform float glow_rate = 1.0;
uniform bool glow_fades = false;
// Creatures (creature_models.gd, tools/models/wube_rig.py): limbs turn about their joints here.
// UV.x is the vertex's limb (1-12, 0 for the body), UV.y how much it follows it (0 at the joint).
// rig_mode 1: the gait comes from INSTANCE_CUSTOM (r phase in radians, g strength 0-1), set by
// creatures.gd from the creature's speed; 2: it runs on its own (worms, spawners) at rig_rate.
// Per limb: joint, swing axis, lift axis, gait (phase offset, swing and lift radians, pulse).
uniform int rig_mode = 0;
uniform float rig_rate = 1.0;
uniform vec3 rig_joint[12];
uniform vec3 rig_swing[12];
uniform vec3 rig_lift[12];
uniform vec4 rig_gait[12];
// rig_mode 3: a skeleton posed on the CPU (the character, character_pose.gd). UV.x is bone a +
// 16 * bone b, UV.y a's weight; each bone's matrix is three rows (rotation | translation).
uniform vec4 rig_bone[48];
// rig_mode 4: a worm (creature_models.gd), bent and raised by position alone, so nothing can
// tear: the neck follows more the higher it is. INSTANCE_CUSTOM.a (anim.gd): 0 folded into its
// hole, 1 prepared (standing, swaying), up to 2 attacking (lunging forwards, -Z).
uniform float worm_height = 1.0;
uniform float belt_speed = 0.0;
uniform int belt_shape = 0;
// The tier's chevron painted on every other slat, pointing the way items go (Factorio's belt sheets:
// yellow, red, blue, green); alpha 0 leaves the slats bare.
uniform vec4 belt_chevron : source_color = vec4(0.0);
// Distance between the belt's slats, in tiles. Factorio's belt animation loops every half tile
// of travel (16 frames at one frame per tick for yellow), so slats every quarter tile.
const float BELT_PERIOD = 0.25;

// One surface per model (model_library.gd, material_rows.gd): a model's surfaces of one shader are
// merged into one draw, each of the materials it was made of a row of material_table, CUSTOM2.r the
// vertex's row. With material_rows 0 (the default) the per-material uniforms above are used, as
// before; with rows, the uniforms the rows hold are ignored and the rest stay the model's own
// (activity_glow is then whether any row glows). A merged surface has every vertex array: a
// material's missing ones are filled with what reads as "none" (white COLOR, UV2 (0, 0.5), CUSTOM0
// 1), so vertex_data, edge_data and view_data aren't needed there. A row, MATERIAL_ROW vec4s:
//   0  albedo (linear rgb, alpha)
//   1  emission * emission_energy (linear), flags: 1 activity_glow, 2 glow_fades,
//      4 a belt surface (belt_speed applies), 8 no sprite (a tier's own paint)
//   2  roughness, metallic, edge_metallic, ground_grime_height
//   3  part_data (0 without part_colors), glow_flicker, glow_pulse, glow_rate
//   4  ao_strength, streaks, desaturate, value
//   5  grain, part_light, -
//   6  part_weathering
//   7-10  grime_color, edge_color, rust_color, dust_color (linear), and grime, edge_wear, rust, dust
// One row's vec4s lie together (a cache line or two), and are read after the noise, which keeps
// them out of registers while it runs.
#define MATERIAL_ROW 11
#define MATERIAL_TABLE 264
uniform int material_rows = 0;
uniform vec4 material_table[MATERIAL_TABLE];
varying flat int mat_row;

bool row_flag(float flags, float bit) {
	return mod(floor(flags / bit), 2.0) > 0.5;
}

const float FACTORIO_SIN = 0.7431448;  // sin(48 degrees): Factorio's camera pitch
const float FACTORIO_COS = 0.6691306;
const vec3 LUMA = vec3(0.2126, 0.7152, 0.0722);

varying vec2 sprite_uv;
varying float sprite_vis;
varying vec3 obj_pos;
varying vec3 obj_normal;
varying float world_y;
varying flat float inst_seed;
varying flat float activity;
varying vec2 depth_uv;
varying float depth_here;
varying float depth_slack;
varying vec4 part_col;
varying flat float fade_amt;

// Distance from p to the segment a-b, and how far along it the nearest point is (0 at a, 1 at b).
float segment_distance(vec3 p, vec3 a, vec3 b, out float t) {
	vec3 ab = b - a;
	t = clamp(dot(p - a, ab) / max(dot(ab, ab), 1e-4), 0.0, 1.0);
	return length(p - (a + ab * t));
}

// How much an instance standing at `o` is in the way of the camera's view of `target`.
float in_the_way(vec3 o, vec3 target) {
	float best = 1e9;
	for (int k = 0; k < 3; k++) {
		float t;
		float d = segment_distance(o + vec3(0.0, 0.8 + 1.2 * float(k), 0.0), f3d_fade_eye, target, t);
		if (t > 0.02 && t < 0.96) {
			best = min(best, d);
		}
	}
	return 1.0 - smoothstep(FADE_NEAR, FADE_FAR, best);
}

float hash13(vec3 p) {
	p = mod(p, 4096.0);
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

float vnoise3(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	vec3 u = f * f * (3.0 - 2.0 * f);
	float a = mix(hash13(i), hash13(i + vec3(1.0, 0.0, 0.0)), u.x);
	float b = mix(hash13(i + vec3(0.0, 1.0, 0.0)), hash13(i + vec3(1.0, 1.0, 0.0)), u.x);
	float c = mix(hash13(i + vec3(0.0, 0.0, 1.0)), hash13(i + vec3(1.0, 0.0, 1.0)), u.x);
	float d = mix(hash13(i + vec3(0.0, 1.0, 1.0)), hash13(i + vec3(1.0, 1.0, 1.0)), u.x);
	return mix(mix(a, b, u.y), mix(c, d, u.y), u.z);
}

float fbm3d(vec3 p) {
	return 0.55 * vnoise3(p) + 0.3 * vnoise3(p * 2.07 + 17.3) + 0.15 * vnoise3(p * 4.13 + 41.1);
}

#ifdef LEAF_CUT
// Leaf cards (tools/models/nature/geo.py `card`, factorio_material_leaf.gdshader): each square
// holds a round spray of small pointed leaves, cut out here, so a crown's edge is as ragged and
// see-through as Factorio's tree sprites. Leaves sit one per cell of a LEAF_CELLS grid, nudged and
// turned at random by the card's own seed (UV2.y, random per part); only leaves whose middle lies
// inside the spray's circle are kept, whole. Returns the leaf's shade (each leaf a little lighter
// or darker, darker at its rim, like the sprites' leaves); discards between leaves. Far away,
// where a leaf would be under a pixel and shimmer, the spray turns into a solid, ragged disk.
const float LEAF_CELLS = 5.0;

float leaf_cut(vec2 uv, float seed) {
	vec2 g = uv * LEAF_CELLS;
	vec2 cell = floor(g);
	vec2 off = vec2(seed * 61.0, seed * 37.0);
	float cover = 0.0;
	float shade = 1.0;
	for (int j = -1; j <= 1; j++) {
		for (int i = -1; i <= 1; i++) {
			vec2 c = cell + vec2(float(i), float(j));
			float h1 = hash12(c + off);
			float h2 = hash12(c + off + 17.31);
			float h3 = hash12(c + off + 41.7);
			vec2 centre = c + 0.15 + 0.7 * vec2(h1, h2);
			vec2 at = centre / LEAF_CELLS * 2.0 - 1.0;
			if (dot(at, at) > 0.72 + 0.2 * h3) {
				continue;
			}
			float a = h3 * 6.2831853;
			vec2 d = g - centre;
			d = vec2(d.x * cos(a) + d.y * sin(a), -d.x * sin(a) + d.y * cos(a));
			// A pointed leaf: a lens 0.6-0.85 cells long, widest in its middle.
			float len = 0.6 + 0.25 * h1;
			float wid = (0.26 + 0.1 * h2) * max(0.0, 1.0 - abs(d.x) / len);
			float v = 1.0 - (d.x * d.x) / (len * len) - (d.y * d.y) / max(wid * wid, 1e-4);
			if (v > cover) {
				cover = v;
				shade = 0.72 + 0.5 * hash12(c + off + 5.3);
			}
		}
	}
	vec2 q = uv * 2.0 - 1.0;
	// Leaves only a pixel or two long shimmer as the camera moves: the disk takes over while a leaf is
	// still about four pixels long (a cell 0.25 pixels per unit of g, wholly by 0.55).
	float far_away = clamp((max(fwidth(g.x), fwidth(g.y)) - 0.25) * 3.3, 0.0, 1.0);
	float disk = 0.78 + 0.18 * hash12(floor(g * 2.0) + off) - length(q);
	if (mix(cover, disk, far_away) <= 0.0) {
		discard;
	}
	return mix(shade * (0.7 + 0.3 * sqrt(clamp(cover, 0.0, 1.0))), 0.95, far_away);
}
#endif

#ifdef ROBOT
// Flying robots (robot_swarm.gd: one MultiMesh per robot kind and part, so a thousand robots are
// a few draw calls). Each part's mesh is in model space at rest, as for movers' nodes; what
// vehicle_anim.gd did per robot happens here from INSTANCE_CUSTOM: r how much it flies (0-1),
// g its bob's phase (radians), b 1 while it carries cargo + 2 while it works (a construction
// robot hovering in place), a how far its arms reach (radians).
uniform int robot_part = 0;  // 0 body, 1 thrusters, 2 cargo lamp, 3 empty lamp, 4 nozzle, 5 arms
uniform vec3 robot_pivot = vec3(0.0);
uniform vec3 robot_axis = vec3(1.0, 0.0, 0.0);  // the pivot's east-west axis, model space
uniform float robot_bob = 0.035;
uniform float robot_bob_rate = 0.7;
const float ROBOT_SWING = -0.5;  // radians the thrusters swing back at full speed
const float ROBOT_WORK_FRAME = 1.0 / 18.0;  // working animation: 2 frames at 0.3 a tick
// vehicle_anim.gd's ROBOT_FULL_SPEED, WORK_STILL and ARMS_REACH: the record's robots (MOVER).
const float ROBOT_FULL_SPEED = 2.5;
const float ROBOT_WORK_STILL = 0.3;
const float ROBOT_ARMS_REACH = 0.6;

void robot_vertex(inout vec3 v, inout vec3 n, vec4 c, float time) {
	float flags = floor(c.b + 0.5);
	bool cargo = mod(flags, 2.0) > 0.5;
	bool working = flags > 1.5;
	if ((robot_part == 2 && !cargo) || (robot_part == 3 && cargo)) {
		v = vec3(0.0);  // the other lamp: nothing drawn
		return;
	}
	float angle = robot_part == 1 ? ROBOT_SWING * c.r : (robot_part == 5 ? c.a : 0.0);
	if (angle != 0.0) {
		vec3 a = robot_axis;
		vec3 p = v - robot_pivot;
		p = p * cos(angle) + cross(a, p) * sin(angle) + a * dot(a, p) * (1.0 - cos(angle));
		n = n * cos(angle) + cross(a, n) * sin(angle) + a * dot(a, n) * (1.0 - cos(angle));
		v = robot_pivot + p;
	}
	v.y += robot_bob * sin(time * robot_bob_rate * 6.2831853 + c.g);
}

float robot_glow(vec4 c, float time) {
	bool working = floor(c.b + 0.5) > 1.5;
	if (robot_part == 1) {
		return 0.3 + 0.7 * c.r;
	}
	if (robot_part == 4) {
		return working ? (mod(floor(time / ROBOT_WORK_FRAME), 2.0) < 0.5 ? 1.0 : 0.3) : 0.6;
	}
	return 1.0;
}
#endif

// Machines' moving parts and glow, worked out here from their state instead of by anim.gd every
// frame. A chunk's moving part (one MultiMesh per part of a model) is drawn at its entity's own
// transform and turned or slid here; anim.gd writes an instance's INSTANCE_CUSTOM only when its
// state changes (`st`, a robot or pod coming near, a strike). Such "timed" instances, and the
// glowing models' instances, have INSTANCE_CUSTOM.b < 0:
//   r  when the state last changed: seconds on the clock f3d_anim_time.x or .y (flag 2)
//   g  how far the part had got then: loops of its motion, or how far open (linear parts)
//   b  -(1 + flags + its speed then, 0-0.999); flags: 1 moving (working; open, lit), 2 on the .y
//      clock, 4 glowing (working)
//   a  how much it glowed then (lit parts: how brightly)
// The two clocks are seconds since the start of anim.gd's latest even and odd epochs, so they stay
// small (and precise) however long the game runs: anim.gd moves every state onto the newer clock
// before the older one starts again.
// anim_mode, per part material (anim.gd setup_part): 1 spinning (loops of a turn), 2 cycling
// (anim_wave 0 out and back, 1 either way of rest, 2 round; ModelLibrary.CYCLES), 3 rocking with
// a crank, 4 a piston (bob), 5 lit, 6 linear (doors, hatches, gates, the power switch: towards
// anim_open at anim_speed a second), 7 a light fading linearly (roboport charging points).
// Turning is about anim_axis in the pivot's frame (anim_pivot, the part node's transform);
// sliding (anim_slide not zero) moves by anim_slide per unit.
global uniform vec2 f3d_anim_time;
uniform int anim_mode = 0;
uniform int anim_wave = 0;
uniform float anim_rate = 0.0;
uniform float anim_amount = 1.0;
uniform vec3 anim_slide = vec3(0.0);
uniform vec3 anim_axis = vec3(0.0, 1.0, 0.0);
uniform mat4 anim_pivot = mat4(1.0);
uniform mat4 anim_unpivot = mat4(1.0);
uniform float anim_speed = 1.0;
uniform float anim_open = 1.0;
uniform bool anim_flicker = false;
uniform bool anim_strike = false;
// anim.gd's SPIN_UP, SPIN_DOWN, GLOW_UP, GLOW_DOWN, STRIKE_RISE, STRIKE_FADE (seconds).
const float ANIM_SPIN_UP = 0.35;
const float ANIM_SPIN_DOWN = 0.9;
const float ANIM_GLOW_UP = 0.25;
const float ANIM_GLOW_DOWN = 0.9;
const float ANIM_STRIKE_RISE = 0.4;
const float ANIM_STRIKE_FADE = 2.5;

// A timed instance's flags (floor) and speed then (the fraction).
float anim_flags(vec4 c, out float speed0) {
	float code = -c.b - 1.0;
	float flags = floor(code);
	speed0 = code - flags;
	return flags;
}

bool anim_bit(float flags, float bit) {
	return mod(floor(flags / bit), 2.0) > 0.5;
}

// Seconds since the instance's state last changed.
float anim_since(vec4 c, float flags) {
	return max((anim_bit(flags, 2.0) ? f3d_anim_time.y : f3d_anim_time.x) - c.r, 0.0);
}

// A lightning attractor's glow after a strike: up over STRIKE_RISE, then fading.
float anim_strike_level(float age) {
	return age < ANIM_STRIKE_RISE ? age / ANIM_STRIKE_RISE : exp(-(age - ANIM_STRIKE_RISE) / ANIM_STRIKE_FADE * 3.0);
}

// move_toward(from, to, step)
float anim_toward(float from, float to, float step) {
	return from + clamp(to - from, -step, step);
}

// How much a timed instance glows now (id: the instance's index, for the flicker).
float anim_glow(vec4 c, float id) {
	float s0;
	float flags = anim_flags(c, s0);
	float dt = anim_since(c, flags);
	if (anim_mode == 5) {
		float level = anim_strike ? anim_strike_level(dt) : c.a;
		if (anim_flicker) {
			float t = f3d_anim_time.x;
			level *= 0.7 + 0.3 * sin(t * 31.0 + id * 1.7) * sin(t * 11.0 + id);
		}
		return level;
	}
	if (anim_mode == 7) {
		return anim_toward(c.g, anim_bit(flags, 1.0) ? 1.0 : 0.0, anim_speed * dt);
	}
	float goal = anim_bit(flags, 4.0) ? 1.0 : 0.0;
	return goal + (c.a - goal) * exp(-dt / (goal > 0.5 ? ANIM_GLOW_UP : ANIM_GLOW_DOWN));
}

// The part turned by `angle` radians about its pivot: pivot * rotation * pivot^-1, the normal by
// that's inverse transpose (the pivot may be scaled).
void anim_turn(inout vec3 v, inout vec3 n, float angle) {
	vec3 a = anim_axis;
	float co = cos(angle);
	float si = sin(angle);
	vec3 p = (anim_unpivot * vec4(v, 1.0)).xyz;
	p = p * co + cross(a, p) * si + a * dot(a, p) * (1.0 - co);
	v = (anim_pivot * vec4(p, 1.0)).xyz;
	vec3 m = transpose(mat3(anim_pivot)) * n;
	m = m * co + cross(a, m) * si + a * dot(a, m) * (1.0 - co);
	n = transpose(mat3(anim_unpivot)) * m;
}

// A timed part's pose now (anim.gd's _pose and AnimPart.turned, as they were done per frame).
void anim_vertex(inout vec3 v, inout vec3 n, vec4 c) {
	float s0;
	float flags = anim_flags(c, s0);
	bool on = anim_bit(flags, 1.0);
	float dt = anim_since(c, flags);
	if (anim_mode == 5) {
		// Hidden: shrunk to nothing at the model's origin, inside the body (ModelLibrary.HIDDEN).
		if (!on || (anim_strike && anim_strike_level(dt) <= 0.02)) {
			v *= 0.001;
		}
		return;
	}
	if (anim_mode == 7) {
		return;
	}
	float x = 0.0;
	if (anim_mode == 6) {
		x = anim_toward(c.g, on ? anim_open : 0.0, anim_speed * dt) * anim_amount;
	} else {
		// The machine's speed eases towards full while it works and coasts to a stop when not;
		// how far the part has gone is that speed's integral since the change.
		float goal = on ? 1.0 : 0.0;
		float tau = on ? ANIM_SPIN_UP : ANIM_SPIN_DOWN;
		float e = exp(-dt / tau);
		float speed = goal + (s0 - goal) * e;
		float loops = c.g + anim_rate * (goal * dt + (s0 - goal) * tau * (1.0 - e));
		if (anim_mode == 1) {
			x = fract(loops) * 6.2831853;
		} else if (anim_mode == 2) {
			if (anim_wave == 1) {
				x = sin(loops * 6.2831853);
			} else if (anim_wave == 2) {
				x = fract(loops);
			} else {
				x = 0.5 - 0.5 * cos(loops * 6.2831853);
			}
			x *= anim_amount;
		} else if (anim_mode == 3) {
			x = anim_amount * sin(loops * 6.2831853);
		} else {
			x = (0.5 - 0.5 * cos(loops * 6.2831853)) * min(speed * 3.0, 1.0);
		}
	}
	if (any(notEqual(anim_slide, vec3(0.0)))) {
		v += anim_slide * x;
	} else {
		anim_turn(v, n, x);
	}
}

void vertex() {
	vec4 icustom = INSTANCE_CUSTOM;
#ifdef MOVER
	// Movers interpolated here from their record (mover_records.gdshaderinc). Robots always have
	// one (their slot in INSTANCE_CUSTOM.r); creatures walking have theirs in b (slot + 1), while
	// creatures posed by creatures.gd (attacking, dying) are drawn at their instance transform as
	// before. What creatures.gd and robot_swarm.gd used to write per instance every frame
	// (INSTANCE_CUSTOM) is worked out from the record into icustom.
#ifdef ROBOT
	bool mover = true;
	int mover_slot = int(INSTANCE_CUSTOM.r + 0.5);
#else
	bool mover = INSTANCE_CUSTOM.b > 0.5;
	int mover_slot = int(INSTANCE_CUSTOM.b - 0.5);
#endif
	MoverState ms;
	if (mover) {
		ms = mover_state(mover_slot);
#ifdef ROBOT
		// How much it flies, its bob, cargo and working flags and its arms' reach, as robot_swarm.gd
		// worked them out: flying eases at 3 a second towards its speed, a construction robot
		// standing still for ROBOT_WORK_STILL works, its arms easing out and back at 3 radians a second.
		float amount = 0.0;
		float reach = 0.0;
		float flags = 0.0;
		bool animates = mover_flag(ms.flags, 16.0);
		if (animates) {
			amount = mover_toward(ms.carried.z, clamp(ms.speed / ROBOT_FULL_SPEED, 0.0, 1.0), 3.0 * ms.since);
			bool working = mover_flag(ms.flags, 4.0) && ms.still > ROBOT_WORK_STILL;
			if (working) {
				float began = max(ms.since - (ms.still - ROBOT_WORK_STILL), 0.0);
				reach = mover_toward(mover_toward(ms.carried.w, 0.0, 3.0 * began), ROBOT_ARMS_REACH, 3.0 * (ms.since - began));
			} else {
				reach = mover_toward(ms.carried.w, 0.0, 3.0 * ms.since);
			}
			flags = (mover_flag(ms.flags, 8.0) ? 1.0 : 0.0) + (working ? 2.0 : 0.0);
		}
		icustom = vec4(amount, animates ? ms.kind.x : 0.0, flags, reach);
#else
		// The gait's phase from the distance walked (a loop of legs per kind.y radians a tile) and a
		// slow idle loop; its strength from its speed over the last few ticks; the body's bob.
		float phase = ms.kind.x + ms.kind.y * ms.walked + 0.15 * 6.2831853 * f3d_mover_clock.w;
		float gait = clamp(ms.average / 1.5, 0.0, 1.0);
		ms.pos.y += abs(sin(phase)) * 0.025 * gait * ms.kind.z;
		icustom = vec4(phase, max(gait, 0.15), 0.0, 1.0);
#endif
	}
#endif
	obj_pos = VERTEX;
	obj_normal = NORMAL;
	part_col = CUSTOM1;
	// The table isn't read here (the shadow and depth passes run this for every vertex): the
	// instance's glow is worked out for the model, and each row takes it or not in fragment().
	mat_row = material_rows > 0 ? clamp(int(CUSTOM2.r + 0.5), 0, material_rows - 1) : -1;
	bool glows = activity_glow;
	float views = mat_row >= 0 ? 1.0 : view_data;
	world_y = (MODEL_MATRIX * vec4(VERTEX, 1.0)).y;
	// One value per instance: a MultiMesh instance's MODEL_MATRIX is its own transform. Parts
	// turned by anim.gd take the entity's position and direction from INSTANCE_CUSTOM instead;
	// timed ones (moved here) are drawn at the entity's own transform.
	bool timed = INSTANCE_CUSTOM.b < -0.5;
	bool from_custom = animated && !timed;
	vec2 origin = from_custom ? INSTANCE_CUSTOM.rg : MODEL_MATRIX[3].xz;
	inst_seed = hash12(origin * 3.17 + 0.5);
#ifdef MOVER
	if (mover) {
		inst_seed = fract(ms.kind.x * 0.1591549 + 0.37);  // its own, not where it happens to be
	}
#endif
	fade_amt = 0.0;
	if (tall && f3d_fade > 0.5) {
		vec3 o = vec3(origin.x, MODEL_MATRIX[3].y, origin.y);
		fade_amt = max(in_the_way(o, f3d_fade_target), in_the_way(o, f3d_fade_cursor)) * FADE_MOST;
	}
	activity = glows && rig_mode != 4 ? clamp(f3d_glow >= 0.0 ? f3d_glow
		: (timed ? anim_glow(INSTANCE_CUSTOM, float(INSTANCE_ID)) : icustom.a), 0.0, 1.0) : 1.0;
#ifdef ROBOT
	activity = glows ? robot_glow(icustom, TIME) : 1.0;
#endif

	sprite_uv = vec2(-1.0);
	sprite_vis = 0.0;
	if (sprite_cells > 0) {
		// Factorio's camera looks north and down; the sprite for the way this instance faces
		// is projected along it. Model north is -Z.
		vec3 north = -MODEL_MATRIX[2].xyz;
#ifdef MOVER
		if (mover) {
			north = vec3(-sin(ms.yaw), 0.0, -cos(ms.yaw));
		}
#endif
		int dir = int(mod(round(atan(north.x, -north.z) / 1.5707963), 4.0));
		if (from_custom) {
			dir = int(mod(round(INSTANCE_CUSTOM.b), 4.0));
		}
		vec3 p = VERTEX;
		vec3 n = NORMAL;
		int cell = 0;
		int frame = 0;
		float vis = CUSTOM0.x;
		vec2 centre = vec2(UV.x, UV.y - 1.0);
		if (sprite_mode == 1) {
			// Turn the model as the instance faces, so the world camera's view applies.
			cell = min(dir, sprite_cells - 1);
			float a = -float(dir) * 1.5707963;
			float c = cos(a);
			float s = sin(a);
			p = vec3(p.x * c + p.z * s, p.y, -p.x * s + p.z * c);
			n = vec3(n.x * c + n.z * s, n.y, -n.x * s + n.z * c);
			centre = vec2(centre.x * c + centre.y * s, -centre.x * s + centre.y * c);
			vis = CUSTOM0[dir];
		} else if (sprite_mode == 3) {
			// The frame drawn nearest the way this instance faces, turned to fit.
			float turn = atan(north.x, -north.z);
			frame = int(mod(round(turn / 6.2831853 * float(sprite_frames)), float(sprite_frames)));
			float a = -float(frame) * 6.2831853 / float(sprite_frames);
			float c = cos(a);
			float s = sin(a);
			p = vec3(p.x * c + p.z * s, p.y, -p.x * s + p.z * c);
			n = vec3(n.x * c + n.z * s, n.y, -n.x * s + n.z * c);
			vis = CUSTOM0[int(mod(round(float(frame) * 4.0 / float(sprite_frames)), 4.0))];
		} else if (sprite_mode == 2) {
			cell = min(int(hash12(origin * 1.37 + 7.1) * float(sprite_cells)), sprite_cells - 1);
		}
		float up = sprite_top_down ? -(centre.y + (p.z - centre.y) * sprite_across)
			: p.y * FACTORIO_COS - p.z * FACTORIO_SIN * sprite_stretch;
		vec2 anchor = sprite_anchor[cell];
		if (sprite_mode == 3) {
			anchor += vec2(float(frame % sprite_grid), float(frame / sprite_grid)) * sprite_slot;
		}
		vec2 px = anchor + vec2(p.x, sprite_anchor_z * FACTORIO_COS - up) * sprite_ppt;
		sprite_uv = px / sprite_atlas_size;
		if (sprite_top_down) {
			float facing = dot(normalize(n), vec3(0.0, 1.0, 0.0));
			sprite_vis = mix(1.0, vis, views) * smoothstep(0.02, 0.3, facing);
		} else {
			float facing = dot(normalize(n), vec3(0.0, FACTORIO_SIN, FACTORIO_COS));
			// A face turned far from Factorio's camera would get the sprite smeared across it (a
			// pixel stretched over 1 / facing of its width): past about 1.7x it fades to the material.
			sprite_vis = mix(1.0, vis, views) * smoothstep(0.35, 0.6, facing);
			if (depth_on) {
				vec2 dp = depth_cell[min(sprite_mode == 1 ? cell : 0, 3)] + vec2(p.x, -up) * depth_ppt;
				depth_uv = dp / depth_size;
				depth_here = p.y * FACTORIO_SIN + p.z * FACTORIO_COS;
				// The map holds one depth per pixel: a sloped face's own depth varies across it.
				float f = max(facing, 0.2);
				depth_slack = 0.035 + 1.5 * sqrt(max(1.0 - f * f, 0.0)) / f / depth_ppt;
			}
		}
	}

	// Creatures' limbs, after the sprite was projected from the rest pose: the sprite and the
	// weathering stay painted on the limb as it moves.
	if (rig_mode == 4) {
		float h = max(worm_height, 0.01);
		float state = INSTANCE_CUSTOM.a;
		float raised = clamp(state, 0.0, 1.0);
		float attack = clamp(state - 1.0, 0.0, 1.0);
		// How much of the neck a point is: none at the ground ring, all of it at the head.
		float t = smoothstep(0.06 * h, 0.9 * h, VERTEX.y) * (1.0 - smoothstep(0.3 * h, 0.55 * h, length(VERTEX.xz)));
		// Factorio's prepared loop: 9 frames forward then back, each way 1 / 0.024 ticks (0.7 Hz).
		float phase = TIME * 0.72 * 6.2831853 + inst_seed * 6.2831853;
		// Folded: the neck sinks into the hole, leaving the head's crown above the ground.
		vec3 p = VERTEX;
		p.y -= (1.0 - raised) * t * (p.y - 0.05 * h) * 0.82;
		p.xz *= 1.0 + (1.0 - raised) * t * 0.25;
		// Swaying while prepared. Attacking, it strikes forward over the starting attack and holds
		// the head out while it spits its stream (a 4-tick cooldown), heaving a little with it.
		// Factorio's lunge (worm-attack, last frames) bends it over until the mouth faces the
		// target, the head about a third of its height off the ground: about a radian at the top.
		float spit = sin(TIME * 15.0 + inst_seed * 6.2831853);
		float bend = raised * (0.07 * sin(phase) * (1.0 - attack) + attack * (0.95 + 0.04 * spit));
		float side = raised * 0.06 * sin(phase * 0.71 + 1.3);
		float a = bend * t * t;
		float b = side * t * t;
		vec3 n = NORMAL;
		// Forwards (towards -Z) about the X axis through the base, then sideways about Z.
		p = vec3(p.x, p.y * cos(a) + p.z * sin(a), -p.y * sin(a) + p.z * cos(a));
		n = vec3(n.x, n.y * cos(a) + n.z * sin(a), -n.y * sin(a) + n.z * cos(a));
		p = vec3(p.x * cos(b) - p.y * sin(b), p.x * sin(b) + p.y * cos(b), p.z);
		n = vec3(n.x * cos(b) - n.y * sin(b), n.x * sin(b) + n.y * cos(b), n.z);
		VERTEX = p;
		NORMAL = n;
	} else if (rig_mode == 3) {
		float code = round(UV.x);
		int a = int(mod(code, 16.0)) * 3;
		int b = int(floor(code / 16.0 + 0.01)) * 3;
		vec4 v = vec4(VERTEX, 1.0);
		vec3 pa = vec3(dot(rig_bone[a], v), dot(rig_bone[a + 1], v), dot(rig_bone[a + 2], v));
		vec3 pb = vec3(dot(rig_bone[b], v), dot(rig_bone[b + 1], v), dot(rig_bone[b + 2], v));
		vec4 n = vec4(NORMAL, 0.0);
		vec3 na = vec3(dot(rig_bone[a], n), dot(rig_bone[a + 1], n), dot(rig_bone[a + 2], n));
		vec3 nb = vec3(dot(rig_bone[b], n), dot(rig_bone[b + 1], n), dot(rig_bone[b + 2], n));
		VERTEX = mix(pb, pa, UV.y);
		NORMAL = normalize(mix(nb, na, UV.y));
	} else if (rig_mode > 0 && UV.x > 0.5 && UV.y > 0.0) {
		int i = clamp(int(UV.x + 0.5) - 1, 0, 11);
		float phase = rig_mode == 1 ? icustom.r : TIME * rig_rate * 6.2831853 + inst_seed * 6.2831853;
		float gait = rig_mode == 1 ? clamp(icustom.g, 0.0, 1.0) : 1.0;
		vec4 g = rig_gait[i];
		float s = sin(phase + g.x);
		float swing = g.y * s * gait * UV.y;
		float lift = g.z * max(0.0, cos(phase + g.x)) * gait * UV.y;
		vec3 p = VERTEX - rig_joint[i];
		vec3 nn = NORMAL;
		vec3 a = rig_lift[i];
		p = p * cos(lift) + cross(a, p) * sin(lift) + a * dot(a, p) * (1.0 - cos(lift));
		nn = nn * cos(lift) + cross(a, nn) * sin(lift) + a * dot(a, nn) * (1.0 - cos(lift));
		a = rig_swing[i];
		p = p * cos(swing) + cross(a, p) * sin(swing) + a * dot(a, p) * (1.0 - cos(swing));
		nn = nn * cos(swing) + cross(a, nn) * sin(swing) + a * dot(a, nn) * (1.0 - cos(swing));
		VERTEX = rig_joint[i] + p * (1.0 + g.w * (0.5 + 0.5 * s) * UV.y);
		NORMAL = nn;
	}
	// Machines' moving parts, also after the sprite was projected from the rest pose.
	if (anim_mode > 0 && timed) {
		anim_vertex(VERTEX, NORMAL, INSTANCE_CUSTOM);
		world_y = (MODEL_MATRIX * vec4(VERTEX, 1.0)).y;
	}
#ifdef ROBOT
	robot_vertex(VERTEX, NORMAL, icustom, TIME);
#endif
#ifdef MOVER
	if (mover) {
		mover_place(VERTEX, NORMAL, ms, MODEL_MATRIX[3].xyz);
		world_y = (MODEL_MATRIX * vec4(VERTEX, 1.0)).y;
	}
#endif
}

void fragment() {
#ifdef LEAF_CUT
	float leaf_shade = leaf_cut(UV, UV2.y);
	// Both sides are drawn and lit by the crown's normal the card carries (Godot flips it on the
	// back side: flipped back).
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
	}
#endif
	if (fade_amt > 0.0) {
		// 4x4 Bayer thresholds: an even, steady dither.
		ivec2 c = ivec2(FRAGCOORD.xy) % 4;
		int i = c.x + c.y * 4;
		float bayer[16] = float[16](0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0, 3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0);
		if ((bayer[i] + 0.5) / 16.0 < fade_amt) {
			discard;
		}
	}
	// A merged surface has every vertex array (material_rows): its data flags are all on.
	bool merged = mat_row >= 0;
	float vertex_on = merged ? 1.0 : vertex_data;
	float edge_on = merged ? 1.0 : edge_data;
	vec3 n = normalize(obj_normal);
	float ao = mix(1.0, COLOR.a, vertex_on);
	vec3 tint = mix(vec3(1.0), COLOR.rgb, vertex_on);
	float edge = UV2.x * edge_on;
	float part = mix(0.5, UV2.y, edge_on);
	// How dirty this instance and this part are.
	float dirt = 0.75 + 0.5 * inst_seed;
	vec3 p = obj_pos + vec3(inst_seed * 37.0, 0.0, inst_seed * 53.0) + part * 11.0;

	float patches = fbm3d(p * 2.3);
	float fine = vnoise3(p * 23.0);
	float mid = vnoise3(p * 7.0 + 5.0);
	float occluded = 1.0 - ao;

	// This fragment's material: the uniforms, or its row of the model's table (material_rows).
	vec4 m_albedo = albedo;
	vec3 m_emission = emission * emission_energy;
	bool m_glow = activity_glow;
	bool m_fades = glow_fades;
	bool m_belt = belt_speed != 0.0;
	bool m_sprite = sprite_cells > 0;
	float m_rough = roughness;
	float m_metal = metallic;
	float m_edge_metal = edge_metallic;
	float m_ground_height = ground_grime_height;
	float m_part = part_colors ? part_data : 0.0;
	float m_flicker = glow_flicker;
	float m_pulse = glow_pulse;
	float m_rate = glow_rate;
	float m_ao = ao_strength;
	vec4 m_wear = part_weathering;
	float m_streaks = streaks;
	float m_desat = desaturate;
	float m_value = value;
	float m_grain = grain;
	vec2 m_light = part_light;
	vec4 m_grime = vec4(grime_color, grime);
	vec4 m_edge = vec4(edge_color, edge_wear);
	vec4 m_rust = vec4(rust_color, rust);
	vec4 m_dust = vec4(dust_color, dust);
	if (merged) {
		int r = mat_row * MATERIAL_ROW;
		m_albedo = material_table[r];
		vec4 e = material_table[r + 1];
		m_emission = e.rgb;
		m_glow = row_flag(e.w, 1.0);
		m_fades = row_flag(e.w, 2.0);
		m_belt = m_belt && row_flag(e.w, 4.0);
		m_sprite = m_sprite && !row_flag(e.w, 8.0);
		vec4 s = material_table[r + 2];
		m_rough = s.x;
		m_metal = s.y;
		m_edge_metal = s.z;
		m_ground_height = s.w;
		vec4 g = material_table[r + 3];
		m_part = g.x;
		m_flicker = g.y;
		m_pulse = g.z;
		m_rate = g.w;
		vec4 t = material_table[r + 4];
		m_ao = t.x;
		m_streaks = t.y;
		m_desat = t.z;
		m_value = t.w;
		vec4 l = material_table[r + 5];
		m_grain = l.x;
		m_light = l.yz;
		m_wear = material_table[r + 6];
		m_grime = material_table[r + 7];
		m_edge = material_table[r + 8];
		m_rust = material_table[r + 9];
		m_dust = material_table[r + 10];
	}
	// The instance's glow (worked out in vertex() for the model) applies to the rows that glow.
	float act = m_glow ? activity : 1.0;

	// The part's own colour from Factorio's sprite, where the model has one. Stored with headroom
	// (rgb / PART_RANGE, a = share * PART_SHARE) so a dark baked tint (the nature models' COLOR)
	// can be divided out without clipping; files from before that store rgb and the share as is,
	// with shares above PART_SHARE (part_colors.py).
	bool headroom = part_col.a <= PART_SHARE + 0.0001;
	float pc = clamp(headroom ? part_col.a / PART_SHARE : part_col.a, 0.0, 1.0) * m_part;
	vec3 part_rgb = part_col.rgb * (headroom ? PART_RANGE : 1.0);
	// Textured surfaces are never merged (model_library.gd Load.combined): their textures are the
	// material's own uniforms.
	if (use_albedo_tex && !merged) {
		pc = 1.0;
		part_rgb = texture(albedo_tex, UV).rgb * albedo.rgb;
	}
	vec3 col = mix(m_albedo.rgb, part_rgb, pc) * tint * model_tint;
	vec4 wear = mix(vec4(1.0), m_wear, pc);
	// Part colours are the sprite's paint as it looks, metal and all: drawn mostly as diffuse paint
	// (as the projected sprite is), or the sky's reflection would grey them.
	// Little specular either: the sun's highlight on tops and domes read as a lighter colour.
	float rough = mix(m_rough, 0.85, pc);
	float metal = m_metal * mix(1.0, 0.1, pc);
	if (use_orm_tex && !merged) {
		vec3 orm = texture(orm_tex, UV).rgb;
		rough = roughness * orm.g;
		metal = metallic * orm.b;
	}

	// The belt's moving slats: light ridges and dark seams over the weathered surface.
	float belt_shade = 1.0;
	float chevron = 0.0;
	if (m_belt) {
		// Distance along the belt (tiles, -0.5 at the input edge to 0.5 at the output edge),
		// so the slats line up from tile to tile. Curves spread a tile's worth over the arc.
		// `across` is the distance from the belt's middle line.
		float s = -obj_pos.z;
		float across = obj_pos.x;
		if (belt_shape > 0) {
			float side = belt_shape == 1 ? 1.0 : -1.0;
			vec2 d = obj_pos.xz - vec2(-0.5 * side, -0.5);
			s = atan(-d.y, d.x * side) / 1.5707963 + 0.5;
			across = length(d) - 0.5;
		}
		if (belt_chevron.a > 0.0) {
			// Factorio's chevron: 0.3 tiles wide, 0.1 deep, its stroke 0.08, on the middle of
			// every other slat; `along` is measured from its middle towards the way items go.
			float cp = fract((s - TIME * belt_speed) / (2.0 * BELT_PERIOD) + 0.325);
			float along = (cp - 0.5) * 2.0 * BELT_PERIOD * sign(belt_speed);
			float centre = 0.05 - abs(across) * 0.67;
			float dist = abs(along - centre);
			float aa = max(fwidth(along), 0.004);
			chevron = (1.0 - smoothstep(0.04 - aa, 0.04 + aa, dist))
				* (1.0 - smoothstep(0.15 - aa, 0.15 + aa, abs(across)))
				* smoothstep(0.6, 0.9, n.y)
				// Far away the stroke is under a pixel: fades out rather than shimmering.
				* (1.0 - smoothstep(0.03, 0.06, aa)) * belt_chevron.a;
		}
		float phase = fract((s - TIME * belt_speed) / BELT_PERIOD);
		// A raised slat with a dark seam behind it, like Factorio's belt; fast belts blur.
		float slat = smoothstep(0.0, 0.08, phase) * (1.0 - smoothstep(0.62, 0.78, phase));
		float seam = 1.0 - smoothstep(0.0, 0.06, phase) * (1.0 - smoothstep(0.9, 1.0, phase));
		float blur = clamp(1.15 - abs(belt_speed) * 0.09, 0.45, 1.0);
		blur *= 1.0 - smoothstep(0.25, 0.6, fwidth(s) / BELT_PERIOD);
		belt_shade = 1.0 + blur * (0.45 * slat - 0.45 * seam - 0.12);
	}

	vec4 sprite = vec4(0.0);
	float sprite_w = 0.0;
	if (m_sprite && all(greaterThan(sprite_uv, vec2(0.0))) && all(lessThan(sprite_uv, vec2(1.0)))) {
		sprite = texture(sprite_tex, sprite_uv);
		// The sprite has Factorio's light and shadows painted in: divide out the broad light
		// (a blurred copy's brightness) part of the way, keeping the paint, grime and detail.
		vec3 light = textureLod(sprite_tex, sprite_uv, sprite_light_lod).rgb;
		float flatten = sprite_mean_luminance / max(dot(light, LUMA), 0.01);
		sprite.rgb *= clamp(mix(1.0, flatten, sprite_delight), 0.4, 3.0) * sprite_gain;
		sprite_w = sprite.a * smoothstep(0.2, 0.8, sprite_vis);
		if (depth_on) {
			float front = texture(depth_tex, depth_uv).r;
			sprite_w *= 1.0 - smoothstep(depth_slack, depth_slack * 2.0, front - depth_here);
		}
		// The fallback leans towards the colour the sprite has nearby (keeping its own
		// brightness), so the parts Factorio's camera doesn't see still match.
		vec4 near = textureLod(sprite_tex, sprite_uv, sprite_light_lod + 1.5);
		vec3 near_rgb = near.rgb * sprite_gain;
		vec3 lean = near_rgb * mix(dot(col, LUMA) / max(dot(near_rgb, LUMA), 0.01), 1.0, sprite_fallback_luma);
		// Part colours already match the sprite: lean less.
		col = mix(col, lean, sprite_fallback_tint * near.a * (1.0 - 0.7 * pc));
	}

	// Slightly greyed and darker, like Factorio's palette next to a clean render.
	float lum = dot(col, vec3(0.299, 0.587, 0.114));
	col = mix(col, vec3(lum), m_desat * (1.0 - pc)) * mix(m_value, 1.0, pc);
	// Mottling: no flat surface in Factorio's art is one colour.
	col *= 1.0 + m_grain * ((fine - 0.5) * 1.4 + (mid - 0.5) * 1.2);
	rough = clamp(rough + 0.12 * (mid - 0.5), 0.0, 1.0);

	// Rust: patches where water sits (crevices, low down, the top of a part) and streaks
	// running down the sides.
	float side = 1.0 - abs(n.y);
	float low = 1.0 - smoothstep(0.0, 0.9, world_y);
	float rust_mask = smoothstep(0.62, 0.8, patches + 0.25 * occluded + 0.12 * low + 0.2 * (part - 0.5) + 0.1 * (dirt - 1.0));
	float streak = smoothstep(0.55, 0.85, vnoise3(vec3(p.x * 11.0, p.y * 0.9, p.z * 11.0)))
		* smoothstep(0.35, 0.65, vnoise3(p * 1.7 + 3.0)) * side;
	float r = clamp((m_rust.a * rust_mask * (0.6 + 0.6 * fine) + m_streaks * streak * dirt) * wear.x, 0.0, 1.0);
	vec3 rc = m_rust.rgb * (0.75 + 0.5 * mid);
	col = mix(col, rc, r);
	rough = mix(rough, 0.9, r);
	metal = mix(metal, 0.25, r);

	// Worn edges: chipped back to bright metal (or lighter wood and stone).
	float chips = smoothstep(0.3, 0.6, vnoise3(p * 31.0) + 0.25 * edge);
	float e = m_edge.a * wear.y * edge * chips * (1.0 - 0.6 * r);
	col = mix(col, m_edge.rgb * (0.85 + 0.3 * fine), e);
	metal = mix(metal, m_edge_metal, e);
	rough = mix(rough, rough * 0.6, e);

	// Grime: settles in occluded corners and climbs up from the ground.
	float ground = 1.0 - smoothstep(0.0, m_ground_height, world_y);
	float g = m_grime.a * wear.z * dirt * clamp(occluded * 1.4 + ground * 0.8, 0.0, 1.0) * (0.55 + 0.6 * patches);
	col = mix(col, m_grime.rgb, clamp(g, 0.0, 0.85));
	rough = mix(rough, 0.95, g);
	metal = mix(metal, 0.1, g);

	// Dust on surfaces facing up.
	float d = m_dust.a * wear.w * smoothstep(0.35, 0.95, n.y) * smoothstep(0.3, 0.7, patches + 0.2 * fine);
	col = mix(col, m_dust.rgb, d);
	rough = mix(rough, 1.0, d);
	metal = mix(metal, 0.0, d);

	col *= belt_shade;
	col = mix(col, belt_chevron.rgb * (0.9 + 0.2 * fine), chevron);

	// Baked occlusion darkens direct light too: Factorio's sprites have it painted in.
	float shade = mix(1.0, ao, m_ao);

	// The sprite over all that, where Factorio's camera sees this face. It carries its own
	// occlusion, so the baked one mostly steps back.
	col = mix(col, sprite.rgb, sprite_w);
	rough = mix(rough, 0.7, sprite_w);
	metal = mix(metal, 0.15, sprite_w);
	shade = mix(shade, 1.0 - 0.3 * (1.0 - shade), sprite_w);
	if (sprite_debug) {
		col = mix(vec3(0.8, 0.1, 0.1), vec3(0.1, 0.8, 0.1), sprite_w);
	}
	ALBEDO = col * mix(1.0, shade, 0.65);
	ALBEDO *= mix(vec3(1.0), f3d_paint * 1.4, 0.6 * step(dot(f3d_paint, vec3(1.0)), 2.99));
#ifdef LEAF_CUT
	ALBEDO *= leaf_shade;
#endif
	float up = clamp((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).y, 0.0, 1.0);
	ALBEDO *= mix(1.0, mix(m_light.x, m_light.y, up), pc * (1.0 - sprite_w));
	AO = shade;
	AO_LIGHT_AFFECT = 0.3;
	ROUGHNESS = rough;
#ifdef LEAF_CUT
	// Leaves keep their base roughness: with SSAO on, Godot's depth prepass writes normals and
	// roughness, so every one of a crown's dozen cut-out card layers ran the weathering noise and
	// sprite sampling feeding `rough` there, which nothing else in that pass needs.
	ROUGHNESS = mix(m_rough, 0.85, pc);
#endif
	METALLIC = metal;
	SPECULAR = mix(0.5, 0.2, pc);
	float wave = 1.0;
	if (m_flicker > 0.0) {
		float t = TIME * 8.0 + inst_seed * 40.0 - obj_pos.y * 6.0 + obj_pos.x * 2.0;
		wave -= m_flicker * (0.5 + 0.25 * sin(t) + 0.15 * sin(t * 2.3 + 1.7) + 0.1 * sin(t * 5.1 + 0.4));
	}
	if (m_pulse > 0.0) {
		wave -= m_pulse * (0.5 + 0.5 * sin((TIME * m_rate + inst_seed) * 6.2831853));
	}
	EMISSION = m_emission * act * act * wave;
	if (m_glow) {
		// Idle fire boxes and lamps go dark, as Factorio's do.
		ALBEDO *= mix(0.3, 1.0, act);
	}
#ifdef BLEND_ALPHA
	// See-through light (a thruster's plume) fades away with its glow when idle; glass stays.
	ALPHA = m_albedo.a * (m_fades ? act : 1.0);
#endif
}
