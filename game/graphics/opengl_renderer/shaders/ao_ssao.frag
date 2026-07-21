#version 410 core

// Grecharged-ambient-occlusion: hemisphere-kernel SSAO in world space. Reconstructs
// world position + normal from the reverse-Z depth texture (GS-style transform, per
// collision.vert), samples a procedural golden-angle hemisphere kernel around the
// surface normal, and accumulates range-checked occlusion. No array uniforms and no
// noise texture (Adreno 618 array-read bug class): the kernel is fully procedural.
precision highp float;

in vec2 tex_coord;
out vec4 color;

uniform highp sampler2D u_depth;

uniform mat4 u_camera;
uniform mat4 u_inv_camera;
uniform vec4 u_hvdf_offset;
uniform float u_fog;
uniform vec4 u_cam_pos;
uniform vec2 u_depth_size;
uniform vec2 u_ao_size;
uniform float u_radius;
uniform float u_intensity;
uniform int u_samples;
uniform int u_dirs;   // unused here (kept for a uniform interface across passes)
uniform int u_steps;  // unused here
uniform int u_debug;

// ---- shared reconstruction (GS-style transform, reverse-Z) ----
vec3 world_from_depth(vec2 uv, float d) {
  vec3 ndc = vec3(uv * 2.0 - 1.0, d * 2.0 - 1.0);
  float sx = ndc.x * 256.0 + 2048.0 - u_hvdf_offset.x;
  float sy = ndc.y * -128.0 + 2048.0 - u_hvdf_offset.y;
  float sz = (ndc.z + 1.0) * 8388608.0 - u_hvdf_offset.z;
  vec4 ph = u_inv_camera * vec4(sx, sy, sz, u_fog);
  return ph.xyz / ph.w;
}

// forward: world -> (uv, window depth). .w<=0.0 means behind camera / invalid.
vec4 project_world(vec3 p) {
  vec4 t = -(u_camera[3] + u_camera[0] * p.x + u_camera[1] * p.y + u_camera[2] * p.z);
  if (t.w <= 0.0) {
    return vec4(-1.0);
  }
  float Q = u_fog / t.w;
  vec3 s = t.xyz * Q + u_hvdf_offset.xyz;
  float nx = (s.x - 2048.0) / 256.0;
  float ny = (s.y - 2048.0) / -128.0;
  float nz = s.z / 8388608.0 - 1.0;
  return vec4(vec2(nx, ny) * 0.5 + 0.5, nz * 0.5 + 0.5, 1.0);
}

void main() {
  // Round F item 1 (owner 2026-07-16 16:50) ROOT CAUSE of the constant horizontal
  // bands at AO quality Low/Medium: at reduced AO res the fragment's tex_coord lands
  // EXACTLY on full-res depth-texel EDGES (quarter-res center -> full-res coord 4i+2.0,
  // half-res -> 2i+1.0). NEAREST resolves the tie per-pixel by fp interpolation wobble,
  // so the depth belongs to one of two adjacent rows while the reconstruction uses the
  // edge's screen position -> P sits off the true surface by up to a full row's depth
  // delta (decimeters at grazing range) -> the whole hemisphere/horizon reads as
  // occluded in dashed iso-depth rows. Fix: snap the center + neighbor reads AND the
  // P reconstruction to the full-res texel CENTER. At High (1:1) snapping is an exact
  // identity (floor(j+0.5)+0.5 == j+0.5), so the frozen SSAO-High look is untouched
  // (x86 proof: Low row/col residual ratio 2.05 -> 1.02, High's isotropic 1.00).
  vec2 snapped = (floor(tex_coord * u_depth_size) + 0.5) / u_depth_size;
  float d = texture(u_depth, snapped).r;
  if (d <= 0.000001) {  // sky / far -> fully lit
    color = vec4(1.0);
    return;
  }

  vec2 px = 1.0 / u_depth_size;
  float dl = texture(u_depth, snapped - vec2(px.x, 0.0)).r;
  float dr = texture(u_depth, snapped + vec2(px.x, 0.0)).r;
  float du = texture(u_depth, snapped + vec2(0.0, px.y)).r;
  float dd = texture(u_depth, snapped - vec2(0.0, px.y)).r;

  vec3 P = world_from_depth(snapped, d);
  float dcam = distance(P, u_cam_pos.xyz);
  if (u_debug == 2) {  // depth-band debug: 10m bands from the camera; sky already white
    color = vec4(vec3(fract(dcam / 40960.0)), 1.0);
    return;
  }
  vec3 dh = (abs(dr - d) < abs(dl - d))
                ? world_from_depth(snapped + vec2(px.x, 0.0), dr) - P
                : P - world_from_depth(snapped - vec2(px.x, 0.0), dl);
  vec3 dv = (abs(du - d) < abs(dd - d))
                ? world_from_depth(snapped + vec2(0.0, px.y), du) - P
                : P - world_from_depth(snapped - vec2(0.0, px.y), dd);
  vec3 N = normalize(cross(dh, dv));
  vec3 V = normalize(u_cam_pos.xyz - P);
  if (dot(N, V) < 0.0) {
    N = -N;
  }

  // tangent basis around N
  vec3 up = abs(N.z) < 0.999 ? vec3(0.0, 0.0, 1.0) : vec3(1.0, 0.0, 0.0);
  vec3 T = normalize(cross(up, N));
  vec3 B = cross(N, T);

  // REOPEN 2026-07-21 (owner: AO still flickers on movement): the rotation noise was pinned
  // to gl_FragCoord — as the camera moves a world point slides across pixels and re-rolls its
  // kernel rotation every frame with no temporal filter = the crawl on all three modes.
  // Anchor the noise to the WORLD cell instead (P is the true reconstructed world position):
  // a surface point keeps the SAME rotation frame after frame => temporally stable by
  // construction. Cells grow with distance so depth-reconstruction error stays << cell; the
  // 45 m near-field fade means far cells never re-roll visibly. (4096 units = 1 m.)
  vec3 q = floor(P / max(1024.0, dcam * 0.02));
  vec3 p3 = fract(q * 0.1031);
  p3 += dot(p3, p3.yzx + 33.33);
  float ign = fract((p3.x + p3.y) * p3.z);

  float occ = 0.0;
  float bias = 0.02 * u_radius + 0.005 * dcam;  // distance-proportional: 24-bit GS depth quantizes coarsely at range
  // defect #7 (attempt 5): grazing-scaled tangent-plane threshold — at grazing incidence
  // the reconstructed height noise + terrain micro-relief pass the flat 5cm test and
  // wash the open floor; a real crate/wall contact occluder sits far above either bar.
  float grz = 1.0 - abs(dot(N, V));
  float above_thresh = 0.05 * u_radius * (1.0 + 4.5 * grz * grz);
  // Near-field micro-relief rejection (see ao_gtao.frag): occluders closer than ~2.5%
  // of the camera distance are noise/bumps at grazing; capped vs radius so distant
  // contact shadows survive.
  float minr = min(0.025 * dcam, 0.35 * u_radius);
  int n = u_samples;
  for (int i = 0; i < n; i++) {
    float a = ign * 6.28318530718 + float(i) * 2.399963;
    float r = sqrt((float(i) + 0.5) / float(n));
    vec3 dir = T * (cos(a) * r) + B * (sin(a) * r) + N * sqrt(max(0.0, 1.0 - r * r));
    vec3 sp = P + N * (0.02 * u_radius) + dir * (u_radius * mix(0.25, 1.0, r));

    vec4 proj = project_world(sp);
    if (proj.w <= 0.0 || proj.x < 0.0 || proj.x > 1.0 || proj.y < 0.0 || proj.y > 1.0) {
      continue;
    }
    float ds = texture(u_depth, proj.xy).r;
    if (ds <= 0.000001) {
      continue;  // sky sample
    }
    vec3 Ps = world_from_depth(proj.xy, ds);
    float dist_Ps = distance(Ps, u_cam_pos.xyz);
    float dist_sp = distance(sp, u_cam_pos.xyz);
    float dPPs = distance(P, Ps);
    // tangent-plane test: a real occluder must sit ABOVE the surface plane at P. Points
    // of the surface itself (flat ground at grazing view) have dot(Ps-P, N) ~= 0 and the
    // radial-distance compare alone is ill-conditioned there (defect #5's 16% open-area
    // darkening came from range-quantized depth noise passing it).
    float above = dot(Ps - P, N);
    if (dist_Ps < dist_sp - bias && dPPs < u_radius * 1.5 && dPPs > minr &&
        above > above_thresh) {
      // bounded occluders only: full weight inside the radius, fading to 0 by 1.5r
      float w = 1.0 - smoothstep(u_radius, u_radius * 1.5, dPPs);
      occ += w;
    }
  }

  float ao = clamp(1.0 - u_intensity * occ / float(n), 0.0, 1.0);
  // defect #7 (owner: "AO = local detail, not global shading"): near-field fade — AO is
  // a contact/crease effect. Fade the term to 1.0 between 20 m and 45 m from the camera
  // so distant scenery (incl. the sea and the seafloor seen through its transparency) is
  // untouched; platformer contact shadows live well inside 30 m. 4096 units = 1 m.
  ao = mix(ao, 1.0, smoothstep(81920.0, 184320.0, dcam));
  color = vec4(vec3(ao), 1.0);
}
