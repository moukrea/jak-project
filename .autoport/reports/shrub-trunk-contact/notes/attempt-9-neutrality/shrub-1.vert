#version 300 es
#define OG_SHRUB_CONTACT_PROBE
precision highp float;
precision highp int;
precision highp sampler2D;

layout (location = 0) in vec3 position_in;
layout (location = 1) in vec3 tex_coord_in;
layout (location = 2) in vec3 rgba_base;
layout (location = 3) in int time_of_day_index;
// Grecharged-mesh-consolidation: shrub finally carries a real per-vertex smooth normal (2-10-10-10,
// same encoding tfrag/tie use). It used to have none, so shrub.frag synthesized one from
// screen-space derivatives = per-triangle flat. Bound by Shrub.cpp's VAO setup.
layout (location = 4) in vec4 shrub_normal;
// frame_ubo.glsl — LE BLOC D'IMAGE `ub_frame` (SPEC-refonte-lumiere §4.3, item
// lighting-ao-indirect). Inclus par les vertex ET fragment shaders des cinq hotes du decor
// (tfrag3, etie_base/etie, tie_wind, shrub, hfrag) et par les etages de tessellation, A LA PLACE
// des `uniform` de camera et de brouillard qu'ils declaraient : les noms sont les MEMES, le corps
// des shaders ne change pas. Miroir C++ : game/graphics/opengl_renderer/frame_ubo.cpp (224 o).
// Point de liaison 2, pose par Shader.cpp a l'edition de liens.
layout(std140) uniform ub_frame {
  mat4 pc_camera;
  mat4 camera;
  vec4 hvdf_offset;
  vec4 cam_trans;
  vec4 fog_color;
  float fog_constant;
  float fog_min;
  float fog_max;
  float u_frame_exposure;  // reserve (SPEC §4.5), 1.0
  vec4 u_frame_screen;     // w, h, 1/w, 1/h du FBO de rendu
  vec4 u_frame_misc;       // x = temps (s), y = palier, zw = 0
};

uniform int decal;
// foliage-wind (owner 2026-09-03) : la brise des buissons est le MEME chunk, la MEME loi et le MEME
// attribut 7 que le TIE statique (tie_sway.glsl). L'ancienne LUT par `color_index` (tex_T18) est
// retiree : elle supposait « une entree de palette par instance » et faisait glisser un buisson
// entier quand l'hypothese tombait. Le poids arrive tout cuit par sommet, ancre sur SON instance.
// Inerte (retourne son entree) quand u_tie_sway_amp vaut 0 : `first_tfrag_draw_setup` l'y met a
// chaque activation du programme, Shrub.cpp le releve juste apres si l'option est allumee.
// =================================================================================================
// foliage-wind (owner 2026-09-03) — LE BALANCEMENT DE LA VEGETATION STATIQUE : TIE **ET** SHRUB.
//
// QUATRE programmes dessinent de la vegetation statique et doivent bouger sous la MEME loi, sinon
// deux plantes voisines que l'oeil lit comme identiques divergent (« deux identiques côté à côte...
// un est pris l'autre non ») :
//   * tfrag3.vert    (TIE non-envmappe, Tie3.cpp)
//   * etie_base.vert (passe de base envmappee, Tie3.cpp)
//   * etie.vert      (passe additive de reflet, Tie3.cpp)
//   * shrub.vert     (buissons, Shrub.cpp)
// Le code vit ICI et une seule fois ; Shader.cpp le recopie verbatim chez les quatre. La loi
// TEMPORELLE elle-meme est dans breeze.glsl, jumelle ligne pour ligne de
// foliage_wind.cpp::breeze_offset (le chemin VENT du TIE, calcule sur CPU, l'emprunte aussi).
//
// LE PIEGE, ET C'EST LE VERROU (a) : `tfrag3.vert` est AUSSI le shader du terrain TFRAG. Un uniforme
// laisse a sa derniere valeur ferait ONDULER LE SOL. `first_tfrag_draw_setup` (background_common.cpp)
// ecrit donc `u_tie_sway_amp = 0` a CHAQUE activation de programme, pour TOUS les appelants, et seuls
// Tie3 et Shrub le relevent juste apres, sur leurs propres passes, via foliage_wind::push_uniforms.
// VERROU (b), independant : le VAO du TFRAG n'active pas les attributs 7/8/9, et
// `glVertexAttrib4f(7, 0, 0, 0, 1)` (et 8, 9) est pousse explicitement a cote de l'uniforme, donc le
// poids vaut 0 la ou aucun VBO de balancement n'est lie.
//
// L'ENREGISTREMENT DE BALANCEMENT (FoliageWindLaw.h : SwayRecord, 8 octets par sommet, derive au
// chargement par TFrag3Data.cpp de l'ancrage et de l'identite de CHAQUE INSTANCE) :
//   attribut 7  poids, GL_SHORT normalise -> [-1, 1], x TIE_SWAY_SCALE. 0 au tronc d'un arbre (30 %
//               du bas) et sur tout ce qui n'est pas vegetal ; LINEAIRE et SIGNE pour un buisson
//               (negatif sous le sol : le GPU interpole lineairement, donc la ligne de sol est
//               EXACTEMENT immobile). A la couronne il porte AUSSI le facteur de taille de la plante,
//               donc une seule amplitude sert a toutes les tailles.
//   attribut 8  phase, GL_UNSIGNED_BYTE normalise -> [0, 1) : constante sur toute la plante,
//               decorrelee d'une plante a l'autre.
//   attribut 9  (shrub seulement, lu par shrub.vert) index d'instance, entier.
// Ni l'un ni l'autre ne se calcule ici : la position varie a l'interieur de la plante (elle la
// dechirerait) et le shader ne sait pas ce qu'est un palmier.
// =================================================================================================
// foliage-wind (owner 2026-09-03 / 2026-09-04) — LA LOI DE BRISE. UNE SEULE, PARTAGEE PAR LES TROIS
// CHEMINS (TIE statique, TIE vent, shrub). Jumelle ligne pour ligne de
// game/graphics/opengl_renderer/background/foliage_wind.cpp::breeze_offset : toute constante changee
// ici l'est aussi la-bas, dans le meme ordre.
//
// CE QUE L'OWNER A REFUSE, DANS L'ORDRE, ET CE QUE CETTE LOI EN FAIT :
//   * 2026-09-03 « une ondulation bizarre comme si c'était pour simuler une distorsion visuelle sous
//     l'eau » : c'etait une onde de 30 cm qui traversait le maillage (phase spatiale a l'echelle du
//     sommet). REGLE (1) : AUCUNE phase spatiale sous l'echelle de la plante. La seule variation
//     spatiale est le FRONT DE RAFALE, de longueur d'onde 120 m ; une plante plie d'un bloc, deux
//     voisines a 3 m plient ensemble.
//   * 2026-09-04 « un mouvement très binaire, juste un tilt, aucune variation, aucune ondulation » :
//     c'etait une flexion toujours sous le vent dont seule l'intensite respirait. REGLE (2) : la
//     couronne OSCILLE autour de sa flexion moyenne (trois composantes de balancement, 0,35 / 0,56 /
//     0,77 Hz, incommensurables, modulees par la rafale) — c'est le retour elastique d'un arbre apres
//     une bouffee, pas un pendule a frequence fixe. REGLE (3) : l'enveloppe est une RAFALE, somme de
//     cinq composantes lentes incommensurables (0,040 a 0,25 Hz) redressee et biaisee vers le calme,
//     donc de vraies accalmies et de vraies bouffees (coefficient de variation de l'enveloppe ~0,5).
//   * 2026-09-04 « ça twitch autant côté feuilles que le tronc » : ce n'est pas cette loi, c'est le
//     POIDS de hauteur (FoliageWindLaw.h : tronc rigide) et, pour les palmiers du chemin vent, le
//     passage de la flexion ajoutee du cisaillement de matrice au sommet-shader (tie_wind.vert).
//   * REGLE (4) : STRICTEMENT HORIZONTAL. Aucune composante verticale : une plante ne flotte pas.
//   * REGLE (5) : LES FEUILLES NE FREMISSENT QUE DANS LA RAFALE (1,40 et 2,13 Hz, gain x enveloppe).
//   * 2026-09-06 « ça doit varier en amplitude, distorsion, direction » : l'amplitude variait
//     (`wind_envelope_cv` = 0,48), la direction NON — le cap moyen etait fige et `cross` ne lui
//     ajoutait qu'un tremblement rapide. REGLE (6) : LE CAP LUI-MEME TOURNE, par trois composantes
//     lentes incommensurables (0,0146 / 0,0250 / 0,0388 Hz), +/- 0,66 rad = 37 deg au plus. C'est
//     une saute de vent, pas une girouette : la plus rapide met 26 s a faire un aller-retour.
//     MESURE (verdict 9, `wind_dir_variation_deg`) : le cap du deplacement LISSE sur 2 s — le
//     lissage efface le balancement (>= 2,2 Hz) et le fremissement (>= 8,8 Hz) et ne garde que la
//     flexion moyenne. Sans lui la mesure serait VIDE : |o| passe par zero a chaque accalmie et le
//     cap instantane fait un tour complet, ce qui rend 128 deg avec un cap PARFAITEMENT fige.
//     Avec le lissage, la loi SANS lacet rend 18 deg (rouge) et avec 56 deg (vert) : la porte
//     separe bien les deux lois.
//
// SPECTRE (Hz) du deplacement d'un sommet de couronne, mesure par le moteur (`wind_spectrum_peak_pct`,
// FFT sur la course) : rafale 0,040 0,065 0,105 0,160 0,250 — balancement 0,350 0,5625 0,770 —
// lateral 0,44 0,22 — feuilles 1,40 2,13, plus les intermodulations. Aucune raie ne porte plus de
// ~27 % de l'energie hors continu (conception : 24-27 % selon la phase ; porte a 40 %).
//
// UNITES. Tout est en unites monde GOAL (4096 = 1 m). `t` est en secondes.
// =================================================================================================

// Le front de rafale : 2*pi / (120 m * 4096) — 120 m est LA constante qui interdit l'ondulation.
#define BREEZE_GUST_K 1.27828e-5

// Le moteur de brise. `wpos` : position monde (celle de la plante, ou celle du sommet — a 120 m
// de longueur d'onde les deux donnent la meme rafale). `dir` : cap du vent, normalise (x, z).
// `ph01` : phase propre a la plante, dans [0, 1), CONSTANTE sur toute la plante.
// Renvoie : .x = flexion sous le vent (~[-0.03, 1.15], moyenne ~0.24), .y = derive laterale (signee),
//           .z = gain de fremissement de feuille, dans [0.34, 1.0].
vec3 breeze_drive(vec3 wpos, vec2 dir, float ph01, float t) {
  float travel = dot(wpos.xz, dir) * BREEZE_GUST_K;
  float pp = ph01 * 6.2831853;
  // la rafale : cinq composantes lentes incommensurables, poids decroissants mais VOISINS (aucune
  // ne domine), sommees dans [-1, 1]
  float g = 0.30 * sin(t * 0.2513 - travel + pp * 0.31)
          + 0.27 * sin(t * 0.4084 - travel * 1.73 + pp * 0.77 + 1.7)
          + 0.22 * sin(t * 0.6597 - travel * 2.91 + pp * 0.29 + 4.1)
          + 0.13 * sin(t * 1.0053 - travel * 1.31 + pp * 1.13 + 2.6)
          + 0.08 * sin(t * 1.5708 + pp * 0.53 + 0.9);
  // redressee et biaisee vers le calme : l'exposant 1.6 fait passer plus de temps en bas qu'en haut
  float gust = 0.12 + 0.88 * pow(clamp(0.5 + 0.5 * g, 0.0, 1.0), 1.6);
  // le balancement : flexion moyenne + retour elastique a trois composantes, le tout module par la
  // rafale (dans le calme la couronne se pose ; dans la bouffee elle plie ET oscille)
  float sway = 0.55 + 0.30 * sin(t * 2.1991 + pp * 1.19 + travel * 0.6)
                    + 0.18 * sin(t * 3.5343 + pp * 2.03 + 1.1)
                    + 0.10 * sin(t * 4.8381 + pp * 0.71 + 2.9);
  float along = gust * sway;
  float cross = gust * (0.22 * sin(t * 2.7646 + pp * 1.61 + 2.3) + 0.10 * sin(t * 1.3823 + pp * 0.4));
  return vec3(along, cross, 0.25 + 0.75 * gust);
}

// LE LACET — regle (6). L'angle dont le cap du vent a tourne a cet instant, en radians. Trois
// composantes lentes incommensurables, la plus grande a 0,0146 Hz (68 s de periode) : une saute de
// vent. `travel` n'entre que dans la deuxieme, pour que deux clairieres distantes ne virent pas
// exactement ensemble sans pour autant qu'une plante et sa voisine divergent (120 m de longueur
// d'onde, regle (1)). Amplitude totale bornee a 0,66 rad = 37,8 deg.
float breeze_yaw(float travel, float pp, float t) {
  return 0.34 * sin(t * 0.0917 + pp * 0.23 + 0.7)
       + 0.21 * sin(t * 0.1571 - travel * 0.7 + pp * 0.61 + 2.2)
       + 0.11 * sin(t * 0.2437 + pp * 1.07 + 4.4);
}

// Le deplacement HORIZONTAL d'un sommet, en unites monde.
//   `w`          : poids de balancement du sommet — 0 au pied de SA plante, 1 a sa couronne. Il
//                  porte AUSSI le facteur de taille de la plante (FoliageWindLaw.h) : c'est pour
//                  cela qu'une seule amplitude `bend_u` sert a toutes les tailles. Peut etre NEGATIF
//                  (partie enfoncee d'un buisson) : la loi est alors lineaire a travers le sol.
//   `bend_u`     : flexion de couronne d'une plante de reference (>= 8 m), en unites monde.
//   `flutter_f`  : fraction de `bend_u` reservee au fremissement de feuille.
// La phase du fremissement ne varie qu'avec `w` — donc avec la hauteur du sommet DANS SA PLANTE.
// Jamais avec sa position monde : c'est la regle (1) ci-dessus, et c'est tout le defaut.
vec2 breeze_offset(vec3 wpos, vec2 dir, float ph01, float t, float w, float bend_u,
                   float flutter_f) {
  vec3 d = breeze_drive(wpos, dir, ph01, t);
  // regle (6) : le cap du vent a CET instant, pas celui de la course
  float travel = dot(wpos.xz, dir) * BREEZE_GUST_K;
  float ya = breeze_yaw(travel, ph01 * 6.2831853, t);
  float cy = cos(ya), sy = sin(ya);
  vec2 wdir = vec2(dir.x * cy - dir.y * sy, dir.x * sy + dir.y * cy);
  vec2 perp = vec2(-wdir.y, wdir.x);
  vec2 o = (wdir * d.x + perp * d.y) * (bend_u * w);
  float lf1 = sin(t * 8.7965 + ph01 * 12.566 + w * 2.9);
  float lf2 = sin(t * 13.4035 + ph01 * 7.3 + w * 4.1 + 1.3);
  o += (wdir * (0.62 * lf1 + 0.38 * lf2) + perp * (lf2 * 0.45)) * (bend_u * w * flutter_f * d.z);
  return o;
}

layout (location = 7) in float tie_sway_w_in;
layout (location = 8) in float tie_sway_ph_in;

// = foliage_law::kSwayScale
#define TIE_SWAY_SCALE 4.0
// (poids, phase) tels que les quatre programmes les consomment
#define tie_sway_in vec2(tie_sway_w_in * TIE_SWAY_SCALE, tie_sway_ph_in)

uniform float u_tie_sway_amp;      // flexion de couronne d'une plante de reference (>= 8 m), unites
                                   // monde (4096 = 1 m) ; 0 = ETEINT, le bloc est saute
uniform float u_tie_sway_time;     // secondes, horloge de brise (figee en pause)
uniform vec2  u_tie_sway_dir;      // cap du vent, normalise (x, z)
uniform float u_tie_sway_flutter;  // part de l'amplitude reservee au fremissement de feuille

vec3 tie_sway_apply(vec3 wpos, vec2 sw) {
  if (u_tie_sway_amp <= 0.0 || sw.x == 0.0) {
    return wpos;
  }
  vec2 o = breeze_offset(wpos, u_tie_sway_dir, sw.y, u_tie_sway_time, sw.x, u_tie_sway_amp,
                         u_tie_sway_flutter);
  // HORIZONTAL uniquement : pas de composante verticale, une plante ne s'enfonce pas dans le sol.
  wpos.x += o.x;
  wpos.z += o.y;
  return wpos;
}

#ifdef TIE_CONTACT
// Shared grass/shrub contact. Keep the literal-index Adreno unroll and grass law intact.
uniform vec4  u_jak_pos;   // xyz = Jak world pos, w = 1 when valid (trample origin)
uniform vec4  u_jak_ledge; // xyz = ledge-grab point, w = 1 while Jak hangs (ledge-parting trample)
uniform vec4 u_trample[16];
uniform int  u_trample_count;
uniform float u_trample_str[16];  // LEGACY (Adreno miscompiles dynamic float-array reads -> 0)
uniform vec4 u_trample2[16];
uniform vec4 u_jak_trail[4];

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
  TR_STEP(8) TR_STEP(9) TR_STEP(10) TR_STEP(11) TR_STEP(12) TR_STEP(13) TR_STEP(14) TR_STEP(15)
#undef TR_STEP

}

layout (location = 10) in uint tie_contact_index;
uniform int u_tie_contact_on;
uniform sampler2D u_tie_contact_tex;
vec3 tie_contact_apply(vec3 original, vec3 bent) {
  if (u_tie_contact_on == 1 && tie_contact_index != 0u) {
    vec4 anchor = texelFetch(u_tie_contact_tex, ivec2(int(tie_contact_index), 0), 0);
    if (anchor.w > 0.0) {
      float heightMul;
      vec3 trample;
      float debug_contact = 0.0;
      vegetation_contact(anchor.xyz, anchor.w, 0, heightMul, trample, debug_contact);
      float dy = original.y - anchor.y;
      bent.y += dy * (heightMul - 1.0);
      bent += trample * (dy / anchor.w);
    }
  }
  return bent;
}
#endif

// Shared grass/shrub contact. Keep the literal-index Adreno unroll and grass law intact.
uniform vec4  u_jak_pos;   // xyz = Jak world pos, w = 1 when valid (trample origin)
uniform vec4  u_jak_ledge; // xyz = ledge-grab point, w = 1 while Jak hangs (ledge-parting trample)
uniform vec4 u_trample[16];
uniform int  u_trample_count;
uniform float u_trample_str[16];  // LEGACY (Adreno miscompiles dynamic float-array reads -> 0)
uniform vec4 u_trample2[16];
uniform vec4 u_jak_trail[4];

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
  TR_STEP(8) TR_STEP(9) TR_STEP(10) TR_STEP(11) TR_STEP(12) TR_STEP(13) TR_STEP(14) TR_STEP(15)
#undef TR_STEP

}

uniform int u_shrub_contact_on;
// foliage-wind (essai 11) — LE VENT NATIF DES BUISSONS, celui de ND (owner 2026-09-03 : « avec
// l'option off on devrait avoir le natif d'origine »). Sur PS2, chaque instance-shrubbery integre
// le meme ressort que le TIE et l'applique en CISAILLEMENT de sa matrice (shrub_asm.md:957-1057) ;
// le port PC l'avait perdu. Shrub.cpp integre le ressort par instance sur CPU (do_wind_math, raideur
// du prototype attenuee par la distance, comme l'EE) et depose par instance un texel
// (s.x, s.z, k, 1) dans tex_T18 ; ici le deplacement vaut `s * (y - pivot)`, ou `(y - pivot)` est
// relu de l'attribut 7 : `w = (y - pivot) / span * taille`, donc `(y - pivot) = w * k` avec
// `k = span / taille`. Lineaire et signe autour du MEME pivot que la brise ajoutee (le sol trouve
// sous le buisson) : la ligne de sol reste exactement immobile pour les deux termes.
// Independant de l'option Recharged : c'est du stock restaure. u_shrub_native_on = 0 => rien.
layout (location = 9) in int shrub_inst_in;
uniform sampler2D tex_T18;
uniform int u_shrub_native_on;
// Wx2 2D LUT (native spring row 0, immutable contact anchor row 1) instead of 1D — GLES has no sampler1D/glTexImage1D (the arm64
// device BLR'd into the NULL glTexImage1D loader slot). texelFetch on a Wx1
// sampler2D is texel-exact on desktop GL too; Shrub.cpp uploads it as a Wx1
// GL_TEXTURE_2D. Matches tfrag3.vert/the TIE shaders.
uniform sampler2D tex_T10; // note, sampled in the vertex shader on purpose.
  // Grecharged-lightprobes PLAYTEST#1 #4: probe SH now evaluated PER-PIXEL in the fragment (see .frag).

out vec4 fragment_color;
out vec3 tex_coord;
out float fogginess;
#ifdef OG_PBR
out vec3 v_fringe_rel;
// Grecharged-mesh-consolidation: the real smooth normal, handed to the fragment stage.
out vec3 v_normal;
// Grecharged-lightprobes: absolute world position (GOAL game units) for probe lookup.
out vec3 v_world;
// REOPEN 2026-07-21: raw stored TOD LUT units (pre x4 / pre rgba_base) for the baked-detail ratio.
out vec3 v_todc;
#endif


#ifdef OG_SHRUB_CONTACT_PROBE
out vec3 probe_pre_contact;
out vec3 probe_post_contact;
flat out uint probe_vertex_index;
#endif

void main() {
  // old system:
  // - load vf12
  // - itof0 vf12
  // - multiply with camera matrix (add trans)
  // - let Q = fogx / vf12.w
  // - xyz *= Q
  // - xyzw += hvdf_offset
  // - clip w.
  // - ftoi4 vf12
  // use in gs.
  // gs is 12.4 fixed point, set up with 2048.0 as the center.

  // the itof0 is done in the preprocessing step.  now we have floats.
  
  // Step 3, the camera transform
  // foliage-wind : balancement par la loi partagee ; inerte quand u_tie_sway_amp vaut 0.
  vec3 wpos = tie_sway_apply(position_in, tie_sway_in);
  if (u_shrub_native_on == 1 && tie_sway_in.x != 0.0) {
    vec4 nw = texelFetch(tex_T18, ivec2(shrub_inst_in, 0), 0);
    wpos.x += nw.x * (nw.z * tie_sway_in.x);
    wpos.z += nw.y * (nw.z * tie_sway_in.x);
  }
#ifdef OG_SHRUB_CONTACT_PROBE
 probe_pre_contact = wpos; probe_vertex_index = uint(gl_VertexID);
#endif
  if (u_shrub_contact_on == 1) {
    vec4 anchor = texelFetch(tex_T18, ivec2(shrub_inst_in, 1), 0);
    if (anchor.w > 0.0) {
      float heightMul;
      vec3 trample;
      float debug_contact = 0.0;
      vegetation_contact(anchor.xyz, anchor.w, 0, heightMul, trample, debug_contact);
      // Signed linear displacement: an edge crossing the buried pivot interpolates to zero.
      float dy = position_in.y - anchor.y;
      wpos.y += dy * (heightMul - 1.0);
      wpos += trample * (dy / anchor.w);
    }
  }
#ifdef OG_SHRUB_CONTACT_PROBE
 probe_post_contact = wpos;
#endif
  vec3 vert = wpos - cam_trans.xyz;
#ifdef OG_PBR
  v_fringe_rel = vert * (1.0 / 4096.0);
  v_normal = shrub_normal.xyz;           // Grecharged-mesh-consolidation: real per-vertex smooth normal
  v_world = position_in;                 // Grecharged-lightprobes: world pos for PER-PIXEL probe lookup
#endif
  vec4 transformed = -pc_camera[3];
  transformed -= pc_camera[0] * vert.x;
  transformed -= pc_camera[1] * vert.y;
  transformed -= pc_camera[2] * vert.z;

  // do fog!
  fogginess = 255.0 - clamp(-transformed.w + hvdf_offset.w, fog_min, fog_max);

  // scissoring area adjust
  transformed.y *= (512.0 / 448.0) * 1.0;
  gl_Position = transformed;

  // time of day lookup
  // start with the vertex color (only rgb, VIF filled in the 255.)
  fragment_color =  vec4(rgba_base, 1);
  // get the time of day multiplier
  vec4 tod_color = texelFetch(tex_T10, ivec2(time_of_day_index, 0), 0);
#ifdef OG_PBR
  v_todc = tod_color.rgb;  // raw stored LUT units (pre x4/pre rgba_base) for the baked-detail ratio
#endif
  // combine
  fragment_color *= tod_color * 4.0;

  if (decal == 1) {
    fragment_color.xyz = vec3(1.0, 1.0, 1.0);
  }

  tex_coord = tex_coord_in;
  tex_coord.xy /= 4096.0;
}
