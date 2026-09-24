// shade.glsl — LE MODELE D'OMBRAGE DU DECOR, EN UN SEUL TEXTE.
//
// POURQUOI CE FICHIER. SPEC-refonte-lumiere.md §2.3 : le decor n'avait pas un modele
// d'eclairage, il en avait cinq, ecrits en quatre quasi-copies (tfrag3, etie_base, tie_wind,
// shrub). Toucher a un chemin cassait silencieusement l'A/B des autres — la mecanique qui a
// produit 25 rounds non acceptes. Ici il y a UN texte, inclus par les hotes.
//
// LE CONTRAT (SPEC §4.2). Un renderer REMPLIT `Surface` et APPELLE `shade()`. Il ne decide plus
// d'aucun composite. Ce qui reste chez l'hote est ce qui n'est PAS de l'eclairage :
//   * la lecture de sa texture et sa couleur de base,
//   * la construction de sa normale — c'est de la GEOMETRIE, et elle differe reellement d'un
//     hote a l'autre (shrub n'a pas de tangente et ne declare pas `u_rt_flat_normal`),
//   * son alpha, son brouillard, son fondu de frange, ses etiquettes de debug.
//
// CE QUI N'A PAS BOUGE, ET POURQUOI C'EST LA CONDITION DE SORTIE. Ce fichier est un
// DEPLACEMENT de texte, pas une reecriture : les expressions viennent de tfrag3.frag mot pour
// mot. Les deux endroits ou les hotes divergeaient VRAIMENT sont devenus des ENTREES
// (`Surface.shadow_N` / `Surface.shadow_ndl`, `Surface.N`), pas des branches — sans quoi la
// fusion aurait deplace les ombres de TIE et des arbustes.
//
// CE QUI A ETE RETIRE, ET IL FAUT LE DIRE. lighting-legacy-purge (2026-09-12) : ce fichier ne
// porte plus qu'UN composite, la modulation du cuit par le soleil temps reel et ses ombres
// portees. Les deux composites reserves a tfrag3 (l'ombrage de materiaux autonome et le relight
// des receveurs d'origine) ont ete SUPPRIMES, mesure a l'appui : la course x86 du 2026-09-12,
// regime epingle RECHARGED+LIGHTING+RT_LIGHT, 16 981 images, les compte a ZERO draw chacun sur
// 7 139 444 draws monde. Les retirer n'ote donc aucun pixel a l'image. La pile de materiaux
// fusionnee, elle, TOURNAIT (374 818 draws) : sa suppression change le decor sous eclairage
// recharge, et c'est voulu — l'owner l'a demandee pour qu'elle soit refaite.
//
// LA MESURE. Les deux marqueurs ci-dessous delimitent la region que
// game/graphics/opengl_renderer/shade_proof.cpp empreinte DANS LE TEXTE QUE LE PILOTE COMPILE.
// Tant que chaque hote portait sa copie, les empreintes differaient : `shade_variants` valait 4
// (mesure du 2026-09-06, 5 programmes monde). Ici il n'y en a qu'une, donc 1.

// ================= @shade-model-begin =================
// ── LES UNIFORMES QUI SURVIVENT AU RETRAIT DE LA PILE DE MATIERE ────────────────────────────
// lighting-legacy-purge (2026-09-12). Les trois fichiers d'inclusion de l'ancien modele de
// materiaux ont QUITTE L'ARBRE : plus de micro-facettes, plus de cartes de relief / rugosite /
// metal / occlusion / specular / emissif, plus de parallaxe, plus d'ambiante analytique, plus de
// presets ni de bisection. L'owner a tranche : « on en veut plus, ca va etre refait, mieux ».
// Ce qui suit vivait dans le fichier d'uniformes supprime et est recopie ici mot pour mot.
// POURQUOI CES NOMS GARDENT UN PREFIXE « pbr » : ce sont LES OMBRES PORTEES. Le prefixe est un
// accident d'histoire, pas une appartenance — leur unique consommateur est le bras
// `u_rt_light_on != 0` ci-dessous, c'est-a-dire le chemin UNIQUE de la refonte, et leur item de
// suite est `lighting-shadows`. Les renommer est un geste a part, qui touche aussi le C++.
// Round-4 mandate B: classic sun SHADOW MAPPING. u_pbr_shadow_mvp maps camera-relative
// meters (== v_fringe_rel) to the light's clip space; tex_PBR_SHADOW is the depth-only sun
// map on unit 9, sampled as a HW-PCF compare sampler (LEQUAL). u_pbr_shadow_on gates it.
// lighting-shadows (SPEC §4.8) : ATLAS D'OMBRE TUILE. Remplace l'unique `u_pbr_shadow_mvp` par
// 4 matrices de tuile — les cascades de l'astre DOMINANT (0..cascades-1) et la tuile 3 pour le
// SECOND astre. Deux astres, deux ombres, aucun fondu ni attribution.
uniform mat4 u_shadow_tile_mvp[4];
uniform int u_shadow_tiles;    // bit t = tuile t active cette image (cote LECTURE)
uniform vec4 u_shadow_split;   // demi-etendues des cascades 0..2 (m), w = nombre de cascades
uniform vec4 u_shadow_texel;   // metres par texel, par tuile
uniform float u_shadow_tile_px;
uniform int u_shadow_key;      // 0 : le soleil porte les cascades, 1 : la lune verte
uniform int u_shadow_proof;
uniform sampler2D tex_SHADOW_ACTOR;
uniform int u_pbr_shadow_on;
// Round-5 suspect (d): the read-side map is anchored to the camera position of the frame
// that WROTE it (camera-relative space), but v_fringe_rel uses the CURRENT camera —
// without correction every shadow trails camera motion by one frame (continuous
// displacement during the owner's orbit repro). cam_delta = (cam_now - cam_at_write)/4096.
uniform vec3 u_pbr_shadow_cam_delta;
// Plain sampler2D + manual in-shader compare: the Adreno 618 HW compare path
// (sampler2DShadow + COMPARE_REF_TO_TEXTURE) returns a constant 1.0 on-device
// (proven with a 0.25-cleared map). Depth-as-float sampling is portable.
uniform highp sampler2D tex_PBR_SHADOW;
// Debug-only bias override added to the compare ref (prop debug.opengoal.pbr.shadowbias /
// OG_PBR_SHADOWBIAS, default 0.0 = no effect). +0.5 must black out every in-box receiver
// if the HW depth compare works — the Adreno-driver binary test.
uniform float u_pbr_shadow_bias;
// Visualisation de mise au point, sans effet sur le rendu livre (0 = rendu normal). Les modes
// qui peignaient les canaux de la pile de matiere sont partis avec elle ; restent les vues du
// chemin survivant (N.L, normale d'ombrage, facteur de modulation, facteur d'ombre portee) et
// l'etiquette de programme qui dit QUEL programme a dessine le pixel.
uniform int u_pbr_debug;

// Grecharged-realtime-lighting (2026-07-19 REWRITE): a clean SUN-ONLY path that
// REPLACES the round-1..5 accretion (ambient / multi-light / moon / baked-GI /
// baked-weight) when it is ON. u_rt_light_on = master (1 => this path taken,
// every round-1..5 branch below skipped). baked vertex lighting is hardwired OFF in
// this path (realtime ON => baked off; realtime OFF takes the stock legacy baked path).
// u_rt_sun_dir = surface->sun, world space, == the vector that places
// the VISIBLE sun sprite (sky-sun dome dir). u_rt_sun_color carries the sun tint
// AND intensity. ONE light, NO ambient — the opposite side is genuinely dark.
uniform int u_rt_light_on;
uniform vec3 u_rt_sun_dir;
uniform vec3 u_rt_sun_color;
// ITEM B (owner insight): GREEN-STAR / MOON directional NIGHT key light. u_rt_moon_dir = surface->moon
// (elevated, opposite the sun's azimuth); u_rt_moon_color = the green colour already scaled C++-side by
// its intensity (weaker than sun) AND the (1-sun_elev) crossover weight => 0 by day, full at night.
uniform vec3 u_rt_moon_dir;
uniform vec3 u_rt_moon_color;
// lighting-legacy-purge (2026-09-11) : u_rt_ambient_on RETIRE, valeur livree figee a 1 (ambiante toujours active).
// lighting-legacy-purge (2026-09-11) : entrees des tiers HEMISPHERE et IBL d'AMBIENT MODEL, retirees avec eux. La force d'ambiance atteint le tier SH par u_rt_sh.
// Grecharged-directional-ambient ROUND 2 : entrees de l'ambiante SH. u_rt_sh[9] = coefficients SH
// L2 deja mis a l'echelle cote C++ par la convolution cosinus A_l/pi, donc l'evaluation rend
// directement la radiance reflechie. Lues UNIQUEMENT sous u_rt_light_on => OFF == stock.
// lighting-legacy-purge (2026-09-11) : u_rt_ambient_model RETIRE, valeur livree figee a 1 (SH).
// lighting-legacy-purge (2026-09-11) : u_rt_ambient_contrast RETIRE, il etait declare et jamais lu.
// Grecharged-directional-ambient ROOT-CAUSE FIX: debug/A-B toggle. 0 (default) = SMOOTH per-vertex
// normal (the fix); 1 = force the OLD flat per-face screen-derivative normal (pre-fix look, same build).
uniform int u_rt_flat_normal;
uniform vec3 u_rt_sh[9];
// lighting-legacy-purge (2026-09-11) : u_rt_shadow_range RETIRE, valeur livree figee a 150.0.
// lighting-legacy-purge (2026-09-11) : u_rt_shadow_res RETIRE, valeur livree figee a 2048.0.
// lighting-legacy-purge (2026-09-11) : u_rt_shadow_residual RETIRE, valeur livree figee a 0.2
// (le plancher de ciel = 1 - Shadow Strength, force livree 0,8).
// Grecharged-realtime-lighting ROUND 7: NIGHT SUN-FADE. The direct-sun term is gated by the
// REAL sun elevation (the sky-parms visible-sun dome vector's up-component), NOT the mood
// current-sun. 1.0 = sun well above the horizon; smooth ramp near the horizon; 0.0 = sun
// below the horizon (night) => the direct sun (and thus any mood tint in u_rt_sun_color)
// vanishes here, leaving ONLY the ~0.2 sky-fill floor. Set identically for all four world
// shaders (they share first_tfrag_draw_setup), so no path stays lit at night.
uniform float u_rt_sun_elev;
// lighting-shadows (SPEC §4.8/§3.4) : `u_rt_shadow_light`/`u_rt_shadow_conf` (attribution +
// fondu de confiance de l'ancienne carte UNIQUE) SONT RETIRES. L'atlas tuile porte les deux
// astres SIMULTANEMENT (une tuile chacun) : il n'y a plus rien a attribuer ni a fondre —
// `u_shadow_key` (ci-dessus) dit seulement laquelle des DEUX porte les cascades.
// ROUND 5: 16-tap Poisson disk for a wide-penumbra SOFT PCF (replaces the round-4 3x3
// grid — a regular grid aliases against the shadow-map texel lattice => the staircase the
// owner still saw; a Poisson disk does not). Rotated per fragment (see the PCF loop).
const vec2 RT_POISSON16[16] = vec2[](
  vec2(-0.94201624, -0.39906216), vec2(0.94558609, -0.76890725), vec2(-0.094184101, -0.92938870),
  vec2(0.34495938, 0.29387760),   vec2(-0.91588581, 0.45771432), vec2(-0.81544232, -0.87912464),
  vec2(-0.38277543, 0.27676845),  vec2(0.97484398, 0.75648379),  vec2(0.44323325, -0.97511554),
  vec2(0.53742981, -0.47373420),  vec2(-0.26496911, -0.41893023),vec2(0.79197514, 0.19090188),
  vec2(-0.24188840, 0.99706507),  vec2(-0.81409955, 0.91437590), vec2(0.19984126, 0.78641367),
  vec2(0.14383161, -0.14100790));
// Grecharged-directional-ambient ROUND 2 — SH (L2) ambient irradiance. Coeffs pre-scaled C++-side by
// the Lambert cosine-convolution (A_l/pi) so this returns reflected ambient radiance directly. max()
// guards SH ringing. Richer than the 2-color hemisphere: a smooth directional quadratic.
vec3 rt_sh_ambient(vec3 n) {
  float x = n.x, y = n.y, z = n.z;
  vec3 r = u_rt_sh[0] * 0.282095
         + u_rt_sh[1] * (0.488603 * y)
         + u_rt_sh[2] * (0.488603 * z)
         + u_rt_sh[3] * (0.488603 * x)
         + u_rt_sh[4] * (1.092548 * x * y)
         + u_rt_sh[5] * (1.092548 * y * z)
         + u_rt_sh[6] * (0.315392 * (3.0 * z * z - 1.0))
         + u_rt_sh[7] * (1.092548 * x * z)
         + u_rt_sh[8] * (0.546274 * (x * x - y * y));
  return max(r, vec3(0.0));
}
// lighting-legacy-purge (2026-09-11) : entrees des tiers HEMISPHERE et IBL d'AMBIENT MODEL, retirees avec eux. La force d'ambiance atteint le tier SH par u_rt_sh.
// SPEC-refonte-lumiere §2.4 — RETIRE : la grille de sondes de FollowProbe.
// Douze uniformes (dont QUATRE unites de texture sampler3D et un samplerCube) et deux
// fonctions, tous derriere la porte de sondes. Le seul ecrivain de cette porte etait
// FollowProbe::update_and_bind, qui poussait la constante 0 a chaque draw : les quatre
// sampler3D etaient lies a une texture 1x1x1 NOIRE que personne n echantillonnait.
// Mesure : 0 draw monde classe dans ce composite sur 11004086 (course du 2026-09-05). Le nom de
// la porte ne figure plus dans ce texte (census-false-reds, 2026-09-12) : le blob Android embarque
// les commentaires, et un jeton qui ne survit qu'en commentaire finit par etre recense comme s'il
// etait du code.
// OWNER FINAL ARCHITECTURE (2026-07-21) — amplitudes de la MODULATION BAKEE (chemin A, celui que
// l'owner a valide le 2026-07-19). Proprietes debug.opengoal.rt.litboost / .shadowmul / .tintlit /
// .tintshadow / .greenamp. Leur ecrivain etait FollowProbe::update_and_bind ; il est desormais
// `first_tfrag_draw_setup` (background_common.cpp), aux MEMES valeurs.
// `u_rt_detail`, `u_rt_detail_norm` et `u_rt_sun_boost` ne sont PAS repris : mesure apres retrait
// du composite D, `grep -c` rend 0 lecture dans les quatre hotes ET dans le composite de
// materiaux (depuis supprime) — ils ne servaient que la re-injection de detail de D.
uniform float u_rt_lit_boost;    // sun-lit multiplicative brighten, > 1 (default 1.15)
uniform float u_rt_shadow_mul;   // shadowed multiplicative darken, < 1 (default 0.65)
uniform float u_rt_tint_lit;     // lit hue push toward the owning sun's chroma (default 0.12)
uniform float u_rt_tint_shadow;  // shadow hue push toward cool/blue (default 0.12)
uniform float u_rt_green_amp;    // green-sun amplitude scale vs the day sun (default 0.60)
// (le `#endif` qui fermait le bloc OG_PBR de tfrag3.frag est reste chez l'hote : ce chunk
//  est inclus DEPUIS l'interieur d'un `#ifdef OG_PBR`, il n'ouvre ni ne ferme rien.)

// lighting-ao-indirect (SPEC-refonte-lumiere §4.7) : L'AO D'ECRAN, LUE ICI ET NULLE PART AILLEURS.
// La texture est la sortie de l'estimateur (PrePass.cpp), calculee sur la prepasse de profondeur
// AVANT le premier draw ombre ; elle est echantillonnee par gl_FragCoord et multipliee au SEUL
// terme indirect, en lineaire, avant le tone map. Le composite d'image et son masque de
// luminance n'existent plus.
uniform sampler2D tex_screen_ao;    // R8, unite 8 (PrePass::bind_screen_ao)
uniform int u_screen_ao_on;         // 0 = pas d'AO ; 1 = appliquee a l'indirect ; 2 = vue de debug
uniform vec2 u_screen_ao_inv_size;  // 1 / taille du FBO de rendu (gl_FragCoord -> uv)
uniform int u_ao_proof;             // 1 sur l'image sondee : la sortie est un jeu de DRAPEAUX

// ── Surface : TOUT ce que l'hote a le droit de decider ──────────────────────────────────────
// Rien ici n'est un choix de composite : ce sont des grandeurs geometriques et d'apparence.
struct Surface {
  vec4  base;         // la couleur de depart de l'hote (baked * texture)
  vec4  baked;        // la couleur bakee par sommet, non texturee
  vec4  tex0;         // la texture de base, telle que lue
  vec3  P_rel;        // position relative camera, en METRES
  vec3  uv;           // coordonnee de texture
  vec3  N;            // normale d'OMBRAGE, construite par l'hote
  vec3  gN;           // normale geometrique de face, orientee vers la camera
  vec3  V;            // surface -> oeil, unitaire
  vec3  shadow_N;     // normale qui porte l'offset de la carte d'ombre
  float shadow_ndl;   // le N.L qui module cet offset
};

// lighting-shadows (SPEC §4.8) : L'ATLAS TUILE, ECHANTILLONNE PAR TUILE.
// `rt_tile_vis` teste UNE tuile de l'atlas (16-tap Poisson, identique au round-5 par tuile) ;
// rend -1.0 si le fragment tombe hors de son cadre. `rt_key_vis` choisit la cascade de l'astre
// DOMINANT et fond en douceur cascade->cascade et cascade->bord ; `rt_sec_vis` fait la meme
// chose pour la tuile UNIQUE du second astre (pas de cascade, juste un bord qui fond).
float rt_tile_vis(int t, vec3 P_rel, vec3 sN, float sndl, float dist) {
  float noff = u_shadow_texel[t] * (u_rt_light_on != 0 ? mix(1.5, 5.0, 1.0 - sndl)
                                                       : mix(0.75, 2.0, 1.0 - sndl));
  vec3 sworld = P_rel + u_pbr_shadow_cam_delta + sN * noff;
  vec4 sp = u_shadow_tile_mvp[t] * vec4(sworld, 1.0);
  vec3 suv = sp.xyz / sp.w * 0.5 + 0.5;
  if (suv.x < 0.002 || suv.x > 0.998 || suv.y < 0.002 || suv.y > 0.998 || suv.z >= 1.0) {
    return -1.0;
  }
  float bias = (u_rt_light_on != 0 ? 0.0010 : 0.0012) + u_pbr_shadow_bias;
  float ref = suv.z - bias;
  float pen = max(1.5 * u_shadow_texel[t], 0.02 + 0.015 * dist);  // penombre, en METRES
  float rr = min(pen / (u_shadow_texel[t] * u_shadow_tile_px), 24.0 / u_shadow_tile_px);
  vec2 org = vec2(float(t & 1), float(t >> 1)) * 0.5;  // origine de la tuile dans l'atlas (uv)
  float hang = fract(sin(dot(gl_FragCoord.xy, vec2(12.9898, 78.233))) * 43758.5453) * 6.2831853;
  vec2 hc = vec2(cos(hang), sin(hang));
  mat2 hrot = mat2(hc.x, -hc.y, hc.y, hc.x);
  float vis = 0.0;
  vec2 lo = vec2(0.5 / u_shadow_tile_px);
  vec2 hi = vec2(1.0 - 0.5 / u_shadow_tile_px);
  for (int i = 0; i < 16; i++) {
    vec2 o = hrot * (RT_POISSON16[i] * rr);
    vec2 uv = clamp(suv.xy + o, lo, hi);
    vis += ref <= texture(tex_PBR_SHADOW, org + uv * 0.5).r ? 1.0 : 0.0;
  }
  return vis * (1.0 / 16.0);
}

float rt_key_vis(vec3 P_rel, vec3 sN, float sndl) {
  float d = length(P_rel);
  int n = int(u_shadow_split.w);
  for (int c = 0; c < 3; c++) {
    if (c >= n) {
      break;
    }
    float s = u_shadow_split[c];
    if (d < s) {
      float v = rt_tile_vis(c, P_rel, sN, sndl, d);
      if (v < 0.0) {
        return 1.0;
      }
      if (c + 1 < n && d > 0.9 * s) {
        float v2 = rt_tile_vis(c + 1, P_rel, sN, sndl, d);
        if (v2 >= 0.0) {
          v = mix(v, v2, (d - 0.9 * s) / (0.1 * s));
        }
      }
      if (c + 1 == n) {
        v = mix(1.0, v, 1.0 - smoothstep(s * 0.72, s * 0.96, d));
      }
      return v;
    }
  }
  return 1.0;
}

float rt_sec_vis(vec3 P_rel, vec3 sN, float sndl) {
  if ((u_shadow_tiles & 8) == 0) {
    return 1.0;
  }
  int n = int(u_shadow_split.w);
  float s = u_shadow_split[n > 0 ? n - 1 : 2];
  float d = length(P_rel);
  float v = rt_tile_vis(3, P_rel, sN, sndl, d);
  if (v < 0.0) {
    return 1.0;
  }
  return mix(1.0, v, 1.0 - smoothstep(s * 0.72, s * 0.96, d));
}

// Rend la couleur ombree. Le brouillard, l'alpha et le discard restent a l'hote : ce n'est pas
// de l'eclairage.
// Le corps de l'ombrage. `sao` est l'AO d'ecran de ce fragment (1 = rien d'occulte) ; c'est le
// SEUL parametre par lequel elle entre, ce qui permet a shade() de l'evaluer deux fois.
vec4 shade_body(in Surface s, float sao) {
  vec4 color = s.base;
  // L'AO en LINEAIRE sur une base encodee gamma : (base^2.2 * sao)^(1/2.2) == base * sao^(1/2.2).
  float ao_mul = (sao >= 1.0) ? 1.0 : pow(max(sao, 0.0), 1.0 / 2.2);
  bool ao_applied = false;
  vec3 N = s.N;

    // lighting-shadows (SPEC §4.8) : le facteur d'ombre portee vient desormais de
    // `rt_key_vis`/`rt_sec_vis` (definis plus haut, atlas tuile), pas d'un calcul inline ici.
    // ===================================================================
    // Grecharged-realtime-lighting (2026-07-19 REWRITE): SUN-ONLY path.
    // When ON this REPLACES every round-1..5 branch below. ONE light = the
    // visible sun; per-face N.L; NO ambient; baked OFF by default. The whole
    // point: sun-side lit / opposite side genuinely dark, pinned to world
    // geometry under any camera orbit.
    // ===================================================================
    if (u_rt_light_on != 0) {
      // The sun: surface->sun, world space, == the vector that places the
      // visible sun sprite (sky-sun dome dir when above the horizon).
      vec3 L = normalize(u_rt_sun_dir);
      float ndl = max(dot(N, L), 0.0);           // opposite side -> 0 = dark
      // lighting-shadows (SPEC §4.8) : DEUX astres, DEUX ombres, aucune attribution ni fondu.
      // `key` = l'astre qui porte les cascades (`u_shadow_key`) ; `sec` = l'autre, sur la
      // tuile 3 s'il en a une. Chacun garde SA propre occlusion, jamais fondue dans l'autre.
      float key = 1.0, sec = 1.0;
      if (u_pbr_shadow_on != 0) {
        float key_ndl = (u_shadow_key == 0) ? s.shadow_ndl
                                            : clamp(dot(s.shadow_N, normalize(u_rt_moon_dir)), 0.0, 1.0);
        float sec_ndl = (u_shadow_key == 0) ? clamp(dot(s.shadow_N, normalize(u_rt_moon_dir)), 0.0, 1.0)
                                            : s.shadow_ndl;
        key = rt_key_vis(s.P_rel, s.shadow_N, key_ndl);
        sec = rt_sec_vis(s.P_rel, s.shadow_N, sec_ndl);
      }
      float sun_occ  = (u_shadow_key == 0) ? key : sec;
      float moon_occ = (u_shadow_key == 0) ? sec : key;
      // ===================================================================================
      // BAKED-MODULATION — preserve the authored lighting as the non-PBR base.
      // The baked (s.baked * s.tex0, already sitting in `color`) already contains shading
      // and ambient light. Keep it as the base without darkening or cooling it a second
      // time. The non-PBR realtime layer modulates the existing lit supplement:
      //   sun-LIT  (N.L toward the sun AND not cast-shadowed): x lit_boost (>1) + hue/sat
      //            pushed slightly TOWARD THE SUN's tint (warm yellow by day; the green sun
      //            uses its own green chroma at night);
      //   SHADOWED (faces away from the sun OR under a cast shadow): x1, back to baked.
      // Each sun contributes 1 + w_i * lit_i * (lit_mul_i - 1); the two factors multiply.
      // Occlusion only removes the existing lit supplement down to the baked base,
      // reducing shadow amplitude. This does not fully separate baked light components.
      // Both suns run the same model; each amplitude SCALES with its sun's elevation weight
      // (w_y = u_rt_sun_elev -> 0 at night = no yellow ghost shadows; the green sun's night
      // weight is already folded into u_rt_moon_color C++-side -> 0 by day), green at a
      // weaker amplitude (u_rt_green_amp). The lit<->shadow terminator is SMOOTHSTEPPED on
      // N.L (no hard edge); cast-shadow edges keep the 16-tap Poisson PCF softness carried
      // inside sun_occ / moon_occ (and the shadow-conf handoff fade already mixed into occ).
      // The probe system no longer projects onto world geometry on this default path — it is
      // a RESOURCE for future PBR/water; the old probe-fed composite is GONE with its gate.
      // Realtime Lighting OFF never reaches here => pure vanilla baked (OFF == stock).
      float term_y = smoothstep(0.0, 0.35, dot(N, L));                       // smooth terminator
      float term_g = smoothstep(0.0, 0.35, dot(N, normalize(u_rt_moon_dir)));
      float lit_y = term_y * sun_occ;    // toward the sun AND not cast-shadowed
      float lit_g = term_g * moon_occ;
      float w_y = clamp(u_rt_sun_elev, 0.0, 1.0);
      float w_g = clamp(dot(u_rt_moon_color, vec3(1.0)), 0.0, 1.0) * clamp(u_rt_green_amp, 0.0, 2.0);
      // luma-neutral chromas: the tint shifts hue/saturation only; lit_boost sets
      // the lit energy (guarded divisions; a zero-color sun also has weight ~0).
      vec3 sun_ch = u_rt_sun_color / max(dot(u_rt_sun_color, vec3(0.299, 0.587, 0.114)), 1e-3);
      vec3 moon_ch = u_rt_moon_color / max(dot(u_rt_moon_color, vec3(0.299, 0.587, 0.114)), 1e-3);
      vec3 lit_mul_y = u_rt_lit_boost * mix(vec3(1.0), sun_ch, clamp(u_rt_tint_lit, 0.0, 1.0));
      vec3 lit_mul_g = u_rt_lit_boost * mix(vec3(1.0), moon_ch, clamp(u_rt_tint_lit, 0.0, 1.0));
      // Baked already includes shading/ambient: occlusion removes only the lit
      // supplement, with reduced shadow amplitude and no second darkening/cooling.
      //
      // L'AMBIANTE SH DIRECTIONNELLE EST RE-HEBERGEE ICI (lighting-legacy-purge, 2026-09-12).
      // POURQUOI ELLE DOIT L'ETRE. Ses deux seuls appelants vivaient dans les deux morceaux de
      // la pile de matiere que cet item supprime (leurs NOMS ne sont pas ecrits ici : le blob
      // Android embarque les commentaires, et un nom de fichier supprime cite en commentaire est
      // recense comme un residu — mesure du 12/09, 2 occurrences dans libgk.so pour ces deux
      // seules lignes). Le recensement les nomme, lui : `lib/census/<id>.sh`. Sans ce site, `u_rt_sh[9]`
      // n'aurait plus AUCUN lecteur : un uniforme declare mais jamais lu est RETIRE par le
      // compilateur GLSL, et les neuf coefficients partiraient vers l'emplacement -1 a chaque
      // image (230 880 poussees mesurees sur le checkpoint de l'essai 8). La feature validee par
      // l'owner — Grecharged-directional-ambient ROUND 2 — serait morte en silence avec le
      // composite qui l'hebergeait. `lighting_legacy_sh_readers` compte ce site sur le programme
      // LIE, et un zero est une porte ROUGE.
      // COMMENT ELLE ENTRE SANS AJOUTER UNE SECONDE DOSE D'AMBIANTE. Ce composite tient deja son
      // INDIRECT du cuit : lui additionner la SH doublerait l'ambiante. On ne prend donc que ce
      // que ROUND 2 apporte, et c'est son propre contrat, ecrit dans le C++ qui la projette
      // (background_common.cpp, MEAN-NORMALIZE) : les modeles « carry identical average ambient
      // energy [...] and differ only in DIRECTIONAL distribution (=> shadowed FORM) ». On divise
      // donc l'ambiante vue par la normale par sa MOYENNE SPHERIQUE — la bande L0 seule, les
      // bandes 1 et 2 s'integrant a zero sur la sphere — ce qui rend un facteur de moyenne 1,0.
      // Un ciel isotrope rend EXACTEMENT 1,0 sur les trois canaux : l'image ne bouge pas d'un bit.
      // Le facteur ne s'applique qu'au bras OMBRE (`shd_mul`), jamais au bras ensoleille : c'est
      // la regle d'or citee au meme endroit (« sunlit byte-identical across models »).
      // LE REPLI. `step()` met le facteur a 1,0 exactement quand la moyenne est degeneree —
      // programme jamais atteint par la poussee, defaut GL a zero : `u_rt_sh` vaut alors (0,0,0)
      // et un rapport y serait un 0/0. Ce n'est pas un reglage, c'est une garde de division.
      vec3 sh_mean = u_rt_sh[0] * 0.282095;
      vec3 sh_form = clamp(rt_sh_ambient(N) / max(sh_mean, vec3(1e-4)), vec3(0.0), vec3(2.0));
      vec3 shd_mul = mix(vec3(1.0), sh_form,
                         step(1e-3, dot(sh_mean, vec3(0.299, 0.587, 0.114))));
      vec3 mod_y = mix(shd_mul, lit_mul_y, lit_y);
      vec3 mod_g = mix(shd_mul, lit_mul_g, lit_g);
      vec3 rt_mod = mix(vec3(1.0), mod_y, w_y) * mix(vec3(1.0), mod_g, w_g);
      // lighting-hdr (essai 62) : LE SUPPLEMENT LIT NE FABRIQUE PAS DE BLANC. Mesure x86 du
      // 2026-09-09 (lot essai62-x86-pathA-before, composite A comme sur le Redmi) : 12 vues sur
      // 34 ecretent PLUS en ON qu'en OFF, et 85 % des pixels ecretes ON-seulement ont un canal
      // OFF >= 222 : c'est ce facteur 1,15 qui pousse une surface deja claire au-dessus de 1,0.
      // Aucune courbe monotone du tone map ne peut le rattraper : les blancs voulus d'origine
      // (x = 1,0) doivent rester blancs, donc tout ce qui depasse 1,0 est ecrete. La marge se
      // prend ICI : le supplement (lit - base) s'eteint en fondu quand la base approche du
      // blanc (plein effet sous 0,7) et ne porte jamais le canal max au-dessus de 1,0. Sous 0,7
      // le rendu est identique a avant ; les ombres (rt_mod = 1) ne bougent pas.
      vec3 rt_lit = max(color.rgb * rt_mod, vec3(0.0));
      float rt_m0 = max(color.r, max(color.g, color.b));
      float rt_m1 = max(rt_lit.r, max(rt_lit.g, rt_lit.b));
      // Plafond a 0,995 (254/255) et non 1,0 : a 1,0 exactement, une base a 250 gagnait
      // encore 2 % et sortait ecretee (misty h18, lot essai62-x86-final : 551 pixels
      // ON-seulement avec un canal OFF >= 245). Le supplement ne fabrique jamais un 255.
      float rt_g = clamp((0.995 - rt_m0) / 0.3, 0.0, 1.0);
      if (rt_m1 > rt_m0 + 1e-5) {
        rt_g = min(rt_g, clamp((0.995 - rt_m0) / (rt_m1 - rt_m0), 0.0, 1.0));
      }
      // lighting-ao-indirect : le supplement DIRECT (rt_lit - base) est calcule sur la base
      // NON occultee et s'ajoute intact ; l'AO ne multiplie que la base cuite — l'indirect,
      // jusqu'a ce que lighting-bake le separe du soleil cuit. Porte : ao_direct_leak_px.
      vec3 rt_sup = (rt_lit - color.rgb) * rt_g;
      color.rgb = color.rgb * ao_mul + rt_sup;
      ao_applied = true;
      if (u_pbr_debug == 1) {
        color.rgb = vec3(ndl);
      } else if (u_pbr_debug == 2) {
        color.rgb = N * 0.5 + 0.5;
      } else if (u_pbr_debug == 12) {
        // modulation-factor luma viz: 0.5 = neutral (x1), brighter = lit boost, darker = shadow
        color.rgb = vec3(dot(rt_mod, vec3(0.299, 0.587, 0.114)) * 0.5);
      }
    }
  if (!ao_applied) {
    // Chemins sans terme direct separe (rendu d'origine sous eclairage recharge) : toute la
    // base est de l'indirect cuit, l'AO la multiplie entiere.
    color.rgb *= ao_mul;
  }
  return color;
}

// L'interface des hotes, INCHANGEE : echantillonne l'AO d'ecran, appelle le corps, et sous
// mesure (u_ao_proof) evalue le corps une seconde fois avec AO = 1 pour sortir les drapeaux de
// la porte a la place de la couleur :
//   R = fuite sur le direct : |(c_ao - c_1) - (ao_mul - 1) * base| > 2e-4. `base` est une
//       ENTREE de l'ombrage et ao_mul une fonction fixe de l'echantillon : la porte compare la
//       sortie REELLE du programme a une grandeur qu'il ne fabrique pas lui-meme.
//   G = l'indirect a recu l'AO (sao < 1 et la couleur a bouge).
//   B = chemin exclu de la porte. Ce seau est desormais toujours vide (voir plus bas).
#ifdef OG_HUT_COLOR
uniform int u_hut_capture;
layout(location = 2) out vec4 hut_color_sample; // actual delta RGB, sampled AO
layout(location = 3) out vec4 hut_color_normal; // actual shade normal, valid
#endif
vec4 shade(in Surface s) {
  float sao = 1.0;
  if (u_screen_ao_on != 0) {
    sao = clamp(texture(tex_screen_ao, gl_FragCoord.xy * u_screen_ao_inv_size).r, 0.0, 1.0);
  }
  vec4 c = shade_body(s, sao);
  // lighting-shadows (A7) : sonde de preuve — l'image de PREUVE (`u_shadow_proof`) sort un
  // drapeau au lieu de la couleur : magenta si CE fragment tombe dans une cascade ET que
  // l'atlas ACTEUR (rempli par les merc a la preparation) l'occulte alors que l'atlas complet
  // dit aussi "ombre" ; vert sinon. `pbr_shadow_proof_before_bucket`/`post_opaque` (C++)
  // isolent ensuite les pixels de SOL touches par cette couleur.
  if (u_shadow_proof != 0) {
    if (u_pbr_shadow_on == 0) {
      return vec4(0.0, 1.0, 0.0, s.base.a);
    }
    float d = length(s.P_rel);
    int n = int(u_shadow_split.w);
    int cc = -1;
    for (int c2 = 0; c2 < 3; c2++) {
      if (c2 < n && d < u_shadow_split[c2]) {
        cc = c2;
        break;
      }
    }
    bool hit = false, actor_occ = false, full_occ = false;
    if (cc >= 0) {
      float noff = u_shadow_texel[cc] * (u_rt_light_on != 0 ? mix(1.5, 5.0, 1.0 - s.shadow_ndl)
                                                            : mix(0.75, 2.0, 1.0 - s.shadow_ndl));
      vec3 sworld = s.P_rel + u_pbr_shadow_cam_delta + s.shadow_N * noff;
      vec4 sp = u_shadow_tile_mvp[cc] * vec4(sworld, 1.0);
      vec3 suv = sp.xyz / sp.w * 0.5 + 0.5;
      if (suv.x >= 0.0 && suv.x <= 1.0 && suv.y >= 0.0 && suv.y <= 1.0 && suv.z < 1.0) {
        float bias = (u_rt_light_on != 0 ? 0.0010 : 0.0012) + u_pbr_shadow_bias;
        float ref = suv.z - bias;
        vec2 org = vec2(float(cc & 1), float(cc >> 1)) * 0.5;
        float actor = texture(tex_SHADOW_ACTOR, org + clamp(suv.xy, 0.0, 1.0) * 0.5).r;
        float key_vis = rt_key_vis(s.P_rel, s.shadow_N, s.shadow_ndl);
        // « Ombre par un acteur » = l'acteur est le PREMIER occulteur vers l'astre : sa profondeur
        // est celle de l'atlas complet au meme texel. Un acteur lui-meme a l'ombre du decor ne
        // compte pas (son ombre ne se voit pas).
        float full_c = texture(tex_PBR_SHADOW, org + clamp(suv.xy, 0.0, 1.0) * 0.5).r;
        actor_occ = (u_shadow_proof == 2) ? (actor < 0.999)
                                          : (ref > actor && abs(full_c - actor) < 2e-4);
        full_occ = key_vis < 0.5;
        hit = actor_occ && full_occ;
      }
    }
    // Quatre etats, pour que la sonde separe ses deux conditions : magenta = ombre d'acteur
    // (les deux), bleu = ombre du decor seulement, cyan = l'atlas acteur occulte mais pas l'atlas
    // complet (desaccord), vert = eclaire.
    if (!hit && full_occ) {
      return vec4(0.0, 0.0, 1.0, s.base.a);
    }
    if (!hit && actor_occ) {
      return vec4(0.0, 1.0, 1.0, s.base.a);
    }
    // L'alpha d'origine est garde : le test d'alpha de l'hote doit trancher comme d'habitude.
    return hit ? vec4(1.0, 0.0, 1.0, s.base.a) : vec4(0.0, 1.0, 0.0, s.base.a);
  }
#ifdef OG_HUT_COLOR
  if (u_hut_capture != 0) {
    vec4 without_ao = shade_body(s, 1.0);
    hut_color_sample = vec4(c.rgb - without_ao.rgb, sao);
    hut_color_normal = vec4(s.N, 1.0);
  }
#endif
  if (u_ao_proof != 0) {
    vec4 c1 = shade_body(s, 1.0);
    float ao_mul = (sao >= 1.0) ? 1.0 : pow(max(sao, 0.0), 1.0 / 2.2);
    vec3 delta = c.rgb - c1.rgb;
    vec3 resid = abs(delta - (ao_mul - 1.0) * s.base.rgb);
    float leak = max(resid.r, max(resid.g, resid.b));
    float changed = max(abs(delta.r), max(abs(delta.g), abs(delta.b)));
    float hit = (sao < 0.999 && changed > 1e-4) ? 1.0 : 0.0;
    // lighting-legacy-purge (2026-09-12) : le seau « exclu » de la porte lighting-ao-indirect
    // se VIDE. Il comptait les fragments dont l'indirect n'etait pas `base` — c'est-a-dire ceux
    // des composites qui viennent d'etre supprimes. Aucun de ces chemins n'existe plus, donc
    // plus aucun fragment n'est exclu de la porte : la valeur est une constante, pas un test.
    float excl = 0.0;
    // The caller still alpha-tests this result. Preserve coverage while replacing RGB
    // with proof flags; alpha=1 would make the probe draw transparent TIE texels.
    return vec4(leak > 2e-4 ? 1.0 : 0.0, hit, excl, c.a);
  }
  if (u_screen_ao_on == 2) {
    c.rgb = vec3(sao);  // vue de debug : le terme d'AO tel qu'il est lu
  }
  return c;
}
// ================= @shade-model-end =================
