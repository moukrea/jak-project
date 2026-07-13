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


void main() {
  if (gfx_hack_no_tex == 0) {
    //vec4 T0 = texture(tex_T0, tex_coord);
    vec4 T0 = texture(tex_T0, tex_coord.xy);
    color = fragment_color * T0;
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
    color.a *= mix(1.0, dist_f, steep_w);
  }

  if (color.a < alpha_min || color.a > alpha_max) {
    discard;
  }

  color.rgb = mix(color.rgb, fog_color.rgb, clamp(fogginess * fog_color.a, 0.0, 1.0));
}
