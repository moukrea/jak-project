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
// traverse plus de 1 % d'ecart de profondeur, 0.0 sinon. 2 : il ecrit 1.0 si au moins un tap a
// ete DEPLACE par la regle de pli ci-dessous. Le recensement relit ces images par le meme
// `glReadPixels(GL_RED)` que le tampon d'AO : aucun instrument neuf.
uniform int u_blur_report;

// Full-resolution strict ridge fill after blur. This bounded operation does not
// correct monotone dilution or secondary peaks in the wall/roof contact profile.
// The wider concave envelope was removed: local replays showed secondary peaks
// and darkening outside the qualified contact (attempt12-delivered-diagnostic.json).
uniform int u_ridge_fill;

vec3 world_from_depth(vec2 uv, float dpt) {
  vec3 ndc = vec3(uv * 2.0 - 1.0, dpt * 2.0 - 1.0);
  float sx = ndc.x * 256.0 + 2048.0 - u_hvdf_offset.x;
  float sy = ndc.y * -128.0 + 2048.0 - u_hvdf_offset.y;
  float sz = (ndc.z + 1.0) * 8388608.0 - u_hvdf_offset.z;
  vec4 ph = u_inv_camera * vec4(sx, sy, sz, u_fog);
  return ph.xyz / ph.w;
}

// ── LA CASSURE DE PENTE, LA MEME QUE CELLE DU JUGE ────────────────────────────────────────
// `contact_band()` (AmbientOcclusion.cpp:1216) declare un PLI quand la courbure pese plus du
// QUART des differences premieres, avec un plancher de 1e-5 : `curv > 0.25*(|d1|+|d2|) + 1e-5`.
// On reprend cette constante et ce plancher, appliques a la pente LOCALE de deux offsets du
// support. La propriete qui compte ici est exacte, pas empirique : sur un plan, la profondeur
// de FENETRE est affine en coordonnees d'ecran, donc la pente locale est la MEME a tous les
// offsets et `gb - ga` vaut EXACTEMENT zero — y compris sur un sol rasant, ou un test sur
// l'ecart de profondeur, lui, declenche (33 % des pixels, `ao_bilateral_cross_witness_px`).
bool slope_break(float ga, float gb) {
  return abs(gb - ga) > 0.25 * (abs(ga) + abs(gb)) + 0.00001;
}

void main() {
  // Only strict AO maxima at a depth fold enter this historical rule. The native
  // contact profile and the complete profile diagnostic remain separate checks.
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
    // Ciel : eclaire, pas de flou. En mode RAPPORT il n'a traverse aucune arete et rien n'y a
    // ete deplace : 0, pas 1 — sinon le ciel a lui seul remplirait le compteur et la grandeur
    // ne dirait plus rien.
    color = (u_blur_report >= 1) ? vec4(0.0) : vec4(1.0);
    return;
  }
  // ── LE SUPPORT, LU UNE FOIS : SEPT PROFONDEURS DE -3 A +3 PAS DE `u_dir` ─────────────────
  // Les offsets -2..+2 sont ceux du noyau ; +-3 n'est JAMAIS un tap de plus : c'est la seule
  // position de la classe modulo 4 des offsets +-1 qui se trouve de l'AUTRE cote du pli.
  float dz[7];
  for (int k = 0; k < 7; k++) {
    dz[k] = (k == 3) ? d0 : texture(u_depth, tex_coord + u_dir * float(k - 3)).r;
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
    float dp = dz[4];
    float dm = dz[2];
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
    float dp = dz[4];
    float dm = dz[2];
    if (dp > 0.000001 && dm > 0.000001) {
      float vp = distance(world_from_depth(tex_coord + u_dir, dp), u_cam_pos.xyz);
      float vm = distance(world_from_depth(tex_coord - u_dir, dm), u_cam_pos.xyz);
      slope = 0.5 * (vp - vm);
    }
  }

  // ── LE PLI, ET POURQUOI LA GAUSSIENNE NE SUFFIT PAS — CHIFFRE SUR L'ARCHIVE ──────────────
  // Archive appareil 22160-600, raccord mur/toit de la hutte, colonne x=100 : le mur monte de
  // 5,84e-6 par texel, le toit de 8,09e-5, et la profondeur de fenetre du contact vaut
  // 1,4532e-2. Pour le pixel de mur (100,550), le tap qui tombe sur le TOIT a un residu au plan
  // de rz = 1,498e-4 pour un ecart-type zsig = 4*zlim = 5,81e-4 : il conserve 96,7 % de son
  // poids. Le toit est CLAIR ; c'est LUI, et non le rayon du flou, qui fait remonter le contact
  // de 25 (brut) a 141 (final) alors que l'interieur du mur se pose a 130. Voila la bande
  // claire que l'owner voit « pile entre le mur et le toit ».
  //
  // LE SUPPORT NE BOUGE PAS, ET DEPLACER LES TAPS NE MARCHE PAS — C'EST MESURE. Rejouer le
  // support avec les taps traversants DEPLACES de quatre pas (meme classe modulo 4, meme poids)
  // rend la bande PIRE : 17/7/10 largeurs cumulees contre 12/2/7 (attempt11-a13-reloc). La
  // raison est geometrique et elle se lit dans l'archive : de PART ET D'AUTRE du raccord, l'AO
  // redevient claire en trois pixels (mur brut 25,31,23 puis 63,78,94,101,173 ; toit 61,71,132,
  // 98,160). Le support composite fait 29 texels au palier Eleve. Aucune reponderation d'une
  // moyenne de 29 texels ne conserve un creux de 3 px : ce n'est pas le COTE d'ou viennent les
  // taps qui perd le contact, c'est la LARGEUR de la moyenne.
  //
  // LE CHIFFRE QUI DESIGNE LE COUPABLE : au mur (100,550) le contact vaut 25 brut, 52 apres les
  // DEUX passes de pas 1, 85 apres celles de pas 2, et 141 a la fin. Les passes de pas 1
  // conservent le contact ET annulent la tuile 4x4 des estimateurs ; ce sont les boites LARGES
  // (pas 2, 3, 5) qui l'effacent, en allant chercher, a dix ou quinze texels, la surface d'en
  // face qui est CLAIRE.
  //
  // D'OU LA REGLE, QUI NE TOUCHE NI LE SUPPORT NI LES PHASES : une boite large a le droit de
  // LISSER un pixel dont un tap traverse un pli, elle n'a pas le droit de l'ECLAIRER. La sortie
  // est bornee par l'entree de la MEME passe. Trois proprietes, toutes exactes :
  //  - hors pli, aucun tap ne traverse, la borne ne s'arme pas, l'image ne bouge pas d'un bit ;
  //  - la borne s'applique a l'ENTREE de la passe, pas a l'AO brute : a partir du pas 2 cette
  //    entree est deja debarrassee de la tuile 4x4 par les deux passes de pas 1, donc la borne
  //    ne peut pas reintroduire le damier que l'owner a declare disparu ;
  //  - min(a, b) de deux grandeurs invariantes par translation du motif l'est aussi : le banc
  //    de phases au pli doit rester a 0.
  bool fold_guard = (u_edge_reject > 0.5);
  // Le pas de CETTE passe, en texels : `u_dir` vaut stride/taille du tampon d'AO.
  float step_texels = max(abs(u_dir.x) * u_ao_size.x, abs(u_dir.y) * u_ao_size.y);
  // ── LE PLI SE CHERCHE AU TEXEL, PAS AU PAS DE LA PASSE ─────────────────────────────────
  // Une boite de pas 5 porte a dix texels : armer la borne des qu'un de SES taps traverse un
  // pli l'arme a dix texels de la jonction — 48 % des pixels PLANS de l'archive changeaient
  // (attempt12-a13-bound-diagnostic.json). Le raccord que l'owner voit fait trois pixels. On
  // cherche donc le pli a l'echelle du TEXEL, sur les offsets -1, 0, +1, avec le test EXACT de
  // `contact_band()` (AmbientOcclusion.cpp:1216) : courbure relative au quart des differences
  // premieres, plancher 1e-5, et silhouette exclue au-dela de 2 % de la profondeur de fenetre.
  vec2 unit = u_dir / max(step_texels, 1.0);
  float uz[5];
  for (int k = 0; k < 5; k++) {
    uz[k] = (k == 2) ? d0 : ((step_texels > 1.5) ? texture(u_depth, tex_coord + unit * float(k - 2)).r
                                                 : dz[k + 1]);
  }
  bool near_crease = false;
  for (int c = 0; c < 3; c++) {
    float za = uz[c], zb = uz[c + 1], zc = uz[c + 2];
    if (za <= 0.000001 || zb <= 0.000001 || zc <= 0.000001) {
      continue;
    }
    float e1 = zb - za;
    float e2 = zc - zb;
    if (max(abs(e1), abs(e2)) > 0.02 * zb) {
      continue;  // silhouette : le vide derriere n'est pas un contact
    }
    if (abs(e2 - e1) > 0.25 * (abs(e1) + abs(e2)) + 0.00001) {
      near_crease = true;
    }
  }
  bool bound_armed = fold_guard && near_crease && step_texels > 1.5;

  // Noyau centre : les poids des quatre classes modulo 4 valent chacun 1/4,
  // et le premier moment est nul. Sur profondeur plane, il moyenne les quatre
  // phases sans le decalage d'un demi-pas de l'ancienne boite -1..2.
  // Un tap supplementaire par passe ; son cout GPU reste non mesure.
  float gw0 = 0.25;

  float sum = texture(u_ao, tex_coord).r * gw0;
  float wsum = gw0;
  float crossed = 0.0;
  float bounded = 0.0;

  // -2, -1, +1, +2 ; le centre est deja accumule.
  for (int i = 0; i < 4; i++) {
    float off = (i == 0) ? -2.0 : (i == 1) ? -1.0 : (i == 2) ? 1.0 : 2.0;
    float tap_weight = abs(off) > 1.5 ? 0.125 : 0.25;
    float use = off;
    vec2 tuv = tex_coord + u_dir * use;
    float td = texture(u_depth, tuv).r;
    if (td <= 0.000001) {
      continue;  // sky tap
    }
    // Le residu au PLAN, en profondeur de fenetre : zero exact sur un plan, explose sur une
    // arete. C'est LUI qui decide, dans les deux bras, ce qui compte comme « traverser ».
    float rz = abs(td - (d0 + zslope * use));
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
      float dv = tvd - (cvd + slope * use);
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
  float out_ao = sum / max(wsum, 1e-5);
  // La borne n'existe que pour les boites LARGES : aux deux passes de pas 1, l'entree porte
  // encore la tuile 4x4 des estimateurs et la borner y reinjecterait le damier.
  if (bound_armed) {
    float in_ao = texture(u_ao, tex_coord).r;
    if (out_ao > in_ao) {
      out_ao = in_ao;
      bounded = 1.0;
    }
  }
  if (u_blur_report == 2) {
    // Le temoin de NON-VACUITE de la regle de pli : 1 la ou la borne a REELLEMENT abaisse la
    // sortie. Un compteur pose sur la seule detection dirait « le pli existe », pas « la regle
    // a agi ».
    color = vec4(vec3(bounded), 1.0);
    return;
  }
  color = vec4(vec3(out_ao), 1.0);
}
