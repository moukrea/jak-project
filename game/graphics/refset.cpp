#include "game/graphics/refset.h"
#include "game/system/recharged_gating.h"

#include <algorithm>
#include <atomic>
#include <charconv>
#include <chrono>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <map>
#include <mutex>
#include <set>
#include <string>
#include <system_error>
#include <tuple>
#include <utility>
#include <vector>

#include "common/log/log.h"
#include "common/util/FileUtil.h"

#include "game/graphics/fixed_tick.h"
#include "game/graphics/gfx.h"
#include "game/graphics/opengl_renderer/background/foliage_wind.h"
#include "game/graphics/opengl_renderer/hdr.h"
#include "game/graphics/opengl_renderer/lighting_census.h"
#include "game/graphics/origin_ablate.h"
#include "game/graphics/refset_file.h"
#include "game/graphics/refset_qualification.h"
#include "game/graphics/refset_state.h"
#include "game/graphics/render_pace.h"
#include "game/system/asset_manifest.h"
#include "game/system/autoport_proof.h"
#include "game/system/pad_replay.h"

#include "third-party/fpng/fpng.h"

#if defined(__ANDROID__)
#include <dlfcn.h>
#include <sys/system_properties.h>
#endif

namespace refset {
namespace {

std::atomic<uint64_t> g_bootstrap_fingerprint{0};
bool g_require_loaded = false;
struct LoadedSnapshot {
  int64_t frame;
  bool target;
  bool spawn;
  bool sweep;
  std::vector<LoadedLevelState> levels;
};
constexpr size_t kLoadedSnapshotWindow = 8;
std::vector<LoadedSnapshot> g_loaded_snapshots;
std::vector<std::string> g_initial_levels;
std::string g_initial_display;
std::string g_initial_levels_spec;
std::string g_initial_display_spec;
LoadRestoreRequest g_load_restore;
bool g_load_restore_pending = false;

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
    // resultat porte seulement sur ces placements : un cadrage donnant assez de ciel reste
    // a trouver. Le couple (sunkenb, chaque creneau) reste compte MANQUANT par
    // `refset_sky_missing`, avec sa valeur mesuree — on ne retire pas le niveau de la liste.
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
    // lighting-hdr essai 62 : le SOL devant la hutte du Sage vert (cas owner « petites zones
    // au sol violettes ON », boite monde `kSageHutGround` ci-dessous, centre (-123.05, 47.3,
    // 204.8)). Tournee de calibrage du 2026-09-09 12:51 (lot essai62-x86-ground-survey, huit
    // placements par OG_REFSET_CAM_BY_HOUR) : a 3,5 m de haut sans recul (-25:180:0:35) la
    // camera est contre le mur de pierre du soubassement ; a 15 m de recul et 12 m de haut,
    // pitch -45, tournee de 180 deg (regarde vers +z), l'image montre la hutte, sa terrasse de
    // bois devant la porte et la pente d'herbe aux taches de sable : c'est le cadrage retenu.
    // La boite projette sur la terrasse devant la porte (ROI [131,38,173,68] a h06).
    {"village1-sage-ground", "village1-hut", "-123 47.3 196", "village1", kAllHours, -45, 180, 150, 120},
    // lighting-hdr essai 62 : interieur de la hutte du Sage, portail acteur 1395 cadre. C'est
    // l'ancienne surcharge `OG_REFSET_CAM=village1-out:-10:-108:152:33` des essais 52-61,
    // promue en vue dediee pour que les lots des cas owner ne dupliquent pas les couples
    // (vue, heure) de la couverture.
    {"village1-portal", "village1-hut", "-126 46 212", "village1", kAllHours, -10, -108, 152, 33},
    // lighting-hdr essai 62 : soleil couchant a h18 sur la plage. C'est la surcharge
    // `OG_REFSET_CAM_BY_HOUR 7:-35:0:5000` de l'essai 53 (sky-fixed), promue en vue dediee.
    {"beach-sun", "beach-start", "", "beach", kAllHours, 7, -35, 0, 500},
    // Dedicated opt-in view. Actor aid10012 is at 9.3109 19.2490 11.2525;
    // spawn 8 m before it to avoid collecting it, camera 2 m above, looking toward +Z.
    {"village1-eco-blue", "village1-hut", "9.3109 19.2490 3.2525", "village1", kAllHours,
     -14, -163, 0, 20},
};
constexpr int kNumSelectableVantages = (int)(sizeof(kVantages) / sizeof(kVantages[0]));
// The explicitly selected diagnostic view does not extend the historical coverage universe.
constexpr int kNumVantages = kNumSelectableVantages - 1;

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
CamTune g_cam_tune[kNumSelectableVantages];
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
  int vant;  // index dans g_vants
  bool supplemental = false;
  int sample = 0;
};
int g_temporal_samples = 1;

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
int g_hdr_capture_scale = 1;
constexpr const char* kHdrReduction = "box_integer_half_up_v1";

std::mutex g_mutex;

int g_mode = 0;  // 0 = eteint, 1 = capture, 2 = replay
// lighting-hdr : le dossier par defaut DIFFERE par plateforme, et ce n'est pas une precaution
// de style. Les references x86 sont re-rendues en 320x180 en resolution interne ; celles de
// l'appareil sont un sous-echantillonnage d'un tampon 4:3. Comparer les unes aux autres est faux
// PAR CONSTRUCTION. On rend donc le melange impossible au point de PRODUCTION plutot que
// detectable au point de controle : les deux familles ne portent pas le meme nom.
std::string g_dir = ".autoport/refset";  // Android : rendu ABSOLU a l'init, voir `enabled()`
int g_provenance_version = 1;  // 0 = root marker unreadable/invalid, 1 = historical, 2 = candidate
uint64_t g_data_fp = 0;
uint64_t g_input_fp = 0;
using QualificationJson = nlohmann::json;
QualificationJson g_qualification_cases = QualificationJson::array();
uint64_t g_qualification_bad = 0;
uint64_t g_qualification_source_fp = 0;
uint64_t g_qualification_settings_fp = 0;
uint64_t g_qualification_capture_fp = 0;
std::string g_qualification_source;
bool g_qualification_adopted = false;
bool g_qualification_written = false;
uint64_t g_case_bg = 0, g_case_px = 0, g_case_probes = 0;
uint64_t g_case_maxdiff = 255, g_case_diffpx = 0;
std::optional<refset_state::Sample> g_case_state;
void qualification_finish();
void qualification_sample(const Step& step, const QualificationJson& effective_options);
constexpr const char* kFormatMarker = "refset-format.txt";

std::vector<int> g_phases;  // lighting-hdr : les phases que CE plan execute
std::vector<int> g_vants;   // lighting-census : les vantages que CE plan parcourt
std::vector<Step> g_steps;
// Les grandeurs de COUVERTURE, une entree par vantage retenu, remplies a la photo.
struct VantStat {
  uint64_t shots = 0;          // photos prises a ce vantage (tous jeux, tous creneaux)
  uint64_t bg_ppm_min = ~0ull;  // fraction d'arriere-plan en ppm : minimum sur ses photos
  uint64_t bg_ppm_max = 0;      // ... et le maximum
  uint64_t px = 0;             // surface de la derniere sonde, pour verifier sa presence
  uint64_t maxdiff = 0;        // le pire ecart de rejeu de ce vantage
  uint64_t level_ok = 0;       // photos ou le niveau ATTENDU etait bien en service
  // LE MEME TRIO, VENTILE PAR CRENEAU HORAIRE. La porte de l'owner porte sur un COUPLE
  // (niveau a ciel, heure fixe) : « pour chaque couple le ciel occupe >= 15 % ». Un minimum
  // agrege sur les huit heures ne peut pas repondre a cette question — il dirait « cette vue
  // montre le ciel » alors que le creneau de 0 h n'en montre pas. Un agregat par vue etait
  // exactement la faiblesse que le superviseur a nommee le 2026-09-07.
  uint64_t shots_h[8] = {0};
  uint64_t level_ok_h[8] = {0};
  uint64_t bg_ppm_min_h[8] = {~0ull, ~0ull, ~0ull, ~0ull, ~0ull, ~0ull, ~0ull, ~0ull};
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
thread_local int64_t g_render_logic_frame = -1;
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
int64_t g_temporal_repin_case = -1;
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
// La camera de l'image EN VOL, copiee par `note_camera` au bucket DEPTH_CUE (fil graphique,
// sous le verrou). `g_cam_noted_lf == g_inflight_lf` = notee pour CETTE image ; sinon la ligne
// `HDR-OWNER-GROUND` sort `supported=false`.
float g_cam_matrix[16] = {0.f};
float g_cam_hvdf_off[4] = {0.f};
float g_cam_fog[4] = {0.f};
int64_t g_cam_noted_lf = -1;
// lighting-hdr essai 62 : boite monde (METRES) du sol devant la hutte du Sage vert, cas owner
// « petites zones au sol violettes ON ». Source : notes/essai53/decision.md, ancre
// `vil1-jng-leafyground`, triangles 1104-1135 : x[-127.485,-118.610] y~47.3 z[200.328,209.203].
// Elargie (essai 62, tournee de calibrage) de 6 m en x de chaque cote et de 16 m vers la camera
// (z >= 184), hauteur 44..50 m, pour englober la pente d'herbe et de sable devant la terrasse et
// pas seulement la terrasse. Convertie en unites GOAL (x4096) a la projection.
constexpr float kSageHutGround[6] = {-133.5f, 44.0f, 184.0f, -112.6f, 50.0f, 209.203f};

// ── mesures ─────────────────────────────────────────────────────────────────────────────────
uint64_t g_captured = 0;
uint64_t g_temporal_captured = 0;
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
uint64_t g_provenance_checked = 0;
uint64_t g_provenance_bad = 0;
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
// La porte census exige la couverture et une qualification courante avec rejeu exact. Les autres items
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

// Caller holds g_mutex. Rendering can trail GOAL dispatch: select the newest
// sample at or before the observed frame, with the same maximum lag of one.
std::string loaded_state_problem(int64_t frame, int64_t* selected_frame = nullptr) {
  const LoadedSnapshot* snapshot = nullptr;
  for (auto it = g_loaded_snapshots.rbegin(); it != g_loaded_snapshots.rend(); ++it) {
    if (it->frame <= frame && (!snapshot || it->frame > snapshot->frame)) {
      snapshot = &*it;
    }
  }
  if (selected_frame) *selected_frame = snapshot ? snapshot->frame : -1;
  if (!snapshot) return "missing-snapshot;";
  std::string problem;
  auto require_level = [&](const std::string& name, bool active) {
    if (name.empty()) {
      return;
    }
    std::string status = "missing";
    for (const auto& level : snapshot->levels) {
      if (level.name == name) {
        status = level.status;
        break;
      }
    }
    if (status != "active" && (active || status != "loaded")) {
      problem += name + "=" + status + (active ? "(need active);" : "(need loaded/active);");
    }
  };
  if (snapshot->frame < 0 || frame - snapshot->frame > 1) {
    problem += "stale-snapshot;";
  }
  if (!snapshot->target) problem += "*target*=absent;";
  if (!snapshot->spawn) problem += "*spawn-actors*!=#t;";
  if (!snapshot->sweep) problem += "*actors-sweep-complete*!=#t;";
  if (g_cur < g_steps.size()) {
    if (first_step_of_vant(g_cur) == 0) {
      for (const auto& name : g_initial_levels) {
        require_level(name, name == g_initial_display);
      }
      require_level(g_initial_display, true);
    }
    require_level(vantage_of(g_steps[g_cur]).level, true);
  }
  return problem;
}

void require_loaded_state(int64_t frame, const char* point) {
  if (!g_require_loaded) return;
  int64_t selected_frame = -1;
  const std::string problem = loaded_state_problem(frame, &selected_frame);
  if (problem.empty()) return;
  autoport_proof::publish("refset_loaded_guard_failed", 1);
  autoport_proof::publish_text("refset_loaded_guard_error", problem.c_str());
  std::fprintf(stderr, "REFSET loaded-state refused point=%s case=%zu lf=%lld snapshot_lf=%lld "
                       "reason=%s\n", point, g_cur, (long long)frame,
                       (long long)selected_frame, problem.c_str());
  std::fflush(stderr);
  std::fflush(stdout);
  // This can run on the GOAL thread while GL still renders. exit() destroys
  // shared shader caches under that renderer; preserve the failure without teardown races.
  std::_Exit(EXIT_FAILURE);
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
  if (s.sample > 0) {
    char suffix[16];
    std::snprintf(suffix, sizeof(suffix), "-t%02d", s.sample);
    return std::string(nm) + suffix;
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
  uint64_t near_white_px = 0;  // RGB >= 245
  uint64_t luma_mean_x1000 = 0;
  uint64_t luma_quantiles[4] = {};     // p10, p50, p90, p99, 0..255
  uint64_t saturation_mean_x1000 = 0;  // HSV S, 0..1000
  uint64_t hue_bins[12] = {};          // seuls les pixels de chroma > 0
  uint64_t saturation_bins[8] = {};    // HSV S, tous les pixels
  std::set<std::string> levels;        // niveaux effectivement dessines lors de la prise
  uint64_t contrast_x1000 = 0;  // contraste local moyen du decile le plus lumineux
  uint64_t decile_px = 0;    // combien de pixels ce decile contenait
  // LE DENOMINATEUR DES VERDICTS 1 ET 2 : la frame de LOGIQUE de la photo. Les deux verdicts
  // apparient RECHARGED et ORIGINE-LUMIERE au meme creneau ; l'ecart de frames entre les deux
  // photos est ce qui melange l'effet de la courbe et celui du temps qui passe. Sans lui,
  // `hdr_hlc_pct_h21=92` ne dit pas si la courbe a ecrase le detail ou si 1440 images de logique
  // ont deplace ce qui bouge dans le decor.
  int64_t cap_lf = -1;
};
// Step.vant est local au plan ; aucune autre vue ne peut ecraser cette clef.
std::map<std::tuple<int, int, int>, StepStats> g_hdr_stats;
StepStats g_stats[4][8];  // [phase 1..3][index de creneau 0..7]

// Les petits ecarts de mouvement sont toleres jusqu'a 0,1 % des pixels OU 5 % du
// compte OFF (le plus grand des deux). Cette marge ne depend jamais du compte ON.
uint64_t hdr_motion_tolerance(const StepStats& off, uint64_t count) {
  return std::max(off.px / 1000, count / 20);
}

const StepStats* hdr_stats(int vant, int phase, int hour) {
  auto it = g_hdr_stats.find({vant, phase, hour});
  return it == g_hdr_stats.end() ? nullptr : &it->second;
}

bool hdr_pair(int vant, int hour, const StepStats*& on, const StepStats*& off) {
  on = hdr_stats(vant, 2, hour);
  off = hdr_stats(vant, 3, hour);
  if (vant < 0 || vant >= int(g_vants.size()))
    return false;
  const char* expected_level = kVantages[g_vants[vant]].level;
  return on && off && on->measured && off->measured && on->px == off->px &&
         on->levels.count(expected_level) && off->levels.count(expected_level);
}

uint64_t hdr_paired_count() {
  uint64_t paired = 0;
  for (int global = 0; global < kNumSelectableVantages; ++global) {
    auto it = std::find(g_vants.begin(), g_vants.end(), global);
    if (it == g_vants.end())
      continue;
    for (int hour : kHours) {
      const StepStats *on, *off;
      if (hdr_pair(int(it - g_vants.begin()), hour, on, off))
        ++paired;
    }
  }
  return paired;
}

void publish_hdr_coverage() {
  const uint64_t paired = hdr_paired_count();
  uint64_t expected = kNumVantages * 8ull;
  for (int global : g_vants) {
    if (global >= kNumVantages) expected += 8;
  }
  autoport_proof::publish("hdr_paired", paired);
  autoport_proof::publish("hdr_expected", expected);
  autoport_proof::publish("hdr_missing", expected - paired);
  std::set<std::string> levels;
  for (int vi = 0; vi < int(g_vants.size()); ++vi) {
    for (int hour : kHours) {
      const StepStats *on, *off;
      if (!hdr_pair(vi, hour, on, off))
        continue;
      levels.insert(kVantages[g_vants[vi]].level);
    }
  }
  std::string names;
  for (const auto& level : levels) {
    if (!names.empty())
      names += ",";
    names += level;
  }
  autoport_proof::publish("hdr_paired_levels", levels.size());
  autoport_proof::publish_text("hdr_paired_levels_list", names.empty() ? "aucun" : names.c_str());
}

void publish_hdr_step(const Step& step, const StepStats& st) {
  std::string view = vantage_of(step).id;
  if (view.empty())
    view = "legacy";
  for (char& c : view) {
    if (!((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9')))
      c = '_';
  }
  const std::string base = "hdr_" + view + "_h" + std::to_string(step.hour);
  const std::string phase = base + "_p" + std::to_string(step.phase) + "_";
  auto number = [&](const std::string& key, uint64_t value) {
    autoport_proof::publish((phase + key).c_str(), value);
  };
  std::string level_names;
  for (const auto& level : st.levels) {
    if (!level_names.empty())
      level_names += ",";
    level_names += level;
  }
  autoport_proof::publish_text((phase + "levels").c_str(),
                               level_names.empty() ? "aucun" : level_names.c_str());
  number("pixels", st.px);
  number("sat", st.sat_px);
  number("white", st.sat_white_px);
  number("nearwhite", st.near_white_px);
  number("luma_mean_x1000", st.luma_mean_x1000);
  number("saturation_mean_x1000", st.saturation_mean_x1000);
  number("hl_contrast_x1000", st.contrast_x1000);
  number("decile_pixels", st.decile_px);
  autoport_proof::publish_text((phase + "cap_lf").c_str(), std::to_string(st.cap_lf).c_str());
  const int quantiles[] = {10, 50, 90, 99};
  for (int q = 0; q < 4; ++q)
    number("luma_p" + std::to_string(quantiles[q]), st.luma_quantiles[q]);
  for (int i = 0; i < 12; ++i)
    number("hue_bin" + std::to_string(i), st.hue_bins[i]);
  for (int i = 0; i < 8; ++i)
    number("saturation_bin" + std::to_string(i), st.saturation_bins[i]);
  const StepStats *on, *off;
  if (!hdr_pair(step.vant, step.hour, on, off))
    return;
  auto delta = [&](const std::string& key, uint64_t a, uint64_t b) {
    autoport_proof::publish_text((base + "_delta_" + key).c_str(),
                                 std::to_string(int64_t(a) - int64_t(b)).c_str());
  };
  delta("sat", on->sat_px, off->sat_px);
  delta("white", on->sat_white_px, off->sat_white_px);
  delta("nearwhite", on->near_white_px, off->near_white_px);
  delta("luma_mean_x1000", on->luma_mean_x1000, off->luma_mean_x1000);
  delta("saturation_mean_x1000", on->saturation_mean_x1000, off->saturation_mean_x1000);
  delta("hl_contrast_x1000", on->contrast_x1000, off->contrast_x1000);
  for (int q = 0; q < 4; ++q)
    delta("luma_p" + std::to_string(quantiles[q]), on->luma_quantiles[q], off->luma_quantiles[q]);
  for (int i = 0; i < 12; ++i)
    delta("hue_bin" + std::to_string(i), on->hue_bins[i], off->hue_bins[i]);
  for (int i = 0; i < 8; ++i)
    delta("saturation_bin" + std::to_string(i), on->saturation_bins[i], off->saturation_bins[i]);
  autoport_proof::publish((base + "_hl_contrast_ratio_defined").c_str(), off->contrast_x1000 != 0);
  autoport_proof::publish(
      (base + "_hl_contrast_ratio_x1000").c_str(),
      off->contrast_x1000 ? on->contrast_x1000 * 1000 / off->contrast_x1000 : 0);
  auto excess = [&](const char* key, uint64_t a, uint64_t b) {
    const uint64_t tolerance = hdr_motion_tolerance(*off, b);
    autoport_proof::publish((base + "_" + key + "_tolerance").c_str(), tolerance);
    autoport_proof::publish((base + "_" + key + "_excess").c_str(),
                            a > b + tolerance ? a - b - tolerance : 0);
  };
  excess("sat", on->sat_px, off->sat_px);
  excess("white", on->sat_white_px, off->sat_white_px);
  excess("nearwhite", on->near_white_px, off->near_white_px);
}

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

void measure_step(const Step& step, int64_t cap_lf, const uint8_t* px, int w, int h) {
  const int phase = step.phase, hour = step.hour;
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
    if (p[0] >= 245 && p[1] >= 245 && p[2] >= 245) {
      st.near_white_px++;
    }
    const int mx = std::max({int(p[0]), int(p[1]), int(p[2])});
    const int mn = std::min({int(p[0]), int(p[1]), int(p[2])});
    const int chroma = mx - mn;
    const uint64_t saturation = mx ? (1000ull * chroma) / mx : 0;
    st.saturation_mean_x1000 += saturation;
    st.saturation_bins[std::min<uint64_t>(7, saturation * 8 / 1000)]++;
    if (chroma > 0) {
      // Hue en six secteurs, deux bins par secteur, sans arrondi flottant.
      int hue = mx == p[0]   ? int(p[1]) - p[2]
                : mx == p[1] ? 2 * chroma + p[2] - p[0]
                             : 4 * chroma + p[0] - p[1];
      if (hue < 0)
        hue += 6 * chroma;
      st.hue_bins[(2 * hue) / chroma]++;
    }
    const uint32_t lum = luma(p);
    st.luma_mean_x1000 += lum * 1000ull;
    hist[lum]++;
  }

  st.luma_mean_x1000 /= st.px;
  st.saturation_mean_x1000 /= st.px;
  const int percentiles[] = {10, 50, 90, 99};
  for (int q = 0; q < 4; ++q) {
    uint64_t cumulative = 0;
    for (int lum = 0; lum < 256; ++lum) {
      cumulative += hist[lum];
      if (cumulative * 100 >= st.px * percentiles[q]) {
        st.luma_quantiles[q] = lum;
        break;
      }
    }
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
  if (vantage_of(step).id[0] == 0) {
    g_stats[phase][hi] = st;
  }
  if (autoport_proof::feature_is("lighting-hdr")) {
    // A loaded level is insufficient when the captured frame is a fade or an
    // achromatic loading screen. Keep its raw statistics, but never let it supply
    // a lighting comparison. This does not qualify other frames as representative.
    const bool black = st.luma_quantiles[3] <= 2;
    const bool achromatic = std::all_of(std::begin(st.hue_bins), std::end(st.hue_bins),
                                      [](uint64_t count) { return count == 0; });
    if (black || achromatic) {
      st.measured = false;
      std::printf("REFSET lighting sample rejected view=%s hour=%d phase=%d reason=%s\n",
                  vantage_of(step).id[0] ? vantage_of(step).id : "legacy", hour, phase,
                  black ? "black" : "achromatic");
    }
    st.levels = g_frame_levels;
    g_hdr_stats[{step.vant, phase, hour}] = st;
    publish_hdr_step(step, st);
  }
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

uint64_t read_capture_witness(int phase, bool supplemental = false);

// Le temoin de capture est ecrit et relu plus bas (section « LE TEMOIN DE CAPTURE ») ;
// `publish_state` le publie, d'ou cette declaration avant usage.
std::string read_capture_flavour(int phase, bool supplemental = false);
std::string witness_path(int phase, bool supplemental = false);

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
        const uint64_t pm = vs.bg_ppm_min_h[hi] / 1000ull;
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
  const bool census = autoport_proof::feature_is("lighting-census");
  const std::vector<int> phases = census ? std::vector<int>{2, 3} : std::vector<int>{1, 2, 3};
  const auto arms = phases.size();
  const bool full_plan = g_vants.size() == kNumVantages && g_steps.size() == kNumVantages * 8 * arms &&
                         g_phases == phases && g_hours_mask == kAllHours;
  if (!full_plan || !g_cam_armed || g_cam_overrides || g_pitch_sweep || g_yaw_sweep ||
      g_cam_hour_sweep || g_slip_nonzero || g_roundtrip_bad || g_provenance_bad) {
    g_census_coverage_missing++;
  }
  for (const auto& vs : g_vstats) {
    for (int hi = 0; hi < 8; hi++) {
      if (vs.shots_h[hi] != arms || vs.level_ok_h[hi] != arms || !vs.px_h[hi]) {
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
    const uint64_t pm_min = vs.bg_ppm_min / 1000ull;
    const uint64_t pm_max = vs.bg_ppm_max / 1000ull;
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
                      (unsigned long long)(vs.bg_ppm_min_h[hh] / 1000ull));
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
  if (autoport_proof::feature_is("lighting-hdr"))
    publish_hdr_coverage();
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
  autoport_proof::publish("refset_temporal_samples", g_temporal_samples);
  autoport_proof::publish("refset_temporal_captured", g_temporal_captured);
  autoport_proof::publish("refset_slip_max", (uint64_t)(g_frame_slip_max < 0 ? 0
                                                                             : g_frame_slip_max));
  autoport_proof::publish("refset_slip_min",
                          (uint64_t)(g_frame_slip_min > (1 << 19) ? 0 : g_frame_slip_min));
  autoport_proof::publish("refset_roundtrip_bad", g_roundtrip_bad);
  autoport_proof::publish("refset_provenance_checked", g_provenance_checked);
  autoport_proof::publish("refset_provenance_bad", g_provenance_bad);
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
    if (g_missing || g_size_bad || g_decode_bad || g_provenance_bad) {
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
                                ? std::max(g_census_replay_gate,
                                    g_census_coverage_missing && !g_qualification_adopted
                                        ? uint64_t(254) : uint64_t(0))
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
    if (!autoport_proof::feature_is("lighting-hdr")) {
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
        const uint64_t ratio = o.contrast_x1000 ? (r.contrast_x1000 * 100ull) / o.contrast_x1000
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
        const uint64_t gap =
            (uint64_t)(r.cap_lf > o.cap_lf ? r.cap_lf - o.cap_lf : o.cap_lf - r.cap_lf);
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
    }
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
  // Les portes historiques restent propres au replay ; HDR mesure ses deux phases en capture.
}

std::string image_path(const Step& step) {
  // The eight old files outside the 564-case capture have no provenance for the extension.
  // Never fall back to them merely because their names match.
  return g_dir + (step.supplemental ? "/supplement-v1/" : "/") +
         step_image_name(step) + ".png";
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
using refset_file::hash_file;

// Les SEIZE references, dans l'ordre du plan. Une reference qui bouge d'un octet change
// l'empreinte, donc coupe le registre : on ne compare jamais deux courses jugees sur des
// references differentes.
uint64_t refs_fingerprint() {
  uint64_t h = 1469598103934665603ull;
  if (!g_provenance_version) {
    return 0;
  }
  if (g_provenance_version == 2) {
    const uint64_t marker = hash_file(g_dir + "/" + kFormatMarker);
    if (!marker) {
      return 0;
    }
    for (int b = 0; b < 8; b++) {
      h = (h ^ ((marker >> (8 * b)) & 0xff)) * 1099511628211ull;
    }
  }
  // TOUTES les references du plan, dans l'ordre du plan — pas « les seize » : le plan en compte
  // autant qu'il a d'etapes, et une vue ajoutee doit perimer le registre comme n'importe quel
  // autre changement de reference.
  for (const Step& s : g_steps) {
    std::vector<std::string> paths = {image_path(s)};
    if (s.supplemental || g_provenance_version == 2) {
      paths.push_back(image_path(s) + ".provenance.txt");
      paths.push_back(witness_path(s.phase, s.supplemental));
    }
    for (const auto& path : paths) {
      const uint64_t fh = hash_file(path);
      if (!fh) {
        return 0;
      }
      for (int b = 0; b < 8; b++) {
        h ^= (unsigned char)((fh >> (8 * b)) & 0xff);
        h *= 1099511628211ull;
      }
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
  // Inventaire des ressources selectionnables, pas une trace des fichiers ouverts. Les
  // overlays remplacent un basename, comme fake_iso et resolve_fr3_asset. Les noms logiques
  // restent ceux du registre historique : sans override, l'empreinte reste identique.
  std::map<std::string, fs::path> files;
  auto scan = [&files](const fs::path& dir, const char* prefix, const char* ext,
                       bool optional) {
    std::error_code ec;
    const auto status = fs::symlink_status(dir, ec);
    const bool absent = status.type() == fs::file_type::not_found &&
                        (!ec || ec == std::errc::no_such_file_or_directory);
    if (optional && absent) {
      return true;
    }
    if (ec) {
      return false;
    }
    fs::directory_iterator it(dir, ec), end;
    if (ec) {
      return false;
    }
    for (; it != end; it.increment(ec)) {
      if (ec) {
        return false;
      }
      const auto& e = *it;
      std::error_code ec2;
      const bool regular = e.is_regular_file(ec2);
      if (ec2) {
        return false;
      }
      if (!regular) {
        continue;
      }
      const std::string name = e.path().filename().string();
      const size_t n = std::strlen(ext);
      if (name.size() > n && name.compare(name.size() - n, n, ext) == 0) {
        files[std::string(prefix) + name] = e.path();
      }
    }
    return !ec;
  };
  const fs::path iso = file_util::get_iso_out_dir(GameVersion::Jak1);
  const fs::path fr3 = file_util::get_fr3_dir(GameVersion::Jak1);
  if (!scan(iso, "iso/", ".CGO", false) || !scan(iso, "iso/", ".DGO", false) ||
      !scan(fr3, "fr3/", ".fr3", false)) {
    return 0;
  }
  if (const auto overlay = file_util::get_iso_overlay_dir(); overlay &&
      (!scan(*overlay, "iso/", ".CGO", true) || !scan(*overlay, "iso/", ".DGO", true))) {
    return 0;
  }
  if (const auto custom = file_util::get_custom_fr3_dir(); custom &&
      !scan(*custom, "fr3/", ".fr3", true)) {
    return 0;
  }
  // Les categories obligatoires se jugent apres l'union, y compris les fichiers qui
  // existent exclusivement dans un overlay.
  auto has_category = [&files](const char* prefix, const char* ext) {
    const size_t n = std::strlen(ext);
    return std::any_of(files.begin(), files.end(), [=](const auto& f) {
      return f.first.compare(0, std::strlen(prefix), prefix) == 0 && f.first.size() > n &&
             f.first.compare(f.first.size() - n, n, ext) == 0;
    });
  };
  if (!has_category("iso/", ".CGO") || !has_category("iso/", ".DGO") ||
      !has_category("fr3/", ".fr3")) {
    return 0;
  }
  // hd_fr3_path consulte enhanced uniquement dans le pack de base, jamais dans custom.
  if (!scan(fr3 / "enhanced", "fr3/enhanced/", ".fr3", true)) {
    return 0;
  }
  // La map trie les noms logiques, independamment de l'ordre du systeme de fichiers.
  uint64_t h = 1469598103934665603ull;
  for (const auto& f : files) {
    const uint64_t fh = hash_file(f.second.string());
    if (!fh) {
      return 0;
    }
    // Le nom entre dans l'empreinte : deux fichiers qui echangent leur contenu ne doivent pas
    // rendre la meme valeur.
    for (unsigned char c : f.first) {
      h ^= c;
      h *= 1099511628211ull;
    }
    h = (h ^ 0xff) * 1099511628211ull;
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
std::string witness_path(int phase, bool supplemental) {
  return g_dir + (supplemental ? "/supplement-v1/" : "/") + set_name(phase) +
         "/captured-by.txt";
}

[[noreturn]] void capture_directory_error(const char* operation, const std::error_code& ec) {
  std::fprintf(stderr, "REFSET capture refused dir=%s operation=%s error=%s; "
                       "OG_REFSET_DIR must name a new directory\n",
               g_dir.c_str(), operation, ec ? ec.message().c_str() : "already exists");
  std::fflush(stderr);
  std::exit(EXIT_FAILURE);
}

void reserve_capture_directory() {
  // Reserve the root atomically before writing any reference or provenance. In particular,
  // create_directory returns false for an existing directory, including a directory symlink.
  fs::path root(g_dir);
  while (root != root.root_path() && root.filename().empty()) {
    root = root.parent_path();
  }
  std::error_code ec;
  const fs::path parent = root.parent_path();
  if (!parent.empty()) {
    fs::create_directories(parent, ec);
    if (ec) {
      capture_directory_error("create-parent", ec);
    }
  }
  if (!fs::create_directory(root, ec)) {
    capture_directory_error("reserve-root", ec);
  }
  for (const char* set : {"origine", "recharged", "origine-lumiere"}) {
    if (!fs::create_directory(root / set, ec)) {
      capture_directory_error("create-set", ec);
    }
  }
  if (!fs::create_directory(root / "supplement-v1", ec)) {
    capture_directory_error("create-supplement", ec);
  }
  for (const char* set : {"origine", "recharged", "origine-lumiere"}) {
    if (!fs::create_directory(root / "supplement-v1" / set, ec)) {
      capture_directory_error("create-supplement-set", ec);
    }
  }
  std::printf("REFSET capture reserved dir=%s\n", g_dir.c_str());
  std::fflush(stdout);
}

bool write_capture_witness(int phase, bool supplemental) {
  if (FILE* f = std::fopen(witness_path(phase, supplemental).c_str(), "w")) {
    // Deux lignes, et les deux comptent. L'empreinte dit « pas le meme binaire » ; la saveur
    // dit « et ce n'etait pas un binaire qui contient la couche qu'on juge ». Sans la seconde,
    // n'importe quel binaire legerement different ferait une reference — la porte serait une
    // mesure de stabilite deguisee, exactement ce que le temoin existe pour empecher.
    const bool written = std::fprintf(f, "%016llx\nflavour=%s\n",
                                     (unsigned long long)self_fingerprint(), build_flavour()) > 0;
    const bool closed = std::fclose(f) == 0;
    return written && closed;
  }
  return false;
}

// Metadata has a deliberately small, strict line format.
bool read_metadata_lines(const std::string& path, std::vector<std::string>& lines) {
  FILE* f = std::fopen(path.c_str(), "rb");
  if (!f) {
    return false;
  }
  std::string line;
  bool valid = true;
  int c;
  while ((c = std::fgetc(f)) != EOF) {
    if (c == '\n') {
      lines.push_back(line);
      line.clear();
      if (lines.size() > 9) {
        valid = false;
        break;
      }
    } else if (c < 32 || c > 126 || line.size() >= 256) {
      valid = false;
      break;
    } else {
      line.push_back(static_cast<char>(c));
    }
  }
  valid = valid && line.empty() && !std::ferror(f);
  const bool closed = std::fclose(f) == 0;
  return valid && closed;
}

void init_candidate_provenance() {
  const std::string marker = g_dir + "/" + kFormatMarker;
  if (g_mode == 1) {
    // The root was exclusively reserved above. Existing reference roots are never rewritten.
    g_provenance_version = 0;
    if (FILE* f = std::fopen(marker.c_str(), "w")) {
      const bool written = std::fprintf(f, "version=2\n") > 0;
      const bool closed = std::fclose(f) == 0;
      if (written && closed) {
        g_provenance_version = 2;
      }
    }
  } else {
    std::error_code ec;
    const auto status = fs::symlink_status(marker, ec);
    const bool absent = status.type() == fs::file_type::not_found &&
                        (!ec || ec == std::errc::no_such_file_or_directory);
    if (!absent) {
      std::vector<std::string> lines;
      g_provenance_version = !ec && read_metadata_lines(marker, lines) &&
                                     lines == std::vector<std::string>{"version=2"}
                                 ? 2
                                 : 0;
    } else {
      // Historical primary images have no sidecars. A candidate whose marker was lost
      // must not silently fall back to the historical reader that skips those sidecars.
      for (const Step& step : g_steps) {
        if (step.supplemental) {
          continue;
        }
        const auto sidecar = fs::symlink_status(image_path(step) + ".provenance.txt", ec);
        const bool sidecar_absent = sidecar.type() == fs::file_type::not_found &&
                                    (!ec || ec == std::errc::no_such_file_or_directory);
        if (!sidecar_absent) {
          g_provenance_version = 0;
          break;
        }
      }
    }
  }
  // Assets are identified on disk at startup. Input instead comes from the replay
  // reader: a later replacement of its path must not describe different loaded bytes.
  g_data_fp = data_fingerprint();
  g_input_fp = pad_replay::replay_input_fingerprint();
  std::printf("REFSET provenance-init version=%d data=%016llx input=%016llx "
              "input_source=loaded-replay actor_rng_state=not-restored-by-sidecars\n",
              g_provenance_version, (unsigned long long)g_data_fp,
              (unsigned long long)g_input_fp);
  if (g_provenance_version == 2) {
    autoport_proof::publish_text("refset_candidate_qualification", "missing-state-and-baseline");
  }
}

bool parse_unsigned(const std::string& text, int base, uint64_t& value) {
  const auto result = std::from_chars(text.data(), text.data() + text.size(), value, base);
  return !text.empty() && result.ec == std::errc() && result.ptr == text.data() + text.size();
}

bool read_strict_witness(int phase, bool supplemental, uint64_t& bin, std::string& flavour) {
  std::vector<std::string> lines;
  if (!read_metadata_lines(witness_path(phase, supplemental), lines) || lines.size() != 2 ||
      lines[0].size() != 16 || !parse_unsigned(lines[0], 16, bin) || !bin ||
      (lines[1] != "flavour=normal" && lines[1] != "flavour=ablate")) {
    return false;
  }
  flavour = lines[1].substr(8);
  return true;
}

// La saveur inscrite a cote de la reference. "" = absente (temoin d'avant ce champ, ou fichier
// manquant) — et une saveur absente n'est jamais traitee comme `ablate`.
std::string read_capture_flavour(int phase, bool supplemental) {
  std::string v;
  if (supplemental || g_provenance_version == 2) {
    uint64_t bin = 0;
    return read_strict_witness(phase, supplemental, bin, v) ? v : "";
  }
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

uint64_t read_capture_witness(int phase, bool supplemental) {
  uint64_t v = 0;
  if (supplemental || g_provenance_version == 2) {
    std::string flavour;
    return read_strict_witness(phase, supplemental, v, flavour) ? v : 0;
  }
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
  if (autoport_proof::feature_is("lighting-census")) {
    add("lighting-census-two-arms-master-on-bootstrap-v2");
  }
  if (g_temporal_samples > 1) {
    add("lighting-hdr-temporal-particles-v1");
    add(std::to_string(g_temporal_samples));
  }
  if (g_hdr_capture_scale > 1) {
    add(std::to_string(g_hdr_capture_scale));
    add(kHdrReduction);
  }
  if (g_require_loaded) {
    add("require-loaded-state-restore-plus2-v2");
    for (const auto& level : g_initial_levels) add(level);
    add(g_initial_display);
    add(g_initial_levels_spec);
    add(g_initial_display_spec);
  }
  // Preserve the historical identity when bootstrap replay is absent. A sealed
  // stream instead separates both sidecars and ledger rows by the consumed state.
  if (const uint64_t bootstrap = g_bootstrap_fingerprint.load()) {
    add("bootstrap-before-play-v1");
    add(std::to_string(bootstrap));
  }
  for (const Step& step : g_steps) {
    const Vantage& v = vantage_of(step);
    add(step.supplemental ? "supplement-v1" : "historical");
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
  // Configuration de camera seulement : ni padding de CamTune, ni pose relevee au spawn.
  auto add_cam_tune = [&add](const CamTune& tune) {
    add(std::to_string(tune.set));
    for (auto value : {tune.pitch_d, tune.yaw_d, tune.dist_dm, tune.height_dm}) {
      add(std::to_string(value));
    }
  };
  for (int value : {g_cam_armed, g_pitch_sweep, g_yaw_sweep, g_cam_hour_sweep}) {
    add(std::to_string(value));
  }
  add(std::to_string(g_vants.size()));
  for (int gi : g_vants) {
    add(std::to_string(gi));
    add_cam_tune(g_cam_tune[gi]);
  }
  for (int hi = 0; hi < 8; hi++) {
    add(std::to_string(g_pitch_by_hour[hi]));
    add(std::to_string(g_yaw_by_hour[hi]));
    add_cam_tune(g_cam_by_hour[hi]);
  }
  return h;
}

void report_provenance(const Step& step, const char* cause) {
  if (cause) {
    g_provenance_bad++;
  }
  std::string key = "refset_provenance_" + step_image_name(step);
  for (char& c : key) {
    if (c == '/' || c == '-') {
      c = '_';
    }
  }
  autoport_proof::publish_text(key.c_str(), cause ? cause : "ok");
  std::printf("REFSET provenance case=%s cause=%s\n", step_image_name(step).c_str(),
              cause ? cause : "ok");
  std::fflush(stdout);
}

bool write_capture_provenance(const Step& step, const std::string& path) {
  const uint64_t bin = self_fingerprint();
  const uint64_t png = hash_file(path);
  if (g_provenance_version != 2 || !bin || !png || !g_data_fp || !g_input_fp ||
      g_inflight_lf < 0) {
    return false;
  }
  FILE* f = std::fopen((path + ".provenance.txt").c_str(), "w");
  if (!f) {
    return false;
  }
  const bool written = std::fprintf(
      f, "version=2\ncase=%s\nconfig=%016llx\nbin=%016llx\nflavour=%s\npng=%016llx\n"
         "capture_lf=%lld\ndata=%016llx\ninput=%016llx\n",
      step_image_name(step).c_str(), (unsigned long long)census_config_fingerprint(),
      (unsigned long long)bin, build_flavour(), (unsigned long long)png,
      (long long)g_inflight_lf, (unsigned long long)g_data_fp,
      (unsigned long long)g_input_fp) > 0;
  const bool closed = std::fclose(f) == 0;
  return written && closed;
}

const char* check_capture_provenance(const Step& step, const std::string& path) {
  if (!g_provenance_version) {
    return "root-format";
  }
  std::vector<std::string> lines;
  if (!read_metadata_lines(path + ".provenance.txt", lines)) {
    return "sidecar-read";
  }
  std::map<std::string, std::string> fields;
  for (const auto& line : lines) {
    const auto equal = line.find('=');
    if (equal == std::string::npos ||
        !fields.emplace(line.substr(0, equal), line.substr(equal + 1)).second) {
      return "sidecar-fields";
    }
  }
  for (const char* key : {"version", "case", "config", "bin", "flavour", "png", "capture_lf"}) {
    if (!fields.count(key)) {
      return "sidecar-fields";
    }
  }
  const bool candidate = g_provenance_version == 2;
  if (fields.size() != (candidate ? 9 : 7) ||
      fields.at("version") != (candidate ? "2" : "1")) {
    return "sidecar-version";
  }
  if (candidate) {
    for (const auto& expected :
         {std::make_pair("data", g_data_fp), std::make_pair("input", g_input_fp)}) {
      uint64_t fp = 0;
      const auto field = fields.find(expected.first);
      if (field == fields.end() || field->second.size() != 16 ||
          !parse_unsigned(field->second, 16, fp) || !fp || fp != expected.second) {
        return expected.first;
      }
    }
  }
  if (fields.at("case") != step_image_name(step)) {
    return "case";
  }
  uint64_t config = 0, bin = 0, png = 0, lf = 0;
  if (fields.at("config").size() != 16 || !parse_unsigned(fields.at("config"), 16, config) ||
      config != census_config_fingerprint()) {
    return "config";
  }
  if (fields.at("bin").size() != 16 || !parse_unsigned(fields.at("bin"), 16, bin) || !bin ||
      bin != read_capture_witness(step.phase, step.supplemental)) {
    return "bin-witness";
  }
  const std::string& flavour = fields.at("flavour");
  if ((flavour != "normal" && flavour != "ablate") ||
      flavour != read_capture_flavour(step.phase, step.supplemental)) {
    return "flavour-witness";
  }
  if (fields.at("png").size() != 16 || !parse_unsigned(fields.at("png"), 16, png) || !png ||
      png != hash_file(path)) {
    return "png";
  }
  // This checks the recorded schedule; it does not restore simulation state.
  if (!parse_unsigned(fields.at("capture_lf"), 10, lf) || g_inflight_lf < 0 ||
      lf != static_cast<uint64_t>(g_inflight_lf)) {
    return "capture-lf";
  }
  return nullptr;
}

// Qualification is opt-in and produces separate immutable artifacts. The v2 image
// format stays unchanged; a short shard never becomes a historical full-plan run.
uint64_t qualification_settings_fingerprint() {
#if defined(__linux__) && !defined(__ANDROID__)
  std::error_code ec;
  const fs::path executable = fs::read_symlink("/proc/self/exe", ec);
  if (ec) return 0;
  uint64_t result = 1469598103934665603ull;
  for (const char* name : {"misc/debug-settings.json", "settings/display-settings.json",
                           "settings/input-settings.json", "settings/settings.ini"}) {
    const auto value = hash_file((executable.parent_path() / "OpenGOAL/jak1" / name).string());
    if (!value) return 0;
    for (int b = 0; b < 8; ++b) result = (result ^ ((value >> (8 * b)) & 255)) * 1099511628211ull;
  }
  return result;
#else
  return 0; // This qualification contract is x86; no inferred device qualification.
#endif
}

bool qualification_write(const std::string& path, const void* bytes, size_t size) {
  // Publish a closed file atomically, without replacing an earlier run or reference.
  const std::string temporary = path + ".pending";
  FILE* file = std::fopen(temporary.c_str(), "wx");
  if (!file) return false;
  const bool written = std::fwrite(bytes, 1, size, file) == size;
  const bool closed = std::fclose(file) == 0;
  std::error_code ec;
  if (written && closed) fs::create_hard_link(temporary, path, ec);
  const bool published = written && closed && !ec;
  fs::remove(temporary, ec);
  return published;
}

bool qualification_write_json(const std::string& path, const QualificationJson& json) {
  const auto bytes = json.dump(2) + "\n";
  return qualification_write(path, bytes.data(), bytes.size());
}

bool qualification_source_current() {
  if (!g_qualification_source_fp || hash_file(g_qualification_source) != g_qualification_source_fp)
    return false;
  try {
    const auto source = refset_qualification::detail::json(g_qualification_source);
    if (source.at("version") != 1 || source.at("bin") != self_fingerprint() ||
        !source.at("files").is_object() || source.at("files").empty()) return false;
    for (const auto& file : source.at("files").items()) {
      if (!fs::path(file.key()).is_absolute() || !file.value().is_number_unsigned() ||
          !file.value().get<uint64_t>() || hash_file(file.key()) != file.value().get<uint64_t>())
        return false;
    }
    return true;
  } catch (const std::exception&) {
    return false;
  }
}

void qualification_init() {
  if (!refset_state::enabled()) return;
  if (const char* path = std::getenv("OG_REFSET_BUILD_PROVENANCE")) {
    g_qualification_source = fs::absolute(path).string();
    g_qualification_source_fp = hash_file(g_qualification_source);
  }
  g_qualification_settings_fp = qualification_settings_fingerprint();
  if (g_mode == 2) g_qualification_capture_fp = hash_file(g_dir + "/qualification-capture.json");
  autoport_proof::publish_text("refset_candidate_qualification", "recording-reconstructed-state");
}

// Called during readback while g_mutex holds the selected phase stable. These are
// effective gates and clamped settings, never the phase's requested environment values.
QualificationJson qualification_effective_options() {
  const auto& gs = Gfx::g_global_settings;
  int rt = recharged_gating::on(recharged_gating::kRtLight) ? 1 : 0;
#ifdef __ANDROID__
  char value[PROP_VALUE_MAX] = {0};
  if (__system_property_get("debug.opengoal.rt.light", value) > 0 && value[0])
    rt = std::atoi(value);
#else
  if (const char* value = std::getenv("OG_RT_LIGHT")) rt = std::atoi(value);
#endif
  // lighting-legacy-purge (2026-09-11) : la PRE-SUBDIVISION est supprimee (elle n'etait
  // atteignable que sous le mode TESSELLATION jamais livre), donc l'option effective ne peut plus
  // etre qu'ETEINTE. Elle reste PUBLIEE, a zero : une cle qui disparait d'un rapport se lit comme
  // une mesure absente, pas comme une valeur nulle.
  const float grass_near = std::min(80.f, std::max(8.f, gs.recharged_grass_near_dist));
  const float grass_card = std::min(200.f, std::max(grass_near + 5.f, gs.recharged_grass_card_dist));
  bool grass_overhang = false;
#ifdef OG_FEAT_GRASS_OVERHANG
  grass_overhang = recharged_gating::on(recharged_gating::kGrassOverhang);
#endif
  return {{"master", Gfx::recharged_master_active()},
      {"lighting", Gfx::recharged_lighting_active()}, {"rt_light", Gfx::lighting_active(rt != 0)},
      {"hdr", hdr::chain_active() && hdr::format_is_float(hdr::scene_color_format())},
      {"others", {
          {"textures", recharged_gating::on(recharged_gating::kTextures)},
          {"managed_assets", recharged_gating::on(recharged_gating::kManagedAssets)},
          {"enhanced_models", recharged_gating::on(recharged_gating::kEnhancedModels)},
          {"grass", recharged_gating::on(recharged_gating::kGrass)},
          {"grass_near_dist", grass_near}, {"grass_card_dist", grass_card},
          {"grass_density_preset", grass_bake::clamp_density_preset(gs.recharged_grass_density_preset)},
          {"grass_precomputed", gs.recharged_grass_precomputed}, {"grass_overhang", grass_overhang},
          {"foliage_wind", foliage_wind::enabled()},
          {"subdivision", false}, {"subdivision_rounds", 0},
          {"load_custom_assets", gs.load_custom_assets},
          {"lod_tfrag", gs.lod_tfrag}, {"lod_tie", gs.lod_tie}, {"hack_no_tex", gs.hack_no_tex},
          {"crisp_title_logo", recharged_gating::on(recharged_gating::kCrispTitleLogo)}
      }}};
}

void qualification_sample(const Step& step, const QualificationJson& effective_options) {
  if (!refset_state::enabled()) return;
  const auto receipt = refset_state::receipt();
  const std::string path = image_path(step);
  const std::string state_path = path + ".state.bin";
  bool state_ok = g_case_state && receipt.bootstrap_fp && receipt.replay_verified &&
                  receipt.actors_sweep && g_require_loaded;
  if (state_ok && g_mode == 1) {
    state_ok = qualification_write(state_path, g_case_state->bytes.data(), g_case_state->bytes.size());
  } else if (state_ok) {
    FILE* file = std::fopen(state_path.c_str(), "rb");
    if (!file) {
      state_ok = false;
    } else {
      std::vector<uint8_t> bytes(g_case_state->bytes.size());
      state_ok = std::fread(bytes.data(), 1, bytes.size(), file) == bytes.size() &&
                 std::fgetc(file) == EOF && !std::ferror(file) && bytes == g_case_state->bytes;
      state_ok = std::fclose(file) == 0 && state_ok;
    }
  }
  if (!state_ok || g_case_probes != 1) ++g_qualification_bad;
  const auto& view = vantage_of(step);
  const auto sky = g_level_sky.find(view.level);
  const std::string key = (step.supplemental ? "supplement-v1/" : "") +
                          step_image_name(step) + ".png";
  g_qualification_cases.push_back({
      {"key", key}, {"vantage", view.id[0] ? view.id : "legacy"}, {"level", view.level},
      {"phase", step.phase}, {"hour", step.hour}, {"lf", g_inflight_lf},
      {"effective_options", effective_options},
      {"state_lf", g_case_state ? g_case_state->lf : -1},
      {"png", hash_file(path)}, {"sidecar", hash_file(path + ".provenance.txt")},
      {"state", state_ok ? hash_file(state_path) : 0},
      {"bg", g_case_bg}, {"px", g_case_px},
      {"level_ok", g_frame_levels.count(view.level) != 0},
      {"has_sky", sky == g_level_sky.end() ? -1 : sky->second},
      {"maxdiff", g_mode == 1 ? 0 : g_case_maxdiff}, {"diffpx", g_case_diffpx}});
  std::printf("REFSET qualification-state case=%s lf=%lld state_lf=%lld verified=%d\n",
              key.c_str(), (long long)g_inflight_lf,
              (long long)(g_case_state ? g_case_state->lf : -1), state_ok ? 1 : 0);
  autoport_proof::publish("refset_qualification_state_cases", g_qualification_cases.size());
  autoport_proof::publish("refset_qualification_state_bad", g_qualification_bad);
}

void qualification_finish() {
  if (!refset_state::enabled() || g_qualification_written) return;
  g_qualification_written = true;
  const auto receipt = refset_state::receipt();
  const bool clean = g_provenance_version == 2 && !g_provenance_bad && !g_qualification_bad &&
      !g_missing && !g_size_bad && !g_decode_bad && !g_slip_nonzero && !g_roundtrip_bad &&
      g_qualification_cases.size() == g_steps.size() && !g_steps.empty() &&
      (g_mode == 1 ? g_captured : g_compared) == g_steps.size();
  const bool fresh = g_qualification_settings_fp && qualification_source_current() &&
      qualification_settings_fingerprint() == g_qualification_settings_fp &&
      data_fingerprint() == g_data_fp;
  const bool reconstructed = receipt.bootstrap_fp && receipt.replay_verified &&
                             receipt.actors_sweep && g_require_loaded && !g_qualification_bad;
  const bool calibrated = !g_cam_armed || g_cam_overrides || g_pitch_sweep || g_yaw_sweep ||
                          g_cam_hour_sweep;
  const std::string execution = std::to_string(
      std::chrono::system_clock::now().time_since_epoch().count());
  std::string assets_path;
  uint64_t assets_fp = 0;
  if (const char* manifest = std::getenv("OG_REFSET_ASSET_MANIFEST")) {
    try {
      asset_manifest::checkpoint("qualification/" + execution);
      const auto bytes = refset_qualification::detail::read(manifest);
      assets_path = fs::absolute(g_dir + "/qualification-assets-" + execution + ".tsv").string();
      if (qualification_write(assets_path, bytes.data(), bytes.size())) assets_fp = hash_file(assets_path);
    } catch (const std::exception&) {
      assets_fp = 0;
    }
  }
  QualificationJson run = {{"version", 1}, {"kind", g_mode == 1 ? "capture" : "replay"},
      {"execution", execution}, {"bin", self_fingerprint()}, {"data", g_data_fp},
      {"input", g_input_fp}, {"config", census_config_fingerprint()},
      {"bootstrap", receipt.bootstrap_fp}, {"settings", g_qualification_settings_fp},
      {"source_path", g_qualification_source}, {"source_fp", g_qualification_source_fp},
      {"assets_path", assets_path}, {"assets_fp", assets_fp},
      {"clean", clean && fresh && assets_fp != 0}, {"reconstructed", reconstructed}, {"calibrated", calibrated},
      {"cases", g_qualification_cases}};
  std::string path = g_dir + "/qualification-capture.json";
  if (g_mode == 2) {
    run["capture_fp"] = g_qualification_capture_fp;
    const char* id = std::getenv("OG_REFSET_RUN_ID");
    if (!id || !*id || std::strlen(id) > 100 ||
        std::strspn(id, "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_") != std::strlen(id)) {
      autoport_proof::publish_text("refset_candidate_qualification", "invalid-execution-id");
      return;
    }
    std::error_code ec;
    fs::create_directories(g_dir + "/qualification-replays", ec);
    if (ec) return;
    path = g_dir + "/qualification-replays/" + id + ".json";
  }
  if (!qualification_write_json(path, run)) {
    autoport_proof::publish_text("refset_candidate_qualification", "receipt-write-failed");
    return;
  }
  autoport_proof::publish("refset_qualification_receipt_written", 1);
  autoport_proof::publish_text("refset_candidate_qualification",
      !clean ? "state-or-run-invalid" : !fresh ? "provenance-missing-or-stale" :
      !reconstructed ? "state-not-reconstructed" : "awaiting-independent-qualification");
  const char* manifest = std::getenv("OG_REFSET_QUALIFICATION");
  if (g_mode != 2 || !clean || !fresh || !assets_fp || !reconstructed || calibrated || !manifest || !*manifest) return;
  std::vector<refset_qualification::Expected> expected;
  // This universe is independent of the currently selected short shard.
  for (int vi = 0; vi < kNumVantages; ++vi) {
    const auto& view = kVantages[vi];
    const std::string name = view.id[0] ? view.id : "legacy";
    const bool expanded = name == "misty-bike" || name == "village2-dock" ||
        name == "sunkenb-helix" || name == "swamp-start" || name == "swamp-cave1" || name == "snow-fort";
    for (int phase : (autoport_proof::feature_is("lighting-census")
                          ? std::vector<int>{2, 3} : std::vector<int>{1, 2, 3})) {
      for (int hour : kHours) {
        char suffix[16];
        std::snprintf(suffix, sizeof(suffix), "h%02d.png", hour);
        const std::string key = std::string(expanded && hour != 9 && hour != 21 ? "supplement-v1/" : "") +
            set_name(phase) + "/" + (view.id[0] ? name + "-" : "") + suffix;
        expected.push_back({key, name, view.level, phase, hour});
      }
    }
  }
  const auto equal_images = [](const std::string& a, const std::string& b) {
    std::vector<uint8_t> aa, bb;
    uint32_t aw = 0, ah = 0, ac = 0, bw = 0, bh = 0, bc = 0;
    if (fpng::fpng_decode_file(a.c_str(), aa, aw, ah, ac, 4) ||
        fpng::fpng_decode_file(b.c_str(), bb, bw, bh, bc, 4) ||
        aw != kShotW || ah != kShotH || aw != bw || ah != bh) return false;
    uint64_t md = 0, px = 0;
    compare(aa.data(), bb.data(), aw * ah, &md, &px);
    return md == 0 && px == 0;
  };
  const auto result = refset_qualification::evaluate(manifest, self_fingerprint(), g_data_fp, hash_file,
                                                    equal_images, expected);
  autoport_proof::publish_text("refset_candidate_qualification", result.status.c_str());
  autoport_proof::publish("refset_qualification_missing", result.missing.size());
  for (const auto& missing : result.missing) std::printf("REFSET qualification missing=%s\n", missing.c_str());
  autoport_proof::publish("refset_qualification_gate", result.gate);
  if (autoport_proof::feature_is("lighting-census") && result.gate != 0)
    g_census_replay_gate = result.gate;
  if (result.gate != 0) return;
  // Adoption is a separate artifact. References and their version marker never change.
  const std::string adoption = g_dir + "/qualification-adoption-" + execution + ".json";
  if (qualification_write_json(adoption, {{"version", 1}, {"manifest", fs::absolute(manifest).string()},
      {"identity", result.identity}, {"bin", self_fingerprint()}, {"data", g_data_fp},
      {"replay_runs", result.replay_runs}})) {
    g_qualification_adopted = true;
    g_census_replay_gate = 0;
    g_census_replay_runs = result.replay_runs;
    autoport_proof::publish("refset_qualification_adopted", 1);
  }
}

void publish_flaky() {
  g_flaky_done = true;
  const uint64_t bin = self_fingerprint();
  const uint64_t refs = refs_fingerprint();
  const uint64_t data = g_data_fp;
  char t[32];
  std::snprintf(t, sizeof(t), "%016llx", (unsigned long long)bin);
  autoport_proof::publish_text("refset_bin_fp", t);
  std::snprintf(t, sizeof(t), "%016llx", (unsigned long long)refs);
  autoport_proof::publish_text("refset_refs_fp", t);
  std::snprintf(t, sizeof(t), "%016llx", (unsigned long long)data);
  autoport_proof::publish_text("refset_data_fp", t);
  if (!bin || !refs || !data || !g_input_fp || g_missing || g_size_bad || g_decode_bad ||
      g_provenance_bad || g_compared != g_steps.size()) {
    autoport_proof::publish("refset_replay_runs", 0);
    autoport_proof::publish("refset_replay_flaky", 255);
    return;
  }
  const std::string path = g_dir + "/replay-ledger.txt";
  publish_coverage();  // inclut la derniere photo, avant de qualifier la ligne du registre
  const uint64_t config = census_config_fingerprint();
  // Historical ledgers remain readable, but cannot adopt the current census contract.
  const bool census_ok = false;

  std::snprintf(t, sizeof(t), "%016llx", (unsigned long long)config);
  autoport_proof::publish_text("refset_census_config_fp", t);
  bool ledger_written = false;
  // On ECRIT d'abord, on RELIT ensuite : le verdict porte sur ce qui est sur le disque, pas sur
  // ce que cette course croit avoir ajoute.
  if (FILE* f = std::fopen(path.c_str(), "a")) {
    std::fprintf(
        f,
        "bin=%016llx refs=%016llx data=%016llx maxdiff=%llu diffpx=%llu config=%016llx "
        "census=%d input=%016llx\n",
        (unsigned long long)bin, (unsigned long long)refs, (unsigned long long)data,
        (unsigned long long)g_maxdiff, (unsigned long long)g_diffpx, (unsigned long long)config,
        census_ok ? 1 : 0, (unsigned long long)g_input_fp);
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
      unsigned long long b = 0, r = 0, dt = 0, m = 0, d = 0, cfg = 0, input = 0;
      int complete = 0;
      // Keep old rows as history; they cannot identify the input consumed by the run.
      // Both reproducibility and census credit require the same plan and loaded input.
      if (std::sscanf(line,
                      "bin=%llx refs=%llx data=%llx maxdiff=%llu diffpx=%llu config=%llx "
                      "census=%d input=%llx",
                      &b, &r, &dt, &m, &d, &cfg, &complete, &input) == 8 &&
          b == bin && r == refs && dt == data && cfg == config && input == g_input_fp) {
        md.emplace_back((uint64_t)m, (uint64_t)d);
        if (complete == 1) {
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
  if (!g_qualification_adopted) g_census_replay_runs = census_runs;
  // Candidate provenance records inputs, not restored actor/RNG state or an independent
  // baseline qualification. Even five exact self-replays cannot supply those missing facts.
  if (!g_qualification_adopted && g_census_replay_gate != 255) g_census_replay_gate = !ledger_written
                            ? 255
                            : (autoport_proof::feature_is("lighting-census") ||
                               g_provenance_version == 2 || census_runs < 5 ? 254 : census_maxdiff);
  autoport_proof::publish("refset_replay_runs", md.size());
  autoport_proof::publish("refset_replay_flaky", autoport_proof::feature_is("lighting-census")
      ? (g_qualification_adopted ? 0 : 254) : (md.size() >= 5 ? flaky : 254));
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
#if defined(__x86_64__) || defined(_M_X64) || defined(__i386__) || defined(_M_IX86)
  if (const char* scale = std::getenv("OG_HDR_CAPTURE_SCALE")) {
    if ((std::strcmp(scale, "1") != 0 && std::strcmp(scale, "2") != 0 &&
         std::strcmp(scale, "4") != 0) || g_mode != 1 ||
        !autoport_proof::feature_is("lighting-hdr")) {
      std::fprintf(stderr, "REFSET fatal: OG_HDR_CAPTURE_SCALE requires lighting-hdr capture "
                           "and exactly 1, 2 or 4\n");
      std::abort();
    }
    g_hdr_capture_scale = scale[0] - '0';
  }
#endif
  char temporal[128] = {};
  const char* temporal_env = std::getenv("OG_REFSET_TEMPORAL_SAMPLES");
  const bool temporal_knob = read_knob("OG_REFSET_TEMPORAL_SAMPLES",
                                      "debug.opengoal.refset.temporal", temporal,
                                      sizeof(temporal));
  if (temporal_env || temporal_knob) {
    int samples = 0;
    bool valid = temporal[0] != 0 &&
                 (!temporal_env || (temporal_env[0] && std::strlen(temporal_env) < sizeof(temporal)));
    for (const char* c = temporal; *c; ++c) {
      if (*c < '0' || *c > '9' || samples > 16) {
        valid = false;
        break;
      }
      samples = samples * 10 + (*c - '0');
    }
    if (!valid || samples < 2 || samples > 16 || g_mode != 1 ||
        !autoport_proof::feature_is("lighting-hdr")) {
      std::fprintf(stderr, "REFSET fatal: temporal samples require lighting-hdr capture and "
                           "an integer in 2..16\n");
      std::abort();
    }
    g_temporal_samples = samples;
  }
  char loaded[32] = {};
  g_require_loaded = read_knob("OG_REFSET_REQUIRE_LOADED", "debug.opengoal.refset.requireloaded",
                              loaded, sizeof(loaded)) && std::strcmp(loaded, "1") == 0;
  if (g_require_loaded) {
    char requested[256] = {};
    if (read_knob("OG_WANT_LEVELS", "debug.opengoal.want.levels", requested, sizeof(requested))) {
      g_initial_levels_spec = requested;
      std::string names = requested;
      size_t begin = 0;
      do {
        const size_t end = names.find(',', begin);
        const auto name = names.substr(begin, end - begin);
        if (!name.empty()) g_initial_levels.push_back(name);
        if (end == std::string::npos) break;
        begin = end + 1;
      } while (begin < names.size());
    }
    if (read_knob("OG_WANT_DISPLAY", "debug.opengoal.want.display", requested, sizeof(requested))) {
      g_initial_display_spec = requested;
      g_initial_display = g_initial_display_spec.substr(0, g_initial_display_spec.find(','));
    }
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
  if (g_mode == 1) {
    reserve_capture_directory();
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
  // lighting-census defaults to phases 2/3 with master ON throughout bootstrap and play.
  // An explicit phase 1 is an error; single-arm plans keep the same scheduling rules.
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
          if (ph == 1 && (autoport_proof::feature_is("lighting-census") ||
                          autoport_proof::feature_is("lighting-hdr"))) {
            std::fprintf(stderr, "REFSET fatal: lighting-census requires phases 2/3; phase 1 is forbidden\n");
            std::abort();
          }
          if (std::find(g_phases.begin(), g_phases.end(), ph) == g_phases.end()) {
            g_phases.push_back(ph);
          }
        }
      }
    }
    if (g_phases.empty()) {
      g_phases = (autoport_proof::feature_is("lighting-census") ||
                  autoport_proof::feature_is("lighting-hdr"))
                     ? std::vector<int>{2, 3}
                     : std::vector<int>{1, 2, 3};
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
          for (int i = 0; i < kNumSelectableVantages; i++) {
            const bool hit = (tok == "legacy" && kVantages[i].id[0] == 0) ||
                             tok == kVantages[i].id ||
                             (tok == kVantages[i].cont &&
                              std::strcmp(kVantages[i].id, "village1-eco-blue") != 0);
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
        for (int i = 0; i < kNumSelectableVantages; i++) {
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
  // Preserve the complete historical itinerary before visiting new hours. Inserting
  // hours inside it changes absolute simulation time and retained actor/effect state.
  // This preserves the schedule, not a claim of restored per-case state or bit identity.
  for (bool supplemental : {false, true}) {
    for (size_t vi = 0; vi < g_vants.size(); vi++) {
      const Vantage& van = kVantages[g_vants[vi]];
      const bool expanded = std::strcmp(van.id, "misty-bike") == 0 ||
                            std::strcmp(van.id, "village2-dock") == 0 ||
                            std::strcmp(van.id, "sunkenb-helix") == 0 ||
                            std::strcmp(van.id, "swamp-start") == 0 ||
                            std::strcmp(van.id, "swamp-cave1") == 0 ||
                            std::strcmp(van.id, "snow-fort") == 0;
      const uint8_t historical = expanded ? (1u << 3) | (1u << 7) : kAllHours;
      const uint8_t mask = van.hours & g_hours_mask &
                           (supplemental ? uint8_t(~historical) : historical);
      const auto append = [&](int phase, int hi) {
        if (mask & (1u << hi)) {
          for (int sample = 0; sample < g_temporal_samples; ++sample) {
            g_steps.push_back(Step{phase, kHours[hi], (int)vi, supplemental, sample});
          }
        }
      };
      if (g_order_by_hour) {
        for (int hi = 0; hi < 8; hi++) {
          for (int phase : g_phases) {
            append(phase, hi);
          }
        }
      } else {
        for (int phase : g_phases) {
          for (int hi = 0; hi < 8; hi++) {
            append(phase, hi);
          }
        }
      }
    }
  }
  for (size_t i = 0; i < g_steps.size(); ++i) {
    std::printf("REFSET case index=%zu layer=%s name=%s\n", i,
                g_steps[i].supplemental ? "supplement-v1" : "historical",
                step_image_name(g_steps[i]).c_str());
  }
  // Poser les deux variables a leur longueur definitive AVANT que le fil graphique ne les lise
  // pour la premiere fois : ainsi chaque bascule ulterieure reecrit un unique octet en place.
  put_env("OG_RECHARGED", (autoport_proof::feature_is("lighting-census") ||
                           autoport_proof::feature_is("lighting-hdr"))
                              ? "1"
                              : "0");
  put_env("OG_RT_LIGHT", "0");
  put_env("OG_LIGHTING", "0");
  init_candidate_provenance();
  qualification_init();
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

bool requires_loaded_state() {
  // The host dispatch hook also runs without this option. Do not initialize refset
  // earlier than its historical caller when the observer was not requested.
  static const bool requested = [] {
    char value[32] = {};
    return read_knob("OG_REFSET_REQUIRE_LOADED", "debug.opengoal.refset.requireloaded",
                     value, sizeof(value)) && std::strcmp(value, "1") == 0;
  }();
  return requested;
}

bool wants_postload_trace(int64_t lf) {
  std::lock_guard<std::mutex> lock(g_mutex);
  return g_require_loaded && g_capture_frame >= 0 &&
         lf >= g_capture_frame - 1 && lf <= g_capture_frame;
}

void note_loaded_state(int64_t frame, bool target, bool spawn, bool sweep,
                       const std::vector<LoadedLevelState>& levels) {
  if (!requires_loaded_state() || !enabled()) return;
  std::lock_guard<std::mutex> lock(g_mutex);
  // Replace a repeated dispatch frame rather than evicting useful older frames.
  if (!g_loaded_snapshots.empty() && g_loaded_snapshots.back().frame == frame) {
    g_loaded_snapshots.back() = {frame, target, spawn, sweep, levels};
  } else {
    if (g_loaded_snapshots.size() == kLoadedSnapshotWindow) {
      g_loaded_snapshots.erase(g_loaded_snapshots.begin());
    }
    g_loaded_snapshots.push_back({frame, target, spawn, sweep, levels});
  }
  const std::string problem = loaded_state_problem(frame);
  std::string states;
  for (const auto& level : levels) states += level.name + "=" + level.status + ";";
  autoport_proof::publish("refset_require_loaded", 1);
  autoport_proof::publish("refset_loaded_snapshot_lf", frame < 0 ? 0 : frame);
  autoport_proof::publish("refset_loaded_ready", problem.empty() ? 1 : 0);
  autoport_proof::publish_text("refset_loaded_levels", states.c_str());
  autoport_proof::publish_text("refset_loaded_pending", problem.c_str());
}

void set_bootstrap_fingerprint(uint64_t fingerprint) {
  g_bootstrap_fingerprint.store(fingerprint);
}

void set_logic_frame_provider(int64_t (*fn)()) {
  g_logic_fn = fn;
}

int64_t current_logic_frame() {
  return g_logic_fn ? g_logic_fn() : -1;
}

void set_render_logic_frame(int64_t frame) {
  g_render_logic_frame = frame;
}

int64_t render_logic_frame() {
#if defined(__ANDROID__)
  // The Android renderer has its own handoff; this correction is scoped to x86 replay.
  return current_logic_frame();
#else
  return g_render_logic_frame;
#endif
}

bool take_load_restore(int64_t frame, LoadRestoreRequest& request) {
  std::lock_guard<std::mutex> lock(g_mutex);
  if (!g_load_restore_pending || frame < g_load_restore.due_lf) return false;
  if (frame > g_load_restore.due_lf) {
    std::fprintf(stderr, "REFSET restore-load FAIL reason=missed-deadline case=%zu "
                         "anchor_lf=%lld due_lf=%lld observed_lf=%lld\n",
                 g_load_restore.case_index, (long long)g_load_restore.anchor_lf,
                 (long long)g_load_restore.due_lf, (long long)frame);
    std::fflush(nullptr);
    std::_Exit(EXIT_FAILURE);
  }
  request = g_load_restore;
  g_load_restore_pending = false;
  return true;
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
    require_loaded_state(lf, "warp-arm");
    g_step_anchor = lf;
    g_capture_frame = lf + g_step_settle;
    if (g_plan_base < 0) {
      g_plan_base = lf;
    }
    if (g_cur < g_steps.size() && step_is_arrival(g_cur)) {
      g_vant_base = lf;
    }
    g_cap = kCapArmed;
    if (g_require_loaded && g_cur < g_steps.size() && first_step_of_vant(g_cur) == 0 &&
        (!g_initial_levels_spec.empty() || !g_initial_display_spec.empty())) {
      // target-death suspends before resetting *load-state*. Reapply only after
      // that reset, on the fixed second frame following this final warp.
      g_load_restore = {g_initial_levels_spec, g_initial_display_spec, lf, lf + 2, g_cur};
      g_load_restore_pending = true;
    }
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
  if (g_temporal_samples > 1) {
    if (g_cap != kCapArmed || g_cur >= g_steps.size() || g_steps[g_cur].sample != 0 ||
        g_temporal_repin_case == (int64_t)g_cur) {
      return false;
    }
    const int64_t due = g_capture_frame - g_step_settle + 1;
    const int64_t lf = current_logic_frame();
    if (lf < due) return false;
    if (lf != due) {
      lg::error("REFSET fatal: temporal particle repin missed case={} due_lf={} lf={}",
                g_capture_name, due, lf);
      std::fprintf(stderr, "REFSET fatal: temporal particle repin missed case=%s due_lf=%lld lf=%lld\n",
                   g_capture_name.c_str(), (long long)due, (long long)lf);
      std::fflush(nullptr);
      std::_Exit(EXIT_FAILURE);
    }
    g_temporal_repin_case = (int64_t)g_cur;
    g_repin_lf = lf;
    ++g_repins;
    std::printf("REFSET repin-particules case=%s due_lf=%lld lf=%lld\n",
                g_capture_name.c_str(), (long long)due, (long long)lf);
    std::fflush(stdout);
    return true;
  }
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
  if (g_temporal_samples == 1 && lf >= g_plan_base + g_step_settle) {
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
      qualification_finish();
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
    require_loaded_state(lf, "arrival-deadline");
    if (g_temporal_samples > 1) {
      // The arrival already pinned the camera. A second warp would restart
      // target-continue and its blackout after this fixed loading deadline.
      g_step_anchor = g_vant_base = g_load_until;
      if (g_plan_base < 0) g_plan_base = g_load_until;
      g_capture_frame = g_step_anchor + g_step_settle;
      g_cap = kCapArmed;
      if (g_require_loaded && g_cur < g_steps.size() && first_step_of_vant(g_cur) == 0 &&
          (!g_initial_levels_spec.empty() || !g_initial_display_spec.empty())) {
        g_load_restore = {g_initial_levels_spec, g_initial_display_spec,
                          g_step_anchor, g_step_anchor + 2, g_cur};
        g_load_restore_pending = true;
      }
      std::printf("REFSET temporal-prepare case=%s anchor_lf=%lld observed_lf=%lld "
                  "capture_lf=%lld rewarp=0\n", g_capture_name.c_str(),
                  (long long)g_step_anchor, (long long)lf, (long long)g_capture_frame);
      std::fflush(stdout);
    } else {
      g_cap = kCapWaitWarp;
    }
  }

  if (g_cap == kCapIdle) {
    // La configuration est posee AVANT le teleport : l'heure et le master sont donc deja ceux de
    // l'etape quand la camera se repose.
    const Step& st = g_steps[g_cur];
    if (st.sample == 0) apply_step_config(st);
    g_capture_name = step_image_name(st);
    if (step_is_arrival(g_cur)) {
      g_load_steps++;
    }
    // UNE ARRIVEE SUR UN NOUVEAU VANTAGE TELEPORTE TOUJOURS, meme quand la politique de l'etape
    // est « pas de teleport » (l'appareil) : sans ce teleport-la, changer de vantage ne
    // changerait que l'heure et le master, et les 25 autres niveaux ne seraient jamais atteints.
    if (st.sample > 0) {
      // Keep the case anchor and requested cadence; no arrival or warp between samples.
      g_capture_frame += g_step_settle;
      require_loaded_state(lf, "temporal-arm");
      g_cap = kCapArmed;
    } else if (step_is_arrival(g_cur) &&
        (g_cur != 0 || g_require_loaded || autoport_proof::feature_is("lighting-hdr"))) {
      // Two teleports, the first to load. The historical first case skipped this wait;
      // the opt-in guard includes it without letting asynchronous readiness move the deadline.
      g_cap = kCapPreWarp;
    } else if (g_warp_per_step || g_cur == 0 || g_vant_base < 0) {
      g_cap = kCapWaitWarp;
    } else if (g_temporal_samples > 1) {
      // Each arm/hour starts an independent sequence after its preceding readback.
      // The logic thread may already be ahead: a new purge cannot inherit a
      // deadline from the previous sequence's last capture.
      const int64_t previous_capture_lf = g_capture_frame;
      g_step_anchor = lf;
      g_capture_frame = lf + g_step_settle;
      require_loaded_state(lf, "temporal-sequence-arm");
      g_cap = kCapArmed;
      std::printf("REFSET temporal-arm case=%s anchor_lf=%lld capture_lf=%lld "
                  "previous_capture_lf=%lld lag_lf=%lld\n", g_capture_name.c_str(),
                  (long long)g_step_anchor, (long long)g_capture_frame,
                  (long long)previous_capture_lf, (long long)(lf - previous_capture_lf));
      std::fflush(stdout);
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
      require_loaded_state(lf, "arm");
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

int64_t capture_logic_frame() {
  std::lock_guard<std::mutex> lock(g_mutex);
  return g_cap == kCapInFlight ? g_inflight_lf : -1;
}

void note_camera(const float* camera_matrix16, const float* hvdf_off4, const float* fog4) {
  if (!enabled() || !camera_matrix16 || !hvdf_off4 || !fog4) {
    return;
  }
  std::lock_guard<std::mutex> lock(g_mutex);
  if (g_cap != kCapInFlight) {
    return;
  }
  std::memcpy(g_cam_matrix, camera_matrix16, sizeof(g_cam_matrix));
  std::memcpy(g_cam_hvdf_off, hvdf_off4, sizeof(g_cam_hvdf_off));
  std::memcpy(g_cam_fog, fog4, sizeof(g_cam_fog));
  g_cam_noted_lf = g_inflight_lf;
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
  ++g_case_probes;
  g_case_bg = bg_px;
  g_case_px = total_px;
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
  // La resolution dynamique peut changer la surface entre deux sondes : normaliser
  // chacune AVANT les extrema, jamais avec la surface de la derniere image.
  const uint64_t bg_ppm = bg_px * 1000000ull / total_px;
  if (bg_ppm < vs.bg_ppm_min) {
    vs.bg_ppm_min = bg_ppm;
  }
  if (bg_ppm > vs.bg_ppm_max) {
    vs.bg_ppm_max = bg_ppm;
  }
  // LE MEME RELEVE, RANGE PAR CRENEAU : c'est lui que lit `refset_sky_missing`.
  const int hi = hour_index(g_steps[g_cur].hour);
  if (hi >= 0) {
    vs.shots_h[hi]++;
    vs.px_h[hi] = total_px;
    if (level_here) {
      vs.level_ok_h[hi]++;
    }
    if (bg_ppm < vs.bg_ppm_min_h[hi]) {
      vs.bg_ppm_min_h[hi] = bg_ppm;
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
  require_loaded_state(lf, "capture");
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
  g_case_bg = g_case_px = g_case_probes = 0;
  g_case_maxdiff = 255;
  g_case_diffpx = 0;
  if (refset_state::enabled()) g_case_state = refset_state::snapshot(lf);
  g_frame_levels.clear();
  // Desarmer ICI, pas a la fin de la capture : entre les deux, le fil graphique dessine une ou
  // deux images de plus et re-prendrait la meme demande.
  g_cap = kCapInFlight;
  std::snprintf(name_out, name_cap, "%s", g_capture_name.c_str());
  *w = kShotW * g_hdr_capture_scale;
  *h = kShotH * g_hdr_capture_scale;
  return true;
}

// lighting-hdr essai 62 : projette `kSageHutGround` a l'ecran avec la camera notee pour l'image
// en vol et emet UNE ligne `HDR-OWNER-GROUND {json}`. Formule (b) de
// notes/essai61/ground-projection.md (grass.vert:81-93, convention decor : le trio se consomme
// NEGATIF) ; ROI en pixels top-left 320x180 comme Sprite3.cpp:1602-1618, quelle que soit la
// taille de capture (`g_hdr_capture_scale`) : c'est l'espace de mesure du harnais. L'occlusion
// n'est pas evaluee : le rectangle contient ses occulteurs. Appelant sous g_mutex.
void emit_owner_ground_line() {
  nlohmann::json j;
  j["lf"] = g_inflight_lf;
  j["actor"] = 0;
  j["layer"] = "sage-hut-ground";
  j["case"] = "sage-hut-ground";
  j["roi"] = nullptr;
  j["supported"] = true;
  j["passed"] = true;
  j["in_frame"] = false;
  j["world_aabb"] = {kSageHutGround[0], kSageHutGround[1], kSageHutGround[2],
                     kSageHutGround[3], kSageHutGround[4], kSageHutGround[5]};
  j["roi_space"] = "top_left_320x180";
  j["capture"] = g_capture_name;
  if (g_cam_noted_lf != g_inflight_lf) {
    j["supported"] = false;
    j["reason"] = "camera not captured";
    lg::info("HDR-OWNER-GROUND {}", j.dump());
    return;
  }
  const float* M = g_cam_matrix;  // colonnes : M[c*4 + r]
  float corner_w[8];
  float lo_x = 1e30f, lo_y = 1e30f, hi_x = -1e30f, hi_y = -1e30f;
  int projectable = 0;
  for (int c = 0; c < 8; ++c) {
    const float px = ((c & 1) ? kSageHutGround[3] : kSageHutGround[0]) * 4096.f;
    const float py = ((c & 2) ? kSageHutGround[4] : kSageHutGround[1]) * 4096.f;
    const float pz = ((c & 4) ? kSageHutGround[5] : kSageHutGround[2]) * 4096.f;
    float t[4];
    for (int r = 0; r < 4; ++r) {
      t[r] = -(M[12 + r] + M[0 + r] * px + M[4 + r] * py + M[8 + r] * pz);
    }
    corner_w[c] = t[3];
    if (!(t[3] > 0.f) || !std::isfinite(t[3])) {
      continue;
    }
    const float Q = g_cam_fog[0] / t[3];
    const float sx = t[0] * Q + g_cam_hvdf_off[0];
    const float sy = t[1] * Q + g_cam_hvdf_off[1];
    const float x = ((sx - 2048.f) / 256.f + 1.f) * 160.f;
    const float y = (1.f + (sy - 2048.f) / 128.f * (512.f / 448.f)) * 90.f;
    if (!std::isfinite(x) || !std::isfinite(y)) {
      continue;
    }
    ++projectable;
    lo_x = std::min(lo_x, x);
    lo_y = std::min(lo_y, y);
    hi_x = std::max(hi_x, x);
    hi_y = std::max(hi_y, y);
  }
  j["corner_w"] = {corner_w[0], corner_w[1], corner_w[2], corner_w[3],
                   corner_w[4], corner_w[5], corner_w[6], corner_w[7]};
  if (projectable > 0) {
    const int x0 = int(std::floor(std::clamp(lo_x, 0.f, 320.f)));
    const int y0 = int(std::floor(std::clamp(lo_y, 0.f, 180.f)));
    const int x1 = int(std::ceil(std::clamp(hi_x, 0.f, 320.f)));
    const int y1 = int(std::ceil(std::clamp(hi_y, 0.f, 180.f)));
    j["roi"] = {x0, y0, x1, y1};
    j["in_frame"] = (x1 > x0) && (y1 > y0);
  }
  lg::info("HDR-OWNER-GROUND {}", j.dump());
}

bool consume_capture(int w, int h, const void* rgba) {
  if (!enabled()) {
    return false;
  }
  std::lock_guard<std::mutex> lock(g_mutex);
  if (g_cap != kCapInFlight) {
    return false;
  }
  int64_t particle_age = -1;
  if (g_temporal_samples > 1) {
    const int sample = g_steps[g_cur].sample;
    const int64_t expected_age = (int64_t)(sample + 1) * g_step_settle - 1;
    const int64_t expected_repin = g_capture_frame - expected_age;
    particle_age = g_inflight_lf - g_repin_lf;
    if (g_temporal_repin_case != (int64_t)g_cur - sample ||
        g_repin_lf != expected_repin || particle_age != expected_age) {
      lg::error("REFSET fatal: temporal particle age case={} chain_lf={} "
                "particle_repin_lf={} particle_age={} expected_repin_lf={} expected_age={}",
                g_capture_name, g_inflight_lf, g_repin_lf, particle_age,
                expected_repin, expected_age);
      std::fprintf(stderr, "REFSET fatal: temporal particle age case=%s chain_lf=%lld "
                           "particle_repin_lf=%lld particle_age=%lld expected_repin_lf=%lld "
                           "expected_age=%lld\n", g_capture_name.c_str(),
                   (long long)g_inflight_lf, (long long)g_repin_lf, (long long)particle_age,
                   (long long)expected_repin, (long long)expected_age);
      std::fflush(nullptr);
      std::_Exit(EXIT_FAILURE);
    }
  }
  std::vector<uint8_t> reduced;
  if (g_hdr_capture_scale > 1) {
    const std::string native_path = image_path(g_steps[g_cur]) + ".native.rgba";
    auto fatal = [&](const char* reason) {
      std::fprintf(stderr, "REFSET fatal: native capture case=%s chain_lf=%lld path=%s: %s\n",
                   g_capture_name.c_str(), (long long)g_inflight_lf, native_path.c_str(), reason);
      std::fflush(nullptr);
      std::_Exit(EXIT_FAILURE);
    };
    if (!rgba || w != kShotW * g_hdr_capture_scale || h != kShotH * g_hdr_capture_scale) {
      fatal("unexpected RGBA8 dimensions or null buffer");
    }
    const size_t native_size = size_t(w) * h * 4;
    try {
      file_util::write_binary_file(native_path, rgba, native_size);
      const uint64_t native_fnv = hash_file(native_path);
      const auto back = file_util::read_binary_file(native_path);
      if (!native_fnv || back.size() != native_size ||
          std::memcmp(back.data(), rgba, native_size) != 0 ||
          hash_file(native_path) != native_fnv) {
        fatal("RAW size, identity or FNV roundtrip failed");
      }
      const QualificationJson metadata = {
          {"width", w}, {"height", h}, {"channels", 4}, {"format", "RGBA8"},
          {"orientation", "top-left"}, {"case", g_capture_name}, {"chain_lf", g_inflight_lf},
          {"scale", g_hdr_capture_scale}, {"method", kHdrReduction}, {"fnv", native_fnv}};
      const std::string metadata_path = native_path + ".json";
      const std::string metadata_bytes = metadata.dump(2) + "\n";
      file_util::write_binary_file(metadata_path, metadata_bytes.data(), metadata_bytes.size());
      const auto metadata_back = file_util::read_binary_file(metadata_path);
      if (metadata_back.size() != metadata_bytes.size() ||
          std::memcmp(metadata_back.data(), metadata_bytes.data(), metadata_bytes.size()) != 0) {
        fatal("JSON roundtrip failed");
      }
      const auto* native = static_cast<const uint8_t*>(rgba);
      const unsigned area = g_hdr_capture_scale * g_hdr_capture_scale;
      reduced.resize(size_t(kShotW) * kShotH * 4);
      for (int y = 0; y < kShotH; ++y) {
        for (int x = 0; x < kShotW; ++x) {
          for (int channel = 0; channel < 4; ++channel) {
            unsigned sum = 0;
            for (int dy = 0; dy < g_hdr_capture_scale; ++dy) {
              for (int dx = 0; dx < g_hdr_capture_scale; ++dx) {
                sum += native[((y * g_hdr_capture_scale + dy) * w +
                               x * g_hdr_capture_scale + dx) * 4 + channel];
              }
            }
            reduced[(y * kShotW + x) * 4 + channel] = (sum + area / 2) / area;
          }
        }
      }
      std::printf("REFSET native case=%s chain_lf=%lld width=%d height=%d path=%s fnv=%llu "
                  "method=%s\n", g_capture_name.c_str(), (long long)g_inflight_lf,
                  w, h, native_path.c_str(), (unsigned long long)native_fnv, kHdrReduction);
      std::fflush(stdout);
    } catch (const std::exception& error) {
      fatal(error.what());
    }
    w = kShotW;
    h = kShotH;
    rgba = reduced.data();
  }
  auto effective_options = (refset_state::enabled() || autoport_proof::feature_is("lighting-hdr"))
      ? qualification_effective_options() : QualificationJson::object();
  if (autoport_proof::feature_is("lighting-hdr")) {
    const auto& settings = Gfx::g_global_settings;
    effective_options["output"] = {
        {"profile", "sdr"}, {"curve", settings.recharged_hdr_curve},
        {"exposure", settings.recharged_hdr_exposure},
        {"pbr_exposure", settings.recharged_pbr_exposure},
        {"knee", settings.recharged_hdr_knee}};
    if (g_hdr_capture_scale > 1) {
      effective_options["native_capture"] = {
          {"width", kShotW * g_hdr_capture_scale}, {"height", kShotH * g_hdr_capture_scale},
          {"scale", g_hdr_capture_scale}, {"method", kHdrReduction}};
    }
    if (g_temporal_samples > 1) {
      effective_options["temporal"] = {
          {"samples", g_temporal_samples}, {"sample", g_steps[g_cur].sample},
          {"spacing_lf", g_step_settle}, {"particle_step", "once-per-logic-frame"},
          {"particle_repin_lf", g_repin_lf}, {"particle_age", particle_age}};
    }
    std::printf("REFSET effective case=%s options=%s\n", g_capture_name.c_str(),
                effective_options.dump().c_str());
    std::fflush(stdout);
  }
  const std::string path = image_path(g_steps[g_cur]);
  if (asset_manifest::enabled()) {
    asset_manifest::checkpoint(step_image_name(g_steps[g_cur]) + "/chain-lf=" +
                               std::to_string(g_inflight_lf));
  }
  std::printf("REFSET sample case=%s layer=%s chain_lf=%lld anchor_lf=%lld sample=%d samples=%d",
              g_capture_name.c_str(), g_steps[g_cur].supplemental ? "supplement-v1" : "historical",
              (long long)g_inflight_lf, (long long)g_step_anchor,
              g_steps[g_cur].sample, g_temporal_samples);
  if (g_temporal_samples > 1) {
    std::printf(" particle_repin_lf=%lld particle_age=%lld",
                (long long)g_repin_lf, (long long)particle_age);
  }
  std::printf("\n");
  emit_owner_ground_line();
  const int n_px = w * h;
  const uint8_t* cur = (const uint8_t*)rgba;
  // lighting-hdr : on mesure AVANT de comparer ou d'ecrire, dans les deux modes. Les
  // verdicts 1 et 2 portent sur ce que le moteur vient de dessiner, pas sur la reference.
  if (g_steps[g_cur].sample == 0 &&
      (autoport_proof::feature_is("lighting-hdr") || vantage_of(g_steps[g_cur]).id[0] == 0)) {
    measure_step(g_steps[g_cur], g_inflight_lf, cur, w, h);
  }

  if (g_mode == 1) {
    file_util::write_rgba_png(path, const_cast<void*>(rgba), w, h);
    // Un chemin n'est pas une preuve : on relit tout de suite ce qu'on vient d'ecrire et on
    // verifie que l'aller-retour PNG est exact. Sinon la reference ne vaut rien et personne ne
    // le saurait avant l'item suivant.
    std::vector<uint8_t> back;
    uint32_t bw = 0, bh = 0, bc = 0;
    bool roundtrip_ok = false;
    if (fpng::fpng_decode_file(path.c_str(), back, bw, bh, bc, 4) == 0 && (int)bw == w &&
        (int)bh == h) {
      uint64_t md = 0, np = 0;
      compare(cur, back.data(), n_px, &md, &np);
      roundtrip_ok = md == 0;
    }
    if (!roundtrip_ok) {
      g_roundtrip_bad++;
    } else {
      const Step& step = g_steps[g_cur];
      const bool witness_ok = write_capture_witness(step.phase, step.supplemental);
      const bool provenance_ok = write_capture_provenance(step, path);
      if (!witness_ok || !provenance_ok) {
        report_provenance(step, !witness_ok ? "witness-write" : "sidecar-write");
      } else {
        g_captured++;
        if (g_temporal_samples > 1) ++g_temporal_captured;
        std::printf("REFSET cap %s step=%d/%d\n", g_capture_name.c_str(), (int)g_cur,
                    (int)g_steps.size());
        std::fflush(stdout);
      }
    }
  } else {
    const Step& step = g_steps[g_cur];
    const char* provenance_error = nullptr;
    if (step.supplemental || g_provenance_version != 1) {
      g_provenance_checked++;
      provenance_error = check_capture_provenance(step, path);
      report_provenance(step, provenance_error);
    }
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
    } else if (!provenance_error) {
      uint64_t md = 0, np = 0;
      compare(cur, ref.data(), n_px, &md, &np);
      g_compared++;
      g_case_maxdiff = md;
      g_case_diffpx = np;
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

  qualification_sample(g_steps[g_cur], effective_options);
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
  const bool clean = !g_missing && !g_size_bad && !g_decode_bad && !g_provenance_bad;
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
  if (autoport_proof::feature_is("lighting-hdr")) {
    return hdr_paired_count() == kNumVantages * 8ull ? 0 : 1;
  }
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
  if (autoport_proof::feature_is("lighting-hdr")) {
    if (hdr_paired_count() != kNumVantages * 8ull)
      return 1;
    for (int vi = 0; vi < int(g_vants.size()); ++vi) {
      for (int hour : kHours) {
        const StepStats *on, *off;
        if (!hdr_pair(vi, hour, on, off))
          return 1;
        if (on->sat_px > off->sat_px + hdr_motion_tolerance(*off, off->sat_px) ||
            on->sat_white_px > off->sat_white_px + hdr_motion_tolerance(*off, off->sat_white_px) ||
            on->near_white_px > off->near_white_px + hdr_motion_tolerance(*off, off->near_white_px))
          return 1;
      }
    }
    return 0;
  }
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

// Verdict 2 — lighting-hdr : couverture complete uniquement (SPEC §4.5, arbitrage
// contraste du 8 septembre). Les gradients, ratios et deltas restent des diagnostics :
// les deciles ON/OFF ne designent pas necessairement les memes surfaces.
// Les autres features conservent leur critere de contraste local ON >= 95 % OFF.
int verdict_highlight_contrast() {
  if (autoport_proof::feature_is("lighting-hdr")) {
    if (hdr_paired_count() != kNumVantages * 8ull)
      return 1;
    for (int vi = 0; vi < int(g_vants.size()); ++vi) {
      for (int hour : kHours) {
        const StepStats *on, *off;
        if (!hdr_pair(vi, hour, on, off))
          return 1;
      }
    }
    return 0;
  }
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
