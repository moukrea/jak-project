#version 410 core

out vec4 color;

in vec4 fragment_color;
in vec3 tex_coord;
in float fogginess;
in vec3 v_fringe_rel;  // Grecharged-grass-overhang2: camera-relative world pos (meters)
in vec3 v_world;       // Grecharged-lightprobes: absolute world pos (game units) for probe lookup
in vec3 v_normal;      // Grecharged-directional-ambient: smooth per-vertex world normal (root-cause fix)
in vec4 v_tangent;     // Grecharged-pbr-realtime-fusion REOPEN#7: per-vertex tangent (xyz world, w handedness)
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
// (u_pbr_uv_tile is GONE. ★ OWNER CHECKER VERDICT, BUG A, 2026-07-26: every map — height, normal,
//  roughness, AO, specular, emissive — must sample at EXACTLY the base colour's uv, with no
//  separate multiplier anywhere. The world-scale reasoning belongs to the displacement AMPLITUDE
//  only, and lives in pom_depth_uv() below.)
// ROUND 20: THIS material's MEASURED authored UV density, in texture tiles per world metre
// (measured at level load, see background_common.cpp measure_uv_density_tfrag/_tie). Converts the
// parallax depth from metres into the UV units the offset lives in.
uniform float u_pbr_uv_per_m;
// ROUND 20 correction: this height MAP's characteristic feature wavelength, in TILES (measured at
// load from the map's own mip-energy spectrum). The parallax depth follows the FEATURE size, the
// same law tfrag3_tess.tese displaces real vertices by — so Parallax and Tessellation show the
// same depth, produced two different ways.
uniform float u_pbr_height_lambda;
// ★ OWNER CHECKER VERDICT, BUG B (2026-07-26): "des chunks entiers (LA PLUPART) sont juste PLATS".
// 1 only on the TFRAG3_TESS program, i.e. only where the tessellation stages actually displaced
// real vertices. The POM used to be suppressed by the GLOBAL u_pbr_displacement == 2 setting, which
// silently killed the parallax on every draw the tess program does not cover — all TIE walls and
// props, shrubs, hfrag, and every patch past the tesc's 30 m gate — leaving them with NO
// displacement at all. Suppression is per-PROGRAM now, so nothing is ever left flat.
uniform int u_pbr_tess_active;
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
uniform float u_pbr_spec_intensity;  // menu SPECULAR INTENSITY slider (0..2, default 1)
// This material's MEAN tangent-space surface gradient (n.xy/n.z, clamped +-4), measured over
// every texel of <tex>_normal.png when the map is loaded (LoaderStages.cpp) and pushed per
// draw by PbrDrawBinder. Subtracting it makes the normal-map perturbation ZERO-MEAN — see the
// long comment at the sample site: a non-zero mean is a CONSTANT TILT of the whole material,
// and that tilt is what turned into the owner's hard brightness plates.
uniform vec2 u_pbr_normal_dc;
// PBR POLISH (owner playtest #17: "ça fait toujours juste bump map glorifié"). This material's
// HEIGHT-MAP statistics, measured over every texel of <tex>_height.png when it is decoded
// (LoaderStages.cpp) and pushed per draw by PbrDrawBinder: .x = the map's MEAN, .y = 0.5 / its
// robust (p2..p98) half-range. Every height consumer below reads the map through hnorm().
// The shipped maps are neither mean-centred nor normalised — leafyground spans 0.063..0.463
// (mean 0.322), wallplaster means 0.807, strawroof spans only 0.298..0.478 — so the naive
// (h - 0.5) the code used before both OFFSET whole materials (leafyground displaced net-INWARD by
// ~4.7 cm, wallplaster net-OUTWARD; a constant offset is not relief, and it steps against the
// unmapped neighbour exactly like the normal-map DC did) and threw away most of the amplitude
// (only 18-75% of the nominal range was ever reached). (0.5, 1.0) = identity, so a draw without a
// height map is bit-for-bit unchanged.
uniform vec2 u_pbr_height_stat;
// REOPEN #3 TERM BISECTION (owner: the plastic sheen SURVIVES specular-intensity = 0, so
// it is NOT in the slider-scaled specular sum — identify the culprit by zeroing ONE term
// at a time on device). Prop debug.opengoal.pbr.bisect, default 0 = full path unchanged.
// Set bit => that term is ZEROED/DISABLED in the fused rt+pbr branch:
//    1 = yellow-sun GGX specular          2 = green-sun GGX specular
//    4 = ambient/IBL specular (famb_spec) 8 = Fresnel-on-diffuse (the line-651 kd darkening)
//   16 = _specular-map F0 (fall back to metallic-derived)   32 = emissive
//   64 = normal-map perturbation (Nm = smooth N)           128 = parallax/POM
//  256 = detail-relight ratio fdetail     512 = baked-modulation lit/shadow fmod
// 1024 = C1 shoulder tone map (linear clamp instead)  2048 = fused-contrast fmod compress off
// 4096 = REOPEN #6 matte-dielectric ENVELOPE off (restores the old glossy sheen for A/B: the
//        default matte look vs the pre-#6 glass — the owner's "path active?" killswitch)
// ---- SUPERVISOR LIVE A/B FIX (2026-07-24): relief=0 smooth vs relief=2.5 HARD PLATES. The
// three bits below are the A/B killswitches for the three halves of that root cause; all
// three default to 0 == the NEW (fixed) behaviour, set the bit to get the old one back.
// 8192 = normal-map DC removal OFF (legacy: apply the map with its raw mean tilt)
// 16384 = macro lit/shadow terminator back on the normal-MAPPED Nm (legacy) instead of N
// 32768 = normal-map tangent frame back on the per-chunk UV tangent (legacy) instead of the
//         seam-stable world frame
// REOPEN #10: the IN-MENU "PBR ISOLATE" carousell (Recharged Settings) seeds this mask via the
// recharged_pbr_isolate setting so the OWNER can bisect the residual grass-facet term at his own
// vantage with NO adb (BOTH=0, NORMAL-MAP ONLY=128 [POM off], PARALLAX ONLY=64 [nm off], NEITHER=192).
// Prime suspect now (tangent frame proven continuous @ REOPEN#9, base normal smooth): the PARALLAX/
// POM at bit 128 — the steep march (below) samples the height map at a data-dependent iteration count;
// where it clips at UV-chart/triangle boundaries it can read a per-triangle offset that reads as a
// facet at high relief. The owner's PARALLAX-ONLY vs NORMAL-MAP-ONLY flip names it; the debug prop/env
// still override the mask for the supervisor's full-term headless A/B.
// ---- PBR POLISH, OWNER PLAYTEST #17 (2026-07-25). Same convention: 0 == the NEW behaviour,
// set the bit to get the previous build back, so every one of this round's fixes is a live A/B
// at the owner's own vantage with one setprop and no rebuild.
// 2097152 = height-field CAVITY / micro-AO off (the "flat in shadow" fix — the direction-
//           INDEPENDENT relief term that replaces the ~1.0 ambient RATIO)
// 4194304 = tess-eval displacement back to the ALIASED textureLod(...,0.0) height fetch
//           (legacy) instead of the mip matched to the tessellated vertex spacing
// 8388608 = direct N.L detail ratio back to its legacy wide [0.45, 1.9] clamp (the
//           "très contrasté à la lumière" half of the rebalance)
// ---- PBR POLISH, OWNER PLAYTEST #18 (2026-07-25) — GROUND relief. Same convention.
// 16777216 = tessellation level law back to the legacy DISTANCE-ONLY 128/d (read by
//            tfrag3_tess.tesc and .tese) instead of the world-space-edge-length law, so the
//            ground-density fix is a live same-vantage A/B.
// 33554432 = parallax GRAZING FADE + world-cm offset cap OFF, i.e. the legacy un-attenuated
//            0.08 UV offset back (the owner's "au sol le displacement est HORIZONTAL, ça s'étale
//            à plat" — see the POM march). Applies to BOTH POM branches.
//            This bit is 33554432 and NOT the next free-LOOKING 262144: 262144 was already taken
//            by round #17's ambient-relief A/B (the fdt_amb site below). The first device A/B run
//            of this round used the overloaded bit and measured the side effect at the SAME ORDER
//            OF MAGNITUDE as the parallax signal itself — it silently confounded both A/Bs. Always
//            scan ALL of *.frag/*.tesc/*.tese for a bit before claiming it is free.
uniform int u_pbr_bisect;
// REOPEN #3 DISPLACEMENT carousel: 0 = Off (height_scale forced 0 C++-side), 1 = Parallax
// (steep POM below, the default = pre-carousel behaviour), 2 = Tessellation (displacement
// happens in the tess evaluation stage; the frag POM must then stand down).
uniform int u_pbr_displacement;
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

// Grecharged-pbr-realtime-fusion REOPEN#9 (owner playtest #9): a CONTINUOUS orthonormal tangent basis
// derived purely from the surface normal, used when the per-vertex tangent v_tangent is degenerate or
// unbound. Duff et al. 2017 "Building an Orthonormal Basis, Revisited" — branchless and numerically
// stable for EVERY normal (the denominator magnitude stays in [1,2]). Because it is a smooth function of
// the (already smooth, interpolated) per-vertex normal, the frame is CONTINUOUS across triangle edges —
// unlike the screen-space derivative frame (dFdx/dFdy), which is CONSTANT within a triangle and JUMPS at
// every edge and is the exact source of the hard triangular FACETS the owner sees scaling with relief.
// The tangent DIRECTION is arbitrary (no UV reference) but per-fragment continuity is what kills the
// facets — exactly the owner's mandate ("an arbitrary but CONTINUOUS per-vertex tangent kills the facets").
// SEAM-STABLE tangent frame for the NORMAL MAP (supervisor live A/B + offline weld measurement,
// 2026-07-24). Every tfrag/tie chunk owns its own UV layout, so the per-vertex UV-derived tangent
// frame is DISCONTINUOUS at chunk boundaries: measured over the welded cross-chunk vertex groups,
// 40.2% of village1 pairs (41.1% jungle) carry frames rotated more than 30 deg and 27% are outright
// MIRRORED (.w handedness disagrees) — i.e. the same physical surface decodes the normal map in a
// different, sometimes flipped, orientation on each side of the seam. This frame is derived ONLY
// from the (position-smoothed, seam-continuous) normal, so it is IDENTICAL on both sides of every
// chunk boundary by construction — the standard chunked-terrain fix. R is a deliberately skew axis:
// the unavoidable hairy-ball singularity then sits on a direction no level surface squarely faces
// (never up, never a cardinal wall), and the guard below keeps even that ~1 deg cone finite.
void stable_frame(vec3 n, out vec3 t, out vec3 b) {
  const vec3 R1 = vec3(0.3113, 0.1504, 0.9382);
  const vec3 R2 = vec3(0.9382, 0.3113, 0.1504);
  vec3 tt = cross(n, R1);
  float l = length(tt);
  t = (l > 0.02) ? (tt / l) : normalize(cross(n, R2));
  b = cross(n, t);
}

void frisvad_basis(vec3 n, out vec3 t, out vec3 b) {
  float s = n.z >= 0.0 ? 1.0 : -1.0;
  float a = -1.0 / (s + n.z);
  float d = n.x * n.y * a;
  t = normalize(vec3(1.0 + s * n.x * n.x * a, s * d, -s * n.x));
  b = normalize(vec3(d, s + n.y * n.y * a, -n.y));
}

#ifdef OG_PBR
// PBR POLISH (owner playtest #17) — MATERIAL-SCALED HEIGHT. Recentre the height map on ITS OWN
// mean and refill the 0..1 range, using the statistics measured per material at load time (see
// u_pbr_height_stat). EVERY height consumer in the pipeline goes through this: the POM march, the
// self-shadow, the cavity term and (with the same expression, same uniform) the tess-eval
// displacement. Consequences, all of them the owner's report:
//   - "material-scaled displacement amplitude": a map that only spans 0.30..0.48 (strawroof) no
//     longer displaces at a fifth of the amplitude a map spanning 0.00..0.75 (stonewall) gets.
//     Every material now reaches the full authored displacement, so one relief slider means the
//     same physical depth everywhere.
//   - the net inward/outward OFFSET disappears: a material whose mean is 0.32 was pushing its
//     whole surface ~4.7 cm INTO the ground (and stepping against its unmapped neighbour at the
//     material border — the same class of defect the normal-map DC removal already fixed).
// Identity when the material has no measured statistics (0.5, 1.0) => unchanged.
float hnorm(float h) {
  return clamp((h - u_pbr_height_stat.x) * u_pbr_height_stat.y + 0.5, 0.0, 1.0);
}

// ---- PARALLAX (POM) DEPTH LAW — rebuilt, OWNER 2026-07-26 ----
// Shared by BOTH POM marches (the fused rt+pbr path and the rt-OFF standalone fallback), because
// every symptom the owner reported is a property of the formula, not of one branch.
//
// OWNER: "le parallax rend complètement plat" ... "AUTANT SUR LES MURS QUE LE SOL". The second half
// is the diagnostic one: on a wall viewed head-on the grazing fade is ~1, so the fade could not be
// the cause. The cause was the ABSOLUTE world cap I had stacked on top of it:
//     pom_cap = min(POM_MAX_TAN * height_scale, POM_MAX_WORLD_M * uv_per_m)     [old]
// with POM_MAX_WORLD_M = 0.03 m flat. Plugging in the measured village materials, the second term
// ALWAYS won: wallplaster uv_per_m 0.439 -> cap 0.0132 UV, leafyground 0.127 -> cap 0.0038 UV,
// against a marched vector of 0.075 UV. The offset was clipped to 5-17 % of its length on every
// shipped material, at every view angle, walls included. 3 cm is not a small depth cue for these
// materials — leafyground's height features are ~2 m across, so 3 cm of lateral shift is nothing.
//
// THE FIX is to stop expressing the depth as an arbitrary absolute and derive it from the MATERIAL,
// exactly like the tessellation tier already does: depth = f(this map's feature wavelength), in
// metres, converted to UV with this material's measured density. Parallax and Tessellation then
// show the SAME depth by construction — they differ only in how it is produced (UV march vs real
// vertices), which is what makes flipping DISPLACEMENT between them read as a quality change and
// not as a depth change.
//
// tan(theta) = |Vt.xy| / Vt.z, so gating on Vt.z gates on the view angle: 0.15 ~= 81 deg off the
// surface normal, 0.50 = 60 deg.
#define POM_GRAZE_LO 0.15
#define POM_GRAZE_HI 0.50
// OWNER 2026-07-26: the grazing attenuation is a gentle FLOOR now, never a kill. At the most
// extreme grazing the offset keeps this fraction of its strength — enough that the relief still
// reads at ordinary gameplay camera angles (which ARE grazing on a floor), while the sideways-smear
// regime the earlier "ça s'étale à plat" report described is still damped. The steep march below
// (16-32 layers with occlusion + secant refine) is what actually keeps grazing views honest.
#define POM_GRAZE_FLOOR 0.35
// The lateral shift may never exceed the feature depth itself (tan(theta) <= 1)...
#define POM_MAX_TAN 1.0
// ...nor this fraction of ONE HEIGHT FEATURE of apparent sliding. Relative, so it scales with the
// material the way the depth does, instead of clipping every material to the same absolute.
#define POM_MAX_FEATURE_FRAC 0.35
// The amplitude law itself, kept numerically IDENTICAL to tfrag3_tess.tese's (TESS_DEPTH_K,
// TESS_DEPTH_MAX_RATIO, TESS_DEPTH_MAX_M and its 0.005*relief floor) so the two displacement tiers
// cannot drift apart. Change one, change both.
#define POM_DEPTH_K 5.0
#define POM_DEPTH_MAX_RATIO 0.5
#define POM_DEPTH_MAX_M 0.15

// This material's parallax depth, in UV units, plus its feature wavelength in metres (out param,
// used for the relative offset cap). uv_per_m converts metres -> UV: one metre of world spans
// uv_per_m tiles of texture, and the parallax offset is a UV offset.
float pom_depth_uv(out float lambda_world_m) {
  float upm = max(u_pbr_uv_per_m, 0.02);
  float tile_m = 1.0 / upm;
  lambda_world_m = clamp(u_pbr_height_lambda, 0.002, 1.0) * tile_m;
  float rel = u_pbr_height_scale * 20.0;  // the relief slider (height_scale = 0.05 * relief)
  float amp_m = u_pbr_height_scale * POM_DEPTH_K * lambda_world_m;
  amp_m = min(amp_m, POM_DEPTH_MAX_RATIO * lambda_world_m);  // never a spike field
  amp_m = min(amp_m, POM_DEPTH_MAX_M * (0.5 + 0.5 * rel));   // never deeper than a step
  amp_m = max(amp_m, 0.005 * rel);
  return amp_m * upm;
}

// Grecharged-pbr-realtime-fusion PBR POLISH (owner playtest #16, defect 2 "completely FLAT in
// shadow"). The realtime AMBIENT IRRADIANCE for an arbitrary direction — the same selector the
// fused branch already used for its ambient-specular source, lifted into a function so the
// INDIRECT DIFFUSE can be evaluated twice (smooth normal vs normal-mapped normal) and the relief
// therefore survives where no sun reaches. Identical expressions => the ambient-specular term it
// replaces is bit-for-bit unchanged.
vec3 rt_amb_eval(vec3 n) {
  if (u_rt_ambient_on == 0) {
    return vec3(clamp(u_rt_shadow_residual, 0.0, 1.0));
  } else if (u_rt_ambient_model == 1) {
    return rt_sh_ambient(n);
  } else if (u_rt_ambient_model == 2) {
    return rt_ibl_ambient(n);
  }
  return mix(u_rt_ground_color, u_rt_sky_color, clamp(n.y * 0.5 + 0.5, 0.0, 1.0));
}

// Grecharged-pbr-realtime-fusion PBR POLISH (owner playtest #16, defect 3: the displacement
// "reads FLAT ... un bump map glorifie avec un peu de normales").
// HEIGHT-FIELD SELF-SHADOWING. What separates real surface depth from a shaded bump is that a
// raised texel CASTS A SHADOW on the texels behind it. Neither tier produced any: an audit of
// every tex_PBR_H fetch in this shader found the height map driving a UV offset (POM) and a
// vertex offset (tess-eval) and NOTHING ELSE — it never occluded a light, so the relief had no
// contact shadow and read as shading, not as geometry.
// This is the standard relief-mapping soft shadow (Policarpo/Kaneko): march the height field from
// the shading point toward the light in TANGENT-UV space and keep the largest amount by which an
// occluder rises ABOVE the ray. The (1 - t) weight makes distant occluders soften into a penumbra
// instead of a hard aliased edge, which also keeps it stable under motion.
//   uv0   = the (parallax-corrected) UV of the shading point
//   h0    = height at uv0
//   Ltuv  = light direction in the SAME tangent-UV frame the POM marches in (xy = uv plane)
//   hs_uv = the UV distance that corresponds to one full height unit (the POM's depth scale)
// Returns a visibility multiplier in [PBR_MS_FLOOR, 1].
float pbr_micro_shadow(vec2 uv0, float h0, vec3 Ltuv, float hs_uv) {
  const int PBR_MS_STEPS = 6;
  const float PBR_MS_K = 3.0;       // occluder-height -> darkness gain
  const float PBR_MS_FLOOR = 0.35;  // never fully black: ambient still reaches a crevice
  // Light at/below the surface horizon: the macro terminator already handles that face — do not
  // double-darken it (and the march direction would be degenerate).
  float lz = Ltuv.z;
  if (lz < 0.08) {
    return 1.0;
  }
  vec2 sd = (Ltuv.xy / lz) * hs_uv;
  // Same surface-lock bound as the POM march: the shadow ray may never wander a whole tile away
  // from the shading point, or the "shadow" stops belonging to this piece of surface.
  float sl = length(sd);
  if (sl > 0.08) {
    sd *= 0.08 / sl;
  }
  float occ = 0.0;
  for (int i = 1; i <= PBR_MS_STEPS; i++) {
    float t = float(i) / float(PBR_MS_STEPS);
    float hs = hnorm(textureLod(tex_PBR_H, uv0 + sd * t, 0.0).r);
    // ray height above the shading point, rising to the top of the height range at t = 1
    float ray = h0 + t * (1.0 - h0);
    occ = max(occ, (hs - ray) * (1.0 - t));
  }
  return clamp(1.0 - occ * PBR_MS_K, PBR_MS_FLOOR, 1.0);
}

// ===================================================================================================
// PBR POLISH — OWNER PLAYTEST #17: "à l'ombre c'est toujours plat" (still completely flat in shade).
//
// THE MATH ROOT CAUSE, found by reading the term that was supposed to do this job. Round #16 added
// an ambient relief term expressed as the RATIO rt_amb_eval(Nm) / rt_amb_eval(N) — the irradiance
// at the normal-mapped normal over the irradiance at the smooth one. That is only ever as strong
// as the ambient's DIRECTIONAL VARIATION, and ours (the accepted baked-modulation composite, plus
// a hemisphere/SH ambient that is deliberately soft) is very nearly direction-INVARIANT. Measured
// shader-exact over all 7 shipped materials, that ratio has mean 0.960..0.996 — i.e. between 0.4%
// and 4% away from exactly 1.0. You cannot extract relief from a function that does not vary with
// the normal. In cast shadow every other normal-dependent term is already zero (sun_occ = 0 kills
// both direct N.L cues, matte_gate kills the env specular on any rough dielectric), so a shadowed
// fragment really was baked x constant x _ao. Flat, by arithmetic.
//
// THE FIX is the one modern games use, and it is the one thing that cannot fail this way: a term
// with NO direction dependence at all. Read the relief straight out of the HEIGHT FIELD as a
// CAVITY / micro-ambient-occlusion factor — a texel that sits BELOW its local neighbourhood is in
// a crevice and receives less skylight; one that sits ABOVE is a ridge and receives more. That is
// physically the ambient-occlusion of the micro-relief, it is defined at every fragment, and it is
// exactly as strong at midnight in a cast shadow as it is in full sun.
//
// MEAN-PRESERVING BY CONSTRUCTION, not by tuning: the driving signal is a HIGH-PASS of the height
// field (the texel minus its own local mean), so its mean over any surface patch is zero, hence
// the multiplier's mean is 1.0 and the accepted overall brightness cannot drift. A material with
// no height map gets no cavity at all and stays bit-for-bit as it was.
//
// BAND-LIMITED BY CONSTRUCTION: the fine tap is taken at the mip the hardware would fit for this
// fragment's own UV footprint (never a lod-0 fetch of a ~1 mm texel from 20 m away, which is the
// aliasing that produced earlier rounds' shimmer), and the blur tap is PBR_CAV_SPAN mips coarser.
// Far away the two taps converge and the term fades to exactly 1.0 — correct, because relief finer
// than a pixel has no business modulating that pixel.
// ===================================================================================================
#define PBR_CAV_SPAN 3.0   // mips between the fine and the local-mean tap (a ~8x8 texel neighbourhood)
#define PBR_CAV_GAIN 1.6   // normalised-height high-pass -> darkness/brightness gain
#define PBR_CAV_MIN 0.55   // a crevice is dark, never black: skylight still reaches into it
#define PBR_CAV_MAX 1.45
float pbr_cavity(vec2 uv0) {
  vec2 ts = vec2(textureSize(tex_PBR_H, 0));
  vec2 dx = dFdx(uv0) * ts;
  vec2 dy = dFdy(uv0) * ts;
  float lod = clamp(0.5 * log2(max(max(dot(dx, dx), dot(dy, dy)), 1e-12)), 0.0, 11.0);
  float hf = hnorm(textureLod(tex_PBR_H, uv0, lod).r);
  float hb = hnorm(textureLod(tex_PBR_H, uv0, min(lod + PBR_CAV_SPAN, 12.0)).r);
  return clamp(1.0 + PBR_CAV_GAIN * (hf - hb), PBR_CAV_MIN, PBR_CAV_MAX);
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
        // REOPEN#7 FOUNDATION FIX: build the TBN from the per-vertex MikkTSpace tangent v_tangent
        // (interpolated => CONTINUOUS across triangle edges / UV seams) instead of screen-space
        // derivatives, which were discontinuous there => the owner's incoherent relief + the hard
        // CONTRAST CRACKS that grew with relief. N is the reconstructed smooth normal; Gram-Schmidt
        // re-orthonormalizes the interpolated tangent against it per fragment; .w carries handedness.
        // A degenerate/unbound tangent (len~0 => (0,0,0,1) default) falls back to the derivative frame.
        // fTuv/fBuv = the UV-derived frame. It is the ONLY frame that can drive a UV OFFSET, so
        // the POM march below MUST keep using it (a world-derived frame would shift the height
        // march in a direction unrelated to the texture = the "floating/epoxy" parallax of
        // owner playtest #5). fTn/fBn = the frame the NORMAL MAP is decoded in — that one is
        // swapped for the seam-stable world frame further down.
        vec3 fTuv, fBuv;
        // REOPEN#9 (owner playtest #9) tangent-fallback coverage flag (for the u_pbr_debug==20 viz + the
        // pbr_tan_diag.txt CPU proof): 1.0 = this fragment took the degenerate-tangent fallback.
        float f_tan_fb = (dot(v_tangent.xyz, v_tangent.xyz) > 0.04) ? 0.0 : 1.0;
        if (dot(v_tangent.xyz, v_tangent.xyz) > 0.04) {
          fTuv = normalize(v_tangent.xyz - N * dot(N, v_tangent.xyz));
          // OWNER PLAYTEST #8: use the SIGN of the interpolated handedness, not its raw magnitude.
          // The interpolated .w can pass through 0 across a strip whose vertices carry opposite
          // handedness, which would SHRINK the bitangent mid-triangle (a per-triangle discontinuity
          // that reads as a facet). sign() keeps a full-length, continuous bitangent.
          fBuv = cross(N, fTuv) * (v_tangent.w < 0.0 ? -1.0 : 1.0);
        } else {
          // REOPEN#9 (owner playtest #9): v_tangent is degenerate/unbound here. The OLD code rebuilt the
          // TBN from screen-space derivatives (dFdx/dFdy) — a per-triangle-CONSTANT frame that JUMPS at
          // every edge => the hard triangular FACETS the owner saw scaling with relief. Derive a
          // CONTINUOUS basis from the smooth interpolated normal N instead (NEVER a screen derivative).
          frisvad_basis(N, fTuv, fBuv);
        }
        // ===================================================================================
        // PBR POLISH — OWNER PLAYTEST #16 DEFECT 1: "displacement in the WRONG DIRECTION in
        // places on the SAME texture".
        // stable_frame() is a function of the surface NORMAL and of nothing else, so its U axis
        // ROTATES as the surface tilts. The same material therefore decodes its height field
        // turned by an arbitrary, orientation-dependent angle from one patch to the next: over a
        // hill the relief's lighting direction sweeps with the slope, and between surfaces facing
        // opposite ways it flips outright — wherever that rotation passes ~90 deg the perceived
        // relief INVERTS and bumps read as pits. That is exactly the owner's defect, and it is
        // structural: a height field authored in TEXTURE space can only be lit correctly in the
        // frame its own UVs define. No parameter tune can fix a frame that ignores the texture.
        // The world frame was adopted to kill the per-chunk brightness plates — but the plates
        // were MEASURED to come from the map's DC TILT (chunk-to-chunk spread 61.4% -> 3.0% once
        // u_pbr_normal_dc is subtracted), and that fix is FRAME-INVARIANT: rotating a zero-mean
        // gradient leaves it zero-mean, so it cannot produce a brightness step in any frame. The
        // normal map goes back into the UV frame it was authored in, where the relief direction is
        // right by construction and the grain finally lines up with the albedo it belongs to.
        // Bonus: the POM march below already had to use the UV frame (it is the only frame a UV
        // OFFSET can be expressed in), so the parallax shift and the normal-map shading were
        // pointing in DIFFERENT directions — they now agree, which is the other half of the
        // "displacement direction" defect.
        // stable_frame survives as (a) the fallback where no per-vertex tangent exists — there is
        // no UV reference to use there, and a continuous arbitrary frame still beats a
        // per-triangle one — and (b) bisect bit 32768, the live A/B killswitch (SET = the old
        // world frame, so the owner's previous build is one prop away).
        // ===================================================================================
        vec3 fTn = fTuv, fBn = fBuv;
        if ((u_pbr_bisect & 32768) != 0 || f_tan_fb > 0.5) {
          stable_frame(N, fTn, fBn);
        }
        // ★ OWNER CHECKER VERDICT, BUG A: the SAME uv the base colour is sampled with (line ~600,
        // `texture(tex_T0, tex_coord.xy)`), no multiplier. Every map below — height, normal,
        // roughness, metallic, AO, specular, emissive — rides this one variable, so the relief can
        // only ever line up with the pattern that drew it.
        vec2 uv = tex_coord.xy;
        // Height map (bit 16): the same mobile-tuned POM march as the standalone path
        // (already proven on Adreno 618 there — same cost class, so it ships here too).
        // ★ BUG B: gated on u_pbr_tess_active, NOT on the global u_pbr_displacement. A draw only
        // skips the march when THIS program actually tessellated it; every draw the tess program
        // does not cover (TIE walls and props, shrubs, hfrag, non-opaque trees, anything past the
        // 30 m tesc gate) keeps its parallax instead of going flat.
        if ((u_pbr_mode & 16) != 0 && u_pbr_debug != 8 && u_pbr_height_scale > 0.0 &&
            (u_pbr_bisect & 128) == 0 && u_pbr_tess_active == 0) {
          vec3 Vt = normalize(vec3(dot(Vv, fTuv), dot(Vv, fBuv), max(dot(Vv, N), 0.0)));
          float vz = max(Vt.z, 0.20);
          // ===========================================================================
          // PBR POLISH — OWNER PLAYTEST #18: "le displacement du parallax est HORIZONTAL
          // au sol, comme si au lieu de s'élever, ça s'étale à plat."
          // He is describing the formula's own failure mode, exactly. The offset is
          //     P = (Vt.xy / Vt.z) * depth        i.e.  |P| = depth * tan(theta)
          // so on a near-horizontal FLOOR viewed by the ordinary gameplay camera — which
          // looks ALONG the ground, theta -> 90 deg — the amplifier blows up and P
          // degenerates into a large HORIZONTAL UV TRANSLATION. The texture slides
          // sideways instead of reading as depth: "ça s'étale à plat". The old 0.08 UV
          // clamp bounded the magnitude but not the NATURE of the artifact, and 0.08 UV is
          // ~16 cm of world sliding at the authored ground UV density — enormous.
          // THE FIX (industry-standard POM attenuation, two parts):
          //  (1) GRAZING FADE, and
          //  (2) an absolute POM_MAX_WORLD_M = 3 cm world cap.
          // ★ BOTH WERE OVER-CORRECTIONS, and (2) was the fatal one — OWNER 2026-07-26:
          // "le parallax rend complètement plat ... AUTANT SUR LES MURS QUE LE SOL". A wall
          // seen head-on has pom_graze ~= 1, so the fade could not explain it; the flat
          // 3 cm cap could, and did. Measured on the shipped materials it clipped the
          // marched vector to 5-17 % of its length at EVERY angle (see the constants block
          // for the numbers). Both parts are rebuilt:
          //  (1') the fade is now a gentle FLOOR (POM_GRAZE_FLOOR) — damped at extreme
          //       grazing, never killed, because the ordinary gameplay camera IS grazing
          //       on a floor and that is precisely where the owner needs to see depth;
          //  (2') the cap is RELATIVE to the material: the feature depth itself
          //       (POM_MAX_TAN, tan(theta) <= 1) and a fraction of one feature wavelength
          //       (POM_MAX_FEATURE_FRAC). No absolute constant clips a whole material any
          //       more, and the depth itself now comes from pom_depth_uv() — the same
          //       feature-scaled law tfrag3_tess.tese displaces real vertices by.
          // Bisect bit 33554432 = the legacy un-faded 0.08 UV offset, so this is still a
          // live same-vantage A/B with one setprop.
          // ===========================================================================
          float pom_graze =
              mix(POM_GRAZE_FLOOR, 1.0, smoothstep(POM_GRAZE_LO, POM_GRAZE_HI, Vt.z));
          float lambda_world_m;
          float depth_uv = pom_depth_uv(lambda_world_m);
          float pom_cap = min(POM_MAX_TAN * depth_uv,
                              POM_MAX_FEATURE_FRAC * lambda_world_m * max(u_pbr_uv_per_m, 0.02));
          // Bisect bit 33554432 restores the ROUND-20 law EXACTLY — the build the owner played and
          // called "complètement plat", not some older variant — so before/after is one setprop
          // apart at the same vantage in the same boot. (It used to restore a pre-round-20 cell,
          // which made the A/B measure the wrong pair: round 20's 3 cm world cap is the term that
          // actually flattened it, and that cell never exercised it.)
          if ((u_pbr_bisect & 33554432) != 0) {
            pom_graze = smoothstep(POM_GRAZE_LO, POM_GRAZE_HI, Vt.z);  // r20: fade to ZERO
            depth_uv = u_pbr_height_scale;                             // r20: raw UV depth scale
            pom_cap = min(POM_MAX_TAN * u_pbr_height_scale,
                          0.03 * max(u_pbr_uv_per_m, 0.02));           // r20: flat 3 cm world cap
          }
          // REOPEN #3: STEEP POM tier — 16 steps head-on to 32 at grazing (was 10-28);
          // the loop bound below already allows 32. Occlusion test + secant interpolation
          // (the industry steep-parallax + refinement) were already in place.
          float n_layers = mix(32.0, 16.0, clamp(Vt.z, 0.0, 1.0));
          // REOPEN #6 SURFACE-LOCK (owner playtest #5: the "10cm epoxy float, texture moves
          // differently than the model"). Build the TOTAL parallax vector P and CLAMP its
          // length so the offset can never exceed a small, surface-locked bound: the depth
          // reads from the surface itself, never from clear epoxy floating in front of it.
          // duv_step marches P/n_layers.
          vec2 P = (Vt.xy / vz) * depth_uv * pom_graze;
          float Plen = length(P);
          if (Plen > pom_cap) P *= pom_cap / Plen;
          // Degenerate (head-on, or a zero-depth material) => skip the march and its taps.
          if (Plen > 1e-6) {
            vec2 duv_step = P / n_layers;
            float layer_d = 1.0 / n_layers;
            float cur_d = 0.0;
            float map_d = 1.0 - hnorm(textureLod(tex_PBR_H, uv, 0.0).r);
            float prev_map_d = map_d;
            for (int i = 0; i < 32; i++) {
              if (cur_d >= map_d || float(i) >= n_layers) {
                break;
              }
              uv -= duv_step;
              prev_map_d = map_d;
              map_d = 1.0 - hnorm(textureLod(tex_PBR_H, uv, 0.0).r);
              cur_d += layer_d;
            }
            float after = map_d - cur_d;
            float before = prev_map_d - (cur_d - layer_d);
            float w = clamp(before / max(before - after, 1e-5), 0.0, 1.0);
            uv += duv_step * (1.0 - w);
          }
        }
        // PBR POLISH — inputs for the HEIGHT-FIELD SELF-SHADOW (owner defect 3: the relief reads
        // as "un bump map glorifie"). Sampled at the FINAL (parallax-corrected) uv so the shadow
        // belongs to the texel actually being shaded, and computed for BOTH displacement tiers:
        // tessellation moves the macro geometry but the map's micro relief still has to shadow
        // itself, otherwise the fine detail stays as flat as it was in the parallax tier.
        // fh_ms_uv is the POM's own depth scale = the UV distance a full height unit spans, so the
        // shadow ray has exactly the same slope the parallax offset assumes. Distance-gated: the
        // 6 taps only run near the camera, where relief is resolvable at all.
        float fh0 = 1.0;
        float fh_ms_uv = 0.0;
        if ((u_pbr_mode & 16) != 0 && u_pbr_height_scale > 0.0 && (u_pbr_bisect & 524288) == 0 &&
            length(v_fringe_rel) < 35.0) {
          // PBR POLISH #17: normalised, so the shadow ray and the occluder heights it compares
          // against live in the SAME material-scaled space the march assumes. On the shipped maps
          // this alone strengthens the contact shadow a lot: a map that only spanned 0.18 of the
          // range could never raise an occluder far enough above the ray to darken anything.
          fh0 = hnorm(textureLod(tex_PBR_H, uv, 0.0).r);
          // Same feature-scaled depth the march uses, so the shadow ray's slope matches the relief
          // it is casting from (it used to be the raw UV height scale, a different depth entirely).
          float fh_lambda_m;
          fh_ms_uv = pom_depth_uv(fh_lambda_m);
        }
        // Normal map (bit 1) perturbs the SMOOTH normal => surface detail that shades
        // correctly as the realtime suns move (the fusion's whole point).
        vec3 Nm = N;
        // REOPEN #3 SHIMMER FIX: Toksvig widening FROM THE FITTED MIP. texture() samples
        // the normal map at the hardware-fitted mip (maps upload with glGenerateMipmap +
        // LINEAR_MIPMAP_LINEAR); mip-averaged normals SHORTEN, and that lost length IS the
        // sub-pixel normal variance the renormalize below would otherwise throw away —
        // exactly the high-relief sparkle. Captured (strength-scaled, so the relief slider
        // widens it too) into fnmip_var and added to the GGX alpha at the spec-AA site.
        float fnmip_var = 0.0;
        // Scaled, DC-REMOVED tangent-space surface gradient of this fragment (0 where no normal
        // map): reused below for the mean-preserving detail term.
        vec2 fg = vec2(0.0);
        if ((u_pbr_mode & 1) != 0 && u_pbr_debug != 7 && (u_pbr_bisect & 64) == 0) {
          vec3 nraw = texture(tex_PBR_N, uv).xyz * 2.0 - 1.0;
          // Toksvig variance is measured on the RAW sample. (It used to be measured AFTER the
          // strength scale, where length() saturates the 1.0 clamp for any relief above ~0.4 and
          // the whole spec-AA term silently died — exactly where shimmer is worst.)
          float fnlen = clamp(length(nraw), 1e-4, 1.0);
          fnmip_var = ((1.0 - fnlen) / max(fnlen, 0.5)) * clamp(u_pbr_normal_strength, 0.0, 3.0);
          // ================= THE PLATE FIX (owner A/B relief 0 vs 2.5, 2026-07-24) =============
          // Work in SURFACE GRADIENT space (g = n.xy/n.z, the height-field slope) rather than
          // scaling n.xy and renormalising: scaling a gradient IS scaling the height field, the
          // physically meaningful "relief strength", and it makes the DC removal below exact at
          // any strength.
          // u_pbr_normal_dc is this material's MEAN gradient over the whole map. It is NOT zero:
          // measured on the shipped set, every map carries a systematic tilt (leafyground DC =
          // (+0.076, -0.227) in normal space => 61 deg of CONSTANT tilt once the relief slider
          // multiplies it by 7.5 at relief 2.5). A constant tilt of an entire material is not
          // relief — it re-aims the whole surface at/away from the sun, so the material reads
          // ~35-48% darker than the neighbouring surfaces that have no normal map, and it reads
          // DIFFERENTLY in each chunk because each chunk decodes it in its own UV frame. That is
          // precisely the owner's hard dark/light plates, and precisely why they scale with relief
          // and vanish at relief 0. Subtracting the DC makes the perturbation ZERO-MEAN: pure
          // relief, no net re-aim. Offline (shader-exact) on the grass at relief 2.5: chunk-to-
          // chunk brightness spread 61.4% -> 3.0%. Bit 8192 restores the raw map for the A/B.
          vec2 g = clamp(nraw.xy / max(nraw.z, 0.05), vec2(-4.0), vec2(4.0));
          if ((u_pbr_bisect & 8192) == 0) {
            g -= u_pbr_normal_dc;
          }
          fg = clamp(g * u_pbr_normal_strength, vec2(-8.0), vec2(8.0));
          vec3 nmt = normalize(vec3(fg, 1.0));
          Nm = normalize(mat3(fTn, fBn, N) * nmt);
          // GLASS-PANE fix (owner preset report 2026-07-23): the old hard snap back to
          // the SMOOTH normal (`if (dot(Nm,gN)<0) Nm = N`) wiped the map grain over
          // whole grazing-angle patches — relief >1 tips many texels past the face
          // plane, and every highlight/reflection term there (NdH/NdV/Rf/Fresnel)
          // followed the flat polygon = the "glass sheet over the material". SLIDE the
          // perturbed normal back to just above the horizon instead: the below-horizon
          // component is removed but the tangential GRAIN survives.
          // OWNER PLAYTEST #8 (faceted grass): the horizon reference here was the PER-FACE
          // screen-space normal gN = cross(dFdx,dFdy), which is CONSTANT within a triangle and
          // JUMPS across edges — so this clamp injected a per-triangle discontinuity into Nm =>
          // exactly the hard triangular patches the owner saw (the base v_normal is otherwise
          // ~96% smooth per the offline [gda-facet] measurement). Clamp against the SMOOTH,
          // interpolated base normal N instead: continuous across faces => no facets, while
          // still keeping the perturbed normal out of the surface backside.
          float fnd = dot(Nm, N);
          if (fnd < 0.04) Nm = normalize(Nm + N * (0.04 - fnd));
        }
        vec4 T0p = texture(tex_T0, uv);
        vec3 albedo = pow(T0p.rgb, vec3(2.2));
        // REOPEN 2026-07-23 roughness CONVENTION AUDIT: the loader uploads _roughness as
        // plain linear GL_RGBA (LoaderStages make_map — no GL_SRGB internal format, no
        // hardware decode), so .r IS the authored PERCEPTUAL roughness; the GGX lobe uses
        // alpha = roughness^2 (industry squaring) below. Perceptual floor 0.045 doubles as
        // the specular-AA minimum (no mirror-edge fireflies).
        // REOPEN #2 MISSING-ROUGHNESS=ROUGH (industry rule): an absent _roughness map now
        // reads 0.9 — internet-pack bases without maps must NEVER get a smooth plastic sheen.
        float rough = (u_pbr_mode & 2) != 0 ? texture(tex_PBR_R, uv).r : 0.9;
        // REOPEN dielectric rule: most owner sets are height/normal/roughness only — a
        // MISSING _metallic map means metal = 0.0 (stone/straw/dirt are dielectrics,
        // constant F0 = 0.04; never assume metalness).
        float metal = (u_pbr_mode & 4) != 0 ? texture(tex_PBR_M, uv).r : 0.0;
        float ao = (u_pbr_mode & 8) != 0 ? texture(tex_PBR_AO, uv).r : 1.0;
        // REOPEN #3 BISECT VERDICT (mask 16): _specular read as RAW F0 (the test map's
        // linear mean is 0.217, p95 0.426 — 5-10x the 0.04 dielectric norm) inflated
        // Fresnel on every texel and the ambient-specular term turned that into the
        // plastic film. Industry (UE) convention: on a DIELECTRIC a "specular" map only
        // tunes F0 within [0, 0.08]; the raw map survives as a true specular COLOR only
        // where _metallic declares metalness.
        vec3 F0;
        if ((u_pbr_mode & 32) != 0 && (u_pbr_bisect & 16) == 0) {
          vec3 spec_raw = pow(texture(tex_PBR_S, uv).rgb, vec3(2.2));
          F0 = mix(min(spec_raw, vec3(0.08)), spec_raw, metal);
        } else {
          F0 = mix(vec3(0.04), albedo, metal);
        }
        float NdV = max(dot(Nm, Vv), 1e-4);
        // REOPEN geometric SPECULAR AA: widen the GGX alpha by the normal-map's screen-
        // space variance (Toksvig-style) so normal-mapped ground never sparkles. One-way:
        // only ever widens the lobe.
        rough = clamp(rough, 0.045, 1.0);
        float fa = rough * rough;  // alpha = perceptual roughness squared (industry)
        vec3 fnddx = dFdx(Nm);
        vec3 fnddy = dFdy(Nm);
        float fnvar = 0.25 * (dot(fnddx, fnddx) + dot(fnddy, fnddy));
        // REOPEN #3: screen-derivative variance (geometric edges) + Toksvig-from-mip
        // variance (sub-texel normal detail at the fitted mip) both widen the lobe;
        // perceptual min-rough 0.045 above stays the floor. One-way: only ever rougher.
        fa = clamp(fa + min(fnvar, 0.18) + min(fnmip_var, 0.35), 0.002, 1.0);
        float fa2 = fa * fa;
        // REOPEN roughness-aware FRESNEL ceiling (Fdez-Aguera): the grazing-angle limit is
        // max(1-roughness, F0), NOT 1.0 — a rough floor seen edge-on can no longer blow out
        // into the white mirror-edge sheen (the owner's "surcouche plastique" at ground +
        // extreme angles).
        vec3 Fceil = max(vec3(1.0 - rough), F0);
        // ===============================================================================
        // REOPEN #6 MATTE-DIELECTRIC DEFAULT (owner playtest #4 + 5-screenshot decomposition:
        // "Lighting-only" is GOOD, the glass appears ONLY when PBR is on => the glass IS the
        // specular / env-reflection term made VISIBLE on MATTE materials where it must not be).
        // Industry truth: a rough dielectric (stone/sand/grass/wood = all of village1) reflects
        // almost NOTHING — its microfacet lobe is so broad the peak radiance is negligible and
        // view-STABLE. So the ENTIRE specular contribution (direct GGX of both suns + the
        // ambient/env reflection) is driven toward ~0 as roughness rises: at rough >= ~0.60 the
        // surface is fully MATTE (no sheen, no camera-dependent highlight). Only genuinely SMOOTH
        // (rough < 0.30) or METALLIC texels keep a visible highlight. This is the visible-highlight
        // ENVELOPE riding ON TOP of the physical BRDF, NOT a replacement — the normal-mapped
        // DIFFUSE relief the owner LIKES (fdetail below) is untouched, so PBR-ON = Lighting-only
        // + depth, MINUS the gloss. Bisect bit 4096 = envelope OFF (device A/B killswitch proving
        // the matte path is active: the old glassy sheen returns when set).
        float matte_gate = max(1.0 - smoothstep(0.30, 0.60, rough), metal);
        if ((u_pbr_bisect & 4096) != 0) matte_gate = 1.0;
        // ===============================================================================
        // REOPEN OWNER ARCHITECTURE: BASE = the validated BAKED-MODULATION composite (the
        // fought-for object relief) — the baked influence ALWAYS remains; the PBR layer
        // only rides on top. Identical formula to the accepted pbr-OFF branch below, but
        // evaluated with the normal-MAP-perturbed Nm so material detail shades under the
        // realtime suns, plus a bounded micro/macro detail-relight ratio so the relief
        // stays alive inside fully-lit zones where the terminator smoothstep saturates.
        // ===============================================================================
        vec3 Mn = normalize(u_rt_moon_dir);
        // MACRO LIGHTING = GEOMETRY, MICRO DETAIL = THE MAP (owner A/B root cause, 2026-07-24).
        // This terminator drives fmod, the baked lit/shadow multiply, through a near-binary
        // smoothstep(0, 0.35) — feeding it the normal-MAPPED Nm let the map decide whether a
        // whole material region counts as LIT or as SHADOWED, so any systematic tilt in the map
        // (see the DC comment above) flipped entire regions between the lit and the shadow
        // multiplier: a hard plate with no geometric cause. The map's contribution belongs in the
        // bounded fdetail ratio below, not in the macro gate. Taking the terminator from the
        // smooth normal N also makes fmod the SAME expression as the accepted pbr-OFF branch,
        // which is the owner's acceptance criterion made structural: PBR ON == Lighting-only,
        // PLUS depth. Bit 16384 = legacy (terminator from Nm) for the device A/B.
        vec3 fNterm = ((u_pbr_bisect & 16384) != 0) ? Nm : N;
        float fterm_y = smoothstep(0.0, 0.35, dot(fNterm, L));
        float fterm_g = smoothstep(0.0, 0.35, dot(fNterm, Mn));
        float flit_y = fterm_y * sun_occ;
        float flit_g = fterm_g * moon_occ;
        float fw_y = clamp(u_rt_sun_elev, 0.0, 1.0);
        float fw_g = clamp(dot(u_rt_moon_color, vec3(1.0)), 0.0, 1.0) * clamp(u_rt_green_amp, 0.0, 2.0);
        // PBR POLISH: the DIRECT share of this fragment's lighting. Hoisted up from the _ao site
        // below (same expression, same value) so the new INDIRECT relief term can weight itself by
        // the complementary ambient share (1 - fdirw) — full effect exactly where the suns are not.
        float fdirw = clamp(flit_y * fw_y + flit_g * fw_g, 0.0, 1.0);
        // PBR POLISH — HEIGHT-FIELD SELF-SHADOW, one march per analytic sun (owner defect 3).
        // The light directions go into the SAME tangent-UV frame the POM marches in, so the
        // shadow the relief casts lies along the same axis the parallax already shifts.
        float fms_y = 1.0;
        float fms_g = 1.0;
        if (fh_ms_uv > 0.0) {
          fms_y = pbr_micro_shadow(uv, fh0, vec3(dot(L, fTuv), dot(L, fBuv), dot(L, N)), fh_ms_uv);
          fms_g =
              pbr_micro_shadow(uv, fh0, vec3(dot(Mn, fTuv), dot(Mn, fBuv), dot(Mn, N)), fh_ms_uv);
        }
        vec3 fsun_ch = u_rt_sun_color / max(dot(u_rt_sun_color, vec3(0.299, 0.587, 0.114)), 1e-3);
        vec3 fmoon_ch = u_rt_moon_color / max(dot(u_rt_moon_color, vec3(0.299, 0.587, 0.114)), 1e-3);
        const vec3 FUS_COOL = vec3(0.896, 1.001, 1.265);
        vec3 flit_mul_y = u_rt_lit_boost * mix(vec3(1.0), fsun_ch, clamp(u_rt_tint_lit, 0.0, 1.0));
        vec3 flit_mul_g = u_rt_lit_boost * mix(vec3(1.0), fmoon_ch, clamp(u_rt_tint_lit, 0.0, 1.0));
        vec3 fshd_mul = u_rt_shadow_mul * mix(vec3(1.0), FUS_COOL, clamp(u_rt_tint_shadow, 0.0, 1.0));
        vec3 fmod = mix(vec3(1.0), mix(fshd_mul, flit_mul_y, flit_y), fw_y) *
                    mix(vec3(1.0), mix(fshd_mul, flit_mul_g, flit_g), fw_g);
        // FUSED-CONTRAST REBALANCE (owner preset report 2026-07-23: Fusion modes read
        // "très contrasté"). The baked colour already carries the TOD contrast; fmod
        // multiplies the realtime lit/shadow spread on top AND the GGX sun specular then
        // adds sparkle on the lit side — a double contrast apply vs the accepted pbr-OFF
        // baked-modulation look (which applies fmod exactly once with no added spec).
        // Compress fmod toward 1 (gamma 0.70) in the FUSED branch only, so the fused
        // overall contrast matches the accepted look and the specular ADDS sparkle
        // instead of stacking another lit/shadow multiply. Bisect 2048 = compress off
        // (device A/B measurement of exactly this rebalance).
        if ((u_pbr_bisect & 2048) == 0) fmod = pow(max(fmod, vec3(0.0)), vec3(0.70));
        if ((u_pbr_bisect & 512) != 0) fmod = vec3(1.0);  // bisect: baked-modulation off
        // Bounded perturbed/smooth N.L ratio (=1 for a flat map => map-free pixels match
        // the accepted baked-modulation look exactly).
        // MEAN-PRESERVING detail. dot(N,L) + g.(T.L, B.L) is the UN-normalised (bump) response of
        // the perturbed surface — identical to dot(Nm,L)/nmt.z, i.e. the same relief WITHOUT the
        // 1/sqrt(1+|g|^2) renormalisation. That renormalisation is what made a normal-mapped
        // surface systematically DARKER than its unmapped neighbour (Jensen: the average of the
        // normalised cosine is below the cosine of the average), which is the second half of the
        // plates — the material BORDER step, visible wherever a mapped ground texture meets an
        // unmapped one (vil1-jng-leafyground vs -hitweak, vil-beach-01 vs -01path: only 8 of 716
        // village1 texture bindings carry maps at all). Because fg is zero-mean, the mean of this
        // term is EXACTLY the smooth-normal response, for any light direction and any frame:
        // relief with no brightness step. Offline (shader-exact) on the grass at relief 1.0:
        // material-border delta -19.5% -> +1.4%, and the detail amplitude RISES 21.5% -> 32.0%.
        // fg == 0 on map-free pixels => fdt == 1 exactly => pbr-OFF look preserved bit for bit.
        float fndl_y = ((u_pbr_bisect & 16384) != 0)
                           ? dot(Nm, L)
                           : (dot(N, L) + fg.x * dot(fTn, L) + fg.y * dot(fBn, L));
        float fndl_g = ((u_pbr_bisect & 16384) != 0)
                           ? dot(Nm, Mn)
                           : (dot(N, Mn) + fg.x * dot(fTn, Mn) + fg.y * dot(fBn, Mn));
        // PBR POLISH — OWNER PLAYTEST #17 REBALANCE: "TRÈS CONTRASTÉ À LA LUMIÈRE (mais quand même
        // plat), TRÈS PLAT À L'OMBRE." Both halves of that sentence are one imbalance. The DIRECT
        // N.L detail ratio was allowed a [0.45, 1.9] swing — a factor of 4.2 between the darkest
        // and brightest texel of the SAME material under the SAME sun — while every actual DEPTH
        // cue was ~0 (cavity did not exist, the ambient ratio measured 0.960..0.996, the
        // self-shadow reached >5% on only 0-17% of texels). High-contrast N.L noise is not depth:
        // it is the same flat surface lit harder. So the direct term gives budget back — a [0.60,
        // 1.55] swing with a larger softening constant — and the budget goes into the cues that
        // actually read as geometry (the cavity below, the now material-scaled self-shadow, and
        // the band-limited real displacement in the tess stage). fg == 0 on map-free pixels still
        // makes this EXACTLY 1.0, so the accepted pbr-OFF look is untouched either way.
        // Bisect 8388608 = the legacy wide clamp back, for the live A/B.
        float fdt_lo = ((u_pbr_bisect & 8388608) != 0) ? 0.45 : 0.60;
        float fdt_hi = ((u_pbr_bisect & 8388608) != 0) ? 1.9 : 1.55;
        float fdt_soft = ((u_pbr_bisect & 8388608) != 0) ? 0.30 : 0.38;
        float fdt_y =
            clamp((max(fndl_y, 0.0) + fdt_soft) / (max(dot(N, L), 0.0) + fdt_soft), fdt_lo, fdt_hi);
        float fdt_g = clamp((max(fndl_g, 0.0) + fdt_soft) / (max(dot(N, Mn), 0.0) + fdt_soft),
                            fdt_lo, fdt_hi);
        // ===================================================================================
        // PBR POLISH — OWNER PLAYTEST #16 DEFECT 2: "completement PLAT dans l'ombre / la ou le
        // soleil ne tape pas". Traced to the exact line: in cast shadow sun_occ = moon_occ = 0, so
        // BOTH mix() weights below collapse to zero and fdetail becomes EXACTLY 1.0 — the normal
        // map stops contributing at all — while the only other normal-dependent term (famb_spec)
        // is driven to zero by matte_gate on every rough dielectric. A shadowed fragment was
        // literally baked x constant x _ao: no normal dependence anywhere in the expression, hence
        // no depth. Relief that only exists in direct sun is not relief.
        // The industry answer is the one the owner named: the INDIRECT term must see the perturbed
        // surface too — irradiance E(n) evaluated with the normal-mapped normal (SH / IBL /
        // hemisphere, whichever ambient model is live) instead of a direction-free constant, with
        // _ao as the contact term (fao_mul below already weights _ao onto exactly this share).
        // Expressed as the same bounded RATIO fdt_y/fdt_g use — E(Nm) / E(N) — so it multiplies the
        // baked composite instead of replacing it (the owner's standing rule: the baked influence
        // always remains) and a map-free fragment gets exactly 1.0, i.e. the accepted
        // Lighting-only look survives bit for bit. E varies slowly and smoothly with direction, so
        // the ratio stays near 1 and carries no brightness step against an unmapped neighbour.
        // Weighted by the AMBIENT SHARE (1 - fdirw): full strength in shadow and at night, fading
        // out where a sun already carries the relief, so full-sun pixels are untouched.
        // Bisect bit 262144 = ambient relief off (the device A/B for this term).
        float fdt_amb = 1.0;
        if ((u_pbr_bisect & 262144) == 0 && dot(fg, fg) > 0.0) {
          const vec3 FUS_LUMA = vec3(0.299, 0.587, 0.114);
          float famb_ls = dot(rt_amb_eval(N), FUS_LUMA);
          float famb_lb = dot(rt_amb_eval(Nm), FUS_LUMA);
          fdt_amb = clamp((max(famb_lb, 0.0) + 0.02) / (max(famb_ls, 0.0) + 0.02), 0.45, 1.9);
        }
        // ===================================================================================
        // PBR POLISH — OWNER PLAYTEST #17, THE "FLAT IN SHADOW" FIX. The ratio above is the term
        // that was SUPPOSED to do this and provably cannot (see pbr_cavity()'s header: our ambient
        // is near direction-invariant, so the ratio measures 0.960..0.996 across every shipped
        // material). This is the direction-INDEPENDENT replacement: a cavity / micro-AO read
        // straight out of the height field, which has exactly the same strength in a cast shadow,
        // in the dark, and at noon.
        // WEIGHTING: full strength on the AMBIENT share (1 - fdirw) — that share IS the whole of a
        // shadowed fragment, which is where the owner sees the flatness — and PBR_CAV_DIR of it in
        // direct sun, because a crevice occludes bounce light there too but the sun's own N.L and
        // self-shadow already carry the relief. So the sunlit look barely moves while the shaded
        // look gains the depth it never had.
        // The _ao MAP, when a material ships one, is the same physical quantity at a coarser scale
        // and already rides this same ambient share through fao_mul below; the cavity is the
        // per-texel detail term that every shipped material can produce from its height map (none
        // of the 7 bundled materials ships an _ao map, which is precisely why an _ao-only ambient
        // occlusion left them flat).
        // Bisect bit 2097152 = cavity off (the live A/B for exactly this fix).
        // ===================================================================================
        float fcav = 1.0;
        if ((u_pbr_mode & 16) != 0 && (u_pbr_bisect & 2097152) == 0) {
          fcav = pbr_cavity(uv);
        }
        const float PBR_CAV_DIR = 0.35;  // how much of the cavity survives in full direct sun
        float fcav_mul = mix(1.0, fcav, mix(PBR_CAV_DIR, 1.0, 1.0 - fdirw));
        // fms_* (height-field self-shadow) rides on each sun's share: a crevice the relief itself
        // occludes cannot receive that sun. It is deliberately NOT applied to the ambient share —
        // skylight reaches into a crevice from every direction, and the cavity above is that term.
        float fdetail = mix(1.0, fdt_y * fms_y, fw_y * sun_occ) *
                        mix(1.0, fdt_g * fms_g, clamp(fw_g, 0.0, 1.0) * moon_occ) *
                        mix(1.0, fdt_amb, 1.0 - fdirw) * fcav_mul;
        if ((u_pbr_bisect & 256) != 0) fdetail = 1.0;  // bisect: detail-relight ratio off
        // _ao = material micro-occlusion: full strength on the ambient/shadowed share,
        // relaxed where the direct sun dominates (AO never occludes the suns).
        float fao_mul = mix(ao, 1.0, 0.55 * fdirw);
        vec3 fbase_disp = max(fragment_color.rgb * T0p.rgb, vec3(0.0)) * fmod * fdetail * fao_mul;
        vec3 fbase_lin = pow(fbase_disp, vec3(2.2));
        // REOPEN ENERGY CONSERVATION + SPECULAR OCCLUSION: kd = (1-F)(1-metal) on the baked
        // diffuse so the specular never ADDS free energy on top of the full baked; and the
        // BAKED-DETAIL luminance gates the specular — a crevice the baked lighting says is
        // dark cannot host a bright highlight (shiny pits read as plastic). _ao joins in.
        // fragment_color is the TOD LUT x2 (lit ~0.5-1.0, crevices < ~0.2).
        float fbklum = dot(fragment_color.rgb, vec3(0.299, 0.587, 0.114));
        float fspecocc = ao * smoothstep(0.05, 0.45, fbklum);
        // REOPEN #3 fix: kd is the INDUSTRY constant (1 - F0)(1 - metal) (UE/Frostbite
        // diffuse). The old view-dependent (1 - Fenv) grayed rough surfaces seen edge-on
        // (the ground at grazing) — a film NOT scaled by the specular slider, which is
        // exactly the owner's "sheen survives specular=0" datapoint.
        fbase_lin *= ((u_pbr_bisect & 8) != 0 ? vec3(1.0) : (vec3(1.0) - F0 * fspecocc)) *
                     (1.0 - metal);
        // BOTH analytic suns, Cook-Torrance with the HEIGHT-CORRELATED SMITH VISIBILITY
        // term (REOPEN: the old separable Schlick G + naive F was exactly the grazing-
        // sheen bug; Vis contains the 1/(4 NdV NdL) denominator). Cast shadows kill each
        // sun's specular via its own occ; the yellow sun also night-fades (fw_y).
        vec3 fspec_direct = vec3(0.0);
        for (int i = 0; i < 2; i++) {
          if ((u_pbr_bisect & (i == 0 ? 1 : 2)) != 0) {
            continue;  // bisect: this sun's GGX specular zeroed
          }
          vec3 Li = (i == 0) ? L : Mn;
          vec3 lc = (i == 0) ? u_rt_sun_color * fw_y : u_rt_moon_color;
          // PBR POLISH: the height-field self-shadow gates the highlight too — a texel the relief
          // occludes cannot host a specular lobe from that sun (a lit highlight sitting inside a
          // crevice is the classic tell that "depth" is only a shaded bump).
          float vis_i = (i == 0) ? (sun_occ * fms_y) : (moon_occ * fms_g);
          if (dot(lc, vec3(1.0)) <= 1e-5 || vis_i <= 1e-4) {
            continue;
          }
          vec3 Hh = normalize(Li + Vv);
          float NdL = max(dot(Nm, Li), 0.0);
          if (NdL <= 0.0) {
            continue;
          }
          float NdH = max(dot(Nm, Hh), 0.0);
          float VdH = max(dot(Vv, Hh), 0.0);
          float dd = NdH * NdH * (fa2 - 1.0) + 1.0;
          float D = fa2 / (3.14159265 * dd * dd);
          float gv = NdL * sqrt(NdV * NdV * (1.0 - fa2) + fa2);
          float gl = NdV * sqrt(NdL * NdL * (1.0 - fa2) + fa2);
          float Vis = 0.5 / max(gv + gl, 1e-4);
          vec3 F = F0 + (Fceil - F0) * pow(1.0 - VdH, 5.0);
          fspec_direct += (D * Vis * F) * lc * NdL * vis_i;
        }
        // AMBIENT SPECULAR — PROBES = the coherence source (REOPEN): the prefiltered local
        // probe cube sampled at the ROUGHNESS MIP (8x8 cube => 4-level chain; lod = rough*3
        // lands roughness 1.0 on the blurriest 1x1 mip), analytic SH/IBL env as the
        // no-probe fallback. Either way the sample CONVERGES to the ambient IRRADIANCE as
        // roughness rises — a rough ground reflects a blurry env, never the sharp sun-glow
        // lobe (the old sharp-Rf eval was the other half of the ground sheen).
        // PBR POLISH: same selector as before, now via the shared rt_amb_eval() the new indirect
        // relief term also uses — one definition of "the ambient irradiance in direction n", so
        // the diffuse and the specular can never drift apart. Value here is unchanged.
        vec3 famb_base = clamp(rt_amb_eval(Nm), 0.0, 1.0);
        vec3 Rf = reflect(-Vv, Nm);
        vec3 fenv_sharp;
        if (u_rt_probe_on != 0 && u_rt_probe_reflections != 0) {
          fenv_sharp = textureLod(u_rt_probe_cube, Rf, rough * 3.0).rgb *
                       clamp(u_rt_probe_strength, 0.0, 1.0);
        } else if (u_rt_ambient_on != 0 && u_rt_ambient_model == 1) {
          fenv_sharp = rt_sh_ambient(Rf);
        } else if (u_rt_ambient_on != 0 && u_rt_ambient_model == 2) {
          fenv_sharp = rt_ibl_ambient(Rf);
        } else {
          fenv_sharp = famb_base;
        }
        // REOPEN #6 VIEW-STABILITY: collapse the sharp view-dependent reflection (Rf, the
        // camera-dependent "highlight shifts with the camera" the owner saw on rock/sand) to the
        // view-INDEPENDENT irradiance (famb_base, from the perturbed Nm) by rough ~0.50 — well
        // before the matte_gate finishes at 0.60 — so no camera-dependent env sheen survives on
        // any rough surface, even inside the 0.30-0.60 transition band.
        vec3 famb_env = mix(fenv_sharp, famb_base, smoothstep(0.12, 0.50, rough));
        // REOPEN #3 fix — THE bisect-identified culprit (mask 4: zeroing this term halved
        // the wall luma; the plastic film lived here). The raw Fresnel multiply (famb_env *
        // Fenv, grazing ceiling max(1-rough, F0)) is replaced by the industry SPLIT-SUM env
        // BRDF (Karis mobile approximation): famb_spec = env * (F0*A + B), A/B folding the
        // GGX lobe energy over (roughness, NdV). Rough ground at grazing now reflects ~5%
        // of the ambient instead of 30-45% — bounded by construction, no mirror-edge film.
        vec4 kr = rough * vec4(-1.0, -0.0275, -0.572, 0.022) + vec4(1.0, 0.0425, 1.04, -0.04);
        float ka004 = min(kr.x * kr.x, exp2(-9.28 * NdV)) * kr.x + kr.y;
        vec2 kAB = vec2(-1.04, 1.04) * ka004 + vec2(kr.z, kr.w);
        vec3 famb_spec = famb_env * (F0 * kAB.x + kAB.y);
        if ((u_pbr_bisect & 4) != 0) famb_spec = vec3(0.0);  // bisect: ambient/IBL specular off
        // EMISSIVE (bit 64): unlit, added on top — glows in full shadow / at night.
        vec3 emissive = ((u_pbr_mode & 64) != 0 && (u_pbr_bisect & 32) == 0)
                            ? pow(texture(tex_PBR_E, uv).rgb, vec3(2.2)) *
                                  max(u_pbr_emissive_str, 0.0)
                            : vec3(0.0);
        // REOPEN #6: matte_gate drives the WHOLE specular (direct GGX + env reflection) to ~0 on
        // rough dielectrics (independent of the slider — a rough surface is matte even at spec=1),
        // then the low-default slider trims what remains on genuinely smooth/metal texels.
        vec3 fspec_sum = (fspec_direct + famb_spec) * fspecocc * matte_gate * max(u_pbr_spec_intensity, 0.0);
        vec3 flit = fbase_lin + fspec_sum + emissive;
        // Same C1 soft-shoulder tone map + far crossfade to baked as the rt composite —
        // the added specular can never clip the baked base to white.
        if ((u_pbr_bisect & 1024) == 0) {
          const float RT_KNEE = 0.8;
          vec3 fe = exp(-max(flit - vec3(RT_KNEE), vec3(0.0)) / (1.0 - RT_KNEE));
          flit = mix(flit, vec3(1.0) - (1.0 - RT_KNEE) * fe, step(vec3(RT_KNEE), flit));
        } else {
          flit = min(flit, vec3(1.0));  // bisect: shoulder off, hard clamp
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
          color.rgb = pow(max(fspec_sum, vec3(0.0)), vec3(1.0 / 2.2));
        } else if (u_pbr_debug == 6) {
          color.rgb = vec3(ao);
        } else if (u_pbr_debug == 18) {
          color.rgb = pow(max(emissive, vec3(0.0)), vec3(1.0 / 2.2));
        } else if (u_pbr_debug == 20) {
          // REOPEN#9 tangent-fallback coverage viz: RED = fragment fell back to a normal-derived
          // continuous basis (v_tangent degenerate/unbound), GREEN = per-vertex MikkTSpace tangent.
          // The screen-space-derivative FACET source is gone in BOTH branches; this measures how much
          // of the visible ground actually carries a valid uploaded per-vertex tangent on THIS device
          // (offline grass_bake can't see a GL upload/bind gap — this can). Screenshot + red-fraction.
          color.rgb = vec3(f_tan_fb, 1.0 - f_tan_fb, 0.0);
        } else if (u_pbr_debug == 21) {
          // PBR POLISH viz: HEIGHT-FIELD SELF-SHADOW (owner defect 3). White = fully lit relief,
          // dark = a texel the surface's own height field occludes from the yellow sun. A flat
          // white screen here means the relief casts nothing = "glorified bump map".
          color.rgb = vec3(fms_y);
        } else if (u_pbr_debug == 22) {
          // PBR POLISH viz: INDIRECT (ambient) RELIEF ratio (owner defect 2), remapped around
          // 0.5 = 1.0. A flat grey screen in shadow means the shadowed surface is FLAT.
          color.rgb = vec3(clamp(fdt_amb * 0.5, 0.0, 1.0));
        } else if (u_pbr_debug == 23) {
          // PBR POLISH #17 viz: the HEIGHT-FIELD CAVITY / micro-AO (the flat-in-shadow fix),
          // remapped so 0.5 = 1.0 (no change), darker = crevice, brighter = ridge. Unlike viz 22
          // this one must show STRUCTURE even on a fragment in full cast shadow — a flat grey
          // screen there is the defect, and this is the term that fixes it.
          color.rgb = vec3(clamp(fcav * 0.5, 0.0, 1.0));
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
      // REOPEN#7 FOUNDATION FIX (same as the fused path): prefer the CONTINUOUS smooth per-vertex
      // normal as the surface base — the derivative geometric normal Ngeo is itself discontinuous at
      // edges and helped crack the standalone PBR too. Ngeo is kept only for view-facing + fallback.
      vec3 Nsurf = (dot(v_normal, v_normal) > 0.01) ? normalize(v_normal) : Ngeo;
      if (dot(Nsurf, V) < 0.0) Nsurf = -Nsurf;
      // Continuous TBN from the per-vertex tangent (interpolated); derivative frame only as fallback.
      vec3 Tn, Bn;
      if (dot(v_tangent.xyz, v_tangent.xyz) > 0.04) {
        Tn = normalize(v_tangent.xyz - Nsurf * dot(Nsurf, v_tangent.xyz));
        Bn = cross(Nsurf, Tn) * (v_tangent.w < 0.0 ? -1.0 : 1.0);
      } else {
        // REOPEN#9: same continuous normal-derived basis as the fused path — NEVER the screen-space
        // derivative frame (per-triangle-constant = the facet source). Standalone rt-OFF+pbr-ON path.
        frisvad_basis(Nsurf, Tn, Bn);
      }
      // ★ OWNER CHECKER VERDICT, BUG A: the SAME uv as the base colour, no multiplier (see the
      // fused branch — this "bidon" fallback is the owner's "PBR seul" preset, so it has to line
      // up with the pattern too).
      vec2 uv = tex_coord.xy;
      // PBR POLISH bug fix — DOUBLE DISPLACEMENT. A draw the tess-eval already moved must not run a
      // 16-32 step POM march on top of it: two displacements stacked. ★ BUG B: the gate is
      // u_pbr_tess_active (per-PROGRAM), not the global u_pbr_displacement setting — otherwise
      // selecting Tessellation flattens every draw the tess program does not cover.
      // Everything else on this fallback path is deliberately untouched.
      if ((u_pbr_mode & 16) != 0 && u_pbr_debug != 8 && u_pbr_height_scale > 0.0 &&
          u_pbr_tess_active == 0) {
        // Parallax occlusion mapping, mobile-tuned: grazing-angle-scaled linear march
        // with early-out + one secant refine. Height convention: 1.0 (white) = surface
        // level, lower = carved in — so a neutral white map yields zero offset and the
        // march depth is (1 - height). textureLod avoids undefined derivatives in the
        // loop; the offsets are small so mip 0 is acceptable at PoC distances.
        vec3 Vt = normalize(vec3(dot(V, Tn), dot(V, Bn), max(dot(V, Nsurf), 0.0)));
        float vz = max(Vt.z, 0.20);  // cap the grazing blow-up (raised REOPEN #6 for surface-lock)
        float n_layers = mix(28.0, 10.0, clamp(Vt.z, 0.0, 1.0));
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
        float depth_uv = pom_depth_uv(lambda_world_m);
        float pom_cap = min(POM_MAX_TAN * depth_uv,
                            POM_MAX_FEATURE_FRAC * lambda_world_m * max(u_pbr_uv_per_m, 0.02));
        // Same round-20 restoration as the fused path, so the A/B pair is identical on both.
        if ((u_pbr_bisect & 33554432) != 0) {
          pom_graze = smoothstep(POM_GRAZE_LO, POM_GRAZE_HI, Vt.z);
          depth_uv = u_pbr_height_scale;
          pom_cap = min(POM_MAX_TAN * u_pbr_height_scale,
                        0.03 * max(u_pbr_uv_per_m, 0.02));
        }
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
          float map_d = 1.0 - hnorm(textureLod(tex_PBR_H, uv, 0.0).r);
          float prev_map_d = map_d;
          for (int i = 0; i < 32; i++) {
            if (cur_d >= map_d || float(i) >= n_layers) {
              break;
            }
            uv -= duv_step;
            prev_map_d = map_d;
            map_d = 1.0 - hnorm(textureLod(tex_PBR_H, uv, 0.0).r);
            cur_d += layer_d;
          }
          // secant refine between the last two samples for a smooth intersection
          float after = map_d - cur_d;
          float before = prev_map_d - (cur_d - layer_d);
          float w = clamp(before / max(before - after, 1e-5), 0.0, 1.0);
          uv += duv_step * (1.0 - w);
        }
      }
      vec3 N = Nsurf;
      if ((u_pbr_mode & 1) != 0 && u_pbr_debug != 7) {
        vec3 nm = texture(tex_PBR_N, uv).xyz * 2.0 - 1.0;
        // Same DC-removed surface-gradient decode as the fused path above (the constant-tilt
        // plate defect is a property of the MAPS, so the rt-OFF "bidon" fallback carries it too;
        // the owner's PBR-only preset showed the identical plates). Same A/B bits: 8192 = raw
        // map, 32768 = per-chunk UV frame instead of the seam-stable one. The path is otherwise
        // untouched — it stays the standalone fallback the owner accepted.
        vec3 sTn = Tn, sBn = Bn;
        if ((u_pbr_bisect & 32768) == 0) {
          stable_frame(Nsurf, sTn, sBn);
        }
        vec2 sg = clamp(nm.xy / max(nm.z, 0.05), vec2(-4.0), vec2(4.0));
        if ((u_pbr_bisect & 8192) == 0) {
          sg -= u_pbr_normal_dc;
        }
        sg = clamp(sg * u_pbr_normal_strength, vec2(-8.0), vec2(8.0));
        nm = normalize(vec3(sg, 1.0));
        N = normalize(mat3(sTn, sBn, Nsurf) * nm);
        // GLASS-PANE fix (owner preset report 2026-07-23, same defect on the PBR ONLY
        // preset = this rt-OFF path): slide back to the face horizon instead of the old
        // hard snap to the base normal — the tangential map grain survives at grazing angles, so
        // the specular follows the material texture, not the flat polygon.
        float snd = dot(N, Nsurf);
        if (snd < 0.04) N = normalize(N + Nsurf * (0.04 - snd));
      }
      // Albedo re-sampled at the (possibly POM-offset, tiled) UV; the initial T0
      // sample keeps supplying alpha for the legacy discard product below.
      vec4 T0p = texture(tex_T0, uv);
      vec3 albedo = pow(T0p.rgb, vec3(2.2));
      // REOPEN #6: missing _roughness => ROUGH (matte), never smooth — a smooth default is the
      // exact cause of the plastic sheen the owner reported on the PBR-ONLY preset.
      float rough = (u_pbr_mode & 2) != 0 ? texture(tex_PBR_R, uv).r : 0.9;
      float metal = (u_pbr_mode & 4) != 0 ? texture(tex_PBR_M, uv).r : 0.0;
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
      vec3 F0 = mix(vec3(0.04), albedo, metal);
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
        lit += prefiltered * Fenv * ao * clamp(u_rt_probe_strength, 0.0, 1.0) * matte_gate;
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
