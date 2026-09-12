#pragma once

// shade_proof — COMBIEN DE MODELES D'OMBRAGE LE MONDE COMPILE-T-IL VRAIMENT ?
//
// POURQUOI. SPEC-refonte-lumiere.md §2.3 : le decor n'a pas un modele d'eclairage, il en a
// cinq, ecrits en quatre quasi-copies (tfrag3, etie_base, tie_wind, shrub). L'item
// `lighting-unify` les ramene a UN SEUL texte, un chunk partage inclus par tous les hotes.
// La porte de l'item est `shade_variants == 1`.
//
// CE QUE LA GRANDEUR NE DOIT PAS ETRE. Un booleen « j'ai fait le refactor » publie par le
// refactor lui-meme serait un miroir : une porte calculee sur ses propres variables est
// infalsifiable. `shade_variants` est donc mesure sur LE TEXTE QUE LE PILOTE COMPILE, releve
// dans `Shader::build` apres l'expansion des `#include`, la substitution des jetons et
// l'injection de `OG_PBR` — c'est-a-dire l'octet exact envoye a `glShaderSource`.
//
// COMMENT. Chaque etage fragment porte une region delimitee par deux marqueurs :
//
//     // @shade-model-begin
//     ... le modele d'ombrage ...
//     // @shade-model-end
//
// Le module concatene TOUTES les regions marquees d'un programme, en prend une empreinte
// FNV-1a 64, et compte les empreintes DISTINCTES sur l'ensemble des programmes. Avant l'item,
// les marqueurs entourent le corps propre de chaque hote et les empreintes different : la
// mesure rend le nombre de copies. Apres, les marqueurs vivent dans le chunk partage et tous
// les hotes rendent la MEME empreinte : la mesure rend 1. Le meme instrument, non modifie,
// mesure les deux etats — c'est ce qui empeche le « avant » d'etre une affirmation.
//
// LES TROIS CLES QUI EMPECHENT LE 1 DE MENTIR. Retirer les marqueurs de trois shaders sur
// quatre rendrait aussi `shade_variants == 1`. Trois grandeurs ferment ce chemin, et elles
// sont lues dans le meme texte :
//
//   `shade_hosts`              programmes qui PORTENT une region marquee. Un 1 obtenu en
//                              n'en marquant qu'un seul se lit tout de suite.
//   `shade_hosts_missing`      programmes dont le texte lit une des quatre portes d'ombrage
//                              (`u_rt_light_on`, `u_pbr_mode`, `u_rt_probe_on`,
//                              `u_pbr_shadow_on`) et qui NE portent aucune region marquee.
//                              Un shader monde qui garde son propre eclairage y tombe.
//   `shade_gate_reads_outside` occurrences de ces quatre portes lues HORS de toute region
//                              marquee, commentaires exclus. C'est la vraie definition de
//                              « un seul modele » : apres l'item, aucun hote ne decide plus
//                              rien de l'eclairage dans son propre texte.
//
// `hits` = draws monde partis avec un programme qui porte le modele. Compte AU SITE DU GESTE
// (le draw), pas au site du predicat, et seulement quand la feature est armee : c'est ce qui
// rend le bras `--off` lisible.

#include <cstdint>
#include <string>

namespace shade_proof {

// Le harnais mesure-t-il CET item et est-il arme ? `armed_for("lighting-unify")`, jamais
// `armed()` : un `armed()` global desarmerait du meme coup le correctif d'un autre item.
bool active();

// Releve du texte REELLEMENT compile, appele depuis `Shader::build` juste avant
// `glShaderSource` de l'etage fragment. `name` est le nom du programme.
void note_fragment_source(const std::string& name, const std::string& expanded_frag_src);

// Le programme GL qui vient d'etre lie a ce nom (`Shader::build`, apres `glLinkProgram`).
// Sert a relier une empreinte de texte a l'objet que les draws vont utiliser.
void note_program_linked(const std::string& name, unsigned gl_program);

// `Shader::activate()` vient de poser ce programme. Suivi sans requete synchrone ; verifie
// une fois par image contre `GL_CURRENT_PROGRAM` (voir `shade_prog_track_mismatch`).
void note_program_bound(unsigned gl_program);

// Un draw monde PORTEUR DE COULEUR vient de partir. Les passes de profondeur en sont exclues :
// elles ne produisent aucune radiance et ne passent pas par le modele.
void note_world_draw();

// Fin d'image : verification du suivi de programme, puis publication.
void frame_end();

}  // namespace shade_proof
