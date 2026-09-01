#pragma once

// Gcutscene-npc-flicker (owner 2026-08-31) — RECENSEMENT DES PNJ QUI CLIGNOTENT EN CINEMATIQUE.
//
// CE QUE C'EST, ET POURQUOI IL EXISTE UN MODULE A PART.
// -----------------------------------------------------
// L'owner : « le probleme des modeles des PNJ qui apparaissent, disparaissent et reapparaissent
// plusieurs fois pendant les cinematiques est revenu ! c'est pas la premiere fois ». Le defaut a
// deja ete corrige (Grecharged-hd-models3/4/5) et il est revenu. La garde laissee par ces
// phases-la etait le compteur `[hd-flicker] blackouts=` de Merc2.cpp :
//
//     $ grep -c 's_hd_blackout_events++' game/graphics/opengl_renderer/foreground/Merc2.cpp
//     0
//
// Le compteur est DECLARE, IMPRIME, et JAMAIS INCREMENTE — le correctif « fail-open » de
// 45b7140ca7 a supprime son unique site d'increment et a laisse la ligne dans l'entete. Les trois
// jambes de preuve (hd4_x86_intro_flicker.sh, hd4_intro_blerc_leg.sh, hd5_proof_bonus.sh) exigent
// toutes `blackouts=0` et zero ligne `[hd-flicker] BLACKOUT` : deux conditions qu'AUCUN chemin de
// code ne peut violer. La garde etait donc VIDE, et elle serait passee au vert quoi qu'il arrive.
//
// DEUX CONSEQUENCES DE CONCEPTION, ET ELLES SONT LA RAISON D'ETRE DE CE FICHIER :
//   1. le recensement ne vit PAS sous `#ifdef OG_FEAT_HD_MODELS`. L'ancien detecteur ne voyait que
//      les acteurs COUVERTS par un modele HD ; un PNJ purement stock qui clignote ne produisait
//      aucune ligne. Ici la mesure est la meme avec les modeles HD allumes ou eteints, ce qui rend
//      l'ablation possible SUR LE MEME BINAIRE ;
//   2. c'est un module autonome, sans OpenGL et sans etat de jeu, exactement comme
//      game/system/load_gate.cpp — donc il se compile seul et ses proprietes se PROUVENT sans
//      appareil et sans course (.autoport/npc_flicker_selftest.sh). Le controle positif fait
//      partie de la garde : le test echoue si le compteur ne MONTE PAS quand on lui injecte une
//      disparition. C'est precisement ce qui manquait a la garde precedente.
//
// LA GRANDEUR MESUREE, ET SON REPERE.
// -----------------------------------
// Nature du defaut : une PRESENCE qui s'interrompt puis revient — pas une amplitude, pas une
// frequence. On mesure donc, par acteur et par image, « quelque chose a-t-il ete DESSINE pour
// lui », et on compte les EPISODES d'absence encadres par deux presences.
//
// Repere : l'image RENDUE. Cote rendu, `note_draw` est appele pour chaque paquet merc a son issue
// (dessine / supprime par la couverture HD / modele absent du chargeur). Cote GOAL, le recensement
// tourne dans `post-sync-draw` (main.gc), c'est-a-dire APRES la passe de dessin de la meme image :
// le bit `was-drawn` (draw-status 3, « passe les tests de culling ») y est donc celui de CETTE
// image, et il separe proprement deux familles :
//     was-drawn = 1 et rien de dessine  -> la perte est cote RENDU   (supprime / modele absent)
//     was-drawn = 0                     -> la perte est cote GOAL    (mort / hidden / no-anim /
//                                                                     culling)
//
// Ligne de base quand le defaut est ABSENT : un acteur present a l'ecran d'un bout a l'autre de la
// cinematique rend `cycles=0` avec `frames=` egal a la duree de la scene. Une scene ou l'acteur
// n'apparait jamais rend `frames=0` et ne compte pour rien — un episode ne s'ouvre qu'apres une
// PREMIERE presence dessinee, sinon un PNJ absent par conception compterait comme un defaut.
//
// CE QUE LE COMPTEUR NE COMPTE PAS, ET C'EST VOULU. Un episode plus court que
// `kMinEpisodeFrames` images est publie separement (`blinks=`) et n'entre pas dans `cycles=` :
// le recensement GOAL et le compteur d'images du rendu sont deux horloges differentes et leur
// decalage vaut au plus une image. Sous-compter est honnete ; sur-compter fabriquerait un faux
// rouge, qui coute aussi cher qu'un faux vert.

#include <cstdint>
#include <string>
#include <vector>

namespace npc_flicker {

// --- cote rendu -------------------------------------------------------------
enum class Outcome {
  kDrawn = 0,       // le paquet a ete accepte et dessine
  kSuppressed = 1,  // la couverture HD a jete le paquet stock (Merc2, per-pid TTL)
  kMissing = 2,     // le modele merc n'est pas resident dans le chargeur
};

// Un paquet merc vient d'etre traite pour l'acteur `owner_pid`. Pour un paquet de COMPAGNON HD,
// `owner_pid` doit etre le pid du DRIVER (l'acteur du jeu), pas celui du compagnon : c'est le
// personnage qui est visible ou non, pas le processus qui le dessine.
void note_draw(uint32_t owner_pid, Outcome outcome, bool is_hd_model);

// Une image rendue de plus. Appelee une fois par image (Merc2::render deduplique).
void end_render_frame(uint64_t frame_idx);

// --- cote GOAL (une fois par image, uniquement pendant une cinematique) ------
// `scene` = nom de la cinematique en cours, ou nullptr / "hors-cinematique" pour la terminer.
void begin_census(const char* scene);

// Un acteur du recensement. `draw_status` est l'octet draw-status de jak1 :
//   bit0 needs-clip, bit1 hidden, bit2 no-anim, bit3 was-drawn, bit4 no-skeleton-update,
//   bit5 skip-bones, bit6 do-not-check-distance, bit7 has-joint-channels.
// `level_active` : 1 = le niveau de l'acteur est 'active (ses moteurs de dessin tournent),
// 0 = il ne l'est plus, -1 = l'acteur n'a pas d'entite (il vit sur level-default, qui tourne
// toujours). Sans cette entree, « le niveau a ete desactive sous l'acteur » et « la camera l'a
// laisse hors champ » rendent le MEME etat : pas de paquet et `was-drawn` a 0.
void census_actor(const char* proc_name,
                  const char* merc_name,
                  uint32_t pid,
                  uint32_t draw_status,
                  int level_active);

void end_census();

// Un CLONE de cinematique (`clone-anim-once`, engine/common-obs/generic-obs.gc) n'a pas pu suivre
// sa source cette image et s'est pose `hidden` lui-meme. C'est le SEUL moyen de separer ce
// masquage-la d'un masquage voulu par le jeu : les deux posent le meme bit. Les figurants des
// cinematiques (sidekick-human, evilsis, allpontoons, les deux mineurs...) sont des clones, et
// une anim de scene est STREAMEE : le slot de son groupe d'art peut etre delie sous ses pieds a
// chaque frontiere de partie — 22 pour `sage-intro-sequence-a`, 16 pour `mayor-introduction`.
void note_clone_remap_fail(const char* merc_name);

// --- lecture ----------------------------------------------------------------
struct Totals {
  uint64_t scenes = 0;
  uint64_t actors = 0;
  uint64_t cycles = 0;   // episodes DEFECTUEUX (voir la note sur les causes gatees)
  uint64_t coupes = 0;   // episodes explicables : hors du frustum, ou masque volontairement
  uint64_t longues = 0;  // episodes de cause DEFECTUEUSE mais plus longs que la borne haute
  uint64_t blinks = 0;   // episodes de 1 a kMinEpisodeFrames-1 images (publies, non gates)
  uint64_t by_reason[8] = {};  // indexe par Reason
  uint64_t frames = 0;
};

// DEUX FAMILLES, ET LA DISTINCTION PORTE LE VERDICT.
//   GATEES (comptees dans `cycles`) : rien dans le jeu n'a demande que l'acteur disparaisse.
//     mort / noanim / supprime / modele-absent / niveau.
//   EXPLIQUEES (comptees dans `coupes`, publiees, jamais gatees) :
//     culled  — GOAL lui-meme a juge l'acteur hors du frustum. C'est le moteur qui fonctionne :
//               une cinematique COUPE d'un cadrage a l'autre, et un acteur hors champ n'est pas
//               un defaut. Mesure a l'appui : sur `sage-intro-sequence-a`, les seuls episodes
//               observes sont de cette classe et durent jusqu'a 1686 images (28 s) — les compter
//               fabriquerait un rouge sur toutes les cinematiques du jeu.
//     hidden  — le jeu a explicitement pose (draw-status hidden). C'est une decision d'auteur.
enum Reason {
  kReasonDead = 0,        // le processus a disparu de l'arbre
  kReasonHidden = 1,      // (draw-status hidden)
  kReasonNoAnim = 2,      // (draw-status no-anim)
  kReasonCulled = 3,      // vivant, visible, mais was-drawn a 0 et son niveau tourne
  kReasonSuppressed = 4,  // GOAL a soumis, le rendu a supprime (couverture HD)
  kReasonMissing = 5,     // GOAL a soumis, le modele n'etait pas resident
  kReasonLevel = 6,       // le niveau de l'acteur n'est plus 'active : ses moteurs ne tournent plus
  kReasonRemap = 7,       // un CLONE de cinematique n'a pas pu suivre sa source et s'est masque
};
bool reason_is_defect(Reason r);
const char* reason_name(Reason r);

Totals totals();

// --- controle positif, sur le binaire LIVRE ---------------------------------
// Env OG_NPCF_INJECT="<fragment-de-nom>:<periode>:<duree>" — ETEINT par defaut. Quand il est
// arme, le rendu jette les paquets dont le nom contient <fragment> pendant <duree> images toutes
// les <periode> images. Un compteur ne vaut que s'il existe une entree qui le fait MONTER : la
// garde precedente n'avait pas ce bras, et son zero etait un zero de compilation.
bool inject_drop(const char* merc_name);

// Bornes de l'episode compte comme CLIGNOTEMENT. En dessous de la borne basse : `blinks`
// (l'ecart des deux horloges vaut au plus une image, sous-compter est honnete). Au-dessus de la
// borne haute : `longues` — l'owner decrit un PNJ qui « apparait, disparait et reapparait
// plusieurs fois pendant UNE cinematique » ; une absence de plusieurs secondes est un autre
// phenomene (un acteur reellement parti, un decor qui se recharge) et se signalerait comme « le
// PNJ manque », pas comme un clignotement. Mesure a l'appui : la seule absence de cause
// DEFECTUEUSE relevee sur `intro-start` etait une caisse morte pendant 1760 images (29 s).
int min_episode_frames();
int max_episode_frames();

void reset_for_test();

}  // namespace npc_flicker
