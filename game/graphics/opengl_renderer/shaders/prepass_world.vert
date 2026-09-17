#version 410 core

// lighting-ao-indirect (SPEC-refonte-lumiere §4.6) : LA PREPASSE DE PROFONDEUR vue camera.
// Meme entree que pbr_depth.vert (attribut 0 = position MONDE absolue, unites de jeu) et
// EXACTEMENT la projection de tfrag3.vert (pc_camera + cam_trans + SCISSOR_ADJUST * HEIGHT_SCALE,
// tokens substitues a l'execution comme partout) : la profondeur ecrite est celle que la passe
// principale ecrira pour la meme geometrie, a l'arrondi pres.
//
// REFUS OWNER DU 2026-09-10 (b) : « sur les shrubs, ca ignore la partie transparente et y applique
// quand meme l'occlusion ambiante dessus ». La prepasse portait un fragment shader vide : les texels
// TRANSPARENTS du feuillage a decoupe ecrivaient de la profondeur, l'estimateur les prenait pour des
// occluders pleins, et l'ombre d'AO du quad flottait au-dessus des brins. SPEC §4.6 le disait deja :
// « pas de texture sauf pour l'alpha-test du feuillage (qui doit y participer) ». D'ou la coordonnee
// de texture, sortie ici.
//
// REFUS OWNER DU 2026-09-13 (i) : « les shrubs qui bougent avec le vent... Leur AO reste a la place
// initiale [...] et ca aussi c'est un desastre ». C'est CE fichier qui le produisait : il lisait
// `position_in` BRUTE, avec un commentaire « Pas de vent » pour toute justification, alors que la
// passe COULEUR deplace le meme sommet — shrub.vert:73-91 (balancement partage + ressort natif de
// ND + contact vegetation), tfrag3.vert:66 pour le TIE statique. Une profondeur non deplacee pose
// l'occlusion la ou le feuillage N'EST PLUS : l'ombre reste sur place pendant que la plante bouge.
// Le deplacement est donc rejoue ICI, par le MEME chunk et sous les MEMES uniformes ; c'est
// `prepass::sway_shrub` / `sway_tie` / `sway_none` (PrePass.cpp) qui les pousse, appeles par les
// trois contributeurs au debut de leur `draw_depth_prepass`.
//
// LA LOCATION 1 EST LA MEME POUR LES TROIS FAMILLES : tfrag3.vert:4, shrub.vert:4 et le TIE (qui
// partage tfrag3.vert) declarent tous `layout (location = 1) in vec3 tex_coord_in`. Le VAO du shrub
// n'y pousse que deux flottants (Shrub.cpp:282-288) — shrub.vert le declare deja en vec3 et vit
// avec, la troisieme composante n'est jamais lue.
//
// LES ATTRIBUTS DE BALANCEMENT NE SONT PAS LIES PARTOUT, ET C'EST VOULU : le VAO du TFRAG n'active
// ni 7, ni 8, ni 9, ni 10 (TFragment.cpp:397-440), celui du TIE n'active pas 9 (Tie3.cpp:584-590),
// celui du shrub pas 10 (Shrub.cpp:299-307). Un attribut desactive rend la VALEUR GENERIQUE
// courante, que `run_prepass` met a zero au debut de chaque passe — le meme double verrou que
// `first_tfrag_draw_setup` pose pour la passe couleur (background_common.cpp:1613-1628).
#define TIE_CONTACT
#include "tie_sway.glsl"

layout (location = 0) in vec3 position_in;
layout (location = 1) in vec3 tex_coord_in;

uniform vec4 cam_trans;
uniform mat4 pc_camera;

// La famille de la plage en cours : 0 = aucun deplacement (TFRAG), 1 = shrub, 2 = TIE statique.
// Deux familles, deux lois : le shrub porte SON ressort natif et SON ancre de contact dans
// tex_T18 (shrub.vert:73-91), le TIE passe par `tie_contact_apply` et l'attribut 10.
uniform int u_pre_kind;
// LE TEMOIN. 0 rejoue EXACTEMENT la prepasse d'avant ce correctif — position brute, aucun
// deplacement — pour que l'ecart avec la scene soit MESURE dans la MEME image et la MEME scene,
// jamais suppose (PrePass.cpp, `ao_geom_*` / `ao_sway_gap_px`). Vaut 1 sur le chemin livre.
uniform int u_pre_sway_on;

// (A1) L'ECHELLE DE LA COORDONNEE DE TEXTURE, ET ELLE DEPEND DE LA FAMILLE. Les deux passes
// couleur ne sortent PAS la meme unite : shrub.vert:125-126 fait `tex_coord = tex_coord_in;` PUIS
// `tex_coord.xy /= 4096.0;`, tandis que tfrag3.vert:95 — partage par le TFRAG **et** le TIE —
// fait `tex_coord = tex_coord_in;` sans division. Ce fichier sortait la coordonnee BRUTE pour les
// trois familles : sur un draw de SHRUB, l'alpha-test de prepass_world.frag:35 echantillonnait
// donc `fract(uv * 4096)`, c'est-a-dire un texel ARBITRAIRE de la texture — pas celui du
// fragment. L'argument « ce test est CONSERVATEUR par construction » ecrit en tete de
// prepass_world.frag etait VIDE sur le shrub : il ne retirait pas ce que la passe couleur retire,
// il retirait au hasard. `PrePass.cpp` (`sway_reset`) pousse 1/4096 pour le shrub et 1 pour
// tfrag/TIE, au MEME endroit que `u_pre_kind` : il est impossible d'en poser un sans l'autre.
// Le bras TEMOIN (u_pre_sway_on == 0) recoit 1 meme sur le shrub : il doit rester EXACTEMENT la
// prepasse d'avant cet essai, pour que l'ecart soit mesure dans la MEME image et la MEME scene.
uniform float u_pre_uv_scale;

// (A4) LE MODE DE PROJECTION. 0 = la projection de tfrag3.vert, inchangee. 1 = celle de
// `etie_base.vert:64-83`, recopiee ligne pour ligne. La passe COULEUR des draws NORMAL_ENVMAP du
// TIE n'utilise pas tfrag3.vert mais etie_base.vert et SON pipeline (uniformes `persp0`,
// `persp1`, `cam_no_persp`, poses par `init_etie_cam_uniforms`, Tie3.cpp:1027-1050) — le
// commentaire Tie3.cpp:1187-1190 dit pourquoi : « if we use envmap, use the envmap-style math for
// the base draw to avoid rounding issue ». La prepasse dessinait ces MEMES plages
// (`prepass_ranges_env`, Tie3.cpp:1284) avec l'autre arithmetique : deux projections censees
// rendre le meme z ne donnent pas le meme bit, et ca se mesure — `ao_geom_tie_gap64_px=192`,
// IDENTIQUE dans les deux bras (donc rien a voir avec le deplacement de sommet).
uniform int u_pre_etie;
// Declares comme dans etie_base.vert:41-43. Inertes quand u_pre_etie == 0.
uniform vec4 persp0;
uniform vec4 persp1;
uniform mat4 cam_no_persp;

// shrub : ligne 0 de tex_T18 = l'etat du ressort natif par instance, ligne 1 = l'ancre de contact.
// Jumeau ligne pour ligne de shrub.vert:73-91.
layout (location = 9) in int shrub_inst_in;
uniform sampler2D tex_T18;
uniform int u_shrub_native_on;
uniform int u_shrub_contact_on;

out vec3 tex_coord;

vec3 prepass_world_position() {
  if (u_pre_sway_on == 0) {
    return position_in;
  }
  if (u_pre_kind == 2) {
    // TIE statique — tfrag3.vert:66, mot pour mot.
    return tie_contact_apply(position_in, tie_sway_apply(position_in, tie_sway_in));
  }
  if (u_pre_kind == 1) {
    // shrub — shrub.vert:73-91, mot pour mot.
    vec3 wpos = tie_sway_apply(position_in, tie_sway_in);
    if (u_shrub_native_on == 1 && tie_sway_in.x != 0.0) {
      vec4 nw = texelFetch(tex_T18, ivec2(shrub_inst_in, 0), 0);
      wpos.x += nw.x * (nw.z * tie_sway_in.x);
      wpos.z += nw.y * (nw.z * tie_sway_in.x);
    }
    if (u_shrub_contact_on == 1) {
      vec4 anchor = texelFetch(tex_T18, ivec2(shrub_inst_in, 1), 0);
      if (anchor.w > 0.0) {
        // essai 15 : LA BRANCHE `carried` ETAIT ABSENTE ICI. shrub.vert:86-102 lit la ligne 2
        // (plan d'attache) et, pour une instance PORTEE par un tronc, prend ce plan pour pivot
        // et SAUTE le bloc quand `dy <= 0` (sommets epingles). Ce fichier prenait sans condition
        // le sol pour pivot : deux passes, deux deplacements, sur les instances portees
        // (`village1/palmplant-base.mb`, 36 sur 37). La ligne 2 ne vaut autre chose que zero que
        // sous `shrub-trunk-contact` (Shrub.cpp:363) — la divergence est donc LATENTE aujourd'hui
        // et ce correctif ne se voit dans aucun compteur de cet item ; il empeche qu'elle
        // reapparaisse le jour ou cet item-la arme la ligne.
        vec4 attachment = texelFetch(tex_T18, ivec2(shrub_inst_in, 2), 0);
        bool carried = attachment.y > 0.0;
        float dy = carried ? max(0.0, position_in.y - attachment.x) : position_in.y - anchor.y;
        if (!carried || dy > 0.0) {
          float heightMul;
          vec3 trample;
          float debug_contact = 0.0;
          vegetation_contact(anchor.xyz, anchor.w, 0, heightMul, trample, debug_contact);
          wpos.y += dy * (heightMul - 1.0);
          wpos += trample * (dy / anchor.w);
        }
      }
    }
    return wpos;
  }
  return position_in;
}

void main() {
  vec3 wpos = prepass_world_position();
  if (u_pre_etie == 1) {
    // etie_base.vert:55-83, ligne pour ligne, sur la MEME position deplacee (la-bas
    // `position_sway`, ici `wpos`). Aucune constante n'est reecrite : c'est la seule facon
    // d'obtenir le meme bit de profondeur que la passe de base de l'envmap.
    vec4 vf17 = cam_no_persp[3];
    vf17 += cam_no_persp[0] * wpos.x;
    vf17 += cam_no_persp[1] * wpos.y;
    vf17 += cam_no_persp[2] * wpos.z;
    vec4 p_proj = vec4(persp1.x * vf17.x, persp1.y * vf17.y, persp1.z, persp1.w);
    p_proj += persp0 * vf17.z;

    float pQ = 1.f / p_proj.w;
    vec4 transformed = p_proj * pQ;
    transformed.w = p_proj.w;

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
  } else {
    vec3 vert = wpos - cam_trans.xyz;
    vec4 transformed = -pc_camera[3];
    transformed.w = 0.0;
    transformed -= pc_camera[0] * vert.x;
    transformed -= pc_camera[1] * vert.y;
    transformed -= pc_camera[2] * vert.z;
    transformed.y *= SCISSOR_ADJUST * HEIGHT_SCALE;
    gl_Position = transformed;
  }
  tex_coord = tex_coord_in;
  tex_coord.xy *= u_pre_uv_scale;
}
