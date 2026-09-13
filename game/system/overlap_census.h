#pragma once

// overlap_census — L'INSTRUMENT DE `perf-goal-gl-overlap`.
//
// CE QU'IL MESURE, ET POURQUOI IL EXISTE.
// ---------------------------------------
// Le recouvrement GOAL/GL fait construire l'image N+1 par le fil GOAL pendant que le fil GL
// rend l'image N. La chaine DMA, elle, est copiee en profondeur (`FixedChunkDmaCopier`) : elle
// ne peut pas bouger sous le rendu. Ce qui PEUT bouger, c'est tout ce que le rendu lit AILLEURS
// que dans cette copie — les matrices d'os, les sommets merc-mod, les pages de texture, la
// source des uploads d'animation de texture — parce que ces donnees-la sont designees par une
// ADRESSE GOAL et relues dans la memoire EE vivante. C'est la regression de juillet 2026 : la
// geometrie qui pope.
//
// L'instrument ne suppose rien de la liste des sites. Il compte AU POINT DE LECTURE : chaque
// lecture hors chaine s'inscrit (adresse, longueur, empreinte du contenu lu). A la fin du rendu,
// il RELIT les memes octets dans la memoire EE et compare. Une difference veut dire, sans
// interpretation possible, que le fil GOAL a reecrit pendant que le fil GL consommait.
//
// LA GRANDEUR DE LA PORTE : `overlap_defects`. Elle est la somme de quatre termes, tous publies
// separement pour qu'un zero soit lisible :
//
//   overlap_chain_mutated  la copie de chaine rendue differe de celle qui a ete publiee ;
//                          ca teste la garde inconditionnelle de `send_chain`.
//   overlap_oob_changed    une plage hors chaine a change entre sa lecture et la fin du rendu.
//   overlap_stamp_mismatch le rendu croyait dessiner une image de logique, la chaine en portait
//                          une autre.
//   overlap_vacuous        LA COURSE N'A PAS RECOUVERT. Un zero obtenu en serialisant ne prouve
//                          rien : ce terme rend la porte infalsifiable autrement. Il vaut 1 des
//                          que la course a dessine assez d'images ET que le fil GOAL n'a JAMAIS
//                          ete relache pendant qu'un rendu etait EN VOL.
//
// CE QUI DISCRIMINE, ET CE QUI NE DISCRIMINE PAS.
// ----------------------------------------------
// `overlap_release_in_flight` compte les retours de `vsync()` pris alors que `has_data_to_render`
// etait encore VRAI — le fil GOAL repart alors que le fil GL n'a pas fini. En mode serialise
// c'est IMPOSSIBLE par construction : le predicat y attend le swap, et le swap suit l'effacement
// du drapeau. Ce compteur lit donc exactement l'etat que l'autre regime interdit ; c'est lui, et
// lui seul, qui rend `overlap_defects == 0` autre chose que ce qu'un binaire serialise rendrait.
//
// `overlap_goal_ahead_max` est publie A COTE, comme temoin de contexte, mais il ne sert PLUS a
// juger : MESURE le 2026-09-13 sur trois courses x86 de 90 s (recouvrement ON, OFF, ON), il vaut
// 1 DANS LES TROIS, y compris celle ou `overlap_frames_overlapped` valait 0. La raison est dans
// le moteur : `display-sync` (drawable.gc:1306) envoie la chaine PUIS bascule `on-screen` et
// appelle `display-frame-start`, qui fait avancer `actual-frame-counter` — les deux regimes
// construisent donc deja l'image N+1 pendant le rendu de N, et ce qui les separe est l'endroit
// ou GOAL ATTEND, pas son avance en images de logique. Le garder sans le dire aurait fait passer
// une porte verte par inaction pour une porte tenue.
//
// COUT. L'instrument ne tourne QUE quand le harnais mesure cet item
// (`autoport_proof::feature_is`). Dans le binaire de l'owner, `measuring()` rend faux au premier
// appel et chaque point de mesure est un test d'un booleen. Il tourne dans LES DEUX bras de
// l'ablation (arme ou non) : un instrument qui s'eteint avec l'armement ne separe rien.

#include <cstdint>

namespace overlap_census {

// Les familles de lecture hors chaine. Une famille inconnue serait comptee sans etre nommee :
// `overlap_kinds` publie les noms, `overlap_oob_by_kind_*` les cardinaux.
enum Kind {
  kBones = 0,      // matrices d'os merc (Merc2, `bones` tourne apres le DMA merc)
  kMercMod,        // sommets merc-mod relus par adresse GOAL
  kTexUpload,      // pages de texture televersees depuis la memoire EE
  kTexAnim,        // source des uploads d'animation de texture
  kOcean,          // l'objet `*ocean-map*` (recharged)
  kKindCount,
};

// Vrai quand le harnais mesure CET item. Tout le reste est un no-op sinon.
bool measuring();

// L'etat EFFECTIF du recouvrement, tel que le moteur l'applique. Appele une fois par image,
// depuis le fil qui decide (GL sur Android, GOAL sur bureau). Publie tel quel.
void set_overlap_active(bool active);

// FIL GOAL — la chaine de `logic_frame` vient d'etre copiee et publiee. `copy`/`bytes` designent
// la COPIE, pas la chaine vivante.
void chain_published(const void* copy, uint32_t bytes, int64_t logic_frame);

// FIL GL — la chaine vient d'etre ramassee, le rendu commence. `logic_frame` est l'estampille que
// le producteur a apposee a CETTE chaine.
void render_begin(int64_t logic_frame);

// FIL GL — une lecture hors chaine, au POINT D'APPEL. `ee_addr` est un offset GOAL dans
// `g_ee_main_mem`. Une adresse hors bornes est comptee (`overlap_oob_rejected`) et ignoree :
// elle ne doit pas passer pour une plage surveillee.
void note_read(int kind, uint32_t ee_addr, uint32_t len);

// FIL GL — le rendu est fini. Relit les plages inscrites, compte les defauts, publie.
void render_end();

// LE SLOT DE REGLAGES (`Gfx::adopt_settings_for_frame`) rend compte ici. Une estampille manquee
// veut dire que les DEUX emplacements ont ete ecrases, donc que le fil GOAL a pris plus d'une
// image d'avance : c'est un terme de `overlap_defects`, pas un temoin.
void note_settings_stamp_miss();
void note_settings_snapshot();

// FIL GOAL — `vsync()` vient de rendre la main. `render_in_flight` est l'etat de
// `has_data_to_render` LU SOUS LE VERROU au moment du retour : vrai veut dire que le fil GL n'a
// pas fini son image et que GOAL repart quand meme. C'est LE discriminant du regime.
void note_goal_release(bool render_in_flight);

}  // namespace overlap_census
