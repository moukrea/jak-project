// Shared grass/shrub contact. Keep the literal-index Adreno unroll and grass law intact.
#include "grass_contact_dir.glsl"
uniform vec4  u_jak_pos;   // xyz = Jak world pos, w = 1 when valid (trample origin)
uniform vec4  u_jak_ledge; // xyz = ledge-grab point, w = 1 while Jak hangs (ledge-parting trample)
uniform vec4 u_trample[16];
uniform int  u_trample_count;
uniform float u_trample_str[16];  // LEGACY (Adreno miscompiles dynamic float-array reads -> 0)
uniform vec4 u_trample2[16];
uniform vec4 u_jak_trail[4];
// grass-interaction-direction : le cap du pas. xy = direction unitaire XZ, z = force 0..1,
// w = 1 quand la loi orientee est armee (palier >= medium et item arme), 0 = repli radial.
// vec4 et NON un tableau : les tableaux de float rendent -1 en localisation sur Adreno 618.
uniform vec4 u_contact_dir;

const float TRAMPLE_R = 2.2 * 4096.0; // grass flattens within this radius of Jak
// OWNER POLISH#3: only trample when Jak is near THIS grass's ground height — not
// airborne. vgap = Jak-root-Y minus blade-base-Y; outside this band => no trample.
const float TRAMPLE_Y_LO = -1.5 * 4096.0; // up to 1.5 m below the grass -> still trample
const float TRAMPLE_Y_HI =  2.0 * 4096.0; // more than 2 m above the grass = airborne -> none
// OWNER ROUND#21: the altitude gate is now a smooth FADE band (1.2 m -> 2.0 m) instead of a hard
// cutoff at 2.0 m — crossing it during a jump used to zero the whole trample in one frame (the
// "instantanément droite" snap). Walking keeps vgap well under the band start -> unchanged.
const float TRAMPLE_Y_EASE = 1.2 * 4096.0;

void vegetation_contact(vec3 base, float H, int u_debug,
                        out float heightMul, out vec3 trample, inout float dbg_tr) {
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
  heightMul = 1.0;
  trample = vec3(0.0);
  float bestk = 0.0;
  vec2  bestp = vec2(0.0, 1.0);
  // grass-interaction-direction : la boucle `for (int ji = 0; ji < 5; ++ji)` d'avant lisait
  // `u_jak_trail[ti]` a index CALCULE. Le commentaire de `grass.vert:282` tenait les petits
  // tableaux [4] pour surs sur l'Adreno 618, mais rien ne le MESURAIT : c'etait la derniere
  // lecture a index non litteral du chemin herbe. Deroulage a index litteral, comme TR_STEP et
  // OC_STEP — et la porte de l'item compte desormais ces lectures, sur l'appareil.
#define JK_STEP(J) { vec4 Jv = (J); float jstr = min(Jv.w, 1.0); float jgap = Jv.y - base.y; \
  if (jstr > 0.004 && jgap > TRAMPLE_Y_LO && jgap < TRAMPLE_Y_HI) { \
    float afade = 1.0 - smoothstep(TRAMPLE_Y_EASE, TRAMPLE_Y_HI, jgap); \
    vec3 rk = grass_contact_dir(base.xz - Jv.xz, vec2(u_contact_dir.x, u_contact_dir.y), \
                                u_contact_dir.z * u_contact_dir.w, TRAMPLE_R, afade * jstr); \
    if (rk.x > bestk) { bestk = rk.x; bestp = vec2(rk.y, rk.z); } } }
  JK_STEP(u_jak_pos)
  JK_STEP(u_jak_trail[0]) JK_STEP(u_jak_trail[1])
  JK_STEP(u_jak_trail[2]) JK_STEP(u_jak_trail[3])
#undef JK_STEP
  if (bestk > 0.0) {
    trample = vec3(bestp.x, 0.0, bestp.y) * (bestk * bestk) * H * 1.3;
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
  TR_STEP(8) TR_STEP(9) TR_STEP(10) TR_STEP(11) TR_STEP(12) TR_STEP(13) TR_STEP(14) TR_STEP(15)
#undef TR_STEP

}
