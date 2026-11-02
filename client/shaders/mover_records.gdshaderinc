// Movers drawn on the GPU (mover_records.gd): flying robots, walking biters, spitters and wrigglers.
// Each mover has a record of MOVER_TEXELS texels in the f3d_movers texture, written by the CPU only
// when a new position of it arrives: its last four positions (A to D, oldest first) and their game
// ticks, its lag behind the clock (movers.gd: about two sends, more for coarse movers, eased when
// that changes), its height, the distance it had walked by A, when the record was written, its
// facing then and the facing it turns to, and a few values per kind. Every frame the CPU sets only
// the clock (f3d_mover_clock); here each vertex works out where its mover is drawn now, as movers.gd
// did on the CPU every frame (_drawn_at at the clock less the lag): between the two positions around
// that tick, before A at A, and after D run on along C-D for up to `ext` of that step (1 for coarse
// movers such as robots: they stop at D until the next comes).
//
// Record (texels, floats):
//   0  A.x, A.z, B.x, B.z          1  C.x, C.z, D.x, D.z (tiles)
//   2  game ticks of A, B, C, D on the record's clock
//   3  flags, height, distance walked by A (tiles), clock tick the record was written
//   4  facing then, facing it turns to (radians), and two values carried from then (robots: how
//      much it flew, how far its arms reached)
//   5  creatures: gait seed (radians), radians of gait per tile, bob scale; robots: bob phase; all:
//      ext in w
//   6  its lag (ticks) when written, the clock's gap between messages then and the gap it eases to,
//      and its own ticks between positions (movers.gd: its lag goes to the larger of two gaps and of
//      a gap and its own spacing, at half a tick a tick growing and a tick a tick shrinking)
//   7  how fast the clock's gap grows (ticks a tick; game_clock.gd `ease`)
// flags: 1 on the odd clock, 2 hidden (remote view fog), 4 a construction robot, 8 carrying cargo,
// 16 a robot that animates (logistic, construction).
// The clock: x and y are the clock tick since the latest even and odd epoch began (two clocks, so
// the numbers stay small and precise in a long game: mover_records.gd moves every record onto the
// newer clock before the older one starts again), z the game's ticks a second as the client
// measures them, w seconds of real time (wrapping every 200 s, a whole number of idle gait loops).

global uniform sampler2D f3d_movers;
global uniform vec4 f3d_mover_clock;

const int MOVER_TEXELS = 8;
const int MOVER_ROW = 1024;
const float MOVER_TURN_RATE = 15.0;  // movers.gd FOLLOW_RATE: how fast the facing eases (1 / seconds)

struct MoverState {
	vec3 pos;      // where it is drawn
	float yaw;
	float walked;  // tiles walked to here, from the distance walked by A
	float speed;   // tiles a second along its path now
	float average; // tiles a second from A to where it is drawn (a few ticks: its speed, smoothed)
	float still;   // seconds since it stopped at its last position (0 while it moves)
	float since;   // seconds since the record was written
	float flags;
	vec4 carried;  // texel 4
	vec4 kind;     // texel 5
};

vec4 mover_texel(int slot, int i) {
	int idx = slot * MOVER_TEXELS + i;
	return texelFetch(f3d_movers, ivec2(idx % MOVER_ROW, idx / MOVER_ROW), 0);
}

bool mover_flag(float flags, float bit) {
	return mod(floor(flags / bit + 0.001), 2.0) > 0.5;
}

// move_toward(from, to, step)
float mover_toward(float from, float to, float step) {
	return from + clamp(to - from, -step, step);
}

// Its lag `ticks` clock ticks after the record was written: as movers.gd eased it every frame
// towards what it wants (two of the clock's gaps, or a gap and its own spacing), while the clock's
// gap eases to its goal (game_clock.gd advance).
float mover_lag(vec4 r6, float ease, float ticks) {
	float gap = mover_toward(r6.y, r6.z, ticks * (r6.z > r6.y ? ease : 1.0));
	float want = max(2.0 * gap, r6.w + gap);
	return want >= r6.x ? min(r6.x + 0.5 * ticks, want) : max(r6.x - ticks, want);
}

MoverState mover_state(int slot) {
	vec4 r0 = mover_texel(slot, 0);
	vec4 r1 = mover_texel(slot, 1);
	vec4 r2 = mover_texel(slot, 2);
	vec4 r3 = mover_texel(slot, 3);
	vec4 r6 = mover_texel(slot, 6);
	float ease = mover_texel(slot, 7).x;
	MoverState s;
	s.carried = mover_texel(slot, 4);
	s.kind = mover_texel(slot, 5);
	s.flags = r3.x;
	float now = mover_flag(r3.x, 1.0) ? f3d_mover_clock.y : f3d_mover_clock.x;
	float rate = max(f3d_mover_clock.z, 1.0);
	// The tick drawn now: the clock less the lag.
	float after = max(now - r3.w, 0.0);
	float lag = mover_lag(r6, ease, after);
	float drawn = now - lag;
	float pace = 1.0 - (lag - mover_lag(r6, ease, max(after - 1.0, 0.0)));  // game ticks drawn a clock tick
	vec2 p[4] = vec2[4](r0.xy, r0.zw, r1.xy, r1.zw);
	float t[4] = float[4](r2.x, r2.y, r2.z, r2.w);
	vec2 at = p[0];
	float walked = 0.0;
	float speed = 0.0;
	float still = 0.0;
	if (drawn > t[0]) {
		bool found = false;
		for (int i = 0; i < 3; i++) {
			float len = distance(p[i], p[i + 1]);
			float span = t[i + 1] - t[i];
			if (!found && drawn <= t[i + 1]) {
				float f = span > 1e-4 ? (drawn - t[i]) / span : 1.0;
				at = mix(p[i], p[i + 1], f);
				speed = span > 1e-4 ? len / span : 0.0;
				walked += len * f;
				found = true;
			} else if (!found) {
				walked += len;
			}
		}
		if (!found) {
			// Past D: on along C-D for up to ext of that step, then standing at its end.
			float span = t[3] - t[2];
			float len = distance(p[2], p[3]);
			float ext = s.kind.w;
			if (span > 1e-4) {
				float f = (drawn - t[2]) / span;
				if (f < ext) {
					speed = len / span;
				} else {
					still = drawn - (t[2] + ext * span);
					f = ext;
				}
				at = mix(p[2], p[3], f);
				walked += len * (f - 1.0);
			} else {
				at = p[3];
				still = drawn - t[3];
			}
		}
	}
	s.pos = vec3(at.x, r3.y, at.y);
	s.walked = r3.z + walked;
	s.speed = speed * pace * rate;
	s.average = drawn > t[0] ? walked / max(drawn - t[0], 0.5) * pace * rate : 0.0;
	s.still = still / rate;
	s.since = max(now - r3.w, 0.0) / rate;
	float d = s.carried.x - s.carried.y;
	d = mod(d + 3.14159265, 6.2831853) - 3.14159265;
	s.yaw = s.carried.y + d * exp(-MOVER_TURN_RATE * s.since);
	return s;
}

// A mover's part turned to its facing and put where it is drawn, in its instance's own space (the
// instance transform is a plain translation, MODEL_MATRIX[3]).
void mover_place(inout vec3 v, inout vec3 n, MoverState s, vec3 origin) {
	float c = cos(s.yaw);
	float si = sin(s.yaw);
	if (mover_flag(s.flags, 2.0)) {
		v = vec3(0.0);  // hidden: shrunk to nothing
	} else {
		v = vec3(c * v.x + si * v.z, v.y, -si * v.x + c * v.z) + s.pos - origin;
	}
	n = vec3(c * n.x + si * n.z, n.y, -si * n.x + c * n.z);
}
