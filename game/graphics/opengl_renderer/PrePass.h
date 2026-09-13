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
  //
  // ELLE NE FAIT PLUS SON PROPRE glDrawElements : elle appelle `draw_depth_range` par plage,
  // parce que l'alpha-test du feuillage (SPEC §4.6) exige la texture du draw et son seuil, et
  // parce que la passe de CLASSIFICATION de la preuve rejoue EXACTEMENT les memes plages. Une
  // implementation qui dessinerait elle-meme serait muette dans le deuxieme bras.
  virtual uint64_t draw_depth_prepass(SharedRenderState* rs) = 0;
};

// Une plage d'indices de l'EBO courant, avec de quoi rejouer l'alpha-test de la passe
// principale. `tex` == 0 (ou `cut_aref` <= 0) = aucun test : la plage est opaque par
// construction et ne coute aucun bind.
//
// `cut_aref` est le seuil sur l'alpha de TEXTURE, deja divise par la borne superieure de
// `fragment_color.a` (= 4.0) : voir l'en-tete de prepass_world.frag. `cut_amb` est le seuil
// NON divise (alpha_min), qui borne la bande ambigue comptee par `ao_alpha_fringe_px`.
struct DepthRange {
  uint32_t tex = 0;       // nom GL de la texture du draw (0 = aucune)
  float cut_aref = 0.f;   // seuil conservateur sur T0.a (0 = pas de test)
  float cut_amb = 0.f;    // alpha_min du draw, pour la bande ambigue
  uint32_t first = 0;     // premier index dans l'EBO lie
  uint32_t count = 0;     // nombre d'indices
};

// Calcule le `alpha_min` que `compute_double_draw` donnerait a ce mode de draw, et remplit
// `cut_aref` / `cut_amb`. Declare ici pour que les trois contributeurs partagent la meme regle.
DepthRange make_depth_range(uint32_t gl_tex, float alpha_min, uint32_t first, uint32_t count);

// Dessine UNE plage. Pose `tex_T0` / `u_cut_aref` / `u_cut_amb` (memoises), compte le draw au
// recensement, et rend `count`. A n'appeler QUE depuis `draw_depth_prepass`.
// `gl_mode` = GL_TRIANGLES ou GL_TRIANGLE_STRIP, selon le buffer du contributeur.
uint64_t draw_depth_range(unsigned gl_mode, const DepthRange& r);

// lighting-ao-indirect : le FBO de la prepasse, pour qui doit RELIRE sa profondeur. Rend 0
// tant qu'aucune image n'a ete prepassee. `glGetTexImage` sur la texture rendait un tampon
// entierement nul sans poser d'erreur GL (mesure du 2026-09-13 : 0 couple plan sur 12 etats,
// 4 images chacun) : on relit par le chemin que le reste du recensement emprunte deja.
unsigned depth_fbo();

// lighting-ao-indirect : VRAI pendant la passe de mesure « occluder fantome » (image sondee
// seulement). Les contributeurs dessinent alors leurs plages ECARTEES — celles des draws sans
// z-write — au lieu de leurs plages livrees. Rend FAUX partout ailleurs.
bool noz_pass_active();
// Recense une plage ECARTEE de la prepasse au CHARGEMENT (comptes publies : ao_noz_ranges,
// ao_noz_inds).
void note_noz_range(uint32_t inds);

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
