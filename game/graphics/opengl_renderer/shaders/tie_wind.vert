#version 410 core

layout (location = 0) in vec3 position_in;
layout (location = 1) in vec3 tex_coord_in;
layout (location = 2) in int time_of_day_index;
#ifdef OG_PBR
// Grecharged-directional-ambient ROOT-CAUSE FIX: real authored per-vertex TIE normal (world space),
// bound at location 3 by Tie3.cpp (same VAO as the base pass). Feeds the realtime-lighting smooth-
// normal path instead of the flat per-face screen-derivative normal.
layout (location = 3) in vec3 normal_in;
// lighting-legacy-purge (2026-09-12) : l'attribut de tangente MikkTSpace (location 5) et son
// varying ont ete RETIRES avec la pile de matiere, leur unique consommateur. Le C++ continue de
// lier l'attribut : un attribut lie que le shader ne declare plus est simplement INACTIF, c'est
// legal en GL. Le format fr3 et TFRAG3_VERSION sont INCHANGES — on lit un champ qu'on n'utilise
// plus, les fr3 livres restent valides.
#endif

#include "frame_ubo.glsl"
uniform mat4 u_inst_camera;
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
// `u_inst_camera`) : `position_in.y / u_fw_height` est donc la hauteur relative du sommet dans SA plante,
// et length(position_in.xz) sa portee depuis l'axe du tronc (0 sur le tronc, max au bout des
// palmes). STRICTEMENT HORIZONTAL : l'ancien ballant vertical en quadrature (« flottaison ») est
// retire — c'est lui, avec la phase spatiale des buissons, qui lisait comme « sous l'eau ».
// u_fw_amp == 0.0 => option ETEINTE => le bloc est saute et le chemin de sommet stock tourne.
uniform float u_fw_amp;     // amplitude du fremissement en UNITES LOCALES du prototype (0 = off) ;
                            // porte deja bend x taille x flutter x gain de rafale (CPU)
uniform float u_fw_time;    // horloge de brise, secondes (figee en pause)
uniform float u_fw_phase;   // phase propre de l'instance, dans [0, 1)
uniform float u_fw_height;  // hauteur LOCALE du prototype (plus haut sommet), unites locales
// Essai 11 (owner 2026-09-04 : « ça twitch autant côté feuilles que le tronc »). La flexion de
// couronne AJOUTEE par la brise n'est plus un cisaillement de la matrice d'instance (lineaire du
// pied a la cime : le tronc bougeait autant, en proportion, que les palmes). Elle arrive ici, par
// instance, en UNITES LOCALES du prototype (le CPU l'a calculee en monde par la loi partagee puis
// ramenee dans le repere de l'instance), et elle est multipliee par le MEME poids de hauteur que les
// deux autres chemins : 30 % du bas rigides, smoothstep^2 au-dessus. Le tronc ne bouge plus ; ce
// qui reste sur lui est l'appui lent de ND (do_wind_math), qui est du stock. 0 = rien d'ajoute.
uniform vec2 u_fw_bend;
// ESSAI 16 (owner 2026-09-06 : « Le feuilles de palmiers meriteraient de bouger plus a leur
// extremites qu'a leur bases ») — LA COORDONNEE D'ELEMENT DU CHEMIN VENT. Le poids de hauteur
// ci-dessus donne le meme deplacement a l'attache d'une palme et a sa pointe (elles sont a la meme
// hauteur, souvent la pointe est PLUS BASSE) : la palme se deplacait d'un bloc. `q` est la portee
// du sommet depuis l'axe du tronc, ramenee a l'etendue de portee de la COURONNE de SA plante —
// exactement ce que le depaqueteur calcule pour le TIE statique (FoliageWindLaw.h::tie_shape).
// x = portee minimale de la couronne, y = son etendue (0 => `q` vaut 0, la rampe rend son plancher
// et on retrouve la loi d'avant l'essai 16 : une plante sans couronne etalee ne peut pas whipper).
// `u_fw_bend` arrive DEJA divise par le maximum de forme du prototype (Tie3.cpp), donc c'est la
// POINTE qui recoit la flexion de couronne de la loi, comme sur le chemin statique.
uniform vec2 u_fw_reach;
// = foliage_law::kTipFloor / kTipPow
#define FW_TIP_FLOOR 0.06
#define FW_TIP_POW 1.6
#ifdef OG_PBR
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
#endif

void main() {
  // Grecharged-foliage-wind2: frond flutter (see the uniform block above). Only the projected
  // position uses the fluttered vertex; v_world / v_fringe_rel below stay on the authored position
  // so nothing in the PBR/probe path shifts with the breeze.
  vec3 lpos = position_in;
  if (u_fw_height > 0.0 && (u_fw_amp > 0.0 || u_fw_bend.x != 0.0 || u_fw_bend.y != 0.0)) {
    // la PORTE DE SOL de FoliageWindLaw.h : nulle sous 10 % de la plante, smoothstep jusqu'a 30 %,
    // 1 au-dessus. Elle ne fait que figer le pied ; la reponse, c'est la rampe d'extremite.
    float h = position_in.y / u_fw_height;
    float w = 0.0;
    if (h > 0.10) {
      float u = min((h - 0.10) / 0.20, 1.0);
      w = u * u * (3.0 - 2.0 * u);
    }
    // ESSAI 16 : la rampe d'extremite. `q` = 0 a l'attache (l'axe du tronc), 1 a la pointe.
    // Elle multiplie la flexion ET le fremissement : un seul poids pour toute la loi, comme sur le
    // chemin statique ou l'attribut 7 les porte tous les deux.
    float q = u_fw_reach.y > 0.0
                  ? clamp((length(position_in.xz) - u_fw_reach.x) / u_fw_reach.y, 0.0, 1.0)
                  : 0.0;
    w *= FW_TIP_FLOOR + (1.0 - FW_TIP_FLOOR) * pow(q, FW_TIP_POW);
    // la flexion de la brise, par ce poids : la pointe fouette, l'attache suit a peine, le tronc non
    lpos.x += u_fw_bend.x * w;
    lpos.z += u_fw_bend.y * w;
    // les deux raies du fremissement, la phase ne variant qu'avec le poids (donc la hauteur dans
    // la plante), jamais avec la position monde — breeze.glsl, regle (1)
    float lf1 = sin(u_fw_time * 8.7965 + u_fw_phase * 12.566 + w * 2.9);
    float lf2 = sin(u_fw_time * 13.4035 + u_fw_phase * 7.3 + w * 4.1 + 1.3);
    // axes LOCAUX du prototype : un fremissement de feuille n'a pas de cap lisible
    lpos.x += (0.62 * lf1 + 0.38 * lf2) * u_fw_amp * w;
    lpos.z += (lf2 * 0.45) * u_fw_amp * w;
  }
  vec4 transformed = -u_inst_camera[3];
  transformed -= u_inst_camera[0] * lpos.x;
  transformed -= u_inst_camera[1] * lpos.y;
  transformed -= u_inst_camera[2] * lpos.z;
#ifdef OG_PBR
  v_fringe_rel = (position_in - cam_trans.xyz) * (1.0 / 4096.0);
  v_world = position_in;                 // Grecharged-lightprobes: world pos for PER-PIXEL probe lookup
  v_normal = normal_in;  // world-space authored TIE normal (wind sways position; base normal is fine)
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