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
// grass-wind : 1 = loi de vent de cet item, 0 = regime remplace (rejoue a l'identique).
// C'est le bras d'ablation : le shader porte LES DEUX lois, le C++ choisit laquelle tourne.
uniform float u_wind_new;
uniform int   u_mode;      // 0 = blade pass, 1 = card pass
// POLISH#4: adjustable LOD reach (world units) from the two Recharged Settings sliders.
uniform float u_near_dist; // near-blade fade-out radius (world units)
uniform float u_card_dist; // grass-card fade-out radius (world units)
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
// OWNER ROUND#21: eased trample RELEASE. u_trample_str[i] is the per-entry strength (0..1) the CPU
// eases in (~0.25 s) when an object is captured and out (~0.6 s) after it disappears (crate broken),
// so the grass under a broken crate springs back gradually instead of snapping upright in one frame.
// R21f: strengths repacked as a vec4 array (.x) — the SAME array type as u_trample, whose dynamic
// indexing is PROVEN to work on the Adreno 618 (mode-4 cyan marks). float[16] dynamic reads returned
// 0 despite a valid location and upload (4th Adreno vertex-shader miscompile in this project).
// OWNER ROUND#21: Jak's recent positions (xyz) with an age-decayed strength in w (~0.6 s window,
// sampled every ~0.15 s on the CPU). The flatten under a takeoff spot (jump) or behind a sprint keeps
// pressing with the decaying strength and eases back up instead of dropping to 0 the frame the hard
// altitude gate disengages.

#include "vegetation_contact.glsl"

out vec3 v_color;
out float v_alpha;
out vec2 v_uv;            // card-local coords: x in [-1,1] across width, y in [0,1] up
flat out int v_is_card;   // 0 = near blade, 1 = mid card (frag cuts the card into a tuft)
out float v_seed;         // per-instance random, seeds the card tuft sub-blades
// grass-shading (SPEC section 7): la direction d'avancee horizontale du brin = la NORMALE de son
// ruban. Le fragment s'en sert avec gl_FrontFacing pour separer la face eclairee de la face
// opposee (voir grass_shade_face.glsl) — la seule grandeur qui distingue les deux cotes.
out vec2 v_fwd_xz;

const int   SEGMENTS = 4;            // blade strip segments -> 2*(SEGMENTS+1) = 10 verts
const float TWO_PI   = 6.28318530718;

// LOD distance bands are ADJUSTABLE (POLISH#4): derived from u_near_dist / u_card_dist
// inside main() (uniforms can't initialise globals in GLSL). B_END = u_near_dist (blade
// fade-out), C_OUT1 = u_card_dist (card fade-out, pushed further out); the intermediate
// bands scale off them so the near->card->far crossfade stays seamless at any slider value.

// X-cross card corners (two triangles per quad), (u = width -1..1, v = height 0..1)
const vec2 CARD[6] = vec2[6](
  vec2(-1.0, 0.0), vec2(1.0, 0.0), vec2(-1.0, 1.0),
  vec2(-1.0, 1.0), vec2(1.0, 0.0), vec2( 1.0, 1.0));

// ================= grass-blade-variants (SPEC-refonte-herbe.md, section 6) ====================
// SIX SILHOUETTES, AUCUN ASSET, AUCUN SOMMET DE PLUS. Le ruban soumet toujours ses 10 sommets ;
// une variante a moins de segments replie ses rangees excedentaires (triangles degeneres, zero
// fragment). Le nombre de segments de chaque ligne est celui que `grass_blade_variants.h` declare,
// et le recensement de l'item compare les deux tables : la duplication est MESUREE.
//   VAR_A = (hauteur, demi-largeur de base, fuite lineaire, fuite carree)
//   VAR_B = (courbure, recourbe de pointe, segments, reserve)
// v0 porte les constantes historiques : desarme, le CPU ecrit 0 partout et le brin livre jusqu'ici
// est rendu AU BIT PRES (les facteurs neutres ci-dessous ne changent aucun arrondi).
const vec4 VAR_A[6] = vec4[6](
  vec4(1.00, 0.092, 0.66,  0.00),   // v0 lame   — la lame d'aujourd'hui
  vec4(1.18, 0.062, 1.00,  0.05),   // v1 fine   — haute, etroite, pointe effilee
  vec4(0.82, 0.150, 0.45, -0.25),   // v2 large  — courte et large, pointe large
  vec4(1.05, 0.105, 0.30, -0.55),   // v3 faux   — large a mi-hauteur, pointe recourbee
  vec4(1.30, 0.055, 0.35, -0.10),   // v4 jonc   — droite et raide, bout franc
  vec4(0.70, 0.125, 0.80,  0.10)    // v5 touffu — petite et trapue
);
//   VAR_B.w = PLAFOND DE COURBURE (essai 2). Owner 20/09 : « on voit clairement leurs polygones de
//   pres ». Un ruban a quatre troncons qui tourne de 70 degres montre ses plis ; chaque plafond est
//   le plus grand qui tienne l'angle entre deux troncons EMIS sous 12 degres sur toute la plage de
//   courbure du bake. Il ne s'applique QUE quand l'item est arme (octet d'instance non nul).
//   Les segments passent tous a 4 : replier des rangees, c'etait fabriquer le pli qu'il voit.
const vec4 VAR_B[6] = vec4[6](
  vec4(1.00,  0.00, 4.0, 0.48),     // v0 seg=4
  vec4(1.35,  0.25, 4.0, 0.35),     // v1 seg=4
  vec4(0.70,  0.00, 4.0, 0.59),     // v2 seg=4
  vec4(1.60,  0.45, 4.0, 0.27),     // v3 seg=4
  vec4(0.45,  0.00, 4.0, 3.00),     // v4 seg=4
  vec4(1.10, -0.20, 4.0, 0.58)      // v5 seg=4
);

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

#ifdef OG_GRASS_CONTACT_PROBE
out vec4 probe_grass_pre;
out vec4 probe_grass_post;
flat out uvec2 probe_grass_ids;
uniform int u_probe_grass_no_contact;
vec4 probe_grass_world;
#endif

void main() {
#ifdef OG_GRASS_CONTACT_PROBE
  probe_grass_world = vec4(inst_pos.xyz, 0.0); // early-out: no emitted world vertex
  probe_grass_pre = probe_grass_world;
  probe_grass_post = probe_grass_world;
  probe_grass_ids = uvec2(uint(gl_InstanceID), uint(gl_VertexID));
#endif
  vec3 base = inst_pos.xyz;
  float H = inst_pos.w;
  float yaw = inst_par.x;
  float tint = inst_par.y;
  float curve = inst_par.z;
  float phase = inst_par.w;
  // POLISH#11: perpendicular distance from this blade's base to the nearest TRUE platform rim (world
  // units). ~1e9 for interior blades -> the edge clamp at the end of main() never triggers for them.
  float rim_dist = inst_gcol.w;

  // grass-blade-variants : la silhouette de CE brin. L'indice est choisi PAR LE CPU
  // (`grass_blade_variants.h`, tire de la racine) et livre dans l'octet de poids faible de
  // `inst_light`, qui valait 255 et que personne ne lisait — aucun attribut neuf, aucune memoire
  // d'instance en plus. Desarme, le CPU ecrit 0 partout.
  // L'octet porte la variante DECALEE DE UN : 0 veut dire « item desarme », 1..6 les six
  // silhouettes. Sans ce decalage, « desarme » et « arme, variante 0 » sont le MEME octet, et le
  // bras d'ablation porterait quand meme le plafond de courbure de l'essai 2 — une ablation qui ne
  // rend pas l'etat d'avant ne separe rien.
  int vb = clamp(int(inst_light.a * 255.0 + 0.5), 0, 6);
  bool var_on = vb > 0;
  int vi = var_on ? vb - 1 : 0;
  vec4 VA = VAR_A[vi];
  vec4 VB = VAR_B[vi];
  H *= VA.x;

  // Grecharged-grass-overhang6 (owner 2026-07-14, verbatim 3-zone spec) instance classes (nspare):
  //   0        plain walkable blade.
  //   -(1+w)   TAGGED walkable original (by comb OR by zone-1 lean) — COLLAPSED in the blade pass when
  //            the toggle is ON (its tail twin takes over); runs the stock else-branch bit-identical
  //            when OFF (nspare unread). Its CARD still draws.
  //   2        droop hang class: DELETED in round 6 (no emission, shader branch removed).
  //   3+k      ZONE-1 LEAN twin (shader band 2.5<nsp<4.5), k = nsp-3. inst_normal.xz = unit outward
  //            horizontal dir, ny=0 — a walkable-top boundary blade leaning toward the void.
  //   5+w      COMB replacement twin (unchanged math) AND ZONE-2 sub-lip strip blade (shader band
  //            4.5<nsp<6.5), w = nsp-5; nx/ny/nz = SMOOTH normal.
  //   9+L+t/2  ZONE-3 TEXTURED CARD (shader nsp>8.5; ROUND 11 design pivot — the 7.x solid fall
  //            classes are DELETED). layer L = floor(nsp-9) in 0..2, +0.5 selects the hang texture
  //            (bch-leafyground-hang-2x1 instead of bch-grassfringe). nx/nz = unit outward XZ from
  //            the owning true-rim segment; the card hangs straight down sampling the native strip
  //            texels (alpha-cut), per-layer outward offset + sway + UV offset/flip.
  // All tail classes live in the toggle-gated buffer tail and never get a card.
  float nsp = inst_normal.w;
  bool is_tail  = nsp > 1.5;                       // any zone tail class (toggle-gated, never a card)
  bool is_lean  = nsp > 2.5 && nsp < 4.5;          // ZONE-1 boundary lean twin (k = nsp - 3)
  bool is_repl  = nsp > 4.5 && nsp < 6.5;          // comb replacement twin / ZONE-2 strip blade (w = nsp-5)
  bool is_fcard = nsp > 8.5;                       // ZONE-3 textured hang card (ROUND 11)
  float comb_w  = is_repl ? clamp(nsp - 5.0, 0.0, 1.0) : 0.0;
  bool is_comb_orig = nsp < -0.5;                  // tagged walkable original (comb OR lean)
  // Comb/droop math runs under the Android-injected global `precision highp float` (audited: 94 highp
  // blocks, 0 mediump) and desktop GL's highp-only default. COMB_TILT/NOFF mirror the bake plane-cap.
  const float COMB_TILT = 0.30;          // == SHADER_TILT_DEFAULT (bake plane-cap assumption); FIXED
  const float NOFF = 0.03 * 4096.0;      // root offset along the smooth normal (world units)
  if (is_tail && u_mode == 1) {
    gl_Position = vec4(2.0, 2.0, 2.0, 1.0);
    v_color = vec3(0.0); v_alpha = 0.0; v_uv = vec2(0.0); v_is_card = 1; v_seed = 0.0;
    return;
  }
  // When the overhang toggle is ON, collapse the comb-tagged walkable ORIGINAL in the BLADE pass — its
  // tail replacement (is_repl) takes over. The card pass keeps drawing it (u_mode==1 falls through).
  if (is_comb_orig && u_overhang > 0.5 && u_mode == 0) {
    gl_Position = vec4(2.0, 2.0, 2.0, 1.0);
    v_color = vec3(0.0); v_alpha = 0.0; v_uv = vec2(0.0); v_is_card = 0; v_seed = 0.0;
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
  // Grecharged-grass-overhang6: dynamic object culls apply to walkable-top classes only (stock, tagged
  // originals, zone-1 lean twins). Zone-2 strip (is_repl) + zone-3 cards (is_fcard) hang below the lip and
  // must NOT collapse — so any tail class OTHER than the zone-1 lean skips the occ cull.
  if (occ_cull && (!is_tail || is_lean)) {
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

  // grass-wind : le champ de vent partage. `gw_on = u_wind_new` selectionne le regime ;
  // a 0, le chunk rejoue a l'identique la loi que cet item remplace.
  vec3  gw_base = base;
  float gw_time = u_time;
  float gw_phase = phase;
  float gw_yaw = yaw;
  float gw_on = u_wind_new;
  float gw_w0; float gw_w1; float gw_dx; float gw_dz; float gw_amp;
  #include "grass_wind.glsl"
  vec3 gw_dir = vec3(gw_dx, 0.0, gw_dz);

  float heightMul;
  vec3 trample;
#ifdef OG_GRASS_CONTACT_PROBE
  if (u_probe_grass_no_contact != 0) {
    heightMul = 1.0;
    trample = vec3(0.0);
  } else
#endif
  vegetation_contact(base, H, u_debug, heightMul, trample, dbg_tr);

  vec3 pos;
  float t_col;
  vec2 fc_uv = vec2(0.0);    // ROUND 11: zone-3 textured-card UV (set only by the is_fcard branch)
  float fc_texb = 0.0;       // ROUND 11: which hang texture the card samples (0 = grassfringe)
  if (u_mode == 0) {
    // ---------- NEAR: curved, tapered blade ----------
    int seg = gl_VertexID / 2;
    int side = gl_VertexID - seg * 2;              // 0 or 1
    float t = float(seg) / float(SEGMENTS);        // 0 base -> 1 tip
    // MOINS DE SEGMENTS, PAS MOINS DE SOMMETS : les rangees excedentaires se replient sur leur
    // voisine. VB.z == 4.0 (v0) laisse t inchange, exactement.
    t = floor(t * VB.z + 0.5) / VB.z;
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
    // grass-blade-variants : profil de largeur QUADRATIQUE par variante. v0 = (0.092, 0.66, 0.0),
    // soit `H * 0.092 * (1.0 - 0.66 * t)` au bit pres — le terme carre vaut alors exactement +0.0.
    float hw = H * VA.y * (1.0 - VA.z * t + VA.w * t * t) * rim_w * nearf; // half width (+ rim taper)

    // breeze: shared gust, grows toward the tip
    // grass-wind : la pointe joue l'onde de la racine EN RETARD (mix des deux ancres de
    // temps), et l'accumulation en t*t du galbe est conservee. Le brin SE COURBE.
    float sway = mix(gw_w0, gw_w1, t) * t * t;
    // grass-blade-variants : courbure de base par variante, plus une recourbe de pointe. v0 =
    // (1.0, 0.0) : `(curve * 1.0) * t * t * 1.0`, associe a gauche comme l'expression d'origine.
    // grass-blade-variants essai 2 : PLAFOND DOUX. Un `min()` ecraserait la moitie des brins sur
    // la meme courbure ; cette forme conserve l'ordre et tend vers VB.w sans l'atteindre. Desarme,
    // `var_on` est faux et l'expression retombe sur `(curve * VB.x) * t * t * (1.0 + VB.y * t)`.
    float Cc = curve * VB.x;
    if (var_on && VB.w > 0.0) {
      float rr = Cc / VB.w;
      Cc = Cc * inversesqrt(1.0 + rr * rr);
    }
    float bend = Cc * t * t * (1.0 + VB.y * t);   // static curvature
    float fwd_amt = bend * H * rim_h;            // galbe statique, le long de fwdv (ROUND#14: no lean past a rim)
    float wind_amt = sway * gw_amp * H * rim_h;  // grass-wind : vent, le long du CAP du champ

    // ROUND#19: optional normal-tilt — the blade leans toward its ground polygon's face normal by
    // u_tilt (0 = EXACTLY the old world-up growth term). ADRENO-SAFE FORM: the first implementation,
    // `normalize(mix(vec3(0,1,0), inst_normal.xyz, u_tilt))`, wedged the Adreno 618 at the FIRST blade
    // draw (kgsl WAITTIMESTAMP errno 35 -> app SIGKILL ~2s later) — device-bisected via grass_dbg
    // (blades-only died, cards-only survived; the only blade-branch delta was this expression), and
    // disabling the attrib-4 fetch (grass_noattr4=1) did NOT help, so the trigger is the normalize/mix
    // expression itself in this branch, not the per-instance normal fetch. Small-angle linear tilt
    // (pure multiply-adds) renders the same 30%-blend look without the wedge.
    float grow_h = t * H * heightMul * rim_h * nearf;  // ROUND#14 rim taper + trample (+ lens near-fade)

    if (is_lean) {
      // ZONE 1 (owner round-6): walkable-top blade near the grass boundary, progressively LEANING toward
      // the void ("l'herbe commence à s'incliner vers le vide"). Replaces its collapsed tagged original.
      // inst_normal.xz = baked unit outward horizontal dir (from the nearest true-rim edge segment); the
      // growth axis blends up -> outward by kk = k*LEAN1_MAX, so the gradient runs upright (band inner
      // edge) -> ~33 deg at the lip, continuing seamlessly into the zone-2 strip blades (is_repl, w floor
      // Z2_K1 == LEAN1_MAX) just below. Pure mads (no normalize(mix()) — Adreno wedge class). Keeps the
      // lawn's bend/sway/trample so it stays alive; plane-capped at bake against inner-corner walls.
      const float LEAN1_MAX = 0.55;
      float k = clamp(nsp - 3.0, 0.0, 1.0);
      float kk = k * LEAN1_MAX;
      vec3 outw = normalize(vec3(inst_normal.x, 0.0, inst_normal.z) + vec3(1e-5, 0.0, 0.0));
      vec3 axis = vec3(0.0, 1.0, 0.0) * (1.0 - kk) + outw * kk;
      float lgrow = t * H * heightMul * nearf * (1.0 - 0.15 * k);   // slight shorten right at the rim
      float lfwd = bend * H * (1.0 - 0.4 * kk);                     // galbe statique, amorti a mesure qu'il s'incline
      // grass-wind : meme amortissement, mais le vent part le long du cap du champ.
      float lwind = sway * gw_amp * H * (1.0 - 0.4 * kk);
      pos = base
          + rightv * ((float(side) * 2.0 - 1.0) * hw)
          + axis * lgrow
          + fwdv * lfwd
          + gw_dir * lwind
          + trample * t;
    } else if (is_repl) {
      // Grecharged-grass-overhang4 COMB REPLACEMENT (tail, toggle ON only; the tagged walkable original
      // is collapsed above). The growth axis lerps from up_axis (a slight COMB_TILT lean toward the
      // smooth normal) to that normal's in-plane DOWN-SLOPE by the per-blade continuous weight comb_w,
      // so the curl's grass lies along the mesh across a seamless upright->droop gradient. Root lifted
      // n*NOFF*w; full height (gspare = NO_RIM -> rim_h = 1, no taper); static curve+sway matched to the
      // bake plane-cap tip formula. Pure mads + one inversesqrt (no normalize(mix())). The half-space
      // clamp at the end keeps it ON the surface past the rim's XZ projection (correct, not an overflow).
      float w = comb_w;
      vec3 n = inst_normal.xyz;
      float ny2 = n.y * n.y;
      float cinv = inversesqrt(max(1.0 - ny2, 1e-4));
      vec3 dv = vec3(n.x * n.y, ny2 - 1.0, n.z * n.y) * cinv;
      vec3 up_axis = vec3(n.x * COMB_TILT, 1.0, n.z * COMB_TILT);
      vec3 axis = up_axis * (1.0 - w) + dv * w;
      float cgrow = t * H * heightMul * nearf;                  // full height (no rim taper)
      float fwd = bend * H * (1.0 - 0.6 * w);                   // matches bake fwdv*curve*h*(1-0.6w)
      // grass-wind : meme amortissement (1 - 0.6w), le vent le long du cap du champ.
      float cwind = sway * gw_amp * H * (1.0 - 0.6 * w);
      pos = base
          + n * (NOFF * w)
          + rightv * ((float(side) * 2.0 - 1.0) * hw)
          + axis * cgrow
          + fwdv * fwd
          + gw_dir * cwind
          + trample * t;
    } else if (is_fcard) {
      // ZONE 3 ROUND 11 (supervisor DESIGN PIVOT): TEXTURED CARD sampling the game's own hang-alpha
      // texels — the 10-vert strip becomes 4 stacked quads of one wide card hung from the lip, so
      // the per-layer sway can bend down its length. The frag samples bch-grassfringe /
      // bch-leafyground-hang-2x1 (alpha-cut) => the near view shows EXACTLY the native art style,
      // with depth from 3 outward-offset layers + per-layer animation. Solid fall blades are gone.
      float rel = nsp - 9.0;
      float layer = clamp(floor(rel + 0.26), 0.0, 2.0);
      fc_texb = (rel - layer) > 0.26 ? 1.0 : 0.0;    // +0.5 encodes the leafyground texture
      vec3 outw = normalize(vec3(inst_normal.x, 0.0, inst_normal.z) + vec3(1e-5, 0.0, 0.0));
      vec3 lipax = normalize(cross(vec3(0.0, 1.0, 0.0), outw));   // along the lip line
      float loff = (0.05 + 0.105 * layer) * 4096.0;  // 5/15.5/26 cm out per layer (bake mirror)
      const float CARD_HW = 0.40 * 4096.0;           // == Z3C_WIDTH_M / 2
      const float RPT = 1.6 * 4096.0;                // == Z3C_REPEAT_W_M (one full u repeat)
      float cu = float(side);                        // 0..1 across the card width
      float cv = t;                                  // 0 at the lip -> 1 at the hanging bottom
      float dlen = clamp(u_droop_len, 0.1, 1.5);
      float hang = H * dlen;                         // H = bake depth (strip bottom + margin, capped)
      // per-layer sway (the pivot's animation ask): gentle pendulum along the lip, bottom-weighted,
      // per-layer frequency/phase so the layers show moving parallax and never ghost-lock.
      float sw = sin(gust * (0.8 + 0.25 * layer) + layer * 1.7 + phase * TWO_PI) * cv * cv
               * (0.035 + 0.020 * layer) * 4096.0;
      // fill guard: collapse only when the camera is basically INSIDE the curtain. The blade-pass
      // 1.1 m guard is WRONG here — the owner judges with the camera AT the edge (R10 defect 3: the
      // painted strip showed through up close exactly because the cover vanished near).
      float cnearf = smoothstep(0.12 * 4096.0, 0.30 * 4096.0, cam_dist);
      pos = base
          + outw * loff
          + lipax * ((cu - 0.5) * 2.0 * CARD_HW + sw)
          + vec3(0.0, -cv * hang * cnearf, 0.0);
      // UVs: u continuous along the lip (curve = bake arc phase at card center; the texture tiles
      // horizontally like the native strip), v spans the card top->bottom (vertical stretch = the
      // per-card length jitter of the native strands). Per-layer flip/offset: layers never show the
      // same texels at the same spot, so the parallax reads as depth, not ghosting.
      float uu = curve + (cu - 0.5) * ((2.0 * CARD_HW) / RPT);
      if (layer > 0.5 && layer < 1.5) uu = 0.31 - uu;
      if (layer > 1.5) uu += 0.47;
      fc_uv = vec2(uu, cv);
    } else {
    pos = base
        + rightv * ((float(side) * 2.0 - 1.0) * hw)
        + vec3(0.0, grow_h, 0.0)                   // world-up growth (u_tilt=0 path, bit-identical)
        + vec3(inst_normal.x, 0.0, inst_normal.z) * (grow_h * u_tilt)  // ROUND#19: lean toward the normal
        + fwdv * fwd_amt
        + gw_dir * wind_amt
        + trample * t * rim_h;
    }
    // ROUND 11: textured cards bypass the procedural colour gradient entirely (the texel IS the
    // art); v_is_card = 2 routes the frag to the hang-texture sampling branch.
    t_col = t;
    v_uv = is_fcard ? fc_uv : vec2(0.0);
    v_is_card = is_fcard ? 2 : 0;
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
    // grass-wind : la carte suit LE MEME champ que les brins — une seule direction de vent
    // dans la scene — avec le meme retard de pointe le long de sa hauteur.
    float csway = mix(gw_w0, gw_w1, uv.y) * uv.y * uv.y * rim_h;  // ROUND#14: no card sway past a rim

    pos = base
        + axis * (uv.x * cardHW)
        + vec3(0.0, uv.y * cardH * heightMul, 0.0)
        + gw_dir * (csway * H * 0.12)
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

  // grass-shading (SPEC-refonte-herbe.md, section 7) : LE MODELE DE COULEUR VIT DANS UN CHUNK
  // PARTAGE, parce que la porte de l'item doit le MESURER. `grass_shade.glsl` est compile ici par
  // le pilote et une seconde fois par le C++ de `grass_bake::shading_census()` : l'ecart de
  // luminance racine/pointe publie par la preuve est celui de CE texte, pas d'un miroir.
  // Le bloc qui etait ici lignes 511-561 y a ete deplace TEL QUEL (swizzles .r/.g/.b reecrits en
  // .x/.y/.z, seul sous-ensemble que les deux compilateurs lisent pareil).
  float gs_t = t_col;
  float gs_tint = tint;
  vec3 gs_gcol = inst_gcol.xyz;
  vec3 gs_light = inst_light.xyz;
  bool gs_card = is_fcard;
  vec3 col;
#include "grass_shade.glsl"

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
  // ROUND 11: for a textured card v_seed carries the hang-texture select (0/1) instead of the
  // procedural tuft seed (the frag's v_is_card==1 tuft path never runs for class-2 cards).
  v_seed = is_fcard ? fc_texb : tint * 331.0 + phase * 71.0;
  // grass-shading : `fwdv` est l'axe de courbure du brin, donc la normale de son ruban (le plan
  // du ruban est tendu par `rightv` et la verticale). Le fragment la combine a gl_FrontFacing.
  v_fwd_xz = vec2(s, c);

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

  // Grecharged-grass-overhang4 HALF-SPACE CLAMP (defect 1: clip-through). Every tail-blade vertex —
  // INCLUDING the dynamic sway/trample — is projected back onto the OUTER side of the base's tangent
  // plane (the smooth normal inst_normal.xyz), so nothing dips through the host surface. Mirrors the
  // bake plane-cap's rest-pose clamp; pure mads, one data-independent branch. Walkable blades (not
  // is_tail) carry a face normal here and are untouched. Grecharged-grass-overhang6: the zone-2 strip
  // blades (is_repl) must stay on the face's OUTER side (their inst_normal is the surface plane
  // normal). ZONE-1's lean (is_lean) is EXCLUDED — its inst_normal is a horizontal OUTWARD dir (not a
  // surface plane normal). ROUND 11: the zone-3 cards join the clamp with their outward-XZ normal —
  // it pins every card vertex on the outer side of the vertical plane through its lip root (a no-op
  // for the rest pose; belt-and-braces against sway pushing texels behind the rock).
  if (is_repl || is_fcard) {
    float dpl = dot(pos - base, inst_normal.xyz);
    if (dpl < 0.0) pos -= inst_normal.xyz * dpl;
  }

#ifdef OG_GRASS_CONTACT_PROBE
  probe_grass_world = vec4(pos, 1.0);
  probe_grass_pre = probe_grass_world;
  probe_grass_post = probe_grass_world;
#endif
  gl_Position = world_to_clip(pos);
}
