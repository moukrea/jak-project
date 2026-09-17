#include "game/graphics/opengl_renderer/soft_draw_census.h"
#include "PrePass.h"
#include "ao_contact_readback.h"
#include "ao_contact_archive.h"
#include <sstream>

#include <algorithm>
#include <array>
#include <cmath>
#include <cstring>
#include <unordered_set>
#include <vector>

#include "common/log/log.h"

#include "game/graphics/gfx.h"
#include "game/graphics/gl_query_census.h"
#include "game/graphics/opengl_renderer/AmbientOcclusion.h"
#include "game/graphics/opengl_renderer/ao_static_probe.h"
#include "game/graphics/opengl_renderer/ao_tie_alpha_probe.h"
#include "game/graphics/opengl_renderer/ao_tie_contract.h"
#include "game/graphics/opengl_renderer/background/background_common.h"
#include "game/graphics/opengl_renderer/background/foliage_wind.h"
#include "game/graphics/opengl_renderer/GrassOccluders.h"
#include "game/graphics/opengl_renderer/buckets.h"
#include "game/graphics/opengl_renderer/lighting_census.h"
#include "game/system/autoport_proof.h"
#include "game/system/ao_item.h"
#include "game/graphics/opengl_renderer/gl_uniform_cache.h"

// Definie dans background_common.cpp (liaison externe, pas de declaration dans son .h) : LA
// matrice que tfrag3.vert consomme sous le nom `pc_camera`. La prepasse doit projeter avec la
// meme, sinon sa profondeur ne serait pas celle de la passe principale.
std::array<math::Vector4f, 4> make_new_cam_mat(const math::Vector4f cam_T_w[4],
                                               const math::Vector4f persp[4],
                                               float fog_constant,
                                               float hvdf_z);

namespace prepass {
namespace {

// L'IDENTIFIANT VIENT DE `game/system/ao_item.h`, ECRIT UNE SEULE FOIS (ao-indirect-clean,
// 2026-09-17). Le litteral etait ici et a cinq autres endroits ; le ticket a change de nom et
// les six conditions seraient devenues fausses en meme temps, en silence.
constexpr const char* kItemId = ao_item::kId;
AUTOPORT_FEATURE_SITE(kItemId);
AUTOPORT_FEATURE_SITE(ao_static_probe::kItem);
ao_static_probe::Run g_static_probe;
uint32_t g_static_acquisition_mask = 0;
bool g_static_acquisition_alpha_ok = false;
bool g_static_acquisition_witness_ok = false;
// Une image sondee sur N sous mesure : la relecture couleur + stencil pleine resolution coute
// une synchronisation GPU, on ne la paie pas a chaque image.
constexpr uint64_t kProbeEvery = 30;  // 18 etats de recensement a couvrir (etait 60 pour 3)

std::vector<DepthContributor*> g_contributors;
AmbientOcclusionPass g_ao;
ShaderLibrary* g_shaders = nullptr;

// Le FBO de la prepasse : profondeur seule (DEPTH24_STENCIL8, comme l'attachement du FBO de
// rendu que les estimateurs lisaient avant), aucune couleur.
GLuint g_fbo = 0;
GLuint g_depth_tex = 0;
int g_w = 0, g_h = 0;

// 1x1 blanc : lie sur l'unite 8 quand l'AO est eteinte, pour que l'unite soit toujours
// complete (un sampler declare et non lie rend un comportement indefini sur Adreno).
GLuint g_white_tex = 0;

// Etat d'image.
uint64_t g_frame = 0;
bool g_frame_ran = false;  // on_first_camera a deja tourne cette image
bool g_ao_valid = false;   // g_ao.texture() decrit cette image
uint64_t g_last_indices = 0;
int g_last_levels = 0;

// ── L'ALPHA-TEST DU FEUILLAGE, ET LE DETECTEUR QUI LE JUGE ────────────────────────────────────
// Refus owner du 2026-09-10 (b). L'etat memoise des plages (le programme garde ses uniformes
// entre deux draws, mais pas entre deux passes : tout ceci est remis a une valeur IMPOSSIBLE au
// debut de chaque passe, sinon un uniforme non repose se croit pose).
bool g_cut_armed = true;  // faux = bras de CONTROLE : la decoupe est desarmee, rien d'autre ne bouge
float g_last_aref = -1.f;
float g_last_amb = -1.f;
GLuint g_last_tex = 0xffffffffu;
bool g_cut_uniforms_ok = false;  // les quatre uniformes de la decoupe existent dans le programme
uint64_t g_cut_ranges = 0;    // plages qui portent un test d'alpha
uint64_t g_total_ranges = 0;  // toutes les plages — son denominateur
// (terme 3) L'ETAT D'ECHANTILLONNAGE HERITE, CHIFFRE PUIS CORRIGE. Voir background_common.h : un
// `glTexParameteri` ecrit sur l'OBJET texture, et la prepasse n'en posait aucun. Ces compteurs
// lisent l'etat REEL de l'objet JUSTE AVANT que la prepasse ne pose le sien, sur les seules images
// sondees. Ce qu'ils mesurent exactement : « depuis la derniere fois que la prepasse a pose cet
// etat, quelqu'un d'autre l'a change ». Non nul = le conflit existe et il est NOMME par parametre ;
// nul = personne ne le change, et l'hypothese tombe au lieu de survivre en prose.
// `_unknown` est le garde-fou : les plages a test d'alpha dont le contributeur n'a pas renseigne
// son `tex_mode`. Un `_bad` nul avec un `_unknown` non nul ne dit RIEN.
uint64_t g_texstate_checked = 0;
uint64_t g_texstate_bad = 0;
uint64_t g_texstate_bad_p[4] = {0, 0, 0, 0};
uint64_t g_texstate_unknown = 0;
// Memo de ce que la prepasse a pose : (objet texture, mode). Remis a l'impossible par
// `forget_range_state` au debut de chaque passe, comme les autres memos de ce bloc.
GLuint g_last_state_tex = 0xffffffffu;
uint16_t g_last_state_mode = 0xffff;

// La classification : un FBO couleur RGBA8 qui PARTAGE la profondeur de la prepasse.
// ELLE TOURNE AUSSI SUR L'APPAREIL depuis le 2026-09-14. Le contrat (verdict (j)) exige la
// mesure d'alpha SUR L'APPAREIL, brise allumee, et rien dans ce chemin n'est propre au bureau :
// un attachement couleur RGBA8, un `GL_EQUAL` contre la profondeur deja ecrite, et un
// `glReadPixels(GL_RGBA, GL_UNSIGNED_BYTE)` — les trois existent en GLES 3.2. C'est la relecture
// du STENCIL, ailleurs, qui ne s'y porte pas.
GLuint g_class_fbo = 0, g_class_tex = 0;
int g_class_w = 0, g_class_h = 0;
GLuint g_class_depth_src = 0;
int g_class_state = 0;  // 0 = pas encore, 1 = ok, -1 = refuse (publie)

uint64_t g_alpha_frames = 0;
uint64_t g_on_alpha_px = 0;       // bras LIVRE : le gagnant est sous le seuil -> doit valoir 0
uint64_t g_alpha_cover_px = 0;    // bras LIVRE : pixels gagnes par la prepasse — le denominateur
uint64_t g_alpha_fringe_px = 0;   // bras LIVRE : gagnants dans la bande ambigue (voir le .frag)
uint64_t g_witness_px = 0;        // bras CONTROLE : le meme detecteur, decoupe desarmee -> > 0
uint64_t g_witness_cover_px = 0;  // bras CONTROLE : son propre denominateur

// ── (i) LE DEPLACEMENT DE SOMMET, ET SON TEMOIN ───────────────────────────────────────────────
// `g_sway_off` desarme le deplacement SANS toucher a rien d'autre : meme geometrie, meme
// programme, memes plages, meme ordre. C'est la prepasse d'AVANT ce correctif, rejouee dans la
// MEME image — la seule facon de CHIFFRER, et non de supposer, ce que l'ancien etat coutait.
bool g_sway_off = false;

// ── (c)/(g)/(i) LA PROFONDEUR DE PREPASSE CONTRE CELLE DE LA SCENE ────────────────────────────
// LA grandeur que six essais n'avaient pas : au POINT DE DESSIN, le pixel que l'owner regarde
// porte-t-il une AO calculee sur la geometrie qui y est REELLEMENT dessinee ? On compare, sur les
// seuls pixels marques au stencil (buckets monde), la profondeur de la prepasse a celle de la
// scene. Les deux bras sont pris dans la MEME image : `livre` (deplacement arme) et `legacy`
// (deplacement desarme = l'etat de l'essai 6).
// LES COMPTEURS EXISTENT SUR LES DEUX PLATEFORMES, LEUR PRODUCTEUR NON. `read_prepass_depth`
// passe par `glReadPixels(GL_DEPTH_COMPONENT, GL_FLOAT)`, que GLES n'accepte pas : sur arm64
// `g_geom_state` vaut -1 des le depart et se publie 2 (« non supporte »), pas 0 (« pas encore »)
// ni un zero de population qui se lirait comme un succes.
std::vector<float> g_pre_depth;         // prepasse LIVREE
std::vector<float> g_pre_depth_legacy;  // prepasse SANS deplacement
// Verdict (c) de l'owner : « le fragment juge par l'estimateur n'est peut-etre pas celui qui est
// DESSINE — autre passe, autre niveau de detail, autre chemin (shrub contre tfrag contre TIE) ».
// Le stencil ne portait qu'un booleen « monde / pas monde » : il ne pouvait pas repondre. Il porte
// desormais LA FAMILLE, et les populations de `ao_geom_*` se lisent par famille.
//   0 = pas un bucket monde   1 = TFRAG   2 = TIE   3 = SHRUB
//   4 = TIE base d'envmap   5 = TIE second draw d'envmap (la couche additive)   6 = TIE vent
// (terme 3) Les QUATRE sous-chemins TIE partageaient la valeur 2 : un `absent` de 1481 px ne
// pouvait pas dire LEQUEL manque. Ils ont chacun leur valeur, posee par `proof_stencil_family`.
// Le second draw a la SIENNE parce que c'est lui que le correctif (C) fait dessiner a la
// prepasse : sans famille propre, l'effet du correctif ne serait pas attribuable.
constexpr int kFamTfrag = 1, kFamTie = 2, kFamShrub = 3, kFamTieEnv = 4, kFamTieEnv2 = 5,
              kFamTieWind = 6;
[[maybe_unused]] constexpr int kFamCount = 7;
[[maybe_unused]] const char* kFamNames[kFamCount] = {"-",       "tfrag",    "tie",     "shrub",
                                                     "tie_env", "tie_env2", "tie_wind"};
// LE TERME 3 DE LA PORTE AGREGE CETTE LISTE, ET ELLE EST DECLAREE UNE SEULE FOIS. Une
// sous-famille ajoutee sans etre inscrite ici ferait BAISSER la porte sans qu'aucun defaut ait
// disparu : c'est un faux vert par decoupage.
constexpr int kSwayFams[] = {kFamShrub, kFamTie, kFamTieEnv, kFamTieEnv2, kFamTieWind};

// (terme 3) LA TROISIEME PROFONDEUR : le bras dont la DECOUPE D'ALPHA est desarmee. Il est deja
// dessine a chaque image sondee (`run_prepass(armed=false)`) et sa profondeur etait jetee ; on la
// FIGE. Elle separe deux causes du MEME compte d'« absent » : la prepasse ne dessine PAS cette
// geometrie (elle reste absente ici aussi), ou son alpha-test l'a JETEE (elle apparait ici).
// Aucune passe de plus, une relecture de plus sur les seules images de recensement.
std::vector<float> g_pre_depth_nocut;
uint64_t g_geom_nocut_frames = 0;
// Le TEMOIN de cet instrument : les pixels, sur TOUT l'ecran, ou le bras sans decoupe porte une
// profondeur que le bras livre n'a pas. Il doit etre GRAND (la decoupe retire le feuillage) :
// a zero, un `_absent_nocut_px` nul ne dirait pas que la decoupe est innocente, il dirait que
// l'instantane est mort.
uint64_t g_geom_nocut_extra_px = 0;
uint64_t g_fam_absent_nocut[kFamCount] = {};
// (terme 3) `_absent_nocut_px` ne dit PAS que c'est la decoupe qui a fait le trou : il dit
// seulement que le bras sans decoupe porte UNE profondeur a ce pixel. Deux causes tres
// differentes le rendent non nul, et elles n'appellent pas le meme correctif :
//   MATCH — cette profondeur est celle de la SCENE (a 64 quanta pres) : la prepasse dessine
//           bien la geometrie que l'image dessine, et c'est SON alpha-test qui l'a jetee
//           alors que la passe couleur l'a gardee. Le correctif porte sur le seuil, la
//           texture ou l'UV de la decoupe.
//   OFF   — cette profondeur est celle d'AUTRE CHOSE (un quad de feuillage que la decoupe
//           retire a juste titre, et derriere lequel la vraie geometrie manque). La
//           decoupe est innocente : il manque un dessin.
// Sans cette separation, un essai peut viser la mauvaise moitie du compte — c'est ce qui
// est arrive a l'essai 12, qui a ajoute une categorie de dessin sur un `absent` qui n'en
// venait pas (`ao_geom_tie_env2_absent_px` est reste a 0, le compte n'a pas bouge).
uint64_t g_fam_absent_nocut_match[kFamCount] = {};
uint64_t g_fam_absent_nocut_off[kFamCount] = {};
bool g_geom_frame = false;              // cette image porte les deux instantanes
// Depuis l'essai 9 la profondeur de prepasse se relit sur les DEUX plateformes, par
// `export_depth` : GLES ne rend pas `GL_DEPTH_COMPONENT`, il rend un RGBA8, et c'est le meme
// entier 24 bits. 0 = pas encore, 1 = mesure, -1 = refuse.
int g_geom_state = 0;
uint64_t g_geom_frames = 0;
uint64_t g_geom_cover = 0;    // denominateur : pixels monde dessines dont la scene a une profondeur
uint64_t g_geom_absent = 0;   // ... dont la prepasse ne porte AUCUNE profondeur
uint64_t g_geom_absent_legacy = 0;
uint64_t g_geom_gap[4] = {0, 0, 0, 0};         // ecart > 4 / 64 / 1024 / 16384 quanta de 24 bits
uint64_t g_geom_gap_legacy[4] = {0, 0, 0, 0};
uint64_t g_geom_near = 0, g_geom_far = 0;                // livre : prepasse DEVANT / DERRIERE
uint64_t g_geom_near_legacy = 0, g_geom_far_legacy = 0;
uint64_t g_sway_gap_px = 0;        // pixels que le deplacement a BOUGES (livre contre legacy)
uint64_t g_sway_gap_world_px = 0;  // les memes, restreints aux pixels monde dessines
// ... et les MEMES populations par famille (1 = TFRAG, 2 = TIE, 3 = SHRUB) : c'est la reponse au
// verdict (c), « shrub contre tfrag contre TIE ».
uint64_t g_fam_cover[kFamCount] = {};
uint64_t g_fam_absent[kFamCount] = {};
uint64_t g_fam_gap64[kFamCount] = {};
uint64_t g_fam_gap64_legacy[kFamCount] = {};
// ── TROIS DECOUPAGES DE DIAGNOSTIC DE LA POPULATION `gap64`, PAR FAMILLE ────────────────────
// Ils ne changent aucune definition de terme : ce sont des sous-comptes gratuits de la MEME
// branche `else` de la boucle de comparaison, destines a trancher entre trois causes du
// `ao_sway_gap_px` residuel : (A) desaccord de rasterisation d'un pixel sur une silhouette —
// structurel, aucun correctif de dessin ne le retire —, (B) petit deplacement de sommet,
// (C) la prepasse dessine un occluder que l'image ne dessine pas.
// (1) L'ECHELLE de l'ecart par famille : pour chaque k, les pixels dont |d| depasse
// tol[k] (4 / 64 / 1024 / 16384 quanta). Seule la somme TOUTES familles existait
// (`g_geom_gap[k]`). L'indice 1 doit reproduire exactement `g_fam_gap64`.
uint64_t g_fam_gap_hist[kFamCount][4] = {};
// (2) Le SIGNE de l'ecart parmi les pixels qui franchissent tol[1] : `near` = la prepasse est
// DEVANT la scene (elle dessine un occluder que l'image ne dessine pas), `far` = elle est
// DERRIERE (il lui manque une surface, ou son sommet est deplace autrement).
uint64_t g_fam_gap64_near[kFamCount] = {};
uint64_t g_fam_gap64_far[kFamCount] = {};
// (3) La SILHOUETTE parmi les memes pixels : `edge` = le voisinage 8-connexe de la profondeur
// de SCENE porte une marche (au moins un voisin a une profondeur et s'ecarte de plus de
// tol[1]), `inner` = aucun. Un `inner` NON NUL REFUTE l'hypothese « desaccord de
// rasterisation sur silhouette » : ces pixels-la sont au milieu d'une surface plane et un
// correctif de dessin peut les retirer.
uint64_t g_fam_gap64_edge[kFamCount] = {};
uint64_t g_fam_gap64_inner[kFamCount] = {};
// (4) LE PIXEL LE PLUS ECARTE, NOMME. Quand `gap64` tombe a UN pixel, « 1 sur 5 411, au bord
// d'une silhouette » ne dit ni ou il est, ni de combien il s'ecarte — et sur le shrub le TAUX DE
// BASE du test de silhouette vaut 1000 pour 1000 (`ao_geom_shrub_edge_base_rate_x1000`), donc la
// repartition edge/inner y est vraie par construction et ne classe rien. On garde le maximum de
// |d| par famille avec ses coordonnees, les deux profondeurs en quanta 24 bits et l'image de
// recensement ou il est tombe : un sous-compte gratuit de la MEME branche, qui nomme le residu
// au lieu de le laisser deviner.
uint64_t g_fam_worst_q[kFamCount] = {};
uint64_t g_fam_worst_x[kFamCount] = {};
uint64_t g_fam_worst_y[kFamCount] = {};
uint64_t g_fam_worst_pre_q[kFamCount] = {};
uint64_t g_fam_worst_scene_q[kFamCount] = {};
uint64_t g_fam_worst_frame[kFamCount] = {};
// ── (n) L'INTERROGATOIRE DU PILOTE, ses trois compteurs ──────────────────────────────────────
// Remplis par `arch_interrogate`, une fois par programme lie qui recoit l'AO. Voir le
// commentaire de cette fonction : `_switch_readers` est le CONTROLE POSITIF sans lequel
// `_luma_mask_sites = 0` ne prouverait rien.
// Le taux de base du test de silhouette, echantillonne un pixel sur N sur la population
// COUVERTE : c'est le denominateur sans lequel `gap64_edge / gap64_inner` n'est pas jugeable.
constexpr size_t kEdgeProbeStride = 16;
uint64_t g_fam_edge_probe_pop[kFamCount] = {};
uint64_t g_fam_edge_probe_hit[kFamCount] = {};
std::vector<GLuint> g_arch_seen_programs;
uint64_t g_arch_programs_queried = 0;
uint64_t g_arch_switch_readers = 0;
uint64_t g_arch_luma_mask_sites = 0;
// La SEPARATION des pixels « absent » : au bord d'une silhouette (au moins un voisin porte une
// profondeur de prepasse) ou au MILIEU d'un trou (aucun). Voir le commentaire du site de compte,
// dans `proof_post_opaque`.
uint64_t g_fam_absent_edge[kFamCount] = {};
uint64_t g_fam_absent_inner[kFamCount] = {};
// ... et la meme population separee par ce que le tampon porte VRAIMENT : `pl` exactement nul
// (rien n'a ete ecrit) contre `pl` dans les 16 premiers quanta (geometrie lointaine que le seuil
// `1e-6f` mislibelle). Voir le commentaire du site de publication.
uint64_t g_fam_absent_zero[kFamCount] = {};
uint64_t g_fam_absent_farq[kFamCount] = {};

// lighting-ao-indirect (c)/(g) : les plages ECARTEES de la prepasse — les draws que la passe
// principale dessine SANS ecrire la profondeur. Recensees au CHARGEMENT par les contributeurs,
// rejouees par `measure_phantom_occluders` quand `g_noz_pass` est vrai.
bool g_noz_pass = false;
// (A4) La camera de l'image en cours de prepasse, pour le contributeur qui doit poser SA propre
// projection : le TIE en a besoin pour `init_etie_cam_uniforms`, et il ne peut pas prendre celle
// de `m_common_data.settings.camera` — quand la prepasse tire (bucket 6), le DMA TIE de l'image
// n'a pas encore ete lu (Tie3.cpp:2141-2153). Non nulle uniquement pendant une passe.
const GoalBackgroundCameraData* g_cur_cam = nullptr;
struct CamScope {
  explicit CamScope(const GoalBackgroundCameraData& c) { g_cur_cam = &c; }
  ~CamScope() { g_cur_cam = nullptr; }
};
uint64_t g_noz_ranges = 0, g_noz_inds = 0;
uint64_t g_wind_pre_calls = 0, g_wind_pre_inds = 0;
// (A3) LE CHEMIN VENT DU TIE LISAIT UNE VISIBILITE D'UNE IMAGE DE RETARD. `draw_tree_wind`
// filtrait ses groupes d'instances par `tree.vis_temp` (Tie3.cpp:2492) ; `vis_temp` est rempli par
// `cull_check_all_slow` dans `setup_all_trees` (Tie3.cpp:971), appele depuis `Tie3::render` au
// bucket 9 — APRES la prepasse, qui tire au bucket 6 depuis `prepass::on_first_camera`
// (background_common.cpp:2846). La prepasse lisait donc la visibilite de l'image PRECEDENTE et
// SOUS-dessinait : 3136 px de `ao_geom_tie_absent_px` sur 3335 de `ao_sway_gap_px`, IDENTIQUES
// dans les deux bras (donc insensibles au deplacement de sommet). Le filtre est retire du chemin
// de PROFONDEUR seul ; ces deux comptes disent de combien de groupes.
uint64_t g_tie_wind_groups_pre = 0;       // groupes dessines par la prepasse
uint64_t g_tie_wind_groups_visgated = 0;  // ... que l'ancien filtre `vis_temp` aurait dessines
// (A2) LE FANTOME AU-DESSUS DU VIDE. Voir `publish_all`.
uint64_t g_phantom_void_px = 0, g_phantom_void_legacy_px = 0, g_phantom_void_pop_px = 0;
uint64_t g_phantom_void_frames = 0;
uint64_t g_phantom_px = 0, g_phantom_cover_px = 0;
int g_phantom_state = 0;  // 0 = pas encore mesure, 1 = mesure, -1 = non supporte

// Preuve.
bool g_probe_frame = false;
// ── LA TRIADE D'IMAGES DU RECENSEMENT (terme 5) ───────────────────────────────────────────────
// `g_probe_frame` reste l'image LOURDE : elle seule porte le stencil de preuve, les relectures
// de profondeur, le recensement de geometrie et la sonde d'alpha — les termes 1, 3 et 4 gardent
// donc EXACTEMENT la meme population qu'a l'essai 10. Les deux images qui la suivent sont
// LEGERES : elles ne font que garder le meme etat de mesure pour que le recensement du tampon
// d'AO dispose de deux releves SEPARES D'UNE SEULE IMAGE, ce que le contrat (k) demande.
int g_probe_pair_phase = -1;  // -1 hors sonde, 0 lourde, 1 reference, 2 comparee
// ── (essai 17) LE BRAS TEMOIN DU RECENSEMENT ETAIT MORT ──────────────────────────────────────
// Le recensement tire son etat de `g_static_probe.state`, et `ao_static_probe::kStates` vaut 6 :
// `st / 6` valait donc TOUJOURS 0 des que la sonde de stabilite est active — c'est-a-dire a
// CHAQUE course appareil de cet item. Les six etats TEMOIN que le commentaire d'AmbientOcclusion
// annonce (« l'ablation ne coute aucune jambe de plus ») n'ont jamais ete rendus : la preuve le
// dit, toutes les populations `ao_*_legacy_*` y sont a ZERO en face de leurs jumelles livrees.
// Consequence : `ao_contact_band_px=0` n'avait AUCUN contraste — un vert par INACTION sur la
// grandeur meme qui juge la bande claire que l'owner voit au raccord mur/toit.
// Reparation, purement ADDITIVE : la sonde garde ses ticks (1200..1353) et ses populations, et
// les six etats temoin sont rendus APRES elle, au meme pas de 30 ticks et avec la meme triade de
// phases. Aucune image du bras LIVRE ne change de tick, donc aucune valeur acquise ne bouge.
constexpr int64_t kWitnessStart =
    ao_static_probe::kStart + ao_static_probe::kStates * ao_static_probe::kStride;
bool g_census_witness = false;
int g_census_witness_state = -1;
int64_t g_census_witness_last_tick = -1;
uint64_t g_probe_seq = 0;  // combien d'images sondees ont commence — choisit le palier d'AO
// ── (terme 3) LES SIX IMAGES DU RECENSEMENT GEOMETRIQUE, ANCREES SUR LE TICK LOGIQUE ────────
// essai 15. Elles se tiraient sur `g_probe_seq % 6`, c'est-a-dire sur le compteur de CHAINES
// RENDUES (`g_frame`, PrePass.cpp:1196) — pas sur un tick. Deux consequences mesurees, toutes
// deux fatales a une grandeur de porte :
//   . `ao_sway_gap_px` est un TOTAL DE COURSE que rien ne remet a zero : une course qui rend
//     60 chaines de plus ajoute une image entiere de recensement au total. Mesure : proof.txt
//     frames=1740, ao_geom_frames=6, gap=94 ; proof-prev.txt frames=1800, ao_geom_frames=7,
//     gap=33 — deux denominateurs differents sous un seul nom.
//   . l'instant lui-meme se promene : le tick logique (une image SIMULEE) et le compteur de
//     chaines rendues peuvent diverger (kmachine.cpp:6261-6265 le dit et le chiffre).
// D'ou six ticks FIXES, tous au-dela de 1200 — le tick ou la sonde deterministe de l'item
// enfant trouve la scene etablie. Les ticks REELLEMENT retenus sont publies : un lecteur peut
// contredire le determinisme au lieu de le croire.
//
// essai 16, LE PAS PASSE DE 60 A 21, POUR DEUX RAISONS MESUREES — pas pour arranger la porte :
//   . LE CALENDRIER NE TENAIT PAS DANS LA COURSE. Pas de 60, le sixieme tick tombe a 1500 ;
//     l'essai 15 a fini a lf ~= 1423 (proof.txt : `ao_geom_tick_0..3` = 1200/1260/1320/1380,
//     `_4` et `_5` a 0, `ao_geom_frames=4`). Deux ticks manquants, et le terme 3 se declare
//     NON MESURE — c'est-a-dire un defaut nomme — sur un recensement dont les quatre images
//     tirees rendent pourtant zero. Pas de 21, le sixieme tombe a 1305 : 118 ticks de marge,
//     et la course n'a plus a etre allongee. Le plafond de l'autre bout est structurel : la
//     campagne de cout prend la parole a l'image 2000 (`AmbientOcclusion.cpp` kCostStartFrame)
//     et desarme `probe_base` avec elle — tout tick non encore tire y serait perdu. 1305
//     tombe vers l'image 1545, loin dessous ; 1500 tombait vers 1739, a 261 images du bord.
//   . 60 TICKS RATAIT SA PROPRE RAISON D'ETRE. Le pas etait justifie par « une seconde de jeu,
//     pour que la phase de la brise differe d'un echantillon a l'autre ». Or la composante
//     dominante du feuillage est a 2,13 Hz (`foliage_wind.cpp:908`), soit une periode de
//     28,2 ticks : 60 ticks valent 2,13 periodes et n'avancent la phase que de 0,13 cycle par
//     echantillon — six echantillons quasiment en phase. 21 ticks valent 0,745 periode : la
//     phase avance de trois quarts de cycle a chaque fois, ce que le pas de 60 promettait.
//     21 est aussi premier avec la cadence de sonde (30 images) : les echeances ne viennent
//     pas se coller systematiquement sur les memes creneaux.
constexpr int64_t kGeomTickStart = 1200;
constexpr int64_t kGeomTickStride = 21;
constexpr int kGeomTicks = 6;
bool g_geom_due = false;
bool g_geom_tick_anchored = false;
int g_geom_tick_next = 0;
int64_t g_geom_tick_last = -1;
int64_t g_geom_tick_seen[kGeomTicks] = {-1, -1, -1, -1, -1, -1};
uint64_t g_geom_tick_exact = 0;
// L'IMAGE DESSINEE du dernier tick tire. Le calendrier a un plafond STRUCTUREL a l'autre bout :
// la campagne de cout s'arme a l'image 2000 et desarme `probe_base`, donc l'ancrage par tick.
// Publier cette image, c'est publier la marge qui reste avant ce bord.
uint64_t g_geom_tick_last_frame = 0;
uint64_t g_probe_frames = 0;
uint64_t g_probe_px = 0;
uint64_t g_leak_px = 0;
uint64_t g_excluded_px = 0;
uint64_t g_hit_px = 0;
uint64_t g_unmarked_px = 0;
GLuint g_probe_fbo = 0, g_probe_color = 0, g_probe_ds = 0;
// ── LA SONDE EN TEXTURES (essai 9) ─────────────────────────────────────────────
// Un renderbuffer ne s'echantillonne pas : la sonde ne pouvait relire couleur, profondeur et
// stencil que par `glReadPixels`, dont DEUX formats sur trois n'existent pas en GLES 3.2. Les
// trois cibles sont donc des textures. `g_probe_res` est la RESOLUTION : les drapeaux de shade()
// seuilles a 0/255 et la FAMILLE dans l'alpha, ecrits par TEST de stencil — le seul acces au
// stencil que GLES accorde.
GLuint g_probe_res_fbo = 0, g_probe_res = 0;
GLenum g_probe_fmt = 0;  // le format couleur de `render_fb` au moment de l'allocation

// ── LA SONDE PORTABLE (essai 9) : un quad plein ecran, un RGBA8, et le deballage ─────────────
// Le quad est celui de `AmbientOcclusionPass::ensure_quad` (4 vec2, TRIANGLE_STRIP, attribut 0) :
// `ao_probe.vert` consomme exactement `post_processing.vert`.
GLuint g_quad_vao = 0, g_quad_vbo = 0;
bool g_quad_ready = false;
GLuint g_exp_fbo = 0, g_exp_tex = 0;
int g_exp_w = 0, g_exp_h = 0;
std::vector<uint8_t> g_exp_buf;
// Temoin de l'export, bureau seul : ecart maximal en quanta 24 bits entre le chemin portable et
// la relecture NATIVE de la meme profondeur, et l'etendue de la population lue. Un `maxq` de 0
// sur une population PLATE ne prouverait rien : `span` est son controle de non-vacuite.
uint64_t g_exp_maxq = 0, g_exp_pop = 0, g_exp_span_q = 0, g_exp_cmp_frames = 0;
int g_exp_state = 0;  // 0 = pas encore, 1 = ok, -1 = refuse
int g_probe_w = 0, g_probe_h = 0;
int g_probe_state = 0;  // 0 = pas encore, 1 = ok, -1 = refuse (publie)

void ensure_fbo(int w, int h) {
  gl_query_census::Armed _ap("prepass-ensure-fbo");
  if (g_fbo && g_w == w && g_h == h) {
    return;
  }
  if (g_fbo) {
    glFinish();  // meme classe de danger que free_targets : Adreno execute en differe
    glDeleteFramebuffers(1, &g_fbo);
    glDeleteTextures(1, &g_depth_tex);
    g_fbo = 0;
    g_depth_tex = 0;
  }
  g_w = w;
  g_h = h;
  glGenTextures(1, &g_depth_tex);
  glBindTexture(GL_TEXTURE_2D, g_depth_tex);
  glTexImage2D(GL_TEXTURE_2D, 0, GL_DEPTH24_STENCIL8, w, h, 0, GL_DEPTH_STENCIL,
               GL_UNSIGNED_INT_24_8, nullptr);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_COMPARE_MODE, GL_NONE);
  glGenFramebuffers(1, &g_fbo);
  glBindFramebuffer(GL_FRAMEBUFFER, g_fbo);
  glFramebufferTexture2D(GL_FRAMEBUFFER, GL_DEPTH_STENCIL_ATTACHMENT, GL_TEXTURE_2D, g_depth_tex,
                         0);
  // Profondeur seule : meme idiome que le FBO de la carte d'ombre soleil (background_common).
  GLenum none = GL_NONE;
  glDrawBuffers(1, &none);
  glReadBuffer(GL_NONE);
  if (glCheckFramebufferStatus(GL_FRAMEBUFFER) != GL_FRAMEBUFFER_COMPLETE) {
    lg::error("[lighting-ao-indirect] FBO de prepasse incomplet ({}x{})", w, h);
  }
}

void ensure_quad() {
  if (g_quad_ready) {
    return;
  }
  const float verts[8] = {-1.f, -1.f, -1.f, 1.f, 1.f, -1.f, 1.f, 1.f};
  glGenVertexArrays(1, &g_quad_vao);
  glGenBuffers(1, &g_quad_vbo);
  glBindVertexArray(g_quad_vao);
  glBindBuffer(GL_ARRAY_BUFFER, g_quad_vbo);
  glBufferData(GL_ARRAY_BUFFER, sizeof(verts), verts, GL_STATIC_DRAW);
  glEnableVertexAttribArray(0);
  glVertexAttribPointer(0, 2, GL_FLOAT, GL_TRUE, 2 * sizeof(float), nullptr);
  glBindBuffer(GL_ARRAY_BUFFER, 0);
  glBindVertexArray(0);
  g_quad_ready = true;
}

void ensure_export(int w, int h) {
  if (g_exp_fbo && g_exp_w == w && g_exp_h == h) {
    return;
  }
  if (g_exp_fbo) {
    glFinish();  // meme classe de danger que ensure_fbo : Adreno execute en differe
    glDeleteFramebuffers(1, &g_exp_fbo);
    glDeleteTextures(1, &g_exp_tex);
    g_exp_fbo = 0;
    g_exp_tex = 0;
  }
  g_exp_w = w;
  g_exp_h = h;
  glGenTextures(1, &g_exp_tex);
  glBindTexture(GL_TEXTURE_2D, g_exp_tex);
  glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8, w, h, 0, GL_RGBA, GL_UNSIGNED_BYTE, nullptr);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
  glGenFramebuffers(1, &g_exp_fbo);
  glBindFramebuffer(GL_FRAMEBUFFER, g_exp_fbo);
  glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, g_exp_tex, 0);
  if (glCheckFramebufferStatus(GL_FRAMEBUFFER) != GL_FRAMEBUFFER_COMPLETE) {
    lg::error("[lighting-ao-indirect] FBO d'export incomplet ({}x{})", w, h);
    g_exp_state = -1;
  } else if (g_exp_state == 0) {
    g_exp_state = 1;
  }
}

void ensure_white() {
  if (g_white_tex) {
    return;
  }
  glGenTextures(1, &g_white_tex);
  glBindTexture(GL_TEXTURE_2D, g_white_tex);
  const uint8_t px = 255;
  glTexImage2D(GL_TEXTURE_2D, 0, GL_R8, 1, 1, 0, GL_RED, GL_UNSIGNED_BYTE, &px);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
}

int world_bucket_family(int id) {
  using B = jak1::BucketId;
  switch ((B)id) {
    case B::TFRAG_LEVEL0:
    case B::TFRAG_NEAR_LEVEL0:
    case B::TFRAG_LEVEL1:
    case B::TFRAG_NEAR_LEVEL1:
      return kFamTfrag;
    case B::TIE_NEAR_LEVEL0:
    case B::TIE_LEVEL0:
    case B::TIE_NEAR_LEVEL1:
    case B::TIE_LEVEL1:
      return kFamTie;
    case B::SHRUB_NORMAL_LEVEL0:
    case B::SHRUB_BILLBOARD_LEVEL0:
    case B::SHRUB_TRANS_LEVEL0:
    case B::SHRUB_NORMAL_LEVEL1:
    case B::SHRUB_BILLBOARD_LEVEL1:
    case B::SHRUB_TRANS_LEVEL1:
      return kFamShrub;
    default:
      return 0;
  }
}

// ── LA PASSE, ET SON DETECTEUR ────────────────────────────────────────────────────────────────
// Un passage de prepasse = poser l'etat, dessiner TOUTES les plages de TOUS les contributeurs,
// restaurer. Il est appele deux fois sur une image sondee : une fois pour de vrai (decoupe
// ARMEE, c'est cette profondeur que l'estimateur d'AO consomme), une fois en CONTROLE (decoupe
// DESARMEE). Le detecteur qui les juge est le MEME, et c'est le bras desarme qui prouve qu'il
// sait rendre autre chose que zero : sans lui, `ao_on_alpha_px = 0` serait un vert par inaction.

// Le FBO de classification : une couleur RGBA8 a nous, et LA PROFONDEUR DE LA PREPASSE, partagee.
// C'est ce partage qui rend le test possible : en GL_EQUAL, seul le fragment qui a GAGNE la
// profondeur repasse, donc la couleur relue decrit le fragment que l'estimateur d'AO a vu.
void ensure_class(int w, int h) {
  if (g_class_fbo && g_class_w == w && g_class_h == h && g_class_depth_src == g_depth_tex) {
    return;
  }
  if (g_class_fbo) {
    glFinish();
    glDeleteFramebuffers(1, &g_class_fbo);
    glDeleteTextures(1, &g_class_tex);
    g_class_fbo = 0;
    g_class_tex = 0;
  }
  g_class_w = w;
  g_class_h = h;
  g_class_depth_src = g_depth_tex;
  glGenTextures(1, &g_class_tex);
  glBindTexture(GL_TEXTURE_2D, g_class_tex);
  glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8, w, h, 0, GL_RGBA, GL_UNSIGNED_BYTE, nullptr);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
  glGenFramebuffers(1, &g_class_fbo);
  glBindFramebuffer(GL_FRAMEBUFFER, g_class_fbo);
  glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, g_class_tex, 0);
  glFramebufferTexture2D(GL_FRAMEBUFFER, GL_DEPTH_STENCIL_ATTACHMENT, GL_TEXTURE_2D, g_depth_tex, 0);
  GLenum bufs[1] = {GL_COLOR_ATTACHMENT0};
  glDrawBuffers(1, bufs);
  if (glCheckFramebufferStatus(GL_FRAMEBUFFER) != GL_FRAMEBUFFER_COMPLETE) {
    lg::error("[lighting-ao-indirect] FBO de classification incomplet ({}x{})", w, h);
    g_class_state = -1;
  } else {
    g_class_state = 1;
  }
}

// Dessine toutes les plages de tous les contributeurs. Un contributeur par (renderer, niveau) :
// plusieurs instances d'un renderer (un bucket par categorie) cachent le meme niveau ; la
// premiere qui le nomme dessine, les autres se taisent.
uint64_t draw_all_contributors(SharedRenderState* rs, int* out_levels) {
  std::unordered_set<std::string> seen;
  uint64_t total = 0;
  for (DepthContributor* c : g_contributors) {
    const std::string& level = c->prepass_level_name();
    if (level.empty()) {
      continue;
    }
    std::string key = c->prepass_kind();
    key += ':';
    key += level;
    if (!seen.insert(key).second) {
      continue;
    }
    total += c->draw_depth_prepass(rs);
  }
  if (out_levels) {
    *out_levels = (int)seen.size();
  }
  return total;
}

// Remet a une valeur IMPOSSIBLE l'etat memoise par `draw_depth_range`.
void forget_range_state() {
  g_last_state_tex = 0xffffffffu;
  g_last_state_mode = 0xffff;
  g_last_aref = -2.f;
  g_last_amb = -2.f;
  g_last_tex = 0xffffffffu;
}

// Rejoue les MEMES plages en GL_EQUAL contre la profondeur qui vient d'etre ecrite, sans aucun
// discard, et relit la classification du fragment GAGNANT de chaque pixel :
//   R = il est sous le seuil d'alpha      G = il a gagne (denominateur)      B = bande ambigue
// La decoupe du detecteur est TOUJOURS armee : c'est la profondeur d'entree qui distingue les
// deux bras, pas le predicat.
void run_classification(SharedRenderState* rs, int w, int h, uint64_t* on, uint64_t* cover,
                        uint64_t* fringe, bool nocut) {
  ensure_class(w, h);
  if (g_class_state != 1 || !g_shaders) {
    return;
  }
  while (glGetError() != GL_NO_ERROR) {
  }
  const GLuint id = (*g_shaders)[ShaderId::PREPASS_WORLD].id();
  glBindFramebuffer(GL_FRAMEBUFFER, g_class_fbo);
  glViewport(0, 0, w, h);
  glColorMask(GL_TRUE, GL_TRUE, GL_TRUE, GL_TRUE);
  GLfloat prev_clear[4] = {0.f, 0.f, 0.f, 0.f};
  glGetFloatv(GL_COLOR_CLEAR_VALUE, prev_clear);
  glClearColor(0.f, 0.f, 0.f, 0.f);
  glClear(GL_COLOR_BUFFER_BIT);
  glClearColor(prev_clear[0], prev_clear[1], prev_clear[2], prev_clear[3]);
  glEnable(GL_DEPTH_TEST);
  glDepthFunc(GL_EQUAL);
  glDepthMask(GL_FALSE);
  glUniform1i(glu::loc(id, "u_cut_mode"), 1);
  const bool saved_armed = g_cut_armed;
  g_cut_armed = true;
  forget_range_state();
  ao_tie_alpha_probe::pre_capture_begin(nocut);
  draw_all_contributors(rs, nullptr);
  ao_tie_alpha_probe::pre_capture_end();
  g_cut_armed = saved_armed;
  glUniform1i(glu::loc(id, "u_cut_mode"), 0);

  std::vector<uint8_t> px((size_t)w * h * 4);
  glPixelStorei(GL_PACK_ALIGNMENT, 1);
  glBindFramebuffer(GL_READ_FRAMEBUFFER, g_class_fbo);
  glReadBuffer(GL_COLOR_ATTACHMENT0);
  glReadPixels(0, 0, w, h, GL_RGBA, GL_UNSIGNED_BYTE, px.data());
  const GLenum err = glGetError();
  if (err != GL_NO_ERROR) {
    lg::error("[lighting-ao-indirect] relecture de la classification refusee (gl=0x{:x})",
              (unsigned)err);
    g_class_state = -1;
    return;
  }
  for (size_t i = 0; i < px.size(); i += 4) {
    if (px[i + 1] < 128) {
      continue;  // aucun fragment de la prepasse n'a gagne ce pixel
    }
    (*cover)++;
    if (px[i] >= 128) {
      (*on)++;
    } else if (px[i + 2] >= 128) {
      (*fringe)++;
    }
  }
}

// L'INSTANTANE DE LA PREPASSE. Sur BUREAU seulement, la relecture NATIVE tourne AUSSI et les deux
// se comparent : `ao_depth_export_maxq` est l'ecart maximal en quanta 24 bits — il vaut 0 si le
// re-encodage est fidele. Il ne prouverait rien sur un tampon plat : `ao_depth_export_span_q`
// publie l'etendue de la population lue, c'est son controle de non-vacuite.
bool read_prepass_depth(int w, int h, std::vector<float>* out) {
  if (!g_fbo || w <= 0 || h <= 0) {
    return false;
  }
  if (!export_depth(g_depth_tex, w, h, out)) {
    return false;
  }
#ifndef __ANDROID__
  static std::vector<float> s_native;
  if (s_native.size() < (size_t)w * h) {
    s_native.resize((size_t)w * h);
  }
  GLint prev_read = 0;
  glGetIntegerv(GL_READ_FRAMEBUFFER_BINDING, &prev_read);
  while (glGetError() != GL_NO_ERROR) {
  }
  glBindFramebuffer(GL_READ_FRAMEBUFFER, g_fbo);
  glPixelStorei(GL_PACK_ALIGNMENT, 1);
  glReadPixels(0, 0, w, h, GL_DEPTH_COMPONENT, GL_FLOAT, s_native.data());
  const GLenum nerr = glGetError();
  glBindFramebuffer(GL_READ_FRAMEBUFFER, (GLuint)prev_read);
  if (nerr == GL_NO_ERROR) {
    float lo = 2.f, hi = -1.f;
    for (size_t i = 0; i < (size_t)w * h; i++) {
      const double dq = std::fabs((double)(*out)[i] - (double)s_native[i]) * 16777215.0;
      const uint64_t q = (uint64_t)(dq + 0.5);
      if (q > g_exp_maxq) {
        g_exp_maxq = q;
      }
      if (s_native[i] < lo) {
        lo = s_native[i];
      }
      if (s_native[i] > hi) {
        hi = s_native[i];
      }
    }
    const uint64_t span = (uint64_t)((double)(hi - lo) * 16777215.0 + 0.5);
    if (span > g_exp_span_q) {
      g_exp_span_q = span;
    }
    g_exp_pop += (uint64_t)w * h;
    g_exp_cmp_frames++;
  }
#endif
  return true;
}

// LE passage. `armed` = la decoupe d'alpha est active (le chemin LIVRE). `classify` = enchaine
// la passe de classification et range ses comptes dans les trois sorties.
uint64_t run_prepass(SharedRenderState* rs,
                     const GoalBackgroundCameraData& cam,
                     int w,
                     int h,
                     bool armed,
                     bool classify,
                     uint64_t* on,
                     uint64_t* cover,
                     uint64_t* fringe,
                     int* out_levels) {
  const CamScope cam_scope(cam);  // (A4) la camera que le TIE relira pour sa projection etie
  GLint prev_program = 0, prev_fbo = 0, prev_vp[4] = {0, 0, 0, 0}, prev_depth_func = GL_LEQUAL;
  GLint prev_vao = 0;
  const GLboolean prev_scissor = glIsEnabled(GL_SCISSOR_TEST);
  const GLboolean prev_cull = glIsEnabled(GL_CULL_FACE);
  const GLboolean prev_blend = glIsEnabled(GL_BLEND);
  const GLboolean prev_stencil = glIsEnabled(GL_STENCIL_TEST);
  const GLboolean prev_poly_off = glIsEnabled(GL_POLYGON_OFFSET_FILL);
  const GLboolean prev_depth_test = glIsEnabled(GL_DEPTH_TEST);
  GLboolean prev_depth_mask = GL_TRUE;
  GLboolean prev_color_mask[4] = {GL_TRUE, GL_TRUE, GL_TRUE, GL_TRUE};
  GLint prev_active_tex = GL_TEXTURE0;
  glGetIntegerv(GL_CURRENT_PROGRAM, &prev_program);
  glGetIntegerv(GL_DRAW_FRAMEBUFFER_BINDING, &prev_fbo);
  glGetIntegerv(GL_VIEWPORT, prev_vp);
  glGetIntegerv(GL_DEPTH_FUNC, &prev_depth_func);
  glGetIntegerv(GL_VERTEX_ARRAY_BINDING, &prev_vao);
  glGetBooleanv(GL_DEPTH_WRITEMASK, &prev_depth_mask);
  glGetBooleanv(GL_COLOR_WRITEMASK, prev_color_mask);
  glGetIntegerv(GL_ACTIVE_TEXTURE, &prev_active_tex);
  glActiveTexture(GL_TEXTURE0);
  GLint prev_tex0 = 0;
  glGetIntegerv(GL_TEXTURE_BINDING_2D, &prev_tex0);
  // (i) L'unite 18 porte le vent natif du shrub ET la carte de contact du TIE : la prepasse y lie
  // ses propres textures, elle doit rendre celle qu'elle a trouvee.
  glActiveTexture(GL_TEXTURE18);
  GLint prev_tex18 = 0;
  glGetIntegerv(GL_TEXTURE_BINDING_2D, &prev_tex18);
  glActiveTexture(GL_TEXTURE0);

  ensure_fbo(w, h);
  ensure_white();

  glBindFramebuffer(GL_FRAMEBUFFER, g_fbo);
  // Le viewport COURANT : celui de la scene 3D (0,0,render_fb_w,render_fb_h sur les deux
  // plateformes). La profondeur doit tomber sous le meme gl_FragCoord que la passe principale.
  glViewport(prev_vp[0], prev_vp[1], prev_vp[2], prev_vp[3]);
  glDisable(GL_SCISSOR_TEST);
  glDisable(GL_CULL_FACE);
  glDisable(GL_BLEND);
  glDisable(GL_STENCIL_TEST);
  glDisable(GL_POLYGON_OFFSET_FILL);
  glColorMask(GL_FALSE, GL_FALSE, GL_FALSE, GL_FALSE);
  glEnable(GL_DEPTH_TEST);
  glDepthMask(GL_TRUE);
  // Convention PS2 inversee, la meme que le FBO de rendu : efface a 0 (le plus loin), GEQUAL.
  glDepthFunc(GL_GEQUAL);
  glClearDepthf(0.0f);
  glClear(GL_DEPTH_BUFFER_BIT);

  const auto& sh = (*g_shaders)[ShaderId::PREPASS_WORLD];
  sh.activate();
  const GLuint id = sh.id();
  const auto newcam = make_new_cam_mat(cam.rot, cam.perspective, cam.fog.x(), cam.hvdf_off.z());
  glUniformMatrix4fv(glu::loc(id, "pc_camera"), 1, GL_FALSE, newcam[0].data());
  glUniform4f(glu::loc(id, "cam_trans"), cam.trans[0], cam.trans[1], cam.trans[2],
              cam.trans[3]);
  glUniform1i(glu::loc(id, "tex_T0"), 0);
  glUniform1i(glu::loc(id, "u_cut_mode"), 0);
  // Un uniforme DECLARE mais jamais lu est RETIRE par le compilateur GLSL, et `glu::loc` rend
  // alors -1 : la decoupe serait muette sans qu'une seule erreur ne sorte. On demande au pilote,
  // et on le publie — c'est la seule facon de savoir qui lit.
  g_cut_uniforms_ok = (glu::loc(id, "u_cut_aref") != -1) && (glu::loc(id, "u_cut_amb") != -1) &&
                      (glu::loc(id, "u_cut_mode") != -1) && (glu::loc(id, "tex_T0") != -1);
  // (i) L'ETAT INERTE, POSE AU DEBUT DE CHAQUE PASSAGE. Un contributeur qui n'annonce pas sa
  // famille (TFRAG) hérite donc d'un deplacement NUL, jamais de celui de l'arbre precedent :
  // c'est le meme piege que `u_tie_sway_amp` laisse a sa derniere valeur ferait ONDULER LE SOL.
  sway_none();

  g_cut_armed = armed;
  forget_range_state();
  const uint64_t total = draw_all_contributors(rs, out_levels);
  g_cut_armed = true;

  if (classify && on && cover && fringe) {
    run_classification(rs, w, h, on, cover, fringe, !armed);
  }
  // ---- restauration ----
  glBindVertexArray((GLuint)prev_vao);
  glUseProgram((GLuint)prev_program);
  glBindFramebuffer(GL_FRAMEBUFFER, (GLuint)prev_fbo);
  glViewport(prev_vp[0], prev_vp[1], prev_vp[2], prev_vp[3]);
  glColorMask(prev_color_mask[0], prev_color_mask[1], prev_color_mask[2], prev_color_mask[3]);
  if (prev_scissor) {
    glEnable(GL_SCISSOR_TEST);
  }
  if (prev_cull) {
    glEnable(GL_CULL_FACE);
  }
  if (prev_blend) {
    glEnable(GL_BLEND);
  }
  if (prev_stencil) {
    glEnable(GL_STENCIL_TEST);
  }
  if (prev_poly_off) {
    glEnable(GL_POLYGON_OFFSET_FILL);
  }
  if (!prev_depth_test) {
    glDisable(GL_DEPTH_TEST);
  }
  glDepthMask(prev_depth_mask);
  glDepthFunc((GLenum)prev_depth_func);
  glActiveTexture(GL_TEXTURE18);
  glBindTexture(GL_TEXTURE_2D, (GLuint)prev_tex18);
  glActiveTexture(GL_TEXTURE0);
  glBindTexture(GL_TEXTURE_2D, (GLuint)prev_tex0);
  glActiveTexture((GLenum)prev_active_tex);
  return total;
}

// lighting-ao-indirect, verdict (c) de l'owner : « publier ce qui est mesure AU POINT DE DESSIN
// du brin d'herbe, pas a l'entree de l'estimateur ». On rejoue les plages ECARTEES — les quads
// de feuillage que la passe principale dessine SANS ecrire la profondeur — contre la
// profondeur LIVREE de la prepasse, en GL_GREATER (convention PS2 : plus grand = plus pres) et
// sans jamais ecrire. La requete d'occlusion rend le nombre EXACT de pixels ou ce quad se
// serait pose DEVANT la geometrie reelle : c'est la population que l'owner voit s'assombrir.
// `ao_phantom_cover_px` est la meme geometrie sans test : le denominateur.
void measure_phantom_occluders(SharedRenderState* rs,
                               const GoalBackgroundCameraData& cam,
                               int w,
                               int h) {
#ifdef __ANDROID__
  // GLES 3 n'a pas GL_SAMPLES_PASSED (seulement GL_ANY_SAMPLES_PASSED, un booleen) : la mesure
  // n'existe pas dans le .so arm64 — ce n'est pas un drapeau a zero, c'est du code non COMPILE.
  (void)rs;
  (void)cam;
  (void)w;
  (void)h;
  g_phantom_state = -1;
#else
  if (!g_shaders || !g_fbo) {
    return;
  }
  const CamScope cam_scope(cam);  // (A4) idem : cette passe rejoue les memes contributeurs
  // `run_prepass` a deja TOUT restaure en sortant : on refait ici exactement son installation
  // (meme FBO, meme viewport, meme programme, memes uniformes), sans jamais effacer la
  // profondeur qu'elle vient d'ecrire.
  GLint prev_program = 0, prev_fbo = 0, prev_vp[4] = {0, 0, 0, 0}, prev_depth_func = GL_LEQUAL;
  GLint prev_vao = 0;
  const GLboolean prev_scissor = glIsEnabled(GL_SCISSOR_TEST);
  const GLboolean prev_cull = glIsEnabled(GL_CULL_FACE);
  const GLboolean prev_blend = glIsEnabled(GL_BLEND);
  const GLboolean prev_stencil = glIsEnabled(GL_STENCIL_TEST);
  const GLboolean prev_poly_off = glIsEnabled(GL_POLYGON_OFFSET_FILL);
  const GLboolean prev_depth_test = glIsEnabled(GL_DEPTH_TEST);
  GLboolean prev_depth_mask = GL_TRUE;
  GLboolean prev_color_mask[4] = {GL_TRUE, GL_TRUE, GL_TRUE, GL_TRUE};
  GLint prev_active_tex = GL_TEXTURE0;
  glGetIntegerv(GL_CURRENT_PROGRAM, &prev_program);
  glGetIntegerv(GL_DRAW_FRAMEBUFFER_BINDING, &prev_fbo);
  glGetIntegerv(GL_VIEWPORT, prev_vp);
  glGetIntegerv(GL_DEPTH_FUNC, &prev_depth_func);
  glGetIntegerv(GL_VERTEX_ARRAY_BINDING, &prev_vao);
  glGetBooleanv(GL_DEPTH_WRITEMASK, &prev_depth_mask);
  glGetBooleanv(GL_COLOR_WRITEMASK, prev_color_mask);
  glGetIntegerv(GL_ACTIVE_TEXTURE, &prev_active_tex);
  glActiveTexture(GL_TEXTURE0);
  GLint prev_tex0 = 0;
  glGetIntegerv(GL_TEXTURE_BINDING_2D, &prev_tex0);

  glBindFramebuffer(GL_FRAMEBUFFER, g_fbo);
  glViewport(prev_vp[0], prev_vp[1], prev_vp[2], prev_vp[3]);
  glDisable(GL_SCISSOR_TEST);
  glDisable(GL_CULL_FACE);
  glDisable(GL_BLEND);
  glDisable(GL_STENCIL_TEST);
  glDisable(GL_POLYGON_OFFSET_FILL);
  glEnable(GL_DEPTH_TEST);

  const auto& sh = (*g_shaders)[ShaderId::PREPASS_WORLD];
  sh.activate();
  const GLuint id = sh.id();
  const auto newcam = make_new_cam_mat(cam.rot, cam.perspective, cam.fog.x(), cam.hvdf_off.z());
  glUniformMatrix4fv(glu::loc(id, "pc_camera"), 1, GL_FALSE, newcam[0].data());
  glUniform4f(glu::loc(id, "cam_trans"), cam.trans[0], cam.trans[1], cam.trans[2], cam.trans[3]);
  glUniform1i(glu::loc(id, "tex_T0"), 0);
  glUniform1i(glu::loc(id, "u_cut_mode"), 0);
  sway_none();

  glDepthMask(GL_FALSE);
  glDepthFunc(GL_GREATER);
  glColorMask(GL_FALSE, GL_FALSE, GL_FALSE, GL_FALSE);

  GLuint q[2] = {0, 0};
  glGenQueries(2, q);
  g_cut_armed = true;
  g_noz_pass = true;
  forget_range_state();
  glBeginQuery(GL_SAMPLES_PASSED, q[0]);
  draw_all_contributors(rs, nullptr);
  glEndQuery(GL_SAMPLES_PASSED);

  glDepthFunc(GL_ALWAYS);
  forget_range_state();
  glBeginQuery(GL_SAMPLES_PASSED, q[1]);
  draw_all_contributors(rs, nullptr);
  glEndQuery(GL_SAMPLES_PASSED);
  g_noz_pass = false;

  GLuint hit = 0, cover = 0;
  glGetQueryObjectuiv(q[0], GL_QUERY_RESULT, &hit);
  glGetQueryObjectuiv(q[1], GL_QUERY_RESULT, &cover);
  g_phantom_px += hit;
  g_phantom_cover_px += cover;
  glDeleteQueries(2, q);
  g_phantom_state = 1;

  // ---- restauration : exactement l'etat dans lequel `run_prepass` laisse GL ----
  glBindVertexArray((GLuint)prev_vao);
  glUseProgram((GLuint)prev_program);
  glBindFramebuffer(GL_FRAMEBUFFER, (GLuint)prev_fbo);
  glViewport(prev_vp[0], prev_vp[1], prev_vp[2], prev_vp[3]);
  glColorMask(prev_color_mask[0], prev_color_mask[1], prev_color_mask[2], prev_color_mask[3]);
  if (prev_scissor) {
    glEnable(GL_SCISSOR_TEST);
  }
  if (prev_cull) {
    glEnable(GL_CULL_FACE);
  }
  if (prev_blend) {
    glEnable(GL_BLEND);
  }
  if (prev_stencil) {
    glEnable(GL_STENCIL_TEST);
  }
  if (prev_poly_off) {
    glEnable(GL_POLYGON_OFFSET_FILL);
  }
  if (!prev_depth_test) {
    glDisable(GL_DEPTH_TEST);
  }
  glDepthMask(prev_depth_mask);
  glDepthFunc((GLenum)prev_depth_func);
  glActiveTexture(GL_TEXTURE0);
  glBindTexture(GL_TEXTURE_2D, (GLuint)prev_tex0);
  glActiveTexture((GLenum)prev_active_tex);
#endif
}

void publish_all() {
  autoport_proof::publish("ao_direct_leak_px", g_leak_px);
  autoport_proof::publish("ao_hit_px", g_hit_px);
  autoport_proof::publish("ao_probe_px", g_probe_px);
  // ── (c)/(g) L'OCCLUDER FANTOME ──────────────────────────────────────────────────────────
  // `ao_noz_ranges` / `ao_noz_inds` : ce que la prepasse ECARTE desormais (draws sans z-write).
  // `ao_phantom_px` : les pixels ou ces quads se seraient poses DEVANT la geometrie reelle —
  // la population qui s'assombrissait. `ao_phantom_cover_px` est son denominateur (meme
  // geometrie, sans test de profondeur). `ao_phantom_state` : 0 pas mesure, 1 mesure, 2 non
  // supporte (GLES).
  autoport_proof::publish("ao_noz_ranges", g_noz_ranges);
  autoport_proof::publish("ao_noz_inds", g_noz_inds);
  autoport_proof::publish("ao_phantom_px", g_phantom_px);
  autoport_proof::publish("ao_phantom_cover_px", g_phantom_cover_px);
  autoport_proof::publish("ao_phantom_state", (uint64_t)(g_phantom_state < 0 ? 2 : g_phantom_state));
  autoport_proof::publish("ao_probe_frames", g_probe_frames);
  autoport_proof::publish("ao_leak_excluded_px", g_excluded_px);
  autoport_proof::publish("ao_probe_unmarked_px", g_unmarked_px);
  autoport_proof::publish("ao_prepass_indices", g_last_indices);
  autoport_proof::publish("ao_prepass_levels", (uint64_t)g_last_levels);
  autoport_proof::publish("ao_screen_ao_active", g_ao_valid ? 1 : 0);
  autoport_proof::publish_text("ao_apply_site", "shade.glsl:shade_body");
  // ── (b) L'ALPHA EST RESPECTE ────────────────────────────────────────────────────────────
  // `ao_on_alpha_px` est LA grandeur que le livrable demande : le nombre de pixels dont le
  // fragment que l'estimateur d'AO a vu est un texel sous le seuil d'alpha. Il vaut 0.
  // `ao_alpha_witness_px` est le MEME detecteur sur le MEME contenu, la decoupe desarmee : il
  // est non nul, et c'est lui qui interdit de lire le 0 d'a cote comme un vert par inaction.
  // `ao_alpha_cover_px` / `ao_alpha_witness_cover_px` sont leurs denominateurs.
  // `ao_alpha_fringe_px` compte la bande que le seuil CONSERVATEUR laisse passer (voir
  // prepass_world.frag) : il dit ce que la borne tod.a <= 1 coute reellement.
  autoport_proof::publish("ao_on_alpha_px", g_on_alpha_px);
  autoport_proof::publish("ao_alpha_witness_px", g_witness_px);
  autoport_proof::publish("ao_alpha_cover_px", g_alpha_cover_px);
  autoport_proof::publish("ao_alpha_witness_cover_px", g_witness_cover_px);
  autoport_proof::publish("ao_alpha_fringe_px", g_alpha_fringe_px);
  autoport_proof::publish("ao_alpha_frames", g_alpha_frames);
  // Combien de plages de la prepasse portent un test d'alpha, et sur combien : si ce rapport
  // etait nul, tout le reste serait vide de sens.
  autoport_proof::publish("ao_cut_ranges", g_cut_ranges);
  // (terme 3) L'ETAT D'ECHANTILLONNAGE HERITE. `_checked` est le denominateur : les plages a test
  // d'alpha dont la prepasse a relu l'objet texture sur une image sondee, JUSTE AVANT d'y poser le
  // sien. `_bad` = celles dont au moins un des quatre parametres n'etait pas celui que le mode du
  // draw demande, et les quatre cles suivantes disent LEQUEL. `_unknown` doit rester a 0 : au-dessus
  // de 0, un contributeur ne renseigne pas son mode et la mesure est aveugle sur ces plages-la.
  autoport_proof::publish("ao_pre_texstate_checked", g_texstate_checked);
  autoport_proof::publish("ao_pre_texstate_bad", g_texstate_bad);
  autoport_proof::publish("ao_pre_texstate_bad_wrap_s", g_texstate_bad_p[0]);
  autoport_proof::publish("ao_pre_texstate_bad_wrap_t", g_texstate_bad_p[1]);
  autoport_proof::publish("ao_pre_texstate_bad_min_filter", g_texstate_bad_p[2]);
  autoport_proof::publish("ao_pre_texstate_bad_mag_filter", g_texstate_bad_p[3]);
  autoport_proof::publish("ao_pre_texstate_unknown", g_texstate_unknown);
  autoport_proof::publish("ao_total_ranges", g_total_ranges);
  autoport_proof::publish("ao_cut_uniforms_ok", g_cut_uniforms_ok ? 1 : 0);
  // ── (c)/(g)/(i) LA PREPASSE CONTRE CE QUI EST DESSINE ───────────────────────────────────
  // `ao_geom_cover_px` : pixels dont la couleur vient d'un bucket monde ET qui portent une
  // profondeur de scene — le denominateur, mesure AU POINT DE DESSIN.
  // `ao_geom_gap_px` : ceux dont la profondeur de PREPASSE s'en ecarte de plus de 4 quanta de
  // 24 bits. C'est la population dont l'AO a ete calculee sur une AUTRE geometrie que celle que
  // l'owner voit. L'echelle monte par facteur 16 (`_64q`, `_1024q`, `_16384q`) : un seuil unique
  // choisi apres la mesure est un seuil choisi pour son resultat.
  // `ao_geom_near_px` / `_far_px` : de quel COTE — prepasse DEVANT la scene (un occluder que
  // l'image ne dessine pas : l'ombre qui flotte) ou DERRIERE (un occluder manquant).
  // `ao_geom_absent_px` : la prepasse n'a RIEN a ce pixel.
  // Les memes cinq grandeurs en `_legacy_` viennent du MEME dessin avec le deplacement de sommet
  // DESARME — l'etat de l'essai 6, rejoue dans la MEME image : c'est l'AVANT, mesure, pas relu
  // d'un commit. `ao_geom_state` : 0 pas mesure, 1 mesure, 2 non supporte.
  // ── LE TEMOIN DE L'EXPORT PORTABLE (essai 9) ──────────────────────────────────
  // `ao_depth_export_state` : 0 pas encore, 1 ok, 2 refuse. `_maxq` n'a de sens que sur bureau,
  // ou la relecture NATIVE tourne a cote ; il vaut 0 si le re-encodage 24 bits est fidele. Sur
  // l'appareil il n'y a PAS de reference native — `_cmp_frames` vaut 0 et le dit.
  autoport_proof::publish("ao_depth_export_state", (uint64_t)(g_exp_state < 0 ? 2 : g_exp_state));
  autoport_proof::publish("ao_depth_export_maxq", g_exp_maxq);
  autoport_proof::publish("ao_depth_export_pop_px", g_exp_pop);
  autoport_proof::publish("ao_depth_export_span_q", g_exp_span_q);
  autoport_proof::publish("ao_depth_export_cmp_frames", g_exp_cmp_frames);
  autoport_proof::publish("ao_geom_state", (uint64_t)(g_geom_state < 0 ? 2 : g_geom_state));
  autoport_proof::publish("ao_geom_frames", g_geom_frames);
  autoport_proof::publish("ao_geom_cover_px", g_geom_cover);
  autoport_proof::publish("ao_geom_gap_px", g_geom_gap[0]);
  autoport_proof::publish("ao_geom_gap_64q_px", g_geom_gap[1]);
  autoport_proof::publish("ao_geom_gap_1024q_px", g_geom_gap[2]);
  autoport_proof::publish("ao_geom_gap_16384q_px", g_geom_gap[3]);
  autoport_proof::publish("ao_geom_near_px", g_geom_near);
  autoport_proof::publish("ao_geom_far_px", g_geom_far);
  autoport_proof::publish("ao_geom_absent_px", g_geom_absent);
  autoport_proof::publish("ao_geom_legacy_gap_px", g_geom_gap_legacy[0]);
  autoport_proof::publish("ao_geom_legacy_gap_64q_px", g_geom_gap_legacy[1]);
  autoport_proof::publish("ao_geom_legacy_gap_1024q_px", g_geom_gap_legacy[2]);
  autoport_proof::publish("ao_geom_legacy_gap_16384q_px", g_geom_gap_legacy[3]);
  autoport_proof::publish("ao_geom_legacy_near_px", g_geom_near_legacy);
  autoport_proof::publish("ao_geom_legacy_far_px", g_geom_far_legacy);
  autoport_proof::publish("ao_geom_legacy_absent_px", g_geom_absent_legacy);
  // (i) LE DEPLACEMENT LUI-MEME : les pixels que le correctif a BOUGES, sur tout l'ecran puis
  // sur les seuls pixels monde dessines. S'il vaut 0, la scene ne bougeait pas et TOUT ce qui
  // precede est vide de sens — d'ou `ao_sway_wind_on`, le regime de brise de la course.
  // Le decoupage PAR FAMILLE des memes populations — la reponse directe au verdict (c) :
  // `ao_geom_<famille>_absent_px` nomme le chemin dont la geometrie est DESSINEE sans que la
  // prepasse la porte, `_gap64_px` celui dont elle la porte AILLEURS.
  for (int f = 1; f < kFamCount; f++) {
    const std::string base = std::string("ao_geom_") + kFamNames[f];
    autoport_proof::publish((base + "_cover_px").c_str(), g_fam_cover[f]);
    autoport_proof::publish((base + "_absent_px").c_str(), g_fam_absent[f]);
    autoport_proof::publish((base + "_gap64_px").c_str(), g_fam_gap64[f]);
    autoport_proof::publish((base + "_legacy_gap64_px").c_str(), g_fam_gap64_legacy[f]);
    // ── LES TROIS DECOUPAGES DE `gap64` (diagnostic, aucune definition de terme ne change) ──
    // (1) l'ECHELLE de l'ecart, par famille. `_gap64q_px` doit valoir EXACTEMENT `_gap64_px`
    // ci-dessus : c'est un controle de coherence gratuit du decoupage, et une divergence
    // signalerait un defaut de l'instrument, pas du jeu.
    autoport_proof::publish((base + "_gap4q_px").c_str(), g_fam_gap_hist[f][0]);
    autoport_proof::publish((base + "_gap64q_px").c_str(), g_fam_gap_hist[f][1]);
    autoport_proof::publish((base + "_gap1024q_px").c_str(), g_fam_gap_hist[f][2]);
    autoport_proof::publish((base + "_gap16384q_px").c_str(), g_fam_gap_hist[f][3]);
    // (2) le SIGNE : `near` = prepasse DEVANT la scene (occluder que l'image ne dessine pas),
    // `far` = DERRIERE. Leur somme vaut `_gap64_px`.
    autoport_proof::publish((base + "_gap64_near_px").c_str(), g_fam_gap64_near[f]);
    autoport_proof::publish((base + "_gap64_far_px").c_str(), g_fam_gap64_far[f]);
    // (3) la SILHOUETTE : `edge` = marche de profondeur de SCENE dans le voisinage 8-connexe,
    // `inner` = aucune. Un `inner` non nul REFUTE l'hypothese silhouette. Leur somme vaut
    // aussi `_gap64_px`.
    autoport_proof::publish((base + "_gap64_edge_px").c_str(), g_fam_gap64_edge[f]);
    // (4) LE RESIDU, NOMME : de combien, ou, et entre quelles deux profondeurs.
    autoport_proof::publish((base + "_worst_q").c_str(), g_fam_worst_q[f]);
    autoport_proof::publish((base + "_worst_x").c_str(), g_fam_worst_x[f]);
    autoport_proof::publish((base + "_worst_y").c_str(), g_fam_worst_y[f]);
    autoport_proof::publish((base + "_worst_pre_q").c_str(), g_fam_worst_pre_q[f]);
    autoport_proof::publish((base + "_worst_scene_q").c_str(), g_fam_worst_scene_q[f]);
    autoport_proof::publish((base + "_worst_frame").c_str(), g_fam_worst_frame[f]);
    autoport_proof::publish((base + "_gap64_inner_px").c_str(), g_fam_gap64_inner[f]);
    // ... et LE TAUX DE BASE du meme test, sur la population couverte, un pixel sur
    // `kEdgeProbeStride`. `edge = 100 %` ne veut rien dire si le taux de base vaut deja 1000.
    autoport_proof::publish((base + "_edge_base_pop_px").c_str(), g_fam_edge_probe_pop[f]);
    autoport_proof::publish((base + "_edge_base_hit_px").c_str(), g_fam_edge_probe_hit[f]);
    autoport_proof::publish(
        (base + "_edge_base_rate_x1000").c_str(),
        g_fam_edge_probe_pop[f] ? (1000ull * g_fam_edge_probe_hit[f] / g_fam_edge_probe_pop[f])
                                : 0ull);
    // (terme 3) Parmi les « absent » de cette famille, ceux que le bras SANS DECOUPE D'ALPHA
    // porte : la prepasse dessine bien cette geometrie, c'est son alpha-test qui l'a jetee.
    autoport_proof::publish((base + "_absent_nocut_px").c_str(), g_fam_absent_nocut[f]);
    // ... et la separation des deux causes du MEME compte : `_match` = le bras sans decoupe porte
    // la profondeur de la SCENE (la decoupe a jete ce que l'image garde) ; `_off` = il porte autre
    // chose (la decoupe est innocente, il manque un dessin). Leur somme vaut `_absent_nocut_px`.
    autoport_proof::publish((base + "_absent_nocut_match_px").c_str(),
                            g_fam_absent_nocut_match[f]);
    autoport_proof::publish((base + "_absent_nocut_off_px").c_str(), g_fam_absent_nocut_off[f]);
    // Les px d'« absent » separes : bord de silhouette contre trou franc (un correctif de
    // dessin ne peut retirer que les seconds), et `pl` exactement nul contre `pl` dans les 16
    // premiers quanta (geometrie lointaine que le seuil `1e-6f` mislibelle).
    autoport_proof::publish((base + "_absent_edge_px").c_str(), g_fam_absent_edge[f]);
    autoport_proof::publish((base + "_absent_inner_px").c_str(), g_fam_absent_inner[f]);
    autoport_proof::publish((base + "_absent_zero_px").c_str(), g_fam_absent_zero[f]);
    autoport_proof::publish((base + "_absent_farq_px").c_str(), g_fam_absent_farq[f]);
  }
  // (terme 3) Le compte d'images ou le troisieme instantane a ete relu, et son TEMOIN : les
  // pixels ou le bras sans decoupe porte une profondeur que le bras livre n'a pas. A zero,
  // tous les `_absent_nocut_px` ci-dessus sont muets, pas innocents.
  autoport_proof::publish("ao_geom_nocut_frames", g_geom_nocut_frames);
  autoport_proof::publish("ao_geom_nocut_extra_px", g_geom_nocut_extra_px);
  // (terme 3) L'ANCRAGE DU RECENSEMENT, VERIFIABLE. Les six ticks VOULUS, les six ticks
  // RETENUS, et combien sont tombes pile. Deux courses du meme binaire doivent publier les
  // memes six ticks ; si elles n'y arrivent pas, c'est ici que ca se lit — pas dans un ecart
  // inexplique du terme 3.
  autoport_proof::publish("ao_geom_tick_expected", (uint64_t)kGeomTicks);
  autoport_proof::publish("ao_geom_tick_start", (uint64_t)kGeomTickStart);
  autoport_proof::publish("ao_geom_tick_stride", (uint64_t)kGeomTickStride);
  autoport_proof::publish("ao_geom_tick_armed", (uint64_t)g_geom_tick_next);
  autoport_proof::publish("ao_geom_tick_exact", g_geom_tick_exact);
  autoport_proof::publish("ao_geom_tick_last_frame", g_geom_tick_last_frame);
  autoport_proof::publish("ao_geom_tick_deadline_frame", 2000ull);
  for (int i = 0; i < kGeomTicks; i++) {
    autoport_proof::publish(("ao_geom_tick_" + std::to_string(i)).c_str(),
                            (uint64_t)(g_geom_tick_seen[i] < 0 ? 0 : g_geom_tick_seen[i]));
  }
  // ── LES DEUX CLES DE VENT, ET POURQUOI L'UNE CHANGE DE NOM ──────────────────────────────
  // Jusqu'au 2026-09-14 ces deux compteurs se publiaient sous `ao_sway_gap_px` /
  // `ao_sway_gap_world_px`. Ils ne mesurent PAS un ecart de prepasse a la scene : ils comptent
  // les pixels que le deplacement de sommet a BOUGES entre le bras livre et le bras desarme.
  // C'est le TEMOIN D'ARMEMENT du correctif — a zero, tout le reste de la mesure serait vide de
  // sens — et il MONTE quand le correctif marche mieux. Le contrat de la porte, lui, nomme
  // `ao_sway_gap_px` « prepasse contre scene sous vent, shrub ET TIE, `ao_geom_tie_absent_px`
  // compte dedans » : une grandeur qui doit TOMBER a zero. Deux grandeurs opposees sous un seul
  // nom : le temoin prend donc son vrai nom, et `ao_sway_gap_px` publie ce que la porte lit.
  autoport_proof::publish("ao_sway_moved_px", g_sway_gap_px);
  autoport_proof::publish("ao_sway_moved_world_px", g_sway_gap_world_px);
  // LA GRANDEUR DE LA PORTE (terme 3) : sur les deux familles qui plient — shrub et TIE — les
  // pixels dont la prepasse porte une AUTRE geometrie que la scene (`_gap64`) ou n'en porte
  // AUCUNE (`_absent`). Mesuree brise ALLUMEE (`ao_sway_wind_on`).
  // LA VALEUR DE LA PORTE EST INCHANGEE PAR LE DECOUPAGE : `kSwayFams` reunit shrub et les QUATRE
  // sous-chemins TIE (statique, base d'envmap, second draw d'envmap, vent), qui portaient tous
  // la valeur `kFamTie` avant que `proof_stencil_family` ne les separe. Seules les
  // SOUS-POPULATIONS sont nommees ;
  // la somme, elle, couvre exactement la meme geometrie qu'a l'essai 11.
  uint64_t sway_gap = 0, sway_gap_legacy = 0, sway_pop = 0;
  for (const int f : kSwayFams) {
    sway_gap += g_fam_gap64[f] + g_fam_absent[f];
    sway_gap_legacy += g_fam_gap64_legacy[f];
    sway_pop += g_fam_cover[f];
  }
  autoport_proof::publish("ao_sway_gap_px", sway_gap);
  autoport_proof::publish("ao_sway_gap_pop_px", sway_pop);
  autoport_proof::publish("ao_sway_gap_legacy_px", sway_gap_legacy);
  autoport_proof::publish("ao_sway_wind_on", foliage_wind::enabled() ? 1 : 0);
  autoport_proof::publish("ao_wind_pre_calls", g_wind_pre_calls);
  autoport_proof::publish("ao_wind_pre_inds", g_wind_pre_inds);
  // (A3) LE FILTRE DE VISIBILITE RETIRE DU CHEMIN DE PROFONDEUR, CHIFFRE. `_prepass` = les
  // groupes d'instances que la prepasse dessine maintenant ; `_visgated` = ceux que l'ancien
  // filtre `tree.vis_temp` (Tie3.cpp:2492, rempli au bucket 9, APRES la prepasse du bucket 6)
  // aurait laisses passer. Le second DOIT etre strictement inferieur au premier : egaux, le
  // changement n'a rien change et il faut le dire au lieu de le supposer.
  autoport_proof::publish("ao_tie_wind_groups_prepass", g_tie_wind_groups_pre);
  // ── LES QUATRE POPULATIONS D'« ABSENT », ET POURQUOI ELLES SONT DANS LA BOUCLE ──────────
  // Bord de silhouette contre trou franc (un correctif de dessin ne peut retirer que les
  // seconds), et `pl` exactement nul contre `pl` dans les 16 premiers quanta. Elles etaient
  // ecrites a la main famille par famille : une sous-famille ajoutee restait muette, et une
  // premiere version avait ecrit shrub et tfrag a l'envers en se fiant a un commentaire. Elles
  // se publient maintenant dans la boucle `for (int f = 1; f < kFamCount; f++)` ci-dessus, sous
  // `ao_geom_<famille>_absent_edge_px` / `_inner_px` / `_zero_px` / `_farq_px`.
  // Le test d'« absent » est `pl <= 1e-6f`, soit les 16,8 PREMIERS QUANTA de la profondeur
  // 24 bits — et la convention PS2 est inversee : 0 = le plus LOIN. Une geometrie TIE lointaine
  // dont la prepasse ecrit bien une profondeur, mais dans ces 16 quanta, serait comptee
  // « absente » alors qu'elle est DESSINEE ; `_zero_px` contre `_farq_px` separe les deux.
  // `ao_sway_gap_px`, le terme 3 de la porte, ne change PAS de definition.
  // LES TROIS AGREGATS DE TIE, PUBLIES EXPLICITEMENT : l'ancienne cle `ao_geom_tie_absent_px` a
  // CHANGE DE SENS (elle ne compte plus que le TIE statique). Ces trois-la portent ce qu'elle
  // portait avant le decoupage, pour que le changement se lise au lieu de se deviner.
  autoport_proof::publish("ao_geom_tie_all_absent_px",
                          g_fam_absent[kFamTie] + g_fam_absent[kFamTieEnv] +
                              g_fam_absent[kFamTieEnv2] + g_fam_absent[kFamTieWind]);
  autoport_proof::publish("ao_geom_tie_all_gap64_px",
                          g_fam_gap64[kFamTie] + g_fam_gap64[kFamTieEnv] +
                              g_fam_gap64[kFamTieEnv2] + g_fam_gap64[kFamTieWind]);
  autoport_proof::publish("ao_geom_tie_all_cover_px",
                          g_fam_cover[kFamTie] + g_fam_cover[kFamTieEnv] +
                              g_fam_cover[kFamTieEnv2] + g_fam_cover[kFamTieWind]);
  autoport_proof::publish("ao_tie_wind_groups_visgated", g_tie_wind_groups_visgated);
  // (A2) LE FANTOME AU-DESSUS DU VIDE — l'instrument qui voit ce que l'owner voit. Trois fois :
  // « des ombres d'occlusion ambiante qui flottent au dessus des brins d'herbe », « l'occlusion
  // ambiante sur tous les shrubs en dehors de la zone occupee par une texture, donc des ombres
  // qui flottent dans le vide ». `ao_on_alpha_device_px` rendait pourtant 0 : la boucle de
  // `proof_post_opaque` commence par `if (sz <= 1e-6f) continue;` (« pas de profondeur de scene :
  // hors population ») — or un fantome de prepasse pose au-dessus du CIEL est EXACTEMENT un pixel
  // ou `sz <= 1e-6f`. La mesure le jetait. L'estimateur d'AO, lui, lit la profondeur de PREPASSE :
  // la ou celle-ci a ecrit un quad de feuillage que la passe couleur a jete, il voit un occluder
  // plein et pose l'AO sur le fond.
  //   population = les pixels de CIEL de la scene (`ao_phantom_void_pop_px`, LE DENOMINATEUR :
  //                sans lui les deux autres ne se lisent pas) ;
  //   grandeur   = la prepasse y a-t-elle ecrit de la geometrie (`ao_phantom_void_px`) ;
  //   temoin     = le meme compte sur la prepasse d'AVANT cet essai — UV casse et deplacement
  //                desarme (`ao_phantom_void_legacy_px`), dans la MEME image et la MEME scene.
  // CE N'EST PAS un terme de la porte : c'est l'instrument qui repond au verdict (c).
  autoport_proof::publish("ao_phantom_void_px", g_phantom_void_px);
  autoport_proof::publish("ao_phantom_void_legacy_px", g_phantom_void_legacy_px);
  autoport_proof::publish("ao_phantom_void_pop_px", g_phantom_void_pop_px);
  autoport_proof::publish("ao_phantom_void_frames", g_phantom_void_frames);
  // ── LES TROIS TERMES QUE LA PREPASSE REMET A LA SOMME ───────────────────────────────────
  // bit 0 : la fuite sur le direct est mesuree (la sonde a tourne et la population est non
  // nulle) ; bit 1 : l'ecart de prepasse sous vent est mesure ; bit 2 : l'alpha a ete mesure
  // SUR L'APPAREIL. Sur bureau le bit 2 reste a 0 : le contrat exige cette mesure sur
  // l'appareil, et un terme non mesure compte pour un defaut, jamais pour un zero.
  // Bits 8..13 carry completed live-wind acquisitions to the AO verdict;
  // bits 0..2 retain the existing prepass-term coverage contract.
  int mask = (int)(g_static_acquisition_mask << 8);
  if (g_probe_px > 0) {
    mask |= 1;
  }
  // (terme 3) LE TOTAL N'EST COMPARABLE QUE SOUS SON DENOMINATEUR. `sway_gap` cumule toute la
  // course sans jamais se remettre a zero : il ne veut dire quelque chose que si le recensement
  // a tourne sur les SIX ticks prevus et sur une population de shrub non nulle. Cinq images au
  // lieu de six, ou une camera qui ne voit aucun buisson, et le zero serait un vert par
  // INACTION — le terme se declare alors NON MESURE, ce que le contrat compte pour un defaut.
  const bool geom_complete =
      g_geom_tick_anchored ? (g_geom_frames == (uint64_t)kGeomTicks) : (g_geom_frames > 0);
  if (sway_pop > 0 && g_fam_cover[kFamShrub] > 0 && geom_complete) {
    mask |= 2;
  }
#ifdef __ANDROID__
  if (g_alpha_cover_px > 0 && g_witness_px > 0) {
    mask |= 4;
  }
  autoport_proof::publish("ao_on_alpha_device_px", g_on_alpha_px);
  autoport_proof::publish("ao_on_alpha_device_cover_px", g_alpha_cover_px);
  autoport_proof::publish("ao_on_alpha_device_witness_px", g_witness_px);
#endif
  AmbientOcclusionPass::set_prepass_defect_terms(g_leak_px, sway_gap, g_on_alpha_px, mask);
  // ── (n) L'AO N'EST PLUS UN FILTRE FINAL : les faits, remis a la porte ────────────────────
  // `g_hit_px` est le compte de pixels dont l'INDIRECT a reellement recu l'AO (drapeau G de
  // `shade_body` sous `u_ao_proof`), `g_probe_px` son denominateur. Le bras `--off` rend 0 :
  // c'est ce qui empeche ce chiffre d'etre un miroir. Les trois autres viennent de
  // l'interrogatoire du pilote.
  AmbientOcclusionPass::set_arch_terms(g_hit_px, g_probe_px, g_arch_luma_mask_sites,
                                       g_arch_switch_readers, g_arch_programs_queried);
  // ── (a) AUCUN MOTIF VISIBLE ─────────────────────────────────────────────────────────────
  AmbientOcclusionPass::publish_pattern_census();
}

}  // namespace

// ------------------------------------------------------------------------- contributeurs ----
DepthContributor::DepthContributor() {
  g_contributors.push_back(this);
}

DepthContributor::~DepthContributor() {
  g_contributors.erase(std::remove(g_contributors.begin(), g_contributors.end(), this),
                       g_contributors.end());
}

// ------------------------------------------------------------------------------- module ----
void init_shaders(ShaderLibrary& shaders) {
  g_shaders = &shaders;
  g_ao.init_shaders(shaders);
}

AmbientOcclusionPass& ao_pass() {
  return g_ao;
}

void set_output_hint(int w, int h) {
  g_ao.set_output_hint(w, h);
}

void frame_begin(SharedRenderState* rs) {
  ao_tie_contract::frame_begin();
  g_frame++;
  g_static_acquisition_alpha_ok = false;
  g_static_acquisition_witness_ok = false;
  g_static_probe.begin(g_frame);
  if (ao_static_probe::active()) {
    AmbientOcclusionPass::set_static_probe_verdict(g_static_probe.differences,
                                                  g_static_probe.samples,
                                                  g_static_probe.compared);
    AmbientOcclusionPass::publish_pattern_census();
  }
  // lighting-ao-indirect, verdict (f) : la campagne de cout avance ICI, au debut de l'image,
  // avant que quoi que ce soit d'autre ne lise le mode ou le palier d'AO. Elle mesure un ECART
  // debut-d'image a debut-d'image ; une image SONDEE porte deux relectures et une passe de
  // classification, elle n'a rien a faire dans un releve de temps. D'ou l'ordre : la campagne
  // parle d'abord, la sonde se tait pendant qu'elle tient la parole.
  AmbientOcclusionPass::measure_frame_begin(g_frame);
  g_frame_ran = false;
  g_ao_valid = false;
  g_geom_frame = false;
  // `ao_item::measured()` (et non `feature_is(kItemId)`) : le ticket REMPLACE arme encore la
  // mesure, pour qu'une course relancee sur l'ancien nom ne rende pas une preuve muette.
  const bool probe_base =
      (ao_item::measured() || autoport_proof::feature_is("ao-prepass-tie-alpha")) &&
      !AmbientOcclusionPass::measure_timing_active();
  const uint64_t probe_slot = g_frame % kProbeEvery;
  g_probe_frame = probe_base && probe_slot == 0;
  // La phase 0 redimensionne la chaine d'AO vers le palier de l'etat : la phase 1 la trouve
  // donc DEJA chaude, et la paire jugee (1, 2) ne porte aucun effet de premiere image.
  g_probe_pair_phase = (probe_base && probe_slot <= 2) ? (int)probe_slot : -1;
  if (ao_static_probe::requested()) {
    g_probe_pair_phase = g_static_probe.phase <= 2 ? g_static_probe.phase : -1;
    g_probe_frame = g_static_probe.phase == 3;
  }
  // ── LES SIX ETATS TEMOIN, APRES LA SONDE ────────────────────────────────────────────────
  // Ils ne se declenchent QUE hors de la fenetre de la sonde (`phase < 0`) : elle a fini son
  // office a 1353, la fenetre temoin ouvre a 1380. L'image LOURDE (`g_probe_frame`) reste
  // eteinte : les termes 1, 3 et 4 gardent la population de la sonde, au texel pres.
  // Le garde-fou de tick est celui de la sonde : un tick logique relu par deux images de rendu
  // ne doit accumuler la bande QU'UNE fois, sinon `ao_contact_pop_*` double sans qu'un shader
  // ait bouge.
  g_census_witness = false;
  g_census_witness_state = -1;
  if (ao_static_probe::active() && g_static_probe.phase < 0) {
    const int64_t lf = ao_static_probe::logic_frame();
    const int64_t off = lf - kWitnessStart;
    if (lf >= kWitnessStart && off < ao_static_probe::kStates * ao_static_probe::kStride &&
        off % ao_static_probe::kStride <= 2 && lf != g_census_witness_last_tick) {
      g_census_witness_last_tick = lf;
      g_census_witness = true;
      g_census_witness_state = (int)(off / ao_static_probe::kStride);
      g_probe_pair_phase = (int)(off % ao_static_probe::kStride);
    }
  }
  // (terme 3) LE RECENSEMENT GEOMETRIQUE EST DU SUR SON TICK, pas sur un multiple d'images
  // rendues. Le premier passage dont le tick logique a ATTEINT l'echeance l'arme, une fois, et
  // force l'image lourde : les trois relectures pleine resolution dont le recensement a besoin
  // (couleur/stencil, profondeur de prepasse, profondeur de scene) vivent toutes sous
  // `g_probe_frame`. Le tick retenu est note tel quel — si le rendu a saute l'echeance, le
  // chiffre publie le dit au lieu de faire semblant.
  // L'ancrage par tick ne vaut QUE hors sonde deterministe : quand la sonde tourne (les deux
  // items enfants), c'est ELLE qui choisit les images lourdes, et lui en ajouter deplacerait ses
  // propres ticks. Ces courses-la gardent l'ancien tirage, ligne pour ligne.
  g_geom_tick_anchored = probe_base && !ao_static_probe::active();
  g_geom_due = false;
  // JAMAIS A L'INTERIEUR D'UNE TRIADE DU RECENSEMENT DE MOTIF. Les phases 0, 1, 2 d'un bloc
  // partagent un etat, et c'est `g_probe_seq` qui le porte : forcer une image lourde entre la
  // phase 1 et la phase 2 incrementerait le compteur au milieu, et la paire jugee (1, 2)
  // comparerait deux paliers differents — les termes 2, 6 et 8 rougiraient sans qu'aucun shader
  // n'ait bouge. L'echeance est en `>=` : differer d'une ou deux images ne la perd pas, et
  // `ao_geom_tick_<i>` publie le tick REELLEMENT retenu.
  if (g_geom_tick_anchored && g_probe_pair_phase < 0 && g_geom_tick_next < kGeomTicks) {
    const int64_t lf = ao_static_probe::logic_frame();
    const int64_t due = kGeomTickStart + (int64_t)g_geom_tick_next * kGeomTickStride;
    if (lf >= due && lf != g_geom_tick_last) {
      g_geom_tick_last = lf;
      g_geom_tick_seen[g_geom_tick_next] = lf;
      g_geom_tick_last_frame = g_frame;
      if (lf == due) {
        g_geom_tick_exact++;
      }
      g_geom_tick_next++;
      g_geom_due = true;
      g_probe_frame = true;
    }
  }
  if (g_probe_frame) {
    g_probe_seq++;
  }
  if (!g_geom_tick_anchored && g_probe_frame && (g_probe_seq % 6) == 0) {
    g_geom_due = true;  // ancien tirage, conserve pour les courses sous sonde deterministe
  }
  // The alpha comparison accompanies the existing geometry snapshot, before any fix.
  ao_tie_alpha_probe::begin_frame(g_probe_frame && (g_probe_seq % 6) == 0,
                                  rs ? rs->render_fb_w : 0, rs ? rs->render_fb_h : 0);
}

bool static_probe_wind_disabled() {
  // Le bras temoin mesure la MEME scene que le bras livre ou rien n'est comparable : le vent
  // reste coupe pendant ses six etats, exactement comme pendant les phases de la sonde.
  //
  // essai 16 : ET PENDANT LA TRIADE DU RECENSEMENT, MEME HORS SONDE. Les deux clauses au-dessus
  // exigent toutes deux `ao_static_probe::active()` (`g_census_witness` n'est arme que sous elle,
  // ligne 1280), et `requested()` ne nomme que les deux items ENFANTS
  // (`ao_static_probe.h:30-32`). Dans la course de l'item PARENT cette fonction rendait donc
  // FAUX a chaque image : le terme 5 etait mesure VENT ALLUME alors que le contrat (k) dit
  // « camera immobile, scene immobile, vent COUPE pour la mesure ». Le zero de l'essai 14 etait
  // un accident — la prepasse ne suivait pas encore le vent, l'AO ne POUVAIT pas bouger avec
  // lui. L'essai 15 l'a fait suivre (3c51ca3c9f) et les 4 texels sont apparus : entre les
  // phases 1 et 2 d'une triade le feuillage se deplace d'une fraction de tick, la profondeur
  // de prepasse y varie SOUS les 4 quanta de `kSameGeom`, le garde ne marque donc pas ces
  // voisinages, et le jitter d'AO qui y subsiste est compte. Ce n'est pas le jeu qui bouge,
  // c'est la premisse qui n'etait pas etablie.
  // `g_probe_pair_phase >= 0` n'est vrai que sous `probe_base` (ligne 1258-1266), c'est-a-dire
  // sous l'armement de la preuve : le build du joueur ne voit rien de cette coupure.
  return (ao_static_probe::active() && g_static_probe.phase >= 0 && g_static_probe.phase <= 2) ||
         g_census_witness || g_probe_pair_phase >= 0;
}

// ── L'HORLOGE DU VENT, EPINGLEE SUR LE TICK LOGIQUE PENDANT LA PREUVE DE CET ITEM ───────────
// essai 15. `foliage_wind::clock_seconds` (foliage_wind.cpp:434-460) n'epingle la phase de la
// brise sur le tick logique que si CETTE fonction rend une valeur ; sinon elle retombe sur
// `refset::render_logic_frame()` — absent, `OG_REFSET` n'est pas pose dans la preuve, la cle
// `refset_wind_clock_pinned` ne figure dans AUCUNE des deux preuves — puis sur un accumulateur
// de `steady_clock`. La phase de la brise dependait donc de la MONTRE : deux courses du MEME
// binaire, a la MEME image, pliaient les buissons differemment, et le terme 3 de la porte a
// rendu 57, 33 puis 94 le meme jour sur le meme appareil. `requested()` ne couvre que les deux
// items enfants ; l'armement de CET item-ci est ajoute, et lui seul — l'armer par
// `ao_static_probe::requested()` rendrait `active()` vrai et ferait retomber le recensement a
// SIX etats alors qu'il en a DIX-HUIT. Hors preuve (`armed_for` faux) le joueur garde le chemin
// d'avant, ligne pour ligne.
int64_t static_probe_logic_frame() {
  if (ao_static_probe::requested() || autoport_proof::armed_for(kItemId)) {
    return ao_static_probe::logic_frame();
  }
  return -1;
}

// ── LES PLAGES DE LA PREPASSE ─────────────────────────────────────────────────────────────────
DepthRange make_depth_range(uint32_t gl_tex,
                            float alpha_min,
                            uint32_t first,
                            uint32_t count,
                            uint8_t tex_mode) {
  DepthRange r;
  r.first = first;
  r.count = count;
  r.tex_mode = tex_mode;
  if (gl_tex != 0 && alpha_min > 0.f) {
    r.tex = gl_tex;
    // LA BORNE, ET ELLE EST PROUVEE, PAS SUPPOSEE. La passe principale jette quand
    // `fragment_color.a * T0.a < alpha_min`, avec `fragment_color.a = tod.a * 4`
    // (tfrag3.vert:92-95, shrub.vert:112-119) ; la prepasse n'a pas l'indice de temps-du-jour.
    // Mais l'alpha de la LUT est SATURE A 128, pas a 255, la ou elle est produite :
    // `o[3] = std::min(128, temp[color][3] >> 6)` (background_common.cpp, interp_time_of_day_slow)
    // et le registre `sat = _mm_set_epi16(128, 255, 255, 255, ...)` de la version SIMD.
    // Donc tod.a <= 128/255 et `fragment_color.a <= 4 * 128/255 = 2.008` : le seuil conservateur
    // le plus SERRE qui existe est alpha_min / 2.008. Le prendre a 4 laissait 6x plus de pixels
    // dans la bande ambigue qu'il n'en retirait (mesure du 12/09 : 49 081 contre 7 824).
    // Ce qui reste dans [alpha_min/2.008, alpha_min) est compte : `ao_alpha_fringe_px`.
    r.cut_aref = alpha_min * (255.f / 512.f);
    r.cut_amb = alpha_min;
  }
  return r;
}

uint64_t draw_depth_range(unsigned gl_mode, const DepthRange& r) {
  if (r.count == 0 || !g_shaders) {
    return 0;
  }
  const GLuint id = (*g_shaders)[ShaderId::PREPASS_WORLD].id();
  // Le bras de CONTROLE desarme la decoupe SANS toucher a rien d'autre : meme geometrie, meme
  // programme, meme ordre, meme plages. C'est la seule difference entre les deux bras.
  const float aref = g_cut_armed ? r.cut_aref : 0.f;
  g_total_ranges++;
  if (r.cut_aref > 0.f) {
    g_cut_ranges++;
  }
  if (aref != g_last_aref) {
    glUniform1f(glu::loc(id, "u_cut_aref"), aref);
    g_last_aref = aref;
  }
  if (r.cut_amb != g_last_amb) {
    glUniform1f(glu::loc(id, "u_cut_amb"), r.cut_amb);
    g_last_amb = r.cut_amb;
  }
  // Un sampler declare et non lie rend un comportement indefini sur Adreno : la plage sans test
  // lie quand meme le 1x1 blanc.
  const GLuint want_tex = (r.cut_aref > 0.f && r.tex != 0) ? (GLuint)r.tex : g_white_tex;
  if (want_tex != g_last_tex) {
    glActiveTexture(GL_TEXTURE0);
    glBindTexture(GL_TEXTURE_2D, want_tex);
    g_last_tex = want_tex;
  }
  // (terme 3) L'ETAT D'ECHANTILLONNAGE EST POSE, PLUS HERITE — et ce qu'il valait AVANT est
  // compte. L'ordre n'est pas negociable : on RELIT l'objet, puis on ecrit. Relire apres, ce
  // serait relire sa propre ecriture et publier un zero qui ne mesure rien.
  // Rien de tout cela ne touche le 1x1 blanc (il n'a pas de mip et aucun draw ne le partage) ni
  // les plages sans test d'alpha (aucun texel n'est lu, `ta` vaut 1.0 par le shader).
  if (want_tex != g_white_tex && want_tex != 0) {
    if (r.tex_mode == 0xff) {
      g_texstate_unknown++;
    } else if (want_tex != g_last_state_tex || (uint16_t)r.tex_mode != g_last_state_mode) {
      int p4[4];
      prepass_tex_params(r.tex_mode, /*mipmap=*/true, p4);
      if (g_probe_frame) {
        static const GLenum kPname[4] = {GL_TEXTURE_WRAP_S, GL_TEXTURE_WRAP_T,
                                         GL_TEXTURE_MIN_FILTER, GL_TEXTURE_MAG_FILTER};
        bool bad = false;
        for (int k = 0; k < 4; k++) {
          GLint got = 0;
          glGetTexParameteriv(GL_TEXTURE_2D, kPname[k], &got);
          if ((int)got != p4[k]) {
            g_texstate_bad_p[k]++;
            bad = true;
          }
        }
        g_texstate_checked++;
        if (bad) {
          g_texstate_bad++;
        }
      }
      glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, p4[0]);
      glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, p4[1]);
      glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, p4[2]);
      glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, p4[3]);
      g_last_state_tex = want_tex;
      g_last_state_mode = (uint16_t)r.tex_mode;
    }
  }
  lighting_census::note_world_draw(lighting_census::Kind::DepthOnly);
  ao_tie_alpha_probe::before_pre_draw(id, r.tie_probe_id);
  glDrawElements((GLenum)gl_mode, (GLsizei)r.count, GL_UNSIGNED_INT,
                 (void*)((size_t)r.first * sizeof(uint32_t)));
  return r.count;
}

// ── (i) LE DEPLACEMENT DE SOMMET, REJOUE ──────────────────────────────────────────────────────
// Refus owner du 2026-09-13 : « les shrubs qui bougent avec le vent... Leur AO reste a la place
// initiale ». `sway_reset` remet TOUT le bloc a l'etat inerte et repose les valeurs GENERIQUES des
// attributs 7/8/9/10 — le MEME double verrou que `first_tfrag_draw_setup`
// (background_common.cpp:1612-1628), que la prepasse n'appelle jamais : un uniforme a 0 ET un poids
// de sommet a 0. Un seul des deux suffirait ; deux tiennent meme si le compilateur GLSL retire
// l'uniforme (loc -1) ou si un VAO n'active pas l'attribut.
static void sway_reset(GLuint id, int kind) {
  glUniform1i(glu::loc(id, "u_pre_sway_on"), g_sway_off ? 0 : 1);
  glUniform1i(glu::loc(id, "u_pre_kind"), kind);
  // (A1) L'ECHELLE DE LA COORDONNEE DE TEXTURE, POSEE AVEC LA FAMILLE ET JAMAIS SANS ELLE.
  // shrub.vert:125-126 divise `tex_coord.xy` par 4096 ; tfrag3.vert:95 (partage par le TFRAG et
  // le TIE) ne divise pas. La prepasse sortait la coordonnee BRUTE pour les trois familles :
  // l'alpha-test de prepass_world.frag:35 echantillonnait `fract(uv*4096)` sur les draws de
  // SHRUB, c'est-a-dire un texel ARBITRAIRE — le test ne retirait pas ce que la passe couleur
  // retire, il retirait au hasard.
  // LE TEMOIN RESTE L'ANCIENNE PREPASSE : dans le rejeu « deplacement desarme » (g_sway_off, qui
  // produit `g_pre_depth_legacy`) l'echelle vaut 1 meme pour le shrub, pour que l'ecart entre les
  // deux bras soit mesure dans la MEME image et la MEME scene.
  glUniform1f(glu::loc(id, "u_pre_uv_scale"),
              (kind == 1 && !g_sway_off) ? (1.0f / 4096.0f) : 1.0f);
  // (A4) La projection etie n'est armee QUE par les plages `prepass_ranges_env` du TIE, qui la
  // posent plage par plage. Toute annonce de famille la desarme : un uniforme laisse a 1 par un
  // voisin ferait projeter du TFRAG avec l'arithmetique de l'envmap.
  glUniform1i(glu::loc(id, "u_pre_etie"), 0);
  glUniform1f(glu::loc(id, "u_tie_sway_amp"), 0.0f);
  glUniform1f(glu::loc(id, "u_tie_sway_time"), 0.0f);
  glUniform2f(glu::loc(id, "u_tie_sway_dir"), 0.7071f, 0.7071f);
  glUniform1f(glu::loc(id, "u_tie_sway_flutter"), 0.0f);
  glUniform1i(glu::loc(id, "u_tie_contact_on"), 0);
  glUniform1i(glu::loc(id, "u_shrub_native_on"), 0);
  glUniform1i(glu::loc(id, "u_shrub_contact_on"), 0);
  glVertexAttrib4f(7, 0.f, 0.f, 0.f, 1.f);
  glVertexAttrib4f(8, 0.f, 0.f, 0.f, 1.f);
  glVertexAttribI4ui(9, 0u, 0u, 0u, 0u);
  glVertexAttribI4ui(10, 0u, 0u, 0u, 0u);
}

void sway_none() {
  if (!g_shaders) {
    return;
  }
  sway_reset((*g_shaders)[ShaderId::PREPASS_WORLD].id(), 0);
}

void sway_tie(uint64_t frame_idx, unsigned contact_tex) {
  if (!g_shaders) {
    return;
  }
  const GLuint id = (*g_shaders)[ShaderId::PREPASS_WORLD].id();
  sway_reset(id, 2);
  // La MEME fonction que la passe couleur (Tie3.cpp:1091-1093) : une seule loi, une seule
  // amplitude, une seule horloge. Le poids par sommet vaut 0 sur tout ce qui n'est pas vegetal,
  // donc pousser l'amplitude pour tout l'arbre ne fait bouger que ce qui bouge a l'ecran.
  foliage_wind::push_uniforms(id, frame_idx, "prepass-tie");
  // Tie3.cpp:1066-1088 (`push_tie_contact`), mot pour mot : sans texture, ou option eteinte,
  // l'uniforme reste a 0 et le bloc du chunk est saute.
  const bool on = contact_tex != 0 && foliage_wind::enabled();
  glUniform1i(glu::loc(id, "u_tie_contact_on"), on ? 1 : 0);
  if (on) {
    grass_occ::push_contact_uniforms(id, true);
    glUniform1i(glu::loc(id, "u_tie_contact_tex"), 18);
    glActiveTexture(GL_TEXTURE18);
    glBindTexture(GL_TEXTURE_2D, (GLuint)contact_tex);
    glActiveTexture(GL_TEXTURE0);
  }
}

void sway_shrub(uint64_t frame_idx, unsigned wind_tex, bool native_on, bool contact_on) {
  if (!g_shaders) {
    return;
  }
  const GLuint id = (*g_shaders)[ShaderId::PREPASS_WORLD].id();
  sway_reset(id, 1);
  foliage_wind::push_uniforms(id, frame_idx, "prepass-shrub");
  // Shrub.cpp:793-831, mot pour mot : le ressort natif de ND (ligne 0 de tex_T18) et l'ancre de
  // contact (ligne 1) vivent dans la MEME texture, par arbre — d'ou l'appel PAR ARBRE.
  const bool static_wind_off = static_probe_wind_disabled();
  glUniform1i(glu::loc(id, "u_shrub_native_on"), native_on && !static_wind_off ? 1 : 0);
  if (static_wind_off) {
    static uint64_t disabled_draws = 0;
    autoport_proof::publish("ao_probe_native_wind_off_draws", ++disabled_draws);
  }
  glUniform1i(glu::loc(id, "u_shrub_contact_on"), contact_on ? 1 : 0);
  if (contact_on) {
    grass_occ::push_contact_uniforms(id, true);
  }
  if (native_on || contact_on) {
    glActiveTexture(GL_TEXTURE18);
    glBindTexture(GL_TEXTURE_2D, (GLuint)wind_tex);
    glActiveTexture(GL_TEXTURE0);
  }
  glUniform1i(glu::loc(id, "tex_T18"), 18);
}

// lighting-ao-indirect (c)/(g) : la passe « occluder fantome ». Hors d'elle, les contributeurs
// dessinent leurs plages LIVREES.
bool noz_pass_active() {
  return g_noz_pass;
}

unsigned depth_fbo() {
  return (unsigned)g_fbo;
}

// (c)/(g)/(i) L'INSTANTANE D'UNE PROFONDEUR, PARTOUT. `glReadPixels(GL_DEPTH_COMPONENT, GL_FLOAT)`
// n'existe pas en GLES 3.2 et `glGetTexImage` non plus : sur cette texture il rendait un tampon
// ENTIEREMENT NUL sans poser la moindre erreur GL (mesure du 2026-09-13, PrePass.h:113). On
// dessine donc un quad qui RE-ENCODE la profondeur 24 bits en RGBA8, format que `glReadPixels`
// rend sur les deux plateformes. La grandeur ne change pas : c'est le meme entier 24 bits.
//
// ELLE REND L'ETAT GL EXACTEMENT COMME ELLE L'A TROUVE : `pattern_census` l'appelle au milieu
// d'une passe qui a deja pose le sien, et une corruption la n'eleverait aucune erreur GL.
bool export_depth(GLuint depth_tex, int w, int h, std::vector<float>* out) {
  if (!g_shaders || depth_tex == 0 || w <= 0 || h <= 0) {
    return false;
  }
  ao_contact_readback::ExportState archive_state;
  if (!archive_state.errors.empty()) return false;
  ensure_quad();
  ensure_export(w, h);
  if (g_exp_state != 1) {
    return false;
  }
  if (out->size() < (size_t)w * h) {
    out->resize((size_t)w * h);
  }
  if (g_exp_buf.size() < (size_t)w * h * 4) {
    g_exp_buf.resize((size_t)w * h * 4);
  }
  GLint prev_program = 0, prev_draw = 0, prev_read = 0, prev_vp[4] = {0, 0, 0, 0}, prev_vao = 0;
  GLint prev_pack = 4, prev_active = GL_TEXTURE0;
  glGetIntegerv(GL_CURRENT_PROGRAM, &prev_program);
  glGetIntegerv(GL_DRAW_FRAMEBUFFER_BINDING, &prev_draw);
  glGetIntegerv(GL_READ_FRAMEBUFFER_BINDING, &prev_read);
  glGetIntegerv(GL_VIEWPORT, prev_vp);
  glGetIntegerv(GL_VERTEX_ARRAY_BINDING, &prev_vao);
  glGetIntegerv(GL_PACK_ALIGNMENT, &prev_pack);
  glGetIntegerv(GL_ACTIVE_TEXTURE, &prev_active);
  GLboolean prev_depth_mask = GL_TRUE;
  GLboolean prev_color_mask[4] = {GL_TRUE, GL_TRUE, GL_TRUE, GL_TRUE};
  GLint prev_tex0 = 0, prev_tex1 = 0;
  glGetBooleanv(GL_DEPTH_WRITEMASK, &prev_depth_mask);
  glGetBooleanv(GL_COLOR_WRITEMASK, prev_color_mask);
  glActiveTexture(GL_TEXTURE0);
  glGetIntegerv(GL_TEXTURE_BINDING_2D, &prev_tex0);
  glActiveTexture(GL_TEXTURE1);
  glGetIntegerv(GL_TEXTURE_BINDING_2D, &prev_tex1);
  glActiveTexture((GLenum)prev_active);
  const GLboolean prev_depth = glIsEnabled(GL_DEPTH_TEST);
  const GLboolean prev_stencil = glIsEnabled(GL_STENCIL_TEST);
  const GLboolean prev_blend = glIsEnabled(GL_BLEND);
  const GLboolean prev_scissor = glIsEnabled(GL_SCISSOR_TEST);
  const GLboolean prev_cull = glIsEnabled(GL_CULL_FACE);
  if (!archive_state.collect("export-initialize-error")) return false;
  ensure_white();
  (*g_shaders)[ShaderId::AO_PROBE].activate();
  const GLuint id = (*g_shaders)[ShaderId::AO_PROBE].id();
  glBindFramebuffer(GL_FRAMEBUFFER, g_exp_fbo);
  glViewport(0, 0, w, h);
  glDisable(GL_DEPTH_TEST);
  glDisable(GL_STENCIL_TEST);
  glDisable(GL_BLEND);
  glDisable(GL_SCISSOR_TEST);
  glDisable(GL_CULL_FACE);
  glDepthMask(GL_FALSE);
  glColorMask(GL_TRUE, GL_TRUE, GL_TRUE, GL_TRUE);
  // LES DEUX SAMPLERS SONT LIES A CHAQUE FOIS. Le mode est un uniforme, donc le compilateur
  // GLSL garde les deux : un sampler declare, lu dans une branche, et non lie rend un resultat
  // indefini sur Adreno — pas une erreur.
  glActiveTexture(GL_TEXTURE0);
  glBindTexture(GL_TEXTURE_2D, depth_tex);
  glActiveTexture(GL_TEXTURE1);
  glBindTexture(GL_TEXTURE_2D, g_white_tex);
  glUniform1i(glu::loc(id, "u_depth"), 0);
  glUniform1i(glu::loc(id, "u_src"), 1);
  glUniform1i(glu::loc(id, "u_mode"), 1);
  glUniform1f(glu::loc(id, "u_fam"), 0.f);
  glBindVertexArray(g_quad_vao);
  glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
  soft_draw_census::record_arrays("postprocess", 4, GL_TRIANGLE_STRIP);
  glBindVertexArray(0);
  glPixelStorei(GL_PACK_ALIGNMENT, 1);
  glBindFramebuffer(GL_READ_FRAMEBUFFER, g_exp_fbo);
  glReadBuffer(GL_COLOR_ATTACHMENT0);
  glReadPixels(0, 0, w, h, GL_RGBA, GL_UNSIGNED_BYTE, g_exp_buf.data());
  const GLenum err = glGetError();
  glPixelStorei(GL_PACK_ALIGNMENT, prev_pack);
  glActiveTexture(GL_TEXTURE0);
  glBindTexture(GL_TEXTURE_2D, (GLuint)prev_tex0);
  glActiveTexture(GL_TEXTURE1);
  glBindTexture(GL_TEXTURE_2D, (GLuint)prev_tex1);
  glActiveTexture((GLenum)prev_active);
  glDepthMask(prev_depth_mask);
  glColorMask(prev_color_mask[0], prev_color_mask[1], prev_color_mask[2], prev_color_mask[3]);
  glBindVertexArray((GLuint)prev_vao);
  glUseProgram((GLuint)prev_program);
  glBindFramebuffer(GL_DRAW_FRAMEBUFFER, (GLuint)prev_draw);
  glBindFramebuffer(GL_READ_FRAMEBUFFER, (GLuint)prev_read);
  glViewport(prev_vp[0], prev_vp[1], prev_vp[2], prev_vp[3]);
  if (prev_depth) {
    glEnable(GL_DEPTH_TEST);
  }
  if (prev_stencil) {
    glEnable(GL_STENCIL_TEST);
  }
  if (prev_blend) {
    glEnable(GL_BLEND);
  }
  if (prev_scissor) {
    glEnable(GL_SCISSOR_TEST);
  }
  if (prev_cull) {
    glEnable(GL_CULL_FACE);
  }
  if (err != GL_NO_ERROR) {
    lg::error("[lighting-ao-indirect] export de profondeur refuse (gl=0x{:x})", (unsigned)err);
    g_exp_state = -1;
    return false;
  }
  const float inv = 1.0f / 16777215.0f;
  for (size_t i = 0; i < (size_t)w * h; i++) {
    const uint32_t v = ((uint32_t)g_exp_buf[i * 4] << 16) |
                       ((uint32_t)g_exp_buf[i * 4 + 1] << 8) | (uint32_t)g_exp_buf[i * 4 + 2];
    (*out)[i] = (float)v * inv;
  }
  return archive_state.restore();
}

void note_noz_range(uint32_t inds) {
  g_noz_ranges++;
  g_noz_inds += inds;
}

void note_wind_group(bool vis_gated_would_draw) {
  g_tie_wind_groups_pre++;
  if (vis_gated_would_draw) {
    g_tie_wind_groups_visgated++;
  }
}

GLuint world_program() {
  return g_shaders ? (*g_shaders)[ShaderId::PREPASS_WORLD].id() : 0;
}

const GoalBackgroundCameraData* prepass_cam() {
  return g_cur_cam;
}

void etie_mode(int on) {
  const GLuint id = world_program();
  if (id == 0) {
    return;
  }
  glUniform1i(glu::loc(id, "u_pre_etie"), on ? 1 : 0);
}

void note_wind_prepass(uint32_t inds) {
  g_wind_pre_calls++;
  g_wind_pre_inds += inds;
}

bool screen_ao_active() {
  return g_ao_valid && g_ao.texture() != 0;
}

GLuint screen_ao_texture() {
  return screen_ao_active() ? g_ao.texture() : 0;
}

void on_first_camera(SharedRenderState* rs, const GoalBackgroundCameraData& cam) {
  gl_query_census::Armed _ap("prepass-first-camera");
  if (g_frame_ran) {
    return;
  }
  g_frame_ran = true;
  g_last_indices = 0;
  g_last_levels = 0;
  if (!rs || rs->version != GameVersion::Jak1 || !g_shaders) {
    return;
  }
  if (ao_tie_alpha_probe::color_frame()) return;
  if (AmbientOcclusionPass::effective_mode() == 0) {
    return;  // AO eteinte : ni prepasse ni estimation — OFF == absence
  }
  // Le bras `--off` du harnais : l'item entier s'efface (prepasse comprise), hits reste a 0.
  if (!autoport_proof::armed_for(kItemId)) {
    return;
  }
  const int w = rs->render_fb_w;
  const int h = rs->render_fb_h;
  if (w <= 0 || h <= 0) {
    return;
  }

  // ── LE BRAS LIVRE ───────────────────────────────────────────────────────────────────────────
  // La prepasse avec la decoupe d'alpha ARMEE : c'est CETTE profondeur que l'estimateur d'AO
  // consomme, donc c'est elle que le detecteur juge.
  int levels = 0;
  uint64_t on = 0, cover = 0, fringe = 0;
  const uint64_t total = run_prepass(rs, cam, w, h, /*armed=*/true, g_probe_frame, &on, &cover,
                                     &fringe, &levels);
  g_last_indices = total;
  g_last_levels = levels;
  if (ao_static_probe::active() && g_static_probe.phase == 3) {
    g_static_acquisition_alpha_ok = g_class_state == 1 && cover > 0;
  }
  if (g_probe_frame) {
    g_alpha_frames++;
    if (ao_static_probe::active()) {
      autoport_proof::publish("ao_probe_wind_on_acquisition_frames", g_alpha_frames);
      const std::string key = "ao_probe_wind_on_acquisition_tick_" +
                              std::to_string(g_static_probe.state);
      autoport_proof::publish(key.c_str(), ao_static_probe::logic_frame());
    }
    g_on_alpha_px += on;
    g_alpha_cover_px += cover;
    g_alpha_fringe_px += fringe;
#ifdef __ANDROID__
    // ── LA PRISE DE L'ITEM, SUR L'APPAREIL ────────────────────────────────────────────────
    // `validators/generic.sh` lit `proof_feature_own_hits` : un site compile qui ne tire
    // jamais est un defaut, pas un detail. Sur bureau la prise est notee par la SONDE, avec le
    // sens exact du livrable (« pixels dont l'indirect a recu l'AO ») ; la sonde lit le
    // stencil, que GLES ne relit pas. Ici la prise est donc le compte de pixels que la
    // prepasse a GAGNES avec sa decoupe d'alpha armee — le denominateur de `ao_on_alpha_px`,
    // c'est-a-dire le chemin de code de CET item, mesure sur cette image. Le sens n'est pas le
    // meme que sur bureau et le rapport le dit : ce n'est pas le meme instrument.
    autoport_proof::note_hit_for(kItemId, cover);
#endif
    // (c)/(g) LA MESURE AU POINT DE DESSIN. La profondeur LIVREE vient d'etre ecrite et
    // l'estimateur ne l'a pas encore lue : c'est ICI que les quads ECARTES se comparent a elle.
    measure_phantom_occluders(rs, cam, w, h);
  }

  // (a) LE RECENSEMENT DU MOTIF. `AO_FORCE_QUALITY` est fige pour toute la course : les trois
  // paliers ne peuvent etre juges dans la MEME scene qu'en les alternant d'une image sondee a
  // l'autre. Le cout — la chaine d'AO se redimensionne a chaque bascule — ne se paie qu'une
  // image sur soixante, et seulement sous mesure.
  // (e) DIX-HUIT ETATS, PAS TROIS. L'owner a vu le damier « en qualite faible, teste en SSAO »
  // ET « en qualite elevee, teste en GTAO », et il a teste HBAO aussi : un recensement qui ne
  // couvre qu'un estimateur ne repond pas a son verdict. Et une grandeur qui ne RETROUVE pas le
  // defaut sur le regime d'AVANT ne peut pas prouver sa disparition : la moitie haute des etats
  // rallume l'ancrage MONDE du bruit (`u_ao_legacy_noise`), dans la MEME course et sur la MEME
  // scene.
  //   etat = legacy*9 + mode_idx*3 + palier,  mode_idx : 0 = SSAO, 1 = GTAO, 2 = HBAO
  if (g_probe_pair_phase >= 0) {
    const int st = g_census_witness
                       ? g_census_witness_state
                       : (ao_static_probe::active() ? g_static_probe.state
                                                    : (int)(g_probe_seq % 18));
    // `st / 9` ne peut pas porter le temoin quand la sonde donne l'etat : elle n'en a que SIX.
    const int legacy = g_census_witness ? 1 : (st / 9);
    const int st9 = st % 9;
    const int mode = (st9 < 3) ? 1 : (st9 < 6) ? 3 : 2;  // 1 = SSAO, 3 = GTAO, 2 = HBAO
    AmbientOcclusionPass::set_measure_state(mode, st9 % 3, legacy);
    AmbientOcclusionPass::set_census_pair_phase(g_probe_pair_phase);
    // (k) LA PREMISSE DU TERME 5, REMISE AU MODULE QUI JUGE : ce module-ci DECIDE de la coupure,
    // l'autre ne doit pas la deviner. Une paire dont l'une des deux images portait le vent ne
    // mesure pas « scene immobile » : elle sortira du terme au lieu d'y entrer en silence.
    AmbientOcclusionPass::set_census_wind_cut(static_probe_wind_disabled());
    AmbientOcclusionPass::request_pattern_census(true);
  } else {
    AmbientOcclusionPass::set_measure_state(-1, -1, 0);
    AmbientOcclusionPass::set_census_pair_phase(-1);
    AmbientOcclusionPass::set_census_wind_cut(false);
  }

  // L'estimation lit la profondeur de la prepasse et ecrit sa texture R8. Elle sauvegarde et
  // restaure elle-meme tout ce qu'elle touche ; le FBO de rendu est deja re-lie — et il DOIT
  // l'etre, parce que `ao_draws_on_scene` compare ses cibles au FBO qu'elle trouve en entrant.
  g_ao_valid = (total > 0) && g_ao.estimate(rs, g_depth_tex, w, h);
  if (ao_static_probe::active() && g_probe_pair_phase >= 0 && g_ao_valid) {
    g_static_probe.record(AmbientOcclusionPass::static_probe_input_hash());
    AmbientOcclusionPass::set_static_probe_verdict(g_static_probe.differences,
                                                  g_static_probe.samples,
                                                  g_static_probe.compared);
    autoport_proof::publish("ao_probe_wind_disabled",
                            static_probe_wind_disabled() && !foliage_wind::enabled());
    AmbientOcclusionPass::publish_pattern_census();
  }

  // ELLES TOURNENT MAINTENANT SUR L'APPAREIL AUSSI (essai 9) : `read_prepass_depth` passe par
  // `export_depth`, et le terme 3 cesse d'y valoir « non-mesure », c'est-a-dire un defaut nomme.
  // ── (c)/(g)/(i) LES DEUX INSTANTANES DE PROFONDEUR ────────────────────────────────────────
  // L'estimateur vient de consommer la profondeur LIVREE : on la fige, puis on rejoue EXACTEMENT
  // le meme dessin avec le deplacement DESARME — c'est la prepasse de l'essai 6, dans la MEME
  // image et la MEME scene. Les deux se compareront a la profondeur de la SCENE au bucket 30,
  // quand le monde aura ete dessine : c'est la mesure AU POINT DE DESSIN que le verdict (c)
  // reclame. Une image sondee sur six — deux relectures pleine resolution ne se paient pas a
  // chaque sonde — et le compte d'images est publie a cote des populations.
  g_geom_frame = false;
  if (g_geom_due && g_geom_state >= 0) {
    if (read_prepass_depth(w, h, &g_pre_depth)) {
      g_sway_off = true;
      run_prepass(rs, cam, w, h, /*armed=*/true, /*classify=*/false, nullptr, nullptr, nullptr,
                  nullptr);
      g_sway_off = false;
      g_geom_frame = read_prepass_depth(w, h, &g_pre_depth_legacy);
    }
    if (!g_geom_frame) {
      g_geom_state = -1;  // publie tel quel : une relecture refusee se DIT, elle ne rend pas 0
    }
  }

  // ── LE BRAS DE CONTROLE ─────────────────────────────────────────────────────────────────────
  // Le MEME dessin, la decoupe DESARMEE : les texels transparents ecrivent a nouveau de la
  // profondeur, et le MEME detecteur les compte. Sans ce bras, `ao_on_alpha_px = 0` ne se
  // distinguerait pas d'un detecteur casse. Il ecrase la profondeur de la prepasse, ce qui est
  // sans consequence : l'estimation vient de la consommer et personne d'autre ne la lit.
  if (g_probe_frame) {
    uint64_t won = 0, wcover = 0, wfringe = 0;
    run_prepass(rs, cam, w, h, /*armed=*/false, true, &won, &wcover, &wfringe, nullptr);
    if (ao_static_probe::active() && g_static_probe.phase == 3) {
      g_static_acquisition_witness_ok = g_class_state == 1 && wcover > 0 && won > 0;
    }
    // (terme 3) On fige la profondeur de CE bras : meme dessin, meme deplacement de sommet,
    // SEULE la decoupe d'alpha change. Une seule variable separe les deux instantanes.
    if (g_geom_frame) {
      if (read_prepass_depth(w, h, &g_pre_depth_nocut)) {
        g_geom_nocut_frames++;
      } else {
        g_pre_depth_nocut.clear();
      }
    }
    g_witness_px += won;
    g_witness_cover_px += wcover;
  }
}

// ── (n) « L'AO N'EST PLUS UN FILTRE FINAL » : L'INTERROGATOIRE DU PILOTE ────────────────────
// Retour owner du 2026-09-17 : « j'ai toujours comme cette impression que l'AO est juste posee
// par dessus comme un filtre ». SPEC 4.7 condamne nommement le masque `1 - smoothstep(0.45,
// 0.90, luma)` qui protegeait le direct. Prouver qu'il n'est plus la ne se fait PAS par un
// grep : un uniforme declare mais jamais lu est retire par le compilateur GLSL, et un grep du
// texte ne distingue pas les deux. Seul le PILOTE repond — c'est la lecon de
// `gl-uniforms-dead-seven`. On interroge donc chaque programme qui recoit l'AO, une fois, sur
// les quatre noms qu'a portes le masque, ET sur un nom dont on SAIT qu'il est lu (`tex_screen_ao`,
// puisque ce programme vient d'echantillonner l'AO avec) : sans ce controle positif, un zero
// dirait seulement que personne n'a ete interroge.
constexpr const char* kLumaMaskNames[] = {"u_ao_luma_mask", "u_ao_mask", "u_ao_scene",
                                          "tex_ao_scene"};

void arch_interrogate(GLuint program) {
  if (program == 0 || !autoport_proof::armed_for(kItemId)) {
    return;
  }
  for (GLuint p : g_arch_seen_programs) {
    if (p == program) {
      return;  // une fois par programme lie, pas une fois par dessin
    }
  }
  g_arch_seen_programs.push_back(program);
  g_arch_programs_queried++;
  // `glGetUniformLocation` en direct, pas `glu::loc` : cet interrogatoire ne doit pas entrer
  // dans le compteur de recherches d'uniformes par image (`uniform_lookups_per_frame`, acquis
  // de SPEC 4.3, qui vaut 0 en regime etabli). Il ne tire qu'une fois par programme.
  if (glGetUniformLocation(program, "tex_screen_ao") >= 0) {
    g_arch_switch_readers++;  // LE CONTROLE POSITIF
  }
  for (const char* name : kLumaMaskNames) {
    if (glGetUniformLocation(program, name) >= 0) {
      g_arch_luma_mask_sites++;
    }
  }
}

void bind_screen_ao(GLuint program, SharedRenderState* rs) {
  arch_interrogate(program);
  const bool on = screen_ao_active() && !ao_tie_alpha_probe::color_frame();
  const int w = rs ? rs->render_fb_w : 0;
  const int h = rs ? rs->render_fb_h : 0;
  ensure_white();
  glUniform1i(glu::loc(program, "tex_screen_ao"), 8);
  // 0 = pas d'AO, 1 = appliquee a l'indirect, 2 = vue de debug (AO_DEBUG / debug.opengoal.ao.debug)
  const int mode = !on ? 0 : (AmbientOcclusionPass::effective_debug() != 0 ? 2 : 1);
  glUniform1i(glu::loc(program, "u_screen_ao_on"), mode);
  glUniform2f(glu::loc(program, "u_screen_ao_inv_size"), w > 0 ? 1.0f / (float)w : 0.f,
              h > 0 ? 1.0f / (float)h : 0.f);
  glUniform1i(glu::loc(program, "u_ao_proof"),
              g_probe_frame && !ao_tie_alpha_probe::color_frame() ? 1 : 0);
  ao_tie_alpha_probe::note_color_binding(!on,
      !(g_probe_frame && !ao_tie_alpha_probe::color_frame()));
  glActiveTexture(GL_TEXTURE8);
  glBindTexture(GL_TEXTURE_2D, on ? g_ao.texture() : g_white_tex);
  glActiveTexture(GL_TEXTURE0);
}

// ------------------------------------------------------------------------------- preuve ----
void proof_before_bucket(int bucket_id) {
  if (!g_probe_frame || bucket_id > 30) {
    return;
  }
  // Les buckets monde ecrivent LEUR FAMILLE (1 = TFRAG, 2 = TIE, 3 = SHRUB), tout le reste
  // (ciel, ocean, merc, generic) ecrit 0 : au bucket 30, un stencil non nul designe exactement
  // les pixels dont la couleur finale vient d'un programme qui passe par shade(), et sa VALEUR
  // dit de quel chemin. Aucun renderer d'avant le bucket 30 ne touche au stencil.
  glEnable(GL_STENCIL_TEST);
  glStencilMask(0xFF);
  glStencilFunc(GL_ALWAYS, world_bucket_family(bucket_id), 0xFF);
  glStencilOp(GL_KEEP, GL_KEEP, GL_REPLACE);
}

// Le bucket a deja pose le test, le masque et `GL_REPLACE` ; on ne change QUE la reference. Hors
// image sondee le stencil de preuve n'est pas arme : ne touche a rien.
void proof_stencil_family(int fam) {
  if (!g_probe_frame || fam <= 0 || fam >= kFamCount) {
    return;
  }
  glStencilFunc(GL_ALWAYS, fam, 0xFF);
}

namespace {

void ensure_probe(int w, int h, GLenum color_fmt) {
  if (g_probe_fbo && g_probe_w == w && g_probe_h == h && g_probe_fmt == color_fmt) {
    return;
  }
  if (g_probe_fbo) {
    glFinish();  // meme classe de danger que ensure_fbo : Adreno execute en differe
    glDeleteFramebuffers(1, &g_probe_fbo);
    glDeleteFramebuffers(1, &g_probe_res_fbo);
    glDeleteTextures(1, &g_probe_color);
    glDeleteTextures(1, &g_probe_ds);
    glDeleteTextures(1, &g_probe_res);
    g_probe_fbo = 0;
    g_probe_res_fbo = 0;
  }
  g_probe_w = w;
  g_probe_h = h;
  g_probe_fmt = color_fmt;
  // LE FORMAT COULEUR EST CELUI DE `render_fb`, PAS UN CHOIX. Un blit entre un attachement
  // flottant et un point fixe est une erreur GL en GLES ; l'essai 8 ne pouvait pas la
  // rencontrer, sa sonde ne tournait pas sur l'appareil.
  const bool is_float = (color_fmt != GL_RGBA8);
  auto mk = [](GLuint* tex, GLenum internal, GLenum fmt, GLenum type, int tw, int th) {
    glGenTextures(1, tex);
    glBindTexture(GL_TEXTURE_2D, *tex);
    glTexImage2D(GL_TEXTURE_2D, 0, (GLint)internal, tw, th, 0, fmt, type, nullptr);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
  };
  mk(&g_probe_color, color_fmt, GL_RGBA, is_float ? GL_HALF_FLOAT : GL_UNSIGNED_BYTE, w, h);
  mk(&g_probe_ds, GL_DEPTH24_STENCIL8, GL_DEPTH_STENCIL, GL_UNSIGNED_INT_24_8, w, h);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_COMPARE_MODE, GL_NONE);
  mk(&g_probe_res, GL_RGBA8, GL_RGBA, GL_UNSIGNED_BYTE, w, h);
  glGenFramebuffers(1, &g_probe_fbo);
  glBindFramebuffer(GL_FRAMEBUFFER, g_probe_fbo);
  glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, g_probe_color, 0);
  glFramebufferTexture2D(GL_FRAMEBUFFER, GL_DEPTH_STENCIL_ATTACHMENT, GL_TEXTURE_2D, g_probe_ds,
                         0);
  const bool ok_a = glCheckFramebufferStatus(GL_FRAMEBUFFER) == GL_FRAMEBUFFER_COMPLETE;
  glGenFramebuffers(1, &g_probe_res_fbo);
  glBindFramebuffer(GL_FRAMEBUFFER, g_probe_res_fbo);
  glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, g_probe_res, 0);
  glFramebufferTexture2D(GL_FRAMEBUFFER, GL_DEPTH_STENCIL_ATTACHMENT, GL_TEXTURE_2D, g_probe_ds,
                         0);
  const bool ok_b = glCheckFramebufferStatus(GL_FRAMEBUFFER) == GL_FRAMEBUFFER_COMPLETE;
  if (!ok_a || !ok_b) {
    lg::error("[lighting-ao-indirect] FBO de sonde incomplet ({}x{}, fmt=0x{:x}, a={} b={})", w, h,
              (unsigned)color_fmt, ok_a, ok_b);
    g_probe_state = -1;
  } else {
    g_probe_state = 1;
  }
}

}  // namespace

void proof_post_opaque(SharedRenderState* rs) {
  gl_query_census::Armed _ap("prepass-proof");
  if (rs) ao_tie_alpha_probe::finish_hut(rs->frame_idx);
  // Independent archive tick; does not schedule or alter the static probe population.
  static bool hut_scene_attempted = false;
  if (!hut_scene_attempted && rs && ao_contact_archive::requested() &&
      ao_static_probe::logic_frame() >= ao_contact_archive::kCaptureLogicFrame) {
    hut_scene_attempted = true;
    std::ostringstream metadata;
    const auto tick = ao_static_probe::logic_frame();
    const int w = rs->render_fb_w, h = rs->render_fb_h;
    metadata << "format=ao-hut-scene-depth-v1\nlogic_frame=" << tick
             << "\nrender_frame=" << rs->frame_idx << "\nwidth=" << w << "\nheight=" << h
             << "\norigin=lower-left\nencoding=ieee754-native-f32-from-d24\nreverse_z=1\n"
                "source=render_fb-post-opaque\n";
    ao_contact_readback::ExportState state;
    bool ok = state.errors.empty() && tick == ao_contact_archive::kCaptureLogicFrame && w > 0 && h > 0;
    GLuint texture = 0, fbo = 0;
    std::vector<float> values;
    if (ok) {
      glGenTextures(1, &texture); glBindTexture(GL_TEXTURE_2D, texture);
      glTexImage2D(GL_TEXTURE_2D, 0, GL_DEPTH24_STENCIL8, w, h, 0,
                   GL_DEPTH_STENCIL, GL_UNSIGNED_INT_24_8, nullptr);
      glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
      glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
      glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_COMPARE_MODE, GL_NONE);
      glGenFramebuffers(1, &fbo); glBindFramebuffer(GL_FRAMEBUFFER, fbo);
      glFramebufferTexture2D(GL_FRAMEBUFFER, GL_DEPTH_STENCIL_ATTACHMENT, GL_TEXTURE_2D, texture, 0);
      const GLenum none = GL_NONE; glDrawBuffers(1, &none); glReadBuffer(GL_NONE);
      ok = glCheckFramebufferStatus(GL_FRAMEBUFFER) == GL_FRAMEBUFFER_COMPLETE;
      glBindFramebuffer(GL_READ_FRAMEBUFFER, rs->render_fb);
      glDisable(GL_SCISSOR_TEST);
      glBlitFramebuffer(0, 0, w, h, 0, 0, w, h, GL_DEPTH_BUFFER_BIT, GL_NEAREST);
      ok = state.collect("scene-depth-copy-error") && ok;
      if (ok) ok = export_depth(texture, w, h, &values);
    }
    if (fbo) glDeleteFramebuffers(1, &fbo);
    if (texture) glDeleteTextures(1, &texture);
    ok = state.restore() && ok;
    for (const auto& error : state.errors)
      metadata << "error=" << error.reason << " gl=" << error.code << '\n';
    const auto& dir = ao_contact_archive::directory();
    const size_t bytes = values.size() * sizeof(float);
    if (ok) ok = !dir.empty() && ao_contact_archive::write_exclusive(
        dir + "/scene-depth.f32", values.data(), bytes);
    metadata << "bytes=" << bytes << "\nfnv1a64=" << ao_contact_archive::hash(values.data(), bytes)
             << "\nstatus=" << (ok ? "complete" : "failed") << '\n';
    const auto data = metadata.str();
    const bool written = !dir.empty() && ao_contact_archive::write_exclusive(
        dir + "/scene-depth.meta", data.data(), data.size());
    autoport_proof::publish_text("ao_hut_scene_depth_status", ok && written ? "complete" : "failed");
  }
  // Dedicated real-color frame, after the static probe's unchanged population.
  if (ao_tie_alpha_probe::color_frame() && rs) {
    GLint old_read, old_draw, old_tex, pack, alignment, row, skipx, skipy;
    glGetIntegerv(GL_READ_FRAMEBUFFER_BINDING, &old_read);
    glGetIntegerv(GL_DRAW_FRAMEBUFFER_BINDING, &old_draw);
    glGetIntegerv(GL_TEXTURE_BINDING_2D, &old_tex);
    glGetIntegerv(GL_PIXEL_PACK_BUFFER_BINDING, &pack);
    glGetIntegerv(GL_PACK_ALIGNMENT, &alignment);
    glGetIntegerv(GL_PACK_ROW_LENGTH, &row);
    glGetIntegerv(GL_PACK_SKIP_PIXELS, &skipx);
    glGetIntegerv(GL_PACK_SKIP_ROWS, &skipy);
    std::vector<float> scene_depth;
    const int w = rs->render_fb_w, h = rs->render_fb_h;
    // A preexisting error is reported as missing evidence, never cleared into a pass.
    const GLenum prior_error = glGetError();
    if (prior_error == GL_NO_ERROR && w > 0 && h > 0) {
      ensure_probe(w, h, rs->render_fb_color_format);
      glBindFramebuffer(GL_READ_FRAMEBUFFER, rs->render_fb);
      glBindFramebuffer(GL_DRAW_FRAMEBUFFER, g_probe_fbo);
      const GLboolean scissor = glIsEnabled(GL_SCISSOR_TEST);
      glDisable(GL_SCISSOR_TEST);
      glBlitFramebuffer(0, 0, w, h, 0, 0, w, h, GL_DEPTH_BUFFER_BIT, GL_NEAREST);
      if (scissor) glEnable(GL_SCISSOR_TEST);
      const GLenum copy_error = glGetError();
      glBindBuffer(GL_PIXEL_PACK_BUFFER, 0);
      glPixelStorei(GL_PACK_ROW_LENGTH, 0);
      glPixelStorei(GL_PACK_SKIP_PIXELS, 0); glPixelStorei(GL_PACK_SKIP_ROWS, 0);
      if (g_probe_state != 1 || copy_error != GL_NO_ERROR ||
          !export_depth(g_probe_ds, w, h, &scene_depth)) scene_depth.clear();
    }
    glBindTexture(GL_TEXTURE_2D, old_tex);
    glBindFramebuffer(GL_READ_FRAMEBUFFER, old_read);
    glBindFramebuffer(GL_DRAW_FRAMEBUFFER, old_draw);
    glBindBuffer(GL_PIXEL_PACK_BUFFER, pack);
    glPixelStorei(GL_PACK_ALIGNMENT, alignment); glPixelStorei(GL_PACK_ROW_LENGTH, row);
    glPixelStorei(GL_PACK_SKIP_PIXELS, skipx); glPixelStorei(GL_PACK_SKIP_ROWS, skipy);
    autoport_proof::publish("ao_tie_color_prior_gl_error", prior_error);
    ao_tie_alpha_probe::finish_color(rs->render_fb, rs->render_fb_color_format, scene_depth);
  }
  if (!g_probe_frame) {
    return;
  }
  // Fin du marquage : le stencil est rendu a zero et eteint pour les buckets d'apres (SHADOW=47
  // compte sur un stencil nul). Le clear honore le scissor, on le coupe le temps du clear.
  auto clear_stencil = [] {
    const GLboolean had_scissor = glIsEnabled(GL_SCISSOR_TEST);
    if (had_scissor) {
      glDisable(GL_SCISSOR_TEST);
    }
    glStencilMask(0xFF);
    glClear(GL_STENCIL_BUFFER_BIT);
    glDisable(GL_STENCIL_TEST);
    if (had_scissor) {
      glEnable(GL_SCISSOR_TEST);
    }
  };
  const int w = rs ? rs->render_fb_w : 0;
  const int h = rs ? rs->render_fb_h : 0;
  if (!rs || w <= 0 || h <= 0 || (size_t)w * h > 3840u * 2160u) {
    clear_stencil();
    return;
  }
  ensure_probe(w, h, rs->render_fb_color_format);
  if (g_probe_state != 1) {
    autoport_proof::publish("ao_probe_unsupported", 1);
    clear_stencil();
    return;
  }
  while (glGetError() != GL_NO_ERROR) {
  }
  GLint prev_read = 0, prev_draw = 0;
  glGetIntegerv(GL_READ_FRAMEBUFFER_BINDING, &prev_read);
  glGetIntegerv(GL_DRAW_FRAMEBUFFER_BINDING, &prev_draw);
  // Un blit a taille identique : copie simple ou resolution MSAA, et il emporte le stencil
  // (memes formats DEPTH24_STENCIL8 des deux cotes).
  glBindFramebuffer(GL_READ_FRAMEBUFFER, rs->render_fb);
  glBindFramebuffer(GL_DRAW_FRAMEBUFFER, g_probe_fbo);
  GLbitfield blit_mask = GL_COLOR_BUFFER_BIT | GL_STENCIL_BUFFER_BIT;
  if (g_geom_frame) {
    blit_mask |= GL_DEPTH_BUFFER_BIT;  // (c)/(g)/(i) : la profondeur de ce que la scene a DESSINE
  }
  glBlitFramebuffer(0, 0, w, h, 0, 0, w, h, blit_mask, GL_NEAREST);
  // ── LA RESOLUTION PORTABLE : LE STENCIL SE TESTE, IL NE SE RELIT PAS ────────────────────
  // GLES 3.2 n'a pas `glReadPixels(GL_STENCIL_INDEX)` — c'est ce qui a tenu les termes 1 et 3
  // hors de l'appareil pendant huit essais. Mais il sait TESTER le stencil. Trois quads plein
  // ecran, `GL_EQUAL` contre 1, 2 puis 3, ecrivent la FAMILLE dans l'alpha d'un RGBA8 et y
  // recopient au passage les drapeaux de shade(), seuilles a 0/255. Le denominateur ne change
  // pas d'un pixel : un alpha nul est exactement un stencil nul.
  // ELLE REND L'ETAT EXACTEMENT COMME ELLE L'A TROUVE. Avant l'essai 9 cette fonction ne
  // dessinait rien : elle blittait et relisait. Maintenant qu'elle DESSINE, tout ce qu'elle pose
  // — viewport, masque de profondeur, test de profondeur, melange, facettes — repartirait avec
  // elle vers les buckets > 30, et le defaut ne se verrait que sur l'appareil.
  GLint prev_program_r = 0, prev_vao_r = 0, prev_vp_r[4] = {0, 0, 0, 0}, prev_tex0_r = 0;
  GLboolean prev_depth_mask_r = GL_TRUE;
  GLboolean prev_color_mask_r[4] = {GL_TRUE, GL_TRUE, GL_TRUE, GL_TRUE};
  glGetIntegerv(GL_CURRENT_PROGRAM, &prev_program_r);
  glGetIntegerv(GL_VERTEX_ARRAY_BINDING, &prev_vao_r);
  glGetIntegerv(GL_VIEWPORT, prev_vp_r);
  glGetBooleanv(GL_DEPTH_WRITEMASK, &prev_depth_mask_r);
  glGetBooleanv(GL_COLOR_WRITEMASK, prev_color_mask_r);
  glActiveTexture(GL_TEXTURE0);
  glGetIntegerv(GL_TEXTURE_BINDING_2D, &prev_tex0_r);
  const GLboolean prev_depth_test_r = glIsEnabled(GL_DEPTH_TEST);
  const GLboolean prev_blend_r = glIsEnabled(GL_BLEND);
  const GLboolean prev_cull_r = glIsEnabled(GL_CULL_FACE);
  ensure_quad();
  (*g_shaders)[ShaderId::AO_PROBE].activate();
  const GLuint pid = (GLuint)(*g_shaders)[ShaderId::AO_PROBE].id();
  glBindFramebuffer(GL_FRAMEBUFFER, g_probe_res_fbo);
  glViewport(0, 0, w, h);
  const GLboolean had_scissor_r = glIsEnabled(GL_SCISSOR_TEST);
  glDisable(GL_SCISSOR_TEST);
  glDisable(GL_BLEND);
  glDisable(GL_CULL_FACE);
  glDisable(GL_DEPTH_TEST);
  glDepthMask(GL_FALSE);
  glColorMask(GL_TRUE, GL_TRUE, GL_TRUE, GL_TRUE);
  GLfloat prev_clear_r[4] = {0.f, 0.f, 0.f, 0.f};
  glGetFloatv(GL_COLOR_CLEAR_VALUE, prev_clear_r);
  glClearColor(0.f, 0.f, 0.f, 0.f);
  glClear(GL_COLOR_BUFFER_BIT);
  glClearColor(prev_clear_r[0], prev_clear_r[1], prev_clear_r[2], prev_clear_r[3]);
  glEnable(GL_STENCIL_TEST);
  glStencilMask(0x00);  // la sonde LIT le stencil, elle ne l'ecrit jamais
  glStencilOp(GL_KEEP, GL_KEEP, GL_KEEP);
  glActiveTexture(GL_TEXTURE0);
  glBindTexture(GL_TEXTURE_2D, g_white_tex);
  glActiveTexture(GL_TEXTURE1);
  glBindTexture(GL_TEXTURE_2D, g_probe_color);
  glUniform1i(glu::loc(pid, "u_depth"), 0);
  glUniform1i(glu::loc(pid, "u_src"), 1);
  glUniform1i(glu::loc(pid, "u_mode"), 0);
  glBindVertexArray(g_quad_vao);
  for (int f = 1; f < kFamCount; f++) {
    glStencilFunc(GL_EQUAL, f, 0xFF);
    glUniform1f(glu::loc(pid, "u_fam"), (float)f);
    glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
    soft_draw_census::record_arrays("postprocess", 4, GL_TRIANGLE_STRIP);
  }
  glBindVertexArray(0);
  glActiveTexture(GL_TEXTURE1);
  glBindTexture(GL_TEXTURE_2D, 0);
  glActiveTexture(GL_TEXTURE0);
  glBindTexture(GL_TEXTURE_2D, (GLuint)prev_tex0_r);
  glStencilMask(0xFF);
  if (had_scissor_r) {
    glEnable(GL_SCISSOR_TEST);
  }
  // ── ET ON REND TOUT ────────────────────────────────────────────────────────────────────
  glUseProgram((GLuint)prev_program_r);
  glBindVertexArray((GLuint)prev_vao_r);
  glViewport(prev_vp_r[0], prev_vp_r[1], prev_vp_r[2], prev_vp_r[3]);
  glDepthMask(prev_depth_mask_r);
  glColorMask(prev_color_mask_r[0], prev_color_mask_r[1], prev_color_mask_r[2],
              prev_color_mask_r[3]);
  if (prev_depth_test_r) {
    glEnable(GL_DEPTH_TEST);
  }
  if (prev_blend_r) {
    glEnable(GL_BLEND);
  }
  if (prev_cull_r) {
    glEnable(GL_CULL_FACE);
  }

  std::vector<uint8_t> px((size_t)w * h * 4);
  std::vector<float> sd;
  glBindFramebuffer(GL_READ_FRAMEBUFFER, g_probe_res_fbo);
  glReadBuffer(GL_COLOR_ATTACHMENT0);
  glPixelStorei(GL_PACK_ALIGNMENT, 1);
  glReadPixels(0, 0, w, h, GL_RGBA, GL_UNSIGNED_BYTE, px.data());
  const GLenum err = glGetError();
  glBindFramebuffer(GL_READ_FRAMEBUFFER, (GLuint)prev_read);
  glBindFramebuffer(GL_DRAW_FRAMEBUFFER, (GLuint)prev_draw);
  // La profondeur de la SCENE par le meme re-encodage 24 bits : `g_probe_ds` est une texture
  // depuis l'essai 9, et `export_depth` sauve et rend l'etat GL qu'elle touche.
  if (err == GL_NO_ERROR && g_geom_frame) {
    if (!export_depth(g_probe_ds, w, h, &sd)) {
      sd.clear();
    }
  }
  if (err != GL_NO_ERROR) {
    lg::error("[lighting-ao-indirect] relecture de la sonde refusee (gl=0x{:x})", (unsigned)err);
    g_probe_state = -1;
    autoport_proof::publish("ao_probe_unsupported", 1);
    clear_stencil();
    return;
  }
  if (g_geom_frame) {
    ao_tie_alpha_probe::finish_frame(g_pre_depth, sd, px);
  }
  uint64_t hits = 0, leak = 0, excl = 0, marked = 0, unmarked = 0;
  for (size_t i = 0; i < (size_t)w * h; i++) {
    // Le stencil porte la FAMILLE depuis le 2026-09-14 : tout ce qui n'est pas 0 est un pixel
    // monde. Le denominateur de la porte (`ao_probe_px`) est donc EXACTEMENT le meme qu'avant,
    // seul son decoupage est neuf.
    if (px[i * 4 + 3] == 0 || px[i * 4 + 3] >= (uint8_t)kFamCount) {
      unmarked++;
      continue;
    }
    marked++;
    // Drapeaux ecrits par shade() en mode preuve : R = fuite sur le direct, G = l'indirect a
    // recu l'AO, B = chemin exclu de la porte (B/C/E : son indirect n'est pas `base`).
    if (px[i * 4 + 2] >= 128) {
      excl++;
    } else if (px[i * 4] >= 128) {
      leak++;
    }
    if (px[i * 4 + 1] >= 128) {
      hits++;
    }
  }
  // ── (c)/(g)/(i) LA PREPASSE CONTRE CE QUI EST DESSINE ──────────────────────────────────────
  // Verdict (c) de l'owner : « publier ce qui est mesure AU POINT DE DESSIN du brin d'herbe, pas
  // a l'entree de l'estimateur ». `st[i] == 1` designe exactement un pixel dont la couleur vient
  // d'un bucket monde ; `sd[i]` est la profondeur que ce pixel PORTE. Si la prepasse n'y a pas la
  // meme, l'AO de ce pixel a ete calculee sur une AUTRE geometrie — un quad reste en place
  // pendant que la plante bouge (verdict i), un occluder que l'image ne dessine pas (c/g), ou
  // rien du tout. Convention PS2 inversee : profondeur PLUS GRANDE = PLUS PRES de la camera.
  // Les seuils montent en puissances de quatre a partir de 4 quanta de 24 bits, parce qu'un
  // seuil unique choisi apres coup est un seuil choisi pour son resultat.
  if (g_geom_frame && sd.size() >= (size_t)w * h && g_pre_depth.size() >= (size_t)w * h &&
      g_pre_depth_legacy.size() >= (size_t)w * h) {
    const float q = 1.0f / 16777215.0f;
    const float tol[4] = {4.f * q, 64.f * q, 1024.f * q, 16384.f * q};
    for (size_t i = 0; i < (size_t)w * h; i++) {
      const float pl = g_pre_depth[i];
      const float pg = g_pre_depth_legacy[i];
      const float moved = std::fabs(pl - pg);
      if (moved > tol[0]) {
        g_sway_gap_px++;
      }
      const float sz_void = sd[i];
      // (A2) LE FANTOME AU-DESSUS DU VIDE, compte AVANT le filtre de famille et AVANT le
      // `continue` sur `sz <= 1e-6f` qui rendait la mesure aveugle. Ce pixel-la n'appartient a
      // aucun bucket monde et la scene n'y a aucune profondeur : c'est du CIEL. Si la prepasse y
      // a ecrit de la geometrie, l'estimateur d'AO y voit un occluder plein et pose une ombre
      // « dans le vide » — le mot de l'owner. Aucune relecture GL de plus : les deux tampons de
      // profondeur et le stencil sont deja en main.
      if (sz_void <= 1e-6f) {
        g_phantom_void_pop_px++;
        if (pl > 1e-6f) {
          g_phantom_void_px++;
        }
        if (pg > 1e-6f) {
          g_phantom_void_legacy_px++;
        }
      }
      // (terme 3) LE TEMOIN de l'instantane sans decoupe, sur TOUT l'ecran et AVANT le filtre
      // de famille : les pixels que le bras livre n'a pas et que le bras sans decoupe porte.
      if (g_pre_depth_nocut.size() >= (size_t)w * h && pl <= 1e-6f &&
          g_pre_depth_nocut[i] > 1e-6f) {
        g_geom_nocut_extra_px++;
      }
      const int fam =
          (px[i * 4 + 3] > 0 && px[i * 4 + 3] < (uint8_t)kFamCount) ? (int)px[i * 4 + 3] : 0;
      if (fam == 0) {
        continue;
      }
      const float sz = sd[i];
      if (sz <= 1e-6f) {
        continue;  // pixel monde sans profondeur de scene (draw sans z-write) : rien a comparer
      }
      g_geom_cover++;
      g_fam_cover[fam]++;
      // ── LE TAUX DE BASE DU TEST DE SILHOUETTE ───────────────────────────────────────────
      // Sans lui, « 33 pixels de `gap64` sur 33 sont au bord d'une marche » ne prouve rien :
      // sur du feuillage a decoupe, presque TOUT pixel touche une marche, et le test serait
      // vrai par construction. On mesure donc le MEME test sur la population couverte, un
      // pixel sur `kEdgeProbeStride` — la borne du cout, publiee avec son compte d'echantillons
      // pour qu'un lecteur puisse la contredire. Un taux de base proche de 1000 rend la
      // repartition edge/inner MUETTE ; un taux bas la rend concluante.
      if ((i % kEdgeProbeStride) == 0) {
        g_fam_edge_probe_pop[fam]++;
        const size_t exi = i % (size_t)w, eyi = i / (size_t)w;
        bool e_step = false;
        for (int dy = -1; dy <= 1 && !e_step; dy++) {
          for (int dx = -1; dx <= 1; dx++) {
            if (dx == 0 && dy == 0) {
              continue;
            }
            const long nx = (long)exi + dx, ny = (long)eyi + dy;
            if (nx < 0 || ny < 0 || nx >= (long)w || ny >= (long)h) {
              continue;
            }
            const float nz = sd[(size_t)ny * (size_t)w + (size_t)nx];
            if (nz > 1e-6f && fabsf(nz - sz) > tol[1]) {
              e_step = true;
              break;
            }
          }
        }
        if (e_step) {
          g_fam_edge_probe_hit[fam]++;
        }
      }
      if (moved > tol[0]) {
        g_sway_gap_world_px++;
      }
      if (pl <= 1e-6f) {
        g_geom_absent++;
        g_fam_absent[fam]++;
        if (g_pre_depth_nocut.size() >= (size_t)w * h && g_pre_depth_nocut[i] > 1e-6f) {
          g_fam_absent_nocut[fam]++;
          // ... et de QUELLE geometrie il s'agit : la MEME que celle que l'image dessine, ou une
          // autre. Meme tolerance que `_gap64` (64 quanta de 24 bits) : un seuil deja en usage
          // dans cette boucle, pas un seuil choisi apres coup pour son resultat.
          const float dn = g_pre_depth_nocut[i] - sz;
          if ((dn < 0.f ? -dn : dn) <= tol[1]) {
            g_fam_absent_nocut_match[fam]++;
          } else {
            g_fam_absent_nocut_off[fam]++;
          }
        }
        // ── CE QU'EST UN PIXEL « ABSENT », SEPARE EN DEUX ─────────────────────────────────
        // Deux causes possibles produisent le MEME compte, et elles n'appellent pas le meme
        // correctif : soit la prepasse ne dessine PAS cette classe de geometrie (le pixel est
        // au MILIEU d'un trou : aucun de ses huit voisins n'a de profondeur de prepasse), soit
        // les deux passes ne couvrent pas exactement le meme pixel sur une SILHOUETTE (au moins
        // un voisin en a une). Le premier se repare en dessinant ce qui manque ; le second est
        // un desaccord de rasterisation d'un pixel, et aucun correctif de dessin ne le retire.
        // Trois essais ont vise la premiere cause sans jamais avoir separe les deux.
        const size_t xi = i % (size_t)w, yi = i / (size_t)w;
        bool nbr_has_depth = false;
        for (int dy = -1; dy <= 1 && !nbr_has_depth; dy++) {
          for (int dx = -1; dx <= 1; dx++) {
            if (dx == 0 && dy == 0) {
              continue;
            }
            const long nx = (long)xi + dx, ny = (long)yi + dy;
            if (nx < 0 || ny < 0 || nx >= (long)w || ny >= (long)h) {
              continue;
            }
            if (g_pre_depth[(size_t)ny * (size_t)w + (size_t)nx] > 1e-6f) {
              nbr_has_depth = true;
              break;
            }
          }
        }
        if (nbr_has_depth) {
          g_fam_absent_edge[fam]++;
        } else {
          g_fam_absent_inner[fam]++;
        }
        if (pl <= 0.f) {
          g_fam_absent_zero[fam]++;
        } else {
          g_fam_absent_farq[fam]++;
        }
      } else {
        const float d = pl - sz;
        const float ad = d < 0.f ? -d : d;
        for (int k = 0; k < 4; k++) {
          if (ad > tol[k]) {
            g_geom_gap[k]++;
            // (1) la MEME echelle, mais par famille.
            g_fam_gap_hist[fam][k]++;
          }
        }
        // (4) le pixel le plus ecarte de la famille, avec de quoi aller le regarder.
        {
          const uint64_t adq = (uint64_t)(ad * 16777215.f);
          if (adq > g_fam_worst_q[fam]) {
            g_fam_worst_q[fam] = adq;
            g_fam_worst_x[fam] = (uint64_t)(i % (size_t)w);
            g_fam_worst_y[fam] = (uint64_t)(i / (size_t)w);
            g_fam_worst_pre_q[fam] = (uint64_t)(pl * 16777215.f);
            g_fam_worst_scene_q[fam] = (uint64_t)(sz * 16777215.f);
            g_fam_worst_frame[fam] = g_geom_frames;
          }
        }
        if (ad > tol[1]) {
          g_fam_gap64[fam]++;
          // (2) le SIGNE : prepasse DEVANT (occluder que l'image ne dessine pas) ou DERRIERE
          // (surface manquante, ou sommet deplace autrement).
          if (d > 0.f) {
            g_fam_gap64_near[fam]++;
          } else {
            g_fam_gap64_far[fam]++;
          }
          // (3) SILHOUETTE ou non, lu sur la profondeur de SCENE seule : un voisin compte comme
          // marche s'il porte une profondeur et s'ecarte de `sz` de plus de tol[1]. `inner` non
          // nul REFUTE l'hypothese « desaccord de rasterisation d'un pixel sur une silhouette ».
          const size_t gxi = i % (size_t)w, gyi = i / (size_t)w;
          bool nbr_is_step = false;
          for (int dy = -1; dy <= 1 && !nbr_is_step; dy++) {
            for (int dx = -1; dx <= 1; dx++) {
              if (dx == 0 && dy == 0) {
                continue;
              }
              const long nx = (long)gxi + dx, ny = (long)gyi + dy;
              if (nx < 0 || ny < 0 || nx >= (long)w || ny >= (long)h) {
                continue;
              }
              const float nz = sd[(size_t)ny * (size_t)w + (size_t)nx];
              if (nz > 1e-6f && fabsf(nz - sz) > tol[1]) {
                nbr_is_step = true;
                break;
              }
            }
          }
          if (nbr_is_step) {
            g_fam_gap64_edge[fam]++;
          } else {
            g_fam_gap64_inner[fam]++;
          }
        }
        if (d > tol[0]) {
          g_geom_near++;
        } else if (d < -tol[0]) {
          g_geom_far++;
        }
      }
      if (pg <= 1e-6f) {
        g_geom_absent_legacy++;
      } else {
        const float d = pg - sz;
        const float ad = d < 0.f ? -d : d;
        for (int k = 0; k < 4; k++) {
          if (ad > tol[k]) {
            g_geom_gap_legacy[k]++;
          }
        }
        if (ad > tol[1]) {
          g_fam_gap64_legacy[fam]++;
        }
        if (d > tol[0]) {
          g_geom_near_legacy++;
        } else if (d < -tol[0]) {
          g_geom_far_legacy++;
        }
      }
    }
    g_geom_frames++;
    g_geom_state = 1;
    g_phantom_void_frames++;  // (A2) le compte d'images ou l'instrument a tourne
  }
  g_probe_frames++;
  g_probe_px += marked;
  g_unmarked_px += unmarked;
  g_leak_px += leak;
  g_excluded_px += excl;
  g_hit_px += hits;
  autoport_proof::note_hit_for(kItemId, hits);
  // Le format couleur effectivement blitte, et le fait que la sonde a tourne ICI. Un lecteur qui
  // voit `ao_probe_unsupported=1` doit pouvoir dire si c'est le FBO ou le format qui a refuse.
  autoport_proof::publish("ao_probe_color_fmt", (uint64_t)g_probe_fmt);
  // Commit coverage only after the color/direct readback above succeeded and
  // both alpha-classification readbacks in this same phase had nonempty populations.
  if (ao_static_probe::active() && g_static_probe.phase == 3 &&
      g_static_probe.state >= 0 && g_static_probe.state < 6 && marked > 0 &&
      g_static_acquisition_alpha_ok && g_static_acquisition_witness_ok &&
      foliage_wind::enabled()) {
    g_static_acquisition_mask |= 1u << g_static_probe.state;
  }
  publish_all();
  clear_stencil();
}

}  // namespace prepass
