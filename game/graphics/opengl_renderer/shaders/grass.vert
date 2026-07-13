#version 410 core

// Grecharged-grass-poc: procedural 3D grass for the TRAINING level (jak1).
// One instanced draw stream, two passes selected by u_mode:
//   u_mode == 0  NEAR blades  (GL_TRIANGLE_STRIP, 10 verts, curved tapered blade)
//   u_mode == 1  MID   cards  (GL_TRIANGLES,      12 verts, X-cross of two quads)
// Geometry is generated from gl_VertexID; only per-instance data comes from the VBO.
// World->clip transform is copied verbatim from collision.vert so grass lands on the
// exact same screen pixels as the scene it sits on. Flat color (no texture) per the PoC.

// per-instance data (glVertexAttribDivisor == 1)
layout (location = 0) in vec4 inst_pos;   // xyz = world base position (GOAL units, 4096 = 1 m), w = blade height
layout (location = 1) in vec4 inst_par;   // x = yaw(rad), y = tint(0..1), z = curve(0..1), w = breeze phase(0..1)
layout (location = 2) in vec4 inst_gcol;  // POLISH#4: xyz = avg colour of the ground texture under this blade (0..1)
layout (location = 3) in vec4 inst_light; // POLISH#9: rgb = ground's DYNAMIC baked light under this blade (0..1; *2 = ground factor)
layout (location = 4) in vec4 inst_normal; // ROUND#19: xyz = unit ground-face normal (world, ny>=0) for the normal-tilt blend

// scene camera (same uniforms/semantics as collision.vert)
uniform vec4 hvdf_offset;
uniform mat4 camera;
uniform vec4 camera_position;
uniform float fog_constant;

// grass controls
uniform float u_time;      // seconds, drives the breeze
uniform vec4  u_jak_pos;   // xyz = Jak world pos, w = 1 when valid (trample origin)
uniform int   u_mode;      // 0 = blade pass, 1 = card pass
// POLISH#4: adjustable LOD reach (world units) from the two Recharged Settings sliders.
uniform float u_near_dist; // near-blade fade-out radius (world units)
uniform float u_card_dist; // grass-card fade-out radius (world units)
uniform vec4  u_jak_ledge; // xyz = ledge-grab point, w = 1 while Jak hangs (ledge-parting trample)
uniform int   u_debug;     // ROUND#14 discriminator: 0 normal / 1 base-stubs (magenta) / 2 blades (cyan) / 3 cards (yellow) / 4 occ+trample forensic
uniform float u_tilt;      // ROUND#19: normal-tilt blend (0 = world-up growth, bit-identical; ~0.30 A/B)
// Grecharged-grass-overhang2 (owner defect 2: droop "descend beaucoup trop bas"): global scale on the
// droop arc's reach/drop so the hang reads like the original painted fringe's length, not curtains.
// Tunable live: prop debug.opengoal.grass.droop_len (Android) / env GRASS_DROOP_LEN (desktop).
uniform float u_droop_len;
// Grecharged-grass-overhang3: 1 while the Recharged overhang toggle is ON. Gates the transition-band
// COMB (negative-nspare walkable blades lie along their tri's down-slope) — with 0 the comb branch is
// never taken and every tagged blade runs the stock else-branch bit-identical (OFF == stock).
uniform float u_overhang;
// OWNER ROUND#18: object occluders (crates / warp-gate button) captured per-frame in Merc2 (merc
// actors, not in the static level data). xyz = world pos (GOAL units), w = ground-contact radius. A
// blade whose base is within an occluder's XZ radius AND near its ground height is hidden, so no grass
// pokes through the object. Y-gated so an object on an upper platform doesn't cull the grass below it.
uniform vec4 u_occ[16];
uniform int  u_occ_count;
// OWNER Q&A 2026-07-12: breakable actors (crates, scarecrows) captured per-frame in Merc2. Same
// (world pos, radius) layout as u_occ, but these FLATTEN the grass (like Jak's trample) instead of
// hiding it -> when the object is broken the grass springs back to full height.
uniform vec4 u_trample[16];
uniform int  u_trample_count;
// OWNER ROUND#21: eased trample RELEASE. u_trample_str[i] is the per-entry strength (0..1) the CPU
// eases in (~0.25 s) when an object is captured and out (~0.6 s) after it disappears (crate broken),
// so the grass under a broken crate springs back gradually instead of snapping upright in one frame.
uniform float u_trample_str[16];  // LEGACY (Adreno miscompiles dynamic float-array reads -> 0)
// R21f: strengths repacked as a vec4 array (.x) — the SAME array type as u_trample, whose dynamic
// indexing is PROVEN to work on the Adreno 618 (mode-4 cyan marks). float[16] dynamic reads returned
// 0 despite a valid location and upload (4th Adreno vertex-shader miscompile in this project).
uniform vec4 u_trample2[16];
// OWNER ROUND#21: Jak's recent positions (xyz) with an age-decayed strength in w (~0.6 s window,
// sampled every ~0.15 s on the CPU). The flatten under a takeoff spot (jump) or behind a sprint keeps
// pressing with the decaying strength and eases back up instead of dropping to 0 the frame the hard
// altitude gate disengages.
uniform vec4 u_jak_trail[4];

out vec3 v_color;
out float v_alpha;
out vec2 v_uv;            // card-local coords: x in [-1,1] across width, y in [0,1] up
flat out int v_is_card;   // 0 = near blade, 1 = mid card (frag cuts the card into a tuft)
out float v_seed;         // per-instance random, seeds the card tuft sub-blades

const int   SEGMENTS = 4;            // blade strip segments -> 2*(SEGMENTS+1) = 10 verts
const float TWO_PI   = 6.28318530718;

// LOD distance bands are ADJUSTABLE (POLISH#4): derived from u_near_dist / u_card_dist
// inside main() (uniforms can't initialise globals in GLSL). B_END = u_near_dist (blade
// fade-out), C_OUT1 = u_card_dist (card fade-out, pushed further out); the intermediate
// bands scale off them so the near->card->far crossfade stays seamless at any slider value.

const float TRAMPLE_R = 2.2 * 4096.0; // grass flattens within this radius of Jak
// OWNER POLISH#3: only trample when Jak is near THIS grass's ground height — not
// airborne. vgap = Jak-root-Y minus blade-base-Y; outside this band => no trample.
const float TRAMPLE_Y_LO = -1.5 * 4096.0; // up to 1.5 m below the grass -> still trample
const float TRAMPLE_Y_HI =  2.0 * 4096.0; // more than 2 m above the grass = airborne -> none
// OWNER ROUND#21: the altitude gate is now a smooth FADE band (1.2 m -> 2.0 m) instead of a hard
// cutoff at 2.0 m — crossing it during a jump used to zero the whole trample in one frame (the
// "instantanément droite" snap). Walking keeps vgap well under the band start -> unchanged.
const float TRAMPLE_Y_EASE = 1.2 * 4096.0;

// X-cross card corners (two triangles per quad), (u = width -1..1, v = height 0..1)
const vec2 CARD[6] = vec2[6](
  vec2(-1.0, 0.0), vec2(1.0, 0.0), vec2(-1.0, 1.0),
  vec2(-1.0, 1.0), vec2(1.0, 0.0), vec2( 1.0, 1.0));

vec4 world_to_clip(vec3 pos) {
  vec4 transformed = -camera[3].xyzw;
  transformed += -camera[0] * pos.x;
  transformed += -camera[1] * pos.y;
  transformed += -camera[2] * pos.z;
  float Q = fog_constant / transformed[3];
  transformed.xyz *= Q;
  transformed.xyz += hvdf_offset.xyz;
  transformed.xy -= (2048.);
  transformed.z /= (8388608.0);
  transformed.z -= 1.0;
  transformed.x /= (256.0);
  transformed.y /= -(128.0);
  transformed.xyz *= transformed.w;
  vec4 p = transformed;
  p.y *= SCISSOR_ADJUST * HEIGHT_SCALE;
  return p;
}

void main() {
  vec3 base = inst_pos.xyz;
  float H = inst_pos.w;
  float yaw = inst_par.x;
  float tint = inst_par.y;
  float curve = inst_par.z;
  float phase = inst_par.w;
  // POLISH#11: perpendicular distance from this blade's base to the nearest TRUE platform rim (world
  // units). ~1e9 for interior blades -> the edge clamp at the end of main() never triggers for them.
  float rim_dist = inst_gcol.w;

  // Grecharged-grass-overhang: nspare (inst_normal.w) == 2 marks a DROOP instance — 3D grass placed
  // on the overhang lip/fringe faces, draping DOWN over the platform edge to cover the game's painted
  // alpha overhang texture. Droop renders in the NEAR blade pass only: the card pass collapses it
  // (owner: at distance the ORIGINAL texture shows, no grass cards). Its gspare is NO_RIM, so the
  // rim height-taper and the POLISH#11 horizontal clamp never touch it (it is the intended overhang).
  // Grecharged-grass-overhang2 (owner defect 3): nspare in [3,4] marks a TRANSITION twin — a
  // walkable-top blade near a droop rim, yaw pre-pointed outward, whose shape blends upright ->
  // droop-lite by the baked lean weight w = nspare - 3 (0 at the band's inner edge, 1 at the rim).
  // Both classes live in the toggle-gated buffer tail and never get a card.
  float nsp = inst_normal.w;
  bool is_tail  = nsp > 1.5;              // droop hang OR transition twin
  bool is_droop = nsp > 1.5 && nsp < 2.5; // hanging droop on the lip faces (skips occ/trample)
  bool is_trans = nsp > 2.5;              // progressive rim-lean twin (keeps occ/trample)
  float trans_w = is_trans ? clamp(nsp - 3.0, 0.0, 1.0) : 0.0;
  // ROUND3: negative nspare = transition-band walkable blade; comb weight tw = -nsp - 1 in [0,1].
  bool is_comb = nsp < -0.5 && u_overhang > 0.5;
  float comb_w = is_comb ? clamp(-nsp - 1.0, 0.0, 1.0) : 0.0;
  if (is_tail && u_mode == 1) {
    gl_Position = vec4(2.0, 2.0, 2.0, 1.0);
    v_color = vec3(0.0); v_alpha = 0.0; v_uv = vec2(0.0); v_is_card = 1; v_seed = 0.0;
    return;
  }

  // ROUND#14 DISCRIMINATOR: cull passes per debug mode so each tier can be viewed alone at a rim.
  //   u_debug 0 = normal; 1 = bases-only magenta stubs (blades only); 2 = blades only (cyan);
  //   3 = cards only (yellow). Modes 1 & 2 cull the card pass; mode 3 culls the blade pass.
  if (((u_debug == 1 || u_debug == 2) && u_mode == 1) || (u_debug == 3 && u_mode == 0)) {
    gl_Position = vec4(2.0, 2.0, 2.0, 1.0);
    v_color = vec3(0.0); v_alpha = 0.0; v_uv = vec2(0.0); v_is_card = u_mode; v_seed = 0.0;
    return;
  }

  float c = cos(yaw);
  float s = sin(yaw);
  vec3 rightv = vec3(c, 0.0, -s);   // width axis
  vec3 fwdv   = vec3(s, 0.0,  c);   // bend/curve axis

  // ROUND#14 FLOATING-OVERFLOW FIX (supervisor-endorsed): taper the blade/card HEIGHT (+ lean/width) to
  // ~0 as the base approaches its nearest TRUE rim, so no tall geometry can stand past a platform edge.
  // rim_dist is the perpendicular distance to that rim (POLISH#11); interior blades (rim_dist ~1e9) are
  // untouched (rim_h = 1). The POLISH#11 horizontal clamp already stops a blade's SPREAD from crossing
  // the rim, but it CANNOT help a base that itself sits just past the silhouette (an overhang lip the
  // topological exclusion missed) — that base grows a full-height blade STRAIGHT UP over the void = the
  // floating the owner still saw after 5 fixes. Tapering height by rim_dist collapses such a base to a
  // ~0-height stub (invisible) instead of a tall floating blade, AND makes ordinary near-rim grass a
  // short stub that cannot lean out. A SMOOTH ramp -> grass naturally shortens to the exact edge, so the
  // round#13 edge coverage / DROPPED=0 is preserved (no new bald hole — the blades are present, just
  // short right at the rim). Cards get the same taper so the mid tier can't float past edges either.
  const float RIM_TAPER = 0.45 * 4096.0;             // height fully restored 0.45 m in from the rim
  float rim_h = smoothstep(0.0, RIM_TAPER, rim_dist);
  float rim_w = mix(0.35, 1.0, rim_h);               // keep a little width so the stub stays visible

  // POLISH#4/#6: adjustable LOD bands, derived from the two slider distances (world units).
  // OWNER POLISH#6: a WIDE crossfade OVERLAP so near blades fade out and cards fade in over the
  // SAME band. Combined with the card colour now unified to the blade gradient (t_col below), the
  // two tiers are the same colour through the overlap -> the near->card transition reads seamless
  // (owner: "la transition entre les deux est bizarre").
  float B_FULL = u_near_dist * 0.55;  // blades fully opaque within this radius
  float B_END  = u_near_dist;         // blades fully faded out beyond this
  float C_IN0  = u_near_dist * 0.45;  // cards start fading in WELL before the blades are gone
  float C_IN1  = u_near_dist * 0.85;  // cards fully in (inside the blade fade-out band -> crossfade)
  float C_OUT1 = u_card_dist;         // cards gone (pushed further out)
  float C_OUT0 = u_card_dist * 0.78;  // cards start fading out

  // --- LOD fade (per-instance, from camera distance to the blade base) ---
  float cam_dist = distance(base, camera_position.xyz);
  float alpha;
  if (u_mode == 0) {
    alpha = 1.0 - smoothstep(B_FULL, B_END, cam_dist);
  } else {
    alpha = smoothstep(C_IN0, C_IN1, cam_dist) * (1.0 - smoothstep(C_OUT0, C_OUT1, cam_dist));
  }
  if (alpha <= 0.004) {
    // fully culled by LOD: collapse offscreen so no fragments are shaded
    gl_Position = vec4(2.0, 2.0, 2.0, 1.0);
    v_color = vec3(0.0);
    v_alpha = 0.0;
    v_uv = vec2(0.0);
    v_is_card = u_mode;
    v_seed = 0.0;
    return;
  }

  // OWNER ROUND#18: hide grass under overlapping ground objects (crates / warp-gate button). base is
  // the blade's ground position; u_occ[i] = (world xyz, ground-contact radius). yd = grass Y - object
  // root Y: cull only when the object sits on THIS grass height (band [-2.5 m .. +1 m]) so an object on
  // a higher/lower platform never culls this grass. Collapses the whole blade/card offscreen.
  // ROUND#19 debug mode 4: instead of hiding/flattening, MARK blades inside a registered CULL radius
  // (dbg_occ) or TRAMPLE radius (dbg_tr) so one device frame shows exactly where the shader thinks the
  // captured actors are (discriminates "uniforms never land" from "condition wrong").
  // ROUND#19: flag accumulation in the loop (<=16 iters), single exit AFTER it. (NOTE: the theory
  // that the round#18 mid-loop `return` caused the Adreno deadlock was FALSIFIED by the grass_dbg
  // device bisect — cards-only mode runs this same restructured block and is stable, and the real
  // wedge was the blade-branch normalize(mix(...)) growth axis, fixed below. The restructure is
  // kept: it is equivalent and simpler for the compiler.)
  float dbg_occ = 0.0;
  float dbg_tr = 0.0;
  bool occ_cull = false;
  // R21f ADRENO FIX (4th miscompile class): uniform-array reads with a DYNAMIC index return garbage
  // on the Adreno 618 (mode-7 value-probe: u_trample[0] constant-indexed reads the CORRECT radius, the
  // dynamically-indexed loop saw a tiny one; the occ loop saw a too-BIG one = the owner's button
  // margin). Constant loop bounds force full unroll -> every index is constant -> correct reads.
  // R21f FINAL (Adreno): LITERAL-index unroll via macro — [16] uniform arrays spill and their
  // dynamic/loop reads return garbage on the Adreno 618 (mode-7 probe: [0] constant reads correct;
  // small [4] arrays like u_jak_trail work). 8 nearest entries are ample (CPU sorts by distance).
#define OC_STEP(i) if (i < u_occ_count) { vec2 od = base.xz - u_occ[i].xz; float yd = base.y - u_occ[i].y; if (dot(od, od) < u_occ[i].w * u_occ[i].w && yd > -1.2 * 4096.0 && yd < 1.0 * 4096.0) { occ_cull = true; } }
  OC_STEP(0) OC_STEP(1) OC_STEP(2) OC_STEP(3) OC_STEP(4) OC_STEP(5) OC_STEP(6) OC_STEP(7)
#undef OC_STEP
  // (droop blades hang on the lip faces past the walkable edge — object culls/tramples are a
  // walkable-top concern and must not collapse or bend them, so droop skips both.)
  if (occ_cull && !is_droop) {
    if (u_debug == 4) {
      dbg_occ = 1.0;  // forensic: mark, don't collapse
    } else {
      gl_Position = vec4(2.0, 2.0, 2.0, 1.0);
      v_color = vec3(0.0);
      v_alpha = 0.0;
      v_uv = vec2(0.0);
      v_is_card = u_mode;
      v_seed = 0.0;
      return;
    }
  }

  // shared breeze: a gust travelling across the field (spatial phase) plus a
  // per-instance offset, so the whole lawn reads as ONE wind but no two blades
  // move in lockstep.
  float gust = u_time * 1.7 + phase * TWO_PI + (base.x + base.z) * 0.00035;

  // --- trample: flatten + push away from Jak within TRAMPLE_R ---
  // OWNER POLISH#3: gate by Jak's ALTITUDE so the grass only bends when he is on/
  // near the ground, not while airborne (jumping) above it.
  // OWNER ROUND#21: EASED RELEASE. Two changes vs the old single-sample hard gate:
  //  (a) the altitude cutoff is a smooth fade band (TRAMPLE_Y_EASE -> TRAMPLE_Y_HI), and
  //  (b) sample 0 is Jak NOW, samples 1..4 are his recent trail with age-decayed strength
  //      (u_jak_trail, ~0.6 s window) — so when the foot leaves (jump) the flatten at the
  //      takeoff spot eases back up over ~0.6 s instead of snapping upright in one frame.
  // MAX over samples (not sum) so overlapping samples cannot over-press. Flag-accumulation
  // style, no mid-loop return/continue, pure mad/smoothstep math (Adreno-618-safe).
  float heightMul = 1.0;
  vec3 trample = vec3(0.0);
  float bestk = 0.0;
  vec2  bestd = vec2(0.0, 1.0);
  for (int ji = 0; ji < 5; ++ji) {
    int ti = (ji > 0) ? (ji - 1) : 0;  // never a negative index expression (Adreno paranoia)
    vec4 J = (ji == 0) ? u_jak_pos : u_jak_trail[ti];
    float jstr = min(J.w, 1.0);
    float jgap = J.y - base.y;
    if (jstr > 0.004 && jgap > TRAMPLE_Y_LO && jgap < TRAMPLE_Y_HI) {
      vec2 d = base.xz - J.xz;
      float dist = length(d);
      if (dist < TRAMPLE_R) {
        float afade = 1.0 - smoothstep(TRAMPLE_Y_EASE, TRAMPLE_Y_HI, jgap);
        float k = (1.0 - dist / TRAMPLE_R) * afade * jstr;  // 0 at edge -> 1 at Jak, eased
        if (k > bestk) { bestk = k; bestd = d; }
      }
    }
  }
  if (bestk > 0.0) {
    float bdist = length(bestd);
    vec2 away = bdist > 1.0 ? bestd / bdist : vec2(0.0, 1.0);
    trample = vec3(away.x, 0.0, away.y) * (bestk * bestk) * H * 1.3;
    heightMul = 1.0 - bestk * 0.8;                 // press the blade down
  }

  // OWNER POLISH#4: LEDGE-GRAB parting — while Jak hangs on a ledge with his hands
  // (u_jak_ledge = the grab point, world units), the ledge-top grass parts around his
  // hands just like walk-trample on the ground. Gated by the grab point being near THIS
  // grass's height (NOT Jak's root altitude — he hangs BELOW the ledge, so the walk gate
  // above would never fire for the ledge grass).
  if (u_jak_ledge.w > 0.5) {
    float lgap = abs(u_jak_ledge.y - base.y);
    if (lgap < 1.5 * 4096.0) {
      vec2 dl = base.xz - u_jak_ledge.xz;
      float distl = length(dl);
      if (distl < TRAMPLE_R) {
        float kl = 1.0 - distl / TRAMPLE_R;
        vec2 awayl = distl > 1.0 ? dl / distl : vec2(1.0, 0.0);
        trample += vec3(awayl.x, 0.0, awayl.y) * (kl * kl) * H * 1.3;
        heightMul = min(heightMul, 1.0 - kl * 0.8);
      }
    }
  }

  // OWNER Q&A 2026-07-12: BREAKABLE actors (crates, scarecrows) FLATTEN the grass like Jak's footstep
  // instead of culling it -> when the object is broken the grass at its spot is still there and springs
  // back. Press the blade nearly flat within the object's ground footprint and splay it outward; keep
  // the blade (no collapse). u_trample[i] = (world pos, footprint radius); Y-gated like the object cull.
  if (u_debug == 6 && u_trample_count > 0) dbg_tr = 1.0;  // R21f bisect: does count even arrive?
  // R21f GPU value-probe: mode 6 = grayscale count/16; mode 7 = R:radius0/2m G:strength0 B:0.
  // Read the pixel -> know EXACTLY what the GPU sees (Adreno uniform corruption forensics).
// R21g PLATEAU profile (owner: crates STILL looked unflattened): the linear-from-CENTER falloff meant
// the object's own model hid the strong zone and edge grass was only ~50% pressed. Now: FULL flatten
// across the whole footprint (w), fading out over +0.45 m beyond it — the grass a player can SEE at a
// crate's side is pressed flat.
// ROUND#22 (owner: "on ne voit pas d'herbe couchée sur les bords"): LYING-DOWN ring — in the fade
// band just OUTSIDE the footprint the blades must visibly LIE flat OUTWARD, not merely shrink. rw
// ramps 0 (core) -> 1 (ring); the core keeps the owner-validated plateau press (height -> 10%,
// lateral mk^2), the ring keeps MODERATE height (cut eases to 50%) but gets a STRONG linear lateral
// push (mk * 1.8 * H, tip-weighted downstream) so the visible edge grass lies radially outward.
// Literal-index unroll only (R21f LOCKED Adreno pattern), pure mad/clamp/mix math.
#define TR_FADE (0.45 * 4096.0)
#define TR_RINGW (0.20 * 4096.0)
#define TR_STEP(i) if (i < u_trample_count) { vec2 md = base.xz - u_trample[i].xz; float myd = base.y - u_trample[i].y; float mr = u_trample[i].w; float mout = mr + TR_FADE; if (u_debug == 5 && dot(md, md) < mout * mout) dbg_tr = 1.0; if (dot(md, md) < mout * mout && myd > -2.5 * 4096.0 && myd < 1.0 * 4096.0) { if (u_debug == 4) dbg_tr = 1.0; float mdist = length(md); float mk = (1.0 - clamp((mdist - mr) / TR_FADE, 0.0, 1.0)) * u_trample2[i].x; float rw = smoothstep(mr - TR_RINGW, mr + 0.15 * 4096.0, mdist); heightMul = min(heightMul, 1.0 - (0.90 - 0.40 * rw) * mk); vec2 maway = mdist > 1.0 ? md / mdist : vec2(1.0, 0.0); trample += vec3(maway.x, 0.0, maway.y) * mix(mk * mk, mk * 1.8, rw) * H; } }
  TR_STEP(0) TR_STEP(1) TR_STEP(2) TR_STEP(3) TR_STEP(4) TR_STEP(5) TR_STEP(6) TR_STEP(7)
#undef TR_STEP

  vec3 pos;
  float t_col;
  if (u_mode == 0) {
    // ---------- NEAR: curved, tapered blade ----------
    int seg = gl_VertexID / 2;
    int side = gl_VertexID - seg * 2;              // 0 or 1
    float t = float(seg) / float(SEGMENTS);        // 0 base -> 1 tip
    // ROUND#19 GPU-WEDGE FIX (the real one — device-bisected): blades whose base sits almost ON the
    // camera rasterize as screen-filling blended quads; in a 150%-density field one frame's fill then
    // exceeds the Adreno 618 kgsl watchdog (~2s) -> IOCTL_KGSL errno-35 "Resource deadlock" -> ANR
    // SIGKILL ~5s after spawn. Bisect proof: cards-only (never nearer than the card LOD band) survive,
    // blades-only die, density 50% survives, the round#18 shader dies too (code exonerated — it is the
    // FILL). Collapse blade geometry within ~1.1 m of the camera (industry-standard near-fade): zero
    // area = zero fragments, so worst-case fill is bounded no matter the density or camera path.
    float nearf = smoothstep(0.35 * 4096.0, 1.1 * 4096.0, cam_dist);
    // OWNER POLISH#3: wider, fuller blades so the lawn reads DENSER (more ground
    // coverage per blade) on top of the higher instance budget (density++ #1 ask).
    float hw = H * 0.092 * (1.0 - 0.66 * t) * rim_w * nearf; // half width, tapering to the tip (+ rim taper)

    // breeze: shared gust, grows toward the tip
    float sway = sin(gust) * t * t;
    float bend = curve * t * t;                    // static curvature
    float fwd_amt = (bend + sway * 0.38) * H * rim_h;  // ROUND#14: no lean past a rim

    // ROUND#19: optional normal-tilt — the blade leans toward its ground polygon's face normal by
    // u_tilt (0 = EXACTLY the old world-up growth term). ADRENO-SAFE FORM: the first implementation,
    // `normalize(mix(vec3(0,1,0), inst_normal.xyz, u_tilt))`, wedged the Adreno 618 at the FIRST blade
    // draw (kgsl WAITTIMESTAMP errno 35 -> app SIGKILL ~2s later) — device-bisected via grass_dbg
    // (blades-only died, cards-only survived; the only blade-branch delta was this expression), and
    // disabling the attrib-4 fetch (grass_noattr4=1) did NOT help, so the trigger is the normalize/mix
    // expression itself in this branch, not the per-instance normal fetch. Small-angle linear tilt
    // (pure multiply-adds) renders the same 30%-blend look without the wedge.
    float grow_h = t * H * heightMul * rim_h * nearf;  // ROUND#14 rim taper + trample (+ lens near-fade)

    if (is_droop) {
      // Grecharged-grass-overhang DROOP blade: emerges from the lip face, reaches OUTWARD over the
      // drop (fwdv = the scan-resolved outward direction, encoded in yaw) and arcs DOWNWARD below
      // its base — gravity-biased, covering the painted alpha fringe strip. H here is the droop
      // LENGTH (scaled to the face's vertical span at placement). No trample/occ/rim influence (it
      // is the intended overhang); the Adreno near-fill fade (nearf, in hw) is kept. Gentle pendulum
      // sway instead of the upright gust lean.
      // ROUND3 droop: the blade grows ALONG its host tri's plane. inst_normal.xyz now carries the
      // bake-computed unit IN-PLANE DOWN-SLOPE (dsl) of the fringe/lip face and H is the length,
      // already capped at the tri's own exit distance -> the drape follows the mesh relief by
      // construction and never extends past the painted fringe. u_droop_len is a live multiplier
      // (default 1.0). Small gravity sag off the plane + gentle sway; pure mad math (no
      // normalize(mix()) — the ROUND#19 Adreno-618 wedge class).
      float dlen = clamp(u_droop_len, 0.1, 1.5);
      vec3 dsl = inst_normal.xyz;
      float dsway = sin(gust * 0.8) * t * t * 0.05 * H;
      pos = base
          + rightv * ((float(side) * 2.0 - 1.0) * hw + dsway)
          + dsl * (t * H * dlen * nearf)
          + vec3(0.0, -0.15 * t * t * H * dlen * nearf, 0.0);
    } else if (is_trans) {
      // ROUND2 (owner defect 3): PROGRESSIVE upright->droop transition twin. Placed on the walkable
      // top within the rim-taper band of a droop rim, yaw already outward. At w~0 (band's inner
      // edge) it is a faded-in upright blade; at w=1 (the rim) it is a droop-lite arc — while the
      // stock upright originals shrink to stubs over the same band (LOCKED rim taper), so together
      // the field bends gradually over the lip. Keeps trample/occ (it IS walkable-top grass).
      float dlen = clamp(u_droop_len, 0.1, 1.5);
      float fade_in = smoothstep(0.02, 0.30, trans_w);  // no pop at the band's inner edge
      hw *= fade_in;
      float up_y   = t * H * heightMul * nearf;                          // stock upright growth
      float fwd_up = (bend + sway * 0.38) * H;                           // stock upright lean/sway
      // ROUND3: the twin's target is the new COMB shape (lean outward toward horizontal, staying on
      // the walkable top), not the old below-base parametric arc — so the flat-top lean continues
      // seamlessly into the band comb and the rooted droop rows.
      float dh = (0.85 - 0.25 * t) * t * H * dlen;
      float dv = 0.25 * t * H;
      pos = base
          + rightv * ((float(side) * 2.0 - 1.0) * hw)
          + fwdv * mix(fwd_up, dh + sin(gust) * t * t * 0.04 * H * dlen, trans_w)
          + vec3(0.0, mix(up_y, dv * nearf, trans_w), 0.0)
          + trample * t * (1.0 - 0.5 * trans_w);
    } else if (is_comb) {
      // ROUND3 transition-band COMB (toggle ON only; OFF runs the stock branch below bit-identical).
      // The blade's growth axis lerps from world-up to the in-plane down-slope of ITS OWN face by the
      // baked tilt weight comb_w, so the curl's grass lies along the mesh instead of towering out of
      // it — the middle of the upright->droop gradient. Down-slope derived analytically from the face
      // normal (pure mads + one inversesqrt; NOT normalize(mix()) — Adreno-618 wedge class). The rim
      // height-taper and the POLISH#11 horizontal clamp ease off as comb_w grows: a combed blade lies
      // ON the surface, so crossing the rim's XZ projection is correct, not an overflow.
      float ny2 = inst_normal.y * inst_normal.y;
      float cinv = inversesqrt(max(1.0 - ny2, 1e-4));
      vec3 dslv = vec3(inst_normal.x * inst_normal.y, ny2 - 1.0, inst_normal.z * inst_normal.y) * cinv;
      float comb_rim = mix(rim_h, 1.0, comb_w);  // restore tapered height as combing takes over
      float cgrow = t * H * heightMul * comb_rim * nearf;
      vec3 up_axis = vec3(0.0, 1.0, 0.0) + vec3(inst_normal.x, 0.0, inst_normal.z) * u_tilt;
      vec3 axis = up_axis * (1.0 - comb_w) + dslv * comb_w;
      pos = base
          + rightv * ((float(side) * 2.0 - 1.0) * hw)
          + axis * cgrow
          + fwdv * (fwd_amt * (1.0 - 0.6 * comb_w))
          + trample * t * rim_h;
    } else {
    pos = base
        + rightv * ((float(side) * 2.0 - 1.0) * hw)
        + vec3(0.0, grow_h, 0.0)                   // world-up growth (u_tilt=0 path, bit-identical)
        + vec3(inst_normal.x, 0.0, inst_normal.z) * (grow_h * u_tilt)  // ROUND#19: lean toward the normal
        + fwdv * fwd_amt
        + trample * t * rim_h;
    }
    t_col = t;
    v_uv = vec2(0.0);
    v_is_card = 0;
  } else {
    // ---------- MID: X-cross grass card ----------
    // OWNER POLISH#6: the cards read "trop denses ... beaucoup plus touffue que la vraie herbe".
    // Thin the card field — skip ~30% of card instances by a deterministic per-instance hash (STABLE,
    // so no pop-in) and make each card narrower with fewer sub-blades (frag NB 5->3). The near blades
    // keep the full density, so the cards are now clearly LIGHTER than the foreground grass.
    if (fract(phase * 13.17 + tint * 7.51) > 0.70) {
      gl_Position = vec4(2.0, 2.0, 2.0, 1.0);
      v_color = vec3(0.0);
      v_alpha = 0.0;
      v_uv = vec2(0.0);
      v_is_card = 1;
      v_seed = 0.0;
      return;
    }
    int quad = gl_VertexID / 6;                    // 0 or 1
    int li = gl_VertexID - quad * 6;
    vec2 uv = CARD[li];
    vec3 axis = (quad == 0) ? rightv : fwdv;       // two crossed quads
    float cardH = H * 1.25 * rim_h;                  // match near heights (+ ROUND#14 rim taper)
    // ROUND3: transition-band cards shrink with the comb weight while the toggle is ON (the curl's
    // mid-distance look = short tufts over the painted fringe); stock height when OFF.
    cardH *= (1.0 - 0.75 * comb_w);
    float cardHW = H * 0.38 * rim_w;                 // POLISH#6: narrower clump (+ rim taper)

    // card wind sway: SAME gust as the blades but MUCH GENTLER than the near blades
    // (owner polish#3: cards swayed "beaucoup plus à fond que devant"). Near-blade
    // fwd sway peaks ~0.38*H; cards now peak ~0.12*H — clearly under the foreground.
    float csway = sin(gust * 0.7) * uv.y * uv.y * rim_h;  // ROUND#14: no card sway past a rim

    pos = base
        + axis * (uv.x * cardHW)
        + vec3(0.0, uv.y * cardH * heightMul, 0.0)
        + fwdv * (csway * H * 0.12)
        + rightv * (csway * H * 0.04)
        + trample * uv.y * rim_h;
    // OWNER POLISH#6: use the EXACT same vertical gradient as the near blade (t_col = local
    // height). With the identical tint / ground-harmonisation / baked-light pipeline below applied
    // to both tiers, a card and a blade at the same height are the SAME colour by construction — so
    // the grass no longer "change de couleur quand on avance" and the crossfade band blends cleanly.
    t_col = uv.y;
    v_uv = uv;
    v_is_card = 1;
  }

  // ROUND#14 DISCRIMINATOR mode 1: replace the blade with a ~7 cm vertical sliver at the EXACT base
  // (no lean/width/sway/trample), so the capture shows precisely where blade BASES sit. If these
  // magenta base markers float over the void at a rim, the floating is H-B (bases past the visible
  // silhouette) — no geometry clamp can help; the fix must be in BASE PLACEMENT.
  if (u_debug == 1) {
    int dseg = gl_VertexID / 2;
    int dside = gl_VertexID - dseg * 2;
    float dt = float(dseg) / float(SEGMENTS);
    pos = base + rightv * ((float(dside) * 2.0 - 1.0) * 0.02 * 4096.0)
              + vec3(0.0, dt * 0.07 * 4096.0, 0.0);
  }

  // --- flat color: vertical gradient (dark base -> bright tip) + per-blade tint ---
  // OWNER POLISH: more tint variation (wider brightness + a hue jitter so some
  // blades are warmer / cooler green).
  float tint2 = fract(tint * 7.919 + 0.371);       // decorrelated secondary random
  vec3 base_dark  = vec3(0.075, 0.185, 0.040);
  vec3 base_light = vec3(0.40, 0.66, 0.20);
  vec3 col = mix(base_dark, base_light, t_col);
  col *= (0.62 + 0.72 * tint);      // wider brightness variation per blade
  float hue = tint2 - 0.5;          // -0.5 .. 0.5
  col.r *= (1.0 + 0.50 * hue);      // warmer <-> cooler green
  col.b *= (1.0 - 0.35 * hue);
  col.g *= (0.88 + 0.22 * tint);

  // OWNER POLISH#4: sample/match the GROUND TEXTURE colour. inst_gcol.rgb is the average
  // colour of the tfrag/tie ground texture UNDER this blade (computed at placement). Shift
  // the canonical grass-green toward that ground tone and let a little of the literal ground
  // colour bleed in, so the grass never clashes with the texture showing through (a bright
  // green blade over sandy/mossy ground would "faire tâche"). Per-location — grass over
  // tra-grass, tra-beachrock and the beach fringes each takes its own matching green. The
  // CARDS use the same per-instance ground colour, so near->far stays one seamless colour.
  vec3 gcol = inst_gcol.rgb;
  vec3 groundRef = vec3(0.24, 0.34, 0.14);   // a canonical grassy-ground average
  vec3 harmon = col * clamp(gcol / max(groundRef, vec3(0.04)), vec3(0.55), vec3(1.9));
  col = mix(col, harmon, 0.55);              // shift the green toward the ground's tone
  col = mix(col, gcol, 0.16);                // a touch of the literal ground colour blends in

  // OWNER POLISH#7: match the grass LUMINANCE to the ground albedo so blades are not brighter than
  // the ground they grow from (owner: grass "bien plus lumineuse que la texture du sol de partout,
  // même aux endroits les plus éclairés"). Pull the grass brightness toward the ground-texture
  // brightness while keeping some per-blade variation (hue is preserved — only magnitude is scaled).
  float glum  = dot(col,  vec3(0.299, 0.587, 0.114));
  float grlum = dot(gcol, vec3(0.299, 0.587, 0.114));
  if (glum > 0.001) {
    float lm = clamp(grlum / glum, 0.45, 1.15);
    col *= mix(1.0, lm, 0.6);
  }

  // OWNER POLISH#9 (#1 owner priority): apply the GROUND's ACTUAL baked light — per-channel + DYNAMIC.
  // inst_light.rgb is the ground vertex's interpolated baked colour UNDER this blade at the CURRENT
  // time of day (normalized [0,1]; re-uploaded by update_light() as the day/night cycle advances).
  // *2.0 recovers the EXACT factor tfrag/TIE multiply the ground texture by (fragment_color =
  // (palette/255)*2), so the grass darkens/brightens EXACTLY like the ground beneath it — per LOCATION
  // and per TIME OF DAY. Where the baked light darkens the ground the grass darkens with it (owner:
  // grass "fait tâche quand le baked lighting rend le sol plus sombre"). The old build multiplied by a
  // FROZEN, level-MEAN-centred luma (inst_gcol.w) sampled once at load -> it never tracked the ground.
  col *= inst_light.rgb * 2.0;
  col = clamp(col, vec3(0.0), vec3(1.5));

  // ROUND#14 DISCRIMINATOR colour override (flat, bypasses the grass/light pipeline so the tier
  // is unmistakable in the capture): 1 = magenta base stubs, 2 = cyan blades, 3 = yellow cards.
  if (u_debug == 1) col = vec3(1.0, 0.0, 1.0);
  else if (u_debug == 2) col = vec3(0.05, 1.0, 1.0);
  else if (u_debug == 3) col = vec3(1.0, 1.0, 0.05);

  v_color = col;
  // ROUND#19 debug mode 4: paint blades inside a registered object-CULL radius MAGENTA and inside a
  // TRAMPLE radius CYAN (instead of hiding them) — one device frame shows exactly where the shader
  // thinks the captured actors are, discriminating "uniforms never land" from "condition wrong".
  if (u_debug == 6) v_color = vec3(float(u_trample_count) / 16.0);
  if (u_debug == 7) v_color = vec3(u_trample[0].w / 8192.0, u_trample2[0].x, 0.0);
  if (u_debug >= 4) {  // R21f: modes 4/5 = clause marks
    if (dbg_occ > 0.5) v_color = vec3(1.0, 0.0, 1.0);
    else if (dbg_tr > 0.5) v_color = vec3(0.0, 1.0, 1.0);
  }
  v_alpha = alpha;
  v_seed = tint * 331.0 + phase * 71.0;   // per-instance tuft seed

  // OWNER POLISH#11: HARD geometric edge clip. Clamp the blade's TOTAL horizontal offset from its base
  // to rim_dist (the distance to the nearest true platform rim), so nothing — width, static bend,
  // breeze sway or trample — can cross the rim. Full height is kept (no bald fringe); only the
  // horizontal spread shrinks as a blade nears a rim, so the lawn fills right to the exact edge without
  // any blade floating past it. Interior blades have rim_dist ~ 1e9, so this never triggers for them.
  {
    vec2 off_xz = pos.xz - base.xz;
    float off_m = length(off_xz);
    // ROUND3: a combed blade lies along the surface past the rim's XZ projection by design — relax
    // the clip with comb_w (comb_w = 0 when the toggle is OFF -> stock behavior).
    float clip_dist = mix(rim_dist, 1.0e9, comb_w);
    if (off_m > clip_dist) {
      pos.xz = base.xz + off_xz * (clip_dist / off_m);
    }
  }

  gl_Position = world_to_clip(pos);
}
