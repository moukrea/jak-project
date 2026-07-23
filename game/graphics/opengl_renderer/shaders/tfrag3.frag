#version 410 core

out vec4 color;

in vec4 fragment_color;
in vec3 tex_coord;
in float fogginess;
in vec3 v_fringe_rel;  // Grecharged-grass-overhang2: camera-relative world pos (meters)
in vec3 v_world;       // Grecharged-lightprobes: absolute world pos (game units) for probe lookup
in vec3 v_normal;      // Grecharged-directional-ambient: smooth per-vertex world normal (root-cause fix)
uniform sampler2D tex_T0;

uniform float alpha_min;
uniform float alpha_max;
uniform vec4 fog_color;

uniform int gfx_hack_no_tex;

// Grecharged-grass-overhang2: near-fade of the painted grass-fringe alpha strips while the recharged
// 3D droop covers them (owner: the texture showed through the blades). x = enable (set per-draw for
// the two fringe textures only), y/z = fade start/end in METERS. 0 (default) = stock path.
uniform vec4 u_fringe_fade;

#ifdef OG_PBR
uniform int u_pbr_mode;        // 0=legacy; bit1 normal, bit2 rough, bit4 metal, bit8 ao, bit16 height/POM,
                               // bit32 specular (F0 workflow), bit64 emissive (unlit add) — fusion phase
uniform vec3 u_pbr_sun_dir;    // world-space, surface->sun, normalized (viz/legacy)
uniform vec3 u_pbr_sun_color;
// Round-4 multi-light: 3 direct lights from light-group 0 (soleil + lune verte + fill),
// surface->light dirs + rgb colors. Each color is pre-weighted by its levels.x morph
// weight in C++ so dir0+dir1 sum ~1 across hour transitions (energy conserved).
uniform vec3 u_pbr_light_dir[3];
uniform vec3 u_pbr_light_color[3];
uniform vec3 u_pbr_ambient;
uniform float u_pbr_exposure;
// Owner mandate 2026-07-18: relief must be unmistakable. Normal-map x/y perturbation
// multiplier (>1 deepens), POM depth in native-UV units (0 disables the march even when
// a height map is bound), extra UV tiling on the PBR path only (1.0 = native density).
uniform float u_pbr_normal_strength;
uniform float u_pbr_height_scale;
uniform float u_pbr_uv_tile;
// Owner round-3 mandate 2026-07-18: lighting split calibration. u_pbr_direct scales the
// realtime direct DIFFUSE (the baked vertex color already contains the baked sun's
// diffuse — this is the double-dose control); u_pbr_indirect scales the baked-GI
// indirect term. Specular is deliberately NOT scaled by u_pbr_direct: baked carries no
// specular, and the moving highlight is the realtime tell.
uniform float u_pbr_direct;
uniform float u_pbr_indirect;
// Round-4bis mandate E (owner: "si notre vrai lighting realtime marche vraiment, on n'a
// plus besoin du baked quand activé"): 1.0 = round-3 hybrid (indirect = baked vertex GI),
// 0.0 = FULL REALTIME (indirect = light-group ambient * AO; baked term gone). At low
// weight the u_pbr_direct double-dose damping also fades back to 1.0 — it exists only
// because the baked term carries the baked sun, which is no longer added at w=0.
uniform float u_pbr_baked_weight;
// Per-channel isolation viz on the PBR draws only (legacy neighbours untouched, so the
// patch outline shows in every mode). 0=off, 1=albedo passthrough (what a plain
// photo-swap would look like; POM still offsets it, so this is also the cleanest
// parallax viz), 2=geometric normal, 3=final shading normal (shows the normal map's
// perturbation vs 2), 4=roughness, 5=accumulated specular term (all lights), 6=AO,
// 7=full PBR with the normal map DISABLED (the N on/off A/B pair with 0),
// 8=full PBR with POM DISABLED (the POM on/off A/B pair with 0), 9=height map,
// 10=indirect/baked-GI term only (the round-3 macro-shading reintegration viz),
// 11=direct term only (accumulated diffuse+spec of ALL lights — round-4 multi-light),
// 12=sun shadow-map factor (round-4 mandate B; white=lit, black=shadowed),
// 13=direct contribution of lights 1+2 ONLY (moon/fill isolation, skips the sun).
uniform int u_pbr_debug;
uniform sampler2D tex_PBR_N;
uniform sampler2D tex_PBR_R;
uniform sampler2D tex_PBR_M;
uniform sampler2D tex_PBR_AO;
uniform sampler2D tex_PBR_H;
// Grecharged-pbr-realtime-fusion (owner: "faut câbler specular et emissive aussi"):
// _specular = F0/specular color (specular workflow, overrides metallic-derived F0),
// _emissive = unlit self-illumination added on top (glows in shadow/night). Units 16/17.
uniform sampler2D tex_PBR_S;
uniform sampler2D tex_PBR_E;
uniform float u_pbr_emissive_str;  // emissive intensity (prop debug.opengoal.pbr.emissive)
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
// Owner clarification 2026-07-18 (WORLD shadows): legacy (non-PBR) fragments in this
// program also receive the sun shadow as a calibrated darkening, so the hut's shadow
// lands on the non-PBR ground. 0 disables; ~0.35 default, prop-tunable so already-baked
// painted shadows don't double-darken into black.
uniform float u_pbr_legacy_shadow;
// Debug-only bias override added to the compare ref (prop debug.opengoal.pbr.shadowbias /
// OG_PBR_SHADOWBIAS, default 0.0 = no effect). +0.5 must black out every in-box receiver
// if the HW depth compare works — the Adreno-driver binary test.
uniform float u_pbr_shadow_bias;
// Round-5 addendum 2, MANDATE F ("light the world like Jak"): world-wide mood-light
// shading for LEGACY (non-PBR-mapped) world fragments. Direct term = per-face geometric
// normal (screen-derivative — camera-independent for planar level tris, so it CANNOT swim
// with the camera) dotted with the light-group lights (sun + fill + moon), times the sun
// shadow factor; indirect stays the baked vertex color. u_pbr_world_relight blends the
// whole effect (0 = old flat legacy darkening path); wr_direct/wr_indirect are the
// anti-double-brightening calibration (the baked color already contains the baked sun).
uniform float u_pbr_world_relight;
uniform float u_pbr_wr_direct;
uniform float u_pbr_wr_indirect;
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
// Grecharged-directional-ambient ROOT-CAUSE FIX: debug/A-B toggle. 0 (default) = SMOOTH per-vertex
// normal (the fix); 1 = force the OLD flat per-face screen-derivative normal (pre-fix look, same build).
uniform int u_rt_flat_normal;
uniform vec3 u_rt_sh[9];
uniform vec3 u_rt_env_zenith;
uniform vec3 u_rt_env_horizon;
uniform vec3 u_rt_env_ground;
uniform vec3 u_rt_sun_glow;
// Grecharged-realtime-lighting ROUND 2: sun shadow-map RANGE (ortho half-extent in meters,
// == the Shadow Distance setting) and RESOLUTION (depth-tex edge in texels, == the Shadow
// Quality setting). Range drives the smooth distance FADE at the realtime-zone edge (no hard
// pop as the camera approaches/recedes); resolution drives the PCF texel size and the
// world-space normal-offset bias (crisper edges + correct relief at higher res). Both default
// in-shader to the round-1 values (40 m half, 1024) when unset.
uniform float u_rt_shadow_range;
uniform float u_rt_shadow_res;
// Grecharged-realtime-lighting ROUND 5: cast-shadow RESIDUAL — the brightness a fully
// occluded fragment KEEPS (owner real-world obs: a clear-sky cast shadow is only ~80-85%
// darker than lit, it still catches ~15-20% skylight, so it must NOT be pure black). We
// have no ambient yet, so this is a cheat: 0.0 == black (round-4 look), 0.2 == default
// (clear-sky). Fed from the "Shadow Strength" setting as (1 - strength). Applies to the
// CAST-SHADOW occlusion term ONLY — the N.L dark side (ndl->0) stays genuinely black
// (owner: un-lit black is intended, do not change it).
uniform float u_rt_shadow_residual;
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
    // Round-4 mandate B / ROUND-2 rewrite: sun shadow-map factor, a real PER-FRAGMENT
    // world-position depth compare — the receiver projects ITS OWN v_fringe_rel (camera-
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
      float rng = u_rt_shadow_range > 1.0 ? u_rt_shadow_range : 150.0;
      float res = u_rt_shadow_res > 1.0 ? u_rt_shadow_res : 2048.0;
      float texel = 1.0 / res;
      float texel_world = (2.0 * rng) / res;  // world meters per shadow texel
      // Per-face WORLD normal for the normal-offset bias (camera-independent: v_fringe_rel
      // is camera-TRANSLATED, not rotated). Double-sided for level tris.
      vec3 sng = cross(dFdx(v_fringe_rel), dFdy(v_fringe_rel));
      float sngl = length(sng);
      vec3 snrm = sngl > 1e-6 ? sng / sngl : vec3(0.0, 1.0, 0.0);
      vec3 svv = -normalize(v_fringe_rel);
      if (dot(snrm, svv) < 0.0) snrm = -snrm;
      float ndl0 = max(dot(snrm, u_pbr_light_dir[0]), 0.0);
      // NORMAL OFFSET in world meters, scaled by texel size (so it stays ~constant in
      // texels across every Shadow Quality / Distance combo) and by grazing angle. The
      // sun-only (no-ambient) path needs a bit more (acne is unmasked without baked
      // indirect); the pbr-materials path keeps a lighter offset.
      float noff = texel_world * (u_rt_light_on != 0 ? mix(1.5, 5.0, 1.0 - ndl0)
                                                     : mix(0.75, 2.0, 1.0 - ndl0));
      vec3 sworld = v_fringe_rel + u_pbr_shadow_cam_delta + snrm * noff;
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
        float sdist = length(v_fringe_rel);
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
        float edge_fade = 1.0 - smoothstep(rng * 0.72, rng * 0.96, length(v_fringe_rel));
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
      // Per-face WORLD normal. v_fringe_rel is the camera-TRANSLATED (not
      // rotated) world position, so its screen-space derivatives give a
      // camera-INDEPENDENT world-space face normal — the lit/dark terminator
      // is pinned to geometry and cannot swim as the camera orbits.
      // Grecharged-directional-ambient ROOT-CAUSE FIX: use the SMOOTH per-vertex normal (v_normal)
      // reconstructed at load, not the flat per-face screen-derivative normal. The per-face geometric
      // normal gN is kept only as the outward-sign reference (renderer's double-sided convention) and
      // as the degenerate fallback, so this reconstruction's global winding is irrelevant and the
      // worst case (missing normal) == the old flat behaviour exactly.
      vec3 gN = cross(dFdx(v_fringe_rel), dFdy(v_fringe_rel));
      float gNl = length(gN);
      gN = gNl > 1e-6 ? gN * (1.0 / gNl) : vec3(0.0, 1.0, 0.0);
      vec3 Vv = -normalize(v_fringe_rel);
      if (dot(gN, Vv) < 0.0) gN = -gN;           // double-sided level tris (outward convention)
      vec3 Ns = v_normal;
      float Nsl2 = dot(Ns, Ns);
      vec3 N;
      if (u_rt_flat_normal == 0 && Nsl2 > 0.2) {  // valid smooth normal present (default)
        Ns *= inversesqrt(Nsl2);
        N = dot(Ns, gN) < 0.0 ? -Ns : Ns;        // align smooth normal to the outward face sign
      } else {
        N = gN;                                  // forced-flat A/B or no reconstructed normal (stock)
      }
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
      // nothing is pure black anywhere. floor = 1 - Shadow Strength (u_rt_shadow_residual).
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
      // rt ON + pbr OFF (u_pbr_mode==0) falls through to the accepted BAKED-MODULATION
      // path below, byte-identical — no regression to the directional-ambient look.
      if (u_pbr_mode != 0) {
        // Cotangent frame around the SMOOTH normal N (screen-derivative TBN — tfrag
        // data has no vertex tangents; same construction as the standalone path, but
        // seeded with the reconstructed smooth normal so map detail rides on it).
        vec3 fdp1 = dFdx(v_fringe_rel);
        vec3 fdp2 = dFdy(v_fringe_rel);
        vec2 fduv1 = dFdx(tex_coord.xy);
        vec2 fduv2 = dFdy(tex_coord.xy);
        vec3 fdp2perp = cross(fdp2, N);
        vec3 fdp1perp = cross(N, fdp1);
        vec3 fT = fdp2perp * fduv1.x + fdp1perp * fduv2.x;
        vec3 fB = fdp2perp * fduv1.y + fdp1perp * fduv2.y;
        float finvmax = inversesqrt(max(max(dot(fT, fT), dot(fB, fB)), 1e-10));
        vec3 fTn = fT * finvmax;
        vec3 fBn = fB * finvmax;
        vec2 uv = tex_coord.xy * u_pbr_uv_tile;
        // Height map (bit 16): the same mobile-tuned POM march as the standalone path
        // (already proven on Adreno 618 there — same cost class, so it ships here too).
        if ((u_pbr_mode & 16) != 0 && u_pbr_debug != 8 && u_pbr_height_scale > 0.0) {
          vec3 Vt = normalize(vec3(dot(Vv, fTn), dot(Vv, fBn), max(dot(Vv, N), 0.0)));
          float vz = max(Vt.z, 0.12);
          float n_layers = mix(28.0, 10.0, clamp(Vt.z, 0.0, 1.0));
          vec2 duv_step = (Vt.xy / vz) * u_pbr_height_scale * u_pbr_uv_tile / n_layers;
          float layer_d = 1.0 / n_layers;
          float cur_d = 0.0;
          float map_d = 1.0 - textureLod(tex_PBR_H, uv, 0.0).r;
          float prev_map_d = map_d;
          for (int i = 0; i < 32; i++) {
            if (cur_d >= map_d || float(i) >= n_layers) {
              break;
            }
            uv -= duv_step;
            prev_map_d = map_d;
            map_d = 1.0 - textureLod(tex_PBR_H, uv, 0.0).r;
            cur_d += layer_d;
          }
          float after = map_d - cur_d;
          float before = prev_map_d - (cur_d - layer_d);
          float w = clamp(before / max(before - after, 1e-5), 0.0, 1.0);
          uv += duv_step * (1.0 - w);
        }
        // Normal map (bit 1) perturbs the SMOOTH normal => surface detail that shades
        // correctly as the realtime suns move (the fusion's whole point).
        vec3 Nm = N;
        if ((u_pbr_mode & 1) != 0 && u_pbr_debug != 7) {
          vec3 nmt = texture(tex_PBR_N, uv).xyz * 2.0 - 1.0;
          nmt.xy *= u_pbr_normal_strength;
          nmt = normalize(nmt);
          Nm = normalize(mat3(fTn, fBn, N) * nmt);
          if (dot(Nm, gN) < 0.0) Nm = N;  // never flip past the face
        }
        vec4 T0p = texture(tex_T0, uv);
        vec3 albedo = pow(T0p.rgb, vec3(2.2));
        float rough = (u_pbr_mode & 2) != 0 ? texture(tex_PBR_R, uv).r : 0.7;
        float metal = (u_pbr_mode & 4) != 0 ? texture(tex_PBR_M, uv).r : 0.0;
        float ao = (u_pbr_mode & 8) != 0 ? texture(tex_PBR_AO, uv).r : 1.0;
        vec3 F0 = (u_pbr_mode & 32) != 0 ? pow(texture(tex_PBR_S, uv).rgb, vec3(2.2))
                                         : mix(vec3(0.04), albedo, metal);
        float NdV = max(dot(Nm, Vv), 1e-4);
        float fa = max(rough * rough, 0.002);
        float fa2 = fa * fa;
        float fk = (rough + 1.0) * (rough + 1.0) / 8.0;
        // BOTH analytic suns, Cook-Torrance each: i=0 the yellow sun (visibility = its
        // cast shadow sun_occ x the night fade u_rt_sun_elev), i=1 the green sun
        // (u_rt_moon_color already carries its night crossover weight C++-side;
        // visibility = ITS cast shadow moon_occ — per-sun map ownership, item 1).
        vec3 direct = vec3(0.0);
        vec3 spec_sum = vec3(0.0);
        for (int i = 0; i < 2; i++) {
          vec3 Li = (i == 0) ? L : normalize(u_rt_moon_dir);
          vec3 lc = (i == 0) ? u_rt_sun_color * clamp(u_rt_sun_elev, 0.0, 1.0)
                             : u_rt_moon_color;
          float vis = (i == 0) ? sun_occ : moon_occ;
          if (dot(lc, vec3(1.0)) <= 1e-5) {
            continue;
          }
          vec3 Hh = normalize(Li + Vv);
          float NdL = max(dot(Nm, Li), 0.0);
          float NdH = max(dot(Nm, Hh), 0.0);
          float VdH = max(dot(Vv, Hh), 0.0);
          float dd = NdH * NdH * (fa2 - 1.0) + 1.0;
          float D = fa2 / (3.14159265 * dd * dd);
          float G = (NdV / (NdV * (1.0 - fk) + fk)) * (NdL / (NdL * (1.0 - fk) + fk));
          vec3 F = F0 + (1.0 - F0) * pow(1.0 - VdH, 5.0);
          vec3 spec = D * G * F / max(4.0 * NdV * NdL, 1e-4);
          vec3 kd = (vec3(1.0) - F) * (1.0 - metal);
          vec3 contrib = (kd * albedo / 3.14159265 + spec) * lc * NdL * vis;
          direct += contrib;
          spec_sum += spec * lc * NdL * vis;
        }
        // AMBIENT (indirect diffuse): the directional-ambient model sampled by the
        // SHADED normal; AO multiplies the ambient ONLY.
        vec3 amb_base;
        if (u_rt_ambient_on == 0) {
          amb_base = vec3(clamp(u_rt_shadow_residual, 0.0, 1.0));
        } else if (u_rt_ambient_model == 1) {
          amb_base = rt_sh_ambient(Nm);
        } else if (u_rt_ambient_model == 2) {
          amb_base = rt_ibl_ambient(Nm);
        } else {
          amb_base = mix(u_rt_ground_color, u_rt_sky_color, clamp(Nm.y * 0.5 + 0.5, 0.0, 1.0));
        }
        amb_base = clamp(amb_base, 0.0, 1.0);
        vec3 amb_diff = albedo * amb_base * ao * (1.0 - metal);
        // Roughness-aware AMBIENT SPECULAR (single reflection term) so smooth metals
        // aren't dead in shadow: env = the prefiltered probe cube when probes +
        // reflections are ON, else the analytic ambient evaluated at the reflection
        // direction (Fdez-Aguera roughness-aware Fresnel, as the standalone path).
        vec3 Rf = reflect(-Vv, Nm);
        vec3 amb_env;
        if (u_rt_probe_on != 0 && u_rt_probe_reflections != 0) {
          amb_env = textureLod(u_rt_probe_cube, Rf, rough * 3.0).rgb *
                    clamp(u_rt_probe_strength, 0.0, 1.0);
        } else if (u_rt_ambient_on != 0 && u_rt_ambient_model == 1) {
          amb_env = rt_sh_ambient(Rf);
        } else if (u_rt_ambient_on != 0 && u_rt_ambient_model == 2) {
          amb_env = rt_ibl_ambient(Rf);
        } else {
          amb_env = amb_base;
        }
        vec3 Fr = max(vec3(1.0 - rough), F0) - F0;
        vec3 Fenv = F0 + Fr * pow(1.0 - NdV, 5.0);
        vec3 amb_spec = amb_env * Fenv * ao;
        // EMISSIVE (bit 64): unlit, added on top — glows in full shadow / at night.
        vec3 emissive = (u_pbr_mode & 64) != 0
                            ? pow(texture(tex_PBR_E, uv).rgb, vec3(2.2)) *
                                  max(u_pbr_emissive_str, 0.0)
                            : vec3(0.0);
        vec3 flit = direct + amb_diff + amb_spec + emissive;
        // Same C1 soft-shoulder tone map + far crossfade to baked as the rt composite,
        // so the fused patch stays coherent with its rt-lit legacy neighbours.
        {
          const float RT_KNEE = 0.8;
          vec3 fe = exp(-max(flit - vec3(RT_KNEE), vec3(0.0)) / (1.0 - RT_KNEE));
          flit = mix(flit, vec3(1.0) - (1.0 - RT_KNEE) * fe, step(vec3(RT_KNEE), flit));
        }
        vec3 fdisp = pow(max(flit, vec3(0.0)), vec3(1.0 / 2.2));
        float ffar_rng = u_rt_shadow_range > 1.0 ? u_rt_shadow_range : 150.0;
        float ffar_t = smoothstep(ffar_rng * 0.82, ffar_rng * 1.05, length(v_fringe_rel));
        vec3 fbaked = max(fragment_color.rgb * T0.rgb, vec3(0.0));
        color.rgb = mix(fdisp, fbaked, ffar_t);
        // Debug viz (default colored render untouched at u_pbr_debug==0).
        if (u_pbr_debug == 2) {
          color.rgb = N * 0.5 + 0.5;
        } else if (u_pbr_debug == 3) {
          color.rgb = Nm * 0.5 + 0.5;
        } else if (u_pbr_debug == 4) {
          color.rgb = vec3(rough);
        } else if (u_pbr_debug == 5) {
          color.rgb = pow(max(spec_sum, vec3(0.0)), vec3(1.0 / 2.2));
        } else if (u_pbr_debug == 6) {
          color.rgb = vec3(ao);
        } else if (u_pbr_debug == 18) {
          color.rgb = pow(max(emissive, vec3(0.0)), vec3(1.0 / 2.2));
        }
      } else if (u_rt_probe_on == 0) {
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
      // Grecharged-directional-ambient: the ambient BASE is now DIRECTIONAL (hemisphere) — sky
      // color on up-facing faces, ground bounce on down-facing faces, blended by the world
      // normal's up-component. Shadowed / away-from-sun surfaces regain FORM (top-lit,
      // underside-dark) with AO fully OFF. Toggle OFF => the legacy flat ~0.2 floor (for A/B).
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
      // baked is hardwired OFF in the realtime path (owner: realtime ON => baked OFF; realtime
      // OFF takes the stock legacy baked path above). GOLDEN RULE: the direct-sun term below is
      // UNCHANGED, so sunlit surfaces are unaffected by this ambient reshaping (base's weight
      // vanishes as the sun term saturates).
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
      // ITEM B: the GREEN MOON adds a directional key at night (weight folded into u_rt_moon_color =>
      // 0 by day, golden rule). Same additive model as the sun; the sun<->moon crossover is smooth.
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
      // flat grey specular wash on every diffuse surface (terrain/walls are NOT reflective). It is REMOVED
      // from this diffuse branch. Reflections now apply ONLY on genuinely reflective PBR materials, gated
      // by metalness/roughness, in the Cook-Torrance branch below (correct-or-off; a grey wash is worse
      // than nothing). Non-reflective surfaces are byte-identical with probe reflections ON vs OFF.
      {
        const float RT_KNEE = 0.8;
        vec3 e = exp(-max(lit - vec3(RT_KNEE), vec3(0.0)) / (1.0 - RT_KNEE));  // max() guards 0*inf NaN
        lit = mix(lit, vec3(1.0) - (1.0 - RT_KNEE) * e, step(vec3(RT_KNEE), lit));
      }
      vec3 sun_disp = pow(max(lit, vec3(0.0)), vec3(1.0 / 2.2));
      // ROUND-4 item #2 OUT-OF-RANGE FALLBACK = BAKED (revises round-3's bare-N.L far).
      // Within the realtime shadow zone the surface is lit by the realtime sun + cast
      // shadow (baked suppressed here when the baked-off sub-option is on). BEYOND the
      // Shadow Distance, CROSSFADE BACK to the stock baked lighting (fragment_color * T0 —
      // it carries AO / bounce / painted macro detail) so distant geometry reads coherent
      // to the horizon instead of flat/unshaded. The baked-off toggle only suppresses baked
      // INSIDE the zone; the far fallback ALWAYS uses baked. Smooth distance crossfade tied
      // to the Shadow Distance setting (rng) — no flat far, no hard pop.
      float far_rng = u_rt_shadow_range > 1.0 ? u_rt_shadow_range : 150.0;
      float far_t = smoothstep(far_rng * 0.82, far_rng * 1.05, length(v_fringe_rel));
      vec3 baked_disp = max(fragment_color.rgb * T0.rgb, vec3(0.0));
      color.rgb = mix(sun_disp, baked_disp, far_t);
      // Debug viz (shared prop u_pbr_debug): 1=N.L factor, 2=world normal,
      // 12=shadow factor.
      if (u_pbr_debug == 1) {
        color.rgb = vec3(ndl);
      } else if (u_pbr_debug == 2) {
        color.rgb = N * 0.5 + 0.5;
      } else if (u_pbr_debug == 12) {
        // total lighting fraction (grayscale): 1.0 in full sun, the directional ambient base
        // luminance on away-faces / in cast shadows (top faces brighter than undersides = form).
        float bl = dot(base, vec3(0.299, 0.587, 0.114));
        color.rgb = vec3(bl + (1.0 - bl) * sun_scalar);
      }
      }  // end "BAKED AMBIENT" curiosity probe-projection path (u_rt_probe_on != 0)
    } else if (u_pbr_mode != 0 && gfx_hack_no_tex == 0) {
      // Grecharged-pbr-materials: Cook-Torrance GGX lit by the mood/TOD sun.
      // Owner round-3 mandate: the baked per-vertex TOD color (fragment_color.rgb) is
      // reintegrated as the INDIRECT/GI term — it carries the level's MACRO shading
      // (building curvature, under-roof darkening, doorway occlusion) that a constant
      // ambient flattened. It is NOT a second direct dose: the realtime direct diffuse
      // is scaled down by u_pbr_direct to compensate for the baked sun it contains.
      // Alpha keeps the legacy product for discard.
      vec3 p = v_fringe_rel;
      vec3 dp1 = dFdx(p);
      vec3 dp2 = dFdy(p);
      vec3 V = -normalize(p);
      vec3 Ngeo = normalize(cross(dp1, dp2));
      if (dot(Ngeo, V) < 0.0) Ngeo = -Ngeo;
      // cotangent frame from screen-space derivatives (no vertex tangents in tfrag
      // data) — shared by POM (tangent-space view) and normal mapping.
      vec2 duv1 = dFdx(tex_coord.xy);
      vec2 duv2 = dFdy(tex_coord.xy);
      vec3 dp2perp = cross(dp2, Ngeo);
      vec3 dp1perp = cross(Ngeo, dp1);
      vec3 T = dp2perp * duv1.x + dp1perp * duv2.x;
      vec3 B = dp2perp * duv1.y + dp1perp * duv2.y;
      float invmax = inversesqrt(max(max(dot(T, T), dot(B, B)), 1e-10));
      vec3 Tn = T * invmax;
      vec3 Bn = B * invmax;
      vec2 uv = tex_coord.xy * u_pbr_uv_tile;
      if ((u_pbr_mode & 16) != 0 && u_pbr_debug != 8 && u_pbr_height_scale > 0.0) {
        // Parallax occlusion mapping, mobile-tuned: grazing-angle-scaled linear march
        // with early-out + one secant refine. Height convention: 1.0 (white) = surface
        // level, lower = carved in — so a neutral white map yields zero offset and the
        // march depth is (1 - height). textureLod avoids undefined derivatives in the
        // loop; the offsets are small so mip 0 is acceptable at PoC distances.
        vec3 Vt = normalize(vec3(dot(V, Tn), dot(V, Bn), max(dot(V, Ngeo), 0.0)));
        float vz = max(Vt.z, 0.12);  // cap the grazing blow-up (offset <= ~8x scale)
        float n_layers = mix(28.0, 10.0, clamp(Vt.z, 0.0, 1.0));
        vec2 duv_step = (Vt.xy / vz) * u_pbr_height_scale * u_pbr_uv_tile / n_layers;
        float layer_d = 1.0 / n_layers;
        float cur_d = 0.0;
        float map_d = 1.0 - textureLod(tex_PBR_H, uv, 0.0).r;
        float prev_map_d = map_d;
        for (int i = 0; i < 32; i++) {
          if (cur_d >= map_d || float(i) >= n_layers) {
            break;
          }
          uv -= duv_step;
          prev_map_d = map_d;
          map_d = 1.0 - textureLod(tex_PBR_H, uv, 0.0).r;
          cur_d += layer_d;
        }
        // secant refine between the last two samples for a smooth intersection
        float after = map_d - cur_d;
        float before = prev_map_d - (cur_d - layer_d);
        float w = clamp(before / max(before - after, 1e-5), 0.0, 1.0);
        uv += duv_step * (1.0 - w);
      }
      vec3 N = Ngeo;
      if ((u_pbr_mode & 1) != 0 && u_pbr_debug != 7) {
        vec3 nm = texture(tex_PBR_N, uv).xyz * 2.0 - 1.0;
        nm.xy *= u_pbr_normal_strength;
        nm = normalize(nm);
        N = normalize(mat3(Tn, Bn, Ngeo) * nm);
        if (dot(N, Ngeo) < 0.0) N = Ngeo;
      }
      // Albedo re-sampled at the (possibly POM-offset, tiled) UV; the initial T0
      // sample keeps supplying alpha for the legacy discard product below.
      vec4 T0p = texture(tex_T0, uv);
      vec3 albedo = pow(T0p.rgb, vec3(2.2));
      float rough = (u_pbr_mode & 2) != 0 ? texture(tex_PBR_R, uv).r : 0.7;
      float metal = (u_pbr_mode & 4) != 0 ? texture(tex_PBR_M, uv).r : 0.0;
      float ao    = (u_pbr_mode & 8) != 0 ? texture(tex_PBR_AO, uv).r : 1.0;
      float NdV = max(dot(N, V), 1e-4);
      float a = max(rough * rough, 0.002);
      float a2 = a * a;
      float k = (rough + 1.0) * (rough + 1.0) / 8.0;
      vec3 F0 = mix(vec3(0.04), albedo, metal);
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
        float G = (NdV / (NdV * (1.0 - k) + k)) * (NdL / (NdL * (1.0 - k) + k));
        vec3 F = F0 + (1.0 - F0) * pow(1.0 - VdH, 5.0);
        vec3 spec = D * G * F / max(4.0 * NdV * NdL, 1e-4);
        vec3 kd = (vec3(1.0) - F) * (1.0 - metal);
        vec3 contrib = (kd * albedo / 3.14159265 * direct_diff_scale + spec) * lc * NdL;
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
      // fragment_color * T0 by construction — the macro luminance profile of the
      // building matches OFF wherever the sun doesn't add on top. The baked color is
      // TOD-palette-interpolated per frame, so this term still tracks the day cycle.
      vec3 baked_gi = pow(max(fragment_color.rgb, vec3(0.0)), vec3(2.2));
      // Round-4bis mandate E: blend the hybrid baked-GI indirect toward the FULL-REALTIME
      // indirect (light-group ambient * AO) as bakedw -> 0. At w=0 the baked vertex color
      // no longer influences the PBR surface at all: sun+moon+fill direct is shadow-mapped
      // realtime, ambient comes from the level light-group, occlusion from the AO map.
      vec3 indirect_baked = albedo * baked_gi * ao * u_pbr_indirect;
      vec3 indirect_rt = albedo * u_pbr_ambient * ao;
      vec3 indirect = mix(indirect_rt, indirect_baked, bakedw);
      vec3 lit = direct + indirect;
      // PLAYTEST#1 #3: LOCAL environment IBL specular — the reflection consumer, applied ONLY on
      // genuinely reflective materials (this is the Cook-Torrance PBR path with real metal/roughness).
      // Prefiltered probe cube at the roughness mip, weighted by the roughness-aware env Fresnel: a
      // dielectric (F0~0.04) barely reflects except at grazing angles, metal (F0~albedo) reflects
      // strongly + colored. Never a flat grey wash on non-reflective surfaces. AO-occluded.
      if (u_rt_probe_on != 0 && u_rt_probe_reflections != 0) {
        vec3 Rf = reflect(-V, N);
        float mip = rough * 3.0;                          // 8x8 cube: ~3 mips; rough -> blurrier
        vec3 prefiltered = textureLod(u_rt_probe_cube, Rf, mip).rgb;
        vec3 Fr = max(vec3(1.0 - rough), F0) - F0;        // roughness-aware Fresnel (Fdez-Aguera)
        vec3 Fenv = F0 + Fr * pow(1.0 - NdV, 5.0);
        lit += prefiltered * Fenv * ao * clamp(u_rt_probe_strength, 0.0, 1.0);
      }
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
        vec3 wrn = cross(dFdx(v_fringe_rel), dFdy(v_fringe_rel));
        float wrl = length(wrn);
        vec3 wrN = wrl > 1e-6 ? wrn / wrl : vec3(0.0, 1.0, 0.0);
        vec3 wrV = -normalize(v_fringe_rel);
        if (dot(wrN, wrV) < 0.0) wrN = -wrN;
        vec3 wr_direct = vec3(0.0);
        for (int i = 0; i < 3; i++) {
          wr_direct += u_pbr_light_color[i] * max(dot(wrN, u_pbr_light_dir[i]), 0.0);
        }
        wr_direct *= sm_shadow * u_pbr_wr_direct;
        vec3 wr_alb = pow(T0.rgb, vec3(2.2));
        vec3 wr_baked = pow(max(fragment_color.rgb, vec3(0.0)), vec3(2.2));
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
  } else {
    color = fragment_color/2.0;
  }

  if (u_fringe_fade.x > 0.5) {
    // Grecharged-grass-overhang2 (owner defect 1): fade the painted fringe ALPHA out near the camera
    // so the 3D droop REPLACES it instead of poking through it; far keeps the stock strip, crossfaded
    // over the SAME band the droop blades fade out in. STEEPNESS-gated via screen-space derivatives
    // (level tris are planar, so this is the exact face normal): only the steep hang faces fade —
    // flat walkable ground sharing the texture keeps its stock texels. The scan's fringe/walkable
    // split is upness 0.35 (GrassBakeCore GROUND_UPNESS); the 0.30..0.40 smooth edge straddles it.
    vec3 fdx = dFdx(v_fringe_rel);
    vec3 fdy = dFdy(v_fringe_rel);
    vec3 fnrm = cross(fdx, fdy);
    float fl = length(fnrm);
    float upness = fl > 1e-6 ? abs(fnrm.y) / fl : 1.0;
    float steep_w = 1.0 - smoothstep(0.30, 0.40, upness);
    float dist_f = smoothstep(u_fringe_fade.y, u_fringe_fade.z, length(v_fringe_rel));
    // Grecharged-grass-overhang7 ROUND 10 forensics (u_fringe_fade.w, prop
    // debug.opengoal.grass.fringe_dbg; 0 = stock): mode 2 paints the gate state instead of fading
    // (magenta = steep/would-fade, cyan = gate-blocked flat-ish) so one close capture names WHY a
    // painted tuft survived the near-fade; mode 1 ignores the steepness gate entirely (A/B).
    if (u_fringe_fade.w > 1.5) {
      color.rgb = mix(color.rgb, mix(vec3(0.0, 1.0, 1.0), vec3(1.0, 0.0, 1.0), steep_w), 0.8);
    } else {
      if (u_fringe_fade.w > 0.5) {
        steep_w = 1.0;
      }
      color.a *= mix(1.0, dist_f, steep_w);
    }
  }

  if (color.a < alpha_min || color.a > alpha_max) {
    discard;
  }

  color.rgb = mix(color.rgb, fog_color.rgb, clamp(fogginess * fog_color.a, 0.0, 1.0));
}
