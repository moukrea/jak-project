#pragma once
// prepass — LA PREPASSE DE PROFONDEUR ET L'AO QUI EN VIT (item `lighting-ao-indirect`,
// SPEC-refonte-lumiere §4.1 P1/P4, §4.6, §4.7).
//
// LE DEFAUT. L'occlusion ambiante composait sur l'image opaque FINALE (`ao_composite.frag`,
// blend GL_ZERO / GL_ONE_MINUS_SRC_COLOR, apres l'encodage gamma) : elle assombrissait AUSSI la
// lumiere directe, d'ou le masque de luminance — le symptome du mauvais emplacement, pas une
// protection. L'owner (2026-09-03) : « on l'a fait tout a la fin du rendu par dessus le reste
// plutot qu'en composant integral du rendu ».
//
// CE QUE CE MODULE FAIT. Au PREMIER passage de `update_render_state_from_pc_settings` de
// l'image — la camera de L'IMAGE COURANTE vient d'etre lue dans le DMA, aucun draw ombre n'a
// encore eu lieu (jak1 : bucket 6, apres le ciel et l'ocean lointain) — il redessine en
// profondeur seule la geometrie opaque STATIQUE des niveaux en service (tfrag, tie, shrub :
// les memes buffers statiques complets que la passe de profondeur soleil), dans un FBO qui lui
// appartient, avec la projection de `tfrag3.vert`. L'estimateur d'AO (inchange : SSAO/HBAO/
// GTAO + flou) lit CETTE profondeur et ecrit une texture R8. `shade.glsl` l'echantillonne par
// gl_FragCoord et la multiplie au SEUL terme indirect, avant le tone map. Le composite, la copie
// de scene et le masque de luminance n'existent plus.
//
// CE QUI N'EST PAS DANS LA PREPASSE, ET C'EST DIT : les acteurs (merc, item 9), les TIE a vent
// (instances a matrice, meme trou que la passe soleil), l'ocean, l'alpha, les particules.
//
// LA PREUVE. Sous mesure (`autoport_proof::feature_is("lighting-ao-indirect")`), une image sur
// N : `shade()` evalue son corps DEUX fois (AO reelle, AO = 1) et sort des drapeaux au lieu de
// la couleur ; les buckets monde marquent le stencil ; ce module relit couleur + stencil au
// bucket 30 et publie `ao_direct_leak_px`. L'attendu de la variation est `(ao_mul - 1) * base`,
// ou `base` est une ENTREE de l'ombrage et `ao_mul` une fonction fixe de l'echantillon : la
// porte compare la sortie REELLE du programme a une grandeur qu'il ne calcule pas lui-meme.
#include <cstdint>
#include <string>
#include <unordered_set>

#include "game/graphics/opengl_renderer/BucketRenderer.h"

#include "third-party/glad/include/glad/glad.h"

struct GoalBackgroundCameraData;
class AmbientOcclusionPass;
class ShaderLibrary;

namespace prepass {

// Un renderer du decor qui sait redessiner sa geometrie OPAQUE STATIQUE en profondeur seule.
// S'enregistre a la construction, se retire a la destruction : les hotes (TFragment, Tie3,
// Shrub) n'ont rien d'autre a faire que d'en heriter.
class DepthContributor {
 public:
  DepthContributor();
  virtual ~DepthContributor();
  DepthContributor(const DepthContributor&) = delete;
  DepthContributor& operator=(const DepthContributor&) = delete;

  // Prefixe de dedoublonnage ("tfrag", "tie", "shrub") : plusieurs instances d'un meme
  // renderer cachent le meme niveau (un bucket par categorie) ; une seule dessine.
  virtual const char* prepass_kind() const = 0;
  // Le niveau que cette instance a en cache ("" si aucun).
  virtual const std::string& prepass_level_name() const = 0;
  // Dessine. Le programme PREPASS_WORLD est ACTIF, ses uniformes camera poses, le FBO et le
  // viewport de la prepasse lies, GL_DEPTH_TEST on / GEQUAL / mask on, cull et scissor off.
  // L'implementation lie son VAO et son EBO, dessine ses buffers statiques complets, et rend
  // le nombre d'indices dessines. Elle ne restaure rien : le module remet VAO 0 et l'etat
  // GL d'avant a la fin.
  virtual uint64_t draw_depth_prepass(SharedRenderState* rs) = 0;
};

// Appele par les DEUX renderers (bureau, Android) la ou ils initialisaient `m_ao_pass`.
void init_shaders(ShaderLibrary& shaders);
// L'estimateur d'AO, possede par ce module (il tournait dans les deux renderers).
AmbientOcclusionPass& ao_pass();
// Android : la taille de fenetre qui dimensionne la chaine d'AO (0 = taille du FBO de rendu).
void set_output_hint(int w, int h);

// Tete de `dispatch_buckets` : nouvelle image (compteur de sonde, etat de preuve).
void frame_begin(SharedRenderState* rs);
// LE POINT D'ENTREE. Appele par `update_render_state_from_pc_settings` la premiere fois de
// l'image : prepasse + estimation d'AO, si l'AO est allumee et l'item arme.
void on_first_camera(SharedRenderState* rs, const GoalBackgroundCameraData& cam);
// `first_tfrag_draw_setup` : lie la texture d'AO d'ecran (unite 8) et pose
// `tex_screen_ao`, `u_screen_ao_on`, `u_screen_ao_inv_size`, `u_ao_proof` sur `program`.
void bind_screen_ao(GLuint program, SharedRenderState* rs);
// L'AO d'ecran est-elle appliquee cette image (mode != 0, item arme, texture valide) ?
bool screen_ao_active();
// La texture d'AO d'ecran de l'image (0 si aucune).
GLuint screen_ao_texture();

// ---- preuve (inertes hors mesure) ----
// Avant `renderer->render(...)` de chaque bucket : sur l'image sondee, les buckets monde
// ecrivent stencil = 1, les autres 0. Ne touche a rien hors mesure.
void proof_before_bucket(int bucket_id);
// Fin du bucket 30 (post-opaque) : relecture couleur + stencil, comptage, publication,
// stencil remis a zero et desactive. Ne touche a rien hors mesure.
void proof_post_opaque(SharedRenderState* rs);

}  // namespace prepass
