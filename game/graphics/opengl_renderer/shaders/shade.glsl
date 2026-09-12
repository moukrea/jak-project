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
// CE QUI CHANGE POUR TROIS HOTES, ET IL FAUT LE DIRE. Les composites C (« PBR autonome »,
// `u_rt_light_on == 0 && u_pbr_mode != 0`) et E (« relight legacy », `u_pbr_shadow_on != 0`)
// n'existaient que dans tfrag3.frag. Ils sont desormais dans le texte commun, donc etie_base,
// tie_wind et shrub les atteignent aussi. Sur les DEUX jeux de reference cela ne change rien
// (ils tournent master OFF, ou master ON + lumiere temps reel ON, ou C et E ne sont pas pris).
// Cela change le rendu dans la configuration « materiaux PBR ON + lumiere temps reel OFF », qui
// n'a jamais ete acceptee par l'owner et que les items 2 a 11 remplacent. Ce n'est pas un effet
// de bord : c'est le but de l'item — une seule fonction ombre tout ce que le jeu dessine.
//
// LA MESURE. Les deux marqueurs ci-dessous delimitent la region que
// game/graphics/opengl_renderer/shade_proof.cpp empreinte DANS LE TEXTE QUE LE PILOTE COMPILE.
// Tant que chaque hote portait sa copie, les empreintes differaient : `shade_variants` valait 4
// (mesure du 2026-09-06, 5 programmes monde). Ici il n'y en a qu'une, donc 1.

// ================= @shade-model-begin =================
#include "pbr_uniforms.glsl"

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
// fonctions, tous derriere `u_rt_probe_on != 0`. Le seul ecrivain de cette porte etait
// FollowProbe::update_and_bind, qui poussait la constante 0 a chaque draw : les quatre
// sampler3D etaient lies a une texture 1x1x1 NOIRE que personne n echantillonnait.
// Mesure : light_census_D=0 sur 11004086 draws monde (course du 2026-09-05).
// OWNER FINAL ARCHITECTURE (2026-07-21) — amplitudes de la MODULATION BAKEE (chemin A, celui que
// l'owner a valide le 2026-07-19). Proprietes debug.opengoal.rt.litboost / .shadowmul / .tintlit /
// .tintshadow / .greenamp. Leur ecrivain etait FollowProbe::update_and_bind ; il est desormais
// `first_tfrag_draw_setup` (background_common.cpp), aux MEMES valeurs.
// `u_rt_detail`, `u_rt_detail_norm` et `u_rt_sun_boost` ne sont PAS repris : mesure apres retrait
// du composite D, `grep -c` rend 0 lecture dans les quatre hotes ET dans pbr_fused.glsl — ils ne
// servaient que la re-injection de detail de D (SPEC-refonte-lumiere D.3).
uniform float u_rt_lit_boost;    // sun-lit multiplicative brighten, > 1 (default 1.15)
uniform float u_rt_shadow_mul;   // shadowed multiplicative darken, < 1 (default 0.65)
uniform float u_rt_tint_lit;     // lit hue push toward the owning sun's chroma (default 0.12)
uniform float u_rt_tint_shadow;  // shadow hue push toward cool/blue (default 0.12)
uniform float u_rt_green_amp;    // green-sun amplitude scale vs the day sun (default 0.60)
// (le `#endif` qui fermait le bloc OG_PBR de tfrag3.frag est reste chez l'hote : ce chunk
//  est inclus DEPUIS l'interieur d'un `#ifdef OG_PBR`, il n'ouvre ni ne ferme rien.)

#include "pbr_helpers.glsl"

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
  vec3  vnormal;      // la normale par sommet BRUTE (le chemin C se refait sa propre base)
  vec4  T;            // tangente MikkTSpace ; (0,0,0,1) quand l'hote n'en a pas
  vec3  shadow_N;     // normale qui porte l'offset de la carte d'ombre
  float shadow_ndl;   // le N.L qui module cet offset
};

// Rend la couleur ombree. Le brouillard, l'alpha et le discard restent a l'hote : ce n'est pas
// de l'eclairage.
// Le corps de l'ombrage. `sao` est l'AO d'ecran de ce fragment (1 = rien d'occulte) ; c'est le
// SEUL parametre par lequel elle entre, ce qui permet a shade() de l'evaluer deux fois.
vec4 shade_body(in Surface s, float sao, out float f_disp_cover, out vec3 f_disp_diag, out vec3 f_disp_diag2) {
  vec4 color = s.base;
  // L'AO en LINEAIRE sur une base encodee gamma : (base^2.2 * sao)^(1/2.2) == base * sao^(1/2.2).
  float ao_mul = (sao >= 1.0) ? 1.0 : pow(max(sao, 0.0), 1.0 / 2.2);
  bool ao_applied = false;
  f_disp_cover = 0.0;
  f_disp_diag = vec3(0.0);
  f_disp_diag2 = vec3(0.0);
  vec3 N = s.N;
  vec3 gN = s.gN;
  vec3 Vv = s.V;

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
    vec3 sm_dbg_suv = vec3(-1.0);  // viz mode 14: shadow-space UV + in-box flag
    float sm_dbg_inbox = 0.0;
    if (u_pbr_shadow_on != 0) {
      // lighting-legacy-purge : DISTANCE DES OMBRES figee (ex-reglage, item lighting-shadows)
      float rng = 150.0;
      // lighting-legacy-purge : RESOLUTION DES OMBRES figee (ex-reglage, item lighting-shadows)
      float res = 2048.0;
      float texel = 1.0 / res;
      float texel_world = (2.0 * rng) / res;  // world meters per shadow texel
      // La normale et le N.L qui pilotent l'OFFSET de la carte d'ombre viennent de Surface :
      // ils DIFFERENT par hote et ce n'est pas une decision d'ombrage, c'est de la geometrie.
      // tfrag3 pousse la normale de FACE (derivees de P_rel) et `dot(face, u_pbr_light_dir[0])` ;
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
      sm_dbg_suv = suv;
      if (suv.x > 0.002 && suv.x < 0.998 && suv.y > 0.002 && suv.y < 0.998 && suv.z < 1.0) {
        sm_dbg_inbox = 1.0;
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
      float sun_scalar = ndl * sun_occ * u_rt_sun_elev;  // N.L * cast-shadow occlusion * night-fade
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
      // a RESOURCE for future PBR/water; the old probe-fed composite survives only behind
      // the default-OFF "BAKED AMBIENT" curiosity toggle (u_rt_probe_on), the else below.
      // Realtime Lighting OFF never reaches here => pure vanilla baked (OFF == stock).
      // ===============================================================================
      // Grecharged-pbr-realtime-fusion (owner 2026-07-20: "c'est là que ça va briller").
      // When PBR MATERIAL MAPS are bound for this draw (pbr-materials ON => u_pbr_mode
      // != 0), the realtime path becomes a full physically-based renderer: Cook-Torrance
      // GGX for BOTH analytic suns (yellow day sun x its cast shadow x night elevation
      // fade; green night sun x its cast shadow, color pre-weighted C++-side), plus the
      // directional-ambient model (hemisphere/SH/IBL) as the indirect term. The
      // standalone u_pbr_mode branch further below is untouched = the rt-OFF fallback.
      // Conventions:
      //   _specular (bit 32): F0/specular color (SPECULAR WORKFLOW). When present it
      //     OVERRIDES the metallic-derived F0 (mix(0.04, albedo, metal)); roughness
      //     stays microfacet roughness; metal still kills diffuse via kd.
      //   _emissive (bit 64): UNLIT self-illumination ADDED on top — independent of
      //     suns/ambient/shadows => glows at night by construction.
      //   _ao: multiplies the AMBIENT term ONLY (contact occlusion, never the suns).
      // rt ON + pbr OFF (u_pbr_mode==0) falls through to the BAKED-MODULATION
      // path below, with a neutral shadow factor that preserves the baked base.
      if (u_pbr_mode != 0) {
        #include "pbr_fused.glsl"
        ao_applied = true;  // pbr_fused.glsl a multiplie sa part ambiante par `sao`
      // Le composite D (« BAKED AMBIENT », projection par sondes) etait garde par
      // `u_rt_probe_on != 0`. Son SEUL ecrivain etait FollowProbe::update_and_bind, qui
      // poussait la constante 0 inconditionnellement a chaque draw : la branche n'a jamais
      // tourne. Le recensement de l'item lighting-census le mesure — light_census_D=0 sur
      // 11004086 draws monde, course du 2026-09-05. SPEC-refonte-lumiere §2.4.
      } else {
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
        vec3 shd_mul = vec3(1.0);
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
    }
// lighting-unify : COMPOSITES C ET E — RESERVES A LEUR HOTE D'ORIGINE.
// Avant cet item ces deux branches n'existaient QUE dans tfrag3.frag (l. 692 et 1001 de
// 21c2d4ca7d) ; etie_base, tie_wind et shrub n'avaient QUE `if (u_rt_light_on != 0)` et
// retombaient sur le rendu d'origine quand elle etait fausse. Les laisser dans le texte commun
// SANS garde les donnerait aux trois autres hotes, et ce n'est pas un no-op : avec le master
// arme et la configuration LIVREE (le rendu PBR est inconditionnel sous RECHARGED LIGHTING
// depuis lighting-legacy-purge ; recharged_rt_light_enable reste faux par defaut) on a
// u_rt_light_on == 0, u_pbr_mode != 0 et u_pbr_shadow_on == 1 — donc C, puis E. Cette configuration n'est couverte par AUCUN des deux jeux de reference : la porte
// `refset_replay_maxdiff == 0` ne l'aurait pas vue, et l'owner aurait recu un changement de
// pixels que personne n'a demande.
// La garde est un #ifdef, pas une variable : le texte du modele reste OCTET POUR OCTET le meme
// dans les cinq programmes, donc `shade_variants` vaut toujours 1.
#ifdef SHADE_HOST_LEGACY_PBR
    else if (u_pbr_mode != 0 && gfx_hack_no_tex == 0) {
      // Grecharged-pbr-materials: Cook-Torrance GGX lit by the mood/TOD sun.
      // Owner round-3 mandate: the baked per-vertex TOD color (s.baked.rgb) is
      // reintegrated as the INDIRECT/GI term — it carries the level's MACRO shading
      // (building curvature, under-roof darkening, doorway occlusion) that a constant
      // ambient flattened. It is NOT a second direct dose: the realtime direct diffuse
      // is scaled down by u_pbr_direct to compensate for the baked sun it contains.
      // Alpha keeps the legacy product for discard.
      vec3 p = s.P_rel;
      vec3 dp1 = dFdx(p);
      vec3 dp2 = dFdy(p);
      vec3 V = -normalize(p);
      vec3 Ngeo = normalize(cross(dp1, dp2));
      if (dot(Ngeo, V) < 0.0) Ngeo = -Ngeo;
      // REOPEN#7 FOUNDATION FIX (same as the fused path): prefer the CONTINUOUS smooth per-vertex
      // normal as the surface base — the derivative geometric normal Ngeo is itself discontinuous at
      // edges and helped crack the standalone PBR too. Ngeo is kept only for view-facing + fallback.
      vec3 Nsurf = (dot(s.vnormal, s.vnormal) > 0.01) ? normalize(s.vnormal) : Ngeo;
      if (dot(Nsurf, V) < 0.0) Nsurf = -Nsurf;
      // Continuous TBN from the per-vertex tangent (interpolated); derivative frame only as fallback.
      vec3 Tn, Bn;
      if (dot(s.T.xyz, s.T.xyz) > 0.04) {
        Tn = normalize(s.T.xyz - Nsurf * dot(Nsurf, s.T.xyz));
        // Gpbr-per-texture-materials — the handedness comes from THE FACE, not from the vertex.
        // Same defect, same reasoning and the same A/B bit as pbr_fused.glsl (see the long comment
        // there): .w is ONE sign per vertex, handedness is a property of the FACE, and on village1
        // 45.9% of triangles carry a mirrored UV chart. dp1/dp2 are already the world-position
        // derivatives computed above in this same scope; invert the full 2x2 screen->UV Jacobian to
        // recover the true geometric dP/dv, whose sign is what the bitangent must follow.
        vec2 fdUx = dFdx(s.uv.xy), fdUy = dFdy(s.uv.xy);
        float fdetJ = fdUx.x * fdUy.y - fdUx.y * fdUy.x;
        vec3 fdPdv = (fdUx.x * dp2 - fdUy.x * dp1) / (abs(fdetJ) > 1e-9 ? fdetJ : 1.0);
        vec3 fdPdu = (fdUy.y * dp1 - fdUx.y * dp2) / (abs(fdetJ) > 1e-9 ? fdetJ : 1.0);
        // Gpbr-per-texture-materials, BANK-2 BIT 2 — per-FACE tangent DIRECTION, same defect class
        // and same remedy as the handedness above (see pbr_fused.glsl for the measured population).
        // Flips only an ALREADY-reversed tangent, and runs before the handedness sign, which is then
        // derived from the corrected T.
        // lighting-legacy-purge (2026-09-11) : u_pbr_bisect2 RETIRE, valeur livree figee a 0 (chemin complet).
        if (abs(fdetJ) > 1e-9 && dot(Tn, fdPdu) < 0.0) {
          Tn = -Tn;
        }
        float fhs = dot(cross(Nsurf, Tn), fdPdv);
        Bn = cross(Nsurf, Tn) * ((abs(fdetJ) > 1e-9 && abs(fhs) > 1e-9)
                                     ? (fhs < 0.0 ? -1.0 : 1.0)
                                     : (s.T.w < 0.0 ? -1.0 : 1.0));
      } else {
        // REOPEN#9: same continuous normal-derived basis as the fused path — NEVER the screen-space
        // derivative frame (per-triangle-constant = the facet source). Standalone rt-OFF+pbr-ON path.
        frisvad_basis(Nsurf, Tn, Bn);
      }
      // ★ OWNER CHECKER VERDICT, BUG A: the SAME uv as the base colour, no multiplier (see the
      // fused branch — this "bidon" fallback is the owner's "PBR seul" preset, so it has to line
      // up with the pattern too).
      vec2 uv = s.uv.xy;
      // ROUND 22 COVERAGE INSTRUMENTATION — same rule as the fused path (u_pbr_debug 31): a
      // tessellated draw already had its real geometry moved, so it counts as covered here even
      // though the POM march below is skipped for it.
      // lighting-legacy-purge (2026-09-11) : u_pbr_displacement RETIRE, valeur livree figee a 1 (PARALLAX).
      // lighting-legacy-purge (2026-09-11) : la couverture par TESSELLATION est retiree avec son etage.
      // PBR POLISH bug fix — DOUBLE DISPLACEMENT. La porte `« u-pbr-tess-active » == 0` (par PROGRAMME)
      // empechait un dessin deja deplace par la tess-eval d'empiler une marche POM. Elle est
      // SUPPRIMEE avec son etage par lighting-legacy-purge (2026-09-11) : elle etait vraie partout.
      // Everything else on this fallback path is deliberately untouched.
      if ((u_pbr_mode & 16) != 0 && u_pbr_debug != 8 && u_pbr_height_scale > 0.0) {
        // Parallax occlusion mapping, mobile-tuned: grazing-angle-scaled linear march
        // with early-out + one secant refine. Height convention: 1.0 (white) = surface
        // level, lower = carved in — so a neutral white map yields zero offset and the
        // march depth is (1 - height). textureLod avoids undefined derivatives in the
        // loop; the offsets are small so mip 0 is acceptable at PoC distances.
        vec3 Vt = normalize(vec3(dot(V, Tn), dot(V, Bn), max(dot(V, Nsurf), 0.0)));
        float vz = max(Vt.z, 0.20);  // cap the grazing blow-up (raised REOPEN #6 for surface-lock)
        // REOPEN #6 SURFACE-LOCK (same fix as the fused path): clamp the total parallax UV
        // offset so the rt-OFF standalone POM is also welded to the surface — no epoxy float.
        // ★ OWNER 2026-07-26, same rebuild as the fused path and for the same reason (the owner's
        // "PBR seul" preset renders through THIS branch, and "plat autant sur les murs que le sol"
        // was reported on both): the grazing fade is a FLOOR, not a kill, and the absolute 3 cm
        // world cap — the term that actually flattened every material at every angle — is replaced
        // by the material's own feature-scaled depth. Bisect bit 33554432 = legacy behaviour.
        float pom_graze =
            mix(POM_GRAZE_FLOOR, 1.0, smoothstep(POM_GRAZE_LO, POM_GRAZE_HI, Vt.z));
        float lambda_world_m;
        float pom_drive;
        float depth_uv = pom_depth_uv(lambda_world_m, pom_drive);
        // ROUND 23: the SAME drive-independent rail that froze the top of the slider on the fused
        // path (full rationale and the arithmetic live at that site in pbr_fused.glsl — one copy of
        // the explanation, two copies of the code). Multiplied by the same pom_drive here to honour
        // this path's existing "same law as the fused path" contract: the owner tests this branch as
        // the "PBR seul" preset, so leaving it un-scaled would make the two presets disagree at
        // slider max — exactly the half-fix this round is about.
        // ROUND 26 D2: `* pom_drive` removed here too — the two paths must agree (see
        // pbr_helpers.glsl's POM_MAX_FEATURE_FRAC block for the full arithmetic).
        float pom_cap = min(POM_MAX_TAN * depth_uv,
                            POM_MAX_FEATURE_FRAC * lambda_world_m *
                                max(u_pbr_uv_per_m, 0.02));
        // lighting-legacy-purge (2026-09-11) : u_pbr_bisect RETIRE, valeur livree figee a 0 (le repli round-20 n'etait jamais pris).
        // ROUND 22: identical sqrt(drive) step scaling as the fused path (1.0x at rel 1), so the
        // deeper field is resolved instead of stair-stepped. Loop bound below raised to 64.
        float n_layers = clamp(mix(28.0, 10.0, clamp(Vt.z, 0.0, 1.0)) * sqrt(pom_drive), 8.0, 64.0);
        vec2 P = (Vt.xy / vz) * depth_uv * pom_graze;
        float Plen = length(P);
        if (Plen > pom_cap) P *= pom_cap / Plen;
        if (Plen > 1e-6) {
          vec2 duv_step = P / n_layers;
          float layer_d = 1.0 / n_layers;
          float cur_d = 0.0;
          // hnorm(), matching the fused path: a map that only spans 0.18 of the 0-1 range would
          // otherwise march against a nearly-constant depth field and read flat. This branch was
          // the only POM still comparing against the RAW texel, and the owner tests it as the
          // "PBR seul" preset — the checkerboard has to read here too.
          float map_d = pom_carve(textureLod(tex_PBR_H, uv, 0.0).r);
          float prev_map_d = map_d;
          for (int i = 0; i < 64; i++) {  // ROUND 22: bound raised for the sqrt(drive) step count
            if (cur_d >= map_d || float(i) >= n_layers) {
              break;
            }
            uv -= duv_step;
            prev_map_d = map_d;
            map_d = pom_carve(textureLod(tex_PBR_H, uv, 0.0).r);
            cur_d += layer_d;
          }
          // secant refine between the last two samples for a smooth intersection
          float after = map_d - cur_d;
          float before = prev_map_d - (cur_d - layer_d);
          float w = clamp(before / max(before - after, 1e-5), 0.0, 1.0);
          uv += duv_step * (1.0 - w);
          // ROUND 22 COVERAGE: the march actually ran here (see the fused path).
          // lighting-legacy-purge (2026-09-11) : u_pbr_displacement RETIRE, valeur livree figee a 1 (PARALLAX).
          f_disp_cover = 1.0;
        }
      }
      vec3 N = Nsurf;
      if ((u_pbr_mode & 1) != 0 && u_pbr_debug != 7) {
        vec3 nm = texture(tex_PBR_N, uv).xyz * 2.0 - 1.0;
        nm.y *= u_pbr_mat.w;  // Gpbr-per-texture-materials: espace de la normal map, +1 OpenGL /
                              // -1 DirectX. Etait suppose OpenGL pour TOUTES les textures
                              // indistinctement. Avant la reconstruction de Z du bit 128, comme
                              // dans le chemin fusionne.
        // Grecharged-managed-assets: two-channel (X/Y) normal from a compressed pack — rebuild Z
        // before the gradient decode, exactly as the fused path does.
        if ((u_pbr_mode & 128) != 0) {
          nm = vec3(nm.xy, sqrt(max(1.0 - dot(nm.xy, nm.xy), 0.0)));
        }
        // Same DC-removed surface-gradient decode as the fused path above (the constant-tilt
        // plate defect is a property of the MAPS, so the rt-OFF "bidon" fallback carries it too;
        // the owner's PBR-only preset showed the identical plates). The path is otherwise
        // untouched — it stays the standalone fallback the owner accepted.
        // lighting-legacy-purge (2026-09-11) : u_pbr_bisect RETIRE, valeur livree figee a 0
        // (repere UV stable + retrait de la composante continue, tous deux toujours actifs).
        vec3 sTn = Tn, sBn = Bn;
        stable_frame(Nsurf, sTn, sBn);
        vec2 sg = clamp(nm.xy / max(nm.z, 0.05), vec2(-4.0), vec2(4.0));
        sg -= u_pbr_normal_dc;
        sg = clamp(sg * u_pbr_normal_strength, vec2(-24.0), vec2(24.0));  // ROUND 22, see fused path
        nm = normalize(vec3(sg, 1.0));
        N = normalize(mat3(sTn, sBn, Nsurf) * nm);
        // GLASS-PANE fix (owner preset report 2026-07-23, same defect on the PBR ONLY
        // preset = this rt-OFF path): slide back to the face horizon instead of the old
        // hard snap to the base normal — the tangential map grain survives at grazing angles, so
        // the specular follows the material texture, not the flat polygon.
        float snd = dot(N, Nsurf);
        if (snd < 0.04) N = normalize(N + Nsurf * (0.04 - snd));
      }
      // Albedo re-sampled at the (possibly POM-offset, tiled) UV; the initial s.tex0
      // sample keeps supplying alpha for the legacy discard product below.
      vec4 T0p = texture(tex_T0, uv);
      vec3 albedo = pow(T0p.rgb, vec3(2.2));
      // REOPEN #6: missing _roughness => ROUGH (matte), never smooth — a smooth default is the
      // exact cause of the plastic sheen the owner reported on the PBR-ONLY preset.
      // Gpbr-per-texture-materials: memes deux boutons que le chemin fusionne (repli sans map,
      // facteur sur la map liee). Defauts (0.9, x1.0) = les constantes ecrites ici auparavant.
      float rough = (u_pbr_mode & 2) != 0 ? texture(tex_PBR_R, uv).r * u_pbr_mat2.x : u_pbr_mat.x;
      float metal = (u_pbr_mode & 4) != 0 ? texture(tex_PBR_M, uv).r * u_pbr_mat2.y : u_pbr_mat.y;
      float ao    = (u_pbr_mode & 8) != 0 ? texture(tex_PBR_AO, uv).r : 1.0;
      float NdV = max(dot(N, V), 1e-4);
      // GLASS-PANE fix (owner preset report 2026-07-23): the PBR ONLY preset showed the
      // same glass sheet — this rt-OFF branch still ran the pre-fix BRDF (plain Schlick
      // Fresnel with a 1.0 grazing ceiling + separable-k G, no min-rough clamp). Apply
      // the same industry pieces the fused branch got: min perceptual roughness 0.045,
      // roughness-aware Fresnel ceiling max(1-rough, F0) (Fdez-Aguera), and the
      // height-correlated Smith visibility term (contains the 1/(4 NdV NdL)).
      rough = clamp(rough, 0.045, 1.0);
      float a = max(rough * rough, 0.002);
      float a2 = a * a;
      vec3 F0 = mix(vec3(u_pbr_mat.z), albedo, metal);  // Gpbr-per-texture-materials: reflectance
      vec3 Fceil = max(vec3(1.0 - rough), F0);
      // REOPEN #6 MATTE-DIELECTRIC DEFAULT (owner sees the same glass on the PBR-ONLY preset):
      // rough dielectrics reflect ~nothing — drive the direct GGX + env reflection toward ~0 by
      // roughness so this rt-OFF fallback is matte too. Only smooth/metal texels keep a highlight.
      float matte_gate = max(1.0 - smoothstep(0.30, 0.60, rough), metal);
      // Round-4 mandate B: the shared sun shadow-map factor computed above.
      float shadow = sm_shadow;
      // Round-4bis mandate E: baked weight. The u_pbr_direct diffuse damping is the
      // double-dose control against the baked sun; as the baked term fades out the
      // realtime sun must carry the full diffuse load again.
      float bakedw = clamp(u_pbr_baked_weight, 0.0, 1.0);
      float direct_diff_scale = mix(1.0, u_pbr_direct, bakedw);
      // Round-4 multi-light accumulation: sum the Cook-Torrance direct response of every
      // non-black light in light-group 0 (soleil + lune verte + fill). D/G/F math is
      // identical to the old single-sun path; kd/F depend on VdH so they're per-light.
      vec3 direct = vec3(0.0);
      vec3 spec_sum = vec3(0.0);   // for viz mode 5 (accumulated spec)
      vec3 direct12 = vec3(0.0);   // for viz mode 13 (lights 1+2 only = moon/fill isolation)
      for (int i = 0; i < 3; i++) {
        vec3 lc = u_pbr_light_color[i];
        if (dot(lc, vec3(1.0)) <= 1e-5) {
          continue;  // black / disabled light
        }
        vec3 L = u_pbr_light_dir[i];
        vec3 H = normalize(L + V);
        float NdL = max(dot(N, L), 0.0);
        float NdH = max(dot(N, H), 0.0);
        float VdH = max(dot(V, H), 0.0);
        float dd = NdH * NdH * (a2 - 1.0) + 1.0;
        float D = a2 / (3.14159265 * dd * dd);
        float gv = NdL * sqrt(NdV * NdV * (1.0 - a2) + a2);
        float gl = NdV * sqrt(NdL * NdL * (1.0 - a2) + a2);
        float Vis = 0.5 / max(gv + gl, 1e-4);
        vec3 F = F0 + (Fceil - F0) * pow(1.0 - VdH, 5.0);
        vec3 spec = D * Vis * F;
        vec3 kd = (vec3(1.0) - F) * (1.0 - metal);
        vec3 contrib = (kd * albedo / 3.14159265 * direct_diff_scale + spec * matte_gate) * lc * NdL;
        direct += contrib;
        spec_sum += spec * lc * NdL;
        if (i > 0) {
          direct12 += contrib;
        }
      }
      // Round-4 mandate B: shadow the ENTIRE direct term (diffuse + spec of all lights).
      // Under a roof there is no direct light at all; the indirect/baked-GI term is
      // deliberately NOT shadowed (baked already carries the level's macro occlusion).
      direct *= shadow;
      spec_sum *= shadow;
      direct12 *= shadow;
      // Indirect = baked vertex TOD color as GI. pow 2.2 linearizes it so a fragment in
      // full baked shadow (no direct term) reproduces the legacy sRGB product
      // s.baked * s.tex0 by construction — the macro luminance profile of the
      // building matches OFF wherever the sun doesn't add on top. The baked color is
      // TOD-palette-interpolated per frame, so this term still tracks the day cycle.
      vec3 baked_gi = pow(max(s.baked.rgb, vec3(0.0)), vec3(2.2));
      // Round-4bis mandate E: blend the hybrid baked-GI indirect toward the FULL-REALTIME
      // indirect (light-group ambient * AO) as bakedw -> 0. At w=0 the baked vertex color
      // no longer influences the PBR surface at all: sun+moon+fill direct is shadow-mapped
      // realtime, ambient comes from the level light-group, occlusion from the AO map.
      vec3 indirect_baked = albedo * baked_gi * ao * u_pbr_indirect;
      vec3 indirect_rt = albedo * u_pbr_ambient * ao;
      vec3 indirect = mix(indirect_rt, indirect_baked, bakedw);
      indirect *= sao;  // lighting-ao-indirect : AO d'ecran sur le seul indirect, en lineaire
      ao_applied = true;
      vec3 lit = direct + indirect;
      // PLAYTEST#1 #3: LOCAL environment IBL specular — the reflection consumer, applied ONLY on
      // genuinely reflective materials (this is the Cook-Torrance PBR path with real metal/roughness).
      // Prefiltered probe cube at the roughness mip, weighted by the roughness-aware env Fresnel: a
      // dielectric (F0~0.04) barely reflects except at grazing angles, metal (F0~albedo) reflects
      // strongly + colored. Never a flat grey wash on non-reflective surfaces. AO-occluded.
      // (§2.4) le consommateur du cube de sondes est retire avec la grille : garde morte.
      color.rgb = pow(max(lit * u_pbr_exposure, vec3(0.0)), vec3(1.0 / 2.2));
      if (u_pbr_debug == 1) {
        color.rgb = T0p.rgb;
      } else if (u_pbr_debug == 2) {
        color.rgb = Ngeo * 0.5 + 0.5;
      } else if (u_pbr_debug == 3) {
        color.rgb = N * 0.5 + 0.5;
      } else if (u_pbr_debug == 4) {
        color.rgb = vec3(rough);
      } else if (u_pbr_debug == 5) {
        color.rgb = pow(max(spec_sum * u_pbr_exposure, vec3(0.0)), vec3(1.0 / 2.2));
      } else if (u_pbr_debug == 6) {
        color.rgb = vec3(ao);
      } else if (u_pbr_debug == 9) {
        color.rgb = vec3(texture(tex_PBR_H, uv).r);
      } else if (u_pbr_debug == 10) {
        color.rgb = pow(max(indirect * u_pbr_exposure, vec3(0.0)), vec3(1.0 / 2.2));
      } else if (u_pbr_debug == 11) {
        color.rgb = pow(max(direct * u_pbr_exposure, vec3(0.0)), vec3(1.0 / 2.2));
      } else if (u_pbr_debug == 12) {
        // Round-4 mandate B: sun shadow factor viz (1=lit, 0=shadowed).
        color.rgb = vec3(shadow);
      } else if (u_pbr_debug == 13) {
        // Round-4: direct contribution of lights 1+2 ONLY (moon/fill isolation viz).
        color.rgb = pow(max(direct12 * u_pbr_exposure, vec3(0.0)), vec3(1.0 / 2.2));
      } else if (u_pbr_debug == 14) {
        // Shadow-space debug: R/G = shadow-map UV, B = in-box flag.
        color.rgb = vec3(fract(sm_dbg_suv.x), fract(sm_dbg_suv.y), sm_dbg_inbox);
      } else if (u_pbr_debug == 15) {
        // Shadow-space depth debug: gray = suv.z (light-space depth of this fragment).
        color.rgb = vec3(clamp(sm_dbg_suv.z, 0.0, 1.0));
      } else if (u_pbr_debug == 16) {
        // Raw map depth the receiver reads at this fragment's shadow UV.
        color.rgb = vec3(texture(tex_PBR_SHADOW, clamp(sm_dbg_suv.xy, 0.0, 1.0)).r);
      }
    } else if (u_pbr_shadow_on != 0) {
      // Owner clarification 2026-07-18: LEGACY receivers. The non-PBR world (the ground
      // under the hut) darkens by the calibrated legacy strength where the sun map says
      // shadowed — this is what makes the hut's shadow visible outside the PBR patch.
      // The baked painted shadows survive: a fully-baked-dark texel just gets the same
      // fractional multiply, and strength is tuned so that never crushes to black.
      color.rgb *= 1.0 - u_pbr_legacy_shadow * (1.0 - sm_shadow);
      if (u_pbr_world_relight > 0.0) {
        // MANDATE F (round-5 addendum 2): per-face N.L mood-light relight of the legacy
        // world — the same directional response actors get from the light-group, attached
        // to the geometry (stable under camera orbit by construction). In full shadow /
        // facing away, wr_indirect * baked reproduces (a calibrated fraction of) the
        // legacy product in linear space — the same round-3 trick the PBR indirect uses.
        vec3 wrn = cross(dFdx(s.P_rel), dFdy(s.P_rel));
        float wrl = length(wrn);
        vec3 wrN = wrl > 1e-6 ? wrn / wrl : vec3(0.0, 1.0, 0.0);
        vec3 wrV = -normalize(s.P_rel);
        if (dot(wrN, wrV) < 0.0) wrN = -wrN;
        vec3 wr_direct = vec3(0.0);
        for (int i = 0; i < 3; i++) {
          wr_direct += u_pbr_light_color[i] * max(dot(wrN, u_pbr_light_dir[i]), 0.0);
        }
        wr_direct *= sm_shadow * u_pbr_wr_direct;
        vec3 wr_alb = pow(s.tex0.rgb, vec3(2.2));
        vec3 wr_baked = pow(max(s.baked.rgb, vec3(0.0)), vec3(2.2));
        vec3 wr_lit = wr_alb * (wr_baked * u_pbr_wr_indirect + wr_direct);
        vec3 wr_srgb = pow(max(wr_lit * u_pbr_exposure, vec3(0.0)), vec3(1.0 / 2.2));
        color.rgb = mix(color.rgb, wr_srgb, clamp(u_pbr_world_relight, 0.0, 1.0));
        if (u_pbr_debug == 17) {
          // Viz: world-relight DIRECT term only (face contrast must follow the sun).
          color.rgb = pow(max(wr_direct * u_pbr_exposure, vec3(0.0)), vec3(1.0 / 2.2));
        }
      }
      if (u_pbr_debug == 12) {
        color.rgb = vec3(sm_shadow);
      } else if (u_pbr_debug == 14) {
        color.rgb = vec3(fract(sm_dbg_suv.x), fract(sm_dbg_suv.y), sm_dbg_inbox);
      } else if (u_pbr_debug == 15) {
        color.rgb = vec3(clamp(sm_dbg_suv.z, 0.0, 1.0));
      } else if (u_pbr_debug == 16) {
        color.rgb = vec3(texture(tex_PBR_SHADOW, clamp(sm_dbg_suv.xy, 0.0, 1.0)).r);
      }
    }
#endif
  if (!ao_applied) {
    // Chemins sans terme direct separe (rendu d'origine sous eclairage recharge, receveurs
    // legacy E) : toute la base est de l'indirect cuit, l'AO la multiplie entiere.
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
//   B = chemin exclu de la porte (B, C, E : leur indirect n'est pas `base`), compte a part.
vec4 shade(in Surface s, out float f_disp_cover, out vec3 f_disp_diag, out vec3 f_disp_diag2) {
  float sao = 1.0;
  if (u_screen_ao_on != 0) {
    sao = clamp(texture(tex_screen_ao, gl_FragCoord.xy * u_screen_ao_inv_size).r, 0.0, 1.0);
  }
  vec4 c = shade_body(s, sao, f_disp_cover, f_disp_diag, f_disp_diag2);
  if (u_ao_proof != 0) {
    float d0;
    vec3 d1, d2;
    vec4 c1 = shade_body(s, 1.0, d0, d1, d2);
    float ao_mul = (sao >= 1.0) ? 1.0 : pow(max(sao, 0.0), 1.0 / 2.2);
    vec3 delta = c.rgb - c1.rgb;
    vec3 resid = abs(delta - (ao_mul - 1.0) * s.base.rgb);
    float leak = max(resid.r, max(resid.g, resid.b));
    float changed = max(abs(delta.r), max(abs(delta.g), abs(delta.b)));
    float hit = (sao < 0.999 && changed > 1e-4) ? 1.0 : 0.0;
    float excl = (u_pbr_mode != 0 || (u_rt_light_on == 0 && u_pbr_shadow_on != 0)) ? 1.0 : 0.0;
    return vec4(leak > 2e-4 ? 1.0 : 0.0, hit, excl, 1.0);
  }
  if (u_screen_ao_on == 2) {
    c.rgb = vec3(sao);  // vue de debug : le terme d'AO tel qu'il est lu
  }
  return c;
}
// ================= @shade-model-end =================
