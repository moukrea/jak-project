#pragma once

// =================================================================================================
// foliage-wind — LES REGLAGES PARTAGES, LE VENT DU JEU, ET LE RECENSEMENT QUI PORTE LA PORTE.
//
// POURQUOI CE FICHIER EXISTE
// --------------------------
// Retour de l'owner, 2026-09-03 : « pour les shrubs, certains sont pris, d'autres ignorés, même
// deux identiques côté à côte... un est pris l'autre non c'est bizarre ». La cause n'etait pas une
// amplitude : c'etaient TROIS lois de mouvement independantes (Tie3.cpp cote vent, tie_sway.glsl cote
// TIE statique, shrub.vert cote buissons), chacune avec sa propre amplitude, sa propre horloge et
// son propre ancrage. Ce fichier pose donc UNE loi et UNE amplitude pour les trois chemins, et il
// MESURE le resultat par des grandeurs que le validateur lit.
//
// ESSAI 11 — LES SEPT VERDICTS (owner 2026-09-04, « je tiens mon précédent feedback, nul ! »).
// Le moteur publie `wind_owner_defects_open` = somme de sept verdicts binaires, publies aussi un par
// un. Chacun est LU sur une grandeur produite par le code — jamais sur une image :
//   (1) `wind_native_stock_dev_pct` <= 1 : la brise NATIVE (ressort de ND, option eteinte ou non)
//       tourne comme sur console. Deux composantes, le max est publie : slots MORTS de l'anneau de
//       vent (48 sur 64 avec l'ancien code « high fps » : `wind_ring_dead_slots`) et CADENCE
//       (`wind_native_rate_dev_pct`).
//
//       LA CADENCE SE MESURE AU POINT DE PRODUCTION, ET SA REFERENCE EST LE TEMPS DE JEU.
//       Essai 11 comparait les pas de vent aux ticks de `fixed_tick`, avec la MONTRE MURALE en
//       repli. Or `fixed_tick` est eteint par defaut (`armed_setting = false`) : la course de
//       preuve tombait toujours sur le repli, et le mural mesure la derive de la cadence
//       D'AFFICHAGE — 3,6 % sur 200 s, sur un vent parfaitement correct. Un chiffre rouge sur un
//       instrument, pas sur le jeu. La reference est desormais `(-> *display* time-adjust-ratio)`,
//       la croyance du moteur sur ce que vaut l'image en 1/60 s de TEMPS DE JEU — celle par
//       laquelle il multiplie deja tous les autres deltas. `update-wind-ticks!` (wind.gc) rapporte
//       par `__pc-wind-note-rate!`, a chaque image, le couple (ratio demande, pas executes).
//       Le critere separe les deux implementations sur LE MEME BINAIRE : le chemin livre execute
//       `int(acc + ratio)` en gardant le reste (ecart <= 1 pas sur toute la course, ~0 %) ; le
//       chemin d'avant (`OG_WIND_NATIVE_RATE=0`, `update-wind-legacy`) execute UN pas par image
//       quel que soit le ratio — a 15 images/s, ratio 4, il rend 75 % : « le vent d'origine
//       tournait au quart de sa vitesse » (owner 2026-08-06), en chiffres.
//       `wind_native_sat_pct` (part du temps colle a la butee) reste PUBLIE, hors verdict.
//   (2) `wind_shrub_base_shift_mm` == 0 : deplacement DESSINE a la ligne de sol des buissons enfonces
//       (poids interpole le long des aretes qui traversent le pivot, x flexion + cisaillement natif).
//   (3) `wind_instances_still` == 0 : aucune instance vegetale dessinee immobile.
//   (4) `wind_divergent_pairs` == 0 : deux voisines de meme taille plient du meme angle.
//   (5) `wind_spectrum_peak_pct` <= 40 : FFT du deplacement d'un sommet de couronne sur la course,
//       part de la raie dominante hors continu — une brise a un spectre large.
//   (6) `wind_base_to_crown_ratio` <= 0.15 : |poids| des 10 % du bas / poids de couronne, max sur
//       les instances dessinees — le tronc ne bouge pas.
//   (7) `wind_envelope_cv` >= 0.30 : ecart-type / moyenne de l'enveloppe (moyenne de |d| par
//       seconde) — des rafales, ni sinusoide pure ni tilt binaire.
//
// ESSAI 16 — DEUX VERDICTS DE PLUS (owner 2026-09-06 : « Le feuilles de palmiers meriteraient de
// bouger plus a leur extremites qu'a leur bases, de meme pour l'ensemble des shrubs [...] ça doit
// varier en amplitude, distorsion, direction »).
//   (8) `wind_tip_gradient_min` >= 3.0 : sur CHAQUE instance dessinee, la moyenne de |poids| de la
//       DERNIERE bande de la coordonnee d'element divisee par celle de la PREMIERE. Cinq bandes,
//       donc une mesure par SEGMENT le long de l'element et pas deux points ; poids relus APRES
//       quantification, donc sur ce que le VBO porte. La valeur publiee est le MINIMUM sur les
//       instances mesurables — une seule plante qui bouge d'un bloc ouvre le verdict. Les instances
//       dont une bande n'a pas `kTipBandMinVerts` sommets sont NON MESURABLES : elles sont comptees
//       a part (`wind_tip_unmeasured`) et, si moins de `kTipMinInstances` restent mesurables, le
//       verdict compte OUVERT — un seau exclu qu'on ne publie pas se lit « correct ».
//   (9) `wind_dir_variation_deg` >= 20 : l'ecart p5-p95 du CAP du deplacement, LISSE sur 2 s et
//       mesure DANS LE REPERE DU VENT. Deux precautions, chacune payee par une mesure ratee :
//         * le lissage : sur le cap instantane, |o| passe par zero a chaque accalmie et le cap fait
//           un tour complet — 128 deg avec un cap PARFAITEMENT fige ;
//         * le repere du vent : `wind-normal` de ND (wind.gc:60) est une MARCHE ALEATOIRE sur
//           l'angle (+/- 5,6 deg par pas de 1/60 s). Mesure sur le cap ABSOLU, la premiere course
//           x86 a rendu 319,9 deg — le tour complet, et un vert que RIEN n'aurait pu mettre au
//           rouge. Dans le repere du vent, ce qui reste est exactement ce que NOTRE loi ajoute.
//       Falsifiabilite mesuree hors moteur (notes/e16-law-tuning.cpp, meme arithmetique, pire des
//       48 fenetres) : la loi SANS le lacet de breeze.glsl rend 18,2 deg (ROUGE), avec 55,9 (VERT).
// wind_owner_defects_open somme les neuf acquis et les deux demandes du 2026-09-07 :
// (10) niveaux végétalisés non observés au dessin ; (11) liaisons du contact partagé.
// Les compteurs de contact attestent des sources/uniformes, pas du déplacement GPU.
// Un verdict qui n'a pas pu etre mesure (pas assez de temps, aucune paire) compte OUVERT.
//
// LA PORTE NE PEUT PAS ETRE VIDE. Si aucune paire n'a ete examinee, `wind_divergent_pairs` vaut
// `kNoMeasurement` (999999), pas 0. OPTION ETEINTE = RIEN A MESURER pour (2)-(7) : la course de
// preuve l'allume par `FOLIAGE_WIND_FORCE=1`, ce qui ne change rien pour l'owner.
// =================================================================================================

#include <cstdint>
#include <string>
#include <vector>

#include "common/common_types.h"
#include "common/custom_data/FoliageWindLaw.h"
#include "common/custom_data/Tfrag3Data.h"
#include "game/graphics/pipelines/opengl.h"

namespace foliage_wind {

// ------------------------------------------------------------------------------- les reglages ---

// Le basculement « FOLIAGE WIND » de l'owner, passe par Gfx::recharged_active (donc le maitre
// Recharged le force a OFF). `FOLIAGE_WIND_FORCE=1` / `debug.opengoal.foliage.force` l'allume sans
// toucher au reglage livre : c'est le levier que la course de preuve utilise.
bool enabled();
// Exact SHRUB prototype inventory for shared grass contact; excludes rocks/props.
bool shrub_contact_prototype(const std::string& name);

// ------------------------------------------------------- shrub-trunk-contact (owner 2026-09-13) --
// LA CLASSE TRONC/FEUILLAGE, POSEE SUR LE NIVEAU ENTIER. A appeler une fois par niveau charge,
// APRES `tfrag3::foliage_wind_finalize_level` (qui remplit `wind_proto_of_inst` depuis le sidecar,
// sans quoi aucune instance SHRUB n'a de prototype) et AVANT que les chargeurs ne construisent
// leurs tables d'ancres. Elle pose `load_bearing` / `carried` sur les `SwayInstance` du niveau.
//
// POURQUOI ICI ET PAS DANS `common/` : la regle ne parle que des instances ELIGIBLES AU CONTACT, et
// ce lexique-la (`shrub_contact_prototype`) vit cote jeu. POURQUOI SUR LE NIVEAU ENTIER : un
// mini-palmier est un ASSEMBLAGE de deux systemes — tronc TIE, frondaison SHRUB — qu'aucun des deux
// chargeurs ne peut voir depuis sa propre table.
void classify_load_bearing(tfrag3::Level& lev);

// Un chargeur vient de decider si CETTE instance recoit une ancre de contact. `anchored` faux n'est
// pas compte : seul un tronc qui en a RECU une est un defaut, et le compteur doit pouvoir rougir.
// `pivot_y` est la hauteur REELLEMENT ecrite dans l'ancre : c'est elle qu'on mesure, pas `base_y`.
void trunk_note_anchor(const tfrag3::TieTree::SwayInstance& si, bool anchored, float pivot_y);

// Publie les termes de la porte `shrub_trunk_squash_defects`. Appelee par `frame()`.
void trunk_census_publish();

// Flexion de couronne, en METRES, d'une plante de reference (8 m et plus). Bouton
// `debug.opengoal.foliage.bend` / `FOLIAGE_WIND_BEND`, defaut 0,30 m, plafond 0,80 m.
float bend_metres();

// Part de `bend_metres` reservee au fremissement de feuille (1,40 et 2,13 Hz), gain module par la
// rafale. Bouton `debug.opengoal.foliage.flutter` / `FOLIAGE_WIND_FLUTTER`, defaut 0,35.
float flutter_fraction();

// Le vent NATIF des buissons (ressort de ND, hors option Recharged : c'est du stock restaure).
// Ablation `OG_WIND_SHRUB_NATIVE` / `debug.opengoal.wind.shrub_native` = 0 ; defaut 1. Lu une fois.
bool shrub_native_enabled();

// Horloge de brise, en secondes. Une seule pour les trois chemins. Avance une fois par `frame_idx`,
// gelee quand le vent du jeu est en pause, `dt` borne a 0,1 s.
float clock_seconds(u64 frame_idx, bool paused);

// L'etat du vent du JEU, recopie une fois par image par Tie3 (le seul renderer qui recoit
// `wind-work` par DMA) : cap (x, z) et pause. Un vecteur nul ou NaN garde le cap precedent.
void set_wind_state(float dir_x, float dir_z, bool paused);
void direction(float* out_x, float* out_z);
bool paused();

// LES UNIFORMES DU CHUNK tie_sway.glsl, POUSSES D'UN SEUL ENDROIT pour les quatre programmes.
// A appeler APRES `first_tfrag_draw_setup`. Rend l'amplitude poussee (0 = eteint).
float push_uniforms(GLuint program, u64 frame_idx, const char* pass);

// ------------------------------------------------------- la loi, cote CPU (chemin VENT du TIE) ---
// Jumelle EXACTE de `breeze_offset` de shaders/breeze.glsl. Sortie : deplacement horizontal en
// unites monde ; `out_flutter_gain` (optionnel) : le gain de fremissement de la rafale, [0.34, 1].
void breeze_offset(float anchor_x,
                   float anchor_z,
                   float dir_x,
                   float dir_z,
                   float ph01,
                   float t,
                   float w,
                   float bend_u,
                   float flutter_f,
                   float* out_x,
                   float* out_z,
                   float* out_flutter_gain = nullptr);

// ----------------------------------------------------------- le vent du JEU (ND), pour (1) ------

// Combien de pas de 1/60 s cette image porte, lu sur `wind-time` (un cran par `update-wind`).
// Premiere image apres un chargement : 1 (on ne rattrape pas l'historique du monde). En pause : 0.
// Borne a 8 (un a-coup de chargement ne fait pas defiler la brise d'un huitieme de seconde).
// Arithmetique non signee : robuste au repliement. UNE definition, pour Tie3 ET Shrub.
int wind_ticks_for(u32 now, u32& last, bool& seeded, bool paused);

// La copie du `wind-work` de cette image (les 64 forces de l'anneau, le compteur, la pause), deposee
// par Tie3 a la reception du DMA. Sert au verdict (1) : slots morts de l'anneau et cadence (pas de
// vent compares aux ticks de logique de fixed_tick).
void note_game_wind(const float* wind_force64, u32 wind_time, bool paused, u64 frame_idx);

// La copie OCTET POUR OCTET du `wind-work` recu par Tie3 (Tie3::WindWork, 1344 octets), pour le
// renderer SHRUB qui ne recoit rien par DMA et integre pourtant le meme ressort. `game_wind_bytes`
// rend nullptr tant qu'aucune copie n'est arrivee ; `*out_n` = taille de la copie.
void set_game_wind_copy(const void* bytes, size_t n);
const void* game_wind_bytes(size_t* out_n);

// Un echantillon du ressort natif (TIE ou shrub) : |etat| AVANT `stiffness` et « a tape la butee ».
void note_native_sample(float raw_pre_stiffness, bool saturated);

// LA CADENCE, RAPPORTEE PAR SON PRODUCTEUR. Appelee une fois par tour de `display-loop` depuis
// `update-wind-ticks!` (wind.gc), via `__pc-wind-note-rate!` : `ratio` = ce que cette image vaut en
// 1/60 s de temps de jeu (`(-> *display* time-adjust-ratio)`), `steps` = le nombre d'appels a
// `update-wind` reellement faits. Les images dont le ratio depasse la borne de 8 pas (a-coup de
// chargement, ecretees a la production) sortent des deux sommes et sont comptees a part dans
// `wind_rate_hitch_frames` : un seau exclu qu'on ne publie pas se lit « correct ».
void note_wind_rate(float ratio, int steps);

// Le plus grand |cisaillement| natif applique a un buisson cette image (sans dimension) : entre dans
// `wind_shrub_base_shift_mm` a cote de la flexion ajoutee.
void note_shrub_native_shear_peak(float s);

// ------------------------------------------------------------------------------ le recensement ---

// Une instance de vegetation DESSINABLE.
struct Instance {
  float anchor_x = 0.f;  // ancrage monde (unites GOAL)
  float anchor_z = 0.f;
  float height_m = 0.f;  // hauteur VISIBLE de la plante (couronne - pivot), metres
  float peak_w = 0.f;    // poids a la couronne, tel que le shader le lit (0 = ne bouge jamais) ;
                         // la flexion en metres est `bend_metres() * peak_w`, calculee a la lecture
  float low_w = 0.f;     // plus grand |poids| des 10 % du bas visibles (le « tronc »)
  float base_w = 0.f;    // |poids| interpole a la ligne du pivot (shrub enfonce ; 0 sinon)
  // essai 16, verdict (8) : moyennes de |poids| de la premiere et de la derniere bande de la
  // coordonnee d'element (TIE : portee depuis l'axe ; SHRUB : hauteur au-dessus du pivot).
  // -1 = bande trop peu peuplee, l'instance ne se mesure pas et compte comme telle.
  float att_w = -1.f;
  float tip_w = -1.f;
  u32 sunk_mm = 0;       // shrub : enfoncement sous le sol trouve
  bool ground_found = false;
  bool shrub = false;
  bool native_stiff = false;  // shrub : son prototype a une raideur ND > 0 (vent natif actif)
};

// Les trois systemes qui dessinent de la vegetation.
enum System : int { kSystemTieStatic = 0, kSystemTieWind = 1, kSystemShrub = 2 };

// Remplace integralement le lot d'instances d'un arbre. Un rechargement ecrase, il n'accumule pas.
void set_tree(const std::string& level, int system, int tree, int geo, std::vector<Instance>&& v);

// Oublie tous les arbres d'un niveau pour un systeme : appele quand le renderer lache le niveau.
void forget(const std::string& level, int system);

// Cet arbre a ete SOUMIS au moins une fois. Sans cette marque, ses instances ne comptent pas.
void mark_drawn(const std::string& level, int system, int tree, int geo);

// Tous les prototypes du niveau qu'aucune ligne du lexique de vegetation ne couvre.
void note_unclassified(const std::string& level, int tree, u32 count);

// Une image de plus. Appelee par chaque renderer ; ne compte qu'une fois par `frame_idx`.
// Echantillonne la loi pour (5) et (7) ; recalcule et publie toutes les `kRepublishFrames` images.
void frame(u64 frame_idx);

// Valeur publiee quand une grandeur n'a PAS pu etre mesuree. Ce n'est pas 0, deliberement.
constexpr u64 kNoMeasurement = 999999;

}  // namespace foliage_wind
