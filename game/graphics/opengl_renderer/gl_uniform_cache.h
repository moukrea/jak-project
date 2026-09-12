#pragma once
// gl_uniform_cache — LE CACHE DES EMPLACEMENTS D'UNIFORMES (item `lighting-ao-indirect`,
// amendement perf du 2026-09-09, SPEC-refonte-lumiere §4.3).
//
// LE DEFAUT. `first_tfrag_draw_setup` resolvait ~91 noms par `glGetUniformLocation` a CHAQUE
// appel, et il est appele par arbre et par categorie : ~2 600 a 3 000 recherches de chaine dans
// le pilote par image, sur les cinq hotes du decor (tfrag3, etie_base, tie_wind, shrub, hfrag).
// Un emplacement d'uniforme est une constante du programme lie : il ne change qu'a l'edition de
// liens. On le resout UNE fois par (programme, nom) et on le garde.
//
// LA CLE est l'adresse du litteral de chaine, verifiee par son contenu : tous les appelants
// passent des litteraux, et deux litteraux de meme texte ne coutent qu'une entree de plus.
// `invalidate(program)` est appele par Shader.cpp a chaque edition de liens : un identifiant GL
// reutilise apres suppression ne peut pas servir un emplacement perime.
//
// LA PORTE (SPEC §4.3) : `uniform_lookups_per_frame` — le nombre d'appels REELS a
// glGetUniformLocation passes par ce cache pendant l'image precedente ; 0 en regime etabli.
#include <cstdint>

#include "third-party/glad/include/glad/glad.h"

namespace glu {

// L'emplacement de `name` dans `program`, resolu une seule fois. -1 si absent (garde aussi).
GLint loc(GLuint program, const char* name);

// A l'edition de liens d'un programme (Shader.cpp) : ses entrees sont oubliees.
void invalidate(GLuint program);

// LE RECENSEMENT DES UNIFORMES SANS LECTEUR (item `gl-uniforms-dead-seven`).
// -------------------------------------------------------------------------
// Sept reglages d'eclairage partaient a chaque image vers des uniformes qu'AUCUN shader ne lit.
// Un `grep` du nom ne pouvait pas le dire : six des sept etaient DECLARES dans un shader, et un
// uniforme declare mais jamais lu est retire par le compilateur GLSL — il n'a pas d'emplacement.
// La seule autorite sur « ce shader lit-il ce nom » est donc le PILOTE, pas le texte.
//
// Ce module est deja le passage OBLIGE de toute poussee d'uniforme du decor (`lgt_*` et les
// appels nus passent tous par `loc()`), ce qui en fait le seul endroit ou compter AU POINT
// D'APPEL : une liste de sites connus ne prouverait que la liste.
//
// La mesure : pour chaque nom vu, on interroge TOUS les programmes lies (`note_program`) ; un
// nom dont aucun programme ne rend d'emplacement n'a aucun lecteur dans l'arbre. `readers` est
// donc une grandeur produite par le compilateur GLSL, pas par nous.
//
// Publie sous `AUTOPORT_FEATURE=gl-uniforms-dead-seven` : `dead_uniform_pushes` (la porte),
// ses denominateurs, la LISTE des noms morts, le recensement nomme des sept, et deux temoins
// semes — un nom mort fabrique et un nom vivant certain — sans lesquels un zero obtenu parce
// que l'instrument ne tourne pas serait indistinguable d'un zero obtenu parce qu'il n'y a plus
// rien a compter.

// Un programme vient d'etre lie (Shader.cpp). Le recensement l'interrogera pour chaque nom.
void note_program(GLuint program);

// Une fois par image (tete de dispatch des deux renderers) : bascule et publie les compteurs.
void frame_begin();

}  // namespace glu
