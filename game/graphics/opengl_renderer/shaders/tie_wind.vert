#version 410 core

layout (location = 0) in vec3 position_in;
layout (location = 1) in vec3 tex_coord_in;
layout (location = 2) in int time_of_day_index;
#ifdef OG_PBR
// Grecharged-directional-ambient ROOT-CAUSE FIX: real authored per-vertex TIE normal (world space),
// bound at location 3 by Tie3.cpp (same VAO as the base pass). Feeds the realtime-lighting smooth-
// normal path instead of the flat per-face screen-derivative normal.
layout (location = 3) in vec3 normal_in;
// Grecharged-pbr-realtime-fusion ROUND 22: the per-vertex MikkTSpace tangent (xyz = world tangent,
// w = handedness) was ALREADY bound at attribute location 5 on the TIE VAO (Tie3.cpp binds the
// tangent_buffer there for the whole tree, and the wind pass draws from that same VAO) — this
// shader simply never declared it, which is why the wind foliage had no tangent frame and hence no
// PBR material path. Declaring it costs nothing when PBR is off; an unbound location 5 reads
// (0,0,0,1), which the fused chunk detects as degenerate and answers with the CONTINUOUS
// normal-derived basis (never a screen-space derivative frame).
layout (location = 5) in vec4 tangent_in;
#endif

uniform vec4 hvdf_offset;
uniform mat4 camera;
uniform float fog_constant;
uniform float fog_min;
uniform float fog_max;
// A36: Wx1 2D LUT instead of 1D — Tie3.cpp uploads the time-of-day colors as a
// Wx1 GL_TEXTURE_2D (shared with the TFRAG3 path). texelFetch(ivec2(i,0)) is
// texel-exact on desktop GL and required on GLES (no sampler1D).
uniform sampler2D tex_T10; // note, sampled in the vertex shader on purpose.
uniform int decal;
// foliage-wind (owner 2026-09-03) : LE FREMISSEMENT DE FEUILLE du chemin VENT (les palmiers que ND
// anime deja). La flexion de couronne, elle, est un CISAILLEMENT de la matrice d'instance calcule
// sur CPU par la loi partagee (foliage_wind::breeze_offset, jumelle de breeze.glsl) ; ici ne vit
// que le terme rapide, par sommet, avec les MEMES raies (1,40 et 2,13 Hz) et le MEME poids de
// hauteur que les deux autres chemins (FoliageWindLaw.h : tiers du bas rigide, smoothstep^2).
// position_in est LOCAL AU PROTOTYPE (Tie3::render_tree_wind fournit la matrice d'instance dans
// `camera`) : `position_in.y / u_fw_height` est donc la hauteur relative du sommet dans SA plante,
// et length(position_in.xz) sa portee depuis l'axe du tronc (0 sur le tronc, max au bout des
// palmes). STRICTEMENT HORIZONTAL : l'ancien ballant vertical en quadrature (« flottaison ») est
// retire — c'est lui, avec la phase spatiale des buissons, qui lisait comme « sous l'eau ».
// u_fw_amp == 0.0 => option ETEINTE => le bloc est saute et le chemin de sommet stock tourne.
uniform float u_fw_amp;     // amplitude du fremissement en UNITES LOCALES du prototype (0 = off) ;
                            // porte deja bend x taille x flutter x gain de rafale (CPU)
uniform float u_fw_time;    // horloge de brise, secondes (figee en pause)
uniform float u_fw_phase;   // phase propre de l'instance, dans [0, 1)
uniform float u_fw_height;  // hauteur LOCALE du prototype (plus haut sommet), unites locales
#ifdef OG_PBR
uniform vec4 cam_trans;
// Grecharged-lightprobes PLAYTEST#1 #4: the LOCAL probe SH is evaluated PER-PIXEL in the fragment
// shader (see tie_wind.frag rt_probe_sh) from the interpolated v_world — the old per-vertex eval
// showed the ~4 m probe-cell pattern and shimmered under tfrag/tie LOD vertex morphing.
#endif

out vec4 fragment_color;
out vec3 tex_coord;
out float fogginess;
#ifdef OG_PBR
out vec3 v_fringe_rel;
// Grecharged-lightprobes: absolute world position (GOAL game units) for probe lookup.
out vec3 v_world;
out vec3 v_normal;  // Grecharged-directional-ambient: smooth per-vertex world normal (root-cause fix)
// ROUND 22: per-vertex tangent -> the continuous PBR TBN in the fragment (mirrors tfrag3.vert).
out vec4 v_tangent;
#endif

void main() {
  // Grecharged-foliage-wind2: frond flutter (see the uniform block above). Only the projected
  // position uses the fluttered vertex; v_world / v_fringe_rel below stay on the authored position
  // so nothing in the PBR/probe path shifts with the breeze.
  vec3 lpos = position_in;
  if (u_fw_amp > 0.0 && u_fw_height > 0.0) {
    // le poids de hauteur de FoliageWindLaw.h : nul sous 30 % de la plante, smoothstep^2 au-dessus
    float h = position_in.y / u_fw_height;
    float w = 0.0;
    if (h > 0.30) {
      float u = min((h - 0.30) / 0.70, 1.0);
      float s = u * u * (3.0 - 2.0 * u);
      w = s * s;
    }
    // la portee depuis l'axe du tronc, plafonnee a 4 m (une vraie palme) : le tronc ne fremit pas,
    // et un prototype dont la geometrie s'etale loin de son origine (palm-01.mb, 23 m) ne projette
    // pas ses sommets a 3 m de cote.
    float reach = min(length(position_in.xz), 4.0 * 4096.0) * (1.0 / (4.0 * 4096.0));
    w *= reach;
    // les deux raies du fremissement, la phase ne variant qu'avec le poids (donc la hauteur dans
    // la plante), jamais avec la position monde — breeze.glsl, regle (1)
    float lf1 = sin(u_fw_time * 8.7965 + u_fw_phase * 12.566 + w * 2.9);
    float lf2 = sin(u_fw_time * 13.4035 + u_fw_phase * 7.3 + w * 4.1 + 1.3);
    // axes LOCAUX du prototype : un fremissement de feuille n'a pas de cap lisible
    lpos.x += (0.62 * lf1 + 0.38 * lf2) * u_fw_amp * w;
    lpos.z += (lf2 * 0.45) * u_fw_amp * w;
  }
  vec4 transformed = -camera[3];
  transformed -= camera[0] * lpos.x;
  transformed -= camera[1] * lpos.y;
  transformed -= camera[2] * lpos.z;
#ifdef OG_PBR
  v_fringe_rel = (position_in - cam_trans.xyz) * (1.0 / 4096.0);
  v_world = position_in;                 // Grecharged-lightprobes: world pos for PER-PIXEL probe lookup
  v_normal = normal_in;  // world-space authored TIE normal (wind sways position; base normal is fine)
  v_tangent = tangent_in;  // ROUND 22: continuous per-vertex tangent for the fused PBR TBN
#endif
  float Q = fog_constant / transformed.w;

  fogginess = 255.0 - clamp(-transformed.w + hvdf_offset.w, fog_min, fog_max);

  // perspective divide!
  transformed.xyz *= Q;
  // offset
  transformed.xyz += hvdf_offset.xyz;
  // correct xy offset
  transformed.xy -= (2048.);
  // correct z scale
  transformed.z /= (8388608.0);
  transformed.z -= 1.0;
  // correct xy scale
  transformed.x /= (256.0);
  transformed.y /= -(128.0);
  // hack
  transformed.xyz *= transformed.w;
  // scissoring area adjust
  transformed.y *= SCISSOR_ADJUST * HEIGHT_SCALE;
  gl_Position = transformed;

  // time of day lookup
  fragment_color = texelFetch(tex_T10, ivec2(time_of_day_index, 0), 0);
  // color adjustment
  fragment_color *= 2.0;
  fragment_color.a *= 2.0;

  if (decal == 1) {
    // tfrag/tie always use TCC=RGB, so even with decal, alpha comes from fragment.
    fragment_color.xyz = vec3(1.0, 1.0, 1.0);
  }

  tex_coord = tex_coord_in;
}