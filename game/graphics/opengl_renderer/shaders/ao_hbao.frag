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
uniform int u_debug;

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

  // screen-space march radius: project P and P + a world tangent of length u_radius.
  vec3 wt = abs(N.z) < 0.999 ? normalize(cross(N, vec3(0.0, 0.0, 1.0)))
                             : normalize(cross(N, vec3(1.0, 0.0, 0.0)));
  vec4 p0 = project_world(P);
  vec4 p1 = project_world(P + wt * u_radius);
  float screen_r = (p0.w > 0.0 && p1.w > 0.0) ? distance(p0.xy, p1.xy) : 0.05;
  // max clamp 0.10 (was 0.25): same GPU-watchdog/cache-thrash bound as ao_gtao.frag.
  screen_r = clamp(screen_r, 2.0 * max(px.x, px.y), 0.10);

  float ign = fract(52.9829189 *
                    fract(dot(gl_FragCoord.xy, vec2(0.06711056, 0.00583715))));

  // world-space image of the screen axes at P (same-window-depth unprojection): gives the
  // march direction's TRUE world direction, so the tangent below is analytic (N-based)
  // instead of first-sample-based. The old first-sample tangent inherited depth noise at
  // range: a noisy near sample lowered sinT while a farther sample raised sinH -> false
  // occlusion across flat ground at grazing angles (defect #5's 31% open-area darkening).
  vec2 eps = px * 4.0;
  vec3 du_world = (world_from_depth(tex_coord + vec2(eps.x, 0.0), d) - P) / eps.x;
  vec3 dv_world = (world_from_depth(tex_coord + vec2(0.0, eps.y), d) - P) / eps.y;

  // defect #7 floor flat-wash (attempt 5): HBAO's single-max-horizon estimator reads
  // grazing terrain micro-relief + D24 quantization lift at FULL weight (no cosine arc
  // weighting like GTAO), so a fixed 7-deg bias leaves a broad wash on open ground
  // (x86 floor term 0.756). Scale the angle bias with grazing incidence: face-on
  // surfaces keep the tight 0.12 rad contact response, grazing floors get up to
  // ~0.37 rad of horizon tolerance, which flattens micro-relief but leaves real
  // walls/props (horizons 45deg+) intact.
  float grz = 1.0 - abs(dot(N, V));
  // closing round: 0.50 -> 0.38 grazing coefficient. SSAO is the perceptual reference and
  // HBAO read too muted at 0.50; but the first cut (0.30) brought the grazing floor wash
  // back (cr7 x86: farfloor +3.2% / nearfloor +3.9% vs SSAO ~0). 0.38 + the estimator
  // intensity raise recovers crease punch without re-washing open floor; real walls/props
  // (45 deg+ horizons) still occlude.
  float abias = 0.12 + 0.38 * grz * grz;
  // Near-field micro-relief rejection (see ao_gtao.frag): HBAO's single-max horizon has
  // no cosine suppression, so a centimeter bump near P reads as a 20-30 deg horizon at
  // grazing regardless of the angle bias (x86 floor term stuck at 0.756). Capped so
  // distant creases keep contact AO.
  // closing round: cap 0.60 -> 0.52 of radius. 0.60 muted HBAO (owner); the first cut
  // (0.45) re-admitted the near-band micro-relief that washes grazing floors (cr7 x86
  // term floor 0.856 vs SSAO 0.913). 0.52 sits between; the visible-strength recovery
  // comes from the estimator intensity instead. Uncapped min-r killed cliffbase contact
  // (v5 sweep, 0.996) — keep the cap.
  float minr = min(0.035 * dcam, 0.52 * u_radius);
  float abias_s = sin(abias);
  float abias_c = cos(abias);

  float occ = 0.0;
  int dirs = u_dirs;
  int steps = u_steps;
  for (int k = 0; k < dirs; k++) {
    float a = ign * 6.28318530718 + float(k) * 6.28318530718 / float(dirs);
    vec2 dirv = vec2(cos(a), sin(a));
    vec2 step_uv = dirv * (screen_r / float(steps));

    // analytic tangent: the march direction's world image projected onto the surface
    // plane. sinT is the horizon floor — the flat surface itself never occludes.
    vec3 wdir = du_world * dirv.x + dv_world * dirv.y;
    vec3 Tsurf = wdir - N * dot(wdir, N);
    float tl = length(Tsurf);
    float sinT = (tl > 1e-6) ? dot(Tsurf / tl, V) : 0.0;
    // defect #7 grazing-floor whiteness: bias in the ANGLE domain (a flat sine bias
    // shrinks to nothing exactly where grazing depth noise peaks, sinT -> 1 on grazing
    // ground). sin(a+B) = sinA cosB + cosA sinB, with B grazing-adaptive (see above).
    sinT = clamp(sinT * abias_c + sqrt(max(0.0, 1.0 - sinT * sinT)) * abias_s, -1.0, 1.0);

    float sinH = sinT;
    float W_at_H = 0.0;

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
      if (len > u_radius || len < max(1e-4, minr)) {
        continue;
      }
      float sinS = dot(D / len, V);
      float atten = 1.0 - (len / u_radius) * (len / u_radius);
      if (sinS > sinH) {
        sinH = sinS;
        W_at_H = atten;
      }
    }

    float ao_dir = max(0.0, sinH - sinT) * W_at_H;
    occ += ao_dir;
  }

  occ /= float(dirs);
  float ao = clamp(1.0 - u_intensity * occ, 0.0, 1.0);
  // defect #7 (owner: "AO = local detail, not global shading"): near-field fade — AO is
  // a contact/crease effect. Closing round: fade the term to 1.0 between 20 m and 45 m from
  // the camera, matching SSAO (HBAO read too muted; the old 15->35 m fade cut mid-field
  // occlusion too early) so distant scenery (incl. the sea and the seafloor seen through
  // its transparency) is untouched; platformer contact shadows live well inside 40 m.
  // 4096 units = 1 m.
  ao = mix(ao, 1.0, smoothstep(81920.0, 184320.0, dcam));
  color = vec4(vec3(ao), 1.0);
}
