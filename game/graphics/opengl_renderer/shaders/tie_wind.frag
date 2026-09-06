#version 410 core

out vec4 color;

in vec4 fragment_color;
in vec3 tex_coord;
in float fogginess;
uniform sampler2D tex_T0;

uniform float alpha_min;
uniform float alpha_max;
uniform vec4 fog_color;

uniform int gfx_hack_no_tex;

#ifdef OG_PBR
// Grecharged-realtime-lighting round-3 (defect A/B): the SAME sun-only N.L path
// tfrag3.frag uses, replicated so envmap-tie base / wind-tie / shrub are sun-lit
// EVERYWHERE (not only inside the shadow zone) and receive the cast shadow. All
// these uniforms are already pushed to this program by first_tfrag_draw_setup /
// pbr_shadow_bind_receiver; absent locations are -1 (glUniform no-ops). Stripped
// entirely in a stock (non-OG_PBR) build => OFF == stock byte-identical.
in vec3 v_fringe_rel;
in vec3 v_world;  // Grecharged-lightprobes: absolute world pos (game units) for probe lookup
in vec3 v_normal;  // Grecharged-directional-ambient: smooth authored TIE normal (root-cause fix)
// ROUND 22: per-vertex tangent (xyz world, w handedness) from the TIE VAO's attribute 5, forwarded
// by tie_wind.vert. Feeds the CONTINUOUS TBN inside the shared fused chunk.
in vec4 v_tangent;
uniform int u_rt_light_on;
uniform vec3 u_rt_sun_dir;
uniform vec3 u_rt_sun_color;
// ITEM B: GREEN-STAR / MOON directional NIGHT key light (weaker than sun); u_rt_moon_color already
// carries green*intensity*(1-sun_elev) crossover weight (0 by day => golden rule).
uniform vec3 u_rt_moon_dir;
uniform vec3 u_rt_moon_color;
// Grecharged-directional-ambient: HEMISPHERE ambient (replaces the flat ~0.2 floor). u_rt_ambient_on
// = master (1 => directional sky/ground base by world normal, 0 => the legacy flat floor for A/B).
// u_rt_sky_color = up-hemisphere (sky) tint, u_rt_ground_color = down-hemisphere (ground bounce) tint;
// both track the mood/TOD ambient and already carry the ambient LEVEL (strength x gentle night-fade),
// so shadowed / away-from-sun faces regain FORM (top-lit, underside-dark) with AO fully OFF.
uniform int u_rt_ambient_on;
uniform vec3 u_rt_sky_color;
uniform vec3 u_rt_ground_color;
// Grecharged-directional-ambient ROUND 2: ambient MODEL selector + SH / IBL inputs. u_rt_ambient_model:
// 0 = HEMISPHERE, 1 = SH (L2 irradiance of the mood/TOD sky), 2 = IBL (procedural sky environment
// sampled by N). All three feed the SAME base->composite below (golden rule + night-fade automatic).
// u_rt_sh[9] = L2 SH coeffs pre-scaled C++-side by the cosine-convolution A_l/pi, so the eval returns
// reflected radiance directly. u_rt_env_zenith/horizon/ground + u_rt_sun_glow drive the IBL procedural
// sky (mean-normalized C++-side to the hemisphere mean). All read ONLY inside u_rt_light_on => OFF==stock.
uniform int u_rt_ambient_model;
// Grecharged-directional-ambient: AZIMUTHAL directional-contrast fill. u_rt_ambient_key = a tilted
// world direction (horizontal component = the sun azimuth so it tracks TOD, fixed upward tilt), NOT
// elevation-faded so it PERSISTS with the sun off. u_rt_ambient_contrast = the owner's Ambient
// Contrast control (directional SPREAD around the ambient mean, a levels/contrast notion, NOT a
// brightness scalar). base *= (1 + contrast * dot(N, key)) => faces at different horizontal
// orientations (rock bumps, the curved hut wall; N.y≈0) differ even sun-off => FORM. Read ONLY
// inside u_rt_light_on => OFF==stock.
uniform vec3 u_rt_ambient_key;
uniform float u_rt_ambient_contrast;
uniform int u_rt_flat_normal;  // Grecharged-directional-ambient A/B: 1 forces the old flat per-face normal
uniform vec3 u_rt_sh[9];
uniform vec3 u_rt_env_zenith;
uniform vec3 u_rt_env_horizon;
uniform vec3 u_rt_env_ground;
uniform vec3 u_rt_sun_glow;
uniform float u_rt_shadow_range;
uniform float u_rt_shadow_res;
// ROUND-5 (mirror of tfrag3.frag): cast-shadow RESIDUAL — brightness a fully-occluded
// fragment keeps (~0.2 clear-sky, 0.0 == black). Fed as (1 - Shadow Strength); CAST-SHADOW
// term only, the N.L dark side stays black.
uniform float u_rt_shadow_residual;
// Grecharged-realtime-lighting ROUND 7: NIGHT SUN-FADE (mirror of tfrag3.frag). Gates the
// direct-sun term by the REAL sun elevation (sky-parms visible-sun up-component), NOT the
// mood current-sun: 1 = sun up, smooth ramp near the horizon, 0 = below horizon (night) =>
// direct sun (and any mood tint) vanishes, leaving ONLY the ~0.2 floor. Identical across all
// four world shaders so nothing stays lit at night.
uniform float u_rt_sun_elev;
// Item 1 (owner playtest #3): which sun the single shadow map was rendered from — 0 = yellow
// sun (day), 1 = green sun (night). The occlusion attenuates the MATCHING directional term.
uniform int u_rt_shadow_light;
// OWNER PLAYTEST #4: shadow-handoff confidence [0..1] — fades the cast shadow near the yellow<->green
// elevation crossover / both-suns overlap so the single-map ownership flip is stepless (golden rule).
uniform float u_rt_shadow_conf;
// ROUND-5: 16-tap Poisson disk for the wide-penumbra soft PCF (replaces the round-4 grid
// that aliased the shadow-texel lattice => staircase). Rotated per fragment in the PCF loop.
const vec2 RT_POISSON16[16] = vec2[](
  vec2(-0.94201624, -0.39906216), vec2(0.94558609, -0.76890725), vec2(-0.094184101, -0.92938870),
  vec2(0.34495938, 0.29387760),   vec2(-0.91588581, 0.45771432), vec2(-0.81544232, -0.87912464),
  vec2(-0.38277543, 0.27676845),  vec2(0.97484398, 0.75648379),  vec2(0.44323325, -0.97511554),
  vec2(0.53742981, -0.47373420),  vec2(-0.26496911, -0.41893023),vec2(0.79197514, 0.19090188),
  vec2(-0.24188840, 0.99706507),  vec2(-0.81409955, 0.91437590), vec2(0.19984126, 0.78641367),
  vec2(0.14383161, -0.14100790));
// ROUND 22 (owner defect A: "la plupart des endroits n'ont toujours pas de displacement du
// tout"). This shader used to declare only the six sun-shadow uniforms by hand and had NO PBR
// material inputs at all, so every wind-animated TIE was structurally incapable of showing relief.
// The shared chunk brings in the WHOLE u_pbr_* block (mode, maps 11-17, relief tunables, bisect,
// displacement, the shadow uniforms it used to duplicate, u_pbr_debug) — one declaration site for
// tfrag3 / shrub / tie_wind / etie_base, so the four can never drift apart again. All of it is
// already pushed to THIS program by first_tfrag_draw_setup (it takes the ShaderId), and
// glGetUniformLocation returns -1 for anything a program does not use, so nothing new is bound.
#include "pbr_uniforms.glsl"
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
// Grecharged-directional-ambient ROUND 2 — IBL: a procedural SKY ENVIRONMENT sampled by the normal
// (prefiltered sky irradiance). Vertical bands ground->warm HORIZON->zenith, plus a soft sun-ward glow
// (elevation-faded C++-side => 0 at night). Sharper horizon + defined glow than the L2 SH => reads as
// the actual sky, richest of the three. Golden-rule/night-safe via the shared composite below.
vec3 rt_ibl_ambient(vec3 d) {
  float u = clamp(d.y, -1.0, 1.0);
  vec3 up = mix(u_rt_env_horizon, u_rt_env_zenith, smoothstep(0.0, 0.55, u));
  vec3 dn = mix(u_rt_env_horizon, u_rt_env_ground, smoothstep(0.0, 0.45, -u));
  vec3 band = u >= 0.0 ? up : dn;
  float g = max(dot(d, normalize(u_rt_sun_dir)), 0.0);
  g = g * g; g = g * g;   // pow 4 soft glow lobe
  return band + u_rt_sun_glow * g;
}
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
// ROUND 22: the PBR helper library — hnorm(), the POM depth law pom_depth_uv() and its constant
// block, rt_amb_eval(), pbr_micro_shadow(), pbr_cavity(), plus the two CONTINUOUS tangent bases
// (stable_frame / frisvad_basis). Shared verbatim with tfrag3.frag, which is the whole point: the
// parallax amplitude law here is not "the same as" tfrag3's, it IS tfrag3's. Included after the
// rt_sh_ambient / rt_ibl_ambient definitions above because rt_amb_eval() calls them.
#include "pbr_helpers.glsl"
#endif


void main() {
#ifdef OG_PBR
  // ROUND 22 per-pixel displacement coverage (u_pbr_debug == 31). Now that this program has a real
  // PBR path this is no longer hardcoded 0: it is set to 1.0 exactly where the POM march actually
  // ran, by the shared fused chunk.
  float f_disp_cover = 0.0;
  // ROUND 24 DEAD-ZONE DIAGNOSTIC (u_pbr_debug == 33), filled by the shared fused chunk:
  //   R = the vertex displacement the TESSELLATION tier actually applied at this fragment, in
  //       cm/10 (|h-0.5| * amp_m * falloff*seam) — 0 means the tier moved nothing HERE.
  //   G = the final POM offset after every cap, converted to world cm/10 — 0 means the parallax
  //       tier moved nothing HERE.
  //   B = camera distance in m/40 (the driver of both LOD fades), so a dead pixel can be
  //       attributed to distance without a second capture.
  vec3 f_disp_diag = vec3(0.0);
  vec3 f_disp_diag2 = vec3(0.0);  // ROUND 24 mode 34: (tess_disp_w, |h-0.5|*2, amp_m)
#endif
  if (gfx_hack_no_tex == 0) {
    //vec4 T0 = texture(tex_T0, tex_coord);
    vec4 T0 = texture(tex_T0, tex_coord.xy);
    color = fragment_color * T0;
    // ================= @shade-model-begin =================
    // Region relevee par game/graphics/opengl_renderer/shade_proof.cpp DANS LE TEXTE QUE LE
    // PILOTE COMPILE. Tant que chaque hote porte sa propre copie, les empreintes different et
    // `shade_variants` compte les copies. L'item lighting-unify deplace cette region dans le
    // chunk partage : tous les hotes rendent alors la MEME empreinte, et la mesure rend 1.
#ifdef OG_PBR
    // Sun-only realtime lighting (mirror of tfrag3.frag): camera-independent per-face
    // world normal from v_fringe_rel derivatives, N.L from the visible-sun direction,
    // NO ambient (opposite side genuinely dark), baked OFF by default, plus the cast-
    // shadow factor (only when a shadow map is bound and this fragment is in range).
    if (u_rt_light_on != 0) {
      // Grecharged-directional-ambient ROOT-CAUSE FIX: SMOOTH per-vertex normal (v_normal) instead of
      // the flat per-face screen-derivative normal. gN kept only as outward-sign reference + fallback.
      vec3 gN = cross(dFdx(v_fringe_rel), dFdy(v_fringe_rel));
      float gNl = length(gN);
      gN = gNl > 1e-6 ? gN * (1.0 / gNl) : vec3(0.0, 1.0, 0.0);
      vec3 Vv = -normalize(v_fringe_rel);
      if (dot(gN, Vv) < 0.0) gN = -gN;
      vec3 Ns = v_normal;
      float Nsl2 = dot(Ns, Ns);
      vec3 N;
      if (u_rt_flat_normal == 0 && Nsl2 > 0.2) {
        Ns *= inversesqrt(Nsl2);
        // ===== ROUND 26, DEFECT D2 — THE FRAME'S HANDEDNESS MUST NOT DEPEND ON THE CAMERA =====
        // `dot(Ns, gN) < 0.0 ? -Ns : Ns` re-signed the smooth normal against gN — and gN had itself
        // just been forced into the CAMERA hemisphere two lines up (`if (dot(gN, Vv) < 0.0)`). So
        // the SIGN of N, and therefore the HANDEDNESS of the whole PBR frame (pbr_fused.glsl builds
        // fBuv = cross(N, fTuv) * sign(v_tangent.w)), was a function of WHERE THE CAMERA IS.
        // Crossing a face's plane flips the bitangent, which flips both the V axis the normal map
        // is decoded in and the V component of the parallax offset: the relief inverts and the
        // motif jumps. This is the SAME ROOT as the rare polarity flips of round-22 defect C, and
        // after this round it is the ONLY camera dependency left anywhere in the frame — the
        // tangent is the per-vertex MikkTSpace attribute and the fallback is frisvad_basis(N),
        // both anchored to geometry (no screen-derivative TBN survives in any of these shaders).
        // The mesh-consolidation phase made the MESH DATA the authority on orientation, so the
        // consolidated normal is now used AS AUTHORED — exactly what shrub.frag already does. The
        // camera-hemisphere flip survives only on gN, which is the fallback for geometry that has
        // no authored normal to be an authority.
        // Bisect bit 2 restores the old camera-signed behaviour for a same-boot A/B.
        N = ((u_pbr_bisect & 2) != 0 && dot(Ns, gN) < 0.0) ? -Ns : Ns;
      } else {
        N = gN;
      }
      vec3 L = normalize(u_rt_sun_dir);
      float ndl = max(dot(N, L), 0.0);
      float shadow = 1.0;
      if (u_pbr_shadow_on != 0) {
        float rng = u_rt_shadow_range > 1.0 ? u_rt_shadow_range : 150.0;
        float res = u_rt_shadow_res > 1.0 ? u_rt_shadow_res : 2048.0;
        float texel = 1.0 / res;
        float texel_world = (2.0 * rng) / res;
        float noff = texel_world * mix(1.5, 5.0, 1.0 - ndl);
        vec3 sworld = v_fringe_rel + u_pbr_shadow_cam_delta + N * noff;
        vec4 sp = u_pbr_shadow_mvp * vec4(sworld, 1.0);
        vec3 suv = sp.xyz / sp.w * 0.5 + 0.5;
        if (suv.x > 0.002 && suv.x < 0.998 && suv.y > 0.002 && suv.y < 0.998 && suv.z < 1.0) {
          float ref = suv.z - (0.0010 + u_pbr_shadow_bias);
          // ROUND-4 item #3 ANTI-PIXELATION: distance-adaptive PCF radius grows with camera
          // distance so far cast shadows are smoothed (never pixelated in the FOV), near stays
          // crisp; a per-fragment rotation dithers the 9-tap grid (smooth even at Very Low 512).
          // ROUND-5 (owner: round-4 grid blur FAILED — distant shadows STILL staircased):
          // 16-tap Poisson disk (a grid aliases the shadow-texel lattice), rotated per
          // fragment, penumbra radius grows strongly with distance => wide soft far shadow,
          // crisp near. No staircase anywhere in the FOV.
          float sdist = length(v_fringe_rel);
          float soft = 1.5 + 18.0 * smoothstep(0.0, rng, sdist);
          float rr = texel * soft;
          float hang = fract(sin(dot(gl_FragCoord.xy, vec2(12.9898, 78.233))) * 43758.5453) * 6.2831853;
          vec2 hc = vec2(cos(hang), sin(hang));
          mat2 hrot = mat2(hc.x, -hc.y, hc.y, hc.x);
          float sm = 0.0;
          for (int i = 0; i < 16; i++) {
            vec2 o = hrot * (RT_POISSON16[i] * rr);
            sm += ref <= texture(tex_PBR_SHADOW, suv.xy + o).r ? 1.0 : 0.0;
          }
          sm *= (1.0 / 16.0);
          float edge_fade = 1.0 - smoothstep(rng * 0.72, rng * 0.96, length(v_fringe_rel));
          shadow = mix(1.0, sm, edge_fade);
        }
      }
      // ROUND-5 CORRECTION (owner, correct physics): the residual ~0.2 is a UNIFORM sky-fill
      // FLOOR, not a cast-shadow-only term. An away-from-sun face is skylight-only EXACTLY
      // like a cast shadow, so BOTH keep ~0.2 (nothing pure black). floor = 1 - Shadow
      // Strength; the sun adds on top gated by N.L and the cast-shadow occlusion:
      //   final = floor + (1 - floor) * sun_color * max(N.L,0) * occ.
      // ROUND-7 NIGHT FADE: * u_rt_sun_elev so the direct sun (and any mood tint) goes to 0 at
      // night. Identical in all four world shaders.
      // Item 1: single shadow map driven by the key sun (u_rt_shadow_light: 0=yellow day / 1=green night).
      // Apply the occlusion ONLY to that light's own term; the other stays unshadowed (its map isn't drawn).
      shadow = mix(1.0, shadow, u_rt_shadow_conf);  // playtest #4: fade shadow at the yellow<->green handoff (stepless)
      float sun_occ  = (u_rt_shadow_light == 1) ? 1.0 : shadow;  // yellow-sun cast shadow (or 1 at night)
      float moon_occ = (u_rt_shadow_light == 1) ? shadow : 1.0;  // green-sun cast shadow (night)
      float sun_scalar = ndl * sun_occ * u_rt_sun_elev;  // N.L * cast-shadow occlusion * night-fade
      // ===================================================================================
      // OWNER FINAL ARCHITECTURE (2026-07-21, "voilà le plan") — BAKED-MODULATION.
      // The baked (fragment_color * T0, already sitting in `color`) is NEVER removed: it is
      // the base and the realtime layer only INFLUENCES it, MULTIPLICATIVELY (a x-k shift
      // preserves the baked's own ratios => contrast preserved BY CONSTRUCTION, never the
      // additive/flattening wash):
      //   sun-LIT  (N.L toward the sun AND not cast-shadowed): x lit_boost (>1) + hue/sat
      //            pushed slightly TOWARD THE SUN's tint (warm yellow by day; the green sun
      //            uses its own green chroma at night);
      //   SHADOWED (faces away from the sun OR under a cast shadow): x shadow_mul (<1) +
      //            slightly COOL hue.
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
      // =================================================================================
      // ROUND 22 — THE PORT (owner defect A). Exactly the shape tfrag3.frag has: the fused
      // Cook-Torrance + POM arm sits IN FRONT of the accepted baked-modulation arm and is
      // taken only when this draw actually bound PBR material maps (u_pbr_mode != 0). So:
      //   rt OFF            -> never reaches here at all               == stock
      //   rt ON  + pbr OFF  -> u_pbr_mode == 0 -> the else-if below    == accepted look
      //   rt ON  + pbr ON   -> the shared fused chunk                  == tfrag3's path
      //
      // ---- PBR FUSED CHUNK CONTRACT (what pbr_fused.glsl reads out of this scope) ----
      //   N        smooth outward world normal        (built above from v_normal / gN)
      //   Vv       surface -> camera, unit            (above)
      //   L        surface -> yellow sun, unit        (above)
      //   sun_occ  yellow-sun cast-shadow visibility  (above)
      //   moon_occ green-sun cast-shadow visibility   (above)
      //   T0       texture(tex_T0, tex_coord.xy)      (top of main)
      //   f_disp_cover  written back = 1.0 where the POM march really ran (debug 31)
      //   varyings fragment_color / tex_coord / v_fringe_rel / v_tangent
      //   uniforms the whole u_pbr_* + u_rt_* set, and the helper functions from
      //            pbr_helpers.glsl + this file's rt_sh_ambient / rt_ibl_ambient.
      // ADAPTER: tie_wind needs NO substitutions — the TIE VAO already binds the per-vertex
      // tangent at attribute location 5 (Tie3.cpp), tie_wind.vert now declares it and
      // forwards v_tangent, and every other name above already existed here under the same
      // meaning. The one tfrag-only input the chunk does NOT use is v_fringe_rel's fringe
      // fade (u_fringe_fade lives in tfrag3.frag's main, outside the chunk).
      // DISPLACEMENT TIER: parallax (POM). u_pbr_tess_active is 0 for this program (only
      // TFRAG3_TESS gets 1 in first_tfrag_draw_setup), so the chunk's own gate runs the
      // march here — with the IDENTICAL pom_depth_uv() amplitude law the tess tier uses.
      // =================================================================================
      if (u_pbr_mode != 0) {
        float tess_disp_w = 0.0;  // ROUND 23 adapter: this program has no tessellation path
        #include "pbr_fused.glsl"
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
        // luma-neutral chromas: the tint shifts hue/saturation only; lit_boost / shadow_mul
        // alone set the energy (guarded divisions; a zero-color sun also has weight ~0).
        vec3 sun_ch = u_rt_sun_color / max(dot(u_rt_sun_color, vec3(0.299, 0.587, 0.114)), 1e-3);
        vec3 moon_ch = u_rt_moon_color / max(dot(u_rt_moon_color, vec3(0.299, 0.587, 0.114)), 1e-3);
        const vec3 RT_COOL = vec3(0.896, 1.001, 1.265);  // luma-normalized cool (blue-shifted) chroma
        vec3 lit_mul_y = u_rt_lit_boost * mix(vec3(1.0), sun_ch, clamp(u_rt_tint_lit, 0.0, 1.0));
        vec3 lit_mul_g = u_rt_lit_boost * mix(vec3(1.0), moon_ch, clamp(u_rt_tint_lit, 0.0, 1.0));
        vec3 shd_mul = u_rt_shadow_mul * mix(vec3(1.0), RT_COOL, clamp(u_rt_tint_shadow, 0.0, 1.0));
        vec3 mod_y = mix(shd_mul, lit_mul_y, lit_y);
        vec3 mod_g = mix(shd_mul, lit_mul_g, lit_g);
        vec3 rt_mod = mix(vec3(1.0), mod_y, w_y) * mix(vec3(1.0), mod_g, w_g);
        color.rgb = max(color.rgb * rt_mod, vec3(0.0));
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
#endif
    // ================= @shade-model-end =================
  } else {
    color = fragment_color/2.0;
  }

  if (color.a < alpha_min || color.a > alpha_max) {
    discard;
  }

  color.rgb = mix(color.rgb, fog_color.rgb, clamp(fogginess * fog_color.a, 0.0, 1.0));
#ifdef OG_PBR
  // ===== ROUND 22 PER-PIXEL SCREEN-COVERAGE INSTRUMENTATION (owner defect A step 1) =====
  // Program tag (30) and displacement tag (31). See tfrag3.frag for the full rationale.
  // tie_wind = cyan (unchanged — the coverage measurement scripts key on these exact colours).
  // ROUND 22 UPDATE: this renderer now HAS a PBR/displacement path, so tag 31 reports the real
  // per-pixel flag the fused chunk sets instead of the hardcoded 0.0 it used while it had none.
  // color.a is NEVER touched and this sits AFTER the alpha discard AND after the fog mix, so the
  // discard keeps rejecting the same fragments and the tag reaches the framebuffer unblended.
  if (u_pbr_debug == 30) {
    color.rgb = vec3(0.0, 1.0, 1.0);
  } else if (u_pbr_debug == 31) {
    color.rgb = vec3(f_disp_cover);
  } else if (u_pbr_debug == 32) {
    // ROUND 24 DENOMINATOR MASK (owner's own framing: "la geometrie ou c'est sense etre le cas,
    // car utilise une texture qui a les maps"). White iff THIS fragment's material has a HEIGHT
    // map bound — nothing else. Deliberately independent of the displacement setting, the tier,
    // the distance and the amplitude, so it is a pure denominator and can never be inflated by
    // the very capability the numerator is supposed to measure.
    color.rgb = ((u_pbr_mode & 16) != 0) ? vec3(1.0) : vec3(0.0);
  } else if (u_pbr_debug == 33) {
    color.rgb = f_disp_diag;
  } else if (u_pbr_debug == 34) {
    color.rgb = f_disp_diag2;
  }
#endif
}