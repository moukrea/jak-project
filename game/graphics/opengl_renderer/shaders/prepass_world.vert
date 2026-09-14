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
        float heightMul;
        vec3 trample;
        float debug_contact = 0.0;
        vegetation_contact(anchor.xyz, anchor.w, 0, heightMul, trample, debug_contact);
        float dy = position_in.y - anchor.y;
        wpos.y += dy * (heightMul - 1.0);
        wpos += trample * (dy / anchor.w);
      }
    }
    return wpos;
  }
  return position_in;
}

void main() {
  vec3 vert = prepass_world_position() - cam_trans.xyz;
  vec4 transformed = -pc_camera[3];
  transformed.w = 0.0;
  transformed -= pc_camera[0] * vert.x;
  transformed -= pc_camera[1] * vert.y;
  transformed -= pc_camera[2] * vert.z;
  transformed.y *= SCISSOR_ADJUST * HEIGHT_SCALE;
  gl_Position = transformed;
  tex_coord = tex_coord_in;
}
