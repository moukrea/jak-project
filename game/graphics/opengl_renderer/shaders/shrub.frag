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
uniform int u_pbr_shadow_on;
uniform mat4 u_pbr_shadow_mvp;
uniform vec3 u_pbr_shadow_cam_delta;
uniform highp sampler2D tex_PBR_SHADOW;
uniform float u_pbr_shadow_bias;
uniform int u_pbr_debug;
#endif

void main() {
  if (gfx_hack_no_tex == 0) {
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
          float sdist = length(v_fringe_rel);
          float soft = 0.75 + 6.5 * smoothstep(0.0, rng, sdist);
          float rr = texel * soft;
          float hang = fract(sin(dot(gl_FragCoord.xy, vec2(12.9898, 78.233))) * 43758.5453) * 6.2831853;
          vec2 hc = vec2(cos(hang), sin(hang));
          mat2 hrot = mat2(hc.x, -hc.y, hc.y, hc.x);
          float sm = 0.0;
          for (int iy = -1; iy <= 1; iy++) {
            for (int ix = -1; ix <= 1; ix++) {
              vec2 o = hrot * (vec2(float(ix), float(iy)) * rr);
              sm += ref <= texture(tex_PBR_SHADOW, suv.xy + o).r ? 1.0 : 0.0;
            }
          }
          sm *= (1.0 / 9.0);
          float edge_fade = 1.0 - smoothstep(rng * 0.72, rng * 0.96, length(v_fringe_rel));
          shadow = mix(1.0, sm, edge_fade);
        }
      }
      vec3 albedo = pow(T0.rgb, vec3(2.2));
      vec3 baked = u_rt_use_baked != 0 ? pow(max(fragment_color.rgb, vec3(0.0)), vec3(2.2)) : vec3(1.0);
      vec3 lit = albedo * baked * u_rt_sun_color * (ndl * shadow);
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
      else if (u_pbr_debug == 12) { color.rgb = vec3(shadow); }
    }
#endif
  } else {
    color = fragment_color;
  }

  if (color.a < alpha_min || color.a > alpha_max) {
    discard;
  }

  color.xyz = mix(color.xyz, fog_color.rgb, clamp(fogginess * fog_color.a, 0.0, 1.0));
}
