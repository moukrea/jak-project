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
uniform int u_rt_light_on;
uniform int u_rt_use_baked;
uniform vec3 u_rt_sun_dir;
uniform vec3 u_rt_sun_color;
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
      vec3 gN = cross(dFdx(v_fringe_rel), dFdy(v_fringe_rel));
      float gNl = length(gN);
      vec3 N = gNl > 1e-6 ? gN * (1.0 / gNl) : vec3(0.0, 1.0, 0.0);
      vec3 Vv = -normalize(v_fringe_rel);
      if (dot(N, Vv) < 0.0) N = -N;
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
      float floorlvl = clamp(u_rt_shadow_residual, 0.0, 1.0);
      // ROUND-7 NIGHT FADE: * u_rt_sun_elev so the direct sun (and any mood tint) goes to 0 at
      // night, leaving only the ~0.2 floor. Identical in all four world shaders.
      float sun_scalar = ndl * shadow * u_rt_sun_elev;  // N.L * cast-shadow occlusion * night-fade
      vec3 albedo = pow(T0.rgb, vec3(2.2));
      vec3 baked = u_rt_use_baked != 0 ? pow(max(fragment_color.rgb, vec3(0.0)), vec3(2.2)) : vec3(1.0);
      vec3 lit = albedo * baked * (vec3(floorlvl) + (1.0 - floorlvl) * u_rt_sun_color * sun_scalar);
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
      else if (u_pbr_debug == 12) { color.rgb = vec3(floorlvl + (1.0 - floorlvl) * sun_scalar); }
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
