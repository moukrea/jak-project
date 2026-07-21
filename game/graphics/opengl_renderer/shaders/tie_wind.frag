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
uniform int u_pbr_shadow_on;
uniform mat4 u_pbr_shadow_mvp;
uniform vec3 u_pbr_shadow_cam_delta;
uniform highp sampler2D tex_PBR_SHADOW;
uniform float u_pbr_shadow_bias;
uniform int u_pbr_debug;
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
// Grecharged-lightprobes PLAYTEST#1: the LOCAL probe SH is evaluated PER-PIXEL here from the dense
// hardware-trilinear 3D SH grid at the fragment's world position v_world. This fixes #4 (the ~4 m
// probe-cell "damier" the old per-vertex eval showed on the flat ground) and #1 (interiors muted):
// the interior-mask lives in u_rt_probe_l1a.a (255 indoors / 0 outdoors); where a fragment is indoors
// we SNAP toward its CONTAINING cell (point-sampled) so the smooth trilinear no longer bleeds bright
// exterior light through the walls -> the room keeps its true LOCAL light.
uniform int u_rt_probe_on;
uniform vec3 u_rt_probe_origin;
uniform float u_rt_probe_inv_cell;
uniform vec3 u_rt_probe_dims;
uniform float u_rt_probe_range;
uniform sampler3D u_rt_probe_dc;    // DC.rgb + validity.a
uniform sampler3D u_rt_probe_l1a;   // L1 coeff1 .rgb + interior-mask .a
uniform sampler3D u_rt_probe_l1b;   // L1 coeff2 .rgb
uniform sampler3D u_rt_probe_l1c;   // L1 coeff3 .rgb
uniform int u_rt_probe_reflections;
uniform float u_rt_probe_strength;
uniform samplerCube u_rt_probe_cube;   // prefiltered LOCAL reflection env (nearest anchor)
// REOPEN 2026-07-21 — BAKED-DETAIL RE-INJECTION. u_rt_detail gates the layer (default ON,
// set by LightProbeGrid; 0 = the pre-reopen flat composite for A/B). u_rt_detail_norm
// recenters the baked/lowpass ratio (prop debug.opengoal.rt.detailnorm, percent; 1.0 =
// the units-matched default: fragment_color/2 and the probe SH are both in stored LUT units).
uniform int u_rt_detail;
uniform float u_rt_detail_norm;
uniform float u_rt_sun_boost;
// OWNER FINAL ARCHITECTURE (2026-07-21) — BAKED-MODULATION amplitude tunables (percent props
// debug.opengoal.rt.litboost / .shadowmul / .tintlit / .tintshadow / .greenamp, set in
// LightProbeGrid::bind_and_upload BEFORE its probe early-out so they live independent of the
// probe world-projection state).
uniform float u_rt_lit_boost;    // sun-lit multiplicative brighten, > 1 (default 1.15)
uniform float u_rt_shadow_mul;   // shadowed multiplicative darken, < 1 (default 0.65)
uniform float u_rt_tint_lit;     // lit hue push toward the owning sun's chroma (default 0.12)
uniform float u_rt_tint_shadow;  // shadow hue push toward cool/blue (default 0.12)
uniform float u_rt_green_amp;    // green-sun amplitude scale vs the day sun (default 0.60)

// SH (DC + L1) -> ambient radiance toward N from 4 already-decoded coeffs (same Y-basis + Al cosine
// convolution as rt_sh_ambient(): DC*Y0 + c1*Y1(N.y) + c2*Y1(N.z) + c3*Y1(N.x)).
// OWNER #3 UNIFICATION: the AMBIENT MODEL selector (u_rt_ambient_model) is the EVALUATION FIDELITY
// of this same PROBE data (probe-fed), not a separate analytic system: 0 HEMISPHERE = DC + the
// VERTICAL L1 band only (cheapest local eval, sky-over-ground character), 1 SH = full L1, 2 IBL =
// full L1 + the prefiltered probe CUBE as the ambient env term (added at the call site). The
// analytic rt_sh_ambient()/rt_ibl_ambient() estimation survives ONLY as the no-probe fallback.
vec3 rt_probe_eval(vec3 dcrgb, vec3 c1, vec3 c2, vec3 c3, vec3 N, int model) {
  vec3 amb = dcrgb * 0.282095;
  if (model == 0) amb += c1 * (0.488603 * N.y);
  else            amb += c1 * (0.488603 * N.y) + c2 * (0.488603 * N.z) + c3 * (0.488603 * N.x);
  return max(amb, vec3(0.0));
}

// PER-PIXEL local probe SH with CONTAINMENT. Returns local ambient radiance; w = grid coverage;
// interior_o = the trilinear interior fraction at this point (0 outdoors .. 1 deep inside a room),
// used by the composition: indoors the baked probe energy is already almost entirely INDIRECT.
vec3 rt_probe_sh(vec3 wp, vec3 N, out float w, out float interior_o) {
  w = 0.0;
  interior_o = 0.0;
  if (u_rt_probe_on == 0) return vec3(0.0);
  vec3 gc = (wp - u_rt_probe_origin) * u_rt_probe_inv_cell;   // grid coords, in cells
  // +0.5: probe (i,j,k) is stored at texel (i,j,k) whose CENTER is (i+0.5)/dims, and origin is
  // the CENTER of cell 0 -> gc==i at probe i. Without the half-texel shift the whole field samples
  // ~half a cell (~2 m) off (part of the visible grid pattern).
  vec3 uvw = (gc + vec3(0.5)) / u_rt_probe_dims;              // normalized 3D-tex coords, texel-center aligned
  if (any(lessThan(uvw, vec3(0.0))) || any(greaterThan(uvw, vec3(1.0)))) return vec3(0.0);
  float R = u_rt_probe_range;
  // (a) SMOOTH hardware-trilinear sample -> seamless per-pixel ambient (no ground damier).
  vec4 dc = texture(u_rt_probe_dc, uvw);
  w = dc.a;
  if (w < 0.02) { w = 0.0; return vec3(0.0); }
  vec4 l1a = texture(u_rt_probe_l1a, uvw);
  vec3 c1 = (l1a.rgb - 0.5) * R;
  vec3 c2 = (texture(u_rt_probe_l1b, uvw).rgb - 0.5) * R;
  vec3 c3 = (texture(u_rt_probe_l1c, uvw).rgb - 0.5) * R;
  vec3 amb = rt_probe_eval(dc.rgb * R, c1, c2, c3, N, u_rt_ambient_model);
  // (b) CONTAINMENT: l1a.a is the interior fraction around this point (trilinearly interpolated). Where
  // the fragment is indoors, snap toward the CONTAINING cell's own SH (point-sampled, no trilinear) so
  // the exterior light the smooth blend pulled through the walls is rejected -> interiors stay local.
  float interior = l1a.a;
  interior_o = clamp(interior, 0.0, 1.0);
  if (interior > 0.02) {
    // CONTAINMENT (industry-standard validity-weighted trilinear, like irradiance-volume renderers):
    // redo the trilinear over the 8 surrounding lattice corners but keep ONLY corners whose exact
    // per-cell flag (texelFetch, no filtering) says INTERIOR, renormalizing the weights. Exterior
    // probes past a wall get weight 0 -> no bleed; the weights vary continuously in space (and a
    // corner enters/leaves the set only where its weight is 0) -> NO seams inside multi-cell rooms,
    // unlike a nearest-probe snap which would be piecewise-constant.
    ivec3 dim = ivec3(u_rt_probe_dims);
    ivec3 i0 = ivec3(floor(gc));
    vec3 fpos = clamp(gc - vec3(i0), 0.0, 1.0);
    vec3 sum = vec3(0.0);
    float wsum = 0.0;
    for (int k = 0; k < 8; ++k) {
      ivec3 o = ivec3(k & 1, (k >> 1) & 1, (k >> 2) & 1);
      ivec3 ci = clamp(i0 + o, ivec3(0), dim - ivec3(1));
      vec3 tw = mix(1.0 - fpos, fpos, vec3(o));
      float wk = tw.x * tw.y * tw.z;
      if (wk < 1e-4) continue;
      vec4 ca = texelFetch(u_rt_probe_l1a, ci, 0);
      if (ca.a < 0.5) continue;                        // exterior/invalid corner: no wall bleed
      vec4 cdc = texelFetch(u_rt_probe_dc, ci, 0);
      if (cdc.a < 0.5) continue;
      vec3 kc1 = (ca.rgb - 0.5) * R;
      vec3 kc2 = (texelFetch(u_rt_probe_l1b, ci, 0).rgb - 0.5) * R;
      vec3 kc3 = (texelFetch(u_rt_probe_l1c, ci, 0).rgb - 0.5) * R;
      sum += wk * rt_probe_eval(cdc.rgb * R, kc1, kc2, kc3, N, u_rt_ambient_model);
      wsum += wk;
    }
    if (wsum > 1e-3) {
      amb = mix(amb, sum / wsum, smoothstep(0.35, 0.85, interior));
    }
  }
  return amb;
}
#endif


void main() {
  if (gfx_hack_no_tex == 0) {
    //vec4 T0 = texture(tex_T0, tex_coord);
    vec4 T0 = texture(tex_T0, tex_coord.xy);
    color = fragment_color * T0;
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
        N = dot(Ns, gN) < 0.0 ? -Ns : Ns;
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
      if (u_rt_probe_on == 0) {
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
      } else {
      // ======= "BAKED AMBIENT" curiosity path (default OFF): the pre-final probe-fed composite =======
      // Grecharged-directional-ambient: DIRECTIONAL hemisphere ambient base (sky up / ground down
      // by the world normal) replaces the flat ~0.2 floor => form in shadow with AO off. Toggle
      // OFF = the legacy flat floor. GOLDEN RULE: the direct-sun term is unchanged, so sunlit
      // surfaces are unaffected by the ambient reshaping.
      // Grecharged-directional-ambient ROUND 2: base = directional ambient irradiance sampled by the
      // world normal N via the selected MODEL (0 hemisphere / 1 SH / 2 IBL). OFF => legacy flat floor.
      vec3 base;
      if (u_rt_ambient_on == 0) {
        base = vec3(clamp(u_rt_shadow_residual, 0.0, 1.0));
      } else if (u_rt_ambient_model == 1) {
        base = rt_sh_ambient(N);
      } else if (u_rt_ambient_model == 2) {
        base = rt_ibl_ambient(N);
      } else {
        base = mix(u_rt_ground_color, u_rt_sky_color, clamp(N.y * 0.5 + 0.5, 0.0, 1.0));
      }
      base = clamp(base, 0.0, 1.0);
      // Grecharged-lightprobes + OWNER #3 UNIFICATION: where the LOCAL probe grid covers this
      // fragment, the PROBE DATA is the ambient data source and the AMBIENT MODEL above becomes its
      // EVALUATION FIDELITY (Hemisphere = probe DC + vertical band, SH = full probe L1, IBL = probe
      // SH + the prefiltered probe CUBE as the ambient env term). The analytic base computed above
      // is reachable ONLY as the no-probe fallback (grid absent / fragment outside coverage);
      // probe_w = grid coverage, fades cleanly back to the analytic base at the grid boundary.
      float probe_w = 0.0;
      float probe_int = 0.0;
      vec3 probe_pamb = vec3(0.0);
      if (u_rt_probe_on != 0) {
        vec3 pamb = rt_probe_sh(v_world, N, probe_w, probe_int);  // PER-PIXEL local SH (+containment): no damier, no wall bleed
        probe_pamb = pamb;  // smooth local SH BEFORE the IBL-cube mix: the low-pass reference for the detail ratio
        if (probe_w > 0.02) {
          if (u_rt_ambient_model == 2) {
            // IBL fidelity tier: the probe's prefiltered cube (nearest anchor) supplies the ambient
            // ENV term — sampled by the normal at a broad mip (~diffuse-convolved local env). This
            // is the probe-fed replacement of the procedural-sky rt_ibl_ambient() estimation.
            vec3 penv = textureLod(u_rt_probe_cube, N, 2.0).rgb;
            pamb = mix(pamb, penv, 0.35);
          }
          base = mix(base, clamp(pamb, 0.0, 1.0), clamp(probe_w, 0.0, 1.0) * clamp(u_rt_probe_strength, 0.0, 1.0));
        }
      }
      // AZIMUTHAL DIRECTIONAL CONTRAST — the fix for flat VERTICAL faces (rocks/walls, N.y~0) with the
      // sun OFF. A GAIN-boosted, FLOORED directional wrap toward the ambient key (sun-azimuth horizontal
      // + up-tilt, NOT elevation-faded so it PERSISTS sun-off): faces toward the key brighten as a soft
      // skylight, faces away keep a DIM FLOOR (form, NOT crushed to black => away-faces stay sculpted).
      // The 2.0 gain makes the shipped default contrast (0.9) sculpt HARD on the DEFAULT colored render
      // (0.9 alone was too subtle — the owner's repeated "still flat" complaint); the max() floor stops
      // the high-gain away-faces from clamping to pure black (which would re-flatten them). contrast 0 =>
      // shape 1 => the pure-hemisphere flat A/B reference. Golden rule intact: the direct-sun term below
      // is untouched, and base's weight vanishes as the sun saturates (sunlit byte-identical).
      if (u_rt_ambient_on != 0 && probe_w <= 0.02) {  // probe carries its OWN local directionality
        float rt_shape = 1.0 + (u_rt_ambient_contrast * 2.0) * dot(N, u_rt_ambient_key);
        base = base * max(rt_shape, 0.15);
        base = clamp(base, 0.0, 1.0);
      }
      vec3 albedo = pow(T0.rgb, vec3(2.2));
      // baked hardwired OFF (realtime ON => baked off; realtime OFF = stock legacy path above).
      // OWNER'S DEFINITIVE ADDITIVE COMPOSITE (clarification 3, 2026-07-20): the ambient base is the
      // ALWAYS-ON indirect light that carries the relief; the sun ADDS its own light on top, gated only
      // by N.L and cast-shadow visibility (sun_scalar) — NOT a screen blend. The old
      // base + (1-base)*sun converged to a FLAT albedo as the sun saturated, ERASING the ambient relief
      // on the LIT side (the owner's "additive sun blows out / re-flattens the relief" = the WIP sun that
      // looked bizarre). True ADD keeps base's normal-varying relief on BOTH the shadowed side
      // (sun_scalar->0 => ambient only) AND the lit side (ambient + sun). A C1 soft-shoulder tone-map
      // (identity below the knee, smooth asymptote to 1) stops the bright sun side from blowing to a flat
      // white while leaving the dim ambient/shadow region — far below the knee — BYTE-untouched (the
      // accepted sun-off relief is preserved exactly; sun_scalar==0 => lit==albedo*base as before).
      float moon_ndl = max(dot(N, normalize(u_rt_moon_dir)), 0.0) * moon_occ;  // green-sun N.L * its cast shadow (item 1)
      // OWNER #4 LAYERING CONTRACT (the industry-standard split): the probe ambient is the INDIRECT
      // FILL layer ONLY; the DIRECT realtime layer — the DAY SUN and the GREEN SUN/MOON, each with
      // its own N.L and its own cast-shadow occlusion (inside sun_scalar / moon_ndl) — stays fully
      // alive ON TOP at FULL strength. A cast shadow removes ONLY its sun's direct term and NEVER
      // darkens the ambient fill (ambient fills where direct doesn't reach). This both preserves the
      // sun-driven lit-vs-shadow CONTRAST (the separation == the full direct term, exactly as in the
      // accepted probe-OFF build => details/albedo not washed) and keeps BOTH suns' cast shadows
      // clearly visible with probes ON (the invisible-moon-shadow bug was ambient washing direct).
      // ENERGY (no double-count): the probe was baked from the FULL-LIT world (suns included), so as
      // an indirect fill it is scaled by RT_PROBE_IND OUTDOORS — the suns' direct share is what the
      // dynamic layer re-adds (occluded by its own moving shadows). INDOORS (probe_int -> 1) the
      // baked energy is already almost entirely indirect (the suns don't reach) so the probe is used
      // at full value — no direct share to subtract, interiors keep their true local brightness.
      // probe_active=0 => ind_k=1 + full direct = the accepted directional-ambient composite,
      // byte-identical. Extensible: N future point lights (fires/lanterns/eco) just add more direct
      // terms on top of the same fill — the layering needs no rewrite.
      const float RT_PROBE_IND = 0.45;
      float probe_active = (u_rt_probe_on != 0 && probe_w > 0.02) ? 1.0 : 0.0;
      // REOPEN 2026-07-21 (owner: realtime much flatter/less rich than baked) — BAKED-DETAIL
      // RE-INJECTION. The baked per-vertex color carries the meso-scale lighting (crevice AO,
      // contact shadows, local bounce) that the 4 m probe-SH grid low-passes away (measured:
      // the baked ground band has ~17-19% more meso/high local-contrast energy). The per-pixel
      // probe SH evaluated HERE is the low-pass of that same baked data (the probes are baked
      // from these very vertex colors, stored LUT units), so the ratio
      //   r = (fragment_color/2) / probe_SH      (both stored-space; ~1.0 on flat areas,
      //                                           <1 in crevices, >1 on baked bounce)
      // is the TOD-tracking high-frequency detail layer. pow(r, 2.2) is the linear-space
      // modulation whose DISPLAY-space effect equals the baked render's own local contrast
      // exactly. It modulates the WHOLE composite (ambient fill + both suns) so crevices dim
      // the direct light too => realtime = the baked richness (strict superset) + the dynamic
      // suns/shadows on top. detail == 1 where the probe has no data (fallback unchanged) and
      // fades in with probe_w; u_rt_detail==0 => the pre-reopen composite, byte-identical.
      // REOPEN #3 (owner: 'clairement mieux' BUT the sun casts no shadow / barely lights) —
      // SHADOW-THE-BAKED. The attempt-8 shade estimator included the DYNAMIC sun visibility
      // (vis_dyn): circular — exactly where the cast shadow blocked the sun, ind_k snapped to
      // 1.0 and the FULL baked (which contains the sun) re-brightened the area => the moving
      // shadow cancelled itself, and lit areas (0.45*base + sun) could even sit BELOW shadowed
      // ones => "sun dead". Correct energy balance (industry de-lighting-by-shadowing): don't
      // zero/re-add the sun — SHADOW THE BAKED. baked = ambient_share + sun_share; the dynamic
      // cast-shadow test says where the sun is NOT reaching NOW:
      //   lit    : keep the FULL baked (its sun share is real there) + a modest dynamic boost
      //   shadow : attenuate the baked TOWARD ITS AMBIENT-ONLY estimate (RT_PROBE_IND * base,
      //            the established no-double-count scaling)
      //   ind_k  = mix(ambient_estimate, full_baked, sun_visibility)
      // => real, OBVIOUS moving cast shadows with ZERO double-count. u_rt_detail==0 => the
      // pre-reopen composite exactly (d0 A/B semantics preserved).
      vec3 rt_detail = vec3(1.0);
      float ind_k;
      float boost_k = 1.0;  // full direct when the detail path is off (pre-reopen semantics)
      if (probe_active > 0.5 && u_rt_detail != 0) {
        vec3 baked_lut = max(fragment_color.rgb, vec3(0.0)) * 0.5;  // undo the x2 GS doubling -> stored LUT units
        vec3 lp = max(probe_pamb * max(u_rt_detail_norm, 1e-3), vec3(0.02));
        vec3 r = clamp(baked_lut / lp, vec3(0.25), vec3(1.6));  // bounded: division noise / systematic offsets can't blow out the suns
        rt_detail = mix(vec3(1.0), pow(r, vec3(2.2)), clamp(probe_w, 0.0, 1.0));
        // Bake-time "was this pixel sun-lit" (lit_bake): GEOMETRY ONLY per sun — N.L *
        // presence, NO cast-shadow occlusion (putting the dynamic occlusion in here was the
        // attempt-8 circularity) — times the r-ratio flatness term (crevices / baked shade
        // carry no sun share to remove; backfaces and interiors neither).
        float r_flat = smoothstep(0.55, 0.95, dot(r, vec3(0.299, 0.587, 0.114)));
        float moon_amp = clamp(dot(u_rt_moon_color, vec3(1.0)), 0.0, 1.0);
        float g_sun = smoothstep(0.05, 0.45, ndl * u_rt_sun_elev);
        float g_moon = smoothstep(0.05, 0.45, max(dot(N, normalize(u_rt_moon_dir)), 0.0) * moon_amp);
        float lit_bake = max(g_sun, g_moon) * r_flat * clamp(probe_w, 0.0, 1.0);
        // Dynamic sun visibility = the cast-shadow occlusion of whichever sun lights this
        // pixel (the geometry factor already lives in lit_bake; the non-owning sun's occ is 1).
        float occ_eff = (g_sun * sun_occ + g_moon * moon_occ + 1e-3) / (g_sun + g_moon + 1e-3);
        float sun_share = (1.0 - RT_PROBE_IND) * lit_bake * (1.0 - probe_int);
        ind_k = 1.0 - sun_share * (1.0 - occ_eff);
        // The dynamic suns stay a MODEST boost on top (direction/specular cue; their energy is
        // already in the baked for lit areas — the SHADOWS are the visible dynamic element).
        boost_k = clamp(u_rt_sun_boost, 0.0, 1.0);
      } else {
        // detail layer off / no probe coverage: the pre-reopen composite exactly (uniform
        // indirect scaling + FULL direct suns).
        ind_k = mix(1.0, mix(RT_PROBE_IND, 1.0, probe_int), probe_active);
      }
      vec3 lit = albedo * rt_detail * (base * ind_k
               + (u_rt_sun_color * sun_scalar + u_rt_moon_color * moon_ndl) * boost_k);
      // PLAYTEST#1 #3 (reflections grey EVERYTHING): the blanket reflection add that lived HERE painted a
      // flat grey specular wash on every diffuse surface. These shaders have NO reflective PBR material
      // path, so the reflection is REMOVED here entirely (correct-or-off; a grey wash is worse than
      // nothing). u_rt_probe_cube stays declared but unused. Reflections apply only on genuinely
      // reflective PBR materials (the Cook-Torrance branch in tfrag3.frag), never as an ambient wash.
      {
        const float RT_KNEE = 0.8;
        vec3 e = exp(-max(lit - vec3(RT_KNEE), vec3(0.0)) / (1.0 - RT_KNEE));  // max() guards 0*inf NaN
        lit = mix(lit, vec3(1.0) - (1.0 - RT_KNEE) * e, step(vec3(RT_KNEE), lit));
      }
      vec3 sun_disp = pow(max(lit, vec3(0.0)), vec3(1.0 / 2.2));
      // ROUND-4 item #2: beyond the Shadow Distance, crossfade back to the stock BAKED
      // lighting (fragment_color * T0 = AO/painted macro detail) so far geometry reads
      // coherent, not flat. baked-off only suppresses baked INSIDE the zone.
      float far_rng = u_rt_shadow_range > 1.0 ? u_rt_shadow_range : 150.0;
      float far_t = smoothstep(far_rng * 0.82, far_rng * 1.05, length(v_fringe_rel));
      vec3 baked_disp = max(fragment_color.rgb * T0.rgb, vec3(0.0));
      color.rgb = mix(sun_disp, baked_disp, far_t);
      if (u_pbr_debug == 1) { color.rgb = vec3(ndl); }
      else if (u_pbr_debug == 2) { color.rgb = N * 0.5 + 0.5; }
      else if (u_pbr_debug == 12) { float bl = dot(base, vec3(0.299, 0.587, 0.114)); color.rgb = vec3(bl + (1.0 - bl) * sun_scalar); }
      }  // end "BAKED AMBIENT" curiosity probe-projection path (u_rt_probe_on != 0)
    }
#endif
  } else {
    color = fragment_color/2.0;
  }

  if (color.a < alpha_min || color.a > alpha_max) {
    discard;
  }

  color.rgb = mix(color.rgb, fog_color.rgb, clamp(fogginess * fog_color.a, 0.0, 1.0));
}