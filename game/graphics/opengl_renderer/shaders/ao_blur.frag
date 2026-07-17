#version 410 core

// Grecharged-ambient-occlusion: separable bilateral blur of the AO buffer. 5 taps at
// offsets -2..2 * u_dir, gaussian weights (1,4,6,4,1)/16, each tap additionally weighted
// by a depth-aware term exp(-(dv)^2 / (2 sigma^2)) so the blur does not bleed AO across
// depth discontinuities. Sky taps (depth ~= 0) are skipped. Reconstruction block matches
// the AO estimators. Procedural, no array uniforms.
precision highp float;

in vec2 tex_coord;
out vec4 color;

uniform highp sampler2D u_ao;
uniform highp sampler2D u_depth;

uniform mat4 u_camera;
uniform mat4 u_inv_camera;
uniform vec4 u_hvdf_offset;
uniform float u_fog;
uniform vec4 u_cam_pos;
uniform vec2 u_depth_size;
uniform vec2 u_ao_size;
uniform vec2 u_dir;  // (1/ao_w,0) or (0,1/ao_h)

vec3 world_from_depth(vec2 uv, float dpt) {
  vec3 ndc = vec3(uv * 2.0 - 1.0, dpt * 2.0 - 1.0);
  float sx = ndc.x * 256.0 + 2048.0 - u_hvdf_offset.x;
  float sy = ndc.y * -128.0 + 2048.0 - u_hvdf_offset.y;
  float sz = (ndc.z + 1.0) * 8388608.0 - u_hvdf_offset.z;
  vec4 ph = u_inv_camera * vec4(sx, sy, sz, u_fog);
  return ph.xyz / ph.w;
}

void main() {
  float d0 = texture(u_depth, tex_coord).r;
  if (d0 <= 0.000001) {
    color = vec4(1.0);  // sky center -> lit, no blur needed
    return;
  }
  float cvd = distance(world_from_depth(tex_coord, d0), u_cam_pos.xyz);
  const float sigma = 2048.0;  // ~0.5 m

  // Round F item 1 (owner 2026-07-16 16:50), SECONDARY fix. The banding ROOT CAUSE was
  // the ESTIMATORS' texel-edge depth reads at reduced AO res (see ao_ssao.frag main());
  // this pass had an independent lesser flaw of the same family: taps step in AO-RES
  // texel units (u_dir), and on grazing floors one sub-full-res step spans several
  // meters of view distance — every tap fails the fixed-sigma depth test and the
  // blur/upsample degenerates to a passthrough exactly at the qualities that need
  // smoothing. PLANE-AWARE weights: predict each tap's view distance from the local
  // view-distance gradient along u_dir (central difference) and weight by the deviation
  // from that plane: planar surfaces regain the full gaussian footprint, true depth
  // edges still reject (prediction breaks there, no halo). Gated to sub-full-res AO
  // only: at High (1:1) slope stays 0 and this path is bit-identical to the frozen
  // SSAO-High look.
  float slope = 0.0;
  if (u_ao_size.y < u_depth_size.y - 0.5) {
    float dp = texture(u_depth, tex_coord + u_dir).r;
    float dm = texture(u_depth, tex_coord - u_dir).r;
    if (dp > 0.000001 && dm > 0.000001) {
      float vp = distance(world_from_depth(tex_coord + u_dir, dp), u_cam_pos.xyz);
      float vm = distance(world_from_depth(tex_coord - u_dir, dm), u_cam_pos.xyz);
      slope = 0.5 * (vp - vm);
    }
  }

  // gaussian weights for offsets -2,-1,0,1,2
  float gw0 = 6.0 / 16.0;
  float gw1 = 4.0 / 16.0;
  float gw2 = 1.0 / 16.0;

  float sum = texture(u_ao, tex_coord).r * gw0;
  float wsum = gw0;

  // -2, -1, +1, +2 taps
  for (int i = 0; i < 4; i++) {
    float off = (i == 0) ? -2.0 : (i == 1) ? -1.0 : (i == 2) ? 1.0 : 2.0;
    float gw = (abs(off) < 1.5) ? gw1 : gw2;
    vec2 tuv = tex_coord + u_dir * off;
    float td = texture(u_depth, tuv).r;
    if (td <= 0.000001) {
      continue;  // sky tap
    }
    float tvd = distance(world_from_depth(tuv, td), u_cam_pos.xyz);
    float dv = tvd - (cvd + slope * off);  // deviation from the local tangent plane
    float dw = exp(-(dv * dv) / (2.0 * sigma * sigma));
    float w = gw * dw;
    sum += texture(u_ao, tuv).r * w;
    wsum += w;
  }

  color = vec4(vec3(sum / max(wsum, 1e-5)), 1.0);
}
