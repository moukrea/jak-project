#pragma once

// hdr — LA CHAINE HDR ET SON RECENSEMENT (item `lighting-hdr`, SPEC-refonte-lumiere §4.5).
//
// LE DEFAUT. §2.3 cause 6 : `make_fbo(..., GL_RGBA8, ...)` partout, et un genou de compression
// ecrit A LA MAIN dans chaque chemin d'ombrage (`RT_KNEE` dans pbr_fused.glsl, `MM_KNEE` et
// une courbe ACES dans pbr_modern.glsl). Aucune marge au-dessus de 1 : un eclat speculaire,
// un bloom, une adaptation d'exposition n'ont pas la place d'exister, et « combien de fois
// l'image est-elle compressee avant l'ecran » n'a pas de reponse.
//
// CE QUE L'ITEM LIVRE. Le tampon de scene passe en RGBA16F (repli declare et mesure), les
// genoux quittent les shaders, et UNE seule compression de plage subsiste sur le chemin
// d'affichage : le programme `tonemap`, tire depuis un seul endroit du code.
//
// LA GRANDEUR DE LA PORTE, ET POURQUOI ELLE N'EST PAS UN MIROIR.
// -------------------------------------------------------------
// `tonemap_sites` n'est pas un booleen « j'ai fait le refactor » publie par le refactor. C'est
// une SOMME de trois recensements independants, chacun publie a cote :
//
//   `tonemap_sites_explicit`  nombre d'emplacements de code DISTINCTS (fichier:ligne) d'ou le
//                             programme de tone map a REELLEMENT ete tire pendant la course.
//                             Deux appels a `tonemap_draw` depuis deux endroits => 2.
//   `tonemap_sites_shader`    nombre de programmes fragment, AUTRES que `tonemap`, dont le
//                             texte REELLEMENT COMPILE (releve dans `Shader::build`, apres
//                             l'expansion des `#include`) porte encore une compression de
//                             plage. Oublier un `RT_KNEE` le fait monter.
//   `tonemap_sites_implicit`  nombre d'emplacements DISTINCTS du chemin d'affichage ou une
//                             couleur de scene flottante a ete recopiee dans une cible 8 bits
//                             pendant la course. Une conversion de format est une compression
//                             de plage que personne n'a ecrite : elle compte comme un site.
//
// CE QUI N'EST PAS COMPTE, ET POURQUOI. L'encodage `pow(x, 1/2.2)` des chemins d'ombrage
// RECHARGED n'est PAS une compression de plage : c'est une bijection monotone de [0,+inf) sur
// [0,+inf), sans plafond et sans perte, et c'est l'encodage COMMUN du tampon — les renderers
// d'origine (ciel, merc, sprites, eau) y ecrivent deja des couleurs d'affichage, et le melange
// PS2 est defini dans cet espace. Le retirer d'un seul chemin melangerait deux encodages dans
// le meme tampon. Il est neanmoins recense et publie sous `hdr_oetf_progs` : rien n'est cache.
// De meme, les lectures de la scene faites par les EFFETS (AO, glow, distorsion, capture de
// fond de menu) sont publiees sous `hdr_aux_clamped_reads`, avec leur denominateur. La copie
// couleur de distorsion, recomposee dans la scene, alimente aussi le verdict d'ecretage
// intermediaire ; les lectures de profondeur ou les masques ne lui sont pas assimiles.

#include <cstdint>
#include <string>

#include "game/graphics/pipelines/opengl.h"

class Shader;

namespace hdr {

// -------------------------------------------------------------------------------- regime ----

// La chaine HDR est-elle active pour cette image ? Master RECHARGED arme, reglage
// `recharged_hdr` a vrai, et feature ARMEE (`armed_for("lighting-hdr")` — le bras `--off` du
// harnais eteint donc la chaine POUR DE VRAI : l'ablation est causale, pas seulement muette).
// Le mode ORIGINE (master OFF) ne passe JAMAIS par ici.
bool chain_active();

// Le format d'attachement couleur demande pour le tampon de scene, apres l'echelle de repli.
// GL_RGBA16F -> GL_R11F_G11F_B10F -> GL_RGBA8 (§4.5).
GLenum scene_color_format();

// Le FBO de scene vient d'etre construit avec ce format : complet ou non. Fait descendre
// l'echelle de repli d'un cran quand il ne l'est pas. Retourne vrai s'il faut re-essayer.
bool note_scene_fbo_result(GLenum requested, bool complete);

bool format_is_float(GLenum fmt);
const char* format_name(GLenum fmt);

// ------------------------------------------------------------------------- le site unique ----

// Tire le quad plein ecran de tone map : `src_tex` -> `dst_fbo`. `site` nomme l'emplacement de
// code appelant (`__FILE__ ":" __LINE__`) ; c'est LUI qui est recense, pas un compteur maison.
// Compte un `note_hit()` par image tone-mappee. Retourne faux si le programme n'est pas
// utilisable — l'appelant doit alors retomber sur son blit, que le recensement verra.
bool tonemap_draw(Shader& shader,
                  const char* site,
                  GLuint src_tex,
                  GLuint dst_fbo,
                  int dst_w,
                  int dst_h,
                  GLuint vao,
                  GLuint vbo);

// ---------------------------------------------------------------------------- recensement ----

// Releve du texte fragment TEL QUE LE PILOTE LE RECOIT (`Shader::build`, avant glShaderSource).
void note_fragment_source(const std::string& name, const std::string& expanded_frag_src);

// Une copie de couleur de scene SUR LE CHEMIN D'AFFICHAGE vient d'avoir lieu. Compte un site
// quand la source est flottante et la destination ne l'est pas.
void note_display_copy(const char* site, GLenum src_fmt, GLenum dst_fmt);

// Une lecture de la scene par un EFFET (hors chemin d'affichage). Publiee a part.
void note_aux_scene_read(const char* site, GLenum src_fmt, GLenum dst_fmt);

// Mesure de la marge : echantillonne le tampon de scene et compte les pixels dont un canal
// depasse 1,0. Ne tourne QUE lorsque le harnais mesure cet item, et une image sur N.
void probe_scene(GLuint scene_fbo, int w, int h, GLenum fmt);

// Fin d'image : publication. A appeler depuis LES DEUX renderers (bureau et Android).
void frame_end();

}  // namespace hdr
