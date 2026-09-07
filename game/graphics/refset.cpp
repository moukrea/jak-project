#include "game/graphics/refset.h"

#include <algorithm>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <map>
#include <mutex>
#include <set>
#include <string>
#include <system_error>
#include <utility>
#include <vector>

#include "common/util/FileUtil.h"

#include "game/graphics/fixed_tick.h"
#include "game/graphics/origin_ablate.h"
#include "game/graphics/opengl_renderer/lighting_census.h"
#include "game/graphics/render_pace.h"
#include "game/system/autoport_proof.h"
#include "game/system/pad_replay.h"

#include "third-party/fpng/fpng.h"

#if defined(__ANDROID__)
#include <dlfcn.h>
#include <sys/system_properties.h>
#endif

namespace refset {
namespace {

// ── le plan ─────────────────────────────────────────────────────────────────────────────────
// TROIS jeux x huit creneaux horaires. Les huit heures sont les huit creneaux de
// `mood-lights-table` (SPEC §3.1) espaces de trois heures : c'est la grille sur laquelle la
// donnee de Naughty Dog est art-dirigee.
constexpr int kHours[8] = {0, 3, 6, 9, 12, 15, 18, 21};

// ── LES VANTAGES : TOUS LES NIVEAUX, EXTERIEURS ET INTERIEURS ────────────────────────────────
// [O] owner 2026-09-07 : « Faut quand meme mesurer aussi les interieurs, mais faut mesurer aussi
// les exterieurs, et je pense que plus que juste Sandover Village histoire d'etre carre ! Geyser
// Rock, Sandover Village en exterieur et interieur de Hutte, Rock Village, le Volcan, le Swamp,
// la cite Precursor sous l'eau, le niveau de neige, lava tube, etc... Tous les niveaux ! »
//
// POURQUOI CE CHAMP EXISTE. Jusqu'au 2026-09-07 le plan tenait 24 etapes A UN SEUL POINT — la
// hutte de Sandover, camera dans le hall, ZERO pixel de ciel. C'est ce qui a laisse passer le
// ciel blanc de `lighting-hdr` : la garde ne pouvait pas voir un defaut qu'aucune de ses 24
// images ne contenait. Le nombre d'images ne servait a rien, c'etait la COUVERTURE qui manquait.
//
// LE JEU EN COMPTE 21 NIVEAUX JOUABLES, PAS 22, et c'est verifiable : `goal_src/jak1/dgos/`
// porte 27 `.gd`, moins `kernel`/`engine`/`game` et `dem`/`int`/`tit` = 21, et
// `level-info.gc` aligne exactement 21 `level-load-info` d'index 1..21 avant `intro`. Les deux
// candidats restants n'existent pas dans le jeu de l'owner : `halfpipe` (level-info.gc:2359,
// `:nickname 'none`) et `test-zone` (:2476) n'ont AUCUN DGO. Ils sont declares ici, pas inventes.
//
// CHAQUE `cont` EST UN `continue-point` VERIFIE dans `goal_src/jak1/engine/level/level-info.gc`
// (une occurrence exacte de la chaine, controlee le 2026-09-07). `pos` surcharge la position de
// depart en METRES (kmachine.cpp:6009, optionnel) ; vide = la position de la donnee de Naughty
// Dog, qui est le choix par defaut parce qu'elle ne se discute pas.
//
// `interieur` / `ciel` NE SONT PAS DECLARES ICI. Ce sont des MESURES : la fraction de pixels
// d'arriere-plan de l'image capturee (voir `sky_fraction`). Un champ « interior = true » serait
// un commentaire, et la porte qui le lirait serait un miroir de sa propre table.
// ── LA CAMERA EST EPINGLEE, ET C'EST CE QUI REND LE CIEL ATTEIGNABLE ────────────────────────
// MESURE DU 2026-09-07 : aucun des 26 points de vue n'atteint 15 % de ciel — le meilleur,
// `beach-start`, en montre 119 pour mille, et huit vues en montrent ZERO. La cause n'est pas le
// choix des continue-points : `target-continue` (target-death.gc:149-167) recopie bien le
// `camera-rot` du continue-point dans le combineur, puis passe la camera en `cam-fixed` PUIS en
// `cam-string`. C'est `cam-string` qui decide la pose finale (cam-states.gc:1579) : elle se
// replace derriere Jak, a hauteur d'epaule, a l'horizontale. Le `camera-rot` de la donnee n'est
// qu'une pose de depart, jetee en quelques images. Un jeu de references bati sur cette camera
// ne peut pas contenir de ciel, quel que soit le continue-point choisi.
// LE GESTE : sous refset, la camera est POSEE, pas suivie. `*external-cam-mode*` a `'locked`
// court-circuite tout le combineur (cam-update.gc:334 -> move-camera-from-pad:169, ou la valeur
// `'locked` coupe aussi la lecture de la manette), et `*save-camera-inv-rot*` est recopie tel
// quel dans `(-> *math-camera* inv-camera-rot)` (cam-update.gc:181-190). On calcule donc la
// pose ICI, en dur, a partir de la SEULE donnee du point de reprise : sa position et le cap de
// Jak. Rien de ce que la camera du jeu produit n'entre dans le calcul.
// CE QUE CA ACHETE EN PLUS, ET CE N'EST PAS UN BONUS ACCESSOIRE : le point de repos de
// `cam-string` etait la premiere source de non-determinisme du rejeu — refset.h le chiffre,
// deux courses identiques le trouvaient a 0,02 m l'une de l'autre et ca suffisait a rendre
// 27000 pixels sur 57600 differents. Une camera calculee de constantes n'a pas de point de
// repos : elle vaut le meme flottant a chaque course.
struct Vantage {
  const char* id;    // prefixe des fichiers ; "" = le vantage historique (hutte de Sandover)
  const char* cont;  // nom du continue-point, tel quel dans level-info.gc
  const char* pos;   // OG_LEVEL_WARP_POS en metres ; "" = la position de la donnee
  const char* level; // le niveau ATTENDU. Celui qui est DESSINE est mesure, pas lu ici.
  uint8_t hours;     // masque sur kHours : bit i = kHours[i]
  // La camera epinglee, en unites entieres — un reglage flottant dont l'arrondi depend du
  // compilateur rendrait deux binaires non comparables.
  int16_t pitch_d;    // degres au-dessus de l'horizontale ; c'est LUI qui ramene du ciel
  int16_t yaw_d;      // degres ajoutes au cap de Jak au point de reprise (positif = droite)
  int16_t dist_dm;    // recul derriere le point de reprise, en decimetres
  int16_t height_dm;  // hauteur au-dessus du point de reprise, en decimetres
};

// Toutes les vues, y compris les interieurs supplementaires, couvrent les huit heures.
constexpr uint8_t kAllHours = 0xff;

// LE PITCH N'EST PAS UN GOUT : IL EST MESURE, VUE PAR VUE. Il vaut 0 partout ou le niveau n'a
// pas de ciel a montrer — la vue garde alors le cadrage de la camera du jeu, a la pose pres —
// et, sur la vue chargee de repondre pour un niveau a ciel, la plus PETITE valeur qui tienne la
// marge. La plus petite : un angle plus haut que necessaire sort le decor du cadre, et un jeu de
// references doit montrer un niveau eclaire, pas une photo du ciel.
// TOURNEE DE CALIBRAGE DU 2026-09-07 09:04 (`OG_REFSET_PITCH_BY_HOUR=0,0,12,0,20,0,30` : le
// creneau porte l'angle, une seule tournee rend quatre angles par vue au lieu de quatre
// tournees). Arriere-plan en pour mille, par angle 0 / 12 / 20 / 30 :
//   beach-start      231  389  512  562      finalboss-start  491  823  995 1000
//   firecanyon-start 121  335  504  692      ogre-start       206  406  558  691
//   snow-start       362  508  620  611      training-start    81  211  374  583
//   jungle-start      31   93  172  311      rolling-start     21   95  201  385
//   misty-start        0   27  111  277      village3-start     0    5   92  251
//   village2-start    46  113  193  268      swamp-start        8    7    8   40
//   village1-out       4    8    9   19      sunkenb-start      0    0    0    0
//   legacy, jungle-tower, sunken, maincave, darkcave, robocave, lavatube, citadel : 0 partout
// `finalboss-start` montre pourquoi le plafond de `kSkyCeilPm` existe : a 20 degres il rend 995
// pour mille, c'est-a-dire le VIDE. Son angle est donc 0, ou il rend 491 avec du decor.
// Les vues que l'angle ne sauve pas se TOURNENT (`yaw_d`), pas se lever : voir plus bas.
constexpr Vantage kVantages[] = {
    // le vantage HISTORIQUE — hall de la hutte de Samos, Sandover. Prefixe vide : ses fichiers
    // restent `<jeu>/hHH.png`, octet pour octet la ou les items precedents les ont laisses.
    {"", "village1-hut", "-116 14 40", "village1", kAllHours, 0, 0, 30, 15},
    // Sandover en EXTERIEUR (l'owner nomme les deux separement). LE POINT DE REPRISE EST
    // `village1-hut`, PAS `village1-warp`, ET C'EST MESURE : `village1-warp` porte le drapeau de
    // tache `sage-ecorocks` (level-info.gc:190), et y arriver DECLENCHE une cinematique — 1798
    // lignes `CINELIVE scene=sage-intro-sequence-d1` dans la tournee d'essai du 2026-09-07. Une
    // scene est cadencee par son FLUX AUDIO, pas par l'image : le nombre de frames de logique
    // pour atteindre un instant donne de la scene depend de la machine, et les deux photos de ce
    // vantage seraient prises a des instants differents de la scene. On garde donc le seul
    // continue-point de village1 SANS drapeau (`village1-hut`) et on pose la position du gate de
    // warp — le meme endroit, sans la tache.
    // LA CAMERA EST HAUTE ET REGARDE LEGEREMENT VERS LE BAS, et c'est mesure. Au niveau du
    // sol de la porte de warp (-126, 46, 212) la vue est BOUCHEE : 0 a 81 pour mille sur
    // huit angles et quatre reculs. La sonde a nomme la cause — a 20 m au-dessus du point
    // l'image est encore couverte a 100 %, a 50 m elle est du ciel pur (1000 pour mille) :
    // le point de reprise est sous une masse de relief. A 50 m et -8 degres on retrouve le
    // village dessous et le ciel dessus : 300 pour mille. Tournee du 2026-09-07 09:33,
    // hauteur 50 m : -25 deg -> 0, -15 deg -> 116, -8 deg -> 300.
    {"village1-out", "village1-hut", "-126 46 212", "village1", kAllHours, -8, 0, 0, 500},
    {"beach-start", "beach-start", "", "beach", kAllHours, 12, 0, 50, 30},
    // Geyser Rock
    {"training-start", "training-start", "", "training", kAllHours, 20, 0, 50, 30},
    {"jungle-start", "jungle-start", "", "jungle", kAllHours, 30, 0, 50, 30},
    {"jungle-tower", "jungle-tower", "", "jungleb", kAllHours, 0, 0, 50, 25},
    {"misty-start", "misty-start", "", "misty", kAllHours, 30, 0, 50, 30},
    {"misty-bike", "misty-bike", "", "misty", kAllHours, 0, 0, 50, 25},
    {"firecanyon-start", "firecanyon-start", "", "firecanyon", kAllHours, 12, 0, 50, 30},
    // Rock Village
    {"village2-start", "village2-start", "", "village2", kAllHours, 30, 0, 50, 30},
    {"village2-dock", "village2-dock", "", "village2", kAllHours, 0, 0, 50, 25},
    // la cite Precursor sous l'eau
    {"sunken-start", "sunken-start", "", "sunken", kAllHours, 0, 0, 50, 25},
    // `sunkenb` porte `:sky #t` dans la donnee mais `sunkenb-start` n'en montre RIEN : 0 pour
    // mille sur quatre pitchs ET quatre caps. Son autre point de reprise, `sunkenb-helix`
    // (level-info.gc:926), donne sur le puits de la helice.
    // `sunkenb` PORTE `:sky #t` DANS LA DONNEE ET N'EN MONTRE AUCUN. Mesure du 2026-09-07 :
    // ses DEUX points de reprise, sondes a huit placements de camera (pitch 0/12/20/30/45/60,
    // cap 0/90/180/270, hauteur 3/10/20/30/50 m), rendent 0 pour mille a chaque fois. Le
    // niveau est le sous-niveau immerge du palais : son ciel n'est jamais a l'ecran. Le couple
    // (sunkenb, chaque creneau) est donc compte MANQUANT par `refset_sky_missing`, avec sa
    // valeur mesuree — on ne retire pas le niveau de la liste pour verdir la porte.
    {"sunkenb-start", "sunkenb-start", "", "sunkenb", kAllHours, 0, 0, 50, 25},
    {"sunkenb-helix", "sunkenb-helix", "", "sunkenb", kAllHours, 20, 0, 50, 30},
    // le Swamp, dehors et dans une de ses grottes
    // Le ciel du Swamp ne se voit pas depuis `swamp-start` : mesure du 2026-09-07, 40 pour
    // mille au mieux sur quatre pitchs et 57 sur quatre caps — la vue est sous la canopee.
    // C'est le DOCK qui donne sur l'eau et sur le ciel ; `swamp-dock1` (level-info.gc:1026)
    // est un continue-point sans drapeau de tache.
    // Tournee du 2026-09-07 09:28 : 20 deg a 10 m -> 274 pour mille, a 25 m -> 569, et
    // 45 deg au sol -> 402. On garde le plus SOBRE des trois qui passent.
    {"swamp-dock1", "swamp-dock1", "", "swamp", kAllHours, 20, 0, 50, 100},
    {"swamp-start", "swamp-start", "", "swamp", kAllHours, 0, 0, 50, 25},
    {"swamp-cave1", "swamp-cave1", "", "swamp", kAllHours, 0, 0, 50, 25},
    {"rolling-start", "rolling-start", "", "rolling", kAllHours, 30, 0, 50, 30},
    {"ogre-start", "ogre-start", "", "ogre", kAllHours, 12, 0, 50, 30},
    // le Volcan (Volcanic Crater)
    {"village3-start", "village3-start", "", "village3", kAllHours, 30, 0, 50, 30},
    // le niveau de neige
    {"snow-start", "snow-start", "", "snow", kAllHours, 0, 0, 50, 30},
    {"snow-fort", "snow-fort", "", "snow", kAllHours, 0, 0, 50, 25},
    {"maincave-start", "maincave-start", "", "maincave", kAllHours, 0, 0, 50, 25},
    {"darkcave-start", "darkcave-start", "", "darkcave", kAllHours, 0, 0, 50, 25},
    {"robocave-start", "robocave-start", "", "robocave", kAllHours, 0, 0, 50, 25},
    // le tube de lave
    {"lavatube-start", "lavatube-start", "", "lavatube", kAllHours, 0, 0, 50, 25},
    {"citadel-start", "citadel-start", "", "citadel", kAllHours, 0, 0, 50, 25},
    {"finalboss-start", "finalboss-start", "", "finalboss", kAllHours, 0, 0, 50, 30},
};
constexpr int kNumVantages = (int)(sizeof(kVantages) / sizeof(kVantages[0]));

// ── L'ETAT DE LA CAMERA EPINGLEE ────────────────────────────────────────────────────────────
// `g_spawn_*` vient du POINT DE REPRISE lui-meme, releve par `level_warp_run` juste avant le
// `(start 'play ...)` : la position que le jeu va donner a Jak, et le cap que son quaternion
// porte. Deux constantes de la donnee de Naughty Dog, pas une lecture de l'etat du jeu — donc
// la meme valeur a chaque course, quel que soit le temps qu'a mis le disque.
struct CamTune {
  int16_t pitch_d, yaw_d, dist_dm, height_dm;
  bool set = false;
};
bool g_pose_known = false;
float g_spawn_m[3] = {0.f, 0.f, 0.f};
float g_spawn_yaw_deg = 0.f;
uint64_t g_cam_pins = 0;   // images ou la pose a ete rendue au fil GOAL
uint64_t g_cam_asks = 0;   // ... et images ou GOAL l'a demandee. Egaux = jamais un repli muet.
int g_cam_armed = 1;       // `OG_REFSET_CAM_OFF=1` rend la camera du jeu : bras de controle
// Surcharges d'etalonnage, une par vantage. `OG_REFSET_CAM=<id>:<pitch>:<yaw>:<dist>:<haut>,...`
// existe pour trouver les angles SANS rebatir ; les valeurs retenues finissent dans `kVantages`
// et la preuve tourne sans la variable. `refset_cam_overrides` publie combien en ont recu une :
// une reference capturee sous une surcharge non declaree serait irreproductible.
CamTune g_cam_tune[kNumVantages];
uint64_t g_cam_overrides = 0;
// Le masque d'heures REELLEMENT parcouru (voir `OG_REFSET_HOURS`). 0xff = le plan complet.
uint8_t g_hours_mask = 0xff;
// L'ETALONNAGE DES ANGLES, EN UNE SEULE TOURNEE. Trouver le pitch qui ramene 15 % de ciel dans
// 26 niveaux demandait une course par angle, et une course paie 26 chargements de niveau — 26
// minutes dont 20 de disque. `OG_REFSET_PITCH_BY_HOUR=0,10,20,30` fait porter au CRENEAU la
// valeur du pitch : le plan garde sa structure, les quatre photos d'un vantage sont prises a
// quatre angles, et une seule tournee rend la table complete. Vide = les angles de `kVantages`,
// c'est-a-dire le plan que la porte exige. `refset_pitch_by_hour` publie ce qui a tourne.
int g_pitch_by_hour[8] = {-1, -1, -1, -1, -1, -1, -1, -1};
int g_pitch_sweep = 0;
// LE MEME LEVIER SUR LE CAP. Mesure du 2026-09-07 : `village1-out` reste entre 4 et 19 pour
// mille de ciel du pitch 0 au pitch 30 — l'angle n'y peut rien, la vue regarde un relief. Ce
// qui manque a ce point de vue n'est pas de lever la tete, c'est de se TOURNER.
// `OG_REFSET_YAW_BY_HOUR=0,90,180,270` balaie les caps de la meme facon.
int g_yaw_by_hour[8] = {0, 0, 0, 0, 0, 0, 0, 0};
int g_yaw_sweep = 0;
// ET LE MEME LEVIER SUR LES QUATRE REGLAGES A LA FOIS. Mesure du 2026-09-07 : `swamp-start` ne
// depasse pas 57 pour mille sur les quatre caps, et `village1-out` 19 sur les quatre pitchs. Ce
// qui manque a ces vues n'est ni de lever la tete ni de se tourner : c'est de se PLACER
// ailleurs. `OG_REFSET_CAM_BY_HOUR="20:0:50:100,20:0:50:200,..."` (pitch:cap:recul:hauteur, un
// jeu par creneau) balaie les quatre ensemble, et une seule tournee de trois minutes tranche.
CamTune g_cam_by_hour[8];
int g_cam_hour_sweep = 0;

struct Step {
  // 1 = ORIGINE-TOTAL (master OFF) ; 2 = RECHARGED (master ON + eclairage ON, prereglage fige) ;
  // 3 = ORIGINE-LUMIERE (master ON, eclairage OFF) — la configuration que le joueur LANCE.
  int phase;
  int hour;
  int vant;  // index dans kVantages
};

// Frames de LOGIQUE. Elles ne dependent pas de la cadence : `pad_replay` force un pas de
// 1/60 s par image des l'ancre.
constexpr int64_t kAnchorSettle = 300;  // 5 s apres le premier warp : le niveau est charge et lie
// Frames de logique entre le TELEPORT d'une etape et sa photo. Reglable par
// `OG_REFSET_SETTLE` : c'est le seul curseur du compromis « la camera n'a pas encore diverge »
// contre « l'heure et le lissage de la lumiere sont poses ». Le regler ne demande pas de rebatir.
int64_t g_step_settle = 180;
// Frames de logique entre le teleport d'une etape qui CHANGE DE VANTAGE et sa photo. Un
// `(start 'play <continue>)` vers un autre niveau rend la main avant que ce niveau soit
// resident : le chargement est asynchrone, et sa duree depend du disque. Le settle ordinaire
// (180 = 3 s) suffit pour un re-teleport dans un niveau deja charge, pas pour une arrivee.
// C'est la meme mine que celle deja payee a l'etape 0 (refset.h, bloc `wants_rewarp`) : une
// camera qui se pose contre une geometrie incomplete trouve son point de repos ailleurs a
// chaque course. `OG_REFSET_LOAD_SETTLE` le regle sans rebatir. `refset_load_steps` publie
// combien d'etapes en ont beneficie : a zero, la clause serait vide.
// LA VALEUR PAR DEFAUT COMPTE, ET PAS SEULEMENT POUR LE CONFORT. `lib/proof_run.sh` pose
// l'environnement de `proof_env` (backlog.yaml), qui ne porte AUCUN reglage de settle : la
// course de preuve tourne donc au defaut. Une capture faite sous `OG_REFSET_LOAD_SETTLE=600` et
// rejouee au defaut de 900 photographierait d'autres instants de logique, et `maxdiff` ne
// pourrait pas valoir 0 — un rouge dont la cause ne ressemble pas a son symptome. On regle donc
// le DEFAUT, et plus aucun lanceur ne passe la variable. 600 est tenu par la mesure : tournee
// du 2026-09-07, `refset_load_margin_min = 475` sur 600, c'est-a-dire que le pire niveau est
// devenu dessinable 125 frames apres son teleport.
int64_t g_load_settle = 600;
// L'INSTANT ABSOLU DU PREMIER TELEPORT (frames de LOGIQUE). Voir `warp_at_frame` dans refset.h :
// le delai apres readiness de `level_warp_maybe` depend du disque, et son ecart d'UNE frame
// entre la capture et le rejeu du 2026-09-06 a suffi a rendre `refpix_maxdiff_origine=232`.
// LA VALEUR N'EST PAS LIBRE VERS LE HAUT. Essayee a 900, la course MEURT avant le teleport :
// mesure du 2026-09-06 sur eae4df44, `signal 4` a la frame 782 avec `A36-TREE at-crash
// viol-total=0` — donc PAS la corruption d'arbre du teleport repete, un autre defaut, atteint
// en restant 300 images de plus sur l'ecran-titre. On ne repousse donc pas l'instant : on le
// FIXE la ou il tombait deja. Mesure des deux courses precedentes : `warp1 lf=600` puis
// `lf=599`, c'est-a-dire readiness atteinte des la premiere image et 600 ticks de delai. 600 en
// frames de LOGIQUE reproduit cet instant sans heriter de la vitesse du disque.
int64_t g_warp_at = 600;

constexpr int kShotW = 320;
constexpr int kShotH = 180;

std::mutex g_mutex;

int g_mode = 0;  // 0 = eteint, 1 = capture, 2 = replay
// lighting-hdr : le dossier par defaut DIFFERE par plateforme, et ce n'est pas une precaution
// de style. Les references x86 sont re-rendues en 320x180 en resolution interne ; celles de
// l'appareil sont un sous-echantillonnage d'un tampon 4:3. Comparer les unes aux autres est faux
// PAR CONSTRUCTION. On rend donc le melange impossible au point de PRODUCTION plutot que
// detectable au point de controle : les deux familles ne portent pas le meme nom.
std::string g_dir = ".autoport/refset";  // Android : rendu ABSOLU a l'init, voir `enabled()`

std::vector<int> g_phases;  // lighting-hdr : les phases que CE plan execute
std::vector<int> g_vants;   // lighting-census : les vantages que CE plan parcourt
std::vector<Step> g_steps;
// Les grandeurs de COUVERTURE, une entree par vantage retenu, remplies a la photo.
struct VantStat {
  uint64_t shots = 0;          // photos prises a ce vantage (tous jeux, tous creneaux)
  uint64_t bg_px_min = ~0ull;  // pixels d'arriere-plan : le minimum sur ses photos
  uint64_t bg_px_max = 0;      // ... et le maximum
  uint64_t px = 0;             // le denominateur : pixels de l'image
  uint64_t maxdiff = 0;        // le pire ecart de rejeu de ce vantage
  uint64_t level_ok = 0;       // photos ou le niveau ATTENDU etait bien en service
  // LE MEME TRIO, VENTILE PAR CRENEAU HORAIRE. La porte de l'owner porte sur un COUPLE
  // (niveau a ciel, heure fixe) : « pour chaque couple le ciel occupe >= 15 % ». Un minimum
  // agrege sur les huit heures ne peut pas repondre a cette question — il dirait « cette vue
  // montre le ciel » alors que le creneau de 0 h n'en montre pas. Un agregat par vue etait
  // exactement la faiblesse que le superviseur a nommee le 2026-09-07.
  uint64_t shots_h[8] = {0};
  uint64_t level_ok_h[8] = {0};
  uint64_t bg_min_h[8] = {~0ull, ~0ull, ~0ull, ~0ull, ~0ull, ~0ull, ~0ull, ~0ull};
  uint64_t px_h[8] = {0};
};
std::vector<VantStat> g_vstats;  // indexe comme g_vants
uint64_t g_load_steps = 0;       // etapes qui ont recu le settle de CHARGEMENT
// LES NIVEAUX REELLEMENT EN SERVICE AU MOMENT D'UNE PHOTO. Le nom vient du chargeur
// (`LevelData::level->level_name`), jamais de `kVantages[].level` : une porte qui compterait les
// lignes de sa propre table ne mesurerait rien.
std::set<std::string> g_levels_seen;
// QUELS NIVEAUX ONT UN CIEL — LU DANS LA DONNEE DE NAUGHTY DOG, PAS DEVINE NI MESURE.
// `level-load-info` porte un champ `sky` (`goal_src/jak1/engine/level/level-h.gc:108`) et c'est
// LUI qui decide, cote jeu, si le ciel est dessine pour ce niveau : `sky-tng.gc:901` teste
// exactement `(-> *level* level i info sky)` avant d'emettre le DMA du ciel. Le fil GOAL le
// recopie ici a chaque image pour les niveaux ACTIFS (`pc-refset-note-level`).
// POURQUOI PAS UNE MESURE DE PIXELS. La porte demande « pour chaque niveau a ciel, le ciel
// occupe >= 15 % de l'image ». Si l'appartenance a la liste se decidait sur les memes pixels,
// la porte serait un miroir de sa propre sortie : un point de vue qui regarde un mur sortirait
// de la liste et la porte resterait verte. La liste vient donc de la DONNEE, la porte des
// PIXELS, et les deux ne partagent aucune variable.
// POURQUOI PAS `kVantages[].level` NON PLUS : ce serait compter les lignes de ma propre table.
std::map<std::string, int> g_level_sky;
// Les niveaux en service pour LA PHOTO EN COURS. Vide a chaque armement de capture. Sert a une
// chose precise : un monde qui n'a pas fini de charger ne dessine RIEN, donc sa profondeur reste
// a la valeur d'effacement et l'image se lit comme « 100 % de ciel ». Mesure du 2026-09-07 :
// `citadel-start` (un niveau a `:sky #f`) rendait 934 a 1000 pour mille d'arriere-plan. Sans ce
// filtre, `refset_sky_views` compterait les vantages RATES comme des vues de ciel — un faux vert
// fabrique par l'instrument lui-meme.
std::set<std::string> g_frame_levels;
// LA MARGE DE L'ATTENTE DE CHARGEMENT, MESUREE ET PAS SUPPOSEE. `g_load_settle` est une duree
// FIXE : c'est ce qui rend la course rejouable, mais c'est aussi un pari sur la duree du pire
// chargement. Le fil GRAPHIQUE leve `g_vant_level_seen` la premiere fois que le niveau ATTENDU
// devient dessinable (il ne peut pas lire l'horloge de logique, qui vit dans la memoire GOAL) ;
// le fil GOAL date l'evenement et publie `refset_load_margin_min` = le plus petit nombre de
// frames restant avant le second teleport. Une marge large dit que le pari est tenu ; une marge
// de quelques frames dit que la prochaine course a une chance de photographier un monde absent.
bool g_vant_level_seen = false;
int64_t g_load_margin_seen_lf = -1;
int64_t g_load_margin_min = -1;
uint64_t g_load_margin_measured = 0;  // arrivees ou le niveau est apparu avant le second warp
uint64_t g_probe_frames = 0;  // images ou la sonde de profondeur a tourne
uint64_t g_probe_px = 0;      // pixels de profondeur relus au total : le denominateur

// LES 21 NIVEAUX JOUABLES, pour pouvoir NOMMER ceux qui manquent au lieu de publier un trou.
// Source : `goal_src/jak1/dgos/*.gd` (27 `.gd` moins kernel/engine/game et dem/int/tit) et les
// 21 `level-load-info` d'index 1..21 de `level-info.gc`.
constexpr const char* kPlayableLevels[] = {
    "training", "village1", "beach",    "jungle",  "jungleb",  "misty",    "firecanyon",
    "village2", "sunken",   "sunkenb",  "swamp",   "rolling",  "ogre",     "village3",
    "snow",     "maincave", "darkcave", "robocave", "lavatube", "citadel", "finalboss",
};
constexpr int kNumPlayableLevels = (int)(sizeof(kPlayableLevels) / sizeof(kPlayableLevels[0]));
size_t g_cur = 0;  // etape en cours
bool g_finished = false;

int g_tod_x100 = -1;

// lighting-hdr essai 7 — LE FEU DE LA HUTTE A UNE SECONDE HORLOGE, ET ELLE BAT PAR IMAGE
// DESSINEE. `update-mood-flames` (mood.gc:366) incremente un compteur prive de `flames-state`
// une fois par appel, et son appelant `update-time-of-day` pend a `real-main-draw-hook`
// (drawable.gc:839), DEHORS de la boucle de rattrapage : il tourne donc une fois par image
// DESSINEE, pas par frame de logique. Le poids qu'il produit (`times[5].w`) part dans
// `interp_time_of_day` et repeint tfrag, tie, shrub, hfrag et l'herbe autour du foyer — une
// region large, douce, de signe alterne. C'est EXACTEMENT la classe de defaut deja fermee pour
// les particules, le vent et l'herbe, et elle etait restee ouverte pour le mood.
// Au passage : le rebouclage de l'etat consomme trois tirages de `rand-vu` (mood.gc:357-361),
// donc un decalage d'images dessinees decale aussi le flux d'alea de TOUS les autres
// consommateurs.
// LE GESTE : sous refset, l'etat de flamme est repose a une valeur FIXE a chaque appel — meme
// phase, meme hauteur, meme longueur pour les 24 photos. Le feu reste dessine et reste la haute
// lumiere dominante ; on retire son scintillement de la comparaison, pas l'objet mesure. Hors
// refset, `mood_flame_pin()` rend -1 et le chemin d'origine est intact.
constexpr int kMoodPinTime = 3;  // 3/12 de periode : sin(45 deg) = 0,707, ni zero ni sommet
uint64_t g_mood_calls = 0;       // appels a `mood_flame_pin()` depuis le debut de la course
uint64_t g_mood_pins = 0;        // ... dont ceux qui ont reellement repose l'etat
uint64_t g_mood_last_photo = 0;  // valeur de `g_mood_calls` a la photo precedente
uint64_t g_mood_span_min = ~0ull;  // images DESSINEES entre deux photos : le minimum
uint64_t g_mood_span_max = 0;      // ... et le maximum. min != max => la fuite etait vivante.
// L'INVITE 2D DU MAIRE. Contrat et mesure : refset.h. `g_text_last_lf` est la derniere frame
// de LOGIQUE ou `print-game-text` a ete appele ; comparee a celle de la photo, elle dit si le
// texte etait a l'ecran a cet instant precis, sans supposer quoi que ce soit de sa cadence.
uint64_t g_text_calls = 0;          // appels a `text_mute()` depuis le debut de la course
uint64_t g_text_muted = 0;          // ... dont ceux qui ont reellement force le mode no-draw
int64_t g_text_last_lf = -1;        // frame de logique du dernier appel
uint64_t g_text_steps_with = 0;     // photos ou le texte AURAIT ete dessine
uint64_t g_text_steps_without = 0;  // ... et celles ou non

// ── demande de capture, du fil GOAL vers le fil graphique ───────────────────────────────────
// UN SEUL automate, et pas trois booleens. Avec trois booleens le fil graphique pouvait
// re-armer la meme demande entre la fin d'une capture et le passage du fil GOAL a l'etape
// suivante : mesure du 2026-09-06, 16 captures annoncees pour 10 fichiers ecrits, les heures
// 03, 15 et 21 SAUTEES dans les deux jeux. Une etape sautee est une reference manquante, et
// une reference manquante rend la porte inoperante sur ce creneau.
// L'ARRIVEE SUR UN NOUVEAU VANTAGE SE FAIT EN DEUX TELEPORTS, PAS UN.
// MESURE DU 2026-09-07 (tournee d'essai, 26 vantages, settle d'arrivee de 300 frames de
// logique) : `refset_levels=14` sur 21, et sept vantages photographies sur un monde ABSENT —
// `citadel-start` 934..1000 pour mille de pixels d'arriere-plan, `finalboss-start` 750..1000,
// `sunkenb-start` 1000. Un `(start 'play <continue>)` vers un AUTRE niveau rend la main avant
// que ce niveau soit resident : la photo tombait pendant le chargement.
// C'est le meme defaut que celui deja ferme a l'etape 0 (refset.h, bloc `wants_rewarp`) et il
// se ferme du meme geste : un PREMIER teleport lance le chargement, on attend `g_load_settle`
// frames de LOGIQUE, puis un SECOND teleport repart d'un monde complet — c'est lui qui pose
// l'ancre, et la photo tombe `g_step_settle` frames apres. Le point de repos de la camera ne
// depend donc plus de la vitesse du disque.
enum CapState {
  kCapIdle = 0,
  kCapPreWarp,   // arrivee : on demande le teleport qui LANCE le chargement
  kCapWaitLoad,  // ... et on attend `g_load_settle` frames de logique
  kCapWaitWarp,
  kCapArmed,
  kCapInFlight,
  kCapDone
};
int g_cap = kCapIdle;
int64_t g_capture_frame = -1;      // la chaine attendue porte cette frame de logique
int64_t g_load_until = -1;         // fin de l'attente de chargement d'une arrivee
int64_t g_vant_base = -1;          // ancre du vantage courant (son teleport d'arrivee)
uint64_t g_prewarps = 0;           // teleports d'arrivee (ceux qui lancent un chargement)
std::string g_capture_name;        // <jeu>/h<hh>

// ── horloge de logique ──────────────────────────────────────────────────────────────────────
// Chaque instant du plan est ancre sur un EVENEMENT (un teleport), jamais sur « l'image ou j'ai
// remarque que... » : une image de logique non rendue ne decale donc rien.
int64_t (*g_logic_fn)() = nullptr;
// UN TELEPORT PAR ETAPE. Le point de repos de la camera depend du chemin : deux courses
// identiques le trouvent a ~0,02 m l'une de l'autre, ce qui suffit a rendre la moitie des pixels
// differents. Un `(start 'play <continue>)` juste avant chaque photo remet la camera a une pose
// TELEPORTEE, et la photo est prise assez tot pour que la derive n'ait pas eu le temps de
// s'installer.
// lighting-hdr essai 6 : le re-ancrage des lanceurs de particules et le gel de leur temps.
// Contrat, chiffres et raison : refset.h, section « LES DEUX GESTES ».
bool g_repin_done = false;
uint64_t g_repins = 0;
int64_t g_repin_lf = -1;
uint64_t g_frozen_frames = 0;
int64_t g_frozen_first_lf = -1;
int64_t g_part_step_lf = -1;
uint64_t g_part_steps = 0;
uint64_t g_part_extra = 0;
int64_t g_warp1 = -1;             // premier warp : sert seulement a savoir que le niveau est la
bool g_rewarp_asked = false;      // une demande de teleport est en vol
int64_t g_rewarp_asked_lf = -1;   // depuis quand : une demande perdue doit se re-poser
int64_t g_step_anchor = -1;       // frame de logique du teleport de l'etape courante
uint64_t g_rewarps = 0;
// UN TELEPORT PAR ETAPE, OU UN SEUL POUR TOUT LE PLAN ? Sur arm64 le plan MEURT au troisieme
// `(start 'play <continue>)` : mesure du 2026-09-06 sur eae4df44, les etapes 0 et 1 capturent
// (`REFSET cap origine/h00`, `h03`) puis
//     GK-DIAG A36-TREE VIOLATION frame=755 tree-self a=0x1dcbd8 b=0x2189d4
//     Process exited due to signal 4
// — une corruption de l'arbre de processus ANTERIEURE a cet item (le scanner d'integrite
// nomme le premier maillon rompu ; il ne fait que LIRE). x86 encaisse les 24 teleports, arm64
// non. Le defaut appartient au redemarrage repete de niveau, pas au jeu de references : on ne
// le corrige pas ici, on cesse de le declencher 24 fois.
// CE QUE LE TELEPORT ACHETAIT reste acquis : le premier re-teleport (etape 0) a toujours lieu,
// et c'est LUI qui rend la pose de la camera independante du chemin de chargement (voir le
// bloc `wants_rewarp` dans refset.h). Les 23 suivants ne faisaient que la re-poser a
// l'identique. Ce qui reste a la charge du determinisme entre deux courses : le pas de temps
// fixe et les graines de `pad_replay`, l'heure du jeu reposee a chaque image, et la
// neutralisation de `render_pace` — tous deja mesures et publies.
// Defaut : 1 sur bureau (le registre de `refset-replay-stable` a ete etabli comme ca, on ne
// change pas la definition de l'instrument sous ses cinq rejeux), 0 sur appareil.
int g_warp_per_step = 1;
// L'ANCRE DU PLAN : la frame de logique du re-teleport de l'etape 0. Quand il n'y a pas de
// teleport par etape, l'instant de chaque photo est CALCULE depuis elle
// (`base + (k+1) * settle`) et jamais lu sur l'horloge au moment ou l'etape s'arme. La
// difference n'est pas cosmetique : l'etape k+1 ne s'arme qu'apres que le fil GRAPHIQUE a
// consomme la photo de l'etape k, donc une lecture d'horloge la ferait dependre de
// l'entrelacement des deux fils — une frame de logique d'ecart, c'est une autre pose de Jak,
// et `refset.h` chiffre deja ce que ca coute (27000 pixels sur 57600).
int64_t g_plan_base = -1;
uint64_t g_late_arms = 0;  // etapes armees APRES leur instant theorique : le plan a pris du retard
// LA CADENCE DU PLAN, ET SON DE-DOUBLONNAGE. Voir `begin_logic_frame` dans refset.h : le plan
// s'avance une fois par frame de LOGIQUE, depuis la lecture de la manette 0, et l'appel depuis
// l'image RENDUE n'est plus qu'un repli. Les deux compteurs disent lequel a reellement cadence.
int64_t g_pumped_lf = -2;
uint64_t g_pump_logic = 0;
uint64_t g_pump_render = 0;
// L'ORDRE DES ETAPES. Voir `enabled()` : par CRENEAU sur appareil (les trois configurations d'une
// meme heure se suivent), par JEU sur bureau (l'instrument de `refset-replay-stable` ne se
// redefinit pas sous ses cinq rejeux).
int g_order_by_hour = 0;
uint64_t g_slip_nonzero = 0;  // captures dont la chaine ne portait PAS la frame demandee
// La frame de logique que porte la chaine EN VOL. Posee par `capture_for_chain` (fil
// GRAPHIQUE, sous le verrou) : `consume_capture` tourne sur ce meme fil et ne peut donc pas
// appeler `current_logic_frame()`, qui lit la memoire GOAL et n'est licite que du fil GOAL.
int64_t g_inflight_lf = -1;

// ── mesures ─────────────────────────────────────────────────────────────────────────────────
uint64_t g_captured = 0;
// L'alpha BRUT du retimeur de rendu, echantillonne une fois par image dessinee. Voir
// `publish_state` : c'est la mesure de ce que la course de reference supprime.
int64_t g_raw_alpha_min = 1 << 30;
int64_t g_raw_alpha_max = -1;
uint64_t g_raw_alpha_n = 0;
uint64_t g_compared = 0;
uint64_t g_missing = 0;
uint64_t g_size_bad = 0;
uint64_t g_decode_bad = 0;
uint64_t g_roundtrip_bad = 0;
uint64_t g_maxdiff = 0;
uint64_t g_diffpx = 0;
// Le maximum PAR JEU. `refset_replay_maxdiff` melange les deux : une regression du seul jeu
// RECHARGED et une derive de la camera qui touche les deux rendent le meme nombre. Les items
// de la refonte doivent pouvoir citer les deux separement (SPEC §7.2, item 1 :
// `refpix_maxdiff_origine` et `refpix_maxdiff_recharged` sont sa condition de sortie).
// lighting-hdr : TROIS jeux desormais (SPEC §7.3). Indices 1..3, la case 0 n'est pas utilisee.
uint64_t g_maxdiff_phase[4] = {0, 0, 0, 0};
uint64_t g_compared_phase[4] = {0, 0, 0, 0};
int64_t g_frame_slip_max = 0;
int64_t g_frame_slip_min = 1 << 20;
// LE REGISTRE DE REJEUX. `refset_replay_flaky` compare des COURSES, pas des images : il ne peut
// donc pas se calculer dans une seule course. Le moteur tient un registre sur disque et publie
// le verdict qu'il en lit. Tant qu'il n'a pas ete ecrit, `publish_state` publie la sentinelle.
bool g_flaky_done = false;
// La porte census exige aussi la couverture et cinq rejeux exacts. Les autres items
// conservent leurs comparaisons historiques, eventuellement sur un sous-plan.
uint64_t g_census_coverage_missing = 1;
uint64_t g_census_replay_gate = 254;
uint64_t g_census_replay_runs = 0;

// lighting-hdr : le TROISIEME jeu, ORIGINE-LUMIERE (SPEC §0.2, §7.3). Il existe parce que ni
// ORIGINE-TOTAL ni RECHARGED n'exercaient la configuration que le joueur LANCE : master ON,
// eclairage de la refonte OFF. Deux bras verts, la condition absente — c'est exactement la ou
// l'owner a trouve les blancs brules le 2026-09-06.
const char* set_name(int phase) {
  if (phase == 1) {
    return "origine";
  }
  return phase == 2 ? "recharged" : "origine-lumiere";
}

// UNE ETAPE QUI ARRIVE SUR UN NOUVEAU VANTAGE. C'est la seule qui paie un chargement de niveau,
// donc la seule qui a besoin du settle long.
bool step_is_arrival(size_t k) {
  if (k >= g_steps.size()) {
    return false;
  }
  return k == 0 || g_steps[k].vant != g_steps[k - 1].vant;
}

// LA PREMIERE ETAPE DU VANTAGE DE L'ETAPE k. Quand une etape ne teleporte pas (politique de
// l'appareil), son instant se calcule depuis l'ancre de SON vantage — pas depuis celle du plan :
// avec 26 vantages, une grille unique partant du debut de la course accumulerait toutes les
// attentes de chargement et n'aurait plus aucun rapport avec l'horloge.
size_t first_step_of_vant(size_t k) {
  if (k >= g_steps.size()) {
    return 0;
  }
  size_t i = k;
  while (i > 0 && g_steps[i - 1].vant == g_steps[k].vant) {
    i--;
  }
  return i;
}

// Le vantage d'une etape. `Step::vant` indexe `g_vants`, qui indexe `kVantages` : le plan peut
// etre restreint sans renumeroter la table.
const Vantage& vantage_of(const Step& s) {
  const size_t i = (size_t)s.vant;
  return kVantages[i < g_vants.size() ? g_vants[i] : 0];
}

// Le prefixe de fichier d'une etape : `<jeu>/hHH` pour le vantage historique, `<jeu>/<id>-hHH`
// pour les autres. Le vantage historique garde son nom NU parce que ses images sont
// l'instrument de `lighting-hdr` et de `lighting-origin-bitexact`.
std::string step_image_name(const Step& s) {
  const Vantage& v = vantage_of(s);
  char nm[128];
  if (v.id[0]) {
    std::snprintf(nm, sizeof(nm), "%s/%s-h%02d", set_name(s.phase), v.id, s.hour);
  } else {
    std::snprintf(nm, sizeof(nm), "%s/h%02d", set_name(s.phase), s.hour);
  }
  return nm;
}

// `setenv` n'existe pas sur MSVC ; le seul appelant est ce module.
void put_env(const char* key, const char* value) {
#if defined(_WIN32)
  _putenv_s(key, value);
#else
  setenv(key, value, 1);
#endif
}

bool read_knob(const char* env, const char* prop, char* out, size_t cap) {
  if (const char* e = std::getenv(env)) {
    if (e[0]) {
      std::snprintf(out, cap, "%s", e);
      return true;
    }
  }
#if defined(__ANDROID__)
  char buf[PROP_VALUE_MAX] = {0};
  if (__system_property_get(prop, buf) > 0 && buf[0]) {
    std::snprintf(out, cap, "%s", buf);
    return true;
  }
#else
  (void)prop;
#endif
  return false;
}

// ── lighting-hdr : les grandeurs des verdicts 1, 2 et 5 ─────────────────────────────────────
// Elles se mesurent SUR CE QUI EST DESSINE (le tampon relu), jamais sur une table source, et
// elles sont ENTIERES de bout en bout : un arrondi flottant dont le mode depend du compilateur
// rendrait deux courses du meme binaire non comparables, et c'est exactement la classe de
// defaut que refset-replay-stable vient de fermer.
// Le jeu de REFERENCE de ces trois verdicts est ORIGINE-LUMIERE (phase 3) : la configuration
// que l'owner joue. Comparer RECHARGED a ORIGINE-TOTAL melangerait l'eclairage avec les
// modeles HD, l'herbe et les textures.
struct StepStats {
  bool measured = false;
  uint64_t px = 0;           // pixels examines
  uint64_t sat_px = 0;       // au moins un canal a 255 — la part qui a perdu toute gradation
  uint64_t sat_white_px = 0; // les TROIS canaux a 255 — le « blanc brule » que l'owner decrit
  uint64_t contrast_x1000 = 0;  // contraste local moyen du decile le plus lumineux
  uint64_t decile_px = 0;    // combien de pixels ce decile contenait
  // LE DENOMINATEUR DES VERDICTS 1 ET 2 : la frame de LOGIQUE de la photo. Les deux verdicts
  // apparient RECHARGED et ORIGINE-LUMIERE au meme creneau ; l'ecart de frames entre les deux
  // photos est ce qui melange l'effet de la courbe et celui du temps qui passe. Sans lui,
  // `hdr_hlc_pct_h21=92` ne dit pas si la courbe a ecrase le detail ou si 1440 images de logique
  // ont deplace ce qui bouge dans le decor.
  int64_t cap_lf = -1;
};
StepStats g_stats[4][8];  // [phase 1..3][index de creneau 0..7]

int hour_index(int hour) {
  for (int i = 0; i < 8; i++) {
    if (kHours[i] == hour) {
      return i;
    }
  }
  return -1;
}

// Luminance entiere en 0..255, ponderation Rec.601 en virgule fixe.
inline uint32_t luma(const uint8_t* p) {
  return (uint32_t)((77u * p[0] + 150u * p[1] + 29u * p[2]) >> 8);
}

void measure_step(int phase, int hour, int64_t cap_lf, const uint8_t* px, int w, int h) {
  const int hi = hour_index(hour);
  if (phase < 1 || phase > 3 || hi < 0 || w < 3 || h < 3) {
    return;
  }
  StepStats st;
  const int64_t n = (int64_t)w * h;
  st.px = (uint64_t)n;

  // Saturation, et histogramme de luminance pour trouver le decile.
  uint64_t hist[256] = {0};
  for (int64_t i = 0; i < n; i++) {
    const uint8_t* p = px + i * 4;
    if (p[0] == 255 || p[1] == 255 || p[2] == 255) {
      st.sat_px++;
      if (p[0] == 255 && p[1] == 255 && p[2] == 255) {
        st.sat_white_px++;
      }
    }
    hist[luma(p)]++;
  }

  // Le seuil du decile le plus lumineux : le plus petit T tel que #{L >= T} <= n/10. On garde
  // le T juste EN DESSOUS, pour que le decile contienne au moins n/10 pixels.
  const uint64_t want = (uint64_t)(n / 10);
  uint64_t acc = 0;
  int thr = 255;
  for (int v = 255; v >= 0; v--) {
    acc += hist[v];
    if (acc >= want) {
      thr = v;
      break;
    }
  }

  // Contraste local : gradient de Manhattan sur le voisin droit et le voisin bas, moyenne sur
  // les seuls pixels du decile. Une zone ecrasee a blanc plat rend zero — c'est precisement le
  // detail que la courbe doit preserver.
  uint64_t gsum = 0, gn = 0;
  for (int y = 0; y + 1 < h; y++) {
    for (int x = 0; x + 1 < w; x++) {
      const uint8_t* p = px + ((int64_t)y * w + x) * 4;
      const uint32_t l = luma(p);
      if ((int)l < thr) {
        continue;
      }
      const uint32_t lr = luma(px + ((int64_t)y * w + (x + 1)) * 4);
      const uint32_t lb = luma(px + ((int64_t)(y + 1) * w + x) * 4);
      gsum += (uint64_t)(l > lr ? l - lr : lr - l);
      gsum += (uint64_t)(l > lb ? l - lb : lb - l);
      gn++;
    }
  }
  st.decile_px = gn;
  st.contrast_x1000 = gn ? (gsum * 1000ull) / gn : 0ull;
  st.measured = true;
  st.cap_lf = cap_lf;
  g_stats[phase][hi] = st;
  // Les images DESSINEES depuis la photo precedente. C'est la grandeur qui variait sous le plan
  // et que rien ne publiait : le plan compte des frames de LOGIQUE, le mood et la passe de
  // textures comptent des images dessinees.
  {
    const uint64_t span = g_mood_calls - g_mood_last_photo;
    g_mood_last_photo = g_mood_calls;
    if (span < g_mood_span_min) {
      g_mood_span_min = span;
    }
    if (span > g_mood_span_max) {
      g_mood_span_max = span;
    }
  }
  // LE RECENSEMENT DE L'INVITE, ETAPE PAR ETAPE. `print-game-text` est appele a chaque image de
  // logique ou le texte est visible : si le dernier appel porte la frame de la photo (ou celle
  // d'avant, l'appel precedant l'incrementation du compteur), le texte etait a l'ecran. C'est ce
  // partage — dix photos contre quatorze — qui rend la neutralisation non vacue.
  if (cap_lf >= 0 && g_text_last_lf >= 0 && g_text_last_lf + 1 >= cap_lf) {
    g_text_steps_with++;
  } else {
    g_text_steps_without++;
  }
}

uint64_t read_capture_witness(int phase);  // defini plus bas, avec le temoin de capture

// Le temoin de capture est ecrit et relu plus bas (section « LE TEMOIN DE CAPTURE ») ;
// `publish_state` le publie, d'ou cette declaration avant usage.
std::string read_capture_flavour(int phase);

// La SAVEUR du binaire courant : `ablate` = la couche Recharged n'est pas compilee dedans
// (game/graphics/origin_ablate.h), `normal` = le binaire de l'owner.
const char* build_flavour() {
#if AUTOPORT_ORIGIN_ABLATE
  return "ablate";
#else
  return "normal";
#endif
}

// ── LA COUVERTURE (owner 2026-09-07 : « Tous les niveaux ! ») ────────────────────────────────
// Trois portes, trois grandeurs, aucune lue dans `kVantages` :
//   `refset_levels`          niveaux distincts en service au moment d'une photo, nommes par le
//                            CHARGEUR. `refset_levels_missing` compte ceux des 21 jouables qui
//                            n'ont jamais ete vus, et `refset_levels_missing_list` les NOMME :
//                            un trou anonyme n'est pas un constat.
//   `refset_sky_views`       vues dont la photo la MOINS ciel porte >= 15 % d'arriere-plan. Le
//                            minimum, pas la moyenne : une vue qui ne montre le ciel qu'a une
//                            heure sur deux ne garde pas le ciel de l'autre.
//   `refset_interior_views`  vues dont la photo la PLUS ciel porte <= 1 % d'arriere-plan.
// `refset_bg_min_pm_<vue>` / `_max_pm_` publient la grandeur brute en pour-mille : sans elles,
// les trois compteurs seraient des verdicts sans mesure derriere.
// ── LA PORTE DU CIEL (owner 2026-09-07) ─────────────────────────────────────────────────────
// « Assures toi de bien tester tous les niveaux qui ont un ciel avec ont bien le ciel visible a
// l'ecran, aussi faut tester a differents moment de la journee [...] avec des heures fixes ».
// Deux grandeurs, et elles ne partagent AUCUNE variable :
//   `refset_sky_levels`   la liste, etablie par la DONNEE du jeu (`level-load-info.sky`, recopiee
//                         par le fil GOAL dans `g_level_sky`). Ni ma table de vantages, ni les
//                         pixels : une porte calculee sur ses propres sorties est un miroir.
//   `refset_sky_missing`  le nombre de COUPLES (niveau a ciel, heure fixe) dont aucune vue ne
//                         montre >= 150 pour mille d'arriere-plan. Le produit complet, pas une
//                         moyenne : c'est un agregat par vue qui a laisse passer le ciel blanc.
// Une vue dont le niveau attendu n'etait pas en service a la photo ne peut pas repondre pour ce
// couple : un monde absent ne dessine rien, donc toute sa profondeur reste a l'effacement et il
// se lirait « 100 % de ciel » (mesure du 2026-09-07 : `citadel-start` 934..1000 pour mille).
// `refset_sky_missing_list` NOMME les couples manquants : un trou anonyme n'est pas un constat.
constexpr uint64_t kSkyFloorPm = 150;  // 15 % de l'image, le seuil de l'owner
// ET UN PLAFOND, PARCE QUE LA SONDE MESURE L'ARRIERE-PLAN, PAS LE CIEL. Un pixel qu'aucune
// surface n'a couvert se lit « arriere-plan » — que ce soit du ciel ou le VIDE vu depuis une
// camera posee dans un mur. Sans plafond, la facon la plus simple de rendre la porte verte
// serait de mal placer la camera, et c'est exactement le genre de faux vert que cet item
// existe pour fermer. Une vue qui ne montre presque aucun decor ne repond donc pour aucun
// couple. Mesure du 2026-09-07 : la vue la plus ouverte du jeu, `firecanyon-start` a 30
// degres, rend 692 pour mille — le plafond ne mord sur aucune vue reelle.
constexpr uint64_t kSkyCeilPm = 900;

void publish_sky_gate() {
  std::string sky_list;
  uint64_t nsky = 0;
  // La liste ne retient que les 21 niveaux JOUABLES : `default-level` et les niveaux de
  // service portent aussi un `:sky`, et ils ne sont le sujet d'aucune photo.
  for (int i = 0; i < kNumPlayableLevels; i++) {
    auto it = g_level_sky.find(kPlayableLevels[i]);
    if (it == g_level_sky.end() || !it->second) {
      continue;
    }
    nsky++;
    sky_list += sky_list.empty() ? "" : "+";
    sky_list += kPlayableLevels[i];
  }
  autoport_proof::publish("refset_sky_levels_n", nsky);
  autoport_proof::publish_text("refset_sky_levels", sky_list.empty() ? "aucun" : sky_list.c_str());
  // Les niveaux dont le fil GOAL n'a JAMAIS rendu compte : sans eux, un niveau jamais visite
  // sortirait de la liste des niveaux a ciel et allegerait la porte en silence.
  {
    std::string unknown;
    uint64_t nunk = 0;
    for (int i = 0; i < kNumPlayableLevels; i++) {
      if (g_level_sky.count(kPlayableLevels[i])) {
        continue;
      }
      nunk++;
      unknown += unknown.empty() ? "" : "+";
      unknown += kPlayableLevels[i];
    }
    g_census_coverage_missing += nunk;
    autoport_proof::publish("refset_sky_unknown_n", nunk);
    autoport_proof::publish_text("refset_sky_unknown", unknown.empty() ? "aucun" : unknown.c_str());
  }

  uint64_t missing = 0;
  std::string miss_list;
  uint64_t worst_pm = 1000;  // le pire couple : la marge quand la porte est tenue
  for (int li = 0; li < kNumPlayableLevels; li++) {
    const char* lev = kPlayableLevels[li];
    auto it = g_level_sky.find(lev);
    if (it == g_level_sky.end() || !it->second) {
      continue;
    }
    for (int hi = 0; hi < 8; hi++) {
      uint64_t best_pm = 0;
      bool answered = false;
      for (size_t vi = 0; vi < g_vstats.size(); vi++) {
        if (std::strcmp(kVantages[g_vants[vi]].level, lev) != 0) {
          continue;
        }
        const VantStat& vs = g_vstats[vi];
        if (!vs.shots_h[hi] || !vs.px_h[hi] || vs.level_ok_h[hi] != vs.shots_h[hi]) {
          continue;
        }
        answered = true;
        const uint64_t pm = vs.bg_min_h[hi] * 1000ull / vs.px_h[hi];
        // La vue RETENUE pour un couple est celle qui montre le plus de ciel SANS depasser le
        // plafond : une vue dans le vide ne doit pas evincer une vue correcte.
        if (pm > best_pm && pm <= kSkyCeilPm) {
          best_pm = pm;
        }
      }
      if (answered && best_pm < worst_pm) {
        worst_pm = best_pm;
      }
      if (answered && best_pm >= kSkyFloorPm && best_pm <= kSkyCeilPm) {
        continue;
      }
      missing++;
      if (miss_list.size() < 900) {
        char buf[64];
        std::snprintf(buf, sizeof(buf), "%s%s@h%02d:%llu", miss_list.empty() ? "" : "+", lev,
                      kHours[hi], (unsigned long long)(answered ? best_pm : 9999));
        miss_list += buf;
      }
    }
  }
  g_census_coverage_missing += missing;
  autoport_proof::publish("refset_sky_missing", missing);
  autoport_proof::publish("refset_sky_worst_pm", worst_pm);
  autoport_proof::publish_text("refset_sky_missing_list", miss_list.empty() ? "aucun"
                                                                           : miss_list.c_str());
}

void publish_coverage() {
  g_census_coverage_missing = 0;
  // Un sous-plan ou une camera de calibrage ne certifie pas le jeu de references livre.
  const bool full_plan = g_vants.size() == kNumVantages && g_steps.size() == kNumVantages * 8 * 3 &&
                         g_phases == std::vector<int>({1, 2, 3}) && g_hours_mask == kAllHours;
  if (!full_plan || !g_cam_armed || g_cam_overrides || g_pitch_sweep || g_yaw_sweep ||
      g_cam_hour_sweep || g_slip_nonzero || g_roundtrip_bad) {
    g_census_coverage_missing++;
  }
  for (const auto& vs : g_vstats) {
    for (int hi = 0; hi < 8; hi++) {
      if (vs.shots_h[hi] != 3 || vs.level_ok_h[hi] != 3 || !vs.px_h[hi]) {
        g_census_coverage_missing++;
      }
    }
  }
  autoport_proof::publish("refset_views", g_vants.size());
  autoport_proof::publish("refset_probe_frames", g_probe_frames);
  autoport_proof::publish("refset_probe_px", g_probe_px);
  uint64_t shot = 0, sky = 0, inter = 0, nolevel = 0;
  for (size_t i = 0; i < g_vstats.size(); i++) {
    const VantStat& vs = g_vstats[i];
    if (!vs.shots || !vs.px) {
      continue;
    }
    shot++;
    const uint64_t pm_min = vs.bg_px_min * 1000ull / vs.px;
    const uint64_t pm_max = vs.bg_px_max * 1000ull / vs.px;
    // UNE VUE DONT LE NIVEAU N'ETAIT PAS LA NE COMPTE NI COMME CIEL NI COMME INTERIEUR.
    const bool loaded = vs.level_ok == vs.shots;
    const char* id = kVantages[g_vants[i]].id;
    char key[128];
    std::snprintf(key, sizeof(key), "refset_bg_min_pm_%s", id[0] ? id : "legacy");
    for (char* c = key; *c; c++) {
      if (*c == '-') {
        *c = '_';
      }
    }
    autoport_proof::publish(key, pm_min);
    std::snprintf(key, sizeof(key), "refset_bg_max_pm_%s", id[0] ? id : "legacy");
    for (char* c = key; *c; c++) {
      if (*c == '-') {
        *c = '_';
      }
    }
    autoport_proof::publish(key, pm_max);
    std::snprintf(key, sizeof(key), "refset_dv_%s", id[0] ? id : "legacy");
    for (char* c = key; *c; c++) {
      if (*c == '-') {
        *c = '_';
      }
    }
    autoport_proof::publish(key, vs.maxdiff);
    // LA GRANDEUR BRUTE, CRENEAU PAR CRENEAU. `refset_sky_missing` compte des couples ; sans
    // cette table on ne saurait pas LEQUEL manque ni de combien, et l'etalonnage des angles se
    // ferait a l'aveugle. Format : `h09:119` — pour mille de pixels d'arriere-plan.
    {
      std::string row;
      char cell[32];
      for (int hh = 0; hh < 8; hh++) {
        if (!vs.shots_h[hh] || !vs.px_h[hh]) {
          continue;
        }
        std::snprintf(cell, sizeof(cell), "%sh%02d:%llu", row.empty() ? "" : ",", kHours[hh],
                      (unsigned long long)(vs.bg_min_h[hh] * 1000ull / vs.px_h[hh]));
        row += cell;
      }
      std::snprintf(key, sizeof(key), "refset_bgh_%s", id[0] ? id : "legacy");
      for (char* c = key; *c; c++) {
        if (*c == '-') {
          *c = '_';
        }
      }
      autoport_proof::publish_text(key, row.empty() ? "aucune" : row.c_str());
    }
    if (loaded && pm_min >= 150) {
      sky++;
    }
    if (loaded && pm_max <= 10) {
      inter++;
    }
    if (!loaded) {
      nolevel++;
    }
  }
  autoport_proof::publish("refset_shot_views", shot);
  // Les vues photographiees SANS leur niveau : elles ne comptent ni en ciel ni en interieur, et
  // ce compteur est ce qui empeche de lire leur absence comme un resultat.
  autoport_proof::publish("refset_views_without_level", nolevel);
  autoport_proof::publish("refset_sky_views", sky);
  autoport_proof::publish("refset_interior_views", inter);
  autoport_proof::publish("refset_levels", g_levels_seen.size());
  {
    std::string seen, missing;
    uint64_t nmiss = 0;
    for (const auto& s : g_levels_seen) {
      seen += seen.empty() ? "" : "+";
      seen += s;
    }
    for (int i = 0; i < kNumPlayableLevels; i++) {
      if (g_levels_seen.count(kPlayableLevels[i])) {
        continue;
      }
      nmiss++;
      missing += missing.empty() ? "" : "+";
      missing += kPlayableLevels[i];
    }
    autoport_proof::publish("refset_levels_playable", (uint64_t)kNumPlayableLevels);
    autoport_proof::publish("refset_levels_missing", nmiss);
    autoport_proof::publish_text("refset_levels_list", seen.empty() ? "aucun" : seen.c_str());
    autoport_proof::publish_text("refset_levels_missing_list",
                                 missing.empty() ? "aucun" : missing.c_str());
  }
  if (g_levels_seen.size() < 20 || inter < 4 || nolevel) {
    g_census_coverage_missing++;
  }
  publish_sky_gate();
  autoport_proof::publish("refset_census_coverage_missing", g_census_coverage_missing);
}

void publish_state() {
  autoport_proof::publish_text("refset_mode", g_mode == 1 ? "capture" : "replay");
  // QUEL BINAIRE A PRODUIT CETTE COURSE. `ablate` = la couche Recharged n'est pas compilee
  // dedans ; il ne sert qu'a CAPTURER la reference ORIGINE-TOTAL et il ne peut pas passer la
  // porte (voir `verdict_master_off_bitexact`). Publie hors du bras `g_mode == 2` : une course
  // de capture doit dire elle aussi de quel binaire elle sort.
  autoport_proof::publish_text("origin_build_flavour", build_flavour());
#if defined(__ANDROID__)
  autoport_proof::publish_text("refset_platform", "device");
#else
  autoport_proof::publish_text("refset_platform", "x86");
#endif
  autoport_proof::publish("refset_steps", g_steps.size());
  autoport_proof::publish("refset_step_done", g_cur);
  autoport_proof::publish("refset_step_anchor_set", g_step_anchor >= 0 ? 1 : 0);
  autoport_proof::publish("refset_rewarps", g_rewarps);
  autoport_proof::publish("refset_parts_repins", g_repins);
  autoport_proof::publish("refset_parts_repin_lf", (uint64_t)(g_repin_lf < 0 ? 0 : g_repin_lf));
  autoport_proof::publish("refset_parts_frozen_frames", g_frozen_frames);
  autoport_proof::publish("refset_parts_steps", g_part_steps);
  autoport_proof::publish("refset_parts_extra_calls", g_part_extra);
  autoport_proof::publish("refset_parts_frozen_first_lf",
                          (uint64_t)(g_frozen_first_lf < 0 ? 0 : g_frozen_first_lf));
  autoport_proof::publish("refset_settle", (uint64_t)g_step_settle);
  autoport_proof::publish("refset_load_settle", (uint64_t)g_load_settle);
  autoport_proof::publish("refset_load_steps", g_load_steps);
  // Les teleports d'ARRIVEE, comptes a part des teleports de photo : `refset_prewarps` doit
  // valoir le nombre de vantages, sinon un vantage a ete photographie sans avoir charge.
  autoport_proof::publish("refset_prewarps", g_prewarps);
  autoport_proof::publish("refset_load_margin_min",
                          (uint64_t)(g_load_margin_min < 0 ? 0 : g_load_margin_min));
  autoport_proof::publish("refset_load_margin_n", g_load_margin_measured);
  autoport_proof::publish("refset_vant_base_lf", (uint64_t)(g_vant_base < 0 ? 0 : g_vant_base));
  publish_coverage();
  // L'HORLOGE DU FEU, ET LE CONTROLE DE NON-VACUITE DE SA NEUTRALISATION. `refset_mood_pins`
  // dit que le geste a bien eu lieu ; `refset_mood_span_min/max` disent combien d'images ont
  // ete DESSINEES entre deux photos consecutives. Si ces deux bornes sont egales, la cadence
  // d'affichage etait deja constante et epingler la flamme n'expliquerait rien : c'est la
  // mesure qui tranche, pas ce commentaire.
  autoport_proof::publish("refset_mood_pins", g_mood_pins);
  autoport_proof::publish("refset_mood_calls", g_mood_calls);
  autoport_proof::publish("refset_mood_span_min",
                          g_mood_span_min == ~0ull ? 0 : g_mood_span_min);
  autoport_proof::publish("refset_mood_span_max", g_mood_span_max);
  // L'INVITE 2D, ET LE CONTROLE DE NON-VACUITE DE SA NEUTRALISATION. `refset_text_muted` dit que
  // le geste a eu lieu ; `refset_text_steps_with/_without` disent que le texte etait bien present
  // dans une partie seulement des photos. Un `_with` a 0 ou a 24 rendrait la clause vide.
  autoport_proof::publish("refset_text_calls", g_text_calls);
  autoport_proof::publish("refset_text_muted", g_text_muted);
  autoport_proof::publish("refset_text_steps_with", g_text_steps_with);
  autoport_proof::publish("refset_text_steps_without", g_text_steps_without);
  // La POLITIQUE DE TELEPORT est publiee : deux courses qui ne l'ont pas la meme ne
  // photographient pas les memes poses, et rien d'autre dans la preuve ne le dirait.
  autoport_proof::publish("refset_warp_per_step", (uint64_t)g_warp_per_step);
  // LA CAMERA EPINGLEE. `armed=1` et `pins == asks` disent que TOUTES les images ont recu la
  // pose calculee : un seul repli sur la camera du jeu suffirait a rendre une photo
  // irreproductible, et il serait muet.
  autoport_proof::publish("refset_cam_armed", (uint64_t)g_cam_armed);
  autoport_proof::publish("refset_cam_pins", g_cam_pins);
  autoport_proof::publish("refset_cam_asks", g_cam_asks);
  autoport_proof::publish("refset_cam_overrides", g_cam_overrides);
  autoport_proof::publish("refset_hours_mask", (uint64_t)g_hours_mask);
  autoport_proof::publish("refset_pitch_sweep", (uint64_t)g_pitch_sweep);
  autoport_proof::publish("refset_yaw_sweep", (uint64_t)g_yaw_sweep);
  autoport_proof::publish("refset_cam_hour_sweep", (uint64_t)g_cam_hour_sweep);
  autoport_proof::publish("refset_late_arms", g_late_arms);
  // L'instant DEMANDE et l'instant OBTENU pour le premier teleport. Publier le seul demande
  // ne dirait pas si la readiness est arrivee apres : `warp1 != warp_at` = la course a rate
  // son ancre, et tout ce qui suit est incomparable.
  autoport_proof::publish("refset_warp_at", (uint64_t)g_warp_at);
  autoport_proof::publish("refset_warp1_lf", (uint64_t)(g_warp1 < 0 ? 0 : g_warp1));
  autoport_proof::publish("refset_plan_base_lf", (uint64_t)(g_plan_base < 0 ? 0 : g_plan_base));
  autoport_proof::publish("refset_captured", g_captured);
  autoport_proof::publish("refset_slip_max", (uint64_t)(g_frame_slip_max < 0 ? 0
                                                                             : g_frame_slip_max));
  autoport_proof::publish("refset_slip_min",
                          (uint64_t)(g_frame_slip_min > (1 << 19) ? 0 : g_frame_slip_min));
  autoport_proof::publish("refset_roundtrip_bad", g_roundtrip_bad);
  // QUI CADENCE LE PLAN, et combien de photos ont rate leur frame. Sans ces trois lignes,
  // « le plan est cadence sur la frame de logique » est une affirmation que la preuve ne
  // contredit pas : `refset_pump_logic` doit dominer, et `refset_slip_nonzero` doit valoir 0
  // pour qu'une comparaison bit-a-bit ait un sens.
  autoport_proof::publish("refset_pump_logic", g_pump_logic);
  autoport_proof::publish("refset_pump_render", g_pump_render);
  autoport_proof::publish("refset_slip_nonzero", g_slip_nonzero);
  autoport_proof::publish("refset_order_by_hour", (uint64_t)g_order_by_hour);
  // LE RETIMEUR DE RENDU, LU SUR SON ETAT REELLEMENT LATCHE — pas sur notre intention.
  // `render_pace` est la seule entree de montre murale du chemin de dessin : son alpha
  // reecrit la pose DESSINEE de la camera (cam-update.gc:246) et celle des articulations
  // (drawable.gc:1107). Tant qu'il est arme, deux courses identiques ne peuvent pas rendre
  // la meme image, et `refset_replay_maxdiff` le dirait sans dire pourquoi. Ces deux lignes
  // nomment la cause dans la preuve elle-meme : une reference n'est rejouable que capturee
  // et rejouee avec `refset_pace_armed=0`.
  autoport_proof::publish("refset_pace_armed", render_pace::armed() ? 1 : 0);
  autoport_proof::publish("refset_fixed_tick_armed", fixed_tick::enabled() ? 1 : 0);
  // CE QUE LA NEUTRALISATION SUPPRIME, MESURE. `refset_pace_alpha` est ce que GOAL lit
  // vraiment (1000000 = identite). `refset_raw_alpha_min/max` est ce que `render_pace` a
  // calcule depuis la cadence d'affichage REELLE pendant la meme course : min != max prouve
  // que la grandeur supprimee variait, donc que la neutralisation n'est pas une clause vide.
  autoport_proof::publish("refset_pace_alpha", (uint64_t)(int64_t)render_pace::alpha_micro());
  autoport_proof::publish("refset_pace_skip", render_pace::skip() ? 1 : 0);
  if (g_raw_alpha_n) {
    autoport_proof::publish("refset_raw_alpha_min", (uint64_t)g_raw_alpha_min);
    autoport_proof::publish("refset_raw_alpha_max", (uint64_t)g_raw_alpha_max);
    autoport_proof::publish("refset_raw_alpha_n", g_raw_alpha_n);
  }
  if (g_mode == 2) {
    autoport_proof::publish("refset_compared", g_compared);
    autoport_proof::publish("refset_missing", g_missing);
    autoport_proof::publish("refset_size_bad", g_size_bad);
    autoport_proof::publish("refset_decode_bad", g_decode_bad);
    autoport_proof::publish("refset_replay_diffpx", g_diffpx);
    // 254 = le plan n'est pas alle au bout ; 255 = une reference manque ou ne se decode pas.
    // La vraie mesure ne remplace ces deux valeurs QUE lorsque tout a ete compare.
    uint64_t gate;
    if (g_missing || g_size_bad || g_decode_bad) {
      gate = 255;
    } else if (!g_finished) {
      gate = 254;
    } else {
      gate = g_maxdiff;
    }
    autoport_proof::publish("refset_census_replay_runs", g_census_replay_runs);
    autoport_proof::publish("refset_replay_run_maxdiff", gate);
    autoport_proof::publish("refset_replay_maxdiff",
                            autoport_proof::feature_is("lighting-census") && gate == 0
                                ? (g_census_coverage_missing ? 254 : g_census_replay_gate)
                                : gate);
    // La grandeur de PORTE de cet item porte sur plusieurs COURSES (voir `publish_flaky`). Tant
    // que le registre n'a pas parle, la preuve porte la sentinelle : une course interrompue est
    // rouge, jamais muette — un `proof.txt` sans la cle se lit « le moteur ne l'emet pas ».
    if (!g_flaky_done) {
      autoport_proof::publish("refset_replay_flaky", 254);
    }
    // Les deux jeux, separement, avec la MEME regle de sentinelle : une course qui n'est pas
    // allee au bout ne peut pas rendre un zero.
    for (int ph = 1; ph <= 3; ph++) {
      static const char* const kMax[4] = {"", "refpix_maxdiff_origine", "refpix_maxdiff_recharged",
                                          "refpix_maxdiff_origine_lumiere"};
      static const char* const kImg[4] = {"", "refpix_images_origine", "refpix_images_recharged",
                                          "refpix_images_origine_lumiere"};
      const char* key = kMax[ph];
      const char* nkey = kImg[ph];
      autoport_proof::publish(key, gate >= 254 ? gate : g_maxdiff_phase[ph]);
      autoport_proof::publish(nkey, g_compared_phase[ph]);
    }
    // lighting-hdr : les grandeurs BRUTES des verdicts 1 et 2, publiees a cote du verdict pour
    // qu'un zero soit lisible. Un verdict sans son denominateur est une fausse constante.
    uint64_t sat_r = 0, sat_o = 0, px_o = 0, worst_ratio = 1u << 30, meas = 0;
    for (int i = 0; i < 8; i++) {
      const StepStats& r = g_stats[2][i];
      const StepStats& o = g_stats[3][i];
      if (!r.measured || !o.measured) {
        continue;
      }
      meas++;
      sat_r += r.sat_px;
      sat_o += o.sat_px;
      px_o += o.px;
      const uint64_t ratio = o.contrast_x1000
                                 ? (r.contrast_x1000 * 100ull) / o.contrast_x1000
                                 : (r.contrast_x1000 ? 1000ull : 100ull);
      if (ratio < worst_ratio) {
        worst_ratio = ratio;
      }
      // PAR CRENEAU, et pas seulement le pire. Les verdicts 1 et 2 echouent DES QU'UN creneau
      // echoue : un chiffre agrege dit qu'il y a un probleme, il ne dit pas ou corriger. Ces
      // seize lignes nomment le creneau fautif — sans elles l'essai suivant recommence a
      // l'aveugle, et c'est exactement ce que la revue reproche a un verdict sans denominateur.
      char k[64];
      std::snprintf(k, sizeof(k), "hdr_sat_excess_h%02d", kHours[i]);
      autoport_proof::publish(k, r.sat_px > o.sat_px ? r.sat_px - o.sat_px : 0ull);
      std::snprintf(k, sizeof(k), "hdr_hlc_pct_h%02d", kHours[i]);
      autoport_proof::publish(k, ratio);
    }
    // L'ECART D'APPARIEMENT DES VERDICTS 1 ET 2, EN FRAMES DE LOGIQUE. Le pire des huit
    // creneaux. C'est le denominateur de `hdr_hlc_pct_h*` : a 1440 il melange la courbe et le
    // temps, a 180 il ne reste que le settle d'une etape. 0 = pas mesurable (une des deux
    // photos manque), ce qui se lit sur `hdr_refset_hours_paired`.
    uint64_t gap_max = 0;
    for (int i = 0; i < 8; i++) {
      const StepStats& r = g_stats[2][i];
      const StepStats& o = g_stats[3][i];
      if (!r.measured || !o.measured || r.cap_lf < 0 || o.cap_lf < 0) {
        continue;
      }
      const uint64_t gap = (uint64_t)(r.cap_lf > o.cap_lf ? r.cap_lf - o.cap_lf
                                                          : o.cap_lf - r.cap_lf);
      if (gap > gap_max) {
        gap_max = gap;
      }
    }
    autoport_proof::publish("refset_pair_gap_lf", gap_max);
    autoport_proof::publish("hdr_refset_hours_paired", meas);
    autoport_proof::publish("hdr_sat_px_recharged", sat_r);
    autoport_proof::publish("hdr_sat_px_origine_lumiere", sat_o);
    autoport_proof::publish("hdr_sat_denom_px", px_o);
    // LA CLASSE DE DEFAUT QUE L'OWNER NOMME, PUBLIEE. `sat_white_px` (les TROIS canaux a 255 —
    // le blanc entierement brule) etait compte par `measure_step` et lu par AUCUNE ligne. Il est
    // publie pour les TROIS configurations, avec le total d'ORIGINE-TOTAL a cote de celui des
    // deux autres : sans ces trois nombres, « est-ce que le master ON brule plus que le jeu
    // d'origine ? » n'a pas de reponse machine, et c'est litteralement la question posee le
    // 2026-09-06. Aucun verdict n'en depend — c'est une mesure, pas une porte.
    {
      uint64_t sw[4] = {0, 0, 0, 0}, sp[4] = {0, 0, 0, 0};
      for (int ph = 1; ph <= 3; ph++) {
        for (int i = 0; i < 8; i++) {
          if (g_stats[ph][i].measured) {
            sw[ph] += g_stats[ph][i].sat_white_px;
            sp[ph] += g_stats[ph][i].sat_px;
          }
        }
      }
      autoport_proof::publish("hdr_sat_px_origine_total", sp[1]);
      autoport_proof::publish("hdr_sat_white_px_origine_total", sw[1]);
      autoport_proof::publish("hdr_sat_white_px_recharged", sw[2]);
      autoport_proof::publish("hdr_sat_white_px_origine_lumiere", sw[3]);
    }
    autoport_proof::publish("hdr_hl_contrast_worst_pct", meas ? worst_ratio : 0);
    // Le temoin de capture d'ORIGINE-TOTAL, publie pour que le verdict 4 soit LISIBLE : s'il
    // egale `refset_bin_fp`, la reference a ete capturee par ce binaire meme et le verdict est
    // rouge par construction, quel que soit le maxdiff.
    char wt[32];
    std::snprintf(wt, sizeof(wt), "%016llx", (unsigned long long)read_capture_witness(1));
    autoport_proof::publish_text("refset_witness_origine", wt);
    // La saveur du binaire qui a capture, et celle du binaire qui rejoue. Sans ces deux lignes,
    // « la reference vient d'un build sans la couche » est une affirmation que la preuve ne
    // contredit pas : la porte les EXIGE, le proof.txt doit donc les MONTRER.
    {
      const std::string wf = read_capture_flavour(1);
      autoport_proof::publish_text("refset_witness_origine_flavour",
                                   wf.empty() ? "absente" : wf.c_str());
    }
  }
  // En mode capture on ne publie AUCUNE valeur de porte : une course qui fabrique ses propres
  // references ne doit pas pouvoir la franchir.
}

std::string image_path(const std::string& name) {
  return g_dir + "/" + name + ".png";
}

void apply_step_config(const Step& s) {
  // Le master et la lumiere temps reel se pilotent par les surcharges d'environnement qui
  // EXISTENT (gfx.h:554 `OG_RECHARGED`, background_common.cpp:2635 `OG_RT_LIGHT`). Ecrire
  // directement dans `g_global_settings` ne tiendrait pas : GOAL repousse `recharged-master?`
  // a chaque image (hud-classes-pc.gc:1747). Les deux variables sont posees a leur longueur
  // definitive des l'initialisation, donc chaque bascule n'est qu'un `strcpy` en place.
  // lighting-hdr : `OG_LIGHTING` epingle le maitre de la refonte lumiere (gfx.h
  // `recharged_lighting_active`). C'est LUI qui separe RECHARGED d'ORIGINE-LUMIERE ; le master
  // les separe toutes les deux d'ORIGINE-TOTAL. `OG_RT_LIGHT` ne choisissait qu'un composite.
  if (s.phase == 1) {
    put_env("OG_RECHARGED", "0");  // ORIGINE-TOTAL : le jeu de Naughty Dog entier
    put_env("OG_LIGHTING", "0");
    put_env("OG_RT_LIGHT", "0");
  } else if (s.phase == 2) {
    put_env("OG_RECHARGED", "1");  // RECHARGED : master ON + refonte lumiere ON
    put_env("OG_LIGHTING", "1");
    put_env("OG_RT_LIGHT", "1");
  } else {
    // ORIGINE-LUMIERE : tout le Recharged SAUF l'eclairage. La config que l'owner joue.
    put_env("OG_RECHARGED", "1");
    put_env("OG_LIGHTING", "0");
    put_env("OG_RT_LIGHT", "0");
  }
  // LE VANTAGE. `level_warp_run` (kmachine.cpp) relit `OG_LEVEL_WARP` a chaque armement, donc
  // poser la variable ICI suffit a diriger le teleport suivant vers un autre point de reprise.
  // `OG_LEVEL_WARP_POS` est vide pour tous les vantages sauf l'historique : une chaine vide
  // laisse la position de la donnee de Naughty Dog intacte (kmachine.cpp:6009, la surcharge est
  // gardee par `posbuf[0]`).
  const Vantage& v = vantage_of(s);
  put_env("OG_LEVEL_WARP", v.cont);
  put_env("OG_LEVEL_WARP_POS", v.pos);
  g_tod_x100 = s.hour * 100;
  lighting_census::set_phase(s.phase);
}

// Compare deux tampons RGBA de meme taille. L'alpha est ignore : `finish_screenshot` le force a
// 0xff, il ne porte donc aucune information.
void compare(const uint8_t* a, const uint8_t* b, int n_px, uint64_t* maxd, uint64_t* npx) {
  uint64_t md = 0, np = 0;
  for (int i = 0; i < n_px; i++) {
    int d = 0;
    for (int c = 0; c < 3; c++) {
      int t = (int)a[i * 4 + c] - (int)b[i * 4 + c];
      if (t < 0) {
        t = -t;
      }
      if (t > d) {
        d = t;
      }
    }
    if (d > 0) {
      np++;
      if ((uint64_t)d > md) {
        md = (uint64_t)d;
      }
    }
  }
  *maxd = md;
  *npx = np;
}


// ── le registre de rejeux ───────────────────────────────────────────────────────────────────
// `refset_replay_flaky` est le NOMBRE DE PAIRES DE REJEUX CONSECUTIFS, meme binaire et memes
// references, dont le `maxdiff` differe. C'est une grandeur qui porte sur des COURSES : aucune
// course seule ne peut la calculer, et un chiffre recopie a la main ne prouverait rien. Le
// moteur tient donc un registre sur disque, `<dir>/replay-ledger.txt`, une ligne par rejeu
// COMPLET :
//     bin=<empreinte du binaire> refs=<empreinte des 16 references> maxdiff=<n> diffpx=<n>
// et ne compare QUE les lignes dont les deux empreintes valent celles de la course en cours.
// Un binaire rebati ou une reference recapturee change l'empreinte : le registre se perime tout
// seul, il n'y a rien a effacer — et effacer un registre pour se debloquer serait exactement le
// geste que la non-destruction interdit.
//
// SENTINELLES, memes regles que `refset_replay_maxdiff` : 255 = la course n'a pas pu se mesurer
// (reference manquante, illisible, plan incomplet) ; 254 = moins de CINQ rejeux au registre,
// donc la question n'a pas encore de reponse. Ni l'une ni l'autre ne vaut zero : une porte
// verte demande cinq rejeux qui se sont mis d'accord.
uint64_t hash_file(const std::string& path) {
  FILE* f = std::fopen(path.c_str(), "rb");
  if (!f) {
    return 0;
  }
  uint64_t h = 1469598103934665603ull;  // FNV-1a 64
  unsigned char buf[1 << 16];
  size_t n;
  while ((n = std::fread(buf, 1, sizeof(buf), f)) > 0) {
    for (size_t i = 0; i < n; i++) {
      h ^= buf[i];
      h *= 1099511628211ull;
    }
  }
  std::fclose(f);
  return h ? h : 1;  // 0 est reserve a « pas lisible »
}

// Les SEIZE references, dans l'ordre du plan. Une reference qui bouge d'un octet change
// l'empreinte, donc coupe le registre : on ne compare jamais deux courses jugees sur des
// references differentes.
uint64_t refs_fingerprint() {
  uint64_t h = 1469598103934665603ull;
  // TOUTES les references du plan, dans l'ordre du plan — pas « les seize » : le plan en compte
  // autant qu'il a d'etapes, et une vue ajoutee doit perimer le registre comme n'importe quel
  // autre changement de reference.
  for (const Step& s : g_steps) {
    const uint64_t fh = hash_file(g_dir + "/" + step_image_name(s) + ".png");
    if (!fh) {
      return 0;
    }
    for (int b = 0; b < 8; b++) {
      h ^= (unsigned char)((fh >> (8 * b)) & 0xff);
      h *= 1099511628211ull;
    }
  }
  return h ? h : 1;
}

// LE JEU DE DONNEES EST UNE ENTREE AU MEME TITRE QUE LE BINAIRE (item `refset-replay-stable`).
// Le registre ne comparait que `bin` et `refs`. Or `out/jak1/iso` est REECRIT par le
// constructeur, et pas rarement : mesure du 2026-09-06, les 28 `.CGO`/`.DGO` portent 15:58,
// c'est-a-dire APRES le rejeu de 15:52 dont la ligne est deja au registre. Deux rejeux qui
// encadrent une reconstruction n'ont pas lu la meme donnee : leur `maxdiff` a toutes les raisons
// de differer, et le registre l'aurait compte comme une intermittence de l'INSTRUMENT. C'est
// exactement le faux rouge que cet item doit supprimer. On ferme donc la porte au POINT DE
// PRODUCTION — les donnees entrent dans la CLE du registre — au lieu de le detecter apres coup.
// L'empreinte est le CONTENU, jamais une date : un `.CGO` rebati a l'identique ne coupe rien, et
// une donnee qui bouge d'un octet perime les lignes d'avant sans qu'on ait rien a effacer.
// Zero = un des repertoires est absent ou illisible ; `publish_flaky` en fait la sentinelle 255,
// jamais un zero de porte.
uint64_t data_fingerprint() {
  std::vector<fs::path> files;
  auto scan = [&files](const fs::path& dir, const char* ext) {
    std::error_code ec;
    for (const auto& e : fs::directory_iterator(dir, ec)) {
      std::error_code ec2;
      if (!e.is_regular_file(ec2)) {
        continue;
      }
      const std::string name = e.path().filename().string();
      const size_t n = std::strlen(ext);
      if (name.size() > n && name.compare(name.size() - n, n, ext) == 0) {
        files.push_back(e.path());
      }
    }
  };
  const fs::path iso = file_util::get_iso_out_dir(GameVersion::Jak1);
  const fs::path fr3 = file_util::get_fr3_dir(GameVersion::Jak1);
  scan(iso, ".CGO");
  scan(iso, ".DGO");
  scan(fr3, ".fr3");
  scan(fr3 / "enhanced", ".fr3");
  if (files.empty()) {
    return 0;
  }
  // Trie sur le NOM : l'ordre de `directory_iterator` est celui du systeme de fichiers, il n'est
  // pas stable d'une course a l'autre.
  std::sort(files.begin(), files.end());
  uint64_t h = 1469598103934665603ull;
  for (const auto& f : files) {
    const uint64_t fh = hash_file(f.string());
    if (!fh) {
      return 0;
    }
    // Le nom entre dans l'empreinte : deux fichiers qui echangent leur contenu ne doivent pas
    // rendre la meme valeur.
    for (unsigned char c : f.filename().string()) {
      h ^= c;
      h *= 1099511628211ull;
    }
    for (int b = 0; b < 8; b++) {
      h ^= (unsigned char)((fh >> (8 * b)) & 0xff);
      h *= 1099511628211ull;
    }
  }
  return h ? h : 1;
}

// lighting-hdr : l'empreinte du binaire COURANT. Extraite de `publish_flaky` pour que le
// verdict 4 puisse s'en servir aussi.
//
// SUR ANDROID, `/proc/self/exe` N'EST PAS NOTRE BINAIRE. Le processus est forke depuis zygote :
// son executable est `/system/bin/app_process64`, IDENTIQUE pour tous nos builds (mesure du
// 2026-09-06 sur eae4df44 : le lien pointe hors de l'APK). Le temoin de capture du verdict 4
// valait donc la meme chose pour le binaire qui capture et pour celui qui rejoue, et
// `verdict_master_off_bitexact()` rendait 1 QUOI QU'IL ARRIVE. Notre code vit dans `libgk.so` :
// on l'atteint par `dladdr` sur une adresse de CE module — jamais par un chemin ecrit en dur,
// qui changerait au premier renommage d'APK.
//
// Le resultat est CALCULE UNE FOIS. `verdict_master_off_bitexact()` est appele toutes les 30
// images depuis `hdr::frame_end` ; relire et hacher 134 Mo a chaque appel arreterait le jeu.
uint64_t self_fingerprint() {
  static uint64_t s_fp = 0;
  static bool s_done = false;
  if (s_done) {
    return s_fp;
  }
  s_done = true;
#if defined(__ANDROID__)
  Dl_info info;
  std::memset(&info, 0, sizeof(info));
  if (dladdr((const void*)&refs_fingerprint, &info) && info.dli_fname && info.dli_fname[0]) {
    s_fp = hash_file(info.dli_fname);
  }
#elif defined(__linux__)
  s_fp = hash_file("/proc/self/exe");
#endif
  return s_fp;
}

// ── LE TEMOIN DE CAPTURE, ET POURQUOI IL EXISTE ─────────────────────────────────────────────
// Le verdict 4 affirme « master eteint, sortie identique au bit a ORIGINE-TOTAL ». Si la
// reference a ete capturee par LE MEME binaire que le rejeu, cette affirmation se compare a
// elle-meme : elle mesure la stabilite, pas l'identite avec le jeu d'origine, et elle rendrait
// zero meme si le changement avait tout casse. C'est la faute « porte calculee sur ses propres
// variables », et elle ne doit pas dependre de la discipline de celui qui lance la course.
// On ecrit donc l'empreinte du binaire qui capture, a cote des images, et le verdict REFUSE de
// passer au vert quand elle est celle du binaire qui rejoue.
std::string witness_path(int phase) {
  return g_dir + "/" + set_name(phase) + "/captured-by.txt";
}

void write_capture_witness(int phase) {
  if (FILE* f = std::fopen(witness_path(phase).c_str(), "w")) {
    // Deux lignes, et les deux comptent. L'empreinte dit « pas le meme binaire » ; la saveur
    // dit « et ce n'etait pas un binaire qui contient la couche qu'on juge ». Sans la seconde,
    // n'importe quel binaire legerement different ferait une reference — la porte serait une
    // mesure de stabilite deguisee, exactement ce que le temoin existe pour empecher.
    std::fprintf(f, "%016llx\nflavour=%s\n", (unsigned long long)self_fingerprint(),
                 build_flavour());
    std::fclose(f);
  }
}

// La saveur inscrite a cote de la reference. "" = absente (temoin d'avant ce champ, ou fichier
// manquant) — et une saveur absente n'est jamais traitee comme `ablate`.
std::string read_capture_flavour(int phase) {
  std::string v;
  if (FILE* f = std::fopen(witness_path(phase).c_str(), "r")) {
    char line[128];
    while (std::fgets(line, sizeof(line), f)) {
      const char* p = std::strstr(line, "flavour=");
      if (p) {
        v = p + 8;
        while (!v.empty() && (v.back() == '\n' || v.back() == '\r')) {
          v.pop_back();
        }
        break;
      }
    }
    std::fclose(f);
  }
  return v;
}

uint64_t read_capture_witness(int phase) {
  uint64_t v = 0;
  if (FILE* f = std::fopen(witness_path(phase).c_str(), "r")) {
    if (std::fscanf(f, "%llx", (unsigned long long*)&v) != 1) {
      v = 0;
    }
    std::fclose(f);
  }
  return v;
}

uint64_t census_config_fingerprint() {
  uint64_t h = 1469598103934665603ull;
  auto add = [&h](const std::string& value) {
    for (unsigned char c : value) {
      h = (h ^ c) * 1099511628211ull;
    }
    h = (h ^ 0xff) * 1099511628211ull;
  };
  for (const Step& step : g_steps) {
    const Vantage& v = vantage_of(step);
    add(step_image_name(step));
    add(v.cont);
    add(v.pos);
    add(v.level);
    for (auto value : {v.pitch_d, v.yaw_d, v.dist_dm, v.height_dm}) {
      add(std::to_string(value));
    }
  }
  for (int64_t value : {g_step_settle, g_load_settle, g_warp_at, int64_t(g_warp_per_step),
                        int64_t(g_order_by_hour)}) {
    add(std::to_string(value));
  }
  return h;
}

void publish_flaky() {
  g_flaky_done = true;
  const uint64_t bin = self_fingerprint();
  const uint64_t refs = refs_fingerprint();
  const uint64_t data = data_fingerprint();
  char t[32];
  std::snprintf(t, sizeof(t), "%016llx", (unsigned long long)bin);
  autoport_proof::publish_text("refset_bin_fp", t);
  std::snprintf(t, sizeof(t), "%016llx", (unsigned long long)refs);
  autoport_proof::publish_text("refset_refs_fp", t);
  std::snprintf(t, sizeof(t), "%016llx", (unsigned long long)data);
  autoport_proof::publish_text("refset_data_fp", t);
  if (!bin || !refs || !data || g_missing || g_size_bad || g_decode_bad ||
      g_compared != g_steps.size()) {
    autoport_proof::publish("refset_replay_runs", 0);
    autoport_proof::publish("refset_replay_flaky", 255);
    return;
  }
  const std::string path = g_dir + "/replay-ledger.txt";
  publish_coverage();  // inclut la derniere photo, avant de qualifier la ligne du registre
  const uint64_t config = census_config_fingerprint();
  const bool census_ok = autoport_proof::feature_is("lighting-census") &&
                         autoport_proof::armed_for("lighting-census") && !g_census_coverage_missing;

  std::snprintf(t, sizeof(t), "%016llx", (unsigned long long)config);
  autoport_proof::publish_text("refset_census_config_fp", t);
  bool ledger_written = false;
  // On ECRIT d'abord, on RELIT ensuite : le verdict porte sur ce qui est sur le disque, pas sur
  // ce que cette course croit avoir ajoute.
  if (FILE* f = std::fopen(path.c_str(), "a")) {
    std::fprintf(
        f,
        "bin=%016llx refs=%016llx data=%016llx maxdiff=%llu diffpx=%llu config=%016llx census=%d\n",
        (unsigned long long)bin, (unsigned long long)refs, (unsigned long long)data,
        (unsigned long long)g_maxdiff, (unsigned long long)g_diffpx, (unsigned long long)config,
        census_ok ? 1 : 0);
    const bool write_ok = !std::ferror(f);
    ledger_written = std::fclose(f) == 0 && write_ok;
  }
  // LA COMPARAISON PORTE SUR LE COUPLE (maxdiff, diffpx), PAS SUR `maxdiff` SEUL.
  // Mesure du 2026-09-07 qui force ce changement : six rejeux a cle IDENTIQUE ont rendu
  // 1242, 1242, 100238, 1242, 1242, 1242 px — et `refset_replay_flaky` a publie 0, parce que
  // l'atlas de police fixait `maxdiff=242` sur les six. Un instrument aveugle a un facteur 80
  // sur le NOMBRE de pixels ne certifie rien. Le nombre de pixels est la grandeur qui bouge ;
  // le maximum est celle qui sature.
  std::vector<std::pair<uint64_t, uint64_t>> md;
  uint64_t census_runs = 0, census_maxdiff = 0;
  if (FILE* f = std::fopen(path.c_str(), "r")) {
    char line[256];
    while (std::fgets(line, sizeof(line), f)) {
      unsigned long long b = 0, r = 0, dt = 0, m = 0, d = 0;
      if (std::sscanf(line, "bin=%llx refs=%llx data=%llx maxdiff=%llu diffpx=%llu", &b, &r, &dt,
                      &m, &d) == 5 &&
          b == bin && r == refs && dt == data) {
        md.emplace_back((uint64_t)m, (uint64_t)d);
        unsigned long long cfg = 0;
        int complete = 0;
        if (std::sscanf(
                line, "bin=%llx refs=%llx data=%llx maxdiff=%llu diffpx=%llu config=%llx census=%d",
                &b, &r, &dt, &m, &d, &cfg, &complete) == 7 &&
            cfg == config && complete == 1) {
          census_runs++;
          census_maxdiff = std::max(census_maxdiff, uint64_t(m));
          if (d && !m) {
            census_maxdiff = 255;  // registre incoherent, jamais un zero
          }
        }
      }
    }
    std::fclose(f);
  }
  uint64_t flaky = 0;
  for (size_t i = 1; i < md.size(); i++) {
    if (md[i] != md[i - 1]) {
      flaky++;
    }
  }
  g_census_replay_runs = census_runs;
  g_census_replay_gate = !ledger_written ? 255 : (census_runs >= 5 ? census_maxdiff : 254);
  autoport_proof::publish("refset_replay_runs", md.size());
  autoport_proof::publish("refset_replay_flaky", md.size() >= 5 ? flaky : 254);
  // LA LIGNE `FEATURE` DE CET ITEM, ET SON PROPRE DENOMINATEUR. `note_hit` alimente un compteur
  // GLOBAL que le recensement d'eclairage domine de plusieurs millions : `hits` prouve que la
  // course a tire, il ne dit pas combien de fois CE code a tire. La grandeur de cet item est
  // `refset_replay_runs` — le nombre de rejeux sur lesquels le verdict est calcule — et elle est
  // publiee juste au-dessus. Un seul hit par rejeu COMPLET : une course interrompue avant la
  // derniere etape n'atteint jamais cette ligne, donc ne peut pas se compter.
  autoport_proof::note_hit();
  std::printf(
      "REFSET ledger runs=%d flaky=%llu (bin=%016llx refs=%016llx data=%016llx "
      "maxdiff=%llu)\n",
      (int)md.size(), (unsigned long long)flaky, (unsigned long long)bin, (unsigned long long)refs,
      (unsigned long long)data, (unsigned long long)g_maxdiff);
  std::fflush(stdout);
}

}  // namespace

bool enabled() {
  static int s_init = 0;
  if (s_init) {
    return g_mode != 0;
  }
  s_init = 1;
  char v[32] = {0};
  if (!read_knob("OG_REFSET", "debug.opengoal.refset", v, sizeof(v))) {
    return false;
  }
  if (std::strcmp(v, "capture") == 0) {
    g_mode = 1;
  } else if (std::strcmp(v, "replay") == 0) {
    g_mode = 2;
  } else {
    return false;
  }
  // lighting-hdr : SUR ANDROID, LE DEFAUT DOIT ETRE ABSOLU, et ce n'est pas une preference.
  // `g_dir` est relatif au CWD du processus, et ce CWD n'est jamais change sur Android : il est
  // en LECTURE SEULE (gk_android_main.cpp:9429-9433 le documente deja pour les sauvegardes,
  // d'ou son `setenv("HOME", files_dir)`). Avec le defaut relatif, la premiere chose que fait
  // refset est `create_directories`, qui LANCE sur un systeme de fichiers en lecture seule —
  // exception non rattrapee, donc `std::terminate` sur le fil GOAL, a l'init. Ce n'etait pas un
  // rouge propre, c'etait un SIGABRT dont la cause ne ressemble pas a son symptome.
  // Le nom differe aussi de celui du x86 : les deux familles d'images ne sont pas comparables
  // (re-rendu 320x180 en resolution interne d'un cote, sous-echantillonnage 4:3 de l'autre), et
  // on rend le melange impossible au point de PRODUCTION plutot que detectable plus tard.
  // La valeur reste ecrasable, mais attention : le canal Android est une propriete systeme,
  // donc plafonnee a PROP_VALUE_MAX (92 octets) — un chemin plus long serait tronque en silence.
#if defined(__ANDROID__)
  if (const char* home = std::getenv("HOME")) {
    if (home[0]) {
      g_dir = std::string(home) + "/.autoport/refset-device";
    }
  }
#endif
  char d[512] = {0};
  if (read_knob("OG_REFSET_DIR", "debug.opengoal.refset.dir", d, sizeof(d))) {
    g_dir = d;
  }
  // UN TELEPORT PAR ETAPE : voir `g_warp_per_step`. Sur appareil le defaut est 0 parce que le
  // troisieme `(start 'play <continue>)` tue la course en SIGILL (mesure du 2026-09-06).
#if defined(__ANDROID__)
  g_warp_per_step = 0;
#endif
  {
    char wv[32] = {0};
    if (read_knob("OG_REFSET_WARP_PER_STEP", "debug.opengoal.refset.warpstep", wv, sizeof(wv))) {
      g_warp_per_step = (std::atoi(wv) != 0) ? 1 : 0;
    }
  }
  {
    char av[32] = {0};
    if (read_knob("OG_REFSET_WARP_AT", "debug.opengoal.refset.warpat", av, sizeof(av))) {
      const long v = std::strtol(av, nullptr, 10);
      if (v >= 60 && v <= 100000) {
        g_warp_at = v;
      }
    }
  }
  {
    char sv[32] = {0};
    if (read_knob("OG_REFSET_SETTLE", "debug.opengoal.refset.settle", sv, sizeof(sv))) {
      const long v = std::strtol(sv, nullptr, 10);
      if (v >= 2 && v <= 3600) {
        g_step_settle = v;
      }
    }
  }
  {
    char sv[32] = {0};
    if (read_knob("OG_REFSET_LOAD_SETTLE", "debug.opengoal.refset.loadsettle", sv, sizeof(sv))) {
      const long ls = std::strtol(sv, nullptr, 10);
      if (ls >= 2 && ls <= 7200) {
        g_load_settle = ls;
      }
    }
    if (g_load_settle < g_step_settle) {
      g_load_settle = g_step_settle;
    }
  }
  fpng::fpng_init();
  // lighting-hdr : quelles phases ce plan execute. `OG_REFSET_PHASES=1,2` ou `=3`, defaut les
  // trois. Ca existe pour une raison precise : la reference ORIGINE-TOTAL du verdict 4 doit
  // etre capturee par un binaire d'AVANT le changement d'eclairage, sinon le verdict se compare
  // a lui-meme. Les phases se capturent donc separement, puis se rejouent ensemble.
  {
    char pv[64] = {0};
    if (read_knob("OG_REFSET_PHASES", "debug.opengoal.refset.phases", pv, sizeof(pv))) {
      for (const char* c = pv; *c; c++) {
        if (*c >= '1' && *c <= '3') {
          const int ph = *c - '0';
          if (std::find(g_phases.begin(), g_phases.end(), ph) == g_phases.end()) {
            g_phases.push_back(ph);
          }
        }
      }
    }
    if (g_phases.empty()) {
      g_phases = {1, 2, 3};
    }
    std::sort(g_phases.begin(), g_phases.end());
  }
  // L'ORDRE DES ETAPES, ET CE QU'IL CHANGE POUR LES VERDICTS 1 ET 2.
  // Par JEU (huit heures d'ORIGINE, puis huit de RECHARGED, puis huit d'ORIGINE-LUMIERE), les
  // deux photos qu'apparient les verdicts 1 et 2 — RECHARGED et ORIGINE-LUMIERE au MEME creneau
  // — sont separees de huit etapes, soit 1440 frames de logique. Ce que ces verdicts mesurent
  // alors est la somme de l'effet de la courbe et de 24 s de decor qui bouge : mesure du
  // 2026-09-06, `hdr_hlc_pct_h21=92` pour un seuil a 95 et `hdr_sat_excess_h06=62` sur 460800
  // pixels — des ecarts du meme ordre que le bruit temporel, donc un verdict qu'on ne peut pas
  // attribuer. Par CRENEAU, les trois configurations d'une meme heure se suivent : l'ecart tombe
  // a UN settle (180 frames), et `refset_pair_gap_lf` le publie au lieu de le supposer.
  // Pourquoi pas partout : sur bureau chaque etape est re-teleportee (`g_warp_per_step=1`), donc
  // l'ordre n'a aucun effet sur les poses — et l'instrument de `refset-replay-stable` ne se
  // redefinit pas sous les cinq rejeux qui l'ont valide (registre keye sur le binaire).
  g_order_by_hour = g_warp_per_step ? 0 : 1;
  {
    char ov[32] = {0};
    if (read_knob("OG_REFSET_ORDER_HOUR", "debug.opengoal.refset.orderhour", ov, sizeof(ov))) {
      g_order_by_hour = (std::atoi(ov) != 0) ? 1 : 0;
    }
  }
  // LES VANTAGES QUE CE PLAN PARCOURT. `OG_REFSET_VANTAGES=legacy` (ou une liste de noms de
  // continue-points separes par des virgules) restreint le parcours ; vide = les 26. `legacy`
  // nomme le vantage historique, dont le prefixe de fichier est vide et qui n'a donc pas de nom
  // typable. Cette restriction existe pour une raison NOMMEE : `lighting-origin-bitexact` et
  // `refset-replay-stable` sont valides sur un instrument de 8 et 24 etapes a la hutte de
  // Sandover. Etendre le plan sous eux, c'est redefinir leur mesure ; leur `proof_env` epingle
  // donc `legacy` et leurs references restent valables octet pour octet.
  {
    char vv[512] = {0};
    if (read_knob("OG_REFSET_VANTAGES", "debug.opengoal.refset.vantages", vv, sizeof(vv))) {
      const std::string want = vv;
      size_t p = 0;
      while (p <= want.size()) {
        const size_t c = want.find(',', p);
        std::string tok = want.substr(p, c == std::string::npos ? std::string::npos : c - p);
        while (!tok.empty() && (tok.front() == ' ' || tok.front() == '\t')) {
          tok.erase(tok.begin());
        }
        while (!tok.empty() && (tok.back() == ' ' || tok.back() == '\t')) {
          tok.pop_back();
        }
        if (!tok.empty()) {
          for (int i = 0; i < kNumVantages; i++) {
            const bool hit = (tok == "legacy" && kVantages[i].id[0] == 0) ||
                             tok == kVantages[i].id || tok == kVantages[i].cont;
            if (hit && std::find(g_vants.begin(), g_vants.end(), i) == g_vants.end()) {
              g_vants.push_back(i);
            }
          }
        }
        if (c == std::string::npos) {
          break;
        }
        p = c + 1;
      }
    }
    if (g_vants.empty()) {
      for (int i = 0; i < kNumVantages; i++) {
        g_vants.push_back(i);
      }
    }
    g_vstats.assign(g_vants.size(), VantStat{});
  }
  // LA CAMERA EPINGLEE : son bras de controle et ses surcharges d'etalonnage.
  {
    char cv[16] = {0};
    if (read_knob("OG_REFSET_CAM_OFF", "debug.opengoal.refset.camoff", cv, sizeof(cv))) {
      g_cam_armed = (std::atoi(cv) != 0) ? 0 : 1;
    }
    char sv2[128] = {0};
    if (read_knob("OG_REFSET_PITCH_BY_HOUR", "debug.opengoal.refset.pitchbyhour", sv2,
                  sizeof(sv2))) {
      int n = 0;
      char* save2 = nullptr;
      for (char* tok = strtok_r(sv2, ",", &save2); tok && n < 8;
           tok = strtok_r(nullptr, ",", &save2)) {
        g_pitch_by_hour[n++] = std::atoi(tok);
      }
      g_pitch_sweep = n > 0 ? 1 : 0;
    }
    char sv3[128] = {0};
    if (read_knob("OG_REFSET_YAW_BY_HOUR", "debug.opengoal.refset.yawbyhour", sv3, sizeof(sv3))) {
      int n = 0;
      char* save3 = nullptr;
      for (char* tok = strtok_r(sv3, ",", &save3); tok && n < 8;
           tok = strtok_r(nullptr, ",", &save3)) {
        g_yaw_by_hour[n++] = std::atoi(tok);
      }
      g_yaw_sweep = n > 0 ? 1 : 0;
    }
    char sv4[256] = {0};
    if (read_knob("OG_REFSET_CAM_BY_HOUR", "debug.opengoal.refset.cambyhour", sv4, sizeof(sv4))) {
      int n = 0;
      char* save4 = nullptr;
      for (char* tok = strtok_r(sv4, ",", &save4); tok && n < 8;
           tok = strtok_r(nullptr, ",", &save4)) {
        int a = 0, b = 0, c = 0, d = 0;
        if (std::sscanf(tok, "%d:%d:%d:%d", &a, &b, &c, &d) == 4) {
          g_cam_by_hour[n] = CamTune{(int16_t)a, (int16_t)b, (int16_t)c, (int16_t)d, true};
        }
        n++;
      }
      g_cam_hour_sweep = n > 0 ? 1 : 0;
    }
    char tv[1024] = {0};
    if (read_knob("OG_REFSET_CAM", "debug.opengoal.refset.cam", tv, sizeof(tv))) {
      char* save = nullptr;
      for (char* tok = strtok_r(tv, ",", &save); tok; tok = strtok_r(nullptr, ",", &save)) {
        char id[64] = {0};
        int p = 0, y = 0, d = 0, h = 0;
        if (std::sscanf(tok, "%63[^:]:%d:%d:%d:%d", id, &p, &y, &d, &h) != 5) {
          continue;
        }
        for (int i = 0; i < kNumVantages; i++) {
          const bool hit = (std::strcmp(id, "legacy") == 0 && kVantages[i].id[0] == 0) ||
                           std::strcmp(id, kVantages[i].id) == 0;
          if (!hit) {
            continue;
          }
          g_cam_tune[i] = CamTune{(int16_t)p, (int16_t)y, (int16_t)d, (int16_t)h, true};
          g_cam_overrides++;
        }
      }
    }
  }
  // L'ETALONNAGE NE PAIE PAS LES HUIT CRENEAUX. `OG_REFSET_HOURS=9` ou `=0,12` restreint le plan
  // a ces heures : une tournee de reperage des angles n'a besoin que d'UNE heure, et elle passe
  // ainsi de 51 minutes a 22. Vide = le masque `hours` de chaque vantage, c'est-a-dire le plan
  // que la porte exige. `refset_hours_mask` publie ce qui a REELLEMENT tourne.
  uint8_t hours_filter = 0xff;
  {
    char hv[64] = {0};
    if (read_knob("OG_REFSET_HOURS", "debug.opengoal.refset.hours", hv, sizeof(hv))) {
      uint8_t m = 0;
      char* save = nullptr;
      for (char* tok = strtok_r(hv, ",", &save); tok; tok = strtok_r(nullptr, ",", &save)) {
        const int hi = hour_index(std::atoi(tok));
        if (hi >= 0) {
          m |= (uint8_t)(1u << hi);
        }
      }
      if (m) {
        hours_filter = m;
      }
    }
  }
  g_hours_mask = hours_filter;
  // L'ORDRE EST PAR VANTAGE D'ABORD, ET CE N'EST PAS UN GOUT. Un vantage = un chargement de
  // niveau ; les grouper met 26 chargements dans la course au lieu de 78, et surtout laisse le
  // regime de modeles du niveau (choisi UNE fois au chargement, jamais refait — Loader.cpp:546)
  // decide par la phase 1, la premiere de chaque bloc, exactement comme le lanceur le pose pour
  // l'etape 0. A l'INTERIEUR d'un vantage l'ordre historique est conserve, si bien qu'un plan
  // restreint a `legacy` reproduit le plan d'avant, etape pour etape.
  for (size_t vi = 0; vi < g_vants.size(); vi++) {
    const Vantage& van = kVantages[g_vants[vi]];
    if (g_order_by_hour) {
      for (int hi = 0; hi < 8; hi++) {
        if (!(van.hours & g_hours_mask & (1u << hi))) {
          continue;
        }
        for (int phase : g_phases) {
          g_steps.push_back(Step{phase, kHours[hi], (int)vi});
        }
      }
    } else {
      for (int phase : g_phases) {
        for (int hi = 0; hi < 8; hi++) {
          if (!(van.hours & g_hours_mask & (1u << hi))) {
            continue;
          }
          g_steps.push_back(Step{phase, kHours[hi], (int)vi});
        }
      }
    }
  }
  // Poser les deux variables a leur longueur definitive AVANT que le fil graphique ne les lise
  // pour la premiere fois : ainsi chaque bascule ulterieure reecrit un unique octet en place.
  put_env("OG_RECHARGED", "0");
  put_env("OG_RT_LIGHT", "0");
  put_env("OG_LIGHTING", "0");
  file_util::create_dir_if_needed(g_dir + "/origine");
  file_util::create_dir_if_needed(g_dir + "/recharged");
  file_util::create_dir_if_needed(g_dir + "/origine-lumiere");
  std::printf("REFSET mode=%s dir=%s steps=%d vues=%d res=%dx%d settle=%lld/%lld\n",
              g_mode == 1 ? "capture" : "replay", g_dir.c_str(), (int)g_steps.size(),
              (int)g_vants.size(), kShotW, kShotH, (long long)g_step_settle,
              (long long)g_load_settle);
  for (size_t i = 0; i < g_vants.size(); i++) {
    const Vantage& van = kVantages[g_vants[i]];
    std::printf("REFSET vue %2d id=%s cont=%s niveau=%s heures=%02x\n", (int)i,
                van.id[0] ? van.id : "legacy", van.cont, van.level, (unsigned)van.hours);
  }
  std::fflush(stdout);
  return true;
}

int tod_override_x100() {
  return g_tod_x100;
}

int64_t warp_at_frame() {
  return g_warp_at;
}

void set_logic_frame_provider(int64_t (*fn)()) {
  g_logic_fn = fn;
}

int64_t current_logic_frame() {
  return g_logic_fn ? g_logic_fn() : -1;
}

void note_anchor() {
  if (!enabled()) {
    return;
  }
  std::lock_guard<std::mutex> lock(g_mutex);
  const int64_t lf = current_logic_frame();
  if (g_warp1 < 0) {
    g_warp1 = lf;
    std::printf("REFSET warp1 lf=%lld (le plan demarre dans %lld images)\n", (long long)lf,
                (long long)kAnchorSettle);
    std::fflush(stdout);
    return;
  }
  g_rewarps++;
  g_rewarp_asked = false;
  if (g_cap == kCapPreWarp) {
    // Teleport d'ARRIVEE : il lance le chargement du niveau du vantage. On ne photographie
    // rien maintenant — on attend que le monde soit la.
    g_prewarps++;
    g_load_until = lf + g_load_settle;
    g_vant_level_seen = false;
    g_load_margin_seen_lf = -1;
    g_cap = kCapWaitLoad;
    std::printf("REFSET arrivee lf=%lld vue=%s attente=%lld\n", (long long)lf,
                g_cur < g_steps.size() ? vantage_of(g_steps[g_cur]).cont : "?",
                (long long)g_load_settle);
    std::fflush(stdout);
    return;
  }
  if (g_cap == kCapWaitWarp) {
    g_step_anchor = lf;
    g_capture_frame = lf + g_step_settle;
    if (g_plan_base < 0) {
      g_plan_base = lf;
    }
    if (g_cur < g_steps.size() && step_is_arrival(g_cur)) {
      g_vant_base = lf;
    }
    g_cap = kCapArmed;
  }
}

// LE RE-ANCRAGE DES LANCEURS DE PARTICULES. Rend vrai UNE seule fois, a la premiere frame de
// logique ou l'ancre du plan existe — donc a un instant FIXE, le meme dans la course qui capture
// et dans celle qui rejoue. C'est ce qui retire au feu sa dependance a la vitesse du chargement.
bool wants_particle_repin() {
  if (!enabled()) {
    return false;
  }
  std::lock_guard<std::mutex> lock(g_mutex);
  if (g_repin_done || g_plan_base < 0) {
    return false;
  }
  g_repin_done = true;
  g_repins++;
  g_repin_lf = current_logic_frame();
  std::printf("REFSET repin-particules lf=%lld (ancre=%lld)\n", (long long)g_repin_lf,
              (long long)g_plan_base);
  std::fflush(stdout);
  return true;
}

// LE PAS DES PARTICULES. Contrat et mesure : refset.h. Deux choses en une fonction, parce que
// ce sont deux faces du meme geste — le temps des particules ne doit avancer qu'a la cadence du
// PLAN, puis plus du tout des la premiere photo.
int particle_step_mode() {
  if (!enabled()) {
    return 2;
  }
  std::lock_guard<std::mutex> lock(g_mutex);
  if (g_plan_base < 0) {
    return 2;  // avant l'ancre : le moteur garde son chemin normal
  }
  const int64_t lf = current_logic_frame();
  if (lf < 0) {
    return 2;
  }
  if (lf >= g_plan_base + g_step_settle) {
    if (g_frozen_first_lf < 0) {
      g_frozen_first_lf = lf;
    }
    g_frozen_frames++;
    return 0;  // gel : les 24 photos voient le meme feu
  }
  if (lf == g_part_step_lf) {
    g_part_extra++;
    return 0;  // deja avance dans cette frame de logique : un deuxieme pas serait du hasard
  }
  g_part_step_lf = lf;
  g_part_steps++;
  return 1;
}

// L'ETAT DE FLAMME, EPINGLE. Contrat et mesure : la declaration d'etat en haut de ce fichier.
// Rend -1 hors du mode refset : le joueur ne rencontre jamais ce chemin, et `update-mood-flames`
// garde son increment d'origine.
int mood_flame_pin() {
  if (!enabled()) {
    return -1;
  }
  std::lock_guard<std::mutex> lock(g_mutex);
  g_mood_calls++;
  if (g_plan_base < 0) {
    return -1;  // avant l'ancre : le moteur garde son chemin normal
  }
  g_mood_pins++;
  return kMoodPinTime;
}

// LE SILENCE DES INCRUSTATIONS DE TEXTE. Contrat et mesure : refset.h. Rend 0 hors du mode
// refset — le joueur ne rencontre jamais ce chemin — et 1 pendant une course, ou
// `print-game-text` bascule alors en mode NO-DRAW : la mise en page est calculee a l'identique et
// la valeur de retour ne change pas, seule l'emission des glyphes disparait.
int text_mute() {
  if (!enabled()) {
    return 0;
  }
  std::lock_guard<std::mutex> lock(g_mutex);
  g_text_calls++;
  g_text_last_lf = current_logic_frame();
  // LA PHASE 1 GARDE SON TEXTE, ET CE N'EST PAS UN DETAIL DE CONFORT.
  // `lighting-origin-bitexact` mesure « maitre eteint => identique au bit au jeu d'origine ».
  // L'invite du maire est le SEUL objet du plan qui dessine l'atlas de police et qui exerce la
  // mise en page de `font.gc`. La muter retirerait de la comparaison tout un sous-systeme, et la
  // porte passerait au vert sur une scene ou la question ne se pose plus — « les DEUX bras au
  // vert parce que la condition est absente ». Depuis l'essai 2 la police n'est plus ablatee
  // dans le binaire-temoin (voir `origin_ablate.h` : banc de texte et chasses vivent dans la
  // donnee partagee), donc ces pixels DOIVENT etre identiques des deux cotes : ce creneau est
  // devenu le controle que le chemin de texte, lui, ne fuit pas ailleurs.
  // On ne mute donc que les phases 2 et 3, celles qu'apparient les verdicts de `lighting-hdr` ;
  // leur instrument est inchange, ligne pour ligne.
  if (g_cur < g_steps.size() && g_steps[g_cur].phase == 1) {
    return 0;
  }
  g_text_muted++;
  return 1;
}

bool wants_rewarp() {
  if (!enabled()) {
    return false;
  }
  std::lock_guard<std::mutex> lock(g_mutex);
  if ((g_cap != kCapWaitWarp && g_cap != kCapPreWarp) || g_warp1 < 0) {
    return false;
  }
  const int64_t lf = current_logic_frame();
  if (g_rewarp_asked) {
    // Le slot `*listener-function*` est partage : une demande peut etre ecrasee avant que le
    // noyau ne la lance. Sans ce re-armement l'etape resterait bloquee pour toujours, et la
    // porte rendrait 254 sans dire pourquoi.
    if (lf < g_rewarp_asked_lf + 300) {
      return false;
    }
  }
  g_rewarp_asked = true;
  g_rewarp_asked_lf = lf;
  return true;
}

// LA CADENCE DU PLAN. Contrat et mesure : voir `begin_logic_frame` dans refset.h. Le
// de-doublonnage porte sur la frame de LOGIQUE, pas sur un compteur maison : deux appels dans la
// meme image simulee (manette lue deux fois, ou image rendue qui suit l'image simulee) rendent
// faux au second, et une frame de logique qu'AUCUNE image rendue ne porte est quand meme
// cadencee — c'est tout l'objet du changement.
bool begin_logic_frame(bool from_logic) {
  if (!enabled()) {
    return false;
  }
  std::lock_guard<std::mutex> lock(g_mutex);
  const int64_t lf = current_logic_frame();
  if (lf == g_pumped_lf) {
    return false;
  }
  g_pumped_lf = lf;
  if (from_logic) {
    g_pump_logic++;
  } else {
    g_pump_render++;
  }
  return true;
}

void tick() {
  if (!enabled()) {
    return;
  }
  std::lock_guard<std::mutex> lock(g_mutex);
  // AVANT tout retour anticipe : l'alpha brut s'echantillonne sur TOUTE la course, y compris
  // le chargement. Le poser apres les gardes ci-dessous ne mesurerait que les images du plan.
  {
    const int64_t raw = (int64_t)render_pace::raw_alpha_micro();
    if (raw < g_raw_alpha_min) {
      g_raw_alpha_min = raw;
    }
    if (raw > g_raw_alpha_max) {
      g_raw_alpha_max = raw;
    }
    g_raw_alpha_n++;
  }
  if (g_warp1 < 0 || g_finished) {
    return;
  }
  const int64_t lf = current_logic_frame();
  if (lf < 0 || lf < g_warp1 + kAnchorSettle) {
    return;
  }

  if (g_cap == kCapDone) {
    g_cap = kCapIdle;
    g_cur++;
    if (g_cur >= g_steps.size()) {
      g_finished = true;
      lighting_census::set_phase(0);
      g_tod_x100 = -1;
      if (g_mode == 2) {
        publish_flaky();
      }
      publish_state();
      std::printf("REFSET done steps=%d captured=%llu compared=%llu maxdiff=%llu diffpx=%llu "
                  "missing=%llu slip=%lld..%lld rewarps=%llu settle=%lld\n",
                  (int)g_steps.size(), (unsigned long long)g_captured,
                  (unsigned long long)g_compared, (unsigned long long)g_maxdiff,
                  (unsigned long long)g_diffpx, (unsigned long long)g_missing,
                  (long long)g_frame_slip_min, (long long)g_frame_slip_max,
                  (unsigned long long)g_rewarps, (long long)g_step_settle);
      std::fflush(stdout);
      return;
    }
  }

  // L'ATTENTE DE CHARGEMENT D'UNE ARRIVEE. Duree FIXE en frames de logique : c'est ce qui rend
  // l'instant du second teleport identique dans la course qui capture et dans celle qui rejoue.
  if (g_cap == kCapWaitLoad) {
    if (g_vant_level_seen && g_load_margin_seen_lf < 0) {
      g_load_margin_seen_lf = lf;
      const int64_t marge = g_load_until - lf;
      g_load_margin_measured++;
      if (g_load_margin_min < 0 || marge < g_load_margin_min) {
        g_load_margin_min = marge;
      }
      std::printf("REFSET niveau-la lf=%lld marge=%lld\n", (long long)lf, (long long)marge);
      std::fflush(stdout);
    }
    if (lf < g_load_until) {
      return;
    }
    g_cap = kCapWaitWarp;
  }

  if (g_cap == kCapIdle) {
    // La configuration est posee AVANT le teleport : l'heure et le master sont donc deja ceux de
    // l'etape quand la camera se repose.
    const Step& st = g_steps[g_cur];
    apply_step_config(st);
    g_capture_name = step_image_name(st);
    if (step_is_arrival(g_cur)) {
      g_load_steps++;
    }
    // UNE ARRIVEE SUR UN NOUVEAU VANTAGE TELEPORTE TOUJOURS, meme quand la politique de l'etape
    // est « pas de teleport » (l'appareil) : sans ce teleport-la, changer de vantage ne
    // changerait que l'heure et le master, et les 25 autres niveaux ne seraient jamais atteints.
    if (step_is_arrival(g_cur) && g_cur != 0) {
      // Nouveau vantage : deux teleports, le premier pour charger. L'etape 0 en est dispensee —
      // son niveau est deja resident, `OG_WANT_LEVELS` l'a demande au lanceur et le premier
      // warp de `level_warp_maybe` a deja eu lieu 300 frames plus tot.
      g_cap = kCapPreWarp;
    } else if (g_warp_per_step || g_cur == 0 || g_vant_base < 0) {
      g_cap = kCapWaitWarp;
    } else {
      // Pas de teleport pour cette etape : l'instant de la photo se DEDUIT de l'ancre du plan.
      // Voir `g_plan_base`. Un retard reel (le plan n'a pas tenu la cadence) n'est pas absorbe
      // en silence : il se compte, et le repli qui suit rend la course non comparable — c'est
      // exactement ce que `refset_late_arms` doit rendre visible.
      g_step_anchor = g_vant_base;
      g_capture_frame = g_vant_base + (int64_t)(g_cur - first_step_of_vant(g_cur) + 1) *
                                          g_step_settle;
      if (g_capture_frame <= lf) {
        g_late_arms++;
        g_capture_frame = lf + g_step_settle;
      }
      g_cap = kCapArmed;
    }
    if (g_cur == 0) {
      std::printf("REFSET start lf=%lld warp1=%lld settle=%lld\n", (long long)lf,
                  (long long)g_warp1, (long long)g_step_settle);
      std::fflush(stdout);
    }
  }
  publish_state();
}

// ── LA SONDE DE SCENE : CIEL ET NIVEAUX (contrat et convention : refset.h) ───────────────────
// Elle ne tourne QUE sur l'image que le plan photographie. `kCapInFlight` est pose par
// `capture_for_chain`, qui est appele avant `render_loop` dans la meme iteration du fil
// graphique (pipelines/opengl.cpp:654) : la sonde et la photo decrivent donc la meme image, et
// c'est le point qui rend la mesure attribuable a une vue.
bool wants_level_census() {
  return enabled();
}

bool wants_scene_probe() {
  if (!enabled()) {
    return false;
  }
  std::lock_guard<std::mutex> lock(g_mutex);
  return g_cap == kCapInFlight && g_cur < g_steps.size();
}

void note_scene_probe(uint64_t bg_px, uint64_t total_px) {
  if (!enabled() || !total_px) {
    return;
  }
  std::lock_guard<std::mutex> lock(g_mutex);
  if (g_cap != kCapInFlight || g_cur >= g_steps.size()) {
    return;
  }
  g_probe_frames++;
  g_probe_px += total_px;
  const size_t vi = (size_t)g_steps[g_cur].vant;
  if (vi >= g_vstats.size()) {
    return;
  }
  VantStat& vs = g_vstats[vi];
  vs.shots++;
  vs.px = total_px;
  const bool level_here = g_frame_levels.count(vantage_of(g_steps[g_cur]).level) != 0;
  if (level_here) {
    vs.level_ok++;
  }
  if (bg_px < vs.bg_px_min) {
    vs.bg_px_min = bg_px;
  }
  if (bg_px > vs.bg_px_max) {
    vs.bg_px_max = bg_px;
  }
  // LE MEME RELEVE, RANGE PAR CRENEAU : c'est lui que lit `refset_sky_missing`.
  const int hi = hour_index(g_steps[g_cur].hour);
  if (hi >= 0) {
    vs.shots_h[hi]++;
    vs.px_h[hi] = total_px;
    if (level_here) {
      vs.level_ok_h[hi]++;
    }
    if (bg_px < vs.bg_min_h[hi]) {
      vs.bg_min_h[hi] = bg_px;
    }
  }
}

// FIL GOAL, une fois par image et par niveau ACTIF. Voir `g_level_sky`.
void note_level_sky(const char* level_name, int has_sky) {
  if (!enabled() || !level_name || !level_name[0]) {
    return;
  }
  std::lock_guard<std::mutex> lock(g_mutex);
  g_level_sky[level_name] = has_sky ? 1 : 0;
}

// FIL GOAL (kmachine, juste avant le `(start 'play <continue>)`). La position ou Jak va
// apparaitre — celle de la donnee, ou celle qu'`OG_LEVEL_WARP_POS` vient d'y ecrire — et son
// quaternion de cap. C'est la SEULE entree du calcul de la camera epinglee.
void note_warp_pose(const float* trans_m, const float* quat) {
  if (!enabled() || !trans_m || !quat) {
    return;
  }
  std::lock_guard<std::mutex> lock(g_mutex);
  g_spawn_m[0] = trans_m[0];
  g_spawn_m[1] = trans_m[1];
  g_spawn_m[2] = trans_m[2];
  // Le cap : l'avant de Jak, (0,0,1) tourne par son quaternion. Seule la composante horizontale
  // compte — un point de reprise sur un plan incline ne doit pas incliner la camera.
  const float x = quat[0], y = quat[1], z = quat[2], w = quat[3];
  const float fx = 2.f * (x * z + w * y);
  const float fz = 1.f - 2.f * (x * x + y * y);
  g_spawn_yaw_deg = std::atan2(fx, fz) * 57.29577951308232f;
  g_pose_known = true;
  std::printf("REFSET pose x=%.2f y=%.2f z=%.2f cap=%.1f\n", (double)trans_m[0],
              (double)trans_m[1], (double)trans_m[2], (double)g_spawn_yaw_deg);
  std::fflush(stdout);
}

// FIL GOAL, une fois par image dessinee. Rend la pose a imposer a `*math-camera*`, en METRES et
// en vecteur avant unitaire. Faux = la camera du jeu garde la main (hors refset, avant le
// premier teleport, ou sous le bras de controle `OG_REFSET_CAM_OFF`).
bool camera_pin(float* out_trans_m, float* out_fwd) {
  if (!enabled() || !out_trans_m || !out_fwd) {
    return false;
  }
  std::lock_guard<std::mutex> lock(g_mutex);
  g_cam_asks++;
  if (!g_cam_armed || !g_pose_known || g_steps.empty()) {
    return false;
  }
  const size_t k = g_cur < g_steps.size() ? g_cur : g_steps.size() - 1;
  const size_t vi = (size_t)g_steps[k].vant;
  const int gi = vi < g_vants.size() ? g_vants[vi] : 0;
  const Vantage& v = kVantages[gi];
  const CamTune* tp = &g_cam_tune[gi];
  if (g_cam_hour_sweep) {
    const int hs = hour_index(g_steps[k].hour);
    if (hs >= 0 && g_cam_by_hour[hs].set) {
      tp = &g_cam_by_hour[hs];
    }
  }
  const CamTune& t = *tp;
  float pitch_d = (float)(t.set ? t.pitch_d : v.pitch_d);
  if (g_pitch_sweep) {
    const int hi = hour_index(g_steps[k].hour);
    if (hi >= 0 && g_pitch_by_hour[hi] > -1000) {
      pitch_d = (float)g_pitch_by_hour[hi];
    }
  }
  float yaw_d = (float)(t.set ? t.yaw_d : v.yaw_d);
  if (g_yaw_sweep) {
    const int hi = hour_index(g_steps[k].hour);
    if (hi >= 0) {
      yaw_d = (float)g_yaw_by_hour[hi];
    }
  }
  const float dist = 0.1f * (float)(t.set ? t.dist_dm : v.dist_dm);
  const float height = 0.1f * (float)(t.set ? t.height_dm : v.height_dm);
  const float kDeg = 0.017453292519943295f;
  const float yaw = (g_spawn_yaw_deg + yaw_d) * kDeg;
  const float pitch = pitch_d * kDeg;
  const float sy = std::sin(yaw), cy = std::cos(yaw);
  const float sp = std::sin(pitch), cp = std::cos(pitch);
  // La camera RECULE a l'horizontale (le pitch ne doit pas la faire monter en plus de la
  // hauteur demandee : les deux reglages resteraient impossibles a lire separement).
  out_trans_m[0] = g_spawn_m[0] - sy * dist;
  out_trans_m[1] = g_spawn_m[1] + height;
  out_trans_m[2] = g_spawn_m[2] - cy * dist;
  out_fwd[0] = sy * cp;
  out_fwd[1] = sp;
  out_fwd[2] = cy * cp;
  g_cam_pins++;
  return true;
}

void note_level_in_use(const char* level_name) {
  if (!enabled() || !level_name || !level_name[0]) {
    return;
  }
  std::lock_guard<std::mutex> lock(g_mutex);
  // Le niveau ATTENDU du vantage courant est-il devenu dessinable ? Releve a CHAQUE image, pas
  // seulement sur les photos : c'est l'instant d'apparition qui donne la marge.
  if (!g_vant_level_seen && g_cur < g_steps.size() &&
      std::strcmp(level_name, vantage_of(g_steps[g_cur]).level) == 0) {
    g_vant_level_seen = true;
  }
  if (g_cap != kCapInFlight) {
    return;
  }
  g_levels_seen.insert(level_name);
  g_frame_levels.insert(level_name);
}

bool capture_for_chain(int64_t lf, char* name_out, int name_cap, int* w, int* h) {
  if (!enabled()) {
    return false;
  }
  std::lock_guard<std::mutex> lock(g_mutex);
  if (g_cap != kCapArmed || lf < g_capture_frame) {
    return false;
  }
  // `lf > g_capture_frame` veut dire qu'une chaine a saute : on le MESURE au lieu de l'ignorer,
  // parce qu'un decalage d'une frame de logique suffit a faire mentir la comparaison.
  // Le decalage entre la frame de logique DEMANDEE et celle que porte la chaine rendue. Il est
  // constant par construction (l'ordre des appels dans une image de GOAL est fixe) ; ce qui
  // serait dangereux, c'est qu'il VARIE. On publie donc le min ET le max : `slip_min ==
  // slip_max` est la preuve que l'appariement est stable, un intervalle ouvert dit que non.
  const int64_t slip = lf - g_capture_frame;
  if (slip > g_frame_slip_max) {
    g_frame_slip_max = slip;
  }
  if (slip < g_frame_slip_min) {
    g_frame_slip_min = slip;
  }
  if (slip != 0) {
    // Un slip non nul veut dire que la chaine portant la frame DEMANDEE n'a jamais ete rendue :
    // la photo decrit une autre image de logique que celle du plan. On le COMPTE, parce que
    // `slip_min..slip_max` ne dit pas combien de photos sont concernees, et c'est ce nombre qui
    // rend une comparaison bit-a-bit impossible.
    g_slip_nonzero++;
  }
  g_inflight_lf = lf;
  g_frame_levels.clear();
  // Desarmer ICI, pas a la fin de la capture : entre les deux, le fil graphique dessine une ou
  // deux images de plus et re-prendrait la meme demande.
  g_cap = kCapInFlight;
  std::snprintf(name_out, name_cap, "%s", g_capture_name.c_str());
  *w = kShotW;
  *h = kShotH;
  return true;
}

bool consume_capture(int w, int h, const void* rgba) {
  if (!enabled()) {
    return false;
  }
  std::lock_guard<std::mutex> lock(g_mutex);
  if (g_cap != kCapInFlight) {
    return false;
  }
  const std::string path = image_path(g_capture_name);
  const int n_px = w * h;
  const uint8_t* cur = (const uint8_t*)rgba;
  // lighting-hdr : on mesure AVANT de comparer ou d'ecrire, dans les deux modes. Les
  // verdicts 1 et 2 portent sur ce que le moteur vient de dessiner, pas sur la reference.
  // Les grandeurs de `lighting-hdr` se mesurent au vantage HISTORIQUE seulement : `g_stats` est
  // indexe [phase][creneau], donc deux vantages a la meme heure s'ecraseraient l'un l'autre et
  // les verdicts appariraient deux photos de scenes differentes.
  if (vantage_of(g_steps[g_cur]).id[0] == 0) {
    measure_step(g_steps[g_cur].phase, g_steps[g_cur].hour, g_inflight_lf, cur, w, h);
  }

  if (g_mode == 1) {
    file_util::write_rgba_png(path, const_cast<void*>(rgba), w, h);
    g_captured++;
    write_capture_witness(g_steps[g_cur].phase);
    std::printf("REFSET cap %s step=%d/%d\n", g_capture_name.c_str(), (int)g_cur,
                (int)g_steps.size());
    std::fflush(stdout);
    // Un chemin n'est pas une preuve : on relit tout de suite ce qu'on vient d'ecrire et on
    // verifie que l'aller-retour PNG est exact. Sinon la reference ne vaut rien et personne ne
    // le saurait avant l'item suivant.
    std::vector<uint8_t> back;
    uint32_t bw = 0, bh = 0, bc = 0;
    if (fpng::fpng_decode_file(path.c_str(), back, bw, bh, bc, 4) != 0 || (int)bw != w ||
        (int)bh != h) {
      g_roundtrip_bad++;
    } else {
      uint64_t md = 0, np = 0;
      compare(cur, back.data(), n_px, &md, &np);
      if (md != 0) {
        g_roundtrip_bad++;
      }
    }
  } else {
    std::vector<uint8_t> ref;
    uint32_t rw = 0, rh = 0, rc = 0;
    const int rc_dec = fpng::fpng_decode_file(path.c_str(), ref, rw, rh, rc, 4);
    if (rc_dec == fpng::FPNG_DECODE_FILE_OPEN_FAILED) {
      g_missing++;
      std::printf("REFSET missing %s\n", path.c_str());
      std::fflush(stdout);
    } else if (rc_dec != 0) {
      g_decode_bad++;
    } else if ((int)rw != w || (int)rh != h) {
      g_size_bad++;
    } else {
      uint64_t md = 0, np = 0;
      compare(cur, ref.data(), n_px, &md, &np);
      g_compared++;
      if (md > g_maxdiff) {
        g_maxdiff = md;
      }
      {
        const size_t vi = (size_t)g_steps[g_cur].vant;
        if (vi < g_vstats.size() && md > g_vstats[vi].maxdiff) {
          g_vstats[vi].maxdiff = md;
        }
      }
      // LES GRANDEURS PAR JEU RESTENT CELLES DU VANTAGE HISTORIQUE, ET C'EST DELIBERE.
      // `refpix_maxdiff_origine` (lighting-unify), `verdict_master_off_bitexact`
      // (lighting-origin-bitexact) et les verdicts 1, 2 et 5 de `lighting-hdr` sont juges sur
      // huit creneaux a la hutte de Sandover. Les etendre aux 25 vantages neufs redefinirait
      // sous eux une mesure qu'ils ont deja passee. La couverture neuve vit dans ses PROPRES
      // grandeurs (`refset_dv_<vue>`, `refset_sky_views`, ...) et dans `refset_replay_maxdiff`,
      // qui lui porte sur TOUT le plan — c'est la porte de cet item.
      if (vantage_of(g_steps[g_cur]).id[0] == 0) {
        // Les phases valent 1..3. La borne haute etait `<= 2` : la phase 3 (ORIGINE-LUMIERE)
        // n'entrait donc JAMAIS dans `g_compared_phase`, et `verdict_origine_lumiere_set()`,
        // qui exige `g_compared_phase[3] == 8`, rendait 1 quoi qu'il arrive — le verdict 5
        // etait rouge par construction, comme `refpix_maxdiff_origine_lumiere` etait mort.
        // La case 0 n'existe pas (voir la declaration de g_maxdiff_phase).
        const int ph = g_steps[g_cur].phase;
        if (ph >= 1 && ph <= 3) {
          if (md > g_maxdiff_phase[ph]) {
            g_maxdiff_phase[ph] = md;
          }
          g_compared_phase[ph]++;
        }
      }
      g_diffpx += np;
      // Le validateur exige `FEATURE <id> armed=1 hits=>0` : une comparaison faite EST le chemin
      // de code de cet item qui tire. `hits` est un compteur global du harnais, pas le notre.
      autoport_proof::note_hit();
      // Une cle par PHOTO. Le vantage historique garde la cle nue `refset_d_<jeu>_hHH` — c'est
      // celle que les rapports des items precedents citent ; les vues neuves portent leur nom,
      // sans quoi 26 vantages ecriraient 26 fois la meme cle et seule la derniere survivrait.
      char key[160];
      const Vantage& kv = vantage_of(g_steps[g_cur]);
      if (kv.id[0]) {
        std::snprintf(key, sizeof(key), "refset_d_%s_%s_h%02d", set_name(g_steps[g_cur].phase),
                      kv.id, g_steps[g_cur].hour);
      } else {
        std::snprintf(key, sizeof(key), "refset_d_%s_h%02d", set_name(g_steps[g_cur].phase),
                      g_steps[g_cur].hour);
      }
      // LE TIRET EST FATAL A UNE CLE, EN SILENCE. `autoport_proof::publish` refuse une cle qui
      // ne respecte pas `[A-Za-z_][A-Za-z0-9_]*` sans rien dire (autoport_proof.h:74). Le jeu
      // ORIGINE-LUMIERE porte un tiret dans son nom : ses huit cles `refset_d_origine-lumiere_*`
      // etaient donc ecrites depuis lighting-hdr et n'ont JAMAIS atteint un proof.txt — un
      // compteur publie sans site d'ecriture lisible. Les 26 noms de vues en portent aussi.
      for (char* c = key; *c; c++) {
        if (*c == '-') {
          *c = '_';
        }
      }
      autoport_proof::publish(key, md);
      std::printf("REFSET cmp %s maxdiff=%llu diffpx=%llu\n", g_capture_name.c_str(),
                  (unsigned long long)md, (unsigned long long)np);
      std::fflush(stdout);
      if (md != 0) {
        // L'image REELLE d'un ecart est ecrite a cote de la preuve pour que l'ecart soit
        // localisable hors ligne. Elle ne prouve rien : c'est le nombre qui prouve.
        //
        // SUR ANDROID CE CHEMIN DOIT ETRE ABSOLU, et c'est la meme mine que celle deja payee
        // pour `g_dir` : `.autoport/reports/...` est relatif au CWD du processus, ce CWD est en
        // LECTURE SEULE sur l'appareil, et `create_dir_if_needed` appelle
        // `fs::create_directories` SANS `error_code` (FileUtil.cpp:530) — donc il LANCE.
        // L'exception traverse le fil graphique et devient `std::terminate` : un SIGABRT dont la
        // cause ne ressemble pas au symptome. Le declencheur n'est pas theorique : il suffit
        // qu'UNE comparaison rende un ecart non nul, ce qui est le cas nominal des le moment ou
        // la reference d'une phase vient d'un autre binaire.
#if defined(__ANDROID__)
        const std::string out = g_dir + "/actual";
#else
        const char* fid = autoport_proof::feature_id();
        const std::string out = std::string(".autoport/reports/") +
                                ((fid && fid[0]) ? fid : "lighting-census") + "/refset-actual";
#endif
        file_util::create_dir_if_needed(out);
        // Le nom porte la VUE : sans elle, 26 vantages ecriraient tous dans le meme fichier et
        // l'ecart ne serait plus localisable.
        std::string leaf = step_image_name(g_steps[g_cur]);
        for (char& c : leaf) {
          if (c == '/') {
            c = '-';
          }
        }
        file_util::write_rgba_png(out + "/" + leaf + ".png", const_cast<void*>(rgba), w, h);
      }
    }
  }

  g_cap = kCapDone;
  publish_state();
  return true;
}


// ── lighting-hdr : quatre des six verdicts de `hdr_tonemap_defects` ─────────────────────────
// Convention, la meme partout : 0 = tenu, 1 = defaut. JAMAIS de troisieme valeur « pas
// mesurable » — une grandeur qu'on n'a pas pu mesurer est un defaut, pas un silence. Sans cette
// regle, une course qui n'irait pas au bout rendrait un zero et fermerait la porte pour rien.

// Verdict 4 — master eteint, sortie identique au bit a ORIGINE-TOTAL.
int verdict_master_off_bitexact() {
#if AUTOPORT_ORIGIN_ABLATE
  // UN BINAIRE D'ABLATION NE JUGE RIEN. Il ne contient pas la couche dont on affirme
  // l'innocuite : son zero ne voudrait rien dire, et il ne doit pas pouvoir fermer la porte.
  return 1;
#else
  const bool clean = !g_missing && !g_size_bad && !g_decode_bad;
  if (g_mode != 2 || !clean || g_compared_phase[1] != 8 || g_maxdiff_phase[1] != 0) {
    return 1;
  }
  // La reference doit venir d'un AUTRE binaire que celui-ci — voir le temoin de capture.
  const uint64_t w = read_capture_witness(1);
  if (w == 0 || w == self_fingerprint()) {
    return 1;
  }
  // ... et pas de n'importe quel autre binaire : d'un binaire ou la couche Recharged n'est pas
  // COMPILEE. C'est la definition que la SPEC donne du jeu d'origine (§1.1 regle 1 point 3 :
  // « son OFF est bit-identique a son ABSENCE »). Une reference capturee par un binaire normal
  // avec le drapeau a zero ne verrait aucun site qui remplace le vanilla sans consulter le
  // maitre — le defaut meme que cet item cherche.
  if (read_capture_flavour(1) != "ablate") {
    return 1;
  }
  return 0;
#endif
}

// Verdict 5 — le jeu ORIGINE-LUMIERE existe ET sert de base aux verdicts 1-3. « Exister » ne
// suffit pas : il faut que ses huit creneaux aient ete compares ET mesures, sinon les verdicts
// 1 et 2 s'appuieraient sur un jeu partiel sans que rien ne le dise.
int verdict_origine_lumiere_set() {
  if (g_mode != 2 || g_compared_phase[3] != 8) {
    return 1;
  }
  for (int i = 0; i < 8; i++) {
    if (!g_stats[3][i].measured) {
      return 1;
    }
  }
  return 0;
}

// Verdict 1 — la part de pixels satures de RECHARGED ne depasse celle d'ORIGINE-LUMIERE sur
// AUCUN creneau. Le maximum par creneau, pas la moyenne : une moyenne laisserait un creneau
// brule se faire compenser par sept creneaux sombres.
int verdict_saturation() {
  if (g_mode != 2) {
    return 1;
  }
  int paired = 0;
  for (int i = 0; i < 8; i++) {
    const StepStats& r = g_stats[2][i];
    const StepStats& o = g_stats[3][i];
    if (!r.measured || !o.measured || r.px != o.px) {
      return 1;
    }
    paired++;
    if (r.sat_px > o.sat_px) {
      return 1;
    }
  }
  return paired == 8 ? 0 : 1;
}

// Verdict 2 — le contraste local du decile le plus lumineux vaut au moins 95 % de celui
// d'ORIGINE-LUMIERE, sur CHAQUE creneau. C'est la mesure de « la courbe preserve le detail » :
// une zone ecrasee a blanc plat a un gradient local nul.
int verdict_highlight_contrast() {
  if (g_mode != 2) {
    return 1;
  }
  for (int i = 0; i < 8; i++) {
    const StepStats& r = g_stats[2][i];
    const StepStats& o = g_stats[3][i];
    if (!r.measured || !o.measured) {
      return 1;
    }
    // o == 0 : la reference n'a aucun detail dans son decile ; on ne peut pas en perdre.
    if (o.contrast_x1000 == 0) {
      continue;
    }
    if (r.contrast_x1000 * 100ull < 95ull * o.contrast_x1000) {
      return 1;
    }
  }
  return 0;
}

}  // namespace refset
