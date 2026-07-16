#version 410 core

// Grecharged-ambient-occlusion: ground-truth AO (Activision GTAO). Per slice we find the
// two horizon angles h1/h2 (both sides of the view axis, within the slice plane) and
// integrate the COSINE-WEIGHTED visible arc against the surface normal projected into the
// slice (the closed-form a = 0.25*(-cos(2h-g) + cos(g) + 2h*sin(g))). This is a genuinely
// different estimator from the HBAO max-horizon accumulation: it integrates the whole
// cosine-weighted arc rather than a single clamped horizon difference, giving smoother,
// physically-plausible gradients. A flat plane facing the camera integrates to ~1.0 (no
// darkening); a 90-degree corner integrates to <1. Procedural slices, no arrays / no noise
// texture (Adreno bug class).
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
uniform int u_samples;  // unused
uniform int u_dirs;     // slices
uniform int u_steps;
uniform int u_debug;

const float PI = 3.14159265359;
const float HALF_PI = 1.57079632679;

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
  vec3 V = normalize(u_cam_pos.xyz - P);  // view direction (toward camera)
  if (dot(N, V) < 0.0) {
    N = -N;
  }

  // screen-space march radius.
  vec3 wt = abs(N.z) < 0.999 ? normalize(cross(N, vec3(0.0, 0.0, 1.0)))
                             : normalize(cross(N, vec3(1.0, 0.0, 0.0)));
  vec4 p0 = project_world(P);
  vec4 p1 = project_world(P + wt * u_radius);
  float screen_r = (p0.w > 0.0 && p1.w > 0.0) ? distance(p0.xy, p1.xy) : 0.05;
  // max clamp 0.10 (was 0.25): a whole-screen march on degenerate transition-frame depth
  // is texture-cache-hostile and multiplies the draw time into the GPU-watchdog zone
  // (defect #6 residual); 0.10 * 2400px is still a 240px radius, visually equivalent.
  screen_r = clamp(screen_r, 2.0 * max(px.x, px.y), 0.10);

  float ign = fract(52.9829189 *
                    fract(dot(gl_FragCoord.xy, vec2(0.06711056, 0.00583715))));

  // defect #7 residual (attempt 5): near-field micro-relief/quantization rejection.
  // A centimeter bump at r->0 subtends an arbitrarily large horizon angle (theta =
  // atan(h/r)), so no fixed angle bias can cover it. Reject march samples closer than
  // ~2.5% of the camera distance, CAPPED at 35% of the radius so distant creases
  // (whose whole march projects inside the min-r at range) keep their contact AO.
  float minr = min(0.03 * dcam, 0.35 * u_radius);

  // world-space image of the screen axes at P: unproject uv +/- eps AT THE SAME window
  // depth and subtract. The slice basis must be aligned with the ACTUAL march sides — an
  // assumed cross-product basis has the wrong handedness for vertical slices (the GS
  // projection flips Y), swapping the toward/away horizon sides relative to gamma and
  // collapsing the visible arc to ~2*(90-gamma) on grazing flat ground (defect #5's
  // measured 54% open-area darkening).
  vec2 eps = px * 4.0;
  vec3 du_world = (world_from_depth(tex_coord + vec2(eps.x, 0.0), d) - P) / eps.x;
  vec3 dv_world = (world_from_depth(tex_coord + vec2(0.0, eps.y), d) - P) / eps.y;

  // defect #7 floor flat-wash ROOT CAUSE (attempt 5): uniform slice azimuths around V.
  // The GTAO slice-sum identity
  // (sum projLen*(a1+a2)/n == 1 on ANY unoccluded plane) requires the slice planes
  // uniformly distributed in azimuth around V. Screen-uniform march azimuths mapped
  // through the anisotropic chord basis (256:128 uv scale + ray obliquity) cluster
  // toward the horizontal, which UNDER-integrates exactly at grazing (gamma large)
  // -> the deterministic open-floor wash (v1-nosamples still measured farfloor 0.85).
  // Fix: orthonormal basis (e1,e2) perpendicular to V, uniform azimuth phi there,
  // and the screen march direction recovered through the INVERSE 2x2 chord map so
  // the +uv march side still lands on the +slice_dir horizon side (handedness safe).
  vec3 e1 = du_world - V * dot(du_world, V);
  float e1l = length(e1);
  e1 = (e1l > 1e-6) ? e1 / e1l : vec3(0.0);
  vec3 e2 = dv_world - V * dot(dv_world, V);
  e2 -= e1 * dot(e2, e1);
  float e2l = length(e2);
  e2 = (e2l > 1e-6) ? e2 / e2l : vec3(0.0);
  float m00 = dot(du_world, e1), m01 = dot(dv_world, e1);
  float m10 = dot(du_world, e2), m11 = dot(dv_world, e2);
  float mdet = m00 * m11 - m01 * m10;

  float visibility = 0.0;
  int slices = u_dirs;
  int steps = u_steps;

  for (int k = 0; k < slices; k++) {
    float phi = ign * PI + float(k) * PI / float(slices);
    float cphi = cos(phi);
    float sphi = sin(phi);
    vec3 slice_dir = e1 * cphi + e2 * sphi;  // uniform azimuth around V
    // screen march direction whose ray-bundle chord lies in THIS slice plane:
    // dir_uv = M^-1 * (cphi, sphi), sign-fixed so +uv marches the +slice_dir side.
    vec2 dir_uv = vec2(m11 * cphi - m01 * sphi, -m10 * cphi + m00 * sphi);
    dir_uv *= sign(mdet);
    float dl_uv = length(dir_uv);
    if (dl_uv < 1e-8 || abs(mdet) < 1e-12) {
      continue;
    }
    dir_uv /= dl_uv;
    vec2 step_uv = dir_uv * (screen_r / float(steps));

    // In the slice plane, angle is measured from V. cos(angle)=dot(dir,V).
    // Find max cos on each side (positive-uv side = h_pos, negative = h_neg).
    float cH_pos = -1.0;
    float cH_neg = -1.0;
    for (int s = 1; s <= steps; s++) {
      // positive side
      vec2 uvp = tex_coord + step_uv * float(s);
      if (uvp.x >= 0.0 && uvp.x <= 1.0 && uvp.y >= 0.0 && uvp.y <= 1.0) {
        float sdp = texture(u_depth, uvp).r;
        if (sdp > 0.000001) {
          vec3 Dp = world_from_depth(uvp, sdp) - P;
          float lp = length(Dp);
          if (lp > max(1e-4, minr)) {
            float hs = dot(Dp / lp, V);
            hs = mix(hs, -1.0, clamp((lp - u_radius) / (0.5 * u_radius), 0.0, 1.0));
            cH_pos = max(cH_pos, hs);
          }
        }
      }
      // negative side
      vec2 uvn = tex_coord - step_uv * float(s);
      if (uvn.x >= 0.0 && uvn.x <= 1.0 && uvn.y >= 0.0 && uvn.y <= 1.0) {
        float sdn = texture(u_depth, uvn).r;
        if (sdn > 0.000001) {
          vec3 Dn = world_from_depth(uvn, sdn) - P;
          float ln = length(Dn);
          if (ln > max(1e-4, minr)) {
            float hs = dot(Dn / ln, V);
            hs = mix(hs, -1.0, clamp((ln - u_radius) / (0.5 * u_radius), 0.0, 1.0));
            cH_neg = max(cH_neg, hs);
          }
        }
      }
    }

    // horizon angles measured from V, signed by side (positive side = +, negative = -).
    float h1 = -acos(clamp(cH_neg, -1.0, 1.0));  // negative side, in [-pi/2 region .. 0)
    float h2 = acos(clamp(cH_pos, -1.0, 1.0));    // positive side, in (0 .. +pi/2 region]

    // defect #7 grazing-floor whiteness: depth quantization at range lifts the apparent
    // horizon a few degrees above a truly flat plane (worst on grazing open ground —
    // shoreline sand read term ~0.93 => 5.3% open-area darkening). Push both horizons
    // OUTWARD by a fixed angle bias before the hemisphere clamp: flat ground clamps back
    // to the full arc (integrates to 1.0), while real crease horizons sit tens of degrees
    // inside and barely move.
    const float HBIAS = 0.12;
    h1 -= HBIAS;
    h2 += HBIAS;

    // component of N in the slice plane basis (slice_dir, V):
    float n_along_dir = dot(N, slice_dir);
    float n_along_V = dot(N, V);
    float projLen = length(vec2(n_along_dir, n_along_V));
    if (projLen < 1e-5) {
      continue;
    }
    float gamma = atan(n_along_dir, n_along_V);  // signed angle of N vs V within slice

    // clamp horizons to the hemisphere around gamma (Activision GTAO).
    h1 = gamma + max(h1 - gamma, -HALF_PI);
    h2 = gamma + min(h2 - gamma, HALF_PI);

    float cg = cos(gamma);
    float sg = sin(gamma);
    // closed-form cosine-weighted arc integral per side.
    float a1 = 0.25 * (-cos(2.0 * h1 - gamma) + cg + 2.0 * h1 * sg);
    float a2 = 0.25 * (-cos(2.0 * h2 - gamma) + cg + 2.0 * h2 * sg);
    visibility += projLen * (a1 + a2);
  }

  visibility /= float(slices);
  // visibility is in [0,1] for a flat facing plane -> ~1.0. Fold intensity into the
  // occlusion (1 - visibility) so the default look matches the other estimators.
  float occ = 1.0 - clamp(visibility, 0.0, 1.0);
  // closing round, defect-5 cap at Stronger + GTAO consistency: GRAZING-MODULATED
  // OCCLUSION GATE (see ao_hbao.frag for the full rationale — a flat gate cannot separate
  // the wash from shallow creases; the discriminator is grazing incidence, the owner's own
  // precision). GTAO's horizon integral reads the bumpy open terrain at grazing as a broad
  // ~0.20-0.30 occ (x86 training term floor 0.902 at int 0.65; still 0.961 after a flat
  // 0.22-0.42 gate). In daylight the (1-dst) ambient-fraction composite masks it (device
  // open 2.4%); at dusk/in shadow the mask approaches 1 and it blooms into a whole-floor
  // wash (device dusk grid: open 6.7-8.2% at every strength) — the owner's "sols au
  // global" / "fort a certains endroits, inexistant a d'autres" variance. Grazing floors
  // gate at ~0.3-0.43 (wash dead, on-floor object contact occ 0.5+ passes); walls and
  // creases gate near 0 (calibrated look unchanged) — at every strength and time of day.
  float grzg = 1.0 - abs(dot(N, V));
  float gate_lo = 0.05 + 0.38 * grzg * grzg;
  occ *= smoothstep(gate_lo, gate_lo + 0.14, occ);
  float ao = clamp(1.0 - u_intensity * occ, 0.0, 1.0);
  // defect #7 (owner: "AO = local detail, not global shading"): near-field fade — AO is
  // a contact/crease effect. Closing round (GTAO consistency): fade the term to 1.0 between
  // 30 m and 70 m from the camera — push the fade boundary out of the visible mid-field so
  // GTAO reads consistently across the scene, while distant scenery (incl. the sea and the
  // seafloor seen through its transparency) still fades out. 4096 units = 1 m.
  ao = mix(ao, 1.0, smoothstep(122880.0, 286720.0, dcam));
  color = vec4(vec3(ao), 1.0);
}
