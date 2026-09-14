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
uniform mat4 u_pbr_shadow_mvp;
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
// Item 1 (owner playtest #3): which sun the single shadow map was rendered from this frame —
// 0 = yellow sun (day), 1 = green sun (night, when the yellow is below the horizon). The cast-
// shadow occlusion is applied to the MATCHING directional term so the green sun casts shadows too.
uniform int u_rt_shadow_light;
// OWNER PLAYTEST #4: shadow-handoff confidence [0..1]. 1 => one sun clearly dominates (full cast
// shadow); ->0 near the yellow<->green elevation crossover / both-suns overlap (fade the shadow out
// so the single-map ownership flip is stepless). Fades ONLY the direct-sun cast shadow (golden rule).
uniform float u_rt_shadow_conf;
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

    // Round-4 mandate B / ROUND-2 rewrite: sun shadow-map factor, a real PER-FRAGMENT
    // world-position depth compare — the receiver projects ITS OWN s.P_rel (camera-
    // relative meters, height included) into the light's clip space and tests depth, so the
    // shadow DRAPES over whatever surface it lands on (owner round-2 defect #1: it must
    // follow ground relief, not sit like a flat decal). The heavy lifting for acne is done
    // by a WORLD-SPACE NORMAL OFFSET (push the sample toward the light hemisphere a couple
    // of texels) instead of the old ~0.025 suv.z depth bias — that bias was ~5 m of depth
    // slack, which peter-panned the contact AND flattened the shadow's response to bumps.
    // Range/res come from the Shadow Distance / Shadow Quality settings.
    float sm_shadow = 1.0;
    if (u_pbr_shadow_on != 0) {
      // lighting-legacy-purge : DISTANCE DES OMBRES figee (ex-reglage, item lighting-shadows)
      float rng = 150.0;
      // lighting-legacy-purge : RESOLUTION DES OMBRES figee (ex-reglage, item lighting-shadows)
      float res = 2048.0;
      float texel = 1.0 / res;
      float texel_world = (2.0 * rng) / res;  // world meters per shadow texel
      // La normale et le N.L qui pilotent l'OFFSET de la carte d'ombre viennent de Surface :
      // ils DIFFERENT par hote et ce n'est pas une decision d'ombrage, c'est de la geometrie.
      // tfrag3 pousse la normale de FACE (derivees de P_rel) et son N.L avec le soleil ;
      // TIE/TIE_WIND/shrub poussent leur normale d'OMBRAGE et `dot(N, u_rt_sun_dir)`. Les deux
      // formes existaient deja, chacune dans son fichier ; les fusionner en une seule aurait
      // deplace les ombres de TIE et des arbustes. La forme est UNE, les entrees sont DEUX.
      // Per-face WORLD normal for the normal-offset bias (camera-independent: s.P_rel
      // is camera-TRANSLATED, not rotated). Double-sided for level tris.
      // NORMAL OFFSET in world meters, scaled by texel size (so it stays ~constant in
      // texels across every Shadow Quality / Distance combo) and by grazing angle. The
      // sun-only (no-ambient) path needs a bit more (acne is unmasked without baked
      // indirect); the pbr-materials path keeps a lighter offset.
      float noff = texel_world * (u_rt_light_on != 0 ? mix(1.5, 5.0, 1.0 - s.shadow_ndl)
                                                     : mix(0.75, 2.0, 1.0 - s.shadow_ndl));
      vec3 sworld = s.P_rel + u_pbr_shadow_cam_delta + s.shadow_N * noff;
      vec4 sp = u_pbr_shadow_mvp * vec4(sworld, 1.0);
      vec3 suv = sp.xyz / sp.w * 0.5 + 0.5;
      if (suv.x > 0.002 && suv.x < 0.998 && suv.y > 0.002 && suv.y < 0.998 && suv.z < 1.0) {
        // Tiny residual constant depth bias; the normal offset does the acne work, so this
        // stays small and the shadow stays in CONTACT at the caster base (no peter-panning).
        // u_pbr_shadow_bias: debug override (prop ...pbr.shadowbias); +0.5 forces every
        // in-box fragment SHADOWED — the binary compare-path test.
        float bias = (u_rt_light_on != 0 ? 0.0010 : 0.0012) + u_pbr_shadow_bias;
        float ref = suv.z - bias;
        // ROUND-4 item #3 ANTI-PIXELATION (owner: a shadow must NEVER look pixelated
        // anywhere in the FOV, ever). Distance-adaptive PCF: the kernel RADIUS grows with
        // the fragment's camera distance, so a far caster's shadow (few shadow-texels per
        // screen pixel = blocky) is smoothed into a soft gradient, while near casters stay
        // crisp (small radius => the Shadow Quality resolution still reads as edge sharpness).
        // The 9-tap grid is ROTATED by a per-fragment hash so no blocky grid pattern survives
        // even at Very Low (512) where each texel is large. Manual compare (Adreno HW-compare
        // returns constant 1.0 — proven this phase).
        // ROUND-5 (owner: the round-4 3x3-grid blur FAILED — distant cast shadows were
        // STILL staircased). A real wide-penumbra soft shadow: a 16-tap POISSON disk
        // (a regular grid aliases against the shadow-texel lattice => staircase; a Poisson
        // disk does not), ROTATED per fragment, with a penumbra RADIUS that grows STRONGLY
        // with camera distance so a far caster's shadow becomes a wide soft gradient (never
        // blocky) while a near caster stays crisp (small radius => the Shadow Quality
        // resolution still reads as edge sharpness). Owner: "more blur is GOOD" — a distant
        // occluder has a wide penumbra. Absolute: no staircase anywhere in the FOV, ever.
        float sdist = length(s.P_rel);
        float soft = 1.5 + 18.0 * smoothstep(0.0, rng, sdist);   // penumbra radius in texels
        float rr = texel * soft;
        float hang = fract(sin(dot(gl_FragCoord.xy, vec2(12.9898, 78.233))) * 43758.5453) * 6.2831853;
        vec2 hc = vec2(cos(hang), sin(hang));
        mat2 hrot = mat2(hc.x, -hc.y, hc.y, hc.x);
        sm_shadow = 0.0;
        for (int i = 0; i < 16; i++) {
          vec2 o = hrot * (RT_POISSON16[i] * rr);
          sm_shadow += ref <= texture(tex_PBR_SHADOW, suv.xy + o).r ? 1.0 : 0.0;
        }
        sm_shadow *= (1.0 / 16.0);
        // ROUND-2 no-pop fade (owner defect #2): fade the CAST shadow smoothly to 'lit'
        // toward the realtime-zone edge, tied to the Shadow Distance setting (rng), instead
        // of the old hard 30..39 m band. (Round-4: just past the edge the whole surface then
        // crossfades to the stock BAKED lighting — see the sun block below — so there is no
        // hard cut and no flat/unshaded far; the shadow simply softens out first.)
        float edge_fade = 1.0 - smoothstep(rng * 0.72, rng * 0.96, length(s.P_rel));
        sm_shadow = mix(1.0, sm_shadow, edge_fade);
      }
    }
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
      // Stage 2: cast-shadow occlusion from the sun depth map (1.0 = lit, 0.0 = fully
      // occluded; 1.0 when the map is off). occ is the RAW occlusion — the ~0.2 residual is
      // NOT applied here anymore; it is folded into the uniform floor below (round-5 corr).
      float occ = u_pbr_shadow_on != 0 ? sm_shadow : 1.0;
      occ = mix(1.0, occ, u_rt_shadow_conf);  // playtest #4: fade shadow at the yellow<->green handoff (stepless)
      // ROUND-5 CORRECTION (owner, correct physics 2026-07-19): the residual ~0.2 is a
      // UNIFORM SKY-FILL FLOOR, not a cast-shadow-only term. A face turned AWAY from the
      // sun is lit only by skylight EXACTLY like a cast shadow, so BOTH keep ~0.2 —
      // nothing is pure black anywhere. floor = 0.2 (lighting-legacy-purge : la litterale
      // livree de 1 - Shadow Strength, l'ancien reglage a disparu).
      // The sun adds on top, gated by BOTH N.L and the cast-shadow occlusion:
      //   final = floor + (1 - floor) * sun_color * max(N.L,0) * occ
      // => away-from-sun faces AND cast shadows sit at the SAME floor level (measure both).
      // ROUND-7 NIGHT FADE: multiply the direct-sun gate by the real sun-elevation fade so the
      // sun (and any mood tint carried in u_rt_sun_color) goes to EXACTLY 0 at night. Identical
      // in all four world shaders => no geometry stays lit at night.
      // Item 1: the single shadow map is driven by whichever sun is the key this frame
      // (u_rt_shadow_light: 0 = yellow by day, 1 = green at night). Apply the occlusion ONLY to
      // that light's own term; the other light stays unshadowed (its map isn't the one drawn).
      float sun_occ  = (u_rt_shadow_light == 1) ? 1.0 : occ;   // yellow-sun cast shadow (or 1 at night)
      float moon_occ = (u_rt_shadow_light == 1) ? occ : 1.0;   // green-sun cast shadow (night)
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
vec4 shade(in Surface s) {
  float sao = 1.0;
  if (u_screen_ao_on != 0) {
    sao = clamp(texture(tex_screen_ao, gl_FragCoord.xy * u_screen_ao_inv_size).r, 0.0, 1.0);
  }
  vec4 c = shade_body(s, sao);
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
