#version 410 core

// Grecharged-grass-poc: flat-color grass (no texture yet, per the PoC spec).
// NEAR blades render solid. MID cards are procedurally cut into a TUFT of blades
// (owner polish 2026-07-10): the card was a translucent rectangle that read as a
// "blurry square" and — because a blended quad still wrote depth — sometimes
// showed as a hollow "empty square". Cutting the card into blade shapes and
// DISCARDING the gaps fixes both: it reads as a bushy grass clump and the gaps
// no longer write depth, so the crossed quad shows through instead of a hole.

in vec3 v_color;
in float v_alpha;
in vec2 v_uv;            // card-local coords (x in [-1,1], y in [0,1]); class-2 = hang-texture UV
flat in int v_is_card;
in float v_seed;         // class-2 cards: hang-texture select (0/1) instead of the tuft seed
// grass-shading (SPEC section 7) : la direction d'avancee horizontale du brin = la normale de son
// ruban. Combinee a gl_FrontFacing, elle separe la face eclairee de la face opposee du MEME brin —
// sans elle, un brin reste un aplat sous tous les angles.
in vec2 v_fwd_xz;
// lighting-shadows : position du brin, camera-relative en metres (voir grass.vert).
in vec3 v_shadow_rel;

// lighting-shadows (SPEC §4.8) : RECEVEUR DE L'ATLAS TUILE, meme geometrie que
// `background_common.cpp`/`shade.glsl`, mais SANS decalage de normale — un brin n'a pas de
// normale stable (deux faces, vent) : le decalage anti-acne est un simple offset vertical fixe.
uniform sampler2D tex_PBR_SHADOW;
uniform int u_pbr_shadow_on;
uniform vec3 u_pbr_shadow_cam_delta;
uniform mat4 u_shadow_tile_mvp[4];
uniform int u_shadow_tiles;
uniform vec4 u_shadow_split;
uniform vec4 u_shadow_texel;
uniform float u_shadow_tile_px;
// x = poids direct de l'astre CASCADES (image lue), y = poids direct du SECOND astre (0 si sa
// tuile 3 est eteinte). Poussés par GrassRenderer.cpp depuis `pbr_shadow_read_*_weight()`.
uniform vec2 u_grass_shadow_w;
// Plancher multiplicatif d'un brin en pleine ombre portee : le meme rapport que le sol applique
// dans son propre bras ombre (`u_rt_lit_boost` par defaut 1,15 -> 1/1,15).
uniform float u_grass_shadow_floor;

// Grecharged-grass-overhang7 ROUND 11 (design pivot): zone-3 hang cards sample the game's OWN
// hang-alpha texels — the exact texture pages the native painted strip uses (already resident).
uniform sampler2D u_hang0;  // bch-grassfringe
uniform sampler2D u_hang1;  // bch-leafyground-hang-2x1

// ROUND 22/23 PER-PIXEL SCREEN-COVERAGE INSTRUMENTATION. Shared PBR debug selector (android prop
// debug.opengoal.pbr.debug). Mode 30 = program tag, 31 = displacement tag. This shader has no PBR
// block, so the uniform is declared plainly. If a program is ever linked without it,
// glGetUniformLocation returns -1 and glUniform1i(-1, ...) is a documented no-op.
uniform int u_pbr_debug;

// grass-shading : 1 quand l'item est arme (le defaut : une correction derriere un drapeau eteint
// n'existe pas pour l'owner), 0 sous le bras `--off` de `proof_run.sh`. A 0, le facteur de face
// vaut exactement 1,0 — le pixel est celui du build precedent, au bit.
uniform float u_shade_face;

#ifdef OG_FLIP_PROBE
layout(location = 0) out vec4 color;
uniform int u_floor_probe;
layout(location = 4) out vec4 floor_probe_out;
#else
out vec4 color;
#endif

// lighting-shadows : une tuile de l'atlas, 4-tap PCF (l'herbe n'a pas besoin des 16 du sol — un
// brin est deja un petit texel a l'ecran, la penombre ne se voit pas). Rend -1 hors cadre.
float grass_tile_vis(int t, vec3 P) {
  vec3 sworld = P + u_pbr_shadow_cam_delta + vec3(0.0, u_shadow_texel[t] * 2.0, 0.0);
  vec4 sp = u_shadow_tile_mvp[t] * vec4(sworld, 1.0);
  vec3 suv = sp.xyz / sp.w * 0.5 + 0.5;
  if (suv.x < 0.002 || suv.x > 0.998 || suv.y < 0.002 || suv.y > 0.998 || suv.z >= 1.0) {
    return -1.0;
  }
  float ref = suv.z - 0.0010;
  vec2 org = vec2(float(t & 1), float(t >> 1)) * 0.5;  // origine de la tuile dans l'atlas
  float texel_uv = 0.5 / u_shadow_tile_px;
  vec2 lo = vec2(texel_uv);
  vec2 hi = vec2(1.0 - texel_uv);
  const vec2 TAPS[4] = vec2[4](vec2(-0.9, -0.3), vec2(0.3, -0.9), vec2(0.9, 0.3), vec2(-0.3, 0.9));
  float vis = 0.0;
  for (int i = 0; i < 4; i++) {
    vec2 uv = clamp(suv.xy + TAPS[i] * 1.5 * texel_uv, lo, hi);
    vis += ref <= texture(tex_PBR_SHADOW, org + uv * 0.5).r ? 1.0 : 0.0;
  }
  return vis * 0.25;
}

// Visibilite de l'astre qui porte les cascades, cote LECTURE — meme choix de cascade que
// `rt_key_vis` (shade.glsl), sans le N.L (l'offset est deja fixe dans `grass_tile_vis`).
float grass_key_vis(vec3 P) {
  float d = length(P);
  int n = int(u_shadow_split.w);
  for (int c = 0; c < 3; c++) {
    if (c >= n) {
      break;
    }
    float s = u_shadow_split[c];
    if (d < s) {
      float v = grass_tile_vis(c, P);
      if (v < 0.0) {
        return 1.0;
      }
      if (c + 1 < n && d > 0.9 * s) {
        float v2 = grass_tile_vis(c + 1, P);
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

// Visibilite du SECOND astre (tuile 3, pas de cascade, juste un bord qui fond).
float grass_sec_vis(vec3 P) {
  if ((u_shadow_tiles & 8) == 0) {
    return 1.0;
  }
  int n = int(u_shadow_split.w);
  float s = u_shadow_split[n > 0 ? n - 1 : 2];
  float d = length(P);
  float v = grass_tile_vis(3, P);
  if (v < 0.0) {
    return 1.0;
  }
  return mix(1.0, v, 1.0 - smoothstep(s * 0.72, s * 0.96, d));
}

// Facteur multiplicatif applique au brin : 1,0 exactement si l'atlas est eteint (bit pres, herbe
// hors regime recharge inchangee) ; sinon melange du plancher `u_grass_shadow_floor` par astre,
// pondere par le poids direct de CET astre (SPEC §4.8 : deux astres, deux ombres, jamais fondues).
float grass_shadow_factor() {
  if (u_pbr_shadow_on == 0) {
    return 1.0;
  }
  float key_vis = grass_key_vis(v_shadow_rel);
  float sec_vis = grass_sec_vis(v_shadow_rel);
  float g = mix(1.0, u_grass_shadow_floor, u_grass_shadow_w.x * (1.0 - key_vis));
  g *= mix(1.0, u_grass_shadow_floor, u_grass_shadow_w.y * (1.0 - sec_vis));
  return g;
}

void main() {
#ifdef OG_FLIP_PROBE
  floor_probe_out = vec4(0.0);
#endif
  float a = v_alpha;

  // ROUND 23 coverage census: grass is its OWN world geometry, not a re-shade of an already
  // tagged draw — it writes depth (glDepthMask GL_TRUE, GEQUAL) and occludes the ground under it,
  // and its alpha is 1.0 through the whole in-band region (v_alpha is only a distance LOD fade at
  // the band edges). Discarding it in the tag modes would hand its pixels back to the hfrag/tfrag
  // draw underneath and INFLATE the measured displaced coverage, so it gets its own tag instead.
  // Structural note: the class-2 branch below used to `return;` early. It is an else-branch now,
  // behaviour for behaviour identical, so the tag stays the LAST statement of main() on every
  // path — the invariant every other tagged shader holds.
  if (v_is_card == 2) {
    // ZONE-3 TEXTURED HANG CARD: alpha-cut sampling of the native strip texels, so the card IS the
    // game's own art (crisp ragged tips, no soft halo). u tiles along the lip (wrap); v is clamped
    // in-shader (the shared level texture object's wrap state must not be touched — tfrag uses it).
    vec2 uv = vec2(v_uv.x, clamp(v_uv.y, 0.002, 0.998));
    vec4 tx = mix(texture(u_hang0, uv), texture(u_hang1, uv), clamp(v_seed, 0.0, 1.0));
    if (tx.a < 0.45 || a < 0.02) {
      discard;
    }
    // v_color = the ground's dynamic baked light (*2 factor), matching the native strip's own draw.
    color = vec4(tx.rgb * v_color * grass_shadow_factor(), a);
  } else {
    if (v_is_card == 1) {
      // Cut the card quad into a few vertical sub-blades so it reads as a tuft.
      // Each sub-blade fills its slot at the base and tapers to a point; the top
      // edge is jagged (random per-blade height) so the clump never looks like a
      // rectangle. Fragments outside a blade are discarded (no color, no depth).
      // OWNER POLISH#6: 5 -> 3 sub-blades so the cards are LESS tufted than the near
      // grass (owner: cards "font beaucoup plus touffue que la vraie herbe").
      const float NB = 3.0;
      float fu = (v_uv.x * 0.5 + 0.5) * NB;        // 0..NB across the card width
      float bi = floor(fu);
      float fp = fu - bi;                           // 0..1 within this sub-blade slot
      float r = fract(sin((bi + 1.0) * 12.9898 + v_seed) * 43758.5453);
      float bladeTop = 0.55 + 0.45 * r;             // this sub-blade's height (0.55..1.0)
      if (v_uv.y > bladeTop) {
        discard;
      }
      float hw = 0.5 * (1.0 - v_uv.y / bladeTop);   // half width in slot units, taper to tip
      float dc = abs(fp - 0.5);
      if (dc > hw) {
        discard;
      }
    }

    if (a < 0.02) {
      discard;
    }
    // grass-shading : LA FACE ECLAIREE ET LA FACE OPPOSEE. Le facteur vient de
    // `grass_shade_face.glsl`, le MEME fichier que `grass_bake::shading_census()` compile en C++ :
    // l'ecart de luminance entre les deux faces que la preuve publie est celui que ce pixel recoit.
    // Les cartes texturees zone-3 (v_is_card == 2) en sont exclues — leur couleur vient de leurs
    // texels, c'est l'art natif du jeu et il ne se remodule pas.
    vec3 gs_shaded = v_color;
    {
      vec2 gs_fwd_xz = v_fwd_xz;
      float gs_side = gl_FrontFacing ? 1.0 : -1.0;
      float gs_face_dot = 0.0;
      float gs_face_mul = 1.0;
#include "grass_shade_face.glsl"
      gs_face_mul = mix(1.0, gs_face_mul, clamp(u_shade_face, 0.0, 1.0));
      gs_shaded = clamp(gs_shaded * gs_face_mul, vec3(0.0), vec3(1.5));
#ifdef OG_FLIP_PROBE
      if (u_floor_probe >= 2) {
        // lighting-flipped-faces-everywhere : le JUMEAU est la face opposee du MEME brin.
        float fc_flip = gl_FrontFacing ? 0.0 : 1.0;
        float mul_t = 1.0 + GRASS_FACE_AMP * (-gs_side) * gs_face_dot;
        float fc_on = dot(gs_shaded, vec3(0.299, 0.587, 0.114));
        float fc_tw = fc_on * mul_t / max(gs_face_mul, 1e-4);
        floor_probe_out = vec4(fc_on / max(fc_tw, 1e-4), 1.0, fc_tw,
                               1.0 + fc_flip + 4.0 * float(u_floor_probe));
      }
#endif
    }
    color = vec4(gs_shaded * grass_shadow_factor(), a);
  }

  // ===== ROUND 23 COVERAGE TAG (see tfrag3.frag / hfrag.frag for the rationale) =====
  // grass = teal. No PBR/displacement path here, so mode 31 reads 0.0 by construction — that is
  // exactly the quantity being measured. color.a is NEVER touched (the alpha discards above have
  // already run and the LOD fade must keep behaving), so the tag arrives on the same pixels the
  // untagged frame draws.
  if (u_pbr_debug == 30) {
    color.rgb = vec3(0.0, 0.5, 0.5);
  } else if (u_pbr_debug >= 31 && u_pbr_debug <= 34) {
    // ROUND 24: 31 = displacement tag, 32 = maps-bearing DENOMINATOR mask, 33 = dead-zone
    // diagnostic. This program never carries PBR material maps, so it is black in all three —
    // otherwise its scene colour would be counted as mask/diagnostic signal.
    color.rgb = vec3(0.0);
  }
}
