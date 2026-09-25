// Round-4 mandate B: classic sun SHADOW MAPPING. u_pbr_shadow_mvp maps camera-relative
// meters (== v_fringe_rel) to the light's clip space; tex_PBR_SHADOW is the depth-only sun
// map on unit 9, sampled as a HW-PCF compare sampler (LEQUAL). u_pbr_shadow_on gates it.
// lighting-shadows (SPEC §4.8) : ATLAS D'OMBRE TUILE. Remplace l'unique `u_pbr_shadow_mvp` par
// 4 matrices de tuile — les cascades de l'astre DOMINANT (0..cascades-1) et la tuile 3 pour le
// SECOND astre. Deux astres, deux ombres, aucun fondu ni attribution.
uniform mat4 u_shadow_tile_mvp[4];
uniform int u_shadow_tiles;    // bit t = tuile t active cette image (cote LECTURE)
uniform vec4 u_shadow_split;   // demi-etendues des cascades 0..2 (m), w = nombre de cascades
uniform float u_shadow_strength;  // lighting-shadows partie B : force du reglage joueur, 0..1
uniform vec4 u_shadow_texel;   // metres par texel, par tuile
uniform float u_shadow_tile_px;
uniform int u_shadow_key;      // 0 : le soleil porte les cascades, 1 : la lune verte
uniform int u_shadow_proof;
uniform sampler2D tex_SHADOW_ACTOR;
uniform int u_pbr_shadow_on;
// Round-5 suspect (d): the read-side map is anchored to the camera position of the frame
// that WROTE it (camera-relative space), but v_fringe_rel uses the CURRENT camera —
// without correction every shadow trails camera motion by one frame (continuous
// displacement during the owner's orbit repro). cam_delta = (cam_now - cam_at_write)/4096.
uniform vec3 u_pbr_shadow_cam_delta;
// Plain sampler2D + manual in-shader compare: the Adreno 618 HW compare path
// (sampler2DShadow + COMPARE_REF_TO_TEXTURE) returns a constant 1.0 on-device
// (proven with a 0.25-cleared map). Depth-as-float sampling is portable.
uniform highp sampler2D tex_PBR_SHADOW;
// Debug-only bias override added to the compare ref (prop debug.opengoal.pbr.shadowbias /
// OG_PBR_SHADOWBIAS, default 0.0 = no effect). +0.5 must black out every in-box receiver
// if the HW depth compare works — the Adreno-driver binary test.
uniform float u_pbr_shadow_bias;

// ROUND 5: 16-tap Poisson disk for a wide-penumbra SOFT PCF (replaces the round-4 3x3
// grid — a regular grid aliases against the shadow-map texel lattice => the staircase the
// owner still saw; a Poisson disk does not). Rotated per fragment (see the PCF loop).
const vec2 RT_POISSON16[16] = vec2[](
  vec2(-0.94201624, -0.39906216), vec2(0.94558609, -0.76890725), vec2(-0.094184101, -0.92938870),
  vec2(0.34495938, 0.29387760),   vec2(-0.91588581, 0.45771432), vec2(-0.81544232, -0.87912464),
  vec2(-0.38277543, 0.27676845),  vec2(0.97484398, 0.75648379),  vec2(0.44323325, -0.97511554),
  vec2(0.53742981, -0.47373420),  vec2(-0.26496911, -0.41893023),vec2(0.79197514, 0.19090188),
  vec2(-0.24188840, 0.99706507),  vec2(-0.81409955, 0.91437590), vec2(0.19984126, 0.78641367),
  vec2(0.14383161, -0.14100790));

// lighting-shadows (SPEC §4.8) : L'ATLAS TUILE, ECHANTILLONNE PAR TUILE.
// `rt_tile_vis` teste UNE tuile de l'atlas (16-tap Poisson, identique au round-5 par tuile) ;
// rend -1.0 si le fragment tombe hors de son cadre. `rt_key_vis` choisit la cascade de l'astre
// DOMINANT et fond en douceur cascade->cascade et cascade->bord ; `rt_sec_vis` fait la meme
// chose pour la tuile UNIQUE du second astre (pas de cascade, juste un bord qui fond).
float rt_tile_vis(int t, vec3 P_rel, vec3 sN, float sndl, float dist) {
  float noff = u_shadow_texel[t] * (u_lighting_on != 0 ? mix(1.5, 5.0, 1.0 - sndl)
                                                       : mix(0.75, 2.0, 1.0 - sndl));
  vec3 sworld = P_rel + u_pbr_shadow_cam_delta + sN * noff;
  vec4 sp = u_shadow_tile_mvp[t] * vec4(sworld, 1.0);
  vec3 suv = sp.xyz / sp.w * 0.5 + 0.5;
  if (suv.x < 0.002 || suv.x > 0.998 || suv.y < 0.002 || suv.y > 0.998 || suv.z >= 1.0) {
    return -1.0;
  }
  float bias = (u_lighting_on != 0 ? 0.0010 : 0.0012) + u_pbr_shadow_bias;
  float ref = suv.z - bias;
  float pen = max(1.5 * u_shadow_texel[t], 0.02 + 0.015 * dist);  // penombre, en METRES
  // lighting-regimes (SPEC §4.11) : le regime elargit la penombre des cascades de la cle (dome
  // couvert x4, ambiante dominante x3, source basse x2). La tuile 3 (second astre) n'en recoit rien.
  // Programme jamais atteint par la poussee : defaut GL a zero, on garde alors la penombre nominale.
  if (t < 3 && u_rt_regime.y > 0.0) {
    pen *= u_rt_regime.y;
  }
  float rr = min(pen / (u_shadow_texel[t] * u_shadow_tile_px), 24.0 / u_shadow_tile_px);
  vec2 org = vec2(float(t & 1), float(t >> 1)) * 0.5;  // origine de la tuile dans l'atlas (uv)
  float hang = fract(sin(dot(gl_FragCoord.xy, vec2(12.9898, 78.233))) * 43758.5453) * 6.2831853;
  vec2 hc = vec2(cos(hang), sin(hang));
  mat2 hrot = mat2(hc.x, -hc.y, hc.y, hc.x);
  float vis = 0.0;
  vec2 lo = vec2(0.5 / u_shadow_tile_px);
  vec2 hi = vec2(1.0 - 0.5 / u_shadow_tile_px);
  for (int i = 0; i < 16; i++) {
    vec2 o = hrot * (RT_POISSON16[i] * rr);
    vec2 uv = clamp(suv.xy + o, lo, hi);
    vis += ref <= texture(tex_PBR_SHADOW, org + uv * 0.5).r ? 1.0 : 0.0;
  }
  return vis * (1.0 / 16.0);
}

float rt_key_vis(vec3 P_rel, vec3 sN, float sndl) {
  float d = length(P_rel);
  int n = int(u_shadow_split.w);
  for (int c = 0; c < 3; c++) {
    if (c >= n) {
      break;
    }
    float s = u_shadow_split[c];
    if (d < s) {
      float v = rt_tile_vis(c, P_rel, sN, sndl, d);
      if (v < 0.0) {
        return 1.0;
      }
      if (c + 1 < n && d > 0.9 * s) {
        float v2 = rt_tile_vis(c + 1, P_rel, sN, sndl, d);
        if (v2 >= 0.0) {
          v = mix(v, v2, (d - 0.9 * s) / (0.1 * s));
        }
      }
      if (c + 1 == n) {
        v = mix(1.0, v, 1.0 - smoothstep(s * 0.72, s * 0.96, d));
      }
      return v;
    }
  }
  return 1.0;
}

float rt_sec_vis(vec3 P_rel, vec3 sN, float sndl) {
  if ((u_shadow_tiles & 8) == 0) {
    return 1.0;
  }
  int n = int(u_shadow_split.w);
  float s = u_shadow_split[n > 0 ? n - 1 : 2];
  float d = length(P_rel);
  float v = rt_tile_vis(3, P_rel, sN, sndl, d);
  if (v < 0.0) {
    return 1.0;
  }
  return mix(1.0, v, 1.0 - smoothstep(s * 0.72, s * 0.96, d));
}

// lighting-shadows essai 6 : sonde de preuve, factorisee hors de shade.glsl pour que merc2.frag
// puisse la reutiliser mot pour mot (ropebridge n'a pas de composite shade_body ; sa preuve
// s'appuie sur la MEME couleur de diagnostic).
vec4 rt_shadow_proof_color(vec3 P_rel, vec3 sN, float sndl, float a) {
  float d = length(P_rel);
  int n = int(u_shadow_split.w);
  int cc = -1;
  for (int c2 = 0; c2 < 3; c2++) {
    if (c2 < n && d < u_shadow_split[c2]) {
      cc = c2;
      break;
    }
  }
  bool hit = false, actor_occ = false, full_occ = false;
  if (cc >= 0) {
    float noff = u_shadow_texel[cc] * (u_lighting_on != 0 ? mix(1.5, 5.0, 1.0 - sndl)
                                                          : mix(0.75, 2.0, 1.0 - sndl));
    vec3 sworld = P_rel + u_pbr_shadow_cam_delta + sN * noff;
    vec4 sp = u_shadow_tile_mvp[cc] * vec4(sworld, 1.0);
    vec3 suv = sp.xyz / sp.w * 0.5 + 0.5;
    if (suv.x >= 0.0 && suv.x <= 1.0 && suv.y >= 0.0 && suv.y <= 1.0 && suv.z < 1.0) {
      float bias = (u_lighting_on != 0 ? 0.0010 : 0.0012) + u_pbr_shadow_bias;
      float ref = suv.z - bias;
      vec2 org = vec2(float(cc & 1), float(cc >> 1)) * 0.5;
      float actor = texture(tex_SHADOW_ACTOR, org + clamp(suv.xy, 0.0, 1.0) * 0.5).r;
      float key_vis = rt_key_vis(P_rel, sN, sndl);
      // « Ombre par un acteur » = l'acteur est le PREMIER occulteur vers l'astre : sa profondeur
      // est celle de l'atlas complet au meme texel. Un acteur lui-meme a l'ombre du decor ne
      // compte pas (son ombre ne se voit pas).
      float full_c = texture(tex_PBR_SHADOW, org + clamp(suv.xy, 0.0, 1.0) * 0.5).r;
      actor_occ = (u_shadow_proof == 2) ? (actor < 0.999)
                                        : (ref > actor && abs(full_c - actor) < 2e-4);
      full_occ = key_vis < 0.5;
      hit = actor_occ && full_occ;
    }
  }
  // Quatre etats, pour que la sonde separe ses deux conditions : magenta = ombre d'acteur
  // (les deux), bleu = ombre du decor seulement, cyan = l'atlas acteur occulte mais pas l'atlas
  // complet (desaccord), vert = eclaire.
  if (!hit && full_occ) {
    return vec4(0.0, 0.0, 1.0, a);
  }
  if (!hit && actor_occ) {
    return vec4(0.0, 1.0, 1.0, a);
  }
  // L'alpha d'origine est garde : le test d'alpha de l'hote doit trancher comme d'habitude.
  return hit ? vec4(1.0, 0.0, 1.0, a) : vec4(0.0, 1.0, 0.0, a);
}
