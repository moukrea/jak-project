#version 410 core

// Grecharged-ambient-occlusion: separable bilateral blur with a centered five-tap kernel.
// Offsets -2..2 use weights 1/8, 1/4, 1/4, 1/4, 1/8 before depth weighting.
// Sky taps are skipped; reconstruction matches the AO estimators.
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

// ── (h) LE REMPLISSAGE DE CRETE AU CONTACT ───────────────────────────────────────────────────
// Owner, 2026-09-13 : « aux contact on a comme une petite bande ou l'ao n'a pas d'effet, laissant
// une bande de quelques pixels eclairee sans AO, c'est distrayant ». Contrat (h) : « elle vaut 0
// ou est declaree et justifiee, jamais "quelques pixels" ». Livre au 14/09 : 850 texels de crete
// (temoin 4204). 0 = flou normal, comportement INCHANGE ; 1 = passe de crete, en pleine
// resolution, APRES le flou.
uniform int u_ridge_fill;

vec3 world_from_depth(vec2 uv, float dpt) {
  vec3 ndc = vec3(uv * 2.0 - 1.0, dpt * 2.0 - 1.0);
  float sx = ndc.x * 256.0 + 2048.0 - u_hvdf_offset.x;
  float sy = ndc.y * -128.0 + 2048.0 - u_hvdf_offset.y;
  float sz = (ndc.z + 1.0) * 8388608.0 - u_hvdf_offset.z;
  vec4 ph = u_inv_camera * vec4(sx, sy, sz, u_fog);
  return ph.xyz / ph.w;
}

void main() {
  // ── (h) LA PASSE DE CRETE : ELLE NE FLOUTE PAS, ELLE CREUSE LES MAXIMA LOCAUX D'UN PLI ─────
  // L'AO doit CREUSER au contact : la ou deux surfaces se replient l'une vers l'autre, l'horizon
  // se ferme et l'occlusion MONTE. Une CRETE — l'AO plus claire au pli qu'a ses deux voisins —
  // y est donc l'artefact que l'owner nomme, pas une nuance. Le test de pli est EXACTEMENT
  // celui de `contact_band()` (AmbientOcclusion.cpp) : la courbure de la profondeur de fenetre
  // pese plus du quart des differences premieres (le pli), et aucune des deux differences n'est
  // un SAUT au-dela de 2 % (sinon c'est une silhouette, ou l'AO a le DROIT de remonter parce
  // qu'il y a du vide derriere). Un voisin de ciel annule l'axe.
  // La passe ne touche QUE les maxima locaux STRICTS poses sur un pli, et ne peut qu'ABAISSER
  // (le resultat est un min) : elle ne sait donc ni eclaircir quoi que ce soit, ni assombrir une
  // surface continue (aucun pli), ni une silhouette (le saut l'exclut). Maximum strict SANS
  // marge : une crete de 3/255 passe sous les 4/255 de la mesure, la corriger quand meme est la
  // seule facon que la mesure ne soit pas ce qu'on optimise.
  if (u_ridge_fill == 1) {
    vec2 px = 1.0 / vec2(textureSize(u_ao, 0));
    float rd0 = texture(u_depth, tex_coord).r;
    float a0 = texture(u_ao, tex_coord).r;
    // ── LE SEUIL DE CIEL EST CELUI DU JUGE, PAS UN ARRONDI COMMODE ─────────────────────────
    // `contact_band()` ecarte le ciel a `z <= 1e-9`, soit MOINS d'un quantum de profondeur
    // 24 bits (5,96e-8). Ce shader ecartait a 1e-6, soit les 16 PREMIERS quanta : la bande
    // k appartenant a [1, 16] — l'horizon, la geometrie la plus LOINTAINE, convention PS2
    // inversee — etait du ciel pour le correcteur et de la surface pour la mesure. Le
    // correcteur ne couvrait donc pas tout ce que la porte compte. Meme constante des deux
    // cotes, et c'est le juge qui la donne.
    if (rd0 <= 1e-9) {
      color = vec4(vec3(a0), 1.0);  // ciel : recopie telle quelle
      return;
    }
    float filled = a0;
    for (int axis = 0; axis < 2; axis++) {
      vec2 st = (axis == 0) ? vec2(px.x, 0.0) : vec2(0.0, px.y);
      float zm = texture(u_depth, tex_coord - st).r;
      float zp = texture(u_depth, tex_coord + st).r;
      if (zm <= 1e-9 || zp <= 1e-9) {
        continue;  // voisin de ciel : cet axe ne dit rien — meme seuil que `contact_band()`
      }
      float rd1 = rd0 - zm;
      float rd2 = zp - rd0;
      float curv = abs(rd2 - rd1);
      float jump = max(abs(rd1), abs(rd2));
      if (jump > 0.02 * rd0) {
        continue;  // silhouette
      }
      if (curv <= 0.25 * (abs(rd1) + abs(rd2)) + 1e-5) {
        continue;  // pas un pli
      }
      float am = texture(u_ao, tex_coord - st).r;
      float ap = texture(u_ao, tex_coord + st).r;
      if (a0 > am && a0 > ap) {
        filled = min(filled, min(am, ap));  // le candidat de CET axe
      }
    }
    color = vec4(vec3(filled), 1.0);
    return;
  }

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

  // Locate a continuous concave fold inside THIS blur support. Four consecutive
  // depth texels define the two one-sided planes and their subpixel intersection.
  // The centre must belong to the receiving plane; distant surface changes cannot
  // supply a boundary. Limit normal diffusion by distance to that intersection.
  float stride = length(u_dir * u_depth_size);
  vec2 unit_dir = u_dir / max(stride, 1.0);
  float support = 2.0 * stride;
  float radius = support;
  float receiving_slope = zslope / max(stride, 1.0);
  if (u_edge_reject > 0.5) {
    for (int k = -10; k < 10; ++k) {
      if (float(k) < -support || float(k) >= support) continue;
      vec2 uv = tex_coord + float(k) * unit_dir;
      float za = texture(u_depth, uv - unit_dir).r;
      float zb = texture(u_depth, uv).r;
      float zc = texture(u_depth, uv + unit_dir).r;
      float zd = texture(u_depth, uv + 2.0 * unit_dir).r;
      float sm = zb - za;
      float sp = zd - zc;
      float bend = sp - sm;
      if (min(min(za, zb), min(zc, zd)) <= 1e-6 ||
          bend <= 0.25 * (abs(sm) + abs(sp)) + 1e-5 ||
          max(max(abs(sm), abs(sp)), abs(zc-zb)) > 0.02 * min(zb, zc)) continue;
      float t = (zb + sp - zc) / bend;
      if (t < 0.0 || t > 1.0) continue;
      float crease = float(k) + t;
      float plane_slope = crease > 0.0 ? sm : sp;
      float plane_centre = crease > 0.0 ? zb - sm * float(k)
                                       : zc - sp * float(k + 1);
      float tolerance = (abs(float(k)) + 3.0) / 16777215.0;
      if (abs(d0 - plane_centre) > tolerance) continue;
      if (abs(crease) < radius) {
        radius = abs(crease);
        receiving_slope = plane_slope;
      }
    }
  }

  // Noyau centre : les poids des quatre classes modulo 4 valent chacun 1/4,
  // et le premier moment est nul. Sur profondeur plane, il moyenne les quatre
  // phases sans le decalage d'un demi-pas de l'ancienne boite -1..2.
  // Un tap supplementaire par passe ; son cout GPU reste non mesure.
  float gw0 = 0.25;

  float sum = texture(u_ao, tex_coord).r * gw0;
  float wsum = gw0;
  float crossed = 0.0;

  // -2, -1, +1, +2 ; le centre est deja accumule.
  for (int i = 0; i < 4; i++) {
    float off = (i == 0) ? -2.0 : (i == 1) ? -1.0 : (i == 2) ? 1.0 : 2.0;
    float tap_weight = abs(off) > 1.5 ? 0.125 : 0.25;
    float sample_offset = off * stride * (radius / max(support, 1.0));
    vec2 tuv = tex_coord + unit_dir * sample_offset;
    float td = texture(u_depth, tuv).r;
    if (td <= 0.000001) {
      continue;  // sky tap
    }
    // Le residu au PLAN, en profondeur de fenetre : zero exact sur un plan, explose sur une
    // arete. C'est LUI qui decide, dans les deux bras, ce qui compte comme « traverser ».
    float predicted_depth = radius < support ? d0 + receiving_slope * sample_offset
                                              : d0 + zslope * off;
    float rz = abs(td - predicted_depth);
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
      w = tap_weight * exp(-(rz * rz) / (2.0 * zsig * zsig));
    } else {
      // Regime TEMOIN : la ponderation d'AVANT le 2026-09-14, une gaussienne sur l'ecart au
      // plan tangent en DISTANCE MONDE — qui, elle, n'est pas affine sur un plan.
      float tvd = distance(world_from_depth(tuv, td), u_cam_pos.xyz);
      float dv = tvd - (cvd + slope * off);
      w = tap_weight * exp(-(dv * dv) / (2.0 * sigma * sigma));
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
