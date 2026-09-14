#pragma once

// perf-fbo-passes — « Une seule passe plein ecran par image, et le depth n'est plus stocke
// pour rien. »
//
// CE QUE CE MODULE MESURE, ET POURQUOI IL NE PEUT PAS SE CONTENTER D'UN ZERO.
// --------------------------------------------------------------------------
// La porte de l'item lit `fb_extra_passes_per_frame == 0`. Un compteur qui ne compterait QUE
// ce que le correctif retire rendrait zero par construction : ce serait un miroir du
// correctif, pas une mesure (gate_quantity_computed_from_own_state_is_unfalsifiable). La
// grandeur est donc ancree sur une borne PHYSIQUE, pas sur notre code :
//
//   extra = (copies plein ecran de l'image - 1)   // il en faut UNE : la scene doit atteindre
//         + (fins de passe sans invalidate)        //   la fenetre une fois, jamais deux
//         + (clears de la fenetre entierement recouverts)
//
// et les DENOMINATEURS voyagent a cote dans la meme preuve — `fb_fullscreen_copies_max`,
// `fb_pass_ends_max`, `fb_invalidate_calls_total`, `fb_frames_measured` : un zero lu sur une
// population vide se voit alors tout de suite, au lieu de passer pour un succes
// (witness_on_a_live_population_the_fix_empties, green_gate_satisfied_by_inaction). Avant ce
// travail, la chaine Android fait DEUX copies quand la passe UI est ouverte (blit scene ->
// tampon UI, puis quad UI -> fenetre), un clear de FB0 integralement recouvert, et ZERO
// invalidate dans tout l'arbre : `fb_extra_passes_per_frame` y vaut au moins 2.
//
// L'INSTRUMENT EST ARME PAR L'IDENTITE, LE CORRECTIF PAR `armed_for`
// (instrument_armed_by_identity_makes_ablation_measurable) : les compteurs tournent toujours,
// de sorte que le bras `--off` MESURE le defaut qui revient au lieu de rendre un zero muet.

#include <cstdint>

#include "game/graphics/pipelines/opengl.h"

namespace fb_passes {

// L'identifiant de l'item. UN seul litteral, partage par l'instrument et par le correctif.
extern const char* const kItemId;

// Le correctif de CET item est-il arme ? Vrai hors harnais et pour l'owner ; faux seulement
// quand le harnais mesure l'ablation de `perf-fbo-passes`.
bool fix_armed();

// --- ce que le chemin de dessin declare, une fois par geste -------------------------------

// Une copie plein ecran de l'image : blit d'upscale, tone map, resolve MSAA, quad de present.
// `site` finit dans `fb_copy_sites` — quand le compte depasse un, la preuve NOMME les copieurs
// au lieu de laisser chercher (boolean_proof_marker_cannot_name_the_culprit).
void note_fullscreen_copy(const char* site);

// Le point de l'image ou le clear du framebuffer de FENETRE se pose. Il est declare a CHAQUE
// image, meme quand le clear n'est plus emis : sans ca, le correctif viderait sa propre
// population et le `covered_max=0` se lirait sur zero observation
// (witness_on_a_live_population_the_fix_empties). `fully_covered` = tout ce que ce clear
// ecrirait sera reecrit par le quad de present de la MEME image ; `issued` = il a bel et bien
// ete emis. Superflu == issued ET fully_covered.
void note_window_clear(bool issued, bool fully_covered);

// Un resolve MSAA (bureau seulement). C'est bien une copie plein ecran, mais elle est
// IRREDUCTIBLE quand le rendu est multi-echantillonne : l'exclure de `extra` est un choix
// assume, pas un silence — elle est publiee a part sous `fb_msaa_resolves_max`, et
// `extra` accuserait sinon le multi-echantillonnage d'un defaut que ce travail ne peut pas
// retirer.
void note_msaa_resolve();

// Le framebuffer par DEFAUT porte-t-il un depth et un stencil ? La passe UI directe y ecrit la
// profondeur du HUD (GEQUAL) : sans eux, elle n'est pas possible.
// Lu UNE fois, FB0 lie, et publie (`fb_window_depth_bits` / `fb_window_stencil_bits`).
// `glGetIntegerv(GL_DEPTH_BITS)` NE CONVIENT PAS : il a disparu du profil core d'OpenGL et
// rend 0 sur le bureau meme quand la fenetre a bien 24 bits de profondeur — mesure du
// 14/09, `fb_ui_direct_blocked=no-window-depth` sur une fenetre qui en avait. On interroge
// donc l'ATTACHEMENT, qui existe dans les deux API.
bool window_has_depth_stencil();

// SAUVE ET RESTAURE L'ETAT GL QUE LE QUAD DE PRESENT PERTURBE.
// ------------------------------------------------------------
// Le quad de present terminait l'image : ce qu'il laissait derriere lui n'avait plus de
// lecteur. La passe UI directe le tire AU MILIEU de l'image, et la 2D qui suit herite de son
// etat. Mesure x86 du 14/09 sans cette garde : 3 177 `GL_INVALID_OPERATION` la ou le binaire
// d'avant en avait 2 — le programme POST_PROCESSING restait actif et les pousseurs d'uniformes
// suivants ecrivaient dans SES emplacements (« u_out_mode@3 has 1 components, not 4 »). Le
// test de profondeur, lui, restait ETEINT : le HUD toujours-au-dessus (GEQUAL) aurait cesse
// d'etre rejete par la profondeur, exactement la regression `orb-hud` deja payee une fois.
// La liste n'est pas devinee : c'est celle des etats que `present_quad_to_window` ecrit.
struct PresentStateGuard {
  PresentStateGuard();
  ~PresentStateGuard();
  PresentStateGuard(const PresentStateGuard&) = delete;
  PresentStateGuard& operator=(const PresentStateGuard&) = delete;

 private:
  GLint m_program = 0;
  GLint m_vao = 0;
  GLint m_array_buffer = 0;
  GLint m_active_texture = GL_TEXTURE0;
  GLint m_texture_2d = 0;
  GLint m_viewport[4] = {0, 0, 0, 0};
  GLboolean m_depth_test = GL_FALSE;
  GLboolean m_blend = GL_FALSE;
};

// Une cible porteuse d'un depth/stencil vient d'etre lue pour la derniere fois de l'image.
// `invalidated` = son depth/stencil a bien ete abandonne au lieu d'etre range en memoire par
// le tiler.
void note_pass_end(const char* site, bool invalidated);

// LE GESTE ET SON COMPTEUR, AU MEME SITE. La cible `target` doit etre liee par l'appelant ;
// son depth/stencil ne sera plus lu de cette image, on l'abandonne au lieu de le laisser
// ranger en memoire par le tiler. `is_window` choisit les noms d'attachement : le framebuffer
// par defaut se nomme GL_DEPTH/GL_STENCIL, un FBO GL_*_ATTACHMENT — se tromper rend
// GL_INVALID_ENUM et l'appel ne fait rien, en silence.
// Desarme (`--off`), l'appel GL n'a PAS lieu et la fin de passe est declaree NON invalidee :
// le bras d'ablation mesure alors le defaut qui revient au lieu de rendre un zero muet.
// `fb_invalidate_calls_total` est le temoin d'EXECUTION : sans lui, un
// `fb_pass_ends_no_invalidate_max=0` ne se distinguerait pas de « aucune fin de passe n'a ete
// declaree » (counter_after_early_return_cannot_separate_empty_from_never_called).
void end_pass_discarding_depth(const char* site, GLenum target, bool is_window, bool has_depth);

// La geometrie de l'image. Publiee telle quelle : c'est elle qui dit dans QUEL regime la
// course a mesure, et sans elle un zero ne se rattache a rien
// (proof_must_pin_its_own_feature_gate_regime).
void note_frame_geometry(int win_w,
                         int win_h,
                         int draw_w,
                         int draw_h,
                         int off_x,
                         int off_y,
                         int scene_w,
                         int scene_h);

// Le regime de la passe UI. `block_reason` NOMME pourquoi l'UI n'a pas pu etre dessinee
// directement dans la fenetre ; "-" quand elle l'a ete, "no-split" quand la question ne se
// pose pas. Un refus muet serait indiscernable d'un correctif absent.
void note_ui_regime(bool split_active, bool direct_to_window, const char* block_reason);

// La passe UI de cette image a ete ouverte DIRECTEMENT dans la fenetre. Compteur separe : le
// declarer par `note_ui_regime(true, true, ...)` comptait le split une SECONDE fois pour la
// meme image (mesure x86 du 14/09 : 922 pour 461 images).
void note_ui_direct();

// --- frontiere d'image, fil graphique -----------------------------------------------------
// Appelee aux DEUX frontieres d'image (x86 `pipelines/opengl.cpp`, appareil `android_gfx.cpp`) :
// un site pose d'un seul cote rend la preuve de l'autre muette — c'est exactement ce qui est
// arrive a `lighting-unify`.
void frame_boundary();

}  // namespace fb_passes
