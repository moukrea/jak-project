#version 410 core

out vec4 color;

in vec4 fragment_color;
in vec3 tex_coord;
in float fogginess;
in vec3 v_fringe_rel;  // Grecharged-grass-overhang2: camera-relative world pos (meters)
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
uniform int u_pbr_mode;        // 0=legacy; bit1 normal, bit2 rough, bit4 metal, bit8 ao
uniform vec3 u_pbr_sun_dir;    // world-space, surface->sun, normalized
uniform vec3 u_pbr_sun_color;
uniform vec3 u_pbr_ambient;
uniform float u_pbr_exposure;
uniform sampler2D tex_PBR_N;
uniform sampler2D tex_PBR_R;
uniform sampler2D tex_PBR_M;
uniform sampler2D tex_PBR_AO;
#endif


void main() {
  if (gfx_hack_no_tex == 0) {
    //vec4 T0 = texture(tex_T0, tex_coord);
    vec4 T0 = texture(tex_T0, tex_coord.xy);
    color = fragment_color * T0;
#ifdef OG_PBR
    // Grecharged-pbr-materials: Cook-Torrance GGX lit by the mood/TOD sun. The baked
    // per-vertex TOD color (fragment_color.rgb) is deliberately NOT applied — the mood
    // light replaces it (no double-dose); alpha keeps the legacy product for discard.
    if (u_pbr_mode != 0 && gfx_hack_no_tex == 0) {
      vec3 p = v_fringe_rel;
      vec3 dp1 = dFdx(p);
      vec3 dp2 = dFdy(p);
      vec3 V = -normalize(p);
      vec3 Ngeo = normalize(cross(dp1, dp2));
      if (dot(Ngeo, V) < 0.0) Ngeo = -Ngeo;
      vec3 N = Ngeo;
      if ((u_pbr_mode & 1) != 0) {
        // cotangent frame from screen-space derivatives (no vertex tangents in tfrag data)
        vec2 duv1 = dFdx(tex_coord.xy);
        vec2 duv2 = dFdy(tex_coord.xy);
        vec3 dp2perp = cross(dp2, Ngeo);
        vec3 dp1perp = cross(Ngeo, dp1);
        vec3 T = dp2perp * duv1.x + dp1perp * duv2.x;
        vec3 B = dp2perp * duv1.y + dp1perp * duv2.y;
        float invmax = inversesqrt(max(max(dot(T, T), dot(B, B)), 1e-10));
        vec3 nm = texture(tex_PBR_N, tex_coord.xy).xyz * 2.0 - 1.0;
        N = normalize(mat3(T * invmax, B * invmax, Ngeo) * nm);
        if (dot(N, Ngeo) < 0.0) N = Ngeo;
      }
      vec3 albedo = pow(T0.rgb, vec3(2.2));
      float rough = (u_pbr_mode & 2) != 0 ? texture(tex_PBR_R, tex_coord.xy).r : 0.7;
      float metal = (u_pbr_mode & 4) != 0 ? texture(tex_PBR_M, tex_coord.xy).r : 0.0;
      float ao    = (u_pbr_mode & 8) != 0 ? texture(tex_PBR_AO, tex_coord.xy).r : 1.0;
      vec3 L = u_pbr_sun_dir;
      vec3 H = normalize(L + V);
      float NdL = max(dot(N, L), 0.0);
      float NdV = max(dot(N, V), 1e-4);
      float NdH = max(dot(N, H), 0.0);
      float VdH = max(dot(V, H), 0.0);
      float a = max(rough * rough, 0.002);
      float a2 = a * a;
      float dd = NdH * NdH * (a2 - 1.0) + 1.0;
      float D = a2 / (3.14159265 * dd * dd);
      float k = (rough + 1.0) * (rough + 1.0) / 8.0;
      float G = (NdV / (NdV * (1.0 - k) + k)) * (NdL / (NdL * (1.0 - k) + k));
      vec3 F0 = mix(vec3(0.04), albedo, metal);
      vec3 F = F0 + (1.0 - F0) * pow(1.0 - VdH, 5.0);
      vec3 spec = D * G * F / max(4.0 * NdV * NdL, 1e-4);
      vec3 kd = (vec3(1.0) - F) * (1.0 - metal);
      vec3 lit = (kd * albedo / 3.14159265 + spec) * u_pbr_sun_color * NdL
               + u_pbr_ambient * albedo * ao;
      color.rgb = pow(max(lit * u_pbr_exposure, vec3(0.0)), vec3(1.0 / 2.2));
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
