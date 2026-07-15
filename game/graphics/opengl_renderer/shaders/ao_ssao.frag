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
  float d = texture(u_depth, tex_coord).r;
  if (d <= 0.000001) {  // sky / far -> fully lit
    color = vec4(1.0);
    return;
  }

  vec2 px = 1.0 / u_depth_size;
  float dl = texture(u_depth, tex_coord - vec2(px.x, 0.0)).r;
  float dr = texture(u_depth, tex_coord + vec2(px.x, 0.0)).r;
  float du = texture(u_depth, tex_coord + vec2(0.0, px.y)).r;
  float dd = texture(u_depth, tex_coord - vec2(0.0, px.y)).r;

  vec3 P = world_from_depth(tex_coord, d);
  float dcam = distance(P, u_cam_pos.xyz);
  if (u_debug == 2) {  // depth-band debug: 10m bands from the camera; sky already white
    color = vec4(vec3(fract(dcam / 40960.0)), 1.0);
    return;
  }
  vec3 dh = (abs(dr - d) < abs(dl - d))
                ? world_from_depth(tex_coord + vec2(px.x, 0.0), dr) - P
                : P - world_from_depth(tex_coord - vec2(px.x, 0.0), dl);
  vec3 dv = (abs(du - d) < abs(dd - d))
                ? world_from_depth(tex_coord + vec2(0.0, px.y), du) - P
                : P - world_from_depth(tex_coord - vec2(0.0, px.y), dd);
  vec3 N = normalize(cross(dh, dv));
  vec3 V = normalize(u_cam_pos.xyz - P);
  if (dot(N, V) < 0.0) {
    N = -N;
  }

  // tangent basis around N
  vec3 up = abs(N.z) < 0.999 ? vec3(0.0, 0.0, 1.0) : vec3(1.0, 0.0, 0.0);
  vec3 T = normalize(cross(up, N));
  vec3 B = cross(N, T);

  // per-pixel rotation noise (interleaved gradient noise, no texture)
  float ign = fract(52.9829189 *
                    fract(dot(gl_FragCoord.xy, vec2(0.06711056, 0.00583715))));

  float occ = 0.0;
  float bias = 0.02 * u_radius + 0.005 * dcam;  // distance-proportional: 24-bit GS depth quantizes coarsely at range
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
    if (dist_Ps < dist_sp - bias && dPPs < u_radius * 1.5 && above > 0.05 * u_radius) {
      // bounded occluders only: full weight inside the radius, fading to 0 by 1.5r
      float w = 1.0 - smoothstep(u_radius, u_radius * 1.5, dPPs);
      occ += w;
    }
  }

  float ao = clamp(1.0 - u_intensity * occ / float(n), 0.0, 1.0);
  // defect #7 (owner: "AO = local detail, not global shading"): near-field fade — AO is
  // a contact/crease effect. Fade the term to 1.0 between 30 m and 60 m from the camera
  // so distant scenery (incl. the sea and the seafloor seen through its transparency) is
  // untouched; platformer contact shadows live well inside 30 m. 4096 units = 1 m.
  ao = mix(ao, 1.0, smoothstep(122880.0, 245760.0, dcam));
  color = vec4(vec3(ao), 1.0);
}
