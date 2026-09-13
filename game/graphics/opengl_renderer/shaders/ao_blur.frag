#version 410 core

// Grecharged-ambient-occlusion: separable bilateral blur of the AO buffer. 4 taps at
// offsets -1..2 * u_dir, poids EGAUX 1/4 (boite exacte sur la tuile d'entrelacement 4x4 des
// estimateurs, voir plus bas), each tap additionally weighted
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
  // lighting-ao-indirect, 2026-09-13 : LA GARDE SAUTE. Elle reservait la prediction de plan au
  // sous-echantillonnage (`u_ao_size.y < u_depth_size.y`), pour garder le palier HAUT
  // bit-identique au « look SSAO-High fige ». C'est precisement ce look que l'owner refuse.
  // Et la garde est ce qui empeche la boite de 4 de faire son travail au palier haut : sans
  // prediction, `dv` vaut l'ecart de distance BRUT entre deux texels voisins, qui atteint
  // plusieurs decimetres sur un sol rasant ; tous les taps tombent sous `exp(-dv^2/2sigma^2)`,
  // la boite se referme sur son centre, et la tuile d'entrelacement 4x4 ressort telle quelle.
  // Avec la prediction armee, `dv` est l'ecart au PLAN TANGENT local : ~0 sur une surface
  // continue, donc les quatre taps passent et la tuile s'annule exactement ; sur une vraie
  // arete la prediction casse et le rejet tient, inchange.
  float slope = 0.0;
  {
    float dp = texture(u_depth, tex_coord + u_dir).r;
    float dm = texture(u_depth, tex_coord - u_dir).r;
    if (dp > 0.000001 && dm > 0.000001) {
      float vp = distance(world_from_depth(tex_coord + u_dir, dp), u_cam_pos.xyz);
      float vm = distance(world_from_depth(tex_coord - u_dir, dm), u_cam_pos.xyz);
      slope = 0.5 * (vp - vm);
    }
  }

  // lighting-ao-indirect, refus owner (a)/(e) du 2026-09-12 : BOITE EXACTE DE 4, pas une
  // gaussienne de 5. Les estimateurs tirent desormais leur rotation d'une tuile d'ecran de
  // 4x4 texels portant 16 rotations distinctes (ao_ssao/hbao/gtao.frag). Quatre taps
  // CONSECUTIFS a poids EGAUX — offsets -1,0,+1,+2 — couvrent les quatre phases de la tuile
  // dans cet axe ; H puis V font donc la moyenne EXACTE des 16 rotations, et le motif
  // d'echantillonnage s'ANNULE au lieu d'etre etale. Une gaussienne (1,4,6,4,1)/16 ne
  // l'annule pas : elle en laisse un residu ~= 37 %, ce qui est precisement ce qui faisait
  // du bruit d'ecran de 2026-07-21 un scintillement. Le poids de profondeur bilateral reste
  // : sur une vraie discontinuite les taps sont rejetes, la boite se referme sur le centre,
  // et l'annulation cede la place a la preservation de l'arete — c'est l'ordre voulu.
  float gw0 = 0.25;
  float gw1 = 0.25;

  float sum = texture(u_ao, tex_coord).r * gw0;
  float wsum = gw0;

  // -1, +1, +2 taps (le +0 est le centre, deja pris)
  for (int i = 0; i < 3; i++) {
    float off = (i == 0) ? -1.0 : (i == 1) ? 1.0 : 2.0;
    float gw = gw1;
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
