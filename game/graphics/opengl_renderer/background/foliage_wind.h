#pragma once

// =================================================================================================
// foliage-wind — LES REGLAGES PARTAGES ET LE RECENSEMENT QUI PORTE LA PORTE.
//
// POURQUOI CE FICHIER EXISTE
// --------------------------
// Retour de l'owner, 2026-09-03 : « pour les shrubs, certains sont pris, d'autres ignorés, même
// deux identiques côté à côte... un est pris l'autre non c'est bizarre ». La cause n'est pas une
// amplitude : ce sont TROIS lois de mouvement independantes (Tie3.cpp cote vent, tie_sway.glsl cote
// TIE statique, shrub.vert cote buissons), chacune avec sa propre amplitude, sa propre horloge et
// son propre ancrage. Mesure de la phase precedente, niveau beach (`sway-cover lev=beach tree=0`) :
// `bch-palmplant-base.mb` (80 instances) recevait 0,10 m de couronne par le chemin STATIQUE pendant
// que `palm-02.mb` (64 instances, stiffness 0,1) en recevait 0,035 x 17,52 m = 0,61 m par le chemin
// VENT. Six fois plus, sur deux plantes que l'oeil lit comme la meme. C'est exactement la phrase de
// l'owner, et aucune des deux valeurs n'etait « fausse » isolement.
//
// Ce fichier pose donc UNE loi et UNE amplitude pour les trois chemins, et il MESURE le resultat
// par une grandeur que le validateur lit : `wind_divergent_pairs`.
//
// CE QUE `wind_divergent_pairs` COMPTE — LA PHRASE DE L'OWNER, TRADUITE
// --------------------------------------------------------------------
// Une PAIRE = deux instances de vegetation REELLEMENT DESSINEES, dont les ancrages sont a moins de
// 12 m l'un de l'autre (« côté à côte ») et dont les hauteurs sont dans un rapport de 1,5 au plus
// (« identiques » : l'oeil compare des plantes de meme taille apparente ; il ne compare pas un
// palmier a une touffe d'herbe).
// Une paire est DIVERGENTE quand le rapport de leurs FLEXIONS RELATIVES depasse 2. La flexion
// relative d'une instance est `reponse_m / hauteur_m` — un ANGLE, pas une longueur : deux plantes
// voisines de tailles differentes doivent plier du meme angle, c'est ce que l'oeil lit. Une
// instance qui ne bouge pas du tout a une flexion nulle, donc TOUTE paire qui la contient diverge :
// un trou de couverture ne peut pas passer cette porte en silence.
// Sous la loi unifiee, la flexion relative de deux plantes dont les hauteurs sont dans un rapport
// <= 1,5 ne peut pas s'ecarter de plus de 1,5 (voir `size_factor` : la reponse est proportionnelle
// a la hauteur sous 8 m et constante au-dessus). La marge au seuil de 2 est donc structurelle, pas
// un reglage.
//
// LA PORTE NE PEUT PAS ETRE VIDE. Si aucune paire n'a ete examinee — niveau sans vegetation, arbre
// jamais dessine, recensement mort — `wind_divergent_pairs` NE VAUT PAS 0. Il vaut
// `kNoMeasurement` (999999) et la porte est rouge. Un zero de « rien mesure » se lit exactement
// comme un zero de « tout va bien », et c'est le faux vert que ce dossier a deja paye plusieurs
// fois. `wind_pairs_examined` est publie a cote pour que le denominateur soit lisible.
//
// LA REPONSE EST LUE AU POINT DE LECTURE. La flexion d'une instance n'est pas une prediction du
// mouvement : pour les chemins ponderes (TIE statique, shrub) c'est le produit de l'UNIFORME
// reellement pousse (`bend_metres()`) par le MAXIMUM DE L'ATTRIBUT reellement televerse (`peak_w`,
// le poids sur 8 bits que le sommet-shader consomme, relu apres quantification). Les deux facteurs
// sont les deux seules grandeurs que le shader lit. Pour le chemin VENT, `peak_w` est le facteur de
// taille que le CPU multiplie (`size_factor`), lu de la meme table.
//
// OPTION ETEINTE = RIEN A MESURER. Toute reponse vaut 0, toute paire est « immobile des deux cotes »
// et le compte de divergences serait 0 par construction : ce zero-la est un faux vert. La porte
// publie donc `kNoMeasurement` tant que la brise n'est pas allumee ; la course de preuve l'allume
// par `FOLIAGE_WIND_FORCE=1` (proof_env de l'item), ce qui ne change rien pour l'owner.
// =================================================================================================

#include <cstdint>
#include <string>
#include <vector>

#include "common/common_types.h"
#include "common/custom_data/FoliageWindLaw.h"
#include "game/graphics/pipelines/opengl.h"

namespace foliage_wind {

// ------------------------------------------------------------------------------- les reglages ---

// Le basculement « FOLIAGE WIND » de l'owner, passe par Gfx::recharged_active (donc le maitre
// Recharged le force a OFF). `FOLIAGE_WIND_FORCE=1` / `debug.opengoal.foliage.force` l'allume sans
// toucher au reglage livre : c'est le levier que la course de preuve utilise pour mesurer l'etat
// que l'owner regarde, et il ne change rien pour lui.
bool enabled();

// Flexion de couronne, en METRES, d'une plante de reference (8 m et plus). Bouton
// `debug.opengoal.foliage.bend` / `FOLIAGE_WIND_BEND`, defaut 0,14 m, plafond 0,50 m.
float bend_metres();

// Part de `bend_metres` reservee au fremissement de feuille (1,40 et 2,13 Hz), gain module par la
// rafale. Bouton `debug.opengoal.foliage.flutter` / `FOLIAGE_WIND_FLUTTER`, defaut 0,35.
float flutter_fraction();

// La loi de POIDS (facteur de taille, poids par sommet, phase d'instance) vit dans
// `common/custom_data/FoliageWindLaw.h` : `TFrag3Data.cpp` (libcommon) la derive au depaquetage et
// ce module la relit pour recenser. Deux cibles de lien differentes, une seule definition.

// Horloge de brise, en secondes. Une seule pour les trois chemins — le shrub avait la sienne, qui
// ne se figeait pas en pause et ne bornait pas les a-coups. Avance une fois par `frame_idx`, gelee
// quand le vent du jeu est en pause, `dt` borne a 0,1 s (un chargement ne doit pas faire defiler
// la brise d'un dixieme de seconde d'un coup).
float clock_seconds(u64 frame_idx, bool paused);

// L'etat du vent du JEU, recopie une fois par image par Tie3 (le seul renderer qui recoit
// `wind-work` par DMA) : cap (x, z) et pause. Un vecteur nul ou NaN garde le cap precedent. Shrub,
// qui ne recoit rien, lit le meme etat : les deux chemins penchent du meme cote et se figent ensemble.
void set_wind_state(float dir_x, float dir_z, bool paused);
void direction(float* out_x, float* out_z);
bool paused();

// LES UNIFORMES DU CHUNK tie_sway.glsl, POUSSES D'UN SEUL ENDROIT pour les quatre programmes
// (tfrag3, etie_base, etie, shrub) : `u_tie_sway_amp` (bend en unites monde, 0 si l'option est
// eteinte), `u_tie_sway_time`, `u_tie_sway_dir`, `u_tie_sway_flutter`. A appeler APRES
// `first_tfrag_draw_setup`, qui vient d'ecrire 0 dans l'amplitude (verrou (a) du terrain). Publie
// une ligne de journal one-shot par `pass` avec les emplacements d'uniformes et l'etat de l'attribut
// 7 — les deux modes de defaillance silencieux de ce chemin. Rend l'amplitude poussee.
float push_uniforms(GLuint program, u64 frame_idx, const char* pass);

// ------------------------------------------------------- la loi, cote CPU (chemin VENT du TIE) ---
// Jumelle EXACTE de `breeze_offset` de shaders/breeze.glsl. Le chemin VENT du TIE n'a pas
// d'attribut par sommet : son terme ajoute est un CISAILLEMENT de la matrice d'instance, calcule
// ici. Les deux implementations doivent rester identiques ligne pour ligne — c'est pour ca
// qu'elles portent les memes constantes nommees et le meme ordre d'operations.
// `anchor_x/z` : position monde de l'instance. `ph01` : sa phase. `t` : secondes.
// `w` : poids a la couronne (le chemin VENT passe `size_factor(hauteur)`). `bend_u` :
// `bend_metres() * 4096`. `flutter_f` : part de fremissement ; 0 pour n'obtenir que la flexion (le
// chemin VENT fait fremir ses feuilles par sommet dans tie_wind.vert, avec le gain rendu ici).
// Sortie : deplacement horizontal en unites monde ; `out_flutter_gain` (optionnel) : le gain de
// fremissement de la rafale a cet instant, dans [0.25, 1].
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

// ------------------------------------------------------------------------------ le recensement ---

// Une instance de vegetation DESSINABLE.
struct Instance {
  float anchor_x = 0.f;  // ancrage monde (unites GOAL)
  float anchor_z = 0.f;
  float height_m = 0.f;  // hauteur de la plante, metres
  float peak_w = 0.f;    // poids a la couronne, tel que le shader le lit (0 = ne bouge jamais) ;
                         // la flexion en metres est `bend_metres() * peak_w`, calculee a la lecture
};

// Les trois systemes qui dessinent de la vegetation. Un arbre est identifie par (niveau, systeme,
// index d'arbre, geo) : c'est la granularite a laquelle le rendu sait dire « j'ai soumis ceci ».
enum System : int { kSystemTieStatic = 0, kSystemTieWind = 1, kSystemShrub = 2 };

// Remplace integralement le lot d'instances d'un arbre. Appele au chargement de niveau, du meme
// point que le recensement existant. Un rechargement de niveau ecrase, il n'accumule pas.
void set_tree(const std::string& level, int system, int tree, int geo, std::vector<Instance>&& v);

// Oublie tous les arbres d'un niveau pour un systeme : appele quand le renderer lache le niveau.
// Sans lui, un niveau decharge resterait « dessine » dans la population et formerait des paires
// avec le niveau voisin qui le remplace.
void forget(const std::string& level, int system);

// Cet arbre a ete SOUMIS au moins une fois. Sans cette marque, ses instances ne comptent pas :
// une porte qui juge des instances jamais dessinees ne mesure pas ce que l'owner voit.
void mark_drawn(const std::string& level, int system, int tree, int geo);

// Tous les prototypes du niveau qu'aucune ligne du lexique de vegetation ne couvre. Publie tel
// quel : la porte ne peut pas prouver la COMPLETUDE du lexique (un palmier absent du lexique
// n'entre pas dans la population), donc le residu est publie en clair a cote d'elle.
void note_unclassified(const std::string& level, int tree, u32 count);

// Une image de plus. Appelee par chaque renderer ; ne compte qu'une fois par `frame_idx`.
// Recalcule et publie toutes les `kRepublishFrames` images.
void frame(u64 frame_idx);

// Valeur publiee quand AUCUNE paire n'a pu etre examinee. Ce n'est pas 0, deliberement.
constexpr u64 kNoMeasurement = 999999;

}  // namespace foliage_wind
