#version 410 core

// Grecharged-ambient-occlusion: horizon-based AO. Reconstructs world position + normal
// from the reverse-Z depth texture, marches u_dirs screen-space directions, and for each
// tracks the maximum horizon elevation toward the camera relative to the surface tangent.
// Procedural directions (no array uniforms / no noise texture) for the Adreno bug class.
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
uniform int u_samples;  // unused here
uniform int u_dirs;
uniform int u_steps;

vec3 world_from_depth(vec2 uv, float d) {
  vec3 ndc = vec3(uv * 2.0 - 1.0, d * 2.0 - 1.0);
  float sx = ndc.x * 256.0 + 2048.0 - u_hvdf_offset.x;
  float sy = ndc.y * -128.0 + 2048.0 - u_hvdf_offset.y;
  float sz = (ndc.z + 1.0) * 8388608.0 - u_hvdf_offset.z;
  vec4 ph = u_inv_camera * vec4(sx, sy, sz, u_fog);
  return ph.xyz / ph.w;
}

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
  if (d <= 0.000001) {
    color = vec4(1.0);
    return;
  }

  vec2 px = 1.0 / u_depth_size;
  float dl = texture(u_depth, tex_coord - vec2(px.x, 0.0)).r;
  float dr = texture(u_depth, tex_coord + vec2(px.x, 0.0)).r;
  float du = texture(u_depth, tex_coord + vec2(0.0, px.y)).r;
  float dd = texture(u_depth, tex_coord - vec2(0.0, px.y)).r;

  vec3 P = world_from_depth(tex_coord, d);
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

  // screen-space march radius: project P and P + a world tangent of length u_radius.
  vec3 wt = abs(N.z) < 0.999 ? normalize(cross(N, vec3(0.0, 0.0, 1.0)))
                             : normalize(cross(N, vec3(1.0, 0.0, 0.0)));
  vec4 p0 = project_world(P);
  vec4 p1 = project_world(P + wt * u_radius);
  float screen_r = (p0.w > 0.0 && p1.w > 0.0) ? distance(p0.xy, p1.xy) : 0.05;
  screen_r = clamp(screen_r, 2.0 * max(px.x, px.y), 0.25);

  float ign = fract(52.9829189 *
                    fract(dot(gl_FragCoord.xy, vec2(0.06711056, 0.00583715))));

  float occ = 0.0;
  int dirs = u_dirs;
  int steps = u_steps;
  for (int k = 0; k < dirs; k++) {
    float a = ign * 6.28318530718 + float(k) * 6.28318530718 / float(dirs);
    vec2 dirv = vec2(cos(a), sin(a));
    vec2 step_uv = dirv * (screen_r / float(steps));

    float sinH = 0.0;
    float W_at_H = 0.0;
    vec3 firstD = vec3(0.0);
    bool have_first = false;

    for (int s = 1; s <= steps; s++) {
      vec2 suv = tex_coord + step_uv * float(s);
      if (suv.x < 0.0 || suv.x > 1.0 || suv.y < 0.0 || suv.y > 1.0) {
        break;
      }
      float sd = texture(u_depth, suv).r;
      if (sd <= 0.000001) {
        continue;
      }
      vec3 S = world_from_depth(suv, sd);
      vec3 D = S - P;
      float len = length(D);
      if (len > u_radius || len < 1e-4) {
        continue;
      }
      if (!have_first) {
        firstD = D;
        have_first = true;
      }
      float sinS = dot(D / len, V);
      float atten = 1.0 - (len / u_radius) * (len / u_radius);
      if (sinS > sinH) {
        sinH = sinS;
        W_at_H = atten;
      }
    }

    // tangent term: the slice direction projected onto the surface at the first hit.
    float sinT = 0.0;
    if (have_first) {
      vec3 Tsurf = firstD - N * dot(firstD, N);
      float tl = length(Tsurf);
      if (tl > 1e-5) {
        sinT = dot(Tsurf / tl, V) + 0.05;  // small tangent bias
      }
    }

    float ao_dir = max(0.0, sinH - max(sinT, 0.0)) * W_at_H;
    occ += ao_dir;
  }

  occ /= float(dirs);
  float ao = clamp(1.0 - u_intensity * occ, 0.0, 1.0);
  color = vec4(vec3(ao), 1.0);
}
