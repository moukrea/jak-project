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

// Une fois par image (tete de dispatch des deux renderers) : bascule et publie les compteurs.
void frame_begin();

}  // namespace glu
