// Shared grass/shrub contact. Keep the literal-index Adreno unroll and grass law intact.
#include "grass_contact_dir.glsl"
uniform vec4  u_jak_ledge; // xyz = ledge-grab point, w = 1 while Jak hangs (ledge-parting trample)
uniform vec4 u_trample[16];
uniform int  u_trample_count;
uniform vec4 u_trample2[16];
// grass-interaction-direction (essai 4) — L'EMPREINTE DU CORPS DE JAK, PAS UN POINT.
// `u_jak_pos`, `u_jak_trail[4]` et `u_contact_dir` ont disparu : c'etaient UN POINT ET UN CAP, et
// l'owner l'a vu (20/09 : « pas vraiment correle au mesh du personnage […] ca prend pas en compte
// le mesh de Jak (ou ses collisions) »). Un point n'a ni pieds, ni bras, ni roue de spin.
// Ce que le vivier `GrassContactPrints.h` depose ici, c'est la trace au sol des SPHERES DE
// COLLISION que le jeu utilise deja pour Jak — corps, membres, et les trois volumes d'attaque du
// spin et du punch quand ils sont armes :
//   u_jak_print[i]  = (x, y, z au SOL, rayon d'empreinte)   rayon 0 = place morte
//   u_jak_printv[i] = (dir.x, dir.z, force du ressort, poids d'orientation)
// La force est un RESSORT AMORTI calcule cote CPU (zeta = 0,7, retour a 5 % en 0,9 s) : le saut,
// l'atterrissage et la marche passent tous par elle, donc il n'existe plus d'etat binaire a
// franchir. Le poids d'orientation vaut 0 aux paliers bas : le repli radial y est EXACT.
uniform vec4 u_jak_print[10];
uniform vec4 u_jak_printv[10];

// TRAMPLE_R reste : la prise de rebord (`u_jak_ledge`, acquis POLISH#4) s'en sert toujours. Les
// bornes d'altitude TRAMPLE_Y_* ont disparu avec le chemin point+cap : c'etaient elles qui
// coupaient le couchage d'un coup quand Jak depassait 2 m. Le vivier referme l'empreinte de facon
// continue par sqrt(r^2 - h^2), donc aucune bande d'altitude n'a plus a etre franchie.
const float TRAMPLE_R = 2.2 * 4096.0;

void vegetation_contact(vec3 base, float H, int u_debug,
                        out float heightMul, out vec3 trample, inout float dbg_tr) {
  // --- couchage : l'empreinte au sol du CORPS de Jak, place par place ---
  // MAX sur les places (jamais une somme) : deux empreintes qui se recouvrent ne peuvent pas
  // sur-appuyer. Deroulage a index LITTERAL (piege Adreno 618, SPEC section 0) — la boucle
  // `for (int ji ...)` de l'essai 3 lisait `u_jak_trail[ti]` a index CALCULE.
  heightMul = 1.0;
  trample = vec3(0.0);
  float bestk = 0.0;
  vec2  bestp = vec2(0.0, 1.0);
#define PR_STEP(i) { vec3 rk = grass_contact_print(base, u_jak_print[i].xyz, u_jak_print[i].w, \
    vec2(u_jak_printv[i].x, u_jak_printv[i].y), u_jak_printv[i].z, u_jak_printv[i].w); \
  if (rk.x > bestk) { bestk = rk.x; bestp = vec2(rk.y, rk.z); } }
  PR_STEP(0) PR_STEP(1) PR_STEP(2) PR_STEP(3) PR_STEP(4)
  PR_STEP(5) PR_STEP(6) PR_STEP(7) PR_STEP(8) PR_STEP(9)
#undef PR_STEP
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
