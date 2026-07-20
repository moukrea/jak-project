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
in vec3 v_normal;  // Grecharged-directional-ambient: smooth authored TIE normal (root-cause fix)
uniform int u_rt_light_on;
uniform vec3 u_rt_sun_dir;
uniform vec3 u_rt_sun_color;
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
      float sun_scalar = ndl * shadow * u_rt_sun_elev;  // N.L * cast-shadow occlusion * night-fade
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
      // AZIMUTHAL DIRECTIONAL CONTRAST — the fix for flat VERTICAL faces (rocks/walls, N.y~0) with the
      // sun OFF. A GAIN-boosted, FLOORED directional wrap toward the ambient key (sun-azimuth horizontal
      // + up-tilt, NOT elevation-faded so it PERSISTS sun-off): faces toward the key brighten as a soft
      // skylight, faces away keep a DIM FLOOR (form, NOT crushed to black => away-faces stay sculpted).
      // The 2.0 gain makes the shipped default contrast (0.9) sculpt HARD on the DEFAULT colored render
      // (0.9 alone was too subtle — the owner's repeated "still flat" complaint); the max() floor stops
      // the high-gain away-faces from clamping to pure black (which would re-flatten them). contrast 0 =>
      // shape 1 => the pure-hemisphere flat A/B reference. Golden rule intact: the direct-sun term below
      // is untouched, and base's weight vanishes as the sun saturates (sunlit byte-identical).
      if (u_rt_ambient_on != 0) {
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
      vec3 lit = albedo * base + albedo * u_rt_sun_color * sun_scalar;
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