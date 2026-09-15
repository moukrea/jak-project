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

#include "ao_hut_report.glsl"

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
uniform float u_broad;  // round F: SSAO-equivalent broad-term intensity (0 = off)
uniform int u_samples;  // unused
uniform int u_dirs;     // slices
uniform int u_steps;
uniform int u_debug;
// lighting-ao-indirect : temoin de mesure, 0 en jeu. 1 restaure l'ancrage MONDE de la rotation
// du noyau (l'etat d'avant le 2026-09-13) pour que la preuve mesure le defaut et sa correction
// dans la MEME course. Pose par AmbientOcclusion.cpp, uniquement sous mesure.
uniform int u_ao_legacy_noise;

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

// Round F (owner 2026-07-16 16:50): SSAO-model broad soft depth term — see ao_hbao.frag
// for the full rationale. SSAO's hemisphere estimator verbatim (radius 5120 = 1.25 m,
// tangent-plane occluder test, grazing-scaled threshold, near-field min-r, 1.5r falloff)
// at a fixed 10-sample budget, blended multiplicatively with GTAO's cosine-horizon
// contact term so GTAO adds DEPTH like SSAO while keeping its sharp physical character.
float broad_occ(vec3 P, vec3 N, vec3 V, float dcam, float ign) {
  const float BR = 5120.0;  // SSAO's broad radius — SSAO is the model
  vec3 up_b = abs(N.z) < 0.999 ? vec3(0.0, 0.0, 1.0) : vec3(1.0, 0.0, 0.0);
  vec3 Tb = normalize(cross(up_b, N));
  vec3 Bb = cross(N, Tb);
  float bias_b = 0.02 * BR + 0.005 * dcam;
  float grz_b = 1.0 - abs(dot(N, V));
  float above_b = 0.05 * BR * (1.0 + 4.5 * grz_b * grz_b);
  float minr_b = min(0.025 * dcam, 0.35 * BR);
  const int NB = 10;
  float occ_b = 0.0;
  for (int i = 0; i < NB; i++) {
    float a = ign * 6.28318530718 + float(i) * 2.399963;
    float r = sqrt((float(i) + 0.5) / float(NB));
    vec3 dirb = Tb * (cos(a) * r) + Bb * (sin(a) * r) + N * sqrt(max(0.0, 1.0 - r * r));
    vec3 sp = P + N * (0.02 * BR) + dirb * (BR * mix(0.25, 1.0, r));
    vec4 proj = project_world(sp);
    if (proj.w <= 0.0 || proj.x < 0.0 || proj.x > 1.0 || proj.y < 0.0 || proj.y > 1.0) {
      if (u_hut_report != 0) hut_broad_reject.x += 1.0;
      continue;
    }
    float ds = texture(u_depth, proj.xy).r;
    if (ds <= 0.000001) {
      if (u_hut_report != 0) hut_broad_reject.y += 1.0;
      continue;
    }
    vec3 Ps = world_from_depth(proj.xy, ds);
    float dPPs = distance(P, Ps);
    float above = dot(Ps - P, N);
    if (u_hut_report != 0) {
      hut_broad_reject.z += float(dPPs >= BR * 1.5);
      hut_broad_reject.w += float(dPPs <= minr_b);
      hut_broad_other.x += float(!(distance(Ps, u_cam_pos.xyz) < distance(sp, u_cam_pos.xyz) - bias_b));
      hut_broad_other.y += float(!(above > above_b));
      hut_broad_other.w += 1.0;
    }
    if (distance(Ps, u_cam_pos.xyz) < distance(sp, u_cam_pos.xyz) - bias_b &&
        dPPs < BR * 1.5 && dPPs > minr_b && above > above_b) {
      if (u_hut_report != 0) hut_broad_other.z += 1.0;
      occ_b += 1.0 - smoothstep(BR, BR * 1.5, dPPs);
    }
  }
  return occ_b / float(NB);
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
  if (d <= 0.000001) {
    color = u_hut_report == 0 ? vec4(1.0) : vec4(0.0);
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

  // lighting-ao-indirect, REFUS DE L'OWNER (a)/(d)/(e), 2026-09-12 : « en qualite faible j'ai le
  // damier (SSAO), en qualite elevee j'ai le damier (GTAO) » et « un flou vraiment degueulasse
  // qui bouge dans tous les sens ». LA CAUSE ETAIT ICI. La rotation du noyau etait ancree a une
  // CELLULE MONDE de cote max(1024, dcam*0.02) unites (1024 = 0,25 m) : TOUS les fragments d'une
  // cellule tiraient la MEME rotation, donc la MEME erreur d'estimation. Sur un sol ou un mur a
  // 3 m, cette cellule se projette en un pave de ~60 pixels de scene : c'est le damier, et il
  // n'apparait que « la ou elle s'applique » parce que la rotation ne change le resultat qu'au
  // voisinage d'un occluder — mot pour mot ce que l'owner decrit. Il est present aux DEUX
  // extremites de qualite et dans les DEUX algorithmes parce que les trois estimateurs
  // partageaient ce bloc. Et comme le cote de la cellule varie CONTINUMENT avec dcam, tout
  // deplacement de camera fait glisser la grille : « ca bouge dans tous les sens ».
  // Pourquoi le recensement de motif l'a lu a 1000 (aucun motif) aux trois paliers : une grille
  // MONDE projetee n'a de periode dans AUCUNE direction d'ecran. Le test de periode 2/4 ne
  // pouvait pas la voir. La porte mesurait a cote.
  //
  // ECHANTILLONNAGE ENTRELACE D'ECRAN, periode 4x4, 16 rotations distinctes, sans terme de
  // temps. Deux proprietes, toutes deux par CONSTRUCTION :
  //   - a camera immobile le tampon d'AO est identique d'une image a l'autre (rien dans `ign`
  //     ne depend du temps ni de la camera) : la variation temporelle est nulle, pas petite ;
  //   - le flou en BOITE de 4 taps par axe de `ao_blur.frag` moyenne EXACTEMENT les 16
  //     rotations de la tuile, donc le motif s'annule au lieu d'etre etale. C'est pourquoi le
  //     retour a un bruit d'ecran ne ramene pas le scintillement de 2026-07-21 : ce qui
  //     scintillait, c'etait un bruit d'ecran sous un noyau GAUSSIEN qui ne l'annulait pas ; un
  //     point du monde qui glisse sur la tuile lit desormais la meme MOYENNE de 16 rotations.
  // L'index est une permutation par inversion de bits (van der Corput) : deux texels voisins
  // recoivent des angles eloignes, pas consecutifs.
  // LE TEMOIN DE MESURE. `u_ao_legacy_noise` restaure l'ancrage MONDE d'avant le 2026-09-13,
  // et RIEN d'autre. Il vaut 0 en jeu, toujours : seule la preuve l'allume, une image sondee
  // sur deux, pour que la MEME course, sur la MEME scene et le MEME binaire, publie la
  // grandeur de blocs des DEUX regimes. L'owner (verdict (e)) : « une grandeur qui ne
  // retrouve pas le defaut connu ne peut pas prouver sa disparition ».
  float ign;
  if (u_ao_legacy_noise != 0) {
    vec3 q = floor(P / max(1024.0, dcam * 0.02));
    vec3 p3 = fract(q * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    ign = fract((p3.x + p3.y) * p3.z);
  } else {
    ivec2 ao_tile = ivec2(gl_FragCoord.xy) & 3;
    int ao_rot = ((ao_tile.x & 1) << 3) | ((ao_tile.y & 1) << 2) | (ao_tile.x & 2) |
                 ((ao_tile.y & 2) >> 1);
    ign = (float(ao_rot) + 0.5) / 16.0;
  }

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
  vec3 du_world = (world_from_depth(snapped + vec2(eps.x, 0.0), d) - P) / eps.x;
  vec3 dv_world = (world_from_depth(snapped + vec2(0.0, eps.y), d) - P) / eps.y;

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
      if (u_hut_report != 0) hut_other.z += 1.0;
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
      if (u_hut_report != 0) hut_reject.x += float(!(uvp.x >= 0.0 && uvp.x <= 1.0 && uvp.y >= 0.0 && uvp.y <= 1.0));
      if (uvp.x >= 0.0 && uvp.x <= 1.0 && uvp.y >= 0.0 && uvp.y <= 1.0) {
        float sdp = texture(u_depth, uvp).r;
        if (u_hut_report != 0) hut_reject.y += float(!(sdp > 0.000001));
        if (sdp > 0.000001) {
          vec3 Dp = world_from_depth(uvp, sdp) - P;
          float lp = length(Dp);
          if (u_hut_report != 0) {
            hut_reject.z += float(lp >= 1.5 * u_radius);
            hut_reject.w += float(!(lp > max(1e-4, minr)));
            hut_other.w += 1.0;
          }
          if (lp > max(1e-4, minr)) {
            float hs = dot(Dp / lp, V);
            hs = mix(hs, -1.0, clamp((lp - u_radius) / (0.5 * u_radius), 0.0, 1.0));
            cH_pos = max(cH_pos, hs);
          }
        }
      }
      // negative side
      vec2 uvn = tex_coord - step_uv * float(s);
      if (u_hut_report != 0) hut_reject.x += float(!(uvn.x >= 0.0 && uvn.x <= 1.0 && uvn.y >= 0.0 && uvn.y <= 1.0));
      if (uvn.x >= 0.0 && uvn.x <= 1.0 && uvn.y >= 0.0 && uvn.y <= 1.0) {
        float sdn = texture(u_depth, uvn).r;
        if (u_hut_report != 0) hut_reject.y += float(!(sdn > 0.000001));
        if (sdn > 0.000001) {
          vec3 Dn = world_from_depth(uvn, sdn) - P;
          float ln = length(Dn);
          if (u_hut_report != 0) {
            hut_reject.z += float(ln >= 1.5 * u_radius);
            hut_reject.w += float(!(ln > max(1e-4, minr)));
            hut_other.w += 1.0;
          }
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
      if (u_hut_report != 0) hut_other.z += 1.0;
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
  if (u_hut_report != 0) hut_terms.x = occ;
  occ *= smoothstep(gate_lo, gate_lo + 0.14, occ);
  if (u_hut_report != 0) hut_terms.y = occ;
  float ao = clamp(1.0 - u_intensity * occ, 0.0, 1.0);
  // round F: multiply in the SSAO-model broad soft depth term (own SSAO-matched
  // 20->45 m fade; the contact term below keeps GTAO's 30->70 m fade unchanged).
  // GTAO-specific saturation (device strengthgrid, 2x reproduced): at Stronger the
  // linear broad scaling (2.0 * 1.5 = 3.0) pushed the whole-frame delta to 8.12-8.18%,
  // breaching the defect-5 global<=8% cap while open/crease/ordering all held. GTAO's
  // contact term already scales with strength; saturating the broad intensity at 2.7
  // (Weaker/Default 1.2/2.0 untouched) lands global ~7.5% with crease ~46% > default
  // 41.5%, so the Stronger step stays visible without breaching the cap.
  if (u_broad > 0.0) {
    float broad_k = min(u_broad, 2.7);
    float ao_b = clamp(1.0 - broad_k * broad_occ(P, N, V, dcam, ign), 0.0, 1.0);
    ao_b = mix(ao_b, 1.0, smoothstep(81920.0, 184320.0, dcam));
    ao = clamp(ao * ao_b, 0.0, 1.0);
  }
  // defect #7 (owner: "AO = local detail, not global shading"): near-field fade — AO is
  // a contact/crease effect. Closing round (GTAO consistency): fade the term to 1.0 between
  // 30 m and 70 m from the camera — push the fade boundary out of the visible mid-field so
  // GTAO reads consistently across the scene, while distant scenery (incl. the sea and the
  // seafloor seen through its transparency) still fades out. 4096 units = 1 m.
  ao = mix(ao, 1.0, smoothstep(122880.0, 286720.0, dcam));
  color = vec4(vec3(ao), 1.0);
  if (u_hut_report != 0) {
    hut_terms.z = smoothstep(81920.0, 184320.0, dcam);
    hut_terms.w = ao;
    hut_finish(N);
  }
}
