#version 410 core

// Grecharged-ambient-occlusion: separable bilateral blur of the AO buffer. 4 taps at
// offsets -1..2 * u_dir, poids EGAUX 1/4 (boite exacte sur la tuile d'entrelacement 4x4 des
// estimateurs, voir plus bas), each tap additionally weighted
// by a depth-aware term exp(-(dv)^2 / (2 sigma^2)) so the blur does not bleed AO across
// depth discontinuities. Sky taps (depth ~= 0) are skipped. Reconstruction block matches
// the AO estimators. Procedural, no array uniforms.
precision highp float;

in vec2 tex_coord;
out vec4 color;

uniform highp sampler2D u_ao;
uniform highp sampler2D u_depth;

uniform mat4 u_camera;
uniform mat4 u_inv_camera;
uniform vec4 u_hvdf_offset;
uniform float u_fog;
uniform vec4 u_cam_pos;
uniform vec2 u_depth_size;
uniform vec2 u_ao_size;
uniform vec2 u_dir;  // (1/ao_w,0) or (0,1/ao_h)

// lighting-ao-indirect, verdict (l) du 2026-09-13 : « en Eleve l'AO est pleine resolution OU
// filtree par un flou bilateral QUI NE TRAVERSE PAS LES ARETES (compte de texels ou le filtre a
// melange deux profondeurs a plus de 1 % d'ecart = zero) ». Le poids gaussien seul
// (exp(-dv^2/2sigma^2), sigma ~= 0,5 m) ne s'annule JAMAIS : il traverse toute arete dont
// l'ecart reste de l'ordre du demi-metre, ce qui est exactement l'echelle d'un contact entre
// deux surfaces. `u_edge_reject` arme le rejet FRANC a 1 % de la distance camera ; le regime
// TEMOIN (0) restitue le comportement d'avant et sert a prouver que la mesure sait voir le
// defaut qu'elle declare absent.
uniform float u_edge_reject;   // 1 = rejet franc a 1 % arme ; 0 = temoin (gaussienne seule)
// Mode de MESURE. 0 : le flou ecrit l'AO. 1 : il ecrit 1.0 si au moins un tap ACCUMULE a
// traverse plus de 1 % d'ecart de profondeur, 0.0 sinon. Le recensement relit cette image par
// le meme `glReadPixels(GL_RED)` que le tampon d'AO : aucun instrument neuf.
uniform int u_blur_report;

vec3 world_from_depth(vec2 uv, float dpt) {
  vec3 ndc = vec3(uv * 2.0 - 1.0, dpt * 2.0 - 1.0);
  float sx = ndc.x * 256.0 + 2048.0 - u_hvdf_offset.x;
  float sy = ndc.y * -128.0 + 2048.0 - u_hvdf_offset.y;
  float sz = (ndc.z + 1.0) * 8388608.0 - u_hvdf_offset.z;
  vec4 ph = u_inv_camera * vec4(sx, sy, sz, u_fog);
  return ph.xyz / ph.w;
}

void main() {
  float d0 = texture(u_depth, tex_coord).r;
  if (d0 <= 0.000001) {
    // Ciel : eclaire, pas de flou. En mode RAPPORT il n'a traverse aucune arete : 0, pas 1 —
    // sinon le ciel a lui seul remplirait le compteur et la grandeur ne dirait plus rien.
    color = (u_blur_report == 1) ? vec4(0.0) : vec4(1.0);
    return;
  }
  float cvd = distance(world_from_depth(tex_coord, d0), u_cam_pos.xyz);
  const float sigma = 2048.0;  // ~0.5 m — regime TEMOIN seulement (voir plus bas)

  // ── LE PLAN SE LIT SUR LA PROFONDEUR DE FENETRE, PAS SUR LA DISTANCE CAMERA ───────────────
  // MESURE du 2026-09-14 : le rejet franc pose sur la DISTANCE CAMERA a fait passer
  // `ao_flatstep_worst_delivered_x1000` de 19 a 66 — il refermait la boite au MILIEU des
  // surfaces planes. La cause est exacte, pas empirique : sous une projection perspective, la
  // profondeur de FENETRE est une fonction AFFINE des coordonnees d'ecran sur tout plan, la
  // distance camera ne l'est PAS (elle va comme 1/z). Une prediction lineaire de la distance
  // extrapolee a quatre texels porte donc une erreur de courbure reelle sur un sol parfaitement
  // plat, et le rejet la prenait pour une arete. Sur la profondeur de fenetre, le residu d'une
  // prediction lineaire est EXACTEMENT nul sur un plan, a n'importe quel offset.
  // C'est la meme arithmetique que `flat_step` (AmbientOcclusion.cpp), qui juge cette passe.
  float zslope = 0.0;
  {
    float dp = texture(u_depth, tex_coord + u_dir).r;
    float dm = texture(u_depth, tex_coord - u_dir).r;
    if (dp > 0.000001 && dm > 0.000001) {
      zslope = 0.5 * (dp - dm);
    }
  }
  // Le seuil d'ARETE du verdict (l) : 1 % de la profondeur de fenetre du centre — c'est-a-dire,
  // la profondeur de fenetre allant comme 1/z, 1 % d'ecart RELATIF de distance. Un plancher
  // absolu au 1e-5 de `flat_step` : au loin la profondeur de fenetre tend vers 0 et un seuil
  // purement relatif rejetterait tout.
  float zlim = max(0.01 * d0, 0.00001);
  // NOTE : `zlim` sert DEUX choses — l'ecart-type de la ponderation, et le seuil au-dela duquel
  // un tap est declare « traversant » pour `ao_bilateral_cross_*`. Les deux disent la meme
  // chose : 1 % d'ecart de profondeur relative.

  // Le regime TEMOIN (u_edge_reject == 0) restitue la ponderation d'AVANT le 2026-09-14 : une
  // gaussienne sur l'ecart au plan tangent en DISTANCE MONDE, qui ne s'annule jamais. C'est lui
  // qui rend `ao_bilateral_cross_witness_px` non nul et donc le 0 d'a cote falsifiable.
  float slope = 0.0;
  if (u_edge_reject <= 0.5) {
    float dp = texture(u_depth, tex_coord + u_dir).r;
    float dm = texture(u_depth, tex_coord - u_dir).r;
    if (dp > 0.000001 && dm > 0.000001) {
      float vp = distance(world_from_depth(tex_coord + u_dir, dp), u_cam_pos.xyz);
      float vm = distance(world_from_depth(tex_coord - u_dir, dm), u_cam_pos.xyz);
      slope = 0.5 * (vp - vm);
    }
  }

  // lighting-ao-indirect, refus owner (a)/(e) du 2026-09-12 : BOITE EXACTE DE 4, pas une
  // gaussienne de 5. Les estimateurs tirent leur rotation d'une tuile d'ecran de 4x4 texels
  // portant 16 rotations distinctes (ao_ssao/hbao/gtao.frag). Quatre taps CONSECUTIFS a poids
  // EGAUX — offsets -1,0,+1,+2 — couvrent les quatre phases de la tuile dans cet axe ; H puis V
  // font donc la moyenne EXACTE des 16 rotations, et le motif s'ANNULE au lieu d'etre etale.
  // Une gaussienne (1,4,6,4,1)/16 en laisse un residu ~= 37 %.
  float gw0 = 0.25;
  float gw1 = 0.25;

  float sum = texture(u_ao, tex_coord).r * gw0;
  float wsum = gw0;
  float crossed = 0.0;

  // -1, +1, +2 taps (le +0 est le centre, deja pris)
  for (int i = 0; i < 3; i++) {
    float off = (i == 0) ? -1.0 : (i == 1) ? 1.0 : 2.0;
    vec2 tuv = tex_coord + u_dir * off;
    float td = texture(u_depth, tuv).r;
    if (td <= 0.000001) {
      continue;  // sky tap
    }
    // Le residu au PLAN, en profondeur de fenetre : zero exact sur un plan, explose sur une
    // arete. C'est LUI qui decide, dans les deux bras, ce qui compte comme « traverser ».
    float rz = abs(td - (d0 + zslope * off));
    bool over = rz > zlim;
    float w;
    if (u_edge_reject > 0.5) {
      // LE POIDS EST DOUX, PAS FRANC, ET C'EST UNE MESURE QUI L'A DECIDE. Le rejet franc a
      // `zlim` (essai du 2026-09-14) a fait passer `ao_flatstep_worst_delivered_x1000` de 19 a
      // 67 : sur un sol RASANT, la courbure de la profondeur de fenetre a quatre texels
      // d'ecart depasse le seuil sans qu'il y ait la moindre arete, la boite se refermait sur
      // son centre et l'AO ressortait BRUTE. Le temoin l'a chiffre : 33 % des pixels
      // pleine-resolution portaient au moins un tap au-dela de 1 % (`ao_bilateral_cross_*`).
      // La gaussienne d'ecart-type `zlim` garde l'arete — a trois seuils, le poids vaut 1 % —
      // et laisse passer la surface continue.
      // L'ECART-TYPE EST QUATRE FOIS LE SEUIL, ET C'EST UNE MESURE QUI L'A FIXE. A un
      // ecart-type de `zlim` exactement, `ao_flatstep_worst_delivered_x1000` tombait a 38 : la
      // surface CONTINUE mais rasante y perdait encore la moitie du poids de ses taps. A
      // quatre fois, un residu de courbure de l'ordre de `zlim` garde 97 % de son poids et la
      // boite reste pleine ; une vraie arete, dont le residu est d'un ordre de grandeur
      // au-dessus, tombe a moins de 1 %. Le SEUIL de `ao_bilateral_cross_*`, lui, reste a 1 % :
      // la mesure ne se deplace pas avec le reglage qu'elle juge.
      float zsig = 4.0 * zlim;
      w = gw1 * exp(-(rz * rz) / (2.0 * zsig * zsig));
    } else {
      // Regime TEMOIN : la ponderation d'AVANT le 2026-09-14, une gaussienne sur l'ecart au
      // plan tangent en DISTANCE MONDE — qui, elle, n'est pas affine sur un plan.
      float tvd = distance(world_from_depth(tuv, td), u_cam_pos.xyz);
      float dv = tvd - (cvd + slope * off);
      w = gw1 * exp(-(dv * dv) / (2.0 * sigma * sigma));
    }
    // Un tap dont le poids est numeriquement nul n'a rien melange : ne l'accuse pas.
    if (over && w > 0.0009765625) {  // 1/1024 : sous ce poids il ne pese pas un quantum R8
      crossed = 1.0;
    }
    sum += texture(u_ao, tuv).r * w;
    wsum += w;
  }

  if (u_blur_report == 1) {
    color = vec4(vec3(crossed), 1.0);
    return;
  }
  color = vec4(vec3(sum / max(wsum, 1e-5)), 1.0);
}
